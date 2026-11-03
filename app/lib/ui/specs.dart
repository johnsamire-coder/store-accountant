// تعريف كل سجل من سجلات الإكسل: خاناته، حالته، والأرقام اللي بتتحسب.
import 'package:flutter/material.dart';

import '../app/state.dart';
import '../data/codecs.dart';
import '../engine/cash.dart';
import '../engine/customers.dart';
import '../engine/format.dart';
import '../engine/payables_stock.dart';
import '../engine/payroll_expenses.dart';
import 'common.dart' show monthName;
import 'form.dart';
import 'theme.dart';

String _m(num v) => fmtNum(v);
String _usd(num v) => '\$${fmtDec(v)}';
List<String> _shipNos(AppState s) => {
      ...s.values(shipmentCodec).map((x) => x.no),
      ...s.values(usdTransferCodec).map((x) => x.shipmentNo),
      ...s.values(safeMovementCodec).map((x) => x.shipmentNo),
    }.where((x) => x.isNotEmpty).toList();
List<String> _customerNames(AppState s) => s.values(customerCodec).map((c) => c.name).toList();
List<String> _chinaSuppliers(AppState s) => {
      ...s.values(supplierCodec).where((x) => x.isUsd || x.type == 'مورد صين').map((x) => x.name),
      ...s.values(usdTransferCodec).map((x) => x.supplier),
    }.where((x) => x.isNotEmpty).toList();
List<String> _employeeCodes(AppState s) => s.values(employeeCodec).map((e) => e.code).toList();

String _nextCode(List<String> codes, String prefix, int width) {
  var n = 0;
  for (final c in codes) {
    final m = RegExp(r'(\d+)$').firstMatch(c);
    if (m != null && int.parse(m[1]!) > n) n = int.parse(m[1]!);
  }
  return '$prefix${(n + 1).toString().padLeft(width, '0')}';
}

const _places = ['بورسعيد الرئيسي', 'القاهرة الفرعي'];
const _countPlaces = ['مخزن بورسعيد', 'مخزن القاهرة', 'محل بورسعيد', 'محل القاهرة'];

// ═════════ البضاعة ═════════
final shipmentSpec = EntitySpec<Shipment>(
  codec: shipmentCodec,
  title: 'الشحنات والتكلفة الواصلة',
  single: 'شحنة',
  icon: Icons.directions_boat,
  color: goodsColor,
  fields: [
    FieldSpec('no', 'رقم الشحنة', FType.text, required: true, hint: 'ش-2026-01',
        initial: (s) => _nextCode(s.values(shipmentCodec).map((x) => x.no).toList(), 'ش-${s.today.year}-', 2)),
    dateField(),
    FieldSpec('rate', 'سعر الصرف الفعلي (جنيه/دولار)', FType.number, required: true, hint: 'من تحويلات الدولار',
        initial: (s) => s.values(usdTransferCodec).isEmpty ? s.usdRate : averageRate(s.values(usdTransferCodec))),
    FieldSpec('profitMargin', 'نسبة الربح المطلوبة على التكلفة (0.35 = 35%)', FType.number, initial: (s) => s.profitMargin),
    const FieldSpec('costs.freight', 'نصيبنا من النولون', FType.number),
    const FieldSpec('costs.customs', 'الرسوم الجمركية', FType.number),
    const FieldSpec('costs.vat', 'ضريبة القيمة المضافة في الجمارك', FType.number),
    const FieldSpec('costs.portFees', 'رسوم الميناء والأرضيات', FType.number),
    const FieldSpec('costs.transport', 'النقل من الميناء للمخزن', FType.number),
    const FieldSpec('costs.brokerCommission', 'عمولة المستخلص', FType.number),
    const FieldSpec('costs.other', 'مصاريف أخرى', FType.number),
    const FieldSpec('items', 'الأصناف', FType.lines, sub: [
      FieldSpec('model', 'الموديل', FType.text, required: true),
      FieldSpec('description', 'الوصف', FType.text),
      FieldSpec('color', 'اللون', FType.text),
      FieldSpec('qty', 'عدد القطع', FType.number),
      FieldSpec('unitUsd', 'سعر القطعة \$', FType.number),
    ]),
  ],
  tileTitle: (x) => x.no,
  tileSub: (x, s) {
    final r = x.calc();
    return '${_m(r.totalQty)} قطعة — مصاريف ${_m(r.costsTotal)} — التكلفة الواصلة ${_m(r.totalLanded)}';
  },
  status: (x, s) => x.items.isEmpty ? '' : x.calc().check,
  sortDate: (x) => x.date,
  details: (x, s) {
    final r = x.calc();
    final avg = s.averageRateFor(x.no);
    return [
      ('إجمالي المصاريف', _m(r.costsTotal)),
      ('إجمالي البضاعة بالدولار', _usd(r.totalUsd)),
      ('إجمالي البضاعة بالجنيه', _m(r.totalEgp)),
      ('التكلفة الواصلة', _m(r.totalLanded)),
      ('نسبة المصاريف على سعر الصين', fmtPct(r.costsRatio)),
      if (avg != null) ('متوسط سعر الصرف من تحويلات الشحنة', fmtDec(avg, 4)),
      for (final l in r.lines) ('${l.item.model} — تكلفة القطعة / البيع المقترح', '${fmtDec(l.costPerPiece)} / ${_m(l.suggestedPrice)}'),
    ];
  },
);

