import 'package:intl/intl.dart';

/// Represents a distinct transport entitlement batch (دفعة استحقاق نقل).
/// Allows withdrawing trucks from a specific batch rather than dealing with an aggregate total.
class TransportBatchModel {
  final int id; // ID of the transport transaction (or -1 for opening balance)
  final int supplierId;
  final String date;
  final String description;
  final String? referenceId;
  final String? routeFrom;
  final String? routeTo;
  final double totalAmount;
  final double totalTrucks;
  final double consumedTrucks;
  final double availableTrucks;
  final double costPerTruck;
  final bool isOpeningBalance;

  const TransportBatchModel({
    required this.id,
    required this.supplierId,
    required this.date,
    required this.description,
    this.referenceId,
    this.routeFrom,
    this.routeTo,
    required this.totalAmount,
    required this.totalTrucks,
    required this.consumedTrucks,
    required this.availableTrucks,
    required this.costPerTruck,
    this.isOpeningBalance = false,
  });

  TransportBatchModel copyWith({
    int? id,
    int? supplierId,
    String? date,
    String? description,
    String? referenceId,
    String? routeFrom,
    String? routeTo,
    double? totalAmount,
    double? totalTrucks,
    double? consumedTrucks,
    double? availableTrucks,
    double? costPerTruck,
    bool? isOpeningBalance,
  }) {
    return TransportBatchModel(
      id: id ?? this.id,
      supplierId: supplierId ?? this.supplierId,
      date: date ?? this.date,
      description: description ?? this.description,
      referenceId: referenceId ?? this.referenceId,
      routeFrom: routeFrom ?? this.routeFrom,
      routeTo: routeTo ?? this.routeTo,
      totalAmount: totalAmount ?? this.totalAmount,
      totalTrucks: totalTrucks ?? this.totalTrucks,
      consumedTrucks: consumedTrucks ?? this.consumedTrucks,
      availableTrucks: availableTrucks ?? this.availableTrucks,
      costPerTruck: costPerTruck ?? this.costPerTruck,
      isOpeningBalance: isOpeningBalance ?? this.isOpeningBalance,
    );
  }

  String get routeDisplay {
    final from = routeFrom?.trim();
    final to = routeTo?.trim();
    if ((from != null && from.isNotEmpty) || (to != null && to.isNotEmpty)) {
      return '${from?.isNotEmpty == true ? from : '—'} ➔ ${to?.isNotEmpty == true ? to : '—'}';
    }
    return '';
  }

  String get formattedCostPerTruck =>
      NumberFormat('#,##0.00').format(costPerTruck);

  String get formattedAvailableTrucks {
    if (availableTrucks % 1 == 0) {
      return availableTrucks.toInt().toString();
    }
    return availableTrucks
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  String get formattedTotalTrucks {
    if (totalTrucks % 1 == 0) {
      return totalTrucks.toInt().toString();
    }
    return totalTrucks
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  String get displayTitle {
    final status = availableTrucks <= 0 ? ' [مستنفدة]' : '';
    if (isOpeningBalance || id == -1) {
      return 'رصيد افتتاحي (متاح $formattedAvailableTrucks من $formattedTotalTrucks نقلة)$status';
    }
    final ref = (referenceId != null && referenceId!.isNotEmpty)
        ? ' (مرجع: $referenceId)'
        : '';
    return 'دفعة #$id$ref • $formattedAvailableTrucks نقلة متاحة ($formattedCostPerTruck ج.م/نقلة)$status';
  }

  String get displaySubtitle {
    final parts = <String>[];
    if (date.isNotEmpty) parts.add(date);
    if (routeDisplay.isNotEmpty) parts.add(routeDisplay);
    if (description.isNotEmpty && description != 'استحقاق نقل') {
      parts.add(description);
    }
    return parts.join(' | ');
  }
}

