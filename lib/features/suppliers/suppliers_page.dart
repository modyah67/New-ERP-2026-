import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/consolidated_statement_pdf_service.dart';
import '../../data/models/supplier_model.dart';
import '../../data/dao/treasury_dao.dart';
import 'supplier_cubit.dart';
import 'supplier_state.dart';
import 'supplier_form_dialog.dart';

class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key});

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  @override
  void initState() {
    super.initState();
   // context.read<SupplierCubit>().loadAll(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(isMobile ? 12 : 24),
        child: BlocBuilder<SupplierCubit, SupplierState>(
          builder: (context, state) {
            final cubit = context.read<SupplierCubit>();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, cubit, state),
                const SizedBox(height: 20),
                _buildSearchBar(cubit, state),
                const SizedBox(height: 16),
                Expanded(child: _buildTable(context, cubit, state)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, SupplierCubit cubit, SupplierState state) {
    final suppliers = state is SupplierLoaded ? state.suppliers : <SupplierModel>[];
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        final isMobile = isNarrow;

        final titleSection = Row(
          mainAxisSize: isNarrow ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Container(
              width: isMobile ? 38 : 44,
              height: isMobile ? 38 : 44,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.people_outline, color: AppTheme.primary, size: isMobile ? 20 : 22),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'الموردون',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isMobile ? 22 : 30,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
                  Text(
                    '${suppliers.length} مورد',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontFamily: 'Cairo',
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        final actions = Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.start,
          children: [
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: 'تحديث',
              onPressed: () => cubit.loadAll(reset: true),
            ),
            if (suppliers.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white70),
                tooltip: 'حفظ PDF',
                onPressed: () => _savePdf(suppliers),
              ),
            ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: Text(isMobile ? 'إضافة' : 'إضافة مورد'),
              onPressed: () async {
                await cubit.prepareAddForm();
                if (context.mounted) {
                  showDialog(
                    context: context,
                    builder: (_) => BlocProvider.value(value: cubit, child: const SupplierFormDialog()),
                  );
                }
              },
            ),
          ],
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              titleSection,
              const SizedBox(height: 12),
              Align(alignment: AlignmentDirectional.centerStart, child: actions),
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: titleSection),
            actions,
          ],
        );
      },
    );
  }

  Widget _buildSearchBar(SupplierCubit cubit, SupplierState state) {
    final searchQuery = state is SupplierLoaded ? state.searchQuery : '';

    return TextField(
      onChanged: cubit.onSearchChanged,
      decoration: InputDecoration(
        hintText: 'بحث بالاسم أو الكود...',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: searchQuery.isEmpty
            ? const SizedBox.shrink()
            : IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () => cubit.onSearchChanged(''),
              ),
      ),
    );
  }

  Widget _buildTable(BuildContext context, SupplierCubit cubit, SupplierState state) {
    if (state is SupplierLoading) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: AppTheme.glassCard(),
            child: const Center(child: CircularProgressIndicator()),
          ),
        ),
      );
    }

    final suppliers = state is SupplierLoaded ? state.suppliers : <SupplierModel>[];
    final searchQuery = state is SupplierLoaded ? state.searchQuery : '';

    if (suppliers.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: AppTheme.glassCard(),
            child: _buildEmptyState(cubit, searchQuery),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: AppTheme.glassCard(),
          child: _buildDataTable(cubit, suppliers),
        ),
      ),
    );
  }

  Widget _buildDataTable(SupplierCubit cubit, List<SupplierModel> suppliers) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: constraints.maxWidth,
                    maxWidth: math.max(constraints.maxWidth, 920),
                  ),
                  child: Column(
                    children: [
                      _buildTableHeader(),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView.separated(
                          itemCount: suppliers.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                          itemBuilder: (context, index) {
                            return _buildTableRow(context, cubit, suppliers[index], index);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static const _labelStyle = TextStyle(
    color: AppTheme.textSecondary,
    fontWeight: FontWeight.w600,
    fontFamily: 'Cairo',
    fontSize: 13,
  );

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0x1A00E5FF),
      child: const Row(
        children: [
          SizedBox(width: 36, child: Text('#', style: _labelStyle)),
          SizedBox(width: 90, child: Text('الكود', style: _labelStyle)),
          Expanded(flex: 3, child: Text('الاسم', style: _labelStyle)),
          Expanded(flex: 2, child: Text('العنوان', style: _labelStyle)),
          SizedBox(width: 100, child: Text('الهاتف', style: _labelStyle)),
          SizedBox(width: 100, child: Text('الرصيد الحالي', style: _labelStyle, textAlign: TextAlign.center)),
          SizedBox(width: 90, child: Text('الرصيد المبدئي', style: _labelStyle, textAlign: TextAlign.center)),
          SizedBox(width: 70, child: Text('إجراءات', style: _labelStyle, textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildTableRow(BuildContext context, SupplierCubit cubit, SupplierModel supplier, int index) {
    final isEven = index % 2 == 0;

    return Container(
      height: 55,
      color: isEven ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.05),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text('${index + 1}', style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
          ),

          SizedBox(
            width: 90,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                supplier.supplierCode.isNotEmpty ? supplier.supplierCode : '—',
                style: const TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          Expanded(
            flex: 3,
            child: Text(
              supplier.name,
              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          Expanded(
            flex: 2,
            child: Text(
              supplier.address.isNotEmpty ? supplier.address : '—',
              style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          SizedBox(
            width: 100,
            child: Text(
              supplier.phone.isNotEmpty ? supplier.phone : '—',
              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
              textDirection: TextDirection.ltr,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          SizedBox(
            width: 100,
            child: Text(
              '${supplier.outstandingBalance < 0 ? '-' : ''}${supplier.outstandingBalance.abs().toStringAsFixed(2)} ${supplier.currencySymbol}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: supplier.outstandingBalance > 0 ? AppTheme.success : AppTheme.danger,
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
            ),
          ),

          SizedBox(
            width: 90,
            child: Text(
              supplier.initialBalance == 0.0 ? '0.00' : '${supplier.initialBalance.toStringAsFixed(2)} ${supplier.currencySymbol}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: supplier.initialBalance > 0 ? AppTheme.success : AppTheme.textSecondary,
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
            ),
          ),

          SizedBox(
            width: 70,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => _showEditDialog(context, cubit, supplier),
                  child: const Icon(Icons.edit_outlined, size: 17, color: AppTheme.primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(SupplierCubit cubit, String searchQuery) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 72, color: AppTheme.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            searchQuery.isEmpty ? 'لا يوجد موردين بعد' : 'لا توجد نتائج للبحث',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, fontFamily: 'Cairo'),
          ),
          const SizedBox(height: 8),
          Text(
            searchQuery.isEmpty ? 'اضغط "إضافة مورد" لإضافة أول مورد' : 'جرب كلمة بحث مختلفة',
            style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
          ),
          if (searchQuery.isEmpty) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة مورد'),
              onPressed: () async {
                await cubit.prepareAddForm();
                if (context.mounted) {
                  showDialog(
                    context: context,
                    builder: (_) => BlocProvider.value(value: cubit, child: const SupplierFormDialog()),
                  );
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  void _showLedgerSheet(BuildContext context, SupplierModel supplier) {
    final dao = TreasuryDao();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return FutureBuilder<List<Map<String, dynamic>>>(
            future: dao.getLedgerEntries(
              entityType: 'supplier',
              entityId: '${supplier.id}',
            ),
            builder: (_, snap) {
              final entries = snap.data ?? [];
              double runningBalance = supplier.initialBalance;
              return Container(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
                decoration: BoxDecoration(
                  color: const Color(0xFF05192D),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border(top: BorderSide(color: AppTheme.glassBorder)),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.receipt_long_outlined, color: AppTheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Text('كشف حساب: ${supplier.name}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Text('الرصيد المبدئي: ${supplier.initialBalance.toStringAsFixed(2)} ${supplier.currencySymbol}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontFamily: 'Cairo')),
                        const Spacer(),
                        Text('الرصيد الحالي: ${supplier.outstandingBalance.toStringAsFixed(2)} ${supplier.currencySymbol}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.success, fontFamily: 'Cairo')),
                      ]),
                      const SizedBox(height: 12),
                      if (snap.connectionState == ConnectionState.waiting)
                        const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
                      else if (snap.hasError)
                        Center(child: Text('خطأ في التحميل: ${snap.error}', style: const TextStyle(color: AppTheme.danger, fontFamily: 'Cairo')))
                      else if (entries.isEmpty)
                        const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('لا توجد حركات', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'))))
                      else
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: entries.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.glassBorder),
                            itemBuilder: (_, i) {
                              final e = entries[i];
                              final entryType = e['entry_type']?.toString() ?? '';
                              final amount = ((e['amount'] as num?)?.toDouble() ?? 0);
                              final isDebit = entryType == 'credit';
                              final refType = e['reference_type']?.toString() ?? '';
                              runningBalance += isDebit ? amount : -amount;
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(children: [
                                  Icon(isDebit ? Icons.arrow_downward : Icons.arrow_upward,
                                      size: 16, color: isDebit ? AppTheme.success : AppTheme.warning),
                                  const SizedBox(width: 8),
                                  Expanded(flex: 2, child: Text(
                                    refType == 'opening_balance' ? 'رصيد افتتاحي' :
                                    refType == 'expense' ? 'مصروف' :
                                    refType == 'payment' ? 'دفع' :
                                    refType == 'packing_order_debit_note' ? 'إشعار خصم أمر تعبئة' :
                                    refType == 'reversal' ? 'عكس' : refType,
                                    style: const TextStyle(fontSize: 12, color: Colors.white, fontFamily: 'Cairo'))),
                                  Text('${e['currency'] ?? 'EGP'} ${AppUtils.formatNumber(amount)}',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDebit ? AppTheme.success : AppTheme.warning, fontFamily: 'Cairo')),
                                  const SizedBox(width: 16),
                                  Text(AppUtils.formatNumber(runningBalance),
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, fontFamily: 'Cairo')),
                                ]),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showEditDialog(BuildContext context, SupplierCubit cubit, SupplierModel supplier) async {
    await cubit.prepareEditForm(supplier);
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (_) => BlocProvider.value(value: cubit, child: SupplierFormDialog(supplier: supplier)),
      );
    }
  }

  void _showDeleteConfirm(BuildContext context, SupplierCubit cubit, SupplierModel supplier) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF05192D),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.glassBorder),
        ),
        title: const Text('تأكيد الحذف', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: Text('هل أنت متأكد من حذف "${supplier.name}"؟', style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(dialogContext);
              final errorCode = await cubit.deleteSupplier(supplier.supplierCode);
              if (errorCode == '23503' && context.mounted) {
                _showFkDeleteError(context, 'المورد');
              }
            },
            child: const Text('حذف', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  void _showFkDeleteError(BuildContext context, String entityLabel) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF05192D),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.glassBorder),
        ),
        title: Text('لا يمكن حذف $entityLabel',
            style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'هذا $entityLabel مرتبط بفواتير شراء أو معاملات مالية مسجلة داخل النظام، لذلك لا يمكن حذفه حفاظاً على سلامة البيانات المحاسبية.',
              style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 14),
            ),
            const SizedBox(height: 16),
            Text(
              'إذا كنت لا ترغب في استخدام هذا $entityLabel مستقبلاً، يفضل تعطيله أو إخفاؤه بدلاً من حذفه.',
              style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.7), fontFamily: 'Cairo', fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسناً', style: TextStyle(color: AppTheme.primary, fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  Future<void> _printStatement(List<SupplierModel> suppliers) async {
    final rows = suppliers.map((s) => {
      'code': s.supplierCode,
      'name': s.name,
      'currency': s.currency,
      'balance': s.outstandingBalance.toStringAsFixed(2),
    }).toList();
    final totalBalance = suppliers.fold<double>(0, (s, sp) => s + sp.outstandingBalance);

    try {
      await ConsolidatedStatementPdfService.print(
        title: 'كشف حساب مجمع - الموردون',
        rows: rows,
        totalBalance: totalBalance,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل إنشاء PDF: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Future<void> _savePdf(List<SupplierModel> suppliers) async {
    final rows = suppliers.map((s) => {
      'code': s.supplierCode,
      'name': s.name,
      'currency': s.currency,
      'balance': s.outstandingBalance.toStringAsFixed(2),
    }).toList();
    final totalBalance = suppliers.fold<double>(0, (s, sp) => s + sp.outstandingBalance);

    try {
      final path = await ConsolidatedStatementPdfService.saveToFile(
        title: 'كشف حساب مجمع - الموردون',
        rows: rows,
        totalBalance: totalBalance,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم الحفظ في: $path'), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل حفظ PDF: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }
}
