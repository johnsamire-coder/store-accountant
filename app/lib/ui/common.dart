import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../engine/format.dart';
import '../engine/whatsapp.dart' show normalizeDigits;
import 'theme.dart';

String money(num v) => fmtNum(v);

class StatusChip extends StatelessWidget {
  final String text;
  const StatusChip(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final c = statusColor(text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.6)),
      ),
      child: Text(text, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }
}

/// زرار كبير بإيد واحدة
class BigTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sub;
  final Color color;
  final VoidCallback onTap;
  const BigTile({super.key, required this.icon, required this.label, this.sub, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: color.withValues(alpha: 0.35))),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                if (sub != null && sub!.isNotEmpty)
                  Text(sub!, style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
            ),
            const Icon(Icons.chevron_left),
          ]),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Color? color;
  const SectionTitle(this.text, {super.key, this.color});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(text, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color ?? Theme.of(context).colorScheme.primary)),
      );
}

/// سطر رقم (ممكن تدوس عليه يوريك القيود اللي وراه)
class NumRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool bold;
  final Color? color;
  final String? note;
  const NumRow(this.label, this.value, {super.key, this.onTap, this.bold = false, this.color, this.note});
  @override
  Widget build(BuildContext context) {
    final st = TextStyle(fontSize: 16, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(children: [
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: st),
            if (note != null) Text(note!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ])),
          Text(value, textDirection: TextDirection.ltr, style: st.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          if (onTap != null) Icon(Icons.chevron_left, size: 18, color: Theme.of(context).colorScheme.primary),
        ]),
      ),
    );
  }
}

/// بيحط فواصل الآلاف وانت بتكتب (1250000 → 1,250,000) وبيقبل الأرقام العربي
class ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var t = normalizeDigits(newValue.text).replaceAll(',', '');
    final neg = t.startsWith('-');
    t = t.replaceAll(RegExp(r'[^\d.]'), '');
    final parts = t.split('.');
    var whole = parts.first;
    final dec = parts.length > 1 ? '.${parts.sublist(1).join()}' : '';
    final b = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) b.write(',');
      b.write(whole[i]);
    }
    final out = '${neg ? '-' : ''}$b$dec';
    return TextEditingValue(text: out, selection: TextSelection.collapsed(offset: out.length));
  }
}

double? parseNum(String s) {
  final t = normalizeDigits(s).replaceAll(',', '').trim();
  return t.isEmpty ? null : double.tryParse(t);
}

String numText(num? v) {
  if (v == null) return '';
  if (v == v.roundToDouble()) return fmtNum(v);
  return fmtNum(v.truncate()) + v.toString().substring(v.toString().indexOf('.'));
}

/// نسخ + مشاركة للواتساب
class MessageBox extends StatelessWidget {
  final String text;
  final String title;
  const MessageBox(this.text, {super.key, this.title = 'رسالة الواتساب الجاهزة'});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: moneyColor.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          SelectableText(text, style: TextStyle(fontSize: 15, height: 1.6, color: cs.onSurface)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: moneyColor),
                icon: const Icon(Icons.share),
                label: const Text('واتساب'),
                onPressed: () => shareText(text),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('نسخ'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (context.mounted) toast(context, 'اتنسخت ✔');
                },
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

Future<void> shareText(String text) async {
  await SharePlus.instance.share(ShareParams(text: text));
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(fontSize: 16))));
}

Future<bool> confirm(BuildContext context, String q, {String yes = 'أيوه', String no = 'لأ'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      content: Text(q, style: const TextStyle(fontSize: 17)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(no)),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(yes)),
      ],
    ),
  );
  return r ?? false;
}

class EmptyHint extends StatelessWidget {
  final String text;
  const EmptyHint(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
            child: Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant))),
      );
}

const arabicMonths = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
const arabicDays = ['الاتنين', 'التلات', 'الأربع', 'الخميس', 'الجمعة', 'السبت', 'الحد'];
String monthName(DateTime d) => '${arabicMonths[d.month - 1]} ${d.year}';
String dayName(DateTime d) => '${arabicDays[d.weekday - 1]} ${fmtDate(d)}';
