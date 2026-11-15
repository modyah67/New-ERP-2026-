import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../core/utils.dart';
import '../../../data/models/supplier_model.dart';

/// Reusable, aesthetic widget for displaying multi-currency balances
/// seamlessly within table cells and cards.
class MultiCurrencyBalanceBadge extends StatelessWidget {
  final String balanceText;
  final bool isMulti;
  final bool isNegative;
  final double? egpEquivalent;
  final Map<String, double>? currenciesMap;
  final TextStyle? textStyle;
  final TextAlign textAlign;

  const MultiCurrencyBalanceBadge({
    super.key,
    required this.balanceText,
    this.isMulti = false,
    this.isNegative = false,
    this.egpEquivalent,
    this.currenciesMap,
    this.textStyle,
    this.textAlign = TextAlign.center,
  });

  @override
  Widget build(BuildContext context) {
    final hasDebit = isNegative || (currenciesMap != null && currenciesMap!.values.any((v) => v < -0.001));
    final color = hasDebit ? AppTheme.danger : AppTheme.success;

    if (!isMulti) {
      return Text(
        balanceText,
        style: textStyle ??
            TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'Cairo',
            ),
        textAlign: textAlign,
        overflow: TextOverflow.ellipsis,
      );
    }

    // Build rich tooltip text
    final buffer = StringBuffer();
    if (currenciesMap != null && currenciesMap!.isNotEmpty) {
      buffer.writeln('تفاصيل الأرصدة بالعملات:');
      for (final entry in currenciesMap!.entries) {
        final val = entry.value;
        final dir = val > 0.001 ? 'له' : (val < -0.001 ? 'عليه' : 'متزن');
        final sym = SupplierModel.getCurrencySymbol(entry.key);
        buffer.writeln('• ${entry.key}: ${AppUtils.formatNumber(val.abs())} $sym ($dir)');
      }
      if (egpEquivalent != null && egpEquivalent!.abs() > 0) {
        final eqDir = egpEquivalent! > 0.001 ? 'له' : (egpEquivalent! < -0.001 ? 'عليه' : 'متزن');
        buffer.write('المعادل بالجنيه: ≈ ${AppUtils.formatNumber(egpEquivalent!.abs())} ج.م ($eqDir)');
      }
    } else {
      buffer.write(balanceText);
      if (egpEquivalent != null && egpEquivalent!.abs() > 0) {
        final eqDir = egpEquivalent! > 0.001 ? 'له' : (egpEquivalent! < -0.001 ? 'عليه' : 'متزن');
        buffer.write('\nالمعادل بالجنيه: ≈ ${AppUtils.formatNumber(egpEquivalent!.abs())} ج.م ($eqDir)');
      }
    }

    return Tooltip(
      message: buffer.toString().trim(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F2B48),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
      ),
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontFamily: 'Cairo',
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
            ),
            child: Text(
              balanceText,
              style: textStyle ??
                  TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontFamily: 'Cairo',
                    letterSpacing: -0.2,
                  ),
              textAlign: textAlign,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (egpEquivalent != null && egpEquivalent!.abs() > 0) ...[
            const SizedBox(height: 2),
            Text(
              '≈ ${AppUtils.formatNumber(egpEquivalent!.abs())} ج.م ${egpEquivalent! < -0.001 ? '(عليه)' : '(له)'}',
              style: TextStyle(
                fontSize: 9.5,
                color: Colors.white.withValues(alpha: 0.65),
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w500,
              ),
              textAlign: textAlign,
            ),
          ],
        ],
      ),
    );
  }
}
