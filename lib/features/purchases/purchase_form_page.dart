// lib/features/purchases/purchase_form_page.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/widgets/read_only_guard.dart';
import '../../data/services/currency_conversion_service.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/item_model.dart';
import '../../data/models/purchase_model.dart';
import '../../data/models/station_model.dart';
import 'purchase_cubit.dart';
import 'purchase_state.dart';

import '../../ui/widgets/app_text_field.dart';
import '../../ui/widgets/app_search_field.dart';

class _PurchaseLineController {
  final TextEditingController searchController = TextEditingController();
  final TextEditingController codeController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController quantityController =
      TextEditingController(text: '0');
  final TextEditingController purchasePriceController = TextEditingController();
  final TextEditingController exchangeRateController =
      TextEditingController();
  String unit = ' قطعة';
  String currency = 'EGP';
  String? existingItemId;
  int? stationId;
  String costCenterId = 'packing_station';
  final ValueNotifier<double> totalPriceRx = ValueNotifier(0.0);
  VoidCallback? _onChanged;

  set onChanged(VoidCallback? callback) => _onChanged = callback;

  final FocusNode searchFocus = FocusNode();
  final FocusNode codeFocus = FocusNode();
  final FocusNode nameFocus = FocusNode();
  final FocusNode quantityFocus = FocusNode();
  final FocusNode purchasePriceFocus = FocusNode();

  void setupKeyEvents({
    required void Function(int index) onArrowDown,
    required void Function(int index) onNextOrAddLine,
    required void Function(_PurchaseLineController line, String query)
        onSearchSelect,
    required int index,
  }) {
    searchFocus.onKeyEvent = (node, event) {
      if (event is KeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          final q = searchController.text.trim();
          onSearchSelect(this, q);
          Future.microtask(() => quantityFocus.requestFocus());
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          onArrowDown(index);
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    };

    quantityFocus.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.enter) {
        Future.microtask(() => purchasePriceFocus.requestFocus());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    purchasePriceFocus.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.enter) {
        onNextOrAddLine(index);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  double get quantity => double.tryParse(quantityController.text) ?? 0;
  double get purchasePrice =>
      double.tryParse(purchasePriceController.text) ?? 0;
  double get exchangeRate => double.tryParse(exchangeRateController.text) ?? 1.0;
  double get totalPrice => AppUtils.roundDouble(quantity * purchasePrice);
  double get totalPriceEgp => AppUtils.roundDouble(CurrencyConversionService.instance.toBase(totalPrice, currency, exchangeRate));

  void _refreshTotal() {
    totalPriceRx.value = AppUtils.roundDouble(totalPrice);
    _onChanged?.call();
  }

  void initListeners() {
    quantityController.addListener(_refreshTotal);
    purchasePriceController.addListener(_refreshTotal);
    exchangeRateController.addListener(_refreshTotal);
  }

  void loadItem(ItemModel item, {int? defaultStationId}) {
    codeController.text = item.code;
    nameController.text = item.name;
    if (item.costPrice > 0) {
      purchasePriceController.text = item.costPrice.toStringAsFixed(2);
    } else if (item.pricePerUnit > 0) {
      purchasePriceController.text = item.pricePerUnit.toStringAsFixed(2);
    }
    existingItemId = item.id;
    if (item.unit.isNotEmpty) {
      unit = item.unit;
    }
    if (stationId == null && defaultStationId != null) {
      stationId = defaultStationId;
    }
    if (quantityController.text.trim().isEmpty || quantityController.text.trim() == '0') {
      quantityController.text = '1';
    }
    searchController.text = '${item.code} - ${item.name}';
    _refreshTotal();
  }

  void clearItem() {
    codeController.clear();
    nameController.clear();
    existingItemId = null;
    searchController.clear();
    purchasePriceController.clear();
    _refreshTotal();
  }

  PurchaseLineData toData() {
    return PurchaseLineData(
      code: codeController.text.trim(),
      name: nameController.text.trim().isEmpty
          ? codeController.text.trim()
          : nameController.text.trim(),
      quantity: quantity,
      purchasePrice: purchasePrice,
      unit: unit,
      existingItemId: existingItemId?.toString(),
      stationId: stationId?.toString(),
      exchangeRate: exchangeRate,
      costCenterId: costCenterId,
    );
  }

  void dispose() {
    quantityController.removeListener(_refreshTotal);
    purchasePriceController.removeListener(_refreshTotal);
    exchangeRateController.removeListener(_refreshTotal);
    totalPriceRx.dispose();
    searchController.dispose();
    codeController.dispose();
    nameController.dispose();
    quantityController.dispose();
    purchasePriceController.dispose();
    exchangeRateController.dispose();
    searchFocus.dispose();
    codeFocus.dispose();
    nameFocus.dispose();
    quantityFocus.dispose();
    purchasePriceFocus.dispose();
  }
}

class PurchaseFormPage extends StatefulWidget {
  final bool viewOnly;
  const PurchaseFormPage({super.key, this.viewOnly = false});

  @override
  State<PurchaseFormPage> createState() => _PurchaseFormPageState();
}

class _PurchaseFormPageState extends State<PurchaseFormPage> {
  final List<_PurchaseLineController> _controllers = [];
  final supplierSearchController = TextEditingController();
  final invoiceExchangeRateController = TextEditingController();
  final subtotalNotifier = ValueNotifier<double>(0.0);
  final subtotalEgpNotifier = ValueNotifier<double>(0.0);
  final notesController = TextEditingController();
  final paidAmountController = TextEditingController(text: '0');
  final notesFocusNode = FocusNode();
  final paidAmountFocusNode = FocusNode();
  final supplierFocusNode = FocusNode();
  String? _selectedTreasuryId;
  String? _selectedPaymentSourceType;
  int? _selectedBankAccountId;
  String? _selectedTreasuryCurrency; // عملة الخزينة المختارة
  bool _initialized = false;

  List<SupplierModel> _suppliers = [];
  List<ItemModel> _allItems = [];
  List<StationModel> _stations = [];

  @override
  void initState() {
    super.initState();
    paidAmountController.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _initForm());
  }

  void _initForm() {
    if (_initialized) return;
    _initialized = true;

    final cubit = context.read<PurchaseCubit>();
    final fs = cubit.formState;

    // Cache lists locally so TypeAheadField doesn't reset on cubit state changes
    final state = cubit.state;
    if (state is PurchaseLoaded) {
      _suppliers = state.suppliers.where((s) => s.isPackagingSupplier).toList();
      if (fs.isEditing && fs.selectedSupplier != null && !_suppliers.any((s) => s.id == fs.selectedSupplier!.id)) {
        _suppliers.insert(0, fs.selectedSupplier!);
      }
      _allItems = state.allItems;
      _stations = state.stations;
    }

    if (fs.isEditing && fs.selectedSupplier != null) {
      supplierSearchController.text = '${fs.selectedSupplier!.supplierCode} - ${fs.selectedSupplier!.name}';
      paidAmountController.text = fs.paidAmount.toStringAsFixed(2);
      _selectedTreasuryId = fs.paymentTreasuryId;
      _selectedPaymentSourceType = fs.paymentSourceType ?? 'treasury';
      _selectedBankAccountId = fs.paymentBankAccountId;
      if (fs.purchaseLines.isNotEmpty) {
        final firstRate = fs.purchaseLines.first.exchangeRate;
        if (firstRate > 0) {
          invoiceExchangeRateController.text = firstRate.toStringAsFixed(2);
        }
      } else if (fs.exchangeRate > 0) {
        invoiceExchangeRateController.text = fs.exchangeRate.toStringAsFixed(2);
      }
      cubit.selectSupplier(fs.selectedSupplier!, initialCurrency: fs.invoiceCurrency);

      for (final line in fs.purchaseLines) {
        final ctrl = _PurchaseLineController();
        ctrl.searchController.text = line.name.isNotEmpty ? '${line.code} - ${line.name}' : line.code;
        ctrl.codeController.text = line.code;
        ctrl.nameController.text = line.name;
        ctrl.quantityController.text = line.quantity.toStringAsFixed(0);
        ctrl.purchasePriceController.text = line.purchasePrice.toStringAsFixed(2);
        ctrl.exchangeRateController.text = line.exchangeRate.toStringAsFixed(2);
        ctrl.unit = line.unit;
        ctrl.currency = fs.invoiceCurrency;
        ctrl.existingItemId = line.existingItemId;
        ctrl.stationId = int.tryParse(line.stationId ?? '');
        ctrl.costCenterId = line.costCenterId ?? 'packing_station';
        ctrl.onChanged = _refreshSubtotal;
        ctrl.initListeners();
        ctrl.totalPriceRx.value = ctrl.totalPrice;

        final idx = _controllers.length;
        ctrl.setupKeyEvents(
          onArrowDown: (i) {
            if (i < _controllers.length - 1) {
              Future.microtask(() => _controllers[i + 1].searchFocus.requestFocus());
            } else {
              _addLine();
              Future.delayed(const Duration(milliseconds: 50), () {
                if (_controllers.isNotEmpty) _controllers.last.searchFocus.requestFocus();
              });
            }
          },
          onNextOrAddLine: (i) {
            if (i < _controllers.length - 1) {
              Future.microtask(() => _controllers[i + 1].searchFocus.requestFocus());
            } else {
              _addLine();
              Future.delayed(const Duration(milliseconds: 50), () {
                if (_controllers.isNotEmpty) _controllers.last.searchFocus.requestFocus();
              });
            }
          },
          onSearchSelect: (ctrl, query) {
            if (query.isEmpty) return;
            final matches = _getFilteredItems(query);
            if (matches.isNotEmpty) {
              int? defaultStation;
              if (_stations.isNotEmpty) {
                defaultStation = int.tryParse(_stations.first.id ?? '');
              }
              ctrl.loadItem(matches.first, defaultStationId: defaultStation);
              setState(() {});
            }
          },
          index: idx,
        );

        _controllers.add(ctrl);
      }
      _refreshSubtotal();
      setState(() {});
    } else {
      _addLine();
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    supplierSearchController.dispose();
    invoiceExchangeRateController.dispose();
    subtotalNotifier.dispose();
    subtotalEgpNotifier.dispose();
    notesController.dispose();
    paidAmountController.dispose();
    notesFocusNode.dispose();
    paidAmountFocusNode.dispose();
    supplierFocusNode.dispose();
    super.dispose();
  }

  void _addLine() {
    final cubit = context.read<PurchaseCubit>();
    final line = _PurchaseLineController();
    line.currency = cubit.formState.invoiceCurrency;
    if (invoiceExchangeRateController.text.isNotEmpty) {
      line.exchangeRateController.text = invoiceExchangeRateController.text;
    }
    if (_stations.isNotEmpty && line.stationId == null) {
      line.stationId = int.tryParse(_stations.first.id ?? '');
    }
    line.onChanged = _refreshSubtotal;
    line.initListeners();

    final index = _controllers.length;
    line.setupKeyEvents(
      onArrowDown: (idx) {
        if (idx < _controllers.length - 1) {
          Future.microtask(
              () => _controllers[idx + 1].searchFocus.requestFocus());
        } else {
          _addLine();
          Future.delayed(const Duration(milliseconds: 50), () {
            if (_controllers.isNotEmpty) {
              _controllers.last.searchFocus.requestFocus();
            }
          });
        }
      },
      onNextOrAddLine: (idx) {
        if (idx < _controllers.length - 1) {
          Future.microtask(
              () => _controllers[idx + 1].searchFocus.requestFocus());
        } else {
          _addLine();
          Future.delayed(const Duration(milliseconds: 50), () {
            if (_controllers.isNotEmpty) {
              _controllers.last.searchFocus.requestFocus();
            }
          });
        }
      },
      onSearchSelect: (ctrl, query) {
        if (query.isEmpty) return;
        final matches = _getFilteredItems(query);
        if (matches.isNotEmpty) {
          int? defaultStation;
          if (_stations.isNotEmpty) {
            defaultStation = int.tryParse(_stations.first.id ?? '');
          }
          ctrl.loadItem(matches.first, defaultStationId: defaultStation);
          setState(() {});
        }
      },
      index: index,
    );

    _controllers.add(line);
    _refreshSubtotal();
    setState(() {});
  }

  void _removeLine(int index) {
    if (index < _controllers.length) {
      final disposed = _controllers.removeAt(index);
      _refreshSubtotal();
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        disposed.dispose();
      });
    }
  }

