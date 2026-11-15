// lib/core/database_seeder.dart
// ─────────────────────────────────────────────────────────────────────────────
// Official Master Database Seeder & Parity Enforcer for "Fruity Farms" ERP.
// Strictly populates standardized financial department codes and exact names
// from the official ledger (الموردين.pdf) without random/auto-prefix generation.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:supabase/supabase.dart';

/// Representation of an official ledger entity from الموردين.pdf
class OfficialMasterEntity {
  final String code;
  final String name;
  final String categoryGroup;
  final String entityType; // 'crop', 'packaging', 'transport', 'station', 'shipping'

  const OfficialMasterEntity({
    required this.code,
    required this.name,
    required this.categoryGroup,
    required this.entityType,
  });
}

class DatabaseSeeder {
  DatabaseSeeder._();

  // ───────────────────────────────────────────────────────────────────────────
  // OFFICIAL MASTER DATASET (الموردين.pdf)
  // ───────────────────────────────────────────────────────────────────────────

  /// Group 5: موردين المحاصيل (501 to 518)
  static const List<OfficialMasterEntity> cropSuppliers = [
    OfficialMasterEntity(code: '501', name: 'مورد محاصيل - الحاج ياسر', categoryGroup: 'موردين المحاصيل', entityType: 'crop'),
    OfficialMasterEntity(code: '502', name: 'مورد محاصيل - وليد رزقانه', categoryGroup: 'موردين المحاصيل', entityType: 'crop'),
    OfficialMasterEntity(code: '503', name: 'مورد محاصيل - الحاج اسماعيل', categoryGroup: 'موردين المحاصيل', entityType: 'crop'),
    OfficialMasterEntity(code: '504', name: 'مورد محاصيل - محمد رزق', categoryGroup: 'موردين المحاصيل', entityType: 'crop'),
    OfficialMasterEntity(code: '505', name: 'مورد محاصيل - ابو عبد الله', categoryGroup: 'موردين المحاصيل', entityType: 'crop'),
    OfficialMasterEntity(code: '506', name: 'مورد محاصيل - شركه بنو', categoryGroup: 'موردين المحاصيل', entityType: 'crop'),
    OfficialMasterEntity(code: '507', name: 'مورد محاصيل - رضا', categoryGroup: 'موردين المحاصيل', entityType: 'crop'),
    OfficialMasterEntity(code: '508', name: 'مورد محاصيل - مصطفى', categoryGroup: 'موردين المحاصيل', entityType: 'crop'),
    OfficialMasterEntity(code: '509', name: 'مورد محاصيل - هيثم ليمون', categoryGroup: 'موردين المحاصيل', entityType: 'crop'),
    OfficialMasterEntity(code: '510', name: 'مورد محاصيل - هانى', categoryGroup: 'موردين المحاصيل', entityType: 'crop'),
    OfficialMasterEntity(code: '511', name: 'مورد محاصيل - فارس', categoryGroup: 'موردين المحاصيل', entityType: 'crop'),
    OfficialMasterEntity(code: '512', name: 'مورد محاصيل - ايهاب كرم', categoryGroup: 'موردين المحاصيل', entityType: 'crop'),
    OfficialMasterEntity(code: '513', name: 'مورد محاصيل - على ناهض', categoryGroup: 'موردين المحاصيل', entityType: 'crop'),
    OfficialMasterEntity(code: '514', name: 'مورد محاصيل - بيكو', categoryGroup: 'موردين المحاصيل', entityType: 'crop'),
    OfficialMasterEntity(code: '515', name: 'مورد محاصيل - دينا عثمان عنب', categoryGroup: 'موردين المحاصيل', entityType: 'crop'),
    OfficialMasterEntity(code: '516', name: 'مورد محاصيل - اشرف البرومبلى مانجو', categoryGroup: 'موردين المحاصيل', entityType: 'crop'),
    OfficialMasterEntity(code: '517', name: 'مورد محاصيل - احمد مصطفى مطاوع مانجو', categoryGroup: 'موردين المحاصيل', entityType: 'crop'),
    OfficialMasterEntity(code: '518', name: 'مورد محاصيل - حماده مصباح مانجو', categoryGroup: 'موردين المحاصيل', entityType: 'crop'),
  ];

