import 'dart:convert';

/// Immutable currency snapshot — stored permanently with every financial transaction.
///
/// Once created, this object MUST NEVER be modified.
/// Exchange rate changes do NOT affect existing snapshots.
class CurrencySnapshot {
  final String originalCurrency;
  final String baseCurrency;
  final double originalAmount;
  final double exchangeRate;
  final double baseAmount;
  final DateTime exchangeRateDate;
  final String exchangeRateSource;
  final DateTime createdAt;
  final String? createdBy;

  const CurrencySnapshot({
    required this.originalCurrency,
    required this.baseCurrency,
    required this.originalAmount,
    required this.exchangeRate,
    required this.baseAmount,
    required this.exchangeRateDate,
    required this.exchangeRateSource,
    required this.createdAt,
    this.createdBy,
  });

  /// Create a snapshot from a transaction amount and exchange rate.
  factory CurrencySnapshot.create({
    required String originalCurrency,
    required double originalAmount,
    required double exchangeRate,
    required DateTime rateDate,
    String rateSource = 'system',
    String? createdBy,
  }) {
    final baseAmount = originalCurrency == 'EGP'
        ? originalAmount
        : originalAmount * exchangeRate;
    return CurrencySnapshot(
      originalCurrency: originalCurrency,
      baseCurrency: 'EGP',
      originalAmount: originalAmount,
      exchangeRate: originalCurrency == 'EGP' ? 1.0 : exchangeRate,
      baseAmount: baseAmount,
      exchangeRateDate: rateDate,
      exchangeRateSource: rateSource,
      createdAt: DateTime.now(),
      createdBy: createdBy,
    );
  }

  /// Zero snapshot for placeholder use.
  static CurrencySnapshot get zero => CurrencySnapshot(
        originalCurrency: 'EGP',
        baseCurrency: 'EGP',
        originalAmount: 0,
        exchangeRate: 1.0,
        baseAmount: 0,
        exchangeRateDate: DateTime.fromMillisecondsSinceEpoch(0),
        exchangeRateSource: 'system',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  /// Whether this is a non-EGP transaction.
  bool get isForeignCurrency => originalCurrency != 'EGP';

  /// Whether this snapshot has valid data.
  bool get isValid => originalAmount > 0 && baseAmount >= 0;

  /// Serialize to JSON for database storage.
  Map<String, dynamic> toJson() => {
        'original_currency': originalCurrency,
        'base_currency': baseCurrency,
        'original_amount': originalAmount,
        'exchange_rate': exchangeRate,
        'base_amount': baseAmount,
        'exchange_rate_date': exchangeRateDate.toIso8601String(),
        'exchange_rate_source': exchangeRateSource,
        'created_at': createdAt.toIso8601String(),
        if (createdBy != null) 'created_by': createdBy,
      };

  /// Serialize to JSON string for TEXT column storage.
  String toJsonString() => jsonEncode(toJson());

  /// Deserialize from JSON map.
  factory CurrencySnapshot.fromJson(Map<String, dynamic> json) {
    return CurrencySnapshot(
      originalCurrency: json['original_currency'] as String? ?? 'EGP',
      baseCurrency: json['base_currency'] as String? ?? 'EGP',
      originalAmount: (json['original_amount'] as num?)?.toDouble() ?? 0.0,
      exchangeRate: (json['exchange_rate'] as num?)?.toDouble() ?? 1.0,
      baseAmount: (json['base_amount'] as num?)?.toDouble() ?? 0.0,
      exchangeRateDate: json['exchange_rate_date'] != null
          ? DateTime.parse(json['exchange_rate_date'] as String)
          : DateTime.now(),
      exchangeRateSource: json['exchange_rate_source'] as String? ?? 'system',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      createdBy: json['created_by'] as String?,
    );
  }

  /// Deserialize from JSON string.
  factory CurrencySnapshot.fromJsonString(String jsonString) {
    return CurrencySnapshot.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }

  /// Deserialize from nullable JSON — returns null if null/empty.
  static CurrencySnapshot? fromJsonNullable(dynamic json) {
    if (json == null) return null;
    if (json is String && json.isEmpty) return null;
    if (json is Map) return CurrencySnapshot.fromJson(json.cast<String, dynamic>());
    return null;
  }

  /// Convert a nullable snapshot to nullable JSON string.
  static String? toJsonStringNullable(CurrencySnapshot? snapshot) {
    return snapshot?.toJsonString();
  }

  @override
  String toString() =>
      'CurrencySnapshot($originalAmount $originalCurrency → $baseAmount $baseCurrency @ $exchangeRate)';
}
