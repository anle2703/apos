// File: lib/screens/sales/retail_order_screen.dart

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';

// Import Models
import '../../models/order_item_model.dart';
import '../../models/order_model.dart';
import '../../models/product_group_model.dart';
import '../../models/product_model.dart';
import '../../models/user_model.dart';
import '../../models/customer_model.dart';
import '../../models/discount_model.dart';
import '../../models/store_settings_model.dart';

// Import Services
import '../../services/firestore_service.dart';
import '../../services/toast_service.dart';
import '../../services/settings_service.dart';
import '../../services/discount_service.dart';

// Import Widgets & Screens
import '../../theme/app_theme.dart';
import '../../widgets/customer_selector.dart';
import '../../widgets/edit_order_item_dialog.dart';
import '../../products/barcode_scanner_screen.dart';
import '/screens/sales/payment_screen.dart';
import '../../theme/string_extensions.dart';
import '../../theme/number_utils.dart';
import '../../models/quick_note_model.dart';

// --- CLASS QUẢN LÝ SESSION ---
class RetailTab {
  String id;
  String name;
  CustomerModel? customer;
  Map<String, OrderItem> items;
  DateTime createdAt;
  String? cloudOrderId; // [MỚI] ID của đơn hàng trên Firestore (nếu được load về)

  RetailTab({
    required this.id,
    required this.name,
    this.customer,
    Map<String, OrderItem>? items,
    DateTime? createdAt,
    this.cloudOrderId,
  })  : items = items ?? {},
        createdAt = createdAt ?? DateTime.now();

  double get totalAmount => items.values.fold(0, (tong, item) => tong + item.subtotal);
}

class RetailSessionManager {
  static final RetailSessionManager _instance = RetailSessionManager._internal();
  factory RetailSessionManager() => _instance;
  RetailSessionManager._internal();

  List<RetailTab> tabs = [];
  String activeTabId = '';

  void clearSession() {
    tabs = [];
    activeTabId = '';
  }
}

class RetailOrderScreen extends StatefulWidget {
  final UserModel currentUser;

  const RetailOrderScreen({
    super.key,
    required this.currentUser,
  });

  @override
  State<RetailOrderScreen> createState() => _RetailOrderScreenState();
}

class _RetailOrderScreenState extends State<RetailOrderScreen> {
  final _firestoreService = FirestoreService();
  late final SettingsService _settingsService;
  final _discountService = DiscountService();
  final _session = RetailSessionManager();

  StreamSubscription<StoreSettings>? _settingsSub;
  StreamSubscription<List<DiscountModel>>? _discountsSub;
  final StreamController<void> _cartUpdateController = StreamController.broadcast();
  RetailTab? get _currentTab => _session.tabs.firstWhereOrNull((t) => t.id == _session.activeTabId);

  final FocusNode _searchFocusNode = FocusNode();
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isPaymentView = false;

  List<ProductGroupModel> _menuGroups = [];
  List<ProductModel> _menuProducts = [];
  List<DiscountModel> _activeDiscounts = [];

  bool get isDesktop => MediaQuery.of(context).size.width >= 1100;

  bool _printBillAfterPayment = true;
  bool _showPricesOnReceipt = true;
  bool _promptForCash = true;
  List<Map<String, dynamic>> _activeBuyXGetYPromos = [];
  StreamSubscription? _buyXGetYSub;

  @override
  void initState() {
    super.initState();
    _settingsService = SettingsService();

    final settingsId = widget.currentUser.ownerUid ?? widget.currentUser.uid;
    _settingsSub = _settingsService.watchStoreSettings(settingsId).listen((s) {
      if (!mounted) return;
      setState(() {
        _printBillAfterPayment = s.printBillAfterPayment;
        _showPricesOnReceipt = s.showPricesOnReceipt;
        _promptForCash = s.promptForCash ?? true;
      });
    });

    if (_session.tabs.isEmpty) {
      _addNewTab(forceName: "Đơn hàng 1");
    } else if (_session.activeTabId.isEmpty) {
      _session.activeTabId = _session.tabs.first.id;
    }

    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _searchController.addListener(() {
      if (!mounted) return;
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });

    _discountsSub = _discountService
        .getActiveDiscountsStream(widget.currentUser.storeId)
        .listen((discounts) {
      if (mounted) setState(() => _activeDiscounts = discounts);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        bool shouldAutoFocus = true;
        try {
          if (Platform.isAndroid || Platform.isIOS) shouldAutoFocus = false;
        } catch (_) {}

        if (shouldAutoFocus && !_searchFocusNode.hasFocus) {
          _searchFocusNode.requestFocus();
        }
      }
    });

    final ownerUid = widget.currentUser.ownerUid ?? widget.currentUser.uid;
    PaymentScreen.preloadData(widget.currentUser.storeId, ownerUid);

