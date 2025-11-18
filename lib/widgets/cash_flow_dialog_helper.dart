// lib/widgets/dialogs/cash_flow_dialog_helper.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:app_4cash/models/cash_flow_transaction_model.dart';
import 'package:app_4cash/models/user_model.dart';
import 'package:app_4cash/models/customer_model.dart';
import 'package:app_4cash/models/supplier_model.dart';
import 'package:app_4cash/services/toast_service.dart';
import 'package:app_4cash/theme/number_utils.dart';
import 'package:app_4cash/widgets/app_dropdown.dart';

class _DropdownItem {
  final String id;
  final String name;
  _DropdownItem({required this.id, required this.name});
}

class CashFlowDialogHelper {
  // Hàm tạo ID, chuyển thành public và static
  static Future<String> generateNextTransactionCode(
      String storeId, TransactionType type, DateTime date) async {
    final db = FirebaseFirestore.instance;
    final prefix = (type == TransactionType.revenue) ? 'PT' : 'PC';
    final dateString = DateFormat('yyMMdd').format(date);
    final idPrefix = '${storeId}_$prefix$dateString';

    final query = db
        .collection('manual_cash_transactions')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: idPrefix)
        .where(FieldPath.documentId, isLessThan: '$idPrefix\uf8ff')
        .orderBy(FieldPath.documentId, descending: true)
        .limit(1);

    final snapshot = await query.get();

    if (snapshot.docs.isEmpty) {
      return '${idPrefix}0001';
    }

