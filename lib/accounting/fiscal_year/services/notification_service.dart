import 'dart:async';

enum FiscalYearNotificationType {
  closingStarted,
  closingProgress,
  closingCompleted,
  closingFailed,
  rollbackStarted,
  rollbackCompleted,
  recoveryNeeded,
  healthCheckFailed,
  healthCheckPassed,
  consistencyIssueFound,
  dryRunCompleted,
  diagnosticsCompleted,
}

class FiscalYearNotification {
  final FiscalYearNotificationType type;
  final int? fiscalYearId;
  final String title;
  final String message;
  final String messageAr;
  final DateTime timestamp;
  final Map<String, dynamic>? data;
  final String severity;

  const FiscalYearNotification({
    required this.type,
    this.fiscalYearId,
    required this.title,
    required this.message,
    required this.messageAr,
    required this.timestamp,
    this.data,
    this.severity = 'info',
  });

  bool get isCritical =>
      type == FiscalYearNotificationType.closingFailed ||
      type == FiscalYearNotificationType.rollbackStarted ||
      type == FiscalYearNotificationType.healthCheckFailed;
}

class FiscalYearNotificationService {
  static final FiscalYearNotificationService _instance =
      FiscalYearNotificationService._();
  factory FiscalYearNotificationService() => _instance;
  FiscalYearNotificationService._();

  final StreamController<FiscalYearNotification> _controller =
      StreamController<FiscalYearNotification>.broadcast();

  final List<FiscalYearNotification> _buffer = [];
  static const int _maxBuffer = 100;

  Stream<FiscalYearNotification> get notifications => _controller.stream;

  List<FiscalYearNotification> get recentNotifications =>
      List.unmodifiable(_buffer);

  Stream<FiscalYearNotification> subscribe({FiscalYearNotificationType? type}) {
    if (type != null) {
      return _controller.stream.where((n) => n.type == type);
    }
    return _controller.stream;
  }

  Stream<FiscalYearNotification> subscribeToFiscalYear(int fiscalYearId) {
    return _controller.stream.where((n) => n.fiscalYearId == fiscalYearId);
  }

  void publish(FiscalYearNotification notification) {
    _buffer.insert(0, notification);
    if (_buffer.length > _maxBuffer) {
      _buffer.removeLast();
    }
    if (!_controller.isClosed) {
      _controller.add(notification);
    }
  }

  void notifyClosingStarted(int fiscalYearId, String fiscalYearName) {
    publish(FiscalYearNotification(
      type: FiscalYearNotificationType.closingStarted,
      fiscalYearId: fiscalYearId,
      title: 'بدء الإغلاق',
      message: 'Closing started for fiscal year $fiscalYearName',
      messageAr: 'تم بدء إغلاق السنة المالية $fiscalYearName',
      timestamp: DateTime.now(),
      severity: 'info',
    ));
  }

  void notifyClosingProgress(int fiscalYearId, int progressPct, String step) {
    publish(FiscalYearNotification(
      type: FiscalYearNotificationType.closingProgress,
      fiscalYearId: fiscalYearId,
      title: 'تقدم الإغلاق',
      message: 'Progress: $progressPct% - $step',
      messageAr: 'التقدم: $progressPct% - $step',
      timestamp: DateTime.now(),
      data: {'progress_pct': progressPct, 'step': step},
      severity: 'info',
    ));
  }

  void notifyClosingCompleted(int fiscalYearId, Map<String, dynamic> result) {
    publish(FiscalYearNotification(
      type: FiscalYearNotificationType.closingCompleted,
      fiscalYearId: fiscalYearId,
      title: 'اكتمل الإغلاق',
      message: 'Fiscal year closed successfully',
      messageAr: 'تم إغلاق السنة المالية بنجاح',
      timestamp: DateTime.now(),
      data: result,
      severity: 'success',
    ));
  }

  void notifyClosingFailed(int fiscalYearId, String error) {
    publish(FiscalYearNotification(
      type: FiscalYearNotificationType.closingFailed,
      fiscalYearId: fiscalYearId,
      title: 'فشل الإغلاق',
      message: 'Closing failed: $error',
      messageAr: 'فشل الإغلاق: $error',
      timestamp: DateTime.now(),
      data: {'error': error},
      severity: 'error',
    ));
  }

  void notifyRollbackStarted(int fiscalYearId) {
    publish(FiscalYearNotification(
      type: FiscalYearNotificationType.rollbackStarted,
      fiscalYearId: fiscalYearId,
      title: 'بدء التراجع',
      message: 'Rollback initiated for fiscal year',
      messageAr: 'تم بدء التراجع عن إغلاق السنة المالية',
      timestamp: DateTime.now(),
      severity: 'warning',
    ));
  }

  void notifyRollbackCompleted(int fiscalYearId) {
    publish(FiscalYearNotification(
      type: FiscalYearNotificationType.rollbackCompleted,
      fiscalYearId: fiscalYearId,
      title: 'اكتمل التراجع',
      message: 'Rollback completed',
      messageAr: 'تم التراجع بنجاح',
      timestamp: DateTime.now(),
      severity: 'warning',
    ));
  }

  void notifyRecoveryNeeded(int fiscalYearId, String reason) {
    publish(FiscalYearNotification(
      type: FiscalYearNotificationType.recoveryNeeded,
      fiscalYearId: fiscalYearId,
      title: 'الاسترداد مطلوب',
      message: 'Recovery needed: $reason',
      messageAr: 'الاسترداد مطلوب: $reason',
      timestamp: DateTime.now(),
      data: {'reason': reason},
      severity: 'warning',
    ));
  }

  void notifyHealthCheckFailed(String checkName, String details) {
    publish(FiscalYearNotification(
      type: FiscalYearNotificationType.healthCheckFailed,
      title: 'فحص الحالة فشل',
      message: 'Health check failed: $checkName - $details',
      messageAr: 'فحص الحالة فشل: $checkName - $details',
      timestamp: DateTime.now(),
      data: {'check': checkName, 'details': details},
      severity: 'error',
    ));
  }

  void notifyConsistencyIssue(String category, String description) {
    publish(FiscalYearNotification(
      type: FiscalYearNotificationType.consistencyIssueFound,
      title: 'مشكلة في التناسق',
      message: 'Consistency issue: $category - $description',
      messageAr: 'مشكلة في التناسق: $category - $description',
      timestamp: DateTime.now(),
      data: {'category': category, 'description': description},
      severity: 'warning',
    ));
  }

  void clearBuffer() => _buffer.clear();

  void dispose() => _controller.close();
}
