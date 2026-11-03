import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../app/pdf.dart';
import '../app/report_data.dart';
import '../app/state.dart';
import '../data/codecs.dart';
import '../data/store.dart';
import '../engine/cash.dart';
import '../engine/customers.dart';
import '../engine/excel.dart';
import '../engine/format.dart';
import '../engine/payroll_expenses.dart';
import '../engine/reports.dart';
import 'backup.dart';
import 'common.dart';
import 'form.dart';
import 'payroll.dart';
import 'registers.dart';
import 'settings.dart';
import 'specs.dart';
import 'theme.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});
  @override
  Widget build(BuildContext context) {
    void go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 100), children: [
      const Text('التقارير', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      BigTile(icon: Icons.today, label: 'التقرير اليومي', sub: 'كل يوم الساعة 10 الصبح', color: moneyColor, onTap: () => go(const DailyReportScreen())),
      const SizedBox(height: 8),
      BigTile(icon: Icons.date_range, label: 'التقرير الأسبوعي', sub: 'كل خميس + تأكيد رصيد خزنة المالك', color: moneyColor, onTap: () => go(const WeeklyReportScreen())),
      const SizedBox(height: 8),
      BigTile(icon: Icons.calendar_month, label: 'التقرير الشهري', sub: 'أرباح وخسائر لكل فرع + PDF', color: moneyColor, onTap: () => go(const MonthlyReportScreen())),
      const SizedBox(height: 8),
      BigTile(icon: Icons.pie_chart, label: 'ملخص المصروفات', sub: 'مقابل الميزانية', color: moneyColor, onTap: () => go(const ExpenseSummaryScreen())),
      const SizedBox(height: 20),
      BigTile(icon: Icons.table_view, label: 'تصدير إكسل', sub: 'بنفس شكل ملف الدورة المستندية', color: Colors.teal, onTap: () => exportExcel(context)),
      const SizedBox(height: 8),
      BigTile(icon: Icons.backup, label: 'النسخة الاحتياطية', sub: 'احفظ كل حاجة في ملف واحد أو رجّعها', color: Colors.indigo, onTap: () => go(const BackupScreen())),
      const SizedBox(height: 8),
      BigTile(icon: Icons.settings, label: 'الإعدادات والتذكيرات', color: Colors.blueGrey, onTap: () => go(const SettingsScreen())),
    ]);
  }
}

// ───────── أدوات ─────────
bool _inRange(DateTime d, DateTime a, DateTime b) => !dateOnly(d).isBefore(dateOnly(a)) && !dateOnly(d).isAfter(dateOnly(b));

void drill<T>(BuildContext context, EntitySpec<T> spec, String title, bool Function(T) f) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => CollectionScreen(spec: spec, titleOverride: title, filter: (Stored x) => f(x.value as T))));

/// سطر "فرعين + إجمالي" ممكن تدوس على كل رقم
class BranchRow extends StatelessWidget {
  final String label;
  final ByBranch v;
  final String Function(num)? fmt;
  final void Function(String? branch)? onTap; // null = الإجمالي
  final bool bold;
  final String? note;
  const BranchRow(this.label, this.v, {super.key, this.fmt, this.onTap, this.bold = false, this.note});
  @override
  Widget build(BuildContext context) {
    final f = fmt ?? money;
    final st = TextStyle(fontSize: 15, fontWeight: bold ? FontWeight.bold : FontWeight.normal);
    Widget cell(String t, String? b) => Expanded(
          child: InkWell(
            onTap: onTap == null ? null : () => onTap!(b),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(t, textAlign: TextAlign.center, textDirection: TextDirection.ltr,
                  style: st.copyWith(decoration: onTap == null ? null : TextDecoration.underline, decorationStyle: TextDecorationStyle.dotted)),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          Expanded(child: Text(label, style: st.copyWith(fontWeight: FontWeight.w600))),
          if (note != null)
            Flexible(child: Text(note!, textAlign: TextAlign.end, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))),
        ]),
      ),
      Row(children: [cell(f(v.cairo), cairo), cell(f(v.portSaid), portSaid), cell(f(v.total), null)]),
      const Divider(height: 1),
    ]);
  }
}

