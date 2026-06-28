import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'email_screen.dart';
import 'signup_screen.dart'; // Make sure this points to your new signup screen

class WelcomeScreen extends StatelessWidget {
  final Client client;
  const WelcomeScreen({super.key, required this.client});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // 1. THE HERO IMAGE
          Expanded(
            flex: 55,
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage(
                      'assets/images/allora_hero.png'), // Ensure your image path is correct
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                ),
              ),
            ),
          ),

          // 2. THE BOTTOM CONTROLS
          Expanded(
            flex: 45,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // --- CONTINUE WITH EMAIL BUTTON ---
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EmailScreen(client: client),
                        ),
                      );
                    },
                    icon: const Icon(Icons.email, color: Colors.white),
                    label: const Text(
                      'Continue with Email',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent.shade700,
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 0,
                    ),
                  ),

                  const SizedBox(
                      height: 32), // Adjusted spacing for a cleaner look

                  // --- CREATE ACCOUNT TEXT ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Don't have an account? ",
                        style: TextStyle(color: Colors.grey),
                      ),
                      GestureDetector(
                        onTap: () {
                          // Routes directly to the Registration Form
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SignupScreen(client: client),
                            ),
                          );
                        },
                        child: Text(
                          "Create Account",
                          style: TextStyle(
                            color: Colors.blueAccent.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // --- LEGAL TEXT ---
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 13,
                        height: 1.5,
                      ),
                      children: [
                        const TextSpan(
                          text: 'By continuing, you agree to our ',
                        ),
                        TextSpan(
                          text: 'terms of use',
                          style: TextStyle(
                            color: Colors.blueAccent.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const TextSpan(text: ' and have read our '),
                        TextSpan(
                          text: 'privacy policy',
                          style: TextStyle(
                            color: Colors.blueAccent.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                  const SafeArea(child: SizedBox.shrink()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
