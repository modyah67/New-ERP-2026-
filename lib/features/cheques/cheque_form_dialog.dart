import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/widgets/read_only_guard.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/clearing_agent_model.dart';
import '../../data/models/shipping_company_model.dart';
import '../../data/models/shareholder_model.dart';
import '../../data/models/account_model.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/services/currency_conversion_service.dart';
import 'cheque_cubit.dart';
import 'cheque_state.dart';

class ChequeFormDialog extends StatefulWidget {
  final String type;
  const ChequeFormDialog({super.key, required this.type});

  @override
  State<ChequeFormDialog> createState() => _ChequeFormDialogState();
}

class _ChequeFormDialogState extends State<ChequeFormDialog> {
  String _currency = 'EGP';
  final TextEditingController _exchangeRateCtrl = TextEditingController(text: '1.00');
  DateTime _issueDate = DateTime.now();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 30));
  String? _counterpartyType;
  String? _counterpartyId;
  String? _supplierId;
  SupplierModel? _selectedSupplier;
  String? _counterpartyName;
  bool _isSaving = false;
  int? _selectedCategoryId;
  List<Map<String, dynamic>> _expenseCategories = [];
  int? _selectedExpenseAccountId;
  List<Map<String, dynamic>> _treasuries = [];
  int? _selectedTreasuryId;

  static const List<String> _defaultCurrencies = ['EGP', 'USD', 'EUR', 'GBP'];
  List<String> _currencies = ['EGP', 'USD', 'EUR', 'GBP'];

  bool get _isCounterpartyValid {
    if (_counterpartyType == null) return false;
    switch (_counterpartyType) {
      case 'customer':
        return _counterpartyId != null && _counterpartyId!.isNotEmpty;
      case 'supplier':
        return _supplierId != null && _supplierId!.isNotEmpty;
      case 'shareholder':
      case 'clearing_agent':
      case 'shipping_company':
        return _counterpartyId != null && _counterpartyId!.isNotEmpty;
      case 'treasury':
        return _selectedTreasuryId != null;
      default:
        return false;
    }
  }

  void _onSearchChanged() {
    if (_counterpartyId != null || _supplierId != null || _counterpartyName != null || _selectedSupplier != null) {
      setState(() {
        _counterpartyId = null;
        _supplierId = null;
        _selectedSupplier = null;
        _counterpartyName = null;
        _currencies = List.from(_defaultCurrencies);
      });
      _updateExchangeRate(_currency);
    }
  }

  void _updateCurrenciesForSupplier(SupplierModel supplier) {
    if (supplier.isEgpOnlySupplier) {
      _currencies = ['EGP'];
      _currency = 'EGP';
      _updateExchangeRate('EGP');
      return;
    }
    final curSet = <String>{};
    if (supplier.isMultiCurrency) {
      for (final c in supplier.supportedCurrencies) {
        final u = c.toUpperCase().trim();
        if (_defaultCurrencies.contains(u)) curSet.add(u);
      }
      for (final c in supplier.initialBalancesByCurrency.keys) {
        final u = c.toUpperCase().trim();
        if (_defaultCurrencies.contains(u)) curSet.add(u);
      }
      for (final c in supplier.currentBalancesByCurrency.keys) {
        final u = c.toUpperCase().trim();
        if (_defaultCurrencies.contains(u)) curSet.add(u);
      }
    } else {
      final u = supplier.currency.toUpperCase().trim();
      if (_defaultCurrencies.contains(u)) {
        curSet.add(u);
      }
    }

    _currencies = curSet.isNotEmpty ? curSet.toList() : List.from(_defaultCurrencies);
    if (!_currencies.contains(_currency)) {
      _currency = _currencies.first;
    }
    _updateExchangeRate(_currency);
  }

  void _setEntityCurrency(String? rawCurrency) {
    if (rawCurrency != null && rawCurrency.isNotEmpty && rawCurrency.toUpperCase() != 'MULTI') {
      final upper = rawCurrency.toUpperCase().trim();
      if (_defaultCurrencies.contains(upper)) {
        _currencies = [upper];
        _currency = upper;
        _updateExchangeRate(_currency);
        return;
      }
    }
    _currencies = List.from(_defaultCurrencies);
    if (!_currencies.contains(_currency)) {
      _currency = 'EGP';
    }
    _updateExchangeRate(_currency);
  }

  Future<void> _updateExchangeRate(String currency) async {
    if (currency.toUpperCase() == 'EGP') {
      if (mounted) {
        setState(() {
          _exchangeRateCtrl.text = '1.00';
        });
      }
      return;
    }
    try {
      final rate = await CurrencyConversionService.instance.getRate(currency);
      if (rate > 0 && mounted) {
        setState(() {
          _exchangeRateCtrl.text = rate.toStringAsFixed(2);
        });
      }
    } catch (e) {
      debugPrint('Error fetching exchange rate for $currency: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadTreasuries();
    _updateExchangeRate(_currency);
  }

  @override
  void dispose() {
    _exchangeRateCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTreasuries() async {
    try {
      final data = await Supabase.instance.client
          .from('treasuries')
          .select('id, name, type')
          .order('type', ascending: true)
          .order('name');
      if (mounted) {
        setState(() {
          _treasuries = List<Map<String, dynamic>>.from(data);
          // Default to main treasury
          final main = _treasuries.where((t) => t['type'] == 'main').toList();
          if (main.isNotEmpty) {
            _selectedTreasuryId = main.first['id'] as int;
          } else if (_treasuries.isNotEmpty) {
            _selectedTreasuryId = _treasuries.first['id'] as int;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _loadCategories() async {
    try {
      final data = await Supabase.instance.client
          .from('expense_categories')
          .select('id, name, currency')
          .eq('is_active', true)
          .order('name');
      if (mounted) setState(() => _expenseCategories = List<Map<String, dynamic>>.from(data));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = context.read<ChequeCubit>();
    final isOutgoing = widget.type == 'outgoing';
    final title = isOutgoing ? 'إضافة شيك صادر' : 'إضافة شيك وارد';
    final subtitle = isOutgoing ? 'صرف شيك لعميل أو مورد' : 'استلام شيك من عميل';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final isMobile = w < 700;
          final titleSize = isMobile ? 18.0 : 20.0;
          final subtitleSize = isMobile ? 11.0 : 13.0;
          final labelSize = isMobile ? 11.0 : 12.0;
          final bodySize = isMobile ? 12.0 : 13.0;
          final amountSize = isMobile ? 18.0 : 22.0;
          final pad = isMobile ? 16.0 : 28.0;
          final spacing = isMobile ? 12.0 : 16.0;

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF0A1630) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
            ),
            insetPadding: EdgeInsets.all(isMobile ? 12 : 24),
            contentPadding: EdgeInsets.all(pad),
            content: SizedBox(
              width: isMobile ? 500 : 600,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(isOutgoing, title, subtitle, titleSize, subtitleSize, isMobile, isDark),
                    SizedBox(height: spacing + 8),
                    _buildChequeNumberAndCurrency(c, isMobile, spacing, labelSize, isDark),
                    SizedBox(height: spacing + 4),
                    _buildLabel('المبلغ', Icons.attach_money, AppTheme.success, labelSize),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: c.amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*')),
                      ],
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: amountSize, fontWeight: FontWeight.bold, fontFamily: 'Cairo', color: AppTheme.success),
                      decoration: InputDecoration(
                        hintText: '0.00',
                        prefixIcon: const Icon(Icons.attach_money, color: AppTheme.success),
                        suffixText: _currency,
                        suffixStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: AppTheme.success),
                      ),
                    ),
                    ListenableBuilder(
                      listenable: Listenable.merge([c.amountCtrl, _exchangeRateCtrl]),
                      builder: (context, _) {
                        final isForeign = _currency.toUpperCase() != 'EGP';
                        if (!isForeign) return const SizedBox.shrink();

                        final amount = double.tryParse(c.amountCtrl.text.trim()) ?? 0.0;
                        final rate = double.tryParse(_exchangeRateCtrl.text.trim()) ?? 1.0;
                        final egpTotal = amount * rate;

                        return Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.primary.withValues(alpha: 0.12) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: isDark ? AppTheme.primary.withValues(alpha: 0.3) : const Color(0xFFCBD5E1)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.currency_exchange, size: 16, color: isDark ? AppTheme.accent : const Color(0xFF0284C7)),
                                  const SizedBox(width: 8),
                                  Text(
                                    'المعادل بالجنيه المصري:',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: isMobile ? 11 : 12,
                                      fontWeight: isDark ? FontWeight.normal : FontWeight.w600,
                                      color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '${AppUtils.formatCurrency(egpTotal)} ج.م',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: isMobile ? 13 : 14,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? AppTheme.accent : const Color(0xFF0284C7),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    SizedBox(height: spacing + 4),
                    _buildDateFields(isMobile, spacing, labelSize, isDark),
                    SizedBox(height: spacing + 4),

                    if (!isOutgoing) ...[
                      _buildLabel('المُرسِل (المصدر)', Icons.person_outline, AppTheme.accent, labelSize),
                      const SizedBox(height: 8),
                      _buildCounterpartyButtonsIncoming(isDark),
                      const SizedBox(height: 8),
                      if (_counterpartyType == 'treasury')
                        _buildTreasurySelector(AppTheme.success, isDark),
                      if (_counterpartyType == 'customer')
                        _CustomerSearchWidget(
                          cubit: c,
                          onSearchChanged: _onSearchChanged,
                          onSelected: (customer) {
                            setState(() {
                              _counterpartyType = 'customer';
                              _counterpartyId = customer.id;
                              _counterpartyName = customer.name;
                              c.customerSearchCtrl.text = customer.name;
                              c.searchCustomers('');
                              _setEntityCurrency(customer.currency);
                            });
                          },
                        ),
                      if (_counterpartyType == 'supplier')
                        _SupplierSearchWidget(
                          cubit: c,
                          selectedSupplier: _selectedSupplier,
                          currentCurrency: _currency,
                          onCurrencyTapped: (curr) {
                            setState(() {
                              _currency = curr;
                              _updateExchangeRate(curr);
                            });
                          },
                          onClearSelected: () {
                            setState(() {
                              _selectedSupplier = null;
                              _supplierId = null;
                              _counterpartyId = null;
                              _counterpartyName = null;
                              c.supplierSearchCtrl.clear();
                              c.searchSuppliers('');
                            });
                          },
                          onSearchChanged: _onSearchChanged,
                          onSelected: (supplier) async {
                            setState(() {
                              _selectedSupplier = supplier;
                              _supplierId = supplier.id;
                              _counterpartyId = supplier.id;
                              _counterpartyName = supplier.name;
                              c.supplierSearchCtrl.text = supplier.name;
                              c.searchSuppliers('');
                              _updateCurrenciesForSupplier(supplier);
                            });
                            if (supplier.id != null) {
                              try {
                                final live = await SupplierDao().getSupplierBalancesByCurrency(supplier.id!);
                                if (live.isNotEmpty && mounted && _selectedSupplier?.id == supplier.id) {
                                  setState(() {
                                    _selectedSupplier = _selectedSupplier!.copyWith(currentBalancesByCurrency: live);
                                  });
                                }
                              } catch (_) {}
                            }
                          },
                        ),
                      if (_counterpartyType == 'clearing_agent')
                        _ClearingAgentSearchWidget(
                          cubit: c,
                          onSearchChanged: _onSearchChanged,
                          onSelected: (agent) {
                            setState(() {
                              _counterpartyType = 'clearing_agent';
                              _counterpartyId = agent.id;
                              _counterpartyName = agent.name;
                              c.clearingAgentSearchCtrl.text = agent.name;
                              c.searchClearingAgents('');
                              _setEntityCurrency(agent.currency);
                            });
                          },
                        ),
                      if (_counterpartyType == 'shipping_company')
                        _ShippingCompanySearchWidget(
                          cubit: c,
                          onSearchChanged: _onSearchChanged,
                          onSelected: (company) {
                            setState(() {
                              _counterpartyType = 'shipping_company';
                              _counterpartyId = company.id?.toString();
                              _counterpartyName = company.name;
                              c.shippingCompanySearchCtrl.text = company.name;
                              c.searchShippingCompanies('');
                              _setEntityCurrency(company.currency);
                            });
                          },
                        ),
                      if (_counterpartyType == 'shareholder')
                        _ShareholderSearchWidget(
                          cubit: c,
                          onSearchChanged: _onSearchChanged,
                          onSelected: (shareholder) {
                            setState(() {
                              _counterpartyType = 'shareholder';
                              _counterpartyId = shareholder.id?.toString();
                              _counterpartyName = shareholder.name;
                              c.shareholderSearchCtrl.text = shareholder.name;
                              c.searchShareholders('');
                            });
                          },
                        ),

                      if (_counterpartyName != null && _isCounterpartyValid && _counterpartyType != 'treasury' && _counterpartyType != 'supplier') ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.success.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle_rounded, size: 14, color: AppTheme.success),
                              const SizedBox(width: 6),
                              Text(
                                'تم التحديد: $_counterpartyName',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.success,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (_counterpartyType == null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('اختر نوع المُرسِل أولاً',
                            style: TextStyle(color: isDark ? AppTheme.textMuted : const Color(0xFF64748B), fontSize: 12, fontFamily: 'Cairo')),
                      ),
                    ] else ...[
                      _buildLabel('المستلم', Icons.people_outline, AppTheme.accent, labelSize),
                      const SizedBox(height: 8),
                      _buildCounterpartyButtonsOutgoing(isDark),
                      const SizedBox(height: 8),
                      if (_counterpartyType == 'treasury')
                        _buildTreasurySelector(AppTheme.primary, isDark),
                      if (_counterpartyType == 'customer')
                        _CustomerSearchWidget(
                          cubit: c,
                          onSearchChanged: _onSearchChanged,
                          onSelected: (customer) {
                            setState(() {
                              _counterpartyType = 'customer';
                              _counterpartyId = customer.id;
                              _counterpartyName = customer.name;
                              c.customerSearchCtrl.text = customer.name;
                              c.searchCustomers('');
                              _setEntityCurrency(customer.currency);
                            });
                          },
                        ),
                      if (_counterpartyType == 'supplier')
                        _SupplierSearchWidget(
                          cubit: c,
                          selectedSupplier: _selectedSupplier,
                          currentCurrency: _currency,
                          onCurrencyTapped: (curr) {
                            setState(() {
                              _currency = curr;
                              _updateExchangeRate(curr);
                            });
                          },
                          onClearSelected: () {
                            setState(() {
                              _selectedSupplier = null;
                              _supplierId = null;
                              _counterpartyId = null;
                              _counterpartyName = null;
                              c.supplierSearchCtrl.clear();
                              c.searchSuppliers('');
                            });
                          },
                          onSearchChanged: _onSearchChanged,
                          onSelected: (supplier) async {
                            setState(() {
                              _selectedSupplier = supplier;
                              _supplierId = supplier.id;
                              _counterpartyId = supplier.id;
                              _counterpartyName = supplier.name;
                              c.supplierSearchCtrl.text = supplier.name;
                              c.searchSuppliers('');
                              _updateCurrenciesForSupplier(supplier);
                            });
                            if (supplier.id != null) {
                              try {
                                final live = await SupplierDao().getSupplierBalancesByCurrency(supplier.id!);
                                if (live.isNotEmpty && mounted && _selectedSupplier?.id == supplier.id) {
                                  setState(() {
                                    _selectedSupplier = _selectedSupplier!.copyWith(currentBalancesByCurrency: live);
                                  });
                                }
                              } catch (_) {}
                            }
                          },
                        ),
                      if (_counterpartyType == 'clearing_agent')
                        _ClearingAgentSearchWidget(
                          cubit: c,
                          onSearchChanged: _onSearchChanged,
                          onSelected: (agent) {
                            setState(() {
                              _counterpartyType = 'clearing_agent';
                              _counterpartyId = agent.id;
                              _counterpartyName = agent.name;
                              c.clearingAgentSearchCtrl.text = agent.name;
                              c.searchClearingAgents('');
                              _setEntityCurrency(agent.currency);
                            });
                          },
                        ),
                      if (_counterpartyType == 'shipping_company')
                        _ShippingCompanySearchWidget(
                          cubit: c,
                          onSearchChanged: _onSearchChanged,
                          onSelected: (company) {
                            setState(() {
                              _counterpartyType = 'shipping_company';
                              _counterpartyId = company.id?.toString();
                              _counterpartyName = company.name;
                              c.shippingCompanySearchCtrl.text = company.name;
                              c.searchShippingCompanies('');
                              _setEntityCurrency(company.currency);
                            });
                          },
                        ),
                      if (_counterpartyType == 'shareholder')
                        _ShareholderSearchWidget(
                          cubit: c,
                          onSearchChanged: _onSearchChanged,
                          onSelected: (shareholder) {
                            setState(() {
                              _counterpartyType = 'shareholder';
                              _counterpartyId = shareholder.id?.toString();
                              _counterpartyName = shareholder.name;
                              c.shareholderSearchCtrl.text = shareholder.name;
                              c.searchShareholders('');
                            });
                          },
                        ),

                      if (_counterpartyName != null && _isCounterpartyValid && _counterpartyType != 'treasury' && _counterpartyType != 'supplier') ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.success.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle_rounded, size: 14, color: AppTheme.success),
                              const SizedBox(width: 6),
                              Text(
                                'تم التحديد: $_counterpartyName',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.success,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (_counterpartyType == null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('اختر نوع المستلم أولاً',
                            style: TextStyle(color: isDark ? AppTheme.textMuted : const Color(0xFF64748B), fontSize: 12, fontFamily: 'Cairo')),
                      ),
                    ],
                    SizedBox(height: spacing + 4),
                    _buildLabel('ملاحظة (اختياري)', Icons.notes_outlined, AppTheme.textSecondary, labelSize),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: c.notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(hintText: 'ملاحظات...'),
                      style: TextStyle(fontFamily: 'Cairo', fontSize: bodySize),
                    ),
                    SizedBox(height: spacing + 8),
                    _buildActionButtons(isOutgoing, isMobile, spacing, isDark),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(bool isOutgoing, String title, String subtitle, double titleSize, double subtitleSize, bool isMobile, bool isDark) {
    return Row(children: [
      Container(
        width: isMobile ? 38 : 44, height: isMobile ? 38 : 44,
        decoration: BoxDecoration(
          color: isOutgoing
              ? AppTheme.danger.withValues(alpha: isDark ? 0.1 : 0.12)
              : AppTheme.success.withValues(alpha: isDark ? 0.1 : 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          isOutgoing ? Icons.upload_outlined : Icons.download_outlined,
          color: isOutgoing ? AppTheme.danger : AppTheme.success,
          size: isMobile ? 20 : 22,
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: isDark ? Colors.white : Colors.black, fontSize: titleSize, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B), fontSize: subtitleSize, fontFamily: 'Cairo')),
          ],
        ),
      ),
    ]);
  }

  Widget _buildChequeNumberAndCurrency(ChequeCubit c, bool isMobile, double spacing, double labelSize, bool isDark) {
    final isEgp = _currency.toUpperCase() == 'EGP';

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabel('رقم الشيك', Icons.numbers, AppTheme.primary, labelSize),
          const SizedBox(height: 6),
          TextFormField(
            controller: c.chequeNumberCtrl,
            decoration: const InputDecoration(hintText: 'رقم الشيك'),
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          SizedBox(height: spacing),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('العملة', Icons.monetization_on_outlined, AppTheme.accent, labelSize),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      key: ValueKey('cheque_currency_${_currency}_${_currencies.join("_")}'),
                      initialValue: _currencies.contains(_currency) ? _currency : _currencies.first,
                      dropdownColor: isDark ? const Color(0xFF0A1630) : Colors.white,
                      items: _currencies.map((cur) => DropdownMenuItem(
                        value: cur,
                        child: Text(cur, style: TextStyle(fontFamily: 'Cairo', color: isDark ? Colors.white : Colors.black)),
                      )).toList(),
                      onChanged: (_selectedSupplier?.isEgpOnlySupplier == true) ? null : (v) {
                        final newCur = v ?? _currencies.first;
                        setState(() => _currency = newCur);
                        _updateExchangeRate(newCur);
                      },
                      decoration: const InputDecoration(),
                      style: TextStyle(fontFamily: 'Cairo', color: isDark ? Colors.white : Colors.black),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('سعر الصرف (ج.م)', Icons.currency_exchange, isEgp ? (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)) : AppTheme.warning, labelSize),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _exchangeRateCtrl,
                      readOnly: true,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        color: isEgp ? (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)) : (isDark ? AppTheme.accent : const Color(0xFF0284C7)),
                      ),
                      decoration: InputDecoration(
                        hintText: '1.00',
                        prefixIcon: Icon(Icons.lock_outline, size: 16, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                        suffixIcon: isEgp
                            ? null
                            : IconButton(
                                icon: Icon(Icons.refresh, size: 18, color: isDark ? AppTheme.accent : const Color(0xFF0284C7)),
                                tooltip: 'تحديث سعر الصرف الرسمي',
                                onPressed: () => _updateExchangeRate(_currency),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            flex: 4,
            child: _buildLabel('رقم الشيك', Icons.numbers, AppTheme.primary, labelSize),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: _buildLabel('العملة', Icons.monetization_on_outlined, AppTheme.accent, labelSize),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: _buildLabel('سعر الصرف (ج.م)', Icons.currency_exchange, isEgp ? (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)) : AppTheme.warning, labelSize),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            flex: 4,
            child: TextFormField(
              controller: c.chequeNumberCtrl,
              decoration: const InputDecoration(hintText: 'رقم الشيك'),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              key: ValueKey('cheque_currency_${_currency}_${_currencies.join("_")}'),
              initialValue: _currencies.contains(_currency) ? _currency : _currencies.first,
              dropdownColor: isDark ? const Color(0xFF0A1630) : Colors.white,
              items: _currencies.map((cur) => DropdownMenuItem(
                value: cur,
                child: Text(cur, style: TextStyle(fontFamily: 'Cairo', color: isDark ? Colors.white : Colors.black)),
              )).toList(),
              onChanged: (_selectedSupplier?.isEgpOnlySupplier == true) ? null : (v) {
                final newCur = v ?? _currencies.first;
                setState(() => _currency = newCur);
                _updateExchangeRate(newCur);
              },
              decoration: const InputDecoration(),
              style: TextStyle(fontFamily: 'Cairo', color: isDark ? Colors.white : Colors.black),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: _exchangeRateCtrl,
              readOnly: true,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                color: isEgp ? (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)) : (isDark ? AppTheme.accent : const Color(0xFF0284C7)),
              ),
              decoration: InputDecoration(
                hintText: '1.00',
                prefixIcon: Icon(Icons.lock_outline, size: 16, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                suffixIcon: isEgp
                    ? null
                    : IconButton(
                        icon: Icon(Icons.refresh, size: 18, color: isDark ? AppTheme.accent : const Color(0xFF0284C7)),
                        tooltip: 'تحديث سعر الصرف الرسمي',
                        onPressed: () => _updateExchangeRate(_currency),
                      ),
              ),
            ),
          ),
        ]),
      ],
    );
  }

  Widget _buildDateFields(bool isMobile, double spacing, double labelSize, bool isDark) {
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabel('تاريخ التحرير', Icons.calendar_today, AppTheme.info, labelSize),
          const SizedBox(height: 6),
          _DatePickerField(
            date: _issueDate,
            onChanged: (d) => setState(() => _issueDate = d),
          ),
          SizedBox(height: spacing),
          _buildLabel('تاريخ الاستحقاق', Icons.date_range, AppTheme.warning, labelSize),
          const SizedBox(height: 6),
          _DatePickerField(
            date: _dueDate,
            onChanged: (d) => setState(() => _dueDate = d),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: _buildLabel('تاريخ التحرير', Icons.calendar_today, AppTheme.info, labelSize)),
          const SizedBox(width: 16),
          Expanded(child: _buildLabel('تاريخ الاستحقاق', Icons.date_range, AppTheme.warning, labelSize)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: _DatePickerField(
            date: _issueDate,
            onChanged: (d) => setState(() => _issueDate = d),
          )),
          const SizedBox(width: 16),
          Expanded(child: _DatePickerField(
            date: _dueDate,
            onChanged: (d) => setState(() => _dueDate = d),
          )),
        ]),
      ],
    );
  }

  Widget _buildCounterpartyButtonsIncoming(bool isDark) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildSmallBtn('عميل (تصدير)', _counterpartyType == 'customer', () {
              setState(() {
                _counterpartyType = 'customer';
                _counterpartyId = null; _counterpartyName = null;
                context.read<ChequeCubit>().customerSearchCtrl.clear();
                _currencies = List.from(_defaultCurrencies);
              });
            }, isDark)),
            const SizedBox(width: 6),
            Expanded(child: _buildSmallBtn('مورد', _counterpartyType == 'supplier', () {
              setState(() {
                _counterpartyType = 'supplier';
                _counterpartyId = null; _supplierId = null; _counterpartyName = null;
                context.read<ChequeCubit>().supplierSearchCtrl.clear();
                _currencies = List.from(_defaultCurrencies);
              });
            }, isDark)),
            const SizedBox(width: 6),
            Expanded(child: _buildSmallBtn('مساهم', _counterpartyType == 'shareholder', () {
              setState(() {
                _counterpartyType = 'shareholder';
                _counterpartyId = null; _counterpartyName = null;
                context.read<ChequeCubit>().shareholderSearchCtrl.clear();
                _currencies = List.from(_defaultCurrencies);
              });
            }, isDark)),
          ],
        ),
      ],
    );
  }

  Widget _buildCounterpartyButtonsOutgoing(bool isDark) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildSmallBtn('مورد', _counterpartyType == 'supplier', () {
              setState(() {
                _counterpartyType = 'supplier';
                _counterpartyId = null; _supplierId = null; _counterpartyName = null;
                context.read<ChequeCubit>().supplierSearchCtrl.clear();
                _currencies = List.from(_defaultCurrencies);
              });
            }, isDark)),
            const SizedBox(width: 6),
            Expanded(child: _buildSmallBtn('مساهم', _counterpartyType == 'shareholder', () {
              setState(() {
                _counterpartyType = 'shareholder';
                _counterpartyId = null; _counterpartyName = null;
                context.read<ChequeCubit>().shareholderSearchCtrl.clear();
                _currencies = List.from(_defaultCurrencies);
              });
            }, isDark)),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: _buildSmallBtn('مخلص', _counterpartyType == 'clearing_agent', () {
              setState(() {
                _counterpartyType = 'clearing_agent';
                _counterpartyId = null; _counterpartyName = null;
                context.read<ChequeCubit>().clearingAgentSearchCtrl.clear();
                _currencies = List.from(_defaultCurrencies);
              });
            }, isDark)),
            const SizedBox(width: 6),
            Expanded(child: _buildSmallBtn('شحن', _counterpartyType == 'shipping_company', () {
              setState(() {
                _counterpartyType = 'shipping_company';
                _counterpartyId = null; _counterpartyName = null;
                context.read<ChequeCubit>().shippingCompanySearchCtrl.clear();
                _currencies = List.from(_defaultCurrencies);
              });
            }, isDark)),
            const SizedBox(width: 6),
            Expanded(child: _buildSmallBtn('خزينة', _counterpartyType == 'treasury', () {
              setState(() {
                _counterpartyType = 'treasury';
                _counterpartyId = null;
                _counterpartyName = _treasuries.isNotEmpty
                    ? _treasuries.firstWhere((t) => t['id'] == _selectedTreasuryId, orElse: () => _treasuries.first)['name']?.toString()
                    : 'الخزينة الرئيسية';
                _selectedExpenseAccountId = null;
                _currencies = List.from(_defaultCurrencies);
              });
            }, isDark)),
          ],
        ),
      ],
    );
  }

  Widget _buildTreasurySelector(Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? color.withValues(alpha: 0.1) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? color.withValues(alpha: 0.3) : const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          if (_treasuries.isEmpty)
            Text('جارٍ تحميل الخزائن...',
                style: TextStyle(color: color.withValues(alpha: 0.6), fontSize: 11, fontFamily: 'Cairo'))
          else
            DropdownButtonFormField<int>(
              initialValue: _selectedTreasuryId,
              items: _treasuries.map((t) => DropdownMenuItem<int>(
                value: t['id'] as int,
                child: Row(
                  children: [
                    Icon(
                      t['type'] == 'main' ? Icons.account_balance : Icons.person_outline,
                      size: 14,
                      color: color,
                    ),
                    const SizedBox(width: 6),
                    Text(t['name']?.toString() ?? '', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: isDark ? Colors.white : Colors.black)),
                  ],
                ),
              )).toList(),
              onChanged: null, // Locked to Main Treasury
              decoration: InputDecoration(
                filled: true,
                fillColor: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: isDark ? color.withValues(alpha: 0.3) : const Color(0xFFCBD5E1)),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              dropdownColor: isDark ? const Color(0xFF0A1630) : Colors.white,
              style: TextStyle(fontFamily: 'Cairo', color: isDark ? Colors.white : Colors.black, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool isOutgoing, bool isMobile, double spacing, bool isDark) {
    final canSave = !ReadOnlyGuard.isReadOnly && !_isSaving && _isCounterpartyValid;
    final primaryColor = isOutgoing ? AppTheme.danger : AppTheme.success;

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: isDark ? AppTheme.textMuted : const Color(0xFFCBD5E1)),
              foregroundColor: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          SizedBox(height: spacing),
          ElevatedButton.icon(
            onPressed: canSave ? () => _save(context) : null,
            icon: _isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: Text(_isSaving ? 'جارٍ الحفظ...' : 'حفظ', style: const TextStyle(fontFamily: 'Cairo')),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              disabledBackgroundColor: primaryColor.withValues(alpha: 0.25),
              disabledForegroundColor: Colors.white38,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      );
    }

    return Row(children: [
      Expanded(
        child: OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: isDark ? AppTheme.textMuted : const Color(0xFFCBD5E1)),
            foregroundColor: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        flex: 2,
        child: ElevatedButton.icon(
          onPressed: canSave ? () => _save(context) : null,
          icon: _isSaving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.save_outlined),
          label: Text(_isSaving ? 'جارٍ الحفظ...' : 'حفظ', style: const TextStyle(fontFamily: 'Cairo')),
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            disabledBackgroundColor: primaryColor.withValues(alpha: 0.25),
            disabledForegroundColor: Colors.white38,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    ]);
  }

  Widget _buildLabel(String text, IconData icon, Color color, double fontSize) {
    return Row(children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 6),
      Text(text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: color, fontFamily: 'Cairo')),
    ]);
  }

  Widget _buildSmallBtn(String label, bool active, VoidCallback onTap, bool isDark) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          color: active
              ? (isDark ? AppTheme.primary.withValues(alpha: 0.15) : const Color(0xFFE0F2FE))
              : (isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
            width: active ? 1.5 : 1.0,
          ),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: active
                    ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                    : (isDark ? AppTheme.textSecondary : const Color(0xFF475569)),
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo')),
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    if (!await ReadOnlyGuard.checkAsync(context)) return;
    // Validation: counterpartyType is required
    if (_counterpartyType == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('يجب اختيار نوع الطرف الآخر', style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }
    // Validation: treasury must be selected
    if (_counterpartyType == 'treasury' && _selectedTreasuryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('يجب اختيار الخزينة', style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }
    setState(() => _isSaving = true);
    try {
      final exchangeRateVal = double.tryParse(_exchangeRateCtrl.text.trim());
      await context.read<ChequeCubit>().saveCheque(
            type: widget.type,
            currency: _currency,
            issueDate: AppUtils.formatDateForDb(_issueDate),
            dueDate: AppUtils.formatDateForDb(_dueDate),
            counterpartyType: _counterpartyType,
            counterpartyId: int.tryParse(_counterpartyId ?? ''),
            supplierId: _supplierId,
            shareholderId: _counterpartyType == 'shareholder' ? _counterpartyId : null,
            clearingAgentId: _counterpartyType == 'clearing_agent' ? int.tryParse(_counterpartyId ?? '') : null,
            shippingCompanyId: _counterpartyType == 'shipping_company' ? int.tryParse(_counterpartyId ?? '') : null,
            categoryId: _selectedCategoryId,
            expenseAccountId: _selectedExpenseAccountId,
            treasuryId: _counterpartyType == 'treasury' ? _selectedTreasuryId : null,
            exchangeRate: exchangeRateVal,
          );
      if (context.mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$e', style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.danger,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _DatePickerField extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  const _DatePickerField({required this.date, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: isDark
                  ? const ColorScheme.dark(primary: AppTheme.primary)
                  : const ColorScheme.light(primary: AppTheme.primary),
            ),
            child: child!,
          ),
        );
        if (picked != null) onChanged(picked);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
        ),
        child: Row(children: [
          Icon(Icons.calendar_today, size: 14, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(AppUtils.formatDate(date),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                )),
          ),
        ]),
      ),
    );
  }
}

