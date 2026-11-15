import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/widgets/order_range_filter_field.dart';
import '../../core/widgets/estimated_cost_delete_helper.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/data_change_event_bus.dart';
import '../../core/language_dialog.dart';
import '../../core/cost_settlement_pdf_service.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/dao/packing_order_dao.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/supplier_expected_cost_item_model.dart';

class SupplierCostSettlementView extends StatefulWidget {
  final String supplierType; // 'station' or 'deduction'
  final String? preselectedSupplierId;

  const SupplierCostSettlementView({
    super.key,
    required this.supplierType,
    this.preselectedSupplierId,
  });

  @override
  State<SupplierCostSettlementView> createState() =>
      _SupplierCostSettlementViewState();
}

class _SupplierCostSettlementViewState
    extends State<SupplierCostSettlementView> {
  final SupplierDao _dao = SupplierDao();
  bool _loading = true;
  List<SupplierExpectedCostItemModel> _items = [];
  List<SupplierModel> _suppliers = [];

  String _searchQuery = '';
  String? _selectedSupplierId;
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _filterOnlyPending = false;
  bool _isPrinting = false;
  bool _isSavingSettlement = false;
  bool _isControlsExpanded = true;

  late final StreamSubscription<void> _sub;
  late final StreamSubscription<void> _poSub;
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _fromOrderCtrl = TextEditingController();
  final TextEditingController _toOrderCtrl = TextEditingController();
  bool _loadedWithOrderRange = false;

  int? get _fromOrderId =>
      OrderRangeFilterHelper.parseFilterBound(_fromOrderCtrl.text);
  int? get _toOrderId =>
      OrderRangeFilterHelper.parseFilterBound(_toOrderCtrl.text);

  // ── Master Invoice / Auto-distribution Controllers ──
  final TextEditingController _overallActualCtrl = TextEditingController();
  final TextEditingController _overallQtyCtrl = TextEditingController(text: '1');
  final TextEditingController _overallUnitPriceCtrl = TextEditingController();
  final TextEditingController _overallNotesCtrl = TextEditingController();
  DateTime _overallInvoiceDateTime = DateTime.now();
  String _distributionMethod = 'proportional'; // 'proportional' or 'equal'

  // ── Per-Row Controllers & State ──
  final Map<dynamic, TextEditingController> _itemActualCtrls = {};
  final Map<dynamic, TextEditingController> _itemQtyCtrls = {};
  final Map<dynamic, TextEditingController> _itemUnitPriceCtrls = {};
  final Map<dynamic, TextEditingController> _itemNotesCtrls = {};
  final Map<dynamic, DateTime> _itemDateTimes = {};
  final Map<dynamic, List<double>> _itemUnitPriceBreakdowns = {};
  final Set<dynamic> _modifiedItemKeys = {};
  final Set<dynamic> _unlockedItemKeys = {};
  final Set<dynamic> _settlingItemKeys = {};
  final Set<dynamic> _deletingItemKeys = {};

  static const String _settlementUnlockPassword = 'eslam2026';

  @override
  void initState() {
    super.initState();
    _selectedSupplierId = (widget.preselectedSupplierId != null &&
            widget.preselectedSupplierId!.trim().isNotEmpty)
        ? widget.preselectedSupplierId!.trim()
        : null;
    _loadData();
    _sub = DataChangeEventBus.instance.suppliersStream.listen((_) {
      _loadData();
    });
    _poSub = DataChangeEventBus.instance.packingOrdersStream.listen((_) {
      _loadData();
    });
  }

  @override
  void didUpdateWidget(covariant SupplierCostSettlementView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preselectedSupplierId != widget.preselectedSupplierId) {
      setState(() {
        _selectedSupplierId = (widget.preselectedSupplierId != null &&
                widget.preselectedSupplierId!.trim().isNotEmpty)
            ? widget.preselectedSupplierId!.trim()
            : null;
      });
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    _poSub.cancel();
    _searchCtrl.dispose();
    _fromOrderCtrl.dispose();
    _toOrderCtrl.dispose();
    _overallActualCtrl.dispose();
    _overallQtyCtrl.dispose();
    _overallUnitPriceCtrl.dispose();
    _overallNotesCtrl.dispose();
    for (final c in _itemActualCtrls.values) {
      c.dispose();
    }
    for (final c in _itemQtyCtrls.values) {
      c.dispose();
    }
    for (final c in _itemUnitPriceCtrls.values) {
      c.dispose();
    }
    for (final c in _itemNotesCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final suppTypes = widget.supplierType == 'station'
          ? ['station']
          : ['deduction', 'deductions'];

      final suppliersList = await _dao.getAll(limit: 2000, supplierTypes: suppTypes);
      // Fetch items for this supplierType (narrowed by order range if requested)
      final fromOrderId = _fromOrderId;
      final toOrderId = _toOrderId;
      final costItems = await _dao.getExpectedCostItems(
        supplierType: widget.supplierType,
        supplierId: null,
        status: null,
        search: null,
        fromOrderId: fromOrderId,
        toOrderId: toOrderId,
        limit: 5000,
      );
      _loadedWithOrderRange = fromOrderId != null || toOrderId != null;

      _syncControllers(costItems);

      if (mounted) {
        setState(() {
          _suppliers = suppliersList;
          _items = costItems;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading cost settlement items: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _syncControllers(List<SupplierExpectedCostItemModel> items) {
    for (final item in items) {
      final key = item.costItemId;

      // 1. Actual amount controller
      if (!_itemActualCtrls.containsKey(key)) {
        final bool isSettled = item.isActual || item.isLocked;
        final double? dbAct = item.actualAmount;
        final String initialText = (isSettled && dbAct != null && dbAct > 0)
            ? dbAct.toStringAsFixed(2)
            : '';
        _itemActualCtrls[key] = TextEditingController(text: initialText);
      }

      // 2. Quantity controller
      if (!_itemQtyCtrls.containsKey(key)) {
        final double qty = item.displayQuantity;
        final String qtyStr = (qty % 1 == 0) ? qty.toInt().toString() : qty.toStringAsFixed(2);
        _itemQtyCtrls[key] = TextEditingController(text: qtyStr);
      }

      // 3. Unit price controller
      if (!_itemUnitPriceCtrls.containsKey(key)) {
        final double up = item.displayUnitPrice;
        _itemUnitPriceCtrls[key] = TextEditingController(
          text: up > 0 ? up.toStringAsFixed(2) : '',
        );
      }

      // 4. Notes controller
      if (!_itemNotesCtrls.containsKey(key)) {
        final String notes = item.detailedNotes ??
            item.settlementNotes ??
            item.invoiceRef ??
            '';
        _itemNotesCtrls[key] = TextEditingController(text: notes);
      }

      // 5. Date & time
      if (!_itemDateTimes.containsKey(key)) {
        _itemDateTimes[key] = item.actualDateTime ??
            item.reconciledAt ??
            item.orderDate ??
            DateTime.now();
      }

      // 6. Unit price breakdowns from currency_snapshot
      if (!_itemUnitPriceBreakdowns.containsKey(key) &&
          item.currencySnapshot is Map) {
        final rawSnap = item.currencySnapshot!;
        final rawPrices = rawSnap['unit_prices'] ?? rawSnap['prices'];
        if (rawPrices is List) {
          final list = rawPrices
              .map((p) => double.tryParse(p.toString()) ?? 0.0)
              .toList();
          if (list.isNotEmpty) {
            _itemUnitPriceBreakdowns[key] = list;
          }
        }
      }
    }
  }

  TextEditingController _getItemActualCtrl(dynamic key, SupplierExpectedCostItemModel item) {
    if (!_itemActualCtrls.containsKey(key)) {
      final bool isSettled = item.isActual || item.isLocked;
      final double? dbAct = item.actualAmount;
      final String initialText = (isSettled && dbAct != null && dbAct > 0)
          ? dbAct.toStringAsFixed(2)
          : '';
      _itemActualCtrls[key] = TextEditingController(text: initialText);
    }
    return _itemActualCtrls[key]!;
  }

  TextEditingController _getItemQtyCtrl(dynamic key, SupplierExpectedCostItemModel item) {
    if (!_itemQtyCtrls.containsKey(key)) {
      final double qty = item.displayQuantity;
      final String qtyStr = (qty % 1 == 0) ? qty.toInt().toString() : qty.toStringAsFixed(2);
      _itemQtyCtrls[key] = TextEditingController(text: qtyStr);
    }
    return _itemQtyCtrls[key]!;
  }

  TextEditingController _getItemUnitPriceCtrl(dynamic key, SupplierExpectedCostItemModel item) {
    if (!_itemUnitPriceCtrls.containsKey(key)) {
      final double up = item.displayUnitPrice;
      _itemUnitPriceCtrls[key] = TextEditingController(
        text: up > 0 ? up.toStringAsFixed(2) : '',
      );
    }
    return _itemUnitPriceCtrls[key]!;
  }

  TextEditingController _getItemNotesCtrl(dynamic key, SupplierExpectedCostItemModel item) {
    if (!_itemNotesCtrls.containsKey(key)) {
      final String notes = item.detailedNotes ??
          item.settlementNotes ??
          item.invoiceRef ??
          '';
      _itemNotesCtrls[key] = TextEditingController(text: notes);
    }
    return _itemNotesCtrls[key]!;
  }

  DateTime _getItemDateTime(dynamic key, SupplierExpectedCostItemModel item) {
    if (!_itemDateTimes.containsKey(key)) {
      _itemDateTimes[key] = item.actualDateTime ??
          item.reconciledAt ??
          item.orderDate ??
          DateTime.now();
    }
    return _itemDateTimes[key]!;
  }

  bool _isItemLocked(SupplierExpectedCostItemModel item) {
    return item.isLocked || item.isActual || item.costStatus == 'actual' || item.costStatus == 'settled';
  }

  void _onRowQtyOrPriceChanged(dynamic key, SupplierExpectedCostItemModel item) {
    final qty = double.tryParse(_itemQtyCtrls[key]?.text.replaceAll(',', '').trim() ?? '') ?? 1.0;
    final unitPrice = double.tryParse(_itemUnitPriceCtrls[key]?.text.replaceAll(',', '').trim() ?? '') ?? 0.0;
    if (qty > 0 && unitPrice > 0) {
      final total = qty * unitPrice;
      _itemActualCtrls[key]?.text = total.toStringAsFixed(2);
    }
    setState(() {
      _modifiedItemKeys.add(key);
    });
  }

  void _onRowActualChanged(dynamic key, SupplierExpectedCostItemModel item) {
    final actAmt = double.tryParse(_itemActualCtrls[key]?.text.replaceAll(',', '').trim() ?? '') ?? 0.0;
    final qty = double.tryParse(_itemQtyCtrls[key]?.text.replaceAll(',', '').trim() ?? '') ?? 1.0;
    if (qty > 0 && actAmt > 0) {
      _itemUnitPriceCtrls[key]?.text = (actAmt / qty).toStringAsFixed(2);
    }
    setState(() {
      _modifiedItemKeys.add(key);
    });
  }

  List<SupplierExpectedCostItemModel> get _filteredItems {
    return _items.where((item) {
      // 1. Pending vs Settled filter
      if (_filterOnlyPending) {
        if (_isItemLocked(item) && !_unlockedItemKeys.contains(item.costItemId)) {
          return false;
        }
      }

      // 2. Strict Supplier Filter & Data Binding
      if (_selectedSupplierId != null && _selectedSupplierId!.isNotEmpty) {
        final selId = _selectedSupplierId!.trim().toLowerCase();
        SupplierModel? selectedSupplier;
        for (final s in _suppliers) {
          if (s.id?.trim().toLowerCase() == selId) {
            selectedSupplier = s;
            break;
          }
        }

        bool matches = false;

        // A. Match by supplier_id
        if (item.supplierId != null && item.supplierId!.trim().isNotEmpty) {
          final itemSupId = item.supplierId!.trim().toLowerCase();
          if (itemSupId == selId) {
            matches = true;
          } else if (selectedSupplier != null) {
            if (selectedSupplier.id?.trim().toLowerCase() == itemSupId ||
                selectedSupplier.supplierCode.trim().toLowerCase() == itemSupId ||
                selectedSupplier.accountId?.toString() == itemSupId) {
              matches = true;
            }
          }
        }

        // B. Match by supplier_code
        if (!matches && selectedSupplier != null && item.supplierCode != null && item.supplierCode!.trim().isNotEmpty) {
          if (item.supplierCode!.trim().toLowerCase() == selectedSupplier.supplierCode.trim().toLowerCase()) {
            matches = true;
          }
        }

        // C. Match by supplier_name
        if (!matches && selectedSupplier != null && item.supplierName != null && item.supplierName!.trim().isNotEmpty) {
          final iName = item.supplierName!.trim().toLowerCase();
          final sName = selectedSupplier.name.trim().toLowerCase();
          if (iName == sName || iName.contains(sName) || sName.contains(iName)) {
            matches = true;
          }
        }

        // D. Currency snapshot supplier fallback
        if (!matches && item.currencySnapshot is Map) {
          final snapSupId = item.currencySnapshot!['supplier_id']?.toString().trim().toLowerCase();
          final snapSupName = item.currencySnapshot!['supplier_name']?.toString().trim().toLowerCase();
          final snapSupCode = item.currencySnapshot!['supplier_code']?.toString().trim().toLowerCase();

          if (snapSupId != null && snapSupId == selId) {
            matches = true;
          } else if (selectedSupplier != null) {
            if (snapSupCode != null && snapSupCode == selectedSupplier.supplierCode.trim().toLowerCase()) {
              matches = true;
            } else if (snapSupName != null && (snapSupName == selectedSupplier.name.trim().toLowerCase() || snapSupName.contains(selectedSupplier.name.trim().toLowerCase()))) {
              matches = true;
            }
          }
        }

        if (!matches) return false;
      }

      // 3. Exact Date Range Filter (from 00:00:00.000 to 23:59:59.999 Local time)
      if (_fromDate != null || _toDate != null) {
        final rawDate = _itemDateTimes[item.costItemId] ??
            item.actualDateTime ??
            item.reconciledAt ??
            item.orderDate;

        if (rawDate == null) {
          return false;
        }

        final itemDate = rawDate.toLocal();

        if (_fromDate != null) {
          final startOfDay = DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day, 0, 0, 0, 0);
          if (itemDate.isBefore(startOfDay)) return false;
        }

        if (_toDate != null) {
          final endOfDay = DateTime(_toDate!.year, _toDate!.month, _toDate!.day, 23, 59, 59, 999);
          if (itemDate.isAfter(endOfDay)) return false;
        }
      }

      // 3.5 Shipment / Packing Order Numeric Range Filter
      if (!OrderRangeFilterHelper.matchesOrderRange(
        orderNumber: item.orderNumber,
        packingOrderId: item.packingOrderId,
        fromOrderId: _fromOrderId,
        toOrderId: _toOrderId,
      )) {
        return false;
      }

      // 4. Text Search Query Filter
      final q = _searchQuery.trim().toLowerCase();
      if (q.isNotEmpty) {
        final matches = item.orderNumber.toLowerCase().contains(q) ||
            item.itemName.toLowerCase().contains(q) ||
            (item.supplierName?.toLowerCase().contains(q) ?? false) ||
            (item.supplierCode?.toLowerCase().contains(q) ?? false) ||
            (item.invoiceRef?.toLowerCase().contains(q) ?? false) ||
            (item.detailedNotes?.toLowerCase().contains(q) ?? false);
        if (!matches) return false;
      }

      return true;
    }).toList();
  }

  void _setDatePreset(String preset) {
    final now = DateTime.now();
    setState(() {
      if (preset == 'today') {
        _fromDate = DateTime(now.year, now.month, now.day);
        _toDate = DateTime(now.year, now.month, now.day);
      } else if (preset == 'week') {
        _fromDate = now.subtract(const Duration(days: 7));
        _toDate = now;
      } else if (preset == 'month') {
        _fromDate = DateTime(now.year, now.month, 1);
        _toDate = now;
      } else if (preset == 'all') {
        _fromDate = null;
        _toDate = null;
      }
    });
  }

  bool _isPresetToday() {
    if (_fromDate == null || _toDate == null) return false;
    final now = DateTime.now();
    return _fromDate!.year == now.year &&
        _fromDate!.month == now.month &&
        _fromDate!.day == now.day &&
        _toDate!.year == now.year &&
        _toDate!.month == now.month &&
        _toDate!.day == now.day;
  }

  bool _isPresetMonth() {
    if (_fromDate == null || _toDate == null) return false;
    final now = DateTime.now();
    return _fromDate!.year == now.year &&
        _fromDate!.month == now.month &&
        _fromDate!.day == 1 &&
        _toDate!.year == now.year &&
        _toDate!.month == now.month &&
        _toDate!.day == now.day;
  }

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: 'من تاريخ',
    );
    if (picked != null) {
      setState(() => _fromDate = picked);
    }
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: 'إلى تاريخ',
    );
    if (picked != null) {
      setState(() => _toDate = picked);
    }
  }

  Future<DateTime?> _pickDateTimeDialog(BuildContext context, DateTime initial) async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: AppTheme.primary,
          ),
        ),
        child: child!,
      ),
    );
    if (pickedDate == null || !context.mounted) return null;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: AppTheme.primary,
          ),
        ),
        child: child!,
      ),
    );

    if (pickedTime == null) {
      return DateTime(pickedDate.year, pickedDate.month, pickedDate.day, initial.hour, initial.minute);
    }

    return DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
  }

  // ── Auto Distribution to All Filtered Rows ──
  void _autoDistributeToAll() {
    final double? totalActual = double.tryParse(_overallActualCtrl.text.replaceAll(',', '').trim());
    if (totalActual == null || totalActual <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال إجمالي المبلغ الفعلي في الحقل أعلاه أولاً للتوزيع التلقائي', textDirection: TextDirection.rtl),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    final targetItems = _filteredItems;
    final editableItems = targetItems.where((i) {
      final isLocked = _isItemLocked(i);
      final isUnlocked = _unlockedItemKeys.contains(i.costItemId);
      return (!isLocked) || isUnlocked;
    }).toList();

    if (editableItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('جميع البنود الحالية مقفلة ومعتمدة! يمكنك الضغط على "إتاحة تعديل المقفل 🔒" لإعادة توزيعها.', textDirection: TextDirection.rtl),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    final double totalEstimated = editableItems.fold(0.0, (s, i) => s + i.expectedAmount);
    final String sharedNotes = _overallNotesCtrl.text.trim();
    final double? masterQty = double.tryParse(_overallQtyCtrl.text.replaceAll(',', '').trim());
    final double? masterUnitPrice = double.tryParse(_overallUnitPriceCtrl.text.replaceAll(',', '').trim());

    setState(() {
      for (final item in editableItems) {
        final key = item.costItemId;
        double allocatedActual = 0.0;

        if (_distributionMethod == 'equal' || totalEstimated <= 0) {
          allocatedActual = totalActual / editableItems.length;
        } else {
          final ratio = item.expectedAmount / totalEstimated;
          allocatedActual = totalActual * ratio;
        }

        final roundedActual = double.parse(allocatedActual.toStringAsFixed(2));
        _getItemActualCtrl(key, item).text = roundedActual.toStringAsFixed(2);

        double q = item.displayQuantity;
        if (masterQty != null && masterQty > 0) {
          if (_distributionMethod == 'equal') {
            q = masterQty / editableItems.length;
          } else if (totalEstimated > 0) {
            q = masterQty * (item.expectedAmount / totalEstimated);
          }
        }
        if (q <= 0) q = 1.0;
        final qStr = (q % 1 == 0) ? q.toInt().toString() : q.toStringAsFixed(2);
        _getItemQtyCtrl(key, item).text = qStr;

        if (masterUnitPrice != null && masterUnitPrice > 0 && _distributionMethod == 'equal') {
          _getItemUnitPriceCtrl(key, item).text = masterUnitPrice.toStringAsFixed(2);
        } else {
          final up = q > 0 ? (roundedActual / q) : roundedActual;
          _getItemUnitPriceCtrl(key, item).text = up.toStringAsFixed(2);
        }

        if (sharedNotes.isNotEmpty) {
          _getItemNotesCtrl(key, item).text = sharedNotes;
        }

        _itemDateTimes[key] = _overallInvoiceDateTime;
        _modifiedItemKeys.add(key);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم توزيع مبلغ EGP ${totalActual.toStringAsFixed(2)} على ${editableItems.length} بند بنجاح!', textDirection: TextDirection.rtl),
        backgroundColor: const Color(0xFF10B981),
      ),
    );
  }

  void _resetSettlementToEstimated() {
    setState(() {
      for (final item in _filteredItems) {
        final key = item.costItemId;
        final isLocked = _isItemLocked(item);
        final isUnlocked = _unlockedItemKeys.contains(key);
        if (!isLocked || isUnlocked) {
          _getItemActualCtrl(key, item).text = '';
          _getItemQtyCtrl(key, item).text = '1';
          _getItemUnitPriceCtrl(key, item).text = item.expectedAmount > 0 ? item.expectedAmount.toStringAsFixed(2) : '0.00';
          _getItemNotesCtrl(key, item).text = '';
          _itemUnitPriceBreakdowns.remove(key);
          _modifiedItemKeys.remove(key);
        }
      }
    });
  }

  // ── Password Unlock Dialog ──
  Future<void> _showUnlockPasswordDialog() async {
    final passwordCtrl = TextEditingController();
    bool obscure = true;
    String? localError;

    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final isDark = AppTheme.isDark(dialogCtx);
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.security_rounded, color: Color(0xFFF59E0B), size: 22),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'تعديل المقفل العام (تحقق أمني)',
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'جميع البنود المسواة معتمدة ومقفلة محاسبياً لحماية البيانات ومنع التلاعب.\nيرجى إدخال كلمة المرور المصرح بها لفتح القفل وإتاحة التعديل:',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 12.5, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordCtrl,
                    obscureText: obscure,
                    autofocus: true,
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, letterSpacing: 2),
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور',
                      labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                      hintText: 'أدخل كلمة المرور...',
                      hintStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
                      prefixIcon: const Icon(Icons.key_rounded, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
                        onPressed: () => setDialogState(() => obscure = !obscure),
                      ),
                      errorText: localError,
                      errorStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppTheme.primary, width: 2),
                      ),
                    ),
                    onSubmitted: (val) {
                      if (val.trim() == _settlementUnlockPassword) {
                        Navigator.pop(ctx, true);
                      } else {
                        setDialogState(() {
                          localError = 'كلمة المرور غير صحيحة!';
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    final entered = passwordCtrl.text.trim();
                    if (entered == _settlementUnlockPassword) {
                      Navigator.pop(ctx, true);
                    } else {
                      setDialogState(() {
                        localError = 'كلمة المرور غير صحيحة!';
                      });
                    }
                  },
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('تأكيد وفك القفل', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (success == true) {
      setState(() {
        for (final item in _items) {
          _unlockedItemKeys.add(item.costItemId);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم فك القفل بنجاح! يمكنك الآن تعديل وإعادة تسوية أي بند مقفل ثم حفظه.', textDirection: TextDirection.rtl),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    }
  }

  // ── Dynamic Multi-Unit Price Breakdown Dialog ──
  Future<void> _showUnitPriceBreakdownDialog(dynamic key, SupplierExpectedCostItemModel item, int count) async {
    final isDark = AppTheme.isDark(context);
    final est = item.expectedAmount;
    final poNum = item.orderNumber;
    final itemName = item.itemName;
    final fNumber = NumberFormat('#,##0.00');

    final isLocked = _isItemLocked(item);
    final isUnlocked = _unlockedItemKeys.contains(key);
    final canEdit = (!isLocked) || isUnlocked;

    // استخراج أو تهيئة قائمة الأسعار الفرعية
    List<double> currentPrices = _itemUnitPriceBreakdowns[key] ?? [];
    if (currentPrices.length != count) {
      final old = currentPrices;
      final currentUp = double.tryParse(_itemUnitPriceCtrls[key]?.text.replaceAll(',', '').trim() ?? '') ?? 0.0;
      currentPrices = List<double>.generate(count, (i) {
        if (i < old.length && old[i] > 0) return old[i];
        return currentUp > 0 ? currentUp : 0.0;
      });
    }

    final controllers = List.generate(count, (i) {
      final p = currentPrices[i];
      return TextEditingController(text: p > 0 ? p.toStringAsFixed(2) : '');
    });

    final uniformCtrl = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            double currentTotal = 0.0;
            for (final c in controllers) {
              final v = double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0.0;
              currentTotal += v;
            }
            final avgPrice = count > 0 ? currentTotal / count : 0.0;
            final varianceAmt = currentTotal - est;
            final variancePct = est > 0 ? (varianceAmt / est) * 100 : 0.0;
            final isSaving = currentTotal < est && currentTotal > 0;
            final isOverrun = currentTotal > est;

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.calculate_rounded, color: AppTheme.primary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تفاصيل أسعار الوحدات ($count وحدات)',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.getTextPrimary(context),
                            ),
                          ),
                          Text(
                            'أمر تعبئة #$poNum | $itemName ${item.supplierName != null ? "(${item.supplierName})" : ""}',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              color: AppTheme.getTextSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close, size: 20),
                      tooltip: 'إغلاق',
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 480,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!canEdit) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFF59E0B)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.lock_rounded, size: 18, color: Color(0xFFF59E0B)),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'هذا البند معتمد ومقفل 🔒 (العرض للقراءة فقط). لفك القفل اضغط أدناه.',
                                    style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _showUnlockPasswordDialog();
                                  },
                                  child: const Text('فك القفل', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          // Quick fill tool: Distribute uniform price
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.getBorderColor(context)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'تطبيق سعر موحد على كافة الوحدات:',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      color: AppTheme.getTextSecondary(context),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 95,
                                  height: 34,
                                  child: TextField(
                                    controller: uniformCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold),
                                    decoration: InputDecoration(
                                      hintText: 'السعر',
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                ElevatedButton(
                                  onPressed: () {
                                    final uVal = double.tryParse(uniformCtrl.text.replaceAll(',', '').trim());
                                    if (uVal != null && uVal >= 0) {
                                      for (final c in controllers) {
                                        c.text = uVal.toStringAsFixed(2);
                                      }
                                      setDialogState(() {});
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                  child: const Text('تطبيق', style: TextStyle(fontFamily: 'Cairo', fontSize: 11)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        Text(
                          'أدخل سعر كل وحدة على حدة (بالجنيه EGP):',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.getTextPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // List of dynamic unit price fields
                        ...List.generate(count, (index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.getBorderColor(context)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${index + 1}',
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'سعر الوحدة (${index + 1})',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 12,
                                        color: AppTheme.getTextPrimary(context),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 130,
                                    height: 38,
                                    child: TextField(
                                      controller: controllers[index],
                                      enabled: canEdit,
                                      readOnly: !canEdit,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      textAlign: TextAlign.end,
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.bold,
                                        color: canEdit ? AppTheme.getTextPrimary(context) : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                                      ),
                                      decoration: InputDecoration(
                                        prefixText: 'EGP ',
                                        prefixStyle: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 10.5,
                                          color: AppTheme.getTextSecondary(context),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                        filled: true,
                                        fillColor: !canEdit
                                            ? (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9))
                                            : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onChanged: (_) => setDialogState(() {}),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),

                        const SizedBox(height: 8),

                        // Auto-summation summary card
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'إجمالي القيمة الفعلية (المحسوبة آلياً):',
                                    style: TextStyle(fontFamily: 'Cairo', fontSize: 12.5, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    'EGP ${fNumber.format(currentTotal)}',
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF10B981),
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'متوسط سعر الوحدة: EGP ${fNumber.format(avgPrice)}',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      color: AppTheme.getTextSecondary(context),
                                    ),
                                  ),
                                  Text(
                                    'المقدر بأمر التعبئة: EGP ${fNumber.format(est)}',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      color: AppTheme.getTextSecondary(context),
                                    ),
                                  ),
                                ],
                              ),
                              if (currentTotal > 0) ...[
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'الانحراف عن المقدر:',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 11,
                                        color: AppTheme.getTextSecondary(context),
                                      ),
                                    ),
                                    Text(
                                      '${varianceAmt >= 0 ? "+" : ""}${fNumber.format(varianceAmt)} (${variancePct >= 0 ? "+" : ""}${variancePct.toStringAsFixed(1)}%)',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isOverrun
                                            ? const Color(0xFFEF4444)
                                            : (isSaving ? const Color(0xFF10B981) : const Color(0xFF3B82F6)),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
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
                    child: const Text('إغلاق', style: TextStyle(fontFamily: 'Cairo')),
                  ),
                  if (canEdit)
                    ElevatedButton.icon(
                      onPressed: () {
                        final prices = controllers.map((c) {
                          return double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0.0;
                        }).toList();

                        final total = prices.fold(0.0, (acc, p) => acc + p);
                        _itemUnitPriceBreakdowns[key] = prices;

                        _getItemActualCtrl(key, item).text = total.toStringAsFixed(2);
                        _getItemUnitPriceCtrl(key, item).text = (total / count).toStringAsFixed(2);

                        _modifiedItemKeys.add(key);
                        setState(() {});
                        Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const Text(
                        'حفظ وتطبيق الإجمالي في الجدول',
                        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Settle Single Cost Item ──
  Future<void> _settleSingleCostItem(SupplierExpectedCostItemModel item) async {
    final key = item.costItemId;
    final ctrl = _getItemActualCtrl(key, item);
    final rawText = ctrl.text.replaceAll(',', '').trim();
    double? actAmt = double.tryParse(rawText);
    if (actAmt == null || actAmt <= 0) {
      actAmt = item.actualAmount;
    }

    if (actAmt == null || actAmt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال قيمة فعلية صحيحة أكبر من الصفر قبل الاعتماد', textDirection: TextDirection.rtl),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    final pId = item.packingOrderId;
    final costItemId = item.costItemId;

    final notesCtrl = _getItemNotesCtrl(key, item);
    final notes = notesCtrl.text.trim().isNotEmpty
        ? notesCtrl.text.trim()
        : (item.detailedNotes ?? item.settlementNotes ?? item.invoiceRef ?? '');

    final qtyStr = _getItemQtyCtrl(key, item).text.replaceAll(',', '').trim();
    final qty = double.tryParse(qtyStr) ?? item.displayQuantity;

    final priceStr = _getItemUnitPriceCtrl(key, item).text.replaceAll(',', '').trim();
    final unitPrice = double.tryParse(priceStr) ??
        item.displayUnitPrice;

    final actualDateTime = _getItemDateTime(key, item);

    setState(() => _settlingItemKeys.add(key));

    try {
      final poDao = PackingOrderDao();
      final itemDesc = notes.isNotEmpty ? ' ($notes)' : '';

      try {
        await poDao.settleCostVariancesBatch(
          packingOrderId: pId,
          settlements: [
            {
              'cost_item_id': costItemId,
              'actual_amount': actAmt,
              'actual_quantity': qty,
              'unit_price': unitPrice,
              'actual_date_time': actualDateTime.toIso8601String(),
              'notes': notes,
              'invoice_ref': item.invoiceRef,
            }
          ],
          generalNotes: 'اعتماد فردي لمورد: ${item.itemName}$itemDesc بأمر #$pId',
        );
      } catch (rpcErr) {
        debugPrint('rpc_settle_packing_cost_variances warning: $rpcErr');
      }

      // Update via SupplierDao RPC if available
      try {
        await _dao.settleCostItem(
          costItemId: costItemId,
          actualAmount: actAmt,
          invoiceRef: item.invoiceRef,
          notes: notes.isNotEmpty ? notes : null,
        );
      } catch (_) {}

      // Direct confirmation update to packing_order_cost_items
      final breakdown = _itemUnitPriceBreakdowns[key];
      final existingSnap = item.currencySnapshot ?? <String, dynamic>{};
      final updatedSnap = {
        ...existingSnap,
        if (breakdown != null && breakdown.isNotEmpty) 'unit_prices': breakdown,
      };

      try {
        await Supabase.instance.client.from('packing_order_cost_items').update({
          'is_locked': true,
          'locked_at': DateTime.now().toIso8601String(),
          'cost_status': 'actual',
          'actual_amount': actAmt,
          'actual_quantity': qty,
          'actual_unit_price': unitPrice,
          'actual_date_time': actualDateTime.toIso8601String(),
          'reconciled_at': DateTime.now().toIso8601String(),
          'currency_snapshot': updatedSnap,
          if (notes.isNotEmpty) 'settlement_notes': notes,
          if (notes.isNotEmpty) 'detailed_notes': notes,
        }).eq('id', costItemId);
      } catch (_) {
        try {
          await Supabase.instance.client.from('packing_order_cost_items').update({
            'cost_status': 'actual',
            'actual_amount': actAmt,
            'reconciled_at': DateTime.now().toIso8601String(),
            'currency_snapshot': updatedSnap,
          }).eq('id', costItemId);
        } catch (_) {}
      }

      // Synchronize detailed notes to ledger_entries and account_ledger_entries
      if (notes.isNotEmpty) {
        try {
          final suppId = item.supplierId ?? _selectedSupplierId;
          final invText = item.invoiceRef != null && item.invoiceRef!.trim().isNotEmpty
              ? ' - مستند: ${item.invoiceRef!.trim()}'
              : '';
          if (suppId != null && suppId.isNotEmpty) {
            await Supabase.instance.client
                .from('ledger_entries')
                .update({
                  'description': 'تسوية تكلفة فعلية بند: ${item.itemName} (أمر #${item.orderNumber}) - $notes$invText',
                })
                .eq('reference_id', pId)
                .eq('entity_id', suppId)
                .inFilter('reference_type', ['cost_settlement', 'packing_cost_settlement'])
                .like('description', '%${item.itemName}%');
          }
          await Supabase.instance.client
              .from('account_ledger_entries')
              .update({
                'description': 'تسوية تكلفة مورد - ${item.itemName} (أمر #${item.orderNumber}) - $notes$invText',
              })
              .like('description', '%${item.itemName}%')
              .like('description', '%$pId%');
        } catch (syncErr) {
          debugPrint('⚠️ Error syncing detailed notes to ledger: $syncErr');
        }
      }

      DataChangeEventBus.instance.notifySuppliersChanged();
      DataChangeEventBus.instance.notifyJournalEntriesChanged();
      DataChangeEventBus.instance.notifyPackingOrdersChanged();

      _modifiedItemKeys.remove(key);
      _unlockedItemKeys.remove(key);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم اعتماد وإقفال تسوية البند بنجاح وتوليد قيد اليومية!', textDirection: TextDirection.rtl),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }

      await _loadData();
    } catch (e, st) {
      debugPrint('❌ Error in _settleSingleCostItem: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر اعتماد تسوية البند: $e', textDirection: TextDirection.rtl), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _settlingItemKeys.remove(key));
    }
  }

  Future<void> _deleteEstimatedCostItem(
      SupplierExpectedCostItemModel item) async {
    if (!SupplierDao.canDeleteExpectedCostItemModel(item)) return;
    final key = item.costItemId;
    if (_deletingItemKeys.contains(key) || _settlingItemKeys.contains(key)) {
      return;
    }

    final confirmed = await showDeleteEstimatedCostItemDialog(
      context,
      itemName: item.itemName,
      orderNumber: item.orderNumber,
      estimatedAmount: item.expectedAmount,
    );
    if (!confirmed || !mounted) return;

    setState(() => _deletingItemKeys.add(key));
    try {
      await _dao.deleteEstimatedCostItem(
        costItemId: item.costItemId,
        packingOrderId: item.packingOrderId,
      );

      if (!mounted) return;
      final actCtrl = _itemActualCtrls.remove(key);
      final qtyCtrl = _itemQtyCtrls.remove(key);
      final priceCtrl = _itemUnitPriceCtrls.remove(key);
      final notesCtrl = _itemNotesCtrls.remove(key);

      setState(() {
        _deletingItemKeys.remove(key);
        _items.removeWhere((e) => e.costItemId == item.costItemId);
        _modifiedItemKeys.remove(key);
        _unlockedItemKeys.remove(key);
        _itemDateTimes.remove(key);
        _itemUnitPriceBreakdowns.remove(key);
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        actCtrl?.dispose();
        qtyCtrl?.dispose();
        priceCtrl?.dispose();
        notesCtrl?.dispose();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم حذف البند التقديري "${item.itemName}" بنجاح',
            textDirection: TextDirection.rtl,
          ),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _deletingItemKeys.remove(key));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تعذر حذف البند: $e',
              textDirection: TextDirection.rtl,
            ),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  // ── Batch Settlements ──
  Future<void> _saveSettlements() async {
    final targetItems = _filteredItems;
    final List<Map<String, dynamic>> itemsToSettle = [];

    for (final item in targetItems) {
      final key = item.costItemId;

      final isLocked = _isItemLocked(item);
      final isUnlocked = _unlockedItemKeys.contains(key);
      if (isLocked && !isUnlocked) {
        continue;
      }

      final ctrl = _getItemActualCtrl(key, item);
      final raw = ctrl.text.replaceAll(',', '').trim();
      double? actAmt = double.tryParse(raw);
      if (actAmt == null || actAmt <= 0) {
        actAmt = item.actualAmount;
      }

      if (actAmt != null && actAmt > 0) {
        final notesCtrl = _getItemNotesCtrl(key, item);
        final notesVal = notesCtrl.text.trim().isNotEmpty
            ? notesCtrl.text.trim()
            : (item.detailedNotes ?? item.settlementNotes ?? item.invoiceRef ?? '');
        final qtyStr = _getItemQtyCtrl(key, item).text.replaceAll(',', '').trim();
        final qty = double.tryParse(qtyStr) ?? item.displayQuantity;
        final priceStr = _getItemUnitPriceCtrl(key, item).text.replaceAll(',', '').trim();
        final unitPrice = double.tryParse(priceStr) ?? (qty > 0 ? actAmt / qty : actAmt);
        final dt = _getItemDateTime(key, item);

        itemsToSettle.add({
          'item': item,
          'cost_item_id': item.costItemId,
          'packing_order_id': item.packingOrderId,
          'expected_amount': item.expectedAmount,
          'resolved_actual': actAmt,
          'resolved_qty': qty,
          'resolved_unit_price': unitPrice,
          'resolved_date_time': dt,
          'resolved_notes': notesVal,
          'invoice_ref': item.invoiceRef,
        });
      }
    }

    if (itemsToSettle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد بنود غير مقفلة بقيمة فعلية مدخلة أكبر من الصفر لاعتمادها.', textDirection: TextDirection.rtl),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    final double sumEst = itemsToSettle.fold(0.0, (s, i) => s + (i['expected_amount'] as double));
    final double sumAct = itemsToSettle.fold(0.0, (s, i) => s + (i['resolved_actual'] as double));
    final double sumVar = sumAct - sumEst;
    final fNumber = NumberFormat('#,##0.00');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.lock_clock_rounded, color: AppTheme.primary),
            SizedBox(width: 8),
            Text('تأكيد اعتماد وإقفال تسوية التكاليف', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('سيتم اعتماد وترحيل وإقفال ${itemsToSettle.length} بند تكلفة للموردين.', style: const TextStyle(fontFamily: 'Cairo', fontSize: 13)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _buildConfirmSummaryRow('إجمالي التقديري:', 'EGP ${fNumber.format(sumEst)}'),
                  const SizedBox(height: 6),
                  _buildConfirmSummaryRow('إجمالي الفعلي الجديد:', 'EGP ${fNumber.format(sumAct)}', bold: true),
                  const Divider(height: 16),
                  _buildConfirmSummaryRow(
                    'صافي الفارق (الانحراف):',
                    '${sumVar >= 0 ? '+' : ''}EGP ${fNumber.format(sumVar)}',
                    color: sumVar > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                    bold: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_rounded, size: 16, color: Color(0xFF10B981)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'تنبيه: سيتم قفل وإقفال هذه البنود بعد الاعتماد لمنع أي تعديل أو تلاعب مستقبلي إلا بصلاحيات الإدارة.',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Color(0xFF0F766E), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo'))),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.lock_rounded, size: 16, color: Colors.white),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            label: const Text('اعتماد وإقفال الآن', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSavingSettlement = true);

    try {
      final poDao = PackingOrderDao();
      final Map<int, List<Map<String, dynamic>>> byOrder = {};
      final Map<dynamic, SupplierExpectedCostItemModel> itemById = {};

      for (final s in itemsToSettle) {
        final poId = s['packing_order_id'] as int;
        final cId = s['cost_item_id'];
        if (s['item'] is SupplierExpectedCostItemModel) {
          itemById[cId] = s['item'] as SupplierExpectedCostItemModel;
        }
        byOrder.putIfAbsent(poId, () => []).add({
          'cost_item_id': cId,
          'actual_amount': s['resolved_actual'],
          'actual_quantity': s['resolved_qty'],
          'unit_price': s['resolved_unit_price'],
          'actual_date_time': (s['resolved_date_time'] as DateTime).toIso8601String(),
          'notes': s['resolved_notes'],
          'invoice_ref': s['invoice_ref'],
        });
      }

      int settledCount = 0;

      for (final entry in byOrder.entries) {
        final pId = entry.key;
        final settlements = entry.value;
        bool batchSucceeded = false;
        try {
          await poDao.settleCostVariancesBatch(
            packingOrderId: pId,
            settlements: settlements,
            generalNotes: 'تسوية مجمعة للموردين لأمر #$pId',
          );
          settledCount += settlements.length;
          batchSucceeded = true;
        } catch (poErr) {
          debugPrint('Error settling packing order #$pId: $poErr');
        }

        for (final s in settlements) {
          final cId = s['cost_item_id'];
          final sNotes = s['notes']?.toString().trim();
          final bDown = _itemUnitPriceBreakdowns[cId];
          final origItem = itemById[cId];
          final existingSnap = origItem?.currencySnapshot ?? <String, dynamic>{};
          final updatedSnap = {
            ...existingSnap,
            if (bDown != null && bDown.isNotEmpty) 'unit_prices': bDown,
          };

          if (cId != null) {
            try {
              await Supabase.instance.client.from('packing_order_cost_items').update({
                'is_locked': true,
                'locked_at': DateTime.now().toIso8601String(),
                'cost_status': 'actual',
                'actual_amount': s['actual_amount'],
                'actual_quantity': s['actual_quantity'],
                'actual_unit_price': s['unit_price'],
                'actual_date_time': s['actual_date_time'],
                'reconciled_at': DateTime.now().toIso8601String(),
                if (updatedSnap.isNotEmpty) 'currency_snapshot': updatedSnap,
                if (sNotes != null && sNotes.isNotEmpty) 'settlement_notes': sNotes,
                if (sNotes != null && sNotes.isNotEmpty) 'detailed_notes': sNotes,
              }).eq('id', cId);
              if (!batchSucceeded) settledCount++;
            } catch (_) {
              try {
                await Supabase.instance.client.from('packing_order_cost_items').update({
                  'cost_status': 'actual',
                  'actual_amount': s['actual_amount'],
                  'reconciled_at': DateTime.now().toIso8601String(),
                  if (updatedSnap.isNotEmpty) 'currency_snapshot': updatedSnap,
                }).eq('id', cId);
                if (!batchSucceeded) settledCount++;
              } catch (_) {}
            }

            // Synchronize detailed notes to ledger_entries and account_ledger_entries
            if (sNotes != null && sNotes.isNotEmpty && origItem != null) {
              try {
                final suppId = origItem.supplierId ?? _selectedSupplierId;
                final invText = origItem.invoiceRef != null && origItem.invoiceRef!.trim().isNotEmpty
                    ? ' - مستند: ${origItem.invoiceRef!.trim()}'
                    : '';
                if (suppId != null && suppId.isNotEmpty) {
                  await Supabase.instance.client
                      .from('ledger_entries')
                      .update({
                        'description': 'تسوية تكلفة فعلية بند: ${origItem.itemName} (أمر #${origItem.orderNumber}) - $sNotes$invText',
                      })
                      .eq('reference_id', pId)
                      .eq('entity_id', suppId)
                      .inFilter('reference_type', ['cost_settlement', 'packing_cost_settlement'])
                      .like('description', '%${origItem.itemName}%');
                }
                await Supabase.instance.client
                    .from('account_ledger_entries')
                    .update({
                      'description': 'تسوية تكلفة مورد - ${origItem.itemName} (أمر #${origItem.orderNumber}) - $sNotes$invText',
                    })
                    .like('description', '%${origItem.itemName}%')
                    .like('description', '%$pId%');
              } catch (syncErr) {
                debugPrint('⚠️ Error syncing batch settlement notes to ledger: $syncErr');
              }
            }
          }
        }
      }

      DataChangeEventBus.instance.notifySuppliersChanged();
      DataChangeEventBus.instance.notifyJournalEntriesChanged();
      DataChangeEventBus.instance.notifyPackingOrdersChanged();

      _modifiedItemKeys.clear();
      _unlockedItemKeys.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم اعتماد وإقفال تسوية $settledCount بند بنجاح وتحديث قيود اليومية!', textDirection: TextDirection.rtl),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }

      await _loadData();
    } catch (e) {
      debugPrint('Error saving settlements: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء اعتماد التسوية: $e', textDirection: TextDirection.rtl), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingSettlement = false);
    }
  }

  Widget _buildConfirmSummaryRow(String label, String value, {bool bold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12.5,
            fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  // ── Print Landscape A4 PDF ──
  Future<void> _printReport() async {
    if (_isPrinting) return;
    final locale = await LanguageDialog.show(context);
    if (locale == null || !mounted) return;

    setState(() => _isPrinting = true);
    try {
      String? resolvedName;
      String? resolvedCode;
      if (_selectedSupplierId != null) {
        for (final s in _suppliers) {
          if (s.id == _selectedSupplierId) {
            resolvedName = s.name;
            resolvedCode = s.supplierCode;
            break;
          }
        }
      }

      final displayed = _filteredItems;

      final actualAmounts = <dynamic, double>{};
      final quantities = <dynamic, double>{};
      final unitPrices = <dynamic, double>{};
      final notes = <dynamic, String>{};
      final lockedMap = <dynamic, bool>{};

      for (final item in displayed) {
        final key = item.costItemId;
        final rawAct = _itemActualCtrls[key]?.text.replaceAll(',', '').trim() ?? '';
        final parsedAct = double.tryParse(rawAct);
        if (parsedAct != null && parsedAct > 0) {
          actualAmounts[key] = parsedAct;
        } else if (item.actualAmount != null && item.actualAmount! > 0) {
          actualAmounts[key] = item.actualAmount!;
        }

        final rawQty = _itemQtyCtrls[key]?.text.replaceAll(',', '').trim() ?? '';
        quantities[key] = double.tryParse(rawQty) ?? item.displayQuantity;

        final rawPrice = _itemUnitPriceCtrls[key]?.text.replaceAll(',', '').trim() ?? '';
        unitPrices[key] = double.tryParse(rawPrice) ?? item.displayUnitPrice;

        notes[key] = _itemNotesCtrls[key]?.text.trim() ?? (item.detailedNotes ?? item.settlementNotes ?? '');
        lockedMap[key] = _isItemLocked(item) && !_unlockedItemKeys.contains(key);
      }

      await CostSettlementPdfService.printPdf(
        items: displayed,
        supplierType: widget.supplierType,
        supplierName: resolvedName,
        supplierCode: resolvedCode,
        fromDate: _fromDate,
        toDate: _toDate,
        fromOrderId: _fromOrderId,
        toOrderId: _toOrderId,
        actualAmounts: actualAmounts,
        quantities: quantities,
        unitPrices: unitPrices,
        notes: notes,
        dateTimes: _itemDateTimes,
        unitPriceBreakdowns: _itemUnitPriceBreakdowns,
        lockedMap: lockedMap,
        locale: locale,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في طباعة التقرير: $e',
                style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final displayedItems = _filteredItems;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenW = MediaQuery.of(context).size.width;
          final effectiveW = constraints.maxWidth.isFinite ? math.min(constraints.maxWidth, screenW) : screenW;
          final isMobile = effectiveW < 850;

          if (isMobile) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── 1. Top Header Auto-Distribution Bar & Master Controls ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: _buildSettlementTopDistributionBar(isDark, isMobile: true),
                  ),

                  // ── 2. Summary KPI Ribbon (Live Real-Time Calculation) ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: _buildSettlementKpiRibbon(displayedItems, isDark),
                  ),

                  // ── 3. Table of Orders & Items ──
                  _loading
                      ? const Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(
                            child: CircularProgressIndicator(color: AppTheme.primary),
                          ),
                        )
                      : displayedItems.isEmpty
                          ? _buildEmptyState(isDark)
                          : Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                              child: SizedBox(
                                height: 520,
                                child: _buildMultiOrderSettlementTable(displayedItems, isDark),
                              ),
                            ),
                ],
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 1. Top Header Auto-Distribution Bar & Master Controls ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: _buildSettlementTopDistributionBar(isDark, isMobile: false),
              ),

              // ── 2. Summary KPI Ribbon (Live Real-Time Calculation) ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: _buildSettlementKpiRibbon(displayedItems, isDark),
              ),

              // ── 3. Table of Orders & Items ──
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppTheme.primary),
                      )
                    : displayedItems.isEmpty
                        ? _buildEmptyState(isDark)
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            child: _buildMultiOrderSettlementTable(displayedItems, isDark),
                          ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Master Invoice Bar with Prominent Supplier Dropdown & Date Filters ──
  Widget _buildSettlementTopDistributionBar(bool isDark, {bool isMobile = false}) {
    final dateDisplay = DateFormat('yyyy-MM-dd HH:mm').format(_overallInvoiceDateTime);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.getCardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.getBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Row 1: Title + Prominent Supplier Dropdown + Unlock Button ──
          LayoutBuilder(
            builder: (ctx, headerConstraints) {
              final screenW = MediaQuery.of(context).size.width;
              final effectiveHeaderW = headerConstraints.maxWidth.isFinite ? math.min(headerConstraints.maxWidth, screenW) : screenW;
              final isNarrowHeader = isMobile || effectiveHeaderW < 750;

              if (isNarrowHeader) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            widget.supplierType == 'station' ? Icons.factory_rounded : Icons.discount_rounded,
                            color: AppTheme.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.supplierType == 'station'
                                ? 'تسوية تكاليف المحطات'
                                : 'تسوية تكاليف التخصيمات',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.getTextPrimary(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        OutlinedButton.icon(
                          onPressed: _showUnlockPasswordDialog,
                          icon: const Icon(Icons.lock_open_rounded, size: 13, color: Color(0xFF0EA5E9)),
                          label: const Text('تعديل المقفل',
                              style: TextStyle(fontFamily: 'Cairo', fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF0EA5E9))),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF0EA5E9)),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          icon: Icon(
                            _isControlsExpanded ? Icons.keyboard_arrow_up_rounded : Icons.tune_rounded,
                            size: 20,
                            color: AppTheme.primary,
                          ),
                          tooltip: _isControlsExpanded ? 'إخفاء أدوات التوزيع' : 'إظهار أدوات التوزيع والفلاتر',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: () => setState(() => _isControlsExpanded = !_isControlsExpanded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildProminentSupplierDropdown(isDark, isFullWidth: true),
                  ],
                );
              }

              return Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      widget.supplierType == 'station' ? Icons.factory_rounded : Icons.discount_rounded,
                      color: AppTheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.supplierType == 'station'
                              ? 'تسوية التكاليف الفعلية لموردي المحطات والتبريد'
                              : 'تسوية التكاليف الفعلية لموردي التخصيمات والفحص',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.getTextPrimary(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _selectedSupplierId != null
                              ? 'تم حصر وعرض بنود المورد المختار فقط في الجدول والإحصائيات'
                              : 'عرض شامل لكافة البنود لجميع الموردين المسجلين',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 10.5,
                            color: _selectedSupplierId != null ? AppTheme.primary : AppTheme.getTextSecondary(context),
                            fontWeight: _selectedSupplierId != null ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Prominent Supplier Selector Dropdown
                  _buildProminentSupplierDropdown(isDark),

                  const SizedBox(width: 8),

                  // Unlock button
                  OutlinedButton.icon(
                    onPressed: _showUnlockPasswordDialog,
                    icon: const Icon(Icons.lock_open_rounded, size: 14, color: Color(0xFF0EA5E9)),
                    label: const Text('إتاحة تعديل المقفل 🔒', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0EA5E9))),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF0EA5E9)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              );
            },
          ),
          if (_isControlsExpanded) ...[
            const SizedBox(height: 12),

          // ── Row 2: Master Invoice Inputs ──
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // 1. Total Amount Input
              SizedBox(
                width: 150,
                height: 38,
                child: TextFormField(
                  controller: _overallActualCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.getTextPrimary(context),
                  ),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    labelText: 'إجمالي المبلغ',
                    labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 10.5),
                    prefixText: 'EGP ',
                    prefixStyle: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10,
                      color: isDark ? Colors.white54 : const Color(0xFF64748B),
                    ),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppTheme.getBorderColor(context)),
                    ),
                  ),
                  onChanged: (val) {
                    final tot = double.tryParse(val.replaceAll(',', '').trim()) ?? 0.0;
                    final q = double.tryParse(_overallQtyCtrl.text.replaceAll(',', '').trim()) ?? 1.0;
                    if (q > 0 && tot > 0) {
                      _overallUnitPriceCtrl.text = (tot / q).toStringAsFixed(2);
                    }
                  },
                ),
              ),

              // 2. Total Quantity Input
              SizedBox(
                width: 105,
                height: 38,
                child: TextFormField(
                  controller: _overallQtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.getTextPrimary(context),
                  ),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    labelText: 'الكمية الإجمالية',
                    labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 10.5),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppTheme.getBorderColor(context)),
                    ),
                  ),
                  onChanged: (val) {
                    final q = double.tryParse(val.replaceAll(',', '').trim()) ?? 1.0;
                    final up = double.tryParse(_overallUnitPriceCtrl.text.replaceAll(',', '').trim()) ?? 0.0;
                    if (q > 0 && up > 0) {
                      _overallActualCtrl.text = (q * up).toStringAsFixed(2);
                    } else {
                      final tot = double.tryParse(_overallActualCtrl.text.replaceAll(',', '').trim()) ?? 0.0;
                      if (q > 0 && tot > 0) {
                        _overallUnitPriceCtrl.text = (tot / q).toStringAsFixed(2);
                      }
                    }
                  },
                ),
              ),

              // 3. Unit Price Input
              SizedBox(
                width: 110,
                height: 38,
                child: TextFormField(
                  controller: _overallUnitPriceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.getTextPrimary(context),
                  ),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    labelText: 'سعر الوحدة',
                    labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 10.5),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppTheme.getBorderColor(context)),
                    ),
                  ),
                  onChanged: (val) {
                    final up = double.tryParse(val.replaceAll(',', '').trim()) ?? 0.0;
                    final q = double.tryParse(_overallQtyCtrl.text.replaceAll(',', '').trim()) ?? 1.0;
                    if (q > 0 && up > 0) {
                      _overallActualCtrl.text = (q * up).toStringAsFixed(2);
                    }
                  },
                ),
              ),

              // 4. Date & Time Picker Button
              InkWell(
                onTap: () async {
                  final dt = await _pickDateTimeDialog(context, _overallInvoiceDateTime);
                  if (dt != null) {
                    setState(() => _overallInvoiceDateTime = dt);
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.getBorderColor(context)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_month_rounded, size: 16, color: AppTheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        dateDisplay,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.getTextPrimary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 5. Statement / Notes Input
              SizedBox(
                width: 190,
                height: 38,
                child: TextFormField(
                  controller: _overallNotesCtrl,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11.5,
                    color: AppTheme.getTextPrimary(context),
                  ),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    labelText: 'البيان التفصيلي للفاتورة',
                    labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 10.5),
                    hintText: 'مثال: فاتورة تعبئة محطة...',
                    hintStyle: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10,
                      color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                    ),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppTheme.getBorderColor(context)),
                    ),
                  ),
                ),
              ),

              // 6. Distribution Method Dropdown
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.getBorderColor(context)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _distributionMethod,
                    icon: const Icon(Icons.arrow_drop_down, size: 20),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.getTextPrimary(context),
                    ),
                    dropdownColor: AppTheme.getCardBg(context),
                    items: const [
                      DropdownMenuItem(
                        value: 'proportional',
                        child: Text('حسب النسبة والتناسب مع التقديري'),
                      ),
                      DropdownMenuItem(
                        value: 'equal',
                        child: Text('بالتساوي على جميع الأوامر'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _distributionMethod = val);
                    },
                  ),
                ),
              ),

              // 7. Auto Distribute Button
              ElevatedButton.icon(
                onPressed: _autoDistributeToAll,
                icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                label: const Text('توزيع تلقائي للكل', style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),

              // 8. Reset Button
              IconButton(
                onPressed: _resetSettlementToEstimated,
                icon: const Icon(Icons.restart_alt_rounded, size: 20),
                tooltip: 'استعادة التقديري الأصلي',
                color: AppTheme.getTextSecondary(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Row 3: Date Filters, Presets, Search & Action Buttons ──
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Status filter chips
                  FilterChip(
                    avatar: const Icon(Icons.all_inbox_rounded, size: 14),
                    label: const Text(
                      'كافة أوامر التعبئة',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    selected: !_filterOnlyPending,
                    onSelected: (val) {
                      setState(() => _filterOnlyPending = !val);
                    },
                    selectedColor: AppTheme.primary.withValues(alpha: 0.18),
                    checkmarkColor: AppTheme.primary,
                  ),
                  FilterChip(
                    avatar: const Icon(Icons.pending_actions_rounded, size: 14),
                    label: const Text(
                      'غير المسواة فقط',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 11),
                    ),
                    selected: _filterOnlyPending,
                    onSelected: (val) {
                      setState(() => _filterOnlyPending = val);
                    },
                    selectedColor: AppTheme.warning.withValues(alpha: 0.18),
                    checkmarkColor: AppTheme.warning,
                  ),

                  // Quick Date Presets
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.getBorderColor(context)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildDatePresetChip('الكل', _fromDate == null && _toDate == null, () => _setDatePreset('all')),
                        _buildDatePresetChip('اليوم', _isPresetToday(), () => _setDatePreset('today')),
                        _buildDatePresetChip('آخر 7 أيام', _fromDate != null && !_isPresetToday() && !_isPresetMonth(), () => _setDatePreset('week')),
                        _buildDatePresetChip('هذا الشهر', _isPresetMonth(), () => _setDatePreset('month')),
                      ],
                    ),
                  ),

                  // Precise Date Range Pickers (من / إلى)
                  SizedBox(
                    width: 235,
                    height: 36,
                    child: _buildDateFilterRow(isDark),
                  ),
                  OrderRangeFilterBar(
                    fromController: _fromOrderCtrl,
                    toController: _toOrderCtrl,
                    isDark: isDark,
                    onChanged: () {
                      setState(() {});
                      if (_loadedWithOrderRange &&
                          _fromOrderId == null &&
                          _toOrderId == null) {
                        _loadData();
                      }
                    },
                    onApplyQuery: _loadData,
                    onClear: () {
                      setState(() {});
                      if (_loadedWithOrderRange) {
                        _loadData();
                      }
                    },
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 180,
                    height: 36,
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11.5,
                        color: AppTheme.getTextPrimary(context),
                      ),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        hintText: 'بحث بالأمر أو البند أو المورد...',
                        hintStyle: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10.5,
                          color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                        ),
                        prefixIcon: const Icon(Icons.search, size: 16),
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 14),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: AppTheme.getBorderColor(context)),
                        ),
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isSavingSettlement ? null : _saveSettlements,
                    icon: _isSavingSettlement
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.verified_rounded, size: 16),
                    label: Text(
                      _modifiedItemKeys.isNotEmpty
                          ? 'اعتماد وحفظ التسوية (${_modifiedItemKeys.length})'
                          : 'اعتماد وحفظ التسوية',
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 2,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: (_isPrinting || _loading) ? null : _printReport,
                    icon: _isPrinting
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.picture_as_pdf_rounded, size: 16),
                    label: Text(
                      _isPrinting ? 'جاري التجهيز...' : 'طباعة تسوية التكاليف (PDF)',
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

  Widget _buildDatePresetChip(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : AppTheme.getTextSecondary(context),
          ),
        ),
      ),
    );
  }

  // ── Prominent Supplier Selection Dropdown in Header ──
  Widget _buildProminentSupplierDropdown(bool isDark, {bool isFullWidth = false}) {
    final seenIds = <String>{};
    final uniqueSuppliers = <SupplierModel>[];
    for (final s in _suppliers) {
      final id = s.id;
      if (id != null && id.trim().isNotEmpty && seenIds.add(id)) {
        uniqueSuppliers.add(s);
      }
    }

    final hasSelected = _selectedSupplierId != null &&
        uniqueSuppliers.any((s) => s.id == _selectedSupplierId);

    final items = <DropdownMenuItem<String?>>[
      DropdownMenuItem<String?>(
        value: null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.all_inclusive_rounded, size: 15, color: AppTheme.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                widget.supplierType == 'station' ? 'جميع موردي المحطات والتبريد' : 'جميع موردي التخصيمات والفحص',
                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 11.5),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      ...uniqueSuppliers.map((s) {
        return DropdownMenuItem<String?>(
          value: s.id,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_pin_rounded, size: 15, color: Color(0xFF0D9488)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '${s.name} (${s.supplierCode})',
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 11.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }),
    ];

    if (_selectedSupplierId != null && !hasSelected) {
      String displayName = 'مورد محدد';
      for (final item in _items) {
        if (item.supplierId == _selectedSupplierId) {
          final name = item.supplierName ?? 'مورد';
          final code = item.supplierCode != null && item.supplierCode!.isNotEmpty ? ' (${item.supplierCode})' : '';
          displayName = '$name$code';
          break;
        }
      }
      items.add(
        DropdownMenuItem<String?>(
          value: _selectedSupplierId,
          child: Text(displayName, overflow: TextOverflow.ellipsis),
        ),
      );
    }

    return Container(
      constraints: isFullWidth ? null : const BoxConstraints(maxWidth: 270),
      width: isFullWidth ? double.infinity : null,
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _selectedSupplierId != null
            ? AppTheme.primary.withValues(alpha: 0.12)
            : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _selectedSupplierId != null ? AppTheme.primary : AppTheme.getBorderColor(context),
          width: _selectedSupplierId != null ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.storefront_rounded,
            size: 16,
            color: _selectedSupplierId != null ? AppTheme.primary : (isDark ? Colors.white60 : const Color(0xFF64748B)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _selectedSupplierId,
                isExpanded: true,
                dropdownColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontFamily: 'Cairo',
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                ),
                items: items,
                onChanged: (val) {
                  setState(() => _selectedSupplierId = val);
                },
              ),
            ),
          ),
          if (_selectedSupplierId != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => setState(() => _selectedSupplierId = null),
              child: Tooltip(
                message: 'إلغاء التصفية وعرض كافة الموردين',
                child: Icon(Icons.close_rounded, size: 16, color: isDark ? Colors.white70 : const Color(0xFF475569)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Date Range Filter Row ──
  Widget _buildDateFilterRow(bool isDark) {
    return Row(
      children: [
        // From Date
        Expanded(
          child: InkWell(
            onTap: _pickFromDate,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _fromDate != null
                      ? AppTheme.primary
                      : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded,
                      size: 12,
                      color: _fromDate != null ? AppTheme.primary : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8))),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _fromDate != null
                          ? 'من: ${AppUtils.formatDate(_fromDate!)}'
                          : 'من تاريخ',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        fontWeight: _fromDate != null ? FontWeight.bold : FontWeight.normal,
                        color: _fromDate != null
                            ? (isDark ? Colors.white : const Color(0xFF0F172A))
                            : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_fromDate != null)
                    GestureDetector(
                      onTap: () => setState(() => _fromDate = null),
                      child: Icon(Icons.close_rounded, size: 12,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        // To Date
        Expanded(
          child: InkWell(
            onTap: _pickToDate,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _toDate != null
                      ? AppTheme.primary
                      : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded,
                      size: 12,
                      color: _toDate != null ? AppTheme.primary : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8))),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _toDate != null
                          ? 'إلى: ${AppUtils.formatDate(_toDate!)}'
                          : 'إلى تاريخ',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        fontWeight: _toDate != null ? FontWeight.bold : FontWeight.normal,
                        color: _toDate != null
                            ? (isDark ? Colors.white : const Color(0xFF0F172A))
                            : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_toDate != null)
                    GestureDetector(
                      onTap: () => setState(() => _toDate = null),
                      child: Icon(Icons.close_rounded, size: 12,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Summary KPI Ribbon (Recalculated Live based on Filtered Items) ──
  Widget _buildSettlementKpiRibbon(List<SupplierExpectedCostItemModel> items, bool isDark) {
    final distinctOrders = items.map((i) => i.packingOrderId).toSet().length;
    double totalEst = 0.0;
    double totalAct = 0.0;
    int lockedCount = 0;
    int pendingCount = 0;

    for (final item in items) {
      final key = item.costItemId;
      final e = item.expectedAmount;
      final isLocked = _isItemLocked(item);
      final ctrl = _itemActualCtrls[key];
      double? a;
      if (ctrl != null && ctrl.text.trim().isNotEmpty) {
        a = double.tryParse(ctrl.text.replaceAll(',', '').trim());
      } else if (isLocked || item.actualAmount != null) {
        a = item.actualAmount;
      }
      totalEst += e;
      if (a != null && a > 0) {
        totalAct += a;
      }
      if (isLocked) {
        lockedCount++;
      } else {
        pendingCount++;
      }
    }

    final varAmt = totalAct - totalEst;
    final varPct = totalEst > 0 ? (varAmt / totalEst) * 100 : 0.0;
    final isOverrun = totalAct > totalEst && totalEst > 0;
    final isSaving = totalAct < totalEst && totalEst > 0;
    final varianceColor = isOverrun
        ? const Color(0xFFEF4444)
        : (isSaving ? const Color(0xFF10B981) : const Color(0xFF3B82F6));
    final fNumber = NumberFormat('#,##0.00');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.6) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.getBorderColor(context)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'الأوامر المشمولة: $distinctOrders أمر',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${items.length} بند',
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.bold),
                ),
              ),
              if (lockedCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_rounded, size: 11, color: Color(0xFF10B981)),
                      const SizedBox(width: 3),
                      Text(
                        '$lockedCount مقفل ومعتمد',
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
              if (_unlockedItemKeys.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0EA5E9).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF0EA5E9).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_open_rounded, size: 11, color: Color(0xFF0EA5E9)),
                      const SizedBox(width: 3),
                      Text(
                        '${_unlockedItemKeys.length} مفتوح بكلمة المرور',
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Color(0xFF0EA5E9), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: (pendingCount > 0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981)).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: (pendingCount > 0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981)).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      pendingCount > 0 ? Icons.pending_actions_rounded : Icons.check_circle_outline_rounded,
                      size: 11,
                      color: pendingCount > 0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      pendingCount > 0 ? '$pendingCount معلق' : 'تم تسوية الكل',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        color: pendingCount > 0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 16,
            children: [
              Text(
                'المقدر: EGP ${fNumber.format(totalEst)}',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, color: isDark ? Colors.white60 : const Color(0xFF64748B)),
              ),
              Text(
                'الفعلي: EGP ${fNumber.format(totalAct)}',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.primary),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'الانحراف: ${varAmt >= 0 ? '+' : ''}${fNumber.format(varAmt)}',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, fontWeight: FontWeight.bold, color: varianceColor),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '(${varPct >= 0 ? '+' : ''}${varPct.toStringAsFixed(1)}%)',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 10.5, fontWeight: FontWeight.bold, color: varianceColor),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Multi-Order Interactive Settlement DataTable ──
  Widget _buildMultiOrderSettlementTable(List<SupplierExpectedCostItemModel> items, bool isDark) {
    final fNumber = NumberFormat('#,##0.00');

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.getCardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.getBorderColor(context)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStatePropertyAll(
                isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              ),
              columnSpacing: 18,
              dataRowMinHeight: 48,
              dataRowMaxHeight: 64,
              columns: [
                DataColumn(
                  label: Text('أمر التعبئة / الشحنة', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context))),
                ),
                DataColumn(
                  label: Text('المورد / بند التكلفة', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context))),
                ),
                DataColumn(
                  label: Text('التكلفة التقديرية', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context))),
                  numeric: true,
                ),
                const DataColumn(
                  label: Text('الكمية الفعلية', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                  numeric: true,
                ),
                const DataColumn(
                  label: Text('سعر الوحدة', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                  numeric: true,
                ),
                const DataColumn(
                  label: Text('القيمة الفعلية (الإجمالي)', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                  numeric: true,
                ),
                DataColumn(
                  label: Text('تاريخ ووقت الفاتورة', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context))),
                ),
                DataColumn(
                  label: Text('الفارق الحسابي (%)', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context))),
                  numeric: true,
                ),
                DataColumn(
                  label: Text('البيان والملاحظات التفصيلية', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context))),
                ),
                DataColumn(
                  label: Text('مؤشر الحالة', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context))),
                ),
                DataColumn(
                  label: Text('إجراء / الاعتماد', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context))),
                ),
              ],
              rows: items.map((item) {
                final key = item.costItemId;
                final poNum = item.orderNumber;
                final itemName = item.itemName;
                final category = item.reportCategoryName.isNotEmpty ? item.reportCategoryName : item.category;
                final supplierLabel = item.supplierName != null && item.supplierName!.isNotEmpty
                    ? '${item.supplierName}${item.supplierCode != null ? " (${item.supplierCode})" : ""}'
                    : null;

                final est = item.expectedAmount;

                final actualCtrl = _getItemActualCtrl(key, item);
                final qtyCtrl = _getItemQtyCtrl(key, item);
                final unitPriceCtrl = _getItemUnitPriceCtrl(key, item);
                final notesCtrl = _getItemNotesCtrl(key, item);
                final itemDateTime = _getItemDateTime(key, item);

                final rawActText = actualCtrl.text.replaceAll(',', '').trim();
                final double? parsedAct = double.tryParse(rawActText);
                final double? dbAct = item.actualAmount;
                final double? effectiveAct = parsedAct ?? dbAct;
                final bool hasActual = effectiveAct != null && (effectiveAct > 0 || rawActText.isNotEmpty);

                final double actVal = effectiveAct ?? 0.0;
                final double varianceAmt = hasActual ? (actVal - est) : 0.0;
                final double variancePct = (hasActual && est > 0) ? (varianceAmt / est) * 100 : 0.0;
                final bool isSaving = hasActual && varianceAmt < 0;
                final bool isOverrun = hasActual && varianceAmt > 0;
                final bool isMatch = hasActual && varianceAmt == 0;
                final Color varianceColor = !hasActual
                    ? (isDark ? Colors.white38 : const Color(0xFF94A3B8))
                    : (isOverrun
                        ? const Color(0xFFEF4444)
                        : (isSaving ? const Color(0xFF10B981) : (isDark ? Colors.white60 : const Color(0xFF64748B))));

                final isLocked = _isItemLocked(item);
                final isUnlockedByPassword = _unlockedItemKeys.contains(key);
                final canEdit = (!isLocked) || isUnlockedByPassword;
                final isModified = _modifiedItemKeys.contains(key);
                final canDelete =
                    SupplierDao.canDeleteExpectedCostItemModel(item);
                final isDeleting = _deletingItemKeys.contains(key);

                return DataRow(
                  cells: [
                    // 1. Order Number & Linked Shipments
                    DataCell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              'أمر #$poNum',
                              style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary),
                            ),
                          ),
                          if (item.linkedShipments.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'شحنة: ${item.linkedShipments.map((s) => "#${s['shipment_no'] ?? s['shipment_id']}").join(", ")}',
                              style: TextStyle(fontFamily: 'Cairo', fontSize: 9.5, color: isDark ? Colors.white54 : const Color(0xFF64748B)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),

                    // 2. Cost item name, category & Supplier
                    DataCell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            itemName,
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context)),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (supplierLabel != null)
                                Flexible(
                                  child: Text(
                                    supplierLabel,
                                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Color(0xFF0D9488), fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              if (supplierLabel != null && category.isNotEmpty)
                                const Text(' • ', style: TextStyle(fontSize: 10, color: Colors.grey)),
                              if (category.isNotEmpty)
                                Flexible(
                                  child: Text(
                                    category,
                                    style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: AppTheme.getTextSecondary(context)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // 3. Estimated Cost
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          'EGP ${fNumber.format(est)}',
                          style: const TextStyle(fontFamily: 'Cairo', fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.primary),
                        ),
                      ),
                    ),

                    // 4. Actual Quantity
                    DataCell(
                      SizedBox(
                        width: 75,
                        height: 38,
                        child: TextFormField(
                          controller: qtyCtrl,
                          enabled: canEdit,
                          readOnly: !canEdit,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: canEdit ? AppTheme.getTextPrimary(context) : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                          ),
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                            filled: true,
                            fillColor: !canEdit
                                ? (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9))
                                : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(color: !canEdit ? (isDark ? Colors.white12 : const Color(0xFFE2E8F0)) : AppTheme.getBorderColor(context)),
                            ),
                          ),
                          onChanged: (_) => _onRowQtyOrPriceChanged(key, item),
                          onFieldSubmitted: (val) {
                            final q = double.tryParse(val.replaceAll(',', '').trim()) ?? 1.0;
                            final n = q.toInt();
                            if (q > 1 && n > 1 && (q - n).abs() < 0.001) {
                              _showUnitPriceBreakdownDialog(key, item, n);
                            }
                          },
                        ),
                      ),
                    ),

                    // 5. Unit Price (Interactive dynamic breakdown when qty > 1, regular input when qty <= 1)
                    DataCell(
                      Builder(builder: (context) {
                        final qtyStr = qtyCtrl.text.replaceAll(',', '').trim();
                        final currentQty = double.tryParse(qtyStr) ?? 1.0;
                        final intQty = currentQty.toInt();
                        final isMultiUnit = currentQty > 1 && intQty > 1 && (currentQty - intQty).abs() < 0.001;

                        if (isMultiUnit) {
                          final breakdown = _itemUnitPriceBreakdowns[key];
                          final hasBreakdown = breakdown != null && breakdown.length == intQty && breakdown.any((p) => p > 0);
                          final totalBreakdown = hasBreakdown ? breakdown.fold(0.0, (a, b) => a + b) : 0.0;
                          final avgPrice = hasBreakdown && intQty > 0
                              ? (totalBreakdown / intQty)
                              : (double.tryParse(unitPriceCtrl.text.replaceAll(',', '').trim()) ?? 0.0);
                          final breakdownFormula = hasBreakdown
                              ? breakdown.map((p) => fNumber.format(p)).join(' + ')
                              : '';

                          return Tooltip(
                            message: hasBreakdown
                                ? 'تفاصيل أسعار $intQty وحدات:\n$breakdownFormula = EGP ${fNumber.format(totalBreakdown)}\n(انقر لتعديل أسعار الوحدات)'
                                : 'الكمية = $intQty: انقر لفتح وتحديد سعر كل وحدة على حدة',
                            child: InkWell(
                              onTap: () => _showUnitPriceBreakdownDialog(key, item, intQty),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                width: 110,
                                height: 38,
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: hasBreakdown
                                      ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9))
                                      : (isDark ? const Color(0xFF0F233B) : const Color(0xFFEFF6FF)),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: hasBreakdown
                                        ? (isDark ? Colors.white24 : const Color(0xFFCBD5E1))
                                        : AppTheme.primary,
                                    width: hasBreakdown ? 1 : 1.3,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Icon(
                                      hasBreakdown ? Icons.checklist_rounded : Icons.edit_note_rounded,
                                      size: 15,
                                      color: hasBreakdown ? const Color(0xFF10B981) : AppTheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            hasBreakdown
                                                ? fNumber.format(avgPrice)
                                                : 'تحديد ($intQty) أسعار',
                                            style: TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: hasBreakdown ? 11 : 10,
                                              fontWeight: FontWeight.bold,
                                              color: hasBreakdown
                                                  ? (canEdit ? AppTheme.getTextPrimary(context) : (isDark ? Colors.white54 : const Color(0xFF94A3B8)))
                                                  : AppTheme.primary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            hasBreakdown ? '$intQty أسعار مفصلة' : 'انقر للإدخال',
                                            style: TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.normal,
                                              color: hasBreakdown
                                                  ? const Color(0xFF10B981)
                                                  : AppTheme.primary,
                                            ),
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

                        return SizedBox(
                          width: 85,
                          height: 38,
                          child: TextFormField(
                            controller: unitPriceCtrl,
                            enabled: canEdit,
                            readOnly: !canEdit,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: canEdit ? AppTheme.getTextPrimary(context) : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                            ),
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                              filled: true,
                              fillColor: !canEdit
                                  ? (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9))
                                  : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(
                                  color: !canEdit
                                      ? (isDark ? Colors.white12 : const Color(0xFFE2E8F0))
                                      : AppTheme.getBorderColor(context),
                                ),
                              ),
                            ),
                            onChanged: (_) => _onRowQtyOrPriceChanged(key, item),
                          ),
                        );
                      }),
                    ),

                    // 6. Actual Value (Total Amount with Lock indicator & Tap-to-unlock)
                    DataCell(
                      Tooltip(
                        message: canEdit
                            ? (isUnlockedByPassword
                                ? 'تم فك القفل بكلمة المرور - متاح للتعديل'
                                : 'أدخل القيمة الفعلية لتسوية البند')
                            : 'البند معتمد ومقفل 🔒 (اضغط لفك القفل بكلمة المرور)',
                        child: InkWell(
                          onTap: !canEdit ? () => _showUnlockPasswordDialog() : null,
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 125,
                            height: 38,
                            child: TextFormField(
                              controller: actualCtrl,
                              enabled: canEdit,
                              readOnly: !canEdit,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: canEdit
                                    ? AppTheme.getTextPrimary(context)
                                    : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                              ),
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                prefixIcon: !canEdit
                                    ? Icon(
                                        Icons.lock_rounded,
                                        size: 14,
                                        color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                                      )
                                    : (isUnlockedByPassword
                                        ? const Icon(Icons.lock_open_rounded, size: 14, color: Color(0xFF0EA5E9))
                                        : null),
                                prefixText: canEdit && !isUnlockedByPassword ? 'EGP ' : null,
                                prefixStyle: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: isDark ? Colors.white54 : const Color(0xFF64748B)),
                                filled: true,
                                fillColor: !canEdit
                                    ? (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9))
                                    : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(
                                    color: !canEdit
                                        ? (isDark ? Colors.white12 : const Color(0xFFE2E8F0))
                                        : (isModified ? AppTheme.primary : AppTheme.getBorderColor(context)),
                                  ),
                                ),
                                disabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                                ),
                              ),
                              onChanged: (_) => _onRowActualChanged(key, item),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // 7. Invoice Date & Time
                    DataCell(
                      InkWell(
                        onTap: canEdit
                            ? () async {
                                final picked = await _pickDateTimeDialog(context, itemDateTime);
                                if (picked != null) {
                                  setState(() {
                                    _itemDateTimes[key] = picked;
                                    _modifiedItemKeys.add(key);
                                  });
                                }
                              }
                            : () => _showUnlockPasswordDialog(),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: !canEdit
                                ? (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9))
                                : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: !canEdit ? (isDark ? Colors.white12 : const Color(0xFFE2E8F0)) : AppTheme.getBorderColor(context)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.calendar_today_rounded, size: 13, color: canEdit ? AppTheme.primary : (isDark ? Colors.white38 : const Color(0xFF94A3B8))),
                              const SizedBox(width: 5),
                              Text(
                                DateFormat('yyyy-MM-dd HH:mm').format(itemDateTime),
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: canEdit ? AppTheme.getTextPrimary(context) : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // 8. Variance Indicator (%)
                    DataCell(
                      !hasActual
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'بانتظار الفاتورة',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                                ),
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${varianceAmt >= 0 ? '+' : ''}${fNumber.format(varianceAmt)}',
                                  style: TextStyle(fontFamily: 'Cairo', fontSize: 11.5, fontWeight: FontWeight.bold, color: varianceColor),
                                ),
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: varianceColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${variancePct >= 0 ? '+' : ''}${variancePct.toStringAsFixed(1)}%',
                                    style: TextStyle(fontFamily: 'Cairo', fontSize: 10, fontWeight: FontWeight.bold, color: varianceColor),
                                  ),
                                ),
                              ],
                            ),
                    ),

                    // 9. Notes / Details / Statement (Read-only if locked)
                    DataCell(
                      Tooltip(
                        message: canEdit ? 'ملاحظات وبيان الفاتورة التفصيلي' : 'البند معتمد ومقفل 🔒 (اضغط لفك القفل بكلمة المرور)',
                        child: InkWell(
                          onTap: !canEdit ? () => _showUnlockPasswordDialog() : null,
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 170,
                            height: 38,
                            child: TextFormField(
                              controller: notesCtrl,
                              enabled: canEdit,
                              readOnly: !canEdit,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11.5,
                                color: canEdit
                                    ? AppTheme.getTextPrimary(context)
                                    : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                              ),
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                hintText: !canEdit ? 'معتمد ومقفل 🔒' : 'بيان الفاتورة أو الملاحظات...',
                                hintStyle: TextStyle(fontFamily: 'Cairo', fontSize: 10.5, color: isDark ? Colors.white38 : const Color(0xFF94A3B8)),
                                filled: true,
                                fillColor: !canEdit
                                    ? (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9))
                                    : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(
                                    color: !canEdit
                                        ? (isDark ? Colors.white12 : const Color(0xFFE2E8F0))
                                        : AppTheme.getBorderColor(context),
                                  ),
                                ),
                                disabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: BorderSide(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                                ),
                              ),
                              onChanged: (_) {
                                setState(() => _modifiedItemKeys.add(key));
                              },
                            ),
                          ),
                        ),
                      ),
                    ),

                    // 10. Status Badge
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isModified
                              ? const Color(0xFF3B82F6).withValues(alpha: 0.15)
                              : (isUnlockedByPassword
                                  ? const Color(0xFF0EA5E9).withValues(alpha: 0.15)
                                  : (isLocked
                                      ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                      : const Color(0xFFF59E0B).withValues(alpha: 0.15))),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isModified
                                ? const Color(0xFF3B82F6).withValues(alpha: 0.4)
                                : (isUnlockedByPassword
                                    ? const Color(0xFF0EA5E9).withValues(alpha: 0.4)
                                    : (isLocked
                                        ? const Color(0xFF10B981).withValues(alpha: 0.4)
                                        : const Color(0xFFF59E0B).withValues(alpha: 0.4))),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isModified
                                  ? Icons.edit_note_rounded
                                  : (isUnlockedByPassword
                                      ? Icons.lock_open_rounded
                                      : (isLocked ? Icons.lock_rounded : Icons.hourglass_top_rounded)),
                              size: 13,
                              color: isModified
                                  ? const Color(0xFF3B82F6)
                                  : (isUnlockedByPassword
                                      ? const Color(0xFF0EA5E9)
                                      : (isLocked ? const Color(0xFF10B981) : const Color(0xFFF59E0B))),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isModified
                                  ? 'معدل (بانتظار الحفظ)'
                                  : (isUnlockedByPassword
                                      ? 'مفتوح للتعديل 🔓'
                                      : (isLocked
                                          ? (isMatch ? 'معتمد ومقفل 🔒 (متطابق)' : 'معتمد ومقفل 🔒')
                                          : (hasActual ? 'جاهز للاعتماد' : 'بانتظار التسوية'))),
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: isModified
                                    ? const Color(0xFF3B82F6)
                                    : (isUnlockedByPassword
                                        ? const Color(0xFF0EA5E9)
                                        : (isLocked ? const Color(0xFF10B981) : const Color(0xFFF59E0B))),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 11. Individual Approve Button / Settled Badge + Delete Estimated Item
                    DataCell(
                      isLocked && !isUnlockedByPassword
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFF10B981)),
                                  SizedBox(width: 4),
                                  Text(
                                    'معتمد ومقفل',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF10B981),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: (_settlingItemKeys.contains(key) ||
                                          isDeleting)
                                      ? null
                                      : () => _settleSingleCostItem(item),
                                  icon: _settlingItemKeys.contains(key)
                                      ? const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white),
                                        )
                                      : const Icon(
                                          Icons.check_circle_outline_rounded,
                                          size: 14),
                                  label: Text(
                                    isUnlockedByPassword
                                        ? 'حفظ وإعادة القفل'
                                        : 'اعتماد التسوية',
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isUnlockedByPassword
                                        ? const Color(0xFF0EA5E9)
                                        : const Color(0xFF10B981),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    elevation: 1,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6)),
                                  ),
                                ),
                                if (canDelete) ...[
                                  const SizedBox(width: 6),
                                  EstimatedCostDeleteButton(
                                    isDeleting: isDeleting,
                                    onPressed: () =>
                                        _deleteEstimatedCostItem(item),
                                  ),
                                ],
                              ],
                            ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  // ── Empty State ──
  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.assignment_turned_in_outlined,
                color: AppTheme.primary,
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد بنود تكلفة مطابقة للبحث أو المورد المختار',
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _selectedSupplierId != null
                  ? 'لم يتم العثور على بنود تكلفة مسجلة تخص المورد المحدد ضمن النطاق الزمني والفلاتر الحالية.'
                  : 'تظهر هنا بنود التكلفة التقديرية المرتبطة بموردي المحطات والتخصيمات من أوامر التعبئة لتسويتها فعلياً.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
                fontFamily: 'Cairo',
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_selectedSupplierId != null) ...[
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _selectedSupplierId = null;
                      });
                    },
                    icon: const Icon(Icons.all_inclusive_rounded, size: 16),
                    label: const Text('عرض جميع الموردين', style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                  ),
                  const SizedBox(width: 8),
                ],
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _filterOnlyPending = false;
                      _searchCtrl.clear();
                      _fromOrderCtrl.clear();
                      _toOrderCtrl.clear();
                      _searchQuery = '';
                      _selectedSupplierId = null;
                      _fromDate = null;
                      _toDate = null;
                    });
                    _loadData();
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('إعادة ضبط كافة الفلاتر', style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
