import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/cost_center.dart';
import 'expense_sub_account_dialog.dart';

/// Callback when an account is selected, returning the account map and a suggested Cost Center ID
typedef OnExpenseAccountSelected = void Function(
  Map<String, dynamic>? account,
  String? suggestedCostCenterId,
);

/// A searchable, multi-level dropdown component populated from the Chart of Accounts (COA)
/// for expense disbursal. Supports category tabs, instant search by code/name,
/// inline creation of Level 4 sub-accounts, and intelligent Cost Center suggestions.
class COAExpenseDropdown extends StatefulWidget {
  final List<Map<String, dynamic>> accounts;
  final String? selectedAccountId;
  final String? selectedCostCenterId;
  final OnExpenseAccountSelected onSelected;
  final VoidCallback? onAccountCreated;
  final bool isRequired;
  final String? label;
  final String? rootCodeFilter;
  final bool allowCreateSubAccount;
  final bool showInlineCostCenterCard;

  const COAExpenseDropdown({
    super.key,
    required this.accounts,
    required this.selectedAccountId,
    this.selectedCostCenterId,
    required this.onSelected,
    this.onAccountCreated,
    this.isRequired = true,
    this.label,
    this.rootCodeFilter = '31',
    this.allowCreateSubAccount = true,
    this.showInlineCostCenterCard = true,
  });

  /// Suggests a default Cost Center ID based on account code or saved default
  static String suggestCostCenter(Map<String, dynamic>? account) {
    if (account == null) return CostCenterHelper.generalAdmin.id;

    // 1. Direct binding in database if present
    final directCc = account['cost_center_id']?.toString();
    if (directCc != null && directCc.isNotEmpty) {
      return directCc;
    }

    // 2. Derive from account code prefix and name keywords
    final code = (account['account_code'] ?? account['code'] ?? '').toString().trim();
    final name = (account['account_name'] ?? account['name'] ?? '').toString().toLowerCase();

    // Check crop-specific production lines (Mango, Strawberry, Citrus, Grapes, Banana)
    if (name.contains('مانجو') || name.contains('mango') || code.endsWith('mango')) {
      return CostCenterHelper.mangoLine.id;
    } else if (name.contains('فراولة') || name.contains('strawberry') || code.endsWith('strawberry')) {
      return CostCenterHelper.strawberryLine.id;
    } else if (name.contains('موالح') || name.contains('برتقال') || name.contains('ليمون') || name.contains('citrus')) {
      return CostCenterHelper.citrusLine.id;
    } else if (name.contains('عنب') || name.contains('grapes')) {
      return CostCenterHelper.grapesLine.id;
    } else if (name.contains('موز') || name.contains('banana')) {
      return CostCenterHelper.bananaLine.id;
    }

    // Direct Sales Costs (341xx)
    if (code.startsWith('341')) {
      if (code == '34114' || code == '34117' || code == '34118') {
        return CostCenterHelper.freightLogistics.id;
      }
      return CostCenterHelper.packingStation.id;
    }

    // Salaries & Employees (311xx)
    if (code.startsWith('311')) {
      return CostCenterHelper.packingStation.id;
    // Operating & Marketing (312xx)
    } else if (code.startsWith('312')) {
      return CostCenterHelper.packingStation.id;
    // Admin & Services (313xx)
    } else if (code.startsWith('313')) {
      return CostCenterHelper.generalAdmin.id;
    // Other Expenses - Bank & Misc (314xx)
    } else if (code.startsWith('314')) {
      return CostCenterHelper.generalAdmin.id;
    // Depreciation (321xx)
    } else if (code.startsWith('321')) {
      return CostCenterHelper.generalAdmin.id;
    // FX Differences (322xx)
    } else if (code.startsWith('322')) {
      return CostCenterHelper.generalAdmin.id;
    // Inventory Costs (331xx)
    } else if (code.startsWith('331') || code.startsWith('33')) {
      return CostCenterHelper.packingStation.id;
    }

    return CostCenterHelper.generalAdmin.id;
  }

