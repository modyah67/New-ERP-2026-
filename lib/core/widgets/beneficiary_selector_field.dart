import 'package:flutter/material.dart';
import '../theme.dart';
import '../utils.dart';
import '../../data/models/supplier_model.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/dao/transport_supplier_dao.dart';
import '../../data/dao/shipping_company_dao.dart';
import '../../data/dao/clearing_agent_dao.dart';
import '../../data/dao/shareholder_dao.dart';
import '../../features/treasury/widgets/coa_expense_dropdown.dart';
import '../../features/treasury/widgets/cost_center_selector_field.dart';

/// تمثيل موحد للجهة المستفيدة المختارة
class BeneficiarySelection {
  final String beneficiaryType; // 'all_suppliers', 'crop', 'packaging', 'transport', 'shared', 'station', 'deduction', 'shipping_company', 'clearing_agent', 'shareholder', 'expense'
  final String? entityId;
  final String? entityName;
  final String? entityCode;
  final String currency;
  final double currentBalance;
  final int? accountId;
  final SupplierModel? supplierModel;

  // لحساب المصروف من شجرة الحسابات
  final String? expenseAccountId;
  final String? costCenterId;
  final Map<String, dynamic>? expenseAccountMap;

  const BeneficiarySelection({
    required this.beneficiaryType,
    this.entityId,
    this.entityName,
    this.entityCode,
    this.currency = 'EGP',
    this.currentBalance = 0.0,
    this.accountId,
    this.supplierModel,
    this.expenseAccountId,
    this.costCenterId,
    this.expenseAccountMap,
  });

  bool get isSupplier =>
      beneficiaryType == 'all_suppliers' ||
      beneficiaryType == 'crop' ||
      beneficiaryType == 'packaging' ||
      beneficiaryType == 'transport' ||
      beneficiaryType == 'shared' ||
      beneficiaryType == 'station' ||
      beneficiaryType == 'deduction';

  bool get isShippingCompany => beneficiaryType == 'shipping_company';
  bool get isClearingAgent => beneficiaryType == 'clearing_agent';
  bool get isShareholder => beneficiaryType == 'shareholder';
  bool get isExpense => beneficiaryType == 'expense';
}

/// بيانات كل تصنيف من تصنيفات جهات التعامل
class BeneficiaryCategoryOption {
  final String key;
  final String label;
  final String shortLabel;
  final IconData icon;
  final Color color;
  final String entityGroup; // 'supplier', 'shipping', 'clearing', 'shareholder', 'expense'

  const BeneficiaryCategoryOption({
    required this.key,
    required this.label,
    required this.shortLabel,
    required this.icon,
    required this.color,
    required this.entityGroup,
  });
}

/// عنصر جهة مسجلة في القائمة المنسدلة
class BeneficiaryDropdownItem {
  final String id;
  final String name;
  final String code;
  final String currency;
  final double balance;
  final String categoryKey;
  final String categoryLabel;
  final Color categoryColor;
  final int? accountId;
  final SupplierModel? supplierModel;

