import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/data_change_event_bus.dart';
import '../models/cost_center.dart';
import '../dao/cost_report_dao.dart';
import 'opening_balance_gl_sync_service.dart';

/// Comprehensive Agricultural Cost Centers Service for Fruity Farms ERP
/// Handles crop-centric consolidation, seasonal lifecycles, and balance rollovers.
class CostCenterService {
  static final CostCenterService instance = CostCenterService._();
  factory CostCenterService([SupabaseClient? client]) => client != null ? CostCenterService._(client) : instance;
  CostCenterService._([SupabaseClient? client]) : _customClient = client;

  final SupabaseClient? _customClient;
  SupabaseClient get _client => _customClient ?? Supabase.instance.client;

  /// Fetches all Cost Centers (Variety & Operational), optionally filtered by season or active status
  Future<List<CostCenter>> fetchCostCenters({
    bool onlyActive = true,
    String? season,
  }) async {
    try {
      var query = _client.from('cost_centers').select();

      if (onlyActive) {
        query = query.eq('is_active', true);
      }
      if (season != null && season.isNotEmpty) {
        query = query.eq('season', season);
      }

      final data = await query.order('cost_center_type').order('name');
      final list = (data as List)
          .map((e) => CostCenter.fromMap(Map<String, dynamic>.from(e)))
          .toList();


      return list;
    } catch (e) {
      debugPrint('CostCenterService fetchCostCenters error: $e');
      return [];
    }
  }

  /// Generates the standard IAS 41 agricultural seasonal name (e.g. "مانجو 2026")
  static String formatSeasonalName({required String cropName, required String season}) {
    final canon = CostCenter.canonicalCropName(cropName);
    return '$canon $season';
  }

