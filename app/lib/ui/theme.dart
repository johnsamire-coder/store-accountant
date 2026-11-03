import 'package:flutter/material.dart';

/// البضاعة = كهرماني، الفلوس = أخضر
const goodsColor = Color(0xFFE6A100);
const moneyColor = Color(0xFF1E8E3E);
const dangerColor = Color(0xFFC62828);
const warnColor = Color(0xFFEF6C00);
const okColor = Color(0xFF2E7D32);

const appFont = 'NotoSansArabic';

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: moneyColor, brightness: b);
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: b,
    fontFamily: appFont,
    fontFamilyFallback: const ['NotoSans'], // علامات زي ( ) — + % مش موجودة في الخط العربي
    visualDensity: VisualDensity.standard,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: appFont, fontFamilyFallback: const ['NotoSans']),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      titleTextStyle: TextStyle(fontFamily: appFont, fontSize: 21, fontWeight: FontWeight.bold, color: scheme.onSurface),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 56),
        textStyle: const TextStyle(fontFamily: appFont, fontSize: 18, fontWeight: FontWeight.bold),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontFamily: appFont, fontSize: 16),
      ),
    ),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 10),
  );
}

/// لون الحالة حسب كلمات الإكسل
Color statusColor(String s) {
  if (s.isEmpty) return Colors.grey;
  const bad = ['عجز', 'ناقص', 'متأخر +90', 'متجاوز', 'مرتد', 'فوق', 'خطأ', 'سداد عاجل', 'أعلى', 'كود مش موجود'];
  const warn = ['مستني', 'مستنية', 'متأخر', 'لسه', 'بتتخصم', 'زيادة', 'مراجعة', 'في الخزنة', 'موافقة'];
  for (final w in bad) {
    if (s.contains(w)) return dangerColor;
  }
  for (final w in warn) {
    if (s.contains(w)) return warnColor;
  }
  return okColor;
}