  const BeneficiaryDropdownItem({
    required this.id,
    required this.name,
    this.code = '',
    this.currency = 'EGP',
    this.balance = 0.0,
    required this.categoryKey,
    required this.categoryLabel,
    required this.categoryColor,
    this.accountId,
    this.supplierModel,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BeneficiaryDropdownItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          categoryKey == other.categoryKey;

  @override
  int get hashCode => id.hashCode ^ categoryKey.hashCode;
}

/// مكون اختيار جهة الصرف أو المستفيد مع قائمة منسدلة تفاعلية لجلب الأسماء المسجلة
class BeneficiarySelectorField extends StatefulWidget {
  final String? initialBeneficiaryType;
  final String? initialEntityId;
  final String? initialEntityName;
  final String? initialExpenseAccountId;
  final String? initialCostCenterId;
  final List<Map<String, dynamic>> expenseAccounts;
  final ValueChanged<BeneficiarySelection> onChanged;
  final VoidCallback? onAccountCreated;

  const BeneficiarySelectorField({
    super.key,
    this.initialBeneficiaryType,
    this.initialEntityId,
    this.initialEntityName,
    this.initialExpenseAccountId,
    this.initialCostCenterId,
    this.expenseAccounts = const [],
    required this.onChanged,
    this.onAccountCreated,
  });

  static const List<BeneficiaryCategoryOption> categories = [
    BeneficiaryCategoryOption(
      key: 'all_suppliers',
      label: 'الموردين (عام)',
      shortLabel: 'موردين (عام)',
      icon: Icons.storefront_outlined,
      color: Color(0xFF0284C7),
      entityGroup: 'supplier',
    ),
    BeneficiaryCategoryOption(
      key: 'packaging',
      label: 'موردين التعبئة والتغليف (70000 - 74999)',
      shortLabel: 'موردين تعبئة',
      icon: Icons.inventory_2_outlined,
      color: Color(0xFF06B6D4),
      entityGroup: 'supplier',
    ),
    BeneficiaryCategoryOption(
      key: 'crop',
      label: 'موردين المحاصيل (50000 - 59999)',
      shortLabel: 'موردين محاصيل',
      icon: Icons.agriculture_outlined,
      color: Color(0xFF10B981),
      entityGroup: 'supplier',
    ),
    BeneficiaryCategoryOption(
      key: 'transport',
      label: 'موردين النقل (60000 - 69999)',
      shortLabel: 'موردين نقل',
      icon: Icons.local_shipping_outlined,
      color: Color(0xFF0284C7),
      entityGroup: 'supplier',
    ),
    BeneficiaryCategoryOption(
      key: 'shared',
      label: 'الموردين المشتركين (75000 - 79999)',
      shortLabel: 'موردين مشتركين',
      icon: Icons.sync_alt_rounded,
      color: Color(0xFFEC4899),
      entityGroup: 'supplier',
    ),
    BeneficiaryCategoryOption(
      key: 'station',
      label: 'موردين المحطات (85000 - 89999)',
      shortLabel: 'موردين محطات',
      icon: Icons.factory_outlined,
      color: Color(0xFFF59E0B),
      entityGroup: 'supplier',
    ),
    BeneficiaryCategoryOption(
      key: 'deduction',
      label: 'موردين التخصيمات (40000 - 49999)',
      shortLabel: 'موردين تخصيمات',
      icon: Icons.assignment_outlined,
      color: Color(0xFF8B5CF6),
      entityGroup: 'supplier',
    ),
    BeneficiaryCategoryOption(
      key: 'shipping_company',
      label: 'شركات الشحن',
      shortLabel: 'شركات شحن',
      icon: Icons.directions_boat_outlined,
      color: Color(0xFF3B82F6),
      entityGroup: 'shipping',
    ),
    BeneficiaryCategoryOption(
      key: 'clearing_agent',
      label: 'المخلصين الجمركيين',
      shortLabel: 'مخلصين',
      icon: Icons.gavel_outlined,
      color: Color(0xFF6366F1),
      entityGroup: 'clearing',
    ),
    BeneficiaryCategoryOption(
      key: 'shareholder',
      label: 'المساهمين',
      shortLabel: 'مساهم',
      icon: Icons.people_outline,
      color: Color(0xFF14B8A6),
      entityGroup: 'shareholder',
    ),
    BeneficiaryCategoryOption(
      key: 'expense',
      label: 'حساب مصروف (شجرة الحسابات)',
      shortLabel: 'حساب مصروف',
      icon: Icons.account_tree_outlined,
      color: Color(0xFFEAB308),
      entityGroup: 'expense',
    ),
  ];

  @override
  State<BeneficiarySelectorField> createState() =>
      _BeneficiarySelectorFieldState();
}

class _BeneficiarySelectorFieldState extends State<BeneficiarySelectorField> {
  late String _selectedCategoryKey;
  BeneficiaryDropdownItem? _selectedEntity;
  String? _selectedExpenseAccountId;
  String? _selectedCostCenterId;
  Map<String, dynamic>? _selectedExpenseAccountMap;

  final TextEditingController _searchCtrl = TextEditingController();
  List<BeneficiaryDropdownItem> _cachedItems = [];
  List<BeneficiaryDropdownItem> _filteredItems = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedCategoryKey = widget.initialBeneficiaryType ?? 'all_suppliers';
    _selectedExpenseAccountId = widget.initialExpenseAccountId;
    _selectedCostCenterId = widget.initialCostCenterId;

    if (widget.initialEntityId != null && widget.initialEntityName != null) {
      final cat = _findCategory(_selectedCategoryKey);
      _selectedEntity = BeneficiaryDropdownItem(
        id: widget.initialEntityId!,
        name: widget.initialEntityName!,
        categoryKey: cat.key,
        categoryLabel: cat.label,
        categoryColor: cat.color,
      );
    }

    _loadEntitiesForCategory(_selectedCategoryKey);
  }

  @override
  void didUpdateWidget(covariant BeneficiarySelectorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialBeneficiaryType != null &&
        widget.initialBeneficiaryType != oldWidget.initialBeneficiaryType) {
      _selectedCategoryKey = widget.initialBeneficiaryType!;
      _loadEntitiesForCategory(_selectedCategoryKey);
    }
    if (widget.initialExpenseAccountId != oldWidget.initialExpenseAccountId) {
      _selectedExpenseAccountId = widget.initialExpenseAccountId;
    }
    if (widget.initialCostCenterId != oldWidget.initialCostCenterId) {
      _selectedCostCenterId = widget.initialCostCenterId;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  BeneficiaryCategoryOption _findCategory(String key) {
    return BeneficiarySelectorField.categories.firstWhere(
      (c) => c.key == key,
      orElse: () => BeneficiarySelectorField.categories.first,
    );
  }

  Future<void> _loadEntitiesForCategory(String categoryKey) async {
    if (categoryKey == 'expense') {
      setState(() {
        _cachedItems = [];
        _filteredItems = [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final category = _findCategory(categoryKey);
      List<BeneficiaryDropdownItem> loaded = [];

      if (category.entityGroup == 'supplier') {
        List<String>? types;
        if (categoryKey != 'all_suppliers') {
          if (categoryKey == 'deduction') {
            types = ['deduction', 'deductions'];
          } else {
            types = [categoryKey];
          }
        }

        final suppliers = await SupplierDao().getAllSuppliers(supplierTypes: types);
        for (final s in suppliers) {
          final codeNum = int.tryParse(s.supplierCode.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          final sType = s.supplierType.toLowerCase().trim();

          bool matches = true;
          if (categoryKey != 'all_suppliers') {
            switch (categoryKey) {
              case 'crop':
                matches = sType == 'crop' || (codeNum >= 50000 && codeNum <= 59999);
                break;
              case 'transport':
                matches = sType == 'transport' || (codeNum >= 60000 && codeNum <= 69999);
                break;
              case 'packaging':
                matches = sType == 'packaging' || sType == 'sticker' || (codeNum >= 70000 && codeNum <= 74999);
                break;
              case 'shared':
                matches = sType == 'shared' || (codeNum >= 75000 && codeNum <= 79999);
                break;
              case 'station':
                matches = sType == 'station' || (codeNum >= 85000 && codeNum <= 89999);
                break;
              case 'deduction':
                matches = sType == 'deduction' || sType == 'deductions' || (codeNum >= 40000 && codeNum <= 49999);
                break;
            }
          }

          if (matches) {
            loaded.add(BeneficiaryDropdownItem(
              id: s.id.toString(),
              name: s.name,
              code: s.supplierCode,
              currency: s.currency.isEmpty ? 'EGP' : s.currency,
              balance: s.outstandingBalance,
              categoryKey: categoryKey,
              categoryLabel: category.shortLabel,
              categoryColor: category.color,
              accountId: s.accountId,
              supplierModel: s,
            ));
          }
        }

        // دمج موردي النقل المسجلين في جدول transport_suppliers إن وجدوا
        if (categoryKey == 'all_suppliers' || categoryKey == 'transport') {
          try {
            final transSuppliers = await TransportSupplierDao().getAll(limit: 50);
            for (final t in transSuppliers) {
              final alreadyIn = loaded.any((e) => e.name == t.name || (t.code.isNotEmpty && e.code == t.code));
              if (!alreadyIn) {
                loaded.add(BeneficiaryDropdownItem(
                  id: t.id.toString(),
                  name: t.name,
                  code: t.code,
                  currency: 'EGP',
                  balance: t.balance,
                  categoryKey: 'transport',
                  categoryLabel: 'مورد نقل',
                  categoryColor: const Color(0xFF0284C7),
                  accountId: t.accountId,
                ));
              }
            }
          } catch (_) {}
        }
      } else if (category.entityGroup == 'shipping') {
        final companies = await ShippingCompanyDao().getAll(limit: 100);
        for (final c in companies) {
          loaded.add(BeneficiaryDropdownItem(
            id: c.id.toString(),
            name: c.name,
            code: c.code,
            currency: c.currency.isEmpty ? 'EGP' : c.currency,
            balance: c.balance,
            categoryKey: 'shipping_company',
            categoryLabel: 'شركة شحن',
            categoryColor: category.color,
          ));
        }
      } else if (category.entityGroup == 'clearing') {
        final agents = await ClearingAgentDao().getAll(limit: 100);
        for (final a in agents) {
          loaded.add(BeneficiaryDropdownItem(
            id: a.id?.toString() ?? '',
            name: a.name,
            code: a.code,
            currency: a.currency.isEmpty ? 'EGP' : a.currency,
            balance: a.balance,
            categoryKey: 'clearing_agent',
            categoryLabel: 'مخلص جمركي',
            categoryColor: category.color,
          ));
        }
      } else if (category.entityGroup == 'shareholder') {
        final shareholders = await ShareholderDao().getAll(limit: 100);
        for (final sh in shareholders) {
          loaded.add(BeneficiaryDropdownItem(
            id: sh.id?.toString() ?? '',
            name: sh.name,
            code: sh.code,
            currency: 'EGP',
            balance: sh.currentBalanceEgp != 0 ? sh.currentBalanceEgp : (sh.totalDepositsEgp - sh.totalWithdrawalsEgp),
            categoryKey: 'shareholder',
            categoryLabel: 'مساهم',
            categoryColor: category.color,
          ));
        }
      }

      if (mounted) {
        setState(() {
          _cachedItems = loaded;
          _filteredItems = loaded;
          _isLoading = false;

          // إذا كانت الجهة المختارة مسجلة، نقوم بربط بياناتها المحدثة
          if (_selectedEntity != null) {
            final match = loaded.where((e) => e.id == _selectedEntity!.id).firstOrNull;
            if (match != null) {
              _selectedEntity = match;
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onCategoryChanged(String newKey) {
    setState(() {
      _selectedCategoryKey = newKey;
      _selectedEntity = null;
      _searchCtrl.clear();
    });

    _loadEntitiesForCategory(newKey);

    widget.onChanged(BeneficiarySelection(
      beneficiaryType: newKey,
      expenseAccountId: newKey == 'expense' ? _selectedExpenseAccountId : null,
      costCenterId: newKey == 'expense' ? _selectedCostCenterId : null,
      expenseAccountMap: newKey == 'expense' ? _selectedExpenseAccountMap : null,
    ));
  }

  void _onEntitySelected(BeneficiaryDropdownItem item) {
    setState(() => _selectedEntity = item);
    widget.onChanged(BeneficiarySelection(
      beneficiaryType: item.categoryKey,
      entityId: item.id,
      entityName: item.name,
      entityCode: item.code,
      currency: item.currency,
      currentBalance: item.balance,
      accountId: item.accountId,
      supplierModel: item.supplierModel,
    ));
  }

  void _filterList(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filteredItems = _cachedItems;
      } else {
        _filteredItems = _cachedItems.where((e) {
          return e.name.toLowerCase().contains(q) ||
              e.code.toLowerCase().contains(q);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentCat = _findCategory(_selectedCategoryKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 1. عنوان الحقل ──
        Row(
          children: [
            Icon(Icons.supervised_user_circle_outlined,
                size: 16, color: currentCat.color),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'جهة الصرف / المستفيد (Beneficiary Entity) *',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── 2. حقل اختيار تصنيف المستفيد (Beneficiary Category Dropdown) ──
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surface : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _selectedCategoryKey,
              dropdownColor: isDark ? const Color(0xFF04192F) : Colors.white,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              items: BeneficiarySelectorField.categories.map((cat) {
                return DropdownMenuItem<String>(
                  value: cat.key,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: cat.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(cat.icon, size: 16, color: cat.color),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        cat.label,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) _onCategoryChanged(val);
              },
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── 3. القائمة التفاعلية لجلب الأسماء المسجلة ──
        if (_selectedCategoryKey == 'expense') ...[
          // حالة حساب المصروف من شجرة الحسابات
          COAExpenseDropdown(
            accounts: widget.expenseAccounts,
            rootCodeFilter: '31',
            selectedAccountId: _selectedExpenseAccountId,
            selectedCostCenterId: _selectedCostCenterId,
            showInlineCostCenterCard: false,
            onSelected: (acct, suggestedCc) {
              setState(() {
                _selectedExpenseAccountId = acct?['id']?.toString();
                _selectedExpenseAccountMap = acct;
                if (acct != null) {
                  _selectedCostCenterId ??= (acct['cost_center_id']?.toString() ?? suggestedCc);
                }
              });
              widget.onChanged(BeneficiarySelection(
                beneficiaryType: 'expense',
                expenseAccountId: _selectedExpenseAccountId,
                costCenterId: _selectedCostCenterId,
                expenseAccountMap: _selectedExpenseAccountMap,
              ));
            },
            onAccountCreated: widget.onAccountCreated,
          ),
          const SizedBox(height: 10),
          CostCenterSelectorField(
            label: 'مركز التكلفة / القسم المستفيد (Cost Center) *',
            selectedCostCenterId: _selectedCostCenterId,
            isRequired: true,
            onSelected: (ccId) {
              setState(() => _selectedCostCenterId = ccId);
              widget.onChanged(BeneficiarySelection(
                beneficiaryType: 'expense',
                expenseAccountId: _selectedExpenseAccountId,
                costCenterId: _selectedCostCenterId,
                expenseAccountMap: _selectedExpenseAccountMap,
              ));
            },
          ),
        ] else ...[
          // حالة الموردين / شركات الشحن / المخلصين / المساهمين
          if (_isLoading)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'جارٍ جلب الأسماء المسجلة لـ ${currentCat.shortLabel}...',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          else if (_selectedEntity == null) ...[
            // قائمة منسدلة تفاعلية مع إمكانية البحث
            Container(
              decoration: BoxDecoration(
                color: isDark ? AppTheme.surface : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1),
                ),
              ),
              child: Column(
                children: [
                  // حقل البحث السريع في القائمة
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: _filterList,
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'ابحث عن اسم أو كود ${currentCat.shortLabel}...',
                        hintStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11.5),
                        prefixIcon: const Icon(Icons.search, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1),
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                    ),
                  ),

                  // قائمة الأسماء المسجلة المنسدلة
                  if (_filteredItems.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        _cachedItems.isEmpty
                            ? 'لا توجد أسماء مسجلة في هذا التصنيف'
                            : 'لا توجد نتائج مطابقة للبحث',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: isDark ? AppTheme.textMuted : const Color(0xFF64748B),
                        ),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _filteredItems.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0),
                        ),
                        itemBuilder: (ctx, idx) {
                          final item = _filteredItems[idx];
                          return InkWell(
                            onTap: () => _onEntitySelected(item),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: item.categoryColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      item.code.isNotEmpty ? item.code : item.categoryLabel,
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: item.categoryColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      item.name,
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : Colors.black87,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    'رصيد: ${AppUtils.formatCurrency(item.balance, item.currency)}',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: item.balance > 0
                                          ? AppTheme.danger
                                          : (isDark ? AppTheme.textSecondary : const Color(0xFF475569)),
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
          ] else ...[
            // بطاقة الجهة المختارة
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: currentCat.color.withValues(alpha: isDark ? 0.12 : 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: currentCat.color.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: currentCat.color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(currentCat.icon, size: 20, color: currentCat.color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          children: [
                            Text(
                              _selectedEntity!.name,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            if (_selectedEntity!.code.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: currentCat.color.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '#${_selectedEntity!.code}',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: currentCat.color,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'الرصيد الحالي المستحق: ${AppUtils.formatCurrency(_selectedEntity!.balance, _selectedEntity!.currency)}',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: _selectedEntity!.balance > 0
                                ? AppTheme.danger
                                : (isDark ? AppTheme.textSecondary : const Color(0xFF475569)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    onPressed: () {
                      setState(() => _selectedEntity = null);
                      _loadEntitiesForCategory(_selectedCategoryKey);
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text(
                      'تغيير',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}
