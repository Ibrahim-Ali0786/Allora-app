import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pinput/pinput.dart';
import '../chat_list_screen.dart';
import '../services/ai_bot_service.dart';

class OtpScreen extends StatefulWidget {
  final Client client;
  final String contact;
  final OtpType otpType;

  const OtpScreen({
    super.key,
    required this.client,
    required this.contact,
    required this.otpType,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  bool _isLoading = false;
  bool _isSuccess = false;

  Future<void> _syncMatrixAccount(String supabaseUserId) async {
    final matrixUsername = supabaseUserId.replaceAll('-', '').toLowerCase();
    final matrixPassword = "Allora_${matrixUsername.substring(0, 15)}!";

    try {
      debugPrint("Attempting to log into Matrix...");
      await widget.client.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: matrixUsername),
        password: matrixPassword,
      );
      AIBotService(widget.client).startDaemon();
      debugPrint("Matrix Login Successful!");
    } catch (e) {
      debugPrint("User not found. Generating new Matrix account...");
      try {
        await widget.client.register(
          username: matrixUsername,
          password: matrixPassword,
        );
        debugPrint("Matrix Native Registration Successful!");
      } catch (err) {
        debugPrint("Matrix Registration FAILED: $err");
      }
    }

    if (widget.client.encryption != null) {
      debugPrint("Initializing Secure E2E Encryption...");
      try {
        await Future<void>.value();
        debugPrint("Encryption bootstrap step skipped (no-op).");
      } catch (e) {
        debugPrint("Encryption already bootstrapped or skipped: $e");
      }
    }
  }

  Future<void> _verifyOtp(String pin) async {
    setState(() => _isLoading = true);

    try {
      final AuthResponse response =
          await Supabase.instance.client.auth.verifyOTP(
        type: widget.otpType,
        email: widget.otpType == OtpType.sms ? null : widget.contact,
        phone: widget.otpType == OtpType.sms ? widget.contact : null,
        token: pin,
      );

      if (response.session != null && mounted) {
        setState(() {
          _isLoading = false;
          _isSuccess = true;
        });

        await _syncMatrixAccount(response.session!.user.id);
        await Future.delayed(const Duration(seconds: 2));

        if (mounted) {
          // FIXED: ChatListScreen no longer takes a 'client' parameter
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const ChatListScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid code. Please try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultPinTheme = PinTheme(
      width: 56,
      height: 60,
      textStyle: GoogleFonts.poppins(
          fontSize: 22, color: Colors.black, fontWeight: FontWeight.w600),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.transparent),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 20.0, vertical: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (_isSuccess) ...[
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.elasticOut,
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: const Icon(Icons.check_circle,
                            color: Colors.green, size: 120),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Text('Verification Successful',
                      style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                  const SizedBox(height: 12),
                  const Text('Securing your workspace...',
                      style: TextStyle(color: Colors.grey, fontSize: 16)),
                  const SizedBox(height: 40),
                  const CircularProgressIndicator(color: Colors.green),
                ] else ...[
                  Text('Enter code',
                      style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueAccent.shade700)),
                  const SizedBox(height: 16),
                  Text('Check ${widget.contact}\nfor the 6-digit code.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 16, color: Colors.black87, height: 1.5)),
                  const SizedBox(height: 40),
                  if (_isLoading)
                    const CircularProgressIndicator()
                  else
                    Pinput(
                      length: 6,
                      autofocus: true,
                      defaultPinTheme: defaultPinTheme,
                      // FIXED: Replaced copyDecorationWith to be compatible with all pinput versions
                      focusedPinTheme: defaultPinTheme.copyWith(
                          decoration: BoxDecoration(
                        border: Border.all(
                            color: Colors.blueAccent.shade700, width: 2),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white,
                      )),
                      onCompleted: _verifyOtp,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
