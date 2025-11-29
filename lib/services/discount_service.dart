import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/discount_model.dart';
import '../models/product_model.dart';
import '../models/customer_model.dart';
import 'package:collection/collection.dart';
import 'dart:async';

class DiscountService {
  // 1. Tạo một "kênh phát thanh" (StreamController) dạng Broadcast để nhiều màn hình cùng nghe được
  static final StreamController<void> _discountUpdateController = StreamController<void>.broadcast();

  // 2. Getter để các màn hình khác lắng nghe
  static Stream<void> get onDiscountsChanged => _discountUpdateController.stream;

  // 3. Hàm để "Bắn tín hiệu" (Gọi hàm này sau khi bạn Lưu/Sửa khuyến mãi thành công)
  static void notifyDiscountsChanged() {
    _discountUpdateController.add(null);
  }

  Stream<List<DiscountModel>> getActiveDiscountsStream(String storeId) {
    final now = DateTime.now();
    return FirebaseFirestore.instance
        .collection('discounts') // Lưu ý: Nếu bạn lưu trong sub-collection của stores thì sửa đường dẫn lại
        .where('storeId', isEqualTo: storeId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => DiscountModel.fromFirestore(doc)).where((d) {
        // Filter thêm về thời gian startAt/endAt ở phía client cho chắc chắn
        if (d.startAt != null && d.startAt!.isAfter(now)) return false;
        if (d.endAt != null && d.endAt!.isBefore(now)) return false;
        return true;
      }).toList();
    });
  }

  DiscountItem? findBestDiscountForProduct({
    required ProductModel product,
    required List<DiscountModel> activeDiscounts,
    CustomerModel? customer,
    required DateTime checkTime,
  }) {
    DiscountItem? bestDiscountItem;
    double bestPrice = product.sellPrice;

    for (var discount in activeDiscounts) {
      if (discount.startAt != null && checkTime.isBefore(discount.startAt!)) continue;
      if (discount.endAt != null && checkTime.isAfter(discount.endAt!)) continue;
      if (!_isValidTimeFrame(discount, checkTime)) continue;
      if (!_isValidCustomer(discount, customer)) continue;

      final item = discount.items.firstWhereOrNull((i) => i.productId == product.id);
      if (item == null) continue;

      double currentPriceAfterDiscount;
      if (item.isPercent) {
        // [Safety] Clamp phần trăm từ 0-100
        double percent = item.value.clamp(0, 100);
        currentPriceAfterDiscount = product.sellPrice * (1 - percent / 100);
      } else {
        currentPriceAfterDiscount = product.sellPrice - item.value;
      }

      if (currentPriceAfterDiscount < 0) currentPriceAfterDiscount = 0;

      // [FIX] Thêm điều kiện (bestDiscountItem == null) để luôn lấy cái đầu tiên tìm thấy nếu chưa có
      // Dùng <= để đảm bảo cập nhật nếu giá ngang nhau nhưng cấu hình thay đổi
      if (currentPriceAfterDiscount < bestPrice || (bestDiscountItem == null && currentPriceAfterDiscount <= bestPrice)) {
        bestPrice = currentPriceAfterDiscount;
        bestDiscountItem = item;
      }
    }

    return bestDiscountItem;
  }

  bool _isValidTimeFrame(DiscountModel d, DateTime checkTime) {
    // Check ngày trong tuần
    if (d.daysOfWeek != null && d.daysOfWeek!.isNotEmpty) {
      if (!d.daysOfWeek!.contains(checkTime.weekday + 1)) return false;
    }

    // SỬA: Check danh sách khung giờ vàng (Nhiều mốc)
    if (d.dailyTimeRanges != null && d.dailyTimeRanges!.isNotEmpty) {
      bool isInAnyRange = false;
      final checkMin = checkTime.hour * 60 + checkTime.minute;

      for (var range in d.dailyTimeRanges!) {
        // Parse start/end từ String 'HH:mm'
        final startStr = range['start'];
        final endStr = range['end'];

        if (startStr != null && endStr != null) {
          final startParts = startStr.split(':');
          final endParts = endStr.split(':');

          final startMin = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
          final endMin = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);

          // Kiểm tra xem giờ hiện tại có nằm trong khoảng này không
          // Logic: start <= check <= end
          if (checkMin >= startMin && checkMin <= endMin) {
            isInAnyRange = true;
            break; // Nếu thỏa mãn 1 khung giờ thì OK luôn
          }
        }
      }

      // Nếu có cấu hình khung giờ mà giờ hiện tại không nằm trong bất kỳ khung nào -> False
      if (!isInAnyRange) return false;
    }

    return true;
  }

  // Helper check khách hàng
  bool _isValidCustomer(DiscountModel d, CustomerModel? c) {
    if (d.targetType == 'all') return true;
    if (d.targetType == 'retail' && c == null) return true; // Khách lẻ (không có info)
    if (d.targetType == 'group') {
      if (c == null) return false;
      // Kiểm tra xem khách có thuộc nhóm này không
      // Giả sử CustomerModel có field groupIds hoặc logic tương tự
      // return c.groupIds.contains(d.targetGroupId);
      return true; // Tạm thời return true để test
    }
    return false;
  }
}