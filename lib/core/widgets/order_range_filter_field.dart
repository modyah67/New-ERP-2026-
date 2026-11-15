import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Pure utility helpers for parsing, matching, and formatting shipment /
/// packing order number ranges across actual cost settlement views and queries.
class OrderRangeFilterHelper {
  OrderRangeFilterHelper._();

  static final RegExp _digitSeqRegex = RegExp(r'\d+');

  /// Converts Arabic-Indic (`٠`–`٩`) and Eastern Arabic-Indic (`۰`–`۹`)
  /// numerals into ASCII `'0'`–`'9'`.
  static String normalizeDigits(String input) {
    if (input.isEmpty) return input;
    final buffer = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final code = input.codeUnitAt(i);
      if (code >= 0x0660 && code <= 0x0669) {
        buffer.writeCharCode(0x30 + (code - 0x0660));
      } else if (code >= 0x06F0 && code <= 0x06F9) {
        buffer.writeCharCode(0x30 + (code - 0x06F0));
      } else {
        buffer.writeCharCode(code);
      }
    }
    return buffer.toString();
  }

  /// Parses an optional lower or upper filter bound entered by the user.
  /// Returns `null` when empty or containing no parseable integer.
  static int? parseFilterBound(String? raw) {
    if (raw == null) return null;
    final trimmed = normalizeDigits(raw).trim();
    if (trimmed.isEmpty) return null;
    final direct = int.tryParse(trimmed);
    if (direct != null) return direct;
    final match = _digitSeqRegex.allMatches(trimmed).lastOrNull;
    if (match == null) return null;
    return int.tryParse(match.group(0)!);
  }

  /// Extracts the numeric order identifier from [orderNumber] (supporting
  /// formats like `'105'`, `'#105'`, `'PO-105'`, `'أمر #١٠٥'`), falling back
  /// to [packingOrderId] when [orderNumber] has no digits.
  static int? extractNumericOrderId({
    String? orderNumber,
    int? packingOrderId,
  }) {
    if (orderNumber != null) {
      final normalized = normalizeDigits(orderNumber).trim();
      if (normalized.isNotEmpty) {
        final direct = int.tryParse(normalized);
        if (direct != null) return direct;
        final lastMatch = _digitSeqRegex.allMatches(normalized).lastOrNull;
        if (lastMatch != null) {
          final parsed = int.tryParse(lastMatch.group(0)!);
          if (parsed != null) return parsed;
        }
      }
    }
    return packingOrderId;
  }

  /// Returns `true` when the item's numeric order ID lies inclusively within
  /// `[fromOrderId, toOrderId]`. Open bounds (`null`) leave that side unbounded.
  static bool matchesOrderRange({
    String? orderNumber,
    int? packingOrderId,
    int? fromOrderId,
    int? toOrderId,
  }) {
    if (fromOrderId == null && toOrderId == null) return true;
    final numericId = extractNumericOrderId(
      orderNumber: orderNumber,
      packingOrderId: packingOrderId,
    );
    if (numericId == null) return false;
    if (fromOrderId != null && numericId < fromOrderId) return false;
    if (toOrderId != null && numericId > toOrderId) return false;
    return true;
  }

  /// Formats a human-readable Arabic label describing the active order range,
  /// or returns `null` when no bound is set.
  static String? formatRangeLabel({
    int? fromOrderId,
    int? toOrderId,
  }) {
    if (fromOrderId == null && toOrderId == null) return null;
    if (fromOrderId != null && toOrderId != null) {
      if (fromOrderId == toOrderId) {
        return 'شحنة / أمر #$fromOrderId';
      }
      return 'من شحنة / أمر #$fromOrderId إلى #$toOrderId';
    }
    if (fromOrderId != null) {
      return 'من شحنة / أمر #$fromOrderId';
    }
    return 'حتى شحنة / أمر #$toOrderId';
  }
}

