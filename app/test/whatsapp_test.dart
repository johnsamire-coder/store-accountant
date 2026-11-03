import 'package:flutter_test/flutter_test.dart';
import 'package:store_accountant/engine/cash.dart';
import 'package:store_accountant/engine/whatsapp.dart';

final today = DateTime(2026, 11, 3);

void main() {
  test('صرف دولار لشحنة', () {
    final r = parseWhatsApp('صرف | التاريخ: 2026-11-03 | المبلغ: 500,000 جنيه | الغرض: (دولار شحنة رقم ش-2026-02) | + صورة الإيصال', today: today).single;
    expect(r.ok, true, reason: r.problems.join());
    expect(r.kind, WaKind.spend);
    expect(r.safe!.type, SafeType.usd);
    expect(r.safe!.amount, 500000);
    expect(r.safe!.shipmentNo, 'ش-2026-02');
    expect(r.safe!.date, DateTime(2026, 11, 3));
    expect(r.safe!.hasDocument, false); // النص لوحده من غير صورة = مستند ناقص
    expect(r.safe!.status, 'مستند ناقص');
  });

  test('صرف شخصي/مستخلص/مصروف + أرقام عربي', () {
    final r = parseWhatsApp(
        'صرف | التاريخ: ٤/١١/٢٠٢٦ | المبلغ: ٢٠٬٠٠٠ جنيه | الغرض: (شخصي)\n'
        'صرف | التاريخ: 4/11 | المبلغ: 50 ألف | الغرض: (مستخلص)\n'
        'صرف | التاريخ: امبارح | المبلغ: 1500 | الغرض: (مصروف: صيانة عربية)',
        today: today);
    expect(r.length, 3);
    expect([r[0].safe!.type, r[0].safe!.amount, r[0].safe!.date], [SafeType.personal, 20000, DateTime(2026, 11, 4)]);
    expect([r[1].safe!.type, r[1].safe!.amount], [SafeType.broker, 50000]);
    expect([r[2].safe!.type, r[2].safe!.note, r[2].safe!.date], [SafeType.expenses, 'صيانة عربية', DateTime(2026, 11, 2)]);
  });

  test('دولار', () {
    final r = parseWhatsApp('دولار | التاريخ: 2026-10-25 | دفعت: 760,000 جنيه | اشتريت: 15,000 دولار | المورد: Guangzhou Textile Co. | الشحنة: ش-2026-01 | + صورة إشعار التحويل', today: today).single;
    expect(r.ok, true, reason: r.problems.join());
    expect(r.usd!.egpPaid, 760000);
    expect(r.usd!.usdReceived, 15000);
    expect(r.usd!.supplier, 'Guangzhou Textile Co.');
    expect(r.usd!.shipmentNo, 'ش-2026-01');
    expect(r.usd!.rate, closeTo(50.6666666666667, 1e-9));
    expect(r.safe, null); // قرار 3: رسالة الدولار ما بتسجلش صرف من الخزنة
  });

  test('إيداع', () {
    final r = parseWhatsApp('إيداع | التاريخ: 3-11-2026 | المبلغ: 100,000 جنيه | جاي منين: تحصيل شيك معرض النور', today: today).single;
    expect([r.safe!.type, r.safe!.amount, r.safe!.note], [SafeType.deposit, 100000, 'تحصيل شيك معرض النور']);
  });

  test('توريد', () {
    final r = parseWhatsApp('توريد | التاريخ: 2026-11-02 | الفرع: القاهرة | المبلغ: 23,800 | رقم المحضر: ت ن-002 | + صورة المحضر الموقّع', today: today).single;
    expect(r.ok, true, reason: r.problems.join());
    expect([r.handover!.branch, r.handover!.delivered, r.handover!.reportNo, r.handover!.date],
        ['القاهرة', 23800, 'ت ن-002', DateTime(2026, 11, 2)]);
  });

  test('تحويل مخزني', () {
    final r = parseWhatsApp('تحويل | رقم الإذن: ت-0001 | من: بورسعيد | لـ: القاهرة | عدد القطع: 100 | + صورة الإذن', today: today).single;
    expect(r.ok, true, reason: r.problems.join());
    expect([r.transfer!.no, r.transfer!.from, r.transfer!.to, r.transfer!.totalSent],
        ['ت-0001', 'بورسعيد الرئيسي', 'القاهرة الفرعي', 100]);
    expect(r.transfer!.receivedAt, null);
    final back = parseWhatsApp('تحويل | رقم الإذن: ت-0002 | من: القاهرة | إلى: بورسعيد | عدد القطع: ١٢', today: today).single;
    expect([back.transfer!.from, back.transfer!.to, back.transfer!.totalSent], ['القاهرة الفرعي', 'بورسعيد الرئيسي', 12]);
  });

  test('نسخة من شات الواتساب بأوقاتها وصورها ورسايل عادية في النص', () {
    const chat = '[3/11/2026, 9:58 م] الحاج: صباح الخير\n'
        '[3/11/2026, 10:01 م] الحاج: صرف | التاريخ: النهارده | المبلغ: 500 ألف جنيه | الغرض: (دولار شحنة رقم 2026-02)\n'
        '[3/11/2026, 10:01 م] الحاج: ‎image omitted\n'
        '[3/11/2026, 10:30 م] الحاج: إيداع | التاريخ: النهارده | المبلغ: 40,050 | جاي منين: توريد القاهرة\n'
        '3/11/26 11:02 م - مسؤول القاهرة: توريد | التاريخ: 3/11 | الفرع: محل القاهرة | المبلغ: 18,000 | رقم المحضر: ت ن-003\n'
        '3/11/26 11:03 م - مسؤول القاهرة: IMG-20261103-WA0007.jpg (file attached)';
    final r = parseWhatsApp(chat, today: today);
    expect(r.map((x) => x.kind).toList(), [WaKind.spend, WaKind.deposit, WaKind.handover]);
    expect(r[0].safe!.amount, 500000);
    expect(r[0].safe!.shipmentNo, 'ش-2026-02');
    expect(r[0].hasMedia, true);
    expect(r[0].safe!.status, 'مستني تسجيل'); // معاها صورة بس لسه ما اتسجلتش في السيستم
    expect(r[1].hasMedia, false);
    expect(r[2].handover!.branch, 'القاهرة');
    expect(r[2].handover!.delivered, 18000);
    expect(r[2].hasMedia, true);
  });

  test('رسالة ناقصة بتقول إيه اللي ناقص', () {
    final r = parseWhatsApp('صرف | التاريخ: ..... | المبلغ: ..... جنيه | الغرض: ', today: today).single;
    expect(r.ok, false);
    expect(r.problems, contains('المبلغ ناقص'));
    expect(r.safe!.date, today); // التاريخ الافتراضي النهارده
    expect(parseWhatsApp('أهلاً يا جماعة', today: today), isEmpty);
  });

  test('قراءة الأرقام والتواريخ', () {
    expect(parseAmount('1.5 مليون'), 1500000);
    expect(parseAmount('١٬٢٥٠٬٠٠٠ جنيه'), 1250000);
    expect(parseDate('31/12', today), DateTime(2025, 12, 31)); // لسه ما جاش السنة دي
    expect(parseDate('31/2/2026', today), null);
  });
}
