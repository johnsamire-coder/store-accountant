// شيتات (التقرير اليومي) + (التقرير الأسبوعي) + (التقرير الشهري) ورسايل الواتساب.
import 'cash.dart';
import 'customers.dart';
import 'excel.dart';
import 'format.dart';
import 'payables_stock.dart';
import 'payroll_expenses.dart';

const cairo = 'القاهرة';
const portSaid = 'بورسعيد';
const _portSaidName = portSaid;
const branches = [cairo, portSaid];

/// رقم لكل فرع + الإجمالي
class ByBranch {
  final double cairo, portSaid;
  const ByBranch(this.cairo, this.portSaid);
  double get total => cairo + portSaid;
  double of(String b) => b == _portSaidName ? portSaid : cairo;
  ByBranch operator +(ByBranch o) =>
      ByBranch(cairo + o.cairo, portSaid + o.portSaid);
}

ByBranch _sumBy<T>(Iterable<T> l, String Function(T) br, double Function(T) v) {
  var c = 0.0, p = 0.0;
  for (final x in l) {
    if (br(x) == portSaid) {
      p += v(x);
    } else if (br(x) == cairo) {
      c += v(x);
    }
  }
  return ByBranch(c, p);
}

double _ratio(double cash, double credit) =>
    cash + credit == 0 ? 0 : credit / (cash + credit);

bool _inRange(DateTime d, DateTime from, DateTime to) =>
    !dateOnly(d).isBefore(dateOnly(from)) && !dateOnly(d).isAfter(dateOnly(to));

// ═════════ التقرير اليومي ═════════
class DailyManual {
  final ByBranch creditSales; // مبيعات آجل (من السيستم)
  final ByBranch returns; // مردودات (بالسالب)
  final ByBranch chequeCollections; // تحصيلات بشيكات
  final int cancelledInvoices; // فواتير اتلغت
  final int creditOverLimit; // بيع آجل لعميل متجاوز أو متأخر
  final int returnsCount; // مرتجعات
  final int pendingTransfers; // تحويلات معلّقة +48 ساعة
  const DailyManual({
    this.creditSales = const ByBranch(0, 0),
    this.returns = const ByBranch(0, 0),
    this.chequeCollections = const ByBranch(0, 0),
    this.cancelledInvoices = 0,
    this.creditOverLimit = 0,
    this.returnsCount = 0,
    this.pendingTransfers = 0,
  });
}

class DailyReport {
  final DateTime date;
  final ByBranch cashSales, creditSales, returns, cashCollections,
      chequeCollections, petty, expected, delivered;
  final int cancelledInvoices, creditOverLimit, returnsCount,
      pendingTransfers, shortageBranches, chequesDue2Days, safeMissingDocs,
      pettyNeedsReview;
  const DailyReport({
    required this.date,
    required this.cashSales,
    required this.creditSales,
    required this.returns,
    required this.cashCollections,
    required this.chequeCollections,
    required this.petty,
    required this.expected,
    required this.delivered,
    required this.cancelledInvoices,
    required this.creditOverLimit,
    required this.returnsCount,
    required this.pendingTransfers,
    required this.shortageBranches,
    required this.chequesDue2Days,
    required this.safeMissingDocs,
    required this.pettyNeedsReview,
  });

  ByBranch get netSales => cashSales + creditSales + returns; // صف 10
  double creditRatio(String? b) => b == null
      ? _ratio(cashSales.total, creditSales.total)
      : _ratio(cashSales.of(b), creditSales.of(b)); // صف 11
  ByBranch get handoverDiff => ByBranch(delivered.cairo - expected.cairo,
      delivered.portSaid - expected.portSaid); // صف 17
  int get alertsCount =>
      cancelledInvoices +
      creditOverLimit +
      returnsCount +
      pendingTransfers +
      shortageBranches +
      chequesDue2Days +
      safeMissingDocs +
      pettyNeedsReview;

