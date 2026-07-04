import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings/app_settings.dart';
import '../providers/network_provider.dart';
import '../screens/connect_networks_screen.dart';
import 'chat_list/chat_list_screen.dart';

/// The post-login home. Reactively shows:
///
///   • the Connect-networks screen while no platform is connected, and
///   • the chat list once at least one account links.
///
/// This lives *inside* LockGate and only swaps its own child, so the app
/// lock/FLAG_SECURE wrapper is preserved across the transition. The swap is
/// safe even while a connect sheet is open — the sheet is a separate route,
/// so it simply reveals the chat list when it closes.
class HomeGate extends ConsumerWidget {
  const HomeGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(matrixClientProvider);
    final hasConnected = ref.watch(
      networkHubProvider.select(
        (s) => s.networks.any((n) => n.status == NetworkStatus.connected),
      ),
    );

    final reduceMotion = ref.watch(reduceMotionProvider);
    return AnimatedSwitcher(
      duration: Duration(milliseconds: reduceMotion ? 0 : 400),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      child: hasConnected
          ? const ChatListScreen(key: ValueKey('chats'))
          : ConnectNetworksScreen(
              key: const ValueKey('connect'),
              client: client,
            ),
    );
  }
}
