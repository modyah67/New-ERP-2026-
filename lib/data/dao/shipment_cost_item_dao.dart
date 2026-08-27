
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/shipment_cost_item_model.dart';
import '../services/currency_conversion_service.dart';

class ShipmentCostItemDao {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<ShipmentCostItemModel>> getForShipment(int shipmentId) async {
    final data = await _client
        .from('shipment_cost_items')
        .select(
          '*, cost_report_categories(name), journal_entry_id, expense_account_id'
        )
        .eq('shipment_id', shipmentId)
        .order('sort_order')
        .order('created_at');
    return data.map((e) => ShipmentCostItemModel.fromMap(e)).toList();
  }

  /// Saves all shipment cost items.
  /// Paid items (treasury_transaction_id or bank_transaction_id set)
  /// are never deleted — they are preserved as-is to protect the audit trail.
  /// Existing items (id != null) are UPDATEd, new items (id == null) are INSERTed.
  Future<List<ShipmentCostItemModel>> saveAll(
      int shipmentId, List<ShipmentCostItemModel> items) async {
    // 2. Separate items into existing (id != null) and new (id == null)
    final existingItems = items.where((i) => i.id != null && !i.isPaid && !i.isReadOnly).toList();
    final newItems = items.where((i) => i.id == null && !i.isPaid && !i.isReadOnly).toList();

    // 1. Delete only UNPAID rows that are no longer in the provided items list
    //    Paid rows are never touched to protect the audit trail.
    final existingIds = items.where((i) => i.id != null).map((i) => i.id!).toList();
    
    final dbUnpaidItems = await _client
        .from('shipment_cost_items')
        .select('id')
        .eq('shipment_id', shipmentId)
        .isFilter('treasury_transaction_id', null)
        .isFilter('bank_transaction_id', null);
        
    for (final row in dbUnpaidItems) {
      final id = row['id'] as int;
      if (!existingIds.contains(id)) {
        await _client.from('shipment_cost_items').delete().eq('id', id);
      }
    }

    // 3. UPDATE existing unpaid items (preserve id, prevent duplicate key)
    for (final item in existingItems) {
      final isShipping = item.vendorType == 'shipping_company' || item.shippingCompanyId != null;
      final isClearing = item.vendorType == 'clearing_agent' || item.clearingAgentId != null;
      final category = isShipping ? 'freight' : (isClearing ? 'clearance' : item.category);
      final shippingId = isShipping ? (item.shippingCompanyId ?? item.vendorId) : null;
      final clearingId = isClearing ? (item.clearingAgentId ?? item.vendorId) : null;

      await _client.from('shipment_cost_items').update({
        'description': item.description,
        'quantity': item.quantity,
        'unit_price': item.unitPrice,
        'category': category,
        'report_category_id': item.reportCategoryId,
        'sort_order': item.sortOrder,
        'exchange_rate': item.exchangeRate,
        if (item.supplierId != null) 'supplier_id': item.supplierId,
        if (item.supplierCurrency != null) 'supplier_currency': item.supplierCurrency,
        if (item.supplierCurrency != null) 'original_currency': item.supplierCurrency,
        if (item.vendorType != null) 'vendor_type': item.vendorType,
        if (item.vendorId != null) 'vendor_id': item.vendorId,
        if (item.expenseAccountId != null) 'expense_account_id': item.expenseAccountId,
        if (shippingId != null) 'shipping_company_id': shippingId,
        if (clearingId != null) 'clearing_agent_id': clearingId,
        if (item.paymentSourceType != null) 'payment_source_type': item.paymentSourceType,
        if (item.paymentSourceId != null) 'payment_source_id': item.paymentSourceId,
        'currency_snapshot': CurrencyConversionService.instance.createSnapshot(
          currency: item.supplierCurrency ?? 'EGP',
          amount: item.totalPrice,
          exchangeRate: item.exchangeRate,
        ).toJson(),
      }).eq('id', item.id!);
    }

    // 4. INSERT only truly new items (no id)
    if (newItems.isNotEmpty) {
      await _client.from('shipment_cost_items').insert(
        newItems.asMap().entries.map((e) {
          final isShipping = e.value.vendorType == 'shipping_company' || e.value.shippingCompanyId != null;
          final isClearing = e.value.vendorType == 'clearing_agent' || e.value.clearingAgentId != null;
          final category = isShipping ? 'freight' : (isClearing ? 'clearance' : e.value.category);
          final shippingId = isShipping ? (e.value.shippingCompanyId ?? e.value.vendorId) : null;
          final clearingId = isClearing ? (e.value.clearingAgentId ?? e.value.vendorId) : null;

          return {
            'shipment_id': shipmentId,
            'category': category,
            'report_category_id': e.value.reportCategoryId,
            'description': e.value.description,
            'quantity': e.value.quantity,
            'unit_price': e.value.unitPrice,
            'sort_order': e.value.sortOrder,
            if (e.value.vendorType != null) 'vendor_type': e.value.vendorType,
            if (e.value.vendorId != null) 'vendor_id': e.value.vendorId,
            'exchange_rate': e.value.exchangeRate,
            if (e.value.supplierId != null) 'supplier_id': e.value.supplierId,
            if (e.value.supplierCurrency != null)
              'supplier_currency': e.value.supplierCurrency,
            if (e.value.supplierCurrency != null)
              'original_currency': e.value.supplierCurrency,
            if (e.value.expenseAccountId != null) 'expense_account_id': e.value.expenseAccountId,
            if (shippingId != null) 'shipping_company_id': shippingId,
            if (clearingId != null) 'clearing_agent_id': clearingId,
            'currency_snapshot': CurrencyConversionService.instance.createSnapshot(
              currency: e.value.supplierCurrency ?? 'EGP',
              amount: e.value.totalPrice,
              exchangeRate: e.value.exchangeRate,
            ).toJson(),
            if (e.value.paymentSourceType != null)
              'payment_source_type': e.value.paymentSourceType,
            if (e.value.paymentSourceId != null)
              'payment_source_id': e.value.paymentSourceId,
          };
        }).toList(),
      );
    }

    // 5. Ensure all accrual journal entries are synced atomically
    try {
      await _client.rpc('rpc_sync_shipment_cost_accruals', params: {'p_shipment_id': shipmentId});
    } catch (_) {}

    // 6. Return all items for this shipment (paid + updated + newly inserted)
    return getForShipment(shipmentId);
  }

