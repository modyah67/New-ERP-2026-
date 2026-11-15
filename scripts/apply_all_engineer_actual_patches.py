# -*- coding: utf-8 -*-

def patch_file(file_path, replacements):
    with open(file_path, 'rb') as f:
        content = f.read().decode('utf-8')
    content_norm = content.replace('\r\n', '\n')
    
    for old, new, label in replacements:
        old_n = old.replace('\r\n', '\n')
        new_n = new.replace('\r\n', '\n')
        if old_n not in content_norm:
            print(f"FAILED to find {label} in {file_path}")
        else:
            content_norm = content_norm.replace(old_n, new_n, 1)
            print(f"SUCCESS: {label} in {file_path}")
            
    with open(file_path, 'wb') as f:
        f.write(content_norm.encode('utf-8'))

# 1. packing_order_dao.dart
dao_file = r'lib/data/dao/packing_order_dao.dart'
old_sync_row = """        rowsToInsert.add({
          'packing_order_id': orderId,
          'name': name,
          'category': mappedCategory,
          'report_category_id': reportCategoryId,
          'original_currency': originalCurrency,
          'original_amount': originalAmount,
          'exchange_rate': exchangeRate,
          'base_amount': baseAmount,
          'expected_amount': (item['expected_amount'] as num?)?.toDouble() ?? baseAmount,
          'cost_status': item['cost_status'] ?? 'expected',
          if (item['actual_amount'] != null) 'actual_amount': (item['actual_amount'] as num).toDouble(),
          if (item['variance_amount'] != null) 'variance_amount': (item['variance_amount'] as num).toDouble(),
          if (item['variance_journal_entry_id'] != null) 'variance_journal_entry_id': item['variance_journal_entry_id'],
          if (item['supplier_id'] != null) 'supplier_id': item['supplier_id'].toString(),
          'currency_snapshot': currencySnapshot,
          'payment_source_type': item['payment_source_type'],
          'payment_source_id': item['payment_source_id'],
          'allocation_method':
              item['allocation_method']?.toString() ?? 'BY_NET_WEIGHT',
          'target_line_id': item['target_line_id'],
          'settlement_notes': item['notes'] ?? item['settlement_notes'],
          if (item['engineer_name'] != null) 'engineer_name': item['engineer_name'],
          if (item['is_engineer_cost_settled'] != null) 'is_engineer_cost_settled': item['is_engineer_cost_settled'],
        });"""

new_sync_row = """        final bool isEng = item['category'] == 'engineer_expenses' ||
            item['category'] == 'engineer' ||
            item['supplier_type'] == 'engineer' ||
            name.toLowerCase().contains('مهندس') ||
            item['custody_id'] != null;
        final effectiveCostStatus = isEng ? 'actual' : (item['cost_status'] ?? 'expected');
        final effectiveActualAmount = isEng
            ? ((item['actual_amount'] as num?)?.toDouble() ?? baseAmount)
            : (item['actual_amount'] != null ? (item['actual_amount'] as num).toDouble() : null);

        rowsToInsert.add({
          'packing_order_id': orderId,
          'name': name,
          'category': mappedCategory,
          'report_category_id': reportCategoryId,
          'original_currency': originalCurrency,
          'original_amount': originalAmount,
          'exchange_rate': exchangeRate,
          'base_amount': baseAmount,
          'expected_amount': (item['expected_amount'] as num?)?.toDouble() ?? baseAmount,
          'cost_status': effectiveCostStatus,
          if (effectiveActualAmount != null) 'actual_amount': effectiveActualAmount,
          if (item['variance_amount'] != null) 'variance_amount': (item['variance_amount'] as num).toDouble(),
          if (item['variance_journal_entry_id'] != null) 'variance_journal_entry_id': item['variance_journal_entry_id'],
          if (item['supplier_id'] != null) 'supplier_id': item['supplier_id'].toString(),
          'currency_snapshot': currencySnapshot,
          'payment_source_type': item['payment_source_type'],
          'payment_source_id': item['payment_source_id'],
          'allocation_method':
              item['allocation_method']?.toString() ?? 'BY_NET_WEIGHT',
          'target_line_id': item['target_line_id'],
          'settlement_notes': item['notes'] ?? item['settlement_notes'],
          if (item['engineer_name'] != null || isEng) 'engineer_name': item['engineer_name'] ?? 'مجمع عهد الموظفين',
          'is_engineer_cost_settled': isEng ? true : (item['is_engineer_cost_settled'] ?? false),
        });"""

