import 'package:field_ops/domain/inventory.dart';
import 'package:field_ops/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

class MovementTile extends StatelessWidget {
  const MovementTile({required this.movement, this.perspectiveWarehouse, this.title, this.onDismiss, super.key});

  final Movement movement;

  /// For transfers: show the incoming side as positive in this warehouse.
  final String? perspectiveWarehouse;
  final String? title;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final incoming = movement.toWarehouseId != null && movement.toWarehouseId == perspectiveWarehouse;
    final delta = incoming ? -movement.delta : movement.delta;
    final (icon, color) = switch (movement.status) {
      MovementStatus.pending => (Icons.schedule, scheme.tertiary),
      MovementStatus.synced => (Icons.cloud_done_outlined, scheme.primary),
      MovementStatus.rejected => (Icons.error_outline, scheme.error),
    };
    final locale = Localizations.localeOf(context).toLanguageTag();
    final subtitle = [
      l10n.movementType(movement.type),
      movement.createdBy,
      DateFormat.MMMd(locale).add_jm().format(movement.createdAt),
      if (movement.note.isNotEmpty) movement.note,
    ].join(' · ');

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(title ?? subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        movement.status == MovementStatus.rejected
            ? l10n.rejectReason(movement.rejectReason)
            : title != null
            ? subtitle
            : l10n.movementStatus(movement.status),
        style: TextStyle(color: movement.status == MovementStatus.rejected ? scheme.error : null),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            delta > 0 ? '+$delta' : '$delta',
            textDirection: TextDirection.ltr,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              decoration: movement.status == MovementStatus.rejected ? TextDecoration.lineThrough : null,
            ),
          ),
          if (onDismiss != null) IconButton(tooltip: l10n.dismiss, onPressed: onDismiss, icon: const Icon(Icons.close)),
        ],
      ),
    );
  }
}
