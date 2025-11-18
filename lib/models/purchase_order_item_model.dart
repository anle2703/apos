import 'product_model.dart';

class PurchaseOrderItem {
  final ProductModel product;
  double quantity;
  double price;
  String unit;
  String? selectedUnitForSeparated;

  // Dành cho sản phẩm quản lý tồn kho riêng biệt
  Map<String, double> separateQuantities = {};
  Map<String, double> separatePrices = {};

  PurchaseOrderItem({
    required this.product,
    this.quantity = 0,
    this.price = 0,
    this.unit = '',
  });

  // Getter tính tổng tiền cho sản phẩm thường
  double get subtotal => quantity * price;

  // Getter tính tổng tiền cho sản phẩm quản lý riêng
  double get separateSubtotal {
    double total = 0;
    separateQuantities.forEach((key, value) {
      total += (separatePrices[key] ?? 0) * value;
    });
    return total;
  }

  Map<String, dynamic> toMap() {
    if (product.manageStockSeparately == true) {
      return {
        'productId': product.id,
        'productName': product.productName,
        'manageStockSeparately': true,
        'separateQuantities': separateQuantities,
        'separatePrices': separatePrices,
        'subtotal': separateSubtotal,
      };
    } else {
      return {
        'productId': product.id,
        'productName': product.productName,
        'manageStockSeparately': false,
        'quantity': quantity,
        'price': price,
        'unit': unit,
        'subtotal': subtotal,
      };
    }
  }
}