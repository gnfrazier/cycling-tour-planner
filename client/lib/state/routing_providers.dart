import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/routing_client.dart';
import '../domain/route.dart';
import '../domain/theme.dart';

final routingClientProvider = Provider<RoutingClient>((ref) => RoutingClient());

/// Polls-once readiness check (Architecture §6.3: health is readiness, not
/// liveness). The planner screen gates route generation on this.
final backendReadyProvider = FutureProvider<bool>((ref) async {
  final client = ref.watch(routingClientProvider);
  for (var attempt = 0; attempt < 60; attempt++) {
    if (await client.checkReady()) return true;
    await Future.delayed(const Duration(seconds: 1));
  }
  return false;
});

final selectedThemeProvider = StateProvider<RouteTheme>((ref) => RouteTheme.flattest);
final selectedShapeProvider = StateProvider<RouteShape>((ref) => RouteShape.loop);
final startPointProvider = StateProvider<LatLon?>((ref) => null);
final destinationPointProvider = StateProvider<LatLon?>((ref) => null);
final targetDistanceKmProvider = StateProvider<double>((ref) => 15.0);

class RouteGenerationNotifier extends AsyncNotifier<RouteResult?> {
  @override
  RouteResult? build() => null;

  Future<void> generate() async {
    final start = ref.read(startPointProvider);
    if (start == null) {
      state = AsyncError('Pick a start point first', StackTrace.current);
      return;
    }

    final shape = ref.read(selectedShapeProvider);
    final theme = ref.read(selectedThemeProvider);
    final end = ref.read(destinationPointProvider);
    if (shape == RouteShape.pointToPoint && end == null) {
      state = AsyncError('Pick a destination for a point-to-point route', StackTrace.current);
      return;
    }

    state = const AsyncLoading();
    final client = ref.read(routingClientProvider);
    state = await AsyncValue.guard(
      () => client.generateRoute(
        start: start,
        end: shape == RouteShape.pointToPoint ? end : null,
        theme: theme,
        shape: shape,
        targetDistanceKm: shape == RouteShape.pointToPoint ? null : ref.read(targetDistanceKmProvider),
      ),
    );
  }

  void clear() {
    state = const AsyncData(null);
  }
}

final routeGenerationProvider =
    AsyncNotifierProvider<RouteGenerationNotifier, RouteResult?>(RouteGenerationNotifier.new);
