import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/state.dart';
import '../data/codecs.dart';
import '../engine/cash.dart';
import '../engine/excel.dart';
import '../engine/format.dart';
import '../engine/whatsapp.dart';
import 'common.dart';
import 'form.dart';
import 'specs.dart';
import 'theme.dart';

/// حركة متسجلة قبل كده؟ (نفس التاريخ والنوع والمبلغ)
String? duplicateOf(AppState s, WaParsed p) {
  bool same(DateTime a, DateTime b) => dateOnly(a) == dateOnly(b);
  if (p.safe != null) {
    final x = p.safe!;
    if (s.values(safeMovementCodec).any((m) => same(m.date, x.date) && m.type == x.type && m.amount == x.amount)) return 'الحركة دي متسجلة قبل كده';
  }
  if (p.usd != null) {
    final x = p.usd!;
    if (s.values(usdTransferCodec).any((t) => same(t.date, x.date) && t.egpPaid == x.egpPaid && t.usdReceived == x.usdReceived)) return 'التحويل ده متسجل قبل كده';
  }
  if (p.transfer != null && p.transfer!.no.isNotEmpty) {
    if (s.values(stockTransferCodec).any((t) => t.no == p.transfer!.no)) return 'الإذن ده متسجل قبل كده';
  }
  if (p.handover != null) {
    final x = p.handover!;
    if (s.values(cashHandoverCodec).any((h) => same(h.date, x.date) && h.branch == x.branch && h.delivered == x.delivered)) return 'التوريد ده متسجل قبل كده';
  }
  return null;
}

/// يحفظ رسالة. التوريد لو له محضر بنفس اليوم والفرع بيكمّل عليه (المورّد فعلاً + رقم المحضر)
Future<void> saveParsed(AppState s, WaParsed p) async {
  switch (p.kind) {
    case WaKind.spend:
    case WaKind.deposit:
      await s.add(safeMovementCodec, p.safe!);
    case WaKind.usd:
      await s.add(usdTransferCodec, p.usd!);
    case WaKind.transfer:
      await s.add(stockTransferCodec, p.transfer!);
    case WaKind.handover:
      final x = p.handover!;
      final ex = s.all(cashHandoverCodec).where((h) => dateOnly(h.value.date) == dateOnly(x.date) && h.value.branch == x.branch).firstOrNull;
      if (ex == null) {
        await s.add(cashHandoverCodec, x);
      } else {
        final o = ex.value;
        await s.save(cashHandoverCodec, ex.id, CashHandover(date: o.date, branch: o.branch, reportNo: x.reportNo.isEmpty ? o.reportNo : x.reportNo,
            cashSales: o.cashSales, collections: o.collections, petty: o.petty, delivered: x.delivered));
      }
  }
}

(EntitySpec, Json) formFor(AppState s, WaParsed p) {
  switch (p.kind) {
    case WaKind.spend:
    case WaKind.deposit:
      return (safeMovementSpec, safeMovementCodec.encode(p.safe!));
    case WaKind.usd:
      return (usdTransferSpec, usdTransferCodec.encode(p.usd!));
    case WaKind.transfer:
      return (stockTransferSpec, stockTransferCodec.encode(p.transfer!));
    case WaKind.handover:
      final x = p.handover!;
      final ex = s.values(cashHandoverCodec).where((h) => dateOnly(h.date) == dateOnly(x.date) && h.branch == x.branch).firstOrNull;
      final j = cashHandoverCodec.encode(x);
      if (ex != null) {
        j['cashSales'] = ex.cashSales;
        j['collections'] = ex.collections;
        j['petty'] = ex.petty;
      }
      return (cashHandoverSpec, j);
  }
}

String summaryOf(WaParsed p) {
  switch (p.kind) {
    case WaKind.spend:
    case WaKind.deposit:
      final x = p.safe!;
      return '${x.type} — ${fmtNum(x.amount)} جنيه — ${fmtDate(x.date)}${x.shipmentNo.isEmpty ? '' : ' — ${x.shipmentNo}'}${x.note.isEmpty ? '' : '\n${x.note}'}';
    case WaKind.usd:
      final x = p.usd!;
      return 'دفع ${fmtNum(x.egpPaid)} جنيه ← \$${fmtNum(x.usdReceived)} (سعر ${x.rate == null ? '-' : fmtDec(x.rate!, 2)})\n${x.supplier} — ${x.shipmentNo} — ${fmtDate(x.date)}';
    case WaKind.handover:
      final x = p.handover!;
      return 'توريد ${x.branch} — ${fmtNum(x.delivered)} — ${fmtDate(x.date)}${x.reportNo.isEmpty ? '' : ' — محضر ${x.reportNo}'}\n(نقدي السيستم والتحصيلات والنثريات بتكملهم من السيستم)';
    case WaKind.transfer:
      final x = p.transfer!;
      return 'إذن ${x.no}: ${x.from} ← ${x.to} — ${fmtNum(x.totalSent)} قطعة';
  }
}

