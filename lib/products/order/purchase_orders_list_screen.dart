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

class PurchaseOrderService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final CollectionReference _poCollection =
  FirebaseFirestore.instance.collection('purchase_orders');

  Stream<List<PurchaseOrderModel>> getPurchaseOrdersStream({
    DateTime? startDate,
    DateTime? endDate,
    String? status,
    String? supplierName,
    String? createdBy,
    String? updatedBy,
    String? purchaseOrderId,
  }) {
    Query query = _poCollection;

    if (purchaseOrderId != null && purchaseOrderId.isNotEmpty) {
      query = query.where(FieldPath.documentId, isEqualTo: purchaseOrderId);
      return query.snapshots().map((snapshot) => snapshot.docs
          .map((doc) => PurchaseOrderModel.fromFirestore(doc))
          .toList());
    }

    if (startDate != null) {
      query = query.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
    }
    if (endDate != null) {
      query = query.where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate));
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

  Future<List<String>> getDistinctSupplierNames() async {
    try {
      final snapshot = await _db.collection('suppliers').get();
      if (snapshot.docs.isEmpty) return [];
      final names = snapshot.docs
          .map((doc) => doc.data()['name'] as String?)
          .nonNulls
          .toSet();
      return names.toList()..sort();
    } catch (e) {
      debugPrint('Lỗi khi lấy danh sách nhà cung cấp: $e');
      return [];
    }
  }

  Future<List<String>> getDistinctUserNames() async {
    try {
      final snapshot = await _db.collection('users').get();
      if (snapshot.docs.isEmpty) return [];
      final names = snapshot.docs
          .map((doc) => doc.data()['name'] as String?)
          .nonNulls
          .toSet();
      return names.toList()..sort();
    } catch (e) {
      debugPrint('Lỗi khi lấy danh sách người dùng: $e');
      return [];
    }
  }
}

class PurchaseOrdersListScreen extends StatefulWidget {
  final UserModel currentUser;
  final String? initialPurchaseOrderId;

  const PurchaseOrdersListScreen({super.key,
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
  final List<String> _statusOptions = ['Hoàn thành', 'Chưa thanh toán đủ', 'Đã hủy'];
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
        _poService.getDistinctSupplierNames(),
        _poService.getDistinctUserNames(),
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
      debugPrint("Lỗi khi tải dữ liệu bộ lọc: $e");
      if (mounted) {
        setState(() {
          _isLoadingFilters = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể tải các tùy chọn bộ lọc.')),
        );
      }
    }
  }

  void _navigateToCreateScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CreatePurchaseOrderScreen(currentUser: widget.currentUser),
      ),
    );
  }

  void _navigateToEditScreen(PurchaseOrderModel order) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CreatePurchaseOrderScreen(
          currentUser: widget.currentUser,
          existingPurchaseOrder: order,
        ),
      ),
    );
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

            // Hàm gọi Omni Picker mới
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

            // Tạo Subtitle cho ListTile
            String subtitleText;
            if (tempStartDate == null && tempEndDate == null) {
              subtitleText = 'Chưa chọn';
            } else {
              final start = tempStartDate != null ? dateFormat.format(tempStartDate!) : '...';
              final end = tempEndDate != null ? dateFormat.format(tempEndDate!) : '...';
              subtitleText = '$start - $end';
            }


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
                    leading: const Icon(Icons.calendar_month, color: AppTheme.primaryColor),
                    title: Text('Khoảng thời gian', style: AppTheme.regularGreyTextStyle),
                    subtitle: Text(
                      subtitleText,
                      style: AppTheme.boldTextStyle.copyWith(fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
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
                    items: _supplierOptions.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                    onChanged: (value) => setModalState(() => tempSupplier = (value == 'Tất cả') ? null : value),
                  ),
                  AppDropdown<String>(
                    labelText: 'Trạng thái',
                    value: tempStatus,
                    items: _statusOptions.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                    onChanged: (value) => setModalState(() => tempStatus = (value == 'Tất cả') ? null : value),
                  ),
                  AppDropdown<String>(
                    labelText: 'Người tạo',
                    value: tempCreator,
                    items: _userOptions.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                    onChanged: (value) => setModalState(() => tempCreator = (value == 'Tất cả') ? null : value),
                  ),
                  AppDropdown<String>(
                    labelText: 'Người sửa',
                    value: tempUpdater,
                    items: _userOptions.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                    onChanged: (value) => setModalState(() => tempUpdater = (value == 'Tất cả') ? null : value),
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
        title: Text(_isFilteredById ? 'Chi tiết Phiếu Nhập' : 'Phiếu nhập hàng'),
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
            debugPrint("Lỗi Firestore Stream: ${snapshot.error}");
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Đã xảy ra lỗi. Vui lòng kiểm tra Debug Console để biết chi tiết và tạo Index cho Firestore nếu được yêu cầu.',
                  textAlign: TextAlign.center,
                  style: AppTheme.regularGreyTextStyle,
                ),
              ),
            );
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            final message = _isFilteredById
                ? 'Không tìm thấy chi tiết phiếu nhập.'
                : 'Không tìm thấy phiếu nhập hàng nào.\nHãy thử lại với bộ lọc khác hoặc nhấn "+" để tạo phiếu mới.';
            return Center(
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }
          final purchaseOrders = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: purchaseOrders.length,
            itemBuilder: (context, index) {
              return _PurchaseOrderCard(
                canEdit: _canEditPurchaseOrder,
                order: purchaseOrders[index],
                onTap: () => _navigateToEditScreen(purchaseOrders[index]),
              );
            },
          );
        },
      ),
    );
  }
}

