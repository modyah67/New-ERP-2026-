import 'package:equatable/equatable.dart';
import 'fiscal_year_status.dart';

class FiscalYear extends Equatable {
  final int id;
  final int year;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final FiscalYearStatus status;
  final bool isCurrent;
  final bool isClosed;
  final String? closedBy;
  final DateTime? closedAt;
  final String? openedBy;
  final DateTime? openedAt;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? companyId;

  const FiscalYear({
    required this.id,
    required this.year,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.isCurrent,
    required this.isClosed,
    this.closedBy,
    this.closedAt,
    this.openedBy,
    this.openedAt,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.companyId,
  });

  factory FiscalYear.fromJson(Map<String, dynamic> json) {
    return FiscalYear(
      id: json['id'] as int,
      year: json['year'] as int,
      name: (json['name'] as String?) ?? json['year'].toString(),
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      status: FiscalYearStatusExtension.fromString(json['status'] as String),
      isCurrent: json['is_current'] as bool? ?? false,
      isClosed: json['is_closed'] as bool? ?? false,
      closedBy: json['closed_by'] as String?,
      closedAt: json['closed_at'] != null ? DateTime.parse(json['closed_at'] as String) : null,
      openedBy: json['opened_by'] as String?,
      openedAt: json['opened_at'] != null ? DateTime.parse(json['opened_at'] as String) : null,
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      companyId: json['company_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'year': year,
      'name': name,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'status': status.value,
      'is_current': isCurrent,
      'is_closed': isClosed,
      if (closedBy != null) 'closed_by': closedBy,
      if (closedAt != null) 'closed_at': closedAt!.toIso8601String(),
      if (openedBy != null) 'opened_by': openedBy,
      if (openedAt != null) 'opened_at': openedAt!.toIso8601String(),
      if (createdBy != null) 'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (companyId != null) 'company_id': companyId,
    };
  }

  FiscalYear copyWith({
    int? id,
    int? year,
    String? name,
    DateTime? startDate,
    DateTime? endDate,
    FiscalYearStatus? status,
    bool? isCurrent,
    bool? isClosed,
    String? closedBy,
    DateTime? closedAt,
    String? openedBy,
    DateTime? openedAt,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? companyId,
  }) {
    return FiscalYear(
      id: id ?? this.id,
      year: year ?? this.year,
      name: name ?? this.name,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      status: status ?? this.status,
      isCurrent: isCurrent ?? this.isCurrent,
      isClosed: isClosed ?? this.isClosed,
      closedBy: closedBy ?? this.closedBy,
      closedAt: closedAt ?? this.closedAt,
      openedBy: openedBy ?? this.openedBy,
      openedAt: openedAt ?? this.openedAt,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      companyId: companyId ?? this.companyId,
    );
  }

  bool get canBeClosed => status.canTransitionToClosing;
  bool get canBeReopened => status == FiscalYearStatus.closed;
  bool get canBeArchived => status.canTransitionToArchived;
  bool get isOpen => status == FiscalYearStatus.active;
  bool get isDraft => status == FiscalYearStatus.draft;
  bool get isClosing => status == FiscalYearStatus.closing;
  bool get isArchived => status == FiscalYearStatus.archived;
  bool get canCreateDocuments => status.canCreateDocuments;

  int get daysRemaining {
    final now = DateTime.now();
    if (now.isAfter(endDate)) return 0;
    return endDate.difference(now).inDays;
  }

  @override
  List<Object?> get props => [
        id, year, name, startDate, endDate, status, isCurrent, isClosed,
        closedBy, closedAt, openedBy, openedAt, createdBy, createdAt, updatedAt,
        companyId,
      ];
}
