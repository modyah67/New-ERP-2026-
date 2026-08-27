class UnpaidLiabilityModel {
  final String liabilityType;
  final int liabilityId;
  final String referenceNumber;
  final String entityType;
  final String entityId;
  final String currency;
  final double? currencySnapshot;
  final double dueAmount;
  final DateTime liabilityDate;

  UnpaidLiabilityModel({
    required this.liabilityType,
    required this.liabilityId,
    required this.referenceNumber,
    required this.entityType,
    required this.entityId,
    required this.currency,
    this.currencySnapshot,
    required this.dueAmount,
    required this.liabilityDate,
  });

  factory UnpaidLiabilityModel.fromJson(Map<String, dynamic> json) {
    return UnpaidLiabilityModel(
      liabilityType: json['liability_type'],
      liabilityId: json['liability_id'] is int 
          ? json['liability_id'] 
          : int.tryParse(json['liability_id'].toString()) ?? 0,
      referenceNumber: json['reference_number'] ?? '',
      entityType: json['entity_type'],
      entityId: json['entity_id'].toString(),
      currency: json['currency'],
      currencySnapshot: json['currency_snapshot'] != null 
          ? (json['currency_snapshot'] is Map
              ? ((json['currency_snapshot'] as Map)['exchange_rate'] as num?)?.toDouble()
              : double.tryParse(json['currency_snapshot'].toString()))
          : null,
      dueAmount: double.tryParse(json['due_amount'].toString()) ?? 0.0,
      liabilityDate: json['liability_date'] is DateTime
          ? (json['liability_date'] as DateTime)
          : (DateTime.tryParse(json['liability_date']?.toString() ?? '') ?? DateTime.now()),
    );
  }
}
