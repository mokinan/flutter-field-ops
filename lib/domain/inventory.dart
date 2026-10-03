import 'package:equatable/equatable.dart';

class Warehouse extends Equatable {
  const Warehouse({required this.id, required this.name, required this.city});

  final String id;
  final String name;
  final String city;

  @override
  List<Object> get props => [id, name, city];
}

/// Stock of one SKU in one warehouse.
///
/// [serverQuantity] is the last value confirmed by the server;
/// [pendingDelta] is the sum of this device's movements not yet confirmed.
/// What the user sees is their sum — local work rebased on server truth.
class StockItem extends Equatable {
  const StockItem({
    required this.sku,
    required this.warehouseId,
    required this.name,
    required this.barcode,
    required this.unit,
    required this.serverQuantity,
    required this.pendingDelta,
  });

  final String sku;
  final String warehouseId;
  final String name;
  final String barcode;
  final String unit;
  final int serverQuantity;
  final int pendingDelta;

  int get quantity => serverQuantity + pendingDelta;
  bool get hasPendingChanges => pendingDelta != 0;

  @override
  List<Object> get props => [sku, warehouseId, name, barcode, unit, serverQuantity, pendingDelta];
}

enum MovementType { receive, issue, transfer, adjustment }

enum MovementStatus { pending, synced, rejected }

/// A stock change recorded on the device.
class Movement extends Equatable {
  const Movement({
    required this.id,
    required this.type,
    required this.sku,
    required this.warehouseId,
    required this.delta,
    required this.createdBy,
    required this.createdAt,
    required this.status,
    this.toWarehouseId,
    this.note = '',
    this.rejectReason,
  });

  final String id;
  final MovementType type;
  final String sku;
  final String warehouseId;

  /// Signed change at [warehouseId]. A transfer also adds `-delta` at
  /// [toWarehouseId].
  final int delta;
  final String? toWarehouseId;
  final String note;
  final String createdBy;
  final DateTime createdAt;
  final MovementStatus status;
  final String? rejectReason;

  @override
  List<Object?> get props => [
    id,
    type,
    sku,
    warehouseId,
    delta,
    toWarehouseId,
    note,
    createdBy,
    createdAt,
    status,
    rejectReason,
  ];
}

/// A counted line in a stock count.
class CountLine extends Equatable {
  const CountLine({required this.sku, required this.name, required this.expected, this.counted});

  final String sku;
  final String name;
  final int expected;
  final int? counted;

  int get variance => (counted ?? expected) - expected;

  CountLine withCount(int? value) => CountLine(sku: sku, name: name, expected: expected, counted: value);

  @override
  List<Object?> get props => [sku, name, expected, counted];
}

/// Decides which count variances a clerk may apply alone.
///
/// Small differences are routine (breakage, miscounts) and are applied
/// immediately; large ones need a manager — the classic control against
/// stock "disappearing" through adjustments.
class VariancePolicy {
  const VariancePolicy({this.maxUnits = 5, this.maxPercent = 10});

  final int maxUnits;
  final int maxPercent;

  bool needsApproval(CountLine line) {
    final variance = line.variance.abs();
    if (variance == 0) return false;
    if (variance > maxUnits) return true;
    return line.expected > 0 && variance * 100 > line.expected * maxPercent;
  }
}

enum ApprovalStatus { pending, approved, rejected }

class AdjustmentRequest extends Equatable {
  const AdjustmentRequest({
    required this.id,
    required this.sku,
    required this.itemName,
    required this.warehouseId,
    required this.expected,
    required this.counted,
    required this.requestedBy,
    required this.requestedAt,
    this.status = ApprovalStatus.pending,
  });

  final String id;
  final String sku;
  final String itemName;
  final String warehouseId;
  final int expected;
  final int counted;
  final String requestedBy;
  final DateTime requestedAt;
  final ApprovalStatus status;

  int get variance => counted - expected;

  @override
  List<Object> get props => [id, sku, itemName, warehouseId, expected, counted, requestedBy, requestedAt, status];
}