String _transferStatus(StockTransfer t, AppState s) {
  if (t.receivedAt == null) return t.isPendingOver48h(s.now) ? 'معلّق أكتر من 48 ساعة' : 'لسه ما اتستلمش';
  final d = t.totalDifference;
  return d == 0 ? 'مطابق' : (d < 0 ? 'عجز — محضر فرق' : 'زيادة — مراجعة');
}

final stockTransferSpec = EntitySpec<StockTransfer>(
  codec: stockTransferCodec,
  title: 'تحويلات بورسعيد للقاهرة',
  single: 'إذن تحويل',
  icon: Icons.local_shipping,
  color: goodsColor,
  fields: [
    FieldSpec('no', 'رقم الإذن', FType.text, required: true,
        initial: (s) => _nextCode(s.values(stockTransferCodec).map((x) => x.no).toList(), 'ت-', 4)),
    FieldSpec('sentAt', 'خرج من المخزن', FType.dateTime, required: true, initial: (s) => s.now.toIso8601String()),
    const FieldSpec('receivedAt', 'اتستلم في القاهرة (سيبه فاضي لو لسه)', FType.dateTime),
    FieldSpec('from', 'من مخزن', FType.choice, options: fixedOptions(_places), initial: (_) => _places[0]),
    FieldSpec('to', 'إلى مخزن', FType.choice, options: fixedOptions(_places), initial: (_) => _places[1]),
    const FieldSpec('driver', 'اسم السواق', FType.text),
    const FieldSpec('vehicle', 'رقم العربية', FType.text),
    const FieldSpec('lines', 'الأصناف', FType.lines, sub: [
      FieldSpec('code', 'كود الصنف (موديل-لون-مقاس)', FType.text, required: true),
      FieldSpec('model', 'الموديل', FType.text),
      FieldSpec('color', 'اللون', FType.text),
      FieldSpec('size', 'المقاس', FType.text),
      FieldSpec('sent', 'الكمية المحوّلة', FType.number),
      FieldSpec('received', 'الكمية المستلمة', FType.number, nullable: true),
    ]),
  ],
  tileTitle: (x) => 'إذن ${x.no}',
  tileSub: (x, s) => '${fmtDate(x.sentAt)} — محوّل ${_m(x.totalSent)} / مستلم ${_m(x.totalReceived)}',
  status: _transferStatus,
  sortDate: (x) => x.sentAt,
  details: (x, s) => [
    ('الكمية المحوّلة', _m(x.totalSent)),
    ('الكمية المستلمة', _m(x.totalReceived)),
    ('الفرق', _m(x.totalDifference)),
    for (final l in x.lines)
      if (l.difference != 0 && l.received != null) ('${l.code}: ${l.note}', _m(l.difference)),
  ],
);

