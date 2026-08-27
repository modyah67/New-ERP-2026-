import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/dao/supplier_dao.dart';
import '../../../data/dao/shipping_company_dao.dart';
import '../../../data/dao/clearing_agent_dao.dart';
import '../../../data/dao/payment_dao.dart';
import '../../../data/dao/treasury_dao.dart';
import '../../../data/dao/bank_account_dao.dart';
import '../../../data/models/unpaid_liability_model.dart';
import '../../../core/theme.dart';
import '../../../core/utils.dart';
import '../../../data/models/treasury_model.dart';
import '../../../data/models/bank_account_model.dart';

class _PayableEntity {
  final String id;
  final String name;
  final String currency;
  final double outstandingBalance;
  final double initialBalance;
  final String initialBalanceDirection;
  final String type;

  _PayableEntity({
    required this.id,
    required this.name,
    required this.currency,
    required this.outstandingBalance,
    required this.initialBalance,
    required this.initialBalanceDirection,
    required this.type,
  });
}

class MultiInvoicePaymentDialog extends StatefulWidget {
  final String? initialSourceType; // 'treasury' or 'bank'
  final int? initialSourceId;
  final String? initialEntityType;
  final String? initialEntityId;
  final TreasuryTransactionModel? draftTx;

  const MultiInvoicePaymentDialog({
    super.key,
    this.initialSourceType,
    this.initialSourceId,
    this.initialEntityType,
    this.initialEntityId,
    this.draftTx,
  });

  @override
  State<MultiInvoicePaymentDialog> createState() => _MultiInvoicePaymentDialogState();
}

class _MultiInvoicePaymentDialogState extends State<MultiInvoicePaymentDialog> {
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _entitySearchCtrl = TextEditingController();

  String _sourceType = 'treasury';
  int? _sourceId;
  String _currency = 'EGP';
  String _entityType = 'SUPPLIER';

  List<TreasuryModel> _treasuries = [];
  List<BankAccountModel> _banks = [];

  List<TreasuryModel> get _filteredTreasuries => _treasuries.where((t) => t.balances.any((b) => b.currency == _currency)).toList();
  List<BankAccountModel> get _filteredBanks => _banks.where((b) => b.currency == _currency).toList();

  double get _currentAvailableBalance {
    if (_sourceType == 'treasury' && _sourceId != null) {
      final matches = _treasuries.where((t) => int.tryParse(t.id.toString()) == _sourceId);
      if (matches.isNotEmpty) {
        final balMatches = matches.first.balances.where((b) => b.currency == _currency);
        if (balMatches.isNotEmpty) return balMatches.first.balance;
      }
    } else if (_sourceType == 'bank' && _sourceId != null) {
      final matches = _banks.where((b) => int.tryParse(b.id.toString()) == _sourceId);
      if (matches.isNotEmpty) return matches.first.balance;
    }
    return 0.0;
  }

  List<_PayableEntity> _entityResults = [];
  _PayableEntity? _selectedEntity;
  String? _entityId;
  String? _entityName;
  Timer? _debounce;
  bool _isSearching = false;
  bool _hasSearched = false;

  bool _isLoading = true;
  bool _isLoadingInvoices = false;
  bool _isSaving = false;
  String? _errorMsg;
  
  List<UnpaidLiabilityModel> _unpaidLiabilities = [];
  double _openingBalanceRemaining = 0.0;
  double _totalOutstanding = 0.0;

  @override
  void initState() {
    super.initState();
    _sourceType = widget.initialSourceType ?? 'treasury';
    _sourceId = widget.initialSourceId;
    if (widget.initialEntityType != null) _entityType = widget.initialEntityType!;
    if (widget.initialEntityId != null) _entityId = widget.initialEntityId;

    if (widget.draftTx != null) {
      final tx = widget.draftTx!;
      _amountCtrl.text = tx.amount.abs().toStringAsFixed(2);
      _descCtrl.text = tx.description ?? '';
      _currency = tx.currency;
      _sourceType = tx.payload?['source_type'] ?? 'treasury';
      _sourceId = tx.payload?['source_id'] != null
          ? int.tryParse(tx.payload!['source_id'].toString())
          : int.tryParse(tx.treasuryId ?? '');
      _entityType = tx.payload?['entity_type'] ?? 'SUPPLIER';
      _entityId = tx.payload?['entity_id'] ??
          (tx.supplierId ?? tx.clearingAgentId ?? tx.shippingCompanyId);
    }

    _amountCtrl.addListener(_onAmountChanged);
    _loadSources();
  }

