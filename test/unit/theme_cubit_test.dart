import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:accounting_system/core/theme_cubit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeCubit Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('initial state defaults to ThemeMode.dark', () {
      final cubit = ThemeCubit();
      expect(cubit.state, equals(ThemeMode.dark));
      expect(cubit.isDark, isTrue);
      expect(cubit.isLight, isFalse);
    });

    test('toggleTheme switches from dark to light and persists value', () async {
      final cubit = ThemeCubit();
      await cubit.toggleTheme();
      expect(cubit.state, equals(ThemeMode.light));
      expect(cubit.isDark, isFalse);
      expect(cubit.isLight, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_theme_mode'), equals('light'));
    });

    test('toggleTheme switches back from light to dark', () async {
      final cubit = ThemeCubit(ThemeMode.light);
      await cubit.toggleTheme();
      expect(cubit.state, equals(ThemeMode.dark));
      expect(cubit.isDark, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_theme_mode'), equals('dark'));
    });

    test('setTheme explicitly sets and persists theme mode', () async {
      final cubit = ThemeCubit();
      await cubit.setTheme(ThemeMode.light);
      expect(cubit.state, equals(ThemeMode.light));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_theme_mode'), equals('light'));

      await cubit.setTheme(ThemeMode.dark);
      expect(cubit.state, equals(ThemeMode.dark));
      expect(prefs.getString('app_theme_mode'), equals('dark'));
    });

    test('loadTheme correctly restores saved theme mode from preferences', () async {
      SharedPreferences.setMockInitialValues({'app_theme_mode': 'light'});

      final cubit = ThemeCubit();
      await cubit.loadTheme();
      expect(cubit.state, equals(ThemeMode.light));
      expect(cubit.isLight, isTrue);
    });

    test('loadTheme defaults to dark if preference is invalid or missing', () async {
      SharedPreferences.setMockInitialValues({'app_theme_mode': 'unknown'});

      final cubit = ThemeCubit(ThemeMode.light);
      await cubit.loadTheme();
      expect(cubit.state, equals(ThemeMode.dark));
      expect(cubit.isDark, isTrue);
    });
  });
}
