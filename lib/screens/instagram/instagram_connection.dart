// ignore_for_file: unnecessary_non_null_assertion, unused_element, curly_braces_in_flow_control_structures, unused_import, unnecessary_string_interpolations, use_build_context_synchronously, deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart' hide Visibility;
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

// ─── BRAND COLORS ────────────────────────────────────────────────────────────
// Named distinctly from whatsapp_connection.dart's kBeeperBlue/kWaGreen so
// both files can be imported side by side without identifier clashes.

const Color kAlloraBlue = Color(0xFF0052FF);
const Color kInstagramPink = Color(0xFFE1306C);

// ─── PUBLIC ENTRY POINT ───────────────────────────────────────────────────────

/// Opens the Instagram "connect account" bottom sheet.
///
/// Call this from any screen that owns a [Client] instance.
///
/// [onConnected] fires once the bridge bot confirms a successful login, so
/// the calling screen can react (refresh state, show its own confirmation,
/// etc.) without this file needing to know about it.
void showInstagramConnectSheet({
  required BuildContext context,
  required Client client,
  VoidCallback? onConnected,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => InstagramConnectSheet(
      client: client,
      onConnected: onConnected,
    ),
  );
}

// ─── THE CONNECT SHEET ────────────────────────────────────────────────────────

/// The full Instagram linking flow: username/password entry -> optional
/// two-factor code -> success/error states. All Instagram state lives
/// inside this widget.
class InstagramConnectSheet extends StatefulWidget {
  final Client client;
  final VoidCallback? onConnected;

  const InstagramConnectSheet({
    super.key,
    required this.client,
    this.onConnected,
  });

  @override
  State<InstagramConnectSheet> createState() => _InstagramConnectSheetState();
}

class _InstagramConnectSheetState extends State<InstagramConnectSheet> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _twoFactorController = TextEditingController();

  StreamSubscription<Event>? _activeSub;

  bool _sheetLoading = false;
  String? _sheetError;
  bool _needsTwoFactor = false;
  bool _connected = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _twoFactorController.dispose();
    _activeSub?.cancel();
    super.dispose();
  }

  Room? _findInstagramRoom() {
    for (final room in widget.client.rooms) {
      if (room.displayname.toLowerCase().contains('instagram')) {
        return room;
      }
    }
    return null;
  }

  // Listens for the bridge bot's reply and routes it to the right state.
  // NOTE: the keyword matching below ("logged in", "two-factor", etc.) is a
  // placeholder — match it against whatever your actual mautrix-instagram
  // bot replies with in your setup.
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
          _needsTwoFactor = false;
          _connected = true;
        });

        widget.onConnected?.call();
        return;
      }

      if (lower.contains('two-factor') ||
          lower.contains('2fa') ||
          lower.contains('verification code')) {
        setState(() {
          _sheetLoading = false;
          _needsTwoFactor = true;
        });
        return;
      }

      if (lower.contains('incorrect') ||
          lower.contains('invalid') ||
          lower.contains('checkpoint') ||
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
      final activeRoom = _findInstagramRoom();

      if (activeRoom == null) {
        setState(() {
          _sheetError = "Instagram room not found on this account.";
          _sheetLoading = false;
        });
        return;
      }

      _listenForBridgeReply(activeRoom);

      debugPrint("==> ME: !ig cancel");
      await activeRoom.sendTextEvent('!ig cancel');

      await Future.delayed(const Duration(seconds: 1));

      debugPrint("==> ME: !ig login $username ********");
      await activeRoom.sendTextEvent('!ig login $username $password');
    } catch (e) {
      debugPrint("ERROR: $e");
      setState(() {
        _sheetLoading = false;
        _sheetError = "Connection failed. Please try again.";
      });
    }
  }

  Future<void> _submitTwoFactorCode() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final code = _twoFactorController.text.trim();

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
      final activeRoom = _findInstagramRoom();

      if (activeRoom == null) {
        setState(() {
          _sheetError = "Instagram room not found on this account.";
          _sheetLoading = false;
        });
        return;
      }

      _listenForBridgeReply(activeRoom);

      debugPrint("==> ME: !ig 2fa $code");
      await activeRoom.sendTextEvent('!ig 2fa $code');
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
              color: kAlloraBlue, borderRadius: BorderRadius.circular(16)),
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
              color: kInstagramPink.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16)),
          // Swap this Icon for an Image.asset('assets/images/instagram.png',
          // width: 56, height: 56) the same way app_icon.png is used above,
          // if/when you add a real Instagram logo asset.
          child: const Icon(Icons.camera_alt_rounded,
              color: kInstagramPink, size: 36),
        ),
      ],
    );
  }

  Widget _buildPillButton(String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
          backgroundColor: kAlloraBlue,
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
                child: InstagramRadarAnimation(),
              ),
              Text('Connecting to Instagram...',
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
              Text('Instagram Connected',
                  style: GoogleFonts.poppins(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 18)),
              const SizedBox(height: 8),
              Text('Your Instagram DMs will start syncing shortly.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      color: Colors.grey.shade500, fontSize: 13)),
              const SizedBox(height: 32),
              _buildPillButton("Done", () => Navigator.pop(context)),
            ]

            // 🟢 STATE 4: TWO-FACTOR CODE

            else if (_needsTwoFactor) ...[
              Text('Enter the verification code Instagram sent you',
                  textAlign: TextAlign.center,
                  style:
                      GoogleFonts.poppins(color: Colors.black87, fontSize: 15)),
              const SizedBox(height: 24),
              _buildTextField(
                controller: _twoFactorController,
                hint: '6-digit code',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 32),
              _buildPillButton("Verify", _submitTwoFactorCode),
            ]

            // 🟢 STATE 5: INITIAL INPUT

            else ...[
              Text('Sign in with your Instagram username and password',
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
                hint: 'Username',
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

class InstagramRadarAnimation extends StatefulWidget {
  const InstagramRadarAnimation({super.key});

  @override
  State<InstagramRadarAnimation> createState() =>
      _InstagramRadarAnimationState();
}

class _InstagramRadarAnimationState extends State<InstagramRadarAnimation>
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
                              color: kInstagramPink.withOpacity(0.5),
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
                  color: kInstagramPink.withOpacity(0.3),
                  blurRadius: 10,
                  spreadRadius: 2)
            ]),
            child: const Icon(Icons.camera_alt_rounded,
                color: kInstagramPink, size: 32),
          ),
        ],
      ),
    );
  }
}
