// lib/screens/contacts/customer_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/bill_model.dart';
import '../../../models/customer_model.dart';
import '../../../models/user_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/toast_service.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/number_utils.dart';
import '../../../bills/bill_history_screen.dart';
import 'add_edit_customer_dialog.dart';
import '../../models/cash_flow_transaction_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/cash_flow_dialog_helper.dart';
import 'package:app_4cash/widgets/cash_flow_receipt_dialog.dart';

class CustomerTransaction {
  final dynamic transaction;
  final double openingDebt;
  final double closingDebt;
  final DateTime createdAt;

  CustomerTransaction({
    required this.transaction,
    required this.openingDebt,
    required this.closingDebt,
    required this.createdAt,
  });
}

class CustomerDetailScreen extends StatefulWidget {
  final String customerId;
  final UserModel currentUser;

  const CustomerDetailScreen(
      {super.key, required this.customerId, required this.currentUser});

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  CustomerModel? _customer;
  List<CustomerTransaction> _transactions = [];
  bool _isLoading = true;
  Map<String, String>? _storeInfo;
  bool _canEditContacts = false;
  bool _canThuChi = false;

  @override
  void initState() {
    super.initState();
    _loadAllData();
    _loadStoreInfo();
    if (widget.currentUser.role == 'owner') {
      _canEditContacts = true;
      _canThuChi = true;
    } else {
      _canEditContacts = widget.currentUser.permissions?['contacts']
      ?['canEditContacts'] ??
          false;
      _canThuChi = widget.currentUser.permissions?['contacts']
      ?['canThuChi'] ??
          false;
    }
  }

