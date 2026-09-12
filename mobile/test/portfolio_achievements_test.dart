// Achievements on the Portfolio (guidelines 2.3) share the one entry sheet
// every other section uses. These drive that real sheet for the new
// section with the insert stubbed out, so the form is exercised without a
// Supabase client: which fields it shows, that the NOT NULL column is
// enforced before any request, and exactly what a save would send.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:richfield_connect/screens/portfolio_entry_sheet.dart';
import 'package:richfield_connect/services/portfolio_service.dart';

Widget host(Future<void> Function(Map<String, dynamic>) onSave) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showPortfolioEntrySheet(
            context,
            section: PortfolioSection.achievements,
            onSave: onSave,
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

Future<void> openSheet(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  test('achievements is a portfolio section backed by the achievements table', () {
    expect(PortfolioSection.achievements.table, 'achievements');
    // Every section resolves to a table; a new enum value without one
    // would be a switch error at compile time, but keep the intent visible.
    for (final section in PortfolioSection.values) {
      expect(section.table, isNotEmpty);
    }
    expect(const PortfolioData().achievements, isEmpty);
  });

  testWidgets('the sheet shows the three achievement fields', (tester) async {
    await tester.pumpWidget(host((_) async {}));
    await openSheet(tester);

    expect(find.text('Add an achievement'), findsOneWidget);
    expect(find.text('Achievement *'), findsOneWidget);
    expect(find.text('What it was for'), findsOneWidget);
    expect(find.text('Date received'), findsOneWidget);
    // Nothing from the badge form leaks in.
    expect(find.text('Issued by'), findsNothing);
    expect(find.text('Badge link'), findsNothing);
  });

  testWidgets('an empty title is refused before anything is sent', (tester) async {
    var saves = 0;
    await tester.pumpWidget(host((_) async => saves++));
    await openSheet(tester);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Achievement is required.'), findsOneWidget);
    expect(saves, 0);
    expect(find.text('Add an achievement'), findsOneWidget, reason: 'sheet stays open');
  });

  testWidgets('saving sends only the filled columns and closes the sheet', (tester) async {
    Map<String, dynamic>? sent;
    await tester.pumpWidget(host((values) async => sent = values));
    await openSheet(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Achievement *'), "Dean's list 2025");
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // description left blank is omitted, not sent as '' (a blank date would
    // be a Postgres error; the sheet treats every optional field the same).
    expect(sent, {'title': "Dean's list 2025"});
    expect(find.text('Add an achievement'), findsNothing, reason: 'sheet closed after save');
  });

  testWidgets('a failed insert keeps the sheet open with the message', (tester) async {
    await tester.pumpWidget(host((_) async => throw Exception('network down')));
    await openSheet(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Achievement *'), 'Hackathon winner');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Add an achievement'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget, reason: 'button re-enabled, not stuck on Saving…');
  });
}
