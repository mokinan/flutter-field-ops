import 'package:equatable/equatable.dart';
import 'package:field_ops/domain/auth.dart';
import 'package:field_ops/domain/inventory.dart';
import 'package:field_ops/domain/inventory_gateway.dart';

/// Thrown when an outgoing movement exceeds the locally known stock.
class InsufficientStock implements Exception {
  const InsufficientStock(this.available);
  final int available;
}

class InvalidMovement implements Exception {
  const InvalidMovement(this.reason);
  final String reason;
}

/// Records a stock movement after checking permission and local stock.
///
/// The local check catches obvious mistakes instantly, even offline; the
/// server re-checks against its own (possibly newer) figures.
class RecordMovement {
  const RecordMovement(this._repository);

  final InventoryGateway _repository;

  Future<Movement> call({
    required MovementType type,
    required String sku,
    required String warehouseId,
    required int quantity,
    String? toWarehouseId,
    String note = '',
  }) async {
    if (!_repository.user.can(Permission.recordMovement)) throw const PermissionDenied(Permission.recordMovement);
    if (quantity <= 0) throw const InvalidMovement('quantity');
    if (type == MovementType.transfer && (toWarehouseId == null || toWarehouseId == warehouseId)) {
      throw const InvalidMovement('destination');
    }

    final outgoing = type == MovementType.issue || type == MovementType.transfer;
    if (outgoing) {
      final item = await _repository.item(sku, warehouseId);
      final available = item?.quantity ?? 0;
      if (quantity > available) throw InsufficientStock(available);
    }
    return _repository.recordMovement(
      type: type,
      sku: sku,
      warehouseId: warehouseId,
      delta: outgoing ? -quantity : quantity,
      toWarehouseId: type == MovementType.transfer ? toWarehouseId : null,
      note: note,
    );
  }
}

class CountResult extends Equatable {
  const CountResult({required this.applied, required this.sentForApproval, required this.unchanged});

  final int applied;
  final int sentForApproval;
  final int unchanged;

  @override
  List<Object> get props => [applied, sentForApproval, unchanged];
}

/// Turns a finished count into adjustments.
///
/// Variances within the [VariancePolicy] are applied directly. Larger ones
/// are applied directly only for users who could approve them anyway;
/// everyone else's become approval requests for a manager.
class SubmitCount {
  const SubmitCount(this._repository, {this.policy = const VariancePolicy()});

  final InventoryGateway _repository;
  final VariancePolicy policy;

  Future<CountResult> call({required String warehouseId, required List<CountLine> lines}) async {
    final user = _repository.user;
    if (!user.can(Permission.countStock)) throw const PermissionDenied(Permission.countStock);

    var applied = 0;
    var requested = 0;
    var unchanged = 0;
    for (final line in lines) {
      if (line.counted == null || line.variance == 0) {
        unchanged++;
        continue;
      }
      if (policy.needsApproval(line) && !user.can(Permission.approveAdjustment)) {
        await _repository.requestAdjustment(
          AdjustmentRequest(
            id: _repository.newId(),
            sku: line.sku,
            itemName: line.name,
            warehouseId: warehouseId,
            expected: line.expected,
            counted: line.counted!,
            requestedBy: user.name,
            requestedAt: _repository.now(),
          ),
        );
        requested++;
      } else {
        await _repository.recordMovement(
          type: MovementType.adjustment,
          sku: line.sku,
          warehouseId: warehouseId,
          delta: line.variance,
          note: 'Stock count',
        );
        applied++;
      }
    }
    return CountResult(applied: applied, sentForApproval: requested, unchanged: unchanged);
  }
}

class DecideAdjustment {
  const DecideAdjustment(this._repository);

  final InventoryGateway _repository;

  Future<void> call(AdjustmentRequest request, {required bool approve}) {
    if (!_repository.user.can(Permission.approveAdjustment)) {
      throw const PermissionDenied(Permission.approveAdjustment);
    }
    return _repository.decideAdjustment(request.id, approve: approve);
  }
}
