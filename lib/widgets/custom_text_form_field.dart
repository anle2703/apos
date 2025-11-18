import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomTextFormField extends StatelessWidget {
  final TextEditingController? controller;
  final String? initialValue;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;
  final bool readOnly;
  final VoidCallback? onTap;
  final bool autofocus;
  final int? maxLines;
  final int? minLines;
  final TextAlign textAlign;
  final EdgeInsets scrollPadding;

  const CustomTextFormField({
    super.key,
    this.controller,
    this.initialValue,
    this.decoration,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.sentences,
    this.validator,
    this.onChanged,
    this.inputFormatters,
    this.obscureText = false,
    this.readOnly = false,
    this.onTap,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.textAlign = TextAlign.start, // ✅ mặc định là trái
    this.scrollPadding = const EdgeInsets.all(20), // ✅ default

  });

  @override
  Widget build(BuildContext context) {
    final baseDecoration = decoration ?? const InputDecoration();
    final mergedDecoration = baseDecoration.copyWith(
      hintStyle: baseDecoration.hintStyle ??
          TextStyle(
            color: Theme.of(context).hintColor,
            fontStyle: FontStyle.italic,
          ),
    );

    return TextFormField(
      controller: controller,
      initialValue: initialValue,
      decoration: mergedDecoration,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      validator: validator,
      onChanged: onChanged,
      inputFormatters: inputFormatters,
      obscureText: obscureText,
      readOnly: readOnly,
      onTap: onTap,
      autofocus: autofocus,
      maxLines: maxLines,
      minLines: minLines,
      textAlign: textAlign, // ✅ truyền xuống
      scrollPadding: scrollPadding, // ✅ FORWARD XUỐNG ĐÂY

    );
  }
}
