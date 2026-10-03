import 'dart:async';

import 'package:drift/drift.dart';
import 'package:durable_sync_queue/durable_sync_queue.dart';
import 'package:field_ops/data/api/field_ops_api.dart';
import 'package:field_ops/data/local/drift_queue_store.dart';
import 'package:field_ops/data/local/tenant_database.dart';
import 'package:field_ops/domain/auth.dart';
import 'package:field_ops/domain/inventory.dart';
import 'package:field_ops/domain/inventory_gateway.dart';
import 'package:uuid/uuid.dart';

abstract final class _Ops {
  static const movement = 'movement';
  static const requestAdjustment = 'request_adjustment';
  static const decideAdjustment = 'decide_adjustment';
}

/// Local-first inventory for one signed-in user and tenant.
///
/// Reads come from the tenant database; writes are recorded locally and
/// queued. The sync queue delivers them in order **per stock line** (SKU in
/// a warehouse), so movements on one item never overtake each other while
/// unrelated items sync independently.
class InventoryRepository implements InventoryGateway {
  InventoryRepository({
    required this.user,
    required TenantDatabase db,
    required FieldOpsApi api,
    BackoffPolicy? backoff,
    DateTime Function()? clock,
    Uuid uuid = const Uuid(),
  }) : _db = db,
       _api = api,
       _clock = clock ?? DateTime.now,
       _uuid = uuid {
    queue = SyncQueue(
      store: DriftQueueStore(db),
      handler: _deliver,
      backoff: backoff,
      onError: (e) => e is Offline ? const Outcome.retryLater('offline') : Outcome.rejected('$e'),
      clock: _clock,
    );
  }

  @override
  final User user;
  final TenantDatabase _db;
  final FieldOpsApi _api;
  final DateTime Function() _clock;
  final Uuid _uuid;
  late final SyncQueue queue;

  // ---- reads -------------------------------------------------------------

  Stream<List<Warehouse>> watchWarehouses() =>
      _db.select(_db.warehouses).map((r) => Warehouse(id: r.id, name: r.name, city: r.city)).watch();

  Stream<List<StockItem>> watchStock(String warehouseId, {String search = ''}) =>
      _db.stockWithPending(warehouseId, search: search).watch();

  @override
  Future<StockItem?> item(String sku, String warehouseId) async =>
      (await _db.stockWithPending(warehouseId).get()).where((i) => i.sku == sku).firstOrNull;

  Stream<List<Movement>> watchMovements({String? sku, String? warehouseId, int limit = 100}) {
    final query = _db.select(_db.movements)
      ..where(
        (m) => Expression.and([
          if (sku != null) m.sku.equals(sku),
          if (warehouseId != null) m.warehouseId.equals(warehouseId) | m.toWarehouseId.equals(warehouseId),
        ]),
      )
      ..orderBy([(m) => OrderingTerm.desc(m.createdAt)])
      ..limit(limit);
    return query.map(_toMovement).watch();
  }

  Stream<int> watchPendingCount() => queue.watchPendingCount();

  // ---- server pulls --------------------------------------------------------

  /// Refreshes warehouses and the stock of [warehouseId] from the server.
  ///
  /// Only server-confirmed quantities are replaced; pending local movements
  /// stay in place and are re-applied on top — local work is rebased, never
  /// lost.
  Future<void> refresh(String? warehouseId) async {
    final warehouses = await _api.warehouses(user);
    await _db.batch(
      (b) => b.insertAllOnConflictUpdate(_db.warehouses, [
        for (final w in warehouses) WarehousesCompanion.insert(id: w.id, name: w.name, city: w.city),
      ]),
    );
    final target = warehouseId ?? warehouses.firstOrNull?.id;
    if (target == null) return;
    final stock = await _api.stock(user, target);
    await _db.batch(
      (b) => b.insertAllOnConflictUpdate(_db.stock, [
        for (final s in stock)
          StockCompanion.insert(
            sku: s.sku,
            warehouseId: s.warehouseId,
            name: s.name,
            barcode: s.barcode,
            unit: s.unit,
            serverQuantity: s.serverQuantity,
          ),
      ]),
    );
  }

  Future<List<AdjustmentRequest>> pendingAdjustments() => _api.pendingAdjustments(user);

  // ---- writes ------------------------------------------------------------

  @override
  Future<Movement> recordMovement({
    required MovementType type,
    required String sku,
    required String warehouseId,
    required int delta,
    String? toWarehouseId,
    String note = '',
  }) async {
    final movement = Movement(
      id: _uuid.v4(),
      type: type,
      sku: sku,
      warehouseId: warehouseId,
      delta: delta,
      toWarehouseId: toWarehouseId,
      note: note.trim(),
      createdBy: user.name,
      createdAt: _clock(),
      status: MovementStatus.pending,
    );
    await _db.transaction(() async {
      await _db
          .into(_db.movements)
          .insert(
            MovementsCompanion.insert(
              id: movement.id,
              type: type,
              sku: sku,
              warehouseId: warehouseId,
              toWarehouseId: Value(toWarehouseId),
              delta: delta,
              note: Value(movement.note),
              createdBy: movement.createdBy,
              createdAt: movement.createdAt,
              status: MovementStatus.pending,
            ),
          );
      await queue.enqueue(_Ops.movement, {'id': movement.id}, group: stockKey(sku, warehouseId));
    });
    unawaited(queue.drain());
    return movement;
  }

