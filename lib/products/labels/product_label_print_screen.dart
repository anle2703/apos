import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/user_model.dart';
import '../../models/product_model.dart';
import '../../models/order_item_model.dart';
import '../../models/purchase_order_model.dart';
import '../../models/label_template_model.dart';
import '../../services/inventory_service.dart';
import '../../services/print_queue_service.dart';
import '../../services/toast_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/number_utils.dart';
import '../../widgets/product_search_delegate.dart';
import '../../models/print_job_model.dart';
import '../../screens/settings/label_setup_screen.dart';
import '../../widgets/app_dropdown.dart';

class ProductToPrint {
  final ProductModel product;
  int quantity;
  String unit;

  ProductToPrint({
    required this.product,
    this.quantity = 1,
    required this.unit,
  });
}

class ProductLabelPrintScreen extends StatefulWidget {
  final UserModel currentUser;

  const ProductLabelPrintScreen({super.key, required this.currentUser});

  @override
  State<ProductLabelPrintScreen> createState() =>
      _ProductLabelPrintScreenState();
}

class _ProductLabelPrintScreenState extends State<ProductLabelPrintScreen> {
  final List<ProductToPrint> _items = [];
  final InventoryService _inventoryService = InventoryService();

  bool _isProcessing = false;
  LabelTemplateModel? _templateSettings;

  @override
  void initState() {
    super.initState();
    _loadLabelSettings();
  }

