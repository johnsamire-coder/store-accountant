// شاشات القوايم والتفاصيل لكل السجلات + ملخص فوق كل قايمة زي صفوف الإجمالي في الإكسل.
import 'package:flutter/material.dart';

import '../app/state.dart';
import '../data/codecs.dart';
import '../data/store.dart';
import '../engine/cash.dart';
import '../engine/customers.dart';
import '../engine/format.dart';
import '../engine/payroll_expenses.dart';
import 'common.dart';
import 'form.dart';
import 'specs.dart';
import 'theme.dart';

Future<void> openCollection(BuildContext context, String collection) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => CollectionScreen(spec: specsByCollection[collection]!)));

Future<void> openRecord(BuildContext context, String collection, String id) => Navigator.push(
    context, MaterialPageRoute(builder: (_) => DetailScreen(spec: specsByCollection[collection]!, id: id)));

Future<bool?> openNew(BuildContext context, EntitySpec spec, {Json? initial}) =>
    Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => spec.formPage(initial: initial)));

class CollectionScreen extends StatefulWidget {
  final EntitySpec spec;
  final bool Function(Stored)? filter;
  final String? titleOverride;
  const CollectionScreen({super.key, required this.spec, this.filter, this.titleOverride});
  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  String? branch; // فلتر الفرع
  String q = '';

  @override
  Widget build(BuildContext context) {
    final sp = widget.spec;
    final s = AppScope.of(context);
    var items = sp.storedIn(s).toList();
    if (widget.filter != null) items = items.where((x) => widget.filter!(x)).toList();
    if (sp.hasDate) {
      items.sort((a, b) => (sp.dateOf(b.value) ?? DateTime(0)).compareTo(sp.dateOf(a.value) ?? DateTime(0)));
    }
    final hasBranch = sp.groupBy == 'branch';
    if (hasBranch && branch != null) {
      items = items.where((x) => sp.encodeOf(x.value)['branch'] == branch).toList();
    }
    if (q.isNotEmpty) {
      items = items.where((x) => '${sp.titleOf(x.value)} ${sp.subOf(x.value, s)}'.contains(q)).toList();
    }
    final header = collectionHeader(context, sp.codec.collection, s, branch);
    return Scaffold(
      appBar: AppBar(title: Text(widget.titleOverride ?? sp.title)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-${sp.codec.collection}',
        backgroundColor: sp.color,
        foregroundColor: Colors.white,
        onPressed: () => openNew(context, sp),
        icon: const Icon(Icons.add),
        label: Text('${sp.single} جديد', style: const TextStyle(fontSize: 17)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
        children: [
          if (hasBranch)
            Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('الكل'), selected: branch == null, onSelected: (_) => setState(() => branch = null)),
              for (final b in branchOptions)
                ChoiceChip(label: Text(b), selected: branch == b, onSelected: (_) => setState(() => branch = b)),
            ]),
          ?header,
          if (sp.storedIn(s).length > 8)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'دوّر'),
                onChanged: (v) => setState(() => q = v.trim()),
              ),
            ),
          if (items.isEmpty) const EmptyHint('لسه مفيش حاجة هنا.\nدوس على الزرار اللي تحت علشان تضيف.'),
          for (final it in items)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Theme.of(context).dividerColor)),
              child: ListTile(
                title: Text(sp.titleOf(it.value), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(sp.subOf(it.value, s), style: const TextStyle(fontSize: 14)),
                    if (sp.statusOf(it.value, s).isNotEmpty)
                      Padding(padding: const EdgeInsets.only(top: 6), child: StatusChip(sp.statusOf(it.value, s))),
                  ]),
                ),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailScreen(spec: sp, id: it.id))),
              ),
            ),
        ],
      ),
    );
  }
}

