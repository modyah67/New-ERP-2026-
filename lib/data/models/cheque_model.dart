class ChequeModel {
  final String? id;
  final String chequeNumber;
  final String type;
  final String status;
  final double amount;
  final String currency;
  final String issueDate;
  final String dueDate;
  final String? counterpartyType;
  final String? counterpartyId;
  final String? supplierId;
  final String? shareholderId;
  final String? counterpartyName;
  final String? notes;
  final String? receiptType;
  final String? createdBy;
  final String? clearedAt;
  final String? cancelledAt;
  final int? categoryId;
  final String createdAt;
  final String? journalEntryId;
  final int? expenseAccountId;
  final int? treasuryId;

  const ChequeModel({
    this.id,
    required this.chequeNumber,
    required this.type,
    this.status = 'pending',
    required this.amount,
    required this.currency,
    required this.issueDate,
    required this.dueDate,
    this.counterpartyType,
    this.counterpartyId,
    this.supplierId,
    this.shareholderId,
    this.counterpartyName,
    this.notes,
    this.receiptType,
    this.createdBy,
    this.clearedAt,
    this.cancelledAt,
    this.categoryId,
    this.createdAt = '',
    this.journalEntryId,
    this.expenseAccountId,
    this.treasuryId,
  });

  bool get isOutgoing => type == 'outgoing';
  bool get isIncoming => type == 'incoming';
  bool get isPending => status == 'pending';
  bool get isCleared => status == 'cleared';
  bool get isCancelled => status == 'cancelled';

  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'معلق';
      case 'cleared':
        return 'تم الصرف';
      case 'cancelled':
        return 'ملغي';
      default:
        return 'غير محدد';
    }
  }

  String get typeLabel => isOutgoing ? 'صادر' : 'وارد';

  String get counterpartyDisplay => counterpartyName ?? '—';

  factory ChequeModel.fromMap(Map<String, dynamic> map) {
    String str(dynamic v) => v?.toString() ?? '';
    double? doubleVal(dynamic v) => (v is num ? v : num.tryParse('$v'))?.toDouble();

    Map<String, dynamic>? counterpartyMap;
    if (map['customers'] is Map) {
      counterpartyMap = Map<String, dynamic>.from(map['customers'] as Map);
    } else if (map['suppliers'] is Map) {
      counterpartyMap = Map<String, dynamic>.from(map['suppliers'] as Map);
    } else if (map['shareholders'] is Map) {
      counterpartyMap = Map<String, dynamic>.from(map['shareholders'] as Map);
    } else if (map['clearing_agents'] is Map) {
      counterpartyMap = Map<String, dynamic>.from(map['clearing_agents'] as Map);
    } else if (map['shipping_companies'] is Map) {
      counterpartyMap = Map<String, dynamic>.from(map['shipping_companies'] as Map);
    }

    return ChequeModel(
      id: map['id']?.toString(),
      chequeNumber: str(map['cheque_number']),
      type: str(map['type']),
      status: str(map['status']),
      amount: doubleVal(map['amount']) ?? 0.0,
      currency: str(map['currency']),
      issueDate: str(map['issue_date']),
      dueDate: str(map['due_date']),
      counterpartyType: map['counterparty_type']?.toString(),
      counterpartyId: map['counterparty_id']?.toString(),
      supplierId: str(map['supplier_id']),
      shareholderId: str(map['shareholder_id']),
      counterpartyName: counterpartyMap?['name']?.toString() ?? str(map['counterparty_name']),
      notes: map['notes']?.toString(),
      receiptType: map['receipt_type']?.toString(),
      createdBy: map['created_by']?.toString(),
      clearedAt: map['cleared_at']?.toString(),
      cancelledAt: map['cancelled_at']?.toString(),
      categoryId: map['category_id'] is int ? map['category_id'] as int : int.tryParse('${map['category_id']}'),
      createdAt: str(map['created_at']),
      journalEntryId: map['journal_entry_id']?.toString(),
      expenseAccountId: map['expense_account_id'] is int ? map['expense_account_id'] as int : int.tryParse('${map['expense_account_id']}'),
      treasuryId: map['treasury_id'] is int ? map['treasury_id'] as int : int.tryParse('${map['treasury_id']}'),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'cheque_number': chequeNumber,
      'type': type,
      'status': status,
      'amount': amount,
      'currency': currency,
      'issue_date': issueDate,
      'due_date': dueDate,
      if (counterpartyType != null) 'counterparty_type': counterpartyType,
      if (counterpartyId != null) 'counterparty_id': counterpartyId,
      if (supplierId != null && supplierId!.isNotEmpty) 'supplier_id': supplierId,
      if (shareholderId != null && shareholderId!.isNotEmpty) 'shareholder_id': shareholderId,
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
      if (receiptType != null) 'receipt_type': receiptType,
      if (categoryId != null) 'category_id': categoryId,
      if (expenseAccountId != null) 'expense_account_id': expenseAccountId,
      if (treasuryId != null) 'treasury_id': treasuryId,
    };
  }

  ChequeModel copyWith({
    String? id,
    String? chequeNumber,
    String? type,
    String? status,
    double? amount,
    String? currency,
    String? issueDate,
    String? dueDate,
    String? counterpartyType,
    String? counterpartyId,
    String? supplierId,
    String? shareholderId,
    String? counterpartyName,
    String? notes,
    String? receiptType,
    String? createdBy,
    String? clearedAt,
    String? cancelledAt,
    int? categoryId,
    String? createdAt,
    String? journalEntryId,
    int? expenseAccountId,
    int? treasuryId,
  }) {
    return ChequeModel(
      id: id ?? this.id,
      chequeNumber: chequeNumber ?? this.chequeNumber,
      type: type ?? this.type,
      status: status ?? this.status,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      issueDate: issueDate ?? this.issueDate,
      dueDate: dueDate ?? this.dueDate,
      counterpartyType: counterpartyType ?? this.counterpartyType,
      counterpartyId: counterpartyId ?? this.counterpartyId,
      supplierId: supplierId ?? this.supplierId,
      shareholderId: shareholderId ?? this.shareholderId,
      counterpartyName: counterpartyName ?? this.counterpartyName,
      notes: notes ?? this.notes,
      receiptType: receiptType ?? this.receiptType,
      createdBy: createdBy ?? this.createdBy,
      clearedAt: clearedAt ?? this.clearedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      categoryId: categoryId ?? this.categoryId,
      createdAt: createdAt ?? this.createdAt,
      journalEntryId: journalEntryId ?? this.journalEntryId,
      expenseAccountId: expenseAccountId ?? this.expenseAccountId,
      treasuryId: treasuryId ?? this.treasuryId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChequeModel && id != null && other.id != null && id == other.id && status == other.status;

  @override
  int get hashCode => Object.hash(id, status);
}
