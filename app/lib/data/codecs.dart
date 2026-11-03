// تحويل كل نوع بيانات لصيغة تتحفظ (JSON) وترجع زي ما هي.
import '../engine/cash.dart';
import 'store.dart' show Stored;
import '../engine/customers.dart';
import '../engine/landed_cost.dart';
import '../engine/payables_stock.dart';
import '../engine/payroll_expenses.dart';

typedef Json = Map<String, dynamic>;

String? _d(DateTime? v) => v?.toIso8601String();
DateTime? _pd(Object? v) => v == null ? null : DateTime.parse(v as String);
DateTime _rd(Object? v) => DateTime.parse(v as String);
double _n(Object? v) => (v as num?)?.toDouble() ?? 0;
double? _nn(Object? v) => (v as num?)?.toDouble();
String _s(Object? v) => (v as String?) ?? '';
bool _b(Object? v) => (v as bool?) ?? false;

/// كود واحد لكل نوع: بيعرف يحفظه ويرجّعه.
class Codec<T> {
  final String collection;
  final Json Function(T) encode;
  final T Function(Json) decode;
  const Codec(this.collection, this.encode, this.decode);

  /// السجل بيتعمل بنوعه الحقيقي (مهم لما الكود بيقرا كل الأنواع مع بعض)
  Stored<T> stored(String id, Json data, DateTime createdAt, DateTime updatedAt) =>
      Stored<T>(id, decode(data), createdAt, updatedAt);
}

// ───────── الشحنة (التكلفة الواصلة) ─────────
class Shipment {
  final String no;
  final DateTime? date;
  final double rate, profitMargin;
  final ShipmentCosts costs;
  final List<ShipmentItem> items;
  const Shipment({
    required this.no,
    this.date,
    required this.rate,
    this.profitMargin = 0.35,
    this.costs = const ShipmentCosts(),
    this.items = const [],
  });
  LandedCostResult calc() => calcLandedCost(
      rate: rate, profitMargin: profitMargin, costs: costs, items: items);
}

final shipmentCodec = Codec<Shipment>(
  'shipments',
  (s) => {
    'no': s.no,
    'date': _d(s.date),
    'rate': s.rate,
    'profitMargin': s.profitMargin,
    'costs': {
      'freight': s.costs.freight,
      'customs': s.costs.customs,
      'vat': s.costs.vat,
      'portFees': s.costs.portFees,
      'transport': s.costs.transport,
      'brokerCommission': s.costs.brokerCommission,
      'other': s.costs.other,
    },
    'items': [
      for (final i in s.items)
        {
          'model': i.model,
          'description': i.description,
          'color': i.color,
          'qty': i.qty,
          'unitUsd': i.unitUsd,
        }
    ],
  },
  (j) {
    final c = (j['costs'] as Map?)?.cast<String, dynamic>() ?? {};
    return Shipment(
      no: _s(j['no']),
      date: _pd(j['date']),
      rate: _n(j['rate']),
      profitMargin: _n(j['profitMargin']),
      costs: ShipmentCosts(
        freight: _n(c['freight']),
        customs: _n(c['customs']),
        vat: _n(c['vat']),
        portFees: _n(c['portFees']),
        transport: _n(c['transport']),
        brokerCommission: _n(c['brokerCommission']),
        other: _n(c['other']),
      ),
      items: [
        for (final i in (j['items'] as List? ?? []).cast<Map>())
          ShipmentItem(
            model: _s(i['model']),
            description: _s(i['description']),
            color: _s(i['color']),
            qty: _n(i['qty']),
            unitUsd: _n(i['unitUsd']),
          )
      ],
    );
  },
);

// ───────── تحويل مخزني ─────────
final stockTransferCodec = Codec<StockTransfer>(
  'stock_transfers',
  (t) => {
    'no': t.no,
    'sentAt': _d(t.sentAt),
    'receivedAt': _d(t.receivedAt),
    'from': t.from,
    'to': t.to,
    'driver': t.driver,
    'vehicle': t.vehicle,
    'lines': [
      for (final l in t.lines)
        {
          'code': l.code,
          'model': l.model,
          'color': l.color,
          'size': l.size,
          'sent': l.sent,
          'received': l.received,
        }
    ],
  },
  (j) => StockTransfer(
    no: _s(j['no']),
    sentAt: _rd(j['sentAt']),
    receivedAt: _pd(j['receivedAt']),
    from: _s(j['from']),
    to: _s(j['to']),
    driver: _s(j['driver']),
    vehicle: _s(j['vehicle']),
    lines: [
      for (final l in (j['lines'] as List? ?? []).cast<Map>())
        TransferLine(
          code: _s(l['code']),
          model: _s(l['model']),
          color: _s(l['color']),
          size: _s(l['size']),
          sent: _n(l['sent']),
          received: _nn(l['received']),
        )
    ],
  ),
);

