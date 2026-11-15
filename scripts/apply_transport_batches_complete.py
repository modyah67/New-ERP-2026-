# -*- coding: utf-8 -*-
import sys

with open('lib/features/packing/packing_order_form_page.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# -------------------------------------------------------------------------
# Part A: Patch _addCostItem()
# -------------------------------------------------------------------------

# 1. Variables in _addCostItem
target_vars_add = """    int? selectedCategoryId =
        _costCategories.isNotEmpty ? _costCategories.first['id'] as int? : null;"""

repl_vars_add = """    int? selectedCategoryId =
        _costCategories.isNotEmpty ? _costCategories.first['id'] as int? : null;

    List<TransportBatchModel> transportBatches = [];
    TransportBatchModel? selectedTransportBatch;
    bool isLoadingBatches = false;
    String? lastLoadedTransportId;"""

if target_vars_add in content:
    content = content.replace(target_vars_add, repl_vars_add, 1)
    print("Part A.1: Added batch state variables in _addCostItem")
else:
    print("Error A.1: target_vars_add not found")

# 2. Define loadTransportBatches in _addCostItem StatefulBuilder
target_load_add = """          void loadCustodyDetails(String? cId) async {"""

repl_load_add = """          void loadTransportBatches(String? suppId) async {
            if (suppId == null || suppId.isEmpty) return;
            final sId = int.tryParse(suppId);
            if (sId == null) return;
            lastLoadedTransportId = suppId;
            setDialogState(() => isLoadingBatches = true);
            try {
              final currentOrdId = int.tryParse(_currentOrder?.id ?? widget.existingOrder?.id ?? '');
              final batches = await TransportSupplierDao().getEntitlementBatches(
                sId,
                excludePackingOrderId: currentOrdId,
              );
              if (ctx.mounted) {
                setDialogState(() {
                  transportBatches = batches;
                  isLoadingBatches = false;
                  if (selectedTransportBatch == null && batches.isNotEmpty) {
                    final withBal = batches.where((b) => b.availableTrucks > 0).toList();
                    selectedTransportBatch = withBal.isNotEmpty ? withBal.first : batches.first;
                    if (qtyCtrl.text.trim().isEmpty) {
                      final defaultQty = selectedTransportBatch!.availableTrucks >= 1 ? 1.0 : (selectedTransportBatch!.availableTrucks > 0 ? selectedTransportBatch!.availableTrucks : 1.0);
                      qtyCtrl.text = defaultQty % 1 == 0 ? defaultQty.toInt().toString() : defaultQty.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\\.$'), '');
                    }
                    final currentQty = double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.')) ?? 1.0;
                    final autoCost = currentQty * selectedTransportBatch!.costPerTruck;
                    priceCtrl.text = autoCost % 1 == 0 ? autoCost.toInt().toString() : autoCost.toStringAsFixed(2);
                  }
                });
              }
            } catch (e) {
              if (ctx.mounted) {
                setDialogState(() => isLoadingBatches = false);
              }
            }
          }

          void loadCustodyDetails(String? cId) async {"""

if target_load_add in content:
    content = content.replace(target_load_add, repl_load_add, 1)
    print("Part A.2: Added loadTransportBatches in _addCostItem")
else:
    print("Error A.2: target_load_add not found")

# 3. Post-frame trigger & canSubmit in _addCostItem
target_trigger_add = """          if (isEngineer && selectedSupplierId != null && !isLoadingCustodyBal && lastLoadedCustodyId != selectedSupplierId) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              loadCustodyDetails(selectedSupplierId);
            });
          }"""

repl_trigger_add = """          if (isEngineer && selectedSupplierId != null && !isLoadingCustodyBal && lastLoadedCustodyId != selectedSupplierId) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              loadCustodyDetails(selectedSupplierId);
            });
          }

          if (isTransport && selectedSupplierId != null && !isLoadingBatches && lastLoadedTransportId != selectedSupplierId) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              loadTransportBatches(selectedSupplierId);
            });
          }"""

if target_trigger_add in content:
    content = content.replace(target_trigger_add, repl_trigger_add, 1)
    print("Part A.3: Added post-frame batch trigger in _addCostItem")
else:
    print("Error A.3: target_trigger_add not found")

# 4. canSubmit in _addCostItem
target_cansubmit_add = """          final canSubmit = name.isNotEmpty &&
              (isAdmin || isEngineer
                  ? price > 0
                  : (isTransport ? (price > 0 && qty >= 0) : (qty > 0 && price > 0))) &&
              (isAdmin || selectedSupplierId != null) &&
              (!isEngineer || selectedExpenseAccountId != null) &&
              (supplierCurrency == 'EGP' || rate > 0) &&
              (paymentSourceType == 'none' || isEngineer ||
                  selectedPaymentSourceId != null) &&
              !isInsufficientBalance;"""

repl_cansubmit_add = """          final isBatchQtyValid = !isTransport || selectedTransportBatch == null || (qty > 0 && qty <= (selectedTransportBatch!.availableTrucks + 0.0001));
          final canSubmit = name.isNotEmpty &&
              (isAdmin || isEngineer
                  ? price > 0
                  : (isTransport ? (price > 0 && qty > 0 && isBatchQtyValid) : (qty > 0 && price > 0))) &&
              (isAdmin || selectedSupplierId != null) &&
              (!isEngineer || selectedExpenseAccountId != null) &&
              (supplierCurrency == 'EGP' || rate > 0) &&
              (paymentSourceType == 'none' || isEngineer ||
                  selectedPaymentSourceId != null) &&
              !isInsufficientBalance;"""

if target_cansubmit_add in content:
    content = content.replace(target_cansubmit_add, repl_cansubmit_add, 1)
    print("Part A.4: Updated canSubmit with batch quantity validation in _addCostItem")
else:
    print("Error A.4: target_cansubmit_add not found")

# 5. onSelected for transport supplier in _addCostItem
target_onsel_add = """                              // Auto-fill cost item name if empty or generic
                              final currentName = nameCtrl.text.trim();
                              if (currentName.isEmpty ||
                                  currentName.startsWith('مصاريف نقل') ||
                                  currentName == 'نقل' ||
                                  currentName == 'نقل بضاعة') {
                                nameCtrl.text = s.name.isNotEmpty
                                    ? 'مصاريف نقل - ${s.name}'
                                    : 'نقل بضاعة';
                              }
                            });"""

repl_onsel_add = """                              selectedTransportBatch = null;
                              lastLoadedTransportId = null;

                              // Auto-fill cost item name if empty or generic
                              final currentName = nameCtrl.text.trim();
                              if (currentName.isEmpty ||
                                  currentName.startsWith('مصاريف نقل') ||
                                  currentName == 'نقل' ||
                                  currentName == 'نقل بضاعة') {
                                nameCtrl.text = s.name.isNotEmpty
                                    ? 'مصاريف نقل - ${s.name}'
                                    : 'نقل بضاعة';
                              }
                            });
                            loadTransportBatches(s.id?.toString());"""

if target_onsel_add in content:
    content = content.replace(target_onsel_add, repl_onsel_add, 1)
    print("Part A.5: Updated onSelected for transport in _addCostItem")
else:
    print("Error A.5: target_onsel_add not found")

# 6. Render _buildTransportBatchSection under transport overview in _addCostItem
target_trans_card_end_add = """                                           if (transSupplier.truckBalance <= 0) ...[
                                             const SizedBox(height: 8),
                                             Container(
                                               padding: const EdgeInsets.all(8),
                                               decoration: BoxDecoration(
                                                 color: AppTheme.warning.withAlpha(20),
                                                 borderRadius: BorderRadius.circular(6),
                                                 border: Border.all(
                                                     color: AppTheme.warning.withAlpha(60)),
                                               ),
                                               child: const Row(
                                                 children: [
                                                   Icon(Icons.info_outline,
                                                       color: AppTheme.warning, size: 14),
                                                   SizedBox(width: 6),
                                                   Expanded(
                                                     child: Text(
                                                       'ملاحظة: لا يوجد رصيد نقلات متاح مسبقاً. سيتم تسجيل استهلاك نقلة وتحميلها على أمر التعبئة دون ازدواج مالي.',
                                                       style: TextStyle(
                                                         color: AppTheme.warning,
                                                         fontFamily: 'Cairo',
                                                         fontSize: 10,
                                                       ),
                                                     ),
                                                   ),
                                                 ],
                                               ),
                                             ),
                                           ],
                                         ],
                                       ),
                                     );
                                   },
                                 )"""

repl_trans_card_end_add = """                                           if (transSupplier.truckBalance <= 0) ...[
                                             const SizedBox(height: 8),
                                             Container(
                                               padding: const EdgeInsets.all(8),
                                               decoration: BoxDecoration(
                                                 color: AppTheme.warning.withAlpha(20),
                                                 borderRadius: BorderRadius.circular(6),
                                                 border: Border.all(
                                                     color: AppTheme.warning.withAlpha(60)),
                                               ),
                                               child: const Row(
                                                 children: [
                                                   Icon(Icons.info_outline,
                                                       color: AppTheme.warning, size: 14),
                                                   SizedBox(width: 6),
                                                   Expanded(
                                                     child: Text(
                                                       'ملاحظة: لا يوجد رصيد نقلات متاح مسبقاً. سيتم تسجيل استهلاك نقلة وتحميلها على أمر التعبئة دون ازدواج مالي.',
                                                       style: TextStyle(
                                                         color: AppTheme.warning,
                                                         fontFamily: 'Cairo',
                                                         fontSize: 10,
                                                       ),
                                                     ),
                                                   ),
                                                 ],
                                               ),
                                             ),
                                           ],
                                           _buildTransportBatchSection(
                                             isDark: isDark,
                                             isLoadingBatches: isLoadingBatches,
                                             batches: transportBatches,
                                             selectedBatch: selectedTransportBatch,
                                             onBatchChanged: (newB) {
                                               setDialogState(() {
                                                 selectedTransportBatch = newB;
                                                 if (newB != null) {
                                                   final q = double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.')) ?? 1.0;
                                                   final autoCost = q * newB.costPerTruck;
                                                   priceCtrl.text = autoCost % 1 == 0 ? autoCost.toInt().toString() : autoCost.toStringAsFixed(2);
                                                 }
                                               });
                                             },
                                             onSelectQuickQty: (q) {
                                               setDialogState(() {
                                                 qtyCtrl.text = q % 1 == 0 ? q.toInt().toString() : q.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\\.$'), '');
                                                 if (selectedTransportBatch != null) {
                                                   final autoCost = q * selectedTransportBatch!.costPerTruck;
                                                   priceCtrl.text = autoCost % 1 == 0 ? autoCost.toInt().toString() : autoCost.toStringAsFixed(2);
                                                 }
                                               });
                                             },
                                           ),
                                         ],
                                       ),
                                     );
                                   },
                                 )"""

if target_trans_card_end_add in content:
    content = content.replace(target_trans_card_end_add, repl_trans_card_end_add, 1)
    print("Part A.6: Inserted _buildTransportBatchSection into transport card in _addCostItem")
else:
    print("Error A.6: target_trans_card_end_add not found")

# 7. Qty onChanged and dynamic calculation in _addCostItem
target_qty_add = """                      TextField(
                        controller: qtyCtrl,
                        decoration: _inputDecoration(
                                isTransport
                                    ? 'عدد النقلات المستهلكة (الكمية)'
                                    : 'الكمية')
                            .copyWith(
                          helperText: isTransport
                              ? 'تُخصم من مخزون نقلات المورد فقط (يدعم 0.5، 1.5 نقلة)'
                              : null,
                          helperStyle: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppTheme.accent : const Color(0xFF0284C7)),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\\d*\\.?\\d*$'))
                        ],
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            fontSize: 15),
                        onChanged: (_) => setDialogState(() {}),
                      ),"""

repl_qty_add = """                      TextField(
                        controller: qtyCtrl,
                        decoration: _inputDecoration(
                                isTransport
                                    ? 'عدد النقلات المسحوبة من الدفعة (مثال: 0.5، 1، 1.5) *'
                                    : 'الكمية')
                            .copyWith(
                          helperText: isTransport
                              ? (selectedTransportBatch != null
                                  ? 'تكلفة النقلة بالدفعة: ${selectedTransportBatch!.formattedCostPerTruck} ج.م (المتاح: ${selectedTransportBatch!.formattedAvailableTrucks} نقلة)'
                                  : 'تُخصم من مخزون نقلات المورد (يدعم 0.5، 1.5 نقلة)')
                              : null,
                          helperStyle: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppTheme.accent : const Color(0xFF0284C7)),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\\d*\\.?\\d*$'))
                        ],
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            fontSize: 15),
                        onChanged: (_) {
                          if (isTransport && selectedTransportBatch != null) {
                            final q = double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.')) ?? 0.0;
                            if (q > 0) {
                              final autoCost = q * selectedTransportBatch!.costPerTruck;
                              priceCtrl.text = autoCost % 1 == 0 ? autoCost.toInt().toString() : autoCost.toStringAsFixed(2);
                            }
                          }
                          setDialogState(() {});
                        },
                      ),
                      if (isTransport && selectedTransportBatch != null) ...[
                        const SizedBox(height: 6),
                        Builder(
                          builder: (_) {
                            final q = double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.')) ?? 0.0;
                            final isOver = q > (selectedTransportBatch!.availableTrucks + 0.0001);
                            final rem = (selectedTransportBatch!.availableTrucks - q).clamp(0.0, double.infinity);
                            if (isOver) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppTheme.danger.withAlpha(25),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppTheme.danger.withAlpha(80)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline, color: AppTheme.danger, size: 16),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'تنبيه: الكمية المطلوبة ($q نقلة) تتجاوز الرصيد المتاح في هذه الدفعة (${selectedTransportBatch!.formattedAvailableTrucks} نقلة)!',
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.danger,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.success.withAlpha(20),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppTheme.success.withAlpha(60)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle_outline, color: AppTheme.success, size: 16),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'الحسبة: $q نقلة × ${selectedTransportBatch!.formattedCostPerTruck} ج.م = ${(q * selectedTransportBatch!.costPerTruck).toStringAsFixed(2)} ج.م | المتبقي في الدفعة: ${rem % 1 == 0 ? rem.toInt() : rem.toStringAsFixed(2)} نقلة',
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.success,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],"""

if target_qty_add in content:
    content = content.replace(target_qty_add, repl_qty_add, 1)
    print("Part A.7: Updated qtyCtrl and dynamic calculation breakdown in _addCostItem")
else:
    print("Error A.7: target_qty_add not found")

# 8. Save batch info into _costItems in _addCostItem
target_save_add = """                            'transport_supplier_id': effectiveTransportSupplierId,
                            'truck_count': effectiveTruckCount,"""

repl_save_add = """                            'transport_supplier_id': effectiveTransportSupplierId,
                            'truck_count': effectiveTruckCount,
                            'transport_batch_id': isTransport ? selectedTransportBatch?.id : null,
                            'transport_batch_desc': isTransport ? selectedTransportBatch?.description : null,
                            'transport_batch_cost_per_truck': isTransport ? selectedTransportBatch?.costPerTruck : null,
                            'transport_batch_ref': isTransport ? selectedTransportBatch?.referenceId : null,
                            'transport_batch_available': isTransport ? selectedTransportBatch?.availableTrucks : null,"""

if target_save_add in content:
    content = content.replace(target_save_add, repl_save_add, 1)
    print("Part A.8: Included batch fields in _costItems.add in _addCostItem")
else:
    print("Error A.8: target_save_add not found")

with open('lib/features/packing/packing_order_form_page.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print("Finished Part A successfully")