final stockCountSpec = EntitySpec<StockCount>(
  codec: stockCountCodec,
  title: 'الجرد',
  single: 'محضر جرد',
  icon: Icons.fact_check,
  color: goodsColor,
  fields: [
    FieldSpec('place', 'المكان', FType.choice, options: fixedOptions(_countPlaces), required: true,
        initial: (s) => s.lastBranch == 'بورسعيد' ? 'مخزن بورسعيد' : 'مخزن القاهرة'),
    dateField(),
    FieldSpec('kind', 'نوع الجرد', FType.choice, options: fixedOptions(['عيّنة مفاجئة', 'جرد شامل']), initial: (_) => 'عيّنة مفاجئة'),
    const FieldSpec('lines', 'الأصناف', FType.lines, sub: [
      FieldSpec('code', 'كود الصنف', FType.text, required: true),
      FieldSpec('model', 'الموديل', FType.text),
      FieldSpec('color', 'اللون', FType.text),
      FieldSpec('size', 'المقاس', FType.text),
      FieldSpec('systemQty', 'رصيد السيستم', FType.number),
      FieldSpec('actualQty', 'العد الفعلي', FType.number),
      FieldSpec('unitCost', 'تكلفة القطعة', FType.number),
      FieldSpec('reason', 'السبب / ملاحظة', FType.text),
    ]),
  ],
  tileTitle: (x) => '${x.place} — ${x.kind}',
  tileSub: (x, s) => '${fmtDate(x.date)} — ${x.lines.length} صنف — مطابق ${fmtPct(x.matchRatio)}',
  status: (x, s) => x.totalValue < 0 ? 'عجز' : (x.totalValue > 0 ? 'زيادة' : 'مطابق'),
  sortDate: (x) => x.date,
  details: (x, s) => [
    ('رصيد السيستم', _m(x.totalSystem)),
    ('العد الفعلي', _m(x.totalActual)),
    ('الفرق (قطع)', _m(x.totalDifference)),
    ('قيمة الفرق', _m(x.totalValue)),
    ('نسبة الأصناف المطابقة', fmtPct(x.matchRatio)),
    for (final l in x.lines)
      if (l.difference != 0) ('${l.code}: ${l.status}', '${_m(l.difference)} قطعة = ${_m(l.value)}'),
  ],
);

// ═════════ الفلوس ═════════
final cashHandoverSpec = EntitySpec<CashHandover>(
  codec: cashHandoverCodec,
  title: 'توريد النقدية اليومي',
  single: 'محضر توريد',
  icon: Icons.payments,
  color: moneyColor,
  fields: [
    dateField(),
    branchField(),
    const FieldSpec('reportNo', 'رقم المحضر', FType.text),
    const FieldSpec('cashSales', 'مبيعات نقدي حسب السيستم', FType.number, required: true),
    const FieldSpec('collections', 'تحصيلات نقدية من عملاء', FType.number),
    const FieldSpec('petty', 'نثريات معتمدة', FType.number),
    const FieldSpec('delivered', 'المورّد فعلاً', FType.number, required: true),
  ],
  tileTitle: (x) => '${x.branch} — ${fmtDate(x.date)}',
  tileSub: (x, s) => 'المفروض ${_m(x.expected)} — اتورد ${_m(x.delivered)}',
  status: (x, s) => x.status,
  sortDate: (x) => x.date,
  groupBy: 'branch',
  details: (x, s) => [
    ('المفروض توريده (نقدي + تحصيلات − نثريات)', _m(x.expected)),
    ('المورّد فعلاً', _m(x.delivered)),
    ('الفرق', _m(x.difference)),
  ],
);

