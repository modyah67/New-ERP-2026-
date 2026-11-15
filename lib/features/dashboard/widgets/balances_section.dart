import 'package:flutter/material.dart';
import '../../../core/theme.dart';

class BalancesSection extends StatelessWidget {
  final List<Map<String, dynamic>> treasuryBalances;
  final List<Map<String, dynamic>> bankBalances;

  const BalancesSection({
    super.key,
    required this.treasuryBalances,
    required this.bankBalances,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : Colors.black;
    final mutedTextColor = isDark ? AppTheme.textMuted : Colors.black;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.account_balance, color: AppTheme.primary, size: 16),
            const SizedBox(width: 6),
            Text(
              'أرصدة الحسابات',
              style: TextStyle(
                color: primaryTextColor,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            children: [
              if (treasuryBalances.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('الخزينة',
                      style: TextStyle(color: mutedTextColor, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                ),
                ...treasuryBalances.map((b) => _balanceTile(
                  b['name']?.toString() ?? 'خزينة',
                  (b['balance'] as num?)?.toDouble() ?? 0,
                  b['currency']?.toString() ?? 'EGP',
                  AppTheme.primary,
                  isDark,
                )),
                const SizedBox(height: 8),
              ],
              if (bankBalances.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('البنوك',
                      style: TextStyle(color: mutedTextColor, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                ),
                ...bankBalances.map((b) => _balanceTile(
                  b['name']?.toString() ?? 'بنك',
                  (b['balance'] as num?)?.toDouble() ?? 0,
                  b['currency']?.toString() ?? 'EGP',
                  AppTheme.accent,
                  isDark,
                )),
              ],
              if (treasuryBalances.isEmpty && bankBalances.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Column(
                      children: [
                        Icon(Icons.account_balance, color: isDark ? mutedTextColor : Colors.black87, size: 32),
                        const SizedBox(height: 8),
                        Text('لا توجد أرصدة',
                            style: TextStyle(color: isDark ? mutedTextColor : Colors.black, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _balanceTile(String name, double balance, String currency, Color color, bool isDark) {
    const maxBalance = 1000000.0;
    final progress = balance > 0 ? (balance / maxBalance).clamp(0.0, 1.0) : 0.0;
    final tileBg = isDark ? Colors.white.withAlpha(5) : const Color(0xFFF8FAFC);
    final tileBorder = isDark ? Colors.white.withAlpha(10) : const Color(0xFFCBD5E1);
    final tileTextColor = isDark ? Colors.white : Colors.black;
    final progressBg = isDark ? Colors.white.withAlpha(10) : const Color(0xFFE2E8F0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: tileBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: tileBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(name,
                      style: TextStyle(color: tileTextColor, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                      overflow: TextOverflow.ellipsis),
                ),
                Text(
                  '${balance.toStringAsFixed(2)} $currency',
                  style: TextStyle(
                    color: isDark ? color : Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: progressBg,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
