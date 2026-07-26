import 'package:client/domain/route.dart';
import 'package:client/domain/theme.dart';
import 'package:client/domain/trip.dart';
import 'package:client/presentation/widgets/day_timeline.dart';
import 'package:client/state/trip_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedTripNotifier extends TripGenerationNotifier {
  final TripResult trip;
  _FixedTripNotifier(this.trip);

  @override
  TripResult? build() => trip;
}

TripResult _trip({List<TripDay>? days}) => TripResult(
      id: 'trip-1',
      waypoints: const [Waypoint(coord: LatLon(35.68, -82.01)), Waypoint(coord: LatLon(35.7, -82.05))],
      theme: RouteTheme.flattest,
      riderBand: RiderBand.smallGroup,
      startDate: DateTime(2026, 9, 12),
      days: days ??
          const [
            TripDay(
              index: 0,
              coords: [LatLon(35.68, -82.01), LatLon(35.7, -82.05)],
              distanceM: 48000,
              elevationGainM: 300,
              surfaceBreakdownM: {'asphalt': 40000.0, 'gravel': 8000.0},
              trafficBreakdownM: {'residential': 30000.0, 'primary': 18000.0},
              lodgingOptions: [
                LodgingOption(name: 'Boone Inn', kind: 'hotel', coord: LatLon(35.7, -82.05), distanceFromDayEndM: 100),
              ],
              regroupCautions: ['Narrow/unpaved stretch near km 18.0-20.0.'],
            ),
            TripDay(index: 1, coords: [LatLon(35.7, -82.05), LatLon(35.9, -82.1)], distanceM: 52000, elevationGainM: 400),
          ],
      totalDistanceM: 100000,
      totalElevationGainM: 700,
    );

void main() {
  testWidgets('renders no timeline before a trip is generated', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: DayTimeline())),
      ),
    );

    expect(find.text('Day 1'), findsNothing);
  });

  testWidgets(
      'renders a card per day with distance, surface/traffic mix, lodging, and a caution badge', (tester) async {
    final container = ProviderContainer(
      overrides: [tripGenerationProvider.overrideWith(() => _FixedTripNotifier(_trip()))],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: DayTimeline())),
      ),
    );

    expect(find.text('Day 1'), findsOneWidget);
    expect(find.text('Day 2'), findsOneWidget);
    expect(find.text('48 km · ↑300 m'), findsOneWidget);
    expect(find.text('Surface: asphalt 83%, gravel 17%'), findsOneWidget);
    expect(find.text('Traffic: residential 63%, primary 38%'), findsOneWidget);
    expect(find.text('Boone Inn'), findsOneWidget);
    expect(find.text('No lodging found nearby'), findsOneWidget);
    expect(find.text('Caution'), findsOneWidget);
  });

  testWidgets('shows a variant-count badge only for days with saved variants', (tester) async {
    final trip = _trip();
    final container = ProviderContainer(
      overrides: [tripGenerationProvider.overrideWith(() => _FixedTripNotifier(trip))],
    );
    addTearDown(container.dispose);
    container.read(savedVariantsProvider.notifier).save(0, DayAlternative(current: trip.days[0], alternative: trip.days[0]));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: DayTimeline())),
      ),
    );

    expect(find.text('1 variant'), findsOneWidget);
  });

  testWidgets('tapping a day card selects it, tapping again deselects it', (tester) async {
    final container = ProviderContainer(
      overrides: [tripGenerationProvider.overrideWith(() => _FixedTripNotifier(_trip()))],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: DayTimeline())),
      ),
    );

    await tester.tap(find.text('Day 1'));
    await tester.pump();
    expect(container.read(selectedDayIndexProvider), 0);

    await tester.tap(find.text('Day 1'));
    await tester.pump();
    expect(container.read(selectedDayIndexProvider), isNull);
  });
}