  void _refreshSubtotal() {
    final newSubtotal = AppUtils.roundDouble(
      _controllers.fold(0.0, (s, l) => s + l.totalPrice),
    );
    subtotalNotifier.value = newSubtotal;
    final newSubtotalEgp = AppUtils.roundDouble(
      _controllers.fold(0.0, (s, l) => s + l.totalPriceEgp),
    );
    subtotalEgpNotifier.value = newSubtotalEgp;
  }

  String _getCurrencyLabel(String cur) {
    switch (cur.toUpperCase()) {
      case 'USD':
        return 'دولار أمريكي';
      case 'EUR':
        return 'يورو أوروبي';
      case 'GBP':
        return 'جنيه إسترليني';
      case 'EGP':
        return 'جنيه مصري';
      case 'SAR':
        return 'ريال سعودي';
      case 'AED':
        return 'درهم إماراتي';
      default:
        return cur;
    }
  }

  Future<void> _onInvoiceCurrencyChanged(String newCurrency, {bool syncCubit = true}) async {
    final cubit = context.read<PurchaseCubit>();
    double rate = 1.0;
    if (newCurrency.toUpperCase() != 'EGP') {
      try {
        final fetchedRate = await CurrencyConversionService.instance.getRate(newCurrency);
        if (fetchedRate > 0) rate = fetchedRate;
      } catch (e) {
        debugPrint('⚠️ Error fetching spot rate for $newCurrency: $e');
      }
      invoiceExchangeRateController.text = rate.toStringAsFixed(2);
    } else {
      invoiceExchangeRateController.text = '1.00';
    }

    if (syncCubit) {
      cubit.setInvoiceCurrency(newCurrency, rate: rate);
    }

    final curUpper = newCurrency.trim().toUpperCase();
    for (final c in _controllers) {
      c.currency = newCurrency;
      c.exchangeRateController.text = invoiceExchangeRateController.text;

      // Auto-clear item if its registered currency does not match the new invoice currency
      if (c.existingItemId != null) {
        final it = _allItems.cast<ItemModel?>().firstWhere(
              (item) => item?.id == c.existingItemId,
              orElse: () => null,
            );
        if (it != null) {
          final itCur = it.currency.trim().toUpperCase();
          final mismatch = curUpper == 'EGP'
              ? (itCur != 'EGP' && itCur.isNotEmpty)
              : (itCur != curUpper);
          if (mismatch) {
            c.clearItem();
          }
        }
      }
    }
    _refreshSubtotal();
    if (mounted) setState(() {});
  }

