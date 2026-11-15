import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/widgets/order_range_filter_field.dart';
import '../../../core/widgets/estimated_cost_delete_helper.dart';
import '../../../data/dao/supplier_dao.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/router.dart';
import '../../../core/theme.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/account_ledger_result.dart';
import '../../../data/services/account_ledger_service.dart';
import '../../accounting/account_statement_pdf_service.dart';
import '../services/account_cost_settlement_pdf_service.dart';
import '../../auth/auth_cubit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/data_change_event_bus.dart';
import '../../../data/dao/packing_order_dao.dart';

class AccountJournalEntriesDialog extends StatefulWidget {
  final AccountModel account;
  final List<AccountModel> allBranchAccounts;
  final bool isBranch;
  final int initialTabIndex;
  final String? initialSearchQuery;

  const AccountJournalEntriesDialog({
    super.key,
    required this.account,
    required this.allBranchAccounts,
    this.isBranch = false,
    this.initialTabIndex = 0,
    this.initialSearchQuery,
  });

  static Future<void> show(
    BuildContext context, {
    required AccountModel account,
    required List<AccountModel> allBranchAccounts,
    bool isBranch = false,
    int initialTabIndex = 0,
    String? initialSearchQuery,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AccountJournalEntriesDialog(
        account: account,
        allBranchAccounts: allBranchAccounts,
        isBranch: isBranch,
        initialTabIndex: initialTabIndex,
        initialSearchQuery: initialSearchQuery,
      ),
    );
  }

  @override
  State<AccountJournalEntriesDialog> createState() =>
      _AccountJournalEntriesDialogState();
}

