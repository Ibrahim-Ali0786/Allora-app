import 'package:allora/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    // Never touch fonts (asset or network) in tests.
    GoogleFonts.config.allowRuntimeFetching = false;
    AppTheme.useGoogleFonts = false;
  });

  testWidgets('themes build and expose Allora design tokens', (tester) async {
    for (final theme in [AppTheme.light(), AppTheme.dark(accentIndex: 2)]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              final c = context.allora;
              return Scaffold(
                body: Column(
                  children: [
                    Text('token check',
                        style: TextStyle(color: c.text)),
                    FilledButton(onPressed: () {}, child: const Text('ok')),
                  ],
                ),
              );
            },
          ),
        ),
      );
      expect(find.text('token check'), findsOneWidget);
      expect(theme.extension<AlloraColors>(), isNotNull);
    }
  });
}
