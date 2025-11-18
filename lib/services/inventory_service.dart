import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import '../models/order_item_model.dart';
import '../models/product_model.dart';
import '../models/purchase_order_item_model.dart';
import '../models/supplier_model.dart';
import 'package:intl/intl.dart';
import '../models/user_model.dart';
import 'supplier_service.dart';
import 'package:flutter/foundation.dart';

class InventoryService {
  final _db = FirebaseFirestore.instance;
  final SupplierService _supplierService = SupplierService();

  Future<void> createPurchaseOrderAndUpdateStock({
    required Map<String, dynamic> poData,
    required List<PurchaseOrderItem> items,
  }) async {
    try {
      final now = DateTime.now();
      final datePrefix = DateFormat('ddMMyy').format(now);
      final storeId = poData['storeId'];
      if (storeId == null || storeId.isEmpty) {
        throw Exception('Store ID không được rỗng, không thể tạo mã phiếu nhập.');
      }
      final monthPrefix = DateFormat('yyyyMM').format(now);
      final counterDocId = 'po_${storeId}_$monthPrefix';
      final counterRef = _db.collection('counters').doc(counterDocId);
      final dayFieldName = 'd${now.day}';

      // --- THAY THẾ TRANSACTION BẰNG READ-THEN-WRITE ---
      int newOrderNumber;
      try {
        // 1. Đọc document tháng
        final counterSnapshot = await counterRef.get();
        int currentDailyCount = 0;

        if (counterSnapshot.exists) {
          final data = counterSnapshot.data() ?? {};
          currentDailyCount = (data[dayFieldName] as num?)?.toInt() ?? 0;
        }

        newOrderNumber = currentDailyCount + 1; // Số thứ tự mới

        // 2. Ghi lại giá trị mới (dùng set với merge: true để tạo hoặc cập nhật)
        // SetOptions(merge: true) sẽ tạo doc nếu chưa có, hoặc chỉ cập nhật field nếu đã có
        await counterRef.set({dayFieldName: newOrderNumber}, SetOptions(merge: true));

        debugPrint('>>> Lấy và cập nhật số thứ tự (không dùng transaction): $newOrderNumber cho ngày ${now.day}');
      } catch (e, stackTrace) {
        debugPrint('!!! LỖI KHI ĐỌC/GHI BỘ ĐẾM (KHÔNG DÙNG TRANSACTION) !!!');
        debugPrint('Lỗi: $e');
        debugPrint('Stack Trace: $stackTrace');
        throw Exception('Không thể lấy/cập nhật số thứ tự phiếu nhập: $e');
      }
      // --- KẾT THÚC THAY THẾ ---

      final newCode = 'NH$datePrefix${newOrderNumber.toString().padLeft(3, '0')}';
      poData['code'] = newCode;

      final batch = _db.batch();

      // (Phần lấy productsData giữ nguyên)
      Map<String, ProductModel> productsData = {};
      try {
        final productIds = items.map((item) => item.product.id).toSet().toList();
        if (productIds.isNotEmpty) {
          final productSnapshots = await getProductsByIds(productIds);
          for (var p in productSnapshots) {
            productsData[p.id] = p;
          }
        }
      } catch (e, stackTrace) {
        debugPrint('!!! LỖI KHI LẤY DỮ LIỆU SẢN PHẨM !!!');
        debugPrint('Lỗi: $e');
        debugPrint('Stack Trace: $stackTrace');
      }


      final newPoRef = _db.collection('purchase_orders').doc();
      poData['createdAt'] = FieldValue.serverTimestamp();
      batch.set(newPoRef, poData);

      // (Phần cập nhật tồn kho giữ nguyên như code gốc)
      try {
        for (final item in items) {
          final productRef = _db.collection('products').doc(item.product.id);
          final currentProduct = productsData[item.product.id];
          if (currentProduct == null) {
            debugPrint(
                "Warning: Product with ID ${item.product.id} not found. Skipping stock update.");
            continue;
          }
          if (currentProduct.manageStockSeparately) {
            // ... (code xử lý manageStockSeparately như cũ) ...
            final newAdditionalUnits =
            List<Map<String, dynamic>>.from(currentProduct.additionalUnits);
            double newBaseStock = currentProduct.stock;

            item.separateQuantities.forEach((unitName, qtyToAdd) {
              if (!qtyToAdd.isFinite || qtyToAdd <= 0){
                return;}
              if (unitName == currentProduct.unit) {
                newBaseStock += qtyToAdd;
              } else {
                final unitIndex =
                newAdditionalUnits.indexWhere((u) => u['unitName'] == unitName);
                if (unitIndex != -1) {
                  final currentUnitStock =
                      (newAdditionalUnits[unitIndex]['stock'] as num?)
                          ?.toDouble() ??
                          0.0;
                  newAdditionalUnits[unitIndex]['stock'] =
                      currentUnitStock + qtyToAdd;
                } else {
                  debugPrint(
                      "Warning: Unit '$unitName' not found in additionalUnits for product ${currentProduct.id}. Skipping separate stock update.");
                }
              }
            });

            Map<String, dynamic> updateData = {};
            if (newBaseStock.isFinite && newBaseStock != currentProduct.stock) {
              updateData['stock'] = newBaseStock;
            }
            if (!DeepCollectionEquality().equals(newAdditionalUnits, currentProduct.additionalUnits)) {
              updateData['additionalUnits'] = newAdditionalUnits;
            }
            if (updateData.isNotEmpty) {
              batch.update(productRef, updateData);
            }
          } else {
            double finalQuantityToAdd = item.quantity;
            if (item.unit != currentProduct.unit) {
              final additionalUnit = currentProduct.additionalUnits
                  .firstWhereOrNull((u) => u['unitName'] == item.unit);
              if (additionalUnit != null) {
                final conversionFactor =
                    (additionalUnit['conversionFactor'] as num?)?.toDouble() ?? 1.0;
                if (conversionFactor > 0) {
                  finalQuantityToAdd = item.quantity * conversionFactor;
                } else {
                  debugPrint(
                      "Warning: Invalid conversionFactor for unit '${item.unit}' in product ${currentProduct.id}. Using quantity as is.");
                  finalQuantityToAdd = item.quantity;
                }
              } else {
                debugPrint(
                    "Warning: Unit '${item.unit}' not found for product ${currentProduct.id}. Using quantity as is.");
                finalQuantityToAdd = item.quantity;
              }
            }

            if (finalQuantityToAdd.isFinite && finalQuantityToAdd != 0) {
              batch.update(
                  productRef, {'stock': FieldValue.increment(finalQuantityToAdd)});
            }
          }
        }
      } catch (e, stackTrace) {
        debugPrint('!!! LỖI TRONG QUÁ TRÌNH CHUẨN BỊ CẬP NHẬT TỒN KHO !!!');
        debugPrint('Lỗi: $e');
        debugPrint('Stack Trace: $stackTrace');
        throw Exception('Lỗi xử lý dữ liệu tồn kho: $e');
      }

      // (Phần batch commit giữ nguyên)
      try {
        await batch.commit();
        debugPrint('>>> Batch commit (tạo PO + cập nhật tồn kho) thành công.');
      } catch (e, stackTrace) {
        debugPrint('!!! LỖI KHI BATCH COMMIT !!!');
        debugPrint('Lỗi: $e');
        debugPrint('Stack Trace: $stackTrace');
        throw Exception('Lỗi lưu phiếu nhập và cập nhật tồn kho: $e');
      }


      // (Phần cập nhật công nợ NCC giữ nguyên)
      final double debtIncrease = (poData['debtAmount'] as num?)?.toDouble() ?? 0.0;
      final String? supplierId = poData['supplierId'] as String?;
      if (supplierId != null && supplierId.isNotEmpty && debtIncrease > 0) {
        try {
          await _supplierService.updateSupplierDebt(supplierId, debtIncrease);
          debugPrint('>>> Cập nhật công nợ NCC thành công.');
        } catch (e, stackTrace) {
          debugPrint('!!! LỖI CẬP NHẬT CÔNG NỢ NCC SAU KHI TẠO PO !!!');
          debugPrint('Lỗi: $e');
          debugPrint('Stack Trace: $stackTrace');
        }
      }

    } catch (e, stackTrace) {
      debugPrint('!!! LỖI TỔNG THỂ TRONG createPurchaseOrderAndUpdateStock !!!');
      debugPrint('Lỗi: $e');
      debugPrint('Stack Trace: $stackTrace');
      rethrow;
    }
  }

