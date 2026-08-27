class ExportInvoiceModel {
  final String? id;
  final String invoiceNo;
  final DateTime date;
  final String customerId;
  final String? customerName;
  final int transportMode;
  final int totalCartons;
  final int totalPallets;
  final double totalNetWeight;
  final double totalGrossWeight;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String currencyCode;
  final double exportPricePerCarton;
  final double purchaseCostPerCarton;
  final double totalAmountForeign;
  final double exchangeRateUsed;
  final double totalAmountEgp;
  final double totalCostEgp;
  final double netProfitEgp;

  ExportInvoiceModel({
    this.id,
    required this.invoiceNo,
    required this.date,
    required this.customerId,
    this.customerName,
    this.transportMode = 0,
    this.totalCartons = 0,
    this.totalPallets = 0,
    this.totalNetWeight = 0.0,
    this.totalGrossWeight = 0.0,
    this.notes,
    this.createdAt,
    this.updatedAt,
    this.currencyCode = 'EGP',
    this.exportPricePerCarton = 0.0,
    this.purchaseCostPerCarton = 0.0,
    this.totalAmountForeign = 0.0,
    this.exchangeRateUsed = 1.0,
    this.totalAmountEgp = 0.0,
    this.totalCostEgp = 0.0,
    this.netProfitEgp = 0.0,
  });

  String get transportModeLabel => transportMode == 0 ? 'بحري (Sea)' : 'جوي (Air)';

  factory ExportInvoiceModel.fromMap(Map<String, dynamic> map) {
    final cust = map['customers'];
    return ExportInvoiceModel(
      id: map['id']?.toString(),
      invoiceNo: (map['invoice_no'] as String?) ?? '',
      date: map['date'] != null
          ? DateTime.tryParse(map['date'] as String) ?? DateTime.now()
          : DateTime.now(),
      customerId: map['customer_id']?.toString() ?? '',
      customerName: cust is Map ? cust['name'] as String? : (map['customer_name'] as String?),
      transportMode: (map['transport_mode'] as int?) ?? 0,
      totalCartons: (map['total_cartons'] as int?) ?? 0,
      totalPallets: (map['total_pallets'] as int?) ?? 0,
      totalNetWeight: (map['total_net_weight'] as num?)?.toDouble() ?? 0.0,
      totalGrossWeight: (map['total_gross_weight'] as num?)?.toDouble() ?? 0.0,
      notes: map['notes'] as String?,
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'] as String) : null,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'] as String) : null,
      currencyCode: (map['currency_code'] as String?) ?? 'EGP',
      exportPricePerCarton: (map['export_price_per_carton'] as num?)?.toDouble() ?? 0.0,
      purchaseCostPerCarton: (map['purchase_cost_per_carton'] as num?)?.toDouble() ?? 0.0,
      totalAmountForeign: (map['total_amount_foreign'] as num?)?.toDouble() ?? 0.0,
      exchangeRateUsed: (map['exchange_rate_used'] as num?)?.toDouble() ?? 1.0,
      totalAmountEgp: (map['total_amount_egp'] as num?)?.toDouble() ?? 0.0,
      totalCostEgp: (map['total_cost_egp'] as num?)?.toDouble() ?? 0.0,
      netProfitEgp: (map['net_profit_egp'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'invoice_no': invoiceNo,
      'date': _formatDate(date),
      'customer_id': customerId,
      'transport_mode': transportMode,
      'total_cartons': totalCartons,
      'total_pallets': totalPallets,
      'total_net_weight': totalNetWeight,
      'total_gross_weight': totalGrossWeight,
      if (notes != null) 'notes': notes,
      'currency_code': currencyCode,
      'export_price_per_carton': exportPricePerCarton,
      'purchase_cost_per_carton': purchaseCostPerCarton,
      'total_amount_foreign': totalAmountForeign,
      'exchange_rate_used': exchangeRateUsed,
      'total_amount_egp': totalAmountEgp,
      'total_cost_egp': totalCostEgp,
      'net_profit_egp': netProfitEgp,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  static String _formatDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  ExportInvoiceModel copyWith({
    String? id,
    String? invoiceNo,
    DateTime? date,
    String? customerId,
    String? customerName,
    int? transportMode,
    int? totalCartons,
    int? totalPallets,
    double? totalNetWeight,
    double? totalGrossWeight,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? currencyCode,
    double? exportPricePerCarton,
    double? purchaseCostPerCarton,
    double? totalAmountForeign,
    double? exchangeRateUsed,
    double? totalAmountEgp,
    double? totalCostEgp,
    double? netProfitEgp,
  }) {
    return ExportInvoiceModel(
      id: id ?? this.id,
      invoiceNo: invoiceNo ?? this.invoiceNo,
      date: date ?? this.date,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      transportMode: transportMode ?? this.transportMode,
      totalCartons: totalCartons ?? this.totalCartons,
      totalPallets: totalPallets ?? this.totalPallets,
      totalNetWeight: totalNetWeight ?? this.totalNetWeight,
      totalGrossWeight: totalGrossWeight ?? this.totalGrossWeight,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      currencyCode: currencyCode ?? this.currencyCode,
      exportPricePerCarton: exportPricePerCarton ?? this.exportPricePerCarton,
      purchaseCostPerCarton: purchaseCostPerCarton ?? this.purchaseCostPerCarton,
      totalAmountForeign: totalAmountForeign ?? this.totalAmountForeign,
      exchangeRateUsed: exchangeRateUsed ?? this.exchangeRateUsed,
      totalAmountEgp: totalAmountEgp ?? this.totalAmountEgp,
      totalCostEgp: totalCostEgp ?? this.totalCostEgp,
      netProfitEgp: netProfitEgp ?? this.netProfitEgp,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExportInvoiceModel && id != null && other.id != null && id == other.id;

  @override
  int get hashCode => id?.hashCode ?? 0;
}
