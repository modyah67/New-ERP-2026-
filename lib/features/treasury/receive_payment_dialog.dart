import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../data/dao/cheque_dao.dart';
import '../../data/dao/customer_dao.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/dao/clearing_agent_dao.dart';
import '../../data/dao/shipping_company_dao.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/clearing_agent_model.dart';
import '../../data/models/shipping_company_model.dart';
import '../../data/models/shareholder_model.dart';
import '../../data/models/treasury_model.dart';
import '../../data/dao/shareholder_dao.dart';
import '../../data/dao/treasury_dao.dart';
import '../../data/dao/exchange_rate_dao.dart';

class ReceivePaymentDialog extends StatefulWidget {
  final int? treasuryId;
  final TreasuryTransactionModel? draftTx;
  const ReceivePaymentDialog({super.key, this.treasuryId, this.draftTx});

  @override
  State<ReceivePaymentDialog> createState() => _ReceivePaymentDialogState();
}

class _ReceivePaymentDialogState extends State<ReceivePaymentDialog> {
  String _method = 'cash';
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  String _currency = 'EGP';
  String? _counterpartyType = 'opening';
  String? _counterpartyId;
  String? _supplierId;
  String? _counterpartyName;
  bool _isSaving = false;
  bool _showCustomerSearch = false;
  bool _showSupplierSearch = false;
  bool _showClearingAgentSearch = false;
  bool _showShippingCompanySearch = false;
  bool _showShareholderSearch = false;

  @override
  void initState() {
    super.initState();
    if (widget.draftTx != null) {
      final tx = widget.draftTx!;
      _amountCtrl.text = tx.amount.abs().toStringAsFixed(2);
      _currency = tx.currency;
      _descriptionCtrl.text = tx.description ?? '';
      _notesCtrl.text = tx.notes ?? '';
      _method = tx.payload?['receipt_type'] ?? 'cash';

      final cType = tx.payload?['counterparty_type'];
      if (cType != null) {
        _counterpartyType = cType;
        if (cType == 'customer') {
          _counterpartyId = tx.customerId;
          _counterpartyName = tx.customerName;
          _customerSearchCtrl.text = tx.customerName ?? '';
        } else if (cType == 'supplier') {
          _supplierId = tx.supplierId;
          _counterpartyName = tx.supplierName;
          _supplierSearchCtrl.text = tx.supplierName ?? '';
        } else if (cType == 'shareholder') {
          _counterpartyId = tx.shareholderId;
          _counterpartyName = tx.shareholderName;
          _shareholderSearchCtrl.text = tx.shareholderName ?? '';
        }
      } else if (tx.customerId != null) {
        _counterpartyType = 'customer';
        _counterpartyId = tx.customerId;
        _counterpartyName = tx.customerName;
        _customerSearchCtrl.text = tx.customerName ?? '';
      } else if (tx.supplierId != null) {
        _counterpartyType = 'supplier';
        _supplierId = tx.supplierId;
        _counterpartyName = tx.supplierName;
        _supplierSearchCtrl.text = tx.supplierName ?? '';
      } else if (tx.shareholderId != null) {
        _counterpartyType = 'shareholder';
        _counterpartyId = tx.shareholderId;
        _counterpartyName = tx.shareholderName;
        _shareholderSearchCtrl.text = tx.shareholderName ?? '';
      }
    }
  }
  List<CustomerModel> _customerResults = [];
  List<SupplierModel> _supplierResults = [];
  List<ClearingAgentModel> _clearingAgentResults = [];
  List<ShippingCompanyModel> _shippingCompanyResults = [];
  List<ShareholderModel> _shareholderResults = [];
  bool _isLoadingCustomers = false;
  bool _isLoadingSuppliers = false;
  bool _isLoadingClearingAgents = false;
  bool _isLoadingShippingCompanies = false;
  final _customerSearchCtrl = TextEditingController();
  final _supplierSearchCtrl = TextEditingController();
  final _clearingAgentSearchCtrl = TextEditingController();
  final _shippingCompanySearchCtrl = TextEditingController();
  final _shareholderSearchCtrl = TextEditingController();
  bool _currencyLocked = false;

  bool get _isCounterpartyValid {
    if (_counterpartyType == '') return false; // Nothing selected yet
    if (_counterpartyType == 'opening') return true;
    if (_counterpartyType == 'supplier') return _supplierId != null;
    return _counterpartyId != null;
  }

