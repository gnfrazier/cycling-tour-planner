import 'dart:async';

import 'package:client/presentation/screens/route_planner_screen.dart';
import 'package:client/state/routing_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_routing_client.dart';

void main() {
  testWidgets('startup wait escalates messages and adds guidance past 5 minutes, without ever failing', (tester) async {
    final container = ProviderContainer(
      overrides: [
        routingClientProvider.overrideWithValue(FakeRoutingClient()),
        // Never resolves — simulates a cold start still in progress.
        backendReadyProvider.overrideWith((ref) => Completer<void>().future),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: RoutePlannerScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Filling up bottles…'), findsOneWidget);
    expect(find.textContaining('Still waiting'), findsNothing);

    await tester.pump(const Duration(seconds: 60));
    expect(find.text("Can't find the tire levers…"), findsOneWidget);
    expect(find.textContaining('Still waiting'), findsNothing, reason: 'still well under the 5-minute threshold');

    await tester.pump(const Duration(seconds: 250)); // total elapsed ~310s, past the 300s threshold
    expect(find.textContaining('Still waiting'), findsOneWidget);
    // Still just informational text alongside the spinner — never a
    // failure state or a stopped poll (FR48).
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
