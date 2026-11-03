import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'app/reminders.dart';
import 'app/state.dart';
import 'data/store.dart';
import 'ui/home.dart';
import 'ui/lock.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getDatabasesPath();
  final store = await LocalStore.open(databaseFactory, p.join(dir, 'hesabaty.db'));
  final state = AppState(store);
  await state.load();
  final reminders = ReminderService();
  Timer? t;
  void resync() {
    t?.cancel();
    t = Timer(const Duration(seconds: 2), () => reminders.sync(state).catchError((_) {}));
  }

  state.addListener(resync);
  resync();
  runApp(HesabatyApp(state: state));
}

class HesabatyApp extends StatelessWidget {
  final AppState state;
  final Widget? home; // للاختبارات
  const HesabatyApp({super.key, required this.state, this.home});

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: Builder(builder: (context) {
        final mode = AppScope.of(context).setting<String>(K.themeMode) ?? 'system';
        return MaterialApp(
          title: 'حساباتي',
          debugShowCheckedModeBanner: false,
          locale: const Locale('ar', 'EG'),
          supportedLocales: const [Locale('ar', 'EG'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: mode == 'light' ? ThemeMode.light : (mode == 'dark' ? ThemeMode.dark : ThemeMode.system),
          home: home ?? const LockGate(child: HomeShell()),
        );
      }),
    );
  }
}
