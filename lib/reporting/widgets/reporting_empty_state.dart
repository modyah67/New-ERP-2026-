library;

import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// Reusable empty state for any report that has no data.
class ReportingEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const ReportingEmptyState({
    super.key,
    this.icon = Icons.balance_outlined,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: AppTheme.textMuted),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textSecondary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