old_raw_return = """        return {
          'id': row['id'],
          'name': row['name'] as String,
          'category': row['category'] as String,
          'report_category_id': row['report_category_id'] as int?,
          'report_category_name': categoryName,
          'supplier_type': snapshot['supplier_type'],
          'item_uuid': snapshot['item_uuid'] ?? (row['id'] != null ? 'db_${row['id']}' : null),
          'category_name': snapshot['category_name'],
          'supplier_id': snapshot['supplier_id'],
          'supplier_name': snapshot['supplier_name'],
          'quantity': snapshot['quantity'] ?? 1.0,
          'unit_price': snapshot['unit_price'] ??
              (row['original_amount'] as num).toDouble(),
          'total': row['original_amount'] as num,
          'total_egp': row['base_amount'] as num,
          'exchange_rate': row['exchange_rate'] as num,
          'supplier_currency': row['original_currency'] as String,
          'payment_source_type': row['payment_source_type'],
          'payment_source_id': row['payment_source_id'],
          'treasury_transaction_id': row['treasury_transaction_id'],
          'bank_transaction_id': row['bank_transaction_id'],
          'allocation_method': row['allocation_method'] ??
              snapshot['allocation_method'] ??
              'BY_NET_WEIGHT',
          'target_line_id': row['target_line_id'],
          'target_line_index': snapshot['target_line_index'],
          'notes': snapshot['notes'] ?? row['settlement_notes'] ?? '',
          'settlement_notes': row['settlement_notes'] ?? snapshot['notes'] ?? '',
          'engineer_name': snapshot['engineer_name'] ?? row['engineer_name'],
          'is_engineer_cost_settled': snapshot['is_engineer_cost_settled'] ?? row['is_engineer_cost_settled'],
          'allocation_type': snapshot['allocation_type'],
          'allocation_percentage': snapshot['allocation_percentage'],
          'pool_total_spent': snapshot['pool_total_spent'],
          'pool_total_allocated': snapshot['pool_total_allocated'],
          'pool_remaining_pool': snapshot['pool_remaining_pool'],
        };"""

