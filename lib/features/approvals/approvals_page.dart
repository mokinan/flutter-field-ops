import 'package:field_ops/app/widgets/adaptive_shell.dart';
import 'package:field_ops/data/api/field_ops_api.dart';
import 'package:field_ops/data/inventory_repository.dart';
import 'package:field_ops/features/approvals/approvals_cubit.dart';
import 'package:field_ops/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ApprovalsPage extends StatelessWidget {
  const ApprovalsPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => ApprovalsCubit(context.read<InventoryRepository>())..load(),
    child: const _ApprovalsView(),
  );
}

class _ApprovalsView extends StatelessWidget {
  const _ApprovalsView();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<ApprovalsCubit>().state;
    final cubit = context.read<ApprovalsCubit>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(l10n.navApprovals), const UserBadge()],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: cubit.load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (state.loading) const LinearProgressIndicator(),
            if (state.error is Offline)
              ListTile(
                leading: const Icon(Icons.cloud_off),
                title: Text(l10n.approvalsOffline),
                trailing: TextButton(onPressed: cubit.load, child: Text(l10n.retry)),
              ),
            if (!state.loading && state.error == null && state.requests.isEmpty)
              Padding(
                padding: const EdgeInsets.all(48),
                child: Center(child: Text(l10n.approvalsEmpty)),
              ),
            for (final r in state.requests)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.itemName, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        '${l10n.expected(r.expected)} · '
                        '${l10n.variance(r.variance > 0 ? '+${r.variance}' : '${r.variance}')} · '
                        '${l10n.requestedBy(r.requestedBy)}',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: state.deciding.contains(r.id) ? null : () => cubit.decide(r, approve: false),
                            child: Text(l10n.reject),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            key: Key('approve-${r.sku}'),
                            onPressed: state.deciding.contains(r.id) ? null : () => cubit.decide(r, approve: true),
                            child: Text(l10n.approve),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
