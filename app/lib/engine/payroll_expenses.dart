// شيت (المرتبات) + (السلف) + (المصروفات الثابتة) + (النثريات والمصروفات) + (ملخص المصروفات).
import 'excel.dart';

DateTime _month(DateTime d) => DateTime(d.year, d.month, 1);

// ───────── السلف (م-18) ─────────
class Advance {
  final DateTime date;
  final String employeeCode;
  final double amount; // D
  final int installments; // E
  final DateTime firstMonth; // G
  final bool ownerApproved; // K
  const Advance({
    required this.date,
    required this.employeeCode,
    required this.amount,
    required this.installments,
    required this.firstMonth,
    this.ownerApproved = false,
  });

  /// F = ROUND(D/E,0)
  double get monthly => installments == 0 ? 0 : xRound(amount / installments);

  /// H = EDATE(G, E−1)
  DateTime get lastMonth => eDate(_month(firstMonth), installments - 1);

  /// عدد الأقساط اللي اتخصمت لحد شهر المرتبات (شامل الشهر نفسه)
  int paidCount(DateTime payrollMonth) {
    final n = (payrollMonth.year - firstMonth.year) * 12 +
        payrollMonth.month -
        firstMonth.month +
        1;
    return n < 0 ? 0 : (n > installments ? installments : n);
  }

  /// I: الباقي بعد مرتبات الشهر
  double remainingAfter(DateTime payrollMonth) {
    final r = amount - monthly * paidCount(payrollMonth);
    return r < 0 ? 0 : r;
  }

  /// القسط اللي بيتخصم في شهر معين (L في المرتبات)
  double deductionFor(DateTime payrollMonth) {
    final m = _month(payrollMonth);
    return (!_month(firstMonth).isAfter(m) && !lastMonth.isBefore(m))
        ? monthly
        : 0;
  }

  /// J: الحالة. maxMultiple = أقصى سلفة كام مرة من الأساسي (D4)
  String status(
      {required DateTime payrollMonth,
      required double maxMultiple,
      required double basicSalary}) {
    if (!ownerApproved) return 'مستنية موافقة المالك';
    if (amount > maxMultiple * basicSalary) return 'فوق الحد المسموح';
    return remainingAfter(payrollMonth) == 0 ? 'اتسددت' : 'بتتخصم';
  }
}

// ───────── المرتبات (م-19) ─────────
class Employee {
  final String code, name, job, branch;
  final DateTime? hiredOn;
  final double basic, allowances;
  const Employee({
    required this.code,
    required this.name,
    this.job = '',
    this.branch = 'القاهرة',
    this.hiredOn,
    required this.basic,
    this.allowances = 0,
  });
}

class PayrollLine {
  final Employee emp;
  final double commission, absenceDays, penalties, insurance;
  final double advances; // L محسوبة من السلف
  const PayrollLine(this.emp, this.commission, this.absenceDays,
      this.penalties, this.insurance, this.advances);

  double get absenceDeduction => xRound(emp.basic / 30 * absenceDays); // J
  double get gross => emp.basic + emp.allowances + commission; // N
  double get deductions =>
      absenceDeduction + penalties + advances + insurance; // O
  double get net => gross - deductions; // P
}

PayrollLine payrollLine(
  Employee e, {
  required DateTime payrollMonth,
  required List<Advance> advances,
  double commission = 0,
  double absenceDays = 0,
  double penalties = 0,
  double insurance = 0,
}) {
  final adv = advances
      .where((a) => a.employeeCode == e.code)
      .fold<double>(0, (s, a) => s + a.deductionFor(payrollMonth));
  return PayrollLine(e, commission, absenceDays, penalties, insurance, adv);
}

class BranchPayroll {
  final String branch;
  final int count;
  final double salariesAndAllowances, commissions, net;
  const BranchPayroll(this.branch, this.count, this.salariesAndAllowances,
      this.commissions, this.net);
}

BranchPayroll branchPayroll(String branch, List<PayrollLine> lines) {
  final l = lines.where((x) => x.emp.branch == branch);
  return BranchPayroll(
    branch,
    l.length,
    l.fold(0, (s, x) => s + x.emp.basic + x.emp.allowances),
    l.fold(0, (s, x) => s + x.commission),
    l.fold(0, (s, x) => s + x.net),
  );
}

