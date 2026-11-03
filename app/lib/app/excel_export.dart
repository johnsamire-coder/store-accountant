// تصدير كل البيانات لملف إكسل بنفس شكل ملف الدورة المستندية:
// نفس أسماء الشيتات وترتيبها، نفس العناوين والأعمدة وأماكنها، والأرقام المحسوبة جاهزة.
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

import '../data/codecs.dart';
import '../engine/cash.dart';
import '../engine/customers.dart';
import '../engine/excel.dart';
import '../engine/format.dart';
import '../engine/payroll_expenses.dart';
import 'report_data.dart';
import 'state.dart';
import 'workbook_static.dart';

class _W {
  final Sheet sh;
  _W(this.sh);
  final _bold = CellStyle(bold: true);
  void put(int row1, int col0, Object? v, {bool bold = false}) {
    if (v == null) return;
    final CellValue cv;
    if (v is CellValue) {
      cv = v;
    } else if (v is String) {
      cv = TextCellValue(v);
    } else if (v is int) {
      cv = IntCellValue(v);
    } else if (v is num) {
      cv = DoubleCellValue(v.toDouble());
    } else if (v is DateTime) {
      cv = DateCellValue(year: v.year, month: v.month, day: v.day);
    } else if (v is bool) {
      cv = TextCellValue(v ? 'نعم' : 'لا');
    } else {
      cv = TextCellValue('$v');
    }
    sh.updateCell(CellIndex.indexByColumnRow(columnIndex: col0, rowIndex: row1 - 1), cv, cellStyle: bold ? _bold : null);
  }

  /// سطر يبدأ من عمود A
  void row(int row1, List<Object?> vals, {bool bold = false, int startCol = 0}) {
    for (var i = 0; i < vals.length; i++) {
      put(row1, startCol + i, vals[i], bold: bold);
    }
  }
}

List<Map<String, dynamic>> _static() => (jsonDecode(workbookStaticJson) as List).cast<Map<String, dynamic>>();

void _copyStatic(Sheet sh, Map<String, dynamic> st) {
  sh.isRTL = true;
  for (final c in (st['cells'] as List).cast<List>()) {
    final v = c[2];
    final ci = CellIndex.indexByColumnRow(columnIndex: c[1] as int, rowIndex: c[0] as int);
    sh.updateCell(ci, v is String ? TextCellValue(v) : (v is int ? IntCellValue(v) : DoubleCellValue((v as num).toDouble())),
        cellStyle: c[3] == 1 ? CellStyle(bold: true) : null);
  }
  for (final m in (st['merges'] as List).cast<List>()) {
    sh.merge(CellIndex.indexByColumnRow(columnIndex: m[1] as int, rowIndex: m[0] as int),
        CellIndex.indexByColumnRow(columnIndex: m[3] as int, rowIndex: m[2] as int));
  }
  for (final e in (st['widths'] as Map).entries) {
    sh.setColumnWidth(int.parse(e.key as String), (e.value as num).toDouble());
  }
}

String _yn(bool b) => b ? 'نعم' : 'لا';
double _sum<T>(Iterable<T> l, double Function(T) f) => l.fold(0, (a, x) => a + f(x));