class _PurchaseOrderCard extends StatelessWidget {
  final PurchaseOrderModel order;
  final VoidCallback onTap;
  final bool canEdit;

  const _PurchaseOrderCard({required this.order,
    required this.onTap,
    required this.canEdit,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = order.status == 'Hoàn thành'
        ? Colors.green
        : order.status == 'Đã hủy'
        ? Colors.red
        : Colors.orange;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          if (canEdit) {
              onTap();
          } else {
            ToastService().show(
                message: 'Bạn chưa được cấp quyền sử dụng tính năng này.',
                type: ToastType.warning);
          }
        },        borderRadius: BorderRadius.circular(12),
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
                    style: AppTheme.boldTextStyle.copyWith(fontSize: 16, color: AppTheme.primaryColor),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      order.status,
                      style: AppTheme.boldTextStyle.copyWith(color: statusColor, fontSize: 14),
                    ),
                  )
                ],
              ),
              const Divider(height: 8, thickness: 0.5, color: Colors.grey,),
              _buildInfoRow(Icons.store_mall_directory_outlined, 'NCC:', order.supplierName),
              const SizedBox(height: 4),
              _buildInfoRow(Icons.person_outline, 'Người tạo:', order.createdBy),
              const SizedBox(height: 4),
              _buildInfoRow(
                Icons.calendar_month,
                'Ngày tạo:',
                DateFormat('HH:mm dd/MM/yyyy').format(order.createdAt),              ),
              if (order.updatedAt != null) ...[
                const SizedBox(height: 4),
                _buildInfoRow(
                  Icons.edit_outlined,
                  order.status == 'Đã hủy' ? 'Người hủy:' : 'Người sửa:',
                  order.updatedBy ?? 'Không rõ',
                ),
                const SizedBox(height: 4),
                _buildInfoRow(
                  Icons.history_outlined,
                  order.status == 'Đã hủy' ? 'Ngày hủy:' : 'Ngày sửa:',
                  DateFormat('HH:mm dd/MM/yyyy').format(order.updatedAt!),
                ),
              ],
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Tổng cộng: ${formatNumber(order.totalAmount)} đ',
                  style: AppTheme.boldTextStyle.copyWith(fontSize: 16),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.black),
        const SizedBox(width: 8),
        Text(label, style: AppTheme.regularGreyTextStyle.copyWith(color: Colors.black, fontSize: 16)),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            value,
            style: AppTheme.regularGreyTextStyle.copyWith(color: Colors.black, fontSize: 16),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}