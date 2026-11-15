// lib/ui/widgets/app_dropdown.dart
// ─────────────────────────────────────────────
// Premium dark glass searchable dropdown
// ─────────────────────────────────────────────

import 'package:dropdown_search/dropdown_search.dart';
import 'package:flutter/material.dart';
import '../../core/theme.dart';

class AppDropdown<T> extends StatelessWidget {
  final String label;
  final String? hint;
  final T? selectedItem;
  final List<T> items;
  final String Function(T)? itemAsString;
  final void Function(T?) onChanged;
  final bool isRequired;
  final bool showSearch;
  final FocusNode? focusNode;
  final String? Function(T?)? validator;

  const AppDropdown({
    super.key,
    required this.label,
    required this.items,
    required this.onChanged,
    this.selectedItem,
    this.hint,
    this.itemAsString,
    this.isRequired = false,
    this.showSearch = true,
    this.focusNode,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : AppTheme.lightTextPrimary;
    final secondaryTextColor = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;
    final mutedTextColor = isDark ? Colors.white.withValues(alpha: 0.35) : AppTheme.lightTextMuted;
    final fieldBg = isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white;
    final fieldBorder = isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFCBD5E1);
    final menuBg = isDark ? const Color(0xFF0A1E38) : Colors.white;
    final menuBorder = isDark ? AppTheme.glassBorder : AppTheme.lightBorder;
    final activeColor = isDark ? AppTheme.primary : AppTheme.lightPrimary;

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
        DropdownSearch<T>(
          items: (filter, loadProps) => items,
          selectedItem: selectedItem,
          onChanged: onChanged,
          validator: validator,
          itemAsString: itemAsString,
          compareFn: (a, b) => a == b,
          popupProps: PopupProps.menu(
            showSearchBox: showSearch || items.length > 5,
            searchFieldProps: TextFieldProps(
              style: TextStyle(
                color: primaryTextColor,
                fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                fontFamily: 'Cairo',
              ),
              decoration: InputDecoration(
                hintText: 'بحث...',
                hintStyle: TextStyle(
                  color: mutedTextColor,
                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                ),
                filled: true,
                fillColor: isDark ? const Color(0x1A00E5FF) : const Color(0xFFF1F5F9),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: fieldBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: fieldBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: activeColor, width: 1.5),
                ),
              ),
            ),
            menuProps: MenuProps(
              elevation: isDark ? 8 : 4,
              color: menuBg,
              shadowColor: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: menuBorder),
              ),
            ),
            itemBuilder: (context, item, isSelected, isHighlighted) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isHighlighted
                      ? activeColor.withValues(alpha: 0.10)
                      : null,
                ),
                child: Text(
                  itemAsString?.call(item) ?? item.toString(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? activeColor : primaryTextColor,
                    fontFamily: 'Cairo',
                  ),
                ),
              );
            },
          ),
          decoratorProps: DropDownDecoratorProps(
            baseStyle: TextStyle(
              color: primaryTextColor,
              fontSize: 14,
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
              filled: true,
              fillColor: fieldBg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                borderSide: BorderSide(color: activeColor, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.danger),
              ),
            ),
          ),
          autoValidateMode: AutovalidateMode.onUserInteraction,
        ),
      ],
    );
  }
}
