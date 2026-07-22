import 'package:client/domain/theme.dart';
import 'package:client/presentation/widgets/theme_picker.dart';
import 'package:client/state/routing_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tapping a theme chip updates selectedThemeProvider', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ThemePicker())),
      ),
    );

    expect(container.read(selectedThemeProvider), RouteTheme.flattest);

    await tester.tap(find.text(RouteTheme.mostArt.label));
    await tester.pump();

    expect(container.read(selectedThemeProvider), RouteTheme.mostArt);
  });
}