  Future<void> _loadStoreInfo() async {
    _storeInfo = await _firestoreService.getStoreDetails(widget.currentUser.storeId);
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final customer = await _firestoreService.getCustomerById(widget.customerId);
      if (customer != null) {
        // 1. Lấy hóa đơn bán hàng
        final billsRaw = await _firestoreService.getBillsByCustomer(widget.customerId);
        final bills = billsRaw.where((bill) => bill.status != 'cancelled').toList();

        // 2. Lấy phiếu thu nợ thủ công
        final manualTxsSnapshot = await FirebaseFirestore.instance
            .collection('manual_cash_transactions')
            .where('storeId', isEqualTo: widget.currentUser.storeId)
            .where('customerId', isEqualTo: widget.customerId)
            .where('reason', isEqualTo: 'Thu nợ bán hàng')
            .where('type', isEqualTo: 'revenue')
            .get();

        final manualTxs = manualTxsSnapshot.docs
            .map((doc) => CashFlowTransaction.fromFirestore(doc))
            .toList();

        // 3. Gộp và Sắp xếp
        List<dynamic> allRawTransactions = [...bills, ...manualTxs];
        allRawTransactions.sort((a, b) {
          final dateA = a is BillModel ? a.createdAt : (a as CashFlowTransaction).date;
          final dateB = b is BillModel ? b.createdAt : (b as CashFlowTransaction).date;
          return dateA.compareTo(dateB); // Sắp xếp tăng dần theo ngày
        });

        // 4. Tính toán
        _calculateTransactionHistory(customer, allRawTransactions);
        setState(() {
          _customer = customer;
        });
      }
    } catch (e) {
      ToastService().show(message: "Lỗi tải dữ liệu: $e", type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _calculateTransactionHistory(CustomerModel customer, List<dynamic> rawTransactions) {
    final List<CustomerTransaction> calculatedTransactions = [];
    double currentDebt = customer.debt ?? 0.0;
    for (int i = rawTransactions.length - 1; i >= 0; i--) {
      final tx = rawTransactions[i];
      final double closingDebt = currentDebt;
      double debtChange = 0;
      DateTime createdAt = DateTime.now();

      if (tx is BillModel) {
        debtChange = tx.debtAmount;
        createdAt = tx.createdAt;
      } else if (tx is CashFlowTransaction) {
        debtChange = -tx.amount;
        createdAt = tx.date;
      }

      final double openingDebt = closingDebt - debtChange;

      calculatedTransactions.add(CustomerTransaction(
        transaction: tx,
        openingDebt: openingDebt,
        closingDebt: closingDebt,
        createdAt: createdAt,
      ));

      currentDebt = openingDebt;
    }
    _transactions = calculatedTransactions;
  }

  Future<void> _showEditCustomerDialog() async {
    if (_customer == null) return;

    // 1. Thay đổi kiểu mong đợi từ Map<String, dynamic> sang dynamic (hoặc CustomerModel)
    final result = await showDialog<dynamic>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddEditCustomerDialog(
        firestoreService: _firestoreService,
        storeId: widget.currentUser.storeId,
        customer: _customer,
      ),
    );

    // 2. Xử lý kết quả trả về
    // Nếu result là CustomerModel nghĩa là Dialog đã lưu và update thành công
    if (result != null && result is CustomerModel) {
      ToastService().show(message: 'Cập nhật thành công!', type: ToastType.success);

      // 3. Tải lại dữ liệu để hiển thị thông tin mới nhất (nhóm mới, tên mới...)
      _loadAllData();
    }
    // Không cần gọi _firestoreService.updateCustomer ở đây nữa vì Dialog đã làm rồi.
  }

  Future<void> _showBillDetailDialog(BillModel bill) async {
    try {
      final storeInfo = await _firestoreService.getStoreDetails(widget.currentUser.storeId);
      if (mounted && storeInfo != null) {
        await showDialog(
          context: context,
          builder: (_) => BillReceiptDialog(
            bill: bill,
            currentUser: widget.currentUser,
            storeInfo: storeInfo,
          ),
        );
      } else {
        ToastService().show(message: "Không tìm thấy thông tin cửa hàng", type: ToastType.error);
      }
    } catch (e) {
      ToastService().show(message: "Lỗi khi mở hóa đơn: $e", type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_customer?.name ?? 'Chi tiết khách hàng'),
        actions: [
          if (_canThuChi)
          IconButton(
            icon: const Icon(Icons.add_circle_outlined, color: AppTheme.primaryColor, size: 30),
            tooltip: 'Tạo phiếu thu nợ',
            onPressed: _customer == null ? null : () async {
              // --- GỌI HÀM HELPER ---
              final bool success = await CashFlowDialogHelper.showAddTransactionDialog(
                context: context,
                currentUser: widget.currentUser,
                type: TransactionType.revenue,
                preSelectedCustomer: _customer,
                isForDebtPayment: true,
              );
              if (success && mounted) {
                _loadAllData();
              }
            },
          ),
          if (_canEditContacts) ...[
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: AppTheme.primaryColor, size: 30,),
            onPressed: _customer == null ? null : _showEditCustomerDialog,
            tooltip: 'Chỉnh sửa thông tin',
          ),
          const SizedBox(width: 8),],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _customer == null
          ? const Center(child: Text('Không tìm thấy khách hàng.'))
          : RefreshIndicator(
        onRefresh: _loadAllData,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _buildCustomerInfoCard(),
            const SizedBox(height: 24),
            const Text(
              'Lịch sử giao dịch',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildTransactionList(),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerInfoCard() {
    final double totalSpent = _customer?.totalSpent ?? 0.0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow(Icons.phone_outlined, _customer!.phone),
            if (_customer!.address != null && _customer!.address!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildInfoRow(Icons.location_on_outlined, _customer!.address!),
            ],
            if (_customer!.customerGroupName != null && _customer!.customerGroupName!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildInfoRow(Icons.groups_outlined, _customer!.customerGroupName!),
            ],
            if (_customer!.companyName != null && _customer!.companyName!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildInfoRow(Icons.business_center_outlined, _customer!.companyName!),
            ],
            if (_customer!.taxId != null && _customer!.taxId!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildInfoRow(Icons.receipt_long_outlined, 'MST: ${_customer!.taxId!}'),
            ],
            const SizedBox(height: 4),
            const Divider(height: 8, thickness: 1, color: Colors.grey),
            const SizedBox(height: 4),
            LayoutBuilder(
              builder: (context, constraints) {
                bool isMobile = constraints.maxWidth < 500;
                final statsWidgets = [
                  _buildStat('Tổng giao dịch', totalSpent, Colors.orange),
                  _buildStat('Dư nợ', _customer!.debt, Colors.red),
                  _buildStat('Điểm thưởng', _customer!.points.toDouble(), Colors.green),
                ];

                if (isMobile) {
                  return Column(
                    children: [
                      _buildMobileStatRow(
                        label: 'Tổng giao dịch:',
                        value: totalSpent,
                        color: Colors.orange,
                        isCurrency: true,
                      ),
                      const SizedBox(height: 12),
                      _buildMobileStatRow(
                        label: 'Dư nợ:',
                        value: _customer!.debt,
                        color: Colors.red,
                        isCurrency: true,
                      ),
                      const SizedBox(height: 12),
                      _buildMobileStatRow(
                        label: 'Điểm thưởng:',
                        value: _customer!.points.toDouble(),
                        color: Colors.green,
                        isCurrency: false,
                      ),
                    ],
                  );
                } else {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: statsWidgets,
                  );
                }
              },
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
        Expanded(child: Text(text, style: const TextStyle(fontSize: 16, color: Colors.black, fontWeight: FontWeight.bold))),
      ],
    );
  }

  Widget _buildMobileStatRow({
    required String label,
    required num? value,
    required Color color,
    bool isCurrency = false,
  }) {
    String formattedValue = NumberFormat('#,##0', 'vi_VN').format(value ?? 0);
    if (isCurrency) {
      formattedValue = '$formattedValue đ';
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.black, fontSize: 16),
        ),
        Text(
          formattedValue,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  Widget _buildStat(String label, num? value, Color color) {
    String formattedValue = NumberFormat('#,##0', 'vi_VN').format(value ?? 0);
    if (label == 'Tổng giao dịch' || label == 'Công nợ') {
      formattedValue = '$formattedValue đ';
    }

    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(
          formattedValue,
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
        final tx = _transactions[index];

        // Phân loại giao dịch để hiển thị thẻ tương ứng
        if (tx.transaction is BillModel) {
          return _buildBillCard(tx);
        } else if (tx.transaction is CashFlowTransaction) {
          return _buildManualTxCard(tx);
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildBillCard(CustomerTransaction tx) {
    final bill = tx.transaction as BillModel;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          _showBillDetailDialog(bill)
              .then((_) => _loadAllData());
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- HÀNG 1: MÃ HĐ / TỔNG TIỀN ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    bill.billCode,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor, fontSize: 16),
                  ),
                  Text(
                    '${formatNumber(bill.totalPayable)} đ',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 16),
                  ),
                ],
              ),
              // --- HÀNG 2: NGƯỜI TẠO / NGÀY GIỜ ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.person_outline, size: 16, color: Colors.black),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            bill.createdByName ?? 'Không rõ',
                            style: AppTheme.regularTextStyle.copyWith(fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    DateFormat('HH:mm dd/MM/yyyy').format(bill.createdAt),
                    style: const TextStyle(color: Colors.black, fontSize: 16),
                  ),
                ],
              ),
              // --- CÔNG NỢ ---
              const Divider(height: 2, thickness: 0.5, color: Colors.grey,),
              _buildDebtRow('Nợ đầu kỳ:', tx.openingDebt),
              _buildDebtRow('Phát sinh:', (tx.transaction as BillModel).debtAmount, isChange: true),
              _buildDebtRow('Nợ cuối kỳ:', tx.closingDebt, isFinal: true),

