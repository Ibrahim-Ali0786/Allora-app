// ignore_for_file: unused_import, depend_on_referenced_packages, unused_local_variable, deprecated_member_use
import 'dart:async';
import 'package:flutter/material.dart' hide Visibility;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../telegram/telegram_connection.dart';
import '../facebook/facebook_messenger_connection.dart';
import '../discord/discord_connection.dart';
import '../slack/slack_connection.dart';
import '../twitter/twitter_connection.dart';
import '../auth/welcome_screen.dart';
import '../whatsapp/whatsapp_connection.dart';
import '../instagram/instagram_connection.dart';
import '../../data/services/account_lifecycle.dart';
import '../../data/services/connection_manager.dart';
import '../../data/services/hidden_rooms_store.dart';
import '../networks/network_account_sheet.dart';
import '../networks/network_meta.dart';
import '../networks/network_connection_cache.dart';
import '../bridge/bridge_room_classifier.dart';
import '../../providers/network_provider.dart'; // Riverpod Provider

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

class ConnectNetworksScreen extends ConsumerStatefulWidget {
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
  ConsumerState<ConnectNetworksScreen> createState() =>
      _ConnectNetworksScreenState();
}

class _ConnectNetworksScreenState extends ConsumerState<ConnectNetworksScreen> {
  final ScrollController _scroll = ScrollController();
  double _collapse = 0.0;
  static const double _extra = 56.0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    NetworkConnectionCache.notifier.addListener(_onCacheChange);

    // Initial Hydration
    Future.microtask(() async {
      await NetworkConnectionCache.hydrate();
      ref.read(networkHubProvider.notifier).refreshCache();
      _detectConnections();
    });
  }

  void _onCacheChange() {
    if (mounted) ref.read(networkHubProvider.notifier).refreshCache();
  }

  @override
  void dispose() {
    NetworkConnectionCache.notifier.removeListener(_onCacheChange);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final p = (_scroll.offset.clamp(0.0, _extra) / _extra);
    if ((p - _collapse).abs() > 0.01) setState(() => _collapse = p);
  }

  /// Single multiplexed probe via the ConnectionManager (no per-network
  /// stream subscriptions leaking out of the UI layer anymore).
  Future<void> _detectConnections() async {
    await ref.read(connectionManagerProvider.notifier).probeNetworks();
  }

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
                                  borderRadius: BorderRadius.circular(12))),
                          child: const Text('Cancel',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _T.onSurface)))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: FilledButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      ref
                          .read(networkHubProvider.notifier)
                          .setGlobalLoading(true);
                      try {
                        await AccountLifecycleService.logoutAllora(
                            widget.client);
                        if (mounted) {
                          Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      WelcomeScreen(client: widget.client)),
                              (r) => false);
                        }
                      } catch (_) {
                        if (mounted) {
                          ref
                              .read(networkHubProvider.notifier)
                              .setGlobalLoading(false);
                        }
                      }
                    },
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        backgroundColor: _T.destructive,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: const Text('Log out',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  )),
                ]),
              ]),
        ),
      ),
    );
  }

  void _openConnectFlow(NetworkAccount net) {
    // A single success handler for EVERY network: force-mark it connected
    // right away (some connect sheets never did, which is why the hub never
    // flipped and onboarding never advanced), refresh, then — in onboarding
    // — jump to the chat list once the sheet has closed.
    void onConnected() {
      // Force-mark connected immediately. Several connect sheets never did,
      // which is why the hub never flipped and the app never advanced to the
      // chat list. HomeGate watches the connected state and swaps this screen
      // for the inbox on its own.
      NetworkConnectionCache.markConnected(net.meta.id, force: true);
      // Row shows "Syncing…" while the bridge backfills, then "Connected".
      ref
          .read(connectionManagerProvider.notifier)
          .noteJustConnected(net.meta.id, syncFor: const Duration(seconds: 8));
      // Reconnecting un-hides anything we hid when it was disconnected.
      HiddenRoomsStore.clear(net.meta.id);
      if (net.meta.id == NetworkId.whatsapp) {
        widget.onWhatsAppConnected?.call();
      }
      ref.read(networkHubProvider.notifier).refreshCache();
      _detectConnections();
    }

    switch (net.meta.displayName) {
      case 'WhatsApp':
        showWhatsAppConnectSheet(
            context: context, client: widget.client, onConnected: onConnected);
        break;
      case 'Instagram':
        showInstagramConnectSheet(
            context: context, client: widget.client, onConnected: onConnected);
        break;
      case 'Messenger':
        showMessengerConnectSheet(
            context: context, client: widget.client, onConnected: onConnected);
        break;
      case 'Discord':
        showDiscordConnectSheet(
            context: context, client: widget.client, onConnected: onConnected);
        break;
      case 'Slack':
        showSlackConnectSheet(
            context: context, client: widget.client, onConnected: onConnected);
        break;
      case 'X':
        showTwitterConnectSheet(
            context: context, client: widget.client, onConnected: onConnected);
        break;
      case 'Telegram':
        showTelegramConnectSheet(
            context: context, client: widget.client, onConnected: onConnected);
        break;
    }
  }

  void _openDetailSheet(NetworkAccount net) {
    showNetworkAccountSheet(
      context: context,
      client: widget.client,
      meta: net.meta,
      accountLabel: net.accountLabel,
      lastSynced: net.lastSynced,
      onDisconnected: () {
        ref.read(networkHubProvider.notifier).refreshCache();
        if (net.meta.id == NetworkId.whatsapp) {
          widget.onWhatsAppDisconnected?.call();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(networkHubProvider);
    final connectedCount =
        state.networks.where((n) => n.status == NetworkStatus.connected).length;
    final totalCount = state.networks
        .where((n) => n.status != NetworkStatus.comingSoon)
        .length;

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
                            fontSize: 14.5,
                            color: _T.onSurfaceVariant,
                            height: 1.4)))),
            SliverToBoxAdapter(
                child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
              child: _SyncBadge(
                  total: totalCount,
                  connected: connectedCount,
                  isWiping: state.isWipePending),
            )),
            SliverToBoxAdapter(
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: const Text('MESSAGING ACCOUNTS',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                            color: _T.onSurfaceMuted)))),
            SliverList(
                delegate: SliverChildBuilderDelegate(
              (_, idx) {
                final net = state.networks[idx];
                final isLast = idx == state.networks.length - 1;
                final wipeSpinner =
                    net.meta.displayName == 'WhatsApp' && state.isWipePending;
                return _Row(
                  net: net,
                  showDivider: !isLast,
                  wipeSpinner: wipeSpinner,
                  onTap: net.status == NetworkStatus.comingSoon
                      ? null
                      : () {
                          if (net.status == NetworkStatus.connected) {
                            _openDetailSheet(net);
                          } else {
                            _openConnectFlow(net);
                          }
                        },
                );
              },
              childCount: state.networks.length,
            )),
          ],
        ),
        if (state.isGlobalLoading)
          Positioned.fill(
              child: ColoredBox(
                  color: Colors.black.withOpacity(0.25),
                  child: const Center(
                      child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                              strokeWidth: 3, color: _T.accent))))),
      ]),
    );
  }
}

