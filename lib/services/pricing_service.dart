// File: lib/services/pricing_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/product_model.dart';
import '../models/service_setup_model.dart';

class TimeBlock {
  final String label;
  final DateTime startTime;
  final DateTime endTime;
  final double ratePerHour;
  final int minutes;
  final double cost;

  Duration get duration => Duration(minutes: minutes);

  TimeBlock({
    required this.label,
    required this.startTime,
    required this.endTime,
    required this.ratePerHour,
    required this.minutes,
    required this.cost,
  });

  /// PHƯƠNG THỨC MỚI: Chuyển đổi đối tượng thành Map để lưu vào Firestore
  Map<String, dynamic> toMap() {
    return {
      'label': label,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'ratePerHour': ratePerHour,
      'minutes': minutes,
      'cost': cost,
    };
  }

  /// HÀM TẠO MỚI: Tạo đối tượng TimeBlock từ Map lấy từ Firestore
  factory TimeBlock.fromMap(Map<String, dynamic> map) {
    return TimeBlock(
      label: map['label'] as String? ?? '',
      startTime: (map['startTime'] as Timestamp).toDate(),
      endTime: (map['endTime'] as Timestamp).toDate(),
      ratePerHour: (map['ratePerHour'] as num).toDouble(),
      minutes: (map['minutes'] as num).toInt(),
      cost: (map['cost'] as num).toDouble(),
    );
  }
}

class TimePricingResult {
  final double totalPrice;
  final List<TimeBlock> blocks;
  final Duration totalDuration;
  final int totalMinutesBilled;

  TimePricingResult({
    required this.totalPrice,
    required this.blocks,
    required this.totalDuration,
    required this.totalMinutesBilled,
  });
}

class TimeBasedPricingService {
  static double getAdjustmentForTime(TimeOfDay time,
      List<Map<String, dynamic>> timeFrames) {
    for (final frame in timeFrames) {
      final startTimeParts = (frame['startTime'] as String).split(':');
      final endTimeParts = (frame['endTime'] as String).split(':');
      final startTime = TimeOfDay(
          hour: int.parse(startTimeParts[0]),
          minute: int.parse(startTimeParts[1]));
      final endTime = TimeOfDay(
          hour: int.parse(endTimeParts[0]), minute: int.parse(endTimeParts[1]));
      final priceChange = (frame['priceChangeValue'] as num? ?? 0).toDouble();

      final nowInMinutes = time.hour * 60 + time.minute;
      final startInMinutes = startTime.hour * 60 + startTime.minute;
      final endInMinutes = endTime.hour * 60 + endTime.minute;

      if (startInMinutes > endInMinutes) {
        if (nowInMinutes >= startInMinutes || nowInMinutes < endInMinutes){
          return priceChange;}
      } else {
        if (nowInMinutes >= startInMinutes && nowInMinutes < endInMinutes){
          return priceChange;}
      }
    }
    return 0.0;
  }

