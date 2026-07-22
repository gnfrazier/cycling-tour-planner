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
    return MaterialApp(
      title: 'Cycle Tour Planner',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A2332)), // Deep Slate Blue
        useMaterial3: true,
      ),
      home: const RoutePlannerScreen(),
    );
  }
}
