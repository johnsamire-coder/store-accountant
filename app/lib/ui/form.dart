// نموذج إدخال عام: كل شاشات الإدخال مبنية منه.
// التاريخ النهارده افتراضي، الفرع آخر فرع، الاختيارات أزرار بدل الكتابة.
import 'package:flutter/material.dart';

import '../app/state.dart';
import '../data/codecs.dart';
import '../data/store.dart';
import '../engine/format.dart';
import 'common.dart';

enum FType { text, number, date, dateTime, month, choice, yesNo, lines }

class FieldSpec {
  final String key, label;
  final FType type;
  final List<String> Function(AppState)? options; // للاختيارات والاقتراحات
  final bool required;
  final String? hint;
  final List<FieldSpec> sub; // لخانات السطور
  final Object? Function(AppState)? initial;
  final bool Function(Json)? visible; // تظهر بس لو...
  final bool nullable; // الرقم ممكن يفضل فاضي (null)
  const FieldSpec(this.key, this.label, this.type,
      {this.options, this.required = false, this.hint, this.sub = const [], this.initial, this.visible, this.nullable = false});
}

List<String> Function(AppState) fixedOptions(List<String> l) => (_) => l;
const branchOptions = ['القاهرة', 'بورسعيد'];

FieldSpec branchField([String key = 'branch']) =>
    FieldSpec(key, 'الفرع', FType.choice, options: fixedOptions(branchOptions), required: true, initial: (s) => s.lastBranch);
FieldSpec dateField([String key = 'date', String label = 'التاريخ']) =>
    FieldSpec(key, label, FType.date, required: true, initial: (s) => s.today.toIso8601String());

/// قراية/كتابة خانة جوه خانة (زي costs.freight)
Object? getPath(Json j, String key) {
  if (!key.contains('.')) return j[key];
  Object? cur = j;
  for (final k in key.split('.')) {
    if (cur is! Map) return null;
    cur = cur[k];
  }
  return cur;
}

void setPath(Json j, String key, Object? v) {
  if (!key.contains('.')) {
    j[key] = v;
    return;
  }
  final parts = key.split('.');
  Map cur = j;
  for (final k in parts.take(parts.length - 1)) {
    cur[k] = Map<String, dynamic>.from((cur[k] as Map?) ?? {});
    cur = cur[k] as Map;
  }
  cur[parts.last] = v;
}

class EntitySpec<T> {
  final Codec<T> codec;
  final String title; // اسم الشاشة
  final String single; // اسم السجل الواحد
  final IconData icon;
  final Color color;
  final List<FieldSpec> fields;
  final String Function(T) tileTitle;
  final String Function(T, AppState) tileSub;
  final String Function(T, AppState)? status;
  final DateTime? Function(T)? sortDate;
  final List<(String, String)> Function(T, AppState)? details;
  final Widget Function(BuildContext, Stored<T>)? extra; // حاجات زيادة في شاشة التفاصيل
  final String? groupBy; // تقسيم القايمة (مثلاً حسب الفرع)
  const EntitySpec({
    required this.codec,
    required this.title,
    required this.single,
    required this.icon,
    required this.color,
    required this.fields,
    required this.tileTitle,
    required this.tileSub,
    this.status,
    this.sortDate,
    this.details,
    this.extra,
    this.groupBy,
  });

  // ── استدعاء الدوال بالنوع الحقيقي (من غير ما الكود اللي برا يعرف النوع) ──
  bool get hasDetails => details != null;
  bool get hasDate => sortDate != null;
  String titleOf(Object? v) => tileTitle(v as T);
  String subOf(Object? v, AppState s) => tileSub(v as T, s);
  String statusOf(Object? v, AppState s) => status == null ? '' : status!(v as T, s);
  DateTime? dateOf(Object? v) => sortDate?.call(v as T);
  List<(String, String)> detailsOf(Object? v, AppState s) => details?.call(v as T, s) ?? const [];
  Json encodeOf(Object? v) => codec.encode(v as T);
  List<Stored> storedIn(AppState s) => s.all<T>(codec);
  Stored? byIdIn(AppState s, String id) => s.byId<T>(codec, id);
  Widget? extraOf(BuildContext c, Stored st) => extra?.call(c, st as Stored<T>);
  Widget formPage({String? id, Json? initial, String? saveLabel}) =>
      EntityForm<T>(spec: this, id: id, initial: initial, saveLabel: saveLabel);