final safeMovementSpec = EntitySpec<SafeMovement>(
  codec: safeMovementCodec,
  title: 'سجل خزنة المالك',
  single: 'حركة خزنة',
  icon: Icons.account_balance_wallet,
  color: moneyColor,
  fields: [
    dateField(),
    FieldSpec('type', 'نوع الحركة', FType.choice, options: fixedOptions(SafeType.all), required: true, initial: (_) => SafeType.usd),
    const FieldSpec('amount', 'المبلغ (جنيه)', FType.number, required: true),
    const FieldSpec('note', 'البيان', FType.text),
    FieldSpec('shipmentNo', 'رقم الشحنة', FType.text, options: _shipNos, visible: (j) => j['type'] == SafeType.usd || j['type'] == SafeType.broker),
    FieldSpec('via', 'وصلت إزاي', FType.choice,
        options: fixedOptions(['رسالة بالقالب على الجروب', 'إذن صرف ورقي', 'مكالمة']), initial: (_) => 'رسالة بالقالب على الجروب'),
    const FieldSpec('hasDocument', 'فيه صورة مستند؟', FType.yesNo),
    const FieldSpec('recorded', 'اتسجلت في السيستم؟', FType.yesNo),
    const FieldSpec('weeklyConfirmed', 'اتأكدت في المراجعة الأسبوعية؟', FType.yesNo),
  ],
  tileTitle: (x) => '${x.type} — ${_m(x.amount)}',
  tileSub: (x, s) => '${fmtDate(x.date)}${x.note.isEmpty ? '' : ' — ${x.note}'}${x.shipmentNo.isEmpty ? '' : ' — ${x.shipmentNo}'}',
  status: (x, s) => x.status,
  sortDate: (x) => x.date,
);

final usdTransferSpec = EntitySpec<UsdTransfer>(
  codec: usdTransferCodec,
  title: 'تحويلات الدولار للصين',
  single: 'تحويل دولار',
  icon: Icons.currency_exchange,
  color: moneyColor,
  fields: [
    dateField(),
    const FieldSpec('voucherNo', 'رقم إذن الصرف', FType.text),
    FieldSpec('supplier', 'المورد في الصين', FType.text, required: true, options: _chinaSuppliers),
    FieldSpec('shipmentNo', 'رقم الشحنة', FType.text, options: _shipNos),
    const FieldSpec('egpPaid', 'الجنيه المدفوع', FType.number, required: true),
    const FieldSpec('usdReceived', 'الدولار اللي وصل للمورد', FType.number, required: true),
    const FieldSpec('feesEgp', 'رسوم تحويل (جنيه)', FType.number),
    FieldSpec('method', 'طريقة التحويل', FType.text, options: fixedOptions(['شركة صرافة', 'بنك', 'تحويل مباشر'])),
  ],
  tileTitle: (x) => '${x.supplier} — ${_usd(x.usdReceived)}',
  tileSub: (x, s) => '${fmtDate(x.date)} — ${_m(x.egpPaid)} جنيه — سعر ${x.rate == null ? '-' : fmtDec(x.rate!, 4)}',
  sortDate: (x) => x.date,
  details: (x, s) => [
    ('سعر الصرف الفعلي', x.rate == null ? '-' : fmtDec(x.rate!, 4)),
    ('التكلفة بالرسوم للدولار', x.rateWithFees == null ? '-' : fmtDec(x.rateWithFees!, 4)),
  ],
);