  static const List<String> _currencies = ['EGP', 'USD', 'EUR', 'GBP'];

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    _descriptionCtrl.dispose();
    _customerSearchCtrl.dispose();
    _supplierSearchCtrl.dispose();
    _clearingAgentSearchCtrl.dispose();
    _shippingCompanySearchCtrl.dispose();
    _shareholderSearchCtrl.dispose();
    super.dispose();
  }

  void _clearAllSearch() {
    _customerSearchCtrl.clear();
    _supplierSearchCtrl.clear();
    _clearingAgentSearchCtrl.clear();
    _shippingCompanySearchCtrl.clear();
    _shareholderSearchCtrl.clear();
    _customerResults = [];
    _supplierResults = [];
    _clearingAgentResults = [];
    _shippingCompanyResults = [];
    _shareholderResults = [];
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: const Color(0xCC05192D),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppTheme.glassBorder),
        ),
        contentPadding: const EdgeInsets.all(28),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 24),
                _buildLabel('المبلغ', Icons.attach_money, AppTheme.success),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: TextFormField(
                        controller: _amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))],
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Cairo', color: AppTheme.success),
                        decoration: InputDecoration(
                          hintText: '0.00',
                          prefixIcon: const Icon(Icons.attach_money, color: AppTheme.success),
                          suffixText: _currency,
                          suffixStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: AppTheme.success),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 100,
                      child: DropdownButtonFormField<String>(
                        value: _currency,
                        dropdownColor: const Color(0xCC05192D),
                        items: _currencies.map((cur) => DropdownMenuItem(
                          value: cur,
                          child: Text(cur, style: const TextStyle(fontFamily: 'Cairo')),
                        )).toList(),
                        onChanged: _currencyLocked ? null : (v) => setState(() => _currency = v ?? 'EGP'),
                        decoration: const InputDecoration(),
                        style: const TextStyle(fontFamily: 'Cairo', color: Colors.white),
                      ),
                    ),
                  ]),
                  if (_currency != 'EGP') ...[
                    const SizedBox(height: 8),
                    FutureBuilder<double>(
                      future: ExchangeRateDao().getRate(_currency),
                      builder: (context, snapshot) {
                        final rate = snapshot.data ?? 0.0;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, size: 16, color: AppTheme.accent),
                              const SizedBox(width: 8),
                              Text(
                                snapshot.connectionState == ConnectionState.waiting
                                    ? 'جارٍ جلب سعر الصرف...'
                                    : 'سعر الصرف الحالي المسجل:  $_currency = ${rate > 0 ? AppUtils.formatCurrency(rate, "EGP") : "غير محدد"}',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  color: AppTheme.accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 20),
                  _buildLabel('المصدر (اختياري)', Icons.people_outline, AppTheme.accent),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // _buildSmallBtn('عميل', _counterpartyType == 'customer', () {
                        //   setState(() {
                        //     _counterpartyType = 'customer';
                        //     _counterpartyId = null;
                        //     _counterpartyName = null;
                        //     _showCustomerSearch = true;
                        //     _showSupplierSearch = false;
                        //     _showClearingAgentSearch = false;
                        //     _showShippingCompanySearch = false;
                        //     _showShareholderSearch = false;
                        //     _currencyLocked = false;
                        //     _currency = 'EGP';
                        //     _clearAllSearch();
                        //   });
                        // }),
                        // const SizedBox(width: 6),
                        _buildSmallBtn('مورد', _counterpartyType == 'supplier', () {
                          setState(() {
                            _counterpartyType = 'supplier';
                            _counterpartyId = null;
                            _counterpartyName = null;
                            _supplierId = null;
                            _showSupplierSearch = true;
                            _showCustomerSearch = false;
                            _showClearingAgentSearch = false;
                            _showShippingCompanySearch = false;
                            _showShareholderSearch = false;
                            _currencyLocked = false;
                            _currency = 'EGP';
                            _clearAllSearch();
                          });
                        }),
                        // const SizedBox(width: 6),
                        // _buildSmallBtn('مخلص', _counterpartyType == 'clearing_agent', () {
                        //   setState(() {
                        //     _counterpartyType = 'clearing_agent';
                        //     _counterpartyId = null;
                        //     _counterpartyName = null;
                        //     _showClearingAgentSearch = true;
                        //     _showCustomerSearch = false;
                        //     _showSupplierSearch = false;
                        //     _showShippingCompanySearch = false;
                        //     _showShareholderSearch = false;
                        //     _currencyLocked = false;
                        //     _currency = 'EGP';
                        //     _clearAllSearch();
                        //   });
                        // }),
                        // const SizedBox(width: 6),
                        // _buildSmallBtn('شحن', _counterpartyType == 'shipping_company', () {
                        //   setState(() {
                        //     _counterpartyType = 'shipping_company';
                        //     _counterpartyId = null;
                        //     _counterpartyName = null;
                        //     _showShippingCompanySearch = true;
                        //     _showCustomerSearch = false;
                        //     _showSupplierSearch = false;
                        //     _showClearingAgentSearch = false;
                        //     _showShareholderSearch = false;
                        //     _currencyLocked = false;
                        //     _currency = 'EGP';
                        //     _clearAllSearch();
                        //   });
                        // }),
                        const SizedBox(width: 6),
                        _buildSmallBtn('مساهم', _counterpartyType == 'shareholder', () {
                          setState(() {
                            _counterpartyType = 'shareholder';
                            _counterpartyId = null;
                            _counterpartyName = null;
                            _showShareholderSearch = true;
                            _showCustomerSearch = false;
                            _showSupplierSearch = false;
                            _showClearingAgentSearch = false;
                            _showShippingCompanySearch = false;
                            _currencyLocked = false;
                            _clearAllSearch();
                          });
                        }),
                        const SizedBox(width: 6),
                        _buildSmallBtn('رصيد افتتاحي', _counterpartyType == 'opening' || _counterpartyType == null, () {
                          setState(() {
                            _counterpartyType = 'opening';
                            _counterpartyId = null;
                            _counterpartyName = null;
                            _supplierId = null;
                            _showCustomerSearch = false;
                            _showSupplierSearch = false;
                            _showClearingAgentSearch = false;
                            _showShippingCompanySearch = false;
                            _showShareholderSearch = false;
                            _currencyLocked = false;
                            _clearAllSearch();
                          });
                        }),
                      ],
                    ),
                  ),
                  if (_showCustomerSearch) ...[
                    const SizedBox(height: 8),
                    _buildCustomerSearch(),
                  ],
                  if (_showSupplierSearch) ...[
                    const SizedBox(height: 8),
                    _buildSupplierSearch(),
                  ],
                  if (_showClearingAgentSearch) ...[
                    const SizedBox(height: 8),
                    _buildClearingAgentSearch(),
                  ],
                  if (_showShippingCompanySearch) ...[
                    const SizedBox(height: 8),
                    _buildShippingCompanySearch(),
                  ],
                  if (_showShareholderSearch) ...[
                    const SizedBox(height: 8),
                    _buildShareholderSearch(),
                  ],
                  const SizedBox(height: 20),
                  _buildLabel('ملاحظة (اختياري)', Icons.notes_outlined, AppTheme.textSecondary),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(hintText: 'ملاحظات...'),
                    style: const TextStyle(fontFamily: 'Cairo'),
                  ),
                  const SizedBox(height: 28),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.textMuted),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: (_isSaving || !_isCounterpartyValid) ? null : () => _saveDraft(context),
                        icon: _isSaving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.save_outlined),
                        label: Text(_isSaving ? 'جارٍ الحفظ...' : 'حفظ الاستلام',
                            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(children: [
      Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.payments_outlined, color: AppTheme.success, size: 22),
      ),
      const SizedBox(width: 14),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('استلام نقدي',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
            Text('تسجيل المبالغ الواردة في الخزنة الرئيسية',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontFamily: 'Cairo')),
          ],
        ),
      ),
    ]);
  }

  Widget _buildLabel(String text, IconData icon, Color color) {
    return Row(children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 6),
      Text(text,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color, fontFamily: 'Cairo')),
    ]);
  }

  Widget _buildSmallBtn(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 16),
        decoration: BoxDecoration(
          color: active ? AppTheme.primary.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? AppTheme.primary : AppTheme.glassBorder),
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  color: active ? AppTheme.primary : AppTheme.textSecondary,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                  fontSize: 11)),
        ),
      ),
    );
  }

  Widget _buildCustomerSearch() {
    return Column(children: [
      TextFormField(
        controller: _customerSearchCtrl,
        onChanged: (v) => _searchCustomers(v),
        decoration: const InputDecoration(
          hintText: 'ابحث عن عميل...',
          prefixIcon: Icon(Icons.search, size: 18),
        ),
        style: const TextStyle(fontFamily: 'Cairo'),
      ),
      if (_customerResults.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 4),
          constraints: const BoxConstraints(maxHeight: 160),
          decoration: BoxDecoration(
            color: const Color(0xCC05192D),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: _customerResults.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.divider),
            itemBuilder: (_, i) {
              final c = _customerResults[i];
              return Material(
                color: Colors.transparent,
                child: ListTile(
                dense: true,
                onTap: () {
                  setState(() {
                    _counterpartyId = c.id;
                    _counterpartyName = c.name;
                    _customerSearchCtrl.text = c.name;
                    _customerResults = [];
                    _currency = c.currency;
                    _currencyLocked = true;
                  });
                },
                title: Text(c.name,
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.white)),
                subtitle: Text('رصيد: ${AppUtils.formatCurrency(c.balance)}',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppTheme.textSecondary)),
              ),
              );
            },
          ),
        ),
    ]);
  }

  Widget _buildSupplierSearch() {
    return Column(children: [
      TextFormField(
        controller: _supplierSearchCtrl,
        onChanged: (v) => _searchSuppliers(v),
        decoration: const InputDecoration(
          hintText: 'ابحث عن مورد...',
          prefixIcon: Icon(Icons.search, size: 18),
        ),
        style: const TextStyle(fontFamily: 'Cairo'),
      ),
      if (_supplierResults.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 4),
          constraints: const BoxConstraints(maxHeight: 160),
          decoration: BoxDecoration(
            color: const Color(0xCC05192D),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: _supplierResults.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.divider),
            itemBuilder: (_, i) {
              final s = _supplierResults[i];
              return Material(
                color: Colors.transparent,
                child: ListTile(
                dense: true,
                onTap: () {
                  setState(() {
                    _supplierId = s.id;
                    _counterpartyName = s.name;
                    _supplierSearchCtrl.text = s.name;
                    _supplierResults = [];
                    _currency = s.currency;
                    _currencyLocked = true;
                  });
                },
                title: Text(s.name,
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.white)),
                subtitle: Text('رصيد: ${AppUtils.formatCurrency(s.outstandingBalance)}',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppTheme.textSecondary)),
              ),
              );
            },
          ),
        ),
    ]);
  }

  Future<void> _searchCustomers(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _customerResults = []);
      return;
    }
    setState(() => _isLoadingCustomers = true);
    try {
      final results = await CustomerDao().search(q.trim(), limit: 20);
      setState(() {
        _customerResults = results;
        _isLoadingCustomers = false;
      });
    } catch (_) {
      setState(() => _isLoadingCustomers = false);
    }
  }

  Future<void> _searchSuppliers(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _supplierResults = []);
      return;
    }
    setState(() => _isLoadingSuppliers = true);
    try {
      final results = await SupplierDao().search(q.trim(), limit: 20);
      setState(() {
        _supplierResults = results;
        _isLoadingSuppliers = false;
      });
    } catch (_) {
      setState(() => _isLoadingSuppliers = false);
    }
  }

  Widget _buildClearingAgentSearch() {
    return Column(children: [
      TextFormField(
        controller: _clearingAgentSearchCtrl,
        onChanged: (v) => _searchClearingAgents(v),
        decoration: const InputDecoration(
          hintText: 'ابحث عن مخلص...',
          prefixIcon: Icon(Icons.search, size: 18),
        ),
        style: const TextStyle(fontFamily: 'Cairo'),
      ),
      if (_clearingAgentResults.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 4),
          constraints: const BoxConstraints(maxHeight: 160),
          decoration: BoxDecoration(
            color: const Color(0xCC05192D),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: _clearingAgentResults.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.divider),
            itemBuilder: (_, i) {
              final a = _clearingAgentResults[i];
              return Material(
                color: Colors.transparent,
                child: ListTile(
                dense: true,
                onTap: () {
                  setState(() {
                    _counterpartyId = a.id;
                    _counterpartyName = a.name;
                    _clearingAgentSearchCtrl.text = a.name;
                    _clearingAgentResults = [];
                    _currency = a.currency;
                    _currencyLocked = true;
                  });
                },
                title: Text(a.name,
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.white)),
                subtitle: Text('عملة: ${a.currency}',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppTheme.textSecondary)),
              ),
              );
            },
          ),
        ),
    ]);
  }

  Widget _buildShippingCompanySearch() {
    return Column(children: [
      TextFormField(
        controller: _shippingCompanySearchCtrl,
        onChanged: (v) => _searchShippingCompanies(v),
        decoration: const InputDecoration(
          hintText: 'ابحث عن شركة شحن...',
          prefixIcon: Icon(Icons.search, size: 18),
        ),
        style: const TextStyle(fontFamily: 'Cairo'),
      ),
      if (_shippingCompanyResults.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 4),
          constraints: const BoxConstraints(maxHeight: 160),
          decoration: BoxDecoration(
            color: const Color(0xCC05192D),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: _shippingCompanyResults.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.divider),
            itemBuilder: (_, i) {
              final s = _shippingCompanyResults[i];
              return Material(
                color: Colors.transparent,
                child: ListTile(
                dense: true,
                onTap: () {
                  setState(() {
                    _counterpartyId = s.id?.toString();
                    _counterpartyName = s.name;
                    _shippingCompanySearchCtrl.text = s.name;
                    _shippingCompanyResults = [];
                    _currency = s.currency;
                    _currencyLocked = true;
                  });
                },
                title: Text(s.name,
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.white)),
                subtitle: Text('عملة: ${s.currency}',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppTheme.textSecondary)),
              ),
              );
            },
          ),
        ),
    ]);
  }

  Future<void> _searchClearingAgents(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _clearingAgentResults = []);
      return;
    }
    setState(() => _isLoadingClearingAgents = true);
    try {
      final results = await ClearingAgentDao().search(q.trim(), limit: 20);
      setState(() {
        _clearingAgentResults = results;
        _isLoadingClearingAgents = false;
      });
    } catch (_) {
      setState(() => _isLoadingClearingAgents = false);
    }
  }

  Future<void> _searchShippingCompanies(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _shippingCompanyResults = []);
      return;
    }
    setState(() => _isLoadingShippingCompanies = true);
    try {
      final results = await ShippingCompanyDao().search(q.trim(), limit: 20);
      setState(() {
        _shippingCompanyResults = results;
        _isLoadingShippingCompanies = false;
      });
    } catch (_) {
      setState(() => _isLoadingShippingCompanies = false);
    }
  }

  Widget _buildShareholderSearch() {
    return Column(children: [
      TextFormField(
        controller: _shareholderSearchCtrl,
        onChanged: (v) => _searchShareholders(v),
        decoration: const InputDecoration(
          hintText: 'ابحث عن مساهم...',
          prefixIcon: Icon(Icons.search, size: 18),
        ),
        style: const TextStyle(fontFamily: 'Cairo'),
      ),
      if (_shareholderResults.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 4),
          constraints: const BoxConstraints(maxHeight: 160),
          decoration: BoxDecoration(
            color: const Color(0xCC05192D),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: _shareholderResults.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.divider),
            itemBuilder: (_, i) {
              final s = _shareholderResults[i];
              return Material(
                color: Colors.transparent,
                child: ListTile(
                dense: true,
                onTap: () {
                  setState(() {
                    _counterpartyId = s.id?.toString();
                    _counterpartyName = s.name;
                    _shareholderSearchCtrl.text = s.name;
                    _shareholderResults = [];
                    _currencyLocked = false;
                  });
                },
                title: Text(s.name,
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.white)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (s.totalDepositsEgp - s.totalWithdrawalsEgp != 0) Text('جنية: ${AppUtils.formatCurrency(s.totalDepositsEgp - s.totalWithdrawalsEgp)}', style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppTheme.success)),
                    if (s.totalDepositsUsd - s.totalWithdrawalsUsd != 0) Text('دولار: ${AppUtils.formatCurrency(s.totalDepositsUsd - s.totalWithdrawalsUsd)}', style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppTheme.success)),
                    if (s.totalDepositsEur - s.totalWithdrawalsEur != 0) Text('يورو: ${AppUtils.formatCurrency(s.totalDepositsEur - s.totalWithdrawalsEur)}', style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppTheme.success)),
                    if (s.totalDepositsGbp - s.totalWithdrawalsGbp != 0) Text('استرليني: ${AppUtils.formatCurrency(s.totalDepositsGbp - s.totalWithdrawalsGbp)}', style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppTheme.success)),
                    if (s.totalDepositsEgp - s.totalWithdrawalsEgp == 0 && s.totalDepositsUsd - s.totalWithdrawalsUsd == 0 && s.totalDepositsEur - s.totalWithdrawalsEur == 0 && s.totalDepositsGbp - s.totalWithdrawalsGbp == 0)
                      const Text('رصيد: 0', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              );
            },
          ),
        ),
    ]);
  }

  Future<void> _searchShareholders(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _shareholderResults = []);
      return;
    }
    try {
      final results = await ShareholderDao().search(q.trim(), limit: 20);
      setState(() {
        _shareholderResults = results;
      });
    } catch (e) {
      print('Error searching shareholders: $e');
    }
  }

  Future<void> _save(BuildContext context) async {
    final text = _amountCtrl.text.trim();
    if (text.contains('.') && (text.startsWith('.') || text.endsWith('.'))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('يجب كتابة أرقام قبل وبعد العلامة العشرية', style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }
    final amount = double.tryParse(text) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('المبلغ يجب أن يكون أكبر من صفر', style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }

    setState(() => _isSaving = true);
      try {
        final dao = ChequeDao();
        final userDesc = _descriptionCtrl.text.trim();
        final isOpening = _counterpartyType == 'opening' || _counterpartyType == null;
        final desc = userDesc.isNotEmpty
            ? userDesc
            : (isOpening
                ? 'رصيد افتتاحي'
                : 'استلام $_currency من ${_counterpartyName ?? (_counterpartyType ?? '')}');
        await dao.receivePayment(
          receiptType: _method,
          amount: amount,
          currency: _currency,
          counterpartyType: isOpening ? null : _counterpartyType,
          counterpartyId: isOpening ? null : int.tryParse(_counterpartyId ?? ''),
          supplierId: isOpening ? null : _supplierId,
          shareholderId: (!isOpening && _counterpartyType == 'shareholder') ? _counterpartyId : null,
          description: desc,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          treasuryId: widget.treasuryId,
        );
      if (context.mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم استلام المبلغ بنجاح', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.success,
        ));
      }
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

  Future<void> _saveDraft(BuildContext context) async {
    final text = _amountCtrl.text.trim();
    if (text.contains('.') && (text.startsWith('.') || text.endsWith('.'))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('يجب كتابة أرقام قبل وبعد العلامة العشرية', style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }
    final amount = double.tryParse(text) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('المبلغ يجب أن يكون أكبر من صفر', style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppTheme.danger,
      ));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final dao = TreasuryDao();
      final userDesc = _descriptionCtrl.text.trim();
      final isOpening = _counterpartyType == 'opening' || _counterpartyType == null;
      final desc = userDesc.isNotEmpty
          ? userDesc
          : (isOpening
              ? 'رصيد افتتاحي'
              : 'استلام $_currency من ${_counterpartyName ?? (_counterpartyType ?? '')}');

      final payload = <String, dynamic>{
        'receipt_type': _method,
        if (!isOpening && _counterpartyType != null) 'counterparty_type': _counterpartyType,
      };

      if (widget.draftTx != null && widget.draftTx!.id != null) {
        await dao.updateDraft(
          transactionId: int.parse(widget.draftTx!.id!),
          amount: amount,
          currency: _currency,
          customerId: isOpening ? null : int.tryParse(_counterpartyId ?? ''),
          supplierId: isOpening ? null : _supplierId,
          shareholderId: (!isOpening && _counterpartyType == 'shareholder') ? _counterpartyId : null,
          description: desc,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          payload: payload,
        );
      } else {
        await dao.saveDraft(
          treasuryId: widget.treasuryId ?? 1,
          type: 'deposit',
          amount: amount,
          currency: _currency,
          customerId: isOpening ? null : int.tryParse(_counterpartyId ?? ''),
          supplierId: isOpening ? null : _supplierId,
          shareholderId: (!isOpening && _counterpartyType == 'shareholder') ? _counterpartyId : null,
          description: desc,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          payload: payload,
        );
      }

      if (context.mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.draftTx != null ? 'تم حفظ تعديلات المسودة بنجاح' : 'تم حفظ الاستلام كمسودة بنجاح',
              style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.warning,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('فشل حفظ المسودة: $e', style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.danger,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
