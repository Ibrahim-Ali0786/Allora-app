// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../providers/network_provider.dart' show matrixClientProvider;
import '../../screens/networks/network_connection_cache.dart';
import '../../screens/networks/network_meta.dart';
import 'account_lifecycle.dart';

/// Unified connection state for Matrix and every bridged network.
enum ConnState {
  connecting,
  connected,
  syncing,
  reconnecting,
  disconnected,
  expired,
  error,
}

extension ConnStateLabel on ConnState {
  String get label {
    switch (this) {
      case ConnState.connecting:
        return 'Connecting…';
      case ConnState.connected:
        return 'Connected';
      case ConnState.syncing:
        return 'Syncing…';
      case ConnState.reconnecting:
        return 'Reconnecting…';
      case ConnState.disconnected:
        return 'Disconnected';
      case ConnState.expired:
        return 'Session expired';
      case ConnState.error:
        return 'Connection error';
    }
  }

  bool get isHealthy => this == ConnState.connected || this == ConnState.syncing;
}

@immutable
class ConnectionSnapshot {
  final ConnState matrix;
  final Map<NetworkId, ConnState> networks;

  const ConnectionSnapshot({
    this.matrix = ConnState.connecting,
    this.networks = const {},
  });

  ConnState stateFor(NetworkId id) => networks[id] ?? ConnState.disconnected;

  ConnectionSnapshot copyWith({
    ConnState? matrix,
    Map<NetworkId, ConnState>? networks,
  }) =>
      ConnectionSnapshot(
        matrix: matrix ?? this.matrix,
        networks: networks ?? this.networks,
      );
}

/// Central, stream-driven connection monitor.
///
/// * Matrix state comes straight from the SDK's sync status stream — the UI
///   flips to "Reconnecting…"/"Connected" the moment the socket does, with
///   zero polling and zero fixed delays.
/// * Bridged-network states are derived from [NetworkConnectionCache]
///   (persisted truth) overlaid with short-lived transient states pushed by
///   connect/disconnect flows ("connecting", "syncing").
/// * [probeNetworks] multiplexes a single timeline listener over every
///   bridge bot instead of one leaky subscription per network.
class ConnectionManager extends StateNotifier<ConnectionSnapshot> {
  static ConnectionManager? instance;

  final Client client;
  StreamSubscription? _syncSub;
  StreamSubscription? _loginSub;
  StreamSubscription? _probeSub;
  Timer? _probeTimeout;
  bool _lastSyncErrored = false;
  final Map<NetworkId, ConnState> _transient = {};

  ConnectionManager(this.client) : super(const ConnectionSnapshot()) {
    instance = this;
    _recomputeNetworks();
    NetworkConnectionCache.notifier.addListener(_recomputeNetworks);

    _syncSub = client.onSyncStatus.stream.listen(_onSyncStatus);
    _loginSub = client.onLoginStateChanged.stream.listen(_onLoginState);

    // Seed the matrix state from what we already know.
    if (!client.isLogged()) {
      state = state.copyWith(matrix: ConnState.disconnected);
    } else if (client.prevBatch != null) {
      state = state.copyWith(matrix: ConnState.connected);
    }
  }

  // ── Matrix ────────────────────────────────────────────────────────────────

  void _onSyncStatus(SyncStatusUpdate update) {
    final s = update.status;
    ConnState? next;

    if (s == SyncStatus.error) {
      _lastSyncErrored = true;
      next = ConnState.error;
    } else if (s == SyncStatus.waitingForResponse) {
      if (client.prevBatch == null) {
        next = ConnState.connecting; // first-ever sync
      } else if (_lastSyncErrored) {
        next = ConnState.reconnecting;
      } else {
        next = ConnState.connected; // healthy long-poll
      }
    } else if (s == SyncStatus.processing) {
      next = ConnState.syncing;
    } else if (s == SyncStatus.finished) {
      _lastSyncErrored = false;
      next = ConnState.connected;
    }

    if (next != null && next != state.matrix) {
      state = state.copyWith(matrix: next);
    }
  }

  void _onLoginState(LoginState loginState) {
    if (loginState == LoginState.loggedOut) {
      state = state.copyWith(matrix: ConnState.disconnected);
    } else if (loginState == LoginState.softLoggedOut) {
      state = state.copyWith(matrix: ConnState.expired);
    } else if (loginState == LoginState.loggedIn) {
      state = state.copyWith(
          matrix: client.prevBatch == null
              ? ConnState.connecting
              : ConnState.connected);
    }
  }

  // ── Bridged networks ─────────────────────────────────────────────────────

