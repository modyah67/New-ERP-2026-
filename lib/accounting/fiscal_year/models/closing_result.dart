import 'closing_entry.dart';

class ClosingResult {
  final bool success;
  final String message;
  final List<ClosingEntry> closingEntries;
  final List<ClosingEntry> openingEntries;
  final Map<String, double> revenueTotals;
  final Map<String, double> expenseTotals;
  final double netIncome;
  final DateTime closedAt;
  final int? auditLogId;
  final int? newFiscalYearId;
  final Duration? duration;

  const ClosingResult({
    required this.success,
    required this.message,
    this.closingEntries = const [],
    this.openingEntries = const [],
    this.revenueTotals = const {},
    this.expenseTotals = const {},
    required this.netIncome,
    required this.closedAt,
    this.auditLogId,
    this.newFiscalYearId,
    this.duration,
  });

  factory ClosingResult.success({
    required List<ClosingEntry> closingEntries,
    required List<ClosingEntry> openingEntries,
    required Map<String, double> revenueTotals,
    required Map<String, double> expenseTotals,
    required double netIncome,
    required DateTime closedAt,
    int? auditLogId,
    int? newFiscalYearId,
    Duration? duration,
  }) {
    return ClosingResult(
      success: true,
      message: 'تم إغلاق السنة المالية بنجاح',
      closingEntries: closingEntries,
      openingEntries: openingEntries,
      revenueTotals: revenueTotals,
      expenseTotals: expenseTotals,
      netIncome: netIncome,
      closedAt: closedAt,
      auditLogId: auditLogId,
      newFiscalYearId: newFiscalYearId,
      duration: duration,
    );
  }

  factory ClosingResult.failure(String message) {
    return ClosingResult(
      success: false,
      message: message,
      netIncome: 0,
      closedAt: DateTime.now(),
    );
  }

  String get durationFormatted {
    if (duration == null) return '-';
    final mins = duration!.inMinutes;
    final secs = duration!.inSeconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }
}
