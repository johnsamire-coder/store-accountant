// تنسيق الأرقام زي دالة TEXT في الإكسل.
import 'excel.dart';

/// "#,##0" → 1,250,000 (السالب بعلامة −  زي الإكسل: -100)
String fmtNum(num v) {
  final r = xRound(v.toDouble());
  final neg = r < 0;
  final s = r.abs().toStringAsFixed(0);
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return neg ? '-$b' : b.toString();
}

/// "0%"
String fmtPct(num v) => '${xRound(v * 100).toStringAsFixed(0)}%';

/// "+0%;-0%"
String fmtSignedPct(num v) {
  final p = xRound(v.abs() * 100).toStringAsFixed(0);
  return v < 0 ? '-$p%' : '+$p%';
}

/// "yyyy-mm-dd"
String fmtDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// رقم بكسور (لتكلفة القطعة مثلاً): 298.04
String fmtDec(num v, [int digits = 2]) {
  final r = xRound(v.toDouble(), digits);
  final whole = fmtNum(r.truncateToDouble());
  final frac = r.abs().toStringAsFixed(digits).split('.').last;
  final sign = (r < 0 && r.truncate() == 0) ? '-' : '';
  return '$sign$whole.$frac';
}