final customerSpec = EntitySpec<Customer>(
  codec: customerCodec,
  title: 'العملاء والأعمار',
  single: 'عميل',
  icon: Icons.people,
  color: moneyColor,
  fields: [
    FieldSpec('code', 'الكود', FType.text, initial: (s) => _nextCode(s.values(customerCodec).map((c) => c.code).toList(), 'ع-', 3)),
    const FieldSpec('name', 'اسم العميل', FType.text, required: true),
    const FieldSpec('phone', 'التليفون', FType.text),
    branchField(),
    const FieldSpec('creditLimit', 'حد الائتمان', FType.number, required: true),
    FieldSpec('paymentDays', 'مدة السداد (يوم)', FType.number, initial: (_) => 30),
    const FieldSpec('b0to30', '0–30 يوم', FType.number),
    const FieldSpec('b31to60', '31–60', FType.number),
    const FieldSpec('b61to90', '61–90', FType.number),
    const FieldSpec('b90plus', 'أكتر من 90', FType.number),
    const FieldSpec('lastCollection', 'تاريخ آخر تحصيل', FType.date),
    const FieldSpec('weeklyTarget', 'مطلوب تحصيله الأسبوع ده', FType.number),
    FieldSpec('followUpBy', 'مسؤول المتابعة', FType.text, options: fixedOptions(['مسؤول المحل', 'مسؤول بورسعيد', 'صاحب المحل'])),
  ],
  tileTitle: (x) => x.name,
  tileSub: (x, s) => 'الرصيد ${_m(x.balance)} من حد ${_m(x.creditLimit)}${x.limitUse == null ? '' : ' (${fmtPct(x.limitUse!)})'}',
  status: (x, s) => x.alert,
  groupBy: 'branch',
  details: (x, s) => [
    ('الرصيد الكلي', _m(x.balance)),
    ('استخدام الحد', x.limitUse == null ? '-' : fmtPct(x.limitUse!)),
    ('0–30 / 31–60', '${_m(x.b0to30)} / ${_m(x.b31to60)}'),
    ('61–90 / +90', '${_m(x.b61to90)} / ${_m(x.b90plus)}'),
    ('مطلوب تحصيله الأسبوع ده', _m(x.weeklyTarget)),
  ],
);

final statementSpec = EntitySpec<CustomerStatement>(
  codec: statementCodec,
  title: 'كشوف حساب العملاء',
  single: 'كشف حساب',
  icon: Icons.receipt_long,
  color: moneyColor,
  fields: [
    FieldSpec('customer', 'اسم العميل', FType.text, required: true, options: _customerNames),
    FieldSpec('from', 'الفترة من', FType.date, required: true, initial: (s) => DateTime(s.today.year, s.today.month - 1, 1).toIso8601String()),
    FieldSpec('to', 'إلى', FType.date, required: true, initial: (s) => s.today.toIso8601String()),
    const FieldSpec('opening', 'الرصيد أول الفترة', FType.number),
    FieldSpec('lines', 'الحركات', FType.lines, sub: [
      FieldSpec('date', 'التاريخ', FType.date, required: true, initial: (s) => s.today.toIso8601String()),
      FieldSpec('type', 'نوع الحركة', FType.choice,
          options: fixedOptions(['فاتورة آجل', 'تحصيل نقدي', 'تحصيل شيك', 'مرتجع', 'خصم']), initial: (_) => 'فاتورة آجل'),
      const FieldSpec('docNo', 'رقم المستند', FType.text),
      const FieldSpec('note', 'البيان', FType.text),
      const FieldSpec('debit', 'مدين (عليه)', FType.number),
      const FieldSpec('credit', 'دائن (دفع / مرتجع)', FType.number),
    ]),
  ],
  tileTitle: (x) => x.customer,
  tileSub: (x, s) => '${fmtDate(x.from)} → ${fmtDate(x.to)} — الرصيد آخر الفترة ${_m(x.closing)}',
  sortDate: (x) => x.to,
  details: (x, s) => [
    ('الرصيد أول الفترة', _m(x.opening)),
    ('+ فواتير (مدين)', _m(x.totalDebit)),
    ('− مدفوعات ومرتجعات (دائن)', _m(x.totalCredit)),
    ('الرصيد آخر الفترة', _m(x.closing)),
  ],
);

