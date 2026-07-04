import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../data/services/room_wipe_service.dart';
import '../screens/networks/network_connection_cache.dart';
import '../screens/networks/network_meta.dart';

/// Global Matrix client (overridden in main() with the real instance).
final matrixClientProvider =
    Provider<Client>((ref) => throw UnimplementedError());

enum NetworkStatus { connected, available, comingSoon }

class NetworkAccount {
  final NetworkMeta meta;
  final NetworkStatus status;
  final String? accountLabel;
  final String? lastSynced;

  const NetworkAccount({
    required this.meta,
    required this.status,
    this.accountLabel,
    this.lastSynced,
  });
}

class NetworkHubState {
  final List<NetworkAccount> networks;
  final bool isGlobalLoading;
  final bool isWipePending;

  const NetworkHubState({
    required this.networks,
    this.isGlobalLoading = false,
    this.isWipePending = false,
  });

  NetworkHubState copyWith({
    List<NetworkAccount>? networks,
    bool? isGlobalLoading,
    bool? isWipePending,
  }) {
    return NetworkHubState(
      networks: networks ?? this.networks,
      isGlobalLoading: isGlobalLoading ?? this.isGlobalLoading,
      isWipePending: isWipePending ?? this.isWipePending,
    );
  }
}

class NetworkNotifier extends StateNotifier<NetworkHubState> {
  NetworkNotifier() : super(const NetworkHubState(networks: [])) {
    refreshCache();
    NetworkConnectionCache.notifier.addListener(refreshCache);
    RoomWipeService.pending.addListener(_syncWipeState);
    _syncWipeState();
  }

  @override
  void dispose() {
    NetworkConnectionCache.notifier.removeListener(refreshCache);
    RoomWipeService.pending.removeListener(_syncWipeState);
    super.dispose();
  }

  void _syncWipeState() {
    if (!mounted) return;
    state = state.copyWith(
        isWipePending: RoomWipeService.pending.value.isNotEmpty);
  }

  void refreshCache() {
    if (!mounted) return;
    final networks = kNetworks.map((meta) {
      if (!meta.available) {
        return NetworkAccount(meta: meta, status: NetworkStatus.comingSoon);
      }
      final cached = NetworkConnectionCache.get(meta.id);
      return NetworkAccount(
        meta: meta,
        status: cached.connected
            ? NetworkStatus.connected
            : NetworkStatus.available,
        accountLabel: cached.accountLabel,
        lastSynced: cached.lastSynced,
      );
    }).toList();
    state = state.copyWith(networks: networks);
  }

  void setGlobalLoading(bool loading) {
    state = state.copyWith(isGlobalLoading: loading);
  }
}

final networkHubProvider =
    StateNotifierProvider<NetworkNotifier, NetworkHubState>(
        (ref) => NetworkNotifier());
