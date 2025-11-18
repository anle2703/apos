// File: lib/models/service_setup_model.dart

import 'package:flutter/material.dart';

// Model cho một cặp giá trị-đơn vị hoa hồng
class CommissionValue {
  double value;
  String unit;

  CommissionValue({this.value = 0, this.unit = 'VND'});

  factory CommissionValue.fromMap(Map<String, dynamic> map) {
    return CommissionValue(
      value: (map['value'] as num?)?.toDouble() ?? 0,
      unit: map['unit'] ?? 'VND',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'value': value,
      'unit': unit,
    };
  }
}

// Model cho một khung giờ
class TimeFrameModel {
  TimeOfDay startTime;
  TimeOfDay endTime;
  double priceChangeValue;
  String priceChangeUnit;

  TimeFrameModel({
    required this.startTime,
    required this.endTime,
    this.priceChangeValue = 0,
    this.priceChangeUnit = 'VND',
  });

  factory TimeFrameModel.fromMap(Map<String, dynamic> map) {
    return TimeFrameModel(
      startTime: _stringToTimeOfDay(map['startTime'] ?? '00:00'),
      endTime: _stringToTimeOfDay(map['endTime'] ?? '00:00'),
      priceChangeValue: (map['priceChangeValue'] as num?)?.toDouble() ?? 0,
      priceChangeUnit: map['priceChangeUnit'] ?? 'VND',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'startTime': _timeOfDayToString(startTime),
      'endTime': _timeOfDayToString(endTime),
      'priceChangeValue': priceChangeValue,
      'priceChangeUnit': priceChangeUnit,
    };
  }

  // SỬA LỖI: Thêm hàm copyWith
  TimeFrameModel copyWith({
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    double? priceChangeValue,
    String? priceChangeUnit,
  }) {
    return TimeFrameModel(
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      priceChangeValue: priceChangeValue ?? this.priceChangeValue,
      priceChangeUnit: priceChangeUnit ?? this.priceChangeUnit,
    );
  }

  // SỬA LỖI: Thêm hàm overlaps
  bool overlaps(TimeFrameModel other) {
    final startA = startTime.hour * 60 + startTime.minute;
    final endA = endTime.hour * 60 + endTime.minute;
    final startB = other.startTime.hour * 60 + other.startTime.minute;
    final endB = other.endTime.hour * 60 + other.endTime.minute;

    // A qua đêm (vd: 22:00 -> 08:00)
    if (startA > endA) {
      // B cũng qua đêm -> luôn bị trùng
      if (startB > endB) return true;
      // B trong ngày (vd: 07:00 -> 10:00)
      return (startB < endA) || (endB > startA);
    }
    // B qua đêm (vd: 22:00 -> 08:00)
    if (startB > endB) {
      // A trong ngày (vd: 07:00 -> 10:00)
      return (startA < endB) || (endA > startB);
    }
    // Cả 2 đều trong ngày (vd: 09:00-11:00 và 10:00-12:00)
    return (startA < endB) && (startB < endA);
  }
}

// Model cho cấu trúc giá theo thời gian
class TimePricingModel {
  int priceUpdateInterval;
  int initialDurationMinutes;
  List<TimeFrameModel> timeFrames;

  TimePricingModel({
    this.priceUpdateInterval = 1,
    this.initialDurationMinutes = 0,
    List<TimeFrameModel>? timeFrames,
  }) : timeFrames = timeFrames ?? [];

  factory TimePricingModel.fromMap(Map<String, dynamic> map) {
    return TimePricingModel(
      priceUpdateInterval: (map['priceUpdateInterval'] as num?)?.toInt() ?? 1,
      initialDurationMinutes: (map['initialDurationMinutes'] as num?)?.toInt() ?? 0,
      timeFrames: (map['timeFrames'] as List<dynamic>?)
          ?.map((e) => TimeFrameModel.fromMap(e as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'priceUpdateInterval': priceUpdateInterval,
      'initialDurationMinutes': initialDurationMinutes,
      'timeFrames': timeFrames.map((e) => e.toMap()).toList(),
    };
  }
}

// Model chính cho toàn bộ thiết lập dịch vụ
class ServiceSetupModel {
  bool isTimeBased;
  TimePricingModel timePricing;
  Map<String, CommissionValue> commissionLevels;

  ServiceSetupModel({
    this.isTimeBased = false,
    TimePricingModel? timePricing,
    Map<String, CommissionValue>? commissionLevels,
  })  : timePricing = timePricing ?? TimePricingModel(),
        commissionLevels = commissionLevels ?? {
          'level1': CommissionValue(),
          'level2': CommissionValue(),
          'level3': CommissionValue(),
        };

  factory ServiceSetupModel.fromMap(Map<String, dynamic> map) {
    final commissionData = map['commissionLevels'] as Map<String, dynamic>?;
    final commissions = <String, CommissionValue>{};
    if (commissionData != null) {
      commissionData.forEach((key, value) {
        commissions[key] = CommissionValue.fromMap(value as Map<String, dynamic>);
      });
    } else {
      // Đảm bảo luôn có giá trị mặc định
      commissions.addAll({
        'level1': CommissionValue(),
        'level2': CommissionValue(),
        'level3': CommissionValue(),
      });
    }

    return ServiceSetupModel(
      isTimeBased: map['isTimeBased'] ?? false,
      timePricing: map['timePricing'] != null
          ? TimePricingModel.fromMap(map['timePricing'])
          : TimePricingModel(),
      commissionLevels: commissions,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'isTimeBased': isTimeBased,
      'timePricing': timePricing.toMap(),
      'commissionLevels': commissionLevels.map((key, value) => MapEntry(key, value.toMap())),
    };
  }
}

// Hàm tiện ích private
String _timeOfDayToString(TimeOfDay tod) =>
    '${tod.hour.toString().padLeft(2, '0')}:${tod.minute.toString().padLeft(2, '0')}';

TimeOfDay _stringToTimeOfDay(String s) {
  try {
    final parts = s.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  } catch (e) {
    return const TimeOfDay(hour: 0, minute: 0);
  }
}