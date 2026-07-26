import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/theme.dart';
import '../../domain/trip.dart';
import '../../state/routing_providers.dart';
import '../../state/trip_providers.dart';

/// Same save-to-disk pattern as route_planner_screen.dart's _exportRoute,
/// parameterized for a single day of a trip (`/trips/{id}/days/{i}/export`)
/// rather than a whole single-generated route.
Future<void> _exportDay(
  BuildContext context,
  WidgetRef ref,
  String tripId,
  int dayIndex,
  ExportFormat format,
) async {
  final client = ref.read(routingClientProvider);
  try {
    final bytes = await client.exportDay(tripId, dayIndex, format);
    final location = await getSaveLocation(
      suggestedName: 'day${dayIndex + 1}.${format.apiValue}',
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

/// Wireframes 9a/10a — FR13's day/segment weighting sliders plus FR42's
/// propose → compare → take/keep/save-variant flow, for whichever day is
/// selected in the DayTimeline.
class DayWeightingPanel extends ConsumerWidget {
  const DayWeightingPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dayIndex = ref.watch(selectedDayIndexProvider);
    final trip = ref.watch(tripGenerationProvider).value;
    if (dayIndex == null || trip == null || dayIndex >= trip.days.length) {
      return const SizedBox.shrink();
    }

    final alternativeAsync = ref.watch(dayAlternativeProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Day ${dayIndex + 1} weighting', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ExportFormat.values
                .map((fmt) => OutlinedButton(
                      onPressed: () => _exportDay(context, ref, trip.id, dayIndex, fmt),
                      child: Text('Export ${fmt.label}'),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          const _DaySliders(),
          const SizedBox(height: 8),
          // Keyed by day so switching days doesn't leave stale typed text in
          // an uncontrolled TextField behind — DayAlternativeNotifier resets
          // the underlying providers on day change, but a fresh key is what
          // actually clears the widgets' own internal editing state.
          _SegmentBoundsFields(key: ValueKey(dayIndex)),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: alternativeAsync.isLoading
                ? null
                : () => ref.read(dayAlternativeProvider.notifier).propose(),
            child: Text(alternativeAsync.isLoading ? 'Proposing…' : 'Propose alternative'),
          ),
          alternativeAsync.when(
            data: (alt) =>
                alt == null ? const SizedBox.shrink() : _ComparePanel(dayIndex: dayIndex, alternative: alt),
            loading: () => const SizedBox.shrink(),
            error: (err, _) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(err.toString(), style: const TextStyle(color: Colors.red)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DaySliders extends ConsumerWidget {
  const _DaySliders();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final elevationGain = ref.watch(dayOverrideElevationGainProvider);
    final surfacePreference = ref.watch(dayOverrideSurfacePreferenceProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Elevation for this day: ${elevationGain.toStringAsFixed(1)}'),
        Slider(
          value: elevationGain,
          min: -1,
          max: 1,
          divisions: 20,
          label: elevationGain.toStringAsFixed(1),
          onChanged: (v) => ref.read(dayOverrideElevationGainProvider.notifier).state = v,
        ),
        Text('Surface for this day: ${surfacePreference.toStringAsFixed(1)}'),
        Slider(
          value: surfacePreference,
          min: -1,
          max: 1,
          divisions: 20,
          label: surfacePreference.toStringAsFixed(1),
          onChanged: (v) => ref.read(dayOverrideSurfacePreferenceProvider.notifier).state = v,
        ),
      ],
    );
  }
}

/// Blank on either field means "whole day" — matches the backend's
/// `segment_start_km`/`segment_end_km` None-means-whole-day contract.
class _SegmentBoundsFields extends ConsumerWidget {
  const _SegmentBoundsFields({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Segment start km',
              hintText: 'whole day',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (text) =>
                ref.read(dayOverrideSegmentStartKmProvider.notifier).state = double.tryParse(text),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Segment end km',
              hintText: 'whole day',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (text) =>
                ref.read(dayOverrideSegmentEndKmProvider.notifier).state = double.tryParse(text),
          ),
        ),
      ],
    );
  }
}

/// PRD §6-style breakdown summary, same shape as route_planner_screen's
/// _formatBreakdown but scoped to this smaller compare table.
String _formatBreakdown(Map<String, double> breakdownM) {
  final total = breakdownM.values.fold(0.0, (sum, m) => sum + m);
  if (total <= 0) return 'unknown';
  final sorted = breakdownM.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return sorted.take(2).map((e) => '${e.key.replaceAll('_', ' ')} ${(e.value / total * 100).round()}%').join(', ');
}

// Same ghost/bold pair TripMap draws on the map for a proposal (grey dashed
// "current", bold deepOrange "proposed") -- the legend dots here use the
// same two colors so the sidebar and the map read as one comparison.
const _currentColor = Colors.grey;
const _proposedColor = Colors.deepOrange;

/// Wireframe 10a — right-sidebar "COMPARE SEGMENT" card: a current/proposed
/// legend, a current-vs-proposed-vs-delta stat table, a caution banner when
/// the proposal flags one, and a primary "Take" action with Keep/Save as
/// secondary actions underneath it (not a flat row of three equal buttons).
class _ComparePanel extends ConsumerWidget {
  final int dayIndex;
  final DayAlternative alternative;

  const _ComparePanel({required this.dayIndex, required this.alternative});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = alternative.current;
    final proposed = alternative.alternative;
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Compare segment', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: const [
              _LegendDot(color: _currentColor, label: 'Current', dashed: true),
              SizedBox(width: 16),
              _LegendDot(color: _proposedColor, label: 'Proposed', dashed: false),
            ],
          ),
          const SizedBox(height: 8),
          _CompareRow(
            label: 'Distance',
            current: '${current.distanceKm.toStringAsFixed(1)} km',
            proposed: '${proposed.distanceKm.toStringAsFixed(1)} km',
            deltaText: _formatDelta(proposed.distanceKm - current.distanceKm, suffix: ' km'),
          ),
          _CompareRow(
            label: 'Climbing',
            current: '${current.elevationGainM.toStringAsFixed(0)} m',
            proposed: '${proposed.elevationGainM.toStringAsFixed(0)} m',
            deltaText: _formatDelta(proposed.elevationGainM - current.elevationGainM, suffix: ' m'),
          ),
          _CompareRow(
            label: 'Surface',
            current: _formatBreakdown(current.surfaceBreakdownM),
            proposed: _formatBreakdown(proposed.surfaceBreakdownM),
          ),
          _CompareRow(
            label: 'Traffic',
            current: _formatBreakdown(current.trafficBreakdownM),
            proposed: _formatBreakdown(proposed.trafficBreakdownM),
          ),
          if (proposed.regroupCautions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                border: Border.all(color: Colors.amber.shade700),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                proposed.regroupCautions.join(' '),
                style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => ref.read(dayAlternativeProvider.notifier).applyActive(),
              child: const Text('Take proposed →'),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => ref.read(dayAlternativeProvider.notifier).discard(),
                  child: const Text('Keep current'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => ref.read(savedVariantsProvider.notifier).save(dayIndex, alternative),
                  child: const Text('Save as variant'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Signed delta, e.g. "+2.6 km" / "-4 m" -- omitted (returns null) when
/// effectively zero, since "current vs. proposed, identical" isn't worth a
/// "+0.0" callout.
String? _formatDelta(double delta, {required String suffix}) {
  if (delta.abs() < 0.05) return null;
  final sign = delta > 0 ? '+' : '';
  return '$sign${delta.toStringAsFixed(suffix == ' km' ? 1 : 0)}$suffix';
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool dashed;

  const _LegendDot({required this.color, required this.label, required this.dashed});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: dashed ? Colors.transparent : color,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: dashed ? 2 : 0),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _CompareRow extends StatelessWidget {
  final String label;
  final String current;
  final String proposed;
  final String? deltaText;

  const _CompareRow({required this.label, required this.current, required this.proposed, this.deltaText});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 60, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(current, style: const TextStyle(color: Colors.grey))),
          const Icon(Icons.arrow_forward, size: 14),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(proposed, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (deltaText != null)
                  Text(deltaText!, style: TextStyle(fontSize: 11, color: Colors.deepOrange.shade400)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
