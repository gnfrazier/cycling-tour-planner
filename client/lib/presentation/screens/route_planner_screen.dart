import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/route.dart';
import '../../domain/theme.dart';
import '../../state/routing_providers.dart';
import '../widgets/route_map.dart';
import '../widgets/search_bar.dart';
import '../widgets/theme_picker.dart';
import 'manage_data_screen.dart';

Future<void> _exportRoute(
  BuildContext context,
  WidgetRef ref,
  RouteResult route,
  ExportFormat format,
) async {
  final client = ref.read(routingClientProvider);
  try {
    final bytes = await client.exportRoute(route.id, format);
    final location = await getSaveLocation(
      suggestedName: 'route-${route.theme.apiValue}-${route.shape.apiValue}.${format.apiValue}',
    );
    if (location == null) return;
    await File(location.path).writeAsBytes(bytes);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved ${format.label} to ${location.path}')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }
}

class RoutePlannerScreen extends ConsumerWidget {
  const RoutePlannerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(backendReadyProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cycle Tour Planner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.storage),
            tooltip: 'Manage downloaded data',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ManageDataScreen())),
          ),
        ],
      ),
      body: ready.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Could not reach the routing engine: $err')),
        data: (isReady) {
          if (!isReady) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Routing engine failed to start. Is the backend running?\n'
                  '(uv run fastapi dev main.py, from backend/)',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return const _PlannerBody();
        },
      ),
    );
  }
}

class _PlannerBody extends ConsumerWidget {
  const _PlannerBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shape = ref.watch(selectedShapeProvider);
    final targetKm = ref.watch(targetDistanceKmProvider);
    final routeAsync = ref.watch(routeGenerationProvider);

    return Row(
      children: [
        SizedBox(
          width: 340,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const GeocodeSearchField(label: 'Start', target: SearchTarget.start),
                  const SizedBox(height: 8),
                  if (shape == RouteShape.pointToPoint)
                    const GeocodeSearchField(label: 'Destination', target: SearchTarget.destination),
                  const Text('(or tap the map)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  const Text('Shape', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SegmentedButton<RouteShape>(
                    segments: RouteShape.values
                        .map((s) => ButtonSegment(value: s, label: Text(s.label)))
                        .toList(),
                    selected: {shape},
                    onSelectionChanged: (selection) =>
                        ref.read(selectedShapeProvider.notifier).state = selection.first,
                  ),
                  if (shape != RouteShape.pointToPoint) ...[
                    const SizedBox(height: 16),
                    Text('Target distance: ${targetKm.toStringAsFixed(1)} km'),
                    Slider(
                      value: targetKm,
                      min: 2,
                      max: 60,
                      divisions: 58,
                      label: '${targetKm.toStringAsFixed(1)} km',
                      onChanged: (v) => ref.read(targetDistanceKmProvider.notifier).state = v,
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text('Theme', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const ThemePicker(),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: routeAsync.isLoading
                        ? null
                        : () => ref.read(routeGenerationProvider.notifier).generate(),
                    child: Text(routeAsync.isLoading ? 'Generating…' : 'Generate route'),
                  ),
                  const SizedBox(height: 16),
                  routeAsync.when(
                    data: (route) => route == null
                        ? const SizedBox.shrink()
                        : _RouteSummary(
                            route: route,
                            onExport: (fmt) => _exportRoute(context, ref, route, fmt),
                          ),
                    loading: () => const SizedBox.shrink(),
                    error: (err, _) => Text(err.toString(), style: const TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        const Expanded(child: RouteMap()),
      ],
    );
  }
}

class _RouteSummary extends StatelessWidget {
  final RouteResult route;
  final void Function(ExportFormat) onExport;

  const _RouteSummary({required this.route, required this.onExport});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Distance: ${route.distanceKm.toStringAsFixed(1)} km'),
        Text('Elevation gain: ${route.elevationGainM.toStringAsFixed(0)} m'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: ExportFormat.values
              .map((fmt) => OutlinedButton(
                    onPressed: () => onExport(fmt),
                    child: Text('Export ${fmt.label}'),
                  ))
              .toList(),
        ),
      ],
    );
  }
}
