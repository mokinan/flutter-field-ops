import 'package:field_ops/domain/auth.dart';
import 'package:field_ops/domain/inventory.dart';

/// What the use cases need from storage and sync. Defined in the domain and
/// implemented in the data layer, so dependencies point inwards.
abstract interface class InventoryGateway {
  User get user;

  Future<StockItem?> item(String sku, String warehouseId);

  Future<Movement> recordMovement({
    required MovementType type,
    required String sku,
    required String warehouseId,
    required int delta,
    String? toWarehouseId,
    String note,
  });

  Future<void> requestAdjustment(AdjustmentRequest request);

  Future<void> decideAdjustment(String requestId, {required bool approve});

  String newId();

  DateTime now();
}
