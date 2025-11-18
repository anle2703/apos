// lib/widgets/supplier_search_dialog.dart

import 'package:flutter/material.dart';
import 'dart:async';
import '../models/supplier_model.dart';
import '../services/supplier_service.dart';
import '../theme/app_theme.dart';
import '../screens/contacts/add_edit_supplier_dialog.dart';

class SupplierSearchDialog extends StatefulWidget {
  final String storeId;

  const SupplierSearchDialog({
    super.key,
    required this.storeId,
  });

  @override
  State<SupplierSearchDialog> createState() => _SupplierSearchDialogState();
}

class _SupplierSearchDialogState extends State<SupplierSearchDialog> {
  final _searchController = TextEditingController();
  final _supplierService = SupplierService();
  late Stream<List<SupplierModel>> _suppliersStream;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _suppliersStream = _supplierService.searchSuppliersStream('', widget.storeId);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _suppliersStream = _supplierService.searchSuppliersStream(
              _searchController.text, widget.storeId);
        });
      }
    });
  }


  Future<void> _addNewSupplier() async {
    final newSupplier = await showDialog<dynamic>(
      context: context,
      builder: (dialogContext) => AddEditSupplierDialog(
        storeId: widget.storeId,
        returnModelOnSuccess: true,
      ),
    );
    if (newSupplier != null && newSupplier is SupplierModel && mounted) {
      Navigator.of(context).pop(newSupplier);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Chọn nhà cung cấp'),
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_outlined, color: AppTheme.primaryColor),
            tooltip: 'Thêm mới NCC',
            onPressed: _addNewSupplier,
          ),
        ],
      ),
      content: SizedBox(
        width: 500, // Giữ kích thước cố định
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Tìm theo tên hoặc SĐT...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<List<SupplierModel>>(
                stream: _suppliersStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Lỗi: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(child: Text('Không tìm thấy nhà cung cấp.'));
                  }
                  final suppliers = snapshot.data!;
                  return ListView.builder(
                    itemCount: suppliers.length,
                    itemBuilder: (context, index) {
                      final supplier = suppliers[index];
                      return Card(
                        child: ListTile(
                          title: Text(supplier.name, style: AppTheme.boldTextStyle),
                          subtitle: Text(supplier.phone),
                          // Khi nhấn vào, trả về SupplierModel (đã chứa thông tin debt mới nhất)
                          onTap: () => Navigator.of(context).pop(supplier),
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
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}