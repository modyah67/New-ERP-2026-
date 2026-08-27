// lib/core/keyboard_shortcuts.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppShortcuts {
  // Define custom intents
  static const searchIntent = SearchIntent();
  static const saveIntent = SaveIntent();
  static const addIntent = AddIntent();
  static const escapeIntent = EscapeIntent();

  // Map LogicalKeySet to Intents
  static final Map<ShortcutActivator, Intent> shortcuts = {
    LogicalKeySet(LogicalKeyboardKey.f1): searchIntent,
    LogicalKeySet(LogicalKeyboardKey.f2): saveIntent,
    LogicalKeySet(LogicalKeyboardKey.f3): addIntent,
    LogicalKeySet(LogicalKeyboardKey.escape): escapeIntent,
    LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS): saveIntent,
  };
}

class SearchIntent extends Intent {
  const SearchIntent();
}

class SaveIntent extends Intent {
  const SaveIntent();
}

class AddIntent extends Intent {
  const AddIntent();
}

class EscapeIntent extends Intent {
  const EscapeIntent();
}
