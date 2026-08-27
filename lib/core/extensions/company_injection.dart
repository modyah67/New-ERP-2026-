import '../services/tenant_service.dart';

extension CompanyInjectionMap on Map<String, dynamic> {
  Map<String, dynamic> withCompanyId() {
    final companyId = TenantService().tenantId;
    if (companyId != null && !containsKey('company_id')) {
      this['company_id'] = companyId;
    }
    return this;
  }
}

extension CompanyInjectionList on List<Map<String, dynamic>> {
  List<Map<String, dynamic>> withCompanyId() {
    return map((e) => e.withCompanyId()).toList();
  }
}
