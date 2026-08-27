import '../models/fiscal_year.dart';
import '../models/fiscal_year_status.dart';
import '../dao/fiscal_year_dao.dart';
import '../validation/fiscal_year_validator.dart';

class FiscalYearService {
  final FiscalYearDao _dao;
  final FiscalYearValidator _validator;

  FiscalYearService({FiscalYearDao? dao})
      : _dao = dao ?? FiscalYearDao(),
        _validator = FiscalYearValidator();

  Future<List<FiscalYear>> getAll() => _dao.getAll();
  Future<FiscalYear?> getCurrent() => _dao.getCurrent();
  Future<FiscalYear?> getById(int id) => _dao.getById(id);
  Future<bool> exists(int year) => _dao.exists(year);

  Future<List<FiscalYear>> getClosedYears() => _dao.getClosedYears();
  Future<List<FiscalYear>> getActiveYears() => _dao.getActiveYears();

  Future<FiscalYear> createFiscalYear(FiscalYear fy) async {
    final errors = _validator.validateCreate(fy);
    if (errors.isNotEmpty) {
      throw Exception('Fiscal year validation failed: ${errors.join(", ")}');
    }
    return _dao.create(fy);
  }

  Future<FiscalYear> updateFiscalYear(FiscalYear fy) async {
    final errors = _validator.validateUpdate(fy);
    if (errors.isNotEmpty) {
      throw Exception('Fiscal year validation failed: ${errors.join(", ")}');
    }
    return _dao.update(fy);
  }

  Future<void> setCurrent(int id, {String? performedBy, String? reason}) =>
      _dao.setCurrent(id, performedBy: performedBy, reason: reason);

  Future<void> closeFiscalYear(int id, {String? performedBy, String? reason}) =>
      _dao.closeStatus(id, performedBy: performedBy, reason: reason);

  Future<void> reopenFiscalYear(int id, {String? performedBy, String? reason}) =>
      _dao.reopenStatus(id, performedBy: performedBy, reason: reason);

  Future<void> archiveFiscalYear(int id, {String? performedBy}) =>
      _dao.archive(id, performedBy: performedBy);

  Future<void> setStatus(int id, FiscalYearStatus status, {String? performedBy, String? reason}) =>
      _dao.updateStatus(id, status: status, performedBy: performedBy, reason: reason);

  Future<bool> isDateInClosedFiscalYear(DateTime date) =>
      _dao.isDateInClosedFiscalYear(date);
}
