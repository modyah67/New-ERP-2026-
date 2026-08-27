import 'dart:ui';

import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/dao/customer_dao.dart';
import '../../data/models/customer_model.dart';
import 'consolidated_statement_pdf_service.dart';

class ConsolidatedStatementPage extends StatefulWidget {
  const ConsolidatedStatementPage({super.key});

  @override
  State<ConsolidatedStatementPage> createState() =>
      _ConsolidatedStatementPageState();
}

class _ConsolidatedStatementPageState
    extends State<ConsolidatedStatementPage> {
  final _dao = CustomerDao();

  List<CustomerModel> _customers = [];
  bool _loading = false;
  bool _isPrinting = false;
  bool _isSaving = false;

  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() { _loading = true; _customers = []; });
    try {
      final list = await _dao.getAllCustomers();
      setState(() => _customers = list);
    } finally {
      setState(() => _loading = false);
    }
  }

  List<CustomerModel> get _filteredCustomers {
    if (_searchQuery.isEmpty) return _customers;
    final q = _searchQuery.toLowerCase();
    return _customers.where((c) =>
      c.name.toLowerCase().contains(q) ||
      c.id.toString().toLowerCase().contains(q)
    ).toList();
  }

  double get _grandTotal =>
      _filteredCustomers.fold(0.0, (s, c) => s + c.balance);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildHeader(),
          _buildFilterBar(),
          const Divider(height: 1),
          Expanded(child: _buildResultPanel()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: AppTheme.primary,
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Row(
        children: [
          const Icon(Icons.summarize_outlined, color: Colors.white, size: 26),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('كشف حساب مجمع',
                  style: TextStyle(color: Colors.white, fontSize: 18,
                      fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              Text('عرض وطباعة أرصدة جميع العملاء',
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Cairo')),
            ],
          ),
          const Spacer(),
          if (_customers.isNotEmpty) ...[
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _savePdf,
              icon: _isSaving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2))
                  : const Icon(Icons.save_alt_outlined, size: 18),
              label: Text(_isSaving ? 'جارى الحفظ...' : 'حفظ PDF',
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _isPrinting ? null : _printPdf,
              icon: _isPrinting
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2))
                  : const Icon(Icons.print_outlined, size: 18),
              label: Text(_isPrinting ? 'جارى الطباعة...' : 'طباعة PDF',
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: AppTheme.glassCard(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Row(
            children: [
              const Text('بحث:', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14)),
              const SizedBox(width: 12),
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  decoration: InputDecoration(
                    hintText: 'ابحث بالاسم أو الكود...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            })
                        : const Icon(Icons.arrow_drop_down),
                  ),
                ),
              ),
              const Spacer(),
              if (_customers.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: (_grandTotal >= 0 ? AppTheme.danger : AppTheme.success).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: (_grandTotal >= 0 ? AppTheme.danger : AppTheme.success).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Text('إجمالي الأرصدة: ',
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 12,
                              color: AppTheme.textSecondary)),
                      Text(
                        _grandTotal < 0
                            ? '-${AppUtils.formatCurrency(_grandTotal.abs())} ج.م'
                            : '${AppUtils.formatCurrency(_grandTotal)} ج.م',
                        style: TextStyle(
                          fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.bold,
                          color: _grandTotal < 0 ? AppTheme.success : AppTheme.danger,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultPanel() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_customers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.black12),
            SizedBox(height: 16),
            Text('لا يوجد عملاء بعد',
                style: TextStyle(fontFamily: 'Cairo',
                    color: AppTheme.textSecondary, fontSize: 15)),
          ],
        ),
      );
    }

    final filtered = _filteredCustomers;
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 64, color: Colors.black12),
            const SizedBox(height: 16),
            Text('لا توجد نتائج للبحث "$_searchQuery"',
                style: const TextStyle(fontFamily: 'Cairo',
                    color: AppTheme.textSecondary, fontSize: 15)),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildTableHeader(),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.divider),
            itemBuilder: (_, i) => _buildRow(filtered[i], i),
          ),
        ),
        _buildFooter(filtered),
      ],
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: const Color(0x1A00E5FF),
      child: Row(
        children: [
          SizedBox(width: 40, child: Text('#', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
          SizedBox(width: 110, child: Text('الكود', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
          Expanded(child: Text('اسم العميل', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14))),
          SizedBox(width: 180, child: Text('الرصيد', style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 14), textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildRow(CustomerModel c, int i) {
    final balance  = c.balance;
    final isEven   = i % 2 == 0;
    final isDebt   = balance > 0;
    final isCredit = balance < 0;
    final balanceColor = isDebt ? AppTheme.danger : isCredit ? AppTheme.success : AppTheme.textSecondary;
    final displayBalance = isCredit
        ? '-${AppUtils.formatCurrency(balance.abs())}'
        : AppUtils.formatCurrency(balance.abs());
    final label = isDebt ? 'عليه' : isCredit ? 'له' : 'متوازن';

    return Container(
      color: isEven ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          SizedBox(width: 40,
              child: Text('${i + 1}', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13))),
          SizedBox(
            width: 110,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(c.id.toString(),
                  style: const TextStyle(fontSize: 12, color: AppTheme.primary,
                      fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
            ),
          ),
          Expanded(
            child: Text(c.name,
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 13,
                    fontWeight: FontWeight.w600, color: Colors.white)),
          ),
          SizedBox(
            width: 180,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayBalance,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: balanceColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: balanceColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(label,
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 10,
                          color: balanceColor, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(List<CustomerModel> customers) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0x1A00E5FF),
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(
        children: [
          Text('إجمالي ${customers.length} عميل',
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 12,
                  color: AppTheme.textSecondary)),
          const Spacer(),
          const Text('إجمالي الأرصدة: ',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 13,
                  fontWeight: FontWeight.bold, color: Colors.white)),
          Text(
            _grandTotal < 0
                ? '-${AppUtils.formatCurrency(_grandTotal.abs())} ج.م'
                : '${AppUtils.formatCurrency(_grandTotal)} ج.م',
            style: TextStyle(
              fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.bold,
              color: _grandTotal < 0 ? AppTheme.success : AppTheme.danger,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printPdf() async {
    if (_customers.isEmpty) return;
    setState(() => _isPrinting = true);
    try {
      await ConsolidatedStatementPdfService.generateAndPrint(
        customers: _customers,
        printDate: DateTime.now(),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل إنشاء PDF: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      setState(() => _isPrinting = false);
    }
  }

  Future<void> _savePdf() async {
    if (_customers.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      await ConsolidatedStatementPdfService.saveToFile(
        context,
        customers: _customers,
        printDate: DateTime.now(),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل حفظ الملف: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }
}
