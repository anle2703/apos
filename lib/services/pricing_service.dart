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
    final double initialPrice = timePricing.initialPrice; // [MỚI]
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

    // --- TÍNH TOÁN TỔNG THỜI GIAN CẦN THU TIỀN ---
    final double elapsedSeconds = totalDuration.inSeconds.toDouble();
    final int elapsedMinutesRoundedUp = (elapsedSeconds / 60).ceil();
    int numberOfCycles = (elapsedMinutesRoundedUp / priceUpdateInterval).ceil();
    if (numberOfCycles <= 0) {
      numberOfCycles = 1;
    }
    int totalMinutesBilled = numberOfCycles * priceUpdateInterval;

    // Đảm bảo thời gian tính tiền không nhỏ hơn thời gian tối thiểu
    if (totalMinutesBilled < initialDurationMinutes) {
      totalMinutesBilled = initialDurationMinutes;
    }

    final billableEndTime =
    serviceStartTime.add(Duration(minutes: totalMinutesBilled));

    final List<TimeBlock> blocks = [];
    double totalCost = 0;

    // --- [LOGIC MỚI] XỬ LÝ GIÁ TỐI THIỂU ---

    // Biến con trỏ thời gian để bắt đầu tính các block tiếp theo
    DateTime calculationCursor = serviceStartTime;

    // Nếu có giá tối thiểu, ta tạo ngay 1 block đầu tiên
    if (initialPrice > 0) {
      // Thời gian áp dụng giá tối thiểu (ví dụ: 60 phút đầu)
      // Nếu initialDurationMinutes = 0 thì coi như phí mở cửa (flagfall) cộng thêm
      int initialMinutes = initialDurationMinutes > 0 ? initialDurationMinutes : 0;

      // Thời gian kết thúc của block mở cửa
      DateTime initialBlockEndTime = serviceStartTime.add(Duration(minutes: initialMinutes));

      // Thêm block giá tối thiểu
      blocks.add(TimeBlock(
        label: "Giá mở cửa / Tối thiểu",
        startTime: serviceStartTime,
        endTime: initialBlockEndTime,
        ratePerHour: 0, // Không quan trọng vì cost cố định
        minutes: initialMinutes,
        cost: initialPrice,
      ));

      totalCost += initialPrice;

      // Cập nhật con trỏ để tính phần thời gian còn lại (nếu có)
      calculationCursor = initialBlockEndTime;
    }

    // --- TÍNH TOÁN PHẦN THỜI GIAN CÒN LẠI (NẾU CÓ) ---
    // Chỉ chạy nếu thời gian kết thúc tính tiền > thời gian đã tính ở block mở cửa
    if (calculationCursor.isBefore(billableEndTime)) {

      final double baseRatePerHour = product.sellPrice;
      final timeFrames = timePricing.timeFrames.map((e) => e.toMap()).toList();

      // Tạo các mốc sự kiện (Event Times) cho khoảng thời gian còn lại
      final List<DateTime> eventTimes = [calculationCursor];

      for (final frame in timeFrames) {
        final startTimeParts = (frame['startTime'] as String).split(':');
        final endTimeParts = (frame['endTime'] as String).split(':');
        for (int dayOffset = -1; dayOffset <= 1; dayOffset++) {
          final day = serviceEndTime.add(Duration(days: dayOffset));
          final start = DateTime(day.year, day.month, day.day,
              int.parse(startTimeParts[0]), int.parse(startTimeParts[1]));
          final end = DateTime(day.year, day.month, day.day,
              int.parse(endTimeParts[0]), int.parse(endTimeParts[1]));

          // Chỉ thêm mốc nếu nó nằm trong khoảng thời gian CÒN LẠI cần tính
          if (start.isAfter(calculationCursor) && start.isBefore(billableEndTime)) {
            eventTimes.add(start);
          }
          if (end.isAfter(calculationCursor) && end.isBefore(billableEndTime)) {
            eventTimes.add(end);
          }
        }
      }
      eventTimes.add(billableEndTime);
      eventTimes.sort();
      final uniqueEventTimes = eventTimes.toSet().toList();

      for (int i = 0; i < uniqueEventTimes.length - 1; i++) {
        final blockStartTime = uniqueEventTimes[i];
        DateTime blockEndTime = uniqueEventTimes[i + 1];

        if (blockStartTime.isAtSameMomentAs(blockEndTime) ||
            blockStartTime.isAfter(blockEndTime)) {
          continue;
        }

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
        final minutesInBlock = (durationOfBlock.inSeconds / 60).round();

        if (minutesInBlock <= 0) continue;

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
    }

    final finalTotalCost = totalCost.round().toDouble();

    return TimePricingResult(
      totalPrice: finalTotalCost,
      blocks: blocks,
      totalDuration: totalDuration,
      totalMinutesBilled: totalMinutesBilled,
    );
  }
}
