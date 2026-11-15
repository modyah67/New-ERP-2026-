# -*- coding: utf-8 -*-
import os

# =====================================================================
# 1. Patch lib/data/dao/packing_order_dao.dart
# =====================================================================
dao_file = r'lib/data/dao/packing_order_dao.dart'
with open(dao_file, 'rb') as f:
    dao_text = f.read().decode('utf-8')

# 1a. In _syncCostItemsToTable preparation of rowsToInsert
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

# 1b. In getCostItemsRaw
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

def safe_replace(content, old, new, label):
    old_n = old.replace('\r\n', '\n')
    new_n = new.replace('\r\n', '\n')
    if old_n not in content:
        print(f"FAILED to find {label}")
        return content, False
    content = content.replace(old_n, new_n, 1)
    print(f"SUCCESS: {label}")
    return content, True

dao_text, ok_d1 = safe_replace(dao_text, old_sync_row, new_sync_row, "dao_sync_row")
dao_text, ok_d2 = safe_replace(dao_text, old_raw_return, new_raw_return, "dao_raw_return")
with open(dao_file, 'wb') as f:
    f.write(dao_text.encode('utf-8'))


# =====================================================================
# 2. Patch lib/data/services/packing_cost_variance_service.dart
# =====================================================================
var_file = r'lib/data/services/packing_cost_variance_service.dart'
with open(var_file, 'rb') as f:
    var_text = f.read().decode('utf-8')

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

var_text, ok_v1 = safe_replace(var_text, old_var_settled, new_var_settled, "var_settled")

with open(var_file, 'wb') as f:
    f.write(var_text.encode('utf-8'))


# =====================================================================
# 3. Patch lib/features/packing/packing_order_form_page.dart
# =====================================================================
form_file = r'lib/features/packing/packing_order_form_page.dart'
with open(form_file, 'rb') as f:
    form_text = f.read().decode('utf-8')

# 3a. In _buildCostItemCard: isEngineerSettled check
old_card_settled = """          final isEngineerSettled = item['is_engineer_cost_settled'] == true ||
              (isEngineerItem && item['cost_status'] == 'actual' && item['actual_amount'] != null);"""

new_card_settled = """          final isEngineerSettled = isEngineerItem ||
              item['is_engineer_cost_settled'] == true ||
              (isEngineerItem && item['cost_status'] == 'actual' && item['actual_amount'] != null);"""

# 3b. Badge for engineer item in cost item card
old_card_badge = """                          if (isEngineerItem) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isEngineerSettled
                                    ? AppTheme.success.withAlpha(25)
                                    : const Color(0xFFF59E0B).withAlpha(25),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isEngineerSettled
                                      ? AppTheme.success.withAlpha(80)
                                      : const Color(0xFFF59E0B).withAlpha(80),
                                ),
                              ),
                              child: Text(
                                isEngineerSettled ? 'تمت التسوية الفعلية ✓' : 'عهدة تقديرية ⏳',
                                style: TextStyle(
                                  color: isEngineerSettled
                                      ? AppTheme.success
                                      : const Color(0xFFF59E0B),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ]"""

new_card_badge = """                          if (isEngineerItem) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.success.withAlpha(25),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.success.withAlpha(80)),
                              ),
                              child: const Text(
                                'تكلفة فعلية من العهد ✓',
                                style: TextStyle(
                                  color: AppTheme.success,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ]"""

# 3c. Amount display in card for engineer
old_card_amt = """                else if (isEngineerItem && !isEngineerSettled)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${(item['expected_amount'] != null ? (item['expected_amount'] as num).toDouble() : totalEgp).toStringAsFixed(2)} ج.م',
                          style: TextStyle(
                              color: isDark ? AppTheme.accent : const Color(0xFF0284C7),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo')),
                      const Text('عهدة تقديرية',
                          style: TextStyle(
                              color: Color(0xFFF59E0B),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo')),
                    ],
                  )
                else if (isEngineerItem && isEngineerSettled)
                  Builder(builder: (_) {
                    final actualAmt = (item['actual_amount'] as num?)?.toDouble() ?? totalEgp;
                    final expectedAmt = item['expected_amount'] != null
                        ? (item['expected_amount'] as num).toDouble()
                        : totalEgp;
                    final varianceAmt = actualAmt - expectedAmt;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('${actualAmt.toStringAsFixed(2)} ج.م',
                            style: TextStyle(
                                color: isDark ? AppTheme.accent : const Color(0xFF0284C7),
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo')),
                        Text('التقديري: ${expectedAmt.toStringAsFixed(2)} ج.م',
                            style: TextStyle(
                                color: isDark ? AppTheme.textMuted : Colors.black54,
                                fontSize: 10,
                                fontFamily: 'Cairo')),
                        if (varianceAmt.abs() > 0.01)
                          Text(
                            'فرق العهدة: ${varianceAmt > 0 ? "+" : ""}${varianceAmt.toStringAsFixed(2)} ج.م',
                            style: TextStyle(
                              color: varianceAmt > 0 ? AppTheme.danger : AppTheme.success,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                      ],
                    );
                  })"""

new_card_amt = """                else if (isEngineerItem)
                  Builder(builder: (_) {
                    final actualAmt = (item['actual_amount'] as num?)?.toDouble() ?? totalEgp;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('${actualAmt.toStringAsFixed(2)} ج.م',
                            style: TextStyle(
                                color: isDark ? AppTheme.accent : const Color(0xFF0284C7),
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo')),
                        const Text('تكلفة فعلية محملة من العهد ✓',
                            style: TextStyle(
                                color: AppTheme.success,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo')),
                      ],
                    );
                  })"""

