enum MovementType {
  purchase('مشتريات'),
  lotReceipt('شراء محصول'),
  packing('تعبئة'),
  materialTransfer('مواد تعبئة'),
  transferIn('تحويل وارد'),
  transferOut('تحويل صادر'),
  lotReturn('مرتجع محصول');

  final String label;
  const MovementType(this.label);
}

class WarehouseMovementModel {
  final int? id;
  final MovementType type;
  final String referenceNumber;
  final DateTime? date;
  final DateTime? createdAt;
  final String? productName;
  final double? quantity;
  final String? supplierName;
  final String? details;
  final Map<String, dynamic>? extraData;
  final String? unit;

  const WarehouseMovementModel({
    this.id,
    required this.type,
    required this.referenceNumber,
    this.date,
    this.createdAt,
    this.productName,
    this.quantity,
    this.supplierName,
    this.details,
    this.extraData,
    this.unit,
  });
}
