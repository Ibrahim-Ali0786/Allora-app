// ignore_for_file: unused_import, deprecated_member_use
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:workmanager/workmanager.dart';

import 'screens/auth/welcome_screen.dart';
import 'screens/chat_list_screen.dart';
import './background_wiper.dart';
import 'providers/network_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Workmanager().initialize(callbackDispatcher, isInDebugMode: kDebugMode);

  await Supabase.initialize(
    url: 'https://rwkebciwvsmavsigdrfa.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ3a2ViY2l3dnNtYXZzaWdkcmZhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA3NjI2NzksImV4cCI6MjA5NjMzODY3OX0.8E1Y4G23Lwojda86Z-R5ZSUFrwDk3MTjysWwxNpRbAM', // Use your actual key
  );

  final dir = await getApplicationSupportDirectory();
  final dbPath = join(dir.path, 'allora_matrix.db');
  final sqliteDb = await openDatabase(dbPath);
  final matrixDb =
      await MatrixSdkDatabase.init('allora_matrix', database: sqliteDb);

  final client = Client('AlloraClient', database: matrixDb);
  await client.init(newHomeserver: Uri.parse('https://matrix.allorachat.app'));

  runApp(
    ProviderScope(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
      ],
      child: AlloraApp(client: client),
    ),
  );
}

class AlloraApp extends StatefulWidget {
  final Client client;
  const AlloraApp({super.key, required this.client});

  @override
  State<AlloraApp> createState() => _AlloraAppState();
}

class _AlloraAppState extends State<AlloraApp> {
  bool _isInitializing = true;
  bool _isAuthenticated = false;
  String? _backendError;

  @override
  void initState() {
    super.initState();
    _performSecureStartupCheck();
  }

  Future<void> _performSecureStartupCheck() async {
    final session = Supabase.instance.client.auth.currentSession;

    if (session == null) {
      if (mounted) {
        setState(() {
          _isAuthenticated = false;
          _isInitializing = false;
          _backendError = null;
        });
      }
      return;
    }

    String chatUsername = session.user.id.replaceAll('-', '').toLowerCase();
    String chatPassword = "Allora_${chatUsername.substring(0, 15)}!";
    bool chatLoggedIn = widget.client.isLogged();

    if (!chatLoggedIn) {
      try {
        await widget.client.login(
          LoginType.mLoginPassword,
          identifier: AuthenticationUserIdentifier(user: chatUsername),
          password: chatPassword,
        );
        chatLoggedIn = true;
      } on MatrixException catch (e) {
        if (e.errcode == 'M_FORBIDDEN' ||
            e.errcode == 'M_USER_NOT_FOUND' ||
            e.toString().toLowerCase().contains('not found')) {
          try {
            final baseUrl = 'https://matrix.allorachat.app';
            final secret = 'AlloraSuperSecret2026';

            final nonceRes = await http
                .get(Uri.parse('$baseUrl/_synapse/admin/v1/register'));
            if (nonceRes.statusCode != 200) {
              throw Exception('Backend sync failed');
            }

            final nonce = jsonDecode(nonceRes.body)['nonce'];
            final macStr =
                '$nonce\x00$chatUsername\x00$chatPassword\x00notadmin';
            final hmacSha1 = Hmac(sha1, utf8.encode(secret));
            final digest = hmacSha1.convert(utf8.encode(macStr));
            final mac = digest.toString();

            final regRes = await http.post(
              Uri.parse('$baseUrl/_synapse/admin/v1/register'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'nonce': nonce,
                'username': chatUsername,
                'password': chatPassword,
                'mac': mac,
                'admin': false,
              }),
            );

            if (regRes.statusCode >= 200 && regRes.statusCode < 300) {
              await widget.client.login(
                LoginType.mLoginPassword,
                identifier: AuthenticationUserIdentifier(user: chatUsername),
                password: chatPassword,
              );
              chatLoggedIn = true;
            } else {
              throw Exception('Allora chat account creation rejected.');
            }
          } catch (backendErr) {
            debugPrint("Allora Backend Error: $backendErr");
            _backendError =
                "We couldn't connect you to the Allora chat servers. Please check your internet connection and try again.";
          }
        } else {
          _backendError = "Authentication failed. Please log in again.";
        }
      } catch (e) {
        _backendError = "An unexpected network error occurred.";
      }
    }

    if (mounted) {
      setState(() {
        _isInitializing = false;
        _isAuthenticated = chatLoggedIn;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Allora',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
      ),
      home: _buildCurrentScreen(),
    );
  }

  Widget _buildCurrentScreen() {
    if (_isInitializing) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body:
            Center(child: CircularProgressIndicator(color: Colors.blueAccent)),
      );
    }

    if (!_isAuthenticated && _backendError != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off_rounded,
                    color: Colors.blueAccent, size: 72),
                const SizedBox(height: 24),
                const Text('Connection Error',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87),
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Text(_backendError!,
                    style: const TextStyle(
                        fontSize: 15, color: Colors.black54, height: 1.5),
                    textAlign: TextAlign.center),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isInitializing = true;
                      _backendError = null;
                    });
                    _performSecureStartupCheck();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent.shade700,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: const Text('Retry Connection',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () async {
                    await Supabase.instance.client.auth.signOut();
                    setState(() {
                      _isInitializing = false;
                      _isAuthenticated = false;
                      _backendError = null;
                    });
                  },
                  child: const Text('Return to Welcome Screen',
                      style: TextStyle(color: Colors.grey)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // FIXED: Passed client back to ChatListScreen
    return _isAuthenticated
        ? ChatListScreen()
        : WelcomeScreen(client: widget.client);
  }
}