class _CustomerSearchWidget extends StatefulWidget {
  final ChequeCubit cubit;
  final ValueChanged<CustomerModel> onSelected;
  final VoidCallback? onSearchChanged;
  const _CustomerSearchWidget({required this.cubit, required this.onSelected, this.onSearchChanged});

  @override
  State<_CustomerSearchWidget> createState() => _CustomerSearchWidgetState();
}

class _CustomerSearchWidgetState extends State<_CustomerSearchWidget> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        TextFormField(
          controller: widget.cubit.customerSearchCtrl,
          onChanged: (v) {
            widget.onSearchChanged?.call();
            widget.cubit.searchCustomers(v);
          },
          decoration: const InputDecoration(
            hintText: 'ابحث عن عميل تصدير...',
            prefixIcon: Icon(Icons.search, size: 18),
          ),
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        BlocBuilder<ChequeCubit, ChequeState>(
          buildWhen: (p, c) =>
              (p is ChequeLoaded && c is ChequeLoaded) &&
              (p.customerResults != c.customerResults || p.isLoadingCustomers != c.isLoadingCustomers),
          builder: (context, state) {
            if (state is! ChequeLoaded) return const SizedBox();
            if (state.customerResults.isEmpty) return const SizedBox();
            return Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0A1630) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: state.isLoadingCustomers
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: state.customerResults.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: isDark ? AppTheme.divider : const Color(0xFFE2E8F0)),
                      itemBuilder: (_, i) {
                        final c = state.customerResults[i];
                        return ListTile(
                          dense: true,
                          onTap: () => widget.onSelected(c),
                          title: Text(c.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                          subtitle: Text('رصيد: ${AppUtils.formatCurrency(c.balance)}',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B))),
                        );
                      },
                    ),
            );
          },
        ),
      ],
    );
  }
}