/// [today] بيحدد الشهر والأسبوع واليوم اللي التقارير بتطلع عنهم
List<int> buildExcel(AppState s) {
  final today = s.today;
  final month = DateTime(today.year, today.month, 1);
  final ex = Excel.createExcel();
  final defaultSheet = ex.getDefaultSheet()!;
  final statics = _static();
  final created = <String>[];

  Sheet sheet(String name, {Map<String, dynamic>? from}) {
    final sh = ex[name];
    created.add(name);
    if (from != null) _copyStatic(sh, from);
    sh.isRTL = true;
    return sh;
  }

  for (final st in statics) {
    final name = st['name'] as String;
    switch (name) {
      case 'التكلفة الواصلة':
        final ships = s.values(shipmentCodec)..sort((a, b) => (a.date ?? DateTime(0)).compareTo(b.date ?? DateTime(0)));
        if (ships.isEmpty) {
          sheet(name, from: st);
          break;
        }
        for (var i = 0; i < ships.length; i++) {
          var n = i == 0 ? name : 'تكلفة ${ships[i].no}';
          if (n.length > 31) n = n.substring(0, 31);
          while (created.contains(n)) {
            n = '${n.substring(0, n.length > 28 ? 28 : n.length)}-$i';
          }
          _landed(_W(sheet(n, from: st)), ships[i]);
        }
        break;
      case 'إذن تحويل مخزني':
        _transfers(_W(sheet(name, from: st)), s);
        break;
      case 'توريد النقدية':
        _handovers(_W(sheet(name, from: st)), s);
        break;
      case 'سجل خزنة المالك':
        _safe(_W(sheet(name, from: st)), s);
        break;
      case 'تحويلات الدولار':
        _usd(_W(sheet(name, from: st)), s);
        break;
      case 'العملاء والأعمار':
        _customers(_W(sheet(name, from: st)), s);
        break;
      case 'كشف حساب عميل':
        _statements(_W(sheet(name, from: st)), s);
        break;
      case 'التحصيلات والشيكات':
        _collections(_W(sheet(name, from: st)), s);
        break;
      case 'الموردين واللي علينا':
        _suppliers(_W(sheet(name, from: st)), s);
        break;
      case 'الجرد':
        _counts(_W(sheet(name, from: st)), s);
        break;
      case 'المرتبات':
        _payroll(_W(sheet(name, from: st)), s, month);
        break;
      case 'السلف':
        _advances(_W(sheet(name, from: st)), s, month);
        break;
      case 'المصروفات الثابتة':
        _fixed(_W(sheet(name, from: st)), s, month);
        break;
      case 'النثريات والمصروفات':
        _petty(_W(sheet(name, from: st)), s);
        break;
      case 'ملخص المصروفات':
        _summary(_W(sheet(name, from: st)), s, month);
        break;
      case 'التقرير اليومي':
        _daily(_W(sheet(name, from: st)), s, today.subtract(const Duration(days: 1)));
        break;
      case 'التقرير الأسبوعي':
        _weekly(_W(sheet(name, from: st)), s, weekStart(today));
        break;
      case 'التقرير الشهري':
        _monthly(_W(sheet(name, from: st)), s, DateTime(today.year, today.month - 1, 1));
        break;
      default:
        sheet(name, from: st); // شيتات الخطة: زي ما هي
    }
  }
  if (!created.contains(defaultSheet)) ex.delete(defaultSheet);
  ex.setDefaultSheet(created.first);
  return forceRtl(ex.encode()!);
}

/// مكتبة الإكسل مش بتعلّم الشيتات الجديدة إنها من اليمين للشمال، فبنعلّمها في الملف نفسه
List<int> forceRtl(List<int> xlsx) {
  final arc = ZipDecoder().decodeBytes(xlsx);
  final out = Archive();
  for (final f in arc.files) {
    if (f.isFile && f.name.startsWith('xl/worksheets/') && f.name.endsWith('.xml')) {
      var xml = utf8.decode(f.content as List<int>);
      xml = xml.replaceAllMapped(RegExp(r'<sheetView(?=[\s/>])(?![^>]*rightToLeft)'), (_) => '<sheetView rightToLeft="1"');
      final b = utf8.encode(xml);
      out.addFile(ArchiveFile(f.name, b.length, b));
    } else {
      out.addFile(f);
    }
  }
  return ZipEncoder().encode(out)!;
}

