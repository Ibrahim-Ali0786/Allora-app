import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/theme/app_theme.dart';
import '../../data/settings/app_settings.dart';

/// Android FLAG_SECURE bridge: blocks screenshots and hides the app's
/// content in the recent-apps switcher. No-ops silently on platforms
/// without the channel.
class SecureScreenService {
  SecureScreenService._();

  static const _channel = MethodChannel('app.allorachat.messenger/secure');

  static Future<void> setSecure(bool secure) async {
    try {
      await _channel.invokeMethod('setSecure', {'secure': secure});
    } catch (_) {
      // Channel missing (iOS/desktop/web) — nothing to do.
    }
  }
}

/// Wraps the authenticated app. Shows the PIN screen at startup when app
/// lock is enabled, re-locks after the configured background timeout, and
/// keeps FLAG_SECURE in sync with settings.
class LockGate extends ConsumerStatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate>
    with WidgetsBindingObserver {
  DateTime? _backgroundedAt;
  bool _secureApplied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // appLockedProvider self-initializes to locked when a PIN is set, so
    // there is no unlocked first frame; here we only sync FLAG_SECURE.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applySecure(ref.read(settingsProvider).effectiveBlockScreenshots);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _applySecure(bool secure) {
    if (secure == _secureApplied) return;
    _secureApplied = secure;
    SecureScreenService.setSecure(secure);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final settings = ref.read(settingsProvider);
    if (!settings.appLockEnabled) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _backgroundedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final away = _backgroundedAt;
      _backgroundedAt = null;
      if (away == null) return;
      final elapsed = DateTime.now().difference(away);
      if (elapsed.inSeconds >= settings.autoLockMinutes * 60) {
        ref.read(appLockedProvider.notifier).state = true;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(appLockedProvider);
    final settings = ref.watch(settingsProvider);
    _applySecure(settings.effectiveBlockScreenshots);

    return Stack(
      children: [
        widget.child,
        if (locked && settings.appLockEnabled && settings.pinHash != null)
          PinLockScreen(
            title: 'Allora is locked',
            biometricAllowed: settings.biometricEnabled,
            onVerify: (pin) =>
                ref.read(settingsProvider.notifier).verifyPin(pin),
            onUnlocked: () =>
                ref.read(appLockedProvider.notifier).state = false,
          ),
      ],
    );
  }
}

/// Full-screen PIN pad, with optional biometric shortcut.
class PinLockScreen extends StatefulWidget {
  final String title;
  final bool biometricAllowed;
  final bool Function(String pin) onVerify;
  final VoidCallback onUnlocked;

  const PinLockScreen({
    super.key,
    required this.title,
    required this.onVerify,
    required this.onUnlocked,
    this.biometricAllowed = false,
  });

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  String _entry = '';
  bool _wrong = false;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    if (widget.biometricAllowed) _initBiometric();
  }

  Future<void> _initBiometric() async {
    try {
      final auth = LocalAuthentication();
      final supported = await auth.isDeviceSupported();
      final can = await auth.canCheckBiometrics;
      if (!mounted) return;
      setState(() => _biometricAvailable = supported && can);
      if (_biometricAvailable) unawaited(_tryBiometric());
    } catch (_) {}
  }

  Future<void> _tryBiometric() async {
    try {
      final ok = await LocalAuthentication().authenticate(
        localizedReason: 'Unlock Allora',
        options: const AuthenticationOptions(stickyAuth: true),
      );
      if (ok && mounted) widget.onUnlocked();
    } catch (_) {}
  }

  void _tap(String digit) {
    if (_entry.length >= 6) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entry += digit;
      _wrong = false;
    });
    if (_entry.length >= 4) {
      if (widget.onVerify(_entry)) {
        HapticFeedback.lightImpact();
        widget.onUnlocked();
      } else if (_entry.length == 6) {
        HapticFeedback.heavyImpact();
        setState(() {
          _wrong = true;
          _entry = '';
        });
      }
    }
  }

  void _backspace() {
    if (_entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    return Material(
      color: c.canvas,
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [c.accent, c.bubbleMineDeep]),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.lock_rounded, color: Colors.white, size: 30),
            ),
            const SizedBox(height: 20),
            Text(widget.title,
                style: TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w800, color: c.text)),
            const SizedBox(height: 6),
            Text(
              _wrong ? 'Wrong PIN — try again' : 'Enter your PIN',
              style: TextStyle(
                  fontSize: 13.5,
                  color: _wrong ? c.danger : c.textSecondary),
            ),
            const SizedBox(height: 22),
            _dots(),
            const Spacer(),
            _pad(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _dots() {
    final c = context.allora;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) {
        final filled = i < _entry.length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: filled ? 14 : 11,
          height: filled ? 14 : 11,
          margin: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: filled ? c.accent : c.surfaceAlt,
            shape: BoxShape.circle,
            border: Border.all(color: filled ? c.accent : c.outline),
          ),
        );
      }),
    );
  }

  Widget _pad() {
    final keys = [
      '1', '2', '3',
      '4', '5', '6',
      '7', '8', '9',
      _biometricAvailable ? 'bio' : '', '0', 'back',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 44),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 14,
          crossAxisSpacing: 26,
          childAspectRatio: 1.35,
        ),
        itemCount: keys.length,
        itemBuilder: (context, i) => _key(keys[i]),
      ),
    );
  }

  Widget _key(String value) {
    final c = context.allora;
    if (value.isEmpty) return const SizedBox.shrink();
    final isBio = value == 'bio';
    final isBack = value == 'back';
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () {
        if (isBio) {
          _tryBiometric();
        } else if (isBack) {
          _backspace();
        } else {
          _tap(value);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: isBio || isBack ? Colors.transparent : c.surface,
          shape: BoxShape.circle,
          border: isBio || isBack ? null : Border.all(color: c.outline),
        ),
        alignment: Alignment.center,
        child: isBio
            ? Icon(Icons.fingerprint_rounded, size: 26, color: c.accent)
            : isBack
                ? Icon(Icons.backspace_outlined,
                    size: 22, color: c.textSecondary)
                : Text(value,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: c.text)),
      ),
    );
  }
}

