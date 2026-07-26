import 'package:client/domain/route.dart';
import 'package:client/presentation/widgets/waypoint_list.dart';
import 'package:client/state/routing_providers.dart';
import 'package:client/state/trip_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_routing_client.dart';

Future<ProviderContainer> _pumpWaypointList(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [routingClientProvider.overrideWithValue(FakeRoutingClient())],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: WaypointList()))),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('typing an address into "Add waypoint" and submitting appends a resolved waypoint', (tester) async {
    final container = await _pumpWaypointList(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Add waypoint'), 'Marion, NC');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(container.read(waypointsProvider), hasLength(1));
    expect(container.read(waypointsProvider).first.label, 'Marion, NC');
  });

  testWidgets('each waypoint gets a lettered row showing its resolved label', (tester) async {
    final container = await _pumpWaypointList(tester);
    container.read(waypointsProvider.notifier).add(const LatLon(35.68, -82.01), label: 'Marion, NC');
    container.read(waypointsProvider.notifier).add(const LatLon(35.9, -81.7), label: 'Blowing Rock, NC');
    await tester.pump();

    expect(find.text('Marion, NC'), findsOneWidget);
    expect(find.text('Blowing Rock, NC'), findsOneWidget);
    // Letters, not numbers -- avoids reading as ambiguous next to "Day 1, Day 2".
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('tapping remove on a row deletes that waypoint', (tester) async {
    final container = await _pumpWaypointList(tester);
    container.read(waypointsProvider.notifier).add(const LatLon(35.68, -82.01), label: 'Marion, NC');
    container.read(waypointsProvider.notifier).add(const LatLon(35.9, -81.7), label: 'Blowing Rock, NC');
    await tester.pump();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.close).first);
    await tester.pump();

    expect(container.read(waypointsProvider), hasLength(1));
    expect(container.read(waypointsProvider).first.label, 'Blowing Rock, NC');
  });

  testWidgets('tapping "locate on map" sets the active waypoint slot to that row', (tester) async {
    final container = await _pumpWaypointList(tester);
    container.read(waypointsProvider.notifier).add(const LatLon(35.68, -82.01), label: 'Marion, NC');
    container.read(waypointsProvider.notifier).add(const LatLon(35.9, -81.7), label: 'Blowing Rock, NC');
    await tester.pump();

    await tester.tap(find.widgetWithIcon(IconButton, Icons.my_location).at(1));
    await tester.pump();

    expect(container.read(activeWaypointSlotProvider), 1);
  });

  testWidgets("a waypoint changed elsewhere (e.g. a map tap) refreshes that row's text", (tester) async {
    final container = await _pumpWaypointList(tester);
    container.read(waypointsProvider.notifier).add(const LatLon(35.68, -82.01), label: 'Marion, NC');
    await tester.pump();
    expect(find.text('Marion, NC'), findsOneWidget);

    container.read(waypointsProvider.notifier).updateAt(0, const LatLon(36.0, -81.5));
    await tester.pump();

    expect(find.text('Marion, NC'), findsNothing);
    expect(find.text('36.00000, -81.50000'), findsOneWidget);
  });
}
