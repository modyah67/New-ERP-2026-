// lib/features/purchases/purchase_form_page.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
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

  void loadItem(ItemModel item) {
    codeController.text = item.code;
    nameController.text = item.name;
    purchasePriceController.text = item.costPrice.toStringAsFixed(2);
    existingItemId = item.id;
    unit = item.unit;
    searchController.text = '${item.code} - ${item.name}';
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
      _suppliers = state.suppliers;
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
      }
      cubit.selectSupplier(fs.selectedSupplier!);

      for (final line in fs.purchaseLines) {
        final ctrl = _PurchaseLineController();
        ctrl.searchController.text = line.name.isNotEmpty ? '${line.code} - ${line.name}' : line.code;
        ctrl.codeController.text = line.code;
        ctrl.nameController.text = line.name;
        ctrl.quantityController.text = line.quantity.toStringAsFixed(0);
        ctrl.purchasePriceController.text = line.purchasePrice.toStringAsFixed(2);
        ctrl.exchangeRateController.text = line.exchangeRate.toStringAsFixed(2);
        ctrl.unit = line.unit;
        ctrl.currency = fs.selectedSupplier!.currency ?? 'EGP';
        ctrl.existingItemId = line.existingItemId;
        ctrl.stationId = int.tryParse(line.stationId ?? '');
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
            final currentState = cubit.state;
            if (currentState is PurchaseLoaded) {
              final matches = currentState.allItems
                  .where((it) => it.name.toLowerCase().contains(query.toLowerCase()) || it.code.toLowerCase().contains(query.toLowerCase()))
                  .toList();
              if (matches.isNotEmpty) ctrl.loadItem(matches.first);
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
    line.currency = cubit.formState.selectedSupplier?.currency ?? 'EGP';
    if (invoiceExchangeRateController.text.isNotEmpty) {
      line.exchangeRateController.text = invoiceExchangeRateController.text;
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
        final currentState = cubit.state;
        if (currentState is PurchaseLoaded) {
          final matches = currentState.allItems
              .where((it) =>
                  it.name.toLowerCase().contains(query.toLowerCase()) ||
                  it.code.toLowerCase().contains(query.toLowerCase()))
              .toList();
          if (matches.isNotEmpty) {
            ctrl.loadItem(matches.first);
          }
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

  Future<void> _selectSupplier(SupplierModel s) async {
    final cubit = context.read<PurchaseCubit>();
    supplierSearchController.text = '${s.supplierCode} - ${s.name}';
    cubit.selectSupplier(s);
    if (s.currency != null && s.currency!.toUpperCase() != 'EGP') {
      final defaultRate = await CurrencyConversionService.instance.getRate(s.currency!);
      if (defaultRate > 0) {
        invoiceExchangeRateController.text = defaultRate.toStringAsFixed(2);
      }
    } else {
      invoiceExchangeRateController.text = '1.00';
    }
    for (final c in _controllers) {
      c.currency = s.currency ?? 'EGP';
      if (invoiceExchangeRateController.text.isNotEmpty) {
        c.exchangeRateController.text = invoiceExchangeRateController.text;
      }
    }
    _refreshSubtotal();
    if (mounted) setState(() {});
    if (_controllers.isNotEmpty) {
      _controllers.first.codeFocus.requestFocus();
    }
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
            );
    _initialized = false;
    _addLine();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in old) {
        c.dispose();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.read<PurchaseCubit>();
    final isEditing = c.formState.isEditing;
    final isMobile = MediaQuery.of(context).size.width < 600;

    final paidAmtForBtn = double.tryParse(paidAmountController.text) ?? 0.0;
    final isSaveDisabled = paidAmtForBtn > 0 && _selectedTreasuryId == null && _selectedBankAccountId == null;

    return BlocListener<PurchaseCubit, PurchaseState>(
      listener: (context, state) {
        if (state is PurchaseFormSaved) {
          _resetForm();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(isEditing ? 'تعديل مشتريات' : 'مشتريات جديدة',
                style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          ),
          actions: [
            if (!widget.viewOnly)
              IconButton(
              icon: Icon(Icons.save, color: isSaveDisabled ? Colors.white38 : Colors.white, size: 20),
              tooltip: isEditing ? 'تحديث' : 'حفظ',
              onPressed: isSaveDisabled ? null : () async {
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

                final supplierCurrency = c.formState.selectedSupplier?.currency ?? 'EGP';
                final isForeign = supplierCurrency.toUpperCase() != 'EGP';
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
                  final curSuppCurrency = (c.formState.selectedSupplier?.currency ?? 'EGP').toUpperCase();
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
                            if ((b['currency']?.toString() ?? '').toUpperCase() == curSuppCurrency) {
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
                          'المبلغ المدفوع ($paidAmount $curSuppCurrency) أكبر من الرصيد المتاح في "$sourceName" ($availableBalance $curSuppCurrency). قم بشحن الخزينة أو الحساب أولاً.',
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
                            if (pattern.isEmpty) return _suppliers;
                            final p = pattern.toLowerCase();
                            return _suppliers
                                .where((s) =>
                                    s.name.toLowerCase().contains(p) ||
                                    s.supplierCode.toLowerCase().contains(p))
                                .toList();
                          },
                          itemBuilder: (context, supplier) {
                            return ListTile(
                              title: Text(supplier.name,
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontFamily: 'Cairo',
                                      fontSize: 15)),
                              subtitle: Text(supplier.supplierCode,
                                  style: TextStyle(
                                      color: AppTheme.textSecondary,
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
                    Builder(
                      builder: (context) {
                        final supplier = c.formState.selectedSupplier;
                        if (supplier == null) return const SizedBox.shrink();
                        final isForeign = supplier.currency.toUpperCase() != 'EGP';
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                                    'عملة المورد: ${supplier.currency}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.warning, fontFamily: 'Cairo'),
                                  ),
                                ],
                              ),
                            ),
                            if (isForeign) ...[
                              const SizedBox(height: 8),
                              AppTextField(
                                label: 'سعر الصرف',
                                controller: invoiceExchangeRateController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                isRequired: true,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*')),
                                ],
                                hint: 'أدخل سعر الصرف...',
                                prefixIcon: const Icon(Icons.currency_exchange, size: 18),
                                onChanged: (val) {
                                  for (final line in _controllers) {
                                    line.exchangeRateController.text = val;
                                  }
                                },
                              ),
                            ],
                          ],
                        );
                      },
                    ),
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
                                      color: AppTheme.textSecondary,
                                      fontWeight: FontWeight.w600,
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
                                            color: const Color(0xFFBDBDBD)),
                                        borderRadius: BorderRadius.circular(8),
                                        color: Colors.white.withValues(alpha: 0.03),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.calendar_today,
                                              size: 16,
                                              color: AppTheme.textSecondary),
                                          const SizedBox(width: 8),
                                          Text(AppUtils.formatDate(purchaseDate),
                                              style: TextStyle(
                                                  color: Colors.white,
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
                                      color: AppTheme.textSecondary,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Cairo',
                                      fontSize: 14)),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  color: AppTheme.background,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.border),
                                ),
                                child: Center(
                                  child: Text(
                                    c.formState.nextPurchaseNumber
                                        .toString()
                                        .padLeft(6, '0'),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        fontFamily: 'Cairo',
                                        color: AppTheme.primary),
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
                                  if (pattern.isEmpty) return _suppliers;
                                  final p = pattern.toLowerCase();
                                  return _suppliers
                                      .where((s) =>
                                          s.name.toLowerCase().contains(p) ||
                                          s.supplierCode.toLowerCase().contains(p))
                                      .toList();
                                },
                                itemBuilder: (context, supplier) {
                                  return ListTile(
                                    title: Text(supplier.name,
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontFamily: 'Cairo',
                                            fontSize: 15)),
                                    subtitle: Text(supplier.supplierCode,
                                        style: TextStyle(
                                            color: AppTheme.textSecondary,
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
                          Builder(
                            builder: (context) {
                              final supplier = c.formState.selectedSupplier;
                              if (supplier == null) return const SizedBox.shrink();
                              final isForeign = supplier.currency.toUpperCase() != 'EGP';
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(top: 8),
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
                                          'عملة المورد: ${supplier.currency}',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.warning, fontFamily: 'Cairo'),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isForeign) ...[
                                    const SizedBox(height: 8),
                                    AppTextField(
                                      label: 'سعر الصرف',
                                      controller: invoiceExchangeRateController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      isRequired: true,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*')),
                                      ],
                                      hint: 'أدخل سعر الصرف...',
                                      prefixIcon: const Icon(Icons.currency_exchange, size: 18),
                                      onChanged: (val) {
                                        for (final line in _controllers) {
                                          line.exchangeRateController.text = val;
                                        }
                                      },
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
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
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w600,
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
                                        color: const Color(0xFFBDBDBD)),
                                    borderRadius: BorderRadius.circular(8),
                                    color: Colors.white.withValues(alpha: 0.03),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.calendar_today,
                                          size: 16,
                                          color: AppTheme.textSecondary),
                                      const SizedBox(width: 8),
                                      Text(AppUtils.formatDate(purchaseDate),
                                          style: TextStyle(
                                              color: Colors.white,
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
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'Cairo',
                                  fontSize: 14)),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppTheme.background,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Center(
                              child: Text(
                                c.formState.nextPurchaseNumber
                                    .toString()
                                    .padLeft(6, '0'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    fontFamily: 'Cairo',
                                    color: AppTheme.primary),
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
                          color: Colors.white,
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
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('الإجمالي:',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Cairo',
                                    fontSize: 14)),
                            const SizedBox(width: 12),
                            Flexible(
                              child: ValueListenableBuilder<double>(
                                valueListenable: subtotalNotifier,
                                builder: (_, val, __) => FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '${AppUtils.formatNumber(val)} ${c.formState.selectedSupplier?.currency ?? 'EGP'}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        fontFamily: 'Cairo',
                                        color: Colors.white),
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
                                          color: AppTheme.textSecondary,
                                          fontWeight: FontWeight.w600,
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
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              fontFamily: 'Cairo',
                                              color: AppTheme.cyan),
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
                            Text(c.formState.selectedSupplier?.currency ?? 'EGP',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontFamily: 'Cairo',
                                    fontSize: 12)),
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
                            final supplierCurrency = (cubit.formState.selectedSupplier?.currency ?? 'EGP').toUpperCase();
                            // Check if any treasuries/banks match the supplier currency
                            bool hasMatchingTreasury = false;
                            for (final t in treasuries) {
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
                            final hasMatchingBank = bankAccounts.any((b) =>
                                (b['currency']?.toString() ?? '').toUpperCase() == supplierCurrency);
                            if (!hasMatchingTreasury && !hasMatchingBank) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  '⚠️ لا توجد خزينة أو حساب بنكي بعملة $supplierCurrency. أضف رصيد بالعملة المطلوبة أولاً.',
                                  style: TextStyle(color: AppTheme.warning, fontFamily: 'Cairo', fontSize: 12),
                                ),
                              );
                            }
                            String? dropdownValue;
                            if (_selectedPaymentSourceType == 'bank' && _selectedBankAccountId != null) {
                              final hasBank = bankAccounts.any((b) => b['id']?.toString() == _selectedBankAccountId.toString() && (b['currency']?.toString() ?? '').toUpperCase() == supplierCurrency);
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
                                        // ── البنوك: مُصفَّاة بعملة المورد ──
                                        ...bankAccounts.where((b) {
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

  Widget _buildLineCard(BuildContext context, PurchaseCubit c, int i) {
    final line = _controllers[i];
    final isMobile = MediaQuery.of(context).size.width < 600;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: AppTheme.glassCard(),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                if (isMobile) ...[
                  Builder(
                    builder: (context) {
                      return AppSearchField<ItemModel>(
                        label: 'بحث عن الصنف',
                        controller: line.searchController,
                        focusNode: line.searchFocus,
                        hint: 'ابحث بالكود أو الاسم...',
                        highlightColor:
                            AppTheme.primary.withValues(alpha: 0.5),
                        suggestionsCallback: (pattern) {
                          if (pattern.isEmpty) return <ItemModel>[];
                          final supplierCurrency = context.read<PurchaseCubit>().formState.selectedSupplier?.currency ?? 'EGP';
                          return _allItems
                              .where((item) =>
                                  item.currency.toUpperCase() == supplierCurrency.toUpperCase() &&
                                  (item.code
                                      .toLowerCase()
                                      .contains(pattern.toLowerCase()) ||
                                  item.name
                                      .toLowerCase()
                                      .contains(pattern.toLowerCase())))
                              .toList();
                        },
                        itemBuilder: (context, item) {
                          return ListTile(
                            title: Text('${item.code} - ${item.name}',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'Cairo',
                                    fontSize: 15)),
                            trailing: Text(item.stockQuantity.toString(),
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontFamily: 'Cairo',
                                    fontSize: 13)),
                          );
                        },
                        onSelected: (item) {
                          line.loadItem(item);
                          Future.microtask(
                              () => line.quantityFocus.requestFocus());
                        },
                      );
                    },
                  ),
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
                        child: Builder(
                          builder: (context) {
                            return AppSearchField<ItemModel>(
                              label: 'بحث عن الصنف',
                              controller: line.searchController,
                              focusNode: line.searchFocus,
                              hint: 'ابحث بالكود أو الاسم...',
                              highlightColor:
                                  AppTheme.primary.withValues(alpha: 0.5),
                              suggestionsCallback: (pattern) {
                                if (pattern.isEmpty) return <ItemModel>[];
                                final supplierCurrency = context.read<PurchaseCubit>().formState.selectedSupplier?.currency ?? 'EGP';
                                return _allItems
                                    .where((item) =>
                                        item.currency.toUpperCase() == supplierCurrency.toUpperCase() &&
                                        (item.code
                                            .toLowerCase()
                                            .contains(pattern.toLowerCase()) ||
                                        item.name
                                            .toLowerCase()
                                            .contains(pattern.toLowerCase())))
                                    .toList();
                              },
                              itemBuilder: (context, item) {
                                return ListTile(
                                  title: Text('${item.code} - ${item.name}',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontFamily: 'Cairo',
                                          fontSize: 15)),
                                  trailing: Text(item.stockQuantity.toString(),
                                      style: TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontFamily: 'Cairo',
                                          fontSize: 13)),
                                );
                              },
                              onSelected: (item) {
                                line.loadItem(item);
                                Future.microtask(
                                    () => line.quantityFocus.requestFocus());
                              },
                            );
                          },
                        ),
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
                                    color: AppTheme.textSecondary,
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
                        final supplierCurrency = context.read<PurchaseCubit>().formState.selectedSupplier?.currency ?? 'EGP';
                        if (supplierCurrency.toUpperCase() == 'EGP') {
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
                              dropdownColor: const Color(0xFF0A2A4A),
                              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                              decoration: InputDecoration(
                                labelText: 'المخزن *',
                                labelStyle: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'),
                                filled: true,
                                fillColor: const Color(0x3805192D),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.glassBorder)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                              ),
                              items: _stations.map((s) => DropdownMenuItem<int>(
                                value: int.tryParse(s.id ?? ''),
                                child: Text('${s.name} (${s.code})', style: const TextStyle(fontSize: 12)),
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
                          color: AppTheme.success.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppTheme.success.withValues(alpha: 0.2)),
                        ),
                        child: ValueListenableBuilder<double>(
                          valueListenable: line.totalPriceRx,
                          builder: (_, val, __) => Text(
                            '${AppUtils.formatNumber(val)} ${c.formState.selectedSupplier?.currency ?? 'EGP'}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.success,
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
                      final supplierCurrency = context.read<PurchaseCubit>().formState.selectedSupplier?.currency ?? 'EGP';
                      if (supplierCurrency.toUpperCase() == 'EGP') {
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
                              dropdownColor: const Color(0xFF0A2A4A),
                              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                              decoration: InputDecoration(
                                labelText: 'المخزن *',
                                labelStyle: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'),
                                filled: true,
                                fillColor: const Color(0x3805192D),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.glassBorder)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                              ),
                              items: _stations.map((s) => DropdownMenuItem<int>(
                                value: int.tryParse(s.id ?? ''),
                                child: Text('${s.name} (${s.code})', style: const TextStyle(fontSize: 12)),
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
                            color: AppTheme.success.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppTheme.success.withValues(alpha: 0.2)),
                          ),
                          child: ValueListenableBuilder<double>(
                            valueListenable: line.totalPriceRx,
                            builder: (_, val, __) => Text(
                              '${AppUtils.formatNumber(val)} ${c.formState.selectedSupplier?.currency ?? 'EGP'}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.success,
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
