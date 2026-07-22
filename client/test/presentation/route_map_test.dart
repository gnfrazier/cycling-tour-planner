import 'package:client/domain/route.dart';
import 'package:client/domain/theme.dart';
import 'package:client/presentation/widgets/route_map.dart';
import 'package:client/state/routing_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_routing_client.dart';

class _FixedRouteNotifier extends RouteGenerationNotifier {
  final RouteResult route;
  _FixedRouteNotifier(this.route);

  @override
  RouteResult? build() => route;
}

void main() {
  testWidgets('RouteMap builds and renders a polyline for a generated route', (tester) async {
    final route = RouteResult(
      id: 'fixed-route',
      theme: RouteTheme.lowestTraffic,
      shape: RouteShape.loop,
      coords: const [LatLon(35.68, -82.01), LatLon(35.69, -82.02), LatLon(35.68, -82.01)],
      distanceM: 3000,
      elevationGainM: 40,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          routingClientProvider.overrideWithValue(FakeRoutingClient()),
          routeGenerationProvider.overrideWith(() => _FixedRouteNotifier(route)),
        ],
        child: const MaterialApp(home: Scaffold(body: SizedBox(height: 400, child: RouteMap()))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byType(PolylineLayer), findsOneWidget);
  });
}
