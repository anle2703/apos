// lib/products/order/purchase_orders_list_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/purchase_order_model.dart';
import '../../theme/app_theme.dart';
import '../../theme/number_utils.dart';
import '../../models/user_model.dart';
import 'create_purchase_order_screen.dart';
import '../../widgets/app_dropdown.dart';
import '../../services/toast_service.dart';
import 'package:omni_datetime_picker/omni_datetime_picker.dart';
import '../labels/product_label_print_screen.dart';

class PurchaseOrderService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final CollectionReference _poCollection =
  FirebaseFirestore.instance.collection('purchase_orders');

  Stream<List<PurchaseOrderModel>> getPurchaseOrdersStream(
      String storeId, {
        DateTime? startDate,
        DateTime? endDate,
        String? status,
        String? supplierName,
        String? createdBy,
        String? updatedBy,
        String? purchaseOrderId,
      }) {
    Query query = _poCollection.where('storeId', isEqualTo: storeId);

    if (purchaseOrderId != null && purchaseOrderId.isNotEmpty) {
      query = query.where(FieldPath.documentId, isEqualTo: purchaseOrderId);
      return query.snapshots().map((snapshot) => snapshot.docs
          .map((doc) => PurchaseOrderModel.fromFirestore(doc))
          .toList());
    }

    if (startDate != null) {
      query = query.where('createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
    }
    if (endDate != null) {
      query = query.where('createdAt',
          isLessThanOrEqualTo: Timestamp.fromDate(endDate));
    }
    if (status != null && status.isNotEmpty) {
      query = query.where('status', isEqualTo: status);
    }
    if (supplierName != null && supplierName.isNotEmpty) {
      query = query.where('supplierName', isEqualTo: supplierName);
    }
    if (createdBy != null && createdBy.isNotEmpty) {
      query = query.where('createdByName', isEqualTo: createdBy);
    }
    if (updatedBy != null && updatedBy.isNotEmpty) {
      query = query.where('updatedByName', isEqualTo: updatedBy);
    }

    return query
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => PurchaseOrderModel.fromFirestore(doc))
        .toList());
  }

  Future<List<String>> getDistinctSupplierNames(String storeId) async {
    try {
      final snapshot = await _db
          .collection('suppliers')
          .where('storeId', isEqualTo: storeId)
          .get();
      if (snapshot.docs.isEmpty) return [];
      final names = snapshot.docs
          .map((doc) => doc.data()['name'] as String?)
          .nonNulls
          .toSet();
      return names.toList()..sort();
    } catch (e) {
      return [];
    }
  }

  Future<List<String>> getDistinctUserNames(String storeId) async {
    try {
      final snapshot = await _db
          .collection('users')
          .where('storeId', isEqualTo: storeId)
          .get();
      if (snapshot.docs.isEmpty) return [];
      final names = snapshot.docs
          .map((doc) => doc.data()['name'] as String?)
          .nonNulls
          .toSet();
      return names.toList()..sort();
    } catch (e) {
      return [];
    }
  }
}

class PurchaseOrdersListScreen extends StatefulWidget {
  final UserModel currentUser;
  final String? initialPurchaseOrderId;

  const PurchaseOrdersListScreen({
    super.key,
    required this.currentUser,
    this.initialPurchaseOrderId,
  });

  @override
  State<PurchaseOrdersListScreen> createState() =>
      _PurchaseOrdersListScreenState();
}

class _PurchaseOrdersListScreenState extends State<PurchaseOrdersListScreen> {
  final PurchaseOrderService _poService = PurchaseOrderService();

  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;
  String? _selectedStatus;
  String? _selectedSupplier;
  String? _selectedCreator;
  String? _selectedUpdater;
  bool _canAddPurchaseOrder = false;
  bool _canEditPurchaseOrder = false;
  bool _isLoadingFilters = true;
  List<String> _supplierOptions = [];
  List<String> _userOptions = [];
  final List<String> _statusOptions = [
    'Hoàn thành',
    'Nợ',
    'Đã hủy'
  ];
  bool _isFilteredById = false;