class BranchHeader extends StatelessWidget {
  const BranchHeader({super.key});
  @override
  Widget build(BuildContext context) => const Row(children: [
        Expanded(child: Text('القاهرة', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
        Expanded(child: Text('بورسعيد', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
        Expanded(child: Text('الإجمالي', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
      ]);
}

/// خانة "فرعين" بتتكتب بالإيد
class ManualBranchInput extends StatelessWidget {
  final String label;
  final ByBranch value;
  final ValueChanged<ByBranch> onChanged;
  final String? note;
  const ManualBranchInput(this.label, this.value, this.onChanged, {super.key, this.note});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$label${note == null ? '' : ' — $note'}', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: _num('القاهرة', value.cairo, (v) => onChanged(ByBranch(v, value.portSaid)))),
            const SizedBox(width: 8),
            Expanded(child: _num('بورسعيد', value.portSaid, (v) => onChanged(ByBranch(value.cairo, v)))),
          ]),
        ]),
      );
}

Widget _num(String label, num? v, ValueChanged<double> onChanged, {Key? key}) => TextFormField(
      key: key,
      initialValue: v == null || v == 0 ? '' : numText(v),
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      inputFormatters: [ThousandsFormatter()],
      textDirection: TextDirection.ltr,
      decoration: InputDecoration(labelText: label, isDense: true),
      onChanged: (t) => onChanged(parseNum(t) ?? 0),
    );

Widget _int(String label, int v, ValueChanged<int> onChanged) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
        IconButton.outlined(onPressed: v > 0 ? () => onChanged(v - 1) : null, icon: const Icon(Icons.remove)),
        SizedBox(width: 40, child: Text('$v', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        IconButton.outlined(onPressed: () => onChanged(v + 1), icon: const Icon(Icons.add)),
      ]),
    );

class DateBar extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  final int step;
  final String? label;
  const DateBar({super.key, required this.date, required this.onChanged, this.step = 1, this.label});
  @override
  Widget build(BuildContext context) => Row(children: [
        IconButton.filledTonal(onPressed: () => onChanged(date.subtract(Duration(days: step))), icon: const Icon(Icons.chevron_right)),
        Expanded(
          child: TextButton(
            onPressed: () async {
              final d = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2035));
              if (d != null) onChanged(d);
            },
            child: Text(label ?? dayName(date), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ),
        IconButton.filledTonal(onPressed: () => onChanged(date.add(Duration(days: step))), icon: const Icon(Icons.chevron_left)),
      ]);
}