  Json blank(AppState s) {
    final j = <String, dynamic>{};
    for (final f in fields) {
      if (f.initial != null) setPath(j, f.key, f.initial!(s));
      if (f.type == FType.yesNo && !j.containsKey(f.key)) j[f.key] = false;
      if (f.type == FType.lines && !j.containsKey(f.key)) j[f.key] = <Map<String, dynamic>>[];
    }
    return j;
  }
}

class EntityForm<T> extends StatefulWidget {
  final EntitySpec<T> spec;
  final String? id;
  final Json? initial; // قيم جاية من الواتساب مثلاً
  final String? saveLabel;
  final Future<void> Function(T value)? onSaved;
  const EntityForm({super.key, required this.spec, this.id, this.initial, this.saveLabel, this.onSaved});
  @override
  State<EntityForm<T>> createState() => _EntityFormState<T>();
}

class _EntityFormState<T> extends State<EntityForm<T>> {
  late Json data;
  bool _init = false;
  String? error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final s = AppScope.read(context);
    final sp = widget.spec;
    if (widget.initial != null) {
      data = {...sp.blank(s), ..._deepCopy(widget.initial!)};
    } else if (widget.id != null) {
      data = _deepCopy(sp.codec.encode(s.byId(sp.codec, widget.id!)!.value));
    } else {
      data = sp.blank(s);
    }
  }

  Json _deepCopy(Json j) => {
        for (final e in j.entries)
          e.key: e.value is List
              ? [for (final x in e.value as List) x is Map ? Map<String, dynamic>.from(x) : x]
              : (e.value is Map ? Map<String, dynamic>.from(e.value as Map) : e.value)
      };

  T? _tryDecode() {
    try {
      return widget.spec.codec.decode(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    final s = AppScope.read(context);
    for (final f in widget.spec.fields) {
      if (f.visible != null && !f.visible!(data)) continue;
      final v = getPath(data, f.key);
      if (f.required && (v == null || (v is String && v.trim().isEmpty))) {
        setState(() => error = 'لازم تملا: ${f.label}');
        return;
      }
    }
    final T value;
    try {
      value = widget.spec.codec.decode(data);
    } catch (e) {
      setState(() => error = 'فيه خانة مش مظبوطة');
      return;
    }
    if (data['branch'] is String) await s.rememberBranch(data['branch'] as String);
    await s.save(widget.spec.codec, widget.id, value);
    if (widget.onSaved != null) await widget.onSaved!(value);
    if (mounted) {
      toast(context, 'اتحفظ ✔');
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final sp = widget.spec;
    final preview = _tryDecode();
    return Scaffold(
      appBar: AppBar(title: Text(widget.id == null ? '${sp.single} جديد' : 'تعديل ${sp.single}')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            for (final f in sp.fields)
              if (f.visible == null || f.visible!(data))
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: FieldEditor(
                    spec: f,
                    value: getPath(data, f.key),
                    state: s,
                    onChanged: (v) => setState(() {
                      setPath(data, f.key, v);
                      error = null;
                    }),
                  ),
                ),
            if (preview != null && sp.details != null) ...[
              const SectionTitle('بيتحسب لوحده'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Column(children: [
                    if (sp.status != null)
                      Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: StatusChip(sp.status!(preview, s))),
                    for (final r in sp.details!(preview, s)) NumRow(r.$1, r.$2),
                  ]),
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (error != null)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(error!, style: const TextStyle(color: Colors.red, fontSize: 16))),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: sp.color, foregroundColor: Colors.white),
                onPressed: _save,
                icon: const Icon(Icons.check),
                label: Text(widget.saveLabel ?? 'حفظ'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// خانة واحدة
class FieldEditor extends StatelessWidget {
  final FieldSpec spec;
  final Object? value;
  final AppState state;
  final ValueChanged<Object?> onChanged;
  const FieldEditor({super.key, required this.spec, required this.value, required this.state, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final label = Text(spec.label + (spec.required ? ' *' : ''), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600));
    switch (spec.type) {
      case FType.text:
        final sugg = spec.options?.call(state) ?? const <String>[];
        return _TextField(key: ValueKey('t-${spec.key}'), label: spec.label, value: value as String? ?? '', hint: spec.hint, suggestions: sugg, onChanged: onChanged);
      case FType.number:
        return _NumField(key: ValueKey('n-${spec.key}'), label: spec.label, value: value as num?, hint: spec.hint, nullable: spec.nullable, onChanged: onChanged);
      case FType.date:
      case FType.dateTime:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          label,
          const SizedBox(height: 6),
          _DatePicker(value: value == null ? null : DateTime.parse(value as String), withTime: spec.type == FType.dateTime, today: state.today, nullable: !spec.required, onChanged: (d) => onChanged(d?.toIso8601String())),
        ]);
      case FType.month:
        final cur = value == null ? DateTime(state.today.year, state.today.month) : DateTime.parse(value as String);
        final months = [for (var i = -12; i <= 3; i++) DateTime(state.today.year, state.today.month + i, 1)];
        return DropdownButtonFormField<String>(
          initialValue: DateTime(cur.year, cur.month, 1).toIso8601String(),
          decoration: InputDecoration(labelText: spec.label),
          items: [for (final m in months) DropdownMenuItem(value: m.toIso8601String(), child: Text(monthName(m)))],
          onChanged: onChanged,
        );
      case FType.choice:
        final opts = spec.options!(state);
        final v = value as String?;
        if (opts.length <= 6) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            label,
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final o in opts)
                ChoiceChip(
                  label: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(o, style: const TextStyle(fontSize: 16))),
                  selected: v == o,
                  onSelected: (_) => onChanged(o),
                ),
            ]),
          ]);
        }
        return DropdownButtonFormField<String>(
          initialValue: opts.contains(v) ? v : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: spec.label + (spec.required ? ' *' : '')),
          items: [for (final o in opts) DropdownMenuItem(value: o, child: Text(o))],
          onChanged: onChanged,
        );
      case FType.yesNo:
        final b = value == true;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          label,
          const SizedBox(height: 6),
          Row(children: [
            ChoiceChip(label: const Padding(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: Text('نعم', style: TextStyle(fontSize: 16))), selected: b, onSelected: (_) => onChanged(true)),
            const SizedBox(width: 10),
            ChoiceChip(label: const Padding(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: Text('لا', style: TextStyle(fontSize: 16))), selected: !b, onSelected: (_) => onChanged(false)),
          ]),
        ]);
      case FType.lines:
        final rows = ((value as List?) ?? const []).cast<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          label,
          const SizedBox(height: 6),
          for (var i = 0; i < rows.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                child: Column(children: [
                  Row(children: [
                    Text('سطر ${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                        tooltip: 'شيل السطر',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => onChanged([...rows]..removeAt(i))),
                  ]),
                  for (final sf in spec.sub)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: FieldEditor(
                        key: ValueKey('l$i-${sf.key}-${rows.length}'),
                        spec: sf,
                        value: rows[i][sf.key],
                        state: state,
                        onChanged: (v) {
                          final n = [...rows];
                          n[i] = {...n[i], sf.key: v};
                          onChanged(n);
                        },
                      ),
                    ),
                ]),
              ),
            ),
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('ضيف سطر'),
            onPressed: () => onChanged([
              ...rows,
              {for (final sf in spec.sub) if (sf.initial != null) sf.key: sf.initial!(state)}
            ]),
          ),
        ]);
    }
  }
}

