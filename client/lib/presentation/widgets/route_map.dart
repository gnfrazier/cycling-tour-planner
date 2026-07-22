import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../domain/route.dart' as domain;
import '../../domain/theme.dart';
import '../../state/routing_providers.dart';

/// Brand Guide routing-theme swatches (Brand Guide.md "Routing Theme Semantics").
const _themeColors = <RouteTheme, Color>{
  RouteTheme.flattest: Color(0xFF1E5E60), // River Valley Teal
  RouteTheme.mostClimbing: Color(0xFFB85A38), // Ridge Line Terracotta
  RouteTheme.lowestTraffic: Color(0xFF2D5236), // Serene Forest Green
  RouteTheme.fewestTurns: Color(0xFF2E5B88), // Linear Horizon Blue
  RouteTheme.mostArt: Color(0xFF722F37), // Curated Burgundy
};

/// flutter_map over self-hosted tiles (ROADMAP.md Leg 2 learning goal) — the
/// client only ever talks to ctp-service for tiles (RoutingClient.tileUrlTemplate),
/// never a third-party host directly.
class RouteMap extends ConsumerWidget {
  const RouteMap({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(routingClientProvider);
    final route = ref.watch(routeGenerationProvider).value;
    final start = ref.watch(startPointProvider);
    final destination = ref.watch(destinationPointProvider);
    final shape = ref.watch(selectedShapeProvider);

    return FlutterMap(
      options: MapOptions(
        initialCenter: const ll.LatLng(35.6841, -82.0091), // Marion, NC (PRD default)
        initialZoom: 13,
        onTap: (_, point) {
          final settingDestination = shape == RouteShape.pointToPoint && start != null;
          final provider = settingDestination ? destinationPointProvider : startPointProvider;
          ref.read(provider.notifier).state = domain.LatLon(point.latitude, point.longitude);
        },
      ),
      children: [
        TileLayer(
          urlTemplate: client.tileUrlTemplate,
          userAgentPackageName: 'com.cycletourplanner.client',
        ),
        if (route != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: route.coords.map((c) => ll.LatLng(c.lat, c.lon)).toList(),
                strokeWidth: 4,
                color: _themeColors[route.theme] ?? Colors.blue,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (start != null)
              Marker(
                point: ll.LatLng(start.lat, start.lon),
                width: 32,
                height: 32,
                child: const Icon(Icons.trip_origin, color: Colors.green),
              ),
            if (destination != null)
              Marker(
                point: ll.LatLng(destination.lat, destination.lon),
                width: 32,
                height: 32,
                child: const Icon(Icons.flag, color: Colors.red),
              ),
          ],
        ),
      ],
    );
  }
}
