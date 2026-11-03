// "لصق من الواتساب": بيقرا رسايل المالك المكتوبة بالقوالب
// (شيت متابعة المالك بدون مكالمات) ويطلع منها قيد جاهز للتأكيد.
//
// القوالب:
// صرف | التاريخ: ..... | المبلغ: ..... جنيه | الغرض: (دولار شحنة رقم ..) أو (مستخلص) أو (شخصي) أو (مصروف: .....)
// دولار | التاريخ: ..... | دفعت: ..... جنيه | اشتريت: ..... دولار | المورد: ..... | الشحنة: .....
// إيداع | التاريخ: ..... | المبلغ: ..... جنيه | جاي منين: .....
// توريد | التاريخ: ..... | الفرع: ..... | المبلغ: ..... | رقم المحضر: .....
// تحويل | رقم الإذن: ..... | من: ..... | لـ: ..... | عدد القطع: .....
import 'cash.dart';

enum WaKind { spend, usd, deposit, handover, transfer }

const waKindNames = {
  WaKind.spend: 'صرف',
  WaKind.usd: 'دولار',
  WaKind.deposit: 'إيداع',
  WaKind.handover: 'توريد',
  WaKind.transfer: 'تحويل',
};

class WaParsed {
  final WaKind kind;
  final String raw;
  final Map<String, String> fields; // الخانات زي ما اتكتبت
  final List<String> problems; // حاجات ناقصة أو مش مفهومة
  final bool hasMedia; // الرسالة جت معاها صورة
  final DateTime? messageTime; // وقت الرسالة من الواتساب لو موجود

  // النتيجة (واحدة بس حسب النوع)
  final SafeMovement? safe;
  final UsdTransfer? usd;
  final CashHandover? handover; // المورّد فعلاً بس — الباقي من السيستم
  final StockTransfer? transfer;
  const WaParsed({
    required this.kind,
    required this.raw,
    required this.fields,
    required this.problems,
    required this.hasMedia,
    this.messageTime,
    this.safe,
    this.usd,
    this.handover,
    this.transfer,
  });
  bool get ok => problems.isEmpty;
}

/// يحوّل الأرقام العربي (٠١٢) والفارسي (۰۱۲) لأرقام عادية
String normalizeDigits(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩', fa = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = ar.indexOf(ch), j = fa.indexOf(ch);
    if (i >= 0) {
      b.write(i);
    } else if (j >= 0) {
      b.write(j);
    } else if (ch == '٫') {
      b.write('.');
    } else if (ch == '٬' || ch == '،') {
      b.write(',');
    } else {
      b.write(ch);
    }
  }
  return b.toString();
}

/// "1,250,000 جنيه" / "500 ألف" / "1.5 مليون" → رقم
double? parseAmount(String? s) {
  if (s == null) return null;
  var t = normalizeDigits(s).replaceAll(RegExp(r'[^\d.,]+(?=\d)'), ' ');
  final m = RegExp(r'\d[\d,]*(\.\d+)?').firstMatch(t);
  if (m == null) return null;
  var v = double.tryParse(m.group(0)!.replaceAll(',', ''));
  if (v == null) return null;
  final rest = normalizeDigits(s);
  if (rest.contains('مليون')) {
    v *= 1000000;
  } else if (RegExp(r'(ألف|الف|آلاف|الاف)').hasMatch(rest)) {
    v *= 1000;
  }
  return v;
}

