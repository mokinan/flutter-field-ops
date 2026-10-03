import 'dart:io';

import 'package:field_ops/app/app.dart';
import 'package:field_ops/data/api/fake_field_ops_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// End-to-end on a phone: a clerk works offline, counts stock, syncs; a
/// manager approves the large variance. On a tablet: the master–detail
/// layout. Run with `flutter drive` to also save screenshots.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> shot(WidgetTester tester, String name) async {
    FocusManager.instance.primaryFocus?.unfocus();
    for (final m in tester.stateList<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))) {
      m.clearSnackBars();
    }
    for (var i = 0; i < 15; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    }
    await binding.takeScreenshot(name);
  }

  Future<void> signIn(WidgetTester tester, String role) async {
    await tester.pumpUntil(find.text('Demo accounts'));
    await tester.tap(find.widgetWithText(ActionChip, role));
    await tester.tap(find.text('Sign in'));
    await tester.pumpUntil(find.textContaining('Cable ties'));
  }

  testWidgets('field operations', (tester) async {
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
    final api = FakeFieldOpsApi(latency: const Duration(milliseconds: 150));
    await tester.pumpWidget(FieldOpsApp(api: api, locale: const Locale('en')));
    final wide = tester.view.physicalSize.width / tester.view.devicePixelRatio >= 840;

    if (wide) {
      await signIn(tester, 'Manager');
      await tester.tap(find.textContaining('Copper cable'));
      await tester.pumpUntil(find.text('On hand'));
      await shot(tester, 'tablet_inventory');
      return;
    }

    // Clerk goes offline (a basement storeroom).
    await signIn(tester, 'Clerk');
    await shot(tester, 'inventory');
    await tester.tap(find.text('Activity'));
    await tester.pumpUntil(find.byKey(const Key('offline-switch')));
    await tester.tap(find.byKey(const Key('offline-switch')));
    await tester.pump();

    // Issue stock while offline.
    await tester.tap(find.text('Inventory'));
    await tester.pumpUntil(find.textContaining('Cable ties'));
    await tester.tap(find.textContaining('Cable ties'));
    await tester.pumpUntil(find.byKey(const Key('action-issue')));
    await tester.tap(find.byKey(const Key('action-issue')));
    await tester.pumpUntil(find.byKey(const Key('quantity')));
    await tester.enterText(find.byKey(const Key('quantity')), '8');
    await tester.tap(find.byKey(const Key('save-movement')));
    await tester.pumpUntil(find.textContaining('pending sync'));
    await shot(tester, 'item_pending');
    await tester.pageBack();
    await tester.pumpUntil(find.text('Count'));

    // Cycle count: one small difference, one large.
    await tester.tap(find.text('Count'));
    await tester.pumpUntil(find.byKey(const Key('start-count')));
    await tester.tap(find.byKey(const Key('start-count')));
    await tester.pumpUntil(find.byKey(const Key('submit-count')));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '48');
    await tester.enterText(fields.at(1), '90');
    await tester.enterText(fields.at(2), '174');
    await tester.pump();
    await shot(tester, 'count');
    await tester.tap(find.byKey(const Key('submit-count')));
    await tester.pumpUntil(find.text('Count submitted'));

    // Activity while offline, then reconnect.
    await tester.tap(find.text('Activity'));
    await tester.pumpUntil(find.textContaining('waiting to sync'));
    await shot(tester, 'activity_offline');
    await tester.tap(find.byKey(const Key('offline-switch')));
    await tester.pumpUntil(find.text('All changes synced'), timeout: const Duration(seconds: 15));
    await shot(tester, 'activity_synced');

    // Manager approves the large variance.
    await tester.tap(find.byTooltip('Sign out'));
    await signIn(tester, 'Manager');
    await tester.tap(find.text('Approvals'));
    await tester.pumpUntil(find.text('Approve'));
    await shot(tester, 'approvals');
    await tester.tap(find.text('Approve').first);
    await tester.pumpUntil(find.text('Nothing to approve'));

    // Arabic.
    await tester.tap(find.text('Activity'));
    await tester.pumpUntil(find.text('العربية'));
    await tester.tap(find.text('العربية'));
    await tester.pumpUntil(find.text('المخزون'));
    await tester.tap(find.text('المخزون'));
    await tester.pumpUntil(find.textContaining('Cable ties'));
    await shot(tester, 'inventory_arabic');
  });
}

extension on WidgetTester {
  Future<void> pumpUntil(Finder finder, {Duration timeout = const Duration(seconds: 10)}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await pump(const Duration(milliseconds: 100));
      if (any(finder)) return;
    }
    throw TestFailure('Timed out waiting for $finder');
  }
}
