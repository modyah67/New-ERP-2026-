class ProformaInvoiceItem {
  final String? id;
  final String? proformaInvoiceId;
  final String productName;
  final double quantity;
  final double pricePerCarton;
  final double netWeight;
  final double grossWeight;
  final int palletsCount;
  final double totalAmount;

  ProformaInvoiceItem({
    this.id,
    this.proformaInvoiceId,
    required this.productName,
    this.quantity = 0,
    this.pricePerCarton = 0,
    this.netWeight = 0,
    this.grossWeight = 0,
    this.palletsCount = 0,
    this.totalAmount = 0,
  });

  double get computedTotal => quantity * pricePerCarton;

  factory ProformaInvoiceItem.fromMap(Map<String, dynamic> map) {
    return ProformaInvoiceItem(
      id: map['id']?.toString(),
      proformaInvoiceId: map['proforma_invoice_id']?.toString(),
      productName: (map['product_name'] ?? '').toString(),
      quantity: _parseDouble(map['quantity']) ?? 0,
      pricePerCarton: _parseDouble(map['price_per_carton']) ?? 0,
      netWeight: _parseDouble(map['net_weight']) ?? 0,
      grossWeight: _parseDouble(map['gross_weight']) ?? 0,
      palletsCount: _parseInt(map['pallets_count']) ?? 0,
      totalAmount: _parseDouble(map['total_amount']) ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (proformaInvoiceId != null) 'proforma_invoice_id': proformaInvoiceId,
      'product_name': productName,
      'quantity': quantity,
      'price_per_carton': pricePerCarton,
      'net_weight': netWeight,
      'gross_weight': grossWeight,
      'pallets_count': palletsCount,
      'total_amount': computedTotal,
    };
  }

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  ProformaInvoiceItem copyWith({
    String? id,
    String? proformaInvoiceId,
    String? productName,
    double? quantity,
    double? pricePerCarton,
    double? netWeight,
    double? grossWeight,
    int? palletsCount,
  }) {
    return ProformaInvoiceItem(
      id: id ?? this.id,
      proformaInvoiceId: proformaInvoiceId ?? this.proformaInvoiceId,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      pricePerCarton: pricePerCarton ?? this.pricePerCarton,
      netWeight: netWeight ?? this.netWeight,
      grossWeight: grossWeight ?? this.grossWeight,
      palletsCount: palletsCount ?? this.palletsCount,
    );
  }
}

class ProformaInvoiceModel {
  final String? id;
  final String invoiceNo;
  final String? customerId;
  final String? customerName;
  final String? customerCode;
  final String? clearingAgentId;
  final String? clearingAgentName;
  final String? contactPerson;
  final String? country;
  final String? destinationAddress;
  final String? containerNo;
  final String? containerType;
  final String? blNumber;
  final String? vesselName;
  final String? dataLoggerNo;
  final String? portOfLoading;
  final String? portOfDestination;
  final String transportMode;
  final String? currency;
  final String? paymentTerms;
  final String? termsConditions;
  final String? internalNotes;
  final String status;
  final double totalAmount;
  final DateTime? invoiceDate;
  final DateTime? createdAt;

  const ProformaInvoiceModel({
    this.id,
    required this.invoiceNo,
    this.customerId,
    this.customerName,
    this.customerCode,
    this.clearingAgentId,
    this.clearingAgentName,
    this.contactPerson,
    this.country,
    this.destinationAddress,
    this.containerNo,
    this.containerType,
    this.blNumber,
    this.vesselName,
    this.dataLoggerNo,
    this.portOfLoading,
    this.portOfDestination,
    this.transportMode = 'sea',
    this.currency,
    this.paymentTerms,
    this.termsConditions,
    this.internalNotes,
    this.status = 'draft',
    this.totalAmount = 0,
    this.invoiceDate,
    this.createdAt,
  });

