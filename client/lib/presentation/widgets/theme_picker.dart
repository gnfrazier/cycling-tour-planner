import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/theme.dart';
import '../../state/routing_providers.dart';
import '../theme_colors.dart';

class ThemePicker extends ConsumerWidget {
  const ThemePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedThemeProvider);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: RouteTheme.values.map((theme) {
        final color = themeColors[theme];
        return ChoiceChip(
          label: Text(theme.label),
          selected: selected == theme,
          onSelected: (_) => ref.read(selectedThemeProvider.notifier).state = theme,
          // Same swatch the map polyline uses for this theme (Brand Guide
          // "Routing Theme Semantics") — lets a rider learn the color
          // language from the control that sets it, not only after
          // generating a route.
          avatar: color == null ? null : CircleAvatar(backgroundColor: color, radius: 8),
          selectedColor: color?.withValues(alpha: 0.25),
          side: color == null ? null : BorderSide(color: color),
        );
      }).toList(),
    );
  }
}
