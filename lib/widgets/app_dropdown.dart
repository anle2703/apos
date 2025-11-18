// File: lib/widgets/app_dropdown.dart

import 'package:flutter/material.dart';
import 'package:dropdown_button2/dropdown_button2.dart';

class AppDropdown<T> extends StatelessWidget {
  final String labelText;
  final IconData? prefixIcon;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final FormFieldValidator<T>? validator;
  final bool isDense;
  // THÊM THAM SỐ MỚI: Cho phép tùy chỉnh widget hiển thị khi đã chọn
  final DropdownButtonBuilder? selectedItemBuilder;

  const AppDropdown({
    super.key,
    required this.labelText,
    this.prefixIcon,
    this.value,
    required this.items,
    this.onChanged,
    this.validator,
    this.isDense = false,
    this.selectedItemBuilder, // Thêm vào constructor
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final EdgeInsetsGeometry contentPadding = isDense
        ? const EdgeInsets.fromLTRB(4, 8.0, 0, 8.0)
        : const EdgeInsets.fromLTRB(4, 16.0, 0, 16.0);

    return DropdownButtonFormField2<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      validator: validator,
      isExpanded: true,
      style: theme.textTheme.bodyLarge?.copyWith(
        fontWeight: FontWeight.w500,
      ),
      // SỬA TẠI ĐÂY: Dùng builder được truyền vào, nếu không có thì dùng mặc định
      selectedItemBuilder: selectedItemBuilder ??
              (context) {
            return items.map((item) {
              return item.child;
            }).toList();
          },
      iconStyleData: IconStyleData(
        icon: Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: Icon(
            Icons.arrow_drop_down,
            color: theme.primaryColor,
          ),
        ),
        iconSize: 24,
      ),
      dropdownStyleData: DropdownStyleData(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8.0),
          color: Colors.white,
        ),
        elevation: 8,
      ),
      decoration: InputDecoration(
        labelText: labelText,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
        contentPadding: contentPadding,
      ),
    );
  }
}