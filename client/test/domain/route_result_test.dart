import 'package:client/domain/route.dart';
import 'package:client/domain/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RouteResult.fromJson parses a ctp-service RouteResponse body', () {
    final json = {
      'id': 'abc-123',
      'theme': 'most_climbing',
      'shape': 'out_and_back',
      'coords': [
        {'lat': 35.68, 'lon': -82.01},
        {'lat': 35.69, 'lon': -82.02},
      ],
      'distance_m': 4200.5,
      'elevation_gain_m': 88.0,
    };

    final route = RouteResult.fromJson(json);

    expect(route.id, 'abc-123');
    expect(route.theme, RouteTheme.mostClimbing);
    expect(route.shape, RouteShape.outAndBack);
    expect(route.coords, hasLength(2));
    expect(route.coords.first.lat, 35.68);
    expect(route.coords.first.lon, -82.01);
    expect(route.distanceM, 4200.5);
    expect(route.distanceKm, closeTo(4.2005, 1e-9));
    expect(route.elevationGainM, 88.0);
  });

  test('theme and shape api values round-trip through fromApiValue', () {
    for (final theme in RouteTheme.values) {
      expect(RouteTheme.fromApiValue(theme.apiValue), theme);
    }
    for (final shape in RouteShape.values) {
      expect(RouteShape.fromApiValue(shape.apiValue), shape);
    }
  });
}