  /// Manually creates or defines a cost center (crop seasonal or operational support line)
  Future<CostCenter?> createCostCenter({
    required String nameAr,
    String? nameEn,
    required CostCenterType type,
    String? cropName,
    String season = '2026-2027',
    dynamic productId,
    dynamic branchId,
    double openingBalance = 0.0,
    String? color,
    String? icon,
    String? notes,
  }) async {
    try {
      final isVariety = type == CostCenterType.variety;
      final effectiveCrop = isVariety
          ? CostCenter.canonicalCropName(cropName != null && cropName.isNotEmpty ? cropName : nameAr)
          : null;
      final slug = effectiveCrop != null ? CostCenterHelper.resolveCropSlug(effectiveCrop) : null;
      final effectiveSeason = season.trim().isNotEmpty ? season.trim() : '2026-2027';

      String code;
      String finalNameAr;
      String finalNameEn;

      if (isVariety) {
        final cropSlug = (slug != null && slug.isNotEmpty && slug != 'CROP') ? slug : 'CROP';
        code = 'CC-$cropSlug-$effectiveSeason';
        finalNameAr = nameAr.contains(effectiveSeason)
            ? nameAr
            : '$effectiveCrop (موسم $effectiveSeason)';
        finalNameEn = (nameEn != null && nameEn.trim().isNotEmpty)
            ? nameEn.trim()
            : '${CostCenterHelper.resolveEnglishName(effectiveCrop ?? nameAr)} (Season $effectiveSeason)';
      } else {
        final timestamp = DateTime.now().millisecondsSinceEpoch % 100000;
        code = 'CC-OP-$timestamp';
        finalNameAr = nameAr.trim();
        finalNameEn = (nameEn != null && nameEn.trim().isNotEmpty)
            ? nameEn.trim()
            : '${nameAr.trim()} Line';
      }

      final row = {
        'code': code,
        'name': finalNameAr,
        'name_ar': finalNameAr,
        'name_en': finalNameEn,
        'cost_center_type': isVariety ? 'variety' : 'operational',
        if (productId != null) 'product_id': int.tryParse(productId.toString()) ?? productId,
        'entity_type': isVariety ? 'fruit_type' : 'operational_line',
        if (effectiveCrop != null) 'crop_name': effectiveCrop,
        if (slug != null) 'crop_code': slug,
        'season': effectiveSeason,
        'season_status': 'active',
        'opening_balance': openingBalance,
        'current_balance': openingBalance,
        if (branchId != null) 'branch_id': int.tryParse(branchId.toString()) ?? branchId,
        if (color != null) 'color': color,
        if (icon != null) 'icon': icon,
        if (notes != null && notes.trim().isNotEmpty) 'description': notes.trim(),
        'is_active': true,
        'updated_at': DateTime.now().toIso8601String(),
      };

      final res = await _client.from('cost_centers').upsert(row, onConflict: 'code').select().maybeSingle();

      if (res != null) {
        final ccDbId = res['id']?.toString() ?? code;
        final txSourceId = 'cc_ob_$ccDbId';
        if (openingBalance > 0) {
          try {
            final opCategory = finalNameAr.contains('شحن')
                ? 'تكلفة شركات الشحن'
                : (finalNameAr.contains('تخليص') || finalNameAr.contains('مخلص')
                    ? 'تكلفة المخلصين'
                    : (finalNameAr.contains('لوجستيك') || finalNameAr.contains('نقل')
                        ? 'لوجستيك ونقل'
                        : (finalNameAr.contains('تعبئة') || finalNameAr.contains('تغليف')
                            ? 'تعبئة وتغليف'
                            : (finalNameAr.contains('مواد التعبئة')
                                ? 'مواد التعبئة'
                                : 'مصاريف إدارية'))));
            final effectiveCategory = isVariety ? 'تكلفة المحاصيل' : opCategory;

            await _client.from('cost_center_transactions').upsert({
              'cost_center_id': code,
              'cost_center_name': finalNameAr,
              'cost_center_type': isVariety ? 'variety' : 'operational',
              'source_type': 'opening_balance',
              'source_id': txSourceId,
              'transaction_date': DateTime.now().toIso8601String().substring(0, 10),
              'supplier_name': 'رصيد أول المدة',
              'product_id': (productId != null) ? int.tryParse(productId.toString()) : null,
              'item_name': 'رصيد افتتاحي - $finalNameAr',
              'category': effectiveCategory,
              'quantity': 1,
              'unit_price': openingBalance,
              'currency': 'EGP',
              'exchange_rate': 1.0,
              'total_in_currency': openingBalance,
              'amount': openingBalance,
              'notes': (notes != null && notes.trim().isNotEmpty) ? notes.trim() : 'رصيد افتتاحي مسجل لمركز التكلفة',
              'is_confirmed': true,
            }, onConflict: 'source_type,source_id');
          } catch (err) {
            debugPrint('CostCenterService createCostCenter opening balance sync error: $err');
          }

          // Sync opening balance to General Ledger (Account 23421)
          try {
            await OpeningBalanceGlSyncService.instance.syncCostCenterOpeningBalance(
              costCenterId: res['id'] ?? code,
              costCenterName: finalNameAr,
              costCenterCode: code,
              type: type,
              openingBalance: openingBalance,
              branchId: int.tryParse(branchId?.toString() ?? ''),
            );
          } catch (err) {
            debugPrint('CostCenterService GL 23421 sync error: $err');
          }
        } else {
          try {
            await _client.from('cost_center_transactions').delete().match({
              'source_type': 'opening_balance',
              'source_id': txSourceId,
            });
            await OpeningBalanceGlSyncService.instance.deleteEntityOpeningBalance(
              'cost_center_$code',
              null,
            );
          } catch (_) {}
        }
      }

      DataChangeEventBus.instance.notifyCostCentersChanged();

      if (res != null) {
        return CostCenter.fromMap(Map<String, dynamic>.from(res));
      }
      return null;
    } catch (e) {
      debugPrint('CostCenterService createCostCenter error: $e');
      rethrow;
    }
  }

