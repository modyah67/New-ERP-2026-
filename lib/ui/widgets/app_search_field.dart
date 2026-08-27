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
    final hl = highlightColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            text: label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
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
          loadingBuilder: (context) => const Padding(
            padding: EdgeInsets.all(8.0),
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.primary,
              ),
            ),
          ),
          emptyBuilder: emptyBuilder ??
              (context) => const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Text('لا توجد نتائج',
                        style: TextStyle(
                            color: AppTheme.textMuted, fontFamily: 'Cairo')),
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
              shortcuts: <ShortcutActivator, Intent>{
                SingleActivator(LogicalKeyboardKey.arrowDown):
                    const DirectionalFocusIntent(TraversalDirection.down),
                SingleActivator(LogicalKeyboardKey.arrowUp):
                    const DirectionalFocusIntent(TraversalDirection.up),
              },
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: autoFocus,
                textInputAction: textInputAction,
                onSubmitted: onSubmitted,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontFamily: 'Cairo',
                ),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(
                    fontFamily: 'Cairo',
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                  prefixIcon: prefixIcon,
                  suffixIcon: prefixIcon == null
                      ? const Icon(Icons.search,
                          size: 20, color: AppTheme.primary)
                      : null,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: AppTheme.primary, width: 1.5),
                  ),
                ),
              ),
            );
          },
          decorationBuilder: (context, child) {
            return Material(
              type: MaterialType.card,
              elevation: 8,
              borderRadius: BorderRadius.circular(14),
              color: const Color(0xFF0A1E38),
              shadowColor: Colors.black.withValues(alpha: 0.4),
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
