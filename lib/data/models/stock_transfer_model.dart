class StockTransferModel {
  final int? id;
  final int fromStationId;
  final int toStationId;
  final String productCode;
  final String productName;
  final double quantity;
  final String? notes;
  final String transferredBy;
  final String createdAt;

  const StockTransferModel({
    this.id,
    required this.fromStationId,
    required this.toStationId,
    required this.productCode,
    required this.productName,
    required this.quantity,
    this.notes,
    required this.transferredBy,
    required this.createdAt,
  });

  factory StockTransferModel.fromMap(Map<String, dynamic> map) {
    String? str(dynamic v) => v?.toString();
    int? intVal(dynamic v) => v is int ? v : int.tryParse('$v');
    num? numVal(dynamic v) => v is num ? v : num.tryParse('$v');

    return StockTransferModel(
      id: intVal(map['id']),
      fromStationId: intVal(map['from_station_id']) ?? 0,
      toStationId: intVal(map['to_station_id']) ?? 0,
      productCode: str(map['product_code']) ?? '',
      productName: str(map['product_name']) ?? '',
      quantity: numVal(map['quantity'])?.toDouble() ?? 0.0,
      notes: str(map['notes']),
      transferredBy: str(map['transferred_by']) ?? '',
      createdAt: str(map['created_at']) ?? '',
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'from_station_id': fromStationId,
      'to_station_id': toStationId,
      'product_code': productCode,
      'product_name': productName,
      'quantity': quantity,
      'notes': notes,
      'transferred_by': transferredBy,
      'created_at': createdAt,
    };
  }

  StockTransferModel copyWith({
    int? id,
    int? fromStationId,
    int? toStationId,
    String? productCode,
    String? productName,
    double? quantity,
    String? notes,
    String? transferredBy,
    String? createdAt,
  }) {
    return StockTransferModel(
      id: id ?? this.id,
      fromStationId: fromStationId ?? this.fromStationId,
      toStationId: toStationId ?? this.toStationId,
      productCode: productCode ?? this.productCode,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      notes: notes ?? this.notes,
      transferredBy: transferredBy ?? this.transferredBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StockTransferModel && id != null && other.id != null && id == other.id;

  @override
  int get hashCode => id?.hashCode ?? 0;
}