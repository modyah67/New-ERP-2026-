import '../../core/utils/inventory_identity.dart';

class StationProductBatch {
  final int? id;
  final int stationId;
  final String productName;
  final String productCode;
  final double quantity;
  final double remainingQuantity;
  final double unitCost;
  final String currency;
  final double exchangeRate;
  final String sourceType;
  final String sourceDate;
  final String supplierName;
  final String sourceStationName;
  final int? purchaseInvoiceId;
  final String? invoiceNumber;
  final String itemType;
  final String? rawMaterialId;
  final int? fruitTypeId;
  final String createdAt;

  const StationProductBatch({
    this.id,
    required this.stationId,
    required this.productName,
    this.productCode = '',
    required this.quantity,
    required this.remainingQuantity,
    this.unitCost = 0,
    this.currency = 'EGP',
    this.exchangeRate = 1.0,
    this.sourceType = 'purchase',
    this.sourceDate = '',
    this.supplierName = '',
    this.sourceStationName = '',
    this.purchaseInvoiceId,
    this.invoiceNumber,
    this.itemType = 'material',
    this.rawMaterialId,
    this.fruitTypeId,
    this.createdAt = '',
  });

  /// Canonical composite item key ensuring zero collision
  String get itemKey => InventoryIdentity.computeItemKey(
        itemType: itemType,
        rawMaterialId: rawMaterialId,
        fruitTypeId: fruitTypeId?.toString(),
        fallbackCode: productCode,
        fallbackName: productName,
      );

  double get batchTotalCost => remainingQuantity * unitCost;

  /// Base cost (EGP) of remaining quantity.
  double get batchTotalCostBase => remainingQuantity * unitCost * exchangeRate;

  /// Per-kg cost in original currency.
  double get costPerKg => quantity > 0 ? unitCost : 0;

  /// Per-kg cost in base currency (EGP).
  double get costPerKgBase => quantity > 0 ? unitCost * exchangeRate : 0;

  factory StationProductBatch.fromMap(Map<String, dynamic> map) {
    num? numVal(dynamic v) => v is num ? v : num.tryParse('$v');
    int? intVal(dynamic v) => v is int ? v : int.tryParse('$v');
    String? str(dynamic v) => v?.toString();

    final rawMatId = str(map['raw_material_id']);
    final fruitId = intVal(map['fruit_type_id']);
    final srcType = str(map['source_type']) ?? 'purchase';
    final pName = str(map['product_name']) ?? '';

    var detectedType = str(map['item_type']) ?? '';
    if (detectedType.isEmpty) {
      if ((fruitId != null && fruitId > 0) || srcType == 'lot_receipt' || srcType == 'crop_purchase') {
        detectedType = 'fruit';
      } else if ((rawMatId != null && rawMatId.isNotEmpty) || pName.contains('(مادة تعبئة)')) {
        detectedType = 'material';
      } else {
        detectedType = srcType == 'lot_receipt' ? 'fruit' : 'material';
      }
    }

    return StationProductBatch(
      id: intVal(map['id']),
      stationId: intVal(map['station_id']) ?? 0,
      productName: str(map['product_name']) ?? '',
      productCode: str(map['product_code']) ?? '',
      quantity: numVal(map['quantity'])?.toDouble() ?? 0.0,
      remainingQuantity: numVal(map['remaining_quantity'])?.toDouble() ?? 0.0,
      unitCost: numVal(map['unit_cost'])?.toDouble() ?? 0.0,
      currency: str(map['currency']) ?? 'EGP',
      exchangeRate: numVal(map['exchange_rate'])?.toDouble() ?? 1.0,
      sourceType: srcType,
      sourceDate: str(map['source_date']) ?? '',
      supplierName: str(map['supplier_name']) ?? '',
      sourceStationName: str(map['source_station_name']) ?? '',
      purchaseInvoiceId: intVal(map['purchase_invoice_id']),
      invoiceNumber: map['purchase_invoices'] is Map
          ? (map['purchase_invoices']['invoice_number']?.toString() ?? str(map['invoice_number']))
          : str(map['invoice_number']),
      itemType: detectedType,
      rawMaterialId: rawMatId,
      fruitTypeId: fruitId,
      createdAt: str(map['created_at']) ?? '',
    );
  }
}
