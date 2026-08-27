import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/consolidated_statement_pdf_service.dart';
import '../../data/models/customer_model.dart';
import '../../data/dao/treasury_dao.dart';
import '../auth/auth_cubit.dart';
import 'customer_cubit.dart';
import 'customer_state.dart';
import 'customer_form_dialog.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  late final CustomerCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = CustomerCubit()..init();
  }

  @override
  void dispose() {
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.person_outline, color: AppTheme.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('العملاء', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: isMobile ? 22 : 32, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
              BlocBuilder<CustomerCubit, CustomerState>(
                buildWhen: (prev, curr) => curr is CustomerLoaded,
                builder: (context, state) {
                  final count = state is CustomerLoaded ? state.customers.length : 0;
                  return Text('$count عميل', style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13));
                },
              ),
            ]),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.refresh_outlined),
          tooltip: 'تحديث',
          onPressed: () => _cubit.loadAll(reset: true),
        ),
        const SizedBox(width: 4),
        BlocBuilder<CustomerCubit, CustomerState>(
          buildWhen: (prev, curr) => curr is CustomerLoaded,
          builder: (context, state) {
            final customers = state is CustomerLoaded ? state.customers : <CustomerModel>[];
            if (customers.isEmpty) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white70),
              tooltip: 'حفظ PDF',
              onPressed: () => _savePdf(customers),
            );
          },
        ),
        const SizedBox(width: 4),
        ElevatedButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: Text(isMobile ? 'إضافة' : 'إضافة عميل'),
          onPressed: () async {
            await _cubit.prepareAddForm();
            if (!mounted) return;
            _showFormDialog();
          },
        ),
        ],
      );
  }

  Widget _buildSearchBar() {
    return TextField(
      onChanged: _cubit.onSearchChanged,
      decoration: InputDecoration(
        hintText: 'بحث بالاسم أو الكود...',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: BlocBuilder<CustomerCubit, CustomerState>(
          buildWhen: (prev, curr) => curr is CustomerLoaded,
          builder: (context, state) {
            final query = state is CustomerLoaded ? state.searchQuery : '';
            if (query.isEmpty) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () => _cubit.onSearchChanged(''),
            );
          },
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
          child: BlocConsumer<CustomerCubit, CustomerState>(
            listener: (context, state) {
              if (state is CustomerError) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(state.message)),
                );
              }
            },
            builder: (context, state) {
              if (state is CustomerLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state is CustomerLoaded) {
                if (state.customers.isEmpty) {
                  return _buildEmptyState(state.searchQuery);
                }
                return _buildDataTable(state);
              }
              return const Center(child: CircularProgressIndicator());
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDataTable(CustomerLoaded state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: constraints.maxWidth,
              maxWidth: constraints.maxWidth > 860 ? constraints.maxWidth : 860,
            ),
            child: Column(
              children: [
                _buildTableHeader(),
                const Divider(height: 1),
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (ScrollNotification scrollInfo) {
                      if (!state.isFetchingMore &&
                          state.hasMore &&
                          scrollInfo.metrics.pixels >= scrollInfo.metrics.maxScrollExtent - 200) {
                        _cubit.fetchMore();
                      }
                      return false;
                    },
                    child: ListView.separated(
                      itemCount: state.customers.length + (state.hasMore ? 1 : 0),
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                      itemBuilder: (listContext, index) {
                        if (index == state.customers.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        return _buildTableRow(listContext, state.customers[index], index);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
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
          Expanded(flex: 2, child: Text('الاسم', style: _labelStyle)),
          Expanded(flex: 2, child: Text('العنوان', style: _labelStyle)),
          SizedBox(width: 90, child: Text('الهاتف', style: _labelStyle)),
          SizedBox(width: 90, child: Text('الرصيد الحالي', style: _labelStyle, textAlign: TextAlign.center)),
          SizedBox(width: 80, child: Text('الرصيد المبدئي', style: _labelStyle, textAlign: TextAlign.center)),
          SizedBox(width: 70, child: Text('إجراءات', style: _labelStyle, textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildTableRow(BuildContext listContext, CustomerModel customer, int index) {
    final isEven = index % 2 == 0;
    final authState = context.read<AuthCubit>().state;
    final isAdmin = authState is AuthAuthenticated && authState.isAdmin;

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
                customer.code.isNotEmpty ? customer.code : '—',
                style: const TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          Expanded(
            flex: 2,
            child: Text(
              customer.name,
              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          Expanded(
            flex: 2,
            child: Text(
              customer.city.isNotEmpty ? customer.city : '—',
              style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          SizedBox(
            width: 90,
            child: Text(
              customer.phone.isNotEmpty ? customer.phone : '—',
              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
              textDirection: TextDirection.ltr,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          SizedBox(
            width: 90,
            child: Text(
              '${customer.balance < 0 ? '-' : ''}${customer.balance.abs().toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: customer.balance > 0 ? AppTheme.success : AppTheme.danger,
                fontFamily: 'Cairo',
              ),
              textAlign: TextAlign.center,
            ),
          ),

          SizedBox(
            width: 80,
            child: Text(
              customer.initialBalance == 0.0 ? '0.00' : customer.initialBalance.toStringAsFixed(2),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: customer.initialBalance > 0 ? AppTheme.success : AppTheme.textSecondary,
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
                  onTap: () => _showFormDialog(customer: customer),
                  child: const Icon(Icons.edit_outlined, size: 17, color: AppTheme.primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String searchQuery) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_search_outlined, size: 72, color: AppTheme.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            searchQuery.isEmpty ? 'لا يوجد عملاء بعد' : 'لا توجد نتائج للبحث',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, fontFamily: 'Cairo'),
          ),
          const SizedBox(height: 8),
          Text(
            searchQuery.isEmpty ? 'اضغط "إضافة عميل" لإضافة أول عميل' : 'جرب كلمة بحث مختلفة',
            style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13),
          ),
          if (searchQuery.isEmpty) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة عميل'),
              onPressed: () async {
                await _cubit.prepareAddForm();
                if (!mounted) return;
                _showFormDialog();
              },
            ),
          ],
        ],
      ),
    );
  }

  void _showLedgerSheet(CustomerModel customer) {
    final dao = TreasuryDao();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return FutureBuilder<List<Map<String, dynamic>>>(
            future: dao.getLedgerEntries(
              entityType: 'customer',
              entityId: '${customer.id}',
            ),
            builder: (_, snap) {
              final entries = snap.data ?? [];
              double runningBalance = customer.initialBalance;
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
                        Text('كشف حساب: ${customer.name}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo')),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Text('الرصيد المبدئي: ${AppUtils.formatCurrency(customer.initialBalance)}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontFamily: 'Cairo')),
                        const Spacer(),
                        Text('الرصيد الحالي: ${AppUtils.formatCurrency(customer.balance)}',
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
                              final isDebit = entryType == 'debit';
                              final refType = e['reference_type']?.toString() ?? '';
                              if (refType != 'opening_balance') {
                                runningBalance += isDebit ? amount : -amount;
                              }
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(children: [
                                  Icon(isDebit ? Icons.arrow_upward : Icons.arrow_downward,
                                      size: 16, color: isDebit ? AppTheme.warning : AppTheme.success),
                                  const SizedBox(width: 8),
                                  Expanded(flex: 2, child: Text(
                                    refType == 'opening_balance' ? 'رصيد افتتاحي' :
                                    refType == 'expense' ? 'مصروف' :
                                    refType == 'payment' ? 'دفع' :
                                    refType == 'reversal' ? 'عكس' : refType,
                                    style: const TextStyle(fontSize: 12, color: Colors.white, fontFamily: 'Cairo'))),
                                  Text('${e['currency'] ?? 'EGP'} ${AppUtils.formatNumber(amount)}',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDebit ? AppTheme.warning : AppTheme.success, fontFamily: 'Cairo')),
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

  void _showFormDialog({CustomerModel? customer}) {
    final cubit = context.read<CustomerCubit>();
    showDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: CustomerFormDialog(customer: customer),
      ),
    );
  }

  Future<String?> _showPasswordDialog() async {
    final ctrl = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF05192D),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.glassBorder),
        ),
        title: const Text('تأكيد كلمة المرور',
            style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: StatefulBuilder(
          builder: (ctx, setInnerState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('يرجى إدخال كلمة المرور لتأكيد العملية',
                    style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 13)),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  obscureText: true,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                  decoration: InputDecoration(
                    hintText: 'كلمة المرور',
                    hintStyle: const TextStyle(color: AppTheme.textSecondary),
                    prefixIcon: const Icon(Icons.lock_outline, color: AppTheme.textSecondary, size: 20),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.glassBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.glassBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.primary),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('تأكيد', style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return password;
  }

  Future<void> _showSecureDeleteConfirm(CustomerModel customer) async {
    // 1. Ask for admin password
    final password = await _showPasswordDialog();
    if (password == null || password.isEmpty) return;

    // 2. Show loading
    _showLoadingOverlay();

    // 3. Attempt deletion
    final errorCode = await _cubit.deleteCustomer(customer, password);

    // 4. Hide loading
    if (context.mounted) _hideLoadingOverlay();

    // 5. Handle result
    if (!context.mounted) return;

    if (errorCode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('تم حذف العميل بنجاح',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } else if (errorCode == 'wrong_password') {
      _showSimpleErrorDialog('كلمة المرور غير صحيحة');
    } else if (errorCode == 'has_dependencies') {
      _showFkDeleteError(context, 'العميل');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('فشل حذف العميل',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  OverlayEntry? _loadingOverlay;

  void _showLoadingOverlay() {
    _loadingOverlay = OverlayEntry(
      builder: (_) => Container(
        color: Colors.black.withValues(alpha: 0.3),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
    Overlay.of(context).insert(_loadingOverlay!);
  }

  void _hideLoadingOverlay() {
    _loadingOverlay?.remove();
    _loadingOverlay = null;
  }

  void _showSimpleErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF05192D),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.glassBorder),
        ),
        title: const Text('خطأ',
            style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
        content: Text(message,
            style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسناً', style: TextStyle(color: AppTheme.primary, fontFamily: 'Cairo')),
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
              'لا يمكن حذف $entityLabel لأنه مرتبط بفواتير أو حركات مالية مسجلة داخل النظام.',
              style: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo', fontSize: 14),
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

  Future<void> _printStatement(List<CustomerModel> customers) async {
    final rows = customers.map((c) => {
      'code': c.code,
      'name': c.name,
      'currency': c.currency,
      'balance': c.balance.toStringAsFixed(2),
    }).toList();
    final totalBalance = customers.fold<double>(0, (s, c) => s + c.balance);

    try {
      await ConsolidatedStatementPdfService.print(
        title: 'كشف حساب مجمع - العملاء',
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

  Future<void> _savePdf(List<CustomerModel> customers) async {
    final rows = customers.map((c) => {
      'code': c.code,
      'name': c.name,
      'currency': c.currency,
      'balance': c.balance.toStringAsFixed(2),
    }).toList();
    final totalBalance = customers.fold<double>(0, (s, c) => s + c.balance);

    try {
      final path = await ConsolidatedStatementPdfService.saveToFile(
        title: 'كشف حساب مجمع - العملاء',
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