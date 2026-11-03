// قاعدة البيانات على الموبايل.
// كل سجل ليه رقم ثابت (uuid) + وقت آخر تعديل + علامة مسح (مش بيتمسح فعلاً)،
// وكل تغيير بيتكتب في جدول (changes). ده اللي هيخلّي الربط بسيرفر خاص
// بعدين سهل: السيرفر ياخد التغييرات اللي لسه ما اتبعتتش. الربط نفسه مش مبني دلوقتي.
import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'codecs.dart';

class Stored<T> {
  final String id;
  final T value;
  final DateTime createdAt, updatedAt;
  const Stored(this.id, this.value, this.createdAt, this.updatedAt);
}

class LocalStore {
  static const schemaVersion = 1;
  static const backupFormat = 'store-accountant-backup';

  final Database db;
  final String deviceId;
  final DateTime Function() _now;
  static const _uuid = Uuid();

  LocalStore._(this.db, this.deviceId, this._now);

  /// يفتح (أو ينشئ) القاعدة. [path] = inMemoryDatabasePath في الاختبارات.
  static Future<LocalStore> open(
    DatabaseFactory factory,
    String path, {
    DateTime Function()? clock,
    bool singleInstance = true,
  }) async {
    final db = await factory.openDatabase(path,
        options: OpenDatabaseOptions(
          version: schemaVersion,
          singleInstance: singleInstance,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE records(
                collection TEXT NOT NULL,
                id TEXT NOT NULL,
                data TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                deleted INTEGER NOT NULL DEFAULT 0,
                device_id TEXT NOT NULL,
                PRIMARY KEY(collection, id))''');
            await db.execute(
                'CREATE INDEX idx_records_col ON records(collection, deleted)');
            await db.execute('''
              CREATE TABLE changes(
                seq INTEGER PRIMARY KEY AUTOINCREMENT,
                collection TEXT NOT NULL,
                id TEXT NOT NULL,
                op TEXT NOT NULL,
                at TEXT NOT NULL,
                synced INTEGER NOT NULL DEFAULT 0)''');
            await db.execute(
                'CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
          },
        ));
    final clk = clock ?? DateTime.now;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: ['device_id']);
    String dev;
    if (rows.isEmpty) {
      dev = _uuid.v4();
      await db.insert('settings', {'key': 'device_id', 'value': jsonEncode(dev)});
    } else {
      dev = jsonDecode(rows.first['value'] as String) as String;
    }
    return LocalStore._(db, dev, clk);
  }

  Future<void> close() => db.close();

  // ───────── السجلات ─────────
  Future<String> add<T>(Codec<T> c, T value) async {
    final id = _uuid.v4();
    final now = _now().toIso8601String();
    await db.transaction((tx) async {
      await tx.insert('records', {
        'collection': c.collection,
        'id': id,
        'data': jsonEncode(c.encode(value)),
        'created_at': now,
        'updated_at': now,
        'deleted': 0,
        'device_id': deviceId,
      });
      await _log(tx, c.collection, id, 'add', now);
    });
    return id;
  }

  Future<void> update<T>(Codec<T> c, String id, T value) async {
    final now = _now().toIso8601String();
    await db.transaction((tx) async {
      final n = await tx.update(
          'records',
          {'data': jsonEncode(c.encode(value)), 'updated_at': now},
          where: 'collection = ? AND id = ? AND deleted = 0',
          whereArgs: [c.collection, id]);
      if (n == 0) throw StateError('السجل مش موجود: ${c.collection}/$id');
      await _log(tx, c.collection, id, 'update', now);
    });
  }

  /// مسح (بيتعلّم بس علشان الربط بعدين يعرف إنه اتمسح)
  Future<void> remove(Codec c, String id) async {
    final now = _now().toIso8601String();
    await db.transaction((tx) async {
      await tx.update('records', {'deleted': 1, 'updated_at': now},
          where: 'collection = ? AND id = ?', whereArgs: [c.collection, id]);
      await _log(tx, c.collection, id, 'delete', now);
    });
  }

  Future<Stored<T>?> get<T>(Codec<T> c, String id) async {
    final r = await db.query('records',
        where: 'collection = ? AND id = ? AND deleted = 0',
        whereArgs: [c.collection, id]);
    return r.isEmpty ? null : _row(c, r.first);
  }

  Future<List<Stored<T>>> list<T>(Codec<T> c) async {
    final r = await db.query('records',
        where: 'collection = ? AND deleted = 0',
        whereArgs: [c.collection],
        orderBy: 'rowid'); // بترتيب الحفظ
    return [for (final x in r) _row(c, x)];
  }

  Future<List<T>> values<T>(Codec<T> c) async =>
      [for (final s in await list(c)) s.value];

  Stored<T> _row<T>(Codec<T> c, Map<String, Object?> r) => c.stored(
        r['id'] as String,
        (jsonDecode(r['data'] as String) as Map).cast<String, dynamic>(),
        DateTime.parse(r['created_at'] as String),
        DateTime.parse(r['updated_at'] as String),
      );

  Future<void> _log(Transaction tx, String col, String id, String op, String at) =>
      tx.insert('changes', {'collection': col, 'id': id, 'op': op, 'at': at});

  /// التغييرات اللي لسه ما اتبعتتش (للربط بعدين)
  Future<List<Map<String, Object?>>> pendingChanges() =>
      db.query('changes', where: 'synced = 0', orderBy: 'seq');

  // ───────── الإعدادات (آخر فرع، الحدود، الميزانية...) ─────────
  Future<void> setSetting(String key, Object? value) => db.insert(
      'settings', {'key': key, 'value': jsonEncode(value)},
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<T?> setting<T>(String key) async {
    final r = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : jsonDecode(r.first['value'] as String) as T?;
  }

  // ───────── النسخة الاحتياطية (ملف واحد) ─────────
  /// كل البيانات في نص واحد. التطبيق بعدين يحفظه في ملف تبعته لنفسك أو لجوجل درايف.
  Future<String> exportBackup() async {
    final records = await db.query('records', orderBy: 'rowid');
    final settings = await db.query('settings');
    return jsonEncode({
      'format': backupFormat,
      'schema': schemaVersion,
      'exportedAt': _now().toIso8601String(),
      'deviceId': deviceId,
      'settings': {
        for (final s in settings)
          if (s['key'] != 'device_id')
            s['key'] as String: jsonDecode(s['value'] as String)
      },
      'records': [
        for (final r in records)
          {...r, 'data': jsonDecode(r['data'] as String), 'deleted': r['deleted'] == 1}
      ],
    });
  }

  /// يرجّع نسخة احتياطية مكان كل البيانات الحالية. لو الملف بايظ ما بيغيرش أي حاجة.
  Future<void> restoreBackup(String text) async {
    final Map<String, dynamic> j;
    try {
      j = (jsonDecode(text) as Map).cast<String, dynamic>();
    } catch (_) {
      throw const FormatException('الملف ده مش نسخة احتياطية من التطبيق');
    }
    if (j['format'] != backupFormat) {
      throw const FormatException('الملف ده مش نسخة احتياطية من التطبيق');
    }
    if ((j['schema'] as num? ?? 0) > schemaVersion) {
      throw const FormatException('النسخة دي من إصدار أحدث من التطبيق — حدّث التطبيق الأول');
    }
    final known = {for (final c in allCodecs) c.collection: c};
    final recs = (j['records'] as List).cast<Map>();
    // نتأكد إن كل سجل يتقري قبل ما نمسح أي حاجة
    for (final r in recs) {
      final c = known[r['collection']];
      if (c == null) throw FormatException('نوع بيانات مش معروف: ${r['collection']}');
      c.decode((r['data'] as Map).cast<String, dynamic>());
    }
    final now = _now().toIso8601String();
    await db.transaction((tx) async {
      await tx.delete('records');
      await tx.delete('settings', where: 'key != ?', whereArgs: ['device_id']);
      for (final r in recs) {
        await tx.insert('records', {
          'collection': r['collection'],
          'id': r['id'],
          'data': jsonEncode(r['data']),
          'created_at': r['created_at'],
          'updated_at': r['updated_at'],
          'deleted': (r['deleted'] == true) ? 1 : 0,
          'device_id': r['device_id'],
        });
      }
      final s = (j['settings'] as Map? ?? {}).cast<String, dynamic>();
      for (final e in s.entries) {
        await tx.insert('settings', {'key': e.key, 'value': jsonEncode(e.value)},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await _log(tx, '*', '*', 'restore', now);
    });
  }
}
