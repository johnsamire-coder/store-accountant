// شيت (العملاء والأعمار) + (كشف حساب عميل) + (التحصيلات والشيكات).
import 'excel.dart';

class CustomerAlert {
  static const over90 = 'متأخر +90 — وقف البيع الآجل';
  static const overLimit = 'متجاوز الحد';
  static const over60 = 'متأخر +60 — موافقة المالك';
  static const ok = 'سليم';
}

class Customer {
  final String code, name, phone, branch, followUpBy;
  final double creditLimit; // E
  final int paymentDays; // F
  final double b0to30, b31to60, b61to90, b90plus; // G..J
  final DateTime? lastCollection; // N
  final double weeklyTarget; // O
  const Customer({
    required this.code,
    required this.name,
    this.phone = '',
    this.branch = 'القاهرة',
    this.followUpBy = '',
    required this.creditLimit,
    this.paymentDays = 30,
    this.b0to30 = 0,
    this.b31to60 = 0,
    this.b61to90 = 0,
    this.b90plus = 0,
    this.lastCollection,
    this.weeklyTarget = 0,
  });

  /// K
  double get balance => b0to30 + b31to60 + b61to90 + b90plus;

  /// L
  double? get limitUse => creditLimit == 0 ? null : balance / creditLimit;

  /// M (نفس ترتيب الأولوية في الإكسل)
  String get alert {
    if (b90plus > 0) return CustomerAlert.over90;
    if (balance > creditLimit) return CustomerAlert.overLimit;
    if (b61to90 > 0) return CustomerAlert.over60;
    return CustomerAlert.ok;
  }
}

class AgingSummary {
  final double b0to30, b31to60, b61to90, b90plus, total, weeklyTarget;
  const AgingSummary(this.b0to30, this.b31to60, this.b61to90, this.b90plus,
      this.total, this.weeklyTarget);
  double pct(double v) => total == 0 ? 0 : v / total; // صف 67
}

AgingSummary agingSummary(List<Customer> cs) {
  double s(double Function(Customer) f) => cs.fold(0, (a, c) => a + f(c));
  return AgingSummary(s((c) => c.b0to30), s((c) => c.b31to60),
      s((c) => c.b61to90), s((c) => c.b90plus), s((c) => c.balance),
      s((c) => c.weeklyTarget));
}

// ───────── كشف حساب عميل ─────────
class StatementLine {
  final DateTime date;
  final String type, docNo, note;
  final double debit; // مدين (عليه)
  final double credit; // دائن (دفع / مرتجع)
  const StatementLine({
    required this.date,
    required this.type,
    this.docNo = '',
    this.note = '',
    this.debit = 0,
    this.credit = 0,
  });
}

class CustomerStatement {
  final String customer;
  final DateTime from, to;
  final double opening;
  final List<StatementLine> lines;
  const CustomerStatement({
    required this.customer,
    required this.from,
    required this.to,
    required this.opening,
    required this.lines,
  });

  /// G: الرصيد المتحرك بعد كل سطر
  List<double> get runningBalances {
    var b = opening;
    return [for (final l in lines) b = b + l.debit - l.credit];
  }

  double get totalDebit => lines.fold(0, (s, l) => s + l.debit);
  double get totalCredit => lines.fold(0, (s, l) => s + l.credit);

  /// G50
  double get closing => opening + totalDebit - totalCredit;

  /// A52: نص المصادقة
  String confirmationText(String Function(double) fmt) =>
      'مصادقة: أقر أنا / $customer بأن رصيدي المستحق للمحل في '
      '${_ymd(to)} هو ${fmt(closing)} جنيه، وده صحيح ( ) — أو مش صحيح '
      'والصحيح هو ............ ( )';
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ───────── التحصيلات والشيكات (م-12) ─────────
class ChequeState {
  static const inSafe = 'في الخزنة';
  static const cashed = 'اتصرف';
  static const bounced = 'مرتد';
}

class Collection {
  final DateTime date;
  final String receiptNo, customer;
  final bool isCheque; // نقدي / شيك
  final double amount;
  final String chequeNo, bank;
  final DateTime? dueDate;
  final String? chequeState;
  const Collection({
    required this.date,
    this.receiptNo = '',
    required this.customer,
    required this.isCheque,
    required this.amount,
    this.chequeNo = '',
    this.bank = '',
    this.dueDate,
    this.chequeState,
  });

  /// J: فاضل كام يوم (بس للشيك اللي لسه في الخزنة)
  int? daysLeft(DateTime today) =>
      (isCheque && chequeState == ChequeState.inSafe && dueDate != null)
          ? daysBetween(today, dueDate!)
          : null;
}
