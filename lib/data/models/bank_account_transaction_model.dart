class BankAccountTransactionModel {
  final int id;
  final int bankAccountId;
  final String type;
  final double amount;
  final double balanceBefore;
  final double balanceAfter;
  final String? description;
  final String? createdBy;
  final String? createdByName;
  final DateTime createdAt;
  final String? journalEntryId;
  final String? referenceNumber;
  final String? relatedPartyName;
  final String? relatedPartyType;
  final String? relatedPartyId;
  final String status;
  final Map<String, dynamic> payload;
  final String? notes;

  bool get isDeposit => type == 'deposit' || type == 'currency_exchange_in';
  bool get isDraft => status == 'draft';

  BankAccountTransactionModel({
    required this.id,
    required this.bankAccountId,
    required this.type,
    required this.amount,
    required this.balanceBefore,
    required this.balanceAfter,
    this.description,
    this.createdBy,
    this.createdByName,
    required this.createdAt,
    this.journalEntryId,
    this.referenceNumber,
    this.relatedPartyName,
    this.relatedPartyType,
    this.relatedPartyId,
    this.status = 'confirmed',
    this.payload = const {},
    this.notes,
  });

  factory BankAccountTransactionModel.fromMap(Map<String, dynamic> map) {
    final entityType = map['entity_type']?.toString();
    final entityId = map['entity_id']?.toString();
    final counterpartyName = map['counterparty_name']?.toString();

    final displayType = entityType ?? map['related_party_type']?.toString();
    final displayId = entityId ?? map['related_party_id']?.toString();
    final displayName = counterpartyName ?? map['related_party_name']?.toString();

    return BankAccountTransactionModel(
      id: map['id'] is int ? map['id'] : int.tryParse('${map['id']}') ?? 0,
      bankAccountId: map['bank_account_id'] is int
          ? map['bank_account_id']
          : int.tryParse('${map['bank_account_id']}') ?? 0,
      type: map['type'] ?? '',
      amount: (map['amount'] is num) ? map['amount'].toDouble() : 0.0,
      balanceBefore:
          (map['balance_before'] is num) ? map['balance_before'].toDouble() : 0.0,
      balanceAfter:
          (map['balance_after'] is num) ? map['balance_after'].toDouble() : 0.0,
      description: map['description'],
      createdBy: map['created_by'],
      createdByName: map['created_by_user'] != null
          ? (map['created_by_user']['full_name'] ?? '')
          : null,
      createdAt: map['created_at'] != null
          ? (DateTime.tryParse(map['created_at']) ?? DateTime.now()).toLocal()
          : DateTime.now(),
      journalEntryId: map['journal_entry_id']?.toString(),
      referenceNumber: map['reference_number']?.toString(),
      relatedPartyName: (displayName != null && displayName.isNotEmpty) ? displayName : null,
      relatedPartyType: displayType,
      relatedPartyId: displayId,
      status: map['status']?.toString() ?? 'confirmed',
      payload: map['payload'] is Map ? Map<String, dynamic>.from(map['payload']) : {},
      notes: map['notes']?.toString(),
    );
  }
}
