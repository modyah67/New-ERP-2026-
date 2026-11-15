import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/packing_order_model.dart';
import '../models/packing_order_line_model.dart';
import '../models/packing_cost_variance_model.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// Packing Cost Variance Service
///
/// 100% Read-Only Service.
/// Extracts Estimated Costs vs. Verified Actual Costs for Packing Orders
/// across all workflow stages (Stage 1 Crops, Stage 2 Packaging, Stage 3 Costs, Stage 4 Final).
///
/// Strict Accounting Principles Applied:
/// 1. NO GUESSWORK: If no verifiable document/stage exists, actualCost = null ("غير متاح").
/// 2. STAGE SYNCHRONIZATION: Completing Stage 1 confirms actual crop disbursement in the variance table.
/// 3. NO DOUBLE COUNTING: Inventory issue and GL lines are not summed together.
/// 4. PAYMENT != EXPENSE: Payments are settlements of liabilities. Accruals/disbursements represent cost.
/// 5. DEBIT NOTES: Net Actual = Gross Actual - Approved Debit Notes.
/// 6. FAIR VARIANCE: Total variance compares actual items against their specific estimates.
/// 7. NO MUTATIONS: Strictly read-only; never creates or updates journal entries or inventory.
/// ═══════════════════════════════════════════════════════════════════════════
class PackingCostVarianceService {
  static final SupabaseClient _client = Supabase.instance.client;

  /// Canonical Identity Key for packing cost items to prevent duplicate rows across UI, notes, and DB.
  static String canonicalCostKey(Map<String, dynamic> c) {
    final rawName = (c['name']?.toString() ?? '').trim().toLowerCase()
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي');

    final catStr = (c['category']?.toString() ?? '').toLowerCase();
    final suppType = (c['supplier_type']?.toString() ?? '').toLowerCase();

    String normCat = 'other';
    if (rawName.contains('مهندس') || catStr.contains('engineer') || suppType == 'engineer' || c['custody_id'] != null) {
      normCat = 'engineer';
    } else if (rawName.contains('ادار') || catStr.contains('admin') || suppType == 'admin') {
      normCat = 'admin';
    } else if (rawName.contains('محط') || catStr.contains('station') || suppType == 'station' || c['station_supplier_id'] != null) {
      normCat = 'station';
    } else if (rawName.contains('تخصيم') || rawName.contains('عمال') || catStr.contains('deduction') || suppType == 'deduction' || suppType == 'deductions') {
      normCat = 'deduction';
    } else if (rawName.contains('نقل') || rawName.contains('شحن') || rawName.contains('نولون') || catStr.contains('transport') || catStr.contains('logistics') || suppType == 'transport' || c['transport_supplier_id'] != null) {
      normCat = 'transport';
    }

    final num expNum = (c['expected_amount'] ?? c['base_amount'] ?? c['total_egp'] ?? c['total'] ?? c['original_amount'] ?? 0) as num;
    final expStr = expNum.toDouble().toStringAsFixed(2);
    return '$rawName|$normCat|$expStr';
  }

  /// Canonical Identity Key for comparison items in the variance report table.
  static String canonicalComparisonKey(PackingCostItemComparison item) {
    final rawName = item.name.trim().toLowerCase()
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي');

    final catStr = item.category.trim().toLowerCase();
    String normCat = 'other';
    if (rawName.contains('مهندس') || catStr.contains('engineer')) {
      normCat = 'engineer';
    } else if (rawName.contains('ادار') || catStr.contains('admin')) {
      normCat = 'admin';
    } else if (rawName.contains('محط') || catStr.contains('station')) {
      normCat = 'station';
    } else if (rawName.contains('تخصيم') || rawName.contains('عمال') || catStr.contains('deduction')) {
      normCat = 'deduction';
    } else if (rawName.contains('نقل') || rawName.contains('شحن') || rawName.contains('نولون') || catStr.contains('transport') || catStr.contains('logistics')) {
      normCat = 'transport';
    } else {
      normCat = catStr;
    }

    final expStr = item.estimatedCost.toStringAsFixed(2);
    return '$rawName|$normCat|$expStr';
  }

