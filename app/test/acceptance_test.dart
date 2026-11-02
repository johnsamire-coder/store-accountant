// اختبارات القبول الأربعة اللي طلبها جون + مقارنة بنتايج الإكسل المحفوظة.
import 'package:flutter_test/flutter_test.dart';
import 'package:store_accountant/engine/cash.dart';
import 'package:store_accountant/engine/format.dart';
import 'package:store_accountant/engine/landed_cost.dart';
import 'package:store_accountant/engine/payroll_expenses.dart';

import 'workbook_example.dart';

void main() {
  group('اختبارات القبول الأربعة', () {
    test('1) التكلفة الواصلة: SH-101 → تكلفة القطعة 298.04', () {
      final r = calcLandedCost(
          rate: 50, profitMargin: 0.35, costs: shipmentCosts, items: shipmentItems);
      expect(shipmentCosts.total, 323000);
      final sh = r.lines.first;
      expect(sh.item.model, 'SH-101');
      expect(fmtDec(sh.costPerPiece), '298.04');
      expect(sh.costPerPiece, closeTo(298.040201005025, 1e-9));
    });

    test('2) توريد القاهرة: 11-01 مطابق، 11-02 عجز −100', () {
      final a = handovers[0], b = handovers[1];
      expect(a.expected, 40050);
      expect(a.difference, 0);
      expect(a.status, 'مطابق');
      expect(b.expected, 23900);
      expect(b.difference, -100);
      expect(b.status, 'عجز');
    });

    test('3) السلفة: 3,000 على 3 شهور من 2026-11 → 1,000 والباقي 2,000', () {
      final adv = advances.first;
      expect(adv.monthly, 1000);
      expect(adv.deductionFor(d(2026, 11, 1)), 1000);
      expect(adv.remainingAfter(d(2026, 11, 1)), 2000);
      expect(adv.lastMonth, d(2027, 1, 1));
      expect(
          adv.status(
              payrollMonth: d(2026, 11, 1), maxMultiple: 0.5, basicSalary: 6000),
          'بتتخصم');
    });

    test('4) كشف حساب العميل: 60,000 + 90,000 − 25,000 = 125,000', () {
      expect(statement.opening, 60000);
      expect(statement.totalDebit, 90000);
      expect(statement.totalCredit, 25000);
      expect(statement.closing, 125000);
      expect(statement.runningBalances, [110000, 88000, 85000, 125000]);
      expect(
          statement.confirmationText(fmtNum),
          'مصادقة: أقر أنا / محلات الأمل بأن رصيدي المستحق للمحل في 2026-11-02 '
          'هو 125,000 جنيه، وده صحيح ( ) — أو مش صحيح والصحيح هو ............ ( )');
    });
  });

  test('خزنة المالك في التقرير الأسبوعي = 1,043,850 زي الإكسل', () {
    final b = safeWeekBalance(
        opening: 1500000,
        from: d(2026, 11, 1),
        to: d(2026, 11, 7),
        handovers: handovers,
        movements: safeMovements,
        confirmed: 1043850);
    expect(b.handovers, 63850);
    expect(b.deposits, 0);
    expect(b.payments, 520000);
    expect(b.expected, 1043850);
    expect(b.difference, 0);
  });

  test('المرتبات بتاخد قسط السلفة لوحدها', () {
    final p = payrollLine(employees[1],
        payrollMonth: d(2026, 11, 1),
        advances: advances,
        commission: 1200,
        absenceDays: 1);
    expect(p.absenceDeduction, 200);
    expect(p.advances, 1000);
    expect(p.net, 6500);
  });
}
