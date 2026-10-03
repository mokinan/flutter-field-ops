import 'dart:math';

import 'package:field_ops/data/api/field_ops_api.dart';
import 'package:field_ops/domain/auth.dart';
import 'package:field_ops/domain/inventory.dart';
import 'package:flutter/foundation.dart';

/// In-process stand-in for the backend. It enforces the same rules a real
/// server must: role checks, no negative stock, idempotent writes. Other
/// "devices" can be simulated with [simulateOtherDevice].
class FakeFieldOpsApi implements FieldOpsApi {
  FakeFieldOpsApi({this.latency = const Duration(milliseconds: 300), DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    for (final tenant in tenants) {
      _stock[tenant.id] = {
        for (final (i, item) in _catalog.indexed)
          for (final wh in _warehouses) stockKey(item.$1, wh.id): 20 + ((i * 37 + wh.id.length * 11) % 180),
      };
    }
  }

  static const tenants = [
    Tenant(id: 'northwind', name: 'Northwind Logistics'),
    Tenant(id: 'desertpeak', name: 'Desert Peak Supply'),
  ];

  static const demoPassword = 'demo';

  /// Demo accounts: one per role and tenant.
  static final List<User> demoUsers = [
    for (final tenant in tenants)
      for (final (role, name) in [(Role.manager, 'Sara'), (Role.clerk, 'Omar'), (Role.viewer, 'Lina')])
        User(
          id: '${tenant.id}-${role.name}',
          name: name,
          email: '${role.name}@${tenant.id}.test',
          role: role,
          tenant: tenant,
        ),
  ];

  static const _warehouses = [
    Warehouse(id: 'ruh', name: 'Riyadh Central', city: 'Riyadh'),
    Warehouse(id: 'jed', name: 'Jeddah Port', city: 'Jeddah'),
  ];

  /// (sku, name, unit)
  static const _catalog = [
    ('PPE-HLM-01', 'Safety helmet, white', 'pcs'),
    ('PPE-VST-L', 'Hi-vis vest, size L', 'pcs'),
    ('PPE-GLV-100', 'Nitrile gloves, box of 100', 'box'),
    ('PPE-BOT-42', 'Steel-toe boots, size 42', 'pair'),
    ('PKG-WRP-500', 'Pallet stretch wrap 500 mm', 'roll'),
    ('PKG-TIE-300', 'Cable ties 300 mm, pack of 100', 'pack'),
    ('ELC-LED-50', 'LED floodlight 50 W', 'pcs'),
    ('ELC-CBL-25', 'Copper cable 2.5 mm², 100 m', 'roll'),
    ('PLB-PVC-2', 'PVC pipe 2", 6 m', 'pcs'),
    ('BLD-CEM-50', 'Portland cement 50 kg', 'bag'),
    ('TLS-DRL-HSS', 'HSS drill bit set, 19 pcs', 'set'),
    ('SAF-EXT-6', 'Fire extinguisher 6 kg', 'pcs'),
    ('SAF-AID-01', 'First aid kit, industrial', 'pcs'),
    ('PNT-WHT-18', 'Emulsion paint white, 18 L', 'pail'),
  ];

  final Duration latency;
  final DateTime Function() _clock;
  final _random = Random(7);

  /// Toggled from Settings to reproduce field conditions.
  final ValueNotifier<bool> offline = ValueNotifier(false);

  final _stock = <String, Map<String, int>>{};
  final _replies = <String, Object>{};
  final _requests = <String, List<AdjustmentRequest>>{};

  /// Pretends another device changed stock, so the next refresh rebases
  /// this device's pending work on new server values.
  void simulateOtherDevice(String tenantId, String sku, String warehouseId, int delta) {
    final key = stockKey(sku, warehouseId);
    _stock[tenantId]![key] = max(0, _stock[tenantId]![key]! + delta);
  }

  int serverQuantity(String tenantId, String sku, String warehouseId) => _stock[tenantId]![stockKey(sku, warehouseId)]!;

  @override
  Future<User> login({required String tenantId, required String email, required String password}) async {
    await _roundTrip();
    final user = demoUsers.where((u) => u.tenant.id == tenantId && u.email == email.trim().toLowerCase()).firstOrNull;
    if (user == null || password != demoPassword) throw const Forbidden();
    return user;
  }

  @override
  Future<List<Warehouse>> warehouses(User user) async {
    await _roundTrip();
    return _warehouses;
  }

  @override
  Future<List<StockItem>> stock(User user, String warehouseId) async {
    await _roundTrip();
    _require(user, Permission.viewStock);
    return [
      for (final (i, (sku, name, unit)) in _catalog.indexed)
        StockItem(
          sku: sku,
          warehouseId: warehouseId,
          name: name,
          barcode: ean13('628${(100000000 + i * 7919).toString().substring(0, 9)}'),
          unit: unit,
          serverQuantity: _stock[user.tenant.id]![stockKey(sku, warehouseId)]!,
          pendingDelta: 0,
        ),
    ];
  }

  @override
  Future<ConfirmedStock> submitMovement(User user, Movement movement, {required String idempotencyKey}) async {
    await _roundTrip();
    final replay = _replies[idempotencyKey];
    if (replay != null) return replay as ConfirmedStock;

    _require(user, Permission.recordMovement);
    if (movement.delta == 0) throw const Invalid('zero_quantity');
    final stock = _stock[user.tenant.id]!;
    final source = stockKey(movement.sku, movement.warehouseId);
    final available = stock[source]!;
    if (available + movement.delta < 0) throw StockConflict(available: available);

    stock[source] = available + movement.delta;
    final confirmed = <String, int>{source: stock[source]!};
    if (movement.type == MovementType.transfer) {
      final destination = stockKey(movement.sku, movement.toWarehouseId!);
      stock[destination] = stock[destination]! - movement.delta;
      confirmed[destination] = stock[destination]!;
    }
    _replies[idempotencyKey] = confirmed;
    return confirmed;
  }

  @override
  Future<void> requestAdjustment(User user, AdjustmentRequest request, {required String idempotencyKey}) async {
    await _roundTrip();
    if (_replies.containsKey(idempotencyKey)) return;
    _require(user, Permission.countStock);
    (_requests[user.tenant.id] ??= []).add(request);
    _replies[idempotencyKey] = const <String, int>{};
  }

  @override
  Future<List<AdjustmentRequest>> pendingAdjustments(User user) async {
    await _roundTrip();
    _require(user, Permission.viewApprovals);
    return (_requests[user.tenant.id] ?? const []).where((r) => r.status == ApprovalStatus.pending).toList();
  }

  @override
  Future<ConfirmedStock> decideAdjustment(
    User user,
    String requestId, {
    required bool approve,
    required String idempotencyKey,
  }) async {
    await _roundTrip();
    final replay = _replies[idempotencyKey];
    if (replay != null) return replay as ConfirmedStock;
    _require(user, Permission.approveAdjustment);

    final requests = _requests[user.tenant.id] ?? [];
    final index = requests.indexWhere((r) => r.id == requestId);
    if (index < 0 || requests[index].status != ApprovalStatus.pending) throw const Invalid('not_pending');
    final request = requests[index];
    requests[index] = AdjustmentRequest(
      id: request.id,
      sku: request.sku,
      itemName: request.itemName,
      warehouseId: request.warehouseId,
      expected: request.expected,
      counted: request.counted,
      requestedBy: request.requestedBy,
      requestedAt: request.requestedAt,
      status: approve ? ApprovalStatus.approved : ApprovalStatus.rejected,
    );

    final confirmed = <String, int>{};
    if (approve) {
      // Apply the variance, not the counted figure: stock may have moved
      // since the count was taken.
      final key = stockKey(request.sku, request.warehouseId);
      final stock = _stock[user.tenant.id]!;
      stock[key] = max(0, stock[key]! + request.variance);
      confirmed[key] = stock[key]!;
    }
    _replies[idempotencyKey] = confirmed;
    return confirmed;
  }

  void _require(User user, Permission permission) {
    if (!user.can(permission)) throw const Forbidden();
  }

  Future<void> _roundTrip() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency + Duration(milliseconds: _random.nextInt(150)));
    if (offline.value) throw const Offline();
  }

  DateTime now() => _clock();
}

/// Appends the EAN-13 check digit to a 12-digit body.
String ean13(String body12) {
  assert(body12.length == 12, 'EAN-13 body must be 12 digits');
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += int.parse(body12[i]) * (i.isEven ? 1 : 3);
  }
  return '$body12${(10 - sum % 10) % 10}';
}
