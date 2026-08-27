import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';

class QuickActionsGrid extends StatelessWidget {
  const QuickActionsGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.bolt, color: AppTheme.warning, size: 16),
            const SizedBox(width: 6),
            const Text(
              'إجراءات سريعة',
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _actionCard(context, 'إنشاء شحنة', Icons.flight_takeoff, AppTheme.primary, '/exports'),
            _actionCard(context, 'عميل', Icons.person_add, AppTheme.accent, '/customers'),
            _actionCard(context, 'مورد', Icons.local_shipping, AppTheme.warning, '/suppliers'),
            _actionCard(context, 'شراء', Icons.shopping_cart, const Color(0xFF8B5CF6), '/purchases'),
            _actionCard(context, 'تحويل مخزن', Icons.swap_horiz, const Color(0xFFEC4899), '/transfers'),
          ],
        ),
      ],
    );
  }

  Widget _actionCard(BuildContext context, String label, IconData icon, Color color, String route) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push(route),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 160,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
            decoration: BoxDecoration(
              color: color.withAlpha(12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withAlpha(40)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: color.withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 10),
                Text(label,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
