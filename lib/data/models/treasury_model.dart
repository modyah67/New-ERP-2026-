class TreasuryModel {
  final String? id;
  final String type;
  final String? userId;
  final String? userName;
  final String name;
  final String? notes;
  final String createdAt;
  final List<TreasuryBalanceModel> balances;

  const TreasuryModel({
    this.id,
    required this.type,
    this.userId,
    this.userName,
    required this.name,
    this.notes,
    required this.createdAt,
    this.balances = const [],
  });

  bool get isMain => type == 'main';
  bool get isEmployee => type == 'employee';

  String get displayName => isMain ? name : '$name${userName != null ? ' - $userName' : ''}';

  TreasuryBalanceModel? getBalance(String currency) {
    try {
      return balances.firstWhere((b) => b.currency == currency);
    } catch (_) {
      return null;
    }
  }

  factory TreasuryModel.fromMap(Map<String, dynamic> map) {
    String str(dynamic v) => v?.toString() ?? '';
    int? intVal(dynamic v) => v is int ? v : int.tryParse('$v');

    List<TreasuryBalanceModel> balanceList = [];
    final balRaw = map['balances'];
    if (balRaw is List) {
      balanceList = balRaw
          .map((b) => TreasuryBalanceModel.fromMap(
              Map<String, dynamic>.from(b as Map)))
          .toList();
    }

    Map<String, dynamic>? userMap;
    if (map['users'] is Map) {
      userMap = Map<String, dynamic>.from(map['users'] as Map);
    }

    return TreasuryModel(
      id: map['id']?.toString(),
      type: str(map['type']),
      userId: map['user_id']?.toString(),
      userName: userMap?['full_name']?.toString() ?? str(map['user_name']),
      name: str(map['name']),
      notes: str(map['notes']),
      createdAt: str(map['created_at']),
      balances: balanceList,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'type': type,
      if (userId != null) 'user_id': userId,
      'name': name,
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
      'created_at': createdAt,
    };
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'type': type,
      if (userId != null) 'user_id': userId,
      'name': name,
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
      'created_at': createdAt,
    };
  }

  TreasuryModel copyWith({
    String? id,
    String? type,
    String? userId,
    String? userName,
    String? name,
    String? notes,
    String? createdAt,
    List<TreasuryBalanceModel>? balances,
  }) {
    return TreasuryModel(
      id: id ?? this.id,
      type: type ?? this.type,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      name: name ?? this.name,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      balances: balances ?? this.balances,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TreasuryModel && id != null && other.id != null && id == other.id;

  @override
  int get hashCode => id?.hashCode ?? 0;
}

// ─── Treasury Balance ────────────────────────────────────────────────

class TreasuryBalanceModel {
  final String? id;
  final String? treasuryId;
  final String currency;
  final double balance;
  final double costBase;
  final double bookRate;
  final String? accountId;

  const TreasuryBalanceModel({
    this.id,
    this.treasuryId,
    required this.currency,
    this.balance = 0.0,
    this.costBase = 0.0,
    this.bookRate = 1.0,
    this.accountId,
  });

  factory TreasuryBalanceModel.fromMap(Map<String, dynamic> map) {
    int? intVal(dynamic v) => v is int ? v : int.tryParse('$v');
    num? numVal(dynamic v) => v is num ? v : num.tryParse('$v');
    String str(dynamic v) => v?.toString() ?? '';

    final cur = str(map['currency']).toUpperCase();
    final bal = numVal(map['balance'])?.toDouble() ?? 0.0;
    final cost = numVal(map['cost_base'])?.toDouble() ?? 0.0;
    double rate = numVal(map['book_rate'])?.toDouble() ?? (cur == 'EGP' ? 1.0 : (cur == 'USD' ? 50.0 : (cur == 'EUR' ? 54.0 : (cur == 'GBP' ? 63.0 : 50.0))));

    if (cur != 'EGP' && bal > 0 && cost > 0) {
      rate = cost / bal;
    }

    return TreasuryBalanceModel(
      id: map['id']?.toString(),
      treasuryId: map['treasury_id']?.toString(),
      currency: cur,
      balance: bal,
      costBase: cost,
      bookRate: rate,
      accountId: map['account_id']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'treasury_id': treasuryId,
      'currency': currency,
      'balance': balance,
      'cost_base': costBase,
      'book_rate': bookRate,
      if (accountId != null) 'account_id': accountId,
    };
  }

  TreasuryBalanceModel copyWith({
    String? id,
    String? treasuryId,
    String? currency,
    double? balance,
    double? costBase,
    double? bookRate,
    String? accountId,
  }) {
    return TreasuryBalanceModel(
      id: id ?? this.id,
      treasuryId: treasuryId ?? this.treasuryId,
      currency: currency ?? this.currency,
      balance: balance ?? this.balance,
      costBase: costBase ?? this.costBase,
      bookRate: bookRate ?? this.bookRate,
      accountId: accountId ?? this.accountId,
    );
  }
}

// ─── Treasury Transaction ────────────────────────────────────────────

class TreasuryTransactionModel {
  final String? id;
  final String? treasuryId;
  final String treasuryName;
  final String transactionType;
  final String currency;
  final double amount;
  final double balanceBefore;
  final double balanceAfter;
  final String? description;
  final String? relatedTreasuryId;
  final String? relatedTreasuryName;
  final String? createdBy;
  final String? creatorName;
  final String createdAt;
  final String? categoryId;
  final String? categoryName;
  final String? categoryColor;
  final String? customerId;
  final String? supplierId;
  final String? supplierName;
  final String? customerName;
  final String? clearingAgentId;
  final String? clearingAgentName;
  final String? shippingCompanyId;
  final String? shippingCompanyName;
  final String? shareholderId;
  final String? shareholderName;
  final String? journalEntryId;
  final String? entryNumber;
  final String? notes;
  final String status;
  final Map<String, dynamic>? payload;

  const TreasuryTransactionModel({
    this.id,
    this.treasuryId,
    this.treasuryName = '',
    required this.transactionType,
    required this.currency,
    this.amount = 0.0,
    this.balanceBefore = 0.0,
    this.balanceAfter = 0.0,
    this.description,
    this.notes,
    this.status = 'confirmed',
    this.payload,
    this.relatedTreasuryId,
    this.relatedTreasuryName,
    this.createdBy,
    this.creatorName,
    required this.createdAt,
    this.categoryId,
    this.categoryName,
    this.categoryColor,
    this.customerId,
    this.supplierId,
    this.supplierName,
    this.customerName,
    this.clearingAgentId,
    this.clearingAgentName,
    this.shippingCompanyId,
    this.shippingCompanyName,
    this.shareholderId,
    this.shareholderName,
    this.journalEntryId,
    this.entryNumber,
  });

  bool get isDraft => status == 'draft';
  bool get isConfirmed => status == 'confirmed';

  bool get isIncoming =>
      transactionType == 'disbursement' ||
      transactionType == 'transfer_in' ||
      transactionType == 'return_in' ||
      transactionType == 'currency_exchange_in' ||
      transactionType == 'deposit';

  bool get isOutgoing =>
      transactionType == 'expense' ||
      transactionType == 'supplier_payment' ||
      transactionType == 'transfer_out' ||
      transactionType == 'return_out' ||
      transactionType == 'currency_exchange_out' ||
      transactionType == 'disbursement_out';

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
      case 'return_in':
        return 'مرتجع وارد';
      case 'return_out':
        return 'مرتجع صادر';
      case 'deposit':
        return 'إيداع';
      case 'withdrawal':
      case 'withdrawa':
        return 'سحب';
      case 'currency_exchange_in':
      case 'currency_exchange_out':
        return 'تحويل عملة';
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

  factory TreasuryTransactionModel.fromMap(Map<String, dynamic> map) {
    String str(dynamic v) => v?.toString() ?? '';
    int? intVal(dynamic v) => v is int ? v : int.tryParse('$v');
    num? numVal(dynamic v) => v is num ? v : num.tryParse('$v');

    Map<String, dynamic>? treasuryMap;
    if (map['treasuries'] is Map) {
      treasuryMap = Map<String, dynamic>.from(map['treasuries'] as Map);
    }
    Map<String, dynamic>? relatedMap;
    if (map['related'] is Map) {
      relatedMap = Map<String, dynamic>.from(map['related'] as Map);
    } else if (map['related_treasury'] is Map) {
      relatedMap = Map<String, dynamic>.from(map['related_treasury'] as Map);
    }
    Map<String, dynamic>? userMap;
    if (map['created_by_user'] is Map) {
      userMap = Map<String, dynamic>.from(map['created_by_user'] as Map);
    }
    Map<String, dynamic>? categoryMap;
    if (map['expense_categories'] is Map) {
      categoryMap = Map<String, dynamic>.from(map['expense_categories'] as Map);
    }
    Map<String, dynamic>? supplierMap;
    if (map['suppliers'] is Map) {
      supplierMap = Map<String, dynamic>.from(map['suppliers'] as Map);
    }
    Map<String, dynamic>? customerMap;
    if (map['customers'] is Map) {
      customerMap = Map<String, dynamic>.from(map['customers'] as Map);
    }
    Map<String, dynamic>? clearingAgentMap;
    if (map['clearing_agents'] is Map) {
      clearingAgentMap = Map<String, dynamic>.from(map['clearing_agents'] as Map);
    }
    Map<String, dynamic>? shippingCompanyMap;
    if (map['shipping_companies'] is Map) {
      shippingCompanyMap = Map<String, dynamic>.from(map['shipping_companies'] as Map);
    }
    Map<String, dynamic>? shareholderMap;
    if (map['shareholders'] is Map) {
      shareholderMap = Map<String, dynamic>.from(map['shareholders'] as Map);
    }

    return TreasuryTransactionModel(
      id: map['id']?.toString(),
      treasuryId: map['treasury_id']?.toString(),
      treasuryName: treasuryMap?['name']?.toString() ?? str(map['treasury_name']),
      transactionType: str(map['transaction_type']).isNotEmpty
          ? str(map['transaction_type'])
          : str(map['type']),
      currency: str(map['currency']),
      amount: numVal(map['amount'])?.toDouble() ?? 0.0,
      balanceBefore: numVal(map['balance_before'])?.toDouble() ?? 0.0,
      balanceAfter: numVal(map['balance_after'])?.toDouble() ?? 0.0,
      description: str(map['description']),
      notes: str(map['notes']).isNotEmpty ? str(map['notes']) : null,
      relatedTreasuryId: map['related_treasury_id']?.toString(),
      relatedTreasuryName: relatedMap?['name']?.toString(),
      createdBy: map['created_by']?.toString(),
      creatorName: userMap?['full_name']?.toString(),
      createdAt: str(map['created_at']),
      categoryId: map['category_id']?.toString(),
      categoryName: categoryMap?['name']?.toString(),
      categoryColor: categoryMap?['color']?.toString(),
      customerId: map['customer_id']?.toString(),
      supplierId: map['supplier_id']?.toString(),
      supplierName: supplierMap?['name']?.toString(),
      customerName: customerMap?['name']?.toString(),
      clearingAgentId: map['clearing_agent_id']?.toString(),
      clearingAgentName: clearingAgentMap?['name']?.toString(),
      shippingCompanyId: map['shipping_company_id']?.toString(),
      shippingCompanyName: shippingCompanyMap?['name']?.toString(),
      shareholderId: map['shareholder_id']?.toString(),
      shareholderName: shareholderMap?['name']?.toString(),
      journalEntryId: map['journal_entry_id']?.toString(),
      status: str(map['status']).isNotEmpty ? str(map['status']) : 'confirmed',
      payload: map['payload'] is Map ? Map<String, dynamic>.from(map['payload'] as Map) : null,
      entryNumber: str(map['entry_number']).isNotEmpty 
          ? str(map['entry_number']) 
          : (map['journal_entries'] is Map ? str(map['journal_entries']['entry_number']) : null),
    );
  }
}
