// ignore_for_file: unnecessary_non_null_assertion, unused_element, curly_braces_in_flow_control_structures, unused_import, unnecessary_string_interpolations, use_build_context_synchronously, deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart' hide Visibility;
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

// ─── BRAND COLOR ──────────────────────────────────────────────────────────────

const Color kSlackAubergine = Color(0xFF4A154B);

// ─── PUBLIC ENTRY POINT ───────────────────────────────────────────────────────

/// Opens the Slack "connect workspace" bottom sheet.
///
/// Slack workspaces (especially SSO ones) can't be logged into with a plain
/// username/password through a bridge, so this uses the token + cookie pair
/// most mautrix-slack bridges expect. [onConnected] fires once the bridge
/// bot confirms a successful login.
void showSlackConnectSheet({
  required BuildContext context,
  required Client client,
  VoidCallback? onConnected,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => SlackConnectSheet(
      client: client,
      onConnected: onConnected,
    ),
  );
}

// ─── THE CONNECT SHEET ────────────────────────────────────────────────────────

class SlackConnectSheet extends StatefulWidget {
  final Client client;
  final VoidCallback? onConnected;

  const SlackConnectSheet({
    super.key,
    required this.client,
    this.onConnected,
  });

  @override
  State<SlackConnectSheet> createState() => _SlackConnectSheetState();
}

class _SlackConnectSheetState extends State<SlackConnectSheet> {
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _cookieController = TextEditingController();

  StreamSubscription<Event>? _activeSub;

  bool _sheetLoading = false;
  String? _sheetError;
  bool _connected = false;
  bool _obscureFields = true;

  @override
  void dispose() {
    _tokenController.dispose();
    _cookieController.dispose();
    _activeSub?.cancel();
    super.dispose();
  }

  Room? _findSlackRoom() {
    for (final room in widget.client.rooms) {
      if (room.displayname.toLowerCase().contains('slack')) {
        return room;
      }
    }
    return null;
  }

  // NOTE: keyword matching below is a placeholder — match it against
  // whatever your actual bridge bot replies with in your setup.
  void _listenForBridgeReply(Room room) {
    _activeSub?.cancel();

    _activeSub = widget.client.onTimelineEvent.stream.listen((Event event) {
      if (event.roomId != room.id || event.senderId == widget.client.userID) {
        return;
      }

      final body = (event.content['body'] as String? ?? '').trim();
      if (body.isEmpty) return;

      final lower = body.toLowerCase();

      if (lower.contains('logged in') || lower.contains('successfully')) {
        setState(() {
          _sheetLoading = false;
          _connected = true;
        });
        widget.onConnected?.call();
        return;
      }

      if (lower.contains('invalid') ||
          lower.contains('expired') ||
          lower.contains('error')) {
        setState(() {
          _sheetLoading = false;
          _sheetError =
              "Login failed. Please check your token and cookie and try again.";
        });
      }
    });

    Future.delayed(const Duration(seconds: 60), () {
      if (mounted && _sheetLoading) {
        setState(() {
          _sheetLoading = false;
          _sheetError = "Timed out waiting for bot to respond.";
        });
      }
    });
  }

  Future<void> _executeLogin() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final token = _tokenController.text.trim();
    final cookie = _cookieController.text.trim();

    if (token.isEmpty || cookie.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter both your token and cookie.'),
            backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() {
      _sheetError = null;
      _sheetLoading = true;
    });

