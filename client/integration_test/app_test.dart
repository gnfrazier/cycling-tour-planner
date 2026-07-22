// Runs the real app against the real backend dev server (no fakes/mocks) on
// the actual `linux` desktop target — the closest this environment can get
// to "drive the running app by hand" without an OS-level input-automation
// tool. Requires the backend to already be running (see backend/README.md).
import 'package:client/domain/theme.dart';
import 'package:client/main.dart';
import 'package:client/presentation/widgets/route_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('generate a route for every theme against the live backend', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CycleTourPlannerApp()));

    // Wait for the real /health readiness poll to succeed.
    await tester.pumpAndSettle(const Duration(seconds: 2));
    for (var i = 0; i < 30 && find.text('Generate route').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('Generate route'), findsOneWidget);

    // FR34 — geocode search sets the start point via the real /geocode call.
    await tester.enterText(find.widgetWithText(TextField, 'Start'), 'Marion, NC');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    for (final theme in RouteTheme.values) {
      await tester.tap(find.text(theme.label));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate route'));
      // Real network + real OSMnx solve — give it real time.
      await tester.pump();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(seconds: 1));
        if (find.textContaining('Distance:').evaluate().isNotEmpty ||
            find.byType(SnackBar).evaluate().isNotEmpty) {
          break;
        }
      }
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Distance:'),
        findsOneWidget,
        reason: 'route generation failed for theme ${theme.label}',
      );
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(PolylineLayer), findsOneWidget);
      expect(find.byType(RouteMap), findsOneWidget);
    }
  });
}
