// lib/data/models/statement_row_model.dart
// ─────────────────────────────────────────────
// One row in the statement table (expanded per item).
// Extracted from statement_controller.dart so it can be
// shared across all statement features without importing
// the old GetX controller.
// ─────────────────────────────────────────────

class StatementRow {
  final String transactionNumber;
  final String date;
  final String accountName;
  final String description;
  final double piecesCount;
  final double quantity;
  final double unitPrice;
  final double debit;
  final double credit;
  final double balance;
  final String type;
  final String createdAt;
  
  // Newly added fields for Unified Ledger Engine mapping
  final String? id;
  final String? referenceType;
  final String? referenceId;
  final String? currency;
  final String? accountCode;

  // Multi-Currency & Foreign Currency fields
  final double? foreignDebit;
  final double? foreignCredit;
  final String? foreignCurrency;
  final double? exchangeRate;

  const StatementRow({
    required this.transactionNumber,
    required this.date,
    required this.accountName,
    required this.description,
    required this.piecesCount,
    required this.quantity,
    required this.unitPrice,
    required this.debit,
    required this.credit,
    required this.balance,
    required this.type,
    required this.createdAt,
    this.id,
    this.referenceType,
    this.referenceId,
    this.currency,
    this.accountCode,
    this.foreignDebit,
    this.foreignCredit,
    this.foreignCurrency,
    this.exchangeRate,
  });

  /// Whether this row has an original foreign currency (USD, EUR, etc.)
  bool get isForeignCurrency {
    final cur = (foreignCurrency ?? currency ?? '').trim().toUpperCase();
    if (cur.isEmpty || cur == 'EGP' || cur == 'ج.م' || cur == 'ALL' || cur == 'MULTI') {
      return false;
    }
    return foreignAmount > 0 || (exchangeRate != null && exchangeRate! > 1.0);
  }

  /// The original amount in foreign currency
  double get foreignAmount {
    if (foreignDebit != null && foreignDebit! > 0) return foreignDebit!;
    if (foreignCredit != null && foreignCredit! > 0) return foreignCredit!;
    return 0.0;
  }

  /// Clean display string for the foreign currency column on screen
  String get foreignDisplay {
    if (!isForeignCurrency) return '—';
    final cur = (foreignCurrency ?? currency ?? '').trim().toUpperCase();
    final amtStr = _formatFixed(foreignAmount);
    if (exchangeRate != null && exchangeRate! > 0 && exchangeRate != 1.0) {
      return '$amtStr $cur\n(سعر: ${_formatFixed(exchangeRate!)})';
    }
    return '$amtStr $cur';
  }

  /// Compact single-line foreign display for export / PDF / Excel
  String get foreignDisplayCompact {
    if (!isForeignCurrency) return '-';
    final cur = (foreignCurrency ?? currency ?? '').trim().toUpperCase();
    final amtStr = _formatFixed(foreignAmount);
    if (exchangeRate != null && exchangeRate! > 0 && exchangeRate != 1.0) {
      return '$amtStr $cur @ ${_formatFixed(exchangeRate!)}';
    }
    return '$amtStr $cur';
  }

  static String _formatFixed(double v) {
    if (v == v.roundToDouble()) {
      return v.toStringAsFixed(0);
    }
    return v.toStringAsFixed(2);
  }

  StatementRow copyWith({
    String? transactionNumber,
    String? date,
    String? accountName,
    String? description,
    double? piecesCount,
    double? quantity,
    double? unitPrice,
    double? debit,
    double? credit,
    double? balance,
    String? type,
    String? createdAt,
    String? id,
    String? referenceType,
    String? referenceId,
    String? currency,
    String? accountCode,
    double? foreignDebit,
    double? foreignCredit,
    String? foreignCurrency,
    double? exchangeRate,
  }) {
    return StatementRow(
      transactionNumber: transactionNumber ?? this.transactionNumber,
      date: date ?? this.date,
      accountName: accountName ?? this.accountName,
      description: description ?? this.description,
      piecesCount: piecesCount ?? this.piecesCount,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      debit: debit ?? this.debit,
      credit: credit ?? this.credit,
      balance: balance ?? this.balance,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      id: id ?? this.id,
      referenceType: referenceType ?? this.referenceType,
      referenceId: referenceId ?? this.referenceId,
      currency: currency ?? this.currency,
      accountCode: accountCode ?? this.accountCode,
      foreignDebit: foreignDebit ?? this.foreignDebit,
      foreignCredit: foreignCredit ?? this.foreignCredit,
      foreignCurrency: foreignCurrency ?? this.foreignCurrency,
      exchangeRate: exchangeRate ?? this.exchangeRate,
    );
  }
}