  Future<void> updatePurchaseOrderAndUpdateStock({
    required String poId,
    required Map<String, dynamic> poData,
    required List<Map<String, dynamic>> oldItems,
    required List<PurchaseOrderItem> newItems,
  }) async {
    final oldPODoc = await _db.collection('purchase_orders').doc(poId).get();
    if (!oldPODoc.exists){
      throw Exception(
          "Không tìm thấy phiếu nhập cũ để cập nhật.");}
    final double oldDebtAmount =
        (oldPODoc.data()?['debtAmount'] as num?)?.toDouble() ?? 0.0;
    final double newDebtAmount =
        (poData['debtAmount'] as num?)?.toDouble() ?? 0.0;
    final double debtDifference = newDebtAmount - oldDebtAmount;
    final String? supplierId = poData['supplierId'] as String?;

    final batch = _db.batch();

    final allProductIds = <String>{};
    for (var item in oldItems) {
      allProductIds.add(item['productId']);
    }
    for (var item in newItems) {
      allProductIds.add(item.product.id);
    }

    final productsData = await getProductsByIds(allProductIds.toList());
    final productsMap = {for (var p in productsData) p.id: p};

    final Map<String, double> stockDeltas = {};
    final Map<String, Map<String, double>> separateStockDeltas = {};

    for (final itemMap in oldItems) {
      final productId = itemMap['productId'] as String;
      final product = productsMap[productId];
      if (product == null) continue;

      if (itemMap['manageStockSeparately'] == true) {
        try {
          final quantities =
              Map<String, num>.from(itemMap['separateQuantities']);
          quantities.forEach((unitName, qty) {
            if (!qty.isFinite) return;
            separateStockDeltas.putIfAbsent(productId, () => {})[unitName] =
                (separateStockDeltas[productId]?[unitName] ?? 0) -
                    qty.toDouble();
          });
        } catch (e) {
          debugPrint("Error processing old separate item: $e");
        }
      } else {
        double quantityToRevert =
            (itemMap['quantity'] as num?)?.toDouble() ?? 0.0;
        if (itemMap['unit'] != product.unit) {
          final unitData = product.additionalUnits
              .firstWhereOrNull((u) => u['unitName'] == itemMap['unit']);
          if (unitData != null) {
            final factor =
                (unitData['conversionFactor'] as num?)?.toDouble() ?? 1.0;
            if (factor > 0) {
              quantityToRevert *= factor;
            }
          }
        }
        if (quantityToRevert.isFinite) {
          stockDeltas[productId] =
              (stockDeltas[productId] ?? 0) - quantityToRevert;
        }
      }
    }

    for (final item in newItems) {
      final product = productsMap[item.product.id];
      if (product == null) continue;

      if (item.product.manageStockSeparately) {
        item.separateQuantities.forEach((unitName, qty) {
          if (!qty.isFinite) return;
          separateStockDeltas.putIfAbsent(product.id, () => {})[unitName] =
              (separateStockDeltas[product.id]?[unitName] ?? 0) + qty;
        });
      } else {
        double quantityToAdd = item.quantity;
        if (item.unit != product.unit) {
          final unitData = product.additionalUnits
              .firstWhereOrNull((u) => u['unitName'] == item.unit);
          if (unitData != null) {
            final factor =
                (unitData['conversionFactor'] as num?)?.toDouble() ?? 1.0;
            if (factor > 0) {
              quantityToAdd *= factor;
            }
          }
        }
        if (quantityToAdd.isFinite) {
          stockDeltas[product.id] =
              (stockDeltas[product.id] ?? 0) + quantityToAdd;
        }
      }
    }

    stockDeltas.forEach((productId, delta) {
      if (delta.isFinite && delta != 0) {
        final productRef = _db.collection('products').doc(productId);
        batch.update(productRef, {'stock': FieldValue.increment(delta)});
      }
    });

    separateStockDeltas.forEach((productId, unitDeltas) {
      final product = productsMap[productId];
      if (product == null) return;
      final productRef = _db.collection('products').doc(productId);

      double updatedBaseStock = product.stock;
      final updatedAdditionalUnits =
          List<Map<String, dynamic>>.from(product.additionalUnits);
      bool baseStockChanged = false;
      bool unitsChanged = false;

      unitDeltas.forEach((unitName, delta) {
        if (!delta.isFinite || delta == 0) return;
        if (unitName == product.unit) {
          updatedBaseStock += delta;
          baseStockChanged = true;
        } else {
          final unitIndex = updatedAdditionalUnits
              .indexWhere((u) => u['unitName'] == unitName);
          if (unitIndex != -1) {
            final currentStock =
                (updatedAdditionalUnits[unitIndex]['stock'] as num?)
                        ?.toDouble() ??
                    0.0;
            updatedAdditionalUnits[unitIndex]['stock'] = currentStock + delta;
            unitsChanged = true;
          }
        }
      });

      Map<String, dynamic> updateData = {};
      if (baseStockChanged) updateData['stock'] = updatedBaseStock;
      if (unitsChanged) updateData['additionalUnits'] = updatedAdditionalUnits;

      if (updateData.isNotEmpty) {
        batch.update(productRef, updateData);
      }
    });

    final poRef = _db.collection('purchase_orders').doc(poId);
    poData['updatedAt'] =
        FieldValue.serverTimestamp(); // Đảm bảo updatedAt được set
    batch.update(poRef, poData);

    await batch.commit();

    if (supplierId != null && supplierId.isNotEmpty && debtDifference != 0) {
      try {
        await _supplierService.updateSupplierDebt(supplierId, debtDifference);
      } catch (e) {
        debugPrint("!!! Lỗi cập nhật công nợ NCC $supplierId sau khi sửa PO: $e");
      }
    }
  }

