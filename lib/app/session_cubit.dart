import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:field_ops/data/api/fake_field_ops_api.dart';
import 'package:field_ops/data/api/field_ops_api.dart';
import 'package:field_ops/data/inventory_repository.dart';
import 'package:field_ops/data/local/tenant_database.dart';
import 'package:field_ops/domain/auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class SessionState extends Equatable {
  const SessionState();

  @override
  List<Object?> get props => [];
}

final class SignedOut extends SessionState {
  const SignedOut({this.error, this.busy = false});
  final ApiError? error;
  final bool busy;

  @override
  List<Object?> get props => [error, busy];
}

final class SignedIn extends SessionState {
  const SignedIn(this.repository);
  final InventoryRepository repository;

  User get user => repository.user;

  @override
  List<Object?> get props => [repository];
}

/// Opens and closes everything that is scoped to a signed-in user and
/// tenant: the tenant's database, the repository and its sync queue.
class SessionCubit extends Cubit<SessionState> {
  SessionCubit(this._api, {TenantDatabase Function(String tenantId)? openDatabase})
    : _openDatabase = openDatabase ?? TenantDatabase.forTenant,
      super(const SignedOut()) {
    // Reconnecting is the moment to sync: skip any backoff still pending.
    _api.offline.addListener(_onConnectivity);
  }

  final FakeFieldOpsApi _api;
  final TenantDatabase Function(String tenantId) _openDatabase;
  TenantDatabase? _db;

  Future<void> signIn({required String tenantId, required String email, required String password}) async {
    emit(const SignedOut(busy: true));
    try {
      final user = await _api.login(tenantId: tenantId, email: email, password: password);
      final db = _db = _openDatabase(user.tenant.id);
      final repository = InventoryRepository(user: user, db: db, api: _api);
      await repository.refresh(null);
      repository.queue.start();
      emit(SignedIn(repository));
    } on ApiError catch (e) {
      await _close();
      emit(SignedOut(error: e));
    }
  }

  Future<void> signOut() async {
    await _close();
    emit(const SignedOut());
  }

  void _onConnectivity() {
    final current = state;
    if (!_api.offline.value && current is SignedIn) unawaited(current.repository.queue.drain(force: true));
  }

  Future<void> _close() async {
    final current = state;
    if (current is SignedIn) await current.repository.dispose();
    await _db?.close();
    _db = null;
  }

  @override
  Future<void> close() async {
    _api.offline.removeListener(_onConnectivity);
    await _close();
    return super.close();
  }
}