  /// Creates or updates a seasonal cost center for a specific crop
  Future<CostCenter?> createSeasonalCostCenter({
    required String cropName,
    required String season,
    dynamic productId,
    dynamic branchId,
    double openingBalance = 0.0,
    String? color,
    String? icon,
    String? notes,
  }) async {
    try {
      final canonCropName = CostCenter.canonicalCropName(cropName);
      final slug = CostCenterHelper.resolveCropSlug(canonCropName);
      final code = 'CC-$slug-$season';
      final nameAr = '$canonCropName (موسم $season)';
      final nameEn = '${CostCenterHelper.resolveEnglishName(canonCropName)} (Season $season)';

      final row = {
        'code': code,
        'name': nameAr,
        'name_ar': nameAr,
        'name_en': nameEn,
        'cost_center_type': 'variety',
        if (productId != null) 'product_id': int.tryParse(productId.toString()) ?? productId,
        'entity_type': 'fruit_type',
        'crop_name': canonCropName,
        'crop_code': slug,
        'season': season,
        'season_status': 'active',
        'opening_balance': openingBalance,
        'current_balance': openingBalance,
        if (branchId != null) 'branch_id': int.tryParse(branchId.toString()) ?? branchId,
        if (color != null) 'color': color,
        if (icon != null) 'icon': icon,
        if (notes != null) 'description': notes,
        'is_active': true,
        'updated_at': DateTime.now().toIso8601String(),
      };

      final res = await _client.from('cost_centers').upsert(row, onConflict: 'code').select().maybeSingle();

      if (res != null) {
        final ccDbId = res['id']?.toString() ?? code;
        final txSourceId = 'cc_ob_$ccDbId';
        if (openingBalance > 0) {
          try {
            await _client.from('cost_center_transactions').upsert({
              'cost_center_id': code,
              'cost_center_name': nameAr,
              'cost_center_type': 'variety',
              'source_type': 'opening_balance',
              'source_id': txSourceId,
              'transaction_date': DateTime.now().toIso8601String().substring(0, 10),
              'supplier_name': 'رصيد أول المدة',
              'product_id': (productId != null) ? int.tryParse(productId.toString()) : null,
              'item_name': 'رصيد افتتاحي - $nameAr',
              'category': 'تكلفة المحاصيل',
              'quantity': 1,
              'unit_price': openingBalance,
              'currency': 'EGP',
              'exchange_rate': 1.0,
              'total_in_currency': openingBalance,
              'amount': openingBalance,
              'notes': (notes != null && notes.trim().isNotEmpty) ? notes.trim() : 'رصيد افتتاحي مسجل لمركز التكلفة',
              'is_confirmed': true,
            }, onConflict: 'source_type,source_id');
          } catch (err) {
            debugPrint('CostCenterService createSeasonalCostCenter opening balance sync error: $err');
          }

          // Sync opening balance to General Ledger (Account 23421)
          try {
            await OpeningBalanceGlSyncService.instance.syncCostCenterOpeningBalance(
              costCenterId: res['id'] ?? code,
              costCenterName: nameAr,
              costCenterCode: code,
              type: CostCenterType.variety,
              openingBalance: openingBalance,
              branchId: int.tryParse(branchId?.toString() ?? ''),
            );
          } catch (err) {
            debugPrint('CostCenterService createSeasonalCostCenter GL 23421 sync error: $err');
          }
        } else {
          try {
            await _client.from('cost_center_transactions').delete().match({
              'source_type': 'opening_balance',
              'source_id': txSourceId,
            });
            await OpeningBalanceGlSyncService.instance.deleteEntityOpeningBalance(
              'cost_center_$code',
              null,
            );
          } catch (_) {}
        }
      }

      DataChangeEventBus.instance.notifyCostCentersChanged();

      if (res != null) {
        return CostCenter.fromMap(Map<String, dynamic>.from(res));
      }
      return null;
    } catch (e) {
      debugPrint('CostCenterService createSeasonalCostCenter error: $e');
      rethrow;
    }
  }

