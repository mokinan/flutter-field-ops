import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:field_ops/app/app.dart';
import 'package:field_ops/data/api/fake_field_ops_api.dart';
import 'package:field_ops/data/local/tenant_database.dart';
import 'package:field_ops/domain/auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  Future<void> signInAs(WidgetTester tester, Role role, {Size size = const Size(390, 844)}) async {
    tester.view
      ..physicalSize = size * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      FieldOpsApp(
        api: FakeFieldOpsApi(latency: Duration.zero),
        locale: const Locale('en'),
        openDatabase: (_) => TenantDatabase.forTesting(NativeDatabase.memory()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(ActionChip, switch (role) {
        Role.manager => 'Manager',
        Role.clerk => 'Clerk',
        Role.viewer => 'Viewer',
      }),
    );
    await tester.tap(find.text('Sign in'));
    // Database work runs on real async; let it complete, then render.
    for (var i = 0; i < 20 && find.text('Cable ties 300 mm, pack of 100').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> tearDownApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // Drift schedules a zero-length timer when a query stream is cancelled.
    await tester.pump(Duration.zero);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  }

  testWidgets('a viewer sees stock but no counting, approvals or actions', (tester) async {
    await signInAs(tester, Role.viewer);

    expect(find.text('Cable ties 300 mm, pack of 100'), findsOneWidget);
    expect(find.text('Count'), findsNothing);
    expect(find.text('Approvals'), findsNothing);

    await tester.tap(find.text('Cable ties 300 mm, pack of 100'));
    await tester.pumpAndSettle();
    expect(find.text('Read-only access'), findsOneWidget);
    expect(find.byKey(const Key('action-receive')), findsNothing);
    await tearDownApp(tester);
  });

  testWidgets('a clerk can count and move stock but not approve', (tester) async {
    await signInAs(tester, Role.clerk);
    expect(find.text('Count'), findsOneWidget);
    expect(find.text('Approvals'), findsNothing);

    await tester.tap(find.text('Cable ties 300 mm, pack of 100'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('action-receive')), findsOneWidget);
    await tearDownApp(tester);
  });

  testWidgets('a manager sees approvals', (tester) async {
    await signInAs(tester, Role.manager);
    expect(find.text('Approvals'), findsOneWidget);
    await tearDownApp(tester);
  });

  testWidgets('tablets get a navigation rail and a detail pane', (tester) async {
    await signInAs(tester, Role.clerk, size: const Size(1194, 834));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Select an item to see details'), findsOneWidget);

    await tester.tap(find.text('Cable ties 300 mm, pack of 100'));
    await tester.pumpAndSettle();
    expect(find.text('On hand'), findsOneWidget, reason: 'opened beside the list, not as a new page');
    expect(find.text('Cable ties 300 mm, pack of 100'), findsNWidgets(2));
    await tearDownApp(tester);
  });

  testWidgets('wrong credentials show an error', (tester) async {
    await tester.pumpWidget(
      FieldOpsApp(
        api: FakeFieldOpsApi(latency: Duration.zero),
        locale: const Locale('en'),
        openDatabase: (_) => TenantDatabase.forTesting(NativeDatabase.memory()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('email')), 'nobody@northwind.test');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect email or password'), findsOneWidget);
  });
}