class _AccountJournalEntriesDialogState
    extends State<AccountJournalEntriesDialog>
    with SingleTickerProviderStateMixin {
  final AccountLedgerService _ledgerService = AccountLedgerService();
  final TextEditingController _searchCtrl = TextEditingController();

  TabController? _tabControllerInstance;
  TabController get _tabController =>
      _tabControllerInstance ??= TabController(
        length: 2,
        vsync: this,
        initialIndex: (widget.initialTabIndex >= 0 && widget.initialTabIndex < 2)
            ? widget.initialTabIndex
            : 0,
      );

  // ── Multi-Order Cost Settlement State ──
  bool _isLoadingSettlement = false;
  bool _isSavingSettlement = false;
  String? _settlementError;
  List<Map<String, dynamic>> _settlementRows = [];
  final TextEditingController _overallActualCtrl = TextEditingController();
  final TextEditingController _overallQtyCtrl = TextEditingController(text: '1');
  final TextEditingController _overallUnitPriceCtrl = TextEditingController();
  final TextEditingController _overallNotesCtrl = TextEditingController();
  DateTime _overallInvoiceDateTime = DateTime.now();
  String _distributionMethod = 'proportional'; // 'proportional' or 'equal'
  final Map<dynamic, TextEditingController> _itemActualCtrls = {};
  final Map<dynamic, TextEditingController> _itemNotesCtrls = {};
  final Map<dynamic, TextEditingController> _itemQtyCtrls = {};
  final Map<dynamic, TextEditingController> _itemUnitPriceCtrls = {};
  final Map<dynamic, DateTime> _itemDateTimes = {};
  final Map<dynamic, List<double>> _itemUnitPriceBreakdowns = {};
  final Set<dynamic> _modifiedItemKeys = {};
  final Set<dynamic> _unlockedItemKeys = {}; // البنود المفتوحة مؤقتاً للتعديل بكلمة المرور
  final Set<dynamic> _settlingItemKeys = {}; // البنود الجاري اعتمادها فردياً
  final Set<dynamic> _deletingItemKeys = {}; // البنود التقديرية الجاري حذفها
  final SupplierDao _supplierDao = SupplierDao();
  static const String _settlementUnlockPassword = 'eslam2026';
  final TextEditingController _settlementSearchCtrl = TextEditingController();
  final TextEditingController _settlementFromOrderCtrl = TextEditingController();
  final TextEditingController _settlementToOrderCtrl = TextEditingController();
  bool _loadedSettlementWithOrderRange = false;
  String _settlementSearchQuery = '';

  int? get _settlementFromOrderId =>
      OrderRangeFilterHelper.parseFilterBound(_settlementFromOrderCtrl.text);
  int? get _settlementToOrderId =>
      OrderRangeFilterHelper.parseFilterBound(_settlementToOrderCtrl.text);
  bool _showAllOrders = true; // زر كافة أوامر التعبئة
  bool _filterOnlyPending = false; // فلتر الأوامر غير المسواة فقط

  bool _isLoading = true;
  bool _isPrinting = false;
  bool _isPrintingSettlement = false;
  String? _error;
  AccountLedgerResult _result = AccountLedgerResult.empty;

  DateTime? _fromDate;
  DateTime? _toDate;
  String _selectedTypeFilter = 'all'; // 'all', 'debit', 'credit'
  String _selectedCurrency = 'ALL'; // 'ALL' (EGP base) or specific currency e.g. 'USD'
  String? _selectedSubAccountId; // filter by specific child if branch

  Set<String> get _availableCurrencies {
    final s = <String>{};
    if (widget.account.balancesByCurrency.isNotEmpty) {
      s.addAll(widget.account.balancesByCurrency.keys);
    }
    if (widget.isBranch) {
      for (final a in widget.allBranchAccounts) {
        s.addAll(a.balancesByCurrency.keys);
      }
    }
    for (final e in _result.entries) {
      if (e.currency.isNotEmpty && e.currency != 'EGP' && e.currency != 'ج.م') {
        s.add(e.currency);
      }
    }
    s.remove('EGP');
    s.remove('ج.م');
    return s;
  }

  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    _tabControllerInstance = TabController(
      length: 2,
      vsync: this,
      initialIndex: (widget.initialTabIndex >= 0 && widget.initialTabIndex < 2)
          ? widget.initialTabIndex
          : 0,
    );
    _tabControllerInstance!.addListener(() {
      if (mounted) setState(() {});
    });
    if (widget.initialSearchQuery != null && widget.initialSearchQuery!.isNotEmpty) {
      _settlementSearchCtrl.text = widget.initialSearchQuery!;
      _settlementSearchQuery = widget.initialSearchQuery!;
    }
    _loadLedger();
    _loadSettlementItems();
  }

  @override
  void dispose() {
    _tabControllerInstance?.dispose();
    _tabControllerInstance = null;
    _searchCtrl.dispose();
    _settlementSearchCtrl.dispose();
    _settlementFromOrderCtrl.dispose();
    _settlementToOrderCtrl.dispose();
    _overallActualCtrl.dispose();
    _overallQtyCtrl.dispose();
    _overallUnitPriceCtrl.dispose();
    _overallNotesCtrl.dispose();
    for (final c in _itemActualCtrls.values) {
      c.dispose();
    }
    for (final c in _itemNotesCtrls.values) {
      c.dispose();
    }
    for (final c in _itemQtyCtrls.values) {
      c.dispose();
    }
    for (final c in _itemUnitPriceCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLedger() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      List<String> accountIds = [];
      if (widget.isBranch && widget.allBranchAccounts.isNotEmpty) {
        accountIds = widget.allBranchAccounts
            .map((a) => a.id ?? '')
            .where((id) => id.isNotEmpty)
            .toList();
      } else if (widget.account.id != null) {
        accountIds = [widget.account.id!];
      }

      if (accountIds.isEmpty) {
        setState(() {
          _result = AccountLedgerResult.empty;
          _isLoading = false;
        });
        return;
      }

      var result = await _ledgerService.getAccountLedger(
        accountIds: accountIds,
        accountType: widget.account.type,
        fromDate: _fromDate,
        toDate: _toDate,
        currency: _selectedCurrency == 'ALL' ? null : _selectedCurrency,
      );



      if (mounted) {
        setState(() {
          _result = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('AccountJournalEntriesDialog: ERROR: $e');
      if (mounted) {
        setState(() {
          _error = 'تعذر تحميل قيود الحساب: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _printAccountStatementPdf() async {
    if (_isPrinting || _isLoading) return;
    setState(() => _isPrinting = true);

    try {
      final entriesToPrint = _filteredEntries;

      // Calculate totals for filtered entries
      double totalDebit = 0.0;
      double totalCredit = 0.0;
      for (final e in entriesToPrint) {
        totalDebit += e.debit;
        totalCredit += e.credit;
      }

      final isFiltered = _searchCtrl.text.trim().isNotEmpty ||
          _selectedTypeFilter != 'all' ||
          _selectedSubAccountId != null;

      final effOpening = isFiltered ? 0.0 : _result.openingBalance;
      final effTotalDebit = isFiltered ? totalDebit : _result.totalDebit;
      final effTotalCredit = isFiltered ? totalCredit : _result.totalCredit;
      final effClosing = isFiltered
          ? (widget.account.isCreditNormal
              ? (effOpening + totalCredit - totalDebit)
              : (effOpening + totalDebit - totalCredit))
          : _result.closingBalance;

      final effectiveCurrency = _selectedCurrency == 'ALL'
          ? (_result.currency.isNotEmpty ? _result.currency : 'EGP')
          : _selectedCurrency;

      await AccountStatementPdfService.printLedgerStatement(
        account: widget.account,
        entries: entriesToPrint,
        openingBalance: effOpening,
        totalDebit: effTotalDebit,
        totalCredit: effTotalCredit,
        closingBalance: effClosing,
        fromDate: _fromDate,
        toDate: _toDate,
        currency: effectiveCurrency,
        isBranch: widget.isBranch,
      );
    } catch (e, st) {
      debugPrint('Error printing account statement PDF: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'حدث خطأ أثناء إعداد كشف الحساب: $e',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPrinting = false);
      }
    }
  }

  Future<void> _printCostSettlementPdf() async {
    if (_isPrintingSettlement || _isLoadingSettlement) return;
    setState(() => _isPrintingSettlement = true);

    try {
      final itemsToPrint = _filteredSettlementRows;
      if (itemsToPrint.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لا توجد بنود تكاليف لعرضها أو طباعتها', textDirection: TextDirection.rtl),
              backgroundColor: AppTheme.warning,
            ),
          );
        }
        return;
      }

      final resolvedRows = AccountCostSettlementPdfService.resolveRowsFromUi(
        items: itemsToPrint,
        actualControllers: _itemActualCtrls,
        qtyControllers: _itemQtyCtrls,
        unitPriceControllers: _itemUnitPriceCtrls,
        notesControllers: _itemNotesCtrls,
        itemDateTimes: _itemDateTimes,
        unitPriceBreakdowns: _itemUnitPriceBreakdowns,
        isItemLockedFn: _isItemLocked,
        getEstimatedCostFn: _getEstimatedCost,
      );

      await AccountCostSettlementPdfService.printCostSettlementReport(
        account: widget.account,
        rows: resolvedRows,
        currency: 'EGP',
        orderRangeLabel: OrderRangeFilterHelper.formatRangeLabel(
          fromOrderId: _settlementFromOrderId,
          toOrderId: _settlementToOrderId,
        ),
      );
    } catch (e, st) {
      debugPrint('❌ Error printing cost settlement PDF: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'حدث خطأ أثناء إعداد تقرير تسوية التكاليف: $e',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPrintingSettlement = false);
      }
    }
  }

  /// Apply local filters (search, type, sub-account) to the loaded result
  List<AccountLedgerEntry> get _filteredEntries {
    var entries = _result.entries;
    final q = _searchCtrl.text.trim().toLowerCase();

    return entries.where((entry) {
      // Sub-account filter
      if (_selectedSubAccountId != null &&
          entry.accountCode != '' &&
          !entry.id.contains(_selectedSubAccountId!)) {
        // For branch accounts, we need to check if the entry belongs to selected sub-account
        // The entry's account info is embedded, so we can filter by accountCode matching
      }

      // Type filter
      if (_selectedTypeFilter == 'debit' && !entry.isDebit) return false;
      if (_selectedTypeFilter == 'credit' && entry.isDebit) return false;

      // Search filter
      if (q.isNotEmpty) {
        final entryNum = entry.entryNumber?.toLowerCase() ?? '';
        final desc = entry.description.toLowerCase();
        final accName = entry.accountName.toLowerCase();
        final accCode = entry.accountCode.toLowerCase();
        final refType = entry.referenceTypeLabel.toLowerCase();
        final amountStr = entry.amount.toString();

        if (!entryNum.contains(q) &&
            !desc.contains(q) &&
            !accName.contains(q) &&
            !accCode.contains(q) &&
            !refType.contains(q) &&
            !amountStr.contains(q)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isMobile = screenSize.width < 900;
    final dialogWidth = isMobile ? screenSize.width * 0.96 : (screenSize.width * 0.92).clamp(360.0, 1400.0);
    final maxHeight = screenSize.height - 32;
    final dialogHeight = (screenSize.height * 0.92).clamp(380.0, maxHeight > 380 ? maxHeight : 380.0);

    return Dialog(
      backgroundColor: AppTheme.getDialogBg(context),
      insetPadding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 16, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: AppTheme.getDialogBorder(context),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: dialogWidth,
          height: dialogHeight,
          padding: EdgeInsets.all(isMobile ? 12 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDialogHeader(),
              const SizedBox(height: 10),
              _buildTabBar(),
              const SizedBox(height: 10),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildStandardLedgerTab(),
                    _buildMultiOrderSettlementTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Multi-Order Cost Settlement Logic & Tabs
  // ══════════════════════════════════════════════════════════════════════════

  String _normalizeArabic(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'[\u064B-\u065F]'), '') // tashkeel
        .trim();
  }

  bool _isItemMatchingCurrentAccount(Map<String, dynamic> item) {
    if (item['deleted_at'] != null && item['deleted_at'].toString().isNotEmpty) {
      return false;
    }
    final code = widget.account.code.trim();
    final accName = _normalizeArabic(widget.account.name);
    final rawName = (item['name'] ?? item['item_name'] ?? item['cost_name'] ?? '').toString();
    final itemName = _normalizeArabic(rawName);
    final category = (item['category'] ?? '').toString().trim().toLowerCase();

    // ── 1. حساب المصاريف الإدارية والعمومية (كود 31331 أو ما يماثله) ──
    final isAdminAccount = code == '31331' ||
        accName.contains('اداري') ||
        accName.contains('عمومي');

    if (isAdminAccount) {
      // استبعاد قاطع لأي بنود تشغيلية أو مستقلة مثل الفحص أو التدوير أو النقل أو المشالات
      if (itemName.contains('فحص') ||
          itemName.contains('تحليل') ||
          itemName.contains('تدوير') ||
          itemName.contains('نقل') ||
          itemName.contains('مشال') ||
          itemName.contains('كرتون') ||
          itemName.contains('سائق') ||
          itemName.contains('مهندس') ||
          itemName.contains('تخليص')) {
        return false;
      }
      // قبول البنود التي تطابق المصروف الإداري صراحة
      return itemName.contains('اداري') ||
          itemName.contains('عمومي') ||
          category == 'admin' ||
          category == 'administrative';
    }

    // ── 2. حساب رسوم الفحص والتحاليل ──
    final isInspectionAccount = accName.contains('فحص') ||
        accName.contains('تحليل') ||
        accName.contains('جوده') ||
        accName.contains('مختبر');
    if (isInspectionAccount) {
      return itemName.contains('فحص') ||
          itemName.contains('تحليل') ||
          itemName.contains('مختبر') ||
          itemName.contains('جوده');
    }

    // ── 3. حساب إعادة التدوير ──
    final isRecyclingAccount = accName.contains('تدوير');
    if (isRecyclingAccount) {
      return itemName.contains('تدوير');
    }

    // ── 4. حساب مصاريف وعهدة المهندس (كود 31251) ──
    final isEngineerAccount = code == '31251' || accName.contains('مهندس');
    if (isEngineerAccount) {
      return category == 'engineer_expenses' || itemName.contains('مهندس');
    }

    // ── 5. حسابات النقل واللوجستيات والمشالات (كود 31321) ──
    final isLogisticsAccount = code == '31321' ||
        accName.contains('نقل') ||
        accName.contains('مشال') ||
        accName.contains('نولون');
    if (isLogisticsAccount) {
      return category == 'logistics' ||
          itemName.contains('نقل') ||
          itemName.contains('مشال') ||
          itemName.contains('نولون') ||
          itemName.contains('سائق');
    }

    // ── 6. المطابقة للحسابات الأخرى بناءً على اسم الحساب ──
    final cleanAcc = accName
        .replaceAll('مصاريف', '')
        .replaceAll('مصروفات', '')
        .replaceAll('حساب', '')
        .trim();
    if (cleanAcc.isNotEmpty && cleanAcc.length >= 3) {
      return itemName.contains(cleanAcc) || category.contains(cleanAcc);
    }

    return itemName.contains(accName) || accName.contains(itemName);
  }

  /// التحقق من صلاحيات المدير لإمكانية التعديل الاستثنائي
  // ignore: unused_element
  bool get _isCurrentUserAdmin {
    try {
      final authState = context.read<AuthCubit>().state;
      if (authState is AuthAuthenticated) {
        return authState.isAdmin;
      }
    } catch (_) {}
    return false;
  }

  /// فحص هل البند معتمد ومقفل لمنع أي تلاعب أو تعديل بعد التسوية
  bool _isItemLocked(Map<String, dynamic> item) {
    final name = (item['name'] ?? '').toString().toLowerCase();
    final cat = (item['category'] ?? '').toString().toLowerCase();
    final isAdmin = cat == 'admin' || name.contains('إدار') || name.contains('ادار');

    if (isAdmin) {
      final hasReconciled = item['reconciled_at'] != null &&
          item['reconciled_at'].toString().isNotEmpty &&
          item['reconciled_at'].toString() != 'null';
      final hasJe = item['variance_journal_entry_id'] != null;
      final status = (item['cost_status'] ?? '').toString().toLowerCase();
      final hasActual = (item['actual_amount'] as num?) != null && ((item['actual_amount'] as num) > 0);

      // بنود المصاريف الإدارية تقفل حصرياً عند وجود تسوية فعلية مؤكدة بمبلغ فعلي وإقفال صريح
      if ((hasReconciled || hasJe || status == 'settled') && hasActual && item['is_locked'] != false) {
        return true;
      }
      return false;
    }

    if (item['is_locked'] == true) return true;
    final status = (item['cost_status'] ?? '').toString().toLowerCase();
    if (status == 'locked' || status == 'settled' || status == 'actual') return true;
    if (item['reconciled_at'] != null &&
        item['reconciled_at'].toString().isNotEmpty &&
        item['reconciled_at'].toString() != 'null') {
      return true;
    }
    return false;
  }

  /// استخراج القيمة التقديرية بدقة عبر فحص كافة الحقول وملاحظات أمر التعبئة الأصلية
  double _getEstimatedCost(Map<String, dynamic> item, {dynamic poNotes}) {
    // 1. إذا تم احتساب التقديري مسبقاً وتأكيده
    final res = (item['resolved_estimated'] as num?)?.toDouble();
    if (res != null && res > 0) return res;

    // 2. فحص expected_amount إذا كانت أكبر من 0
    final exp = (item['expected_amount'] as num?)?.toDouble();
    if (exp != null && exp > 0) return exp;

    // 3. فحص base_amount (القيمة بالجنيه المصري EGP)
    final base = (item['base_amount'] as num?)?.toDouble();
    if (base != null && base > 0) return base;

    // 4. فحص original_amount
    final orig = (item['original_amount'] as num?)?.toDouble();
    if (orig != null && orig > 0) return orig;

    // 5. فحص بيانات currency_snapshot
    final snap = item['currency_snapshot'];
    if (snap is Map) {
      final snapEgp = (snap['total_egp'] as num?)?.toDouble();
      if (snapEgp != null && snapEgp > 0) return snapEgp;
      final snapTotal = (snap['total'] as num?)?.toDouble();
      if (snapTotal != null && snapTotal > 0) return snapTotal;
      final snapExp = (snap['expected_amount'] as num?)?.toDouble();
      if (snapExp != null && snapExp > 0) return snapExp;
      final snapPrice = (snap['unit_price'] as num?)?.toDouble();
      final snapQty = (snap['quantity'] as num?)?.toDouble() ?? 1.0;
      if (snapPrice != null && snapPrice > 0) return snapPrice * snapQty;
    }

    // 6. فحص ملاحظات وبيانات أمر التعبئة الأصلي (notes.cost_items)
    final notesSource = poNotes ?? item['notes'];
    if (notesSource != null) {
      try {
        final parsedNotes = notesSource is Map ? notesSource : jsonDecode(notesSource.toString());
        if (parsedNotes is Map && parsedNotes.containsKey('cost_items')) {
          final rawList = parsedNotes['cost_items'];
          if (rawList is List) {
            final normTarget = _normalizeArabic((item['name'] ?? item['item_name'] ?? '').toString());
            for (final c in rawList) {
              if (c is Map) {
                final cName = _normalizeArabic((c['name'] ?? c['item_name'] ?? '').toString());
                if (cName == normTarget || (cName.isNotEmpty && (cName.contains(normTarget) || normTarget.contains(cName)))) {
                  final cTot = (c['total_egp'] as num?)?.toDouble() ??
                      (c['total'] as num?)?.toDouble() ??
                      (c['expected_amount'] as num?)?.toDouble() ??
                      (((c['unit_price'] as num?)?.toDouble() ?? 0.0) * ((c['quantity'] as num?)?.toDouble() ?? 1.0));
                  if (cTot > 0) return cTot;
                }
              }
            }
          }
        }
      } catch (_) {}
    }

    // 7. فحص الحقول المباشرة total_egp أو total
    final totEgp = (item['total_egp'] as num?)?.toDouble();
    if (totEgp != null && totEgp > 0) return totEgp;
    final tot = (item['total'] as num?)?.toDouble();
    if (tot != null && tot > 0) return tot;

    // 8. فحص سعر الوحدة والكمية
    final uPrice = (item['unit_price'] as num?)?.toDouble();
    final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
    if (uPrice != null && uPrice > 0) return uPrice * qty;

    return 0.0;
  }

  Future<void> _loadSettlementItems({
    bool showAllOrders = true,
    int? fromOrderId,
    int? toOrderId,
    bool applyOrderRangeToQuery = true,
  }) async {
    setState(() {
      _isLoadingSettlement = true;
      _settlementError = null;
      _showAllOrders = showAllOrders;
    });

    try {
      final client = Supabase.instance.client;
      final effectiveFrom =
          applyOrderRangeToQuery ? (fromOrderId ?? _settlementFromOrderId) : null;
      final effectiveTo =
          applyOrderRangeToQuery ? (toOrderId ?? _settlementToOrderId) : null;
      final hasServerRange = effectiveFrom != null || effectiveTo != null;

      final Map<int, Map<String, dynamic>> ordersMap = {};
      final List<dynamic> itemsList = [];

      if (hasServerRange) {
        final ordersData = await client
            .from('packing_orders')
            .select('id, order_number, product_name, status, created_at, notes')
            .neq('status', 'cancelled');

        final matchingPoIds = <int>[];
        for (final o in (ordersData as List)) {
          final m = Map<String, dynamic>.from(o as Map);
          final pId = (m['id'] as num?)?.toInt();
          if (pId == null) continue;
          if (OrderRangeFilterHelper.matchesOrderRange(
            orderNumber: m['order_number']?.toString(),
            packingOrderId: pId,
            fromOrderId: effectiveFrom,
            toOrderId: effectiveTo,
          )) {
            ordersMap[pId] = m;
            matchingPoIds.add(pId);
          }
        }

        if (matchingPoIds.isNotEmpty) {
          for (var i = 0; i < matchingPoIds.length; i += 200) {
            final chunk = matchingPoIds.sublist(
              i,
              i + 200 > matchingPoIds.length ? matchingPoIds.length : i + 200,
            );
            final batchData = await client
                .from('packing_order_cost_items')
                .select()
                .isFilter('deleted_at', null)
                .inFilter('packing_order_id', chunk)
                .order('packing_order_id', ascending: false)
                .order('id', ascending: true);
            itemsList.addAll(batchData as List);
          }
        }
      } else {
        // 1. Fetch packing_order_cost_items (active items only)
        final costItemsData = await client
            .from('packing_order_cost_items')
            .select()
            .isFilter('deleted_at', null)
            .order('packing_order_id', ascending: false)
            .order('id', ascending: true);
        itemsList.addAll(costItemsData as List);
      }

      _loadedSettlementWithOrderRange = hasServerRange;

      if (itemsList.isEmpty) {
        if (mounted) {
          setState(() {
            _settlementRows = [];
            _isLoadingSettlement = false;
          });
        }
        return;
      }

      // 2. Fetch linked packing orders safely (including notes for complete cost items data)
      final poIds = itemsList
          .map((e) => (e as Map)['packing_order_id'] as int?)
          .whereType<int>()
          .toSet()
          .toList();

      if (poIds.isNotEmpty && ordersMap.isEmpty) {
        try {
          final ordersData = await client
              .from('packing_orders')
              .select('id, order_number, product_name, status, created_at, notes')
              .inFilter('id', poIds);
          for (final o in ordersData) {
            final m = Map<String, dynamic>.from(o as Map);
            final pId = m['id'] as int?;
            if (pId != null) ordersMap[pId] = m;
          }
        } catch (poErr) {
          debugPrint('⚠️ Orders fetch for settlement error: $poErr');
        }
      }

      final List<Map<String, dynamic>> enriched = [];
      for (final raw in itemsList) {
        final item = Map<String, dynamic>.from(raw as Map);

        // فلترة دقيقة: استبعاد أي بند لا يخص هذا الحساب (مثل استبعاد رسوم الفحص والتدوير عن المصاريف الإدارية)
        if (!_isItemMatchingCurrentAccount(item)) {
          continue;
        }

        final pId = (item['packing_order_id'] as num?)?.toInt();
        final po = pId != null ? ordersMap[pId] : null;

        final poNum = po?['order_number']?.toString() ?? pId?.toString() ?? '-';
        final poProd = po?['product_name']?.toString() ?? '';
        final poDate = po?['created_at']?.toString() ?? '';

        // استخراج القيمة التقديرية الحقيقية بدقة تامة وضمان عدم ظهور 0.00
        final double estimatedCost = _getEstimatedCost(item, poNotes: po?['notes']);

        // استخراج وتدقيق البيان / الملاحظات
        String resolvedNotes = (item['settlement_notes'] ?? item['notes'] ?? item['invoice_ref'] ?? '').toString();
        if (resolvedNotes.isEmpty || resolvedNotes == 'null') {
          final snap = item['currency_snapshot'];
          if (snap is Map && snap['notes'] != null && snap['notes'].toString().isNotEmpty) {
            resolvedNotes = snap['notes'].toString();
          }
        }
        if ((resolvedNotes.isEmpty || resolvedNotes == 'null') && po?['notes'] != null) {
          try {
            final parsedNotes = jsonDecode(po!['notes'].toString());
            if (parsedNotes is Map && parsedNotes.containsKey('cost_items')) {
              final rawList = parsedNotes['cost_items'];
              if (rawList is List) {
                for (final ci in rawList) {
                  if (ci is Map && (ci['name'] == item['name'] || ci['id'] == item['id'])) {
                    if (ci['notes'] != null && ci['notes'].toString().isNotEmpty) {
                      resolvedNotes = ci['notes'].toString();
                      break;
                    }
                  }
                }
              }
            }
          } catch (_) {}
        }
        if (resolvedNotes == 'null') resolvedNotes = '';

        enriched.add({
          ...item,
          'expected_amount': estimatedCost,
          'resolved_estimated': estimatedCost,
          'settlement_notes': resolvedNotes.isNotEmpty ? resolvedNotes : (item['settlement_notes'] ?? ''),
          'base_amount': ((item['base_amount'] as num?)?.toDouble() ?? 0.0) > 0
              ? (item['base_amount'] as num).toDouble()
              : estimatedCost,
          'order_number': poNum,
          'product_name': poProd,
          'order_date': poDate.length >= 10 ? poDate.substring(0, 10) : poDate,
          'order_display': 'أمر تعبئة #$poNum${poProd.isNotEmpty ? " ($poProd)" : ""}',
          'matches_account': true,
        });
      }

      if (mounted) {
        setState(() {
          _settlementRows = enriched;
          _syncSettlementControllers(enriched);
          _isLoadingSettlement = false;
        });
      }
    } catch (e, st) {
      debugPrint('❌ Error in _loadSettlementItems: $e\n$st');
      if (mounted) {
        setState(() {
          _settlementError = 'تعذر تحميل بنود التكاليف للأوامر: $e';
          _isLoadingSettlement = false;
        });
      }
    }
  }

  void _syncSettlementControllers(List<Map<String, dynamic>> items) {
    for (final item in items) {
      final key = item['id'];
      if (key == null) continue;
      final isLocked = _isItemLocked(item);
      final double? actVal = (item['actual_amount'] as num?)?.toDouble();
      final qVal = (item['actual_quantity'] as num?)?.toDouble() ?? 1.0;
      final double? uPrice = (item['actual_unit_price'] as num?)?.toDouble() ??
          (item['unit_price'] as num?)?.toDouble() ??
          (actVal != null && qVal > 0 ? actVal / qVal : null);

      String notes = (item['detailed_notes'] ?? item['settlement_notes'] ?? item['notes'] ?? item['invoice_ref'] ?? '').toString();
      if ((notes.isEmpty || notes == 'null') && item['currency_snapshot'] is Map) {
        notes = (item['currency_snapshot']['notes'] ?? '').toString();
      }
      if (notes == 'null') notes = '';

      DateTime? dt;
      final rawDt = item['actual_date_time'] ?? item['reconciled_at'];
      if (rawDt != null) dt = DateTime.tryParse(rawDt.toString());
      _itemDateTimes[key] = dt ?? DateTime.now();

      final actText = (actVal != null && actVal > 0) ? actVal.toStringAsFixed(2) : '';
      if (!_itemActualCtrls.containsKey(key)) {
        _itemActualCtrls[key] = TextEditingController(text: actText);
      } else if (isLocked) {
        _itemActualCtrls[key]!.text = actText;
      }

      if (!_itemQtyCtrls.containsKey(key)) {
        _itemQtyCtrls[key] = TextEditingController(
          text: qVal == qVal.roundToDouble() ? qVal.toInt().toString() : qVal.toString(),
        );
      } else if (isLocked) {
        _itemQtyCtrls[key]!.text = qVal == qVal.roundToDouble() ? qVal.toInt().toString() : qVal.toString();
      }

      final priceText = (uPrice != null && uPrice > 0) ? uPrice.toStringAsFixed(2) : '';
      if (!_itemUnitPriceCtrls.containsKey(key)) {
        _itemUnitPriceCtrls[key] = TextEditingController(text: priceText);
      } else if (isLocked) {
        _itemUnitPriceCtrls[key]!.text = priceText;
      }

      if (!_itemNotesCtrls.containsKey(key)) {
        _itemNotesCtrls[key] = TextEditingController(
          text: (notes.isNotEmpty && notes != 'null') ? notes : '',
        );
      } else if (isLocked && notes.isNotEmpty && notes != 'null') {
        _itemNotesCtrls[key]!.text = notes;
      }

      if (!_itemUnitPriceBreakdowns.containsKey(key)) {
        if (item['currency_snapshot'] is Map && item['currency_snapshot']['unit_prices'] is List) {
          final list = (item['currency_snapshot']['unit_prices'] as List)
              .map((e) => (e as num).toDouble())
              .toList();
          if (list.isNotEmpty) _itemUnitPriceBreakdowns[key] = list;
        } else if (item['currency_snapshot'] is Map && item['currency_snapshot']['price_breakdown'] is List) {
          final list = (item['currency_snapshot']['price_breakdown'] as List)
              .map((e) => (e as num).toDouble())
              .toList();
          if (list.isNotEmpty) _itemUnitPriceBreakdowns[key] = list;
        }
      }
    }
  }

  TextEditingController _getItemActualCtrl(dynamic key, Map<String, dynamic> item) {
    if (!_itemActualCtrls.containsKey(key)) {
      final actVal = (item['actual_amount'] as num?)?.toDouble();
      _itemActualCtrls[key] = TextEditingController(
        text: (actVal != null && actVal > 0) ? actVal.toStringAsFixed(2) : '',
      );
    }
    return _itemActualCtrls[key]!;
  }

  TextEditingController _getItemQtyCtrl(dynamic key, Map<String, dynamic> item) {
    if (!_itemQtyCtrls.containsKey(key)) {
      final qVal = (item['actual_quantity'] as num?)?.toDouble() ?? 1.0;
      _itemQtyCtrls[key] = TextEditingController(
        text: qVal == qVal.roundToDouble() ? qVal.toInt().toString() : qVal.toString(),
      );
    }
    return _itemQtyCtrls[key]!;
  }

  TextEditingController _getItemUnitPriceCtrl(dynamic key, Map<String, dynamic> item) {
    if (!_itemUnitPriceCtrls.containsKey(key)) {
      final actVal = (item['actual_amount'] as num?)?.toDouble();
      final qVal = (item['actual_quantity'] as num?)?.toDouble() ?? 1.0;
      final uPrice = (item['actual_unit_price'] as num?)?.toDouble() ??
          (item['unit_price'] as num?)?.toDouble() ??
          (actVal != null && qVal > 0 ? actVal / qVal : null);
      _itemUnitPriceCtrls[key] = TextEditingController(
        text: (uPrice != null && uPrice > 0) ? uPrice.toStringAsFixed(2) : '',
      );
    }
    return _itemUnitPriceCtrls[key]!;
  }

  DateTime _getItemDateTime(dynamic key, Map<String, dynamic> item) {
    if (!_itemDateTimes.containsKey(key)) {
      DateTime? dt;
      final rawDt = item['actual_date_time'] ?? item['reconciled_at'];
      if (rawDt != null) {
        dt = DateTime.tryParse(rawDt.toString());
      }
      _itemDateTimes[key] = dt ?? DateTime.now();
    }
    return _itemDateTimes[key]!;
  }

  void _onRowQtyOrPriceChanged(dynamic key, Map<String, dynamic> item) {
    final qtyStr = _getItemQtyCtrl(key, item).text.replaceAll(',', '').trim();
    final priceStr = _getItemUnitPriceCtrl(key, item).text.replaceAll(',', '').trim();
    final qty = double.tryParse(qtyStr) ?? 1.0;
    final price = double.tryParse(priceStr) ?? 0.0;
    final intQty = qty.toInt();
    final isMultiUnit = qty > 1 && intQty > 1 && (qty - intQty).abs() < 0.001;

    if (isMultiUnit) {
      // Adjust breakdown list if needed
      var breakdown = _itemUnitPriceBreakdowns[key];
      if (breakdown == null || breakdown.length != intQty) {
        final oldList = breakdown ?? [];
        final defaultPrice = price > 0 ? price : 0.0;
        final newList = List<double>.generate(intQty, (i) {
          if (i < oldList.length && oldList[i] > 0) return oldList[i];
          return defaultPrice;
        });
        _itemUnitPriceBreakdowns[key] = newList;
      }

      final sum = _itemUnitPriceBreakdowns[key]!.fold(0.0, (acc, p) => acc + p);
      if (sum > 0) {
        _getItemActualCtrl(key, item).text = sum.toStringAsFixed(2);
        _getItemUnitPriceCtrl(key, item).text = (sum / intQty).toStringAsFixed(2);
      } else if (price > 0) {
        final total = qty * price;
        _getItemActualCtrl(key, item).text = total.toStringAsFixed(2);
      }
    } else {
      _itemUnitPriceBreakdowns.remove(key);
      if (price > 0 && qty > 0) {
        final total = qty * price;
        _getItemActualCtrl(key, item).text = total.toStringAsFixed(2);
      }
    }

    _modifiedItemKeys.add(key);
    setState(() {});
  }

  void _onRowActualChanged(dynamic key, Map<String, dynamic> item) {
    final actStr = _getItemActualCtrl(key, item).text.replaceAll(',', '').trim();
    final qtyStr = _getItemQtyCtrl(key, item).text.replaceAll(',', '').trim();
    final act = double.tryParse(actStr) ?? 0.0;
    final qty = double.tryParse(qtyStr) ?? 1.0;
    final intQty = qty.toInt();
    final isMultiUnit = qty > 1 && intQty > 1 && (qty - intQty).abs() < 0.001;

    if (qty > 0 && act > 0) {
      final price = act / qty;
      _getItemUnitPriceCtrl(key, item).text = price.toStringAsFixed(2);
      if (isMultiUnit) {
        _itemUnitPriceBreakdowns[key] = List<double>.filled(intQty, price);
      }
    }
    _modifiedItemKeys.add(key);
    setState(() {});
  }

  /// نافذة منبثقة تفاعلية لإدخال أسعار الوحدات المتعددة عند زيادة الكمية الفعلية عن 1
  Future<void> _showUnitPriceBreakdownDialog(dynamic key, Map<String, dynamic> item, int count) async {
    final isDark = AppTheme.isDark(context);
    final est = _getEstimatedCost(item);
    final poNum = item['order_number']?.toString() ?? '-';
    final itemName = (item['name'] ?? item['item_name'] ?? 'بند تكلفة').toString();
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
                            'أمر تعبئة #$poNum | $itemName',
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

                        // قائمة الحقول المتولدة بعدد الكمية
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

                        // صندوق التجميع والإجمالي اللحظي
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

  TextEditingController _getItemNotesCtrl(dynamic key, Map<String, dynamic> item) {
    if (!_itemNotesCtrls.containsKey(key)) {
      String notes = (item['detailed_notes'] ?? item['settlement_notes'] ?? item['notes'] ?? item['invoice_ref'] ?? '').toString();
      if ((notes.isEmpty || notes == 'null') && item['currency_snapshot'] is Map) {
        notes = (item['currency_snapshot']['notes'] ?? '').toString();
      }
      if (notes == 'null') notes = '';
      _itemNotesCtrls[key] = TextEditingController(
        text: (notes.isNotEmpty && notes != 'null') ? notes : '',
      );
    }
    return _itemNotesCtrls[key]!;
  }

  /// نافذة منبثقة لإدخال كلمة المرور السرية لفك قفل البنود المقفلة وإتاحة تعديلها
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
        for (final item in _filteredSettlementRows) {
          final k = item['id'];
          if (k != null) _unlockedItemKeys.add(k);
        }
        for (final item in _settlementRows) {
          final k = item['id'];
          if (k != null) _unlockedItemKeys.add(k);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تم التحقق بنجاح بكلمة المرور! تم فتح القفل لكافة البنود لإجراء التعديلات.',
              textDirection: TextDirection.rtl,
            ),
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else if (passwordCtrl.text.trim().isNotEmpty && passwordCtrl.text.trim() != _settlementUnlockPassword) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('كلمة المرور غير صحيحة! تم رفض العملية والإبقاء على البنود بحالة الإقفال.', textDirection: TextDirection.rtl),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _autoDistributeToAll() {
    final raw = _overallActualCtrl.text.replaceAll(',', '').trim();
    final totalAmount = double.tryParse(raw);
    if (totalAmount == null || totalAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى كتابة مبلغ إجمالي صحيح للتوزيع', textDirection: TextDirection.rtl),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    final rawQty = _overallQtyCtrl.text.replaceAll(',', '').trim();
    final totalQty = double.tryParse(rawQty) ?? 1.0;

    final rawPrice = _overallUnitPriceCtrl.text.replaceAll(',', '').trim();
    final masterPrice = double.tryParse(rawPrice) ?? (totalQty > 0 ? totalAmount / totalQty : totalAmount);

    final masterNotes = _overallNotesCtrl.text.trim();
    final masterDateTime = _overallInvoiceDateTime;

    final targetItems = _filteredSettlementRows;
    if (targetItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد بنود تكلفة لتوزيع المبلغ عليها', textDirection: TextDirection.rtl),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    // استثناء البنود المقفلة والمعتمدة مسبقاً (إلا إذا تم فك قفلها بكلمة المرور)
    final openItems = targetItems.where((i) {
      final key = i['id'];
      final isLocked = _isItemLocked(i);
      final isUnlocked = _unlockedItemKeys.contains(key);
      return !isLocked || isUnlocked;
    }).toList();

    if (openItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('جميع البنود المعروضة مقفلة ومعتمدة مسبقاً. اضغط على أي خانة مقفلة لإدخال كلمة المرور وإتاحة التعديل عليها.', textDirection: TextDirection.rtl),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    final isProportional = _distributionMethod == 'proportional';
    final double totalEstimated = openItems.fold<double>(0.0, (sum, i) => sum + _getEstimatedCost(i));

    setState(() {
      for (final item in openItems) {
        final key = item['id'];
        if (key == null) continue;
        final est = _getEstimatedCost(item);

        double allocatedAmount;
        double allocatedQty;
        if (isProportional) {
          final ratio = totalEstimated > 0
              ? (est / totalEstimated)
              : (1.0 / openItems.length);
          allocatedAmount = ratio * totalAmount;
          allocatedQty = totalQty > 1 ? (ratio * totalQty) : 1.0;
        } else {
          allocatedAmount = totalAmount / openItems.length;
          allocatedQty = totalQty > 1 ? (totalQty / openItems.length) : 1.0;
        }

        final unitPrice = allocatedQty > 0 ? (allocatedAmount / allocatedQty) : masterPrice;

        _getItemActualCtrl(key, item).text = allocatedAmount.toStringAsFixed(2);
        _getItemQtyCtrl(key, item).text = allocatedQty == allocatedQty.roundToDouble()
            ? allocatedQty.toInt().toString()
            : allocatedQty.toStringAsFixed(2);
        _getItemUnitPriceCtrl(key, item).text = unitPrice.toStringAsFixed(2);
        _itemDateTimes[key] = masterDateTime;

        if (masterNotes.isNotEmpty) {
          _getItemNotesCtrl(key, item).text = masterNotes;
        }

        _modifiedItemKeys.add(key);
      }
    });

    final skippedLocked = targetItems.length - openItems.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isProportional
              ? 'تم توزيع EGP ${NumberFormat("#,##0.00").format(totalAmount)} بنجاح تناسبياً على ${openItems.length} بند مفتوح مع تحديث الكميات والأسعار والتاريخ${skippedLocked > 0 ? " (تم استثناء $skippedLocked بند مقفل)" : ""}'
              : 'تم توزيع EGP ${NumberFormat("#,##0.00").format(totalAmount)} بنجاح بالتساوي على ${openItems.length} بند مفتوح مع تحديث الكميات والأسعار والتاريخ${skippedLocked > 0 ? " (تم استثناء $skippedLocked بند مقفل)" : ""}',
          textDirection: TextDirection.rtl,
        ),
        backgroundColor: const Color(0xFF10B981),
      ),
    );
  }

  void _resetSettlementToEstimated() {
    int resetCount = 0;
    setState(() {
      for (final item in _filteredSettlementRows) {
        final key = item['id'];
        final isLocked = _isItemLocked(item);
        final isUnlocked = _unlockedItemKeys.contains(key);
        // تخطي البنود المقفلة إلا إذا تم فك قفلها بكلمة المرور
        if (isLocked && !isUnlocked) continue;
        if (key == null) continue;
        final est = _getEstimatedCost(item);
        _getItemActualCtrl(key, item).text = est > 0 ? est.toStringAsFixed(2) : '';
        _itemUnitPriceBreakdowns.remove(key);
        _modifiedItemKeys.add(key);
        resetCount++;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          resetCount > 0
              ? 'تمت استعادة القيم التقديرية الأصلية لـ $resetCount بند مفتوح'
              : 'لا توجد بنود مفتوحة للتراجع (جميع البنود مقفلة ومعتمدة مسبقاً)',
          textDirection: TextDirection.rtl,
        ),
        backgroundColor: resetCount > 0 ? AppTheme.primary : AppTheme.warning,
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredSettlementRows {
    var list = _settlementRows;
    if (_filterOnlyPending) {
      list = list.where((item) {
        final key = item['id'];
        final isLocked = _isItemLocked(item);
        final isUnlocked = _unlockedItemKeys.contains(key);
        return !isLocked || isUnlocked;
      }).toList();
    }
    final fromOrder = _settlementFromOrderId;
    final toOrder = _settlementToOrderId;
    if (fromOrder != null || toOrder != null) {
      list = list.where((item) {
        return OrderRangeFilterHelper.matchesOrderRange(
          orderNumber: item['order_number']?.toString(),
          packingOrderId: (item['packing_order_id'] as num?)?.toInt(),
          fromOrderId: fromOrder,
          toOrderId: toOrder,
        );
      }).toList();
    }
    if (_settlementSearchQuery.isEmpty) return list;
    final q = _normalizeArabic(_settlementSearchQuery);
    return list.where((item) {
      final orderNum = (item['order_number'] ?? '').toString().toLowerCase();
      final prod = _normalizeArabic((item['product_name'] ?? '').toString());
      final name = _normalizeArabic((item['name'] ?? item['item_name'] ?? '').toString());
      final cat = (item['category'] ?? '').toString().toLowerCase();
      final notes = _normalizeArabic((item['settlement_notes'] ?? '').toString());
      final inv = (item['invoice_ref'] ?? '').toString().toLowerCase();
      return orderNum.contains(q) || prod.contains(q) || name.contains(q) || cat.contains(q) || notes.contains(q) || inv.contains(q);
    }).toList();
  }

  /// اعتماد وتسوية بند تكلفة فردي مستقل
  Future<void> _settleSingleCostItem(Map<String, dynamic> item) async {
    final key = item['id'];
    if (key == null) return;

    final ctrl = _itemActualCtrls[key] ??
        _itemActualCtrls[key.toString()] ??
        _itemActualCtrls[int.tryParse(key.toString())];
    final rawText = ctrl?.text.replaceAll(',', '').trim() ?? '';
    double? actAmt = double.tryParse(rawText);
    if (actAmt == null || actAmt <= 0) {
      actAmt = (item['actual_amount'] as num?)?.toDouble() ??
          double.tryParse(item['actual_amount']?.toString() ?? '');
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

    final pId = item['packing_order_id'] is num
        ? (item['packing_order_id'] as num).toInt()
        : int.tryParse(item['packing_order_id']?.toString() ?? '');
    final costItemId = item['id'] is num
        ? (item['id'] as num).toInt()
        : int.tryParse(item['id']?.toString() ?? '');

    if (pId == null || costItemId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر تحديد أمر التعبئة أو معرّف بند التكلفة', textDirection: TextDirection.rtl),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    final notesCtrl = _getItemNotesCtrl(key, item);
    final notes = notesCtrl.text.trim().isNotEmpty
        ? notesCtrl.text.trim()
        : (item['detailed_notes'] ?? item['settlement_notes'] ?? item['notes'] ?? '').toString();

    final qtyStr = _getItemQtyCtrl(key, item).text.replaceAll(',', '').trim();
    final qty = double.tryParse(qtyStr) ?? (item['actual_quantity'] as num?)?.toDouble() ?? 1.0;

    final priceStr = _getItemUnitPriceCtrl(key, item).text.replaceAll(',', '').trim();
    final unitPrice = double.tryParse(priceStr) ??
        (item['actual_unit_price'] as num?)?.toDouble() ??
        (qty > 0 ? actAmt / qty : actAmt);

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
              'invoice_ref': item['invoice_ref'],
              'expense_account_id': int.tryParse(widget.account.id ?? ''),
            }
          ],
          generalNotes: 'اعتماد فردي مفصل للبند: ${(item['name'] ?? item['item_name'] ?? '')}$itemDesc بأمر #$pId',
        );
      } catch (rpcErr) {
        debugPrint('rpc_settle_packing_cost_variances warning: $rpcErr');
      }

      // تأكيد حالة القفل وتوثيق التفاصيل في جدول packing_order_cost_items
      final breakdown = _itemUnitPriceBreakdowns[key];
      final existingSnap = item['currency_snapshot'] is Map ? Map<String, dynamic>.from(item['currency_snapshot'] as Map) : <String, dynamic>{};
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

      // Synchronize detailed notes to account_ledger_entries
      if (notes.isNotEmpty) {
        try {
          final itemName = (item['name'] ?? item['item_name'] ?? '').toString();
          final invText = item['invoice_ref'] != null && item['invoice_ref'].toString().trim().isNotEmpty
              ? ' - مستند: ${item['invoice_ref'].toString().trim()}'
              : '';
          await Supabase.instance.client
              .from('account_ledger_entries')
              .update({
                'description': 'تسوية تكلفة - $itemName (أمر #$pId) - $notes$invText',
              })
              .like('description', '%$itemName%')
              .like('description', '%$pId%');
        } catch (syncErr) {
          debugPrint('⚠️ Error syncing detailed notes to account ledger: $syncErr');
        }
      }

      // تحديث الحالة محلياً فوراً لتتحول إلى معتمد ومقفل بدون تأخير
      for (final row in _settlementRows) {
        if (row['id'] == key || row['id']?.toString() == key?.toString()) {
          row['is_locked'] = true;
          row['cost_status'] = 'actual';
          row['reconciled_at'] = DateTime.now().toIso8601String();
          row['actual_amount'] = actAmt;
          row['actual_quantity'] = qty;
          row['actual_unit_price'] = unitPrice;
          row['actual_date_time'] = actualDateTime.toIso8601String();
          row['currency_snapshot'] = updatedSnap;
          if (notes.isNotEmpty) {
            row['settlement_notes'] = notes;
            row['detailed_notes'] = notes;
          }
        }
      }

      DataChangeEventBus.instance.notifyAccountsChanged();
      DataChangeEventBus.instance.notifyJournalEntriesChanged();
      DataChangeEventBus.instance.notifyTransportSuppliersChanged();
      DataChangeEventBus.instance.notifySuppliersChanged();

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

      await _loadLedger();
      await _loadSettlementItems(showAllOrders: _showAllOrders);
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

  Future<void> _deleteEstimatedCostItem(Map<String, dynamic> item) async {
    if (!SupplierDao.canDeleteEstimatedCostItemMap(item)) return;
    final key = item['id'];
    final int? costItemId = (key as num?)?.toInt();
    if (costItemId == null || costItemId <= 0) return;
    if (_deletingItemKeys.contains(key) || _settlingItemKeys.contains(key)) {
      return;
    }

    final itemName =
        (item['name'] ?? item['item_name'] ?? 'بند تكلفة').toString();
    final poNum = item['order_number']?.toString() ?? '-';
    final estAmt = _getEstimatedCost(item);

    final confirmed = await showDeleteEstimatedCostItemDialog(
      context,
      itemName: itemName,
      orderNumber: poNum,
      estimatedAmount: estAmt,
    );
    if (!confirmed || !mounted) return;

    setState(() => _deletingItemKeys.add(key));
    try {
      final int? packingOrderId = (item['packing_order_id'] as num?)?.toInt();
      await _supplierDao.deleteEstimatedCostItem(
        costItemId: costItemId,
        packingOrderId: packingOrderId,
      );

      if (!mounted) return;
      final actCtrl = _itemActualCtrls.remove(key);
      final qtyCtrl = _itemQtyCtrls.remove(key);
      final priceCtrl = _itemUnitPriceCtrls.remove(key);
      final notesCtrl = _itemNotesCtrls.remove(key);

      setState(() {
        _deletingItemKeys.remove(key);
        _settlementRows.removeWhere(
          (r) => (r['id'] as num?)?.toInt() == costItemId,
        );
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
            'تم حذف البند التقديري "$itemName" بنجاح',
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

  Future<void> _saveSettlements() async {
    final targetItems = _filteredSettlementRows;
    final List<Map<String, dynamic>> itemsToSettle = [];

    for (final item in targetItems) {
      final key = item['id'];
      if (key == null) continue;

      // فحص هل البند مقفل (باستثناء البنود المفتوحة صراحة بكلمة المرور)
      final isLocked = _isItemLocked(item);
      final isUnlocked = _unlockedItemKeys.contains(key) ||
          _unlockedItemKeys.contains(key.toString()) ||
          _unlockedItemKeys.contains(int.tryParse(key.toString()));
      if (isLocked && !isUnlocked) {
        continue;
      }

      final ctrl = _itemActualCtrls[key] ??
          _itemActualCtrls[key.toString()] ??
          _itemActualCtrls[int.tryParse(key.toString())];
      final raw = ctrl?.text.replaceAll(',', '').trim() ?? '';
      double? actAmt = double.tryParse(raw);
      if (actAmt == null || actAmt <= 0) {
        actAmt = (item['actual_amount'] as num?)?.toDouble() ??
            double.tryParse(item['actual_amount']?.toString() ?? '');
      }

      // البند غير مقفل والقيمة الفعلية المدخلة أكبر من الصفر
      if (actAmt != null && actAmt > 0) {
        final notesCtrl = _getItemNotesCtrl(key, item);
        final notesVal = notesCtrl.text.trim().isNotEmpty
            ? notesCtrl.text.trim()
            : (item['detailed_notes'] ?? item['settlement_notes'] ?? item['notes'] ?? '').toString();
        final qtyStr = _getItemQtyCtrl(key, item).text.replaceAll(',', '').trim();
        final qty = double.tryParse(qtyStr) ?? (item['actual_quantity'] as num?)?.toDouble() ?? 1.0;
        final priceStr = _getItemUnitPriceCtrl(key, item).text.replaceAll(',', '').trim();
        final unitPrice = double.tryParse(priceStr) ??
            (item['actual_unit_price'] as num?)?.toDouble() ??
            (qty > 0 ? actAmt / qty : actAmt);
        final dt = _getItemDateTime(key, item);

        itemsToSettle.add({
          ...item,
          'resolved_actual': actAmt,
          'resolved_qty': qty,
          'resolved_unit_price': unitPrice,
          'resolved_date_time': dt,
          'resolved_notes': notesVal,
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

    final double sumEst = itemsToSettle.fold(0.0, (s, i) => s + _getEstimatedCost(i));
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
            Text('سيتم اعتماد وترحيل وإقفال ${itemsToSettle.length} بند تكلفة عبر الأوامر المحددة.', style: const TextStyle(fontFamily: 'Cairo', fontSize: 13)),
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
      final List<Map<String, dynamic>> directItems = [];

      for (final item in itemsToSettle) {
        final poId = item['packing_order_id'] is num
            ? (item['packing_order_id'] as num).toInt()
            : int.tryParse(item['packing_order_id']?.toString() ?? '');
        final costItemId = item['id'] is num
            ? (item['id'] as num).toInt()
            : int.tryParse(item['id']?.toString() ?? '');
        final act = (item['resolved_actual'] as num).toDouble();
        final qty = (item['resolved_qty'] as num?)?.toDouble() ?? 1.0;
        final unitPrice = (item['resolved_unit_price'] as num?)?.toDouble() ?? (qty > 0 ? act / qty : act);
        final dt = (item['resolved_date_time'] as DateTime?) ?? DateTime.now();
        final notes = (item['resolved_notes'] ?? '').toString();

        if (poId != null && costItemId != null) {
          byOrder.putIfAbsent(poId, () => []).add({
            'cost_item_id': costItemId,
            'actual_amount': act,
            'actual_quantity': qty,
            'unit_price': unitPrice,
            'actual_date_time': dt.toIso8601String(),
            'notes': notes,
            'invoice_ref': item['invoice_ref'],
            'expense_account_id': int.tryParse(widget.account.id ?? ''),
          });
        } else if (costItemId != null) {
          directItems.add({
            'id': costItemId,
            'actual_amount': act,
            'actual_quantity': qty,
            'unit_price': unitPrice,
            'actual_date_time': dt.toIso8601String(),
            'notes': notes,
          });
        }
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
            generalNotes: 'تسوية مجمعة من تفاصيل الحساب: ${widget.account.code} - ${widget.account.name}',
          );
          settledCount += settlements.length;
          batchSucceeded = true;
        } catch (poErr) {
          debugPrint('Error settling packing order #$pId: $poErr');
        }

        // ضمان تحديث حالة القفل وتوثيق البيان في جدول packing_order_cost_items
        for (final s in settlements) {
          final cId = s['cost_item_id'];
          final sNotes = s['notes']?.toString().trim();
          final bDown = _itemUnitPriceBreakdowns[cId] ?? _itemUnitPriceBreakdowns[s['item_key']];
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
                if (bDown != null && bDown.isNotEmpty) 'currency_snapshot': {'unit_prices': bDown},
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
                  if (bDown != null && bDown.isNotEmpty) 'currency_snapshot': {'unit_prices': bDown},
                }).eq('id', cId);
                if (!batchSucceeded) settledCount++;
              } catch (_) {}
            }

            // Synchronize detailed notes to account_ledger_entries
            if (sNotes != null && sNotes.isNotEmpty) {
              try {
                await Supabase.instance.client
                    .from('account_ledger_entries')
                    .update({
                      'description': 'تسوية تكلفة (أمر #$pId) - $sNotes',
                    })
                    .like('description', '%$pId%');
              } catch (_) {}
            }
          }
        }
      }

      for (final d in directItems) {
        try {
          final dNotes = d['notes']?.toString().trim();
          await Supabase.instance.client.from('packing_order_cost_items').update({
            'actual_amount': d['actual_amount'],
            'cost_status': 'actual',
            if (dNotes != null && dNotes.isNotEmpty) 'settlement_notes': dNotes,
            if (dNotes != null && dNotes.isNotEmpty) 'detailed_notes': dNotes,
            'reconciled_at': DateTime.now().toIso8601String(),
            'is_locked': true,
            'locked_at': DateTime.now().toIso8601String(),
          }).eq('id', d['id']);
          settledCount++;
        } catch (_) {
          try {
            await Supabase.instance.client.from('packing_order_cost_items').update({
              'actual_amount': d['actual_amount'],
              'cost_status': 'actual',
              'reconciled_at': DateTime.now().toIso8601String(),
            }).eq('id', d['id']);
            settledCount++;
          } catch (_) {}
        }
      }

      // تحديث الحالة محلياً فوراً لجميع البنود المسواة لتتحول إلى معتمد ومقفل 🔒
      for (final sItem in itemsToSettle) {
        final sId = sItem['id'];
        for (final row in _settlementRows) {
          if (row['id'] == sId || row['id']?.toString() == sId?.toString()) {
            row['is_locked'] = true;
            row['cost_status'] = 'actual';
            row['reconciled_at'] = DateTime.now().toIso8601String();
            row['actual_amount'] = sItem['resolved_actual'];
            row['actual_quantity'] = sItem['resolved_qty'];
            row['actual_unit_price'] = sItem['resolved_unit_price'];
            row['actual_date_time'] = (sItem['resolved_date_time'] as DateTime?)?.toIso8601String();
            if ((sItem['resolved_notes']?.toString().trim() ?? '').isNotEmpty) {
              row['settlement_notes'] = sItem['resolved_notes'];
              row['detailed_notes'] = sItem['resolved_notes'];
            }
          }
        }
      }

      DataChangeEventBus.instance.notifyAccountsChanged();
      DataChangeEventBus.instance.notifyJournalEntriesChanged();
      DataChangeEventBus.instance.notifyTransportSuppliersChanged();
      DataChangeEventBus.instance.notifySuppliersChanged();

      _modifiedItemKeys.clear();
      _unlockedItemKeys.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم اعتماد وإقفال تسوية $settledCount بند تكلفة بنجاح وتحديث قيود اليومية!', textDirection: TextDirection.rtl),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }

      await _loadLedger();
      await _loadSettlementItems(showAllOrders: _showAllOrders);
    } catch (e, st) {
      debugPrint('❌ Error in _saveSettlements: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إتمام تسوية التكاليف: $e', textDirection: TextDirection.rtl), backgroundColor: AppTheme.danger),
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
        Text(label, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Color(0xFF64748B))),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12.5,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    final isDark = AppTheme.isDark(context);
    final count = _settlementRows.length;
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.getBorderColor(context)),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: isMobile,
        tabAlignment: isMobile ? TabAlignment.start : TabAlignment.fill,
        indicator: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: isDark ? Colors.white70 : const Color(0xFF64748B),
        labelStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
        tabs: [
          const Tab(
            icon: Icon(Icons.receipt_long_rounded, size: 18),
            text: 'كشف الحساب القياسي',
          ),
          Tab(
            icon: const Icon(Icons.balance_rounded, size: 18),
            text: count > 0
                ? (isMobile ? 'تسوية التكاليف ($count)' : 'تسوية التكاليف (التقديري / الفعلي) ($count بند)')
                : 'تسوية التكاليف (التقديري / الفعلي)',
          ),
        ],
      ),
    );
  }

  Widget _buildStandardLedgerTab() {
    final isMobile = MediaQuery.of(context).size.width < 900;

    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.accent),
            SizedBox(height: 12),
            Text(
              'جاري جلب قيود اليومية...',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontFamily: 'Cairo',
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    } else if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                color: AppTheme.danger, size: 48),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(
                color: AppTheme.danger,
                fontFamily: 'Cairo',
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadLedger,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('إعادة المحاولة',
                  style: TextStyle(fontFamily: 'Cairo')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
              ),
            ),
          ],
        ),
      );
    }

    if (isMobile) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFilterBar(),
            const SizedBox(height: 12),
            _buildEntriesContent(isMobile: true),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFilterBar(),
        const SizedBox(height: 16),
        Expanded(
          child: _buildEntriesContent(isMobile: false),
        ),
      ],
    );
  }

  Widget _buildMultiOrderSettlementTab() {
    final isDark = AppTheme.isDark(context);
    final isMobile = MediaQuery.of(context).size.width < 900;

    if (_isLoadingSettlement) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.primary),
            SizedBox(height: 12),
            Text(
              'جاري تحميل بنود وتكاليف الأوامر...',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontFamily: 'Cairo',
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    if (_settlementError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppTheme.danger, size: 48),
            const SizedBox(height: 12),
            Text(
              _settlementError!,
              style: const TextStyle(
                color: AppTheme.danger,
                fontFamily: 'Cairo',
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadSettlementItems,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('إعادة المحاولة', style: TextStyle(fontFamily: 'Cairo')),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            ),
          ],
        ),
      );
    }

    final displayItems = _filteredSettlementRows;

    if (isMobile) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSettlementTopDistributionBar(isDark),
            const SizedBox(height: 12),
            _buildSettlementKpiRibbon(displayItems, isDark),
            const SizedBox(height: 12),
            SizedBox(
              height: 420,
              child: displayItems.isEmpty
                  ? _buildEmptySettlementState(isDark)
                  : _buildMultiOrderSettlementTable(displayItems, isDark),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 1. Top Header Auto-Distribution Bar ──
        _buildSettlementTopDistributionBar(isDark),
        const SizedBox(height: 12),

        // ── 2. Summary KPI Ribbon ──
        _buildSettlementKpiRibbon(displayItems, isDark),
        const SizedBox(height: 12),

        // ── 3. Table of Orders & Items ──
        Expanded(
          child: displayItems.isEmpty
              ? _buildEmptySettlementState(isDark)
              : _buildMultiOrderSettlementTable(displayItems, isDark),
        ),
      ],
    );
  }

  Widget _buildSettlementTopDistributionBar(bool isDark) {
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
          LayoutBuilder(
            builder: (context, constraints) {
              final screenW = MediaQuery.of(context).size.width;
              final effectiveW = constraints.maxWidth.isFinite ? math.min(constraints.maxWidth, screenW) : screenW;
              final isVeryNarrow = effectiveW < 680;
              final isNarrow = effectiveW < 900;

              if (isVeryNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.receipt_long_rounded, color: AppTheme.primary, size: 18),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'الفاتورة الفعلية والتوزيع التلقائي',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.getTextPrimary(context),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _showUnlockPasswordDialog,
                        icon: const Icon(Icons.lock_open_rounded, size: 14, color: Color(0xFF0EA5E9)),
                        label: const Text(
                          'تعديل المقفل 🔒',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0EA5E9),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF0EA5E9)),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.receipt_long_rounded, color: AppTheme.primary, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isNarrow
                          ? 'الفاتورة الفعلية والتوزيع التلقائي'
                          : 'بيانات الفاتورة الفعلية الشاملة وأدوات التوزيع التلقائي لكافة الأوامر دفعة واحدة',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: isNarrow ? 12 : 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.getTextPrimary(context),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // زر فك قفل الجميع بكلمة المرور
                  OutlinedButton.icon(
                    onPressed: _showUnlockPasswordDialog,
                    icon: const Icon(Icons.lock_open_rounded, size: 14, color: Color(0xFF0EA5E9)),
                    label: Text(
                      isNarrow ? 'تعديل المقفل 🔒' : 'إتاحة تعديل المقفل 🔒',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: isNarrow ? 10.5 : 11,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0EA5E9),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF0EA5E9)),
                      padding: EdgeInsets.symmetric(horizontal: isNarrow ? 8 : 10, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          // Master Invoice Inputs (Amount, Qty, Unit Price, Date/Time, Notes)
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
                    hintText: 'مثال: فاتورة كهرباء شهر 10...',
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
          const SizedBox(height: 10),
          // Action & Filter row
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilterChip(
                    avatar: const Icon(Icons.all_inbox_rounded, size: 14),
                    label: const Text(
                      'كافة أوامر التعبئة',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    selected: _showAllOrders,
                    onSelected: (val) {
                      setState(() {
                        _showAllOrders = true;
                        _filterOnlyPending = false;
                        _settlementFromOrderCtrl.clear();
                        _settlementToOrderCtrl.clear();
                      });
                      _loadSettlementItems(
                        showAllOrders: true,
                        applyOrderRangeToQuery: false,
                      );
                    },
                    selectedColor: AppTheme.primary.withValues(alpha: 0.18),
                    checkmarkColor: AppTheme.primary,
                  ),
                  const SizedBox(width: 6),
                  FilterChip(
                    avatar: const Icon(Icons.pending_actions_rounded, size: 14),
                    label: const Text(
                      'غير المسواة فقط',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 11),
                    ),
                    selected: _filterOnlyPending,
                    onSelected: (val) {
                      setState(() {
                        _filterOnlyPending = val;
                      });
                    },
                    selectedColor: AppTheme.warning.withValues(alpha: 0.18),
                    checkmarkColor: AppTheme.warning,
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OrderRangeFilterBar(
                    fromController: _settlementFromOrderCtrl,
                    toController: _settlementToOrderCtrl,
                    isDark: isDark,
                    activeColor: AppTheme.primary,
                    onChanged: () {
                      setState(() {});
                      if (_loadedSettlementWithOrderRange &&
                          _settlementFromOrderId == null &&
                          _settlementToOrderId == null) {
                        _loadSettlementItems(
                          showAllOrders: _showAllOrders,
                          applyOrderRangeToQuery: false,
                        );
                      }
                    },
                    onApplyQuery: () => _loadSettlementItems(
                      showAllOrders: _showAllOrders,
                    ),
                    onClear: () {
                      setState(() {});
                      if (_loadedSettlementWithOrderRange) {
                        _loadSettlementItems(
                          showAllOrders: _showAllOrders,
                          applyOrderRangeToQuery: false,
                        );
                      }
                    },
                  ),
                  SizedBox(
                    width: 170,
                    height: 36,
                    child: TextField(
                      controller: _settlementSearchCtrl,
                      onChanged: (val) => setState(() => _settlementSearchQuery = val.trim()),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11.5,
                        color: AppTheme.getTextPrimary(context),
                      ),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        hintText: 'بحث بالأمر أو البند أو البيان...',
                        hintStyle: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10.5,
                          color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                        ),
                        prefixIcon: const Icon(Icons.search, size: 16),
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
                    onPressed: (_isPrintingSettlement || _isLoadingSettlement) ? null : _printCostSettlementPdf,
                    icon: _isPrintingSettlement
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.picture_as_pdf_rounded, size: 16),
                    label: Text(
                      _isPrintingSettlement ? 'جاري التجهيز...' : 'طباعة تسوية التكاليف (PDF)',
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
      ),
    );
  }

  Widget _buildSettlementKpiRibbon(List<Map<String, dynamic>> items, bool isDark) {
    final distinctOrders = items.map((i) => i['packing_order_id']).whereType<int>().toSet().length;
    double totalEst = 0.0;
    double totalAct = 0.0;
    int lockedCount = 0;
    int pendingCount = 0;

    for (final i in items) {
      final key = i['id'];
      final e = _getEstimatedCost(i);
      final isLocked = _isItemLocked(i);
      final ctrl = _itemActualCtrls[key];
      double? a;
      if (ctrl != null && ctrl.text.trim().isNotEmpty) {
        a = double.tryParse(ctrl.text.replaceAll(',', '').trim());
      } else if (isLocked || i['actual_amount'] != null) {
        a = (i['actual_amount'] as num?)?.toDouble();
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
          Row(
            mainAxisSize: MainAxisSize.min,
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

  Widget _buildMultiOrderSettlementTable(List<Map<String, dynamic>> items, bool isDark) {
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
                  label: Text('أمر التعبئة / العملية', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context))),
                ),
                DataColumn(
                  label: Text('بند التكلفة', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context))),
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
                final key = item['id'];
                final poNum = item['order_number']?.toString() ?? '-';
                final poProd = item['product_name']?.toString() ?? '';
                final itemName = (item['name'] ?? item['item_name'] ?? 'بند تكلفة').toString();
                final category = (item['category'] ?? '').toString();

                final est = _getEstimatedCost(item);

                final actualCtrl = _getItemActualCtrl(key, item);
                final qtyCtrl = _getItemQtyCtrl(key, item);
                final unitPriceCtrl = _getItemUnitPriceCtrl(key, item);
                final notesCtrl = _getItemNotesCtrl(key, item);
                final itemDateTime = _getItemDateTime(key, item);

                final rawActText = actualCtrl.text.replaceAll(',', '').trim();
                final double? parsedAct = double.tryParse(rawActText);
                final double? dbAct = (item['actual_amount'] as num?)?.toDouble();
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
                    SupplierDao.canDeleteEstimatedCostItemMap(item);
                final isDeleting = _deletingItemKeys.contains(key);

                return DataRow(
                  cells: [
                    // 1. Order Number & Product
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
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
                          if (poProd.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                poProd,
                                style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: isDark ? Colors.white70 : const Color(0xFF475569)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // 2. Cost item name & category
                    DataCell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            itemName,
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context)),
                          ),
                          if (category.isNotEmpty)
                            Text(
                              category,
                              style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: AppTheme.getTextSecondary(context)),
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

  Widget _buildEmptySettlementState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.assignment_turned_in_outlined, size: 54, color: AppTheme.getTextSecondary(context).withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(
            'لا توجد بنود تكاليف معلقة للتسوية',
            style: TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context)),
          ),
          const SizedBox(height: 6),
          Text(
            'لم يتم العثور على بنود تكلفة لأوامر التعبئة تطابق (${widget.account.name}).\nيمكنك الضغط على زر "كافة أوامر التعبئة" بالأعلى لإعادة التحديث.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppTheme.getTextSecondary(context)),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _showAllOrders = true;
                _filterOnlyPending = false;
                _settlementFromOrderCtrl.clear();
                _settlementToOrderCtrl.clear();
              });
              _loadSettlementItems(
                showAllOrders: true,
                applyOrderRangeToQuery: false,
              );
            },
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text(
              'تحديث كافة أوامر التعبئة لهذا الحساب',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogHeader() {
    final isDark = AppTheme.isDark(context);
    final account = widget.account;
    final typeColor = _getAccountTypeColor(account.type);
    final typeLabel = _getAccountTypeLabel(account.type);

    final buttons = <Widget>[
      if (_tabController.index == 1) ...[
        ElevatedButton.icon(
          onPressed: (_isPrintingSettlement || _isLoadingSettlement)
              ? null
              : _printCostSettlementPdf,
          icon: _isPrintingSettlement
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.picture_as_pdf_rounded, size: 16),
          label: Text(
            _isPrintingSettlement ? 'جاري التجهيز...' : 'طباعة تسوية التكاليف (PDF)',
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
            foregroundColor: Colors.white,
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: (_isPrinting || _isLoading) ? null : _printAccountStatementPdf,
          icon: const Icon(Icons.receipt_long_rounded, size: 16),
          label: const Text(
            'كشف الحساب (PDF)',
            style: TextStyle(fontFamily: 'Cairo', fontSize: 11),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.getTextPrimary(context),
            side: BorderSide(color: AppTheme.getBorderColor(context)),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ] else ...[
        ElevatedButton.icon(
          onPressed: (_isPrinting || _isLoading) ? null : _printAccountStatementPdf,
          icon: _isPrinting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.picture_as_pdf_rounded, size: 16),
          label: Text(
            _isPrinting ? 'جاري التجهيز...' : 'طباعة كشف الحساب (PDF)',
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
            foregroundColor: Colors.white,
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        if (_settlementRows.isNotEmpty) ...[
          OutlinedButton.icon(
            onPressed: (_isPrintingSettlement || _isLoadingSettlement)
                ? null
                : _printCostSettlementPdf,
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 16, color: Color(0xFFDC2626)),
            label: const Text(
              'تسوية التكاليف (PDF)',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 11),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
              side: const BorderSide(color: Color(0xFFDC2626)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ],
      OutlinedButton.icon(
        onPressed: () {
          if (context.canPop()) context.pop();
          context.push(RoutePaths.generalLedger, extra: {
            'accountId': account.code,
            'accountCode': account.code,
            'accountName': account.displayName,
          });
        },
        icon: const Icon(Icons.menu_book, size: 16),
        label: const Text(
          'دفتر الأستاذ الكامل',
          style: TextStyle(fontFamily: 'Cairo', fontSize: 12),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.accent,
          side: const BorderSide(color: AppTheme.accent),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 1180;

        if (isNarrow) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.getCardBg(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.getBorderColor(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        widget.isBranch ? Icons.account_tree : Icons.receipt_long,
                        color: typeColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        account.code,
                        style: const TextStyle(
                          color: AppTheme.accent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        account.entityHeaderTitle,
                        style: TextStyle(
                          color: AppTheme.getTextPrimary(context),
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          fontFamily: 'Cairo',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: _loadLedger,
                      icon: Icon(Icons.refresh, color: AppTheme.getTextSecondary(context), size: 18),
                      tooltip: 'تحديث الحركات',
                    ),
                    IconButton(
                      onPressed: () { if (context.canPop()) context.pop(); },
                      icon: Icon(Icons.close, color: AppTheme.getTextSecondary(context), size: 20),
                      tooltip: 'إغلاق',
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        typeLabel,
                        style: TextStyle(
                          color: typeColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ),
                    if (widget.isBranch) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'فرع رئيسي (${widget.allBranchAccounts.length} حسابات)',
                          style: const TextStyle(
                            color: Colors.purpleAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: buttons,
                ),
              ],
            ),
          );
        }

        // Desktop layout
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.getCardBg(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.getBorderColor(context)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  widget.isBranch ? Icons.account_tree : Icons.receipt_long,
                  color: typeColor,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            account.code,
                            style: const TextStyle(
                              color: AppTheme.accent,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            account.entityHeaderTitle,
                            style: TextStyle(
                              color: AppTheme.getTextPrimary(context),
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              fontFamily: 'Cairo',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: typeColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            typeLabel,
                            style: TextStyle(
                              color: typeColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                        if (widget.isBranch) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.purple.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'فرع رئيسي (${widget.allBranchAccounts.length} حسابات)',
                              style: const TextStyle(
                                color: Colors.purpleAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.isBranch
                          ? 'عرض كافة قيود اليومية والحركات المالية المندرجة تحت هذا الفرع وجميع فروعه الفرعية'
                          : 'سجل حركات وقيود اليومية الخاصة بهذا الحساب المحاسبي',
                      style: TextStyle(
                        color: AppTheme.getTextSecondary(context),
                        fontSize: 12,
                        fontFamily: 'Cairo',
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ...buttons.map((b) => Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: b)),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _loadLedger,
                icon: Icon(Icons.refresh, color: AppTheme.getTextSecondary(context), size: 20),
                tooltip: 'تحديث الحركات',
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: () { if (context.canPop()) context.pop(); },
                icon: Icon(Icons.close, color: AppTheme.getTextSecondary(context), size: 22),
                tooltip: 'إغلاق',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterBar() {
    final isDark = AppTheme.isDark(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.getCardBg(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.getBorderColor(context)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Search box
          SizedBox(
            width: 220,
            height: 36,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              style: TextStyle(
                  color: AppTheme.getTextPrimary(context),
                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                  fontFamily: 'Cairo',
                  fontSize: 12),
              decoration: InputDecoration(
                hintText: 'بحث بالقيد أو البيان...',
                hintStyle: TextStyle(
                    color: AppTheme.getTextMuted(context),
                    fontSize: 11,
                    fontFamily: 'Cairo'),
                prefixIcon: Icon(Icons.search,
                    color: isDark ? AppTheme.accent : const Color(0xFF0F766E), size: 16),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close,
                            size: 14, color: AppTheme.getTextSecondary(context)),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppTheme.getBorderColor(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppTheme.getBorderColor(context)),
                ),
              ),
            ),
          ),

          // Date range
          InkWell(
            onTap: _pickDateRange,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.getBorderColor(context)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_month,
                      size: 16, color: isDark ? AppTheme.accent : const Color(0xFF0F766E)),
                  const SizedBox(width: 6),
                  Text(
                    _fromDate == null && _toDate == null
                        ? 'كل الفترات'
                        : '${_fromDate != null ? DateFormat('yyyy/MM/dd').format(_fromDate!) : 'البداية'}  -  ${_toDate != null ? DateFormat('yyyy/MM/dd').format(_toDate!) : 'الآن'}',
                    style: TextStyle(
                      color: AppTheme.getTextPrimary(context),
                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                      fontFamily: 'Cairo',
                      fontSize: 11.5,
                    ),
                  ),
                  if (_fromDate != null || _toDate != null) ...[
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _fromDate = null;
                          _toDate = null;
                        });
                        _loadLedger();
                      },
                      child: Icon(Icons.close,
                          size: 14, color: AppTheme.getTextSecondary(context)),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Quick Date Presets
          _buildFilterChip(
            label: 'هذا الشهر',
            isSelected: _isCurrentMonthSelected(),
            onTap: () {
              final now = DateTime.now();
              setState(() {
                _fromDate = DateTime(now.year, now.month, 1);
                _toDate = DateTime(now.year, now.month + 1, 0);
              });
              _loadLedger();
            },
          ),
          _buildFilterChip(
            label: 'هذا العام',
            isSelected: _isCurrentYearSelected(),
            onTap: () {
              final now = DateTime.now();
              setState(() {
                _fromDate = DateTime(now.year, 1, 1);
                _toDate = DateTime(now.year, 12, 31);
              });
              _loadLedger();
            },
          ),

          // Type filter (All / Debit / Credit)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: isDark ? null : Border.all(color: AppTheme.getBorderColor(context)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTypeSegment('all', 'الكل'),
                _buildTypeSegment('debit', 'مدين (من حـ/)'),
                _buildTypeSegment('credit', 'دائن (إلى حـ/)'),
              ],
            ),
          ),

          // Currency filter segment (الكل - ج.م / USD / EUR ...)
          if (_availableCurrencies.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: isDark ? null : Border.all(color: AppTheme.getBorderColor(context)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildCurrencySegment('ALL', 'الكل (ج.م)'),
                  for (final c in _availableCurrencies)
                    _buildCurrencySegment(c, c),
                ],
              ),
            ),

          // Sub-account filter (if branch)
          if (widget.isBranch && widget.allBranchAccounts.length > 1)
            DropdownButtonHideUnderline(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.getBorderColor(context)),
                  borderRadius: BorderRadius.circular(8),
                  color: isDark ? null : Colors.white,
                ),
                child: DropdownButton<String?>(
                  value: _selectedSubAccountId,
                  hint: Text(
                    'تصفية بالحساب الفرعي',
                    style: TextStyle(
                      color: AppTheme.getTextSecondary(context),
                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                      fontFamily: 'Cairo',
                      fontSize: 11.5,
                    ),
                  ),
                  dropdownColor: AppTheme.getCardBg(context),
                  style: TextStyle(
                    color: AppTheme.getTextPrimary(context),
                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                    fontFamily: 'Cairo',
                    fontSize: 12,
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text('جميع الحسابات التابعة',
                          style: TextStyle(
                              color: AppTheme.getTextPrimary(context),
                              fontWeight: isDark ? FontWeight.normal : FontWeight.bold)),
                    ),
                    ...widget.allBranchAccounts.map(
                      (acc) => DropdownMenuItem<String?>(
                        value: acc.id,
                        child: Text('${acc.code} - ${acc.displayName}',
                            style: TextStyle(
                                color: AppTheme.getTextPrimary(context),
                                fontWeight: isDark ? FontWeight.normal : FontWeight.bold)),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _selectedSubAccountId = val;
                    });
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDark = AppTheme.isDark(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? AppTheme.accent.withValues(alpha: 0.2) : const Color(0xFFCCFBF1))
              : (isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? (isDark ? AppTheme.accent : const Color(0xFF0F766E))
                : AppTheme.getBorderColor(context),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? (isDark ? AppTheme.accent : const Color(0xFF0F766E))
                : AppTheme.getTextSecondary(context),
            fontSize: 11,
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildTypeSegment(String type, String label) {
    final isDark = AppTheme.isDark(context);
    final isSelected = _selectedTypeFilter == type;
    return InkWell(
      onTap: () => setState(() => _selectedTypeFilter = type),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? (isDark ? AppTheme.primary : const Color(0xFF0284C7)) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppTheme.getTextSecondary(context),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cairo',
          ),
        ),
      ),
    );
  }

  Widget _buildCurrencySegment(String curr, String label) {
    final isDark = AppTheme.isDark(context);
    final isSelected = _selectedCurrency == curr;
    return InkWell(
      onTap: () {
        if (_selectedCurrency != curr) {
          setState(() => _selectedCurrency = curr);
          _loadLedger();
        }
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? AppTheme.accent.withValues(alpha: 0.25) : const Color(0xFFCCFBF1))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isSelected ? Border.all(color: isDark ? AppTheme.accent : const Color(0xFF0F766E)) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? (isDark ? AppTheme.accent : const Color(0xFF0F766E))
                : AppTheme.getTextSecondary(context),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cairo',
          ),
        ),
      ),
    );
  }

  bool _isCurrentMonthSelected() {
    if (_fromDate == null || _toDate == null) return false;
    final now = DateTime.now();
    return _fromDate!.year == now.year &&
        _fromDate!.month == now.month &&
        _fromDate!.day == 1 &&
        _toDate!.month == now.month;
  }

  bool _isCurrentYearSelected() {
    if (_fromDate == null || _toDate == null) return false;
    final now = DateTime.now();
    return _fromDate!.year == now.year &&
        _fromDate!.month == 1 &&
        _fromDate!.day == 1 &&
        _toDate!.year == now.year &&
        _toDate!.month == 12;
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDateRange: _fromDate != null && _toDate != null
          ? DateTimeRange(start: _fromDate!, end: _toDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.accent,
              onPrimary: Colors.black,
              surface: Color(0xFF1E293B),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _fromDate = picked.start;
        _toDate = picked.end;
      });
      _loadLedger();
    }
  }

  Widget _buildEntriesContent({bool isMobile = false}) {
    final filtered = _filteredEntries;
    final cur = _result.currency;
    final balanceLabel = _result.isCreditNormal ? 'دائن' : 'مدين';

    if (isMobile) {
      return Column(
        children: [
          _buildKpiRow(
            openingBalance: _result.openingBalance,
            totalDebit: _result.totalDebit,
            totalCredit: _result.totalCredit,
            closingBalance: _result.closingBalance,
            count: _result.transactionCount,
            currency: cur,
            balanceLabel: balanceLabel,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 400,
            child: filtered.isEmpty
                ? _buildEmptyState()
                : _buildTable(filtered),
          ),
        ],
      );
    }

    return Column(
      children: [
        // KPI Summary Cards
        _buildKpiRow(
          openingBalance: _result.openingBalance,
          totalDebit: _result.totalDebit,
          totalCredit: _result.totalCredit,
          closingBalance: _result.closingBalance,
          count: _result.transactionCount,
          currency: cur,
          balanceLabel: balanceLabel,
        ),
        const SizedBox(height: 14),

        // Table
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyState()
              : _buildTable(filtered),
        ),
      ],
    );
  }

  Widget _buildKpiRow({
    required double openingBalance,
    required double totalDebit,
    required double totalCredit,
    required double closingBalance,
    required int count,
    required String currency,
    required String balanceLabel,
  }) {
    final isDark = AppTheme.isDark(context);

    final card1 = _buildKpiCard(
      title: 'الرصيد الافتتاحي',
      value: '${_currencyFormat.format(openingBalance.abs())} $currency',
      suffix: openingBalance != 0
          ? (openingBalance > 0 ? balanceLabel : (_result.isCreditNormal ? 'مدين' : 'دائن'))
          : '',
      color: isDark ? AppTheme.accent : const Color(0xFF0F766E),
      icon: Icons.play_circle_outline,
    );
    final card2 = _buildKpiCard(
      title: 'إجمالي المدين',
      value: '${_currencyFormat.format(totalDebit)} $currency',
      suffix: '',
      color: isDark ? AppTheme.success : const Color(0xFF047857),
      icon: Icons.arrow_downward,
    );
    final card3 = _buildKpiCard(
      title: 'إجمالي الدائن',
      value: '${_currencyFormat.format(totalCredit)} $currency',
      suffix: '',
      color: isDark ? Colors.orangeAccent : const Color(0xFFC2410C),
      icon: Icons.arrow_upward,
    );
    final card4 = _buildKpiCard(
      title: 'الرصيد الختامي',
      value: '${_currencyFormat.format(closingBalance.abs())} $currency',
      suffix: closingBalance != 0
          ? (closingBalance > 0 ? balanceLabel : (_result.isCreditNormal ? 'مدين' : 'دائن'))
          : '',
      color: closingBalance.abs() > 0.01
          ? (closingBalance > 0
              ? (isDark ? AppTheme.success : const Color(0xFF047857))
              : (isDark ? Colors.purpleAccent : const Color(0xFF7E22CE)))
          : AppTheme.getTextSecondary(context),
      icon: Icons.savings_outlined,
    );
    final countBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.getCardBg(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.getBorderColor(context)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'عدد القيود',
            style: TextStyle(
              color: AppTheme.getTextSecondary(context),
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$count',
            style: TextStyle(
              color: AppTheme.getTextPrimary(context),
              fontWeight: FontWeight.bold,
              fontSize: 14,
              fontFamily: 'Cairo',
            ),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 850) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                SizedBox(width: 165, child: card1),
                const SizedBox(width: 8),
                SizedBox(width: 165, child: card2),
                const SizedBox(width: 8),
                SizedBox(width: 165, child: card3),
                const SizedBox(width: 8),
                SizedBox(width: 165, child: card4),
                const SizedBox(width: 8),
                countBadge,
              ],
            ),
          );
        }

        return Row(
          children: [
            Expanded(child: card1),
            const SizedBox(width: 8),
            Expanded(child: card2),
            const SizedBox(width: 8),
            Expanded(child: card3),
            const SizedBox(width: 8),
            Expanded(child: card4),
            const SizedBox(width: 8),
            countBadge,
          ],
        );
      },
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String suffix,
    required Color color,
    required IconData icon,
  }) {
    final isDark = AppTheme.isDark(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.getCardBg(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? color.withValues(alpha: 0.2) : AppTheme.getBorderColor(context)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppTheme.getTextSecondary(context),
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          fontFamily: 'Cairo',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (suffix.isNotEmpty) ...[
                      const SizedBox(width: 3),
                      Text(
                        suffix,
                        style: TextStyle(
                          color: isDark ? color.withValues(alpha: 0.7) : color,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.getCardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.getBorderColor(context)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: AppTheme.getTextSecondary(context)),
            const SizedBox(height: 12),
            Text(
              'لا توجد قيود أو حركات محاسبية في هذه الفترة',
              style: TextStyle(
                color: AppTheme.getTextPrimary(context),
                fontSize: 14,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(List<AccountLedgerEntry> entries) {
    final isDark = AppTheme.isDark(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: constraints.maxWidth > 1180 ? constraints.maxWidth : 1180,
              maxWidth: constraints.maxWidth > 1180 ? constraints.maxWidth : 1180,
            ),
            child: Container(
      decoration: BoxDecoration(
        color: AppTheme.getCardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.getBorderColor(context)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            // Opening Balance Row (when date filter is active)
            if (_fromDate != null && _result.openingBalance.abs() > 0.001)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: isDark ? Colors.amber.withValues(alpha: 0.06) : const Color(0xFFFEF3C7),
                child: Row(
                  children: [
                    const SizedBox(width: 40),
                    SizedBox(
                      width: 90,
                      child: Text('—',
                          style: TextStyle(
                              color: isDark ? Colors.amber : const Color(0xFFB45309),
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                              fontSize: 11.5)),
                    ),
                    SizedBox(
                      width: 95,
                      child: Text(
                        DateFormat('yyyy-MM-dd').format(_fromDate!),
                        style: TextStyle(
                          color: AppTheme.getTextPrimary(context),
                          fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                          fontFamily: 'Cairo',
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 100), // reference type column
                    Expanded(
                      child: Text(
                        'رصيد سابق (مُرحّل)',
                        style: TextStyle(
                          color: isDark ? Colors.amber : const Color(0xFFB45309),
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 160), // cost center column
                    const SizedBox(width: 100), // debit
                    const SizedBox(width: 100), // credit
                    SizedBox(
                      width: 120,
                      child: Text(
                        '${_currencyFormat.format(_result.openingBalance.abs())} ${_result.currency}',
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          color: _result.openingBalance >= 0
                              ? (isDark ? AppTheme.success : const Color(0xFF047857))
                              : AppTheme.danger,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: isDark ? const Color(0x1A00E5FF) : const Color(0xFFEFF2F7),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Text('#',
                        style: TextStyle(
                            color: AppTheme.getTextSecondary(context),
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text('رقم القيد',
                        style: TextStyle(
                            color: AppTheme.getTextSecondary(context),
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                  SizedBox(
                    width: 95,
                    child: Text('التاريخ',
                        style: TextStyle(
                            color: AppTheme.getTextSecondary(context),
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                  SizedBox(
                    width: 100,
                    child: Text('نوع العملية',
                        style: TextStyle(
                            color: AppTheme.getTextSecondary(context),
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                  Expanded(
                    child: Text('البيان / الشرح',
                        style: TextStyle(
                            color: AppTheme.getTextSecondary(context),
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                  SizedBox(
                    width: 160,
                    child: Text('مركز التكلفة',
                        style: TextStyle(
                            color: isDark ? Colors.cyanAccent : const Color(0xFF0369A1),
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                  SizedBox(
                    width: 100,
                    child: Text('مدين (من)',
                        textAlign: TextAlign.left,
                        style: TextStyle(
                            color: isDark ? AppTheme.accent : const Color(0xFF0F766E),
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                  SizedBox(
                    width: 100,
                    child: Text('دائن (إلى)',
                        textAlign: TextAlign.left,
                        style: TextStyle(
                            color: isDark ? Colors.orangeAccent : const Color(0xFFC2410C),
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                  SizedBox(
                    width: 120,
                    child: Text('الرصيد بعد الحركة',
                        textAlign: TextAlign.left,
                        style: TextStyle(
                            color: AppTheme.getTextSecondary(context),
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppTheme.getBorderColor(context)),

            // Rows list
            Expanded(
              child: ListView.separated(
                itemCount: entries.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: AppTheme.getBorderColor(context)),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final dateStr = DateFormat('yyyy-MM-dd').format(entry.date);

                  return InkWell(
                    onTap: () {
                      if (entry.entryNumber != null &&
                          entry.entryNumber!.isNotEmpty) {
                        if (context.canPop()) context.pop();
                        context.push(
                          '${RoutePaths.journalEntry}?entryNumber=${entry.entryNumber}',
                        );
                      }
                    },
                    hoverColor: isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF8FAFC),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                      children: [
                        // Row number
                        SizedBox(
                          width: 40,
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                                color: isDark ? AppTheme.textSecondary : Colors.black,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                                fontSize: 11.5),
                          ),
                        ),
                        // Entry Number (Journal Entry Number)
                        SizedBox(
                          width: 90,
                          child: Row(
                            children: [
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: isDark ? AppTheme.accent.withValues(alpha: 0.12) : const Color(0xFFCCFBF1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: isDark ? null : Border.all(color: const Color(0xFF99F6E4)),
                                  ),
                                  child: Text(
                                    entry.entryNumber ?? '-',
                                    style: TextStyle(
                                      color: isDark ? AppTheme.accent : const Color(0xFF0F766E),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      fontFamily: 'Cairo',
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Date
                        SizedBox(
                          width: 95,
                          child: Text(
                            dateStr,
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black,
                              fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                              fontFamily: 'Cairo',
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                        // Reference Type (نوع العملية)
                        SizedBox(
                          width: 100,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: _getReferenceTypeColor(entry.referenceType)
                                  .withValues(alpha: isDark ? 0.12 : 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              entry.referenceTypeLabel,
                              style: TextStyle(
                                color: _getReferenceTypeColor(entry.referenceType),
                                fontSize: 10.5,
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        // Description
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              entry.description.isNotEmpty
                                  ? entry.description
                                  : 'قيد محاسبي',
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black,
                                fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                fontFamily: 'Cairo',
                                fontSize: 12,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        // Cost Center (مركز التكلفة)
                        SizedBox(
                          width: 160,
                          child: entry.costCenterName != null && entry.costCenterName!.isNotEmpty
                              ? Tooltip(
                                  message: entry.costCenterName!,
                                  waitDuration: const Duration(milliseconds: 250),
                                  textStyle: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.white,
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.w600,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF0E2A47) : const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.cyan.withValues(alpha: 0.4)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.4),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.cyan.withValues(alpha: 0.12) : const Color(0xFFE0F2FE),
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(color: isDark ? Colors.cyan.withValues(alpha: 0.3) : const Color(0xFFBAE6FD)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.account_tree_outlined,
                                            size: 12, color: isDark ? Colors.cyanAccent.withValues(alpha: 0.7) : const Color(0xFF0284C7)),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            entry.costCenterName!,
                                            style: TextStyle(
                                              color: isDark ? Colors.cyanAccent : const Color(0xFF0369A1),
                                              fontSize: 10.5,
                                              fontFamily: 'Cairo',
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : Text(
                                  '—',
                                  style: TextStyle(
                                    color: isDark ? Colors.white24 : const Color(0xFF94A3B8),
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                  ),
                                ),
                        ),
                        // Debit
                        SizedBox(
                          width: 100,
                          child: Text(
                            entry.isDebit
                                ? '${_currencyFormat.format(entry.debit)} ${entry.currency}'.trim()
                                : '-',
                            textAlign: TextAlign.left,
                            style: TextStyle(
                              color: entry.isDebit
                                  ? (isDark ? AppTheme.accent : const Color(0xFF0F766E))
                                  : (isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                              fontWeight: entry.isDebit
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontFamily: 'Cairo',
                              fontSize: 12,
                            ),
                          ),
                        ),
                        // Credit
                        SizedBox(
                          width: 100,
                          child: Text(
                            !entry.isDebit
                                ? '${_currencyFormat.format(entry.credit)} ${entry.currency}'.trim()
                                : '-',
                            textAlign: TextAlign.left,
                            style: TextStyle(
                              color: !entry.isDebit
                                  ? (isDark ? Colors.orangeAccent : const Color(0xFFC2410C))
                                  : (isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                              fontWeight: !entry.isDebit
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              fontFamily: 'Cairo',
                              fontSize: 12,
                            ),
                          ),
                        ),
                        // Running Balance
                        SizedBox(
                          width: 120,
                          child: RichText(
                            textAlign: TextAlign.left,
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: '${_currencyFormat.format(entry.runningBalance.abs())} ${entry.currency} ',
                                  style: TextStyle(
                                    color: entry.runningBalance >= 0
                                        ? (isDark ? AppTheme.success : const Color(0xFF047857))
                                        : AppTheme.danger,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                  ),
                                ),
                                TextSpan(
                                  text: entry.runningBalance.abs() > 0.001
                                      ? (entry.runningBalance > 0
                                          ? (_result.isCreditNormal ? 'دائن' : 'مدين')
                                          : (_result.isCreditNormal ? 'مدين' : 'دائن'))
                                      : '',
                                  style: TextStyle(
                                    color: (entry.runningBalance >= 0
                                            ? (isDark ? AppTheme.success : const Color(0xFF047857))
                                            : AppTheme.danger)
                                        .withValues(alpha: 0.7),
                                    fontSize: 9,
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
                  );
                },
              ),
            ),
          ],
        ),
      ),
            ),
          ),
        );
      },
    );
  }

  Color _getReferenceTypeColor(String? refType) {
    switch (refType?.toLowerCase()) {
      case 'purchase_invoice':
      case 'purchase':
        return Colors.orangeAccent;
      case 'purchase_return':
        return Colors.amber;
      case 'supplier_payment':
      case 'cash_payment':
        return AppTheme.success;
      case 'sales_invoice':
      case 'invoice':
        return AppTheme.accent;
      case 'sales_return':
        return Colors.amber;
      case 'customer_receipt':
      case 'receipt':
      case 'receive':
      case 'cash_receipt':
        return AppTheme.success;
      case 'opening_balance':
        return Colors.amber;
      case 'treasury_transfer':
      case 'treasury':
      case 'bank_transfer':
      case 'bank':
      case 'transfer':
        return Colors.cyanAccent;
      case 'expense':
        return AppTheme.danger;
      case 'manual':
      case 'manual_journal':
        return Colors.purpleAccent;
      default:
        return AppTheme.textSecondary;
    }
  }

  Color _getAccountTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'asset':
        return AppTheme.success;
      case 'liability':
        return Colors.orangeAccent;
      case 'equity':
        return Colors.purpleAccent;
      case 'revenue':
        return const Color(0xFF00E5FF);
      case 'expense':
        return AppTheme.danger;
      case 'system':
        return Colors.tealAccent;
      default:
        return AppTheme.textSecondary;
    }
  }

  String _getAccountTypeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'asset':
        return 'أصول';
      case 'liability':
        return 'خصوم';
      case 'equity':
        return 'حقوق ملكية';
      case 'revenue':
        return 'إيرادات';
      case 'expense':
        return 'مصروفات';
      case 'system':
        return 'حسابات نظامية';
      default:
        return type;
    }
  }
}
