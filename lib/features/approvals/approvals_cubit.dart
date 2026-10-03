import 'package:equatable/equatable.dart';
import 'package:field_ops/data/api/field_ops_api.dart';
import 'package:field_ops/data/inventory_repository.dart';
import 'package:field_ops/domain/inventory.dart';
import 'package:field_ops/domain/use_cases.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ApprovalsState extends Equatable {
  const ApprovalsState({this.loading = true, this.requests = const [], this.error, this.deciding = const {}});

  final bool loading;
  final List<AdjustmentRequest> requests;
  final ApiError? error;

  /// Ids being approved or rejected right now.
  final Set<String> deciding;

  @override
  List<Object?> get props => [loading, requests, error, deciding];
}

/// Manager's queue of large count variances. Approvals act on live server
/// figures, so this screen needs a connection — unlike everything else.
class ApprovalsCubit extends Cubit<ApprovalsState> {
  ApprovalsCubit(this._repository) : _decide = DecideAdjustment(_repository), super(const ApprovalsState());

  final InventoryRepository _repository;
  final DecideAdjustment _decide;

  Future<void> load() async {
    emit(ApprovalsState(requests: state.requests));
    try {
      final requests = await _repository.pendingAdjustments();
      if (!isClosed) emit(ApprovalsState(loading: false, requests: requests));
    } on ApiError catch (e) {
      if (!isClosed) emit(ApprovalsState(loading: false, requests: state.requests, error: e));
    }
  }

  Future<void> decide(AdjustmentRequest request, {required bool approve}) async {
    emit(
      ApprovalsState(loading: false, requests: state.requests, deciding: {...state.deciding, request.id}),
    );
    await _decide(request, approve: approve);
    await load();
  }
}
