/// Context model encapsulating source and destination warehouse details for a transfer entry.
class TransferWarehouseContext {
  final bool isTransfer;
  final String? fromWarehouse;
  final String? toWarehouse;
  final String? productName;
  final double? quantity;

  const TransferWarehouseContext({
    required this.isTransfer,
    this.fromWarehouse,
    this.toWarehouse,
    this.productName,
    this.quantity,
  });

  bool get hasContext => (fromWarehouse != null && fromWarehouse!.isNotEmpty) ||
      (toWarehouse != null && toWarehouse!.isNotEmpty);

  /// Warehouse associated with the receiving leg (Debit / من حـ/)
  String? get receivingWarehouse => toWarehouse;

  /// Warehouse associated with the sending leg (Credit / إلى حـ/)
  String? get sendingWarehouse => fromWarehouse;
}

/// Service providing business logic for generating, resolving, and formatting
/// inventory transfer journal entries with explicit warehouse context and clean multi-currency support.
class WarehouseTransferJournalService {
  WarehouseTransferJournalService._();

  /// Extracts transfer context (source warehouse, destination warehouse, item name, quantity)
  /// from the journal entry and individual line description/notes.
  static TransferWarehouseContext extractTransferContext({
    required Map<String, dynamic> entry,
    dynamic line,
  }) {
    final sourceType = entry['sourceType']?.toString() ??
        entry['source_type']?.toString() ??
        '';
    final entryNotes = entry['notes']?.toString() ??
        entry['description']?.toString() ??
        '';

    String lineDesc = '';
    if (line is Map) {
      lineDesc = line['description']?.toString() ?? '';
    } else if (line != null) {
      try {
        lineDesc = (line as dynamic).description?.toString() ?? '';
      } catch (_) {}
    }

    final combinedText = '$lineDesc $entryNotes';
    final bool isTransfer = sourceType == 'stock_transfer' ||
        sourceType == 'transfer' ||
        combinedText.contains('تحويل مخزني') ||
        combinedText.contains('تحويل من مخزن') ||
        (combinedText.contains('تحويل') &&
            (combinedText.contains('وارد إلى') || combinedText.contains('منصرف من')));

    if (!isTransfer) {
      return const TransferWarehouseContext(isTransfer: false);
    }

    String? fromWh;
    String? toWh;
    String? prodName;
    double? qty;

    // Pattern 1: "إثبات تحويل مخزني وارد إلى [To] من [From]" or "[إلى مخزن To] من [مخزن From]"
    final inRegex = RegExp(
        r'(?:وارد\s+(?:إلى|لـ)\s*(?:\[?مخزن\s*)?|إلى\s+مخزن\s+)([^\]\(\)\-\|]+?)(?:\])?\s+من\s*(?:\[?مخزن\s*)?([^\]\(\)\-\|]+)',
        caseSensitive: false);
    final inMatch = inRegex.firstMatch(combinedText);
    if (inMatch != null) {
      toWh = _cleanWarehouseName(inMatch.group(1));
      fromWh = _cleanWarehouseName(inMatch.group(2));
    }

    // Pattern 2: "إثبات تحويل مخزني منصرف من [From] إلى [To]"
    if (fromWh == null || toWh == null) {
      final outRegex = RegExp(
          r'(?:منصرف\s+من\s*(?:\[?مخزن\s*)?|من\s+مخزن\s+)([^\]\(\)\-\|]+?)(?:\])?\s+(?:إلى|لـ)\s*(?:\[?مخزن\s*)?([^\]\(\)\-\|]+)',
          caseSensitive: false);
      final outMatch = outRegex.firstMatch(combinedText);
      if (outMatch != null) {
        fromWh = _cleanWarehouseName(outMatch.group(1));
        toWh = _cleanWarehouseName(outMatch.group(2));
      }
    }

    // Pattern 3: Standard summary format: "تحويل مخزني من [From] إلى [To]"
    if (fromWh == null || toWh == null) {
      final generalRegex = RegExp(
          r'تحويل\s*(?:مخزني)?\s*من\s*(?:محطة|مخزن)?\s*([^\s]+)\s+(?:إلى|لـ)\s*(?:محطة|مخزن)?\s*([^\s\-]+)',
          caseSensitive: false);
      final genMatch = generalRegex.firstMatch(combinedText);
      if (genMatch != null) {
        fromWh ??= _cleanWarehouseName(genMatch.group(1));
        toWh ??= _cleanWarehouseName(genMatch.group(2));
      }
    }

    // Extract item & quantity if present in parenthesis, e.g. "(مانجو - 1000)" or "صنف: مانجو - كمية: 1000"
    final itemRegex = RegExp(r'\(([^-\)]+?)\s*-\s*([0-9\.,]+)\)');
    final itemMatch = itemRegex.firstMatch(combinedText);
    if (itemMatch != null) {
      prodName = itemMatch.group(1)?.trim();
      qty = double.tryParse(itemMatch.group(2)?.replaceAll(',', '') ?? '');
    }

    return TransferWarehouseContext(
      isTransfer: true,
      fromWarehouse: fromWh,
      toWarehouse: toWh,
      productName: prodName,
      quantity: qty,
    );
  }

