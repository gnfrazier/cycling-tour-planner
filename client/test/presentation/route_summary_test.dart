import 'package:client/domain/route.dart';
import 'package:client/domain/theme.dart';
import 'package:client/presentation/screens/route_planner_screen.dart';
import 'package:client/state/routing_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_routing_client.dart';

void main() {
  testWidgets('surface and traffic breakdown are shown alongside distance and elevation (PRD S6)', (tester) async {
    final route = RouteResult(
      id: 'r1',
      theme: RouteTheme.flattest,
      shape: RouteShape.loop,
      coords: const [LatLon(35.68, -82.01), LatLon(35.69, -82.02)],
      distanceM: 1000,
      elevationGainM: 10,
      surfaceBreakdownM: const {'asphalt': 800.0, 'gravel': 200.0},
      trafficBreakdownM: const {'residential': 1000.0},
    );

    final container = ProviderContainer(
      overrides: [
        routingClientProvider.overrideWithValue(FakeRoutingClient(routeToReturn: route)),
        backendReadyProvider.overrideWith((ref) async {}),
      ],
    );
    addTearDown(container.dispose);

    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: RoutePlannerScreen()),
      ),
    );
    await tester.pumpAndSettle();

    container.read(startPointProvider.notifier).state = const LatLon(35.6841, -82.0091);
    await container.read(routeGenerationProvider.notifier).generate();
    await tester.pumpAndSettle();

    expect(find.text('Surface: asphalt 80%, gravel 20%'), findsOneWidget);
    expect(find.text('Traffic: residential 100%'), findsOneWidget);
  });
}