// ───────── التكلفة الواصلة ─────────
void _landed(_W w, Shipment x) {
  final r = x.calc();
  w.put(6, 1, x.no);
  w.put(7, 1, x.rate);
  w.put(8, 1, x.profitMargin);
  final c = x.costs;
  for (final (i, v) in [c.freight, c.customs, c.vat, c.portFees, c.transport, c.brokerCommission, c.other].indexed) {
    w.put(11 + i, 1, v);
  }
  w.put(18, 1, c.total);
  var row = 22;
  for (final l in r.lines) {
    w.row(row++, [l.item.model, l.item.description, l.item.color, l.item.qty, l.item.unitUsd, l.totalUsd, l.totalEgp, l.share, l.allocated, l.landed, l.costPerPiece]);
  }
  final t = 22 + (r.lines.length > 10 ? r.lines.length : 10);
  w.row(t, ['الإجمالي', null, null, r.totalQty, null, r.totalUsd, r.totalEgp, r.totalShare, r.totalAllocated, r.totalLanded], bold: true);
  w.put(t + 1, 0, 'تحقق: المصاريف الموزعة = إجمالي المصاريف');
  w.put(t + 1, 8, r.check);
  w.put(t + 2, 0, 'نسبة المصاريف على سعر الصين');
  w.put(t + 2, 8, r.costsRatio);
  w.put(t + 4, 0, 'سعر البيع المقترح (على أساس التكلفة الواصلة)', bold: true);
  w.row(t + 5, ['الموديل', 'تكلفة القطعة', 'سعر البيع المقترح', 'ربح القطعة'], bold: true);
  var pr = t + 6;
  for (final l in r.lines) {
    w.row(pr++, [l.item.model, l.costPerPiece, l.suggestedPrice, l.profitPerPiece]);
  }
}

// ───────── إذن تحويل مخزني (كل إذن بلوك تحت التاني) ─────────
void _transfers(_W w, AppState s) {
  final l = s.values(stockTransferCodec)..sort((a, b) => a.sentAt.compareTo(b.sentAt));
  var r = 4;
  for (final t in l) {
    w.row(r, ['رقم الإذن', t.no, null, 'التاريخ', t.sentAt]);
    w.put(r, 0, 'رقم الإذن', bold: true);
    w.row(r + 1, ['من مخزن', t.from, null, 'إلى مخزن', t.to]);
    w.row(r + 2, ['اسم السواق', t.driver, null, 'رقم العربية', t.vehicle]);
    w.row(r + 3, ['تاريخ الاستلام', t.receivedAt == null ? 'لسه ما اتستلمش' : fmtDate(t.receivedAt!)]);
    w.row(r + 4, ['كود الصنف', 'الموديل', 'اللون', 'المقاس', 'الكمية المحوّلة', 'الكمية المستلمة', 'الفرق', 'ملاحظات'], bold: true);
    var rr = r + 5;
    for (final x in t.lines) {
      w.row(rr++, [x.code, x.model, x.color, x.size, x.sent, x.received, x.received == null ? null : x.difference, x.received == null ? null : x.note]);
    }
    w.row(rr, ['الإجمالي', null, null, null, t.totalSent, t.totalReceived, t.totalDifference], bold: true);
    r = rr + 3;
  }
  w.put(r, 0, 'التوقيعات', bold: true);
  w.put(r + 1, 0, 'أمين مخزن بورسعيد (المرسل): ...................   التاريخ/الساعة: ..........');
  w.put(r + 2, 0, 'السواق (استلمت البضاعة بالعدد): ...................');
  w.put(r + 3, 0, 'مسؤول القاهرة (المستلم — استلمت الكميات في خانة المستلمة): ...................   التاريخ/الساعة: ..........');
  w.put(r + 4, 0, 'المحاسب (راجعت وطابقت في السيستم): ...................');
}

// ───────── توريد النقدية ─────────
void _handovers(_W w, AppState s) {
  final l = s.values(cashHandoverCodec)..sort((a, b) => a.date.compareTo(b.date));
  var r = 6;
  for (final h in l) {
    w.row(r++, [h.date, h.branch, h.reportNo, h.cashSales, h.collections, h.petty, h.expected, h.delivered, h.difference, h.status]);
  }
  final t = r < 46 ? 46 : r;
  w.row(t, ['الإجمالي', null, null, _sum(l, (h) => h.cashSales), _sum(l, (h) => h.collections), _sum(l, (h) => h.petty), _sum(l, (h) => h.expected), _sum(l, (h) => h.delivered), _sum(l, (h) => h.difference)], bold: true);
  w.row(t + 1, ['عدد أيام فيها عجز', null, null, l.where((h) => h.status == 'عجز').length]);
}

