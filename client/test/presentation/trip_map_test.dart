import 'package:client/domain/route.dart';
import 'package:client/domain/theme.dart';
import 'package:client/domain/trip.dart';
import 'package:client/presentation/widgets/trip_map.dart';
import 'package:client/state/routing_providers.dart';
import 'package:client/state/trip_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_routing_client.dart';

class _FixedTripNotifier extends TripGenerationNotifier {
  final TripResult trip;
  _FixedTripNotifier(this.trip);

  @override
  TripResult? build() => trip;
}

class _FixedAlternativeNotifier extends DayAlternativeNotifier {
  final DayAlternative? alternative;
  _FixedAlternativeNotifier(this.alternative);

  @override
  DayAlternative? build() => alternative;
}

TripResult _twoDayTrip() => TripResult(
      id: 'trip-1',
      waypoints: const [
        Waypoint(coord: LatLon(35.68, -82.01)),
        Waypoint(coord: LatLon(35.7, -82.05)),
        Waypoint(coord: LatLon(35.9, -82.1)),
      ],
      theme: RouteTheme.flattest,
      riderBand: RiderBand.solo,
      startDate: DateTime(2026, 9, 12),
      days: const [
        TripDay(index: 0, coords: [LatLon(35.68, -82.01), LatLon(35.7, -82.05)], distanceM: 48000, elevationGainM: 300),
        TripDay(index: 1, coords: [LatLon(35.7, -82.05), LatLon(35.9, -82.1)], distanceM: 52000, elevationGainM: 400),
      ],
      totalDistanceM: 100000,
      totalElevationGainM: 700,
    );

void main() {
  testWidgets('TripMap renders a numbered marker per waypoint and a polyline per day', (tester) async {
    final trip = _twoDayTrip();
    final container = ProviderContainer(
      overrides: [
        routingClientProvider.overrideWithValue(FakeRoutingClient()),
        tripGenerationProvider.overrideWith(() => _FixedTripNotifier(trip)),
      ],
    );
    addTearDown(container.dispose);
    for (final wp in trip.waypoints) {
      container.read(waypointsProvider.notifier).add(wp.coord);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SizedBox(height: 400, child: TripMap()))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FlutterMap), findsOneWidget);

    // flutter_map culls markers outside the current viewport at render
    // time, so assert on what TripMap constructed rather than on rendered
    // text — the marker-count/label contract, not the camera framing.
    final markerLayer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
    expect(markerLayer.markers, hasLength(3));

    final polylineLayer = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
    expect(polylineLayer.polylines, hasLength(2));
  });

  // Driving flutter_map's onTap via a synthetic tester gesture doesn't
  // reliably fire in this widget-test harness (confirmed with a minimal
  // bare-FlutterMap repro, same as RouteMap's own unexercised map-tap path)
  // — the tap-target-resolution logic (_handleTap: fills activeWaypointSlot
  // if set, else appends) is instead covered at the provider level in
  // trip_providers_test.dart (waypointsProvider/activeWaypointSlotProvider).

  testWidgets('a pending day alternative renders a ghost (current) and bold (proposed) polyline', (tester) async {
    final trip = _twoDayTrip();
    final alt = DayAlternative(current: trip.days[0], alternative: trip.days[0]);
    final container = ProviderContainer(
      overrides: [
        routingClientProvider.overrideWithValue(FakeRoutingClient()),
        tripGenerationProvider.overrideWith(() => _FixedTripNotifier(trip)),
        dayAlternativeProvider.overrideWith(() => _FixedAlternativeNotifier(alt)),
      ],
    );
    addTearDown(container.dispose);
    container.read(selectedDayIndexProvider.notifier).state = 0;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SizedBox(height: 400, child: TripMap()))),
      ),
    );
    await tester.pumpAndSettle();

    final polylineLayer = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
    // Day 1's own polyline (not day 0, which is being compared) + ghost + bold.
    expect(polylineLayer.polylines, hasLength(3));
  });
}
