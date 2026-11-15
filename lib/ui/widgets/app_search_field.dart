// lib/ui/widgets/app_search_field.dart
// ─────────────────────────────────────────────
// Premium dark glass typeahead search field
// ─────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../../core/theme.dart';

class AppSearchField<T> extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final FutureOr<List<T>?> Function(String) suggestionsCallback;
  final Widget Function(BuildContext, T) itemBuilder;
  final void Function(T) onSelected;
  final String Function(T)? displayStringForOption;
  final Widget? prefixIcon;
  final bool isRequired;
  final TextInputAction textInputAction;
  final void Function(String)? onSubmitted;
  final bool autoFocus;
  final Color? highlightColor;
  final WidgetBuilder? emptyBuilder;

  const AppSearchField({
    super.key,
    required this.label,
    required this.controller,
    required this.suggestionsCallback,
    required this.itemBuilder,
    required this.onSelected,
    this.focusNode,
    this.hint,
    this.displayStringForOption,
    this.prefixIcon,
    this.isRequired = false,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.autoFocus = false,
    this.highlightColor,
    this.emptyBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : AppTheme.lightTextPrimary;
    final secondaryTextColor = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;
    final mutedTextColor = isDark ? Colors.white.withValues(alpha: 0.35) : AppTheme.lightTextMuted;
    final fieldBg = isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white;
    final fieldBorder = isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFCBD5E1);
    final popupBg = isDark ? const Color(0xFF0A1E38) : Colors.white;
    final popupBorder = isDark ? AppTheme.glassBorder : AppTheme.lightBorder;
    final activeColor = isDark ? AppTheme.primary : AppTheme.lightPrimary;
    final hl = highlightColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            text: label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isDark ? FontWeight.w600 : FontWeight.bold,
              color: isDark ? secondaryTextColor : Colors.black,
              fontFamily: 'Cairo',
            ),
            children: isRequired
                ? const [
                    TextSpan(
                      text: ' *',
                      style: TextStyle(color: AppTheme.danger),
                    ),
                  ]
                : [],
          ),
        ),
        const SizedBox(height: 8),
        TypeAheadField<T>(
          focusNode: focusNode,
          controller: controller,
          autoFlipDirection: true,
          hideOnEmpty: false,
          hideOnError: false,
          loadingBuilder: (context) => Padding(
            padding: const EdgeInsets.all(8.0),
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: activeColor,
              ),
            ),
          ),
          emptyBuilder: emptyBuilder ??
              (context) => Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Text('لا توجد نتائج',
                        style: TextStyle(
                            color: mutedTextColor, fontFamily: 'Cairo')),
                  ),
          suggestionsCallback: suggestionsCallback,
          itemBuilder: hl == null
              ? itemBuilder
              : (ctx, item) => Material(
                    color: Colors.transparent,
                    child: InkWell(
                      hoverColor: hl,
                      splashColor: hl,
                      highlightColor: hl,
                      onTap: () {
                        onSelected(item);
                        FocusScope.of(ctx).unfocus();
                      },
                      child: itemBuilder(ctx, item),
                    ),
                  ),
          onSelected: (item) {
            onSelected(item);
            FocusScope.of(context).unfocus();
          },
          builder: (context, controller, focusNode) {
            return Shortcuts(
              shortcuts: const <ShortcutActivator, Intent>{
                SingleActivator(LogicalKeyboardKey.arrowDown):
                    DirectionalFocusIntent(TraversalDirection.down),
                SingleActivator(LogicalKeyboardKey.arrowUp):
                    DirectionalFocusIntent(TraversalDirection.up),
              },
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: autoFocus,
                textInputAction: textInputAction,
                onSubmitted: onSubmitted,
                style: TextStyle(
                  color: primaryTextColor,
                  fontSize: 15,
                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(
                    fontFamily: 'Cairo',
                    color: mutedTextColor,
                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                  ),
                  prefixIcon: prefixIcon,
                  suffixIcon: prefixIcon == null
                      ? Icon(Icons.search,
                          size: 20, color: activeColor)
                      : null,
                  filled: true,
                  fillColor: fieldBg,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: fieldBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: fieldBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        BorderSide(color: activeColor, width: 1.5),
                  ),
                ),
              ),
            );
          },
          decorationBuilder: (context, child) {
            return Material(
              type: MaterialType.card,
              elevation: isDark ? 8 : 4,
              color: popupBg,
              shadowColor: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: popupBorder),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: child,
              ),
            );
          },
        ),
      ],
    );
  }
}
