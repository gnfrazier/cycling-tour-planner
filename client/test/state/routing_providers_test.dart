import 'dart:async';

import 'package:client/data/routing_client.dart';
import 'package:client/domain/route.dart';
import 'package:client/domain/theme.dart';
import 'package:client/state/routing_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_routing_client.dart';

class _DelayedRoutingClient extends RoutingClient {
  final Completer<RouteResult> completer;
  _DelayedRoutingClient(this.completer) : super(baseUrl: 'http://fake');

  @override
  Future<bool> checkReady() async => true;

  @override
  Future<RouteResult> generateRoute({
    required LatLon start,
    LatLon? end,
    required RouteTheme theme,
    required RouteShape shape,
    double? targetDistanceKm,
  }) =>
      completer.future;
}

RouteResult _route(String id) => RouteResult(
      id: id,
      theme: RouteTheme.flattest,
      shape: RouteShape.loop,
      coords: const [LatLon(35.68, -82.01), LatLon(35.69, -82.02)],
      distanceM: 1000,
      elevationGainM: 10,
    );

void main() {
  test('a reset while generate() is in flight is not clobbered when the stale request resolves', () async {
    final completer = Completer<RouteResult>();
    final container = ProviderContainer(
      overrides: [routingClientProvider.overrideWithValue(_DelayedRoutingClient(completer))],
    );
    addTearDown(container.dispose);

    container.read(startPointProvider.notifier).state = const LatLon(35.6841, -82.0091);
    final pending = container.read(routeGenerationProvider.notifier).generate();

    // Reset while the request above is still pending.
    container.read(routeGenerationProvider.notifier).clear();

    // The stale request now resolves — it must not overwrite the reset.
    completer.complete(_route('stale'));
    await pending;

    expect(container.read(routeGenerationProvider).value, isNull);
  });

  test('changing an input after a route is generated clears the now-stale route', () async {
    final container = ProviderContainer(
      overrides: [routingClientProvider.overrideWithValue(FakeRoutingClient(routeToReturn: _route('r1')))],
    );
    addTearDown(container.dispose);

    container.read(startPointProvider.notifier).state = const LatLon(35.6841, -82.0091);
    await container.read(routeGenerationProvider.notifier).generate();
    expect(container.read(routeGenerationProvider).value, isNotNull);

    container.read(selectedThemeProvider.notifier).state = RouteTheme.mostArt;

    expect(container.read(routeGenerationProvider).value, isNull);
  });

  test('changing target distance after a route is generated clears the now-stale route', () async {
    final container = ProviderContainer(
      overrides: [routingClientProvider.overrideWithValue(FakeRoutingClient(routeToReturn: _route('r1')))],
    );
    addTearDown(container.dispose);

    container.read(startPointProvider.notifier).state = const LatLon(35.6841, -82.0091);
    await container.read(routeGenerationProvider.notifier).generate();
    expect(container.read(routeGenerationProvider).value, isNotNull);

    container.read(targetDistanceKmProvider.notifier).state = 80.0;

    expect(container.read(routeGenerationProvider).value, isNull);
  });
}
