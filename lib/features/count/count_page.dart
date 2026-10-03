import 'package:field_ops/app/router.dart';
import 'package:field_ops/app/widgets/adaptive_shell.dart';
import 'package:field_ops/domain/inventory.dart';
import 'package:field_ops/features/count/count_cubit.dart';
import 'package:field_ops/features/inventory/inventory_cubit.dart';
import 'package:field_ops/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class CountPage extends StatelessWidget {
  const CountPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<CountCubit>().state;
    final cubit = context.read<CountCubit>();
    final inventory = context.watch<InventoryCubit>().state;

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l10n.navCount), const UserBadge()]),
        actions: [
          if (state.phase == CountPhase.counting)
            IconButton(
              tooltip: l10n.scan,
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final code = await context.push<String>(Routes.scan);
                if (code != null && !await cubit.scan(code)) {
                  messenger.showSnackBar(SnackBar(content: Text(l10n.itemNotFound)));
                }
              },
            ),
        ],
      ),
      body: switch (state.phase) {
        CountPhase.idle => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.fact_check_outlined, size: 56),
                const SizedBox(height: 16),
                Text(l10n.countHint, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const Key('start-count'),
                  onPressed: inventory.warehouseId == null ? null : () => cubit.start(inventory.warehouseId!),
                  icon: const Icon(Icons.play_arrow),
                  label: Text('${l10n.startCount} · ${inventory.warehouse?.name ?? ''}'),
                ),
              ],
            ),
          ),
        ),
        CountPhase.done => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, size: 56, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(l10n.countDone, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(l10n.countResult(state.result!.applied, state.result!.sentForApproval)),
                const SizedBox(height: 24),
                FilledButton.tonal(onPressed: cubit.reset, child: Text(l10n.newCount)),
              ],
            ),
          ),
        ),
        _ => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.countProgress(state.counted, state.lines.length, state.withVariance)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: state.lines.length,
                itemBuilder: (_, i) =>
                    _CountRow(line: state.lines[i], highlight: state.lastScanned == state.lines[i].sku),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  key: const Key('submit-count'),
                  onPressed: state.phase == CountPhase.submitting || state.counted == 0 ? null : cubit.submit,
                  child: Text(l10n.submitCount),
                ),
              ),
            ),
          ],
        ),
      },
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({required this.line, required this.highlight});

  final CountLine line;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<CountCubit>();
    final scheme = Theme.of(context).colorScheme;
    final escalates = line.counted != null && cubit.policy.needsApproval(line);
    final varianceText = line.variance > 0 ? '+${line.variance}' : '${line.variance}';

    return ListTile(
      tileColor: highlight ? scheme.primaryContainer.withValues(alpha: 0.4) : null,
      title: Text(line.name),
      subtitle: Text(
        [
          l10n.expected(line.expected),
          if (line.counted != null && line.variance != 0) l10n.variance(varianceText),
          if (escalates) l10n.needsApproval,
        ].join(' · '),
        style: TextStyle(color: escalates ? scheme.error : null),
      ),
      trailing: SizedBox(
        width: 88,
        child: TextFormField(
          key: ValueKey('count-${line.sku}-${line.counted}'),
          initialValue: line.counted?.toString() ?? '',
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(isDense: true, hintText: '—'),
          onChanged: (v) => cubit.setCount(line.sku, int.tryParse(v)),
        ),
      ),
    );
  }
}
