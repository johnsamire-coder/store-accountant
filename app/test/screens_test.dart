// بنستخدم الشاشات زي ما جون هيستخدمها: ندوس ونكتب ونحفظ ونشوف النتيجة.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_accountant/app/state.dart';
import 'package:store_accountant/data/codecs.dart';
import 'package:store_accountant/main.dart';
import 'package:store_accountant/ui/home.dart';
import 'package:store_accountant/ui/lock.dart';
import 'package:store_accountant/ui/paste.dart';
import 'package:store_accountant/ui/reports.dart';

import 'seed.dart';

Future<AppState> pumpApp(WidgetTester t, {Widget? home, bool seed = true}) async {
  late AppState s;
  await t.runAsync(() async => s = await makeState(seed: seed));
  t.view.physicalSize = const Size(1080, 2340);
  t.view.devicePixelRatio = 2.6;
  addTearDown(t.view.reset);
  await t.pumpWidget(HesabatyApp(state: s, home: home ?? const HomeShell()));
  await t.pumpAndSettle();
  return s;
}

/// ينزل في الشاشة لحد ما الكلام يبان (زي ما الإيد بتعمل)
Future<Finder> seek(WidgetTester t, Finder f) async {
  for (var dir in [-1.0, 1.0]) {
    for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
      final sc = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
      if (sc.evaluate().isEmpty) break;
      await t.drag(sc.first, Offset(0, 350 * dir), warnIfMissed: false);
      await t.pumpAndSettle();
    }
  }
  return f;
}

Future<void> see(WidgetTester t, String text, {bool contains = false}) async {
  final f = await seek(t, contains ? find.textContaining(text) : find.text(text));
  expect(f, findsWidgets, reason: text);
}

