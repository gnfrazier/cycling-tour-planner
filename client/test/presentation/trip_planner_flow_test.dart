import 'package:client/domain/route.dart';
import 'package:client/domain/theme.dart';
import 'package:client/domain/trip.dart';
import 'package:client/presentation/screens/trip_planner_screen.dart';
import 'package:client/state/routing_providers.dart';
import 'package:client/state/trip_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_routing_client.dart';

TripResult _twoDayTrip() => TripResult(
      id: 'trip-1',
      waypoints: const [
        Waypoint(coord: LatLon(35.68, -82.01), label: 'Marion, NC'),
        Waypoint(coord: LatLon(35.9, -81.7), label: 'Blowing Rock, NC'),
      ],
      theme: RouteTheme.flattest,
      riderBand: RiderBand.solo,
      startDate: DateTime(2026, 9, 12),
      days: const [
        TripDay(index: 0, coords: [LatLon(35.68, -82.01), LatLon(35.8, -81.85)], distanceM: 48000, elevationGainM: 300),
        TripDay(index: 1, coords: [LatLon(35.8, -81.85), LatLon(35.9, -81.7)], distanceM: 52000, elevationGainM: 400),
      ],
      totalDistanceM: 100000,
      totalElevationGainM: 700,
    );

void main() {
  testWidgets(
    'end to end: add waypoints, generate a trip, select a day, propose an '
    'alternative, compare it, and take it',
    (tester) async {
      final trip = _twoDayTrip();
      final container = ProviderContainer(
        overrides: [routingClientProvider.overrideWithValue(FakeRoutingClient(tripToReturn: trip))],
      );
      addTearDown(container.dispose);

      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: TripPlannerScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Waypoint entry (FR10).
      await tester.enterText(find.widgetWithText(TextField, 'Add waypoint'), 'Marion, NC');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Add waypoint'), 'Blowing Rock, NC');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(container.read(waypointsProvider), hasLength(2));

      // 2. Generate the trip (FR11).
      final generateButton = find.widgetWithText(FilledButton, 'Generate trip');
      await tester.ensureVisible(generateButton);
      await tester.pumpAndSettle();
      await tester.tap(generateButton);
      await tester.pumpAndSettle();
      expect(container.read(tripGenerationProvider).value, isNotNull);

      // 3. Day timeline shows both generated days.
      expect(find.text('Day 1'), findsOneWidget);
      expect(find.text('Day 2'), findsOneWidget);

      // 4. Select day 1 — the weighting panel appears (FR13).
      await tester.tap(find.text('Day 1'));
      await tester.pumpAndSettle();
      expect(container.read(selectedDayIndexProvider), 0);
      final proposeButton = find.text('Propose alternative');
      await tester.ensureVisible(proposeButton);
      await tester.pumpAndSettle();

      // 5. Propose an alternative (FR42) and see the compare panel.
      await tester.tap(proposeButton);
      await tester.pumpAndSettle();
      expect(find.text('Compare segment'), findsOneWidget);
      final proposedDistance = container.read(dayAlternativeProvider).value!.alternative.distanceM;

      // 6. Take the proposed alternative — it becomes the trip's day 1.
      final takeButton = find.text('Take proposed →');
      await tester.ensureVisible(takeButton);
      await tester.pumpAndSettle();
      await tester.tap(takeButton);
      await tester.pumpAndSettle();

      expect(find.text('Compare segment'), findsNothing);
      expect(container.read(tripGenerationProvider).value!.days[0].distanceM, proposedDistance);
    },
  );
}
