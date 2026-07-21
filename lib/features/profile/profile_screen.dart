import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/allora_avatar.dart';
import '../../data/services/account_lifecycle.dart';
import '../../data/settings/app_settings.dart';
import '../../providers/network_provider.dart';
import '../../screens/auth/welcome_screen.dart';
import '../../screens/connection_screen/connect_networks_screen.dart';

/// Premium profile page: cover gradient, avatar, editable display name & bio,
/// account details with member-since date, stats, and sign-out.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _picker = ImagePicker();
  Uri? _avatarUri;
  String? _matrixDisplayName;
  bool _loading = true;
  bool _uploadingAvatar = false;
  bool _savingName = false;

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
            _matrixDisplayName = profile.displayName;
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

  /// Returns the best available username handle.
  String get _username {
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email != null && email.contains('@')) {
      final local = email.split('@').first.toLowerCase();
      final cleaned = local.replaceAll(RegExp(r'[^a-z0-9._-]'), '');
      if (cleaned.isNotEmpty) return cleaned;
    }
    return client.userID?.split(':').first.replaceAll('@', '') ?? 'user';
  }

  /// Priority: local setting → Matrix profile → username handle.
  String _resolvedName(AppSettingsState settings) {
    if (settings.displayName.isNotEmpty) return settings.displayName;
    if (_matrixDisplayName != null && _matrixDisplayName!.isNotEmpty) {
      return _matrixDisplayName!;
    }
    return _username;
  }

  String get _memberSince {
    final ts = Supabase.instance.client.auth.currentUser?.createdAt;
    if (ts == null) return '';
    try {
      final date = DateTime.parse(ts);
      const months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      return '${months[date.month - 1]} ${date.year}';
    } catch (_) {
      return '';
    }
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
        _showSnack('Profile photo updated ✓', success: true);
      }
    } catch (_) {
      if (mounted) _showSnack('Couldn\'t update photo');
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _editName() async {
    final settings = ref.read(settingsProvider);
    final current = _resolvedName(settings);
    final controller = TextEditingController(text: current);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = ctx.allora;
        return AlertDialog(
          backgroundColor: c.surface,
          title: Text('Display name',
              style: TextStyle(color: c.text, fontWeight: FontWeight.w700)),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'Your name',
              hintStyle: TextStyle(color: c.textTertiary),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('Save')),
          ],
        );
      },
    );

    if (result == null || result.isEmpty) return;

    setState(() => _savingName = true);
    // 1. Save locally (instant, across-device via shared prefs)
    ref.read(settingsProvider.notifier).setDisplayName(result);

    // 2. Sync to Matrix profile (visible to contacts and other devices)
    try {
      await client.request(
        RequestType.PUT,
        '/client/v3/profile/${Uri.encodeComponent(client.userID!)}/displayname',
        data: {'displayname': result},
      );
      setState(() => _matrixDisplayName = result);
      if (mounted) _showSnack('Name updated ✓', success: true);
    } catch (_) {
      // Matrix sync failed — local save still works
      if (mounted) _showSnack('Saved locally (Matrix sync failed)');
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _editBio() async {
    final controller =
        TextEditingController(text: ref.read(settingsProvider).bio);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = ctx.allora;
        return AlertDialog(
          backgroundColor: c.surface,
          title: Text('About you',
              style: TextStyle(color: c.text, fontWeight: FontWeight.w700)),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            maxLength: 160,
            decoration: InputDecoration(
              hintText: 'A short bio',
              hintStyle: TextStyle(color: c.textTertiary),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('Save')),
          ],
        );
      },
    );
    if (result != null) {
      ref.read(settingsProvider.notifier).setBio(result);
      _showSnack('Bio updated ✓', success: true);
    }
  }

  void _showSnack(String msg, {bool success = false}) {
    final c = context.allora;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? c.success : null,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _confirmLogout() {
    final c = context.allora;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text('Log out?',
            style: TextStyle(color: c.text, fontWeight: FontWeight.w700)),
        content: Text(
          'Your connected networks stay linked to your account.',
          style: TextStyle(color: c.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await AccountLifecycleService.logoutAllora(client);
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                      builder: (_) => WelcomeScreen(client: client)),
                  (r) => false,
                );
              }
            },
            child: Text('Log out', style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );
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
    final name = _resolvedName(settings);
    final memberSince = _memberSince;

    return Scaffold(
      backgroundColor: c.canvas,
      body: CustomScrollView(
        slivers: [
          // ── Cover / AppBar ─────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: 180,
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

          // ── Avatar + identity ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -46),
              child: Column(
                children: [
                  // Avatar
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
                              border:
                                  Border.all(color: c.canvas, width: 2.5),
                            ),
                            child: _uploadingAvatar
                                ? const Padding(
                                    padding: EdgeInsets.all(7),
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white))
                                : const Icon(Icons.camera_alt_rounded,
                                    color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Display name (tappable to edit)
                  GestureDetector(
                    onTap: _editName,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_savingName)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: c.accent),
                            ),
                          ),
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
                      style:
                          TextStyle(fontSize: 13.5, color: c.textSecondary)),
                  const SizedBox(height: 8),

                  // Plan badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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

                  // Bio (tappable)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: GestureDetector(
                      onTap: _editBio,
                      child: Text(
                        settings.bio.isEmpty ? 'Tap to add a bio' : settings.bio,
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

          // ── Content cards ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Account details
                  _sectionLabel('ACCOUNT DETAILS'),
                  _card([
                    _infoRow(Icons.person_outline_rounded, 'Name', name),
                    if (user?.email != null) ...[
                      _divider(),
                      _infoRow(Icons.mail_outline_rounded, 'Email',
                          user!.email!),
                    ],
                    _divider(),
                    _infoRow(Icons.alternate_email_rounded, 'Username',
                        '@$_username'),
                    if (memberSince.isNotEmpty) ...[
                      _divider(),
                      _infoRow(Icons.calendar_today_rounded, 'Member since',
                          memberSince),
                    ],
                  ]),
                  const SizedBox(height: 14),

                  // Connected Social Accounts
                  _sectionLabel('CONNECTED ACCOUNTS'),
                  _card([
                    ListTile(
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: c.accent.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(Icons.hub_rounded, color: c.accent, size: 20),
                      ),
                      title: const Text('Linked Networks',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                      subtitle: Text(
                          connectedCount > 0
                              ? '$connectedCount network${connectedCount > 1 ? 's' : ''} connected'
                              : 'Connect WhatsApp, Telegram, Instagram…',
                          style: TextStyle(fontSize: 13, color: c.textSecondary)),
                      trailing: Icon(Icons.chevron_right_rounded, color: c.textTertiary),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ConnectNetworksScreen(client: client),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),

                  // Stats grid
                  _statGrid(connectedCount, settings),
                  const SizedBox(height: 24),

                  // Sign out
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.danger,
                        side: BorderSide(
                            color: c.danger.withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _confirmLogout,
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text('Sign out',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  Widget _sectionLabel(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Text(title,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: context.allora.textTertiary)),
      );

  Widget _card(List<Widget> children) {
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

  Widget _divider() {
    final c = context.allora;
    return Padding(
      padding: const EdgeInsets.only(left: 52),
      child: Divider(color: c.outline, height: 1),
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

  Widget _statGrid(int connectedCount, AppSettingsState s) {
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
                    style: TextStyle(fontSize: 11, color: c.textTertiary)),
              ],
            ),
          ),
        );
    return Row(
      children: [
        stat(Icons.hub_rounded, '$connectedCount', 'Accounts', c.accent),
        stat(Icons.star_rounded, '${s.starred.length}', 'Starred',
            c.warning),
        stat(
            s.appLockEnabled ? Icons.shield_rounded : Icons.shield_outlined,
            s.appLockEnabled ? 'On' : 'Off',
            'Lock',
            c.success),
      ],
    );
  }
}