  /// Pays a single cost item atomically via treasury or bank.
  /// Calls RPC rpc_pay_shipment_cost_item on the DB.
  /// Returns the updated item on success, throws on failure.
  Future<Map<String, dynamic>> payItem({
    required int costItemId,
    required String sourceType, // 'treasury' | 'bank'
    required int sourceId,
    int? expenseAccountId,
  }) async {
    final result = await _client.rpc(
      'rpc_pay_shipment_cost_item',
      params: {
        'p_cost_item_id': costItemId,
        'p_source_type': sourceType,
        'p_source_id': sourceId,
        if (expenseAccountId != null) 'p_expense_account_id': expenseAccountId,
      },
    );
    if (result is Map && result['success'] == true) {
      return Map<String, dynamic>.from(result);
    }
    throw Exception(
        result is Map ? result['error'] ?? 'فشل سداد البند' : 'فشل سداد البند');
  }

  Future<void> updateVendorBalances() async {
    await _client.rpc('rpc_sync_vendor_balances_and_ledger');
  }

  Future<void> upsertSupplierLedgerEntries(List<ShipmentCostItemModel> savedItems) async {
    // Now handled atomically by rpc_sync_vendor_balances_and_ledger (Migration 036)
    // Balance recalc + ledger_entries upsert in one SQL transaction
    await _client.rpc('rpc_sync_vendor_balances_and_ledger');
  }

  Future<double> getTotalForShipment(int shipmentId) async {
    final data = await _client
        .from('shipment_cost_items')
        .select('total_price')
        .eq('shipment_id', shipmentId);
    return data.fold<double>(
        0.0, (sum, row) => sum + ((row['total_price'] as num?)?.toDouble() ?? 0));
  }

  /// Fetches all journal entries related to a shipment's cost items (profitability).
  /// Returns entries ordered newest-first with cost item metadata.
  Future<List<Map<String, dynamic>>> getJournalEntriesForShipment(int shipmentId) async {
    final data = await _client.rpc(
      'rpc_get_profitability_journal_entries',
      params: {'p_shipment_id': shipmentId},
    );
    if (data is List) {
      return List<Map<String, dynamic>>.from(data);
    }
    return [];
  }

  /// Edits a paid cost item atomically: reversals old GL + financial tx,
  /// creates new GL + financial tx, updates the cost item.
  /// Returns the result map with reversal_je_id, new_je_id, revision, etc.
  Future<Map<String, dynamic>> editExpense({
    required int costItemId,
    required String description,
    required double quantity,
    required double unitPrice,
    required String sourceType, // 'treasury' | 'bank'
    required int sourceId,
    int? expenseAccountId,
    int? shippingCompanyId,
    int? clearingAgentId,
  }) async {
    final result = await _client.rpc(
      'rpc_edit_profitability_expense',
      params: {
        'p_cost_item_id': costItemId,
        'p_new_description': description,
        'p_new_quantity': quantity,
        'p_new_unit_price': unitPrice,
        'p_new_source_type': sourceType,
        'p_new_source_id': sourceId,
        if (expenseAccountId != null) 'p_new_expense_account_id': expenseAccountId,
        if (shippingCompanyId != null) 'p_new_shipping_company_id': shippingCompanyId,
        if (clearingAgentId != null) 'p_new_clearing_agent_id': clearingAgentId,
      },
    );
    if (result is Map && result['success'] == true) {
      return Map<String, dynamic>.from(result);
    }
    throw Exception(
        result is Map ? result['error'] ?? 'فشل تعديل البند' : 'فشل تعديل البند');
  }
}
