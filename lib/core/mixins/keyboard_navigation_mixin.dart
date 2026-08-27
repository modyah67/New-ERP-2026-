// lib/core/mixins/keyboard_navigation_mixin.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

mixin KeyboardNavigationMixin<T extends StatefulWidget> on State<T> {
  late List<FocusNode> focusNodes;

  void initFocusNodes(int count, {VoidCallback? onSave}) {
    focusNodes = List.generate(count, (index) => FocusNode(
      onKeyEvent: (node, event) => handleKeyEvent(node, event, onSave: onSave),
    ));
  }

  void disposeFocusNodes() {
    for (var node in focusNodes) {
      node.dispose();
    }
  }

  KeyEventResult handleKeyEvent(
    FocusNode node,
    KeyEvent event,
    {VoidCallback? onSave}
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final index = focusNodes.indexOf(node);
    if (index == -1) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.enter || 
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (index < focusNodes.length - 1) {
        Future.microtask(() => focusNodes[index + 1].requestFocus());
      } else if (event.logicalKey == LogicalKeyboardKey.enter) {
        // Last field + Enter = Save
        onSave?.call();
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (index > 0) {
        Future.microtask(() => focusNodes[index - 1].requestFocus());
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }
}
