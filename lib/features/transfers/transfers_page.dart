import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/data_change_event_bus.dart';
import '../../core/theme.dart';
import '../../data/models/stock_transfer_model.dart';
import '../../data/services/journal_entry_navigation_service.dart';
import 'transfer_cubit.dart';
import 'transfer_state.dart';
import 'transfer_export_service.dart';

class TransfersPage extends StatefulWidget {
  const TransfersPage({super.key});

  @override
  State<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends State<TransfersPage> {
  late final TransferCubit _cubit;
  TransferLoaded? _lastLoadedState;
  Timer? _debounceRefresh;
  late StreamSubscription _stationsSub;
  late StreamSubscription _cropPurchasesSub;
  late StreamSubscription _itemsSub;

  @override
  void initState() {
    super.initState();
    _cubit = TransferCubit()..init();
    _stationsSub = DataChangeEventBus.instance.stationsStream.listen((_) => _debouncedRefresh());
    _cropPurchasesSub = DataChangeEventBus.instance.cropPurchasesStream.listen((_) => _debouncedRefresh());
    _itemsSub = DataChangeEventBus.instance.itemsStream.listen((_) => _debouncedRefresh());
  }

  void _debouncedRefresh() {
    _debounceRefresh?.cancel();
    _debounceRefresh = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _cubit.refreshDeletability();
    });
  }

  @override
  void dispose() {
    _debounceRefresh?.cancel();
    _stationsSub.cancel();
    _cropPurchasesSub.cancel();
    _itemsSub.cancel();
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return BlocProvider.value(
      value: _cubit,
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.background : AppTheme.lightBackground,
        body: Padding(
          padding: EdgeInsets.all(isMobile ? 12 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(isDark, isMobile),
              const SizedBox(height: 20),
              _buildSearchBar(isDark),
              const SizedBox(height: 12),
              _buildDateFilter(isDark),
              const SizedBox(height: 16),
              Expanded(child: _buildTable(isDark)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark, bool isMobile) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isDark ? AppTheme.success.withValues(alpha: 0.1) : const Color(0xFFDCFCE7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.transparent : const Color(0xFF86EFAC),
            ),
          ),
          child: Icon(Icons.swap_horiz, color: isDark ? AppTheme.success : const Color(0xFF16A34A), size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'تحويل بين المخازن',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isMobile ? 18 : 28,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                  fontFamily: 'Cairo',
                ),
              ),
              BlocBuilder<TransferCubit, TransferState>(
                buildWhen: (prev, curr) => curr is TransferLoaded,
                builder: (context, state) {
                  final count = state is TransferLoaded ? state.transfers.length : 0;
                  return Text(
                    '$count تحويل',
                    style: TextStyle(
                      color: isDark ? AppTheme.textSecondary : Colors.black,
                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                      fontFamily: 'Cairo',
                      fontSize: 13,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        if (!isMobile) ...[
          IconButton(
            icon: Icon(Icons.refresh_outlined, color: isDark ? null : Colors.black),
            tooltip: 'تحديث',
            onPressed: () => _cubit.loadAll(reset: true),
          ),
          IconButton(
            icon: const Icon(Icons.table_chart_outlined, color: AppTheme.success, size: 20),
            tooltip: 'تصدير Excel',
            onPressed: _exportExcel,
          ),
          const SizedBox(width: 8),
        ],
        ElevatedButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: Text(
            isMobile ? '+' : 'تحويل جديد',
            style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0284C7),
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 10),
          ),
          onPressed: () => _showTransferDialog(),
        ),
        if (isMobile) ...[
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: isDark ? AppTheme.textSecondary : Colors.black),
            onSelected: (v) {
              if (v == 'refresh') _cubit.loadAll(reset: true);
              else if (v == 'excel') _exportExcel();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'refresh', child: Text('تحديث', style: TextStyle(fontFamily: 'Cairo'))),
              const PopupMenuItem(value: 'excel', child: Text('تصدير Excel', style: TextStyle(fontFamily: 'Cairo'))),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSearchBar(bool isDark) {
    if (isDark) {
      return TextField(
        onChanged: _cubit.onSearchChanged,
        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
        decoration: InputDecoration(
          hintText: 'بحث بالمنتج أو الوصف...',
          hintStyle: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'),
          prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.textSecondary),
          suffixIcon: BlocBuilder<TransferCubit, TransferState>(
            buildWhen: (prev, curr) => curr is TransferLoaded,
            builder: (context, state) {
              final query = state is TransferLoaded ? state.searchQuery : '';
              if (query.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.clear, size: 18, color: AppTheme.textSecondary),
                onPressed: () => _cubit.onSearchChanged(''),
              );
            },
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        onChanged: _cubit.onSearchChanged,
        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
        decoration: InputDecoration(
          hintText: 'بحث بالمنتج أو الوصف...',
          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontFamily: 'Cairo'),
          prefixIcon: const Icon(Icons.search, size: 20, color: Colors.black54),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          suffixIcon: BlocBuilder<TransferCubit, TransferState>(
            buildWhen: (prev, curr) => curr is TransferLoaded,
            builder: (context, state) {
              final query = state is TransferLoaded ? state.searchQuery : '';
              if (query.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.clear, size: 18, color: Colors.black54),
                onPressed: () => _cubit.onSearchChanged(''),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDateFilter(bool isDark) {
    return BlocBuilder<TransferCubit, TransferState>(
      buildWhen: (prev, curr) => curr is TransferLoaded,
      builder: (context, state) {
        final fromDate = state is TransferLoaded ? state.fromDate : null;
        final toDate = state is TransferLoaded ? state.toDate : null;
        final hasFilter = fromDate != null || toDate != null;
        return Row(
          children: [
            Expanded(
              child: _buildDateField(
                label: 'من تاريخ',
                date: fromDate,
                isDark: isDark,
                onSelect: (d) => _cubit.onFromDateChanged(d),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDateField(
                label: 'إلى تاريخ',
                date: toDate,
                isDark: isDark,
                onSelect: (d) => _cubit.onToDateChanged(d),
              ),
            ),
            if (hasFilter) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.clear, size: 18, color: AppTheme.danger),
                tooltip: 'مسح الفلتر',
                onPressed: () => _cubit.clearDateFilter(),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime? date,
    required ValueChanged<DateTime> onSelect,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
          locale: const Locale('ar', 'EG'),
        );
        if (picked != null) onSelect(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: isDark ? AppTheme.textSecondary : Colors.black,
            fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
            fontFamily: 'Cairo',
            fontSize: 12,
          ),
          prefixIcon: Icon(Icons.calendar_today, size: 18, color: isDark ? AppTheme.textSecondary : Colors.black54),
          suffixIcon: date != null
              ? GestureDetector(
                  onTap: () => onSelect(DateTime.now()),
                  child: Icon(Icons.close, size: 16, color: isDark ? AppTheme.textSecondary : Colors.black54),
                )
              : null,
          filled: true,
          fillColor: isDark ? const Color(0x3805192D) : Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1), width: 1.2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1), width: 1.2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        child: Text(
          date != null
              ? '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
              : 'اختر التاريخ',
          style: TextStyle(
            color: isDark ? (date != null ? Colors.white : AppTheme.textSecondary) : Colors.black,
            fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
            fontFamily: 'Cairo',
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildTable(bool isDark) {
    return Container(
      decoration: isDark
          ? AppTheme.glassCard()
          : BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BlocConsumer<TransferCubit, TransferState>(
          listener: (context, state) {
            if (state is TransferError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message)),
              );
            }
          },
          builder: (context, state) {
            if (state is TransferLoading) return const Center(child: CircularProgressIndicator());
            if (state is TransferLoaded) {
              _lastLoadedState = state;
              if (state.transfers.isEmpty) return _buildEmptyState(state.searchQuery, isDark);
              return _buildDataTable(state, isDark);
            }
            if (_lastLoadedState != null) {
              if (_lastLoadedState!.transfers.isEmpty) return _buildEmptyState(_lastLoadedState!.searchQuery, isDark);
              return _buildDataTable(_lastLoadedState!, isDark);
            }
            return const Center(child: CircularProgressIndicator());
          },
        ),
      ),
    );
  }

  Widget _buildDataTable(TransferLoaded state, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth > 1050 ? constraints.maxWidth : 1050.0;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              children: [
                _buildTableHeader(isDark),
                Divider(height: 1, color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0)),
                Expanded(
                  child: ListView.separated(
                    itemCount: state.transfers.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFE2E8F0),
                    ),
                    itemBuilder: (context, index) {
                      return _buildTableRow(context, state.transfers[index], index, state.stationNames, isDark);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTableHeader(bool isDark) {
    final labelStyle = TextStyle(
      color: isDark ? AppTheme.textSecondary : Colors.black,
      fontWeight: FontWeight.bold,
      fontFamily: 'Cairo',
      fontSize: 13,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: isDark ? const Color(0x1A00E5FF) : const Color(0xFFF1F5F9),
      child: Row(
        children: [
          Expanded(flex: 1, child: Text('#', style: labelStyle)),
          Expanded(flex: 2, child: Text('من', style: labelStyle)),
          Expanded(flex: 2, child: Text('إلى', style: labelStyle)),
          Expanded(flex: 3, child: Text('المنتج', style: labelStyle)),
          Expanded(flex: 1, child: Text('الكمية', style: labelStyle, textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text('القيمة الإجمالية', style: labelStyle, textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text('التاريخ', style: labelStyle)),
          Expanded(flex: 3, child: Text('القيد والإجراءات', style: labelStyle, textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildTableRow(BuildContext context, StockTransferModel transfer, int index, Map<int, String> stationNames, bool isDark) {
    final isEven = index % 2 == 0;
    final fromName = stationNames[transfer.fromStationId] ?? 'محطة #${transfer.fromStationId}';
    final toName = stationNames[transfer.toStationId] ?? 'محطة #${transfer.toStationId}';
    final totalVal = transfer.totalCost ?? 0.0;
    final currency = transfer.currency ?? 'EGP';

    return Container(
      color: isEven
          ? (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white)
          : (isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: isDark ? AppTheme.textSecondary : Colors.black,
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.danger.withValues(alpha: 0.1) : const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(6),
                border: isDark ? null : Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Text(
                fromName,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? AppTheme.danger : const Color(0xFFDC2626),
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.success.withValues(alpha: 0.1) : const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(6),
                border: isDark ? null : Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: Text(
                toName,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? AppTheme.success : const Color(0xFF16A34A),
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  transfer.productName,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (transfer.productCode.isNotEmpty)
                  Text(
                    transfer.productCode,
                    style: TextStyle(
                      color: isDark ? AppTheme.textSecondary : Colors.black87,
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              transfer.quantity.toStringAsFixed(0),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark ? AppTheme.accent : Colors.black,
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  totalVal > 0 ? '${totalVal.toStringAsFixed(2)} $currency' : '-',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: totalVal > 0 ? (isDark ? AppTheme.warning : Colors.black) : (isDark ? AppTheme.textSecondary : Colors.black54),
                    fontFamily: 'Cairo',
                  ),
                  textAlign: TextAlign.center,
                ),
                if (transfer.unitCost != null && transfer.unitCost! > 0)
                  Text(
                    '(@${transfer.unitCost!.toStringAsFixed(2)})',
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? AppTheme.textSecondary : Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatDate(transfer.createdAt),
              style: TextStyle(
                color: isDark ? AppTheme.textSecondary : Colors.black,
                fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                fontFamily: 'Cairo',
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  InkWell(
                    onTap: () {
                      JournalEntryNavigationService.openForWarehouseTransfer(
                        context,
                        transferId: transfer.id,
                        journalEntryId: transfer.journalEntryId,
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.cyan.withValues(alpha: 0.12) : const Color(0xFFE0F2FE),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? AppTheme.cyan.withValues(alpha: 0.3) : const Color(0xFFBAE6FD),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long_outlined, size: 14, color: isDark ? AppTheme.cyan : const Color(0xFF0284C7)),
                          const SizedBox(width: 4),
                          Text(
                            'عرض القيد',
                            style: TextStyle(
                              color: isDark ? AppTheme.cyan : const Color(0xFF0284C7),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateStr;
    }
  }

  Widget _buildEmptyState(String searchQuery, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.swap_horiz, size: 72, color: AppTheme.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            searchQuery.isEmpty ? 'لا توجد تحويلات بعد' : 'لا توجد نتائج للبحث',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? AppTheme.textSecondary : Colors.black,
              fontFamily: 'Cairo',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            searchQuery.isEmpty ? 'ابدأ بتحويل جديد من زر "تحويل جديد"' : 'جرب كلمة بحث مختلفة',
            style: TextStyle(
              color: isDark ? AppTheme.textSecondary : Colors.black,
              fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
              fontFamily: 'Cairo',
              fontSize: 13,
            ),
          ),
          if (searchQuery.isEmpty) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('تحويل جديد', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
              ),
              onPressed: () => _showTransferDialog(),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showTransferDialog() async {
    await _cubit.prepareTransferForm();
    if (!mounted) return;
    _showTransferFormDialog();
  }

  void _showTransferFormDialog() {
    showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: _cubit,
        child: const _TransferFormDialog(),
      ),
    );
  }

  Future<void> _exportExcel() async {
    final state = _cubit.state;
    if (state is! TransferLoaded) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري إنشاء ملف Excel...'), backgroundColor: AppTheme.primary, duration: Duration(seconds: 2)),
    );
    try {
      await TransferExportService.exportExcel(
        transfers: state.transfers,
        stationNames: state.stationNames,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم التصدير بنجاح'), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في التصدير: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }
}

class _TransferFormDialog extends StatefulWidget {
  const _TransferFormDialog();

  @override
  State<_TransferFormDialog> createState() => _TransferFormDialogState();
}

class _TransferFormDialogState extends State<_TransferFormDialog> {
  int? _selectedFrom;
  int? _selectedTo;
  int? _selectedProductIdx;
  String _productSearch = '';
  bool _showProductDropdown = false;
  String _productTypeFilter = 'crops'; // 'crops', 'materials'

  Widget _buildFilterChip(String label, String value, bool isDark) {
    final isSelected = _productTypeFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _productTypeFilter = value;
          _selectedProductIdx = null;
          _showProductDropdown = _productSearch.isNotEmpty;
        });
        context.read<TransferCubit>().selectProduct('', '');
        context.read<TransferCubit>().productSearchController.clear();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? AppTheme.primary.withValues(alpha: 0.2) : const Color(0xFFE0F2FE))
              : (isDark ? const Color(0x3805192D) : Colors.white),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                : (isDark ? AppTheme.textSecondary : Colors.black),
            fontFamily: 'Cairo',
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      backgroundColor: isDark ? const Color(0xCC05192D) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1),
          width: 1.2,
        ),
      ),
      child: BlocBuilder<TransferCubit, TransferState>(
        builder: (context, state) {
          final formState = state is TransferFormState ? state : const TransferFormState();
          final allStations = formState.allStations;
          final sourceProductsRaw = formState.sourceProducts;
          final sourceProducts = sourceProductsRaw.where((p) {
            final isMaterial = p.productName.contains('مادة تعبئة') || p.productName.contains('مادة تعبئه');
            if (_productTypeFilter == 'crops') return !isMaterial;
            if (_productTypeFilter == 'materials') return isMaterial;
            return true;
          }).toList();
          
          final cubit = context.read<TransferCubit>();

          final destStations = _selectedFrom != null
              ? allStations.where((s) => int.parse(s.id ?? '0') != _selectedFrom).toList()
              : allStations;

          final sourceStations = _selectedTo != null
              ? allStations.where((s) => int.parse(s.id ?? '0') != _selectedTo).toList()
              : allStations;

          return Container(
            width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width * 0.92 : 520,
            padding: EdgeInsets.all(MediaQuery.of(context).size.width < 600 ? 16 : 24),
            child: Form(
              key: cubit.formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.success.withValues(alpha: 0.12) : const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(12),
                            border: isDark ? null : Border.all(color: const Color(0xFF86EFAC)),
                          ),
                          child: Icon(Icons.swap_horiz, color: isDark ? AppTheme.success : const Color(0xFF16A34A), size: 24),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'تحويل بين المخازن',
                          style: TextStyle(
                            fontSize: MediaQuery.of(context).size.width < 600 ? 16 : 20,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                            fontFamily: 'Cairo',
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(Icons.close, color: isDark ? Colors.white70 : Colors.black),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    if (allStations.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.warning_amber_outlined, size: 18, color: AppTheme.warning),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'لا توجد مخازن. قم بإضافة مخزن أولاً من صفحة "المخازن".',
                                style: TextStyle(color: AppTheme.warning, fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      DropdownButtonFormField<int>(
                        value: _selectedFrom,
                        dropdownColor: isDark ? const Color(0xFF0A2A4A) : Colors.white,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          labelText: 'من مخزن *',
                          labelStyle: TextStyle(
                            color: isDark ? AppTheme.textSecondary : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                          filled: true,
                          fillColor: isDark ? const Color(0x3805192D) : Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                          ),
                          prefixIcon: Icon(Icons.upload_outlined, size: 18, color: isDark ? null : Colors.black54),
                        ),
                        items: sourceStations.map((s) => DropdownMenuItem<int>(
                          value: int.parse(s.id ?? '0'),
                          child: Row(
                            children: [
                              Text(
                                '${s.name} (${s.code})',
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: (s.isMain ? AppTheme.primary : AppTheme.accent).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  s.isMain ? 'رئيسي' : 'فرعي',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: s.isMain ? AppTheme.primary : AppTheme.accent,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )).toList(),
                        onChanged: (v) {
                          setState(() {
                            _selectedFrom = v;
                            _selectedTo = null;
                            _selectedProductIdx = null;
                            _productSearch = '';
                            _showProductDropdown = false;
                          });
                          cubit.setFromStation(v);
                          cubit.productSearchController.clear();
                        },
                        validator: (v) => v == null ? 'اختر مخزن المصدر' : null,
                      ),
                      const SizedBox(height: 12),

                      Center(
                        child: Icon(
                          Icons.arrow_downward,
                          color: isDark ? AppTheme.success.withValues(alpha: 0.5) : const Color(0xFF0284C7),
                          size: 20,
                        ),
                      ),
                      const SizedBox(height: 12),

                      DropdownButtonFormField<int>(
                        value: _selectedTo,
                        dropdownColor: isDark ? const Color(0xFF0A2A4A) : Colors.white,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          labelText: 'إلى مخزن *',
                          labelStyle: TextStyle(
                            color: isDark ? AppTheme.textSecondary : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                          filled: true,
                          fillColor: isDark ? const Color(0x3805192D) : Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                          ),
                          prefixIcon: Icon(Icons.download_outlined, size: 18, color: isDark ? null : Colors.black54),
                        ),
                        items: destStations.map((s) => DropdownMenuItem<int>(
                          value: int.parse(s.id ?? '0'),
                          child: Row(
                            children: [
                              Text(
                                '${s.name} (${s.code})',
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: (s.isMain ? AppTheme.primary : AppTheme.accent).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  s.isMain ? 'رئيسي' : 'فرعي',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: s.isMain ? AppTheme.primary : AppTheme.accent,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )).toList(),
                        onChanged: (v) {
                          setState(() => _selectedTo = v);
                          context.read<TransferCubit>().setToStation(v);
                        },
                        validator: (v) {
                          if (v == null) return 'اختر مخزن الوجهة';
                          if (v == _selectedFrom) return 'لا يمكن التحويل لنفس المخزن';
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      if (_selectedFrom == null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.accent.withValues(alpha: 0.08) : const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark ? AppTheme.accent.withValues(alpha: 0.2) : const Color(0xFF86EFAC),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 18, color: isDark ? AppTheme.accent : const Color(0xFF16A34A)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'اختر مخزن المصدر أولاً لعرض المنتجات المتاحة',
                                  style: TextStyle(
                                    color: isDark ? AppTheme.accent : Colors.black,
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        Text(
                          'نوع المنتج',
                          style: TextStyle(
                            color: isDark ? AppTheme.textSecondary : Colors.black,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(child: _buildFilterChip('محاصيل', 'crops', isDark)),
                            const SizedBox(width: 8),
                            Expanded(child: _buildFilterChip('مواد تعبئة', 'materials', isDark)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'المنتج *',
                          style: TextStyle(
                            color: isDark ? AppTheme.textSecondary : Colors.black,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0x3805192D) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1),
                              width: 1.2,
                            ),
                          ),
                          child: Column(
                            children: [
                              TextFormField(
                                controller: cubit.productSearchController,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'ابحث بالاسم أو الكود...',
                                  hintStyle: TextStyle(
                                    color: isDark ? AppTheme.textSecondary.withValues(alpha: 0.5) : const Color(0xFF94A3B8),
                                  ),
                                  prefixIcon: Icon(Icons.search, size: 18, color: isDark ? null : Colors.black54),
                                  suffixIcon: _selectedProductIdx != null
                                      ? IconButton(
                                          icon: Icon(Icons.close, size: 16, color: isDark ? null : Colors.black54),
                                          onPressed: () {
                                            setState(() {
                                              _selectedProductIdx = null;
                                              _productSearch = '';
                                              _showProductDropdown = false;
                                            });
                                            cubit.selectProduct('', '');
                                            cubit.productSearchController.clear();
                                          },
                                        )
                                      : null,
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                ),
                                onChanged: (v) {
                                  setState(() {
                                    _productSearch = v;
                                    _showProductDropdown = v.isNotEmpty && _selectedProductIdx == null;
                                  });
                                  cubit.onProductSearchChanged(v);
                                },
                                onTap: () {
                                  if (_selectedProductIdx == null) {
                                    setState(() => _showProductDropdown = _productSearch.isNotEmpty);
                                  }
                                },
                              ),
                              if (_selectedProductIdx != null && _selectedProductIdx! < sourceProducts.length)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isDark ? AppTheme.success.withValues(alpha: 0.08) : const Color(0xFFF0FDF4),
                                    border: Border(
                                      top: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.check_circle, color: isDark ? AppTheme.success : const Color(0xFF16A34A), size: 16),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              sourceProducts[_selectedProductIdx!].productName,
                                              style: TextStyle(
                                                color: isDark ? AppTheme.textPrimary : Colors.black,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'Cairo',
                                                fontSize: 13,
                                              ),
                                            ),
                                            if (sourceProducts[_selectedProductIdx!].productCode.isNotEmpty)
                                              Text(
                                                sourceProducts[_selectedProductIdx!].productCode,
                                                style: TextStyle(
                                                  color: isDark ? AppTheme.textSecondary : Colors.black87,
                                                  fontFamily: 'Cairo',
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isDark ? AppTheme.accent.withValues(alpha: 0.1) : const Color(0xFFDCFCE7),
                                          borderRadius: BorderRadius.circular(6),
                                          border: isDark ? null : Border.all(color: const Color(0xFF86EFAC)),
                                        ),
                                        child: Text(
                                          () {
                                            final p = sourceProducts[_selectedProductIdx!];
                                            final isMaterial = p.productName.contains('مادة تعبئة') || p.productName.contains('مادة تعبئه');
                                            final formattedQty = p.quantity.toStringAsFixed(p.quantity % 1 == 0 ? 0 : 2);
                                            final unitStr = isMaterial ? '' : (p.unit == 'carton' ? ' كرتونة' : (p.unit == 'kg' ? ' كجم' : (p.unit.isNotEmpty ? ' ${p.unit}' : '')));
                                            return 'المتوفر: $formattedQty$unitStr';
                                          }(),
                                          style: TextStyle(
                                            color: isDark ? AppTheme.accent : const Color(0xFF16A34A),
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (_showProductDropdown && sourceProducts.isNotEmpty)
                                Container(
                                  constraints: const BoxConstraints(maxHeight: 200),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      top: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                                    ),
                                  ),
                                  child: ListView.separated(
                                    shrinkWrap: true,
                                    itemCount: sourceProducts.length,
                                    separatorBuilder: (_, __) => Divider(
                                      height: 1,
                                      color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFE2E8F0),
                                    ),
                                    itemBuilder: (context, index) {
                                      final p = sourceProducts[index];
                                      final isMaterial = p.productName.contains('مادة تعبئة') || p.productName.contains('مادة تعبئه');
                                      final formattedQty = p.quantity.toStringAsFixed(p.quantity % 1 == 0 ? 0 : 2);
                                      final unitStr = isMaterial ? '' : (p.unit == 'carton' ? ' كرتونة' : (p.unit == 'kg' ? ' كجم' : (p.unit.isNotEmpty ? ' ${p.unit}' : '')));
                                      return ListTile(
                                        dense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                        leading: Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: isDark ? AppTheme.accent.withValues(alpha: 0.1) : const Color(0xFFE0F2FE),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Icon(Icons.inventory_2_outlined, color: isDark ? AppTheme.accent : const Color(0xFF0284C7), size: 16),
                                        ),
                                        title: Text(
                                          p.productName,
                                          style: TextStyle(
                                            color: isDark ? Colors.white : Colors.black,
                                            fontFamily: 'Cairo',
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        subtitle: p.productCode.isNotEmpty
                                            ? Text(
                                                p.productCode,
                                                style: TextStyle(
                                                  color: isDark ? AppTheme.textSecondary : Colors.black87,
                                                  fontFamily: 'Cairo',
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              )
                                            : null,
                                        trailing: Text(
                                          '$formattedQty$unitStr',
                                          style: TextStyle(
                                            color: isDark ? AppTheme.success : const Color(0xFF16A34A),
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo',
                                            fontSize: 13,
                                          ),
                                        ),
                                        onTap: () {
                                          setState(() {
                                            _selectedProductIdx = index;
                                            _showProductDropdown = false;
                                            _productSearch = '';
                                          });
                                          cubit.selectProduct(p.productName, p.productCode);
                                          cubit.productSearchController.text = p.productName;
                                        },
                                      );
                                    },
                                  ),
                                ),
                              if (_showProductDropdown && sourceProducts.isEmpty && _productSearch.isNotEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      top: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                                    ),
                                  ),
                                  child: Text(
                                    'لا توجد منتجات تطابق البحث',
                                    style: TextStyle(
                                      color: isDark ? AppTheme.textSecondary : Colors.black,
                                      fontFamily: 'Cairo',
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: cubit.quantityController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: 'الكمية *',
                          labelStyle: TextStyle(
                            color: isDark ? AppTheme.textSecondary : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                          filled: true,
                          fillColor: isDark ? const Color(0x3805192D) : Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                          ),
                        ),
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'الكمية مطلوبة';
                          final qty = double.tryParse(v.trim());
                          if (qty == null || qty <= 0) return 'كمية غير صالحة';
                          if (_selectedProductIdx != null && sourceProducts.isNotEmpty) {
                            final p = sourceProducts[_selectedProductIdx!];
                            final isMaterial = p.productName.contains('مادة تعبئة') || p.productName.contains('مادة تعبئه');
                            final formattedQty = p.quantity.toStringAsFixed(p.quantity % 1 == 0 ? 0 : 2);
                            final unitStr = isMaterial ? '' : (p.unit == 'carton' ? ' كرتونة' : (p.unit == 'kg' ? ' كجم' : (p.unit.isNotEmpty ? ' ${p.unit}' : '')));
                            if (qty > p.quantity) return 'الكمية أكبر من المتوفر ($formattedQty$unitStr)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: cubit.notesController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'ملاحظات (اختياري)',
                          labelStyle: TextStyle(
                            color: isDark ? AppTheme.textSecondary : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                          filled: true,
                          fillColor: isDark ? const Color(0x3805192D) : Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                          ),
                        ),
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 24),

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isDark ? AppTheme.textSecondary : Colors.black,
                                side: BorderSide(
                                  color: isDark ? Colors.white.withValues(alpha: 0.15) : const Color(0xFFCBD5E1),
                                  width: 1.2,
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: formState.isSaving ? null : () => Navigator.pop(context),
                              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0284C7),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: formState.isSaving ? null : () async {
                                final success = await cubit.saveTransfer('current_user');
                                if (!mounted) return;
                                if (success) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Row(
                                        children: [
                                          Icon(Icons.check_circle, color: Colors.white, size: 20),
                                          SizedBox(width: 10),
                                          Text('تم التحويل بنجاح', style: TextStyle(fontFamily: 'Cairo', fontSize: 14)),
                                        ],
                                      ),
                                      backgroundColor: AppTheme.success,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text('فشل التحويل - تأكد من صحة البيانات', style: TextStyle(fontFamily: 'Cairo')),
                                      backgroundColor: AppTheme.danger,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  );
                                }
                              },
                              icon: formState.isSaving
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.swap_horiz, size: 18),
                              label: Text(
                                formState.isSaving
                                    ? 'جاري الحفظ...'
                                    : 'تنفيذ التحويل',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}