import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:field_ops/domain/inventory.dart';

part 'tenant_database.g.dart';

@DataClassName('WarehouseRow')
class Warehouses extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get city => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Server-confirmed stock. Local, unconfirmed changes live in [Movements].
@DataClassName('StockRow')
class Stock extends Table {
  TextColumn get sku => text()();
  TextColumn get warehouseId => text()();
  TextColumn get name => text()();
  TextColumn get barcode => text()();
  TextColumn get unit => text()();
  IntColumn get serverQuantity => integer()();

  @override
  Set<Column<Object>> get primaryKey => {sku, warehouseId};
}

@DataClassName('MovementRow')
class Movements extends Table {
  TextColumn get id => text()();
  IntColumn get type => intEnum<MovementType>()();
  TextColumn get sku => text()();
  TextColumn get warehouseId => text()();
  TextColumn get toWarehouseId => text().nullable()();
  IntColumn get delta => integer()();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get status => intEnum<MovementStatus>()();
  TextColumn get rejectReason => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Backing table for `durable_sync_queue`.
@DataClassName('QueueRow')
class QueueEntries extends Table {
  TextColumn get id => text()();
  TextColumn get json => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One database **per tenant**: switching company opens a different file, so
/// one company's data can never appear in another's screens. See ADR 0002.
@DriftDatabase(tables: [Warehouses, Stock, Movements, QueueEntries])
class TenantDatabase extends _$TenantDatabase {
  TenantDatabase.forTenant(String tenantId) : super(driftDatabase(name: 'fieldops_$tenantId'));

  TenantDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;

  /// Stock for a warehouse with this device's pending deltas applied —
  /// including the incoming side of pending transfers.
  Selectable<StockItem> stockWithPending(String warehouseId, {String search = ''}) {
    final pattern = '%${search.trim().toLowerCase()}%';
    return customSelect(
      '''
      SELECT s.*,
        COALESCE((SELECT SUM(m.delta) FROM movements m
                  WHERE m.status = ?2 AND m.sku = s.sku AND m.warehouse_id = s.warehouse_id), 0)
      - COALESCE((SELECT SUM(m.delta) FROM movements m
                  WHERE m.status = ?2 AND m.sku = s.sku AND m.to_warehouse_id = s.warehouse_id), 0)
        AS pending_delta
      FROM stock s
      WHERE s.warehouse_id = ?1
        AND (?3 = '%%' OR lower(s.name) LIKE ?3 OR lower(s.sku) LIKE ?3 OR s.barcode LIKE ?3)
      ORDER BY s.name
      ''',
      variables: [
        Variable<String>(warehouseId),
        Variable<int>(MovementStatus.pending.index),
        Variable<String>(pattern),
      ],
      readsFrom: {stock, movements},
    ).map(
      (row) => StockItem(
        sku: row.read<String>('sku'),
        warehouseId: row.read<String>('warehouse_id'),
        name: row.read<String>('name'),
        barcode: row.read<String>('barcode'),
        unit: row.read<String>('unit'),
        serverQuantity: row.read<int>('server_quantity'),
        pendingDelta: row.read<int>('pending_delta'),
      ),
    );
  }
}