  void _onAmountChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _amountCtrl.removeListener(_onAmountChanged);
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _entitySearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSources() async {
    try {
      final treasuries = await TreasuryDao().getAll();
      final banks = await BankAccountDao().getAll();
      
      setState(() {
        _treasuries = treasuries;
        _banks = banks;
        _isLoading = false;

        if (_sourceId == null) {
          if (_sourceType == 'treasury' && _treasuries.isNotEmpty) {
            _sourceId = int.tryParse(_treasuries.first.id.toString());
          } else if (_sourceType == 'bank' && _banks.isNotEmpty) {
            _sourceId = int.tryParse(_banks.first.id.toString());
          }
        }
      });
    } catch (e) {
      setState(() {
        _errorMsg = e.toString();
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    final query = q.trim();

    if (_entityId != null && query != _entityName) {
      setState(() {
        _entityId = null;
        _entityName = null;
        _selectedEntity = null;
        _unpaidLiabilities = [];
        _openingBalanceRemaining = 0.0;
        _totalOutstanding = 0.0;
      });
    }

    if (query.isEmpty) {
      setState(() {
        _entityResults = [];
        _isSearching = false;
        _hasSearched = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _hasSearched = false;
    });

    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        List<_PayableEntity> results = [];
        if (_entityType == 'SUPPLIER') {
          final res = await SupplierDao().search(query, limit: 10);
          results = res.map((e) => _PayableEntity(
            id: e.id.toString(),
            name: e.name,
            currency: e.currency,
            outstandingBalance: e.outstandingBalance,
            initialBalance: e.initialBalance,
            initialBalanceDirection: e.initialBalanceDirection,
            type: 'SUPPLIER'
          )).toList();
        } else if (_entityType == 'SHIPPING_COMPANY') {
          final res = await ShippingCompanyDao().search(query, limit: 10);
          results = res.map((e) => _PayableEntity(
            id: e.id.toString(),
            name: e.name,
            currency: e.currency,
            outstandingBalance: e.balance,
            initialBalance: e.initialBalance,
            initialBalanceDirection: e.initialBalanceDirection,
            type: 'SHIPPING_COMPANY'
          )).toList();
        } else if (_entityType == 'CLEARING_AGENT') {
          final res = await ClearingAgentDao().search(query, limit: 10);
          results = res.map((e) => _PayableEntity(
            id: e.id.toString(),
            name: e.name,
            currency: e.currency,
            outstandingBalance: e.balance,
            initialBalance: e.initialBalance,
            initialBalanceDirection: e.initialBalanceDirection,
            type: 'CLEARING_AGENT'
          )).toList();
        }

        if (!mounted) return;
        if (_entitySearchCtrl.text.trim() == query) {
          setState(() {
            _entityResults = results;
            _isSearching = false;
            _hasSearched = true;
          });
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _entityResults = [];
          _isSearching = false;
          _hasSearched = true;
        });
      }
    });
  }

  void _clearSelectedEntity() {
    _debounce?.cancel();
    setState(() {
      _entityId = null;
      _entityName = null;
      _selectedEntity = null;
      _entitySearchCtrl.clear();
      _entityResults.clear();
      _isSearching = false;
      _hasSearched = false;
      _unpaidLiabilities.clear();
      _openingBalanceRemaining = 0.0;
      _totalOutstanding = 0.0;
    });
  }

