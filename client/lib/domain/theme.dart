/// The five MVP routing themes (FR1-FR5). Pure domain enum, no I/O.
enum RouteTheme {
  flattest,
  mostClimbing,
  lowestTraffic,
  fewestTurns,
  mostArt;

  String get apiValue => switch (this) {
        RouteTheme.flattest => 'flattest',
        RouteTheme.mostClimbing => 'most_climbing',
        RouteTheme.lowestTraffic => 'lowest_traffic',
        RouteTheme.fewestTurns => 'fewest_turns',
        RouteTheme.mostArt => 'most_art',
      };

  String get label => switch (this) {
        RouteTheme.flattest => 'Flattest',
        RouteTheme.mostClimbing => 'Most Climbing',
        RouteTheme.lowestTraffic => 'Lowest Traffic',
        RouteTheme.fewestTurns => 'Fewest Turns',
        RouteTheme.mostArt => 'Most Art & History',
      };

  static RouteTheme fromApiValue(String value) =>
      RouteTheme.values.firstWhere((t) => t.apiValue == value);
}

/// Route shape (FR35). Independent of theme.
enum RouteShape {
  loop,
  outAndBack,
  pointToPoint;

  String get apiValue => switch (this) {
        RouteShape.loop => 'loop',
        RouteShape.outAndBack => 'out_and_back',
        RouteShape.pointToPoint => 'point_to_point',
      };

  String get label => switch (this) {
        RouteShape.loop => 'Loop',
        RouteShape.outAndBack => 'Out & Back',
        RouteShape.pointToPoint => 'Point to Point',
      };

  static RouteShape fromApiValue(String value) =>
      RouteShape.values.firstWhere((s) => s.apiValue == value);
}

enum ExportFormat {
  gpx,
  tcx,
  fit;

  String get apiValue => name;

  String get label => switch (this) {
        ExportFormat.gpx => 'GPX',
        ExportFormat.tcx => 'TCX',
        ExportFormat.fit => 'FIT',
      };
}
