import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:richfield_connect/main.dart';

void main() {
  testWidgets('login screen loads without rendering exceptions', (tester) async {
    await tester.pumpWidget(MaterialApp(home: LoginScreen()));

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('main role screens avoid phone-sized layout overflows', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final role in RichfieldRole.values) {
      await tester.pumpWidget(MaterialApp(home: RootShell(role: role)));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'overflow for $role');
    }
  });
}
