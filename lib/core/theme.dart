import 'dart:ui';
import 'package:flutter/material.dart';

class AppTheme {
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
  static BoxDecoration get backgroundGradient => const BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [navy, navyLight, Color(0xFF0A2A4A), navy],
    ),
  );

  // ── Glass card (login-inspired) ──
  static Widget glassCardWidget({
    required Widget child,
    EdgeInsets? padding,
    double borderRadius = 20,
    BoxBorder? border,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding ?? const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(borderRadius),
            border: border ?? Border.all(color: glassBorder, width: 1),
            boxShadow: [
              BoxShadow(
                color: cyan.withValues(alpha: 0.10),
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

  // ── Full ThemeData ──
  static ThemeData get lightTheme {
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
          side: BorderSide(color: glassBorder, width: 1),
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
          borderSide: BorderSide(color: cyan, width: 2.2),
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
        hintStyle: TextStyle(fontFamily: 'Cairo', color: textMuted),
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
          side: BorderSide(color: cyan, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: const TextStyle(
          fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: textPrimary, fontSize: 13,
        ),
        dataTextStyle: const TextStyle(
          fontFamily: 'Cairo', color: textPrimary, fontSize: 13,
        ),
        headingRowColor: WidgetStatePropertyAll(const Color(0x1A22D3EE)),
        dataRowColor: WidgetStatePropertyAll(Colors.transparent),
        dataRowMinHeight: 40,
        dataRowMaxHeight: 48,
      ),
      dividerTheme: DividerThemeData(
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
          side: BorderSide(color: glassBorder, width: 1),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: Colors.transparent,
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
