// شيت (توريد النقدية) + (سجل خزنة المالك) + (تحويلات الدولار) + (إذن تحويل مخزني).
import 'excel.dart';

// ───────── توريد النقدية (م-14) ─────────
class CashHandover {
  final DateTime date;
  final String branch;
  final String reportNo;
  final double cashSales; // D مبيعات نقدي حسب السيستم
  final double collections; // E تحصيلات نقدية من عملاء
  final double petty; // F نثريات معتمدة
  final double delivered; // H المورّد فعلاً
  const CashHandover({
    required this.date,
    required this.branch,
    this.reportNo = '',
    required this.cashSales,
    required this.collections,
    required this.petty,
    required this.delivered,
  });

  /// G = D+E−F
  double get expected => cashSales + collections - petty;

  /// I = H−G
  double get difference => delivered - expected;

  /// J
  String get status =>
      difference == 0 ? 'مطابق' : (difference < 0 ? 'عجز' : 'زيادة');
}

// ───────── سجل خزنة المالك ─────────
class SafeType {
  static const usd = 'صرف لشراء دولار';
  static const broker = 'سداد مستخلص';
  static const personal = 'مسحوبات شخصية';
  static const expenses = 'مصروفات';
  static const deposit = 'إيداع في الخزنة';
  static const all = [usd, broker, personal, expenses, deposit];
}

class SafeMovement {
  final DateTime date;
  final String type; // من SafeType
  final String note;
  final String shipmentNo;
  final double amount;
  final String via; // وصلت إزاي
  final bool hasDocument; // فيه صورة مستند؟
  final bool recorded; // اتسجلت في السيستم؟
  final bool weeklyConfirmed;
  const SafeMovement({
    required this.date,
    required this.type,
    this.note = '',
    this.shipmentNo = '',
    required this.amount,
    this.via = 'رسالة بالقالب على الجروب',
    this.hasDocument = false,
    this.recorded = false,
    this.weeklyConfirmed = false,
  });

  /// I
  String get status =>
      !hasDocument ? 'مستند ناقص' : (!recorded ? 'مستني تسجيل' : 'تمام');
}

/// رصيد خزنة المالك في التقرير الأسبوعي (صفوف 46–52).
class SafeWeekBalance {
  final double opening, handovers, deposits, payments, expected;
  final double? confirmed;
  const SafeWeekBalance(this.opening, this.handovers, this.deposits,
      this.payments, this.expected, this.confirmed);
  double? get difference => confirmed == null ? null : confirmed! - expected;
}

bool _inRange(DateTime d, DateTime from, DateTime to) =>
    !dateOnly(d).isBefore(dateOnly(from)) && !dateOnly(d).isAfter(dateOnly(to));

SafeWeekBalance safeWeekBalance({
  required double opening,
  required DateTime from,
  required DateTime to,
  required List<CashHandover> handovers,
  required List<SafeMovement> movements,
  double? confirmed,
}) {
  final h = handovers
      .where((x) => _inRange(x.date, from, to))
      .fold<double>(0, (s, x) => s + x.delivered);
  final inRange = movements.where((m) => _inRange(m.date, from, to));
  final dep = inRange
      .where((m) => m.type == SafeType.deposit)
      .fold<double>(0, (s, m) => s + m.amount);
  // B49 = كل الحركات في الفترة − الإيداعات
  final pay = inRange.fold<double>(0, (s, m) => s + m.amount) - dep;
  return SafeWeekBalance(opening, h, dep, pay, opening + h + dep - pay,
      confirmed);
}

// ───────── تحويلات الدولار (م-06) ─────────
class UsdTransfer {
  final DateTime date;
  final String voucherNo;
  final String supplier;
  final String shipmentNo;
  final double egpPaid; // E
  final double usdReceived; // F
  final double feesEgp; // H
  final String method;
  const UsdTransfer({
    required this.date,
    this.voucherNo = '',
    required this.supplier,
    this.shipmentNo = '',
    required this.egpPaid,
    required this.usdReceived,
    this.feesEgp = 0,
    this.method = '',
  });

  /// G = E/F
  double? get rate => usdReceived == 0 ? null : egpPaid / usdReceived;

  /// I = (E+H)/F
  double? get rateWithFees =>
      usdReceived == 0 ? null : (egpPaid + feesEgp) / usdReceived;
}

/// G36 متوسط السعر = مجموع الجنيه ÷ مجموع الدولار (لشحنة معينة لو اتحددت)
double? averageRate(List<UsdTransfer> list, {String? shipmentNo}) {
  final l = shipmentNo == null
      ? list
      : list.where((t) => t.shipmentNo == shipmentNo).toList();
  final usd = l.fold<double>(0, (s, t) => s + t.usdReceived);
  final egp = l.fold<double>(0, (s, t) => s + t.egpPaid);
  return usd == 0 ? null : egp / usd;
}

class SupplierUsdBalance {
  final String supplier;
  final double transferred; // B
  final double invoices; // C
  final double? statement; // E رصيد كشفه
  const SupplierUsdBalance(
      this.supplier, this.transferred, this.invoices, this.statement);

  /// D (موجب = دفعة مقدمة عنده)
  double get balance => transferred - invoices;

  /// F
  double? get difference => statement == null ? null : balance - statement!;
}

SupplierUsdBalance supplierUsdBalance(String supplier,
        List<UsdTransfer> transfers, double invoicesUsd, double? statement) =>
    SupplierUsdBalance(
        supplier,
        transfers
            .where((t) => t.supplier == supplier)
            .fold<double>(0, (s, t) => s + t.usdReceived),
        invoicesUsd,
        statement);

// ───────── إذن تحويل مخزني (م-08) ─────────
class TransferLine {
  final String code, model, color, size;
  final double sent; // E
  final double? received; // F
  const TransferLine({
    required this.code,
    this.model = '',
    this.color = '',
    this.size = '',
    required this.sent,
    this.received,
  });

  /// G = F−E (لو لسه ما اتسجلش المستلم بنعتبره صفر زي الإكسل)
  double get difference => (received ?? 0) - sent;

  /// H
  String get note => difference < 0
      ? 'عجز — محضر فرق'
      : (difference > 0 ? 'زيادة — مراجعة' : '');
}

class StockTransfer {
  final String no;
  final DateTime sentAt;
  final DateTime? receivedAt;
  final String from, to, driver, vehicle;
  final List<TransferLine> lines;
  const StockTransfer({
    required this.no,
    required this.sentAt,
    this.receivedAt,
    this.from = 'بورسعيد الرئيسي',
    this.to = 'القاهرة الفرعي',
    this.driver = '',
    this.vehicle = '',
    required this.lines,
  });

  double get totalSent => lines.fold(0, (s, l) => s + l.sent);
  double get totalReceived => lines.fold(0, (s, l) => s + (l.received ?? 0));
  double get totalDifference => lines.fold(0, (s, l) => s + l.difference);

  /// خريطة الدورة خطوة 10: تحويل معلّق أكتر من 48 ساعة
  bool isPendingOver48h(DateTime now) =>
      receivedAt == null && now.difference(sentAt).inHours > 48;
}
