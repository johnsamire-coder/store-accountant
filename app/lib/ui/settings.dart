import 'package:flutter/material.dart';

import '../app/state.dart';
import 'common.dart';
import 'lock.dart';
import 'payroll.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final mode = s.setting<String>(K.themeMode) ?? 'system';
    Widget numSetting(String key, String label, double def, {String? note}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
            key: ValueKey('$key-${s.numOf(key, def)}'),
            initialValue: numText(s.numOf(key, def)),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [ThousandsFormatter()],
            decoration: InputDecoration(labelText: label, helperText: note),
            onFieldSubmitted: (t) => s.set(key, parseNum(t) ?? def),
            onChanged: (t) {
              final v = parseNum(t);
              if (v != null) s.set(key, v);
            },
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const SectionTitle('الشكل'),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'light', label: Text('فاتح'), icon: Icon(Icons.light_mode)),
            ButtonSegment(value: 'dark', label: Text('غامق'), icon: Icon(Icons.dark_mode)),
            ButtonSegment(value: 'system', label: Text('زي الموبايل'), icon: Icon(Icons.phone_android)),
          ],
          selected: {mode},
          onSelectionChanged: (v) => s.set(K.themeMode, v.first),
        ),
        const SectionTitle('القفل'),
        ListTile(
          leading: const Icon(Icons.pin),
          title: const Text('غيّر الرقم السري'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PinSetupScreen(changing: true))),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.fingerprint),
          title: const Text('افتح بالبصمة'),
          value: s.setting<bool>(K.biometric) ?? false,
          onChanged: (v) => s.set(K.biometric, v),
        ),
        const SectionTitle('التذكيرات'),
        SwitchListTile(
          secondary: const Icon(Icons.notifications_active),
          title: const Text('شغّل التذكيرات'),
          subtitle: const Text('10 الصبح اليومي • الخميس متابعة المالك • أول الشهر المطابقة • الشيكات • المصروفات الثابتة • المرتبات يوم 25'),
          value: s.setting<bool>(K.reminders) ?? true,
          onChanged: (v) => s.set(K.reminders, v),
        ),
        const SectionTitle('الحدود والأرقام الثابتة (من الإكسل)'),
        numSetting(K.pettyLimit, 'حد المصروف من غير موافقة المالك', 1000),
        numSetting(K.floatCairo, 'عهدة القاهرة الثابتة', 3000),
        numSetting(K.floatPortSaid, 'عهدة بورسعيد الثابتة', 3000),
        numSetting(K.advanceMax, 'أقصى سلفة = كام مرة من المرتب الأساسي', 0.5, note: '0.5 = نص المرتب'),
        numSetting(K.usdRate, 'سعر الدولار للتقييم (الموردين)', 50, note: 'آخر سعر صرف فعلي من تحويلات الدولار'),
        numSetting(K.profitMargin, 'نسبة الربح المطلوبة على التكلفة', 0.35, note: '0.35 = 35%'),
        ListTile(
          leading: const Icon(Icons.pie_chart),
          title: const Text('الميزانية الشهرية لكل بند'),
          subtitle: const Text('دوس على رقم الميزانية في ملخص المصروفات علشان تغيّره'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpenseSummaryScreen())),
        ),
        const SizedBox(height: 24),
        const Text('كل البيانات على الموبايل ده بس — مفيش حاجة بتطلع غير لما انت تصدّر أو تبعت.', textAlign: TextAlign.center),
      ]),
    );
  }
}
