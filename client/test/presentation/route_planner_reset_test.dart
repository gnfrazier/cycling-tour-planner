import 'package:client/domain/route.dart';
import 'package:client/domain/theme.dart';
import 'package:client/presentation/screens/route_planner_screen.dart';
import 'package:client/state/routing_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_routing_client.dart';

void main() {
  testWidgets('Reset reverts every control to its default and clears the route', (tester) async {
    final container = ProviderContainer(
      overrides: [
        routingClientProvider.overrideWithValue(FakeRoutingClient()),
        backendReadyProvider.overrideWith((ref) async {}),
      ],
    );
    addTearDown(container.dispose);

    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: RoutePlannerScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Drive every control away from its default.
    container.read(selectedThemeProvider.notifier).state = RouteTheme.mostArt;
    container.read(selectedShapeProvider.notifier).state = RouteShape.pointToPoint;
    container.read(startPointProvider.notifier).state = const LatLon(35.6841, -82.0091);
    container.read(destinationPointProvider.notifier).state = const LatLon(35.9, -81.7);
    container.read(targetDistanceKmProvider.notifier).state = 130.0;
    await container.read(routeGenerationProvider.notifier).generate();
    await tester.pumpAndSettle();

    expect(container.read(routeGenerationProvider).value, isNotNull);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reset'));
    await tester.pumpAndSettle();

    // A confirmation dialog appears — nothing is reset yet.
    expect(find.text('Reset all controls?'), findsOneWidget);
    expect(container.read(selectedThemeProvider), RouteTheme.mostArt);

    await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
    await tester.pumpAndSettle();

    expect(container.read(selectedThemeProvider), RouteTheme.flattest);
    expect(container.read(selectedShapeProvider), RouteShape.loop);
    expect(container.read(startPointProvider), isNull);
    expect(container.read(destinationPointProvider), isNull);
    expect(container.read(targetDistanceKmProvider), 20.0);
    expect(container.read(routeGenerationProvider).value, isNull);
  });

  testWidgets('Cancelling the Reset confirmation leaves every control untouched', (tester) async {
    final container = ProviderContainer(
      overrides: [
        routingClientProvider.overrideWithValue(FakeRoutingClient()),
        backendReadyProvider.overrideWith((ref) async {}),
      ],
    );
    addTearDown(container.dispose);

    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: RoutePlannerScreen()),
      ),
    );
    await tester.pumpAndSettle();

    container.read(selectedThemeProvider.notifier).state = RouteTheme.mostArt;

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reset'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(container.read(selectedThemeProvider), RouteTheme.mostArt);
  });
}
