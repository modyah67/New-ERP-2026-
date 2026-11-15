import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../theme.dart';

/// حوار تأكيد حذف بند تكلفة تقديري قبل اعتماد تسويته أو ترحيله للقيود
Future<bool> showDeleteEstimatedCostItemDialog(
  BuildContext context, {
  required String itemName,
  required String orderNumber,
  required double estimatedAmount,
}) async {
  final fNumber = NumberFormat('#,##0.00');
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final isDark = AppTheme.isDark(ctx);
      return Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppTheme.getCardBg(ctx),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: AppTheme.getBorderColor(ctx)),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppTheme.danger,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'حذف بند تكلفة تقديري',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.getTextPrimary(ctx),
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'هل أنت متأكد من حذف هذا البند التقديري؟',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.getTextPrimary(ctx),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.getBorderColor(ctx)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'البند: $itemName',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.getTextPrimary(ctx),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'أمر التعبئة: #$orderNumber  |  التكلفة التقديرية: EGP ${fNumber.format(estimatedAmount)}',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11.5,
                        color: AppTheme.getTextSecondary(ctx),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'سيتم إزالة هذا البند التقديري المعلق فقط دون أي تأثير على الحسابات أو أرصدة الموردين أو القيود المرحّلة.',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  color: AppTheme.getTextSecondary(ctx),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'إلغاء',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  color: AppTheme.getTextSecondary(ctx),
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.delete_rounded, size: 16),
              label: const Text(
                'تأكيد الحذف',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.danger,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
  return result == true;
}

/// زر حذف أيقوني موحد للبنود التقديرية غير المعتمدة داخل جداول تسوية التكاليف
class EstimatedCostDeleteButton extends StatelessWidget {
  final bool isDeleting;
  final VoidCallback? onPressed;

  const EstimatedCostDeleteButton({
    super.key,
    required this.isDeleting,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'حذف البند التقديري',
      child: Material(
        color: AppTheme.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: isDeleting ? null : onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: AppTheme.danger.withValues(alpha: 0.35),
              ),
            ),
            child: isDeleting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.danger,
                    ),
                  )
                : const Icon(
                    Icons.delete_outline_rounded,
                    size: 17,
                    color: AppTheme.danger,
                  ),
          ),
        ),
      ),
    );
  }
}