final collectionSpec = EntitySpec<Collection>(
  codec: collectionCodec,
  title: 'التحصيلات والشيكات',
  single: 'إيصال تحصيل',
  icon: Icons.request_quote,
  color: moneyColor,
  fields: [
    dateField(),
    const FieldSpec('receiptNo', 'رقم الإيصال', FType.text),
    FieldSpec('customer', 'العميل', FType.text, required: true, options: _customerNames),
    const FieldSpec('isCheque', 'شيك؟ (لأ = نقدي)', FType.yesNo),
    const FieldSpec('amount', 'المبلغ', FType.number, required: true),
    FieldSpec('chequeNo', 'رقم الشيك', FType.text, visible: (j) => j['isCheque'] == true),
    FieldSpec('bank', 'البنك', FType.text, options: fixedOptions(['بنك مصر', 'البنك الأهلي', 'بنك القاهرة', 'CIB']), visible: (j) => j['isCheque'] == true),
    FieldSpec('dueDate', 'تاريخ الاستحقاق', FType.date, visible: (j) => j['isCheque'] == true),
    FieldSpec('chequeState', 'حالة الشيك', FType.choice,
        options: fixedOptions([ChequeState.inSafe, ChequeState.cashed, ChequeState.bounced]),
        initial: (_) => ChequeState.inSafe,
        visible: (j) => j['isCheque'] == true),
  ],
  tileTitle: (x) => '${x.customer} — ${_m(x.amount)}',
  tileSub: (x, s) {
    final d = x.daysLeft(s.today);
    return '${fmtDate(x.date)} — ${x.isCheque ? 'شيك ${x.chequeNo} ${x.bank}' : 'نقدي'}${d == null ? '' : ' — فاضل $d يوم'}';
  },
  status: (x, s) => x.isCheque ? (x.chequeState ?? '') : 'نقدي',
  sortDate: (x) => x.date,
  details: (x, s) => [
    if (x.isCheque) ('تاريخ الاستحقاق', x.dueDate == null ? '-' : fmtDate(x.dueDate!)),
    if (x.daysLeft(s.today) != null) ('فاضل كام يوم', '${x.daysLeft(s.today)}'),
  ],
);

final supplierSpec = EntitySpec<Supplier>(
  codec: supplierCodec,
  title: 'الموردين واللي علينا',
  single: 'مورد',
  icon: Icons.storefront,
  color: moneyColor,
  fields: [
    FieldSpec('code', 'الكود', FType.text, initial: (s) => _nextCode(s.values(supplierCodec).map((c) => c.code).toList(), 'م-', 3)),
    const FieldSpec('name', 'اسم المورد', FType.text, required: true),
    FieldSpec('type', 'النوع', FType.choice, options: fixedOptions(['مورد صين', 'مستخلص', 'مورد محلي', 'خدمات']), initial: (_) => 'مورد محلي'),
    const FieldSpec('isUsd', 'العملة دولار؟ (لأ = جنيه)', FType.yesNo),
    const FieldSpec('notDue', 'لسه ما استحقش', FType.number),
    const FieldSpec('late1to30', 'متأخر 1–30', FType.number),
    const FieldSpec('late31to60', 'متأخر 31–60', FType.number),
    const FieldSpec('late60plus', 'متأخر +60', FType.number),
    const FieldSpec('prepaid', 'دفعات مقدمة لينا عنده (بعملته)', FType.number),
    const FieldSpec('nearestDue', 'أقرب ميعاد سداد', FType.date),
  ],
  tileTitle: (x) => x.name,
  tileSub: (x, s) => 'الصافي علينا ${_m(x.netEgp(s.usdRate))} جنيه — خلال 7 أيام ${_m(x.dueIn7DaysEgp(s.usdRate, s.today))}',
  status: (x, s) => x.status,
  details: (x, s) => [
    ('الإجمالي بعملته', x.isUsd ? _usd(x.totalOwnCurrency) : _m(x.totalOwnCurrency)),
    ('الإجمالي بالجنيه', _m(x.totalEgp(s.usdRate))),
    ('الصافي علينا بالجنيه', _m(x.netEgp(s.usdRate))),
    ('مطلوب سداده خلال 7 أيام (جنيه)', _m(x.dueIn7DaysEgp(s.usdRate, s.today))),
    if (x.isUsd) ('سعر الدولار للتقييم', fmtDec(s.usdRate)),
  ],
);

