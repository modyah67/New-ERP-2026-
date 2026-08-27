import 'dart:async';
import '../models/closing_progress.dart';

enum ProgressEventPhase {
  started,
  validating,
  acquiringLock,
  closingGl,
  closingInventory,
  generatingOpening,
  writingAudit,
  postClosingVerification,
  creatingNextYear,
  releasingLock,
  completed,
  failed,
  rolledBack,
}

class ClosingProgressEvent {
  final int fiscalYearId;
  final ProgressEventPhase phase;
  final ClosingProgressStatus status;
  final int progressPct;
  final String currentStep;
  final String currentOperation;
  final String? currentTable;
  final int? rowsProcessed;
  final int? totalRows;
  final List<String> logs;
  final List<String> warnings;
  final String? errorMessage;
  final DateTime timestamp;
  final Duration? elapsedTime;
  final Duration? estimatedRemaining;
  final bool isIrreversible;
  final Map<String, dynamic>? metadata;

  const ClosingProgressEvent({
    required this.fiscalYearId,
    required this.phase,
    required this.status,
    required this.progressPct,
    required this.currentStep,
    this.currentOperation = '',
    this.currentTable,
    this.rowsProcessed,
    this.totalRows,
    this.logs = const [],
    this.warnings = const [],
    this.errorMessage,
    required this.timestamp,
    this.elapsedTime,
    this.estimatedRemaining,
    this.isIrreversible = false,
    this.metadata,
  });

  double get progressFraction => progressPct / 100.0;

  bool get canCancel => !isIrreversible &&
      phase != ProgressEventPhase.completed &&
      phase != ProgressEventPhase.failed &&
      phase != ProgressEventPhase.rolledBack;
}

class FiscalYearProgressService {
  static final FiscalYearProgressService _instance = FiscalYearProgressService._();
  factory FiscalYearProgressService() => _instance;
  FiscalYearProgressService._();

  final StreamController<ClosingProgressEvent> _controller =
      StreamController<ClosingProgressEvent>.broadcast();

  final Map<int, ClosingProgressEvent> _currentProgress = {};
  final Map<int, List<ClosingProgressEvent>> _history = {};

  Stream<ClosingProgressEvent> get progressStream => _controller.stream;

  ClosingProgressEvent? getCurrentProgress(int fiscalYearId) =>
      _currentProgress[fiscalYearId];

  List<ClosingProgressEvent> getHistory(int fiscalYearId) =>
      List.unmodifiable(_history[fiscalYearId] ?? []);

  Stream<ClosingProgressEvent> subscribe(int fiscalYearId) {
    return _controller.stream.where((e) => e.fiscalYearId == fiscalYearId);
  }

  void unsubscribe(int fiscalYearId) {
    _currentProgress.remove(fiscalYearId);
    _history.remove(fiscalYearId);
  }

  void emit(ClosingProgressEvent event) {
    _currentProgress[event.fiscalYearId] = event;
    _history.putIfAbsent(event.fiscalYearId, () => []).add(event);
    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  void emitPhase({
    required int fiscalYearId,
    required ProgressEventPhase phase,
    required String currentStep,
    String currentOperation = '',
    String? currentTable,
    int? rowsProcessed,
    int? totalRows,
    List<String> logs = const [],
    List<String> warnings = const [],
    String? errorMessage,
    bool isIrreversible = false,
    Map<String, dynamic>? metadata,
  }) {
    final status = _phaseToStatus(phase);
    final pct = _phaseToPct(phase);
    final now = DateTime.now();
    final elapsed = now.difference(_getStartTime(fiscalYearId));
    final estimated = _estimateRemaining(phase, elapsed);

    emit(ClosingProgressEvent(
      fiscalYearId: fiscalYearId,
      phase: phase,
      status: status,
      progressPct: pct,
      currentStep: currentStep,
      currentOperation: currentOperation,
      currentTable: currentTable,
      rowsProcessed: rowsProcessed,
      totalRows: totalRows,
      logs: logs,
      warnings: warnings,
      errorMessage: errorMessage,
      timestamp: now,
      elapsedTime: elapsed,
      estimatedRemaining: estimated,
      isIrreversible: isIrreversible,
      metadata: metadata,
    ));
  }

  void reset(int fiscalYearId) {
    _currentProgress.remove(fiscalYearId);
    _history.remove(fiscalYearId);
  }

  void dispose() {
    _controller.close();
  }

  DateTime _getStartTime(int fiscalYearId) {
    final history = _history[fiscalYearId];
    if (history != null && history.isNotEmpty) {
      return history.first.timestamp;
    }
    return DateTime.now();
  }

  Duration _estimateRemaining(ProgressEventPhase phase, Duration elapsed) {
    final totalEstimate = const Duration(minutes: 5);
    final phasePct = _phaseToPct(phase) / 100.0;
    if (phasePct <= 0) return totalEstimate;
    final estimatedTotal = elapsed.inMilliseconds / phasePct;
    final remaining = estimatedTotal - elapsed.inMilliseconds;
    return Duration(milliseconds: remaining.toInt().clamp(0, estimatedTotal.toInt()));
  }

  ClosingProgressStatus _phaseToStatus(ProgressEventPhase phase) {
    switch (phase) {
      case ProgressEventPhase.started:
      case ProgressEventPhase.validating:
      case ProgressEventPhase.acquiringLock:
        return ClosingProgressStatus.validating;
      case ProgressEventPhase.closingGl:
        return ClosingProgressStatus.closingGl;
      case ProgressEventPhase.closingInventory:
        return ClosingProgressStatus.closingInventory;
      case ProgressEventPhase.generatingOpening:
        return ClosingProgressStatus.generatingOpening;
      case ProgressEventPhase.writingAudit:
      case ProgressEventPhase.postClosingVerification:
      case ProgressEventPhase.creatingNextYear:
        return ClosingProgressStatus.writingAudit;
      case ProgressEventPhase.releasingLock:
      case ProgressEventPhase.completed:
        return ClosingProgressStatus.completed;
      case ProgressEventPhase.failed:
        return ClosingProgressStatus.failed;
      case ProgressEventPhase.rolledBack:
        return ClosingProgressStatus.rolledBack;
    }
  }

  int _phaseToPct(ProgressEventPhase phase) {
    switch (phase) {
      case ProgressEventPhase.started:
        return 0;
      case ProgressEventPhase.validating:
        return 5;
      case ProgressEventPhase.acquiringLock:
        return 8;
      case ProgressEventPhase.closingGl:
        return 35;
      case ProgressEventPhase.closingInventory:
        return 50;
      case ProgressEventPhase.generatingOpening:
        return 70;
      case ProgressEventPhase.writingAudit:
        return 82;
      case ProgressEventPhase.postClosingVerification:
        return 90;
      case ProgressEventPhase.creatingNextYear:
        return 93;
      case ProgressEventPhase.releasingLock:
        return 97;
      case ProgressEventPhase.completed:
        return 100;
      case ProgressEventPhase.failed:
        return 0;
      case ProgressEventPhase.rolledBack:
        return 0;
    }
  }
}
