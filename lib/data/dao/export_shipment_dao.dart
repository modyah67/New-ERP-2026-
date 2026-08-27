import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/export_shipment_model.dart';
import '../services/currency_conversion_service.dart';

class ExportShipmentDao {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<ExportShipmentModel>> getAll({
    String? status,
    String? searchQuery,
    String? fromDate,
    String? toDate,
    int limit = 50,
    int offset = 0,
    String? excludeStatus,
  }) async {
    try {
      var query = _client.from('export_shipments').select();
      if (status != null && status.isNotEmpty) {
        query = query.eq('status', status);
      } else if (excludeStatus != null && excludeStatus.isNotEmpty) {
        query = query.neq('status', excludeStatus);
      }
      if (fromDate != null) query = query.gte('shipment_date', fromDate);
      if (toDate != null) query = query.lte('shipment_date', toDate);
      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or(
            'shipment_no.ilike.%$searchQuery%,vessel_name.ilike.%$searchQuery%,container_number.ilike.%$searchQuery%');
      }
      final data = await query.order('created_at', ascending: false).range(offset, offset + limit - 1);
      return data.map((row) => ExportShipmentModel.fromMap(row)).toList();
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (getAll): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (getAll): $e');
    }
  }

  Future<ExportShipmentModel?> getLatest() async {
    try {
      final data = await _client
          .from('export_shipments')
          .select()
          .neq('status', 'cancelled')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (data == null) return null;
      return ExportShipmentModel.fromMap(data);
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (getLatest): ${e.message}');
    } catch (e) {
      throw Exception('Unexpected error (getLatest): $e');
    }
  }

  Future<ExportShipmentModel?> getById(dynamic id) async {
    try {
      final parsedId = int.tryParse(id.toString()) ?? id;
      final data = await _client.from('export_shipments').select().eq('id', parsedId).maybeSingle();
      if (data == null) return null;
      return ExportShipmentModel.fromMap(data);
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (getById): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (getById): $e');
    }
  }

  Future<dynamic> saveWithRpc(ExportShipmentModel shipment, List<Map<String, dynamic>> items) async {
    try {
      if (shipment.shipmentNo.trim().isEmpty) {
        throw Exception(' shipment_no cannot be empty');
      }
      final data = shipment.toMap();
      // Remove created_at if updating
      if (shipment.id != null) {
        data.remove('created_at');
      } else {
        data.remove('id');
      }
      
      final result = await _client.rpc('rpc_save_export_shipment', params: {
        'p_shipment': data,
        'p_items': items,
      });
      
      if (result != null && result['id'] != null) {
        return result['id'];
      }
      throw Exception('No ID returned from RPC');
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (saveWithRpc): ${e.message} | code: ${e.code} | details: ${e.details}');
    } catch (e) {
      throw Exception('Unexpected error (saveWithRpc): $e');
    }
  }

  Future<dynamic> insert(ExportShipmentModel shipment) async {
    try {
      if (shipment.shipmentNo.trim().isEmpty) {
        throw Exception(' shipment_no cannot be empty');
      }
      final data = shipment.toMap();
      data.remove('id');
      // user_id is NOT sent — Supabase fills it via DEFAULT auth.uid()
      final result = await _client.from('export_shipments').insert(data).select().single();
      return result['id'];
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (insert): ${e.message} | code: ${e.code} | details: ${e.details}');
    } catch (e) {
      throw Exception('Unexpected error (insert): $e');
    }
  }

  Future<void> update(ExportShipmentModel shipment) async {
    try {
      final data = shipment.toMap();
      data.remove('id');
      data.remove('created_at');
      await _client.from('export_shipments').update(data).eq('id', int.parse(shipment.id!));
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (update): ${e.message} | code: ${e.code} | details: ${e.details}');
    } catch (e) {
      throw Exception('Unexpected error (update): $e');
    }
  }

  Future<void> updatePackingRecipeId(dynamic shipmentId, String recipeId) async {
    try {
      final parsedSid = shipmentId is int ? shipmentId : int.tryParse(shipmentId.toString()) ?? shipmentId;
      await _client.from('export_shipments').update({'packing_recipe_id': recipeId}).eq('id', parsedSid);
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (updatePackingRecipeId): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (updatePackingRecipeId): $e');
    }
  }

  Future<void> updateStatus(dynamic id, String status) async {
    try {
      final parsedId = int.tryParse(id.toString()) ?? id;
      await _client.from('export_shipments').update({'status': status}).eq('id', parsedId);
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (updateStatus): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (updateStatus): $e');
    }
  }

  /// Cancel shipment with full accounting reversal via SQL RPC.
  /// Reverses customer balance, ledger entries, creates journal entries
  /// and treasury transaction for cancellation audit trail.
  Future<Map<String, dynamic>> cancelShipment(dynamic id) async {
    try {
      final sid = id is int ? id : int.tryParse('$id');
      if (sid == null) throw Exception('Invalid shipment id: $id');

      final result = await _client
          .rpc('rpc_cancel_export_shipment', params: {
        'p_shipment_id': sid,
      });

      if (result is Map<String, dynamic>) {
        if (result['success'] == false) {
          throw Exception(result['error'] ?? 'Failed to cancel shipment');
        }
        return result;
      }
      throw Exception('Unexpected response from cancel RPC');
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (cancelShipment): ${e.message} | code: ${e.code}');
    } catch (e) {
      if (e.toString().contains('Invalid shipment') ||
          e.toString().contains('Failed to cancel')) {
        rethrow;
      }
      throw Exception('Unexpected error (cancelShipment): $e');
    }
  }

  /// Get cancel info for UI display (check if cancellable, amounts, etc.)
  Future<Map<String, dynamic>?> getCancelInfo(dynamic id) async {
    try {
      final sid = id is int ? id : int.tryParse('$id');
      if (sid == null) return null;

      final result = await _client
          .rpc('rpc_get_export_shipment_cancel_info', params: {
        'p_shipment_id': sid,
      });

      if (result is Map<String, dynamic> && result['success'] == true) {
        return result;
      }
      return null;
    } catch (e) {
      print('⚠️ Failed to get cancel info for shipment $id: $e');
      return null;
    }
  }

  Future<void> delete(dynamic id) async {
    try {
      final parsedId = int.tryParse(id.toString()) ?? id;
      final result = await _client
          .from('export_shipments')
          .delete()
          .eq('id', parsedId)
          .select() as List;
      print('ExportShipmentDao.delete: id=$id, rows_affected=${result.length}');
      if (result.isEmpty) {
        throw Exception('لم يتم العثور على الشحنة أو لا تملك صلاحية الحذف (id=$id)');
      }
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (delete): ${e.message} | code: ${e.code}');
    }
  }

  Future<Map<String, dynamic>> syncLedger(dynamic shipmentId) async {
    final sid = shipmentId is int ? shipmentId : int.tryParse('$shipmentId');
    if (sid == null) {
      throw Exception('معرف الشحنة غير صالح');
    }
    try {
      final result = await _client.rpc('rpc_process_export_shipment_ledger', params: {
        'p_shipment_id': sid,
      });
      if (result is Map && result['success'] == false) {
        throw Exception(result['error']?.toString() ?? 'فشل ترحيل قيود الشحنة');
      }
      return result is Map<String, dynamic>
          ? result
          : {'success': true, 'result': result};
    } on PostgrestException catch (e) {
      throw Exception('فشل ترحيل قيود الشحنة: ${e.message}');
    } catch (e) {
      throw Exception('فشل ترحيل قيود الشحنة: $e');
    }
  }

  Future<String> getNextShipmentNo(String customerCode, int year) async {
    try {
      final yy = (year % 100).toString().padLeft(2, '0');
      final prefix = '$yy/$customerCode/';
      final data = await _client
          .from('export_shipments')
          .select('shipment_no')
          .like('shipment_no', '$prefix%')
          .order('shipment_no', ascending: false)
          .limit(1)
          .maybeSingle();
      if (data == null) return '${prefix}01';
      final last = (data['shipment_no'] ?? '').toString();
      final suffix = last.replaceFirst(prefix, '');
      final lastNum = int.tryParse(suffix) ?? 0;
      final nextNum = lastNum + 1;
      return '$prefix${nextNum.toString().padLeft(2, '0')}';
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (getNextShipmentNo): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (getNextShipmentNo): $e');
    }
  }

  Future<List<ExportShipmentModel>> getByCustomer(dynamic customerId) async {
    try {
      final data = await _client
          .from('export_shipments')
          .select()
          .eq('customer_id', customerId is int ? customerId : int.tryParse(customerId.toString()) ?? customerId)
          .order('created_at', ascending: false);
      return data.map((row) => ExportShipmentModel.fromMap(row)).toList();
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (getByCustomer): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (getByCustomer): $e');
    }
  }

  Future<void> updateCosting({
    required int shipmentId,
    required double totalLandedCost,
    required int cartonCount,
    required double exportPricePerCarton,
    required String currencyCode,
    required double exchangeRate,
    double totalFruitCost = 0.0,
    double totalPackingMaterialCost = 0.0,
    double nonPackingLandedCost = 0.0,
  }) async {
    try {
      final costPerCarton = cartonCount > 0 ? totalLandedCost / cartonCount : 0.0;
      
      // Accurately calculate total revenue from items
      final itemsData = await _client.from('export_shipment_items').select('quantity, export_price_per_carton').eq('shipment_id', shipmentId);
      double totalRevenueForeign = 0.0;
      for (final item in itemsData) {
        final qty = (item['quantity'] as num?)?.toDouble() ?? 0;
        final price = (item['export_price_per_carton'] as num?)?.toDouble() ?? 0;
        totalRevenueForeign += qty * price;
      }
      
      // Fetch discount from existing shipment
      final shipmentData = await _client.from('export_shipments').select('discount_amount').eq('id', shipmentId).maybeSingle();
      final discount = (shipmentData?['discount_amount'] as num?)?.toDouble() ?? 0.0;
      
      totalRevenueForeign = totalRevenueForeign - discount;
      final totalRevenueEgp = CurrencyConversionService.instance.toBase(totalRevenueForeign, currencyCode, exchangeRate);
      
      final netProfit = totalRevenueEgp - totalLandedCost;
      final grossProfit = totalRevenueEgp - totalFruitCost - totalPackingMaterialCost;

      await _client.from('export_shipments').update({
        'total_landed_cost': totalLandedCost,
        'cost_per_carton': costPerCarton,
        'export_price_per_carton': exportPricePerCarton,
        'currency_code': currencyCode,
        'exchange_rate': exchangeRate,
        'total_revenue_foreign': totalRevenueForeign,
        'total_revenue_egp': totalRevenueEgp,
        'net_profit_egp': netProfit,
        'total_fruit_cost': totalFruitCost,
        'total_packing_material_cost': totalPackingMaterialCost,
        'gross_profit': grossProfit,
        'net_profit': netProfit,
        'needs_profit_redistribution': true,
        'currency_snapshot': CurrencyConversionService.instance.createSnapshot(
          currency: currencyCode,
          amount: totalRevenueForeign,
          exchangeRate: exchangeRate,
        ).toJson(),
      }).eq('id', shipmentId);
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (updateCosting): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (updateCosting): $e');
    }
  }

  Future<Map<String, dynamic>> getProfitSummary() async {
    try {
      final data = await _client
        .from('export_shipments')
        .select('total_revenue_egp, total_landed_cost, net_profit_egp')
        .neq('status', 'cancelled')
        .eq('is_confirmed', true);

      double totalRevenue = 0, totalCost = 0, totalProfit = 0;
      for (final row in data) {
        totalRevenue += (row['total_revenue_egp'] as num?)?.toDouble() ?? 0;
        totalCost += (row['total_landed_cost'] as num?)?.toDouble() ?? 0;
        totalProfit += (row['net_profit_egp'] as num?)?.toDouble() ?? 0;
      }
      return {
        'total_revenue_egp': totalRevenue,
        'total_cost_egp': totalCost,
        'net_profit_egp': totalProfit,
        'shipment_count': data.length,
      };
    } on PostgrestException catch (e) {
      throw Exception('Supabase error (getProfitSummary): ${e.message} | code: ${e.code}');
    } catch (e) {
      throw Exception('Unexpected error (getProfitSummary): $e');
    }
  }

  Future<List<Map<String, dynamic>>> getJournalEntriesForShipment(dynamic shipmentId) async {
    try {
      final sid = shipmentId is int ? shipmentId : int.tryParse('$shipmentId');
      if (sid == null) return [];

      // Get the shipment_no for description matching
      final shipmentRow = await _client
          .from('export_shipments')
          .select('shipment_no')
          .eq('id', sid)
          .maybeSingle();
      final shipmentNo = shipmentRow?['shipment_no']?.toString() ?? '';

      // Collect journal entry IDs from multiple sources
      final Set<int> jeIds = {};

      // 1. Match by source_id (new entries after migration 120 & 282)
      final bySourceId = await _client
          .from('journal_entries')
          .select('id')
          .eq('source_id', sid.toString())
          .inFilter('source_type', [
            'export_shipment', 'export_discount', 'shipment_cost_accrual',
            'bank_deposit', 'customer_bank_deposit',
            'customer_treasury_deposit', 'customer_treasury_withdrawal',
            'export_payment', 'expense_payment', 'bank_withdrawal',
          ]);
      for (final row in bySourceId) {
        jeIds.add(row['id'] as int);
      }

      // 2. Match directly by journal_entry_id referenced in shipment_cost_items
      final costItemJEs = await _client
          .from('shipment_cost_items')
          .select('journal_entry_id')
          .eq('shipment_id', sid)
          .not('journal_entry_id', 'is', null);
      for (final row in costItemJEs) {
        if (row['journal_entry_id'] != null) {
          jeIds.add(row['journal_entry_id'] as int);
        }
      }

      // 3. Match by description containing shipment_no (all relevant types)
      if (shipmentNo.isNotEmpty) {
        final byDesc = await _client
            .from('journal_entries')
            .select('id')
            .ilike('description', '%$shipmentNo%')
            .inFilter('source_type', [
              'export_shipment', 'export_discount', 'shipment_cost_accrual',
              'bank_deposit', 'customer_bank_deposit',
              'customer_treasury_deposit', 'customer_treasury_withdrawal',
              'export_payment', 'expense_payment', 'bank_withdrawal',
            ]);
        for (final row in byDesc) {
          jeIds.add(row['id'] as int);
        }
      }

      if (jeIds.isEmpty) return [];

      // Fetch full details for matching journal entries
      final entries = await _client
          .from('journal_entries')
          .select('id, entry_number, entry_date, description, source_type, source_id, created_at')
          .inFilter('id', jeIds.toList())
          .order('created_at', ascending: true);

      // Enrich with account_ledger_entries totals
      final results = <Map<String, dynamic>>[];
      for (final je in entries) {
        final jeId = je['id'] as int;
        final aleRows = await _client
            .from('account_ledger_entries')
            .select('debit, credit, currency, amount_in_base_currency')
            .eq('journal_entry_id', jeId);
        
        final srcType = je['source_type']?.toString() ?? '';
        double displayAmount = 0;
        String displayCurrency = 'EGP';

        if (srcType == 'export_shipment') {
          // For export sale entry: display the customer revenue in foreign/original currency
          final foreignDebitLine = aleRows.firstWhere(
            (r) => (r['currency']?.toString() ?? 'EGP') != 'EGP' && ((r['debit'] as num?)?.toDouble() ?? 0) > 0,
            orElse: () => <String, dynamic>{},
          );
          if (foreignDebitLine.isNotEmpty) {
            displayAmount = (foreignDebitLine['debit'] as num?)?.toDouble() ?? 0;
            displayCurrency = foreignDebitLine['currency']?.toString() ?? 'USD';
          } else {
            final firstDebit = aleRows.firstWhere(
              (r) => ((r['debit'] as num?)?.toDouble() ?? 0) > 0,
              orElse: () => <String, dynamic>{},
            );
            displayAmount = (firstDebit['debit'] as num?)?.toDouble() ?? 0;
            displayCurrency = firstDebit['currency']?.toString() ?? 'EGP';
          }
        } else {
          final nonEgpCurrencies = aleRows
              .map((r) => r['currency']?.toString() ?? 'EGP')
              .where((c) => c != 'EGP')
              .toSet();

          if (nonEgpCurrencies.length == 1) {
            final cur = nonEgpCurrencies.first;
            displayAmount = aleRows
                .where((r) => (r['currency']?.toString() ?? 'EGP') == cur)
                .fold<double>(0.0, (sum, r) => sum + ((r['debit'] as num?)?.toDouble() ?? 0));
            displayCurrency = cur;
          } else {
            double totalBaseDebit = 0;
            for (final ale in aleRows) {
              final debit = (ale['debit'] as num?)?.toDouble() ?? 0;
              final baseAmt = (ale['amount_in_base_currency'] as num?)?.toDouble() ?? 0;
              if (debit > 0) {
                totalBaseDebit += baseAmt > 0 ? baseAmt : debit;
              }
            }
            displayAmount = totalBaseDebit;
            displayCurrency = 'EGP';
          }
        }

        results.add({
          'journal_entry_id': jeId,
          'entry_number': je['entry_number'],
          'entry_date': je['entry_date'],
          'description': je['description'],
          'source_type': je['source_type'],
          'source_id': je['source_id'],
          'total_debit': displayAmount,
          'total_credit': displayAmount,
          'currency': displayCurrency,
          'created_at': je['created_at'],
        });
      }
      return results;
    } catch (e) {
      print('ExportShipmentDao.getJournalEntriesForShipment error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> applyDiscount({
    required dynamic shipmentId,
    required double discountAmount,
    String? reason,
  }) async {
    final sid = shipmentId is int ? shipmentId : int.tryParse('$shipmentId');
    if (sid == null) throw Exception('Invalid shipment id: $shipmentId');

    final result = await _client.rpc('rpc_apply_export_discount', params: {
      'p_shipment_id': sid,
      'p_discount_amount': discountAmount,
      'p_discount_reason': reason,
    });

    if (result is Map<String, dynamic> && result['success'] == false) {
      throw Exception(result['error'] ?? 'Failed to apply discount');
    }
    return result is Map<String, dynamic> ? result : {'success': true};
  }

  Future<Map<String, double>> getItemTotals(List<dynamic> shipmentIds) async {
    if (shipmentIds.isEmpty) return {};
    try {
      final idStrs = shipmentIds.map((id) => id.toString()).toList();
      final data = await _client
          .from('export_shipment_items')
          .select('shipment_id, quantity, export_price_per_carton')
          .inFilter('shipment_id', idStrs);
          
      final shipmentData = await _client
          .from('export_shipments')
          .select('id, discount_amount')
          .inFilter('id', idStrs);
          
      final discounts = <String, double>{};
      for (final row in shipmentData) {
        discounts[row['id'].toString()] = (row['discount_amount'] as num?)?.toDouble() ?? 0.0;
      }

      final totals = <String, double>{};
      for (final row in data) {
        final sid = row['shipment_id']?.toString() ?? '';
        final qty = (row['quantity'] as num?)?.toDouble() ?? 0;
        final price = (row['export_price_per_carton'] as num?)?.toDouble() ?? 0;
        totals[sid] = (totals[sid] ?? 0) + qty * price;
      }
      
      for (final sid in totals.keys) {
        totals[sid] = totals[sid]! - (discounts[sid] ?? 0.0);
      }
      return totals;
    } catch (e) {
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> getProfitDistributionJournalEntries(dynamic shipmentId) async {
    try {
      final sid = shipmentId is int ? shipmentId : int.tryParse('$shipmentId');
      if (sid == null) return [];

      final result = await _client.rpc('rpc_get_profit_distribution_journal_entries', params: {
        'p_shipment_id': sid,
      });

      if (result is List) {
        return List<Map<String, dynamic>>.from(result);
      }
      return [];
    } catch (e) {
      print('ExportShipmentDao.getProfitDistributionJournalEntries error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> saveAllocatedAdminExpenses({
    required int shipmentId,
    required double allocatedAdminExpenses,
  }) async {
    try {
      final res = await _client.rpc('rpc_save_shipment_admin_expenses', params: {
        'p_shipment_id': shipmentId,
        'p_allocated_admin_expenses': allocatedAdminExpenses,
      });
      return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    } catch (e, st) {
      print('ExportShipmentDao.saveAllocatedAdminExpenses error: $e\n$st');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> saveAllocatedTaxes({
    required int shipmentId,
    required double allocatedTaxes,
  }) async {
    try {
      final res = await _client.rpc('rpc_save_shipment_taxes', params: {
        'p_shipment_id': shipmentId,
        'p_allocated_taxes': allocatedTaxes,
      });
      return res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    } catch (e, st) {
      print('ExportShipmentDao.saveAllocatedTaxes error: $e\n$st');
      rethrow;
    }
  }

  Future<bool> isShipmentProfitDistributed(int shipmentId) async {
    try {
      final data = await _client
          .from('shareholder_profit_distributions')
          .select('id')
          .eq('shipment_id', shipmentId)
          .isFilter('deleted_at', null)
          .limit(1);
      return (data as List).isNotEmpty;
    } catch (e, st) {
      print('ExportShipmentDao.isShipmentProfitDistributed error: $e\n$st');
      return false;
    }
  }
}
