// ignore_for_file: depend_on_referenced_packages, unused_local_variable, deprecated_member_use
import 'dart:async';
import 'package:flutter/material.dart' hide Visibility;
import 'package:matrix/matrix.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import './facebook_messenger_connection.dart';
import './discord_connection.dart';
import './slack_connection.dart';
import './twitter_connection.dart';
import './auth/welcome_screen.dart';
import './whatsapp/whatsapp_connection.dart';
import './instagram_connection.dart';
import './whatsapp/whatsapp_disconnect.dart';
import './whatsapp/whatsapp_disconnect_service.dart';
import './networks/network_meta.dart';
import './networks/network_connection_cache.dart';
import './bridge/bridge_room_classifier.dart';

// ─── DESIGN TOKENS ────────────────────────────────────────────────────────────
class _T {
  static const Color canvas = Color(0xFFF5F5F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFE5E5EA);
  static const Color onSurface = Color(0xFF1C1C1E);
  static const Color onSurfaceVariant = Color(0xFF6B6D78);
  static const Color onSurfaceMuted = Color(0xFFADAFB8);
  static const Color accent = Color(0xFF007AFF);
  static const Color accentTint = Color(0xFFEFF6FF);
  static const Color positive = Color(0xFF34C759);
  static const Color destructive = Color(0xFFFF3B30);
  static const Color rippleTint = Color(0x10007AFF);
}

// ─── SCREEN ───────────────────────────────────────────────────────────────────

class ConnectNetworksScreen extends StatefulWidget {
  final Client client;
  final VoidCallback? onWhatsAppDisconnected;
  final VoidCallback? onWhatsAppConnected;

  const ConnectNetworksScreen({
    super.key,
    required this.client,
    this.onWhatsAppDisconnected,
    this.onWhatsAppConnected,
  });

  @override
  State<ConnectNetworksScreen> createState() => _ConnectNetworksScreenState();
}

class _ConnectNetworksScreenState extends State<ConnectNetworksScreen> {
  bool _isGlobalLoading = false;
  bool _isWipePending = false;

  final ScrollController _scroll = ScrollController();
  double _collapse = 0.0;
  static const double _extra = 56.0;

  late List<_Network> _networks;

  // ── INIT ──────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // 🟢 INSTANT RENDER from cache — no waiting for bridge-bot round trip.
    _networks = _buildNetworksFromCache();
    _scroll.addListener(_onScroll);
    _checkWipePending();
    _bootstrapConnections();

