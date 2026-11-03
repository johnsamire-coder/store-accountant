// التقرير الشهري PDF (عربي من اليمين للشمال).
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../engine/format.dart';
import '../engine/reports.dart';

const _months = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

Future<Uint8List> buildMonthlyPdf(DateTime m, MonthlyReport r,
    {ByteData? regular, ByteData? bold, ByteData? latin, ByteData? latinBold, DateTime? printedAt}) async {
  regular ??= await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf');
  bold ??= await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf');
  latin ??= await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
  latinBold ??= await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
  final base = pw.Font.ttf(regular), b = pw.Font.ttf(bold);
  // الخط العربي مافيهوش علامات زي % و / و ( — بناخدها من خط تاني
  final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: base, bold: b, fontFallback: [pw.Font.ttf(latin), pw.Font.ttf(latinBold)]));
  final mm = r.m;
  String pct(double v) => fmtPct(v);

  pw.TableRow row(String label, String c, String p, String t, {bool strong = false, bool section = false}) {
    final st = pw.TextStyle(fontSize: section ? 12 : 10.5, fontWeight: strong || section ? pw.FontWeight.bold : pw.FontWeight.normal);
    pw.Widget cell(String x, {bool num = true}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: pw.Text(x, style: st, textAlign: num ? pw.TextAlign.left : pw.TextAlign.right, textDirection: RegExp(r'^-?\d').hasMatch(x) ? pw.TextDirection.ltr : null),
        );
    return pw.TableRow(
      decoration: section ? const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE8F5E9)) : null,
      children: [cell(label, num: false), cell(c), cell(p), cell(t)],
    );
  }

  pw.TableRow br(String l, ByBranch v, {bool strong = false, String Function(num)? f}) {
    final ff = f ?? fmtNum;
    return row(l, ff(v.cairo), ff(v.portSaid), ff(v.total), strong: strong);
  }

  pw.TableRow ratio(String l, double Function(String?) f) => row(l, pct(f(cairo)), pct(f(portSaid)), pct(f(null)));
  pw.TableRow sec(String l) => row(l, '', '', '', section: true);

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    textDirection: pw.TextDirection.rtl,
    margin: const pw.EdgeInsets.all(28),
    build: (_) => [
      pw.Text('التقرير الشهري لصاحب المحل', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      pw.Text('${_months[m.month - 1]} ${m.year} — محل ملابس رجالي — بورسعيد و القاهرة', style: const pw.TextStyle(fontSize: 12)),
      pw.SizedBox(height: 12),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
        columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1.4), 2: pw.FlexColumnWidth(1.4), 3: pw.FlexColumnWidth(1.4)},
        children: [
          row('البند', 'القاهرة', 'بورسعيد', 'الإجمالي', strong: true),
          sec('المبيعات'),
          br('مبيعات نقدي', mm.cashSales),
          br('مبيعات آجل', mm.creditSales),
          br('مردودات وخصومات', mm.returns),
          br('صافي المبيعات', r.netSales, strong: true),
          br('تكلفة المبيعات', mm.cogs),
          br('مجمل الربح', r.grossProfit, strong: true),
          ratio('نسبة مجمل الربح', r.grossMargin),
          sec('المصروفات'),
          br('إيجارات', r.rent),
          br('مرتبات وعمولات', r.payroll),
          br('باقي المصروفات', r.otherExpenses),
          br('صافي الربح', r.netProfit, strong: true),
          ratio('نسبة صافي الربح', r.netMargin),
          sec('مؤشرات العملاء والتحصيل'),
          ratio('نسبة البيع الآجل', r.creditRatio),
          br('تحصيلات الشهر', mm.collections),
          ratio('نسبة التحصيل من الآجل', r.collectionRatio),
          br('رصيد العملاء آخر الشهر', mm.customersBalance),
          br('منه متأخر أكتر من 90 يوم', mm.customersOver90),
          ratio('نسبة المتأخر +90', r.over90Ratio),
          sec('مؤشرات المخزون'),
          br('رصيد المخزون بالتكلفة', mm.stockAtCost),
          row('المخزون يكفي كام يوم بيع', fmtNum(r.stockDays(cairo)), fmtNum(r.stockDays(portSaid)), fmtNum(r.stockDays(null))),
          br('عجز جرد الشهر (قيمة)', mm.stockShortage),
          sec('مؤشرات النقدية والاستيراد'),
          br('نقدية اتوردت لخزنة المالك', mm.deliveredToSafe),
          row('دولار اتحوّل للصين (\$)', '', '', fmtNum(mm.usdTransferred)),
          row('رصيد مورد الصين (\$)', '', '', fmtNum(mm.chinaSupplierUsd)),
          sec('اللي علينا للموردين'),
          row('الصافي علينا للموردين (جنيه)', '', '', fmtNum(r.suppliersNet), strong: true),
          row('منه متأخر', '', '', fmtNum(r.suppliersLate)),
        ],
      ),
      pw.SizedBox(height: 16),
      pw.Text('إعداد: المحاسب ...........   مراجعة واعتماد: صاحب المحل ...........', style: const pw.TextStyle(fontSize: 11)),
      if (printedAt != null) pw.Text('اتطبع: ${fmtDate(printedAt)}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
    ],
  ));
  return doc.save();
}
