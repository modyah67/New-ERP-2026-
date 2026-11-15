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
import '../../data/dao/transport_supplier_dao.dart';

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
  SupplierModel? _selectedSupplier;
  Map<String, double> _selectedSupplierBalances = {};
  bool _isLoadingSupplierBalances = false;
  String _selectedSupplierType = 'all';
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
      final rawCur = tx.currency.toUpperCase();
      _currency = _currencies.contains(rawCur) ? rawCur : 'EGP';
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
          _showSupplierSearch = true;
          if (tx.payload?['supplier_type'] != null) {
            _selectedSupplierType = tx.payload!['supplier_type'];
          }
        } else if (cType == 'shareholder') {
          _counterpartyId = tx.shareholderId;
          _counterpartyName = tx.shareholderName;
          _shareholderSearchCtrl.text = tx.shareholderName ?? '';
          _showShareholderSearch = true;
        }
      } else if (tx.customerId != null) {
        _counterpartyType = 'customer';
        _counterpartyId = tx.customerId;
        _counterpartyName = tx.customerName;
        _customerSearchCtrl.text = tx.customerName ?? '';
        _showCustomerSearch = true;
      } else if (tx.supplierId != null) {
        _counterpartyType = 'supplier';
        _supplierId = tx.supplierId;
        _counterpartyName = tx.supplierName;
        _supplierSearchCtrl.text = tx.supplierName ?? '';
        _showSupplierSearch = true;
        if (tx.payload?['supplier_type'] != null) {
          _selectedSupplierType = tx.payload!['supplier_type'];
        }
        final sId = tx.supplierId!;
        SupplierDao().getById(sId).then((s) {
          if (s != null && mounted) {
            _onSelectSupplier(s);
          }
        });
      } else if (tx.shareholderId != null) {
        _counterpartyType = 'shareholder';
        _counterpartyId = tx.shareholderId;
        _counterpartyName = tx.shareholderName;
        _shareholderSearchCtrl.text = tx.shareholderName ?? '';
        _showShareholderSearch = true;
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
    _shippingCompanySearchCtrl.clear();
    _shareholderResults = [];
    _selectedSupplier = null;
    _selectedSupplierBalances = {};
    _isLoadingSupplierBalances = false;
  }

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

  static String _getSupplierTypeLabel(String type, [String? code]) {
    final codeNum = int.tryParse((code ?? '').replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final t = type.toLowerCase().trim();
    if (t == 'station' || (codeNum >= 85000 && codeNum <= 89999)) return 'مورد محطة';
    if (t == 'deduction' || t == 'deductions' || (codeNum >= 40000 && codeNum <= 49999)) return 'مورد تخصيمات';
    if (t == 'transport' || (codeNum >= 60000 && codeNum <= 69999)) return 'مورد نقل';
    if (t == 'packaging' || t == 'sticker' || (codeNum >= 70000 && codeNum <= 74999)) return 'مواد تعبئة';
    if (t == 'crop' || (codeNum >= 50000 && codeNum <= 59999)) return 'مورد محاصيل';
    if (t == 'shared' || (codeNum >= 75000 && codeNum <= 79999)) return 'مورد مشترك';
    return 'مورد';
  }

  static Color _getSupplierTypeColor(String type, [String? code]) {
    final codeNum = int.tryParse((code ?? '').replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final t = type.toLowerCase().trim();
    if (t == 'station' || (codeNum >= 85000 && codeNum <= 89999)) return const Color(0xFFF59E0B);
    if (t == 'deduction' || t == 'deductions' || (codeNum >= 40000 && codeNum <= 49999)) return const Color(0xFF8B5CF6);
    if (t == 'transport' || (codeNum >= 60000 && codeNum <= 69999)) return const Color(0xFF0284C7);
    if (t == 'packaging' || t == 'sticker' || (codeNum >= 70000 && codeNum <= 74999)) return const Color(0xFF06B6D4);
    if (t == 'crop' || (codeNum >= 50000 && codeNum <= 59999)) return const Color(0xFF10B981);
    if (t == 'shared' || (codeNum >= 75000 && codeNum <= 79999)) return const Color(0xFFEC4899);
    return AppTheme.primary;
  }

  static IconData _getSupplierTypeIcon(String type, [String? code]) {
    final codeNum = int.tryParse((code ?? '').replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final t = type.toLowerCase().trim();
    if (t == 'station' || (codeNum >= 85000 && codeNum <= 89999)) return Icons.factory_rounded;
    if (t == 'deduction' || t == 'deductions' || (codeNum >= 40000 && codeNum <= 49999)) return Icons.assignment_outlined;
    if (t == 'transport' || (codeNum >= 60000 && codeNum <= 69999)) return Icons.local_shipping_rounded;
    if (t == 'packaging' || t == 'sticker' || (codeNum >= 70000 && codeNum <= 74999)) return Icons.inventory_2_outlined;
    if (t == 'crop' || (codeNum >= 50000 && codeNum <= 59999)) return Icons.agriculture_rounded;
    if (t == 'shared' || (codeNum >= 75000 && codeNum <= 79999)) return Icons.sync_alt_rounded;
    return Icons.people_outline;
  }

  String _getFilterTitle(String key) {
    switch (key) {
      case 'crop':
        return 'موردي المحاصيل';
      case 'transport':
        return 'موردي النقل';
      case 'station':
        return 'موردي المحطات';
      case 'deduction':
        return 'موردي التخصيمات';
      case 'packaging':
        return 'موردي التعبئة';
      case 'shared':
        return 'الموردين المشتركين';
      default:
        return 'جميع الموردين';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEgpOnly = _selectedSupplier?.isEgpOnlySupplier ?? false;
    final activeCurrencies = isEgpOnly ? const ['EGP'] : _currencies;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: isDark ? const Color(0xCC05192D) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
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
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                            color: isDark ? AppTheme.success : const Color(0xFF16A34A)),
                        decoration: InputDecoration(
                          hintText: '0.00',
                          hintStyle: TextStyle(
                              color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
                              fontWeight: FontWeight.bold),
                          prefixIcon: Icon(Icons.attach_money,
                              color: isDark ? AppTheme.success : const Color(0xFF16A34A)),
                          suffixText: _currency,
                          suffixStyle: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              color: isDark ? AppTheme.success : const Color(0xFF16A34A)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 100,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('receipt_cur_${isEgpOnly}_$_currency'),
                        value: activeCurrencies.contains(_currency) ? _currency : 'EGP',
                        dropdownColor: isDark ? const Color(0xCC05192D) : Colors.white,
                        items: activeCurrencies.map((cur) => DropdownMenuItem(
                          value: cur,
                          child: Text(cur,
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.bold)),
                        )).toList(),
                        onChanged: (_currencyLocked || isEgpOnly) ? null : (v) => setState(() => _currency = v ?? 'EGP'),
                        decoration: const InputDecoration(),
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold),
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
                            color: isDark ? AppTheme.accent.withValues(alpha: 0.08) : const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isDark ? AppTheme.accent.withValues(alpha: 0.25) : const Color(0xFFBBF7D0)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 16, color: isDark ? AppTheme.accent : const Color(0xFF15803D)),
                              const SizedBox(width: 8),
                              Text(
                                snapshot.connectionState == ConnectionState.waiting
                                    ? 'جارٍ جلب سعر الصرف...'
                                    : 'سعر الصرف الحالي المسجل:  $_currency = ${rate > 0 ? AppUtils.formatCurrency(rate, "EGP") : "غير محدد"}',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  color: isDark ? AppTheme.accent : const Color(0xFF15803D),
                                  fontWeight: FontWeight.bold,
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
                            _selectedSupplier = null;
                            _showSupplierSearch = true;
                            _showCustomerSearch = false;
                            _showClearingAgentSearch = false;
                            _showShippingCompanySearch = false;
                            _showShareholderSearch = false;
                            _currencyLocked = false;
                            _currency = 'EGP';
                            _clearAllSearch();
                          });
                          _searchSuppliers('');
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
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      hintText: 'ملاحظات...',
                      hintStyle: TextStyle(
                        fontFamily: 'Cairo',
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: isDark ? AppTheme.textMuted : const Color(0xFF94A3B8)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text('إلغاء',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                color: isDark ? Colors.white70 : Colors.black,
                                fontWeight: FontWeight.bold)),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(children: [
      Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: isDark ? 0.1 : 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.payments_outlined, color: AppTheme.success, size: 22),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('استلام نقدي',
                style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo')),
            Text('تسجيل المبالغ الواردة في الخزنة الرئيسية',
                style: TextStyle(
                    color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                    fontSize: 13,
                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                    fontFamily: 'Cairo')),
          ],
        ),
      ),
    ]);
  }

  Widget _buildLabel(String text, IconData icon, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? color : (color == AppTheme.textSecondary ? const Color(0xFF475569) : color);
    final textColor = isDark ? color : (color == AppTheme.textSecondary ? const Color(0xFF1E293B) : color);
    return Row(children: [
      Icon(icon, size: 14, color: iconColor),
      const SizedBox(width: 6),
      Text(text,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: textColor,
              fontFamily: 'Cairo')),
    ]);
  }

  Widget _buildSmallBtn(String label, bool active, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 16),
        decoration: BoxDecoration(
          color: active
              ? (isDark ? AppTheme.primary.withValues(alpha: 0.15) : const Color(0xFFE0F2FE))
              : (isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: active
                  ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                  : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  color: active
                      ? (isDark ? AppTheme.primary : const Color(0xFF0369A1))
                      : (isDark ? AppTheme.textSecondary : Colors.black),
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                  fontSize: 11)),
        ),
      ),
    );
  }

  Widget _buildCustomerSearch() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(children: [
      TextFormField(
        controller: _customerSearchCtrl,
        onChanged: (v) => _searchCustomers(v),
        decoration: const InputDecoration(
          hintText: 'ابحث عن عميل...',
          prefixIcon: Icon(Icons.search, size: 18),
        ),
        style: TextStyle(
            fontFamily: 'Cairo',
            color: isDark ? Colors.white : Colors.black,
            fontWeight: isDark ? FontWeight.normal : FontWeight.bold),
      ),
      if (_customerResults.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 4),
          constraints: const BoxConstraints(maxHeight: 160),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xCC05192D) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ],
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: _customerResults.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: isDark ? AppTheme.divider : const Color(0xFFE2E8F0)),
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
                    _currency = _currencies.contains(c.currency) ? c.currency : 'EGP';
                    _currencyLocked = _currencies.contains(c.currency);
                  });
                },
                title: Text(c.name,
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black)),
                subtitle: Text('رصيد: ${AppUtils.formatCurrency(c.balance)}',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF475569))),
              ),
              );
            },
          ),
        ),
    ]);
  }

  String _formatSupplierBalancesSummary(SupplierModel s) {
    if (s.currentBalancesByCurrency.isNotEmpty) {
      final active = s.currentBalancesByCurrency.entries
          .where((e) => e.value.abs() > 0.001)
          .toList();
      if (active.isNotEmpty) {
        return active.map((e) {
          final sym = SupplierModel.getCurrencySymbol(e.key);
          final dir = e.value > 0.001 ? '(له)' : '(عليه)';
          return '${AppUtils.formatNumber(e.value.abs())} $sym $dir';
        }).join('  •  ');
      }
    }
    final sym = SupplierModel.getCurrencySymbol(s.currency.isNotEmpty && s.currency != 'MULTI' ? s.currency : 'EGP');
    return '${AppUtils.formatCurrency(s.outstandingBalance.abs())} $sym';
  }

  Future<void> _onSelectSupplier(SupplierModel s) async {
    final isEgpOnly = s.isEgpOnlySupplier;
    setState(() {
      _selectedSupplier = s;
      _supplierId = s.id;
      _counterpartyName = s.name;
      _supplierSearchCtrl.text = s.name;
      _supplierResults = [];
      _currencyLocked = isEgpOnly;
      _isLoadingSupplierBalances = true;

      // Extract existing balances as instant preview
      final initialMap = Map<String, double>.from(s.currentBalancesByCurrency);
      if (initialMap.isEmpty && s.currency.isNotEmpty && s.currency != 'MULTI') {
        initialMap[s.currency] = s.outstandingBalance;
      }
      _selectedSupplierBalances = initialMap;

      if (isEgpOnly) {
        _currency = 'EGP';
      } else {
        // Select default receipt currency: pick the first currency that has a positive balance (or supplier currency)
        String? matchedCur;
        for (final cur in _currencies) {
          if ((initialMap[cur] ?? 0.0) > 0.001) {
            matchedCur = cur;
            break;
          }
        }
        if (matchedCur != null) {
          _currency = matchedCur;
        } else if (s.supportsMultiCurrency || s.currency == 'MULTI') {
          final firstValid = s.supportedCurrencies.firstWhere(
            (cur) => _currencies.contains(cur),
            orElse: () => 'EGP',
          );
          _currency = firstValid;
        } else if (_currencies.contains(s.currency)) {
          _currency = s.currency;
        } else {
          _currency = 'EGP';
        }
      }
    });

    if (s.id != null) {
      try {
        final liveMap = await SupplierDao().getSupplierBalancesByCurrency(s.id!);
        if (mounted && liveMap.isNotEmpty) {
          setState(() {
            _selectedSupplierBalances = liveMap;
            _isLoadingSupplierBalances = false;
          });
        } else {
          if (mounted) setState(() => _isLoadingSupplierBalances = false);
        }
      } catch (_) {
        if (mounted) setState(() => _isLoadingSupplierBalances = false);
      }
    } else {
      if (mounted) setState(() => _isLoadingSupplierBalances = false);
    }
  }

  Widget _buildMultiCurrencyPills() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEgpOnly = _selectedSupplier?.isEgpOnlySupplier ?? false;
    
    // For station/deduction suppliers, ONLY EGP is shown.
    final allCurrencies = isEgpOnly
        ? <String>['EGP']
        : (<String>{'EGP', 'USD', 'EUR', 'GBP'}..addAll(_selectedSupplierBalances.keys)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: allCurrencies.map((c) {
            final bal = _selectedSupplierBalances[c] ?? 0.0;
            final isSelectedCurrency = _currency == c;
            final sym = SupplierModel.getCurrencySymbol(c);

            final isCredit = bal > 0.001; // له
            final isDebit = bal < -0.001;  // عليه

            final statusText = isCredit ? '(له)' : (isDebit ? '(عليه)' : '(0)');
            final statusColor = isCredit
                ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                : (isDebit
                    ? (isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626))
                    : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)));

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: isEgpOnly
                    ? null
                    : () {
                        setState(() {
                          _currency = c;
                        });
                      },
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelectedCurrency
                        ? (isDark ? AppTheme.primary.withValues(alpha: 0.25) : const Color(0xFFE0F2FE))
                        : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelectedCurrency
                          ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                          : (isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                      width: isSelectedCurrency ? 1.6 : 1.0,
                    ),
                    boxShadow: isSelectedCurrency
                        ? [
                            BoxShadow(
                              color: (isDark ? AppTheme.primary : const Color(0xFF0284C7)).withValues(alpha: 0.2),
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
                        Icon(Icons.check_circle_rounded, size: 12, color: isDark ? AppTheme.primary : const Color(0xFF0284C7)),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        '$c: ',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          fontWeight: isSelectedCurrency ? FontWeight.bold : FontWeight.w600,
                          color: isSelectedCurrency
                              ? (isDark ? Colors.white : const Color(0xFF0369A1))
                              : (isDark ? AppTheme.textSecondary : const Color(0xFF475569)),
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
        if (!isEgpOnly && ((_selectedSupplier?.supportsMultiCurrency ?? false) || _selectedSupplierBalances.length > 1)) ...[
          const SizedBox(height: 6),
          Text(
            'المعادل الإجمالي بالجنيه: ≈ ${AppUtils.formatCurrency(_selectedSupplier?.outstandingBalance ?? 0.0)} ج.م',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSupplierSearch() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('نوع المورد', Icons.category_outlined, isDark ? AppTheme.accent : const Color(0xFF0F766E)),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: _supplierTypeOptions.map((opt) {
              final key = opt['key'] as String;
              final label = opt['label'] as String;
              final icon = opt['icon'] as IconData;
              final color = opt['color'] as Color;
              final isSelected = _selectedSupplierType == key;

              return Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedSupplierType = key;
                    });
                    _searchSuppliers(_supplierSearchCtrl.text);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withValues(alpha: isDark ? 0.22 : 0.15)
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
                        Icon(icon, size: 13, color: isSelected ? color : (isDark ? AppTheme.textSecondary : const Color(0xFF475569))),
                        const SizedBox(width: 5),
                        Text(
                          label,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            color: isSelected ? color : (isDark ? AppTheme.textSecondary : const Color(0xFF334155)),
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
        const SizedBox(height: 10),
        if (_selectedSupplier != null || (_supplierId != null && _counterpartyName != null)) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F2744) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? AppTheme.primary.withValues(alpha: 0.4) : const Color(0xFFCBD5E1),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
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
                        color: _getSupplierTypeColor(
                          _selectedSupplier?.supplierType ?? _selectedSupplierType,
                          _selectedSupplier?.supplierCode,
                        ).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _getSupplierTypeIcon(
                          _selectedSupplier?.supplierType ?? _selectedSupplierType,
                          _selectedSupplier?.supplierCode,
                        ),
                        color: _getSupplierTypeColor(
                          _selectedSupplier?.supplierType ?? _selectedSupplierType,
                          _selectedSupplier?.supplierCode,
                        ),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  _selectedSupplier?.name ?? _counterpartyName ?? '',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _getSupplierTypeColor(
                                    _selectedSupplier?.supplierType ?? _selectedSupplierType,
                                    _selectedSupplier?.supplierCode,
                                  ).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _getSupplierTypeLabel(
                                    _selectedSupplier?.supplierType ?? _selectedSupplierType,
                                    _selectedSupplier?.supplierCode,
                                  ),
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: _getSupplierTypeColor(
                                      _selectedSupplier?.supplierType ?? _selectedSupplierType,
                                      _selectedSupplier?.supplierCode,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_selectedSupplier?.supplierCode != null && _selectedSupplier!.supplierCode.isNotEmpty)
                            Text(
                              'كود المورد: ${_selectedSupplier!.supplierCode}',
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
                      tooltip: 'تغيير المورد',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                      onPressed: () {
                        setState(() {
                          _selectedSupplier = null;
                          _supplierId = null;
                          _counterpartyName = null;
                          _selectedSupplierBalances = {};
                          _supplierSearchCtrl.clear();
                          _currencyLocked = false;
                        });
                        _searchSuppliers('');
                      },
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1),
                ),
                Row(
                  children: [
                    Icon(Icons.account_balance_wallet_outlined, size: 13, color: isDark ? AppTheme.accent : const Color(0xFF0F766E)),
                    const SizedBox(width: 5),
                    Text(
                      'أرصدة المورد الحالية بالعملات (انقر لتحديد عملة الاستلام):',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppTheme.accent : const Color(0xFF0F766E),
                      ),
                    ),
                    const Spacer(),
                    if (_isLoadingSupplierBalances)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                _buildMultiCurrencyPills(),
              ],
            ),
          ),
        ] else ...[
          TextFormField(
            controller: _supplierSearchCtrl,
            onChanged: (v) => _searchSuppliers(v),
            decoration: InputDecoration(
              hintText: _selectedSupplierType == 'all'
                  ? 'ابحث عن مورد (بالاسم أو الكود)...'
                  : 'ابحث في ${_getFilterTitle(_selectedSupplierType)}...',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _isLoadingSuppliers
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : (_supplierSearchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _supplierSearchCtrl.clear();
                            _searchSuppliers('');
                          },
                        )
                      : null),
            ),
            style: TextStyle(
                fontFamily: 'Cairo',
                color: isDark ? Colors.white : Colors.black,
                fontWeight: isDark ? FontWeight.normal : FontWeight.bold),
          ),
          if (_supplierResults.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xCC05192D) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 4))
                      ],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _supplierResults.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: isDark ? AppTheme.divider : const Color(0xFFE2E8F0)),
                itemBuilder: (_, i) {
                  final s = _supplierResults[i];
                  final badgeColor = _getSupplierTypeColor(s.supplierType, s.supplierCode);
                  final badgeIcon = _getSupplierTypeIcon(s.supplierType, s.supplierCode);
                  final typeLabel = _getSupplierTypeLabel(s.supplierType, s.supplierCode);

                  return Material(
                    color: Colors.transparent,
                    child: ListTile(
                      dense: true,
                      leading: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(badgeIcon, color: badgeColor, size: 18),
                      ),
                      onTap: () => _onSelectSupplier(s),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              s.name,
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              typeLabel,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: badgeColor,
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
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                            ),
                            const Text('  |  ', style: TextStyle(color: Colors.grey, fontSize: 10)),
                          ],
                          Expanded(
                            child: Text(
                              'الأرصدة: ${_formatSupplierBalancesSummary(s)}',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF475569)),
                              overflow: TextOverflow.ellipsis,
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
      ],
    );
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
    final query = q.trim();
    setState(() => _isLoadingSuppliers = true);
    try {
      List<SupplierModel> results = [];

      List<String>? types;
      if (_selectedSupplierType != 'all') {
        if (_selectedSupplierType == 'deduction') {
          types = ['deduction', 'deductions'];
        } else {
          types = [_selectedSupplierType];
        }
      }

      if (query.isEmpty) {
        if (_selectedSupplierType != 'all') {
          final res = await SupplierDao().getAllSuppliers(supplierTypes: types);
          results = res;
          if (_selectedSupplierType == 'transport') {
            try {
              final trans = await TransportSupplierDao().getAll(limit: 30);
              for (final t in trans) {
                final exists = results.any((r) => r.supplierCode == t.code || r.name == t.name);
                if (!exists) {
                  results.add(SupplierModel(
                    id: t.id.toString(),
                    supplierCode: t.code,
                    name: t.name,
                    phone: t.phone,
                    supplierType: 'transport',
                    outstandingBalance: t.balance,
                    currency: 'EGP',
                  ));
                }
              }
            } catch (_) {}
          }
        } else {
          results = await SupplierDao().getAllSuppliers(supplierTypes: null);
        }
      } else {
        final res = await SupplierDao().search(query, limit: 30, supplierTypes: types);
        results = res;

        if (_selectedSupplierType == 'all' || _selectedSupplierType == 'transport') {
          try {
            final trans = await TransportSupplierDao().search(query, limit: 15);
            for (final t in trans) {
              final exists = results.any((r) => r.supplierCode == t.code || r.name == t.name);
              if (!exists) {
                results.add(SupplierModel(
                  id: t.id.toString(),
                  supplierCode: t.code,
                  name: t.name,
                  phone: t.phone,
                  supplierType: 'transport',
                  outstandingBalance: t.balance,
                  currency: 'EGP',
                ));
              }
            }
          } catch (_) {}
        }
      }

      if (_selectedSupplierType != 'all') {
        results = results.where((s) {
          final codeNum = int.tryParse(s.supplierCode.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          final type = s.supplierType.toLowerCase().trim();
          switch (_selectedSupplierType) {
            case 'crop':
              return type == 'crop' || (codeNum >= 50000 && codeNum <= 59999);
            case 'transport':
              return type == 'transport' || (codeNum >= 60000 && codeNum <= 69999);
            case 'station':
              return type == 'station' || (codeNum >= 85000 && codeNum <= 89999);
            case 'deduction':
              return type == 'deduction' || type == 'deductions' || (codeNum >= 40000 && codeNum <= 49999);
            case 'packaging':
              return type == 'packaging' || type == 'sticker' || (codeNum >= 70000 && codeNum <= 74999);
            case 'shared':
              return type == 'shared' || (codeNum >= 75000 && codeNum <= 79999);
            default:
              return true;
          }
        }).toList();
      }

      if (mounted) {
        setState(() {
          _supplierResults = results;
          _isLoadingSuppliers = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingSuppliers = false);
    }
  }

  Widget _buildClearingAgentSearch() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(children: [
      TextFormField(
        controller: _clearingAgentSearchCtrl,
        onChanged: (v) => _searchClearingAgents(v),
        decoration: const InputDecoration(
          hintText: 'ابحث عن مخلص...',
          prefixIcon: Icon(Icons.search, size: 18),
        ),
        style: TextStyle(
            fontFamily: 'Cairo',
            color: isDark ? Colors.white : Colors.black,
            fontWeight: isDark ? FontWeight.normal : FontWeight.bold),
      ),
      if (_clearingAgentResults.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 4),
          constraints: const BoxConstraints(maxHeight: 160),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xCC05192D) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ],
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: _clearingAgentResults.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: isDark ? AppTheme.divider : const Color(0xFFE2E8F0)),
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
                    _currency = _currencies.contains(a.currency) ? a.currency : 'EGP';
                    _currencyLocked = _currencies.contains(a.currency);
                  });
                },
                title: Text(a.name,
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black)),
                subtitle: Text('عملة: ${a.currency}',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF475569))),
              ),
              );
            },
          ),
        ),
    ]);
  }

  Widget _buildShippingCompanySearch() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(children: [
      TextFormField(
        controller: _shippingCompanySearchCtrl,
        onChanged: (v) => _searchShippingCompanies(v),
        decoration: const InputDecoration(
          hintText: 'ابحث عن شركة شحن...',
          prefixIcon: Icon(Icons.search, size: 18),
        ),
        style: TextStyle(
            fontFamily: 'Cairo',
            color: isDark ? Colors.white : Colors.black,
            fontWeight: isDark ? FontWeight.normal : FontWeight.bold),
      ),
      if (_shippingCompanyResults.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 4),
          constraints: const BoxConstraints(maxHeight: 160),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xCC05192D) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ],
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: _shippingCompanyResults.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: isDark ? AppTheme.divider : const Color(0xFFE2E8F0)),
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
                    _currency = _currencies.contains(s.currency) ? s.currency : 'EGP';
                    _currencyLocked = _currencies.contains(s.currency);
                  });
                },
                title: Text(s.name,
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black)),
                subtitle: Text('عملة: ${s.currency}',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF475569))),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(children: [
      TextFormField(
        controller: _shareholderSearchCtrl,
        onChanged: (v) => _searchShareholders(v),
        decoration: const InputDecoration(
          hintText: 'ابحث عن مساهم...',
          prefixIcon: Icon(Icons.search, size: 18),
        ),
        style: TextStyle(
            fontFamily: 'Cairo',
            color: isDark ? Colors.white : Colors.black,
            fontWeight: isDark ? FontWeight.normal : FontWeight.bold),
      ),
      if (_shareholderResults.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 4),
          constraints: const BoxConstraints(maxHeight: 160),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xCC05192D) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ],
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: _shareholderResults.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: isDark ? AppTheme.divider : const Color(0xFFE2E8F0)),
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
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (s.totalDepositsEgp - s.totalWithdrawalsEgp != 0) Text('جنية: ${AppUtils.formatCurrency(s.totalDepositsEgp - s.totalWithdrawalsEgp)}', style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.success)),
                    if (s.totalDepositsUsd - s.totalWithdrawalsUsd != 0) Text('دولار: ${AppUtils.formatCurrency(s.totalDepositsUsd - s.totalWithdrawalsUsd)}', style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.success)),
                    if (s.totalDepositsEur - s.totalWithdrawalsEur != 0) Text('يورو: ${AppUtils.formatCurrency(s.totalDepositsEur - s.totalWithdrawalsEur)}', style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.success)),
                    if (s.totalDepositsGbp - s.totalWithdrawalsGbp != 0) Text('استرليني: ${AppUtils.formatCurrency(s.totalDepositsGbp - s.totalWithdrawalsGbp)}', style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.success)),
                    if (s.totalDepositsEgp - s.totalWithdrawalsEgp == 0 && s.totalDepositsUsd - s.totalWithdrawalsUsd == 0 && s.totalDepositsEur - s.totalWithdrawalsEur == 0 && s.totalDepositsGbp - s.totalWithdrawalsGbp == 0)
                      Text('رصيد: 0', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B))),
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
        final isCustomer = _counterpartyType == 'customer';
        final isSupplier = _counterpartyType == 'supplier';
        final typeLabel = isSupplier
            ? _getSupplierTypeLabel(_selectedSupplier?.supplierType ?? _selectedSupplierType, _selectedSupplier?.supplierCode)
            : '';
        final desc = userDesc.isNotEmpty
            ? (isCustomer && _counterpartyName != null && _counterpartyName!.isNotEmpty && !userDesc.contains(_counterpartyName!)
                ? '$userDesc - العميل: $_counterpartyName (سداد حساب العميل)'
                : isSupplier && _counterpartyName != null && _counterpartyName!.isNotEmpty && !userDesc.contains(_counterpartyName!)
                    ? '$userDesc - $typeLabel: $_counterpartyName (دفعة مقدمة / إيداع)'
                    : userDesc)
            : (isOpening
                ? 'رصيد افتتاحي'
                : isCustomer
                    ? 'استلام نقدية من العميل ${_counterpartyName ?? ''} (سداد حساب العميل)'
                    : isSupplier
                        ? 'إيداع نقدي / دفعة مقدمة من $typeLabel ${_counterpartyName ?? ''}'
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
        if (_counterpartyType == 'supplier') ...{
          'supplier_type': _selectedSupplier?.supplierType ?? _selectedSupplierType,
          if (_selectedSupplier?.supplierCode != null) 'supplier_code': _selectedSupplier!.supplierCode,
        },
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
