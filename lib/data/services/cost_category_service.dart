import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chart_of_accounts_cache_service.dart';
import '../../core/data_change_event_bus.dart';

export '../models/cost_category_scope.dart';

/// Enterprise Service for Cost Category Management.
/// Automates synchronization between:
/// 1. Cost Categories (`cost_report_categories`)
/// 2. Chart of Accounts Root 3 (`accounts`)
/// 3. Operational Cost Centers (`cost_centers`)
class CostCategoryService {
  final SupabaseClient _client;

  static CostCategoryService? _instance;
  factory CostCategoryService([SupabaseClient? client]) {
    if (client != null) return CostCategoryService._internal(client);
    return _instance ??= CostCategoryService._internal(Supabase.instance.client);
  }
  CostCategoryService._internal(this._client);

  /// Resolves the canonical Root 3 parent account code based on scope, category name, and supplier type.
  /// Station operation costs map to 3124 (تكاليف ومصروفات تشغيل المحطات).
  /// Deduction fees map to 3126 (رسوم فحص وتخصيمات التشغيل).
  static String resolveParentAccountCode({
    required String scope,
    required String name,
    String? supplierType,
  }) {
    final cleanName = name.trim().toLowerCase();
    final cleanScope = scope.trim().toLowerCase();
    final cleanType = supplierType?.trim().toLowerCase();

    // 1. Station Suppliers / Operation Costs -> Level 4 Control: 3124 (تكاليف ومصروفات تشغيل المحطات)
    if (cleanType == 'station' ||
        stationSupplierCategories.contains(cleanName) ||
        RegExp(r'(محطة|تبريد|تشغيل|حفظ مبرد|تقفيل كرتون|تعتيق|تدوير|تبخير|station)').hasMatch(cleanName)) {
      return '3124';
    }

    // 2. Deduction Suppliers / Quality & Inspection -> Level 4 Control: 3126 (رسوم فحص وتخصيمات التشغيل)
    if (cleanType == 'deduction' ||
        deductionSupplierCategories.contains(cleanName) ||
        RegExp(r'(تخصيم|فحص|تحليل|عينة|عينات|حجر زراعي|سلامة غذاء|وجات|deduction|inspection)').hasMatch(cleanName)) {
      return '3126';
    }

    // 3. Packaging waste / scrap -> 3124 (هالك وفاقد التشغيل والمحاصيل)
    if (cleanScope == 'packing_waste' ||
        RegExp(r'(هالك|فاقد|تالف|توالف|waste|scrap)').hasMatch(cleanName)) {
      return '3124';
    }

    // 4. Crop purchases / raw materials -> 3411 (تكاليف المبيعات)
    if (RegExp(r'(محصول|محاصيل|شراء خام|خام|فراولة|مانجو|مبيعات|produce|crop)')
        .hasMatch(cleanName)) {
      return '3411';
    }

    // 5. Freight, Shipping, Logistics, Customs -> 3411 (مصروفات الشحن والتخليص واللوجستيات)
    if (cleanScope == 'shipment' ||
        RegExp(r'(شحن|نولون|تخليص|لوجست|مشال|نقل|جمارك|مخلص|shipping|freight|customs|logistics)')
            .hasMatch(cleanName)) {
      return '3411';
    }

    // 6. General & Administrative Scope -> Level 4 Control: 3133 / 3131 / 3132
    if (cleanType == 'admin' ||
        cleanScope == 'general_admin' ||
        cleanScope == 'admin' ||
        cleanName.contains('إدار') ||
        cleanName.contains('ادار')) {
      if (RegExp(r'(استشار|اشتراك|رسوم|أتعاب|مراجعة|legal|consulting)').hasMatch(cleanName)) {
        return '3132';
      }
      return '3133';
    }

    // 7. Scope fallbacks
    if (cleanScope == 'packing') return '3124';
    if (cleanScope == 'shipment') return '3411';
    return '3131';
  }

