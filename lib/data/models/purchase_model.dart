// lib/data/models/purchase_model.dart

import '../../core/utils.dart';

class PurchaseLineData {
  String code;
  String name;
  double quantity;
  double purchasePrice;
  String unit;
  String? existingItemId;
  String? stationId;
  double exchangeRate;

  PurchaseLineData({
    this.code = '',
    this.name = '',
    this.quantity = 0,
    this.purchasePrice = 0,
    this.unit = 'متر',
    this.existingItemId,
    this.stationId,
    this.exchangeRate = 1.0,
  });

  double get totalPrice => AppUtils.roundDouble(quantity * purchasePrice);
  double get totalPriceEgp => AppUtils.roundDouble(totalPrice * exchangeRate);
}

class PurchaseItemModel {
  final String? id;
  final String purchaseId;
  final String? itemId;
  final String itemCode;
  final String itemName;
  final double quantity;
  final double purchasePrice;
  final double sellingPrice;
  final double totalPrice;
  final String unit;
  final double piecesCount;
  final int? stationId;
  final double exchangeRate;

  const PurchaseItemModel({
    this.id,
    required this.purchaseId,
    this.itemId,
    required this.itemCode,
    required this.itemName,
    required this.quantity,
    required this.purchasePrice,
    required this.sellingPrice,
    required this.totalPrice,
    this.unit = 'متر',
    this.piecesCount = 0.0,
    this.stationId,
    this.exchangeRate = 1.0,
  });

  factory PurchaseItemModel.fromMap(Map<String, dynamic> map) {
    return PurchaseItemModel(
      id: map['id']?.toString(),
      purchaseId: map['purchase_id']?.toString() ?? '',
      itemId: map['item_id']?.toString(),
      itemCode: (map['item_code'] ?? map['product_sku'] ?? '') as String,
      itemName: (map['item_name'] ?? map['product_name'] ?? '') as String,
      quantity: (map['quantity'] as num).toDouble(),
      purchasePrice: (map['purchase_price'] ?? map['unit_cost'] ?? 0.0 as num).toDouble(),
      sellingPrice: (map['selling_price'] ?? 0.0 as num).toDouble(),
      totalPrice: (map['total_price'] ?? map['total_cost'] ?? 0.0 as num).toDouble(),
      unit: map['unit'] as String? ?? 'كجم',
      piecesCount: (map['pieces_count'] as num?)?.toDouble() ?? 0.0,
      stationId: map['station_id'] is int ? map['station_id'] as int : int.tryParse(map['station_id']?.toString() ?? ''),
      exchangeRate: (map['exchange_rate'] as num?)?.toDouble() ?? 1.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'purchase_id': purchaseId,
      'item_id': itemId,
      'item_code': itemCode,
      'item_name': itemName,
      'quantity': quantity,
      'purchase_price': purchasePrice,
      'selling_price': sellingPrice,
      'unit': unit,
      'pieces_count': piecesCount,
      if (stationId != null) 'station_id': stationId,
      'exchange_rate': exchangeRate,
    };
  }

  PurchaseItemModel copyWith({String? purchaseId, int? stationId}) {
    return PurchaseItemModel(
      id: id,
      purchaseId: purchaseId ?? this.purchaseId,
      itemId: itemId,
      itemCode: itemCode,
      itemName: itemName,
      quantity: quantity,
      purchasePrice: purchasePrice,
      sellingPrice: sellingPrice,
      totalPrice: totalPrice,
      unit: unit,
      piecesCount: piecesCount,
      stationId: stationId ?? this.stationId,
      exchangeRate: exchangeRate,
    );
  }
}

class PurchaseModel {
  final String? id;
  final String purchaseNumber;
  final String purchaseDate;
  final String? supplierId;
  final String? supplierName; // joined
  final String? supplierCode; // joined
  final double totalAmount;
  final double paidAmount;
  final double discountAmount;
  final String status;
  final String? notes;
  final String currency;
  final String createdAt;
  final String? paymentTreasuryId;
  final String? paymentSourceType;
  final int? paymentBankAccountId;
  final String? journalEntryId;
  final List<PurchaseItemModel> items;

  const PurchaseModel({
    this.id,
    required this.purchaseNumber,
    required this.purchaseDate,
    this.supplierId,
    this.supplierName,
    this.supplierCode,
    this.totalAmount = 0.0,
    this.paidAmount = 0.0,
    this.discountAmount = 0.0,
    this.status = 'draft',
    this.notes,
    this.currency = 'EGP',
    required this.createdAt,
    this.paymentTreasuryId,
    this.paymentSourceType,
    this.paymentBankAccountId,
    this.journalEntryId,
    this.items = const [],
  });

  double get netAmount => totalAmount - discountAmount;
  double get remainingAmount => netAmount - paidAmount;

  factory PurchaseModel.fromMap(Map<String, dynamic> map) {
    final invoiceCurrency = map['currency']?.toString();
    String? supplierCurrency;
    final suppliersRaw = map['suppliers'];
    if (suppliersRaw is Map<String, dynamic>) {
      supplierCurrency = suppliersRaw['currency']?.toString();
    } else if (suppliersRaw is List && suppliersRaw.isNotEmpty) {
      supplierCurrency = (suppliersRaw.first as Map<String, dynamic>?)?['currency']?.toString();
    }
    return PurchaseModel(
      id: map['id']?.toString(),
      purchaseNumber: map['purchase_number'] as String,
      purchaseDate: map['purchase_date'] as String,
      supplierId: map['supplier_id']?.toString(),
      supplierName: map['supplier_name'] as String?,
      supplierCode: map['supplier_code'] as String?,
      totalAmount: (map['total_amount'] as num).toDouble(),
      paidAmount: (map['paid_amount'] as num).toDouble(),
      discountAmount: (map['discount_amount'] as num?)?.toDouble() ?? 0.0,
      status: map['status'] as String? ?? 'draft',
      notes: map['notes'] as String?,
      currency: (invoiceCurrency != null && invoiceCurrency.isNotEmpty && invoiceCurrency != 'EGP')
          ? invoiceCurrency
          : (supplierCurrency ?? 'EGP'),
      createdAt: map['created_at'] as String,
      paymentTreasuryId: map['payment_treasury_id']?.toString(),
      paymentSourceType: map['payment_source_type']?.toString(),
      paymentBankAccountId: map['payment_bank_account_id'] is int
          ? map['payment_bank_account_id']
          : int.tryParse(map['payment_bank_account_id']?.toString() ?? ''),
      journalEntryId: map['journal_entry_id']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'purchase_number': purchaseNumber,
      'purchase_date': purchaseDate,
      'supplier_id': supplierId,
      'total_amount': totalAmount,
      'paid_amount': paidAmount,
      'discount_amount': discountAmount,
      'status': status,
      'notes': notes,
      'created_at': createdAt,
    };
  }

  PurchaseModel copyWith({List<PurchaseItemModel>? items, String? id, String? currency}) {
    return PurchaseModel(
      id: id ?? this.id,
      purchaseNumber: purchaseNumber,
      purchaseDate: purchaseDate,
      supplierId: supplierId,
      supplierName: supplierName,
      supplierCode: supplierCode ?? this.supplierCode,
      totalAmount: totalAmount,
      paidAmount: paidAmount,
      discountAmount: discountAmount,
      status: status,
      notes: notes,
      currency: currency ?? this.currency,
      createdAt: createdAt,
      paymentTreasuryId: paymentTreasuryId,
      paymentSourceType: paymentSourceType,
      paymentBankAccountId: paymentBankAccountId,
      journalEntryId: journalEntryId,
      items: items ?? this.items,
    );
  }
}
