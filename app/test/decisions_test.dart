// قرارات جون اللي بتختلف عن الإكسل (2026-11-03).
import 'package:flutter_test/flutter_test.dart';
import 'package:store_accountant/engine/cash.dart';
import 'package:store_accountant/engine/payroll_expenses.dart';
import 'package:store_accountant/engine/reports.dart';

import 'workbook_example.dart';

void main() {
  test('قرار 1: فرع فيه عجز توريد بيتعد فعلاً (الإكسل كان بيبص على سطر فاضي)', () {
    final r = dailyReport(
      date: d(2026, 11, 2),
      today: savedOn,
      handovers: handovers,
      collections: const [],
      safe: const [],
      petty: const [],
      pettyLimit: pettyLimit,
    );
    expect(r.handoverDiff.cairo, -100);
    expect(r.shortageBranches, 1);
    expect(r.message, contains('اتورد لخزنتك: 23,800 — فيه فرق -100'));
    expect(r.message, contains('عدد التنبيهات: 1 (التفاصيل في التقرير)'));
  });

  test('قرار 2: آخر قسط ياخد الباقي — 1,000 على 3 = 333 / 333 / 334', () {
    final a = Advance(
        date: d(2026, 10, 1),
        employeeCode: 'ع-01',
        amount: 1000,
        installments: 3,
        firstMonth: d(2026, 11, 1),
        ownerApproved: true);
    expect(a.monthly, 333);
    expect([
      a.deductionFor(d(2026, 10, 1)),
      a.deductionFor(d(2026, 11, 1)),
      a.deductionFor(d(2026, 12, 1)),
      a.deductionFor(d(2027, 1, 1)),
      a.deductionFor(d(2027, 2, 1)),
    ], [0, 333, 333, 334, 0]);
    expect(a.remainingAfter(d(2026, 12, 1)), 334);
    expect(a.remainingAfter(d(2027, 1, 1)), 0);
    expect(a.status(payrollMonth: d(2027, 1, 1), maxMultiple: 0.5, basicSalary: 9000),
        'اتسددت');
  });

  test('قرار 2: مبلغ صغير ما يخصمش أكتر من السلفة', () {
    final a = Advance(
        date: d(2026, 10, 1),
        employeeCode: 'x',
        amount: 2,
        installments: 4,
        firstMonth: d(2026, 11, 1),
        ownerApproved: true);
    final ds = [for (var m = 11; m <= 14; m++) a.deductionFor(DateTime(2026, m, 1))];
    expect(ds.fold<double>(0, (s, v) => s + v), 2);
    expect(ds.every((v) => v >= 0), true);
  });

  test('قرار 4: أرقام اليومي اللي بتتكتب بالإيد ما بتتحسبش لوحدها', () {
    // فيه شيك في السجل وتحويل معلّق، بس اليومي بياخد اللي جون كتبه بس
    final r = dailyReport(
      date: d(2026, 11, 2),
      today: savedOn,
      handovers: handovers,
      collections: collections,
      safe: const [],
      petty: const [],
      pettyLimit: pettyLimit,
    );
    expect(r.chequeCollections.total, 0);
    expect(r.pendingTransfers, 0);
    expect(SafeType.all.length, 5);
  });
}
