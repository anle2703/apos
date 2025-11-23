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

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), () {
        if (mounted) setState(() {});
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }


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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
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
        width: 500,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nhập tên hoặc SĐT...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<List<CustomerModel>>(
                stream: widget.firestoreService.searchCustomers(
                    _searchController.text.trim().toLowerCase(),
                    widget.storeId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Lỗi: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(
                        child: Text('Không tìm thấy khách hàng.'));
                  }
                  final customers = snapshot.data!;
                  customers.sort((a, b) => a.name.compareTo(b.name));
                  return ListView.builder(
                    itemCount: customers.length,
                    itemBuilder: (context, index) {
                      final customer = customers[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: const Icon(Icons.person, color: Colors.grey),
                          title: Text(
                            customer.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.black),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                customer.phone,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Dư nợ: ${NumberFormat('#,##0').format(customer.debt ?? 0)}đ   •   Điểm thưởng: ${NumberFormat('#,##0').format(customer.points)}",
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                          onTap: () => Navigator.of(context).pop(customer),
                        ),
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
            'Xóa lựa chọn',
            style: TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }
}