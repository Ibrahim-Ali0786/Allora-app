// ignore_for_file: unnecessary_non_null_assertion, unused_element, curly_braces_in_flow_control_structures, unused_import, unnecessary_string_interpolations, use_build_context_synchronously, deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart' hide Visibility;
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

// ─── BRAND COLOR ──────────────────────────────────────────────────────────────

const Color kTwitterBlue = Color(0xFF1DA1F2);

// ─── PUBLIC ENTRY POINT ───────────────────────────────────────────────────────

/// Opens the X (Twitter) "connect account" bottom sheet.
///
/// [onConnected] fires once the bridge bot confirms a successful login.
void showTwitterConnectSheet({
  required BuildContext context,
  required Client client,
  VoidCallback? onConnected,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => TwitterConnectSheet(
      client: client,
      onConnected: onConnected,
    ),
  );
}

// ─── THE CONNECT SHEET ────────────────────────────────────────────────────────

/// Username/password entry -> optional email verification code -> success/error.
class TwitterConnectSheet extends StatefulWidget {
  final Client client;
  final VoidCallback? onConnected;

  const TwitterConnectSheet({
    super.key,
    required this.client,
    this.onConnected,
  });

  @override
  State<TwitterConnectSheet> createState() => _TwitterConnectSheetState();
}

class _TwitterConnectSheetState extends State<TwitterConnectSheet> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _verifyController = TextEditingController();

  StreamSubscription<Event>? _activeSub;

  bool _sheetLoading = false;
  String? _sheetError;
  bool _needsVerification = false;
  bool _connected = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _verifyController.dispose();
    _activeSub?.cancel();
    super.dispose();
  }

  Room? _findTwitterRoom() {
    for (final room in widget.client.rooms) {
      final name = room.displayname.toLowerCase();
      if (name.contains('twitter') || name.contains('x (twitter)')) {
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
          _needsVerification = false;
          _connected = true;
        });
        widget.onConnected?.call();
        return;
      }

      if (lower.contains('verification code') ||
          lower.contains('confirmation code') ||
          lower.contains('check your email')) {
        setState(() {
          _sheetLoading = false;
          _needsVerification = true;
        });
        return;
      }

      if (lower.contains('incorrect') ||
          lower.contains('invalid') ||
          lower.contains('locked') ||
          lower.contains('error')) {
        setState(() {
          _sheetLoading = false;
          _sheetError =
              "Login failed. Please check your details and try again.";
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

    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter your username and password.'),
            backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() {
      _sheetError = null;
      _sheetLoading = true;
    });

    try {
      final activeRoom = _findTwitterRoom();

      if (activeRoom == null) {
        setState(() {
          _sheetError = "X (Twitter) room not found on this account.";
          _sheetLoading = false;
        });
        return;
      }

      _listenForBridgeReply(activeRoom);

      debugPrint("==> ME: !x cancel");
      await activeRoom.sendTextEvent('!x cancel');

      await Future.delayed(const Duration(seconds: 1));

      debugPrint("==> ME: !x login $username ********");
      await activeRoom.sendTextEvent('!x login $username $password');
    } catch (e) {
      debugPrint("ERROR: $e");
      setState(() {
        _sheetLoading = false;
        _sheetError = "Connection failed. Please try again.";
      });
    }
  }

  Future<void> _submitVerificationCode() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final code = _verifyController.text.trim();

    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter the verification code.'),
            backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() {
      _sheetError = null;
      _sheetLoading = true;
    });

    try {
      final activeRoom = _findTwitterRoom();

      if (activeRoom == null) {
        setState(() {
          _sheetError = "X (Twitter) room not found on this account.";
          _sheetLoading = false;
        });
        return;
      }

      _listenForBridgeReply(activeRoom);

      debugPrint("==> ME: !x verify $code");
      await activeRoom.sendTextEvent('!x verify $code');
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
          // Replaced the placeholder icon with the actual X asset
          child: Image.asset(
            'assets/images/x.png',
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: GoogleFonts.poppins(color: Colors.black87, fontSize: 16),
        decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.poppins(color: Colors.grey.shade500),
            border: InputBorder.none,
            suffixIcon: suffix,
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
                child: TwitterRadarAnimation(),
              ),
              Text('Connecting to X...',
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
              Text('X Connected',
                  style: GoogleFonts.poppins(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 18)),
              const SizedBox(height: 8),
              Text('Your DMs will start syncing shortly.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      color: Colors.grey.shade500, fontSize: 13)),
              const SizedBox(height: 32),
              _buildPillButton("Done", () => Navigator.pop(context)),
            ]

            // 🟢 STATE 4: VERIFICATION CODE

            else if (_needsVerification) ...[
              Text('Enter the verification code sent to your email',
                  textAlign: TextAlign.center,
                  style:
                      GoogleFonts.poppins(color: Colors.black87, fontSize: 15)),
              const SizedBox(height: 24),
              _buildTextField(
                controller: _verifyController,
                hint: 'Verification code',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 32),
              _buildPillButton("Verify", _submitVerificationCode),
            ]

            // 🟢 STATE 5: INITIAL INPUT

            else ...[
              Text('Sign in with your X (Twitter) username and password',
                  textAlign: TextAlign.center,
                  style:
                      GoogleFonts.poppins(color: Colors.black87, fontSize: 15)),
              const SizedBox(height: 8),
              Text(
                  'Your credentials are sent directly to the bridge and are not stored by Allora.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      color: Colors.grey.shade400, fontSize: 12)),
              const SizedBox(height: 24),
              _buildTextField(
                controller: _usernameController,
                hint: 'Username or email',
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _passwordController,
                hint: 'Password',
                obscure: _obscurePassword,
                suffix: IconButton(
                  icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: Colors.grey,
                      size: 20),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
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

class TwitterRadarAnimation extends StatefulWidget {
  const TwitterRadarAnimation({super.key});

  @override
  State<TwitterRadarAnimation> createState() => _TwitterRadarAnimationState();
}

class _TwitterRadarAnimationState extends State<TwitterRadarAnimation>
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
                              color: kTwitterBlue.withOpacity(0.5), width: 2)),
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
                  color: kTwitterBlue.withOpacity(0.3),
                  blurRadius: 10,
                  spreadRadius: 2)
            ]),
            // Replaced the placeholder icon with the actual X asset
            child: Image.asset('assets/images/x.png', width: 44, height: 44),
          ),
        ],
      ),
    );
  }
}
