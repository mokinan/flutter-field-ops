import 'dart:convert';

import 'package:durable_sync_queue/durable_sync_queue.dart';
import 'package:field_ops/data/local/tenant_database.dart';

/// Persists the sync queue in the tenant database, so a queued operation is
/// written in the same transaction as the movement it sends.
class DriftQueueStore implements QueueStore {
  DriftQueueStore(this._db);

  final TenantDatabase _db;

  @override
  Future<List<QueuedOperation>> loadAll() async => [
    for (final row in await _db.select(_db.queueEntries).get())
      QueuedOperation.fromJson(jsonDecode(row.json) as Map<String, Object?>),
  ];

  @override
  Future<void> save(QueuedOperation operation) => _db
      .into(_db.queueEntries)
      .insertOnConflictUpdate(QueueEntriesCompanion.insert(id: operation.id, json: jsonEncode(operation.toJson())));

  @override
  Future<void> delete(String id) => (_db.delete(_db.queueEntries)..where((r) => r.id.equals(id))).go();
}
