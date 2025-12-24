// File: lib/screens/sales/failed_jobs_sheet.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/print_job_model.dart';
import '../../services/print_queue_service.dart';
import '../../theme/app_theme.dart';
import '../../services/toast_service.dart';
import '../../models/order_item_model.dart';
import '../../models/product_model.dart';
import '../../services/firestore_service.dart';
import '../../theme/number_utils.dart';

class FailedJobsSheet extends StatefulWidget {
  const FailedJobsSheet({super.key});

  @override
  State<FailedJobsSheet> createState() => _FailedJobsSheetState();
}

class _FailedJobsSheetState extends State<FailedJobsSheet> {
  final Set<String> _loadingJobs = {};
  final printService = PrintQueueService();
  bool _isRetryingAll = false;

  // Thêm các biến và hàm để tải danh sách sản phẩm
  final _firestoreService = FirestoreService();
  List<ProductModel> _allProducts = [];
  bool _isLoadingProducts = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    // Hàm này sẽ tải tất cả sản phẩm một lần để dùng cho việc tra cứu
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoadingProducts = false);
      return;
    }
    // Lấy user profile để có storeId
    final userProfile = await _firestoreService.getUserProfile(user.uid);
    if (userProfile == null) {
      if (mounted) setState(() => _isLoadingProducts = false);
      return;
    }

    // Lắng nghe stream để dữ liệu sản phẩm luôn mới
    _firestoreService.getAllProductsStream(userProfile.storeId).listen((products) {
      if (mounted) {
        setState(() {
          _allProducts = products;
          _isLoadingProducts = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<PrintJob>>(
      valueListenable: printService.failedJobsNotifier,
      builder: (context, failedJobs, _) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          builder: (_, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Danh sách in lỗi (${failedJobs.length})', style: Theme.of(context).textTheme.titleLarge),
                        IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
                      ],
                    ),
                  ),
                  const Divider(
                    height: 1,
                    thickness: 0.5,
                    color: Colors.grey,
                  ),
                  if (failedJobs.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: _isRetryingAll
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.sync, size: 25),
                              label: const Text('In lại tất cả'),
                              onPressed: _isRetryingAll
                                  ? null
                                  : () async {
                                      setState(() => _isRetryingAll = true);
                                      final bool allSuccess = await printService.retryAllJobs();

                                      if (!allSuccess && mounted) {
                                        ToastService().show(
                                          message: 'Một vài lệnh in lại đã thất bại.',
                                          type: ToastType.warning,
                                        );
                                      }

                                      if (mounted) {
                                        setState(() => _isRetryingAll = false);
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.delete_sweep_outlined, size: 25),
                              label: const Text('Xóa tất cả'),
                              onPressed: () => printService.deleteAllJobs(),
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: failedJobs.isEmpty
                        ? const Center(child: Text('Đã xử lý hết lỗi.'))
                        : _isLoadingProducts
                            ? const Center(child: CircularProgressIndicator())
                            : ListView.builder(
                                controller: scrollController,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: failedJobs.length,
                                itemBuilder: (context, index) {
                                  final job = failedJobs[index];
                                  final isLoading = _loadingJobs.contains(job.id);
                                  return _buildJobCard(context, job, isLoading);
                                },
                              ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- THAY THẾ TOÀN BỘ HÀM NÀY ---
  Widget _buildJobCard(BuildContext context, PrintJob job, bool isLoading) {
    const Map<String, String> keysToLabels = {
      'cashier_printer': 'Thu ngân',
      'kitchen_printer_a': 'Máy in A',
      'kitchen_printer_b': 'Máy in B',
      'kitchen_printer_c': 'Máy in C',
      'kitchen_printer_d': 'Máy in D',
      'label_printer': 'Tem',
    };

    final String typeText;
    IconData typeIcon;
    switch (job.type) {
      case PrintJobType.kitchen:
        typeText = 'CHẾ BIẾN';
        typeIcon = Icons.notification_add;
        break;
      case PrintJobType.provisional:
        typeText = 'TẠM TÍNH';
        typeIcon = Icons.receipt_long_outlined;
        break;
      case PrintJobType.detailedProvisional:
        typeText = 'TẠM TÍNH';
        typeIcon = Icons.receipt_long_outlined;
        break;
      case PrintJobType.cancel:
        typeText = 'HỦY MÓN';
        typeIcon = Icons.notifications_off;
        break;
      case PrintJobType.receipt:
        typeText = 'HÓA ĐƠN';
        typeIcon = Icons.receipt;
        break;
      case PrintJobType.cashFlow:
        typeText = 'THU/CHI';
        typeIcon = Icons.paid_outlined;
        break;
      case PrintJobType.endOfDayReport:
        typeText = 'BÁO CÁO TỔNG KẾT';
        typeIcon = Icons.bar_chart_outlined;
        break;
      case PrintJobType.tableManagement:
        typeText = 'QUẢN LÝ BÀN';
        typeIcon = Icons.swap_horiz_outlined;
        break;
      case PrintJobType.label:
        typeText = 'IN TEM';
        typeIcon = Icons.label_outline;
        break;
    }

    final tableName = job.data['tableName'] ?? (job.type == PrintJobType.cashFlow ? "Sổ quỹ" : 'N/A');
    final timeText = DateFormat('HH:mm dd/MM/yy').format(job.createdAt);
    final errorText = job.data['error'] as String?;
    final targetPrinterRole = job.data['targetPrinterRole'] as String?;
    final printerFriendlyName = keysToLabels[targetPrinterRole];

    final List<OrderItem> items;
    if (job.type != PrintJobType.cashFlow && job.data['items'] != null) {
      final itemsList = (job.data['items'] as List?) ?? [];
      items = itemsList.map((i) => OrderItem.fromMap(i, allProducts: _allProducts)).toList();
    } else {
      items = [];
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.only(left: 8.0, right: 4.0),
          leading: Icon(typeIcon, color: AppTheme.primaryColor),
          title: Text(
            '$typeText - $tableName${printerFriendlyName != null ? ' ($printerFriendlyName)' : ''}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (errorText != null && errorText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2.0, bottom: 2.0),
                  child: Text(
                    errorText,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.red),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              Text(
                'Lúc: $timeText',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          trailing: isLoading
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.sync, color: Colors.blue, size: 25),
                      tooltip: 'In lại',
                      onPressed: () async {
                        setState(() => _loadingJobs.add(job.id));
                        final success = await printService.retryJob(job.id);
                        if (!success && mounted) {
                          ToastService().show(message: 'In lại thất bại!', type: ToastType.error);
                        }
                        if (mounted) {
                          setState(() => _loadingJobs.remove(job.id));
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.red,
                        size: 25,
                      ),
                      tooltip: 'Xóa',
                      onPressed: () => printService.deleteJob(job.id),
                    ),
                  ],
                ),
          children: [
            Container(
              color: Colors.grey.shade50,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: job.type == PrintJobType.cashFlow
                    ? [
                        Text(
                          'Người tạo: ${job.data['transaction']?['user'] ?? 'N/A'}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          'Nội dung: ${job.data['transaction']?['reason'] ?? 'N/A'}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          'Số tiền: ${formatNumber(job.data['transaction']?['amount'] ?? 0)} đ',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ]
                    : (items.isEmpty // Hiển thị chi tiết cho các phiếu khác
                        ? [const Text('Không có chi tiết món ăn.')]
                        : items.map((item) {
                            String quantityText;
                            if (job.type == PrintJobType.provisional) {
                              quantityText = NumberFormat('#,##0.##').format(item.quantity);
                            } else {
                              final double change = item.unsentChange;
                              final quantityToDisplay = change != 0 ? change : item.quantity;
                              quantityText = NumberFormat('+ #,##0.##;- #,##0.##').format(quantityToDisplay);
                            }
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                      child: Text(
                                    '• ${item.product.productName}',
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  )),
                                  Text(
                                    quantityText,
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            );
                          }).toList()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