  static TimePricingResult calculatePriceWithBreakdown({
    required ProductModel product,
    required Timestamp startTime,
    bool isPaused = false,
    Timestamp? pausedAt,
    required int totalPausedDurationInSeconds,
  }) {
    final serviceSetup = product.serviceSetup;
    if (serviceSetup == null || serviceSetup['isTimeBased'] != true) {
      return TimePricingResult(
          totalPrice: product.sellPrice,
          blocks: [],
          totalDuration: Duration.zero,
          totalMinutesBilled: 0);
    }

    final timePricing = TimePricingModel.fromMap(
        serviceSetup['timePricing'] as Map<String, dynamic>? ?? {});
    final int initialDurationMinutes = timePricing.initialDurationMinutes;
    final int priceUpdateInterval = timePricing.priceUpdateInterval > 0
        ? timePricing.priceUpdateInterval
        : 1;

    final serviceStartTime = startTime.toDate();
    final now = DateTime.now();
    final serviceEndTime = isPaused ? pausedAt!.toDate() : now;
    final totalDuration = serviceEndTime.difference(serviceStartTime) -
        Duration(seconds: totalPausedDurationInSeconds);

    if (totalDuration.isNegative) {
      return TimePricingResult(
          totalPrice: 0,
          blocks: [],
          totalDuration: Duration.zero,
          totalMinutesBilled: 0);
    }

    // 1. Lấy tổng số giây thực tế đã trôi qua.
    final double elapsedSeconds = totalDuration.inSeconds.toDouble();

    // 2. Làm tròn lên thành số phút. Bất kỳ phần dư nào cũng được tính là 1 phút.
    final int elapsedMinutesRoundedUp = (elapsedSeconds / 60).ceil();

    // 3. Tính số chu kỳ thanh toán dựa trên số phút đã làm tròn (giống logic gốc).
    int numberOfCycles = (elapsedMinutesRoundedUp / priceUpdateInterval).ceil();

    // 4. Nếu dịch vụ vừa bắt đầu (0 chu kỳ), đảm bảo tính tiền cho ít nhất 1 chu kỳ.
    if (numberOfCycles <= 0) {
      numberOfCycles = 1;
    }

    // 5. Tổng số phút tính tiền là số chu kỳ * độ dài mỗi chu kỳ.
    int totalMinutesBilled = numberOfCycles * priceUpdateInterval;

    // 6. Áp dụng quy tắc về thời gian tối thiểu ban đầu (nếu có).
    if (totalMinutesBilled < initialDurationMinutes) {
      totalMinutesBilled = initialDurationMinutes;
    }

    final billableEndTime =
    serviceStartTime.add(Duration(minutes: totalMinutesBilled));

    final double baseRatePerHour = product.sellPrice;
    final List<DateTime> eventTimes = [serviceStartTime];
    final timeFrames = timePricing.timeFrames.map((e) => e.toMap()).toList();

    for (final frame in timeFrames) {
      final startTimeParts = (frame['startTime'] as String).split(':');
      final endTimeParts = (frame['endTime'] as String).split(':');
      for (int dayOffset = -1; dayOffset <= 1; dayOffset++) {
        final day = serviceEndTime.add(Duration(days: dayOffset));
        final start = DateTime(day.year, day.month, day.day,
            int.parse(startTimeParts[0]), int.parse(startTimeParts[1]));
        final end = DateTime(day.year, day.month, day.day,
            int.parse(endTimeParts[0]), int.parse(endTimeParts[1]));
        if (start.isAfter(serviceStartTime) && start.isBefore(billableEndTime)){
          eventTimes.add(start);}
        if (end.isAfter(serviceStartTime) && end.isBefore(billableEndTime)){
          eventTimes.add(end);}
      }
    }
    eventTimes.add(billableEndTime);
    eventTimes.sort();
    final uniqueEventTimes = eventTimes.toSet().toList();

    final List<TimeBlock> blocks = [];
    double totalCost = 0;

    for (int i = 0; i < uniqueEventTimes.length - 1; i++) {
      final blockStartTime = uniqueEventTimes[i];
      DateTime blockEndTime = uniqueEventTimes[i + 1];
      if (blockStartTime.isAtSameMomentAs(blockEndTime) ||
          blockStartTime.isAfter(blockEndTime)) {continue;}

      final midPoint =
      blockStartTime.add(blockEndTime.difference(blockStartTime) ~/ 2);
      double currentRate = baseRatePerHour;
      String currentLabel = "Giá bán mặc định";

      final midTimeOfDay = TimeOfDay.fromDateTime(midPoint);
      final adjustment = getAdjustmentForTime(midTimeOfDay, timeFrames);
      if (adjustment != 0) {
        currentRate += adjustment;
        currentLabel = adjustment > 0 ? "Giờ cao điểm" : "Giờ khuyến mãi";
      }

      final durationOfBlock = blockEndTime.difference(blockStartTime);
      // 1. Tính số phút để hiển thị (làm tròn toán học thông thường)
      final minutesInBlock = (durationOfBlock.inSeconds / 60).round();
      if (minutesInBlock <= 0) continue;

      // 2. Tính chi phí dựa trên SỐ GIÂY chính xác để không bị sai số
      final costForBlock = (currentRate / 3600) * durationOfBlock.inSeconds;

      totalCost += costForBlock;

      blocks.add(TimeBlock(
        label: currentLabel,
        startTime: blockStartTime,
        endTime: blockEndTime,
        ratePerHour: currentRate,
        minutes: minutesInBlock,
        cost: costForBlock,
      ));
    }

    // Để tránh sai số làm tròn của double, làm tròn tổng chi phí cuối cùng
    final finalTotalCost = (totalCost / 10).round() * 10;

    return TimePricingResult(
      totalPrice: finalTotalCost.toDouble(),
      blocks: blocks,
      totalDuration: totalDuration,
      totalMinutesBilled: totalMinutesBilled,
    );
  }
}
