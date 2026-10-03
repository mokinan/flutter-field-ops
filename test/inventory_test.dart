import 'package:drift/native.dart';
import 'package:durable_sync_queue/durable_sync_queue.dart';
import 'package:field_ops/data/api/fake_field_ops_api.dart';
import 'package:field_ops/data/inventory_repository.dart';
import 'package:field_ops/data/local/tenant_database.dart';
import 'package:field_ops/domain/auth.dart';
import 'package:field_ops/domain/inventory.dart';
import 'package:field_ops/domain/use_cases.dart';
import 'package:flutter_test/flutter_test.dart';

const sku = 'PPE-HLM-01';
const tenant = 'northwind';

User userWith(Role role) => FakeFieldOpsApi.demoUsers.firstWhere((u) => u.tenant.id == tenant && u.role == role);

void main() {
  late FakeFieldOpsApi api;
  late TenantDatabase db;
  late InventoryRepository repo;

  Future<InventoryRepository> signIn(Role role) async {
    final r = InventoryRepository(
      user: userWith(role),
      db: db,
      api: api,
      backoff: const ConstantBackoff(Duration.zero),
    );
    await r.refresh('ruh');
    return r;
  }

  Future<StockItem> stockOf(String warehouse) async => (await repo.item(sku, warehouse))!;

  setUp(() async {
    api = FakeFieldOpsApi(latency: Duration.zero);
    db = TenantDatabase.forTesting(NativeDatabase.memory());
    repo = await signIn(Role.clerk);
  });

  tearDown(() async {
    await repo.dispose();
    await db.close();
  });

  group('local-first movements', () {
    test('show immediately as pending, then confirm', () async {
      final before = await stockOf('ruh');
      api.offline.value = true;

      await RecordMovement(repo)(type: MovementType.receive, sku: sku, warehouseId: 'ruh', quantity: 12);
      final pending = await stockOf('ruh');
      expect(pending.quantity, before.quantity + 12);
      expect(pending.pendingDelta, 12);

      api.offline.value = false;
      await repo.queue.drain(force: true);
      final synced = await stockOf('ruh');
      expect(synced.quantity, before.quantity + 12);
      expect(synced.pendingDelta, 0, reason: 'now part of the server quantity');
      expect(api.serverQuantity(tenant, sku, 'ruh'), before.quantity + 12);
    });

    test('a refresh rebases pending work on newer server figures', () async {
      final start = (await stockOf('ruh')).quantity;
      api.offline.value = true;
      await RecordMovement(repo)(type: MovementType.issue, sku: sku, warehouseId: 'ruh', quantity: 3);
      await repo.queue.drain(); // fails offline; stays pending

      // Meanwhile another device receives 50 units.
      api
        ..simulateOtherDevice(tenant, sku, 'ruh', 50)
        ..offline.value = false;
      await repo.refresh('ruh');

      final item = await stockOf('ruh');
      expect(item.serverQuantity, start + 50);
      expect(item.quantity, start + 50 - 3, reason: 'local issue still applied on top');
    });

    test('a server-side conflict rejects the movement and restores truth', () async {
      api.offline.value = true;
      final available = (await stockOf('ruh')).quantity;
      await RecordMovement(repo)(type: MovementType.issue, sku: sku, warehouseId: 'ruh', quantity: available);
      await repo.queue.drain(); // fails offline; stays pending

      // Another device empties the shelf before we reconnect.
      api
        ..simulateOtherDevice(tenant, sku, 'ruh', -available)
        ..offline.value = false;
      final report = await repo.queue.drain(force: true);

      expect(report.deadLettered, 1);
      final movement = (await repo.watchMovements().first).single;
      expect(movement.status, MovementStatus.rejected);
      expect(movement.rejectReason, 'insufficient_stock:0');
      expect((await stockOf('ruh')).quantity, 0, reason: 'rejected work no longer counts');
    });

    test('transfers move stock between warehouses', () async {
      await repo.refresh('jed');
      final ruh = (await stockOf('ruh')).quantity;
      final jed = (await stockOf('jed')).quantity;

      await RecordMovement(repo)(
        type: MovementType.transfer,
        sku: sku,
        warehouseId: 'ruh',
        toWarehouseId: 'jed',
        quantity: 5,
      );
      expect((await stockOf('ruh')).quantity, ruh - 5);
      expect((await stockOf('jed')).quantity, jed + 5, reason: 'incoming side counts while pending');

      await repo.queue.drain();
      expect(api.serverQuantity(tenant, sku, 'jed'), jed + 5);
      expect((await stockOf('jed')).pendingDelta, 0);
    });

    test('movements on one stock line stay in order', () async {
      api.offline.value = true;
      await RecordMovement(repo)(type: MovementType.receive, sku: sku, warehouseId: 'ruh', quantity: 1000);
      final total = (await stockOf('ruh')).quantity;
      // Only possible because the receive above is applied first.
      await RecordMovement(repo)(type: MovementType.issue, sku: sku, warehouseId: 'ruh', quantity: total);

      api.offline.value = false;
      final report = await repo.queue.drain(force: true);
      expect(report.delivered, 2);
      expect(api.serverQuantity(tenant, sku, 'ruh'), 0);
    });
  });

  group('RecordMovement rules', () {
    test('rejects outgoing quantities above local stock', () async {
      final available = (await stockOf('ruh')).quantity;
      expect(
        () => RecordMovement(repo)(type: MovementType.issue, sku: sku, warehouseId: 'ruh', quantity: available + 1),
        throwsA(isA<InsufficientStock>().having((e) => e.available, 'available', available)),
      );
    });

    test('rejects zero quantities and same-warehouse transfers', () async {
      expect(
        () => RecordMovement(repo)(type: MovementType.receive, sku: sku, warehouseId: 'ruh', quantity: 0),
        throwsA(isA<InvalidMovement>()),
      );
      expect(
        () => RecordMovement(repo)(
          type: MovementType.transfer,
          sku: sku,
          warehouseId: 'ruh',
          toWarehouseId: 'ruh',
          quantity: 1,
        ),
        throwsA(isA<InvalidMovement>()),
      );
    });

    test('viewers cannot record movements — enforced in the domain', () async {
      await repo.dispose();
      repo = await signIn(Role.viewer);
      expect(
        () => RecordMovement(repo)(type: MovementType.receive, sku: sku, warehouseId: 'ruh', quantity: 1),
        throwsA(isA<PermissionDenied>()),
      );
    });
  });

  group('stock counts', () {
    Future<List<CountLine>> lines(Map<String, int> counted) async {
      final items = await repo.watchStock('ruh').first;
      return [
        for (final i in items)
          CountLine(sku: i.sku, name: i.name, expected: i.quantity, counted: counted[i.sku] ?? i.quantity),
      ];
    }

    test("a clerk's small variance is applied, a large one goes to a manager", () async {
      final items = {for (final i in await repo.watchStock('ruh').first) i.sku: i.quantity};
      final result = await SubmitCount(repo)(
        warehouseId: 'ruh',
        lines: await lines({sku: items[sku]! - 2, 'PPE-VST-L': items['PPE-VST-L']! - 40}),
      );

      expect(result.applied, 1);
      expect(result.sentForApproval, 1);
      await repo.queue.drain();
      expect(api.serverQuantity(tenant, sku, 'ruh'), items[sku]! - 2);
      expect(api.serverQuantity(tenant, 'PPE-VST-L', 'ruh'), items['PPE-VST-L'], reason: 'awaiting approval');

      // A manager approves on their own device.
      final manager = await signIn(Role.manager);
      final pending = await manager.pendingAdjustments();
      expect(pending.single.variance, -40);
      await DecideAdjustment(manager)(pending.single, approve: true);
      expect(api.serverQuantity(tenant, 'PPE-VST-L', 'ruh'), items['PPE-VST-L']! - 40);
      expect(await manager.pendingAdjustments(), isEmpty);
      await manager.dispose();
    });

    test("a manager's large variance is applied directly", () async {
      await repo.dispose();
      repo = await signIn(Role.manager);
      final before = (await stockOf('ruh')).quantity;
      final result = await SubmitCount(repo)(warehouseId: 'ruh', lines: await lines({sku: before + 30}));
      expect(result, const CountResult(applied: 1, sentForApproval: 0, unchanged: 13));
    });

    test('only managers can decide adjustments', () async {
      final request = AdjustmentRequest(
        id: 'r1',
        sku: sku,
        itemName: 'x',
        warehouseId: 'ruh',
        expected: 10,
        counted: 2,
        requestedBy: 'Omar',
        requestedAt: DateTime(2026),
      );
      expect(() => DecideAdjustment(repo)(request, approve: true), throwsA(isA<PermissionDenied>()));
    });
  });

  group('VariancePolicy', () {
    const policy = VariancePolicy();
    CountLine line(int expected, int counted) => CountLine(sku: 's', name: 'n', expected: expected, counted: counted);

    test('applies small differences, escalates large ones', () {
      expect(policy.needsApproval(line(100, 100)), isFalse);
      expect(policy.needsApproval(line(100, 95)), isFalse, reason: '5 units, 5%');
      expect(policy.needsApproval(line(100, 94)), isTrue, reason: 'more than 5 units');
      expect(policy.needsApproval(line(20, 17)), isTrue, reason: '15% of a small stock');
      expect(policy.needsApproval(line(0, 3)), isFalse, reason: 'found stock within the unit limit');
    });
  });

  group('roles', () {
    test('map to permissions', () {
      expect(userWith(Role.manager).can(Permission.approveAdjustment), isTrue);
      expect(userWith(Role.clerk).can(Permission.approveAdjustment), isFalse);
      expect(userWith(Role.clerk).can(Permission.countStock), isTrue);
      expect(userWith(Role.viewer).can(Permission.recordMovement), isFalse);
    });

    test('the server enforces them too', () async {
      await expectLater(api.pendingAdjustments(userWith(Role.clerk)), throwsA(isA<Exception>()));
    });
  });

  test('barcodes carry a valid EAN-13 check digit', () {
    expect(ean13('400638133393'), '4006381333931');
  });
}
