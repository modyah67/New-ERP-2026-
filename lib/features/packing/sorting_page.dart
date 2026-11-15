import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:excel/excel.dart' hide Border;
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/data_change_event_bus.dart';
import 'dart:async';
import '../../data/dao/packing_order_sorting_dao.dart';
import '../../data/dao/treasury_dao.dart';
import '../../data/dao/customer_dao.dart';
import '../../data/models/packing_order_sorting_model.dart';
import '../../data/models/customer_model.dart';
import 'package:accounting_system/core/utils/file_helper.dart';
import '../../data/services/journal_entry_navigation_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'sorted_batch_sale_pdf_service.dart';

class SortingPage extends StatefulWidget {
  const SortingPage({super.key});

  @override
  State<SortingPage> createState() => _SortingPageState();
}

class _SortingPageState extends State<SortingPage> {
  final _dao = PackingOrderSortingDao();
  final _treasuryDao = TreasuryDao();
  final _customerDao = CustomerDao();
  static const _currencyCode = 'EGP';
  List<PackingOrderSortingModel> _allSortings = [];
  List<PackingOrderSortingModel> _filtered = [];
  bool _loading = true;
  String _filter = 'pending';
  String _searchQuery = '';
  DateTime? _dateFrom;
  DateTime? _dateTo;

  int _allCount = 0;
  int _pendingCount = 0;
  int _partialCount = 0;
  int _soldCount = 0;
  int _fullySoldCount = 0;

  StreamSubscription<void>? _sortingSubscription;
  StreamSubscription<void>? _packingOrdersSubscription;

