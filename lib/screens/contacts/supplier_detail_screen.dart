// lib/screens/contacts/supplier_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:app_4cash/models/purchase_order_model.dart';
import 'package:app_4cash/models/supplier_model.dart';
import 'package:app_4cash/models/user_model.dart';
import 'package:app_4cash/services/supplier_service.dart';
import 'package:app_4cash/services/toast_service.dart';
import 'package:app_4cash/theme/app_theme.dart';
import 'package:app_4cash/theme/number_utils.dart';
import 'package:app_4cash/products/order/purchase_orders_list_screen.dart';
import 'add_edit_supplier_dialog.dart';
import 'package:app_4cash/models/cash_flow_transaction_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/cash_flow_dialog_helper.dart';
import 'package:app_4cash/services/firestore_service.dart';
import 'package:app_4cash/widgets/cash_flow_receipt_dialog.dart';

class SupplierTransaction {
  final dynamic transaction;
  final double openingDebt;
  final double closingDebt;
  final DateTime createdAt;

  SupplierTransaction({
    required this.transaction,
    required this.openingDebt,
    required this.closingDebt,
    required this.createdAt,
  });
}

class SupplierDetailScreen extends StatefulWidget {
  final String supplierId;
  final UserModel currentUser;

  const SupplierDetailScreen({
    super.key,
    required this.supplierId,
    required this.currentUser,
  });