    _buyXGetYSub = _firestoreService
        .getActiveBuyXGetYPromotionsStream(widget.currentUser.storeId)
        .listen((promos) {
      if (mounted) {
        setState(() {
          _activeBuyXGetYPromos = promos;
        });
        // Tính toán lại ngay khi load xong
        _applyBuyXGetYLogic();
      }
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _cartUpdateController.close();
    _settingsSub?.cancel();
    _discountsSub?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _buyXGetYSub?.cancel();
    super.dispose();
  }

  void _applyBuyXGetYLogic() {
    if (_currentTab == null) return;
    if (_activeBuyXGetYPromos.isEmpty) return;

    final tab = _currentTab!;
    final Map<String, OrderItem> updates = {};
    bool hasChanges = false;

    // Snapshot giỏ hàng hiện tại
    final Map<String, OrderItem> cartSnapshot = Map.from(tab.items);

    for (final promo in _activeBuyXGetYPromos) {
      final String buyId = promo['buyProductId'];
      final double buyQtyReq = (promo['buyQuantity'] as num).toDouble();
      final String? buyUnitReq = promo['buyUnit']; // ĐVT yêu cầu

      final String giftId = promo['giftProductId'];
      final double giftQtyReward = (promo['giftQuantity'] as num).toDouble();
      final double giftPrice = (promo['giftPrice'] as num).toDouble();
      final String promoName = promo['name'];
      final String giftNote = "Tặng kèm ($promoName)";

      // 1. Tính tổng số lượng hàng MUA
      double currentBuyQty = 0;
      for (final item in cartSnapshot.values) {
        if (item.product.id == buyId) {
          if (item.note != giftNote) {
            // Kiểm tra ĐVT
            if (buyUnitReq != null && buyUnitReq.isNotEmpty) {
              if (item.selectedUnit == buyUnitReq) {
                currentBuyQty += item.quantity;
              }
            } else {
              currentBuyQty += item.quantity;
            }
          }
        }
      }

      // 2. Tính số lượng hàng TẶNG
      int sets = 0;
      if (buyQtyReq > 0) {
        sets = (currentBuyQty / buyQtyReq).floor();
      }
      double totalGiftNeeded = sets * giftQtyReward;

      // 3. Tìm hàng tặng trong giỏ
      String? existingGiftLineId;
      OrderItem? existingGiftItem;

      for (final entry in cartSnapshot.entries) {
        if (entry.value.product.id == giftId && entry.value.note == giftNote) {
          existingGiftLineId = entry.key;
          existingGiftItem = entry.value;
          break;
        }
      }

      // 4. Đồng bộ
      if (totalGiftNeeded > 0) {
        if (existingGiftItem != null) {
          if (existingGiftItem.quantity != totalGiftNeeded || existingGiftItem.price != giftPrice) {
            updates[existingGiftLineId!] = existingGiftItem.copyWith(
              quantity: totalGiftNeeded,
              price: giftPrice,
              discountValue: 0,
              discountUnit: 'VNĐ',
            );
            hasChanges = true;
          }
        } else {
          // Tạo mới
          final productModel = _menuProducts.firstWhereOrNull((p) => p.id == giftId);
          if (productModel != null) {
            final newItem = OrderItem(
              product: productModel,
              price: giftPrice,
              quantity: totalGiftNeeded,
              selectedUnit: promo['giftUnit'] ?? productModel.unit ?? '',
              addedBy: "System",
              addedAt: Timestamp.now(),
              discountValue: 0,
              discountUnit: 'VNĐ',
              note: giftNote,
              commissionStaff: {},
            );
            updates[newItem.lineId] = newItem;
            hasChanges = true;
          }
        }
      } else {
        // Xóa hàng tặng (Xóa Y khi X bị xóa)
        if (existingGiftLineId != null) {
          // Trong Retail Mode, xóa trực tiếp khỏi Map
          tab.items.remove(existingGiftLineId);
          hasChanges = true;
        }
      }
    }

    if (hasChanges) {
      setState(() {
        tab.items.addAll(updates);
      });
      _cartUpdateController.add(null);
    }
  }

  Future<void> _confirmClearCart() async {
    if (_currentTab == null || _currentTab!.items.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Xác nhận"),
        content: const Text("Bạn có chắc muốn xóa toàn bộ giỏ hàng không?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Hủy")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Xóa", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _currentTab!.items.clear();
      });
      // Báo cho popup cập nhật
      _cartUpdateController.add(null);
      ToastService().show(message: "Đã xóa giỏ hàng", type: ToastType.success);
    }
  }

  void _addNewTab({String? forceName}) {
    final String newId = 'tab_${DateTime.now().microsecondsSinceEpoch}';
    final int nextNum = _session.tabs.length + 1;
    final String name = forceName ?? 'Đơn hàng $nextNum';

    final newTab = RetailTab(id: newId, name: name);

    setState(() {
      _session.tabs.add(newTab);
      _session.activeTabId = newId;
      _isPaymentView = false;
    });
  }

  void _switchTab(String id) {
    if (_session.activeTabId == id) return;
    setState(() {
      _session.activeTabId = id;
      _isPaymentView = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isPaymentView && isDesktop) _searchFocusNode.requestFocus();
    });
  }

  void _closeTab(String id) {
    setState(() {
      _session.tabs.removeWhere((t) => t.id == id);
      if (_session.tabs.isEmpty) {
        _addNewTab(forceName: "Đơn hàng 1");
      } else {
        if (_session.activeTabId == id) {
          _session.activeTabId = _session.tabs.last.id;
        }
      }
      _isPaymentView = false;
    });
  }

  void _updateTabCustomer(CustomerModel? customer) {
    if (_currentTab == null) return;
    setState(() {
      _currentTab!.customer = customer;
      if (customer != null && customer.name.isNotEmpty) {
        _currentTab!.name = customer.name;
      } else {
        int index = _session.tabs.indexOf(_currentTab!);
        _currentTab!.name = "Đơn hàng ${index + 1}";
      }
    });
  }

  Future<void> _saveOrderToCloud() async {
    if (_currentTab == null) return;
    final tab = _currentTab!;

    if (tab.items.isEmpty) {
      ToastService().show(message: "Giỏ hàng trống, không thể lưu.", type: ToastType.warning);
      return;
    }

    // Nếu đã có cloudOrderId (đơn restore), dùng lại ID đó để cập nhật.
    // Nếu chưa có, tạo ID mới.
    final orderId = tab.cloudOrderId ?? 'retail_saved_${DateTime.now().millisecondsSinceEpoch}';

    final itemsList = tab.items.values.map((e) => e.toMap()).toList();
    final total = tab.totalAmount;

    final savedOrder = OrderModel(
      id: orderId,
      tableId: orderId,
      tableName: tab.name,
      status: 'saved',     // Trạng thái 'saved'
      startTime: Timestamp.fromDate(tab.createdAt),
      items: itemsList,
      totalAmount: total,
      storeId: widget.currentUser.storeId,
      createdAt: Timestamp.now(),
      createdByUid: widget.currentUser.uid,
      createdByName: widget.currentUser.name ?? 'Staff',
      version: 1,
      numberOfCustomers: 1,
      customerId: tab.customer?.id,
      customerName: tab.customer?.name,
      customerPhone: tab.customer?.phone,
    );

    try {
      // 2. Đẩy lên Firestore (Ghi đè hoặc tạo mới)
      await _firestoreService.getOrderReference(orderId).set(savedOrder.toMap());

      // 3. Đóng tab hiện tại
      _closeTab(tab.id);

      ToastService().show(message: "Đã đồng bộ đơn hàng lên hệ thống.", type: ToastType.success);
    } catch (e) {
      ToastService().show(message: "Lỗi khi lưu: $e", type: ToastType.error);
    }
  }

  Future<void> _deleteSavedOrder(String orderId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Xác nhận xóa"),
        content: const Text("Bạn có chắc muốn xóa vĩnh viễn đơn hàng đã lưu này không?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Hủy"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Xóa", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance.collection('orders').doc(orderId).delete();
        ToastService().show(message: "Đã xóa đơn hàng.", type: ToastType.success);
      } catch (e) {
        ToastService().show(message: "Lỗi khi xóa: $e", type: ToastType.error);
      }
    }
  }

  void _showSavedOrdersList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (_, controller) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                AppBar(
                  title: const Text("Đơn hàng đã lưu"),
                  centerTitle: true,
                  automaticallyImplyLeading: false,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                  actions: [IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))],
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('orders')
                        .where('storeId', isEqualTo: widget.currentUser.storeId)
                        .where('status', isEqualTo: 'saved')
                        .orderBy('createdAt', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.cloud_off, size: 60, color: Colors.grey),
                              SizedBox(height: 16),
                              Text("Không có đơn hàng nào được lưu.", style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        );
                      }

                      final docs = snapshot.data!.docs;
                      return ListView.separated(
                        controller: controller,
                        padding: const EdgeInsets.all(16),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final data = docs[index].data() as Map<String, dynamic>;
                          final order = OrderModel.fromMap(data);

                          return Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: CircleAvatar(
                                backgroundColor: AppTheme.primaryColor.withAlpha(30),
                                child: const Icon(Icons.receipt_long, color: AppTheme.primaryColor),
                              ),
                              title: Text(order.tableName, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                "${DateFormat('HH:mm dd/MM').format(order.createdAt?.toDate() ?? DateTime.now())} - ${order.createdByName}",
                                style: TextStyle(color: Colors.grey[600], fontSize: 14),
                              ),
                              // --- SỬA PHẦN TRAILING ĐỂ CÓ NÚT XÓA ---
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Hiển thị giá tiền
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                          formatNumber(order.totalAmount),
                                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor, fontSize: 15)
                                      ),
                                      Text(
                                        "${order.items.length} sản phẩm",
                                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 8),
                                  // Nút xóa
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    tooltip: "Xóa đơn này",
                                    onPressed: () {
                                      // [QUAN TRỌNG] Gọi hàm xóa đã viết ở Bước 1
                                      _deleteSavedOrder(docs[index].id);
                                    },
                                  ),
                                ],
                              ),
                              onTap: () {
                                Navigator.pop(ctx);
                                _restoreOrderFromCloud(order, docs[index].reference);
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _restoreOrderFromCloud(OrderModel order, DocumentReference ref) {
    // Tạo Tab mới từ dữ liệu Order
    final String newTabId = 'tab_restored_${DateTime.now().microsecondsSinceEpoch}';
    final Map<String, OrderItem> items = {};

    for (var itemMap in order.items) {
      final item = OrderItem.fromMap(itemMap as Map<String, dynamic>, allProducts: _menuProducts);
      items[item.lineId] = item;
    }

    final newTab = RetailTab(
      id: newTabId,
      name: order.tableName,
      customer: (order.customerId != null)
          ? CustomerModel(id: order.customerId!, storeId: order.storeId, name: order.customerName ?? '', phone: order.customerPhone ?? '', points: 0, debt: 0, searchKeys: [])
          : null,
      items: items,
      createdAt: order.createdAt?.toDate(),
      cloudOrderId: ref.id, // [QUAN TRỌNG] Lưu lại ID để biết đây là đơn từ Cloud
    );

    setState(() {
      _session.tabs.add(newTab);
      _session.activeTabId = newTabId;
    });

    // [QUAN TRỌNG] Không xóa đơn trên Cloud khi xem, chỉ xóa khi thanh toán
    ToastService().show(message: "Đã mở lại đơn hàng.", type: ToastType.success);
  }

  void _showActiveTabsList() {
    showModalBottomSheet(
        context: context,
        builder: (ctx) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text("Đơn hàng đang mở", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _session.tabs.length,
                    separatorBuilder: (ctx, index) => const Divider(height: 1, color: Colors.grey, thickness:  0.5,),
                    itemBuilder: (context, index) {
                      final tab = _session.tabs[index];
                      final isSelected = tab.id == _session.activeTabId;

                      return ListTile(
                        selected: isSelected,
                        selectedColor: AppTheme.primaryColor,
                        leading: Icon(Icons.shopping_bag_outlined, color: isSelected ? AppTheme.primaryColor : Colors.grey),
                        title: Text(tab.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(formatNumber(tab.totalAmount), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () {
                                _closeTab(tab.id);
                                // Refresh UI của bottom sheet
                                Navigator.pop(ctx);
                                _showActiveTabsList();
                              },
                            )
                          ],
                        ),
                        onTap: () {
                          _switchTab(tab.id);
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _addNewTab();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text("Tạo đơn mới"),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                )
              ],
            ),
          );
        }
    );
  }

  Future<void> _addItemToCart(ProductModel product) async {
    if (_currentTab == null) return;
    final tab = _currentTab!;

    // --- LOGIC CŨ: BỎ ĐOẠN CHECK needsOptionDialog VÀ GỌI DIALOG ---

    // Tìm khuyến mãi giảm giá tốt nhất
    final discountItem = _discountService.findBestDiscountForProduct(
      product: product,
      activeDiscounts: _activeDiscounts,
      customer: tab.customer,
      checkTime: DateTime.now(),
    );

    double discountVal = 0;
    String discountUnit = '%';
    if (discountItem != null) {
      discountVal = discountItem.value;
      discountUnit = discountItem.isPercent ? '%' : 'VNĐ';
    }

    // Tạo item mới với ĐVT mặc định
    final newItem = OrderItem(
      product: product,
      price: product.sellPrice,
      selectedUnit: product.unit ?? '', // Lấy ĐVT mặc định
      quantity: 1,
      addedAt: Timestamp.now(),
      addedBy: widget.currentUser.name ?? 'Staff',
      discountValue: discountVal,
      discountUnit: discountUnit,
      commissionStaff: {},
    );

    setState(() {
      final existingKey = tab.items.keys.firstWhereOrNull(
              (k) => tab.items[k]!.groupKey == newItem.groupKey);

      if (existingKey != null) {
        final existingItem = tab.items[existingKey]!;
        tab.items[existingKey] = existingItem.copyWith(
          quantity: existingItem.quantity + 1,
        );
      } else {
        tab.items[newItem.lineId] = newItem;
      }
    });

    // Vẫn gọi hàm này để check xem món vừa thêm có kích hoạt quà tặng không
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyBuyXGetYLogic();
    });
  }

  void _updateQuantity(String key, double change) {
    if (_currentTab == null) return;
    final tab = _currentTab!;
    if (!tab.items.containsKey(key)) return;

    final item = tab.items[key]!;

    // Chặn sửa số lượng hàng tặng (nếu muốn)
    if (item.note != null && item.note!.contains("Tặng kèm")) {
      ToastService().show(message: "Hàng tặng tự động cập nhật theo món chính.", type: ToastType.warning);
      return;
    }

    final newQty = item.quantity + change;

    setState(() {
      if (newQty <= 0) {
        tab.items.remove(key);
      } else {
        tab.items[key] = item.copyWith(quantity: newQty);
      }
    });

    _cartUpdateController.add(null);

    // [QUAN TRỌNG] Chạy lại logic sau khi đổi số lượng (để xóa/thêm quà)
    _applyBuyXGetYLogic();
  }

  void _removeItem(String key) {
    if (_currentTab == null) return;
    final item = _currentTab!.items[key];

    if (item != null && item.note != null && item.note!.contains("Tặng kèm")) {
      ToastService().show(message: "Vui lòng xóa món chính, quà tặng sẽ tự mất.", type: ToastType.warning);
      return;
    }

    setState(() {
      _currentTab!.items.remove(key);
    });

    _cartUpdateController.add(null);
    // [QUAN TRỌNG] Chạy lại logic sau khi xóa
    _applyBuyXGetYLogic();
  }

  OrderModel _createOrderFromTab(RetailTab tab) {
    // [TỐI ƯU] Sử dụng ??= thay cho if (null)
    // Nếu chưa có ID -> Tạo ID mới và gán luôn vào tab.cloudOrderId
    // Nếu đã có ID -> Giữ nguyên (không làm gì cả)
    tab.cloudOrderId ??= FirebaseFirestore.instance.collection('orders').doc().id;

    final orderId = tab.cloudOrderId!; // Chắc chắn đã có ID

    final itemsList = tab.items.values.map((e) => e.toMap()).toList();
    final total = tab.totalAmount;

    return OrderModel(
      id: orderId,
      tableId: orderId,
      tableName: tab.name,
      status: 'active',
      startTime: Timestamp.fromDate(tab.createdAt),
      items: itemsList,
      totalAmount: total,
      storeId: widget.currentUser.storeId,
      createdAt: Timestamp.now(),
      createdByUid: widget.currentUser.uid,
      createdByName: widget.currentUser.name ?? widget.currentUser.phoneNumber,
      version: 1,
      numberOfCustomers: 1,
      customerId: tab.customer?.id,
      customerName: tab.customer?.name,
      customerPhone: tab.customer?.phone,
    );
  }

  void _handlePayment() {
    if (_currentTab == null) return;
    final tab = _currentTab!;

    // 1. Kiểm tra giỏ hàng
    if (tab.items.isEmpty) {
      ToastService().show(message: "Giỏ hàng trống, vui lòng chọn món.", type: ToastType.warning);
      return;
    }

    // 2. CHUẨN BỊ DỮ LIỆU TẠI CHỖ (INSTANT DATA)
    // Tạo OrderModel ngay lập tức từ Tab hiện tại
    // Nếu chưa có ID (đơn mới), tạo ID mới. Nếu đã có (đơn đã lưu), dùng lại ID đó.
    final String orderId = tab.cloudOrderId ?? 'retail_${DateTime.now().millisecondsSinceEpoch}';

    // Đảm bảo tab có ID để dùng cho việc lưu sau này
    tab.cloudOrderId ??= orderId;

    final itemsList = tab.items.values.map((e) => e.toMap()).toList();
    final total = tab.totalAmount;

    // Tạo model đơn hàng
    final newOrder = OrderModel(
      id: orderId,
      tableId: orderId, // Với Retail, TableID thường là OrderID
      tableName: tab.name,
      status: 'active',
      startTime: Timestamp.fromDate(tab.createdAt),
      items: itemsList,
      totalAmount: total,
      storeId: widget.currentUser.storeId,
      createdAt: Timestamp.now(),
      createdByUid: widget.currentUser.uid,
      createdByName: widget.currentUser.name ?? widget.currentUser.phoneNumber,
      version: 1,
      numberOfCustomers: 1,
      customerId: tab.customer?.id,
      customerName: tab.customer?.name,
      customerPhone: tab.customer?.phone,
    );

    // 3. BACKGROUND TASK (CHẠY NGẦM - KHÔNG AWAIT)
    // Lưu lên Server và để nó tự chạy, không chờ kết quả để tránh delay
    _firestoreService.getOrderReference(newOrder.id).set(newOrder.toMap())
        .then((_) => debugPrint(">>> [Background Retail] Đã lưu đơn ngầm thành công"))
        .catchError((e) => debugPrint(">>> [Background Retail] Lỗi lưu đơn ngầm: $e"));

    // 4. XỬ LÝ GIAO DIỆN & NAVIGATE NGAY LẬP TỨC
    if (isDesktop) {
      // DESKTOP: Bật view thanh toán tại chỗ
      setState(() {
        _isPaymentView = true;
      });
    } else {
      // MOBILE: Chuyển màn hình PaymentScreen ngay lập tức
      _navigateToPaymentMobile(newOrder, tab);
    }
  }

  void _navigateToPaymentMobile(OrderModel order, RetailTab tab) async {
    final result = await Navigator.of(context).push(MaterialPageRoute(
        builder: (ctx) => PaymentScreen(
          order: order,
          currentUser: widget.currentUser,
          subtotal: order.totalAmount,
          customer: tab.customer,
          printBillAfterPayment: _printBillAfterPayment,
          showPricesOnReceipt: _showPricesOnReceipt,
          promptForCash: _promptForCash,
          isRetailMode: true,
          // [SỬA: XÓA DÒNG initialPaymentMethodId]
        )));

    _checkPaymentResult(result, tab);
  }

  void _checkPaymentResult(dynamic result, RetailTab tab) {
    // result == true: Thanh toán thành công (Mobile callback)
    // result is PaymentResult: Trả về kết quả thanh toán (Desktop/PaymentScreen callback)
    if (result == true || result is PaymentResult) {

      // 1. Đóng Tab hiện tại khỏi giao diện bán hàng
      _closeTab(tab.id);

      // 2. Tắt view thanh toán (cho Desktop)
      if (mounted) {
        setState(() {
          _isPaymentView = false;
        });
      }

      // [QUAN TRỌNG - ĐÃ SỬA]
      // Tuyệt đối KHÔNG gọi delete() document ở đây.
      // PaymentScreen đã update trạng thái đơn thành 'paid'.
      // Nếu delete ở đây, bạn sẽ mất lịch sử giao dịch.

      // Chỉ xóa nếu đây là đơn nháp chưa thanh toán (logic custom của bạn),
      // nhưng với luồng chuẩn thì khi PaymentResult trả về thành công, đơn đã an toàn trên server.

      ToastService().show(message: "Thanh toán thành công!", type: ToastType.success);
    }
    // Trường hợp result là PaymentState (In tạm tính hoặc Lưu nháp mà chưa thanh toán xong)
    else if (result is PaymentState) {
      // Không làm gì cả, giữ nguyên tab để thu ngân thao tác tiếp
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ProductModel>>(
      stream: _firestoreService.getAllProductsStream(widget.currentUser.storeId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        _menuProducts = snapshot.data!
            .where((p) => p.isVisibleInMenu == true && p.productType != 'Nguyên liệu')
            .toList();

        return FutureBuilder<List<ProductGroupModel>>(
          future: _firestoreService.getProductGroups(widget.currentUser.storeId),
          builder: (context, groupSnapshot) {
            if (groupSnapshot.hasData) {
              _menuGroups = groupSnapshot.data!
                  .where((g) => _menuProducts.any((p) => p.productGroup == g.name))
                  .toList();

              if (_menuProducts.any((p) => p.productGroup == null || p.productGroup!.isEmpty)) {
                if (!_menuGroups.any((g) => g.name == 'Khác')) {
                  _menuGroups.add(ProductGroupModel(id: 'other', name: 'Khác', stt: 999));
                }
              }
            }

            return Scaffold(
              appBar: _buildAppBar(),
              backgroundColor: const Color(0xFFF5F5F5),
              body: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
            );
          },
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    // 1. Widget Icon Đám mây (Đơn đã lưu)
    final savedOrdersWidget = StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('storeId', isEqualTo: widget.currentUser.storeId)
          .where('status', isEqualTo: 'saved')
          .snapshots(),
      builder: (context, snapshot) {
        final int count = snapshot.hasData ? snapshot.data!.docs.length : 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(Icons.cloud_upload_outlined, color: AppTheme.primaryColor, size: 30),
              tooltip: "Đơn hàng đã lưu",
              onPressed: _showSavedOrdersList,
            ),
            if (count > 0)
              Positioned(
                top: -2,
                left: 2,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)]
                  ),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  child: Center(
                    child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
          ],
        );
      },
    );

    // 2. Widget Ô chọn đơn hàng (Cho Mobile)
    final mobileOrderSelectorWidget = Expanded(
      child: InkWell(
        onTap: _showActiveTabsList,
        child: Container(
          height: 45,
          padding: const EdgeInsets.only(left: 12, right: 12),
          decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12), // Bo góc 12 giống ô tìm kiếm
              border: Border.all(color: Colors.grey.shade300)
          ),
          child: Row(
            children: [
              const Icon(Icons.layers_outlined, color: AppTheme.primaryColor),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentTab?.name ?? "Đơn hàng",
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    if (_currentTab != null && _currentTab!.items.isNotEmpty)
                      Text(
                        formatNumber(_currentTab!.totalAmount),
                        style: TextStyle(color: Colors.grey[700], fontSize: 12, fontWeight: FontWeight.w600),
                      )
                  ],
                ),
              ),
              const Icon(Icons.arrow_drop_down, color: Colors.grey)
            ],
          ),
        ),
      ),
    );

    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      backgroundColor: Colors.white,
      elevation: 1,
      title: Container(
        height: kToolbarHeight,
        // Padding 8 ngang để khớp với padding 8 của ô tìm kiếm bên dưới
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            // --- LOGIC SẮP XẾP ---

            // 1. NẾU LÀ MOBILE -> Hiện Ô Đơn Hàng TRƯỚC (Bên trái)
            if (!isDesktop) ...[
              mobileOrderSelectorWidget,
              const SizedBox(width: 8), // Khoảng cách giữa ô đơn và icon cloud
            ],

            // 2. NẾU LÀ DESKTOP -> Hiện Icon Cloud TRƯỚC (Bên trái)
            if (isDesktop) ...[
              savedOrdersWidget,
              const SizedBox(width: 4),
            ],

            // 3. HIỂN THỊ TAB NGANG (Chỉ Desktop)
            if (isDesktop)
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: _session.tabs.length,
                  separatorBuilder: (ctx, index) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final tab = _session.tabs[index];
                    final isSelected = tab.id == _session.activeTabId;
                    return Center(
                      child: InkWell(
                        onTap: () => _switchTab(tab.id),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          height: 45,
                          constraints: const BoxConstraints(minWidth: 80),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                              color: isSelected ? AppTheme.primaryColor : Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: isSelected ? AppTheme.primaryColor : Colors.grey.shade300,
                                  width: 1.5
                              ),
                              boxShadow: isSelected
                                  ? [BoxShadow(color: AppTheme.primaryColor.withAlpha(30), blurRadius: 4, offset: const Offset(0,2))]
                                  : null
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tab.name,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.black87,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (tab.items.isNotEmpty)
                                    Text(
                                      formatNumber(tab.totalAmount),
                                      style: TextStyle(
                                          color: isSelected ? Colors.white.withAlpha(230) : Colors.grey[700],
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600
                                      ),
                                    )
                                ],
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: () => _closeTab(tab.id),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(2.0),
                                  child: Icon(Icons.close, size: 18, color: isSelected ? Colors.white70 : Colors.grey),
                                ),
                              )
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

            // 4. NẾU LÀ MOBILE -> Hiện Icon Cloud SAU CÙNG (Bên phải)
            if (!isDesktop)
              savedOrdersWidget,

            // 5. CÁC NÚT CHỨC NĂNG (Chỉ Desktop)
            if (isDesktop) ...[
              const SizedBox(width: 8),
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: () => _addNewTab(),
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text("Tạo đơn", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                  ),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(width: 300, child: _buildSearchBar()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    final cardDecoration = BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: kElevationToShadow[1],
    );

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 4,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: cardDecoration,
              child: _buildCartView(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: cardDecoration,
              child: _isPaymentView
                  ? _buildPaymentView()
                  : _buildMenuView(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: _buildSearchBar(),
        ),
        Expanded(child: _buildMenuView()),
        _buildMobileCartSummary(),
      ],
    );
  }

  // --- PAYMENT VIEW (Embedded) ---
  Widget _buildPaymentView() {
    if (_currentTab == null) return const SizedBox.shrink();
    final order = _createOrderFromTab(_currentTab!);

    // [SỬA: XÓA DÒNG LẤY ID CACHE]

    return PaymentView(
      order: order,
      currentUser: widget.currentUser,
      subtotal: order.totalAmount,
      customer: _currentTab!.customer,
      printBillAfterPayment: _printBillAfterPayment,
      showPricesOnReceipt: _showPricesOnReceipt,
      promptForCash: _promptForCash,
      initialState: null,
      isRetailMode: true,
      // [SỬA: XÓA DÒNG initialPaymentMethodId]
      onCancel: () {
        setState(() {
          _isPaymentView = false;
        });
      },
      onConfirmPayment: (result) {
        _checkPaymentResult(true, _currentTab!);
      },
      onPrintAndExit: (state) {
        _checkPaymentResult(true, _currentTab!);
      },
    );
  }

  // --- MENU WIDGETS ---

  Widget _buildMenuView() {
    final groupNames = ['Tất cả', ..._menuGroups.map((g) => g.name)];

    return DefaultTabController(
      length: groupNames.length,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            width: double.infinity,
            child: TabBar(
              isScrollable: true,
              labelColor: AppTheme.primaryColor,
              unselectedLabelColor: Colors.grey[600],
              indicatorColor: AppTheme.primaryColor,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold),
              tabs: groupNames.map((g) => Tab(text: g)).toList(),
            ),
          ),
          Expanded(
            child: Container(
              color: const Color(0xFFF9F9F9),
              child: TabBarView(
                children: groupNames.map((groupName) {
                  final products = _menuProducts.where((p) {
                    bool matchGroup = groupName == 'Tất cả' || p.productGroup == groupName;
                    if (groupName == 'Khác') matchGroup = (p.productGroup == null || p.productGroup!.isEmpty);
                    bool matchSearch = _searchQuery.isEmpty ||
                        p.productName.toLowerCase().contains(_searchQuery) ||
                        (p.productCode?.toLowerCase().contains(_searchQuery) ?? false) ||
                        p.additionalBarcodes.any((b) => b.contains(_searchQuery));
                    return matchGroup && matchSearch;
                  }).toList();

                  return GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180,
                      childAspectRatio: 0.82,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: products.length,
                    itemBuilder: (ctx, i) => _buildProductCard(products[i]),
                  );
                }).toList(),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildProductCard(ProductModel product) {
    double quantityInCart = 0;
    if (_currentTab != null) {
      final cartItems = _currentTab!.items.values.where((i) => i.product.id == product.id);
      quantityInCart = cartItems.fold(0, (tong, i) => tong + i.quantity);
    }

    const stockManagedTypes = {'Hàng hóa'};
    final bool showStock = stockManagedTypes.contains(product.productType);

    return InkWell(
      onTap: () => _addItemToCart(product),
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(color: Colors.grey.shade200, blurRadius: 4, spreadRadius: 1)
                ]
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                  child: Text(
                    product.productName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, height: 1.2),
                  ),
                ),
                Expanded(
                  child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                      ? CachedNetworkImage(
                    imageUrl: product.imageUrl!,
                    fit: BoxFit.contain,
                    placeholder: (c, u) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    errorWidget: (c, u, e) => const Icon(Icons.image_not_supported, color: Colors.grey),
                  )
                      : Container(
                    color: Colors.grey[100],
                    child: const Icon(Icons.fastfood, size: 40, color: Colors.grey),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (showStock)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            NumberFormat('#,##0.##').format(product.stock),
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          formatNumber(product.sellPrice),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              color: AppTheme.primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 14
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),

          if (quantityInCart > 0)
            Positioned(
              top: -6,
              right: -6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)]
                ),
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                child: Center(
                  child: Text(
                    formatNumber(quantityInCart),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- CART WIDGETS ---

  Widget _buildCartView({ScrollController? scrollController, bool showCustomerSelector = true}) {
    final tab = _currentTab;
    if (tab == null) return const SizedBox.shrink();

    final cartEntries = tab.items.entries.toList().reversed.toList();
    final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');

    return Column(
      children: [
        // [SỬA] Chỉ hiện ô chọn khách hàng ở đây nếu showCustomerSelector = true
        if (showCustomerSelector)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: CustomerSelector(
                    currentCustomer: tab.customer,
                    firestoreService: _firestoreService,
                    storeId: widget.currentUser.storeId,
                    onCustomerSelected: _updateTabCustomer,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: cartEntries.isEmpty
              ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.remove_shopping_cart, size: 60, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text("Chưa có sản phẩm nào", style: TextStyle(color: Colors.grey[500]))
              ],
            ),
          )
              : ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: cartEntries.length,
            itemBuilder: (ctx, i) {
              final entry = cartEntries[i];
              return _buildCartItemCard(entry.key, entry.value, currencyFormat);
            },
          ),
        ),

        // Footer Actions
        _buildCartActions(currencyFormat),
      ],
    );
  }

  double _getBasePriceForUnit(ProductModel product, String selectedUnit) {
    if ((product.unit ?? '') == selectedUnit) {
      return product.sellPrice;
    }
    final additionalUnitData = product.additionalUnits.firstWhereOrNull(
            (unitData) => (unitData['unitName'] as String?) == selectedUnit
    );
    if (additionalUnitData != null) {
      return (additionalUnitData['sellPrice'] as num?)?.toDouble() ?? product.sellPrice;
    }
    return product.sellPrice;
  }

  Widget _buildCartItemCard(String key, OrderItem item, NumberFormat fmt) {
    final textTheme = Theme.of(context).textTheme;

    double originalListingPrice = _getBasePriceForUnit(item.product, item.selectedUnit);
    double sellingPrice = item.price;

    double discountAmount = 0;
    if (item.discountValue != null && item.discountValue! > 0) {
      if (item.discountUnit == 'VNĐ') {
        discountAmount = item.discountValue!;
      } else {
        discountAmount = item.price * (item.discountValue! / 100);
      }
    }
    final double finalPrice = item.price - discountAmount;

    bool showOriginalPrice = (item.discountValue != null && item.discountValue! > 0) ||
        (sellingPrice != originalListingPrice);

    // [FIX LỖI CRASH Ở ĐÂY] Phải check item.note != null trước
    final bool isGift = item.note != null && item.note!.contains("Tặng kèm");

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: () {
          // [CHẶN SỬA MÓN QUÀ TẶNG]
          if (isGift) {
            ToastService().show(
                message: "Đây là quà tặng kèm, không thể chỉnh sửa trực tiếp.",
                type: ToastType.warning
            );
            return;
          }
          _showEditItemDialog(key, item);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: item.product.productName,
                          style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.black87
                          ),
                        ),
                        if (item.selectedUnit.isNotEmpty)
                          TextSpan(
                            text: ' (${item.selectedUnit}) ',
                            style: textTheme.bodyMedium?.copyWith(
                                color: Colors.grey.shade700,
                                fontSize: 13
                            ),
                          ),
                        if (showOriginalPrice)
                          TextSpan(
                            text: fmt.format(originalListingPrice),
                            style: textTheme.bodyMedium?.copyWith(
                              decoration: TextDecoration.lineThrough,
                              decorationColor: Colors.red,
                              color: Colors.red,
                              fontSize: 13,
                            ),
                          ),
                        if (item.discountValue != null && item.discountValue! > 0)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.red.shade100)
                              ),
                              child: Text(
                                item.discountUnit == '%'
                                    ? "-${formatNumber(item.discountValue ?? 0)}%"
                                    : "-${formatNumber(item.discountValue ?? 0)}",
                                style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                      ]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    onTap: () => _removeItem(key),
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(4.0),
                      child: Icon(Icons.close, color: Colors.grey, size: 20),
                    ),
                  )
                ],
              ),

              if (item.note != null && item.note!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    item.note!,
                    style: textTheme.bodyMedium?.copyWith(
                      color: Colors.red,
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(
                      fmt.format(finalPrice),
                      style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Colors.black87
                      ),
                    ),
                  ),

                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          splashRadius: 18,
                          icon: Icon(Icons.remove,
                              size: 18, color: Colors.red.shade400),
                          onPressed: () => _updateQuantity(key, -1),
                        ),
                        InkWell(
                          onTap: () {
                            // [CHẶN SỬA MÓN QUÀ TẶNG - KHI BẤM VÀO SỐ LƯỢNG]
                            if (isGift) {
                              ToastService().show(message: "Không thể sửa món tặng kèm.", type: ToastType.warning);
                              return;
                            }
                            _showEditItemDialog(key, item);
                          },
                          child: Container(
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12.0),
                                border: Border.all(
                                    color: Colors.grey.shade300, width: 0.5)),
                            alignment: Alignment.center,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              maxWidth: 65,
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4.0, vertical: 1.0),
                            child: Text(
                              formatNumber(item.quantity),
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          splashRadius: 18,
                          icon: const Icon(Icons.add,
                              size: 18, color: AppTheme.primaryColor),
                          onPressed: () => _updateQuantity(key, 1),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(
                    width: 100,
                    child: Text(
                      fmt.format(item.subtotal),
                      textAlign: TextAlign.right,
                      style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppTheme.primaryColor
                      ),
                    ),
                  )
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCartActions(NumberFormat fmt) {
    final tab = _currentTab;
    if (tab == null) return const SizedBox.shrink();

    if (_isPaymentView) return const SizedBox.shrink();

    final double totalQuantity = tab.items.values.fold(0.0, (tong, item) => tong + item.quantity);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, -5))]
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                  "Tổng cộng (${formatNumber(totalQuantity)}):",
                  style: const TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w600)
              ),
              Text(
                  fmt.format(tab.totalAmount),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (isDesktop) ...[
                IconButton(
                  onPressed: tab.items.isEmpty ? null : () => _closeTab(tab.id),
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: "Hủy đơn hàng này",
                ),
                const SizedBox(width: 8),
              ],

              // [NÚT LƯU ĐƠN]
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: tab.items.isNotEmpty ? _saveOrderToCloud : null,
                  icon: const Icon(Icons.cloud_upload_outlined, size: 20),
                  label: const Text("LƯU ĐƠN"),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppTheme.primaryColor),
                      foregroundColor: AppTheme.primaryColor
                  ),
                ),
              ),

              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: tab.items.isNotEmpty ? _handlePayment : null,
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 2
                  ),
                  child: const Text("THANH TOÁN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildMobileCartSummary() {
    final tab = _currentTab;
    if (tab == null) return const SizedBox.shrink();

    return StreamBuilder<void>(
        stream: _cartUpdateController.stream,
        builder: (context, snapshot) {
          final totalQty = tab.items.values.fold(0.0, (s, i) => s + i.quantity);
          final totalAmount = tab.totalAmount;

          return InkWell(
            onTap: () {
              showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: Colors.transparent,
                  builder: (ctx) => DraggableScrollableSheet(
                      initialChildSize: 1.0,
                      minChildSize: 0.5,
                      builder: (_, controller) => Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Scaffold(
                          backgroundColor: Colors.white,
                          appBar: AppBar(
                            // [SỬA QUAN TRỌNG] Đưa CustomerSelector vào vị trí Title
                            title: SizedBox(
                              height: 40, // Chiều cao vừa phải cho ô chọn
                              child: CustomerSelector(
                                currentCustomer: tab.customer,
                                firestoreService: _firestoreService,
                                storeId: widget.currentUser.storeId,
                                onCustomerSelected: (customer) {
                                  // Gọi hàm update gốc
                                  _updateTabCustomer(customer);
                                  // Cập nhật lại UI popup ngay lập tức
                                  _cartUpdateController.add(null);
                                },
                              ),
                            ),
                            titleSpacing: 0, // Bỏ khoảng cách thừa để ô chọn khách rộng hơn
                            centerTitle: false, // Canh trái
                            elevation: 0,
                            leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                            actions: [
                              if (tab.items.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  tooltip: "Xóa hết",
                                  onPressed: _confirmClearCart,
                                ),
                              const SizedBox(width: 8),
                            ],
                          ),
                          body: StreamBuilder<void>(
                              stream: _cartUpdateController.stream,
                              builder: (context, _) {
                                // [SỬA] Truyền showCustomerSelector: false để ẩn cái cũ đi
                                return _buildCartView(
                                    scrollController: controller,
                                    showCustomerSelector: false
                                );
                              }
                          ),
                        ),
                      )
                  )
              );
            },
            // --- GIAO DIỆN THANH TỔNG BÊN DƯỚI (Làm gọn lại) ---
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                  color: AppTheme.primaryColor,
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, -2))]
              ),
              child: SafeArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
                          child: const Icon(Icons.shopping_cart_outlined, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                                "${formatNumber(totalQty)} sản phẩm",
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)
                            ),
                            Text(
                                "Xem chi tiết",
                                style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 12)
                            )
                          ],
                        )
                      ],
                    ),
                    Text(
                        NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(totalAmount),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)
                    )
                  ],
                ),
              ),
            ),
          );
        }
    );
  }

  Widget _buildSearchBar() {
    Widget? suffixIcon;
    if (_searchController.text.isNotEmpty) {
      suffixIcon = IconButton(
        icon: const Icon(Icons.clear, color: Colors.grey),
        onPressed: () {
          _searchController.clear();
          if (isDesktop) _searchFocusNode.requestFocus();
        },
      );
    } else if (!isDesktop) {
      suffixIcon = IconButton(
        icon: const Icon(Icons.qr_code_scanner, color: AppTheme.primaryColor,),
        onPressed: _scanBarcode,
      );
    }

    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      decoration: InputDecoration(
          hintText: "Tìm tên, mã vạch...",
          prefixIcon: const Icon(Icons.search),
          suffixIcon: suffixIcon,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          filled: true,
          fillColor: Colors.white,
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300)
          )
      ),
      onSubmitted: _handleBarcodeScan,
    );
  }

  // --- HELPERS ---

  void _handleBarcodeScan(String val) {
    if (val.trim().isEmpty) return;
    final query = val.trim().toLowerCase();

    final product = _menuProducts.firstWhereOrNull((p) =>
    p.productCode?.toLowerCase() == query ||
        p.additionalBarcodes.any((b) => b.toLowerCase() == query) ||
        p.productName.toLowerCase().contains(query)
    );

    if (product != null) {
      _addItemToCart(product);
      _searchController.clear();
      if(isDesktop) _searchFocusNode.requestFocus();
    } else {
      ToastService().show(message: "Không tìm thấy SP: $val", type: ToastType.warning);
      if(isDesktop) _searchFocusNode.requestFocus();
    }
  }

  Future<void> _scanBarcode() async {
    final res = await Navigator.push(context,
        MaterialPageRoute(builder: (ctx) => const BarcodeScannerScreen()));
    if (res != null) _handleBarcodeScan(res);
  }

  Future<void> _showEditItemDialog(String key, OrderItem item) async {
    if (_currentTab == null) return;

    _searchFocusNode.unfocus();

    final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => EditOrderItemDialog(
          initialItem: item,
          staffList: const [],
          isLoadingStaff: false,
          relevantQuickNotes: const [],
        ));

    if (mounted && isDesktop) {
      _searchFocusNode.requestFocus();
    }

    if (result != null) {
      setState(() {
        _currentTab!.items[key] = item.copyWith(
            quantity: result['quantity'],
            price: result['price'],
            discountValue: result['discountValue'],
            discountUnit: result['discountUnit'],
            selectedUnit: result['selectedUnit'],
            note: () => (result['note'] as String?).nullIfEmpty);
      });
      _applyBuyXGetYLogic();
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    if (_isPaymentView) return false;

    if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }

    if (_searchFocusNode.hasFocus) return false;

    if (event.character != null && event.character!.isNotEmpty) {
      _searchFocusNode.requestFocus();
    }
    return false;
  }
}