class _TextField extends StatefulWidget {
  final String label, value;
  final String? hint;
  final List<String> suggestions;
  final ValueChanged<Object?> onChanged;
  const _TextField({super.key, required this.label, required this.value, this.hint, required this.suggestions, required this.onChanged});
  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late final c = TextEditingController(text: widget.value);
  @override
  void didUpdateWidget(_TextField old) {
    super.didUpdateWidget(old);
    if (widget.value != c.text) c.text = widget.value;
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = c.text.trim();
    final sugg = widget.suggestions.where((s) => s != q && (q.isEmpty || s.contains(q))).take(6).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: c,
        style: const TextStyle(fontSize: 17),
        decoration: InputDecoration(labelText: widget.label, hintText: widget.hint),
        onChanged: (v) {
          widget.onChanged(v);
          setState(() {});
        },
      ),
      if (sugg.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in sugg)
              ActionChip(
                label: Text(s),
                onPressed: () {
                  c.text = s;
                  widget.onChanged(s);
                  setState(() {});
                },
              ),
          ]),
        ),
    ]);
  }
}

class _NumField extends StatefulWidget {
  final String label;
  final num? value;
  final String? hint;
  final bool nullable;
  final ValueChanged<Object?> onChanged;
  const _NumField({super.key, required this.label, required this.value, this.hint, required this.nullable, required this.onChanged});
  @override
  State<_NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<_NumField> {
  late final c = TextEditingController(text: numText(widget.value));
  @override
  void didUpdateWidget(_NumField old) {
    super.didUpdateWidget(old);
    if (parseNum(c.text) != widget.value?.toDouble()) c.text = numText(widget.value);
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        inputFormatters: [ThousandsFormatter()],
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.right,
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(labelText: widget.label, hintText: widget.hint),
        onChanged: (v) => widget.onChanged(parseNum(v) ?? (widget.nullable ? null : 0)),
      );
}

class _DatePicker extends StatelessWidget {
  final DateTime? value;
  final bool withTime, nullable;
  final DateTime today;
  final ValueChanged<DateTime?> onChanged;
  const _DatePicker({required this.value, required this.withTime, required this.today, required this.nullable, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final v = value;
    final yest = today.subtract(const Duration(days: 1));
    bool same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
    return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      ChoiceChip(
          label: const Text('النهارده', style: TextStyle(fontSize: 16)),
          selected: v != null && same(v, today),
          onSelected: (_) => onChanged(withTime ? DateTime.now() : today)),
      ChoiceChip(
          label: const Text('امبارح', style: TextStyle(fontSize: 16)),
          selected: v != null && same(v, yest),
          onSelected: (_) => onChanged(withTime ? yest.add(Duration(hours: DateTime.now().hour)) : yest)),
      ActionChip(
        avatar: const Icon(Icons.calendar_month, size: 20),
        label: Text(v == null ? 'اختار تاريخ' : (withTime ? '${fmtDate(v)}  ${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}' : dayName(v)),
            style: const TextStyle(fontSize: 16)),
        onPressed: () async {
          final d = await showDatePicker(context: context, initialDate: v ?? today, firstDate: DateTime(2020), lastDate: DateTime(2035));
          if (d == null) return;
          if (withTime && context.mounted) {
            final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(v ?? DateTime.now()));
            onChanged(DateTime(d.year, d.month, d.day, t?.hour ?? 0, t?.minute ?? 0));
          } else {
            onChanged(d);
          }
        },
      ),
      if (nullable && v != null) IconButton(onPressed: () => onChanged(null), icon: const Icon(Icons.clear), tooltip: 'شيل التاريخ'),
    ]);
  }
}
