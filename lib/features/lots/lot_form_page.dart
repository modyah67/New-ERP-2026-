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

import '../../data/services/cost_allocation_service.dart';
import '../../data/services/lot_payment_service.dart';
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
      final netCartons = int.tryParse(_netWeightCtrl.text) ?? 0;
      expectedAmount = cartonCount * pricePerCarton;
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
      final grossWeight = double.tryParse(_grossWeightCtrl.text) ?? 0;
      final unitCost = double.tryParse(_unitCostCtrl.text) ?? 0;
      expectedAmount = grossWeight * unitCost;
    }
    _expectedSupplierAmountCtrl.text = expectedAmount.toStringAsFixed(2);
    setState(() {});
  }

  @override
  void dispose() {
    _grossWeightCtrl.removeListener(_updateExpectedAmount);
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
        SupplierDao().getAll(),
        StationDao().getAll(),
        FruitTypeDao().getAllWithPrices(),
        Supabase.instance.client.from('treasuries').select('id,name,type,treasury_balances(currency,balance)'),
        Supabase.instance.client.from('bank_accounts').select('id,name,currency,balance'),
      ]);
      if (mounted) {
        setState(() {
          _suppliers = results[0] as List<SupplierModel>;
          _stations = results[1] as List<StationModel>;
          _fruitTypes = results[2] as List<FruitTypeModel>;
          _treasuries = List<Map<String, dynamic>>.from(results[3] as List)
              .where((t) => t['type']?.toString() != 'employee')
              .toList();
          _bankAccounts = List<Map<String, dynamic>>.from(results[4] as List);
          _loadingData = false;
        });
        if (_selectedSupplierId != null) {
          final s = _suppliers
              .where((s) => s.id == _selectedSupplierId)
              .firstOrNull;
          if (s != null) {
            _supplierController.text = s.displayName;
            _currency = s.currency;
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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.background,
                Color(0xFF0D2137),
                AppTheme.background
              ],
            ),
          ),
          child: _loadingData
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary))
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
                                      return 'الوزン الصافي ($net) لا يمكن أن يتجاوز الوزن الإجمالي ($gross)';
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
            color: const Color(0x3805192D),
            border: Border(
                bottom: BorderSide(color: AppTheme.glassBorder.withAlpha(50))),
          ),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_forward, color: Colors.white),
              onPressed: () => context.pop(),
            ),
            Text(
              widget.lot != null ? 'تعديل المحصول' : 'محصول جديد',
              style: const TextStyle(
                  color: AppTheme.textPrimary,
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0x3805192D),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: AppTheme.primary,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: const TextSpan(
            text: 'الصنف',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
              fontFamily: 'Cairo',
            ),
            children: [
              TextSpan(
                text: ' *',
                style: TextStyle(color: AppTheme.danger),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TypeAheadField<FruitTypeModel>(
          key: ValueKey('${_selectedSupplierId ?? ''}_${_selectedProductId ?? ''}'),
          controller: _productController,
          autoFlipDirection: true,
          hideOnEmpty: false,
          hideOnError: true,
          suggestionsCallback: (pattern) {
            if (pattern.isEmpty) return <FruitTypeModel>[];
            final lower = pattern.toLowerCase();
            return _filteredFruitTypes.where((ft) {
              return ft.name.toLowerCase().contains(lower) ||
                     ft.code.toLowerCase().contains(lower);
            }).toList();
          },
          emptyBuilder: (context) {
            return Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'لا يوجد صنف بهذا الاسم. ربما يكون نوع التسجيل أثناء الشراء مختلف',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
            );
          },
          itemBuilder: (context, fruitType) {
            return ListTile(
              dense: true,
              title: Text(fruitType.name,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 13)),
              trailing: Text(fruitType.currency,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppTheme.textSecondary)),
            );
          },
          onSelected: (fruitType) {
            setState(() {
              _selectedProductId = fruitType.id;
              _productNameCtrl.text = fruitType.name;
              _productController.text = fruitType.name;
            });
          },
          builder: (context, controller, focusNode) {
            return TextField(
              enabled: _canEdit,
              controller: controller,
              focusNode: focusNode,
              decoration: _inputDecoration('بحث عن الصنف *',
                  hint: 'اكتب اسم الصنف...'),
              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
            );
          },
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

  Widget _buildSupplierDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: const TextSpan(
            text: 'المورد',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
              fontFamily: 'Cairo',
            ),
            children: [
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
            if (pattern.isEmpty) return _suppliers;
            final lower = pattern.toLowerCase();
            return _suppliers.where((s) {
              return s.displayName.toLowerCase().contains(lower) ||
                  (s.supplierCode?.toLowerCase().contains(lower) ?? false) ||
                  (s.name?.toLowerCase().contains(lower) ?? false);
            }).toList();
          },
          itemBuilder: (context, supplier) {
            return ListTile(
              dense: true,
              title: Text(supplier.displayName,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 13)),
            );
          },
          onSelected: (supplier) {
            setState(() {
              final oldCurrency = _currency;
              _selectedSupplierId = supplier.id;
              _currency = supplier.currency;
              if (oldCurrency != supplier.currency) {
                _selectedProductId = null;
                _productNameCtrl.clear();
                _productController.clear();
              }
              if (_currency.toUpperCase() == 'EGP') {
                _exchangeRate = 1.0;
                _exchangeRateCtrl.text = '';
              }
            });
            _supplierController.text = supplier.displayName;
          },
          builder: (context, controller, focusNode) {
            return TextField(
              enabled: _canEdit,
              controller: controller,
              focusNode: focusNode,
              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم أو الكود...',
                hintStyle: TextStyle(
                  fontFamily: 'Cairo',
                  color: Colors.white.withValues(alpha: 0.35),
                ),
                suffixIcon: _selectedSupplierId != null && _canEdit
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          setState(() => _selectedSupplierId = null);
                          _supplierController.clear();
                        },
                      )
                    : const Icon(Icons.search,
                        size: 20, color: AppTheme.primary),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      BorderSide(color: Colors.white.withValues(alpha: 0.12)),
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
              color: const Color(0xFF0A1E38),
              shadowColor: Colors.black.withValues(alpha: 0.4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: child,
              ),
            );
          },
        ),
        if (_selectedSupplierId != null)
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
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.warning, fontFamily: 'Cairo'),
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
            style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
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

  Widget _buildDatePicker() {
    return GestureDetector(
      onTap: !_canEdit ? null : () async {
        final date = await showDatePicker(
          context: context,
          initialDate: _receiptDate,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
          builder: (context, child) => Theme(
            data: ThemeData.dark().copyWith(
              colorScheme: const ColorScheme.dark(primary: AppTheme.primary),
            ),
            child: child!,
          ),
        );
        if (date != null) setState(() => _receiptDate = date);
      },
      child: AbsorbPointer(
        child: TextFormField(
          decoration: _inputDecoration('تاريخ الشراء / التوريد',
              suffix: const Icon(Icons.calendar_today,
                  color: AppTheme.textSecondary, size: 18)),
          controller: TextEditingController(
            text:
                '${_receiptDate.year}-${_receiptDate.month.toString().padLeft(2, '0')}-${_receiptDate.day.toString().padLeft(2, '0')}',
          ),
          style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
        ),
      ),
    );
  }

  Widget _buildPurchaseModeToggle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('طريقة الشراء',
            style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFamily: 'Cairo')),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: RadioListTile<String>(
                title: const Text('بالوزن',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
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
                title: const Text('بالكرتون',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
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
      style: const TextStyle(
          color: Colors.white,
          fontFamily: 'Cairo'),
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
      style: const TextStyle(
          color: Colors.white,
          fontFamily: 'Cairo'),
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
      style: const TextStyle(
          color: Colors.white,
          fontFamily: 'Cairo'),
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
      style: const TextStyle(
          color: Colors.white,
          fontFamily: 'Cairo'),
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
    return TextFormField(
      controller: _pricePerCartonCtrl,
      decoration: _inputDecoration('سعر الكرتونة الواحدة ($_currency) *',
          hint: 'سعر ثابت لكل كرتونة',
          suffix: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(_currency,
                style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontFamily: 'Cairo',
                    fontSize: 13)),
          )),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*')),
      ],
      style: const TextStyle(
          color: Colors.white,
          fontFamily: 'Cairo'),
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
      style: TextStyle(
        color: readOnly ? AppTheme.textSecondary : Colors.white,
        fontFamily: 'Cairo',
      ),
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
      style: const TextStyle(
          color: Colors.white,
          fontFamily: 'Cairo'),
      onChanged: (_) => setState(() {}),
      validator: (v) {
        final val = double.tryParse(v ?? '') ?? 0;
        if (val <= 0) return 'أدخل سعر الشراء';
        return null;
      },
    );
  }

  Widget _buildExpectedAmountField() {
    final isCarton = _purchaseMode == 'carton';
    final expectedAmount = double.tryParse(_expectedSupplierAmountCtrl.text) ?? 0;
    final expectedAmountEgp = expectedAmount * _exchangeRate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _expectedSupplierAmountCtrl,
          decoration: _inputDecoration(
            'المبلغ المتوقع للمورد ($_currency)',
            hint: isCarton ? 'عدد الكراتين × سعر الكرتونة' : 'الوزن الإجمالي × سعر الشراء',
            suffix: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(_currency,
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontFamily: 'Cairo',
                      fontSize: 13)),
            ),
          ),
          readOnly: true,
          style: const TextStyle(
              color: AppTheme.primary,
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: 14),
          enabled: false,
          textAlign: TextAlign.left,
        ),
        if (_currency.toUpperCase() != 'EGP' && _exchangeRate > 0) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              'بالجنيه المصري: ${expectedAmountEgp.toStringAsFixed(2)} ج.م',
              style: const TextStyle(
                  color: AppTheme.cyan,
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPaidAmountField() {
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
                      color: AppTheme.textSecondary,
                      fontFamily: 'Cairo',
                      fontSize: 13)),
            ),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          ],
          style: const TextStyle(
              color: Colors.white,
              fontFamily: 'Cairo',
              fontSize: 14),
          textAlign: TextAlign.left,
          onChanged: (_) => setState(() {}),
        ),
        if (paidAmount > 0 && remaining > 0) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              'المتبقي للمورد: ${remaining.toStringAsFixed(2)} $_currency',
              style: const TextStyle(
                  color: AppTheme.warning,
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
              style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontFamily: 'Cairo',
                  fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStationDropdown() {
    return DropdownButtonFormField<int>(
      value: _selectedStationId,
      decoration: _inputDecoration('المحطة *'),
      dropdownColor: const Color(0xFF05192D),
      style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
      items: _stations
          .map((s) => DropdownMenuItem<int>(
                value: int.parse(s.id ?? '0'),
                child:
                    Text(s.name, style: const TextStyle(fontFamily: 'Cairo')),
              ))
          .toList(),
      onChanged: !_canEdit ? null : (v) => setState(() => _selectedStationId = v),
      validator: (v) => v == null ? 'اختر المحطة' : null,
    );
  }

  Widget _buildPaymentSourceDropdown() {
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
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Cairo',
                  fontSize: 14)),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: dropdownValue,
              isExpanded: true,
              dropdownColor: const Color(0xFF0A2A4A),
              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
              decoration: InputDecoration(
                labelText: 'اختر الخزينة أو الحساب البنكي',
                labelStyle: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'),
                filled: true,
                fillColor: const Color(0x3805192D),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.glassBorder)),
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
                                style: const TextStyle(fontSize: 12),
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
                            style: const TextStyle(fontSize: 12),
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
      style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
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
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: const TextStyle(
          color: AppTheme.textSecondary, fontSize: 13, fontFamily: 'Cairo'),
      labelStyle: const TextStyle(
          color: AppTheme.textSecondary, fontSize: 14, fontFamily: 'Cairo'),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0x1AFFFFFF),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
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
      totalProductCost = cartonCount * pricePerCarton;
      unitCostKg = netWt > 0 ? totalProductCost / netWt : 0;
    } else {
      grossWt = double.tryParse(_grossWeightCtrl.text) ?? 0;
      netWt = double.tryParse(_netWeightCtrl.text) ?? grossWt;
      final enteredPrice = double.tryParse(_unitCostCtrl.text) ?? 0;
      totalProductCost = grossWt * enteredPrice;
      unitCostKg = netWt > 0 ? totalProductCost / netWt : 0;
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

      } else {
        // ── INSERT new lot (draft) ──
        final result = await _dao.insert(lot);
        final lotId = result['id']?.toString() ?? '';
        final lotNumber = result['lot_number']?.toString() ?? '';
        debugPrint('✅ Draft lot created: id=$lotId, lot_number=$lotNumber');

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
