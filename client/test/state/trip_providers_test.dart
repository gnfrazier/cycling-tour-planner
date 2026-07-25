import 'dart:async';

import 'package:client/data/routing_client.dart';
import 'package:client/domain/route.dart';
import 'package:client/domain/theme.dart';
import 'package:client/domain/trip.dart';
import 'package:client/state/routing_providers.dart';
import 'package:client/state/trip_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_routing_client.dart';

class _DelayedTripClient extends RoutingClient {
  final Completer<TripResult> completer;
  _DelayedTripClient(this.completer) : super(baseUrl: 'http://fake');

  @override
  Future<bool> checkReady() async => true;

  @override
  Future<TripResult> generateTrip({
    required List<Waypoint> waypoints,
    required RouteTheme theme,
    required RiderBand riderBand,
    required DateTime startDate,
    double elevationGain = 0.0,
    double surfacePreference = 0.0,
    List<WeightOverrideInput> overrides = const [],
    double? maxDailyKm,
    double? maxDailyElevationM,
  }) =>
      completer.future;
}

TripResult _trip(String id) => TripResult(
      id: id,
      waypoints: const [Waypoint(coord: LatLon(35.68, -82.01)), Waypoint(coord: LatLon(35.7, -82.05))],
      theme: RouteTheme.flattest,
      riderBand: RiderBand.solo,
      startDate: DateTime(2026, 9, 12),
      days: const [
        TripDay(
          index: 0,
          coords: [LatLon(35.68, -82.01), LatLon(35.7, -82.05)],
          distanceM: 48000.0,
          elevationGainM: 365.0,
        ),
      ],
      totalDistanceM: 48000.0,
      totalElevationGainM: 365.0,
    );