    final lastId = snapshot.docs.first.id;
    final lastSeqStr = lastId.substring(idPrefix.length);
    final nextSeqInt = (int.tryParse(lastSeqStr) ?? 0) + 1;
    return '$idPrefix${nextSeqInt.toString().padLeft(4, '0')}';
  }

  // Hàm hiển thị Dialog chính
  static Future<bool> showAddTransactionDialog({
    required BuildContext context,
    required UserModel currentUser,
    required TransactionType type,
    CustomerModel? preSelectedCustomer,
    SupplierModel? preSelectedSupplier,
    bool isForDebtPayment = false, // Cờ kiểm soát
  }) async {
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    String paymentMethod = 'Tiền mặt';
    TransactionType transactionType = type;

    List<String> reasonOptions = [];
    bool isLoadingReasons = true;

    final reasonsCollection =
    FirebaseFirestore.instance.collection('cash_flow_reasons');

    bool isLoadingPartners = true;
    List<_DropdownItem> customerList = [];
    List<_DropdownItem> supplierList = [];

    _DropdownItem? selectedCustomer = preSelectedCustomer != null
        ? _DropdownItem(
        id: preSelectedCustomer.id, name: preSelectedCustomer.name)
        : null;

    _DropdownItem? selectedSupplier = preSelectedSupplier != null
        ? _DropdownItem(
        id: preSelectedSupplier.id, name: preSelectedSupplier.name)
        : null;

    String? selectedReason; // Khởi tạo là null
    if (isForDebtPayment) {
      // Chỉ set cứng lý do khi là thu/chi nợ
      selectedReason = (type == TransactionType.revenue)
          ? "Thu nợ bán hàng"
          : "Trả nợ nhập hàng";
    }

    bool isSuccess = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            type == TransactionType.revenue
                ? 'TẠO PHIẾU THU'
                : 'TẠO PHIẾU CHI',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> loadReasons() async {
                setDialogState(() => isLoadingReasons = true);
                try {
                  final snapshot = await reasonsCollection
                      .where('storeId', isEqualTo: currentUser.storeId)
                      .where('type', isEqualTo: transactionType.name)
                      .orderBy('name')
                      .get();
                  reasonOptions = snapshot.docs
                      .map((doc) => doc.data()['name'] as String)
                      .toList();

                  if (transactionType == TransactionType.revenue &&
                      !reasonOptions.contains("Thu nợ bán hàng")) {
                    reasonOptions.add("Thu nợ bán hàng");
                  }
                  if (transactionType == TransactionType.expense &&
                      !reasonOptions.contains("Trả nợ nhập hàng")) {
                    reasonOptions.add("Trả nợ nhập hàng");
                  }
                  reasonOptions = reasonOptions.toSet().toList()..sort();
                } catch (e) {
                  debugPrint("Lỗi tải nội dung: $e");
                }
                setDialogState(() {
                  isLoadingReasons = false;
                  if (selectedReason == null && !isForDebtPayment) {
                    selectedReason =
                    reasonOptions.isNotEmpty ? reasonOptions.first : null;
                  }
                });
              }

              Future<void> loadPartners() async {
                setDialogState(() => isLoadingPartners = true);
                try {
                  final db = FirebaseFirestore.instance;

                  if (isForDebtPayment) {
                    if (preSelectedCustomer != null) {
                      customerList = [_DropdownItem(
                          id: preSelectedCustomer.id,
                          name: preSelectedCustomer.name)];
                    }
                    if (preSelectedSupplier != null) {
                      supplierList = [_DropdownItem(
                          id: preSelectedSupplier.id,
                          name: preSelectedSupplier.name)];
                    }
                  } else {
                    if (transactionType == TransactionType.revenue) {
                      final customerSnap = await db
                          .collection('customers')
                          .where('storeId', isEqualTo: currentUser.storeId)
                          .orderBy('name')
                          .get();
                      customerList = customerSnap.docs
                          .map((doc) => _DropdownItem(
                          id: doc.id,
                          name: doc.data()['name'] ?? 'Lỗi tên'))
                          .toList();
                    } else {
                      final supplierSnap = await db
                          .collection('suppliers')
                          .where('storeId', isEqualTo: currentUser.storeId)
                          .orderBy('name')
                          .get();
                      supplierList = supplierSnap.docs
                          .map((doc) => _DropdownItem(
                          id: doc.id,
                          name: doc.data()['name'] ?? 'Lỗi tên'))
                          .toList();
                    }
                  }
                } catch (e) {
                  debugPrint("Lỗi tải KH/NCC: $e");
                }
                setDialogState(() => isLoadingPartners = false);
              }

              Future<void> addNewReason() async {
                final newReasonController = TextEditingController();
                final newReason = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("Thêm nội dung mới"),
                    content: TextField(
                      controller: newReasonController,
                      decoration: const InputDecoration(labelText: "Nội dung thu/chi"),
                      autofocus: true,
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Hủy")),
                      FilledButton(
                          onPressed: (){
                            if (ctx.mounted) {
                              Navigator.of(ctx).pop(newReasonController.text);
                            }
                          },
                          child: const Text("Lưu")),
                    ],
                  ),
                );

                if (newReason != null && newReason.isNotEmpty && ! reasonOptions.contains(newReason)) {
                  try {
                    await reasonsCollection.add({
                      'name': newReason,
                      'type': transactionType.name,
                      'storeId': currentUser.storeId
                    });
                    setDialogState(() {
                      reasonOptions.add(newReason);
                      reasonOptions.sort();
                      selectedReason = newReason;
                    });
                  } catch (e) {
                    ToastService().show(message: "Lỗi khi lưu: $e", type: ToastType.error);
                  }
                }
              }

              if (isLoadingReasons) loadReasons();
              if (isLoadingPartners) loadPartners();

              // --- ĐÂY LÀ CODE FORM HOÀN CHỈNH ---
              return Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- 1. LOẠI PHIẾU (CÓ KHÓA) ---
                      AbsorbPointer(
                        absorbing: isForDebtPayment,
                        child: AppDropdown<TransactionType>(
                          labelText: 'Loại phiếu *',
                          prefixIcon: Icons.article_outlined,
                          value: transactionType,
                          items: const [
                            DropdownMenuItem(
                                value: TransactionType.revenue,
                                child: Text('Phiếu Thu')),
                            DropdownMenuItem(
                                value: TransactionType.expense,
                                child: Text('Phiếu Chi')),
                          ],
                          onChanged: isForDebtPayment
                              ? null
                              : (val) {
                            if (val != null && val != transactionType) {
                              setDialogState(() {
                                transactionType = val;
                                selectedReason = null;
                                selectedCustomer = null;
                                selectedSupplier = null;
                                loadReasons();
                                loadPartners();
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      // --- 2. NỘI DUNG (CÓ KHÓA) ---
                      isLoadingReasons
                          ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(8.0),
                            child: CircularProgressIndicator(),
                          ))
                          : AbsorbPointer(
                        absorbing: isForDebtPayment,
                        child: AppDropdown<String>(
                          labelText: 'Nội dung *',
                          prefixIcon: Icons.subject_outlined,
                          value: reasonOptions.contains(selectedReason)
                              ? selectedReason
                              : null,
                          items: [
                            ...reasonOptions.map((reason) =>
                                DropdownMenuItem(
                                    value: reason, child: Text(reason))),
                            if (!isForDebtPayment)
                              const DropdownMenuItem<String>(
                                value: '_ADD_NEW_',
                                child: Text("+ Thêm nội dung mới..."),
                              ),
                          ],
                          onChanged: isForDebtPayment
                              ? null
                              : (val) {
                            if (val == '_ADD_NEW_') {
                              addNewReason();
                            } else {
                              setDialogState(
                                      () => selectedReason = val);
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      // --- 3. ĐỐI TÁC (KH/NCC) (CÓ KHÓA) ---
                      if (isLoadingPartners)
                        const Center(
                            child: Padding(
                              padding: EdgeInsets.all(8.0),
                              child: CircularProgressIndicator(),
                            ))
                      else if (transactionType == TransactionType.revenue)
                        AbsorbPointer(
                          absorbing: isForDebtPayment,
                          child: AppDropdown<String>(
                            labelText: 'Người nộp tiền',
                            prefixIcon: Icons.person_outline,
                            value: selectedCustomer?.id,
                            items: customerList
                                .map((customer) => DropdownMenuItem(
                                value: customer.id,
                                child: Text(customer.name)))
                                .toList(),
                            onChanged: isForDebtPayment
                                ? null
                                : (val) {
                              setDialogState(() => selectedCustomer =
                                  customerList.firstWhere(
                                          (c) => c.id == val,
                                      orElse: () =>
                                      customerList.first));
                            },
                          ),
                        )
                      else
                        AbsorbPointer(
                          absorbing: isForDebtPayment,
                          child: AppDropdown<String>(
                            labelText: 'Người nhận tiền',
                            prefixIcon: Icons.store_mall_directory_outlined,
                            value: selectedSupplier?.id,
                            items: supplierList
                                .map((supplier) => DropdownMenuItem(
                                value: supplier.id,
                                child: Text(supplier.name)))
                                .toList(),
                            onChanged: isForDebtPayment
                                ? null
                                : (val) {
                              setDialogState(() => selectedSupplier =
                                  supplierList.firstWhere(
                                          (s) => s.id == val,
                                      orElse: () =>
                                      supplierList.first));
                            },
                          ),
                        ),
                      const SizedBox(height: 16),

                      // --- 4. THỜI GIAN (KHÔNG KHÓA) ---
                      TextFormField(
                        readOnly: true,
                        controller: TextEditingController(
                            text: DateFormat('dd/MM/yyyy HH:mm')
                                .format(selectedDate)),
                        decoration: InputDecoration(
                          labelText: 'Thời gian',
                          prefixIcon: const Icon(Icons.calendar_today),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onTap: () async {
                          final pickedDate = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2101),
                          );
                          if (pickedDate != null && context.mounted) {
                            final pickedTime = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(selectedDate),
                            );
                            if (pickedTime != null) {
                              setDialogState(() {
                                selectedDate = DateTime(
                                  pickedDate.year,
                                  pickedDate.month,
                                  pickedDate.day,
                                  pickedTime.hour,
                                  pickedTime.minute,
                                );
                              });
                            }
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      // --- 5. GIÁ TRỊ (KHÔNG KHÓA) ---
                      TextFormField(
                        controller: amountController,
                        decoration: InputDecoration(
                          labelText: 'Giá trị *',
                          prefixIcon: const Icon(Icons.attach_money),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          ThousandDecimalInputFormatter(),
                        ],
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Vui lòng nhập số tiền';
                          }
                          if (parseVN(value) <= 0) {
                            return 'Số tiền phải lớn hơn 0';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // --- 6. HÌNH THỨC THANH TOÁN (KHÔNG KHÓA) ---
                      AppDropdown<String>(
                        labelText: 'Hình thức thanh toán',
                        prefixIcon: Icons.payment_outlined,
                        value: paymentMethod,
                        items: const [
                          DropdownMenuItem(
                              value: 'Tiền mặt', child: Text('Tiền mặt')),
                          DropdownMenuItem(
                              value: 'Chuyển khoản',
                              child: Text('Chuyển khoản')),
                          DropdownMenuItem(value: 'Thẻ', child: Text('Thẻ')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              paymentMethod = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      // --- 7. GHI CHÚ (KHÔNG KHÓA) ---
                      TextFormField(
                        controller: noteController,
                        decoration: InputDecoration(
                          labelText: 'Ghi chú (không bắt buộc)',
                          prefixIcon: const Icon(Icons.edit_note),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () async {
                if (formKey.currentState!.validate() && selectedReason != null) {

                  if (selectedReason == "Thu nợ bán hàng" &&
                      selectedCustomer == null) {
                    ToastService().show(
                        message: 'Vui lòng chọn khách hàng để thu nợ',
                        type: ToastType.warning);
                    return;
                  }

                  if (selectedReason == "Trả nợ nhập hàng" &&
                      selectedSupplier == null) {
                    ToastService().show(
                        message: 'Vui lòng chọn NCC để trả nợ',
                        type: ToastType.warning);
                    return;
                  }

                  try {
                    final db = FirebaseFirestore.instance;
                    final batch = db.batch();

                    final newId = await generateNextTransactionCode(
                        currentUser.storeId,
                        transactionType,
                        selectedDate);
                    final double amountToUpdate =
                    parseVN(amountController.text);

                    final newTransaction = CashFlowTransaction(
                      id: newId,
                      type: transactionType,
                      date: selectedDate,
                      user: currentUser.name ?? 'N/A',
                      amount: amountToUpdate,
                      paymentMethod: paymentMethod,
                      reason: selectedReason!,
                      note: noteController.text.trim(),
                      storeId: currentUser.storeId,
                      userId: currentUser.uid,
                      customerId: selectedCustomer?.id,
                      customerName: selectedCustomer?.name,
                      supplierId: selectedSupplier?.id,
                      supplierName: selectedSupplier?.name,
                    );

                    final newTransactionRef =
                    db.collection('manual_cash_transactions').doc(newId);
                    batch.set(newTransactionRef, newTransaction.toMap());

                    if (transactionType == TransactionType.revenue &&
                        selectedReason == "Thu nợ bán hàng" &&
                        selectedCustomer != null) {
                      final customerRef =
                      db.collection('customers').doc(selectedCustomer!.id);
                      batch.update(customerRef, {
                        'debt': FieldValue.increment(-amountToUpdate),
                      });
                    } else if (transactionType == TransactionType.expense &&
                        selectedReason == "Trả nợ nhập hàng" &&
                        selectedSupplier != null) {
                      final supplierRef =
                      db.collection('suppliers').doc(selectedSupplier!.id);
                      batch.update(supplierRef, {
                        'debt': FieldValue.increment(-amountToUpdate),
                      });
                    }

                    await batch.commit();

                    if (!context.mounted) return;
                    isSuccess = true;
                    Navigator.of(context).pop();
                    ToastService().show(
                        message: 'Tạo phiếu thành công',
                        type: ToastType.success);
                  } catch (e) {
                    ToastService().show(
                        message: 'Lỗi khi lưu phiếu: $e',
                        type: ToastType.error);
                  }
                } else if (selectedReason == null) {
                  ToastService().show(
                      message: 'Vui lòng chọn nội dung thu chi',
                      type: ToastType.warning);
                }
              },
              child: const Text('Lưu'),
            ),
          ],
        );
      },
    );

    return isSuccess;
  }
}