// ═════════ الموظفين والمصروفات ═════════
final employeeSpec = EntitySpec<Employee>(
  codec: employeeCodec,
  title: 'الموظفين',
  single: 'موظف',
  icon: Icons.badge,
  color: moneyColor,
  fields: [
    FieldSpec('code', 'كود', FType.text, required: true, initial: (s) => _nextCode(_employeeCodes(s), 'ع-', 2)),
    const FieldSpec('name', 'الاسم', FType.text, required: true),
    FieldSpec('job', 'الوظيفة', FType.text, options: fixedOptions(['مسؤول المحل', 'بياع', 'أمين مخزن', 'كاشير'])),
    branchField(),
    const FieldSpec('hiredOn', 'تاريخ التعيين', FType.date),
    const FieldSpec('basic', 'المرتب الأساسي', FType.number, required: true),
    const FieldSpec('allowances', 'بدلات', FType.number),
  ],
  tileTitle: (x) => '${x.code} — ${x.name}',
  tileSub: (x, s) => '${x.job} — ${x.branch} — أساسي ${_m(x.basic)}',
  groupBy: 'branch',
);

final payrollEntrySpec = EntitySpec<PayrollEntry>(
  codec: payrollEntryCodec,
  title: 'كشف المرتبات',
  single: 'سطر مرتب',
  icon: Icons.request_page,
  color: moneyColor,
  fields: [
    FieldSpec('month', 'شهر المرتبات', FType.month, initial: (s) => DateTime(s.today.year, s.today.month, 1).toIso8601String()),
    FieldSpec('employeeCode', 'الموظف', FType.choice, options: _employeeCodes, required: true),
    const FieldSpec('commission', 'عمولة / حافز', FType.number),
    const FieldSpec('absenceDays', 'أيام الغياب', FType.number),
    const FieldSpec('penalties', 'جزاءات وتأخير', FType.number),
    const FieldSpec('insurance', 'تأمينات (حصة الموظف)', FType.number),
    FieldSpec('payMethod', 'طريقة الصرف', FType.choice, options: fixedOptions(['كاش', 'تحويل', 'محفظة']), initial: (_) => 'كاش'),
    const FieldSpec('signed', 'مضى بالاستلام؟', FType.yesNo),
  ],
  tileTitle: (x) => x.employeeCode,
  tileSub: (x, s) => monthNameShort(x.month),
  status: (x, s) => x.signed ? 'مضى' : 'لسه ما مضاش',
);

String monthNameShort(DateTime d) => '${d.month}/${d.year}';

String _advanceStatus(Advance a, AppState s) => a.status(
    payrollMonth: DateTime(s.today.year, s.today.month, 1), maxMultiple: s.advanceMax, basicSalary: s.employee(a.employeeCode)?.basic ?? 0);

final advanceSpec = EntitySpec<Advance>(
  codec: advanceCodec,
  title: 'السلف',
  single: 'سلفة',
  icon: Icons.handshake,
  color: moneyColor,
  fields: [
    dateField(),
    FieldSpec('employeeCode', 'كود الموظف', FType.choice, options: _employeeCodes, required: true),
    const FieldSpec('amount', 'المبلغ', FType.number, required: true),
    FieldSpec('installments', 'عدد الأقساط (شهور)', FType.number, initial: (_) => 1),
    FieldSpec('firstMonth', 'أول شهر خصم', FType.month, initial: (s) => DateTime(s.today.year, s.today.month, 1).toIso8601String()),
    const FieldSpec('ownerApproved', 'موافقة المالك', FType.yesNo),
  ],
  tileTitle: (x) => '${x.employeeCode} — ${x.amount == 0 ? '' : fmtNum(x.amount)}',
  tileSub: (x, s) {
    final m = DateTime(s.today.year, s.today.month, 1);
    return '${s.employee(x.employeeCode)?.name ?? 'كود مش موجود'} — القسط ${_m(x.monthly)} — الباقي ${_m(x.remainingAfter(m))}';
  },
  status: _advanceStatus,
  sortDate: (x) => x.date,
  details: (x, s) {
    final m = DateTime(s.today.year, s.today.month, 1);
    return [
      ('الاسم', s.employee(x.employeeCode)?.name ?? 'كود مش موجود'),
      ('القسط الشهري', _m(x.monthly)),
      ('آخر شهر خصم', monthNameShort(x.lastMonth)),
      ('بيتخصم الشهر ده', _m(x.deductionFor(m))),
      ('الباقي بعد مرتبات الشهر ده', _m(x.remainingAfter(m))),
      ('أقصى سلفة (${fmtDec(s.advanceMax)} × الأساسي)', _m(s.advanceMax * (s.employee(x.employeeCode)?.basic ?? 0))),
    ];
  },
);

