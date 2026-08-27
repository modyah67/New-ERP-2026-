class LotGradingResult {
  final String? id;
  final String lotId;
  final String grade;
  final double weightKg;
  final String? stockBatchId;
  final String? notes;
  final DateTime? createdAt;

  const LotGradingResult({
    this.id,
    required this.lotId,
    required this.grade,
    this.weightKg = 0.0,
    this.stockBatchId,
    this.notes,
    this.createdAt,
  });

  double percentageOf(double totalKg) =>
      totalKg > 0 ? (weightKg / totalKg * 100) : 0;

  factory LotGradingResult.fromMap(Map<String, dynamic> map) {
    return LotGradingResult(
      id: map['id']?.toString(),
      lotId: map['lot_id']?.toString() ?? '',
      grade: map['grade'] as String,
      weightKg: (map['weight_kg'] as num?)?.toDouble() ?? 0.0,
      stockBatchId: map['stock_batch_id']?.toString(),
      notes: map['notes'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'lot_id': lotId,
      'grade': grade,
      'weight_kg': weightKg,
      if (stockBatchId != null) 'stock_batch_id': stockBatchId,
      if (notes != null) 'notes': notes,
    };
  }
}

class LotReceiptModel {
  static const List<String> validStatuses = [
    'received', 'sorting', 'packed', 'shipped', 'closed',
  ];

  final String? id;
  final String lotNumber;
  final String? fruitTypeId;
  final String? productName;
  final String? supplierId;
  final String? supplierName;
  final DateTime receiptDate;
  final double grossWeightKg;
  final double netWeightKg;
  final double wasteWeightKg;
  final double wastePercentage;
  final String status;
  final String? stationId;
  final String? purchaseInvoiceItemId;
  final double productCostPerKg;
  final double totalProductCost;
  final String? notes;
  final DateTime? createdAt;
  final String purchaseMode;
  final int? cartonCount;
  final double? weightPerCartonKg;
  final double? grossWeightPerCartonKg;
  final double? pricePerCarton;
  final String currency;
  final double exchangeRate;
  final bool isConfirmed;
  final DateTime? confirmedAt;
  final double paidAmount;
  final String paymentSourceType;
  final String? paymentTreasuryId;
  final int? paymentBankAccountId;
  final int? journalEntryId;

  double get fruitCostPerKg => productCostPerKg;
  double get totalFruitCost => totalProductCost;
  int get netCartonCount {
    if (purchaseMode == 'carton' && (weightPerCartonKg ?? 0) > 0) {
      return (netWeightKg / weightPerCartonKg!).round();
    }
    return cartonCount ?? 0;
  }
  double get costPerCarton => pricePerCarton ?? 0.0;

  List<LotGradingResult> gradingResults;

  double get gradingWastePercentage {
    final waste = gradingResults
        .where((r) => r.grade == 'waste')
        .fold<double>(0.0, (sum, r) => sum + r.weightKg);
    return grossWeightKg > 0 ? (waste / grossWeightKg * 100) : 0;
  }

  double get gradedPercentage {
    final graded = gradingResults
        .where((r) => r.grade != 'waste')
        .fold<double>(0.0, (sum, r) => sum + r.weightKg);
    return grossWeightKg > 0 ? (graded / grossWeightKg * 100) : 0;
  }

  LotReceiptModel({
    this.id,
    required this.lotNumber,
    this.fruitTypeId,
    this.productName,
    this.supplierId,
    this.supplierName,
    required this.receiptDate,
    this.grossWeightKg = 0.0,
    this.netWeightKg = 0.0,
    double? wasteWeightKg,
    double? wastePercentage,
    this.status = 'received',
    this.stationId,
    this.purchaseInvoiceItemId,
    this.productCostPerKg = 0.0,
    this.totalProductCost = 0.0,
    this.notes,
    this.createdAt,
    this.purchaseMode = 'weight',
    this.cartonCount,
    this.weightPerCartonKg,
    this.grossWeightPerCartonKg,
    this.pricePerCarton,
    this.currency = 'EGP',
    this.exchangeRate = 1.0,
    this.isConfirmed = false,
    this.confirmedAt,
    this.paidAmount = 0.0,
    this.paymentSourceType = 'treasury',
    this.paymentTreasuryId,
    this.paymentBankAccountId,
    this.journalEntryId,
    List<LotGradingResult>? gradingResults,
  })  : wasteWeightKg = wasteWeightKg ?? grossWeightKg - netWeightKg,
        wastePercentage = wastePercentage ??
            (grossWeightKg > 0
                ? ((grossWeightKg - netWeightKg) / grossWeightKg * 100)
                : 0),
        gradingResults = gradingResults ?? [] {
    if (!validStatuses.contains(status)) {
      throw ArgumentError('Invalid lot_receipts status: "$status". '
          'Must be one of: ${validStatuses.join(", ")}');
    }
  }

  factory LotReceiptModel.fromMap(Map<String, dynamic> map) {
    final grossWeight = (map['gross_weight_kg'] as num?)?.toDouble() ?? 0.0;
    var parsedProductCostPerKg = (map['product_cost_per_kg'] as num?)?.toDouble() ?? (map['fruit_cost_per_kg'] as num?)?.toDouble() ?? 0.0;
    final parsedTotalProductCost = (map['total_product_cost'] as num?)?.toDouble() ?? (map['total_fruit_cost'] as num?)?.toDouble() ?? 0.0;

    if (parsedProductCostPerKg == 0 && parsedTotalProductCost > 0 && grossWeight > 0) {
      parsedProductCostPerKg = parsedTotalProductCost / grossWeight;
    }

    return LotReceiptModel(
      id: map['id']?.toString(),
      lotNumber: (map['lot_number'] as String?) ?? '',
      fruitTypeId: map['fruit_type_id']?.toString(),
      productName: map['product_name'] as String?,
      supplierId: map['supplier_id']?.toString(),
      supplierName: map['supplier_name'] as String?,
      receiptDate: map['receipt_date'] != null
          ? DateTime.parse(map['receipt_date'] as String)
          : DateTime.now(),
      grossWeightKg: grossWeight,
      netWeightKg: (map['net_weight_kg'] as num?)?.toDouble() ?? 0.0,
      wasteWeightKg: (map['waste_weight_kg'] as num?)?.toDouble(),
      wastePercentage: (map['waste_percentage'] as num?)?.toDouble(),
      status: (map['status'] as String?) ?? 'received',
      stationId: map['station_id']?.toString(),
      purchaseInvoiceItemId: map['purchase_invoice_item_id']?.toString(),
      productCostPerKg: parsedProductCostPerKg,
      totalProductCost: parsedTotalProductCost,
      notes: map['notes'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      purchaseMode: (map['purchase_mode'] as String?) ?? 'weight',
      cartonCount: (map['carton_count'] as num?)?.toInt(),
      weightPerCartonKg: (map['weight_per_carton_kg'] as num?)?.toDouble(),
      grossWeightPerCartonKg: (map['gross_weight_per_carton_kg'] as num?)?.toDouble(),
      pricePerCarton: (map['price_per_carton'] as num?)?.toDouble(),
      currency: map['currency']?.toString() ?? 'EGP',
      exchangeRate: (map['exchange_rate'] as num?)?.toDouble() ?? 1.0,
      isConfirmed: map['is_confirmed'] == true,
      confirmedAt: map['confirmed_at'] != null
          ? DateTime.tryParse(map['confirmed_at'] as String)
          : null,
      paidAmount: (map['paid_amount'] as num?)?.toDouble() ?? 0.0,
      paymentSourceType: (map['payment_source_type'] as String?) ?? 'treasury',
      paymentTreasuryId: map['payment_treasury_id']?.toString(),
      paymentBankAccountId: (map['payment_bank_account_id'] as num?)?.toInt(),
      journalEntryId: (map['journal_entry_id'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'lot_number': lotNumber,
      if (fruitTypeId != null) 'fruit_type_id': fruitTypeId,
      if (productName != null) 'product_name': productName,
      if (supplierId != null) 'supplier_id': supplierId,
      'receipt_date':
          '${receiptDate.year}-${receiptDate.month.toString().padLeft(2, '0')}-${receiptDate.day.toString().padLeft(2, '0')}',
      'gross_weight_kg': grossWeightKg,
      'net_weight_kg': netWeightKg,
      'waste_weight_kg': wasteWeightKg,
      'waste_percentage': wastePercentage,
      'status': status,
      if (stationId != null) 'station_id': stationId,
      if (purchaseInvoiceItemId != null) 'purchase_invoice_item_id': purchaseInvoiceItemId,
      'fruit_cost_per_kg': productCostPerKg,
      'total_fruit_cost': totalProductCost,
      if (notes != null) 'notes': notes,
      'purchase_mode': purchaseMode,
      if (cartonCount != null) 'carton_count': cartonCount,
      if (weightPerCartonKg != null) 'weight_per_carton_kg': weightPerCartonKg,
      if (grossWeightPerCartonKg != null) 'gross_weight_per_carton_kg': grossWeightPerCartonKg,
      if (pricePerCarton != null) 'price_per_carton': pricePerCarton,
      'currency': currency,
      'exchange_rate': exchangeRate,
      'paid_amount': paidAmount,
      'payment_source_type': paymentSourceType,
      if (paymentTreasuryId != null) 'payment_treasury_id': paymentTreasuryId,
      if (paymentBankAccountId != null) 'payment_bank_account_id': paymentBankAccountId,
      if (journalEntryId != null) 'journal_entry_id': journalEntryId,
    };
  }

  LotReceiptModel copyWith({
    String? id,
    String? lotNumber,
    String? fruitTypeId,
    String? productName,
    String? supplierId,
    String? supplierName,
    DateTime? receiptDate,
    double? grossWeightKg,
    double? netWeightKg,
    double? wasteWeightKg,
    double? wastePercentage,
    String? status,
    String? stationId,
    String? purchaseInvoiceItemId,
    double? productCostPerKg,
    double? totalProductCost,
    String? notes,
    DateTime? createdAt,
    String? purchaseMode,
    int? cartonCount,
    double? weightPerCartonKg,
    double? grossWeightPerCartonKg,
    double? pricePerCarton,
    String? currency,
    double? exchangeRate,
    bool? isConfirmed,
    DateTime? confirmedAt,
    double? paidAmount,
    String? paymentSourceType,
    String? paymentTreasuryId,
    int? paymentBankAccountId,
    int? journalEntryId,
    List<LotGradingResult>? gradingResults,
  }) {
    return LotReceiptModel(
      id: id ?? this.id,
      lotNumber: lotNumber ?? this.lotNumber,
      fruitTypeId: fruitTypeId ?? this.fruitTypeId,
      productName: productName ?? this.productName,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      receiptDate: receiptDate ?? this.receiptDate,
      grossWeightKg: grossWeightKg ?? this.grossWeightKg,
      netWeightKg: netWeightKg ?? this.netWeightKg,
      wasteWeightKg: wasteWeightKg ?? this.wasteWeightKg,
      wastePercentage: wastePercentage ?? this.wastePercentage,
      status: status ?? this.status,
      stationId: stationId ?? this.stationId,
      purchaseInvoiceItemId: purchaseInvoiceItemId ?? this.purchaseInvoiceItemId,
      productCostPerKg: productCostPerKg ?? this.productCostPerKg,
      totalProductCost: totalProductCost ?? this.totalProductCost,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      purchaseMode: purchaseMode ?? this.purchaseMode,
      cartonCount: cartonCount ?? this.cartonCount,
      weightPerCartonKg: weightPerCartonKg ?? this.weightPerCartonKg,
      grossWeightPerCartonKg: grossWeightPerCartonKg ?? this.grossWeightPerCartonKg,
      pricePerCarton: pricePerCarton ?? this.pricePerCarton,
      currency: currency ?? this.currency,
      exchangeRate: exchangeRate ?? this.exchangeRate,
      isConfirmed: isConfirmed ?? this.isConfirmed,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      paidAmount: paidAmount ?? this.paidAmount,
      paymentSourceType: paymentSourceType ?? this.paymentSourceType,
      paymentTreasuryId: paymentTreasuryId ?? this.paymentTreasuryId,
      paymentBankAccountId: paymentBankAccountId ?? this.paymentBankAccountId,
      journalEntryId: journalEntryId ?? this.journalEntryId,
      gradingResults: gradingResults ?? List.from(this.gradingResults),
    );
  }
}
