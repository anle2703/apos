import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  String generateStandardImageName(String productName) {
    String slug = productName.toLowerCase();
    slug = slug.replaceAll(RegExp(r'[àáạảãâầấậẩẫăằắặẳẵ]'), 'a');
    slug = slug.replaceAll(RegExp(r'[èéẹẻẽêềếệểễ]'), 'e');
    slug = slug.replaceAll(RegExp(r'[ìíịỉĩ]'), 'i');
    slug = slug.replaceAll(RegExp(r'[òóọỏõôồốộổỗơờớợởỡ]'), 'o');
    slug = slug.replaceAll(RegExp(r'[ùúụủũưừứựửữ]'), 'u');
    slug = slug.replaceAll(RegExp(r'[ỳýỵỷỹ]'), 'y');
    slug = slug.replaceAll(RegExp(r'[đ]'), 'd');
    slug = slug
        .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'_$'), '');
    return slug;
  }

  Future<String?> findMatchingSharedImage(String productName) async {
    final standardizedProductName = generateStandardImageName(productName);

    if (standardizedProductName.isEmpty) {
      return null;
    }

    debugPrint(
        "--- [StorageService] Đang tìm ảnh trực tiếp: $standardizedProductName");

    return await getSharedImageUrl(standardizedProductName);
  }

  Future<String?> getSharedImageUrl(String originalBaseName) async {
    const extensions = ['.png', '.jpg', '.jpeg', '.webp'];

    for (final ext in extensions) {
      try {
        final ref = _storage
            .ref()
            .child('shared_product_images/$originalBaseName$ext');
        final downloadUrl = await ref.getDownloadURL();
        debugPrint("--- [StorageService] Đã tìm thấy: $downloadUrl");
        return downloadUrl;
      } on FirebaseException catch (e) {
        if (e.code == 'object-not-found') {
          continue;
        }
        debugPrint("Lỗi Firebase Storage: ${e.message}");
      } catch (e) {
        debugPrint("Lỗi không xác định khi lấy ảnh dùng chung: $e");
      }
    }
    debugPrint(
        "--- [StorageService] Không tìm thấy file nào khớp: $originalBaseName");
    return null;
  }

  Future<String?> uploadStoreProductImage({
    required Uint8List imageBytes,
    required String storeId,
    required String fileName,
  }) async {
    try {
      final ref = _storage.ref().child('store_images/$storeId/$fileName.jpg');
      UploadTask uploadTask = ref.putData(imageBytes);
      final snapshot = await uploadTask.whenComplete(() => {});
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      debugPrint("Lỗi khi tải ảnh riêng lên: $e");
      return null;
    }
  }

  Future<void> deleteImageFromUrl(String imageUrl) async {
    if (!imageUrl.contains('firebasestorage.googleapis.com')) {
      return;
    }
    try {
      final Reference photoRef = _storage.refFromURL(imageUrl);
      await photoRef.delete();
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') {
      } else {
        debugPrint('Error deleting image: $e');
      }
    } catch (e) {
      debugPrint('An unexpected error occurred while deleting the image: $e');
    }
  }
}