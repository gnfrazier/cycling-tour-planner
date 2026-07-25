import 'package:client/domain/trip.dart';
import 'package:client/presentation/screens/route_planner_screen.dart';
import 'package:client/presentation/screens/trip_planner_screen.dart';
import 'package:client/state/routing_providers.dart';
import 'package:client/state/trip_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_routing_client.dart';

void main() {
  testWidgets('the AppBar exposes a "Plan a multi-day trip" entry point from the single-route screen', (tester) async {
    final container = ProviderContainer(
      overrides: [
        routingClientProvider.overrideWithValue(FakeRoutingClient()),
        backendReadyProvider.overrideWith((ref) async {}),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: RoutePlannerScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Plan a multi-day trip'));
    await tester.pumpAndSettle();

    expect(find.byType(TripPlannerScreen), findsOneWidget);
  });

  testWidgets('adding two waypoints and generating shows the resulting trip summary', (tester) async {
    final container = ProviderContainer(
      overrides: [routingClientProvider.overrideWithValue(FakeRoutingClient())],
    );
    addTearDown(container.dispose);

    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TripPlannerScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Add waypoint'), 'Marion, NC');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Add waypoint'), 'Blowing Rock, NC');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(container.read(waypointsProvider), hasLength(2));

    final generateButton = find.widgetWithText(FilledButton, 'Generate trip');
    await tester.ensureVisible(generateButton);
    await tester.pumpAndSettle();
    await tester.tap(generateButton);
    await tester.pumpAndSettle();

    expect(find.textContaining('day(s)'), findsOneWidget);
    expect(container.read(tripGenerationProvider).value, isNotNull);
  });

  testWidgets('changing rider band updates riderBandProvider', (tester) async {
    final container = ProviderContainer(
      overrides: [routingClientProvider.overrideWithValue(FakeRoutingClient())],
    );
    addTearDown(container.dispose);
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TripPlannerScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(riderBandProvider), RiderBand.solo);

    await tester.tap(find.text(RiderBand.largeGroup.label));
    await tester.pumpAndSettle();

    expect(container.read(riderBandProvider), RiderBand.largeGroup);
  });
}
