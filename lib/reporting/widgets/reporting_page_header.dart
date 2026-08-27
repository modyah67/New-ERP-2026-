library;

import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// Reusable page header with icon, title, count badge, and action buttons.
class ReportingPageHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final int? count;
  final String? countLabel;
  final List<Widget> actions;

  const ReportingPageHeader({
    super.key,
    this.icon = Icons.balance_outlined,
    required this.title,
    this.count,
    this.countLabel,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(25),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 26),
          ),
          const SizedBox(width: 14),
          Text(
            title,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${countLabel ?? ''} ${count!}',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(width: 24),
          ...actions,
        ],
      ),
    );
  }
}
