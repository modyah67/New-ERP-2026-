class ShipmentCostItemModel {
  final int? id;
  final int shipmentId;
  final String category;
  final int? reportCategoryId;
  final String? reportCategoryName;
  final String description;
  final double quantity;
  final double unitPrice;
  final double totalPrice;
  final int sortOrder;
  final DateTime? createdAt;
  final bool isReadOnly;
  final String? vendorType;
  final int? vendorId;
  final double exchangeRate;
  final String? supplierId;
  final String? supplierCurrency;
  // Phase 3: payment source tracking
  final String? paymentSourceType;      // 'treasury' | 'bank' | null
  final int? paymentSourceId;           // treasury_id or bank_account_id
  final int? treasuryTransactionId;     // set after cash payment from treasury
  final int? bankTransactionId;         // set after cash payment from bank
  final int? journalEntryId;            // GL journal entry linked to payment
  final int? revisionNumber;            // edit revision counter (0 = original)
  final int? expenseAccountId;          // GL expense account from Chart of Accounts
  final int? shippingCompanyId;         // linked shipping company
  final int? clearingAgentId;           // linked clearing agent

  bool get isPaid =>
      treasuryTransactionId != null || bankTransactionId != null;

  const ShipmentCostItemModel({
    this.id,
    this.shipmentId = 0,
    this.category = 'other',
    this.reportCategoryId,
    this.reportCategoryName,
    this.description = '',
    this.quantity = 1,
    this.unitPrice = 0,
    this.totalPrice = 0,
    this.sortOrder = 0,
    this.createdAt,
    this.isReadOnly = false,
    this.vendorType,
    this.vendorId,
    this.exchangeRate = 1.0,
    this.supplierId,
    this.supplierCurrency,
    this.paymentSourceType,
    this.paymentSourceId,
    this.treasuryTransactionId,
    this.bankTransactionId,
    this.journalEntryId,
    this.revisionNumber,
    this.expenseAccountId,
    this.shippingCompanyId,
    this.clearingAgentId,
  });

  String get categoryLabel {
    if (reportCategoryName != null && reportCategoryName!.isNotEmpty) {
      return reportCategoryName!;
    }
    switch (category) {
      case 'manual_crop': return 'المحاصيل';
      case 'packing': return 'تعبئة وتغليف';
      case 'manual_packing': return 'تعبئة وتغليف إضافية';
      case 'freight': return 'الشحن';
      case 'TRANSPORT': return 'شحن';
      case 'clearance': return 'التخليص الجمركي';
      case 'CLEARING': return 'تخليص جمركي';
      case 'logistics': return 'لوجستيك ونقل';
      case 'admin': return 'مصاريف إدارية';
      case 'other': return 'أخرى';
      case 'OTHER': return 'أخرى';
      default: return category;
    }
  }

   /// قيمة التكلفة بالعملة الأصلية للمورد/الشركة (بعد تحويل سعر الصرف)
   double get totalInVendorCurrency => (totalPrice / exchangeRate).toDouble();

   factory ShipmentCostItemModel.fromMap(Map<String, dynamic> map) {
    return ShipmentCostItemModel(
      id: map['id'] as int?,
      shipmentId: (map['shipment_id'] as num?)?.toInt() ?? 0,
      category: (map['category'] as String?) ?? 'other',
      reportCategoryId: map['report_category_id'] as int?,
      reportCategoryName: map['cost_report_categories'] != null
          ? (map['cost_report_categories'] as Map)['name']?.toString()
          : null,
      description: (map['description'] as String?) ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0,
      totalPrice: (map['total_price'] as num?)?.toDouble() ?? 0,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      vendorType: map['vendor_type'] as String?,
      vendorId: (map['vendor_id'] as num?)?.toInt(),
      exchangeRate: (map['exchange_rate'] as num?)?.toDouble() ?? 1.0,
      supplierId: map['supplier_id'] as String?,
      supplierCurrency: map['supplier_currency'] as String?,
      paymentSourceType: map['payment_source_type'] as String?,
      paymentSourceId: (map['payment_source_id'] as num?)?.toInt(),
      treasuryTransactionId: (map['treasury_transaction_id'] as num?)?.toInt(),
      bankTransactionId: (map['bank_transaction_id'] as num?)?.toInt(),
      journalEntryId: (map['journal_entry_id'] as num?)?.toInt(),
      revisionNumber: (map['revision_number'] as num?)?.toInt(),
      expenseAccountId: (map['expense_account_id'] as num?)?.toInt(),
      shippingCompanyId: (map['shipping_company_id'] as num?)?.toInt(),
      clearingAgentId: (map['clearing_agent_id'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'shipment_id': shipmentId,
      'category': category,
      'report_category_id': reportCategoryId,
      'description': description,
      'quantity': quantity,
      'unit_price': unitPrice,
      'sort_order': sortOrder,
      if (vendorType != null) 'vendor_type': vendorType,
      if (vendorId != null) 'vendor_id': vendorId,
      'exchange_rate': exchangeRate,
      if (supplierId != null) 'supplier_id': supplierId,
      if (supplierCurrency != null) 'supplier_currency': supplierCurrency,
      // payment source fields (never overwrite a paid stamp during a save)
      if (paymentSourceType != null) 'payment_source_type': paymentSourceType,
      if (paymentSourceId != null) 'payment_source_id': paymentSourceId,
      if (expenseAccountId != null) 'expense_account_id': expenseAccountId,
      if (shippingCompanyId != null) 'shipping_company_id': shippingCompanyId,
      if (clearingAgentId != null) 'clearing_agent_id': clearingAgentId,
    };
  }

  ShipmentCostItemModel copyWith({
    int? id,
    int? shipmentId,
    String? category,
    int? reportCategoryId,
    String? reportCategoryName,
    String? description,
    double? quantity,
    double? unitPrice,
    double? totalPrice,
    int? sortOrder,
    DateTime? createdAt,
    bool? isReadOnly,
    String? vendorType,
    int? vendorId,
    double? exchangeRate,
    String? supplierId,
    String? supplierCurrency,
    String? paymentSourceType,
    int? paymentSourceId,
    int? treasuryTransactionId,
    int? bankTransactionId,
    int? journalEntryId,
    int? revisionNumber,
    int? expenseAccountId,
    int? shippingCompanyId,
    int? clearingAgentId,
  }) {
    return ShipmentCostItemModel(
      id: id ?? this.id,
      shipmentId: shipmentId ?? this.shipmentId,
      category: category ?? this.category,
      reportCategoryId: reportCategoryId ?? this.reportCategoryId,
      reportCategoryName: reportCategoryName ?? this.reportCategoryName,
      description: description ?? this.description,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      totalPrice: totalPrice ?? this.totalPrice,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      isReadOnly: isReadOnly ?? this.isReadOnly,
      vendorType: vendorType ?? this.vendorType,
      vendorId: vendorId ?? this.vendorId,
      exchangeRate: exchangeRate ?? this.exchangeRate,
      supplierId: supplierId ?? this.supplierId,
      supplierCurrency: supplierCurrency ?? this.supplierCurrency,
      paymentSourceType: paymentSourceType ?? this.paymentSourceType,
      paymentSourceId: paymentSourceId ?? this.paymentSourceId,
      treasuryTransactionId: treasuryTransactionId ?? this.treasuryTransactionId,
      bankTransactionId: bankTransactionId ?? this.bankTransactionId,
      journalEntryId: journalEntryId ?? this.journalEntryId,
      revisionNumber: revisionNumber ?? this.revisionNumber,
      expenseAccountId: expenseAccountId ?? this.expenseAccountId,
      shippingCompanyId: shippingCompanyId ?? this.shippingCompanyId,
      clearingAgentId: clearingAgentId ?? this.clearingAgentId,
    );
  }
}
