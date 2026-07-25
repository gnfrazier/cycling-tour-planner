import 'package:flutter/material.dart';

/// Shared zoom-in/zoom-out control, floated over a `flutter_map` — used by
/// both the single-route map (`RouteMap`) and the multi-day trip map
/// (`TripMap`).
class MapZoomControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  const MapZoomControls({super.key, required this.onZoomIn, required this.onZoomOut});

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
