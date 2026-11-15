import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/data_change_event_bus.dart';
import '../models/cost_center.dart';
import 'currency_conversion_service.dart';

/// Automated synchronization service that ensures each product / inventory item
/// has a corresponding Cost Center record dynamically generated and maintained
/// in the database.
class ProductCostCenterSyncService {
  static final ProductCostCenterSyncService instance =
      ProductCostCenterSyncService._();
  ProductCostCenterSyncService._([SupabaseClient? client]) : _customClient = client;
  factory ProductCostCenterSyncService([SupabaseClient? client]) {
    if (client != null) return ProductCostCenterSyncService._(client);
    return instance;
  }

  final SupabaseClient? _customClient;
  SupabaseClient get _client => _customClient ?? Supabase.instance.client;

  /// Translates or formats the product's English operational line name
  String resolveEnglishName(String arabicName) {
    final lower = arabicName.toLowerCase();
    if (lower.contains('مانجو') ||
        lower.contains('مانجا') ||
        lower.contains('mango')) {
      return 'Mango Line';
    }
    if (lower.contains('فراولة') ||
        lower.contains('فراوله') ||
        lower.contains('strawberry')) {
      return 'Strawberry Line';
    }
    if (lower.contains('عنب') || lower.contains('grape')) {
      return 'Grapes Line';
    }
    if (lower.contains('برتقال') || lower.contains('orange')) {
      return 'Orange Line';
    }
    if (lower.contains('ليمون') || lower.contains('lemon')) {
      return 'Lemon Line';
    }
    if (lower.contains('يوسفي') || lower.contains('mandarin')) {
      return 'Mandarin Line';
    }
    if (lower.contains('رمان') || lower.contains('pomegranate')) {
      return 'Pomegranate Line';
    }
    if (lower.contains('موز') || lower.contains('banana')) {
      return 'Banana Line';
    }
    if (lower.contains('خوخ') || lower.contains('peach')) {
      return 'Peach Line';
    }
    if (lower.contains('مشمش') || lower.contains('apricot')) {
      return 'Apricot Line';
    }
    if (lower.contains('بلح') || lower.contains('تمر') || lower.contains('dates')) {
      return 'Dates Line';
    }
    if (lower.contains('تين') || lower.contains('fig')) {
      return 'Fig Line';
    }
    return '$arabicName Line';
  }

