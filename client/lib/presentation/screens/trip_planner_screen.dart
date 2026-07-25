import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/trip.dart';
import '../../state/trip_providers.dart';
import '../widgets/day_timeline.dart';
import '../widgets/theme_picker.dart';
import '../widgets/trip_map.dart';
import '../widgets/waypoint_list.dart';

/// Leg 3 (M5) Desktop client — waypoints (FR10), daily splitting (FR11),
/// sliding-scale weighting (FR13), group-size-aware planning (FR46), Historical
/// Weather (FR15) and route alternatives (FR42) are all backend-complete
/// (`ctp_core/trips.py`); this screen is what makes them reachable from the app.
class TripPlannerScreen extends ConsumerWidget {
  const TripPlannerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripAsync = ref.watch(tripGenerationProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Plan a multi-day trip')),
      body: Row(
        children: [
          SizedBox(
            width: 340,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Waypoints', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const WaypointList(),
                    const SizedBox(height: 16),
                    const Text('Group size', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const _RiderBandPicker(),
                    const SizedBox(height: 16),
                    const _StartDatePicker(),
                    const SizedBox(height: 16),
                    const Text('Theme', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const ThemePicker(),
                    const SizedBox(height: 16),
                    const _TourWeightingSliders(),
                    const SizedBox(height: 8),
                    const _AdvancedDaySplit(),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: tripAsync.isLoading
                          ? null
                          : () => ref.read(tripGenerationProvider.notifier).generate(),
                      child: Text(tripAsync.isLoading ? 'Generating…' : 'Generate trip'),
                    ),
                    const SizedBox(height: 16),
                    tripAsync.when(
                      data: (trip) => trip == null
                          ? const SizedBox.shrink()
                          : Text(
                              '${trip.days.length} day(s) · ${trip.totalDistanceKm.toStringAsFixed(1)} km total',
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
          Expanded(
            child: Column(
              children: const [
                Expanded(child: TripMap()),
                DayTimeline(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RiderBandPicker extends ConsumerWidget {
  const _RiderBandPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final riderBand = ref.watch(riderBandProvider);
    return SegmentedButton<RiderBand>(
      segments: RiderBand.values.map((b) => ButtonSegment(value: b, label: Text(b.label))).toList(),
      selected: {riderBand},
      onSelectionChanged: (selection) => ref.read(riderBandProvider.notifier).state = selection.first,
    );
  }
}

class _StartDatePicker extends ConsumerWidget {
  const _StartDatePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startDate = ref.watch(tripStartDateProvider);
    return Row(
      children: [
        Expanded(child: Text('Start date: ${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}')),
        OutlinedButton(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: startDate,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 730)),
            );
            if (picked != null) {
              ref.read(tripStartDateProvider.notifier).state = picked;
            }
          },
          child: const Text('Change'),
        ),
      ],
    );
  }
}

/// FR13 — tour-default sliding-scale weighting, applied unless a day/segment
/// override takes over for that scope.
class _TourWeightingSliders extends ConsumerWidget {
  const _TourWeightingSliders();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final elevationGain = ref.watch(tripElevationGainProvider);
    final surfacePreference = ref.watch(tripSurfacePreferenceProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Tour weighting', style: TextStyle(fontWeight: FontWeight.bold)),
        Text('Elevation: ${elevationGain.toStringAsFixed(1)} (flatter ↔ more climbing)'),
        Slider(
          value: elevationGain,
          min: -1,
          max: 1,
          divisions: 20,
          label: elevationGain.toStringAsFixed(1),
          onChanged: (v) => ref.read(tripElevationGainProvider.notifier).state = v,
        ),
        Text('Surface: ${surfacePreference.toStringAsFixed(1)} (paved ↔ unpaved)'),
        Slider(
          value: surfacePreference,
          min: -1,
          max: 1,
          divisions: 20,
          label: surfacePreference.toStringAsFixed(1),
          onChanged: (v) => ref.read(tripSurfacePreferenceProvider.notifier).state = v,
        ),
      ],
    );
  }
}

/// FR11/FR46 — leaving both fields blank uses the rider-band default
/// (`default_day_split` server-side); entering a value overrides it.
class _AdvancedDaySplit extends ConsumerStatefulWidget {
  const _AdvancedDaySplit();

  @override
  ConsumerState<_AdvancedDaySplit> createState() => _AdvancedDaySplitState();
}

class _AdvancedDaySplitState extends ConsumerState<_AdvancedDaySplit> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final riderBand = ref.watch(riderBandProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton(
          onPressed: () => setState(() => _expanded = !_expanded),
          child: Text(_expanded ? 'Hide advanced' : 'Advanced (day-split caps)'),
        ),
        if (_expanded) ...[
          TextField(
            decoration: InputDecoration(
              labelText: 'Max daily km',
              hintText: '${riderBand.label} default',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (text) => ref.read(maxDailyKmProvider.notifier).state = double.tryParse(text),
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Max daily elevation gain (m)',
              hintText: 'no cap',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (text) => ref.read(maxDailyElevationMProvider.notifier).state = double.tryParse(text),
          ),
        ],
      ],
    );
  }
}
