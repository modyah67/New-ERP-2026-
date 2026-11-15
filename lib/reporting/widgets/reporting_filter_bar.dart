library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// A composable filter bar. Reports supply the content via [child].
///
/// The bar provides the glass-card container, search box with debounce,
/// and reset button. Report-specific filters go in [child].
class ReportingFilterBar extends StatefulWidget {
  final Widget child;
  final Function(String)? onSearchChanged;
  final String? searchHint;
  final VoidCallback? onReset;

  const ReportingFilterBar({
    super.key,
    required this.child,
    this.onSearchChanged,
    this.searchHint,
    this.onReset,
  });

  @override
  State<ReportingFilterBar> createState() => _ReportingFilterBarState();
}

class _ReportingFilterBarState extends State<ReportingFilterBar> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      widget.onSearchChanged?.call(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final textPrimary = AppTheme.getTextPrimary(context);
    final textMuted = isDark ? AppTheme.textMuted : AppTheme.lightTextMuted;
    final textSecondary = AppTheme.getTextSecondary(context);
    final primary = isDark ? AppTheme.primary : AppTheme.lightPrimary;
    final searchFill = isDark ? Colors.white.withAlpha(8) : const Color(0xFFF1F5F9);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: AppTheme.glassCard().copyWith(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                widget.child,
                if (widget.onSearchChanged != null) ...[
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 200,
                    height: 36,
                    child: TextField(
                      onChanged: _onSearchChanged,
                      style: TextStyle(color: textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: widget.searchHint ?? 'بحث...',
                        hintStyle: TextStyle(color: textMuted, fontSize: 12),
                        prefixIcon:
                            Icon(Icons.search, size: 16, color: textMuted),
                        filled: true,
                        fillColor: searchFill,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                              color: primary.withAlpha(80), width: 1),
                        ),
                      ),
                    ),
                  ),
                ],
                if (widget.onReset != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: widget.onReset,
                    icon: Icon(Icons.restart_alt,
                        size: 18, color: textSecondary),
                    tooltip: 'إعادة ضبط',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A styled toggle button for filter bar use.
class ReportingToggleButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onPressed;

  const ReportingToggleButton({
    super.key,
    required this.label,
    required this.isActive,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final primary = isDark ? AppTheme.primary : AppTheme.lightPrimary;
    final textSecondary = AppTheme.getTextSecondary(context);
    final inactiveBg = isDark ? Colors.white.withAlpha(8) : const Color(0xFFF1F5F9);

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? primary.withAlpha(30) : inactiveBg,
          borderRadius: BorderRadius.circular(8),
          border: isActive ? Border.all(color: primary.withAlpha(50)) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isActive ? primary : textSecondary,
          ),
        ),
      ),
    );
  }
}

/// A styled preset button for filter bar use (e.g., date range presets).
class ReportingPresetButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const ReportingPresetButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final textSecondary = AppTheme.getTextSecondary(context);
    final bg = isDark ? Colors.white.withAlpha(8) : const Color(0xFFF1F5F9);

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 12, color: textSecondary)),
      ),
    );
  }
}

/// A styled date chip for filter bar use.
class ReportingDateChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const ReportingDateChip({
    super.key,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final textPrimary = AppTheme.getTextPrimary(context);
    final textSecondary = AppTheme.getTextSecondary(context);
    final borderColor = AppTheme.getBorderColor(context);
    final bg = isDark ? Colors.white.withAlpha(8) : const Color(0xFFF1F5F9);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor.withAlpha(80)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 14, color: textSecondary),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(fontSize: 12, color: textPrimary)),
          ],
        ),
      ),
    );
  }
}
