// lib/widgets/customer_selector.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/customer_model.dart';
import '../screens/contacts/add_edit_customer_dialog.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

class CustomerSelector extends StatelessWidget {
  final CustomerModel? currentCustomer;
  final ValueChanged<CustomerModel?> onCustomerSelected;
  final String storeId;
  final FirestoreService firestoreService;

  const CustomerSelector({
    super.key,
    required this.currentCustomer,
    required this.onCustomerSelected,
    required this.storeId,
    required this.firestoreService,
  });

  Future<void> _showCustomerSearch(BuildContext context) async {
    final result = await showDialog<dynamic>(
      context: context,
      builder: (context) => CustomerSearchDialog(
        firestoreService: firestoreService,
        storeId: storeId,
        currentCustomer: currentCustomer,
      ),
    );

    if (result == null) return;

    if (result is CustomerModel) {
      onCustomerSelected(result);
    } else if (result is bool && result == false) {
      onCustomerSelected(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => _showCustomerSearch(context),
      icon: Icon(Icons.person_outline, size: 25, color: AppTheme.primaryColor),
      label: Text(
        currentCustomer?.name ?? 'Khách lẻ',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.textColor,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class CustomerSearchDialog extends StatefulWidget {
  final FirestoreService firestoreService;
  final String storeId;
  final CustomerModel? currentCustomer;

  const CustomerSearchDialog({
    super.key,
    required this.firestoreService,
    required this.storeId,
    this.currentCustomer,
  });

  @override
  State<CustomerSearchDialog> createState() => _CustomerSearchDialogState();
}

class _CustomerSearchDialogState extends State<CustomerSearchDialog> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  // Stream khởi tạo là luồng rỗng
  Stream<List<CustomerModel>>? _customerStream;

  @override
  void initState() {
    super.initState();

    // [FIX QUAN TRỌNG] Không load data ngay lúc đầu nữa
    // Để null hoặc Stream rỗng để giao diện đứng yên, không hiện loading
    _customerStream = null;

    _searchController.addListener(() {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          final keyword = _searchController.text.trim().toLowerCase();
          setState(() {
            if (keyword.isEmpty) {
              // Nếu xóa hết chữ thì quay về trạng thái rỗng, không load tất cả
              _customerStream = null;
            } else {
              // Chỉ tìm khi có chữ
              _customerStream = widget.firestoreService.searchCustomers(
                keyword,
                widget.storeId,
              );
            }
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ... (Giữ nguyên các hàm _addNewCustomer, _editCustomer cũ) ...
  Future<void> _addNewCustomer() async {
    final CustomerModel? newCustomer = await showDialog<CustomerModel>(
      context: context,
      builder: (_) => AddEditCustomerDialog(
        firestoreService: widget.firestoreService,
        storeId: widget.storeId,
      ),
    );
    if (newCustomer == null || !mounted) return;
    Navigator.of(context).pop(newCustomer);
  }

  Future<void> _editCustomer(CustomerModel customer) async {
    await showDialog<CustomerModel>(
      context: context,
      builder: (_) => AddEditCustomerDialog(
        firestoreService: widget.firestoreService,
        storeId: widget.storeId,
        customer: customer,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;
    final dialogWidth = isDesktop ? 550.0 : double.maxFinite;

    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 40.0 : 16.0,
          vertical: 24.0
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Tìm khách hàng'),
          IconButton(
            icon: Icon(Icons.person_add_alt_1,
                color: Theme.of(context).primaryColor),
            tooltip: 'Thêm mới',
            onPressed: _addNewCustomer,
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nhập tên hoặc SĐT...',
                prefixIcon: Icon(Icons.search),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 350,
              // [FIX UI] Hiển thị thông báo ban đầu thay vì Loading
              child: _customerStream == null
                  ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.keyboard_outlined, size: 48, color: Colors.grey),
                    SizedBox(height: 12),
                    Text('Tìm theo tên hoặc 3 số cuối SĐT của khách hàng.', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              )
                  : StreamBuilder<List<CustomerModel>>(
                stream: _customerStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Lỗi: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, size: 40, color: Colors.grey),
                          SizedBox(height: 8),
                          Text('Không tìm thấy kết quả nào.', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    );
                  }

                  final customers = snapshot.data!;
                  customers.sort((a, b) => a.name.compareTo(b.name));

                  return ListView.separated(
                    itemCount: customers.length,
                    separatorBuilder: (ctx, i) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final customer = customers[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                        leading: CircleAvatar(
                          backgroundColor: Colors.grey.shade200,
                          child: Icon(Icons.person, color: Colors.grey.shade600),
                        ),
                        title: Text(
                          customer.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(customer.phone, style: const TextStyle(fontSize: 14)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.monetization_on_outlined,
                                      size: 14, color: Colors.red),
                                  const SizedBox(width: 4),
                                  Text(
                                    NumberFormat('#,##0').format(customer.debt ?? 0),
                                    style: TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Icon(Icons.stars_rounded,
                                      size: 14, color: Colors.greenAccent),
                                  const SizedBox(width: 4),
                                  Text(
                                    NumberFormat('#,##0').format(customer.points),
                                    style: TextStyle(
                                        color: Colors.greenAccent,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14
                                    ),
                                  ),
                                ],
                              )
                            ],
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.blue),
                          onPressed: () => _editCustomer(customer),
                        ),
                        onTap: () => Navigator.of(context).pop(customer),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(
            'Bỏ chọn khách',
            style: TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }
}