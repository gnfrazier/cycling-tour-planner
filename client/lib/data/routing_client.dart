import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../domain/route.dart';
import '../domain/theme.dart';

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

  RoutingClient({this.baseUrl = AppConfig.apiBaseUrl, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

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
    final resp = await _http.get(uri);
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

    final resp = await _http.post(
      Uri.parse('$baseUrl/routes/generate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (resp.statusCode != 200) {
      throw RoutingClientException(_errorDetail(resp));
    }
    return RouteResult.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<Uint8List> exportRoute(String routeId, ExportFormat format) async {
    final uri = Uri.parse('$baseUrl/routes/$routeId/export')
        .replace(queryParameters: {'fmt': format.apiValue});
    final resp = await _http.post(uri);
    if (resp.statusCode != 200) {
      throw RoutingClientException(_errorDetail(resp));
    }
    return resp.bodyBytes;
  }

  /// FR39 (desktop half) — prune downloaded region data. Returns whether
  /// anything was actually cleared.
  Future<bool> clearCache() async {
    final resp = await _http.post(Uri.parse('$baseUrl/admin/clear-cache'));
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