new_raw_return = """        final rName = (row['name'] as String? ?? '').toLowerCase();
        final sType = (snapshot['supplier_type']?.toString() ?? '').toLowerCase();
        final catStr = (row['category']?.toString() ?? '').toLowerCase();
        final bool isEng = sType == 'engineer' || catStr == 'engineer_expenses' || catStr == 'engineer' || rName.contains('مهندس') || snapshot['custody_id'] != null;
        final baseAmt = (row['base_amount'] as num).toDouble();
        final origAmt = (row['original_amount'] as num).toDouble();
        final costStatus = isEng ? 'actual' : (row['cost_status'] ?? 'expected');
        final actualAmt = isEng
            ? ((row['actual_amount'] as num?)?.toDouble() ?? baseAmt)
            : (row['actual_amount'] as num?)?.toDouble();
        final expAmt = (row['expected_amount'] as num?)?.toDouble() ?? baseAmt;

        return {
          'id': row['id'],
          'name': row['name'] as String,
          'category': isEng ? 'engineer_expenses' : (row['category'] as String),
          'report_category_id': row['report_category_id'] as int?,
          'report_category_name': categoryName,
          'supplier_type': isEng ? 'engineer' : snapshot['supplier_type'],
          'item_uuid': snapshot['item_uuid'] ?? (row['id'] != null ? 'db_${row['id']}' : null),
          'category_name': isEng ? 'مصاريف مهندسين وإشراف' : snapshot['category_name'],
          'supplier_id': snapshot['supplier_id'],
          'supplier_name': isEng ? 'مجمع عهد الموظفين' : snapshot['supplier_name'],
          'quantity': snapshot['quantity'] ?? 1.0,
          'unit_price': snapshot['unit_price'] ?? origAmt,
          'total': row['original_amount'] as num,
          'total_egp': row['base_amount'] as num,
          'exchange_rate': row['exchange_rate'] as num,
          'supplier_currency': row['original_currency'] as String,
          'payment_source_type': row['payment_source_type'],
          'payment_source_id': row['payment_source_id'],
          'treasury_transaction_id': row['treasury_transaction_id'],
          'bank_transaction_id': row['bank_transaction_id'],
          'allocation_method': row['allocation_method'] ??
              snapshot['allocation_method'] ??
              'BY_NET_WEIGHT',
          'target_line_id': row['target_line_id'],
          'target_line_index': snapshot['target_line_index'],
          'notes': snapshot['notes'] ?? row['settlement_notes'] ?? '',
          'settlement_notes': row['settlement_notes'] ?? snapshot['notes'] ?? '',
          'cost_status': costStatus,
          'expected_amount': expAmt,
          'actual_amount': actualAmt,
          'variance_amount': (row['variance_amount'] as num?)?.toDouble() ?? 0.0,
          'variance_journal_entry_id': row['variance_journal_entry_id'],
          'settlement_journal_entry_id': row['settlement_journal_entry_id'],
          'journal_entry_id': row['journal_entry_id'],
          'engineer_name': snapshot['engineer_name'] ?? row['engineer_name'] ?? (isEng ? 'مجمع عهد الموظفين' : null),
          'is_engineer_cost_settled': isEng ? true : (snapshot['is_engineer_cost_settled'] ?? row['is_engineer_cost_settled'] ?? false),
          'allocation_type': snapshot['allocation_type'],
          'allocation_percentage': snapshot['allocation_percentage'],
          'pool_total_spent': snapshot['pool_total_spent'],
          'pool_total_allocated': snapshot['pool_total_allocated'],
          'pool_remaining_pool': snapshot['pool_remaining_pool'],
        };"""

patch_file(dao_file, [
    (old_sync_row, new_sync_row, "dao_sync_row"),
    (old_raw_return, new_raw_return, "dao_raw_return")
])

# 2. packing_cost_variance_service.dart
var_file = r'lib/data/services/packing_cost_variance_service.dart'
old_var_settled = """          // Check if the cost item has been actually settled
          final costItemStatus = c['cost_status']?.toString();
          final double? actualAmount = (c['actual_amount'] as num?)?.toDouble();
          final bool isEngineerSettled = (isEngineer && (c['is_engineer_cost_settled'] == true || costItemStatus == 'actual')) ||
              (isEngineer && actualAmount != null && actualAmount > 0);
          final bool isSettledActual = (costItemStatus == 'actual' && actualAmount != null) ||
              (c['settled_actual'] == true && actualAmount != null) ||
              (c['variance_journal_entry_id'] != null && actualAmount != null) ||
              isEngineerSettled ||
              (actualAmount != null && actualAmount > 0 && costItemStatus != 'expected' && costItemStatus != 'estimated') ||
              isTransport; // Transport cost items are directly actual by design

          final double totalAmount = ((c['total_egp'] ?? c['total'] ?? c['base_amount'] ?? 0) as num).toDouble();
          final double expectedAmount = (c['expected_amount'] as num?)?.toDouble() ?? 0.0;

          // For Transport: directly entered cost is both base estimate and actual
          // For Others: expected_amount is the preserved original estimate.
          final double estAmount = isTransport
              ? (expectedAmount > 0 ? expectedAmount : totalAmount)
              : (((isStationOrDeduction || isEngineer) && expectedAmount > 0)
                  ? expectedAmount
                  : (expectedAmount > 0 ? expectedAmount : totalAmount));

          final int? costItemId = (c['id'] as num?)?.toInt();

          // ── 1. If item has been settled OR is Transport: ALWAYS fullyActual across all environments and stages ──
          if (isSettledActual || isTransport) {
            final double netActual = isTransport
                ? ((actualAmount != null && actualAmount > 0)
                    ? actualAmount
                    : (totalAmount > 0 ? totalAmount : expectedAmount))
                : (isEngineerSettled
                    ? (actualAmount ?? (estAmount > 0 ? estAmount : totalAmount))
                    : actualAmount!);
            final double baseEstimate = isTransport
                ? (expectedAmount > 0 ? expectedAmount : netActual)
                : estAmount;
            final double diff = isTransport ? 0.0 : (netActual - baseEstimate);
            final double? pct = (isTransport || baseEstimate <= 0) ? null : (diff / baseEstimate * 100);

            String settledSource;
            if (isEngineer) {
              settledSource = c['variance_journal_entry_id'] != null
                  ? 'قيد تسوية عهدة مهندس #'
                  : (c['pool_remaining_pool'] != null || c['allocation_type'] != null || c['is_engineer_cost_settled'] == true
                      ? 'مجمع عهد الموظفين (محمل فعلياً)'
                      : 'تسوية عهدة مهندس معتمدة');
            }"""