  /// A30: رسالة الواتساب
  String get message {
    final n = netSales, d = handoverDiff.total, a = alertsCount;
    return 'تقرير يوم ${fmtDate(date)}\n'
        'صافي المبيعات: ${fmtNum(n.total)} (القاهرة ${fmtNum(n.cairo)} / بورسعيد ${fmtNum(n.portSaid)})\n'
        'نسبة الآجل: ${fmtPct(creditRatio(null))}\n'
        'التحصيلات: ${fmtNum(cashCollections.total + chequeCollections.total)} (نقدي ${fmtNum(cashCollections.total)} / شيكات ${fmtNum(chequeCollections.total)})\n'
        'اتورد لخزنتك: ${fmtNum(delivered.total)}${d == 0 ? ' — مطابق' : ' — فيه فرق ${fmtNum(d)}'}\n'
        'عدد التنبيهات: $a${a == 0 ? '' : ' (التفاصيل في التقرير)'}';
  }
}

DailyReport dailyReport({
  required DateTime date,
  required DateTime today,
  required List<CashHandover> handovers,
  required List<Collection> collections,
  required List<SafeMovement> safe,
  required List<PettyExpense> petty,
  required double pettyLimit,
  DailyManual manual = const DailyManual(),
}) {
  final h = handovers.where((x) => dateOnly(x.date) == dateOnly(date));
  final diff = _sumBy(h, (x) => x.branch, (x) => x.difference);
  return DailyReport(
    date: date,
    cashSales: _sumBy(h, (x) => x.branch, (x) => x.cashSales),
    creditSales: manual.creditSales,
    returns: manual.returns,
    cashCollections: _sumBy(h, (x) => x.branch, (x) => x.collections),
    chequeCollections: manual.chequeCollections,
    petty: _sumBy(h, (x) => x.branch, (x) => x.petty),
    expected: _sumBy(h, (x) => x.branch, (x) => x.expected),
    delivered: _sumBy(h, (x) => x.branch, (x) => x.delivered),
    cancelledInvoices: manual.cancelledInvoices,
    creditOverLimit: manual.creditOverLimit,
    returnsCount: manual.returnsCount,
    pendingTransfers: manual.pendingTransfers,
    // ملحوظة: في الإكسل المعادلة بتبص على صف 18 الفاضي؛ هنا بنعد فعلاً الفروع اللي فيها عجز (صف 17)
    shortageBranches: [diff.cairo, diff.portSaid].where((v) => v < 0).length,
    chequesDue2Days: collections.where((c) {
      final d = c.daysLeft(today);
      return d != null && d >= 0 && d <= 2;
    }).length,
    safeMissingDocs: safe.where((m) => m.status == 'مستند ناقص').length,
    pettyNeedsReview:
        petty.where((p) => p.status(pettyLimit) != 'تمام').length,
  );
}

// ═════════ التقرير الأسبوعي ═════════
class WeeklyManual {
  final ByBranch creditSales, returns, lastWeekNet;
  final double safeOpening;
  final double? ownerConfirmed;
  const WeeklyManual({
    this.creditSales = const ByBranch(0, 0),
    this.returns = const ByBranch(0, 0),
    this.lastWeekNet = const ByBranch(0, 0),
    this.safeOpening = 0,
    this.ownerConfirmed,
  });
}

class WeeklyReport {
  final DateTime from, to;
  final ByBranch cashSales, creditSales, returns, lastWeekNet;
  final double collections, cashCollections, chequeCollections, target;
  final AgingSummary aging;
  final int overLimitCount, over90Count;
  final double chequesDueNextWeek, bouncedCheques;
  final double suppliersNet, suppliersLate, suppliersDue7;
  final int shortageDays;
  final double handoverDiffTotal;
  final SafeWeekBalance safe;
  final int safeMissingDocs;
  final double stockMatchRatio, stockDiffValue;
  const WeeklyReport({
    required this.from,
    required this.to,
    required this.cashSales,
    required this.creditSales,
    required this.returns,
    required this.lastWeekNet,
    required this.collections,
    required this.cashCollections,
    required this.chequeCollections,
    required this.target,
    required this.aging,
    required this.overLimitCount,
    required this.over90Count,
    required this.chequesDueNextWeek,
    required this.bouncedCheques,
    required this.suppliersNet,
    required this.suppliersLate,
    required this.suppliersDue7,
    required this.shortageDays,
    required this.handoverDiffTotal,
    required this.safe,
    required this.safeMissingDocs,
    required this.stockMatchRatio,
    required this.stockDiffValue,
  });

