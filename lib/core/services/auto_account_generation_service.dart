import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/services/account_validation_service.dart';
import 'tenant_service.dart';

enum EntityType {
  customer('customer', '1251', 'asset', 'Customer - ', 'عميل - '),
  cropSupplier('crop_supplier', '2111', 'liability', 'Crop Supplier - ', 'مورد محاصيل - '),
  supplier('supplier', '2111', 'liability', 'Supplier - ', 'مورد - '),
  sharedSupplier('shared_supplier', '2111', 'liability', 'Shared Supplier - ', 'مورد مشترك - '),
  transportSupplier('transport_supplier', '2111', 'liability', 'Transporter - ', 'مورد نقل - '),
  notesPayable('notes_payable', '2112', 'liability', 'Notes Payable - ', 'أوراق دفع - '),
  shippingCompany('shipping_company', '2111', 'liability', 'Shipping - ', 'شركة شحن - '),
  clearingAgent('clearing_agent', '2111', 'liability', 'Clearing Agent - ', 'مخلص جمركي - '),
  packagingSupplier('packaging_supplier', '2111', 'liability', 'Packaging Supplier - ', 'مورد تعبئة - '),
  stationSupplier('station_supplier', '2111', 'liability', 'Packaging Station - ', 'محطة تعبئة - '),
  shareholder('shareholder', '2321', 'equity', 'Shareholder - ', 'مساهم - ');

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

  /// Dynamically maps a business supplier category type to its standardized Level 4 EntityType.
  static EntityType resolveSupplierEntityType(String? supplierType) {
    if (supplierType == null) return EntityType.supplier;
    switch (supplierType.trim().toLowerCase()) {
      case 'packaging':
        return EntityType.packagingSupplier;
      case 'station':
        return EntityType.stationSupplier;
      case 'shipping':
        return EntityType.shippingCompany;
      case 'clearing':
      case 'customs':
        return EntityType.clearingAgent;
      case 'transport':
        return EntityType.transportSupplier;
      case 'shared':
        return EntityType.sharedSupplier;
      case 'crop':
      default:
        return EntityType.cropSupplier;
    }
  }

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
  /// Dynamically nests under the Level 4 parent, assigning level = 5, is_leaf = true, and allow_posting = true.
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

  /// Create a dynamic sub-account for a supplier/vendor based on their category type.
  /// Automatically routes to Level 4 parent (e.g. 2111 for crop, 2115 for packaging),
  /// setting level = 5, is_leaf = true, and allow_posting = true.
  Future<int> createSupplierSubAccount({
    required String supplierType,
    required String supplierName,
  }) async {
    final entityType = resolveSupplierEntityType(supplierType);
    return createAccount(
      entityType: entityType,
      entityName: supplierName,
    );
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
    try {
      var query = _client
          .from('accounts')
          .select('id')
          .eq('account_code', parentCode);

      if (companyId.isNotEmpty) {
        query = query.or('company_id.eq.$companyId,company_id.is.null,company_id.eq.a0000000-0000-0000-0000-000000000001');
      }

      final data = await query.order('company_id', ascending: false).limit(1).maybeSingle();
      if (data != null && data['id'] != null) {
        return (data['id'] as num).toInt();
      }

      final fallback = await _client
          .from('accounts')
          .select('id')
          .eq('account_code', parentCode)
          .limit(1)
          .maybeSingle();
      return (fallback?['id'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  String _fallbackCode(EntityType entityType) {
    switch (entityType) {
      case EntityType.customer:
        return '125101';
      case EntityType.cropSupplier:
      case EntityType.supplier:
      case EntityType.sharedSupplier:
      case EntityType.transportSupplier:
      case EntityType.shippingCompany:
      case EntityType.clearingAgent:
      case EntityType.packagingSupplier:
      case EntityType.stationSupplier:
        return '211101';
      case EntityType.notesPayable:
        return '211201';
      case EntityType.shareholder:
        return '23211';
    }
  }
}
