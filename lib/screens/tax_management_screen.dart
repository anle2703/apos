// File: lib/screens/tax/tax_management_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dropdown.dart';
import '../../models/product_model.dart';
import '../widgets/product_search_delegate.dart';
import '../../services/toast_service.dart';
import '../../theme/number_utils.dart';

// Dùng cho HKD Nhóm 2 (200tr - 3 tỷ)
const Map<String, Map<String, dynamic>> kHkdGopRates = {
  'HKD_GOP_0': {'name': '0%', 'rate': 0.0},
  'HKD_GOP_1_5': {'name': '1.5% (Bán lẻ, hàng hóa)', 'rate': 0.015},
  'HKD_GOP_4_5': {'name': '4.5% (Dịch vụ ăn uống)', 'rate': 0.045},
  'HKD_GOP_7': {'name': '7% (Dịch vụ khác)', 'rate': 0.07},
  'HKD_GOP_10': {'name': '10% (Cho thuê)', 'rate': 0.10},
};

// Dùng cho HKD Nhóm 3 (>= 3 tỷ) và Doanh nghiệp
const Map<String, Map<String, dynamic>> kVatRates = {
  'VAT_0': {'name': '0% (Không chịu thuế)', 'rate': 0.0},
  'VAT_5': {'name': '5%', 'rate': 0.05},
  'VAT_8': {'name': '8%', 'rate': 0.08},
  'VAT_10': {'name': '10%', 'rate': 0.1},
};

// Dùng cho Tab Kê khai (Gộp cả 2 map trên)
const Map<String, Map<String, dynamic>> kAllTaxRates = {
  ...kHkdGopRates, ...kVatRates,
};


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
        title: const Text('Quản lý Thuế & Kê khai'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.settings), text: 'Cài Đặt Thuế'),
            Tab(icon: Icon(Icons.calculate), text: 'Kê Khai (Mẫu 01/CNKD)'),
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
// TAB 1: CÀI ĐẶT THUẾ (V5 - THEO YÊU CẦU MỚI)
// ===================================================================
enum BusinessType { hkd, dn }
enum TaxGroup { group1, group2, group3, company }

class TaxSettingsTab extends StatefulWidget {
  final UserModel currentUser;
  const TaxSettingsTab({super.key, required this.currentUser});

  @override
  State<TaxSettingsTab> createState() => _TaxSettingsTabState();
}

class _TaxSettingsTabState extends State<TaxSettingsTab> {
  final FirestoreService _firestoreService = FirestoreService();

  // A. Thông tin
  BusinessType _businessType = BusinessType.hkd;
  double _annualRevenue = 500000000;
  final TextEditingController _taxIdController = TextEditingController();
  String _declarationPeriod = 'Theo Quý';

  // B. Trạng thái
  TaxGroup _taxGroup = TaxGroup.group2;

  // C. Cài đặt áp dụng (Nâng cao)
  bool _applyRounding = true;

  // D. Bảng phân loại
  Map<String, List<String>> _taxRateProductMap = {};
  List<ProductModel> _allProducts = [];

  // UI State
  bool _isLoading = true;
  bool _isAdvancedExpanded = false;
  final _revenueController = TextEditingController();
  final _formatter = NumberFormat.decimalPattern('vi_VN');
  Map<String, dynamic> _taxThresholds = {};

  @override
  void initState() {
    super.initState();
    _revenueController.text = _formatter.format(_annualRevenue);
    _loadSettingsAndProducts();
  }