class PasteScreen extends StatefulWidget {
  final String? initialText;
  const PasteScreen({super.key, this.initialText});
  @override
  State<PasteScreen> createState() => _PasteScreenState();
}

class _PasteScreenState extends State<PasteScreen> {
  late final c = TextEditingController(text: widget.initialText ?? '');
  List<WaParsed> parsed = [];
  final saved = <int>{};
  bool read = false;

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  void _parse() {
    final s = AppScope.read(context);
    setState(() {
      parsed = parseWhatsApp(c.text, today: s.today);
      saved.clear();
      read = true;
    });
  }

  Future<void> _pasteAndRead() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    if (d?.text != null) c.text = d!.text!;
    _parse();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final ready = [for (var i = 0; i < parsed.length; i++) if (parsed[i].ok && !saved.contains(i) && duplicateOf(s, parsed[i]) == null) i];
    return Scaffold(
      appBar: AppBar(title: const Text('لصق من الواتساب')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: moneyColor, minimumSize: const Size.fromHeight(64)),
          icon: const Icon(Icons.content_paste, size: 28),
          label: const Text('الصق الرسايل واقراها', style: TextStyle(fontSize: 20)),
          onPressed: _pasteAndRead,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: c,
          minLines: 4,
          maxLines: 10,
          decoration: const InputDecoration(hintText: 'أو اكتب/الصق هنا رسالة أو أكتر بالقوالب: صرف / دولار / إيداع / توريد / تحويل'),
          onChanged: (_) => setState(() => read = false),
        ),
        const SizedBox(height: 8),
        if (!read && c.text.trim().isNotEmpty) OutlinedButton.icon(icon: const Icon(Icons.search), label: const Text('اقرا الرسايل'), onPressed: _parse),
        if (read && parsed.isEmpty)
          const EmptyHint('مالقيتش رسايل بالقالب.\nالرسالة لازم تبدأ بكلمة: صرف أو دولار أو إيداع أو توريد أو تحويل'),
        for (var i = 0; i < parsed.length; i++) _card(context, s, i),
      ]),
      bottomNavigationBar: ready.length > 1
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: moneyColor),
                  icon: const Icon(Icons.done_all),
                  label: Text('احفظ الـ ${ready.length} اللي سليمين'),
                  onPressed: () async {
                    for (final i in ready) {
                      await saveParsed(s, parsed[i]);
                      saved.add(i);
                    }
                    setState(() {});
                    if (context.mounted) toast(context, 'اتحفظ ${ready.length} ✔');
                  },
                ),
              ),
            )
          : null,
    );
  }

  Widget _card(BuildContext context, AppState s, int i) {
    final p = parsed[i];
    final dup = duplicateOf(s, p);
    final done = saved.contains(i);
    final color = p.kind == WaKind.transfer ? goodsColor : moneyColor;
    return Card(
      margin: const EdgeInsets.only(top: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: color.withValues(alpha: 0.5))),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CircleAvatar(backgroundColor: color, foregroundColor: Colors.white, child: Text(waKindNames[p.kind]!.substring(0, 1))),
            const SizedBox(width: 10),
            Expanded(child: Text(waKindNames[p.kind]!, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
            if (done) const StatusChip('اتحفظ ✔'),
            if (!done && p.safe != null) StatusChip(p.safe!.status),
          ]),
          const SizedBox(height: 8),
          Text(summaryOf(p), style: const TextStyle(fontSize: 16, height: 1.5)),
          for (final pr in p.problems) Text('• $pr', style: const TextStyle(color: dangerColor, fontSize: 15)),
          if (dup != null && !done) Text('• $dup', style: const TextStyle(color: warnColor, fontSize: 15)),
          if (p.safe != null && !p.hasMedia && !done)
            const Text('الرسالة جت من غير صورة مستند — هتتسجل (مستند ناقص) لحد ما الصورة توصل', style: TextStyle(fontSize: 13)),
          if (!done) ...[
            const SizedBox(height: 10),
            Row(children: [
              if (p.ok && dup == null)
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: color),
                    onPressed: () async {
                      await saveParsed(s, p);
                      setState(() => saved.add(i));
                    },
                    child: const Text('احفظ'),
                  ),
                ),
              if (p.ok && dup == null) const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final (spec, json) = formFor(s, p);
                    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => _typedForm(spec, json, p, s)));
                    if (ok == true) setState(() => saved.add(i));
                  },
                  child: const Text('راجع وعدّل'),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _typedForm(EntitySpec spec, Json json, WaParsed p, AppState s) {
    // التوريد لو له محضر بنفس اليوم بنعدّل عليه بدل ما نعمل واحد جديد
    String? id;
    if (p.kind == WaKind.handover) {
      id = s.all(cashHandoverCodec).where((h) => dateOnly(h.value.date) == dateOnly(p.handover!.date) && h.value.branch == p.handover!.branch).firstOrNull?.id;
    }
    return spec.formPage(id: id, initial: json, saveLabel: 'تأكيد وحفظ');
  }
}
