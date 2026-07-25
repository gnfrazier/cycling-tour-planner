import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'presentation/screens/route_planner_screen.dart';

void main() {
  runApp(const ProviderScope(child: CycleTourPlannerApp()));
}

class CycleTourPlannerApp extends StatelessWidget {
  const CycleTourPlannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    // PRD §6 / Brand Guide "Interface Adaptability": Desktop defaults to
    // Indoor Contrast and should track the OS's light/dark setting, one of
    // the signals the adaptive system reads. This covers just that —
    // Indoor Contrast in both brightnesses. The separate Outdoor Contrast
    // mode (Absolute Obsidian, high-contrast monochrome, Mobile's default)
    // and the account-synced manual override are a larger, Mobile-scoped
    // feature, not part of this Desktop client yet.
    const seedColor = Color(0xFF1A2332); // Deep Slate Blue
    return MaterialApp(
      title: 'Cycle Tour Planner',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const RoutePlannerScreen(),
    );
  }
}
