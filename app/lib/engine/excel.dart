// دوال صغيرة بتقلد دوال الإكسل بالظبط، علشان نتايج التطبيق تطابق الملف.

/// ROUND في الإكسل: التقريب بعيد عن الصفر عند النص (2.5 → 3، -2.5 → -3).
double xRound(double v, [int digits = 0]) {
  final f = _pow10(digits);
  final x = v * f;
  // تصحيح أخطاء الكسور العشرية الصغيرة قبل التقريب
  final adj = double.parse(x.toStringAsFixed(9));
  return (adj.isNegative ? -(-adj).roundToDouble() : adj.roundToDouble()) / f;
}

/// ROUNDUP في الإكسل: دايمًا بعيد عن الصفر.
double xRoundUp(double v, [int digits = 0]) {
  final f = _pow10(digits);
  final x = double.parse((v * f).toStringAsFixed(9));
  return (x.isNegative ? -(-x).ceilToDouble() : x.ceilToDouble()) / f;
}

double _pow10(int d) {
  var r = 1.0;
  for (var i = 0; i < d; i++) {
    r *= 10;
  }
  return r;
}

/// EDATE: نفس اليوم بعد عدد شهور (لو اليوم مش موجود ياخد آخر يوم في الشهر).
DateTime eDate(DateTime d, int months) {
  final m0 = d.month - 1 + months;
  final y = d.year + (m0 >= 0 ? m0 ~/ 12 : ((m0 + 1) ~/ 12) - 1);
  final m = (m0 % 12) + 1;
  final lastDay = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, d.day > lastDay ? lastDay : d.day);
}

/// تاريخ من غير وقت.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// فرق الأيام (b − a) زي طرح التواريخ في الإكسل.
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day)
        .difference(DateTime.utc(a.year, a.month, a.day))
        .inDays;
