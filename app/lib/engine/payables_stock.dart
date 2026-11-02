// شيت (الموردين واللي علينا) + (الجرد).
import 'excel.dart';

class Supplier {
  final String code, name, type; // مورد صين / مستخلص / مورد محلي / خدمات
  final bool isUsd; // العملة دولار ولا جنيه
  final double notDue, late1to30, late31to60, late60plus; // E..H
  final double prepaid; // K بعملته
  final DateTime? nearestDue; // M
  const Supplier({
    required this.code,
    required this.name,
    this.type = 'مورد محلي',
    this.isUsd = false,
    this.notDue = 0,
    this.late1to30 = 0,
    this.late31to60 = 0,
    this.late60plus = 0,
    this.prepaid = 0,
    this.nearestDue,
  });

  double _f(double usdRate) => isUsd ? usdRate : 1;

  /// I
  double get totalOwnCurrency => notDue + late1to30 + late31to60 + late60plus;

  /// J
  double totalEgp(double usdRate) => totalOwnCurrency * _f(usdRate);

  /// L
  double netEgp(double usdRate) =>
      totalEgp(usdRate) - prepaid * _f(usdRate);

  /// N: المتأخر كله + اللي لسه ما استحقش لو ميعاده خلال 7 أيام
  double dueIn7DaysEgp(double usdRate, DateTime today) =>
      _f(usdRate) *
      (late1to30 +
          late31to60 +
          late60plus +
          ((nearestDue != null && daysBetween(today, nearestDue!) <= 7)
              ? notDue
              : 0));

  /// متأخر بالجنيه (صف 38)
  double lateEgp(double usdRate) =>
      (late1to30 + late31to60 + late60plus) * _f(usdRate);

  /// O
  String get status => late60plus > 0
      ? 'متأخر +60 — سداد عاجل'
      : (late1to30 + late31to60 > 0 ? 'متأخر' : 'منتظم');
}

// ───────── الجرد (م-16) ─────────
class CountLine {
  final String code, model, color, size, reason;
  final double systemQty, actualQty, unitCost;
  const CountLine({
    required this.code,
    this.model = '',
    this.color = '',
    this.size = '',
    this.reason = '',
    required this.systemQty,
    required this.actualQty,
    required this.unitCost,
  });
  double get difference => actualQty - systemQty; // G
  double get value => difference * unitCost; // I
  String get status =>
      difference == 0 ? 'مطابق' : (difference < 0 ? 'عجز' : 'زيادة'); // J
}

class StockCount {
  final String place, kind; // عيّنة مفاجئة / جرد شامل
  final DateTime date;
  final List<CountLine> lines;
  const StockCount(
      {required this.place,
      required this.kind,
      required this.date,
      required this.lines});
  double get totalSystem => lines.fold(0, (s, l) => s + l.systemQty);
  double get totalActual => lines.fold(0, (s, l) => s + l.actualQty);
  double get totalDifference => lines.fold(0, (s, l) => s + l.difference);
  double get totalValue => lines.fold(0, (s, l) => s + l.value);

  /// E58: نسبة الأصناف المطابقة
  double get matchRatio => lines.isEmpty
      ? 0
      : lines.where((l) => l.status == 'مطابق').length / lines.length;
}

/// للاستخدام في الحسابات اللي محتاجة تقريب زي الإكسل
double roundEgp(double v) => xRound(v);