class _SupplierSearchWidget extends StatefulWidget {
  final ChequeCubit cubit;
  final ValueChanged<SupplierModel> onSelected;
  final VoidCallback? onSearchChanged;
  final SupplierModel? selectedSupplier;
  final VoidCallback? onClearSelected;
  final ValueChanged<String>? onCurrencyTapped;
  final String currentCurrency;

  const _SupplierSearchWidget({
    required this.cubit,
    required this.onSelected,
    this.onSearchChanged,
    this.selectedSupplier,
    this.onClearSelected,
    this.onCurrencyTapped,
    this.currentCurrency = 'EGP',
  });

  @override
  State<_SupplierSearchWidget> createState() => _SupplierSearchWidgetState();
}

class _SupplierSearchWidgetState extends State<_SupplierSearchWidget> {
  String _selectedCategory = 'all';

  static const List<Map<String, dynamic>> _supplierTypeOptions = [
    {
      'key': 'all',
      'label': 'جميع الأنواع',
      'icon': Icons.all_inclusive_rounded,
      'color': AppTheme.primary,
    },
    {
      'key': 'crop',
      'label': 'موردين محاصيل',
      'icon': Icons.agriculture_rounded,
      'color': Color(0xFF10B981),
    },
    {
      'key': 'transport',
      'label': 'موردين نقل',
      'icon': Icons.local_shipping_rounded,
      'color': Color(0xFF0284C7),
    },
    {
      'key': 'station',
      'label': 'موردين محطات',
      'icon': Icons.factory_rounded,
      'color': Color(0xFFF59E0B),
    },
    {
      'key': 'deduction',
      'label': 'موردين تخصيمات',
      'icon': Icons.assignment_outlined,
      'color': Color(0xFF8B5CF6),
    },
    {
      'key': 'packaging',
      'label': 'موردين تعبئة',
      'icon': Icons.inventory_2_outlined,
      'color': Color(0xFF06B6D4),
    },
    {
      'key': 'shared',
      'label': 'موردين مشتركين',
      'icon': Icons.sync_alt_rounded,
      'color': Color(0xFFEC4899),
    },
  ];

