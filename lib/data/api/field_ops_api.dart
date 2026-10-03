import 'package:field_ops/domain/auth.dart';
import 'package:field_ops/domain/inventory.dart';

/// Server errors the app reacts to differently.
sealed class ApiError implements Exception {
  const ApiError(this.message);
  final String message;

  @override
  String toString() => '$ApiError: $message';
}

/// No connection — retry later.
final class Offline extends ApiError {
  const Offline() : super('offline');
}

/// The server's stock no longer allows this movement.
final class StockConflict extends ApiError {
  const StockConflict({required this.available}) : super('insufficient_stock');
  final int available;
}

final class Forbidden extends ApiError {
  const Forbidden() : super('forbidden');
}

final class Invalid extends ApiError {
  const Invalid(super.message);
}

/// Server-confirmed quantities after a write, keyed by `sku@warehouse`.
typedef ConfirmedStock = Map<String, int>;

String stockKey(String sku, String warehouseId) => '$sku@$warehouseId';

/// The backend contract. Every write takes an idempotency key.
abstract interface class FieldOpsApi {
  Future<User> login({required String tenantId, required String email, required String password});

  Future<List<Warehouse>> warehouses(User user);

  /// Items with server quantities; local deltas are applied by the caller.
  Future<List<StockItem>> stock(User user, String warehouseId);

  Future<ConfirmedStock> submitMovement(User user, Movement movement, {required String idempotencyKey});

  Future<void> requestAdjustment(User user, AdjustmentRequest request, {required String idempotencyKey});

  Future<List<AdjustmentRequest>> pendingAdjustments(User user);

  Future<ConfirmedStock> decideAdjustment(
    User user,
    String requestId, {
    required bool approve,
    required String idempotencyKey,
  });
}
