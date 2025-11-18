// File: lib/utils/responsive_helper.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

bool isMobile() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
}

TextStyle? responsiveTextStyle(TextStyle? originalStyle) {
  if (originalStyle == null || originalStyle.fontSize == null) {
    return originalStyle;
  }

  double newSize = originalStyle.fontSize!;
  if (isMobile()) {
    newSize -= 2;
  }

  return originalStyle.copyWith(fontSize: newSize);
}