    // Listen to cache changes so the UI updates the moment anything calls
    // markConnected / markDisconnected — even from another screen.
    NetworkConnectionCache.notifier.addListener(_onCacheChange);
  }

  void _onCacheChange() {
    if (mounted) setState(() => _networks = _buildNetworksFromCache());
  }

  @override
  void dispose() {
    NetworkConnectionCache.notifier.removeListener(_onCacheChange);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  // ── BOOTSTRAP ─────────────────────────────────────────────────────────────

  Future<void> _bootstrapConnections() async {
    // Hydrate cache from disk (fast, in-memory if already done).
    await NetworkConnectionCache.hydrate();
    if (mounted) setState(() => _networks = _buildNetworksFromCache());
    // Then do a live probe — but the cache guard in markConnected means
    // a suppressed network will NOT flip back even if the bridge bot lags.
    await _detectConnections();
  }

  List<_Network> _buildNetworksFromCache() {
    return kNetworks.map((meta) {
      if (!meta.available) return _Network(meta: meta, status: _S.comingSoon);
      final cached = NetworkConnectionCache.get(meta.id);
      return _Network(
        meta: meta,
        status: cached.connected ? _S.connected : _S.available,
        accountLabel: cached.accountLabel,
        lastSynced: cached.lastSynced,
      );
    }).toList();
  }

  /// Polls every 2 s to decide when to remove the wipe spinner.
  void _checkWipePending() {
    Future.doWhile(() async {
      if (!mounted) return false;
      final p = await WhatsAppDisconnectService.isWipePending();
      if (mounted) setState(() => _isWipePending = p);
      await Future.delayed(const Duration(seconds: 2));
      return mounted;
    });
  }

  // ── LIVE DETECTION ────────────────────────────────────────────────────────

  /// Sends `list-logins` to each bridge bot and updates status — but
  /// only for networks whose auto-detect window is NOT suppressed.
  Future<void> _detectConnections() async {
    for (int i = 0; i < _networks.length; i++) {
      final net = _networks[i];
      if (net.status == _S.comingSoon) continue;

      // 🔒 Skip if we just disconnected this network.
      final cached = NetworkConnectionCache.get(net.meta.id);
      if (cached.autoDetectSuppressed) continue;

      final botAlias = net.meta.botAlias;

      Room? botRoom;
      for (final r in widget.client.rooms) {
        if (r.displayname.toLowerCase().contains(botAlias)) {
          botRoom = r;
          break;
        }
      }
      if (botRoom == null) continue;

      final capturedRoom = botRoom;
      StreamSubscription? sub;

      sub = widget.client.onTimelineEvent.stream.listen((event) {
        if (event.roomId != capturedRoom.id) return;
        if (event.senderId == widget.client.userID) return;

        final body = (event.content['body'] as String? ?? '').trim();
        if (body.isEmpty) return;

        final result = _parseListLogins(body);
        if (result == null) return;

        if (result.isLoggedIn) {
          // markConnected is a no-op if suppression is active.
          NetworkConnectionCache.markConnected(
            net.meta.id,
            accountLabel: result.accountLabel,
            lastSynced: 'Active',
          );
        } else {
          // Only mark disconnected if not already suppressed (avoid resetting window).
          if (!NetworkConnectionCache.get(net.meta.id).autoDetectSuppressed) {
            NetworkConnectionCache.markDisconnected(net.meta.id, suppressMs: 0);
          }
        }

        // UI update is handled by the _onCacheChange listener above.
        sub?.cancel();
      });

      await capturedRoom.sendTextEvent('list-logins');
      Future.delayed(const Duration(seconds: 8), () => sub?.cancel());
    }
  }

  // ── MISC ──────────────────────────────────────────────────────────────────

  int get _connectedCount =>
      _networks.where((n) => n.status == _S.connected).length;

  void _onScroll() {
    final p = (_scroll.offset.clamp(0.0, _extra) / _extra);
    if ((p - _collapse).abs() > 0.01) setState(() => _collapse = p);
  }

  // ── LOGOUT ────────────────────────────────────────────────────────────────

  void _confirmLogout() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _T.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Log out of Allora?',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: _T.onSurface)),
                const SizedBox(height: 8),
                const Text(
                    "You'll need to sign back in to see your connected accounts and messages.",
                    style: TextStyle(
                        fontSize: 14,
                        color: _T.onSurfaceVariant,
                        height: 1.45)),
                const SizedBox(height: 22),
                Row(children: [
                  Expanded(
                      child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
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
                    onPressed: () async {
                      Navigator.pop(ctx);
                      setState(() => _isGlobalLoading = true);
                      try {
                        // Mark all networks disconnected before logging out.
                        for (final id in NetworkId.values) {
                          await NetworkConnectionCache.markDisconnected(id);
                        }
                        await widget.client.logout();
                        await Supabase.instance.client.auth.signOut();
                        if (mounted) {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                                builder: (_) =>
                                    WelcomeScreen(client: widget.client)),
                            (r) => false,
                          );
                        }
                      } catch (_) {
                        if (mounted) {
                          setState(() => _isGlobalLoading = false);
                        }
                      }
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      backgroundColor: _T.destructive,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Log out',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  )),
                ]),
              ]),
        ),
      ),
    );
  }

  // ── CONNECT FLOWS ─────────────────────────────────────────────────────────

  void _openConnectFlow(_Network net) {
    switch (net.name) {
      case 'WhatsApp':
        showWhatsAppConnectSheet(
          context: context,
          client: widget.client,
          onConnected: () {
            widget.onWhatsAppConnected?.call();
            _detectConnections();
          },
        );
        break;
      case 'Instagram':
        showInstagramConnectSheet(
            context: context,
            client: widget.client,
            onConnected: _detectConnections);
        break;
      case 'Messenger':
        showMessengerConnectSheet(
            context: context,
            client: widget.client,
            onConnected: _detectConnections);
        break;
      case 'Discord':
        showDiscordConnectSheet(
            context: context,
            client: widget.client,
            onConnected: _detectConnections);
        break;
      case 'Slack':
        showSlackConnectSheet(
            context: context,
            client: widget.client,
            onConnected: _detectConnections);
        break;
      case 'X':
        showTwitterConnectSheet(
            context: context,
            client: widget.client,
            onConnected: _detectConnections);
        break;
    }
  }

  void _handleTap(_Network net) {
    if (net.status == _S.comingSoon) return;
    if (net.status == _S.connected) {
      _openDetailSheet(net);
    } else {
      _openConnectFlow(net);
    }
  }

  // ── DETAIL SHEETS ─────────────────────────────────────────────────────────

  void _openDetailSheet(_Network net) {
    if (net.name == 'WhatsApp') {
      showWhatsAppAccountDetailSheet(
        context: context,
        client: widget.client,
        brandColor: net.brandColor,
        asset: net.asset,
        accountLabel: net.accountLabel ?? 'Connected',
        lastSynced: net.lastSynced ?? 'Active',
        onGlobalLoading: (v) => setState(() => _isGlobalLoading = v),
        onDisconnected: () {
          // Cache is already marked by WhatsAppDisconnectService.
          // Clear classifier cache to force fresh room identification.
          BridgeRoomClassifier.clearCache();
          // Just flip the local UI state and show the wipe spinner.
          setState(() {
            _isWipePending = true;
            _networks = _buildNetworksFromCache();
          });
          widget.onWhatsAppDisconnected?.call();
        },
      );
      return;
    }

    // Generic detail sheet for networks without a custom disconnect flow yet.
    showModalBottomSheet(
      context: context,
      backgroundColor: _T.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _Glyph(net: net, disabled: false),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(net.name,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: _T.onSurface)),
                        const SizedBox(height: 2),
                        Text(net.accountLabel ?? 'Connected account',
                            style: const TextStyle(
                                fontSize: 13.5, color: _T.onSurfaceVariant)),
                      ])),
                ]),
                const SizedBox(height: 18),
                Container(height: 1, color: _T.divider),
                const SizedBox(height: 14),
                Row(children: [
                  const Icon(Icons.sync_rounded,
                      size: 17, color: _T.onSurfaceMuted),
                  const SizedBox(width: 8),
                  Text(net.lastSynced ?? 'Synced recently',
                      style: const TextStyle(
                          fontSize: 13.5, color: _T.onSurfaceVariant)),
                ]),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Disconnect coming soon for this network.')),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      side: const BorderSide(color: _T.destructive),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Disconnect',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _T.destructive)),
                  ),
                ),
              ]),
        ),
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _T.canvas,
      body: Stack(children: [
        CustomScrollView(
          controller: _scroll,
          slivers: [
            _TopBar(
                collapse: _collapse,
                onBack: () => Navigator.maybePop(context),
                onLogout: _confirmLogout),
            SliverToBoxAdapter(
                child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: const Text(
                  'Link your networks to read and reply from one inbox.',
                  style: TextStyle(
                      fontSize: 14.5, color: _T.onSurfaceVariant, height: 1.4)),
            )),
            SliverToBoxAdapter(
                child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
              child: _SyncBadge(
                total: _networks.where((n) => n.status != _S.comingSoon).length,
                connected: _connectedCount,
                isWiping: _isWipePending,
              ),
            )),
            SliverToBoxAdapter(
                child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: const Text('MESSAGING ACCOUNTS',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      color: _T.onSurfaceMuted)),
            )),
            SliverList(
                delegate: SliverChildBuilderDelegate(
              (_, idx) {
                final net = _networks[idx];
                final isLast = idx == _networks.length - 1;
                final wipeSpinner = net.name == 'WhatsApp' && _isWipePending;
                return _Row(
                  net: net,
                  showDivider: !isLast,
                  wipeSpinner: wipeSpinner,
                  onTap: net.status == _S.comingSoon
                      ? null
                      : () => _handleTap(net),
                );
              },
              childCount: _networks.length,
            )),
            SliverToBoxAdapter(
                child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              child: const Text(
                'Allora syncs end-to-end where the network supports it. '
                'Disconnecting a network removes its messages from your unified inbox.',
                style: TextStyle(
                    fontSize: 12.5, color: _T.onSurfaceMuted, height: 1.45),
              ),
            )),
          ],
        ),
        if (_isGlobalLoading)
          Positioned.fill(
              child: ColoredBox(
            color: Colors.black.withOpacity(0.25),
            child: const Center(
                child: SizedBox(
              width: 28,
              height: 28,
              child:
                  CircularProgressIndicator(strokeWidth: 3, color: _T.accent),
            )),
          )),
      ]),
    );
  }
}

