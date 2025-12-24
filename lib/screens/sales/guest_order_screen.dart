// File: lib/screens/sales/guest_order_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/order_item_model.dart';
import '../../models/order_model.dart';
import '../../models/product_group_model.dart';
import '../../models/product_model.dart';
import '../../models/table_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/toast_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/number_utils.dart';
import '../../widgets/custom_text_form_field.dart';
import '../../models/store_settings_model.dart';
import 'package:omni_datetime_picker/omni_datetime_picker.dart';
import '../../models/quick_note_model.dart';
import '../../theme/string_extensions.dart';

class GuestOrderScreen extends StatefulWidget {
  final UserModel? currentUser;
  final TableModel table;
  final OrderModel? initialOrder;
  final StoreSettings settings;

  const GuestOrderScreen({
    super.key,
    this.currentUser,
    required this.table,
    this.initialOrder,
    required this.settings,
  });

  @override
  State<GuestOrderScreen> createState() => _GuestOrderScreenState();
}

class _GuestOrderScreenState extends State<GuestOrderScreen> {
  final _firestoreService = FirestoreService();

  final Map<String, OrderItem> _cart = {};
  final Map<String, OrderItem> _pendingChanges = {};
  final Map<String, OrderItem> _localChanges = {};

  Map<String, OrderItem> get _displayCart {
    final mergedCart = Map<String, OrderItem>.from(_cart);
    mergedCart.addAll(_pendingChanges); // Thêm các món đang chờ
    mergedCart.addAll(_localChanges); // Thêm (và ghi đè) các món mới
    mergedCart.removeWhere((key, item) => item.quantity <= 0);
    return mergedCart;
  }

  double get _totalAmount => _displayCart.values.fold(0, (total, item) => total + item.subtotal);

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _scheduleTimeController = TextEditingController();
  final _noteController = TextEditingController();
  bool _isSavingOrder = false;
  final _numberOfCustomersController = TextEditingController();

  final _searchController = TextEditingController();
  OrderModel? _currentOrder;
  List<ProductGroupModel> _menuGroups = [];
  List<ProductModel> _menuProducts = [];
  List<Map<String, dynamic>> _lastFirestoreItems = [];
  bool _isMenuView = true;
  String _searchQuery = '';
  Stream<QuerySnapshot>? _orderStream;
  Stream<List<ProductModel>>? _productsStream;
  StreamSubscription? _webOrderCancelStream;
  StreamSubscription? _pendingOrdersStreamSub;
  final Set<String> _processedCancellations = {};
  StreamSubscription<List<QuickNoteModel>>? _quickNotesSub;
  List<QuickNoteModel> _quickNotes = [];

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.initialOrder;
    _isMenuView = widget.initialOrder == null;

    _orderStream = FirebaseFirestore.instance
        .collection('orders')
        .where('tableId', isEqualTo: widget.table.id)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .snapshots();

    _productsStream = _firestoreService.getAllProductsStream(widget.table.storeId);

    _searchController.addListener(() {
      if (mounted) {
        setState(() => _searchQuery = _searchController.text.toLowerCase());
      }
    });

    _webOrderCancelStream = FirebaseFirestore.instance
        .collection('web_orders')
        .where('tableId', isEqualTo: widget.table.id)
        .where('status', isEqualTo: 'cancelled')
        .where('type', isEqualTo: 'at_table')
        .where('createdAt', isGreaterThan: Timestamp.fromDate(DateTime.now().subtract(const Duration(minutes: 15))))
        .snapshots()
        .listen(_handleCancelledWebOrders);

    _pendingOrdersStreamSub = FirebaseFirestore.instance
        .collection('web_orders')
        .where('tableId', isEqualTo: widget.table.id)
        .where('status', isEqualTo: 'pending')
        .where('type', isEqualTo: 'at_table')
        .snapshots()
        .listen(_rebuildPendingChanges);

