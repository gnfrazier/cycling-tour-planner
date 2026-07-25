import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../domain/route.dart';
import '../domain/trip.dart';
import 'routing_providers.dart';

/// FR10 — the ordered chain of waypoints a trip must honor. Unlike the
/// single-route planner's fixed start/destination pair, this is a
/// mutable-length list, so it needs a Notifier rather than a bare
/// StateProvider.
class WaypointListNotifier extends Notifier<List<Waypoint>> {
  @override
  List<Waypoint> build() => const [];

  void add(LatLon coord, {String? label}) {
    state = [...state, Waypoint(coord: coord, label: label)];
  }

  /// `label` is not preserved from the previous value at this index unless
  /// explicitly passed again — a coordinate change (e.g. a map tap) makes
  /// any old typed address stale, so it's cleared rather than left
  /// misleadingly attached to the new coordinate.
  void updateAt(int index, LatLon coord, {String? label}) {
    final updated = List<Waypoint>.from(state);
    updated[index] = Waypoint(coord: coord, label: label);
    state = updated;
  }

  void removeAt(int index) {
    final updated = List<Waypoint>.from(state)..removeAt(index);
    state = updated;
  }

  /// `newIndex` is the item's final index *after* removal — matches
  /// ReorderableListView's `onReorderItem` callback contract.
  void reorder(int oldIndex, int newIndex) {
    final updated = List<Waypoint>.from(state);
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    state = updated;
  }

  void clear() => state = const [];
}

final waypointsProvider = NotifierProvider<WaypointListNotifier, List<Waypoint>>(WaypointListNotifier.new);

/// Which waypoint row a map tap should fill next — set while a row's search
/// field has focus or right after "Add waypoint" is pressed, cleared once
/// filled. Null means a map tap appends a new waypoint instead of editing one.
final activeWaypointSlotProvider = StateProvider<int?>((ref) => null);

final riderBandProvider = StateProvider<RiderBand>((ref) => RiderBand.solo);
final tripStartDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

/// FR13 — tour-default sliding-scale weighting, -1..1 (mirrors the
/// day/segment override sliders in the weighting panel, but scoped to the
/// whole trip).
final tripElevationGainProvider = StateProvider<double>((ref) => 0.0);
final tripSurfacePreferenceProvider = StateProvider<double>((ref) => 0.0);

/// FR11/FR46 — null means "use the rider-band default"
/// (`default_day_split` server-side); a non-null value overrides it.
final maxDailyKmProvider = StateProvider<double?>((ref) => null);
final maxDailyElevationMProvider = StateProvider<double?>((ref) => null);

class TripGenerationNotifier extends AsyncNotifier<TripResult?> {
  // Same role as RouteGenerationNotifier's _generation counter: lets an
  // in-flight generate() tell it's been superseded (input change or a newer
  // generate()) and discard its result instead of overwriting the current one.
  int _generation = 0;

  @override
  TripResult? build() {
    ref.listen(waypointsProvider, (_, _) => clear());
    ref.listen(selectedThemeProvider, (_, _) => clear());
    ref.listen(riderBandProvider, (_, _) => clear());
    ref.listen(tripStartDateProvider, (_, _) => clear());
    ref.listen(tripElevationGainProvider, (_, _) => clear());
    ref.listen(tripSurfacePreferenceProvider, (_, _) => clear());
    ref.listen(maxDailyKmProvider, (_, _) => clear());
    ref.listen(maxDailyElevationMProvider, (_, _) => clear());
    return null;
  }

  Future<void> generate() async {
    final generation = ++_generation;

    final waypoints = ref.read(waypointsProvider);
    if (waypoints.length < 2) {
      state = AsyncError('A trip needs at least two waypoints', StackTrace.current);
      return;
    }

    state = const AsyncLoading();
    final client = ref.read(routingClientProvider);
    final result = await AsyncValue.guard(
      () => client.generateTrip(
        waypoints: waypoints,
        theme: ref.read(selectedThemeProvider),
        riderBand: ref.read(riderBandProvider),
        startDate: ref.read(tripStartDateProvider),
        elevationGain: ref.read(tripElevationGainProvider),
        surfacePreference: ref.read(tripSurfacePreferenceProvider),
        maxDailyKm: ref.read(maxDailyKmProvider),
        maxDailyElevationM: ref.read(maxDailyElevationMProvider),
      ),
    );
    if (generation == _generation) {
      state = result;
    }
  }

  void clear() {
    _generation++;
    state = const AsyncData(null);
  }
}

final tripGenerationProvider =
    AsyncNotifierProvider<TripGenerationNotifier, TripResult?>(TripGenerationNotifier.new);