  void _recomputeNetworks() {
    final map = <NetworkId, ConnState>{};
    for (final meta in kNetworks) {
      if (!meta.available) continue;
      final transient = _transient[meta.id];
      if (transient != null) {
        map[meta.id] = transient;
        continue;
      }
      final snap = NetworkConnectionCache.get(meta.id);
      map[meta.id] = snap.connected ? ConnState.connected : ConnState.disconnected;
    }
    if (mounted) state = state.copyWith(networks: map);
  }

  /// Transient overlays from connect/disconnect flows.
  void noteConnecting(NetworkId id) => _setTransient(id, ConnState.connecting);
  void noteSyncing(NetworkId id) => _setTransient(id, ConnState.syncing);

  void noteConnected(NetworkId id) {
    _transient.remove(id);
    _recomputeNetworks();
  }

  void noteDisconnected(NetworkId id) {
    _transient.remove(id);
    _recomputeNetworks();
  }

  void _setTransient(NetworkId id, ConnState s) {
    _transient[id] = s;
    _recomputeNetworks();
  }

  // ── Probing ──────────────────────────────────────────────────────────────

  /// Ask every bridge bot for its login state with a single multiplexed
  /// listener. Sticky manual disconnects are respected: a probe can only
  /// re-connect a network the user hasn't explicitly disconnected.
  Future<void> probeNetworks() async {
    if (!client.isLogged()) return;

    final waiting = <String, NetworkId>{}; // botRoomId -> network
    for (final meta in kNetworks) {
      if (!meta.available) continue;
      final cached = NetworkConnectionCache.get(meta.id);
      if (cached.autoDetectSuppressed) continue;
      final room = AccountLifecycleService.findManagementRoom(client, meta.id);
      if (room == null) continue;
      waiting[room.id] = meta.id;
    }
    if (waiting.isEmpty) return;

    await _probeSub?.cancel();
    _probeTimeout?.cancel();

    _probeSub = client.onTimelineEvent.stream.listen((event) {
      final roomId = event.roomId;
      if (roomId == null) return;
      final networkId = waiting[roomId];
      if (networkId == null) return;
      if (event.senderId == client.userID) return;

      final body = event.content['body']?.toString() ?? '';
      final result = parseListLogins(body);
      if (result == null) return;

      if (result.isLoggedIn) {
        NetworkConnectionCache.markConnected(networkId,
            accountLabel: result.accountLabel, lastSynced: 'Active');
      } else if (!NetworkConnectionCache.get(networkId).autoDetectSuppressed) {
        NetworkConnectionCache.markDisconnected(networkId, suppressMs: 0);
      }
      waiting.remove(roomId);
      if (waiting.isEmpty) {
        _probeSub?.cancel();
        _probeSub = null;
        _probeTimeout?.cancel();
      }
    });

    for (final entry in waiting.entries.toList()) {
      final room = client.getRoomById(entry.key);
      if (room == null) continue;
      try {
        await room.sendTextEvent('list-logins');
      } catch (e) {
        debugPrint('ConnectionManager: probe send failed for ${entry.value}: $e');
      }
    }

    _probeTimeout = Timer(const Duration(seconds: 12), () {
      _probeSub?.cancel();
      _probeSub = null;
    });
  }

  void shutdown() {
    _probeTimeout?.cancel();
    _probeSub?.cancel();
    _probeSub = null;
  }

  @override
  void dispose() {
    NetworkConnectionCache.notifier.removeListener(_recomputeNetworks);
    _syncSub?.cancel();
    _loginSub?.cancel();
    shutdown();
    if (identical(instance, this)) instance = null;
    super.dispose();
  }
}

/// Parsed bridge-bot reply to `list-logins`.
class LoginProbeResult {
  final bool isLoggedIn;
  final String? accountLabel;
  const LoginProbeResult({required this.isLoggedIn, this.accountLabel});
}

LoginProbeResult? parseListLogins(String body) {
  final lower = body.toLowerCase();
  if (lower.contains('not logged in') ||
      lower.contains("you're not logged into") ||
      lower.contains('no logins')) {
    return const LoginProbeResult(isLoggedIn: false);
  }
  if (lower.contains('list of logins') ||
      lower.contains('logged in as') ||
      RegExp(r'^\s*[*\-•]\s*\S+', multiLine: true).hasMatch(body)) {
    final phone = RegExp(r'\+\d{6,15}').firstMatch(body);
    final handle = RegExp(r'@[\w.\-]+').firstMatch(body);
    return LoginProbeResult(
        isLoggedIn: true, accountLabel: phone?.group(0) ?? handle?.group(0));
  }
  return null;
}

final connectionManagerProvider =
    StateNotifierProvider<ConnectionManager, ConnectionSnapshot>(
        (ref) => ConnectionManager(ref.watch(matrixClientProvider)));