final fixedExpenseSpec = EntitySpec<FixedExpense>(
  codec: fixedExpenseCodec,
  title: 'المصروفات الثابتة',
  single: 'مصروف ثابت',
  icon: Icons.event_repeat,
  color: moneyColor,
  fields: [
    FieldSpec('month', 'الشهر', FType.month, initial: (s) => DateTime(s.today.year, s.today.month, 1).toIso8601String()),
    const FieldSpec('name', 'البند', FType.text, required: true),
    FieldSpec('category', 'النوع', FType.choice, options: fixedOptions(expenseCategories), required: true),
    branchField(),
    const FieldSpec('expected', 'المبلغ المتوقع', FType.number, required: true),
    FieldSpec('dueDay', 'ميعاد الدفع (يوم في الشهر)', FType.number, initial: (_) => 1),
    const FieldSpec('paid', 'اتدفع؟', FType.yesNo),
    FieldSpec('actual', 'المبلغ الفعلي', FType.number, nullable: true, visible: (j) => j['paid'] == true),
    FieldSpec('receiptNo', 'رقم الإيصال / الفاتورة', FType.text, visible: (j) => j['paid'] == true),
  ],
  tileTitle: (x) => '${x.name} — ${_m(x.expected)}',
  tileSub: (x, s) => '${x.month == null ? '' : monthName(x.month!)} — يوم ${x.dueDay}${x.paid ? ' — اتدفع ${_m(x.actual ?? 0)}' : ''}',
  status: (x, s) => x.status,
  groupBy: 'branch',
  details: (x, s) => [if (x.difference != null) ('الفرق عن المتوقع', _m(x.difference!))],
);


final pettyExpenseSpec = EntitySpec<PettyExpense>(
  codec: pettyExpenseCodec,
  title: 'النثريات والمصروفات',
  single: 'مصروف نثري',
  icon: Icons.shopping_bag,
  color: moneyColor,
  fields: [
    dateField(),
    branchField(),
    FieldSpec('category', 'البند', FType.choice, options: fixedOptions(expenseCategories), required: true, initial: (_) => 'ضيافة ونثريات'),
    const FieldSpec('amount', 'المبلغ', FType.number, required: true),
    const FieldSpec('note', 'البيان', FType.text),
    const FieldSpec('hasInvoice', 'فيه فاتورة/إيصال؟', FType.yesNo),
    FieldSpec('invoiceNo', 'رقم الفاتورة', FType.text, visible: (j) => j['hasInvoice'] == true),
    FieldSpec('approvedBy', 'اعتمده', FType.choice,
        options: fixedOptions(['مسؤول المحل', 'مسؤول بورسعيد', 'صاحب المحل']),
        initial: (s) => s.lastBranch == 'بورسعيد' ? 'مسؤول بورسعيد' : 'مسؤول المحل'),
    const FieldSpec('reimbursed', 'اتعوّض في العهدة؟', FType.yesNo),
  ],
  tileTitle: (x) => '${x.category} — ${_m(x.amount)}',
  tileSub: (x, s) => '${fmtDate(x.date)} — ${x.branch}${x.note.isEmpty ? '' : ' — ${x.note}'}',
  status: (x, s) => x.status(s.pettyLimit),
  sortDate: (x) => x.date,
  groupBy: 'branch',
);

/// كل السجلات بالاسم (للتنقل من التنبيهات والتقارير)
final specsByCollection = <String, EntitySpec>{
  for (final s in <EntitySpec>[
    shipmentSpec, stockTransferSpec, stockCountSpec, cashHandoverSpec, safeMovementSpec, usdTransferSpec,
    customerSpec, statementSpec, collectionSpec, supplierSpec, employeeSpec, payrollEntrySpec, advanceSpec,
    fixedExpenseSpec, pettyExpenseSpec,
  ])
    s.codec.collection: s,
};
