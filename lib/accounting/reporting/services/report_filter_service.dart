/// ReportFilterService — Reusable filter engine for financial reports
library;

import '../models/report_models.dart';

class ReportFilterService {
  ReportFilter applyDateRange(ReportFilter filter, DateTime from, DateTime to) {
    return filter.copyWith(fromDate: from, toDate: to);
  }

  ReportFilter applyFinancialYear(ReportFilter filter, int year) {
    return filter.copyWith(
      fromDate: DateTime(year, 1, 1),
      toDate: DateTime(year, 12, 31),
    );
  }

  ReportFilter applyCurrentMonth(ReportFilter filter) {
    final now = DateTime.now();
    return filter.copyWith(
      fromDate: DateTime(now.year, now.month, 1),
      toDate: now,
    );
  }

  ReportFilter applyCurrentYear(ReportFilter filter) {
    final now = DateTime.now();
    return filter.copyWith(
      fromDate: DateTime(now.year, 1, 1),
      toDate: now,
    );
  }

  ReportFilter applyAccountType(ReportFilter filter, AccountClassification type) {
    return filter.copyWith(accountType: type);
  }

  ReportFilter applyAccount(ReportFilter filter, String accountId) {
    return filter.copyWith(accountId: accountId);
  }

  ReportFilter applyCurrency(ReportFilter filter, String currency) {
    return filter.copyWith(currency: currency);
  }

  ReportFilter applyEntity(ReportFilter filter, String entityType, String entityId) {
    return filter.copyWith(entityType: entityType, entityId: entityId);
  }

  ReportFilter applySearch(ReportFilter filter, String query) {
    return filter.copyWith(searchQuery: query);
  }

  ReportFilter clearAll(ReportFilter filter) {
    return const ReportFilter();
  }

  List<FilterValidationError> validateFilter(ReportFilter filter) {
    final errors = <FilterValidationError>[];
    if (filter.fromDate != null &&
        filter.toDate != null &&
        filter.fromDate!.isAfter(filter.toDate!)) {
      errors.add(FilterValidationError(
        field: 'dateRange',
        message: 'From date must be before to date',
        messageAr: 'يجب أن يكون التاريخ الأول قبل التاريخ الثاني',
      ));
    }
    return errors;
  }

  String describeFilter(ReportFilter filter) {
    final parts = <String>[];
    if (filter.fromDate != null) parts.add('From: ${_formatDate(filter.fromDate!)}');
    if (filter.toDate != null) parts.add('To: ${_formatDate(filter.toDate!)}');
    if (filter.accountId != null) parts.add('Account: ${filter.accountId}');
    if (filter.accountType != null) parts.add('Type: ${filter.accountType!.labelEn}');
    if (filter.currency != null) parts.add('Currency: ${filter.currency}');
    return parts.isEmpty ? 'No filters' : parts.join(' | ');
  }

  String describeFilterAr(ReportFilter filter) {
    final parts = <String>[];
    if (filter.fromDate != null) parts.add('من: ${_formatDate(filter.fromDate!)}');
    if (filter.toDate != null) parts.add('إلى: ${_formatDate(filter.toDate!)}');
    if (filter.accountId != null) parts.add('الحساب: ${filter.accountId}');
    if (filter.accountType != null) parts.add('النوع: ${filter.accountType!.labelAr}');
    if (filter.currency != null) parts.add('العملة: ${filter.currency}');
    return parts.isEmpty ? 'بدون فلاتر' : parts.join(' | ');
  }

  String _formatDate(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

class FilterValidationError {
  final String field;
  final String message;
  final String messageAr;

  const FilterValidationError({
    required this.field,
    required this.message,
    required this.messageAr,
  });
}
