class StockDistributionEntry {
  final String supplierName;
  final String supplierCode;
  final double totalQuantity;
  final double totalCost;
  final double unitCost;

  const StockDistributionEntry({
    required this.supplierName,
    required this.supplierCode,
    required this.totalQuantity,
    required this.totalCost,
    required this.unitCost,
  });
}

class PurchaseBatch {
  final int id;
  final int productId;
  final String? productName;
  final String? productCode;
  final double originalQuantity;
  final double remainingQuantity;
  final double unitCost;
  final double totalCost;
  final String purchaseDate;
  final String? invoiceNumber;
  final String? supplierName;

  const PurchaseBatch({
    required this.id,
    required this.productId,
    this.productName,
    this.productCode,
    required this.originalQuantity,
    required this.remainingQuantity,
    required this.unitCost,
    required this.totalCost,
    required this.purchaseDate,
    this.invoiceNumber,
    this.supplierName,
  });

  double get batchTotalCost => remainingQuantity * unitCost;
}
