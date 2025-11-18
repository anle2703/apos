// File: lib/screens/tables/qr_order_management_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:file_picker/file_picker.dart';

import '../../models/store_settings_model.dart';
import '../../models/table_group_model.dart';
import '../../models/table_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/settings_service.dart';
import '../../services/toast_service.dart';
import '../../theme/app_theme.dart';

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

class QrOrderManagementScreen extends StatefulWidget {
  final UserModel currentUser;

  const QrOrderManagementScreen({super.key, required this.currentUser});

  @override
  State<QrOrderManagementScreen> createState() =>
      _QrOrderManagementScreenState();
}

class _QrOrderManagementScreenState extends State<QrOrderManagementScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final SettingsService _settingsService = SettingsService();
  late StreamSubscription<StoreSettings> _settingsSub;

  late Future<List<TableGroupModel>> _tableGroupsFuture;
  bool _isLoadingSettings = true;
  bool _isGeneratingAll = false;
  bool _isQrOrderRequiresConfirmation = true;

  final String _qrOrderBaseUrl = "https://cash-bae5d.web.app/order";

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _settingsSub.cancel();
    super.dispose();
  }

  void _loadData() {
    _loadGroups();
    _loadSettings();
  }

  void _loadGroups() {
    _tableGroupsFuture =
        _firestoreService.getTableGroups(widget.currentUser.storeId);
  }

  void _loadSettings() {
    final settingsId = widget.currentUser.ownerUid ?? widget.currentUser.uid;
    _settingsSub =
        _settingsService.watchStoreSettings(settingsId).listen((settings) {
          if (mounted) {
            setState(() {
              _isQrOrderRequiresConfirmation = settings.qrOrderRequiresConfirmation ?? false;
              _isLoadingSettings = false;
            });
          }
        }, onError: (e) {
          debugPrint("Lỗi tải cài đặt: $e");
          if (mounted) setState(() => _isLoadingSettings = false);
        });
  }

  Future<void> _updateQrConfirmationMode(bool newValue) async {
    setState(() => _isQrOrderRequiresConfirmation = newValue);
    try {
      final settingsId = widget.currentUser.ownerUid ?? widget.currentUser.uid;
      await _settingsService.updateStoreSettings(settingsId, {
        'qrOrderRequiresConfirmation': newValue,
      });
      ToastService().show(
          message: "Cập nhật chế độ xác nhận thành công.",
          type: ToastType.success);
    } catch (e) {
      ToastService()
          .show(message: "Lỗi cập nhật: $e", type: ToastType.error);
      setState(() => _isQrOrderRequiresConfirmation = !newValue);
    }
  }

  Future<void> _generateAllQrTokens() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận'),
        content: const Text(
            'Tạo mã QR cho tất cả các bàn chưa có mã? (Các bàn đã có mã sẽ được giữ nguyên).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Hủy')),
          ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Tạo')),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isGeneratingAll = true);

    try {
      final allTables = await _firestoreService
          .getTablesStream(widget.currentUser.storeId, group: null)
          .first;

      final tablesToUpdate = allTables
          .where((t) => (t.qrToken == null || t.qrToken!.isEmpty) && t.id != 'web_ship_order' && t.id != 'web_schedule_order')
          .toList();

      if (tablesToUpdate.isEmpty) {
        ToastService().show(
            message: "Tất cả các bàn đã có mã QR.", type: ToastType.success);
        setState(() => _isGeneratingAll = false);
        return;
      }

      final batch = _firestoreService.batch();
      for (final table in tablesToUpdate) {
        final newToken = FirebaseFirestore.instance.collection('_').doc().id;
        final tableRef = _firestoreService.getTableReference(table.id);
        batch.update(tableRef, {'qrToken': newToken});
      }

      await batch.commit();
      ToastService().show(
          message: "Đã tạo thành công ${tablesToUpdate.length} mã QR mới.",
          type: ToastType.success);
    } catch (e) {
      ToastService()
          .show(message: "Lỗi tạo mã hàng loạt: $e", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isGeneratingAll = false);
    }
  }

  Future<void> _saveQrToFile(GlobalKey qrKey, String fileName) async {
    setState(() => _isGeneratingAll = true);

    try {
      // 2. Chuyển widget (RepaintBoundary) thành ảnh
      RenderRepaintBoundary boundary = qrKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0); // Tăng chất lượng
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception("Không thể tạo dữ liệu ảnh");
      Uint8List pngBytes = byteData.buffer.asUint8List();

      // 3. Sử dụng file_picker để mở dialog "Save As"
      final safeFileName = fileName.replaceAll(RegExp(r'[\\/*?:"<>|]'), '_');

      final String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Lưu mã QR',
        fileName: '$safeFileName.png',
        bytes: pngBytes,
        type: FileType.custom,
        allowedExtensions: ['png'],
      );

      if (outputFile != null) {
        ToastService().show(message: "Đã lưu mã QR thành công!", type: ToastType.success);
      } else {
        ToastService().show(message: "Đã hủy lưu file.", type: ToastType.warning);
      }

    } catch (e) {
      ToastService().show(message: "Lỗi khi lưu: $e", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isGeneratingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TableGroupModel>>(
      future: _tableGroupsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Quản lý QR Order')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Quản lý QR Order')),
            body: Center(child: Text('Lỗi tải nhóm bàn: ${snapshot.error}')),
          );
        }

        final tableGroups = snapshot.data ?? [];
        final groupNames = ['Tất cả', ...tableGroups.map((g) => g.name)];

        return DefaultTabController(
          length: groupNames.length,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Quản lý QR Order'),
              // --- XÓA ACTIONS Ở ĐÂY ---
              bottom: TabBar(
                isScrollable: true,
                tabs: groupNames.map((name) => Tab(text: name)).toList(),
              ),
            ),
            body: Column(
              children: [
                _isLoadingSettings
                    ? const LinearProgressIndicator()
                    : const SizedBox.shrink(),
                SwitchListTile(
                  title: const Text(
                    'Yêu cầu Thu ngân xác nhận',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(_isQrOrderRequiresConfirmation
                      ? 'Các đơn Order tại bàn phải được thu ngân xác nhận.'
                      : 'Các đơn Order tại bàn sẽ tự động gửi báo chế biến.'),
                  value: _isQrOrderRequiresConfirmation,
                  onChanged: _updateQrConfirmationMode,
                  activeThumbColor: AppTheme.primaryColor,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: const Text('Tạo QR cho tất cả bàn chưa có'),
                      onPressed: _isGeneratingAll ? null : _generateAllQrTokens,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                // --- KẾT THÚC THÊM NÚT ---
                Expanded(
                  child: TabBarView(
                    children: groupNames.map((name) {
                      final filterGroup = (name == 'Tất cả') ? null : name;
                      return _buildTableGridForGroup(filterGroup);
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTableGridForGroup(String? group) {
    return StreamBuilder<List<TableModel>>(
      stream: _firestoreService.getTablesStream(widget.currentUser.storeId,
          group: group),
      builder: (context, tableSnapshot) {
        if (tableSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (tableSnapshot.hasError) {
          return Center(
              child: Text('Lỗi tải danh sách bàn: ${tableSnapshot.error}'));
        }

        List<TableModel> tables = tableSnapshot.data ?? [];

        if (group == null) {
          final onlineTables = [
            TableModel(
                id: 'web_ship_order',
                storeId: widget.currentUser.storeId,
                tableName: 'Đặt Hàng',
                tableGroup: 'Online',
                stt: -2,
                serviceId: '',
                qrToken: 'ship_token'
            ),
            TableModel(
                id: 'web_schedule_order',
                storeId: widget.currentUser.storeId,
                tableName: 'Booking',
                tableGroup: 'Online',
                stt: -1,
                serviceId: '',
                qrToken: 'schedule_token'
            ),
          ];
          tables.addAll(onlineTables);
        }

        tables = tables
            .where((t) =>
        !t.id.startsWith('ship') && !t.id.startsWith('schedule'))
            .toList();

        if (tables.isEmpty) {
          return const Center(
              child: Text('Chưa có phòng/bàn nào trong nhóm này.'));
        }

        tables.sort((a, b) => a.stt.compareTo(b.stt));

        return GridView.builder(
          padding: const EdgeInsets.all(12.0),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 150,
            childAspectRatio: 1,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: tables.length,
          itemBuilder: (context, index) {
            final table = tables[index];
            return _QrTableCard(
              table: table,
              onTap: () => _showQrDialog(context, table),
            );
          },
        );
      },
    );
  }

  String _buildQrData(TableModel table) {
    final storeId = widget.currentUser.storeId;

    // Logic cho card đặc biệt
    if (table.id == 'web_ship_order') {
      return '$_qrOrderBaseUrl?store=$storeId&type=ship';
    }
    if (table.id == 'web_schedule_order') {
      return '$_qrOrderBaseUrl?store=$storeId&type=schedule';
    }

    // Logic cho bàn thường
    if (table.qrToken != null && table.qrToken!.isNotEmpty) {
      return '$_qrOrderBaseUrl?store=$storeId&token=${table.qrToken!}';
    }

    return ''; // Trả về rỗng nếu không có token (để QrImageView hiển thị lỗi)
  }

  Future<void> _showQrDialog(BuildContext context, TableModel table) async {
    String? currentToken = table.qrToken;
    bool isProcessing = false;

    final GlobalKey qrKey = GlobalKey();

    final bool isOnlineCard = table.id == 'web_ship_order' || table.id == 'web_schedule_order';

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateInDialog) {

            final tempTableForQr = TableModel(
              id: table.id,
              storeId: table.storeId,
              tableName: table.tableName,
              tableGroup: table.tableGroup,
              stt: table.stt,
              serviceId: table.serviceId,
              qrToken: currentToken,
            );

            final qrData = _buildQrData(tempTableForQr);
            final bool hasQr = qrData.isNotEmpty;

            return AlertDialog(
              // Giảm padding của tiêu đề
              titlePadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              // Giảm padding của nội dung
              contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              content: SizedBox(
                width: 250,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isProcessing)
                      const SizedBox(
                        height: 250,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    // --- SỬA LỖI 3: THÊM TÊN BÀN VÀO ẢNH ---
                    else if (hasQr)
                      SizedBox(
                        width: 250,
                        height: 250, // Giữ kích thước vuông
                        child: RepaintBoundary(
                          key: qrKey,
                          child: Container(
                            color: Colors.white, // Nền trắng cho ảnh PNG
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                  child: Text(
                                    table.tableName, // Tên bàn
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Expanded( // Mã QR
                                  child: QrImageView(
                                    data: qrData,
                                    version: QrVersions.auto,
                                    backgroundColor: Colors.white,
                                    padding: const EdgeInsets.all(12), // Thu nhỏ 1 chút
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    // --- KẾT THÚC SỬA LỖI 3 ---
                    else
                      SizedBox(
                        height: 250,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.qr_code,
                                  size: 80, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('Chưa tạo mã QR cho bàn này.'),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // --- SỬA LỖI 4: GOM NÚT VÀO 1 HÀNG NGANG ---
              actionsAlignment: MainAxisAlignment.center,
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              actions: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!isOnlineCard)
                      TextButton(
                        onPressed: isProcessing
                            ? null
                            : () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Xác nhận xóa'),
                              content:
                              const Text('Xóa mã QR sẽ vô hiệu hóa link order. Bạn có chắc?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Hủy')),
                                TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Xóa', style: TextStyle(color: Colors.red))),
                              ],
                            ),
                          );

                          if(confirmed != true) return;

                          setStateInDialog(() => isProcessing = true);
                          try {
                            await _firestoreService.updateTable(
                                table.id, {'qrToken': FieldValue.delete()});
                            ToastService().show(
                                message: "Đã xóa mã QR.",
                                type: ToastType.success);
                            setStateInDialog(() {
                              currentToken = null;
                              isProcessing = false;
                            });
                          } catch (e) {
                            ToastService().show(
                                message: "Lỗi khi xóa: $e",
                                type: ToastType.error);
                            setStateInDialog(() => isProcessing = false);
                          }
                        },
                        child: const Text('Xóa', style: TextStyle(color: Colors.red)),
                      ),

                    const SizedBox(width: 8),

                    ElevatedButton.icon(
                      icon: const Icon(Icons.save_alt_outlined, size: 18),
                      label: const Text('Lưu'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green, // Đổi màu
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      onPressed: (isProcessing || !hasQr)
                          ? null
                          : () => _saveQrToFile(qrKey, 'QR_${table.tableName}'),
                    ),

                    const SizedBox(width: 8),

                    if (!isOnlineCard)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text(currentToken != null ? 'Mã mới' : 'Tạo'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        onPressed: isProcessing
                            ? null
                            : () async {
                          setStateInDialog(() => isProcessing = true);
                          try {
                            final newToken = FirebaseFirestore.instance
                                .collection('_')
                                .doc()
                                .id;
                            await _firestoreService
                                .updateTable(table.id, {'qrToken': newToken});
                            ToastService().show(
                                message: "Đã tạo mã QR mới.",
                                type: ToastType.success);
                            setStateInDialog(() {
                              currentToken = newToken;
                              isProcessing = false;
                            });
                          } catch (e) {
                            ToastService().show(
                                message: "Lỗi khi tạo mã: $e",
                                type: ToastType.error);
                            setStateInDialog(() => isProcessing = false);
                          }
                        },
                      ),
                  ],
                ),
              ],
              // --- KẾT THÚC SỬA LỖI 4 ---
            );
          },
        );
      },
    );
  }
}

class _QrTableCard extends StatelessWidget {
  final TableModel table;
  final VoidCallback onTap;

  const _QrTableCard({required this.table, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    bool hasQr;
    if (table.id == 'web_ship_order' || table.id == 'web_schedule_order') {
      hasQr = true;
    } else {
      hasQr = table.qrToken != null && table.qrToken!.isNotEmpty;
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hasQr ? AppTheme.primaryColor : Colors.grey.shade300,
          width: 1.0,
        ),
      ),
      elevation: 2.0,
      shadowColor: Colors.black.withAlpha(25),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          // Giữ padding nhỏ để có không gian
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
          child: Column(
            // SỬA 1: Đổi lại thành .center để căn giữa
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                hasQr ? Icons.qr_code_2_rounded : Icons.qr_code_scanner_rounded,
                size: 40, // Giữ kích thước icon nhỏ
                color: hasQr ? AppTheme.primaryColor : Colors.grey.shade400,
              ),
              // Giữ khoảng cách nhỏ
              const SizedBox(height: 8),
              Text(
                table.tableName,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              // SỬA 2: Bỏ widget Expanded() đi
              Text(
                table.tableGroup,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall
                    ?.copyWith(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}