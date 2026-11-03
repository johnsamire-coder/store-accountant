// الحفظ على الموبايل: كل بيانات مثال الإكسل تتحفظ وترجع وتدي نفس النتايج.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:store_accountant/data/codecs.dart';
import 'package:store_accountant/data/store.dart';
import 'package:store_accountant/engine/cash.dart';
import 'package:store_accountant/engine/format.dart';

import 'workbook_example.dart';

Future<LocalStore> fresh() => LocalStore.open(
    databaseFactoryFfi, inMemoryDatabasePath,
    clock: () => DateTime(2026, 11, 3, 10), singleInstance: false);

Future<void> seed(LocalStore s) async {
  await s.add(shipmentCodec, const Shipment(no: 'ش-2026-01', rate: 50, costs: shipmentCosts, items: shipmentItems));
  for (final x in handovers) { await s.add(cashHandoverCodec, x); }
  for (final x in safeMovements) { await s.add(safeMovementCodec, x); }
  for (final x in usdTransfers) { await s.add(usdTransferCodec, x); }
  for (final x in customers) { await s.add(customerCodec, x); }
  await s.add(statementCodec, statement);
  for (final x in collections) { await s.add(collectionCodec, x); }
  for (final x in suppliers) { await s.add(supplierCodec, x); }
  await s.add(stockCountCodec, stockCount);
  for (final x in employees) { await s.add(employeeCodec, x); }
  for (final x in advances) { await s.add(advanceCodec, x); }
  for (final x in fixedExpenses) { await s.add(fixedExpenseCodec, x); }
  for (final x in petty) { await s.add(pettyExpenseCodec, x); }
  await s.add(stockTransferCodec, StockTransfer(no: 'ت-0001', sentAt: DateTime(2026, 11, 5, 9), lines: const [
    TransferLine(code: 'SH-101-BL-L', sent: 60, received: 60),
    TransferLine(code: 'SH-101-BL-XL', sent: 40, received: 39),
  ]));
  await s.setSetting('lastBranch', 'القاهرة');
  await s.setSetting('pettyLimit', 1000);
}

Future<void> expectWorkbookResults(LocalStore s) async {
  final sh = (await s.values(shipmentCodec)).single.calc();
  expect(fmtDec(sh.lines.first.costPerPiece), '298.04');
  final h = await s.values(cashHandoverCodec);
  expect(h.map((x) => x.status).toList(), ['مطابق', 'عجز']);
  expect(h[1].difference, -100);
  final adv = (await s.values(advanceCodec)).first;
  expect(adv.remainingAfter(d(2026, 11, 1)), 2000);
  expect((await s.values(statementCodec)).single.closing, 125000);
  final b = safeWeekBalance(opening: 1500000, from: d(2026, 11, 1), to: d(2026, 11, 7),
      handovers: h, movements: await s.values(safeMovementCodec));
  expect(b.expected, 1043850);
  expect((await s.values(customerCodec)).map((c) => c.alert).toList(),
      ['سليم', 'متأخر +90 — وقف البيع الآجل', 'متجاوز الحد']);
  expect((await s.values(collectionCodec))[1].daysLeft(savedOn), 42);
  expect((await s.values(stockTransferCodec)).single.totalDifference, -1);
  expect(await s.setting<String>('lastBranch'), 'القاهرة');
}

void main() {
  sqfliteFfiInit();

  test('كل بيانات الإكسل تتحفظ وترجع بنفس النتايج', () async {
    final s = await fresh();
    await seed(s);
    await expectWorkbookResults(s);
    await s.close();
  });

  test('كل حفظ/تعديل/مسح بيتسجل علشان الربط بسيرفر بعدين', () async {
    final s = await fresh();
    final id = await s.add(cashHandoverCodec, handovers.first);
    await s.update(cashHandoverCodec, id, handovers.last);
    expect((await s.get(cashHandoverCodec, id))!.value.delivered, 23800);
    await s.remove(cashHandoverCodec, id);
    expect(await s.get(cashHandoverCodec, id), null);
    expect(await s.list(cashHandoverCodec), isEmpty);
    expect((await s.pendingChanges()).map((c) => c['op']).toList(), ['add', 'update', 'delete']);
    expect(s.deviceId, isNotEmpty);
    await s.close();
  });

  test('النسخة الاحتياطية: تتصدّر وترجع في موبايل جديد بنفس الأرقام', () async {
    final a = await fresh();
    await seed(a);
    final backup = await a.exportBackup();
    await a.close();

    final b = await fresh();
    await b.add(customerCodec, customers.first); // بيانات قديمة هتتشال
    await b.restoreBackup(backup);
    await expectWorkbookResults(b);
    expect((await b.values(customerCodec)).length, 3);
    await b.close();
  });

  test('ملف بايظ ما يبوّظش البيانات الموجودة', () async {
    final s = await fresh();
    await seed(s);
    await expectLater(s.restoreBackup('مش ملف'), throwsFormatException);
    await expectLater(s.restoreBackup('{"format":"x"}'), throwsFormatException);
    await expectLater(
        s.restoreBackup('{"format":"store-accountant-backup","schema":1,"records":[{"collection":"customers","data":{"creditLimit":"غلط"}}]}'),
        throwsA(anything));
    await expectWorkbookResults(s);
    await s.close();
  });
}