  /// Categorizes an account into high-level COA category for filtering
  static String resolveCategory(Map<String, dynamic> account) {
    final code = (account['account_code'] ?? account['code'] ?? '').toString().trim();
    if (code.startsWith('3111')) return 'salaries';   // مرتبات ومافي حكمها
    if (code.startsWith('3112')) return 'employees';  // مصروفات عاملين اخري
    if (code.startsWith('312')) return 'operating';    // مصروفات تشغيل وبيع
    if (code.startsWith('313')) return 'admin';         // مصروفات إداريه
    if (code.startsWith('314')) return 'finance';       // فوائد ومصروفات بنكيه
    if (code.startsWith('321')) return 'depreciation';  // إهلاك أصول ثابته
    if (code.startsWith('322')) return 'fx';            // فروق عمله
    if (code.startsWith('331') || code.startsWith('33')) return 'inventory'; // تكاليف مخزنيه
    if (code.startsWith('341')) return 'cogs';          // تكاليف المبيعات
    return 'other';
  }

  /// Human-readable category label in Arabic
  static String getCategoryLabel(String categoryKey) {
    switch (categoryKey) {
      case 'salaries':
        return 'مرتبات ومافي حكمها (3111x)';
      case 'employees':
        return 'مصروفات عاملين اخري (3112x)';
      case 'operating':
        return 'تشغيل وبيع وتسويق (312x)';
      case 'admin':
        return 'مصروفات إداريه (313x)';
      case 'finance':
        return 'فوائد ومصروفات بنكيه (314x)';
      case 'depreciation':
        return 'إهلاك أصول ثابته (321x)';
      case 'fx':
        return 'فروق عمله (322x)';
      case 'inventory':
        return 'تكاليف مخزنيه (331x)';
      case 'cogs':
        return 'تكاليف المبيعات (341x)';
      default:
        return 'مصروفات أخرى';
    }
  }

  @override
  State<COAExpenseDropdown> createState() => _COAExpenseDropdownState();
}

