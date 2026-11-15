// lib/core/theme_cubit.dart
// ─────────────────────────────────────────────
// State management for ThemeMode (Dark / Light)
// with persistent storage via SharedPreferences
// and filesystem fallback for seamless hot-reloads.
// ─────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeCubit extends Cubit<ThemeMode> {
  static const String _prefKey = 'app_theme_mode';
  static final File _fallbackFile = File('.theme_mode');

  static ThemeMode currentMode = ThemeMode.dark;
  static bool get isCurrentDark => currentMode == ThemeMode.dark;

  ThemeCubit([super.state = ThemeMode.dark]) {
    currentMode = state;
  }

  @override
  void emit(ThemeMode state) {
    currentMode = state;
    super.emit(state);
  }

  bool get isDark => state == ThemeMode.dark;
  bool get isLight => state == ThemeMode.light;

  /// Loads the persisted theme mode from local storage.
  /// Defaults to [ThemeMode.dark] if no preference is found or on error.
  Future<void> loadTheme() async {
    // 1. Try SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = prefs.getString(_prefKey);
      if (modeStr == 'light') {
        emit(ThemeMode.light);
        return;
      } else if (modeStr == 'dark') {
        emit(ThemeMode.dark);
        return;
      }
    } catch (_) {
      // SharedPreferences native plugin not compiled in old running process yet
    }

    // 2. Try file fallback on desktop
    if (!kIsWeb) {
      try {
        if (_fallbackFile.existsSync()) {
          final modeStr = _fallbackFile.readAsStringSync().trim();
          if (modeStr == 'light') {
            emit(ThemeMode.light);
            return;
          } else if (modeStr == 'dark') {
            emit(ThemeMode.dark);
            return;
          }
        }
      } catch (_) {}
    }

    emit(ThemeMode.dark);
  }

  /// Toggles between [ThemeMode.dark] and [ThemeMode.light] and persists the choice.
  Future<void> toggleTheme() async {
    final newMode = isDark ? ThemeMode.light : ThemeMode.dark;
    await setTheme(newMode);
  }

  /// Sets an explicit [ThemeMode] and persists the choice.
  Future<void> setTheme(ThemeMode mode) async {
    emit(mode);
    final val = mode == ThemeMode.light ? 'light' : 'dark';

    // 1. Persist to SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, val);
    } catch (_) {}

    // 2. Persist to file fallback
    if (!kIsWeb) {
      try {
        _fallbackFile.writeAsStringSync(val);
      } catch (_) {}
    }
  }
}
