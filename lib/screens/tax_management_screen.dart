import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/toast_service.dart';
import '../../widgets/app_dropdown.dart';
import '../../models/product_model.dart';
import '../widgets/product_search_delegate.dart';
import '../../theme/app_theme.dart';
import 'sales/payment_screen.dart';
// ===================================================================
// 1. BẢNG THUẾ CHO PHƯƠNG PHÁP KHẤU TRỪ (VAT - Deduction)
// ===================================================================
const Map<String, Map<String, dynamic>> kDeductionRates = {
  'VAT_0': {'name': '0% (Xuất khẩu/Không chịu thuế)', 'rate': 0.0},
  'VAT_5': {'name': '5% (Thực phẩm, Y tế, Giáo dục)', 'rate': 0.05},
  'VAT_8': {'name': '8% (Mức ưu đãi)', 'rate': 0.08},
  'VAT_10': {'name': '10% (Hàng hóa thông thường)', 'rate': 0.10},
};

// ===================================================================
// 2. BẢNG THUẾ CHO PHƯƠNG PHÁP TRỰC TIẾP (Direct)
// ===================================================================
const Map<String, Map<String, dynamic>> kDirectRates = {
  'HKD_0': {
    'name': '0% (Miễn thuế/Chưa gán)',
    'rate': 0.0,
    'desc': 'Không chịu thuế'
  },
  'HKD_RETAIL': {
    'name': '1.5% (Bán lẻ, Tạp hóa)',
    'rate': 0.015,
    'desc': '1% VAT + 0.5% TNCN'
  },
  'HKD_PRODUCTION': {
    'name': '4.5% (Sản xuất, Ăn uống, Vận tải)',
    'rate': 0.045,
    'desc': '3% VAT + 1.5% TNCN'
  },
  'HKD_SERVICE': {
    'name': '7% (Dịch vụ, Xây dựng)',
    'rate': 0.07,
    'desc': '5% VAT + 2% TNCN'
  },
  'HKD_LEASING': {
    'name': '10% (Cho thuê tài sản)',
    'rate': 0.10,
    'desc': '5% VAT + 5% TNCN'
  },
};

// --- ALIAS (ĐỂ TƯƠNG THÍCH CODE CŨ) ---
const kHkdGopRates = kDirectRates;
const kVatRates = kDeductionRates;

// --- BIẾN TỔNG HỢP (SỬA LỖI "Undefined name 'kAllTaxRates'") ---
const Map<String, Map<String, dynamic>> kAllTaxRates = {
  ...kDirectRates,
  ...kDeductionRates,
};

// Enum định nghĩa
enum LegalEntityType { hkd, dn }
enum TaxCalcMethod { direct, deduction }
enum RevenueRange { low, medium, high }

class TaxManagementScreen extends StatefulWidget {
  final UserModel currentUser;
  const TaxManagementScreen({super.key, required this.currentUser});

  @override
  State<TaxManagementScreen> createState() => _TaxManagementScreenState();
}

class _TaxManagementScreenState extends State<TaxManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cấu Hình & Kê Khai Thuế'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.settings), text: 'Cài Đặt Thuế'),
            Tab(icon: Icon(Icons.calculate), text: 'Báo Cáo Kê Khai'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          TaxSettingsTab(currentUser: widget.currentUser),
          TaxDeclarationTab(currentUser: widget.currentUser),
        ],
      ),
    );
  }
}

// ===================================================================
// TAB 1: CÀI ĐẶT THUẾ (LOGIC TỰ ĐỘNG)
// ===================================================================
class TaxSettingsTab extends StatefulWidget {
  final UserModel currentUser;
  const TaxSettingsTab({super.key, required this.currentUser});

  @override
  State<TaxSettingsTab> createState() => _TaxSettingsTabState();
}

class _TaxSettingsTabState extends State<TaxSettingsTab> {
  final FirestoreService _firestoreService = FirestoreService();
  final _formatter = NumberFormat.decimalPattern('vi_VN');

  // 1. Cấu hình từ Firestore
  double _threshold1 = 200000000;
  double _threshold2 = 3000000000;

  // 2. Trạng thái người dùng chọn
  LegalEntityType _entityType = LegalEntityType.hkd;
  RevenueRange _selectedRange = RevenueRange.medium;

  // 3. Trạng thái tính toán (Tự động)
  TaxCalcMethod _calcMethod = TaxCalcMethod.direct;

  // 4. Dữ liệu gán thuế
  Map<String, List<String>> _taxAssignmentMap = {};
  List<ProductModel> _allProducts = [];
  bool _isTaxInclusive = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      final thresholds = await _firestoreService.getTaxThresholds();
      _threshold1 = (thresholds['hkd_revenue_threshold_group1'] as num?)?.toDouble() ?? 200000000;
      _threshold2 = (thresholds['hkd_revenue_threshold_group2'] as num?)?.toDouble() ?? 3000000000;

