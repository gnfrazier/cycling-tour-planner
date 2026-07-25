import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/trip.dart';
import '../../state/trip_providers.dart';

/// Wireframe 9a — horizontal day cards; tapping one opens/closes the
/// weighting panel (DayWeightingPanel) for that day.
class DayTimeline extends ConsumerWidget {
  const DayTimeline({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(tripGenerationProvider).value;
    if (trip == null) return const SizedBox.shrink();

    final selected = ref.watch(selectedDayIndexProvider);
    final savedVariants = ref.watch(savedVariantsProvider);

    return SizedBox(
      height: 144,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(8),
        itemCount: trip.days.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final day = trip.days[index];
          final isSelected = selected == index;
          return _DayCard(
            day: day,
            selected: isSelected,
            variantCount: savedVariants[day.index]?.length ?? 0,
            onTap: () =>
                ref.read(selectedDayIndexProvider.notifier).state = isSelected ? null : day.index,
          );
        },
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  final TripDay day;
  final bool selected;
  final int variantCount;
  final VoidCallback onTap;

  const _DayCard({
    required this.day,
    required this.selected,
    required this.variantCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lodging = day.lodgingOptions.isNotEmpty ? day.lodgingOptions.first.name : 'No lodging found nearby';
    final weather = day.weather;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Day ${day.index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(
              '${day.distanceKm.toStringAsFixed(0)} km · ↑${day.elevationGainM.toStringAsFixed(0)} m',
              style: const TextStyle(fontSize: 12),
            ),
            Text(lodging, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis, maxLines: 1),
            if (weather != null)
              Text(
                '${weather.tempMinC.toStringAsFixed(0)}–${weather.tempMaxC.toStringAsFixed(0)}°C',
                style: const TextStyle(fontSize: 12),
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                if (day.regroupCautions.isNotEmpty)
                  Text(
                    'Caution',
                    style: TextStyle(fontSize: 10, color: Colors.amber.shade800, fontWeight: FontWeight.bold),
                  ),
                if (variantCount > 0)
                  Text(
                    '$variantCount variant${variantCount == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 10, color: theme.colorScheme.primary),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
