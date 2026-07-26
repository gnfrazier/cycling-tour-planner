import 'package:client/domain/route.dart';
import 'package:client/domain/theme.dart';
import 'package:client/domain/trip.dart';
import 'package:client/presentation/widgets/day_weighting_panel.dart';
import 'package:client/state/routing_providers.dart';
import 'package:client/state/trip_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_routing_client.dart';

TripResult _trip() => TripResult(
      id: 'trip-1',
      waypoints: const [Waypoint(coord: LatLon(35.68, -82.01)), Waypoint(coord: LatLon(35.7, -82.05))],
      theme: RouteTheme.flattest,
      riderBand: RiderBand.solo,
      startDate: DateTime(2026, 9, 12),
      days: const [
        TripDay(index: 0, coords: [LatLon(35.68, -82.01), LatLon(35.7, -82.05)], distanceM: 48000, elevationGainM: 300),
      ],
      totalDistanceM: 48000,
      totalElevationGainM: 300,
    );

Future<ProviderContainer> _pumpPanelWithDaySelected(WidgetTester tester, {bool withProposal = false}) async {
  final trip = _trip();
  final container = ProviderContainer(
    overrides: [routingClientProvider.overrideWithValue(FakeRoutingClient(tripToReturn: trip))],
  );
  addTearDown(container.dispose);
  container.read(waypointsProvider.notifier).add(const LatLon(35.68, -82.01));
  container.read(waypointsProvider.notifier).add(const LatLon(35.7, -82.05));
  await container.read(tripGenerationProvider.notifier).generate();
  container.read(selectedDayIndexProvider.notifier).state = 0;
  if (withProposal) {
    await container.read(dayAlternativeProvider.notifier).propose();
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DayWeightingPanel()))),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('renders nothing when no day is selected', (tester) async {
    final container = ProviderContainer(
      overrides: [routingClientProvider.overrideWithValue(FakeRoutingClient())],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: DayWeightingPanel())),
      ),
    );

    expect(find.text('Propose alternative'), findsNothing);
  });

  testWidgets('shows a per-format export button for the selected day', (tester) async {
    await _pumpPanelWithDaySelected(tester);

    expect(find.text('Export GPX'), findsOneWidget);
    expect(find.text('Export TCX'), findsOneWidget);
    expect(find.text('Export FIT'), findsOneWidget);
  });

  testWidgets('tapping "Propose alternative" shows the compare panel', (tester) async {
    final container = await _pumpPanelWithDaySelected(tester);

    expect(find.text('Compare segment'), findsNothing);

    await tester.tap(find.text('Propose alternative'));
    await tester.pumpAndSettle();

    expect(find.text('Compare segment'), findsOneWidget);
    expect(container.read(dayAlternativeProvider).value, isNotNull);
    // Wireframe 10a parity: legend, and a full stat table including traffic
    // (not just distance/climbing/surface) with a delta callout.
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('Proposed'), findsOneWidget);
    expect(find.text('Traffic'), findsOneWidget);
    expect(find.textContaining('+2.0 km'), findsOneWidget);
  });

  testWidgets('"Take proposed" applies the alternative and closes the compare panel', (tester) async {
    final container = await _pumpPanelWithDaySelected(tester, withProposal: true);
    expect(find.text('Compare segment'), findsOneWidget);
    final proposedDistance = container.read(dayAlternativeProvider).value!.alternative.distanceM;

    final takeButton = find.text('Take proposed →');
    await tester.ensureVisible(takeButton);
    await tester.pumpAndSettle();
    await tester.tap(takeButton);
    await tester.pumpAndSettle();

    expect(find.text('Compare segment'), findsNothing);
    expect(container.read(tripGenerationProvider).value!.days[0].distanceM, proposedDistance);
  });

  testWidgets('"Keep current" discards the proposal without touching the trip', (tester) async {
    final container = await _pumpPanelWithDaySelected(tester, withProposal: true);

    final keepButton = find.text('Keep current');
    await tester.ensureVisible(keepButton);
    await tester.pumpAndSettle();
    await tester.tap(keepButton);
    await tester.pumpAndSettle();

    expect(find.text('Compare segment'), findsNothing);
    expect(container.read(tripGenerationProvider).value!.days[0].distanceM, 48000.0);
  });

  testWidgets('"Save as variant" records it without discarding the working proposal', (tester) async {
    final container = await _pumpPanelWithDaySelected(tester, withProposal: true);

    final saveButton = find.text('Save as variant');
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(container.read(savedVariantsProvider)[0], hasLength(1));
    // The comparison stays open — nothing was applied or discarded.
    expect(find.text('Compare segment'), findsOneWidget);
  });
}
