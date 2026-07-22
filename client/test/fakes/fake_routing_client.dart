import 'dart:typed_data';

import 'package:client/data/routing_client.dart';
import 'package:client/domain/route.dart';
import 'package:client/domain/theme.dart';

/// A RoutingClient that never touches the network — for widget tests.
class FakeRoutingClient extends RoutingClient {
  final RouteResult? routeToReturn;

  FakeRoutingClient({this.routeToReturn}) : super(baseUrl: 'http://fake');

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
  String get tileUrlTemplate => 'http://fake/tiles/{z}/{x}/{y}';
}
