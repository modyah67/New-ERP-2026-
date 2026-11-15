class SupplierExpectedCostItemModel {
  final int costItemId;
  final int packingOrderId;
  final String orderNumber;
  final String orderStatus;
  final DateTime? orderDate;
  final double packingCostPerCarton;
  final String itemName;
  final String category;
  final int? reportCategoryId;
  final String reportCategoryName;
  final String costStatus; // 'expected' or 'actual'
  final double expectedAmount;
  final double? actualAmount;
  final double varianceAmount;
  final String originalCurrency;
  final double originalAmount;
  final double exchangeRate;
  final double baseAmount;
  final String? invoiceRef;
  final String? settlementNotes;
  final DateTime? reconciledAt;
  final int? varianceJournalEntryId;
  final String? supplierId;
  final String? supplierName;
  final String? supplierCode;
  final String? supplierType;
  final String? supplierPhone;
  final double? supplierOutstandingBalance;
  final List<Map<String, dynamic>> linkedShipments;

  final double? quantity;
  final double? unitPrice;
  final double? actualQuantity;
  final double? actualUnitPrice;
  final DateTime? actualDateTime;
  final String? detailedNotes;
  final bool isLocked;
  final Map<String, dynamic>? currencySnapshot;

  double get displayQuantity =>
      (actualQuantity != null && actualQuantity! > 0)
          ? actualQuantity!
          : ((quantity != null && quantity! > 0) ? quantity! : 1.0);
  double get displayUnitPrice => (actualUnitPrice != null && actualUnitPrice! > 0)
      ? actualUnitPrice!
      : ((unitPrice != null && unitPrice! > 0)
          ? unitPrice!
          : (expectedAmount > 0 ? (expectedAmount / displayQuantity) : 0.0));

  const SupplierExpectedCostItemModel({
    required this.costItemId,
    required this.packingOrderId,
    required this.orderNumber,
    required this.orderStatus,
    this.orderDate,
    this.packingCostPerCarton = 0.0,
    required this.itemName,
    required this.category,
    this.reportCategoryId,
    required this.reportCategoryName,
    required this.costStatus,
    required this.expectedAmount,
    this.actualAmount,
    this.varianceAmount = 0.0,
    this.originalCurrency = 'EGP',
    this.originalAmount = 0.0,
    this.exchangeRate = 1.0,
    this.baseAmount = 0.0,
    this.quantity = 1.0,
    this.unitPrice = 0.0,
    this.actualQuantity,
    this.actualUnitPrice,
    this.actualDateTime,
    this.detailedNotes,
    this.isLocked = false,
    this.currencySnapshot,
    this.invoiceRef,
    this.settlementNotes,
    this.reconciledAt,
    this.varianceJournalEntryId,
    this.supplierId,
    this.supplierName,
    this.supplierCode,
    this.supplierType,
    this.supplierPhone,
    this.supplierOutstandingBalance,
    this.linkedShipments = const [],
  });

  bool get isExpected => costStatus == 'expected';
  bool get isActual => costStatus == 'actual';
  String get statusLabel => isExpected ? 'تقديري' : 'فعلي';

  factory SupplierExpectedCostItemModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic d) {
      if (d == null) return null;
      if (d is DateTime) return d;
      return DateTime.tryParse(d.toString());
    }

    double parseNum(dynamic val, [double def = 0.0]) {
      if (val == null) return def;
      if (val is num) return val.toDouble();
      return double.tryParse(val.toString()) ?? def;
    }

    int parseInt(dynamic val, [int def = 0]) {
      if (val == null) return def;
      if (val is int) return val;
      if (val is num) return val.toInt();
      return int.tryParse(val.toString()) ?? def;
    }

    List<Map<String, dynamic>> shipments = [];
    if (json['linked_shipments'] is List) {
      shipments = (json['linked_shipments'] as List)
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }

    final expAmt = parseNum(json['expected_amount']);
    final baseAmt = parseNum(json['base_amount']);
    final origAmt = parseNum(json['original_amount']);
    final snapshot = json['currency_snapshot'] is Map ? json['currency_snapshot'] as Map : null;
    final snapTotal = snapshot != null
        ? parseNum(snapshot['total_egp'] ?? snapshot['total'])
        : 0.0;

    final resolvedExpectedAmount = expAmt > 0
        ? expAmt
        : (baseAmt > 0
            ? baseAmt
            : (snapTotal > 0 ? snapTotal : (origAmt > 0 ? origAmt : 0.0)));

    final qty = parseNum(json['quantity'] ?? snapshot?['quantity'], 1.0);
    final rawUnitPrice = json['unit_price'] ?? snapshot?['unit_price'];
    final uPrice = rawUnitPrice != null
        ? parseNum(rawUnitPrice)
        : (resolvedExpectedAmount > 0 ? (resolvedExpectedAmount / (qty > 0 ? qty : 1.0)) : 0.0);

    final isLockedVal = json['is_locked'] == true ||
        (json['cost_status'] == 'actual') ||
        (json['cost_status'] == 'settled') ||
        (json['cost_status'] == 'locked');

    final actualQtyVal = json['actual_quantity'] != null
        ? parseNum(json['actual_quantity'])
        : (json['quantity'] != null ? parseNum(json['quantity']) : null);
    final actualUnitPriceVal = json['actual_unit_price'] != null
        ? parseNum(json['actual_unit_price'])
        : (json['unit_price'] != null ? parseNum(json['unit_price']) : null);
    final actualDateTimeVal = parseDate(json['actual_date_time'] ?? json['reconciled_at'] ?? json['locked_at']);
    final detailedNotesVal = (json['detailed_notes'] ?? json['settlement_notes'] ?? json['notes'] ?? snapshot?['notes'])?.toString();

    final currencySnapshotVal = json['currency_snapshot'] is Map
        ? Map<String, dynamic>.from(json['currency_snapshot'] as Map)
        : null;

    return SupplierExpectedCostItemModel(
      costItemId: parseInt(json['cost_item_id'] ?? json['id']),
      packingOrderId: parseInt(json['packing_order_id']),
      orderNumber: (json['order_number'] ?? '').toString(),
      orderStatus: (json['order_status'] ?? 'pending').toString(),
      orderDate: parseDate(json['order_date']),
      packingCostPerCarton: parseNum(json['packing_cost_per_carton']),
      itemName: (json['item_name'] ?? json['name'] ?? 'بند تكلفة').toString(),
      category: (json['category'] ?? 'other').toString(),
      reportCategoryId: json['report_category_id'] != null
          ? parseInt(json['report_category_id'])
          : null,
      reportCategoryName:
          (json['report_category_name'] ?? json['category'] ?? '').toString(),
      costStatus: (json['cost_status'] ?? 'expected').toString(),
      expectedAmount: resolvedExpectedAmount,
      actualAmount: json['actual_amount'] != null
          ? parseNum(json['actual_amount'])
          : null,
      varianceAmount: parseNum(json['variance_amount']),
      originalCurrency: (json['original_currency'] ?? 'EGP').toString(),
      originalAmount: parseNum(json['original_amount']),
      exchangeRate: parseNum(json['exchange_rate'], 1.0),
      baseAmount: baseAmt > 0 ? baseAmt : resolvedExpectedAmount,
      quantity: qty > 0 ? qty : 1.0,
      unitPrice: uPrice,
      actualQuantity: actualQtyVal,
      actualUnitPrice: actualUnitPriceVal,
      actualDateTime: actualDateTimeVal,
      detailedNotes: detailedNotesVal,
      isLocked: isLockedVal,
      currencySnapshot: currencySnapshotVal,
      invoiceRef: json['invoice_ref']?.toString(),
      settlementNotes: json['settlement_notes']?.toString(),
      reconciledAt: parseDate(json['reconciled_at']),
      varianceJournalEntryId: json['variance_journal_entry_id'] != null
          ? parseInt(json['variance_journal_entry_id'])
          : null,
      supplierId: (json['supplier_id'] ?? snapshot?['supplier_id'])?.toString(),
      supplierName: (json['supplier_name'] ?? snapshot?['supplier_name'])?.toString(),
      supplierCode: (json['supplier_code'] ?? snapshot?['supplier_code'])?.toString(),
      supplierType: (json['supplier_type'] ?? snapshot?['supplier_type'])?.toString(),
      supplierPhone: json['supplier_phone']?.toString(),
      supplierOutstandingBalance: json['supplier_outstanding_balance'] != null
          ? parseNum(json['supplier_outstanding_balance'])
          : null,
      linkedShipments: shipments,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cost_item_id': costItemId,
      'packing_order_id': packingOrderId,
      'order_number': orderNumber,
      'order_status': orderStatus,
      'order_date': orderDate?.toIso8601String(),
      'packing_cost_per_carton': packingCostPerCarton,
      'item_name': itemName,
      'category': category,
      'report_category_id': reportCategoryId,
      'report_category_name': reportCategoryName,
      'cost_status': costStatus,
      'expected_amount': expectedAmount,
      'actual_amount': actualAmount,
      'variance_amount': varianceAmount,
      'original_currency': originalCurrency,
      'original_amount': originalAmount,
      'exchange_rate': exchangeRate,
      'base_amount': baseAmount,
      'quantity': quantity,
      'unit_price': unitPrice,
      'actual_quantity': actualQuantity,
      'actual_unit_price': actualUnitPrice,
      'actual_date_time': actualDateTime?.toIso8601String(),
      'detailed_notes': detailedNotes,
      'is_locked': isLocked,
      'currency_snapshot': currencySnapshot,
      'invoice_ref': invoiceRef,
      'settlement_notes': settlementNotes,
      'reconciled_at': reconciledAt?.toIso8601String(),
      'variance_journal_entry_id': varianceJournalEntryId,
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'supplier_code': supplierCode,
      'supplier_type': supplierType,
      'supplier_phone': supplierPhone,
      'supplier_outstanding_balance': supplierOutstandingBalance,
      'linked_shipments': linkedShipments,
    };
  }
}