  @override
  void initState() {
    super.initState();
    _load();
    _sortingSubscription = DataChangeEventBus.instance.sortingStream.listen((_) {
      if (mounted) _load();
    });
    _packingOrdersSubscription = DataChangeEventBus.instance.packingOrdersStream.listen((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _sortingSubscription?.cancel();
    _packingOrdersSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _allSortings = await _dao.getAll();
    } catch (_) {}
    _applyFilter();
    if (mounted) setState(() => _loading = false);
  }

  void _applyFilter() {
    var base = List<PackingOrderSortingModel>.from(_allSortings);

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase().trim();
      base = base.where((s) =>
        s.productName.toLowerCase().contains(q) ||
        (s.lotNumber != null && s.lotNumber!.toLowerCase().contains(q)) ||
        (s.exportShipmentNo != null && s.exportShipmentNo!.toLowerCase().contains(q)) ||
        (s.customerName != null && s.customerName!.toLowerCase().contains(q)) ||
        s.packingOrderId.toString().contains(q)
      ).toList();
    }

    if (_dateFrom != null) {
      base = base.where((s) =>
        s.createdAt != null && !s.createdAt!.isBefore(_dateFrom!)
      ).toList();
    }

    if (_dateTo != null) {
      final endOfDay = DateTime(_dateTo!.year, _dateTo!.month, _dateTo!.day, 23, 59, 59);
      base = base.where((s) =>
        s.createdAt != null && !s.createdAt!.isAfter(endOfDay)
      ).toList();
    }

    // Accurately evaluate total_qty, sold_qty, and remaining stock status
    _allCount = base.length;
    _pendingCount = base.where((s) => s.remainingWeightKg > 0).length;
    _partialCount = base.where((s) {
      final sold = s.weightKg - s.remainingWeightKg;
      return sold > 0 && s.remainingWeightKg > 0;
    }).length;
    _soldCount = base.where((s) {
      final sold = s.weightKg - s.remainingWeightKg;
      return sold > 0 || s.remainingWeightKg <= 0 || s.status == 'sold';
    }).length;
    _fullySoldCount = base.where((s) => s.remainingWeightKg <= 0 || s.status == 'sold').length;

    // Apply active filter condition
    switch (_filter) {
      case 'pending':
        _filtered = base.where((s) => s.remainingWeightKg > 0).toList();
        break;
      case 'partial':
        _filtered = base.where((s) {
          final sold = s.weightKg - s.remainingWeightKg;
          return sold > 0 && s.remainingWeightKg > 0;
        }).toList();
        break;
      case 'sold':
        _filtered = base.where((s) {
          final sold = s.weightKg - s.remainingWeightKg;
          return sold > 0 || s.remainingWeightKg <= 0 || s.status == 'sold';
        }).toList();
        break;
      case 'fully_sold':
        _filtered = base.where((s) => s.remainingWeightKg <= 0 || s.status == 'sold').toList();
        break;
      case 'all':
      default:
        _filtered = base;
        break;
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_dateFrom ?? now) : (_dateTo ?? now),
      firstDate: DateTime(2020),
      lastDate: now,
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _dateFrom = picked;
        } else {
          _dateTo = picked;
        }
        _applyFilter();
      });
    }
  }

  Future<List<CustomerModel>> _fetchLocalCustomers() async {
    try {
      final allCustomers = await _customerDao.getAll(limit: 500);

      // Resolve account id for 12512 ("عملاء محلي") from Chart of Accounts
      int? localAccountId;
      try {
        final accRow = await Supabase.instance.client
            .from('accounts')
            .select('id')
            .eq('account_code', '12512')
            .maybeSingle();
        if (accRow != null) {
          localAccountId = (accRow['id'] as num?)?.toInt();
        }
      } catch (_) {}

      final localList = allCustomers.where((c) {
        final type = c.customerType.toLowerCase().trim();
        final isLocalType = type == 'local' ||
            type == 'محلي' ||
            type == 'local_customer' ||
            type == 'عملاء محلي';
        final isLocalAccount = localAccountId != null && c.accountId == localAccountId;
        return isLocalType || isLocalAccount;
      }).toList();

      return localList.isNotEmpty ? localList : allCustomers;
    } catch (e) {
      debugPrint('Error fetching local customers: $e');
      return [];
    }
  }

  Future<void> _sellSorting(PackingOrderSortingModel sorting) async {
    final treasuries = await _treasuryDao.getAll();
    if (treasuries.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا توجد خزن متاحة. يرجى إنشاء خزينة أولاً.',
                textDirection: TextDirection.rtl),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
      return;
    }

    final localCustomers = await _fetchLocalCustomers();

    if (!mounted) return;

    final qtyCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    String? selectedTreasuryId;
    String? selectedTreasuryName;
    String? selectedLocalCustomerId;
    String? selectedLocalCustomerName;

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDark = AppTheme.isDark(ctx);
          final qty = double.tryParse(qtyCtrl.text) ?? 0;
          final price = double.tryParse(priceCtrl.text) ?? 0;
          final total = qty * price;
          final screenWidth = MediaQuery.of(ctx).size.width;
          final dialogWidth = (screenWidth - 48).clamp(280.0, 400.0);

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1A2940) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('بيع فرز',
                style: TextStyle(
                    color: isDark ? AppTheme.textPrimary : Colors.black,
                    fontFamily: 'Cairo',
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            content: Directionality(
              textDirection: TextDirection.rtl,
              child: SizedBox(
                width: dialogWidth,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoRow('المنتج', sorting.productName,
                          valueColor: isDark ? AppTheme.textPrimary : Colors.black, isDark: isDark),
                      const SizedBox(height: 4),
                      _infoRow(
                          'المتبقي',
                          '${sorting.remainingWeightKg.toStringAsFixed(0)} كجم',
                          valueColor: isDark ? AppTheme.textPrimary : Colors.black, isDark: isDark),
                      const SizedBox(height: 14),
                      TextField(
                        controller: qtyCtrl,
                        decoration: InputDecoration(
                          labelText: 'الكمية المباعة (كجم)',
                          suffixText: 'كجم',
                          suffixStyle: TextStyle(
                              color: isDark ? AppTheme.textSecondary : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo'),
                          labelStyle: TextStyle(
                              color: isDark ? AppTheme.textSecondary : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo'),
                          filled: true,
                          fillColor: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFF1F5F9),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
                        ),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                        ],
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            fontSize: 15),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: priceCtrl,
                        decoration: InputDecoration(
                          labelText: 'سعر البيع (${AppUtils.currencySymbol(_currencyCode)}/كجم)',
                          suffixText: AppUtils.currencySymbol(_currencyCode),
                          suffixStyle: TextStyle(
                              color: isDark ? AppTheme.textSecondary : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo'),
                          labelStyle: TextStyle(
                              color: isDark ? AppTheme.textSecondary : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo'),
                          filled: true,
                          fillColor: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFF1F5F9),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
                        ),
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                        ],
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            fontSize: 15),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? Colors.transparent : const Color(0xFFCBD5E1)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            dropdownColor: isDark ? const Color(0xFF1A2940) : Colors.white,
                            value: selectedTreasuryId,
                            hint: Text('اختر الخزنة المستهدفة',
                                style: TextStyle(
                                    color: isDark ? AppTheme.textSecondary : Colors.black54,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo')),
                            items: treasuries
                                .map((t) => DropdownMenuItem<String>(
                                      value: t.id,
                                      child: Text(t.displayName,
                                          style: TextStyle(
                                              color: isDark ? Colors.white : Colors.black,
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'Cairo')),
                                    ))
                                .toList(),
                            onChanged: (val) {
                              setDialogState(() {
                                selectedTreasuryId = val;
                                selectedTreasuryName = treasuries.firstWhere((t) => t.id == val).displayName;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        dropdownColor: isDark ? const Color(0xFF1A2940) : Colors.white,
                        initialValue: selectedLocalCustomerId,
                        decoration: InputDecoration(
                          labelText: 'اختر العميل المحلي',
                          labelStyle: TextStyle(
                              color: isDark ? AppTheme.textSecondary : Colors.black87,
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 14),
                          filled: true,
                          fillColor: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFF1F5F9),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 15),
                        hint: Text('اختر العميل المحلي',
                            style: TextStyle(
                                color: isDark ? AppTheme.textSecondary : Colors.black54,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo')),
                        items: localCustomers
                            .map((c) => DropdownMenuItem<String>(
                                  value: c.id,
                                  child: Text(
                                    c.name.isNotEmpty
                                        ? c.name
                                        : (c.code.isNotEmpty
                                            ? c.code
                                            : 'عميل #${c.id}'),
                                    style: TextStyle(
                                        color: isDark ? Colors.white : Colors.black,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Cairo'),
                                  ),
                                ))
                            .toList(),
                        onChanged: (val) {
                          setDialogState(() {
                            selectedLocalCustomerId = val;
                            if (val != null) {
                              final matched = localCustomers.where((c) => c.id == val);
                              if (matched.isNotEmpty) {
                                selectedLocalCustomerName = matched.first.name;
                              }
                            } else {
                              selectedLocalCustomerName = null;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      if (qty > 0 && price > 0) ...[
                        Divider(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                        const SizedBox(height: 6),
                        _infoRow('كمية البيع',
                            '${qty.toStringAsFixed(0)} كجم',
                            valueColor: isDark ? AppTheme.textPrimary : Colors.black, isDark: isDark),
                        const SizedBox(height: 4),
                        _infoRow('اجمالي البيع',
                            '${total.toStringAsFixed(2)} ${AppUtils.currencySymbol(_currencyCode)}',
                            valueColor: AppTheme.success, isDark: isDark),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppTheme.textSecondary : Colors.black87)),
              ),
              ElevatedButton(
                onPressed: (qty > 0 &&
                        price > 0 &&
                        selectedTreasuryId != null &&
                        qty <= sorting.remainingWeightKg)
                    ? () => Navigator.pop(
                        ctx, {
                          'quantity': qty,
                          'price': price,
                          'treasury_id': selectedTreasuryId,
                          'treasury_name': selectedTreasuryName,
                          'customer_id': selectedLocalCustomerId,
                          'customer_name': selectedLocalCustomerName,
                        })
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  foregroundColor: Colors.white,
                ),
                child: const Text('تأكيد البيع',
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      final qty = result['quantity'] as double;
      final price = result['price'] as double;
      final treasuryId = result['treasury_id'] as String;
      final treasuryName = result['treasury_name'] as String;
      final customerId = result['customer_id'] as String?;
      final customerName = result['customer_name'] as String?;
      final amount = qty * price;

      try {
        await _dao.processSortingSale(
          sorting: sorting,
          quantityKg: qty,
          unitPrice: price,
          treasuryId: int.tryParse(treasuryId) ?? 1,
          treasuryName: treasuryName,
          customerId: customerId != null ? int.tryParse(customerId) : null,
          customerName: customerName,
        );

        await _load();

        if (mounted) {
          final customerInfo = (customerName != null && customerName.isNotEmpty)
              ? ' للعميل ($customerName)'
              : '';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'تم البيع بنجاح$customerInfo - المبلغ: ${amount.toStringAsFixed(2)} ${AppUtils.currencySymbol(_currencyCode)}',
                  textDirection: TextDirection.rtl),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('خطأ: $e', textDirection: TextDirection.rtl),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
      }
    }
  }

  Map<String, Map<String, dynamic>> _buildSummary(List<PackingOrderSortingModel> items) {
    final summary = <String, Map<String, dynamic>>{};
    for (final s in items) {
      final sold = s.weightKg - s.remainingWeightKg;
      if (sold <= 0) continue;
      if (!summary.containsKey(s.productName)) {
        summary[s.productName] = {
          'totalWeight': 0.0,
          'soldWeight': 0.0,
          'totalSale': 0.0,
          'count': 0,
        };
      }
      final entry = summary[s.productName]!;
      entry['totalWeight'] = (entry['totalWeight'] as double) + s.weightKg;
      entry['soldWeight'] = (entry['soldWeight'] as double) + sold;
      entry['totalSale'] = (entry['totalSale'] as double) + s.totalSaleAmount;
      entry['count'] = (entry['count'] as int) + 1;
    }
    return summary;
  }

  String get _dateLabel {
    final from = _dateFrom != null ? DateFormat('yyyy-MM-dd').format(_dateFrom!) : '—';
    final to = _dateTo != null ? DateFormat('yyyy-MM-dd').format(_dateTo!) : '—';
    return 'من $from إلى $to';
  }

  Future<void> _exportExcel() async {
    final items = _filtered;
    if (items.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد بيانات للتصدير', textDirection: TextDirection.rtl), backgroundColor: AppTheme.danger),
        );
      }
      return;
    }

    final excel = Excel.createExcel();
    final sheet = excel['تقارير الفرز'];

    final headerStyle = CellStyle(
      fontSize: 11,
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#1A5276'),
      horizontalAlign: HorizontalAlign.Center,
    );

    final headers = ['التاريخ', 'المنتج', 'رقم اللوت', 'الوزن الأصلي', 'المتبقي', 'الوزن المباع', 'اجمالي المبيعات', 'الخزنة', 'الحالة'];
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }

    for (var i = 0; i < items.length; i++) {
      final s = items[i];
      final sold = s.weightKg - s.remainingWeightKg;
      final row = i + 1;

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
          TextCellValue(s.createdAt != null ? DateFormat('yyyy-MM-dd').format(s.createdAt!) : '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value =
          TextCellValue(s.productName);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value =
          TextCellValue(s.lotNumber ?? '');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value =
          DoubleCellValue(s.weightKg);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value =
          DoubleCellValue(s.remainingWeightKg);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value =
          DoubleCellValue(sold);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row)).value =
          DoubleCellValue(s.totalSaleAmount);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row)).value =
          TextCellValue(s.treasuryNames ?? '—');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row)).value =
          TextCellValue(s.isSoldOut ? 'تم البيع بالكامل' : (sold > 0 ? 'مباع جزئياً' : 'متاح'));
    }

    final summary = _buildSummary(items);
    if (summary.isNotEmpty) {
      final startRow = items.length + 3;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: startRow)).value =
          TextCellValue('ملخص المبيعات');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: startRow)).cellStyle =
          CellStyle(bold: true, fontSize: 12);

      final sumHeaders = ['المنتج', 'العدد', 'الوزن المباع (كجم)', 'اجمالي المبيعات (${AppUtils.currencySymbol(_currencyCode)})'];
      for (var i = 0; i < sumHeaders.length; i++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: startRow + 1));
        cell.value = TextCellValue(sumHeaders[i]);
        cell.cellStyle = headerStyle;
      }

      var r = startRow + 2;
      for (final entry in summary.entries) {
        final v = entry.value;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value =
            TextCellValue(entry.key);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value =
            IntCellValue(v['count'] as int);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value =
            DoubleCellValue(v['soldWeight'] as double);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value =
            DoubleCellValue(v['totalSale'] as double);
        r++;
      }
    }

    final bytes = excel.save();
    if (bytes == null) return;

    final dir = await FileHelper.getExportDirectory();
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final file = File('${dir.path}/sorting_report_$dateStr.xlsx');
    await file.writeAsBytes(bytes);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم التصدير: ${file.path}', textDirection: TextDirection.rtl), backgroundColor: AppTheme.success),
      );
    }
  }

  Future<void> _exportPdf() async {
    final items = _filtered;
    if (items.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد بيانات للتصدير', textDirection: TextDirection.rtl), backgroundColor: AppTheme.danger),
        );
      }
      return;
    }

    await SortedBatchSalePdfService.printSalesRegister(
      context,
      items,
      dateLabel: _dateLabel,
      filterQuery: _searchQuery.trim().isNotEmpty ? _searchQuery.trim() : null,
      currency: _currencyCode,
    );
  }

  Widget _buildSortingCard(PackingOrderSortingModel sorting, double width, bool isDark) {
    final dateStr = sorting.createdAt != null
        ? DateFormat('yyyy-MM-dd').format(sorting.createdAt!)
        : '—';
    final isSoldOut = sorting.isSoldOut;
    final totalQty = sorting.weightKg;
    final remainingQty = sorting.remainingWeightKg;
    final soldQty = totalQty - remainingQty;
    final isSmall = width < 400;
    final isMedium = width >= 400 && width < 700;
    final titleSize = isSmall ? 15.0 : (isMedium ? 17.0 : 19.0);
    final bodySize = isSmall ? 12.5 : (isMedium ? 13.5 : 14.5);
    final secondarySize = isSmall ? 11.0 : (isMedium ? 12.0 : 13.0);
    final statIconSize = isSmall ? 16.0 : 18.0;

    return Container(
      margin: const EdgeInsets.all(4),
      padding: EdgeInsets.all(isSmall ? 10 : 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D253E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isSoldOut
              ? (isDark ? AppTheme.success.withValues(alpha: 0.3) : const Color(0xFF86EFAC))
              : (isDark ? AppTheme.primary.withValues(alpha: 0.4) : const Color(0xFFCBD5E1)),
          width: 1.5,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF163A5F) : const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.inventory_2_outlined,
                  color: isDark ? AppTheme.primary : const Color(0xFF0284C7),
                  size: statIconSize,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sorting.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? AppTheme.textPrimary : Colors.black,
                    fontSize: titleSize,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF163A5F) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isDark ? AppTheme.primary.withValues(alpha: 0.5) : const Color(0xFFCBD5E1)),
                  ),
                  child: Text(
                    sorting.lotNumber ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? AppTheme.primary : const Color(0xFF0284C7),
                      fontSize: secondarySize,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
              ),
              if (sorting.totalSaleAmount > 0) ...[
                const SizedBox(width: 6),
                _buildPrintSalePdfButton(sorting, statIconSize),
              ],
            ],
          ),
          const SizedBox(height: 6),
          // Order ID & Traceability info (Shipment / Customer)
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tag, size: secondarySize - 1, color: isDark ? AppTheme.textSecondary : Colors.black54),
                    const SizedBox(width: 2),
                    Text(
                      'أمر #${sorting.packingOrderId}',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: secondarySize - 1,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppTheme.textSecondary : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
              if (sorting.exportShipmentNo != null && sorting.exportShipmentNo!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isDark ? const Color(0xFF3B82F6).withValues(alpha: 0.3) : const Color(0xFFBFDBFE),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.local_shipping_outlined, size: secondarySize - 1, color: const Color(0xFF3B82F6)),
                      const SizedBox(width: 2),
                      Text(
                        'شحنة: ${sorting.exportShipmentNo}',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: secondarySize - 1,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8),
                        ),
                      ),
                    ],
                  ),
                ),
              if (sorting.customerName != null && sorting.customerName!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isDark ? const Color(0xFF22C55E).withValues(alpha: 0.3) : const Color(0xFFBBF7D0),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_outline, size: secondarySize - 1, color: const Color(0xFF16A34A)),
                      const SizedBox(width: 2),
                      Text(
                        'عميل: ${sorting.customerName}',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: secondarySize - 1,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          SizedBox(height: isSmall ? 6 : 8),
          Container(
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: isSoldOut
                    ? (isDark ? AppTheme.success.withValues(alpha: 0.15) : const Color(0xFFDCFCE7))
                    : (isDark ? AppTheme.warning.withValues(alpha: 0.15) : const Color(0xFFFEF3C7)),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSoldOut
                      ? AppTheme.success
                      : (isDark ? AppTheme.warning : const Color(0xFFF59E0B)),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: isSoldOut ? AppTheme.success : (isDark ? AppTheme.warning : const Color(0xFFD97706)),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isSoldOut ? 'تم البيع بالكامل' : 'متاح',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSoldOut ? (isDark ? AppTheme.success : const Color(0xFF16A34A)) : (isDark ? AppTheme.warning : const Color(0xFFD97706)),
                      fontSize: secondarySize,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: isSmall ? 8 : 12),
          _buildStatBox(
            icon: Icons.inventory_2_outlined,
            label: 'الكمية (${totalQty.toStringAsFixed(0)} كجم)',
            value: soldQty > 0 ? 'مباع ${soldQty.toStringAsFixed(0)}' : '—',
            valueColor: soldQty > 0 ? AppTheme.success : null,
            iconSize: statIconSize,
            fontSize: bodySize,
            isDark: isDark,
          ),
          SizedBox(height: isSmall ? 6 : 8),
          _buildStatBox(
            icon: Icons.scale_outlined,
            label: 'المتبقي',
            value: '${remainingQty.toStringAsFixed(0)} كجم',
            iconSize: statIconSize,
            fontSize: bodySize,
            isDark: isDark,
          ),
          if (sorting.totalSaleAmount > 0) ...[
            SizedBox(height: isSmall ? 6 : 8),
            _buildStatBox(
              icon: Icons.monetization_on_outlined,
              label: 'المبيعات',
              value: '${sorting.totalSaleAmount.toStringAsFixed(2)} ${AppUtils.currencySymbol(_currencyCode)}',
              valueColor: AppTheme.success,
              iconSize: statIconSize,
              fontSize: bodySize,
              isDark: isDark,
            ),
          ],
          SizedBox(height: isSmall ? 6 : 8),
          Text(
            dateStr,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isDark ? AppTheme.textSecondary : Colors.black54,
              fontSize: secondarySize,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo',
            ),
          ),
          if (!isSoldOut) ...[
            SizedBox(height: isSmall ? 8 : 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _sellSorting(sorting),
                icon: Icon(Icons.sell, size: isSmall ? 12 : 14),
                label: Text('بيع',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: isSmall ? 12 : 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: isSmall ? 6 : 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPrintSalePdfButton(PackingOrderSortingModel sorting, double iconSize) {
    return Tooltip(
      message: 'طباعة إذن بيع الفرزة (PDF)',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _printSortingSalePdf(sorting),
          onLongPress: () => _openJournalEntry(sorting),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.danger.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.danger.withAlpha(60)),
            ),
            child: Icon(Icons.picture_as_pdf, size: iconSize, color: AppTheme.danger),
          ),
        ),
      ),
    );
  }

  Future<void> _printSortingSalePdf(PackingOrderSortingModel sorting) async {
    final desc = 'بيع فرز - ${sorting.productName}';
    final client = Supabase.instance.client;
    String? jeEntryNumber;
    String? jeId;
    DateTime? saleDate = sorting.soldAt;

    try {
      final res = await client
          .from('v_journal_entry_lines')
          .select('journal_entry_id, entry_number, description, date')
          .ilike('description', '$desc%')
          .order('date', ascending: false)
          .limit(1);

      if (res.isNotEmpty) {
        final first = res.first;
        jeEntryNumber = first['entry_number']?.toString();
        jeId = first['journal_entry_id']?.toString();
        if (first['date'] != null) {
          saleDate = DateTime.tryParse(first['date'].toString()) ?? saleDate;
        }
      }
    } catch (e) {
      debugPrint('Error fetching JE for sorting sale: $e');
    }

    final details = SortedBatchSaleDetails(
      sorting: sorting,
      customerName: 'عميل نقدي / مبيعات فرزة',
      journalEntryNumber: jeEntryNumber,
      journalEntryId: jeId,
      treasuryName: sorting.treasuryNames ?? 'الخزينة العامة',
      saleDate: saleDate,
      currency: _currencyCode,
    );

    if (mounted) {
      await SortedBatchSalePdfService.printSaleVoucher(context, details);
    }
  }

  Future<void> _openJournalEntry(PackingOrderSortingModel sorting) async {
    final desc = 'بيع فرز - ${sorting.productName}';
    final client = Supabase.instance.client;
    try {
      final res = await client
          .from('v_journal_entry_lines')
          .select('journal_entry_id, entry_number, description')
          .ilike('description', '$desc%');

      if (res.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا يوجد قيد محاسبي مرتبط', textDirection: TextDirection.rtl), backgroundColor: AppTheme.danger),
          );
        }
        return;
      }

      final uniqueEntries = <String, Map<String, dynamic>>{};
      for (final r in res) {
        final entryNo = r['entry_number']?.toString();
        final jeId = r['journal_entry_id'];
        final d = r['description']?.toString();
        if (entryNo != null && d != null) {
          uniqueEntries[entryNo] = {
            'id': jeId,
            'desc': d,
          };
        }
      }

      if (uniqueEntries.length == 1) {
        if (mounted) {
          final target = uniqueEntries.values.first['id'] ?? uniqueEntries.keys.first;
          JournalEntryNavigationService.openById(context, journalEntryId: target);
        }
      } else {
        if (mounted) {
          final isDark = AppTheme.isDark(context);
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1A2940) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('القيود المحاسبية للمبيعات',
                  style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              content: SizedBox(
                width: 400,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: uniqueEntries.length,
                  itemBuilder: (context, index) {
                    final entryNo = uniqueEntries.keys.elementAt(index);
                    final item = uniqueEntries.values.elementAt(index);
                    final descText = item['desc']?.toString() ?? '';
                    final targetId = item['id'] ?? entryNo;
                    return ListTile(
                      title: Text(descText,
                          style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              fontWeight: FontWeight.bold)),
                      subtitle: Text('رقم القيد: $entryNo',
                          style: TextStyle(
                              color: isDark ? AppTheme.textSecondary : Colors.black87,
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                      trailing: const Icon(Icons.arrow_forward_ios, color: AppTheme.success, size: 14),
                      onTap: () {
                        Navigator.pop(ctx);
                        JournalEntryNavigationService.openById(context, journalEntryId: targetId);
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('إغلاق',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppTheme.textSecondary : Colors.black87)),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        JournalEntryNavigationService.openForTransaction(
          context,
          description: desc,
        );
      }
    }
  }

  Widget _buildStatBox({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    double iconSize = 16,
    double fontSize = 13,
    bool isDark = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF163A5F) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.transparent : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: isDark ? AppTheme.textSecondary : Colors.black87, size: iconSize),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark ? AppTheme.textSecondary : Colors.black87,
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  color: valueColor ?? (isDark ? AppTheme.textPrimary : Colors.black),
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? valueColor, bool isDark = true}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: isDark ? AppTheme.textSecondary : Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: valueColor ?? (isDark ? AppTheme.textPrimary : Colors.black),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
        ),
      ],
    );
  }

  String _formatDateShort(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.background : AppTheme.lightBackground,
        body: Container(
          decoration: isDark ? AppTheme.backgroundGradient : null,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final screenW = constraints.maxWidth;
              final isSmall = screenW < 400;
              final isMedium = screenW >= 400 && screenW < 700;
              final titleFontSize = isSmall ? 16.0 : (isMedium ? 18.0 : 22.0);
              final chipFontSize = isSmall ? 10.0 : 12.0;
              final crossAxisCount = screenW >= 1200 ? 4 : (screenW >= 800 ? 3 : (screenW >= 500 ? 2 : 1));
              final cardPadding = isSmall ? 12.0 : 16.0;

              return Column(
                children: [
                  ClipRRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        padding: EdgeInsets.only(
                            top: MediaQuery.of(context).padding.top + 12,
                            bottom: 12,
                            left: 8,
                            right: 8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0x3805192D) : Colors.white,
                          border: Border(
                              bottom: BorderSide(
                                  color: isDark
                                      ? AppTheme.glassBorder.withAlpha(50)
                                      : const Color(0xFFCBD5E1))),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                IconButton(
                                  icon: Icon(Icons.arrow_forward,
                                      color: isDark ? Colors.white : Colors.black),
                                  onPressed: () => context.pop(),
                                ),
                                Expanded(
                                  child: Text('الفرز',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: isDark ? AppTheme.textPrimary : Colors.black,
                                          fontSize: titleFontSize,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Cairo')),
                                ),
                                IconButton(
                                  icon: Icon(Icons.picture_as_pdf,
                                      color: AppTheme.danger,
                                      size: isSmall ? 18 : 20),
                                  onPressed: _exportPdf,
                                  tooltip: 'تصدير PDF',
                                ),
                                IconButton(
                                  icon: Icon(Icons.table_chart,
                                      color: AppTheme.success,
                                      size: isSmall ? 18 : 20),
                                  onPressed: _exportExcel,
                                  tooltip: 'تصدير Excel',
                                ),
                                IconButton(
                                  icon: Icon(Icons.refresh,
                                      color: AppTheme.primary,
                                      size: isSmall ? 18 : 20),
                                  onPressed: _load,
                                ),
                              ],
                            ),
                            SizedBox(height: isSmall ? 4 : 8),
                            TextField(
                              decoration: InputDecoration(
                                hintText: 'بحث...',
                                hintStyle: TextStyle(
                                    color: isDark ? AppTheme.textSecondary : Colors.black54,
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    fontSize: chipFontSize),
                                prefixIcon: Icon(Icons.search,
                                    color: isDark ? AppTheme.textSecondary : Colors.black87,
                                    size: isSmall ? 16 : 18),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _searchQuery = '';
                                            _applyFilter();
                                          });
                                        },
                                        child: Icon(Icons.close,
                                            color: isDark ? AppTheme.textSecondary : Colors.black87,
                                            size: isSmall ? 14 : 16),
                                      )
                                    : null,
                                filled: true,
                                fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
                                contentPadding:
                                    EdgeInsets.symmetric(horizontal: 10, vertical: isSmall ? 6 : 8),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
                                enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
                              ),
                              style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                  fontSize: chipFontSize),
                              onChanged: (v) {
                                setState(() {
                                  _searchQuery = v;
                                  _applyFilter();
                                });
                              },
                            ),
                            SizedBox(height: isSmall ? 4 : 8),
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => _pickDate(isFrom: true),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: _dateFrom != null
                                            ? (isDark ? AppTheme.primary.withValues(alpha: 0.15) : const Color(0xFFE0F2FE))
                                            : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: _dateFrom != null
                                                ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                                                : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.date_range,
                                              size: isSmall ? 12 : 14,
                                              color: isDark ? AppTheme.textSecondary : Colors.black87),
                                          const SizedBox(width: 3),
                                          Expanded(
                                            child: Text(
                                              _dateFrom != null
                                                  ? _formatDateShort(_dateFrom!)
                                                  : 'من تاريخ',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  color: _dateFrom != null
                                                      ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                                                      : (isDark ? AppTheme.textSecondary : Colors.black87),
                                                  fontSize: isSmall ? 10 : 11,
                                                  fontWeight: FontWeight.bold,
                                                  fontFamily: 'Cairo'),
                                            ),
                                          ),
                                          if (_dateFrom != null)
                                            GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  _dateFrom = null;
                                                  _applyFilter();
                                                });
                                              },
                                              child: Icon(Icons.close,
                                                  size: isSmall ? 10 : 12,
                                                  color: isDark ? AppTheme.textSecondary : Colors.black87),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => _pickDate(isFrom: false),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: _dateTo != null
                                            ? (isDark ? AppTheme.primary.withValues(alpha: 0.15) : const Color(0xFFE0F2FE))
                                            : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: _dateTo != null
                                                ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                                                : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.date_range,
                                              size: isSmall ? 12 : 14,
                                              color: isDark ? AppTheme.textSecondary : Colors.black87),
                                          const SizedBox(width: 3),
                                          Expanded(
                                            child: Text(
                                              _dateTo != null
                                                  ? _formatDateShort(_dateTo!)
                                                  : 'إلى تاريخ',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  color: _dateTo != null
                                                      ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                                                      : (isDark ? AppTheme.textSecondary : Colors.black87),
                                                  fontSize: isSmall ? 10 : 11,
                                                  fontWeight: FontWeight.bold,
                                                  fontFamily: 'Cairo'),
                                            ),
                                          ),
                                          if (_dateTo != null)
                                            GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  _dateTo = null;
                                                  _applyFilter();
                                                });
                                              },
                                              child: Icon(Icons.close,
                                                  size: isSmall ? 10 : 12,
                                                  color: isDark ? AppTheme.textSecondary : Colors.black87),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: isSmall ? 4 : 8),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _buildFilterChip('قيد الانتظار', 'pending', _pendingCount, chipFontSize, isDark: isDark),
                                  SizedBox(width: isSmall ? 4 : 8),
                                  _buildFilterChip('مباع جزئياً', 'partial', _partialCount, chipFontSize, isDark: isDark),
                                  SizedBox(width: isSmall ? 4 : 8),
                                  _buildFilterChip('تم البيع', 'sold', _soldCount, chipFontSize, isDark: isDark),
                                  SizedBox(width: isSmall ? 4 : 8),
                                  _buildFilterChip('تم البيع بالكامل', 'fully_sold', _fullySoldCount, chipFontSize, isDark: isDark),
                                  SizedBox(width: isSmall ? 4 : 8),
                                  _buildFilterChip('الكل', 'all', _allCount, chipFontSize, isDark: isDark),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: AppTheme.primary))
                        : _filtered.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.sort,
                                        size: 64,
                                        color: isDark
                                            ? AppTheme.textSecondary
                                                .withValues(alpha: 0.3)
                                            : Colors.black26),
                                    const SizedBox(height: 16),
                                    Text(
                                      _filter == 'pending'
                                          ? 'لا توجد عناصر فرز متاحة قيد الانتظار'
                                          : _filter == 'partial'
                                              ? 'لا توجد عناصر فرز مباعة جزئياً'
                                              : _filter == 'sold'
                                                  ? 'لا توجد عناصر فرز تم بيعها'
                                                  : _filter == 'fully_sold'
                                                      ? 'لا توجد عناصر فرز مباعة بالكامل'
                                                      : 'لا توجد عناصر فرز',
                                      style: TextStyle(
                                          color: isDark ? AppTheme.textSecondary : Colors.black,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Cairo'),
                                    ),
                                  ],
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _load,
                                color: AppTheme.primary,
                                child: crossAxisCount == 1
                                    ? ListView.builder(
                                        padding: EdgeInsets.all(cardPadding),
                                        itemCount: _filtered.length,
                                        itemBuilder: (context, index) {
                                          return _buildSortingCard(
                                              _filtered[index], screenW - cardPadding * 2, isDark);
                                        },
                                      )
                                    : GridView.builder(
                                        padding: EdgeInsets.all(cardPadding),
                                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: crossAxisCount,
                                          mainAxisExtent: screenW < 500 ? 395.0 : 410.0,
                                          crossAxisSpacing: 12,
                                          mainAxisSpacing: 12,
                                        ),
                                        itemCount: _filtered.length,
                                        itemBuilder: (context, index) {
                                          final cardW = (screenW - cardPadding * 2 - 12 * (crossAxisCount - 1)) / crossAxisCount;
                                          return _buildSortingCard(
                                              _filtered[index], cardW, isDark);
                                        },
                                      ),
                              ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, int count, double fontSize, {required bool isDark}) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _filter = value;
          _applyFilter();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? AppTheme.primary.withValues(alpha: 0.25) : const Color(0xFFE0F2FE))
              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
            width: selected ? 1.5 : 1.0,
          ),
          boxShadow: isDark || !selected
              ? null
              : [
                  BoxShadow(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                    : (isDark ? AppTheme.textSecondary : Colors.black87),
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                    : (isDark ? const Color(0xFF163A5F) : const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected
                      ? (isDark ? AppTheme.primary.withValues(alpha: 0.6) : const Color(0xFF0284C7))
                      : (isDark ? AppTheme.glassBorder.withValues(alpha: 0.3) : const Color(0xFFCBD5E1)),
                  width: 0.8,
                ),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: selected ? Colors.white : (isDark ? AppTheme.textSecondary : Colors.black),
                  fontSize: (fontSize - 1.5).clamp(9.0, 13.0),
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
