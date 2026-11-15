library;

import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../accounting/reporting/models/report_models.dart';

/// Reusable validation panel showing balanced/unbalanced status and totals.
class ReportingValidationPanel extends StatelessWidget {
  final bool isBalanced;
  final double totalDebit;
  final double totalCredit;
  final double difference;
  final ValidationResult? validationResult;
  final String? debitLabel;
  final String? creditLabel;
  final String? differenceLabel;
  final bool showStatusBadge;

  const ReportingValidationPanel({
    super.key,
    required this.isBalanced,
    required this.totalDebit,
    required this.totalCredit,
    required this.difference,
    this.validationResult,
    this.debitLabel,
    this.creditLabel,
    this.differenceLabel,
    this.showStatusBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: isBalanced
            ? AppTheme.success.withAlpha(15)
            : AppTheme.danger.withAlpha(15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isBalanced
              ? AppTheme.success.withAlpha(50)
              : AppTheme.danger.withAlpha(50),
          width: 1,
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Icon(
              isBalanced
                  ? Icons.check_circle_outline
                  : Icons.warning_amber_outlined,
              color: isBalanced ? AppTheme.success : AppTheme.danger,
              size: 22,
            ),
            const SizedBox(width: 12),
            _buildStat(context, debitLabel ?? 'إجمالي المدين', totalDebit),
            const SizedBox(width: 24),
            _buildStat(context, creditLabel ?? 'إجمالي الدائن', totalCredit),
            const SizedBox(width: 24),
            _buildStat(context, differenceLabel ?? 'الفرق', difference, isDifference: true),
            if (showStatusBadge) ...[
              const SizedBox(width: 24),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isBalanced
                      ? AppTheme.success.withAlpha(30)
                      : AppTheme.danger.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isBalanced ? 'متوازن ✓' : 'غير متوازن ⚠',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isBalanced
                        ? AppTheme.success
                        : AppTheme.danger,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStat(BuildContext context, String label, double value,
      {bool isDifference = false}) {
    final textPrimary = AppTheme.getTextPrimary(context);
    final textSecondary = AppTheme.getTextSecondary(context);
    final color = isDifference && value.abs() > 0.01
        ? AppTheme.danger
        : textPrimary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
              fontSize: 11,
              color: textSecondary,
              fontFamily: 'Cairo',
            )),
        const SizedBox(height: 2),
        Text(
          AppUtils.formatNumber(value),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
            fontFamily: 'Cairo',
          ),
        ),
      ],
    );
  }
}
