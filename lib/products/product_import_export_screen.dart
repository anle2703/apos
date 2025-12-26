// lib/screens/products/product_import_export_screen.dart
import 'dart:convert';
import 'dart:typed_data'; // Cần thiết cho Uint8List
import 'package:flutter/material.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart'; // Dùng gói này
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/user_model.dart';
import '../../models/product_model.dart';
import '../../services/firestore_service.dart';
import '../../services/toast_service.dart';
import '../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/number_utils.dart';
import '../../screens/tax_management_screen.dart';

class ProductImportExportScreen extends StatelessWidget {
  final UserModel currentUser;

  const ProductImportExportScreen({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Nhập/Xuất file Hàng hóa'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Xuất File (Export)', icon: Icon(Icons.file_download)),
              Tab(text: 'Nhập File (Import)', icon: Icon(Icons.file_upload)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ExportTab(currentUser: currentUser),
            _ImportTab(currentUser: currentUser),
          ],
        ),
      ),
    );
  }
}

class _ExportTab extends StatefulWidget {
  final UserModel currentUser;
  const _ExportTab({required this.currentUser});

  @override
  State<_ExportTab> createState() => _ExportTabState();
}

class _ExportTabState extends State<_ExportTab> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _isLoading = false;

  final List<String> _headers = [
    'ID (Không sửa)',
    'Tên sản phẩm',
    'Mã SP',
    'Nhóm SP',
    'ĐVT',
    'Giá bán',
    'Giá vốn',
    'Tồn kho',
    'Tồn tối thiểu',
    '% Thuế',
    'Loại SP',
    'Mã vạch phụ (Cách nhau bởi dấu ,)',
    'Máy in bếp (Cách nhau bởi dấu ,)',
    'Cho phép bán (true/false)',
    'QL Kho riêng (true/false)',
    'ĐVT phụ (JSON)',
    'Định lượng (JSON)',
    'Bán kèm (JSON)',
    'Dịch vụ (JSON)',
  ];

  Future<void> _exportProducts() async {
    setState(() => _isLoading = true);
    final toastService = ToastService();

    try {
      final products = await _firestoreService
          .getAllProductsStream(widget.currentUser.storeId)
          .first;

      if (products.isEmpty) {
        toastService.show(message: "Không có sản phẩm nào để xuất", type: ToastType.warning);
        setState(() => _isLoading = false);
        return;
      }

      // 2. [MỚI] Lấy cấu hình thuế để map ngược từ ID sản phẩm -> % Thuế
      final taxSettings = await _firestoreService.getStoreTaxSettings(widget.currentUser.storeId);
      final Map<String, List<dynamic>> taxAssignmentMap = {};
      if (taxSettings != null && taxSettings['taxAssignmentMap'] is Map) {
        final rawMap = taxSettings['taxAssignmentMap'] as Map<String, dynamic>;
        rawMap.forEach((key, value) {
          if (value is List) taxAssignmentMap[key] = value;
        });
      }

      // Helper function để tìm thuế suất của sản phẩm
      double getTaxRateForProduct(String productId) {
        // Tìm xem productId nằm trong list nào của taxAssignmentMap
        for (var entry in taxAssignmentMap.entries) {
          if (entry.value.contains(productId)) {
            final taxKey = entry.key;
            // Tra cứu rate trong các bảng hằng số (kDeductionRates / kDirectRates từ tax_management_screen)
            if (kDeductionRates.containsKey(taxKey)) {
              return (kDeductionRates[taxKey]?['rate'] as num?)?.toDouble() ?? 0.0;
            }
            if (kDirectRates.containsKey(taxKey)) {
              return (kDirectRates[taxKey]?['rate'] as num?)?.toDouble() ?? 0.0;
            }
          }
        }
        return 0.0;
      }

      final excel = Excel.createExcel();
      final Sheet sheet = excel[excel.getDefaultSheet()!];

      sheet.appendRow(_headers.map((header) => TextCellValue(header)).toList());

      for (final product in products) {
        final double taxRate = getTaxRateForProduct(product.id);
        final row = [
          TextCellValue(product.id),
          TextCellValue(product.productName),
          TextCellValue(product.productCode ?? ''),
          TextCellValue(product.productGroup ?? ''),
          TextCellValue(product.unit ?? ''),
          DoubleCellValue(product.sellPrice),
          DoubleCellValue(product.costPrice),
          DoubleCellValue(product.stock),
          DoubleCellValue(product.minStock),
          DoubleCellValue(taxRate * 100),
          TextCellValue(product.productType ?? ''),
          TextCellValue(product.additionalBarcodes.join(',')),
          TextCellValue(product.kitchenPrinters.join(',')),
          TextCellValue(product.isVisibleInMenu.toString()),
          TextCellValue(product.manageStockSeparately.toString()),
          TextCellValue(jsonEncode(product.additionalUnits)),
          TextCellValue(jsonEncode(product.recipeItems)),
          TextCellValue(jsonEncode(product.accompanyingItems)),
          TextCellValue(product.serviceSetup != null ? jsonEncode(product.serviceSetup) : ''),
        ];
        sheet.appendRow(row);
      }

      final String fileName = 'DanhSachSanPham_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final fileBytes = excel.save();

      if (fileBytes != null) {
        final String? result = await FilePicker.platform.saveFile(
          dialogTitle: 'Lưu file Excel',
          fileName: fileName,
          bytes: Uint8List.fromList(fileBytes),
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
        );

        if (result != null) {
          toastService.show(
              message: "Đã lưu file thành công!", type: ToastType.success);
        } else {
          toastService.show(message: "Đã hủy lưu file.", type: ToastType.warning);
        }
      }
    } catch (e) {
      toastService.show(message: "Xuất file thất bại: $e", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.description_outlined, size: 80, color: Colors.green),
            const SizedBox(height: 16),
            const Text(
              'Xuất toàn bộ danh sách hàng hóa ra file Excel. Bạn có thể dùng file này để chỉnh sửa và nhập lại, hoặc để sao lưu dữ liệu.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else
              ElevatedButton.icon(
                icon: const Icon(Icons.file_download),
                label: const Text('Bắt đầu Xuất file'),
                onPressed: _exportProducts,
              ),
          ],
        ),
      ),
    );
  }
}

