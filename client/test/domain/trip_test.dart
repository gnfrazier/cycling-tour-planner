import 'package:client/domain/route.dart';
import 'package:client/domain/theme.dart';
import 'package:client/domain/trip.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _fakeDayJson({int index = 0}) => {
      'index': index,
      'coords': [
        {'lat': 35.68, 'lon': -82.01},
        {'lat': 35.7, 'lon': -82.05},
      ],
      'distance_m': 48000.0,
      'elevation_gain_m': 365.0,
      'surface_breakdown_m': {'asphalt': 40000.0, 'gravel': 8000.0},
      'lodging_options': [
        {
          'name': 'Boone Inn',
          'kind': 'hotel',
          'coord': {'lat': 35.7, 'lon': -82.05},
          'distance_from_day_end_m': 120.0,
        },
      ],
      'weather': {
        'month': 9,
        'day': 12,
        'temp_min_c': 12.0,
        'temp_max_c': 22.0,
        'apparent_temp_c': 21.0,
        'wind_speed_kph': 10.0,
        'wind_direction_deg': 270.0,
        'precip_probability_pct': 15.0,
        'precip_timing': 'afternoon',
        'years_averaged': 10,
        'pm2_5': 8.0,
        'pm10': null,
        'o3': null,
        'no2': null,
        'uv_index': 6.0,
        'pollen': {'tree': 2.0},
      },
      'regroup_cautions': ['Narrow/unpaved stretch near km 18.0-20.0 — consider regroup points for larger groups.'],
    };

Map<String, dynamic> _fakeTripJson() => {
      'id': 'trip-1',
      'waypoints': [
        {
          'coord': {'lat': 35.68, 'lon': -82.01},
        },
        {
          'coord': {'lat': 35.7, 'lon': -82.05},
          'label': 'Boone, NC',
        },
      ],
      'theme': 'flattest',
      'rider_band': 'small_group',
      'start_date': '2026-09-12',
      'days': [_fakeDayJson()],
      'total_distance_m': 48000.0,
      'total_elevation_gain_m': 365.0,
    };

void main() {
  test('TripResult.fromJson parses a ctp-service TripResponse body', () {
    final trip = TripResult.fromJson(_fakeTripJson());

    expect(trip.id, 'trip-1');
    expect(trip.waypoints, hasLength(2));
    expect(trip.waypoints[1].label, 'Boone, NC');
    expect(trip.theme, RouteTheme.flattest);
    expect(trip.riderBand, RiderBand.smallGroup);
    expect(trip.startDate, DateTime(2026, 9, 12));
    expect(trip.days, hasLength(1));
    expect(trip.totalDistanceKm, closeTo(48.0, 1e-9));
  });

  test('TripDay.fromJson parses lodging, weather, and regroup cautions', () {
    final day = TripDay.fromJson(_fakeDayJson());

    expect(day.distanceKm, closeTo(48.0, 1e-9));
    expect(day.lodgingOptions, hasLength(1));
    expect(day.lodgingOptions.first.name, 'Boone Inn');
    expect(day.weather, isNotNull);
    expect(day.weather!.tempMinC, 12.0);
    expect(day.weather!.pm10, isNull);
    expect(day.weather!.pollen, {'tree': 2.0});
    expect(day.regroupCautions, hasLength(1));
    expect(day.surfaceBreakdownM, {'asphalt': 40000.0, 'gravel': 8000.0});
  });

  test('a day with no weather parses weather as null, not a crash', () {
    final json = _fakeDayJson()..['weather'] = null;
    final day = TripDay.fromJson(json);
    expect(day.weather, isNull);
  });

  test('TripResult.copyWithDay replaces one day and recomputes totals', () {
    final trip = TripResult.fromJson(_fakeTripJson());
    final replacement = TripDay(
      index: 0,
      coords: const [LatLon(35.68, -82.01), LatLon(35.9, -82.1)],
      distanceM: 60000.0,
      elevationGainM: 900.0,
    );

    final updated = trip.copyWithDay(0, replacement);

    expect(updated.days.first.distanceM, 60000.0);
    expect(updated.totalDistanceM, 60000.0);
    expect(updated.totalElevationGainM, 900.0);
    // Original is untouched.
    expect(trip.totalDistanceM, 48000.0);
  });

  test('DayAlternative.fromJson parses current and alternative days', () {
    final json = {'current': _fakeDayJson(index: 0), 'alternative': _fakeDayJson(index: 0)};
    final alt = DayAlternative.fromJson(json);
    expect(alt.current.distanceM, alt.alternative.distanceM);
  });

  test('rider band api values round-trip through fromApiValue', () {
    for (final band in RiderBand.values) {
      expect(RiderBand.fromApiValue(band.apiValue), band);
    }
  });

  test('an unrecognized rider band throws a clear FormatException', () {
    expect(() => RiderBand.fromApiValue('not_a_real_band'), throwsFormatException);
  });

  test('WeightOverrideInput.toJson omits null segment bounds', () {
    const override = WeightOverrideInput(dayIndex: 1, elevationGain: 0.5, surfacePreference: -0.2);
    final json = override.toJson();
    expect(json.containsKey('segment_start_km'), isFalse);
    expect(json.containsKey('segment_end_km'), isFalse);
    expect(json['day_index'], 1);
  });

  test('WeightOverrideInput.toJson includes segment bounds when set', () {
    const override = WeightOverrideInput(dayIndex: 1, segmentStartKm: 18.0, segmentEndKm: 34.0);
    final json = override.toJson();
    expect(json['segment_start_km'], 18.0);
    expect(json['segment_end_km'], 34.0);
  });
}
