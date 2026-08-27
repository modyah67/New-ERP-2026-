import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../core/router.dart';
import '../../../core/theme.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/account_ledger_result.dart';
import '../../../data/services/account_ledger_service.dart';

class AccountJournalEntriesDialog extends StatefulWidget {
  final AccountModel account;
  final List<AccountModel> allBranchAccounts;
  final bool isBranch;

  const AccountJournalEntriesDialog({
    super.key,
    required this.account,
    required this.allBranchAccounts,
    this.isBranch = false,
  });

  static Future<void> show(
    BuildContext context, {
    required AccountModel account,
    required List<AccountModel> allBranchAccounts,
    bool isBranch = false,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AccountJournalEntriesDialog(
        account: account,
        allBranchAccounts: allBranchAccounts,
        isBranch: isBranch,
      ),
    );
  }

  @override
  State<AccountJournalEntriesDialog> createState() =>
      _AccountJournalEntriesDialogState();
}

class _AccountJournalEntriesDialogState
    extends State<AccountJournalEntriesDialog> {
  final AccountLedgerService _ledgerService = AccountLedgerService();
  final TextEditingController _searchCtrl = TextEditingController();

  bool _isLoading = true;
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
    _loadLedger();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
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

      final result = await _ledgerService.getAccountLedger(
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
    final dialogWidth = (screenSize.width * 0.92).clamp(700.0, 1200.0);
    final dialogHeight = (screenSize.height * 0.88).clamp(500.0, 850.0);

    return Dialog(
      backgroundColor: const Color(0xFF0F172A),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: Container(
              width: dialogWidth,
              height: dialogHeight,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDialogHeader(),
            const SizedBox(height: 16),
            _buildFilterBar(),
            const SizedBox(height: 16),
            if (_isLoading)
              const Expanded(
                child: Center(
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
                ),
              )
            else if (_error != null)
              Expanded(
                child: Center(
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
                ),
              )
            else
              Expanded(
                child: _buildEntriesContent(),
              ),
          ],
        ),
      ),
          ),
        ),
      ),
    );
  }

  Widget _buildDialogHeader() {
    final account = widget.account;
    final typeColor = _getAccountTypeColor(account.type);
    final typeLabel = _getAccountTypeLabel(account.type);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                        account.displayName,
                        style: const TextStyle(
                          color: Colors.white,
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
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Go to General Ledger button
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
          const SizedBox(width: 8),
          IconButton(
            onPressed: _loadLedger,
            icon: const Icon(Icons.refresh, color: Colors.white70, size: 20),
            tooltip: 'تحديث الحركات',
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () { if (context.canPop()) context.pop(); },
            icon: const Icon(Icons.close, color: Colors.white70, size: 22),
            tooltip: 'إغلاق',
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
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
              style: const TextStyle(
                  color: Colors.white, fontFamily: 'Cairo', fontSize: 12),
              decoration: InputDecoration(
                hintText: 'بحث بالقيد أو البيان...',
                hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                    fontFamily: 'Cairo'),
                prefixIcon: const Icon(Icons.search,
                    color: AppTheme.accent, size: 16),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close,
                            size: 14, color: Colors.white60),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.15)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.15)),
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
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_month,
                      size: 16, color: AppTheme.accent),
                  const SizedBox(width: 6),
                  Text(
                    _fromDate == null && _toDate == null
                        ? 'كل الفترات'
                        : '${_fromDate != null ? DateFormat('yyyy/MM/dd').format(_fromDate!) : 'البداية'}  -  ${_toDate != null ? DateFormat('yyyy/MM/dd').format(_toDate!) : 'الآن'}',
                    style: const TextStyle(
                      color: Colors.white,
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
                      child: const Icon(Icons.close,
                          size: 14, color: Colors.white60),
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
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTypeSegment('all', 'الكل'),
                _buildTypeSegment('debit', 'مدين فقط'),
                _buildTypeSegment('credit', 'دائن فقط'),
              ],
            ),
          ),

          // Currency filter segment (الكل - ج.م / USD / EUR ...)
          if (_availableCurrencies.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
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
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<String?>(
                  value: _selectedSubAccountId,
                  hint: const Text(
                    'تصفية بالحساب الفرعي',
                    style: TextStyle(
                      color: Colors.white70,
                      fontFamily: 'Cairo',
                      fontSize: 11.5,
                    ),
                  ),
                  dropdownColor: const Color(0xFF1E293B),
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Cairo',
                    fontSize: 12,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('جميع الحسابات التابعة'),
                    ),
                    ...widget.allBranchAccounts.map(
                      (acc) => DropdownMenuItem<String?>(
                        value: acc.id,
                        child: Text('${acc.code} - ${acc.displayName}'),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accent.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? AppTheme.accent
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppTheme.accent : Colors.white70,
            fontSize: 11,
            fontFamily: 'Cairo',
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildTypeSegment(String type, String label) {
    final isSelected = _selectedTypeFilter == type;
    return InkWell(
      onTap: () => setState(() => _selectedTypeFilter = type),
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
            color: isSelected ? Colors.white : Colors.white60,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontFamily: 'Cairo',
          ),
        ),
      ),
    );
  }

  Widget _buildCurrencySegment(String curr, String label) {
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
          color: isSelected ? AppTheme.accent.withValues(alpha: 0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isSelected ? Border.all(color: AppTheme.accent) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppTheme.accent : Colors.white60,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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

  Widget _buildEntriesContent() {
    final filtered = _filteredEntries;
    final cur = _result.currency;
    final balanceLabel = _result.isCreditNormal ? 'دائن' : 'مدين';

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
    return Row(
      children: [
        Expanded(
          child: _buildKpiCard(
            title: 'الرصيد الافتتاحي',
            value: '${_currencyFormat.format(openingBalance.abs())} $currency',
            suffix: openingBalance != 0
                ? (openingBalance > 0 ? balanceLabel : (_result.isCreditNormal ? 'مدين' : 'دائن'))
                : '',
            color: AppTheme.accent,
            icon: Icons.play_circle_outline,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildKpiCard(
            title: 'إجمالي المدين',
            value: '${_currencyFormat.format(totalDebit)} $currency',
            suffix: '',
            color: AppTheme.success,
            icon: Icons.arrow_downward,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildKpiCard(
            title: 'إجمالي الدائن',
            value: '${_currencyFormat.format(totalCredit)} $currency',
            suffix: '',
            color: Colors.orangeAccent,
            icon: Icons.arrow_upward,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildKpiCard(
            title: 'الرصيد الختامي',
            value: '${_currencyFormat.format(closingBalance.abs())} $currency',
            suffix: closingBalance != 0
                ? (closingBalance > 0 ? balanceLabel : (_result.isCreditNormal ? 'مدين' : 'دائن'))
                : '',
            color: closingBalance.abs() > 0.01
                ? (closingBalance > 0 ? AppTheme.success : Colors.purpleAccent)
                : AppTheme.textSecondary,
            icon: Icons.savings_outlined,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'عدد القيود',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 10.5,
                  fontFamily: 'Cairo',
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  fontFamily: 'Cairo',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String suffix,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
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
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10.5,
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
                          color: color.withValues(alpha: 0.7),
                          fontSize: 9.5,
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
        color: const Color(0xFF1E293B).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: AppTheme.textSecondary),
            SizedBox(height: 12),
            Text(
              'لا توجد قيود أو حركات محاسبية في هذه الفترة',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
                fontFamily: 'Cairo',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(List<AccountLedgerEntry> entries) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: constraints.maxWidth > 1000 ? constraints.maxWidth : 1000,
              maxWidth: constraints.maxWidth > 1000 ? constraints.maxWidth : 1000,
            ),
            child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            // Opening Balance Row (when date filter is active)
            if (_fromDate != null && _result.openingBalance.abs() > 0.001)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.amber.withValues(alpha: 0.06),
                child: Row(
                  children: [
                    const SizedBox(width: 40),
                    const SizedBox(
                      width: 90,
                      child: Text('—',
                          style: TextStyle(
                              color: Colors.amber,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                              fontSize: 11.5)),
                    ),
                    SizedBox(
                      width: 95,
                      child: Text(
                        DateFormat('yyyy-MM-dd').format(_fromDate!),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontFamily: 'Cairo',
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 100), // reference type column
                    const Expanded(
                      child: Text(
                        'رصيد سابق (مُرحّل)',
                        style: TextStyle(
                          color: Colors.amber,
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 100), // debit
                    const SizedBox(width: 100), // credit
                    SizedBox(
                      width: 120,
                      child: Text(
                        '${_currencyFormat.format(_result.openingBalance.abs())} ${_result.currency}',
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          color: _result.openingBalance >= 0
                              ? AppTheme.success
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
              color: Colors.white.withValues(alpha: 0.04),
              child: const Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Text('#',
                        style: TextStyle(
                            color: Colors.white70,
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text('رقم القيد',
                        style: TextStyle(
                            color: Colors.white70,
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                  SizedBox(
                    width: 95,
                    child: Text('التاريخ',
                        style: TextStyle(
                            color: Colors.white70,
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                  SizedBox(
                    width: 100,
                    child: Text('نوع العملية',
                        style: TextStyle(
                            color: Colors.white70,
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                  Expanded(
                    child: Text('البيان / الشرح',
                        style: TextStyle(
                            color: Colors.white70,
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                  SizedBox(
                    width: 100,
                    child: Text('مدين',
                        textAlign: TextAlign.left,
                        style: TextStyle(
                            color: AppTheme.accent,
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                  SizedBox(
                    width: 100,
                    child: Text('دائن',
                        textAlign: TextAlign.left,
                        style: TextStyle(
                            color: Colors.orangeAccent,
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                  SizedBox(
                    width: 120,
                    child: Text('الرصيد بعد الحركة',
                        textAlign: TextAlign.left,
                        style: TextStyle(
                            color: Colors.white70,
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white10),

            // Rows list
            Expanded(
              child: ListView.separated(
                itemCount: entries.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Colors.white10),
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
                    hoverColor: Colors.white.withValues(alpha: 0.03),
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
                            style: const TextStyle(
                                color: AppTheme.textSecondary,
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
                                    color: AppTheme.accent.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    entry.entryNumber ?? '-',
                                    style: const TextStyle(
                                      color: AppTheme.accent,
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
                            style: const TextStyle(
                              color: Colors.white70,
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
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              entry.referenceTypeLabel,
                              style: TextStyle(
                                color: _getReferenceTypeColor(entry.referenceType),
                                fontSize: 10.5,
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.w500,
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
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'Cairo',
                                fontSize: 12,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
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
                                  ? AppTheme.accent
                                  : Colors.white24,
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
                                  ? Colors.orangeAccent
                                  : Colors.white24,
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
                                        ? AppTheme.success
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
                                            ? AppTheme.success
                                            : AppTheme.danger)
                                        .withValues(alpha: 0.7),
                                    fontSize: 9,
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
      default:
        return type;
    }
  }
}
