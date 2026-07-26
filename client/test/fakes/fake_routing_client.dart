import 'dart:typed_data';

import 'package:client/data/routing_client.dart';
import 'package:client/domain/route.dart';
import 'package:client/domain/theme.dart';
import 'package:client/domain/trip.dart';

/// A RoutingClient that never touches the network — for widget tests.
class FakeRoutingClient extends RoutingClient {
  final RouteResult? routeToReturn;
  final TripResult? tripToReturn;
  final DayAlternative? alternativeToReturn;

  FakeRoutingClient({this.routeToReturn, this.tripToReturn, this.alternativeToReturn})
      : super(baseUrl: 'http://fake');

  @override
  Future<bool> checkReady() async => true;

  @override
  Future<GeocodeResult> geocode(String query) async =>
      const GeocodeResult(lat: 35.6841, lon: -82.0091, displayName: 'Marion, NC');

  @override
  Future<RouteResult> generateRoute({
    required LatLon start,
    LatLon? end,
    required RouteTheme theme,
    required RouteShape shape,
    double? targetDistanceKm,
  }) async {
    return routeToReturn ??
        RouteResult(
          id: 'fake-route',
          theme: theme,
          shape: shape,
          coords: [LatLon(start.lat, start.lon), LatLon(start.lat + 0.01, start.lon + 0.01)],
          distanceM: 1000,
          elevationGainM: 20,
        );
  }

  @override
  Future<Uint8List> exportRoute(String routeId, ExportFormat format) async =>
      Uint8List.fromList([1, 2, 3]);

  @override
  Future<bool> clearCache() async => true;

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
  }) async {
    return tripToReturn ??
        TripResult(
          id: 'fake-trip',
          waypoints: waypoints,
          theme: theme,
          riderBand: riderBand,
          startDate: startDate,
          days: [
            TripDay(
              index: 0,
              coords: waypoints.map((w) => w.coord).toList(),
              distanceM: 48000.0,
              elevationGainM: 365.0,
              surfaceBreakdownM: const {'asphalt': 40000.0, 'gravel': 8000.0},
              trafficBreakdownM: const {'residential': 30000.0, 'primary': 18000.0},
            ),
          ],
          totalDistanceM: 48000.0,
          totalElevationGainM: 365.0,
        );
  }

  Future<TripResult> _baseTrip() async =>
      tripToReturn ??
      await generateTrip(
        waypoints: const [Waypoint(coord: LatLon(35.68, -82.01)), Waypoint(coord: LatLon(35.7, -82.05))],
        theme: RouteTheme.flattest,
        riderBand: RiderBand.solo,
        startDate: DateTime.now(),
      );

  @override
  Future<DayAlternative> proposeAlternative({
    required String tripId,
    required int dayIndex,
    double elevationGain = 0.0,
    double surfacePreference = 0.0,
    double? segmentStartKm,
    double? segmentEndKm,
  }) async {
    if (alternativeToReturn != null) return alternativeToReturn!;
    final day = (await _baseTrip()).days[dayIndex];
    final alternative = TripDay(
      index: day.index,
      coords: day.coords,
      distanceM: day.distanceM + 2000.0,
      elevationGainM: day.elevationGainM + 100.0,
      surfaceBreakdownM: const {'asphalt': 30000.0, 'gravel': 20000.0},
      trafficBreakdownM: const {'residential': 20000.0, 'track': 30000.0},
    );
    return DayAlternative(current: day, alternative: alternative);
  }

  @override
  Future<TripResult> applyAlternative({
    required String tripId,
    required int dayIndex,
    double elevationGain = 0.0,
    double surfacePreference = 0.0,
    double? segmentStartKm,
    double? segmentEndKm,
  }) async {
    final proposal = await proposeAlternative(
      tripId: tripId,
      dayIndex: dayIndex,
      elevationGain: elevationGain,
      surfacePreference: surfacePreference,
      segmentStartKm: segmentStartKm,
      segmentEndKm: segmentEndKm,
    );
    final base = await _baseTrip();
    return base.copyWithDay(dayIndex, proposal.alternative);
  }

  @override
  Future<Uint8List> exportDay(String tripId, int dayIndex, ExportFormat format) async =>
      Uint8List.fromList([1, 2, 3]);

  @override
  String get tileUrlTemplate => 'http://fake/tiles/{z}/{x}/{y}';
}
