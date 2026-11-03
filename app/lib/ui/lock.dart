// قفل التطبيق: رقم سري (4 أرقام) + بصمة اختياري.
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../app/state.dart';
import 'theme.dart';

String hashPin(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin')).toString();

bool checkPin(AppState s, String pin) {
  final h = s.setting<String>(K.pinHash), salt = s.setting<String>(K.pinSalt);
  return h != null && salt != null && hashPin(pin, salt) == h;
}

Future<void> savePin(AppState s, String pin) async {
  final r = Random.secure();
  final salt = base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
  await s.set(K.pinSalt, salt);
  await s.set(K.pinHash, hashPin(pin, salt));
}

/// لوحة أرقام كبيرة
class PinPad extends StatelessWidget {
  final String entered;
  final int length;
  final ValueChanged<String> onChanged;
  final Widget? extra;
  const PinPad({super.key, required this.entered, required this.onChanged, this.length = 4, this.extra});
  @override
  Widget build(BuildContext context) {
    Widget key(String k) => Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: 78,
            height: 78,
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(shape: const CircleBorder(), padding: EdgeInsets.zero),
              onPressed: () {
                HapticFeedback.selectionClick();
                if (k == '⌫') {
                  if (entered.isNotEmpty) onChanged(entered.substring(0, entered.length - 1));
                } else if (entered.length < length) {
                  onChanged(entered + k);
                }
              },
              child: Text(k, style: const TextStyle(fontSize: 28)),
            ),
          ),
        );
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < length; i++)
            Container(
              margin: const EdgeInsets.all(8),
              width: 18,
              height: 18,
              decoration: BoxDecoration(shape: BoxShape.circle, color: i < entered.length ? moneyColor : Colors.grey.withValues(alpha: 0.3)),
            ),
        ]),
        const SizedBox(height: 16),
        for (final r in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']]) Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (final k in r) key(k)]),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(width: 94, height: 94, child: extra),
          key('0'),
          key('⌫'),
        ]),
      ]),
    );
  }
}

class PinSetupScreen extends StatefulWidget {
  final bool changing;
  final VoidCallback? onDone;
  const PinSetupScreen({super.key, this.changing = false, this.onDone});
  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  String first = '', cur = '';
  String? msg;
  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      appBar: widget.changing ? AppBar(title: const Text('غيّر الرقم السري')) : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(children: [
              const Icon(Icons.lock_outline, size: 56, color: moneyColor),
              const SizedBox(height: 12),
              Text(first.isEmpty ? 'اختار رقم سري من 4 أرقام' : 'اكتبه تاني للتأكيد', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              if (msg != null) Padding(padding: const EdgeInsets.all(8), child: Text(msg!, style: const TextStyle(color: dangerColor, fontSize: 16))),
              const SizedBox(height: 16),
              PinPad(
                entered: cur,
                onChanged: (v) async {
                  setState(() => cur = v);
                  if (v.length < 4) return;
                  if (first.isEmpty) {
                    setState(() {
                      first = v;
                      cur = '';
                      msg = null;
                    });
                  } else if (v == first) {
                    await savePin(s, v);
                    if (!context.mounted) return;
                    if (widget.onDone != null) {
                      widget.onDone!();
                    } else {
                      Navigator.pop(context);
                    }
                  } else {
                    setState(() {
                      first = '';
                      cur = '';
                      msg = 'الرقمين مش زي بعض — ابدأ من الأول';
                    });
                  }
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.onUnlocked});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String cur = '';
  String? msg;
  final auth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bio());
  }

  Future<void> _bio() async {
    final s = AppScope.read(context);
    if (s.setting<bool>(K.biometric) != true) return;
    try {
      if (!await auth.canCheckBiometrics && !await auth.isDeviceSupported()) return;
      final ok = await auth.authenticate(localizedReason: 'افتح حساباتي', biometricOnly: true);
      if (ok && mounted) widget.onUnlocked();
    } catch (_) {
      // لو البصمة مش شغالة، الرقم السري موجود
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final bio = s.setting<bool>(K.biometric) == true;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(children: [
              const Icon(Icons.lock, size: 56, color: moneyColor),
              const SizedBox(height: 12),
              const Text('حساباتي', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const Text('اكتب الرقم السري', style: TextStyle(fontSize: 18)),
              if (msg != null) Padding(padding: const EdgeInsets.all(8), child: Text(msg!, style: const TextStyle(color: dangerColor, fontSize: 16))),
              const SizedBox(height: 16),
              PinPad(
                entered: cur,
                extra: bio ? IconButton(iconSize: 44, onPressed: _bio, icon: const Icon(Icons.fingerprint, color: moneyColor), tooltip: 'البصمة') : null,
                onChanged: (v) {
                  setState(() => cur = v);
                  if (v.length == 4) {
                    if (checkPin(s, v)) {
                      widget.onUnlocked();
                    } else {
                      setState(() {
                        cur = '';
                        msg = 'الرقم غلط';
                      });
                      HapticFeedback.heavyImpact();
                    }
                  }
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// بيقفل التطبيق أول ما يفتح، ولما يرجع من الخلفية بعد 30 ثانية
class LockGate extends StatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});
  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool locked = true;
  DateTime? pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState st) {
    if (st == AppLifecycleState.paused || st == AppLifecycleState.hidden) {
      pausedAt ??= DateTime.now();
    } else if (st == AppLifecycleState.resumed) {
      if (pausedAt != null && DateTime.now().difference(pausedAt!).inSeconds >= 30) setState(() => locked = true);
      pausedAt = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (s.setting<String>(K.pinHash) == null) {
      return PinSetupScreen(onDone: () => setState(() => locked = false));
    }
    if (locked) return LockScreen(onUnlocked: () => setState(() => locked = false));
    return widget.child;
  }
}