  Future<void> _loadSettingsAndProducts() async {
    setState(() => _isLoading = true);
    try {
      _taxThresholds = await _firestoreService.getTaxThresholds();

      final results = await Future.wait([
        _firestoreService.getStoreTaxSettings(widget.currentUser.storeId),
        _firestoreService.getAllProductsStream(widget.currentUser.storeId).first,
      ]);

      final settings = results[0] as Map<String, dynamic>?;
      _allProducts = results[1] as List<ProductModel>;

      if (settings != null) {
        _taxIdController.text = settings['taxId'] ?? '';
        _declarationPeriod = settings['declarationPeriod'] ?? 'Theo Quý';
        _businessType = (settings['businessType'] == 'dn')
            ? BusinessType.dn
            : BusinessType.hkd;
        _annualRevenue =
            (settings['annualRevenue'] as num?)?.toDouble() ?? 500000000;

        _applyRounding = settings['applyRounding'] ?? true;

        _taxRateProductMap = {};
        final rawMap =
            settings['taxRateProductMap'] as Map<String, dynamic>? ?? {};
        rawMap.forEach((key, value) {
          if (value is List) {
            _taxRateProductMap[key] = List<String>.from(value);
          }
        });

        _revenueController.text = _formatter.format(_annualRevenue);
      }

      _updateTaxLogic();
    } catch (e) {
      ToastService().show(message: "Lỗi tải cài đặt: $e", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);
    try {
      final settings = {
        'taxId': _taxIdController.text.trim(),
        'declarationPeriod': _declarationPeriod,
        'businessType': _businessType == BusinessType.dn ? 'dn' : 'hkd',
        'annualRevenue': _annualRevenue,
        'applyRounding': _applyRounding,
        'taxRateProductMap': _taxRateProductMap,
      };
      await _firestoreService.updateStoreTaxSettings(
          widget.currentUser.storeId, settings);
      ToastService()
          .show(message: "Đã lưu cài đặt thuế!", type: ToastType.success);
    } catch (e) {
      ToastService().show(message: "Lỗi lưu cài đặt: $e", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _revenueController.dispose();
    _taxIdController.dispose();
    super.dispose();
  }

  void _updateTaxLogic() {
    TaxGroup newGroup;

    final double m1 = (_taxThresholds['hkd_revenue_threshold_group1'] as num?)?.toDouble() ?? 200000000;
    final double m2 = (_taxThresholds['hkd_revenue_threshold_group2'] as num?)?.toDouble() ?? 3000000000;

    if (_businessType == BusinessType.hkd) {
      if (_annualRevenue <= m1) {
        newGroup = TaxGroup.group1;
      } else if (_annualRevenue < m2) {
        newGroup = TaxGroup.group2;
      } else {
        newGroup = TaxGroup.group3;
      }
    } else {
      newGroup = TaxGroup.company;
    }

    setState(() {
      _taxGroup = newGroup;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildSectionAInfo(),
          const SizedBox(height: 16),
          _buildSectionBRevenue(),
          const SizedBox(height: 16),
          _buildTaxGroupStatus(),
          const SizedBox(height: 16),
          _buildSectionCAdvancedSettings(),
          const SizedBox(height: 16),
          _buildSectionDTaxAssignment(),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: _saveSettings,
          child: _isLoading
              ? const CircularProgressIndicator()
              : const Text('Lưu Cài Đặt'),
        ),
      ),
    );
  }

  Widget _buildSectionAInfo() {
    String description = '';
    if (_businessType == BusinessType.hkd) {
      description =
      'Áp dụng thuế theo ngưỡng doanh thu năm. Hệ thống sẽ tự động phân nhóm và bật các cài đặt thuế phù hợp.';
    } else {
      description =
      'Áp dụng thuế VAT khấu trừ và Thuế TNDN (15%-20%) theo quy định. Yêu cầu sổ sách kế toán đầy đủ.';
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('A. Thông tin chung',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _taxIdController,
              decoration: InputDecoration(
                labelText: 'Mã số thuế',
                border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            AppDropdown<BusinessType>(
              labelText: 'Loại hình kinh doanh',
              value: _businessType,
              items: const [
                DropdownMenuItem(
                  value: BusinessType.hkd,
                  child: Text('Hộ kinh doanh cá thể'),
                ),
                DropdownMenuItem(
                  value: BusinessType.dn,
                  child: Text('Doanh nghiệp (TNHH, Cổ phần... )'),
                ),
              ],
              onChanged: (type) {
                if (type != null) {
                  setState(() {
                    _businessType = type;
                    _updateTaxLogic();
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            Text(description, style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionBRevenue() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('B. Ước tính doanh thu / năm',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Slider(
              value: _annualRevenue,
              min: 0,
              max: 10000000000,
              divisions: 200,
              label: _formatter.format(_annualRevenue.round()),
              onChanged: (value) {
                setState(() {
                  _annualRevenue = value;
                  _revenueController.text = _formatter.format(value.round());
                  _updateTaxLogic();
                });
              },
            ),
            TextFormField(
              controller: _revenueController,
              decoration: const InputDecoration(
                labelText: 'Hoặc nhập chính xác (VND)',
                suffixText: 'đ / năm',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsInputFormatter()],
              onEditingComplete: () {
                final value =
                    double.tryParse(_revenueController.text.replaceAll('.', '')) ??
                        0;
                setState(() {
                  _annualRevenue = value.clamp(0, 10000000000);
                  _revenueController.text =
                      _formatter.format(_annualRevenue.round());
                  _updateTaxLogic();
                });
                FocusScope.of(context).unfocus();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaxGroupStatus() {
    String title;
    String description;
    Color color;

    final double m1 = (_taxThresholds['hkd_revenue_threshold_group1'] as num?)?.toDouble() ?? 200000000;
    final double m2 = (_taxThresholds['hkd_revenue_threshold_group2'] as num?)?.toDouble() ?? 3000000000;

    switch (_taxGroup) {
      case TaxGroup.group1:
        title = 'Trạng thái: Miễn Thuế';
        description =
        'Doanh thu ≤ ${_formatter.format(m1.round())} đ/năm. Bạn được miễn thuế VAT và TNCN.';
        color = Colors.green;
        break;
      case TaxGroup.group2:
        title = 'Trạng thái: Thuế Gộp (% Doanh Thu)';
        description =
        'Doanh thu ${_formatter.format(m1.round())} - ${_formatter.format(m2.round())} đ/năm. Áp dụng thuế gộp (VAT + TNCN) theo tỷ lệ % trên doanh thu.';
        color = Colors.orange;
        break;
      case TaxGroup.group3:
        title = 'Trạng thái: Thuế VAT (Kế Toán HKD)';
        description =
        'Doanh thu ≥ ${_formatter.format(m2.round())} đ/năm. Áp dụng VAT khấu trừ và sổ sách kế toán đầy đủ.';
        color = Colors.red;
        break;
      case TaxGroup.company:
        title = 'Trạng thái: Thuế VAT (Doanh Nghiệp)';
        description =
        'Áp dụng VAT khấu trừ và Thuế TNDN. Yêu cầu sổ sách kế toán.';
        color = Colors.blue;
        break;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                const SizedBox(height: 4),
                Text(description, style: TextStyle(color: color.darken(0.2))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCAdvancedSettings() {
    if (_taxGroup == TaxGroup.group1) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        title: Text('C. Cài đặt áp dụng thuế',
            style: Theme.of(context).textTheme.titleLarge),
        onExpansionChanged: (isExpanded) =>
            setState(() => _isAdvancedExpanded = isExpanded),
        initiallyExpanded: _isAdvancedExpanded,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('1. Làm tròn',
                    style: Theme.of(context).textTheme.titleSmall),
                SwitchListTile(
                  title: const Text('Tự động làm tròn số thuế'),
                  subtitle: const Text(
                      'Làm tròn đến đơn vị Đồng (VNĐ) gần nhất trên tổng hóa đơn.'),
                  value: _applyRounding,
                  onChanged: (val) => setState(() => _applyRounding = val),
                ),
                const SizedBox(height: 16),
                Text('2. Kỳ kê khai',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                AppDropdown<String>(
                  labelText: 'Kê khai theo',
                  value: _declarationPeriod,
                  items: const [
                    DropdownMenuItem(value: 'Theo Quý', child: Text('Theo Quý')),
                    DropdownMenuItem(value: 'Theo Tháng', child: Text('Theo Tháng')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _declarationPeriod = value);
                  },
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSectionDTaxAssignment() {
    if (_taxGroup == TaxGroup.group1) {
      return Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: _buildInfoCard('Miễn thuế',
              'Doanh thu dưới 200tr/năm, bạn không cần cài đặt thuế.'),
        ),
      );
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('D. Bảng phân loại thuế',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),

            // HKD Nhóm 2 (200tr - 3 tỷ)
            if (_taxGroup == TaxGroup.group2) ...[
              const Text(
                'Gán sản phẩm/dịch vụ vào các nhóm Thuế Gộp (VAT + TNCN) sau:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              ...kHkdGopRates.entries.map((entry) {
                return _buildTaxRateAssignmentTile(
                  taxKey: entry.key,
                  name: entry.value['name'],
                  rate: entry.value['rate'],
                );
              }),
            ],

            // HKD Nhóm 3 (>= 3 tỷ)
            if (_taxGroup == TaxGroup.group3) ...[
              const Text(
                'Gán sản phẩm/dịch vụ vào các nhóm Thuế VAT (HKD Nộp theo Sổ sách):',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              ...kVatRates.entries.map((entry) {
                return _buildTaxRateAssignmentTile(
                  taxKey: entry.key,
                  name: entry.value['name'],
                  rate: entry.value['rate'],
                );
              }),
            ],

            // Doanh nghiệp
            if (_taxGroup == TaxGroup.company) ...[
              const Text(
                'Gán sản phẩm/dịch vụ vào các nhóm Thuế VAT (Doanh nghiệp):',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              ...kVatRates.entries.map((entry) {
                return _buildTaxRateAssignmentTile(
                  taxKey: entry.key,
                  name: entry.value['name'],
                  rate: entry.value['rate'],
                );
              }),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildTaxRateAssignmentTile({
    required String taxKey,
    required String name,
    required double rate,
  }) {
    final List<String> productIds = _taxRateProductMap[taxKey] ?? [];
    final int productCount = productIds.length;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.grey.shade300)),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dòng Text hiển thị % màu đã bị xóa
            Text(productCount == 0
                ? 'Chưa có sản phẩm nào'
                : 'Đã gán $productCount sản phẩm'),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final List<ProductModel> previouslySelected = productIds
              .map((id) => _allProducts.firstWhere((p) => p.id == id,
              orElse: () => ProductModel.fromMap({})))
              .where((p) => p.id.isNotEmpty)
              .toList();

          final List<ProductModel>? selectedProducts =
          await ProductSearchScreen.showMultiSelect(
            context: context,
            currentUser: widget.currentUser,
            previouslySelected: previouslySelected,
            groupByCategory: true,
          );

          if (selectedProducts != null) {
            setState(() {
              // 1. Lấy ID của các sản phẩm vừa được chọn
              final Set<String> newSelectedIds =
              selectedProducts.map((p) => p.id).toSet();

              // 2. Lặp qua TẤT CẢ các nhóm thuế khác
              // (Dùng .keys.toList() để tránh lỗi "Concurrent modification")
              for (final otherTaxKey in _taxRateProductMap.keys.toList()) {
                // 3. Bỏ qua nhóm thuế mà chúng ta đang chỉnh sửa
                if (otherTaxKey == taxKey) continue;

                // 4. Lấy danh sách ID sản phẩm của nhóm thuế "khác"
                final List<String>? otherProductIds =
                _taxRateProductMap[otherTaxKey];
                if (otherProductIds == null || otherProductIds.isEmpty) continue;

                // 5. Xóa bất kỳ sản phẩm nào trong nhóm "khác"
                //    nếu nó tồn tại trong danh sách mới
                otherProductIds.removeWhere((id) => newSelectedIds.contains(id));

                // 6. Cập nhật lại map cho nhóm "khác"
                _taxRateProductMap[otherTaxKey] = otherProductIds;
              }

              // 7. Gán danh sách mới cho nhóm thuế hiện tại
              _taxRateProductMap[taxKey] = newSelectedIds.toList();
            });
          }
        },
      ),
    );
  }

  Widget _buildInfoCard(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.check_circle, color: Colors.green.shade700),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(subtitle, style: TextStyle(color: Colors.grey.shade600)),
        ),
      ],
    );
  }
}

// ===================================================================
// TAB 2: KÊ KHAI THUẾ
// ===================================================================

class TaxDeclarationSummary {
  final String categoryKey;
  final String categoryName;
  final double totalRevenue;
  final double taxRate;

  double get taxAmount => totalRevenue * taxRate;

  TaxDeclarationSummary({
    required this.categoryKey,
    required this.categoryName,
    required this.totalRevenue,
    required this.taxRate,
  });
}

class TaxDeclarationTab extends StatefulWidget {
  final UserModel currentUser;
  const TaxDeclarationTab({super.key, required this.currentUser});

  @override
  State<TaxDeclarationTab> createState() => _TaxDeclarationTabState();
}

class _TaxDeclarationTabState extends State<TaxDeclarationTab> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _isSettingsLoading = true;
  bool _isDeclarationLoading = false;

  final Map<String, String> _productTaxRateMap = {};
  String _periodType = 'Theo Quý';
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  int _selectedQuarter = (DateTime.now().month / 3).ceil();

  List<TaxDeclarationSummary> _summaryData = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isSettingsLoading = true);
    try {
      final settings = await _firestoreService
          .getStoreTaxSettings(widget.currentUser.storeId);
      if (settings != null) {
        _periodType = settings['declarationPeriod'] ?? 'Theo Quý';

        final rawMap = settings['taxRateProductMap'] as Map<String, dynamic>? ?? {};
        _productTaxRateMap.clear();
        rawMap.forEach((taxKey, productIds) {
          if (productIds is List) {
            for (final productId in productIds) {
              _productTaxRateMap[productId as String] = taxKey;
            }
          }
        });

      }
    } catch (e) {
      ToastService().show(message: "Lỗi tải cài đặt: $e", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isSettingsLoading = false);
    }
  }

  Future<void> _fetchDeclarationData() async {
    if (_productTaxRateMap.isEmpty) {
      ToastService().show(
          message:
          "Vui lòng 'Lưu Cài Đặt Thuế' (Tab 1) và gán sản phẩm vào ngành thuế trước.",
          type: ToastType.warning);
      return;
    }
    setState(() => _isDeclarationLoading = true);

    try {
      DateTime startDate;
      DateTime endDate;

      if (_periodType == 'Theo Tháng') {
        startDate = DateTime(_selectedYear, _selectedMonth, 1);
        endDate = DateTime(_selectedYear, _selectedMonth + 1, 0, 23, 59, 59);
      } else {
        int startMonth = (_selectedQuarter - 1) * 3 + 1;
        int endMonth = startMonth + 2;
        startDate = DateTime(_selectedYear, startMonth, 1);
        endDate = DateTime(_selectedYear, endMonth + 1, 0, 23, 59, 59);
      }

      final List<String> dateStringsToFetch =
      _getDateStringsInRange(startDate, endDate);
      if (dateStringsToFetch.isEmpty) {
        setState(() {
          _isDeclarationLoading = false;
          _summaryData = [];
        });
        ToastService()
            .show(message: "Không có dữ liệu cho kỳ này", type: ToastType.warning);
        return;
      }

      final List<String> dailyReportIds = dateStringsToFetch
          .map((dateStr) => '${widget.currentUser.storeId}_$dateStr')
          .toList();

      final Map<String, double> revenueByTaxCategory = {};
      const batchSize = 30;

      for (int i = 0; i < dailyReportIds.length; i += batchSize) {
        final batchIds = dailyReportIds.sublist(
            i,
            i + batchSize > dailyReportIds.length
                ? dailyReportIds.length
                : i + batchSize);

        if (batchIds.isNotEmpty) {
          final snapshot = await FirebaseFirestore.instance
              .collection('daily_reports')
              .where(FieldPath.documentId, whereIn: batchIds)
              .get();

          for (final doc in snapshot.docs) {
            final data = doc.data();
            final rootProducts =
                (data['products'] as Map<String, dynamic>?) ?? {};

            for (final pEntry in rootProducts.entries) {
              final pData = pEntry.value as Map<String, dynamic>;
              final String? productId = pData['productId'];
              final double productRevenue =
                  (pData['totalRevenue'] as num?)?.toDouble() ?? 0.0;

              if (productId != null) {
                // Gán vào nhóm "0%" nếu không tìm thấy
                final String taxCategoryKey =
                    _productTaxRateMap[productId] ?? (kAllTaxRates.keys.first);

                revenueByTaxCategory.update(
                  taxCategoryKey,
                      (value) => value + productRevenue,
                  ifAbsent: () => productRevenue,
                );
              }
            }
          }
        }
      }

      final List<TaxDeclarationSummary> summaryList = [];
      revenueByTaxCategory.forEach((key, revenue) {
        // Dùng kAllTaxRates (map gộp) để tra cứu
        if (revenue > 0 && kAllTaxRates.containsKey(key)) {
          final taxInfo = kAllTaxRates[key]!;
          summaryList.add(TaxDeclarationSummary(
            categoryKey: key,
            categoryName: taxInfo['name'],
            totalRevenue: revenue,
            taxRate: taxInfo['rate'],
          ));
        }
      });

      setState(() {
        _summaryData = summaryList;
        _isDeclarationLoading = false;
      });
    } catch (e) {
      ToastService().show(message: "Lỗi tải dữ liệu: $e", type: ToastType.error);
      if (mounted) setState(() => _isDeclarationLoading = false);
    }
  }

  List<String> _getDateStringsInRange(DateTime startDate, DateTime endDate) {
    final List<String> dateStrings = [];
    DateTime currentDate =
    DateTime(startDate.year, startDate.month, startDate.day);
    final DateTime finalDate =
    DateTime(endDate.year, endDate.month, endDate.day);
    final DateFormat formatter = DateFormat('yyyy-MM-dd');
    while (currentDate.isBefore(finalDate) ||
        currentDate.isAtSameMomentAs(finalDate)) {
      dateStrings.add(formatter.format(currentDate));
      currentDate = currentDate.add(const Duration(days: 1));
    }
    return dateStrings;
  }

  @override
  Widget build(BuildContext context) {
    if (_isSettingsLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildPeriodSelector(),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _isDeclarationLoading ? null : _fetchDeclarationData,
            icon: const Icon(Icons.calculate_outlined),
            label: Text(_isDeclarationLoading
                ? 'Đang tính toán...'
                : 'Tính Thuế & Lập Tờ Khai'),
          ),
          const Divider(height: 32),
          if (_isDeclarationLoading)
            const Center(child: CircularProgressIndicator())
          else if (_summaryData.isEmpty)
            const Center(child: Text('Chưa có dữ liệu kê khai.'))
          else
            _buildDeclarationResult(),
        ],
      ),
      bottomNavigationBar: _summaryData.isNotEmpty
          ? Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.download_for_offline),
          label: const Text('Xuất File XML (Nộp Thuế)'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            foregroundColor: Colors.white,
          ),
        ),
      )
          : null,
    );
  }

  Widget _buildPeriodSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chọn Kỳ Kê Khai',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            AppDropdown<String>(
              labelText: 'Loại kỳ',
              value: _periodType,
              items: [
                DropdownMenuItem(
                    value: 'Theo Quý', child: const Text('Theo Quý')),
                DropdownMenuItem(
                    value: 'Theo Tháng', child: const Text('Theo Tháng')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _periodType = value);
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (_periodType == 'Theo Tháng')
                  Expanded(
                    child: AppDropdown<int>(
                      labelText: 'Tháng',
                      value: _selectedMonth,
                      items: List.generate(
                          12,
                              (i) => DropdownMenuItem(
                              value: i + 1, child: Text('Tháng ${i + 1}'))),
                      onChanged: (value) {
                        if (value != null) setState(() => _selectedMonth = value);
                      },
                    ),
                  )
                else
                  Expanded(
                    child: AppDropdown<int>(
                      labelText: 'Quý',
                      value: _selectedQuarter,
                      items: List.generate(
                          4,
                              (i) => DropdownMenuItem(
                              value: i + 1, child: Text('Quý ${i + 1}'))),
                      onChanged: (value) {
                        if (value != null){
                          setState(() => _selectedQuarter = value);
                        }
                      },
                    ),
                  ),
                const SizedBox(width: 16),
                Expanded(
                  child: AppDropdown<int>(
                    labelText: 'Năm',
                    value: _selectedYear,
                    items: List.generate(5, (i) => DateTime.now().year - i)
                        .map((year) => DropdownMenuItem(
                        value: year, child: Text('Năm $year')))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _selectedYear = value);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeclarationResult() {
    double totalRevenue = 0;
    double totalTax = 0;

    for (final item in _summaryData) {
      totalRevenue += item.totalRevenue;
      totalTax += item.taxAmount;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tờ Khai Thuế (Mẫu 01/CNKD)',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Row(
          children: [
            Expanded(
                flex: 3,
                child: Text('Ngành nghề',
                    style: TextStyle(fontWeight: FontWeight.bold))),
            Expanded(
                flex: 2,
                child: Text('Doanh thu',
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.right)),
            Expanded(
                flex: 2,
                child: Text('Thuế phải nộp',
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.right)),
          ],
        ),
        const Divider(),
        ..._summaryData.map((item) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    flex: 3,
                    child: Text(item.categoryName,
                        style: const TextStyle(fontSize: 13))),
                Expanded(
                    flex: 2,
                    child: Text(formatNumber(item.totalRevenue),
                        textAlign: TextAlign.right)),
                Expanded(
                    flex: 2,
                    child: Text(
                        formatNumber(item.taxAmount),
                        textAlign: TextAlign.right)),
              ],
            ),
          );
        }),
        const Divider(thickness: 2),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              const Expanded(
                  flex: 3,
                  child: Text('TỔNG CỘNG',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16))),
              Expanded(
                  flex: 2,
                  child: Text(formatNumber(totalRevenue),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                      textAlign: TextAlign.right)),
              Expanded(
                  flex: 2,
                  child: Text(formatNumber(totalTax),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red),
                      textAlign: TextAlign.right)),
            ],
          ),
        ),
      ],
    );
  }
}

class ThousandsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    String newText = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (newText.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final number = int.parse(newText);
    final formatter = NumberFormat.decimalPattern('vi_VN');
    final String newString = formatter.format(number);

    return TextEditingValue(
      text: newString,
      selection: TextSelection.collapsed(offset: newString.length),
    );
  }
}

extension ColorExtension on Color {
  Color darken([double amount = .1]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(this);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }
}