import 'package:flutter_test/flutter_test.dart';
import 'package:accounting_system/accounting/reporting/services/report_filter_service.dart';
import 'package:accounting_system/accounting/reporting/models/report_models.dart';

void main() {
  group('ReportFilterService', () {
    late ReportFilterService service;

    setUp(() {
      service = ReportFilterService();
    });

    group('applyDateRange', () {
      test('sets from and to dates', () {
        final from = DateTime(2025, 1, 1);
        final to = DateTime(2025, 12, 31);
        final filter = service.applyDateRange(const ReportFilter(), from, to);
        expect(filter.fromDate, from);
        expect(filter.toDate, to);
      });

      test('preserves other filter fields', () {
        final filter = service.applyDateRange(
          const ReportFilter(accountId: '123'),
          DateTime(2025, 1, 1),
          DateTime(2025, 12, 31),
        );
        expect(filter.accountId, '123');
      });
    });

    group('applyFinancialYear', () {
      test('sets full year range', () {
        final filter = service.applyFinancialYear(const ReportFilter(), 2025);
        expect(filter.fromDate, DateTime(2025, 1, 1));
        expect(filter.toDate, DateTime(2025, 12, 31));
      });
    });

    group('applyCurrentMonth', () {
      test('sets month start to now', () {
        final now = DateTime.now();
        final filter = service.applyCurrentMonth(const ReportFilter());
        expect(filter.fromDate!.year, now.year);
        expect(filter.fromDate!.month, now.month);
        expect(filter.fromDate!.day, 1);
      });

      test('sets toDate to now', () {
        final now = DateTime.now();
        final filter = service.applyCurrentMonth(const ReportFilter());
        expect(filter.toDate!.year, now.year);
        expect(filter.toDate!.month, now.month);
        expect(filter.toDate!.day, now.day);
      });
    });

    group('applyCurrentYear', () {
      test('sets year start to now', () {
        final now = DateTime.now();
        final filter = service.applyCurrentYear(const ReportFilter());
        expect(filter.fromDate!.year, now.year);
        expect(filter.fromDate!.month, 1);
        expect(filter.fromDate!.day, 1);
      });
    });

    group('applyAccountType', () {
      test('sets account type', () {
        final filter = service.applyAccountType(
          const ReportFilter(),
          AccountClassification.asset,
        );
        expect(filter.accountType, AccountClassification.asset);
      });
    });

    group('applyAccount', () {
      test('sets account id', () {
        final filter = service.applyAccount(const ReportFilter(), 'acc-123');
        expect(filter.accountId, 'acc-123');
      });
    });

    group('applyCurrency', () {
      test('sets currency', () {
        final filter = service.applyCurrency(const ReportFilter(), 'USD');
        expect(filter.currency, 'USD');
      });
    });

    group('applyEntity', () {
      test('sets entity type and id', () {
        final filter = service.applyEntity(const ReportFilter(), 'customer', 'C001');
        expect(filter.entityType, 'customer');
        expect(filter.entityId, 'C001');
      });
    });

    group('applySearch', () {
      test('sets search query', () {
        final filter = service.applySearch(const ReportFilter(), 'cash');
        expect(filter.searchQuery, 'cash');
      });
    });

    group('clearAll', () {
      test('returns default empty filter', () {
        final filter = service.clearAll(ReportFilter(
          fromDate: DateTime(2025, 1, 1),
          toDate: DateTime(2025, 12, 31),
          accountId: '123',
          accountType: AccountClassification.asset,
          currency: 'USD',
          searchQuery: 'test',
        ));
        expect(filter.fromDate, isNull);
        expect(filter.toDate, isNull);
        expect(filter.accountId, isNull);
        expect(filter.accountType, isNull);
        expect(filter.currency, isNull);
        expect(filter.searchQuery, isNull);
      });
    });

    group('validateFilter', () {
      test('returns no errors for valid filter', () {
        final errors = service.validateFilter(ReportFilter(
          fromDate: DateTime(2025, 1, 1),
          toDate: DateTime(2025, 12, 31),
        ));
        expect(errors, isEmpty);
      });

      test('returns error when fromDate is after toDate', () {
        final errors = service.validateFilter(ReportFilter(
          fromDate: DateTime(2025, 12, 31),
          toDate: DateTime(2025, 1, 1),
        ));
        expect(errors.length, 1);
        expect(errors[0].field, 'dateRange');
      });

      test('returns no errors when only fromDate is set', () {
        final errors = service.validateFilter(ReportFilter(
          fromDate: DateTime(2025, 1, 1),
        ));
        expect(errors, isEmpty);
      });

      test('returns no errors when dates are equal', () {
        final errors = service.validateFilter(ReportFilter(
          fromDate: DateTime(2025, 6, 15),
          toDate: DateTime(2025, 6, 15),
        ));
        expect(errors, isEmpty);
      });
    });

    group('describeFilter', () {
      test('returns No filters for empty filter', () {
        expect(service.describeFilter(const ReportFilter()), 'No filters');
      });

      test('describes date range', () {
        final filter = service.applyDateRange(
          const ReportFilter(),
          DateTime(2025, 1, 1),
          DateTime(2025, 12, 31),
        );
        final desc = service.describeFilter(filter);
        expect(desc, contains('From: 2025-01-01'));
        expect(desc, contains('To: 2025-12-31'));
      });

      test('describes all fields', () {
        final filter = ReportFilter(
          fromDate: DateTime(2025, 1, 1),
          toDate: DateTime(2025, 12, 31),
          accountId: 'acc-1',
          accountType: AccountClassification.asset,
          currency: 'USD',
        );
        final desc = service.describeFilter(filter);
        expect(desc, contains('From:'));
        expect(desc, contains('To:'));
        expect(desc, contains('Account: acc-1'));
        expect(desc, contains('Type: asset'));
        expect(desc, contains('Currency: USD'));
      });
    });

    group('describeFilterAr', () {
      test('returns Arabic text for empty filter', () {
        expect(service.describeFilterAr(const ReportFilter()), 'بدون فلاتر');
      });

      test('describes filter in Arabic', () {
        final filter = ReportFilter(
          fromDate: DateTime(2025, 1, 1),
          toDate: DateTime(2025, 12, 31),
          accountId: 'acc-1',
          accountType: AccountClassification.liability,
          currency: 'EUR',
        );
        final desc = service.describeFilterAr(filter);
        expect(desc, contains('من:'));
        expect(desc, contains('إلى:'));
        expect(desc, contains('الحساب: acc-1'));
        expect(desc, contains('النوع: خصوم'));
        expect(desc, contains('العملة: EUR'));
      });
    });
  });

  group('FilterValidationError', () {
    test('has correct fields', () {
      const error = FilterValidationError(
        field: 'dateRange',
        message: 'From date must be before to date',
        messageAr: 'يجب أن يكون التاريخ الأول قبل التاريخ الثاني',
      );
      expect(error.field, 'dateRange');
      expect(error.message, 'From date must be before to date');
      expect(error.messageAr, 'يجب أن يكون التاريخ الأول قبل التاريخ الثاني');
    });
  });
}