  Future<void> _refreshExchangeRate() async {
    final cubit = context.read<PurchaseCubit>();
    final cur = cubit.formState.invoiceCurrency;
    if (cur.toUpperCase() == 'EGP') return;
    try {
      final fetchedRate = await CurrencyConversionService.instance.getRate(cur);
      if (fetchedRate > 0) {
        invoiceExchangeRateController.text = fetchedRate.toStringAsFixed(2);
        cubit.updateExchangeRate(fetchedRate);
        for (final c in _controllers) {
          c.exchangeRateController.text = invoiceExchangeRateController.text;
        }
        _refreshSubtotal();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم تحديث سعر الصرف الحي: 1 $cur = ${fetchedRate.toStringAsFixed(2)} ج.م',
                  style: const TextStyle(fontFamily: 'Cairo')),
              backgroundColor: AppTheme.success,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching live exchange rate: $e');
    }
  }

  Future<void> _selectSupplier(SupplierModel s) async {
    final cubit = context.read<PurchaseCubit>();
    supplierSearchController.text = '${s.supplierCode} - ${s.name}';
    
    // Auto-determine initial invoice currency
    String targetCurrency = 'EGP';
    if (s.supportsMultiCurrency) {
      if (s.packagingCurrency.isNotEmpty && s.supportedCurrencies.contains(s.packagingCurrency)) {
        targetCurrency = s.packagingCurrency;
      } else if (s.supportedCurrencies.isNotEmpty) {
        targetCurrency = s.supportedCurrencies.first;
      }
    } else {
      targetCurrency = (s.currency.isNotEmpty && s.currency != 'MULTI') ? s.currency : 'EGP';
    }

    cubit.selectSupplier(s, initialCurrency: targetCurrency);
    await _onInvoiceCurrencyChanged(targetCurrency, syncCubit: false);

    // Auto-clear item if supplier binding is restricted
    for (final c in _controllers) {
      if (c.existingItemId != null) {
        final it = _allItems.cast<ItemModel?>().firstWhere(
              (item) => item?.id == c.existingItemId,
              orElse: () => null,
            );
        if (it != null && it.supplierId != null && it.supplierId!.isNotEmpty && it.supplierId != s.id) {
          c.clearItem();
        }
      }
    }

    if (_controllers.isNotEmpty) {
      _controllers.first.codeFocus.requestFocus();
    }
    if (mounted) setState(() {});
  }