    try {
      final activeRoom = _findSlackRoom();

      if (activeRoom == null) {
        setState(() {
          _sheetError = "Slack room not found on this account.";
          _sheetLoading = false;
        });
        return;
      }

      _listenForBridgeReply(activeRoom);

      debugPrint("==> ME: !sl cancel");
      await activeRoom.sendTextEvent('!sl cancel');

      await Future.delayed(const Duration(seconds: 1));

      debugPrint("==> ME: !sl login-token ******** ********");
      await activeRoom.sendTextEvent('!sl login-token $token $cookie');
    } catch (e) {
      debugPrint("ERROR: $e");
      setState(() {
        _sheetLoading = false;
        _sheetError = "Connection failed. Please try again.";
      });
    }
  }

  // ─── UI HELPER WIDGETS ────────────────────────────────────────────────────

  Widget _buildTopRightCloseButton() {
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onTap: () {
          _activeSub?.cancel();
          Navigator.pop(context);
        },
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
              color: Colors.grey.shade200, shape: BoxShape.circle),
          child:
              const Icon(Icons.close_rounded, color: Colors.black87, size: 16),
        ),
      ),
    );
  }

  Widget _buildConnectionIconsHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
              color: const Color(0xFF0052FF),
              borderRadius: BorderRadius.circular(16)),
          child:
              Image.asset('assets/images/app_icon.png', width: 56, height: 56),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0),
          child: Icon(Icons.sync_alt_rounded, color: Colors.grey, size: 32),
        ),
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: kSlackAubergine.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16)),
          // Swap for Image.asset('assets/images/slack.png', width: 56,
          // height: 56) if/when you add a real Slack logo asset.
          child:
              const Icon(Icons.tag_rounded, color: kSlackAubergine, size: 36),
        ),
      ],
    );
  }

  Widget _buildPillButton(String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0052FF),
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 54),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          elevation: 0),
      child: Text(label,
          style:
              GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
  }) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: GoogleFonts.poppins(color: Colors.black87, fontSize: 16),
        decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.poppins(color: Colors.grey.shade500),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 18)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTopRightCloseButton(),

            const SizedBox(height: 12),

            _buildConnectionIconsHeader(),

            const SizedBox(height: 32),

            // 🟢 STATE 1: ERROR

            if (_sheetError != null) ...[
              const Icon(Icons.error_outline_rounded,
                  color: Colors.redAccent, size: 56),
              const SizedBox(height: 16),
              Text('Connection Failed',
                  style: GoogleFonts.poppins(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 18)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.redAccent.withOpacity(0.3))),
                child: Text(_sheetError!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        color: Colors.redAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ),
              const SizedBox(height: 32),
              _buildPillButton(
                  "Try Again", () => setState(() => _sheetError = null)),
            ]

            // 🟢 STATE 2: LOADING

            else if (_sheetLoading) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32.0),
                child: SlackRadarAnimation(),
              ),
              Text('Connecting to Slack...',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      color: Colors.grey.shade600, fontSize: 14)),
              const SizedBox(height: 24),
            ]

            // 🟢 STATE 3: SUCCESS

            else if (_connected) ...[
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF25D366), size: 56),
              const SizedBox(height: 16),
              Text('Slack Connected',
                  style: GoogleFonts.poppins(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 18)),
              const SizedBox(height: 8),
              Text(
                  'Your workspace channels and DMs will start syncing shortly.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      color: Colors.grey.shade500, fontSize: 13)),
              const SizedBox(height: 32),
              _buildPillButton("Done", () => Navigator.pop(context)),
            ]

            // 🟢 STATE 4: INITIAL INPUT

            else ...[
              Text('Connect your Slack workspace',
                  textAlign: TextAlign.center,
                  style:
                      GoogleFonts.poppins(color: Colors.black87, fontSize: 15)),
              const SizedBox(height: 8),
              Text(
                  'Paste your Slack session token (xoxc-...) and "d" cookie. These are sent directly to the bridge and are not stored by Allora.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      color: Colors.grey.shade400, fontSize: 12)),
              const SizedBox(height: 24),
              _buildTextField(
                controller: _tokenController,
                hint: 'Slack token (xoxc-...)',
                obscure: _obscureFields,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _cookieController,
                hint: 'Slack "d" cookie',
                obscure: _obscureFields,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () =>
                      setState(() => _obscureFields = !_obscureFields),
                  child: Text(_obscureFields ? 'Show values' : 'Hide values',
                      style: GoogleFonts.poppins(
                          color: kSlackAubergine,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 16),
              _buildPillButton("Continue", _executeLogin),
            ]
          ],
        ),
      ),
    );
  }
}

// ─── CUSTOM RADAR ANIMATION FOR LOADING STATE ────────────────────────────────

class SlackRadarAnimation extends StatefulWidget {
  const SlackRadarAnimation({super.key});

  @override
  State<SlackRadarAnimation> createState() => _SlackRadarAnimationState();
}

class _SlackRadarAnimationState extends State<SlackRadarAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      width: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ...List.generate(3, (index) {
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final double value = (_controller.value + (index / 3)) % 1.0;

                return Opacity(
                  opacity: (1.0 - value).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 1.0 + (value * 2.5),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: kSlackAubergine.withOpacity(0.5),
                              width: 2)),
                    ),
                  ),
                );
              },
            );
          }),
          Container(
            width: 50,
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
              BoxShadow(
                  color: kSlackAubergine.withOpacity(0.3),
                  blurRadius: 10,
                  spreadRadius: 2)
            ]),
            child:
                const Icon(Icons.tag_rounded, color: kSlackAubergine, size: 32),
          ),
        ],
      ),
    );
  }
}