  factory ProformaInvoiceModel.fromMap(Map<String, dynamic> map) {
    return ProformaInvoiceModel(
      id: map['id']?.toString(),
      invoiceNo: (map['invoice_no'] ?? '').toString(),
      customerId: map['customer_id']?.toString(),
      customerName: (map['customer_name'] ?? '').toString(),
      customerCode: (map['customer_code'] ?? '').toString(),
      clearingAgentId: map['clearing_agent_id']?.toString(),
      clearingAgentName: (map['clearing_agent_name'] ?? '').toString(),
      contactPerson: map['contact_person']?.toString(),
      country: (map['country'] ?? '').toString(),
      destinationAddress: map['destination_address']?.toString(),
      containerNo: map['container_no']?.toString(),
      containerType: map['container_type']?.toString(),
      blNumber: map['bl_number']?.toString(),
      vesselName: map['vessel_name']?.toString(),
      dataLoggerNo: map['data_logger_no']?.toString(),
      portOfLoading: map['port_of_loading']?.toString(),
      portOfDestination: map['port_of_destination']?.toString(),
      transportMode: (map['transport_mode'] ?? 'sea').toString(),
      currency: map['currency']?.toString(),
      paymentTerms: map['payment_terms']?.toString(),
      termsConditions: map['terms_conditions']?.toString(),
      internalNotes: map['internal_notes']?.toString(),
      status: (map['status'] ?? 'draft').toString(),
      totalAmount: _parseDouble(map['total_amount']) ?? 0,
      invoiceDate: _parseDate(map['invoice_date']),
      createdAt: _parseDate(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'invoice_no': invoiceNo,
      if (customerId != null) 'customer_id': customerId,
      'customer_name': customerName ?? '',
      'customer_code': customerCode ?? '',
      if (clearingAgentId != null) 'clearing_agent_id': clearingAgentId,
      'clearing_agent_name': clearingAgentName ?? '',
      if (contactPerson != null) 'contact_person': contactPerson,
      'country': country ?? '',
      if (destinationAddress != null) 'destination_address': destinationAddress,
      if (containerNo != null) 'container_no': containerNo,
      if (containerType != null) 'container_type': containerType,
      if (blNumber != null) 'bl_number': blNumber,
      if (vesselName != null) 'vessel_name': vesselName,
      if (dataLoggerNo != null) 'data_logger_no': dataLoggerNo,
      if (portOfLoading != null) 'port_of_loading': portOfLoading,
      if (portOfDestination != null) 'port_of_destination': portOfDestination,
      'transport_mode': transportMode,
      if (currency != null) 'currency': currency,
      if (paymentTerms != null) 'payment_terms': paymentTerms,
      if (termsConditions != null) 'terms_conditions': termsConditions,
      if (internalNotes != null) 'internal_notes': internalNotes,
      'status': status,
      'total_amount': totalAmount,
      if (invoiceDate != null) 'invoice_date': _formatDate(invoiceDate!),
    };
  }

  static String _formatDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

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

  ProformaInvoiceModel copyWith({
    String? id,
    String? invoiceNo,
    String? customerId,
    String? customerName,
    String? customerCode,
    String? clearingAgentId,
    String? clearingAgentName,
    String? contactPerson,
    String? country,
    String? destinationAddress,
    String? containerNo,
    String? containerType,
    String? blNumber,
    String? vesselName,
    String? dataLoggerNo,
    String? portOfLoading,
    String? portOfDestination,
    String? transportMode,
    String? currency,
    String? paymentTerms,
    String? termsConditions,
    String? internalNotes,
    String? status,
    double? totalAmount,
    DateTime? invoiceDate,
  }) {
    return ProformaInvoiceModel(
      id: id ?? this.id,
      invoiceNo: invoiceNo ?? this.invoiceNo,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerCode: customerCode ?? this.customerCode,
      clearingAgentId: clearingAgentId ?? this.clearingAgentId,
      clearingAgentName: clearingAgentName ?? this.clearingAgentName,
      contactPerson: contactPerson ?? this.contactPerson,
      country: country ?? this.country,
      destinationAddress: destinationAddress ?? this.destinationAddress,
      containerNo: containerNo ?? this.containerNo,
      containerType: containerType ?? this.containerType,
      blNumber: blNumber ?? this.blNumber,
      vesselName: vesselName ?? this.vesselName,
      dataLoggerNo: dataLoggerNo ?? this.dataLoggerNo,
      portOfLoading: portOfLoading ?? this.portOfLoading,
      portOfDestination: portOfDestination ?? this.portOfDestination,
      transportMode: transportMode ?? this.transportMode,
      currency: currency ?? this.currency,
      paymentTerms: paymentTerms ?? this.paymentTerms,
      termsConditions: termsConditions ?? this.termsConditions,
      internalNotes: internalNotes ?? this.internalNotes,
      status: status ?? this.status,
      totalAmount: totalAmount ?? this.totalAmount,
      invoiceDate: invoiceDate ?? this.invoiceDate,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProformaInvoiceModel &&
          id != null &&
          other.id != null &&
          id == other.id;

  @override
  int get hashCode => id?.hashCode ?? 0;
}