class _RetailProductOptionsDialog extends StatefulWidget {
  final ProductModel product;
  final List<ProductModel> allProducts;
  final List<QuickNoteModel> relevantQuickNotes;

  const _RetailProductOptionsDialog({
    required this.product,
    required this.allProducts,
    required this.relevantQuickNotes,
  });

  @override
  State<_RetailProductOptionsDialog> createState() => _RetailProductOptionsDialogState();
}

class _RetailProductOptionsDialogState extends State<_RetailProductOptionsDialog> {
  late String _selectedUnit;
  late Map<String, dynamic> _baseUnitData;
  late List<Map<String, dynamic>> _allUnitOptions;
  List<ProductModel> _accompanyingProducts = [];
  final Map<String, double> _selectedToppings = {};
  final List<QuickNoteModel> _selectedQuickNotes = [];

  @override
  void initState() {
    super.initState();
    _baseUnitData = {
      'unitName': widget.product.unit ?? '',
      'sellPrice': widget.product.sellPrice
    };
    _allUnitOptions = [_baseUnitData, ...widget.product.additionalUnits];
    _selectedUnit = _baseUnitData['unitName'] as String;

    final productMap = {for (var p in widget.allProducts) p.id: p};
    _accompanyingProducts = widget.product.accompanyingItems
        .map((item) => productMap[item['productId']])
        .where((p) => p != null)
        .cast<ProductModel>()
        .toList();
  }

