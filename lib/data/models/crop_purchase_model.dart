class CropPurchaseModel {
  final String? id;
  final String receiptNumber;
  final String supplierId;
  final String fruitTypeId;
  final String? warehouseId;
  final double quantity;
  final double purchasePricePerKg;
  final double totalCost;
  final double freightCost;
  final double commission;
  final double otherExpenses;
  final double netCost;
  final String purchaseDate;
  final String? lotReceiptId;
  final String? notes;

  // Joined fields
  final String? supplierName;
  final String? fruitTypeName;
  final String? warehouseName;

  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  CropPurchaseModel({
    this.id,
    required this.receiptNumber,
    required this.supplierId,
    required this.fruitTypeId,
    this.warehouseId,
    this.quantity = 0,
    this.purchasePricePerKg = 0,
    this.totalCost = 0,
    this.freightCost = 0,
    this.commission = 0,
    this.otherExpenses = 0,
    this.netCost = 0,
    required this.purchaseDate,
    this.lotReceiptId,
    this.notes,
    this.supplierName,
    this.fruitTypeName,
    this.warehouseName,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
  });

  factory CropPurchaseModel.fromMap(Map<String, dynamic> map) {
    double? n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');
    return CropPurchaseModel(
      id: map['id']?.toString(),
      receiptNumber: map['receipt_number']?.toString() ?? '',
      supplierId: map['supplier_id']?.toString() ?? '',
      fruitTypeId: map['fruit_type_id']?.toString() ?? '',
      warehouseId: map['warehouse_id']?.toString(),
      quantity: n(map['quantity']) ?? 0,
      purchasePricePerKg: n(map['purchase_price_per_kg']) ?? 0,
      totalCost: n(map['total_cost']) ?? 0,
      freightCost: n(map['freight_cost']) ?? 0,
      commission: n(map['commission']) ?? 0,
      otherExpenses: n(map['other_expenses']) ?? 0,
      netCost: n(map['net_cost']) ?? 0,
      purchaseDate: map['purchase_date']?.toString() ?? '',
      lotReceiptId: map['lot_receipt_id']?.toString(),
      notes: map['notes']?.toString(),
      supplierName: map['supplier_name']?.toString(),
      fruitTypeName: map['fruit_type_name']?.toString(),
      warehouseName: map['warehouse_name']?.toString(),
      createdBy: map['created_by']?.toString(),
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) : null,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'receipt_number': receiptNumber,
      'supplier_id': supplierId,
      'fruit_type_id': fruitTypeId,
      if (warehouseId != null) 'warehouse_id': warehouseId,
      'quantity': quantity,
      'purchase_price_per_kg': purchasePricePerKg,
      'total_cost': totalCost,
      'freight_cost': freightCost,
      'commission': commission,
      'other_expenses': otherExpenses,
      'net_cost': netCost,
      'purchase_date': purchaseDate,
      if (lotReceiptId != null) 'lot_receipt_id': lotReceiptId,
      if (notes != null) 'notes': notes,
    };
  }

  CropPurchaseModel copyWith({
    String? id,
    String? receiptNumber,
    String? supplierId,
    String? fruitTypeId,
    String? warehouseId,
    double? quantity,
    double? purchasePricePerKg,
    double? totalCost,
    double? freightCost,
    double? commission,
    double? otherExpenses,
    double? netCost,
    String? purchaseDate,
    String? lotReceiptId,
    String? notes,
    String? supplierName,
    String? fruitTypeName,
    String? warehouseName,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CropPurchaseModel(
      id: id ?? this.id,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      supplierId: supplierId ?? this.supplierId,
      fruitTypeId: fruitTypeId ?? this.fruitTypeId,
      warehouseId: warehouseId ?? this.warehouseId,
      quantity: quantity ?? this.quantity,
      purchasePricePerKg: purchasePricePerKg ?? this.purchasePricePerKg,
      totalCost: totalCost ?? this.totalCost,
      freightCost: freightCost ?? this.freightCost,
      commission: commission ?? this.commission,
      otherExpenses: otherExpenses ?? this.otherExpenses,
      netCost: netCost ?? this.netCost,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      lotReceiptId: lotReceiptId ?? this.lotReceiptId,
      notes: notes ?? this.notes,
      supplierName: supplierName ?? this.supplierName,
      fruitTypeName: fruitTypeName ?? this.fruitTypeName,
      warehouseName: warehouseName ?? this.warehouseName,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CropPurchaseModel && id != null && other.id != null && id == other.id;

  @override
  int get hashCode => id?.hashCode ?? 0;
}
