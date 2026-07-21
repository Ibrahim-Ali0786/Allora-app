// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/account_lifecycle.dart';
import '../../data/services/connection_manager.dart';
import 'network_meta.dart';

/// Account detail + disconnect sheet, shared by every network.
///
/// Disconnect goes through [AccountLifecycleService]: bridge logout command,
/// instant portal-room wipe, sticky cache flag, connection-manager refresh.
/// The result screen tells the user the truth — whether the remote session
/// was signed out, or only the Allora link was removed.
Future<void> showNetworkAccountSheet({
  required BuildContext context,
  required Client client,
  required NetworkMeta meta,
  String? accountLabel,
  String? lastSynced,
  VoidCallback? onDisconnected,
}) {
  return showModalBottomSheet(
    context: context,
    isDismissible: true,
    builder: (ctx) => _NetworkAccountSheet(
      client: client,
      meta: meta,
      accountLabel: accountLabel,
      lastSynced: lastSynced,
      onDisconnected: onDisconnected,
    ),
  );
}

enum _Phase { idle, confirming, working, done, error }

class _NetworkAccountSheet extends StatefulWidget {
  final Client client;
  final NetworkMeta meta;
  final String? accountLabel;
  final String? lastSynced;
  final VoidCallback? onDisconnected;

  const _NetworkAccountSheet({
    required this.client,
    required this.meta,
    this.accountLabel,
    this.lastSynced,
    this.onDisconnected,
  });

  @override
  State<_NetworkAccountSheet> createState() => _NetworkAccountSheetState();
}

class _NetworkAccountSheetState extends State<_NetworkAccountSheet> {
  _Phase _phase = _Phase.idle;
  DisconnectResult? _result;
  String? _error;

  void _disconnect() {
    HapticFeedback.heavyImpact();
    // Non-blocking: account flips to "Disconnecting…" instantly, the sheet
    // closes, and bridge logout + room cleanup run in the background. A
    // toast reports the honest outcome when everything finishes.
    AccountLifecycleService.disconnectInBackground(
        widget.client, widget.meta.id);
    widget.onDisconnected?.call();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 22),
          child: _body(),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.idle:
        return _idle();
      case _Phase.confirming:
        return _confirm();
      case _Phase.working:
        return _working();
      case _Phase.done:
        return _done();
      case _Phase.error:
        return _errorView();
    }
  }

  Widget _header() {
    final c = context.allora;
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: widget.meta.brandColor,
            borderRadius: BorderRadius.circular(15),
          ),
          padding: const EdgeInsets.all(12),
          child: widget.meta.asset != null
              ? Image.asset(widget.meta.asset!, color: Colors.white,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.link, color: Colors.white))
              : Icon(widget.meta.icon ?? Icons.link,
                  color: Colors.white, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.meta.displayName,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: c.text)),
              const SizedBox(height: 2),
              Text(
                widget.accountLabel ?? 'Connected',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: c.textSecondary),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: c.success.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration:
                    BoxDecoration(color: c.success, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text('Active',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: c.success)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _idle() {
    final c = context.allora;
    return Column(
      key: const ValueKey('idle'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.sync_rounded, size: 17, color: c.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Last synced: ${widget.lastSynced ?? 'Active'}',
                  style: TextStyle(fontSize: 13, color: c.textSecondary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () {
            ConnectionManager.instance?.probeNetworks();
            Navigator.pop(context);
          },
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Check connection'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: c.danger),
          onPressed: () => setState(() => _phase = _Phase.confirming),
          icon: const Icon(Icons.link_off_rounded, size: 18),
          label: const Text('Disconnect account'),
        ),
      ],
    );
  }

  Widget _confirm() {
    final c = context.allora;
    return Column(
      key: const ValueKey('confirm'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.link_off_rounded, size: 40, color: c.danger),
        const SizedBox(height: 14),
        Text(
          'Disconnect ${widget.meta.displayName}?',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: c.text),
        ),
        const SizedBox(height: 8),
        Text(
          'Allora will sign out your ${widget.meta.displayName} session and '
          'immediately remove every synced chat, group and file from this '
          'app. Nothing is deleted on ${widget.meta.displayName} itself.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13.5, color: c.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _phase = _Phase.idle),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: c.danger),
                onPressed: _disconnect,
                child: const Text('Disconnect'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _working() {
    final c = context.allora;
    return Column(
      key: const ValueKey('working'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 10),
        SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(strokeWidth: 3, color: c.accent),
        ),
        const SizedBox(height: 18),
        Text('Disconnecting…',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
        const SizedBox(height: 6),
        Text(
          'Signing out and removing synced chats',
          style: TextStyle(fontSize: 13, color: c.textSecondary),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _done() {
    final c = context.allora;
    final result = _result!;
    return Column(
      key: const ValueKey('done'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 450),
          curve: Curves.elasticOut,
          builder: (context, t, child) =>
              Transform.scale(scale: t, child: child),
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: c.success.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_rounded, size: 32, color: c.success),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Disconnected',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: c.text),
        ),
        const SizedBox(height: 8),
        Text(
          result.userMessage +
              (result.roomsWiped > 0
                  ? ' ${result.roomsWiped} ${result.roomsWiped == 1 ? 'chat is' : 'chats are'} being removed now.'
                  : ''),
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13.5, color: c.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _errorView() {
    final c = context.allora;
    return Column(
      key: const ValueKey('error'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.error_outline_rounded, size: 40, color: c.danger),
        const SizedBox(height: 12),
        Text('Something went wrong',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800, color: c.text)),
        const SizedBox(height: 6),
        Text(
          _error ?? 'Please try again.',
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: c.textSecondary),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _disconnect,
                child: const Text('Retry'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
