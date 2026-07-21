import 'package:flutter/material.dart';

/// Global messenger so background jobs (disconnects, syncs) can surface
/// toasts after the originating screen/sheet is long gone.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void showGlobalToast(String message) {
  final messenger = rootScaffoldMessengerKey.currentState;
  if (messenger == null) return;
  messenger.showSnackBar(SnackBar(
    content: Text(message),
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 3),
  ));
}
