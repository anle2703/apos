import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:screenshot/screenshot.dart'; // Import Screenshot
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../models/user_model.dart';
import 'package:app_4cash/models/cash_flow_transaction_model.dart';
import 'package:app_4cash/models/bill_model.dart';
import 'package:app_4cash/models/purchase_order_model.dart';
import 'package:app_4cash/services/toast_service.dart';
import 'package:app_4cash/services/print_queue_service.dart';
import 'package:app_4cash/models/print_job_model.dart';
import 'package:app_4cash/services/cash_flow_service.dart';

// QUAN TRỌNG: Import Widget mẫu in mới
import '../widgets/cash_flow_ticket_widget.dart';

class CashFlowReceiptDialog extends StatefulWidget {
  final CashFlowTransaction transaction;
  final UserModel currentUser;
  final Map<String, String> storeInfo;

  const CashFlowReceiptDialog({
    super.key,
    required this.transaction,
    required this.currentUser,
    required this.storeInfo,
  });

  @override
  State<CashFlowReceiptDialog> createState() => _CashFlowReceiptDialogState();
}

class _CashFlowReceiptDialogState extends State<CashFlowReceiptDialog> {
  ImageProvider? _imageProvider;
  Uint8List? _pdfBytes;
  bool _isLoading = true;

  // Controller chụp ảnh
  final ScreenshotController _screenshotController = ScreenshotController();

  double? _openingDebt;
  double? _closingDebt;
  bool get _isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  void initState() {
    super.initState();
    _loadDataAndGenerateImage();
  }

  Future<void> _loadDataAndGenerateImage() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      // Bước 1: Tính toán dư nợ (Logic cũ)
      await _calculateDebtHistory();

      // Bước 2: Tạo Widget mẫu in để chụp
      final widgetToCapture = Container(
        color: Colors.white,
        child: CashFlowTicketWidget(
          storeInfo: widget.storeInfo,
          transaction: widget.transaction,
          userName: widget.currentUser.name ?? 'Unknown',
        ),
      );

      // Bước 3: Chụp ảnh Widget
      final Uint8List imageBytes = await _screenshotController.captureFromWidget(
        widgetToCapture,
        delay: const Duration(milliseconds: 50),
        pixelRatio: 2.5,
        targetSize: const Size(550, double.infinity),
      );