class _COAExpenseDropdownState extends State<COAExpenseDropdown> {
  Map<String, dynamic>? get _selectedAccount {
    if (widget.selectedAccountId == null) return null;
    try {
      return widget.accounts.firstWhere(
        (a) => a['id'].toString() == widget.selectedAccountId.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _openNewAccountDialog({String? initialParentCode}) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ExpenseSubAccountDialog(
        initialParentCode: initialParentCode ?? (widget.rootCodeFilter == '31' ? '3131' : widget.rootCodeFilter),
      ),
    );

    if (result != null && mounted) {
      widget.onAccountCreated?.call();
      final suggestedCc = COAExpenseDropdown.suggestCostCenter(result);
      widget.onSelected(result, suggestedCc);
    }
  }

  void _openSelectionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ExpenseAccountPickerSheet(
        accounts: widget.accounts,
        selectedAccountId: widget.selectedAccountId,
        rootCodeFilter: widget.rootCodeFilter,
        allowCreateSubAccount: widget.allowCreateSubAccount,
        onSelected: (acct) {
          final suggestedCc = COAExpenseDropdown.suggestCostCenter(acct);
          widget.onSelected(acct, suggestedCc);
        },
        onAddNew: (parentCode) => _openNewAccountDialog(initialParentCode: parentCode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selected = _selectedAccount;
    final model = selected != null ? AccountModel.fromMap(selected) : null;
    final categoryKey = selected != null ? COAExpenseDropdown.resolveCategory(selected) : null;
    final boundCcId = widget.selectedCostCenterId ??
        (selected != null ? COAExpenseDropdown.suggestCostCenter(selected) : null);
    final boundCostCenter = (widget.showInlineCostCenterCard && boundCcId != null && boundCcId.isNotEmpty)
        ? CostCenterHelper.fromId(boundCcId)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title Bar with inline "+ حساب جديد" action
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  const Icon(Icons.account_tree_outlined, size: 15, color: AppTheme.primary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      widget.label ?? 'حساب المصروف (دليل الحسابات - COA)',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
                  if (widget.isRequired)
                    const Text(' *', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            if (widget.allowCreateSubAccount)
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _openNewAccountDialog(),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    children: [
                      Icon(Icons.add_circle_outline, size: 14, color: AppTheme.primary),
                      SizedBox(width: 4),
                      Text(
                        'حساب فرعي جديد',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.primary,
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
        const SizedBox(height: 6),

        // Main Selector Box
        InkWell(
          onTap: _openSelectionSheet,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D2137) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected != null
                    ? AppTheme.primary.withValues(alpha: 0.6)
                    : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                width: selected != null ? 1.5 : 1.0,
              ),
            ),
            child: selected == null
                ? Row(
                    children: [
                      Icon(Icons.search, size: 18, color: isDark ? AppTheme.textMuted : const Color(0xFF475569)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'اختر حساب المصروف من شجرة الحسابات...',
                          style: TextStyle(
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                            fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                            fontSize: 13,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                      Icon(Icons.keyboard_arrow_down, size: 20, color: isDark ? AppTheme.textMuted : const Color(0xFF475569)),
                    ],
                  )
                : Row(
                    children: [
                      // Account Code Chip
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          model?.code ?? (selected['account_code'] ?? selected['code'] ?? ''),
                          style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Account Name, Category, and Bound Cost Center
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              model?.displayName.isNotEmpty == true
                                  ? model!.displayName
                                  : (selected['name'] ?? ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            if (categoryKey != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                COAExpenseDropdown.getCategoryLabel(categoryKey),
                                style: TextStyle(
                                  color: isDark ? AppTheme.textMuted.withValues(alpha: 0.8) : const Color(0xFF475569),
                                  fontSize: 10,
                                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ],
                            if (boundCostCenter != null) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: boundCostCenter.color.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: boundCostCenter.color.withValues(alpha: 0.35)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(boundCostCenter.icon, size: 10, color: boundCostCenter.color),
                                        const SizedBox(width: 4),
                                        Text(
                                          'مركز التكلفة: ${boundCostCenter.nameAr}',
                                          style: TextStyle(
                                            color: boundCostCenter.color,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Clear Button
                      IconButton(
                        icon: const Icon(Icons.close, size: 16, color: AppTheme.textMuted),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: () => widget.onSelected(null, null),
                        tooltip: 'إلغاء التحديد',
                      ),
                      const SizedBox(width: 4),

                      // Edit/Change Icon
                      const Icon(Icons.swap_vert_rounded, size: 18, color: AppTheme.primary),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

/// Inner Bottom Sheet for browsing and searching Chart of Accounts
class _ExpenseAccountPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> accounts;
  final String? selectedAccountId;
  final String? rootCodeFilter;
  final bool allowCreateSubAccount;
  final ValueChanged<Map<String, dynamic>> onSelected;
  final ValueChanged<String?> onAddNew;

  const _ExpenseAccountPickerSheet({
    required this.accounts,
    required this.selectedAccountId,
    this.rootCodeFilter,
    this.allowCreateSubAccount = true,
    required this.onSelected,
    required this.onAddNew,
  });

  @override
  State<_ExpenseAccountPickerSheet> createState() => _ExpenseAccountPickerSheetState();
}

class _ExpenseAccountPickerSheetState extends State<_ExpenseAccountPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String get _headerTitle {
    final prefix = widget.rootCodeFilter ?? '31';
    // 1. Try to find parent account in widget.accounts
    try {
      final parentAccount = widget.accounts.firstWhere(
        (a) {
          final code = (a['account_code'] ?? a['code'] ?? '').toString().trim();
          return code == prefix;
        },
      );
      final name = (parentAccount['account_name'] ?? parentAccount['name'] ?? '').toString().trim();
      if (name.isNotEmpty) {
        return '$name ($prefix)';
      }
    } catch (_) {}

    // 2. Fallback to standard COA group names
    switch (prefix) {
      case '31':
        return 'المصروفات النقدية التشغيلية والإدارية (31)';
      case '311':
        return 'أجور ومرتبات العاملين (311)';
      case '312':
        return 'مصروفات تشغيل وبيع وتسويق (312)';
      case '313':
        return 'مصروفات إدارية وعمومية (313)';
      case '314':
        return 'مصروفات متنوعة وبنكية (314)';
      case '341':
        return 'تكاليف المبيعات (341)';
      default:
        return 'دليل الحسابات ($prefix)';
    }
  }

  List<Map<String, dynamic>> get _filteredAccounts {
    final prefix = widget.rootCodeFilter ?? '31';
    return widget.accounts.where((a) {
      final code = (a['account_code'] ?? a['code'] ?? '').toString().trim();

      // 0. Exclusively restrict to root code prefix (e.g. 31 or custom)
      if (!code.startsWith(prefix)) return false;

      // 1. Filter out non-analytical parent root folder
      if (code == prefix) return false;

      // 2. Strict exclusion: completely exclude Group 32 (depreciation & non-cash costs), and Assets/Liabilities/Equity
      if (code.startsWith('32') || code.startsWith('1') || code.startsWith('2') || code.startsWith('4')) {
        return false;
      }

      // 2b. Explicit exclusion of purged obsolete accounts (e.g. 3121, 3123, 3412)
      if (const {'3121', '3123', '3212', '3222', '3223', '3224', '3412'}.contains(code)) {
        return false;
      }

      // 3. Restrict to leaf-node analytical expense accounts (prevent parent grouping accounts)
      final isLeaf = a['is_leaf'] == true;
      final allowPosting = a['allow_posting'] == true;
      if (!isLeaf && !allowPosting) return false;
      if (a['is_active'] == false) return false;

      // 4. Query filter
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        final model = AccountModel.fromMap(a);
        final name = (a['name'] ?? '').toString().toLowerCase();
        final accountName = (a['account_name'] ?? '').toString().toLowerCase();
        final displayName = model.displayName.toLowerCase();

        return code.toLowerCase().contains(q) ||
            name.contains(q) ||
            accountName.contains(q) ||
            displayName.contains(q);
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filteredAccounts;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0A1E34) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(
              color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1),
              width: 1.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.business_center_rounded, color: AppTheme.neonCyan, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _headerTitle,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
                // Add New Sub-Account button
                if (widget.allowCreateSubAccount)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.neonCyan.withValues(alpha: 0.15),
                      foregroundColor: isDark ? AppTheme.neonCyan : const Color(0xFF0284C7),
                      elevation: 0,
                      side: BorderSide(color: AppTheme.neonCyan.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text(
                      'حساب جديد',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onAddNew(widget.rootCodeFilter ?? '3131');
                    },
                  ),
                const SizedBox(width: 6),
                IconButton(
                  icon: Icon(Icons.close, color: isDark ? AppTheme.textSecondary : const Color(0xFF475569), size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: (v) => setState(() => _query = v.trim()),
              style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontFamily: 'Cairo',
                  fontSize: 14,
                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold),
              decoration: InputDecoration(
                filled: true,
                fillColor: isDark ? const Color(0xFF061524) : const Color(0xFFF1F5F9),
                hintText: 'ابحث باسم المصروف أو كود الحساب (مثال: ${widget.rootCodeFilter ?? '31'}1)...',
                hintStyle: TextStyle(
                    color: isDark ? AppTheme.textMuted : const Color(0xFF64748B),
                    fontSize: 13,
                    fontFamily: 'Cairo',
                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold),
                prefixIcon: const Icon(Icons.search, color: AppTheme.neonCyan, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: isDark ? AppTheme.textSecondary : const Color(0xFF475569), size: 16),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                  borderSide: BorderSide(color: AppTheme.primary),
                ),
              ),
            ),
          ),

          // Active Scope Badge (Unused tabs/chips removed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.neonCyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.business_center_rounded, size: 14, color: AppTheme.neonCyan),
                      const SizedBox(width: 6),
                      Text(
                        '$_headerTitle • ${filtered.length} حساب نشط',
                        style: const TextStyle(
                          color: AppTheme.neonCyan,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: AppTheme.glassBorder, height: 1),

          // Accounts List
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off, size: 48, color: AppTheme.textMuted.withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          Text(
                            _query.isNotEmpty
                                ? 'لا يوجد حساب يطابق "$_query"'
                                : 'لا توجد حسابات مسجلة في هذا القسم',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontFamily: 'Cairo',
                              fontSize: 14,
                            ),
                          ),
                          if (widget.allowCreateSubAccount) ...[
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              ),
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text(
                                'إنشاء هذا الحساب الآن',
                                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                              ),
                              onPressed: () {
                                Navigator.of(context).pop();
                                widget.onAddNew(widget.rootCodeFilter ?? '3131');
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => Divider(
                        color: isDark ? AppTheme.divider : const Color(0xFFE2E8F0),
                        height: 1),
                    itemBuilder: (ctx, i) {
                      final acct = filtered[i];
                      final model = AccountModel.fromMap(acct);
                      final acctId = acct['id'].toString();
                      final isSelected = widget.selectedAccountId == acctId;
                      final code = model.code.isNotEmpty
                          ? model.code
                          : (acct['account_code'] ?? acct['code'] ?? '').toString();
                      final cat = COAExpenseDropdown.resolveCategory(acct);
                      final ccId = COAExpenseDropdown.suggestCostCenter(acct);
                      final costCenter = CostCenterHelper.fromId(ccId);

                      return Material(
                        color: isSelected
                            ? AppTheme.primary.withValues(alpha: isDark ? 0.12 : 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          onTap: () {
                            widget.onSelected(acct);
                            Navigator.of(context).pop();
                          },
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.primary.withValues(alpha: 0.25)
                                  : (isDark ? const Color(0xFF0F2642) : const Color(0xFFF1F5F9)),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.primary
                                    : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                              ),
                            ),
                            child: Icon(
                              _getCategoryIcon(cat),
                              size: 18,
                              color: isSelected ? AppTheme.primary : (isDark ? AppTheme.textSecondary : const Color(0xFF475569)),
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(
                                code,
                                style: TextStyle(
                                  color: isSelected
                                      ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                                      : (isDark ? AppTheme.warning : const Color(0xFFD97706)),
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  model.displayName.isNotEmpty
                                      ? model.displayName
                                      : (acct['name'] ?? ''),
                                  style: TextStyle(
                                    color: isSelected
                                        ? (isDark ? Colors.white : const Color(0xFF0284C7))
                                        : (isDark ? AppTheme.textPrimary : Colors.black),
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Row(
                              children: [
                                Text(
                                  COAExpenseDropdown.getCategoryLabel(cat),
                                  style: TextStyle(
                                    color: isDark ? AppTheme.textMuted.withValues(alpha: 0.8) : const Color(0xFF475569),
                                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                    fontFamily: 'Cairo',
                                    fontSize: 11,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: costCenter.color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: costCenter.color.withValues(alpha: 0.25)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(costCenter.icon, size: 10, color: costCenter.color),
                                      const SizedBox(width: 4),
                                      Text(
                                        costCenter.nameAr,
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          color: costCenter.color,
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle, color: AppTheme.primary, size: 20)
                              : const Icon(Icons.chevron_left, color: AppTheme.textMuted, size: 18),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }



  IconData _getCategoryIcon(String cat) {
    switch (cat) {
      case 'admin':
        return Icons.business_outlined;
      case 'packing':
        return Icons.inventory_2_outlined;
      case 'logistics':
        return Icons.local_shipping_outlined;
      case 'marketing':
        return Icons.campaign_outlined;
      case 'finance':
        return Icons.account_balance_outlined;
      default:
        return Icons.receipt_long_outlined;
    }
  }
}
