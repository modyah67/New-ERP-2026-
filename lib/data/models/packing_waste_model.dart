import 'dart:convert';

class PackingWasteModel {
  final int? id;
  final String wasteNumber;
  final int? stationId;
  final DateTime date;
  final String status;
  final double totalCropWasteCost;
  final double totalSortingCost;
  final double totalMaterialWasteCost;
  final double totalCostItems;
  final double totalWasteAmount;
  final int? journalEntryId;
  final Map<String, dynamic> notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  PackingWasteModel({
    this.id,
    required this.wasteNumber,
    this.stationId,
    required this.date,
    this.status = 'draft',
    this.totalCropWasteCost = 0.0,
    this.totalSortingCost = 0.0,
    this.totalMaterialWasteCost = 0.0,
    this.totalCostItems = 0.0,
    this.totalWasteAmount = 0.0,
    this.journalEntryId,
    this.notes = const {},
    this.createdAt,
    this.updatedAt,
  });

  factory PackingWasteModel.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> parsedNotes = {};
    if (map['notes'] != null) {
      if (map['notes'] is Map) {
        parsedNotes = Map<String, dynamic>.from(map['notes']);
      } else if (map['notes'] is String) {
        try {
          parsedNotes = jsonDecode(map['notes']);
        } catch (_) {}
      }
    }
    return PackingWasteModel(
      id: map['id'] as int?,
      wasteNumber: map['waste_number'] ?? '',
      stationId: map['station_id'] as int?,
      date: map['date'] != null ? DateTime.parse(map['date']) : DateTime.now(),
      status: map['status'] ?? 'draft',
      totalCropWasteCost: (map['total_crop_waste_cost'] as num?)?.toDouble() ?? 0.0,
      totalSortingCost: (map['total_sorting_cost'] as num?)?.toDouble() ?? 0.0,
      totalMaterialWasteCost: (map['total_material_waste_cost'] as num?)?.toDouble() ?? 0.0,
      totalCostItems: (map['total_cost_items'] as num?)?.toDouble() ?? 0.0,
      totalWasteAmount: (map['total_waste_amount'] as num?)?.toDouble() ?? 0.0,
      journalEntryId: map['journal_entry_id'] as int?,
      notes: parsedNotes,
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : null,
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'waste_number': wasteNumber,
      'station_id': stationId,
      'date': date.toIso8601String().split('T').first,
      'status': status,
      'total_crop_waste_cost': totalCropWasteCost,
      'total_sorting_cost': totalSortingCost,
      'total_material_waste_cost': totalMaterialWasteCost,
      'total_cost_items': totalCostItems,
      'total_waste_amount': totalWasteAmount,
      'notes': notes,
    };
  }
}
