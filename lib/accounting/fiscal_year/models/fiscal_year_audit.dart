import 'package:equatable/equatable.dart';

class FiscalYearAudit extends Equatable {
  final int id;
  final int fiscalYearId;
  final String action;
  final String? performedBy;
  final DateTime performedAt;
  final Map<String, dynamic>? oldStatus;
  final Map<String, dynamic>? newStatus;
  final String? reason;
  final String? machineInfo;
  final String? ipAddress;
  final Map<String, dynamic>? details;
  final DateTime createdAt;

  const FiscalYearAudit({
    required this.id,
    required this.fiscalYearId,
    required this.action,
    this.performedBy,
    required this.performedAt,
    this.oldStatus,
    this.newStatus,
    this.reason,
    this.machineInfo,
    this.ipAddress,
    this.details,
    required this.createdAt,
  });

  factory FiscalYearAudit.fromJson(Map<String, dynamic> json) {
    return FiscalYearAudit(
      id: json['id'] as int,
      fiscalYearId: json['fiscal_year_id'] as int,
      action: json['action'] as String,
      performedBy: json['performed_by'] as String?,
      performedAt: DateTime.parse(json['performed_at'] as String),
      oldStatus: json['old_status'] as Map<String, dynamic>?,
      newStatus: json['new_status'] as Map<String, dynamic>?,
      reason: json['reason'] as String?,
      machineInfo: json['machine_info'] as String?,
      ipAddress: json['ip_address'] as String?,
      details: json['details'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fiscal_year_id': fiscalYearId,
      'action': action,
      if (performedBy != null) 'performed_by': performedBy,
      'performed_at': performedAt.toIso8601String(),
      if (oldStatus != null) 'old_status': oldStatus,
      if (newStatus != null) 'new_status': newStatus,
      if (reason != null) 'reason': reason,
      if (machineInfo != null) 'machine_info': machineInfo,
      if (ipAddress != null) 'ip_address': ipAddress,
      if (details != null) 'details': details,
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
        id,
        fiscalYearId,
        action,
        performedBy,
        performedAt,
        oldStatus,
        newStatus,
        reason,
        machineInfo,
        ipAddress,
        details,
        createdAt,
      ];
}
