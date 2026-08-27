import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/fiscal_year.dart';
import '../models/closing_result.dart';
import '../models/closing_progress.dart';
import '../models/closing_entry.dart';
import '../services/fiscal_year_service.dart';
import '../services/fiscal_year_closing_engine.dart';
import '../services/closing_validation_service.dart';
import '../services/closing_audit_service.dart';
import '../services/closing_report_service.dart';

sealed class FiscalYearState {
  const FiscalYearState();
}

class FiscalYearInitial extends FiscalYearState {
  const FiscalYearInitial();
}

class FiscalYearLoading extends FiscalYearState {
  const FiscalYearLoading();
}

class FiscalYearLoaded extends FiscalYearState {
  final List<FiscalYear> fiscalYears;
  final FiscalYear? currentFiscalYear;
  final List<FiscalYear> closedYears;

  const FiscalYearLoaded({
    required this.fiscalYears,
    this.currentFiscalYear,
    this.closedYears = const [],
  });

  List<FiscalYear> get allFiscalYears => fiscalYears;
}

class FiscalYearClosingInProgress extends FiscalYearState {
  final ClosingProgress progress;
  const FiscalYearClosingInProgress({required this.progress});
}

class FiscalYearClosingSuccess extends FiscalYearState {
  final ClosingResult result;
  final List<ClosingEntry> closingEntries;
  final double netIncome;
  final Map<String, double> revenueTotals;
  final Map<String, double> expenseTotals;

  const FiscalYearClosingSuccess({
    required this.result,
    this.closingEntries = const [],
    required this.netIncome,
    this.revenueTotals = const {},
    this.expenseTotals = const {},
  });
}

class FiscalYearClosingFailure extends FiscalYearState {
  final String message;
  const FiscalYearClosingFailure({required this.message});
}

class FiscalYearOpeningInProgress extends FiscalYearState {
  const FiscalYearOpeningInProgress();
}

class FiscalYearOpeningSuccess extends FiscalYearState {
  final ClosingResult result;
  final List<ClosingEntry> openingEntries;
  const FiscalYearOpeningSuccess({required this.result, this.openingEntries = const []});
}

class FiscalYearOpeningFailure extends FiscalYearState {
  final String message;
  const FiscalYearOpeningFailure({required this.message});
}

class FiscalYearValidationSuccess extends FiscalYearState {
  final List<String> messages;
  const FiscalYearValidationSuccess({this.messages = const []});
}

class FiscalYearValidationFailure extends FiscalYearState {
  final List<String> errors;
  const FiscalYearValidationFailure({required this.errors});
}

class FiscalYearReopeningInProgress extends FiscalYearState {
  const FiscalYearReopeningInProgress();
}

class FiscalYearReopeningSuccess extends FiscalYearState {
  final String message;
  const FiscalYearReopeningSuccess({required this.message});
}

class FiscalYearReopeningFailure extends FiscalYearState {
  final String message;
  const FiscalYearReopeningFailure({required this.message});
}

class FiscalYearReportLoaded extends FiscalYearState {
  final Map<String, dynamic> report;
  const FiscalYearReportLoaded({required this.report});
}

class FiscalYearAuditLogLoaded extends FiscalYearState {
  final List<Map<String, dynamic>> entries;
  const FiscalYearAuditLogLoaded({required this.entries});
}

class FiscalYearError extends FiscalYearState {
  final String message;
  const FiscalYearError({required this.message});
}

class FiscalYearCubit extends Cubit<FiscalYearState> {
  final FiscalYearService _service;
  final FiscalYearClosingEngine _closingEngine;
  final ClosingReportService _reportService;

  FiscalYearCubit({
    required FiscalYearService service,
    FiscalYearClosingEngine? closingEngine,
    ClosingValidationService? validationService,
    ClosingAuditService? auditService,
    ClosingReportService? reportService,
  })  : _service = service,
        _closingEngine = closingEngine ?? FiscalYearClosingEngine(),
        _reportService = reportService ?? ClosingReportService(),
        super(const FiscalYearInitial());

  Future<void> loadFiscalYears() async {
    emit(const FiscalYearLoading());
    try {
      final years = await _service.getAll();
      final current = await _service.getCurrent();
      final closedYears = await _service.getClosedYears();
      emit(FiscalYearLoaded(
        fiscalYears: years,
        currentFiscalYear: current,
        closedYears: closedYears,
      ));
    } catch (e) {
      emit(FiscalYearError(message: 'خطأ في تحميل البيانات: $e'));
    }
  }

