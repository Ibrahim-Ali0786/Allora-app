// ignore_for_file: unnecessary_non_null_assertion, unused_element, curly_braces_in_flow_control_structures, unused_import, unnecessary_string_interpolations, use_build_context_synchronously, deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart' hide Visibility;
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

// ─── BRAND COLOR ──────────────────────────────────────────────────────────────

const Color kDiscordPurple = Color(0xFF5865F2);

// ─── PUBLIC ENTRY POINT ───────────────────────────────────────────────────────

/// Opens the Discord "connect account" bottom sheet.
///
/// Uses token-based login (the `login-token` flow most mautrix-discord
/// bridges support as an alternative to QR scanning). [onConnected] fires
/// once the bridge bot confirms a successful login.
void showDiscordConnectSheet({
  required BuildContext context,
  required Client client,
  VoidCallback? onConnected,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => DiscordConnectSheet(
      client: client,
      onConnected: onConnected,
    ),
  );
}

// ─── THE CONNECT SHEET ────────────────────────────────────────────────────────

class DiscordConnectSheet extends StatefulWidget {
  final Client client;
  final VoidCallback? onConnected;

  const DiscordConnectSheet({
    super.key,
    required this.client,
    this.onConnected,
  });

  @override
  State<DiscordConnectSheet> createState() => _DiscordConnectSheetState();
}

class _DiscordConnectSheetState extends State<DiscordConnectSheet> {
  final TextEditingController _tokenController = TextEditingController();

  StreamSubscription<Event>? _activeSub;

  bool _sheetLoading = false;
  String? _sheetError;
  bool _connected = false;
  bool _obscureToken = true;

  @override
  void dispose() {
    _tokenController.dispose();
    _activeSub?.cancel();
    super.dispose();
  }

  Room? _findDiscordRoom() {
    for (final room in widget.client.rooms) {
      if (room.displayname.toLowerCase().contains('discord')) {
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
          lower.contains('unauthorized') ||
          lower.contains('error')) {
        setState(() {
          _sheetLoading = false;
          _sheetError = "Login failed. Please check your token and try again.";
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

    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter your Discord token.'),
            backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() {
      _sheetError = null;
      _sheetLoading = true;
    });

    try {
      final activeRoom = _findDiscordRoom();

      if (activeRoom == null) {
        setState(() {
          _sheetError = "Discord room not found on this account.";
          _sheetLoading = false;
        });
        return;
      }

      _listenForBridgeReply(activeRoom);

      debugPrint("==> ME: !dc cancel");
      await activeRoom.sendTextEvent('!dc cancel');

      await Future.delayed(const Duration(seconds: 1));

      debugPrint("==> ME: !dc login-token ********");
      await activeRoom.sendTextEvent('!dc login-token $token');
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
              color: kDiscordPurple.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16)),
          // Replaced placeholder icon with custom Discord asset
          child: Image.asset(
            'assets/images/discord.png',
            width: 56,
            height: 56,
          ),
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
                child: DiscordRadarAnimation(),
              ),
              Text('Connecting to Discord...',
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
              Text('Discord Connected',
                  style: GoogleFonts.poppins(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 18)),
              const SizedBox(height: 8),
              Text('Your servers and DMs will start syncing shortly.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      color: Colors.grey.shade500, fontSize: 13)),
              const SizedBox(height: 32),
              _buildPillButton("Done", () => Navigator.pop(context)),
            ]

            // 🟢 STATE 4: INITIAL INPUT

            else ...[
              Text('Sign in to Discord with your account token',
                  textAlign: TextAlign.center,
                  style:
                      GoogleFonts.poppins(color: Colors.black87, fontSize: 15)),
              const SizedBox(height: 8),
              Text(
                  'Your token is sent directly to the bridge and is not stored by Allora.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      color: Colors.grey.shade400, fontSize: 12)),
              const SizedBox(height: 24),
              Container(
                decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(16)),
                child: TextField(
                  controller: _tokenController,
                  obscureText: _obscureToken,
                  autofocus: true,
                  style:
                      GoogleFonts.poppins(color: Colors.black87, fontSize: 16),
                  decoration: InputDecoration(
                      hintText: 'Discord token',
                      hintStyle:
                          GoogleFonts.poppins(color: Colors.grey.shade500),
                      border: InputBorder.none,
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscureToken
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: Colors.grey,
                            size: 20),
                        onPressed: () =>
                            setState(() => _obscureToken = !_obscureToken),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 18)),
                ),
              ),
              const SizedBox(height: 32),
              _buildPillButton("Continue", _executeLogin),
            ]
          ],
        ),
      ),
    );
  }
}

// ─── CUSTOM RADAR ANIMATION FOR LOADING STATE ────────────────────────────────

class DiscordRadarAnimation extends StatefulWidget {
  const DiscordRadarAnimation({super.key});

  @override
  State<DiscordRadarAnimation> createState() => _DiscordRadarAnimationState();
}

class _DiscordRadarAnimationState extends State<DiscordRadarAnimation>
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
                              color: kDiscordPurple.withOpacity(0.5),
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
                  color:
                      const Color.fromARGB(255, 255, 255, 255).withOpacity(0.3),
                  blurRadius: 10,
                  spreadRadius: 2)
            ]),
            // Replaced placeholder icon with custom Discord asset
            child:
                Image.asset('assets/images/discord.png', width: 44, height: 44),
          ),
        ],
      ),
    );
  }
}