  /// Lists all cost categories with linked COA account and Cost Center metadata
  Future<List<Map<String, dynamic>>> listCategories({String? scope}) async {
    try {
      // 1. Try modern RPC returning joined account and cost center data
      final dynamic response = await _client.rpc(
        'list_cost_report_categories',
        params: scope != null ? {'p_scope': scope} : {},
      );

      if (response is List && response.isNotEmpty) {
        final list = response.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        // Check if modern fields are populated
        if (list.any((r) => r.containsKey('account_code') || r.containsKey('cost_center_id'))) {
          await _enrichSupplierType(list);
          return list;
        }
      }
    } catch (e) {
      debugPrint('[CostCategoryService] list RPC notice: $e');
    }

    // 2. Direct table fallback with client-side enrichment
    try {
      var query = _client.from('cost_report_categories').select('*');
      if (scope != null && scope != 'all') {
        query = query.or('scope.eq.$scope,scope.eq.both,scope.eq.all');
      }
      final rawList = await query.order('id');
      final categories = (rawList as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      // Enrich with accounts and cost centers cache
      await _enrichCategoriesWithCOAAndCostCenters(categories);
      await _enrichSupplierType(categories);
      return categories;
    } catch (e) {
      debugPrint('[CostCategoryService] Table select error: $e');
      rethrow;
    }
  }

  /// Fetches registered operational services for Station Suppliers.
  /// Dynamically queries `cost_report_categories` where `supplier_type = 'station'`.
  /// Falls back to default station categories if none registered yet.
  Future<List<String>> getStationCategories() async {
    try {
      final data = await _client
          .from('cost_report_categories')
          .select('name')
          .eq('supplier_type', 'station')
          .order('id');
      final list = (data as List)
          .map((e) => (e['name']?.toString() ?? '').trim())
          .where((name) => name.isNotEmpty)
          .toList();
      if (list.isNotEmpty) return list;
    } catch (e) {
      debugPrint('[CostCategoryService] getStationCategories query error: $e');
    }
    return List<String>.from(stationSupplierCategories);
  }

  /// Fetches registered operational deduction categories for Deductions Suppliers.
  /// Dynamically queries `cost_report_categories` where `supplier_type = 'deduction'`.
  /// Falls back to default deduction categories if none registered yet.
  Future<List<String>> getDeductionCategories() async {
    try {
      final data = await _client
          .from('cost_report_categories')
          .select('name')
          .eq('supplier_type', 'deduction')
          .order('id');
      final list = (data as List)
          .map((e) => (e['name']?.toString() ?? '').trim())
          .where((name) => name.isNotEmpty)
          .toList();
      if (list.isNotEmpty) return list;
    } catch (e) {
      debugPrint('[CostCategoryService] getDeductionCategories query error: $e');
    }
    return List<String>.from(deductionSupplierCategories);
  }

  /// Fetches registered operational services for Administrative Expenses.
  /// Dynamically queries `cost_report_categories` where `supplier_type = 'admin'`.
  /// Falls back to default admin categories if none registered yet.
  Future<List<String>> getAdminCategories() async {
    try {
      final data = await _client
          .from('cost_report_categories')
          .select('name')
          .eq('supplier_type', 'admin')
          .order('id');
      final list = (data as List)
          .map((e) => (e['name']?.toString() ?? '').trim())
          .where((name) => name.isNotEmpty)
          .toList();
      if (list.isNotEmpty) return list;
    } catch (e) {
      debugPrint('[CostCategoryService] getAdminCategories query error: $e');
    }
    return List<String>.from(adminSupplierCategories);
  }

  /// Ensures categories carry their correct `supplier_type` attribute.
  /// If the underlying RPC does not project `supplier_type`, this queries the table or standard maps.
  Future<void> _enrichSupplierType(List<Map<String, dynamic>> list) async {
    try {
      final rows = await _client
          .from('cost_report_categories')
          .select('id, name, supplier_type');
      final mapById = <dynamic, String>{};
      final mapByName = <String, String>{};
      for (final r in (rows as List)) {
        final id = r['id'];
        final name = (r['name']?.toString() ?? '').trim();
        final st = r['supplier_type']?.toString();
        if (id != null && st != null && st.isNotEmpty) mapById[id] = st;
        if (name.isNotEmpty && st != null && st.isNotEmpty) mapByName[name.toLowerCase()] = st;
      }
      for (final cat in list) {
        final id = cat['id'];
        final name = (cat['name']?.toString() ?? '').trim();
        final currentType = cat['supplier_type']?.toString();
        if (currentType == null || currentType.isEmpty || currentType == 'general') {
          if (id != null && mapById.containsKey(id)) {
            cat['supplier_type'] = mapById[id];
          } else if (mapByName.containsKey(name.toLowerCase())) {
            cat['supplier_type'] = mapByName[name.toLowerCase()];
          } else {
            cat['supplier_type'] = resolveCategorySupplierType(cat);
          }
        }
      }
    } catch (e) {
      debugPrint('[CostCategoryService] _enrichSupplierType fallback: $e');
      for (final cat in list) {
        final currentType = cat['supplier_type']?.toString();
        if (currentType == null || currentType.isEmpty || currentType == 'general') {
          cat['supplier_type'] = resolveCategorySupplierType(cat);
        }
      }
    }

  }

  /// Ensures categories carry their correct `supplier_type` attribute (public wrapper).
  Future<void> enrichSupplierType(List<Map<String, dynamic>> list) => _enrichSupplierType(list);

  /// The 9 Canonical Station Categories for UI & Forms
  static const List<String> canonicalStationCategories = [
    'تشغيل',
    'تبريد',
    'حفظ مبرد',
    'تقفيل كرتون',
    'تعتيق صادر',
    'اعادة تدوير',
    'عماله',
    'تبخير',
    'تدوير خام',
  ];

  /// The Standard Station Suppliers Categories (with search aliases)
  static const List<String> stationSupplierCategories = [
    'تشغيل',
    'تبريد',
    'حفظ مبرد',
    'تقفيل كرتون',
    'تعتيق صادر',
    'اعادة تدوير',
    'إعادة تدوير',
    'عماله',
    'عمالة',
    'تبخير',
    'تدوير خام',
  ];

  static List<String> get defaultStationCategories => canonicalStationCategories;

  /// The 9 Canonical Deduction Categories for UI & Forms
  static const List<String> canonicalDeductionCategories = [
    'رسوم فحص',
    'تخصيم عربي',
    'تخصيم اوروبي',
    'تحليل خاص',
    'تحليل هيئه',
    'سحب عينه عربي',
    'تعديل وجات',
    'دفتر حجر زراعي',
    'دفتر حجر سلامه غذاء',
  ];

  /// The Standard Deductions Suppliers Categories (with search aliases)
  static const List<String> deductionSupplierCategories = [
    'رسوم فحص',
    'تخصيم عربي',
    'تخصيم اوروبي',
    'تخصيم أوروبي',
    'تحليل خاص',
    'تحليل هيئه',
    'تحليل هيئة',
    'سحب عينه عربي',
    'سحب عينة عربي',
    'تعديل وجات',
    'دفتر حجر زراعي',
    'دفاتر حجر زراعي',
    'دفتر حجر سلامه غذاء',
    'دفاتر حجر سلامه غذاء',
    'دفتر حجر سلامة غذاء',
    'دفاتر حجر سلامة غذاء',
  ];

  static List<String> get defaultDeductionCategories => canonicalDeductionCategories;

  /// Standard Administrative Expenses Categories (تصنيفات المصاريف الإدارية)
  static const List<String> adminSupplierCategories = [
    'مصاريف إدارية',
    'مصاريف إدارية وعمومية',
    'أتعاب واستشارات إدارية',
    'رسوم واشتراكات وتراخيص',
    'انتقالات وضيافة إدارية',
    'مصاريف بنكية وإدارية',
    'مصاريف تشغيل إدارية',
  ];

  static List<String> get defaultAdminCategories => adminSupplierCategories;

  /// Mapping of supported supplier types and display labels with icons
  static const Map<String, String> supplierTypeOptions = {
    'station': 'موردي المحطات 🏭',
    'deduction': 'موردي التخصيمات 📋',
    'admin': 'مصاريف إدارية 💼',
    'transport': 'موردي النقل 🚛',
    'packaging': 'موردي مواد التعبئة 📦',
    'crop': 'موردي المحاصيل 🌾',
    'general': 'عام / أخرى 🌐',
  };

  /// Resolves the canonical supplier type label in Arabic
  static String getSupplierTypeLabel(String? type) {
    if (type == null || type.isEmpty) return 'عام / أخرى 🌐';
    return supplierTypeOptions[type.toLowerCase()] ?? type;
  }

  /// Creates a new cost category, automatically creating:
  /// 1. A sub-account under Root 3 in Chart of Accounts
  /// 2. A designated Cost Center in public.cost_centers
  /// 3. Returns the enriched category row
  Future<Map<String, dynamic>> createCategory({
    required String name,
    required String scope,
    String? parentAccountCode,
    String? supplierType,
  }) async {
    final cleanName = name.trim();

    // Auto-resolve supplierType if not explicitly specified
    String effectiveSupplierType = supplierType ?? 'general';
    if (supplierType == null || supplierType == 'general') {
      if (stationSupplierCategories.contains(cleanName)) {
        effectiveSupplierType = 'station';
      } else if (deductionSupplierCategories.contains(cleanName)) {
        effectiveSupplierType = 'deduction';
      } else if (adminSupplierCategories.contains(cleanName) || cleanName.contains('إدار') || cleanName.contains('ادار')) {
        effectiveSupplierType = 'admin';
      }
    }

    final parentCode = parentAccountCode ??
        resolveParentAccountCode(
          scope: scope,
          name: cleanName,
          supplierType: effectiveSupplierType,
        );

    Map<String, dynamic> result = {};

    // 1. Call create RPC
    try {
      final dynamic rpcResult = await _client.rpc(
        'create_cost_report_category',
        params: {
          'p_name': cleanName,
          'p_scope': scope,
          'p_parent_code': parentCode,
          'p_supplier_type': effectiveSupplierType,
        },
      );

      if (rpcResult is Map) {
        result = Map<String, dynamic>.from(rpcResult);
      }
    } catch (e) {
      debugPrint('[CostCategoryService] RPC create error: $e. Falling back to direct insert.');
      // Fallback: direct table insert
      final res = await _client
          .from('cost_report_categories')
          .insert({
            'name': cleanName,
            'scope': scope,
            'supplier_type': effectiveSupplierType,
            'is_system': false,
            'type': 'direct',
          })
          .select()
          .single();
      result = Map<String, dynamic>.from(res);
    }

    final categoryId = result['id'] ?? result['p_id'];

    // 2. Ensure Client-side COA Sub-Account and Cost Center if not populated by DB trigger
    if (result['account_id'] == null || result['cost_center_id'] == null) {
      final synced = await _ensureCOAAndCostCenterForCategory(
        categoryId: categoryId,
        categoryName: cleanName,
        scope: scope,
        parentCode: parentCode,
        supplierType: effectiveSupplierType,
      );
      result.addAll(synced);
    }

    // 3. Invalidate Chart of Accounts cache so the new account is immediately available
    ChartOfAccountsCacheService().invalidate();
    try {
      await ChartOfAccountsCacheService().refresh();
    } catch (_) {}

    DataChangeEventBus.instance.notifyCostCategoriesChanged();
    return result;
  }

  /// Updates an existing category name, scope, or linked accounts
  Future<void> updateCategory({
    required int id,
    String? name,
    String? scope,
    int? accountId,
    String? costCenterId,
    String? supplierType,
  }) async {
    try {
      await _client.rpc('update_cost_report_category', params: {
        'p_id': id,
        if (name != null) 'p_name': name.trim(),
        if (scope != null) 'p_scope': scope,
        if (accountId != null) 'p_account_id': accountId,
        if (costCenterId != null) 'p_cost_center_id': costCenterId,
        if (supplierType != null) 'p_supplier_type': supplierType,
      });
    } catch (e) {
      debugPrint('[CostCategoryService] update RPC error: $e. Direct table update.');
      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name.trim();
      if (scope != null) updates['scope'] = scope;
      if (accountId != null) updates['account_id'] = accountId;
      if (costCenterId != null) updates['cost_center_id'] = costCenterId;
      if (supplierType != null) updates['supplier_type'] = supplierType;

      if (updates.isNotEmpty) {
        await _client.from('cost_report_categories').update(updates).eq('id', id);
      }
    }

    try {
      ChartOfAccountsCacheService().invalidate();
    } catch (_) {}

    DataChangeEventBus.instance.notifyCostCategoriesChanged();
  }

  /// Seeds or ensures standard Station (9) and Deductions (9) categories exist and are properly mapped
  Future<int> seedStandardSupplierCategories() async {
    int updatedCount = 0;
    try {
      final existing = await _client.from('cost_report_categories').select('id, name, supplier_type, scope');
      final existingMap = <String, Map<String, dynamic>>{};
      for (final row in (existing as List)) {
        final r = Map<String, dynamic>.from(row as Map);
        existingMap[(r['name']?.toString() ?? '').trim()] = r;
      }

      // 1. Station categories
      for (final catName in stationSupplierCategories) {
        if (!existingMap.containsKey(catName)) {
          await createCategory(
            name: catName,
            scope: 'packing',
            supplierType: 'station',
            parentAccountCode: '3124',
          );
          updatedCount++;
        } else {
          final row = existingMap[catName]!;
          if (row['supplier_type'] != 'station' || row['account_id'] == null) {
            await updateCategory(
              id: row['id'] as int,
              name: catName,
              scope: 'packing',
              supplierType: 'station',
            );
            if (row['account_id'] == null) {
              await _ensureCOAAndCostCenterForCategory(
                categoryId: row['id'],
                categoryName: catName,
                scope: 'packing',
                parentCode: '3124',
                supplierType: 'station',
              );
            }
            updatedCount++;
          }
        }
      }

      // 2. Deduction categories
      for (final catName in deductionSupplierCategories) {
        if (!existingMap.containsKey(catName)) {
          await createCategory(
            name: catName,
            scope: 'packing',
            supplierType: 'deduction',
            parentAccountCode: '3126',
          );
          updatedCount++;
        } else {
          final row = existingMap[catName]!;
          if (row['supplier_type'] != 'deduction' || row['account_id'] == null) {
            await updateCategory(
              id: row['id'] as int,
              name: catName,
              scope: 'packing',
              supplierType: 'deduction',
            );
            if (row['account_id'] == null) {
              await _ensureCOAAndCostCenterForCategory(
                categoryId: row['id'],
                categoryName: catName,
                scope: 'packing',
                parentCode: '3126',
                supplierType: 'deduction',
              );
            }
            updatedCount++;
          }
        }
      }

      // 3. Admin categories
      for (final catName in adminSupplierCategories) {
        if (!existingMap.containsKey(catName)) {
          await createCategory(
            name: catName,
            scope: 'all',
            supplierType: 'admin',
            parentAccountCode: '3133',
          );
          updatedCount++;
        } else {
          final row = existingMap[catName]!;
          if (row['supplier_type'] != 'admin' || row['account_id'] == null) {
            await updateCategory(
              id: row['id'] as int,
              name: catName,
              scope: 'all',
              supplierType: 'admin',
            );
            if (row['account_id'] == null) {
              await _ensureCOAAndCostCenterForCategory(
                categoryId: row['id'],
                categoryName: catName,
                scope: 'all',
                parentCode: '3133',
                supplierType: 'admin',
              );
            }
            updatedCount++;
          }
        }
      }
    } catch (e) {
      debugPrint('[CostCategoryService] seedStandardSupplierCategories error: $e');
    }

    if (updatedCount > 0) {
      DataChangeEventBus.instance.notifyCostCategoriesChanged();
    }

    return updatedCount;
  }

  /// Deletes a cost category
  Future<void> deleteCategory(dynamic id) async {
    try {
      await _client.rpc('delete_cost_report_category', params: {'p_id': id});
    } catch (e) {
      await _client.from('cost_report_categories').delete().eq('id', id);
    }
    try {
      ChartOfAccountsCacheService().invalidate();
    } catch (_) {}

    DataChangeEventBus.instance.notifyCostCategoriesChanged();
  }

  /// Helper: Enriches category rows with account and cost center details
  Future<void> _enrichCategoriesWithCOAAndCostCenters(
      List<Map<String, dynamic>> categories) async {
    try {
      final accounts = await _client
          .from('accounts')
          .select('id, account_code, account_name, name, cost_center_id')
          .like('account_code', '3%')
          .filter('deleted_at', 'is', null);

      final costCenters = await _client.from('cost_centers').select('code, name, name_ar');

      final acctList = (accounts as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final ccList = (costCenters as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

      for (var cat in categories) {
        final catName = (cat['name'] as String? ?? '').trim().toLowerCase();
        final rawAcctId = cat['account_id'];
        final rawCcId = cat['cost_center_id']?.toString();

        // 1. Match Account
        Map<String, dynamic>? matchedAcct;
        if (rawAcctId != null) {
          matchedAcct = acctList.firstWhere(
            (a) => a['id'] == rawAcctId,
            orElse: () => {},
          );
        }
        if (matchedAcct == null || matchedAcct.isEmpty) {
          matchedAcct = acctList.firstWhere(
            (a) =>
                (a['account_name']?.toString().trim().toLowerCase() == catName) ||
                (a['name']?.toString().trim().toLowerCase() == catName),
            orElse: () => {},
          );
        }

        if (matchedAcct.isNotEmpty) {
          cat['account_id'] ??= matchedAcct['id'];
          cat['account_code'] = matchedAcct['account_code'];
          cat['account_name'] = matchedAcct['account_name'] ?? matchedAcct['name'];
        }

        // 2. Match Cost Center
        final ccCode = rawCcId ?? 'CC-CAT-${cat['id']}';
        final matchedCc = ccList.firstWhere(
          (c) => c['code'] == ccCode || c['code'] == rawCcId,
          orElse: () => {},
        );

        cat['cost_center_id'] = ccCode;
        cat['cost_center_name'] = matchedCc['name_ar'] ?? matchedCc['name'] ?? cat['name'];
      }
    } catch (e) {
      debugPrint('[CostCategoryService] Enrichment notice: $e');
    }
  }

  /// Helper: Ensures sub-account in COA and Cost Center record exist
  Future<Map<String, dynamic>> _ensureCOAAndCostCenterForCategory({
    required dynamic categoryId,
    required String categoryName,
    required String scope,
    required String parentCode,
    String? supplierType,
  }) async {
    final result = <String, dynamic>{};

    // 1. Resolve or Create Sub-Account in public.accounts under the correct parent node (COA Root 3)
    try {
      // 1a. Check if account already exists under Root 3
      final existingAccounts = await _client
          .from('accounts')
          .select('id, account_code, account_name, name')
          .or('account_name.eq.$categoryName,name.eq.$categoryName')
          .like('account_code', '3%')
          .filter('deleted_at', 'is', null)
          .limit(1);

      if ((existingAccounts as List).isNotEmpty) {
        final existing = Map<String, dynamic>.from(existingAccounts.first as Map);
        result['account_id'] = existing['id'];
        result['account_code'] = existing['account_code'];
        result['account_name'] = existing['account_name'] ?? existing['name'];
      } else {
        // 2b. Query active parent node from accounts table
        Map<String, dynamic>? parentNode;

        // Try exact parentCode
        final parentRes = await _client
            .from('accounts')
            .select('id, account_code, level, company_id')
            .eq('account_code', parentCode)
            .filter('deleted_at', 'is', null)
            .limit(1);

        if ((parentRes as List).isNotEmpty) {
          parentNode = Map<String, dynamic>.from(parentRes.first as Map);
        } else {
          // If 3124 or 3126 doesn't exist, check under 312
          final p312Res = await _client
              .from('accounts')
              .select('id, account_code, level, company_id')
              .eq('account_code', '312')
              .filter('deleted_at', 'is', null)
              .limit(1);

          if ((p312Res as List).isNotEmpty) {
            final p312 = Map<String, dynamic>.from(p312Res.first as Map);
            final isStation = supplierType == 'station' || parentCode == '3124';
            final ctrlCode = isStation ? '3124' : '3126';
            final ctrlName = isStation ? 'تكاليف ومصروفات تشغيل المحطات' : 'رسوم فحص وتخصيمات التشغيل';
            final ctrlNameEn = isStation ? 'Station Packing & Operations Control' : 'Inspection & Deduction Fees Control';

            try {
              final insCtrl = await _client.from('accounts').insert({
                'account_code': ctrlCode,
                'account_name': ctrlName,
                'name': ctrlNameEn,
                'account_type': 'expense',
                'normal_balance': 'Debit',
                'level': 4,
                'is_leaf': false,
                'allow_posting': false,
                'is_active': true,
                'parent_id': p312['id'],
                'company_id': p312['company_id'],
              }).select('id, account_code, level, company_id').single();
              parentNode = Map<String, dynamic>.from(insCtrl);
            } catch (_) {
              final recheck = await _client
                  .from('accounts')
                  .select('id, account_code, level, company_id')
                  .eq('account_code', ctrlCode)
                  .limit(1);
              if ((recheck as List).isNotEmpty) {
                parentNode = Map<String, dynamic>.from(recheck.first as Map);
              }
            }
          }
        }

        // Ultimate fallback: any active expense account under 31
        if (parentNode == null) {
          final fallbackRes = await _client
              .from('accounts')
              .select('id, account_code, level, company_id')
              .like('account_code', '31%')
              .filter('deleted_at', 'is', null)
              .limit(1);
          if ((fallbackRes as List).isNotEmpty) {
            parentNode = Map<String, dynamic>.from(fallbackRes.first as Map);
          }
        }

        if (parentNode != null) {
          final targetParentCode = parentNode['account_code'].toString();
          final parentId = parentNode['id'];
          final companyId = parentNode['company_id'];

          // 2c. Find existing children under parent to allocate next sequential code
          final childrenRes = await _client
              .from('accounts')
              .select('account_code')
              .like('account_code', '$targetParentCode%')
              .filter('deleted_at', 'is', null);

          final existingCodes = (childrenRes as List)
              .map((c) => c['account_code']?.toString() ?? '')
              .toSet();

          const obsoleteCodes = {
            '3121', '3123', '3212', '3222', '3223', '3224', '3412', '341', '3411',
          };

          String nextCode = '';
          for (int i = 1; i <= 9; i++) {
            final candidate = '$targetParentCode$i';
            if (!existingCodes.contains(candidate) && !obsoleteCodes.contains(candidate)) {
              nextCode = candidate;
              break;
            }
          }

          if (nextCode.isEmpty) {
            for (int i = 1; i <= 99; i++) {
              final candidate = '$targetParentCode${i.toString().padLeft(2, '0')}';
              if (!existingCodes.contains(candidate) && !obsoleteCodes.contains(candidate)) {
                nextCode = candidate;
                break;
              }
            }
          }

          if (nextCode.isNotEmpty) {
            // 2d. Insert new sub-account at Level 5
            final newAcct = await _client.from('accounts').insert({
              'account_code': nextCode,
              'account_name': categoryName,
              'name': categoryName,
              'account_type': 'expense',
              'normal_balance': 'Debit',
              'level': 5,
              'is_leaf': true,
              'allow_posting': true,
              'is_active': true,
              'parent_id': parentId,
              'company_id': companyId,
            }).select('id, account_code, account_name, name').single();

            result['account_id'] = newAcct['id'];
            result['account_code'] = newAcct['account_code'];
            result['account_name'] = newAcct['account_name'] ?? newAcct['name'] ?? categoryName;
          }
        }
      }
    } catch (e) {
      debugPrint('[CostCategoryService] Sub-account creation error: $e');
    }

    // 3. Update category row
    try {
      final updates = <String, dynamic>{};
      if (result['account_id'] != null) updates['account_id'] = result['account_id'];
      if (result['cost_center_id'] != null) updates['cost_center_id'] = result['cost_center_id'];
      if (supplierType != null) updates['supplier_type'] = supplierType;
      if (updates.isNotEmpty) {
        await _client.from('cost_report_categories').update(updates).eq('id', categoryId);
      }
    } catch (e) {
      debugPrint('[CostCategoryService] Category update error: $e');
    }

    return result;
  }

  /// Normalizes supplier type aliases used across packing dialogs and categories.
  static String normalizeSupplierType(String? supplierType) {
    final raw = (supplierType ?? '').toLowerCase().trim();
    switch (raw) {
      case 'station':
      case 'stations':
        return 'station';
      case 'deduction':
      case 'deductions':
        return 'deduction';
      case 'admin':
      case 'administrative':
        return 'admin';
      case 'transport':
      case 'logistics':
        return 'transport';
      case 'engineer':
      case 'engineers':
      case 'engineer_expenses':
        return 'engineer';
      case '':
      case 'general':
      case 'packaging':
      case 'crop':
      case 'materials':
      case 'other':
      case 'all':
      default:
        return 'general';
    }
  }

  /// Resolves the canonical supplier type ('station', 'deduction', 'admin',
  /// 'transport', 'engineer', or 'general') for a cost report category row.
  static String resolveCategorySupplierType(Map<String, dynamic> category) {
    final rawType =
        (category['supplier_type'] ?? '').toString().toLowerCase().trim();
    if (rawType == 'station' || rawType == 'stations') return 'station';
    if (rawType == 'deduction' || rawType == 'deductions') return 'deduction';
    if (rawType == 'admin' || rawType == 'administrative') return 'admin';
    if (rawType == 'transport' || rawType == 'logistics') return 'transport';
    if (rawType == 'engineer' ||
        rawType == 'engineers' ||
        rawType == 'engineer_expenses') {
      return 'engineer';
    }
    if (rawType == 'packaging' || rawType == 'crop' || rawType == 'materials') {
      return 'general';
    }

    final name = (category['name'] ?? '').toString().trim();
    final categoryKey =
        (category['category'] ?? '').toString().toLowerCase().trim();
    if (name.isEmpty || name == 'أخرى') {
      return 'general';
    }

    if (adminSupplierCategories.contains(name) ||
        name == 'مصاريف إدارية' ||
        name.contains('إدار') ||
        name.contains('ادار')) {
      return 'admin';
    }

    if (name == 'مصاريف مهندسين' ||
        name.contains('مهندس') ||
        name.contains('مهندسين') ||
        categoryKey == 'engineer_expenses' ||
        categoryKey == 'engineer') {
      return 'engineer';
    }

    if (stationSupplierCategories.contains(name) ||
        name.contains('محطة') ||
        name.contains('تبريد') ||
        name.contains('تشغيل') ||
        name.contains('تبخير') ||
        name.contains('تعتيق') ||
        name.contains('حفظ مبرد') ||
        name.contains('تقفيل كرتون') ||
        name.contains('اعادة تدوير') ||
        name.contains('إعادة تدوير') ||
        name.contains('عماله') ||
        name.contains('عمالة') ||
        name.contains('تدوير خام')) {
      return 'station';
    }

    if (deductionSupplierCategories.contains(name) ||
        name.contains('تخصيم') ||
        name.contains('حجر') ||
        name.contains('تحليل') ||
        name.contains('فحص') ||
        name.contains('عينه') ||
        name.contains('عينة') ||
        name.contains('وجات') ||
        name.contains('سلامه غذاء') ||
        name.contains('سلامة غذاء')) {
      return 'deduction';
    }

    if (name.contains('نقل') ||
        name.contains('شحن') ||
        name.contains('لوجستيك') ||
        categoryKey == 'logistics') {
      return 'transport';
    }

    return 'general';
  }

  /// Filters cost report categories so only items belonging strictly to
  /// [supplierType] are returned as an ordered `{id: name}` map.
  static Map<int, String> filterCategoriesBySupplierType(
    List<Map<String, dynamic>> categories, {
    required String supplierType,
  }) {
    final targetType = normalizeSupplierType(supplierType);
    final filtered = <int, String>{};
    for (final category in categories) {
      final rawId = category['id'];
      final int? id =
          rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
      final name = (category['name'] ?? '').toString().trim();
      if (id == null || name.isEmpty) continue;
      if (resolveCategorySupplierType(category) == targetType) {
        filtered[id] = name;
      }
    }
    return filtered;
  }

  /// Resolves the valid category id when opening a dialog or switching supplier type.
  static int? resolveSelectedCategoryIdForSupplierType({
    required int? currentCategoryId,
    required Map<int, String> filteredCategories,
    required String supplierType,
  }) {
    final targetType = normalizeSupplierType(supplierType);
    if (targetType == 'transport' || targetType == 'engineer') {
      return null;
    }
    if (currentCategoryId != null &&
        filteredCategories.containsKey(currentCategoryId)) {
      return currentCategoryId;
    }
    return filteredCategories.isNotEmpty ? filteredCategories.keys.first : null;
  }

  /// Checks whether the current item name is empty or an auto-filled category/system label
  /// so switching supplier tabs or categories only updates non-custom item names.
  static bool isAutoGeneratedItemName(
    String currentName,
    Iterable<String> allCategoryNames,
  ) {
    final trimmed = currentName.trim();
    if (trimmed.isEmpty ||
        trimmed == 'أخرى' ||
        trimmed == 'مصاريف إدارية' ||
        trimmed == 'مصاريف نقل' ||
        trimmed == 'نقل بضاعة' ||
        trimmed == 'مصاريف مهندسين وإشراف' ||
        trimmed.startsWith('مصاريف نقل') ||
        trimmed.startsWith('خدمات محطة') ||
        trimmed.startsWith('تخصيمات')) {
      return true;
    }
    for (final catName in allCategoryNames) {
      if (catName.trim() == trimmed) return true;
    }
    return false;
  }
}