class DetailScreen extends StatelessWidget {
  final EntitySpec spec;
  final String id;
  const DetailScreen({super.key, required this.spec, required this.id});
  @override
  Widget build(BuildContext context) {
    final sp = spec;
    final s = AppScope.of(context);
    final st = sp.byIdIn(s, id);
    if (st == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyHint('السجل ده اتمسح'));
    }
    final v = st.value;
    final json = sp.encodeOf(v);
    return Scaffold(
      appBar: AppBar(title: Text(sp.titleOf(v)), actions: [
        IconButton(
          tooltip: 'امسح',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            if (await confirm(context, 'متأكد إنك عايز تمسح ${sp.single} ده؟')) {
              await s.remove(sp.codec, id);
              if (context.mounted) Navigator.pop(context);
            }
          },
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'edit-$id',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => sp.formPage(id: id))),
        icon: const Icon(Icons.edit),
        label: const Text('تعديل', style: TextStyle(fontSize: 17)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          if (sp.statusOf(v, s).isNotEmpty) Align(alignment: AlignmentDirectional.centerStart, child: StatusChip(sp.statusOf(v, s))),
          const SizedBox(height: 8),
          Text(sp.subOf(v, s), style: const TextStyle(fontSize: 16)),
          if (sp.hasDetails) ...[
            const SectionTitle('الحسابات'),
            for (final r in sp.detailsOf(v, s)) NumRow(r.$1, r.$2),
          ],
          ?sp.extraOf(context, st),
          ?detailExtra(context, sp.codec.collection, st, s),
          const SectionTitle('البيانات'),
          for (final f in sp.fields)
            if (f.type != FType.lines && (f.visible == null || f.visible!(json)))
              NumRow(f.label, _show(f, getPath(json, f.key))),
          for (final f in sp.fields)
            if (f.type == FType.lines) ...[
              SectionTitle(f.label),
              for (final row in ((json[f.key] as List?) ?? const []).cast<Map>())
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text([for (final sf in f.sub) if (row[sf.key] != null && '${row[sf.key]}'.isNotEmpty) '${sf.label}: ${_show(sf, row[sf.key])}'].join('   •   ')),
                  ),
                ),
            ],
        ],
      ),
    );
  }

  String _show(FieldSpec f, Object? v) {
    if (v == null || (v is String && v.isEmpty)) return '—';
    switch (f.type) {
      case FType.number:
        return numText(v as num);
      case FType.date:
        return fmtDate(DateTime.parse(v as String));
      case FType.dateTime:
        final d = DateTime.parse(v as String);
        return '${fmtDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      case FType.month:
        return monthName(DateTime.parse(v as String));
      case FType.yesNo:
        return v == true ? 'نعم' : 'لا';
      default:
        return '$v';
    }
  }
}

// ═════════ ملخصات فوق القوايم ═════════
Widget _box(BuildContext context, Color color, List<Widget> children) => Card(
      elevation: 0,
      color: color.withValues(alpha: 0.08),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: Column(children: children)),
    );

