library;

import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// Transparent overlay with a spinner, shown during refresh operations.
/// Does not replace the existing content — sits on top via Stack.
class ReportingLoadingOverlay extends StatelessWidget {
  final bool isVisible;

  const ReportingLoadingOverlay({super.key, required this.isVisible});

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    final isDark = AppTheme.isDark(context);
    final primary = isDark ? AppTheme.primary : AppTheme.lightPrimary;

    return Positioned(
      top: 8,
      left: 8,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: primary.withAlpha(30),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: primary,
          ),
        ),
      ),
    );
  }
}