  @override
  State<SupplierDetailScreen> createState() => _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends State<SupplierDetailScreen> {
  final SupplierService _supplierService = SupplierService();
  SupplierModel? _supplier;
  List<SupplierTransaction> _transactions = [];
  bool _isLoading = true;
  Map<String, String>? _storeInfo;

  @override
  void initState() {
    super.initState();
    _loadAllData();
    _loadStoreInfo();
  }

  Future<void> _loadStoreInfo() async {
    _storeInfo = await FirestoreService().getStoreDetails(widget.currentUser.storeId);
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      final supplier = await _supplierService.getSupplierById(widget.supplierId);
      if (supplier != null) {
        // 1. Lấy phiếu nhập hàng
        final purchaseOrders = await _supplierService.getPurchaseOrdersBySupplier(widget.supplierId);

        // 2. Lấy phiếu chi trả nợ thủ công
        final manualTxsSnapshot = await FirebaseFirestore.instance
            .collection('manual_cash_transactions')
            .where('storeId', isEqualTo: widget.currentUser.storeId)
            .where('supplierId', isEqualTo: widget.supplierId)
            .where('reason', isEqualTo: 'Trả nợ nhập hàng')
            .where('type', isEqualTo: 'expense')
            .get();

        final manualTxs = manualTxsSnapshot.docs
            .map((doc) => CashFlowTransaction.fromFirestore(doc))
            .toList();

        // 3. Gộp và Sắp xếp
        List<dynamic> allRawTransactions = [...purchaseOrders, ...manualTxs];
        allRawTransactions.sort((a, b) {
          // Sửa logic sắp xếp
          final dateA = a is PurchaseOrderModel ? a.createdAt : (a as CashFlowTransaction).date;
          final dateB = b is PurchaseOrderModel ? b.createdAt : (b as CashFlowTransaction).date;
          return dateA.compareTo(dateB); // Sắp xếp tăng dần
        });

        // 4. Tính toán
        _calculateTransactionHistory(supplier, allRawTransactions);

        setState(() {
          _supplier = supplier;
        });
      }
    } catch (e) {
      ToastService().show(message: "Lỗi tải dữ liệu: $e", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _calculateTransactionHistory(SupplierModel supplier, List<dynamic> rawTransactions) {
    final List<SupplierTransaction> calculatedTransactions = [];
    double currentDebt = supplier.debt;

    for (int i = rawTransactions.length - 1; i >= 0; i--) {
      final tx = rawTransactions[i];
      final double closingDebt = currentDebt;
      double debtChange = 0;
      DateTime createdAt = DateTime.now();

      // --- SỬA LOGIC IF ---
      if (tx is PurchaseOrderModel) {
        // Phiếu nhập hàng -> Tăng nợ (debtAmount > 0)
        debtChange = tx.debtAmount;
        createdAt = tx.createdAt;
      } else if (tx is CashFlowTransaction) {
        // Phiếu chi trả nợ -> Giảm nợ
        debtChange = -tx.amount; // tx.amount là số dương
        createdAt = tx.date;
      }
      // --- KẾT THÚC SỬA ---

      final double openingDebt = closingDebt - debtChange;

      calculatedTransactions.add(SupplierTransaction(
        transaction: tx,
        openingDebt: openingDebt,
        closingDebt: closingDebt,
        createdAt: createdAt,
      ));

      currentDebt = openingDebt;
    }

    _transactions = calculatedTransactions;
  }

  Future<void> _showEditSupplierDialog() async {
    if (_supplier == null) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddEditSupplierDialog(
        supplier: _supplier,
        storeId: widget.currentUser.storeId,
      ),
    );
    _loadAllData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_supplier?.name ?? 'Chi tiết NCC'),
        actions: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outlined, color: AppTheme.primaryColor, size: 30),
            tooltip: 'Tạo phiếu chi trả nợ',
            onPressed: _supplier == null ? null : () async {
              final bool success = await CashFlowDialogHelper.showAddTransactionDialog(
                context: context,
                currentUser: widget.currentUser,
                type: TransactionType.expense,
                preSelectedSupplier: _supplier,
                isForDebtPayment: true,
              );
              if (success && mounted) {
                _loadAllData();
              }
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: AppTheme.primaryColor, size: 30,),
            onPressed: _supplier == null ? null : _showEditSupplierDialog,
            tooltip: 'Chỉnh sửa thông tin',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _supplier == null
          ? const Center(child: Text('Không tìm thấy nhà cung cấp.'))
          : RefreshIndicator(
        onRefresh: _loadAllData,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _buildSupplierInfoCard(),
            const SizedBox(height: 24),
            const Text('Lịch sử giao dịch', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildTransactionList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSupplierInfoCard() {
    final double totalPurchase = _transactions
        .where((t) => t.transaction is PurchaseOrderModel)
        .fold(0.0, (tong, t) => tong + (t.transaction as PurchaseOrderModel).totalAmount);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow(Icons.phone_outlined, _supplier!.phone),
            if (_supplier!.supplierGroupName != null && _supplier!.supplierGroupName!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildInfoRow(Icons.groups_outlined, _supplier!.supplierGroupName!),
            ],
            if (_supplier!.address != null && _supplier!.address!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildInfoRow(Icons.location_on_outlined, _supplier!.address!),
            ],
            if (_supplier!.taxCode != null && _supplier!.taxCode!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildInfoRow(Icons.receipt_long_outlined, 'MST: ${_supplier!.taxCode!}'),
            ],
            const SizedBox(height: 4),
            const Divider(height: 8, thickness: 1, color: Colors.grey),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStat('Tổng mua', totalPurchase, Colors.green),
                _buildStat('Dư nợ', _supplier!.debt, Colors.red),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: Colors.black, size: 20),
        const SizedBox(width: 16),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black))),
      ],
    );
  }

  Widget _buildStat(String label, num? value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          '${NumberFormat('#,##0', 'vi_VN').format(value ?? 0)} đ',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  Widget _buildTransactionList() {
    if (_transactions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32.0),
        child: Center(child: Text('Chưa có giao dịch nào.')),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _transactions.length,
      itemBuilder: (context, index) {
        final supplierTx = _transactions[index];

        // --- SỬA LOGIC IF ---
        if (supplierTx.transaction is PurchaseOrderModel) {
          return _buildPurchaseOrderCard(supplierTx);
        } else if (supplierTx.transaction is CashFlowTransaction) {
          return _buildManualTxCard(supplierTx); // Hàm mới
        }
        return const SizedBox.shrink();
        // --- KẾT THÚC SỬA ---
      },
    );
  }

  Widget _buildManualTxCard(SupplierTransaction supplierTx) {
    final manualTx = supplierTx.transaction as CashFlowTransaction;

    final bool isCancelled = manualTx.status == 'cancelled';
    final Color color = isCancelled ? Colors.grey.shade600 : Colors.red;
    final String displayId = manualTx.id.split('_').last;
    final String displayedUser = isCancelled ? (manualTx.cancelledBy ?? 'Đã hủy') : manualTx.user;
    final IconData userIcon = isCancelled ? Icons.cancel_outlined : Icons.person_outline;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isCancelled ? Colors.grey.shade200 : null,
      child: InkWell(
        onTap: () {
          if (_storeInfo == null) {
            ToastService().show(message: "Đang tải dữ liệu cửa hàng...", type: ToastType.warning);
            return;
          }
          showDialog(
            context: context,
            builder: (_) => CashFlowReceiptDialog(
              transaction: manualTx,
              currentUser: widget.currentUser,
              storeInfo: _storeInfo!,
            ),
          ).then((_) {
            _loadAllData();
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- HÀNG 1: MÃ PHIẾU CHI / SỐ TIỀN HOẶC NÚT XÓA ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    displayId,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: color,
                      fontSize: 16,
                    ),
                  ),
                  isCancelled
                      ? Row(
                    children: [
                      Text(
                        'ĐÃ HỦY',
                        style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16),
                      ),
                    ],
                  )
                      : Text(
                    '${formatNumber(manualTx.amount)} đ',
                    style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // --- HÀNG 2: NGƯỜI TẠO / NGÀY GIỜ ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(userIcon, size: 16, color: Colors.black),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            displayedUser,
                            style: AppTheme.regularTextStyle.copyWith(
                              fontSize: 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    DateFormat('HH:mm dd/MM/yyyy').format(manualTx.date),
                    style: TextStyle(
                      color: isCancelled ? color : Colors.black,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const Divider(height: 8, thickness: 0.5, color: Colors.grey,),
              _buildDebtRow('Nợ đầu kỳ:', supplierTx.openingDebt, isCancelled: isCancelled),
              const SizedBox(height: 4),
              _buildDebtRow(
                  'Phát sinh:',
                  isCancelled ? 0 : -manualTx.amount,
                  isChange: true,
                  isCancelled: isCancelled
              ),
              const SizedBox(height: 4),
              _buildDebtRow('Nợ cuối kỳ:', supplierTx.closingDebt, isFinal: true, isCancelled: isCancelled),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPurchaseOrderCard(SupplierTransaction supplierTx) {
    final po = supplierTx.transaction as PurchaseOrderModel;

    final bool isEdited = po.updatedAt != null;
    final String personName = isEdited ? (po.updatedBy ?? 'Không rõ') : po.createdBy;
    final DateTime relevantDate = isEdited ? po.updatedAt! : po.createdAt;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => PurchaseOrdersListScreen(
              currentUser: widget.currentUser,
              initialPurchaseOrderId: po.id,
            ),
          ))
              .then((_) => _loadAllData());
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    po.code,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor, fontSize: 16),
                  ),
                  Text(
                    '${formatNumber(po.totalAmount)} đ',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(isEdited ? Icons.edit_note_outlined : Icons.person_outline, size: 20, color: Colors.black),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            personName,
                            style: AppTheme.regularTextStyle.copyWith(fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    DateFormat('HH:mm dd/MM/yyyy').format(relevantDate),
                    style: const TextStyle(color: Colors.black, fontSize: 16),
                  ),
                ],
              ),
              const Divider(height: 8, thickness: 0.5, color: Colors.grey,),
              _buildDebtRow('Nợ đầu kỳ:', supplierTx.openingDebt),
              const SizedBox(height: 4),
              _buildDebtRow('Phát sinh:', po.debtAmount, isChange: true),
              const SizedBox(height: 4),
              _buildDebtRow('Nợ cuối kỳ:', supplierTx.closingDebt, isFinal: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDebtRow(String label, double value, {bool isChange = false, bool isFinal = false, bool isCancelled = false}) {
    Color valueColor = Colors.black;
    String prefix = '';

    if (isChange && !isCancelled) { // Chỉ tô màu nếu chưa bị hủy
      if (value > 0) {
        valueColor = Colors.red; // Tăng nợ
        prefix = '+';
      } else if (value < 0) {
        valueColor = Colors.green; // Giảm nợ
      }
    } else if (isCancelled) {
      valueColor = Colors.grey.shade600;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
            label,
            style: TextStyle(
              color: isCancelled ? Colors.grey.shade600 : Colors.black,
              fontSize: 16,
            )
        ),
        Text(
          '$prefix${formatNumber(value)} đ',
          style: TextStyle(
            fontSize: 16,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}