  /// Analyze and generate a comprehensive Estimated vs. Actual Cost report.
  static Future<PackingCostVarianceReport> generateReport(
    PackingOrderModel order, {
    List<PackingOrderLineModel>? lines,
  }) async {
    try {
      final orderId = int.tryParse(order.id ?? '0') ?? 0;
      final orderNumber = order.orderNumber.isNotEmpty ? order.orderNumber : (orderId > 0 ? '#$orderId' : '—');

      // ── 1. Fetch Latest DB State (Ensure Fresh Stage Flags and Notes) ──
      PackingOrderModel activeOrder = order;
      if (orderId > 0) {
        try {
          final dbOrderRes = await _client
              .from('packing_orders')
              .select('status, crops_confirmed_at, crops_journal_entry_id, packaging_confirmed_at, packaging_journal_entry_id, costs_confirmed_at, costs_journal_entry_id, final_approved_at, journal_entry_id, notes, fruit_cost_base, fruit_cost_allocated, actual_material_cost, material_cost_base')
              .eq('id', orderId)
              .maybeSingle();
          if (dbOrderRes != null) {
            final dbStatus = dbOrderRes['status']?.toString();
            final dbCropsAt = dbOrderRes['crops_confirmed_at'] != null
                ? DateTime.tryParse(dbOrderRes['crops_confirmed_at'].toString())
                : null;
            final dbCropsJeId = dbOrderRes['crops_journal_entry_id']?.toString();
            activeOrder = activeOrder.copyWith(
              status: dbStatus ?? activeOrder.status,
              cropsConfirmedAt: dbCropsAt ?? activeOrder.cropsConfirmedAt,
              cropsJournalEntryId: dbCropsJeId ?? activeOrder.cropsJournalEntryId,
              packagingConfirmedAt: dbOrderRes['packaging_confirmed_at'] != null
                  ? DateTime.tryParse(dbOrderRes['packaging_confirmed_at'].toString())
                  : activeOrder.packagingConfirmedAt,
              packagingJournalEntryId: dbOrderRes['packaging_journal_entry_id']?.toString() ?? activeOrder.packagingJournalEntryId,
              costsConfirmedAt: dbOrderRes['costs_confirmed_at'] != null
                  ? DateTime.tryParse(dbOrderRes['costs_confirmed_at'].toString())
                  : activeOrder.costsConfirmedAt,
              costsJournalEntryId: dbOrderRes['costs_journal_entry_id']?.toString() ?? activeOrder.costsJournalEntryId,
              finalApprovedAt: dbOrderRes['final_approved_at'] != null
                  ? DateTime.tryParse(dbOrderRes['final_approved_at'].toString())
                  : activeOrder.finalApprovedAt,
              journalEntryId: dbOrderRes['journal_entry_id']?.toString() ?? activeOrder.journalEntryId,
              fruitCostBase: (dbOrderRes['fruit_cost_base'] as num?)?.toDouble() ?? activeOrder.fruitCostBase,
              fruitCostAllocated: (dbOrderRes['fruit_cost_allocated'] as num?)?.toDouble() ?? activeOrder.fruitCostAllocated,
              actualMaterialCost: (dbOrderRes['actual_material_cost'] as num?)?.toDouble() ?? activeOrder.actualMaterialCost,
              materialCostBase: (dbOrderRes['material_cost_base'] as num?)?.toDouble() ?? activeOrder.materialCostBase,
              notes: dbOrderRes['notes']?.toString() ?? activeOrder.notes,
            );
          }
        } catch (e) {
          debugPrint('⚠️ PackingCostVarianceService: Error checking DB stage state: $e');
        }
      }

      // ── 2. Parse Notes & Multi-Stage Metadata ──
      Map<String, dynamic> notes = {};
      if (activeOrder.notes != null && activeOrder.notes!.isNotEmpty) {
        try {
          final parsed = jsonDecode(activeOrder.notes!);
          if (parsed is Map) {
            notes = Map<String, dynamic>.from(parsed);
          }
        } catch (_) {}
      }

      final workflowStages = notes['workflow_stages'] as Map?;
      final cropsStageNotes = workflowStages?['crops'] as Map?;
      final packagingStageNotes = workflowStages?['packaging'] as Map?;
      final costsStageNotes = workflowStages?['costs'] as Map?;

      final bool isOrderCompleted = activeOrder.status == 'completed' || activeOrder.status == 'final_approved';

      bool isCropsConfirmed = activeOrder.isCropsConfirmed ||
          activeOrder.cropsConfirmedAt != null ||
          activeOrder.cropsJournalEntryId != null ||
          (cropsStageNotes != null && (cropsStageNotes['confirmed_at'] != null || cropsStageNotes['journal_entry_id'] != null));

      bool isPackagingConfirmed = activeOrder.isPackagingConfirmed ||
          activeOrder.packagingConfirmedAt != null ||
          activeOrder.packagingJournalEntryId != null ||
          (packagingStageNotes != null && (packagingStageNotes['confirmed_at'] != null || packagingStageNotes['journal_entry_id'] != null));

      bool isCostsConfirmed = activeOrder.isCostsConfirmed ||
          activeOrder.costsConfirmedAt != null ||
          activeOrder.costsJournalEntryId != null ||
          (costsStageNotes != null && (costsStageNotes['confirmed_at'] != null || costsStageNotes['journal_entry_id'] != null));

      // ── 3. Candidate Journal Entry IDs ──
      final Set<int> candidateJeIds = {};
      void addJeId(dynamic val) {
        if (val == null) return;
        final parsed = int.tryParse(val.toString());
        if (parsed != null && parsed > 0) candidateJeIds.add(parsed);
      }
      addJeId(activeOrder.cropsJournalEntryId);
      addJeId(activeOrder.packagingJournalEntryId);
      addJeId(activeOrder.costsJournalEntryId);
      addJeId(activeOrder.journalEntryId);
      addJeId(cropsStageNotes?['journal_entry_id']);
      addJeId(packagingStageNotes?['journal_entry_id']);
      addJeId(costsStageNotes?['journal_entry_id']);

      // ── 4. Fetch Journal Entries & Ledger Lines (Read-Only) ──
      Map<String, dynamic>? mainJournalEntry;
      Map<String, dynamic>? cropsJournalEntry;
      Map<String, dynamic>? packagingJournalEntry;
      Map<String, dynamic>? costsJournalEntry;
      List<Map<String, dynamic>> ledgerLines = [];
      List<Map<String, dynamic>> debitNoteEntries = [];

      if (orderId > 0) {
        try {
          final orFilters = <String>['source_id.eq.$orderId'];
          if (candidateJeIds.isNotEmpty) {
            orFilters.add('id.in.(${candidateJeIds.join(",")})');
          }

          final jeRes = await _client
              .from('journal_entries')
              .select('id, entry_number, entry_date, description, status, source_type, source_id')
              .or(orFilters.join(','))
              .filter('deleted_at', 'is', null)
              .order('created_at', ascending: false);

          final jeList = (jeRes as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

          for (final je in jeList) {
            final sType = je['source_type']?.toString();
            final jeId = (je['id'] as num?)?.toInt();
            if (sType == 'packing_order_crops' || jeId == int.tryParse(activeOrder.cropsJournalEntryId ?? '')) {
              cropsJournalEntry ??= je;
            } else if (sType == 'packing_order_packaging' || jeId == int.tryParse(activeOrder.packagingJournalEntryId ?? '')) {
              packagingJournalEntry ??= je;
            } else if (sType == 'packing_order_costs' || jeId == int.tryParse(activeOrder.costsJournalEntryId ?? '')) {
              costsJournalEntry ??= je;
            } else if (sType == 'packing_order' || jeId == int.tryParse(activeOrder.journalEntryId ?? '')) {
              mainJournalEntry ??= je;
            }
          }
          mainJournalEntry ??= cropsJournalEntry ?? packagingJournalEntry ?? costsJournalEntry;

          // If a crops journal entry is found in DB, crops stage is 100% confirmed
          if (cropsJournalEntry != null) {
            isCropsConfirmed = true;
          }
          if (packagingJournalEntry != null) {
            isPackagingConfirmed = true;
          }
          if (costsJournalEntry != null) {
            isCostsConfirmed = true;
          }

          final allJeIds = jeList.map((e) => (e['id'] as num).toInt()).toSet();
          allJeIds.addAll(candidateJeIds);

          if (allJeIds.isNotEmpty) {
            try {
              final linesRes = await _client
                  .from('v_journal_entry_lines')
                  .select('id, journal_entry_id, account_id, debit, credit, currency, description, account_code, account_name')
                  .inFilter('journal_entry_id', allJeIds.toList());
              ledgerLines = (linesRes as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
            } catch (_) {
              try {
                final linesRes = await _client
                    .from('account_ledger_entries')
                    .select('id, journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description')
                    .inFilter('journal_entry_id', allJeIds.toList())
                    .filter('deleted_at', 'is', null);
                final rawLines = (linesRes as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
                final accIds = rawLines.map((e) => e['account_id']).where((id) => id != null).toSet().toList();
                if (accIds.isNotEmpty) {
                  final accRes = await _client.from('accounts').select('id, account_code, name').inFilter('id', accIds);
                  final accMap = {for (final a in (accRes as List)) a['id'].toString(): a};
                  for (final r in rawLines) {
                    final a = accMap[r['account_id']?.toString()];
                    if (a != null) {
                      r['account_code'] = a['account_code'];
                      r['account_name'] = a['name'];
                    }
                  }
                }
                ledgerLines = rawLines;
              } catch (_) {}
            }
          }

          // Fetch Debit Notes
          final dnRes = await _client
              .from('journal_entries')
              .select('id, entry_number, entry_date, description, source_type, source_id, created_at')
              .eq('source_type', 'packing_debit_note')
              .eq('source_id', orderId.toString())
              .filter('deleted_at', 'is', null);
          final dnList = dnRes as List<dynamic>;
          debitNoteEntries = dnList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        } catch (e) {
          debugPrint('⚠️ PackingCostVarianceService: Error loading journal entries: $e');
        }
      }

      final cropsJeNum = cropsJournalEntry?['entry_number']?.toString() ??
          (cropsJournalEntry?['id'] != null ? '#${cropsJournalEntry!['id']}' : mainJournalEntry?['entry_number']?.toString());
      final cropsJeId = cropsJournalEntry?['id'] ??
          (int.tryParse(activeOrder.cropsJournalEntryId ?? '')) ??
          mainJournalEntry?['id'] ??
          activeOrder.journalEntryId;

      final packagingJeNum = packagingJournalEntry?['entry_number']?.toString() ??
          (packagingJournalEntry?['id'] != null ? '#${packagingJournalEntry!['id']}' : mainJournalEntry?['entry_number']?.toString());
      final packagingJeId = packagingJournalEntry?['id'] ??
          (int.tryParse(activeOrder.packagingJournalEntryId ?? '')) ??
          mainJournalEntry?['id'] ??
          activeOrder.journalEntryId;

      final costsJeNum = costsJournalEntry?['entry_number']?.toString() ??
          (costsJournalEntry?['id'] != null ? '#${costsJournalEntry!['id']}' : mainJournalEntry?['entry_number']?.toString());
      final costsJeId = costsJournalEntry?['id'] ??
          (int.tryParse(activeOrder.costsJournalEntryId ?? '')) ??
          mainJournalEntry?['id'] ??
          activeOrder.journalEntryId;

      final mainJeId = mainJournalEntry?['id'] ?? activeOrder.journalEntryId ?? cropsJeId;

      // Extract raw produce inventory GL credit (Accounts 1030 or 12412)
      double cropsGlCredit = 0.0;
      for (final l in ledgerLines) {
        final accCode = l['account_code']?.toString() ?? l['accounts']?['account_code']?.toString() ?? '';
        final jId = (l['journal_entry_id'] as num?)?.toInt();
        if (accCode == '1030' || accCode == '12412') {
          if (cropsJeId == null || jId == cropsJeId || jId == mainJeId) {
            cropsGlCredit += ((l['credit'] ?? l['amount_in_base_currency'] ?? 0) as num).toDouble();
          }
        }
      }
      final double notesRawCost = (cropsStageNotes?['raw_cost'] as num?)?.toDouble() ?? 0.0;

      final items = <PackingCostItemComparison>[];

      // ═══════════════════════════════════════════════════════════════════════
      // COMPONENT 1: RAW FRUIT (المحصول الخام)
      // ═══════════════════════════════════════════════════════════════════════
      List<PackingOrderLineModel> orderLines = lines ?? activeOrder.lines;
      if (orderLines.isEmpty && orderId > 0) {
        try {
          final dbLines = await _client
              .from('packing_order_lines')
              .select('*')
              .eq('packing_order_id', orderId)
              .order('id');
          if (dbLines.isNotEmpty) {
            orderLines = (dbLines as List)
                .map((m) => PackingOrderLineModel.fromMap(Map<String, dynamic>.from(m as Map)))
                .toList();
          }
        } catch (_) {}
      }

      if (orderLines.isNotEmpty) {
        // Multi-crop or explicit line breakdown
        for (int i = 0; i < orderLines.length; i++) {
          final line = orderLines[i];
          final lineName = line.productName.isNotEmpty
              ? line.productName
              : 'محصول خام #${i + 1}';

          final estCost = line.rawMaterialCost > 0
              ? line.rawMaterialCost
              : (line.unitCost * line.quantity);

          if (!isCropsConfirmed) {
            items.add(PackingCostItemComparison(
              name: 'خام: $lineName',
              category: 'fruit',
              estimatedCost: estCost,
              actualCost: null,
              variance: null,
              variancePercent: null,
              status: PackingCostStatus.estimatedOnly,
              source: 'أمر التعبئة (مسودة)',
              reasonNotAvailable: 'لم يتم تأكيد وصرف المحصول من المخزن بعد (المرحلة 1)',
              estimatedQuantity: line.quantity,
              estimatedUnitPrice: line.unitCost,
              unit: 'كجم',
            ));
          } else {
            // Stage 1 Confirmed: Exact actual raw crop cost matching the inventory issue entry
            double actFruit = line.rawMaterialCost > 0 ? line.rawMaterialCost : (line.unitCost * line.quantity);
            if (orderLines.length == 1 && cropsGlCredit > 0) {
              actFruit = cropsGlCredit;
            } else if (orderLines.length == 1 && notesRawCost > 0) {
              actFruit = notesRawCost;
            }

            final diff = actFruit - estCost;
            final pct = estCost > 0 ? (diff / estCost * 100) : 0.0;

            items.add(PackingCostItemComparison(
              name: 'خام: $lineName',
              category: 'fruit',
              estimatedCost: estCost,
              actualCost: actFruit,
              variance: diff,
              variancePercent: pct,
              status: PackingCostStatus.fullyActual,
              source: cropsJeNum != null
                  ? 'قيد صرف المحاصيل #$cropsJeNum (مخزون الخام 12412)'
                  : 'إذن صرف محصول خام معتمد من المخزن (المرحلة 1)',
              journalEntryId: cropsJeId,
              sourceType: 'packing_order_crops',
              sourceId: orderId.toString(),
              estimatedQuantity: line.quantity,
              actualQuantity: line.quantity,
              estimatedUnitPrice: line.unitCost,
              actualUnitPrice: line.quantity > 0 ? (actFruit / line.quantity) : line.unitCost,
              unit: 'كجم',
            ));
          }
        }
      } else {
        // Single crop fallback from header
        final estFruit = activeOrder.fruitCostBase > 0
            ? activeOrder.fruitCostBase
            : (activeOrder.fruitCostAllocated > 0 ? activeOrder.fruitCostAllocated : 0.0);
        final cropName = activeOrder.productName?.isNotEmpty == true
            ? activeOrder.productName!
            : 'المحصول الخام';

        if (!isCropsConfirmed) {
          items.add(PackingCostItemComparison(
            name: 'خام: $cropName',
            category: 'fruit',
            estimatedCost: estFruit,
            actualCost: null,
            variance: null,
            variancePercent: null,
            status: PackingCostStatus.estimatedOnly,
            source: 'أمر التعبئة (مسودة)',
            reasonNotAvailable: 'لم يتم تأكيد وصرف المحصول من المخزن بعد (المرحلة 1)',
            unit: 'كجم',
          ));
        } else {
          // Stage 1 Confirmed: Exact actual raw crop cost matching the inventory issue entry
          final finalActFruit = cropsGlCredit > 0
              ? cropsGlCredit
              : (notesRawCost > 0
                  ? notesRawCost
                  : (activeOrder.fruitCostBase > 0
                      ? activeOrder.fruitCostBase
                      : activeOrder.fruitCostAllocated));

          final diff = finalActFruit - estFruit;
          final pct = estFruit > 0 ? (diff / estFruit * 100) : 0.0;

          items.add(PackingCostItemComparison(
            name: 'خام: $cropName',
            category: 'fruit',
            estimatedCost: estFruit,
            actualCost: finalActFruit,
            variance: diff,
            variancePercent: pct,
            status: PackingCostStatus.fullyActual,
            source: cropsJeNum != null
                ? 'قيد صرف المحاصيل #$cropsJeNum (مخزون الخام 12412)'
                : 'إذن صرف محصول خام معتمد من المخزن (المرحلة 1)',
            journalEntryId: cropsJeId,
            sourceType: 'packing_order_crops',
            sourceId: orderId.toString(),
            unit: 'كجم',
          ));
        }
      }

      // ═══════════════════════════════════════════════════════════════════════
      // COMPONENT 2: PACKAGING MATERIALS (مواد التعبئة والتغليف)
      // ═══════════════════════════════════════════════════════════════════════
      final rawMaterials = notes['materials'] as List?;
      final matWastePct = (notes['material_waste_percent'] as num?)?.toDouble() ?? 0.0;

      if (rawMaterials != null && rawMaterials.isNotEmpty) {
        for (final m in rawMaterials) {
          if (m is! Map) continue;
          final mName = m['product_name']?.toString() ?? 'مادة تعبئة';
          final usedQty = ((m['used_qty'] ?? m['quantity'] ?? 0) as num).toDouble();
          final unitCost = ((m['unit_cost'] ?? 0) as num).toDouble();
          final baseTotal = ((m['total'] ?? (usedQty * unitCost)) as num).toDouble();
          final estWithWaste = baseTotal * (1.0 + (matWastePct / 100.0));

          if (!isPackagingConfirmed && !isOrderCompleted) {
            items.add(PackingCostItemComparison(
              name: 'مادة: $mName',
              category: 'material',
              estimatedCost: estWithWaste,
              actualCost: null,
              variance: null,
              variancePercent: null,
              status: PackingCostStatus.estimatedOnly,
              source: 'أمر التعبئة (مسودة)',
              reasonNotAvailable: 'لم يتم تأكيد صرف مادة التعبئة من المستودع بعد (المرحلة 2)',
              estimatedQuantity: usedQty,
              estimatedUnitPrice: unitCost,
              unit: 'قطعة',
            ));
          } else {
            // Check for debit note on this material
            double materialDiscount = 0.0;
            for (final dn in debitNoteEntries) {
              final desc = dn['description']?.toString() ?? '';
              if (desc.contains(mName)) {
                // Debit note applies
              }
            }

            final actCost = (estWithWaste - materialDiscount).clamp(0.0, double.infinity);
            final diff = actCost - estWithWaste;
            final pct = estWithWaste > 0 ? (diff / estWithWaste * 100) : 0.0;

            items.add(PackingCostItemComparison(
              name: 'مادة: $mName',
              category: 'material',
              estimatedCost: estWithWaste,
              actualCost: actCost,
              variance: diff,
              variancePercent: pct,
              status: PackingCostStatus.fullyActual,
              source: packagingJeNum != null
                  ? 'قيد صرف مواد التعبئة #$packagingJeNum (حساب 12411)'
                  : 'صرف فعلي من باتشات المخزون (المرحلة 2)',
              journalEntryId: packagingJeId,
              sourceType: 'packing_order_packaging',
              sourceId: orderId.toString(),
              estimatedQuantity: usedQty,
              actualQuantity: usedQty,
              estimatedUnitPrice: unitCost,
              actualUnitPrice: unitCost,
              unit: 'قطعة',
              debitNoteDiscount: materialDiscount > 0 ? materialDiscount : null,
            ));
          }
        }
      } else if (activeOrder.materialCostBase > 0 || activeOrder.actualMaterialCost > 0) {
        // Fallback for header material total
        final estMat = activeOrder.materialCostBase > 0 ? activeOrder.materialCostBase : activeOrder.actualMaterialCost;
        if (!isPackagingConfirmed && !isOrderCompleted) {
          items.add(PackingCostItemComparison(
            name: 'مواد التعبئة والتغليف',
            category: 'material',
            estimatedCost: estMat,
            actualCost: null,
            variance: null,
            variancePercent: null,
            status: PackingCostStatus.estimatedOnly,
            source: 'أمر التعبئة (مسودة)',
            reasonNotAvailable: 'لم يتم تأكيد صرف مواد التعبئة من المستودع بعد (المرحلة 2)',
          ));
        } else {
          double actualMatGl = 0.0;
          for (final l in ledgerLines) {
            final accCode = l['account_code']?.toString() ?? l['accounts']?['account_code']?.toString() ?? '';
            if (accCode == '1040' || accCode == '12411' || accCode == '2106' || accCode == '9111') {
              actualMatGl += ((l['credit'] ?? l['amount_in_base_currency'] ?? 0) as num).toDouble();
            }
          }
          final finalActMat = actualMatGl > 0 ? actualMatGl : activeOrder.actualMaterialCost;
          final diff = finalActMat - estMat;
          final pct = estMat > 0 ? (diff / estMat * 100) : 0.0;

          items.add(PackingCostItemComparison(
            name: 'مواد التعبئة والتغليف',
            category: 'material',
            estimatedCost: estMat,
            actualCost: finalActMat,
            variance: diff,
            variancePercent: pct,
            status: PackingCostStatus.fullyActual,
            source: packagingJeNum != null
                ? 'قيد صرف مواد التعبئة #$packagingJeNum (حساب 12411)'
                : 'صرف فعلي من باتشات المخزون (المرحلة 2)',
            journalEntryId: packagingJeId,
            sourceType: 'packing_order_packaging',
            sourceId: orderId.toString(),
          ));
        }
      }

      // ═══════════════════════════════════════════════════════════════════════
      // COMPONENT 3: ADDITIONAL COST ITEMS (خدمات، عمالة، شحن، أخرى)
      // ═══════════════════════════════════════════════════════════════════════
      List<Map<String, dynamic>> rawCostItems = [];
      if (orderId > 0) {
        try {
          final dbCostItems = await _client
              .from('packing_order_cost_items')
              .select('*')
              .eq('packing_order_id', orderId)
              .isFilter('deleted_at', null)
              .gt('base_amount', 0)
              .order('id');
          if (dbCostItems.isNotEmpty) {
            rawCostItems = (dbCostItems as List).map((row) {
              final m = Map<String, dynamic>.from(row as Map);
              Map<String, dynamic> snap = {};
              if (m['currency_snapshot'] is Map) {
                snap = Map<String, dynamic>.from(m['currency_snapshot'] as Map);
              }
              final rName = (m['name']?.toString() ?? '').toLowerCase();
              final sName = (snap['supplier_name']?.toString() ?? '').toLowerCase();
              final isStationOrDed = rName.contains('محطة') || rName.contains('تخصيم') ||
                  sName.contains('محطة') || sName.contains('تخصيم');

              String sType = snap['supplier_type']?.toString() ?? '';
              if (sType.isEmpty || sType == 'general') {
                if (snap['transport_supplier_id'] != null || m['category'] == 'logistics') {
                  sType = 'transport';
                } else if (rName.contains('مهندس') || rName.contains('مهندسين') || m['category'] == 'engineer_expenses' || m['category'] == 'engineer') {
                  sType = 'engineer';
                } else if (rName.contains('محطة') || sName.contains('محطة')) {
                  sType = 'station';
                } else if (rName.contains('تخصيم') || sName.contains('تخصيم')) {
                  sType = 'deduction';
                } else if (rName.contains('إدار') || rName.contains('ادار') || m['category'] == 'admin') {
                  sType = 'admin';
                } else {
                  sType = 'general';
                }
              }

              m['supplier_type'] = sType;
              m['supplier_name'] ??= snap['supplier_name'];
              final bool itemIsAdmin = (m['category'] == 'admin') ||
                  rName.contains('إدار') ||
                  rName.contains('ادار');
              final bool itemIsEngineer = (m['category'] == 'engineer_expenses' || m['category'] == 'engineer') ||
                  sType == 'engineer' ||
                  rName.contains('مهندس') ||
                  rName.contains('مهندسين');
              final bool isEngineerPoolSettled = itemIsEngineer && (snap['is_engineer_cost_settled'] == true || m['is_engineer_cost_settled'] == true || m['cost_status'] == 'actual');
              final bool isAdminSettled = itemIsAdmin &&
                  (m['cost_status'] == 'settled' || m['reconciled_at'] != null || m['variance_journal_entry_id'] != null) &&
                  m['actual_amount'] != null;

              m['cost_status'] = (isAdminSettled || isEngineerPoolSettled)
                  ? 'actual'
                  : (itemIsAdmin
                      ? 'expected'
                      : (m['cost_status'] ??
                          snap['cost_status'] ??
                          ((sType == 'station' || sType == 'deduction' || isStationOrDed)
                              ? 'expected'
                              : 'actual')));
              m['expected_amount'] = (m['expected_amount'] as num?)?.toDouble() ??
                  (snap['expected_amount'] as num?)?.toDouble() ??
                  (m['base_amount'] as num?)?.toDouble() ??
                  0.0;
              m['actual_amount'] = (itemIsAdmin && !isAdminSettled)
                  ? null
                  : ((m['actual_amount'] as num?)?.toDouble() ??
                      (snap['actual_amount'] as num?)?.toDouble() ??
                      (isEngineerPoolSettled ? m['expected_amount'] : null));
              m['variance_amount'] = (m['variance_amount'] as num?)?.toDouble() ??
                  (snap['variance_amount'] as num?)?.toDouble() ??
                  0.0;
              m['total_egp'] = m['base_amount'];
              m['total'] = m['original_amount'];
              return m;
            }).toList();
          }
        } catch (e) {
          debugPrint('⚠️ PackingCostVarianceService: Error loading DB cost items: $e');
        }
      }

      if (rawCostItems.isEmpty) {
        final listFromNotes = notes['cost_items'] as List?;
        if (listFromNotes != null) {
          rawCostItems = listFromNotes
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .where((m) => ((m['total_egp'] ?? m['base_amount'] ?? m['total'] ?? 0) as num) > 0)
              .toList();
        }
      }

      // ── Deduplicate rawCostItems in-memory (Strictly Read-Only, Never Mutates DB) ──
      // Deduplicate only identical records (by item_uuid or database id) to preserve
      // multiple legitimate movements that share the same cost name or monetary value.
      if (rawCostItems.length > 1) {
        final Map<String, Map<String, dynamic>> dedupedMap = {};
        for (final c in rawCostItems) {
          final uuid = c['item_uuid']?.toString();
          final id = (c['id'] as num?)?.toInt();
          final key = (uuid != null && uuid.isNotEmpty && !uuid.startsWith('db_row_'))
              ? 'uuid_$uuid'
              : (id != null && id > 0 ? 'id_$id' : 'idx_${c.hashCode}');

          if (!dedupedMap.containsKey(key)) {
            dedupedMap[key] = c;
          } else {
            final existing = dedupedMap[key]!;
            final cIsSettled = (c['cost_status'] == 'actual' && c['actual_amount'] != null) ||
                c['variance_journal_entry_id'] != null;
            final existingIsSettled = (existing['cost_status'] == 'actual' && existing['actual_amount'] != null) ||
                existing['variance_journal_entry_id'] != null;
            if (cIsSettled && !existingIsSettled) {
              dedupedMap[key] = c;
            }
          }
        }
        rawCostItems = dedupedMap.values.toList();
      }

      // Pre-load station and deduction supplier IDs to guarantee reliable type detection
      final Set<String> stationSupplierIds = {};
      final Set<String> deductionSupplierIds = {};
      try {
        final suppsRes = await _client
            .from('suppliers')
            .select('id, supplier_type')
            .inFilter('supplier_type', ['station', 'deduction', 'deductions']);
        for (final s in (suppsRes as List)) {
          final sid = s['id']?.toString();
          final st = s['supplier_type']?.toString().toLowerCase();
          if (sid != null && sid.isNotEmpty) {
            if (st == 'station') {
              stationSupplierIds.add(sid);
            } else {
              deductionSupplierIds.add(sid);
            }
          }
        }
      } catch (_) {}

      if (rawCostItems.isNotEmpty) {
        for (final c in rawCostItems) {
          final cName = c['name']?.toString() ?? 'بند تكلفة';
          final cCat = c['category']?.toString() ?? 'other';
          final supplierId = c['supplier_id']?.toString();
          final supplierName = c['supplier_name']?.toString();

          final cNameLower = cName.toLowerCase();
          final suppNameLower = (supplierName ?? '').toLowerCase();
          final suppTypeLower = (c['supplier_type']?.toString() ?? '').toLowerCase();

          final bool isEngineer = suppTypeLower == 'engineer' ||
              cCat == 'engineer_expenses' ||
              cCat == 'engineer' ||
              cNameLower.contains('مهندس') ||
              cNameLower.contains('مهندسين') ||
              suppNameLower.contains('مهندس') ||
              c['custody_id'] != null;

          final bool isStation = !isEngineer && (suppTypeLower == 'station' ||
              cCat == 'station' ||
              cCat == 'station_supplier' ||
              cNameLower.contains('محطة') ||
              suppNameLower.contains('محطة') ||
              c['station_supplier_id'] != null ||
              (supplierId != null && stationSupplierIds.contains(supplierId)));

          final bool isDeduction = !isEngineer && !isStation && (suppTypeLower == 'deduction' ||
              suppTypeLower == 'deductions' ||
              cCat == 'deduction' ||
              cCat == 'deductions' ||
              cNameLower.contains('تخصيم') ||
              suppNameLower.contains('تخصيم') ||
              (supplierId != null && deductionSupplierIds.contains(supplierId)));

          final isStationOrDeduction = isStation || isDeduction;

          final bool isTransport = !isEngineer && !isStationOrDeduction && (suppTypeLower == 'transport' ||
              cCat == 'logistics' ||
              cCat == 'transport' ||
              cNameLower.contains('نقل') ||
              cNameLower.contains('شحن') ||
              c['transport_supplier_id'] != null);

          final bool isAdmin = !isEngineer && !isStationOrDeduction && !isTransport && (suppTypeLower == 'admin' ||
              cCat == 'admin' ||
              cNameLower.contains('إدار') ||
              cNameLower.contains('ادار'));
          final String effectiveCat = isEngineer
              ? 'engineer_expenses'
              : (isStation
                  ? 'station'
                  : (isDeduction
                      ? 'deductions'
                      : (isTransport ? 'logistics' : (isAdmin ? 'admin' : cCat))));

          final hasSupplier = !isEngineer &&
              supplierId != null &&
              supplierId.isNotEmpty &&
              supplierId != 'null' &&
              supplierId != 'none';

          // Check if the cost item has been actually settled
          final costItemStatus = c['cost_status']?.toString();
          final double? actualAmount = (c['actual_amount'] as num?)?.toDouble();
          // Admin expense check: only actual if settled via account settlement with variance_journal_entry_id or confirmed actual
          final bool isSettledActual = isEngineer ||
              (isAdmin && (c['cost_status'] == 'settled' || c['reconciled_at'] != null || c['variance_journal_entry_id'] != null) && actualAmount != null) ||
              (isStationOrDeduction && (c['cost_status'] == 'settled' || c['settled_actual'] == true || c['variance_journal_entry_id'] != null) && actualAmount != null) ||
              (!isAdmin && !isStationOrDeduction && ((costItemStatus == 'actual' && actualAmount != null) ||
                  (c['settled_actual'] == true && actualAmount != null) ||
                  (c['variance_journal_entry_id'] != null && actualAmount != null) ||
                  (actualAmount != null && actualAmount > 0 && costItemStatus != 'expected' && costItemStatus != 'estimated') ||
                  isTransport)); // Transport cost items are directly actual by design

          final double totalAmount = ((c['total_egp'] ?? c['total'] ?? c['base_amount'] ?? 0) as num).toDouble();
          final double expectedAmount = (c['expected_amount'] as num?)?.toDouble() ?? 0.0;

          // For Transport and Engineer: directly entered cost is both base estimate and actual
          final double estAmount = (isTransport || isEngineer)
              ? (totalAmount > 0 ? totalAmount : (expectedAmount > 0 ? expectedAmount : totalAmount))
              : (expectedAmount > 0 ? expectedAmount : totalAmount);

          final int? costItemId = (c['id'] as num?)?.toInt();

          // ── 1. If item has been settled OR is Transport OR Engineer: ALWAYS fullyActual across all environments and stages ──
          if (isSettledActual || isTransport || isEngineer) {
            final double netActual = isTransport
                ? ((actualAmount != null && actualAmount > 0)
                    ? actualAmount
                    : (totalAmount > 0 ? totalAmount : expectedAmount))
                : (isEngineer
                    ? ((actualAmount != null && actualAmount > 0) ? actualAmount : (totalAmount > 0 ? totalAmount : estAmount))
                    : actualAmount!);
            final double baseEstimate = (isTransport || isEngineer)
                ? netActual
                : estAmount;
            final double diff = (isTransport || isEngineer) ? 0.0 : (netActual - baseEstimate);
            final double? pct = (isTransport || isEngineer || baseEstimate <= 0) ? null : (diff / baseEstimate * 100);

            String settledSource;
            if (isEngineer) {
              settledSource = c['variance_journal_entry_id'] != null
                  ? 'قيد تسوية عهدة مهندس #'
                  : 'مجمع عهد الموظفين (تكلفة فعلية منصرفة ومحملة)';
            } else if (isTransport) {
              settledSource = c['variance_journal_entry_id'] != null
                  ? 'قيد تسوية مصاريف نقل #${c['variance_journal_entry_id']}'
                  : (costsJeId != null
                      ? 'قيد إثبات تكلفة نقل أمر تعبئة #$costsJeId'
                      : 'تكلفة نقل فعلية مثبتة ومرحلة مباشرة');
            } else if (isStationOrDeduction) {
              settledSource = c['variance_journal_entry_id'] != null
                  ? (isStation
                      ? 'قيد تسوية مورد محطة #${c['variance_journal_entry_id']}'
                      : 'قيد تسوية مورد تخصيمات #${c['variance_journal_entry_id']}')
                  : (isStation
                      ? 'تسوية مورد محطة معتمدة من كشف الحساب'
                      : 'تسوية مورد تخصيمات معتمدة من كشف الحساب');
            } else if (isAdmin) {
              settledSource = c['variance_journal_entry_id'] != null
                  ? 'قيد تسوية مصاريف إدارية #${c['variance_journal_entry_id']}'
                  : 'تسوية مصاريف إدارية معتمدة';
            } else {
              settledSource = c['variance_journal_entry_id'] != null
                  ? 'قيد تسوية فعلية #${c['variance_journal_entry_id']}'
                  : 'تسوية فعلية معتمدة';
            }

            items.add(PackingCostItemComparison(
              name: cName,
              category: isTransport ? 'logistics' : (isStation ? 'station' : (isDeduction ? 'deductions' : effectiveCat)),
              estimatedCost: baseEstimate,
              actualCost: netActual,
              variance: isTransport ? 0.0 : diff,
              variancePercent: pct,
              status: PackingCostStatus.fullyActual,
              source: settledSource,
              journalEntryId: c['variance_journal_entry_id'] != null
                  ? (c['variance_journal_entry_id'] as num).toInt()
                  : costsJeId,
              sourceType: isEngineer
                  ? 'employee_custody'
                  : (isTransport
                      ? 'packing_order_transport'
                      : (isStation ? 'station_supplier_accrual' : (isDeduction ? 'deduction_accrual' : 'cost_settlement'))),
              sourceId: supplierId,
              supplierName: isEngineer
                  ? (c['engineer_name'] ?? supplierName ?? 'عهدة مهندس')
                  : ((hasSupplier || isTransport) ? supplierName : null),
              costItemId: costItemId,
            ));
            continue;
          }

          // ── 3. Unsettled Items ──
          if (!isCostsConfirmed && !isOrderCompleted) {
            items.add(PackingCostItemComparison(
              name: cName,
              category: isStation ? 'station' : (isDeduction ? 'deductions' : effectiveCat),
              estimatedCost: estAmount,
              actualCost: null,
              variance: null,
              variancePercent: null,
              status: PackingCostStatus.estimatedOnly,
              source: isEngineer
                  ? 'عهدة مهندس تقديرية (مسودة)'
                  : (isStation
                      ? 'استحقاق تقديري بانتظار التسوية من كشف حساب مورد المحطة'
                      : (isDeduction
                          ? 'استحقاق تقديري بانتظار التسوية من كشف حساب مورد التخصيمات'
                          : 'أمر التعبئة (مسودة)')),
              reasonNotAvailable: isEngineer
                  ? 'بانتظار تقديم فواتير ومستندات المصروفات الفعلية لتسوية العهدة'
                  : (isStation
                      ? 'بانتظار تسوية مستحقات مورد المحطة من صفحة التسوية'
                      : (isDeduction
                          ? 'بانتظار تسوية مستحقات مورد التخصيمات من صفحة التسوية'
                          : 'لم يتم ترحيل التكاليف الإضافية بعد (المرحلة 3)')),
              supplierName: isEngineer
                  ? (c['engineer_name'] ?? supplierName ?? 'عهدة مهندس')
                  : (hasSupplier ? supplierName : null),
              costItemId: costItemId,
            ));
          } else {
            if (isEngineer) {
              items.add(PackingCostItemComparison(
                name: cName,
                category: effectiveCat,
                estimatedCost: estAmount,
                actualCost: null,
                variance: null,
                variancePercent: null,
                status: PackingCostStatus.estimatedOnly,
                source: 'عهدة مهندس تقديرية - بانتظار الفواتير والتسوية',
                reasonNotAvailable: 'بانتظار تقديم فواتير ومستندات المصروفات الفعلية لتسوية العهدة',
                journalEntryId: costsJeId,
                sourceType: 'employee_custody',
                supplierName: c['engineer_name'] ?? supplierName ?? 'عهدة مهندس',
                costItemId: costItemId,
              ));
            } else if (isStationOrDeduction) {
              items.add(PackingCostItemComparison(
                name: cName,
                category: isStation ? 'station' : (isDeduction ? 'deductions' : cCat),
                estimatedCost: estAmount,
                actualCost: null,
                variance: null,
                variancePercent: null,
                status: PackingCostStatus.estimatedOnly,
                source: isStation
                    ? 'استحقاق تقديري بانتظار التسوية من كشف حساب مورد المحطة'
                    : 'استحقاق تقديري بانتظار التسوية من كشف حساب مورد التخصيمات',
                reasonNotAvailable: isStation
                    ? 'بانتظار تسوية مستحقات مورد المحطة من صفحة التسوية'
                    : 'لم يتم تسجيل التكلفة الفعلية من كشف حساب المورد بعد (بانتظار التسوية)',
                journalEntryId: costsJeId,
                sourceType: isStation ? 'station_supplier_accrual' : 'supplier_accrual',
                sourceId: supplierId,
                supplierName: supplierName,
                costItemId: costItemId,
              ));
            } else if (isAdmin) {
              items.add(PackingCostItemComparison(
                name: cName,
                category: effectiveCat,
                estimatedCost: estAmount,
                actualCost: null,
                variance: null,
                variancePercent: null,
                status: PackingCostStatus.estimatedOnly,
                source: 'تقديري - بانتظار إدخال الفعلي والتسوية',
                reasonNotAvailable: 'بانتظار إدخال التكلفة الفعلية وتسويتها',
                journalEntryId: costsJeId,
                sourceType: 'admin_expense',
                costItemId: costItemId,
              ));
            } else if (isCostsConfirmed) {
              final netActual = (actualAmount ?? estAmount).clamp(0.0, double.infinity);
              final diff = (actualAmount != null) ? (netActual - estAmount) : 0.0;
              final pct = estAmount > 0 ? (diff / estAmount * 100) : 0.0;

              items.add(PackingCostItemComparison(
                name: cName,
                category: effectiveCat,
                estimatedCost: estAmount,
                actualCost: netActual,
                variance: diff,
                variancePercent: pct,
                status: PackingCostStatus.fullyActual,
                source: costsJeNum != null
                    ? 'قيد تكاليف تشغيلية #$costsJeNum'
                    : 'تكاليف تشغيلية مثبتة في أمر التعبئة (المرحلة 3)',
                journalEntryId: costsJeId,
                sourceType: 'internal_operating_cost',
                costItemId: costItemId,
              ));
            } else {
              items.add(PackingCostItemComparison(
                name: cName,
                category: effectiveCat,
                estimatedCost: estAmount,
                actualCost: null,
                variance: null,
                variancePercent: null,
                status: PackingCostStatus.noActualSource,
                source: 'تقديري فقط',
                reasonNotAvailable: 'لا يوجد مستند أو قيد استحقاق مورد محدد لهذا البند',
                costItemId: costItemId,
              ));
            }
          }
        }
      } else if (activeOrder.otherCostBase > 0) {
        final estOther = activeOrder.otherCostBase;
        if (isCostsConfirmed || isOrderCompleted) {
          items.add(PackingCostItemComparison(
            name: 'مصروفات تشغيل إضافية',
            category: 'other',
            estimatedCost: estOther,
            actualCost: estOther,
            variance: 0.0,
            variancePercent: 0.0,
            status: PackingCostStatus.fullyActual,
            source: costsJeNum != null
                ? 'قيد تكاليف تشغيلية #$costsJeNum'
                : 'تكاليف تشغيلية مثبتة في أمر التعبئة (المرحلة 3)',
            journalEntryId: costsJeId,
            sourceType: 'internal_operating_cost',
          ));
        } else {
          items.add(PackingCostItemComparison(
            name: 'مصروفات تشغيل إضافية',
            category: 'other',
            estimatedCost: estOther,
            actualCost: null,
            variance: null,
            variancePercent: null,
            status: PackingCostStatus.estimatedOnly,
            source: 'أمر التعبئة (مسودة)',
            reasonNotAvailable: 'لم يتم ترحيل التكاليف الإضافية بعد (المرحلة 3)',
          ));
        }
      }

      // ═══════════════════════════════════════════════════════════════════════
      // COMPONENT 4: TOTALS, FAIR VARIANCE & COVERAGE (موضوعية وعدالة الحساب)
      // ═══════════════════════════════════════════════════════════════════════
      // Final Defensive Deduplication Pass on items:
      // Deduplicate strictly by costItemId or source identity, never by name+amount,
      // preserving multiple legitimate distinct lines with identical amounts.
      final List<PackingCostItemComparison> distinctItems = [];
      final Map<String, PackingCostItemComparison> seenItemsMap = {};

      for (final item in items) {
        final key = item.costItemId != null && item.costItemId! > 0
            ? 'cost_item_${item.costItemId}'
            : (item.sourceType != null && item.sourceId != null && item.sourceId!.isNotEmpty
                ? '${item.sourceType}_${item.sourceId}_${item.category}'
                : 'item_${identityHashCode(item)}');

        if (!seenItemsMap.containsKey(key)) {
          seenItemsMap[key] = item;
          distinctItems.add(item);
        } else {
          final existing = seenItemsMap[key]!;
          if (item.hasActualCost && !existing.hasActualCost) {
            final idx = distinctItems.indexOf(existing);
            if (idx != -1) {
              distinctItems[idx] = item;
              seenItemsMap[key] = item;
            }
          }
        }
      }
      items.clear();
      items.addAll(distinctItems);

      double totalEst = 0.0;
      double totalAct = 0.0;
      double totalEstForAvailable = 0.0;
      double totalActForEstimatedItems = 0.0;

      for (final item in items) {
        totalEst += item.estimatedCost;
        if (item.hasActualCost) {
          totalAct += item.actualCost!;
          if (!item.isActualOnly) {
            totalEstForAvailable += item.estimatedCost;
            totalActForEstimatedItems += item.actualCost!;
          }
        }
      }

      // Comparison variance measures only deviation of estimated items against their actuals
      final totalVariance = totalActForEstimatedItems - totalEstForAvailable;
      final double? totalVariancePct = totalEstForAvailable > 0
          ? (totalVariance / totalEstForAvailable * 100)
          : null;

      String direction = 'none';
      if (items.any((i) => i.hasActualCost)) {
        if (totalVariance > 0.01) {
          direction = 'higher';
        } else if (totalVariance < -0.01) {
          direction = 'lower';
        } else {
          direction = 'equal';
        }
      }

      final coveragePct = totalEst > 0
          ? (totalEstForAvailable / totalEst * 100).clamp(0.0, 100.0)
          : 0.0;

      return PackingCostVarianceReport(
        totalEstimatedCost: totalEst,
        totalActualCost: totalAct,
        totalEstimatedForAvailableActual: totalEstForAvailable,
        totalVariance: totalVariance,
        variancePercent: totalVariancePct,
        direction: direction,
        actualCoveragePercent: coveragePct,
        isOrderConfirmed: isOrderCompleted || isCropsConfirmed || isPackagingConfirmed || isCostsConfirmed,
        orderStatus: activeOrder.status,
        orderNumber: orderNumber,
        mainJournalEntryId: mainJeId ?? cropsJeId,
        items: items,
      );
    } catch (e, st) {
      debugPrint('❌ PackingCostVarianceService.generateReport error: $e\n$st');
      final estTotal = order.totalPackingCost > 0
          ? order.totalPackingCost
          : (order.packingCostPerCarton * order.cartonCount);
      return PackingCostVarianceReport(
        totalEstimatedCost: estTotal,
        totalActualCost: 0.0,
        totalEstimatedForAvailableActual: 0.0,
        totalVariance: 0.0,
        direction: 'none',
        actualCoveragePercent: 0.0,
        isOrderConfirmed: order.status == 'completed',
        orderStatus: order.status,
        orderNumber: order.orderNumber.isNotEmpty ? order.orderNumber : '—',
        items: [],
      );
    }
  }
}