// ───────── سجل خزنة المالك ─────────
void _safe(_W w, AppState s) {
  final l = s.values(safeMovementCodec)..sort((a, b) => a.date.compareTo(b.date));
  var r = 6;
  for (final m in l) {
    w.row(r++, [m.date, m.type, m.note, m.shipmentNo, m.amount, m.via, _yn(m.hasDocument), _yn(m.recorded), m.status, _yn(m.weeklyConfirmed)]);
  }
  final t = (r < 106 ? 106 : r) + 1;
  w.put(t, 0, 'ملخص حسب النوع', bold: true);
  w.row(t + 1, ['النوع', 'الإجمالي'], bold: true);
  var i = t + 2;
  for (final ty in SafeType.all) {
    w.row(i++, [ty, _sum(l.where((m) => m.type == ty), (m) => m.amount)]);
  }
  w.row(i++, ['عدد الحركات (مستند ناقص)', l.where((m) => m.status == 'مستند ناقص').length]);
  w.row(i, ['عدد الحركات (مستني تسجيل)', l.where((m) => m.status == 'مستني تسجيل').length]);
}

// ───────── تحويلات الدولار ─────────
void _usd(_W w, AppState s) {
  final l = s.values(usdTransferCodec)..sort((a, b) => a.date.compareTo(b.date));
  var r = 6;
  for (final t in l) {
    w.row(r++, [t.date, t.voucherNo, t.supplier, t.shipmentNo, t.egpPaid, t.usdReceived, t.rate, t.feesEgp, t.rateWithFees, t.method]);
  }
  final t = r < 36 ? 36 : r;
  w.row(t, ['الإجمالي', null, null, null, _sum(l, (x) => x.egpPaid), _sum(l, (x) => x.usdReceived), averageRate(l), _sum(l, (x) => x.feesEgp)], bold: true);
  w.put(t + 2, 0, 'رصيد كل مورد بالدولار (يتطابق شهريًا مع كشف حساب المورد)', bold: true);
  w.row(t + 3, ['المورد', 'المحوّل له \$', 'فواتيره \$', 'الرصيد \$ (موجب = دفعة مقدمة عنده)', 'رصيد كشفه \$', 'الفرق'], bold: true);
  final saved = (s.setting<Map>(K.usdBalances) ?? const {}).cast<String, dynamic>();
  var i = t + 4;
  for (final n in {...l.map((x) => x.supplier)}) {
    final m = (saved[n] as Map?)?.cast<String, dynamic>() ?? {};
    final b = supplierUsdBalance(n, l, (m['invoices'] as num?)?.toDouble() ?? 0, (m['statement'] as num?)?.toDouble());
    w.row(i++, [n, b.transferred, b.invoices, b.balance, b.statement, b.difference]);
  }
}

// ───────── العملاء والأعمار ─────────
void _customers(_W w, AppState s) {
  final l = s.values(customerCodec);
  var r = 6;
  for (final c in l) {
    w.row(r++, [c.code, c.name, c.phone, c.branch, c.creditLimit, c.paymentDays, c.b0to30, c.b31to60, c.b61to90, c.b90plus, c.balance, c.limitUse, c.alert, c.lastCollection, c.weeklyTarget, c.followUpBy]);
  }
  final a = agingSummary(l);
  final t = r < 66 ? 66 : r;
  w.row(t, [null, 'الإجمالي', null, null, _sum(l, (c) => c.creditLimit), null, a.b0to30, a.b31to60, a.b61to90, a.b90plus, a.total, null, null, 'هدف الأسبوع', a.weeklyTarget], bold: true);
  w.row(t + 1, [null, 'نسبة كل شريحة من الرصيد', null, null, null, null, a.pct(a.b0to30), a.pct(a.b31to60), a.pct(a.b61to90), a.pct(a.b90plus)]);
}

