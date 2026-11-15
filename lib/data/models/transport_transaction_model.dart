class TransportTransactionModel {
  final int? id;
  final int supplierId;
  final String type;
  final double amount;
  final String currency;
  final String? referenceId;
  final String? description;
  final String? routeFrom;
  final String? routeTo;
  final double truckCount;
  final String? notes;
  final int? journalEntryId;
  final String date;
  final String createdAt;
  final String? createdBy;

  const TransportTransactionModel({
    this.id,
    required this.supplierId,
    required this.type,
    required this.amount,
    this.currency = 'EGP',
    this.referenceId,
    this.description,
    this.routeFrom,
    this.routeTo,
    this.truckCount = 1.0,
    this.notes,
    this.journalEntryId,
    required this.date,
    required this.createdAt,
    this.createdBy,
  });

  bool get isInvoice =>
      type == 'invoice' ||
      type == 'packing_cost' ||
      (type == 'packing_order_invoice' && amount > 0);
  bool get isPayment => type == 'cash_payment' || type == 'bank_payment';
  bool get isConsumption =>
      type == 'packing_consumption' ||
      type == 'packing_order_consumption' ||
      (type == 'packing_order_invoice' && amount == 0);
  bool get isCashPayment => type == 'cash_payment';
  bool get isBankPayment => type == 'bank_payment';
  bool get isOpeningBalance => type == 'opening_balance';

  /// In Transporter Liability Ledger:
  /// Credit (دائن / له): Invoices & packing order cost entitlements (Freight owed to transporter)
  /// Debit (مدين / عليه / مسدد له): Cash/Bank Payments made to transporter
  /// Note: Packing consumptions without cost are purely operational movements (debit=0, credit=0)
  double get debit => isPayment ? amount : 0.0;
  double get credit => (isInvoice || isOpeningBalance) ? amount : 0.0;

  String get typeLabel {
    switch (type) {
      case 'invoice':
        return 'فاتورة / استحقاق نقل';
      case 'packing_order_invoice':
        return amount > 0 ? 'استحقاق نقل أمر تعبئة' : 'استهلاك نقلات (أمر تعبئة)';
      case 'packing_cost':
        return 'استحقاق نقل أمر تعبئة';
      case 'packing_consumption':
      case 'packing_order_consumption':
        return 'استهلاك نقلات (أمر تعبئة)';
      case 'cash_payment':
        return 'سند صرف نقدي (خزينة)';
      case 'bank_payment':
        return 'سند صرف بنكي (CIB)';
      case 'opening_balance':
        return 'رصيد افتتاحي';
      case 'manual_adjustment':
        return 'تسوية حساب';
      default:
        return type;
    }
  }

  String? get routeDisplay {
    final from = routeFrom?.trim();
    final to = routeTo?.trim();
    if ((from != null && from.isNotEmpty) || (to != null && to.isNotEmpty)) {
      return '${from?.isNotEmpty == true ? from : '—'} ➔ ${to?.isNotEmpty == true ? to : '—'}';
    }
    return null;
  }

  factory TransportTransactionModel.fromMap(Map<String, dynamic> map) {
    String? str(dynamic v) => v?.toString();
    int? intVal(dynamic v) => v is int ? v : int.tryParse('$v');
    num? numVal(dynamic v) => v is num ? v : num.tryParse('$v');

    return TransportTransactionModel(
      id: intVal(map['id']),
      supplierId: intVal(map['supplier_id']) ?? 0,
      type: str(map['type']) ?? '',
      amount: numVal(map['amount'])?.toDouble() ?? 0.0,
      currency: str(map['currency']) ?? 'EGP',
      referenceId: str(map['reference_id']),
      description: str(map['description']),
      routeFrom: str(map['route_from']),
      routeTo: str(map['route_to']),
      truckCount: numVal(map['truck_count'])?.toDouble() ?? 1.0,
      notes: str(map['notes']),
      journalEntryId: intVal(map['journal_entry_id']),
      date: str(map['date']) ?? '',
      createdAt: str(map['created_at']) ?? '',
      createdBy: str(map['created_by']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'supplier_id': supplierId,
      'type': type,
      'amount': amount,
      'currency': currency,
      'reference_id': referenceId,
      'description': description,
      if (routeFrom != null) 'route_from': routeFrom,
      if (routeTo != null) 'route_to': routeTo,
      'truck_count': truckCount,
      if (notes != null) 'notes': notes,
      if (journalEntryId != null) 'journal_entry_id': journalEntryId,
      'date': date,
      'created_at': createdAt,
      if (createdBy != null) 'created_by': createdBy,
    };
  }

  TransportTransactionModel copyWith({
    int? id,
    int? supplierId,
    String? type,
    double? amount,
    String? currency,
    String? referenceId,
    String? description,
    String? routeFrom,
    String? routeTo,
    double? truckCount,
    String? notes,
    int? journalEntryId,
    String? date,
    String? createdAt,
    String? createdBy,
  }) {
    return TransportTransactionModel(
      id: id ?? this.id,
      supplierId: supplierId ?? this.supplierId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      referenceId: referenceId ?? this.referenceId,
      description: description ?? this.description,
      routeFrom: routeFrom ?? this.routeFrom,
      routeTo: routeTo ?? this.routeTo,
      truckCount: truckCount ?? this.truckCount,
      notes: notes ?? this.notes,
      journalEntryId: journalEntryId ?? this.journalEntryId,
      date: date ?? this.date,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }
}