  @override
  void initState() {
    super.initState();
    if (widget.selectedSupplier == null) {
      widget.cubit.searchSuppliers(
        widget.cubit.supplierSearchCtrl.text,
        supplierType: _selectedCategory,
      );
    }
  }

  Color _getSupplierTypeColor(String? type, [String? code]) {
    final t = (type ?? '').toLowerCase();
    final c = (code ?? '').trim();
    if (t == 'crop') return const Color(0xFF10B981);
    if (t == 'transport' || c.startsWith('6')) return const Color(0xFF0284C7);
    if (t == 'station' || c.startsWith('85') || c.startsWith('86') || c.startsWith('87') || c.startsWith('88') || c.startsWith('89')) {
      return const Color(0xFFF59E0B);
    }
    if (t == 'deduction' || t == 'deductions' || c.startsWith('4')) return const Color(0xFF8B5CF6);
    if (t == 'packaging' || c.startsWith('70') || c.startsWith('71') || c.startsWith('72') || c.startsWith('73') || c.startsWith('74')) {
      return const Color(0xFF06B6D4);
    }
    if (t == 'shared' || c.startsWith('75') || c.startsWith('76') || c.startsWith('77') || c.startsWith('78') || c.startsWith('79')) {
      return const Color(0xFFEC4899);
    }
    return AppTheme.primary;
  }