// ───────── كشف حساب عميل (كل كشف بلوك) ─────────
void _statements(_W w, AppState s) {
  var r = 4;
  for (final x in s.values(statementCodec)) {
    w.row(r, ['اسم العميل', x.customer, 'الفترة من', x.from, 'إلى', x.to], bold: false);
    w.row(r + 1, ['الرصيد أول الفترة', x.opening]);
    w.row(r + 3, ['التاريخ', 'نوع الحركة', 'رقم المستند', 'البيان', 'مدين (عليه)', 'دائن (دفع / مرتجع)', 'الرصيد'], bold: true);
    w.row(r + 4, [null, null, null, 'رصيد أول الفترة', null, null, x.opening]);
    final bal = x.runningBalances;
    var rr = r + 5;
    for (var i = 0; i < x.lines.length; i++) {
      final l = x.lines[i];
      w.row(rr++, [l.date, l.type, l.docNo, l.note, l.debit == 0 ? null : l.debit, l.credit == 0 ? null : l.credit, bal[i]]);
    }
    w.row(rr, [null, null, null, 'الإجمالي', x.totalDebit, x.totalCredit], bold: true);
    w.row(rr + 1, [null, null, null, 'الرصيد آخر الفترة (المستحق على العميل)', null, null, x.closing], bold: true);
    w.put(rr + 3, 0, x.confirmationText(fmtNum));
    w.put(rr + 4, 0, 'توقيع العميل: ..................   التاريخ: ..........   ختم المحل: ..................');
    r = rr + 7;
  }
}

// ───────── التحصيلات والشيكات ─────────
void _collections(_W w, AppState s) {
  final l = s.values(collectionCodec)..sort((a, b) => a.date.compareTo(b.date));
  var r = 6;
  for (final c in l) {
    w.row(r++, [c.date, c.receiptNo, c.customer, c.isCheque ? 'شيك' : 'نقدي', c.amount, c.chequeNo, c.bank, c.dueDate, c.chequeState, c.daysLeft(s.today)]);
  }
  final t = r < 66 ? 66 : r;
  w.row(t, [null, null, 'إجمالي التحصيلات', null, _sum(l, (c) => c.amount)]);
  w.row(t + 1, [null, null, 'منها نقدي', null, _sum(l.where((c) => !c.isCheque), (c) => c.amount)]);
  w.row(t + 2, [null, null, 'شيكات في الخزنة لسه', null, _sum(l.where((c) => c.isCheque && c.chequeState == ChequeState.inSafe), (c) => c.amount)]);
  w.row(t + 3, [null, null, 'شيكات مرتدة', null, _sum(l.where((c) => c.chequeState == ChequeState.bounced), (c) => c.amount)]);
}

// ───────── الموردين ─────────
void _suppliers(_W w, AppState s) {
  final rate = s.usdRate;
  w.put(4, 1, rate);
  final l = s.values(supplierCodec);
  var r = 7;
  for (final x in l) {
    w.row(r++, [x.code, x.name, x.type, x.isUsd ? 'دولار' : 'جنيه', x.notDue, x.late1to30, x.late31to60, x.late60plus, x.totalOwnCurrency, x.totalEgp(rate), x.prepaid, x.netEgp(rate), x.nearestDue, x.dueIn7DaysEgp(rate, s.today), x.status]);
  }
  final t = r < 37 ? 37 : r;
  w.row(t, [null, 'الإجمالي بالجنيه', null, null, null, null, null, null, null, _sum(l, (x) => x.totalEgp(rate)), null, _sum(l, (x) => x.netEgp(rate)), null, _sum(l, (x) => x.dueIn7DaysEgp(rate, s.today))], bold: true);
  w.row(t + 1, [null, 'منه متأخر (بالجنيه)', null, null, null, null, null, null, null, _sum(l, (x) => x.lateEgp(rate))]);
}