// ═════════ اليومي ═════════
class DailyReportScreen extends StatefulWidget {
  const DailyReportScreen({super.key});
  @override
  State<DailyReportScreen> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends State<DailyReportScreen> {
  DateTime? date;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    // التقرير بيتبعت الصبح عن اليوم اللي فات
    final d = date ?? s.today.subtract(const Duration(days: 1));
    final key = K.daily(d);
    final mj = s.manual(key);
    final manual = dailyManualFrom(mj);
    Future<void> put(String k, Object v) => s.set(key, {...mj, k: v});
    final r = dailyFor(s, d);
    void hand(String? b) => drill<CashHandover>(context, cashHandoverSpec, 'توريد ${fmtDate(d)}',
        (h) => dateOnly(h.date) == dateOnly(d) && (b == null || h.branch == b));
    return Scaffold(
      appBar: AppBar(title: const Text('التقرير اليومي')),
      body: ListView(key: ValueKey(key), padding: const EdgeInsets.fromLTRB(12, 8, 12, 40), children: [
        DateBar(date: d, onChanged: (v) => setState(() => date = v)),
        const SectionTitle('اكتب من السيستم (الخانات الصفرا)'),
        ManualBranchInput('مبيعات آجل', manual.creditSales, (v) => put('creditSales', bbJson(v)), note: 'تقرير المبيعات في السيستم'),
        ManualBranchInput('مردودات (بالسالب)', manual.returns, (v) => put('returns', bbJson(v))),
        ManualBranchInput('تحصيلات بشيكات', manual.chequeCollections, (v) => put('chequeCollections', bbJson(v)), note: 'سجل الشيكات'),
        const SectionTitle('الأرقام'),
        const BranchHeader(),
        BranchRow('مبيعات نقدي', r.cashSales, onTap: hand, note: 'من توريد النقدية'),
        BranchRow('مبيعات آجل', r.creditSales, note: 'بالإيد'),
        BranchRow('مردودات', r.returns, note: 'بالإيد'),
        BranchRow('صافي المبيعات', r.netSales, bold: true),
        BranchRow('نسبة الآجل', ByBranch(r.creditRatio(cairo), r.creditRatio(portSaid)), fmt: (v) => fmtPct(v)),
        Text('نسبة الآجل الإجمالية: ${fmtPct(r.creditRatio(null))}', textAlign: TextAlign.center),
        BranchRow('تحصيلات نقدية من عملاء', r.cashCollections, onTap: hand),
        BranchRow('تحصيلات بشيكات', r.chequeCollections, note: 'بالإيد'),
        BranchRow('نثريات اتصرفت', r.petty, onTap: hand),
        BranchRow('المفروض يتورد لخزنة المالك', r.expected, onTap: hand),
        BranchRow('اتورد فعلاً', r.delivered, onTap: hand),
        BranchRow('فرق التوريد (لازم صفر)', r.handoverDiff, bold: true, onTap: hand),
        const SectionTitle('تنبيهات اليوم'),
        _int('فواتير اتلغت', manual.cancelledInvoices, (v) => put('cancelledInvoices', v)),
        _int('بيع آجل لعميل متجاوز الحد أو متأخر', manual.creditOverLimit, (v) => put('creditOverLimit', v)),
        _int('مرتجعات', manual.returnsCount, (v) => put('returnsCount', v)),
        _int('تحويلات مخزنية معلّقة أكتر من 48 ساعة', manual.pendingTransfers, (v) => put('pendingTransfers', v)),
        NumRow('فرع فيه عجز توريد', '${r.shortageBranches}', onTap: () => hand(null)),
        NumRow('شيكات مستحقة خلال يومين', '${r.chequesDue2Days}',
            onTap: () => drill<Collection>(context, collectionSpec, 'شيكات خلال يومين', (c) {
                  final x = c.daysLeft(s.today);
                  return x != null && x >= 0 && x <= 2;
                })),
        NumRow('حركات خزنة المالك من غير مستند', '${r.safeMissingDocs}',
            onTap: () => drill<SafeMovement>(context, safeMovementSpec, 'من غير مستند', (m) => m.status == 'مستند ناقص')),
        NumRow('مصروفات من غير فاتورة أو فوق الحد', '${r.pettyNeedsReview}',
            onTap: () => drill<PettyExpense>(context, pettyExpenseSpec, 'محتاجة مراجعة', (p) => p.status(s.pettyLimit) != 'تمام')),
        NumRow('عدد التنبيهات', '${r.alertsCount}', bold: true),
        const SizedBox(height: 8),
        MessageBox(r.message),
      ]),
    );
  }
}