  /// Group 6: موردين النقل (601 to 610)
  static const List<OfficialMasterEntity> transportSuppliers = [
    OfficialMasterEntity(code: '601', name: 'مورد نقل - محمود ابو حسين', categoryGroup: 'موردين النقل', entityType: 'transport'),
    OfficialMasterEntity(code: '602', name: 'مورد نقل - عزام', categoryGroup: 'موردين النقل', entityType: 'transport'),
    OfficialMasterEntity(code: '603', name: 'مورد نقل - سيد هوايه', categoryGroup: 'موردين النقل', entityType: 'transport'),
    OfficialMasterEntity(code: '604', name: 'مورد نقل - سلامه', categoryGroup: 'موردين النقل', entityType: 'transport'),
    OfficialMasterEntity(code: '605', name: 'مورد نقل - باهر', categoryGroup: 'موردين النقل', entityType: 'transport'),
    OfficialMasterEntity(code: '606', name: 'مورد نقل - عبده', categoryGroup: 'موردين النقل', entityType: 'transport'),
    OfficialMasterEntity(code: '607', name: 'مورد نقل - سمير مرزوق', categoryGroup: 'موردين النقل', entityType: 'transport'),
    OfficialMasterEntity(code: '608', name: 'مورد نقل - ماهر تبع اشرف البرومبلى', categoryGroup: 'موردين النقل', entityType: 'transport'),
    OfficialMasterEntity(code: '609', name: 'مورد نقل - محمود', categoryGroup: 'موردين النقل', entityType: 'transport'),
    OfficialMasterEntity(code: '610', name: 'مورد نقل برادات - وليد', categoryGroup: 'موردين النقل', entityType: 'transport'),
  ];

  /// Group 7: موردين مواد التعبئة والتغليف والاستيكر (701 to 717)
  static const List<OfficialMasterEntity> packagingSuppliers = [
    OfficialMasterEntity(code: '701', name: 'مورد مواد تعبئه وتغليف - يوسف', categoryGroup: 'موردين مواد التعبئة والتغليف', entityType: 'packaging'),
    OfficialMasterEntity(code: '702', name: 'مورد مواد تعبئه وتغليف - مصنع مودرن للكرتون', categoryGroup: 'موردين مواد التعبئة والتغليف', entityType: 'packaging'),
    OfficialMasterEntity(code: '703', name: 'مورد مواد تعبئه وتغليف - تبارك للكرتون', categoryGroup: 'موردين مواد التعبئة والتغليف', entityType: 'packaging'),
    OfficialMasterEntity(code: '704', name: 'مورد مواد تعبئه وتغليف - صالح بالتات', categoryGroup: 'موردين مواد التعبئة والتغليف', entityType: 'packaging'),
    OfficialMasterEntity(code: '705', name: 'مورد مواد تعبئه وتغليف - القمه بالتات', categoryGroup: 'موردين مواد التعبئة والتغليف', entityType: 'packaging'),
    OfficialMasterEntity(code: '706', name: 'مورد مواد تعبئه وتغليف - جورج استيكر', categoryGroup: 'موردين مواد التعبئة والتغليف', entityType: 'packaging'),
    OfficialMasterEntity(code: '707', name: 'مورد مواد تعبئه وتغليف - حنا استيكر', categoryGroup: 'موردين مواد التعبئة والتغليف', entityType: 'packaging'),
    OfficialMasterEntity(code: '708', name: 'مورد مواد تعبئه وتغليف - وادى النيل', categoryGroup: 'موردين مواد التعبئة والتغليف', entityType: 'packaging'),
    OfficialMasterEntity(code: '709', name: 'مورد مواد تعبئه وتغليف - رمزى شتا', categoryGroup: 'موردين مواد التعبئة والتغليف', entityType: 'packaging'),
    OfficialMasterEntity(code: '710', name: 'مورد مواد تعبئه وتغليف - محمود جنزور', categoryGroup: 'موردين مواد التعبئة والتغليف', entityType: 'packaging'),
    OfficialMasterEntity(code: '711', name: 'مورد مواد تعبئه وتغليف - هشام عبد الباسط', categoryGroup: 'موردين مواد التعبئة والتغليف', entityType: 'packaging'),
    OfficialMasterEntity(code: '712', name: 'مورد مواد تعبئه وتغليف - جورج', categoryGroup: 'موردين مواد التعبئة والتغليف', entityType: 'packaging'),
    OfficialMasterEntity(code: '713', name: 'مورد مواد تعبئه وتغليف - احمد سعيد', categoryGroup: 'موردين مواد التعبئة والتغليف', entityType: 'packaging'),
    OfficialMasterEntity(code: '714', name: 'مورد مواد تعبئه وتغليف - مصطفى عاطف', categoryGroup: 'موردين مواد التعبئة والتغليف', entityType: 'packaging'),
    OfficialMasterEntity(code: '715', name: 'مورد مواد تعبئه وتغليف - جورج', categoryGroup: 'موردين مواد التعبئة والتغليف', entityType: 'packaging'),
    OfficialMasterEntity(code: '716', name: 'مورد استكير - يوسف', categoryGroup: 'موردين مواد التعبئة والتغليف', entityType: 'packaging'),
    OfficialMasterEntity(code: '717', name: 'مورد استكير - رحاب', categoryGroup: 'موردين مواد التعبئة والتغليف', entityType: 'packaging'),
  ];

