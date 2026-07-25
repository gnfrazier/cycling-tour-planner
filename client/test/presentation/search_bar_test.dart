import 'package:client/data/routing_client.dart';
import 'package:client/domain/route.dart';
import 'package:client/presentation/widgets/search_bar.dart';
import 'package:client/state/routing_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_routing_client.dart';

class _FailingGeocodeClient extends RoutingClient {
  _FailingGeocodeClient() : super(baseUrl: 'http://fake');

  @override
  Future<bool> checkReady() async => true;

  @override
  Future<GeocodeResult> geocode(String query) async {
    throw RoutingClientException('could not find "$query"');
  }
}

void main() {
  testWidgets('losing focus (e.g. Tab) geocodes the typed text, same as pressing Enter', (tester) async {
    final container = ProviderContainer(
      overrides: [routingClientProvider.overrideWithValue(FakeRoutingClient())],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                GeocodeSearchField(label: 'Start', target: SearchTarget.start),
                TextField(), // a second focusable field to Tab/tap away to
              ],
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'Marion, NC');
    await tester.tap(find.byType(TextField).last);
    await tester.pumpAndSettle();

    expect(container.read(startPointProvider), isNotNull);
  });

  testWidgets('a point set externally (e.g. a map tap) shows as coordinates, not blank text', (tester) async {
    final container = ProviderContainer(
      overrides: [routingClientProvider.overrideWithValue(FakeRoutingClient())],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: GeocodeSearchField(label: 'Start', target: SearchTarget.start)),
        ),
      ),
    );

    container.read(startPointProvider.notifier).state = const LatLon(35.68410, -82.00910);
    await tester.pump();

    expect(find.text('35.68410, -82.00910'), findsOneWidget);
  });

  testWidgets('clearing the bound point externally clears the field text', (tester) async {
    final container = ProviderContainer(
      overrides: [routingClientProvider.overrideWithValue(FakeRoutingClient())],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: GeocodeSearchField(label: 'Start', target: SearchTarget.start)),
        ),
      ),
    );

    container.read(startPointProvider.notifier).state = const LatLon(35.68410, -82.00910);
    await tester.pump();
    expect(find.text('35.68410, -82.00910'), findsOneWidget);

    container.read(startPointProvider.notifier).state = null;
    await tester.pump();
    expect(find.text('35.68410, -82.00910'), findsNothing);
  });

  testWidgets('a failed-search error clears when the bound point is reset externally', (tester) async {
    final container = ProviderContainer(
      overrides: [routingClientProvider.overrideWithValue(_FailingGeocodeClient())],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: GeocodeSearchField(label: 'Start', target: SearchTarget.start)),
        ),
      ),
    );

    // Start from an already-set point (e.g. an earlier successful search or
    // a map tap) — otherwise setting it to null again below is a no-op
    // Riverpod never notifies for, and wouldn't exercise the reset path.
    container.read(startPointProvider.notifier).state = const LatLon(35.68410, -82.00910);
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'not a real place');
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    expect(find.text('could not find "not a real place"'), findsOneWidget);

    // Reset (or a shape change) clears the point externally — the stale
    // error label must go with it, not linger under an empty field.
    container.read(startPointProvider.notifier).state = null;
    await tester.pump();

    expect(find.text('could not find "not a real place"'), findsNothing);
  });
}
