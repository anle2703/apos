import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class AppTheme {
  static const Color primaryColor = Color(0xFF02D0C1);
  static const Color scaffoldBackgroundColor = Color(0xFFF5F8FA);
  static const Color textColor = Color(0xFF333333);

  // Định nghĩa các style chữ cơ bản để tái sử dụng
  static const TextStyle _baseTextStyle = TextStyle(
    fontFamily: 'Quicksand',
    color: textColor,
  );
  static final TextStyle regularTextStyle = _baseTextStyle.copyWith(
    fontWeight: FontWeight.normal,
  );

  static final TextStyle regularGreyTextStyle = _baseTextStyle.copyWith(
    color: Colors.grey[600],
    fontWeight: FontWeight.normal,
  );

  static final TextStyle boldTextStyle = _baseTextStyle.copyWith(
    fontWeight: FontWeight.bold,
  );

  static ThemeData get lightTheme {
    final ColorScheme colorScheme = const ColorScheme.light().copyWith(
      primary: primaryColor,
      secondary: primaryColor,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      fontFamily: 'Quicksand',

      textTheme: TextTheme(
        displaySmall: boldTextStyle.copyWith(fontSize: 28),
        headlineMedium: boldTextStyle.copyWith(fontSize: 22),
        titleMedium: regularGreyTextStyle.copyWith(fontSize: 16),
        bodyMedium: regularGreyTextStyle.copyWith(fontSize: 14),
        labelLarge: boldTextStyle.copyWith(fontSize: 16, color: Colors.white),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        prefixIconColor: Colors.grey[500],
        contentPadding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: const BorderSide(color: primaryColor, width: 2.0),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide(color: Colors.red.shade200, width: 1.2),
        ),
        labelStyle: regularGreyTextStyle,
      ),

      textSelectionTheme: TextSelectionThemeData(
        cursorColor: primaryColor,
        selectionColor: primaryColor.withAlpha(77),
        selectionHandleColor: primaryColor,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: kIsWeb ? 14 : 8),
          shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(12.0), ),
          textStyle: boldTextStyle.copyWith(fontSize: 16),
        ),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primaryColor;
          }
          return null;
        }),
        checkColor: WidgetStateProperty.all(Colors.white),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith<Color>(
                (Set<WidgetState> states) {
              if (states.contains(WidgetState.selected)) {
                return primaryColor;
              }
              return Colors.white;
            },
          ),
          foregroundColor: WidgetStateProperty.resolveWith<Color>(
                (Set<WidgetState> states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.white;
              }
              return textColor;
            },
          ),
          side: WidgetStateProperty.resolveWith<BorderSide?>(
                (Set<WidgetState> states) {
              return BorderSide(color: Colors.grey[300]!);
            },
          ),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return primaryColor;
          }
          return Colors.grey;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected)) {
            return primaryColor.withAlpha(128);
          }
          return Colors.grey.withAlpha(64);
        }),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          textStyle: _baseTextStyle.copyWith(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),

      timePickerTheme: TimePickerThemeData(
        backgroundColor: Colors.white,
        hourMinuteColor: primaryColor.withAlpha(25),
        hourMinuteTextColor: textColor,
        hourMinuteShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
          side: const BorderSide(color: primaryColor, width: 1.5),
        ),
        dayPeriodColor: Colors.grey.shade100,
        dayPeriodTextColor: textColor,
        dayPeriodShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        dayPeriodTextStyle: boldTextStyle,
        dialHandColor: primaryColor,
        dialBackgroundColor: primaryColor.withAlpha(25),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textColor,
          minimumSize: const Size(double.infinity, 42),
          side: BorderSide(color: Colors.grey[300]!),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          textStyle: boldTextStyle.copyWith(fontSize: 16),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: primaryColor.withAlpha(38),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 14),
        labelStyle: _baseTextStyle.copyWith(fontSize: 13, color: Colors.grey),
        secondaryLabelStyle: boldTextStyle.copyWith(fontSize: 14, color: primaryColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
        side: BorderSide(color: Colors.grey.shade300),
        checkmarkColor: primaryColor,
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryColor,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        titleTextStyle: boldTextStyle.copyWith(fontSize: 20),
      ),

      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
        elevation: 6.0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 0.0),
      ),

      splashFactory: InkRipple.splashFactory,
      highlightColor: Colors.transparent,
      splashColor: primaryColor.withValues(alpha: 0.1),
      hoverColor: Colors.grey.shade100,

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        elevation: 8.0,
        type: BottomNavigationBarType.fixed,
        selectedIconTheme: const IconThemeData(
          size: 28,
        ),
        unselectedIconTheme: IconThemeData(
          color: Colors.grey[600],
          size: 24,
        ),
        selectedLabelStyle: const TextStyle(
          fontFamily: 'Quicksand',
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: 'Quicksand',
          fontWeight: FontWeight.normal,
          fontSize: 12,
        ),
        showUnselectedLabels: true,
        showSelectedLabels: true,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0, // Độ nổi khi đã cuộn (đặt bằng elevation)
        shadowColor: Colors.black.withAlpha(25), // Màu của bóng đổ
        surfaceTintColor: Colors.transparent, // Giữ màu nền trắng khi cuộn
        foregroundColor: textColor,
        titleTextStyle: boldTextStyle.copyWith(fontSize: 20),
      ),

      // Tabbar
      tabBarTheme: TabBarThemeData(
        indicatorColor: primaryColor,
        labelColor: primaryColor,
        unselectedLabelColor: Colors.grey,
        dividerColor: Colors.transparent,
        labelStyle: _baseTextStyle.copyWith(fontSize: 18, fontWeight: FontWeight.bold),
        unselectedLabelStyle: _baseTextStyle.copyWith(fontSize: 16),
        overlayColor: WidgetStateProperty.resolveWith<Color?>(
              (Set<WidgetState> states) {
            if (states.contains(WidgetState.hovered)) {
              return primaryColor.withAlpha(26);
            }
            return null;
          },
        ),
        splashBorderRadius: BorderRadius.circular(12.0),
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.white,
        elevation: 8,
        indicatorColor: primaryColor.withAlpha(26),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
        selectedIconTheme: const IconThemeData(color: primaryColor, size: 30),
        unselectedIconTheme: IconThemeData(color: Colors.grey[600], size: 25),
        selectedLabelTextStyle: boldTextStyle.copyWith(
          color: primaryColor,
          fontSize: 16,
        ),
        unselectedLabelTextStyle: _baseTextStyle.copyWith(
          color: Colors.grey[600],
          fontSize: 14,
          fontWeight: FontWeight.normal,
        ),
      ),
    );
  }
}