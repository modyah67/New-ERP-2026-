import 'package:equatable/equatable.dart';

enum ClosingProgressStatus {
  pending,
  validating,
  closingGl,
  closingInventory,
  generatingOpening,
  writingAudit,
  finalizing,
  completed,
  failed,
  rolledBack,
}

extension ClosingProgressStatusExtension on ClosingProgressStatus {
  String get value {
    switch (this) {
      case ClosingProgressStatus.pending:
        return 'PENDING';
      case ClosingProgressStatus.validating:
        return 'VALIDATING';
      case ClosingProgressStatus.closingGl:
        return 'CLOSING_GL';
      case ClosingProgressStatus.closingInventory:
        return 'CLOSING_INVENTORY';
      case ClosingProgressStatus.generatingOpening:
        return 'GENERATING_OPENING';
      case ClosingProgressStatus.writingAudit:
        return 'WRITING_AUDIT';
      case ClosingProgressStatus.finalizing:
        return 'FINALIZING';
      case ClosingProgressStatus.completed:
        return 'COMPLETED';
      case ClosingProgressStatus.failed:
        return 'FAILED';
      case ClosingProgressStatus.rolledBack:
        return 'ROLLED_BACK';
    }
  }

  String get displayNameAr {
    switch (this) {
      case ClosingProgressStatus.pending:
        return 'في الانتظار';
      case ClosingProgressStatus.validating:
        return 'التحقق من البيانات';
      case ClosingProgressStatus.closingGl:
        return 'إغلاق الدفتر الأستاذ العام';
      case ClosingProgressStatus.closingInventory:
        return 'إغلاق المخزون';
      case ClosingProgressStatus.generatingOpening:
        return 'إنشاء القيود الافتتاحية';
      case ClosingProgressStatus.writingAudit:
        return 'كتابة سجل التدقيق';
      case ClosingProgressStatus.finalizing:
        return 'الإنهاء';
      case ClosingProgressStatus.completed:
        return 'مكتمل';
      case ClosingProgressStatus.failed:
        return 'فشل';
      case ClosingProgressStatus.rolledBack:
        return 'تم التراجع';
    }
  }

  int get progressPct {
    switch (this) {
      case ClosingProgressStatus.pending:
        return 0;
      case ClosingProgressStatus.validating:
        return 5;
      case ClosingProgressStatus.closingGl:
        return 40;
      case ClosingProgressStatus.closingInventory:
        return 55;
      case ClosingProgressStatus.generatingOpening:
        return 75;
      case ClosingProgressStatus.writingAudit:
        return 90;
      case ClosingProgressStatus.finalizing:
        return 95;
      case ClosingProgressStatus.completed:
        return 100;
      case ClosingProgressStatus.failed:
        return 0;
      case ClosingProgressStatus.rolledBack:
        return 0;
    }
  }

  static ClosingProgressStatus fromString(String s) {
    switch (s.toUpperCase()) {
      case 'PENDING':
        return ClosingProgressStatus.pending;
      case 'VALIDATING':
        return ClosingProgressStatus.validating;
      case 'CLOSING_GL':
        return ClosingProgressStatus.closingGl;
      case 'CLOSING_INVENTORY':
        return ClosingProgressStatus.closingInventory;
      case 'GENERATING_OPENING':
        return ClosingProgressStatus.generatingOpening;
      case 'WRITING_AUDIT':
        return ClosingProgressStatus.writingAudit;
      case 'FINALIZING':
        return ClosingProgressStatus.finalizing;
      case 'COMPLETED':
        return ClosingProgressStatus.completed;
      case 'FAILED':
        return ClosingProgressStatus.failed;
      case 'ROLLED_BACK':
        return ClosingProgressStatus.rolledBack;
      default:
        return ClosingProgressStatus.pending;
    }
  }
}

class ClosingProgress extends Equatable {
  final int? id;
  final int fiscalYearId;
  final ClosingProgressStatus status;
  final int progressPct;
  final String? currentStep;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String? performedBy;
  final String? errorMessage;
  final Map<String, dynamic>? details;

  const ClosingProgress({
    this.id,
    required this.fiscalYearId,
    required this.status,
    this.progressPct = 0,
    this.currentStep,
    required this.startedAt,
    this.completedAt,
    this.performedBy,
    this.errorMessage,
    this.details,
  });

  factory ClosingProgress.fromJson(Map<String, dynamic> json) {
    return ClosingProgress(
      id: json['id'] as int?,
      fiscalYearId: json['fiscal_year_id'] as int,
      status: ClosingProgressStatusExtension.fromString(json['status'] as String),
      progressPct: json['progress_pct'] as int? ?? 0,
      currentStep: json['current_step'] as String?,
      startedAt: DateTime.parse(json['started_at'] as String),
      completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at'] as String) : null,
      performedBy: json['performed_by'] as String?,
      errorMessage: json['error_message'] as String?,
      details: json['details'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'fiscal_year_id': fiscalYearId,
      'status': status.value,
      'progress_pct': progressPct,
      'current_step': currentStep,
      'started_at': startedAt.toIso8601String(),
      if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
      'performed_by': performedBy,
      'error_message': errorMessage,
      'details': details,
    };
  }

  bool get isCompleted => status == ClosingProgressStatus.completed;
  bool get isFailed => status == ClosingProgressStatus.failed;
  bool get isInProgress => !isCompleted && !isFailed &&
      status != ClosingProgressStatus.pending &&
      status != ClosingProgressStatus.rolledBack;

  @override
  List<Object?> get props => [id, fiscalYearId, status, progressPct, currentStep, startedAt, completedAt];
}