// ───────── الجرد (كل محضر بلوك) ─────────
void _counts(_W w, AppState s) {
  final l = s.values(stockCountCodec)..sort((a, b) => a.date.compareTo(b.date));
  var r = 4;
  for (final c in l) {
    w.row(r, ['المكان', c.place, null, 'التاريخ', c.date, null, 'نوع الجرد', c.kind]);
    w.row(r + 2, ['كود الصنف', 'الموديل', 'اللون', 'المقاس', 'رصيد السيستم', 'العد الفعلي', 'الفرق', 'تكلفة القطعة', 'قيمة الفرق', 'الحالة', 'السبب / ملاحظة'], bold: true);
    var rr = r + 3;
    for (final x in c.lines) {
      w.row(rr++, [x.code, x.model, x.color, x.size, x.systemQty, x.actualQty, x.difference, x.unitCost, x.value, x.status, x.reason]);
    }
    w.row(rr, ['الإجمالي', null, null, null, c.totalSystem, c.totalActual, c.totalDifference, null, c.totalValue], bold: true);
    w.row(rr + 1, ['نسبة الأصناف المطابقة', null, null, null, c.matchRatio]);
    w.put(rr + 3, 0, 'لجنة الجرد: أمين المخزن ...........   المحاسب ...........   اعتماد صاحب المحل للتسوية ...........');
    r = rr + 6;
  }
}

// ───────── المرتبات ─────────
void _payroll(_W w, AppState s, DateTime month) {
  w.put(4, 2, month);
  final lines = s.payroll(month);
  final entries = {
    for (final e in s.values(payrollEntryCodec))
      if (e.month.year == month.year && e.month.month == month.month) e.employeeCode: e
  };
  var r = 7;
  for (final l in lines) {
    final e = entries[l.emp.code];
    w.row(r++, [l.emp.code, l.emp.name, l.emp.job, l.emp.branch, l.emp.hiredOn, l.emp.basic, l.emp.allowances, l.commission, l.absenceDays, l.absenceDeduction, l.penalties, l.advances, l.insurance, l.gross, l.deductions, l.net, e?.payMethod ?? 'كاش', e?.signed == true ? 'مضى' : null]);
  }
  double t(double Function(PayrollLine) f) => _sum(lines, f);
  final tr = r < 37 ? 37 : r;
  w.row(tr, [null, 'الإجمالي', null, null, null, t((l) => l.emp.basic), t((l) => l.emp.allowances), t((l) => l.commission), null, t((l) => l.absenceDeduction), t((l) => l.penalties), t((l) => l.advances), t((l) => l.insurance), t((l) => l.gross), t((l) => l.deductions), t((l) => l.net)], bold: true);
  w.put(tr + 2, 0, 'ملخص حسب الفرع (بيروح لملخص المصروفات والتقرير الشهري)', bold: true);
  w.row(tr + 3, ['الفرع', null, 'عدد الموظفين', 'المرتبات + البدلات', 'العمولات والحوافز', 'الصافي المصروف'], bold: true);
  var i = tr + 4;
  for (final b in ['القاهرة', 'بورسعيد']) {
    final bp = branchPayroll(b, lines);
    w.row(i++, [b, null, bp.count, bp.salariesAndAllowances, bp.commissions, bp.net]);
  }
  w.put(i + 1, 0, 'إعداد: المحاسب ...........   مراجعة واعتماد: صاحب المحل ...........   تاريخ الصرف: ...........   (مفيش موظف يقبض من غير ما يمضي قدام اسمه)');
}

// ───────── السلف ─────────
void _advances(_W w, AppState s, DateTime month) {
  w.put(4, 3, s.advanceMax);
  final l = s.values(advanceCodec)..sort((a, b) => a.date.compareTo(b.date));
  var r = 6;
  for (final a in l) {
    final e = s.employee(a.employeeCode);
    w.row(r++, [a.date, a.employeeCode, e?.name ?? 'كود مش موجود', a.amount, a.installments, a.monthly, a.firstMonth, a.lastMonth, a.remainingAfter(month),
      a.status(payrollMonth: month, maxMultiple: s.advanceMax, basicSalary: e?.basic ?? 0), _yn(a.ownerApproved)]);
  }
  final t = r < 106 ? 106 : r;
  w.row(t, [null, null, 'الإجمالي', _sum(l, (a) => a.amount), null, null, null, null, _sum(l, (a) => a.remainingAfter(month))], bold: true);
  w.put(t + 1, 2, 'لازم يساوي رصيد (ذمم العاملين) في السيستم');
}

