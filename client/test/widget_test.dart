import 'package:client/main.dart';
import 'package:client/state/routing_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_routing_client.dart';

void main() {
  testWidgets('app launches and shows the planner once the backend is ready', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          routingClientProvider.overrideWithValue(FakeRoutingClient()),
          backendReadyProvider.overrideWith((ref) async {}),
        ],
        child: const CycleTourPlannerApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cycle Tour Planner'), findsOneWidget);
    expect(find.text('Generate route'), findsOneWidget);
  });

  testWidgets('app follows the OS light/dark setting instead of a single fixed theme', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          routingClientProvider.overrideWithValue(FakeRoutingClient()),
          backendReadyProvider.overrideWith((ref) async {}),
        ],
        child: const CycleTourPlannerApp(),
      ),
    );

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.darkTheme, isNotNull);
    expect(app.themeMode, ThemeMode.system);
  });
}