// ═════════ الأسبوعي ═════════
class WeeklyReportScreen extends StatefulWidget {
  const WeeklyReportScreen({super.key});
  @override
  State<WeeklyReportScreen> createState() => _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends State<WeeklyReportScreen> {
  DateTime? start;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final from = start ?? weekStart(s.today);
    final end = from.add(const Duration(days: 6));
    final key = K.weekly(from);
    final mj = s.manual(key);
    final manual = weeklyManualFor(s, from);
    final r = weeklyFor(s, from);
    Future<void> put(String k, Object? v) => s.set(key, {...mj, k: v, 'netSales': bbJson(r.netSales)});
    void hand(String? b) => drill<CashHandover>(context, cashHandoverSpec, 'توريد الأسبوع',
        (h) => _inRange(h.date, from, end) && (b == null || h.branch == b));
    void cols(bool? cheque) => drill<Collection>(context, collectionSpec, 'تحصيلات الأسبوع',
        (c) => _inRange(c.date, from, end) && (cheque == null || c.isCheque == cheque));
    void safe(bool deposits) => drill<SafeMovement>(context, safeMovementSpec, deposits ? 'إيداعات الأسبوع' : 'صرف الأسبوع',
        (m) => _inRange(m.date, from, end) && ((m.type == SafeType.deposit) == deposits));
    return Scaffold(
      appBar: AppBar(title: const Text('التقرير الأسبوعي')),
      body: ListView(key: ValueKey(key), padding: const EdgeInsets.fromLTRB(12, 8, 12, 40), children: [
        DateBar(date: from, step: 7, label: '${fmtDate(from)} ← ${fmtDate(end)}', onChanged: (v) => setState(() => start = weekStart(v))),
        const SectionTitle('اكتب من السيستم'),
        ManualBranchInput('مبيعات آجل', manual.creditSales, (v) => put('creditSales', bbJson(v))),
        ManualBranchInput('مردودات (بالسالب)', manual.returns, (v) => put('returns', bbJson(v))),
        ManualBranchInput('صافي مبيعات الأسبوع اللي فات', manual.lastWeekNet, (v) => put('lastWeekNet', bbJson(v))),
        const SectionTitle('1) المبيعات'),
        const BranchHeader(),
        BranchRow('مبيعات نقدي', r.cashSales, onTap: hand),
        BranchRow('مبيعات آجل', r.creditSales, note: 'بالإيد'),
        BranchRow('مردودات', r.returns, note: 'بالإيد'),
        BranchRow('صافي المبيعات', r.netSales, bold: true),
        BranchRow('التغيير عن الأسبوع اللي فات', ByBranch(r.change(cairo), r.change(portSaid)), fmt: (v) => fmtSignedPct(v)),
        Text('التغيير الإجمالي: ${fmtSignedPct(r.change(null))} — نسبة الآجل: ${fmtPct(r.creditRatio(null))}', textAlign: TextAlign.center),
        const SectionTitle('2) التحصيل مقابل الهدف'),
        NumRow('إجمالي تحصيلات الأسبوع', money(r.collections), onTap: () => cols(null)),
        NumRow('منه نقدي', money(r.cashCollections), onTap: () => cols(false)),
        NumRow('منه شيكات', money(r.chequeCollections), onTap: () => cols(true)),
        NumRow('هدف التحصيل للأسبوع', money(r.target), onTap: () => openCollection(context, customerCodec.collection)),
        NumRow('نسبة تحقيق الهدف', fmtPct(r.targetRatio), bold: true, color: r.targetRatio < 0.8 ? dangerColor : okColor, note: 'أقل من 80% = لازم نتكلم'),
        const SectionTitle('3) أعمار ديون العملاء'),
        NumRow('0–30 يوم', '${money(r.aging.b0to30)} (${fmtPct(r.aging.pct(r.aging.b0to30))})'),
        NumRow('31–60 يوم', '${money(r.aging.b31to60)} (${fmtPct(r.aging.pct(r.aging.b31to60))})'),
        NumRow('61–90 يوم', '${money(r.aging.b61to90)} (${fmtPct(r.aging.pct(r.aging.b61to90))})'),
        NumRow('أكتر من 90 يوم', '${money(r.aging.b90plus)} (${fmtPct(r.aging.pct(r.aging.b90plus))})',
            onTap: () => drill<Customer>(context, customerSpec, 'متأخر +90', (c) => c.b90plus > 0)),
        NumRow('الإجمالي لينا عند العملاء', money(r.aging.total), bold: true, onTap: () => openCollection(context, customerCodec.collection)),
        NumRow('عدد العملاء المتجاوزين الحد', '${r.overLimitCount}',
            onTap: () => drill<Customer>(context, customerSpec, 'متجاوزين الحد', (c) => c.alert == CustomerAlert.overLimit)),
        NumRow('عدد العملاء المتأخرين +90', '${r.over90Count}',
            onTap: () => drill<Customer>(context, customerSpec, 'متأخرين +90', (c) => c.alert == CustomerAlert.over90)),
        NumRow('شيكات مستحقة الأسبوع الجاي', money(r.chequesDueNextWeek),
            onTap: () => drill<Collection>(context, collectionSpec, 'شيكات الأسبوع الجاي', (c) {
                  final x = c.daysLeft(s.today);
                  return x != null && x >= 0 && x <= 7;
                })),
        NumRow('شيكات مرتدة لسه', money(r.bouncedCheques),
            onTap: () => drill<Collection>(context, collectionSpec, 'شيكات مرتدة', (c) => c.chequeState == ChequeState.bounced)),
        const SectionTitle('4) اللي علينا للموردين'),
        NumRow('الصافي علينا للموردين', money(r.suppliersNet), onTap: () => openCollection(context, supplierCodec.collection)),
        NumRow('منه متأخر', money(r.suppliersLate), onTap: () => openCollection(context, supplierCodec.collection)),
        NumRow('مطلوب سداده خلال 7 أيام', money(r.suppliersDue7), bold: true, onTap: () => openCollection(context, supplierCodec.collection)),
        const SectionTitle('5) النقدية وخزنة المالك'),
        NumRow('أيام فيها عجز توريد', '${r.shortageDays}', onTap: () => hand(null)),
        NumRow('إجمالي فروق التوريد', money(r.handoverDiffTotal), onTap: () => hand(null)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: _num('رصيد خزنة المالك أول الأسبوع', manual.safeOpening, (v) => put('safeOpening', v),
              key: ValueKey('open-$key-${manual.safeOpening == 0}')),
        ),
        NumRow('+ توريدات المحلات', money(r.safe.handovers), onTap: () => hand(null)),
        NumRow('+ إيداعات تانية', money(r.safe.deposits), onTap: () => safe(true)),
        NumRow('− صرف من الخزنة', money(r.safe.payments), onTap: () => safe(false), note: 'دولار + مستخلص + مسحوبات + مصروفات'),
        NumRow('الرصيد المفروض دلوقتي', money(r.safe.expected), bold: true, color: moneyColor),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: _num('الرصيد اللي المالك أكده (رده على رسالة الخميس)', manual.ownerConfirmed, (v) => put('ownerConfirmed', v)),
        ),
        if (r.safe.difference != null)
          NumRow('الفرق', money(r.safe.difference!), bold: true, color: r.safe.difference == 0 ? okColor : dangerColor,
              note: 'لو مش صفر = حركة ماوصلتش الجروب'),
        NumRow('حركات لسه من غير مستند', '${r.safeMissingDocs}',
            onTap: () => drill<SafeMovement>(context, safeMovementSpec, 'من غير مستند', (m) => m.status == 'مستند ناقص')),
        const SectionTitle('6) الجرد'),
        NumRow('نسبة الأصناف المطابقة في جرد العيّنة', fmtPct(r.stockMatchRatio), onTap: () => openCollection(context, stockCountCodec.collection)),
        NumRow('قيمة فروق الجرد', money(r.stockDiffValue), onTap: () => openCollection(context, stockCountCodec.collection)),
        const SizedBox(height: 8),
        MessageBox(r.message, title: 'رسالة الخميس الجاهزة'),
      ]),
    );
  }
}

