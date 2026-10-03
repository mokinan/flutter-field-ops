import 'package:field_ops/app/app.dart';
import 'package:field_ops/app/session_cubit.dart';
import 'package:field_ops/app/widgets/adaptive_shell.dart';
import 'package:field_ops/data/api/fake_field_ops_api.dart';
import 'package:field_ops/data/inventory_repository.dart';
import 'package:field_ops/domain/inventory.dart';
import 'package:field_ops/features/activity/movement_tile.dart';
import 'package:field_ops/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Sync status, the device's movement log, and field-condition switches.
class ActivityPage extends StatelessWidget {
  const ActivityPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final repository = context.read<InventoryRepository>();
    final api = context.read<FakeFieldOpsApi>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(l10n.navActivity), const UserBadge()],
        ),
        actions: [
          IconButton(
            tooltip: l10n.signOut,
            onPressed: () => context.read<SessionCubit>().signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StreamBuilder<int>(
            stream: repository.watchPendingCount(),
            builder: (context, snapshot) {
              final pending = snapshot.data ?? 0;
              return ValueListenableBuilder(
                valueListenable: api.offline,
                builder: (context, offline, _) => Card(
                  color: pending == 0 ? null : (offline ? scheme.errorContainer : scheme.tertiaryContainer),
                  child: ListTile(
                    leading: Icon(
                      pending == 0
                          ? Icons.cloud_done_outlined
                          : (offline ? Icons.cloud_off : Icons.cloud_upload_outlined),
                    ),
                    title: Text(pending == 0 ? l10n.allSynced : l10n.pendingChanges(pending)),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder(
            valueListenable: api.offline,
            builder: (_, offline, _) => SwitchListTile(
              key: const Key('offline-switch'),
              secondary: const Icon(Icons.signal_wifi_off),
              title: Text(l10n.offlineMode),
              subtitle: Text(l10n.offlineModeHint),
              value: offline,
              onChanged: (v) => api.offline.value = v,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.devices_other),
            title: Text(l10n.otherDevice),
            subtitle: Text(l10n.otherDeviceHint),
            onTap: () => api.simulateOtherDevice(repository.user.tenant.id, 'PPE-HLM-01', 'ruh', -1000),
          ),
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(l10n.language),
            onTap: () => context.read<LocaleController>().toggle(Localizations.localeOf(context)),
          ),
          const Divider(height: 32),
          StreamBuilder<List<Movement>>(
            stream: repository.watchMovements(),
            builder: (context, snapshot) {
              final movements = snapshot.data ?? const [];
              if (movements.isEmpty) return Center(child: Text(l10n.noMovements));
              return Column(
                children: [
                  for (final m in movements)
                    StreamBuilder(
                      stream: repository.watchStock(m.warehouseId),
                      builder: (context, items) => MovementTile(
                        movement: m,
                        title: items.data?.where((i) => i.sku == m.sku).firstOrNull?.name ?? m.sku,
                        onDismiss: m.status == MovementStatus.rejected ? () => repository.dismissRejected(m.id) : null,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
