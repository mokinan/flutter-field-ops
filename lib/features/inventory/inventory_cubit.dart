import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:field_ops/data/api/field_ops_api.dart';
import 'package:field_ops/data/inventory_repository.dart';
import 'package:field_ops/domain/inventory.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class InventoryState extends Equatable {
  const InventoryState({
    this.warehouses = const [],
    this.warehouseId,
    this.search = '',
    this.items = const [],
    this.selectedSku,
    this.refreshing = false,
    this.refreshError,
  });

  final List<Warehouse> warehouses;
  final String? warehouseId;
  final String search;
  final List<StockItem> items;

  /// The item shown in the detail pane on wide layouts.
  final String? selectedSku;
  final bool refreshing;
  final ApiError? refreshError;

  Warehouse? get warehouse => warehouses.where((w) => w.id == warehouseId).firstOrNull;
  StockItem? get selected => items.where((i) => i.sku == selectedSku).firstOrNull;

  InventoryState copyWith({
    List<Warehouse>? warehouses,
    String? warehouseId,
    String? search,
    List<StockItem>? items,
    String? Function()? selectedSku,
    bool? refreshing,
    ApiError? Function()? refreshError,
  }) => InventoryState(
    warehouses: warehouses ?? this.warehouses,
    warehouseId: warehouseId ?? this.warehouseId,
    search: search ?? this.search,
    items: items ?? this.items,
    selectedSku: selectedSku != null ? selectedSku() : this.selectedSku,
    refreshing: refreshing ?? this.refreshing,
    refreshError: refreshError != null ? refreshError() : this.refreshError,
  );

  @override
  List<Object?> get props => [warehouses, warehouseId, search, items, selectedSku, refreshing, refreshError];
}

/// Inventory list for one warehouse, live from the local database.
class InventoryCubit extends Cubit<InventoryState> {
  InventoryCubit(this._repository) : super(const InventoryState()) {
    _warehouses = _repository.watchWarehouses().listen((list) {
      emit(state.copyWith(warehouses: list));
      if (state.warehouseId == null && list.isNotEmpty) selectWarehouse(list.first.id);
    });
  }

  final InventoryRepository _repository;
  StreamSubscription<List<Warehouse>>? _warehouses;
  StreamSubscription<List<StockItem>>? _items;

  void selectWarehouse(String id) {
    emit(state.copyWith(warehouseId: id, selectedSku: () => null));
    _watchItems();
    unawaited(refresh());
  }

  void search(String text) {
    emit(state.copyWith(search: text));
    _watchItems();
  }

  /// Finds an item by scanned barcode in the current warehouse.
  StockItem? findByBarcode(String code) => state.items.where((i) => i.barcode == code.trim()).firstOrNull;

  void select(String? sku) => emit(state.copyWith(selectedSku: () => sku));

  Future<void> refresh() async {
    final id = state.warehouseId;
    if (id == null) return;
    emit(state.copyWith(refreshing: true, refreshError: () => null));
    try {
      await _repository.refresh(id);
      if (!isClosed) emit(state.copyWith(refreshing: false));
    } on ApiError catch (e) {
      // Offline is normal in the field: keep showing local data.
      if (!isClosed) emit(state.copyWith(refreshing: false, refreshError: () => e));
    }
  }

  void _watchItems() {
    unawaited(_items?.cancel());
    _items = _repository
        .watchStock(state.warehouseId!, search: state.search)
        .listen((items) => emit(state.copyWith(items: items)));
  }

  @override
  Future<void> close() async {
    await _warehouses?.cancel();
    await _items?.cancel();
    return super.close();
  }
}