  IconData _getSupplierTypeIcon(String? type, [String? code]) {
    final t = (type ?? '').toLowerCase();
    final c = (code ?? '').trim();
    if (t == 'crop') return Icons.agriculture_rounded;
    if (t == 'transport' || c.startsWith('6')) return Icons.local_shipping_rounded;
    if (t == 'station' || c.startsWith('85') || c.startsWith('86') || c.startsWith('87') || c.startsWith('88') || c.startsWith('89')) {
      return Icons.factory_rounded;
    }
    if (t == 'deduction' || t == 'deductions' || c.startsWith('4')) return Icons.assignment_outlined;
    if (t == 'packaging' || c.startsWith('70') || c.startsWith('71') || c.startsWith('72') || c.startsWith('73') || c.startsWith('74')) {
      return Icons.inventory_2_outlined;
    }
    if (t == 'shared' || c.startsWith('75') || c.startsWith('76') || c.startsWith('77') || c.startsWith('78') || c.startsWith('79')) {
      return Icons.sync_alt_rounded;
    }
    return Icons.business_outlined;
  }

  String _getSupplierTypeLabel(String? type, [String? code]) {
    final t = (type ?? '').toLowerCase();
    final c = (code ?? '').trim();
    if (t == 'crop') return 'مورد محصول';
    if (t == 'transport' || c.startsWith('6')) return 'مورد نقل';
    if (t == 'station' || c.startsWith('85') || c.startsWith('86') || c.startsWith('87') || c.startsWith('88') || c.startsWith('89')) {
      return 'مورد محطة';
    }
    if (t == 'deduction' || t == 'deductions' || c.startsWith('4')) return 'مورد تخصيم';
    if (t == 'packaging' || c.startsWith('70') || c.startsWith('71') || c.startsWith('72') || c.startsWith('73') || c.startsWith('74')) {
      return 'مورد تعبئة';
    }
    if (t == 'shared' || c.startsWith('75') || c.startsWith('76') || c.startsWith('77') || c.startsWith('78') || c.startsWith('79')) {
      return 'مورد مشترك';
    }
    return 'مورد';
  }

