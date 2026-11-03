// التنبيهات + التذكيرات + التقارير من بيانات التطبيق + الإكسل + PDF
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_accountant/app/alerts.dart';
import 'package:store_accountant/app/excel_export.dart';
import 'package:store_accountant/app/pdf.dart';
import 'package:store_accountant/app/reminders.dart';
import 'package:store_accountant/app/report_data.dart';
import 'package:store_accountant/data/codecs.dart';

import 'seed.dart';
import 'workbook_example.dart';

/// فولدر بنحط فيه الملفات اللي بتطلع علشان نبص عليها
final outDir = Directory(Platform.environment['TEST_OUT'] ?? '${Directory.systemTemp.path}/hesabaty_out')..createSync(recursive: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('تنبيهات النهارده بمثال الإكسل', () async {
    final s = await makeState();
    final a = s.alerts();
    List<String> g(String grp) => a.where((x) => x.group == grp).map((x) => x.title).toList();
    expect(g(AlertGroups.cash), ['القاهرة — 2026-11-02']);
    expect(g(AlertGroups.docs).length, 1); // مسحوبات شخصية من غير مستند
    expect(g(AlertGroups.customers), ['معرض النور', 'الشروق للملابس']);
    expect(g(AlertGroups.cheques), isEmpty); // الشيك فاضله 42 يوم
    expect(g(AlertGroups.payables), ['المستخلص الجمركي', 'مورد أكياس وشماعات']);
    expect(g(AlertGroups.fixed), isEmpty); // كهرباء بورسعيد ميعادها يوم 10 — فاضل 7 أيام، التنبيه بيبدأ قبلها بـ 3
    expect(g(AlertGroups.petty), ['بورسعيد — نقل بضاعة للقاهرة 1,200']); // فاتورة ناقصة
    expect(g(AlertGroups.transfers), ['إذن ت-0001 — 100 قطعة']);
    // الترتيب: نفس ترتيب الطلب
    expect(a.first.group, AlertGroups.cash);
    expect(a.last.group, AlertGroups.transfers);
  });

  test('المصروف الثابت بيظهر قبل ميعاده بـ 3 أيام ولما يفوت', () async {
    final s7 = await makeState(clock: () => DateTime(2026, 11, 7, 10));
    expect(s7.alerts().where((x) => x.group == AlertGroups.fixed).map((x) => '${x.title} | ${x.detail}').toList(),
        ['كهرباء بورسعيد — 4,000 | ميعاده يوم 10']);
    final s12 = await makeState(clock: () => DateTime(2026, 11, 12, 10));
    expect(s12.alerts().where((x) => x.group == AlertGroups.fixed).single.detail, 'ميعاده كان يوم 10 وفات');
    // عجز التوريد بيفضل ظاهر 7 أيام بس
    expect(s12.alerts().where((x) => x.group == AlertGroups.cash), isEmpty);
  });

  test('التقارير من بيانات التطبيق = أرقام الإكسل', () async {
    final s = await makeState();
    final daily = dailyFor(s, d(2026, 11, 1));
    expect(daily.netSales.total, 90500);
    final w = weeklyFor(s, d(2026, 11, 4));
    expect([w.from, w.to], [d(2026, 11, 1), d(2026, 11, 7)]);
    expect(w.safe.expected, 1043850);
    expect(w.message, contains('رصيد خزنتك حسب الحسابات: 1,043,850'));
    final m = monthlyFor(s, d(2026, 11, 1));
    expect(m.netProfit.total, 710750);
    expect(m.netProfit.cairo, 269750);
    final p = s.payroll(d(2026, 11, 1));
    expect(p.map((x) => x.net).toList(), [11500, 6500, 6700, 7700, 5200]);
  });

  test('خطة التذكيرات', () async {
    final s = await makeState();
    final plan = reminderPlan(s);
    Reminder byId(int id) => plan.firstWhere((r) => r.id == id);
    expect(byId(1).when, DateTime(2026, 11, 4, 10)); // الساعة 10 عدت النهارده → بكره
    expect(byId(1).repeat, Repeat.daily);
    expect(byId(2).when, DateTime(2026, 11, 5, 10)); // أول خميس
    expect(byId(2).when.weekday, DateTime.thursday);
    expect(byId(3).when, DateTime(2026, 11, 25, 9));
    final cheques = plan.where((r) => r.id >= 1000).toList();
    expect(cheques.map((r) => r.when).toList(), [DateTime(2026, 12, 13, 9), DateTime(2026, 12, 15, 9)]);
    final fixed = plan.where((r) => r.id >= 100 && r.id < 1000).toList();
    expect(fixed.length, fixedExpenses.length);
    expect(fixed.every((r) => r.repeat == Repeat.monthly), true);
    expect(fixed.firstWhere((r) => r.body.contains('كهرباء محل القاهرة')).when, DateTime(2026, 11, 10, 9));
    expect(fixed.firstWhere((r) => r.body.contains('إيجار محل القاهرة')).when, DateTime(2026, 12, 1, 9)); // يوم 1 عدى
  });

  test('تصدير الإكسل بنفس شكل الملف', () async {
    final s = await makeState();
    final bytes = buildExcel(s);
    File('${outDir.path}/export.xlsx').writeAsBytesSync(bytes);
    final ex = Excel.decodeBytes(bytes);
    expect(ex.tables.keys.toList(), [
      'الفهرس', 'خريطة الدورة', 'دليل المستندات', 'القيود المحاسبية', 'دليل الحسابات', 'التكلفة الواصلة', 'إذن تحويل مخزني', 'توريد النقدية',
      'سجل خزنة المالك', 'تحويلات الدولار', 'العملاء والأعمار', 'كشف حساب عميل', 'التحصيلات والشيكات', 'الموردين واللي علينا', 'الجرد', 'المرتبات',
      'السلف', 'المصروفات الثابتة', 'النثريات والمصروفات', 'ملخص المصروفات', 'التقرير اليومي', 'التقرير الأسبوعي', 'التقرير الشهري', 'المتابعة عن بعد',
      'متابعة المالك بدون مكالمات', 'المخاطر والضوابط', 'أسئلة للمالك', 'خطة التنفيذ',
    ]);
    String v(String sh, String cell) => '${ex.tables[sh]!.cell(CellIndex.indexByString(cell)).value}';
    double n(String sh, String cell) => double.parse(v(sh, cell));
    expect(v('توريد النقدية', 'A5'), 'التاريخ'); // العناوين في نفس مكانها
    expect(v('توريد النقدية', 'J6'), 'مطابق');
    expect(v('توريد النقدية', 'J7'), 'عجز');
    expect(n('توريد النقدية', 'I7'), -100);
    expect(n('التكلفة الواصلة', 'K22'), closeTo(298.04, 0.001));
    expect(v('التكلفة الواصلة', 'C32'), 'null');
    expect(v('التكلفة الواصلة', 'I33'), 'مطابق');
    expect(n('السلف', 'I6'), 2000);
    expect(v('السلف', 'J6'), 'بتتخصم');
    expect(n('كشف حساب عميل', 'G14'), 125000); // الرصيد آخر الفترة
    expect(v('كشف حساب عميل', 'A16'), startsWith('مصادقة: أقر أنا / محلات الأمل'));
    expect(n('المرتبات', 'P8'), 6500);
    expect(v('الفهرس', 'A1'), startsWith('الدورة المستندية'));
    expect(v('خريطة الدورة', 'B6'), 'طلب الشراء');
  });

  test('التقرير الشهري PDF بالعربي', () async {
    final s = await makeState();
    final r = monthlyFor(s, d(2026, 11, 1));
    final reg = ByteData.sublistView(File('assets/fonts/NotoSansArabic-Regular.ttf').readAsBytesSync());
    final bold = ByteData.sublistView(File('assets/fonts/NotoSansArabic-Bold.ttf').readAsBytesSync());
    ByteData f(String n) => ByteData.sublistView(File('assets/fonts/$n.ttf').readAsBytesSync());
    final bytes = await buildMonthlyPdf(d(2026, 11, 1), r, regular: reg, bold: bold, latin: f('NotoSans-Regular'), latinBold: f('NotoSans-Bold'));
    File('${outDir.path}/monthly.pdf').writeAsBytesSync(bytes);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(5000));
  });

  test('رصيد مورد الدولار من الإعدادات', () async {
    final s = await makeState();
    expect(s.averageRateFor('ش-2026-01'), closeTo(50.2857142857143, 1e-9));
    expect(s.values(stockTransferCodec).single.receivedAt, null);
  });
}
