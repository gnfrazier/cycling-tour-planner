import 'route.dart';
import 'theme.dart';

/// FR46 — a trip's group size (mirrors ctp_core.types.RiderBand), coarse on
/// purpose: seeds day mileage/climb defaults and lodging sizing, and flags
/// narrow/gravel stretches for larger groups.
enum RiderBand {
  solo,
  smallGroup,
  largeGroup;

  String get apiValue => switch (this) {
        RiderBand.solo => 'solo',
        RiderBand.smallGroup => 'small_group',
        RiderBand.largeGroup => 'large_group',
      };

  String get label => switch (this) {
        RiderBand.solo => 'Solo',
        RiderBand.smallGroup => 'Small group',
        RiderBand.largeGroup => 'Large group',
      };

  static RiderBand fromApiValue(String value) => RiderBand.values.firstWhere(
        (b) => b.apiValue == value,
        orElse: () => throw FormatException('Unrecognized rider band from the backend: "$value"'),
      );
}

/// QA: waypoints labeled 1, 2, 3 read as ambiguous next to "Day 1, Day 2,
/// Day 3" — letters (A, B, C, ..., Z, AA, AB, ...) keep the two countable
/// things visually distinct. Spreadsheet-column style so it never runs out.
String waypointLetter(int index) {
  var n = index;
  var label = '';
  do {
    label = String.fromCharCode(65 + (n % 26)) + label;
    n = n ~/ 26 - 1;
  } while (n >= 0);
  return label;
}

/// FR10 — a point a multi-day trip must honor; the route still optimizes for
/// the selected theme between consecutive waypoints.
class Waypoint {
  final LatLon coord;
  final String? label;

  const Waypoint({required this.coord, this.label});

  Map<String, dynamic> toJson() => {
        'coord': coord.toJson(),
        if (label != null) 'label': label,
      };

  factory Waypoint.fromJson(Map<String, dynamic> json) => Waypoint(
        coord: LatLon(
          (json['coord']['lat'] as num).toDouble(),
          (json['coord']['lon'] as num).toDouble(),
        ),
        label: json['label'] as String?,
      );
}

/// FR13 — a day- or partial-day-segment-scoped weighting override, sent as
/// part of a trip-generate request. `segmentStartKm`/`segmentEndKm` null on
/// both means the whole day.
class WeightOverrideInput {
  final int dayIndex;
  final double elevationGain;
  final double surfacePreference;
  final double? segmentStartKm;
  final double? segmentEndKm;

  const WeightOverrideInput({
    required this.dayIndex,
    this.elevationGain = 0.0,
    this.surfacePreference = 0.0,
    this.segmentStartKm,
    this.segmentEndKm,
  });

  Map<String, dynamic> toJson() => {
        'day_index': dayIndex,
        'elevation_gain': elevationGain,
        'surface_preference': surfacePreference,
        if (segmentStartKm != null) 'segment_start_km': segmentStartKm,
        if (segmentEndKm != null) 'segment_end_km': segmentEndKm,
      };
}

/// FR14 — a lodging/campground option near a day's end point.
class LodgingOption {
  final String name;
  final String kind;
  final LatLon coord;
  final double distanceFromDayEndM;

  const LodgingOption({
    required this.name,
    required this.kind,
    required this.coord,
    required this.distanceFromDayEndM,
  });

  factory LodgingOption.fromJson(Map<String, dynamic> json) => LodgingOption(
        name: json['name'] as String,
        kind: json['kind'] as String,
        coord: LatLon(
          (json['coord']['lat'] as num).toDouble(),
          (json['coord']['lon'] as num).toDouble(),
        ),
        distanceFromDayEndM: (json['distance_from_day_end_m'] as num).toDouble(),
      );
}

/// FR15 — seasonal-norms weather for one day of a trip, averaged over
/// several past years at the same calendar day.
class WeatherSummary {
  final int month;
  final int day;
  final double tempMinC;
  final double tempMaxC;
  final double apparentTempC;
  final double windSpeedKph;
  final double windDirectionDeg;
  final double precipProbabilityPct;
  final String? precipTiming;
  final int yearsAveraged;
  final double? pm25;
  final double? pm10;
  final double? o3;
  final double? no2;
  final double? uvIndex;
  final Map<String, double>? pollen;

  const WeatherSummary({
    required this.month,
    required this.day,
    required this.tempMinC,
    required this.tempMaxC,
    required this.apparentTempC,
    required this.windSpeedKph,
    required this.windDirectionDeg,
    required this.precipProbabilityPct,
    this.precipTiming,
    required this.yearsAveraged,
    this.pm25,
    this.pm10,
    this.o3,
    this.no2,
    this.uvIndex,
    this.pollen,
  });

