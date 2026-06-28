import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'otp_screen.dart';

class SignupScreen extends StatefulWidget {
  final Client client;
  const SignupScreen({super.key, required this.client});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  String?
      _errorMessage; // Used to display live validation errors under the button

  // PROFESSIONAL PASSWORD VALIDATOR
  bool _isPasswordStrong(String password) {
    if (password.length < 8) return false;
    // Checks if the password contains AT LEAST one letter and one number
    final hasLetter = RegExp(r'[a-zA-Z]').hasMatch(password);
    final hasNumber = RegExp(r'[0-9]').hasMatch(password);
    return hasLetter && hasNumber;
  }

  Future<void> _createAccount() async {
    // Clear previous errors
    setState(() => _errorMessage = null);

    // 1. Username Validation
    if (_usernameController.text.trim().length < 3) {
      setState(
          () => _errorMessage = 'Username must be at least 3 characters long.');
      return;
    }

    // 2. Email Validation
    if (!_emailController.text.contains('@')) {
      setState(() => _errorMessage = 'Please enter a valid email address.');
      return;
    }

    // 3. Password Strength Validation
    if (!_isPasswordStrong(_passwordController.text)) {
      setState(() => _errorMessage =
          'Password must be at least 8 characters and contain both letters and numbers.');
      return;
    }

    // 4. Password Match Validation
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(
          () => _errorMessage = 'Passwords do not match. Please retype them.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 5. Create the user in Supabase
      await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        data: {
          'username': _usernameController.text.trim(),
          'phone': _phoneController.text.trim(),
        },
      );

      if (mounted) {
        setState(() => _isLoading = false);
        // 6. Route to OTP screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OtpScreen(
              client: widget.client,
              contact: _emailController.text.trim(),
              otpType: OtpType.signup,
            ),
          ),
        );
      }
    } on AuthException catch (e) {
      setState(() {
        _isLoading = false;
        // If Supabase rejects the email (e.g. already in use), it shows here
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'An unexpected network error occurred.';
      });
    }
  }

  Widget _buildTextField(String hint, TextEditingController controller,
      {bool isPassword = false, TextInputType type = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Container(
        decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(16)),
        child: TextField(
          controller: controller,
          obscureText: isPassword,
          keyboardType: type,
          decoration: InputDecoration(
            hintText: hint,
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Create Account',
                style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent.shade700),
              ),
              const SizedBox(height: 32),

              _buildTextField('Username', _usernameController),
              _buildTextField('Email Address', _emailController,
                  type: TextInputType.emailAddress),
              _buildTextField('Phone Number (+1...)', _phoneController,
                  type: TextInputType.phone),
              _buildTextField('Password', _passwordController,
                  isPassword: true),
              _buildTextField('Confirm Password', _confirmPasswordController,
                  isPassword: true),

              // LIVE ERROR MESSAGE DISPLAY
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                        color: Colors.red,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                ),

              const SizedBox(height: 8),

              if (_isLoading)
                const CircularProgressIndicator()
              else
                ElevatedButton(
                  onPressed: _createAccount,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent.shade700,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: const Text('Sign Up',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
