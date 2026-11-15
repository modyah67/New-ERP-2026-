// lib/ui/widgets/app_text_field.dart
// ─────────────────────────────────────────────
// Premium dark glass text field
// ─────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';

class AppTextField extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextDirection textDirection;
  final int maxLines;
  final bool readOnly;
  final VoidCallback? onTap;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final List<TextInputFormatter>? inputFormatters;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final TextInputAction textInputAction;
  final bool isRequired;
  final bool autoFocus;
  final String? errorText;
  final String? helperText;

  const AppTextField({
    super.key,
    required this.label,
    required this.controller,
    this.focusNode,
    this.hint,
    this.validator,
    this.keyboardType,
    this.textDirection = TextDirection.rtl,
    this.maxLines = 1,
    this.readOnly = false,
    this.onTap,
    this.suffixIcon,
    this.prefixIcon,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction = TextInputAction.next,
    this.isRequired = false,
    this.autoFocus = false,
    this.errorText,
    this.helperText,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : AppTheme.lightTextPrimary;
    final secondaryTextColor = isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;
    final mutedTextColor = isDark ? Colors.white.withValues(alpha: 0.35) : AppTheme.lightTextMuted;
    final fieldBg = isDark
        ? (readOnly ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.06))
        : (readOnly ? const Color(0xFFF1F5F9) : Colors.white);
    final fieldBorder = isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFCBD5E1);

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
                      style: TextStyle(
                        color: AppTheme.danger,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ]
                : [],
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          validator: validator,
          keyboardType: keyboardType,
          textDirection: textDirection,
          maxLines: maxLines,
          readOnly: readOnly,
          onTap: onTap,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          textInputAction: textInputAction,
          autofocus: autoFocus,
          style: TextStyle(
            color: readOnly
                ? (isDark ? Colors.white70 : const Color(0xFF334155))
                : primaryTextColor,
            fontSize: 15,
            fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
            fontFamily: 'Cairo',
          ),
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
            suffixIcon: suffixIcon ??
                (readOnly
                    ? Icon(Icons.lock_outline,
                        size: 18,
                        color: isDark ? AppTheme.textMuted : const Color(0xFF64748B))
                    : null),
            prefixIcon: prefixIcon,
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
              borderSide: BorderSide(
                color: readOnly
                    ? fieldBorder
                    : (isDark ? AppTheme.primary : AppTheme.lightPrimary),
                width: readOnly ? 1.0 : 1.8,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppTheme.danger),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppTheme.danger, width: 1.8),
            ),
            hintStyle: TextStyle(
              fontFamily: 'Cairo',
              color: mutedTextColor,
              fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
            ),
            labelStyle: TextStyle(
              fontFamily: 'Cairo',
              color: isDark ? secondaryTextColor : Colors.black,
              fontWeight: isDark ? FontWeight.w600 : FontWeight.bold,
            ),
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 4),
          Text(helperText!,
              style: TextStyle(
                  color: isDark ? AppTheme.textMuted : Colors.black,
                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                  fontSize: 11,
                  fontFamily: 'Cairo')),
        ],
      ],
    );
  }
}