Widget? collectionHeader(BuildContext context, String col, AppState s, String? branch) {
  double sum<T>(Iterable<T> l, double Function(T) f) => l.fold(0, (a, x) => a + f(x));
  switch (col) {
    case 'cash_handovers':
      var l = s.values(cashHandoverCodec);
      if (branch != null) l = l.where((h) => h.branch == branch).toList();
      return _box(context, moneyColor, [
        NumRow('إجمالي المفروض توريده', money(sum(l, (h) => h.expected))),
        NumRow('إجمالي المورّد فعلاً', money(sum(l, (h) => h.delivered))),
        NumRow('إجمالي الفروق', money(sum(l, (h) => h.difference)), bold: true),
        NumRow('عدد أيام فيها عجز', '${l.where((h) => h.status == 'عجز').length}'),
      ]);
    case 'safe_movements':
      final l = s.values(safeMovementCodec);
      return _box(context, moneyColor, [
        for (final t in SafeType.all) NumRow(t, money(sum(l.where((m) => m.type == t), (m) => m.amount))),
        NumRow('عدد الحركات (مستند ناقص)', '${l.where((m) => m.status == 'مستند ناقص').length}', color: dangerColor),
        NumRow('عدد الحركات (مستني تسجيل)', '${l.where((m) => m.status == 'مستني تسجيل').length}', color: warnColor),
      ]);
    case 'usd_transfers':
      final l = s.values(usdTransferCodec);
      final avg = averageRate(l);
      return _box(context, moneyColor, [
        NumRow('إجمالي الجنيه المدفوع', money(sum(l, (t) => t.egpPaid))),
        NumRow('إجمالي الدولار', '\$${fmtDec(sum(l, (t) => t.usdReceived))}'),
        NumRow('متوسط سعر الصرف', avg == null ? '-' : fmtDec(avg, 4)),
        NumRow('رسوم التحويل', money(sum(l, (t) => t.feesEgp))),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            icon: const Icon(Icons.account_balance),
            label: const Text('رصيد كل مورد بالدولار', style: TextStyle(fontSize: 16)),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UsdBalancesScreen())),
          ),
        ),
      ]);
    case 'customers':
      var l = s.values(customerCodec);
      if (branch != null) l = l.where((c) => c.branch == branch).toList();
      final a = agingSummary(l);
      String p(double v) => '${money(v)}  (${fmtPct(a.pct(v))})';
      return _box(context, moneyColor, [
        NumRow('0–30 يوم', p(a.b0to30)),
        NumRow('31–60', p(a.b31to60)),
        NumRow('61–90', p(a.b61to90)),
        NumRow('أكتر من 90', p(a.b90plus), color: a.b90plus > 0 ? dangerColor : null),
        NumRow('الإجمالي لينا عند العملاء', money(a.total), bold: true),
        NumRow('هدف التحصيل الأسبوع ده', money(a.weeklyTarget), bold: true),
      ]);
    case 'collections':
      final l = s.values(collectionCodec);
      return _box(context, moneyColor, [
        NumRow('إجمالي التحصيلات', money(sum(l, (c) => c.amount))),
        NumRow('منها نقدي', money(sum(l.where((c) => !c.isCheque), (c) => c.amount))),
        NumRow('شيكات في الخزنة لسه', money(sum(l.where((c) => c.isCheque && c.chequeState == ChequeState.inSafe), (c) => c.amount))),
        NumRow('شيكات مرتدة', money(sum(l.where((c) => c.chequeState == ChequeState.bounced), (c) => c.amount)), color: dangerColor),
      ]);
    case 'suppliers':
      final l = s.values(supplierCodec);
      return _box(context, moneyColor, [
        NumRow('الإجمالي بالجنيه', money(sum(l, (x) => x.totalEgp(s.usdRate)))),
        NumRow('منه متأخر', money(sum(l, (x) => x.lateEgp(s.usdRate))), color: warnColor),
        NumRow('الصافي علينا (بعد الدفعات المقدمة)', money(sum(l, (x) => x.netEgp(s.usdRate))), bold: true),
        NumRow('مطلوب سداده خلال 7 أيام', money(sum(l, (x) => x.dueIn7DaysEgp(s.usdRate, s.today))), bold: true),
        NumRow('سعر الدولار للتقييم', fmtDec(s.usdRate), note: 'بيتغير من الإعدادات'),
      ]);
    case 'advances':
      final m = DateTime(s.today.year, s.today.month, 1);
      final l = s.values(advanceCodec);
      return _box(context, moneyColor, [
        NumRow('إجمالي السلف', money(sum(l, (a) => a.amount))),
        NumRow('الباقي بعد مرتبات الشهر ده', money(sum(l, (a) => a.remainingAfter(m))), bold: true,
            note: 'لازم يساوي رصيد (ذمم العاملين) في السيستم'),
      ]);
    case 'fixed_expenses':
      final m = DateTime(s.today.year, s.today.month, 1);
      var l = s.values(fixedExpenseCodec).where((f) => f.month != null && f.month!.year == m.year && f.month!.month == m.month).toList();
      if (branch != null) l = l.where((f) => f.branch == branch).toList();
      return _box(context, moneyColor, [
        NumRow('الشهر ده: المتوقع', money(sum(l, (f) => f.expected))),
        NumRow('المدفوع فعلاً', money(sum(l, (f) => f.actual ?? 0))),
        NumRow('لسه ما اتدفعش (المتوقع)', money(sum(l.where((f) => !f.paid), (f) => f.expected)), bold: true),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            icon: const Icon(Icons.copy_all),
            label: const Text('انسخ بنود الشهر اللي فات للشهر ده', style: TextStyle(fontSize: 16)),
            onPressed: () => copyFixedToThisMonth(context, s),
          ),
        ),
      ]);
    case 'petty_expenses':
      final l = s.values(pettyExpenseCodec);
      return _box(context, moneyColor, [
        for (final b in branchOptions)
          if (branch == null || branch == b) ...[
            NumRow('عهدة $b', money(s.floatOf(b))),
            NumRow('  المصروف ولسه ما اتعوضش', money(pettyFloat(b, s.floatOf(b), l).unreimbursed)),
            NumRow('  الباقي في إيد المسؤول', money(pettyFloat(b, s.floatOf(b), l).remaining), bold: true),
          ],
        NumRow('محتاجة مراجعة', '${l.where((p) => p.status(s.pettyLimit) != 'تمام').length}', color: warnColor,
            note: 'حد المصروف من غير موافقة المالك: ${money(s.pettyLimit)}'),
      ]);
    case 'stock_transfers':
      final l = s.values(stockTransferCodec);
      return _box(context, goodsColor, [
        NumRow('لسه ما اتستلمتش', '${l.where((t) => t.receivedAt == null).length}'),
        NumRow('معلّقة أكتر من 48 ساعة', '${l.where((t) => t.isPendingOver48h(s.now)).length}', color: dangerColor),
        NumRow('تحويلات فيها فرق', '${l.where((t) => t.receivedAt != null && t.totalDifference != 0).length}', color: warnColor),
      ]);
  }
  return null;
}

