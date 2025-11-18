import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final numberFormat = NumberFormat('#,##0.####', 'vi_VN');

String capitalizeWords(String text) {
  if (text.trim().isEmpty) return "";
  return text
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) {
    if (word == word.toUpperCase()) {
      return word;
    }return word[0].toUpperCase() + word.substring(1).toLowerCase();
  })
      .join(' ');
}

String formatNumber(double value) {
  return numberFormat.format(value);
}

double parseVN(String input) {
  final normalized = input.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(normalized) ?? 0.0;
}

class ThousandDecimalInputFormatter extends TextInputFormatter {
  final NumberFormat _intFormatter = NumberFormat('#,##0', 'vi_VN');
  final bool allowSigned;

  ThousandDecimalInputFormatter({this.allowSigned = false});

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    String text = newValue.text;
    if (text.isEmpty) return newValue.copyWith(text: '');

    // Cho phép ký tự '-' nếu allowSigned
    final regex = allowSigned ? RegExp(r'[^0-9,-]') : RegExp(r'[^0-9,]');
    text = text.replaceAll(regex, '');

    // Nếu chỉ có dấu '-' thì giữ nguyên
    if (text == '-') {
      return TextEditingValue(
        text: '-',
        selection: const TextSelection.collapsed(offset: 1),
      );
    }

    // Nếu bắt đầu bằng "-" thì tách riêng
    bool isNegative = text.startsWith('-');
    if (isNegative) {
      text = text.substring(1);
    }

    if (text == ',') {
      return TextEditingValue(
        text: isNegative ? '-0,' : '0,',
        selection: TextSelection.collapsed(offset: isNegative ? 3 : 2),
      );
    }

    final parts = text.split(',');
    String intPart = parts[0];
    final decPart = parts.length > 1 ? ',${parts[1]}' : '';

    final newInt =
    intPart.isNotEmpty ? _intFormatter.format(int.parse(intPart)) : '0';
    final newText = (isNegative ? '-' : '') + newInt + decPart;

    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}