  @override
  void initState() {
    super.initState();
    _isFilteredById = widget.initialPurchaseOrderId != null;

    if (widget.currentUser.role == 'owner') {
      _canAddPurchaseOrder = true;
      _canEditPurchaseOrder = true;
    } else {
      _canAddPurchaseOrder = widget.currentUser.permissions?['purchaseOrder']
      ?['canAddPurchaseOrder'] ??
          false;
      _canEditPurchaseOrder = widget.currentUser.permissions?['purchaseOrder']
      ?['canEditPurchaseOrder'] ??
          false;
    }
    if (!_isFilteredById) {
      _loadFilterData();
    } else {
      _isLoadingFilters = false;
    }
  }

  Future<void> _loadFilterData() async {
    try {
      final results = await Future.wait([
        _poService.getDistinctSupplierNames(widget.currentUser.storeId),
        _poService.getDistinctUserNames(widget.currentUser.storeId),
      ]);

      if (mounted) {
        setState(() {
          final supplierSet = results[0].toSet();
          supplierSet.add('Nhà cung cấp lẻ');
          _supplierOptions = supplierSet.toList()..sort();
          _supplierOptions.insert(0, 'Tất cả');

          _userOptions = results[1];
          if (_userOptions.isNotEmpty) {
            _userOptions.insert(0, 'Tất cả');
          }

          if (!_statusOptions.contains('Tất cả')) {
            _statusOptions.insert(0, 'Tất cả');
          }
          _isLoadingFilters = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingFilters = false);
    }
  }

  void _navigateToCreateScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            CreatePurchaseOrderScreen(currentUser: widget.currentUser),
      ),
    );
  }

  void _navigateToEditScreen(PurchaseOrderModel order) {
    if (_canEditPurchaseOrder) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CreatePurchaseOrderScreen(
            currentUser: widget.currentUser,
            existingPurchaseOrder: order,
          ),
        ),
      );
    } else {
      ToastService().show(
          message: 'Bạn chưa được cấp quyền sửa phiếu nhập.',
          type: ToastType.warning);
    }
  }

  void _showFilterModal() {
    DateTime? tempStartDate = _selectedStartDate;
    DateTime? tempEndDate = _selectedEndDate;
    String? tempStatus = _selectedStatus;
    String? tempSupplier = _selectedSupplier;
    String? tempCreator = _selectedCreator;
    String? tempUpdater = _selectedUpdater;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            final dateFormat = DateFormat('HH:mm dd/MM/yy');

            Future<void> pickDateRange() async {
              if (!mounted) return;
              List<DateTime>? pickedRange = await showOmniDateTimeRangePicker(
                context: context,
                startInitialDate: tempStartDate ?? DateTime.now(),
                endInitialDate: tempEndDate,
                startFirstDate: DateTime(2020),
                startLastDate: DateTime.now().add(const Duration(days: 365)),
                endFirstDate: tempStartDate ?? DateTime(2020),
                endLastDate: DateTime.now().add(const Duration(days: 365)),
                is24HourMode: true,
                isShowSeconds: false,
                type: OmniDateTimePickerType.dateAndTime,
              );

              if (pickedRange != null && pickedRange.length == 2) {
                setModalState(() {
                  tempStartDate = pickedRange[0];
                  tempEndDate = pickedRange[1];
                });
              }
            }

            String subtitleText = (tempStartDate == null && tempEndDate == null)
                ? 'Chưa chọn'
                : '${tempStartDate != null ? dateFormat.format(tempStartDate!) : '...'} - ${tempEndDate != null ? dateFormat.format(tempEndDate!) : '...'}';

            return Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20,
                  MediaQuery.of(context).viewInsets.bottom + 20),
              child: Wrap(
                runSpacing: 16,
                children: [
                  Text('Lọc Phiếu Nhập Hàng',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const Divider(),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: const Icon(Icons.calendar_month,
                        color: AppTheme.primaryColor),
                    title: Text('Khoảng thời gian',
                        style: AppTheme.regularGreyTextStyle),
                    subtitle: Text(subtitleText,
                        style: AppTheme.boldTextStyle.copyWith(fontSize: 16)),
                    onTap: pickDateRange,
                    trailing: (tempStartDate != null || tempEndDate != null)
                        ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () => setModalState(() {
                        tempStartDate = null;
                        tempEndDate = null;
                      }),
                    )
                        : null,
                  ),
                  AppDropdown<String>(
                    labelText: 'Nhà cung cấp',
                    value: tempSupplier,
                    items: _supplierOptions
                        .map((item) =>
                        DropdownMenuItem(value: item, child: Text(item)))
                        .toList(),
                    onChanged: (value) => setModalState(() =>
                    tempSupplier = (value == 'Tất cả') ? null : value),
                  ),
                  AppDropdown<String>(
                    labelText: 'Trạng thái',
                    value: tempStatus,
                    items: _statusOptions
                        .map((item) =>
                        DropdownMenuItem(value: item, child: Text(item)))
                        .toList(),
                    onChanged: (value) => setModalState(
                            () => tempStatus = (value == 'Tất cả') ? null : value),
                  ),
                  AppDropdown<String>(
                    labelText: 'Người tạo',
                    value: tempCreator,
                    items: _userOptions
                        .map((item) =>
                        DropdownMenuItem(value: item, child: Text(item)))
                        .toList(),
                    onChanged: (value) => setModalState(
                            () => tempCreator = (value == 'Tất cả') ? null : value),
                  ),
                  AppDropdown<String>(
                    labelText: 'Người sửa',
                    value: tempUpdater,
                    items: _userOptions
                        .map((item) =>
                        DropdownMenuItem(value: item, child: Text(item)))
                        .toList(),
                    onChanged: (value) => setModalState(
                            () => tempUpdater = (value == 'Tất cả') ? null : value),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedStartDate = null;
                            _selectedEndDate = null;
                            _selectedStatus = null;
                            _selectedSupplier = null;
                            _selectedCreator = null;
                            _selectedUpdater = null;
                          });
                          Navigator.of(ctx).pop();
                        },
                        child: const Text('Xóa bộ lọc'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _selectedStartDate = tempStartDate;
                            _selectedEndDate = tempEndDate;
                            _selectedStatus = tempStatus;
                            _selectedSupplier = tempSupplier;
                            _selectedCreator = tempCreator;
                            _selectedUpdater = tempUpdater;
                          });
                          Navigator.of(ctx).pop();
                        },
                        child: const Text('Áp dụng'),
                      ),
                    ],
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
        Text(_isFilteredById ? 'Chi tiết Phiếu Nhập' : 'Phiếu nhập hàng'),
        actions: [
          if (!_isFilteredById) ...[
            IconButton(
              icon: _isLoadingFilters
                  ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.primaryColor),
              )
                  : const Icon(Icons.filter_list,
                  color: AppTheme.primaryColor, size: 30),
              tooltip: 'Lọc',
              onPressed: _isLoadingFilters ? null : _showFilterModal,
            ),
            if (_canAddPurchaseOrder)
              IconButton(
                icon: const Icon(Icons.add_circle),
                iconSize: 30.0,
                color: AppTheme.primaryColor,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                onPressed: _navigateToCreateScreen,
                tooltip: 'Tạo phiếu mới',
              ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<List<PurchaseOrderModel>>(
        stream: _poService.getPurchaseOrdersStream(
          widget.currentUser.storeId,
          purchaseOrderId: widget.initialPurchaseOrderId,
          startDate: _selectedStartDate,
          endDate: _selectedEndDate,
          status: _selectedStatus,
          supplierName: _selectedSupplier,
          createdBy: _selectedCreator,
          updatedBy: _selectedUpdater,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Lỗi khi tải dữ liệu'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Không tìm thấy phiếu nhập nào.'));
          }

          final purchaseOrders = snapshot.data!;

          // FIX LỖI: Sử dụng ListView.separated và thêm cacheExtent
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: purchaseOrders.length,
            // [QUAN TRỌNG] cacheExtent giúp giữ widget sống lâu hơn khi cuộn,
            // tránh lỗi hitTest khi widget bị destroy quá nhanh.
            cacheExtent: 500,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final order = purchaseOrders[index];
              return _PurchaseOrderCard(
                key: ValueKey(order.id),
                order: order,
                currentUser: widget.currentUser,
                onEditTap: () => _navigateToEditScreen(order),
              );
            },
          );
        },
      ),
    );
  }
}

