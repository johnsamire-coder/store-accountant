// تطبيق كامل في الذاكرة بمثال الإكسل (للاختبارات)
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:store_accountant/app/state.dart';
import 'package:store_accountant/data/codecs.dart';
import 'package:store_accountant/data/store.dart';
import 'package:store_accountant/engine/cash.dart';
import 'package:store_accountant/engine/payroll_expenses.dart';

import 'workbook_example.dart';

/// ساعة الاختبار: يوم الحفظ في الإكسل الساعة 10 الصبح
DateTime testNow() => DateTime(2026, 11, 3, 10);

Future<AppState> makeState({bool seed = true, bool withPin = true, DateTime Function()? clock}) async {
  sqfliteFfiInit();
  final store = await LocalStore.open(databaseFactoryFfiNoIsolate, inMemoryDatabasePath, clock: clock ?? testNow, singleInstance: false);
  final s = AppState(store, clock: clock ?? testNow);
  await s.load();
  if (seed) await seedAll(s);
  if (!withPin) {
    await s.set(K.pinHash, null);
  }
  return s;
}

Future<void> seedAll(AppState s) async {
  await s.add(shipmentCodec, Shipment(no: 'ش-2026-01', date: d(2026, 10, 30), rate: 50, costs: shipmentCosts, items: shipmentItems));
  for (final x in handovers) {
    await s.add(cashHandoverCodec, x);
  }
  for (final x in safeMovements) {
    await s.add(safeMovementCodec, x);
  }
  for (final x in usdTransfers) {
    await s.add(usdTransferCodec, x);
  }
  for (final x in customers) {
    await s.add(customerCodec, x);
  }
  await s.add(statementCodec, statement);
  for (final x in collections) {
    await s.add(collectionCodec, x);
  }
  for (final x in suppliers) {
    await s.add(supplierCodec, x);
  }
  await s.add(stockCountCodec, stockCount);
  for (final x in employees) {
    await s.add(employeeCodec, x);
  }
  for (final e in payrollInputs.entries) {
    await s.add(payrollEntryCodec, PayrollEntry(month: d(2026, 11, 1), employeeCode: e.key, commission: e.value.$1, absenceDays: e.value.$2, insurance: e.value.$3));
  }
  for (final x in advances) {
    await s.add(advanceCodec, x);
  }
  for (final f in fixedExpenses) {
    await s.add(fixedExpenseCodec, FixedExpense(month: d(2026, 11, 1), name: f.name, category: f.category, branch: f.branch, expected: f.expected, dueDay: f.dueDay, paid: f.paid, actual: f.actual, receiptNo: f.receiptNo));
  }
  for (final x in petty) {
    await s.add(pettyExpenseCodec, x);
  }
  await s.add(stockTransferCodec, StockTransfer(no: 'ت-0001', sentAt: DateTime(2026, 11, 1, 9), lines: const [
    TransferLine(code: 'SH-101-BL-L', model: 'قميص كاجوال', color: 'أزرق', size: 'L', sent: 60),
    TransferLine(code: 'SH-101-BL-XL', model: 'قميص كاجوال', color: 'أزرق', size: 'XL', sent: 40),
  ]));
  await s.set(K.usdBalances, {
    'Guangzhou Textile Co.': {'invoices': 34000, 'statement': 1000}
  });
  // التقرير الأسبوعي والشهري واليومي بنفس الأرقام اليدوية اللي في الإكسل
  await s.set(K.daily(d(2026, 11, 1)), {
    'creditSales': {'c': 45000, 'p': 30000},
    'returns': {'c': -3000, 'p': 0},
    'chequeCollections': {'c': 10000, 'p': 0},
    'returnsCount': 1,
  });
  await s.set(K.weekly(d(2026, 11, 1)), {
    'creditSales': {'c': 600000, 'p': 850000},
    'returns': {'c': -8000, 'p': -5000},
    'lastWeekNet': {'c': 600000, 'p': 700000},
    'safeOpening': 1500000,
    'ownerConfirmed': 1043850,
  });
  await s.set(K.monthly(d(2026, 11, 1)), {
    'cashSales': {'c': 300000, 'p': 450000},
    'creditSales': {'c': 700000, 'p': 1050000},
    'returns': {'c': -20000, 'p': -30000},
    'cogs': {'c': -650000, 'p': -980000},
    'collections': {'c': 650000, 'p': 900000},
    'customersBalance': {'c': 1200000, 'p': 1600000},
    'customersOver90': {'c': 90000, 'p': 120000},
    'stockAtCost': {'c': 2500000, 'p': 4000000},
    'stockShortage': {'c': 3000, 'p': 0},
    'deliveredToSafe': {'c': 950000, 'p': 1300000},
    'usdTransferred': 35000,
    'chinaSupplierUsd': 1000,
  });
}