  String _formatSupplierBalances(SupplierModel s) {
    if (s.currentBalancesByCurrency.isNotEmpty) {
      final active = s.currentBalancesByCurrency.entries
          .where((en) => en.value.abs() > 0.001)
          .toList();
      if (active.isNotEmpty) {
        return active.map((en) {
          final sym = SupplierModel.getCurrencySymbol(en.key);
          final dir = en.value > 0.001 ? '(له)' : '(عليه)';
          return '${AppUtils.formatNumber(en.value.abs())} $sym $dir';
        }).join('  •  ');
      }
    } else if (s.initialBalancesByCurrency.isNotEmpty) {
      final active = s.initialBalancesByCurrency.entries
          .where((en) => en.value.amount.abs() > 0.001)
          .toList();
      if (active.isNotEmpty) {
        return active.map((en) {
          final sym = SupplierModel.getCurrencySymbol(en.key);
          return '${AppUtils.formatNumber(en.value.amount.abs())} $sym';
        }).join('  •  ');
      }
    }
    final sym = SupplierModel.getCurrencySymbol(s.currency.isNotEmpty && s.currency != 'MULTI' ? s.currency : 'EGP');
    final dir = s.outstandingBalance > 0.001 ? '(له)' : (s.outstandingBalance < -0.001 ? '(عليه)' : '');
    return '${AppUtils.formatCurrency(s.outstandingBalance.abs())} $sym $dir'.trim();
  }

