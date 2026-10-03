import 'package:field_ops/app/session_cubit.dart';
import 'package:field_ops/data/inventory_repository.dart';
import 'package:field_ops/domain/auth.dart';
import 'package:field_ops/features/count/count_cubit.dart';
import 'package:field_ops/features/inventory/inventory_cubit.dart';
import 'package:field_ops/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Breakpoint between phone and tablet/desktop layouts (Material 3
/// "expanded" window class).
const double kExpandedWidth = 840;

bool isExpanded(BuildContext context) => MediaQuery.sizeOf(context).width >= kExpandedWidth;

/// Provides the session's repository and screen state. Keyed by user, so
/// signing in as someone else rebuilds everything from scratch.
class SessionScope extends StatelessWidget {
  const SessionScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionCubit>().state;
    if (session is! SignedIn) return const SizedBox.shrink();
    final repository = session.repository;
    return RepositoryProvider<InventoryRepository>.value(
      key: ValueKey(repository.user.id),
      value: repository,
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => InventoryCubit(repository)),
          BlocProvider(create: (_) => CountCubit(repository)),
        ],
        child: child,
      ),
    );
  }
}

/// Bottom navigation on phones, a navigation rail on tablets. Tabs the user
/// has no permission for are not shown.
class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final user = context.read<InventoryRepository>().user;
    final tabs = [
      (0, Icons.inventory_2_outlined, Icons.inventory_2, l10n.navInventory, Permission.viewStock),
      (1, Icons.fact_check_outlined, Icons.fact_check, l10n.navCount, Permission.countStock),
      (2, Icons.approval_outlined, Icons.approval, l10n.navApprovals, Permission.viewApprovals),
      (3, Icons.sync_alt, Icons.sync_alt, l10n.navActivity, Permission.viewStock),
    ].where((t) => user.can(t.$5)).toList();
    final selected = tabs.indexWhere((t) => t.$1 == shell.currentIndex).clamp(0, tabs.length - 1);
    void go(int i) => shell.goBranch(tabs[i].$1, initialLocation: tabs[i].$1 == shell.currentIndex);

    if (!isExpanded(context)) {
      return Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: go,
          destinations: [
            for (final t in tabs) NavigationDestination(icon: Icon(t.$2), selectedIcon: Icon(t.$3), label: t.$4),
          ],
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selected,
            onDestinationSelected: go,
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Icon(Icons.warehouse_outlined, size: 32, color: Theme.of(context).colorScheme.primary),
            ),
            destinations: [
              for (final t in tabs)
                NavigationRailDestination(icon: Icon(t.$2), selectedIcon: Icon(t.$3), label: Text(t.$4)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: shell),
        ],
      ),
    );
  }
}

/// Shows [child] only if the user holds [permission]. The domain checks
/// again — this only keeps the UI honest.
class PermissionGate extends StatelessWidget {
  const PermissionGate({required this.permission, required this.child, this.fallback, super.key});

  final Permission permission;
  final Widget child;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) =>
      context.read<InventoryRepository>().user.can(permission) ? child : (fallback ?? const SizedBox.shrink());
}

/// App bar subtitle with the user's name, role and company.
class UserBadge extends StatelessWidget {
  const UserBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.read<InventoryRepository>().user;
    return Text(
      '${user.name} · ${context.l10n.role(user.role)} · ${user.tenant.name}',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}