  /// Resolves the specific Cost Center entity for a given fruit type / crop,
  /// strictly enforcing the item's bound cost center ID set during fruit variety registration.
  Future<CostCenter> resolveCropCostCenter({
    required dynamic fruitTypeId,
    required String cropName,
    String season = '2026-2027',
  }) async {
    final canonCropName = CostCenter.canonicalCropName(cropName);
    final slug = CostCenterHelper.resolveCropSlug(canonCropName);

    // 1. Priority 1: Check fruit_types.cost_center_id explicitly bound during item setup/registration.
    // IMPORTANT: If the bound CC is closed/permanently-closed, follow its rollover_cost_center_id
    // to the currently active period, preventing stale-pointer routing after season closure.
    try {
      if (fruitTypeId != null && fruitTypeId.toString().isNotEmpty) {
        final ft = await _client
            .from('fruit_types')
            .select('id, code, name, cost_center_id')
            .eq('id', fruitTypeId)
            .maybeSingle();

        if (ft != null && ft['cost_center_id'] != null && ft['cost_center_id'].toString().trim().isNotEmpty) {
          final boundCcId = ft['cost_center_id'].toString().trim();
          final numericId = int.tryParse(boundCcId);

          // First try: the bound CC is still active and not closed
          Map<String, dynamic>? ccRes;
          try {
            final q = _client
                .from('cost_centers')
                .select('*, rollover_cost_center_id')
                .eq('is_active', true)
                .not('season_status', 'in', '(closed,permanently_closed)');
            ccRes = await (numericId != null
                ? q.or('code.eq.$boundCcId,id.eq.$numericId')
                : q.eq('code', boundCcId)).maybeSingle();
          } catch (_) {}

          // Second try: bound CC is closed — follow rollover_cost_center_id
          if (ccRes == null) {
            try {
              final closedCc = await _client
                  .from('cost_centers')
                  .select('rollover_cost_center_id')
                  .or(numericId != null ? 'code.eq.$boundCcId,id.eq.$numericId' : 'code.eq.$boundCcId')
                  .maybeSingle();
              final rolloverIdRaw = closedCc?['rollover_cost_center_id'];
              if (rolloverIdRaw != null) {
                ccRes = await _client
                    .from('cost_centers')
                    .select()
                    .eq('id', rolloverIdRaw)
                    .eq('is_active', true)
                    .not('season_status', 'in', '(closed,permanently_closed)')
                    .maybeSingle();
              }
            } catch (_) {}
          }

          if (ccRes != null) {
            // Auto-heal fruit_types.cost_center_id pointer to active period
            final resolvedCode = ccRes['code']?.toString() ?? ccRes['id']?.toString();
            if (resolvedCode != null && resolvedCode != boundCcId && fruitTypeId != null) {
              _client
                  .from('fruit_types')
                  .update({'cost_center_id': resolvedCode})
                  .eq('id', fruitTypeId)
                  .catchError((_) {});
            }
            return CostCenter.fromMap(Map<String, dynamic>.from(ccRes));
          }
        }
      }
    } catch (e) {
      debugPrint('ProductCostCenterSyncService: error querying fruit_types.cost_center_id by id: $e');
    }

    // 1b. Priority 1b: If fruitTypeId was null or not found, try looking up fruit_types by crop name.
    // Also follows rollover_cost_center_id if the bound CC is closed.
    try {
      if (cropName.isNotEmpty) {
        final ft = await _client
            .from('fruit_types')
            .select('id, code, name, cost_center_id')
            .not('cost_center_id', 'is', null)
            .or('name.eq.$cropName,name.ilike.%$canonCropName%')
            .limit(1)
            .maybeSingle();

        if (ft != null && ft['cost_center_id'] != null && ft['cost_center_id'].toString().trim().isNotEmpty) {
          final boundCcId = ft['cost_center_id'].toString().trim();
          final numericId = int.tryParse(boundCcId);

          // First try: bound CC still active and not closed
          Map<String, dynamic>? ccRes;
          try {
            final q = _client
                .from('cost_centers')
                .select('*, rollover_cost_center_id')
                .eq('is_active', true)
                .not('season_status', 'in', '(closed,permanently_closed)')
                .not('status', 'in', '(closed,permanently_closed)');
            ccRes = await (numericId != null
                ? q.or('code.eq.$boundCcId,id.eq.$numericId')
                : q.eq('code', boundCcId)).maybeSingle();
          } catch (_) {}

          // Second try: follow rollover pointer if closed
          if (ccRes == null) {
            try {
              final closedCc = await _client
                  .from('cost_centers')
                  .select('rollover_cost_center_id')
                  .or(numericId != null ? 'code.eq.$boundCcId,id.eq.$numericId' : 'code.eq.$boundCcId')
                  .maybeSingle();
              final rolloverIdRaw = closedCc?['rollover_cost_center_id'];
              if (rolloverIdRaw != null) {
                ccRes = await _client
                    .from('cost_centers')
                    .select()
                    .eq('id', rolloverIdRaw)
                    .eq('is_active', true)
                    .not('season_status', 'in', '(closed,permanently_closed)')
                    .not('status', 'in', '(closed,permanently_closed)')
                    .maybeSingle();
              }
            } catch (_) {}
          }

          if (ccRes != null) {
            // Auto-heal fruit_types.cost_center_id pointer
            final resolvedCode = ccRes['code']?.toString() ?? ccRes['id']?.toString();
            final matchedFtId = ft['id'];
            if (resolvedCode != null && resolvedCode != boundCcId && matchedFtId != null) {
              _client
                  .from('fruit_types')
                  .update({'cost_center_id': resolvedCode})
                  .eq('id', matchedFtId)
                  .catchError((_) {});
            }
            return CostCenter.fromMap(Map<String, dynamic>.from(ccRes));
          }
        }
      }
    } catch (e) {
      debugPrint('ProductCostCenterSyncService: error querying fruit_types.cost_center_id by name: $e');
    }

    // 2. Priority 2: Resolve canonical seasonal cost center for the crop variety
    // STRICT RULE: Only variety cost centers, and NEVER generic line-based centers (name_ar NOT LIKE 'خط %')
    try {
      // 2a: Prefer period-qualified active cost center (e.g. CC-MANGO-2026-2027-P2)
      final periodRes = await _client
          .from('cost_centers')
          .select()
          .eq('is_active', true)
          .eq('cost_center_type', 'variety')
          .eq('season_status', 'active')
          .not('status', 'in', '(closed,permanently_closed)')
          .not('name_ar', 'like', 'خط %')
          .or('crop_code.eq.$slug,code.ilike.CC-$slug-%-P%,name_ar.ilike.%$canonCropName%الفترة%')
          .order('season_number', ascending: false)
          .order('id', ascending: false)
          .limit(1)
          .maybeSingle();

      if (periodRes != null) {
        return CostCenter.fromMap(Map<String, dynamic>.from(periodRes));
      }

      // 2b: Standard active seasonal variety cost center
      final activeRes = await _client
          .from('cost_centers')
          .select()
          .eq('is_active', true)
          .eq('cost_center_type', 'variety')
          .eq('season_status', 'active')
          .not('status', 'in', '(closed,permanently_closed)')
          .not('name_ar', 'like', 'خط %')
          .or('crop_code.eq.$slug,code.eq.CC-$slug-$season,code.eq.CC-$slug,name_ar.eq.$canonCropName,name_ar.ilike.%$canonCropName%')
          .order('season_number', ascending: false)
          .order('id', ascending: false)
          .limit(1)
          .maybeSingle();

      if (activeRes != null) {
        return CostCenter.fromMap(Map<String, dynamic>.from(activeRes));
      }

      // 2c: Fallback search any active variety cost center for this crop (strictly filtering out closed ones!)
      final res = await _client
          .from('cost_centers')
          .select()
          .eq('is_active', true)
          .eq('cost_center_type', 'variety')
          .not('season_status', 'in', '(closed,permanently_closed)')
          .not('status', 'in', '(closed,permanently_closed)')
          .not('name_ar', 'like', 'خط %')
          .or('crop_code.eq.$slug,code.eq.CC-$slug-$season,code.eq.CC-$slug,name_ar.eq.$canonCropName,name_ar.ilike.%$canonCropName%')
          .order('season_number', ascending: false)
          .order('id', ascending: false)
          .limit(1)
          .maybeSingle();

      if (res != null) {
        return CostCenter.fromMap(Map<String, dynamic>.from(res));
      }
    } catch (e) {
      debugPrint('ProductCostCenterSyncService: error querying seasonal cost_centers: $e');
    }

    // 3. Priority 3: Fallback canonical seasonal cost center (NEVER line-based!)
    final baseCode = slug != 'CROP' ? slug : (fruitTypeId?.toString() ?? 'CROP');
    final ccCode = 'CC-$baseCode-$season';
    final nameWithSeason = '$canonCropName (موسم $season)';
    return CostCenter(
      id: ccCode,
      nameAr: nameWithSeason,
      nameEn: '${resolveEnglishName(canonCropName)} ($season)',
      type: CostCenterType.variety,
      color: CostCenterHelper.resolveColor(null, canonCropName),
      icon: CostCenterHelper.resolveIcon(null, canonCropName),
      code: ccCode,
      productId: fruitTypeId,
      cropName: canonCropName,
      cropCode: slug,
      season: season,
      seasonStatus: 'active',
      openingBalance: 0.0,
      currentBalance: 0.0,
      isActive: true,
    );
  }