class _ProductImportJob {
  final Map<String, dynamic> data;
  final ProductModel? existingProduct;
  final String? idFromFile; // id từ file Excel
  final int excelRow;
  final double? taxPercent;
  _ProductImportJob({
    required this.data,
    this.existingProduct,
    this.idFromFile,
    required this.excelRow,
    this.taxPercent,
  });
}

class _ImportTab extends StatefulWidget {
  final UserModel currentUser;
  const _ImportTab({required this.currentUser});

  @override
  State<_ImportTab> createState() => _ImportTabState();
}

class _ImportTabState extends State<_ImportTab> {
  final FirestoreService _firestoreService = FirestoreService();
  final StorageService _storageService = StorageService();
  bool _isLoading = false;
  String _statusText = '';
  bool _updateExisting = false;
  bool _updateStockCost = false;
  bool _updateComplexData = false;

  final List<String> _templateHeaders = [
    'ID (Không sửa)',
    'Tên sản phẩm',
    'Mã SP',
    'Nhóm SP',
    'ĐVT',
    'Giá bán',
    'Giá vốn',
    'Tồn kho',
    'Tồn tối thiểu',
    '% Thuế', // [MỚI]
    'Loại SP',
    'Mã vạch phụ (Cách nhau bởi dấu ,)',
    'Máy in bếp (Cách nhau bởi dấu ,)',
    'Cho phép bán (true/false)',
    'QL Kho riêng (true/false)',
    'ĐVT phụ (JSON)',
    'Định lượng (JSON)',
    'Bán kèm (JSON)',
    'Dịch vụ (JSON)',
  ];

  String? parseString(dynamic v) {
    final str = v?.toString().trim();
    if (str == null || str.isEmpty) return null;
    return str;
  }

