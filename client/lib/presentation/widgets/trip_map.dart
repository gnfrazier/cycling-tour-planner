import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../domain/route.dart' as domain;
import '../../presentation/theme_colors.dart';
import '../../state/routing_providers.dart';
import '../../state/trip_providers.dart';
import 'map_zoom_controls.dart';

// Matches the sidecar's /tiles/{z}/{x}/{y} bounds check (ctp_service/app.py) —
// same bounds RouteMap already uses.
const _minZoom = 1.0;
const _maxZoom = 19.0;

/// Multi-day counterpart to RouteMap: renders the waypoint chain (FR10), one
/// polyline per generated trip day, and — while a day alternative (FR42) is
/// being proposed — that day's current path as a dashed ghost alongside the
/// proposed path drawn bold, per wireframe 10a.
class TripMap extends ConsumerStatefulWidget {
  const TripMap({super.key});

  @override
  ConsumerState<TripMap> createState() => _TripMapState();
}

class _TripMapState extends ConsumerState<TripMap> {
  final MapController _mapController = MapController();

  void _zoomBy(double delta) {
    final camera = _mapController.camera;
    final newZoom = (camera.zoom + delta).clamp(_minZoom, _maxZoom);
    _mapController.move(camera.center, newZoom);
  }

  /// Same "only move if genuinely out of view" rule RouteMap uses, extended
  /// to an arbitrary-length waypoint chain.
  void _ensureWaypointsVisible() {
    final waypoints = ref.read(waypointsProvider);
    final points = waypoints.map((w) => ll.LatLng(w.coord.lat, w.coord.lon)).toList();
    if (points.isEmpty) return;

    final visible = _mapController.camera.visibleBounds;
    if (points.length == 1) {
      if (!visible.contains(points.first)) {
        _mapController.move(points.first, _mapController.camera.zoom);
      }
      return;
    }
    final bounds = LatLngBounds.fromPoints(points);
    if (!visible.containsBounds(bounds)) {
      _mapController.fitCamera(CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)));
    }
  }

  void _handleTap(domain.LatLon point) {
    final activeSlot = ref.read(activeWaypointSlotProvider);
    if (activeSlot != null) {
      ref.read(waypointsProvider.notifier).updateAt(activeSlot, point);
      ref.read(activeWaypointSlotProvider.notifier).state = null;
    } else {
      ref.read(waypointsProvider.notifier).add(point);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(routingClientProvider);
    final waypoints = ref.watch(waypointsProvider);
    final trip = ref.watch(tripGenerationProvider).value;
    final alternative = ref.watch(dayAlternativeProvider).value;
    final selectedDayIndex = ref.watch(selectedDayIndexProvider);

    ref.listen(waypointsProvider, (_, _) => _ensureWaypointsVisible());

    final dayColors = themeColors.values.toList();

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: const ll.LatLng(35.6841, -82.0091), // Marion, NC (PRD default)
            initialZoom: 13,
            minZoom: _minZoom,
            maxZoom: _maxZoom,
            onTap: (_, point) => _handleTap(domain.LatLon(point.latitude, point.longitude)),
          ),
          children: [
            TileLayer(
              urlTemplate: client.tileUrlTemplate,
              userAgentPackageName: 'com.cycletourplanner.client',
            ),
            if (trip != null)
              PolylineLayer(
                polylines: [
                  for (final day in trip.days)
                    if (!(alternative != null && day.index == selectedDayIndex))
                      Polyline(
                        points: day.coords.map((c) => ll.LatLng(c.lat, c.lon)).toList(),
                        strokeWidth: 4,
                        color: dayColors[day.index % dayColors.length],
                      ),
                  // FR42 — current as a ghost (dashed), proposed bold.
                  if (alternative != null) ...[
                    Polyline(
                      points: alternative.current.coords.map((c) => ll.LatLng(c.lat, c.lon)).toList(),
                      strokeWidth: 3,
                      color: Colors.grey,
                      pattern: StrokePattern.dashed(segments: const [8, 6]),
                    ),
                    Polyline(
                      points: alternative.alternative.coords.map((c) => ll.LatLng(c.lat, c.lon)).toList(),
                      strokeWidth: 5,
                      color: Colors.deepOrange,
                    ),
                  ],
                ],
              ),
            MarkerLayer(
              markers: [
                for (var i = 0; i < waypoints.length; i++)
                  Marker(
                    point: ll.LatLng(waypoints[i].coord.lat, waypoints[i].coord.lon),
                    width: 28,
                    height: 28,
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(color: Theme.of(context).colorScheme.onPrimary, fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: MapZoomControls(onZoomIn: () => _zoomBy(1), onZoomOut: () => _zoomBy(-1)),
        ),
      ],
    );
  }
}
