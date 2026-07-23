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

// Matches the sidecar's /tiles/{z}/{x}/{y} bounds check (ctp_service/app.py).
const _minZoom = 1.0;
const _maxZoom = 19.0;

/// flutter_map over self-hosted tiles (ROADMAP.md Leg 2 learning goal) — the
/// client only ever talks to ctp-service for tiles (RoutingClient.tileUrlTemplate),
/// never a third-party host directly.
class RouteMap extends ConsumerStatefulWidget {
  const RouteMap({super.key});

  @override
  ConsumerState<RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends ConsumerState<RouteMap> {
  final MapController _mapController = MapController();

  void _zoomBy(double delta) {
    final camera = _mapController.camera;
    final newZoom = (camera.zoom + delta).clamp(_minZoom, _maxZoom);
    _mapController.move(camera.center, newZoom);
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(routingClientProvider);
    final route = ref.watch(routeGenerationProvider).value;
    final start = ref.watch(startPointProvider);
    final destination = ref.watch(destinationPointProvider);
    final shape = ref.watch(selectedShapeProvider);

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: const ll.LatLng(35.6841, -82.0091), // Marion, NC (PRD default)
            initialZoom: 13,
            minZoom: _minZoom,
            maxZoom: _maxZoom,
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
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: _ZoomControls(onZoomIn: () => _zoomBy(1), onZoomOut: () => _zoomBy(-1)),
        ),
      ],
    );
  }
}

class _ZoomControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  const _ZoomControls({required this.onZoomIn, required this.onZoomOut});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Zoom in',
            onPressed: onZoomIn,
          ),
          const Divider(height: 1),
          IconButton(
            icon: const Icon(Icons.remove),
            tooltip: 'Zoom out',
            onPressed: onZoomOut,
          ),
        ],
      ),
    );
  }
}