void main() {
  group('waypointsProvider', () {
    test('add/updateAt/removeAt/reorder mutate the ordered list', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(waypointsProvider.notifier).add(const LatLon(35.68, -82.01));
      container.read(waypointsProvider.notifier).add(const LatLon(35.7, -82.05));
      container.read(waypointsProvider.notifier).add(const LatLon(35.9, -82.2));
      expect(container.read(waypointsProvider), hasLength(3));

      container.read(waypointsProvider.notifier).updateAt(1, const LatLon(35.75, -82.1), label: 'Boone');
      expect(container.read(waypointsProvider)[1].coord.lat, 35.75);
      expect(container.read(waypointsProvider)[1].label, 'Boone');

      // newIndex is the item's final index after removal (onReorderItem's
      // contract) — moving index 0 to index 2 in a 3-item list means it
      // ends up last, not at position 1.
      container.read(waypointsProvider.notifier).reorder(0, 2);
      expect(container.read(waypointsProvider)[2].coord.lat, 35.68);

      container.read(waypointsProvider.notifier).removeAt(0);
      expect(container.read(waypointsProvider), hasLength(2));

      container.read(waypointsProvider.notifier).clear();
      expect(container.read(waypointsProvider), isEmpty);
    });
  });

  group('TripGenerationNotifier', () {
    test('generate() with fewer than two waypoints fails without calling the client', () async {
      final container = ProviderContainer(
        overrides: [routingClientProvider.overrideWithValue(FakeRoutingClient())],
      );
      addTearDown(container.dispose);

      container.read(waypointsProvider.notifier).add(const LatLon(35.68, -82.01));
      await container.read(tripGenerationProvider.notifier).generate();

      expect(container.read(tripGenerationProvider).hasError, isTrue);
    });

    test('a reset while generate() is in flight is not clobbered when the stale request resolves', () async {
      final completer = Completer<TripResult>();
      final container = ProviderContainer(
        overrides: [routingClientProvider.overrideWithValue(_DelayedTripClient(completer))],
      );
      addTearDown(container.dispose);

      container.read(waypointsProvider.notifier).add(const LatLon(35.68, -82.01));
      container.read(waypointsProvider.notifier).add(const LatLon(35.7, -82.05));
      final pending = container.read(tripGenerationProvider.notifier).generate();

      container.read(tripGenerationProvider.notifier).clear();

      completer.complete(_trip('stale'));
      await pending;

      expect(container.read(tripGenerationProvider).value, isNull);
    });

    test('changing an input after a trip is generated clears the now-stale trip', () async {
      final container = ProviderContainer(
        overrides: [routingClientProvider.overrideWithValue(FakeRoutingClient(tripToReturn: _trip('t1')))],
      );
      addTearDown(container.dispose);

      container.read(waypointsProvider.notifier).add(const LatLon(35.68, -82.01));
      container.read(waypointsProvider.notifier).add(const LatLon(35.7, -82.05));
      await container.read(tripGenerationProvider.notifier).generate();
      expect(container.read(tripGenerationProvider).value, isNotNull);

      container.read(riderBandProvider.notifier).state = RiderBand.largeGroup;

      expect(container.read(tripGenerationProvider).value, isNull);
    });

    test('changing max daily km after a trip is generated clears the now-stale trip', () async {
      final container = ProviderContainer(
        overrides: [routingClientProvider.overrideWithValue(FakeRoutingClient(tripToReturn: _trip('t1')))],
      );
      addTearDown(container.dispose);

      container.read(waypointsProvider.notifier).add(const LatLon(35.68, -82.01));
      container.read(waypointsProvider.notifier).add(const LatLon(35.7, -82.05));
      await container.read(tripGenerationProvider.notifier).generate();
      expect(container.read(tripGenerationProvider).value, isNotNull);

      container.read(maxDailyKmProvider.notifier).state = 80.0;

      expect(container.read(tripGenerationProvider).value, isNull);
    });
  });

  group('DayAlternativeNotifier', () {
    Future<ProviderContainer> containerWithTrip() async {
      final container = ProviderContainer(
        overrides: [routingClientProvider.overrideWithValue(FakeRoutingClient(tripToReturn: _trip('t1')))],
      );
      container.read(waypointsProvider.notifier).add(const LatLon(35.68, -82.01));
      container.read(waypointsProvider.notifier).add(const LatLon(35.7, -82.05));
      await container.read(tripGenerationProvider.notifier).generate();
      return container;
    }

    test('propose() without a selected day fails without calling the client', () async {
      final container = await containerWithTrip();
      addTearDown(container.dispose);

      await container.read(dayAlternativeProvider.notifier).propose();

      expect(container.read(dayAlternativeProvider).hasError, isTrue);
    });

    test('propose() populates current/alternative for the selected day', () async {
      final container = await containerWithTrip();
      addTearDown(container.dispose);

      container.read(selectedDayIndexProvider.notifier).state = 0;
      await container.read(dayAlternativeProvider.notifier).propose();

      final alt = container.read(dayAlternativeProvider).value;
      expect(alt, isNotNull);
      expect(alt!.alternative.distanceM, greaterThan(alt.current.distanceM));
    });

    test('selecting a different day discards the pending proposal and resets its sliders', () async {
      final container = await containerWithTrip();
      addTearDown(container.dispose);

      container.read(selectedDayIndexProvider.notifier).state = 0;
      container.read(dayOverrideElevationGainProvider.notifier).state = 0.7;
      await container.read(dayAlternativeProvider.notifier).propose();
      expect(container.read(dayAlternativeProvider).value, isNotNull);

      container.read(selectedDayIndexProvider.notifier).state = null;

      expect(container.read(dayAlternativeProvider).value, isNull);
      expect(container.read(dayOverrideElevationGainProvider), 0.0);
    });

    test('applyActive() writes the returned trip into tripGenerationProvider and clears the proposal', () async {
      final container = await containerWithTrip();
      addTearDown(container.dispose);

      container.read(selectedDayIndexProvider.notifier).state = 0;
      await container.read(dayAlternativeProvider.notifier).propose();
      final proposedDistance = container.read(dayAlternativeProvider).value!.alternative.distanceM;

      await container.read(dayAlternativeProvider.notifier).applyActive();

      expect(container.read(dayAlternativeProvider).value, isNull);
      expect(container.read(tripGenerationProvider).value!.days[0].distanceM, proposedDistance);
    });

    test('discard() clears the proposal without touching the trip', () async {
      final container = await containerWithTrip();
      addTearDown(container.dispose);

      container.read(selectedDayIndexProvider.notifier).state = 0;
      await container.read(dayAlternativeProvider.notifier).propose();

      container.read(dayAlternativeProvider.notifier).discard();

      expect(container.read(dayAlternativeProvider).value, isNull);
      expect(container.read(tripGenerationProvider).value!.days[0].distanceM, 48000.0);
    });
  });

  group('savedVariantsProvider', () {
    test('save() appends per day index without disturbing other days', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final dayZero = TripDay(index: 0, coords: const [LatLon(35.68, -82.01)], distanceM: 1000, elevationGainM: 10);
      final alt = DayAlternative(current: dayZero, alternative: dayZero);

      container.read(savedVariantsProvider.notifier).save(0, alt);
      container.read(savedVariantsProvider.notifier).save(0, alt);

      expect(container.read(savedVariantsProvider)[0], hasLength(2));
      expect(container.read(savedVariantsProvider)[1], isNull);
    });
  });
}
