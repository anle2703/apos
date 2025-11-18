import 'package:flutter/material.dart';
import './product_model.dart';

class SelectedIngredient {
  final ProductModel product;
  double quantity;
  String selectedUnit;
  final UniqueKey id = UniqueKey();

  SelectedIngredient({
    required this.product,
    this.quantity = 1,
    required this.selectedUnit,
  });

  Map<String, dynamic> toMap() {
    return {
      'productId': product.id,
      'quantity': quantity,
      'selectedUnit': selectedUnit,
    };
  }
}