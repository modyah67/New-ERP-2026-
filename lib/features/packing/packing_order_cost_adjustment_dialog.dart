import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models/packing_order_model.dart';
import '../../data/models/packing_order_line_model.dart';
import '../../data/dao/packing_order_dao.dart';
import '../../data/dao/lot_dao.dart';
import '../../data/models/lot_model.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/models/supplier_model.dart';

class PackingOrderCostAdjustmentDialog extends StatefulWidget {
  final PackingOrderModel order;
  final VoidCallback? onUpdated;

  const PackingOrderCostAdjustmentDialog({
    super.key,
    required this.order,
    this.onUpdated,
  });

  @override
  State<PackingOrderCostAdjustmentDialog> createState() =>
      _PackingOrderCostAdjustmentDialogState();
}

class _PackingOrderCostAdjustmentDialogState
    extends State<PackingOrderCostAdjustmentDialog> {
  final _dao = PackingOrderDao();
  final _lotDao = LotDao();
  final _supplierDao = SupplierDao();
  late PackingOrderModel _order;
  LotReceiptModel? _lot;
  bool _loading = false;
  List<Map<String, dynamic>> _materials = [];
  List<SupplierModel> _allSuppliers = [];

  final Map<String, LotReceiptModel> _lineLots = {};

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _parseNotes();
    _loadLot();
  }

  Future<void> _loadLot() async {
    try {
      try {
        _allSuppliers = await _supplierDao.getAll(limit: 2000);
      } catch (e) {
        debugPrint('Error loading suppliers in adjustment dialog: $e');
      }

      final orderId = int.tryParse(_order.id ?? '0') ?? 0;
      if (orderId > 0) {
        final dbLines = await _dao.getLines(orderId);
        if (dbLines.isNotEmpty && mounted) {
          _order = _order.copyWith(lines: dbLines);
        }
      }

      if (_order.lotId.isNotEmpty) {
        final lot = await _lotDao.getById(_order.lotId);
        if (mounted && lot != null) {
          _lot = lot;
          _lineLots[_order.lotId] = lot;
        }
      }
      for (final line in _order.lines) {
        final lid = line.sourceLotId;
        if (lid != null && lid.isNotEmpty && !_lineLots.containsKey(lid)) {
          final lot = await _lotDao.getById(lid);
          if (lot != null) {
            _lineLots[lid] = lot;
          }
        }
      }

      // Automatically enrich packaging materials with linked suppliers
      await _enrichMaterialsWithSuppliers();

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading lot in adjustment dialog: $e');
    }
  }

  Future<void> _enrichMaterialsWithSuppliers() async {
    bool hasUpdates = false;

    // 1. Determine the linked supplier of this packing order
    String? orderSupplierName = _lot?.supplierName ?? _order.supplierName;
    String? orderSupplierId = _lot?.supplierId;

    if (orderSupplierName == null || orderSupplierName.isEmpty || orderSupplierName == 'غير محدد') {
      for (final l in _lineLots.values) {
        if (l.supplierName != null && l.supplierName!.trim().isNotEmpty && l.supplierName != 'غير محدد') {
          orderSupplierName = l.supplierName!.trim();
          orderSupplierId = l.supplierId;
          break;
        }
      }
    }

    // Check notes for cost_items supplier
    if ((orderSupplierName == null || orderSupplierName.isEmpty || orderSupplierName == 'غير محدد') && _order.notes != null) {
      try {
        final parsedNotes = jsonDecode(_order.notes!);
        if (parsedNotes is Map && parsedNotes['cost_items'] is List) {
          for (final ci in parsedNotes['cost_items']) {
            if (ci is Map && ci['supplier_name'] != null) {
              final s = ci['supplier_name'].toString().trim();
              if (s.isNotEmpty && s != 'غير محدد') {
                orderSupplierName = s;
                orderSupplierId = ci['supplier_id']?.toString();
                break;
              }
            }
          }
        }
      } catch (_) {}
    }

    // If only 1 supplier exists in the system, default to it
    if ((orderSupplierName == null || orderSupplierName.isEmpty || orderSupplierName == 'غير محدد') && _allSuppliers.length == 1) {
      orderSupplierName = _allSuppliers.first.name.trim();
      orderSupplierId = _allSuppliers.first.id;
    }

    // Resolve orderSupplierId if missing
    if ((orderSupplierId == null || orderSupplierId.isEmpty) && orderSupplierName != null && orderSupplierName.isNotEmpty) {
      for (final s in _allSuppliers) {
        if (s.name.trim().toLowerCase() == orderSupplierName.trim().toLowerCase()) {
          orderSupplierId = s.id;
          break;
        }
      }
    }

    for (final mat in _materials) {
      final sName = mat['supplier_name']?.toString().trim() ?? '';
      if (sName.isEmpty || sName == 'غير محدد' || sName == 'null') {
        final batchId = int.tryParse(mat['batch_id']?.toString() ?? '0') ?? 0;
        if (batchId > 0) {
          try {
            final bRes = await Supabase.instance.client
                .from('station_product_batches')
                .select('id, supplier_name, supplier_id, purchase_invoice_id, raw_material_id')
                .eq('id', batchId)
                .maybeSingle();
            if (bRes != null) {
              final bSup = bRes['supplier_name']?.toString().trim();
              final bSupId = bRes['supplier_id']?.toString().trim();
              final invId = bRes['purchase_invoice_id'];
              final rawId = bRes['raw_material_id'];

              if (bSup != null && bSup.isNotEmpty && bSup != 'غير محدد' && bSup != 'null') {
                mat['supplier_name'] = bSup;
                if (bSupId != null && bSupId.isNotEmpty) {
                  mat['supplier_id'] = bSupId;
                }
                hasUpdates = true;
              } else if (bSupId != null && bSupId.isNotEmpty) {
                final match = _allSuppliers
                    .where((s) => s.id == bSupId)
                    .firstOrNull;
                if (match != null && match.name.isNotEmpty) {
                  mat['supplier_name'] = match.name.trim();
                  mat['supplier_id'] = bSupId;
                  hasUpdates = true;
                }
              } else if (invId != null) {
                final invRes = await Supabase.instance.client
                    .from('purchase_invoices')
                    .select('supplier_id, suppliers(name)')
                    .eq('id', invId)
                    .maybeSingle();
                if (invRes != null) {
                  final invSupId = invRes['supplier_id']?.toString();
                  final invSupName = (invRes['suppliers'] is Map)
                      ? invRes['suppliers']['name']?.toString().trim()
                      : null;
                  if (invSupName != null && invSupName.isNotEmpty) {
                    mat['supplier_name'] = invSupName;
                    mat['supplier_id'] = invSupId;
                    hasUpdates = true;
                  }
                }
              } else if (rawId != null) {
                final rmRes = await Supabase.instance.client
                    .from('raw_materials')
                    .select('default_supplier_id')
                    .eq('id', rawId)
                    .maybeSingle();
                if (rmRes != null && rmRes['default_supplier_id'] != null) {
                  final dsId = rmRes['default_supplier_id'].toString();
                  final match = _allSuppliers
                      .where((s) => s.id == dsId)
                      .firstOrNull;
                  if (match != null && match.name.isNotEmpty) {
                    mat['supplier_name'] = match.name.trim();
                    mat['supplier_id'] = dsId;
                    hasUpdates = true;
                  }
                }
              }
            }
          } catch (e) {
            debugPrint('Error enriching batch supplier: $e');
          }
        }

        // 2. Lookup in raw_materials by code or name
        final currentName = mat['supplier_name']?.toString().trim() ?? '';
        if (currentName.isEmpty || currentName == 'غير محدد' || currentName == 'null') {
          final prodCode = mat['product_code']?.toString().trim();
          final prodName = (mat['product_name'] ?? mat['name'])?.toString().trim();
          try {
            var rmQuery = Supabase.instance.client
                .from('raw_materials')
                .select('default_supplier_id');
            Map<String, dynamic>? rm;
            if (prodCode != null && prodCode.isNotEmpty) {
              rm = await rmQuery.eq('code', prodCode).maybeSingle();
            }
            if (rm == null && prodName != null && prodName.isNotEmpty) {
              rm = await Supabase.instance.client
                  .from('raw_materials')
                  .select('default_supplier_id')
                  .eq('name', prodName)
                  .maybeSingle();
            }
            if (rm != null && rm['default_supplier_id'] != null) {
              final dsId = rm['default_supplier_id'].toString();
              final match = _allSuppliers
                  .where((s) => s.id == dsId)
                  .firstOrNull;
              if (match != null && match.name.isNotEmpty) {
                mat['supplier_name'] = match.name.trim();
                mat['supplier_id'] = dsId;
                hasUpdates = true;
              }
            }
          } catch (_) {}
        }

        // 3. Fallback: Automatically link to packing order supplier (Crop / Material linked to Order)
        final afterRm = mat['supplier_name']?.toString().trim() ?? '';
        if ((afterRm.isEmpty || afterRm == 'غير محدد' || afterRm == 'null') &&
            orderSupplierName != null &&
            orderSupplierName.isNotEmpty &&
            orderSupplierName != 'غير محدد') {
          mat['supplier_name'] = orderSupplierName;
          mat['supplier_id'] = orderSupplierId;
          hasUpdates = true;
        }
      }
    }

    // Persist auto-resolved suppliers to packing_orders and station_product_batches
    if (hasUpdates) {
      try {
        final orderId = int.tryParse(_order.id ?? '0') ?? 0;
        if (orderId > 0) {
          final parsed = jsonDecode(_order.notes ?? '{}');
          if (parsed is Map) {
            parsed['materials'] = _materials;
            final updatedNotes = jsonEncode(parsed);
            await Supabase.instance.client
                .from('packing_orders')
                .update({'notes': updatedNotes})
                .eq('id', orderId);
            _order = _order.copyWith(notes: updatedNotes);
          }
        }
      } catch (e) {
        debugPrint('Error updating packing order notes with enriched suppliers: $e');
      }

      for (final mat in _materials) {
        final batchId = int.tryParse(mat['batch_id']?.toString() ?? '0') ?? 0;
        final sName = mat['supplier_name']?.toString().trim() ?? '';
        final sId = mat['supplier_id']?.toString().trim();
        if (batchId > 0 && sName.isNotEmpty && sName != 'غير محدد' && sName != 'null') {
          try {
            await Supabase.instance.client
                .from('station_product_batches')
                .update({
                  'supplier_name': sName,
                  if (sId != null && sId.isNotEmpty) 'supplier_id': sId,
                })
                .eq('id', batchId);
          } catch (_) {}
        }
      }

      if (mounted) {
        setState(() {});
      }
    }
  }

  void _parseNotes() {
    _materials = [];
    if (_order.notes != null && _order.notes!.isNotEmpty) {
      try {
        final parsed = jsonDecode(_order.notes!);
        if (parsed is Map) {
          final map = Map<String, dynamic>.from(parsed);
          if (map.containsKey('materials') && map['materials'] is List) {
            _materials = (map['materials'] as List)
                .whereType<Map>()
                .map((m) => Map<String, dynamic>.from(m))
                .toList();
          }
        }
      } catch (e) {
        debugPrint('Error parsing notes in adjustment dialog: $e');
      }
    }
  }

  Future<void> _openItemDiscountModal({
    required String itemType,
    required String itemName,
    required String supplierName,
    required int batchId,
    required double currentTotal,
    required double currentUnitCost,
    required double usedQty,
    String? supplierId,
    String? unitLabel,
    String? cropAllocation,
  }) async {
    final discountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController(text: 'خصم جودة / تسوية سعر مورد');
    double discountAmount = 0.0;
    final unitSuffix = unitLabel != null && unitLabel.isNotEmpty ? ' $unitLabel' : '';
    final unitCostSuffix = unitLabel != null && unitLabel.isNotEmpty ? ' ج.م / $unitLabel' : ' ج.م';

    String currentSupplierName = supplierName.trim();
    String? currentSupplierId = supplierId;

    if (currentSupplierName.isEmpty ||
        currentSupplierName == 'غير محدد' ||
        currentSupplierName == 'null') {
      final fallbackName = _lot?.supplierName ?? _order.supplierName;
      if (fallbackName != null &&
          fallbackName.trim().isNotEmpty &&
          fallbackName != 'غير محدد') {
        currentSupplierName = fallbackName.trim();
      } else if (_allSuppliers.isNotEmpty) {
        currentSupplierName = _allSuppliers.first.name.trim();
        currentSupplierId = _allSuppliers.first.id;
      }
    }

    if ((currentSupplierId == null || currentSupplierId.isEmpty) &&
        currentSupplierName.isNotEmpty &&
        currentSupplierName != 'غير محدد') {
      for (final s in _allSuppliers) {
        if (s.name.trim().toLowerCase() == currentSupplierName.toLowerCase()) {
          currentSupplierId = s.id;
          break;
        }
      }
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final newTotal = (currentTotal - discountAmount).clamp(0.0, double.infinity);
            final newUnitCost = usedQty > 0 ? newTotal / usedQty : 0.0;
            final formattedQty = usedQty == usedQty.roundToDouble()
                ? usedQty.toInt().toString()
                : usedQty.toStringAsFixed(2);

            return AlertDialog(
              backgroundColor: isDark ? AppTheme.surface : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: isDark ? AppTheme.primary.withValues(alpha: 0.3) : const Color(0xFFCBD5E1)),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.price_change_outlined,
                        color: AppTheme.primary, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'إشعار خصم / تسوية سعر بند',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        Text(
                          itemName,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? AppTheme.textSecondary : Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.background : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFCBD5E1)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'المورد المرتبط:',
                                  style: TextStyle(
                                    color: isDark ? AppTheme.textSecondary : Colors.black87,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: AppTheme.primary.withValues(alpha: 0.4)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.person,
                                          size: 15, color: AppTheme.primary),
                                      const SizedBox(width: 6),
                                      Text(
                                        currentSupplierName.isNotEmpty &&
                                                currentSupplierName != 'غير محدد'
                                            ? currentSupplierName
                                            : (_order.supplierName ?? 'مورد أمر التعبئة'),
                                        style: TextStyle(
                                          color: isDark ? Colors.white : Colors.black,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (cropAllocation != null && cropAllocation.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              _buildInfoRow('المحصول / التخصيص:', cropAllocation, isDark: isDark),
                            ],
                            const SizedBox(height: 6),
                            _buildInfoRow('الكمية المستخدمة:', '$formattedQty$unitSuffix', isDark: isDark),
                            const SizedBox(height: 6),
                            _buildInfoRow('التكلفة الحالية للبند:', '${AppUtils.formatCurrency(currentTotal)} ج.م', isDark: isDark),
                            const SizedBox(height: 6),
                            _buildInfoRow('سعر الوحدة الحالي:', '${currentUnitCost.toStringAsFixed(3)}$unitCostSuffix', isDark: isDark),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: discountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: TextStyle(color: isDark ? Colors.white : Colors.black, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: 'مبلغ الخصم الإجمالي (ج.م) *',
                          labelStyle: TextStyle(color: isDark ? AppTheme.primary : const Color(0xFF0284C7), fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                          prefixIcon: Icon(Icons.money_off, color: isDark ? AppTheme.primary : const Color(0xFF0284C7)),
                          filled: true,
                          fillColor: isDark ? AppTheme.background : const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: isDark ? AppTheme.primary : const Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: isDark ? AppTheme.primary.withValues(alpha: 0.5) : const Color(0xFFCBD5E1)),
                          ),
                        ),
                        onChanged: (val) {
                          setModalState(() {
                            discountAmount = double.tryParse(val) ?? 0.0;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: reasonCtrl,
                        style: TextStyle(color: isDark ? Colors.white : Colors.black, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: 'سبب التسوية / البيان *',
                          labelStyle: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black87, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                          prefixIcon: Icon(Icons.notes, color: isDark ? AppTheme.textSecondary : Colors.black87),
                          filled: true,
                          fillColor: isDark ? AppTheme.background : const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.success.withValues(alpha: 0.1) : const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: isDark ? AppTheme.success.withValues(alpha: 0.3) : const Color(0xFF86EFAC)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('التكلفة الجديدة للبند:',
                                    style: TextStyle(
                                        color: isDark ? AppTheme.textSecondary : Colors.black87,
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12)),
                                Text('${AppUtils.formatCurrency(newTotal)} ج.م',
                                    style: const TextStyle(
                                        color: AppTheme.success,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Cairo',
                                        fontSize: 13)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('سعر الوحدة الجديد:',
                                    style: TextStyle(
                                        color: isDark ? AppTheme.textSecondary : Colors.black87,
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12)),
                                Text('${newUnitCost.toStringAsFixed(3)}$unitCostSuffix',
                                    style: const TextStyle(
                                        color: AppTheme.success,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Cairo',
                                        fontSize: 13)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('إلغاء',
                      style: TextStyle(color: isDark ? AppTheme.textSecondary : Colors.black87, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                ),
                ElevatedButton.icon(
                  onPressed: discountAmount <= 0
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          await _executeDebitNote(
                            itemType: itemType,
                            batchId: batchId,
                            discountAmount: discountAmount,
                            supplierId: currentSupplierId,
                            supplierName: currentSupplierName,
                            reason: reasonCtrl.text.trim(),
                            itemName: itemName,
                          );
                        },
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('تأكيد وإصدار إشعار الخصم',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }



  Future<void> _executeDebitNote({
    required String itemType,
    required int batchId,
    required double discountAmount,
    String? supplierId,
    String? supplierName,
    required String reason,
    required String itemName,
  }) async {
    setState(() => _loading = true);
    try {
      final orderId = int.tryParse(_order.id ?? '0') ?? 0;
      final res = await _dao.applyItemDebitNote(
        orderId: orderId,
        itemType: itemType,
        batchId: batchId,
        discountAmount: discountAmount,
        supplierId: supplierId,
        reason: reason,
        itemName: itemName,
      );

      if (res['success'] == true) {
        if (!mounted) return;
        final entryNum = res['entry_number'] ?? '';

        // 1. Immediately update in-memory _materials so UI reflects the discount instantaneously
        if (itemType == 'material') {
          for (var mat in _materials) {
            final mName = (mat['product_name'] ?? mat['name'] ?? '').toString().trim();
            final bId = int.tryParse(mat['batch_id']?.toString() ?? '0') ?? 0;
            if ((batchId > 0 && bId == batchId) ||
                (itemName.isNotEmpty && mName == itemName.trim()) ||
                _materials.length == 1) {
              final usedQty = double.tryParse(mat['used_qty']?.toString() ?? mat['quantity']?.toString() ?? '0') ?? 1.0;
              final currentTotal = double.tryParse(mat['total']?.toString() ?? mat['total_cost']?.toString() ?? '0') ?? (usedQty * (double.tryParse(mat['unit_cost']?.toString() ?? '0') ?? 0.0));
              final newTotal = (currentTotal - discountAmount).clamp(0.0, double.infinity);
              final currentDiscount = double.tryParse(mat['discount_applied']?.toString() ?? '0') ?? 0.0;
              mat['total'] = newTotal;
              mat['total_cost'] = newTotal;
              mat['discount_applied'] = currentDiscount + discountAmount;
              if (usedQty > 0) {
                mat['unit_cost'] = newTotal / usedQty;
                mat['cost'] = newTotal / usedQty;
              }
              break;
            }
          }
        }

        // 2. Reload the order from DB to reflect latest costs and notes updated by the RPC
        PackingOrderModel? dbOrder;
        if (orderId > 0) {
          dbOrder = await _dao.getById(orderId);
        }
        var refreshed = dbOrder ?? _order;

        if (orderId > 0) {
          final updatedLines = await _dao.getLines(orderId);
          if (updatedLines.isNotEmpty) {
            refreshed = refreshed.copyWith(lines: updatedLines);
          }
        }

        final newCostVal = double.tryParse(res['new_packing_cost_per_carton']?.toString() ?? '') ??
            refreshed.packingCostPerCarton;
        final newTotalCost = double.tryParse(res['new_total_packing_cost']?.toString() ?? '') ??
            refreshed.totalPackingCost;
        final newMatCost = double.tryParse(res['new_actual_material_cost']?.toString() ?? '') ??
            refreshed.actualMaterialCost;

        refreshed = refreshed.copyWith(
          packingCostPerCarton: newCostVal > 0 ? newCostVal : refreshed.packingCostPerCarton,
          totalPackingCost: newTotalCost > 0 ? newTotalCost : refreshed.totalPackingCost,
          actualMaterialCost: newMatCost > 0 ? newMatCost : refreshed.actualMaterialCost,
        );

        final displayCost = newCostVal > 0 ? newCostVal.toStringAsFixed(2) : (res['new_packing_cost_per_carton']?.toString() ?? '');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'تم إصدار إشعار الخصم ($entryNum) بنجاح وتحديث تكلفة الكرتونة إلى $displayCost ج.م',
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              backgroundColor: AppTheme.success,
            ),
          );
        }

        setState(() {
          _order = refreshed;
          _parseNotes();
          // Keep the updated discount if DB note parsing lagged behind
          if (itemType == 'material') {
            for (var mat in _materials) {
              final mName = (mat['product_name'] ?? mat['name'] ?? '').toString().trim();
              final bId = int.tryParse(mat['batch_id']?.toString() ?? '0') ?? 0;
              if ((batchId > 0 && bId == batchId) ||
                  (itemName.isNotEmpty && mName == itemName.trim()) ||
                  _materials.length == 1) {
                final applied = double.tryParse(mat['discount_applied']?.toString() ?? '0') ?? 0.0;
                if (applied == 0.0) {
                  final usedQty = double.tryParse(mat['used_qty']?.toString() ?? mat['quantity']?.toString() ?? '0') ?? 1.0;
                  final curTotal = double.tryParse(mat['total']?.toString() ?? mat['total_cost']?.toString() ?? '0') ?? 0.0;
                  final newTot = (curTotal - discountAmount).clamp(0.0, double.infinity);
                  mat['total'] = newTot;
                  mat['total_cost'] = newTot;
                  mat['discount_applied'] = discountAmount;
                  if (usedQty > 0) {
                    mat['unit_cost'] = newTot / usedQty;
                    mat['cost'] = newTot / usedQty;
                  }
                }
                break;
              }
            }
          }
        });

        widget.onUpdated?.call();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res['error'] ?? 'حدث خطأ أثناء تطبيق إشعار الخصم',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'حدث خطأ: $e',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildInfoRow(String label, String value, {bool? isDark}) {
    final dark = isDark ?? (Theme.of(context).brightness == Brightness.dark);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                color: dark ? AppTheme.textSecondary : Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo')),
        Text(value,
            style: TextStyle(
                color: dark ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                fontFamily: 'Cairo')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cartonCount = _order.cartonCount;
    final totalCost = _order.totalPackingCost;
    final costPerCarton = _order.packingCostPerCarton > 0
        ? _order.packingCostPerCarton
        : (cartonCount > 0 ? totalCost / cartonCount : 0.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          width: 760,
          constraints: const BoxConstraints(maxHeight: 700),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surface : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? AppTheme.primary.withValues(alpha: 0.3) : const Color(0xFFCBD5E1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.1),
                blurRadius: 20,
                spreadRadius: 4,
              )
            ],
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.primary.withValues(alpha: 0.08) : const Color(0xFFF8FAFC),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border(
                      bottom: BorderSide(
                          color: isDark ? AppTheme.primary.withValues(alpha: 0.2) : const Color(0xFFE2E8F0))),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.price_change_outlined,
                          color: AppTheme.primary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'تسوية أسعار بنود أمر التعبئة',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                  color: isDark ? Colors.white : Colors.black,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _order.orderNumber,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'تعديل تكلفة خامة أو محصول فردي وتوليد إشعار خصم مورد وتحديث تكلفة الكرتونة للشحنة',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? AppTheme.textSecondary : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: isDark ? AppTheme.textSecondary : Colors.black87),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Overview KPI Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                color: isDark ? AppTheme.background : const Color(0xFFF1F5F9),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildKpiCard(
                        'إجمالي كراتين الأمر',
                        '$cartonCount كرتونة',
                        Icons.inventory_2_outlined,
                        Colors.blue,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildKpiCard(
                        'إجمالي تكلفة الأمر',
                        '${AppUtils.formatCurrency(totalCost)} ج.م',
                        Icons.payments_outlined,
                        AppTheme.warning,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildKpiCard(
                        'تكلفة الكرتونة الحالية',
                        '${costPerCarton.toStringAsFixed(2)} ج.م',
                        Icons.analytics_outlined,
                        AppTheme.success,
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
              ),

              // Content Items
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppTheme.primary))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Packaging Materials Section
                            _buildSectionHeader(
                              'خامات ومواد التعبئة والتغليف (${_materials.length})',
                              Icons.all_inbox_outlined,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 8),
                            if (_materials.isEmpty)
                              _buildEmptyState('لا توجد خامات مسجلة في ملاحظات الأمر', isDark: isDark)
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _materials.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final mat = _materials[index];
                                  return _buildMaterialRow(mat, isDark: isDark);
                                },
                              ),

                            const SizedBox(height: 20),

                            // 2. Fruit / Crop Allocation Section
                            _buildSectionHeader(
                              _order.lines.length > 1
                                  ? 'المحاصيل المستخدمة / تخصيص اللوت (${_order.lines.length})'
                                  : 'المحصول المستخدم / تخصيص اللوت',
                              Icons.eco_outlined,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 8),
                            _buildFruitSection(isDark: isDark),
                          ],
                        ),
                      ),
              ),

              // Footer
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.surface : Colors.white,
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(16)),
                  border: Border(
                      top: BorderSide(
                          color: isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '🔒 التعديل متاح للمسؤولين فقط - يتم إنشاء قيود تسوية GL تلقائياً',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppTheme.textSecondary : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFF1F5F9),
                        foregroundColor: isDark ? Colors.white : Colors.black,
                        elevation: 0,
                      ),
                      child: const Text('إغلاق', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, {bool isDark = true}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cairo',
          ),
        ),
      ],
    );
  }

  Widget _buildKpiCard(String label, String value, IconData icon, Color color, {bool isDark = true}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.3 : 0.6)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: isDark ? AppTheme.textSecondary : Colors.black87,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo')),
                Text(value,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        fontFamily: 'Cairo')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getMaterialCropAllocation(Map<String, dynamic> mat) {
    if (mat.containsKey('crop_name') &&
        mat['crop_name'] != null &&
        mat['crop_name'].toString().trim().isNotEmpty) {
      return mat['crop_name'].toString().trim();
    }

    final applyTo = mat['apply_to']?.toString().trim() ?? 'all';

    if (applyTo.startsWith('line:')) {
      final idx = int.tryParse(applyTo.substring(5));
      if (idx != null) {
        if (_order.lines.isNotEmpty && idx < _order.lines.length) {
          final lineName = _order.lines[idx].productName.trim();
          if (lineName.isNotEmpty) return lineName;
        }
        if (_order.notes != null) {
          try {
            final parsed = jsonDecode(_order.notes!);
            if (parsed is Map && parsed['waste_data'] is List) {
              final wd = parsed['waste_data'] as List;
              if (idx < wd.length && wd[idx] is Map && wd[idx]['product_name'] != null) {
                final n = wd[idx]['product_name'].toString().trim();
                if (n.isNotEmpty) return n;
              }
            }
          } catch (_) {}
        }
        return 'بند #${idx + 1}';
      }
    }

    if (int.tryParse(applyTo) != null) {
      final idx = int.parse(applyTo);
      if (_order.lines.isNotEmpty && idx < _order.lines.length) {
        final lineName = _order.lines[idx].productName.trim();
        if (lineName.isNotEmpty) return lineName;
      }
      return 'بند #${idx + 1}';
    }

    if (applyTo != 'all' && applyTo.isNotEmpty) {
      return applyTo;
    }

    // applyTo == 'all'
    if (_order.lines.length > 1) {
      return 'مشترك';
    }

    if (_order.lines.length == 1 && _order.lines.first.productName.trim().isNotEmpty) {
      return _order.lines.first.productName.trim();
    }

    final orderCrop = _order.productName ?? _lot?.productName;
    if (orderCrop != null && orderCrop.trim().isNotEmpty) {
      return orderCrop.trim();
    }

    return 'مشترك';
  }

  Widget _buildMaterialRow(Map<String, dynamic> mat, {bool isDark = true}) {
    final productName = mat['product_name'] ?? mat['name'] ?? 'خامة';
    final supplierName = mat['supplier_name'] ?? 'غير محدد';
    final supplierId = mat['supplier_id']?.toString();
    final batchId = int.tryParse(mat['batch_id']?.toString() ?? '0') ?? 0;
    final usedQty = double.tryParse(mat['used_qty']?.toString() ?? mat['quantity']?.toString() ?? '0') ?? 0.0;
    final unitCost = double.tryParse(mat['unit_cost']?.toString() ?? mat['cost']?.toString() ?? '0') ?? 0.0;
    final total = double.tryParse(mat['total']?.toString() ?? mat['total_cost']?.toString() ?? '0') ?? (usedQty * unitCost);
    final discountApplied = double.tryParse(mat['discount_applied']?.toString() ?? '0') ?? 0.0;
    final cropAllocation = _getMaterialCropAllocation(mat);
    final isShared = cropAllocation == 'مشترك';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.background : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFCBD5E1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.inventory, color: isDark ? Colors.white70 : const Color(0xFF0284C7), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productName,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    fontFamily: 'Cairo',
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  runSpacing: 3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'المورد: $supplierName',
                      style: TextStyle(
                        color: isDark ? AppTheme.textSecondary : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: isShared
                            ? AppTheme.primary.withValues(alpha: 0.15)
                            : Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isShared
                              ? (isDark ? AppTheme.primary.withValues(alpha: 0.35) : const Color(0xFF0284C7))
                              : (isDark ? Colors.greenAccent.withValues(alpha: 0.35) : Colors.green),
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isShared ? Icons.call_split : Icons.eco,
                            size: 10,
                            color: isShared ? (isDark ? AppTheme.primary : const Color(0xFF0284C7)) : (isDark ? Colors.greenAccent : const Color(0xFF16A34A)),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            isShared ? 'مشترك' : 'المحصول: $cropAllocation',
                            style: TextStyle(
                              color: isShared ? (isDark ? AppTheme.primary : const Color(0xFF0284C7)) : (isDark ? Colors.greenAccent : const Color(0xFF16A34A)),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (discountApplied > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    'تم تطبيق خصم سابق: ${AppUtils.formatCurrency(discountApplied)}',
                    style: const TextStyle(
                      color: AppTheme.warning,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الكمية: $usedQty',
                  style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'Cairo'),
                ),
                Text(
                  'سعر الوحدة: ${unitCost.toStringAsFixed(3)} ج.م',
                  style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'Cairo'),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('إجمالي التكلفة',
                    style: TextStyle(
                        color: isDark ? AppTheme.textSecondary : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        fontFamily: 'Cairo')),
                Text(
                  AppUtils.formatCurrency(total),
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () => _openItemDiscountModal(
              itemType: 'material',
              itemName: productName,
              supplierName: supplierName,
              batchId: batchId,
              currentTotal: total,
              currentUnitCost: unitCost,
              usedQty: usedQty,
              supplierId: supplierId,
              cropAllocation: cropAllocation,
            ),
            icon: const Icon(Icons.price_change_outlined, size: 16),
            label: const Text('خصم / تسوية',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo')),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary.withValues(alpha: isDark ? 0.2 : 0.1),
              foregroundColor: isDark ? AppTheme.primary : const Color(0xFF0284C7),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: isDark ? AppTheme.primary.withValues(alpha: 0.5) : const Color(0xFF0284C7)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFruitSection({bool isDark = true}) {
    if (_order.lines.length > 1) {
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _order.lines.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final line = _order.lines[index];
          return _buildSingleLineFruitRow(line, index, isDark: isDark);
        },
      );
    }

    return _buildSingleCropDefaultRow(isDark: isDark);
  }

  Widget _buildSingleLineFruitRow(PackingOrderLineModel line, int index, {bool isDark = true}) {
    final lot = line.sourceLotId != null ? _lineLots[line.sourceLotId] : null;
    final isCartonMode =
        lot?.purchaseMode == 'carton' || _lot?.purchaseMode == 'carton';
    final unitLabel = isCartonMode ? 'كرتونة' : 'كجم';

    // Calculate this line's crop cost BEFORE waste and sorting
    double lineFruitCost = line.rawMaterialCost;
    if (lineFruitCost <= 0) {
      if (line.finalCost > 0) {
        lineFruitCost = line.finalCost -
            (line.wasteCost +
                line.sortingCost +
                line.specificPackagingCost +
                line.allocatedSharedPackaging +
                line.allocatedCostItems);
      }
      if (lineFruitCost <= 0 && _order.cartonCount > 0) {
        final totalBase = _order.fruitCostBase > 0
            ? _order.fruitCostBase
            : (_order.fruitCostAllocated > 0 ? _order.fruitCostAllocated : 0.0);
        lineFruitCost = totalBase * (line.cartonCount / _order.cartonCount);
      }
    }

    double usedQty = 0.0;
    if (isCartonMode) {
      usedQty = (line.quantity > 0
              ? line.quantity
              : (line.cartonCount > 0 ? line.cartonCount : 1))
          .toDouble();
    } else {
      usedQty = line.totalNetWeight > 0
          ? line.totalNetWeight
          : ((line.cartonCount > 0 ? line.cartonCount : 1) *
                  (line.netWeightPerCarton > 0 ? line.netWeightPerCarton : 1))
              .toDouble();
    }
    if (usedQty <= 0) usedQty = 1.0;

    final unitCost = usedQty > 0 ? (lineFruitCost / usedQty) : 0.0;
    final lotNumber =
        lot?.lotNumber ?? _order.lotNumber ?? 'لوت #${index + 1}';
    final supplierName = lot?.supplierName ??
        _order.supplierName ??
        _lot?.supplierName ??
        'مورد المحصول';
    String? lineSupId = lot?.supplierId ?? _lot?.supplierId;
    if ((lineSupId == null || lineSupId.isEmpty) && supplierName.isNotEmpty && supplierName != 'مورد المحصول') {
      for (final s in _allSuppliers) {
        if (s.name.trim().toLowerCase() == supplierName.trim().toLowerCase()) {
          lineSupId = s.id;
          break;
        }
      }
    }
    final cropName = line.productName.trim().isNotEmpty
        ? line.productName.trim()
        : (lot?.productName ?? _order.productName ?? 'محصول #${index + 1}');

    final formattedQty = usedQty == usedQty.roundToDouble()
        ? usedQty.toInt().toString()
        : usedQty.toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.background : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFCBD5E1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? Colors.green.withValues(alpha: 0.1) : const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.eco, color: isDark ? Colors.greenAccent : const Color(0xFF16A34A), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$cropName ($lotNumber)',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    fontFamily: 'Cairo',
                  ),
                ),
                Text(
                  'المورد: $supplierName',
                  style: TextStyle(
                    color: isDark ? AppTheme.textSecondary : Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCartonMode
                      ? 'الكراتين: $formattedQty كرتونة'
                      : 'الوزن: $formattedQty كجم',
                  style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                      fontSize: 11,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold),
                ),
                Text(
                  'الكراتين: ${line.cartonCount} كرتونة',
                  style: TextStyle(
                      color: isDark ? AppTheme.textSecondary : Colors.black54,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo'),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('تكلفة المحصول المستخدم (قبل الهالك والفرز)',
                    style: TextStyle(
                        color: isDark ? AppTheme.textSecondary : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        fontFamily: 'Cairo')),
                Text(
                  AppUtils.formatCurrency(lineFruitCost),
                  style: TextStyle(
                    color: isDark ? Colors.greenAccent : const Color(0xFF16A34A),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () => _openItemDiscountModal(
              itemType: 'crop',
              itemName: '$cropName ($lotNumber)',
              supplierName: supplierName,
              batchId: int.tryParse(line.id ?? '') ??
                  int.tryParse(line.batchId ?? '') ??
                  int.tryParse(line.sourceLotId ?? '') ??
                  0,
              currentTotal: lineFruitCost,
              currentUnitCost: unitCost,
              usedQty: usedQty,
              supplierId: lineSupId,
              unitLabel: unitLabel,
              cropAllocation: cropName,
            ),
            icon: const Icon(Icons.price_change_outlined, size: 16),
            label: const Text('خصم / تسوية',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo')),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.withValues(alpha: isDark ? 0.2 : 0.1),
              foregroundColor: isDark ? Colors.greenAccent : const Color(0xFF16A34A),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: isDark ? Colors.green.withValues(alpha: 0.5) : const Color(0xFF16A34A)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleCropDefaultRow({bool isDark = true}) {
    final isCartonMode = _lot?.purchaseMode == 'carton';
    final unitLabel = isCartonMode ? 'كرتونة' : 'كجم';

    // تكلفة المحصول الخام المستخدم قبل الفرز والهالك
    final fruitCost = _order.fruitCostBase > 0
        ? _order.fruitCostBase
        : (_order.fruitCostAllocated > 0 ? _order.fruitCostAllocated : 0.0);

    // الكمية الصافية المستخدمة في أمر التعبئة
    double usedQty = 0.0;
    if (isCartonMode) {
      final lotCartons =
          (_lot?.cartonCount ?? 0) > 0 ? _lot!.cartonCount!.toDouble() : 0.0;
      usedQty = lotCartons > 0
          ? lotCartons
          : (_order.cartonCount > 0 ? _order.cartonCount : 1).toDouble();
    } else {
      usedQty = _order.totalNetWeight > 0
          ? _order.totalNetWeight
          : ((_order.cartonCount > 0 ? _order.cartonCount : 1) *
                  (_order.netWeightPerCarton > 0 ? _order.netWeightPerCarton : 1))
              .toDouble();
    }
    if (usedQty <= 0) usedQty = 1.0;

    // سعر الوحدة قبل الهالك والفرز
    final unitCost = usedQty > 0 ? (fruitCost / usedQty) : 0.0;

    final lotNumber = _order.lotNumber ?? _lot?.lotNumber ?? 'لوت رئيسي';
    final supplierName = _order.supplierName ?? _lot?.supplierName ?? 'مورد المحصول';
    String? cropSupId = _lot?.supplierId;
    if ((cropSupId == null || cropSupId.isEmpty) && supplierName.isNotEmpty && supplierName != 'مورد المحصول') {
      for (final s in _allSuppliers) {
        if (s.name.trim().toLowerCase() == supplierName.trim().toLowerCase()) {
          cropSupId = s.id;
          break;
        }
      }
    }
    final cropName = _order.productName ?? _lot?.productName ?? 'محصول المحطة';

    final formattedQty = usedQty == usedQty.roundToDouble()
        ? usedQty.toInt().toString()
        : usedQty.toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.background : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFCBD5E1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? Colors.green.withValues(alpha: 0.1) : const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.eco, color: isDark ? Colors.greenAccent : const Color(0xFF16A34A), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$cropName ($lotNumber)',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    fontFamily: 'Cairo',
                  ),
                ),
                Text(
                  'المورد: $supplierName',
                  style: TextStyle(
                    color: isDark ? AppTheme.textSecondary : Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCartonMode
                      ? 'الكراتين: $formattedQty كرتونة'
                      : 'الوزن: $formattedQty كجم',
                  style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                      fontSize: 11,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold),
                ),
                Text(
                  'الكراتين: ${_order.cartonCount} كرتونة',
                  style: TextStyle(
                      color: isDark ? AppTheme.textSecondary : Colors.black54,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo'),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('تكلفة المحصول المستخدم (قبل الهالك والفرز)',
                    style: TextStyle(
                        color: isDark ? AppTheme.textSecondary : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        fontFamily: 'Cairo')),
                Text(
                  AppUtils.formatCurrency(fruitCost),
                  style: TextStyle(
                    color: isDark ? Colors.greenAccent : const Color(0xFF16A34A),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () => _openItemDiscountModal(
              itemType: 'crop',
              itemName: '$cropName ($lotNumber)',
              supplierName: supplierName,
              batchId: 0,
              currentTotal: fruitCost,
              currentUnitCost: unitCost,
              usedQty: usedQty,
              supplierId: cropSupId,
              unitLabel: unitLabel,
              cropAllocation: cropName,
            ),
            icon: const Icon(Icons.price_change_outlined, size: 16),
            label: const Text('خصم / تسوية',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo')),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.withValues(alpha: isDark ? 0.2 : 0.1),
              foregroundColor: isDark ? Colors.greenAccent : const Color(0xFF16A34A),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: isDark ? Colors.green.withValues(alpha: 0.5) : const Color(0xFF16A34A)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message, {bool isDark = true}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.background : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? Colors.transparent : const Color(0xFFCBD5E1)),
      ),
      child: Center(
        child: Text(
          message,
          style: TextStyle(
            color: isDark ? AppTheme.textSecondary : Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 12,
            fontFamily: 'Cairo',
          ),
        ),
      ),
    );
  }
}
