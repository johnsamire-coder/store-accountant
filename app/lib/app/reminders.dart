// التذكيرات: 10 الصبح التقرير اليومي، الخميس الأسبوعي + تأكيد خزنة المالك،
// مواعيد الشيكات، مواعيد المصروفات الثابتة، والمرتبات يوم 25.
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/codecs.dart';
import '../engine/customers.dart';
import '../engine/excel.dart';
import '../engine/format.dart';
import 'state.dart';

enum Repeat { none, daily, weekly, monthly }

class Reminder {
  final int id;
  final String title, body;
  final DateTime when; // أول مرة
  final Repeat repeat;
  const Reminder(this.id, this.title, this.body, this.when, this.repeat);
  @override
  String toString() => '$id $title @ $when ($repeat)';
}

DateTime _next(DateTime now, int hour, {int? weekday, int? day}) {
  var d = DateTime(now.year, now.month, day ?? now.day, hour);
  if (weekday != null) {
    while (d.weekday != weekday || !d.isAfter(now)) {
      d = DateTime(d.year, d.month, d.day + 1, hour);
    }
    return d;
  }
  if (!d.isAfter(now)) d = day != null ? DateTime(now.year, now.month + 1, day, hour) : DateTime(now.year, now.month, now.day + 1, hour);
  return d;
}

/// الخطة كلها (من غير ما نلمس الموبايل) — علشان تتختبر
List<Reminder> reminderPlan(AppState s) {
  final now = s.now;
  final out = <Reminder>[
    Reminder(1, 'التقرير اليومي', 'سجّل حركات امبارح من الجروب وابعت التقرير اليومي للمالك', _next(now, 10), Repeat.daily),
    Reminder(2, 'متابعة الخميس مع المالك',
        'اسأله: جالك كام الأسبوع ده؟ دفعت كام ولمين (الوسيط، شركة الشحن، فيني، المستخلص)؟ + ابعت التقرير الأسبوعي وأكّد رصيد الخزنة',
        _next(now, 10, weekday: DateTime.thursday), Repeat.weekly),
    Reminder(3, 'المرتبات', 'كشف الحضور بيوصل النهارده (25) — جهّز كشف المرتبات والسلف', _next(now, 9, day: 25), Repeat.monthly),
    Reminder(4, 'مطابقة أول الشهر', 'طابق مع المالك رصيده عند شركة الشحن وفيني والوسيط، وراجع المحافظ، وطلّع التقرير الشهري',
        _next(now, 10, day: 1), Repeat.monthly),
  ];
  // المصروفات الثابتة: كل بند ليه ميعاد في الشهر
  final seen = <String>{};
  var i = 0;
  for (final f in s.values(fixedExpenseCodec)) {
    final key = '${f.name}|${f.branch}|${f.dueDay}';
    if (!seen.add(key) || f.dueDay < 1 || f.dueDay > 28) continue;
    out.add(Reminder(100 + i++, 'مصروف ثابت مستحق', '${f.name} (${f.branch}) — المتوقع ${fmtNum(f.expected)}', _next(now, 9, day: f.dueDay), Repeat.monthly));
  }
  // الشيكات اللي في الخزنة: قبلها بيومين ويوم الاستحقاق
  var j = 0;
  for (final c in s.values(collectionCodec)) {
    if (!c.isCheque || c.chequeState != ChequeState.inSafe || c.dueDate == null) continue;
    final due = dateOnly(c.dueDate!);
    for (final (k, d) in [(0, due.subtract(const Duration(days: 2))), (1, due)]) {
      final at = DateTime(d.year, d.month, d.day, 9);
      if (at.isAfter(now)) {
        out.add(Reminder(1000 + j * 2 + k, k == 0 ? 'شيك مستحق بعد يومين' : 'شيك مستحق النهارده',
            '${c.customer} — ${fmtNum(c.amount)} — ${c.bank} ${c.chequeNo} (${fmtDate(due)})', at, Repeat.none));
      }
    }
    j++;
  }
  return out;
}

class ReminderService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  String _lastPlan = '';

  Future<void> init() async {
    if (_ready || kIsWeb) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Africa/Cairo'));
    await _plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    _ready = true;
  }

  /// بيرتب التذكيرات من الأول (بس لو الخطة اتغيرت)
  Future<void> sync(AppState s) async {
    if (kIsWeb) return;
    final enabled = s.setting<bool>(K.reminders) ?? true;
    final plan = enabled ? reminderPlan(s) : <Reminder>[];
    final sig = plan.map((r) => '${r.id}|${r.when.toIso8601String()}|${r.body}').join(';');
    if (sig == _lastPlan) return;
    _lastPlan = sig;
    await init();
    await _plugin.cancelAll();
    const details = NotificationDetails(
      android: AndroidNotificationDetails('reminders', 'التذكيرات', channelDescription: 'تذكيرات التقارير والشيكات والمصروفات',
          importance: Importance.high, priority: Priority.high),
    );
    for (final r in plan) {
      await _plugin.zonedSchedule(
        id: r.id,
        title: r.title,
        body: r.body,
        scheduledDate: tz.TZDateTime(tz.local, r.when.year, r.when.month, r.when.day, r.when.hour, r.when.minute),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: switch (r.repeat) {
          Repeat.daily => DateTimeComponents.time,
          Repeat.weekly => DateTimeComponents.dayOfWeekAndTime,
          Repeat.monthly => DateTimeComponents.dayOfMonthAndTime,
          Repeat.none => null,
        },
      );
    }
  }
}