  /// Disables automatic cost center generation per requirement.
  /// Cost centers are now managed manually through the Cost Centers page.
  Future<void> syncProductCostCenter({
    required dynamic productId,
    required String productCode,
    required String productNameAr,
    String? productNameEn,
    String? color,
    String? icon,
    bool isActive = true,
    String season = '2026-2027',
  }) async {
    // Automatic generation disabled. Cost centers are created explicitly and manually by accountants.
    debugPrint(
      'ProductCostCenterSyncService: Automatic cost center creation skipped for $productNameAr ($productCode).',
    );
  }

  /// Automatically records an explicit transaction entry into the cost center ledger
  /// (`cost_center_transactions`) directly mapped to the crop's cost center ID.
  Future<void> recordCropPurchaseTransaction({
    required String sourceId,
    dynamic fruitTypeId,
    String? cropName,
    String? supplierId,
    String? supplierName,
    required double quantity,
    required double unitPrice,
    required double totalCost,
    String currency = 'EGP',
    double exchangeRate = 1.0,
    DateTime? date,
    DateTime? purchaseDate,
    String? notes,
    String sourceType = 'crop_purchase',
  }) async {
    try {
      final effectiveDate = purchaseDate ?? date ?? DateTime.now();
      final effectiveCropName = (cropName != null && cropName.trim().isNotEmpty)
          ? cropName.trim()
          : 'محصول';

      final costCenter = await resolveCropCostCenter(
        fruitTypeId: fruitTypeId,
        cropName: effectiveCropName,
      );

      final dateStr = '${effectiveDate.year}-${effectiveDate.month.toString().padLeft(2, '0')}-${effectiveDate.day.toString().padLeft(2, '0')}';
      final actualExRate = (currency.toUpperCase() == 'EGP' || exchangeRate <= 0) ? 1.0 : exchangeRate;
      final totalInCurrency = totalCost > 0 ? totalCost : (quantity * unitPrice);
      final totalEgp = CurrencyConversionService.instance.toBase(totalInCurrency, currency, actualExRate);

      double effectiveQty = quantity;
      double effectiveUnitPrice = unitPrice;
      if (effectiveQty <= 0 && effectiveUnitPrice > 0 && totalInCurrency > 0) {
        effectiveQty = totalInCurrency / effectiveUnitPrice;
      } else if (effectiveQty > 0 && effectiveUnitPrice <= 0 && totalInCurrency > 0) {
        effectiveUnitPrice = totalInCurrency / effectiveQty;
      } else if (effectiveQty <= 0 && effectiveUnitPrice <= 0 && totalInCurrency > 0) {
        effectiveQty = 1.0;
        effectiveUnitPrice = totalInCurrency;
      }

      final row = {
        'cost_center_id': costCenter.code ?? costCenter.id,
        'cost_center_name': costCenter.displayTitle,
        'cost_center_type': 'variety',
        'source_type': sourceType,
        'source_id': sourceId,
        'transaction_date': dateStr,
        if (supplierId != null) 'supplier_id': supplierId,
        'supplier_name': supplierName ?? 'مورد محصول',
        'product_id': int.tryParse(fruitTypeId?.toString() ?? '') ?? fruitTypeId,
        'item_name': effectiveCropName,
        'category': 'تكلفة المحاصيل',
        'quantity': effectiveQty,
        'unit_price': effectiveUnitPrice,
        'currency': currency,
        'exchange_rate': actualExRate,
        'total_in_currency': totalInCurrency,
        'amount': totalEgp,
        'notes': notes,
        'is_confirmed': true,
        'updated_at': DateTime.now().toIso8601String(),
      };

      // 1. Attempt upsert into dedicated cost_center_transactions table
      try {
        await _client.from('cost_center_transactions').upsert(
          row,
          onConflict: 'source_type,source_id',
        );
      } catch (tableErr) {
        debugPrint('cost_center_transactions upsert notice: $tableErr');
        try {
          await _client.from('cost_center_transactions').insert(row);
        } catch (_) {}
      }

      // 2. Ensure product's cost center exists in cost_centers table
      await syncProductCostCenter(
        productId: fruitTypeId,
        productCode: costCenter.code ?? costCenter.id.replaceFirst('CC-', ''),
        productNameAr: effectiveCropName,
      );

      DataChangeEventBus.instance.notifyCostCentersChanged();
    } catch (e, st) {
      debugPrint('❌ recordCropPurchaseTransaction error (non-fatal): $e\n$st');
    }
  }