// ───────── المصروفات الثابتة (الشهر الحالي) ─────────
void _fixed(_W w, AppState s, DateTime month) {
  final l = s.values(fixedExpenseCodec).where((f) => f.month != null && f.month!.year == month.year && f.month!.month == month.month).toList();
  var r = 6;
  for (final f in l) {
    w.row(r++, [f.name, f.category, f.branch, f.expected, f.dueDay, _yn(f.paid), f.actual, f.difference, f.receiptNo, f.status]);
  }
  final t = r < 36 ? 36 : r;
  w.row(t, ['الإجمالي', null, null, _sum(l, (f) => f.expected), null, null, _sum(l, (f) => f.actual ?? 0), _sum(l, (f) => f.difference ?? 0)], bold: true);
  w.row(t + 1, ['لسه ما اتدفعش (المتوقع)', null, null, _sum(l.where((f) => !f.paid), (f) => f.expected)]);
}

// ───────── النثريات ─────────
void _petty(_W w, AppState s) {
  final l = s.values(pettyExpenseCodec)..sort((a, b) => a.date.compareTo(b.date));
  w.put(4, 2, s.pettyLimit);
  for (final (i, b) in ['القاهرة', 'بورسعيد'].indexed) {
    final f = pettyFloat(b, s.floatOf(b), l);
    w.put(5 + i, 2, f.float);
    w.put(5 + i, 6, f.float);
    w.put(5 + i, 7, f.unreimbursed);
    w.put(5 + i, 8, f.remaining);
  }
  var r = 8;
  for (final p in l) {
    w.row(r++, [p.date, p.branch, p.category, p.note, p.amount, _yn(p.hasInvoice), p.invoiceNo, p.approvedBy, _yn(p.reimbursed), p.status(s.pettyLimit)]);
  }
  final t = r < 158 ? 158 : r;
  w.row(t, [null, null, null, 'الإجمالي', _sum(l, (p) => p.amount)], bold: true);
  w.row(t + 1, [null, null, null, 'عدد المصروفات اللي محتاجة مراجعة', l.where((p) => p.status(s.pettyLimit) != 'تمام').length]);
}

// ───────── ملخص المصروفات ─────────
void _summary(_W w, AppState s, DateTime month) {
  final l = s.expenseSummaryFor(month);
  for (final (i, x) in l.indexed) {
    w.row(6 + i, [x.item, x.cairo, x.portSaid, x.total, x.budget, x.variance, x.note]);
  }
  w.row(18, ['إجمالي المصروفات', _sum(l, (x) => x.cairo), _sum(l, (x) => x.portSaid), _sum(l, (x) => x.total), _sum(l, (x) => x.budget), _sum(l, (x) => x.variance)], bold: true);
}

// ───────── التقارير ─────────
void _branch(_W w, int row, dynamic v) => w.row(row, [v.cairo, v.portSaid, v.total], startCol: 1);

void _daily(_W w, AppState s, DateTime d) {
  final r = dailyFor(s, d);
  w.put(4, 1, d);
  _branch(w, 7, r.cashSales);
  _branch(w, 8, r.creditSales);
  _branch(w, 9, r.returns);
  _branch(w, 10, r.netSales);
  w.row(11, [r.creditRatio('القاهرة'), r.creditRatio('بورسعيد'), r.creditRatio(null)], startCol: 1);
  _branch(w, 12, r.cashCollections);
  _branch(w, 13, r.chequeCollections);
  _branch(w, 14, r.petty);
  _branch(w, 15, r.expected);
  _branch(w, 16, r.delivered);
  _branch(w, 17, r.handoverDiff);
  for (final (i, v) in [r.cancelledInvoices, r.creditOverLimit, r.returnsCount, r.pendingTransfers, r.shortageBranches, r.chequesDue2Days, r.safeMissingDocs, r.pettyNeedsReview].indexed) {
    w.put(21 + i, 1, v);
  }
  w.put(30, 0, r.message);
}