  factory WeatherSummary.fromJson(Map<String, dynamic> json) => WeatherSummary(
        month: json['month'] as int,
        day: json['day'] as int,
        tempMinC: (json['temp_min_c'] as num).toDouble(),
        tempMaxC: (json['temp_max_c'] as num).toDouble(),
        apparentTempC: (json['apparent_temp_c'] as num).toDouble(),
        windSpeedKph: (json['wind_speed_kph'] as num).toDouble(),
        windDirectionDeg: (json['wind_direction_deg'] as num).toDouble(),
        precipProbabilityPct: (json['precip_probability_pct'] as num).toDouble(),
        precipTiming: json['precip_timing'] as String?,
        yearsAveraged: json['years_averaged'] as int,
        pm25: (json['pm2_5'] as num?)?.toDouble(),
        pm10: (json['pm10'] as num?)?.toDouble(),
        o3: (json['o3'] as num?)?.toDouble(),
        no2: (json['no2'] as num?)?.toDouble(),
        uvIndex: (json['uv_index'] as num?)?.toDouble(),
        pollen: (json['pollen'] as Map<String, dynamic>?)
            ?.map((key, value) => MapEntry(key, (value as num).toDouble())),
      );
}

Map<String, double> _parseBreakdown(dynamic raw) {
  if (raw == null) return const {};
  return (raw as Map<String, dynamic>).map((key, value) => MapEntry(key, (value as num).toDouble()));
}

/// One day of a multi-day Trip (mirrors ctp_core.types.Day / ctp_service
/// DayModel). Named TripDay, not Day, to avoid reading like a core Dart type.
class TripDay {
  final int index;
  final List<LatLon> coords;
  final double distanceM;
  final double elevationGainM;
  final Map<String, double> surfaceBreakdownM;
  final Map<String, double> trafficBreakdownM;
  final List<LodgingOption> lodgingOptions;
  final WeatherSummary? weather;
  final List<String> regroupCautions;

  const TripDay({
    required this.index,
    required this.coords,
    required this.distanceM,
    required this.elevationGainM,
    this.surfaceBreakdownM = const {},
    this.trafficBreakdownM = const {},
    this.lodgingOptions = const [],
    this.weather,
    this.regroupCautions = const [],
  });

  double get distanceKm => distanceM / 1000;

  factory TripDay.fromJson(Map<String, dynamic> json) => TripDay(
        index: json['index'] as int,
        coords: (json['coords'] as List)
            .map((c) => LatLon((c['lat'] as num).toDouble(), (c['lon'] as num).toDouble()))
            .toList(),
        distanceM: (json['distance_m'] as num).toDouble(),
        elevationGainM: (json['elevation_gain_m'] as num).toDouble(),
        surfaceBreakdownM: _parseBreakdown(json['surface_breakdown_m']),
        trafficBreakdownM: _parseBreakdown(json['traffic_breakdown_m']),
        lodgingOptions: (json['lodging_options'] as List? ?? [])
            .map((o) => LodgingOption.fromJson(o as Map<String, dynamic>))
            .toList(),
        weather: json['weather'] == null
            ? null
            : WeatherSummary.fromJson(json['weather'] as Map<String, dynamic>),
        regroupCautions: (json['regroup_cautions'] as List? ?? []).cast<String>(),
      );
}

/// A generated multi-day trip (mirrors ctp_core.types.Trip / ctp_service
/// TripResponse).
class TripResult {
  final String id;
  final List<Waypoint> waypoints;
  final RouteTheme theme;
  final RiderBand riderBand;
  final DateTime startDate;
  final List<TripDay> days;
  final double totalDistanceM;
  final double totalElevationGainM;

  const TripResult({
    required this.id,
    required this.waypoints,
    required this.theme,
    required this.riderBand,
    required this.startDate,
    required this.days,
    required this.totalDistanceM,
    required this.totalElevationGainM,
  });

  double get totalDistanceKm => totalDistanceM / 1000;

  TripResult copyWithDay(int index, TripDay day) {
    final newDays = List<TripDay>.from(days);
    newDays[index] = day;
    return TripResult(
      id: id,
      waypoints: waypoints,
      theme: theme,
      riderBand: riderBand,
      startDate: startDate,
      days: newDays,
      totalDistanceM: newDays.fold(0.0, (sum, d) => sum + d.distanceM),
      totalElevationGainM: newDays.fold(0.0, (sum, d) => sum + d.elevationGainM),
    );
  }

  factory TripResult.fromJson(Map<String, dynamic> json) => TripResult(
        id: json['id'] as String,
        waypoints: (json['waypoints'] as List)
            .map((w) => Waypoint.fromJson(w as Map<String, dynamic>))
            .toList(),
        theme: RouteTheme.fromApiValue(json['theme'] as String),
        riderBand: RiderBand.fromApiValue(json['rider_band'] as String),
        startDate: DateTime.parse(json['start_date'] as String),
        days: (json['days'] as List).map((d) => TripDay.fromJson(d as Map<String, dynamic>)).toList(),
        totalDistanceM: (json['total_distance_m'] as num).toDouble(),
        totalElevationGainM: (json['total_elevation_gain_m'] as num).toDouble(),
      );
}

/// FR42 — current vs. proposed day, for a ghost-vs-bold client comparison.
class DayAlternative {
  final TripDay current;
  final TripDay alternative;

  const DayAlternative({required this.current, required this.alternative});

  factory DayAlternative.fromJson(Map<String, dynamic> json) => DayAlternative(
        current: TripDay.fromJson(json['current'] as Map<String, dynamic>),
        alternative: TripDay.fromJson(json['alternative'] as Map<String, dynamic>),
      );
}