      final results = await Future.wait([
        _firestoreService.getStoreTaxSettings(widget.currentUser.storeId),
        _firestoreService.getAllProductsStream(widget.currentUser.storeId).first,
      ]);

      final settings = results[0] as Map<String, dynamic>?;
      _allProducts = results[1] as List<ProductModel>;

      if (settings != null) {
        _entityType = (settings['entityType'] == 'dn')
            ? LegalEntityType.dn
            : LegalEntityType.hkd;

        final String rangeStr = settings['revenueRange'] ?? 'medium';
        if (rangeStr == 'low') {_selectedRange = RevenueRange.low;}
        else if (rangeStr == 'high') {_selectedRange = RevenueRange.high;}
        else {_selectedRange = RevenueRange.medium;}

        final String savedMethod = settings['calcMethod'] ?? 'direct';
        _calcMethod = (savedMethod == 'deduction')
            ? TaxCalcMethod.deduction
            : TaxCalcMethod.direct;
        _isTaxInclusive = settings['isTaxInclusive'] ?? false;
        final rawMap = settings['taxAssignmentMap'] as Map<String, dynamic>? ?? {};
        _taxAssignmentMap = {};
        rawMap.forEach((key, value) {
          if (value is List) _taxAssignmentMap[key] = List<String>.from(value);
        });
      } else {
        _calculateTaxMethod(forceClear: false);
      }
      _calculateTaxMethod(forceClear: false);

    } catch (e) {
      ToastService().show(message: "Lỗi tải dữ liệu: $e", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _calculateTaxMethod({bool forceClear = true}) {
    TaxCalcMethod newMethod;
    if (_entityType == LegalEntityType.dn) {
      newMethod = TaxCalcMethod.deduction;
    } else {
      if (_selectedRange == RevenueRange.high) {
        newMethod = TaxCalcMethod.deduction;
      } else {
        newMethod = TaxCalcMethod.direct;
      }
    }

    if (newMethod != _calcMethod && forceClear) {
      _taxAssignmentMap.clear();
    }

    setState(() {
      _calcMethod = newMethod;
    });
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);
    try {
      String rangeStr = 'medium';
      if (_selectedRange == RevenueRange.low) rangeStr = 'low';
      if (_selectedRange == RevenueRange.high) rangeStr = 'high';

      final settings = {
        'entityType': _entityType == LegalEntityType.dn ? 'dn' : 'hkd',
        'revenueRange': rangeStr,
        'calcMethod': _calcMethod == TaxCalcMethod.deduction ? 'deduction' : 'direct',
        'isTaxInclusive': _isTaxInclusive,
        'taxAssignmentMap': _taxAssignmentMap,
        'updatedAt': FieldValue.serverTimestamp(),
        'snapshot_threshold1': _threshold1,
        'snapshot_threshold2': _threshold2,
      };

      await _firestoreService.updateStoreTaxSettings(
          widget.currentUser.storeId, settings);

      PaymentScreen.clearCache();

      ToastService().show(message: "Đã lưu cấu hình thuế", type: ToastType.success);
    } catch (e) {
      ToastService().show(message: "Lỗi lưu: $e", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader("1. Thông tin mô hình kinh doanh"),
          _buildBusinessInfoCard(),

          const SizedBox(height: 24),
          _buildSectionHeader("2. Chế độ thuế áp dụng (Tự động)"),
          _buildAutoStatusCard(),

          const SizedBox(height: 24),
          _buildSectionHeader("3. Gán thuế cho sản phẩm"),
          _buildTaxAssignmentSection(),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          onPressed: _saveSettings,
          child: const Text("Lưu Cấu Hình"),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
    );
  }

  Widget _buildBusinessInfoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppDropdown<LegalEntityType>(
              labelText: "Mô hình kinh doanh",
              value: _entityType,
              items: const [
                DropdownMenuItem(value: LegalEntityType.hkd, child: Text("Hộ Kinh Doanh (Cá thể)")),
                DropdownMenuItem(value: LegalEntityType.dn, child: Text("Doanh Nghiệp (Công ty)")),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _entityType = val;
                    _calculateTaxMethod();
                  });
                }
              },
            ),

            if (_entityType == LegalEntityType.hkd) ...[
              const SizedBox(height: 16),
              AppDropdown<RevenueRange>(
                labelText: "Mức doanh thu ước tính / năm",
                value: _selectedRange,
                items: [
                  DropdownMenuItem(
                    value: RevenueRange.low,
                    child: Text("Dưới ${_formatter.format(_threshold1)} đ (Nhóm 1)"),
                  ),
                  DropdownMenuItem(
                    value: RevenueRange.medium,
                    child: Text("Từ ${_formatter.format(_threshold1)} - ${_formatter.format(_threshold2)} đ (Nhóm 2)"),
                  ),
                  DropdownMenuItem(
                    value: RevenueRange.high,
                    child: Text("Trên ${_formatter.format(_threshold2)} đ (Nhóm 3)"),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedRange = val;
                      _calculateTaxMethod();
                    });
                  }
                },
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: Colors.blueGrey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedRange == RevenueRange.low
                            ? "Bạn thuộc diện MIỄN LỆ PHÍ MÔN BÀI và MIỄN THUẾ GTGT, TNCN."
                            : _selectedRange == RevenueRange.medium
                            ? "Bạn nộp thuế khoán hoặc kê khai theo tỷ lệ % trên doanh thu."
                            : "Quy mô lớn: Bắt buộc thực hiện sổ sách và nộp thuế KHẤU TRỪ (giống Doanh nghiệp).",
                        style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.blueGrey),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Giá bán đã bao gồm thuế",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: const Text("Hệ thống sẽ tự động tách ngược tiền thuế từ giá bán sản phẩm khi thanh toán.",
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              value: _isTaxInclusive,
              onChanged: (val) {
                setState(() {
                  _isTaxInclusive = val;
                });
              },
              activeTrackColor: AppTheme.primaryColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoStatusCard() {
    Color color;
    String title;
    String desc;
    IconData icon;

    if (_entityType == LegalEntityType.hkd && _selectedRange == RevenueRange.low) {
      color = Colors.green;
      title = "ĐƯỢC MIỄN THUẾ";
      desc = "Doanh thu dưới ngưỡng quy định. Bạn không cần kê khai thuế.";
      icon = Icons.check_circle_outline;
    } else if (_calcMethod == TaxCalcMethod.deduction) {
      color = Colors.blue;
      title = "PHƯƠNG PHÁP KHẤU TRỪ (VAT)";
      desc = "Hệ thống HĐĐT sẽ gửi thuế suất 10%, 8%, 5%... và tính tiền thuế chi tiết.";
      icon = Icons.domain;
    } else {
      color = Colors.orange;
      title = "PHƯƠNG PHÁP TRỰC TIẾP (Tỷ lệ %)";
      desc = "Hệ thống HĐĐT sẽ gửi mã 'KCT' (Không chịu thuế GTGT). Tiền thuế được tính ngầm trong giá bán.";
      icon = Icons.storefront;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Text(desc, style: TextStyle(color: color.withAlpha(200), fontSize: 13)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTaxAssignmentSection() {
    if (_entityType == LegalEntityType.hkd && _selectedRange == RevenueRange.low) {
      return const Center(child: Text("Không cần cấu hình (Miễn thuế)", style: TextStyle(color: Colors.grey)));
    }

    final rateMap = _calcMethod == TaxCalcMethod.deduction ? kDeductionRates : kDirectRates;
    final title = _calcMethod == TaxCalcMethod.deduction
        ? "Phân loại thuế suất VAT (0% - 10%)"
        : "Phân nhóm ngành nghề (Tỷ lệ %)";

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            const Text("Vui lòng gán sản phẩm vào nhóm thuế tương ứng:", style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 16),
            ...rateMap.entries.map((entry) {
              final taxCode = entry.key;
              final taxInfo = entry.value;
              final assignedCount = (_taxAssignmentMap[taxCode] ?? []).length;

              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(taxInfo['name'], style: const TextStyle(fontWeight: FontWeight.w500)),
                subtitle: _calcMethod == TaxCalcMethod.direct
                    ? Text(taxInfo['desc'] ?? '', style: TextStyle(fontSize: 14, color: Colors.grey[600]))
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: assignedCount > 0 ? AppTheme.primaryColor.withAlpha(25) : Colors.grey[100],
                          borderRadius: BorderRadius.circular(4)
                      ),
                      child: Text("$assignedCount SP",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14,
                              color: assignedCount > 0 ? AppTheme.primaryColor : Colors.grey)),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => _openProductAssignment(taxCode),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _openProductAssignment(String taxCode) async {
    final currentIds = _taxAssignmentMap[taxCode] ?? [];
    final List<ProductModel> previouslySelected = _allProducts
        .where((p) => currentIds.contains(p.id))
        .toList();

    final List<ProductModel>? selected = await ProductSearchScreen.showMultiSelect(
      context: context,
      currentUser: widget.currentUser,
      previouslySelected: previouslySelected,
      groupByCategory: true,
    );

    if (selected != null) {
      setState(() {
        final newIds = selected.map((e) => e.id).toList();

        _taxAssignmentMap.forEach((key, list) {
          if (key != taxCode) {
            list.removeWhere((id) => newIds.contains(id));
          }
        });

        _taxAssignmentMap[taxCode] = newIds;
      });
    }
  }
}

// ===================================================================
// TAB 2: KÊ KHAI THUẾ (Placeholder)
// ===================================================================
class TaxDeclarationTab extends StatefulWidget {
  final UserModel currentUser;
  const TaxDeclarationTab({super.key, required this.currentUser});
  @override
  State<TaxDeclarationTab> createState() => _TaxDeclarationTabState();
}

class _TaxDeclarationTabState extends State<TaxDeclarationTab> {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            "Tính năng Báo cáo Kê khai Thuế\nđang được cập nhật.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}