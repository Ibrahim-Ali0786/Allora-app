// ignore_for_file: unused_element, unnecessary_non_null_assertion, deprecated_member_use
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

import 'whatsapp_disconnect_service.dart';
import '../bridge/bridge_room_classifier.dart';

class _T {
  static const Color surface = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFEBEBEE);
  static const Color onSurface = Color(0xFF1A1B20);
  static const Color onSurfaceVariant = Color(0xFF6B6D78);
  static const Color onSurfaceMuted = Color(0xFFADAFB8);
  static const Color destructive = Color(0xFFD8423D);
  static const Color positive = Color(0xFF1F9D55);
}

const Color _kWaGreen = Color(0xFF25D366);

// ─── PUBLIC ENTRY POINT ───────────────────────────────────────────────────────

Future<void> showWhatsAppAccountDetailSheet({
  required BuildContext context,
  required Client client,
  required Color brandColor,
  String? asset,
  String accountLabel = 'Connected',
  String lastSynced = 'Active',
  required VoidCallback onDisconnected,
  required ValueChanged<bool> onGlobalLoading,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: _T.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    isDismissible: true,
    builder: (ctx) => _WhatsAppDetailSheet(
      client: client,
      brandColor: brandColor,
      asset: asset,
      accountLabel: accountLabel,
      lastSynced: lastSynced,
      onDisconnected: onDisconnected,
      onGlobalLoading: onGlobalLoading,
    ),
  );
}

// ─── SHEET WIDGET ─────────────────────────────────────────────────────────────

class _WhatsAppDetailSheet extends StatefulWidget {
  final Client client;
  final Color brandColor;
  final String? asset;
  final String accountLabel;
  final String lastSynced;
  final VoidCallback onDisconnected;
  final ValueChanged<bool> onGlobalLoading;

  const _WhatsAppDetailSheet({
    required this.client,
    required this.brandColor,
    required this.asset,
    required this.accountLabel,
    required this.lastSynced,
    required this.onDisconnected,
    required this.onGlobalLoading,
  });

  @override
  State<_WhatsAppDetailSheet> createState() => _WhatsAppDetailSheetState();
}

enum _SheetState { idle, confirming, disconnecting, done, error }

