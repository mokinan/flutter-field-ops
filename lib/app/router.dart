import 'dart:async';

import 'package:field_ops/app/session_cubit.dart';
import 'package:field_ops/app/widgets/adaptive_shell.dart';
import 'package:field_ops/features/activity/activity_page.dart';
import 'package:field_ops/features/approvals/approvals_page.dart';
import 'package:field_ops/features/auth/login_page.dart';
import 'package:field_ops/features/count/count_page.dart';
import 'package:field_ops/features/inventory/inventory_page.dart';
import 'package:field_ops/features/inventory/item_page.dart';
import 'package:field_ops/features/scanner/scanner_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

abstract final class Routes {
  static const login = '/login';
  static const inventory = '/inventory';
  static const count = '/count';
  static const approvals = '/approvals';
  static const activity = '/activity';
  static const scan = '/scan';
  static String item(String sku) => '/inventory/item/$sku';
}

GoRouter createRouter(SessionCubit session) => GoRouter(
  initialLocation: Routes.inventory,
  refreshListenable: _StreamListenable(session.stream),
  redirect: (context, state) {
    final signedIn = session.state is SignedIn;
    final atLogin = state.matchedLocation == Routes.login;
    if (!signedIn) return atLogin ? null : Routes.login;
    return atLogin ? Routes.inventory : null;
  },
  routes: [
    GoRoute(path: Routes.login, builder: (_, _) => const LoginPage()),
    GoRoute(path: Routes.scan, builder: (_, _) => const ScannerPage()),
    StatefulShellRoute.indexedStack(
      // Everything below is scoped to the signed-in session.
      builder: (_, _, shell) => SessionScope(child: AdaptiveShell(shell: shell)),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.inventory,
              builder: (_, _) => const InventoryPage(),
              routes: [
                GoRoute(
                  path: 'item/:sku',
                  builder: (_, s) => ItemPage(sku: s.pathParameters['sku']!),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: Routes.count, builder: (_, _) => const CountPage())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: Routes.approvals, builder: (_, _) => const ApprovalsPage())],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: Routes.activity, builder: (_, _) => const ActivityPage())],
        ),
      ],
    ),
  ],
);

class _StreamListenable extends ChangeNotifier {
  _StreamListenable(Stream<Object?> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _subscription;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