// ─── SUB-WIDGETS ──────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final double collapse;
  final VoidCallback onBack, onLogout;
  const _TopBar(
      {required this.collapse, required this.onBack, required this.onLogout});
  @override
  Widget build(BuildContext context) => SliverPersistentHeader(
      pinned: true,
      delegate: _TopBarDelegate(
          topPad: MediaQuery.of(context).padding.top,
          collapse: collapse,
          onBack: onBack,
          onLogout: onLogout));
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
                if (Navigator.of(ctx).canPop())
                  IconButton(
                      icon: const Icon(Icons.arrow_back,
                          color: _T.onSurface, size: 23),
                      onPressed: onBack)
                else
                  const SizedBox(width: 12),
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
              ])),
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
        ]));
  }

  @override
  bool shouldRebuild(_TopBarDelegate old) => old.collapse != collapse;
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
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _T.accent))),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final NetworkAccount net;
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(children: [
                  _Glyph(net: net, disabled: disabled),
                  const SizedBox(width: 16),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(net.meta.displayName,
                            style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w500,
                                color: disabled
                                    ? _T.onSurfaceMuted
                                    : _T.onSurface)),
                        const SizedBox(height: 2),
                        Text(
                            wipeSpinner
                                ? 'Clearing rooms in background…'
                                : net.meta.description,
                            style: const TextStyle(
                                fontSize: 13, color: _T.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ])),
                  const SizedBox(width: 10),
                  wipeSpinner
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _T.onSurfaceMuted))
                      : _Status(net: net),
                ])),
          )),
      if (showDivider)
        Padding(
            padding: const EdgeInsets.only(left: 72),
            child: Container(height: 0.5, color: _T.divider)),
    ]);
  }
}

class _Glyph extends StatelessWidget {
  final NetworkAccount net;
  final bool disabled;
  const _Glyph({required this.net, required this.disabled});
  @override
  Widget build(BuildContext ctx) => Opacity(
      opacity: disabled ? 0.35 : 1.0,
      child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              color: net.meta.brandColor,
              borderRadius: BorderRadius.circular(12)),
          child: Center(
              child: net.meta.asset != null
                  ? Padding(
                      padding: const EdgeInsets.all(8),
                      child: Image.asset(net.meta.asset!))
                  : Icon(net.meta.icon, color: Colors.white, size: 18))));
}

class _Status extends ConsumerWidget {
  final NetworkAccount net;
  const _Status({required this.net});

  @override
  Widget build(BuildContext ctx, WidgetRef ref) {
    // Live per-account state: Connected / Syncing… / Disconnecting… /
    // Reconnecting… update in real time from the ConnectionManager streams.
    final live = ref.watch(connectionManagerProvider
        .select((s) => s.networks[net.meta.id]));

    switch (net.status) {
      case NetworkStatus.connected:
        final state = live ?? ConnState.connected;
        final busy = state == ConnState.syncing ||
            state == ConnState.connecting ||
            state == ConnState.reconnecting ||
            state == ConnState.disconnecting;
        final color = state == ConnState.error
            ? _T.destructive
            : busy
                ? _T.accent
                : _T.positive;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Row(
            key: ValueKey(state),
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _T.accent))
              else
                Icon(
                    state == ConnState.error
                        ? Icons.error_rounded
                        : Icons.check_circle,
                    size: 15,
                    color: color),
              const SizedBox(width: 4),
              Text(state.label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color)),
            ],
          ),
        );
      case NetworkStatus.available:
        if (live == ConnState.disconnecting) {
          return Row(mainAxisSize: MainAxisSize.min, children: const [
            SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: _T.onSurfaceMuted)),
            SizedBox(width: 4),
            Text('Disconnecting…',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _T.onSurfaceVariant)),
          ]);
        }
        return const Text('Connect',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: _T.accent));
      case NetworkStatus.comingSoon:
        return const Text('Coming soon',
            style: TextStyle(fontSize: 13, color: _T.onSurfaceMuted));
    }
  }
}
