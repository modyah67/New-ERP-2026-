import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/models/packing_order_model.dart';
import '../../data/models/packing_order_line_model.dart';
import '../../data/dao/packing_order_dao.dart';
import '../../data/dao/lot_dao.dart';
import '../../data/models/lot_model.dart';

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
  late PackingOrderModel _order;
  LotReceiptModel? _lot;
  bool _loading = false;
  List<Map<String, dynamic>> _materials = [];

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
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading lot in adjustment dialog: $e');
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

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final newTotal = (currentTotal - discountAmount).clamp(0.0, double.infinity);
            final newUnitCost = usedQty > 0 ? newTotal / usedQty : 0.0;
            final formattedQty = usedQty == usedQty.roundToDouble()
                ? usedQty.toInt().toString()
                : usedQty.toStringAsFixed(2);

            return AlertDialog(
              backgroundColor: AppTheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3)),
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
                        const Text(
                          'إشعار خصم / تسوية سعر بند',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          itemName,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
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
                          color: AppTheme.background,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Column(
                          children: [
                            _buildInfoRow('المورد:', supplierName.isEmpty ? 'غير محدد' : supplierName),
                            if (cropAllocation != null && cropAllocation.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              _buildInfoRow('المحصول / التخصيص:', cropAllocation),
                            ],
                            const SizedBox(height: 6),
                            _buildInfoRow('الكمية المستخدمة:', '$formattedQty$unitSuffix'),
                            const SizedBox(height: 6),
                            _buildInfoRow('التكلفة الحالية للبند:', '${AppUtils.formatCurrency(currentTotal)} ج.م'),
                            const SizedBox(height: 6),
                            _buildInfoRow('سعر الوحدة الحالي:', '${currentUnitCost.toStringAsFixed(3)}$unitCostSuffix'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: discountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                        decoration: InputDecoration(
                          labelText: 'مبلغ الخصم الإجمالي (ج.م) *',
                          labelStyle: const TextStyle(color: AppTheme.primary, fontFamily: 'Cairo'),
                          prefixIcon: const Icon(Icons.money_off, color: AppTheme.primary),
                          filled: true,
                          fillColor: AppTheme.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: AppTheme.primary),
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
                        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                        decoration: InputDecoration(
                          labelText: 'سبب التسوية / البيان *',
                          labelStyle: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'),
                          prefixIcon: const Icon(Icons.notes, color: AppTheme.textSecondary),
                          filled: true,
                          fillColor: AppTheme.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppTheme.success.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('التكلفة الجديدة للبند:',
                                    style: TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontFamily: 'Cairo',
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
                                const Text('سعر الوحدة الجديد:',
                                    style: TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontFamily: 'Cairo',
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
                  child: const Text('إلغاء',
                      style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
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
                            supplierId: supplierId,
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
      );

      if (res['success'] == true) {
        if (!mounted) return;
        final entryNum = res['entry_number'] ?? '';

        // Reload the order from DB to reflect latest costs and lines
        final updatedList = await _dao.getAll();
        var refreshed = updatedList.firstWhere(
          (o) => o.id == _order.id,
          orElse: () => _order,
        );

        if (orderId > 0) {
          final updatedLines = await _dao.getLines(orderId);
          if (updatedLines.isNotEmpty) {
            refreshed = refreshed.copyWith(lines: updatedLines);
          }
        }

        final newCostVal = double.tryParse(res['new_packing_cost_per_carton']?.toString() ?? '') ??
            refreshed.packingCostPerCarton;
        final displayCost = newCostVal > 0 ? newCostVal.toStringAsFixed(2) : (res['new_packing_cost_per_carton']?.toString() ?? '');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم إصدار إشعار الخصم ($entryNum) بنجاح وتحديث تكلفة الكرتونة إلى $displayCost ج.م',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: AppTheme.success,
          ),
        );

        setState(() {
          _order = refreshed;
          _parseNotes();
        });
        await _loadLot();

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
          content: Text('خطأ: $e', style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontFamily: 'Cairo')),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
                fontFamily: 'Cairo')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cartonCount = _order.cartonCount ?? 1;
    final totalCost = _order.totalPackingCost ?? 0.0;
    final costPerCarton = _order.packingCostPerCarton ?? (cartonCount > 0 ? totalCost / cartonCount : 0.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          width: 760,
          constraints: const BoxConstraints(maxHeight: 700),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
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
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border(
                      bottom: BorderSide(
                          color: AppTheme.primary.withValues(alpha: 0.2))),
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
                              const Text(
                                'تسوية أسعار بنود أمر التعبئة',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                  color: Colors.white,
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
                          const Text(
                            'تعديل تكلفة خامة أو محصول فردي وتوليد إشعار خصم مورد وتحديث تكلفة الكرتونة للشحنة',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Overview KPI Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                color: AppTheme.background,
                child: Row(
                  children: [
                    Expanded(
                      child: _buildKpiCard(
                        'إجمالي كراتين الأمر',
                        '$cartonCount كرتونة',
                        Icons.inventory_2_outlined,
                        Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildKpiCard(
                        'إجمالي تكلفة الأمر',
                        '${AppUtils.formatCurrency(totalCost)} ج.م',
                        Icons.payments_outlined,
                        AppTheme.warning,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildKpiCard(
                        'تكلفة الكرتونة الحالية',
                        '${costPerCarton.toStringAsFixed(2)} ج.م',
                        Icons.analytics_outlined,
                        AppTheme.success,
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
                            ),
                            const SizedBox(height: 8),
                            if (_materials.isEmpty)
                              _buildEmptyState('لا توجد خامات مسجلة في ملاحظات الأمر')
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _materials.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final mat = _materials[index];
                                  return _buildMaterialRow(mat);
                                },
                              ),

                            const SizedBox(height: 20),

                            // 2. Fruit / Crop Allocation Section
                            _buildSectionHeader(
                              _order.lines.length > 1
                                  ? 'المحاصيل المستخدمة / تخصيص اللوت (${_order.lines.length})'
                                  : 'المحصول المستخدم / تخصيص اللوت',
                              Icons.eco_outlined,
                            ),
                            const SizedBox(height: 8),
                            _buildFruitSection(),
                          ],
                        ),
                      ),
              ),

              // Footer
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(16)),
                  border: Border(
                      top: BorderSide(
                          color: Colors.white.withValues(alpha: 0.08))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '🔒 التعديل متاح للمسؤولين فقط - يتم إنشاء قيود تسوية GL تلقائياً',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('إغلاق', style: TextStyle(fontFamily: 'Cairo')),
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

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cairo',
          ),
        ),
      ],
    );
  }

  Widget _buildKpiCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
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
                    style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
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

  Widget _buildMaterialRow(Map<String, dynamic> mat) {
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
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.inventory, color: Colors.white70, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productName,
                  style: const TextStyle(
                    color: Colors.white,
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
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
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
                              ? AppTheme.primary.withValues(alpha: 0.35)
                              : Colors.greenAccent.withValues(alpha: 0.35),
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isShared ? Icons.call_split : Icons.eco,
                            size: 10,
                            color: isShared ? AppTheme.primary : Colors.greenAccent,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            isShared ? 'مشترك' : 'المحصول: $cropAllocation',
                            style: TextStyle(
                              color: isShared ? AppTheme.primary : Colors.greenAccent,
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
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 11, fontFamily: 'Cairo'),
                ),
                Text(
                  'سعر الوحدة: ${unitCost.toStringAsFixed(3)} ج.م',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 11, fontFamily: 'Cairo'),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('إجمالي التكلفة',
                    style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                        fontFamily: 'Cairo')),
                Text(
                  AppUtils.formatCurrency(total),
                  style: const TextStyle(
                    color: Colors.white,
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
              backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
              foregroundColor: AppTheme.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFruitSection() {
    if (_order.lines.length > 1) {
      return ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _order.lines.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final line = _order.lines[index];
          return _buildSingleLineFruitRow(line, index);
        },
      );
    }

    return _buildSingleCropDefaultRow();
  }

  Widget _buildSingleLineFruitRow(PackingOrderLineModel line, int index) {
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
    final cropName = line.productName.trim().isNotEmpty
        ? line.productName.trim()
        : (lot?.productName ?? _order.productName ?? 'محصول #${index + 1}');

    final formattedQty = usedQty == usedQty.roundToDouble()
        ? usedQty.toInt().toString()
        : usedQty.toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.eco, color: Colors.greenAccent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$cropName ($lotNumber)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    fontFamily: 'Cairo',
                  ),
                ),
                Text(
                  'المورد: $supplierName',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
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
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w600),
                ),
                Text(
                  'الكراتين: ${line.cartonCount} كرتونة',
                  style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
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
                const Text('تكلفة المحصول المستخدم (قبل الهالك والفرز)',
                    style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                        fontFamily: 'Cairo')),
                Text(
                  AppUtils.formatCurrency(lineFruitCost),
                  style: const TextStyle(
                    color: Colors.greenAccent,
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
              supplierId: lot?.supplierId ?? _lot?.supplierId,
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
              backgroundColor: Colors.green.withValues(alpha: 0.2),
              foregroundColor: Colors.greenAccent,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.green.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleCropDefaultRow() {
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
    final cropName = _order.productName ?? _lot?.productName ?? 'محصول المحطة';

    final formattedQty = usedQty == usedQty.roundToDouble()
        ? usedQty.toInt().toString()
        : usedQty.toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.eco, color: Colors.greenAccent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$cropName ($lotNumber)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    fontFamily: 'Cairo',
                  ),
                ),
                Text(
                  'المورد: $supplierName',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
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
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w600),
                ),
                Text(
                  'الكراتين: ${_order.cartonCount} كرتونة',
                  style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
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
                const Text('تكلفة المحصول المستخدم (قبل الهالك والفرز)',
                    style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                        fontFamily: 'Cairo')),
                Text(
                  AppUtils.formatCurrency(fruitCost),
                  style: const TextStyle(
                    color: Colors.greenAccent,
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
              supplierId: _lot?.supplierId,
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
              backgroundColor: Colors.green.withValues(alpha: 0.2),
              foregroundColor: Colors.greenAccent,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.green.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          message,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            fontFamily: 'Cairo',
          ),
        ),
      ),
    );
  }
}