# 3d. Comparison table: isSettledCost for engineer
old_tbl_settled = """                  final bool isSettlableCost = category != 'fruit' && category != 'material' && !isTransport && !isAdmin;
                  final int costId = item.costItemId ?? name.hashCode;

                  final bool isSettledCost = isSettlableCost &&
                      (item.status == PackingCostStatus.fullyActual || item.hasActualCost) &&
                      !_adminForceEditingIds.contains(costId);"""

new_tbl_settled = """                  final bool isSettlableCost = category != 'fruit' && category != 'material' && !isTransport && !isAdmin;
                  final int costId = item.costItemId ?? name.hashCode;

                  final bool isSettledCost = isEngineer || (isSettlableCost &&
                      (item.status == PackingCostStatus.fullyActual || item.hasActualCost) &&
                      !_adminForceEditingIds.contains(costId));"""

# 3e. Comparison table: column 3 (estimated cost) for engineer
old_tbl_est = """                      // 3. التقديري
                      DataCell(
                        Text(
                          isTransport
                              ? (item.estimatedCost > 0
                                  ? item.estimatedCost.toStringAsFixed(2)
                                  : (item.actualCost?.toStringAsFixed(2) ?? '0.00'))
                              : item.estimatedCost.toStringAsFixed(2),"""

new_tbl_est = """                      // 3. التقديري
                      DataCell(
                        Text(
                          (isTransport || isEngineer)
                              ? (item.actualCost?.toStringAsFixed(2) ?? item.estimatedCost.toStringAsFixed(2))
                              : item.estimatedCost.toStringAsFixed(2),"""

# 3f. Comparison table: column 8 (source/doc)
old_tbl_src = """                                        isSettledCost
                                            ? (item.source.isNotEmpty ? item.source : 'تسوية فعلية معتمدة')
                                            : (isTransport ? 'تكلفة نقل (فعلي فقط - بانتظار التسوية)' : 'تقديري - بانتظار التسوية'),"""

new_tbl_src = """                                        isEngineer
                                            ? (item.source.isNotEmpty ? item.source : 'مجمع عهد الموظفين (تكلفة فعلية منصرفة ومحملة)')
                                            : (isSettledCost
                                                ? (item.source.isNotEmpty ? item.source : 'تسوية فعلية معتمدة')
                                                : (isTransport ? 'تكلفة نقل (فعلي فقط - بانتظار التسوية)' : 'تقديري - بانتظار التسوية')),"""

# 3g. Comparison table: column 9 (action button / status)
old_tbl_action = """                                          Container(
                                             padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                             decoration: BoxDecoration(
                                               color: AppTheme.success.withValues(alpha: 0.12),
                                               borderRadius: BorderRadius.circular(6),
                                               border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
                                             ),
                                             child: const Row(
                                               mainAxisSize: MainAxisSize.min,
                                               children: [
                                                 Icon(Icons.check, size: 12, color: AppTheme.success),
                                                 SizedBox(width: 4),
                                                 Text(
                                                   'تمت التسوية',
                                                   style: TextStyle(
                                                     color: AppTheme.success,
                                                     fontSize: 11,
                                                     fontWeight: FontWeight.bold,
                                                     fontFamily: 'Cairo',
                                                   ),
                                                 ),
                                               ],
                                             ),
                                           ),"""

new_tbl_action = """                                          Container(
                                             padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                             decoration: BoxDecoration(
                                               color: AppTheme.success.withValues(alpha: 0.12),
                                               borderRadius: BorderRadius.circular(6),
                                               border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
                                             ),
                                             child: Row(
                                               mainAxisSize: MainAxisSize.min,
                                               children: [
                                                 const Icon(Icons.check, size: 12, color: AppTheme.success),
                                                 const SizedBox(width: 4),
                                                 Text(
                                                   isEngineer ? 'محمل فعلياً من العهد' : 'تمت التسوية',
                                                   style: const TextStyle(
                                                     color: AppTheme.success,
                                                     fontSize: 11,
                                                     fontWeight: FontWeight.bold,
                                                     fontFamily: 'Cairo',
                                                   ),
                                                 ),
                                               ],
                                             ),
                                           ),"""

form_text, ok_f1 = safe_replace(form_text, old_card_settled, new_card_settled, "form_card_settled")
form_text, ok_f2 = safe_replace(form_text, old_card_badge, new_card_badge, "form_card_badge")
form_text, ok_f3 = safe_replace(form_text, old_card_amt, new_card_amt, "form_card_amt")
form_text, ok_f4 = safe_replace(form_text, old_tbl_settled, new_tbl_settled, "form_tbl_settled")
form_text, ok_f5 = safe_replace(form_text, old_tbl_est, new_tbl_est, "form_tbl_est")
form_text, ok_f6 = safe_replace(form_text, old_tbl_src, new_tbl_src, "form_tbl_src")
form_text, ok_f7 = safe_replace(form_text, old_tbl_action, new_tbl_action, "form_tbl_action")

with open(form_file, 'wb') as f:
    f.write(form_text.encode('utf-8'))

print("Completed patch_engineer_actual.py")