class _WhatsAppDetailSheetState extends State<_WhatsAppDetailSheet>
    with TickerProviderStateMixin {
  _SheetState _phase = _SheetState.idle;
  String? _errorMsg;

  late final AnimationController _pulseCtrl;
  late final AnimationController _doneCtrl;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _doneScale;
  late final Animation<double> _doneFade;

  @override
  void initState() {
    super.initState();
    _pulseCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();
    _doneCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 550));
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut);
    _doneScale = CurvedAnimation(parent: _doneCtrl, curve: Curves.elasticOut);
    _doneFade = CurvedAnimation(parent: _doneCtrl, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _doneCtrl.dispose();
    super.dispose();
  }

  // ── DISCONNECT HANDLER ────────────────────────────────────────────────────

  Future<void> _doDisconnect() async {
    HapticFeedback.heavyImpact();
    setState(() => _phase = _SheetState.disconnecting);

    try {
      // beginDisconnect: sends logout <loginId>, collects rooms, starts wiper
      await WhatsAppDisconnectService.beginDisconnect(widget.client);

      // Clear classifier cache to force fresh room identification
      BridgeRoomClassifier.clearCache();

      if (!mounted) return;

      // Immediately tell the parent: flip status to Available + hide WA in list
      widget.onDisconnected();

      setState(() => _phase = _SheetState.done);
      _doneCtrl.forward();
      HapticFeedback.heavyImpact();

      await Future.delayed(const Duration(milliseconds: 1800));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _SheetState.error;
        _errorMsg = e.toString();
      });
    }
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _SheetState.idle:
        return _idle();
      case _SheetState.confirming:
        return _confirm();
      case _SheetState.disconnecting:
        return _disconnecting();
      case _SheetState.done:
        return _done();
      case _SheetState.error:
        return _error();
    }
  }

  // ── IDLE ──────────────────────────────────────────────────────────────────
  Widget _idle() {
    return Padding(
      key: const ValueKey('idle'),
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            const SizedBox(height: 18),
            Container(height: 1, color: _T.divider),
            const SizedBox(height: 14),
            Row(children: [
              const Icon(Icons.check_circle, size: 16, color: _T.positive),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(widget.accountLabel,
                      style: const TextStyle(
                          fontSize: 13.5, color: _T.onSurfaceVariant))),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.sync_rounded,
                  size: 16, color: _T.onSurfaceMuted),
              const SizedBox(width: 8),
              Text(widget.lastSynced,
                  style: const TextStyle(
                      fontSize: 13.5, color: _T.onSurfaceVariant)),
            ]),
            const SizedBox(height: 22),
            _disconnectBtn(
                () => setState(() => _phase = _SheetState.confirming)),
          ]),
    );
  }

  // ── CONFIRM ───────────────────────────────────────────────────────────────
  Widget _confirm() {
    return Padding(
      key: const ValueKey('confirm'),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Disconnect WhatsApp?',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: _T.onSurface)),
            const SizedBox(height: 10),
            const Text(
              'You will be logged out of WhatsApp on this device.\n\n'
              'All bridged chats and groups will be removed from your inbox '
              'in the background — this can take a minute depending on how many rooms exist.',
              style: TextStyle(
                  fontSize: 14, color: _T.onSurfaceVariant, height: 1.55),
            ),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                  child: OutlinedButton(
                onPressed: () => setState(() => _phase = _SheetState.idle),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  side: const BorderSide(color: _T.divider),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Cancel',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: _T.onSurface)),
              )),
              const SizedBox(width: 10),
              Expanded(
                  child: FilledButton(
                onPressed: _doDisconnect,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  backgroundColor: _T.destructive,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Disconnect',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              )),
            ]),
          ]),
    );
  }

  // ── DISCONNECTING ─────────────────────────────────────────────────────────
  Widget _disconnecting() {
    return Padding(
      key: const ValueKey('disconnecting'),
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 44),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 110,
          height: 110,
          child: Stack(alignment: Alignment.center, children: [
            ...List.generate(
                3,
                (i) => AnimatedBuilder(
                      animation: _pulseAnim,
                      builder: (_, __) {
                        final v = (_pulseCtrl.value + i / 3) % 1.0;
                        return Opacity(
                          opacity: (1.0 - v).clamp(0.0, 1.0),
                          child: Transform.scale(
                            scale: 0.45 + v * 1.6,
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: _T.destructive.withOpacity(0.55),
                                    width: 2),
                              ),
                            ),
                          ),
                        );
                      },
                    )),
            _waIcon(52),
          ]),
        ),
        const SizedBox(height: 22),
        const Text('Disconnecting…',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: _T.onSurface)),
        const SizedBox(height: 6),
        const Text('Logging out and scheduling room cleanup.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: _T.onSurfaceVariant)),
      ]),
    );
  }

  // ── DONE ──────────────────────────────────────────────────────────────────
  Widget _done() {
    return Padding(
      key: const ValueKey('done'),
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 44),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ScaleTransition(
          scale: _doneScale,
          child: FadeTransition(
            opacity: _doneFade,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _T.destructive.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(
                    color: _T.destructive.withOpacity(0.35), width: 2),
              ),
              child: const Icon(Icons.link_off_rounded,
                  color: _T.destructive, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 20),
        FadeTransition(
          opacity: _doneFade,
          child: Column(children: const [
            Text('Disconnected',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: _T.onSurface)),
            SizedBox(height: 6),
            Text('WhatsApp removed. Chats clearing in the background.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: _T.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
  }

  // ── ERROR ─────────────────────────────────────────────────────────────────
  Widget _error() {
    return Padding(
      key: const ValueKey('error'),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Row(children: [
            Icon(Icons.error_outline_rounded, color: Colors.red.shade400),
            const SizedBox(width: 12),
            Expanded(
                child: Text(_errorMsg ?? 'Unknown error',
                    style:
                        TextStyle(color: Colors.red.shade800, fontSize: 14))),
          ]),
        ),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
              child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
              side: const BorderSide(color: _T.divider),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Cancel',
                style: TextStyle(
                    color: _T.onSurface, fontWeight: FontWeight.w600)),
          )),
          const SizedBox(width: 10),
          Expanded(
              child: FilledButton(
            onPressed: _doDisconnect,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
              backgroundColor: _T.destructive,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Retry',
                style: TextStyle(fontWeight: FontWeight.w600)),
          )),
        ]),
      ]),
    );
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  Widget _header() {
    return Row(children: [
      _waIcon(44),
      const SizedBox(width: 14),
      const Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('WhatsApp',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _T.onSurface)),
        SizedBox(height: 2),
        Text('Connected', style: TextStyle(fontSize: 13.5, color: _T.positive)),
      ])),
    ]);
  }

  Widget _waIcon(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: widget.brandColor,
        borderRadius: BorderRadius.circular(size * 0.27),
      ),
      child: Center(
        child: widget.asset != null
            ? Padding(
                padding: EdgeInsets.all(size * 0.18),
                child: Image.asset(widget.asset!))
            : Icon(Icons.chat_bubble_rounded,
                color: Colors.white, size: size * 0.45),
      ),
    );
  }

  Widget _disconnectBtn(VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 13),
          side: const BorderSide(color: _T.destructive),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: const Text('Disconnect',
            style:
                TextStyle(fontWeight: FontWeight.w600, color: _T.destructive)),
      ),
    );
  }
}