  Future<void> _onSelectEntity(_PayableEntity e) async {
    _debounce?.cancel();
    setState(() {
      _selectedEntity = e;
      _entityId = e.id;
      _entityName = e.name;
      _entitySearchCtrl.text = e.name;
      _entityResults.clear();
      _isSearching = false;
      _hasSearched = false;
      if (e.currency.isNotEmpty) {
        _currency = e.currency;
        
        if (_sourceType == 'treasury') {
          _sourceId = _filteredTreasuries.isNotEmpty ? int.tryParse(_filteredTreasuries.first.id.toString()) : null;
        } else {
          _sourceId = _filteredBanks.isNotEmpty ? int.tryParse(_filteredBanks.first.id.toString()) : null;
        }
      }
      
      String typeLabel = 'جهة';
      if (_entityType == 'SUPPLIER') typeLabel = 'مورد';
      else if (_entityType == 'SHIPPING_COMPANY') typeLabel = 'شركة شحن';
      else if (_entityType == 'CLEARING_AGENT') typeLabel = 'مخلص جمركي';

      _descCtrl.text = 'سداد مستحقات ل$typeLabel ${e.name}';
      _isLoadingInvoices = true;
    });

    try {
      final allLiabilities = await PaymentDao().getUnpaidLiabilities(_entityType, e.id);
      final unpaid = allLiabilities.where((l) => l.dueAmount > 0.001).toList();

      final initialPayable = (e.initialBalanceDirection.toUpperCase() == 'CREDIT') ? e.initialBalance : 0.0;
      final liabilitiesDue = unpaid.fold<double>(0.0, (sum, l) => sum + l.dueAmount);
      
      double openingRemaining = 0.0;
      if (initialPayable > 0) {
        if (e.outstandingBalance > 0) {
          if (e.outstandingBalance >= liabilitiesDue) {
            openingRemaining = min(initialPayable, e.outstandingBalance - liabilitiesDue);
          } else {
            openingRemaining = min(initialPayable, e.outstandingBalance);
          }
        } else {
          openingRemaining = initialPayable;
        }
      }

      final totalOut = max(0.0, openingRemaining + liabilitiesDue);

      setState(() {
        _unpaidLiabilities = unpaid;
        _openingBalanceRemaining = openingRemaining;
        _totalOutstanding = totalOut;
        _isLoadingInvoices = false;
      });
    } catch (err) {
      setState(() => _isLoadingInvoices = false);
    }
  }