// ─── SUB-WIDGETS ──────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final double collapse;
  final VoidCallback onBack;
  final VoidCallback onLogout;
  const _TopBar(
      {required this.collapse, required this.onBack, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _TopBarDelegate(
        topPad: MediaQuery.of(context).padding.top,
        collapse: collapse,
        onBack: onBack,
        onLogout: onLogout,
      ),
    );
  }
}

class _TopBarDelegate extends SliverPersistentHeaderDelegate {
  final double topPad, collapse;
  final VoidCallback onBack, onLogout;
  _TopBarDelegate(
      {required this.topPad,
      required this.collapse,
      required this.onBack,
      required this.onLogout});

  static const double _comp = 56, _exp = 56;

  @override
  double get minExtent => topPad + _comp;
  @override
  double get maxExtent => topPad + _comp + _exp;

  @override
  Widget build(BuildContext ctx, double shrink, bool overlaps) {
    final c = collapse.clamp(0.0, 1.0);
    return Container(
      color: Color.lerp(_T.canvas, _T.surface, c),
      child: Stack(children: [
        Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Opacity(
                opacity: c, child: Container(height: 1, color: _T.divider))),
        Positioned(
          top: topPad,
          left: 0,
          right: 0,
          height: _comp,
          child: Row(children: [
            IconButton(
                icon:
                    const Icon(Icons.arrow_back, color: _T.onSurface, size: 23),
                onPressed: onBack),
            Expanded(
                child: Opacity(
                    opacity: c,
                    child: const Text('Connected accounts',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: _T.onSurface)))),
            TextButton(
                onPressed: onLogout,
                child: const Text('Log out',
                    style: TextStyle(
                        color: _T.destructive,
                        fontWeight: FontWeight.w600,
                        fontSize: 14.5))),
            const SizedBox(width: 6),
          ]),
        ),
        Positioned(
            top: topPad + _comp,
            left: 20,
            right: 20,
            height: _exp,
            child: Align(
                alignment: Alignment.bottomLeft,
                child: Opacity(
                    opacity: (1 - c * 1.6).clamp(0.0, 1.0),
                    child: Text('Connected accounts',
                        style: TextStyle(
                            fontSize: 26 - c * 4,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                            color: _T.onSurface))))),
      ]),
    );
  }

  @override
  bool shouldRebuild(_TopBarDelegate old) => old.collapse != collapse;
}

