import 'dart:io';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:intl/intl.dart' hide TextDirection;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/dao/treasury_dao.dart';
import '../../data/models/treasury_model.dart';
import 'package:accounting_system/core/utils/file_helper.dart';

class CurrencyTransactionsPage extends StatefulWidget {
  final String treasuryId;
  final String treasuryName;
  final String currency;

  const CurrencyTransactionsPage({
    super.key,
    required this.treasuryId,
    required this.treasuryName,
    required this.currency,
  });

  @override
  State<CurrencyTransactionsPage> createState() =>
      _CurrencyTransactionsPageState();
}

class _CurrencyTransactionsPageState extends State<CurrencyTransactionsPage> {
  final _dao = TreasuryDao();
  final _scrollCtrl = ScrollController();
  final _searchCtrl = TextEditingController();

  List<TreasuryTransactionModel> _txns = [];
  bool _loading = true;
  bool _hasMore = true;
  int _offset = 0;
  static const int _limit = 50;
  String? _typeFilter;
  String _searchQuery = '';
  bool _exporting = false;

  final _typeOptions = <String?>[
    null, 'deposit', 'expense', 'withdrawal', 'disbursement',
    'disbursement_out', 'transfer_in', 'transfer_out', 'return_in', 'return_out',
    'supplier_payment',
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _debugCheckLinking();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 200 &&
        !_loading &&
        _hasMore) {
      _loadMore();
    }
  }

  // TODO: احذف هذه الدالة بعد التحقق من الربط
  Future<void> _debugCheckLinking() async {
    try {
      final raw = await _dao.getTransactionsForExport(
        treasuryId: int.parse(widget.treasuryId),
        currency: widget.currency,
      );
      final total = raw.length;
      final withCustomer = raw.where((m) => m['customer_id'] != null).length;
      final withSupplier = raw.where((m) => m['supplier_id'] != null).length;

      debugPrint('═══════════════════════════════════════════');
      debugPrint('🔍 Debug: Linking check for ${widget.currency}');
      debugPrint('   Total transactions : $total');
      debugPrint('   Linked to customer : $withCustomer');
      debugPrint('   Linked to supplier : $withSupplier');

      if (raw.isNotEmpty) {
        final first = raw.first;
        debugPrint('   ─── Example first tx ───');
        debugPrint('   customer_id  : ${first['customer_id']}');
        debugPrint('   supplier_id  : ${first['supplier_id']}');
        final createdByUser = first['created_by_user'];
        debugPrint('   creatorName  : ${createdByUser is Map ? createdByUser['full_name'] : 'N/A'}');
        debugPrint('   description  : ${first['description']}');
        debugPrint('   type         : ${first['type']}');
      }
      debugPrint('═══════════════════════════════════════════');
    } catch (e, st) {
      debugPrint('❌ Debug check failed: $e\n$st');
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _offset = 0;
    try {
      final raw = await _dao.getTransactions(
        widget.treasuryId,
        limit: _limit,
        offset: 0,
      );
      _txns = _applyFilters(raw);
      _hasMore = raw.length >= _limit;
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    _offset += _limit;
    try {
      final raw = await _dao.getTransactions(
        widget.treasuryId,
        limit: _limit,
        offset: _offset,
      );
      _txns.addAll(_applyFilters(raw));
      _hasMore = raw.length >= _limit;
    } catch (_) {}
    setState(() => _loading = false);
  }

  List<TreasuryTransactionModel> _applyFilters(
      List<TreasuryTransactionModel> list) {
    var result = list.where((t) => t.currency == widget.currency).toList();
    if (_typeFilter != null) {
      result =
          result.where((t) => t.transactionType == _typeFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((t) =>
          t.description?.toLowerCase().contains(q) == true ||
          t.typeLabel.toLowerCase().contains(q)).toList();
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  // ── Export to Excel ──

  Future<void> _exportToExcel() async {
    setState(() => _exporting = true);
    try {
      final customerMap = await _dao.getCustomerNameMap();
      final supplierMap = await _dao.getSupplierNameMap();

      final excel = Excel.createExcel();
      final sheet = excel['حركات'];

      // Column widths
      sheet.setColumnWidth(0, 18);
      sheet.setColumnWidth(1, 16);
      sheet.setColumnWidth(2, 12);
      sheet.setColumnWidth(3, 10);
      sheet.setColumnWidth(4, 30);
      sheet.setColumnWidth(5, 14);
      sheet.setColumnWidth(6, 14);
      sheet.setColumnWidth(7, 16);
      sheet.setColumnWidth(8, 20);

      // Header row
      final headers = [
        'التاريخ والوقت', 'نوع الحركة', 'المبلغ', 'العملة',
        'الوصف', 'المنشئ', 'العميل/المورد',
      ];
      final headerCell = CellStyle(
        fontFamily: getFontFamily(FontFamily.Calibri),
        fontSize: 12,
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        backgroundColorHex: ExcelColor.fromHexString('#1B5E20'),
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );
      for (var i = 0; i < headers.length; i++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = headerCell;
      }

      // Data rows
      final dataCell = CellStyle(
        fontFamily: getFontFamily(FontFamily.Calibri),
        fontSize: 11,
        horizontalAlign: HorizontalAlign.Left,
        verticalAlign: VerticalAlign.Center,
      );
      final dataCellCenter = CellStyle(
        fontFamily: getFontFamily(FontFamily.Calibri),
        fontSize: 11,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );
      final dataCellAmount = CellStyle(
        fontFamily: getFontFamily(FontFamily.Calibri),
        fontSize: 11,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        numberFormat: NumFormat.standard_2,
      );

      for (var i = 0; i < _txns.length; i++) {
        final tx = _txns[i];
        final row = i + 1;

        String entityName = '';
        if (tx.customerId != null) {
          entityName = customerMap['${tx.customerId}'] ?? '#${tx.customerId}';
        } else if (tx.supplierId != null) {
          entityName = supplierMap[tx.supplierId] ?? '#${tx.supplierId}';
        }

        final dateStr = _formatDateForExcel(tx.createdAt);

        final values = <dynamic>[
          dateStr,
          tx.typeLabel,
          tx.amount,
          tx.currency,
          tx.description ?? '',
          tx.creatorName ?? '',
          entityName,
        ];

        for (var c = 0; c < values.length; c++) {
          final cell = sheet.cell(
              CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row));
          final val = values[c];
          if (val is double) {
            cell.value = DoubleCellValue(val);
            cell.cellStyle = dataCellAmount;
          } else if (val is int) {
            cell.value = IntCellValue(val);
            cell.cellStyle = dataCellCenter;
          } else {
            cell.value = TextCellValue(val?.toString() ?? '');
            cell.cellStyle = c == 4 ? dataCell : dataCellCenter;
          }
        }
      }

      // Save to temp file
      final dir = await FileHelper.getExportDirectory();
      final datePart = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'transactions_${widget.currency}_$datePart.xlsx';
      final filePath = '${dir.path}/$fileName';
      final bytes = excel.encode();
      if (bytes == null) throw Exception('فشل ترميز ملف Excel');
      await File(filePath).writeAsBytes(bytes);

      if (!mounted) return;

      // Show success with open + share actions
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تصدير ${_txns.length} حركة إلى $fileName',
              style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'فتح',
            textColor: Colors.white,
            onPressed: () => OpenFilex.open(filePath),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل التصدير: $e',
              style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      setState(() => _exporting = false);
    }
  }

  String _formatDateForExcel(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.treasuryName} — ${widget.currency}',
            style: const TextStyle(
                fontSize: 16, fontFamily: 'Cairo', color: Colors.white)),
        backgroundColor: const Color(0xFF051B2B),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_txns.isNotEmpty)
            IconButton(
              icon: _exporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.file_download_outlined),
              tooltip: 'تصدير إلى Excel',
              onPressed: _exporting ? null : _exportToExcel,
            ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(
                  color: Colors.white, fontSize: 13, fontFamily: 'Cairo'),
              decoration: const InputDecoration(
                hintText: 'بحث...',
                hintStyle: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
                prefixIcon: Icon(Icons.search,
                    color: AppTheme.textSecondary, size: 18),
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (v) {
                _searchQuery = v;
                _load();
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _typeFilter,
              dropdownColor: const Color(0xDD05192D),
              hint: const Text('الكل',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      fontFamily: 'Cairo')),
              items: _typeOptions.map((t) => DropdownMenuItem(
                value: t,
                child: Text(
                  t == null ? 'الكل' : _typeLabel(t),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontFamily: 'Cairo'),
                ),
              )).toList(),
              onChanged: (v) {
                _typeFilter = v;
                _load();
              },
            ),
          ),
        ),
      ]),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'deposit':
        return 'إيداع';
      case 'expense':
        return 'مصروف';
      case 'withdrawal':
        return 'سحب';
      case 'disbursement':
        return 'صرف عهدة وارد';
      case 'disbursement_out':
        return 'صرف عهدة صادر';
      case 'transfer_in':
        return 'تحويل وارد';
      case 'transfer_out':
        return 'تحويل صادر';
      case 'return_in':
        return 'مرتجع وارد';
      case 'return_out':
        return 'مرتجع صادر';
      case 'supplier_payment':
        return 'دفعة للمورد';
      case 'currency_exchange_in':
        return 'تحويل عملة وارد';
      case 'currency_exchange_out':
        return 'تحويل عملة صادر';
      case 'payment':
        return 'سند قبض';
      case 'receipt':
        return 'سند قبض';
      case 'purchase':
        return 'شراء';
      case 'sale':
        return 'بيع';
      case 'cheque':
        return 'شيك';
      case 'receive':
        return 'قبض';
      case 'income':
        return 'إيراد';
      case 'opening_balance':
        return 'رصيد افتتاحي';
      default:
        return type;
    }
  }

  Widget _buildList() {
    if (_loading && _txns.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_txns.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 64,
                color: AppTheme.textSecondary.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            const Text('لا توجد حركات',
                style: TextStyle(
                    color: AppTheme.textSecondary, fontFamily: 'Cairo')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: _txns.length + (_hasMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i == _txns.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            );
          }
          return _buildRow(_txns[i]);
        },
      ),
    );
  }

  Widget _buildRow(TreasuryTransactionModel tx) {
    final isIncoming = tx.isIncoming;
    return Card(
      color: Colors.white.withValues(alpha: 0.04),
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        dense: true,
        leading: Icon(
          isIncoming ? Icons.arrow_downward : Icons.arrow_upward,
          color: isIncoming ? AppTheme.success : AppTheme.danger,
          size: 18,
        ),
        title: Text(tx.typeLabel,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'Cairo')),
        subtitle: Text(
          '${tx.amount.toStringAsFixed(2)} ${tx.currency}'
          '${tx.description != null && tx.description!.isNotEmpty ? ' • ${tx.description}' : ''}'
          '${tx.creatorName != null ? ' • ${tx.creatorName}' : ''}',
          style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontFamily: 'Cairo'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          AppUtils.formatDate(_parseDate(tx.createdAt)),
          style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 10,
              fontFamily: 'Cairo'),
        ),
      ),
    );
  }

  DateTime _parseDate(String s) => DateTime.tryParse(s) ?? DateTime.now();
}
