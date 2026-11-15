import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:go_router/go_router.dart';
import 'package:collection/collection.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../core/widgets/read_only_guard.dart';
import '../../data/dao/lot_dao.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/dao/station_dao.dart';
import '../../data/models/lot_model.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/station_model.dart';
import '../../data/dao/fruit_type_dao.dart';
import '../../data/models/fruit_type_model.dart';

import '../../data/services/lot_payment_service.dart';
import '../../data/services/product_cost_center_sync_service.dart';
import '../../data/services/currency_conversion_service.dart';
import '../../data/services/crop_purchase_calculation_service.dart';
import '../../core/data_change_event_bus.dart';

class LotFormPage extends StatefulWidget {
  final LotReceiptModel? lot;
  const LotFormPage({super.key, this.lot});

  @override
  State<LotFormPage> createState() => _LotFormPageState();
}

class _LotFormPageState extends State<LotFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _dao = LotDao();

  late TextEditingController _productNameCtrl;
  late TextEditingController _grossWeightCtrl;
  late TextEditingController _netWeightCtrl;
  late TextEditingController _notesCtrl;
  late TextEditingController _unitCostCtrl;
  late TextEditingController _expectedSupplierAmountCtrl;
  late TextEditingController _supplierController;
  late TextEditingController _cartonCountCtrl;
  late TextEditingController _weightPerCartonCtrl;
  late TextEditingController _grossWeightPerCartonCtrl;
  late TextEditingController _pricePerCartonCtrl;
  late TextEditingController _exchangeRateCtrl;
  late TextEditingController _productController;
  late TextEditingController _paidAmountCtrl;

  DateTime _receiptDate = DateTime.now();
  String? _selectedSupplierId;
  int? _selectedStationId;
  String? _selectedProductId;
  String _purchaseMode = 'weight';
  String _currency = 'EGP';
  double _exchangeRate = 1.0;
  bool _isMultiCurrencySupplier = false;
  List<String> _supplierCurrencies = [];

  String? _selectedTreasuryId;
  String? _selectedPaymentSourceType;
  int? _selectedBankAccountId;
  String? _selectedTreasuryCurrency;
  List<Map<String, dynamic>> _treasuries = [];
  List<Map<String, dynamic>> _bankAccounts = [];

  List<SupplierModel> _suppliers = [];
  List<StationModel> _stations = [];
  List<FruitTypeModel> _fruitTypes = [];
  bool _loadingData = true;
  bool _saving = false;
  bool _formSubmitted = false;
  int? _selectedPurchaseItemId;

  bool get _canEdit => widget.lot == null || widget.lot?.isConfirmed != true;

  List<FruitTypeModel> get _filteredFruitTypes {
    return _fruitTypes.where((ft) {
      // Filter by supplier currency if supplier is selected
      if (_selectedSupplierId != null) {
        if (ft.currency.toUpperCase() != _currency.toUpperCase()) return false;
      }
      // Filter by purchase mode
      final ftMode = ft.purchaseMode ?? ft.latestPurchaseMode;
      if (ftMode != _purchaseMode) return false;
      return true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    final lot = widget.lot;
    _productNameCtrl = TextEditingController(text: lot?.productName ?? '');
    _grossWeightCtrl =
        TextEditingController(text: lot?.grossWeightKg.toString());
    _netWeightCtrl =
        TextEditingController(text: lot?.netWeightKg != null && lot!.netWeightKg > 0
            ? (lot.purchaseMode == 'carton' && lot.weightPerCartonKg != null && lot.weightPerCartonKg! > 0
                ? (lot.netWeightKg / lot.weightPerCartonKg!).round().toString()
                : lot.netWeightKg.toString())
            : '');
    _notesCtrl = TextEditingController(text: lot?.notes);
    // Reverse-calculate the original purchase price the user entered:
    // For weight mode: originalPrice = totalProductCost / grossWeight
    // (productCostPerKg stores totalProductCost/netWeight which is the NEW cost,
    //  but the user entered totalProductCost/grossWeight as purchase price)
    final double editPurchasePrice;
    if (lot != null && lot.purchaseMode != 'carton' && lot.grossWeightKg > 0 && lot.totalProductCost > 0) {
      editPurchasePrice = lot.totalProductCost / lot.grossWeightKg;
    } else {
      editPurchasePrice = lot?.productCostPerKg ?? 0;
    }
    _unitCostCtrl = TextEditingController(
      text: editPurchasePrice > 0
          ? (editPurchasePrice == editPurchasePrice.roundToDouble()
              ? editPurchasePrice.toInt().toString()
              : editPurchasePrice.toStringAsFixed(2))
          : null,
    );
    _expectedSupplierAmountCtrl = TextEditingController(text: '0.00');
    _supplierController = TextEditingController();
    _selectedSupplierId = lot?.supplierId;
    _selectedStationId = int.tryParse(lot?.stationId ?? '');
    _selectedProductId = lot?.fruitTypeId;
    _selectedPurchaseItemId = int.tryParse(lot?.purchaseInvoiceItemId ?? '');
    _receiptDate = lot?.receiptDate ?? DateTime.now();
    _purchaseMode = lot?.purchaseMode ?? 'weight';
    _cartonCountCtrl = TextEditingController(
        text: lot?.cartonCount != null ? lot!.cartonCount.toString() : '');
    _weightPerCartonCtrl = TextEditingController(
        text: lot?.weightPerCartonKg != null
            ? lot!.weightPerCartonKg.toString()
            : '');
    _grossWeightPerCartonCtrl = TextEditingController(
        text: lot?.grossWeightPerCartonKg != null
            ? lot!.grossWeightPerCartonKg.toString()
            : '');
    _pricePerCartonCtrl = TextEditingController(
        text: lot?.pricePerCarton != null
            ? lot!.pricePerCarton.toString()
            : '');
    _exchangeRateCtrl = TextEditingController(
        text: lot?.exchangeRate != null && lot!.exchangeRate != 1.0
            ? lot!.exchangeRate.toString()
            : '');
    _exchangeRate = lot?.exchangeRate ?? 1.0;
    _productController = TextEditingController(
        text: lot?.productName ?? '');
    _paidAmountCtrl = TextEditingController(
        text: lot?.paidAmount != null && lot!.paidAmount > 0
            ? lot.paidAmount.toString()
            : '0');
    _selectedPaymentSourceType = lot?.paymentSourceType ?? 'treasury';
    _selectedTreasuryId = lot?.paymentTreasuryId;
    _selectedBankAccountId = lot?.paymentBankAccountId;

    _grossWeightCtrl.addListener(_updateExpectedAmount);
    _netWeightCtrl.addListener(_updateExpectedAmount);
    _unitCostCtrl.addListener(_updateExpectedAmount);
    _cartonCountCtrl.addListener(_updateExpectedAmount);
    _weightPerCartonCtrl.addListener(_updateExpectedAmount);
    _grossWeightPerCartonCtrl.addListener(_updateExpectedAmount);
    _pricePerCartonCtrl.addListener(_updateExpectedAmount);
    _updateExpectedAmount();
    _loadData();
  }

  void _updateExpectedAmount() {
    double expectedAmount = 0;
    if (_purchaseMode == 'carton') {
      final cartonCount = (double.tryParse(_cartonCountCtrl.text) ?? 0).toInt();
      final pricePerCarton = double.tryParse(_pricePerCartonCtrl.text) ?? 0;
      final weightPerCarton = double.tryParse(_weightPerCartonCtrl.text) ?? 0;
      expectedAmount = CropPurchaseCalculationService.calculateTotalAmount(
        purchaseMethod: 'carton',
        cartonCount: cartonCount,
        pricePerCarton: pricePerCarton,
      );
      // Auto-fill gross weight per carton from net weight per carton
      if (weightPerCarton > 0 && (double.tryParse(_grossWeightPerCartonCtrl.text) ?? 0) <= 0) {
        _grossWeightPerCartonCtrl.text = weightPerCarton.toString();
      }
      // Auto-fill gross weight for inventory tracking
      final computedGross = cartonCount * weightPerCarton;
      if (computedGross > 0) {
        _grossWeightCtrl.text = computedGross.toStringAsFixed(3);
      }
    } else {
      // Weight mode: Financial liability to supplier = Gross Weight (الوزن الإجمالي/القائم) × Price per Kg
      final grossWeight = double.tryParse(_grossWeightCtrl.text) ?? 0;
      final netWeight = double.tryParse(_netWeightCtrl.text) ?? grossWeight;
      final unitCost = double.tryParse(_unitCostCtrl.text) ?? 0;
      expectedAmount = CropPurchaseCalculationService.calculateTotalAmount(
        purchaseMethod: 'weight',
        grossWeightKg: grossWeight > 0 ? grossWeight : netWeight,
        netWeightKg: netWeight,
        pricePerKg: unitCost,
      );
    }
    _expectedSupplierAmountCtrl.text = expectedAmount.toStringAsFixed(2);
    setState(() {});
  }

  @override
  void dispose() {
    _grossWeightCtrl.removeListener(_updateExpectedAmount);
    _netWeightCtrl.removeListener(_updateExpectedAmount);
    _unitCostCtrl.removeListener(_updateExpectedAmount);
    _cartonCountCtrl.removeListener(_updateExpectedAmount);
    _weightPerCartonCtrl.removeListener(_updateExpectedAmount);
    _grossWeightPerCartonCtrl.removeListener(_updateExpectedAmount);
    _pricePerCartonCtrl.removeListener(_updateExpectedAmount);
    _productNameCtrl.dispose();
    _grossWeightCtrl.dispose();
    _netWeightCtrl.dispose();
    _notesCtrl.dispose();
    _unitCostCtrl.dispose();
    _expectedSupplierAmountCtrl.dispose();
    _supplierController.dispose();
    _cartonCountCtrl.dispose();
    _weightPerCartonCtrl.dispose();
    _grossWeightPerCartonCtrl.dispose();
    _pricePerCartonCtrl.dispose();
    _exchangeRateCtrl.dispose();
    _productController.dispose();
    _paidAmountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        SupplierDao().getAll(supplierTypes: ['crop', 'shared']),
        StationDao().getAll(),
        FruitTypeDao().getAllWithPrices(),
        Supabase.instance.client.from('treasuries').select('id,name,type,treasury_balances(currency,balance)'),
        Supabase.instance.client.from('bank_accounts').select('id,name,currency,balance'),
      ]);
      if (mounted) {
        final cropSuppliers = (results[0] as List<SupplierModel>)
            .where((s) => s.isCropSupplier)
            .toList();
        setState(() {
          _suppliers = cropSuppliers;
          _stations = results[1] as List<StationModel>;
          _fruitTypes = results[2] as List<FruitTypeModel>;
          _treasuries = List<Map<String, dynamic>>.from(results[3] as List)
              .where((t) => t['type']?.toString() != 'employee')
              .toList();
          _bankAccounts = List<Map<String, dynamic>>.from(results[4] as List);
          _loadingData = false;
        });
        if (_selectedSupplierId != null) {
          var s = _suppliers
              .where((s) => s.id == _selectedSupplierId)
              .firstOrNull;
          if (s == null) {
            final allSupps = await SupplierDao().getAll(limit: 1000);
            s = allSupps.where((x) => x.id == _selectedSupplierId).firstOrNull;
            if (s != null && mounted) {
              setState(() {
                _suppliers.insert(0, s!);
              });
            }
          }
          if (s != null) {
            _supplierController.text = s.displayName;
            _isMultiCurrencySupplier = s.supportsMultiCurrency;
            if (s.supportsMultiCurrency) {
              _supplierCurrencies = s.supportedCurrencies;
              // In edit mode, preserve the lot's saved currency
              if (widget.lot != null && widget.lot!.currency.isNotEmpty && widget.lot!.currency != 'MULTI') {
                _currency = widget.lot!.currency;
              } else {
                _currency = s.getCurrencyForTransactionType('crop');
              }
            } else {
              _supplierCurrencies = [];
              _currency = s.currency;
            }
            // In edit mode, preserve the lot's saved exchange rate
            if (widget.lot == null || widget.lot!.exchangeRate == 1.0) {
              _fetchExchangeRate();
            }
          }
        }
        if (_selectedTreasuryId != null) {
          for (final t in _treasuries) {
            if (t['id']?.toString() == _selectedTreasuryId) {
              final balancesRaw = t['treasury_balances'];
              final List<dynamic> balances = balancesRaw is List ? balancesRaw : [];
              for (final b in balances) {
                if ((b['currency']?.toString() ?? '').toUpperCase() == _currency.toUpperCase()) {
                  _selectedTreasuryCurrency = b['currency']?.toString();
                  break;
                }
              }
              break;
            }
          }
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  TextStyle get _inputTextStyle {
    final isDark = AppTheme.isDark(context);
    return TextStyle(
      color: isDark ? Colors.white : Colors.black,
      fontWeight: FontWeight.bold,
      fontFamily: 'Cairo',
    );
  }

  TextStyle get _readOnlyTextStyle {
    final isDark = AppTheme.isDark(context);
    return TextStyle(
      color: isDark ? AppTheme.textSecondary : Colors.black87,
      fontWeight: FontWeight.bold,
      fontFamily: 'Cairo',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.background : AppTheme.lightBackground,
        body: Container(
          decoration: isDark
              ? const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.background,
                      Color(0xFF0D2137),
                      AppTheme.background
                    ],
                  ),
                )
              : null,
          child: _loadingData
              ? Center(
                  child: CircularProgressIndicator(
                      color: isDark ? AppTheme.primary : const Color(0xFF0284C7)))
              : SingleChildScrollView(
                  padding:
                      EdgeInsets.only(top: MediaQuery.of(context).padding.top),
                  child: Form(
                    key: _formKey,
                    child: Column(children: [
                      _buildHeader(),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          _buildSection('بيانات الشراء والتوريد', [
                            _buildPurchaseModeToggle(),
                            const SizedBox(height: 12),
                            _buildSupplierDropdown(),
                            const SizedBox(height: 12),
                            if (_isMultiCurrencySupplier && _selectedSupplierId != null)
                              _buildCurrencyDropdown(),
                            if (_isMultiCurrencySupplier && _selectedSupplierId != null)
                              const SizedBox(height: 12),
                            _buildProductField(),
                            const SizedBox(height: 12),
                            _buildDatePicker(),
                            const SizedBox(height: 12),
                            if (_purchaseMode == 'weight') ...[
                              _buildWeightField(
                                  _grossWeightCtrl,
                                  'الوزن الإجمالي (كجم)',
                                  'وزن المحصول بالكيلو'),
                              const SizedBox(height: 12),
                              _buildWeightField(
                                  _netWeightCtrl,
                                  'الوزن الصافي (كجم)',
                                  'الوزن الصافي',
                                  extraValidator: (v) {
                                    final gross = double.tryParse(_grossWeightCtrl.text) ?? 0;
                                    final net = double.tryParse(v ?? '') ?? 0;
                                    if (gross > 0 && net > gross) {
                                      return 'الوزن الصافي ($net) لا يمكن أن يتجاوز الوزن الإجمالي ($gross)';
                                    }
                                    return null;
                                  }),
                              _buildFieldError(_weightValidationError),
                              const SizedBox(height: 12),
                              _buildRequiredWeightField(
                                  _unitCostCtrl,
                                  'سعر الشراء ($_currency/كجم)',
                                  'سعر شراء الكيلو'),
                            ] else ...[
                              _buildCartonCountField(),
                              const SizedBox(height: 12),
                              _buildWeightPerCartonField(),
                              const SizedBox(height: 12),
                              _buildGrossWeightPerCartonField(),
                              const SizedBox(height: 12),
                              _buildPricePerCartonField(),
                              const SizedBox(height: 12),
                              _buildWeightField(
                                  _grossWeightCtrl,
                                  'الوزن الإجمالي المحسوب (كجم)',
                                  'محسوب تلقائياً من الكراتين',
                                  readOnly: true),
                              const SizedBox(height: 12),
                              _buildNetCartonField(),
                              _buildFieldError(_cartonValidationError),
                            ],
                            const SizedBox(height: 12),
                            _buildExpectedAmountField(),
                            const SizedBox(height: 12),
                            //_buildPaidAmountField(),
                            if ((double.tryParse(_paidAmountCtrl.text) ?? 0) > 0)
                              _buildPaymentSourceDropdown(),
                            const SizedBox(height: 12),
                            _buildStationDropdown(),
                            const SizedBox(height: 12),
                           // _buildNotesField(),
                          ]),
                          const SizedBox(height: 24),
                          _buildSaveButton(),
                          const SizedBox(height: 32),
                        ]),
                      ),
                    ]),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final isDark = AppTheme.isDark(context);
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 12,
              bottom: 12,
              left: 8,
              right: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0x3805192D) : Colors.white,
            border: Border(
                bottom: BorderSide(
                    color: isDark
                        ? AppTheme.glassBorder.withAlpha(50)
                        : const Color(0xFFCBD5E1))),
          ),
          child: Row(children: [
            IconButton(
              icon: Icon(Icons.arrow_forward,
                  color: isDark ? Colors.white : Colors.black),
              onPressed: () => context.pop(),
            ),
            Text(
              widget.lot != null ? 'تعديل المحصول' : 'محصول جديد',
              style: TextStyle(
                  color: isDark ? AppTheme.textPrimary : Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo'),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    final isDark = AppTheme.isDark(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark ? const Color(0x3805192D) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1),
                width: 1.2),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: isDark ? AppTheme.primary : Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo')),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductField() {
    final isDark = AppTheme.isDark(context);
    final filtered = _filteredFruitTypes;
    final hasFilters = _selectedSupplierId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            text: 'الصنف',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDark ? AppTheme.textSecondary : Colors.black,
              fontFamily: 'Cairo',
            ),
            children: const [
              TextSpan(
                text: ' *',
                style: TextStyle(color: AppTheme.danger),
              ),
            ],
          ),
        ),
        // ── Context filter chips ──
        if (hasFilters)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _buildFilterChip(
                  icon: Icons.scale_outlined,
                  label: _purchaseMode == 'carton' ? 'بالكراتين' : 'بالوزن',
                ),
                _buildFilterChip(
                  icon: Icons.monetization_on_outlined,
                  label: _currency,
                ),
                _buildFilterChip(
                  icon: Icons.inventory_2_outlined,
                  label: '${filtered.length} صنف متاح',
                  color: filtered.isEmpty ? AppTheme.danger : AppTheme.cyan,
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        TypeAheadField<FruitTypeModel>(
          key: ValueKey('${_selectedSupplierId ?? ''}_${_selectedProductId ?? ''}_${_currency}_$_purchaseMode'),
          controller: _productController,
          autoFlipDirection: true,
          hideOnEmpty: false,
          hideOnError: true,
          suggestionsCallback: (pattern) {
            // Show all items on empty to act as a dropdown
            if (pattern.isEmpty) return filtered;
            final lower = pattern.toLowerCase();
            return filtered.where((ft) {
              return ft.name.toLowerCase().contains(lower) ||
                     ft.code.toLowerCase().contains(lower);
            }).toList();
          },
          emptyBuilder: (context) {
            return Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_off_rounded, size: 28, color: isDark ? AppTheme.textSecondary.withValues(alpha: 0.5) : Colors.black38),
                  const SizedBox(height: 6),
                  Text(
                    'لا يوجد صنف بهذا الاسم.\nتأكد من نوع الشراء ($_purchaseMode == "carton" ? "كراتين" : "وزن") والعملة ($_currency)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                      color: isDark ? AppTheme.textSecondary : Colors.black87,
                    ),
                  ),
                ],
              ),
            );
          },
          itemBuilder: (context, fruitType) {
            final isSelected = fruitType.id == _selectedProductId;
            final priceText = fruitType.latestPurchasePrice != null
                ? '${fruitType.latestPurchasePrice!.toStringAsFixed(2)} ${SupplierModel.getCurrencySymbol(fruitType.currency)}'
                : null;
            return Container(
              color: isSelected ? AppTheme.primary.withValues(alpha: 0.1) : null,
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      fruitType.code,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ),
                title: Text(
                  fruitType.name,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? AppTheme.primary : (isDark ? Colors.white : Colors.black),
                  ),
                ),
                subtitle: priceText != null
                    ? Text(
                        'آخر سعر: $priceText',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppTheme.textSecondary : Colors.black87,
                        ),
                      )
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      fruitType.currency,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppTheme.textSecondary : Colors.black87,
                      ),
                    ),
                    if (isSelected) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.check_circle, size: 16, color: AppTheme.primary),
                    ],
                  ],
                ),
              ),
            );
          },
          onSelected: (fruitType) {
            setState(() {
              _selectedProductId = fruitType.id;
              _productNameCtrl.text = fruitType.name;
              _productController.text = fruitType.name;
            });
          },
          decorationBuilder: (context, child) {
            return Material(
              type: MaterialType.card,
              elevation: 12,
              borderRadius: BorderRadius.circular(14),
              color: isDark ? const Color(0xFF0A1E38) : Colors.white,
              shadowColor: Colors.black.withValues(alpha: isDark ? 0.5 : 0.1),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? Colors.transparent : const Color(0xFFCBD5E1),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: child,
                  ),
                ),
              ),
            );
          },
          builder: (context, controller, focusNode) {
            return TextField(
              enabled: _canEdit,
              controller: controller,
              focusNode: focusNode,
              decoration: InputDecoration(
                labelText: 'بحث عن الصنف *',
                hintText: 'اكتب اسم الصنف أو الكود...',
                hintStyle: TextStyle(
                    color: isDark ? AppTheme.textSecondary : Colors.black54,
                    fontSize: 13,
                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                    fontFamily: 'Cairo'),
                labelStyle: TextStyle(
                    color: isDark ? AppTheme.textSecondary : Colors.black,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo'),
                filled: true,
                fillColor: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                        color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                        color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                        color: AppTheme.primary,
                        width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                prefixIcon: Icon(Icons.search_rounded,
                    color: isDark ? AppTheme.textSecondary : Colors.black54, size: 20),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_selectedProductId != null && _canEdit)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedProductId = null;
                            _productNameCtrl.clear();
                            _productController.clear();
                          });
                          controller.clear();
                        },
                        child: Icon(Icons.close,
                            size: 18,
                            color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black54),
                      ),
                    const SizedBox(width: 4),
                    // Quick-picker icon button
                    GestureDetector(
                      onTap: _canEdit ? () => _showItemPickerSheet() : null,
                      child: Container(
                        margin: const EdgeInsets.only(left: 8, right: 4),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                        ),
                        child: const Icon(Icons.grid_view_rounded, size: 18, color: AppTheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
              style: _inputTextStyle,
              onTap: () {
                // Trigger suggestions on tap (acts like a dropdown)
                if (controller.text.isEmpty) {
                  controller.text = '';
                }
              },
            );
          },
        ),
        // Selected item indicator
        if (_selectedProductId != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.success.withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_outline, size: 14, color: AppTheme.success),
                  const SizedBox(width: 6),
                  Text(
                    'تم اختيار: ${_productNameCtrl.text}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.success, fontFamily: 'Cairo'),
                  ),
                ],
              ),
            ),
          ),
        if (_selectedProductId == null && _formSubmitted)
          const Padding(
            padding: EdgeInsets.only(top: 4, right: 4),
            child: Text('يرجى اختيار الصنف',
                style: TextStyle(color: AppTheme.danger, fontSize: 12, fontFamily: 'Cairo')),
          ),
      ],
    );
  }

  /// Filter chip widget for showing active context filters
  Widget _buildFilterChip({required IconData icon, required String label, Color? color}) {
    final isDark = AppTheme.isDark(context);
    final chipColor = color ?? AppTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: chipColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: chipColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isDark ? chipColor : Colors.black,
                fontFamily: 'Cairo'),
          ),
        ],
      ),
    );
  }

  /// Full-screen bottom sheet item picker
  void _showItemPickerSheet() {
    final isDark = AppTheme.isDark(context);
    final items = _filteredFruitTypes;
    String searchQuery = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final filtered = searchQuery.isEmpty
                ? items
                : items.where((ft) {
                    final q = searchQuery.toLowerCase();
                    return ft.name.toLowerCase().contains(q) ||
                           ft.code.toLowerCase().contains(q);
                  }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0A1E38) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(
                  color: isDark ? Colors.transparent : const Color(0xFFCBD5E1),
                ),
              ),
              child: Column(
                children: [
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.25) : const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'اختيار الصنف',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${filtered.length} صنف',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: AppTheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Search field
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: TextField(
                      autofocus: false,
                      onChanged: (v) => setSheetState(() => searchQuery = v),
                      style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                          fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'بحث سريع بالاسم أو الكود...',
                        hintStyle: TextStyle(
                            fontFamily: 'Cairo',
                            color: isDark ? Colors.white.withValues(alpha: 0.35) : Colors.black54,
                            fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                            fontSize: 13),
                        prefixIcon: Icon(Icons.search,
                            color: isDark ? AppTheme.textSecondary : Colors.black54, size: 20),
                        filled: true,
                        fillColor: isDark ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: isDark ? Colors.transparent : const Color(0xFFCBD5E1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: isDark ? Colors.transparent : const Color(0xFFCBD5E1)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  Divider(
                      color: isDark ? const Color(0x22FFFFFF) : const Color(0xFFE2E8F0),
                      height: 1),
                  // Items grid/list
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.inbox_outlined,
                                    size: 48,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.2)
                                        : Colors.black26),
                                const SizedBox(height: 8),
                                Text(
                                  'لا توجد أصناف متطابقة',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.4)
                                          : Colors.black54),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (ctx, i) {
                              final ft = filtered[i];
                              final isSelected = ft.id == _selectedProductId;
                              final priceText = ft.latestPurchasePrice != null
                                  ? '${ft.latestPurchasePrice!.toStringAsFixed(2)} ${SupplierModel.getCurrencySymbol(ft.currency)}'
                                  : null;
                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedProductId = ft.id;
                                    _productNameCtrl.text = ft.name;
                                    _productController.text = ft.name;
                                  });
                                  Navigator.of(ctx).pop();
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppTheme.primary.withValues(alpha: 0.15)
                                        : (isDark
                                            ? Colors.white.withValues(alpha: 0.04)
                                            : const Color(0xFFF8FAFC)),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppTheme.primary
                                          : (isDark
                                              ? Colors.white.withValues(alpha: 0.08)
                                              : const Color(0xFFE2E8F0)),
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      // Code badge
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: isSelected
                                                ? [AppTheme.primary, AppTheme.primary.withValues(alpha: 0.7)]
                                                : [const Color(0xFF1A3A5C), const Color(0xFF0F2744)],
                                          ),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Center(
                                          child: Text(
                                            ft.code,
                                            style: TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: isSelected ? Colors.white : AppTheme.primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Name & price
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              ft.name,
                                              style: TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: isSelected
                                                    ? AppTheme.primary
                                                    : (isDark ? Colors.white : Colors.black),
                                              ),
                                            ),
                                            if (priceText != null)
                                              Text(
                                                'آخر سعر: $priceText',
                                                style: TextStyle(
                                                  fontFamily: 'Cairo',
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: isDark
                                                      ? Colors.white.withValues(alpha: 0.45)
                                                      : Colors.black87,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      // Currency + check
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            ft.currency,
                                            style: TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: isDark
                                                  ? Colors.white.withValues(alpha: 0.5)
                                                  : Colors.black87,
                                            ),
                                          ),
                                          if (isSelected)
                                            const Icon(Icons.check_circle, size: 18, color: AppTheme.primary),
                                        ],
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
            );
          },
        );
      },
    );
  }


  Widget _buildSupplierDropdown() {
    final isDark = AppTheme.isDark(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            text: 'المورد',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDark ? AppTheme.textSecondary : Colors.black,
              fontFamily: 'Cairo',
            ),
            children: const [
              TextSpan(
                text: ' *',
                style: TextStyle(color: AppTheme.danger),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TypeAheadField<SupplierModel>(
          key: ValueKey(_selectedSupplierId),
          controller: _supplierController,
          autoFlipDirection: true,
          hideOnEmpty: true,
          hideOnError: true,
          suggestionsCallback: (pattern) {
            final cropSuppliers = _suppliers.where((s) => s.isCropSupplier).toList();
            if (pattern.isEmpty) return cropSuppliers;
            final lower = pattern.toLowerCase();
            return cropSuppliers.where((s) {
              return s.displayName.toLowerCase().contains(lower) ||
                  s.supplierCode.toLowerCase().contains(lower) ||
                  s.name.toLowerCase().contains(lower);
            }).toList();
          },
          itemBuilder: (context, supplier) {
            return ListTile(
              dense: true,
              title: Text(supplier.displayName,
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black)),
            );
          },
          onSelected: (supplier) {
            setState(() {
              final oldCurrency = _currency;
              _selectedSupplierId = supplier.id;
              _isMultiCurrencySupplier = supplier.supportsMultiCurrency;
              if (supplier.supportsMultiCurrency) {
                _supplierCurrencies = supplier.supportedCurrencies;
                _currency = supplier.getCurrencyForTransactionType('crop');
              } else {
                _supplierCurrencies = [];
                _currency = supplier.currency;
              }
              if (oldCurrency != _currency) {
                _selectedProductId = null;
                _productNameCtrl.clear();
                _productController.clear();
              }
              if (_currency.toUpperCase() == 'EGP') {
                _exchangeRate = 1.0;
                _exchangeRateCtrl.text = '';
              }
            });
            _fetchExchangeRate();
            _supplierController.text = supplier.displayName;
          },
          builder: (context, controller, focusNode) {
            return TextField(
              enabled: _canEdit,
              controller: controller,
              focusNode: focusNode,
              style: _inputTextStyle,
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم أو الكود...',
                hintStyle: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                  color: isDark ? Colors.white.withValues(alpha: 0.35) : Colors.black54,
                ),
                suffixIcon: _selectedSupplierId != null && _canEdit
                    ? IconButton(
                        icon: Icon(Icons.clear,
                            size: 18,
                            color: isDark ? Colors.white : Colors.black),
                        onPressed: () {
                          setState(() => _selectedSupplierId = null);
                          _supplierController.clear();
                        },
                      )
                    : const Icon(Icons.search,
                        size: 20, color: AppTheme.primary),
                filled: true,
                fillColor: isDark ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF8FAFC),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFCBD5E1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFCBD5E1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: AppTheme.primary, width: 1.5),
                ),
              ),
            );
          },
          decorationBuilder: (context, child) {
            return Material(
              type: MaterialType.card,
              elevation: 8,
              borderRadius: BorderRadius.circular(14),
              color: isDark ? const Color(0xFF0A1E38) : Colors.white,
              shadowColor: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? Colors.transparent : const Color(0xFFCBD5E1),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: child,
                ),
              ),
            );
          },
        ),
        if (_selectedSupplierId != null && !_isMultiCurrencySupplier)
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.monetization_on_outlined, size: 14, color: AppTheme.warning),
                  const SizedBox(width: 6),
                  Text(
                    'عملة المورد: $_currency',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppTheme.warning : const Color(0xFFB45309),
                        fontFamily: 'Cairo'),
                  ),
                ],
              ),
            ),
          ),
        if (_selectedSupplierId == null && _formSubmitted)
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 4),
            child: Text('اختر المورد',
                style: TextStyle(color: AppTheme.danger, fontSize: 12, fontFamily: 'Cairo')),
          ),
        if (_selectedSupplierId != null && _currency.toUpperCase() != 'EGP') ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: _exchangeRateCtrl,
            enabled: _canEdit,
            decoration: _inputDecoration('سعر الصرف ($_currency → ج.م) *',
                hint: 'مثال: 50'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*')),
            ],
            style: _inputTextStyle,
            onChanged: (v) {
              _exchangeRate = double.tryParse(v) ?? 0.0;
              _updateExpectedAmount();
            },
            validator: (v) {
              final val = double.tryParse(v ?? '') ?? 0;
              if (val <= 0) return 'أدخل سعر الصرف';
              return null;
            },
          ),
        ],
      ],
    );
  }

  /// Currency dropdown for multi-currency suppliers
  Widget _buildCurrencyDropdown() {
    final isDark = AppTheme.isDark(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            text: 'عملة الشراء',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDark ? AppTheme.textSecondary : Colors.black,
              fontFamily: 'Cairo',
            ),
            children: const [
              TextSpan(
                text: ' *',
                style: TextStyle(color: AppTheme.danger),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.transparent : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : const Color(0xFFCBD5E1)),
          ),
          child: DropdownButtonFormField<String>(
            value: _supplierCurrencies.contains(_currency) ? _currency : null,
            items: _supplierCurrencies.map((cur) {
              final symbol = SupplierModel.getCurrencySymbol(cur);
              return DropdownMenuItem<String>(
                value: cur,
                child: Text(
                  '$cur ($symbol)',
                  style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                      fontSize: 14),
                ),
              );
            }).toList(),
            onChanged: _canEdit ? (value) {
              if (value != null && value != _currency) {
                setState(() {
                  final oldCurrency = _currency;
                  _currency = value;
                  if (oldCurrency != _currency) {
                    _selectedProductId = null;
                    _productNameCtrl.clear();
                    _productController.clear();
                  }
                  if (_currency.toUpperCase() == 'EGP') {
                    _exchangeRate = 1.0;
                    _exchangeRateCtrl.text = '';
                  }
                });
                _fetchExchangeRate();
              }
            } : null,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: InputBorder.none,
              prefixIcon: const Icon(Icons.currency_exchange, color: AppTheme.primary, size: 20),
              hintText: 'اختر العملة',
              hintStyle: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                  color: isDark ? Colors.white.withValues(alpha: 0.35) : Colors.black54),
            ),
            dropdownColor: isDark ? const Color(0xFF0A1E38) : Colors.white,
            style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo'),
            icon: Icon(Icons.arrow_drop_down,
                color: isDark ? AppTheme.textSecondary : Colors.black),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, size: 14, color: AppTheme.primary),
              const SizedBox(width: 6),
              Text(
                'مورد متعدد العملات — العملة المختارة: $_currency',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary, fontFamily: 'Cairo'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Fetch exchange rate from CurrencyConversionService for the selected currency
  Future<void> _fetchExchangeRate() async {
    if (_currency.toUpperCase() == 'EGP') {
      setState(() {
        _exchangeRate = 1.0;
        _exchangeRateCtrl.text = '';
      });
      _updateExpectedAmount();
      return;
    }
    try {
      final rate = await CurrencyConversionService.instance.getRate(_currency);
      if (mounted) {
        setState(() {
          _exchangeRate = rate;
          _exchangeRateCtrl.text = rate.toStringAsFixed(2);
        });
        _updateExpectedAmount();
      }
    } catch (_) {
      // Keep existing rate if fetch fails
    }
  }

  Widget _buildDatePicker() {
    final isDark = AppTheme.isDark(context);
    return GestureDetector(
      onTap: !_canEdit ? null : () async {
        final date = await showDatePicker(
          context: context,
          initialDate: _receiptDate,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
          builder: (context, child) => Theme(
            data: isDark
                ? ThemeData.dark().copyWith(
                    colorScheme: const ColorScheme.dark(primary: AppTheme.primary),
                  )
                : ThemeData.light().copyWith(
                    colorScheme: const ColorScheme.light(primary: AppTheme.primary),
                  ),
            child: child!,
          ),
        );
        if (date != null) setState(() => _receiptDate = date);
      },
      child: AbsorbPointer(
        child: TextFormField(
          decoration: _inputDecoration('تاريخ الشراء / التوريد',
              suffix: Icon(Icons.calendar_today,
                  color: isDark ? AppTheme.textSecondary : Colors.black, size: 18)),
          controller: TextEditingController(
            text:
                '${_receiptDate.year}-${_receiptDate.month.toString().padLeft(2, '0')}-${_receiptDate.day.toString().padLeft(2, '0')}',
          ),
          style: _readOnlyTextStyle,
        ),
      ),
    );
  }

  Widget _buildPurchaseModeToggle() {
    final isDark = AppTheme.isDark(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('طريقة الشراء',
            style: TextStyle(
                color: isDark ? AppTheme.textSecondary : Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo')),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: RadioListTile<String>(
                title: Text('بالوزن',
                    style: TextStyle(
                        color: isDark ? AppTheme.textPrimary : Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        fontFamily: 'Cairo')),
                value: 'weight',
                groupValue: _purchaseMode,
                onChanged: !_canEdit
                    ? null
                    : (v) => setState(() {
                          _purchaseMode = v!;
                          _selectedProductId = null;
                          _productNameCtrl.clear();
                          _productController.clear();
                          _updateExpectedAmount();
                        }),
                activeColor: AppTheme.primary,
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            Expanded(
              child: RadioListTile<String>(
                title: Text('بالكرتون',
                    style: TextStyle(
                        color: isDark ? AppTheme.textPrimary : Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        fontFamily: 'Cairo')),
                value: 'carton',
                groupValue: _purchaseMode,
                onChanged: !_canEdit
                    ? null
                    : (v) => setState(() {
                          _purchaseMode = v!;
                          _selectedProductId = null;
                          _productNameCtrl.clear();
                          _productController.clear();
                          _updateExpectedAmount();
                        }),
                activeColor: AppTheme.primary,
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCartonCountField() {
    return TextFormField(
      controller: _cartonCountCtrl,
      decoration: _inputDecoration('عدد الكراتين *', hint: 'عدد الكراتين'),
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*')),
      ],
      style: _inputTextStyle,
      onChanged: (_) { _updateExpectedAmount(); setState(() {}); },
      validator: (v) {
        if (_purchaseMode != 'carton') return null;
        final val = double.tryParse(v ?? '') ?? 0;
        if (val <= 0) return 'أدخل عدد الكراتين';
        return null;
      },
    );
  }

  Widget _buildWeightPerCartonField() {
    return TextFormField(
      controller: _weightPerCartonCtrl,
      decoration: _inputDecoration('وزن الكرتونة الصافي (كجم) *',
          hint: 'الوزن الصافي لكرتونة واحدة'),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*')),
      ],
      style: _inputTextStyle,
      onChanged: (_) => _updateExpectedAmount(),
      validator: (v) {
        if (_purchaseMode != 'carton') return null;
        final val = double.tryParse(v ?? '') ?? 0;
        if (val <= 0) return 'أدخل وزن الكرتونة';
        return null;
      },
    );
  }

  Widget _buildGrossWeightPerCartonField() {
    return TextFormField(
      controller: _grossWeightPerCartonCtrl,
      decoration: _inputDecoration('الوزن الإجمالي للكرتونة (كجم) *',
          hint: 'الوزن الإجمالي مع التغليف'),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*')),
      ],
      style: _inputTextStyle,
      onChanged: (_) => _updateExpectedAmount(),
      validator: (v) {
        if (_purchaseMode != 'carton') return null;
        final val = double.tryParse(v ?? '') ?? 0;
        if (val <= 0) return 'أدخل الوزن الإجمالي للكرتونة';
        return null;
      },
    );
  }

  Widget _buildNetCartonField() {
    return TextFormField(
      controller: _netWeightCtrl,
      decoration: _inputDecoration('الكراتين الصافي *',
          hint: 'عدد الكراتين الصافي بعد الخصم'),
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
      ],
      style: _inputTextStyle,
      onChanged: (_) { _updateExpectedAmount(); setState(() {}); },
      validator: (v) {
        if (_purchaseMode != 'carton') return null;
        final val = int.tryParse(v ?? '') ?? 0;
        final cartonCount = (double.tryParse(_cartonCountCtrl.text) ?? 0).toInt();
        if (val <= 0) return 'أدخل عدد الكراتين الصافي';
        if (val > cartonCount) return 'لا يمكن أن يتجاوز عدد الكراتين الصافي ($cartonCount)';
        return null;
      },
    );
  }

  Widget _buildPricePerCartonField() {
    final isDark = AppTheme.isDark(context);
    return TextFormField(
      controller: _pricePerCartonCtrl,
      decoration: _inputDecoration('سعر الكرتونة الواحدة ($_currency) *',
          hint: 'سعر ثابت لكل كرتونة',
          suffix: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(_currency,
                style: TextStyle(
                    color: isDark ? AppTheme.textSecondary : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                    fontSize: 13)),
          )),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*')),
      ],
      style: _inputTextStyle,
      onChanged: (_) => _updateExpectedAmount(),
      validator: (v) {
        if (_purchaseMode != 'carton') return null;
        final val = double.tryParse(v ?? '') ?? -1;
        if (val < 0) return 'أدخل سعر الكرتونة';
        return null;
      },
    );
  }

  Widget _buildWeightField(
      TextEditingController ctrl, String label, String hint,
      {bool readOnly = false, String? Function(String?)? extraValidator}) {
    return TextFormField(
      controller: ctrl,
      readOnly: readOnly,
      decoration: _inputDecoration(label, hint: hint),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*')),
      ],
      style: readOnly ? _readOnlyTextStyle : _inputTextStyle,
      onChanged: readOnly ? null : (_) => setState(() {}),
      validator: (v) {
        if (readOnly) return null;
        final val = double.tryParse(v ?? '') ?? 0;
        if (val <= 0) return 'الوزن الإجمالي مطلوب';
        if (extraValidator != null) {
          final extra = extraValidator(v);
          if (extra != null) return extra;
        }
        return null;
      },
    );
  }

  Widget _buildRequiredWeightField(
      TextEditingController ctrl, String label, String hint) {
    return TextFormField(
      controller: ctrl,
      decoration: _inputDecoration(label, hint: hint),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*')),
      ],
      style: _inputTextStyle,
      onChanged: (_) => setState(() {}),
      validator: (v) {
        final val = double.tryParse(v ?? '') ?? 0;
        if (val <= 0) return 'أدخل سعر الشراء';
        return null;
      },
    );
  }

  Widget _buildExpectedAmountField() {
    final isDark = AppTheme.isDark(context);
    final isCarton = _purchaseMode == 'carton';
    final expectedAmount = double.tryParse(_expectedSupplierAmountCtrl.text) ?? 0;
    final expectedAmountEgp = expectedAmount * _exchangeRate;
    final currencySymbol = CropPurchaseCalculationService.formatCurrencySymbol(_currency);

    // Derived values for gross vs net comparison
    final double grossWt;
    final double netWt;
    final double effectiveUnitCost;
    final String formulaText;

    if (isCarton) {
      final cartonCount = (double.tryParse(_cartonCountCtrl.text) ?? 0).toInt();
      final pricePerCarton = double.tryParse(_pricePerCartonCtrl.text) ?? 0;
      final weightPerCarton = double.tryParse(_weightPerCartonCtrl.text) ?? 0;
      final netCartons = int.tryParse(_netWeightCtrl.text) ?? cartonCount;
      grossWt = cartonCount * weightPerCarton;
      netWt = netCartons * weightPerCarton;
      effectiveUnitCost = netWt > 0 ? (expectedAmount / netWt) : 0.0;
      formulaText = '$cartonCount كرتونة (إجمالي) × ${pricePerCarton.toStringAsFixed(2)} $currencySymbol';
    } else {
      grossWt = double.tryParse(_grossWeightCtrl.text) ?? 0;
      netWt = double.tryParse(_netWeightCtrl.text) ?? grossWt;
      final unitCost = double.tryParse(_unitCostCtrl.text) ?? 0;
      effectiveUnitCost = netWt > 0 ? (expectedAmount / netWt) : unitCost;
      formulaText = '${grossWt.toStringAsFixed(2)} كجم (إجمالي) × ${unitCost.toStringAsFixed(2)} $currencySymbol';
    }

    final hasTareWaste = grossWt > 0 && netWt > 0 && (grossWt - netWt) > 0.001;
    final tareAmount = (grossWt - netWt).clamp(0.0, double.infinity);
    final tarePercent = grossWt > 0 ? (tareAmount / grossWt) * 100 : 0.0;

    return Container(
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0F2642),
                  Color(0xFF08182B),
                ],
              )
            : null,
        color: isDark ? null : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTheme.primary.withValues(alpha: 0.35) : const Color(0xFFCBD5E1),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section 1: Financial Liability to Supplier (Gross Basis) ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: const Icon(
                  Icons.receipt_long,
                  color: AppTheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'المبلغ المستحق للمورد (حساب على الإجمالي)',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppTheme.success.withValues(alpha: 0.35),
                            ),
                          ),
                          child: const Text(
                            'دائن للمورد',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.success,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${expectedAmount.toStringAsFixed(2)} $_currency',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        color: isDark ? AppTheme.primary : Colors.black,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Formula preview pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'معادلة الحساب: $formulaText',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                          color: isDark ? AppTheme.textSecondary : Colors.black,
                        ),
                      ),
                    ),
                    if (_currency.toUpperCase() != 'EGP' && _exchangeRate > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        'المعادل بالجنيه المصري: ${expectedAmountEgp.toStringAsFixed(2)} ج.م (سعر صرف ${_exchangeRate.toStringAsFixed(2)})',
                        style: TextStyle(
                          color: isDark ? AppTheme.cyan : const Color(0xFF0369A1),
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(
                color: isDark ? const Color(0x22FFFFFF) : const Color(0xFFCBD5E1),
                height: 1),
          ),

          // ── Section 2: Physical Inventory Tracking (Net Basis) ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.cyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.cyan.withValues(alpha: 0.3),
                  ),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  color: AppTheme.cyan,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'المخزون الفعلي بالمستودع (تتبع على الصافي)',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.cyan.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppTheme.cyan.withValues(alpha: 0.35),
                            ),
                          ),
                          child: const Text(
                            'مدين مخزون',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.cyan,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildSummaryBadge(
                          icon: Icons.scale,
                          label: 'الوزن الصافي: ${netWt.toStringAsFixed(2)} كجم',
                          color: AppTheme.cyan,
                        ),
                        if (effectiveUnitCost > 0)
                          _buildSummaryBadge(
                            icon: Icons.calculate_outlined,
                            label: 'التكلفة المستوعبة: ${effectiveUnitCost.toStringAsFixed(2)} $currencySymbol/كجم صافي',
                            color: isDark ? Colors.amberAccent : const Color(0xFFB45309),
                          ),
                        if (hasTareWaste)
                          _buildSummaryBadge(
                            icon: Icons.remove_circle_outline,
                            label: 'فوارغ وشوائب: ${tareAmount.toStringAsFixed(2)} كجم (${tarePercent.toStringAsFixed(1)}%)',
                            color: AppTheme.warning,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final isDark = AppTheme.isDark(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.25 : 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isDark ? color : Colors.black,
              fontFamily: 'Cairo',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaidAmountField() {
    final isDark = AppTheme.isDark(context);
    final expectedAmount = double.tryParse(_expectedSupplierAmountCtrl.text) ?? 0;
    final paidAmount = double.tryParse(_paidAmountCtrl.text) ?? 0;
    final remaining = expectedAmount - paidAmount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _paidAmountCtrl,
          decoration: _inputDecoration(
            'المبلغ المدفوع للمورد ($_currency)',
            hint: '0',
            suffix: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(_currency,
                  style: TextStyle(
                      color: isDark ? AppTheme.textSecondary : Colors.black,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                      fontSize: 13)),
            ),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          ],
          style: _inputTextStyle,
          textAlign: TextAlign.left,
          onChanged: (_) => setState(() {}),
        ),
        if (paidAmount > 0 && remaining > 0) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              'المتبقي للمورد: ${remaining.toStringAsFixed(2)} $_currency',
              style: TextStyle(
                  color: isDark ? AppTheme.warning : const Color(0xFFB45309),
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 12),
            ),
          ),
        ],
        if (paidAmount > 0 && _currency.toUpperCase() != 'EGP' && _exchangeRate > 0) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              'بالجنيه المصري: ${(paidAmount * _exchangeRate).toStringAsFixed(2)} ج.م',
              style: TextStyle(
                  color: isDark ? AppTheme.textSecondary : Colors.black,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStationDropdown() {
    final isDark = AppTheme.isDark(context);
    return DropdownButtonFormField<int>(
      value: _selectedStationId,
      decoration: _inputDecoration('المحطة *'),
      dropdownColor: isDark ? const Color(0xFF05192D) : Colors.white,
      style: TextStyle(
          color: isDark ? Colors.white : Colors.black,
          fontWeight: FontWeight.bold,
          fontFamily: 'Cairo'),
      items: _stations
          .map((s) => DropdownMenuItem<int>(
                value: int.parse(s.id ?? '0'),
                child: Text(s.name,
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo')),
              ))
          .toList(),
      onChanged: !_canEdit ? null : (v) => setState(() => _selectedStationId = v),
      validator: (v) => v == null ? 'اختر المحطة' : null,
    );
  }

  Widget _buildPaymentSourceDropdown() {
    final isDark = AppTheme.isDark(context);
    final paid = double.tryParse(_paidAmountCtrl.text) ?? 0.0;
    if (paid <= 0) return const SizedBox.shrink();
    if (_treasuries.isEmpty && _bankAccounts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'لا توجد خزائن أو حسابات بنكية. قم بإنشائها من إعدادات النظام أولاً.',
          style: TextStyle(color: AppTheme.danger, fontFamily: 'Cairo', fontSize: 12),
        ),
      );
    }
    final supplierCurrency = _currency.toUpperCase();
    bool hasMatchingTreasury = false;
    for (final t in _treasuries) {
      final balances = t['treasury_balances'];
      if (balances is List) {
        for (final b in balances) {
          if ((b['currency']?.toString() ?? '').toUpperCase() == supplierCurrency) {
            hasMatchingTreasury = true;
            break;
          }
        }
      }
      if (hasMatchingTreasury) break;
    }
    final hasMatchingBank = _bankAccounts.any((b) =>
        (b['currency']?.toString() ?? '').toUpperCase() == supplierCurrency);
    if (!hasMatchingTreasury && !hasMatchingBank) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'لا توجد خزينة أو حساب بنكي بعملة $supplierCurrency. أضف رصيد بالعملة المطلوبة أولاً.',
          style: TextStyle(color: AppTheme.warning, fontFamily: 'Cairo', fontSize: 12),
        ),
      );
    }
    String? dropdownValue;
    if (_selectedPaymentSourceType == 'bank' && _selectedBankAccountId != null) {
      final hasBank = _bankAccounts.any((b) => b['id']?.toString() == _selectedBankAccountId.toString() && (b['currency']?.toString() ?? '').toUpperCase() == supplierCurrency);
      if (hasBank) dropdownValue = 'bank_$_selectedBankAccountId';
    } else if (_selectedPaymentSourceType == 'treasury' && _selectedTreasuryId != null && _selectedTreasuryCurrency != null) {
      if (_selectedTreasuryCurrency == supplierCurrency) {
        dropdownValue = 't_${_selectedTreasuryId}_${_selectedTreasuryCurrency}';
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Text('الخزينة/البنك *:',
              style: TextStyle(
                  color: isDark ? AppTheme.textSecondary : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                  fontSize: 14)),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: dropdownValue,
              isExpanded: true,
              dropdownColor: isDark ? const Color(0xFF0A2A4A) : Colors.white,
              style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                  fontSize: 13),
              decoration: InputDecoration(
                labelText: 'اختر الخزينة أو الحساب البنكي',
                labelStyle: TextStyle(
                    color: isDark ? AppTheme.textSecondary : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo'),
                filled: true,
                fillColor: isDark ? const Color(0x3805192D) : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              ),
              items: [
                ...() {
                  final filteredTreasuries = <DropdownMenuItem<String>>[];
                  for (final t in _treasuries) {
                    final tId = t['id']?.toString() ?? '';
                    final tName = t['name']?.toString() ?? '';
                    final balancesRaw = t['treasury_balances'];
                    final List<dynamic> balances = balancesRaw is List ? balancesRaw : [];
                    for (final b in balances) {
                      final currency = (b['currency']?.toString() ?? 'EGP').toUpperCase();
                      if (currency != supplierCurrency) continue;
                      final balance = num.tryParse(b['balance']?.toString() ?? '0')?.toDouble() ?? 0.0;
                      filteredTreasuries.add(DropdownMenuItem<String>(
                        value: 't_${tId}_$currency',
                        child: Row(
                          children: [
                            Icon(Icons.account_balance_wallet, size: 14, color: AppTheme.success),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'خزينة - $tName ($currency) — ${balance.toStringAsFixed(2)}',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : Colors.black),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ));
                    }
                  }
                  return filteredTreasuries;
                }(),
                ..._bankAccounts.where((b) {
                  final bankCurrency = (b['currency']?.toString() ?? '').toUpperCase();
                  return bankCurrency == supplierCurrency;
                }).map((b) {
                  final balance = num.tryParse(b['balance']?.toString() ?? '0')?.toDouble() ?? 0.0;
                  return DropdownMenuItem<String>(
                    value: 'bank_${b['id']}',
                    child: Row(
                      children: [
                        Icon(Icons.account_balance, size: 14, color: AppTheme.cyan),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'بنك - ${b['name']} (${(b['currency']?.toString() ?? '').toUpperCase()}) — ${balance.toStringAsFixed(2)}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
              onChanged: (v) {
                setState(() {
                  if (v != null && v.startsWith('bank_')) {
                    _selectedPaymentSourceType = 'bank';
                    _selectedBankAccountId = int.tryParse(v.replaceFirst('bank_', ''));
                    _selectedTreasuryId = null;
                    _selectedTreasuryCurrency = null;
                  } else if (v != null && v.startsWith('t_')) {
                    _selectedPaymentSourceType = 'treasury';
                    _selectedBankAccountId = null;
                    final withoutPrefix = v.replaceFirst('t_', '');
                    final lastUnderscore = withoutPrefix.lastIndexOf('_');
                    if (lastUnderscore > 0) {
                      _selectedTreasuryId = withoutPrefix.substring(0, lastUnderscore);
                      _selectedTreasuryCurrency = withoutPrefix.substring(lastUnderscore + 1);
                    } else {
                      _selectedTreasuryId = withoutPrefix;
                      _selectedTreasuryCurrency = 'EGP';
                    }
                  } else {
                    _selectedPaymentSourceType = 'treasury';
                    _selectedTreasuryId = v;
                    _selectedBankAccountId = null;
                    _selectedTreasuryCurrency = null;
                  }
                });
              },
              validator: (v) {
                if (paid > 0 && (v == null || v.isEmpty)) {
                  return 'اختر الخزينة أو الحساب البنكي';
                }
                return null;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesField() {
    return TextFormField(
      controller: _notesCtrl,
      decoration: _inputDecoration('ملاحظات', hint: 'ملاحظات إضافية...'),
      maxLines: 3,
      style: _inputTextStyle,
    );
  }

  String? get _weightValidationError {
    if (_purchaseMode != 'weight') return null;
    final gross = double.tryParse(_grossWeightCtrl.text) ?? 0;
    final net = double.tryParse(_netWeightCtrl.text) ?? 0;
    if (gross > 0 && net > gross) {
      return 'الوزن الصافي ($net) لا يمكن أن يتجاوز الوزن الإجمالي ($gross)';
    }
    return null;
  }

  String? get _cartonValidationError {
    if (_purchaseMode != 'carton') return null;
    final cartonCount = (double.tryParse(_cartonCountCtrl.text) ?? 0).toInt();
    final netCartons = int.tryParse(_netWeightCtrl.text) ?? 0;
    if (cartonCount > 0 && netCartons > cartonCount) {
      return 'الكراتين الصافي ($netCartons) لا يمكن أن يتجاوز عدد الكراتين ($cartonCount)';
    }
    return null;
  }

  Widget _buildFieldError(String? error) {
    if (error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppTheme.danger, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(
                color: AppTheme.danger,
                fontSize: 12,
                fontFamily: 'Cairo',
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _hasValidationErrors {
    return _weightValidationError != null || _cartonValidationError != null;
  }

  Widget _buildSaveButton() {
    final paidAmtForBtn = double.tryParse(_paidAmountCtrl.text) ?? 0.0;
    final isSaveDisabled = paidAmtForBtn > 0 && _selectedTreasuryId == null && _selectedBankAccountId == null;
    final disabled = _saving || _selectedProductId == null || _hasValidationErrors || isSaveDisabled;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: disabled ? null : _save,
        style: ElevatedButton.styleFrom(
          backgroundColor: isSaveDisabled ? Colors.white38 : AppTheme.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Text('حفظ',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo')),
      ),
    );
  }

  InputDecoration _inputDecoration(String label,
      {String? hint, Widget? suffix}) {
    final isDark = AppTheme.isDark(context);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: TextStyle(
          color: isDark ? AppTheme.textSecondary : Colors.black54,
          fontSize: 13,
          fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
          fontFamily: 'Cairo'),
      labelStyle: TextStyle(
          color: isDark ? AppTheme.textSecondary : Colors.black,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          fontFamily: 'Cairo'),
      suffixIcon: suffix,
      filled: true,
      fillColor: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: isDark ? AppTheme.primary : AppTheme.primary,
              width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Future<void> _save() async {
    if (!ReadOnlyGuard.check(context)) return;
    setState(() => _formSubmitted = true);
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSupplierId == null) return;

    final productName = _productNameCtrl.text.trim();
    double grossWt;
    double unitCostKg;
    double totalProductCost;
    double netWt;

    // 📦 Carton mode: compute derived values 📦
    if (_purchaseMode == 'carton') {
      final cartonCount = (double.tryParse(_cartonCountCtrl.text) ?? 0).toInt();
      final weightPerCarton = double.tryParse(_weightPerCartonCtrl.text) ?? 0;
      final pricePerCarton = double.tryParse(_pricePerCartonCtrl.text) ?? 0;
      final netCartons = int.tryParse(_netWeightCtrl.text) ?? 0;

      if (cartonCount <= 0 || weightPerCarton <= 0 || pricePerCarton < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('يرجى إدخال قيم صحيحة لعدد الكراتين ووزن الكرتونة والسعر'),
            backgroundColor: AppTheme.danger,
          ),
        );
        return;
      }

      if (netCartons <= 0 || netCartons > cartonCount) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('يرجى إدخال عدد الكراتين الصافي بشكل صحيح'),
            backgroundColor: AppTheme.danger,
          ),
        );
        return;
      }

      grossWt = cartonCount * weightPerCarton;
      netWt = netCartons * weightPerCarton;
      totalProductCost = CropPurchaseCalculationService.calculateTotalAmount(
        purchaseMethod: 'carton',
        cartonCount: cartonCount,
        pricePerCarton: pricePerCarton,
      );
      unitCostKg = netWt > 0 ? totalProductCost / netWt : 0;
    } else {
      grossWt = double.tryParse(_grossWeightCtrl.text) ?? 0;
      netWt = double.tryParse(_netWeightCtrl.text) ?? grossWt;
      final enteredPrice = double.tryParse(_unitCostCtrl.text) ?? 0;
      // Weight mode: Financial liability to supplier = Gross Weight (الوزن الإجمالي) × Price per Kg
      totalProductCost = CropPurchaseCalculationService.calculateTotalAmount(
        purchaseMethod: 'weight',
        grossWeightKg: grossWt > 0 ? grossWt : netWt,
        netWeightKg: netWt,
        pricePerKg: enteredPrice,
      );
      // Absorbed inventory unit cost per net kg (keeps double-entry inventory value balanced with supplier credit)
      unitCostKg = netWt > 0 ? (totalProductCost / netWt) : enteredPrice;
    }

    setState(() => _saving = true);

    try {
      final lot = LotReceiptModel(
        id: widget.lot?.id,
        lotNumber: widget.lot?.lotNumber ?? '',
        fruitTypeId: _selectedProductId ?? '',
        productName: productName,
        supplierId: _selectedSupplierId ?? '',
        receiptDate: _receiptDate,
        grossWeightKg: grossWt,
        netWeightKg: netWt,
        wasteWeightKg: 0,
        wastePercentage: 0,
        status: widget.lot?.status ?? 'received',
        stationId: _selectedStationId?.toString(),
        purchaseInvoiceItemId: _selectedPurchaseItemId?.toString(),
        notes: _notesCtrl.text.isNotEmpty ? _notesCtrl.text : null,
        productCostPerKg: unitCostKg,
        totalProductCost: totalProductCost,
        purchaseMode: _purchaseMode,
        cartonCount: _purchaseMode == 'carton'
            ? (double.tryParse(_cartonCountCtrl.text) ?? 0).toInt()
            : null,
        weightPerCartonKg: _purchaseMode == 'carton'
            ? double.tryParse(_weightPerCartonCtrl.text)
            : null,
        grossWeightPerCartonKg: _purchaseMode == 'carton'
            ? double.tryParse(_grossWeightPerCartonCtrl.text)
            : null,
        pricePerCarton: _purchaseMode == 'carton'
            ? double.tryParse(_pricePerCartonCtrl.text)
            : null,
        currency: _currency,
        exchangeRate: _currency.toUpperCase() == 'EGP' ? 1.0 : (_exchangeRate > 0 ? _exchangeRate : 1.0),
        paidAmount: double.tryParse(_paidAmountCtrl.text) ?? 0.0,
        paymentSourceType: _selectedPaymentSourceType ?? 'treasury',
        paymentTreasuryId: _selectedTreasuryId,
        paymentBankAccountId: _selectedBankAccountId,
        gradingResults: [],
      );

      if (widget.lot?.id != null) {
        // ── EDIT existing lot ──
        final oldLot = widget.lot!;

        // Update the lot data
        await _dao.update(widget.lot!.id!, lot, skipCostFields: oldLot.isConfirmed);

                if (oldLot.isConfirmed) {
  // Process treasury/bank payment delta (edit case)
          if (lot.paidAmount != oldLot.paidAmount ||
              lot.paymentSourceType != oldLot.paymentSourceType ||
              lot.paymentTreasuryId != oldLot.paymentTreasuryId ||
              lot.paymentBankAccountId != oldLot.paymentBankAccountId) {
            try {
              final supplierName = await _resolveSupplierName(lot.supplierId);
              await LotPaymentService().processPayment(
                lot: lot.copyWith(id: widget.lot!.id!),
                supplierName: supplierName,
                oldPaidAmount: oldLot.paidAmount,
                oldPaymentSourceType: oldLot.paymentSourceType,
                oldPaymentTreasuryId: oldLot.paymentTreasuryId,
                oldPaymentBankAccountId: oldLot.paymentBankAccountId,
              );
              debugPrint('✅ Lot payment delta processed');
            } catch (e) {
              debugPrint('⚠️ Lot payment delta processing failed (non-fatal): $e');
            }
          }
  
          
        }
// If it was already confirmed, we must re-run the side effects so the changes propagate
        if (oldLot.isConfirmed) {
          try {
            final rpcResult = await _dao.processReceiptSideEffects(
              widget.lot!.id!,
              unitCostKg: unitCostKg,
              oldStationId: oldLot.stationId,
              oldFruitTypeId: oldLot.fruitTypeId,
              oldSupplierId: oldLot.supplierId,
              isEdit: true,
            );
            // Sync station_product_batches
            if (rpcResult['station_id'] != null) {
              final supplierName = await _dao.getById(widget.lot!.id!).then((v) => v?.supplierName ?? '');
              final rpcTotalGraded = rpcResult['total_graded'] != null ? (rpcResult['total_graded'] as num).toDouble() : 0.0;
              final rpcEffectiveCostKg = (rpcResult['effective_cost_kg'] as num?)?.toDouble();
              final isCarton = lot.purchaseMode == 'carton' && (lot.cartonCount ?? 0) > 0;
              final qty = rpcTotalGraded > 0
                  ? rpcTotalGraded
                  : (isCarton
                      ? (lot.cartonCount ?? 0).toDouble()
                      : (lot.netWeightKg > 0 ? lot.netWeightKg : lot.grossWeightKg));
              final uc = isCarton
                  ? (lot.pricePerCarton ?? (qty > 0 ? lot.totalProductCost / qty : unitCostKg))
                  : (rpcEffectiveCostKg ?? (qty > 0 ? lot.totalProductCost / qty : unitCostKg));

              await _dao.syncStationProductBatch(
                stationId: rpcResult['station_id'].toString(),
                productName: rpcResult['product_name']?.toString() ?? lot.productName ?? '',
                productCode: lot.lotNumber,
                quantity: qty,
                unitCost: uc,
                supplierName: supplierName,
                exchangeRate: lot.exchangeRate,
                currency: lot.currency,
              );
            }
          } catch (e) {
            debugPrint('⚠️ processReceiptSideEffects after edit failed: $e');
            setState(() => _saving = false);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('حدث خطأ أثناء تعديل الحسابات أو المخزون: $e'),
                  backgroundColor: AppTheme.danger,
                ),
              );
            }
            return;
          }

          try {
            final packingResult = await Supabase.instance.client.rpc('rpc_update_packing_costs_for_lot', params: {
              'p_lot_id': int.parse(widget.lot!.id!),
            });
            debugPrint('✅ rpc_update_packing_costs_for_lot result: $packingResult');
          } catch (e) {
            debugPrint('⚠️ rpc_update_packing_costs_for_lot failed: $e');
          }
        }

        // Record / update cost center transaction
        try {
          final supplierName = await _resolveSupplierName(lot.supplierId);
          final isCarton = _purchaseMode == 'carton';
          final cartonCount = (double.tryParse(_cartonCountCtrl.text) ?? 0).toInt();
          final pricePerCarton = double.tryParse(_pricePerCartonCtrl.text) ?? 0;
          final double qty = isCarton ? cartonCount.toDouble() : netWt;
          final double unitPrice = isCarton ? pricePerCarton : (double.tryParse(_unitCostCtrl.text) ?? 0);
          final formulaDesc = CropPurchaseCalculationService.buildFormulaDescription(
            purchaseMethod: _purchaseMode,
            cartonCount: cartonCount,
            pricePerCarton: pricePerCarton,
            grossWeightKg: grossWt,
            netWeightKg: netWt,
            pricePerKg: unitPrice,
            totalAmount: totalProductCost,
            currency: _currency,
          );

          await ProductCostCenterSyncService.instance.recordCropPurchaseTransaction(
            sourceId: widget.lot!.id!,
            fruitTypeId: _selectedProductId ?? lot.fruitTypeId,
            cropName: productName,
            supplierId: _selectedSupplierId ?? lot.supplierId,
            supplierName: supplierName,
            quantity: qty,
            unitPrice: unitPrice,
            totalCost: totalProductCost,
            currency: _currency,
            exchangeRate: _currency.toUpperCase() == 'EGP' ? 1.0 : (_exchangeRate > 0 ? _exchangeRate : 1.0),
            date: _receiptDate,
            notes: _notesCtrl.text.isNotEmpty ? '${_notesCtrl.text} ($formulaDesc)' : formulaDesc,
            sourceType: 'lot_receipt',
          );
        } catch (e) {
          debugPrint('⚠️ Cost center transaction recording notice: $e');
        }

      } else {
        // ── INSERT new lot (draft) ──
        final result = await _dao.insert(lot);
        final lotId = result['id']?.toString() ?? '';
        final lotNumber = result['lot_number']?.toString() ?? '';
        debugPrint('✅ Draft lot created: id=$lotId, lot_number=$lotNumber');

        // Automatically record cost center transaction for this new crop purchase
        try {
          final supplierName = await _resolveSupplierName(_selectedSupplierId);
          final isCarton = _purchaseMode == 'carton';
          final cartonCount = (double.tryParse(_cartonCountCtrl.text) ?? 0).toInt();
          final pricePerCarton = double.tryParse(_pricePerCartonCtrl.text) ?? 0;
          final double qty = isCarton ? cartonCount.toDouble() : netWt;
          final double unitPrice = isCarton ? pricePerCarton : (double.tryParse(_unitCostCtrl.text) ?? 0);
          final formulaDesc = CropPurchaseCalculationService.buildFormulaDescription(
            purchaseMethod: _purchaseMode,
            cartonCount: cartonCount,
            pricePerCarton: pricePerCarton,
            grossWeightKg: grossWt,
            netWeightKg: netWt,
            pricePerKg: unitPrice,
            totalAmount: totalProductCost,
            currency: _currency,
          );

          await ProductCostCenterSyncService.instance.recordCropPurchaseTransaction(
            sourceId: lotId,
            fruitTypeId: _selectedProductId ?? '',
            cropName: productName,
            supplierId: _selectedSupplierId,
            supplierName: supplierName,
            quantity: qty,
            unitPrice: unitPrice,
            totalCost: totalProductCost,
            currency: _currency,
            exchangeRate: _currency.toUpperCase() == 'EGP' ? 1.0 : (_exchangeRate > 0 ? _exchangeRate : 1.0),
            date: _receiptDate,
            notes: _notesCtrl.text.isNotEmpty ? '${_notesCtrl.text} ($formulaDesc)' : formulaDesc,
            sourceType: 'lot_receipt',
          );
        } catch (e) {
          debugPrint('⚠️ Cost center transaction recording notice: $e');
        }
      }


      DataChangeEventBus.instance.notifySuppliersChanged();
      DataChangeEventBus.instance.notifyStationsChanged();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تم الحفظ بنجاح'),
              backgroundColor: AppTheme.success,
              duration: Duration(seconds: 2)),
        );
        context.pop(true);
      }
    } catch (e, st) {
      debugPrint('LotForm save error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('خطأ في الحفظ: $e'),
              backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String> _resolveSupplierName(String? supplierId) async {
    if (supplierId == null || supplierId.isEmpty) return '';
    try {
      final result = await Supabase.instance.client
          .from('suppliers')
          .select('name')
          .eq('id', supplierId)
          .maybeSingle();
      return result?['name']?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }
}
