import 'dart:convert';

import 'package:client/data/routing_client.dart';
import 'package:client/domain/route.dart';
import 'package:client/domain/theme.dart';
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
}
