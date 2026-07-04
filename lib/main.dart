import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'background_wiper.dart';
import 'core/theme/app_theme.dart';
import 'data/services/connection_manager.dart';
import 'data/services/disappearing_message_service.dart';
import 'data/services/hidden_rooms_store.dart';
import 'data/services/room_wipe_service.dart';
import 'data/services/scheduled_message_service.dart';
import 'data/settings/app_settings.dart';
import 'features/home_gate.dart';
import 'features/privacy/app_lock.dart';
import 'providers/network_provider.dart';
import 'screens/auth/welcome_screen.dart';
import 'screens/networks/network_connection_cache.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Crash-visibility in release builds: log instead of dying silently.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught: $error\n$stack');
    return true;
  };

  Workmanager().initialize(callbackDispatcher, isInDebugMode: kDebugMode);

  // Independent init work runs concurrently — this is most of the startup
  // time. The futures start immediately; we just await them in sequence.
  final prefsFuture = SharedPreferences.getInstance();
  final dirFuture = getApplicationSupportDirectory();
  final supabaseFuture = Supabase.initialize(
    url: 'https://rwkebciwvsmavsigdrfa.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ3a2ViY2l3dnNtYXZzaWdkcmZhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA3NjI2NzksImV4cCI6MjA5NjMzODY3OX0.8E1Y4G23Lwojda86Z-R5ZSUFrwDk3MTjysWwxNpRbAM',
  );
  final hydrateFuture = NetworkConnectionCache.hydrate();
  final hiddenFuture = HiddenRoomsStore.hydrate();

  final prefs = await prefsFuture;
  final Directory supportDir = await dirFuture;
  await supabaseFuture;
  await hydrateFuture;
  await hiddenFuture;

  final sqliteDb =
      await openDatabase(join(supportDir.path, 'allora_matrix.db'));
  final matrixDb =
      await MatrixSdkDatabase.init('allora_matrix', database: sqliteDb);

  final client = Client('AlloraClient', database: matrixDb);
  await client.init(newHomeserver: Uri.parse('https://matrix.allorachat.app'));

  runApp(
    ProviderScope(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        sharedPrefsProvider.overrideWithValue(prefs),
      ],
      child: AlloraApp(client: client),
    ),
  );
}

class AlloraApp extends ConsumerStatefulWidget {
  final Client client;
  const AlloraApp({super.key, required this.client});

  @override
  ConsumerState<AlloraApp> createState() => _AlloraAppState();
}

enum _StartupState { checking, unauthenticated, error, ready }

