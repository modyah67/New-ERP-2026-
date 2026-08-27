// lib/data/models/cashbox_model.dart

class CashboxModel {
  final int? id;
  final String transactionDate;
  final String type;         // debit (money in) / credit (money out)
  final double amount;
  final double balanceAfter; // running balance after this entry
  final String description;
  final int? relatedTransactionId;
  final String createdAt;

  CashboxModel({
    this.id,
    required this.transactionDate,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    required this.description,
    this.relatedTransactionId,
    required this.createdAt,
  });

  factory CashboxModel.fromMap(Map<String, dynamic> map) {
    return CashboxModel(
      id: map['id'] as int?,
      transactionDate: map['transaction_date'] as String,
      type: map['type'] as String,
      amount: (map['amount'] as num).toDouble(),
      balanceAfter: (map['balance_after'] as num).toDouble(),
      description: map['description'] as String,
      relatedTransactionId: map['related_transaction_id'] as int?,
      createdAt: map['created_at'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'transaction_date': transactionDate,
      'type': type,
      'amount': amount,
      'balance_after': balanceAfter,
      'description': description,
      'related_transaction_id': relatedTransactionId,
      'created_at': createdAt,
    };
  }

  CashboxModel copyWith({
    int? id, String? transactionDate, String? type,
    double? amount, double? balanceAfter,
    String? description, int? relatedTransactionId, String? createdAt,
  }) {
    return CashboxModel(
      id: id ?? this.id,
      transactionDate: transactionDate ?? this.transactionDate,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      balanceAfter: balanceAfter ?? this.balanceAfter,
      description: description ?? this.description,
      relatedTransactionId: relatedTransactionId ?? this.relatedTransactionId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}