  ByBranch get netSales => cashSales + creditSales + returns; // صف 11
  double creditRatio(String? b) => b == null
      ? _ratio(cashSales.total, creditSales.total)
      : _ratio(cashSales.of(b), creditSales.of(b));
  double change(String? b) {
    final last = b == null ? lastWeekNet.total : lastWeekNet.of(b);
    final now = b == null ? netSales.total : netSales.of(b);
    return last == 0 ? 0 : now / last - 1; // صف 14
  }

  double get targetRatio => target == 0 ? 0 : collections / target; // صف 22

  /// A61: رسالة الواتساب يوم الخميس
  String get message => 'التقرير الأسبوعي من ${fmtDate(from)} لـ ${fmtDate(to)}\n'
      'صافي المبيعات: ${fmtNum(netSales.total)} (${fmtSignedPct(change(null))} عن الأسبوع اللي فات)\n'
      'التحصيل: ${fmtNum(collections)} من هدف ${fmtNum(target)} (${fmtPct(targetRatio)})\n'
      'لينا عند العملاء: ${fmtNum(aging.total)} — منه متأخر +90: ${fmtNum(aging.b90plus)}\n'
      'علينا للموردين (بعد الدفعات المقدمة): ${fmtNum(suppliersNet)} — مطلوب خلال أسبوع: ${fmtNum(suppliersDue7)}\n'
      'رصيد خزنتك حسب الحسابات: ${fmtNum(safe.expected)} — ده صح؟\n'
      '${safeMissingDocs > 0 ? 'محتاج صور مستندات لعدد $safeMissingDocs حركة' : 'كل الحركات مستنداتها كاملة'}';
}

WeeklyReport weeklyReport({
  required DateTime from,
  required DateTime to,
  required DateTime today,
  required List<CashHandover> handovers,
  required List<Collection> collections,
  required List<Customer> customers,
  required List<Supplier> suppliers,
  required double usdRate,
  required List<SafeMovement> safe,
  StockCount? lastCount,
  WeeklyManual manual = const WeeklyManual(),
}) {
  final h = handovers.where((x) => _inRange(x.date, from, to));
  final col = collections.where((c) => _inRange(c.date, from, to));
  double s<T>(Iterable<T> l, double Function(T) f) =>
      l.fold<double>(0, (a, x) => a + f(x));
  return WeeklyReport(
    from: from,
    to: to,
    cashSales: _sumBy(h, (x) => x.branch, (x) => x.cashSales),
    creditSales: manual.creditSales,
    returns: manual.returns,
    lastWeekNet: manual.lastWeekNet,
    collections: s(col, (c) => c.amount),
    cashCollections: s(col.where((c) => !c.isCheque), (c) => c.amount),
    chequeCollections: s(col.where((c) => c.isCheque), (c) => c.amount),
    target: s(customers, (c) => c.weeklyTarget),
    aging: agingSummary(customers),
    overLimitCount:
        customers.where((c) => c.alert == CustomerAlert.overLimit).length,
    over90Count: customers.where((c) => c.alert == CustomerAlert.over90).length,
    chequesDueNextWeek: s(collections.where((c) {
      final d = c.daysLeft(today);
      return d != null && d >= 0 && d <= 7;
    }), (c) => c.amount),
    bouncedCheques: s(
        collections.where((c) => c.chequeState == ChequeState.bounced),
        (c) => c.amount),
    suppliersNet: s(suppliers, (x) => x.netEgp(usdRate)),
    suppliersLate: s(suppliers, (x) => x.lateEgp(usdRate)),
    suppliersDue7: s(suppliers, (x) => x.dueIn7DaysEgp(usdRate, today)),
    shortageDays: h.where((x) => x.status == 'عجز').length,
    handoverDiffTotal: s(h, (x) => x.difference),
    safe: safeWeekBalance(
        opening: manual.safeOpening,
        from: from,
        to: to,
        handovers: handovers,
        movements: safe,
        confirmed: manual.ownerConfirmed),
    safeMissingDocs: safe.where((m) => m.status == 'مستند ناقص').length,
    stockMatchRatio: lastCount?.matchRatio ?? 0,
    stockDiffValue: lastCount?.totalValue ?? 0,
  );
}