  double? parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return parseVN(v.toString());
  }

  bool? parseBool(dynamic v) {
    if (v == null) return null;
    return v.toString().toLowerCase() == 'true';
  }

  List<String>? parseStringList(dynamic v) {
    if (v == null) return null;
    return v.toString().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  List<Map<String, dynamic>>? parseJsonList(dynamic v) {
    if (v == null) return null;
    try {
      final decoded = jsonDecode(v.toString());
      if (decoded is List) {
        return decoded.map((item) {
          if (item is Map) {
            return Map<String, dynamic>.from(item);
          }
          return <String, dynamic>{};
        }).where((item) => item.isNotEmpty).toList();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? parseServiceJson(dynamic v) {
    if (v == null) return null;
    try {
      final decoded = jsonDecode(v.toString());
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
      return null;
    } catch(_) {
      return null;
    }
  }

  String? _getProductPrefix(String? productType) {
    switch (productType) {
      case 'Hàng hóa': return 'HH';
      case 'Thành phẩm/Combo': return 'TP';
      case 'Dịch vụ/Tính giờ': return 'DV';
      case 'Topping/Bán kèm': return 'BK';
      case 'Nguyên liệu': return 'NL';
      case 'Vật liệu': return 'VL';
      default: return 'SP';
    }
  }

  Future<void> _downloadSampleFile() async {
    final excel = Excel.createExcel();
    final Sheet sheet = excel[excel.getDefaultSheet()!];

    // Tạo Header
    sheet.appendRow(_templateHeaders.map((e) => TextCellValue(e)).toList());

    // Tạo 1 dòng mẫu (Optional)
    sheet.appendRow([
      TextCellValue(''), // ID trống
      TextCellValue('Cà phê sữa đá (Mẫu)'),
      TextCellValue(''), // Mã SP trống (tự sinh)
      TextCellValue('Cà phê'),
      TextCellValue('Ly'),
      DoubleCellValue(25000), // Giá bán
      DoubleCellValue(10000), // Giá vốn
      DoubleCellValue(100),   // Tồn kho
      DoubleCellValue(10),    // Min stock
      DoubleCellValue(8),     // % Thuế (ví dụ 8%)
      TextCellValue('Hàng hóa'), // Loại SP
      TextCellValue(''),
      TextCellValue('Máy in A'),
      TextCellValue('true'),
      TextCellValue(''),
      TextCellValue(''), // JSON
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
    ]);

    final String fileName = 'APOS_FileMauHangHoa.xlsx';
    final fileBytes = excel.save();

    if (fileBytes != null) {
      final String? result = await FilePicker.platform.saveFile(
        dialogTitle: 'Lưu file mẫu',
        fileName: fileName,
        bytes: Uint8List.fromList(fileBytes),
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (result != null) {
        ToastService().show(message: "Đã tải file mẫu!", type: ToastType.success);
      }
    }
  }

  Future<void> _importProducts() async {
    // 1. Kiểm tra mounted đầu hàm
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _statusText = 'Đang chọn file...';
    });

    final toastService = ToastService();
    final storeId = widget.currentUser.storeId;

    const allowedProductTypes = {
      'Hàng hóa',
      'Thành phẩm/Combo',
      'Dịch vụ/Tính giờ',
      'Topping/Bán kèm',
      'Nguyên liệu',
      'Vật liệu'
    };

    try {
      // 1. CHỌN FILE
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );
      if (result == null || result.files.first.bytes == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // 2. ĐỌC FILE
      if (mounted) setState(() => _statusText = 'Đang đọc file Excel...');
      final bytes = result.files.first.bytes!;
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables[excel.tables.keys.first]!;
      if (sheet.rows.isEmpty) throw Exception("File không có dữ liệu");

      final headers = sheet.rows.first;
      final Map<String, int> headerMap = {};
      for (int i = 0; i < headers.length; i++) {
        final cell = headers[i];
        if (cell != null) {
          headerMap[cell.value.toString().trim()] = i;
        }
      }
      if (!headerMap.containsKey('Tên sản phẩm')) {
        throw Exception("Thiếu cột 'Tên sản phẩm'");
      }

      // 3. TẢI DỮ LIỆU HIỆN TẠI
      if (mounted) setState(() => _statusText = 'Đang lấy dữ liệu hệ thống...');
      final allProducts = await _firestoreService.getAllProductsStream(storeId).first;

      final productMapByCode = <String, ProductModel>{};
      final productMapById = <String, ProductModel>{};

      for (var p in allProducts) {
        if (p.productCode != null && p.productCode!.isNotEmpty) {
          productMapByCode[p.productCode!] = p;
        }
        productMapById[p.id] = p;
      }

      final taxSettingsDoc = await _firestoreService.getStoreTaxSettings(storeId);
      final taxMethod = taxSettingsDoc?['calcMethod'] ?? 'direct';

      final allGroupsSnapshot = await FirebaseFirestore.instance
          .collection('product_groups').where('storeId', isEqualTo: storeId).get();
      final existingGroupNames = allGroupsSnapshot.docs
          .map((doc) => doc.data()['name'] as String).toSet();

      // 4. PHA 1: XÁC THỰC & PARSE DỮ LIỆU
      if (mounted) setState(() => _statusText = 'Đang xác thực dữ liệu...');

      final List<_ProductImportJob> jobsToProcess = [];
      final Set<String> newGroupNamesToCreate = {};
      final Set<String> skusInFile = {};

      int skippedCount = 0;
      int newCount = 0;
      int updatedCount = 0;

      for (int i = 1; i < sheet.rows.length; i++) {
        final int excelRow = i + 1;
        final row = sheet.rows[i];

        dynamic getCell(String headerName) {
          if (!headerMap.containsKey(headerName) || headerMap[headerName]! >= row.length) {
            return null;
          }
          return row[headerMap[headerName]!]?.value;
        }

        final productName = parseString(getCell('Tên sản phẩm'));
        if (productName == null) continue;

        final String? id = parseString(getCell('ID (Không sửa)'));
        final String? code = parseString(getCell('Mã SP'));
        final String? productType = parseString(getCell('Loại SP'));
        final double? taxPercent = parseDouble(getCell('% Thuế'));

        if (productType == null) throw Exception("Dòng $excelRow: Thiếu 'Loại SP'");
        if (!allowedProductTypes.contains(productType)) throw Exception("Dòng $excelRow: Loại SP '$productType' sai");

        if (code != null) {
          if (skusInFile.contains(code)) throw Exception("Dòng $excelRow: Trùng Mã SP '$code' trong file");
          skusInFile.add(code);
        }

        ProductModel? existingProduct;
        if (id != null) existingProduct = productMapById[id];

        if (code != null) {
          final productWithThisCode = productMapByCode[code];
          if (productWithThisCode != null) {
            if (existingProduct == null) {
              throw Exception("Dòng $excelRow: Mã SP '$code' đã tồn tại (ID: ${productWithThisCode.id})");
            } else if (existingProduct.id != productWithThisCode.id) {
              throw Exception("Dòng $excelRow: Mã SP '$code' thuộc về SP khác");
            }
          }
        }

        if (existingProduct != null && !_updateExisting) {
          skippedCount++;
          continue;
        }

        final Map<String, dynamic> productData = {};
        productData['productName'] = productName;
        productData['productCode'] = code;
        productData['productType'] = productType;
        productData['productGroup'] = parseString(getCell('Nhóm SP'));
        productData['unit'] = parseString(getCell('ĐVT'));
        productData['sellPrice'] = parseDouble(getCell('Giá bán'));
        productData['additionalBarcodes'] = parseStringList(getCell('Mã vạch phụ (Cách nhau bởi dấu ,)'));
        productData['kitchenPrinters'] = parseStringList(getCell('Máy in bếp (Cách nhau bởi dấu ,)'));
        productData['isVisibleInMenu'] = parseBool(getCell('Cho phép bán (true/false)'));
        productData['manageStockSeparately'] = parseBool(getCell('QL Kho riêng (true/false)'));

        if (_updateComplexData) {
          productData['additionalUnits'] = parseJsonList(getCell('ĐVT phụ (JSON)'));
          productData['recipeItems'] = parseJsonList(getCell('Định lượng (JSON)'));
          productData['accompanyingItems'] = parseJsonList(getCell('Bán kèm (JSON)'));
          productData['serviceSetup'] = parseServiceJson(getCell('Dịch vụ (JSON)'));
        }

        if (_updateStockCost) {
          productData['costPrice'] = parseDouble(getCell('Giá vốn'));
          productData['stock'] = parseDouble(getCell('Tồn kho'));
          productData['minStock'] = parseDouble(getCell('Tồn tối thiểu'));
        } else if (existingProduct != null) {
          productData['costPrice'] = existingProduct.costPrice;
          productData['stock'] = existingProduct.stock;
          productData['minStock'] = existingProduct.minStock;
        }

        final String? groupNameFromExcel = productData['productGroup'] as String?;
        if (groupNameFromExcel != null && !existingGroupNames.contains(groupNameFromExcel)) {
          newGroupNamesToCreate.add(groupNameFromExcel);
        }

        jobsToProcess.add(_ProductImportJob(
          data: productData,
          existingProduct: existingProduct,
          idFromFile: id,
          excelRow: excelRow,
          taxPercent: taxPercent,
        ));
      }

      // [LOGIC CŨ] Validate Complex Data (Đã khôi phục đầy đủ)
      if (_updateComplexData) {
        if (mounted) setState(() => _statusText = 'Đang kiểm tra liên kết dữ liệu...');
        final Set<String> validIds = Set.from(productMapById.keys);
        for (var job in jobsToProcess) {
          if (job.idFromFile != null && job.idFromFile!.isNotEmpty) validIds.add(job.idFromFile!);
        }
        for (var job in jobsToProcess) {
          void validateRefIds(String listKey) {
            final listData = job.data[listKey] as List<Map<String, dynamic>>?;
            if (listData == null || listData.isEmpty) return;
            for (var item in listData) {
              String? refId;
              if (item.containsKey('productId')) {refId = item['productId'];}
              else if (item.containsKey('product') && item['product'] is Map) {refId = item['product']['id'];}
              else if (item.containsKey('id')) {refId = item['id'];}

              if (refId != null && refId.isNotEmpty && !validIds.contains(refId)) {
                throw Exception("Dòng ${job.excelRow}: ID tham chiếu '$refId' không tồn tại.");
              }
            }
          }
          validateRefIds('recipeItems');
          validateRefIds('accompanyingItems');
        }
      }

      // 5. PHA 2: TẠO NHÓM & SINH MÃ TỰ ĐỘNG
      if (mounted) setState(() => _statusText = 'Đang khởi tạo Mã SP và Nhóm...');

      if (newGroupNamesToCreate.isNotEmpty) {
        var groupBatch = FirebaseFirestore.instance.batch();
        int highestStt = allGroupsSnapshot.docs
            .map((doc) => (doc.data()['stt'] as num?)?.toInt() ?? 0)
            .fold(0, (max, curr) => curr > max ? curr : max);

        for (final newGroup in newGroupNamesToCreate) {
          highestStt++;
          final groupDocRef = FirebaseFirestore.instance.collection('product_groups').doc();
          groupBatch.set(groupDocRef, {
            'name': newGroup, 'storeId': storeId, 'stt': highestStt, 'createdAt': FieldValue.serverTimestamp(),
          });
        }
        await groupBatch.commit();
        existingGroupNames.addAll(newGroupNamesToCreate);
      }

      // [LOGIC CŨ] Sinh mã SP (Đã khôi phục đầy đủ)
      int extractNumericCode(String code, String prefix) {
        if (code.startsWith(prefix)) return int.tryParse(code.substring(prefix.length)) ?? 0;
        return 0;
      }
      final countersRef = FirebaseFirestore.instance.collection('counters').doc('product_codes_$storeId');
      final countersDoc = await countersRef.get();
      final countersData = countersDoc.data() ?? {};
      Map<String, int> currentCounters = {};
      final prefixes = {'HH', 'TP', 'DV', 'BK', 'NL', 'VL', 'SP'};

      for (final prefix in prefixes) {
        int dbCount = (countersData['${prefix}_count'] as num?)?.toInt() ?? 0;
        if (dbCount == 0) {
          int maxInDb = 0;
          for (final product in allProducts) {
            if (product.productCode?.startsWith(prefix) == true) {
              final n = extractNumericCode(product.productCode!, prefix);
              if (n > maxInDb) maxInDb = n;
            }
          }
          int maxInExcel = 0;
          if (headerMap.containsKey('Mã SP')) {
            final idx = headerMap['Mã SP']!;
            for (int i=1; i<sheet.rows.length; i++) {
              final v = sheet.rows[i][idx]?.value?.toString().trim();
              if (v != null && v.startsWith(prefix)) {
                final n = extractNumericCode(v, prefix);
                if (n > maxInExcel) maxInExcel = n;
              }
            }
          }
          currentCounters[prefix] = maxInDb > maxInExcel ? maxInDb : maxInExcel;
        } else {
          currentCounters[prefix] = dbCount;
        }
      }

      for (final job in jobsToProcess) {
        if (job.existingProduct == null && job.data['productCode'] == null) {
          final prefix = _getProductPrefix(job.data['productType']) ?? 'SP';
          final nextCount = (currentCounters[prefix] ?? 0) + 1;
          job.data['productCode'] = '$prefix${nextCount.toString().padLeft(5, '0')}';
          currentCounters[prefix] = nextCount;
        }
      }

      // 6. PHA 3: LƯU SẢN PHẨM
      if (mounted) setState(() => _statusText = 'Đang lưu ${jobsToProcess.length} sản phẩm...');

      var batch = FirebaseFirestore.instance.batch();
      int batchCount = 0;

      // Map<ID, TaxKey?>. Nếu TaxKey là null nghĩa là XÓA thuế (đối với thuế 0%)
      final Map<String, String?> productTaxUpdates = {};

      for (int i = 0; i < jobsToProcess.length; i++) {
        final job = jobsToProcess[i];
        final data = job.data;

        // Default values
        data['isVisibleInMenu'] ??= true;
        data['manageStockSeparately'] ??= false;
        data['kitchenPrinters'] ??= ['Máy in A'];
        data['sellPrice'] ??= 0.0;
        data['costPrice'] ??= 0.0;
        data['stock'] ??= 0.0;
        data['minStock'] ??= 0.0;
        data['additionalBarcodes'] ??= [];
        data['additionalUnits'] ??= [];
        data['recipeItems'] ??= [];
        data['accompanyingItems'] ??= [];

        String productId;

        if (job.existingProduct != null) {
          updatedCount++;
          productId = job.existingProduct!.id;
          batch.update(FirebaseFirestore.instance.collection('products').doc(productId), data);
        } else {
          newCount++;
          data['storeId'] = storeId;
          data['ownerUid'] = widget.currentUser.uid;
          data['createdAt'] = FieldValue.serverTimestamp();

          String? imageUrl;
          if (data['productName'] != null) {
            imageUrl = await _storageService.findMatchingSharedImage(data['productName'].toString());
          }
          data['imageUrl'] = imageUrl;

          final docRef = FirebaseFirestore.instance.collection('products').doc();
          productId = docRef.id;
          batch.set(docRef, data);
        }

        // --- [LOGIC MỚI] XỬ LÝ THUẾ ---
        if (job.taxPercent != null) {
          final rateVal = job.taxPercent! / 100.0;

          if (rateVal < 0.001) {
            // Trường hợp Thuế = 0%: Đánh dấu là null để XÓA khỏi DB thuế
            productTaxUpdates[productId] = null;
          } else {
            // Trường hợp Thuế > 0%: Tìm key và đánh dấu để UPDATE
            String? matchedKey;
            final targetMap = (taxMethod == 'deduction') ? kDeductionRates : kDirectRates;
            for (var entry in targetMap.entries) {
              final dbRate = (entry.value['rate'] as num).toDouble();
              if ((dbRate - rateVal).abs() < 0.001) {
                matchedKey = entry.key;
                break;
              }
            }
            if (matchedKey != null) {
              productTaxUpdates[productId] = matchedKey;
            }
          }
        }

        batchCount++;
        if (batchCount >= 400) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
          batchCount = 0;
        }
      }

      if (batchCount > 0) {
        await batch.commit();
      }

      // 7. CẬP NHẬT THUẾ (KHÔNG DÙNG TRANSACTION)
      if (productTaxUpdates.isNotEmpty) {
        if (mounted) setState(() => _statusText = 'Đang cập nhật thuế...');

        // Delay nhẹ để giảm tải thread
        await Future.delayed(const Duration(milliseconds: 200));

        final docRef = FirebaseFirestore.instance.collection('store_tax_settings').doc(storeId);

        try {
          // 1. Đọc
          final snapshot = await docRef.get();

          if (snapshot.exists) {
            Map<String, dynamic> currentMap = Map<String, dynamic>.from(snapshot.data()?['taxAssignmentMap'] ?? {});
            Map<String, Set<String>> typedMap = {};

            // Ép kiểu an toàn
            currentMap.forEach((k, v) {
              if (v is List) {
                typedMap[k] = v.map((e) => e.toString()).toSet();
              }
            });

            // 2. Xử lý logic Update
            productTaxUpdates.forEach((productId, newTaxKey) {
              // Bước A: Luôn xóa ID khỏi tất cả các nhóm thuế cũ (Dù là 0% hay >0% đều phải xóa cũ trước)
              typedMap.forEach((key, idSet) {
                idSet.remove(productId);
              });

              // Bước B: Chỉ thêm vào nhóm mới nếu newTaxKey KHÁC NULL (Tức là > 0%)
              if (newTaxKey != null) {
                if (!typedMap.containsKey(newTaxKey)) {
                  typedMap[newTaxKey] = {};
                }
                typedMap[newTaxKey]!.add(productId);
              }
            });

            // 3. Chuyển lại Map để lưu
            Map<String, List<String>> finalMap = {};
            typedMap.forEach((k, v) {
              if (v.isNotEmpty) finalMap[k] = v.toList();
            });

            // 4. Ghi (Update)
            await docRef.update({'taxAssignmentMap': finalMap});
          }
        } catch (e) {
          toastService.show(message: "Lỗi cập nhật thuế: $e", type: ToastType.warning);
        }
      }

      // 8. CẬP NHẬT COUNTERS
      try {
        final Map<String, dynamic> newCountersData = {};
        currentCounters.forEach((prefix, value) {
          newCountersData['${prefix}_count'] = value;
        });
        await countersRef.set(newCountersData, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Counter update error: $e');
      }

      toastService.show(
        message: 'Hoàn tất! Thêm: $newCount, Sửa: $updatedCount, Bỏ qua: $skippedCount.',
        type: ToastType.success,
        duration: const Duration(seconds: 5),
      );

    } catch (e) {
      toastService.show(message: "Lỗi: $e", type: ToastType.error, duration: const Duration(seconds: 7));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusText = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.cloud_upload_outlined, size: 80, color: Colors.blue),
            const SizedBox(height: 16),
            const Text(
              'Nhập hàng hóa hàng loạt từ file Excel. Vui lòng sử dụng file mẫu được xuất từ chức năng "Xuất File" để đảm bảo đúng định dạng cột.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            Center(
              child: TextButton.icon(
                onPressed: _isLoading ? null : _downloadSampleFile,
                icon: const Icon(Icons.download),
                label: const Text('Tải file Excel mẫu'),
              ),
            ),
            const SizedBox(height: 24),
            CheckboxListTile(
              title: const Text('Cập nhật hàng hóa đã có'),
              subtitle: const Text('Ghi đè thông tin các hàng hóa đã có (dựa theo ID). Nếu tắt, sẽ bỏ qua các hàng hóa này.'),
              value: _updateExisting,
              onChanged: _isLoading ? null : (value) {
                setState(() {
                  _updateExisting = value ?? false;
                });
              },
            ),
            CheckboxListTile(
              title: const Text('Import Tồn kho & Giá vốn'),
              subtitle: const Text('Đọc dữ liệu: Tồn kho, Giá vốn, Tồn tối thiểu.'),
              value: _updateStockCost,
              onChanged: _isLoading ? null : (value) {
                setState(() => _updateStockCost = value ?? false);
              },
            ),
            CheckboxListTile(
              title: const Text('Cập nhật dữ liệu phức tạp (JSON)'),
              subtitle: const Text('Cập nhật: ĐVT phụ, Định lượng, Sản phẩm Bán kèm, Thiết lập Dịch vụ.'),
              value: _updateComplexData,
              onChanged: _isLoading ? null : (value) {
                setState(() => _updateComplexData = value ?? false);
              },
            ),
            const SizedBox(height: 24),
            if (_isLoading)
              Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_statusText, style: const TextStyle(fontStyle: FontStyle.italic)),
                ],
              )
            else
              ElevatedButton.icon(
                icon: const Icon(Icons.file_upload),
                label: const Text('Chọn file và Nhập'),
                onPressed: _importProducts,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }
}