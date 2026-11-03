import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app/excel_export.dart';
import '../app/state.dart';
import '../engine/format.dart';
import 'common.dart';
import 'theme.dart';

Future<File> _tempFile(String name, List<int> bytes) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$name');
  await f.writeAsBytes(bytes, flush: true);
  return f;
}

String _stamp(DateTime d) => '${fmtDate(d)}_${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}';

/// تصدير إكسل وبعتُه (لجوجل درايف أو لنفسك على الواتساب/الإيميل)
Future<void> exportExcel(BuildContext context) async {
  final s = AppScope.read(context);
  try {
    final bytes = buildExcel(s);
    final f = await _tempFile('الدورة_المستندية_${_stamp(s.now)}.xlsx', bytes);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(f.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
      text: 'ملف الإكسل — ${fmtDate(s.today)}',
    ));
  } catch (e) {
    if (context.mounted) toast(context, 'ماعرفتش أعمل الملف: $e');
  }
}

class BackupScreen extends StatelessWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final last = s.setting<String>('lastBackupAt');
    return Scaffold(
      appBar: AppBar(title: const Text('النسخة الاحتياطية')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
          'كل بياناتك موجودة على الموبايل ده بس. النسخة الاحتياطية بتحط كل حاجة في ملف واحد، '
          'تحفظه على جوجل درايف أو تبعته لنفسك. لو غيرت الموبايل، نزّل التطبيق ورجّع الملف.',
          style: TextStyle(fontSize: 16, height: 1.6),
        ),
        const SizedBox(height: 8),
        Text(last == null ? 'لسه ما اتعملتش نسخة احتياطية' : 'آخر نسخة: ${last.substring(0, 16).replaceFirst('T', ' ')}',
            style: TextStyle(fontSize: 15, color: last == null ? dangerColor : okColor, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: moneyColor),
          icon: const Icon(Icons.cloud_upload),
          label: const Text('اعمل نسخة احتياطية وابعتها'),
          onPressed: () async {
            final text = await s.store.exportBackup();
            final f = await _tempFile('نسخة_احتياطية_حساباتي_${_stamp(s.now)}.json', utf8.encode(text));
            await s.set('lastBackupAt', s.now.toIso8601String());
            await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'application/json')], text: 'نسخة احتياطية — ${fmtDate(s.today)}'));
          },
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.teal),
          icon: const Icon(Icons.table_view),
          label: const Text('تصدير إكسل بنفس شكل الملف'),
          onPressed: () => exportExcel(context),
        ),
        const SizedBox(height: 32),
        OutlinedButton.icon(
          icon: const Icon(Icons.restore),
          label: const Text('رجّع نسخة احتياطية'),
          onPressed: () async {
            final pf = await FilePicker.pickFile(dialogTitle: 'اختار ملف النسخة الاحتياطية');
            if (pf == null || pf.path == null) return;
            if (!context.mounted) return;
            if (!await confirm(context, 'البيانات اللي على الموبايل دلوقتي هتتشال وتتحط مكانها النسخة دي. متأكد؟', yes: 'أيوه رجّعها')) return;
            try {
              final text = await File(pf.path!).readAsString();
              await s.store.restoreBackup(text);
              await s.load();
              if (context.mounted) toast(context, 'اترجعت النسخة ✔');
            } on FormatException catch (e) {
              if (context.mounted) toast(context, e.message);
            } catch (e) {
              if (context.mounted) toast(context, 'الملف ده مش نسخة احتياطية سليمة — البيانات ما اتغيرتش');
            }
          },
        ),
      ]),
    );
  }
}