enum _S { connected, available, comingSoon }

class _Network {
  final NetworkMeta meta;
  final String? accountLabel, lastSynced;
  final _S status;

  const _Network({
    required this.meta,
    required this.status,
    this.accountLabel,
    this.lastSynced,
  });

  String get name => meta.displayName;
  String? get asset => meta.asset;
  IconData? get icon => meta.icon;
  Color get brandColor => meta.brandColor;
  String get description => meta.description;

  _Network copyWith({_S? status, String? accountLabel, String? lastSynced}) =>
      _Network(
        meta: meta,
        status: status ?? this.status,
        accountLabel: accountLabel,
        lastSynced: lastSynced,
      );
}

class _SyncBadge extends StatelessWidget {
  final int total, connected;
  final bool isWiping;
  const _SyncBadge(
      {required this.total, required this.connected, required this.isWiping});

  @override
  Widget build(BuildContext ctx) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          color: _T.accentTint, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        if (isWiping)
          const SizedBox(
              width: 8,
              height: 8,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: _T.onSurfaceMuted))
        else
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: connected > 0 ? _T.positive : _T.onSurfaceMuted,
                  shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(
            child: Text(
          isWiping
              ? '$connected of $total connected · clearing rooms…'
              : connected == 0
                  ? 'No accounts connected · tap a network to connect'
                  : connected == total
                      ? 'All accounts connected and syncing'
                      : '$connected of $total accounts connected · syncing',
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w500, color: _T.accent),
        )),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final _Network net;
  final bool showDivider, wipeSpinner;
  final VoidCallback? onTap;
  const _Row(
      {required this.net,
      required this.showDivider,
      required this.onTap,
      this.wipeSpinner = false});

  @override
  Widget build(BuildContext ctx) {
    final disabled = onTap == null;
    return Column(children: [
      Material(
        color: _T.surface,
        child: InkWell(
          onTap: onTap,
          splashColor: _T.rippleTint,
          highlightColor: _T.rippleTint,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(children: [
              _Glyph(net: net, disabled: disabled),
              const SizedBox(width: 16),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(net.name,
                        style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w500,
                            color:
                                disabled ? _T.onSurfaceMuted : _T.onSurface)),
                    const SizedBox(height: 2),
                    Text(
                      wipeSpinner
                          ? 'Clearing rooms in background…'
                          : net.description,
                      style: const TextStyle(
                          fontSize: 13, color: _T.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ])),
              const SizedBox(width: 10),
              wipeSpinner
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _T.onSurfaceMuted))
                  : _Status(net: net),
            ]),
          ),
        ),
      ),
      if (showDivider)
        Padding(
            padding: const EdgeInsets.only(left: 72),
            child: Container(height: 0.5, color: _T.divider)),
    ]);
  }
}

