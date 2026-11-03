// صور للشاشات بالخط الحقيقي (بتشتغل بس لما SCREENSHOTS_DIR يتحدد)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_accountant/app/state.dart';
import 'package:store_accountant/main.dart';
import 'package:store_accountant/ui/home.dart';
import 'package:store_accountant/ui/lock.dart';
import 'package:store_accountant/ui/paste.dart';
import 'package:store_accountant/ui/registers.dart';
import 'package:store_accountant/ui/reports.dart';
import 'package:store_accountant/ui/specs.dart';

import 'seed.dart';

final outDir = Platform.environment['SCREENSHOTS_DIR'];

Future<void> loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await l.load();
  }

  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/opt/sdk/flutter';
  await load('NotoSansArabic', ['assets/fonts/NotoSansArabic-Regular.ttf', 'assets/fonts/NotoSansArabic-Bold.ttf']);
  await load('MaterialIcons', ['$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
  await load('NotoSans', ['assets/fonts/NotoSans-Regular.ttf', 'assets/fonts/NotoSans-Bold.ttf']);
  await load('Roboto', ['assets/fonts/NotoSans-Regular.ttf', 'assets/fonts/NotoSans-Bold.ttf']);
}

Future<void> shot(WidgetTester t, String name) async {
  await t.pumpAndSettle();
  final rb = t.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
  await t.runAsync(() async {
    final img = await rb.toImage(pixelRatio: 1.5);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$outDir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Future<AppState> app(WidgetTester t, Widget home, {String theme = 'light'}) async {
  late AppState s;
  await t.runAsync(() async {
    s = await makeState();
    await s.set(K.themeMode, theme);
  });
  t.view.physicalSize = const Size(412 * 1.5, 915 * 1.5);
  t.view.devicePixelRatio = 1.5;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox());
  await t.pumpWidget(HesabatyApp(state: s, home: home));
  await t.pumpAndSettle();
  return s;
}

void main() {
  final skip = outDir == null;
  setUpAll(() async {
    if (!skip) await loadFonts();
  });

  testWidgets('صور الشاشات', (t) async {
    await app(t, const HomeShell());
    await shot(t, '01_home');
    await t.tap(find.text('إضافة سريعة'));
    await t.pumpAndSettle();
    await shot(t, '02_quick_add');
    await t.tap(find.text('توريد نقدية'));
    await t.pumpAndSettle();
    await shot(t, '03_handover_form');

    await app(t, const PasteScreen(
        initialText: 'صرف | التاريخ: 2026-11-03 | المبلغ: 15,000 جنيه | الغرض: (مستخلص)\n'
            'دولار | التاريخ: 2026-11-03 | دفعت: 510,000 جنيه | اشتريت: 10,000 دولار | المورد: Guangzhou Textile Co. | الشحنة: ش-2026-02'));
    await t.tap(find.text('اقرا الرسايل'));
    await shot(t, '04_paste_whatsapp');

    await app(t, const DailyReportScreen());
    await t.tap(find.byIcon(Icons.chevron_right).first);
    await t.pumpAndSettle();
    await t.drag(find.byType(Scrollable).first, const Offset(0, -2600));
    await shot(t, '05_daily_report');

    await app(t, const WeeklyReportScreen());
    await t.drag(find.byType(Scrollable).first, const Offset(0, -900));
    await shot(t, '06_weekly_report');

    await app(t, const MonthlyReportScreen());
    await t.tap(find.byIcon(Icons.chevron_left).first);
    await t.pumpAndSettle();
    await t.tap(find.text('الأرقام اللي بتتنقل من السيستم آخر الشهر'));
    await t.pumpAndSettle();
    await shot(t, '07_monthly_report');

    await app(t, const HomeShell());
    await t.tap(find.text('البضاعة'));
    await t.pumpAndSettle();
    await t.tap(find.text('الشحنات والتكلفة الواصلة'));
    await t.pumpAndSettle();
    await t.tap(find.text('ش-2026-01'));
    await t.pumpAndSettle();
    await t.drag(find.byType(Scrollable).first, const Offset(0, -450));
    await shot(t, '08_shipment_landed_cost');

    await app(t, CollectionScreen(spec: customerSpec));
    await shot(t, '09_customers');

    await app(t, const HomeShell(), theme: 'dark');
    await shot(t, '10_home_dark');

    await app(t, const LockGate(child: SizedBox()));
    await shot(t, '11_lock');
  }, skip: skip);
}
