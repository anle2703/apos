// lib/theme/string_extensions.dart
extension NullIfEmpty on String? {
  String? get nullIfEmpty => (this ?? '').trim().isEmpty ? null : this;
}