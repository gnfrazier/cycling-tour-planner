import 'package:flutter/material.dart';

import '../domain/theme.dart';

/// Brand Guide "Routing Theme Semantics" swatches — shared between the
/// theme picker and the map polyline so a rider learns the color language
/// from the control that sets it, not only after generating a route.
/// Lives in presentation/, not domain/theme.dart, so the domain enum stays
/// free of a Flutter (Color) dependency.
const themeColors = <RouteTheme, Color>{
  RouteTheme.flattest: Color(0xFF1E5E60), // River Valley Teal
  RouteTheme.mostClimbing: Color(0xFFB85A38), // Ridge Line Terracotta
  RouteTheme.lowestTraffic: Color(0xFF2D5236), // Serene Forest Green
  RouteTheme.fewestTurns: Color(0xFF2E5B88), // Linear Horizon Blue
  RouteTheme.mostArt: Color(0xFF722F37), // Curated Burgundy
};
