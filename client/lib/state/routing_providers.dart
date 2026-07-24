import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../data/routing_client.dart';
import '../domain/route.dart';
import '../domain/theme.dart';

final routingClientProvider = Provider<RoutingClient>((ref) => RoutingClient());

/// Polls until ready (Architecture §6.3: health is readiness, not
/// liveness). The planner screen gates route generation on this.
///
/// FR48: a cold start (first-run graph fetch + elevation enrichment) can
/// take minutes — that's not a failure, so this polls indefinitely rather
/// than giving up after a fixed window. The planner screen shows an
/// escalating cycling-themed message for the duration.
final backendReadyProvider = FutureProvider<void>((ref) async {
  final client = ref.watch(routingClientProvider);
  while (!await client.checkReady()) {
    await Future.delayed(const Duration(seconds: 1));
  }
});

final selectedThemeProvider = StateProvider<RouteTheme>((ref) => RouteTheme.flattest);
final selectedShapeProvider = StateProvider<RouteShape>((ref) => RouteShape.loop);
final startPointProvider = StateProvider<LatLon?>((ref) => null);
final destinationPointProvider = StateProvider<LatLon?>((ref) => null);

/// Target-distance slider steps (PRD FR47): Fibonacci-like growth (each step
/// ≈ sum of the previous two) from a 10km floor to a 300km/180mi ceiling,
/// rather than a linear scale — short rides get fine-grained steps, long
/// tours get coarse ones.
const targetDistanceStepsKm = <double>[10, 20, 30, 50, 80, 130, 210, 300];

final targetDistanceKmProvider = StateProvider<double>((ref) => 20.0);

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
        targetDistanceKm: ref.read(targetDistanceKmProvider),
      ),
    );
  }

  void clear() {
    state = const AsyncData(null);
  }
}

final routeGenerationProvider =
    AsyncNotifierProvider<RouteGenerationNotifier, RouteResult?>(RouteGenerationNotifier.new);
