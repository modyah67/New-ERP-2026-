library;

import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../models/reporting_models.dart';

/// Reusable action toolbar with export buttons and fullscreen toggle.
///
/// Reports supply [exportActions] — the toolbar renders them as buttons.
/// Refresh and fullscreen are standard actions.
class ReportingToolbar extends StatelessWidget {
  final VoidCallback onRefresh;
  final VoidCallback onFullscreen;
  final List<ExportAction> exportActions;

  const ReportingToolbar({
    super.key,
    required this.onRefresh,
    required this.onFullscreen,
    this.exportActions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: AppTheme.glassCard().copyWith(
        borderRadius: BorderRadius.circular(14),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ToolButton(
              icon: Icons.refresh_outlined,
              label: 'تحديث',
              onPressed: onRefresh,
            ),
            const SizedBox(width: 8),
            for (final action in exportActions) ...[
              _ToolButton(
                icon: action.icon,
                label: action.label,
                onPressed: action.onPressed,
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ToolButton({
    required this.icon,
    required this.label,
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
          color: Colors.white.withAlpha(8),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppTheme.textSecondary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