new_var_settled = """          // Check if the cost item has been actually settled
          final costItemStatus = c['cost_status']?.toString();
          final double? actualAmount = (c['actual_amount'] as num?)?.toDouble();
          // Engineer custody pool expenses are already disbursed actual cash, ALWAYS actual
          final bool isEngineerSettled = isEngineer;
          final bool isSettledActual = isEngineer ||
              (costItemStatus == 'actual' && actualAmount != null) ||
              (c['settled_actual'] == true && actualAmount != null) ||
              (c['variance_journal_entry_id'] != null && actualAmount != null) ||
              (actualAmount != null && actualAmount > 0 && costItemStatus != 'expected' && costItemStatus != 'estimated') ||
              isTransport; // Transport cost items are directly actual by design

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
            }"""

patch_file(var_file, [
    (old_var_settled, new_var_settled, "var_settled")
])

# 3. packing_order_details_dialog.dart
dlg_file = r'lib/features/packing/packing_order_details_dialog.dart'
old_dlg_eng = """        final isEngineer = suppType == 'engineer' ||
            cat == 'engineer_expenses' ||
            cat == 'engineer' ||
            rName.contains('مهندس') ||
            c['custody_id'] != null;
        final engSettled = c['is_engineer_cost_settled'] == true || (isEngineer && isActual);"""

new_dlg_eng = """        final isEngineer = suppType == 'engineer' ||
            cat == 'engineer_expenses' ||
            cat == 'engineer' ||
            rName.contains('مهندس') ||
            c['custody_id'] != null;
        final engSettled = isEngineer || c['is_engineer_cost_settled'] == true || (isEngineer && isActual);"""

patch_file(dlg_file, [
    (old_dlg_eng, new_dlg_eng, "dlg_eng")
])

# 4. packing_order_form_page.dart (remaining action text)
old_form_action = """Text(
                                                   'تمت التسوية',
                                                   style: TextStyle(
                                                     color: AppTheme.success,
                                                     fontSize: 11,
                                                     fontWeight: FontWeight.bold,
                                                     fontFamily: 'Cairo',
                                                   ),
                                                 ),"""

new_form_action = """Text(
                                                   isEngineer ? 'محمل فعلياً من العهد' : 'تمت التسوية',
                                                   style: const TextStyle(
                                                     color: AppTheme.success,
                                                     fontSize: 11,
                                                     fontWeight: FontWeight.bold,
                                                     fontFamily: 'Cairo',
                                                   ),
                                                 ),"""

patch_file(r'lib/features/packing/packing_order_form_page.dart', [
    (old_form_action, new_form_action, "form_action_text")
])

print("Finished applying all patches!")