              // --- BỔ SUNG LẠI CODE HIỂN THỊ ĐIỂM ---
              if (bill.pointsEarned > 0 || bill.customerPointsUsed > 0) ...[
                const Divider(height: 2, thickness: 0.5, color: Colors.grey,),
                if (bill.pointsEarned > 0)
                  _buildPointsRow(
                      label: 'Điểm thưởng cộng:',
                      value: bill.pointsEarned,
                      color: Colors.green,
                      prefix: '+'
                  ),
                if (bill.customerPointsUsed > 0) ...[
                  SizedBox(height: bill.pointsEarned > 0 ? 4 : 0),
                  _buildPointsRow(
                      label: 'Điểm thưởng sử dụng:',
                      value: bill.customerPointsUsed,
                      color: Colors.red,
                      prefix: '-'
                  ),
                ]
              ],
              // --- KẾT THÚC BỔ SUNG ---
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManualTxCard(CustomerTransaction tx) {
    final manualTx = tx.transaction as CashFlowTransaction;

    final bool isCancelled = manualTx.status == 'cancelled';
    final Color color = isCancelled ? Colors.grey.shade600 : Colors.green;
    final String displayId = manualTx.id.split('_').last;
    final String displayedUser = isCancelled ? (manualTx.cancelledBy ?? 'Đã hủy') : manualTx.user;
    final IconData userIcon = isCancelled ? Icons.cancel_outlined: Icons.person_outline;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isCancelled ? Colors.grey.shade200 : null, // Nền xám
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
              // --- HÀNG 1: MÃ PHIẾU THU / SỐ TIỀN (ĐÃ SỬA) ---
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
                  // Yêu cầu: Hiển thị "ĐÃ HỦY"
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
              // --- HÀNG 2: NGƯỜI TẠO / NGÀY GIỜ (ĐÃ SỬA) ---
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
              const Divider(height: 2, thickness: 0.5, color: Colors.grey,),

              // --- CÔNG NỢ (ĐÃ SỬA) ---
              _buildDebtRow('Nợ đầu kỳ:', tx.openingDebt, isCancelled: isCancelled),
              _buildDebtRow(
                  'Phát sinh:',
                  isCancelled ? 0 : -manualTx.amount,
                  isChange: true,
                  isCancelled: isCancelled
              ),
              _buildDebtRow('Nợ cuối kỳ:', tx.closingDebt, isFinal: true, isCancelled: isCancelled),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPointsRow({required String label, required double value, required Color color, required String prefix}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.black, fontSize: 16)),
        Text(
          '$prefix${NumberFormat('#,##0').format(value)}',
          style: TextStyle(
            fontWeight: FontWeight.normal,
            color: color, fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _buildDebtRow(String label, double value, {bool isChange = false, bool isFinal = false, bool isCancelled = false}) {
    Color valueColor = Colors.black;
    String prefix = '';

    // Áp dụng gạch ngang nếu bị hủy
    if(isChange && !isCancelled) { // Chỉ tô màu nếu chưa bị hủy
      if (value > 0) {
        valueColor = Colors.red;
        prefix = '+';
      } else if (value < 0) {
        valueColor = Colors.green;
      }
    } else if (isCancelled) {
      valueColor = Colors.grey.shade600;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isCancelled ? Colors.grey.shade600 : Colors.black,
            )
        ),
        Text(
          '$prefix${formatNumber(value)} đ',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: valueColor,
          ),
        ),
      ],
    );
  }
}