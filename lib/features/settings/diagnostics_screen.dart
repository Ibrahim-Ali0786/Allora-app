import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/connection_manager.dart';
import '../../data/services/room_wipe_service.dart';
import '../../data/services/scheduled_message_service.dart';
import '../../providers/network_provider.dart';
import '../../screens/networks/network_meta.dart';

/// Live diagnostics: version, connection health, bridge status, storage,
/// encryption and background workers — plus one-tap export to clipboard.
class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  static const _version = '2.0.0 (2)';
  int _dbBytes = 0;

  @override
  void initState() {
    super.initState();
    _measureDb();
  }

  Future<void> _measureDb() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File(p.join(dir.path, 'allora_matrix.db'));
      if (f.existsSync() && mounted) {
        setState(() => _dbBytes = f.lengthSync());
      }
    } catch (_) {}
  }

  String _fmt(int b) => b > 1048576
      ? '${(b / 1048576).toStringAsFixed(1)} MB'
      : '${(b / 1024).toStringAsFixed(0)} KB';

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    final client = ref.watch(matrixClientProvider);
    final conn = ref.watch(connectionManagerProvider);
    final networks = ref.watch(networkHubProvider);
    final wiping = ref.watch(wipePendingProvider);

    bool encryption;
    try {
      encryption = client.encryptionEnabled;
    } catch (_) {
      encryption = false;
    }

    final connected = networks.networks
        .where((n) => n.status == NetworkStatus.connected)
        .toList();

    final rows = <_Diag>[
      _Diag('App version', _version),
      _Diag('Matrix', conn.matrix.label,
          good: conn.matrix.isHealthy),
      _Diag('Logged in', client.isLogged() ? 'Yes' : 'No',
          good: client.isLogged()),
      _Diag('User ID', client.userID ?? '—', mono: true),
      _Diag('Homeserver', client.homeserver?.host ?? '—'),
      _Diag('First sync',
          client.prevBatch != null ? 'Complete' : 'Pending',
          good: client.prevBatch != null),
      _Diag('Encryption', encryption ? 'Enabled' : 'Disabled',
          good: encryption),
      _Diag('Rooms', '${client.rooms.length}'),
      _Diag('Connected platforms', '${connected.length}'),
      _Diag('Database size', _fmt(_dbBytes)),
      _Diag('Pending room wipes', '${wiping.length}',
          good: wiping.isEmpty),
      _Diag('Scheduled messages',
          '${ScheduledMessageService.queue.value.length}'),
    ];

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Copy report',
            icon: const Icon(Icons.copy_all_rounded),
            onPressed: () => _export(rows, connected),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(context, [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(color: c.outline, height: 1),
              _row(rows[i]),
            ],
          ]),
          if (connected.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
              child: Text('BRIDGE STATUS',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: c.textTertiary)),
            ),
            _card(context, [
              for (var i = 0; i < connected.length; i++) ...[
                if (i > 0) Divider(color: c.outline, height: 1),
                _bridgeRow(connected[i].meta, conn.stateFor(connected[i].meta.id)),
              ],
            ]),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _export(rows, connected),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Export diagnostics'),
          ),
        ],
      ),
    );
  }

  void _export(List<_Diag> rows, List<NetworkAccount> connected) {
    final buffer = StringBuffer('Allora diagnostics\n==================\n');
    for (final r in rows) {
      buffer.writeln('${r.label}: ${r.value}');
    }
    if (connected.isNotEmpty) {
      buffer.writeln('\nBridges:');
      for (final n in connected) {
        buffer.writeln('  ${n.meta.displayName}: connected');
      }
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Diagnostics copied to clipboard')));
  }

  Widget _card(BuildContext context, List<Widget> children) {
    final c = context.allora;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _row(_Diag d) {
    final c = context.allora;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(d.label,
                style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
          ),
          if (d.good != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                d.good! ? Icons.check_circle_rounded : Icons.error_rounded,
                size: 15,
                color: d.good! ? c.success : c.warning,
              ),
            ),
          Flexible(
            child: Text(
              d.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: c.text,
                fontFamily: d.mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bridgeRow(NetworkMeta meta, ConnState state) {
    final c = context.allora;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: meta.brandColor,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(6),
            child: meta.asset != null
                ? Image.asset(meta.asset!, color: Colors.white,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.link, color: Colors.white, size: 16))
                : Icon(meta.icon ?? Icons.link,
                    color: Colors.white, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(meta.displayName,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: state.isHealthy ? c.success : c.warning,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(state.label,
              style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
        ],
      ),
    );
  }
}

class _Diag {
  final String label;
  final String value;
  final bool? good;
  final bool mono;
  const _Diag(this.label, this.value, {this.good, this.mono = false});
}
