import 'package:equatable/equatable.dart';

class ClosingLock extends Equatable {
  final int id;
  final String? lockedBy;
  final DateTime? lockedAt;
  final int? fiscalYearId;
  final DateTime? releasedAt;
  final String status;

  const ClosingLock({
    required this.id,
    this.lockedBy,
    this.lockedAt,
    this.fiscalYearId,
    this.releasedAt,
    required this.status,
  });

  factory ClosingLock.fromJson(Map<String, dynamic> json) {
    return ClosingLock(
      id: json['id'] as int,
      lockedBy: json['locked_by'] as String?,
      lockedAt: json['locked_at'] != null ? DateTime.parse(json['locked_at'] as String) : null,
      fiscalYearId: json['fiscal_year_id'] as int?,
      releasedAt: json['released_at'] != null ? DateTime.parse(json['released_at'] as String) : null,
      status: json['status'] as String? ?? 'FREE',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'locked_by': lockedBy,
      'locked_at': lockedAt?.toIso8601String(),
      'fiscal_year_id': fiscalYearId,
      'released_at': releasedAt?.toIso8601String(),
      'status': status,
    };
  }

  bool get isLocked => status == 'LOCKED';
  bool get isFree => status == 'FREE';
  bool get isRecovering => status == 'RECOVERING';

  @override
  List<Object?> get props => [id, lockedBy, lockedAt, fiscalYearId, releasedAt, status];
}
