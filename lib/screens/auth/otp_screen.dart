import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pinput/pinput.dart';
import '../../features/home_gate.dart';
import '../../features/privacy/app_lock.dart';

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
        setState(() => _isLoading = false);

        await _syncMatrixAccount(response.session!.user.id);

        if (mounted) {
          // Go directly to the home/connect screen with a clean 600ms fade.
          Navigator.pushAndRemoveUntil(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const LockGate(child: HomeGate()),
              transitionDuration: const Duration(milliseconds: 600),
              transitionsBuilder: (_, animation, __, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
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
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: _isLoading
                      ? Column(
                          key: const ValueKey('loading'),
                          children: [
                            const SizedBox(height: 10),
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                SizedBox(
                                  width: 80,
                                  height: 80,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.blueAccent.shade100,
                                  ),
                                ),
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.blueAccent.withValues(alpha: 0.2),
                                        blurRadius: 20,
                                        spreadRadius: 5,
                                      ),
                                    ],
                                  ),
                                  child: ClipOval(
                                    child: Image.asset('assets/images/app_icon.png', fit: BoxFit.cover),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 32),
                            Text('Authenticating securely...',
                                style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.5,
                                    color: Colors.blueAccent.shade700)),
                          ],
                        )
                      : Pinput(
                          key: const ValueKey('pinput'),
                          length: 6,
                          autofocus: true,
                          defaultPinTheme: defaultPinTheme,
                          focusedPinTheme: defaultPinTheme.copyWith(
                              decoration: BoxDecoration(
                            border: Border.all(
                                color: Colors.blueAccent.shade700, width: 2),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.white,
                          )),
                          onCompleted: _verifyOtp,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
