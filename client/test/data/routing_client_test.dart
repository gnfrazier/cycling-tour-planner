import 'dart:convert';

import 'package:client/data/routing_client.dart';
import 'package:client/domain/route.dart';
import 'package:client/domain/theme.dart';
import 'package:client/domain/trip.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _fakeRouteResponseJson(Map<String, dynamic> requestBody) => {
      'id': 'fake-id',
      'theme': requestBody['theme'],
      'shape': requestBody['shape'],
      'coords': [
        {'lat': 35.6841, 'lon': -82.0091},
        {'lat': 35.685, 'lon': -82.01},
      ],
      'distance_m': 1000.0,
      'elevation_gain_m': 10.0,
    };

Map<String, dynamic> _fakeTripResponseJson(Map<String, dynamic> requestBody) => {
      'id': 'trip-1',
      'waypoints': requestBody['waypoints'],
      'theme': requestBody['theme'],
      'rider_band': requestBody['rider_band'],
      'start_date': requestBody['start_date'],
      'days': [
        {
          'index': 0,
          'coords': [
            {'lat': 35.68, 'lon': -82.01},
            {'lat': 35.7, 'lon': -82.05},
          ],
          'distance_m': 48000.0,
          'elevation_gain_m': 365.0,
          'surface_breakdown_m': <String, double>{},
          'lodging_options': <Map<String, dynamic>>[],
          'weather': null,
          'regroup_cautions': <String>[],
        },
      ],
      'total_distance_m': 48000.0,
      'total_elevation_gain_m': 365.0,
    };

void main() {
  test('generateRoute omits target_distance_km for point-to-point even if one is passed in', () async {
    late Map<String, dynamic> sentBody;
    final client = RoutingClient(
      httpClient: MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(_fakeRouteResponseJson(sentBody)), 200);
      }),
    );

    await client.generateRoute(
      start: const LatLon(35.6841, -82.0091),
      end: const LatLon(35.695, -82.010),
      theme: RouteTheme.flattest,
      shape: RouteShape.pointToPoint,
      targetDistanceKm: 20.0,
    );

    expect(sentBody.containsKey('target_distance_km'), isFalse);
  });

  test('generateRoute includes target_distance_km for loop', () async {
    late Map<String, dynamic> sentBody;
    final client = RoutingClient(
      httpClient: MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(_fakeRouteResponseJson(sentBody)), 200);
      }),
    );

    await client.generateRoute(
      start: const LatLon(35.6841, -82.0091),
      theme: RouteTheme.flattest,
      shape: RouteShape.loop,
      targetDistanceKm: 20.0,
    );

    expect(sentBody['target_distance_km'], 20.0);
  });

  test('a connection-level failure is surfaced as a friendly RoutingClientException, not raw exception text', () async {
    final client = RoutingClient(
      httpClient: MockClient((request) async {
        throw Exception('Connection refused');
      }),
    );

    await expectLater(
      client.generateRoute(
        start: const LatLon(35.6841, -82.0091),
        theme: RouteTheme.flattest,
        shape: RouteShape.loop,
        targetDistanceKm: 20.0,
      ),
      throwsA(isA<RoutingClientException>()),
    );
  });

  test('a connection-level failure on geocode is also wrapped as a friendly RoutingClientException', () async {
    final client = RoutingClient(
      httpClient: MockClient((request) async {
        throw Exception('DNS lookup failed');
      }),
    );

    await expectLater(client.geocode('Marion, NC'), throwsA(isA<RoutingClientException>()));
  });

  test('generateTrip omits day_split when no max daily km is given', () async {
    late Map<String, dynamic> sentBody;
    final client = RoutingClient(
      httpClient: MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(_fakeTripResponseJson(sentBody)), 200);
      }),
    );

    await client.generateTrip(
      waypoints: const [
        Waypoint(coord: LatLon(35.68, -82.01)),
        Waypoint(coord: LatLon(35.7, -82.05)),
      ],
      theme: RouteTheme.flattest,
      riderBand: RiderBand.solo,
      startDate: DateTime(2026, 9, 12),
    );

    expect(sentBody.containsKey('day_split'), isFalse);
    expect(sentBody['start_date'], '2026-09-12');
  });

  test('generateTrip includes day_split when a max daily km is given', () async {
    late Map<String, dynamic> sentBody;
    final client = RoutingClient(
      httpClient: MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(_fakeTripResponseJson(sentBody)), 200);
      }),
    );

    await client.generateTrip(
      waypoints: const [
        Waypoint(coord: LatLon(35.68, -82.01)),
        Waypoint(coord: LatLon(35.7, -82.05)),
      ],
      theme: RouteTheme.flattest,
      riderBand: RiderBand.largeGroup,
      startDate: DateTime(2026, 9, 12),
      maxDailyKm: 80.0,
      maxDailyElevationM: 900.0,
    );

    expect(sentBody['day_split'], {'min_daily_km': 1.0, 'max_daily_km': 80.0, 'max_daily_elevation_m': 900.0});
  });

  test('proposeAlternative posts to the reroute endpoint and parses current/alternative', () async {
    Uri? calledUri;
    final client = RoutingClient(
      httpClient: MockClient((request) async {
        calledUri = request.url;
        final day = _fakeTripResponseJson({
          'waypoints': [],
          'theme': 'flattest',
          'rider_band': 'solo',
          'start_date': '2026-09-12',
        })['days'][0];
        return http.Response(jsonEncode({'current': day, 'alternative': day}), 200);
      }),
    );

    final alt = await client.proposeAlternative(tripId: 'trip-1', dayIndex: 1, elevationGain: 0.5);

    expect(calledUri.toString(), endsWith('/trips/trip-1/days/1/reroute'));
    expect(alt.current.distanceM, 48000.0);
  });

  test('applyAlternative posts to the apply-alternative endpoint and returns the updated trip', () async {
    Uri? calledUri;
    final client = RoutingClient(
      httpClient: MockClient((request) async {
        calledUri = request.url;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode(_fakeTripResponseJson({
            'waypoints': [],
            'theme': 'flattest',
            'rider_band': 'solo',
            'start_date': '2026-09-12',
            ...body,
          })),
          200,
        );
      }),
    );

    final trip = await client.applyAlternative(tripId: 'trip-1', dayIndex: 0, surfacePreference: -0.3);

    expect(calledUri.toString(), endsWith('/trips/trip-1/days/0/apply-alternative'));
    expect(trip.id, 'trip-1');
  });

  test('exportDay posts to the per-day export endpoint with the format as a query param', () async {
    Uri? calledUri;
    final client = RoutingClient(
      httpClient: MockClient((request) async {
        calledUri = request.url;
        return http.Response.bytes([1, 2, 3], 200);
      }),
    );

    final bytes = await client.exportDay('trip-1', 2, ExportFormat.gpx);

    expect(calledUri?.path, '/trips/trip-1/days/2/export');
    expect(calledUri?.queryParameters['fmt'], 'gpx');
    expect(bytes, [1, 2, 3]);
  });

  test('a connection-level failure on generateTrip is wrapped as a friendly RoutingClientException', () async {
    final client = RoutingClient(
      httpClient: MockClient((request) async {
        throw Exception('Connection refused');
      }),
    );

    await expectLater(
      client.generateTrip(
        waypoints: const [
          Waypoint(coord: LatLon(35.68, -82.01)),
          Waypoint(coord: LatLon(35.7, -82.05)),
        ],
        theme: RouteTheme.flattest,
        riderBand: RiderBand.solo,
        startDate: DateTime(2026, 9, 12),
      ),
      throwsA(isA<RoutingClientException>()),
    );
  });
}