class _AlloraAppState extends ConsumerState<AlloraApp> {
  _StartupState _state = _StartupState.checking;
  String? _errorMessage;
  bool _servicesStarted = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// Ensure the Supabase session maps onto a Matrix session, registering the
  /// Matrix account on first login. Mirrors the original flow, minus the
  /// blocking UI states where nothing was actually blocking.
  Future<void> _bootstrap() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      _finish(_StartupState.unauthenticated);
      return;
    }

    if (widget.client.isLogged()) {
      _finish(_StartupState.ready);
      return;
    }

    final chatUsername = session.user.id.replaceAll('-', '').toLowerCase();
    final chatPassword = 'Allora_${chatUsername.substring(0, 15)}!';

    try {
      await widget.client.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: chatUsername),
        password: chatPassword,
      );
      _finish(_StartupState.ready);
    } on MatrixException catch (e) {
      if (e.errcode == 'M_FORBIDDEN' ||
          e.errcode == 'M_USER_NOT_FOUND' ||
          e.toString().toLowerCase().contains('not found')) {
        await _registerAndLogin(chatUsername, chatPassword);
      } else {
        _errorMessage = 'Authentication failed. Please log in again.';
        _finish(_StartupState.error);
      }
    } catch (_) {
      _errorMessage =
          'We couldn\u2019t reach the Allora servers. Check your connection '
          'and try again.';
      _finish(_StartupState.error);
    }
  }

  Future<void> _registerAndLogin(String username, String password) async {
    // Preferred path: server-side provisioning (the Synapse registration
    // secret stays on the server). See supabase/functions/allora-provision.
    try {
      final res = await Supabase.instance.client.functions
          .invoke('allora-provision', body: {'password': password})
          .timeout(const Duration(seconds: 20));
      final data = res.data;
      if (data is Map && data['ok'] == true) {
        await widget.client.login(
          LoginType.mLoginPassword,
          identifier: AuthenticationUserIdentifier(user: username),
          password: password,
        );
        _finish(_StartupState.ready);
        return;
      }
    } catch (e) {
      debugPrint('Provision function unavailable, using legacy path: $e');
    }

    // LEGACY FALLBACK — remove once allora-provision is deployed and the
    // old registration secret has been rotated on the homeserver. Shipping
    // this secret in the app is the pre-v2 behaviour kept only so existing
    // installs keep working during the migration.
    try {
      const baseUrl = 'https://matrix.allorachat.app';
      const secret = 'AlloraSuperSecret2026';

      final nonceRes = await http
          .get(Uri.parse('$baseUrl/_synapse/admin/v1/register'))
          .timeout(const Duration(seconds: 15));
      if (nonceRes.statusCode != 200) {
        throw Exception('Backend sync failed');
      }
      final nonce = jsonDecode(nonceRes.body)['nonce'];
      final macStr = '$nonce\x00$username\x00$password\x00notadmin';
      final mac =
          Hmac(sha1, utf8.encode(secret)).convert(utf8.encode(macStr));

      final regRes = await http
          .post(
            Uri.parse('$baseUrl/_synapse/admin/v1/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'nonce': nonce,
              'username': username,
              'password': password,
              'mac': mac.toString(),
              'admin': false,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (regRes.statusCode < 200 || regRes.statusCode >= 300) {
        throw Exception('Account creation rejected');
      }

      await widget.client.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: username),
        password: password,
      );
      _finish(_StartupState.ready);
    } catch (e) {
      debugPrint('Allora backend error: $e');
      _errorMessage =
          'We couldn\u2019t connect you to the Allora chat servers. Please '
          'check your internet connection and try again.';
      _finish(_StartupState.error);
    }
  }

  void _finish(_StartupState state) {
    if (!mounted) return;
    setState(() => _state = state);
    if (state == _StartupState.ready) _startServices();
  }

  /// Long-lived services; started once per authenticated run.
  void _startServices() {
    if (_servicesStarted) return;
    _servicesStarted = true;
    final client = widget.client;
    // Finish any wipe interrupted by a kill, resume scheduled sends, start
    // the disappearing-message sweeper.
    RoomWipeService.resume(client);
    ScheduledMessageService.resume(client);
    DisappearingMessageService.start(
        client, ref.read(settingsProvider.notifier));
    // Instantiate the connection manager so state flows from first frame.
    ref.read(connectionManagerProvider);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return MaterialApp(
      title: 'Allora',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: AppTheme.light(
          accentIndex: settings.accentIndex,
          highContrast: settings.highContrast,
          reduceMotion: settings.reduceMotion),
      darkTheme: AppTheme.dark(
          accentIndex: settings.accentIndex,
          amoled: settings.amoledBlack,
          highContrast: settings.highContrast,
          reduceMotion: settings.reduceMotion),
      home: _home(),
    );
  }

  Widget _home() {
    switch (_state) {
      case _StartupState.checking:
        return const _SplashScreen();
      case _StartupState.unauthenticated:
        return WelcomeScreen(client: widget.client);
      case _StartupState.error:
        return _ErrorScreen(
          message: _errorMessage ?? 'Something went wrong.',
          onRetry: () {
            setState(() => _state = _StartupState.checking);
            _bootstrap();
          },
          onSignOut: () async {
            await Supabase.instance.client.auth.signOut();
            if (mounted) setState(() => _state = _StartupState.unauthenticated);
          },
        );
      case _StartupState.ready:
        return const LockGate(child: HomeGate());
    }
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    return Scaffold(
      backgroundColor: c.canvas,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [c.accent, c.bubbleMineDeep],
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: c.accent.withValues(alpha: 0.3),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(Icons.forum_rounded,
                  color: Colors.white, size: 36),
            ),
            const SizedBox(height: 22),
            Text('Allora',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: c.text)),
            const SizedBox(height: 26),
            SizedBox(
              width: 22,
              height: 22,
              child:
                  CircularProgressIndicator(strokeWidth: 2.4, color: c.accent),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  const _ErrorScreen({
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    return Scaffold(
      backgroundColor: c.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.cloud_off_rounded, color: c.accent, size: 64),
              const SizedBox(height: 24),
              Text('Connection error',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: c.text)),
              const SizedBox(height: 12),
              Text(message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14.5, color: c.textSecondary, height: 1.5)),
              const SizedBox(height: 36),
              FilledButton(
                onPressed: onRetry,
                child: const Text('Retry connection'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: onSignOut,
                child: Text('Return to welcome screen',
                    style: TextStyle(color: c.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
