import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../domain/route.dart';
import '../domain/theme.dart';
import '../domain/trip.dart';

class RoutingClientException implements Exception {
  final String message;
  RoutingClientException(this.message);

  @override
  String toString() => message;
}

class GeocodeResult {
  final double lat;
  final double lon;
  final String displayName;

  const GeocodeResult({required this.lat, required this.lon, required this.displayName});
}

/// HTTP facade over ctp-service (Architecture §7.1). Holds a base URL; on
/// Desktop/Mobile that's the local sidecar, on Web it would be the Render
/// origin — nothing above this layer knows which (Architecture §7.1).
class RoutingClient {
  final String baseUrl;
  final http.Client _http;

  static const _requestTimeout = Duration(seconds: 30);

  RoutingClient({this.baseUrl = AppConfig.apiBaseUrl, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  /// Runs an HTTP call with a timeout and turns anything below the HTTP
  /// layer (connection refused, DNS failure, a hung backend) into the same
  /// friendly RoutingClientException a bad status code already produces —
  /// without this, those failures reach the UI as raw framework exception
  /// text (`SocketException: ...`) instead of something a rider can act on.
  Future<http.Response> _guarded(Future<http.Response> Function() send) async {
    try {
      return await send().timeout(_requestTimeout);
    } on TimeoutException {
      throw RoutingClientException('The routing engine took too long to respond.');
    } catch (e) {
      throw RoutingClientException('Could not reach the routing engine — is it still running? ($e)');
    }
  }

  Future<bool> checkReady() async {
    try {
      final resp = await _http.get(Uri.parse('$baseUrl/health'));
      if (resp.statusCode != 200) return false;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return body['ready'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<GeocodeResult> geocode(String query) async {
    final uri = Uri.parse('$baseUrl/geocode').replace(queryParameters: {'q': query});
    final resp = await _guarded(() => _http.get(uri));
    if (resp.statusCode != 200) {
      throw RoutingClientException('could not find "$query"');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return GeocodeResult(
      lat: (body['lat'] as num).toDouble(),
      lon: (body['lon'] as num).toDouble(),
      displayName: body['display_name'] as String,
    );
  }

  Future<RouteResult> generateRoute({
    required LatLon start,
    LatLon? end,
    required RouteTheme theme,
    required RouteShape shape,
    double? targetDistanceKm,
  }) async {
    // Point-to-point never takes a target distance (routing.py's
    // point_to_point branch doesn't read it) — enforced here at the wire
    // boundary so it can't be reintroduced by a future caller forgetting to
    // null it out itself.
    final effectiveTargetDistanceKm = shape == RouteShape.pointToPoint ? null : targetDistanceKm;
    final payload = <String, dynamic>{
      'start': start.toJson(),
      'theme': theme.apiValue,
      'shape': shape.apiValue,
      if (end != null) 'end': end.toJson(),
      'target_distance_km': ?effectiveTargetDistanceKm,
    };

    final resp = await _guarded(
      () => _http.post(
        Uri.parse('$baseUrl/routes/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ),
    );
    if (resp.statusCode != 200) {
      throw RoutingClientException(_errorDetail(resp));
    }
    return RouteResult.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<Uint8List> exportRoute(String routeId, ExportFormat format) async {
    final uri = Uri.parse('$baseUrl/routes/$routeId/export')
        .replace(queryParameters: {'fmt': format.apiValue});
    final resp = await _guarded(() => _http.post(uri));
    if (resp.statusCode != 200) {
      throw RoutingClientException(_errorDetail(resp));
    }
    return resp.bodyBytes;
  }

  /// FR10/FR11/FR12/FR13/FR14/FR15/FR46 — solve a multi-day trip. `day_split`
  /// is omitted entirely when both caps are null, letting the backend's
  /// rider-band default (`default_day_split`) apply — same wire-boundary
  /// pattern as `target_distance_km` being omitted for point-to-point above.
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
    final payload = <String, dynamic>{
      'waypoints': waypoints.map((w) => w.toJson()).toList(),
      'theme': theme.apiValue,
      'elevation_gain': elevationGain,
      'surface_preference': surfacePreference,
      'overrides': overrides.map((o) => o.toJson()).toList(),
      'rider_band': riderBand.apiValue,
      'start_date': _dateOnly(startDate),
      if (maxDailyKm != null)
        'day_split': {
          // FR11's min is a soft target only; a fixed generous floor keeps
          // the payload valid without exposing a control the UI doesn't have.
          'min_daily_km': 1.0,
          'max_daily_km': maxDailyKm,
          'max_daily_elevation_m': ?maxDailyElevationM,
        },
    };

    final resp = await _guarded(
      () => _http.post(
        Uri.parse('$baseUrl/trips/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ),
    );
    if (resp.statusCode != 200) {
      throw RoutingClientException(_errorDetail(resp));
    }
    return TripResult.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// FR42 — proposes an alternative for one day/segment alongside the
  /// current one, without mutating the stored trip.
  Future<DayAlternative> proposeAlternative({
    required String tripId,
    required int dayIndex,
    double elevationGain = 0.0,
    double surfacePreference = 0.0,
    double? segmentStartKm,
    double? segmentEndKm,
  }) async {
    final resp = await _guarded(
      () => _http.post(
        Uri.parse('$baseUrl/trips/$tripId/days/$dayIndex/reroute'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(_alternativeRequestBody(
          elevationGain: elevationGain,
          surfacePreference: surfacePreference,
          segmentStartKm: segmentStartKm,
          segmentEndKm: segmentEndKm,
        )),
      ),
    );
    if (resp.statusCode != 200) {
      throw RoutingClientException(_errorDetail(resp));
    }
    return DayAlternative.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// FR42 "make active" — recomputes the same alternative and swaps it into
  /// the stored trip, returning the whole updated trip.
  Future<TripResult> applyAlternative({
    required String tripId,
    required int dayIndex,
    double elevationGain = 0.0,
    double surfacePreference = 0.0,
    double? segmentStartKm,
    double? segmentEndKm,
  }) async {
    final resp = await _guarded(
      () => _http.post(
        Uri.parse('$baseUrl/trips/$tripId/days/$dayIndex/apply-alternative'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(_alternativeRequestBody(
          elevationGain: elevationGain,
          surfacePreference: surfacePreference,
          segmentStartKm: segmentStartKm,
          segmentEndKm: segmentEndKm,
        )),
      ),
    );
    if (resp.statusCode != 200) {
      throw RoutingClientException(_errorDetail(resp));
    }
    return TripResult.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Map<String, dynamic> _alternativeRequestBody({
    required double elevationGain,
    required double surfacePreference,
    double? segmentStartKm,
    double? segmentEndKm,
  }) =>
      {
        'elevation_gain': elevationGain,
        'surface_preference': surfacePreference,
        'segment_start_km': ?segmentStartKm,
        'segment_end_km': ?segmentEndKm,
      };

  Future<Uint8List> exportDay(String tripId, int dayIndex, ExportFormat format) async {
    final uri = Uri.parse('$baseUrl/trips/$tripId/days/$dayIndex/export')
        .replace(queryParameters: {'fmt': format.apiValue});
    final resp = await _guarded(() => _http.post(uri));
    if (resp.statusCode != 200) {
      throw RoutingClientException(_errorDetail(resp));
    }
    return resp.bodyBytes;
  }

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  /// FR39 (desktop half) — prune downloaded region data. Returns whether
  /// anything was actually cleared.
  Future<bool> clearCache() async {
    final resp = await _guarded(() => _http.post(Uri.parse('$baseUrl/admin/clear-cache')));
    if (resp.statusCode != 200) {
      throw RoutingClientException(_errorDetail(resp));
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return body['cleared'] == true;
  }

  /// Template for flutter_map's TileLayer — the client only ever talks to
  /// ctp-service for tiles, never a third-party host directly (see the
  /// tile callout in ARCHITECTURE.md / ROADMAP.md Leg 2).
  String get tileUrlTemplate => '$baseUrl/tiles/{z}/{x}/{y}';

  String _errorDetail(http.Response resp) {
    try {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return body['detail']?.toString() ?? 'request failed (${resp.statusCode})';
    } catch (_) {
      return 'request failed (${resp.statusCode})';
    }
  }
}
