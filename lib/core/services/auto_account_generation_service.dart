import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/services/account_validation_service.dart';
import 'tenant_service.dart';

enum EntityType {
  customer('customer', '1020', 'asset', 'Customer - ', 'عميل - '),
  supplier('supplier', '2000', 'liability', 'Supplier - ', 'مورد - '),
  shippingCompany('shipping_company', '2000', 'liability', 'Shipping - ', 'شركة شحن - '),
  clearingAgent('clearing_agent', '2000', 'liability', 'Agent - ', 'مخلص جمركي - '),
  shareholder('shareholder', '3000', 'equity', 'Shareholder - ', 'مساهم - ');

  final String rpcType;
  final String parentCode;
  final String accountType;
  final String namePrefix;
  final String nameArPrefix;

  const EntityType(
    this.rpcType,
    this.parentCode,
    this.accountType,
    this.namePrefix,
    this.nameArPrefix,
  );
}

class AutoAccountGenerationService {
  final _client = Supabase.instance.client;

  /// Generate the next account code for an entity type.
  Future<String> generateAccountCode(EntityType entityType) async {
    final companyId = _resolveCompanyId();
    final data = await _client.rpc('get_next_entity_account_code', params: {
      'p_entity_type': entityType.rpcType,
      'p_company_id': companyId,
    });
    return data?.toString() ?? _fallbackCode(entityType);
  }

  /// Create an account for an entity. Returns the new account ID.
  Future<int> createAccount({
    required EntityType entityType,
    required String entityName,
  }) async {
    final companyId = _resolveCompanyId();
    final code = await generateAccountCode(entityType);
    final parentId = await _resolveParentId(entityType.parentCode, companyId);

    if (parentId == null) {
      throw Exception('Parent account ${entityType.parentCode} not found');
    }

    final data = await _client
        .from('accounts')
        .insert({
          'account_code': code,
          'name': '${entityType.namePrefix}$entityName',
          'account_name': '${entityType.nameArPrefix}$entityName',
          'account_type': entityType.accountType,
          'sort_order': 10,
          'parent_id': parentId,
          'level': 5,
          'is_leaf': true,
          'allow_posting': true,
          'company_id': companyId,
        })
        .select('id')
        .single();

    return data['id'] as int;
  }

  /// Delete an account using the generic validation engine.
  Future<String?> deleteAccount(int accountId) async {
    final result = await AccountValidationService().performAction('delete', accountId.toString());
    if (result.success) return null;
    return result.message ?? 'Cannot delete account';
  }

  /// Validate whether an entity can be deleted via SQL RPC.
  Future<Map<String, dynamic>> validateDeletion({
    required EntityType entityType,
    required String entityId,
  }) async {
    final result = await _client.rpc('validate_entity_account_deletion', params: {
      'p_entity_type': entityType.rpcType,
      'p_entity_id': entityId,
    });
    return Map<String, dynamic>.from(result as Map);
  }

  /// Get linked account info for display.
  Future<Map<String, dynamic>?> getAccountInfo(int? accountId) async {
    if (accountId == null) return null;
    return await _client
        .from('accounts')
        .select('id, account_code, name, account_name, balance')
        .eq('id', accountId)
        .maybeSingle();
  }

  String _resolveCompanyId() {
    final tenantId = TenantService().tenantId;
    if (tenantId == null) throw Exception('No tenant ID set');
    return tenantId;
  }

  Future<int?> _resolveParentId(String parentCode, String companyId) async {
    final data = await _client
        .from('accounts')
        .select('id')
        .eq('account_code', parentCode)
        .eq('company_id', companyId)
        .limit(1)
        .maybeSingle();
    return data?['id'] as int?;
  }

  String _fallbackCode(EntityType entityType) {
    switch (entityType) {
      case EntityType.customer:
        return '11001';
      case EntityType.supplier:
        return '21001';
      case EntityType.shippingCompany:
        return '20001';
      case EntityType.clearingAgent:
        return '20101';
      case EntityType.shareholder:
        return '30001';
    }
  }
}