// ═════════ الشهري ═════════
class MonthlyReportScreen extends StatefulWidget {
  const MonthlyReportScreen({super.key});
  @override
  State<MonthlyReportScreen> createState() => _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends State<MonthlyReportScreen> {
  DateTime? month;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    // التقرير الشهري بيتعمل أول الشهر عن الشهر اللي فات
    final m = month ?? DateTime(s.today.year, s.today.month - 1, 1);
    final key = K.monthly(m);
    final mj = s.manual(key);
    final r = monthlyFor(s, m);
    final mm = r.m;
    Future<void> put(String k, Object v) => s.set(key, {...mj, k: v});
    void exp() => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpenseSummaryScreen()));
    return Scaffold(
      appBar: AppBar(title: const Text('التقرير الشهري')),
      body: ListView(key: ValueKey(key), padding: const EdgeInsets.fromLTRB(12, 8, 12, 40), children: [
        MonthPicker(month: m, onChanged: (v) => setState(() => month = v)),
        ExpansionTile(
          title: const Text('الأرقام اللي بتتنقل من السيستم آخر الشهر', style: TextStyle(fontWeight: FontWeight.bold)),
          initiallyExpanded: mj.isEmpty,
          children: [
            ManualBranchInput('مبيعات نقدي', mm.cashSales, (v) => put('cashSales', bbJson(v))),
            ManualBranchInput('مبيعات آجل', mm.creditSales, (v) => put('creditSales', bbJson(v))),
            ManualBranchInput('مردودات وخصومات (بالسالب)', mm.returns, (v) => put('returns', bbJson(v))),
            ManualBranchInput('تكلفة المبيعات (بالسالب)', mm.cogs, (v) => put('cogs', bbJson(v))),
            ManualBranchInput('تحصيلات الشهر', mm.collections, (v) => put('collections', bbJson(v))),
            ManualBranchInput('رصيد العملاء آخر الشهر', mm.customersBalance, (v) => put('customersBalance', bbJson(v))),
            ManualBranchInput('منه متأخر أكتر من 90 يوم', mm.customersOver90, (v) => put('customersOver90', bbJson(v))),
            ManualBranchInput('رصيد المخزون بالتكلفة', mm.stockAtCost, (v) => put('stockAtCost', bbJson(v))),
            ManualBranchInput('عجز جرد الشهر (قيمة)', mm.stockShortage, (v) => put('stockShortage', bbJson(v))),
            ManualBranchInput('نقدية اتوردت لخزنة المالك', mm.deliveredToSafe, (v) => put('deliveredToSafe', bbJson(v))),
            Row(children: [
              Expanded(child: _num('دولار اتحوّل للصين (\$)', mm.usdTransferred, (v) => put('usdTransferred', v))),
              const SizedBox(width: 8),
              Expanded(child: _num('رصيد مورد الصين (\$)', mm.chinaSupplierUsd, (v) => put('chinaSupplierUsd', v))),
            ]),
            const SizedBox(height: 10),
          ],
        ),
        const BranchHeader(),
        const SectionTitle('المبيعات'),
        BranchRow('صافي المبيعات', r.netSales, bold: true, note: 'نقدي + آجل − مردودات'),
        BranchRow('تكلفة المبيعات', mm.cogs),
        BranchRow('مجمل الربح', r.grossProfit, bold: true),
        BranchRow('نسبة مجمل الربح', ByBranch(r.grossMargin(cairo), r.grossMargin(portSaid)), fmt: (v) => fmtPct(v)),
        const SectionTitle('المصروفات'),
        BranchRow('إيجارات', r.rent, onTap: (_) => exp()),
        BranchRow('مرتبات وعمولات', r.payroll, onTap: (_) => Navigator.push(context, MaterialPageRoute(builder: (_) => const PayrollScreen()))),
        BranchRow('باقي المصروفات', r.otherExpenses, onTap: (_) => exp()),
        BranchRow('صافي الربح', r.netProfit, bold: true),
        BranchRow('نسبة صافي الربح', ByBranch(r.netMargin(cairo), r.netMargin(portSaid)), fmt: (v) => fmtPct(v)),
        Text('نسبة صافي الربح الإجمالية: ${fmtPct(r.netMargin(null))}', textAlign: TextAlign.center),
        const SectionTitle('مؤشرات العملاء والتحصيل'),
        BranchRow('نسبة البيع الآجل', ByBranch(r.creditRatio(cairo), r.creditRatio(portSaid)), fmt: (v) => fmtPct(v)),
        BranchRow('نسبة التحصيل من الآجل', ByBranch(r.collectionRatio(cairo), r.collectionRatio(portSaid)), fmt: (v) => fmtPct(v)),
        BranchRow('نسبة المتأخر +90', ByBranch(r.over90Ratio(cairo), r.over90Ratio(portSaid)), fmt: (v) => fmtPct(v),
            note: 'لو بيزيد شهر ورا شهر = مشكلة تحصيل'),
        const SectionTitle('مؤشرات المخزون'),
        BranchRow('المخزون يكفي كام يوم بيع', ByBranch(r.stockDays(cairo), r.stockDays(portSaid)), fmt: (v) => fmtNum(v)),
        BranchRow('عجز جرد الشهر', mm.stockShortage),
        const SectionTitle('النقدية والاستيراد'),
        BranchRow('نقدية اتوردت لخزنة المالك', mm.deliveredToSafe),
        NumRow('دولار اتحوّل للصين', '\$${fmtNum(mm.usdTransferred)}'),
        NumRow('رصيد مورد الصين', '\$${fmtNum(mm.chinaSupplierUsd)}'),
        NumRow('الصافي علينا للموردين', money(r.suppliersNet), onTap: () => openCollection(context, supplierCodec.collection)),
        NumRow('منه متأخر', money(r.suppliersLate), onTap: () => openCollection(context, supplierCodec.collection)),
        const SizedBox(height: 12),
        MessageBox(monthlyMessage(m, r), title: 'ملخص للواتساب'),
        const SizedBox(height: 8),
        FilledButton.icon(
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('PDF للتقرير الشهري'),
          onPressed: () async {
            final bytes = await buildMonthlyPdf(m, r);
            await Printing.sharePdf(bytes: bytes, filename: 'التقرير_الشهري_${m.year}-${m.month.toString().padLeft(2, '0')}.pdf');
          },
        ),
      ]),
    );
  }
}

/// ملخص الشهري للواتساب (الإكسل مافيهوش رسالة جاهزة للشهري، فدي على نفس نمط اليومي والأسبوعي)
String monthlyMessage(DateTime m, MonthlyReport r) => 'التقرير الشهري — ${monthName(m)}\n'
    'صافي المبيعات: ${fmtNum(r.netSales.total)} (القاهرة ${fmtNum(r.netSales.cairo)} / بورسعيد ${fmtNum(r.netSales.portSaid)})\n'
    'مجمل الربح: ${fmtNum(r.grossProfit.total)} (${fmtPct(r.grossMargin(null))})\n'
    'صافي الربح: ${fmtNum(r.netProfit.total)} (${fmtPct(r.netMargin(null))}) — القاهرة ${fmtNum(r.netProfit.cairo)} / بورسعيد ${fmtNum(r.netProfit.portSaid)}\n'
    'نسبة التحصيل من الآجل: ${fmtPct(r.collectionRatio(null))} — المتأخر +90: ${fmtPct(r.over90Ratio(null))}\n'
    'علينا للموردين: ${fmtNum(r.suppliersNet)} — منه متأخر: ${fmtNum(r.suppliersLate)}';