// ───────── توريد النقدية ─────────
final cashHandoverCodec = Codec<CashHandover>(
  'cash_handovers',
  (h) => {
    'date': _d(h.date),
    'branch': h.branch,
    'reportNo': h.reportNo,
    'cashSales': h.cashSales,
    'collections': h.collections,
    'petty': h.petty,
    'delivered': h.delivered,
  },
  (j) => CashHandover(
    date: _rd(j['date']),
    branch: _s(j['branch']),
    reportNo: _s(j['reportNo']),
    cashSales: _n(j['cashSales']),
    collections: _n(j['collections']),
    petty: _n(j['petty']),
    delivered: _n(j['delivered']),
  ),
);

// ───────── خزنة المالك ─────────
final safeMovementCodec = Codec<SafeMovement>(
  'safe_movements',
  (m) => {
    'date': _d(m.date),
    'type': m.type,
    'note': m.note,
    'shipmentNo': m.shipmentNo,
    'amount': m.amount,
    'via': m.via,
    'hasDocument': m.hasDocument,
    'recorded': m.recorded,
    'weeklyConfirmed': m.weeklyConfirmed,
  },
  (j) => SafeMovement(
    date: _rd(j['date']),
    type: _s(j['type']),
    note: _s(j['note']),
    shipmentNo: _s(j['shipmentNo']),
    amount: _n(j['amount']),
    via: _s(j['via']),
    hasDocument: _b(j['hasDocument']),
    recorded: _b(j['recorded']),
    weeklyConfirmed: _b(j['weeklyConfirmed']),
  ),
);

// ───────── تحويلات الدولار ─────────
final usdTransferCodec = Codec<UsdTransfer>(
  'usd_transfers',
  (t) => {
    'date': _d(t.date),
    'voucherNo': t.voucherNo,
    'supplier': t.supplier,
    'shipmentNo': t.shipmentNo,
    'egpPaid': t.egpPaid,
    'usdReceived': t.usdReceived,
    'feesEgp': t.feesEgp,
    'method': t.method,
  },
  (j) => UsdTransfer(
    date: _rd(j['date']),
    voucherNo: _s(j['voucherNo']),
    supplier: _s(j['supplier']),
    shipmentNo: _s(j['shipmentNo']),
    egpPaid: _n(j['egpPaid']),
    usdReceived: _n(j['usdReceived']),
    feesEgp: _n(j['feesEgp']),
    method: _s(j['method']),
  ),
);

// ───────── العملاء ─────────
final customerCodec = Codec<Customer>(
  'customers',
  (c) => {
    'code': c.code,
    'name': c.name,
    'phone': c.phone,
    'branch': c.branch,
    'followUpBy': c.followUpBy,
    'creditLimit': c.creditLimit,
    'paymentDays': c.paymentDays,
    'b0to30': c.b0to30,
    'b31to60': c.b31to60,
    'b61to90': c.b61to90,
    'b90plus': c.b90plus,
    'lastCollection': _d(c.lastCollection),
    'weeklyTarget': c.weeklyTarget,
  },
  (j) => Customer(
    code: _s(j['code']),
    name: _s(j['name']),
    phone: _s(j['phone']),
    branch: _s(j['branch']),
    followUpBy: _s(j['followUpBy']),
    creditLimit: _n(j['creditLimit']),
    paymentDays: (j['paymentDays'] as num?)?.toInt() ?? 0,
    b0to30: _n(j['b0to30']),
    b31to60: _n(j['b31to60']),
    b61to90: _n(j['b61to90']),
    b90plus: _n(j['b90plus']),
    lastCollection: _pd(j['lastCollection']),
    weeklyTarget: _n(j['weeklyTarget']),
  ),
);

