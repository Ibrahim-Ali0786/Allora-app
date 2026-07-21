import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/allora_avatar.dart';
import '../../data/settings/app_settings.dart';
import '../../providers/network_provider.dart';
import '../../screens/connection_screen/connect_networks_screen.dart';
import '../settings/ai_settings_screen.dart';
import '../settings/privacy_settings_screen.dart';
import '../settings/security_settings_screen.dart';

/// Premium profile page: cover + avatar, editable display name & bio,
/// account details, and status cards (connected accounts, security, AI,
/// privacy) with quick actions.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _picker = ImagePicker();
  Uri? _avatarUri;
  String? _displayName;
  bool _loading = true;
  bool _uploadingAvatar = false;

  Client get client => ref.read(matrixClientProvider);

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final id = client.userID;
      if (id != null) {
        final profile = await client.getProfileFromUserId(id);
        if (mounted) {
          setState(() {
            _displayName = profile.displayName;
            _avatarUri = profile.avatarUrl;
          });
        }
      }
    } catch (_) {
      // best-effort — fall back to the username
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// A clean, email-derived handle (e.g. "ibrahimtin0786@gmail.com" →
  /// "ibrahimtin0786"). Unique per account; falls back to the Matrix id.
  String get _username {
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email != null && email.contains('@')) {
      final local = email.split('@').first.toLowerCase();
      final cleaned = local.replaceAll(RegExp(r'[^a-z0-9._-]'), '');
      if (cleaned.isNotEmpty) return cleaned;
    }
    return client.userID?.split(':').first.replaceAll('@', '') ?? 'user';
  }

  Future<void> _changeAvatar() async {
    XFile? file;
    try {
      file = await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 88, maxWidth: 1024);
    } catch (_) {
      return;
    }
    if (file == null || !mounted) return;
    setState(() => _uploadingAvatar = true);
    try {
      final Uint8List bytes = await file.readAsBytes();
      await client.setAvatar(MatrixImageFile(bytes: bytes, name: file.name));
      await _loadProfile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile photo updated')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Couldn\u2019t update photo')));
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _editName() async {
    final settings = ref.read(settingsProvider);
    final current = settings.displayName.isNotEmpty
        ? settings.displayName
        : (_displayName ?? _username);
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Display name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Your name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (result == null) return;
    // Stored on-device: the Matrix profile write API isn't exposed by this
    // SDK build, and a bridged user's identity lives on each platform anyway.
    ref.read(settingsProvider.notifier).setDisplayName(result);
  }

  Future<void> _editBio() async {
    final controller =
        TextEditingController(text: ref.read(settingsProvider).bio);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('About'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          maxLength: 160,
          decoration: const InputDecoration(hintText: 'A short bio'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (result != null) ref.read(settingsProvider.notifier).setBio(result);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    final settings = ref.watch(settingsProvider);
    final networks = ref.watch(networkHubProvider);
    final connectedCount = networks.networks
        .where((n) => n.status == NetworkStatus.connected)
        .length;
    final user = Supabase.instance.client.auth.currentUser;
    final name = settings.displayName.isNotEmpty
        ? settings.displayName
        : _username;

    return Scaffold(
      backgroundColor: c.canvas,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 200,
            backgroundColor: c.accent,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [c.accent, c.bubbleMineDeep],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -46),
              child: Column(
                children: [
                  Stack(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: c.canvas,
                          shape: BoxShape.circle,
                        ),
                        child: _loading
                            ? CircleAvatar(
                                radius: 48,
                                backgroundColor: c.surfaceAlt,
                                child: const CircularProgressIndicator(
                                    strokeWidth: 2))
                            : AlloraAvatar(
                                name: name,
                                mxcUri: _avatarUri,
                                client: client,
                                size: 96,
                                showNetworkBadge: false,
                              ),
                      ),
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: GestureDetector(
                          onTap: _uploadingAvatar ? null : _changeAvatar,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: c.accent,
                              shape: BoxShape.circle,
                              border: Border.all(color: c.canvas, width: 2.5),
                            ),
                            child: _uploadingAvatar
                                ? const Padding(
                                    padding: EdgeInsets.all(7),
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.camera_alt_rounded,
                                    color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: _editName,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(name,
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                color: c.text)),
                        const SizedBox(width: 6),
                        Icon(Icons.edit_rounded,
                            size: 16, color: c.textTertiary),
                      ],
                    ),
                  ),
                  Text('@$_username',
                      style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: c.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_rounded, size: 14, color: c.accent),
                        const SizedBox(width: 5),
                        Text('Allora · Free',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: c.accent)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: GestureDetector(
                      onTap: _editBio,
                      child: Text(
                        settings.bio.isEmpty ? 'Add a bio' : settings.bio,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          fontStyle: settings.bio.isEmpty
                              ? FontStyle.italic
                              : FontStyle.normal,
                          color: settings.bio.isEmpty
                              ? c.textTertiary
                              : c.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: Column(
                children: [
                  _sectionCard(context, 'ACCOUNT DETAILS', [
                    _infoRow(Icons.person_outline_rounded, 'Name', name),
                    if (user?.email != null)
                      _infoRow(Icons.mail_outline_rounded, 'Email account',
                          user!.email!),
                    _infoRow(
                        Icons.alternate_email_rounded, 'Username', _username),
                  ]),
                  const SizedBox(height: 14),
                  _statGrid(context, connectedCount, settings),
                  const SizedBox(height: 14),
                  _actionCard(
                    context,
                    icon: Icons.hub_rounded,
                    color: c.accent,
                    title: 'Connected accounts',
                    subtitle:
                        '$connectedCount linked · manage bridges',
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                ConnectNetworksScreen(client: client))),
                  ),
                  _actionCard(
                    context,
                    icon: Icons.lock_rounded,
                    color: const Color(0xFF1FA45B),
                    title: 'Security',
                    subtitle: settings.appLockEnabled
                        ? 'App lock is on'
                        : 'Set up app lock',
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SecuritySettingsScreen())),
                  ),
                  _actionCard(
                    context,
                    icon: Icons.visibility_off_rounded,
                    color: const Color(0xFF7C5CFC),
                    title: 'Privacy',
                    subtitle: settings.incognito
                        ? 'Incognito is on'
                        : 'Read receipts, typing, hidden chats',
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const PrivacySettingsScreen())),
                  ),
                  _actionCard(
                    context,
                    icon: Icons.auto_awesome_rounded,
                    color: const Color(0xFFE45794),
                    title: 'AI preferences',
                    subtitle: settings.aiEnabled
                        ? 'Allora AI is on'
                        : 'Allora AI is off',
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AiSettingsScreen())),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statGrid(
      BuildContext context, int connectedCount, AppSettingsState s) {
    final c = context.allora;
    Widget stat(IconData icon, String value, String label, Color color) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.outline),
            ),
            child: Column(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 6),
                Text(value,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: c.text)),
                Text(label,
                    style:
                        TextStyle(fontSize: 11, color: c.textTertiary)),
              ],
            ),
          ),
        );
    return Row(
      children: [
        stat(Icons.hub_rounded, '$connectedCount', 'Accounts', c.accent),
        stat(Icons.star_rounded, '${s.starred.length}', 'Starred',
            const Color(0xFFF5A623)),
        stat(
            s.appLockEnabled ? Icons.shield_rounded : Icons.shield_outlined,
            s.appLockEnabled ? 'On' : 'Off',
            'Lock',
            const Color(0xFF1FA45B)),
      ],
    );
  }

  Widget _sectionCard(
      BuildContext context, String title, List<Widget> rows) {
    final c = context.allora;
    final filtered = rows.whereType<Widget>().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Text(title,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: c.textTertiary)),
        ),
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.outline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: filtered),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    final c = context.allora;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 19, color: c.textSecondary),
          const SizedBox(width: 14),
          Text(label,
              style: TextStyle(fontSize: 13.5, color: c.textTertiary)),
          const Spacer(),
          Flexible(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: c.text)),
          ),
        ],
      ),
    );
  }

  Widget _actionCard(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final c = context.allora;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.outline),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Icon(Icons.chevron_right_rounded, color: c.textTertiary),
        onTap: onTap,
      ),
    );
  }
}