  /// Group 8: محطات التعبئة والتحاليل (801 to 809)
  static const List<OfficialMasterEntity> stationsAndTesting = [
    OfficialMasterEntity(code: '801', name: 'محطة - العبور', categoryGroup: 'محطات التعبئة والتحاليل', entityType: 'station'),
    OfficialMasterEntity(code: '802', name: 'محطة الصفا - العاشر من رمضان', categoryGroup: 'محطات التعبئة والتحاليل', entityType: 'station'),
    OfficialMasterEntity(code: '803', name: 'محطة الاعتماد', categoryGroup: 'محطات التعبئة والتحاليل', entityType: 'station'),
    OfficialMasterEntity(code: '804', name: 'تحاليل وتخصيم - الشيخ تامر', categoryGroup: 'محطات التعبئة والتحاليل', entityType: 'station'),
    OfficialMasterEntity(code: '805', name: 'تحاليل وتخصيم - مصطفى العربى', categoryGroup: 'محطات التعبئة والتحاليل', entityType: 'station'),
    OfficialMasterEntity(code: '806', name: 'محطه تاج', categoryGroup: 'محطات التعبئة والتحاليل', entityType: 'station'),
    OfficialMasterEntity(code: '807', name: 'محطه عسكر', categoryGroup: 'محطات التعبئة والتحاليل', entityType: 'station'),
    OfficialMasterEntity(code: '808', name: 'محطه فاكهه الموسم', categoryGroup: 'محطات التعبئة والتحاليل', entityType: 'station'),
    OfficialMasterEntity(code: '809', name: 'محطه دلتا جروب', categoryGroup: 'محطات التعبئة والتحاليل', entityType: 'station'),
  ];

  /// Group 9: شركات الشحن (901 to 905)
  static const List<OfficialMasterEntity> shippingCompanies = [
    OfficialMasterEntity(code: '901', name: 'شركه فالكون للشحن', categoryGroup: 'شركات الشحن', entityType: 'shipping'),
    OfficialMasterEntity(code: '902', name: 'شركه المصريه للشحن', categoryGroup: 'شركات الشحن', entityType: 'shipping'),
    OfficialMasterEntity(code: '903', name: 'شركه فينوس للشحن', categoryGroup: 'شركات الشحن', entityType: 'shipping'),
    OfficialMasterEntity(code: '904', name: 'شركه العربى للشحن', categoryGroup: 'شركات الشحن', entityType: 'shipping'),
    OfficialMasterEntity(code: '905', name: 'شركه الندى للشحن', categoryGroup: 'شركات الشحن', entityType: 'shipping'),
  ];

  /// All 59 authoritative entries combined
  static List<OfficialMasterEntity> get allEntities => [
    ...cropSuppliers,
    ...transportSuppliers,
    ...packagingSuppliers,
    ...stationsAndTesting,
    ...shippingCompanies,
  ];

  // ───────────────────────────────────────────────────────────────────────────
  // SEEDING EXECUTION ENGINE
  // ───────────────────────────────────────────────────────────────────────────

