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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.account_balance, color: AppTheme.primary, size: 16),
            const SizedBox(width: 6),
            const Text(
              'أرصدة الحسابات',
              style: TextStyle(
                color: Colors.white,
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
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontFamily: 'Cairo')),
                ),
                ...treasuryBalances.map((b) => _balanceTile(
                  b['name']?.toString() ?? 'خزينة',
                  (b['balance'] as num?)?.toDouble() ?? 0,
                  b['currency']?.toString() ?? 'EGP',
                  AppTheme.primary,
                )),
                const SizedBox(height: 8),
              ],
              if (bankBalances.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('البنوك',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontFamily: 'Cairo')),
                ),
                ...bankBalances.map((b) => _balanceTile(
                  b['name']?.toString() ?? 'بنك',
                  (b['balance'] as num?)?.toDouble() ?? 0,
                  b['currency']?.toString() ?? 'EGP',
                  AppTheme.accent,
                )),
              ],
              if (treasuryBalances.isEmpty && bankBalances.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Column(
                      children: [
                        Icon(Icons.account_balance, color: AppTheme.textMuted, size: 32),
                        const SizedBox(height: 8),
                        Text('لا توجد أرصدة',
                            style: TextStyle(color: AppTheme.textMuted, fontFamily: 'Cairo')),
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

  Widget _balanceTile(String name, double balance, String currency, Color color) {
    final maxBalance = 1000000.0;
    final progress = balance > 0 ? (balance / maxBalance).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(name,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Cairo'),
                      overflow: TextOverflow.ellipsis),
                ),
                Text(
                  '${balance.toStringAsFixed(2)} $currency',
                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white.withAlpha(10),
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
