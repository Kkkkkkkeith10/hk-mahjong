// Basic smoke test: the app root builds and shows the loading state
// (the fan table loads asynchronously from bundled assets).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mj_app/main.dart';

void main() {
  testWidgets('MjApp builds', (WidgetTester tester) async {
    await tester.pumpWidget(const MjApp());
    // First frame: either the loading spinner or (if assets resolved
    // synchronously in the test binding) the home screen — the point is
    // simply that the root widget builds without throwing.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
