import 'dart:async';
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

/// FR49 — reverts every planning control to its declared default and clears
/// any generated route, so the rider can back out of an in-progress plan
/// without individually re-toggling each control.
void _resetControls(WidgetRef ref) {
  ref.read(selectedThemeProvider.notifier).state = RouteTheme.flattest;
  ref.read(selectedShapeProvider.notifier).state = RouteShape.loop;
  ref.read(startPointProvider.notifier).state = null;
  ref.read(destinationPointProvider.notifier).state = null;
  ref.read(targetDistanceKmProvider.notifier).state = 20.0;
  ref.read(routeGenerationProvider.notifier).clear();
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
        loading: () => const _StartupWait(),
        error: (err, _) => Center(child: Text('Could not reach the routing engine: $err')),
        data: (_) => const _PlannerBody(),
      ),
    );
  }
}

/// FR48: escalating cycling-themed messages while the backend cold-starts,
/// rather than a bare spinner or a false "failed to start" after a fixed
/// timeout. Short waits look like ordinary pre-ride prep; long waits shift
/// to the kind of small mishap that delays an actual ride.
const _startupMessages = <(int, String)>[
  (0, 'Filling up bottles…'),
  (8, 'Airing up the tires…'),
  (16, 'Lubing the chain…'),
  (26, 'Double-checking the route sheet…'),
  (40, 'Digging the good pump out of the garage…'),
  (60, "Can't find the tire levers…"),
  (90, 'Untangling the spare tube from the bottom of the toolbox…'),
  (130, 'Convincing the dog you really are leaving this time…'),
];

class _StartupWait extends StatefulWidget {
  const _StartupWait();

  @override
  State<_StartupWait> createState() => _StartupWaitState();
}

class _StartupWaitState extends State<_StartupWait> {
  int _elapsedSeconds = 0;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _elapsedSeconds++),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message =
        _startupMessages.lastWhere((m) => m.$1 <= _elapsedSeconds).$2;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
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
                    onSelectionChanged: (selection) {
                      final newShape = selection.first;
                      ref.read(selectedShapeProvider.notifier).state = newShape;
                      if (newShape != RouteShape.pointToPoint) {
                        ref.read(destinationPointProvider.notifier).state = null;
                      }
                    },
                  ),
                  if (shape != RouteShape.pointToPoint) ...[
                    const SizedBox(height: 16),
                    Text('Target distance: ${targetKm.toStringAsFixed(0)} km'),
                    Slider(
                      value: targetDistanceStepsKm.indexOf(targetKm).clamp(0, targetDistanceStepsKm.length - 1).toDouble(),
                      min: 0,
                      max: (targetDistanceStepsKm.length - 1).toDouble(),
                      divisions: targetDistanceStepsKm.length - 1,
                      label: '${targetKm.toStringAsFixed(0)} km',
                      onChanged: (v) => ref.read(targetDistanceKmProvider.notifier).state =
                          targetDistanceStepsKm[v.round()],
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text('Theme', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const ThemePicker(),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: routeAsync.isLoading
                            ? null
                            : () => ref.read(routeGenerationProvider.notifier).generate(),
                        child: Text(routeAsync.isLoading ? 'Generating…' : 'Generate route'),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Reset'),
                        onPressed: () => _resetControls(ref),
                      ),
                    ],
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
