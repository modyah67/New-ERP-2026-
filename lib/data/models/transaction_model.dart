// lib/data/models/transaction_model.dart

class TransactionModel {
  final String? id;
  final String? journalEntryId;
  final String? entryNumber;
  final String transactionDate;
  final String type;          // debit / credit
  final double amount;
  final String? accountId;
  final String? accountName;  // joined
  final String? accountCode;  // joined
  final String? customerId;
  final String? customerName; // joined
  final String? customerCode; // joined
  final String? supplierId;
  final String? supplierName; // joined
  final String? supplierCode; // joined
  final String? invoiceId;
  final String? purchaseId;
  final String description;
  final String createdAt;
  final String? currency;
  final double? amountInBaseCurrency;

  TransactionModel({
    this.id,
    this.journalEntryId,
    this.entryNumber,
    required this.transactionDate,
    required this.type,
    required this.amount,
    this.accountId,
    this.accountName,
    this.accountCode,
    this.customerId,
    this.customerName,
    this.customerCode,
    this.supplierId,
    this.supplierName,
    this.supplierCode,
    this.invoiceId,
    this.purchaseId,
    required this.description,
    required this.createdAt,
    this.currency,
    this.amountInBaseCurrency,
  });

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id']?.toString(),
      journalEntryId: (map['journal_entry_id'] ?? map['entry_id'])?.toString(),
      entryNumber: map['entry_number']?.toString(),
      transactionDate: map['transaction_date']?.toString() ?? '',
      type: map['type']?.toString() ?? 'debit',
      amount: double.tryParse(map['amount']?.toString() ?? '') ?? 0.0,
      accountId: map['account_id']?.toString(),
      accountName: map['account_name'] as String?,
      accountCode: map['account_code'] as String?,
      customerId: map['customer_id']?.toString(),
      customerName: map['customer_name'] as String?,
      customerCode: map['customer_code'] as String?,
      supplierId: map['supplier_id']?.toString(),
      supplierName: map['supplier_name'] as String?,
      supplierCode: map['supplier_code'] as String?,
      invoiceId: map['invoice_id']?.toString(),
      purchaseId: map['purchase_id']?.toString(),
      description: map['description']?.toString() ?? '',
      createdAt: map['created_at']?.toString() ?? '',
      currency: map['currency']?.toString() ?? 'EGP',
      amountInBaseCurrency: double.tryParse(map['amount_in_base_currency']?.toString() ?? '') ??
          double.tryParse(map['base_amount']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (entryNumber != null) 'entry_number': entryNumber,
      'transaction_date': transactionDate,
      'type': type,
      'amount': amount,
      'account_id': accountId,
      'customer_id': customerId,
      'supplier_id': supplierId,
      'invoice_id': invoiceId,
      'purchase_id': purchaseId,
      'description': description,
      'created_at': createdAt,
      'currency': currency,
      if (amountInBaseCurrency != null) 'amount_in_base_currency': amountInBaseCurrency,
    };
  }

  TransactionModel copyWith({
    String? id, String? entryNumber, String? transactionDate, String? type,
    double? amount, String? accountId, String? accountName, String? accountCode,
    String? customerId, String? customerName, String? customerCode,
    String? supplierId, String? supplierName, String? supplierCode,
    String? invoiceId, String? purchaseId, String? description, String? createdAt,
    String? currency, double? amountInBaseCurrency,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      entryNumber: entryNumber ?? this.entryNumber,
      transactionDate: transactionDate ?? this.transactionDate,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      accountId: accountId ?? this.accountId,
      accountName: accountName ?? this.accountName,
      accountCode: accountCode ?? this.accountCode,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerCode: customerCode ?? this.customerCode,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      supplierCode: supplierCode ?? this.supplierCode,
      invoiceId: invoiceId ?? this.invoiceId,
      purchaseId: purchaseId ?? this.purchaseId,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      currency: currency ?? this.currency,
      amountInBaseCurrency: amountInBaseCurrency ?? this.amountInBaseCurrency,
    );
  }
}