// ignore_for_file: unnecessary_non_null_assertion, unused_element, curly_braces_in_flow_control_structures, unused_import, unnecessary_string_interpolations, use_build_context_synchronously, deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart' hide Visibility;
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';

// ─── BRAND COLOR ──────────────────────────────────────────────────────────────

const Color kMessengerBlue = Color(0xFF006FFF);

// ─── PUBLIC ENTRY POINT ───────────────────────────────────────────────────────

/// Opens the Facebook Messenger "connect account" bottom sheet.
///
/// [onConnected] fires once the bridge bot confirms a successful login.
void showMessengerConnectSheet({
  required BuildContext context,
  required Client client,
  VoidCallback? onConnected,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => MessengerConnectSheet(
      client: client,
      onConnected: onConnected,
    ),
  );
}

// ─── THE CONNECT SHEET ────────────────────────────────────────────────────────

/// Email/password entry -> optional two-factor checkpoint code -> success/error.
class MessengerConnectSheet extends StatefulWidget {
  final Client client;
  final VoidCallback? onConnected;

  const MessengerConnectSheet({
    super.key,
    required this.client,
    this.onConnected,
  });

  @override
  State<MessengerConnectSheet> createState() => _MessengerConnectSheetState();
}

class _MessengerConnectSheetState extends State<MessengerConnectSheet> {
  final TextEditingController _emailController = TextEditingController();
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
    _emailController.dispose();
    _passwordController.dispose();
    _twoFactorController.dispose();
    _activeSub?.cancel();
    super.dispose();
  }

  Room? _findMessengerRoom() {
    for (final room in widget.client.rooms) {
      final name = room.displayname.toLowerCase();
      if (name.contains('messenger') || name.contains('facebook')) {
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
          _needsTwoFactor = false;
          _connected = true;
        });
        widget.onConnected?.call();
        return;
      }

      if (lower.contains('two-factor') ||
          lower.contains('checkpoint') ||
          lower.contains('verification code')) {
        setState(() {
          _sheetLoading = false;
          _needsTwoFactor = true;
        });
        return;
      }

      if (lower.contains('incorrect') ||
          lower.contains('invalid') ||
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

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter your email/phone and password.'),
            backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() {
      _sheetError = null;
      _sheetLoading = true;
    });

    try {
      final activeRoom = _findMessengerRoom();

      if (activeRoom == null) {
        setState(() {
          _sheetError = "Messenger room not found on this account.";
          _sheetLoading = false;
        });
        return;
      }

      _listenForBridgeReply(activeRoom);

      debugPrint("==> ME: !fb cancel");
      await activeRoom.sendTextEvent('!fb cancel');

      await Future.delayed(const Duration(seconds: 1));

      debugPrint("==> ME: !fb login $email ********");
      await activeRoom.sendTextEvent('!fb login $email $password');
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
      final activeRoom = _findMessengerRoom();

      if (activeRoom == null) {
        setState(() {
          _sheetError = "Messenger room not found on this account.";
          _sheetLoading = false;
        });
        return;
      }

      _listenForBridgeReply(activeRoom);

      debugPrint("==> ME: !fb 2fa $code");
      await activeRoom.sendTextEvent('!fb 2fa $code');
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
                color:
                    const Color.fromARGB(255, 255, 255, 255).withOpacity(0.12),
                borderRadius: BorderRadius.circular(16)),
            // Swap for Image.asset('assets/images/messenger.png', width: 56,
            // height: 56) if/when you add a real Messenger logo asset.
            child: Image.asset('assets/images/messenger.png',
                width: 56, height: 56)),
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
                child: MessengerRadarAnimation(),
              ),
              Text('Connecting to Messenger...',
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
              Text('Messenger Connected',
                  style: GoogleFonts.poppins(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 18)),
              const SizedBox(height: 8),
              Text('Your Messenger chats will start syncing shortly.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      color: Colors.grey.shade500, fontSize: 13)),
              const SizedBox(height: 32),
              _buildPillButton("Done", () => Navigator.pop(context)),
            ]

            // 🟢 STATE 4: TWO-FACTOR CODE

            else if (_needsTwoFactor) ...[
              Text('Enter the verification code Facebook sent you',
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
              Text('Sign in with your Facebook email/phone and password',
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
                controller: _emailController,
                hint: 'Email or phone number',
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

class MessengerRadarAnimation extends StatefulWidget {
  const MessengerRadarAnimation({super.key});

  @override
  State<MessengerRadarAnimation> createState() =>
      _MessengerRadarAnimationState();
}

class _MessengerRadarAnimationState extends State<MessengerRadarAnimation>
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
                              color: kMessengerBlue.withOpacity(0.5),
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
                    color: kMessengerBlue.withOpacity(0.3),
                    blurRadius: 10,
                    spreadRadius: 2)
              ]),
              child: Image.asset('assets/images/messenger.png',
                  width: 36, height: 36)),
        ],
      ),
    );
  }
}