// ───────── كشف حساب عميل ─────────
final statementCodec = Codec<CustomerStatement>(
  'customer_statements',
  (s) => {
    'customer': s.customer,
    'from': _d(s.from),
    'to': _d(s.to),
    'opening': s.opening,
    'lines': [
      for (final l in s.lines)
        {
          'date': _d(l.date),
          'type': l.type,
          'docNo': l.docNo,
          'note': l.note,
          'debit': l.debit,
          'credit': l.credit,
        }
    ],
  },
  (j) => CustomerStatement(
    customer: _s(j['customer']),
    from: _rd(j['from']),
    to: _rd(j['to']),
    opening: _n(j['opening']),
    lines: [
      for (final l in (j['lines'] as List? ?? []).cast<Map>())
        StatementLine(
          date: _rd(l['date']),
          type: _s(l['type']),
          docNo: _s(l['docNo']),
          note: _s(l['note']),
          debit: _n(l['debit']),
          credit: _n(l['credit']),
        )
    ],
  ),
);

// ───────── التحصيلات والشيكات ─────────
final collectionCodec = Codec<Collection>(
  'collections',
  (c) => {
    'date': _d(c.date),
    'receiptNo': c.receiptNo,
    'customer': c.customer,
    'isCheque': c.isCheque,
    'amount': c.amount,
    'chequeNo': c.chequeNo,
    'bank': c.bank,
    'dueDate': _d(c.dueDate),
    'chequeState': c.chequeState,
  },
  (j) => Collection(
    date: _rd(j['date']),
    receiptNo: _s(j['receiptNo']),
    customer: _s(j['customer']),
    isCheque: _b(j['isCheque']),
    amount: _n(j['amount']),
    chequeNo: _s(j['chequeNo']),
    bank: _s(j['bank']),
    dueDate: _pd(j['dueDate']),
    chequeState: j['chequeState'] as String?,
  ),
);

// ───────── الموردين ─────────
final supplierCodec = Codec<Supplier>(
  'suppliers',
  (s) => {
    'code': s.code,
    'name': s.name,
    'type': s.type,
    'isUsd': s.isUsd,
    'notDue': s.notDue,
    'late1to30': s.late1to30,
    'late31to60': s.late31to60,
    'late60plus': s.late60plus,
    'prepaid': s.prepaid,
    'nearestDue': _d(s.nearestDue),
  },
  (j) => Supplier(
    code: _s(j['code']),
    name: _s(j['name']),
    type: _s(j['type']),
    isUsd: _b(j['isUsd']),
    notDue: _n(j['notDue']),
    late1to30: _n(j['late1to30']),
    late31to60: _n(j['late31to60']),
    late60plus: _n(j['late60plus']),
    prepaid: _n(j['prepaid']),
    nearestDue: _pd(j['nearestDue']),
  ),
);

// ───────── الجرد ─────────
final stockCountCodec = Codec<StockCount>(
  'stock_counts',
  (c) => {
    'place': c.place,
    'kind': c.kind,
    'date': _d(c.date),
    'lines': [
      for (final l in c.lines)
        {
          'code': l.code,
          'model': l.model,
          'color': l.color,
          'size': l.size,
          'reason': l.reason,
          'systemQty': l.systemQty,
          'actualQty': l.actualQty,
          'unitCost': l.unitCost,
        }
    ],
  },
  (j) => StockCount(
    place: _s(j['place']),
    kind: _s(j['kind']),
    date: _rd(j['date']),
    lines: [
      for (final l in (j['lines'] as List? ?? []).cast<Map>())
        CountLine(
          code: _s(l['code']),
          model: _s(l['model']),
          color: _s(l['color']),
          size: _s(l['size']),
          reason: _s(l['reason']),
          systemQty: _n(l['systemQty']),
          actualQty: _n(l['actualQty']),
          unitCost: _n(l['unitCost']),
        )
    ],
  ),
);

// ───────── الموظفين ─────────
final employeeCodec = Codec<Employee>(
  'employees',
  (e) => {
    'code': e.code,
    'name': e.name,
    'job': e.job,
    'branch': e.branch,
    'hiredOn': _d(e.hiredOn),
    'basic': e.basic,
    'allowances': e.allowances,
  },
  (j) => Employee(
    code: _s(j['code']),
    name: _s(j['name']),
    job: _s(j['job']),
    branch: _s(j['branch']),
    hiredOn: _pd(j['hiredOn']),
    basic: _n(j['basic']),
    allowances: _n(j['allowances']),
  ),
);