  void _resetForm() {
    final old = List<_PurchaseLineController>.from(_controllers);

    _controllers.clear();
    supplierSearchController.clear();
    invoiceExchangeRateController.clear();
    subtotalNotifier.value = 0.0;
    notesController.clear();
    paidAmountController.text = '0';
    context.read<PurchaseCubit>().formState =
        context.read<PurchaseCubit>().formState.copyWith(
              clearSelectedSupplier: true,
              clearEditingPurchaseId: true,
              invoiceCurrency: 'EGP',
              exchangeRate: 1.0,
            );
    _initialized = false;
    _addLine();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in old) {
        c.dispose();
      }
    });
  }

  Widget _buildCurrencyAndExchangeRateSection(BuildContext context, {required bool isMobile}) {
    final cubit = context.watch<PurchaseCubit>();
    final supplier = cubit.formState.selectedSupplier;
    if (supplier == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMulti = supplier.supportsMultiCurrency;
    final allowedCurrencies = isMulti
        ? (supplier.supportedCurrencies.isNotEmpty ? supplier.supportedCurrencies : ['EGP', 'USD', 'EUR'])
        : [((supplier.currency.isNotEmpty && supplier.currency != 'MULTI') ? supplier.currency : 'EGP')];

    final currentCurrency = allowedCurrencies.contains(cubit.formState.invoiceCurrency)
        ? cubit.formState.invoiceCurrency
        : allowedCurrencies.first;

    final isForeign = currentCurrency.toUpperCase() != 'EGP';

    final currencySelectorWidget = isMulti
        ? DropdownButtonFormField<String>(
            value: currentCurrency,
            dropdownColor: isDark ? const Color(0xFF0A2A4A) : Colors.white,
            style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              labelText: 'عملة الفاتورة *',
              labelStyle: TextStyle(
                  color: isDark ? AppTheme.textSecondary : Colors.black87,
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold),
              prefixIcon: const Icon(Icons.currency_exchange, size: 18, color: AppTheme.primary),
              filled: true,
              fillColor: isDark ? const Color(0x3805192D) : Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: allowedCurrencies.map((cur) => DropdownMenuItem(
              value: cur,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(cur,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                          color: isDark ? Colors.white : Colors.black)),
                  const SizedBox(width: 8),
                  Text('(${_getCurrencyLabel(cur)})',
                      style: TextStyle(
                          fontSize: 11,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                          fontFamily: 'Cairo',
                          fontWeight: isDark ? FontWeight.normal : FontWeight.bold)),
                ],
              ),
            )).toList(),
            onChanged: (newCur) {
              if (newCur != null && newCur != cubit.formState.invoiceCurrency) {
                _onInvoiceCurrencyChanged(newCur);
              }
            },
          )
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.primary.withValues(alpha: 0.1) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: isDark ? AppTheme.primary.withValues(alpha: 0.3) : const Color(0xFFCBD5E1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline, size: 16, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'عملة الفاتورة: $currentCurrency (${_getCurrencyLabel(currentCurrency)})',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
              ],
            ),
          );

    final exchangeRateWidget = isForeign
        ? AppTextField(
            label: 'سعر الصرف (مقابل EGP)',
            controller: invoiceExchangeRateController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            isRequired: true,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*')),
            ],
            hint: 'أدخل سعر الصرف...',
            prefixIcon: const Icon(Icons.trending_up, size: 18, color: AppTheme.warning),
            suffixIcon: IconButton(
              icon: const Icon(Icons.sync, size: 18, color: AppTheme.primary),
              tooltip: 'تحديث سعر الصرف الحي',
              onPressed: _refreshExchangeRate,
            ),
            onChanged: (val) {
              final rate = double.tryParse(val) ?? 1.0;
              cubit.updateExchangeRate(rate);
              for (final line in _controllers) {
                line.exchangeRateController.text = val;
              }
              _refreshSubtotal();
            },
          )
        : null;

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          currencySelectorWidget,
          if (exchangeRateWidget != null) ...[
            const SizedBox(height: 8),
            exchangeRateWidget,
          ],
        ],
      );
    } else {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: isForeign ? 5 : 10,
              child: currencySelectorWidget,
            ),
            if (isForeign && exchangeRateWidget != null) ...[
              const SizedBox(width: 12),
              Expanded(
                flex: 5,
                child: exchangeRateWidget,
              ),
            ],
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.read<PurchaseCubit>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEditing = c.formState.isEditing;
    final isMobile = MediaQuery.of(context).size.width < 600;

    final state = c.state;
    if (state is PurchaseLoaded) {
      _suppliers = state.suppliers.where((s) => s.isPackagingSupplier).toList();
      _allItems = state.allItems;
      _stations = state.stations;
    }

    final paidAmtForBtn = double.tryParse(paidAmountController.text) ?? 0.0;
    final isSaveDisabled = ReadOnlyGuard.isReadOnly ||
        (paidAmtForBtn > 0 && _selectedTreasuryId == null && _selectedBankAccountId == null);

    return BlocListener<PurchaseCubit, PurchaseState>(
      listener: (context, state) {
        if (state is PurchaseFormSaved) {
          _resetForm();
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? null : const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: isDark ? null : Colors.white,
          elevation: 0,
          iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
          title: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(isEditing ? 'تعديل مشتريات' : 'مشتريات جديدة',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold)),
          ),
          actions: [
            if (!widget.viewOnly)
              IconButton(
              icon: Icon(Icons.save,
                  color: isSaveDisabled
                      ? (isDark ? Colors.white38 : Colors.black26)
                      : (isDark ? Colors.white : Colors.black),
                  size: 20),
              tooltip: isEditing ? 'تحديث' : 'حفظ',
              onPressed: isSaveDisabled ? null : () async {
                if (!await ReadOnlyGuard.checkAsync(context)) return;
                final lines = _controllers.map((l) => l.toData()).toList();
                final hasNullStation = lines.any((l) => l.stationId == null && l.quantity > 0 && l.code.isNotEmpty);
                if (hasNullStation) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('يجب اختيار المخزن لكل صنف', textDirection: TextDirection.rtl),
                      backgroundColor: AppTheme.danger,
                    ),
                  );
                  return;
                }

                final invoiceCurrency = c.formState.invoiceCurrency;
                final isForeign = invoiceCurrency.toUpperCase() != 'EGP';
                final hasInvalidExchangeRate = isForeign && lines.any((l) => l.exchangeRate <= 0 && l.quantity > 0 && l.code.isNotEmpty);
                if (hasInvalidExchangeRate) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('يجب إدخال سعر الصرف بشكل صحيح لكل صنف', textDirection: TextDirection.rtl),
                      backgroundColor: AppTheme.danger,
                    ),
                  );
                  return;
                }

                final paidAmount = double.tryParse(paidAmountController.text) ?? 0.0;

                // ── Balance validation: prevent payment exceeding available funds ──
                if (paidAmount > 0) {
                  final curInvoiceCurrency = invoiceCurrency.toUpperCase();
                  double availableBalance = 0;
                  String sourceName = '';
                  bool hasSource = false;

                  if (_selectedPaymentSourceType == 'treasury' && _selectedTreasuryId != null) {
                    for (final t in c.treasuries) {
                      if (t['id']?.toString() == _selectedTreasuryId) {
                        sourceName = t['name']?.toString() ?? '';
                        final balances = t['treasury_balances'];
                        if (balances is List) {
                          for (final b in balances) {
                            if ((b['currency']?.toString() ?? '').toUpperCase() == curInvoiceCurrency) {
                              availableBalance = num.tryParse(b['balance']?.toString() ?? '0')?.toDouble() ?? 0.0;
                              hasSource = true;
                              break;
                            }
                          }
                        }
                        break;
                      }
                    }
                  } else if (_selectedPaymentSourceType == 'bank' && _selectedBankAccountId != null) {
                    for (final b in c.bankAccounts) {
                      if (b['id']?.toString() == _selectedBankAccountId.toString()) {
                        sourceName = b['name']?.toString() ?? '';
                        availableBalance = num.tryParse(b['balance']?.toString() ?? '0')?.toDouble() ?? 0.0;
                        hasSource = true;
                        break;
                      }
                    }
                  }

                  if (hasSource && paidAmount > availableBalance) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'المبلغ المدفوع ($paidAmount $curInvoiceCurrency) أكبر من الرصيد المتاح في "$sourceName" ($availableBalance $curInvoiceCurrency). قم بشحن الخزينة أو الحساب أولاً.',
                          textDirection: TextDirection.rtl,
                        ),
                        backgroundColor: AppTheme.danger,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                    return;
                  }
                }

                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const Center(
                    child: Card(
                      color: Color(0xCC05192D),
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: AppTheme.primary),
                            SizedBox(height: 16),
                            Text('جاري حفظ المشتريات...', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );

                bool success = false;
                try {
                  if (isEditing) {
                    success = await c.updatePurchase(
                      purchaseId: c.formState.editingPurchaseId!,
                      lines: lines,
                      paidAmount: paidAmount,
                      notes: notesController.text,
                      paymentTreasuryId: _selectedPaymentSourceType == 'treasury' ? _selectedTreasuryId : null,
                      paymentSourceType: _selectedPaymentSourceType ?? 'treasury',
                      paymentBankAccountId: _selectedPaymentSourceType == 'bank' ? _selectedBankAccountId : null,
                    );
                  } else {
                    success = await c.savePurchase(
                      lines: lines,
                      paidAmount: paidAmount,
                      notes: notesController.text,
                      paymentTreasuryId: _selectedPaymentSourceType == 'treasury' ? _selectedTreasuryId : null,
                      paymentSourceType: _selectedPaymentSourceType ?? 'treasury',
                      paymentBankAccountId: _selectedPaymentSourceType == 'bank' ? _selectedBankAccountId : null,
                    );
                  }
                } finally {
                  if (mounted) Navigator.of(context, rootNavigator: true).pop();
                }

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        success
                            ? (isEditing ? 'تم تحديث المشتريات بنجاح' : 'تم حفظ المشتريات بنجاح')
                            : 'فشل الحفظ',
                        textDirection: TextDirection.rtl,
                      ),
                      backgroundColor: success ? AppTheme.success : AppTheme.danger,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                  if (success && mounted) {
                    context.go('/purchases');
                  }
                }
              },
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 12 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isMobile)
                Column(
                  children: [
                    Builder(
                      builder: (context) {
                        return AppSearchField<SupplierModel>(
                          label: 'المورد',
                          controller: supplierSearchController,
                          focusNode: supplierFocusNode,
                          isRequired: true,
                          hint: 'ابحث عن مورد...',
                          prefixIcon:
                              const Icon(Icons.person_outline, size: 18),
                          highlightColor:
                              AppTheme.primary.withValues(alpha: 0.5),
                          suggestionsCallback: (pattern) {
                            final packagingSuppliers = _suppliers.where((s) => s.isPackagingSupplier).toList();
                            if (pattern.isEmpty) return packagingSuppliers;
                            final p = pattern.toLowerCase();
                            return packagingSuppliers
                                .where((s) =>
                                    s.name.toLowerCase().contains(p) ||
                                    s.supplierCode.toLowerCase().contains(p))
                                .toList();
                          },
                          itemBuilder: (context, supplier) {
                            return ListTile(
                              tileColor: isDark ? null : Colors.white,
                              title: Text(supplier.name,
                                  style: TextStyle(
                                      color: isDark ? Colors.white : Colors.black,
                                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                      fontFamily: 'Cairo',
                                      fontSize: 15)),
                              subtitle: Text(supplier.supplierCode,
                                  style: TextStyle(
                                      color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                      fontFamily: 'Cairo',
                                      fontSize: 13)),
                            );
                          },
                          onSelected: (s) {
                            _selectSupplier(s);
                          },
                          onSubmitted: (val) {},
                        );
                      },
                    ),
                    _buildCurrencyAndExchangeRateSection(context, isMobile: true),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('التاريخ',
                                  style: TextStyle(
                                      color: isDark ? AppTheme.textSecondary : Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo',
                                      fontSize: 14)),
                              const SizedBox(height: 6),
                              BlocBuilder<PurchaseCubit, PurchaseState>(
                                builder: (context, state) {
                                  final purchaseDate = c.formState.purchaseDate;
                                  return InkWell(
                                    onTap: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: purchaseDate,
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime(2030),
                                      );
                                      if (picked != null) {
                                        c.formState = c.formState
                                            .copyWith(purchaseDate: picked);
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 14),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                            color: isDark ? const Color(0xFFBDBDBD) : const Color(0xFFCBD5E1)),
                                        borderRadius: BorderRadius.circular(8),
                                        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.calendar_today,
                                              size: 16,
                                              color: isDark ? AppTheme.textSecondary : Colors.black87),
                                          const SizedBox(width: 8),
                                          Text(AppUtils.formatDate(purchaseDate),
                                              style: TextStyle(
                                                  color: isDark ? Colors.white : Colors.black,
                                                  fontWeight: FontWeight.bold,
                                                  fontFamily: 'Cairo',
                                                  fontSize: 15)),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('رقم المشتريات',
                                  style: TextStyle(
                                      color: isDark ? AppTheme.textSecondary : Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo',
                                      fontSize: 14)),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isDark ? AppTheme.background : Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: isDark ? AppTheme.border : const Color(0xFFCBD5E1)),
                                ),
                                child: Center(
                                  child: Text(
                                    c.formState.nextPurchaseNumber
                                        .toString()
                                        .padLeft(6, '0'),
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        fontFamily: 'Cairo',
                                        color: isDark ? AppTheme.primary : Colors.black),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Builder(
                            builder: (context) {
                              return AppSearchField<SupplierModel>(
                                label: 'المورد',
                                controller: supplierSearchController,
                                focusNode: supplierFocusNode,
                                isRequired: true,
                                hint: 'ابحث عن مورد...',
                                prefixIcon:
                                    const Icon(Icons.person_outline, size: 18),
                                highlightColor:
                                    AppTheme.primary.withValues(alpha: 0.5),
                                suggestionsCallback: (pattern) {
                                  final packagingSuppliers = _suppliers.where((s) => s.isPackagingSupplier).toList();
                                  if (pattern.isEmpty) return packagingSuppliers;
                                  final p = pattern.toLowerCase();
                                  return packagingSuppliers
                                      .where((s) =>
                                          s.name.toLowerCase().contains(p) ||
                                          s.supplierCode.toLowerCase().contains(p))
                                      .toList();
                                },
                                itemBuilder: (context, supplier) {
                                  return ListTile(
                                    tileColor: isDark ? null : Colors.white,
                                    title: Text(supplier.name,
                                        style: TextStyle(
                                            color: isDark ? Colors.white : Colors.black,
                                            fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                            fontFamily: 'Cairo',
                                            fontSize: 15)),
                                    subtitle: Text(supplier.supplierCode,
                                        style: TextStyle(
                                            color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                                            fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                            fontFamily: 'Cairo',
                                            fontSize: 13)),
                                  );
                                },
                                onSelected: (s) {
                                  _selectSupplier(s);
                                },
                                onSubmitted: (val) {},
                              );
                            },
                          ),
                          _buildCurrencyAndExchangeRateSection(context, isMobile: false),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('التاريخ',
                              style: TextStyle(
                                  color: isDark ? AppTheme.textSecondary : Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                  fontSize: 14)),
                          const SizedBox(height: 6),
                          BlocBuilder<PurchaseCubit, PurchaseState>(
                            builder: (context, state) {
                              final purchaseDate = c.formState.purchaseDate;
                              return InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: purchaseDate,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2030),
                                  );
                                  if (picked != null) {
                                    c.formState = c.formState
                                        .copyWith(purchaseDate: picked);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 14),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: isDark ? const Color(0xFFBDBDBD) : const Color(0xFFCBD5E1)),
                                    borderRadius: BorderRadius.circular(8),
                                    color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.calendar_today,
                                          size: 16,
                                          color: isDark ? AppTheme.textSecondary : Colors.black87),
                                      const SizedBox(width: 8),
                                      Text(AppUtils.formatDate(purchaseDate),
                                          style: TextStyle(
                                              color: isDark ? Colors.white : Colors.black,
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'Cairo',
                                              fontSize: 15)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('رقم المشتريات',
                              style: TextStyle(
                                  color: isDark ? AppTheme.textSecondary : Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                  fontSize: 14)),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.background : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: isDark ? AppTheme.border : const Color(0xFFCBD5E1)),
                            ),
                            child: Center(
                              child: Text(
                                c.formState.nextPurchaseNumber
                                    .toString()
                                    .padLeft(6, '0'),
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    fontFamily: 'Cairo',
                                    color: isDark ? AppTheme.primary : Colors.black),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text('الأصناف',
                      style: TextStyle(
                          fontSize: isMobile ? 16 : 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                          fontFamily: 'Cairo')),
                  const Spacer(),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(isMobile ? 'صنف' : 'إضافة صنف'),
                    onPressed: _addLine,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                children: List.generate(
                  _controllers.length,
                  (i) => _buildLineCard(context, c, i),
                ),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? AppTheme.border : const Color(0xFFCBD5E1)),
                      boxShadow: isDark
                          ? null
                          : [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('الإجمالي:',
                                style: TextStyle(
                                    color: isDark ? AppTheme.textSecondary : Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo',
                                    fontSize: 14)),
                            const SizedBox(width: 12),
                            Flexible(
                              child: ValueListenableBuilder<double>(
                                valueListenable: subtotalNotifier,
                                builder: (_, val, __) => FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '${AppUtils.formatNumber(val)} ${c.formState.invoiceCurrency}',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        fontFamily: 'Cairo',
                                        color: isDark ? Colors.white : Colors.black),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Builder(
                          builder: (context) {
                            final supplierCurrency = c.formState.selectedSupplier?.currency ?? 'EGP';
                            if (supplierCurrency.toUpperCase() == 'EGP') {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                children: [
                                  Text('بالجنيه المصري:',
                                      style: TextStyle(
                                          color: isDark ? AppTheme.textSecondary : Colors.black,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Cairo',
                                          fontSize: 13)),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    child: ValueListenableBuilder<double>(
                                      valueListenable: subtotalEgpNotifier,
                                      builder: (_, val, __) => FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          '${AppUtils.formatNumber(val)} ج.م',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              fontFamily: 'Cairo',
                                              color: isDark ? AppTheme.cyan : const Color(0xFF0284C7)),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            // Text('المبلغ المدفوع:',
                            //     style: TextStyle(
                            //         color: AppTheme.textSecondary,
                            //         fontWeight: FontWeight.w600,
                            //         fontFamily: 'Cairo',
                            //         fontSize: 14)),
                            // const SizedBox(width: 12),
                            // Expanded(
                            //   child: AppTextField(
                            //     label: 'المبلغ المدفوع',
                            //     controller: paidAmountController,
                            //     focusNode: paidAmountFocusNode,
                            //     hint: '0',
                            //     keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            //     textInputAction: TextInputAction.next,
                            //     onChanged: (_) {
                            //       _refreshSubtotal();
                            //       setState(() {});
                            //     },
                            //   ),
                            // ),
                            const SizedBox(width: 8),
                            Text(c.formState.invoiceCurrency,
                                style: TextStyle(
                                    color: isDark ? AppTheme.textSecondary : Colors.black54,
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold)),
                          ],
                        ),
                        ValueListenableBuilder<double>(
                          valueListenable: subtotalNotifier,
                          builder: (_, subtotal, __) {
                            final paid = double.tryParse(paidAmountController.text) ?? 0.0;
                            if (paid <= 0) return const SizedBox.shrink();
                            final cubit = context.read<PurchaseCubit>();
                            final treasuries = cubit.treasuries;
                            final bankAccounts = cubit.bankAccounts;
                            if (treasuries.isEmpty && bankAccounts.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  '⚠️ لا توجد خزائن أو حسابات بنكية. قم بإنشائها من إعدادات النظام أولاً.',
                                  style: TextStyle(color: AppTheme.danger, fontFamily: 'Cairo', fontSize: 12),
                                ),
                              );
                            }
                            final invoiceCurrency = (cubit.formState.invoiceCurrency).toUpperCase();
                            // Check if any treasuries/banks match the invoice currency
                            bool hasMatchingTreasury = false;
                            for (final t in treasuries) {
                              final balances = t['treasury_balances'];
                              if (balances is List) {
                                for (final b in balances) {
                                  if ((b['currency']?.toString() ?? '').toUpperCase() == invoiceCurrency) {
                                    hasMatchingTreasury = true;
                                    break;
                                  }
                                }
                              }
                              if (hasMatchingTreasury) break;
                            }
                            final hasMatchingBank = bankAccounts.any((b) =>
                                (b['currency']?.toString() ?? '').toUpperCase() == invoiceCurrency);
                            if (!hasMatchingTreasury && !hasMatchingBank) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  '⚠️ لا توجد خزينة أو حساب بنكي بعملة $invoiceCurrency. أضف رصيد بالعملة المطلوبة أولاً.',
                                  style: TextStyle(color: AppTheme.warning, fontFamily: 'Cairo', fontSize: 12),
                                ),
                              );
                            }
                            String? dropdownValue;
                            if (_selectedPaymentSourceType == 'bank' && _selectedBankAccountId != null) {
                              final hasBank = bankAccounts.any((b) => b['id']?.toString() == _selectedBankAccountId.toString() && (b['currency']?.toString() ?? '').toUpperCase() == invoiceCurrency);
                              if (hasBank) dropdownValue = 'bank_$_selectedBankAccountId';
                            } else if (_selectedPaymentSourceType == 'treasury' && _selectedTreasuryId != null && _selectedTreasuryCurrency != null) {
                              if (_selectedTreasuryCurrency == invoiceCurrency) {
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
                                          fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                          fontFamily: 'Cairo',
                                          fontSize: 13),
                                      decoration: InputDecoration(
                                        labelText: 'اختر الخزينة أو الحساب البنكي',
                                        labelStyle: TextStyle(
                                            color: isDark ? AppTheme.textSecondary : Colors.black87,
                                            fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                            fontFamily: 'Cairo'),
                                        filled: true,
                                        fillColor: isDark ? const Color(0x3805192D) : Colors.white,
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
                                        // ── الخزائن: مُصفَّاة بعملة المورد ──
                                        ...() {
                                          final filteredTreasuries = <DropdownMenuItem<String>>[];
                                          for (final t in treasuries) {
                                            final tId = t['id']?.toString() ?? '';
                                            final tName = t['name']?.toString() ?? '';
                                            final balancesRaw = t['treasury_balances'];
                                            final List<dynamic> balances = balancesRaw is List ? balancesRaw : [];
                                            for (final b in balances) {
                                              final currency = (b['currency']?.toString() ?? 'EGP').toUpperCase();
                                              if (currency != invoiceCurrency) continue;
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
                                                            color: isDark ? Colors.white : Colors.black,
                                                            fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                                            fontFamily: 'Cairo'),
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
                                        // ── البنوك: مُصفَّاة بعملة الفاتورة ──
                                        ...bankAccounts.where((b) {
                                          final bankCurrency = (b['currency']?.toString() ?? '').toUpperCase();
                                          return bankCurrency == invoiceCurrency;
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
                                                        color: isDark ? Colors.white : Colors.black,
                                                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                                        fontFamily: 'Cairo'),
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
                                            // format: t_<id>_<CURRENCY>
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
                          },
                        ),
                        const SizedBox(height: 12),
                        // Row(
                        //   children: [
                        //     Text('المتبقي:',
                        //         style: TextStyle(
                        //             color: AppTheme.textSecondary,
                        //             fontWeight: FontWeight.w600,
                        //             fontFamily: 'Cairo',
                        //             fontSize: 14)),
                        //     const SizedBox(width: 12),
                        //     ValueListenableBuilder<double>(
                        //       valueListenable: subtotalNotifier,
                        //       builder: (_, subtotal, __) {
                        //         final paid = double.tryParse(paidAmountController.text) ?? 0.0;
                        //         final remaining = AppUtils.roundDouble(subtotal - paid);
                        //         return Text(
                        //           '${AppUtils.formatNumber(remaining)} ${c.formState.selectedSupplier?.currency ?? 'EGP'}',
                        //           style: TextStyle(
                        //               fontWeight: FontWeight.bold,
                        //               fontSize: 16,
                        //               fontFamily: 'Cairo',
                        //               color: remaining > 0 ? AppTheme.success : remaining < 0 ? AppTheme.danger : AppTheme.success),
                        //         );
                        //       },
                        //     ),
                        //   ],
                        // ),
                        const SizedBox(height: 12),
                        // AppTextField(
                        //   label: 'ملاحظات',
                        //   controller: notesController,
                        //   focusNode: notesFocusNode,
                        //   hint: 'ملاحظات إضافية...',
                        //   maxLines: 2,
                        //   textInputAction: TextInputAction.done,
                        // ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<ItemModel> _getFilteredItems(String pattern) {
    final cubit = context.read<PurchaseCubit>();
    final invoiceCurrency = cubit.formState.invoiceCurrency.trim().toUpperCase();
    final selectedSupplier = cubit.formState.selectedSupplier;

    final sourceList = (cubit.state is PurchaseLoaded && (cubit.state as PurchaseLoaded).allItems.isNotEmpty)
        ? (cubit.state as PurchaseLoaded).allItems
        : _allItems;

    // Strict filter by invoice currency and supplier
    var list = sourceList.where((item) {
      final itemCur = item.currency.trim().toUpperCase();

      // 1. Currency filter: strictly match the invoice currency
      if (invoiceCurrency.isNotEmpty) {
        if (invoiceCurrency == 'EGP') {
          if (itemCur != 'EGP' && itemCur.isNotEmpty) {
            return false;
          }
        } else {
          if (itemCur != invoiceCurrency) {
            return false;
          }
        }
      }

      // 2. Supplier binding filter: if item is bound to a specific supplier, it must match
      if (selectedSupplier != null && item.supplierId != null && item.supplierId!.isNotEmpty) {
        if (item.supplierId != selectedSupplier.id) {
          return false;
        }
      }

      return true;
    }).toList();

    if (pattern.trim().isEmpty) return list;
    final q = pattern.trim().toLowerCase();
    return list.where((item) =>
        item.name.toLowerCase().contains(q) ||
        item.code.toLowerCase().contains(q)).toList();
  }

  void _showItemPickerSheet(int lineIndex) {
    final line = _controllers[lineIndex];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final invoiceCurrency = context.read<PurchaseCubit>().formState.invoiceCurrency;
    final items = _getFilteredItems('');
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
                : items.where((it) {
                    final q = searchQuery.toLowerCase();
                    return it.name.toLowerCase().contains(q) ||
                           it.code.toLowerCase().contains(q);
                  }).toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0A1E38) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.15),
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
                            invoiceCurrency.isNotEmpty
                                ? 'اختيار مادة التعبئة ($invoiceCurrency)'
                                : 'اختيار مادة التعبئة',
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
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          fontWeight: isDark ? FontWeight.normal : FontWeight.bold),
                      decoration: InputDecoration(
                        hintText: 'بحث سريع بالاسم أو الكود...',
                        hintStyle: TextStyle(
                            fontFamily: 'Cairo',
                            color: isDark ? Colors.white.withValues(alpha: 0.35) : Colors.black38,
                            fontSize: 13),
                        prefixIcon: Icon(Icons.search,
                            color: isDark ? AppTheme.textSecondary : Colors.black87, size: 20),
                        filled: true,
                        fillColor: isDark ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFF1F5F9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: isDark ? Colors.transparent : const Color(0xFFCBD5E1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: isDark ? Colors.transparent : const Color(0xFFCBD5E1)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  Divider(color: isDark ? const Color(0x22FFFFFF) : const Color(0xFFE2E8F0), height: 1),
                  // Items list
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.inbox_outlined, size: 48,
                                    color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black26),
                                const SizedBox(height: 8),
                                Text(
                                  items.isEmpty
                                      ? (invoiceCurrency.isNotEmpty
                                          ? 'لا توجد أصناف مسجلة بالعملة الحالية ($invoiceCurrency)'
                                          : 'لا توجد أصناف متاحة')
                                      : 'لا توجد أصناف متطابقة مع البحث',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 14,
                                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                      color: isDark ? Colors.white54 : Colors.black54),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (ctx, i) {
                              final it = filtered[i];
                              final isSelected = it.id != null && it.id == line.existingItemId;
                              final priceText = it.costPrice > 0
                                  ? '${it.costPrice.toStringAsFixed(2)} ${it.currency}'
                                  : (it.pricePerUnit > 0 ? '${it.pricePerUnit.toStringAsFixed(2)} ${it.currency}' : null);

                              return GestureDetector(
                                onTap: () {
                                  int? defaultStation;
                                  if (_stations.isNotEmpty) {
                                    defaultStation = int.tryParse(_stations.first.id ?? '');
                                  }
                                  line.loadItem(it, defaultStationId: defaultStation);
                                  setState(() {});
                                  Navigator.of(ctx).pop();
                                  Future.microtask(() => line.quantityFocus.requestFocus());
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppTheme.primary.withValues(alpha: 0.15)
                                        : (isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC)),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppTheme.primary.withValues(alpha: 0.5)
                                          : (isDark ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0)),
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
                                                : (isDark
                                                    ? [const Color(0xFF1A3A5C), const Color(0xFF0F2744)]
                                                    : [const Color(0xFFE0F2FE), const Color(0xFFBAE6FD)]),
                                          ),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Center(
                                          child: Text(
                                            it.code,
                                            style: TextStyle(
                                              fontFamily: 'Cairo',
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: isSelected
                                                  ? Colors.white
                                                  : (isDark ? AppTheme.primary : const Color(0xFF0369A1)),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Name & price / stock
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              it.name,
                                              style: TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: isSelected
                                                    ? AppTheme.primary
                                                    : (isDark ? Colors.white : Colors.black),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                if (priceText != null) ...[
                                                  Text(
                                                    'السعر: $priceText',
                                                    style: TextStyle(
                                                        fontFamily: 'Cairo',
                                                        fontSize: 11,
                                                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                                        color: isDark ? AppTheme.textSecondary : const Color(0xFF475569)),
                                                  ),
                                                  const SizedBox(width: 8),
                                                ],
                                                Text(
                                                  'المخزون: ${it.stockQuantity} ${it.unit}',
                                                  style: TextStyle(
                                                      fontFamily: 'Cairo',
                                                      fontSize: 11,
                                                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                                      color: isDark
                                                          ? AppTheme.textSecondary.withValues(alpha: 0.7)
                                                          : const Color(0xFF475569)),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Currency / checked
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            it.currency,
                                            style: TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 11,
                                                fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                                color: isDark ? AppTheme.textSecondary : Colors.black87),
                                          ),
                                          if (isSelected) ...[
                                            const SizedBox(width: 6),
                                            const Icon(Icons.check_circle, size: 18, color: AppTheme.primary),
                                          ],
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

  Widget _buildItemSearchField(_PurchaseLineController line, int lineIndex) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TypeAheadField<ItemModel>(
      controller: line.searchController,
      focusNode: line.searchFocus,
      suggestionsCallback: (pattern) => _getFilteredItems(pattern),
      emptyBuilder: (context) {
        final cur = context.read<PurchaseCubit>().formState.invoiceCurrency;
        return Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 28, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
              const SizedBox(height: 6),
              Text(
                cur.isNotEmpty
                    ? 'لا توجد أصناف مسجلة بعملة الفاتورة ($cur)'
                    : 'لا يوجد صنف بهذا الاسم أو الكود',
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
      itemBuilder: (context, item) {
        final isSelected = item.id != null && item.id == line.existingItemId;
        final priceText = item.costPrice > 0
            ? '${item.costPrice.toStringAsFixed(2)} ${item.currency}'
            : (item.pricePerUnit > 0 ? '${item.pricePerUnit.toStringAsFixed(2)} ${item.currency}' : null);

        return Container(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.1)
              : (isDark ? null : Colors.white),
          child: ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            leading: Container(
              width: 42,
              height: 36,
              decoration: BoxDecoration(
                color: isDark
                    ? AppTheme.primary.withValues(alpha: 0.15)
                    : const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  item.code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppTheme.primary : const Color(0xFF0369A1),
                  ),
                ),
              ),
            ),
            title: Text(
              item.name,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isSelected
                    ? AppTheme.primary
                    : (isDark ? Colors.white : Colors.black),
              ),
            ),
            subtitle: Row(
              children: [
                if (priceText != null)
                  Text(
                    'السعر: $priceText',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF475569)),
                  ),
                if (priceText != null) const SizedBox(width: 8),
                Text(
                  'المخزون: ${item.stockQuantity} ${item.unit}',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10,
                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                      color: isDark ? AppTheme.textSecondary.withValues(alpha: 0.8) : const Color(0xFF475569)),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.currency,
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                      color: isDark ? AppTheme.textSecondary : Colors.black87),
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
      onSelected: (item) {
        int? defaultStation;
        if (_stations.isNotEmpty) {
          defaultStation = int.tryParse(_stations.first.id ?? '');
        }
        line.loadItem(item, defaultStationId: defaultStation);
        setState(() {});
        Future.microtask(() => line.quantityFocus.requestFocus());
      },
      decorationBuilder: (context, child) {
        return Material(
          type: MaterialType.card,
          elevation: 12,
          borderRadius: BorderRadius.circular(14),
          color: isDark ? const Color(0xFF0A1E38) : Colors.white,
          shadowColor: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: child,
            ),
          ),
        );
      },
      builder: (context, controller, focusNode) {
        return TextField(
          enabled: !widget.viewOnly,
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: 'بحث عن الصنف *',
            hintText: 'بحث عن الصنف... اكتب اسم الصنف أو الكود',
            hintStyle: TextStyle(
                color: isDark ? AppTheme.textSecondary : Colors.black38, fontSize: 13, fontFamily: 'Cairo'),
            labelStyle: TextStyle(
                color: isDark ? AppTheme.textSecondary : Colors.black87,
                fontSize: 14,
                fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                fontFamily: 'Cairo'),
            filled: true,
            fillColor: isDark ? const Color(0x1AFFFFFF) : Colors.white,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: isDark ? Colors.transparent : const Color(0xFFCBD5E1))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            prefixIcon: Icon(Icons.search_rounded,
                color: isDark ? AppTheme.textSecondary : Colors.black87, size: 20),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (line.existingItemId != null && !widget.viewOnly)
                  GestureDetector(
                    onTap: () {
                      line.clearItem();
                      setState(() {});
                    },
                    child: Icon(Icons.close,
                        size: 18,
                        color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black45),
                  ),
                const SizedBox(width: 4),
                // Quick-picker icon button
                GestureDetector(
                  onTap: !widget.viewOnly ? () => _showItemPickerSheet(lineIndex) : null,
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
          style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
              fontFamily: 'Cairo'),
          onTap: () {
            if (controller.text.isEmpty) {
              controller.text = '';
            }
          },
        );
      },
    );
  }

  Widget _buildLineCard(BuildContext context, PurchaseCubit c, int i) {
    final line = _controllers[i];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width < 600;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: isDark
              ? AppTheme.glassCard()
              : BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                if (isMobile) ...[
                  _buildItemSearchField(line, i),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          label: 'الكود',
                          controller: line.codeController,
                          readOnly: true,
                          hint: 'كود',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AppTextField(
                          label: 'الاسم',
                          controller: line.nameController,
                          readOnly: true,
                          hint: 'اسم الصنف',
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: AppTheme.danger, size: 20),
                        onPressed: () => _removeLine(i),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: _buildItemSearchField(line, i),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 100,
                        child: AppTextField(
                          label: 'الكود',
                          controller: line.codeController,
                          readOnly: true,
                          hint: 'كود',
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 120,
                        child: AppTextField(
                          label: 'الاسم',
                          controller: line.nameController,
                          readOnly: true,
                          hint: 'اسم الصنف',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 24.0),
                        child: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: AppTheme.danger, size: 20),
                          onPressed: () => _removeLine(i),
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: AppTextField(
                        label: 'الكمية',
                        controller: line.quantityController,
                        focusNode: line.quantityFocus,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*')),
                        ],
                        hint: '0.00',
                        suffixIcon: Center(
                            widthFactor: 1,
                            child: Text(line.unit,
                                style: TextStyle(
                                    color: isDark ? AppTheme.textSecondary : Colors.black87,
                                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                    fontFamily: 'Cairo',
                                    fontSize: 13))),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppTextField(
                        label: 'سعر الشراء',
                        controller: line.purchasePriceController,
                        focusNode: line.purchasePriceFocus,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*')),
                        ],
                        hint: '0.00',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Builder(
                      builder: (context) {
                        final invoiceCurrency = context.read<PurchaseCubit>().formState.invoiceCurrency;
                        if (invoiceCurrency.toUpperCase() == 'EGP') {
                          return const SizedBox.shrink();
                        }
                        return SizedBox(
                          width: 120,
                          child: AppTextField(
                            label: 'سعر الصرف',
                            controller: line.exchangeRateController,
                            readOnly: true,
                            keyboardType: TextInputType.number,
                            isRequired: true,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*')),
                            ],
                            hint: 'سعر الصرف',
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    if (!isMobile)
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            return DropdownButtonFormField<int>(
                              value: line.stationId,
                              dropdownColor: isDark ? const Color(0xFF0A2A4A) : Colors.white,
                              style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                  fontFamily: 'Cairo',
                                  fontSize: 13),
                              decoration: InputDecoration(
                                labelText: 'المخزن *',
                                labelStyle: TextStyle(
                                    color: isDark ? AppTheme.textSecondary : Colors.black87,
                                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                    fontFamily: 'Cairo'),
                                filled: true,
                                fillColor: isDark ? const Color(0x3805192D) : Colors.white,
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
                              items: _stations.map((s) => DropdownMenuItem<int>(
                                value: int.tryParse(s.id ?? ''),
                                child: Text('${s.name} (${s.code})',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? Colors.white : Colors.black,
                                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                        fontFamily: 'Cairo')),
                              )).toList(),
                              onChanged: (v) => line.stationId = v,
                              validator: (v) => v == null ? 'اختر المخزن' : null,
                            );
                          },
                        ),
                      ),
                    if (!isMobile) const SizedBox(width: 8),
                    if (!isMobile)
                      Container(
                        height: 48,
                        width: 110,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.success.withValues(alpha: 0.05) : const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: isDark ? AppTheme.success.withValues(alpha: 0.2) : const Color(0xFFA7F3D0)),
                        ),
                        child: ValueListenableBuilder<double>(
                          valueListenable: line.totalPriceRx,
                          builder: (_, val, __) => Text(
                            '${AppUtils.formatNumber(val)} ${c.formState.invoiceCurrency}',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isDark ? AppTheme.success : const Color(0xFF047857),
                                fontFamily: 'Cairo'),
                          ),
                        ),
                      ),
                  ],
                ),
                if (isMobile) ...[
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final invoiceCurrency = context.read<PurchaseCubit>().formState.invoiceCurrency;
                      if (invoiceCurrency.toUpperCase() == 'EGP') {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SizedBox(
                          width: 120,
                          child: AppTextField(
                            label: 'سعر الصرف',
                            controller: line.exchangeRateController,
                            readOnly: true,
                            keyboardType: TextInputType.number,
                            isRequired: true,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*')),
                            ],
                            hint: 'سعر الصرف',
                          ),
                        ),
                      );
                    },
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Builder(
                          builder: (context) {
                            return DropdownButtonFormField<int>(
                              value: line.stationId,
                              dropdownColor: isDark ? const Color(0xFF0A2A4A) : Colors.white,
                              style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                  fontFamily: 'Cairo',
                                  fontSize: 13),
                              decoration: InputDecoration(
                                labelText: 'المخزن *',
                                labelStyle: TextStyle(
                                    color: isDark ? AppTheme.textSecondary : Colors.black87,
                                    fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                    fontFamily: 'Cairo'),
                                filled: true,
                                fillColor: isDark ? const Color(0x3805192D) : Colors.white,
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
                              items: _stations.map((s) => DropdownMenuItem<int>(
                                value: int.tryParse(s.id ?? ''),
                                child: Text('${s.name} (${s.code})',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? Colors.white : Colors.black,
                                        fontWeight: isDark ? FontWeight.normal : FontWeight.bold,
                                        fontFamily: 'Cairo')),
                              )).toList(),
                              onChanged: (v) => line.stationId = v,
                              validator: (v) => v == null ? 'اختر المخزن' : null,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.success.withValues(alpha: 0.05) : const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: isDark ? AppTheme.success.withValues(alpha: 0.2) : const Color(0xFFA7F3D0)),
                          ),
                          child: ValueListenableBuilder<double>(
                            valueListenable: line.totalPriceRx,
                            builder: (_, val, __) => Text(
                              '${AppUtils.formatNumber(val)} ${c.formState.invoiceCurrency}',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? AppTheme.success : const Color(0xFF047857),
                                  fontFamily: 'Cairo'),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