  Future<List<ProductModel>> getProductsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final List<ProductModel> products = [];
    // Chia nhỏ danh sách ID để tránh giới hạn của Firestore 'whereIn' (10 phần tử)
    for (var i = 0; i < ids.length; i += 10) {
      final sublist = ids.sublist(i, i + 10 > ids.length ? ids.length : i + 10);
      try {
        final snapshot = await _db
            .collection('products')
            .where(FieldPath.documentId, whereIn: sublist)
            .get();
        products.addAll(
            snapshot.docs.map((doc) => ProductModel.fromFirestore(doc)));
      } catch (e) {
        debugPrint("Error fetching product sublist: $e");
        // Có thể ném lỗi hoặc bỏ qua tùy logic
      }
    }
    return products;
  }

  Future<SupplierModel?> getSupplierById(String id) async {
    return await _supplierService.getSupplierById(id);
  }

  Future<void> processStockDeductionForOrder(
      List<Map<String, dynamic>> billItems, String storeId) async {
    if (billItems.isEmpty) return;

    final allProductsSnapshot = await _db
        .collection('products')
        .where('storeId', isEqualTo: storeId)
        .get();
    final allProducts = {
      for (var doc in allProductsSnapshot.docs)
        doc.id: ProductModel.fromFirestore(doc)
    };

    if (allProducts.isEmpty) return;

    final Map<String, double> finalDeductions = {};

    for (final itemMap in billItems) {
      final orderItem =
      OrderItem.fromMap(itemMap, allProducts: allProducts.values.toList());

      _calculateDeductions(
        orderItem: orderItem,
        quantitySold: orderItem.quantity,
        allProducts: allProducts,
        deductionsMap: finalDeductions,
      );
    }

    final batch = _db.batch();
    finalDeductions.forEach((key, quantityToDeduct) {
      if (quantityToDeduct <= 0) return;

      final parts = key.split('|');
      final productId = parts[0];
      final unitName = parts.length > 1 ? parts[1] : null;
      final productRef = _db.collection('products').doc(productId);

      if (unitName != null) {
        final product = allProducts[productId];
        if (product != null) {
          final updatedUnits = product.additionalUnits.map((unit) {
            if (unit['unitName'] == unitName) {
              final currentStock = (unit['stock'] as num?)?.toDouble() ?? 0.0;
              unit['stock'] = currentStock - quantityToDeduct;
            }
            return unit;
          }).toList();
          batch.update(productRef, {'additionalUnits': updatedUnits});
        }
      } else {
        batch.update(
            productRef, {'stock': FieldValue.increment(-quantityToDeduct)});
      }
    });

    try {
      await batch.commit();
    } catch (e) {
      debugPrint("Lỗi nghiêm trọng khi trừ tồn kho: $e");
    }
  }

  void _calculateDeductions({
    required OrderItem orderItem,
    required double quantitySold, // Số lượng của orderItem (ví dụ: 3 Bánh Mì)
    required Map<String, ProductModel> allProducts,
    required Map<String, double> deductionsMap,
  }) {
    final product = allProducts[orderItem.product.id];
    if (product == null) return;

    // 1. Xử lý bản thân sản phẩm (orderItem)

    final bool hasRecipe = product.compiledMaterials.isNotEmpty;

    if (product.productType == 'Thành phẩm/Combo' || product.productType == 'Topping/Bán kèm') {
      if (hasRecipe) {
        for (final material in product.compiledMaterials) {
          final materialProductId = material['productId'] as String?;
          if (materialProductId == null) continue;

          final materialProduct = allProducts[materialProductId];
          if (materialProduct == null) continue;

          final double materialQtyPerProduct = (material['quantity'] as num?)?.toDouble() ?? 0.0;
          final double totalMaterialQtyToDeduct = materialQtyPerProduct * quantitySold;

          if (totalMaterialQtyToDeduct > 0) {
            _addOrUpdateDeduction(
                materialProduct,
                materialProduct.unit ?? '',
                totalMaterialQtyToDeduct,
                deductionsMap
            );
          }
        }
      } else {
      }

    } else {
      _addOrUpdateDeduction(
          product,
          orderItem.selectedUnit,
          quantitySold,
          deductionsMap
      );
    }
    orderItem.toppings.forEach((toppingProduct, toppingQuantity) {

      final double totalToppingQtySold = toppingQuantity * quantitySold;
      if (totalToppingQtySold <= 0) return;

      final toppingOrderItem = OrderItem(
        product: toppingProduct,
        selectedUnit: toppingProduct.unit ?? '', // Topping dùng ĐV cơ bản khi đệ quy
        price: toppingProduct.sellPrice,
        addedBy: 'System',
        addedAt: Timestamp.now(),
      );
      _calculateDeductions(
        orderItem: toppingOrderItem,
        quantitySold: totalToppingQtySold,
        allProducts: allProducts,
        deductionsMap: deductionsMap,
      );
    });
  }

  Future<void> cancelPurchaseOrder({
    required String poId,
    required List<Map<String, dynamic>> itemsToReverse,
    required UserModel currentUser,
    String? supplierId,
    double debtAmountToReverse = 0,
  }) async {
    final batch = _db.batch();

    final poRef = _db.collection('purchase_orders').doc(poId);
    batch.update(poRef, {
      'status': 'Đã hủy',
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByName': currentUser.name,
      'updatedByUid': currentUser.uid,
    });

    // --- LOGIC MỚI ĐỂ TRỪ NỢ NHÀ CUNG CẤP ---
    if (supplierId != null && supplierId.isNotEmpty && debtAmountToReverse > 0) {
      final supplierRef = _db.collection('suppliers').doc(supplierId);
      batch.update(supplierRef, {
        'debt': FieldValue.increment(-debtAmountToReverse), // <-- Trừ công nợ
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    // --- KẾT THÚC LOGIC MỚI ---

    for (final itemMap in itemsToReverse) {
      final productId = itemMap['productId'] as String;
      final productRef = _db.collection('products').doc(productId);
      final manageStockSeparately =
          itemMap['manageStockSeparately'] as bool? ?? false;

      if (manageStockSeparately) {
        final separateQuantities = Map<String, double>.from(
          (itemMap['separateQuantities'] as Map).map(
                (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
          ),
        );

        // Cảnh báo: Lệnh get() ở đây làm cho hàm chạy chậm
        // và không hoàn toàn an toàn trong batch.
        final productDoc = await productRef.get();
        if (!productDoc.exists) continue;

        final productData = productDoc.data()!;
        final List<dynamic> additionalUnits =
        List.from(productData['additionalUnits'] ?? []);

        for (int i = 0; i < additionalUnits.length; i++) {
          final unit = additionalUnits[i] as Map<String, dynamic>;
          final unitName = unit['unitName'] as String;
          if (separateQuantities.containsKey(unitName)) {
            final currentStock = (unit['stock'] as num?)?.toDouble() ?? 0.0;
            unit['stock'] = currentStock - separateQuantities[unitName]!;
          }
        }

        final mainUnitName = productData['unit'] as String?;
        if (mainUnitName != null &&
            separateQuantities.containsKey(mainUnitName)) {
          batch.update(productRef, {
            'stock': FieldValue.increment(-(separateQuantities[mainUnitName]!)),
          });
        }

        if (additionalUnits.isNotEmpty) {
          batch.update(productRef, {'additionalUnits': additionalUnits});
        }
      } else {
        final quantity = (itemMap['quantity'] as num).toDouble();
        if (quantity > 0) {
          batch.update(productRef, {'stock': FieldValue.increment(-quantity)});
        }
      }
    }
    await batch.commit();
  }

  void _addOrUpdateDeduction(ProductModel product, String soldUnit,
      double quantityToDeduct, Map<String, double> deductionsMap) {
    if (product.manageStockSeparately == true) {
      final key = '${product.id}|$soldUnit';
      deductionsMap[key] = (deductionsMap[key] ?? 0) + quantityToDeduct;
    } else {
      double stockToDeduct = quantityToDeduct;
      if (soldUnit != product.unit) {
        final additionalUnit = product.additionalUnits
            .firstWhereOrNull((u) => u['unitName'] == soldUnit);
        if (additionalUnit != null) {
          final conversionFactor =
              (additionalUnit['conversionFactor'] as num?) ?? 1;
          stockToDeduct = quantityToDeduct * conversionFactor;
        }
      }
      final key = product.id;
      deductionsMap[key] = (deductionsMap[key] ?? 0) + stockToDeduct;
    }
  }

  Future<void> deletePurchaseOrderPermanently(String poId) async {
    if (poId.isEmpty) {
      throw ArgumentError('Purchase Order ID không được rỗng.');
    }
    try {
      final poRef = _db.collection('purchase_orders').doc(poId);
      await poRef.delete();
      debugPrint('Đã xóa vĩnh viễn phiếu nhập hàng ID: $poId');
    } catch (e) {
      debugPrint('Lỗi khi xóa vĩnh viễn phiếu nhập hàng $poId: $e');
      rethrow;
    }
  }
}
