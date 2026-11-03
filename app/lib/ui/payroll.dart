import 'package:flutter/material.dart';

import '../app/state.dart';
import '../data/codecs.dart';
import '../engine/payroll_expenses.dart';
import 'common.dart';
import 'form.dart';
import 'specs.dart';
import 'theme.dart';

class MonthPicker extends StatelessWidget {
  final DateTime month;
  final ValueChanged<DateTime> onChanged;
  const MonthPicker({super.key, required this.month, required this.onChanged});
  @override
  Widget build(BuildContext context) => Row(children: [
        IconButton.filledTonal(
            onPressed: () => onChanged(DateTime(month.year, month.month - 1, 1)), icon: const Icon(Icons.chevron_right), tooltip: 'الشهر اللي فات'),
        Expanded(child: Center(child: Text(monthName(month), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)))),
        IconButton.filledTonal(
            onPressed: () => onChanged(DateTime(month.year, month.month + 1, 1)), icon: const Icon(Icons.chevron_left), tooltip: 'الشهر الجاي'),
      ]);
}

/// كشف المرتبات الشهري (م-19): السلف بتتخصم لوحدها
class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});
  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  DateTime? month;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final m = month ?? DateTime(s.today.year, s.today.month, 1);
    final lines = s.payroll(m);
    final entries = s.all(payrollEntryCodec).where((e) => e.value.month.year == m.year && e.value.month.month == m.month).toList();
    double sum(double Function(PayrollLine) f) => lines.fold(0, (a, l) => a + f(l));
    return Scaffold(
      appBar: AppBar(title: const Text('كشف المرتبات')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'emp',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EntityForm(spec: employeeSpec))),
        icon: const Icon(Icons.person_add),
        label: const Text('موظف جديد'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 100), children: [
        MonthPicker(month: m, onChanged: (v) => setState(() => month = v)),
        if (lines.isEmpty) const EmptyHint('ضيف الموظفين الأول (الزرار اللي تحت)'),
        for (final l in lines)
          Builder(builder: (context) {
            final e = entries.where((x) => x.value.employeeCode == l.emp.code).firstOrNull;
            return Card(
              child: InkWell(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => EntityForm(
                              spec: payrollEntrySpec,
                              id: e?.id,
                              initial: e == null ? {'month': m.toIso8601String(), 'employeeCode': l.emp.code} : null,
                            ))),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(child: Text('${l.emp.code} — ${l.emp.name}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
                      StatusChip(e?.value.signed == true ? 'مضى' : 'لسه ما مضاش'),
                    ]),
                    Text('${l.emp.job} — ${l.emp.branch}'),
                    NumRow('إجمالي المستحق (أساسي + بدلات + عمولة)', money(l.gross)),
                    NumRow('خصم الغياب (${numText(l.absenceDays)} يوم)', money(l.absenceDeduction)),
                    if (l.penalties != 0) NumRow('جزاءات وتأخير', money(l.penalties)),
                    NumRow('سلف بتتخصم الشهر ده', money(l.advances), note: 'من سجل السلف لوحدها'),
                    if (l.insurance != 0) NumRow('تأمينات', money(l.insurance)),
                    NumRow('الصافي اللي هيقبضه', money(l.net), bold: true, color: moneyColor),
                  ]),
                ),
              ),
            );
          }),
        if (lines.isNotEmpty) ...[
          const SectionTitle('الإجمالي'),
          NumRow('إجمالي المستحق', money(sum((l) => l.gross))),
          NumRow('إجمالي الخصومات', money(sum((l) => l.deductions))),
          NumRow('إجمالي الصافي', money(sum((l) => l.net)), bold: true),
          const SectionTitle('ملخص حسب الفرع (بيروح لملخص المصروفات)'),
          for (final b in branchOptions)
            Builder(builder: (_) {
              final bp = branchPayroll(b, lines);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(children: [
                    NumRow(b, '${bp.count} موظف', bold: true),
                    NumRow('المرتبات + البدلات', money(bp.salariesAndAllowances)),
                    NumRow('العمولات والحوافز', money(bp.commissions)),
                    NumRow('الصافي المصروف', money(bp.net)),
                  ]),
                ),
              );
            }),
        ],
      ]),
    );
  }
}

/// ملخص مصروفات الشهر مقابل الميزانية
class ExpenseSummaryScreen extends StatefulWidget {
  const ExpenseSummaryScreen({super.key});
  @override
  State<ExpenseSummaryScreen> createState() => _ExpenseSummaryScreenState();
}

class _ExpenseSummaryScreenState extends State<ExpenseSummaryScreen> {
  DateTime? month;
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final m = month ?? DateTime(s.today.year, s.today.month, 1);
    final lines = s.expenseSummaryFor(m);
    double t(double Function(BudgetLine) f) => lines.fold(0, (a, l) => a + f(l));
    return Scaffold(
      appBar: AppBar(title: const Text('ملخص المصروفات مقابل الميزانية')),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 40), children: [
        MonthPicker(month: m, onChanged: (v) => setState(() => month = v)),
        const SizedBox(height: 8),
        for (final l in lines)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text(l.item, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
                  if (l.note.isNotEmpty) StatusChip(l.note),
                ]),
                NumRow('القاهرة / بورسعيد', '${money(l.cairo)} / ${money(l.portSaid)}'),
                NumRow('الإجمالي', money(l.total), bold: true),
                NumRow('الميزانية الشهرية', money(l.budget), onTap: () => _editBudget(context, s, l.item, l.budget)),
                NumRow('الفرق عن الميزانية', money(l.variance), color: l.variance > 0 ? dangerColor : okColor),
              ]),
            ),
          ),
        const SectionTitle('إجمالي المصروفات'),
        NumRow('القاهرة', money(t((l) => l.cairo))),
        NumRow('بورسعيد', money(t((l) => l.portSaid))),
        NumRow('الإجمالي', money(t((l) => l.total)), bold: true),
        NumRow('الميزانية', money(t((l) => l.budget))),
        NumRow('الفرق', money(t((l) => l.variance)), bold: true),
      ]),
    );
  }

  Future<void> _editBudget(BuildContext context, AppState s, String item, double cur) async {
    final c = TextEditingController(text: numText(cur));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('ميزانية: $item'),
        content: TextField(controller: c, autofocus: true, keyboardType: TextInputType.number, inputFormatters: [ThousandsFormatter()]),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx, parseNum(c.text)), child: const Text('حفظ'))],
      ),
    );
    if (v == null) return;
    final b = Map<String, dynamic>.from(s.budgets);
    b[item] = v;
    await s.set(K.budgets, b);
  }
}