  @override
  Future<void> requestAdjustment(AdjustmentRequest request) async {
    await queue.enqueue(_Ops.requestAdjustment, _requestToJson(request), group: 'approvals');
    unawaited(queue.drain());
  }

  @override
  Future<void> decideAdjustment(String requestId, {required bool approve}) async {
    await queue.enqueue(_Ops.decideAdjustment, {'id': requestId, 'approve': approve}, group: 'approvals');
    await queue.drain();
  }

  Future<void> dismissRejected(String movementId) => (_db.delete(
    _db.movements,
  )..where((m) => m.id.equals(movementId) & m.status.equalsValue(MovementStatus.rejected))).go();

  // ---- delivery --------------------------------------------------------------

  Future<Outcome> _deliver(QueuedOperation op) async {
    try {
      switch (op.type) {
        case _Ops.movement:
          return await _deliverMovement(op);
        case _Ops.requestAdjustment:
          await _api.requestAdjustment(user, _requestFromJson(op.payload), idempotencyKey: op.idempotencyKey);
          return const Outcome.delivered();
        case _Ops.decideAdjustment:
          final confirmed = await _api.decideAdjustment(
            user,
            op.payload['id']! as String,
            approve: op.payload['approve']! as bool,
            idempotencyKey: op.idempotencyKey,
          );
          await _applyConfirmed(confirmed);
          return const Outcome.delivered();
        default:
          return Outcome.rejected('unknown operation ${op.type}');
      }
    } on Offline {
      return const Outcome.retryLater('offline');
    }
  }

  Future<Outcome> _deliverMovement(QueuedOperation op) async {
    final row = await (_db.select(
      _db.movements,
    )..where((m) => m.id.equals(op.payload['id']! as String))).getSingleOrNull();
    if (row == null) return const Outcome.delivered(); // dismissed locally
    final movement = _toMovement(row);
    try {
      final confirmed = await _api.submitMovement(user, movement, idempotencyKey: op.idempotencyKey);
      // One transaction: the movement stops counting as pending at the same
      // moment its effect lands in the server quantity — no flicker, no
      // double counting.
      await _db.transaction(() async {
        await _applyConfirmed(confirmed);
        await _setStatus(movement.id, MovementStatus.synced);
      });
      return const Outcome.delivered();
    } on StockConflict catch (e) {
      await _db.transaction(() async {
        await _applyConfirmed({stockKey(movement.sku, movement.warehouseId): e.available});
        await _setStatus(movement.id, MovementStatus.rejected, reason: 'insufficient_stock:${e.available}');
      });
      return Outcome.rejected(e.message);
    } on ApiError catch (e) {
      if (e is Offline) rethrow;
      await _setStatus(movement.id, MovementStatus.rejected, reason: e.message);
      return Outcome.rejected(e.message);
    }
  }

  Future<void> _applyConfirmed(ConfirmedStock confirmed) async {
    for (final MapEntry(:key, :value) in confirmed.entries) {
      final [sku, warehouseId] = key.split('@');
      await (_db.update(_db.stock)..where((s) => s.sku.equals(sku) & s.warehouseId.equals(warehouseId))).write(
        StockCompanion(serverQuantity: Value(value)),
      );
    }
  }

  Future<void> _setStatus(String id, MovementStatus status, {String? reason}) =>
      (_db.update(_db.movements)..where((m) => m.id.equals(id))).write(
        MovementsCompanion(status: Value(status), rejectReason: Value(reason)),
      );

  Movement _toMovement(MovementRow r) => Movement(
    id: r.id,
    type: r.type,
    sku: r.sku,
    warehouseId: r.warehouseId,
    toWarehouseId: r.toWarehouseId,
    delta: r.delta,
    note: r.note,
    createdBy: r.createdBy,
    createdAt: r.createdAt,
    status: r.status,
    rejectReason: r.rejectReason,
  );

  Map<String, Object?> _requestToJson(AdjustmentRequest r) => {
    'id': r.id,
    'sku': r.sku,
    'itemName': r.itemName,
    'warehouseId': r.warehouseId,
    'expected': r.expected,
    'counted': r.counted,
    'requestedBy': r.requestedBy,
    'requestedAt': r.requestedAt.toIso8601String(),
  };

  AdjustmentRequest _requestFromJson(Map<String, Object?> j) => AdjustmentRequest(
    id: j['id']! as String,
    sku: j['sku']! as String,
    itemName: j['itemName']! as String,
    warehouseId: j['warehouseId']! as String,
    expected: j['expected']! as int,
    counted: j['counted']! as int,
    requestedBy: j['requestedBy']! as String,
    requestedAt: DateTime.parse(j['requestedAt']! as String),
  );

  @override
  String newId() => _uuid.v4();
  @override
  DateTime now() => _clock();

  Future<void> dispose() => queue.dispose();
}
