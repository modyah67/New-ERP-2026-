class ExportShipmentModel {
  final String? id;
  final String shipmentNo;
  final String? invoiceId;
  final String? invoiceNumber;
  final String? customerId;
  final String? customerName;
  final String? customerCode;
  final String? clearingAgentId;
  final String? clearingAgentName;
  final String? contactPerson;
  final String? country;
  final String? countryOfOrigin;
  final String? destinationAddress;
  final String? containerNo;
  final String? containerType;
  final String? blNumber;
  final String? vesselName;
  final String? shippingCompany;
  final String? dataLoggerNo;
  final String? portOfLoading;
  final String? portOfDestination;
  final String transportMode;
  final int palletsCount;
  final int cartonsCount;
  final double netWeight;
  final double grossWeight;
  final String? incoterm;
  final String? paymentTerms;
  final String? currency;
  final String? termsConditions;
  final String? internalNotes;
  final String status;
  final String? packingRecipeId;
  final double freightCost;
  final double insuranceCost;
  final double clearanceCost;
  final double otherCosts;
  final double totalLandedCost;
  final double costPerCarton;
  final double exportPricePerCarton;
  final String currencyCode;
  final double exchangeRate;
  final double totalRevenueForeign;
  final double totalRevenueEgp;
  final double netProfitEgp;
  final double totalFruitCost;
  final double totalPackingMaterialCost;
  final double grossProfit;
  final double netProfit;
  final double discountAmount;
  final String? discountReason;
  final double appliedDiscountAmount;
  final DateTime? shipmentDate;
  final DateTime? createdAt;
  final bool needsProfitRedistribution;
  final double paidAmount;
  final String paymentSourceType;
  final String? paymentTreasuryId;
  final int? paymentBankAccountId;
  final double allocatedAdminExpenses;
  final double allocatedTaxes;
  final bool isConfirmed;
  final int? returnJournalEntryId;

  ExportShipmentModel({
    this.id,
    required this.shipmentNo,
    this.invoiceId,
    this.invoiceNumber,
    this.customerId,
    this.customerName,
    this.customerCode,
    this.clearingAgentId,
    this.clearingAgentName,
    this.contactPerson,
    this.country,
    this.countryOfOrigin,
    this.destinationAddress,
    this.containerNo,
    this.containerType,
    this.blNumber,
    this.vesselName,
    this.shippingCompany,
    this.dataLoggerNo,
    this.portOfLoading,
    this.portOfDestination,
    this.transportMode = 'sea',
    this.palletsCount = 0,
    this.cartonsCount = 0,
    this.netWeight = 0.0,
    this.grossWeight = 0.0,
    this.incoterm,
    this.paymentTerms,
    this.currency,
    this.termsConditions,
    this.internalNotes,
    this.status = 'draft',
    this.packingRecipeId,
    this.freightCost = 0.0,
    this.insuranceCost = 0.0,
    this.clearanceCost = 0.0,
    this.otherCosts = 0.0,
    this.totalLandedCost = 0.0,
    this.costPerCarton = 0.0,
    this.exportPricePerCarton = 0.0,
    this.currencyCode = 'USD',
    this.exchangeRate = 1.0,
    this.totalRevenueForeign = 0.0,
    this.totalRevenueEgp = 0.0,
    this.netProfitEgp = 0.0,
    this.totalFruitCost = 0.0,
    this.totalPackingMaterialCost = 0.0,
    this.grossProfit = 0.0,
    this.netProfit = 0.0,
    this.discountAmount = 0.0,
    this.discountReason,
    this.appliedDiscountAmount = 0.0,
    this.shipmentDate,
    this.createdAt,
    this.needsProfitRedistribution = false,
    this.paidAmount = 0.0,
    this.allocatedAdminExpenses = 0.0,
    this.allocatedTaxes = 0.0,
    this.paymentSourceType = 'treasury',
    this.paymentTreasuryId,
    this.paymentBankAccountId,
    this.isConfirmed = false,
    this.returnJournalEntryId,
  });

  double get grossProfitPerCarton => exportPricePerCarton - costPerCarton;
  double get profitMarginPercent =>
      totalRevenueEgp > 0 ? (netProfitEgp / totalRevenueEgp * 100) : 0;

  factory ExportShipmentModel.fromMap(Map<String, dynamic> map) {
    return ExportShipmentModel(
      id: map['id']?.toString(),
      shipmentNo:
          (map['shipment_no'] ?? map['shipment_number'] ?? '').toString(),
      invoiceId: map['invoice_id']?.toString(),
      invoiceNumber: map['invoice_number']?.toString(),
      customerId: map['customer_id']?.toString(),
      customerName: (map['customer_name'] ?? '').toString(),
      customerCode: (map['customer_code'] ?? '').toString(),
      clearingAgentId: map['clearing_agent_id']?.toString(),
      clearingAgentName: (map['clearing_agent_name'] ?? '').toString(),
      contactPerson: map['contact_person']?.toString(),
      country: (map['destination_country'] ?? map['country'] ?? '').toString(),
      countryOfOrigin: (map['country_of_origin']?.toString()),
      destinationAddress: map['destination_address']?.toString(),
      containerNo: (map['container_number'] ?? map['container_no'])?.toString(),
      containerType: map['container_type']?.toString(),
      blNumber: map['bl_number']?.toString(),
      vesselName: map['vessel_name']?.toString(),
      shippingCompany: map['shipping_company']?.toString(),
      dataLoggerNo: map['data_logger_no']?.toString(),
      portOfLoading: map['port_of_loading']?.toString(),
      portOfDestination: map['port_of_destination']?.toString(),
      transportMode:
          (map['transport_mode'] ?? map['shipping_method'] ?? 'sea').toString(),
      palletsCount: _parseInt(map['pallet_count'] ?? map['pallets_count']) ?? 0,
      cartonsCount: _parseInt(map['carton_count'] ?? map['cartons_count']) ?? 0,
      netWeight: _parseDouble(map['net_weight']) ?? 0.0,
      grossWeight: _parseDouble(map['gross_weight']) ?? 0.0,
      incoterm: map['incoterm']?.toString(),
      paymentTerms: map['payment_terms']?.toString(),
      currency: map['currency']?.toString(),
      termsConditions: map['terms_conditions']?.toString(),
      internalNotes: (map['internal_notes'] ?? map['notes'])?.toString(),
      status: (map['status'] ?? 'draft').toString(),
      packingRecipeId: map['packing_recipe_id']?.toString(),
      freightCost: _parseDouble(map['freight_cost']) ?? 0.0,
      insuranceCost: _parseDouble(map['insurance_cost']) ?? 0.0,
      clearanceCost: _parseDouble(map['clearance_cost']) ?? 0.0,
      otherCosts: _parseDouble(map['other_costs']) ?? 0.0,
      totalLandedCost: _parseDouble(map['total_landed_cost']) ?? 0.0,
      costPerCarton: _parseDouble(map['cost_per_carton']) ?? 0.0,
      exportPricePerCarton: _parseDouble(map['export_price_per_carton']) ?? 0.0,
      currencyCode: (map['currency_code'] ?? 'USD').toString(),
      exchangeRate: _parseDouble(map['exchange_rate']) ?? 1.0,
      totalRevenueForeign: _parseDouble(map['total_revenue_foreign']) ?? 0.0,
      totalRevenueEgp: _parseDouble(map['total_revenue_egp']) ?? 0.0,
      netProfitEgp: _parseDouble(map['net_profit_egp']) ?? 0.0,
      totalFruitCost: _parseDouble(map['total_fruit_cost']) ?? 0.0,
      totalPackingMaterialCost:
          _parseDouble(map['total_packing_material_cost']) ?? 0.0,
      grossProfit: _parseDouble(map['gross_profit']) ?? 0.0,
      netProfit: _parseDouble(map['net_profit']) ?? 0.0,
      discountAmount: _parseDouble(map['discount_amount']) ?? 0.0,
      discountReason: map['discount_reason']?.toString(),
      appliedDiscountAmount: _parseDouble(map['applied_discount_amount']) ?? 0.0,
      shipmentDate: _parseDate(map['shipment_date']),
      createdAt: _parseDate(map['created_at']),
      needsProfitRedistribution: map['needs_profit_redistribution'] == true,
      paidAmount: _parseDouble(map['paid_amount']) ?? 0.0,
      allocatedAdminExpenses: _parseDouble(map['allocated_admin_expenses']) ?? 0.0,
      allocatedTaxes: _parseDouble(map['allocated_taxes']) ?? 0.0,
      paymentSourceType: (map['payment_source_type'] ?? 'treasury').toString(),
      paymentTreasuryId: map['payment_treasury_id']?.toString(),
      paymentBankAccountId: _parseInt(map['payment_bank_account_id']),
      isConfirmed: map['is_confirmed'] == true,
      returnJournalEntryId: _parseInt(map['return_journal_entry_id']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'shipment_no': shipmentNo,
      if (invoiceId != null) 'invoice_id': invoiceId,
      if (invoiceNumber != null && invoiceNumber!.isNotEmpty)
        'invoice_number': invoiceNumber,
      if (customerId != null) 'customer_id': customerId,
      'customer_name': customerName ?? '',
      'customer_code': customerCode ?? '',
      if (clearingAgentId != null) 'clearing_agent_id': clearingAgentId,
      'clearing_agent_name': clearingAgentName ?? '',
      if (contactPerson != null) 'contact_person': contactPerson,
      'destination_country': country ?? '',
      if (countryOfOrigin != null && countryOfOrigin!.isNotEmpty)
        'country_of_origin': countryOfOrigin,
      if (destinationAddress != null) 'destination_address': destinationAddress,
      if (containerNo != null) 'container_number': containerNo,
      if (containerType != null) 'container_type': containerType,
      if (blNumber != null) 'bl_number': blNumber,
      if (vesselName != null) 'vessel_name': vesselName,
      if (shippingCompany != null) 'shipping_company': shippingCompany,
      if (dataLoggerNo != null) 'data_logger_no': dataLoggerNo,
      if (portOfLoading != null) 'port_of_loading': portOfLoading,
      if (portOfDestination != null) 'port_of_destination': portOfDestination,
      'transport_mode': transportMode,
      'pallet_count': palletsCount,
      'carton_count': cartonsCount,
      'net_weight': netWeight,
      'gross_weight': grossWeight,
      if (incoterm != null) 'incoterm': incoterm,
      if (paymentTerms != null) 'payment_terms': paymentTerms,
      if (currency != null) 'currency': currency,
      if (termsConditions != null) 'terms_conditions': termsConditions,
      if (internalNotes != null) 'internal_notes': internalNotes,
      'status': status,
      if (packingRecipeId != null) 'packing_recipe_id': packingRecipeId,
      'freight_cost': freightCost,
      'insurance_cost': insuranceCost,
      'clearance_cost': clearanceCost,
      'other_costs': otherCosts,
      'total_landed_cost': totalLandedCost,
      'cost_per_carton': costPerCarton,
      'export_price_per_carton': exportPricePerCarton,
      'currency_code': currencyCode,
      'exchange_rate': exchangeRate,
      'total_revenue_foreign': totalRevenueForeign,
      'total_revenue_egp': totalRevenueEgp,
      'net_profit_egp': netProfitEgp,
      'total_fruit_cost': totalFruitCost,
      'total_packing_material_cost': totalPackingMaterialCost,
      'gross_profit': grossProfit,
      'net_profit': netProfit,
      'discount_amount': discountAmount,
      if (discountReason != null) 'discount_reason': discountReason,
      'applied_discount_amount': appliedDiscountAmount,
      if (shipmentDate != null) 'shipment_date': _formatDate(shipmentDate!),
      'needs_profit_redistribution': needsProfitRedistribution,
      'paid_amount': paidAmount,
      'allocated_admin_expenses': allocatedAdminExpenses,
      'allocated_taxes': allocatedTaxes,
      'payment_source_type': paymentSourceType,
      if (paymentTreasuryId != null) 'payment_treasury_id': paymentTreasuryId,
      if (paymentBankAccountId != null) 'payment_bank_account_id': paymentBankAccountId,
      'is_confirmed': isConfirmed,
      if (returnJournalEntryId != null) 'return_journal_entry_id': returnJournalEntryId,
    };
  }

  static String _formatDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  ExportShipmentModel copyWith({
    String? id,
    String? shipmentNo,
    String? invoiceId,
    String? invoiceNumber,
    String? customerId,
    String? customerName,
    String? customerCode,
    String? clearingAgentId,
    String? clearingAgentName,
    String? contactPerson,
    String? country,
    String? countryOfOrigin,
    String? destinationAddress,
    String? containerNo,
    String? containerType,
    String? blNumber,
    String? vesselName,
    String? shippingCompany,
    String? dataLoggerNo,
    String? portOfLoading,
    String? portOfDestination,
    String? transportMode,
    int? palletsCount,
    int? cartonsCount,
    double? netWeight,
    double? grossWeight,
    String? incoterm,
    String? paymentTerms,
    String? currency,
    String? termsConditions,
    String? internalNotes,
    String? status,
    String? packingRecipeId,
    double? freightCost,
    double? insuranceCost,
    double? clearanceCost,
    double? otherCosts,
    double? totalLandedCost,
    double? costPerCarton,
    double? exportPricePerCarton,
    String? currencyCode,
    double? exchangeRate,
    double? totalRevenueForeign,
    double? totalRevenueEgp,
    double? netProfitEgp,
    double? totalFruitCost,
    double? totalPackingMaterialCost,
    double? grossProfit,
    double? netProfit,
    double? discountAmount,
    String? discountReason,
    double? appliedDiscountAmount,
    DateTime? shipmentDate,
    DateTime? createdAt,
    bool? needsProfitRedistribution,
    double? paidAmount,
    double? allocatedAdminExpenses,
    String? paymentSourceType,
    String? paymentTreasuryId,
    int? paymentBankAccountId,
    bool? isConfirmed,
    int? returnJournalEntryId,
  }) {
    return ExportShipmentModel(
      id: id ?? this.id,
      shipmentNo: shipmentNo ?? this.shipmentNo,
      invoiceId: invoiceId ?? this.invoiceId,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerCode: customerCode ?? this.customerCode,
      clearingAgentId: clearingAgentId ?? this.clearingAgentId,
      clearingAgentName: clearingAgentName ?? this.clearingAgentName,
      contactPerson: contactPerson ?? this.contactPerson,
      country: country ?? this.country,
      countryOfOrigin: countryOfOrigin ?? this.countryOfOrigin,
      destinationAddress: destinationAddress ?? this.destinationAddress,
      containerNo: containerNo ?? this.containerNo,
      containerType: containerType ?? this.containerType,
      blNumber: blNumber ?? this.blNumber,
      vesselName: vesselName ?? this.vesselName,
      shippingCompany: shippingCompany ?? this.shippingCompany,
      dataLoggerNo: dataLoggerNo ?? this.dataLoggerNo,
      portOfLoading: portOfLoading ?? this.portOfLoading,
      portOfDestination: portOfDestination ?? this.portOfDestination,
      transportMode: transportMode ?? this.transportMode,
      palletsCount: palletsCount ?? this.palletsCount,
      cartonsCount: cartonsCount ?? this.cartonsCount,
      netWeight: netWeight ?? this.netWeight,
      grossWeight: grossWeight ?? this.grossWeight,
      incoterm: incoterm ?? this.incoterm,
      paymentTerms: paymentTerms ?? this.paymentTerms,
      currency: currency ?? this.currency,
      termsConditions: termsConditions ?? this.termsConditions,
      internalNotes: internalNotes ?? this.internalNotes,
      status: status ?? this.status,
      packingRecipeId: packingRecipeId ?? this.packingRecipeId,
      freightCost: freightCost ?? this.freightCost,
      insuranceCost: insuranceCost ?? this.insuranceCost,
      clearanceCost: clearanceCost ?? this.clearanceCost,
      otherCosts: otherCosts ?? this.otherCosts,
      totalLandedCost: totalLandedCost ?? this.totalLandedCost,
      costPerCarton: costPerCarton ?? this.costPerCarton,
      exportPricePerCarton: exportPricePerCarton ?? this.exportPricePerCarton,
      currencyCode: currencyCode ?? this.currencyCode,
      exchangeRate: exchangeRate ?? this.exchangeRate,
      totalRevenueForeign: totalRevenueForeign ?? this.totalRevenueForeign,
      totalRevenueEgp: totalRevenueEgp ?? this.totalRevenueEgp,
      netProfitEgp: netProfitEgp ?? this.netProfitEgp,
      totalFruitCost: totalFruitCost ?? this.totalFruitCost,
      totalPackingMaterialCost:
          totalPackingMaterialCost ?? this.totalPackingMaterialCost,
      grossProfit: grossProfit ?? this.grossProfit,
      netProfit: netProfit ?? this.netProfit,
      discountAmount: discountAmount ?? this.discountAmount,
      discountReason: discountReason ?? this.discountReason,
      appliedDiscountAmount: appliedDiscountAmount ?? this.appliedDiscountAmount,
      shipmentDate: shipmentDate ?? this.shipmentDate,
      createdAt: createdAt ?? this.createdAt,
      needsProfitRedistribution: needsProfitRedistribution ?? this.needsProfitRedistribution,
      paidAmount: paidAmount ?? this.paidAmount,
      allocatedAdminExpenses: allocatedAdminExpenses ?? this.allocatedAdminExpenses,
      paymentSourceType: paymentSourceType ?? this.paymentSourceType,
      paymentTreasuryId: paymentTreasuryId ?? this.paymentTreasuryId,
      paymentBankAccountId: paymentBankAccountId ?? this.paymentBankAccountId,
      isConfirmed: isConfirmed ?? this.isConfirmed,
      returnJournalEntryId: returnJournalEntryId ?? this.returnJournalEntryId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExportShipmentModel &&
          id != null &&
          other.id != null &&
          id == other.id;

  @override
  int get hashCode => id?.hashCode ?? 0;
}
