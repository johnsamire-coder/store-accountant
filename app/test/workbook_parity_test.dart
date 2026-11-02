// مقارنة كل نتيجة في التطبيق بالنتيجة المحفوظة في ملف الإكسل (شيت بشيت).
import 'package:flutter_test/flutter_test.dart';
import 'package:store_accountant/engine/cash.dart';
import 'package:store_accountant/engine/customers.dart';
import 'package:store_accountant/engine/format.dart';
import 'package:store_accountant/engine/landed_cost.dart';
import 'package:store_accountant/engine/payroll_expenses.dart';
import 'package:store_accountant/engine/reports.dart';

import 'workbook_example.dart';

List<PayrollLine> payroll() => [
      for (final e in employees)
        payrollLine(e,
            payrollMonth: d(2026, 11, 1),
            advances: advances,
            commission: payrollInputs[e.code]!.$1,
            absenceDays: payrollInputs[e.code]!.$2,
            insurance: payrollInputs[e.code]!.$3),
    ];

List<BudgetLine> summary() {
  final p = payroll();
  return expenseSummary(
      cairo: branchPayroll(cairo, p),
      portSaid: branchPayroll(portSaid, p),
      fixed: fixedExpenses,
      petty: petty,
      budgets: budgets);
}

void main() {
  test('شيت التكلفة الواصلة', () {
    final r = calcLandedCost(
        rate: 50, profitMargin: 0.35, costs: shipmentCosts, items: shipmentItems);
    expect(r.lines.map((l) => l.costPerPiece).toList(), [
      closeTo(298.040201005025, 1e-9),
      closeTo(463.618090452261, 1e-9),
      closeTo(145.708542713568, 1e-9),
      closeTo(993.467336683417, 1e-9),
    ]);
    expect(r.lines.map((l) => l.suggestedPrice).toList(), [403, 626, 197, 1342]);
    expect(r.lines[3].profitPerPiece, closeTo(348.532663316583, 1e-9));
    expect(r.totalAllocated, closeTo(323000, 1e-6));
    expect(r.totalLanded, closeTo(1318000, 1e-6));
    expect(r.check, 'مطابق');
    expect(r.costsRatio, closeTo(0.324623115577889, 1e-12));
  });

  test('شيت إذن تحويل مخزني', () {
    final t = StockTransfer(no: 'ت-0001', sentAt: d(2026, 11, 5), receivedAt: d(2026, 11, 5), lines: const [
      TransferLine(code: 'SH-101-BL-L', sent: 60, received: 60),
      TransferLine(code: 'SH-101-BL-XL', sent: 40, received: 39),
    ]);
    expect(t.lines[0].difference, 0);
    expect(t.lines[0].note, '');
    expect(t.lines[1].difference, -1);
    expect(t.lines[1].note, 'عجز — محضر فرق');
    expect([t.totalSent, t.totalReceived, t.totalDifference], [100, 99, -1]);
    expect(t.isPendingOver48h(DateTime(2026, 11, 7, 1)), false); // اتستلم
    final pending = StockTransfer(no: 'ت-2', sentAt: DateTime(2026, 11, 5, 10), lines: const []);
    expect(pending.isPendingOver48h(DateTime(2026, 11, 7, 10)), false);
    expect(pending.isPendingOver48h(DateTime(2026, 11, 7, 11)), true);
  });

  test('شيت سجل خزنة المالك', () {
    expect(safeMovements[0].status, 'تمام');
    expect(safeMovements[1].status, 'مستند ناقص');
    final s = SafeMovement(date: d(2026, 11, 1), type: SafeType.broker, amount: 1, hasDocument: true);
    expect(s.status, 'مستني تسجيل');
  });

  test('شيت تحويلات الدولار', () {
    expect(usdTransfers[0].rate, 50);
    expect(usdTransfers[0].rateWithFees, closeTo(50.075, 1e-9));
    expect(usdTransfers[1].rate, closeTo(50.6666666666667, 1e-9));
    expect(usdTransfers[1].rateWithFees, closeTo(50.7333333333333, 1e-9));
    expect(averageRate(usdTransfers), closeTo(50.2857142857143, 1e-9));
    expect(averageRate(usdTransfers, shipmentNo: 'ش-2026-01'),
        closeTo(50.2857142857143, 1e-9));
    final b = supplierUsdBalance('Guangzhou Textile Co.', usdTransfers, 34000, 1000);
    expect([b.transferred, b.invoices, b.balance, b.difference], [35000, 34000, 1000, 0]);
  });

  test('شيت العملاء والأعمار', () {
    expect(customers.map((c) => c.balance).toList(), [120000, 110000, 95000]);
    expect(customers.map((c) => c.limitUse).toList(), [0.8, 1.1, 1.1875]);
    expect(customers.map((c) => c.alert).toList(),
        ['سليم', 'متأخر +90 — وقف البيع الآجل', 'متجاوز الحد']);
    final a = agingSummary(customers);
    expect([a.b0to30, a.b31to60, a.b61to90, a.b90plus, a.total, a.weeklyTarget],
        [205000, 65000, 20000, 35000, 325000, 90000]);
    expect(a.pct(a.b0to30), closeTo(0.630769230769231, 1e-12));
  });

  test('شيت التحصيلات والشيكات', () {
    expect(collections[1].daysLeft(savedOn), 42);
    expect(collections[0].daysLeft(savedOn), null);
  });

  test('شيت الموردين واللي علينا', () {
    final today = savedOn;
    expect(suppliers.map((s) => s.totalEgp(50)).toList(), [0, 50000, 15000]);
    expect(suppliers.map((s) => s.netEgp(50)).toList(), [-50000, 50000, 15000]);
    expect(suppliers.map((s) => s.dueIn7DaysEgp(50, today)).toList(), [0, 50000, 15000]);
    expect(suppliers.map((s) => s.status).toList(), ['منتظم', 'متأخر', 'منتظم']);
    expect(suppliers.fold<double>(0, (s, x) => s + x.lateEgp(50)), 50000);
  });

  test('شيت الجرد', () {
    expect(stockCount.lines.map((l) => l.status).toList(), ['مطابق', 'عجز']);
    expect([stockCount.totalSystem, stockCount.totalActual, stockCount.totalDifference, stockCount.totalValue],
        [75, 73, -2, -818]);
    expect(stockCount.matchRatio, 0.5);
  });

  test('شيت المرتبات', () {
    final p = payroll();
    expect(p.map((l) => l.net).toList(), [11500, 6500, 6700, 7700, 5200]);
    expect(p.map((l) => l.deductions).toList(), [0, 1200, 200, 0, 2400]);
    final c = branchPayroll(cairo, p), ps = branchPayroll(portSaid, p);
    expect([c.count, c.salariesAndAllowances, c.commissions, c.net], [3, 22500, 3600, 24700]);
    expect([ps.count, ps.salariesAndAllowances, ps.commissions, ps.net], [2, 14200, 1100, 12900]);
  });

  test('شيت السلف', () {
    final m = d(2026, 11, 1);
    expect(advances[1].lastMonth, d(2026, 11, 1));
    expect(advances[1].remainingAfter(m), 0);
    expect(advances[1].status(payrollMonth: m, maxMultiple: 0.5, basicSalary: 6000), 'اتسددت');
    expect(Advance(date: m, employeeCode: 'x', amount: 10, installments: 1, firstMonth: m)
        .status(payrollMonth: m, maxMultiple: 0.5, basicSalary: 6000), 'مستنية موافقة المالك');
    expect(Advance(date: m, employeeCode: 'x', amount: 3001, installments: 1, firstMonth: m, ownerApproved: true)
        .status(payrollMonth: m, maxMultiple: 0.5, basicSalary: 6000), 'فوق الحد المسموح');
  });

  test('شيت المصروفات الثابتة', () {
    expect(fixedExpenses.map((f) => f.status).toList(), [
      'تمام', 'تمام', 'أعلى من المتوقع — يتسأل', 'لسه ما اتدفعش', 'تمام', 'تمام', 'تمام'
    ]);
    expect(fixedExpenses[2].difference, 700);
    expect(fixedExpenses.where((f) => !f.paid).fold<double>(0, (s, f) => s + f.expected), 4000);
  });

  test('شيت النثريات والمصروفات', () {
    expect(petty.map((p) => p.status(pettyLimit)).toList(),
        ['تمام', 'تمام', 'فاتورة ناقصة', 'تمام']);
    final c = pettyFloat(cairo, 3000, petty), p = pettyFloat(portSaid, 3000, petty);
    expect([c.unreimbursed, c.remaining], [2650, 350]);
    expect([p.unreimbursed, p.remaining], [1200, 1800]);
    expect(petty.fold<double>(0, (s, x) => s + x.amount), 3850);
  });

  test('شيت ملخص المصروفات', () {
    final s = summary();
    expect(s.map((l) => l.total).toList(),
        [36700, 4700, 55000, 4200, 800, 2500, 1800, 1200, 600, 250, 1500, 0]);
    expect(s.map((l) => l.variance).toList(),
        [-11300, -300, 0, -3800, -200, 0, 800, -1800, -400, -1250, 0, -1000]);
    expect(s.where((l) => l.note.isNotEmpty).map((l) => l.item).toList(), ['صيانة']);
    expect(s.fold<double>(0, (a, l) => a + l.cairo), 60250);
    expect(s.fold<double>(0, (a, l) => a + l.portSaid), 49000);
  });

  test('شيت التقرير اليومي + رسالة الواتساب حرف بحرف', () {
    final r = dailyReport(
      date: d(2026, 11, 1),
      today: savedOn,
      handovers: handovers,
      collections: collections,
      safe: safeMovements,
      petty: petty,
      pettyLimit: pettyLimit,
      manual: const DailyManual(
          creditSales: ByBranch(45000, 30000),
          returns: ByBranch(-3000, 0),
          chequeCollections: ByBranch(10000, 0),
          returnsCount: 1),
    );
    expect(r.netSales.cairo, 60500);
    expect(r.netSales.total, 90500);
    expect(r.creditRatio(cairo), closeTo(0.708661417322835, 1e-12));
    expect(r.creditRatio(portSaid), 1);
    expect(r.expected.total, 40050);
    expect(r.handoverDiff.total, 0);
    expect(r.alertsCount, 3);
    expect(
        r.message,
        'تقرير يوم 2026-11-01\nصافي المبيعات: 90,500 (القاهرة 60,500 / بورسعيد 30,000)\n'
        'نسبة الآجل: 80%\nالتحصيلات: 32,000 (نقدي 22,000 / شيكات 10,000)\n'
        'اتورد لخزنتك: 40,050 — مطابق\nعدد التنبيهات: 3 (التفاصيل في التقرير)');
  });

  test('شيت التقرير الأسبوعي + رسالة الخميس حرف بحرف', () {
    final r = weeklyReport(
      from: d(2026, 11, 1),
      to: d(2026, 11, 7),
      today: savedOn,
      handovers: handovers,
      collections: collections,
      customers: customers,
      suppliers: suppliers,
      usdRate: 50,
      safe: safeMovements,
      lastCount: stockCount,
      manual: const WeeklyManual(
          creditSales: ByBranch(600000, 850000),
          returns: ByBranch(-8000, -5000),
          lastWeekNet: ByBranch(600000, 700000),
          safeOpening: 1500000,
          ownerConfirmed: 1043850),
    );
    expect(r.cashSales.cairo, 33700);
    expect(r.netSales.total, 1470700);
    expect(r.change(null), closeTo(0.131307692307692, 1e-12));
    expect([r.collections, r.cashCollections, r.chequeCollections, r.target], [52000, 22000, 30000, 90000]);
    expect(r.targetRatio, closeTo(0.577777777777778, 1e-12));
    expect([r.overLimitCount, r.over90Count], [1, 1]);
    expect([r.chequesDueNextWeek, r.bouncedCheques], [0, 0]);
    expect([r.suppliersNet, r.suppliersLate, r.suppliersDue7], [15000, 50000, 65000]);
    expect([r.shortageDays, r.handoverDiffTotal], [1, -100]);
    expect(r.safe.expected, 1043850);
    expect(r.safe.difference, 0);
    expect(r.safeMissingDocs, 1);
    expect([r.stockMatchRatio, r.stockDiffValue], [0.5, -818]);
    expect(
        r.message,
        'التقرير الأسبوعي من 2026-11-01 لـ 2026-11-07\n'
        'صافي المبيعات: 1,470,700 (+13% عن الأسبوع اللي فات)\n'
        'التحصيل: 52,000 من هدف 90,000 (58%)\n'
        'لينا عند العملاء: 325,000 — منه متأخر +90: 35,000\n'
        'علينا للموردين (بعد الدفعات المقدمة): 15,000 — مطلوب خلال أسبوع: 65,000\n'
        'رصيد خزنتك حسب الحسابات: 1,043,850 — ده صح؟\n'
        'محتاج صور مستندات لعدد 1 حركة');
  });

  test('شيت التقرير الشهري (أرباح وخسائر لكل فرع)', () {
    final r = monthlyReport(
      manual: const MonthlyManual(
        cashSales: ByBranch(300000, 450000),
        creditSales: ByBranch(700000, 1050000),
        returns: ByBranch(-20000, -30000),
        cogs: ByBranch(-650000, -980000),
        collections: ByBranch(650000, 900000),
        customersBalance: ByBranch(1200000, 1600000),
        customersOver90: ByBranch(90000, 120000),
        stockAtCost: ByBranch(2500000, 4000000),
        stockShortage: ByBranch(3000, 0),
        deliveredToSafe: ByBranch(950000, 1300000),
        usdTransferred: 35000,
        chinaSupplierUsd: 1000,
      ),
      expenseSummary: summary(),
      suppliers: suppliers,
      usdRate: 50,
    );
    expect([r.netSales.cairo, r.netSales.portSaid, r.netSales.total], [980000, 1470000, 2450000]);
    expect([r.grossProfit.cairo, r.grossProfit.portSaid], [330000, 490000]);
    expect([r.rent.cairo, r.payroll.cairo, r.otherExpenses.cairo], [-25000, -26100, -9150]);
    expect([r.rent.portSaid, r.payroll.portSaid, r.otherExpenses.portSaid], [-30000, -15300, -3700]);
    expect([r.netProfit.cairo, r.netProfit.portSaid, r.netProfit.total], [269750, 441000, 710750]);
    expect(r.netMargin(null), closeTo(0.290102040816327, 1e-12));
    expect(r.grossMargin(cairo), closeTo(0.336734693877551, 1e-12));
    expect(r.grossMargin(portSaid), closeTo(0.333333333333333, 1e-12));
    expect(r.netMargin(portSaid), closeTo(0.3, 1e-12));
    expect(r.collectionRatio(portSaid), closeTo(0.857142857142857, 1e-12));
    expect(r.stockDays(portSaid), closeTo(122.448979591837, 1e-9));
    expect(r.collectionRatio(cairo), closeTo(0.928571428571429, 1e-12));
    expect(r.over90Ratio(null), 0.075);
    expect(r.stockDays(null), closeTo(119.631901840491, 1e-9));
    expect([r.suppliersNet, r.suppliersLate], [15000, 50000]);
  });

  test('تنسيق الأرقام', () {
    expect(fmtNum(1250000), '1,250,000');
    expect(fmtNum(-100), '-100');
    expect(fmtNum(0), '0');
    expect(fmtPct(0.577777), '58%');
    expect(fmtSignedPct(0.1313), '+13%');
    expect(fmtSignedPct(-0.05), '-5%');
    expect(fmtDec(298.040201), '298.04');
  });
}