  void _onConfirm() {
    final selectedUnitData =
    _allUnitOptions.firstWhere((u) => u['unitName'] == _selectedUnit);
    final priceForSelectedUnit =
    (selectedUnitData['sellPrice'] as num).toDouble();

    final Map<ProductModel, double> toppingsMap = {};
    _selectedToppings.forEach((productId, quantity) {
      if (quantity > 0) {
        final product =
        _accompanyingProducts.firstWhere((p) => p.id == productId);
        toppingsMap[product] = quantity;
      }
    });

    final String noteText = _selectedQuickNotes.map((n) => n.noteText).join(', ');

    Navigator.of(context).pop({
      'selectedUnit': _selectedUnit,
      'price': priceForSelectedUnit,
      'selectedToppings': toppingsMap,
      'selectedNote': noteText,
    });
  }

  void _updateToppingQuantity(String productId, double change) {
    setState(() {
      double currentQuantity = _selectedToppings[productId] ?? 0;
      double newQuantity = currentQuantity + change;
      if (newQuantity < 0) newQuantity = 0;
      _selectedToppings[productId] = newQuantity;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasUnits = widget.product.additionalUnits.isNotEmpty;
    final hasToppings = _accompanyingProducts.isNotEmpty;
    final hasNotes = widget.relevantQuickNotes.isNotEmpty;

    return AlertDialog(
      title: Text(widget.product.productName, textAlign: TextAlign.center),
      scrollable: true,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasUnits) ...[
              const Text('Đơn vị tính:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _allUnitOptions.map((unitData) {
                  final unitName = unitData['unitName'] as String;
                  final price = (unitData['sellPrice'] as num).toDouble();
                  final isSelected = _selectedUnit == unitName;
                  return ChoiceChip(
                    label: Text("$unitName (${formatNumber(price)})"),
                    selected: isSelected,
                    onSelected: (val) {
                      setState(() => _selectedUnit = unitName);
                    },
                  );
                }).toList(),
              ),
              const Divider(height: 24),
            ],
            if (hasToppings) ...[
              const Text('Topping / Bán kèm:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Column(
                children: _accompanyingProducts.map((topping) {
                  final quantity = _selectedToppings[topping.id] ?? 0;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text("${topping.productName} (+${formatNumber(topping.sellPrice)})"),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                            onPressed: () => _updateToppingQuantity(topping.id, -1),
                          ),
                          Text(formatNumber(quantity), style: const TextStyle(fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                            onPressed: () => _updateToppingQuantity(topping.id, 1),
                          ),
                        ],
                      )
                    ],
                  );
                }).toList(),
              ),
              const Divider(height: 24),
            ],
            if (hasNotes) ...[
              const Text('Ghi chú nhanh:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.relevantQuickNotes.map((note) {
                  final isSelected = _selectedQuickNotes.contains(note);
                  return FilterChip(
                    label: Text(note.noteText),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedQuickNotes.add(note);
                        } else {
                          _selectedQuickNotes.remove(note);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ]
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
        ElevatedButton(onPressed: _onConfirm, child: const Text('Thêm vào đơn')),
      ],
    );
  }
}