Future<void> tapText(WidgetTester t, String text) async {
  final f = await seek(t, find.text(text));
  await t.ensureVisible(f.first);
  await t.pumpAndSettle();
  await t.tap(f.first);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('الرئيسية: التنبيهات الأول والأرقام', (t) async {
    await pumpApp(t);
    expect(find.text('حساباتي'), findsOneWidget);
    expect(find.textContaining('تنبيهات النهارده ('), findsOneWidget);
    expect(find.text('عجز في توريد النقدية'), findsOneWidget);
    expect(find.text('عملاء متجاوزين الحد أو متأخرين'), findsOneWidget);
    await see(t, 'تحويلات مخزنية لسه ما اتستلمتش');
    await t.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await t.pumpAndSettle();
    // التنبيه بيفتح السجل
    await tapText(t, 'القاهرة — 2026-11-02');
    expect(find.text('عجز'), findsWidgets);
    expect(find.text('-100'), findsWidgets);
  });

  testWidgets('توريد جديد في 3 دوسات + الفرع بيتفتكر', (t) async {
    final s = await pumpApp(t);
    final before = s.values(cashHandoverCodec).length;
    await tapText(t, 'إضافة سريعة'); // 1
    await tapText(t, 'توريد نقدية'); // 2
    await tapText(t, 'بورسعيد');
    final fields = find.byType(TextField);
    await t.enterText(fields.at(1), '20000'); // مبيعات نقدي
    await t.enterText(fields.at(2), '5000'); // تحصيلات
    await t.enterText(fields.at(3), '500'); // نثريات
    await t.enterText(fields.at(4), '24,500'); // المورّد
    await t.pumpAndSettle();
    expect(find.text('مطابق'), findsOneWidget); // بيتحسب وانت بتكتب
    await tapText(t, 'حفظ'); // 3
    final l = s.values(cashHandoverCodec);
    expect(l.length, before + 1);
    expect(l.last.branch, 'بورسعيد');
    expect(l.last.date, s.today);
    expect(l.last.expected, 24500);
    expect(s.lastBranch, 'بورسعيد');
  });

  testWidgets('لصق من الواتساب ← حفظ', (t) async {
    late AppState s;
    await t.runAsync(() async => s = await makeState());
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    await t.pumpWidget(HesabatyApp(
        state: s,
        home: const PasteScreen(
            initialText: 'صرف | التاريخ: 2026-11-03 | المبلغ: 15,000 جنيه | الغرض: (مستخلص)\n'
                'دولار | التاريخ: 2026-11-03 | دفعت: 510,000 جنيه | اشتريت: 10,000 دولار | المورد: Guangzhou Textile Co. | الشحنة: ش-2026-02\n'
                'صرف | التاريخ: 2026-11-03 | المبلغ: 500,000 جنيه | الغرض: (دولار شحنة رقم ش-2026-02)')));
    await t.pumpAndSettle();
    await tapText(t, 'اقرا الرسايل');
    expect(find.textContaining('سداد مستخلص — 15,000 جنيه — 2026-11-03'), findsOneWidget);
    await see(t, 'الحركة دي متسجلة قبل كده', contains: true); // ال 500 ألف متسجلة في المثال
    final safeBefore = s.values(safeMovementCodec).length, usdBefore = s.values(usdTransferCodec).length;
    await tapText(t, 'احفظ الـ 2 اللي سليمين');
    expect(s.values(safeMovementCodec).length, safeBefore + 1);
    expect(s.values(usdTransferCodec).length, usdBefore + 1);
    expect(s.values(usdTransferCodec).last.rate, 51);
    expect(s.values(safeMovementCodec).last.status, 'مستند ناقص');
  });

  testWidgets('التقرير اليومي ليوم 11-01 = رسالة الإكسل', (t) async {
    await pumpApp(t, home: const DailyReportScreen());
    await t.tap(find.byIcon(Icons.chevron_right).first); // يوم قبل امبارح = 11-01
    await t.pumpAndSettle();
    await see(t, 'تقرير يوم 2026-11-01', contains: true);
    await see(t, 'صافي المبيعات: 90,500 (القاهرة 60,500 / بورسعيد 30,000)', contains: true);
    await see(t, 'عدد التنبيهات: 3 (التفاصيل في التقرير)', contains: true);
    await t.drag(find.byType(Scrollable).first, const Offset(0, 5000));
    await t.pumpAndSettle();
    // الدوس على "اتورد فعلاً" بيفتح محاضر التوريد اللي وراه
    final cell = await seek(t, find.text('40,050'));
    await t.ensureVisible(cell.last);
    await t.tap(cell.last);
    await t.pumpAndSettle();
    expect(find.text('توريد 2026-11-01'), findsOneWidget);
    expect(find.text('القاهرة — 2026-11-01'), findsOneWidget);
  });

  testWidgets('الأسبوعي: رصيد الخزنة 1,043,850 ورسالة الخميس', (t) async {
    await pumpApp(t, home: const WeeklyReportScreen());
    // النهارده التلات 11-03 → الأسبوع من الحد 11-01 للسبت 11-07
    await see(t, 'التقرير الأسبوعي من 2026-11-01 لـ 2026-11-07', contains: true);
    expect(find.textContaining('رصيد خزنتك حسب الحسابات: 1,043,850 — ده صح؟'), findsOneWidget);
    expect(find.textContaining('صافي المبيعات: 1,470,700 (+13% عن الأسبوع اللي فات)'), findsOneWidget);
  });

  testWidgets('الشهري: صافي الربح 710,750', (t) async {
    await pumpApp(t, home: const MonthlyReportScreen());
    await t.tap(find.byIcon(Icons.chevron_left).first); // نوفمبر
    await t.pumpAndSettle();
    await see(t, '710,750');
    await see(t, 'صافي الربح: 710,750', contains: true);
  });

  testWidgets('الشحنة: تكلفة القطعة 298.04 وسعر البيع 403', (t) async {
    await pumpApp(t);
    await tapText(t, 'البضاعة');
    await tapText(t, 'الشحنات والتكلفة الواصلة');
    await tapText(t, 'ش-2026-01');
    await see(t, '298.04');
    await see(t, '403');
    await see(t, 'مطابق');
  });

  testWidgets('كشف حساب العميل + المصادقة', (t) async {
    await pumpApp(t);
    await tapText(t, 'الناس');
    await tapText(t, 'كشوف حساب العملاء');
    await tapText(t, 'محلات الأمل');
    await see(t, '125,000');
    await see(t, 'بأن رصيدي المستحق للمحل في 2026-11-02 هو 125,000 جنيه', contains: true);
  });

  testWidgets('المرتبات: السلفة بتتخصم لوحدها', (t) async {
    await pumpApp(t);
    await tapText(t, 'الناس');
    await tapText(t, 'كشف المرتبات');
    await see(t, 'ع-02 — محمد علي');
    await see(t, '6,500');
  });

  testWidgets('القفل: أول مرة يختار رقم سري، وبعدين لازم يكتبه', (t) async {
    late AppState s;
    await t.runAsync(() async => s = await makeState(seed: false));
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.6;
    addTearDown(t.view.reset);
    await t.pumpWidget(HesabatyApp(state: s, home: const LockGate(child: Text('جوه'))));
    await t.pumpAndSettle();
    expect(find.text('اختار رقم سري من 4 أرقام'), findsOneWidget);
    for (final k in '24682468'.split('')) {
      await t.tap(find.text(k));
      await t.pumpAndSettle();
    }
    expect(find.text('جوه'), findsOneWidget);
    expect(s.setting<String>(K.pinHash), isNotNull);
    expect(s.setting<String>(K.pinHash), isNot(contains('2468')));
    expect(checkPin(s, '2468'), true);
    expect(checkPin(s, '1111'), false);
    // القفل
    await t.pumpWidget(HesabatyApp(state: s, home: const LockGate(key: ValueKey(2), child: Text('جوه'))));
    await t.pumpAndSettle();
    expect(find.text('اكتب الرقم السري'), findsOneWidget);
    for (final k in '1111'.split('')) {
      await t.tap(find.text(k));
      await t.pumpAndSettle();
    }
    expect(find.text('الرقم غلط'), findsOneWidget);
    for (final k in '2468'.split('')) {
      await t.tap(find.text(k));
      await t.pumpAndSettle();
    }
    expect(find.text('جوه'), findsOneWidget);
  });

  testWidgets('كل شاشات القوايم بتفتح من غير أخطاء', (t) async {
    await pumpApp(t);
    for (final (tab, items) in [
      ('البضاعة', ['الشحنات والتكلفة الواصلة', 'تحويلات بورسعيد ← القاهرة', 'الجرد']),
      ('الفلوس', ['توريد النقدية اليومي', 'سجل خزنة المالك', 'تحويلات الدولار للصين', 'التحصيلات والشيكات', 'النثريات والمصروفات', 'المصروفات الثابتة', 'ملخص المصروفات']),
      ('الناس', ['العملاء والأعمار', 'كشوف حساب العملاء', 'الموردين واللي علينا', 'السلف', 'الموظفين']),
    ]) {
      await tapText(t, tab);
      for (final it in items) {
        await tapText(t, it);
        expect(t.takeException(), isNull, reason: it);
        // افتح نموذج جديد لو فيه زرار
        final add = find.byType(FloatingActionButton);
        if (add.evaluate().isNotEmpty) {
          await t.tap(add.first);
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: '$it — نموذج');
          t.state<NavigatorState>(find.byType(Navigator)).pop();
          await t.pumpAndSettle();
        }
        t.state<NavigatorState>(find.byType(Navigator)).pop();
        await t.pumpAndSettle();
      }
    }
    await tapText(t, 'التقارير');
    expect(find.text('تصدير إكسل'), findsOneWidget);
  });
}