  /// Automatically records a sorting sale / produce sale transaction into
  /// `cost_center_transactions` directly linked to the parent fruit's cost center ID.
  /// Registers the sale amount as a negative/credit cost entry (-revenue) to offset
  /// the product's total cost and reflect net cost accurately in cost reports.
  Future<Map<String, dynamic>?> recordSortingSaleTransaction({
    required int sortingId,
    required int packingOrderId,
    required String productName,
    required double quantityKg,
    required double unitPrice,
    required double totalRevenue,
    required String treasuryName,
    int? treasuryId,
    int? journalEntryId,
    int? treasuryTransactionId,
    DateTime? date,
    String? notes,
  }) async {
    try {
      final effectiveDate = date ?? DateTime.now();
      dynamic fruitTypeId;
      String? parentProductName;
      String? orderNumber;

      // 1. Resolve parent fruit attributes from packing order
      if (packingOrderId > 0) {
        try {
          final poRes = await _client
              .from('packing_orders')
              .select('fruit_type_id, product_name, order_number')
              .eq('id', packingOrderId)
              .maybeSingle();
          if (poRes != null) {
            fruitTypeId = poRes['fruit_type_id'];
            parentProductName = poRes['product_name']?.toString();
            orderNumber = poRes['order_number']?.toString();
          }
        } catch (e) {
          debugPrint('ProductCostCenterSyncService error loading PO: $e');
        }
      }

      final effectiveCropName = (parentProductName != null && parentProductName.trim().isNotEmpty)
          ? parentProductName.trim()
          : (productName.trim().isNotEmpty ? productName.trim() : 'محصول');

      // 2. Resolve fruit_type_id if still null
      if (fruitTypeId == null) {
        try {
          final ftRes = await _client
              .from('fruit_types')
              .select('id, code, name')
              .ilike('name', '%$effectiveCropName%')
              .limit(1)
              .maybeSingle();
          if (ftRes != null) {
            fruitTypeId = ftRes['id'];
          }
        } catch (_) {}
      }

      // 3. Resolve the exact Cost Center for the parent fruit item
      final costCenter = await resolveCropCostCenter(
        fruitTypeId: fruitTypeId,
        cropName: effectiveCropName,
      );

      final dateStr = '${effectiveDate.year}-${effectiveDate.month.toString().padLeft(2, '0')}-${effectiveDate.day.toString().padLeft(2, '0')}';
      final revenuePositive = totalRevenue > 0 ? totalRevenue : (quantityKg * unitPrice);
      final amountNegative = -revenuePositive.abs(); // Negative to offset costs

      double effectiveQty = quantityKg;
      double effectiveUnitPrice = unitPrice;
      if (effectiveQty <= 0 && effectiveUnitPrice > 0 && revenuePositive > 0) {
        effectiveQty = revenuePositive / effectiveUnitPrice;
      } else if (effectiveQty > 0 && effectiveUnitPrice <= 0 && revenuePositive > 0) {
        effectiveUnitPrice = revenuePositive / effectiveQty;
      } else if (effectiveQty <= 0 && effectiveUnitPrice <= 0 && revenuePositive > 0) {
        effectiveQty = 1.0;
        effectiveUnitPrice = revenuePositive;
      }

      final sourceId = (treasuryTransactionId != null && treasuryTransactionId > 0)
          ? 'sorting_sale_${sortingId}_$treasuryTransactionId'
          : 'sorting_sale_${sortingId}_${effectiveDate.millisecondsSinceEpoch}';

      final row = {
        'cost_center_id': costCenter.code ?? costCenter.id,
        'cost_center_name': costCenter.displayTitle,
        'cost_center_type': 'variety',
        'source_type': 'sorting_sale',
        'source_id': sourceId,
        'transaction_date': dateStr,
        'supplier_name': 'عميل نقدي / مبيعات فرزة',
        'product_id': int.tryParse(fruitTypeId?.toString() ?? '') ?? fruitTypeId,
        'item_name': 'إيراد بيع فرز - $effectiveCropName',
        'category': 'تكلفة الفرز',
        'quantity': effectiveQty,
        'unit_price': effectiveUnitPrice,
        'currency': 'EGP',
        'exchange_rate': 1.0,
        'total_in_currency': amountNegative,
        'amount': amountNegative,
        'notes': notes ?? 'بيع فرز لأمر التعبئة #${orderNumber ?? packingOrderId} - خزينة: $treasuryName',
        'is_confirmed': true,
        'updated_at': DateTime.now().toIso8601String(),
      };

      // 4. Attempt upsert / insert into cost_center_transactions
      Map<String, dynamic>? insertedRow;
      try {
        final res = await _client.from('cost_center_transactions').upsert(
          row,
          onConflict: 'source_type,source_id',
        ).select().maybeSingle();
        insertedRow = res != null ? Map<String, dynamic>.from(res) : row;
      } catch (upsertErr) {
        debugPrint('cost_center_transactions upsert notice: $upsertErr');
        try {
          final res = await _client.from('cost_center_transactions').insert(row).select().maybeSingle();
          insertedRow = res != null ? Map<String, dynamic>.from(res) : row;
        } catch (_) {
          insertedRow = row;
        }
      }

      // 5. Ensure product's cost center is synchronized in cost_centers table
      await syncProductCostCenter(
        productId: fruitTypeId,
        productCode: costCenter.code ?? costCenter.id.replaceFirst('CC-', ''),
        productNameAr: effectiveCropName,
      );

      // 6. Broadcast event so cost center UI screens update in real-time
      DataChangeEventBus.instance.notifyCostCentersChanged();

      return insertedRow;
    } catch (e, st) {
      debugPrint('❌ recordSortingSaleTransaction error: $e\n$st');
      return null;
    }
  }