  Widget _buildSelectedCard(SupplierModel supplier, bool isDark) {
    final isEgpOnly = supplier.isEgpOnlySupplier;
    final allCurrencies = isEgpOnly
        ? <String>['EGP']
        : (<String>{'EGP', 'USD', 'EUR', 'GBP'}..addAll(supplier.currentBalancesByCurrency.keys)).toList();

    final color = _getSupplierTypeColor(supplier.supplierType, supplier.supplierCode);
    final icon = _getSupplierTypeIcon(supplier.supplierType, supplier.supplierCode);
    final typeLabel = _getSupplierTypeLabel(supplier.supplierType, supplier.supplierCode);

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F1E3D) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            supplier.name,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            typeLabel,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (supplier.supplierCode.isNotEmpty)
                      Text(
                        'كود: ${supplier.supplierCode}',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: widget.onClearSelected,
                tooltip: 'تغيير المورد',
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1, color: isDark ? AppTheme.divider : const Color(0xFFE2E8F0)),
          ),
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined, size: 13, color: isDark ? AppTheme.accent : const Color(0xFF0F766E)),
              const SizedBox(width: 5),
              Text(
                'أرصدة المورد بالعملات (انقر لتحديد عملة الشيك):',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.accent : const Color(0xFF0F766E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: allCurrencies.map((c) {
              final bal = supplier.currentBalancesByCurrency[c] ??
                  (supplier.currency == c ? supplier.outstandingBalance : 0.0);
              final isSelectedCurrency = widget.currentCurrency == c;
              final sym = SupplierModel.getCurrencySymbol(c);

              final isCredit = bal > 0.001; // له
              final isDebit = bal < -0.001;  // عليه

              final statusText = isCredit ? '(له)' : (isDebit ? '(عليه)' : '(0)');
              final statusColor = isCredit
                  ? const Color(0xFF059669)
                  : (isDebit ? const Color(0xFFDC2626) : const Color(0xFF64748B));

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isEgpOnly ? null : () => widget.onCurrencyTapped?.call(c),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelectedCurrency
                          ? (isDark ? AppTheme.primary.withValues(alpha: 0.25) : const Color(0xFFE0F2FE))
                          : (isDark ? const Color(0xFF0A1630) : Colors.white),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelectedCurrency ? const Color(0xFF0284C7) : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                        width: isSelectedCurrency ? 1.6 : 1.0,
                      ),
                      boxShadow: isSelectedCurrency
                          ? [
                              BoxShadow(
                                color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                                blurRadius: 6,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelectedCurrency) ...[
                          const Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF0284C7)),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          '$c: ',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: isSelectedCurrency ? FontWeight.bold : FontWeight.w600,
                            color: isSelectedCurrency ? const Color(0xFF0369A1) : (isDark ? Colors.white70 : const Color(0xFF475569)),
                          ),
                        ),
                        Text(
                          '${AppUtils.formatNumber(bal.abs())} $sym',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: statusColor.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (widget.selectedSupplier != null) {
      return _buildSelectedCard(widget.selectedSupplier!, isDark);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: _supplierTypeOptions.map((opt) {
              final key = opt['key'] as String;
              final label = opt['label'] as String;
              final icon = opt['icon'] as IconData;
              final color = opt['color'] as Color;
              final isSelected = _selectedCategory == key;

              return Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedCategory = key;
                    });
                    widget.cubit.searchSuppliers(
                      widget.cubit.supplierSearchCtrl.text,
                      supplierType: key,
                    );
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withValues(alpha: 0.18)
                          : (isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9)),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? color : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 13, color: isSelected ? color : (isDark ? Colors.white70 : const Color(0xFF475569))),
                        const SizedBox(width: 5),
                        Text(
                          label,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            color: isSelected ? color : (isDark ? Colors.white : const Color(0xFF334155)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),

        // Search Field
        TextFormField(
          controller: widget.cubit.supplierSearchCtrl,
          onTap: () {
            widget.cubit.searchSuppliers(
              widget.cubit.supplierSearchCtrl.text,
              supplierType: _selectedCategory,
            );
          },
          onChanged: (v) {
            widget.onSearchChanged?.call();
            widget.cubit.searchSuppliers(v, supplierType: _selectedCategory);
          },
          decoration: InputDecoration(
            hintText: 'ابحث عن مورد بالاسم أو الكود...',
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: widget.cubit.supplierSearchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      widget.cubit.supplierSearchCtrl.clear();
                      widget.cubit.searchSuppliers('', supplierType: _selectedCategory);
                    },
                  )
                : null,
          ),
          style: const TextStyle(fontFamily: 'Cairo'),
        ),

        // Results List
        BlocBuilder<ChequeCubit, ChequeState>(
          buildWhen: (p, c) =>
              (p is ChequeLoaded && c is ChequeLoaded) &&
              (p.supplierResults != c.supplierResults || p.isLoadingSuppliers != c.isLoadingSuppliers),
          builder: (context, state) {
            if (state is! ChequeLoaded) return const SizedBox();
            if (state.supplierResults.isEmpty) return const SizedBox();
            return Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0A1630) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: state.isLoadingSuppliers
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: state.supplierResults.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: isDark ? AppTheme.divider : const Color(0xFFE2E8F0)),
                      itemBuilder: (_, i) {
                        final s = state.supplierResults[i];
                        final color = _getSupplierTypeColor(s.supplierType, s.supplierCode);
                        final icon = _getSupplierTypeIcon(s.supplierType, s.supplierCode);
                        final label = _getSupplierTypeLabel(s.supplierType, s.supplierCode);

                        return ListTile(
                          dense: true,
                          leading: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(icon, color: color, size: 18),
                          ),
                          onTap: () => widget.onSelected(s),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  s.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Row(
                            children: [
                              if (s.supplierCode.isNotEmpty) ...[
                                Text(
                                  'كود: ${s.supplierCode}',
                                  style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                                ),
                                const Text('  |  ', style: TextStyle(color: Colors.grey, fontSize: 10)),
                              ],
                              Expanded(
                                child: Text(
                                  'الأرصدة: ${_formatSupplierBalances(s)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            );
          },
        ),
      ],
    );
  }
}

class _ClearingAgentSearchWidget extends StatefulWidget {
  final ChequeCubit cubit;
  final ValueChanged<ClearingAgentModel> onSelected;
  final VoidCallback? onSearchChanged;
  const _ClearingAgentSearchWidget({required this.cubit, required this.onSelected, this.onSearchChanged});

  @override
  State<_ClearingAgentSearchWidget> createState() => _ClearingAgentSearchWidgetState();
}

class _ClearingAgentSearchWidgetState extends State<_ClearingAgentSearchWidget> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        TextFormField(
          controller: widget.cubit.clearingAgentSearchCtrl,
          onChanged: (v) {
            widget.onSearchChanged?.call();
            widget.cubit.searchClearingAgents(v);
          },
          decoration: const InputDecoration(
            hintText: 'ابحث عن مخلص...',
            prefixIcon: Icon(Icons.search, size: 18),
          ),
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        BlocBuilder<ChequeCubit, ChequeState>(
          buildWhen: (p, c) =>
              (p is ChequeLoaded && c is ChequeLoaded) &&
              (p.clearingAgentResults != c.clearingAgentResults || p.isLoadingClearingAgents != c.isLoadingClearingAgents),
          builder: (context, state) {
            if (state is! ChequeLoaded) return const SizedBox();
            if (state.clearingAgentResults.isEmpty) return const SizedBox();
            return Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0A1630) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: state.isLoadingClearingAgents
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: state.clearingAgentResults.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: isDark ? AppTheme.divider : const Color(0xFFE2E8F0)),
                      itemBuilder: (_, i) {
                        final a = state.clearingAgentResults[i];
                        return ListTile(
                          dense: true,
                          onTap: () => widget.onSelected(a),
                          title: Text(a.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                          subtitle: Text('عملة: ${a.currency}',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B))),
                        );
                      },
                    ),
            );
          },
        ),
      ],
    );
  }
}

class _ShippingCompanySearchWidget extends StatefulWidget {
  final ChequeCubit cubit;
  final ValueChanged<ShippingCompanyModel> onSelected;
  final VoidCallback? onSearchChanged;
  const _ShippingCompanySearchWidget({required this.cubit, required this.onSelected, this.onSearchChanged});

