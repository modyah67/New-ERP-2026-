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
import '../../../data/dao/transport_supplier_dao.dart';
import '../../../data/models/supplier_model.dart';
import '../../../data/models/transport_supplier_model.dart';
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
  final String type; // 'SUPPLIER', 'TRANSPORT_SUPPLIER', 'SHIPPING_COMPANY', 'CLEARING_AGENT'
  final String supplierType;
  final String code;
  final bool isMultiCurrency;
  final List<String> supportedCurrencies;
  final Map<String, double> currentBalancesByCurrency;
  final Map<String, double> initialBalancesByCurrency;

  _PayableEntity({
    required this.id,
    required this.name,
    required this.currency,
    required this.outstandingBalance,
    required this.initialBalance,
    required this.initialBalanceDirection,
    required this.type,
    this.supplierType = '',
    this.code = '',
    this.isMultiCurrency = false,
    this.supportedCurrencies = const [],
    this.currentBalancesByCurrency = const {},
    this.initialBalancesByCurrency = const {},
  });

  int get codeNumber => int.tryParse(code.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  bool get isStationSupplier =>
      supplierType.toLowerCase() == 'station' || (codeNumber >= 85000 && codeNumber <= 89999);
  bool get isDeductionSupplier =>
      supplierType.toLowerCase() == 'deduction' ||
      supplierType.toLowerCase() == 'deductions' ||
      (codeNumber >= 40000 && codeNumber <= 49999);
  bool get isEgpOnlySupplier => isStationSupplier || isDeductionSupplier;
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
  List<_PayableEntity> _defaultEntities = [];
  _PayableEntity? _selectedEntity;
  String? _entityId;
  String? _entityName;
  String _selectedSupplierType = 'all';
  Timer? _debounce;
  bool _isSearching = false;
  bool _hasSearched = false;

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

  String _formatEntityBalancesSummary(_PayableEntity e) {
    if (e.currentBalancesByCurrency.isNotEmpty) {
      final active = e.currentBalancesByCurrency.entries
          .where((en) => en.value.abs() > 0.001)
          .toList();
      if (active.isNotEmpty) {
        return active.map((en) {
          final sym = SupplierModel.getCurrencySymbol(en.key);
          final dir = en.value > 0.001 ? '(له)' : '(عليه)';
          return '${AppUtils.formatNumber(en.value.abs())} $sym $dir';
        }).join('  •  ');
      }
    } else if (e.initialBalancesByCurrency.isNotEmpty) {
      final active = e.initialBalancesByCurrency.entries
          .where((en) => en.value.abs() > 0.001)
          .toList();
      if (active.isNotEmpty) {
        return active.map((en) {
          final sym = SupplierModel.getCurrencySymbol(en.key);
          return '${AppUtils.formatNumber(en.value.abs())} $sym';
        }).join('  •  ');
      }
    }
    final sym = SupplierModel.getCurrencySymbol(e.currency.isNotEmpty && e.currency != 'MULTI' ? e.currency : 'EGP');
    final dir = e.outstandingBalance > 0.001 ? '(له)' : (e.outstandingBalance < -0.001 ? '(عليه)' : '');
    return '${AppUtils.formatCurrency(e.outstandingBalance.abs())} $sym $dir'.trim();
  }

  Widget _buildEntityMultiCurrencyPills(_PayableEntity entity) {
    final isEgpOnly = entity.isEgpOnlySupplier;
    final allCurrencies = isEgpOnly
        ? <String>['EGP']
        : (<String>{'EGP', 'USD', 'EUR', 'GBP'}..addAll(entity.currentBalancesByCurrency.keys)).toList();

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: allCurrencies.map((c) {
        final bal = entity.currentBalancesByCurrency[c] ??
            (entity.currency == c ? entity.outstandingBalance : 0.0);
        final isSelectedCurrency = _currency == c;
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
            onTap: isEgpOnly ? null : () {
              if (c != _currency) {
                _switchCurrency(c);
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isSelectedCurrency ? const Color(0xFFE0F2FE) : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelectedCurrency ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
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
                      color: isSelectedCurrency ? const Color(0xFF0369A1) : const Color(0xFF475569),
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
    );
  }

  bool _isLoading = true;
  bool _isLoadingInvoices = false;
  bool _isSaving = false;
  String? _errorMsg;
  
  List<UnpaidLiabilityModel> _unpaidLiabilities = [];
  List<UnpaidLiabilityModel> _allFetchedLiabilities = [];
  List<String> _availableCurrencies = [];
  Map<String, double> _openingPaidByCurrency = {};
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
      if (tx.payload?['supplier_type'] != null) {
        _selectedSupplierType = tx.payload!['supplier_type'];
      }
    }

    _amountCtrl.addListener(_onAmountChanged);
    _loadSources();
    _loadDefaultEntities();
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

  Future<void> _loadDefaultEntities() async {
    try {
      List<_PayableEntity> results = [];
      if (_entityType == 'SUPPLIER') {
        List<SupplierModel> sups = [];
        List<TransportSupplierModel> trans = [];

        if (_selectedSupplierType == 'all') {
          final resFutures = await Future.wait([
            SupplierDao().getAll(limit: 50),
            TransportSupplierDao().getAll(limit: 20),
          ]);
          sups = resFutures[0] as List<SupplierModel>;
          trans = resFutures[1] as List<TransportSupplierModel>;
        } else if (_selectedSupplierType == 'transport') {
          final resFutures = await Future.wait([
            SupplierDao().getAllSuppliers(supplierTypes: ['transport']),
            TransportSupplierDao().getAll(limit: 50),
          ]);
          sups = resFutures[0] as List<SupplierModel>;
          trans = resFutures[1] as List<TransportSupplierModel>;
        } else {
          sups = await SupplierDao().getAllSuppliers(supplierTypes: [_selectedSupplierType]);
        }

        results.addAll(sups.map((e) => _PayableEntity(
          id: e.id.toString(),
          name: e.name,
          currency: e.currency,
          outstandingBalance: e.outstandingBalance,
          initialBalance: e.initialBalance,
          initialBalanceDirection: e.initialBalanceDirection,
          type: 'SUPPLIER',
          supplierType: e.supplierType,
          code: e.supplierCode,
          isMultiCurrency: e.isMultiCurrency,
          supportedCurrencies: e.supportedCurrencies,
          currentBalancesByCurrency: e.currentBalancesByCurrency,
          initialBalancesByCurrency: e.initialBalancesByCurrency.map((k, v) => MapEntry(k, v.amount)),
        )));

        results.addAll(trans.map((e) => _PayableEntity(
          id: e.id.toString(),
          name: e.name,
          currency: 'EGP',
          outstandingBalance: e.balance,
          initialBalance: e.initialBalance,
          initialBalanceDirection: e.initialBalanceDirection,
          type: 'TRANSPORT_SUPPLIER',
          supplierType: 'transport',
          code: e.code,
        )));
      } else if (_entityType == 'SHIPPING_COMPANY') {
        final res = await ShippingCompanyDao().getAll(limit: 20);
        results = res.map((e) => _PayableEntity(
          id: e.id.toString(),
          name: e.name,
          currency: e.currency,
          outstandingBalance: e.balance,
          initialBalance: e.initialBalance,
          initialBalanceDirection: e.initialBalanceDirection,
          type: 'SHIPPING_COMPANY',
          code: e.code,
        )).toList();
      } else if (_entityType == 'CLEARING_AGENT') {
        final res = await ClearingAgentDao().getAll(limit: 20);
        results = res.map((e) => _PayableEntity(
          id: e.id.toString(),
          name: e.name,
          currency: e.currency,
          outstandingBalance: e.balance,
          initialBalance: e.initialBalance,
          initialBalanceDirection: e.initialBalanceDirection,
          type: 'CLEARING_AGENT',
          code: e.code,
        )).toList();
      }

      if (mounted) {
        setState(() {
          _defaultEntities = results;
          if (_entitySearchCtrl.text.isEmpty && _entityId == null) {
            _entityResults = List.from(results);
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading default entities: $e');
    }
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
        _allFetchedLiabilities = [];
        _availableCurrencies = [];
        _openingBalanceRemaining = 0.0;
        _totalOutstanding = 0.0;
      });
    }

    if (query.isEmpty) {
      setState(() {
        _entityResults = List.from(_defaultEntities);
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
          List<SupplierModel> sups = [];
          List<TransportSupplierModel> trans = [];

          if (_selectedSupplierType == 'all') {
            final resFutures = await Future.wait([
              SupplierDao().search(query, limit: 30),
              TransportSupplierDao().search(query, limit: 20),
            ]);
            sups = resFutures[0] as List<SupplierModel>;
            trans = resFutures[1] as List<TransportSupplierModel>;
          } else if (_selectedSupplierType == 'transport') {
            final resFutures = await Future.wait([
              SupplierDao().search(query, limit: 30, supplierTypes: ['transport']),
              TransportSupplierDao().search(query, limit: 30),
            ]);
            sups = resFutures[0] as List<SupplierModel>;
            trans = resFutures[1] as List<TransportSupplierModel>;
          } else {
            sups = await SupplierDao().search(query, limit: 50, supplierTypes: [_selectedSupplierType]);
          }

          results.addAll(sups.map((e) => _PayableEntity(
            id: e.id.toString(),
            name: e.name,
            currency: e.currency,
            outstandingBalance: e.outstandingBalance,
            initialBalance: e.initialBalance,
            initialBalanceDirection: e.initialBalanceDirection,
            type: 'SUPPLIER',
            supplierType: e.supplierType,
            code: e.supplierCode,
            isMultiCurrency: e.isMultiCurrency,
            supportedCurrencies: e.supportedCurrencies,
            currentBalancesByCurrency: e.currentBalancesByCurrency,
            initialBalancesByCurrency: e.initialBalancesByCurrency.map((k, v) => MapEntry(k, v.amount)),
          )));

          results.addAll(trans.map((e) => _PayableEntity(
            id: e.id.toString(),
            name: e.name,
            currency: 'EGP',
            outstandingBalance: e.balance,
            initialBalance: e.initialBalance,
            initialBalanceDirection: e.initialBalanceDirection,
            type: 'TRANSPORT_SUPPLIER',
            supplierType: 'transport',
            code: e.code,
          )));
        } else if (_entityType == 'SHIPPING_COMPANY') {
          final res = await ShippingCompanyDao().search(query, limit: 10);
          results = res.map((e) => _PayableEntity(
            id: e.id.toString(),
            name: e.name,
            currency: e.currency,
            outstandingBalance: e.balance,
            initialBalance: e.initialBalance,
            initialBalanceDirection: e.initialBalanceDirection,
            type: 'SHIPPING_COMPANY',
            code: e.code,
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
            type: 'CLEARING_AGENT',
            code: e.code,
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
      _entityResults = List.from(_defaultEntities);
      _isSearching = false;
      _hasSearched = false;
      _unpaidLiabilities.clear();
      _allFetchedLiabilities.clear();
      _availableCurrencies.clear();
      _openingPaidByCurrency.clear();
      _openingBalanceRemaining = 0.0;
      _totalOutstanding = 0.0;
    });
  }

  Future<void> _onSelectEntity(_PayableEntity e) async {
    _debounce?.cancel();
    _PayableEntity entity = e;
    if (_entityType == 'SUPPLIER' && e.type == 'SUPPLIER') {
      try {
        final fresh = await SupplierDao().getById(e.id);
        final liveBalances = await SupplierDao().getSupplierBalancesByCurrency(e.id);
        if (fresh != null) {
          entity = _PayableEntity(
            id: fresh.id.toString(),
            name: fresh.name,
            currency: fresh.currency,
            outstandingBalance: fresh.outstandingBalance,
            initialBalance: fresh.initialBalance,
            initialBalanceDirection: fresh.initialBalanceDirection,
            type: 'SUPPLIER',
            supplierType: fresh.supplierType,
            code: fresh.supplierCode,
            isMultiCurrency: fresh.isMultiCurrency,
            supportedCurrencies: fresh.supportedCurrencies,
            currentBalancesByCurrency: liveBalances.isNotEmpty ? liveBalances : fresh.currentBalancesByCurrency,
            initialBalancesByCurrency: fresh.initialBalancesByCurrency.map((k, v) => MapEntry(k, v.amount)),
          );
        }
      } catch (err) {
        debugPrint('Error refreshing supplier in dialog: $err');
      }
    }

    setState(() {
      _selectedEntity = entity;
      _entityId = entity.id;
      _entityName = entity.name;
      _entitySearchCtrl.text = entity.name;
      _entityResults.clear();
      _isSearching = false;
      _hasSearched = false;
      _isLoadingInvoices = true;

      String typeLabel = 'جهة';
      if (entity.type == 'TRANSPORT_SUPPLIER') {
        typeLabel = 'مورد نقل';
      } else if (_entityType == 'SUPPLIER') {
        typeLabel = 'مورد';
      } else if (_entityType == 'SHIPPING_COMPANY') {
        typeLabel = 'شركة شحن';
      } else if (_entityType == 'CLEARING_AGENT') {
        typeLabel = 'مخلص جمركي';
      }

      _descCtrl.text = 'سداد مستحقات ل$typeLabel ${entity.name}';
    });

    try {
      final effectiveType = entity.type == 'TRANSPORT_SUPPLIER' ? 'transport_supplier' : _entityType;
      final results = await Future.wait([
        PaymentDao().getUnpaidLiabilities(effectiveType, entity.id),
        PaymentDao().getOpeningBalancePaid(effectiveType, entity.id),
      ]);
      final allLiabilities = results[0] as List<UnpaidLiabilityModel>;
      final openingPaidMap = results[1] as Map<String, double>;

      // Collect all currencies that have either unpaid liabilities or opening balances
      final currSet = <String>{};
      for (final l in allLiabilities) {
        if (l.currency.isNotEmpty) currSet.add(l.currency.toUpperCase());
      }
      if (entity.isMultiCurrency) {
        for (final c in entity.supportedCurrencies) {
          if (c.isNotEmpty) currSet.add(c.toUpperCase());
        }
        for (final c in entity.currentBalancesByCurrency.keys) {
          if (c.isNotEmpty) currSet.add(c.toUpperCase());
        }
        for (final c in entity.initialBalancesByCurrency.keys) {
          if (c.isNotEmpty) currSet.add(c.toUpperCase());
        }
      } else if (entity.currency.isNotEmpty && entity.currency != 'MULTI') {
        currSet.add(entity.currency.toUpperCase());
      }
      if (currSet.isEmpty || entity.isEgpOnlySupplier) {
        currSet.clear();
        currSet.add('EGP');
      }

      final availCurrencies = currSet.toList();

      // Determine initial settlement currency: prioritize the currency with active unpaid liabilities
      String targetCurrency = 'EGP';
      if (entity.isEgpOnlySupplier) {
        targetCurrency = 'EGP';
      } else {
        final liabCurrencies = allLiabilities
            .where((l) => l.dueAmount > 0.001)
            .map((l) => l.currency.toUpperCase())
            .toList();

        if (liabCurrencies.isNotEmpty) {
          targetCurrency = liabCurrencies.first;
        } else if (availCurrencies.contains('EGP')) {
          targetCurrency = 'EGP';
        } else {
          targetCurrency = availCurrencies.first;
        }
      }

      setState(() {
        _allFetchedLiabilities = allLiabilities;
        _availableCurrencies = availCurrencies;
        _openingPaidByCurrency = openingPaidMap;
      });

      _applyCurrency(targetCurrency, entity, allLiabilities);
    } catch (err) {
      setState(() => _isLoadingInvoices = false);
    }
  }

  void _switchCurrency(String newCurrency) {
    if (_selectedEntity == null || newCurrency == _currency) return;
    if (_selectedEntity!.isEgpOnlySupplier && newCurrency != 'EGP') return;
    _applyCurrency(newCurrency, _selectedEntity!, _allFetchedLiabilities);
  }

  void _applyCurrency(String cur, _PayableEntity e, List<UnpaidLiabilityModel> allLiab) {
    final unpaid = allLiab
        .where((l) => l.currency.toUpperCase() == cur.toUpperCase() && l.dueAmount > 0.001)
        .toList();

    double initialPayable = 0.0;
    if (e.isMultiCurrency) {
      initialPayable = e.initialBalancesByCurrency[cur] ?? 0.0;
    } else if (e.currency.toUpperCase() == cur.toUpperCase() &&
        e.initialBalanceDirection.toUpperCase() == 'CREDIT') {
      initialPayable = e.initialBalance;
    }

    final liabilitiesDue = unpaid.fold<double>(0.0, (sum, l) => sum + l.dueAmount);
    final paidOpening = _openingPaidByCurrency[cur.toUpperCase()] ?? 0.0;
    final remainingOpening = max(0.0, initialPayable - paidOpening);

    double openingRemaining = 0.0;
    if (remainingOpening > 0) {
      if (e.isMultiCurrency) {
        final curBal = e.currentBalancesByCurrency[cur];
        if (curBal != null) {
          if (curBal <= 0) {
            openingRemaining = 0.0;
          } else if (curBal >= liabilitiesDue) {
            openingRemaining = min(remainingOpening, curBal - liabilitiesDue);
          } else {
            openingRemaining = min(remainingOpening, curBal);
          }
        } else {
          // If curBal is null, the currency net balance in DB is 0.0 (filtered out by HAVING <> 0).
          // If any opening balance was paid or remainingOpening is already 0, openingRemaining is 0.
          if (paidOpening > 0) {
            openingRemaining = 0.0;
          } else {
            openingRemaining = remainingOpening;
          }
        }
      } else {
        if (e.outstandingBalance <= 0) {
          openingRemaining = 0.0;
        } else if (e.outstandingBalance >= liabilitiesDue) {
          openingRemaining = min(remainingOpening, e.outstandingBalance - liabilitiesDue);
        } else {
          openingRemaining = min(remainingOpening, e.outstandingBalance);
        }
      }
    }

    final totalOut = max(0.0, openingRemaining + liabilitiesDue);

    setState(() {
      _currency = cur;
      _unpaidLiabilities = unpaid;
      _openingBalanceRemaining = openingRemaining;
      _totalOutstanding = totalOut;
      _isLoadingInvoices = false;

      _amountCtrl.text = totalOut > 0 ? totalOut.toStringAsFixed(2) : '';

      if (_sourceType == 'treasury') {
        _sourceId = _filteredTreasuries.isNotEmpty ? int.tryParse(_filteredTreasuries.first.id.toString()) : null;
      } else {
        _sourceId = _filteredBanks.isNotEmpty ? int.tryParse(_filteredBanks.first.id.toString()) : null;
      }
    });
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

      final effectiveType = _selectedEntity?.type == 'TRANSPORT_SUPPLIER' ? 'transport_supplier' : _entityType;
      await PaymentDao().entityMultiPayment(
        sourceType: _sourceType,
        sourceId: _sourceId!,
        amount: amount,
        currency: _currency,
        entityType: effectiveType,
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
      final effectiveType = _selectedEntity?.type == 'TRANSPORT_SUPPLIER' ? 'transport_supplier' : _entityType;
      String typeLabel = 'جهة';
      if (_selectedEntity?.type == 'TRANSPORT_SUPPLIER') typeLabel = 'مورد نقل';
      else if (_entityType == 'SUPPLIER') typeLabel = 'المورد';
      else if (_entityType == 'SHIPPING_COMPANY') typeLabel = 'شركة الشحن';
      else if (_entityType == 'CLEARING_AGENT') typeLabel = 'المخلص الجمركي';

      final desc = _descCtrl.text.trim().isNotEmpty 
          ? _descCtrl.text.trim() 
          : 'سداد متعدد ل$typeLabel $_entityName';

      final payload = <String, dynamic>{
        'is_multi_payment': true,
        'source_type': _sourceType,
        'source_id': _sourceId,
        'entity_type': effectiveType,
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
                                _loadDefaultEntities();
                              }
                            },
                          ),
                        ),
                      ],
                    ),

                    if (_entityType == 'SUPPLIER') ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.category_outlined, size: 14, color: AppTheme.primary),
                          const SizedBox(width: 6),
                          const Text(
                            'نوع المورد:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primary,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ],
                      ),
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
                                    _clearSelectedEntity();
                                  });
                                  if (_entitySearchCtrl.text.isNotEmpty) {
                                    _onSearchChanged(_entitySearchCtrl.text);
                                  } else {
                                    _loadDefaultEntities();
                                  }
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: isSelected ? color.withValues(alpha: 0.18) : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected ? color : const Color(0xFFCBD5E1),
                                      width: isSelected ? 1.5 : 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(icon, size: 13, color: isSelected ? color : const Color(0xFF475569)),
                                      const SizedBox(width: 5),
                                      Text(
                                        label,
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 11,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                          color: isSelected ? color : const Color(0xFF334155),
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
                    ],

                    const SizedBox(height: 16),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_selectedEntity != null) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 34,
                                            height: 34,
                                            decoration: BoxDecoration(
                                              color: _getSupplierTypeColor(_selectedEntity!.supplierType, _selectedEntity!.code).withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Icon(
                                              _getSupplierTypeIcon(_selectedEntity!.supplierType, _selectedEntity!.code),
                                              color: _getSupplierTypeColor(_selectedEntity!.supplierType, _selectedEntity!.code),
                                              size: 18,
                                            ),
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
                                                        _selectedEntity!.name,
                                                        style: const TextStyle(
                                                          fontFamily: 'Cairo',
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.bold,
                                                          color: Color(0xFF0F172A),
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                      decoration: BoxDecoration(
                                                        color: _getSupplierTypeColor(_selectedEntity!.supplierType, _selectedEntity!.code).withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        _selectedEntity!.type == 'TRANSPORT_SUPPLIER'
                                                            ? 'مورد نقل'
                                                            : _selectedEntity!.type == 'SHIPPING_COMPANY'
                                                                ? 'شركة شحن'
                                                                : _selectedEntity!.type == 'CLEARING_AGENT'
                                                                    ? 'مخلص جمركي'
                                                                    : _getSupplierTypeLabel(_selectedEntity!.supplierType, _selectedEntity!.code),
                                                        style: TextStyle(
                                                          fontFamily: 'Cairo',
                                                          fontSize: 9.5,
                                                          fontWeight: FontWeight.bold,
                                                          color: _getSupplierTypeColor(_selectedEntity!.supplierType, _selectedEntity!.code),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                if (_selectedEntity!.code.isNotEmpty)
                                                  Text(
                                                    'كود: ${_selectedEntity!.code}',
                                                    style: const TextStyle(
                                                      fontFamily: 'Cairo',
                                                      fontSize: 11,
                                                      color: Color(0xFF64748B),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.close_rounded, size: 18),
                                            onPressed: _clearSelectedEntity,
                                            tooltip: 'تغيير الجهة',
                                          ),
                                        ],
                                      ),
                                      const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 6),
                                        child: Divider(height: 1),
                                      ),
                                      Row(
                                        children: [
                                          const Icon(Icons.account_balance_wallet_outlined, size: 13, color: Color(0xFF0F766E)),
                                          const SizedBox(width: 5),
                                          const Text(
                                            'أرصدة الجهة بالعملات (انقر لاختيار عملة السداد):',
                                            style: TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF0F766E),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      _buildEntityMultiCurrencyPills(_selectedEntity!),
                                    ],
                                  ),
                                ),
                              ] else ...[
                                TextFormField(
                                  controller: _entitySearchCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'بحث عن جهة السداد...',
                                    hintText: 'اختر من القائمة أدناه أو ابحث...',
                                    labelStyle: const TextStyle(fontFamily: 'Cairo'),
                                    hintStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.grey),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    prefixIcon: const Icon(Icons.search),
                                    suffixIcon: _entitySearchCtrl.text.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(Icons.clear, size: 20),
                                            onPressed: _clearSelectedEntity,
                                          )
                                        : null,
                                  ),
                                  onTap: () {
                                    if (_entitySearchCtrl.text.isEmpty && _entityId == null && _defaultEntities.isNotEmpty) {
                                      setState(() {
                                        _entityResults = List.from(_defaultEntities);
                                      });
                                    }
                                  },
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
                                    constraints: const BoxConstraints(maxHeight: 180),
                                    child: ListView.separated(
                                      shrinkWrap: true,
                                      itemCount: _entityResults.length,
                                      separatorBuilder: (_, __) => const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        final s = _entityResults[index];
                                        final badgeColor = s.type == 'TRANSPORT_SUPPLIER'
                                            ? const Color(0xFF0284C7)
                                            : s.type == 'SHIPPING_COMPANY'
                                                ? const Color(0xFF3B82F6)
                                                : s.type == 'CLEARING_AGENT'
                                                    ? const Color(0xFFF97316)
                                                    : _getSupplierTypeColor(s.supplierType, s.code);
                                        final badgeIcon = s.type == 'TRANSPORT_SUPPLIER'
                                            ? Icons.local_shipping_rounded
                                            : s.type == 'SHIPPING_COMPANY'
                                                ? Icons.flight_takeoff_rounded
                                                : s.type == 'CLEARING_AGENT'
                                                    ? Icons.assignment_turned_in_rounded
                                                    : _getSupplierTypeIcon(s.supplierType, s.code);
                                        final typeLabel = s.type == 'TRANSPORT_SUPPLIER'
                                            ? 'مورد نقل'
                                            : s.type == 'SHIPPING_COMPANY'
                                                ? 'شركة شحن'
                                                : s.type == 'CLEARING_AGENT'
                                                    ? 'مخلص جمركي'
                                                    : _getSupplierTypeLabel(s.supplierType, s.code);

                                        return ListTile(
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
                                          title: Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  s.name,
                                                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
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
                                              if (s.code.isNotEmpty) ...[
                                                Text(
                                                  'كود: ${s.code}',
                                                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Color(0xFF64748B)),
                                                ),
                                                const Text('  |  ', style: TextStyle(color: Colors.grey, fontSize: 10)),
                                              ],
                                              Expanded(
                                                child: Text(
                                                  'الأرصدة: ${_formatEntityBalancesSummary(s)}',
                                                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          onTap: () => _onSelectEntity(s),
                                        );
                                      },
                                    ),
                                  ),
                              ],
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
                    
                    if (_selectedEntity != null && _availableCurrencies.length > 1) ...[
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text('عملة السداد:', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: _availableCurrencies.map((c) {
                                final isSelected = c == _currency;
                                final count = _allFetchedLiabilities
                                    .where((l) => l.currency.toUpperCase() == c.toUpperCase() && l.dueAmount > 0.001)
                                    .length;
                                return ChoiceChip(
                                  label: Text('$c ${count > 0 ? "($count مستحق)" : ""}',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 12,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        color: isSelected ? Colors.white : Colors.black87,
                                      )),
                                  selected: isSelected,
                                  selectedColor: AppTheme.primary,
                                  backgroundColor: Colors.grey.shade100,
                                  onSelected: (selected) {
                                    if (selected && c != _currency) {
                                      _switchCurrency(c);
                                    }
                                  },
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ],

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
                                          Builder(builder: (_) {
                                            final hasHashOrNum = int.tryParse(inv.referenceNumber) != null || inv.referenceNumber.startsWith('#');
                                            final displayLabel = hasHashOrNum 
                                                ? '$refTitle #${inv.referenceNumber.replaceAll('#', '')}' 
                                                : '$refTitle: ${inv.referenceNumber}';
                                            return Text('$displayLabel (${inv.liabilityDate.toLocal().toString().split(' ')[0]})', 
                                              style: TextStyle(fontFamily: 'Cairo', fontWeight: alloc > 0 ? FontWeight.bold : FontWeight.normal, color: AppTheme.textPrimary));
                                          }),
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
        OutlinedButton.icon(
          onPressed: _isSaving || _isLoadingInvoices || !isFormValid ? null : _submitDraft,
          style: OutlinedButton.styleFrom(
            foregroundColor: isFormValid ? AppTheme.primary : Colors.grey,
            side: BorderSide(color: isFormValid ? AppTheme.primary : Colors.grey.shade700),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          icon: const Icon(Icons.drafts_outlined, size: 18),
          label: const Text('حفظ مسودة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14)),
        ),
        ElevatedButton.icon(
          onPressed: _isSaving || _isLoadingInvoices || !isFormValid ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: isFormValid ? AppTheme.primary : Colors.grey.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          icon: _isSaving 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('تأكيد السداد', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15)),
        ),
      ],
    );
  }
}
