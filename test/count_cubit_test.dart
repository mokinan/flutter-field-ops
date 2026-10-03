import 'package:drift/native.dart';
import 'package:field_ops/data/api/fake_field_ops_api.dart';
import 'package:field_ops/data/inventory_repository.dart';
import 'package:field_ops/data/local/tenant_database.dart';
import 'package:field_ops/domain/auth.dart';
import 'package:field_ops/domain/use_cases.dart';
import 'package:field_ops/features/count/count_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TenantDatabase db;
  late InventoryRepository repo;
  late FakeFieldOpsApi api;

  setUp(() async {
    api = FakeFieldOpsApi(latency: Duration.zero);
    db = TenantDatabase.forTesting(NativeDatabase.memory());
    repo = InventoryRepository(
      user: FakeFieldOpsApi.demoUsers.firstWhere((u) => u.tenant.id == 'northwind' && u.role == Role.clerk),
      db: db,
      api: api,
    );
    await repo.refresh('ruh');
  });

  tearDown(() async {
    await repo.dispose();
    await db.close();
  });

  test('each scan adds one unit; unknown barcodes are reported', () async {
    final cubit = CountCubit(repo);
    await cubit.start('ruh');
    final helmet = (await repo.watchStock('ruh').first).firstWhere((i) => i.sku == 'PPE-HLM-01');

    expect(await cubit.scan(helmet.barcode), isTrue);
    expect(await cubit.scan(helmet.barcode), isTrue);
    expect(await cubit.scan('0000000000000'), isFalse);

    final line = cubit.state.lines.firstWhere((l) => l.sku == helmet.sku);
    expect(line.counted, 2);
    expect(cubit.state.lastScanned, helmet.sku);
    expect(cubit.state.counted, 1);
    await cubit.close();
  });

  test('submitting reports what was applied and what needs approval', () async {
    final cubit = CountCubit(repo);
    await cubit.start('ruh');
    final lines = cubit.state.lines;
    cubit
      ..setCount(lines[0].sku, lines[0].expected - 1)
      ..setCount(lines[1].sku, lines[1].expected + 50)
      ..setCount(lines[2].sku, lines[2].expected);

    await cubit.submit();

    expect(cubit.state.phase, CountPhase.done);
    expect(cubit.state.result, const CountResult(applied: 1, sentForApproval: 1, unchanged: 12));
    cubit.reset();
    expect(cubit.state.phase, CountPhase.idle);
    await cubit.close();
  });
}
