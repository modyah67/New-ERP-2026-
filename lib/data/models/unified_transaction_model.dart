import '../models/treasury_model.dart';

class UnifiedTransactionModel {
  final String id;
  final String? journalEntryId;
  final String entryNumber;
  final String accountCategory; // 'treasury' or 'bank'
  final String accountSourceId;
  final String accountSourceName;
  final String transactionType;
  final String currency;
  final double amount;
  final double balanceBefore;
  final double balanceAfter;
  final String description;
  final String? notes;
  final String? categoryName;
  final String? referenceNumber;
  final String? createdBy;
  final String? creatorName;
  final String createdAt;
  final String? relatedPartyName;
  final String? relatedPartyType; // 'supplier', 'customer', 'treasury', 'bank'

  const UnifiedTransactionModel({
    required this.id,
    this.journalEntryId,
    required this.entryNumber,
    required this.accountCategory,
    required this.accountSourceId,
    required this.accountSourceName,
    required this.transactionType,
    required this.currency,
    required this.amount,
    required this.balanceBefore,
    required this.balanceAfter,
    required this.description,
    this.notes,
    this.categoryName,
    this.referenceNumber,
    this.createdBy,
    this.creatorName,
    required this.createdAt,
    this.relatedPartyName,
    this.relatedPartyType,
  });

  bool get isIncoming =>
      transactionType == 'disbursement' ||
      transactionType == 'transfer_in' ||
      transactionType == 'return_in' ||
      transactionType == 'currency_exchange_in' ||
      transactionType == 'deposit';

  bool get isOutgoing => !isIncoming;

  String get typeLabel {
    switch (transactionType) {
      case 'disbursement':
      case 'disbursement_out':
        return 'صرف عهدة';
      case 'transfer_in':
        return 'تحويل وارد';
      case 'transfer_out':
        return 'تحويل صادر';
      case 'expense':
        return 'مصروف';
      case 'supplier_payment':
        return 'دفعة للمورد';
      case 'deposit':
        return 'إيداع';
      case 'withdrawal':
      case 'withdrawa':
        return 'سحب';
      case 'currency_exchange_in':
      case 'currency_exchange_out':
        return 'تحويل عملة';
      case 'return_in':
        return 'مرتجع وارد';
      case 'return_out':
        return 'مرتجع صادر';
      case 'payment':
        return 'سند قبض';
      case 'receipt':
        return 'سند قبض';
      case 'purchase':
        return 'شراء';
      case 'sale':
        return 'بيع';
      case 'cheque':
        return 'شيك';
      case 'receive':
        return 'قبض';
      case 'income':
        return 'إيراد';
      case 'opening_balance':
        return 'رصيد افتتاحي';
      default:
        return transactionType;
    }
  }

  factory UnifiedTransactionModel.fromTreasuryTx(TreasuryTransactionModel tx) {
    String? partyName;
    String? partyType;
    if (tx.supplierName != null && tx.supplierName!.isNotEmpty) {
      partyName = tx.supplierName;
      partyType = 'supplier';
    } else if (tx.customerName != null && tx.customerName!.isNotEmpty) {
      partyName = tx.customerName;
      partyType = 'customer';
    } else if (tx.relatedTreasuryName != null && tx.relatedTreasuryName!.isNotEmpty) {
      partyName = tx.relatedTreasuryName;
      partyType = tx.transactionType.contains('transfer') ? 'treasury' : null;
    }

    return UnifiedTransactionModel(
      id: tx.id ?? '0',
      journalEntryId: tx.journalEntryId,
      entryNumber: tx.entryNumber ?? (tx.journalEntryId != null ? '#${tx.journalEntryId}' : ''),
      accountCategory: 'treasury',
      accountSourceId: tx.treasuryId ?? '',
      accountSourceName: tx.treasuryName,
      transactionType: tx.transactionType,
      currency: tx.currency,
      amount: tx.amount,
      balanceBefore: tx.balanceBefore,
      balanceAfter: tx.balanceAfter,
      description: tx.description ?? '',
      notes: tx.notes,
      categoryName: tx.categoryName,
      createdBy: tx.createdBy,
      creatorName: tx.creatorName,
      createdAt: tx.createdAt,
      relatedPartyName: partyName,
      relatedPartyType: partyType,
    );
  }

  factory UnifiedTransactionModel.fromMap(Map<String, dynamic> map) {
    num numVal(dynamic v) => v is num ? v : (num.tryParse('$v') ?? 0);
    String str(dynamic v) => v?.toString() ?? '';

    return UnifiedTransactionModel(
      id: str(map['tx_id'].isNotEmpty ? map['tx_id'] : map['id']),
      journalEntryId: map['journal_entry_id']?.toString(),
      entryNumber: str(map['entry_number']).isNotEmpty
          ? str(map['entry_number'])
          : (map['journal_entry_id'] != null ? '#${map['journal_entry_id']}' : ''),
      accountCategory: str(map['account_category']).isNotEmpty ? str(map['account_category']) : 'treasury',
      accountSourceId: str(map['account_source_id']),
      accountSourceName: str(map['account_source_name']),
      transactionType: str(map['transaction_type'].isNotEmpty ? map['transaction_type'] : map['type']),
      currency: str(map['currency']),
      amount: numVal(map['amount']).toDouble(),
      balanceBefore: numVal(map['balance_before']).toDouble(),
      balanceAfter: numVal(map['balance_after']).toDouble(),
      description: str(map['description']),
      notes: str(map['notes']).isNotEmpty ? str(map['notes']) : null,
      categoryName: map['category_name']?.toString(),
      referenceNumber: map['reference_number']?.toString(),
      createdBy: map['created_by']?.toString(),
      creatorName: map['creator_name']?.toString(),
      createdAt: str(map['created_at']),
      relatedPartyName: map['related_party_name']?.toString(),
      relatedPartyType: map['related_party_type']?.toString(),
    );
  }
}