/// Compact reusable RTL filter widget for filtering settlements by shipment /
/// packing order number range (`من شحنة / أمر [X] إلى [Y]`).
class OrderRangeFilterBar extends StatelessWidget {
  final TextEditingController fromController;
  final TextEditingController toController;
  final bool isDark;
  final VoidCallback? onChanged;
  final VoidCallback? onApplyQuery;
  final VoidCallback? onClear;
  final Color activeColor;
  final double fieldWidth;
  final double height;

  const OrderRangeFilterBar({
    super.key,
    required this.fromController,
    required this.toController,
    this.isDark = false,
    this.onChanged,
    this.onApplyQuery,
    this.onClear,
    this.activeColor = const Color(0xFF0D9488),
    this.fieldWidth = 96,
    this.height = 36,
  });

  static final List<TextInputFormatter> _orderInputFormatters = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9\u0660-\u0669\u06F0-\u06F9]')),
  ];

  @override
  Widget build(BuildContext context) {
    final fromVal = OrderRangeFilterHelper.parseFilterBound(fromController.text);
    final toVal = OrderRangeFilterHelper.parseFilterBound(toController.text);
    final hasRange = fromVal != null || toVal != null;
    final isInverted = fromVal != null && toVal != null && fromVal > toVal;

    final borderColor = isInverted
        ? Colors.redAccent
        : (hasRange
            ? activeColor.withValues(alpha: 0.75)
            : (isDark ? Colors.white24 : Colors.grey.shade300));

    final bgColor = hasRange
        ? activeColor.withValues(alpha: isDark ? 0.14 : 0.06)
        : (isDark ? const Color(0xFF1E293B) : Colors.white);

    return Tooltip(
      message: isInverted
          ? 'تنبيه: رقم البداية أكبر من رقم النهاية'
          : 'فلترة بنطاق أرقام الشحنات / أوامر التعبئة (شامل الطرفين)',
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: borderColor,
            width: hasRange ? 1.2 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.tag_rounded,
              size: 15,
              color: isInverted
                  ? Colors.redAccent
                  : (hasRange ? activeColor : Colors.grey),
            ),
            const SizedBox(width: 4),
            _buildBoundField(
              controller: fromController,
              hint: 'من شحنة/أمر',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '—',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                ),
              ),
            ),
            _buildBoundField(
              controller: toController,
              hint: 'إلى شحنة/أمر',
            ),
            if (onApplyQuery != null) ...[
              const SizedBox(width: 2),
              InkWell(
                onTap: onApplyQuery,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Tooltip(
                    message: 'تطبيق الاستعلام على الخادم بالنطاق المحدد',
                    child: Icon(
                      Icons.filter_alt_rounded,
                      size: 16,
                      color: hasRange ? activeColor : Colors.grey,
                    ),
                  ),
                ),
              ),
            ],
            if (hasRange) ...[
              const SizedBox(width: 2),
              InkWell(
                onTap: () {
                  fromController.clear();
                  toController.clear();
                  if (onClear != null) {
                    onClear!();
                  } else {
                    onChanged?.call();
                  }
                },
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Tooltip(
                    message: 'مسح نطاق الشحنات / الأوامر',
                    child: Icon(
                      Icons.close_rounded,
                      size: 15,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBoundField({
    required TextEditingController controller,
    required String hint,
  }) {
    return SizedBox(
      width: fieldWidth,
      height: height - 6,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.search,
        inputFormatters: _orderInputFormatters,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black87,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.normal,
            color: isDark ? Colors.white54 : Colors.grey.shade500,
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
              color: isDark ? Colors.white12 : Colors.grey.shade200,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
              color: isDark ? Colors.white12 : Colors.grey.shade200,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: activeColor, width: 1.2),
          ),
          filled: true,
          fillColor: isDark ? const Color(0xFF0F172A) : Colors.grey.shade50,
        ),
        onChanged: (_) => onChanged?.call(),
        onSubmitted: (_) {
          if (onApplyQuery != null) {
            onApplyQuery!();
          } else {
            onChanged?.call();
          }
        },
      ),
    );
  }
}

