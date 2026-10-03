import 'package:field_ops/domain/inventory.dart';
import 'package:field_ops/features/inventory/inventory_cubit.dart';
import 'package:field_ops/features/inventory/item_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Phone layout for one item; tablets show [ItemDetails] in a side pane.
class ItemPage extends StatelessWidget {
  const ItemPage({required this.sku, super.key});

  final String sku;

  @override
  Widget build(BuildContext context) {
    final item = context.select<InventoryCubit, StockItem?>(
      (c) => c.state.items.where((i) => i.sku == sku).firstOrNull,
    );
    return Scaffold(
      appBar: AppBar(),
      body: item == null ? const Center(child: CircularProgressIndicator()) : ItemDetails(item: item),
    );
  }
}
