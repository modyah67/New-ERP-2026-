import 'dart:ui';
import 'package:flutter/material.dart';
import 'theme_cubit.dart';
export 'theme_cubit.dart';

class AppTheme {
  static bool get isCurrentDark => ThemeCubit.isCurrentDark;

  // ── ERP Dark Palette ──
  static const Color cyan = Color(0xFF16D5FF);
  static const Color teal = Color(0xFF14B8A6);
  static const Color navy = Color(0xFF041E42);
  static const Color navyLight = Color(0xFF082B57);
  static const Color cardBg = Color(0xFF082B57);
  static const Color borderColor = Color(0xFF0F4C81);

  // ── Semantic ──
  static const Color primary = cyan;
  static const Color accent = teal;
  static const Color success = cyan;
  static const Color warning = Color(0xFFF4B400);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = cyan;

  // ── Surfaces ──
  static const Color background = navy;
  static const Color surface = Color(0xFF082B57);

  // ── Sidebar ──
  static const Color sidebarBg = Color(0xFF041E42);
  static const Color sidebarDark = Color(0xFF031935);
  static const Color sidebarActive = Color(0xFF0D2F5F);
  static const Color sidebarHover = Color(0xFF0B2A52);
  static const Color sidebarText = Color(0xFFFFFFFF);
  static const Color sidebarTextInactive = Color(0x99FFFFFF);