void _weekly(_W w, AppState s, DateTime from) {
  final r = weeklyFor(s, from);
  w.put(4, 1, r.from);
  w.put(4, 3, r.to);
  _branch(w, 8, r.cashSales);
  _branch(w, 9, r.creditSales);
  _branch(w, 10, r.returns);
  _branch(w, 11, r.netSales);
  w.row(12, [r.creditRatio('القاهرة'), r.creditRatio('بورسعيد'), r.creditRatio(null)], startCol: 1);
  _branch(w, 13, r.lastWeekNet);
  w.row(14, [r.change('القاهرة'), r.change('بورسعيد'), r.change(null)], startCol: 1);
  for (final (i, v) in [r.collections, r.cashCollections, r.chequeCollections, r.target, r.targetRatio].indexed) {
    w.put(18 + i, 1, v);
  }
  final a = r.aging;
  for (final (i, v) in [a.b0to30, a.b31to60, a.b61to90, a.b90plus].indexed) {
    w.row(26 + i, [v, a.pct(v)], startCol: 1);
  }
  for (final (i, v) in [a.total, r.overLimitCount, r.over90Count, r.chequesDueNextWeek, r.bouncedCheques].indexed) {
    w.put(30 + i, 1, v);
  }
  w.put(38, 1, r.suppliersNet);
  w.put(39, 1, r.suppliersLate);
  w.put(40, 1, r.suppliersDue7);
  for (final (i, v) in [r.shortageDays, r.handoverDiffTotal, r.safe.opening, r.safe.handovers, r.safe.deposits, r.safe.payments, r.safe.expected, r.safe.confirmed, r.safe.difference, r.safeMissingDocs].indexed) {
    w.put(44 + i, 1, v);
  }
  w.put(57, 1, r.stockMatchRatio);
  w.put(58, 1, r.stockDiffValue);
  w.put(61, 0, r.message);
}

void _monthly(_W w, AppState s, DateTime m) {
  final r = monthlyFor(s, m);
  final mm = r.m;
  _branch(w, 7, mm.cashSales);
  _branch(w, 8, mm.creditSales);
  _branch(w, 9, mm.returns);
  _branch(w, 10, r.netSales);
  _branch(w, 11, mm.cogs);
  _branch(w, 12, r.grossProfit);
  w.row(13, [r.grossMargin('القاهرة'), r.grossMargin('بورسعيد'), r.grossMargin(null)], startCol: 1);
  _branch(w, 15, r.rent);
  _branch(w, 16, r.payroll);
  _branch(w, 17, r.otherExpenses);
  _branch(w, 18, r.netProfit);
  w.row(19, [r.netMargin('القاهرة'), r.netMargin('بورسعيد'), r.netMargin(null)], startCol: 1);
  w.row(21, [r.creditRatio('القاهرة'), r.creditRatio('بورسعيد'), r.creditRatio(null)], startCol: 1);
  _branch(w, 22, mm.collections);
  w.row(23, [r.collectionRatio('القاهرة'), r.collectionRatio('بورسعيد'), r.collectionRatio(null)], startCol: 1);
  _branch(w, 24, mm.customersBalance);
  _branch(w, 25, mm.customersOver90);
  w.row(26, [r.over90Ratio('القاهرة'), r.over90Ratio('بورسعيد'), r.over90Ratio(null)], startCol: 1);
  _branch(w, 28, mm.stockAtCost);
  w.row(29, [r.stockDays('القاهرة'), r.stockDays('بورسعيد'), r.stockDays(null)], startCol: 1);
  _branch(w, 30, mm.stockShortage);
  _branch(w, 32, mm.deliveredToSafe);
  w.put(33, 1, mm.usdTransferred);
  w.put(33, 3, mm.usdTransferred);
  w.put(34, 1, mm.chinaSupplierUsd);
  w.put(34, 3, mm.chinaSupplierUsd);
  w.put(36, 3, r.suppliersNet);
  w.put(37, 3, r.suppliersLate);
  w.put(4, 0, 'الشهر: ${m.year}-${m.month.toString().padLeft(2, '0')}');
}

/// للتأكد إن التاريخ اتحسب صح في الاختبارات
DateTime exportMonth(AppState s) => dateOnly(DateTime(s.today.year, s.today.month, 1));