  /// Idempotently seeds or updates all official master records in Supabase
  static Future<Map<String, int>> seedAll({required SupabaseClient client}) async {
    final c = client;
    final stats = <String, int>{
      'crop_suppliers': 0,
      'transport_suppliers': 0,
      'packaging_suppliers': 0,
      'stations': 0,
      'shipping_companies': 0,
      'accounts_linked': 0,
    };

    // 1. Resolve default company_id from accounts table
    String? companyId;
    try {
      final accSample = await c.from('accounts').select('company_id').not('company_id', 'is', null).limit(1).maybeSingle();
      companyId = accSample?['company_id']?.toString() ?? 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5';
    } catch (_) {
      companyId = 'cc6c170b-7115-4a3f-8e26-96b682bbf4e5';
    }

    // 2. Resolve Level 4 Parent Account IDs
    int? parentCropSuppliersId;     // 2112
    int? parentTransportId;         // 2111
    int? parentShippingId;          // 2113
    try {
      final accRows = await c.from('accounts').select('id, account_code').inFilter('account_code', ['2111', '2112', '2113']);
      for (final r in (accRows as List)) {
        final code = r['account_code']?.toString();
        final id = r['id'] as int;
        if (code == '2111') parentTransportId = id;
        if (code == '2112') parentCropSuppliersId = id;
        if (code == '2113') parentShippingId = id;
      }
    } catch (e) {
      print('Warning: Could not query parent accounts: $e');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helper: Ensure Account exists and is Level 4 (sub-analytic)
    // ─────────────────────────────────────────────────────────────────────────
    Future<int?> ensureSubAccount({
      required String accountCode,
      required String name,
      required String accountType,
      int? parentId,
    }) async {
      try {
        final existing = await c.from('accounts').select('id').eq('account_code', accountCode).maybeSingle();
        if (existing != null) {
          final id = existing['id'] as int;
          await c.from('accounts').update({
            'name': name,
            'account_name': name,
            'is_active': true,
            'allow_posting': true,
            'is_leaf': true,
          }).eq('id', id);
          return id;
        }

        final insertData = {
          'account_code': accountCode,
          'name': name,
          'account_name': name,
          'account_type': accountType,
          'parent_id': parentId,
          'level': 4, // Strict 4-level standard: operational sub-nodes are level 4
          'is_leaf': true,
          'allow_posting': true,
          'is_active': true,
          'is_system': false,
          'normal_balance': accountType == 'asset' ? 'Debit' : 'Credit',
          if (companyId != null) 'company_id': companyId,
        };
        final inserted = await c.from('accounts').insert(insertData).select('id').single();
        return inserted['id'] as int;
      } catch (e) {
        try {
          final retry = await c.from('accounts').select('id').eq('account_code', accountCode).maybeSingle();
          if (retry != null) return retry['id'] as int;
        } catch (_) {}
        print('Sub-account notice for $accountCode: $e');
        return null;
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 3. Seed Crop Suppliers (501 - 518)
    // ─────────────────────────────────────────────────────────────────────────
    for (final s in cropSuppliers) {
      try {
        final accCode = '2112${s.code}';
        final accId = await ensureSubAccount(
          accountCode: accCode,
          name: s.name,
          accountType: 'liability',
          parentId: parentCropSuppliersId,
        );
        if (accId != null) stats['accounts_linked'] = (stats['accounts_linked'] ?? 0) + 1;

        final existing = await c.from('suppliers').select('id').or('code.eq.${s.code},supplier_code.eq.${s.code}').maybeSingle();
        if (existing != null) {
          await c.from('suppliers').update({
            'code': s.code,
            'supplier_code': s.code,
            'name': s.name,
            'supplier_type': 'crop',
            if (accId != null) 'account_id': accId,
          }).eq('id', existing['id']);
        } else {
          await c.from('suppliers').insert({
            'code': s.code,
            'supplier_code': s.code,
            'name': s.name,
            'supplier_type': 'crop',
            'initial_balance': 0.0,
            'initial_balance_direction': 'CREDIT',
            'outstanding_balance': 0.0,
            'currency': 'EGP',
            if (accId != null) 'account_id': accId,
            if (companyId != null) 'company_id': companyId,
          });
        }
        stats['crop_suppliers'] = (stats['crop_suppliers'] ?? 0) + 1;
      } catch (e) {
        print('Error seeding crop supplier ${s.code}: $e');
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 4. Seed Transport Suppliers (601 - 610)
    // ─────────────────────────────────────────────────────────────────────────
    for (final t in transportSuppliers) {
      try {
        final accCode = '2111${t.code}';
        final accId = await ensureSubAccount(
          accountCode: accCode,
          name: t.name,
          accountType: 'liability',
          parentId: parentTransportId,
        );
        if (accId != null) stats['accounts_linked'] = (stats['accounts_linked'] ?? 0) + 1;

        final existing = await c.from('transport_suppliers').select('id').eq('code', t.code).maybeSingle();
        if (existing != null) {
          await c.from('transport_suppliers').update({
            'name': t.name,
            if (accId != null) 'account_id': accId,
          }).eq('id', existing['id']);
        } else {
          await c.from('transport_suppliers').insert({
            'code': t.code,
            'name': t.name,
            'initial_balance': 0.0,
            'initial_balance_direction': 'CREDIT',
            'balance': 0.0,
            'truck_balance': 0,
            'initial_truck_balance': 0,
            if (accId != null) 'account_id': accId,
            if (companyId != null) 'company_id': companyId,
          });
        }
        stats['transport_suppliers'] = (stats['transport_suppliers'] ?? 0) + 1;
      } catch (e) {
        print('Error seeding transport supplier ${t.code}: $e');
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 5. Seed Packaging Suppliers (701 - 717)
    // ─────────────────────────────────────────────────────────────────────────
    for (final p in packagingSuppliers) {
      try {
        final accCode = '2112${p.code}';
        final accId = await ensureSubAccount(
          accountCode: accCode,
          name: p.name,
          accountType: 'liability',
          parentId: parentCropSuppliersId,
        );
        if (accId != null) stats['accounts_linked'] = (stats['accounts_linked'] ?? 0) + 1;

        final existing = await c.from('suppliers').select('id').or('code.eq.${p.code},supplier_code.eq.${p.code}').maybeSingle();
        if (existing != null) {
          await c.from('suppliers').update({
            'code': p.code,
            'supplier_code': p.code,
            'name': p.name,
            'supplier_type': 'packaging',
            if (accId != null) 'account_id': accId,
          }).eq('id', existing['id']);
        } else {
          await c.from('suppliers').insert({
            'code': p.code,
            'supplier_code': p.code,
            'name': p.name,
            'supplier_type': 'packaging',
            'initial_balance': 0.0,
            'initial_balance_direction': 'CREDIT',
            'outstanding_balance': 0.0,
            'currency': 'EGP',
            if (accId != null) 'account_id': accId,
            if (companyId != null) 'company_id': companyId,
          });
        }
        stats['packaging_suppliers'] = (stats['packaging_suppliers'] ?? 0) + 1;
      } catch (e) {
        print('Error seeding packaging supplier ${p.code}: $e');
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 6. Seed Stations & Testing Centers (801 - 809)
    // ─────────────────────────────────────────────────────────────────────────
    for (final st in stationsAndTesting) {
      try {
        final existing = await c.from('stations').select('id').eq('code', st.code).maybeSingle();
        if (existing != null) {
          await c.from('stations').update({
            'name': st.name,
            'type': 'sub',
            'is_active': true,
          }).eq('id', existing['id']);
        } else {
          await c.from('stations').insert({
            'code': st.code,
            'name': st.name,
            'type': 'sub',
            'is_active': true,
          });
        }
        stats['stations'] = (stats['stations'] ?? 0) + 1;
      } catch (e) {
        print('Error seeding station ${st.code}: $e');
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 7. Seed Shipping Companies (901 - 905)
    // ─────────────────────────────────────────────────────────────────────────
    for (final sh in shippingCompanies) {
      try {
        final accCode = '2113${sh.code}';
        final accId = await ensureSubAccount(
          accountCode: accCode,
          name: sh.name,
          accountType: 'liability',
          parentId: parentShippingId,
        );
        if (accId != null) stats['accounts_linked'] = (stats['accounts_linked'] ?? 0) + 1;

        final existing = await c.from('shipping_companies').select('id').eq('code', sh.code).maybeSingle();
        if (existing != null) {
          await c.from('shipping_companies').update({
            'name': sh.name,
            if (accId != null) 'account_id': accId,
          }).eq('id', existing['id']);
        } else {
          await c.from('shipping_companies').insert({
            'code': sh.code,
            'name': sh.name,
            'initial_balance': 0.0,
            'initial_balance_direction': 'CREDIT',
            'balance': 0.0,
            'currency': 'EGP',
            if (accId != null) 'account_id': accId,
            if (companyId != null) 'company_id': companyId,
          });
        }
        stats['shipping_companies'] = (stats['shipping_companies'] ?? 0) + 1;
      } catch (e) {
        print('Error seeding shipping company ${sh.code}: $e');
      }
    }

    print('DatabaseSeeder finished successfully: $stats');
    return stats;
  }
}
