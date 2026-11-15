import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme.dart';
import '../../../data/dao/packing_order_dao.dart';
import '../../../data/models/packing_order_model.dart';
import '../../../data/services/journal_entry_navigation_service.dart';

/// Modal dialog for settling estimated vs. actual cost variances
/// and recalculating packing carton costs and linked shipment profitability.
class PackingCostVarianceSettlementModal extends StatefulWidget {
  final int packingOrderId;
  final String? orderNumber;
  final PackingOrderModel? order;
  final VoidCallback? onSettled;

  const PackingCostVarianceSettlementModal({
    super.key,
    required this.packingOrderId,
    this.orderNumber,
    this.order,
    this.onSettled,
  });

  static Future<void> show(
    BuildContext context, {
    required int packingOrderId,
    String? orderNumber,
    PackingOrderModel? order,
    VoidCallback? onSettled,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PackingCostVarianceSettlementModal(
        packingOrderId: packingOrderId,
        orderNumber: orderNumber,
        order: order,
        onSettled: onSettled,
      ),
    );
  }

  @override
  State<PackingCostVarianceSettlementModal> createState() =>
      _PackingCostVarianceSettlementModalState();
}

class _PackingCostVarianceSettlementModalState
    extends State<PackingCostVarianceSettlementModal> {
  final _dao = PackingOrderDao();

  bool _loading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  Map<String, dynamic>? _varianceData;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _shipments = [];
  String _effectiveShipmentNo = '';

  // Controllers mapped by cost item ID
  final Map<int, TextEditingController> _actualControllers = {};
  final Map<int, TextEditingController> _invoiceControllers = {};
  final Map<int, TextEditingController> _notesControllers = {};
  final TextEditingController _generalNotesController = TextEditingController();
  final Set<int> _adminSettlingItems = {};
  final Set<int> _adminForceEditingItems = {};

  final _currencyFormat = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    for (final c in _actualControllers.values) {
      c.dispose();
    }
    for (final c in _invoiceControllers.values) {
      c.dispose();
    }
    for (final c in _notesControllers.values) {
      c.dispose();
    }
    _generalNotesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final res = await _dao.getVarianceDetails(widget.packingOrderId);
      if (res['success'] != true) {
        throw Exception(res['error'] ?? 'تعذر تحميل بيانات التكاليف');
      }

      _varianceData = res;
      _items = List<Map<String, dynamic>>.from(res['items'] ?? []);
      _shipments = List<Map<String, dynamic>>.from(res['shipments'] ?? []);

      // Extract registered shipment number from packing order or variance data
      final orderShipNo = widget.order?.exportShipmentNo?.toString().trim();
      final resShipNo = res['export_shipment_no']?.toString().trim();
      final linkedShipNo = _shipments.isNotEmpty ? _shipments.first['shipment_no']?.toString().trim() : null;

      _effectiveShipmentNo = (orderShipNo != null && orderShipNo.isNotEmpty)
          ? orderShipNo
          : (resShipNo != null && resShipNo.isNotEmpty)
              ? resShipNo
              : (linkedShipNo != null && linkedShipNo.isNotEmpty)
                  ? linkedShipNo
                  : '';

      // Initialize controllers
      _actualControllers.clear();
      _invoiceControllers.clear();
      _notesControllers.clear();

      for (final it in _items) {
        final id = it['id'] as int;
        final isTrans = _isTransportItem(it);
        final actual = (it['actual_amount'] as num?)?.toDouble();
        final expected = isTrans ? 0.0 : ((it['expected_amount'] ?? it['base_amount'] ?? 0) as num).toDouble();
        final initialActual = actual ?? (isTrans ? 0.0 : expected);

        final rawInv = (it['invoice_ref'] ?? it['invoice_reference'])?.toString().trim() ?? '';
        final initialInv = rawInv.isNotEmpty ? rawInv : _effectiveShipmentNo;

        _actualControllers[id] = TextEditingController(
          text: initialActual.toStringAsFixed(2),
        );
        _invoiceControllers[id] = TextEditingController(
          text: initialInv,
        );
        _notesControllers[id] = TextEditingController(
          text: it['notes']?.toString() ?? it['settlement_notes']?.toString() ?? '',
        );
      }

      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('Error loading variance details: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  bool _isTransportItem(Map<String, dynamic> item) {
    final name = (item['name'] ?? '').toString().toLowerCase();
    final category = (item['category'] ?? '').toString().toLowerCase();
    final suppType = (item['supplier_type'] ?? '').toString().toLowerCase();

    // Station and Deduction suppliers must NEVER be treated as transport
    final isStation = suppType == 'station' ||
        category == 'station' ||
        category == 'station_supplier' ||
        name.contains('محطة') ||
        item['station_supplier_id'] != null;
    if (isStation) return false;

    final isDeduction = suppType == 'deduction' ||
        suppType == 'deductions' ||
        category == 'deduction' ||
        category == 'deductions' ||
        name.contains('تخصيم');
    if (isDeduction) return false;

    return suppType == 'transport' ||
        category == 'logistics' ||
        category == 'transport' ||
        name.contains('نقل') ||
        name.contains('شحن') ||
        item['transport_supplier_id'] != null;
  }

  double _getItemEstimated(Map<String, dynamic> item) {
    if (_isTransportItem(item)) return 0.0;
    return ((item['expected_amount'] ?? item['base_amount'] ?? 0) as num).toDouble();
  }

  double _getItemActual(int itemId) {
    final text = _actualControllers[itemId]?.text.trim() ?? '';
    return double.tryParse(text) ?? 0.0;
  }

  double _getItemVariance(Map<String, dynamic> item) {
    if (_isTransportItem(item)) return 0.0;
    final id = item['id'] as int;
    final est = _getItemEstimated(item);
    final act = _getItemActual(id);
    return act - est;
  }

  double get _totalEstimated {
    return _items
        .where((it) => !_isTransportItem(it))
        .fold<double>(0.0, (sum, it) => sum + _getItemEstimated(it));
  }

  double get _totalActual {
    return _items.fold<double>(0.0, (sum, it) {
      final id = it['id'] as int;
      return sum + _getItemActual(id);
    });
  }

  double get _netVariance {
    return _items
        .where((it) => !_isTransportItem(it))
        .fold<double>(0.0, (sum, it) {
      final id = it['id'] as int;
      return sum + (_getItemActual(id) - _getItemEstimated(it));
    });
  }

  double get _cartonsCount {
    if (_varianceData == null) return 1.0;
    final c = ((_varianceData!['carton_count'] ?? 0) as num).toDouble();
    return c > 0 ? c : 1.0;
  }

  double get _currentCartonCost {
    if (_varianceData == null) return 0.0;
    return ((_varianceData!['packing_cost_per_carton'] ?? 0) as num).toDouble();
  }

  double get _newCartonCost {
    if (_varianceData == null) return 0.0;
    final fruitCost = ((_varianceData!['fruit_cost_base'] ?? 0) as num).toDouble();
    final matCost = ((_varianceData!['actual_material_cost'] ?? 0) as num).toDouble();
    final total = fruitCost + matCost + _totalActual;
    final cartons = _cartonsCount;
    return cartons > 0 ? (total / cartons) : 0.0;
  }

  void _copyAllEstimatedToActual() {
    setState(() {
      for (final it in _items) {
        if (_isTransportItem(it)) continue;
        final id = it['id'] as int;
        final est = _getItemEstimated(it);
        _actualControllers[id]?.text = est.toStringAsFixed(2);
        if ((_invoiceControllers[id]?.text.trim().isEmpty ?? true) && _effectiveShipmentNo.isNotEmpty) {
          _invoiceControllers[id]?.text = _effectiveShipmentNo;
        }
      }
    });
  }

  Future<void> _submitSettlement() async {
    // 1. Prepare settlement payload
    final settlements = <Map<String, dynamic>>[];
    for (final it in _items) {
      final id = it['id'] as int;
      final act = _getItemActual(id);
      final invRef = _invoiceControllers[id]?.text.trim() ?? '';
      final notes = _notesControllers[id]?.text.trim() ?? '';

      settlements.add({
        'cost_item_id': id,
        'actual_amount': act,
        'invoice_ref': invRef.isNotEmpty
            ? invRef
            : (_effectiveShipmentNo.isNotEmpty ? _effectiveShipmentNo : null),
        'notes': notes.isNotEmpty ? notes : null,
      });
    }

    // 2. Confirm modal with breakdown
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF07213D) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: AppTheme.primary, size: 24),
              const SizedBox(width: 8),
              Text(
                'تأكيد التسوية الفعلية وترحيل القيود',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.textPrimary : Colors.black,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'سيتم إجراء العمليات التالية بصورة آلية وبدقة مزدوجة:',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? AppTheme.textSecondary : Colors.black87),
              ),
              const SizedBox(height: 12),
              _buildConfirmBullet('تعديل التكاليف الفعلية لـ ${settlements.length} بنود تكلفة.'),
              _buildConfirmBullet(
                _netVariance >= 0
                    ? 'توليد قيد تسوية بفروق إضافية قدرها: +${_currencyFormat.format(_netVariance)} ج.م (مدين المخزون 12413 / دائن الموردين أو 21111/31331).'
                    : 'توليد قيد تسوية بوفر تكلفة قدره: ${_currencyFormat.format(_netVariance)} ج.م (دائن المخزون 12413 / مدين الموردين أو 21111/31331).',
              ),
              _buildConfirmBullet(
                'تحديث تكلفة كرتونة التعبئة من ${_currencyFormat.format(_currentCartonCost)} ج.م إلى ${_currencyFormat.format(_newCartonCost)} ج.م.',
              ),
              if (_shipments.isNotEmpty)
                _buildConfirmBullet(
                  'إعادة احتساب تكلفة الهبوط وصافي أرباح ${_shipments.length} شحنة تصدير مرتبطة فوراً.',
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: isDark ? AppTheme.textMuted : Colors.black54)),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.send_rounded, size: 16),
              label: const Text('تأكيد وترحيل', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: const Color(0xFF041E42),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);

    try {
      final res = await _dao.settleCostVariancesBatch(
        packingOrderId: widget.packingOrderId,
        settlements: settlements,
        generalNotes: _generalNotesController.text.trim().isNotEmpty
            ? _generalNotesController.text.trim()
            : null,
      );

      if (res['success'] != true) {
        throw Exception(res['error'] ?? 'فشلت عملية التسوية');
      }

      final jeId = res['journal_entry_id'];
      final jeNumber = res['journal_entry_number'] ?? (jeId != null ? '#$jeId' : null);

      if (mounted) {
        setState(() => _isSubmitting = false);
        widget.onSettled?.call();

        // Show Success Dialog with direct Journal Entry Link
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF07213D) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.verified, color: AppTheme.success, size: 28),
                  SizedBox(width: 8),
                  Text(
                    'تمت التسوية بنجاح',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    res['message']?.toString() ?? 'تم ترحيل الفروق وتحديث التكاليف والأرباح بدقة.',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  if (jeId != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.primary.withAlpha(60)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.receipt_long, color: AppTheme.primary, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'تم إنشاء القيد المحاسبي رقم: $jeNumber',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              Navigator.of(context).pop();
                              JournalEntryNavigationService.openById(
                                context,
                                journalEntryId: jeId,
                              );
                            },
                            icon: const Icon(Icons.open_in_new, size: 14),
                            label: const Text('عرض القيد', style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                            style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    'تكلفة الكرتونة الجديدة: ${_currencyFormat.format(_newCartonCost)} ج.م',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: const Color(0xFF041E42),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('إغلاق', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      debugPrint('Settlement submission error: $e');
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء تأكيد التسوية: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _settleSingleCostItem(Map<String, dynamic> item) async {
    final id = item['id'] as int;
    final act = _getItemActual(id);
    final est = _getItemEstimated(item);
    final invRef = _invoiceControllers[id]?.text.trim() ?? '';
    final notes = _notesControllers[id]?.text.trim() ?? '';
    final diff = act - est;

    final name = item['name']?.toString() ?? 'بند تكلفة';
    final category = item['category']?.toString() ?? '';
    final suppType = item['supplier_type']?.toString() ?? '';
    final suppName = item['supplier_name']?.toString();

    final isEngineer = category == 'engineer_expenses' ||
        category == 'engineer' ||
        name.contains('مهندس') ||
        name.contains('مهندسين') ||
        suppType == 'engineer' ||
        item['custody_id'] != null;
    final isStation = !isEngineer &&
        (category == 'station' ||
            category == 'station_supplier' ||
            name.contains('محطة') ||
            suppType == 'station' ||
            item['station_supplier_id'] != null);
    final isDeduction = !isEngineer &&
        !isStation &&
        (category == 'deduction' ||
            category == 'deductions' ||
            name.contains('تخصيم') ||
            suppType == 'deduction' ||
            suppType == 'deductions');
    final isTransport = !isEngineer &&
        !isStation &&
        !isDeduction &&
        (category == 'logistics' ||
            category == 'transport' ||
            name.contains('نقل') ||
            name.contains('شحن') ||
            name.contains('سيار') ||
            suppType == 'transport' ||
            item['transport_supplier_id'] != null);
    final isAdmin = !isEngineer &&
        !isStation &&
        !isDeduction &&
        !isTransport &&
        (category == 'admin' ||
            name.contains('إدار') ||
            name.contains('ادار') ||
            suppType == 'admin');

    String title = 'تأكيد تسوية التكلفة الفعلية';
    IconData icon = Icons.check_circle_outline;
    Color color = AppTheme.primary;

    if (isEngineer) {
      title = 'تأكيد تسوية مصاريف المهندسين والعهدة';
      icon = Icons.engineering_outlined;
      color = const Color(0xFFF59E0B);
    } else if (isStation) {
      title = 'تأكيد تسوية مورد المحطة';
      icon = Icons.domain_verification_outlined;
      color = const Color(0xFF0D9488);
    } else if (isDeduction) {
      title = 'تأكيد تسوية مورد التخصيمات';
      icon = Icons.fact_check_outlined;
      color = const Color(0xFF6366F1);
    } else if (isAdmin) {
      title = 'تأكيد تسوية المصاريف الإدارية';
      icon = Icons.admin_panel_settings_outlined;
      color = const Color(0xFF8B5CF6);
    } else if (isTransport) {
      title = 'تأكيد تسوية مصاريف النقل';
      icon = Icons.local_shipping_outlined;
      color = const Color(0xFF2563EB);
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF07213D) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppTheme.textPrimary : Colors.black,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'البند: $name${suppName != null && suppName.isNotEmpty && suppName != name ? " ($suppName)" : ""}',
                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
              ),
              if (!isTransport) ...[
                Text(
                  'التكلفة التقديرية: ${_currencyFormat.format(est)} ج.م',
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                ),
              ] else ...[
                const Text(
                  'التكلفة التقديرية: — (فعلي فقط)',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
              Text(
                'التكلفة الفعلية المدخلة: ${_currencyFormat.format(act)} ج.م',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
              ),
              if (!isTransport)
                Text(
                  'فرق التكلفة: ${diff > 0 ? "+" : ""}${_currencyFormat.format(diff)} ج.م',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: diff > 0 ? const Color(0xFFF97316) : (diff < 0 ? AppTheme.accent : AppTheme.textSecondary),
                  ),
                ),
              const SizedBox(height: 12),
              const Text(
                'سيتم ترحيل قيد التسوية وتحديث تكلفة الكرتونة وربحية الشحنات فوراً.',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppTheme.textMuted),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: AppTheme.textMuted)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('تأكيد التسوية', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _adminSettlingItems.add(id));

    try {
      final res = await _dao.settleCostVariancesBatch(
        packingOrderId: widget.packingOrderId,
        settlements: [
          {
            'cost_item_id': id,
            'actual_amount': act,
            'invoice_ref': invRef.isNotEmpty
                ? invRef
                : (_effectiveShipmentNo.isNotEmpty ? _effectiveShipmentNo : 'تسوية تكلفة فعلية ($name)'),
            'notes': notes.isNotEmpty ? notes : 'تسوية منفردة للبند من شاشة المقارنة',
          }
        ],
      );

      if (res['success'] != true) {
        throw Exception(res['error'] ?? 'فشلت عملية التسوية');
      }

      _adminForceEditingItems.remove(id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تمت تسوية $name وتحديث الأرباح بنجاح ✓', style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            backgroundColor: AppTheme.success,
          ),
        );
        widget.onSettled?.call();
        await _loadData();
      }
    } catch (e) {
      debugPrint('Error settling single cost item: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في التسوية: $e', style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _adminSettlingItems.remove(id));
      }
    }
  }

  Widget _buildConfirmBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: AppTheme.primary, fontSize: 14, fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final orderNum = widget.orderNumber ??
        _varianceData?['order_number'] ??
        widget.order?.orderNumber ??
        '#${widget.packingOrderId}';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.92,
              maxWidth: 1080,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFA051B33) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 100 : 30),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildHeader(orderNum, isDark),
                if (_loading)
                  const Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: AppTheme.primary),
                          SizedBox(height: 16),
                          Text(
                            'جاري جلب تفاصيل التكاليف التقديرية والفعلية...',
                            style: TextStyle(fontFamily: 'Cairo', color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_errorMessage != null)
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, color: AppTheme.danger, size: 48),
                            const SizedBox(height: 12),
                            Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontFamily: 'Cairo', color: AppTheme.danger),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _loadData,
                              icon: const Icon(Icons.refresh),
                              label: const Text('إعادة المحاولة', style: TextStyle(fontFamily: 'Cairo')),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSummaryKpis(isDark),
                          const SizedBox(height: 16),
                          if (_shipments.isNotEmpty) ...[
                            _buildShipmentProfitabilityCard(isDark),
                            const SizedBox(height: 16),
                          ],
                          _buildComparisonTableHeader(isDark),
                          const SizedBox(height: 8),
                          _buildItemsList(isDark),
                          const SizedBox(height: 16),
                          _buildGeneralNotesField(isDark),
                        ],
                      ),
                    ),
                  ),
                _buildFooterActions(isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String orderNum, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF04162B) : const Color(0xFFF1F5F9),
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withAlpha(25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.balance, color: AppTheme.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تسوية فروق التكاليف الفعلية وإعادة احتساب الربحية',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppTheme.textPrimary : Colors.black,
                  ),
                ),
                Text(
                  'أمر تعبئة: $orderNum | عدد الكراتين: ${_cartonsCount.toInt()}${_effectiveShipmentNo.isNotEmpty ? ' | شحنة: $_effectiveShipmentNo' : ''}',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppTheme.textSecondary : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: AppTheme.textSecondary),
            tooltip: 'إغلاق',
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryKpis(bool isDark) {
    final netVar = _netVariance;
    final isSaving = netVar < 0;
    final isIncrease = netVar > 0;
    final varColor = isSaving ? AppTheme.success : (isIncrease ? AppTheme.danger : AppTheme.textSecondary);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 700;
        final cardWidth = isMobile ? (constraints.maxWidth - 12) / 2 : (constraints.maxWidth - 36) / 4;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildKpiCard(
              title: 'إجمالي التكاليف التقديرية',
              value: '${_currencyFormat.format(_totalEstimated)} ج.م',
              icon: Icons.history_toggle_off,
              iconColor: const Color(0xFF60A5FA),
              subtext: 'المعياري من الوصفة/الأمر',
              width: cardWidth,
              isDark: isDark,
            ),
            _buildKpiCard(
              title: 'إجمالي التكاليف الفعلية',
              value: '${_currencyFormat.format(_totalActual)} ج.م',
              icon: Icons.receipt_long,
              iconColor: AppTheme.primary,
              subtext: 'المحدث من الفواتير',
              width: cardWidth,
              isDark: isDark,
            ),
            _buildKpiCard(
              title: 'صافي فرق التكلفة',
              value: '${netVar > 0 ? "+" : ""}${_currencyFormat.format(netVar)} ج.م',
              icon: isSaving ? Icons.trending_down : (isIncrease ? Icons.trending_up : Icons.drag_handle),
              iconColor: varColor,
              valueColor: varColor,
              subtext: isSaving ? 'وفر في المصروفات ✓' : (isIncrease ? 'زيادة مصروفات ⚠️' : 'مطابق للتقديري'),
              width: cardWidth,
              isDark: isDark,
            ),
            _buildKpiCard(
              title: 'تكلفة الكرتونة المتوقعة',
              value: '${_currencyFormat.format(_newCartonCost)} ج.م',
              icon: Icons.inventory_2_outlined,
              iconColor: const Color(0xFFF59E0B),
              subtext: 'الحالية: ${_currencyFormat.format(_currentCartonCost)} ج.م',
              width: cardWidth,
              isDark: isDark,
            ),
          ],
        );
      },
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    required String subtext,
    required double width,
    required bool isDark,
    Color? valueColor,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF07213D) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppTheme.textSecondary : Colors.black,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: valueColor ?? (isDark ? AppTheme.textPrimary : Colors.black),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtext,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isDark ? AppTheme.textMuted : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShipmentProfitabilityCard(bool isDark) {
    final shipment = _shipments.first;
    final shipNo = shipment['shipment_no']?.toString() ?? 'شحنة تصدير';
    final custName = shipment['customer_name']?.toString() ?? 'عميل تصدير';
    final totalRevenue = ((shipment['total_revenue_egp'] ?? 0) as num).toDouble();
    final curLanded = ((shipment['total_landed_cost'] ?? 0) as num).toDouble();
    final curProfit = ((shipment['net_profit_egp'] ?? 0) as num).toDouble();

    // Calculate updated landed cost & profit
    final orderCartons = ((shipment['order_cartons_in_shipment'] ?? _cartonsCount) as num).toDouble();
    final unitCostDiff = _newCartonCost - _currentCartonCost;
    final totalPackingDiff = orderCartons * unitCostDiff;
    final newLanded = curLanded + totalPackingDiff;
    final adminExp = ((shipment['allocated_admin_expenses'] ?? 0) as num).toDouble();
    final taxes = ((shipment['allocated_taxes'] ?? 0) as num).toDouble();
    final newProfit = totalRevenue - newLanded - adminExp - taxes;
    final profitDiff = newProfit - curProfit;

    final isProfitIncrease = profitDiff > 0;
    final profitColor = isProfitIncrease
        ? AppTheme.success
        : (profitDiff < 0 ? AppTheme.danger : AppTheme.textSecondary);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xAA072545) : const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isProfitIncrease
              ? AppTheme.success.withAlpha(90)
              : AppTheme.primary.withAlpha(90),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_graph, color: AppTheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'إعادة احتساب ربحية الشحنة المرتبطة ($shipNo - $custName)',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: profitColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: profitColor.withAlpha(80)),
                ),
                child: Text(
                  profitDiff >= 0
                      ? 'تأثير الربح: +${_currencyFormat.format(profitDiff)} ج.م'
                      : 'تأثير الربح: ${_currencyFormat.format(profitDiff)} ج.م',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: profitColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildShipmentMetric(
                  'إجمالي إيراد الشحنة',
                  '${_currencyFormat.format(totalRevenue)} ج.م',
                  AppTheme.textPrimary,
                  isDark,
                ),
              ),
              Expanded(
                child: _buildShipmentMetric(
                  'تكلفة الهبوط (Landed)',
                  '${_currencyFormat.format(curLanded)} ➔ ${_currencyFormat.format(newLanded)} ج.م',
                  AppTheme.warning,
                  isDark,
                ),
              ),
              Expanded(
                child: _buildShipmentMetric(
                  'صافي الربح المتوقع',
                  '${_currencyFormat.format(curProfit)} ➔ ${_currencyFormat.format(newProfit)} ج.م',
                  profitColor,
                  isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShipmentMetric(String label, String value, Color color, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isDark ? AppTheme.textSecondary : Colors.black,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildComparisonTableHeader(bool isDark) {
    return Row(
      children: [
        const Icon(Icons.table_chart_outlined, size: 18, color: AppTheme.primary),
        const SizedBox(width: 8),
        Text(
          'جدول مقارنة بنود التكلفة (التقديري vs الفعلي)',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isDark ? AppTheme.textPrimary : Colors.black,
          ),
        ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: _copyAllEstimatedToActual,
          icon: const Icon(Icons.copy, size: 14),
          label: const Text(
            'نسخ التقديري كفعلي لجميع البنود',
            style: TextStyle(fontFamily: 'Cairo', fontSize: 11),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primary,
            side: const BorderSide(color: AppTheme.primary),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  Widget _buildItemsList(bool isDark) {
    if (_items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF07213D) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          'لا توجد بنود تكلفة إضافية مسجلة في هذا الأمر.',
          style: TextStyle(fontFamily: 'Cairo', color: AppTheme.textSecondary),
        ),
      );
    }

    return Column(
      children: _items.map((item) => _buildCostItemRow(item, isDark)).toList(),
    );
  }

  Widget _buildCostItemRow(Map<String, dynamic> item, bool isDark) {
    final id = item['id'] as int;
    final name = item['name']?.toString() ?? 'بند تكلفة';
    final category = item['category']?.toString() ?? '';
    final supplierName = item['supplier_name']?.toString();
    final est = _getItemEstimated(item);
    final variance = _getItemVariance(item);
    final costStatus = item['cost_status']?.toString() ?? 'estimated';
    final isAlreadyActual = (costStatus == 'actual' ||
            item['settled_actual'] == true ||
            item['is_settled_actual'] == true ||
            item['variance_journal_entry_id'] != null) &&
        item['actual_amount'] != null;
    final jeId = item['settlement_journal_entry_id'] ?? item['variance_journal_entry_id'];

    final suppType = item['supplier_type']?.toString() ?? '';
    final isStation = category == 'station' ||
        category == 'station_supplier' ||
        name.contains('محطة') ||
        suppType == 'station' ||
        item['station_supplier_id'] != null;
    final isDeduction = !isStation &&
        (category == 'deduction' ||
            category == 'deductions' ||
            name.contains('تخصيم') ||
            suppType == 'deduction' ||
            suppType == 'deductions');
    final isTransport = !isStation && !isDeduction && _isTransportItem(item);
    final isEngineer = !isStation &&
        !isDeduction &&
        !isTransport &&
        (category == 'engineer_expenses' ||
            category == 'engineer' ||
            name.contains('مهندس') ||
            name.contains('مهندسين') ||
            suppType == 'engineer' ||
            item['custody_id'] != null);
    final isAdmin = !isStation &&
        !isDeduction &&
        !isTransport &&
        !isEngineer &&
        (category == 'admin' ||
            name.contains('إدار') ||
            name.contains('ادار') ||
            suppType == 'admin');

    final isSettledItem = isAlreadyActual && !_adminForceEditingItems.contains(id);

    String actionLabel = 'تسوية التكلفة الفعلية';
    IconData actionIcon = Icons.check_circle_outline;
    Color actionColor = AppTheme.primary;

    if (isEngineer) {
      actionLabel = 'تسوية مصاريف المهندسين';
      actionIcon = Icons.engineering_outlined;
      actionColor = const Color(0xFFF59E0B);
    } else if (isStation) {
      actionLabel = 'تسوية مورد المحطة';
      actionIcon = Icons.domain_verification_outlined;
      actionColor = const Color(0xFF0D9488);
    } else if (isDeduction) {
      actionLabel = 'تسوية مورد التخصيمات';
      actionIcon = Icons.fact_check_outlined;
      actionColor = const Color(0xFF6366F1);
    } else if (isAdmin) {
      actionLabel = 'تسوية المصاريف الإدارية';
      actionIcon = Icons.admin_panel_settings_outlined;
      actionColor = const Color(0xFF8B5CF6);
    } else if (isTransport) {
      actionLabel = 'تسوية مصاريف النقل';
      actionIcon = Icons.local_shipping_outlined;
      actionColor = const Color(0xFF2563EB);
    }

    final varColor = variance < 0
        ? AppTheme.success
        : (variance > 0 ? AppTheme.danger : AppTheme.textMuted);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF07213D) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Name, Category, Badges & Action
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppTheme.textPrimary : Colors.black,
                      ),
                    ),
                    if (isEngineer)
                      _buildChip('مصاريف مهندسين (31251)', const Color(0xFFF59E0B))
                    else if (isTransport)
                      _buildChip('نقل (21111)', const Color(0xFF3B82F6))
                    else if (isAdmin)
                      _buildChip('إداري (31331)', const Color(0xFF8B5CF6))
                    else if (isStation)
                      _buildChip('مورد محطة', const Color(0xFF0D9488))
                    else if (isDeduction)
                      _buildChip('مورد تخصيمات', const Color(0xFF6366F1))
                    else if (category.isNotEmpty)
                      _buildChip(category, AppTheme.textSecondary),
                    if (supplierName != null && supplierName.isNotEmpty)
                      _buildChip(supplierName, const Color(0xFF10B981)),
                  ],
                ),
              ),
              if (isSettledItem) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.success.withAlpha(60)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'مكتمل فعلياً ✓',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.success,
                        ),
                      ),
                      if (jeId != null) ...[
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => JournalEntryNavigationService.openById(
                            context,
                            journalEntryId: jeId,
                          ),
                          child: const Icon(Icons.open_in_new, size: 12, color: AppTheme.primary),
                        ),
                      ],
                    ],
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.warning.withAlpha(60)),
                  ),
                  child: const Text(
                    'تقديري ⏳',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.warning,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _adminSettlingItems.contains(id) ? null : () => _settleSingleCostItem(item),
                  icon: _adminSettlingItems.contains(id)
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(actionIcon, size: 14),
                  label: Text(
                    actionLabel,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: actionColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 1,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // Grid / Form inputs for this item
          LayoutBuilder(
            builder: (ctx, constraints) {
              final isNarrow = constraints.maxWidth < 650;
              if (isNarrow) {
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: _buildEstimatedReadOnlyField(est, isDark, isTransport: isTransport)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: isSettledItem
                              ? _buildConfirmedActualReadOnlyField(
                                  _getItemActual(id),
                                  isDark,
                                  onEdit: () => setState(() => _adminForceEditingItems.add(id)),
                                )
                              : _buildActualInputField(id, isDark),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _buildVarianceBadge(variance, varColor, isDark, isTransport: isTransport)),
                        const SizedBox(width: 10),
                        Expanded(child: _buildInvoiceRefField(id, isDark)),
                      ],
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 1. Estimated
                  Expanded(flex: 2, child: _buildEstimatedReadOnlyField(est, isDark, isTransport: isTransport)),
                  const SizedBox(width: 10),
                  // 2. Actual Input
                  Expanded(
                    flex: 2,
                    child: isSettledItem
                        ? _buildConfirmedActualReadOnlyField(
                            _getItemActual(id),
                            isDark,
                            onEdit: () => setState(() => _adminForceEditingItems.add(id)),
                          )
                        : _buildActualInputField(id, isDark),
                  ),
                  const SizedBox(width: 10),
                  // 3. Variance Badge
                  Expanded(flex: 2, child: _buildVarianceBadge(variance, varColor, isDark, isTransport: isTransport)),
                  const SizedBox(width: 10),
                  // 4. Invoice Reference
                  Expanded(flex: 2, child: _buildInvoiceRefField(id, isDark)),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          // Notes row for this item
          _buildItemNotesField(id, isDark),
        ],
      ),
    );
  }

  Widget _buildConfirmedActualReadOnlyField(double actual, bool isDark, {VoidCallback? onEdit}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'الفعلي (مؤكد)',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: AppTheme.success, fontWeight: FontWeight.bold),
            ),
            if (onEdit != null)
              GestureDetector(
                onTap: onEdit,
                child: const Text(
                  'تعديل',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF031628) : const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppTheme.success.withAlpha(80),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_currencyFormat.format(actual)} ج.م',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.success,
                  ),
                ),
              ),
              const Icon(Icons.check_circle, size: 14, color: AppTheme.success),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildEstimatedReadOnlyField(double est, bool isDark, {bool isTransport = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'التقديري (معياري)',
          style: TextStyle(fontFamily: 'Cairo', fontSize: 10, fontWeight: FontWeight.bold, color: isDark ? AppTheme.textMuted : Colors.black),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF031628) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1),
            ),
          ),
          child: Text(
            isTransport ? '— (فعلي فقط)' : '${_currencyFormat.format(est)} ج.م',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isTransport ? (isDark ? AppTheme.textMuted : Colors.black54) : (isDark ? AppTheme.textPrimary : Colors.black),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActualInputField(int id, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'الفعلي (فاتورة)',
          style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: _actualControllers[id],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isDark ? AppTheme.textPrimary : Colors.black,
          ),
          decoration: InputDecoration(
            isDense: true,
            suffixText: 'ج.م',
            suffixStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: AppTheme.textMuted),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            filled: true,
            fillColor: isDark ? const Color(0xFF04192F) : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.primary),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _buildVarianceBadge(double variance, Color color, bool isDark, {bool isTransport = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'فرق التكلفة',
          style: TextStyle(fontFamily: 'Cairo', fontSize: 10, fontWeight: FontWeight.bold, color: isDark ? AppTheme.textMuted : Colors.black),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isTransport ? (isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9)) : color.withAlpha(20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isTransport ? (isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0)) : color.withAlpha(60)),
          ),
          child: Text(
            isTransport ? '— (فعلي فقط)' : '${variance > 0 ? "+" : ""}${_currencyFormat.format(variance)} ج.م',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isTransport ? (isDark ? AppTheme.textMuted : Colors.black54) : color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInvoiceRefField(int id, bool isDark) {
    final controller = _invoiceControllers[id];
    final currentVal = controller?.text.trim() ?? '';
    final isShipmentVal = _effectiveShipmentNo.isNotEmpty && currentVal == _effectiveShipmentNo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'رقم الفاتورة / المستند',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isDark ? AppTheme.textMuted : Colors.black,
              ),
            ),
            const Spacer(),
            if (_effectiveShipmentNo.isNotEmpty) ...[
              if (isShipmentVal)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(25),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.primary.withAlpha(60)),
                  ),
                  child: const Text(
                    'رقم الشحنة ✓',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                )
              else
                InkWell(
                  onTap: () {
                    setState(() {
                      controller?.text = _effectiveShipmentNo;
                    });
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sync, size: 10, color: AppTheme.primary),
                        const SizedBox(width: 2),
                        Text(
                          'تعيين كـ ($_effectiveShipmentNo)',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          onChanged: (_) => setState(() {}),
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isDark ? AppTheme.textPrimary : Colors.black,
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: _effectiveShipmentNo.isNotEmpty ? 'رقم الشحنة: $_effectiveShipmentNo' : 'مثال: INV-2026/041',
            hintStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppTheme.textMuted),
            prefixIcon: const Icon(Icons.receipt_long, size: 14, color: AppTheme.textMuted),
            suffixIcon: _effectiveShipmentNo.isNotEmpty && currentVal != _effectiveShipmentNo
                ? IconButton(
                    icon: const Icon(Icons.replay, size: 14, color: AppTheme.primary),
                    tooltip: 'استعادة رقم الشحنة ($_effectiveShipmentNo)',
                    onPressed: () {
                      setState(() {
                        controller?.text = _effectiveShipmentNo;
                      });
                    },
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            filled: true,
            fillColor: isDark ? const Color(0xFF04192F) : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isShipmentVal
                    ? AppTheme.primary.withAlpha(120)
                    : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppTheme.primary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItemNotesField(int id, bool isDark) {
    return TextFormField(
      controller: _notesControllers[id],
      style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? AppTheme.textPrimary : Colors.black),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'ملاحظات المحاسب للبند (اختياري)...',
        hintStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: AppTheme.textMuted),
        prefixIcon: const Icon(Icons.notes, size: 14, color: AppTheme.textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        filled: true,
        fillColor: isDark ? const Color(0x66031628) : const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0)),
        ),
      ),
    );
  }

  Widget _buildGeneralNotesField(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF07213D) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ملاحظات عامة لتسوية القيد المحاسبي',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? AppTheme.textPrimary : Colors.black,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _generalNotesController,
            maxLines: 2,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? AppTheme.textPrimary : Colors.black),
            decoration: InputDecoration(
              hintText: 'سجل أي ملاحظات تفصيلية ليتم إرفاقها بدفتر اليومية والقيد المحاسبي...',
              hintStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppTheme.textMuted),
              filled: true,
              fillColor: isDark ? const Color(0xFF04192F) : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterActions(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF04162B) : const Color(0xFFF1F5F9),
        border: Border(
          top: BorderSide(
            color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: AppTheme.textMuted)),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: (_loading || _isSubmitting) ? null : _submitSettlement,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF041E42)),
                  )
                : const Icon(Icons.verified_outlined, size: 18),
            label: Text(
              _isSubmitting ? 'جاري الترحيل وتوليد القيود...' : 'تأكيد التسوية الفعلية وترحيل القيد',
              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: const Color(0xFF041E42),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}
