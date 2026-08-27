import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/data_change_event_bus.dart';
import '../../core/theme.dart';
import '../../data/models/stock_transfer_model.dart';
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
    return BlocProvider.value(
      value: _cubit,
      child: Scaffold(
        body: Padding(
          padding: EdgeInsets.all(MediaQuery.of(context).size.width < 600 ? 12 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              _buildSearchBar(),
              const SizedBox(height: 12),
              _buildDateFilter(),
              const SizedBox(height: 16),
              Expanded(child: _buildTable()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Row(
      children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: AppTheme.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.swap_horiz, color: AppTheme.success, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('تحويل بين المخازن', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: isMobile ? 18 : 28, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
              BlocBuilder<TransferCubit, TransferState>(
                buildWhen: (prev, curr) => curr is TransferLoaded,
                builder: (context, state) {
                  final count = state is TransferLoaded ? state.transfers.length : 0;
                  return Text('$count تحويل', style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13));
                },
              ),
            ],
          ),
        ),
        if (!isMobile) ...[
          IconButton(
            icon: const Icon(Icons.refresh_outlined), tooltip: 'تحديث',
            onPressed: () => _cubit.loadAll(reset: true),
          ),
          // IconButton(
          //   icon: const Icon(Icons.picture_as_pdf_outlined, color: AppTheme.danger, size: 20),
          //   tooltip: 'تصدير PDF',
          //   onPressed: _exportPdf,
          // ),
          IconButton(
            icon: const Icon(Icons.table_chart_outlined, color: AppTheme.success, size: 20),
            tooltip: 'تصدير Excel',
            onPressed: _exportExcel,
          ),
          const SizedBox(width: 8),
        ],
        ElevatedButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: Text(isMobile ? '+' : 'تحويل جديد'),
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 10),
          ),
          onPressed: () => _showTransferDialog(),
        ),
        if (isMobile) ...[
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
            onSelected: (v) {
              if (v == 'refresh') _cubit.loadAll(reset: true);
              else if (v == 'pdf') _exportPdf();
              else if (v == 'excel') _exportExcel();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'refresh', child: Text('تحديث', style: TextStyle(fontFamily: 'Cairo'))),
              const PopupMenuItem(value: 'pdf', child: Text('تصدير PDF', style: TextStyle(fontFamily: 'Cairo'))),
              const PopupMenuItem(value: 'excel', child: Text('تصدير Excel', style: TextStyle(fontFamily: 'Cairo'))),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      onChanged: _cubit.onSearchChanged,
      decoration: InputDecoration(
        hintText: 'بحث بالمنتج أو الوصف...',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: BlocBuilder<TransferCubit, TransferState>(
          buildWhen: (prev, curr) => curr is TransferLoaded,
          builder: (context, state) {
            final query = state is TransferLoaded ? state.searchQuery : '';
            if (query.isEmpty) return const SizedBox.shrink();
            return IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => _cubit.onSearchChanged(''));
          },
        ),
      ),
    );
  }

  Widget _buildDateFilter() {
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
                onSelect: (d) => _cubit.onFromDateChanged(d),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDateField(
                label: 'إلى تاريخ',
                date: toDate,
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
          labelStyle: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 12),
          prefixIcon: const Icon(Icons.calendar_today, size: 18),
          suffixIcon: date != null
              ? GestureDetector(
                  onTap: () => onSelect(DateTime.now()),
                  child: const Icon(Icons.close, size: 16, color: AppTheme.textSecondary),
                )
              : null,
          filled: true,
          fillColor: const Color(0x3805192D),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.glassBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.glassBorder),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        child: Text(
          date != null
              ? '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
              : 'اختر التاريخ',
          style: TextStyle(
            color: date != null ? Colors.white : AppTheme.textSecondary,
            fontFamily: 'Cairo',
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildTable() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: AppTheme.glassCard(),
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
                if (state.transfers.isEmpty) return _buildEmptyState(state.searchQuery);
                return _buildDataTable(state);
              }
              if (_lastLoadedState != null) {
                if (_lastLoadedState!.transfers.isEmpty) return _buildEmptyState(_lastLoadedState!.searchQuery);
                return _buildDataTable(_lastLoadedState!);
              }
              return const Center(child: CircularProgressIndicator());
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDataTable(TransferLoaded state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: constraints.maxWidth,
              maxWidth: constraints.maxWidth > 800 ? constraints.maxWidth : 800,
            ),
            child: Column(
              children: [
                _buildTableHeader(),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: state.transfers.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (context, index) {
                      return _buildTableRow(context, state.transfers[index], index, state.stationNames);
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

  static const _labelStyle = TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 13);

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0x1A00E5FF),
      child: const Row(
        children: [
          Expanded(flex: 1, child: Text('#', style: _labelStyle)),
          Expanded(flex: 2, child: Text('من', style: _labelStyle)),
          Expanded(flex: 2, child: Text('إلى', style: _labelStyle)),
          Expanded(flex: 3, child: Text('المنتج', style: _labelStyle)),
          Expanded(flex: 1, child: Text('الكمية', style: _labelStyle, textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text('التاريخ', style: _labelStyle)),
        ],
      ),
    );
  }

  Widget _buildTableRow(BuildContext context, StockTransferModel transfer, int index, Map<int, String> stationNames) {
    final isEven = index % 2 == 0;
    final fromName = stationNames[transfer.fromStationId] ?? 'محطة #${transfer.fromStationId}';
    final toName = stationNames[transfer.toStationId] ?? 'محطة #${transfer.toStationId}';

    return Container(
      color: isEven ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(flex: 1, child: Text('${index + 1}', style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13))),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                fromName,
                style: const TextStyle(fontSize: 11, color: AppTheme.danger, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                toName,
                style: const TextStyle(fontSize: 11, color: AppTheme.success, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
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
                Text(transfer.productName, style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13), overflow: TextOverflow.ellipsis),
                if (transfer.productCode.isNotEmpty)
                  Text(transfer.productCode, style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 11), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              transfer.quantity.toStringAsFixed(0),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.accent, fontFamily: 'Cairo'),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _formatDate(transfer.createdAt),
              style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 12),
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

  Widget _buildEmptyState(String searchQuery) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.swap_horiz, size: 72, color: AppTheme.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            searchQuery.isEmpty ? 'لا توجد تحويلات بعد' : 'لا توجد نتائج للبحث',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, fontFamily: 'Cairo'),
          ),
          const SizedBox(height: 8),
          Text(
            searchQuery.isEmpty ? 'ابدأ بتحويل جديد من زر "تحويل جديد"' : 'جرب كلمة بحث مختلفة',
            style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
          ),
        ],
      ),
    );
  }

  bool _hasActiveFilters(TransferLoaded state) {
    return state.searchQuery.isNotEmpty || state.fromDate != null || state.toDate != null;
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

  void _showDeleteConfirm(BuildContext context, StockTransferModel transfer) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF05192D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppTheme.glassBorder)),
        title: const Text('تأكيد الحذف', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: const Text('هل أنت متأكد من حذف هذا التحويل؟', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(dialogContext);
              _cubit.deleteTransfer(transfer.id!);
            },
            child: const Text('حذف', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  Future<void> _exportPdf() async {
    final state = _cubit.state;
    if (state is! TransferLoaded) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري إنشاء ملف PDF...'), backgroundColor: AppTheme.primary, duration: Duration(seconds: 2)),
    );
    try {
      await TransferExportService.exportPdf(
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

  Widget _buildFilterChip(String label, String value) {
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
          color: isSelected ? AppTheme.primary.withValues(alpha: 0.2) : const Color(0x3805192D),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.glassBorder),
        ),
        child: Text(label, style: TextStyle(color: isSelected ? AppTheme.primary : AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      clipBehavior: Clip.antiAlias,
      backgroundColor: const Color(0xCC05192D),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppTheme.glassBorder),
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
                            color: AppTheme.success.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.swap_horiz, color: AppTheme.success, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Text('تحويل بين المخازن', style: TextStyle(fontSize: MediaQuery.of(context).size.width < 600 ? 16 : 20, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
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
                        child:const Row(
                          children: [
                             Icon(Icons.warning_amber_outlined, size: 18, color: AppTheme.warning),
                             SizedBox(width: 8),
                             Expanded(
                              child: Text('لا توجد مخازن. قم بإضافة مخزن أولاً من صفحة "المخازن".',
                                  style: TextStyle(color: AppTheme.warning, fontFamily: 'Cairo', fontSize: 12)),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      DropdownButtonFormField<int>(
                        value: _selectedFrom,
                        dropdownColor: const Color(0xFF0A2A4A),
                        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'من مخزن *',
                          labelStyle: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'),
                          filled: true,
                          fillColor: const Color(0x3805192D),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.glassBorder)),
                          prefixIcon: const Icon(Icons.upload_outlined, size: 18),
                        ),
                        items: sourceStations.map((s) => DropdownMenuItem<int>(
                          value: int.parse(s.id ?? '0'),
                          child: Row(
                            children: [
                              Text('${s.name} (${s.code})'),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: (s.isMain ? AppTheme.primary : AppTheme.accent).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(s.isMain ? 'رئيسي' : 'فرعي',
                                  style: TextStyle(fontSize: 9, color: s.isMain ? AppTheme.primary : AppTheme.accent, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
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
                        child: Icon(Icons.arrow_downward, color: AppTheme.success.withValues(alpha: 0.5), size: 20),
                      ),
                      const SizedBox(height: 12),

                      DropdownButtonFormField<int>(
                        value: _selectedTo,
                        dropdownColor: const Color(0xFF0A2A4A),
                        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'إلى مخزن *',
                          labelStyle: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'),
                          filled: true,
                          fillColor: const Color(0x3805192D),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.glassBorder)),
                          prefixIcon: const Icon(Icons.download_outlined, size: 18),
                        ),
                        items: destStations.map((s) => DropdownMenuItem<int>(
                          value: int.parse(s.id ?? '0'),
                          child: Row(
                            children: [
                              Text('${s.name} (${s.code})'),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: (s.isMain ? AppTheme.primary : AppTheme.accent).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(s.isMain ? 'رئيسي' : 'فرعي',
                                  style: TextStyle(fontSize: 9, color: s.isMain ? AppTheme.primary : AppTheme.accent, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
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
                            color: AppTheme.accent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, size: 18, color: AppTheme.accent),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text('اختر مخزن المصدر أولاً لعرض المنتجات المتاحة',
                                    style: TextStyle(color: AppTheme.accent, fontFamily: 'Cairo', fontSize: 12)),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        const Text('نوع المنتج', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(child: _buildFilterChip('محاصيل', 'crops')),
                            const SizedBox(width: 8),
                            Expanded(child: _buildFilterChip('مواد تعبئة', 'materials')),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text('المنتج *', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo')),
                        const SizedBox(height: 6),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0x3805192D),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.glassBorder),
                          ),
                          child: Column(
                            children: [
                              TextFormField(
                                controller: cubit.productSearchController,
                                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'ابحث بالاسم أو الكود...',
                                  hintStyle: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.5)),
                                  prefixIcon: const Icon(Icons.search, size: 18),
                                  suffixIcon: _selectedProductIdx != null
                                      ? IconButton(
                                          icon: const Icon(Icons.close, size: 16),
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
                                    color: AppTheme.success.withValues(alpha: 0.08),
                                    border: const Border(top: BorderSide(color: AppTheme.glassBorder)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.check_circle, color: AppTheme.success, size: 16),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              sourceProducts[_selectedProductIdx!].productName,
                                              style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13),
                                            ),
                                            if (sourceProducts[_selectedProductIdx!].productCode.isNotEmpty)
                                              Text(
                                                sourceProducts[_selectedProductIdx!].productCode,
                                                style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 11),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: AppTheme.accent.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          () {
                                            final p = sourceProducts[_selectedProductIdx!];
                                            final isMaterial = p.productName.contains('مادة تعبئة') || p.productName.contains('مادة تعبئه');
                                            final formattedQty = p.quantity.toStringAsFixed(p.quantity % 1 == 0 ? 0 : 2);
                                            final unitStr = isMaterial ? '' : (p.unit == 'carton' ? ' كرتونة' : (p.unit == 'kg' ? ' كجم' : (p.unit.isNotEmpty ? ' ${p.unit}' : '')));
                                            return 'المتوفر: $formattedQty$unitStr';
                                          }(),
                                          style: const TextStyle(color: AppTheme.accent, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (_showProductDropdown && sourceProducts.isNotEmpty)
                                Container(
                                  constraints: const BoxConstraints(maxHeight: 200),
                                  decoration:const BoxDecoration(
                                    border: Border(top: BorderSide(color: AppTheme.glassBorder)),
                                  ),
                                  child: ListView.separated(
                                    shrinkWrap: true,
                                    itemCount: sourceProducts.length,
                                    separatorBuilder: (_, __) => Divider(height: 1, color: Colors.white.withValues(alpha: 0.05)),
                                    itemBuilder: (context, index) {
                                      final p = sourceProducts[index];
                                      final isMaterial = p.productName.contains('مادة تعبئة') || p.productName.contains('مادة تعبئه');
                                      final formattedQty = p.quantity.toStringAsFixed(p.quantity % 1 == 0 ? 0 : 2);
                                      final unitStr = isMaterial ? '' : (p.unit == 'carton' ? ' كرتونة' : (p.unit == 'kg' ? ' كجم' : (p.unit.isNotEmpty ? ' ${p.unit}' : '')));
                                      return ListTile(
                                        dense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                        leading: Container(
                                          width: 32, height: 32,
                                          decoration: BoxDecoration(
                                            color: AppTheme.accent.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Icon(Icons.inventory_2_outlined, color: AppTheme.accent, size: 16),
                                        ),
                                        title: Text(p.productName, style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13)),
                                        subtitle: p.productCode.isNotEmpty
                                            ? Text(p.productCode, style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 11))
                                            : null,
                                        trailing: Text(
                                          '$formattedQty$unitStr',
                                          style: const TextStyle(color: AppTheme.success, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13),
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
                                  decoration:const BoxDecoration(
                                    border: Border(top: BorderSide(color: AppTheme.glassBorder)),
                                  ),
                                  child: const Text(
                                    'لا توجد منتجات تطابق البحث',
                                    style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
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
                          labelStyle: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'),
                          filled: true,
                          fillColor: const Color(0x3805192D),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.glassBorder)),
                        ),
                        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
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
                          labelStyle: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'),
                          filled: true,
                          fillColor: const Color(0x3805192D),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.glassBorder)),
                        ),
                        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                      ),
                      const SizedBox(height: 24),

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.textSecondary,
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: formState.isSaving ? null : () => Navigator.pop(context),
                              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.success,
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
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}