/// Which day card is expanded/under edit in the timeline — drives both the
/// weighting panel and the compare panel.
final selectedDayIndexProvider = StateProvider<int?>((ref) => null);

/// FR13 — the day-weighting-panel's own sliders/fields, scoped to whichever
/// day is currently selected. Null start/end means the whole day.
final dayOverrideElevationGainProvider = StateProvider<double>((ref) => 0.0);
final dayOverrideSurfacePreferenceProvider = StateProvider<double>((ref) => 0.0);
final dayOverrideSegmentStartKmProvider = StateProvider<double?>((ref) => null);
final dayOverrideSegmentEndKmProvider = StateProvider<double?>((ref) => null);

class DayAlternativeNotifier extends AsyncNotifier<DayAlternative?> {
  @override
  DayAlternative? build() {
    // Switching which day is under edit invalidates any in-progress
    // proposal for the previous day and resets that day's own sliders back
    // to neutral, so a proposal never silently carries over onto a
    // different day's map/compare view.
    ref.listen(selectedDayIndexProvider, (_, _) => _resetForNewDay());
    return null;
  }

  void _resetForNewDay() {
    ref.read(dayOverrideElevationGainProvider.notifier).state = 0.0;
    ref.read(dayOverrideSurfacePreferenceProvider.notifier).state = 0.0;
    ref.read(dayOverrideSegmentStartKmProvider.notifier).state = null;
    ref.read(dayOverrideSegmentEndKmProvider.notifier).state = null;
    state = const AsyncData(null);
  }

  Future<void> propose() async {
    final dayIndex = ref.read(selectedDayIndexProvider);
    final trip = ref.read(tripGenerationProvider).value;
    if (dayIndex == null || trip == null) {
      state = AsyncError('Select a day first', StackTrace.current);
      return;
    }

    state = const AsyncLoading();
    final client = ref.read(routingClientProvider);
    state = await AsyncValue.guard(
      () => client.proposeAlternative(
        tripId: trip.id,
        dayIndex: dayIndex,
        elevationGain: ref.read(dayOverrideElevationGainProvider),
        surfacePreference: ref.read(dayOverrideSurfacePreferenceProvider),
        segmentStartKm: ref.read(dayOverrideSegmentStartKmProvider),
        segmentEndKm: ref.read(dayOverrideSegmentEndKmProvider),
      ),
    );
  }

  /// FR42 "make active" — recomputes the same alternative and swaps it into
  /// the stored trip; the endpoint already returns the whole updated trip,
  /// so this writes straight into `tripGenerationProvider`'s state rather
  /// than re-deriving totals client-side.
  Future<void> applyActive() async {
    final dayIndex = ref.read(selectedDayIndexProvider);
    final trip = ref.read(tripGenerationProvider).value;
    if (dayIndex == null || trip == null) {
      state = AsyncError('Select a day first', StackTrace.current);
      return;
    }

    state = const AsyncLoading();
    final client = ref.read(routingClientProvider);
    final result = await AsyncValue.guard(
      () => client.applyAlternative(
        tripId: trip.id,
        dayIndex: dayIndex,
        elevationGain: ref.read(dayOverrideElevationGainProvider),
        surfacePreference: ref.read(dayOverrideSurfacePreferenceProvider),
        segmentStartKm: ref.read(dayOverrideSegmentStartKmProvider),
        segmentEndKm: ref.read(dayOverrideSegmentEndKmProvider),
      ),
    );
    result.when(
      data: (updatedTrip) {
        ref.read(tripGenerationProvider.notifier).state = AsyncData(updatedTrip);
        state = const AsyncData(null);
      },
      error: (err, st) => state = AsyncError(err, st),
      loading: () {},
    );
  }

  /// Discards the working proposal without applying it — the map/compare
  /// panel reverts to showing just the trip's current day.
  void discard() {
    state = const AsyncData(null);
  }
}

final dayAlternativeProvider =
    AsyncNotifierProvider<DayAlternativeNotifier, DayAlternative?>(DayAlternativeNotifier.new);

/// FR42 "save as variant" — session-local only (no cross-device sync; that's
/// FR21/Leg 4). Keyed by day index so each day can accumulate its own set of
/// saved-but-not-applied alternatives.
class SavedVariantsNotifier extends Notifier<Map<int, List<DayAlternative>>> {
  @override
  Map<int, List<DayAlternative>> build() => const {};

  void save(int dayIndex, DayAlternative alternative) {
    final updated = Map<int, List<DayAlternative>>.from(state);
    updated[dayIndex] = [...(updated[dayIndex] ?? const []), alternative];
    state = updated;
  }
}

final savedVariantsProvider =
    NotifierProvider<SavedVariantsNotifier, Map<int, List<DayAlternative>>>(SavedVariantsNotifier.new);