class _PurchaseOrderCard extends StatelessWidget {
  final UserModel currentUser;
  final PurchaseOrderModel order;
  final VoidCallback onEditTap;

  const _PurchaseOrderCard({
    super.key,
    required this.order,
    required this.currentUser,
    required this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width > 600;

    final bool isRetail = currentUser.businessType == 'retail';

    final statusColor = order.status == 'Hoàn thành'
        ? Colors.green
        : order.status == 'Đã hủy'
        ? Colors.red
        : Colors.orange;

    String displayStatus = order.status;
    if (order.status == 'Nợ') {
      final double debt = (order.debtAmount).toDouble();
      displayStatus = 'Dư nợ: ${formatNumber(debt)} đ';
    }

    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. PHẦN THÔNG TIN
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onEditTap,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        order.code,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: AppTheme.primaryColor),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withAlpha(25),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          displayStatus,
                          style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                      )
                    ],
                  ),
                  const Divider(height: 6, thickness: 0.5, color: Colors.grey,),

                  _buildSimpleRow(Icons.store, 'NCC:', order.supplierName),
                  const SizedBox(height: 4),

                  if (isDesktop)
                  // [DESKTOP] Dùng isCompact: true để các cột nằm gần nhau
                    Row(
                      children: [
                        Flexible(
                            child: _buildSimpleRow(Icons.person_outline, 'Tạo:', order.createdBy, isCompact: true)
                        ),
                        const SizedBox(width: 24), // Khoảng cách cố định 24px
                        Flexible(
                            child: _buildSimpleRow(Icons.access_time, 'Lúc:', DateFormat('HH:mm dd/MM/yyyy').format(order.createdAt), isCompact: true)
                        ),
                      ],
                    )
                  else ...[
                    // [MOBILE] Giữ nguyên hiển thị dọc
                    _buildSimpleRow(Icons.person_outline, 'Tạo:', order.createdBy),
                    const SizedBox(height: 4),
                    _buildSimpleRow(Icons.access_time, 'Lúc:', DateFormat('HH:mm dd/MM/yyyy').format(order.createdAt)),
                  ],

                  if (order.updatedAt != null) ...[
                    const SizedBox(height: 4),
                    if (isDesktop)
                    // [DESKTOP] Dùng isCompact: true
                      Row(
                        children: [
                          Flexible(
                            child: _buildSimpleRow(
                              Icons.edit_outlined,
                              order.status == 'Đã hủy' ? 'Hủy:' : 'Sửa:',
                              order.updatedBy ?? 'N/A',
                              isCompact: true,
                            ),
                          ),
                          const SizedBox(width: 24), // Khoảng cách cố định 24px
                          Flexible(
                            child: _buildSimpleRow(
                              Icons.history,
                              'Lúc:',
                              DateFormat('HH:mm dd/MM/yyyy').format(order.updatedAt!),
                              isCompact: true,
                            ),
                          ),
                        ],
                      )
                    else ...[
                      // [MOBILE]
                      _buildSimpleRow(
                        Icons.edit_outlined,
                        order.status == 'Đã hủy' ? 'Hủy:' : 'Sửa:',
                        order.updatedBy ?? 'N/A',
                      ),
                      const SizedBox(height: 4),
                      _buildSimpleRow(
                        Icons.history,
                        'Lúc:',
                        DateFormat('HH:mm dd/MM/yyyy').format(order.updatedAt!),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),

          // 2. PHẦN NÚT BẤM VÀ GIÁ
          Container(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (isRetail)
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ProductLabelPrintScreen(
                            currentUser: currentUser,
                            initialPurchaseOrder: order,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.print, size: 18),
                    label: const Text("In Tem"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.primaryColor,
                      elevation: 0,
                      side: const BorderSide(color: AppTheme.primaryColor),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  )
                else
                  const SizedBox(),

                Text(
                  '${formatNumber(order.totalAmount)} đ',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleRow(IconData icon, String label, String value, {Color? textColor, bool isCompact = false}) {
    final color = textColor ?? Colors.grey[600];
    final valueColor = textColor ?? Colors.black87;

    Widget textWidget = Text(
        value,
        style: TextStyle(color: valueColor, fontSize: 14),
        overflow: TextOverflow.ellipsis
    );

    Widget contentWidget = isCompact
        ? Flexible(fit: FlexFit.loose, child: textWidget)
        : Expanded(child: textWidget);

    return Row(
      mainAxisSize: MainAxisSize.min, // Giúp Row co lại vừa với nội dung
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: color, fontSize: 14)),
        const SizedBox(width: 4),
        contentWidget,
      ],
    );
  }
}