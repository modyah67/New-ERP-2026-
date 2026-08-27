// lib/core/utils.dart
// Pure Dart — no external packages needed.

class AppUtils {

  // ── Date helpers ──────────────────────────

  static String formatDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString();
    return '$d/$m/$y';
  }

  static String formatDateForDb(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString();
    return '$y-$m-$d';
  }

  static DateTime parseDate(String dateStr) {
    // Expects 'yyyy-MM-dd'
    final parts = dateStr.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  // ── Number helpers ────────────────────────
  
  static double roundDouble(double value, {int places = 2}) {
    return double.parse(value.toStringAsFixed(places));
  }

  // Formats 1234567.5 → "1,234,567.50 ج.م" (default EGP)
  // formatCurrency(100, 'USD') → "100.00 $"
  static String formatCurrency(double amount, [String currency = 'EGP']) {
    return '${_formatWithCommas(amount)} ${currencySymbol(currency)}';
  }

  // Returns the symbol for a currency code
  static String currencySymbol(String code) {
    switch (code.toUpperCase()) {
      case 'USD': return '\$';
      case 'EUR': return '\u20AC';
      case 'GBP': return '\u00A3';
      case 'EGP': return 'ج.م';
      default: return code.toUpperCase();
    }
  }

  // Returns the Arabic name for a currency code
  static String currencyName(String code) {
    switch (code.toUpperCase()) {
      case 'EGP': return 'مصري';
      case 'USD': return 'دولار';
      case 'EUR': return 'يورو';
      case 'GBP': return 'استرليني';
      default: return code.toUpperCase();
    }
  }

  // Formats 1234567.5 → "1,234,567.50"
  static String formatNumber(double number) {
    return _formatWithCommas(number);
  }

  static String _formatWithCommas(double number) {
    final parts = number.toStringAsFixed(2).split('.');
    final intPart = parts[0];
    final decPart = parts[1];

    // Insert comma every 3 digits from the right
    final buffer = StringBuffer();
    final digits = intPart.replaceAll('-', '');
    final isNegative = number < 0;
    int count = 0;

    for (int i = digits.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
      count++;
    }

    final reversed = buffer.toString().split('').reversed.join('');
    return '${isNegative ? '-' : ''}$reversed.$decPart';
  }

  // ── Arabic number words ───────────────────
  // 1250.50 → "ألف ومئتان وخمسون جنيهاً وخمسون قرشاً"

  static String numberToArabicWords(double amount) {
    if (amount < 0) return 'سالب ${numberToArabicWords(-amount)}';

    final int pounds = amount.floor();
    final int piasters = ((amount - pounds) * 100).round();

    String result = pounds == 0 ? 'صفر' : _intToArabic(pounds);
    result += ' جنيهاً';

    if (piasters > 0) {
      result += ' و${_intToArabic(piasters)} قرشاً';
    }

    return result;
  }

  static const List<String> _ones = [
    '', 'واحد', 'اثنان', 'ثلاثة', 'أربعة', 'خمسة',
    'ستة', 'سبعة', 'ثمانية', 'تسعة', 'عشرة',
    'أحد عشر', 'اثنا عشر', 'ثلاثة عشر', 'أربعة عشر',
    'خمسة عشر', 'ستة عشر', 'سبعة عشر', 'ثمانية عشر', 'تسعة عشر',
  ];

  static const List<String> _tens = [
    '', '', 'عشرون', 'ثلاثون', 'أربعون', 'خمسون',
    'ستون', 'سبعون', 'ثمانون', 'تسعون',
  ];

  static const List<String> _hundreds = [
    '', 'مئة', 'مئتان', 'ثلاثمئة', 'أربعمئة', 'خمسمئة',
    'ستمئة', 'سبعمئة', 'ثمانمئة', 'تسعمئة',
  ];

  static String _intToArabic(int number) {
    if (number == 0) return 'صفر';
    if (number < 0)  return 'سالب ${_intToArabic(-number)}';

    final parts = <String>[];

    if (number >= 1000000) {
      final millions = number ~/ 1000000;
      parts.add('${_intToArabic(millions)} مليون');
      number %= 1000000;
    }

    if (number >= 1000) {
      final thousands = number ~/ 1000;
      if (thousands == 1)       parts.add('ألف');
      else if (thousands == 2)  parts.add('ألفان');
      else if (thousands <= 10) parts.add('${_ones[thousands]} آلاف');
      else                      parts.add('${_intToArabic(thousands)} ألف');
      number %= 1000;
    }

    if (number >= 100) {
      parts.add(_hundreds[number ~/ 100]);
      number %= 100;
    }

    if (number >= 20) {
      final t = number ~/ 10;
      final o = number % 10;
      parts.add(o > 0 ? '${_ones[o]} و${_tens[t]}' : _tens[t]);
    } else if (number > 0) {
      parts.add(_ones[number]);
    }

    return parts.join(' و');
  }

  // ── String helpers ────────────────────────

  static bool isNullOrEmpty(String? value) {
    return value == null || value.trim().isEmpty;
  }

  static String generateCode(String prefix, int id) {
    return '$prefix${id.toString().padLeft(6, '0')}';
  }

  // ── Supabase embedded-response helpers ────

  /// Safely extract a single Map from a Supabase embedded value that may be
  /// a Map (single row), a List (one-to-many or ambiguous FK), or null.
  /// Returns the first item if it's a list, or null.
  static Map<String, dynamic>? asMap(dynamic value) {
    if (value == null) return null;
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty) {
      final first = value.first;
      if (first is Map<String, dynamic>) return first;
      if (first is Map) return Map<String, dynamic>.from(first);
    }
    return null;
  }

  /// Safely extract a String field from an embedded Supabase value.
  /// Handles Map, List-of-Maps, and null.
  static String? embeddedString(dynamic value, String key) {
    final map = asMap(value);
    return map?[key] as String?;
  }

  /// Safely extract a nested field from a Supabase row.
  /// e.g. `nestedField(row, 'product_categories', 'name')`
  static String? nestedString(Map<String, dynamic> row, String embedKey, String field) {
    return embeddedString(row[embedKey], field);
  }

  /// Clean shipment number: remove "----" placeholders and "manual" text.
  /// Ensures format is YY/CODE/INVOICE (year first).
  /// Falls back to 'شحنة #$shipmentId' if result is empty.
  static String cleanShipmentNo(String raw, dynamic shipmentId) {
    var no = raw.trim();
    if (no.isEmpty) return 'شحنة #$shipmentId';

    // Remove "manual" text and "----" placeholders
    no = no.replaceAll(RegExp(r'manual', caseSensitive: false), '').replaceAll('----', '').trim();
    // Clean up slashes
    while (no.contains('//')) {
      no = no.replaceAll('//', '/');
    }
    if (no.endsWith('/')) no = no.substring(0, no.length - 1);
    if (no.startsWith('/')) no = no.substring(1);
    if (no.isEmpty) return 'شحنة #$shipmentId';

    // Ensure format is YY/CODE/INVOICE (year first)
    final parts = no.split('/');
    if (parts.length == 3) {
      final lastIs2Digit = RegExp(r'^\d{2}$').hasMatch(parts[2]);
      final firstIs2Digit = RegExp(r'^\d{2}$').hasMatch(parts[0]);
      // If last part is 2-digit year and first is not, rearrange
      if (lastIs2Digit && !firstIs2Digit) {
        no = '${parts[2]}/${parts[0]}/${parts[1]}';
      }
    }

    if (no.isEmpty) return '\u202Aشحنة #$shipmentId\u202C';
    return '\u202A$no\u202C';
  }

  /// Map shipment cost category keys to Arabic labels.
  static String costCategoryLabel(String cat) {
    switch (cat) {
      case 'freight': return 'شحن';
      case 'clearance': return 'تخليص جمركي';
      case 'manual_crop': return 'محاصيل';
      case 'manual_packing': return 'تعبئة وتغليف';
      case 'packing': case 'PACKAGING': return 'تعبئة وتغليف';
      case 'logistics': case 'TRANSPORT': return 'لوجستيك ونقل';
      case 'admin': return 'مصاريف إدارية';
      case 'export_cost': return 'تكاليف تصدير';
      case 'fruit': return 'تكلفة الفاكهة';
      case 'packing_material': return 'مواد تعبئة';
      case 'LABOR': return 'عمالة';
      case 'DIESEL': return 'ديزل';
      case 'AGRICULTURE': return 'أجرة زراعية';
      case 'COOLING': return 'تبريد';
      case 'LABELS': return 'ليبل';
      case 'STICKERS': return 'استيكر';
      case 'OTHER': case 'other': return 'أخرى';
      case 'crop': return 'محاصيل';
      default: return cat;
    }
  }
}