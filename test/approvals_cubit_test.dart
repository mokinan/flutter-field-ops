import 'package:drift/native.dart';
import 'package:field_ops/data/api/fake_field_ops_api.dart';
import 'package:field_ops/data/api/field_ops_api.dart';
import 'package:field_ops/data/inventory_repository.dart';
import 'package:field_ops/data/local/tenant_database.dart';
import 'package:field_ops/domain/auth.dart';
import 'package:field_ops/domain/inventory.dart';
import 'package:field_ops/features/approvals/approvals_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFieldOpsApi api;
  final dbs = <TenantDatabase>[];
  final repos = <InventoryRepository>[];

  Future<InventoryRepository> as(Role role) async {
    final db = TenantDatabase.forTesting(NativeDatabase.memory());
    final repo = InventoryRepository(
      user: FakeFieldOpsApi.demoUsers.firstWhere((u) => u.tenant.id == 'northwind' && u.role == role),
      db: db,
      api: api,
    );
    dbs.add(db);
    repos.add(repo);
    await repo.refresh('ruh');
    return repo;
  }

  setUp(() => api = FakeFieldOpsApi(latency: Duration.zero));

  tearDown(() async {
    for (final r in repos) {
      await r.dispose();
    }
    for (final d in dbs) {
      await d.close();
    }
    repos.clear();
    dbs.clear();
  });

  test('loads pending requests, approves, and reloads', () async {
    final clerk = await as(Role.clerk);
    await clerk.requestAdjustment(
      AdjustmentRequest(
        id: 'r1',
        sku: 'PPE-HLM-01',
        itemName: 'Safety helmet',
        warehouseId: 'ruh',
        expected: 50,
        counted: 20,
        requestedBy: 'Omar',
        requestedAt: DateTime(2026),
      ),
    );
    await clerk.queue.drain();
    final before = api.serverQuantity('northwind', 'PPE-HLM-01', 'ruh');

    final cubit = ApprovalsCubit(await as(Role.manager));
    await cubit.load();
    expect(cubit.state.requests.single.variance, -30);

    await cubit.decide(cubit.state.requests.single, approve: true);
    expect(cubit.state.requests, isEmpty);
    expect(api.serverQuantity('northwind', 'PPE-HLM-01', 'ruh'), before - 30);
    await cubit.close();
  });

  test('reports when offline', () async {
    final cubit = ApprovalsCubit(await as(Role.manager));
    api.offline.value = true;
    await cubit.load();
    expect(cubit.state.error, isA<Offline>());
    expect(cubit.state.loading, isFalse);
    await cubit.close();
  });
}