/// سطر كشف مرتبات شهري (المدخلات اللي بتتكتب كل شهر لكل موظف)
class PayrollEntry {
  final DateTime month;
  final String employeeCode, payMethod;
  final double commission, absenceDays, penalties, insurance;
  final bool signed;
  const PayrollEntry({
    required this.month,
    required this.employeeCode,
    this.commission = 0,
    this.absenceDays = 0,
    this.penalties = 0,
    this.insurance = 0,
    this.payMethod = 'كاش',
    this.signed = false,
  });
}

final payrollEntryCodec = Codec<PayrollEntry>(
  'payroll_entries',
  (p) => {
    'month': _d(p.month),
    'employeeCode': p.employeeCode,
    'commission': p.commission,
    'absenceDays': p.absenceDays,
    'penalties': p.penalties,
    'insurance': p.insurance,
    'payMethod': p.payMethod,
    'signed': p.signed,
  },
  (j) => PayrollEntry(
    month: _rd(j['month']),
    employeeCode: _s(j['employeeCode']),
    commission: _n(j['commission']),
    absenceDays: _n(j['absenceDays']),
    penalties: _n(j['penalties']),
    insurance: _n(j['insurance']),
    payMethod: _s(j['payMethod']),
    signed: _b(j['signed']),
  ),
);

// ───────── السلف ─────────
final advanceCodec = Codec<Advance>(
  'advances',
  (a) => {
    'date': _d(a.date),
    'employeeCode': a.employeeCode,
    'amount': a.amount,
    'installments': a.installments,
    'firstMonth': _d(a.firstMonth),
    'ownerApproved': a.ownerApproved,
  },
  (j) => Advance(
    date: _rd(j['date']),
    employeeCode: _s(j['employeeCode']),
    amount: _n(j['amount']),
    installments: (j['installments'] as num?)?.toInt() ?? 1,
    firstMonth: _rd(j['firstMonth']),
    ownerApproved: _b(j['ownerApproved']),
  ),
);

// ───────── المصروفات الثابتة ─────────
final fixedExpenseCodec = Codec<FixedExpense>(
  'fixed_expenses',
  (f) => {
    'month': _d(f.month),
    'name': f.name,
    'category': f.category,
    'branch': f.branch,
    'expected': f.expected,
    'dueDay': f.dueDay,
    'paid': f.paid,
    'actual': f.actual,
    'receiptNo': f.receiptNo,
  },
  (j) => FixedExpense(
    month: _pd(j['month']),
    name: _s(j['name']),
    category: _s(j['category']),
    branch: _s(j['branch']),
    expected: _n(j['expected']),
    dueDay: (j['dueDay'] as num?)?.toInt() ?? 1,
    paid: _b(j['paid']),
    actual: _nn(j['actual']),
    receiptNo: _s(j['receiptNo']),
  ),
);

// ───────── النثريات ─────────
final pettyExpenseCodec = Codec<PettyExpense>(
  'petty_expenses',
  (p) => {
    'date': _d(p.date),
    'branch': p.branch,
    'category': p.category,
    'note': p.note,
    'amount': p.amount,
    'hasInvoice': p.hasInvoice,
    'invoiceNo': p.invoiceNo,
    'approvedBy': p.approvedBy,
    'reimbursed': p.reimbursed,
  },
  (j) => PettyExpense(
    date: _rd(j['date']),
    branch: _s(j['branch']),
    category: _s(j['category']),
    note: _s(j['note']),
    amount: _n(j['amount']),
    hasInvoice: _b(j['hasInvoice']),
    invoiceNo: _s(j['invoiceNo']),
    approvedBy: _s(j['approvedBy']),
    reimbursed: _b(j['reimbursed']),
  ),
);

/// كل الأنواع (بتستخدم في النسخة الاحتياطية والتصدير)
final allCodecs = <Codec>[
  shipmentCodec,
  stockTransferCodec,
  cashHandoverCodec,
  safeMovementCodec,
  usdTransferCodec,
  customerCodec,
  statementCodec,
  collectionCodec,
  supplierCodec,
  stockCountCodec,
  employeeCodec,
  payrollEntryCodec,
  advanceCodec,
  fixedExpenseCodec,
  pettyExpenseCodec,
];
