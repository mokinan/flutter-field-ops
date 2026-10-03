import 'package:equatable/equatable.dart';
import 'package:field_ops/data/inventory_repository.dart';
import 'package:field_ops/domain/inventory.dart';
import 'package:field_ops/domain/use_cases.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum CountPhase { idle, counting, submitting, done }

class CountState extends Equatable {
  const CountState({
    this.phase = CountPhase.idle,
    this.warehouseId,
    this.lines = const [],
    this.result,
    this.lastScanned,
  });

  final CountPhase phase;
  final String? warehouseId;
  final List<CountLine> lines;
  final CountResult? result;
  final String? lastScanned;

  int get counted => lines.where((l) => l.counted != null).length;
  int get withVariance => lines.where((l) => l.counted != null && l.variance != 0).length;

  CountState copyWith({
    CountPhase? phase,
    String? warehouseId,
    List<CountLine>? lines,
    CountResult? result,
    String? lastScanned,
  }) => CountState(
    phase: phase ?? this.phase,
    warehouseId: warehouseId ?? this.warehouseId,
    lines: lines ?? this.lines,
    result: result ?? this.result,
    lastScanned: lastScanned ?? this.lastScanned,
  );

  @override
  List<Object?> get props => [phase, warehouseId, lines, result, lastScanned];
}

/// A cycle count: snapshot expected quantities, record counted ones (typed
/// or scanned), then submit through [SubmitCount].
class CountCubit extends Cubit<CountState> {
  CountCubit(this._repository, {VariancePolicy policy = const VariancePolicy()})
    : _submit = SubmitCount(_repository, policy: policy),
      policy = policy,
      super(const CountState());

  final InventoryRepository _repository;
  final SubmitCount _submit;
  final VariancePolicy policy;

  Future<void> start(String warehouseId) async {
    final items = await _repository.watchStock(warehouseId).first;
    emit(
      CountState(
        phase: CountPhase.counting,
        warehouseId: warehouseId,
        lines: [for (final i in items) CountLine(sku: i.sku, name: i.name, expected: i.quantity)],
      ),
    );
  }

  void setCount(String sku, int? value) => _update(sku, (l) => l.withCount(value));

  /// Each scan of a barcode adds one unit — counting by scanning items.
  Future<bool> scan(String barcode) async {
    final items = await _repository.watchStock(state.warehouseId!).first;
    final item = items.where((i) => i.barcode == barcode.trim()).firstOrNull;
    if (item == null) return false;
    _update(item.sku, (l) => l.withCount((l.counted ?? 0) + 1));
    emit(state.copyWith(lastScanned: item.sku));
    return true;
  }

  Future<void> submit() async {
    emit(state.copyWith(phase: CountPhase.submitting));
    final result = await _submit(warehouseId: state.warehouseId!, lines: state.lines);
    emit(state.copyWith(phase: CountPhase.done, result: result));
  }

  void reset() => emit(const CountState());

  void _update(String sku, CountLine Function(CountLine) change) =>
      emit(state.copyWith(lines: [for (final l in state.lines) l.sku == sku ? change(l) : l]));
}