  @override
  State<_ShippingCompanySearchWidget> createState() => _ShippingCompanySearchWidgetState();
}

class _ShippingCompanySearchWidgetState extends State<_ShippingCompanySearchWidget> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        TextFormField(
          controller: widget.cubit.shippingCompanySearchCtrl,
          onChanged: (v) {
            widget.onSearchChanged?.call();
            widget.cubit.searchShippingCompanies(v);
          },
          decoration: const InputDecoration(
            hintText: 'ابحث عن شركة شحن...',
            prefixIcon: Icon(Icons.search, size: 18),
          ),
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        BlocBuilder<ChequeCubit, ChequeState>(
          buildWhen: (p, c) =>
              (p is ChequeLoaded && c is ChequeLoaded) &&
              (p.shippingCompanyResults != c.shippingCompanyResults || p.isLoadingShippingCompanies != c.isLoadingShippingCompanies),
          builder: (context, state) {
            if (state is! ChequeLoaded) return const SizedBox();
            if (state.shippingCompanyResults.isEmpty) return const SizedBox();
            return Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0A1630) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: state.isLoadingShippingCompanies
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: state.shippingCompanyResults.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: isDark ? AppTheme.divider : const Color(0xFFE2E8F0)),
                      itemBuilder: (_, i) {
                        final s = state.shippingCompanyResults[i];
                        return ListTile(
                          dense: true,
                          onTap: () => widget.onSelected(s),
                          title: Text(s.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                          subtitle: Text('عملة: ${s.currency}',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B))),
                        );
                      },
                    ),
            );
          },
        ),
      ],
    );
  }
}

class _ShareholderSearchWidget extends StatefulWidget {
  final ChequeCubit cubit;
  final ValueChanged<ShareholderModel> onSelected;
  final VoidCallback? onSearchChanged;
  const _ShareholderSearchWidget({required this.cubit, required this.onSelected, this.onSearchChanged});

  @override
  State<_ShareholderSearchWidget> createState() => _ShareholderSearchWidgetState();
}

class _ShareholderSearchWidgetState extends State<_ShareholderSearchWidget> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        TextFormField(
          controller: widget.cubit.shareholderSearchCtrl,
          onChanged: (v) {
            widget.onSearchChanged?.call();
            widget.cubit.searchShareholders(v);
          },
          decoration: const InputDecoration(
            hintText: 'ابحث عن مساهم...',
            prefixIcon: Icon(Icons.search, size: 18),
          ),
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        BlocBuilder<ChequeCubit, ChequeState>(
          buildWhen: (p, c) =>
              (p is ChequeLoaded && c is ChequeLoaded) &&
              (p.shareholderResults != c.shareholderResults || p.isLoadingShareholders != c.isLoadingShareholders),
          builder: (context, state) {
            if (state is! ChequeLoaded) return const SizedBox();
            if (state.shareholderResults.isEmpty) return const SizedBox();
            return Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0A1630) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: state.isLoadingShareholders
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: state.shareholderResults.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: isDark ? AppTheme.divider : const Color(0xFFE2E8F0)),
                      itemBuilder: (_, i) {
                        final s = state.shareholderResults[i];
                        final balEgp = s.totalDepositsEgp - s.totalWithdrawalsEgp;
                        final balUsd = s.totalDepositsUsd - s.totalWithdrawalsUsd;
                        final balEur = s.totalDepositsEur - s.totalWithdrawalsEur;
                        final balGbp = s.totalDepositsGbp - s.totalWithdrawalsGbp;
                        return ListTile(
                          dense: true,
                          onTap: () => widget.onSelected(s),
                          title: Text(s.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (balEgp != 0) Text('جنية: ${AppUtils.formatCurrency(balEgp)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppTheme.success)),
                              if (balUsd != 0) Text('دولار: ${AppUtils.formatCurrency(balUsd)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppTheme.success)),
                              if (balEur != 0) Text('يورو: ${AppUtils.formatCurrency(balEur)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppTheme.success)),
                              if (balGbp != 0) Text('استرليني: ${AppUtils.formatCurrency(balGbp)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppTheme.success)),
                              if (balEgp == 0 && balUsd == 0 && balEur == 0 && balGbp == 0)
                                Text('رصيد: 0', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B))),
                            ],
                          ),
                        );
                      },
                    ),
            );
          },
        ),
      ],
    );
  }
}

class _ExpenseAccountSelector extends StatefulWidget {
  final ValueChanged<int> onSelected;
  const _ExpenseAccountSelector({required this.onSelected});

  @override
  State<_ExpenseAccountSelector> createState() => _ExpenseAccountSelectorState();
}

class _ExpenseAccountSelectorState extends State<_ExpenseAccountSelector> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<AccountModel> _accounts = [];
  bool _isLoading = false;
  AccountModel? _selectedAccount;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    setState(() => _isLoading = true);
    try {
      final client = Supabase.instance.client;
      final data = await client
          .from('chart_of_accounts')
          .select('id, code, name, account_type')
          .order('code')
          .limit(100);
      
      if (mounted) {
        setState(() {
          _accounts = (data as List)
              .map((e) {
                final map = Map<String, dynamic>.from(e as Map);
                // Convert id to string for AccountModel compatibility
                map['id'] = map['id']?.toString();
                return AccountModel.fromMap(map);
              })
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<AccountModel> _filterAccounts(String query) {
    if (query.isEmpty) return _accounts;
    final lowerQuery = query.toLowerCase();
    return _accounts.where((a) =>
        a.name.toLowerCase().contains(lowerQuery) ||
        a.code.toLowerCase().contains(lowerQuery)
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filterAccounts(_searchCtrl.text);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.account_tree_outlined, size: 16, color: AppTheme.accent),
            const SizedBox(width: 6),
            Text('اختر الحساب المحاسبي *',
                style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF475569), fontWeight: FontWeight.w600, fontFamily: 'Cairo', fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
          ),
          child: Column(
            children: [
              TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'ابحث بالكود أو الاسم...',
                  hintStyle: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: isDark ? null : const Color(0xFF94A3B8)),
                  prefixIcon: const Icon(Icons.search, size: 16),
                  suffixIcon: _selectedAccount != null
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            setState(() {
                              _selectedAccount = null;
                              _searchCtrl.clear();
                            });
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: isDark ? Colors.white : Colors.black),
              ),
              if (filtered.isNotEmpty && _searchCtrl.text.isNotEmpty) ...[
                Divider(height: 1, color: isDark ? AppTheme.divider : const Color(0xFFE2E8F0)),
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final account = filtered[index];
                      return ListTile(
                        dense: true,
                        title: Text('${account.code} - ${account.name}',
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: isDark ? Colors.white : Colors.black)),
                        onTap: () {
                          setState(() {
                            _selectedAccount = account;
                            _searchCtrl.text = '${account.code} - ${account.name}';
                          });
                          if (account.id != null) {
                            final accountId = int.tryParse(account.id!);
                            if (accountId != null) {
                              widget.onSelected(accountId);
                            }
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_selectedAccount != null) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, size: 12, color: AppTheme.success),
                const SizedBox(width: 4),
                Text(_selectedAccount!.name,
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppTheme.success)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
