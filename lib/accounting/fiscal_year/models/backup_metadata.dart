import 'package:equatable/equatable.dart';

class BackupMetadata extends Equatable {
  final int? id;
  final int fiscalYearId;
  final DateTime backupTime;
  final String? performedBy;
  final String? dbVersion;
  final String? migrationVersion;
  final String backupIdentifier;
  final String status;
  final Map<String, dynamic>? details;
  final DateTime createdAt;

  const BackupMetadata({
    this.id,
    required this.fiscalYearId,
    required this.backupTime,
    this.performedBy,
    this.dbVersion,
    this.migrationVersion,
    required this.backupIdentifier,
    this.status = 'CREATED',
    this.details,
    required this.createdAt,
  });

  factory BackupMetadata.fromJson(Map<String, dynamic> json) {
    return BackupMetadata(
      id: json['id'] as int?,
      fiscalYearId: json['fiscal_year_id'] as int,
      backupTime: DateTime.parse(json['backup_time'] as String),
      performedBy: json['performed_by'] as String?,
      dbVersion: json['db_version'] as String?,
      migrationVersion: json['migration_version'] as String?,
      backupIdentifier: json['backup_identifier'] as String,
      status: json['status'] as String? ?? 'CREATED',
      details: json['details'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'fiscal_year_id': fiscalYearId,
      'backup_time': backupTime.toIso8601String(),
      'performed_by': performedBy,
      'db_version': dbVersion,
      'migration_version': migrationVersion,
      'backup_identifier': backupIdentifier,
      'status': status,
      'details': details,
    };
  }

  @override
  List<Object?> get props => [id, fiscalYearId, backupIdentifier, status];
}