  Future<void> _submit() async {
    if (_sourceId == null || _entityId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء تحديد المصدر وجهة السداد', style: TextStyle(fontFamily: 'Cairo'))),
      );
      return;
    }

    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال مبلغ صحيح', style: TextStyle(fontFamily: 'Cairo'))),
      );
      return;
    }

    if (_sourceType == 'bank') {
      final selectedBank = _banks.firstWhere((b) => b.id.toString() == _sourceId.toString(), orElse: () => _banks.first);
      if (amount > selectedBank.balance) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('رصيد البنك غير كافٍ. المتاح: ${selectedBank.balance}', style: const TextStyle(fontFamily: 'Cairo'))),
        );
        return;
      }
    } else if (_sourceType == 'treasury') {
      final selectedTreasury = _treasuries.firstWhere((t) => t.id.toString() == _sourceId.toString(), orElse: () => _treasuries.first);
      final balances = selectedTreasury.balances.where((b) => b.currency == _currency);
      final currencyBalance = balances.isNotEmpty ? balances.first.balance : 0.0;
      if (amount > currencyBalance) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('رصيد الخزينة غير كافٍ. المتاح: $currencyBalance', style: const TextStyle(fontFamily: 'Cairo'))),
        );
        return;
      }
    }

    setState(() {
      _isSaving = true;
      _errorMsg = null;
    });

    try {
      String typeLabel = 'جهة';
      if (_entityType == 'SUPPLIER') typeLabel = 'المورد';
      else if (_entityType == 'SHIPPING_COMPANY') typeLabel = 'شركة الشحن';
      else if (_entityType == 'CLEARING_AGENT') typeLabel = 'المخلص الجمركي';

      await PaymentDao().entityMultiPayment(
        sourceType: _sourceType,
        sourceId: _sourceId!,
        amount: amount,
        currency: _currency,
        entityType: _entityType,
        entityId: _entityId!,
        description: _descCtrl.text.trim().isNotEmpty 
            ? _descCtrl.text.trim() 
            : 'سداد متعدد ل$typeLabel $_entityName',
        notes: '',
      );
      
      if (mounted) {
        Navigator.pop(context, true); 
      }
    } on PostgrestException catch (e) {
      setState(() {
        _errorMsg = e.message;
        _isSaving = false;
      });
    } catch (e) {
      setState(() {
        _errorMsg = e.toString().replaceAll('Exception: ', '');
        _isSaving = false;
      });
    }
  }

  Future<void> _submitDraft() async {
    if (_sourceId == null || _entityId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء تحديد المصدر وجهة السداد', style: TextStyle(fontFamily: 'Cairo'))),
      );
      return;
    }

    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال مبلغ صحيح', style: TextStyle(fontFamily: 'Cairo'))),
      );
      return;
    }

    final available = _currentAvailableBalance;
    if (amount > available) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('المبلغ المطلوب سداده ($amount) أكبر من الرصيد المتاح ($available $_currency)',
              style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMsg = null;
    });

    try {
      String typeLabel = 'جهة';
      if (_entityType == 'SUPPLIER') typeLabel = 'المورد';
      else if (_entityType == 'SHIPPING_COMPANY') typeLabel = 'شركة الشحن';
      else if (_entityType == 'CLEARING_AGENT') typeLabel = 'المخلص الجمركي';

      final desc = _descCtrl.text.trim().isNotEmpty 
          ? _descCtrl.text.trim() 
          : 'سداد متعدد ل$typeLabel $_entityName';

      final payload = <String, dynamic>{
        'is_multi_payment': true,
        'source_type': _sourceType,
        'source_id': _sourceId,
        'entity_type': _entityType,
        'entity_id': _entityId,
      };

      if (widget.draftTx != null && widget.draftTx!.id != null) {
        await TreasuryDao().updateDraft(
          transactionId: int.parse(widget.draftTx!.id!),
          treasuryId: _sourceType == 'treasury' ? _sourceId : null,
          amount: amount,
          currency: _currency,
          description: desc,
          supplierId: _entityType == 'SUPPLIER' ? _entityId : null,
          clearingAgentId: _entityType == 'CLEARING_AGENT' ? int.tryParse(_entityId!) : null,
          shippingCompanyId: _entityType == 'SHIPPING_COMPANY' ? int.tryParse(_entityId!) : null,
          payload: payload,
        );
      } else {
        await TreasuryDao().saveDraft(
          treasuryId: _sourceType == 'treasury' ? _sourceId! : 1,
          type: 'multi_payment',
          amount: amount,
          currency: _currency,
          description: desc,
          supplierId: _entityType == 'SUPPLIER' ? _entityId : null,
          clearingAgentId: _entityType == 'CLEARING_AGENT' ? int.tryParse(_entityId!) : null,
          shippingCompanyId: _entityType == 'SHIPPING_COMPANY' ? int.tryParse(_entityId!) : null,
          payload: payload,
        );
      }
      
      if (mounted) {
        Navigator.pop(context, true); 
      }
    } catch (e) {
      setState(() {
        _errorMsg = 'فشل حفظ المسودة: ${e.toString().replaceAll('Exception: ', '')}';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final enteredAmount = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
    final availableBalance = _currentAvailableBalance;
    final bool isAmountExceeded = enteredAmount > availableBalance;
    final bool isAmountValid = enteredAmount > 0 && !isAmountExceeded;
    final bool isFormValid = _sourceId != null && _entityId != null && isAmountValid;
    
    double remainingToAlloc = enteredAmount;
    final allocatedToOpening = min(remainingToAlloc, _openingBalanceRemaining);
    remainingToAlloc = max(0.0, remainingToAlloc - allocatedToOpening);

    final Map<String, double> invoiceAllocations = {};
    for (final inv in _unpaidLiabilities) {
      final due = inv.dueAmount;
      final alloc = min(remainingToAlloc, due);
      invoiceAllocations['${inv.liabilityType}_${inv.liabilityId}'] = alloc;
      remainingToAlloc = max(0.0, remainingToAlloc - alloc);
    }
    final advanceAmount = remainingToAlloc;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Container(
        constraints: const BoxConstraints(maxHeight: 700),
        child: _isLoading
            ? const SizedBox(
                width: 600,
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Container(
                  width: 600,
                  padding: const EdgeInsets.all(24),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(
                      children: [
                        const Icon(Icons.receipt_long_outlined, color: AppTheme.primary, size: 28),
                        const SizedBox(width: 10),
                        const Text('سداد متعدد (فواتير، شحن، تخليص)',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_errorMsg != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withOpacity(0.5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red),
                            const SizedBox(width: 12),
                            Expanded(child: Text(_errorMsg!, style: const TextStyle(color: Colors.red, fontFamily: 'Cairo'))),
                          ],
                        ),
                      ),

                    // Entity Type Dropdown
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _entityType,
                            decoration: InputDecoration(
                              labelText: 'نوع الجهة',
                              labelStyle: const TextStyle(fontFamily: 'Cairo'),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'SUPPLIER', child: Text('مورد', style: TextStyle(fontFamily: 'Cairo'))),
                              DropdownMenuItem(value: 'SHIPPING_COMPANY', child: Text('شركة شحن', style: TextStyle(fontFamily: 'Cairo'))),
                              DropdownMenuItem(value: 'CLEARING_AGENT', child: Text('مخلص جمركي', style: TextStyle(fontFamily: 'Cairo'))),
                            ],
                            onChanged: (val) {
                              if (val != null && val != _entityType) {
                                setState(() {
                                  _entityType = val;
                                  _clearSelectedEntity();
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextFormField(
                                controller: _entitySearchCtrl,
                                decoration: InputDecoration(
                                  labelText: 'بحث عن جهة السداد...',
                                  labelStyle: const TextStyle(fontFamily: 'Cairo'),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  prefixIcon: const Icon(Icons.search),
                                  suffixIcon: _entityId != null || _entitySearchCtrl.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear, size: 20),
                                          onPressed: _clearSelectedEntity,
                                        )
                                      : null,
                                ),
                                onChanged: _onSearchChanged,
                              ),
                              if (_isSearching)
                                const Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                                )
                              else if (_hasSearched && _entityResults.isEmpty && _entityId == null)
                                const Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: Text('لم يتم العثور على نتائج', style: TextStyle(color: Colors.grey, fontFamily: 'Cairo')),
                                )
                              else if (_entityResults.isNotEmpty && _entityId == null)
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  constraints: const BoxConstraints(maxHeight: 150),
                                  child: ListView.separated(
                                    shrinkWrap: true,
                                    itemCount: _entityResults.length,
                                    separatorBuilder: (_, __) => const Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      final s = _entityResults[index];
                                      return ListTile(
                                        title: Text(s.name, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                                        subtitle: Text('رصيد: ${s.outstandingBalance} ${s.currency}', style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                                        onTap: () => _onSelectEntity(s),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _amountCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                            decoration: InputDecoration(
                              labelText: 'المبلغ المدفوع',
                              labelStyle: const TextStyle(fontFamily: 'Cairo'),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              suffixText: _currency,
                              suffixStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                              filled: true,
                              fillColor: isAmountExceeded && enteredAmount > 0 
                                  ? Colors.red.withOpacity(0.06) 
                                  : AppTheme.primary.withOpacity(0.05),
                              errorText: isAmountExceeded && enteredAmount > 0 
                                  ? 'المبلغ أكبر من الرصيد المتاح ($availableBalance $_currency)' 
                                  : null,
                              errorStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
                            ),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _sourceType,
                            decoration: InputDecoration(
                              labelText: 'نوع المصدر',
                              labelStyle: const TextStyle(fontFamily: 'Cairo'),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'treasury', child: Text('خزينة', style: TextStyle(fontFamily: 'Cairo'))),
                              DropdownMenuItem(value: 'bank', child: Text('حساب بنكي', style: TextStyle(fontFamily: 'Cairo'))),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _sourceType = val;
                                  _sourceId = null; 
                                  if (_sourceType == 'treasury' && _filteredTreasuries.isNotEmpty) {
                                    _sourceId = int.tryParse(_filteredTreasuries.first.id.toString());
                                  } else if (_sourceType == 'bank' && _filteredBanks.isNotEmpty) {
                                    _sourceId = int.tryParse(_filteredBanks.first.id.toString());
                                  }
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: _sourceType == 'treasury'
                              ? DropdownButtonFormField<int>(
                                  value: _sourceId,
                                  decoration: InputDecoration(
                                    labelText: 'الخزينة',
                                    labelStyle: const TextStyle(fontFamily: 'Cairo'),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  items: _filteredTreasuries.map((t) {
                                    final bal = t.balances.firstWhere((b) => b.currency == _currency).balance;
                                    return DropdownMenuItem(
                                      value: int.tryParse(t.id.toString()),
                                      child: Text('${t.name} (متاح: $bal $_currency)', style: const TextStyle(fontFamily: 'Cairo')),
                                    );
                                  }).toList(),
                                  onChanged: (val) => setState(() => _sourceId = val),
                                )
                              : DropdownButtonFormField<int>(
                                  value: _sourceId,
                                  decoration: InputDecoration(
                                    labelText: 'الحساب البنكي',
                                    labelStyle: const TextStyle(fontFamily: 'Cairo'),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  items: _filteredBanks.map((b) {
                                    return DropdownMenuItem(
                                      value: int.tryParse(b.id.toString()),
                                      child: Text('${b.name} (متاح: ${b.balance} $_currency)', style: const TextStyle(fontFamily: 'Cairo')),
                                    );
                                  }).toList(),
                                  onChanged: (val) => setState(() => _sourceId = val),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'البيان',
                        labelStyle: const TextStyle(fontFamily: 'Cairo'),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const Text('توزيع الدفعة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                    const SizedBox(height: 8),
                    if (_entityId == null)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Text('الرجاء اختيار جهة السداد لعرض المستحقات وتوزيع الدفعة', 
                            style: TextStyle(color: Colors.grey, fontFamily: 'Cairo', fontSize: 16)),
                        ),
                      )
                    else if (_isLoadingInvoices)
                      const Center(child: Padding(padding: EdgeInsets.all(24.0), child: CircularProgressIndicator()))
                    else if (_totalOutstanding == 0)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Text('لا توجد مستحقات أو رصيد افتتاحي دائن لهذه الجهة', 
                            style: TextStyle(color: Colors.green, fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF062244),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('إجمالي المديونية (رصيد افتتاحي + مستحقات):', style: TextStyle(fontFamily: 'Cairo', color: AppTheme.textSecondary)),
                                Text('$_totalOutstanding $_currency', style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primary)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Text('التوزيع التفصيلي:', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                            const SizedBox(height: 8),

                            if (_openingBalanceRemaining > 0)
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: allocatedToOpening > 0 ? AppTheme.primary.withValues(alpha: 0.12) : const Color(0xFF082B57),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: allocatedToOpening > 0 ? AppTheme.primary.withValues(alpha: 0.6) : AppTheme.borderColor),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.account_balance_wallet, color: AppTheme.primary, size: 20),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text('سداد من الرصيد الافتتاحي (دائن)', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                                    ),
                                    Text('مطلوب: $_openingBalanceRemaining', style: const TextStyle(fontFamily: 'Cairo', color: AppTheme.textSecondary, fontSize: 12)),
                                    const SizedBox(width: 16),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text('يُخصم: $allocatedToOpening', style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: AppTheme.primary)),
                                        if (_openingBalanceRemaining - allocatedToOpening > 0)
                                          Text('يتبقى: ${_openingBalanceRemaining - allocatedToOpening}', style: const TextStyle(fontFamily: 'Cairo', color: Colors.redAccent, fontSize: 10)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                            ..._unpaidLiabilities.map((inv) {
                              final alloc = invoiceAllocations['${inv.liabilityType}_${inv.liabilityId}'] ?? 0.0;
                              final remainingAfter = max(0.0, inv.dueAmount - alloc);
                              
                              String refTitle = 'مستحق';
                              final lType = inv.liabilityType.toLowerCase();
                              if (lType.contains('purchase') || lType == 'purchase_invoice') refTitle = 'فاتورة مشتريات';
                              else if (lType.contains('lot') || lType.contains('crop') || lType == 'lot_receipt') refTitle = 'شراء محصول';
                              else if (lType.contains('packing') || lType == 'packing_cost_item') refTitle = 'تكلفة تعبئة';
                              else if (lType.contains('shipment') || lType == 'shipment_cost_item') refTitle = 'تكلفة شحن/تخليص';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: alloc > 0 ? AppTheme.primary.withValues(alpha: 0.12) : const Color(0xFF082B57),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: alloc > 0 ? AppTheme.primary.withValues(alpha: 0.6) : AppTheme.borderColor),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.receipt, color: alloc > 0 ? AppTheme.primary : AppTheme.textSecondary, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('$refTitle #${inv.referenceNumber} (${inv.liabilityDate.toLocal().toString().split(' ')[0]})', 
                                            style: TextStyle(fontFamily: 'Cairo', fontWeight: alloc > 0 ? FontWeight.bold : FontWeight.normal, color: AppTheme.textPrimary)),
                                          Text('المستحق: ${inv.dueAmount} $_currency', 
                                            style: const TextStyle(fontFamily: 'Cairo', color: AppTheme.textSecondary, fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text('يُسدد: $alloc', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: alloc > 0 ? AppTheme.primary : AppTheme.textSecondary)),
                                        if (remainingAfter > 0)
                                          Text('يتبقى: $remainingAfter', style: const TextStyle(fontFamily: 'Cairo', color: Colors.redAccent, fontSize: 10)),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }),

                            if (advanceAmount > 0)
                              Container(
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.arrow_circle_up, color: Colors.greenAccent, size: 20),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text('دفعة مقدمة / فائض (يضاف لرصيد الجهة)', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                                    ),
                                    Text('$advanceAmount $_currency', style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
        ),
        ElevatedButton.icon(
          onPressed: _isSaving || _isLoadingInvoices || !isFormValid ? null : _submitDraft,
          style: ElevatedButton.styleFrom(
            backgroundColor: isFormValid ? AppTheme.primary : Colors.grey.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          icon: _isSaving 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.save_outlined),
          label: const Text('حفظ السداد', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      ],
    );
  }
}
