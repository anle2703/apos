// File: lib/screens/promotions/promotions_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/number_utils.dart';
import '../../services/toast_service.dart';
import 'package:app_4cash/models/voucher_model.dart';
import 'package:intl/intl.dart';
import '../../widgets/app_dropdown.dart';
import 'package:flutter/services.dart';
import '../../widgets/custom_text_form_field.dart';
import '../../models/discount_model.dart';
import 'discount_form_screen.dart';
import 'buy_x_get_y_form_screen.dart';
import '../sales/payment_screen.dart';

// --- WIDGET CHÍNH ---
class PromotionsScreen extends StatelessWidget {
  final UserModel currentUser;

  const PromotionsScreen({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Cài đặt Khuyến mãi"),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              _buildTab(icon: Icons.star_outline, text: "Tích Điểm"),
              _buildTab(icon: Icons.local_offer_outlined, text: "Giảm Giá"),
              _buildTab(icon: Icons.receipt_long_outlined, text: "Voucher"),
              _buildTab(
                  icon: Icons.card_giftcard_outlined, text: "Mua X Tặng Y"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            PointsSettingsTab(currentUser: currentUser),
            DiscountsTab(currentUser: currentUser),
            VouchersTab(currentUser: currentUser),
            BuyXGetYTab(currentUser: currentUser),
          ],
        ),
      ),
    );
  }

  Widget _buildTab({required IconData icon, required String text}) {
    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(text),
        ],
      ),
    );
  }
}

// --- TAB CÀI ĐẶT TÍCH ĐIỂM (Không thay đổi) ---
class PointsSettingsTab extends StatefulWidget {
  final UserModel currentUser;

  const PointsSettingsTab({super.key, required this.currentUser});

  @override
  State<PointsSettingsTab> createState() => _PointsSettingsTabState();
}

class _PointsSettingsTabState extends State<PointsSettingsTab> {
  late final TextEditingController _earnRateController;
  late final TextEditingController _redeemRateController;
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();
  bool _isLoading = true;
  bool _canSetupPromotions = false;