  /// Records export shipment sales movements into `cost_center_transactions`
  /// mapping each exported item to its parent fruit's Cost Center and populating
  /// the shipment number, packing order number, quantity, and foreign/EGP amounts.
  Future<void> recordExportShipmentRevenueTransactions({
    required dynamic shipmentId,
    required String shipmentNo,
    String? customerName,
    dynamic customerId,
    String currency = 'USD',
    double exchangeRate = 1.0,
    required List<dynamic> items,
    DateTime? date,
    int? journalEntryId,
  }) async {
    try {
      final effectiveDate = date ?? DateTime.now();
      final dateStr =
          '${effectiveDate.year}-${effectiveDate.month.toString().padLeft(2, '0')}-${effectiveDate.day.toString().padLeft(2, '0')}';
      final actualExRate =
          (currency.toUpperCase() == 'EGP' || exchangeRate <= 0) ? 1.0 : exchangeRate;

      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final itemMap = item is Map<String, dynamic>
            ? item
            : (item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{});

        final itemId = itemMap['id'] ?? (i + 1);
        final rawProductName = (itemMap['product_name'] ??
                itemMap['name'] ??
                itemMap['invoice_product_name'] ??
                '')
            .toString()
            .trim();
        final effectiveProductName =
            rawProductName.isNotEmpty ? rawProductName : 'محصول';

        final dynamic packingOrderId =
            itemMap['packing_order_id'] ?? itemMap['packingOrderId'];

        dynamic fruitTypeId = itemMap['finished_product_id'] ??
            itemMap['fruit_type_id'] ??
            itemMap['productId'];
        String? poNumber;

        // Try to resolve packing order details if present
        if (packingOrderId != null && packingOrderId.toString().isNotEmpty) {
          try {
            final poRes = await _client
                .from('packing_orders')
                .select('order_number, product_name, fruit_type_id')
                .eq('id', packingOrderId)
                .maybeSingle();
            if (poRes != null) {
              poNumber = poRes['order_number']?.toString();
              fruitTypeId ??= poRes['fruit_type_id'];
            }
          } catch (_) {}
        }

        final costCenter = await resolveCropCostCenter(
          fruitTypeId: fruitTypeId,
          cropName: effectiveProductName,
        );

        final qty = (itemMap['quantity'] ?? itemMap['qty'] as num?)?.toDouble() ?? 0.0;
        final unitPriceForeign = (itemMap['export_price_per_carton'] ??
                itemMap['exportPricePerCarton'] ??
                itemMap['price'] as num?)
            ?.toDouble() ??
            0.0;
        final totalForeign = (itemMap['amount'] as num?)?.toDouble() ??
            (qty > 0 && unitPriceForeign > 0 ? qty * unitPriceForeign : 0.0);
        final totalEgp = totalForeign * actualExRate;
        final unitPriceEgp = unitPriceForeign * actualExRate;

        final displayPo = poNumber ??
            packingOrderId?.toString();

        final row = {
          'cost_center_id': costCenter.code ?? costCenter.id,
          'cost_center_code': costCenter.code ?? costCenter.id,
          'cost_center_name': costCenter.displayTitle,
          'cost_center_type': 'variety',
          'source_type': 'export_shipment',
          'source_id': 'shipment_${shipmentId}_item_$itemId',
          'transaction_date': dateStr,
          if (customerId != null) 'supplier_id': customerId.toString(),
          'supplier_name': customerName ?? 'عميل تصدير',
          if (fruitTypeId != null)
            'product_id': int.tryParse(fruitTypeId.toString()) ?? fruitTypeId,
          'item_name': 'مبيعات تصدير - $effectiveProductName',
          'category': 'إيرادات المبيعات',
          'quantity': qty > 0 ? qty : 1.0,
          'unit_price': unitPriceEgp > 0 ? unitPriceEgp : totalEgp,
          'currency': currency,
          'exchange_rate': actualExRate,
          'total_in_currency': totalForeign,
          'amount': totalEgp,
          'amount_in_base_currency': totalEgp,
          'description':
              'شحنة تصدير رقم $shipmentNo${displayPo != null ? " | أمر تعبئة #$displayPo" : ""}',
          'notes':
              'شحنة: $shipmentNo${displayPo != null ? " - أمر تعبئة: #$displayPo" : ""}',
          if (journalEntryId != null) 'journal_entry_id': journalEntryId,
          'shipment_no': shipmentNo,
          if (displayPo != null) 'packing_order_number': displayPo,
          if (packingOrderId != null)
            'packing_order_id': int.tryParse(packingOrderId.toString()) ?? packingOrderId,
          'is_confirmed': true,
          'updated_at': DateTime.now().toIso8601String(),
        };

        try {
          await _client.from('cost_center_transactions').upsert(
            row,
            onConflict: 'source_type,source_id',
          );
        } catch (tableErr) {
          debugPrint('cost_center_transactions upsert notice: $tableErr');
          try {
            final fallbackRow = Map<String, dynamic>.from(row)
              ..remove('shipment_no')
              ..remove('packing_order_number')
              ..remove('packing_order_id');
            await _client.from('cost_center_transactions').upsert(
              fallbackRow,
              onConflict: 'source_type,source_id',
            );
          } catch (_) {}
        }
      }

      DataChangeEventBus.instance.notifyCostCentersChanged();
    } catch (e, st) {
      debugPrint('❌ recordExportShipmentRevenueTransactions error: $e\n$st');
    }
  }

  /// Records a waste/spoilage transaction into `cost_center_transactions`
  /// with fully populated quantity and unit_price.
  Future<Map<String, dynamic>?> recordWasteCostTransaction({
    required String sourceId,
    required String costCenterId,
    required String costCenterName,
    required String itemName,
    required double wasteCost,
    double quantity = 0.0,
    double unitPrice = 0.0,
    dynamic productId,
    DateTime? date,
    String? notes,
    String currency = 'EGP',
    double exchangeRate = 1.0,
  }) async {
    try {
      final effectiveDate = date ?? DateTime.now();
      final dateStr = '${effectiveDate.year}-${effectiveDate.month.toString().padLeft(2, '0')}-${effectiveDate.day.toString().padLeft(2, '0')}';
      final actualExRate = (currency.toUpperCase() == 'EGP' || exchangeRate <= 0) ? 1.0 : exchangeRate;
      final totalInCur = wasteCost;
      final totalEgp = totalInCur * actualExRate;

      double effQty = quantity;
      double effPrice = unitPrice;
      if (effQty <= 0 && effPrice > 0 && totalInCur > 0) {
        effQty = totalInCur / effPrice;
      } else if (effQty > 0 && effPrice <= 0 && totalInCur > 0) {
        effPrice = totalInCur / effQty;
      } else if (effQty <= 0 && effPrice <= 0 && totalInCur > 0) {
        effQty = 1.0;
        effPrice = totalInCur;
      }

      final row = {
        'cost_center_id': costCenterId,
        'cost_center_name': costCenterName,
        'cost_center_type': 'variety',
        'source_type': 'packing_waste',
        'source_id': sourceId,
        'transaction_date': dateStr,
        'supplier_name': 'هالك تشغيل وتعبئة',
        if (productId != null) 'product_id': int.tryParse(productId.toString()) ?? productId,
        'item_name': itemName,
        'category': 'تكلفة الهالك',
        'quantity': effQty,
        'unit_price': effPrice,
        'currency': currency,
        'exchange_rate': actualExRate,
        'total_in_currency': totalInCur,
        'amount': totalEgp,
        'notes': notes ?? 'تكلفة هالك محملة على مركز التكلفة',
        'is_confirmed': true,
        'updated_at': DateTime.now().toIso8601String(),
      };

      final res = await _client.from('cost_center_transactions').upsert(
        row,
        onConflict: 'source_type,source_id',
      ).select().maybeSingle();

      DataChangeEventBus.instance.notifyCostCentersChanged();
      return res != null ? Map<String, dynamic>.from(res) : row;
    } catch (e, st) {
      debugPrint('❌ recordWasteCostTransaction error: $e\n$st');
      return null;
    }
  }

  /// Records an additional cost / service movement into `cost_center_transactions`
  /// ensuring quantity & unit_price are always set.
  Future<Map<String, dynamic>?> recordAdditionalCostTransaction({
    required String sourceId,
    required String costCenterId,
    required String costCenterName,
    required String itemName,
    required String category,
    required double amount,
    double quantity = 0.0,
    double unitPrice = 0.0,
    String? supplierName,
    dynamic supplierId,
    dynamic productId,
    DateTime? date,
    String? notes,
    String currency = 'EGP',
    double exchangeRate = 1.0,
  }) async {
    try {
      final effectiveDate = date ?? DateTime.now();
      final dateStr = '${effectiveDate.year}-${effectiveDate.month.toString().padLeft(2, '0')}-${effectiveDate.day.toString().padLeft(2, '0')}';
      final actualExRate = (currency.toUpperCase() == 'EGP' || exchangeRate <= 0) ? 1.0 : exchangeRate;
      final totalInCur = amount;
      final totalEgp = totalInCur * actualExRate;

      double effQty = quantity;
      double effPrice = unitPrice;
      if (effQty <= 0 && effPrice > 0 && totalInCur != 0) {
        effQty = totalInCur / effPrice;
      } else if (effQty != 0 && effPrice <= 0 && totalInCur != 0) {
        effPrice = (totalInCur / effQty).abs();
      } else if (effQty <= 0 && effPrice <= 0 && totalInCur != 0) {
        effQty = totalInCur < 0 ? -1.0 : 1.0;
        effPrice = totalInCur.abs();
      }

      final row = {
        'cost_center_id': costCenterId,
        'cost_center_name': costCenterName,
        'cost_center_type': 'variety',
        'source_type': 'additional_cost',
        'source_id': sourceId,
        'transaction_date': dateStr,
        if (supplierId != null) 'supplier_id': supplierId.toString(),
        if (supplierName != null) 'supplier_name': supplierName,
        if (productId != null) 'product_id': int.tryParse(productId.toString()) ?? productId,
        'item_name': itemName,
        'category': category,
        'quantity': effQty,
        'unit_price': effPrice,
        'currency': currency,
        'exchange_rate': actualExRate,
        'total_in_currency': totalInCur,
        'amount': totalEgp,
        'notes': notes,
        'is_confirmed': true,
        'updated_at': DateTime.now().toIso8601String(),
      };

      final res = await _client.from('cost_center_transactions').upsert(
        row,
        onConflict: 'source_type,source_id',
      ).select().maybeSingle();

      DataChangeEventBus.instance.notifyCostCentersChanged();
      return res != null ? Map<String, dynamic>.from(res) : row;
    } catch (e, st) {
      debugPrint('❌ recordAdditionalCostTransaction error: $e\n$st');
      return null;
    }
  }

  /// Deactivates matching Cost Center when the parent product is archived/deleted
  Future<void> deactivateCostCenter(String productCode) async {
    try {
      final code = productCode.startsWith('CC-') ? productCode : 'CC-$productCode';
      await _client.from('cost_centers').update({
        'is_active': false,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('code', code);
    } catch (e) {
      debugPrint('ProductCostCenterSyncService deactivate error: $e');
    }
  }

  /// Fetches all dynamic product-linked cost centers from Supabase
  Future<List<Map<String, dynamic>>> getProductCostCenters({bool onlyActive = true}) async {
    try {
      var query = _client.from('cost_centers').select();
      if (onlyActive) {
        query = query.eq('is_active', true);
      }
      final data = await query.order('name');
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      return [];
    }
  }
}

