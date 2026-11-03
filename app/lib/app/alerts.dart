// تنبيهات النهارده للشاشة الرئيسية — نفس القواعد اللي في الإكسل.
import '../data/codecs.dart';
import '../data/store.dart';
import '../engine/cash.dart';
import '../engine/customers.dart';
import '../engine/excel.dart';
import '../engine/format.dart';
import '../engine/payables_stock.dart';
import '../engine/payroll_expenses.dart';

enum AlertLevel { high, medium }

class AppAlert {
  final String group; // عنوان المجموعة
  final String title;
  final String detail;
  final AlertLevel level;
  final String collection; // يفتح السجل ده لما تدوس
  final String? id;
  const AppAlert(this.group, this.title, this.detail, this.level,
      this.collection, this.id);
}

class AlertGroups {
  static const cash = 'عجز في توريد النقدية';
  static const docs = 'حركات خزنة المالك ناقصها حاجة';
  static const customers = 'عملاء متجاوزين الحد أو متأخرين';
  static const cheques = 'شيكات مستحقة';
  static const payables = 'مطلوب سداده للموردين خلال 7 أيام';
  static const fixed = 'مصروفات ثابتة مستحقة';
  static const petty = 'نثريات من غير فاتورة أو فوق الحد';
  static const transfers = 'تحويلات مخزنية لسه ما اتستلمتش';
  static const order = [cash, docs, customers, cheques, payables, fixed, petty, transfers];
}

List<AppAlert> buildAlerts({
  required DateTime now,
  required List<Stored<CashHandover>> handovers,
  required List<Stored<SafeMovement>> safe,
  required List<Stored<Customer>> customers,
  required List<Stored<Collection>> collections,
  required List<Stored<Supplier>> suppliers,
  required List<Stored<FixedExpense>> fixed,
  required List<Stored<PettyExpense>> petty,
  required List<Stored<StockTransfer>> transfers,
  required double usdRate,
  required double pettyLimit,
}) {
  final today = dateOnly(now);
  final out = <AppAlert>[];

  // 1) عجز توريد آخر 7 أيام
  for (final h in handovers) {
    final age = daysBetween(h.value.date, today);
    if (h.value.status == 'عجز' && age >= 0 && age <= 7) {
      out.add(AppAlert(AlertGroups.cash, '${h.value.branch} — ${fmtDate(h.value.date)}',
          'عجز ${fmtNum(h.value.difference)} (المفروض ${fmtNum(h.value.expected)} واتورد ${fmtNum(h.value.delivered)})',
          AlertLevel.high, cashHandoverCodec.collection, h.id));
    }
  }
  // 2) خزنة المالك: مستند ناقص / مستني تسجيل
  for (final m in safe) {
    final st = m.value.status;
    if (st != 'تمام') {
      out.add(AppAlert(AlertGroups.docs, '${m.value.type} ${fmtNum(m.value.amount)}',
          '$st — ${fmtDate(m.value.date)}',
          st == 'مستند ناقص' ? AlertLevel.high : AlertLevel.medium,
          safeMovementCodec.collection, m.id));
    }
  }
  // 3) العملاء
  for (final c in customers) {
    final a = c.value.alert;
    if (a != CustomerAlert.ok) {
      out.add(AppAlert(AlertGroups.customers, c.value.name,
          '$a — الرصيد ${fmtNum(c.value.balance)} من حد ${fmtNum(c.value.creditLimit)}',
          a == CustomerAlert.over60 ? AlertLevel.medium : AlertLevel.high,
          customerCodec.collection, c.id));
    }
  }
  // 4) الشيكات: مستحقة خلال 7 أيام أو فات ميعادها، والمرتدة
  for (final c in collections) {
    final d = c.value.daysLeft(today);
    if (d != null && d <= 7) {
      out.add(AppAlert(AlertGroups.cheques, '${c.value.customer} — ${fmtNum(c.value.amount)}',
          d < 0 ? 'فات ميعاده من ${-d} يوم' : (d == 0 ? 'مستحق النهارده' : 'فاضل $d يوم'),
          d <= 2 ? AlertLevel.high : AlertLevel.medium, collectionCodec.collection, c.id));
    } else if (c.value.chequeState == ChequeState.bounced) {
      out.add(AppAlert(AlertGroups.cheques, '${c.value.customer} — ${fmtNum(c.value.amount)}',
          'شيك مرتد', AlertLevel.high, collectionCodec.collection, c.id));
    }
  }
  // 5) الموردين
  for (final s in suppliers) {
    final due = s.value.dueIn7DaysEgp(usdRate, today);
    if (due > 0) {
      out.add(AppAlert(AlertGroups.payables, s.value.name,
          '${fmtNum(due)} جنيه — ${s.value.status}',
          s.value.late60plus > 0 ? AlertLevel.high : AlertLevel.medium,
          supplierCodec.collection, s.id));
    }
  }
  // 6) المصروفات الثابتة للشهر ده اللي لسه ما اتدفعتش وميعادها خلال 3 أيام أو فات
  for (final f in fixed) {
    final m = f.value.month;
    if (f.value.paid || m == null || m.year != today.year || m.month != today.month) continue;
    final left = f.value.dueDay - today.day;
    if (left <= 3) {
      out.add(AppAlert(AlertGroups.fixed, '${f.value.name} — ${fmtNum(f.value.expected)}',
          left < 0 ? 'ميعاده كان يوم ${f.value.dueDay} وفات' : (left == 0 ? 'ميعاده النهارده' : 'ميعاده يوم ${f.value.dueDay}'),
          left < 0 ? AlertLevel.high : AlertLevel.medium, fixedExpenseCodec.collection, f.id));
    }
  }
  // 7) النثريات
  for (final p in petty) {
    final st = p.value.status(pettyLimit);
    if (st != 'تمام') {
      out.add(AppAlert(AlertGroups.petty, '${p.value.branch} — ${p.value.note.isEmpty ? p.value.category : p.value.note} ${fmtNum(p.value.amount)}',
          st, AlertLevel.medium, pettyExpenseCodec.collection, p.id));
    }
  }
  // 8) التحويلات المعلّقة
  for (final t in transfers) {
    if (t.value.receivedAt != null) continue;
    final over = t.value.isPendingOver48h(now);
    out.add(AppAlert(AlertGroups.transfers, 'إذن ${t.value.no} — ${fmtNum(t.value.totalSent)} قطعة',
        over ? 'معلّق أكتر من 48 ساعة' : 'خرج ${fmtDate(t.value.sentAt)} ولسه ما اتأكدش',
        over ? AlertLevel.high : AlertLevel.medium, stockTransferCodec.collection, t.id));
  }
  out.sort((a, b) {
    final g = AlertGroups.order.indexOf(a.group) - AlertGroups.order.indexOf(b.group);
    return g != 0 ? g : a.level.index - b.level.index;
  });
  return out;
}