  Future<void> setCurrent(int id, {String? performedBy, String? reason}) async {
    emit(const FiscalYearLoading());
    try {
      await _service.setCurrent(id, performedBy: performedBy, reason: reason);
      await loadFiscalYears();
    } catch (e) {
      emit(FiscalYearError(message: 'خطأ: $e'));
    }
  }

  Future<void> validatePreClosing(int fiscalYearId) async {
    emit(const FiscalYearLoading());
    try {
      final errors = await _closingEngine.validatePreClosing(fiscalYearId);
      if (errors.isEmpty) {
        emit(const FiscalYearValidationSuccess(
          messages: ['تم التحقق بنجاح - يمكن إغلاق السنة المالية'],
        ));
      } else {
        emit(FiscalYearValidationFailure(errors: errors));
      }
    } catch (e) {
      emit(FiscalYearError(message: 'خطأ في التحقق: $e'));
    }
  }

  Future<void> closeFiscalYear({
    required int fiscalYearId,
    required String userId,
    String? reason,
    bool createNextYear = false,
  }) async {
    try {
      // Start progress monitoring
      final progress = ClosingProgress(
        fiscalYearId: fiscalYearId,
        status: ClosingProgressStatus.validating,
        progressPct: 5,
        currentStep: 'بدء الإغلاق',
        startedAt: DateTime.now(),
        performedBy: userId,
      );
      emit(FiscalYearClosingInProgress(progress: progress));

      final result = await _closingEngine.closeFiscalYear(
        fiscalYearId: fiscalYearId,
        userId: userId,
        reason: reason,
        createNextYear: createNextYear,
      );

      if (result.success) {
        emit(FiscalYearClosingSuccess(
          result: result,
          closingEntries: result.closingEntries,
          netIncome: result.netIncome,
          revenueTotals: result.revenueTotals,
          expenseTotals: result.expenseTotals,
        ));
        await loadFiscalYears();
      } else {
        emit(FiscalYearClosingFailure(message: result.message));
      }
    } catch (e) {
      emit(FiscalYearClosingFailure(message: 'خطأ في الإغلاق: $e'));
    }
  }

  Future<void> reopenFiscalYear({
    required int fiscalYearId,
    required String userId,
    required String reason,
  }) async {
    emit(const FiscalYearReopeningInProgress());
    try {
      final result = await _closingEngine.reopenFiscalYear(
        fiscalYearId: fiscalYearId,
        userId: userId,
        reason: reason,
      );

      if (result.success) {
        emit(FiscalYearReopeningSuccess(message: result.message));
        await loadFiscalYears();
      } else {
        emit(FiscalYearReopeningFailure(message: result.message));
      }
    } catch (e) {
      emit(FiscalYearReopeningFailure(message: 'خطأ في إعادة الفتح: $e'));
    }
  }

  Future<void> archiveFiscalYear({
    required int fiscalYearId,
    required String userId,
  }) async {
    emit(const FiscalYearLoading());
    try {
      final result = await _closingEngine.archiveFiscalYear(
        fiscalYearId: fiscalYearId,
        userId: userId,
      );
      if (result.success) {
        await loadFiscalYears();
      } else {
        emit(FiscalYearError(message: result.message));
      }
    } catch (e) {
      emit(FiscalYearError(message: 'خطأ في الأرشفة: $e'));
    }
  }

  Future<void> loadFiscalYearSummary(int fiscalYearId) async {
    emit(const FiscalYearLoading());
    try {
      final report = await _reportService.getFiscalYearSummary(fiscalYearId);
      emit(FiscalYearReportLoaded(report: report));
    } catch (e) {
      emit(FiscalYearError(message: 'خطأ في تحميل التقرير: $e'));
    }
  }

  Future<void> loadAuditLog(int fiscalYearId) async {
    emit(const FiscalYearLoading());
    try {
      final entries = await _reportService.getAuditReport(fiscalYearId);
      emit(FiscalYearAuditLogLoaded(entries: entries));
    } catch (e) {
      emit(FiscalYearError(message: 'خطأ في تحميل السجل: $e'));
    }
  }

  Future<void> createFiscalYear(FiscalYear fy) async {
    emit(const FiscalYearLoading());
    try {
      await _service.createFiscalYear(fy);
      await loadFiscalYears();
    } catch (e) {
      emit(FiscalYearError(message: 'خطأ في الإنشاء: $e'));
    }
  }

  Future<void> updateFiscalYear(FiscalYear fy) async {
    emit(const FiscalYearLoading());
    try {
      await _service.updateFiscalYear(fy);
      await loadFiscalYears();
    } catch (e) {
      emit(FiscalYearError(message: 'خطأ في التحديث: $e'));
    }
  }
}
