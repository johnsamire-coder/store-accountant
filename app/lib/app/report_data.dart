// التقارير من بيانات التطبيق — نفس الحساب للشاشة وللإكسل وللـ PDF.
import '../data/codecs.dart';
import '../engine/excel.dart';
import '../engine/reports.dart';
import 'state.dart';

ByBranch bb(Object? j) {
  final m = (j as Map?)?.cast<String, dynamic>() ?? const {};
  return ByBranch((m['c'] as num?)?.toDouble() ?? 0, (m['p'] as num?)?.toDouble() ?? 0);
}

Map<String, double> bbJson(ByBranch b) => {'c': b.cairo, 'p': b.portSaid};

DailyManual dailyManualFrom(Map<String, dynamic> mj) => DailyManual(
      creditSales: bb(mj['creditSales']),
      returns: bb(mj['returns']),
      chequeCollections: bb(mj['chequeCollections']),
      cancelledInvoices: (mj['cancelledInvoices'] as num?)?.toInt() ?? 0,
      creditOverLimit: (mj['creditOverLimit'] as num?)?.toInt() ?? 0,
      returnsCount: (mj['returnsCount'] as num?)?.toInt() ?? 0,
      pendingTransfers: (mj['pendingTransfers'] as num?)?.toInt() ?? 0,
    );

DailyReport dailyFor(AppState s, DateTime d) => dailyReport(
      date: d,
      today: s.today,
      handovers: s.values(cashHandoverCodec),
      collections: s.values(collectionCodec),
      safe: s.values(safeMovementCodec),
      petty: s.values(pettyExpenseCodec),
      pettyLimit: s.pettyLimit,
      manual: dailyManualFrom(s.manual(K.daily(d))),
    );

/// الأسبوع من الحد للسبت (زي مثال الإكسل: 2026-11-01 الحد ← 2026-11-07 السبت)
DateTime weekStart(DateTime d) {
  final x = dateOnly(d);
  return x.subtract(Duration(days: x.weekday % 7));
}

WeeklyManual weeklyManualFor(AppState s, DateTime from) {
  final mj = s.manual(K.weekly(from));
  final prev = s.manual(K.weekly(from.subtract(const Duration(days: 7))));
  final lastConfirmed = (prev['ownerConfirmed'] as num?)?.toDouble();
  return WeeklyManual(
    creditSales: bb(mj['creditSales']),
    returns: bb(mj['returns']),
    lastWeekNet: mj.containsKey('lastWeekNet') ? bb(mj['lastWeekNet']) : bb(prev['netSales']),
    safeOpening: (mj['safeOpening'] as num?)?.toDouble() ?? lastConfirmed ?? 0,
    ownerConfirmed: (mj['ownerConfirmed'] as num?)?.toDouble(),
  );
}

WeeklyReport weeklyFor(AppState s, DateTime start) {
  final from = weekStart(start);
  return weeklyReport(
    from: from,
    to: from.add(const Duration(days: 6)),
    today: s.today,
    handovers: s.values(cashHandoverCodec),
    collections: s.values(collectionCodec),
    customers: s.values(customerCodec),
    suppliers: s.values(supplierCodec),
    usdRate: s.usdRate,
    safe: s.values(safeMovementCodec),
    lastCount: s.lastStockCount,
    manual: weeklyManualFor(s, from),
  );
}

MonthlyManual monthlyManualFrom(Map<String, dynamic> j) => MonthlyManual(
      cashSales: bb(j['cashSales']),
      creditSales: bb(j['creditSales']),
      returns: bb(j['returns']),
      cogs: bb(j['cogs']),
      collections: bb(j['collections']),
      customersBalance: bb(j['customersBalance']),
      customersOver90: bb(j['customersOver90']),
      stockAtCost: bb(j['stockAtCost']),
      stockShortage: bb(j['stockShortage']),
      deliveredToSafe: bb(j['deliveredToSafe']),
      usdTransferred: (j['usdTransferred'] as num?)?.toDouble() ?? 0,
      chinaSupplierUsd: (j['chinaSupplierUsd'] as num?)?.toDouble() ?? 0,
    );

MonthlyReport monthlyFor(AppState s, DateTime m) => monthlyReport(
      manual: monthlyManualFrom(s.manual(K.monthly(m))),
      expenseSummary: s.expenseSummaryFor(m),
      suppliers: s.values(supplierCodec),
      usdRate: s.usdRate,
    );