  Future<void> _loadLabelSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('label_template_settings');
    if (jsonStr != null) {
      try {
        setState(() {
          _templateSettings = LabelTemplateModel.fromJson(jsonStr);
        });
      } catch (e) {
        debugPrint("Lỗi đọc cài đặt tem: $e");
        setState(() {
          _templateSettings = LabelTemplateModel(labelWidth: 50, labelHeight: 30);
        });
      }
    } else {
      setState(() {
        _templateSettings = LabelTemplateModel(labelWidth: 50, labelHeight: 30);
      });
    }
  }

  void _addProduct() async {
    final selectedProducts = await ProductSearchScreen.showMultiSelect(
      context: context,
      currentUser: widget.currentUser,
      previouslySelected: _items.map((e) => e.product).toList(),
      groupByCategory: true,
    );

    if (selectedProducts != null) {
      setState(() {
        for (var product in selectedProducts) {
          if (!_items.any((e) => e.product.id == product.id)) {
            _items.add(ProductToPrint(
              product: product,
              quantity: 1,
              unit: product.unit ?? '',
            ));
          }
        }
      });
    }
  }

  void _importFromPurchaseOrder() async {
    final PurchaseOrderModel? selectedPO = await showDialog(
      context: context,
      builder: (context) => _PurchaseOrderSelectionDialog(
        storeId: widget.currentUser.storeId,
      ),
    );

    if (selectedPO != null) {
      setState(() => _isProcessing = true);
      try {
        List<String> productIds =
        selectedPO.items.map((e) => e['productId'] as String).toList();

        final products = await _inventoryService.getProductsByIds(productIds);
        final productMap = {for (var p in products) p.id: p};

        setState(() {
          for (var itemMap in selectedPO.items) {
            final productId = itemMap['productId'];
            final product = productMap[productId];

            if (product != null) {
              double qtyDouble = 0;
              if (itemMap['manageStockSeparately'] == true) {
                Map<String, dynamic> sepQty = itemMap['separateQuantities'] ?? {};
                sepQty.forEach((k, v) => qtyDouble += (v as num).toDouble());
              } else {
                qtyDouble = (itemMap['quantity'] as num).toDouble();
              }

              int qty = qtyDouble.toInt();
              if (qty <= 0) qty = 1;

              final existingIndex = _items.indexWhere((e) => e.product.id == productId);
              if (existingIndex != -1) {
                _items[existingIndex].quantity = qty;
              } else {
                _items.add(ProductToPrint(
                  product: product,
                  quantity: qty,
                  unit: itemMap['unit'] ?? product.unit ?? '',
                ));
              }
            }
          }
        });
        ToastService().show(message: "Đã nhập từ phiếu ${selectedPO.code}", type: ToastType.success);
      } catch (e) {
        ToastService().show(message: "Lỗi: $e", type: ToastType.error);
      } finally {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _clearAll() {
    if (_items.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Xác nhận"),
        content: const Text("Xóa tất cả danh sách đang chọn?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Hủy")),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _items.clear();
              });
            },
            child: const Text("Xóa", style: TextStyle(color: Colors.red)),
          )
        ],
      ),
    );
  }
  void _handlePrint() async {
    if (_items.isEmpty) {
      ToastService().show(message: "Danh sách trống", type: ToastType.warning);
      return;
    }

    if (_templateSettings == null) {
      await _loadLabelSettings();
    }

    int totalLabels = _items.fold(0, (tong, e) => tong + e.quantity);
    if (totalLabels == 0) return;

    List<Map<String, dynamic>> itemsPayload = [];
    int labelCounter = 1;

    for (var itemToPrint in _items) {
      if (itemToPrint.quantity <= 0) continue;

      final dummyOrderItem = OrderItem(
          product: itemToPrint.product,
          quantity: 1,
          price: itemToPrint.product.sellPrice,
          selectedUnit: itemToPrint.unit,
          addedBy: widget.currentUser.name ?? 'Admin',
          addedAt: Timestamp.now(),
          discountValue: 0,
          commissionStaff: {}
      );

      for (int i = 0; i < itemToPrint.quantity; i++) {
        final itemMap = dummyOrderItem.toMap();

        // Metadata cho tem
        itemMap['labelIndex'] = labelCounter;
        itemMap['labelTotal'] = totalLabels;
        // Gán Header Title từ cấu hình nếu có, nếu không dùng mặc định
        itemMap['headerTitle'] = _templateSettings?.retailStoreName ?? "Cửa Hàng";

        itemsPayload.add(itemMap);
        labelCounter++;
      }
    }

    // [QUAN TRỌNG] Mã hóa Settings thành JSON String
    // Vì LabelTemplateModel.fromJson(String source) yêu cầu String
    String? settingsJsonStr;
    if (_templateSettings != null) {
      settingsJsonStr = json.encode(_templateSettings!.toMap());
    }

    final printData = {
      'storeId': widget.currentUser.storeId,
      'tableName': 'IN_TEM_SP',
      'items': itemsPayload,
      'isRetailMode': true,

      // Gửi kích thước (để máy in set khổ giấy)
      'width': _templateSettings?.labelWidth ?? 50.0,
      'height': _templateSettings?.labelHeight ?? 30.0,

      // Gửi toàn bộ setting dưới dạng chuỗi JSON
      'templateSettingsJson': settingsJsonStr,
    };

    PrintQueueService().addJob(PrintJobType.label, printData);

    ToastService().show(message: "Đã gửi lệnh in $totalLabels tem", type: ToastType.success);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("In Tem Sản Phẩm", style: TextStyle(fontSize: 18)),
            if (_templateSettings != null)
              Text(
                "Khổ: ${_templateSettings!.labelWidth.toInt()}x${_templateSettings!.labelHeight.toInt()}mm (${_templateSettings!.labelColumns} tem/hàng)",
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
          ],
        ),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
              tooltip: "Xóa tất cả",
              onPressed: _clearAll,
            ),
          IconButton(
            icon: const Icon(Icons.settings, color: AppTheme.primaryColor),
            tooltip: "Thiết lập mẫu in",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => LabelSetupScreen(currentUser: widget.currentUser),
                ),
              ).then((_) {
                // [QUAN TRỌNG] Tải lại cài đặt ngay khi quay về
                _loadLabelSettings();
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey[50],
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _importFromPurchaseOrder,
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text("Từ Phiếu Nhập"),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _addProduct,
                    icon: const Icon(Icons.add),
                    label: const Text("Thêm Sản Phẩm"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.grey, thickness: 0.5),
          Expanded(
            child: _isProcessing
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code_2, size: 60, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text("Chưa có sản phẩm nào để in", style: TextStyle(color: Colors.grey[600])),
                  const SizedBox(height: 8),
                  // Có thể bấm vào đây để mở cài đặt nhanh luôn
                  TextButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LabelSetupScreen(currentUser: widget.currentUser),
                        ),
                      ).then((_) => _loadLabelSettings());
                    },
                    icon: const Icon(Icons.settings, size: 14),
                    label: const Text("Cấu hình mẫu tem"),
                  )
                ],
              ),
            )
                : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _items.length,
              separatorBuilder: (_,__) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                return _buildItemCard(index);
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black.withAlpha(12), blurRadius: 10, offset: const Offset(0, -5))
                ]
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("Tổng số tem:", style: TextStyle(color: Colors.grey)),
                        Text(
                            formatNumber(_items.fold(0.0, (tong, e) => tong + e.quantity)),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: AppTheme.primaryColor)
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _handlePrint,
                    icon: const Icon(Icons.print),
                    label: const Text("IN NGAY"),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                    ),
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildItemCard(int index) {
    final item = _items[index];
    final bool isDesktop = MediaQuery.of(context).size.width > 800;

    // 1. Lấy danh sách ĐVT
    final List<String> availableUnits = [];
    if (item.product.unit != null && item.product.unit!.isNotEmpty) {
      availableUnits.add(item.product.unit!);
    }
    for (var u in item.product.additionalUnits) {
      if (u['unitName'] != null) {
        availableUnits.add(u['unitName']);
      }
    }
    if (availableUnits.isEmpty) availableUnits.add('Cái');
    final uniqueUnits = availableUnits.toSet().toList();

    if (!uniqueUnits.contains(item.unit) && uniqueUnits.isNotEmpty) {
      item.unit = uniqueUnits.first;
    }

    // --- CÁC WIDGET CON ĐƯỢC CHỈNH SỬA ---

    // Widget: Chọn ĐVT (Chiều cao 40px, viền mờ của AppDropdown)
    Widget buildUnitDropdown() {
      return SizedBox(
        width: isDesktop ? 140 : null,
        height: 40, // [SỬA] Chiều cao cố định 40
        child: AppDropdown<String>(
          labelText: 'Đơn vị',
          value: item.unit,
          isDense: true,
          items: uniqueUnits.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (val) {
            if (val != null) setState(() => item.unit = val);
          },
        ),
      );
    }

    // Widget: Chỉnh Số Lượng (Chiều cao 40px, Viền xám mờ giống Dropdown)
    Widget buildQtyControl() {
      return Container(
        height: 40, // [SỬA] Chiều cao cố định 40
        width: isDesktop ? 140 : null,
        decoration: BoxDecoration(
          // [SỬA] Viền màu grey[300] để giống AppDropdown
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.remove_outlined, color: Colors.red, size: 20),
              onPressed: () {
                if (item.quantity > 1) setState(() => item.quantity--);
              },
              constraints: const BoxConstraints(minWidth: 36),
              padding: EdgeInsets.zero,
            ),
            Expanded(
              child: TextFormField(
                key: ValueKey(item.quantity),
                initialValue: item.quantity.toString(),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                // Chữ số lượng đậm, size vừa phải
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (value) {
                  final int? newVal = int.tryParse(value);
                  if (newVal != null && newVal > 0) {
                    item.quantity = newVal;
                  }
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_outlined, color: AppTheme.primaryColor, size: 20),
              onPressed: () => setState(() => item.quantity++),
              constraints: const BoxConstraints(minWidth: 36),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      );
    }

    // Widget: Mã Sản Phẩm (Kiểu cũ: Nền xanh, chữ xanh)
    Widget buildProductCode() {
      if (item.product.productCode == null || item.product.productCode!.isEmpty) {
        return const SizedBox.shrink();
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          // [SỬA] Quay lại style màu xanh dương nhạt
          color: Colors.blue.withAlpha(25),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          "Mã: ${item.product.productCode}",
          style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.w600),
        ),
      );
    }

    // Widget: Giá Bán
    Widget buildPrice() {
      return Text(
        "${formatNumber(item.product.sellPrice)} đ",
        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor, fontSize: 15),
      );
    }

    // --- MAIN BUILD ---
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: isDesktop
            ? _buildDesktopLayout(item, buildUnitDropdown, buildQtyControl, buildProductCode, buildPrice, index)
            : _buildMobileLayout(item, buildUnitDropdown, buildQtyControl, buildProductCode, buildPrice, index),
      ),
    );
  }

  // --- LAYOUT DESKTOP (Nút xóa là icon Close màu xám) ---
  Widget _buildDesktopLayout(
      ProductToPrint item,
      Widget Function() buildUnitDropdown,
      Widget Function() buildQtyControl,
      Widget Function() buildCode,
      Widget Function() buildPrice,
      int index) {

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 1. CỤM THÔNG TIN (BÊN TRÁI)
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                item.product.productName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Row(
                children: [
                  buildCode(),
                  if (item.product.productCode != null && item.product.productCode!.isNotEmpty)
                    const SizedBox(width: 12),
                  buildPrice(),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(width: 16),

        // 2. CỤM ĐIỀU KHIỂN (BÊN PHẢI)
        SizedBox(
          width: 140,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildUnitDropdown(), // Height 40
            ],
          ),
        ),

        const SizedBox(width: 16),

        SizedBox(
          width: 140,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildQtyControl(), // Height 40
            ],
          ),
        ),

        const SizedBox(width: 12),

        // Nút Xóa Desktop: Icon 'X' màu xám
        IconButton(
          onPressed: () => setState(() => _items.removeAt(index)),
          icon: const Icon(Icons.close, color: Colors.grey), // [SỬA] Icon X màu xám
          tooltip: "Xóa dòng này",
          splashRadius: 20,
        ),
      ],
    );
  }

  // --- LAYOUT MOBILE (Giữ nguyên cấu trúc cũ, chỉ thay đổi style widget con) ---
  Widget _buildMobileLayout(
      ProductToPrint item,
      Widget Function() buildUnitDropdown,
      Widget Function() buildQtyControl,
      Widget Function() buildCode,
      Widget Function() buildPrice,
      int index) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hàng 1: Tên + Xóa
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                item.product.productName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => setState(() => _items.removeAt(index)),
              child: const Padding(
                padding: EdgeInsets.all(4.0),
                child: Icon(Icons.close, color: Colors.grey, size: 20),
              ),
            )
          ],
        ),
        // Hàng 2: Mã (Trái) --- Giá (Phải)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            buildCode(),
            buildPrice(),
          ],
        ),
        const SizedBox(height: 8),

        // Hàng 3: ĐVT (Trái) --- Số Lượng (Phải)
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(flex: 5, child: buildUnitDropdown()), // Height 40
            const SizedBox(width: 12),
            Expanded(flex: 5, child: buildQtyControl()),   // Height 40
          ],
        ),
      ],
    );
  }
}

class _PurchaseOrderSelectionDialog extends StatelessWidget {
  final String storeId;

  const _PurchaseOrderSelectionDialog({required this.storeId});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 500,
        height: 600,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text("Chọn Phiếu Nhập Hàng", style: Theme.of(context).textTheme.titleLarge),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('purchase_orders')
                    .where('storeId', isEqualTo: storeId)
                    .orderBy('createdAt', descending: true)
                    .limit(20)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(child: Text("Không có phiếu nhập hàng nào gần đây"));
                  }

                  final docs = snapshot.data!.docs;

                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_,__) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final poData = PurchaseOrderModel.fromFirestore(docs[index]);

                      return ListTile(
                        title: Text(
                            "${poData.code} - ${poData.supplierName}",
                            style: const TextStyle(fontWeight: FontWeight.bold)
                        ),
                        subtitle: Text(
                            "${DateFormat('dd/MM/yyyy HH:mm').format(poData.createdAt)} - ${formatNumber(poData.totalAmount)}đ"
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          Navigator.pop(context, poData);
                        },
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Đóng"),
              ),
            )
          ],
        ),
      ),
    );
  }
}