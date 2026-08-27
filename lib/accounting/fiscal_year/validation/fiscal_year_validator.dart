import '../models/fiscal_year.dart';
import '../models/fiscal_year_status.dart';

class FiscalYearValidator {
  List<String> validateCreate(FiscalYear fy) => _commonChecks(fy);

  List<String> validateUpdate(FiscalYear fy) => _commonChecks(fy);

  List<String> _commonChecks(FiscalYear fy) {
    final errors = <String>[];
    if (fy.startDate.isAfter(fy.endDate) || fy.startDate.isAtSameMomentAs(fy.endDate)) {
      errors.add('Start date must be before end date');
    }
    if (fy.year <= 0) {
      errors.add('Year must be a positive integer');
    }
    if (fy.name.isEmpty) {
      errors.add('Name cannot be empty');
    }
    return errors;
  }

  Future<List<String>> validateStatusTransition(FiscalYear current, FiscalYearStatus newStatus) async {
    final errors = <String>[];

    switch (newStatus) {
      case FiscalYearStatus.draft:
        if (current.status != FiscalYearStatus.draft) {
          errors.add('يمكن فقط للسنة المالية في حالة مسودة البقاء مسودة');
        }
        break;
      case FiscalYearStatus.active:
        if (!current.status.canTransitionToActive) {
          errors.add('لا يمكن تفعيل السنة المالية من حالة ${current.status.displayNameAr}');
        }
        break;
      case FiscalYearStatus.closing:
        if (!current.status.canTransitionToClosing) {
          errors.add('لا يمكن إغلاق السنة المالية من حالة ${current.status.displayNameAr}');
        }
        break;
      case FiscalYearStatus.closed:
        if (!current.status.canTransitionToClosed) {
          errors.add('لا يمكن إنهاء الإغلاق من حالة ${current.status.displayNameAr}');
        }
        break;
      case FiscalYearStatus.archived:
        if (!current.status.canTransitionToArchived) {
          errors.add('لا يمكن أرشفة السنة المالية من حالة ${current.status.displayNameAr}');
        }
        break;
    }

    return errors;
  }
}