Future<void> copyFixedToThisMonth(BuildContext context, AppState s) async {
  final m = DateTime(s.today.year, s.today.month, 1);
  final prev = DateTime(m.year, m.month - 1, 1);
  final all = s.values(fixedExpenseCodec);
  bool inM(FixedExpense f, DateTime x) => f.month != null && f.month!.year == x.year && f.month!.month == x.month;
  final have = all.where((f) => inM(f, m)).map((f) => '${f.name}|${f.branch}').toSet();
  final src = all.where((f) => inM(f, prev) && !have.contains('${f.name}|${f.branch}')).toList();
  if (src.isEmpty) {
    toast(context, 'مفيش بنود جديدة تتنسخ');
    return;
  }
  for (final f in src) {
    await s.add(fixedExpenseCodec, f.copyFor(m));
  }
  if (context.mounted) toast(context, 'اتنسخ ${src.length} بند للشهر ده ✔');
}

/// إضافات في شاشة التفاصيل
Widget? detailExtra(BuildContext context, String col, Stored st, AppState s) {
  switch (col) {
    case 'shipments':
      final r = (st.value as Shipment).calc();
      if (r.lines.isEmpty) return null;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionTitle('توزيع المصاريف على الأصناف (حسب القيمة)', color: goodsColor),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 16,
            columns: const [
              DataColumn(label: Text('الموديل')),
              DataColumn(label: Text('القطع'), numeric: true),
              DataColumn(label: Text('جنيه'), numeric: true),
              DataColumn(label: Text('النصيب'), numeric: true),
              DataColumn(label: Text('المصاريف'), numeric: true),
              DataColumn(label: Text('الواصلة'), numeric: true),
              DataColumn(label: Text('القطعة'), numeric: true),
              DataColumn(label: Text('البيع المقترح'), numeric: true),
              DataColumn(label: Text('ربح القطعة'), numeric: true),
            ],
            rows: [
              for (final l in r.lines)
                DataRow(cells: [
                  DataCell(Text(l.item.model)),
                  DataCell(Text(money(l.item.qty))),
                  DataCell(Text(money(l.totalEgp))),
                  DataCell(Text(fmtPct(l.share))),
                  DataCell(Text(money(l.allocated))),
                  DataCell(Text(money(l.landed))),
                  DataCell(Text(fmtDec(l.costPerPiece), style: const TextStyle(fontWeight: FontWeight.bold))),
                  DataCell(Text(money(l.suggestedPrice), style: const TextStyle(fontWeight: FontWeight.bold, color: goodsColor))),
                  DataCell(Text(fmtDec(l.profitPerPiece))),
                ]),
            ],
          ),
        ),
        NumRow('تحقق: المصاريف الموزعة = إجمالي المصاريف', r.check, color: statusColor(r.check)),
      ]);
    case 'customer_statements':
      final x = st.value as CustomerStatement;
      final bal = x.runningBalances;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionTitle('الكشف بالرصيد المتحرك'),
        NumRow('رصيد أول الفترة', money(x.opening)),
        for (var i = 0; i < x.lines.length; i++)
          NumRow('${fmtDate(x.lines[i].date)} ${x.lines[i].type} ${x.lines[i].docNo}',
              money(bal[i]), note: x.lines[i].debit != 0 ? 'عليه ${money(x.lines[i].debit)}' : 'دفع/مرتجع ${money(x.lines[i].credit)}'),
        NumRow('الرصيد آخر الفترة (المستحق على العميل)', money(x.closing), bold: true),
        const SizedBox(height: 8),
        MessageBox('كشف حساب ${x.customer} من ${fmtDate(x.from)} إلى ${fmtDate(x.to)}\n'
            'الرصيد أول الفترة: ${money(x.opening)}\n'
            'فواتير: ${money(x.totalDebit)}\n'
            'مدفوعات ومرتجعات: ${money(x.totalCredit)}\n'
            'الرصيد آخر الفترة: ${money(x.closing)}\n\n'
            '${x.confirmationText(fmtNum)}', title: 'الكشف + نص المصادقة'),
      ]);
    case 'customers':
      final c = st.value as Customer;
      final cols = s.values(collectionCodec).where((x) => x.customer == c.name).toList();
      if (cols.isEmpty) return null;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionTitle('تحصيلات العميل'),
        for (final x in cols) NumRow('${fmtDate(x.date)} ${x.isCheque ? 'شيك' : 'نقدي'}', money(x.amount)),
      ]);
  }
  return null;
}

