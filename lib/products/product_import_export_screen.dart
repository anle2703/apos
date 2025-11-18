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
  // ... code không đổi ...
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

      final excel = Excel.createExcel();
      final Sheet sheet = excel[excel.getDefaultSheet()!];

      sheet.appendRow(_headers.map((header) => TextCellValue(header)).toList());

      for (final product in products) {
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

// --- Lớp Helper để chứa dữ liệu tạm thời ---
class _ProductImportJob {
  final Map<String, dynamic> data;
  final ProductModel? existingProduct;
  final String? idFromFile; // id từ file Excel
  final int excelRow;

  _ProductImportJob({
    required this.data,
    this.existingProduct,
    this.idFromFile,
    required this.excelRow,
  });
}


// --- TAB NHẬP FILE (Đã sửa đổi toàn bộ) ---
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

  Future<void> _importProducts() async {
    setState(() {
      _isLoading = true;
      _statusText = 'Đang chọn file...';
    });
    final toastService = ToastService();
    final storeId = widget.currentUser.storeId;

    // Các loại SP hợp lệ
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
        setState(() => _isLoading = false);
        return;
      }

      // 2. ĐỌC FILE VÀ HEADER
      setState(() => _statusText = 'Đang đọc file Excel...');
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

      // 3. TẢI DỮ LIỆU HIỆN CÓ (ĐỂ SO SÁNH)
      setState(() => _statusText = 'Đang lấy dữ liệu hiện tại...');
      final allProducts = await _firestoreService.getAllProductsStream(storeId).first;
      final productMapByCode = <String, ProductModel>{};
      final productMapById = <String, ProductModel>{};
      for (var p in allProducts) {
        if (p.productCode != null && p.productCode!.isNotEmpty) {
          productMapByCode[p.productCode!] = p;
        }
        productMapById[p.id] = p;
      }

      final allGroupsSnapshot = await FirebaseFirestore.instance
          .collection('product_groups').where('storeId', isEqualTo: storeId).get();
      final existingGroupNames = allGroupsSnapshot.docs
          .map((doc) => doc.data()['name'] as String).toSet();

      // 4. PHA 1: XÁC THỰC (VALIDATION)
      setState(() => _statusText = 'Đang xác thực dữ liệu...');
      final List<_ProductImportJob> jobsToProcess = [];
      final Set<String> newGroupNamesToCreate = {};
      final Set<String> skusInFile = {}; // Kiểm tra trùng lặp SKU trong file

      int skippedCount = 0;
      int newCount = 0;
      int updatedCount = 0;

      // Bắt đầu từ hàng 1 (dòng 2 trong Excel)
      for (int i = 1; i < sheet.rows.length; i++) {
        final int excelRow = i + 1;
        final row = sheet.rows[i];

        // Hàm helper để đọc cell
        dynamic getCell(String headerName) {
          if (!headerMap.containsKey(headerName) || headerMap[headerName]! >= row.length) {
            return null;
          }
          return row[headerMap[headerName]!]?.value;
        }

        // --- Bắt đầu kiểm tra ---
        final productName = parseString(getCell('Tên sản phẩm'));
        if (productName == null) continue; // Bỏ qua hàng trống

        final String? id = parseString(getCell('ID (Không sửa)'));
        final String? code = parseString(getCell('Mã SP'));
        final String? productType = parseString(getCell('Loại SP'));

        // 1. Kiểm tra Loại SP
        if (productType == null) {
          throw Exception("Dòng $excelRow: 'Loại SP' không được để trống.");
        }
        if (!allowedProductTypes.contains(productType)) {
          throw Exception("Dòng $excelRow: 'Loại SP' không hợp lệ: '$productType'.");
        }

        // 2. Kiểm tra trùng lặp SKU trong file
        if (code != null) {
          if (skusInFile.contains(code)) {
            throw Exception("Dòng $excelRow: 'Mã SP' ($code) bị lặp lại trong file Excel.");
          }
          skusInFile.add(code);
        }

        // 3. Tìm sản phẩm hiện có (CHỈ DỰA VÀO ID)
        ProductModel? existingProduct;
        if (id != null) {
          existingProduct = productMapById[id];
        }

        // 3.1. Kiểm tra trùng lặp Mã SP với CSDL (QUAN TRỌNG)
        if (code != null) {
          final productWithThisCode = productMapByCode[code];
          if (productWithThisCode != null) {
            // Đã tìm thấy Mã SP này trong CSDL
            if (existingProduct == null) {
              // Đây là SẢN PHẨM MỚI (vì không có ID), nhưng Mã SP lại trùng
              throw Exception("Dòng $excelRow: 'Mã SP' ($code) đã tồn tại cho một sản phẩm khác. Sản phẩm mới phải có Mã SP duy nhất hoặc để trống để tự tạo.");
            } else if (existingProduct.id != productWithThisCode.id) {
              // Đây là SẢN PHẨM CẬP NHẬT (vì có ID), nhưng Mã SP lại trùng với một SP KHÁC
              throw Exception("Dòng $excelRow: 'Mã SP' ($code) bạn đang cố cập nhật đã thuộc về một sản phẩm khác (ID: ${productWithThisCode.id}).");
            }
            // Nếu "existingProduct.id == productWithThisCode.id", thì đây là chính nó, không có vấn đề.
          }
        }


        if (existingProduct != null && !_updateExisting) {
          skippedCount++;
          continue;
        }

        // 4. Parse dữ liệu và lưu vào job
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

        // 5. Chuẩn bị tạo nhóm
        final String? groupNameFromExcel = productData['productGroup'] as String?;
        if (groupNameFromExcel != null && !existingGroupNames.contains(groupNameFromExcel)) {
          newGroupNamesToCreate.add(groupNameFromExcel);
        }

        jobsToProcess.add(_ProductImportJob(
          data: productData,
          existingProduct: existingProduct,
          idFromFile: id,
          excelRow: excelRow,
        ));
      }

      // 5. PHA 2: KHỞI TẠO MÃ SP VÀ NHÓM MỚI
      setState(() => _statusText = 'Đang khởi tạo Mã SP và Nhóm...');

      // 5.1 Tạo nhóm mới
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
        existingGroupNames.addAll(newGroupNamesToCreate); // Thêm vào danh sách để không tạo lại
      }

      // SỬA LINT: Hàm helper được định nghĩa bên trong hàm _importProducts,
      // và đổi tên, bỏ dấu gạch dưới
      int extractNumericCode(String code, String prefix) {
        if (code.startsWith(prefix)) {
          final numericPart = code.substring(prefix.length);
          return int.tryParse(numericPart) ?? 0;
        }
        return 0;
      }

      // 5.2 Lấy và cập nhật counters (LOGIC TÌM MAX)
      final countersRef = FirebaseFirestore.instance.collection('counters').doc('product_codes_$storeId');
      final countersDoc = await countersRef.get();
      final countersData = countersDoc.data() ?? {};

      Map<String, int> currentCounters = {};
      final prefixes = {'HH', 'TP', 'DV', 'BK', 'NL', 'VL', 'SP'};

      for (final prefix in prefixes) {
        int counterFromFirestore = (countersData['${prefix}_count'] as num?)?.toInt() ?? 0;

        if (counterFromFirestore == 0) {
          // Nếu counter trên DB = 0, tìm max trong DB và Excel
          int maxInDb = 0;
          for (final product in allProducts) {
            if (product.productCode != null && product.productCode!.startsWith(prefix)) {
              final codeNum = extractNumericCode(product.productCode!, prefix);
              if (codeNum > maxInDb) {
                maxInDb = codeNum;
              }
            }
          }

          int maxInExcel = 0;
          if (headerMap.containsKey('Mã SP')) {
            final codeIndex = headerMap['Mã SP']!;
            for (int i = 1; i < sheet.rows.length; i++) {
              final row = sheet.rows[i];
              if (codeIndex >= row.length) continue;
              final cell = row[codeIndex];
              if (cell != null) {
                final code = cell.value?.toString().trim();
                if (code != null && code.startsWith(prefix)) {
                  final codeNum = extractNumericCode(code, prefix);
                  if (codeNum > maxInExcel) {
                    maxInExcel = codeNum;
                  }
                }
              }
            }
          }

          currentCounters[prefix] = maxInDb > maxInExcel ? maxInDb : maxInExcel;
        } else {
          // Nếu counter trên DB > 0, dùng số đó
          currentCounters[prefix] = counterFromFirestore;
        }
      }

      for (final job in jobsToProcess) {
        // Chỉ gán Mã SP nếu: là sản phẩm mới (không có existingProduct) VÀ Mã SP trong file bị trống
        if (job.existingProduct == null && job.data['productCode'] == null) {

          // SỬA LINT: Sử dụng hàm _getProductPrefix (đã có ở ngoài)
          final prefix = _getProductPrefix(job.data['productType']) ?? 'SP';
          final nextCount = (currentCounters[prefix] ?? 0) + 1;

          job.data['productCode'] = '$prefix${nextCount.toString().padLeft(5, '0')}';

          currentCounters[prefix] = nextCount; // Cập nhật số đếm
        }
      }

      // 6. PHA 3: BATCH COMMIT
      setState(() => _statusText = 'Đang lưu ${jobsToProcess.length} sản phẩm...');
      var batch = FirebaseFirestore.instance.batch();
      int batchCount = 0;

      for (final job in jobsToProcess) {
        final data = job.data;

        // --- Áp dụng giá trị MẶC ĐỊNH ---
        data['isVisibleInMenu'] = data['isVisibleInMenu'] ?? true;
        data['manageStockSeparately'] = data['manageStockSeparately'] ?? false;
        if (data['kitchenPrinters'] == null || (data['kitchenPrinters'] as List).isEmpty) {
          data['kitchenPrinters'] = ['Máy in A'];
        }
        data['sellPrice'] = data['sellPrice'] ?? 0.0;
        data['costPrice'] = data['costPrice'] ?? 0.0;
        data['stock'] = data['stock'] ?? 0.0;
        data['minStock'] = data['minStock'] ?? 0.0;
        data['additionalBarcodes'] = data['additionalBarcodes'] ?? [];
        data['additionalUnits'] = data['additionalUnits'] ?? [];
        data['recipeItems'] = data['recipeItems'] ?? [];
        data['accompanyingItems'] = data['accompanyingItems'] ?? [];

        if (job.existingProduct != null) {
          // --- CẬP NHẬT SẢN PHẨM ---
          updatedCount++;
          final docRef = FirebaseFirestore.instance.collection('products').doc(job.existingProduct!.id);
          batch.update(docRef, data);
        } else {
          // --- TẠO MỚI SẢN PHẨM ---
          newCount++;
          data['storeId'] = storeId;
          data['ownerUid'] = widget.currentUser.uid;
          data['createdAt'] = FieldValue.serverTimestamp();

          String? imageUrl;
          if (data['productName'] != null) {
            imageUrl = await _storageService.findMatchingSharedImage(data['productName'].toString());
          }
          data['imageUrl'] = imageUrl;

          final DocumentReference docRef;
          // Ưu tiên ID từ file nếu có (cho trường hợp import lại file cũ đã xóa sp)
          if (job.idFromFile != null && !productMapById.containsKey(job.idFromFile)) {
            docRef = FirebaseFirestore.instance.collection('products').doc(job.idFromFile);
          } else {
            docRef = FirebaseFirestore.instance.collection('products').doc();
          }
          batch.set(docRef, data);
        }

        batchCount++;
        if (batchCount >= 400) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
          batchCount = 0;
        }
      }

      // Commit batch cuối
      if (batchCount > 0) {
        await batch.commit();
      }

      // 7. CẬP NHẬT COUNTERS MỚI
      final Map<String, dynamic> newCountersData = {};

      // SỬA LINT: đổi tên 'count' thành 'value'
      currentCounters.forEach((prefix, value) {
        newCountersData['${prefix}_count'] = value;
      });
      await countersRef.set(newCountersData, SetOptions(merge: true));

      toastService.show(
        message: 'Hoàn tất! Thêm mới: $newCount, Cập nhật: $updatedCount, Bỏ qua: $skippedCount. Đã tạo: ${newGroupNamesToCreate.length} nhóm mới.',
        type: ToastType.success,
        duration: const Duration(seconds: 5),
      );

    } catch (e) {
      toastService.show(message: "$e", type: ToastType.error, duration: const Duration(seconds: 7));
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