  @override
  void initState() {
    super.initState();
    _earnRateController = TextEditingController();
    _redeemRateController = TextEditingController();
    if (widget.currentUser.role == 'owner') {
      _canSetupPromotions = true;
    } else {
      _canSetupPromotions = widget.currentUser.permissions?['promotions']
              ?['canSetupPromotions'] ??
          false;
    }
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final settings = await _firestoreService
          .loadPointsSettings(widget.currentUser.storeId);
      if (mounted) {
        _earnRateController.text = formatNumber(settings['earnRate'] ?? 0.0);
        _redeemRateController.text =
            formatNumber(settings['redeemRate'] ?? 0.0);
      }
    } catch (e) {
      ToastService()
          .show(message: "Lỗi tải cài đặt: $e", type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _earnRateController.dispose();
    _redeemRateController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    if ((_formKey.currentState?.validate() ?? false) && !_isLoading) {
      setState(() => _isLoading = true);
      final focusScope = FocusScope.of(context);
      try {
        final earnValue = parseVN(_earnRateController.text);
        final redeemValue = parseVN(_redeemRateController.text);
        await _firestoreService.savePointsSettings(
          storeId: widget.currentUser.storeId,
          earnRate: earnValue,
          redeemRate: redeemValue,
        );
        ToastService().show(
            message: "Đã lưu cài đặt tích điểm thành công!",
            type: ToastType.success);
        focusScope.unfocus();
      } catch (e) {
        ToastService().show(message: "Lỗi khi lưu: $e", type: ToastType.error);
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Quy đổi điểm thưởng",
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              "Thiết lập quy tắc tích và tiêu điểm. Nhập 0 để tắt tính năng tương ứng.",
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Text("Tỷ lệ tích điểm",
                style: AppTheme.boldTextStyle.copyWith(fontSize: 16)),
            const SizedBox(height: 8),
            CustomTextFormField(
              controller: _earnRateController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [ThousandDecimalInputFormatter()],
              decoration: const InputDecoration(
                labelText: "Số tiền (VNĐ) để nhận 1 điểm",
                hintText: "Ví dụ: 10.000 (Nhập 0 để tắt)",
                suffixText: "VNĐ / 1 điểm",
              ),
              validator: (value) {
                // SỬA LỖI: Cho phép nhập 0, chỉ chặn số âm
                if (value != null && value.isNotEmpty && parseVN(value) < 0) {
                  return 'Giá trị không được là số âm';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            Text("Tỷ lệ sử dụng điểm",
                style: AppTheme.boldTextStyle.copyWith(fontSize: 16)),
            const SizedBox(height: 8),
            CustomTextFormField(
              controller: _redeemRateController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [ThousandDecimalInputFormatter()],
              decoration: const InputDecoration(
                labelText: "Giá trị (VNĐ) của 1 điểm",
                hintText: "Ví dụ: 1.000 (Nhập 0 để tắt)",
                suffixText: "VNĐ = 1 điểm",
              ),
              validator: (value) {
                // SỬA LỖI: Cho phép nhập 0, chỉ chặn số âm
                if (value != null && value.isNotEmpty && parseVN(value) < 0) {
                  return 'Giá trị không được là số âm';
                }
                return null;
              },
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save_outlined),
                label: const Text("Lưu Cài Đặt"),
                onPressed: () {
                  if (_isLoading) {
                    return;
                  }
                  if (_canSetupPromotions) {
                    _saveSettings();
                  } else {
                    ToastService().show(
                        message:
                            'Bạn chưa được cấp quyền sử dụng tính năng này.',
                        type: ToastType.warning);
                  }
                },
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- TAB VOUCHER (Đã cập nhật theo yêu cầu) ---
// --- TAB VOUCHER (Đã sửa lại: Lưu settings chung vào collection promotions) ---
class VouchersTab extends StatefulWidget {
  final UserModel currentUser;

  const VouchersTab({super.key, required this.currentUser});

  @override
  State<VouchersTab> createState() => _VouchersTabState();
}

class _VouchersTabState extends State<VouchersTab> {
  final _firestoreService = FirestoreService();
  bool _canSetupPromotions = false;

  @override
  void initState() {
    super.initState();
    if (widget.currentUser.role == 'owner') {
      _canSetupPromotions = true;
    } else {
      _canSetupPromotions = widget.currentUser.permissions?['promotions']
              ?['canSetupPromotions'] ??
          false;
    }
  }

  void _showAddEditVoucherDialog({VoucherModel? voucher}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddEditVoucherDialog(
        currentUser: widget.currentUser,
        voucher: voucher,
      ),
    );
  }

  // [HÀM MỚI] Cập nhật voucher mặc định vào document Settings trong collection promotions
  Future<void> _updateDefaultVoucher(String? newCode) async {
    // Tạo ID document cài đặt cố định theo storeId (VD: 4cash_PromoSettings)
    final String settingsDocId = '${widget.currentUser.storeId}_PromoSettings';

    final docRef = FirebaseFirestore.instance
        .collection('promotions') // Lưu chung vào root collection promotions
        .doc(settingsDocId);

    // Sử dụng set với merge: true để tạo mới nếu chưa có, hoặc cập nhật nếu đã có
    await docRef.set({
      'storeId': widget.currentUser.storeId,
      'defaultVoucherCode': newCode,
      'updatedAt': FieldValue.serverTimestamp(),
      'type': 'settings',
      // Đánh dấu đây là doc settings để phân biệt với voucher
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    final String settingsDocId = '${widget.currentUser.storeId}_PromoSettings';

    return Scaffold(
      // 1. [SỬA] Stream lắng nghe document Settings cụ thể trong collection promotions
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('promotions')
            .doc(settingsDocId)
            .snapshots(),
        builder: (context, settingsSnapshot) {
          String? currentDefaultCode;

          // Lấy mã voucher mặc định từ document settings
          if (settingsSnapshot.hasData && settingsSnapshot.data!.exists) {
            final data = settingsSnapshot.data!.data() as Map<String, dynamic>;
            currentDefaultCode = data['defaultVoucherCode'];
          }

          // 2. Stream Danh sách Voucher (Giữ nguyên)
          return StreamBuilder<List<VoucherModel>>(
            stream:
                _firestoreService.getVouchersStream(widget.currentUser.storeId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text("Lỗi: ${snapshot.error}"));
              }
              // Lọc bỏ các document không phải là voucher (ví dụ các doc settings)
              // Giả sử VoucherModel của bạn có logic fromMap xử lý an toàn hoặc query của bạn đã lọc theo type
              // Nếu getVouchersStream của bạn query `where('type', isEqualTo: 'voucher')` thì không cần lọc thêm.
              // Nếu query lấy tất cả, bạn cần lọc ở đây:
              final allDocs = snapshot.data ?? [];
              final vouchers = allDocs
                  .where((v) => v.code.isNotEmpty)
                  .toList(); // Ví dụ lọc đơn giản

              if (vouchers.isEmpty) {
                return const Center(child: Text("Chưa có voucher nào."));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: vouchers.length,
                itemBuilder: (context, index) {
                  final v = vouchers[index];

                  final valueString = v.isPercent
                      ? '${formatNumber(v.value)}%'
                      : '${formatNumber(v.value)} đ';
                  String subtitle = "Giảm $valueString";
                  final quantityUsed = v.quantityUsed ?? 0;

                  if (v.quantity != null) {
                    subtitle +=
                        " - Còn: ${v.quantity} - Đã dùng: $quantityUsed";
                  } else {
                    subtitle += " - Đã dùng: $quantityUsed";
                  }

                  if (v.startAt != null) {
                    subtitle +=
                        "\nBắt đầu: ${DateFormat('dd/MM/yy HH:mm').format(v.startAt!.toDate())}";
                  }
                  if (v.expiryAt != null) {
                    subtitle +=
                        " - HSD: ${DateFormat('dd/MM/yy HH:mm').format(v.expiryAt!.toDate())}";
                  }

                  final titleStyle =
                      Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: v.isActive ? Colors.green.shade700 : null,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          );

                  // Kiểm tra xem voucher này có phải là voucher mặc định không
                  final isDefault = currentDefaultCode == v.code;

                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        if (_canSetupPromotions) {
                          _showAddEditVoucherDialog(voucher: v);
                        } else {
                          ToastService().show(
                              message:
                                  'Bạn chưa được cấp quyền sử dụng tính năng này.',
                              type: ToastType.warning);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 12.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.confirmation_number_outlined,
                              color: v.isActive
                                  ? Colors.green.shade700
                                  : Colors.grey,
                              size: 32,
                            ),
                            const SizedBox(width: 16.0),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(v.code, style: titleStyle),
                                  const SizedBox(height: 4.0),
                                  Text(
                                    subtitle,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),

                            // --- NÚT NGÔI SAO ---
                            if (_canSetupPromotions && v.isActive)
                              IconButton(
                                icon: Icon(
                                  isDefault ? Icons.star : Icons.star_border,
                                  color:
                                      isDefault ? Colors.orange : Colors.grey,
                                  size: 30,
                                ),
                                tooltip: isDefault
                                    ? "Hủy mặc định"
                                    : "Đặt làm mặc định",
                                onPressed: () async {
                                  final newCode = isDefault ? null : v.code;

                                  // 1. Gọi hàm update vào collection promotions
                                  await _updateDefaultVoucher(newCode);

                                  // 2. [THÊM MỚI] Xóa Cache của màn hình thanh toán ngay lập tức
                                  // Để lần sau mở Payment lên nó sẽ tải lại cài đặt mới nhất
                                  PaymentScreen.clearCache();

                                  if (mounted) {
                                    ToastService().show(
                                        message: isDefault
                                            ? "Đã hủy voucher mặc định"
                                            : "Đã đặt ${v.code} làm voucher mặc định",
                                        type: ToastType.success);
                                  }
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: _canSetupPromotions
          ? FloatingActionButton.extended(
              onPressed: () => _showAddEditVoucherDialog(),
              icon: const Icon(Icons.add),
              label: const Text("Tạo Voucher"),
              backgroundColor: AppTheme.primaryColor,
            )
          : null,
    );
  }
}

class _AddEditVoucherDialog extends StatefulWidget {
  final UserModel currentUser;
  final VoucherModel? voucher;

  const _AddEditVoucherDialog({required this.currentUser, this.voucher});

  @override
  State<_AddEditVoucherDialog> createState() => _AddEditVoucherDialogState();
}

class _AddEditVoucherDialogState extends State<_AddEditVoucherDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _codeController;
  late TextEditingController _valueController;
  late TextEditingController _quantityController;

  // <<< THÊM VÀO: CONTROLLER CHO START DATE & TIME >>>
  late TextEditingController _startDateController;
  late TextEditingController _expiryDateController;

  bool _isPercent = false;
  bool _isActive = true;

  // <<< THÊM VÀO: BIẾN LƯU START DATE & TIME >>>
  DateTime? _selectedStartDate;
  DateTime? _selectedExpiryDate;

  bool get _isEditMode => widget.voucher != null;

  @override
  void initState() {
    super.initState();
    final v = widget.voucher;
    _codeController = TextEditingController(text: v?.code ?? '');
    _valueController =
        TextEditingController(text: v != null ? formatNumber(v.value) : '');
    _quantityController = TextEditingController(
        text: v?.quantity != null ? v!.quantity.toString() : '');

    // <<< THÊM VÀO: KHỞI TẠO START DATE & TIME >>>
    if (v?.startAt != null) {
      _selectedStartDate = v!.startAt!.toDate();
      _startDateController = TextEditingController(
          text: DateFormat('dd/MM/yyyy HH:mm').format(_selectedStartDate!));
    } else {
      _startDateController = TextEditingController();
    }

    if (v?.expiryAt != null) {
      _selectedExpiryDate = v!.expiryAt!.toDate();
      _expiryDateController = TextEditingController(
          text: DateFormat('dd/MM/yyyy HH:mm').format(_selectedExpiryDate!));
    } else {
      _expiryDateController = TextEditingController();
    }

    _isPercent = v?.isPercent ?? false;
    _isActive = v?.isActive ?? true;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _valueController.dispose();
    _quantityController.dispose();
    _startDateController.dispose(); // <<< THÊM VÀO
    _expiryDateController.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedStartDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (pickedDate == null) return;

    // --- SỬA LỖI ---
    // 1. Kiểm tra xem widget (và context) có còn tồn tại không
    if (!context.mounted) return;

    // 2. Lưu context vào biến mới để "tắt" cảnh báo
    final BuildContext safeContext = context;

    final pickedTime = await showTimePicker(
      context: safeContext, // Dùng biến an toàn
      initialTime: TimeOfDay.fromDateTime(_selectedStartDate ?? DateTime.now()),
    );
    if (pickedTime == null) return;

    setState(() {
      _selectedStartDate = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
      _startDateController.text =
          DateFormat('dd/MM/yyyy HH:mm').format(_selectedStartDate!);
    });
  }

  Future<void> _pickExpiryDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedExpiryDate ?? _selectedStartDate ?? DateTime.now(),
      firstDate: _selectedStartDate ?? DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (pickedDate == null) return;
    if (!context.mounted) return;
    final BuildContext safeContext = context;

    final pickedTime = await showTimePicker(
      context: safeContext,
      initialTime:
          TimeOfDay.fromDateTime(_selectedExpiryDate ?? DateTime.now()),
    );
    if (pickedTime == null) return;

    setState(() {
      _selectedExpiryDate = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
      _expiryDateController.text =
          DateFormat('dd/MM/yyyy HH:mm').format(_selectedExpiryDate!);
    });
  }

  Future<void> _saveVoucher() async {
    if (!_formKey.currentState!.validate()) return;

    // <<< THÊM VÀO: KIỂM TRA NGÀY HỢP LỆ >>>
    if (_selectedStartDate != null &&
        _selectedExpiryDate != null &&
        _selectedStartDate!.isAfter(_selectedExpiryDate!)) {
      ToastService().show(
          message: "Ngày bắt đầu không được sau ngày kết thúc.",
          type: ToastType.error);
      return;
    }

    final data = {
      'storeId': widget.currentUser.storeId,
      'code': _codeController.text.trim().toUpperCase(),
      'value': parseVN(_valueController.text),
      'isPercent': _isPercent,
      'isActive': _isActive,
      'quantity': _quantityController.text.isNotEmpty
          ? int.tryParse(_quantityController.text)
          : null,
      'startAt': _selectedStartDate != null
          ? Timestamp.fromDate(_selectedStartDate!)
          : null, // <<< THÊM VÀO
      'expiryAt': _selectedExpiryDate != null
          ? Timestamp.fromDate(_selectedExpiryDate!)
          : null,
    };

    try {
      if (_isEditMode) {
        await FirestoreService().updateVoucher(widget.voucher!.id, data);
      } else {
        await FirestoreService().addVoucher(data);
      }
      ToastService()
          .show(message: "Lưu voucher thành công!", type: ToastType.success);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      ToastService().show(message: "Lỗi: $e", type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditMode ? "Sửa Voucher" : "Tạo Voucher Mới"),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomTextFormField(
                controller: _codeController,
                decoration: const InputDecoration(
                    labelText: "Mã voucher",
                    prefixIcon: Icon(Icons.confirmation_number_outlined)),
                textCapitalization: TextCapitalization.characters,
                validator: (v) =>
                    (v?.isEmpty ?? true) ? "Không được để trống" : null,
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: CustomTextFormField(
                      controller: _valueController,
                      decoration: const InputDecoration(
                          labelText: "Giá trị",
                          prefixIcon: Icon(Icons.attach_money)),
                      keyboardType: TextInputType.number,
                      inputFormatters: [ThousandDecimalInputFormatter()],
                      validator: (v) =>
                          (v?.isEmpty ?? true) ? "Không được để trống" : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 120,
                    child: AppDropdown<bool>(
                      labelText: "Loại",
                      value: _isPercent,
                      items: const [
                        DropdownMenuItem(value: false, child: Text("VNĐ")),
                        DropdownMenuItem(value: true, child: Text("%")),
                      ],
                      onChanged: (val) =>
                          setState(() => _isPercent = val ?? false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              CustomTextFormField(
                controller: _quantityController,
                decoration: const InputDecoration(
                  labelText: "Số lượng",
                  hintText: "Bỏ trống nếu không giới hạn",
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 16),

              // <<< THÊM VÀO: INPUT CHO START & EXPIRY DATE >>>
              CustomTextFormField(
                controller: _startDateController,
                readOnly: true,
                onTap: _pickStartDate,
                decoration: const InputDecoration(
                  labelText: "Bắt đầu",
                  hintText: "Bỏ trống nếu áp dụng ngay",
                  prefixIcon: Icon(Icons.play_arrow_outlined),
                ),
              ),
              const SizedBox(height: 16),
              CustomTextFormField(
                controller: _expiryDateController,
                readOnly: true,
                onTap: _pickExpiryDate,
                decoration: const InputDecoration(
                  labelText: "Thời hạn",
                  hintText: "Bỏ trống nếu vô hạn",
                  prefixIcon: Icon(Icons.timer_off_outlined),
                ),
              ),

              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text("Kích hoạt"),
                value: _isActive,
                onChanged: (val) => setState(() => _isActive = val),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Hủy")),
        ElevatedButton(onPressed: _saveVoucher, child: const Text("Lưu")),
      ],
    );
  }
}

// --- TAB GIẢM GIÁ ---
class DiscountsTab extends StatefulWidget {
  final UserModel currentUser;

  const DiscountsTab({super.key, required this.currentUser});

  @override
  State<DiscountsTab> createState() => _DiscountsTabState();
}

class _DiscountsTabState extends State<DiscountsTab> {
  final _firestoreService = FirestoreService();
  bool _canSetupPromotions = false;

  @override
  void initState() {
    super.initState();
    // Kiểm tra quyền
    if (widget.currentUser.role == 'owner') {
      _canSetupPromotions = true;
    } else {
      _canSetupPromotions = widget.currentUser.permissions?['promotions']
              ?['canSetupPromotions'] ??
          false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<DiscountModel>>(
        stream:
            _firestoreService.getDiscountsStream(widget.currentUser.storeId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            debugPrint(snapshot.error.toString());
            return Center(child: Text("Lỗi: ${snapshot.error}"));
          }

          final discounts = snapshot.data ?? [];
          if (discounts.isEmpty) {
            return const Center(
                child: Text("Chưa có chương trình giảm giá nào."));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: discounts.length,
            itemBuilder: (context, index) {
              final discount = discounts[index];

              // Xử lý hiển thị text thời gian
              String timeStr = "Chưa thiết lập thời gian";
              if (discount.startAt != null && discount.endAt != null) {
                timeStr =
                    "${DateFormat('dd/MM').format(discount.startAt!)} - ${DateFormat('dd/MM').format(discount.endAt!)}";
              } else if (discount.type == 'weekly') {
                timeStr =
                    "Hàng tuần (${discount.daysOfWeek?.length ?? 0} ngày)";
              } else if (discount.type == 'daily') {
                timeStr = "Hàng ngày";
              }

              // Xử lý hiển thị text đối tượng
              String targetStr = "Tất cả khách";
              if (discount.targetType == 'retail') targetStr = "Khách lẻ";
              if (discount.targetType == 'group') targetStr = discount.targetGroupName ?? "Nhóm khách hàng";

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: discount.isActive
                        ? AppTheme.primaryColor.withAlpha(25)
                        : Colors.grey.shade200,
                    child: Icon(Icons.price_change,
                        color: discount.isActive
                            ? AppTheme.primaryColor
                            : Colors.grey),
                  ),
                  title: Text(discount.name,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("${discount.items.length} sản phẩm - $targetStr",
                          style: TextStyle(fontSize: 16)),
                      Text(timeStr,
                          style: TextStyle(
                              fontSize: 16, color: Colors.grey.shade600)),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    if (_canSetupPromotions) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => DiscountFormScreen(
                            currentUser: widget.currentUser,
                            discount: discount,
                          ),
                        ),
                      );
                    } else {
                      ToastService().show(
                          message: 'Bạn không có quyền chỉnh sửa.',
                          type: ToastType.warning);
                    }
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: _canSetupPromotions
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) =>
                        DiscountFormScreen(currentUser: widget.currentUser),
                  ),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text("Tạo Giảm Giá"),
              backgroundColor: AppTheme.primaryColor,
            )
          : null,
    );
  }
}

// --- TAB DANH SÁCH MUA X TẶNG Y ---
// --- [THÊM MỚI] TAB DANH SÁCH MUA X TẶNG Y ---
class BuyXGetYTab extends StatefulWidget {
  final UserModel currentUser;

  const BuyXGetYTab({super.key, required this.currentUser});

  @override
  State<BuyXGetYTab> createState() => _BuyXGetYTabState();
}

class _BuyXGetYTabState extends State<BuyXGetYTab> {
  final _firestoreService = FirestoreService();
  bool _canSetupPromotions = false;

  @override
  void initState() {
    super.initState();
    // Kiểm tra quyền
    if (widget.currentUser.role == 'owner') {
      _canSetupPromotions = true;
    } else {
      _canSetupPromotions = widget.currentUser.permissions?['promotions']
              ?['canSetupPromotions'] ??
          false;
    }
  }

  // Hàm mở form (Thêm mới hoặc Sửa)
  void _openForm({Map<String, dynamic>? item}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => BuyXGetYFormScreen(
          currentUser: widget.currentUser,
          initialData: item, // Nếu item null -> Thêm mới, Ngược lại -> Sửa
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Stream lấy danh sách chương trình
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _firestoreService.getBuyXGetYStream(widget.currentUser.storeId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            // --- [THÊM ĐOẠN NÀY ĐỂ IN LINK INDEX] ---
            debugPrint(
                "======================================================================");
            debugPrint(
                ">>> [CẦN TẠO INDEX] Bấm vào link bên dưới để tạo index cho Mua X Tặng Y:");
            debugPrint(snapshot.error.toString());
            debugPrint(
                "======================================================================");
            // ----------------------------------------
            return Center(child: Text("Lỗi: ${snapshot.error}"));
          }

          final promotions = snapshot.data ?? [];
          if (promotions.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.card_giftcard, size: 60, color: Colors.grey),
                  SizedBox(height: 16),
                  Text("Chưa có chương trình Mua X Tặng Y nào."),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: promotions.length,
            itemBuilder: (context, index) {
              final promo = promotions[index];

              // Lấy thông tin hiển thị
              final String name = promo['name'] ?? 'Không tên';
              final bool isActive = promo['isActive'] ?? true;

              final String buyName = promo['buyProductName'] ?? '...';

              final num rawBuyQty = promo['buyQuantity'] ?? 1;
              final num rawGiftQty = promo['giftQuantity'] ?? 1;

              final String buyQtyStr = formatNumber(rawBuyQty.toDouble());
              final String giftQtyStr = formatNumber(rawGiftQty.toDouble());

              final String giftName = promo['giftProductName'] ?? '...';

              // Hiển thị thời gian ngắn gọn
              String timeStr = "Cụ thể";
              if (promo['timeType'] == 'daily') {
                timeStr = "Hàng ngày";
              } else if (promo['timeType'] == 'weekly') {
                timeStr = "Hàng tuần";
              } else if (promo['startAt'] != null && promo['endAt'] != null) {
                timeStr =
                    "${DateFormat('dd/MM').format((promo['startAt'] as Timestamp).toDate())} - ${DateFormat('dd/MM').format((promo['endAt'] as Timestamp).toDate())}";
              }

              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    if (_canSetupPromotions) {
                      _openForm(item: promo);
                    } else {
                      ToastService().show(
                          message: 'Bạn không có quyền chỉnh sửa.',
                          type: ToastType.warning);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        // Icon trạng thái
                        CircleAvatar(
                          backgroundColor: isActive
                              ? Colors.orange.withAlpha(30)
                              : Colors.grey.shade200,
                          child: Icon(Icons.local_mall_outlined,
                              color: isActive ? Colors.orange : Colors.grey),
                        ),
                        const SizedBox(width: 16),
                        // Nội dung chính
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.black)),
                              const SizedBox(height: 4),
                              RichText(
                                text: TextSpan(
                                  style: DefaultTextStyle.of(context).style,
                                  children: [
                                    const TextSpan(text: "Mua "),
                                    // [SỬA] Dùng biến String đã format
                                    TextSpan(
                                        text: "$buyQtyStr $buyName",
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold)),
                                    const TextSpan(text: " tặng "),
                                    // [SỬA] Dùng biến String đã format
                                    TextSpan(
                                        text: "$giftQtyStr $giftName",
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.access_time,
                                      size: 16, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Text(timeStr,
                                      style: const TextStyle(
                                          fontSize: 16, color: Colors.grey)),
                                ],
                              )
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      // Nút Thêm Mới
      floatingActionButton: _canSetupPromotions
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(), // Gọi form với null data (Tạo mới)
              icon: const Icon(Icons.add),
              label: const Text("Tạo Mới"),
              backgroundColor: AppTheme.primaryColor,
            )
          : null,
    );
  }
}
