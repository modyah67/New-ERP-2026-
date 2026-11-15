import 'dart:convert';

class ExportShipmentReturnModel {
  final int? id;
  final String returnNumber;
  final int shipmentId;
  final int? stationId;
  final DateTime returnDate;
  final String? costCenterId;
  final int totalCartons;
  final int intactCartons;
  final int damagedCartons;
  final double totalCropWeight;
  final double intactCropWeight;
  final double damagedCropWeight;
  final double cropWasteCost;
  final double materialWasteCost;
  final double extraExpensesCost;
  final double reversedRevenueAmount;
  final double reversedRevenueEgp;
  final double reversedCustomerAmount;
  final double reversedCustomerEgp;
  final String currency;
  final double exchangeRate;
  final String? returnReason;
  final String? notes;
  final Map<String, dynamic>? rawData;
  final int? journalEntryId;
  final DateTime? createdAt;

  const ExportShipmentReturnModel({
    this.id,
    required this.returnNumber,
    required this.shipmentId,
    this.stationId,
    required this.returnDate,
    this.costCenterId,
    this.totalCartons = 0,
    this.intactCartons = 0,
    this.damagedCartons = 0,
    this.totalCropWeight = 0.0,
    this.intactCropWeight = 0.0,
    this.damagedCropWeight = 0.0,
    this.cropWasteCost = 0.0,
    this.materialWasteCost = 0.0,
    this.extraExpensesCost = 0.0,
    this.reversedRevenueAmount = 0.0,
    this.reversedRevenueEgp = 0.0,
    this.reversedCustomerAmount = 0.0,
    this.reversedCustomerEgp = 0.0,
    this.currency = 'USD',
    this.exchangeRate = 1.0,
    this.returnReason,
    this.notes,
    this.rawData,
    this.journalEntryId,
    this.createdAt,
  });

  factory ExportShipmentReturnModel.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic>? rawMap;
    if (map['raw_data'] != null) {
      if (map['raw_data'] is Map) {
        rawMap = Map<String, dynamic>.from(map['raw_data']);
      } else if (map['raw_data'] is String) {
        try {
          rawMap = jsonDecode(map['raw_data']);
        } catch (_) {}
      }
    }

    num? numVal(dynamic v) => v is num ? v : num.tryParse('$v');
    int? intVal(dynamic v) => v is int ? v : int.tryParse('$v');

    return ExportShipmentReturnModel(
      id: intVal(map['id']),
      returnNumber: map['return_number']?.toString() ?? '',
      shipmentId: intVal(map['shipment_id']) ?? 0,
      stationId: intVal(map['station_id']),
      returnDate: map['return_date'] != null
          ? DateTime.tryParse(map['return_date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      costCenterId: map['cost_center_id']?.toString(),
      totalCartons: intVal(map['total_cartons']) ?? 0,
      intactCartons: intVal(map['intact_cartons']) ?? 0,
      damagedCartons: intVal(map['damaged_cartons']) ?? 0,
      totalCropWeight: numVal(map['total_crop_weight'])?.toDouble() ?? 0.0,
      intactCropWeight: numVal(map['intact_crop_weight'])?.toDouble() ?? 0.0,
      damagedCropWeight: numVal(map['damaged_crop_weight'])?.toDouble() ?? 0.0,
      cropWasteCost: numVal(map['crop_waste_cost'])?.toDouble() ?? 0.0,
      materialWasteCost: numVal(map['material_waste_cost'])?.toDouble() ?? 0.0,
      extraExpensesCost: numVal(map['extra_expenses_cost'])?.toDouble() ?? 0.0,
      reversedRevenueAmount: numVal(map['reversed_revenue_amount'])?.toDouble() ?? 0.0,
      reversedRevenueEgp: numVal(map['reversed_revenue_egp'])?.toDouble() ?? 0.0,
      reversedCustomerAmount: numVal(map['reversed_customer_amount'])?.toDouble() ?? 0.0,
      reversedCustomerEgp: numVal(map['reversed_customer_egp'])?.toDouble() ?? 0.0,
      currency: map['currency']?.toString() ?? 'USD',
      exchangeRate: numVal(map['exchange_rate'])?.toDouble() ?? 1.0,
      returnReason: map['return_reason']?.toString(),
      notes: map['notes']?.toString(),
      rawData: rawMap,
      journalEntryId: intVal(map['journal_entry_id']),
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'return_number': returnNumber,
      'shipment_id': shipmentId,
      'station_id': stationId,
      'return_date': returnDate.toIso8601String().split('T').first,
      'cost_center_id': costCenterId,
      'total_cartons': totalCartons,
      'intact_cartons': intactCartons,
      'damaged_cartons': damagedCartons,
      'total_crop_weight': totalCropWeight,
      'intact_crop_weight': intactCropWeight,
      'damaged_crop_weight': damagedCropWeight,
      'crop_waste_cost': cropWasteCost,
      'material_waste_cost': materialWasteCost,
      'extra_expenses_cost': extraExpensesCost,
      'reversed_revenue_amount': reversedRevenueAmount,
      'reversed_revenue_egp': reversedRevenueEgp,
      'reversed_customer_amount': reversedCustomerAmount,
      'reversed_customer_egp': reversedCustomerEgp,
      'currency': currency,
      'exchange_rate': exchangeRate,
      'return_reason': returnReason,
      'notes': notes,
      'raw_data': rawData,
      'journal_entry_id': journalEntryId,
    };
  }
}
