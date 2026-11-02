// نفس بيانات المثال اللي في ملف الإكسل بالظبط، علشان نقارن النتايج.
import 'package:store_accountant/engine/cash.dart';
import 'package:store_accountant/engine/customers.dart';
import 'package:store_accountant/engine/landed_cost.dart';
import 'package:store_accountant/engine/payables_stock.dart';
import 'package:store_accountant/engine/payroll_expenses.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

/// اليوم اللي الملف اتحفظ فيه (الشيك المستحق 2026-12-15 كان فاضله 42 يوم)
final savedOn = d(2026, 11, 3);

const shipmentCosts = ShipmentCosts(
  freight: 60000,
  customs: 120000,
  vat: 95000,
  portFees: 15000,
  transport: 8000,
  brokerCommission: 25000,
  other: 0,
);

const shipmentItems = [
  ShipmentItem(model: 'SH-101', description: 'قميص كاجوال', color: 'أزرق', qty: 1200, unitUsd: 4.5),
  ShipmentItem(model: 'PN-220', description: 'بنطلون جينز', color: 'أسود', qty: 800, unitUsd: 7),
  ShipmentItem(model: 'TS-330', description: 'تيشيرت قطن', color: 'أبيض', qty: 2000, unitUsd: 2.2),
  ShipmentItem(model: 'JK-410', description: 'جاكيت شتوي', color: 'كحلي', qty: 300, unitUsd: 15),
];

final handovers = [
  CashHandover(date: d(2026, 11, 1), branch: 'القاهرة', reportNo: 'ت ن-001', cashSales: 18500, collections: 22000, petty: 450, delivered: 40050),
  CashHandover(date: d(2026, 11, 2), branch: 'القاهرة', reportNo: 'ت ن-002', cashSales: 15200, collections: 9000, petty: 300, delivered: 23800),
];

final safeMovements = [
  SafeMovement(date: d(2026, 11, 3), type: SafeType.usd, note: 'دولار للشحنة الجاية', shipmentNo: 'ش-2026-02', amount: 500000, hasDocument: true, recorded: true, weeklyConfirmed: true),
  SafeMovement(date: d(2026, 11, 4), type: SafeType.personal, note: 'مصاريف البيت', amount: 20000),
];

final usdTransfers = [
  UsdTransfer(date: d(2026, 10, 10), voucherNo: 'ص-0101', supplier: 'Guangzhou Textile Co.', shipmentNo: 'ش-2026-01', egpPaid: 1000000, usdReceived: 20000, feesEgp: 1500, method: 'شركة صرافة'),
  UsdTransfer(date: d(2026, 10, 25), voucherNo: 'ص-0108', supplier: 'Guangzhou Textile Co.', shipmentNo: 'ش-2026-01', egpPaid: 760000, usdReceived: 15000, feesEgp: 1000, method: 'شركة صرافة'),
];

final customers = [
  Customer(code: 'ع-001', name: 'محلات الأمل', branch: 'القاهرة', creditLimit: 150000, paymentDays: 45, b0to30: 80000, b31to60: 40000, lastCollection: d(2026, 10, 20), weeklyTarget: 40000),
  Customer(code: 'ع-002', name: 'معرض النور', branch: 'القاهرة', creditLimit: 100000, paymentDays: 30, b0to30: 30000, b31to60: 25000, b61to90: 20000, b90plus: 35000, lastCollection: d(2026, 9, 15), weeklyTarget: 35000),
  Customer(code: 'ع-003', name: 'الشروق للملابس', branch: 'بورسعيد', creditLimit: 80000, paymentDays: 30, b0to30: 95000, lastCollection: d(2026, 10, 28), weeklyTarget: 15000),
];

final statement = CustomerStatement(
  customer: 'محلات الأمل',
  from: d(2026, 10, 1),
  to: d(2026, 11, 2),
  opening: 60000,
  lines: [
    StatementLine(date: d(2026, 10, 5), type: 'فاتورة آجل', docNo: '2201', note: 'بضاعة متنوعة', debit: 50000),
    StatementLine(date: d(2026, 10, 20), type: 'تحصيل نقدي', docNo: '1001', note: 'إيصال تحصيل', credit: 22000),
    StatementLine(date: d(2026, 10, 25), type: 'مرتجع', docNo: 'م-15', note: 'مرتجع قمصان', credit: 3000),
    StatementLine(date: d(2026, 11, 1), type: 'فاتورة آجل', docNo: '2240', note: 'بضاعة شتوي', debit: 40000),
  ],
);

final collections = [
  Collection(date: d(2026, 11, 1), receiptNo: '1001', customer: 'محلات الأمل', isCheque: false, amount: 22000),
  Collection(date: d(2026, 11, 2), receiptNo: '1002', customer: 'معرض النور', isCheque: true, amount: 30000, chequeNo: '556677', bank: 'بنك مصر', dueDate: d(2026, 12, 15), chequeState: ChequeState.inSafe),
];

final suppliers = [
  const Supplier(code: 'م-001', name: 'Guangzhou Textile Co.', type: 'مورد صين', isUsd: true, prepaid: 1000),
  const Supplier(code: 'م-002', name: 'المستخلص الجمركي', type: 'مستخلص', late1to30: 50000),
  Supplier(code: 'م-003', name: 'مورد أكياس وشماعات', type: 'مورد محلي', notDue: 15000, nearestDue: d(2026, 11, 6)),
];