      // Bước 4: Bọc vào PDF để share/save
      final pdf = pw.Document();
      final image = pw.MemoryImage(imageBytes);
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat(80 * PdfPageFormat.mm, double.infinity, marginAll: 0),
        build: (ctx) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
      ));
      final pdfBytes = await pdf.save();

      if (mounted) {
        setState(() {
          _pdfBytes = pdfBytes;
          if (imageBytes.isNotEmpty) {
            _imageProvider = MemoryImage(imageBytes);
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        debugPrint("Lỗi khi tạo ảnh phiếu thu/chi: $e");
        ToastService().show(message: "Lỗi tạo ảnh: $e", type: ToastType.error);
      }
    }
  }

  // Logic tính nợ (Giữ nguyên như cũ vì không liên quan đến in ấn)
  Future<void> _calculateDebtHistory() async {
    final db = FirebaseFirestore.instance;
    final tx = widget.transaction;
    List<dynamic> allRawTransactions = [];
    double initialDebt = 0;

    try {
      if (tx.reason == "Thu nợ bán hàng" && tx.customerId != null) {
        final customer = await db.collection('customers').doc(tx.customerId).get();
        if (!customer.exists) return;
        initialDebt = (customer.data()?['debt'] as num?)?.toDouble() ?? 0.0;

        final billsSnap = await db
            .collection('bills')
            .where('storeId', isEqualTo: widget.currentUser.storeId)
            .where('customerId', isEqualTo: tx.customerId)
            .get();
        final bills = billsSnap.docs.map((doc) => BillModel.fromFirestore(doc)).toList();

        final manualTxsSnapshot = await db
            .collection('manual_cash_transactions')
            .where('storeId', isEqualTo: widget.currentUser.storeId)
            .where('customerId', isEqualTo: tx.customerId)
            .where('reason', isEqualTo: 'Thu nợ bán hàng')
            .where('type', isEqualTo: 'revenue')
            .get();
        final manualTxs = manualTxsSnapshot.docs
            .map((doc) => CashFlowTransaction.fromFirestore(doc))
            .toList();

        allRawTransactions = [...bills, ...manualTxs];
      } else if (tx.reason == "Trả nợ nhập hàng" && tx.supplierId != null) {
        final supplier = await db.collection('suppliers').doc(tx.supplierId).get();
        if (!supplier.exists) return;
        initialDebt = (supplier.data()?['debt'] as num?)?.toDouble() ?? 0.0;

        final poSnap = await db
            .collection('purchase_orders')
            .where('storeId', isEqualTo: widget.currentUser.storeId)
            .where('supplierId', isEqualTo: tx.supplierId)
            .get();
        final purchaseOrders = poSnap.docs.map((doc) => PurchaseOrderModel.fromFirestore(doc)).toList();

        final manualTxsSnapshot = await db
            .collection('manual_cash_transactions')
            .where('storeId', isEqualTo: widget.currentUser.storeId)
            .where('supplierId', isEqualTo: tx.supplierId)
            .where('reason', isEqualTo: 'Trả nợ nhập hàng')
            .where('type', isEqualTo: 'expense')
            .get();
        final manualTxs = manualTxsSnapshot.docs
            .map((doc) => CashFlowTransaction.fromFirestore(doc))
            .toList();

        allRawTransactions = [...purchaseOrders, ...manualTxs];
      } else {
        return;
      }

      allRawTransactions.sort((a, b) {
        final dateA = a is BillModel ? a.createdAt : (a is PurchaseOrderModel ? a.createdAt : (a as CashFlowTransaction).date);
        final dateB = b is BillModel ? b.createdAt : (b is PurchaseOrderModel ? b.createdAt : (b as CashFlowTransaction).date);
        return dateA.compareTo(dateB);
      });

      double currentDebt = initialDebt;

      for (int i = allRawTransactions.length - 1; i >= 0; i--) {
        final currentTx = allRawTransactions[i];
        final double closingDebt = currentDebt;
        double debtChange = 0;
        String currentTxId = '';

        if (currentTx is BillModel) {
          debtChange = currentTx.debtAmount;
          currentTxId = currentTx.id;
        } else if (currentTx is PurchaseOrderModel) {
          debtChange = currentTx.debtAmount;
          currentTxId = currentTx.id;
        } else if (currentTx is CashFlowTransaction) {
          debtChange = -currentTx.amount;
          currentTxId = currentTx.id;
        }

        final double openingDebt = closingDebt - debtChange;

        if (currentTxId == widget.transaction.id) {
          setState(() {
            _openingDebt = openingDebt;
            _closingDebt = closingDebt;
          });
          return;
        }
        currentDebt = openingDebt;
      }
    } catch (e) {
      debugPrint("Lỗi nghiêm trọng khi tính toán nợ: $e");
    }
  }

  Future<void> _handleCancel(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Xác nhận Hủy'),
          content: Text(
              'Bạn có chắc chắn muốn hủy ${widget.transaction.type == TransactionType.revenue ? 'phiếu thu' : 'phiếu chi'} này? Hành động này sẽ hoàn tác lại công nợ (nếu có) và không thể khôi phục.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Không'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            TextButton(
              child: const Text('HỦY PHIẾU',
                  style: TextStyle(color: Colors.red)),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      final cashFlowService = CashFlowService();
      await cashFlowService.cancelManualTransaction(
        widget.transaction,
        widget.currentUser.name ?? widget.currentUser.phoneNumber,
      );

      ToastService().show(
          message: "Phiếu đã được hủy và hoàn tác công nợ",
          type: ToastType.success);
      if (context.mounted) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint("LỖI KHI HỦY PHIẾU: $e");
      ToastService()
          .show(message: "Lỗi khi hủy phiếu: $e", type: ToastType.error);
    }
  }

  Future<void> _handleDelete(BuildContext context) async {
    if (widget.transaction.status != 'cancelled') {
      ToastService()
          .show(message: "Chỉ có thể xóa phiếu đã hủy", type: ToastType.warning);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Xác nhận Xóa'),
          content: const Text(
              'Bạn có chắc chắn muốn XÓA VĨNH VIỄN phiếu này? Thao tác này không thể khôi phục.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Không'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            TextButton(
              child: const Text('XÓA VĨNH VIỄN',
                  style: TextStyle(color: Colors.red)),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      final cashFlowService = CashFlowService();
      await cashFlowService.deleteManualTransaction(widget.transaction.id);

      ToastService()
          .show(message: "Đã xóa phiếu vĩnh viễn", type: ToastType.success);
      if (context.mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint("LỖI KHI XÓA PHIẾU: $e");
      ToastService()
          .show(message: "Lỗi khi xóa phiếu: $e", type: ToastType.error);
    }
  }

  Future<void> _reprintReceipt() async {
    final jobData = {
      'storeId': widget.currentUser.storeId,
      'storeInfo': widget.storeInfo,
      'transaction': widget.transaction.toMap(),
      'transactionId': widget.transaction.id,
      'openingDebt': _openingDebt,
      'closingDebt': _closingDebt,
    };

    await PrintQueueService().addJob(PrintJobType.cashFlow, jobData);
    ToastService()
        .show(message: "Đã gửi lại lệnh in", type: ToastType.success);
  }

  Future<void> _shareReceipt() async {
    if (_pdfBytes == null) return;
    final shortId = widget.transaction.id.split('_').last;
    await Printing.sharePdf(
        bytes: _pdfBytes!, filename: 'PhieuThuChi_$shortId.pdf');
  }

  Future<void> _savePdf() async {
    if (_pdfBytes == null) return;
    try {
      final shortId = widget.transaction.id.split('_').last;
      final String? filePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Lưu phiếu PDF',
        fileName: 'PhieuThuChi_$shortId.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (filePath != null) {
        final file = File(filePath);
        await file.writeAsBytes(_pdfBytes!);
        ToastService().show(
            message: "Đã lưu phiếu thành công!", type: ToastType.success);
      }
    } catch (e) {
      ToastService()
          .show(message: "Lỗi khi lưu file: $e", type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bool isCancelled = widget.transaction.status == 'cancelled';

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding:
      const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 380,
          maxHeight: screenHeight * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12.0)),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _imageProvider == null
                    ? const Center(child: Text("Lỗi tạo ảnh phiếu."))
                    : SingleChildScrollView(
                  child: Padding(
                    padding:
                    const EdgeInsets.symmetric(vertical: 20),
                    child: Image(image: _imageProvider!),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: 380,
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12.0)),
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (isCancelled)
                    TextButton(
                      onPressed: () => _handleDelete(context),
                      child: const Text("Xóa phiếu", style: TextStyle(color: Colors.red)),
                    )
                  else
                    TextButton(
                      onPressed: () => _handleCancel(context),
                      child: const Text("Hủy phiếu", style: TextStyle(color: Colors.red)),
                    ),

                  TextButton(
                    onPressed: _reprintReceipt,
                    child: const Text("In lại"),
                  ),
                  TextButton(
                    onPressed:
                    _pdfBytes == null ? null : (_isDesktop ? _savePdf : _shareReceipt),
                    child: Text(_isDesktop ? "Lưu PDF" : "Chia sẻ"),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("Đóng"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}