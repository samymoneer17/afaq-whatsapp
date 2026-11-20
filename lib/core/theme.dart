// ثيم واتساب الرسمي — فاتح + داكن بألوان التطبيق الحقيقية
import 'package:flutter/material.dart';

/// ألوان واتساب الرسمية (Android)
class WaColors {
  // الأخضر الرسمي
  static const green = Color(0xFF00A884);
  static const greenDeep = Color(0xFF005C4B);
  static const greenBadge = Color(0xFF25D366);
  static const greenDarkHeader = Color(0xFF1F2C34);

  // الوضع الفاتح
  static const lightBg = Color(0xFFFFFFFF);
  static const lightChatBg = Color(0xFFEFEAE2);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightBubbleIn = Color(0xFFFFFFFF);
  static const lightBubbleOut = Color(0xFFD9FDD3);
  static const lightText = Color(0xFF111B21);
  static const lightMuted = Color(0xFF667781);
  static const lightDivider = Color(0xFFE9EDEF);
  static const lightSearch = Color(0xFFF0F2F5);
  static const lightTabBg = Color(0xFFFFFFFF);
  static const lightUnreadPill = Color(0xFF25D366);

  // الوضع الداكن
  static const darkBg = Color(0xFF0B141A);
  static const darkChatBg = Color(0xFF0B141A);
  static const darkSurface = Color(0xFF111B21);
  static const darkAppbar = Color(0xFF202C33);
  static const darkBubbleIn = Color(0xFF202C33);
  static const darkBubbleOut = Color(0xFF005C4B);
  static const darkText = Color(0xFFE9EDEF);
  static const darkMuted = Color(0xFF8696A0);
  static const darkDivider = Color(0xFF222D34);
  static const darkSearch = Color(0xFF202C33);
  static const darkInput = Color(0xFF2A3942);

  // التفاعلات والعلامات
  static const tickRead = Color(0xFF53BDEB);
  static const recording = Color(0xFFEA4335);

  static const light = WaColors._(
    bg: lightBg,
    chatBg: lightChatBg,
    surface: lightSurface,
    appbar: lightBg,
    bubbleIn: lightBubbleIn,
    bubbleOut: lightBubbleOut,
    text: lightText,
    muted: lightMuted,
    divider: lightDivider,
    search: lightSearch,
    input: lightSearch,
    avatarPlaceholder: Color(0xFFDFE5E7),
  );

  static const dark = WaColors._(
    bg: darkBg,
    chatBg: darkChatBg,
    surface: darkSurface,
    appbar: darkAppbar,
    bubbleIn: darkBubbleIn,
    bubbleOut: darkBubbleOut,
    text: darkText,
    muted: darkMuted,
    divider: darkDivider,
    search: darkSearch,
    input: darkInput,
    avatarPlaceholder: Color(0xFF3B4A54),
  );

  final Color bg,
      chatBg,
      surface,
      appbar,
      bubbleIn,
      bubbleOut,
      text,
      muted,
      divider,
      search,
      input,
      avatarPlaceholder;

  const WaColors._({
    required this.bg,
    required this.chatBg,
    required this.surface,
    required this.appbar,
    required this.bubbleIn,
    required this.bubbleOut,
    required this.text,
    required this.muted,
    required this.divider,
    required this.search,
    required this.input,
    required this.avatarPlaceholder,
  });

  static WaColors of(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark
          ? WaColors.dark
          : WaColors.light;
}

/// بناء ثيم كامل مطابق لواجهة واتساب
ThemeData waTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final c = isDark ? WaColors.dark : WaColors.light;
  final colorScheme = ColorScheme(
    brightness: brightness,
    primary: WaColors.green,
    onPrimary: Colors.white,
    secondary: WaColors.greenDeep,
    onSecondary: Colors.white,
    surface: c.surface,
    onSurface: c.text,
    error: const Color(0xFFEA4335),
    onError: Colors.white,
    primaryContainer: isDark ? WaColors.darkAppbar : WaColors.lightSearch,
    onPrimaryContainer: c.text,
    secondaryContainer: WaColors.greenDeep,
    onSecondaryContainer: Colors.white,
    surfaceContainerHighest: c.search,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: c.bg,
    fontFamily: 'Roboto',
    appBarTheme: AppBarTheme(
      backgroundColor: c.appbar,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 20,
      toolbarHeight: 56,
      titleTextStyle: TextStyle(
          color: c.text,
          fontSize: 20,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1),
      iconTheme: IconThemeData(
          color: isDark ? WaColors.darkMuted : const Color(0xFF54656F),
          size: 24),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.appbar,
      indicatorColor: Colors.transparent,
      height: 64,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: WaColors.green,
      foregroundColor: Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.input,
      hintStyle: TextStyle(color: c.muted, fontSize: 14.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: WaColors.green, width: 1.6)),
    ),
    dividerTheme:
        DividerThemeData(color: c.divider, thickness: 0.6, space: 0.6),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shadowColor: Colors.black38,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: TextStyle(color: c.text, fontSize: 15),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle:
          TextStyle(color: c.text, fontSize: 18, fontWeight: FontWeight.w600),
      contentTextStyle: TextStyle(color: c.muted, fontSize: 14.5),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark ? WaColors.darkAppbar : const Color(0xFF1F2C34),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? Colors.white
              : (isDark ? Colors.grey.shade400 : Colors.grey.shade50)),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? WaColors.green
              : (isDark ? WaColors.darkInput : Colors.grey.shade300)),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? WaColors.green
              : Colors.transparent),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: WaColors.green,
      selectionColor: WaColors.green.withValues(alpha: 0.25),
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: WaColors.green),
    listTileTheme: ListTileThemeData(
      iconColor: isDark ? WaColors.darkMuted : const Color(0xFF54656F),
    ),
  );
}
