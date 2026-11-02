// شيت (التكلفة الواصلة): توزيع مصاريف الشحنة على الأصناف حسب القيمة.
import 'excel.dart';

class ShipmentCosts {
  final double freight; // نصيبنا من النولون
  final double customs; // الرسوم الجمركية
  final double vat; // ضريبة القيمة المضافة في الجمارك
  final double portFees; // رسوم الميناء والأرضيات
  final double transport; // النقل من الميناء للمخزن
  final double brokerCommission; // عمولة المستخلص
  final double other; // مصاريف أخرى

  const ShipmentCosts({
    this.freight = 0,
    this.customs = 0,
    this.vat = 0,
    this.portFees = 0,
    this.transport = 0,
    this.brokerCommission = 0,
    this.other = 0,
  });

  /// B18 = SUM(B11:B17)
  double get total =>
      freight + customs + vat + portFees + transport + brokerCommission + other;
}

class ShipmentItem {
  final String model;
  final String description;
  final String color;
  final double qty; // عدد القطع
  final double unitUsd; // سعر القطعة $
  const ShipmentItem({
    required this.model,
    this.description = '',
    this.color = '',
    required this.qty,
    required this.unitUsd,
  });
}

class LandedLine {
  final ShipmentItem item;
  final double totalUsd; // F = D*E
  final double totalEgp; // G = F*سعر الصرف
  final double share; // H = G / SUM(G)
  final double allocated; // I = H * إجمالي المصاريف
  final double landed; // J = G + I
  final double costPerPiece; // K = J / D
  final double suggestedPrice; // ROUNDUP(K*(1+نسبة الربح),0)
  final double profitPerPiece; // سعر البيع − التكلفة
  const LandedLine(this.item, this.totalUsd, this.totalEgp, this.share,
      this.allocated, this.landed, this.costPerPiece, this.suggestedPrice,
      this.profitPerPiece);
}

class LandedCostResult {
  final List<LandedLine> lines;
  final double totalQty, totalUsd, totalEgp, totalShare, totalAllocated,
      totalLanded, costsTotal;
  const LandedCostResult(this.lines, this.totalQty, this.totalUsd,
      this.totalEgp, this.totalShare, this.totalAllocated, this.totalLanded,
      this.costsTotal);

  /// I33: تحقق إن الموزع = إجمالي المصاريف
  String get check =>
      xRound(totalAllocated - costsTotal) == 0 ? 'مطابق' : 'خطأ';

  /// I34: نسبة المصاريف على سعر الصين
  double get costsRatio => totalEgp == 0 ? 0 : costsTotal / totalEgp;
}

LandedCostResult calcLandedCost({
  required double rate, // سعر الصرف الفعلي
  required double profitMargin, // نسبة الربح المطلوبة على التكلفة
  required ShipmentCosts costs,
  required List<ShipmentItem> items,
}) {
  final totalEgp =
      items.fold<double>(0, (s, i) => s + i.qty * i.unitUsd * rate);
  final lines = <LandedLine>[];
  for (final i in items) {
    final usd = i.qty * i.unitUsd;
    final egp = usd * rate;
    final share = totalEgp == 0 ? 0.0 : egp / totalEgp;
    final alloc = share * costs.total;
    final landed = egp + alloc;
    final cpp = i.qty == 0 ? 0.0 : landed / i.qty;
    final price = xRoundUp(cpp * (1 + profitMargin));
    lines.add(LandedLine(i, usd, egp, share, alloc, landed, cpp, price,
        price - cpp));
  }
  double sum(double Function(LandedLine) f) =>
      lines.fold<double>(0, (s, l) => s + f(l));
  return LandedCostResult(
    lines,
    items.fold<double>(0, (s, i) => s + i.qty),
    sum((l) => l.totalUsd),
    totalEgp,
    sum((l) => l.share),
    sum((l) => l.allocated),
    sum((l) => l.landed),
    costs.total,
  );
}
