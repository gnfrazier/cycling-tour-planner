import 'theme.dart';

/// A plain lat/lon pair. Pure domain value, no I/O.
class LatLon {
  final double lat;
  final double lon;

  const LatLon(this.lat, this.lon);

  Map<String, double> toJson() => {'lat': lat, 'lon': lon};
}

/// A generated route (mirrors ctp_core.types.Route / ctp_service RouteResponse).
class RouteResult {
  final String id;
  final RouteTheme theme;
  final RouteShape shape;
  final List<LatLon> coords;
  final double distanceM;
  final double elevationGainM;

  const RouteResult({
    required this.id,
    required this.theme,
    required this.shape,
    required this.coords,
    required this.distanceM,
    required this.elevationGainM,
  });

  double get distanceKm => distanceM / 1000;

  factory RouteResult.fromJson(Map<String, dynamic> json) {
    return RouteResult(
      id: json['id'] as String,
      theme: RouteTheme.fromApiValue(json['theme'] as String),
      shape: RouteShape.fromApiValue(json['shape'] as String),
      coords: (json['coords'] as List)
          .map((c) => LatLon(
                (c['lat'] as num).toDouble(),
                (c['lon'] as num).toDouble(),
              ))
          .toList(),
      distanceM: (json['distance_m'] as num).toDouble(),
      elevationGainM: (json['elevation_gain_m'] as num).toDouble(),
    );
  }
}
