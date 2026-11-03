import 'package:flutter/material.dart';

import '../app/alerts.dart';
import '../app/state.dart';
import '../data/codecs.dart';
import '../engine/customers.dart';
import '../engine/format.dart';
import '../engine/payroll_expenses.dart';
import 'common.dart';
import 'form.dart';
import 'payroll.dart';
import 'paste.dart';
import 'registers.dart';
import 'reports.dart';
import 'settings.dart';
import 'specs.dart';
import 'theme.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [const DashboardPage(), const GoodsPage(), const MoneyPage(), const PeoplePage(), const ReportsPage()];
    return Scaffold(
      body: SafeArea(child: pages[tab]),
      floatingActionButton: tab == 0 || tab == 2
          ? FloatingActionButton.extended(
              heroTag: 'quick',
              onPressed: () => showQuickAdd(context),
              icon: const Icon(Icons.add, size: 28),
              label: const Text('إضافة سريعة', style: TextStyle(fontSize: 18)),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined, color: goodsColor), selectedIcon: Icon(Icons.inventory_2, color: goodsColor), label: 'البضاعة'),
          NavigationDestination(icon: Icon(Icons.payments_outlined, color: moneyColor), selectedIcon: Icon(Icons.payments, color: moneyColor), label: 'الفلوس'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'الناس'),
          NavigationDestination(icon: Icon(Icons.assessment_outlined), selectedIcon: Icon(Icons.assessment), label: 'التقارير'),
        ],
      ),
    );
  }
}

/// إضافة سريعة: أي قيد في تلات دوسات (إضافة ← النوع ← حفظ)
void showQuickAdd(BuildContext context) {
  final items = <(IconData, String, Color, VoidCallback)>[
    (Icons.content_paste_go, 'لصق من الواتساب', moneyColor, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PasteScreen()))),
    (Icons.payments, 'توريد نقدية', moneyColor, () => openNew(context, cashHandoverSpec)),
    (Icons.account_balance_wallet, 'حركة خزنة المالك', moneyColor, () => openNew(context, safeMovementSpec)),
    (Icons.request_quote, 'تحصيل / شيك', moneyColor, () => openNew(context, collectionSpec)),
    (Icons.shopping_bag, 'مصروف نثري', moneyColor, () => openNew(context, pettyExpenseSpec)),
    (Icons.currency_exchange, 'تحويل دولار', moneyColor, () => openNew(context, usdTransferSpec)),
    (Icons.local_shipping, 'تحويل مخزني', goodsColor, () => openNew(context, stockTransferSpec)),
  ];
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), children: [
        for (final it in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: BigTile(
              icon: it.$1,
              label: it.$2,
              color: it.$3,
              onTap: () {
                Navigator.pop(ctx);
                it.$4();
              },
            ),
          ),
      ]),
    ),
  );
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final alerts = s.alerts();
    final groups = <String, List<AppAlert>>{};
    for (final a in alerts) {
      groups.putIfAbsent(a.group, () => []).add(a);
    }
    return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 100), children: [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('حساباتي', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            Text(dayName(s.today), style: const TextStyle(fontSize: 15)),
          ]),
        ),
        IconButton(
          tooltip: 'الإعدادات',
          iconSize: 30,
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          icon: const Icon(Icons.settings),
        ),
      ]),
      SectionTitle(alerts.isEmpty ? 'تنبيهات النهارده: مفيش ✔' : 'تنبيهات النهارده (${alerts.length})',
          color: alerts.isEmpty ? okColor : dangerColor),
      for (final g in AlertGroups.order)
        if (groups[g] != null)
          Card(
            elevation: 0,
            color: dangerColor.withValues(alpha: 0.06),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: dangerColor.withValues(alpha: 0.25))),
            child: ExpansionTile(
              initiallyExpanded: groups[g]!.length <= 3,
              shape: const Border(),
              leading: CircleAvatar(
                backgroundColor: groups[g]!.any((a) => a.level == AlertLevel.high) ? dangerColor : warnColor,
                foregroundColor: Colors.white,
                child: Text('${groups[g]!.length}'),
              ),
              title: Text(g, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              children: [
                for (final a in groups[g]!)
                  ListTile(
                    leading: Icon(a.level == AlertLevel.high ? Icons.error : Icons.warning_amber,
                        color: a.level == AlertLevel.high ? dangerColor : warnColor),
                    title: Text(a.title),
                    subtitle: Text(a.detail),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => a.id == null ? openCollection(context, a.collection) : openRecord(context, a.collection, a.id!),
                  ),
              ],
            ),
          ),
      const SectionTitle('الفلوس', color: moneyColor),
      _KeyNumbers(s),
      const SectionTitle('البضاعة', color: goodsColor),
      _GoodsNumbers(s),
    ]);
  }
}

