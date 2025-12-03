import 'package:app_4cash/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/payment_method_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/toast_service.dart';
import '../../widgets/app_dropdown.dart';
import '../../widgets/custom_text_form_field.dart';
import 'package:app_4cash/widgets/bank_list.dart';
import '../../services/settings_service.dart';
import '../../models/store_settings_model.dart';
import 'package:app_4cash/screens/sales/payment_screen.dart';

extension PaymentMethodTypeExtension on PaymentMethodType {
  String get vietnameseName {
    switch (this) {
      case PaymentMethodType.cash:
        return 'Tiền mặt';
      case PaymentMethodType.bank:
        return 'Chuyển khoản';
      case PaymentMethodType.card:
        return 'Thẻ (POS)';
      case PaymentMethodType.other:
        return 'Khác';
    }
  }
}

class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key, required this.currentUser});
  final UserModel currentUser;

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  // Thêm SettingsService
  final SettingsService _settingsService = SettingsService();

  Future<void> _setDefaultPaymentMethod(String methodId, bool isCurrentlyDefault) async {
    try {
      final dynamic newDefaultId = isCurrentlyDefault ? null : methodId;

      // 1. Cập nhật Settings trên Firestore
      await _settingsService.updateStoreSettings(
          widget.currentUser.ownerUid ?? widget.currentUser.uid,
          {'defaultPaymentMethodId': newDefaultId}
      );

      // 2. [QUAN TRỌNG] Xóa cache bên màn hình thanh toán
      // Để lần sau mở PaymentScreen lên, nó buộc phải tải lại Settings mới nhất
      PaymentScreen.clearCache();
      final ownerUid = widget.currentUser.ownerUid ?? widget.currentUser.uid;
      PaymentScreen.preloadData(widget.currentUser.storeId, ownerUid);
      // 3. Nếu bạn đã thêm hàm preloadData, hãy gọi luôn để nạp cache mới (Optional nhưng tốt hơn)
      // await PaymentScreen.preloadData(widget.currentUser.storeId);

      ToastService().show(
          message: isCurrentlyDefault ? "Đã gỡ PTTT mặc định" : "Đã đặt làm PTTT mặc định",
          type: ToastType.success
      );
    } catch (e) {
      ToastService().show(message: "Lỗi khi cập nhật: $e", type: ToastType.error);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phương thức Thanh toán'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: AppTheme.primaryColor, size: 30),
            onPressed: () => _showMethodForm(),
            tooltip: 'Thêm PTTT mới',
          ),
        ],
      ),
      body: StreamBuilder<StoreSettings>(
        // Giả sử storeId là ID để lấy settings
        stream: _settingsService.watchStoreSettings(widget.currentUser.ownerUid ?? widget.currentUser.uid),
        builder: (context, settingsSnapshot) {
          if (!settingsSnapshot.hasData && settingsSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // Lấy ID mặc định, có thể là null
          final defaultMethodId = settingsSnapshot.data?.defaultPaymentMethodId;

          // StreamBuilder gốc cho PTTT
          return StreamBuilder<QuerySnapshot>(
            stream: _firestoreService.getPaymentMethods(widget.currentUser.storeId),
            builder: (context, methodSnapshot) {
              if (methodSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (methodSnapshot.hasError) {
                return Center(child: Text('Lỗi: ${methodSnapshot.error}'));
              }
              if (!methodSnapshot.hasData || methodSnapshot.data!.docs.isEmpty) {
                return const Center(
                    child: Text('Chưa có phương thức thanh toán nào.'));
              }

              final methods = methodSnapshot.data!.docs
                  .map((doc) => PaymentMethodModel.fromFirestore(doc))
                  .where((method) => method.type != PaymentMethodType.cash)
                  .toList();

              if (methods.isEmpty) {
                return const Center(
                    child: Text('Chưa có PTTT nào (ngoài Tiền mặt).'));
              }

              return ListView.builder(
                padding: const EdgeInsets.only(top: 6),
                itemCount: methods.length,
                itemBuilder: (context, index) {
                  final method = methods[index];
                  // Kiểm tra xem PTTT này có phải là mặc định không
                  final bool isDefault = (method.id == defaultMethodId);

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ListTile(
                      leading: Icon(_getIconForMethodType(method.type)),
                      title: Text(method.name),
                      subtitle: Text(_getSubtitle(method)),
                      // --- SỬA: Thêm nút ngôi sao vào trailing ---
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              isDefault ? Icons.star : Icons.star_border,
                              color: isDefault ? Colors.amber : Colors.grey,
                            ),
                            onPressed: () => _setDefaultPaymentMethod(method.id, isDefault),
                            tooltip: isDefault ? 'Gỡ làm mặc định' : 'Đặt làm mặc định',
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: () => _showMethodForm(method: method),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      // --- KẾT THÚC SỬA ---
    );
  }

  String _getSubtitle(PaymentMethodModel method) {
    if (method.type == PaymentMethodType.bank) {
      final bankName = vietnameseBanks.firstWhere(
            (b) => b.bin == method.bankBin,
        orElse: () => BankInfo(name: '', shortName: 'Không rõ', bin: ''),
      ).shortName;
      return '$bankName - ${method.bankAccount ?? ''}';
    }
    return method.type.vietnameseName;
  }

  IconData _getIconForMethodType(PaymentMethodType type) {
    switch (type) {
      case PaymentMethodType.cash:
        return Icons.money;
      case PaymentMethodType.bank:
        return Icons.account_balance;
      case PaymentMethodType.card:
        return Icons.credit_card;
      case PaymentMethodType.other:
        return Icons.payment;
    }
  }

  void _showMethodForm({PaymentMethodModel? method}) {
    final formKey = GlobalKey<_PaymentMethodFormState>();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(method == null ? 'Thêm PTTT' : 'Sửa PTTT'),
              contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              content: SizedBox(
                width: 350,
                child: _PaymentMethodForm(
                  key: formKey,
                  currentUser: widget.currentUser,
                  method: method,
                  firestoreService: _firestoreService,
                  onStateChanged: (bool newIsLoading) {
                    setDialogState(() => isLoading = newIsLoading);
                  },
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () => formKey.currentState?.saveMethod(),
                  child: isLoading
                      ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : const Text('Lưu'),
                ),
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Hủy'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _PaymentMethodForm extends StatefulWidget {
  final UserModel currentUser;
  final PaymentMethodModel? method;
  final FirestoreService firestoreService;
  final void Function(bool isLoading)? onStateChanged;

  const _PaymentMethodForm({
    super.key,
    required this.currentUser,
    this.method,
    required this.firestoreService,
    this.onStateChanged,
  });

  @override
  State<_PaymentMethodForm> createState() => _PaymentMethodFormState();
}

class _PaymentMethodFormState extends State<_PaymentMethodForm> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _bankAccountController;
  late final TextEditingController _bankAccountNameController;

  late PaymentMethodType _type;
  String? _selectedBin;
  late bool _qrDisplayOnScreen;
  late bool _qrDisplayOnBill;
  late bool _qrDisplayOnProvisionalBill;

  @override
  void initState() {
    super.initState();
    final m = widget.method;
    _nameController = TextEditingController(text: m?.name ?? '');
    _bankAccountController = TextEditingController(text: m?.bankAccount ?? '');
    _bankAccountNameController =
        TextEditingController(text: m?.bankAccountName ?? '');

    _type = m?.type ?? PaymentMethodType.bank;
    _selectedBin = m?.bankBin;

    _qrDisplayOnScreen = m?.qrDisplayOnScreen ?? false;
    _qrDisplayOnBill = m?.qrDisplayOnBill ?? false;
    _qrDisplayOnProvisionalBill = m?.qrDisplayOnProvisionalBill ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bankAccountController.dispose();
    _bankAccountNameController.dispose();
    super.dispose();
  }

  Future<void> saveMethod() async {
    if (!_formKey.currentState!.validate()) return;

    if (_type == PaymentMethodType.bank && _selectedBin == null) {
      ToastService().show(message: 'Vui lòng chọn ngân hàng', type: ToastType.error);
      return;
    }

    widget.onStateChanged?.call(true);

    try {
      final newMethod = PaymentMethodModel(
        id: widget.method?.id ?? '',
        storeId: widget.currentUser.storeId,
        name: _nameController.text.trim(),
        type: _type,
        bankBin: _type == PaymentMethodType.bank ? _selectedBin : null,
        bankAccount: _type == PaymentMethodType.bank
            ? _bankAccountController.text.trim()
            : null,
        bankAccountName: _type == PaymentMethodType.bank
            ? _bankAccountNameController.text.trim()
            : null,
        qrDisplayOnScreen: _qrDisplayOnScreen,
        qrDisplayOnBill: _qrDisplayOnBill,
        qrDisplayOnProvisionalBill: _qrDisplayOnProvisionalBill,
      );

      if (widget.method == null) {
        await widget.firestoreService.addPaymentMethod(newMethod);
      } else {
        await widget.firestoreService.updatePaymentMethod(newMethod);
      }

      PaymentScreen.clearCache();
      final ownerUid = widget.currentUser.ownerUid ?? widget.currentUser.uid;
      PaymentScreen.preloadData(widget.currentUser.storeId, ownerUid);
      ToastService()
          .show(message: 'Đã lưu PTTT thành công', type: ToastType.success);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      ToastService().show(message: 'Lỗi khi lưu: $e', type: ToastType.error);
    } finally {
      if (mounted) widget.onStateChanged?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CustomTextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Tên PTTT',
                prefixIcon: Icon(Icons.text_fields_outlined),
              ),
              validator: (val) =>
              val == null || val.isEmpty ? 'Không được bỏ trống' : null,
            ),
            const SizedBox(height: 16),
            AppDropdown<PaymentMethodType>(
              labelText: 'Loại PTTT',
              value: _type,
              items: PaymentMethodType.values
                  .where((type) => type != PaymentMethodType.cash)
                  .map((type) => DropdownMenuItem(
                value: type,
                child: Text(type.vietnameseName),
              ))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _type = val);
              },
            ),
            if (_type == PaymentMethodType.bank) ...[
              const SizedBox(height: 16),
              AppDropdown<String>(
                labelText: 'Chọn ngân hàng',
                value: _selectedBin,
                items: vietnameseBanks
                    .map((bank) => DropdownMenuItem(
                  value: bank.bin,
                  child: Text(bank.shortName, overflow: TextOverflow.ellipsis,),
                ))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedBin = val);
                },
              ),

              const SizedBox(height: 16),
              CustomTextFormField(
                controller: _bankAccountController,
                decoration: const InputDecoration(
                  labelText: 'Số tài khoản',
                  prefixIcon: Icon(Icons.pin_outlined),
                ),
                keyboardType: TextInputType.number,
                validator: (val) => _type == PaymentMethodType.bank && (val == null || val.isEmpty)
                    ? 'Không được bỏ trống' : null,
              ),
              const SizedBox(height: 16),
              CustomTextFormField(
                controller: _bankAccountNameController,
                decoration: const InputDecoration(
                  labelText: 'Tên chủ TK (Không dấu)',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (val) => _type == PaymentMethodType.bank && (val == null || val.isEmpty)
                    ? 'Không được bỏ trống' : null,
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: SwitchListTile(
                  title: const Text('Hiện QR trên màn hình'),
                  value: _qrDisplayOnScreen,
                  onChanged: (val) => setState(() => _qrDisplayOnScreen = val),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: SwitchListTile(
                  title: const Text('In QR trên bill Tạm tính'),
                  value: _qrDisplayOnProvisionalBill,
                  onChanged: (val) =>
                      setState(() => _qrDisplayOnProvisionalBill = val),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: SwitchListTile(
                  title: const Text('In QR trên Hóa đơn'),
                  value: _qrDisplayOnBill,
                  onChanged: (val) => setState(() => _qrDisplayOnBill = val),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}