// ═════════ التقرير الشهري (أرباح وخسائر لكل فرع) ═════════
class MonthlyManual {
  final ByBranch cashSales, creditSales, returns, cogs; // cogs و returns بالسالب
  final ByBranch collections, customersBalance, customersOver90;
  final ByBranch stockAtCost, stockShortage, deliveredToSafe;
  final double usdTransferred, chinaSupplierUsd;
  const MonthlyManual({
    this.cashSales = const ByBranch(0, 0),
    this.creditSales = const ByBranch(0, 0),
    this.returns = const ByBranch(0, 0),
    this.cogs = const ByBranch(0, 0),
    this.collections = const ByBranch(0, 0),
    this.customersBalance = const ByBranch(0, 0),
    this.customersOver90 = const ByBranch(0, 0),
    this.stockAtCost = const ByBranch(0, 0),
    this.stockShortage = const ByBranch(0, 0),
    this.deliveredToSafe = const ByBranch(0, 0),
    this.usdTransferred = 0,
    this.chinaSupplierUsd = 0,
  });
}

class MonthlyReport {
  final MonthlyManual m;
  final ByBranch rent, payroll, otherExpenses; // بالسالب
  final double suppliersNet, suppliersLate;
  const MonthlyReport(this.m, this.rent, this.payroll, this.otherExpenses,
      this.suppliersNet, this.suppliersLate);

  ByBranch get netSales => m.cashSales + m.creditSales + m.returns; // 10
  ByBranch get grossProfit => netSales + m.cogs; // 12
  ByBranch get netProfit => grossProfit + rent + payroll + otherExpenses; // 18
  double _r(double a, double b) => b == 0 ? 0 : a / b;
  double grossMargin(String? b) => b == null
      ? _r(grossProfit.total, netSales.total)
      : _r(grossProfit.of(b), netSales.of(b));
  double netMargin(String? b) => b == null
      ? _r(netProfit.total, netSales.total)
      : _r(netProfit.of(b), netSales.of(b));
  double creditRatio(String? b) => b == null
      ? _ratio(m.cashSales.total, m.creditSales.total)
      : _ratio(m.cashSales.of(b), m.creditSales.of(b));
  double collectionRatio(String? b) => b == null
      ? _r(m.collections.total, m.creditSales.total)
      : _r(m.collections.of(b), m.creditSales.of(b));
  double over90Ratio(String? b) => b == null
      ? _r(m.customersOver90.total, m.customersBalance.total)
      : _r(m.customersOver90.of(b), m.customersBalance.of(b));

  /// المخزون يكفي كام يوم بيع
  double stockDays(String? b) {
    final cogs = b == null ? m.cogs.total : m.cogs.of(b);
    final st = b == null ? m.stockAtCost.total : m.stockAtCost.of(b);
    return cogs == 0 ? 0 : st / (-cogs / 30);
  }
}

MonthlyReport monthlyReport({
  required MonthlyManual manual,
  required List<BudgetLine> expenseSummary,
  required List<Supplier> suppliers,
  required double usdRate,
}) {
  BudgetLine line(String n) => expenseSummary.firstWhere((l) => l.item == n,
      orElse: () => BudgetLine(n, 0, 0, 0));
  final totC = expenseSummary.fold<double>(0, (s, l) => s + l.cairo);
  final totP = expenseSummary.fold<double>(0, (s, l) => s + l.portSaid);
  final sal = line('مرتبات وأجور'), com = line('عمولات وحوافز'),
      rent = line('إيجارات');
  return MonthlyReport(
    manual,
    ByBranch(-rent.cairo, -rent.portSaid),
    ByBranch(-(sal.cairo + com.cairo), -(sal.portSaid + com.portSaid)),
    ByBranch(-(totC - sal.cairo - com.cairo - rent.cairo),
        -(totP - sal.portSaid - com.portSaid - rent.portSaid)),
    suppliers.fold(0, (s, x) => s + x.netEgp(usdRate)),
    suppliers.fold(0, (s, x) => s + x.lateEgp(usdRate)),
  );
}