  /// Cleans and trims raw warehouse string from surrounding punctuation or keywords
  static String? _cleanWarehouseName(String? raw) {
    if (raw == null) return null;
    var cleaned = raw
        .replaceAll('[', '')
        .replaceAll(']', '')
        .replaceAll('(', '')
        .replaceAll(')', '')
        .replaceAll('مخزن', '')
        .replaceAll('محطة', '')
        .trim();
    if (cleaned.endsWith('-')) cleaned = cleaned.substring(0, cleaned.length - 1).trim();
    return cleaned.isNotEmpty ? cleaned : null;
  }

  /// Generates the explicit, distinct display account name for transfer lines.
  /// Example:
  /// - Debit: "مخزون المحاصيل - مخزن السادات"
  /// - Credit: "مخزون المحاصيل - مخزن تاج"
  static String formatTransferAccountName({
    required String baseAccountName,
    required bool isDebit,
    required TransferWarehouseContext context,
    bool includePrefix = true,
  }) {
    final prefix = includePrefix ? (isDebit ? 'من حـ/ ' : 'إلى حـ/ ') : '';
    final cleanBase = baseAccountName
        .replaceFirst(RegExp(r'^(من|إلى)\s+حـ?/?\s*'), '')
        .trim();

    if (!context.isTransfer || !context.hasContext) {
      return '$prefix$cleanBase';
    }

    final targetWarehouse = isDebit ? context.receivingWarehouse : context.sendingWarehouse;
    if (targetWarehouse == null || targetWarehouse.isEmpty) {
      return '$prefix$cleanBase';
    }

    // If account name already contains the warehouse name, avoid duplicate
    if (cleanBase.contains(targetWarehouse)) {
      return '$prefix$cleanBase';
    }

    // Shorten generic long account names to a clean ERP standard
    String normalizedBase = cleanBase;
    if (normalizedBase == 'مخزون المحاصيل الزراعية') {
      normalizedBase = 'مخزون المحاصيل';
    } else if (normalizedBase == 'مخزون مواد التعبئة والتغليف') {
      normalizedBase = 'مخزون مواد التعبئة';
    }

    return '$prefix$normalizedBase - مخزن $targetWarehouse';
  }

  /// Generates standard balanced double-entry lines for a stock transfer
  /// with explicit warehouse names and multi-currency valuation.
  static List<Map<String, dynamic>> generateTransferJournalLines({
    required int transferId,
    required String fromWarehouse,
    required String toWarehouse,
    required String productName,
    required double quantity,
    required double totalCost,
    required String currency,
    double exchangeRate = 1.0,
    int? fromAccountId,
    int? toAccountId,
    String fromAccountCode = '1231',
    String toAccountCode = '1231',
  }) {
    final double safeRate = exchangeRate > 0 ? exchangeRate : 1.0;
    final double baseAmount = totalCost * safeRate;

    final debitDesc =
        'إثبات تحويل مخزني وارد [إلى مخزن $toWarehouse] من [مخزن $fromWarehouse] ($productName - $quantity)';
    final creditDesc =
        'إثبات تحويل مخزني منصرف [من مخزن $fromWarehouse] إلى [مخزن $toWarehouse] ($productName - $quantity)';

    return [
      // 1. Debit leg: Receiving Warehouse (من حـ/ مخزون المحاصيل - مخزن الوجهة)
      {
        'account_id': toAccountId,
        'account_name': 'مخزون المحاصيل - مخزن $toWarehouse',
        'account_code': toAccountCode,
        'debit': totalCost,
        'credit': 0.0,
        'currency': currency,
        'amount_in_base_currency': baseAmount,
        'description': debitDesc,
        'warehouse_name': toWarehouse,
        'transfer_direction': 'in',
      },
      // 2. Credit leg: Sending Warehouse (إلى حـ/ مخزون المحاصيل - مخزن المصدر)
      {
        'account_id': fromAccountId,
        'account_name': 'مخزون المحاصيل - مخزن $fromWarehouse',
        'account_code': fromAccountCode,
        'debit': 0.0,
        'credit': totalCost,
        'currency': currency,
        'amount_in_base_currency': baseAmount,
        'description': creditDesc,
        'warehouse_name': fromWarehouse,
        'transfer_direction': 'out',
      },
    ];
  }
}