    _listenQuickNotes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _scheduleTimeController.dispose();
    _noteController.dispose();
    _webOrderCancelStream?.cancel();
    _pendingOrdersStreamSub?.cancel();
    _quickNotesSub?.cancel();
    _numberOfCustomersController.dispose();
    super.dispose();
  }

  Future<void> _listenQuickNotes() async {
    _quickNotesSub = _firestoreService.getQuickNotes(widget.table.storeId).listen((notes) {
      if (mounted) {
        setState(() {
          _quickNotes = notes;
        });
      }
    }, onError: (e) {
      debugPrint('Lỗi khi lắng nghe quick notes (Guest): $e');
    });
  }

  void _handleCancelledWebOrders(QuerySnapshot snapshot) {
    if (!mounted) return;
    bool didRevert = false;

    final Map<String, OrderItem> currentPendingChanges = Map.from(_pendingChanges);

    for (final doc in snapshot.docs) {
      if (_processedCancellations.contains(doc.id)) continue;

      final data = doc.data() as Map<String, dynamic>;
      final List<dynamic> itemsData = data['items'] ?? [];

      final List<OrderItem> deltaItems = itemsData
          .map((itemMap) {
            try {
              return OrderItem.fromMap((itemMap as Map).cast<String, dynamic>(), allProducts: _menuProducts);
            } catch (e) {
              return null;
            }
          })
          .whereType<OrderItem>()
          .toList();

      if (deltaItems.isEmpty) {
        _processedCancellations.add(doc.id);
        continue;
      }

      for (final deltaItem in deltaItems) {
        final double deltaQty = deltaItem.quantity; // e.g., +1 hoặc -1

        // 1. Kiểm tra PENDING changes
        final pendingEntry =
            currentPendingChanges.entries.firstWhereOrNull((entry) => entry.value.groupKey == deltaItem.groupKey);

        if (pendingEntry != null) {
          final pendingItem = pendingEntry.value;
          final pendingKey = pendingEntry.key;

          // Hoàn tác lại (trừ đi delta)
          final double newPendingQty = pendingItem.quantity - deltaQty;

          final double originalQty = _cart[pendingKey]?.quantity ?? 0;

          if (newPendingQty <= originalQty) {
            currentPendingChanges.remove(pendingKey);
          } else {
            currentPendingChanges[pendingKey] = pendingItem.copyWith(quantity: newPendingQty);
          }
          didRevert = true;
        }
        // Nếu không có trong pending (có thể đã bị local change ghi đè),
        // Stream 'orders' (khi thu ngân xác nhận) sẽ tự dọn dẹp
      }

      _processedCancellations.add(doc.id); // Đánh dấu đã xử lý
    }

    if (didRevert && mounted) {
      setState(() {
        _pendingChanges.clear();
        _pendingChanges.addAll(currentPendingChanges);
        // Cũng kiểm tra local changes phòng trường hợp user
        // thay đổi SL khi đang chờ, rồi bị hủy
        _localChanges.removeWhere((key, localItem) {
          final pendingItem = _pendingChanges[key];
          final cartItem = _cart[key];
          // Nếu local item khớp với pending (đã revert) hoặc cart (gốc)
          // thì xóa local item
          return (pendingItem != null && localItem.quantity == pendingItem.quantity) ||
              (pendingItem == null && cartItem != null && localItem.quantity == cartItem.quantity) ||
              (pendingItem == null && cartItem == null && localItem.quantity == 0);
        });
      });
      ToastService().show(message: "Một số món đã bị thu ngân từ chối.", type: ToastType.warning);
    }
  }

  void _rebuildPendingChanges(QuerySnapshot snapshot) {
    if (!mounted) return;

    // 1. Bắt đầu với trạng thái đã xác nhận (cart)
    final Map<String, OrderItem> tempProposedCart = {};
    _cart.forEach((key, item) {
      // Dùng groupKey để gom nhóm
      tempProposedCart[item.groupKey] = item.copyWith();
    });

    // 2. Áp dụng tất cả các DELTA đang chờ (pending)
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final List<dynamic> itemsData = data['items'] ?? [];

      for (final itemMap in itemsData) {
        try {
          final deltaItem = OrderItem.fromMap((itemMap as Map).cast<String, dynamic>(), allProducts: _menuProducts);
          final double deltaQty = deltaItem.quantity;
          final String key = deltaItem.groupKey;

          final currentItem = tempProposedCart[key];
          if (currentItem != null) {
            // Áp dụng delta
            final newQty = currentItem.quantity + deltaQty;
            if (newQty > 0) {
              tempProposedCart[key] = currentItem.copyWith(quantity: newQty);
            } else {
              tempProposedCart.remove(key); // Món bị hủy
            }
          } else if (deltaQty > 0) {
            // Thêm món mới
            tempProposedCart[key] = deltaItem.copyWith(quantity: deltaQty);
          }
        } catch (e) {
          debugPrint("Lỗi parse pending item: $e");
        }
      }
    }

    // 3. Diff (so sánh) giỏ hàng đã áp dụng pending (tempProposedCart)
    //    với giỏ hàng gốc (_cart) để tạo ra _pendingChanges
    final Map<String, OrderItem> newPendingChanges = {};
    for (final proposedEntry in tempProposedCart.entries) {
      final key = proposedEntry.key;
      final proposedItem = proposedEntry.value;

      // Phải tìm lại item gốc trong _cart bằng groupKey
      final cartItem = _cart.values.firstWhereOrNull((item) => item.groupKey == key);

      if (cartItem == null) {
        // Món này mới hoàn toàn
        newPendingChanges[proposedItem.lineId] = proposedItem;
      } else if (cartItem.quantity != proposedItem.quantity) {
        // Món này bị thay đổi số lượng
        // Lưu ý: dùng lineId của món gốc (cartItem)
        newPendingChanges[cartItem.lineId] = proposedItem.copyWith(lineId: cartItem.lineId);
      }
      // Nếu SL bằng nhau -> không phải pending change
    }

    // 4. Update state
    if (mounted) {
      setState(() {
        _pendingChanges.clear();
        _pendingChanges.addAll(newPendingChanges);
      });
    }
  }

  void _updateQuantity(String lineId, double change) {
    final currentItem = _displayCart[lineId];
    if (currentItem == null) return;
    final newQuantity = currentItem.quantity + change;

    if (newQuantity < 0) return;

    setState(() {
      // Tìm trạng thái gốc (đã xác nhận)
      final originalItem = _cart[lineId];
      final double originalQty = originalItem?.quantity ?? 0;

      // Tìm trạng thái đang chờ (pending)
      final pendingItem = _pendingChanges[lineId];
      final double pendingQty = pendingItem?.quantity ?? originalQty;

      bool isRevertedToPending = (pendingItem != null && newQuantity == pendingQty);
      bool isRevertedToCart = (newQuantity == originalQty);

      if (isRevertedToPending || isRevertedToCart) {
        _localChanges.remove(lineId);
      } else {
        _localChanges[lineId] = currentItem.copyWith(quantity: newQuantity);
      }
    });
  }

  Future<bool> _saveOrderAtTable() async {
    // ... (Hàm này giữ nguyên như lần trước) ...
    if (_currentOrder != null && ['paid', 'cancelled'].contains(_currentOrder!.status)) {
      return true;
    }
    final localChanges = Map<String, OrderItem>.from(_localChanges);
    if (localChanges.isEmpty) return true;

    Map<String, OrderItem> finalCart = {};

    try {
      final DocumentReference orderRef;
      final DocumentSnapshot serverSnapshot;
      final Map<String, dynamic>? serverData;
      final int currentVersion;

      if (_currentOrder != null && _currentOrder!.status == 'active') {
        orderRef = FirebaseFirestore.instance.collection('orders').doc(_currentOrder!.id);
        serverSnapshot = await orderRef.get();
        serverData = serverSnapshot.data() as Map<String, dynamic>?;
        currentVersion = (serverData?['version'] as num?)?.toInt() ?? 0;
      } else {
        orderRef = FirebaseFirestore.instance.collection('orders').doc();
        serverSnapshot = await orderRef.get();
        serverData = null;
        currentVersion = 0;
      }

      ({List<Map<String, dynamic>> items, double total}) groupAndCalculate(Map<String, OrderItem> itemsToProcess) {
        final Map<String, OrderItem> grouped = {};
        for (final item in itemsToProcess.values) {
          if (item.quantity <= 0) continue;

          final key = item.groupKey;
          if (grouped.containsKey(key)) {
            final existing = grouped[key]!;
            grouped[key] = existing.copyWith(
              quantity: existing.quantity + item.quantity,
              sentQuantity: existing.sentQuantity + item.sentQuantity,
              addedAt: (existing.addedAt.seconds < item.addedAt.seconds) ? existing.addedAt : item.addedAt,
            );
          } else {
            grouped[key] = item;
          }
        }
        final totalAmount = grouped.values.fold(0.0, (tong, item) => tong + item.subtotal);
        final itemsToSave = grouped.values.map((e) => e.toMap()).toList();
        finalCart = {for (var item in grouped.values) item.lineId: item};
        return (items: itemsToSave, total: totalAmount);
      }

      final serverStatus = serverData?['status'];

      final mergedForSaving = Map<String, OrderItem>.from(_cart);
      mergedForSaving.addAll(_pendingChanges);
      mergedForSaving.addAll(localChanges);

      if (!serverSnapshot.exists || ['paid', 'cancelled'].contains(serverStatus)) {
        final result = groupAndCalculate(mergedForSaving);
        if (result.items.isEmpty) return true;

        final itemsToSave = result.items.map((itemMap) {
          itemMap['sentQuantity'] = itemMap['quantity'];
          return itemMap;
        }).toList();

        final newOrderData = {
          'id': orderRef.id,
          'tableId': widget.table.id,
          'tableName': widget.table.tableName,
          'status': 'active',
          'startTime': Timestamp.now(),
          'items': itemsToSave,
          'totalAmount': result.total,
          'storeId': widget.table.storeId,
          'createdAt': FieldValue.serverTimestamp(),
          'createdByUid': 'guest_order_qr',
          'createdByName': 'Khách Order QR',
          'numberOfCustomers': 1,
          'version': currentVersion + 1,
          'kitchenPrinted': false,
        };
        await orderRef.set(newOrderData);
        _currentOrder = OrderModel.fromMap(newOrderData);
      } else {
        final currentVersion = (serverData!['version'] as num?)?.toInt() ?? 0;

        final serverItemsMap = {
          for (var item
              in (serverData['items'] as List<dynamic>? ?? []).map((e) => OrderItem.fromMap(e, allProducts: _menuProducts)))
            item.lineId: item
        };

        bool hasUnprintedChanges = false;

        final Map<String, OrderItem> finalMergedItems = Map.from(mergedForSaving);

        for (final entry in localChanges.entries) {
          final key = entry.key;
          final localItem = entry.value;
          final oldSentQty = _pendingChanges[key]?.sentQuantity ?? serverItemsMap[key]?.sentQuantity ?? 0;

          if (localItem.quantity > oldSentQty) {
            hasUnprintedChanges = true;
            finalMergedItems[key] = localItem.copyWith(sentQuantity: localItem.quantity);
          } else {
            finalMergedItems[key] = localItem.copyWith(sentQuantity: localItem.quantity);
          }
        }

        final result = groupAndCalculate(finalMergedItems);

        if (result.items.isEmpty) {
          await orderRef.update({
            'status': 'cancelled',
            'items': [],
            'totalAmount': 0.0,
            'updatedAt': FieldValue.serverTimestamp(),
            'version': currentVersion + 1,
          });
          _currentOrder = null;
          finalCart.clear();
        } else {
          final Map<String, dynamic> updateData = {
            'items': result.items,
            'totalAmount': result.total,
            'updatedAt': FieldValue.serverTimestamp(),
            'version': currentVersion + 1,
          };

          if (hasUnprintedChanges) {
            updateData['kitchenPrinted'] = false;
          }

          await orderRef.update(updateData);
        }
      }

      if (mounted) {
        setState(() {
          _localChanges.clear();
          _pendingChanges.clear();
          _cart.clear();
          _cart.addAll(finalCart);
        });
      }
      return true;
    } catch (e) {
      debugPrint("==== GUEST SAVE ORDER FAILED ====\n$e");
      ToastService().show(message: "Lỗi lưu đơn hàng: $e", type: ToastType.error);
      return false;
    }
  }

  Future<void> _rebuildCartFromFirestore(List<dynamic> firestoreItems) async {
    final currentProducts = _menuProducts;
    if (currentProducts.isEmpty && firestoreItems.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) _rebuildCartFromFirestore(firestoreItems);
      });
      return;
    }
    final Map<String, OrderItem> mergedCart = {};
    for (var itemData in firestoreItems) {
      final newItem = OrderItem.fromMap(
        (itemData as Map).cast<String, dynamic>(),
        allProducts: currentProducts,
      );
      final existingEntry = mergedCart.entries.firstWhereOrNull(
        (entry) => entry.value.groupKey == newItem.groupKey,
      );
      if (existingEntry != null) {
        final existingItem = existingEntry.value;
        final existingKey = existingEntry.key;
        final updatedItem = existingItem.copyWith(
          quantity: existingItem.quantity + newItem.quantity,
          sentQuantity: existingItem.sentQuantity + newItem.sentQuantity,
          addedAt: (existingItem.addedAt.seconds < newItem.addedAt.seconds) ? existingItem.addedAt : newItem.addedAt,
        );
        mergedCart[existingKey] = updatedItem;
      } else {
        mergedCart[newItem.lineId] = newItem;
      }
    }
    if (mounted) {
      setState(() {
        _cart.clear();
        _cart.addAll(mergedCart);

        // --- SỬA LỖI 2: Xóa local và pending nếu server đã cập nhật ---
        _localChanges.removeWhere((localKey, localItem) {
          final cartItem = _cart[localKey];
          return cartItem != null && cartItem.sentQuantity >= localItem.quantity;
        });

        _pendingChanges.removeWhere((pendingKey, pendingItem) {
          final cartItem = _cart[pendingKey];
          return cartItem != null && cartItem.sentQuantity >= pendingItem.quantity;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ProductModel>>(
      stream: _productsStream,
      builder: (context, productSnapshot) {
        if (!productSnapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        _menuProducts = productSnapshot.data!
            .where((p) => p.productType != 'Nguyên liệu' && p.productType != 'Vật liệu' && p.isVisibleInMenu == true)
            .toList();

        return FutureBuilder<List<ProductGroupModel>>(
          future: _firestoreService.getProductGroups(widget.table.storeId),
          builder: (context, groupSnapshot) {
            if (groupSnapshot.hasData) {
              _menuGroups = groupSnapshot.data!.where((g) => _menuProducts.any((p) => p.productGroup == g.name)).toList();
              final bool hasOrphanProducts = _menuProducts.any((p) => p.productGroup == null || p.productGroup!.isEmpty);
              if (hasOrphanProducts && !_menuGroups.any((g) => g.name == 'Khác')) {
                _menuGroups.add(ProductGroupModel(id: 'khac_group_id', name: 'Khác', stt: 9999));
              }
            }

            return StreamBuilder<QuerySnapshot>(
              stream: _orderStream,
              builder: (context, orderSnapshot) {
                if (orderSnapshot.connectionState == ConnectionState.active && orderSnapshot.hasData) {
                  List<Map<String, dynamic>> newItemsFromFirestore = [];

                  if (orderSnapshot.data!.docs.isNotEmpty) {
                    final doc = orderSnapshot.data!.docs.first;

                    final data = doc.data() as Map<String, dynamic>;
                    _currentOrder = OrderModel.fromFirestore(doc);
                    newItemsFromFirestore = List<Map<String, dynamic>>.from((data['items'] ?? []) as List);
                  } else {
                    if (_displayCart.isEmpty) {
                      _currentOrder = null;
                    }
                  }

                  final bool hasChanges = !const DeepCollectionEquality().equals(newItemsFromFirestore, _lastFirestoreItems);
                  if (hasChanges) {
                    _lastFirestoreItems = newItemsFromFirestore;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _rebuildCartFromFirestore(newItemsFromFirestore);
                      }
                    });
                  }
                }
                return _buildMobileLayout();
              },
            );
          },
        );
      },
    );
  }

  Widget _buildMobileLayout() {
    final bool isShip = widget.table.id == 'web_ship_order';
    final bool isBooking = widget.table.id == 'web_schedule_order';

    bool isServiceDisabled = false;
    String disabledMessage = "";

    if (isShip && (widget.settings.enableShip == false)) {
      isServiceDisabled = true;
      disabledMessage = "Cửa hàng hiện đang tạm ngưng nhận đặt hàng giao đi.";
    }

    if (isBooking && (widget.settings.enableBooking == false)) {
      isServiceDisabled = true;
      disabledMessage = "Cửa hàng hiện đang tạm ngưng nhận đặt lịch hẹn.";
    }

    // Nếu bị tắt, hiển thị màn hình cảnh báo và chặn thao tác
    if (isServiceDisabled) {
      return Scaffold(
        appBar: AppBar(title: const Text("Thông báo")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.store_mall_directory_outlined, size: 80, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  "Rất tiếc!",
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  disabledMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                const Text("Vui lòng quay lại sau hoặc liên hệ trực tiếp với cửa hàng.",
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ),
      );
    }

    final groupNames = ['Tất cả', ..._menuGroups.map((g) => g.name)];
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return DefaultTabController(
      length: groupNames.length,
      child: _isMenuView
          ? Scaffold(
              resizeToAvoidBottomInset: true,
              backgroundColor: Colors.white,
              appBar: AppBar(
                title: Text('Sản phẩm - ${widget.table.tableName}'),
                automaticallyImplyLeading: false,
                actions: [
                  _buildMobileCartIcon(),
                ],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(100.0),
                  child: Column(
                    children: [
                      _buildMobileSearchBar(),
                      TabBar(
                        isScrollable: true,
                        tabs: groupNames.map((name) => Tab(text: name)).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              body: TabBarView(
                children: groupNames.map((groupName) {
                  final products = _menuProducts.where((p) {
                    bool groupMatch;
                    if (groupName == 'Tất cả') {
                      groupMatch = true;
                    } else if (groupName == 'Khác') {
                      groupMatch = (p.productGroup == null || p.productGroup!.isEmpty);
                    } else {
                      groupMatch = (p.productGroup == groupName);
                    }

                    final searchMatch = _searchQuery.isEmpty ||
                        p.productName.toLowerCase().contains(_searchQuery) ||
                        (p.productCode?.toLowerCase().contains(_searchQuery) ?? false);

                    return groupMatch && searchMatch;
                  }).toList();

                  return GridView.builder(
                    padding: EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 80.0 + bottomPadding),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 200,
                      childAspectRatio: 0.85,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: products.length,
                    itemBuilder: (context, index) => _buildProductCard(products[index]),
                  );
                }).toList(),
              ),
            )
          : Scaffold(
              resizeToAvoidBottomInset: true,
              appBar: AppBar(
                title: Text('Giỏ hàng - ${widget.table.tableName}'),
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    icon: const Icon(
                      Icons.add_shopping_cart,
                      color: AppTheme.primaryColor,
                      size: 30,
                    ),
                    tooltip: 'Thêm món',
                    onPressed: () => setState(() => _isMenuView = true),
                  )
                ],
              ),
              body: _buildCartView(bottomPadding),
            ),
    );
  }

  Widget _buildMobileSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 8.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Tìm theo tên món...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30.0),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.grey[200],
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildMobileCartIcon() {
    // ... (Hàm này giữ nguyên) ...
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.shopping_cart_outlined, color: AppTheme.primaryColor, size: 30),
          onPressed: () {
            if (_displayCart.isEmpty) {
              setState(() => _isMenuView = true);
              ToastService().show(message: "Giỏ hàng trống, vui lòng chọn sản phẩm.", type: ToastType.warning);
            } else {
              setState(() => _isMenuView = false);
            }
          },
        ),
        if (_displayCart.isNotEmpty)
          Positioned(
            top: -0,
            right: 15,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(8),
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                _displayCart.values.fold<double>(0.0, (total, item) => total + item.quantity).toInt().toString(),
                style: const TextStyle(color: Colors.white, fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCartView(double bottomInset) {
    final textTheme = Theme.of(context).textTheme;
    final cartEntries = _displayCart.entries.toList().reversed.toList();
    final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');

    return Column(
      children: [
        const Divider(height: 1, thickness: 0.5, color: Colors.grey),
        Expanded(
          child: _displayCart.isEmpty
              ? Center(
                  child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Giỏ hàng của bạn đang trống.', style: textTheme.bodyMedium),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add_shopping_cart),
                      label: const Text('Quay lại chọn món'),
                      onPressed: () => setState(() => _isMenuView = true),
                    )
                  ],
                ))
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 8.0 + bottomInset),
                  itemCount: cartEntries.length,
                  itemBuilder: (context, index) {
                    final entry = cartEntries[index];
                    return _buildCartItemCard(entry.key, entry.value, currencyFormat);
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [BoxShadow(color: Colors.black.withAlpha(12), blurRadius: 10, offset: const Offset(0, -5))]),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Tổng cộng:', style: textTheme.displaySmall?.copyWith(fontSize: 18)),
                  Text(
                    currencyFormat.format(_totalAmount),
                    style:
                        textTheme.displaySmall?.copyWith(fontSize: 18, color: AppTheme.primaryColor, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Gởi yêu cầu'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _displayCart.isNotEmpty ? _handleCheckout : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        )
      ],
    );
  }

  Future<void> _addItemToCart(ProductModel product) async {
    // ... (Hàm này giữ nguyên) ...
    final bool needsOptionDialog = product.additionalUnits.isNotEmpty || product.accompanyingItems.isNotEmpty;
    OrderItem newItem;

    if (needsOptionDialog) {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => _ProductOptionsDialog(product: product, allProducts: _menuProducts),
      );
      if (result == null) return;
      final selectedUnit = result['selectedUnit'] as String;
      final priceForUnit = result['price'] as double;
      final selectedToppings = result['selectedToppings'] as Map<ProductModel, double>;
      newItem = OrderItem(
        product: product,
        selectedUnit: selectedUnit,
        price: priceForUnit,
        toppings: selectedToppings,
        addedBy: 'Khách hàng',
        addedAt: Timestamp.now(),
      );
    } else {
      newItem = OrderItem(
        product: product,
        price: product.sellPrice,
        selectedUnit: product.unit ?? '',
        addedBy: 'Khách hàng',
        addedAt: Timestamp.now(),
      );
    }

    final gk = newItem.groupKey;
    setState(() {
      final existingEntry = _displayCart.entries.firstWhereOrNull((entry) => entry.value.groupKey == gk);
      if (existingEntry != null) {
        final existingItem = existingEntry.value;
        final existingKey = existingEntry.key;
        _localChanges[existingKey] = existingItem.copyWith(quantity: existingItem.quantity + 1);
      } else {
        _localChanges[newItem.lineId] = newItem;
      }
    });
  }

  void _handleCheckout() {
    if (_displayCart.isEmpty) {
      ToastService().show(message: "Giỏ hàng của bạn đang trống.", type: ToastType.warning);
      return;
    }
    // Check _localChanges (chỉ những thay đổi MỚI)
    if (_localChanges.isEmpty && widget.table.id != 'web_ship_order' && widget.table.id != 'web_schedule_order') {
      ToastService().show(message: "Bạn chưa thay đổi món nào.", type: ToastType.warning);
      return;
    }
    if (_isSavingOrder) return;

    final String tableId = widget.table.id;

    if (tableId == 'web_ship_order') {
      _showShippingInfoDialog('ship');
    } else if (tableId == 'web_schedule_order') {
      _showShippingInfoDialog('schedule');
    } else {
      _handleAtTableOrder();
    }
  }

  Future<void> _handleShippingOrder(String type) async {
    if (!_formKey.currentState!.validate()) return;

    final int numberOfCustomers = int.tryParse(_numberOfCustomersController.text) ?? 1;

    final customerInfo = {
      'name': (type == 'ship') ? '' : _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'address': (type == 'ship') ? _addressController.text.trim() : _scheduleTimeController.text.trim(),
      'note': _noteController.text.trim(),
      'numberOfCustomers': (type == 'schedule' && widget.settings.businessType == "fnb") ? numberOfCustomers : 1,
    };

    final itemsToSend = _displayCart.values.toList();
    final totalAmount = _totalAmount;

    await _saveOrderToWeb(type: type, customerInfo: customerInfo, items: itemsToSend, totalAmount: totalAmount);
  }

  Future<void> _handleAtTableOrder() async {
    setState(() => _isSavingOrder = true);

    final bool isPending = widget.settings.qrOrderRequiresConfirmation ?? false;

    if (isPending) {
      // 1. CẦN XÁC NHẬN -> Gửi "PHẦN THAY ĐỔI" (DELTA) đến 'web_orders'

      final List<OrderItem> itemsDelta = [];
      double totalDelta = 0;

      for (final changedItem in _localChanges.values) {
        // Tìm trạng thái gốc (trong _cart + _pending)
        final originalItem = _pendingChanges[changedItem.lineId] ?? _cart[changedItem.lineId];
        final double originalQty = originalItem?.quantity ?? 0;
        final double newQty = changedItem.quantity;

        final double delta = newQty - originalQty;

        if (delta != 0) {
          final deltaItem = changedItem.copyWith(quantity: delta);
          itemsDelta.add(deltaItem);
          totalDelta += deltaItem.subtotal;
        }
      }

      if (itemsDelta.isEmpty) {
        ToastService().show(message: "Không có thay đổi nào để gửi.", type: ToastType.warning);
        if (mounted) setState(() => _isSavingOrder = false);
        return;
      }

      await _saveOrderToWeb(type: 'at_table', customerInfo: null, items: itemsDelta, totalAmount: totalDelta);
    } else {
      // 2. KHÔNG CẦN XÁC NHẬN -> Gửi thẳng vào 'orders' và báo bếp
      await _saveOrderToTableAndPrint();
    }
  }

  Future<void> _saveOrderToWeb({
    required String type,
    required Map<String, dynamic>? customerInfo,
    required List<OrderItem> items,
    required double totalAmount,
  }) async {
    if (!_isSavingOrder) {
      setState(() => _isSavingOrder = true);
    }

    try {
      final webOrderData = {
        'storeId': widget.table.storeId,
        'status': 'pending',
        'type': type,
        'customerInfo': customerInfo ?? {'name': 'Khách tại bàn'},
        'items': items.map((e) => e.toMap()).toList(),
        'totalAmount': totalAmount,
        'createdAt': FieldValue.serverTimestamp(),
        'tableName': widget.table.tableName,
        'tableId': widget.table.id,
        'note': (type != 'at_table' && customerInfo != null) ? customerInfo['note'] : null,
      };

      await _firestoreService.addWebOrder(webOrderData);

      if (type == 'ship' || type == 'schedule') {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }

      _showOrderSuccessDialog(
          type == 'at_table' ? "Đã gửi yêu cầu" : "Đặt hàng thành công!",
          type == 'at_table'
              ? "Yêu cầu của bạn đã được gửi, vui lòng chờ thu ngân xác nhận."
              : "Cửa hàng sẽ liên hệ với bạn để xác nhận đơn hàng.");

      if (type == 'at_table') {
        _moveLocalToPending();
      } else {
        _clearCartCompletelyAndReset();
      }
    } catch (e) {
      ToastService().show(message: "Lỗi gửi yêu cầu: $e", type: ToastType.error);
      if (mounted) setState(() => _isSavingOrder = false);
    }
  }

  Future<void> _saveOrderToTableAndPrint() async {
    final success = await _saveOrderAtTable();
    if (!success) {
      ToastService().show(message: "Gửi yêu cầu thất bại", type: ToastType.error);
      if (mounted) setState(() => _isSavingOrder = false);
      return;
    }

    _showOrderSuccessDialog("Gửi yêu cầu thành công!", "Yêu cầu của bạn đã được gửi thẳng đến bếp.");
    _resetUiFlagsAfterSave();
  }

  void _showShippingInfoDialog(String type) {
    final bool isShipping = type == 'ship';
    final title = isShipping ? 'Thông tin giao hàng' : 'Thông tin đặt lịch hẹn';

    _nameController.clear();
    _phoneController.clear();
    _addressController.clear();
    _scheduleTimeController.clear();
    _noteController.clear();
    _numberOfCustomersController.clear();

    _isSavingOrder = false;

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final dialogWidth = isMobile ? screenWidth * 0.9 : 500.0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: false, // Chặn hành động thoát mặc định
          onPopInvokedWithResult: (bool didPop, dynamic result) {
            if (didPop) return;

            // Logic xử lý nút Back:
            // 1. Nếu bàn phím đang mở -> Tắt bàn phím (unfocus)
            if (MediaQuery.of(context).viewInsets.bottom > 0) {
              FocusScope.of(context).unfocus();
            }
            // 2. Nếu bàn phím đã tắt -> Đóng Dialog (Giống nút Hủy)
            else {
              Navigator.of(context).pop();
            }
          },
          child: Center(
            child: StatefulBuilder(
              builder: (context, setStateDialog) {
                Future<void> pickScheduleTime() async {
                  DateTime? pickedDate = await showOmniDateTimePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now().subtract(const Duration(minutes: 10)),
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                    is24HourMode: true,
                    isShowSeconds: false,
                    minutesInterval: 15,
                  );

                  if (pickedDate != null) {
                    final formattedTime = DateFormat('HH:mm - dd/MM/yyyy').format(pickedDate);
                    setStateDialog(() {
                      _scheduleTimeController.text = formattedTime;
                    });
                  }
                }

                return AlertDialog(
                  title: Text(title),
                  contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  buttonPadding: EdgeInsets.zero,
                  actionsPadding: EdgeInsets.zero,
                  content: SizedBox(
                    width: dialogWidth,
                    child: Form(
                      key: _formKey,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isShipping) ...[
                              CustomTextFormField(
                                controller: _nameController,
                                decoration: const InputDecoration(
                                  labelText: 'Tên của bạn (*)',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                                validator: (value) => (value == null || value.isEmpty) ? 'Vui lòng nhập tên' : null,
                              ),
                              const SizedBox(height: 16),
                            ],
                            CustomTextFormField(
                              controller: _phoneController,
                              decoration: const InputDecoration(
                                labelText: 'Số điện thoại (*)',
                                prefixIcon: Icon(Icons.phone_outlined),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(10),
                              ],
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Vui lòng nhập SĐT';
                                }
                                if (value.length != 10) {
                                  return 'SĐT phải đủ 10 số';
                                }
                                if (!value.startsWith('0')) {
                                  return 'SĐT phải bắt đầu bằng số 0';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            if (isShipping) ...[
                              CustomTextFormField(
                                controller: _addressController,
                                decoration: const InputDecoration(
                                  labelText: 'Địa chỉ giao hàng (*)',
                                  prefixIcon: Icon(Icons.location_on_outlined),
                                ),
                                validator: (value) => (value == null || value.isEmpty) ? 'Vui lòng nhập địa chỉ' : null,
                              ),
                            ],
                            if (!isShipping) ...[
                              CustomTextFormField(
                                controller: _scheduleTimeController,
                                readOnly: true,
                                decoration: const InputDecoration(
                                  labelText: 'Thời gian đặt lịch (*)',
                                  prefixIcon: Icon(Icons.calendar_month_outlined),
                                ),
                                onTap: pickScheduleTime,
                                validator: (value) => (value == null || value.isEmpty) ? 'Vui lòng chọn thời gian' : null,
                              ),
                              if (widget.settings.businessType == "fnb") ...[
                                const SizedBox(height: 16),
                                CustomTextFormField(
                                  controller: _numberOfCustomersController,
                                  decoration: const InputDecoration(
                                    labelText: 'Số lượng khách',
                                    prefixIcon: Icon(Icons.people_alt_outlined),
                                  ),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(3),
                                  ],
                                ),
                              ],
                            ],
                            const SizedBox(height: 16),
                            CustomTextFormField(
                              controller: _noteController,
                              decoration: const InputDecoration(
                                labelText: 'Ghi chú',
                                prefixIcon: Icon(Icons.note_alt_outlined),
                              ),
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _isSavingOrder ? null : () => Navigator.of(context).pop(),
                            child: const Text('Hủy'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: _isSavingOrder
                                ? null
                                : () async {
                                    if (_formKey.currentState!.validate()) {
                                      setStateDialog(() => _isSavingOrder = true);
                                      await _handleShippingOrder(type);
                                      if (mounted) {
                                        setStateDialog(() => _isSavingOrder = false);
                                      }
                                    }
                                  },
                            child: _isSavingOrder
                                ? const SizedBox(
                                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Xác nhận'),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _clearCartCompletelyAndReset() {
    setState(() {
      _cart.clear();
      _localChanges.clear();
      _pendingChanges.clear();
      _isMenuView = true;
      _isSavingOrder = false;
    });
  }

  void _moveLocalToPending() {
    setState(() {
      _pendingChanges.addAll(_localChanges);
      _localChanges.clear();
      _isMenuView = true;
      _isSavingOrder = false;
    });
  }

  void _resetUiFlagsAfterSave() {
    setState(() {
      _isMenuView = true;
      _isSavingOrder = false;
    });
  }

  void _showOrderSuccessDialog(String title, String content) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Đã hiểu'),
          )
        ],
      ),
    );
  }

  Widget _buildProductCard(ProductModel product) {
    final quantityInCart = _displayCart.values
        .where((item) => item.product.id == product.id)
        .fold<double>(0.0, (total, item) => total + item.quantity);

    final bool hasLocalChanges = _localChanges.values.any((item) => item.product.id == product.id);

    return GestureDetector(
      onTap: () => _addItemToCart(product),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                Expanded(
                  child: (product.imageUrl != null && product.imageUrl!.isNotEmpty)
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: CachedNetworkImage(
                            imageUrl: product.imageUrl!,
                            fit: BoxFit.contain,
                            placeholder: (context, url) => const Center(child: CircularProgressIndicator(strokeWidth: 2.0)),
                            errorWidget: (context, url, error) => const Icon(Icons.image_not_supported, color: Colors.grey),
                          ),
                        )
                      : const Icon(Icons.fastfood, size: 50, color: Colors.grey),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Text(
                    '${formatNumber(product.sellPrice)} đ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (quantityInCart > 0)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  formatNumber(quantityInCart),
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          // --- SỬA LỖI 1 & 3: Thay đổi điều kiện hiển thị 'x' ---
          if (hasLocalChanges)
            Positioned(
              top: -2,
              left: -2,
              child: GestureDetector(
                onTap: () => _clearProductFromCart(product.id),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade700,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 17,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _clearProductFromCart(String productId) async {
    setState(() {
      final keysToRemove =
          _localChanges.entries.where((entry) => entry.value.product.id == productId).map((entry) => entry.key).toList();
      for (final key in keysToRemove) {
        _localChanges.remove(key);
      }
    });
  }

  Widget _buildCartItemCard(String cartId, OrderItem item, NumberFormat currencyFormat) {
    final textTheme = Theme.of(context).textTheme;
    final originalItem = _cart[cartId];
    final sentQuantity = originalItem?.sentQuantity ?? 0;
    final bool isPending = _pendingChanges.containsKey(cartId);
    final bool isLocal = _localChanges.containsKey(cartId);
    final double baseQuantity = _pendingChanges[cartId]?.quantity ?? sentQuantity;
    final change = item.quantity - baseQuantity;
    final bool isCancelled = item.quantity == 0;

    IconData iconData;
    Color iconColor;

    if (isCancelled) {
      iconData = Icons.cancel_outlined;
      iconColor = Colors.grey;
    } else if (isLocal) {
      iconData = Icons.notifications_on_outlined;
      iconColor = Colors.grey;
    } else if (isPending) {
      iconData = Icons.hourglass_top_outlined;
      iconColor = Colors.orange.shade700;
    } else if (sentQuantity > 0) {
      iconData = Icons.notifications_active_outlined;
      iconColor = AppTheme.primaryColor;
    } else {
      iconData = Icons.help_outline;
      iconColor = Colors.grey;
    }

    return Card(
      child: InkWell(
        onTap: () => _showEditItemDialog(cartId, item),
        borderRadius: BorderRadius.circular(12.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    iconData,
                    color: iconColor,
                    size: 20,
                  ),
                  if (isLocal && change != 0 && !isCancelled) ...[
                    const SizedBox(width: 4),
                    Text(
                      change > 0 ? "+${formatNumber(change)}" : formatNumber(change),
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: '${item.product.productName} ',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isCancelled ? Colors.grey : AppTheme.textColor,
                            decoration: isCancelled ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        if (item.selectedUnit.isNotEmpty)
                          TextSpan(
                            text: '(${item.selectedUnit})',
                            style: textTheme.bodyMedium?.copyWith(
                              color: isCancelled ? Colors.grey : Colors.grey.shade700,
                              decoration: isCancelled ? TextDecoration.lineThrough : null,
                            ),
                          ),
                      ]),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
              if (item.toppings.isNotEmpty || (item.note != null && item.note!.isNotEmpty))
                Padding(
                  padding: const EdgeInsets.only(left: 32, bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.toppings.isNotEmpty) _buildToppingsList(item.toppings, currencyFormat),
                      if (item.note != null && item.note!.isNotEmpty)
                        Text('Ghi chú: ${item.note}', style: const TextStyle(color: Colors.red, fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(
                      currencyFormat.format(item.price),
                      style: textTheme.bodyMedium?.copyWith(color: isCancelled ? Colors.grey : null),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: isCancelled ? Colors.transparent : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          splashRadius: 18,
                          icon: Icon(Icons.remove, size: 18, color: Colors.red.shade400),
                          onPressed: () => _updateQuantity(cartId, -1),
                        ),
                        InkWell(
                          onTap: () => _showEditItemDialog(cartId, item),
                          child: Container(
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12.0),
                                border: Border.all(color: Colors.grey.shade300, width: 0.5)),
                            alignment: Alignment.center,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              maxWidth: 65,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
                            child: Text(
                              formatNumber(item.quantity),
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isCancelled ? Colors.grey : null,
                                decoration: isCancelled ? TextDecoration.lineThrough : null,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          splashRadius: 18,
                          icon: const Icon(Icons.add, size: 18, color: AppTheme.primaryColor),
                          onPressed: () => _updateQuantity(cartId, 1),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: Text(
                      currencyFormat.format(item.subtotal),
                      textAlign: TextAlign.right,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isCancelled ? Colors.grey : null,
                        decoration: isCancelled ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEditItemDialog(String cartId, OrderItem item) async {
    if (item.quantity <= 0) return;

    final relevantNotes = _quickNotes.where((note) {
      return note.productIds.isEmpty || note.productIds.contains(item.product.id);
    }).toList();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _GuestEditItemDialog(
        initialItem: item,
        relevantQuickNotes: relevantNotes,
      ),
    );

    if (result == null) return;

    final newQuantity = result['quantity'] as double;
    final newNote = (result['note'] as String?).nullIfEmpty;

    if (newQuantity <= 0) {
      _updateQuantity(cartId, newQuantity - item.quantity);
      return;
    }

    setState(() {
      _localChanges[cartId] = item.copyWith(
        quantity: newQuantity,
        note: () => newNote,
      );
    });
  }

  Widget _buildToppingsList(Map<ProductModel, double> toppings, NumberFormat currencyFormat) {
    return Padding(
      padding: const EdgeInsets.only(top: 2.0),
      child: Wrap(
        spacing: 16.0,
        runSpacing: 4.0,
        children: toppings.entries.map((entry) {
          final topping = entry.key;
          final quantity = entry.value;
          return Text(
            '+ ${topping.productName} (${currencyFormat.format(topping.sellPrice)} x ${NumberFormat('#,##0.##').format(quantity)})',
            style: Theme.of(context).textTheme.bodyMedium,
          );
        }).toList(),
      ),
    );
  }
}

class _ProductOptionsDialog extends StatefulWidget {
  final ProductModel product;
  final List<ProductModel> allProducts;

  const _ProductOptionsDialog({required this.product, required this.allProducts});

  @override
  State<_ProductOptionsDialog> createState() => _ProductOptionsDialogState();
}

class _ProductOptionsDialogState extends State<_ProductOptionsDialog> {
  late String _selectedUnit;
  late Map<String, dynamic> _baseUnitData;
  late List<Map<String, dynamic>> _allUnitOptions;
  List<ProductModel> _accompanyingProducts = [];
  final Map<String, double> _selectedToppings = {};

  @override
  void initState() {
    super.initState();
    _baseUnitData = {'unitName': widget.product.unit ?? '', 'sellPrice': widget.product.sellPrice};
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
    final selectedUnitData = _allUnitOptions.firstWhere((u) => u['unitName'] == _selectedUnit);
    final priceForSelectedUnit = (selectedUnitData['sellPrice'] as num).toDouble();
    final Map<ProductModel, double> toppingsMap = {};
    _selectedToppings.forEach((productId, quantity) {
      if (quantity > 0) {
        final product = _accompanyingProducts.firstWhere((p) => p.id == productId);
        toppingsMap[product] = quantity;
      }
    });
    Navigator.of(context).pop({
      'selectedUnit': _selectedUnit,
      'price': priceForSelectedUnit,
      'selectedToppings': toppingsMap,
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        final rootInsets = MediaQuery.of(this.context).viewInsets.bottom;
        if (rootInsets > 0) {
          FocusScope.of(context).unfocus();
        } else {
          Navigator.of(context).pop();
        }
      },
      child: AlertDialog(
        title: Text(widget.product.productName, textAlign: TextAlign.center),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.product.additionalUnits.isNotEmpty) ...[
                  const Text('Chọn đơn vị tính:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: _allUnitOptions.map((unitData) {
                      return ButtonSegment<String>(
                        value: unitData['unitName'] as String,
                        label: Text(unitData['unitName'] as String),
                      );
                    }).toList(),
                    selected: {_selectedUnit},
                    onSelectionChanged: (newSelection) {
                      setState(() => _selectedUnit = newSelection.first);
                    },
                  ),
                  const Divider(height: 24),
                ],
                if (_accompanyingProducts.isNotEmpty) ...[
                  const Text('Chọn Topping/Bán kèm:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ..._accompanyingProducts.map((topping) {
                    final quantity = _selectedToppings[topping.id] ?? 0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('${topping.productName} (+${formatNumber(topping.sellPrice)}đ)'),
                          ),
                          Container(
                            decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove, size: 18, color: Colors.red),
                                  onPressed: () => _updateToppingQuantity(topping.id, -1),
                                ),
                                Text(formatNumber(quantity)),
                                IconButton(
                                  icon: const Icon(Icons.add, size: 18, color: AppTheme.primaryColor),
                                  onPressed: () => _updateToppingQuantity(topping.id, 1),
                                ),
                              ],
                            ),
                          )
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Hủy')),
          ElevatedButton(onPressed: _onConfirm, child: const Text('Xác nhận')),
        ],
      ),
    );
  }
}

class _GuestEditItemDialog extends StatefulWidget {
  final OrderItem initialItem;
  final List<QuickNoteModel> relevantQuickNotes;

  const _GuestEditItemDialog({
    required this.initialItem,
    required this.relevantQuickNotes,
  });

  @override
  State<_GuestEditItemDialog> createState() => _GuestEditItemDialogState();
}

class _GuestEditItemDialogState extends State<_GuestEditItemDialog> {
  late final TextEditingController _quantityController;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(text: formatNumber(widget.initialItem.quantity));
    _noteController = TextEditingController(text: widget.initialItem.note ?? '');
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _onConfirm() {
    final double quantity = parseVN(_quantityController.text);
    if (quantity < 0) {
      // Cho phép bằng 0 (để hủy)
      ToastService().show(message: "Số lượng không hợp lệ", type: ToastType.warning);
      return;
    }

    Navigator.of(context).pop({
      'quantity': quantity,
      'note': _noteController.text,
    });
  }

  void _addQuickNote(String note) {
    String currentNote = _noteController.text;
    if (currentNote.isEmpty) {
      _noteController.text = note;
    } else {
      _noteController.text = '$currentNote, $note';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;

        if (MediaQuery.of(context).viewInsets.bottom > 0) {
          FocusScope.of(context).unfocus();
        } else {
          Navigator.of(context).pop();
        }
      },
      child: AlertDialog(
        title: Text(widget.initialItem.product.productName, textAlign: TextAlign.center),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.9,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomTextFormField(
                  controller: _quantityController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Số lượng',
                    prefixIcon: Icon(Icons.calculate_outlined),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [ThousandDecimalInputFormatter()],
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Không được trống';
                    }
                    final val = parseVN(value);
                    if (val < 0) return 'Số lượng không hợp lệ';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                CustomTextFormField(
                  controller: _noteController,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú',
                    prefixIcon: Icon(Icons.note_alt_outlined),
                  ),
                  maxLines: 1,
                ),
                const SizedBox(height: 16),
                if (widget.relevantQuickNotes.isNotEmpty) ...[
                  Text('Ghi chú nhanh:', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 4.0,
                    children: widget.relevantQuickNotes.map((note) {
                      return ActionChip(
                        label: Text(note.noteText),
                        onPressed: () => _addQuickNote(note.noteText),
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: _onConfirm,
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
  }
}
