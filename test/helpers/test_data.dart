Map<String, dynamic> samplePurchaseInvoice({
  int id = 1,
  String status = 'pending',
  double total = 15000.0,
  int? supplierId = 1,
}) => {
  'id': id,
  'invoice_number': 'PO-2026-0001',
  'supplier_id': supplierId,
  'invoice_date': '2026-06-15',
  'total_amount': total,
  'status': status,
  'created_by': 'test-user-id',
  'created_at': '2026-06-15T10:00:00Z',
  'updated_at': '2026-06-15T10:00:00Z',
};

Map<String, dynamic> samplePurchaseItem({
  int id = 1,
  int invoiceId = 1,
  int productId = 1,
  double quantity = 1000.0,
  double unitPrice = 15.0,
}) => {
  'id': id,
  'purchase_invoice_id': invoiceId,
  'product_id': productId,
  'quantity': quantity,
  'unit_price': unitPrice,
};

Map<String, dynamic> sampleProduct({int id = 1, String name = 'برتقال', String? category}) => {
  'id': id,
  'name': name,
  'category': category ?? 'فاكهة',
  'unit': 'kg',
};

Map<String, dynamic> sampleSupplier({int id = 1, String name = 'مورد تجريبي'}) => {
  'id': id,
  'name': name,
  'phone': '0123456789',
};

Map<String, dynamic> sampleLot({
  int id = 1,
  int purchaseInvoiceId = 1,
  int productId = 1,
  double quantity = 1000.0,
  String status = 'received',
}) => {
  'id': id,
  'lot_number': 'LOT-2026-0001',
  'purchase_invoice_id': purchaseInvoiceId,
  'product_id': productId,
  'received_quantity': quantity,
  'remaining_quantity': quantity,
  'status': status,
  'created_at': '2026-06-15T10:00:00Z',
};

Map<String, dynamic> sampleStockBatch({
  int id = 1,
  int? lotId = 1,
  String batchNumber = 'B-20260615-001',
  int productId = 1,
  double quantity = 500.0,
  String status = 'active',
  double costPerKg = 15.0,
}) => {
  'id': id,
  'lot_id': lotId,
  'batch_number': batchNumber,
  'product_id': productId,
  'quantity': quantity,
  'unit_cost': costPerKg,
  'status': status,
  'created_at': '2026-06-15T10:00:00Z',
};

Map<String, dynamic> sampleGradingResult({
  int id = 1,
  int lotId = 1,
  int stockBatchId = 1,
  String grade = 'A',
  double quantity = 400.0,
  double? costPerKg,
}) => {
  'id': id,
  'lot_id': lotId,
  'stock_batch_id': stockBatchId,
  'grade': grade,
  'quantity': quantity,
  'cost_per_kg': costPerKg,
  'created_at': '2026-06-15T10:00:00Z',
};

Map<String, dynamic> samplePackingOrder({
  int id = 1,
  int? lotId = 1,
  String status = 'confirmed',
  int? productId = 1,
  double quantity = 300.0,
}) => {
  'id': id,
  'lot_id': lotId,
  'product_id': productId,
  'packing_date': '2026-06-16',
  'total_quantity': quantity,
  'status': status,
  'created_at': '2026-06-16T10:00:00Z',
};

Map<String, dynamic> samplePackingRecipe({
  int id = 1,
  int packingOrderId = 1,
  int productId = 1,
  double quantity = 300.0,
  String materialType = 'fruit',
}) => {
  'id': id,
  'packing_order_id': packingOrderId,
  'product_id': productId,
  'quantity': quantity,
  'unit_cost': 15.0,
  'material_type': materialType,
};

Map<String, dynamic> sampleExportShipment({
  int id = 1,
  int? packingOrderId = 1,
  String status = 'pending',
  double totalCost = 4500.0,
  double totalRevenue = 9000.0,
  bool cogsPosted = false,
}) => {
  'id': id,
  'shipment_number': 'SHP-2026-0001',
  'packing_order_id': packingOrderId,
  'status': status,
  'total_quantity': 300,
  'total_cost': totalCost,
  'total_revenue': totalRevenue,
  'cogs_posted': cogsPosted,
  'created_at': '2026-06-17T10:00:00Z',
};

Map<String, dynamic> sampleShipmentBreakdown({
  int id = 1,
  int shipmentId = 1,
  String category = 'fruit',
  double amount = 3000.0,
}) => {
  'id': id,
  'export_shipment_id': shipmentId,
  'category': category,
  'amount': amount,
  'description': 'تكلفة الفاكهة',
};

Map<String, dynamic> sampleTransaction({
  int id = 1,
  String type = 'debit',
  double amount = 4500.0,
  int accountId = 6,
  String? referenceType,
  int? referenceId,
}) => {
  'id': id,
  'account_id': accountId,
  'transaction_date': '2026-06-17',
  'type': type,
  'amount': amount,
  'description': 'COGS for shipment',
  'reference_type': referenceType,
  'reference_id': referenceId,
  'created_by': 'test-user-id',
};

Map<String, dynamic> sampleAccount({
  int id = 1,
  String code = '1000',
  String name = 'نقدي',
  String type = 'asset',
}) => {
  'id': id,
  'code': code,
  'name': name,
  'type': type,
};

Map<String, dynamic> sampleNotification({
  int id = 1,
  String type = 'approval',
  String severity = 'info',
  String title = 'موافقة مطلوبة',
  bool isRead = false,
}) => {
  'id': id,
  'user_id': 'test-user-id',
  'type': type,
  'severity': severity,
  'title': title,
  'message': 'فاتورة شراء رقم PO-2026-0001 تحتاج موافقتك',
  'is_read': isRead,
  'created_at': '2026-06-17T10:00:00Z',
};

Map<String, dynamic> sampleApprovalHistory({
  int id = 1,
  String entityType = 'purchase_invoice',
  int entityId = 1,
  String status = 'pending',
  String action = 'submit',
}) => {
  'id': id,
  'entity_type': entityType,
  'entity_id': entityId,
  'from_status': 'draft',
  'to_status': status,
  'action': action,
  'performed_by': 'test-user-id',
  'created_at': '2026-06-17T10:00:00Z',
};

Map<String, dynamic> sampleTreasury({
  int id = 1,
  String type = 'cash',
  double balance = 50000.0,
}) => {
  'id': id,
  'name': 'الخزينة الرئيسية',
  'type': type,
  'balance': balance,
  'created_at': '2026-06-01T10:00:00Z',
};

Map<String, dynamic> sampleInventoryValuation({
  int productId = 1,
  String productName = 'برتقال',
  double totalQuantity = 500.0,
  double totalValue = 7500.0,
  double avgCost = 15.0,
}) => {
  'product_id': productId,
  'product_name': productName,
  'total_quantity': totalQuantity,
  'total_value': totalValue,
  'average_cost': avgCost,
};