/// Two-step PIN creation. Pops with `true` when a PIN was set.
class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key});

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  String _first = '';
  String _entry = '';
  bool _confirming = false;
  bool _mismatch = false;

  void _tap(String d) {
    if (_entry.length >= 6) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entry += d;
      _mismatch = false;
    });
    if (_entry.length == 6) _advance();
  }

  void _advance() {
    if (!_confirming) {
      setState(() {
        _first = _entry;
        _entry = '';
        _confirming = true;
      });
    } else if (_entry == _first) {
      ref.read(settingsProvider.notifier).setPin(_entry);
      HapticFeedback.lightImpact();
      Navigator.pop(context, true);
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _mismatch = true;
        _entry = '';
        _first = '';
        _confirming = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(title: const Text('Set PIN')),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Icon(Icons.pin_rounded, size: 44, color: c.accent),
            const SizedBox(height: 18),
            Text(
              _confirming ? 'Confirm your PIN' : 'Choose a 6-digit PIN',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: c.text),
            ),
            const SizedBox(height: 6),
            Text(
              _mismatch
                  ? 'PINs didn\u2019t match — start over'
                  : 'You\u2019ll use this to unlock Allora',
              style: TextStyle(
                  fontSize: 13,
                  color: _mismatch ? c.danger : c.textSecondary),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (i) {
                final filled = i < _entry.length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: filled ? 14 : 11,
                  height: filled ? 14 : 11,
                  margin: const EdgeInsets.symmetric(horizontal: 7),
                  decoration: BoxDecoration(
                    color: filled ? c.accent : c.surfaceAlt,
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: filled ? c.accent : c.outline),
                  ),
                );
              }),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 44),
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                mainAxisSpacing: 14,
                crossAxisSpacing: 26,
                childAspectRatio: 1.35,
                children: [
                  for (final k in [
                    '1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', 'back',
                  ])
                    k.isEmpty
                        ? const SizedBox.shrink()
                        : InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              if (k == 'back') {
                                if (_entry.isNotEmpty) {
                                  setState(() => _entry = _entry.substring(
                                      0, _entry.length - 1));
                                }
                              } else {
                                _tap(k);
                              }
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: k == 'back'
                                    ? Colors.transparent
                                    : c.surface,
                                shape: BoxShape.circle,
                                border: k == 'back'
                                    ? null
                                    : Border.all(color: c.outline),
                              ),
                              alignment: Alignment.center,
                              child: k == 'back'
                                  ? Icon(Icons.backspace_outlined,
                                      size: 22, color: c.textSecondary)
                                  : Text(k,
                                      style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w600,
                                          color: c.text)),
                            ),
                          ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