  /// Executes seasonal closing and automatically rolls over remaining balance into the next season.
  /// Enforces the strict agricultural accounting rules:
  /// 1. Period 1 -> Period 2: Rollover within the SAME cost center card without creating a new card.
  /// 2. Period 2 (Final Season Closure): Current card permanently closes (Read-Only), and a NEW card is created for the next season.
  Future<Map<String, dynamic>> closeAndRolloverSeason({
    required dynamic costCenterId,
    required String nextSeason,
    String? notes,
    String? targetStage,
    double? overrideRolloverBalance,
  }) async {
    try {
      dynamic resolvedId = int.tryParse(costCenterId.toString());
      if (resolvedId == null) {
        final queryStr = costCenterId.toString();
        final row = await _client
            .from('cost_centers')
            .select('id')
            .or('code.eq.$queryStr,name_ar.eq.$queryStr,name.eq.$queryStr')
            .maybeSingle();
        if (row != null && row['id'] != null) {
          resolvedId = row['id'];
        }
      }

      if (resolvedId == null) {
        throw Exception('تعذر العثور على المعرف الرقمي لمركز التكلفة: $costCenterId');
      }

      // Fetch current cost center details
      final existing = await _client
          .from('cost_centers')
          .select()
          .eq('id', resolvedId)
          .maybeSingle();

      if (existing == null) {
        throw Exception('مركز التكلفة برقم $resolvedId غير موجود');
      }

      final seasonStatus = existing['season_status']?.toString() ?? 'active';
      final closureCount = (existing['closure_count'] as num?)?.toInt() ?? 0;
      final seasonNumber = (existing['season_number'] as num?)?.toInt() ?? 1;

      // Hard reject: permanently closed
      if (seasonStatus == 'permanently_closed' || closureCount >= 2) {
        throw Exception(
            'مركز التكلفة (${existing['name_ar']}) مقفل نهائياً للسنة الزراعية (${existing['season']}). '
            'تم استنفاد الموسمين المسموح بهما ولا يمكن الترحيل مرة أخرى.');
      }

      // Standard duplicate check
      final isClosed = seasonStatus == 'closed' ||
          existing['status'] == 'closed' ||
          existing['is_active'] == false;
      if (isClosed) {
        throw Exception(
            'مركز التكلفة (${existing['name_ar']}) مقفل بالفعل لهذا الموسم (${existing['season']}) ولا يمكن تكرار ترحيله.');
      }

      // Strict stage idempotency guard against double-clicks
      if (targetStage == 'season_1_to_2' && (seasonNumber == 2 || closureCount >= 1)) {
        throw Exception(
            'تم إقفال وترحيل الفترة الأولى بالفعل لمركز التكلفة (${existing['name_ar']}) ولا يمكن تكرار الترحيل.');
      }
      if (targetStage == 'final_closure' && (seasonNumber == 1 && closureCount == 0)) {
        throw Exception(
            'يجب إقفال وترحيل الفترة الأولى أولاً قبل تنفيذ الإقفال النهائي للسنة الزراعية لمركز التكلفة (${existing['name_ar']}).');
      }

      // ── Stage Determination ──
      // Stage 1: Period 1 -> Period 2 within the SAME cost center card
      // Stage 2: Final Year-end closure -> permanently lock current card and create a NEW card for next year
      final bool isFinalClosure = targetStage == 'final_closure' || (targetStage == null && (seasonNumber == 2 || closureCount >= 1));

      final code = existing['code']?.toString() ?? '';
      final nameAr = existing['name_ar']?.toString() ?? '';
      final currentSeason = existing['season']?.toString().trim() ?? '2026-2027';

      // Determine accurate net balance:
      // If overrideRolloverBalance is supplied (from the report screen), use it directly.
      // Otherwise, query CostReportDao to calculate the exact operational & baseline balance.
      double? calculatedBalance = overrideRolloverBalance;
      if (calculatedBalance == null) {
        try {
          final dao = CostReportDao(_client);
          final details = await dao.getDetails(costCenter: code);
          if (details.isNotEmpty) {
            double reportTotal = 0.0;
            for (final row in details) {
              final amt = (row['amount'] as num?)?.toDouble() ?? 0.0;
              final isExcluded = row['is_redundant_rollover'] == true ||
                  row['exclude_from_totals'] == true;
              if (!isExcluded) {
                reportTotal += amt;
              }
            }
            calculatedBalance = reportTotal;
          }
        } catch (e) {
          debugPrint('CostCenterService CostReportDao pre-calculation error: $e');
        }
      }

      // First, try calling the RPC if available
      try {
        String sanitizedSeason = nextSeason.trim();
        final yearMatch = RegExp(r'(\d{4})').firstMatch(sanitizedSeason);
        if (yearMatch != null) {
          final y1 = int.parse(yearMatch.group(1)!);
          sanitizedSeason = isFinalClosure ? '$y1-${y1 + 1}' : (existing['season']?.toString().trim() ?? '$y1-${y1 + 1}');
        }

        final res = await _client.rpc('rpc_close_and_rollover_cost_center', params: {
          'p_cost_center_id': resolvedId,
          'p_next_season': sanitizedSeason,
          if (notes != null && notes.isNotEmpty) 'p_notes': notes.trim(),
          if (targetStage != null && targetStage.isNotEmpty) 'p_target_stage': targetStage.trim(),
          if (calculatedBalance != null) 'p_override_balance': calculatedBalance,
        });

        if (res is Map && res['success'] == true) {
          // Verify that the RPC adhered to the required stage contract:
          // In Stage 1: new_cost_center_id must equal resolvedId (same card)
          if (!isFinalClosure && res['new_cost_center_id'] != null && res['new_cost_center_id'] == resolvedId) {
            DataChangeEventBus.instance.notifyCostCentersChanged();
            return Map<String, dynamic>.from(res);
          } else if (isFinalClosure && res['is_final_closure'] == true) {
            DataChangeEventBus.instance.notifyCostCentersChanged();
            return Map<String, dynamic>.from(res);
          }
        }
      } catch (rpcErr) {
        debugPrint('ℹ️ rpc_close_and_rollover_cost_center fallback triggered: $rpcErr');
        final errStr = rpcErr.toString();
        if (errStr.contains('مقفل') ||
            errStr.contains('استنفاد') ||
            errStr.contains('الحد الأقصى') ||
            errStr.contains('غير موجود')) {
          rethrow;
        }
      }

      // ── High-Fidelity Agricultural 2-Stage Lifecycle Implementation ──
      // 1. Calculate net balance
      double netBalance = calculatedBalance ?? 0.0;
      if (calculatedBalance == null) {
        final txs = await _client
            .from('cost_center_transactions')
            .select('amount, source_type, source_id, item_name')
            .or('cost_center_id.eq.$code,cost_center_id.eq.$resolvedId,cost_center_name.eq.$nameAr')
            .eq('is_confirmed', true);

        bool hasOpeningTx = false;
        for (final t in txs) {
          final st = t['source_type']?.toString();
          final sid = t['source_id']?.toString() ?? '';
          final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;

          if (st == 'opening_balance' || st == 'season_rollover') {
            hasOpeningTx = true;
          }

          // Deduplication: Ignore intra-center rollover to avoid duplicating underlying operations
          if (st == 'season_rollover' && RegExp(r'^rollover_(\d+)_to_\1').hasMatch(sid)) {
            continue;
          }

          netBalance += amt;
        }

        if (!hasOpeningTx) {
          netBalance += (existing['opening_balance'] as num?)?.toDouble() ?? 0.0;
        }
      }

      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

      if (!isFinalClosure) {
        // ── STAGE 1: Period 1 -> Period 2 within SAME cost center ──
        // Update the existing card: remains ACTIVE, period becomes 2, closure_count becomes 1
        await _client.from('cost_centers').update({
          'season_number': 2,
          'closure_count': 1,
          'current_balance': netBalance,
          'is_active': true,
          'status': 'active',
          'season_status': 'active',
          'description': notes?.trim().isNotEmpty == true
              ? notes!.trim()
              : (existing['description'] ?? 'تم ترحيل الفترة الأولى إلى الفترة الثانية داخل نفس الكارت'),
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', resolvedId);

        // Record rollover transaction within the same cost center
        if (netBalance != 0) {
          final sourceId = 'rollover_${resolvedId}_to_$resolvedId';
          await _client.from('cost_center_transactions').upsert({
            'cost_center_id': code,
            'cost_center_name': nameAr,
            'cost_center_type': existing['cost_center_type'] ?? 'variety',
            'source_type': 'season_rollover',
            'source_id': sourceId,
            'transaction_date': todayStr,
            'supplier_name': 'رصيد مرحل من الفترة الأولى',
            'product_id': existing['product_id'],
            'item_name': 'رصيد مرحل من الفترة الأولى إلى الفترة الثانية',
            'category': 'رصيد مرحل من الفترة الأولى',
            'quantity': 1,
            'unit_price': netBalance,
            'currency': 'EGP',
            'exchange_rate': 1.0,
            'total_in_currency': netBalance,
            'amount': netBalance,
            'notes': notes?.trim().isNotEmpty == true
                ? notes!.trim()
                : 'ترحيل رصيد الفترة الأولى إلى الفترة الثانية داخل نفس كارت مركز التكلفة ($nameAr)',
            'is_confirmed': true,
            'is_opening_balance': true,
            'transaction_type': 'carried_forward',
          }, onConflict: 'source_type,source_id');
        }

        DataChangeEventBus.instance.notifyCostCentersChanged();

        return {
          'success': true,
          'message': 'تم ترحيل رصيد الفترة الأولى إلى الفترة الثانية بنجاح داخل نفس كارت مركز التكلفة ($nameAr) بدون إنشاء كارت جديد',
          'closure_stage': 'season_1_to_2',
          'is_final_closure': false,
          'closed_cost_center_id': resolvedId,
          'cost_center_id': resolvedId,
          'cost_center_code': code,
          'cost_center_name': nameAr,
          'season': currentSeason,
          'season_number': 2,
          'closure_count': 1,
          'new_cost_center_id': resolvedId,
          'new_cost_center_code': code,
          'new_cost_center_name': nameAr,
          'rollover_balance': netBalance,
        };
      } else {
        // ── STAGE 2: Final Season Closure ──
        // 1. Calculate next year season (e.g. 2026-2027 -> 2027-2028)
        String calcNextSeason = '';
        final m = RegExp(r'(\d{4})').firstMatch(nextSeason);
        if (m != null) {
          final y = int.parse(m.group(1)!);
          calcNextSeason = '$y-${y + 1}';
        } else {
          final curM = RegExp(r'(\d{4})').firstMatch(currentSeason);
          final curY = curM != null ? int.parse(curM.group(1)!) : 2026;
          calcNextSeason = '${curY + 1}-${curY + 2}';
        }

        final cleanCropName = CostCenter.canonicalCropName(existing['crop_name']?.toString() ?? nameAr);
        final slug = existing['crop_code']?.toString() ?? CostCenterHelper.resolveCropSlug(cleanCropName);
        final newCode = 'CC-$slug-$calcNextSeason';
        final newNameAr = '$cleanCropName (موسم $calcNextSeason)';
        final newNameEn = '${existing['name_en'] ?? slug} (Season $calcNextSeason)';

        // 2. Insert NEW cost center card for next year
        final inserted = await _client.from('cost_centers').upsert({
          'code': newCode,
          'name': newNameAr,
          'name_ar': newNameAr,
          'name_en': newNameEn,
          'cost_center_type': existing['cost_center_type'] ?? 'variety',
          'product_id': existing['product_id'],
          'entity_type': existing['entity_type'] ?? 'fruit_type',
          'color': existing['color'] ?? '#F59E0B',
          'icon': existing['icon'] ?? 'eco',
          'is_active': true,
          'status': 'active',
          'crop_name': cleanCropName,
          'crop_code': slug,
          'season': calcNextSeason,
          'season_status': 'active',
          'opening_balance': netBalance,
          'current_balance': netBalance,
          'branch_id': existing['branch_id'],
          'description': notes?.trim().isNotEmpty == true
              ? notes!.trim()
              : 'مرحل تلقائياً من إقفال السنة الزراعية $currentSeason',
          'closure_count': 0,
          'season_number': 1,
        }, onConflict: 'code').select('id').single();

        final dynamic newCcId = inserted['id'];

        // 3. Update old cost center to permanently closed (Read-Only)
        await _client.from('cost_centers').update({
          'status': 'permanently_closed',
          'season_status': 'permanently_closed',
          'is_active': false,
          'closed_at': DateTime.now().toIso8601String(),
          'current_balance': netBalance,
          'rollover_cost_center_id': newCcId,
          'closure_count': 2,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', resolvedId);

        // 4. Insert rollover into NEW cost center
        if (netBalance != 0) {
          final sourceId = 'rollover_${resolvedId}_to_$newCcId';
          await _client.from('cost_center_transactions').upsert({
            'cost_center_id': newCode,
            'cost_center_name': newNameAr,
            'cost_center_type': existing['cost_center_type'] ?? 'variety',
            'source_type': 'season_rollover',
            'source_id': sourceId,
            'transaction_date': todayStr,
            'supplier_name': 'رصيد افتتاحي للموسم الجديد',
            'product_id': existing['product_id'],
            'item_name': 'رصيد افتتاحي مرحل من موسم $currentSeason',
            'category': 'رصيد افتتاحي منقول من الموسم السابق',
            'quantity': 1,
            'unit_price': netBalance,
            'currency': 'EGP',
            'exchange_rate': 1.0,
            'total_in_currency': netBalance,
            'amount': netBalance,
            'notes': 'ترحيل نهائي - إقفال السنة الزراعية من مركز #$resolvedId ($nameAr)',
            'is_confirmed': true,
            'is_opening_balance': true,
            'transaction_type': 'carried_forward',
          }, onConflict: 'source_type,source_id');
        }

        // 5. Update fruit_types routing to the new code
        try {
          await _client
              .from('fruit_types')
              .update({'cost_center_id': newCode})
              .or('cost_center_id.eq.$code,cost_center_id.eq.$resolvedId');
        } catch (_) {}

        DataChangeEventBus.instance.notifyCostCentersChanged();

        return {
          'success': true,
          'message': 'تم إقفال السنة الزراعية نهائياً وتعيين الكارت للاطلاع فقط، وإنشاء كارت مركز تكلفة جديد للسنة الزراعية $calcNextSeason وترحيل الرصيد بنجاح',
          'closure_stage': 'final_closure',
          'is_final_closure': true,
          'closed_cost_center_id': resolvedId,
          'closed_season': currentSeason,
          'new_cost_center_id': newCcId,
          'new_cost_center_code': newCode,
          'new_cost_center_name': newNameAr,
          'new_season': calcNextSeason,
          'new_season_number': 1,
          'rollover_balance': netBalance,
        };
      }
    } catch (e) {
      debugPrint('CostCenterService closeAndRolloverSeason error: $e');
      rethrow;
    }
  }

  /// Retrieves list of distinct seasons recorded in the system
  Future<List<String>> getAvailableSeasons() async {
    try {
      final data = await _client.from('cost_centers').select('season').not('season', 'is', null);
      final seasons = <String>{};
      for (final r in data) {
        final s = r['season']?.toString().trim();
        if (s != null && s.isNotEmpty) {
          seasons.add(s);
        }
      }
      if (seasons.isEmpty) {
        seasons.add('2026-2027');
      }
      final sorted = seasons.toList()..sort((a, b) => b.compareTo(a));
      return sorted;
    } catch (_) {
      return ['2026-2027', '2025-2026'];
    }
  }
}
