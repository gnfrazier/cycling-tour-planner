import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/theme.dart';
import '../../state/routing_providers.dart';

class ThemePicker extends ConsumerWidget {
  const ThemePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedThemeProvider);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: RouteTheme.values.map((theme) {
        return ChoiceChip(
          label: Text(theme.label),
          selected: selected == theme,
          onSelected: (_) => ref.read(selectedThemeProvider.notifier).state = theme,
        );
      }).toList(),
    );
  }
}
