// حالة التطبيق: كل البيانات في الذاكرة (قليلة) + بتتحفظ على طول في القاعدة.
import 'package:flutter/widgets.dart';

import '../data/codecs.dart';
import '../data/store.dart';
import '../engine/cash.dart';
import '../engine/customers.dart';
import '../engine/excel.dart';
import '../engine/payables_stock.dart';
import '../engine/payroll_expenses.dart';
import 'alerts.dart';

/// مفاتيح الإعدادات وقيمها الافتراضية (من الإكسل)
class K {
  static const lastBranch = 'lastBranch';
  static const pettyLimit = 'pettyLimit'; // النثريات C4 = 1000
  static const floatCairo = 'floatCairo'; // عهدة القاهرة 3000
  static const floatPortSaid = 'floatPortSaid'; // عهدة بورسعيد 3000
  static const advanceMax = 'advanceMax'; // السلف D4 = 0.5
  static const usdRate = 'usdRate'; // سعر الدولار للتقييم (الموردين B4) = 50
  static const profitMargin = 'profitMargin'; // التكلفة الواصلة B8 = 0.35
  static const budgets = 'budgets'; // ملخص المصروفات عمود E
  static const usdBalances = 'usdBalances'; // {المورد: {invoices, statement}}
  static const pinHash = 'pinHash';
  static const pinSalt = 'pinSalt';
  static const biometric = 'biometric';
  static const themeMode = 'themeMode'; // system / light / dark
  static const reminders = 'reminders';
  static String daily(DateTime d) => 'daily:${_ymd(d)}';
  static String weekly(DateTime from) => 'weekly:${_ymd(from)}';
  static String monthly(DateTime m) => 'monthly:${m.year}-${m.month.toString().padLeft(2, '0')}';
  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

const defaultBudgets = {
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

class AppState extends ChangeNotifier {
  final LocalStore store;
  final DateTime Function() clock;
  final Map<String, List<Stored>> _data = {};
  final Map<String, Object?> _settings = {};

  AppState(this.store, {DateTime Function()? clock}) : clock = clock ?? DateTime.now;

  DateTime get now => clock();
  DateTime get today => dateOnly(clock());

  Future<void> load() async {
    for (final c in allCodecs) {
      _data[c.collection] = await store.list(c);
    }
    final rows = await store.db.query('settings');
    _settings.clear();
    for (final r in rows) {
      _settings[r['key'] as String] = await store.setting(r['key'] as String);
    }
    notifyListeners();
  }

  List<Stored<T>> all<T>(Codec<T> c) => (_data[c.collection] ?? const []).cast<Stored<T>>();
  List<T> values<T>(Codec<T> c) => [for (final s in all(c)) s.value];
  Stored<T>? byId<T>(Codec<T> c, String id) {
    for (final s in all(c)) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<String> add<T>(Codec<T> c, T v) async {
    final id = await store.add(c, v);
    _data[c.collection] = await store.list(c);
    notifyListeners();
    return id;
  }

  Future<void> save<T>(Codec<T> c, String? id, T v) async {
    if (id == null) {
      await add(c, v);
      return;
    }
    await store.update(c, id, v);
    _data[c.collection] = await store.list(c);
    notifyListeners();
  }

  Future<void> remove(Codec c, String id) async {
    await store.remove(c, id);
    _data[c.collection] = await store.list(c);
    notifyListeners();
  }

  // ───────── الإعدادات ─────────
  T? setting<T>(String key) => _settings[key] as T?;
  double numOf(String key, double def) => (_settings[key] as num?)?.toDouble() ?? def;
  Future<void> set(String key, Object? v) async {
    await store.setSetting(key, v);
    _settings[key] = v;
    notifyListeners();
  }

  String get lastBranch => setting<String>(K.lastBranch) ?? 'القاهرة';
  Future<void> rememberBranch(String b) async {
    if (b != lastBranch && (b == 'القاهرة' || b == 'بورسعيد')) await set(K.lastBranch, b);
  }

  double get pettyLimit => numOf(K.pettyLimit, 1000);
  double get advanceMax => numOf(K.advanceMax, 0.5);
  double get usdRate => numOf(K.usdRate, 50);
  double get profitMargin => numOf(K.profitMargin, 0.35);
  double floatOf(String b) => b == 'بورسعيد' ? numOf(K.floatPortSaid, 3000) : numOf(K.floatCairo, 3000);
  Map<String, double> get budgets {
    final m = (setting<Map>(K.budgets) ?? const {}).cast<String, dynamic>();
    return {for (final e in defaultBudgets.entries) e.key: (m[e.key] as num?)?.toDouble() ?? e.value};
  }

  Map<String, dynamic> manual(String key) =>
      (setting<Map>(key) ?? const {}).cast<String, dynamic>();

  // ───────── مختصرات ─────────
  Employee? employee(String code) {
    for (final e in values(employeeCodec)) {
      if (e.code == code) return e;
    }
    return null;
  }

  List<AppAlert> alerts() => buildAlerts(
        now: now,
        handovers: all(cashHandoverCodec),
        safe: all(safeMovementCodec),
        customers: all(customerCodec),
        collections: all(collectionCodec),
        suppliers: all(supplierCodec),
        fixed: all(fixedExpenseCodec),
        petty: all(pettyExpenseCodec),
        transfers: all(stockTransferCodec),
        usdRate: usdRate,
        pettyLimit: pettyLimit,
      );

  /// كشف مرتبات شهر معين
  List<PayrollLine> payroll(DateTime month) {
    final m = DateTime(month.year, month.month, 1);
    final entries = {
      for (final e in values(payrollEntryCodec))
        if (e.month.year == m.year && e.month.month == m.month) e.employeeCode: e
    };
    return [
      for (final e in values(employeeCodec))
        payrollLine(e,
            payrollMonth: m,
            advances: values(advanceCodec).where((a) => a.ownerApproved).toList(),
            commission: entries[e.code]?.commission ?? 0,
            absenceDays: entries[e.code]?.absenceDays ?? 0,
            penalties: entries[e.code]?.penalties ?? 0,
            insurance: entries[e.code]?.insurance ?? 0),
    ];
  }

  /// ملخص مصروفات شهر
  List<BudgetLine> expenseSummaryFor(DateTime month) {
    final p = payroll(month);
    bool inMonth(DateTime? d) => d != null && d.year == month.year && d.month == month.month;
    return expenseSummary(
      cairo: branchPayroll('القاهرة', p),
      portSaid: branchPayroll('بورسعيد', p),
      fixed: values(fixedExpenseCodec).where((f) => inMonth(f.month)).toList(),
      petty: values(pettyExpenseCodec).where((x) => inMonth(x.date)).toList(),
      budgets: budgets,
    );
  }

  /// آخر سعر صرف فعلي (لتقييم الموردين والتكلفة الواصلة)
  double? averageRateFor(String shipmentNo) => averageRate(values(usdTransferCodec), shipmentNo: shipmentNo);

  StockCount? get lastStockCount {
    final l = values(stockCountCodec);
    if (l.isEmpty) return null;
    l.sort((a, b) => a.date.compareTo(b.date));
    return l.last;
  }

  Customer? customerByName(String name) {
    for (final c in values(customerCodec)) {
      if (c.name == name) return c;
    }
    return null;
  }

  Supplier? supplierByName(String name) {
    for (final s in values(supplierCodec)) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// يوصّل الحالة لكل الشاشات
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);
  static AppState of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext c) => c.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