// ───────── البنود ─────────
const expenseCategories = [
  'إيجارات',
  'كهرباء ومياه',
  'نت وتليفونات',
  'أمن ونظافة',
  'صيانة',
  'نقل بين المخازن',
  'دعاية',
  'ضيافة ونثريات',
  'اشتراك السيستم',
  'أخرى',
];

// ───────── المصروفات الثابتة (م-20) ─────────
class FixedExpense {
  final String name, category, branch, receiptNo;
  final double expected; // D
  final int dueDay; // E
  final bool paid; // F
  final double? actual; // G
  const FixedExpense({
    required this.name,
    required this.category,
    required this.branch,
    required this.expected,
    required this.dueDay,
    this.paid = false,
    this.actual,
    this.receiptNo = '',
  });

  /// H
  double? get difference => paid ? (actual ?? 0) - expected : null;

  /// J
  String get status {
    if (!paid) return 'لسه ما اتدفعش';
    if (receiptNo.isEmpty) return 'إيصال ناقص';
    if ((difference ?? 0) > 0) return 'أعلى من المتوقع — يتسأل';
    return 'تمام';
  }
}

// ───────── النثريات (م-15) ─────────
class PettyExpense {
  final DateTime date;
  final String branch, category, note, invoiceNo, approvedBy;
  final double amount;
  final bool hasInvoice, reimbursed;
  const PettyExpense({
    required this.date,
    required this.branch,
    required this.category,
    this.note = '',
    required this.amount,
    this.hasInvoice = false,
    this.invoiceNo = '',
    this.approvedBy = '',
    this.reimbursed = false,
  });

  /// J. limit = حد المصروف من غير موافقة المالك (C4)
  String status(double limit) {
    if (!hasInvoice) return 'فاتورة ناقصة';
    if (amount > limit && approvedBy != 'صاحب المحل') {
      return 'فوق الحد — محتاج موافقة المالك';
    }
    return 'تمام';
  }
}

class PettyFloat {
  final String branch;
  final double float, unreimbursed;
  const PettyFloat(this.branch, this.float, this.unreimbursed);
  double get remaining => float - unreimbursed; // الباقي في إيد المسؤول
}

PettyFloat pettyFloat(String branch, double float, List<PettyExpense> l) =>
    PettyFloat(
        branch,
        float,
        l
            .where((e) => e.branch == branch && !e.reimbursed)
            .fold(0, (s, e) => s + e.amount));

// ───────── ملخص المصروفات مقابل الميزانية ─────────
class BudgetLine {
  final String item;
  final double cairo, portSaid, budget;
  const BudgetLine(this.item, this.cairo, this.portSaid, this.budget);
  double get total => cairo + portSaid;
  double get variance => total - budget;
  String get note => budget == 0
      ? ''
      : (total > budget * 1.1 ? 'أعلى من الميزانية بأكتر من 10%' : '');
}

/// صفوف 6..17 من ملخص المصروفات
List<BudgetLine> expenseSummary({
  required BranchPayroll cairo,
  required BranchPayroll portSaid,
  required List<FixedExpense> fixed,
  required List<PettyExpense> petty,
  required Map<String, double> budgets,
}) {
  double sumFor(String cat, String br) =>
      fixed
          .where((f) => f.category == cat && f.branch == br)
          .fold<double>(0, (s, f) => s + (f.actual ?? 0)) +
      petty
          .where((p) => p.category == cat && p.branch == br)
          .fold<double>(0, (s, p) => s + p.amount);
  return [
    BudgetLine('مرتبات وأجور', cairo.salariesAndAllowances,
        portSaid.salariesAndAllowances, budgets['مرتبات وأجور'] ?? 0),
    BudgetLine('عمولات وحوافز', cairo.commissions, portSaid.commissions,
        budgets['عمولات وحوافز'] ?? 0),
    for (final c in expenseCategories)
      BudgetLine(c, sumFor(c, 'القاهرة'), sumFor(c, 'بورسعيد'),
          budgets[c] ?? 0),
  ];
}