class _KeyNumbers extends StatelessWidget {
  final AppState s;
  const _KeyNumbers(this.s);
  @override
  Widget build(BuildContext context) {
    final h = s.values(cashHandoverCodec);
    final c = s.values(customerCodec);
    final a = agingSummary(c);
    final sup = s.values(supplierCodec);
    final col = s.values(collectionCodec);
    final petty = s.values(pettyExpenseCodec);
    double sum<T>(Iterable<T> l, double Function(T) f) => l.fold(0, (x, y) => x + f(y));
    final rows = <Widget>[];
    for (final b in branchOptions) {
      final l = h.where((x) => x.branch == b).toList()..sort((x, y) => y.date.compareTo(x.date));
      if (l.isEmpty) continue;
      final last = l.first;
      rows.add(NumRow('آخر توريد $b (${fmtDate(last.date)})', '${money(last.delivered)} من ${money(last.expected)}',
          color: statusColor(last.status), onTap: () => openRecord(context, cashHandoverCodec.collection, s.all(cashHandoverCodec).firstWhere((x) => x.value == last).id)));
    }
    rows.addAll([
      NumRow('لينا عند العملاء', money(a.total), onTap: () => openCollection(context, customerCodec.collection)),
      NumRow('منه متأخر +90', money(a.b90plus), color: a.b90plus > 0 ? dangerColor : null, onTap: () => openCollection(context, customerCodec.collection)),
      NumRow('هدف التحصيل الأسبوع ده', money(a.weeklyTarget)),
      NumRow('شيكات في الخزنة', money(sum(col.where((x) => x.isCheque && x.chequeState == ChequeState.inSafe), (x) => x.amount)),
          onTap: () => openCollection(context, collectionCodec.collection)),
      NumRow('علينا للموردين (الصافي)', money(sum(sup, (x) => x.netEgp(s.usdRate))), onTap: () => openCollection(context, supplierCodec.collection)),
      NumRow('مطلوب سداده خلال 7 أيام', money(sum(sup, (x) => x.dueIn7DaysEgp(s.usdRate, s.today))), bold: true,
          onTap: () => openCollection(context, supplierCodec.collection)),
      for (final b in branchOptions)
        NumRow('الباقي في عهدة $b', money(pettyFloat(b, s.floatOf(b), petty).remaining), onTap: () => openCollection(context, pettyExpenseCodec.collection)),
    ]);
    return Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Column(children: rows)));
  }
}

class _GoodsNumbers extends StatelessWidget {
  final AppState s;
  const _GoodsNumbers(this.s);
  @override
  Widget build(BuildContext context) {
    final t = s.values(stockTransferCodec);
    final lc = s.lastStockCount;
    final sh = s.values(shipmentCodec);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(children: [
          NumRow('تحويلات لسه ما اتستلمتش', '${t.where((x) => x.receivedAt == null).length}', onTap: () => openCollection(context, stockTransferCodec.collection)),
          NumRow('عدد الشحنات', '${sh.length}', onTap: () => openCollection(context, shipmentCodec.collection)),
          if (lc != null)
            NumRow('آخر جرد (${lc.place} ${fmtDate(lc.date)})', 'مطابق ${fmtPct(lc.matchRatio)} — فرق ${money(lc.totalValue)}',
                onTap: () => openCollection(context, stockCountCodec.collection)),
        ]),
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  final String title;
  final List<(IconData, String, String?, Color, VoidCallback)> items;
  const _Menu(this.title, this.items);
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 100), children: [
        Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        for (final it in items)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: BigTile(icon: it.$1, label: it.$2, sub: it.$3, color: it.$4, onTap: it.$5)),
      ]);
}

(IconData, String, String?, Color, VoidCallback) _reg(BuildContext c, AppState s, EntitySpec spec, [String? sub]) =>
    (spec.icon, spec.title, sub ?? '${spec.storedIn(s).length} سجل', spec.color, () => openCollection(c, spec.codec.collection));

class GoodsPage extends StatelessWidget {
  const GoodsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return _Menu('البضاعة', [
      _reg(context, s, shipmentSpec, 'ملف لكل شحنة + تكلفة القطعة وسعر البيع'),
      _reg(context, s, stockTransferSpec, 'المحوّل مقابل المستلم والفروق'),
      _reg(context, s, stockCountSpec, 'عيّنة مفاجئة أو جرد شامل'),
    ]);
  }
}

class MoneyPage extends StatelessWidget {
  const MoneyPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return _Menu('الفلوس', [
      (Icons.content_paste_go, 'لصق من الواتساب', 'رسالة المالك ← قيد جاهز', moneyColor,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PasteScreen()))),
      _reg(context, s, cashHandoverSpec),
      _reg(context, s, safeMovementSpec),
      _reg(context, s, usdTransferSpec),
      _reg(context, s, collectionSpec),
      _reg(context, s, pettyExpenseSpec),
      _reg(context, s, fixedExpenseSpec),
      (Icons.pie_chart, 'ملخص المصروفات', 'مقابل الميزانية', moneyColor,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpenseSummaryScreen()))),
    ]);
  }
}

class PeoplePage extends StatelessWidget {
  const PeoplePage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return _Menu('العملاء والموردين والموظفين', [
      _reg(context, s, customerSpec, 'الحدود والأعمار والتنبيهات'),
      _reg(context, s, statementSpec, 'كشف + نص مصادقة'),
      _reg(context, s, supplierSpec, 'الأرصدة والمستحق خلال أسبوع'),
      (Icons.request_page, 'كشف المرتبات', '${s.values(employeeCodec).length} موظف', moneyColor,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PayrollScreen()))),
      _reg(context, s, advanceSpec, 'الأقساط بتتخصم لوحدها'),
      _reg(context, s, employeeSpec),
    ]);
  }
}
