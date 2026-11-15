import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cost_center.dart';

class CostReportDao {
  final SupabaseClient _client;

  CostReportDao([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  /// Normalizes Arabic text for flexible matching across variations (ة/ه, أ/إ/آ/ا, فرولة/فراولة, etc.)
  static String normalizeArabic(String text) =>
      CostCenterHelper.normalizeArabic(text);

  /// Extracts the agricultural season string (e.g. "2026-2027") from text or codes
  static String? extractSeason(String? text) {
    if (text == null || text.isEmpty) return null;
    final m = RegExp(r'(\d{4})[-/–](\d{4})').firstMatch(text);
    if (m != null) return '${m.group(1)}-${m.group(2)}';
    return null;
  }

  /// Extracts the base item name by stripping transaction prefixes like "مرتجع", "شراء", etc.
  static String extractBaseItemName(String item) {
    var s = item.trim();
    s = s.replaceFirst(RegExp(r'^مرتجع\s+(شراء\s+)?(محصول\s+)?(خام\s+)?'), '');
    s = s.replaceFirst(RegExp(r'^شراء\s+(محصول\s+)?'), '');
    s = s.replaceFirst(RegExp(r'^فاتورة\s+مشتريات\s+-\s+'), '');
    return normalizeArabic(s);
  }

  /// Maps a cost center to its primary reporting category
  static String resolveCostCenterCategory(CostCenter c) {
    if (c.type == CostCenterType.variety) return 'تكلفة المحاصيل';
    final name = c.nameAr;
    final code = (c.code ?? c.id).toUpperCase();
    if (name.contains('شحن') || code == 'CC-LOGISTICS' || code == 'CC-CAT-4' || code == 'FREIGHT_LOGISTICS') {
      return 'تكلفة شركات الشحن';
    }
    if (name.contains('تخليص') || name.contains('مخلص') || code == 'CC-CUSTOMS' || code == 'CC-CAT-5' || code == 'CUSTOMS_CLEARANCE') {
      return 'تكلفة المخلصين';
    }
    if (name.contains('لوجستيك') || name.contains('نقل') || code == 'CC-CAT-6') {
      return 'لوجستيك ونقل';
    }
    if (name.contains('تعبئة') || name.contains('تغليف') || code == 'CC-PACKING' || code == 'CC-CAT-3' || code == 'PACKING_STATION') {
      return 'تعبئة وتغليف';
    }
    if (name.contains('مواد التعبئة') || code == 'CC-CAT-2') {
      return 'مواد التعبئة';
    }
    return c.nameAr.isNotEmpty ? c.nameAr : 'مصاريف إدارية';
  }

  /// Resolves an expense transaction or cost item to its canonical reporting branch
  static String resolveExpenseBranchName({
    String? category,
    String? itemName,
    String? supplierType,
    String? accountCode,
    String? accountName,
  }) {
    final cat = (category ?? '').toLowerCase().trim();
    final name = (itemName ?? '').toLowerCase().trim();
    final supp = (supplierType ?? '').toLowerCase().trim();
    final code = (accountCode ?? '').trim();

    // 1. Direct 5-digit Account Code starting with 3
    if (code.startsWith('3') && code.length >= 5 && code.length != 3 && code.length != 4) {
      final title = accountName ?? (itemName != null && itemName.isNotEmpty ? itemName : 'مصروف تحليلي');
      return '$code - $title';
    }

    // 2. Category is an Account Code starting with 3
    if (cat.startsWith('3') && cat.length >= 5 && cat.length != 3 && cat.length != 4) {
      final title = accountName ?? (itemName != null && itemName.isNotEmpty ? itemName : 'مصروف تحليلي');
      return '$cat - $title';
    }

    // 3. Embedded 5-digit code starting with 3 in category or name
    final match = RegExp(r'(3\d{4})').firstMatch('$cat $name');
    if (match != null) {
      final matchedCode = match.group(1)!;
      final title = accountName ?? (name.isNotEmpty ? name : 'مصروف تحليلي');
      return '$matchedCode - $title';
    }

    // 4. Engineer Expenses (مصاريف مهندسين - كود 31251)
    if (cat == 'engineer_expenses' ||
        cat == 'engineer' ||
        cat == '31251' ||
        cat == 'مصاريف مهندسين' ||
        cat == '31251 - مصاريف مهندسين' ||
        supp == 'engineer' ||
        name.contains('مهندس') ||
        name.contains('مهندسين') ||
        name.contains('إشراف') ||
        name.contains('اشراف') ||
        name.contains('مأمورية') ||
        name.contains('مأموريات')) {
      return '31251 - مصاريف مهندسين';
    }

    // 5. Operational packing items (3124x and 3126x)
    if (name.contains('تشغيل') || cat.contains('تشغيل')) return '31241 - تشغيل';
    if (name.contains('تبريد') || cat.contains('تبريد')) return '31242 - تبريد';
    if (name.contains('حفظ مبرد')) return '31243 - حفظ مبرد';
    if (name.contains('تقفيل كرتون')) return '31244 - تقفيل كرتون';
    if (name.contains('تعتيق')) return '31245 - تعتيق صادر';
    if (name.contains('اعادة تدوير') || name.contains('إعادة تدوير')) return '31246 - اعادة تدوير';
    if (name.contains('عماله') || name.contains('عمالة')) return '31247 - عماله';
    if (name.contains('تبخير')) return '31248 - تبخير';
    if (name.contains('تدوير خام')) return '31249 - تدوير خام';
    if (name.contains('رسوم فحص')) return '31261 - رسوم فحص';
    if (name.contains('تخصيم عربي')) return '31262 - تخصيم عربي';
    if (name.contains('تخصيم اوروبي') || name.contains('تخصيم أوروبي')) return '31263 - تخصيم اوروبي';
    if (name.contains('تحليل خاص')) return '31264 - تحليل خاص';
    if (name.contains('تحليل هيئه') || name.contains('تحليل هيئة')) return '31265 - تحليل هيئه';
    if (name.contains('سحب عينه') || name.contains('سحب عينة')) return '31266 - سحب عينه عربي';
    if (name.contains('تعديل وجات')) return '31267 - تعديل وجات';
    if (name.contains('حجر زراعي')) return '31268 - دفتر حجر زراعي';
    if (name.contains('سلامه غذاء') || name.contains('سلامة غذاء')) return '31269 - دفتر حجر سلامه غذاء';

    // 6. Salaries & Benefits (3111x)
    if (name.contains('مرتب') || cat.contains('مرتب')) return '31111 - مصروفات مرتبات';
    if (name.contains('تامين') || name.contains('تأمين')) return '31112 - مصروفات تامينات اجتماعيه';
    if (name.contains('بدلات ثابته') || name.contains('بدلات ثابتة')) return '31113 - مصروفات بدلات اخري - ثابته';
    if (name.contains('بدلات متغيره') || name.contains('بدلات متغيرة')) return '31114 - مصروفات بدلات اخري - متغيره';
    if (name.contains('مكافآت') || name.contains('حوافز')) return '31115 - مصروفات مكافآت وحوافز';
    if (name.contains('مكافأه نهايه الخدمه') || name.contains('مكافأة نهاية الخدمة')) return '31116 - مصروفات مكافأه نهايه الخدمه';

    // 7. Travel & Medical (3112x)
    if (name.contains('سفر للخارج') || name.contains('بدلات سفر')) return '31121 - مصروفات سفر للخارج - بدلات سفر';
    if (name.contains('علاج العاملين')) return '31122 - مصروفات علاج العاملين';
    if (name.contains('انتقالات') || cat.contains('انتقالات')) return '31123 - مصروفات انتقالات';

    // 8. General & Administrative (3131x, 3132x, 3133x)
    if (name.contains('نظافه') || name.contains('نظافة') || name.contains('بوفيه')) return '31311 - مصروفات النظافه والبوفيه';
    if (name.contains('كهرباء') || name.contains('مياه') || name.contains('غاز')) return '31312 - مصروفات فواتير الكهرباء والمياه والغاز الطبيعي';
    if (name.contains('ضيافه') || name.contains('ضيافة')) return '31313 - مصروفات الضيافه';
    if (name.contains('ادوات كتابيه') || name.contains('أدوات كتابية') || name.contains('تصوير')) return '31314 - مصروفات ادوات كتابيه وماكينات التصوير والفاكس';
    if (name.contains('كمبيوتر') || name.contains('انترنت') || name.contains('إنترنت') || name.contains('تليفون')) return '31315 - مصروفات الكمبيوتر والانترنت وتليفون ارضي';
    if (name.contains('إكراميات') || name.contains('اكراميات')) return '31316 - مصروفات الإكراميات';
    if (name.contains('هدايا')) return '31317 - مصروفات الهدايا';
    if (name.contains('صيانه عامه') || name.contains('صيانة عامة')) return '31318 - مصروفات الصيانه العامه';
    if (name.contains('ايجار') || name.contains('إيجار')) return '31319 - مصروفات ايجار عقارات';
    if (name.contains('استشاريه') || name.contains('استشارية')) return '31321 - مصروفات أتعاب استشاريه';
    if (name.contains('مراجعه') || name.contains('مراجعة')) return '31322 - مصروفات أتعاب مكتب المراجعه';
    if (name.contains('اشتراكات') || name.contains('تراخيص')) return '31323 - مصروفات رسوم واشتراكات وتراخيص';
    if (name.contains('شحن مستندات')) return '31324 - مصروفات شحن مستندات';
    if (name.contains('إدارية وعمومية') || cat.contains('إدارية') || cat == 'admin') return '31331 - مصاريف إدارية وعمومية';
    if (name.contains('فوائد بنكيه') || name.contains('فوائد بنكية')) return '31411 - مصروفات فوائد بنكيه';

    // 9. Transport & Logistics (34114)
    if (name.contains('نقل') ||
        name.contains('نولون') ||
        name.contains('مشال') ||
        name.contains('شاحن') ||
        cat.contains('نقل') ||
        cat == 'logistics' ||
        cat == 'transport' ||
        supp == 'transport') {
      return '34114 - لوجستيك ونقل';
    }

    // 10. Shipping & Freight
    if (name.contains('شحن بحري') ||
        name.contains('شحن جوي') ||
        name.contains('شحن بري') ||
        cat == 'shipping' ||
        cat == 'freight' ||
        cat == 'shipping_company') {
      return 'تكلفة شركات الشحن';
    }

    // 11. Customs Clearance
    if (name.contains('تخليص') ||
        name.contains('مخلص') ||
        cat == 'clearance' ||
        cat == 'clearing' ||
        cat == 'clearing_agent') {
      return 'تكلفة المخلصين';
    }

    // 11.5 Waste Cost
    if (name.contains('هالك') || cat.contains('هالك') || cat == 'waste' || cat == 'waste_cost') {
      return 'تكلفة الهالك';
    }

    // 12. Packaging & Materials
    if (name.contains('كرتون') ||
        name.contains('كراتين') ||
        name.contains('مادة تعبئة') ||
        name.contains('مواد تعبئة') ||
        name.contains('تعبئة وتغليف') ||
        cat == 'packing_material' ||
        cat == 'مواد التعبئة') {
      return 'مواد التعبئة';
    }
    if (name.contains('تعبئة') ||
        name.contains('تغليف') ||
        cat == 'packing' ||
        cat == 'packaging' ||
        cat == 'manual_packing') {
      return 'تعبئة وتغليف';
    }

    // 13. Fallbacks
    if (cat == 'other' || cat == 'OTHER') {
      return 'مصاريف تشغيلية أخرى';
    }

    // 14. If category is non-empty, use it directly
    if (category != null && category.isNotEmpty) {
      return category;
    }
    return itemName != null && itemName.isNotEmpty ? itemName : '31251 - مصاريف مهندسين';
  }

  /// Maps branch name to its canonical category code (Level 5 5-digit code)
  static String branchToCategoryCode(String branch) {
    final b = branch.trim();
    final match = RegExp(r'^(\d{5})').firstMatch(b);
    if (match != null) {
      return match.group(1)!;
    }
    final match3 = RegExp(r'(3\d{4})').firstMatch(b);
    if (match3 != null) {
      return match3.group(1)!;
    }
    if (b.contains('مهندس') || b.contains('إشراف') || b == 'engineer_expenses') {
      return '31251';
    }
    return '';
  }




  static List<Map<String, dynamic>> _asList(dynamic val) {
    if (val is List) {
      return val
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } else if (val is Map) {
      return [Map<String, dynamic>.from(val)];
    }
    return [];
  }

  static List<CostCenter>? _cachedAllCenters;
  static DateTime? _cacheTimestamp;
  static Map<String, String>? _cachedRmNames;
  static DateTime? _rmCacheTimestamp;

  /// Invalidate cost center in-memory cache to force re-fetch
  static void clearCostCenterCache() {
    _cachedAllCenters = null;
    _cacheTimestamp = null;
    _cachedRmNames = null;
    _rmCacheTimestamp = null;
  }

  /// Fetches all active cost centers (both crop/variety lines from cost_centers and Level 5 COA expense accounts)
  Future<List<CostCenter>> getActiveCostCenters({bool forceRefresh = false}) async {
    final all = await getAllCostCenters(forceRefresh: forceRefresh);
    return all.where((c) => !c.isClosed).toList();
  }

  /// Fetches ALL cost centers (active and closed crop/variety lines, plus Level 5 accounts)
  Future<List<CostCenter>> getAllCostCenters({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedAllCenters != null && _cacheTimestamp != null) {
      if (DateTime.now().difference(_cacheTimestamp!).inSeconds < 60) {
        return List<CostCenter>.from(_cachedAllCenters!);
      }
    }
    try {
      final List<CostCenter> list = [];

      // 1. Fetch ALL cost_centers from cost_centers table (both active and closed)
      try {
        final data = await _client
            .from('cost_centers')
            .select()
            .order('name');

        for (final e in data as List) {
          final c = CostCenter.fromMap(Map<String, dynamic>.from(e));
          final code = (c.code ?? c.id).trim();
          if (RegExp(r'^\d{3,4}$').hasMatch(code)) continue;
          if (!list.any((x) => x.id == c.id || x.code == c.code)) {
            list.add(c);
          }
        }
      } catch (e) {
        debugPrint('ℹ️ Error loading all cost_centers into getAllCostCenters: $e');
      }

      // 2. Fetch all Level 5 leaf accounts under root 3 from accounts table
      try {
        final accData = await _client
            .from('accounts')
            .select('id, account_code, account_name, level, is_leaf')
            .like('account_code', '3%')
            .order('account_code');
        for (final a in accData as List) {
          final code = (a['account_code'] ?? '').toString().trim();
          final name = (a['account_name'] ?? '').toString().trim();
          if (code.startsWith('3') && code.length >= 5 && code.length != 3 && code.length != 4) {
            if (!list.any((x) => x.id == code || x.code == code)) {
              list.add(
                CostCenter(
                  id: code,
                  nameAr: '$code - $name',
                  nameEn: '$name ($code)',
                  type: CostCenterType.operational,
                  color: const Color(0xFF0D74CE),
                  icon: code == '31251' ? Icons.engineering_outlined : Icons.account_tree_outlined,
                  code: code,
                  season: '2026-2027',
                  seasonStatus: 'active',
                  isActive: true,
                ),
              );
            }
          }
        }
      } catch (e) {
        debugPrint('ℹ️ Error loading accounts into getAllCostCenters: $e');
      }

      // Ensure 31251 is included
      if (!list.any((c) => c.id == '31251' || c.code == '31251')) {
        list.add(
          const CostCenter(
            id: '31251',
            nameAr: '31251 - مصاريف مهندسين',
            nameEn: 'Engineer Expenses (31251)',
            type: CostCenterType.operational,
            color: Color(0xFF0D74CE),
            icon: Icons.engineering_outlined,
            code: '31251',
            season: '2026-2027',
            seasonStatus: 'active',
            isActive: true,
          ),
        );
      }

      // Ensure standard predefined operational cost centers are included
      for (final op in CostCenterHelper.operationalCenters) {
        if (!list.any((c) => c.id == op.id || c.code == op.code)) {
          list.add(op);
        }
      }

      // Sort: Variety lines (Crops) first, then 31251, then other accounts by code
      list.sort((a, b) {
        if (a.type == CostCenterType.variety && b.type != CostCenterType.variety) return -1;
        if (b.type == CostCenterType.variety && a.type != CostCenterType.variety) return 1;
        if (a.id == '31251') return -1;
        if (b.id == '31251') return 1;
        return (a.code ?? a.id).compareTo(b.code ?? b.id);
      });

      _cachedAllCenters = List<CostCenter>.from(list);
      _cacheTimestamp = DateTime.now();

      return list;
    } catch (_) {
      return [
        const CostCenter(
          id: '31251',
          nameAr: '31251 - مصاريف مهندسين',
          nameEn: 'Engineer Expenses (31251)',
          type: CostCenterType.operational,
          color: Color(0xFF0D74CE),
          icon: Icons.engineering_outlined,
          code: '31251',
          season: '2026-2027',
          seasonStatus: 'active',
          isActive: true,
        ),
      ];
    }
  }

  /// Resolves the specific CostCenter for a product line
  CostCenter _resolveProductCostCenter(
    String productName,
    String? fruitTypeId,
    List<CostCenter>? centers,
  ) {
    if (centers != null && centers.isNotEmpty) {
      // 1. Direct ID / fruitTypeId match (prioritizing active seasons)
      if (fruitTypeId != null && fruitTypeId.isNotEmpty) {
        for (final c in centers) {
          if (c.isActiveSeason &&
              (c.id == fruitTypeId ||
                  c.code == fruitTypeId ||
                  c.id == 'CC-$fruitTypeId' ||
                  c.code == 'CC-$fruitTypeId' ||
                  (c.productId != null && c.productId.toString() == fruitTypeId))) {
            return c;
          }
        }
        for (final c in centers) {
          if (c.id == fruitTypeId ||
              c.code == fruitTypeId ||
              c.id == 'CC-$fruitTypeId' ||
              c.code == 'CC-$fruitTypeId' ||
              (c.productId != null && c.productId.toString() == fruitTypeId)) {
            return c;
          }
        }
      }

      // 2. Match canonical crop name and crop slug (prioritizing active seasons)
      final canonCrop = CostCenter.canonicalCropName(productName);
      final slug = CostCenterHelper.resolveCropSlug(canonCrop);

      for (final c in centers) {
        if (!c.isActiveSeason) continue;
        if (slug != 'CROP' && c.cropCode == slug) {
          return c;
        }
        if (c.cropName != null && c.cropName == canonCrop) {
          return c;
        }
      }

      for (final c in centers) {
        if (slug != 'CROP' && c.cropCode == slug) {
          return c;
        }
        if (c.cropName != null && c.cropName == canonCrop) {
          return c;
        }
      }

      // 3. Normalized Arabic name comparison
      final normProd = normalizeArabic(canonCrop.isNotEmpty ? canonCrop : productName);
      for (final c in centers) {
        if (!c.isActiveSeason) continue;
        final normCenter = normalizeArabic(c.cropName ?? c.nameAr);
        if (normCenter == normProd ||
            (normProd.length >= 3 && normCenter.contains(normProd)) ||
            (normCenter.length >= 3 && normProd.contains(normCenter))) {
          return c;
        }
      }
      for (final c in centers) {
        final normCenter = normalizeArabic(c.cropName ?? c.nameAr);
        if (normCenter == normProd ||
            (normProd.length >= 3 && normCenter.contains(normProd)) ||
            (normCenter.length >= 3 && normProd.contains(normCenter))) {
          return c;
        }
      }
    }

    final canonCrop = CostCenter.canonicalCropName(productName);
    final slug = CostCenterHelper.resolveCropSlug(canonCrop);
    final code = slug != 'CROP'
        ? 'CC-$slug'
        : ((fruitTypeId != null && fruitTypeId.isNotEmpty) ? 'CC-$fruitTypeId' : 'CC-01');

    return CostCenter(
      id: code,
      nameAr: canonCrop.isNotEmpty ? canonCrop : productName,
      nameEn: CostCenterHelper.resolveEnglishName(canonCrop.isNotEmpty ? canonCrop : productName),
      type: CostCenterType.variety,
      color: CostCenterHelper.resolveColor(null, canonCrop),
      icon: CostCenterHelper.resolveIcon(null, canonCrop),
      code: code,
      cropName: canonCrop,
      cropCode: slug,
      season: '2026-2027',
      seasonStatus: 'active',
      isActive: true,
    );
  }

  /// Appends operational transaction rows for a product line: raw material, waste, and sorting deduction
  void _addOperationalEntries({
    required List<Map<String, dynamic>> operationalRows,
    required String shipmentDate,
    required String shipmentNo,
    required String customerName,
    required String productName,
    required CostCenter costCenter,
    required int poId,
    required String orderNumber,
    required double qty,
    required double unitPrice,
    required double rawCost,
    required double wasteCost,
    required double wasteWeight,
    required double wastePct,
    required double sortingCost,
    required double sortedWeight,
    double? expectedRawCost,
  }) {
    // 1. Raw material cost row (تكلفة الخام الإجمالي)
    if (rawCost > 0) {
      double effectiveRawQty = qty;
      double effectiveUnitPrice = unitPrice;
      if (effectiveRawQty <= 0 && effectiveUnitPrice > 0) {
        effectiveRawQty = rawCost / effectiveUnitPrice;
      } else if (effectiveRawQty > 0 && effectiveUnitPrice <= 0) {
        effectiveUnitPrice = rawCost / effectiveRawQty;
      } else if (effectiveRawQty <= 0 && effectiveUnitPrice <= 0) {
        effectiveRawQty = 1.0;
        effectiveUnitPrice = rawCost;
      }

      final est = expectedRawCost ?? rawCost;
      operationalRows.add({
        'shipment_date': shipmentDate,
        'shipment_no': shipmentNo,
        'customer_name': customerName,
        'category': 'تكلفة المحاصيل',
        'item_name': 'تكلفة الخام الإجمالي - $productName',
        'quantity': effectiveRawQty,
        'unit_price': effectiveUnitPrice,
        'amount': rawCost,
        'expected_amount': est,
        'actual_amount': rawCost,
        'variance_amount': rawCost - est,
        'cost_status': 'settled',
        'currency': 'EGP',
        'exchange_rate': 1.0,
        'total_in_currency': rawCost,
        'cost_center_id': costCenter.id,
        'cost_center_name': costCenter.nameAr,
        'cost_center_type': costCenter.typeLabelAr,
        'target_product_name': productName,
        'is_packing_operational': true,
        'source_type': 'packing_raw_material',
        'source_id': 'po_${poId}_raw',
        'packing_order_id': poId,
        'description': 'تكلفة الخام الإجمالي - أمر #$orderNumber',
        'notes': 'أمر تعبئة #$orderNumber - تكلفة الخام الإجمالي للمنتج',
      });
    }

    // 2. Waste cost row (تكلفة الهالك)
    if (wasteCost > 0) {
      final pctStr = wastePct > 0 ? ' (${wastePct.toStringAsFixed(1)}%)' : '';
      
      double effectiveWasteQty = wasteWeight;
      double effectiveUnitPrice = 0.0;

      if (effectiveWasteQty <= 0) {
        if (wastePct > 0 && qty > 0) {
          effectiveWasteQty = qty * (wastePct / 100.0);
        } else if (unitPrice > 0) {
          effectiveWasteQty = wasteCost / unitPrice;
        }
      }

      if (effectiveWasteQty > 0) {
        effectiveUnitPrice = wasteCost / effectiveWasteQty;
      } else if (unitPrice > 0) {
        effectiveUnitPrice = unitPrice;
        effectiveWasteQty = wasteCost / unitPrice;
      } else {
        effectiveWasteQty = 1.0;
        effectiveUnitPrice = wasteCost;
      }

      operationalRows.add({
        'shipment_date': shipmentDate,
        'shipment_no': shipmentNo,
        'customer_name': customerName,
        'category': 'تكلفة الهالك',
        'item_name': 'تكلفة الهالك$pctStr - $productName',
        'quantity': effectiveWasteQty,
        'unit_price': effectiveUnitPrice,
        'amount': wasteCost,
        'expected_amount': wasteCost,
        'actual_amount': wasteCost,
        'variance_amount': 0.0,
        'cost_status': 'settled',
        'currency': 'EGP',
        'exchange_rate': 1.0,
        'total_in_currency': wasteCost,
        'cost_center_id': costCenter.id,
        'cost_center_name': costCenter.nameAr,
        'cost_center_type': costCenter.typeLabelAr,
        'target_product_name': productName,
        'is_packing_operational': true,
        'is_packing_waste': true,
        'source_type': 'packing_crop_waste',
        'source_id': 'po_${poId}_crop_waste',
        'packing_order_id': poId,
        'description': 'تكلفة الهالك$pctStr - أمر #$orderNumber',
        'notes': 'أمر تعبئة #$orderNumber - تكلفة الهالك المحسوبة',
      });
    }

    // 3. Sorting cost deduction row (تكلفة الفرز - مستبعد كخصم لصافي المنتج)
    if (sortingCost > 0) {
      double effectiveSortedQty = sortedWeight;
      double effectiveUnitPrice = 0.0;

      if (effectiveSortedQty <= 0) {
        if (unitPrice > 0) {
          effectiveSortedQty = sortingCost / unitPrice;
        }
      }

      if (effectiveSortedQty > 0) {
        effectiveUnitPrice = sortingCost / effectiveSortedQty;
      } else if (unitPrice > 0) {
        effectiveUnitPrice = unitPrice;
        effectiveSortedQty = sortingCost / unitPrice;
      } else {
        effectiveSortedQty = 1.0;
        effectiveUnitPrice = sortingCost;
      }

      operationalRows.add({
        'shipment_date': shipmentDate,
        'shipment_no': shipmentNo,
        'customer_name': customerName,
        'category': 'تكلفة الفرز',
        'item_name': 'تكلفة الفرز (مستبعد) - $productName',
        'quantity': effectiveSortedQty,
        'unit_price': effectiveUnitPrice,
        'amount': -sortingCost, // Negative deduction so the sum reconciles with net product cost
        'expected_amount': -sortingCost,
        'actual_amount': -sortingCost,
        'variance_amount': 0.0,
        'cost_status': 'settled',
        'currency': 'EGP',
        'exchange_rate': 1.0,
        'total_in_currency': -sortingCost,
        'cost_center_id': costCenter.id,
        'cost_center_name': costCenter.nameAr,
        'cost_center_type': costCenter.typeLabelAr,
        'target_product_name': productName,
        'is_packing_operational': true,
        'source_type': 'packing_sorting_deduction',
        'source_id': 'po_${poId}_sorting',
        'packing_order_id': poId,
        'description': 'استبعاد تكلفة الفرز لصافي المنتج - أمر #$orderNumber',
        'notes': 'أمر تعبئة #$orderNumber - استبعاد تكلفة الفرز من المنتج',
      });
    }
  }

  /// Fetches operational packing order lines (raw materials, waste, sorting) from packing orders & order lines
  Future<List<Map<String, dynamic>>> _fetchPackingOrderOperationalRows({
    String? fromDate,
    String? toDate,
    String? customer,
    int? shipmentId,
    List<CostCenter>? centers,
  }) async {
    try {
      var query = _client.from('packing_orders').select(
          'id, order_number, status, packed_at, created_at, fruit_cost_base, fruit_cost_allocated, total_packing_cost, total_net_weight, total_gross_weight, product_name, notes, export_shipment_id, export_shipments(id, shipment_no, customer_name)');

      if (shipmentId != null) {
        query = query.eq('export_shipment_id', shipmentId);
      }
      if (fromDate != null && fromDate.isNotEmpty) {
        query = query.gte('created_at', fromDate);
      }
      if (toDate != null && toDate.isNotEmpty) {
        query = query.lte('created_at', toDate);
      }

      final orders = await query.order('id', ascending: false);
      if (orders.isEmpty) return [];

      final orderIds = orders.map((o) => o['id']).toList();
      final linesData = await _client
          .from('packing_order_lines')
          .select('*')
          .inFilter('packing_order_id', orderIds);

      final Map<int, List<Map<String, dynamic>>> linesByOrder = {};
      for (final l in linesData) {
        final pId = (l['packing_order_id'] as num?)?.toInt();
        if (pId != null) {
          linesByOrder.putIfAbsent(pId, () => []).add(Map<String, dynamic>.from(l as Map));
        }
      }

      List<dynamic> costItemsData = [];
      try {
        costItemsData = await _client
            .from('packing_order_cost_items')
            .select('*')
            .inFilter('packing_order_id', orderIds);
      } catch (_) {}

      final Map<int, List<Map<String, dynamic>>> costItemsByOrder = {};
      for (final c in costItemsData) {
        final pId = (c['packing_order_id'] as num?)?.toInt();
        if (pId != null) {
          costItemsByOrder.putIfAbsent(pId, () => []).add(Map<String, dynamic>.from(c as Map));
        }
      }

      final List<Map<String, dynamic>> operationalRows = [];

      for (final o in orders) {
        final po = Map<String, dynamic>.from(o as Map);
        final poId = (po['id'] as num?)?.toInt() ?? 0;
        final orderNumber = po['order_number']?.toString() ?? poId.toString();

        final shipmentData = po['export_shipments'] is Map ? po['export_shipments'] as Map : null;
        final shipmentNo = shipmentData?['shipment_no']?.toString() ?? 'أمر #$orderNumber';
        final customerName = shipmentData?['customer_name']?.toString() ?? '';

        if (customer != null && customer.isNotEmpty && customer != 'all') {
          if (customerName.trim().toLowerCase() != customer.trim().toLowerCase()) {
            continue;
          }
        }

        final rawDate = (po['packed_at'] ?? po['created_at'])?.toString() ?? '';
        final shipmentDate = rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate;

        final rawNotes = po['notes']?.toString() ?? '';
        Map<String, dynamic>? notesMap;
        if (rawNotes.trim().startsWith('{')) {
          try {
            final dec = jsonDecode(rawNotes);
            if (dec is Map<String, dynamic>) notesMap = dec;
          } catch (_) {}
        }

        final poLines = linesByOrder[poId] ?? [];

        if (poLines.isNotEmpty) {
          // Case A: Product lines in packing_order_lines table
          for (final line in poLines) {
            final pName = (line['product_name'] as String? ?? '').trim();
            final qty = (line['quantity'] as num?)?.toDouble() ??
                (line['total_net_weight'] as num?)?.toDouble() ??
                0.0;
            final rawCost = (line['raw_material_cost'] as num?)?.toDouble() ?? 0.0;
            final unitPrice = (line['unit_cost'] as num?)?.toDouble() ??
                (qty > 0 ? (rawCost / qty) : 0.0);
            double wasteCost = (line['waste_cost'] as num?)?.toDouble() ?? 0.0;
            double wasteWeight = (line['waste_weight_kg'] as num?)?.toDouble() ?? 0.0;
            double wastePct = (line['expected_loss_percent'] as num?)?.toDouble() ?? 0.0;
            double sortingCost = (line['sorting_cost'] as num?)?.toDouble() ?? 0.0;
            double sortedWeight = (line['sorted_weight_kg'] as num?)?.toDouble() ?? 0.0;

            if (notesMap != null) {
              final wasteList = _asList(notesMap['waste_data']);
              for (final w in wasteList) {
                if (normalizeArabic(w['product_name']?.toString() ?? '') == normalizeArabic(pName) || wasteList.length == 1) {
                  if (wasteCost <= 0) wasteCost = (w['waste_cost'] as num?)?.toDouble() ?? 0.0;
                  if (wasteWeight <= 0) wasteWeight = (w['waste_weight_kg'] as num?)?.toDouble() ?? (w['quantity'] as num?)?.toDouble() ?? 0.0;
                  if (wastePct <= 0) wastePct = (w['waste_percent'] as num?)?.toDouble() ?? 0.0;
                  break;
                }
              }
              final sortingList = _asList(notesMap['sorting_data']);
              for (final s in sortingList) {
                if (normalizeArabic(s['product_name']?.toString() ?? '') == normalizeArabic(pName) || sortingList.length == 1) {
                  if (sortingCost <= 0) sortingCost = (s['sorting_cost'] as num?)?.toDouble() ?? 0.0;
                  if (sortedWeight <= 0) sortedWeight = (s['sorted_weight_kg'] as num?)?.toDouble() ?? (s['quantity'] as num?)?.toDouble() ?? 0.0;
                  break;
                }
              }
            }

            final cc = _resolveProductCostCenter(
                pName, line['fruit_type_id']?.toString(), centers);

            _addOperationalEntries(
              operationalRows: operationalRows,
              shipmentDate: shipmentDate,
              shipmentNo: shipmentNo,
              customerName: customerName,
              productName: pName,
              costCenter: cc,
              poId: poId,
              orderNumber: orderNumber,
              qty: qty,
              unitPrice: unitPrice,
              rawCost: rawCost,
              wasteCost: wasteCost,
              wasteWeight: wasteWeight,
              wastePct: wastePct,
              sortingCost: sortingCost,
              sortedWeight: sortedWeight,
            );
          }
        } else {
          // Case B: Fallback to packing_orders notes JSON
          final rawNotes = po['notes']?.toString() ?? '';
          Map<String, dynamic>? notesMap;
          if (rawNotes.trim().startsWith('{')) {
            try {
              final dec = jsonDecode(rawNotes);
              if (dec is Map<String, dynamic>) notesMap = dec;
            } catch (_) {}
          }

          final fruitCostBase = (po['fruit_cost_base'] as num?)?.toDouble() ??
              (po['fruit_cost_allocated'] as num?)?.toDouble() ??
              0.0;
          final productCostPerKg =
              (notesMap?['product_cost_per_kg'] as num?)?.toDouble() ?? 0.0;

          final allocList = _asList(notesMap?['fruit_allocation'] ??
              notesMap?['order_lines'] ??
              notesMap?['lot_entries']);
          final wasteList = _asList(notesMap?['waste_data']);
          final sortingList = _asList(notesMap?['sorting_data']);

          if (allocList.isNotEmpty) {
            double accumulatedRaw = 0.0;
            for (int i = 0; i < allocList.length; i++) {
              final entry = allocList[i];
              final pName =
                  (entry['product_name'] ?? entry['name'])?.toString().trim() ?? '';
              final qty = (entry['quantity'] as num?)?.toDouble() ??
                  (entry['effective_weight'] as num?)?.toDouble() ??
                  0.0;

              // Match waste item
              Map<String, dynamic>? wItem;
              if (wasteList.isNotEmpty) {
                for (final w in wasteList) {
                  if ((w['line_index'] == i) ||
                      (normalizeArabic(w['product_name']?.toString() ?? '') ==
                          normalizeArabic(pName))) {
                    wItem = w;
                    break;
                  }
                }
              }
              final wasteCost = (wItem?['waste_cost'] as num?)?.toDouble() ?? 0.0;
              final wasteWeight = (wItem?['waste_weight_kg'] as num?)?.toDouble() ?? 0.0;
              final wastePct = (wItem?['waste_percent'] as num?)?.toDouble() ?? 0.0;

              // Match sorting item
              Map<String, dynamic>? sItem;
              if (sortingList.isNotEmpty) {
                for (final s in sortingList) {
                  if ((s['line_index'] == i) ||
                      (normalizeArabic(s['product_name']?.toString() ?? '') ==
                          normalizeArabic(pName))) {
                    sItem = s;
                    break;
                  }
                }
              }
              final sortingCost = (sItem?['sorting_cost'] as num?)?.toDouble() ?? 0.0;
              final sortedWeight = (sItem?['sorted_weight_kg'] as num?)?.toDouble() ?? 0.0;

              // Raw cost calculation
              double rawCost = 0.0;
              if (entry['raw_material_cost'] != null) {
                rawCost = (entry['raw_material_cost'] as num).toDouble();
              } else if (i == 0 && productCostPerKg > 0 && qty > 0) {
                rawCost = (qty * productCostPerKg).roundToDouble();
                accumulatedRaw += rawCost;
              } else if (i == allocList.length - 1 &&
                  fruitCostBase > accumulatedRaw &&
                  accumulatedRaw > 0) {
                rawCost = fruitCostBase - accumulatedRaw;
              } else if (productCostPerKg > 0 && qty > 0) {
                rawCost = qty * productCostPerKg;
                accumulatedRaw += rawCost;
              } else if (allocList.length == 1) {
                rawCost = fruitCostBase;
              }

              final unitPrice = qty > 0 ? (rawCost / qty) : productCostPerKg;
              final cc = _resolveProductCostCenter(
                  pName,
                  entry['fruit_type_id']?.toString() ??
                      entry['batch_id']?.toString() ??
                      entry['product_code']?.toString(),
                  centers);

              _addOperationalEntries(
                operationalRows: operationalRows,
                shipmentDate: shipmentDate,
                shipmentNo: shipmentNo,
                customerName: customerName,
                productName: pName,
                costCenter: cc,
                poId: poId,
                orderNumber: orderNumber,
                qty: qty,
                unitPrice: unitPrice,
                rawCost: rawCost,
                wasteCost: wasteCost,
                wasteWeight: wasteWeight,
                wastePct: wastePct,
                sortingCost: sortingCost,
                sortedWeight: sortedWeight,
              );
            }
          } else {
            // Single-product order without fruit_allocation array
            final pName = (po['product_name'] as String? ?? '').trim();
            final qty = (po['total_net_weight'] as num?)?.toDouble() ?? 0.0;
            final rawCost = fruitCostBase;
            final unitPrice = qty > 0 ? rawCost / qty : productCostPerKg;
            final wasteCost = (notesMap?['waste_cost'] as num?)?.toDouble() ?? 0.0;
            final wasteWeight = (notesMap?['waste_weight_kg'] as num?)?.toDouble() ?? 0.0;
            final wastePct = (notesMap?['waste_percent'] as num?)?.toDouble() ?? 0.0;
            final sortingCost = (notesMap?['sorting_cost'] as num?)?.toDouble() ?? 0.0;
            final sortedWeight = (notesMap?['sorted_weight_kg'] as num?)?.toDouble() ?? 0.0;

            final cc = _resolveProductCostCenter(
                pName, po['fruit_type_id']?.toString(), centers);

            _addOperationalEntries(
              operationalRows: operationalRows,
              shipmentDate: shipmentDate,
              shipmentNo: shipmentNo,
              customerName: customerName,
              productName: pName,
              costCenter: cc,
              poId: poId,
              orderNumber: orderNumber,
              qty: qty,
              unitPrice: unitPrice,
              rawCost: rawCost,
              wasteCost: wasteCost,
              wasteWeight: wasteWeight,
              wastePct: wastePct,
              sortingCost: sortingCost,
              sortedWeight: sortedWeight,
            );
          }
        }

        // Case C: Explicit cost items from packing_order_cost_items
        final poCostItems = costItemsByOrder[poId] ?? [];
        if (poCostItems.isNotEmpty) {
          for (final ci in poCostItems) {
            final expAmt = (ci['expected_amount'] as num?)?.toDouble() ?? 0.0;
            final actAmt = (ci['actual_amount'] as num?)?.toDouble() ?? 0.0;
            final varAmt = (ci['variance_amount'] as num?)?.toDouble() ?? (actAmt - expAmt);
            final status = ci['cost_status']?.toString() ?? 'pending';
            final effectiveAmt = actAmt > 0 ? actAmt : expAmt;
            if (effectiveAmt <= 0 && expAmt <= 0) continue;

            final rawCat = (ci['category']?.toString() ?? '').trim();
            final rawItemName = (ci['name'] ?? ci['item_name'] ?? ci['cost_name'] ?? ci['description'] ?? '').toString().trim();

            Map<String, dynamic>? snap;
            if (ci['currency_snapshot'] is Map) {
              snap = Map<String, dynamic>.from(ci['currency_snapshot'] as Map);
            } else if (ci['currency_snapshot'] is String && (ci['currency_snapshot'] as String).trim().startsWith('{')) {
              try {
                final dec = jsonDecode(ci['currency_snapshot'] as String);
                if (dec is Map) snap = Map<String, dynamic>.from(dec);
              } catch (_) {}
            }

            final suppName = (ci['supplier_name'] ?? snap?['supplier_name'] ?? snap?['engineer_name'] ?? '').toString().trim();
            final entityParty = customerName.isNotEmpty ? customerName : suppName;
            final suppType = (snap?['supplier_type'] ?? '').toString().trim();

            final branchName = CostReportDao.resolveExpenseBranchName(
              category: rawCat,
              itemName: rawItemName,
              supplierType: suppType,
            );
            final itemName = rawItemName.isNotEmpty
                ? rawItemName
                : (branchName.isNotEmpty && branchName != 'other' && branchName != 'logistics'
                    ? branchName
                    : (rawCat == 'logistics' ? 'لوجستيك ونقل' : 'مصاريف تشغيلية أخرى'));

            final origCurrency = (ci['original_currency'] ?? snap?['original_currency'] ?? snap?['currency'] ?? 'EGP').toString().trim();
            final exRate = (ci['exchange_rate'] as num?)?.toDouble() ?? (snap?['exchange_rate'] as num?)?.toDouble() ?? 1.0;
            final origAmt = (ci['original_amount'] as num?)?.toDouble() ?? (snap?['original_amount'] as num?)?.toDouble() ?? (snap?['total'] as num?)?.toDouble() ?? effectiveAmt;
            final totalInCur = (origCurrency != 'EGP' && origAmt > 0)
                ? origAmt
                : (exRate > 0 && origCurrency != 'EGP' ? effectiveAmt / exRate : effectiveAmt);

            final ciQty = (ci['quantity'] as num?)?.toDouble() ??
                (snap?['quantity'] as num?)?.toDouble() ??
                (snap?['truck_count'] as num?)?.toDouble() ??
                1.0;
            final ciUnitPrice = (ci['unit_price'] as num?)?.toDouble() ??
                (snap?['unit_price'] as num?)?.toDouble() ??
                (ciQty > 0 ? (totalInCur / ciQty) : totalInCur);

            final invoiceRef = (ci['invoice_ref'] ?? snap?['invoice_ref'] ?? '').toString().trim();
            final settlementNotes = (ci['settlement_notes'] ?? snap?['settlement_notes'] ?? snap?['notes'] ?? '').toString().trim();

            String itemDesc = itemName;
            if (invoiceRef.isNotEmpty && invoiceRef != 'null') {
              itemDesc += ' (مستند #$invoiceRef)';
            }
            if (settlementNotes.isNotEmpty && settlementNotes != 'null') {
              itemDesc += ' - $settlementNotes';
            }

            final itemCcId = ci['cost_center_id']?.toString();

            final cc = (itemCcId != null && itemCcId.isNotEmpty)
                ? CostCenterHelper.fromId(itemCcId, centers ?? [])
                : _resolveProductCostCenter(po['product_name']?.toString() ?? '', null, centers);

            operationalRows.add({
              'id': ci['id'],
              'cost_item_id': ci['id'],
              'shipment_date': shipmentDate,
              'shipment_no': shipmentNo,
              'customer_name': entityParty,
              'supplier_name': suppName,
              'category': branchName,
              'item_name': itemName,
              'description': itemDesc,
              'quantity': ciQty > 0 ? ciQty : 1.0,
              'unit_price': ciUnitPrice > 0 ? ciUnitPrice : effectiveAmt,
              'amount': effectiveAmt,
              'expected_amount': expAmt,
              'actual_amount': actAmt,
              'variance_amount': varAmt,
              'cost_status': status,
              'currency': origCurrency.isNotEmpty ? origCurrency : 'EGP',
              'exchange_rate': exRate > 0 ? exRate : 1.0,
              'total_in_currency': totalInCur,
              'cost_center_id': cc.id,
              'cost_center_name': cc.nameAr,
              'cost_center_type': cc.typeLabelAr,
              'target_product_name': po['product_name']?.toString() ?? '',
              'is_packing_operational': true,
              'is_packing_order_cost_item': true,
              'packing_order_id': poId,
              'invoice_ref': invoiceRef,
              'settlement_notes': settlementNotes,
              'notes': settlementNotes.isNotEmpty && settlementNotes != 'null'
                  ? settlementNotes
                  : 'أمر تعبئة #$orderNumber - $itemName (${status == 'actual' ? 'تسوية فعلية' : 'تقديري'})',
            });
          }
        }

        // Case D: Consumed packaging materials
        final rawMaterials = _asList(notesMap?['materials'] ?? notesMap?['material_items']);
        if (rawMaterials.isNotEmpty) {
          int matIdx = 0;
          for (final m in rawMaterials) {
            matIdx++;
            final pName = (m['product_name'] ?? m['name'] ?? 'مادة تعبئة').toString().trim();
            final usedQty = (m['used_qty'] as num?)?.toDouble() ??
                (m['quantity'] as num?)?.toDouble() ??
                0.0;
            final unitCost = (m['unit_cost'] as num?)?.toDouble() ??
                (m['unit_price'] as num?)?.toDouble() ??
                0.0;
            double matTotal = (m['total'] as num?)?.toDouble() ?? 0.0;
            if (matTotal <= 0 && usedQty > 0 && unitCost > 0) {
              matTotal = usedQty * unitCost;
            }
            if (matTotal <= 0 && usedQty <= 0) continue;

            final matCurrency = (m['currency'] ?? 'EGP').toString().trim();
            final matRate = (m['exchange_rate'] as num?)?.toDouble() ?? 1.0;
            final totalInForeign = (m['total_foreign'] as num?)?.toDouble() ??
                (matCurrency != 'EGP' && matRate > 0 ? matTotal / matRate : matTotal);
            final targetProductName = (m['target_product_name'] ?? po['product_name'] ?? '').toString().trim();

            final matCcId = m['cost_center_id']?.toString();
            final cc = (matCcId != null && matCcId.isNotEmpty)
                ? CostCenterHelper.fromId(matCcId, centers ?? [])
                : _resolveProductCostCenter(targetProductName.isNotEmpty ? targetProductName : (po['product_name']?.toString() ?? ''), null, centers);

            final suppName = (m['supplier_name']?.toString() ?? '').trim();
            final invoiceRef = (m['invoice_number'] ?? m['invoice_ref'] ?? '').toString().trim();

            operationalRows.add({
              'id': m['id'] ?? m['material_id'],
              'cost_item_id': m['id'] ?? m['material_id'],
              'shipment_date': shipmentDate,
              'shipment_no': shipmentNo,
              'customer_name': customerName.isNotEmpty ? customerName : (suppName.isNotEmpty ? suppName : 'محطة التعبئة والتجهيز'),
              'supplier_name': suppName.isNotEmpty ? suppName : 'محطة التعبئة والتجهيز',
              'category': 'مواد التعبئة',
              'item_name': pName,
              'description': 'استهلاك مادة تعبئة ($pName) - أمر #$orderNumber',
              'quantity': usedQty > 0 ? usedQty : 1.0,
              'unit_price': unitCost > 0 ? unitCost : matTotal,
              'amount': matTotal,
              'expected_amount': matTotal,
              'actual_amount': matTotal,
              'variance_amount': 0.0,
              'cost_status': 'settled',
              'currency': matCurrency.isNotEmpty ? matCurrency : 'EGP',
              'exchange_rate': matRate > 0 ? matRate : 1.0,
              'total_in_currency': totalInForeign,
              'cost_center_id': cc.id,
              'cost_center_name': cc.nameAr,
              'cost_center_type': cc.typeLabelAr,
              'target_product_name': targetProductName.isNotEmpty ? targetProductName : (po['product_name']?.toString() ?? ''),
              'is_packing_operational': true,
              'is_packing_material': true,
              'source_type': 'packing_material',
              'source_id': 'po_${poId}_mat_${m['batch_id'] ?? matIdx}',
              'packing_order_id': poId,
              'invoice_ref': invoiceRef,
              'notes': 'أمر تعبئة #$orderNumber - استهلاك مادة تعبئة ($pName) لصنف ${targetProductName.isNotEmpty ? targetProductName : (po['product_name'] ?? '')}',
            });
          }
        }

        // Case E: Packaging material waste
        final matWastePct = (notesMap?['material_waste_percent'] as num?)?.toDouble() ?? 0.0;
        final actMatCost = (po['actual_material_cost'] as num?)?.toDouble();
        final baseMatCost = (po['material_cost_base'] as num?)?.toDouble();
        double pkgWasteAmt = 0.0;
        if (actMatCost != null && baseMatCost != null && actMatCost > baseMatCost) {
          pkgWasteAmt = actMatCost - baseMatCost;
        } else if (matWastePct > 0) {
          final totalMatDrawn = rawMaterials.fold<double>(
              0.0, (s, m) => s + ((m['total'] as num?)?.toDouble() ?? 0.0));
          if (totalMatDrawn > 0) {
            pkgWasteAmt = totalMatDrawn * (matWastePct / 100.0);
          }
        }

        if (pkgWasteAmt > 0) {
          final targetProductName = (po['product_name']?.toString() ?? '').trim();
          final cc = _resolveProductCostCenter(targetProductName, null, centers);

          operationalRows.add({
            'shipment_date': shipmentDate,
            'shipment_no': shipmentNo,
            'customer_name': customerName,
            'supplier_name': 'محطة التعبئة والتجهيز',
            'category': 'تكلفة الهالك',
            'item_name': 'هالك مواد تعبئة (${matWastePct.toStringAsFixed(1)}%) - أمر #$orderNumber',
            'description': 'هالك مواد تعبئة (${matWastePct.toStringAsFixed(1)}%) - أمر #$orderNumber',
            'quantity': 1.0,
            'unit_price': pkgWasteAmt,
            'amount': pkgWasteAmt,
            'expected_amount': pkgWasteAmt,
            'actual_amount': pkgWasteAmt,
            'variance_amount': 0.0,
            'cost_status': 'settled',
            'currency': 'EGP',
            'exchange_rate': 1.0,
            'total_in_currency': pkgWasteAmt,
            'cost_center_id': cc.id,
            'cost_center_name': cc.nameAr,
            'cost_center_type': cc.typeLabelAr,
            'target_product_name': targetProductName,
            'is_packing_operational': true,
            'is_packing_waste': true,
            'source_type': 'packing_material_waste',
            'source_id': 'po_${poId}_mat_waste',
            'packing_order_id': poId,
            'notes': 'أمر تعبئة #$orderNumber - هالك مواد التعبئة والتغليف (${matWastePct.toStringAsFixed(1)}%) لصنف $targetProductName',
          });
        }
      }

      return operationalRows;
    } catch (e, st) {
      debugPrint('❌ _fetchPackingOrderOperationalRows error: $e\n$st');
      return [];
    }
  }

  /// Extracts distinct product names from packing order notes JSON
  List<String> _extractOrderProducts(Map<String, dynamic>? notesMap) {
    if (notesMap == null) return [];
    final products = <String>{};

    // 1. fruit_allocation
    final fa = notesMap['fruit_allocation'];
    if (fa is List) {
      for (final item in fa) {
        if (item is Map && item['product_name'] != null) {
          final p = item['product_name'].toString().trim();
          if (p.isNotEmpty) products.add(p);
        }
      }
    } else if (fa is Map && fa['product_name'] != null) {
      final p = fa['product_name'].toString().trim();
      if (p.isNotEmpty) products.add(p);
    }

    // 2. order_lines
    final ol = notesMap['order_lines'];
    if (ol is List) {
      for (final item in ol) {
        if (item is Map && item['product_name'] != null) {
          final p = item['product_name'].toString().trim();
          if (p.isNotEmpty) products.add(p);
        }
      }
    }

    // 3. waste_data
    final wd = notesMap['waste_data'];
    if (wd is List) {
      for (final item in wd) {
        if (item is Map && item['product_name'] != null) {
          final p = item['product_name'].toString().trim();
          if (p.isNotEmpty) products.add(p);
        }
      }
    }

    return products.toList();
  }

  Future<List<Map<String, dynamic>>> getDetails({
    String? fromDate,
    String? toDate,
    String? customer,
    String? category,
    int? shipmentId,
    String? itemName,
    String? costCenter,
    String? costCenterLabel,
    List<CostCenter>? activeCenters,
    List<CostCenter>? allCenters,
    int? limit,
    int? offset,
  }) async {
    // Fetch only needed columns from unified live view to save bandwidth
    var query = _client.from('vw_cost_details_live').select(
      'shipment_date, shipment_no, customer_name, category, item_name, quantity, unit_price, amount, currency, exchange_rate, total_in_currency, notes, shipment_id'
    );

    if (category != null && category.isNotEmpty) {
      final cLower = category.toLowerCase().trim();
      if (cLower == 'تكلفة شركات الشحن' || cLower == 'shipping' || cLower == 'freight' || cLower == 'shipping_company') {
        query = query.inFilter('category', ['تكلفة شركات الشحن', 'shipping', 'freight', 'shipping_company']);
      } else if (cLower == 'تكلفة المخلصين' || cLower == 'clearance' || cLower == 'clearing' || cLower == 'clearing_agent') {
        query = query.inFilter('category', ['تكلفة المخلصين', 'clearance', 'clearing', 'clearing_agent']);
      } else if (cLower == 'لوجستيك ونقل' || cLower == 'logistics' || cLower == 'transport') {
        query = query.inFilter('category', ['لوجستيك ونقل', 'logistics', 'transport']);
      } else if (cLower == 'تعبئة وتغليف' || cLower == 'packing' || cLower == 'packaging') {
        query = query.inFilter('category', ['تعبئة وتغليف', 'packing', 'packaging', 'manual_packing']);
      } else if (cLower == 'مواد التعبئة' || cLower == 'packing_material') {
        query = query.inFilter('category', ['مواد التعبئة', 'packing_material']);
      } else if (cLower == 'تكلفة المحاصيل' || cLower == 'crop' || cLower == 'fruit') {
        query = query.inFilter('category', ['تكلفة المحاصيل', 'crop', 'fruit', 'manual_crop']);
      } else {
        query = query.eq('category', category);
      }
    }
    if (shipmentId != null) {
      query = query.eq('shipment_id', shipmentId);
    }
    if (customer != null && customer.isNotEmpty && customer != 'all') {
      query = query.eq('customer_name', customer);
    }
    if (itemName != null && itemName.isNotEmpty) {
      query = query.eq('item_name', itemName);
    }
    if (fromDate != null && fromDate.isNotEmpty) {
      query = query.gte('shipment_date', fromDate);
    }
    if (toDate != null && toDate.isNotEmpty) {
      query = query.lte('shipment_date', toDate);
    }

    final orderedQuery = query.order('shipment_date', ascending: false);
    dynamic resultQuery = orderedQuery;
    if (limit != null) {
      if (offset != null) {
        resultQuery = orderedQuery.range(offset, offset + limit - 1);
      } else {
        resultQuery = orderedQuery.limit(limit);
      }
    }
    final result = await resultQuery;
    final centers = activeCenters ?? await getActiveCostCenters();
    final allCostCenters = allCenters ?? await getAllCostCenters();
    final lookupPool = allCostCenters.isNotEmpty ? allCostCenters : centers;

    final cleanCc = costCenter?.trim();
    final normLabel =
        costCenterLabel != null ? normalizeArabic(costCenterLabel) : '';
    final isFilteringCc =
        cleanCc != null && cleanCc.isNotEmpty && cleanCc != 'all';
    final isSharedFilter = cleanCc == 'ALL' ||
        cleanCc?.toLowerCase() == 'all' ||
        cleanCc == 'CC-ALL' ||
        cleanCc == 'توزيع بالتساوي على كل المنتجات';

    CostCenter targetCenter;
    if (isFilteringCc) {
      CostCenter? matched;
      for (final c in lookupPool) {
        if (c.id == cleanCc ||
            c.code == cleanCc ||
            (c.dbId != null && c.dbId.toString() == cleanCc) ||
            (c.code != null &&
                ('CC-${c.code}' == cleanCc || c.code == 'CC-$cleanCc')) ||
            (c.productId != null && c.productId.toString() == cleanCc) ||
            c.nameAr == cleanCc ||
            normalizeArabic(c.nameAr) == normalizeArabic(cleanCc) ||
            (normLabel.isNotEmpty && normalizeArabic(c.nameAr) == normLabel)) {
          matched = c;
          break;
        }
      }
      targetCenter = matched ?? CostCenterHelper.fromId(cleanCc, lookupPool);
      if (targetCenter.id == CostCenterHelper.generalAdmin.id &&
          cleanCc != CostCenterHelper.generalAdmin.id &&
          cleanCc != CostCenterHelper.generalAdmin.code &&
          !cleanCc.toLowerCase().contains('admin') &&
          !cleanCc.contains('عمومية') &&
          !normLabel.contains('عمومية')) {
        targetCenter = CostCenter(
          id: cleanCc,
          nameAr:
              (costCenterLabel?.isNotEmpty == true) ? costCenterLabel! : cleanCc,
          nameEn:
              (costCenterLabel?.isNotEmpty == true) ? costCenterLabel! : cleanCc,
          type: CostCenterType.variety,
          color: CostCenterHelper.resolveColor(null, cleanCc),
          icon: CostCenterHelper.resolveIcon(null, costCenterLabel ?? cleanCc),
          code: cleanCc,
        );
      }
    } else {
      targetCenter = CostCenterHelper.generalAdmin;
    }

    final enriched = <Map<String, dynamic>>[];

    final resultList = result as List;
    for (int i = 0; i < resultList.length; i++) {
      if (i > 0 && i % 40 == 0) {
        await Future.delayed(Duration.zero);
      }
      final r = resultList[i];
      final row = Map<String, dynamic>.from(r);
      final rawNotes = row['notes']?.toString() ?? '';
      Map<String, dynamic>? notesMap;
      if (rawNotes.trim().startsWith('{')) {
        try {
          final dec = jsonDecode(rawNotes);
          if (dec is Map<String, dynamic>) notesMap = dec;
        } catch (_) {}
      }

      final iName = (row['item_name'] as String? ?? '').trim();
      final totalAmount = (row['amount'] as num?)?.toDouble() ?? 0.0;

      // 1. Check if this row corresponds to a specific cost item in packing order notes
      Map<String, dynamic>? matchedCostItem;
      if (notesMap != null && notesMap['cost_items'] is List) {
        for (final ci in notesMap['cost_items']) {
          if (ci is Map && (ci['name']?.toString().trim() == iName)) {
            matchedCostItem = Map<String, dynamic>.from(ci);
            break;
          }
        }
      }

      // 2. Check if this row corresponds to a packaging material in packing order notes
      Map<String, dynamic>? matchedMaterial;
      if (notesMap != null && notesMap['materials'] is List) {
        for (final mat in notesMap['materials']) {
          if (mat is Map) {
            final pName = (mat['product_name'] ?? mat['name'])?.toString().trim();
            if (pName == iName) {
              matchedMaterial = Map<String, dynamic>.from(mat);
              break;
            }
          }
        }
      }

      final orderProducts = _extractOrderProducts(notesMap);

      if (matchedMaterial != null) {
        final matAllocMethod =
            matchedMaterial['allocation_method']?.toString().toUpperCase();
        final matCostCenterId = matchedMaterial['cost_center_id']?.toString();
        final matTargetProduct =
            matchedMaterial['target_product_name']?.toString();
        final matApplyTo = matchedMaterial['apply_to']?.toString() ?? '';

        final isExplicitEqual = (matAllocMethod == 'EQUAL' ||
                matCostCenterId == 'ALL') &&
            orderProducts.length > 1 &&
            (matApplyTo == 'all' || matApplyTo.isEmpty);

        if (isExplicitEqual) {
          row['is_equal_distribution'] = true;
          row['order_products'] = orderProducts;
          row['total_shared_amount'] = totalAmount;
          row['cost_center_id'] = 'ALL';
          row['cost_center_name'] = 'توزيع بالتساوي على كل المنتجات';
          row['cost_center_type'] = 'مشترك بين المحاصيل';
          enriched.add(row);
          continue;
        } else {
          // Direct packaging material allocation to specific product line
          if (matCostCenterId != null &&
              matCostCenterId.isNotEmpty &&
              matCostCenterId != 'ALL' &&
              matCostCenterId != 'all') {
            row['cost_center_id'] = matCostCenterId;
          }
          if (matTargetProduct != null && matTargetProduct.isNotEmpty) {
            row['target_product_name'] = matTargetProduct;
          } else if (matApplyTo.startsWith('line:') &&
              notesMap != null &&
              notesMap['lot_entries'] is List) {
            final idx = int.tryParse(matApplyTo.substring(5));
            if (idx != null &&
                idx >= 0 &&
                idx < (notesMap['lot_entries'] as List).length) {
              final entry = notesMap['lot_entries'][idx];
              if (entry is Map && entry['product_name'] != null) {
                row['target_product_name'] = entry['product_name'].toString();
              }
            }
          } else if (orderProducts.length == 1) {
            row['target_product_name'] = orderProducts.first;
          }

          final cc = CostCenterHelper.resolve(row, centers);
          row['cost_center_id'] = cc.id;
          row['cost_center_name'] = cc.nameAr;
          row['cost_center_name_en'] = cc.nameEn;
          row['cost_center_type'] = cc.typeLabelAr;
          enriched.add(row);
          continue;
        }
      }

      final allocMethod =
          matchedCostItem?['allocation_method']?.toString().toUpperCase();
      final ciCostCenterId = matchedCostItem?['cost_center_id']?.toString();
      final ciTargetProduct =
          matchedCostItem?['target_product_name']?.toString();

      final isExplicitEqual =
          allocMethod == 'EQUAL' || ciCostCenterId == 'ALL';

      if (isExplicitEqual && orderProducts.length > 1) {
        row['is_equal_distribution'] = true;
        row['order_products'] = orderProducts;
        row['total_shared_amount'] = totalAmount;
        row['cost_center_id'] = 'ALL';
        row['cost_center_name'] = 'توزيع بالتساوي على كل المنتجات';
        row['cost_center_type'] = 'مشترك بين المحاصيل';
        enriched.add(row);
      } else {
        // Direct assignment to specific cost center or product line
        if (ciCostCenterId != null &&
            ciCostCenterId.isNotEmpty &&
            ciCostCenterId != 'ALL' &&
            ciCostCenterId != 'all') {
          row['cost_center_id'] = ciCostCenterId;
        }
        if (ciTargetProduct != null && ciTargetProduct.isNotEmpty) {
          row['target_product_name'] = ciTargetProduct;
        } else if (orderProducts.length == 1) {
          row['target_product_name'] = orderProducts.first;
        }

        final isCropCategory = row['category'] == 'تكلفة المحاصيل' ||
            row['category'] == 'crop' ||
            row['category'] == 'fruit' ||
            row['category'] == 'manual_crop';

        final isLotReturn = isCropCategory &&
            (((row['amount'] as num?)?.toDouble() ?? 0.0) < 0 ||
             (row['item_name']?.toString().startsWith('مرتجع') ?? false));

        final isLotReceipt = !isLotReturn &&
            matchedMaterial == null &&
            matchedCostItem == null &&
            isCropCategory &&
            (notesMap == null ||
                (notesMap['materials'] == null &&
                    notesMap['cost_items'] == null &&
                    notesMap['fruit_allocation'] == null));

        row['is_lot_receipt'] = isLotReceipt;
        row['is_lot_return'] = isLotReturn;
        final rawCat = (row['category']?.toString() ?? '').trim().toLowerCase();
        if (isCropCategory || rawCat == 'crop' || rawCat == 'fruit' || rawCat == 'manual_crop') {
          row['category'] = 'تكلفة المحاصيل';
        } else if (rawCat == 'shipping' || rawCat == 'freight' || rawCat == 'shipping_company') {
          row['category'] = 'تكلفة شركات الشحن';
        } else if (rawCat == 'clearance' || rawCat == 'clearing' || rawCat == 'clearing_agent') {
          row['category'] = 'تكلفة المخلصين';
        } else if (rawCat == 'transport' || rawCat == 'logistics') {
          row['category'] = 'لوجستيك ونقل';
        } else if (rawCat == 'packing' || rawCat == 'packaging' || rawCat == 'manual_packing') {
          row['category'] = 'تعبئة وتغليف';
        } else if (rawCat == 'packing_material') {
          row['category'] = 'مواد التعبئة';
        }
        if (isLotReceipt && (row['customer_name'] == null || row['customer_name'].toString().isEmpty)) {
          row['customer_name'] = row['supplier_name'] ?? 'مورد محصول';
        }

        final cc = CostCenterHelper.resolve(row, centers);
        row['cost_center_id'] = cc.id;
        row['cost_center_name'] = cc.nameAr;
        row['cost_center_name_en'] = cc.nameEn;
        row['cost_center_type'] = cc.typeLabelAr;
        enriched.add(row);
      }
    }

    // 2. Fetch operational packing order lines (raw material, waste, sorting)
    final operationalRows = await _fetchPackingOrderOperationalRows(
      fromDate: fromDate,
      toDate: toDate,
      customer: customer,
      shipmentId: shipmentId,
      centers: centers,
    );

    // 3. Fetch dedicated cost center transactions (recorded crop purchases & direct lot receipts)
    final cctRows = <Map<String, dynamic>>[];
    List<dynamic> allCctRecords = [];
    try {
      var cctQuery = _client.from('cost_center_transactions').select();
      if (fromDate != null && fromDate.isNotEmpty) {
        cctQuery = cctQuery.gte('transaction_date', fromDate);
      }
      if (toDate != null && toDate.isNotEmpty) {
        cctQuery = cctQuery.lte('transaction_date', toDate);
      }
      final cctData = await cctQuery.order('transaction_date', ascending: false);
      final cctList = cctData as List<dynamic>;
      allCctRecords = cctList;
      for (int i = 0; i < cctList.length; i++) {
        if (i > 0 && i % 40 == 0) {
          await Future.delayed(Duration.zero);
        }
        final c = cctList[i];
        final cct = Map<String, dynamic>.from(c);
        final cc = CostCenterHelper.fromId(cct['cost_center_id']?.toString(), lookupPool);
        if (isFilteringCc && !isSharedFilter) {
          final cctCcId = cct['cost_center_id']?.toString();
          final cctProdId = cct['product_id']?.toString();
          final cctName = cct['cost_center_name']?.toString() ??
              cct['item_name']?.toString() ??
              '';
          final normCctName = normalizeArabic(cctName);
          final normTarget = normalizeArabic(targetCenter.nameAr);

          final targetCode = targetCenter.code ?? targetCenter.id;
          final targetSeason = targetCenter.season ?? extractSeason(targetCode) ?? extractSeason(targetCenter.nameAr);

          // STRICT YEAR/SEASON & CLOSED CENTER ISOLATION:
          // If transaction belongs to a closed/different cost center and target is active, skip it
          if (cc.id != targetCenter.id &&
              cc.code != targetCenter.code &&
              (targetCenter.dbId == null || cc.dbId != targetCenter.dbId)) {
            final sId = cct['source_id']?.toString() ?? '';
            final isRolloverIntoTarget = sId.contains('_to_${targetCenter.dbId}') ||
                sId.contains('_to_${targetCenter.code}') ||
                sId.contains('_to_${targetCenter.id}');
            if (!isRolloverIntoTarget && (cc.isClosed || cc.isPermanentlyClosed)) {
              continue;
            }
          }

          // If target center belongs to a specific agricultural year/season (e.g. 2026-2027 or 2027-2028),
          // strictly reject ANY transaction that specifies a different agricultural year/season!
          if (targetSeason != null && targetSeason.isNotEmpty) {
            final rowSeason = extractSeason(cctCcId) ??
                extractSeason(cctName) ??
                extractSeason(cct['season']?.toString()) ??
                extractSeason(cct['item_name']?.toString()) ??
                cc.season;
            if (rowSeason != null && rowSeason.isNotEmpty && rowSeason != targetSeason) {
              continue;
            }
          }

          // PERIOD ISOLATION GUARD:
          // If the target cost center is period-qualified (e.g. CC-MANGO-2026-2027-P2),
          // then ONLY accept an exact cost_center_id match — skip slug/name fuzzy matching.
          // This prevents Period 1 records bleeding into Period 2 views (and vice-versa).
          final targetIsPeriodQualified =
              RegExp(r'-P\d+$').hasMatch(targetCode) ||
              RegExp(r'-P\d+$').hasMatch(cleanCc);

          final cctCanonCrop = CostCenter.canonicalCropName(cctName);
          final cctSlug = CostCenterHelper.resolveCropSlug(cctCanonCrop.isNotEmpty ? cctCanonCrop : cctName);
          final targetCanonCrop = CostCenter.canonicalCropName(targetCenter.nameAr);
          final targetSlug = targetCenter.cropCode ?? CostCenterHelper.resolveCropSlug(targetCanonCrop);

          final matchesDirectId = cctCcId != null &&
              (cctCcId == targetCenter.id ||
                  cctCcId == cleanCc ||
                  (targetCenter.code != null && cctCcId == targetCenter.code) ||
                  (targetCenter.dbId != null &&
                      cctCcId == targetCenter.dbId.toString()));

          final matchesProd = targetCenter.productId != null &&
              (cctCcId == targetCenter.productId.toString() ||
                  cctProdId == targetCenter.productId.toString());

          final bool matchesCct;
          if (targetSeason != null && targetSeason.isNotEmpty) {
            matchesCct = matchesDirectId ||
                matchesProd ||
                cc.id == targetCenter.id ||
                cc.code == targetCenter.code ||
                (normCctName == normTarget && !targetIsPeriodQualified);
          } else {
            final matchesCropSlug = !targetIsPeriodQualified &&
                ((targetSlug != 'CROP' && (targetSlug == cctSlug || cctCcId == 'CC-$targetSlug')) ||
                (targetCenter.cropName != null && cctCanonCrop.isNotEmpty && targetCenter.cropName == cctCanonCrop));

            matchesCct = matchesDirectId ||
                matchesProd ||
                cc.id == targetCenter.id ||
                (!targetIsPeriodQualified &&
                    cc.cropCode != null &&
                    targetSlug != 'CROP' &&
                    cc.cropCode == targetSlug) ||
                matchesCropSlug ||
                (!targetIsPeriodQualified && normCctName == normTarget) ||
                (!targetIsPeriodQualified && normLabel.isNotEmpty && normCctName == normLabel);
          }

          if (!matchesCct) continue;
        }

        // Defensive filter: skip non-positive remainder rollovers
        final sId = cct['source_id']?.toString() ?? '';
        final sType = cct['source_type']?.toString() ?? '';
        final sAmt = (cct['amount'] as num?)?.toDouble() ??
            (cct['total_cost_egp'] as num?)?.toDouble() ??
            0.0;
        if (sType == 'season_rollover' && sId.endsWith('_remainder') && sAmt <= 0) {
          continue;
        }

        final qty = (cct['quantity'] as num?)?.toDouble() ?? 0.0;
        final unitPrice = (cct['unit_price'] as num?)?.toDouble() ?? 0.0;
        final totalEgp = (cct['amount'] as num?)?.toDouble() ??
            (cct['total_cost_egp'] as num?)?.toDouble() ??
            0.0;
        final exchangeRate = (cct['exchange_rate'] as num?)?.toDouble() ?? 1.0;
        final currency = cct['currency']?.toString() ?? 'EGP';
        final totalInCurrency = (cct['total_in_currency'] as num?)?.toDouble() ??
            ((currency != 'EGP' && exchangeRate > 0)
                ? (totalEgp / exchangeRate)
                : (qty > 0 && unitPrice > 0 ? qty * unitPrice : totalEgp));

        final isPurchase = cct['source_type'] == 'purchase' ||
            cct['source_type'] == 'crop_purchase' ||
            cct['source_type'] == 'purchase_order';
        final isRollover = cct['source_type'] == 'season_rollover' ||
            cct['transaction_type'] == 'carried_forward' ||
            (cct['source_id']?.toString().startsWith('rollover_') ?? false) ||
            (cct['item_name']?.toString().startsWith('رصيد مرحل') ?? false);
        final isOpening = cct['is_opening_balance'] == true ||
            cct['transaction_type'] == 'carried_forward' ||
            cct['source_type'] == 'opening_balance' ||
            cct['source_type'] == 'initial_stock' ||
            cct['source_type'] == 'raw_material_opening' ||
            isRollover;
        final isSortingSale = cct['source_type'] == 'sorting_sale' ||
            cct['source_type'] == 'sale_sorting';
        final isReturn = cct['source_type'] == 'lot_return' ||
            cct['source_type'] == 'crop_return';
        final isLotReceipt = cct['source_type'] == 'lot_receipt';

        final effectiveAmount = (isSortingSale || isReturn) ? -totalEgp.abs() : totalEgp;
        final effectiveTotalInCurrency = (isSortingSale || isReturn) ? -totalInCurrency.abs() : totalInCurrency;
        final rawEffectiveQty = isReturn ? -qty.abs() : qty;

        double cctFinalQty = rawEffectiveQty;
        double cctFinalUnitPrice = unitPrice;
        if (cctFinalUnitPrice <= 0 && cctFinalQty.abs() > 0 && effectiveTotalInCurrency != 0) {
          cctFinalUnitPrice = (effectiveTotalInCurrency / cctFinalQty).abs();
        } else if (cctFinalQty == 0 && cctFinalUnitPrice > 0 && effectiveTotalInCurrency != 0) {
          cctFinalQty = effectiveTotalInCurrency / cctFinalUnitPrice;
        } else if (cctFinalQty == 0 && cctFinalUnitPrice <= 0 && effectiveTotalInCurrency != 0) {
          cctFinalQty = effectiveTotalInCurrency < 0 ? -1.0 : 1.0;
          cctFinalUnitPrice = effectiveTotalInCurrency.abs();
        }

        final isExportReturnWaste = cct['source_type'] == 'export_return_waste' ||
            cct['source_type'] == 'export_return_crop_waste' ||
            cct['source_type'] == 'export_return_material_waste';
        final isExportReturnExpense = cct['source_type'] == 'export_return_expense';
        final isExportReturn = isExportReturnWaste || isExportReturnExpense;
        final isExportSale = cct['source_type'] == 'export_shipment' ||
            cct['source_type'] == 'export_sale';
        final isPackingMaterial = cct['source_type'] == 'packing_material';
        final isPackingWaste = cct['source_type'] == 'packing_waste' ||
            cct['source_type'] == 'packing_material_waste' ||
            cct['source_type'] == 'packing_crop_waste';
        final isPackingOp = isPackingMaterial || isPackingWaste;

        final String shipmentNo;
        if (isExportReturn) {
          final notesStr = cct['notes']?.toString() ?? '';
          final exrMatch = RegExp(r'EXR-\d+').firstMatch(notesStr)?.group(0);
          final sId = cct['source_id']?.toString() ?? '';
          final exrInSource = RegExp(r'EXR-\d+').firstMatch(sId)?.group(0);
          shipmentNo = exrMatch ?? exrInSource ?? (cct['shipment_no']?.toString() ?? 'مرتجع من المطار');
        } else if (isExportSale) {
          final sNo = cct['shipment_no']?.toString();
          final notesStr = cct['notes']?.toString() ?? '';
          final match = RegExp(r'شحنة:?\s*([^\s|-]+)').firstMatch(notesStr)?.group(1);
          shipmentNo = sNo ?? match ?? 'شحنة تصدير';
        } else if (isPackingOp) {
          final sId = cct['source_id']?.toString() ?? '';
          final poMatch = RegExp(r'po_(\d+)').firstMatch(sId)?.group(1);
          final notesStr = cct['notes']?.toString() ?? '';
          final poNotesMatch = RegExp(r'أمر تعبئة #?(\d+)').firstMatch(notesStr)?.group(1);
          final poNum = poMatch ?? poNotesMatch;
          shipmentNo = poNum != null ? 'أمر تعبئة #$poNum' : (cct['shipment_no']?.toString() ?? 'أمر تعبئة');
        } else if (isRollover) {
          shipmentNo = 'رصيد مرحل';
        } else if (isOpening) {
          shipmentNo = 'رصيد أول المدة';
        } else if (isPurchase) {
          shipmentNo = 'فاتورة مشتريات';
        } else if (isSortingSale) {
          shipmentNo = 'بيع فرز';
        } else if (isReturn) {
          shipmentNo = 'مرتجع شراء محصول';
        } else if (cct['source_type'] == 'crop_purchase') {
          shipmentNo = 'شراء محصول';
        } else {
          shipmentNo = 'استلام لوط';
        }

        final String customerName = cct['customer_name']?.toString() ??
            cct['supplier_name']?.toString() ??
            (isExportSale
                ? (cct['supplier_name'] ?? 'عميل تصدير')
                : (isExportReturn
                    ? (cct['supplier_name'] ?? 'مرتجع شحنة من المطار')
                    : (isPackingOp
                        ? (cct['supplier_name'] ?? 'محطة التعبئة والتجهيز')
                        : (isRollover
                            ? 'رصيد افتتاحي للموسم الجديد'
                            : (isSortingSale
                                ? 'عميل نقدي / مبيعات فرزة'
                                : (isOpening
                                    ? 'رصيد افتتاحي'
                                    : (isReturn
                                        ? (cct['supplier_name'] ?? 'مورد محصول (مرتجع)')
                                        : (isPurchase ? 'مورد مواد تعبئة' : 'مورد محصول'))))))));

        final String? supplierName = cct['supplier_name']?.toString() ??
            (isExportSale
                ? cct['customer_name']?.toString()
                : (isExportReturn
                    ? cct['supplier_name']?.toString()
                    : (isPackingOp
                        ? 'محطة التعبئة والتجهيز'
                        : (isRollover ? 'رصيد مرحل' : (isOpening ? 'رصيد افتتاحي' : null)))));

        final String categoryName = cct['category']?.toString() ??
            (isExportSale
                ? 'إيرادات المبيعات'
                : (isExportReturnWaste || isPackingWaste
                    ? 'تكلفة الهالك'
                    : (isPackingMaterial
                        ? 'مواد التعبئة'
                        : (isExportReturnExpense
                            ? 'لوجستيك ونقل'
                            : (isRollover
                                ? 'رصيد افتتاحي'
                                : (isSortingSale
                                    ? 'تكلفة الفرز'
                                    : (isReturn
                                        ? 'تكلفة المحاصيل'
                                        : (isPurchase ? 'مواد التعبئة' : resolveCostCenterCategory(cc)))))))));

        final String? packingOrderNum = cct['packing_order_number']?.toString() ??
            RegExp(r'أمر تعبئة:?\s*#?([^\s|-]+)').firstMatch(cct['notes']?.toString() ?? '')?.group(1);
        final dynamic packingOrderId = cct['packing_order_id'];

        cctRows.add({
          'id': 'cct_${cct['id']}',
          'source_type': cct['source_type'],
          'source_id': cct['source_id']?.toString(),
          'shipment_id': null,
          'shipment_no': shipmentNo,
          'shipment_date': cct['transaction_date']?.toString(),
          'date': cct['transaction_date']?.toString(),
          'created_at': cct['created_at']?.toString(),
          'season_number': cct['season_number'],
          'season_status': cct['season_status'] ?? cc.seasonStatus,
          'season': cct['season'] ?? cc.season,
          'customer_name': customerName,
          'supplier_name': supplierName,
          'category': categoryName,
          'item_name': cct['item_name'] ??
              (isRollover
                  ? 'رصيد مرحل من موسم سابق'
                  : (isSortingSale
                      ? 'بيع فرز'
                      : (isReturn
                          ? 'مرتجع محصول'
                          : (isPackingMaterial ? 'مادة تعبئة' : (isPackingWaste ? 'تكلفة الهالك' : (isPurchase || isOpening ? 'مواد تعبئة' : 'شراء محصول')))))),
          'quantity': cctFinalQty,
          'unit_price': cctFinalUnitPrice,
          'amount': effectiveAmount,
          'currency': currency,
          'exchange_rate': exchangeRate,
          'total_in_currency': effectiveTotalInCurrency,
          'notes': cct['notes'],
          'cost_center_id': cc.id,
          'cost_center_name': cc.nameAr,
          'cost_center_name_en': cc.nameEn,
          'cost_center_type': cc.typeLabelAr,
          'target_product_name': cct['item_name']?.toString()
              .replaceFirst('إيراد بيع فرز - ', '')
              .replaceFirst('مبيعات فرزة - ', '')
              .replaceFirst('مرتجع شراء محصول خام ', '')
              .replaceFirst('مرتجع محصول - ', '') ?? cc.nameAr,
          'packing_order_number': packingOrderNum,
          'packing_order_id': packingOrderId,
          'is_export_sale': isExportSale,
          'is_lot_receipt': isLotReceipt,
          'is_opening_balance': isOpening,
          'is_rollover': isRollover,
          'transaction_type': cct['transaction_type'] ?? (isOpening ? 'carried_forward' : 'operational'),
          'is_sorting_sale': isSortingSale,
          'is_lot_return': isReturn,
          'is_purchase': isPurchase,
          'is_export_return': isExportReturn,
          'is_export_return_waste': isExportReturnWaste,
          'is_export_return_expense': isExportReturnExpense,
          'is_packing_operational': isPackingOp,
          'is_packing_material': isPackingMaterial,
          'is_packing_waste': isPackingWaste,
          'description': cct['item_name'] ?? (isPackingMaterial ? 'استهلاك مادة تعبئة' : (isPackingWaste ? 'تكلفة الهالك' : 'حركة مركز تكلفة')),
        });
      }
    } catch (e) {
      debugPrint('Cost center transactions query fallback: $e');
    }

    // 3b. Direct fallback query from confirmed purchase_invoices + items for packaging materials
    try {
      Map<String, String> rmNames = {};
      if (_cachedRmNames != null &&
          _rmCacheTimestamp != null &&
          DateTime.now().difference(_rmCacheTimestamp!).inMinutes < 10) {
        rmNames = _cachedRmNames!;
      } else {
        try {
          final rmList = await _client.from('raw_materials').select('id, name, code');
          for (final rm in rmList) {
            final id = rm['id']?.toString() ?? '';
            final name = (rm['name']?.toString() ?? rm['code']?.toString() ?? '').trim();
            if (id.isNotEmpty && name.isNotEmpty) rmNames[id] = name;
          }
          _cachedRmNames = rmNames;
          _rmCacheTimestamp = DateTime.now();
        } catch (_) {}
      }

      var piQuery = _client
          .from('purchase_invoices')
          .select('id, invoice_number, invoice_date, currency, exchange_rate, supplier_id, suppliers(name), purchase_invoice_items(id, raw_material_id, quantity, unit_cost, total_cost, exchange_rate, cost_center_id)')
          .eq('status', 'confirmed');
      if (fromDate != null && fromDate.isNotEmpty) {
        piQuery = piQuery.gte('invoice_date', fromDate);
      }
      if (toDate != null && toDate.isNotEmpty) {
        piQuery = piQuery.lte('invoice_date', toDate);
      }
      final piData = await piQuery.order('invoice_date', ascending: false);
      final piList = piData as List<dynamic>;
      for (int i = 0; i < piList.length; i++) {
        if (i > 0 && i % 40 == 0) {
          await Future.delayed(Duration.zero);
        }
        final pi = piList[i];
        final invoiceMap = Map<String, dynamic>.from(pi as Map);
        final invId = invoiceMap['id']?.toString() ?? '';
        final invNumber = invoiceMap['invoice_number']?.toString() ?? invId;
        final invDate = invoiceMap['invoice_date']?.toString() ?? '';
        final invCurrency = invoiceMap['currency']?.toString() ?? 'EGP';
        final invExRate = (invoiceMap['exchange_rate'] as num?)?.toDouble() ?? 1.0;
        final supplierMap = invoiceMap['suppliers'] is Map ? invoiceMap['suppliers'] as Map : null;
        final supplierName = supplierMap?['name']?.toString() ?? 'مورد مواد تعبئة';

        final itemsList = invoiceMap['purchase_invoice_items'] is List
            ? invoiceMap['purchase_invoice_items'] as List
            : [];

        for (final itm in itemsList) {
          final itemMap = Map<String, dynamic>.from(itm as Map);
          final itemId = itemMap['id']?.toString() ?? '';
          final explicitCcId = itemMap['cost_center_id']?.toString();

          if (isFilteringCc && !isSharedFilter) {
            final isTargetPacking = targetCenter.id == CostCenterHelper.packingStation.id ||
                targetCenter.code == 'CC-PACKING';
            if (!isTargetPacking) {
              final itmSlug = CostCenterHelper.resolveCropSlug(explicitCcId ?? '');
              final targetCanonCrop = CostCenter.canonicalCropName(targetCenter.nameAr);
              final targetSlug = targetCenter.cropCode ?? CostCenterHelper.resolveCropSlug(targetCanonCrop);

              final matchesItm = explicitCcId != null &&
                  (explicitCcId == targetCenter.id ||
                      explicitCcId == cleanCc ||
                      explicitCcId == targetCenter.code ||
                      (targetSlug != 'CROP' && (itmSlug == targetSlug || explicitCcId == 'CC-$targetSlug')));
              if (!matchesItm) continue;
            }
          }

          final rmId = itemMap['raw_material_id']?.toString();
          final rawMaterialName = (rmId != null ? rmNames[rmId] : null) ?? 'مادة تعبئة';
          final qty = (itemMap['quantity'] as num?)?.toDouble() ?? 0.0;
          final unitCost = (itemMap['unit_cost'] as num?)?.toDouble() ?? 0.0;
          final itemExRate = (itemMap['exchange_rate'] as num?)?.toDouble() ?? invExRate;
          final totalForeign = (itemMap['total_cost'] as num?)?.toDouble() ?? (qty * unitCost);
          final totalEgp = totalForeign * (itemExRate > 0 ? itemExRate : 1.0);
          final cc = CostCenterHelper.fromId(explicitCcId ?? 'packing_station', centers);

          final sig = 'pii_$itemId';
          final alreadyPresent = cctRows.any((r) =>
              r['source_id'] == sig ||
              r['source_id'] == 'pii_$itemId' ||
              (r['shipment_date'] == invDate &&
               normalizeArabic(r['item_name']?.toString() ?? '') == normalizeArabic(rawMaterialName) &&
               ((r['amount'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0) == totalEgp.toStringAsFixed(0)));

          if (!alreadyPresent) {
            cctRows.add({
              'id': 'pii_$itemId',
              'source_type': 'purchase',
              'source_id': 'pii_$itemId',
              'shipment_id': null,
              'shipment_no': 'فاتورة مشتريات #$invNumber',
              'shipment_date': invDate,
              'customer_name': supplierName,
              'supplier_name': supplierName,
              'category': 'مواد التعبئة',
              'item_name': rawMaterialName,
              'quantity': qty,
              'unit_price': unitCost > 0 ? unitCost : (qty > 0 ? totalForeign / qty : 0.0),
              'amount': totalEgp,
              'currency': invCurrency,
              'exchange_rate': itemExRate,
              'total_in_currency': totalForeign,
              'notes': 'فاتورة مشتريات رقم $invNumber - $rawMaterialName',
              'cost_center_id': cc.id,
              'cost_center_name': cc.nameAr,
              'cost_center_name_en': cc.nameEn,
              'cost_center_type': cc.typeLabelAr,
              'is_lot_receipt': false,
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Direct purchase_invoices query fallback: $e');
    }

    // 3c. Direct fallback query from export_shipment_returns for airport return waste and expenses
    if (centers.isNotEmpty) {
      try {
        final returnsList = await _client.from('export_shipment_returns').select('*, export_shipments(shipment_no, customer_name)');
        for (final ret in returnsList) {
          final retId = ret['id'];
          final retNo = ret['return_number']?.toString() ?? 'EXR-$retId';
          final retDate = ret['return_date']?.toString();
          final retCcId = ret['cost_center_id']?.toString() ?? 'CC-MANGO-2026-2027';
          final shipData = ret['export_shipments'] is Map ? ret['export_shipments'] as Map : null;
          final shipmentNo = shipData?['shipment_no']?.toString() ?? retNo;
          final customerName = shipData?['customer_name']?.toString() ?? 'مرتجع شحنة من المطار';

          final hasMatchInCenters = centers.any((c) =>
              c.id == retCcId ||
              c.code == retCcId ||
              (c.cropCode != null && c.cropCode != 'CROP' && retCcId.contains(c.cropCode!)));
          if (!hasMatchInCenters) continue;

          final cc = CostCenterHelper.fromId(retCcId, centers);

          if (isFilteringCc && !isSharedFilter) {
            final retSlug = CostCenterHelper.resolveCropSlug(retCcId);
            final targetCanonCrop = CostCenter.canonicalCropName(targetCenter.nameAr);
            final targetSlug = targetCenter.cropCode ?? CostCenterHelper.resolveCropSlug(targetCanonCrop);

            final matchesRet = retCcId == targetCenter.id ||
                retCcId == cleanCc ||
                retCcId == targetCenter.code ||
                (targetSlug != 'CROP' && (retSlug == targetSlug || retCcId == 'CC-$targetSlug'));
            if (!matchesRet) continue;
          }

          // 1. Crop Waste
          final cropWaste = (ret['crop_waste_cost'] as num?)?.toDouble() ?? 0.0;
          final damagedCropWeight = (ret['damaged_crop_weight'] as num?)?.toDouble() ?? 0.0;
          if (cropWaste > 0 || damagedCropWeight > 0) {
            final cropSourceId = 'exr_crop_waste_${retNo}_$retId';
            final alreadyPresent = cctRows.any((r) =>
                r['source_id'] == cropSourceId ||
                r['source_id']?.toString().startsWith('exr_crop_waste_$retNo') == true);
            if (!alreadyPresent) {
              final cropQty = damagedCropWeight > 0 ? damagedCropWeight : 1.0;
              final cropUnitPrice = cropWaste / cropQty;
              cctRows.add({
                'id': cropSourceId,
                'source_type': 'export_return_waste',
                'source_id': cropSourceId,
                'shipment_id': ret['shipment_id'],
                'shipment_no': retNo,
                'shipment_date': retDate,
                'customer_name': customerName,
                'supplier_name': null,
                'category': 'تكلفة الهالك',
                'item_name': 'هالك رجوع شحنة (محصول) - شحنة #$shipmentNo',
                'quantity': cropQty,
                'unit_price': cropUnitPrice,
                'amount': cropWaste,
                'currency': 'EGP',
                'exchange_rate': 1.0,
                'total_in_currency': cropWaste,
                'notes': 'هالك وتلف محصول عند رجوع الشحنة التصديرية رقم $shipmentNo ($retNo)',
                'cost_center_id': cc.id,
                'cost_center_name': cc.nameAr,
                'cost_center_name_en': cc.nameEn,
                'cost_center_type': cc.typeLabelAr,
                'is_export_return': true,
                'is_export_return_waste': true,
              });
            }
          }

          // 2. Material Waste
          final matWaste = (ret['material_waste_cost'] as num?)?.toDouble() ?? 0.0;
          final damagedCartons = (ret['damaged_cartons'] as num?)?.toDouble() ?? 0.0;
          if (matWaste > 0 || damagedCartons > 0) {
            final matSourceId = 'exr_mat_waste_${retNo}_$retId';
            final alreadyPresent = cctRows.any((r) =>
                r['source_id'] == matSourceId ||
                r['source_id']?.toString().startsWith('exr_mat_waste_$retNo') == true);
            if (!alreadyPresent) {
              final matQty = damagedCartons > 0 ? damagedCartons : 1.0;
              final matUnitPrice = matWaste / matQty;
              cctRows.add({
                'id': matSourceId,
                'source_type': 'export_return_waste',
                'source_id': matSourceId,
                'shipment_id': ret['shipment_id'],
                'shipment_no': retNo,
                'shipment_date': retDate,
                'customer_name': customerName,
                'supplier_name': null,
                'category': 'مواد التعبئة',
                'item_name': 'هالك رجوع شحنة (كراتين) - شحنة #$shipmentNo',
                'quantity': matQty,
                'unit_price': matUnitPrice,
                'amount': matWaste,
                'currency': 'EGP',
                'exchange_rate': 1.0,
                'total_in_currency': matWaste,
                'notes': 'هالك كراتين ومواد تعبئة عند رجوع الشحنة التصديرية رقم $shipmentNo ($retNo)',
                'cost_center_id': cc.id,
                'cost_center_name': cc.nameAr,
                'cost_center_name_en': cc.nameEn,
                'cost_center_type': cc.typeLabelAr,
                'is_export_return': true,
                'is_export_return_waste': true,
              });
            }
          }

          // 3. Extra Return Expenses
          final rawData = ret['raw_data'];
          if (rawData is Map && rawData['extra_expenses'] is List) {
            final expList = rawData['extra_expenses'] as List;
            for (int i = 0; i < expList.length; i++) {
              final exp = expList[i];
              if (exp is Map) {
                final amt = (exp['amount'] as num?)?.toDouble() ?? 0.0;
                if (amt <= 0) continue;
                final expSourceId = 'exr_exp_${retNo}_$i';
                final alreadyPresent = cctRows.any((r) => r['source_id'] == expSourceId);
                if (!alreadyPresent) {
                  final expName = exp['name']?.toString() ?? 'مصروف رجوع شحنة';
                  final suppName = exp['supplier_name']?.toString();
                  cctRows.add({
                    'id': expSourceId,
                    'source_type': 'export_return_expense',
                    'source_id': expSourceId,
                    'shipment_id': ret['shipment_id'],
                    'shipment_no': retNo,
                    'shipment_date': retDate,
                    'customer_name': suppName ?? customerName,
                    'supplier_name': suppName,
                    'category': (expName.contains('نولون') || expName.contains('نقل')) ? 'لوجستيك ونقل' : 'لوجستيك ونقل',
                    'item_name': expName,
                    'quantity': 1.0,
                    'unit_price': amt,
                    'amount': amt,
                    'currency': 'EGP',
                    'exchange_rate': 1.0,
                    'total_in_currency': amt,
                    'notes': 'مصروف رجوع شحنة تصدير رقم $shipmentNo ($retNo)',
                    'cost_center_id': cc.id,
                    'cost_center_name': cc.nameAr,
                    'cost_center_name_en': cc.nameEn,
                    'cost_center_type': cc.typeLabelAr,
                    'is_export_return': true,
                    'is_export_return_expense': true,
                  });
                }
              }
            }
          } else if (((ret['extra_expenses_cost'] as num?)?.toDouble() ?? 0.0) > 0) {
            final expCost = (ret['extra_expenses_cost'] as num).toDouble();
            final expSourceId = 'exr_exp_${retNo}_total';
            final alreadyPresent = cctRows.any((r) => r['source_id'] == expSourceId);
            if (!alreadyPresent) {
              cctRows.add({
                'id': expSourceId,
                'source_type': 'export_return_expense',
                'source_id': expSourceId,
                'shipment_id': ret['shipment_id'],
                'shipment_no': retNo,
                'shipment_date': retDate,
                'customer_name': customerName,
                'supplier_name': null,
                'category': 'لوجستيك ونقل',
                'item_name': 'مصروفات رجوع شحنة إضافية - شحنة #$shipmentNo',
                'quantity': 1.0,
                'unit_price': expCost,
                'amount': expCost,
                'currency': 'EGP',
                'exchange_rate': 1.0,
                'total_in_currency': expCost,
                'notes': 'مصروفات رجوع شحنة تصدير رقم $shipmentNo ($retNo)',
                'cost_center_id': cc.id,
                'cost_center_name': cc.nameAr,
                'cost_center_name_en': cc.nameEn,
                'cost_center_type': cc.typeLabelAr,
                'is_export_return': true,
                'is_export_return_expense': true,
              });
            }
          }
        }
      } catch (e) {
        debugPrint('Direct export_shipment_returns query fallback: $e');
      }
    }

    // 3d. Direct fallback query from export_shipments + export_shipment_items
    try {
      var shipQuery = _client.from('export_shipments').select(
        'id, shipment_no, shipment_date, customer_name, customer_id, currency, currency_code, exchange_rate, export_shipment_items(*, packing_orders(order_number, product_name, fruit_type_id))',
      );
      if (fromDate != null && fromDate.isNotEmpty) {
        shipQuery = shipQuery.gte('shipment_date', fromDate);
      }
      if (toDate != null && toDate.isNotEmpty) {
        shipQuery = shipQuery.lte('shipment_date', toDate);
      }
      final shipments = await shipQuery;
      for (final shp in shipments) {
        final sId = shp['id'];
        final sNo = shp['shipment_no']?.toString() ?? 'شحنة #$sId';
        final sDate = shp['shipment_date']?.toString();
        final sCust = shp['customer_name']?.toString() ?? 'عميل تصدير';
        final sCur = shp['currency_code']?.toString() ?? shp['currency']?.toString() ?? 'USD';
        final sExRate = (shp['exchange_rate'] as num?)?.toDouble() ?? 1.0;
        final itemsList = shp['export_shipment_items'] as List? ?? [];

        for (final itm in itemsList) {
          final itmMap = Map<String, dynamic>.from(itm as Map);
          final itemId = itmMap['id'];
          final sig = 'shipment_${sId}_item_$itemId';
          final alreadyPresent = cctRows.any((r) => r['source_id'] == sig);
          if (alreadyPresent) continue;

          final pName = (itmMap['product_name'] ?? itmMap['invoice_product_name'] ?? 'محصول').toString();
          final poData = itmMap['packing_orders'] is Map ? itmMap['packing_orders'] as Map : null;
          final poNum = poData?['order_number']?.toString() ?? itmMap['packing_order_id']?.toString();
          final cc = CostCenterHelper.fromId(pName, lookupPool);

          if (isFilteringCc && !isSharedFilter) {
            final targetCanonCrop = CostCenter.canonicalCropName(targetCenter.nameAr);
            final targetSlug = targetCenter.cropCode ?? CostCenterHelper.resolveCropSlug(targetCanonCrop);
            final itmSlug = CostCenterHelper.resolveCropSlug(pName);
            final matches = cc.id == targetCenter.id ||
                cc.code == targetCenter.code ||
                targetSlug == itmSlug ||
                normalizeArabic(pName).contains(normalizeArabic(targetCenter.nameAr)) ||
                normalizeArabic(targetCenter.nameAr).contains(normalizeArabic(pName));
            if (!matches) continue;
          }

          final qty = (itmMap['quantity'] as num?)?.toDouble() ?? 0.0;
          final priceForeign = (itmMap['export_price_per_carton'] ?? itmMap['price'] as num?)?.toDouble() ?? 0.0;
          final totalForeign = (itmMap['amount'] as num?)?.toDouble() ?? (qty * priceForeign);
          final totalEgp = totalForeign * sExRate;
          final priceEgp = priceForeign * sExRate;

          cctRows.add({
            'id': 'exp_item_$itemId',
            'source_type': 'export_shipment',
            'source_id': sig,
            'shipment_id': sId,
            'shipment_no': sNo,
            'shipment_date': sDate,
            'customer_name': sCust,
            'supplier_name': sCust,
            'category': 'إيرادات المبيعات',
            'item_name': 'مبيعات تصدير - $pName',
            'quantity': qty > 0 ? qty : 1.0,
            'unit_price': priceEgp > 0 ? priceEgp : totalEgp,
            'amount': totalEgp,
            'currency': sCur,
            'exchange_rate': sExRate,
            'total_in_currency': totalForeign,
            'notes': 'شحنة: $sNo${poNum != null ? " - أمر تعبئة: #$poNum" : ""}',
            'cost_center_id': cc.id,
            'cost_center_name': cc.nameAr,
            'cost_center_name_en': cc.nameEn,
            'cost_center_type': cc.typeLabelAr,
            'target_product_name': pName,
            'packing_order_number': poNum,
            'packing_order_id': itmMap['packing_order_id'],
            'is_export_sale': true,
            'description': 'مبيعات تصدير - $pName',
          });
        }
      }
    } catch (e) {
      debugPrint('Direct export_shipments query fallback: $e');
    }

    // 3c. Direct fallback query for raw_materials initial balances (رصيد أول المدة)
    final isTargetPacking = targetCenter.id == CostCenterHelper.packingStation.id ||
        targetCenter.code == 'CC-PACKING' ||
        targetCenter.code == 'CC-CAT-3' ||
        targetCenter.nameAr.contains('تعبئة');
    final hasPackingCenter = centers.any((c) =>
        c.id == CostCenterHelper.packingStation.id ||
        c.code == 'CC-PACKING' ||
        c.code == 'CC-CAT-3' ||
        c.nameAr.contains('تعبئة'));
    if (hasPackingCenter && (!isFilteringCc || isTargetPacking)) {
      try {
        final rmData = await _client
            .from('raw_materials')
            .select('id, code, name, initial_quantity, initial_avg_price, currency, exchange_rate, created_at')
            .gt('initial_quantity', 0);
        for (final rm in rmData) {
          final rmMap = Map<String, dynamic>.from(rm as Map);
          final rmId = rmMap['id']?.toString() ?? '';
          final rmName = (rmMap['name']?.toString() ?? rmMap['code']?.toString() ?? 'مادة تعبئة').trim();
          final qty = (rmMap['initial_quantity'] as num?)?.toDouble() ?? 0.0;
          final unitPrice = (rmMap['initial_avg_price'] as num?)?.toDouble() ?? 0.0;
          final cur = rmMap['currency']?.toString() ?? 'EGP';
          final exRate = (rmMap['exchange_rate'] as num?)?.toDouble() ?? 1.0;
          final totalForeign = qty * unitPrice;
          final totalEgp = totalForeign * (exRate > 0 ? exRate : 1.0);
          final dateStr = (rmMap['created_at']?.toString() ?? '').split('T').first;
          final sig = 'ob_rm_$rmId';

          final alreadyPresent = cctRows.any((r) =>
              r['source_id'] == sig ||
              r['id'] == 'ob_rm_$rmId' ||
              (r['is_opening_balance'] == true &&
               normalizeArabic(r['item_name']?.toString() ?? '') == normalizeArabic(rmName)));

          if (!alreadyPresent) {
            cctRows.add({
              'id': 'ob_rm_$rmId',
              'source_type': 'opening_balance',
              'source_id': sig,
              'shipment_id': null,
              'shipment_no': 'رصيد أول المدة',
              'shipment_date': dateStr.isNotEmpty ? dateStr : DateTime.now().toIso8601String().substring(0, 10),
              'customer_name': 'رصيد افتتاحي',
              'supplier_name': 'رصيد أول المدة',
              'category': 'مواد التعبئة',
              'item_name': rmName,
              'quantity': qty,
              'unit_price': unitPrice > 0 ? unitPrice : 0.0,
              'amount': totalEgp,
              'currency': cur,
              'exchange_rate': exRate,
              'total_in_currency': totalForeign,
              'notes': 'رصيد أول المدة - $rmName',
              'cost_center_id': 'packing_station',
              'cost_center_name': 'محطة التعبئة والتجهيز',
              'cost_center_name_en': 'Packing & Processing Station',
              'cost_center_type': 'تشغيلي',
              'is_lot_receipt': false,
              'is_opening_balance': true,
            });
          }
        }
      } catch (e) {
        debugPrint('Direct raw_materials initial balances query fallback: $e');
      }
    }

    // 3c.1 Direct fallback query for shipping_companies initial balances (رصيد أول المدة لشركات الشحن)
    final isTargetShipping = targetCenter.id == CostCenterHelper.freightLogistics.id ||
        targetCenter.code == 'CC-LOGISTICS' ||
        targetCenter.code == 'CC-CAT-4' ||
        targetCenter.nameAr.contains('شحن');
    final hasShippingCenter = centers.any((c) =>
        c.id == CostCenterHelper.freightLogistics.id ||
        c.code == 'CC-LOGISTICS' ||
        c.code == 'CC-CAT-4' ||
        c.nameAr.contains('شحن'));
    if (hasShippingCenter && (!isFilteringCc || isTargetShipping)) {
      try {
        final scData = await _client
            .from('shipping_companies')
            .select('id, code, name, initial_balance, currency, created_at')
            .gt('initial_balance', 0);
        for (final sc in scData) {
          final scMap = Map<String, dynamic>.from(sc as Map);
          final scId = scMap['id']?.toString() ?? '';
          final scName = (scMap['name']?.toString() ?? 'شركة شحن').trim();
          final bal = (scMap['initial_balance'] as num?)?.toDouble() ?? 0.0;
          final cur = scMap['currency']?.toString() ?? 'EGP';
          final dateStr = (scMap['created_at']?.toString() ?? '').split('T').first;
          final sig = 'ob_sc_$scId';

          final alreadyPresent = cctRows.any((r) =>
              r['source_id'] == sig ||
              r['id'] == 'ob_sc_$scId' ||
              (r['is_opening_balance'] == true &&
               normalizeArabic(r['item_name']?.toString() ?? '') == normalizeArabic('رصيد أول المدة - $scName')));

          if (!alreadyPresent) {
            cctRows.add({
              'id': 'ob_sc_$scId',
              'source_type': 'opening_balance',
              'source_id': sig,
              'shipment_id': null,
              'shipment_no': 'رصيد أول المدة',
              'shipment_date': dateStr.isNotEmpty ? dateStr : DateTime.now().toIso8601String().substring(0, 10),
              'customer_name': 'رصيد افتتاحي',
              'supplier_name': scName,
              'category': 'تكلفة شركات الشحن',
              'item_name': 'رصيد أول المدة - $scName',
              'quantity': 1.0,
              'unit_price': bal,
              'amount': bal,
              'currency': cur,
              'exchange_rate': 1.0,
              'total_in_currency': bal,
              'notes': 'رصيد أول المدة لشركة الشحن $scName',
              'cost_center_id': 'freight_logistics',
              'cost_center_name': 'تكلفة شركات الشحن',
              'cost_center_name_en': 'Freight & Shipping',
              'cost_center_type': 'تشغيلي',
              'is_lot_receipt': false,
              'is_opening_balance': true,
            });
          }
        }
      } catch (e) {
        debugPrint('Direct shipping_companies initial balances query fallback: $e');
      }
    }

    // 3c.2 Direct fallback query for clearing_agents initial balances (رصيد أول المدة للمخلصين)
    final isTargetClearance = targetCenter.id == CostCenterHelper.customsClearance.id ||
        targetCenter.code == 'CC-CUSTOMS' ||
        targetCenter.code == 'CC-CAT-5' ||
        targetCenter.nameAr.contains('تخليص') ||
        targetCenter.nameAr.contains('مخلص');
    final hasClearanceCenter = centers.any((c) =>
        c.id == CostCenterHelper.customsClearance.id ||
        c.code == 'CC-CUSTOMS' ||
        c.code == 'CC-CAT-5' ||
        c.nameAr.contains('تخليص') ||
        c.nameAr.contains('مخلص'));
    if (hasClearanceCenter && (!isFilteringCc || isTargetClearance)) {
      try {
        final caData = await _client
            .from('clearing_agents')
            .select('id, code, name, initial_balance, currency, created_at')
            .gt('initial_balance', 0);
        for (final ca in caData) {
          final caMap = Map<String, dynamic>.from(ca as Map);
          final caId = caMap['id']?.toString() ?? '';
          final caName = (caMap['name']?.toString() ?? 'مخلص جمركي').trim();
          final bal = (caMap['initial_balance'] as num?)?.toDouble() ?? 0.0;
          final cur = caMap['currency']?.toString() ?? 'EGP';
          final dateStr = (caMap['created_at']?.toString() ?? '').split('T').first;
          final sig = 'ob_ca_$caId';

          final alreadyPresent = cctRows.any((r) =>
              r['source_id'] == sig ||
              r['id'] == 'ob_ca_$caId' ||
              (r['is_opening_balance'] == true &&
               normalizeArabic(r['item_name']?.toString() ?? '') == normalizeArabic('رصيد أول المدة - $caName')));

          if (!alreadyPresent) {
            cctRows.add({
              'id': 'ob_ca_$caId',
              'source_type': 'opening_balance',
              'source_id': sig,
              'shipment_id': null,
              'shipment_no': 'رصيد أول المدة',
              'shipment_date': dateStr.isNotEmpty ? dateStr : DateTime.now().toIso8601String().substring(0, 10),
              'customer_name': 'رصيد افتتاحي',
              'supplier_name': caName,
              'category': 'تكلفة المخلصين',
              'item_name': 'رصيد أول المدة - $caName',
              'quantity': 1.0,
              'unit_price': bal,
              'amount': bal,
              'currency': cur,
              'exchange_rate': 1.0,
              'total_in_currency': bal,
              'notes': 'رصيد أول المدة للمخلص الجمركي $caName',
              'cost_center_id': 'customs_clearance',
              'cost_center_name': 'تكلفة المخلصين',
              'cost_center_name_en': 'Customs Clearance',
              'cost_center_type': 'تشغيلي',
              'is_lot_receipt': false,
              'is_opening_balance': true,
            });
          }
        }
      } catch (e) {
        debugPrint('Direct clearing_agents initial balances query fallback: $e');
      }
    }

    // 3c.3 Direct fallback query for transport_suppliers initial balances (رصيد أول المدة للنقل واللوجستيات)
    final isTargetTransport = targetCenter.id == 'CC-CAT-6' ||
        targetCenter.code == 'CC-CAT-6' ||
        targetCenter.nameAr.contains('لوجستيك') ||
        targetCenter.nameAr.contains('نقل');
    final hasTransportCenter = centers.any((c) =>
        c.id == 'CC-CAT-6' ||
        c.code == 'CC-CAT-6' ||
        c.nameAr.contains('لوجستيك') ||
        c.nameAr.contains('نقل'));
    if (hasTransportCenter && (!isFilteringCc || isTargetTransport)) {
      try {
        final tsData = await _client
            .from('transport_suppliers')
            .select('id, code, name, initial_balance, currency, created_at')
            .gt('initial_balance', 0);
        for (final ts in tsData) {
          final tsMap = Map<String, dynamic>.from(ts as Map);
          final tsId = tsMap['id']?.toString() ?? '';
          final tsName = (tsMap['name']?.toString() ?? 'مورد نقل ولوجستيك').trim();
          final bal = (tsMap['initial_balance'] as num?)?.toDouble() ?? 0.0;
          final cur = tsMap['currency']?.toString() ?? 'EGP';
          final dateStr = (tsMap['created_at']?.toString() ?? '').split('T').first;
          final sig = 'ob_ts_$tsId';

          final alreadyPresent = cctRows.any((r) =>
              r['source_id'] == sig ||
              r['id'] == 'ob_ts_$tsId' ||
              (r['is_opening_balance'] == true &&
               normalizeArabic(r['item_name']?.toString() ?? '') == normalizeArabic('رصيد أول المدة - $tsName')));

          if (!alreadyPresent) {
            cctRows.add({
              'id': 'ob_ts_$tsId',
              'source_type': 'opening_balance',
              'source_id': sig,
              'shipment_id': null,
              'shipment_no': 'رصيد أول المدة',
              'shipment_date': dateStr.isNotEmpty ? dateStr : DateTime.now().toIso8601String().substring(0, 10),
              'customer_name': 'رصيد افتتاحي',
              'supplier_name': tsName,
              'category': 'لوجستيك ونقل',
              'item_name': 'رصيد أول المدة - $tsName',
              'quantity': 1.0,
              'unit_price': bal,
              'amount': bal,
              'currency': cur,
              'exchange_rate': 1.0,
              'total_in_currency': bal,
              'notes': 'رصيد أول المدة لمورد النقل $tsName',
              'cost_center_id': 'CC-CAT-6',
              'cost_center_name': 'لوجستيك ونقل',
              'cost_center_name_en': 'Logistics & Transport',
              'cost_center_type': 'تشغيلي',
              'is_lot_receipt': false,
              'is_opening_balance': true,
            });
          }
        }
      } catch (e) {
        debugPrint('Direct transport_suppliers initial balances query fallback: $e');
      }
    }

    // 3d. Direct fallback for Cost Centers initial opening balances (رصيد أول المدة لمراكز التكلفة)
    try {
      final allRelevantCenters = activeCenters ?? centers;
      for (final c in allRelevantCenters) {
        if (c.openingBalance > 0) {
          final cId = c.id;
          final cCode = c.code ?? cId;
          final cDbId = c.dbId?.toString() ?? cCode;
          final sig = 'cc_ob_$cDbId';

          // Strictly check if any opening balance or season rollover already exists for this cost center
          final alreadyPresent = cctRows.any((r) =>
              r['source_id'] == sig ||
              r['id'] == 'ob_cc_$cDbId' ||
              ((r['is_opening_balance'] == true || r['source_type'] == 'opening_balance' || r['source_type'] == 'season_rollover') &&
               (r['cost_center_id'] == cId ||
                r['cost_center_id'] == cCode ||
                r['cost_center_id'] == cDbId ||
                (c.code != null && r['cost_center_id'] == c.code) ||
                normalizeArabic(r['cost_center_name']?.toString() ?? '') == normalizeArabic(c.nameAr))));

          if (!alreadyPresent) {
            final dateStr = DateTime.now().toIso8601String().split('T').first;
            final centerCategory = resolveCostCenterCategory(c);

            cctRows.add({
              'id': 'ob_cc_$cDbId',
              'source_type': 'opening_balance',
              'source_id': sig,
              'shipment_id': null,
              'shipment_no': 'رصيد أول المدة',
              'shipment_date': dateStr,
              'customer_name': 'رصيد افتتاحي',
              'supplier_name': 'رصيد أول المدة',
              'category': centerCategory,
              'item_name': 'رصيد افتتاحي - ${c.nameAr}',
              'quantity': 1.0,
              'unit_price': c.openingBalance,
              'amount': c.openingBalance,
              'currency': 'EGP',
              'exchange_rate': 1.0,
              'total_in_currency': c.openingBalance,
              'notes': 'رصيد افتتاحي مسجل لمركز التكلفة',
              'cost_center_id': c.id,
              'cost_center_name': c.nameAr,
              'cost_center_name_en': c.nameEn,
              'cost_center_type': c.typeLabelAr,
              'target_product_name': c.nameAr,
              'is_lot_receipt': false,
              'is_opening_balance': true,
              'is_rollover': false,
              'season': c.season,
              'season_status': c.seasonStatus,
              'season_number': c.seasonNumber,
              'date': DateTime.now().toIso8601String().split('T').first,
              'is_sorting_sale': false,
              'is_lot_return': false,
              'is_purchase': false,
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Cost centers initial balances fallback query error: $e');
    }

    // 3a. Deduplicate within cctRows:
    // If a detailed lot_receipt exists, eliminate redundant preliminary purchase order / invoice entries (crop_purchase) under the same reference or item/amount/date
    final lotReceiptsInCct = cctRows.where((r) => r['is_lot_receipt'] == true).toList();
    final cctDeduplicated = cctRows.where((r) {
      if (r['is_purchase'] == true) {
        final rBaseItem = extractBaseItemName(r['item_name']?.toString() ?? '');
        final rDate = (r['shipment_date']?.toString() ?? '').split('T').first;
        final rAmt = ((r['amount'] as num?)?.toDouble() ?? 0.0).abs();
        final rQty = ((r['quantity'] as num?)?.toDouble() ?? 0.0).abs();

        final hasMatchingLot = lotReceiptsInCct.any((lot) {
          final lotBaseItem = extractBaseItemName(lot['item_name']?.toString() ?? '');
          final lotDate = (lot['shipment_date']?.toString() ?? '').split('T').first;
          final lotAmt = ((lot['amount'] as num?)?.toDouble() ?? 0.0).abs();
          final lotQty = ((lot['quantity'] as num?)?.toDouble() ?? 0.0).abs();

          final sameRef = (lot['source_id'] != null && r['source_id'] != null && lot['source_id'] == r['source_id']);
          final sameItem = rBaseItem.isEmpty ||
              lotBaseItem.isEmpty ||
              rBaseItem == lotBaseItem ||
              lotBaseItem.contains(rBaseItem) ||
              rBaseItem.contains(lotBaseItem);
          final sameAmt = (rAmt - lotAmt).abs() < 1.0;
          final sameQty = (rQty > 0 && lotQty > 0) && (rQty - lotQty).abs() < 1.0;
          final sameDate = rDate.isEmpty || lotDate.isEmpty || rDate == lotDate;

          return sameRef || (sameItem && (sameAmt || sameQty) && sameDate);
        });

        if (hasMatchingLot) {
          return false; // Preliminary purchase order entry is already fully fulfilled and represented by detailed lot receipt
        }
      }
      return true;
    }).toList();

    // 3b. Deduplicate between vw_cost_details_live and cost_center_transactions:
    final Set<String> existingSignatures = {};
    for (final c in cctDeduplicated) {
      final sType = c['source_type']?.toString();
      final sId = c['source_id']?.toString();
      if (sType != null && sId != null) {
        existingSignatures.add('$sType:$sId');
      }
      final date = (c['shipment_date']?.toString() ?? '').split('T').first;
      final rawItem = c['item_name']?.toString() ?? '';
      final baseItem = extractBaseItemName(rawItem);
      final amtAbs = ((c['amount'] as num?)?.toDouble() ?? 0.0).abs().toStringAsFixed(0);

      if (date.isNotEmpty) {
        existingSignatures.add('$date:$baseItem:$amtAbs');
      }
      if (baseItem.isNotEmpty) {
        existingSignatures.add('$baseItem:$amtAbs');
      }
    }

    // Also register global signatures from ALL cost_center_transactions
    // so transactions belonging to other cost centers or closed seasons never bleed into other cards via vw_cost_details_live!
    for (final c in allCctRecords) {
      final sType = c['source_type']?.toString();
      final sId = c['source_id']?.toString();
      if (sType != null && sId != null) {
        existingSignatures.add('$sType:$sId');
      }
      final date = (c['transaction_date']?.toString() ?? c['created_at']?.toString() ?? '').split('T').first;
      final rawItem = c['item_name']?.toString() ?? '';
      final baseItem = extractBaseItemName(rawItem);
      final amt = ((c['amount'] ?? c['amount_egp'] ?? c['total_cost_egp']) as num?)?.toDouble() ?? 0.0;
      final amtAbs = amt.abs().toStringAsFixed(0);

      if (date.isNotEmpty && baseItem.isNotEmpty) {
        existingSignatures.add('$date:$baseItem:$amtAbs');
      }
      if (baseItem.isNotEmpty) {
        existingSignatures.add('$baseItem:$amtAbs');
      }
    }

    for (final op in operationalRows) {
      if (op['is_packing_order_cost_item'] == true) {
        final date = (op['shipment_date']?.toString() ?? '').split('T').first;
        final rawItem = op['item_name']?.toString() ?? '';
        final baseItem = extractBaseItemName(rawItem);
        final amtAbs = ((op['amount'] as num?)?.toDouble() ?? 0.0).abs().toStringAsFixed(0);
        if (date.isNotEmpty && baseItem.isNotEmpty) {
          existingSignatures.add('$date:$baseItem:$amtAbs');
        }
        if (baseItem.isNotEmpty) {
          existingSignatures.add('$baseItem:$amtAbs');
        }
      }
    }

    final filteredEnriched = enriched.where((row) {
      final cat = row['category']?.toString() ?? '';
      final isCropCat = cat == 'crop' ||
          cat == 'fruit' ||
          cat == 'manual_crop' ||
          cat == 'تكلفة المحاصيل' ||
          row['is_lot_receipt'] == true ||
          row['is_lot_return'] == true;
      final isPackingCat = cat == 'مواد التعبئة' || cat == 'packing_material';

      if ((isCropCat || isPackingCat) && cctDeduplicated.isNotEmpty) {
        final date = (row['shipment_date']?.toString() ?? '').split('T').first;
        final rawItem = row['item_name']?.toString() ?? '';
        final baseItem = extractBaseItemName(rawItem);
        final amtAbs = ((row['amount'] as num?)?.toDouble() ?? 0.0).abs().toStringAsFixed(0);

        final sigWithDate = '$date:$baseItem:$amtAbs';
        final sigWithoutDate = '$baseItem:$amtAbs';

        if (existingSignatures.contains(sigWithDate) || existingSignatures.contains(sigWithoutDate)) {
          return false; // Prefer rich cctRow with supplier and cost center details
        }
      }
      return true;
    }).toList();

    // Deduplicate operationalRows against cost_center_transactions:
    // If a packaging material or waste entry is already persisted in cost_center_transactions, skip the operational copy
    final filteredOperationalRows = operationalRows.where((op) {
      final sType = op['source_type']?.toString();
      final sId = op['source_id']?.toString();
      if (sType != null && sId != null && existingSignatures.contains('$sType:$sId')) {
        return false;
      }
      return true;
    }).toList();

    // Combine enriched live view rows + operational packing rows + cost center transactions
    final allRows = <Map<String, dynamic>>[...filteredEnriched, ...filteredOperationalRows, ...cctDeduplicated];

    // Ensure all rows have non-zero quantity and unit price whenever total is non-zero
    for (final row in allRows) {
      final totalEgp = ((row['amount'] ?? row['total_cost_egp']) as num?)?.toDouble() ?? 0.0;
      final totalInCur = (row['total_in_currency'] as num?)?.toDouble() ?? totalEgp;
      double q = (row['quantity'] as num?)?.toDouble() ?? 0.0;
      double up = (row['unit_price'] as num?)?.toDouble() ?? 0.0;

      if (totalInCur != 0) {
        if (up <= 0 && q.abs() > 0) {
          up = (totalInCur / q).abs();
        } else if (q == 0 && up > 0) {
          q = totalInCur / up;
        } else if (q == 0 && up <= 0) {
          q = totalInCur < 0 ? -1.0 : 1.0;
          up = totalInCur.abs();
        }
        row['quantity'] = q;
        row['unit_price'] = up;
      }
    }

    // 3c. Tag and identify redundant seasonal rollovers:
    // Intra-card rollovers (e.g. 'rollover_X_to_X' from Period 1 to Period 2) exist in the SAME card
    // alongside the original Period 1 operational transactions. Marking them redundant prevents double counting.
    // Inter-card rollovers (from one agricultural year to the next card) are preserved as carried-forward opening balances.
    for (final row in allRows) {
      final sId = row['source_id']?.toString() ?? '';
      final isIntraCardRollover = RegExp(r'^rollover_(\d+)_to_\1').hasMatch(sId);
      if (isIntraCardRollover) {
        row['is_redundant_rollover'] = true;
      } else {
        row['is_redundant_rollover'] = false;
      }
    }

    // Clean UI sorting flow: Opening/Rollover -> Purchase/Receipt -> Lot Receipt -> Operations -> Returns
    allRows.sort((a, b) {
      final dateA = a['shipment_date']?.toString() ?? '';
      final dateB = b['shipment_date']?.toString() ?? '';
      final dateComp = dateB.compareTo(dateA); // Newest date first
      if (dateComp != 0) return dateComp;

      int orderPriority(Map<String, dynamic> r) {
        if (r['is_opening_balance'] == true || r['is_rollover'] == true || r['source_type'] == 'season_rollover') return 0;
        if (r['is_purchase'] == true) return 1;
        if (r['is_lot_receipt'] == true) return 2;
        if (r['is_packing_operational'] == true) return 3;
        if (r['is_export_return'] == true) return 4;
        if (r['is_lot_return'] == true || ((r['amount'] as num?)?.toDouble() ?? 0) < 0) return 6;
        if (r['is_sorting_sale'] == true) return 7;
        return 5;
      }

      return orderPriority(a).compareTo(orderPriority(b));
    });

    // Filter by category if specified
    if (category != null && category.isNotEmpty) {
      final normCat = category.trim().toLowerCase();
      allRows.retainWhere((r) {
        final rCat = (r['category']?.toString() ?? '').trim().toLowerCase();
        if (rCat == normCat) return true;
        if (normCat == 'تكلفة شركات الشحن' || normCat == 'shipping' || normCat == 'freight' || normCat == 'shipping_company') {
          return rCat == 'تكلفة شركات الشحن' || rCat == 'shipping' || rCat == 'freight' || rCat == 'shipping_company';
        }
        if (normCat == 'تكلفة المخلصين' || normCat == 'clearance' || normCat == 'clearing' || normCat == 'clearing_agent') {
          return rCat == 'تكلفة المخلصين' || rCat == 'clearance' || rCat == 'clearing' || rCat == 'clearing_agent';
        }
        if (normCat == 'لوجستيك ونقل' || normCat == 'logistics' || normCat == 'transport') {
          return rCat == 'لوجستيك ونقل' || rCat == 'logistics' || rCat == 'transport';
        }
        if (normCat == 'تعبئة وتغليف' || normCat == 'packing' || normCat == 'packaging') {
          return rCat == 'تعبئة وتغليف' || rCat == 'packing' || rCat == 'packaging' || rCat == 'manual_packing';
        }
        if (normCat == 'مواد التعبئة' || normCat == 'packing_material') {
          return rCat == 'مواد التعبئة' || rCat == 'packing_material';
        }
        if (normCat == 'تكلفة المحاصيل' || normCat == 'crop' || normCat == 'fruit' || normCat == 'manual_crop') {
          return rCat == 'تكلفة المحاصيل' || rCat == 'crop' || rCat == 'fruit' || rCat == 'manual_crop';
        }
        return false;
      });
    }

    // Filter by Cost Center if specified
    if (isFilteringCc) {
      final filteredList = <Map<String, dynamic>>[];
      final normTarget = normalizeArabic(targetCenter.nameAr);
      final targetId = targetCenter.id;
      final targetCode = targetCenter.code;
      final targetProdId = targetCenter.productId?.toString();
      final targetDbId = targetCenter.dbId?.toString();
      final targetSeason = targetCenter.season ?? extractSeason(targetCode) ?? extractSeason(targetCenter.nameAr);

      for (final row in allRows) {
        final rowCcId = row['cost_center_id']?.toString();
        final rowCc = rowCcId != null ? CostCenterHelper.fromId(rowCcId, lookupPool) : null;

        // STRICT CLOSED CENTER ISOLATION:
        // If targetCenter is active, never allow transactions from closed/historical cost centers to bleed in
        if (rowCc != null &&
            rowCc.id != targetCenter.id &&
            rowCc.code != targetCenter.code &&
            (targetCenter.dbId == null || rowCc.dbId != targetCenter.dbId)) {
          final sId = row['source_id']?.toString() ?? '';
          final isRolloverIntoTarget = sId.contains('_to_${targetCenter.dbId}') ||
              sId.contains('_to_${targetCenter.code}') ||
              sId.contains('_to_${targetCenter.id}');
          if (!isRolloverIntoTarget && (rowCc.isClosed || rowCc.isPermanentlyClosed)) {
            continue;
          }
        }

        // STRICT YEAR/SEASON ISOLATION:
        // Exclude transactions explicitly tagged with a different agricultural year/season
        if (targetSeason != null && targetSeason.isNotEmpty) {
          final rowCcName = row['cost_center_name']?.toString() ?? '';
          final rowItem = row['item_name']?.toString() ?? '';
          final rowSeason = extractSeason(rowCcId) ??
              extractSeason(rowCcName) ??
              extractSeason(row['target_product_name']?.toString()) ??
              extractSeason(row['season']?.toString()) ??
              extractSeason(rowItem) ??
              rowCc?.season;
          if (rowSeason != null && rowSeason.isNotEmpty && rowSeason != targetSeason) {
            continue;
          }
        }
        if (row['is_equal_distribution'] == true) {
          if (isSharedFilter) {
            filteredList.add(row);
            continue;
          }

          final List<String> orderProds =
              (row['order_products'] as List<dynamic>? ?? [])
                  .map((e) => e.toString())
                  .toList();
          final prodCount = orderProds.isNotEmpty ? orderProds.length : 1;

          // Check if this cost center corresponds to any of the products in the packing order
          final isIncluded = orderProds.any((p) {
            final normP = normalizeArabic(p);
            final canonP = CostCenter.canonicalCropName(p);
            final slugP = CostCenterHelper.resolveCropSlug(canonP);
            final targetCanonCrop = CostCenter.canonicalCropName(targetCenter.nameAr);
            final targetCropSlug = targetCenter.cropCode ?? CostCenterHelper.resolveCropSlug(targetCanonCrop);

            return normP == normTarget ||
                normP.contains(normTarget) ||
                normTarget.contains(normP) ||
                (targetCropSlug != 'CROP' && targetCropSlug == slugP) ||
                (canonP.isNotEmpty && canonP == targetCanonCrop) ||
                (normLabel.isNotEmpty &&
                    (normP == normLabel ||
                        normP.contains(normLabel) ||
                        normLabel.contains(normP)));
          });

          if (isIncluded) {
            final filteredRow = Map<String, dynamic>.from(row);
            final shareAmt =
                ((row['amount'] as num?)?.toDouble() ?? 0.0) / prodCount;
            filteredRow['cost_center_id'] = targetCenter.id;
            filteredRow['cost_center_name'] = targetCenter.nameAr;
            filteredRow['cost_center_type'] = targetCenter.typeLabelAr;
            filteredRow['amount'] = shareAmt;
            filteredRow['notes'] =
                '${row['item_name']} (حصة بالتساوي من إجمالي ${((row['amount'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)} ج.م بين $prodCount منتجات)';
            filteredList.add(filteredRow);
          }
        } else {
          if (isSharedFilter) continue;

          // If filtering for a specific product cost center, do not include generic pre-production
          // lot receipts IF the finished product's raw fruit cost is already captured by its
          // operational packing order line (تكلفة الخام الإجمالي).
          final isLotReceipt = row['is_lot_receipt'] == true;
          if (isLotReceipt) {
            final hasOperationalForThisProduct = operationalRows.any((op) {
              final opCc = op['cost_center_id']?.toString();
              final opTarget = normalizeArabic(op['target_product_name']?.toString() ?? '');
              final rowCc = row['cost_center_id']?.toString();
              final rowItem = normalizeArabic(row['item_name']?.toString() ?? '');
              return (opCc != null && (opCc == rowCc || opCc == targetId)) ||
                     (opTarget.isNotEmpty && (opTarget == rowItem || opTarget == normTarget));
            });
            if (hasOperationalForThisProduct) {
              continue;
            }
          }

          final id = row['cost_center_id']?.toString();
          final name = row['cost_center_name']?.toString() ?? '';
          final targetProd = row['target_product_name']?.toString() ?? '';
          final prodId = row['product_id']?.toString();
          final normName = normalizeArabic(name);
          final normTargetProd = normalizeArabic(targetProd);
          final rowCat = row['category']?.toString() ?? '';

          final isTargetPacking = targetId == CostCenterHelper.packingStation.id ||
              targetCode == 'CC-PACKING' ||
              targetCode == 'CC-CAT-3' ||
              targetCenter.nameAr.contains('تعبئة');
          final isRowPacking = id == CostCenterHelper.packingStation.id ||
              id == 'CC-PACKING' ||
              id == 'CC-CAT-3' ||
              name.contains('تعبئة');

          if (isTargetPacking) {
            if (isRowPacking ||
                ((rowCat == 'مواد التعبئة' || rowCat == 'تعبئة وتغليف') &&
                    (id == null || id.isEmpty || id == 'packing_station' || id == 'CC-PACKING' || id == 'CC-CAT-3'))) {
              filteredList.add(row);
            }
            continue;
          }

          final isTargetShipping = targetId == CostCenterHelper.freightLogistics.id ||
              targetCode == 'CC-LOGISTICS' ||
              targetCode == 'CC-CAT-4' ||
              targetCenter.nameAr.contains('شحن');
          final isRowShipping = id == CostCenterHelper.freightLogistics.id ||
              id == 'CC-LOGISTICS' ||
              id == 'CC-CAT-4' ||
              name.contains('شحن');

          if (isTargetShipping) {
            if (isRowShipping || rowCat == 'تكلفة شركات الشحن' || rowCat == 'freight' || rowCat == 'shipping') {
              filteredList.add(row);
            }
            continue;
          }

          final isTargetClearance = targetId == CostCenterHelper.customsClearance.id ||
              targetCode == 'CC-CUSTOMS' ||
              targetCode == 'CC-CAT-5' ||
              targetCenter.nameAr.contains('تخليص') ||
              targetCenter.nameAr.contains('مخلص');
          final isRowClearance = id == CostCenterHelper.customsClearance.id ||
              id == 'CC-CUSTOMS' ||
              id == 'CC-CAT-5' ||
              name.contains('تخليص') ||
              name.contains('مخلص');

          if (isTargetClearance) {
            if (isRowClearance || rowCat == 'تكلفة المخلصين' || rowCat == 'clearance' || rowCat == 'clearing') {
              filteredList.add(row);
            }
            continue;
          }

          final isTargetTransport = targetId == 'CC-CAT-6' ||
              targetCode == 'CC-CAT-6' ||
              targetCenter.nameAr.contains('لوجستيك') ||
              targetCenter.nameAr.contains('نقل');
          final isRowTransport = id == 'CC-CAT-6' ||
              name.contains('لوجستيك') ||
              name.contains('نقل');

          if (isTargetTransport) {
            if (isRowTransport || rowCat == 'لوجستيك ونقل' || rowCat == 'transport' || rowCat == 'logistics') {
              filteredList.add(row);
            }
            continue;
          }

          // If filtering for a variety line (e.g. فرولة - وزن), strictly exclude operational lines and general admin rows
          final belongsDirectlyToTarget = (id != null &&
              (id == targetId ||
                  id == cleanCc ||
                  (targetCode != null && id == targetCode) ||
                  (targetDbId != null && id == targetDbId)));

          if (!belongsDirectlyToTarget && (isRowPacking || isRowShipping || isRowClearance || isRowTransport || id == CostCenterHelper.generalAdmin.id || id == 'CC-ADMIN')) {
            continue;
          }

          final matchesDirectId = id != null &&
              (id == targetId ||
                  id == cleanCc ||
                  (targetCode != null && id == targetCode) ||
                  (targetDbId != null && id == targetDbId));
          final matchesProdId = targetProdId != null &&
              (id == targetProdId || prodId == targetProdId);
          final matchesExactName = normName == normTarget || normTargetProd == normTarget;
          final matchesLabel = normLabel.isNotEmpty &&
              (normName == normLabel || normTargetProd == normLabel);

          final bool matches;
          if (targetSeason != null && targetSeason.isNotEmpty) {
            matches = matchesDirectId || matchesProdId || matchesExactName;
          } else {
            final rowCanonCrop = CostCenter.canonicalCropName(targetProd.isNotEmpty ? targetProd : name);
            final rowCropSlug = CostCenterHelper.resolveCropSlug(rowCanonCrop.isNotEmpty ? rowCanonCrop : (targetProd.isNotEmpty ? targetProd : name));
            final targetCanonCrop = CostCenter.canonicalCropName(targetCenter.nameAr);
            final targetCropSlug = targetCenter.cropCode ?? CostCenterHelper.resolveCropSlug(targetCanonCrop);

            final matchesCropSlug = (targetCropSlug != 'CROP' && (targetCropSlug == rowCropSlug || id == 'CC-$targetCropSlug')) ||
                (targetCenter.cropName != null && rowCanonCrop.isNotEmpty && targetCenter.cropName == rowCanonCrop);

            matches = matchesDirectId ||
                matchesProdId ||
                matchesExactName ||
                matchesLabel ||
                matchesCropSlug;
          }

          if (matches) {
            filteredList.add(row);
          }
        }
      }
      return filteredList;
    }

    return allRows;
  }

  Future<List<Map<String, dynamic>>> getSummary({
    String? fromDate,
    String? toDate,
    String? customer,
    String? costCenter,
    List<Map<String, dynamic>>? preloadedDetails,
    List<CostCenter>? activeCenters,
    List<CostCenter>? allCenters,
  }) async {
    final details = preloadedDetails ??
        await getDetails(
          fromDate: fromDate,
          toDate: toDate,
          customer: customer,
          costCenter: costCenter,
          activeCenters: activeCenters,
          allCenters: allCenters,
        );
    final Map<String, Map<String, dynamic>> grouped = {};
    for (final row in details) {
      if (row['is_redundant_rollover'] == true) {
        continue;
      }
      // Exclude carried forward opening balances from direct operational expenses
      final isRollover = row['is_rollover'] == true ||
          row['source_type'] == 'season_rollover' ||
          row['transaction_type'] == 'carried_forward';
      final isOpening = row['is_opening_balance'] == true ||
          row['source_type'] == 'opening_balance' ||
          isRollover;
      if (isOpening) {
        continue;
      }
      final item = (row['item_name'] as String?)?.trim();
      final name = (item != null && item.isNotEmpty)
          ? item
          : ((row['category'] as String?) ?? 'unknown');
      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
      if (!grouped.containsKey(name)) {
        grouped[name] = {
          'item_name': name,
          'total_amount': 0.0,
          'transaction_count': 0,
        };
      }
      grouped[name]!['total_amount'] =
          (grouped[name]!['total_amount'] as double) + amount;
      grouped[name]!['transaction_count'] =
          (grouped[name]!['transaction_count'] as int) + 1;
    }
    final result = grouped.values.toList();
    result.sort((a, b) =>
        (b['total_amount'] as double).compareTo(a['total_amount'] as double));
    // Filter out generic/unknown names
    final generic = {'أخرى', 'other', 'OTHER', 'unknown', ''};
    result.removeWhere((e) {
      final name = (e['item_name'] as String?)?.trim() ?? '';
      return generic.contains(name);
    });
    return result;
  }

  /// Calculates aggregated financial metrics per dynamic Cost Center
  Future<List<Map<String, dynamic>>> getCostCenterBreakdown({
    String? fromDate,
    String? toDate,
    String? customer,
    List<Map<String, dynamic>>? preloadedDetails,
    List<CostCenter>? allCenters,
    List<CostCenter>? activeCenters,
  }) async {
    // Fetch ALL cost centers (including closed) so we can show lock badges
    final allCentersList = allCenters ?? await getAllCostCenters();
    final activeCentersList = activeCenters ?? allCentersList.where((c) => !c.isClosed).toList();

    final details = preloadedDetails ??
        await getDetails(
          fromDate: fromDate,
          toDate: toDate,
          customer: customer,
          activeCenters: activeCentersList,
          allCenters: allCentersList,
        );

    final double grandTotal = details
        .where((r) {
          if (r['is_redundant_rollover'] == true) {
            return false;
          }
          final isRollover = r['is_rollover'] == true ||
              r['source_type'] == 'season_rollover' ||
              r['transaction_type'] == 'carried_forward';
          final isOpening = r['is_opening_balance'] == true ||
              r['source_type'] == 'opening_balance' ||
              isRollover;
          if (isOpening) {
            return false;
          }
          if (r['is_lot_receipt'] == true) {
            final hasOperational = details.any((d) =>
                d['is_packing_operational'] == true &&
                (d['cost_center_id'] == r['cost_center_id'] ||
                 normalizeArabic(d['target_product_name'] ?? '') == normalizeArabic(r['item_name'] ?? '')));
            return !hasOperational;
          }
          return true;
        })
        .fold<double>(
            0.0, (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0.0));

    final Map<String, Map<String, dynamic>> map = {};

    // Filter to genuine crop/variety cost centers & operational lines (exclude raw 5-digit COA accounts so they don't pollute crop cards)
    final cropAndOperationalCenters = allCentersList.where((center) {
      final code = (center.code ?? center.id).trim();
      final isPureCoaAccount = RegExp(r'^\d{5,}$').hasMatch(code);
      return !isPureCoaAccount;
    }).toList();

    // Initialize product centers (active + closed) — closed ones get is_closed=true flag
    for (final center in cropAndOperationalCenters) {
      map[center.id] = {
        'id': center.id,
        'name': center.nameAr,
        'name_en': center.nameEn,
        'type': center.typeLabelAr,
        'color': center.color,
        'icon': center.icon,
        'total_amount': 0.0,
        'opening_balance': center.openingBalance,
        'carried_forward_amount': 0.0,
        'transaction_count': 0,
        'percentage': 0.0,
        // Season locking flags — consumed by the UI
        'is_closed': center.isClosed,
        'season_status': center.seasonStatus,
        'closure_count': center.closureCount,
        'is_permanently_closed': center.isPermanentlyClosed,
      };
    }

    // Accumulate transaction costs
    for (final row in details) {
      if (row['is_redundant_rollover'] == true) {
        continue;
      }
      final isRollover = row['is_rollover'] == true ||
          row['source_type'] == 'season_rollover' ||
          row['transaction_type'] == 'carried_forward';
      final isOpening = row['is_opening_balance'] == true ||
          row['source_type'] == 'opening_balance' ||
          isRollover;

      final amount = (row['amount'] as num?)?.toDouble() ?? 0.0;

      if (isOpening) {
        final rawId = row['cost_center_id'] as String?;
        if (rawId != null && rawId.isNotEmpty) {
          final cc = CostCenterHelper.fromId(rawId, activeCentersList);
          String? targetMapKey;
          for (final k in map.keys) {
            final entry = map[k]!;
            final entryName = entry['name']?.toString() ?? '';
            if (k == cc.id || k == cc.code || k == rawId || entryName == cc.nameAr) {
              targetMapKey = k;
              break;
            }
          }
          final keyToUse = targetMapKey ?? cc.id;
          if (map.containsKey(keyToUse)) {
            map[keyToUse]!['carried_forward_amount'] =
                (map[keyToUse]!['carried_forward_amount'] as double) + amount;
            if (((map[keyToUse]!['opening_balance'] as num?)?.toDouble() ?? 0.0) == 0.0) {
              map[keyToUse]!['opening_balance'] = amount;
            }
          }
        }
        continue; // Do NOT add carried forward opening balance into direct operational cost
      }

      if (row['is_lot_receipt'] == true) {
        // Skip unallocated pre-production lot receipts only if the product already has packing order operational lines
        final hasOperational = details.any((d) =>
            d['is_packing_operational'] == true &&
            (d['cost_center_id'] == row['cost_center_id'] ||
             normalizeArabic(d['target_product_name'] ?? '') == normalizeArabic(row['item_name'] ?? '')));
        if (hasOperational) {
          continue;
        }
      }

      if (row['is_equal_distribution'] == true) {
        final List<String> orderProds =
            (row['order_products'] as List<dynamic>? ?? [])
                .map((e) => e.toString())
                .toList();

        // Find which active centers match the order products
        final matchedCenters = <CostCenter>[];
        for (final p in orderProds) {
          final normP = normalizeArabic(p);
          final canonP = CostCenter.canonicalCropName(p);
          final slugP = CostCenterHelper.resolveCropSlug(canonP);
          for (final c in activeCentersList) {
            final normC = normalizeArabic(c.nameAr);
            final match = normP == normC ||
                normP.contains(normC) ||
                normC.contains(normP) ||
                (slugP != 'CROP' && c.cropCode == slugP) ||
                (c.cropName != null && c.cropName == canonP);
            if (match) {
              if (!matchedCenters.contains(c)) matchedCenters.add(c);
            }
          }
        }

        final count = matchedCenters.isNotEmpty ? matchedCenters.length : 1;
        final splitAmt = amount / count;

        if (matchedCenters.isNotEmpty) {
          for (final c in matchedCenters) {
            if (map.containsKey(c.id)) {
              map[c.id]!['total_amount'] =
                  (map[c.id]!['total_amount'] as double) + splitAmt;
              map[c.id]!['transaction_count'] =
                  (map[c.id]!['transaction_count'] as int) + 1;
            }
          }
        }
        // No matching cost center found in DB — skip this transaction
        // (client must create cost centers manually)
      } else {
        final rawId = row['cost_center_id'] as String?;
        if (rawId == null || rawId.isEmpty) continue; // skip unassigned transactions
        final cat = row['category']?.toString() ?? '';
        final cc = CostCenterHelper.fromId(rawId, activeCentersList);

        // Find existing center in map by id or matching operational criteria
        String? targetMapKey;
        for (final k in map.keys) {
          final entry = map[k]!;
          final entryName = entry['name']?.toString() ?? '';
          if (k == cc.id ||
              k == cc.code ||
              k == rawId ||
              entryName == cc.nameAr ||
              ((cc.id == 'freight_logistics' || cat == 'تكلفة شركات الشحن') && (k == 'CC-CAT-4' || k == 'CC-LOGISTICS' || k == 'freight_logistics' || entryName.contains('شحن'))) ||
              ((cc.id == 'customs_clearance' || cat == 'تكلفة المخلصين') && (k == 'CC-CAT-5' || k == 'CC-CUSTOMS' || k == 'customs_clearance' || entryName.contains('تخليص') || entryName.contains('مخلص'))) ||
              ((cc.id == 'CC-CAT-6' || cat == 'لوجستيك ونقل') && (k == 'CC-CAT-6' || entryName.contains('لوجستيك') || entryName.contains('نقل'))) ||
              ((cc.id == 'packing_station' || cat == 'تعبئة وتغليف' || cat == 'مواد التعبئة') && (k == 'CC-CAT-3' || k == 'CC-PACKING' || k == 'packing_station' || entryName.contains('تعبئة')))) {
            targetMapKey = k;
            break;
          }
        }

        // Add to map if it exists in DB (allCenters) or is a valid variety / operational center
        if (targetMapKey == null && !map.containsKey(cc.id)) {
          if (cc.type == CostCenterType.operational || cc.id == 'packing_station' || cc.type == CostCenterType.variety) {
            map[cc.id] = {
              'id': cc.id,
              'name': cc.nameAr,
              'name_en': cc.nameEn,
              'type': cc.typeLabelAr,
              'color': cc.color,
              'icon': cc.icon,
              'total_amount': 0.0,
              'opening_balance': cc.openingBalance,
              'carried_forward_amount': 0.0,
              'transaction_count': 0,
              'percentage': 0.0,
              'is_closed': cc.isClosed,
              'season_status': cc.seasonStatus,
              'closure_count': cc.closureCount,
              'is_permanently_closed': cc.isPermanentlyClosed,
            };
            targetMapKey = cc.id;
          } else {
            // Not in DB — skip
            continue;
          }
        }
        final keyToUse = targetMapKey ?? cc.id;
        if (map.containsKey(keyToUse)) {
          map[keyToUse]!['total_amount'] = (map[keyToUse]!['total_amount'] as double) + amount;
          map[keyToUse]!['transaction_count'] =
              (map[keyToUse]!['transaction_count'] as int) + 1;
        }
      }
    }

    // Filter to relevant cost centers:
    // - Variety lines (crops) are ALWAYS kept.
    // - Operational lines with activity (transactions/balance) or explicitly registered in DB are kept.
    final list = map.values.where((item) {
      final isOperational = (item['type'] as String?) == 'مركز تشغيلي' ||
          (item['type'] as String?) == 'Operational Line';
      final hasActivity = ((item['total_amount'] as num?)?.toDouble() ?? 0.0) > 0 ||
          ((item['transaction_count'] as num?)?.toInt() ?? 0) > 0 ||
          ((item['opening_balance'] as num?)?.toDouble() ?? 0.0) > 0 ||
          ((item['carried_forward_amount'] as num?)?.toDouble() ?? 0.0) > 0;
      if (!isOperational) return true;
      if (hasActivity) return true;
      final centerId = item['id']?.toString() ?? '';
      return allCentersList.any((c) => c.dbId != null && (c.id == centerId || c.code == centerId));
    }).toList();
    for (final item in list) {
      final amt = item['total_amount'] as double;
      item['percentage'] = grandTotal > 0 ? (amt / grandTotal * 100) : 0.0;
    }

    list.sort((a, b) {
      final aClosed = (a['is_closed'] as bool?) ?? false;
      final bClosed = (b['is_closed'] as bool?) ?? false;
      if (aClosed != bClosed) return aClosed ? 1 : -1; // active first
      return (b['total_amount'] as double).compareTo(a['total_amount'] as double);
    });

    return list;
  }

  Future<List<String>> getDistinctCustomers({
    List<Map<String, dynamic>>? preloadedDetails,
  }) async {
    if (preloadedDetails != null && preloadedDetails.isNotEmpty) {
      final names = preloadedDetails
          .map((e) => e['customer_name'] as String?)
          .where((n) => n != null && n.isNotEmpty && n != 'عميل تصدير' && n != 'رصيد افتتاحي')
          .toSet()
          .toList();
      names.sort();
      return List<String>.from(names);
    }
    try {
      final result = await _client
          .from('export_shipments')
          .select('customer_name')
          .not('customer_name', 'is', null);

      final names = (result as List)
          .map((e) => e['customer_name'] as String?)
          .where((n) => n != null && n.isNotEmpty)
          .toSet()
          .toList();
      names.sort();
      return List<String>.from(names);
    } catch (_) {
      try {
        final result = await _client
            .from('vw_cost_details_live')
            .select('customer_name')
            .not('customer_name', 'is', null);

        final names = (result as List)
            .map((e) => e['customer_name'] as String?)
            .where((n) => n != null && n.isNotEmpty)
            .toSet()
            .toList();
        names.sort();
        return List<String>.from(names);
      } catch (_) {
        return [];
      }
    }
  }

  /// Aggregates cost center expenses into their canonical branches for ALL accounts starting with Code 3
  /// (Level 5 leaf accounts), comparing Total Estimated Cost vs Total Actual Settled Cost, Variance, and Variance Percentage.
  Future<List<Map<String, dynamic>>> getExpenseBranchVariance({
    String? fromDate,
    String? toDate,
    String? customer,
    String? costCenter,
    String? costCenterId,
    String? costCenterLabel,
    List<CostCenter>? activeCenters,
    List<CostCenter>? allCenters,
    List<Map<String, dynamic>>? preloadedDetails,
    List<Map<String, dynamic>>? preloadedCategories,
  }) async {
    final targetCc = costCenter ?? costCenterId;
    final Map<String, Map<String, dynamic>> branchMap = {};
    final Map<dynamic, String> accIdToCode = {};
    final Map<String, String> catNameToCode = {};

    // 1. Fetch all Level 5 accounts under Code 3 from accounts table
    try {
      final accData = await _client
          .from('accounts')
          .select('id, account_code, account_name, level, is_leaf')
          .like('account_code', '3%')
          .order('account_code');
      for (final a in accData as List) {
        final m = Map<String, dynamic>.from(a as Map);
        final code = (m['account_code'] ?? '').toString().trim();
        final name = (m['account_name'] ?? '').toString().trim();
        final id = m['id'];
        if (id != null) {
          accIdToCode[id] = code;
          accIdToCode[id.toString()] = code;
        }

        // Must be Level 5 (length >= 5 and not 3 or 4 digits)
        if (code.startsWith('3') && code.length >= 5 && code.length != 3 && code.length != 4) {
          final branchTitle = '$code - $name';
          branchMap[code] = {
            'branch_name': branchTitle,
            'category_code': code,
            'account_name': name,
            'account_id': id,
            'estimated_cost': 0.0,
            'actual_cost': 0.0,
            'variance_amount': 0.0,
            'variance_percentage': 0.0,
            'transaction_count': 0,
            'settled_count': 0,
            'pending_count': 0,
            'level': 5,
            'items': <Map<String, dynamic>>[],
          };
          if (name.isNotEmpty) {
            catNameToCode[normalizeArabic(name)] = code;
          }
        }
      }
    } catch (e) {
      debugPrint('ℹ️ Error loading accounts for expense branches: $e');
    }

    // Ensure 31251 - مصاريف مهندسين is always present
    if (!branchMap.containsKey('31251')) {
      branchMap['31251'] = {
        'branch_name': '31251 - مصاريف مهندسين',
        'category_code': '31251',
        'account_name': 'مصاريف مهندسين',
        'estimated_cost': 0.0,
        'actual_cost': 0.0,
        'variance_amount': 0.0,
        'variance_percentage': 0.0,
        'transaction_count': 0,
        'settled_count': 0,
        'pending_count': 0,
        'level': 5,
        'items': <Map<String, dynamic>>[],
      };
    }

    // 2. Load cost_report_categories to map category IDs to accounts
    try {
      final catsData = preloadedCategories ??
          await _client
              .from('cost_report_categories')
              .select('id, name, account_id, cost_center_id');
      for (final c in catsData as List) {
        final cId = c['id'];
        final aId = c['account_id'];
        final name = c['name']?.toString() ?? '';
        if (aId != null && accIdToCode.containsKey(aId)) {
          final code = accIdToCode[aId]!;
          if (cId != null) accIdToCode['cat_$cId'] = code;
          if (name.isNotEmpty) catNameToCode[normalizeArabic(name)] = code;
        }
      }
    } catch (e) {
      debugPrint('ℹ️ Error loading cost_report_categories: $e');
    }

    // 3. Attempt Supabase RPC first
    try {
      final rpcRes = await _client.rpc(
        'fn_get_cost_center_expense_branch_variance',
        params: {
          'p_cost_center_id': targetCc,
          'p_from_date': fromDate,
          'p_to_date': toDate,
          'p_customer': (customer != null && customer != 'all') ? customer : null,
        },
      );
      if (rpcRes is List && rpcRes.isNotEmpty) {
        for (final item in rpcRes) {
          final m = Map<String, dynamic>.from(item as Map);
          final code = (m['category_code'] ?? '').toString().trim();
          final name = (m['branch_name'] ?? '').toString().trim();
          if (code.length == 3 || code.length == 4) continue;
          if (!code.startsWith('3') && code != '31251' && code != 'engineer_expenses' && !name.contains('مهندس')) continue;

          final effectiveCode = (code == 'engineer_expenses' || name.contains('مهندس')) ? '31251' : code;
          final est = (m['estimated_cost'] as num?)?.toDouble() ?? 0.0;
          final act = (m['actual_cost'] as num?)?.toDouble() ?? 0.0;
          final tx = (m['transaction_count'] as num?)?.toInt() ?? 0;
          final settled = (m['settled_count'] as num?)?.toInt() ?? 0;
          final pending = (m['pending_count'] as num?)?.toInt() ?? 0;

          if (branchMap.containsKey(effectiveCode)) {
            final entry = branchMap[effectiveCode]!;
            entry['estimated_cost'] = est;
            entry['actual_cost'] = act;
            entry['variance_amount'] = act - est;
            entry['variance_percentage'] = est > 0 ? ((act - est) / est * 100) : 0.0;
            entry['transaction_count'] = tx;
            entry['settled_count'] = settled;
            entry['pending_count'] = pending;
          } else if (effectiveCode.startsWith('3') && effectiveCode.length >= 5) {
            branchMap[effectiveCode] = {
              'branch_name': name.isNotEmpty ? name : '$effectiveCode - مصروف تحليلي',
              'category_code': effectiveCode,
              'estimated_cost': est,
              'actual_cost': act,
              'variance_amount': act - est,
              'variance_percentage': est > 0 ? ((act - est) / est * 100) : 0.0,
              'transaction_count': tx,
              'settled_count': settled,
              'pending_count': pending,
              'level': 5,
              'items': <Map<String, dynamic>>[],
            };
          }
        }
      }
    } catch (e) {
      debugPrint('ℹ️ fn_get_cost_center_expense_branch_variance RPC info/fallback: $e');
    }

    // 4. Enrich or aggregate from getDetails
    final details = preloadedDetails ??
        await getDetails(
          fromDate: fromDate,
          toDate: toDate,
          customer: customer,
          costCenter: targetCc,
          costCenterLabel: costCenterLabel,
          activeCenters: activeCenters,
          allCenters: allCenters,
        );

    for (final row in details) {
      if (row['is_redundant_rollover'] == true) continue;
      final isRollover = row['is_rollover'] == true ||
          row['source_type'] == 'season_rollover' ||
          row['transaction_type'] == 'carried_forward';
      final isOpening = row['is_opening_balance'] == true ||
          row['source_type'] == 'opening_balance' ||
          isRollover;
      if (isOpening) continue;

      final cat = row['category']?.toString() ?? '';
      final name = row['item_name']?.toString() ?? '';
      final code = (row['account_code'] ?? row['code'] ?? '').toString().trim();
      final repCatId = row['report_category_id'];
      
      // Strict exclusion of Level 3 and 4
      if (code.length == 3 || code.length == 4) continue;

      String targetCode = '';
      if (code.startsWith('3') && code.length >= 5) {
        targetCode = code;
      } else if (repCatId != null && accIdToCode.containsKey('cat_$repCatId')) {
        targetCode = accIdToCode['cat_$repCatId']!;
      } else if (catNameToCode.containsKey(normalizeArabic(name))) {
        targetCode = catNameToCode[normalizeArabic(name)]!;
      } else if (catNameToCode.containsKey(normalizeArabic(cat))) {
        targetCode = catNameToCode[normalizeArabic(cat)]!;
      } else {
        final resolved = resolveExpenseBranchName(category: cat, itemName: name);
        final c = branchToCategoryCode(resolved);
        if (c.startsWith('3') && c.length >= 5) {
          targetCode = c;
        }
      }

      // If still not matched, check if engineer
      if (targetCode.isEmpty) {
        final isEng = cat == 'engineer_expenses' ||
            cat == '31251' ||
            cat.contains('مهندس') ||
            name.contains('مهندس') ||
            name.contains('إشراف') ||
            code == '31251';
        if (isEng) targetCode = '31251';
      }

      if (targetCode.isEmpty || !targetCode.startsWith('3') || targetCode.length < 5) {
        continue;
      }

      final entry = branchMap.putIfAbsent(targetCode, () => {
        'branch_name': '$targetCode - ${name.isNotEmpty ? name : "مصروف تحليلي"}',
        'category_code': targetCode,
        'estimated_cost': 0.0,
        'actual_cost': 0.0,
        'variance_amount': 0.0,
        'variance_percentage': 0.0,
        'transaction_count': 0,
        'settled_count': 0,
        'pending_count': 0,
        'level': 5,
        'items': <Map<String, dynamic>>[],
      });

      (entry['items'] as List<Map<String, dynamic>>).add(row);
    }

    // Accumulate locally if RPC returned empty
    for (final entry in branchMap.values) {
      final items = entry['items'] as List<Map<String, dynamic>>;
      if (items.isNotEmpty && (entry['transaction_count'] as int) == 0) {
        double est = 0.0;
        double act = 0.0;
        int settled = 0;
        int pending = 0;
        for (final row in items) {
          final rowAmt = (row['amount'] as num?)?.toDouble() ?? 0.0;
          final e = (row['expected_amount'] as num?)?.toDouble() ?? rowAmt;
          final a = (row['actual_amount'] as num?)?.toDouble() ?? rowAmt;
          final costStatus = row['cost_status']?.toString() ?? 'settled';
          final isSettled = costStatus == 'settled' || costStatus == 'actual' || row['actual_amount'] != null;
          est += e;
          act += a;
          if (isSettled) {
            settled++;
          } else {
            pending++;
          }
        }
        entry['estimated_cost'] = est;
        entry['actual_cost'] = act;
        entry['transaction_count'] = items.length;
        entry['settled_count'] = settled;
        entry['pending_count'] = pending;
      }

      final est = (entry['estimated_cost'] as num).toDouble();
      final act = (entry['actual_cost'] as num).toDouble();
      final variance = act - est;
      final variancePct = est > 0 ? (variance / est * 100) : 0.0;
      entry['variance_amount'] = variance;
      entry['variance_percentage'] = variancePct;
    }

    // 5. Filter if target cost center is selected
    var resultList = branchMap.values.toList();
    if (targetCc != null && targetCc.isNotEmpty && targetCc != 'all' && targetCc != 'ALL') {
      resultList = resultList.where((b) {
        final code = (b['category_code'] ?? '').toString();
        return code == targetCc;
      }).toList();
    }

    // 6. Sort resultList:
    // Sort: 31251 first, then ascending by code
    resultList.sort((a, b) {
      final aCode = (a['category_code'] ?? '').toString();
      final bCode = (b['category_code'] ?? '').toString();
      if (aCode == '31251') return -1;
      if (bCode == '31251') return 1;
      return aCode.compareTo(bCode);
    });

    return resultList;
  }
}

