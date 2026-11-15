import 'package:flutter/material.dart';
import '../../../core/theme.dart';

class TopFruitsWidget extends StatelessWidget {
  final List<Map<String, dynamic>> products;

  const TopFruitsWidget({super.key, required this.products});

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
            const Icon(Icons.eco, color: AppTheme.success, size: 16),
            const SizedBox(width: 6),
            Text(
              'أكثر الأصناف مبيعاً',
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
          child: products.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.eco_outlined, color: isDark ? mutedTextColor : Colors.black87, size: 32),
                      const SizedBox(height: 8),
                      Text('لا توجد بيانات مبيعات',
                          style: TextStyle(
                            color: isDark ? mutedTextColor : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          )),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: products.take(10).length,
                  itemBuilder: (_, i) {
                    final p = products[i];
                    final name = p['name']?.toString() ?? '—';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: _rankColor(i).withAlpha(isDark ? 30 : 40),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: _rankColor(i).withAlpha(isDark ? 80 : 120), width: 1),
                            ),
                            child: Center(
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  color: isDark ? _rankColor(i) : Colors.black,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(
                                color: primaryTextColor,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Color _rankColor(int index) {
    const colors = [
      Color(0xFFFFD700),
      Color(0xFFC0C0C0),
      Color(0xFFCD7F32),
      AppTheme.accent,
      AppTheme.primary,
      AppTheme.cyan,
      AppTheme.warning,
      AppTheme.success,
    ];
    return colors[index % colors.length];
  }
}