class _Glyph extends StatelessWidget {
  final _Network net;
  final bool disabled;
  const _Glyph({required this.net, required this.disabled});

  @override
  Widget build(BuildContext ctx) => Opacity(
        opacity: disabled ? 0.35 : 1.0,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              color: net.brandColor, borderRadius: BorderRadius.circular(12)),
          child: Center(
              child: net.asset != null
                  ? Padding(
                      padding: const EdgeInsets.all(8),
                      child: Image.asset(net.asset!))
                  : Icon(net.icon, color: Colors.white, size: 18)),
        ),
      );
}

class _Status extends StatelessWidget {
  final _Network net;
  const _Status({required this.net});

  @override
  Widget build(BuildContext ctx) {
    switch (net.status) {
      case _S.connected:
        return Row(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.check_circle, size: 15, color: _T.positive),
          SizedBox(width: 4),
          Text('Connected',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _T.positive)),
        ]);
      case _S.available:
        return const Text('Connect',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: _T.accent));
      case _S.comingSoon:
        return const Text('Coming soon',
            style: TextStyle(fontSize: 13, color: _T.onSurfaceMuted));
    }
  }
}

// ─── LIST-LOGINS PARSER ───────────────────────────────────────────────────────

class _LoginResult {
  final bool isLoggedIn;
  final String? accountLabel;
  _LoginResult({required this.isLoggedIn, this.accountLabel});
}

_LoginResult? _parseListLogins(String body) {
  final lower = body.toLowerCase();

  if (lower.contains('not logged in') ||
      lower.contains("you're not logged into") ||
      lower.contains('you are not logged into') ||
      lower.contains('no logins') ||
      lower.contains("haven't logged in") ||
      lower.contains('no active logins')) {
    return _LoginResult(isLoggedIn: false);
  }

  final positive = lower.contains('list of logins') ||
      lower.contains('logged in as') ||
      lower.contains('active logins') ||
      RegExp(r'^\s*[*\-•]\s*\S+', multiLine: true).hasMatch(body);

  if (positive) {
    final phone = RegExp(r'\+\d{6,15}').firstMatch(body);
    final handle = RegExp(r'@[\w.\-]+').firstMatch(body);
    return _LoginResult(
        isLoggedIn: true, accountLabel: phone?.group(0) ?? handle?.group(0));
  }

  return null;
}
