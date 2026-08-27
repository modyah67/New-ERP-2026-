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
                      style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: widget.searchHint ?? 'بحث...',
                        hintStyle:
                            TextStyle(color: AppTheme.textMuted, fontSize: 12),
                        prefixIcon: Icon(Icons.search,
                            size: 16, color: AppTheme.textMuted),
                        filled: true,
                        fillColor: Colors.white.withAlpha(8),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                              color: AppTheme.primary.withAlpha(80), width: 1),
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
                        size: 18, color: AppTheme.textSecondary),
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
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? AppTheme.primary.withAlpha(30)
              : Colors.white.withAlpha(8),
          borderRadius: BorderRadius.circular(8),
          border:
              isActive ? Border.all(color: AppTheme.primary.withAlpha(50)) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isActive ? AppTheme.primary : AppTheme.textSecondary,
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
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(8),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(8),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.border.withAlpha(80)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 14, color: AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
          ],
        ),
      ),
    );
  }
}
