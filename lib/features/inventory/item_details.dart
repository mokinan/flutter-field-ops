import 'package:field_ops/app/widgets/adaptive_shell.dart';
import 'package:field_ops/data/inventory_repository.dart';
import 'package:field_ops/domain/auth.dart';
import 'package:field_ops/domain/inventory.dart';
import 'package:field_ops/domain/use_cases.dart';
import 'package:field_ops/features/activity/movement_tile.dart';
import 'package:field_ops/features/inventory/inventory_cubit.dart';
import 'package:field_ops/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Quantities, actions and history for one stock line. Used as a page on
/// phones and as the detail pane on tablets.
class ItemDetails extends StatelessWidget {
  const ItemDetails({required this.item, super.key});

  final StockItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final repository = context.read<InventoryRepository>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(item.name, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('${item.sku} · ${item.barcode}', style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.onHand, style: theme.textTheme.labelLarge),
                Text(
                  '${item.quantity} ${item.unit}',
                  textDirection: TextDirection.ltr,
                  style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (item.hasPendingChanges) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${l10n.serverQuantity(item.serverQuantity)} · '
                    '${l10n.pendingUnits(item.pendingDelta)}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.tertiary),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        PermissionGate(
          permission: Permission.recordMovement,
          fallback: ListTile(leading: const Icon(Icons.lock_outline), title: Text(l10n.readOnly)),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (type, icon) in [
                (MovementType.receive, Icons.add_box_outlined),
                (MovementType.issue, Icons.outbox_outlined),
                (MovementType.transfer, Icons.swap_horiz),
              ])
                FilledButton.tonalIcon(
                  key: Key('action-${type.name}'),
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => RepositoryProvider.value(
                      value: repository,
                      child: BlocProvider.value(
                        value: context.read<InventoryCubit>(),
                        child: MovementSheet(item: item, type: type),
                      ),
                    ),
                  ),
                  icon: Icon(icon),
                  label: Text(l10n.movementType(type)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(l10n.recentMovements, style: theme.textTheme.titleMedium),
        StreamBuilder<List<Movement>>(
          stream: repository.watchMovements(sku: item.sku, warehouseId: item.warehouseId, limit: 20),
          builder: (context, snapshot) {
            final movements = snapshot.data ?? const [];
            if (movements.isEmpty) {
              return Padding(padding: const EdgeInsets.all(16), child: Text(l10n.noMovements));
            }
            return Column(
              children: [for (final m in movements) MovementTile(movement: m, perspectiveWarehouse: item.warehouseId)],
            );
          },
        ),
      ],
    );
  }
}

class MovementSheet extends StatefulWidget {
  const MovementSheet({required this.item, required this.type, super.key});

  final StockItem item;
  final MovementType type;

  @override
  State<MovementSheet> createState() => _MovementSheetState();
}

class _MovementSheetState extends State<MovementSheet> {
  final _quantity = TextEditingController();
  final _note = TextEditingController();
  String? _destination;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await RecordMovement(context.read<InventoryRepository>())(
        type: widget.type,
        sku: widget.item.sku,
        warehouseId: widget.item.warehouseId,
        quantity: int.tryParse(_quantity.text) ?? 0,
        toWarehouseId: _destination,
        note: _note.text,
      );
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(l10n.movementSaved)));
    } on InsufficientStock catch (e) {
      setState(() => _error = l10n.insufficientStock(e.available));
    } on InvalidMovement {
      setState(() => _error = l10n.invalidQuantity);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final warehouses = context
        .watch<InventoryCubit>()
        .state
        .warehouses
        .where((w) => w.id != widget.item.warehouseId)
        .toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${l10n.movementType(widget.type)} · ${widget.item.name}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('quantity'),
            controller: _quantity,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: l10n.quantity,
              suffixText: widget.item.unit,
              errorText: _error,
            ),
          ),
          if (widget.type == MovementType.transfer) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _destination,
              decoration: InputDecoration(labelText: l10n.destination),
              items: [for (final w in warehouses) DropdownMenuItem(value: w.id, child: Text(w.name))],
              onChanged: (v) => setState(() => _destination = v),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            decoration: InputDecoration(labelText: l10n.note),
          ),
          const SizedBox(height: 24),
          FilledButton(key: const Key('save-movement'), onPressed: _saving ? null : _save, child: Text(l10n.save)),
        ],
      ),
    );
  }
}
