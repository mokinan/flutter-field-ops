import 'package:field_ops/app/router.dart';
import 'package:field_ops/app/widgets/adaptive_shell.dart';
import 'package:field_ops/domain/inventory.dart';
import 'package:field_ops/features/inventory/inventory_cubit.dart';
import 'package:field_ops/features/inventory/item_details.dart';
import 'package:field_ops/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Stock list. On tablets the selected item opens in a side pane
/// (master–detail); on phones it opens a new page.
class InventoryPage extends StatelessWidget {
  const InventoryPage({super.key});

  Future<void> _scan(BuildContext context) async {
    final cubit = context.read<InventoryCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final code = await context.push<String>(Routes.scan);
    if (code == null || !context.mounted) return;
    final item = cubit.findByBarcode(code);
    if (item == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.itemNotFound)));
    } else {
      _open(context, item);
    }
  }

  void _open(BuildContext context, StockItem item) {
    if (isExpanded(context)) {
      context.read<InventoryCubit>().select(item.sku);
    } else {
      context.push(Routes.item(item.sku));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<InventoryCubit>().state;
    final cubit = context.read<InventoryCubit>();
    final expanded = isExpanded(context);

    final list = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: ValueKey(state.warehouses.length),
                  initialValue: state.warehouseId,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.warehouse_outlined), isDense: true),
                  items: [
                    for (final w in state.warehouses) DropdownMenuItem(value: w.id, child: Text(w.name)),
                  ],
                  onChanged: (id) => cubit.selectWarehouse(id!),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            key: const Key('search'),
            onChanged: cubit.search,
            decoration: InputDecoration(
              hintText: l10n.searchItems,
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: IconButton(
                tooltip: l10n.scan,
                icon: const Icon(Icons.qr_code_scanner),
                onPressed: () => _scan(context),
              ),
            ),
          ),
        ),
        if (state.refreshing) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: RefreshIndicator(
            onRefresh: cubit.refresh,
            child: ListView.separated(
              itemCount: state.items.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (context, i) {
                final item = state.items[i];
                return _ItemTile(
                  item: item,
                  selected: expanded && item.sku == state.selectedSku,
                  onTap: () => _open(context, item),
                );
              },
            ),
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(l10n.navInventory), const UserBadge()],
        ),
      ),
      body: expanded
          ? Row(
              children: [
                SizedBox(width: 400, child: list),
                const VerticalDivider(width: 1),
                Expanded(
                  child: state.selected == null
                      ? Center(child: Text(l10n.selectItem))
                      : ItemDetails(key: ValueKey(state.selected!.sku), item: state.selected!),
                ),
              ],
            )
          : list,
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.selected, required this.onTap});

  final StockItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      selected: selected,
      onTap: onTap,
      title: Text(item.name),
      subtitle: Text(item.sku, style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${item.quantity} ${item.unit}',
            textDirection: TextDirection.ltr,
            style: theme.textTheme.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          if (item.hasPendingChanges)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_upload_outlined, size: 14, color: theme.colorScheme.tertiary),
                const SizedBox(width: 4),
                Text(
                  item.pendingDelta > 0 ? '+${item.pendingDelta}' : '${item.pendingDelta}',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.tertiary),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