/// رصيد كل مورد بالدولار (يتطابق شهريًا مع كشف حساب المورد)
class UsdBalancesScreen extends StatelessWidget {
  const UsdBalancesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final tr = s.values(usdTransferCodec);
    final names = {...tr.map((t) => t.supplier), ...s.values(supplierCodec).where((x) => x.isUsd).map((x) => x.name)}.where((n) => n.isNotEmpty);
    final saved = (s.setting<Map>(K.usdBalances) ?? const {}).cast<String, dynamic>();
    return Scaffold(
      appBar: AppBar(title: const Text('رصيد الموردين بالدولار')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        if (names.isEmpty) const EmptyHint('سجل تحويل دولار الأول'),
        for (final n in names)
          Builder(builder: (context) {
            final m = (saved[n] as Map?)?.cast<String, dynamic>() ?? {};
            final b = supplierUsdBalance(n, tr, (m['invoices'] as num?)?.toDouble() ?? 0, (m['statement'] as num?)?.toDouble());
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(n, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  NumRow('المحوّل له \$', fmtDec(b.transferred)),
                  _UsdInput(label: 'فواتيره \$', value: b.invoices, onSave: (v) => _saveUsd(s, n, 'invoices', v)),
                  NumRow('الرصيد \$ (موجب = دفعة مقدمة عنده)', fmtDec(b.balance), bold: true),
                  _UsdInput(label: 'رصيد كشفه \$', value: b.statement, onSave: (v) => _saveUsd(s, n, 'statement', v)),
                  NumRow('الفرق', b.difference == null ? '—' : fmtDec(b.difference!),
                      color: b.difference == null || b.difference == 0 ? okColor : dangerColor),
                ]),
              ),
            );
          }),
      ]),
    );
  }

  Future<void> _saveUsd(AppState s, String name, String key, double? v) async {
    final all = Map<String, dynamic>.from((s.setting<Map>(K.usdBalances) ?? const {}).cast<String, dynamic>());
    all[name] = {...((all[name] as Map?)?.cast<String, dynamic>() ?? {}), key: v};
    await s.set(K.usdBalances, all);
  }
}

class _UsdInput extends StatelessWidget {
  final String label;
  final double? value;
  final ValueChanged<double?> onSave;
  const _UsdInput({required this.label, required this.value, required this.onSave});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextFormField(
          initialValue: value == null ? '' : numText(value),
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          inputFormatters: [ThousandsFormatter()],
          decoration: InputDecoration(labelText: label),
          onChanged: (t) => onSave(parseNum(t)),
        ),
      );
}
