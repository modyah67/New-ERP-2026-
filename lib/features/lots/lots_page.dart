import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../data/models/lot_model.dart';
import '../../data/dao/lot_dao.dart';
import '../../data/services/journal_entry_navigation_service.dart';
import 'lot_export_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../auth/auth_cubit.dart';

class LotsPage extends StatefulWidget {
  const LotsPage({super.key});

  @override
  State<LotsPage> createState() => _LotsPageState();
}

class _LotsPageState extends State<LotsPage> {
  final _dao = LotDao();
  final _searchController = TextEditingController();
  List<LotReceiptModel> _lots = [];
  List<LotReceiptModel> _filteredLots = [];
  bool _loading = true;
  String _searchQuery = '';
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _lots = await _dao.getAll();
    } catch (_) {}
    _applyFilter();
    if (mounted) setState(() => _loading = false);
  }

  void _applyFilter() {
    if (!mounted) return;
    final q = _searchQuery.toLowerCase();
    setState(() {
      _filteredLots = _lots.where((lot) {
        final productName = (lot.productName ?? '').toLowerCase();
        final supplierName = (lot.supplierName ?? '').toLowerCase();
        final matchesSearch = q.isEmpty || productName.contains(q) || supplierName.contains(q);
        bool matchesDate = true;
        if (_fromDate != null) {
          matchesDate = lot.receiptDate.isAfter(_fromDate!.subtract(const Duration(days: 1)));
        }
        if (matchesDate && _toDate != null) {
          matchesDate = lot.receiptDate.isBefore(_toDate!.add(const Duration(days: 1)));
        }
        return matchesSearch && matchesDate;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.background : AppTheme.lightBackground,
        body: Container(
          decoration: isDark
              ? const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [AppTheme.background, Color(0xFF0D2137), AppTheme.background],
                  ),
                )
              : null,
          child: Column(children: [
            _buildHeader(isDark),
            _buildSearchBar(isDark),
            Expanded(child: _buildBody(isDark)),
          ]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openForm(null),
          backgroundColor: AppTheme.primary,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('محصول جديد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 16, bottom: 16, left: 20, right: 20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0x3805192D) : Colors.white,
            border: Border(bottom: BorderSide(color: isDark ? AppTheme.glassBorder.withAlpha(50) : const Color(0xFFCBD5E1))),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.primary.withAlpha(30) : const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.eco_outlined, color: isDark ? AppTheme.primary : const Color(0xFF0284C7), size: 24),
            ),
            const SizedBox(width: 12),
            Text('شراء المحاصيل',
                style: TextStyle(
                    color: isDark ? AppTheme.textPrimary : Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo')),
            const SizedBox(width: 12),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: _exportAllPdf,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                        ),
                        child: const Icon(Icons.picture_as_pdf_outlined, color: AppTheme.danger, size: 20),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _exportAllExcel,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                        ),
                        child: const Icon(Icons.table_chart_outlined, color: AppTheme.success, size: 20),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => context.push('/lots/returns'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.danger.withAlpha(30) : const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? AppTheme.danger.withAlpha(80) : const Color(0xFFFCA5A5)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.assignment_return_outlined, color: isDark ? AppTheme.danger : const Color(0xFFB91C1C), size: 18),
                            const SizedBox(width: 6),
                            Text('المرتجعات',
                                style: TextStyle(
                                    color: isDark ? AppTheme.danger : const Color(0xFFB91C1C),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    fontFamily: 'Cairo')),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => context.go('/lots'),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                        ),
                        child: Icon(Icons.refresh_rounded, color: isDark ? AppTheme.textSecondary : Colors.black87, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: _searchController,
                onChanged: (v) {
                  _searchQuery = v;
                  _applyFilter();
                },
                style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                    fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'بحث باسم المنتج أو المورد...',
                  hintStyle: TextStyle(
                      color: isDark ? AppTheme.textSecondary.withAlpha(120) : Colors.black45,
                      fontFamily: 'Cairo',
                      fontSize: 12),
                  prefixIcon: Icon(Icons.search,
                      color: isDark ? AppTheme.textSecondary.withAlpha(120) : Colors.black54,
                      size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear,
                              size: 16,
                              color: isDark ? Colors.white70 : Colors.black87),
                          onPressed: () {
                            _searchController.clear();
                            _searchQuery = '';
                            _applyFilter();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: isDark ? const Color(0x3805192D) : Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: isDark ? AppTheme.glassBorder.withAlpha(40) : const Color(0xFFCBD5E1))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: isDark ? AppTheme.glassBorder.withAlpha(40) : const Color(0xFFCBD5E1))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: _pickFromDate,
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0x3805192D) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: _fromDate != null
                          ? AppTheme.primary.withAlpha(80)
                          : (isDark ? AppTheme.glassBorder.withAlpha(40) : const Color(0xFFCBD5E1))),
                ),
                child: Row(
                  children: [
                    Icon(Icons.date_range,
                        color: isDark ? AppTheme.textSecondary : Colors.black87,
                        size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _fromDate != null ? '${_fromDate!.day}/${_fromDate!.month}/${_fromDate!.year}' : 'من تاريخ',
                        style: TextStyle(
                          color: _fromDate != null
                              ? (isDark ? Colors.white : Colors.black)
                              : (isDark ? AppTheme.textSecondary : Colors.black54),
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_fromDate != null)
                      GestureDetector(
                        onTap: () {
                          setState(() => _fromDate = null);
                          _applyFilter();
                        },
                        child: Icon(Icons.close,
                            size: 14,
                            color: isDark ? AppTheme.textSecondary : Colors.black87),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: _pickToDate,
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0x3805192D) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: _toDate != null
                          ? AppTheme.primary.withAlpha(80)
                          : (isDark ? AppTheme.glassBorder.withAlpha(40) : const Color(0xFFCBD5E1))),
                ),
                child: Row(
                  children: [
                    Icon(Icons.date_range,
                        color: isDark ? AppTheme.textSecondary : Colors.black87,
                        size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _toDate != null ? '${_toDate!.day}/${_toDate!.month}/${_toDate!.year}' : 'إلى تاريخ',
                        style: TextStyle(
                          color: _toDate != null
                              ? (isDark ? Colors.white : Colors.black)
                              : (isDark ? AppTheme.textSecondary : Colors.black54),
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                          fontSize: 11,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_toDate != null)
                      GestureDetector(
                        onTap: () {
                          setState(() => _toDate = null);
                          _applyFilter();
                        },
                        child: Icon(Icons.close,
                            size: 14,
                            color: isDark ? AppTheme.textSecondary : Colors.black87),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFromDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppTheme.primary)),
        child: child!,
      ),
    );
    if (date != null) {
      setState(() => _fromDate = date);
      _applyFilter();
    }
  }

  Future<void> _pickToDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _toDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppTheme.primary)),
        child: child!,
      ),
    );
    if (date != null) {
      setState(() => _toDate = date);
      _applyFilter();
    }
  }

  Widget _buildBody(bool isDark) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_filteredLots.isEmpty) return _buildEmptyState(isDark);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: _filteredLots.map((lot) => _buildLotCard(lot, isDark)).toList(),
      ),
    );
  }

  Widget _buildLotCard(LotReceiptModel lot, bool isDark) {
    final productName = lot.productName ?? '—';
    final supplierName = lot.supplierName ?? '—';
    final title = 'شراء $productName من $supplierName';
    final isDraft = !lot.isConfirmed;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0x3805192D) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDraft
                    ? const Color(0x55FFB300) // amber border for drafts
                    : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                width: 1.2,
              ),
              boxShadow: [
                if (!isDark)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _openForm(lot),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        // Lot number badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.primary.withAlpha(15) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: isDark ? Colors.transparent : const Color(0xFFCBD5E1)),
                          ),
                          child: Text(lot.lotNumber,
                              style: TextStyle(
                                  color: isDark ? AppTheme.primary : Colors.black,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo')),
                        ),
                        const SizedBox(width: 8),
                        // Draft / Confirmed badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isDraft
                                ? const Color(0x33FFB300)
                                : const Color(0x3300C853),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isDraft ? Icons.edit_note : Icons.check_circle,
                                size: 12,
                                color: isDraft ? const Color(0xFFFFB300) : const Color(0xFF00C853),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isDraft ? 'مسودة' : 'مؤكد',
                                style: TextStyle(
                                  color: isDraft ? const Color(0xFFFFB300) : const Color(0xFF00C853),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(title,
                              style: TextStyle(
                                  color: isDark ? AppTheme.textPrimary : Colors.black,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo'),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Icon(Icons.shopping_bag_outlined,
                            color: isDark ? AppTheme.textSecondary : Colors.black87,
                            size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            lot.purchaseMode == 'carton'
                                ? '${lot.cartonCount} كرتونة'
                                : '${lot.grossWeightKg.toStringAsFixed(1)} كجم',
                            style: TextStyle(
                                color: isDark ? AppTheme.textPrimary : Colors.black,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // ── Confirm button (only for drafts) ──
                        if (isDraft) ...[
                          Tooltip(
                            message: 'تأكيد شراء المحصول',
                            child: GestureDetector(
                              onTap: () => _confirmLot(lot),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0x3300C853),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0x5500C853)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle_outline, color: Color(0xFF00C853), size: 16),
                                    SizedBox(width: 4),
                                    Text('تأكيد',
                                        style: TextStyle(
                                          color: Color(0xFF00C853),
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Cairo',
                                        )),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        if (!isDraft) ...[
                          _buildJournalEntriesDropdown(context, lot),
                          const SizedBox(width: 10),
                        ],
                        GestureDetector(
                          onTap: () async {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('جاري إنشاء PDF...'), duration: Duration(seconds: 2)),
                            );
                            await LotExportService.exportSinglePdf(lot);
                          },
                          child: const Icon(Icons.picture_as_pdf_outlined, color: AppTheme.danger, size: 18),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () async {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('جاري إنشاء Excel...'), duration: Duration(seconds: 2)),
                            );
                            await LotExportService.exportSingleExcel(lot);
                          },
                          child: const Icon(Icons.table_chart_outlined, color: AppTheme.success, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Text(lot.receiptDate.toString().split(' ')[0],
                            style: TextStyle(
                                color: isDark ? AppTheme.textSecondary : Colors.black,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo')),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.primary.withAlpha(15) : const Color(0xFFE0F2FE),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.eco_outlined,
                size: 48,
                color: isDark ? AppTheme.primary : const Color(0xFF0284C7)),
          ),
          const SizedBox(height: 20),
          Text('لا توجد محاصيل',
              style: TextStyle(
                  color: isDark ? AppTheme.textPrimary : Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
          const SizedBox(height: 8),
          Text('اضغط على "محصول جديد" لتسجيل أول شراء محصول',
              style: TextStyle(
                  color: isDark ? AppTheme.textSecondary.withAlpha(180) : Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
        ],
      ),
    );
  }

  Future<void> _openForm(LotReceiptModel? lot) async {
    // Block opening confirmed lots for editing
    if (lot != null && lot.isConfirmed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('المحصول مؤكد ولا يمكن تعديله.'),
            backgroundColor: Color(0xFFFFB300),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    debugPrint('===== LotsPage._openForm START =====');
    debugPrint('  input lot: id=${lot?.id}, lotNumber=${lot?.lotNumber}, gradingResults.length=${lot?.gradingResults.length ?? 0}');
    
    LotReceiptModel? lotToEdit = lot;
    if (lot != null && lot.id != null) {
      debugPrint('  calling _dao.getById(${lot.id})...');
      lotToEdit = await _dao.getById(lot.id!);
      debugPrint('  _dao.getById returned: id=${lotToEdit?.id}, lotNumber=${lotToEdit?.lotNumber}, gradingResults.length=${lotToEdit?.gradingResults.length ?? 0}');
      if (lotToEdit != null && lotToEdit.gradingResults.isNotEmpty) {
        for (final r in lotToEdit.gradingResults) {
          debugPrint('    grading: grade=${r.grade}, weightKg=${r.weightKg}');
        }
      }
    }
    
    debugPrint('  navigating with extra: lotToEdit (not lot)');
    final result = await context.push<bool>('/lots/new', extra: lotToEdit);
    debugPrint('  navigation returned result=$result');
    
    if (result == true) {
      debugPrint('  reload triggered');
      _load();
    }
    debugPrint('===== LotsPage._openForm END =====');
  }

  Future<void> _confirmLot(LotReceiptModel lot) async {
    if (lot.id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text(
          'تأكيد شراء المحصول',
          style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'هل تريد تأكيد شراء المحصول رقم ${lot.lotNumber}؟',
              style: const TextStyle(color: AppTheme.textPrimary, fontFamily: 'Cairo', fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x1AFFB300),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x33FFB300)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚠️ بعد التأكيد:',
                    style: TextStyle(color: Color(0xFFFFB300), fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 6),
                  Text('• سيتم إنشاء قيد محاسبي مزدوج وإضافته لدفتر الأستاذ العام', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 12)),
                  Text('• سيتم إضافة الكمية في المخزن (حساب المخزون 1030)', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 12)),
                  Text('• سيتم تسجيل المبلغ في حساب المورد الدائن', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 12)),
                  Text('• لن يمكن تعديل بيانات المحصول بعد ذلك', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 12)),
                  Text('• يمكن تعديل السعر فقط من زرار تعديل السعر', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00C853)),
            child: const Text('تأكيد', style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Show loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            SizedBox(width: 12),
            Text('جاري تأكيد شراء المحصول...', style: TextStyle(fontFamily: 'Cairo')),
          ],
        ),
        duration: Duration(seconds: 10),
      ),
    );

    try {
      await _dao.confirmLot(lot.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تأكيد شراء المحصول بنجاح ✅', style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.success,
            duration: Duration(seconds: 3),
          ),
        );
        _load(); // Reload the list
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء تأكيد شراء المحصول: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: AppTheme.danger,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }


  // ignore: unused_element
  Future<void> _showEditPriceDialog(LotReceiptModel lot) async {
    if (lot.id == null) return;
    
    final isCarton = lot.purchaseMode == 'carton';
    final currentPrice = isCarton ? (lot.pricePerCarton ?? 0.0) : lot.fruitCostPerKg;
    final currentCurrency = lot.currency.isEmpty ? 'EGP' : lot.currency;
    final currentExchangeRate = lot.exchangeRate;

    final priceCtrl = TextEditingController(text: currentPrice.toString());

    bool isSaving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: AppTheme.surface,
              title: Text('تعديل سعر المحصول - ${lot.lotNumber}', 
                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 16)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'العملة الحالية: $currentCurrency',
                      style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: isCarton ? 'السعر للكرتونة' : 'السعر للكيلو',
                        labelStyle: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'),
                        filled: true,
                        fillColor: const Color(0x1AFFFFFF),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('إلغاء', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      :                         () async {
                          final newPrice = double.tryParse(priceCtrl.text);

                          if (newPrice == null || newPrice < 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('السعر غير صالح'), backgroundColor: AppTheme.danger),
                            );
                            return;
                          }

                          setState(() => isSaving = true);
                          try {
                            await _dao.updateLotPrice(lot.id!, newPrice, currentExchangeRate, currentCurrency);
                            if (mounted) {
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم تعديل السعر بنجاح'), backgroundColor: AppTheme.success),
                              );
                              _load(); // Refresh the list
                            }
                          } catch (e) {
                            setState(() => isSaving = false);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTheme.danger),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                  child: isSaving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('حفظ السعر', style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
                ),
              ],
            );
          }
        );
      },
    );
  }

  Future<void> _exportAllPdf() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري تحميل البيانات وإنشاء PDF...'), duration: Duration(seconds: 3)),
    );
    try {
      await LotExportService.exportAllPdf();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم التصدير بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في التصدير: $e')),
        );
      }
    }
  }

  Widget _buildJournalEntriesDropdown(BuildContext context, LotReceiptModel lot) {
    return PopupMenuButton<String>(
      onSelected: (entryNumber) {
        JournalEntryNavigationService.openById(context, journalEntryId: entryNumber);
      },
      offset: const Offset(0, 30),
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppTheme.glassBorder.withAlpha(40)),
      ),
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(
          enabled: false,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _dao.getJournalEntriesForLot(lot.id ?? ''),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              final entries = snapshot.data ?? [];
              if (entries.isEmpty) {
                return const Text('لا توجد قيود محاسبية',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontFamily: 'Cairo'));
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('القيود المحاسبية (${entries.length})',
                      style: const TextStyle(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                  const SizedBox(height: 8),
                  ...entries.map((je) {
                    final entryNum = je['entry_number']?.toString() ?? '';
                    final date = je['entry_date']?.toString() ?? '';
                    final debit = (je['total_debit'] as num?)?.toDouble() ?? 0;
                    final cur = je['currency']?.toString() ?? 'EGP';
                    final srcType = je['source_type']?.toString() ?? '';
                    String typeLabel;
                    switch (srcType) {
                      case 'lot_receipt': typeLabel = 'قيد الشراء'; break;
                      case 'lot_price_adjustment': typeLabel = 'تعديل السعر'; break;
                      case 'crop_payment': typeLabel = 'قيد السداد'; break;
                      case 'purchase_payment': typeLabel = 'قيد السداد'; break;
                      default: typeLabel = srcType;
                    }
                    return GestureDetector(
                      onTap: () {
                        Navigator.of(ctx).pop();
                        JournalEntryNavigationService.openById(context, journalEntryId: entryNum);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: AppTheme.glassBorder.withAlpha(30))),
                        ),
                        child: Row(children: [
                          Icon(
                            srcType == 'lot_receipt' ? Icons.receipt_long_outlined
                              : srcType == 'lot_price_adjustment' ? Icons.price_change_outlined
                              : Icons.payment_outlined,
                            size: 14,
                            color: srcType == 'lot_receipt' ? AppTheme.cyan
                              : srcType == 'lot_price_adjustment' ? AppTheme.warning
                              : AppTheme.accent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('قيد #$entryNum — $typeLabel',
                                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 11, fontWeight: FontWeight.w600, fontFamily: 'Cairo')),
                                const SizedBox(height: 2),
                                Text('$date — ${debit.toStringAsFixed(2)} $cur',
                                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 10, fontFamily: 'Cairo')),
                              ],
                            ),
                          ),
                          const Icon(Icons.open_in_new, size: 12, color: AppTheme.textMuted),
                        ]),
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.cyan.withAlpha(25),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.cyan.withAlpha(80)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined, color: AppTheme.cyan, size: 14),
            SizedBox(width: 4),
            Text(
              'عرض القيد',
              style: TextStyle(
                color: AppTheme.cyan,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportAllExcel() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري تحميل البيانات وإنشاء Excel...'), duration: Duration(seconds: 3)),
    );
    try {
      await LotExportService.exportAllExcel();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم التصدير بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في التصدير: $e')),
        );
      }
    }
  }
}
