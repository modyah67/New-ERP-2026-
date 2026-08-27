// lib/data/models/invoice_model.dart
import 'package:flutter/material.dart';
import 'item_model.dart';

class InvoiceModel {
  final String? id;
  final int invoiceNumber;   // auto-incremented, NEVER reused
  final String invoiceDate;
  final String? customerId;
  final String? customerName; // joined
  final String? customerCode; // joined
  final double totalAmount;
  final double paidAmount;
  final double discountAmount;
  final String status;
  final String type;  // 'sale' or 'return'
  final String? notes;
  final String createdAt;
  final String? journalEntryId;

  // Items are loaded separately
  final List<InvoiceItemModel> items;

  InvoiceModel({
    this.id,
    required this.invoiceNumber,
    required this.invoiceDate,
    this.customerId,
    this.customerName,
    this.customerCode,
    this.totalAmount = 0.0,
    this.paidAmount = 0.0,
    this.discountAmount = 0.0,
    required this.status,
    this.type = 'sale',
    this.notes,
    required this.createdAt,
    this.journalEntryId,
    this.items = const [],
  });

  double get netAmount => totalAmount - discountAmount;
  double get remainingAmount => netAmount - paidAmount;

  factory InvoiceModel.fromMap(Map<String, dynamic> map) {
    String? str(dynamic v) => v?.toString();
    int? intVal(dynamic v) => v is int ? v : int.tryParse('$v');
    num? numVal(dynamic v) => v is num ? v : num.tryParse('$v');

    return InvoiceModel(
      id: str(map['id']),
      invoiceNumber: intVal(map['invoice_number']) ?? 0,
      invoiceDate: str(map['invoice_date']) ?? '',
      customerId: str(map['customer_id']),
      customerName: str(map['customer_name']),
      customerCode: str(map['customer_code']),
      totalAmount: numVal(map['total_amount'])?.toDouble() ?? 0.0,
      paidAmount: numVal(map['paid_amount'])?.toDouble() ?? 0.0,
      discountAmount: numVal(map['discount_amount'])?.toDouble() ?? 0.0,
      status: str(map['status']) ?? '',
      type: str(map['sale_type']) ?? 'sale',
      notes: str(map['notes']),
      createdAt: str(map['created_at']) ?? '',
      journalEntryId: str(map['journal_entry_id']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'invoice_number': invoiceNumber,
      'invoice_date': invoiceDate,
      'customer_id': customerId,
      'total_amount': totalAmount,
      'paid_amount': paidAmount,
      'discount_amount': discountAmount,
      'status': status,
      'sale_type': type,
      'notes': notes,
      'created_at': createdAt,
    };
  }

  InvoiceModel copyWith({
    String? id, int? invoiceNumber, String? invoiceDate,
    String? customerId, String? customerName, String? customerCode,
    double? totalAmount, double? paidAmount, double? discountAmount,
    String? status, String? type, String? notes, String? createdAt,
    String? journalEntryId,
    List<InvoiceItemModel>? items,
  }) {
    return InvoiceModel(
      id: id ?? this.id,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerCode: customerCode ?? this.customerCode,
      totalAmount: totalAmount ?? this.totalAmount,
      paidAmount: paidAmount ?? this.paidAmount,
      discountAmount: discountAmount ?? this.discountAmount,
      status: status ?? this.status,
      type: type ?? this.type,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      journalEntryId: journalEntryId ?? this.journalEntryId,
      items: items ?? this.items,
    );
  }
}

// ── Invoice Line Item ─────────────────────────
class InvoiceItemModel {
  final String? id;
  final String invoiceId;
  final String? itemId;
  final String? itemName;   // joined
  final String? itemCode;   // joined
  final double quantity;    // meters or pieces
  final double unitPrice;
  final double totalPrice;  // quantity × unitPrice
  final double costPrice;   // cost at time of sale
  final String unit;
  final double piecesCount;

  InvoiceItemModel({
    this.id,
    required this.invoiceId,
    this.itemId,
    this.itemName,
    this.itemCode,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    this.costPrice = 0.0,
    required this.unit,
    this.piecesCount = 0.0,
  });

  factory InvoiceItemModel.fromMap(Map<String, dynamic> map) {
    String? str(dynamic v) => v?.toString();
    int? intVal(dynamic v) => v is int ? v : int.tryParse('$v');
    num? numVal(dynamic v) => v is num ? v : num.tryParse('$v');

    return InvoiceItemModel(
      id: str(map['id']),
      invoiceId: str(map['invoice_id']) ?? '',
      itemId: str(map['item_id']),
      itemName: str(map['item_name']),
      itemCode: str(map['item_code']),
      quantity: numVal(map['quantity'])?.toDouble() ?? 0.0,
      unitPrice: numVal(map['unit_price'])?.toDouble() ?? 0.0,
      totalPrice: numVal(map['total_price'])?.toDouble() ?? 0.0,
      costPrice: numVal(map['cost_price'])?.toDouble() ?? 0.0,
      unit: str(map['unit']) ?? '',
      piecesCount: numVal(map['pieces_count'])?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'invoice_id': invoiceId,
      'item_id': itemId,
      'quantity': quantity,
      'unit_price': unitPrice,
      'cost_price': costPrice,
      'unit': unit,
      'pieces_count': piecesCount,
    };
  }
}

enum DiscountMode { none, percentage, fixed }

class InvoiceLine {
  final TextEditingController quantityController;
  final TextEditingController priceController;
  final TextEditingController piecesController;
  final TextEditingController itemSearchController;
  final FocusNode quantityFocus;
  final FocusNode priceFocus;
  final FocusNode piecesFocus;
  final FocusNode itemFocus;
  final FocusNode keyboardFocus;
  ItemModel? selectedItem;
  double quantity;
  double unitPrice;
  double totalPrice;
  String unit;

  InvoiceLine({
    TextEditingController? quantityController,
    TextEditingController? priceController,
    TextEditingController? piecesController,
    TextEditingController? itemSearchController,
    FocusNode? quantityFocus,
    FocusNode? priceFocus,
    FocusNode? piecesFocus,
    FocusNode? itemFocus,
    FocusNode? keyboardFocus,
    this.selectedItem,
    this.quantity = 0,
    this.unitPrice = 0,
    this.totalPrice = 0,
    this.unit = 'متر',
  })  : quantityController = quantityController ?? TextEditingController(),
        priceController = priceController ?? TextEditingController(),
        piecesController = piecesController ?? TextEditingController(),
        itemSearchController = itemSearchController ?? TextEditingController(),
        quantityFocus = quantityFocus ?? FocusNode(),
        priceFocus = priceFocus ?? FocusNode(),
        piecesFocus = piecesFocus ?? FocusNode(),
        itemFocus = itemFocus ?? FocusNode(),
        keyboardFocus = keyboardFocus ?? FocusNode();

  void dispose() {
    quantityController.dispose();
    priceController.dispose();
    piecesController.dispose();
    itemSearchController.dispose();
    quantityFocus.dispose();
    priceFocus.dispose();
    piecesFocus.dispose();
    itemFocus.dispose();
    keyboardFocus.dispose();
  }

  void recalculateTotal() {
    totalPrice = quantity * unitPrice;
  }
}