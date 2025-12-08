import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/quick_note_model.dart';
import '../models/user_model.dart';
import '../models/product_model.dart';
import '../services/firestore_service.dart';
import '../services/toast_service.dart'; // Giả định bạn có file này
import '../theme/app_theme.dart'; // Giả định bạn có file này
import '../widgets/product_search_delegate.dart'; // File bạn đã cung cấp

class QuickNotesScreen extends StatefulWidget {
  final UserModel currentUser;

  const QuickNotesScreen({super.key, required this.currentUser});

  @override
  State<QuickNotesScreen> createState() => _QuickNotesScreenState();
}

class _QuickNotesScreenState extends State<QuickNotesScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  late Stream<List<QuickNoteModel>> _notesStream;

  @override
  void initState() {
    super.initState();
    _notesStream =
        _firestoreService.getQuickNotes(widget.currentUser.storeId);
  }

  void _showEditDialog({QuickNoteModel? note}) {
    showDialog(
      context: context,
      builder: (context) => _QuickNoteEditDialog(
        currentUser: widget.currentUser,
        firestoreService: _firestoreService,
        existingNote: note,
      ),
    );
  }

  Future<void> _deleteNote(QuickNoteModel note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa ghi chú "${note.noteText}" không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _firestoreService.deleteQuickNote(note.id);
        ToastService().show(message: 'Đã xóa ghi chú', type: ToastType.success);
      } catch (e) {
        ToastService()
            .show(message: 'Lỗi khi xóa: $e', type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý Ghi chú nhanh'),
      ),
      body: StreamBuilder<List<QuickNoteModel>>(
        stream: _notesStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Lỗi: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
                child: Text('Chưa có ghi chú nhanh nào.\nBấm + để thêm mới.'));
          }

          final notes = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
              return Card(
                child: ListTile(
                  title: Text(note.noteText),
                  subtitle: Text(note.productIds.isEmpty
                      ? 'Áp dụng cho tất cả sản phẩm'
                      : 'Áp dụng cho ${note.productIds.length} sản phẩm'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon:
                        const Icon(Icons.edit_outlined, color: Colors.blue),
                        onPressed: () => _showEditDialog(note: note),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.red),
                        onPressed: () => _deleteNote(note),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditDialog(),
        backgroundColor: AppTheme.primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class _QuickNoteEditDialog extends StatefulWidget {
  final UserModel currentUser;
  final FirestoreService firestoreService;
  final QuickNoteModel? existingNote;

  const _QuickNoteEditDialog({
    required this.currentUser,
    required this.firestoreService,
    this.existingNote,
  });

  @override
  State<_QuickNoteEditDialog> createState() => _QuickNoteEditDialogState();
}

class _QuickNoteEditDialogState extends State<_QuickNoteEditDialog> {
  final _textController = TextEditingController();
  List<ProductModel> _selectedProducts = [];
  bool _isLoadingProducts = false;

  // 1. ĐỊNH NGHĨA DANH SÁCH CÁC LOẠI ĐƯỢC PHÉP HIỂN THỊ (Loại bỏ Nguyên liệu/Vật liệu)
  final List<String> _allowedSalesTypes = [
    'Hàng hóa',
    'Topping/Bán kèm',
    'Dịch vụ',
    'Dịch vụ/Tính giờ',
    'Combo',
    'Thành phẩm/Combo' // Thêm các loại hình kinh doanh của bạn vào đây
  ];

  @override
  void initState() {
    super.initState();
    if (widget.existingNote != null) {
      _textController.text = widget.existingNote!.noteText;
      if (widget.existingNote!.productIds.isNotEmpty) {
        _loadInitialProducts(widget.existingNote!.productIds);
      }
    }
  }

  Future<void> _loadInitialProducts(List<String> productIds) async {
    setState(() => _isLoadingProducts = true);
    try {
      final allProducts = await widget.firestoreService
          .getAllProductsStream(widget.currentUser.storeId)
          .first;

      final loadedProducts = allProducts
          .where((p) => productIds.contains(p.id))
      // 2. LỌC DANH SÁCH ĐÃ GÁN (Chỉ lấy những loại nằm trong danh sách cho phép)
          .where((p) => _allowedSalesTypes.contains(p.productType))
          .toList();

      if (mounted) {
        setState(() {
          _selectedProducts = loadedProducts;
        });
      }
    } catch (e) {
      ToastService().show(message: 'Lỗi tải SP đã gán: $e', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _isLoadingProducts = false);
      }
    }
  }

  Future<void> _pickProducts() async {
    final result = await ProductSearchScreen.showMultiSelect(
      context: context,
      currentUser: widget.currentUser,
      previouslySelected: _selectedProducts,
      groupByCategory: true,

      // 3. TRUYỀN THAM SỐ LỌC VÀO ĐÂY (Giống bên màn hình Nhập hàng)
      allowedProductTypes: _allowedSalesTypes,
      // -----------------------------------------------------------
    );

    if (result != null) {
      setState(() {
        _selectedProducts = result;
      });
    }
  }

  Future<void> _saveNote() async {
    final noteText = _textController.text.trim();
    if (noteText.isEmpty) {
      ToastService().show(
          message: 'Nội dung ghi chú không được để trống',
          type: ToastType.warning);
      return;
    }

    try {
      final productIds = _selectedProducts.map((p) => p.id).toList();
      final now = Timestamp.now();

      final noteToSave = QuickNoteModel(
        id: widget.existingNote?.id ?? '', // ID rỗng nếu tạo mới
        storeId: widget.currentUser.storeId,
        noteText: noteText,
        productIds: productIds,
        createdAt: widget.existingNote?.createdAt ?? now,
      );

      await widget.firestoreService.saveQuickNote(noteToSave);

      ToastService().show(
          message: 'Đã lưu ghi chú thành công', type: ToastType.success);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      ToastService()
          .show(message: 'Lỗi khi lưu: $e', type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
          widget.existingNote == null ? 'Ghi chú nhanh mới' : 'Sửa ghi chú'),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _textController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nội dung ghi chú',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _pickProducts,
                icon: const Icon(Icons.list_alt_outlined),
                label: const Text('Gán cho sản phẩm'),
              ),
              const SizedBox(height: 8),
              Text(
                _selectedProducts.isEmpty
                    ? 'Ghi chú này sẽ hiển thị cho TẤT CẢ sản phẩm.'
                    : 'Áp dụng cho ${_selectedProducts.length} sản phẩm:',
                style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: _selectedProducts.isEmpty ? Colors.red : null),
              ),
              const SizedBox(height: 8),
              if (_isLoadingProducts)
                const Center(child: CircularProgressIndicator())
              else if (_selectedProducts.isNotEmpty)
                Wrap(
                  spacing: 6.0,
                  runSpacing: 4.0,
                  children: _selectedProducts.map((product) {
                    return Chip(
                      label: Text(product.productName),
                      onDeleted: () {
                        setState(() {
                          _selectedProducts
                              .removeWhere((p) => p.id == product.id);
                        });
                      },
                    );
                  }).toList(),
                )
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          onPressed: _saveNote,
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}