final stockCount = StockCount(place: 'مخزن القاهرة', kind: 'عيّنة مفاجئة', date: d(2026, 11, 8), lines: const [
  CountLine(code: 'SH-101-BL-L', model: 'قميص كاجوال', color: 'أزرق', size: 'L', systemQty: 45, actualQty: 45, unitCost: 263),
  CountLine(code: 'PN-220-BK-32', model: 'بنطلون جينز', color: 'أسود', size: '32', systemQty: 30, actualQty: 28, unitCost: 409),
]);

const employees = [
  Employee(code: 'ع-01', name: 'أحمد محمود', job: 'مسؤول المحل', branch: 'القاهرة', basic: 9000, allowances: 1000),
  Employee(code: 'ع-02', name: 'محمد علي', job: 'بياع', branch: 'القاهرة', basic: 6000, allowances: 500),
  Employee(code: 'ع-03', name: 'كريم سمير', job: 'بياع', branch: 'القاهرة', basic: 5500, allowances: 500),
  Employee(code: 'ع-04', name: 'مصطفى حسن', job: 'أمين مخزن', branch: 'بورسعيد', basic: 7000, allowances: 700),
  Employee(code: 'ع-05', name: 'إبراهيم فتحي', job: 'بياع', branch: 'بورسعيد', basic: 6000, allowances: 500),
];

// العمولة، أيام الغياب، التأمينات لكل موظف (نفس ترتيب الكشف)
const payrollInputs = {
  'ع-01': (1500.0, 0.0, 0.0),
  'ع-02': (1200.0, 1.0, 0.0),
  'ع-03': (900.0, 0.0, 200.0),
  'ع-04': (0.0, 0.0, 0.0),
  'ع-05': (1100.0, 2.0, 0.0),
};

final advances = [
  Advance(date: d(2026, 10, 10), employeeCode: 'ع-02', amount: 3000, installments: 3, firstMonth: d(2026, 11, 1), ownerApproved: true),
  Advance(date: d(2026, 10, 25), employeeCode: 'ع-05', amount: 2000, installments: 1, firstMonth: d(2026, 11, 1), ownerApproved: true),
];

const fixedExpenses = [
  FixedExpense(name: 'إيجار محل القاهرة', category: 'إيجارات', branch: 'القاهرة', expected: 25000, dueDay: 1, paid: true, actual: 25000, receiptNo: 'إيصال 11/2026'),
  FixedExpense(name: 'إيجار المحل والمخزن بورسعيد', category: 'إيجارات', branch: 'بورسعيد', expected: 30000, dueDay: 1, paid: true, actual: 30000, receiptNo: 'إيصال 11/2026'),
  FixedExpense(name: 'كهرباء محل القاهرة', category: 'كهرباء ومياه', branch: 'القاهرة', expected: 3500, dueDay: 10, paid: true, actual: 4200, receiptNo: 'فاتورة 11/2026'),
  FixedExpense(name: 'كهرباء بورسعيد', category: 'كهرباء ومياه', branch: 'بورسعيد', expected: 4000, dueDay: 10, paid: false),
  FixedExpense(name: 'نت وتليفونات', category: 'نت وتليفونات', branch: 'القاهرة', expected: 800, dueDay: 5, paid: true, actual: 800, receiptNo: 'فاتورة'),
  FixedExpense(name: 'أمن ونظافة بورسعيد', category: 'أمن ونظافة', branch: 'بورسعيد', expected: 2500, dueDay: 1, paid: true, actual: 2500, receiptNo: 'إيصال'),
  FixedExpense(name: 'اشتراك السيستم السحابي', category: 'اشتراك السيستم', branch: 'القاهرة', expected: 1500, dueDay: 1, paid: true, actual: 1500, receiptNo: 'فاتورة'),
];

const pettyLimit = 1000.0;
final petty = [
  PettyExpense(date: d(2026, 11, 1), branch: 'القاهرة', category: 'ضيافة ونثريات', note: 'مية وشاي للمحل', amount: 250, hasInvoice: true, invoiceNo: '112', approvedBy: 'مسؤول المحل'),
  PettyExpense(date: d(2026, 11, 2), branch: 'القاهرة', category: 'صيانة', note: 'تصليح تكييف', amount: 1800, hasInvoice: true, invoiceNo: '4501', approvedBy: 'صاحب المحل'),
  PettyExpense(date: d(2026, 11, 2), branch: 'بورسعيد', category: 'نقل بين المخازن', note: 'نقل بضاعة للقاهرة', amount: 1200, hasInvoice: false, approvedBy: 'مسؤول بورسعيد'),
  PettyExpense(date: d(2026, 11, 3), branch: 'القاهرة', category: 'دعاية', note: 'طباعة ورق دعاية', amount: 600, hasInvoice: true, invoiceNo: '77', approvedBy: 'مسؤول المحل'),
];

const budgets = {
  'مرتبات وأجور': 48000.0,
  'عمولات وحوافز': 5000.0,
  'إيجارات': 55000.0,
  'كهرباء ومياه': 8000.0,
  'نت وتليفونات': 1000.0,
  'أمن ونظافة': 2500.0,
  'صيانة': 1000.0,
  'نقل بين المخازن': 3000.0,
  'دعاية': 1000.0,
  'ضيافة ونثريات': 1500.0,
  'اشتراك السيستم': 1500.0,
  'أخرى': 1000.0,
};