/// تواريخ زي: 2026-11-03 / 3/11/2026 / 3-11 / 3/11 / النهارده / امبارح
DateTime? parseDate(String? s, DateTime today) {
  if (s == null) return null;
  final t = normalizeDigits(s).trim();
  if (RegExp(r'(النهارده|النهاردة|اليوم)').hasMatch(t)) {
    return DateTime(today.year, today.month, today.day);
  }
  if (RegExp(r'(امبارح|إمبارح|أمس|امس)').hasMatch(t)) {
    return DateTime(today.year, today.month, today.day - 1);
  }
  var m = RegExp(r'(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})').firstMatch(t);
  if (m != null) {
    return _valid(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }
  m = RegExp(r'(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})').firstMatch(t);
  if (m != null) {
    var y = int.parse(m[3]!);
    if (y < 100) y += 2000;
    return _valid(y, int.parse(m[2]!), int.parse(m[1]!));
  }
  m = RegExp(r'(\d{1,2})[-/.](\d{1,2})').firstMatch(t);
  if (m != null) {
    final day = int.parse(m[1]!), mon = int.parse(m[2]!);
    // لو التاريخ ده لسه ما جاش السنة دي، يبقى السنة اللي فاتت
    var y = today.year;
    final cand = _valid(y, mon, day);
    if (cand != null && cand.isAfter(today)) y -= 1;
    return _valid(y, mon, day);
  }
  return null;
}

DateTime? _valid(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final dt = DateTime(y, m, d);
  return (dt.month == m && dt.day == d) ? dt : null;
}

// بداية رسالة واتساب منسوخة: "[3/11/2026, 10:15 م] المالك: " أو "3/11/26 10:15 - المالك: "
final _waPrefix = RegExp(
    r'^\s*\[?\s*(\d{1,4}[/.-]\d{1,2}[/.-]\d{1,4})[,،]?\s+(\d{1,2}:\d{2}(?::\d{2})?)\s*([AaPp][Mm]|ص|م)?\s*\]?\s*[-–]?\s*([^:]{1,40}):\s*');
final _mediaMarker = RegExp(
    r'(omitted|attached|attachment|<Media|‎?image|صورة مرفقة|تم حذف|محذوف|مرفق|IMG-\d|\.jpe?g|\.png|\.pdf)',
    caseSensitive: false);

/// يفصل النص الملصوق لرسايل ويقرا كل رسالة بقالب.
List<WaParsed> parseWhatsApp(String text, {required DateTime today}) {
  final lines = normalizeDigits(text).replaceAll('\r', '').split('\n');
  // تجميع الأسطر لرسايل: كل سطر بيبدأ بكلمة قالب أو ببداية رسالة واتساب = رسالة جديدة
  final chunks = <({String body, DateTime? time, bool media})>[];
  String? cur;
  DateTime? curTime;
  var curMedia = false;
  void flush() {
    if (cur != null && cur!.trim().isNotEmpty) {
      chunks.add((body: cur!.trim(), time: curTime, media: curMedia));
    }
    cur = null;
    curTime = null;
    curMedia = false;
  }

  for (var line in lines) {
    DateTime? t;
    final p = _waPrefix.firstMatch(line);
    if (p != null) {
      t = parseDate(p[1], today);
      line = line.substring(p.end);
    }
    final starts = _kindOf(line) != null;
    if (starts) {
      flush();
      cur = line;
      curTime = t;
    } else if (_mediaMarker.hasMatch(line) && line.trim().length < 80) {
      // صورة جت لوحدها في رسالة: بتتحسب للرسالة اللي قبلها أو اللي جاية
      if (cur != null) {
        curMedia = true;
      } else if (chunks.isNotEmpty) {
        final l = chunks.removeLast();
        chunks.add((body: l.body, time: l.time, media: true));
      }
    } else if (cur != null && p == null) {
      cur = '${cur!} | $line';
    } else if (p != null) {
      flush(); // رسالة عادية مش بقالب
    }
  }
  flush();
  return [for (final c in chunks) _parseOne(c.body, c.time, c.media, today)];
}

WaKind? _kindOf(String line) {
  final t = line.trim().replaceAll(RegExp(r'^[*_~\s]+'), '');
  final m = RegExp(r'^(صرف|دولار|إيداع|ايداع|أيداع|توريد|تحويل)(?=\s|\||:|$)').firstMatch(t);
  if (m == null) return null;
  switch (m[1]) {
    case 'صرف':
      return WaKind.spend;
    case 'دولار':
      return WaKind.usd;
    case 'توريد':
      return WaKind.handover;
    case 'تحويل':
      return WaKind.transfer;
    default:
      return WaKind.deposit;
  }
}

Map<String, String> _fields(String body) {
  final out = <String, String>{};
  for (final part in body.split(RegExp(r'[|｜]'))) {
    final i = part.indexOf(':');
    if (i <= 0) continue;
    final k = part.substring(0, i).replaceAll(RegExp(r'[*_~+]'), '').trim();
    final v = part.substring(i + 1).trim();
    if (k.isNotEmpty && v.isNotEmpty && !RegExp(r'^\.+$').hasMatch(v)) out[k] = v;
  }
  return out;
}

String? _f(Map<String, String> f, List<String> keys, {bool exact = false}) {
  for (final k in keys) {
    for (final e in f.entries) {
      if (e.key.replaceAll(' ', '') == k.replaceAll(' ', '')) return e.value;
    }
  }
  if (exact) return null;
  for (final k in keys) {
    for (final e in f.entries) {
      if (e.key.contains(k)) return e.value;
    }
  }
  return null;
}

String _clean(String s) => s.replaceAll(RegExp(r'^[()\s]+|[()\s]+$'), '').trim();

WaParsed _parseOne(String body, DateTime? time, bool media, DateTime today) {
  final kind = _kindOf(body)!;
  final f = _fields(body);
  final problems = <String>[];
  final hasMedia = media || _mediaMarker.hasMatch(body);
  final dateStr = _f(f, ['التاريخ', 'تاريخ']);
  var date = parseDate(dateStr, today);
  if (date == null) {
    if (dateStr != null) problems.add('التاريخ مش مفهوم: $dateStr');
    date = time ?? DateTime(today.year, today.month, today.day);
  }

  switch (kind) {
    case WaKind.spend:
      final amount = parseAmount(_f(f, ['المبلغ']));
      if (amount == null) problems.add('المبلغ ناقص');
      final purpose = _f(f, ['الغرض']) ?? '';
      String type;
      var note = _clean(purpose);
      var ship = '';
      if (purpose.contains('دولار')) {
        type = SafeType.usd;
        final m = RegExp(r'ش\s*-?\s*\d{4}\s*-\s*\d+').firstMatch(purpose) ??
            RegExp(r'\d{4}\s*-\s*\d+').firstMatch(purpose) ??
            RegExp(r'رقم\s*([^\s()]+)').firstMatch(purpose);
        if (m != null) {
          ship = (m.groupCount >= 1 ? m[1]! : m[0]!).replaceAll(' ', '');
          if (!ship.startsWith('ش')) ship = 'ش-$ship';
          ship = ship.replaceFirst(RegExp(r'^ش(?!-)'), 'ش-');
        }
      } else if (purpose.contains('مستخلص')) {
        type = SafeType.broker;
      } else if (purpose.contains('شخصي')) {
        type = SafeType.personal;
      } else if (purpose.contains('مصروف')) {
        type = SafeType.expenses;
        final i = purpose.indexOf(':');
        if (i >= 0) note = _clean(purpose.substring(i + 1));
      } else {
        type = SafeType.expenses;
        problems.add('الغرض مش واضح — اختار النوع');
      }
      return WaParsed(
          kind: kind, raw: body, fields: f, problems: problems, hasMedia: hasMedia, messageTime: time,
          safe: SafeMovement(date: date, type: type, note: note, shipmentNo: ship, amount: amount ?? 0,
              via: 'رسالة بالقالب على الجروب', hasDocument: hasMedia));
    case WaKind.deposit:
      final amount = parseAmount(_f(f, ['المبلغ']));
      if (amount == null) problems.add('المبلغ ناقص');
      return WaParsed(
          kind: kind, raw: body, fields: f, problems: problems, hasMedia: hasMedia, messageTime: time,
          safe: SafeMovement(date: date, type: SafeType.deposit, note: _clean(_f(f, ['جاي منين', 'منين']) ?? ''),
              amount: amount ?? 0, via: 'رسالة بالقالب على الجروب', hasDocument: hasMedia));
    case WaKind.usd:
      final egp = parseAmount(_f(f, ['دفعت']));
      final usd = parseAmount(_f(f, ['اشتريت']));
      if (egp == null) problems.add('الجنيه المدفوع ناقص');
      if (usd == null) problems.add('الدولار ناقص');
      final sup = _clean(_f(f, ['المورد']) ?? '');
      if (sup.isEmpty) problems.add('المورد ناقص');
      var ship = _clean(_f(f, ['الشحنة']) ?? '');
      if (ship.isNotEmpty && RegExp(r'^\d').hasMatch(ship)) ship = 'ش-$ship';
      return WaParsed(
          kind: kind, raw: body, fields: f, problems: problems, hasMedia: hasMedia, messageTime: time,
          usd: UsdTransfer(date: date, supplier: sup, shipmentNo: ship, egpPaid: egp ?? 0, usdReceived: usd ?? 0));
    case WaKind.handover:
      final amount = parseAmount(_f(f, ['المبلغ']));
      if (amount == null) problems.add('المبلغ ناقص');
      final br = _f(f, ['الفرع']) ?? '';
      final branch = br.contains('بور') ? 'بورسعيد' : (br.contains('قاهر') ? 'القاهرة' : '');
      if (branch.isEmpty) problems.add('الفرع مش مفهوم');
      return WaParsed(
          kind: kind, raw: body, fields: f, problems: problems, hasMedia: hasMedia, messageTime: time,
          handover: CashHandover(date: date, branch: branch, reportNo: _clean(_f(f, ['رقم المحضر', 'المحضر']) ?? ''),
              cashSales: 0, collections: 0, petty: 0, delivered: amount ?? 0));
    case WaKind.transfer:
      final no = _clean(_f(f, ['رقم الإذن', 'الإذن', 'الاذن']) ?? '');
      final pcs = parseAmount(_f(f, ['عدد القطع', 'القطع']));
      if (no.isEmpty) problems.add('رقم الإذن ناقص');
      if (pcs == null) problems.add('عدد القطع ناقص');
      String place(String? s, String def) {
        final v = s ?? '';
        if (v.contains('بور')) return 'بورسعيد الرئيسي';
        if (v.contains('قاهر')) return 'القاهرة الفرعي';
        return v.isEmpty ? def : _clean(v);
      }
      return WaParsed(
          kind: kind, raw: body, fields: f, problems: problems, hasMedia: hasMedia, messageTime: time,
          transfer: StockTransfer(
              no: no,
              sentAt: time ?? date,
              from: place(_f(f, ['من'], exact: true), 'بورسعيد الرئيسي'),
              to: place(_f(f, ['لـ', 'ل', 'إلى', 'الى', 'لحد'], exact: true), 'القاهرة الفرعي'),
              lines: [TransferLine(code: 'إجمالي الإذن', sent: pcs ?? 0)]));
  }
}