  // ── Text ──
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFA7B4C8);
  static const Color textMuted = Color(0x99FFFFFF);

  // ── Borders ──
  static const Color glassBorder = Color(0xFF0F4C81);
  static const Color border = Color(0xFF0F4C81);
  static const Color divider = Color(0xFF0F4C81);

  // ── Legacy aliases for backward compat ──
  static const Color primaryLight = teal;
  static const Color primaryDark = cyan;
  static const Color neonCyan = cyan;
  static const Color emerald = teal;
  static const Color cyberGlow = Color(0x1A16D5FF);
  static const Color cyberBg = navy;
  static const Color cyberSurface = Color(0xFF082B57);
  static const Color textLight = textPrimary;

  // ── Typography ──
  static const TextStyle heading1 = TextStyle(
    fontSize: 32, fontWeight: FontWeight.bold, color: textPrimary, fontFamily: 'Cairo',
  );
  static const TextStyle heading2 = TextStyle(
    fontSize: 22, fontWeight: FontWeight.w600, color: textPrimary, fontFamily: 'Cairo',
  );
  static const TextStyle heading3 = TextStyle(
    fontSize: 18, fontWeight: FontWeight.bold, color: textPrimary, fontFamily: 'Cairo',
  );
  static const TextStyle body = TextStyle(
    fontSize: 15, color: textPrimary, fontFamily: 'Cairo',
  );
  static const TextStyle bodySmall = TextStyle(
    fontSize: 13, color: textSecondary, fontFamily: 'Cairo',
  );
  static const TextStyle label = TextStyle(
    fontSize: 14, fontWeight: FontWeight.w600, color: textSecondary, fontFamily: 'Cairo',
  );
  static const TextStyle cardNumber = TextStyle(
    fontSize: 34, fontWeight: FontWeight.w800, color: textPrimary, fontFamily: 'Cairo', letterSpacing: 0.5,
  );

  // ── Login-style background ──
  static BoxDecoration get backgroundGradient => ThemeCubit.isCurrentDark
      ? const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [navy, navyLight, Color(0xFF0A2A4A), navy],
          ),
        )
      : lightBackgroundGradient;

  // ── Glass card (login-inspired) ──
  static Widget glassCardWidget({
    required Widget child,
    EdgeInsets? padding,
    double borderRadius = 20,
    BoxBorder? border,
  }) {
    final isCurrentDark = ThemeCubit.isCurrentDark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding ?? const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isCurrentDark ? cardBg : Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(borderRadius),
            border: border ?? Border.all(color: isCurrentDark ? glassBorder : lightBorder, width: 1),
            boxShadow: [
              BoxShadow(
                color: isCurrentDark
                    ? cyan.withValues(alpha: 0.10)
                    : const Color(0xFF0F172A).withValues(alpha: 0.06),
                blurRadius: 40,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  static BoxDecoration glassCard({double blur = 20, double opacity = 0.55}) {
    if (!ThemeCubit.isCurrentDark) {
      return lightGlassCard(blur: blur);
    }
    return BoxDecoration(
      color: const Color(0x1E0A1E3A).withValues(alpha: opacity),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: glassBorder, width: 1),
      boxShadow: [
        BoxShadow(
          color: cyan.withValues(alpha: 0.08),
          blurRadius: blur,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  // ── Login-style gradient button ──
  static BoxDecoration get gradientButton => BoxDecoration(
    gradient: const LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xFF22D3EE), Color(0xFF14B8A6)],
    ),
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF22D3EE).withValues(alpha: 0.30),
        blurRadius: 22, offset: const Offset(0, 8),
      ),
      BoxShadow(
        color: const Color(0xFF14B8A6).withValues(alpha: 0.20),
        blurRadius: 30,
      ),
    ],
  );

  // ── Light Palette ──
  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color lightCardBg = Colors.white;
  static const Color lightBorder = Color(0xFFCBD5E1);
  static const Color lightTextPrimary = Colors.black;
  static const Color lightTextSecondary = Color(0xFF1E293B);
  static const Color lightTextMuted = Color(0xFF475569);
  static const Color lightPrimary = Color(0xFF0284C7);
  static const Color lightAccent = Color(0xFF0D9488);

  // ── Context-aware theme helpers ──
  static bool isDark(BuildContext context) =>
      ThemeCubit.isCurrentDark;

  static Color getBackgroundColor(BuildContext context) =>
      isDark(context) ? background : lightBackground;

  static Color getCardBg(BuildContext context) =>
      isDark(context) ? cardBg : lightCardBg;

  static Color getTextPrimary(BuildContext context) =>
      isDark(context) ? textPrimary : lightTextPrimary;

  static Color getTextSecondary(BuildContext context) =>
      isDark(context) ? textSecondary : lightTextSecondary;

  static Color getTextMuted(BuildContext context) =>
      isDark(context) ? textMuted : lightTextMuted;

  static Color getBorderColor(BuildContext context) =>
      isDark(context) ? borderColor : lightBorder;

  static BoxDecoration get lightBackgroundGradient => const BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xFFF8FAFC), Color(0xFFEDF2F7), Color(0xFFF1F5F9), Color(0xFFE2E8F0)],
    ),
  );

  static BoxDecoration lightGlassCard({double blur = 20}) {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.06),
          blurRadius: blur,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  static BoxDecoration getBackgroundGradientFor(BuildContext context) =>
      isDark(context) ? backgroundGradient : lightBackgroundGradient;

  static BoxDecoration getGlassCardFor(BuildContext context, {double blur = 20, double? opacity}) =>
      isDark(context) ? glassCard(blur: blur, opacity: opacity ?? 0.55) : lightGlassCard(blur: blur);

  static Color getDialogBg(BuildContext context) =>
      isDark(context) ? const Color(0xCC05192D) : Colors.white;

  static Color getDialogInnerBg(BuildContext context) =>
      isDark(context) ? const Color(0xB305192D) : Colors.white;

  static BorderSide getDialogBorder(BuildContext context) =>
      BorderSide(color: isDark(context) ? glassBorder : lightBorder);

  // ── Dark ThemeData ──
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Cairo',
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: cyan,
        brightness: Brightness.dark,
        surface: background,
      ),
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'Cairo', fontSize: 18,
          fontWeight: FontWeight.bold, color: textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: glassBorder, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0x1A00D4FF),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cyan.withValues(alpha: 0.3), width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cyan.withValues(alpha: 0.3), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cyan, width: 2.2),
        ),
        focusColor: cyan.withValues(alpha: 0.15),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: danger, width: 1.8),
        ),
        labelStyle: const TextStyle(fontFamily: 'Cairo', color: textSecondary),
        hintStyle: const TextStyle(fontFamily: 'Cairo', color: textMuted),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(
            fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.bold,
          ),
          elevation: 0,
        ).copyWith(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return teal;
            return Colors.transparent;
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: cyan,
          textStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: cyan,
          side: const BorderSide(color: cyan, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
        ),
      ),
      dataTableTheme: const DataTableThemeData(
        headingTextStyle: TextStyle(
          fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: textPrimary, fontSize: 13,
        ),
        dataTextStyle: TextStyle(
          fontFamily: 'Cairo', color: textPrimary, fontSize: 13,
        ),
        headingRowColor: WidgetStatePropertyAll(Color(0x1A22D3EE)),
        dataRowColor: WidgetStatePropertyAll(Colors.transparent),
        dataRowMinHeight: 40,
        dataRowMaxHeight: 48,
      ),
      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xE60A1E3A),
        contentTextStyle: const TextStyle(fontFamily: 'Cairo', color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xE60A1E3A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: glassBorder, width: 1),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: Colors.transparent,
      ),
    );
  }

  // ── Light ThemeData ──
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Cairo',
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: lightPrimary,
        brightness: Brightness.light,
        surface: Colors.white,
        surfaceContainer: const Color(0xFFF1F5F9),
        onSurface: Colors.black,
        outline: lightBorder,
      ),
      scaffoldBackgroundColor: lightBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'Cairo', fontSize: 18,
          fontWeight: FontWeight.bold, color: Colors.black,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 2,
        shadowColor: const Color(0x120F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: lightBorder, width: 1),
        ),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontFamily: 'Cairo', color: Colors.black, fontWeight: FontWeight.bold),
        displayMedium: TextStyle(fontFamily: 'Cairo', color: Colors.black, fontWeight: FontWeight.bold),
        displaySmall: TextStyle(fontFamily: 'Cairo', color: Colors.black, fontWeight: FontWeight.bold),
        headlineLarge: TextStyle(fontFamily: 'Cairo', color: Colors.black, fontWeight: FontWeight.bold),
        headlineMedium: TextStyle(fontFamily: 'Cairo', color: Colors.black, fontWeight: FontWeight.bold),
        headlineSmall: TextStyle(fontFamily: 'Cairo', color: Colors.black, fontWeight: FontWeight.bold),
        titleLarge: TextStyle(fontFamily: 'Cairo', color: Colors.black, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(fontFamily: 'Cairo', color: Colors.black, fontWeight: FontWeight.bold),
        titleSmall: TextStyle(fontFamily: 'Cairo', color: Colors.black, fontWeight: FontWeight.bold),
        bodyLarge: TextStyle(fontFamily: 'Cairo', color: Colors.black, fontWeight: FontWeight.bold),
        bodyMedium: TextStyle(fontFamily: 'Cairo', color: Colors.black, fontWeight: FontWeight.bold),
        bodySmall: TextStyle(fontFamily: 'Cairo', color: Colors.black, fontWeight: FontWeight.bold),
        labelLarge: TextStyle(fontFamily: 'Cairo', color: Colors.black, fontWeight: FontWeight.bold),
        labelMedium: TextStyle(fontFamily: 'Cairo', color: Colors.black, fontWeight: FontWeight.bold),
        labelSmall: TextStyle(fontFamily: 'Cairo', color: Colors.black, fontWeight: FontWeight.bold),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF94A3B8), width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF94A3B8), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightPrimary, width: 2.0),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: danger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: danger, width: 1.8),
        ),
        labelStyle: const TextStyle(fontFamily: 'Cairo', color: Colors.black, fontWeight: FontWeight.bold),
        floatingLabelStyle: const TextStyle(fontFamily: 'Cairo', color: Colors.black, fontWeight: FontWeight.bold),
        hintStyle: const TextStyle(fontFamily: 'Cairo', color: Color(0xFF64748B), fontWeight: FontWeight.bold),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: lightPrimary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(
            fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.bold,
          ),
          elevation: 2,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: lightPrimary,
          textStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: lightPrimary,
          side: const BorderSide(color: lightPrimary, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
      dataTableTheme: const DataTableThemeData(
        headingTextStyle: TextStyle(
          fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.black, fontSize: 13,
        ),
        dataTextStyle: TextStyle(
          fontFamily: 'Cairo', color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13,
        ),
        headingRowColor: WidgetStatePropertyAll(Color(0xFFF1F5F9)),
        dataRowColor: WidgetStatePropertyAll(Colors.white),
        dataRowMinHeight: 40,
        dataRowMaxHeight: 48,
        dividerThickness: 1,
      ),
      dividerTheme: const DividerThemeData(
        color: lightBorder,
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF0F172A),
        contentTextStyle: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: lightBorder, width: 1),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: 'Cairo', fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: 'Cairo', fontSize: 14, color: Colors.black, fontWeight: FontWeight.bold,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: Color(0xFFF1F5F9),
      ),
    );
  }


  // ── Responsive Typography ──
  static const _menuDesktop = 16.0, _menuNormal = 15.0, _menuSmall = 14.0;
  static const _titleDesktop = 28.0, _titleNormal = 24.0, _titleSmall = 22.0;
  static const _cardTitleDesktop = 18.0, _cardTitleNormal = 16.0, _cardTitleSmall = 15.0;
  static const _bodyDesktop = 14.0, _bodyNormal = 13.0, _bodySmall = 12.0;
  static const _tableDesktop = 14.0, _tableNormal = 13.0, _tableSmall = 12.0;

  static double _size(double desktop, double normal, double small) {
    final width = PlatformDispatcher.instance.views.first.physicalSize.width /
        PlatformDispatcher.instance.views.first.devicePixelRatio;
    if (width > 1600) return desktop;
    if (width >= 1200) return normal;
    return small;
  }

  static double get menuFontSize => _size(_menuDesktop, _menuNormal, _menuSmall);
  static double get pageTitleFontSize => _size(_titleDesktop, _titleNormal, _titleSmall);
  static double get cardTitleFontSize => _size(_cardTitleDesktop, _cardTitleNormal, _cardTitleSmall);
  static double get bodyFontSize => _size(_bodyDesktop, _bodyNormal, _bodySmall);
  static double get tableFontSize => _size(_tableDesktop, _tableNormal, _tableSmall);
}
