import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../core/widgets/read_only_guard.dart';
import '../../core/ui_utils.dart';
import '../../core/utils.dart';
import '../../data/models/export_shipment_model.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/clearing_agent_model.dart';
import '../../data/dao/clearing_agent_dao.dart';
import '../../ui/widgets/app_text_field.dart';
import '../../ui/widgets/app_search_field.dart';
import 'dart:async';
import '../../core/data_change_event_bus.dart';
import '../../data/dao/packing_order_dao.dart';
import '../../data/models/packing_order_model.dart';
import '../../data/models/packing_order_line_model.dart';
import 'export_shipment_cubit.dart';
import 'shipment_constants.dart';
import 'invoice_preview_page.dart';
import 'credit_note_pdf_service.dart';
import '../../data/services/currency_conversion_service.dart';

class ExportShipmentFormPage extends StatefulWidget {
  final ExportShipmentModel? shipment;
  final bool isReadOnly;
  const ExportShipmentFormPage({super.key, this.shipment, this.isReadOnly = false});

  @override
  State<ExportShipmentFormPage> createState() => _ExportShipmentFormPageState();
}

class _ExportShipmentFormPageState extends State<ExportShipmentFormPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _countryOfOriginCtrl;

  late TextEditingController _shipmentNoCtrl;
  late TextEditingController _manualCodeCtrl;
  late TextEditingController _customerSearchCtrl;
  late TextEditingController _invoiceSearchCtrl;
  late TextEditingController _contactPersonCtrl;
  late TextEditingController _countryCtrl;
  late TextEditingController _destinationAddressCtrl;
  late TextEditingController _containerNoCtrl;
  late TextEditingController _vesselNameCtrl;
  late TextEditingController _dataLoggerNoCtrl;
  late TextEditingController _awbCtrl;
  late TextEditingController _portOfLoadingCtrl;
  late TextEditingController _portOfDestCtrl;
  late TextEditingController _paymentTermsCtrl;
  late TextEditingController _termsConditionsCtrl;
  late TextEditingController _internalNotesCtrl;
  late TextEditingController _invoiceNoCtrl;
  late TextEditingController _transportModeCtrl;
  late TextEditingController _clearingAgentSearchCtrl;
  late TextEditingController _discountAmountCtrl;
  late TextEditingController _discountReasonCtrl;
  final TextEditingController _exchangeRateCtrl = TextEditingController(text: '1.00');

  String _transportMode = 'sea';
  String _incoterm = 'FOB';
  String _currency = 'EGP';
  DateTime? _shipmentDate;
  bool _isSaving = false;

  String? _selectedCustomerId;
  int? _selectedAddressIndex;
  dynamic _selectedInvoiceId;
  String? _selectedClearingAgentId;
  String _customerDisplayText = '';
  String _customerCode = '';
  String _invoiceDisplayText = '';

  late TextEditingController _paidAmountCtrl;
  String? _selectedTreasuryId;
  String? _selectedPaymentSourceType;
  int? _selectedBankAccountId;
  String? _selectedTreasuryCurrency;
  List<Map<String, dynamic>> _treasuries = [];
  List<Map<String, dynamic>> _bankAccounts = [];

  final _packingOrderDao = PackingOrderDao();

  List<CustomerModel> _customers = [];
  List<dynamic> _invoices = [];
  List<ClearingAgentModel> _clearingAgents = [];
  List<PackingOrderModel> _availablePackingOrders = [];
  StreamSubscription<void>? _packingOrdersSub;
  StreamSubscription<void>? _exportsSub;
  double _totalExtraCosts = 0.0;
  List<_ShipmentItem> _items = [];

  @override
  void initState() {
    super.initState();
    final s = widget.shipment;
    _countryOfOriginCtrl =
        TextEditingController(text: s?.countryOfOrigin ?? 'Egypt');
    _shipmentNoCtrl = TextEditingController(text: s?.shipmentNo ?? '');
    _manualCodeCtrl = TextEditingController();
    _customerSearchCtrl = TextEditingController();
    _invoiceSearchCtrl = TextEditingController();
    _contactPersonCtrl = TextEditingController(text: s?.contactPerson ?? '');
    _countryCtrl = TextEditingController(text: s?.country ?? '');
    _destinationAddressCtrl =
        TextEditingController(text: s?.destinationAddress ?? '');
    _containerNoCtrl = TextEditingController(text: s?.containerNo ?? '');
    _vesselNameCtrl = TextEditingController(text: s?.vesselName ?? '');
    _dataLoggerNoCtrl = TextEditingController(text: s?.dataLoggerNo ?? '');
    _awbCtrl = TextEditingController(text: s?.blNumber ?? '');
    _portOfLoadingCtrl = TextEditingController(text: s?.portOfLoading ?? '');
    _portOfDestCtrl = TextEditingController(text: s?.portOfDestination ?? '');
    _paymentTermsCtrl = TextEditingController(text: s?.paymentTerms ?? '');
    _termsConditionsCtrl =
        TextEditingController(text: s?.termsConditions ?? '');
    _internalNotesCtrl = TextEditingController(text: s?.internalNotes ?? '');
    _invoiceNoCtrl = TextEditingController(text: s?.invoiceNumber ?? '');
    _transportModeCtrl = TextEditingController(
        text: s?.transportMode == 'air' ? 'By Air' : 'By Sea');
    _clearingAgentSearchCtrl = TextEditingController();
    _discountAmountCtrl = TextEditingController(
        text: (s?.discountAmount ?? 0.0) > 0 ? s!.discountAmount.toString() : '');
    _discountReasonCtrl = TextEditingController(text: s?.discountReason ?? '');
    _transportMode = s?.transportMode ?? 'sea';
    _incoterm = s?.incoterm ?? 'FOB';
    _currency = s?.currency ?? s?.currencyCode ?? 'EGP';
    final initialRate = (s?.exchangeRate ?? 0.0) > 0
        ? s!.exchangeRate
        : (_currency == 'EGP' ? 1.0 : 50.0);
    _exchangeRateCtrl.text = initialRate.toStringAsFixed(2);
    if (_currency != 'EGP' && (s?.exchangeRate ?? 0.0) <= 0) {
      CurrencyConversionService.instance.getRate(_currency).then((rate) {
        if (mounted && rate > 0) {
          setState(() {
            _exchangeRateCtrl.text = rate.toStringAsFixed(2);
          });
        }
      });
    }
    _shipmentDate = s?.shipmentDate;
    _selectedCustomerId = s?.customerId;
    _selectedInvoiceId = s?.invoiceId;
    _selectedClearingAgentId = s?.clearingAgentId;
    _customerDisplayText =
        s != null && s.customerName != null ? s.customerName! : '';
    _customerCode = s?.customerCode ?? '';
    _invoiceDisplayText = s?.invoiceNumber ?? '';
    if (s?.clearingAgentName != null && s!.clearingAgentName!.isNotEmpty) {
      _clearingAgentSearchCtrl.text = s.clearingAgentName!;
    }
    _paidAmountCtrl = TextEditingController(
        text: (s?.paidAmount ?? 0.0) > 0 ? s!.paidAmount.toString() : '0');
    _discountAmountCtrl.addListener(_onFinancialsChanged);
    _paidAmountCtrl.addListener(_onFinancialsChanged);
    _selectedPaymentSourceType = s?.paymentSourceType ?? 'bank';
    _selectedTreasuryId = s?.paymentTreasuryId;
    _selectedBankAccountId = s?.paymentBankAccountId;
    _selectedTreasuryCurrency = s?.currency ?? s?.currencyCode ?? 'EGP';

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ExportShipmentCubit>().loadForm(widget.shipment?.id);
      _loadClearingAgents();
      _loadTreasuriesAndBanks();
      _loadAvailablePackingOrders();
    });
    _packingOrdersSub =
        DataChangeEventBus.instance.packingOrdersStream.listen((_) {
      _loadAvailablePackingOrders();
    });
    _exportsSub = DataChangeEventBus.instance.exportsStream.listen((_) {
      _loadAvailablePackingOrders();
    });
  }

  Future<void> _loadClearingAgents() async {
    try {
      final agents = await ClearingAgentDao().getAll(limit: 200);
      if (!mounted) return;
      setState(() => _clearingAgents = agents);
    } catch (_) {}
  }

  Future<void> _loadTreasuriesAndBanks() async {
    try {
      final results = await Future.wait([
        Supabase.instance.client.from('treasuries').select('id,name,type,treasury_balances(currency,balance)'),
        Supabase.instance.client.from('bank_accounts').select('id,name,currency,balance'),
      ]);
      if (!mounted) return;
      setState(() {
        _treasuries = List<Map<String, dynamic>>.from(results[0] as List)
            .where((t) => t['type']?.toString() != 'employee')
            .toList();
        _bankAccounts = List<Map<String, dynamic>>.from(results[1] as List);
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _countryOfOriginCtrl.dispose();
    _shipmentNoCtrl.dispose();
    _manualCodeCtrl.dispose();
    _customerSearchCtrl.dispose();
    _invoiceSearchCtrl.dispose();
    _contactPersonCtrl.dispose();
    _countryCtrl.dispose();
    _destinationAddressCtrl.dispose();
    _containerNoCtrl.dispose();
    _vesselNameCtrl.dispose();
    _dataLoggerNoCtrl.dispose();
    _awbCtrl.dispose();
    _portOfLoadingCtrl.dispose();
    _portOfDestCtrl.dispose();
    _paymentTermsCtrl.dispose();
    _termsConditionsCtrl.dispose();
    _internalNotesCtrl.dispose();
    _invoiceNoCtrl.dispose();
    _transportModeCtrl.dispose();
    _clearingAgentSearchCtrl.dispose();
    _discountAmountCtrl.removeListener(_onFinancialsChanged);
    _paidAmountCtrl.removeListener(_onFinancialsChanged);
    _discountAmountCtrl.dispose();
    _discountReasonCtrl.dispose();
    _paidAmountCtrl.dispose();
    _exchangeRateCtrl.dispose();
    _packingOrdersSub?.cancel();
    _exportsSub?.cancel();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<List<PackingOrderModel>> _loadAvailablePackingOrders() async {
    try {
      final orders = await _packingOrderDao.getAvailableForShipment();
      if (mounted) {
        setState(() => _availablePackingOrders = orders);
      }
      return orders;
    } catch (_) {
      return _availablePackingOrders;
    }
  }

  void _onFinancialsChanged() {
    if (mounted) setState(() {});
  }

  String _currencySymbol() {
    switch (_currency) {
      case 'EUR':
        return '€';
      case 'USD':
        return '\$';
      case 'GBP':
        return '£';
      case 'EGP':
        return 'ج.م';
      default:
        return _currency;
    }
  }

  void _onCustomerSelected(CustomerModel cu) {
    setState(() {
      _selectedCustomerId = cu.id;
      _selectedAddressIndex = null;
      _customerDisplayText = cu.name;
      _customerCode = cu.code;
      _customerSearchCtrl.text = _customerDisplayText;
      if (cu.currency.isNotEmpty) {
        _currency = cu.currency;
        if (_currency != 'EGP') {
          CurrencyConversionService.instance.getRate(_currency).then((rate) {
            if (mounted && rate > 0) {
              setState(() => _exchangeRateCtrl.text = rate.toStringAsFixed(2));
            }
          });
        } else {
          _exchangeRateCtrl.text = '1.00';
        }
      }
      if (cu.country.isNotEmpty) {
        _countryCtrl.text = cu.country;
      }
      final defaults = ClientDefaults.forName(cu.name);
      if (defaults != null) {
        if (_contactPersonCtrl.text.trim().isEmpty) {
          _contactPersonCtrl.text = defaults.contact;
        }
        if (_destinationAddressCtrl.text.trim().isEmpty) {
          _destinationAddressCtrl.text = defaults.destinationAddress;
        }
        _incoterm = defaults.incoterm;
        if (_portOfDestCtrl.text.trim().isEmpty) {
          _portOfDestCtrl.text =
              _transportMode == 'sea' ? defaults.seaPort : defaults.airPort;
        }
      }
    });
    _autoGenerateManualCode(cu.code);
  }

  Future<void> _autoGenerateManualCode(String customerCode) async {
    if (widget.shipment != null) return;
    try {
      final year =
          _shipmentDate != null ? _shipmentDate!.year : DateTime.now().year;
      final nextNo = await context
          .read<ExportShipmentCubit>()
          .getNextShipmentNo(customerCode, year);
      if (!mounted) return;
      final manual = nextNo.split('/').last;
      setState(() {
        _manualCodeCtrl.text = manual;
        _invoiceNoCtrl.text = _getShipmentNo();
      });
    } catch (_) {}
  }

  void _onTransportModeChanged(String mode) {
    setState(() {
      _transportMode = mode;
      _transportModeCtrl.text = mode == 'air' ? 'By Air' : 'By Sea';
      _portOfLoadingCtrl.text = mode == 'sea'
          ? 'ميناء شرق بورسعيد'
          : 'مطار القاهرة الدولي (CAI Airport)';
      _selectedClearingAgentId = null;
      _clearingAgentSearchCtrl.clear();
      if (mode == 'air') {
        _vesselNameCtrl.clear();
        _containerNoCtrl.clear();
        _dataLoggerNoCtrl.clear();
      } else {
        _awbCtrl.clear();
      }
    });
    if (_selectedCustomerId != null) {
      final match = _customers.where((c) => c.id == _selectedCustomerId);
      if (match.isNotEmpty) {
        final defaults = ClientDefaults.forName(match.first.name);
        if (defaults != null) {
          _portOfDestCtrl.text =
              mode == 'sea' ? defaults.seaPort : defaults.airPort;
        }
      }
    }
  }

  void _save() {
    if (!ReadOnlyGuard.check(context)) return;
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('يرجى اختيار العميل'),
            backgroundColor: AppTheme.warning),
      );
      return;
    }
    final shipmentNo = _getShipmentNo();
    if (shipmentNo.trim().isEmpty || shipmentNo.contains('----')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال رقم الشحنة (الكود اليدوي)'),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }
    if (_countryCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال دولة الوجهة'),
          backgroundColor: AppTheme.warning),
      );
      return;
    }
    final validItems =
        _items.where((i) => i.nameCtrl.text.trim().isNotEmpty).toList();
    if (validItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إضافة صنف واحد على الأقل'),
          backgroundColor: AppTheme.warning),
      );
      return;
    }
    for (final i in validItems) {
      final qty = int.tryParse(i.qtyCtrl.text) ?? 0;
      final price = double.tryParse(i.priceCtrl.text) ?? 0;
      final netWt = double.tryParse(i.netWtCtrl.text) ?? 0;
      if (qty <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('الكمية يجب أن تكون أكبر من 0 للصنف: ${i.nameCtrl.text}'),
            backgroundColor: AppTheme.warning,
          ),
        );
        return;
      }
      if (i._maxCartons != null && qty > i._maxCartons!) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('الكمية ($qty) تتجاوز المتبقي (${i._maxCartons}) للصنف: ${i.nameCtrl.text}'),
            backgroundColor: AppTheme.warning,
          ),
        );
        return;
      }
      final exportPrice = double.tryParse(i.exportPricePerCartonCtrl.text.trim()) ?? 0;
      if (exportPrice <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'سعر الكرتونة التصديري يجب أن يكون أكبر من 0 للصنف: ${i.nameCtrl.text}'),
            backgroundColor: AppTheme.warning,
          ),
        );
        return;
      }
      if (netWt <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'الوزن الصافي يجب أن يكون أكبر من 0 للصنف: ${i.nameCtrl.text}'),
            backgroundColor: AppTheme.warning,
          ),
        );
        return;
      }
    }
    setState(() => _isSaving = true);
    final itemsData = _items
        .where((i) => i.nameCtrl.text.trim().isNotEmpty)
        .map((i) => {
              'name': i.nameCtrl.text.trim(),
              'product_name': i.invoiceProductCtrl.text.trim().isNotEmpty
                  ? i.invoiceProductCtrl.text.trim()
                  : i.nameCtrl.text.trim(),
              'productId': i.productId,
              'grade': i.grade,
              'hsCode': i.hsCode,
              'countryOfOrigin': _countryOfOriginCtrl.text.trim().isNotEmpty
                  ? _countryOfOriginCtrl.text.trim()
                  : 'Egypt',
              'qty': i.qtyCtrl.text.trim(),
              'price': i.priceCtrl.text.trim(),
              'exportPricePerCarton': i.exportPricePerCartonCtrl.text.trim(),
              'weightPerCarton': i.weightPerCartonCtrl.text.trim(),
              'netWt': i.netWtCtrl.text.trim(),
              'grossWt': i.grossWtCtrl.text.trim(),
              'amount': i.amountCtrl.text.trim(),
              'pallets': i.palletsCtrl.text.trim(),
              if (i.packingOrderId != null)
                'packingOrderId': i.packingOrderId,
              if (i.lineId != null)
                'packing_order_line_id': i.lineId,
              'quantity': i.qtyCtrl.text.trim(),
            })
        .toList();
    final rate = _currency == 'EGP'
        ? 1.0
        : (double.tryParse(_exchangeRateCtrl.text.trim()) ?? 1.0);
    final grossRevenueForeign =
        _items.fold<double>(0.0, (sum, i) => sum + i.totalRevenueForeign);
    final discountForeign =
        double.tryParse(_discountAmountCtrl.text.trim()) ?? 0.0;
    final discountEgp = discountForeign * rate;
    final grossRevenueEgp = grossRevenueForeign * rate;
    final netRevenueEgp =
        (grossRevenueEgp - discountEgp).clamp(0.0, double.infinity);
    final totalCostEgp =
        _items.fold<double>(0.0, (sum, i) => sum + i.totalCostEgp);
    final netProfitEgp = netRevenueEgp - totalCostEgp;
    final paidAmount =
        double.tryParse(_paidAmountCtrl.text.trim()) ?? 0.0;

    final shipment = ExportShipmentModel(
      id: widget.shipment?.id,
      shipmentNo: _getShipmentNo(),
      customerId: _selectedCustomerId?.toString(),
      customerName:
          _customerDisplayText.isNotEmpty ? _customerDisplayText : null,
      customerCode: _customerCode.isNotEmpty ? _customerCode : null,
      clearingAgentId: _selectedClearingAgentId?.toString(),
      clearingAgentName: _clearingAgentSearchCtrl.text.trim().isNotEmpty
          ? _clearingAgentSearchCtrl.text.trim()
          : null,
      invoiceId: _selectedInvoiceId,
      invoiceNumber: shipmentNo,
      contactPerson: _contactPersonCtrl.text.trim().isEmpty
          ? null
          : _contactPersonCtrl.text.trim(),
      countryOfOrigin: _countryOfOriginCtrl.text.trim().isNotEmpty
          ? _countryOfOriginCtrl.text.trim()
          : 'Egypt',
      country:
          _countryCtrl.text.trim().isEmpty ? null : _countryCtrl.text.trim(),
      destinationAddress: _destinationAddressCtrl.text.trim().isEmpty
          ? null
          : _destinationAddressCtrl.text.trim(),
      containerNo: _transportMode == 'sea'
          ? (_containerNoCtrl.text.trim().isNotEmpty
              ? _containerNoCtrl.text.trim()
              : 'TBA')
          : null,
      blNumber: _awbCtrl.text.trim().isNotEmpty ? _awbCtrl.text.trim() : 'TBA',
      vesselName: _transportMode == 'sea'
          ? (_vesselNameCtrl.text.trim().isNotEmpty
              ? _vesselNameCtrl.text.trim()
              : 'TBA')
          : null,
      dataLoggerNo: _transportMode == 'sea'
          ? (_dataLoggerNoCtrl.text.trim().isNotEmpty
              ? _dataLoggerNoCtrl.text.trim()
              : 'TBA')
          : null,
      portOfLoading: _portOfLoadingCtrl.text.trim().isEmpty
          ? null
          : _portOfLoadingCtrl.text.trim(),
      portOfDestination: _portOfDestCtrl.text.trim().isEmpty
          ? null
          : _portOfDestCtrl.text.trim(),
      transportMode: _transportMode,
      palletsCount: _items.fold(
          0, (sum, i) => sum + (int.tryParse(i.palletsCtrl.text) ?? 0)),
      cartonsCount:
          _items.fold(0, (sum, i) => sum + (int.tryParse(i.qtyCtrl.text) ?? 0)),
      netWeight: _items.fold(
          0.0, (sum, i) => sum + (double.tryParse(i.netWtCtrl.text) ?? 0)),
      grossWeight: _items.fold(
          0.0, (sum, i) => sum + (double.tryParse(i.grossWtCtrl.text) ?? 0)),
      incoterm: _incoterm,
      paymentTerms: _paymentTermsCtrl.text.trim().isEmpty
          ? null
          : _paymentTermsCtrl.text.trim(),
      currency: _currency,
      currencyCode: _currency,
      exchangeRate: rate,
      totalRevenueForeign: grossRevenueForeign,
      totalRevenueEgp: grossRevenueEgp,
      netProfitEgp: netProfitEgp,
      termsConditions: _termsConditionsCtrl.text.trim().isEmpty
          ? null
          : _termsConditionsCtrl.text.trim(),
      internalNotes: _internalNotesCtrl.text.trim().isEmpty
          ? null
          : _internalNotesCtrl.text.trim(),
      status: widget.shipment?.status ?? 'draft',
      shipmentDate: _shipmentDate ?? DateTime.now(),
      discountAmount: discountForeign,
      discountReason: _discountReasonCtrl.text.trim().isEmpty
          ? null
          : _discountReasonCtrl.text.trim(),
      paidAmount: paidAmount,
      paymentSourceType: _selectedPaymentSourceType ?? 'bank',
      paymentTreasuryId: _selectedTreasuryId,
      paymentBankAccountId: _selectedBankAccountId,
    );
    context.read<ExportShipmentCubit>().save(shipment, items: itemsData);
  }

  void _openPreview() {
    final rate = _currency == 'EGP'
        ? 1.0
        : (double.tryParse(_exchangeRateCtrl.text.trim()) ?? 1.0);
    final grossRevenueForeign =
        _items.fold<double>(0.0, (sum, i) => sum + i.totalRevenueForeign);
    final discountForeign =
        double.tryParse(_discountAmountCtrl.text.trim()) ?? 0.0;
    final discountEgp = discountForeign * rate;
    final grossRevenueEgp = grossRevenueForeign * rate;
    final netRevenueEgp =
        (grossRevenueEgp - discountEgp).clamp(0.0, double.infinity);
    final totalCostEgp =
        _items.fold<double>(0.0, (sum, i) => sum + i.totalCostEgp);
    final netProfitEgp = netRevenueEgp - totalCostEgp;
    final paidAmount =
        double.tryParse(_paidAmountCtrl.text.trim()) ?? 0.0;

    final shipment = ExportShipmentModel(
      shipmentNo: _getShipmentNo(),
      customerId: _selectedCustomerId?.toString(),
      customerName:
          _customerDisplayText.isNotEmpty ? _customerDisplayText : null,
      customerCode: _customerCode.isNotEmpty ? _customerCode : null,
      clearingAgentId: _selectedClearingAgentId?.toString(),
      clearingAgentName: _clearingAgentSearchCtrl.text.trim().isNotEmpty
          ? _clearingAgentSearchCtrl.text.trim()
          : null,
      invoiceId: _selectedInvoiceId,
      invoiceNumber: _getShipmentNo(),
      contactPerson: _contactPersonCtrl.text.trim().isEmpty
          ? null
          : _contactPersonCtrl.text.trim(),
      countryOfOrigin: _countryOfOriginCtrl.text.trim().isNotEmpty
          ? _countryOfOriginCtrl.text.trim()
          : 'Egypt',
      country:
          _countryCtrl.text.trim().isEmpty ? null : _countryCtrl.text.trim(),
      destinationAddress: _destinationAddressCtrl.text.trim().isEmpty
          ? null
          : _destinationAddressCtrl.text.trim(),
      containerNo: _transportMode == 'sea'
          ? (_containerNoCtrl.text.trim().isNotEmpty
              ? _containerNoCtrl.text.trim()
              : null)
          : null,
      blNumber: _awbCtrl.text.trim().isNotEmpty ? _awbCtrl.text.trim() : null,
      vesselName: _transportMode == 'sea'
          ? (_containerNoCtrl.text.trim().isNotEmpty
              ? _containerNoCtrl.text.trim()
              : null)
          : null,
      dataLoggerNo: _transportMode == 'sea'
          ? (_dataLoggerNoCtrl.text.trim().isNotEmpty
              ? _dataLoggerNoCtrl.text.trim()
              : null)
          : null,
      portOfLoading: _portOfLoadingCtrl.text.trim().isEmpty
          ? null
          : _portOfLoadingCtrl.text.trim(),
      portOfDestination: _portOfDestCtrl.text.trim().isEmpty
          ? null
          : _portOfDestCtrl.text.trim(),
      transportMode: _transportMode,
      palletsCount: _items.fold(
          0, (sum, i) => sum + (int.tryParse(i.palletsCtrl.text) ?? 0)),
      cartonsCount:
          _items.fold(0, (sum, i) => sum + (int.tryParse(i.qtyCtrl.text) ?? 0)),
      netWeight: _items.fold(
          0.0, (sum, i) => sum + (double.tryParse(i.netWtCtrl.text) ?? 0)),
      grossWeight: _items.fold(
          0.0, (sum, i) => sum + (double.tryParse(i.grossWtCtrl.text) ?? 0)),
      incoterm: _incoterm,
      paymentTerms: _paymentTermsCtrl.text.trim().isNotEmpty
          ? _paymentTermsCtrl.text.trim()
          : null,
      currency: _currency,
      currencyCode: _currency,
      exchangeRate: rate,
      totalRevenueForeign: grossRevenueForeign,
      totalRevenueEgp: grossRevenueEgp,
      netProfitEgp: netProfitEgp,
      termsConditions: _buildTermsText(),
      status: widget.shipment?.status ?? 'draft',
      shipmentDate: _shipmentDate,
      discountAmount: discountForeign,
      discountReason: _discountReasonCtrl.text.trim().isEmpty
          ? null
          : _discountReasonCtrl.text.trim(),
      paidAmount: paidAmount,
      paymentSourceType: _selectedPaymentSourceType ?? 'bank',
      paymentTreasuryId: _selectedTreasuryId,
      paymentBankAccountId: _selectedBankAccountId,
    );
    final itemsData = _items
        .where((i) => i.nameCtrl.text.trim().isNotEmpty)
        .map((i) => {
              'name': i.nameCtrl.text.trim(),
              'product_name': i.invoiceProductCtrl.text.trim().isNotEmpty
                  ? i.invoiceProductCtrl.text.trim()
                  : i.nameCtrl.text.trim(),
              'productId': i.productId,
              'grade': i.grade,
              'hsCode': i.hsCode,
              'countryOfOrigin': _countryOfOriginCtrl.text.trim().isNotEmpty
                  ? _countryOfOriginCtrl.text.trim()
                  : 'Egypt',
              'qty': i.qtyCtrl.text.trim(),
              'price': i.priceCtrl.text.trim(),
              'exportPricePerCarton': i.exportPricePerCartonCtrl.text.trim(),
              'weightPerCarton': i.weightPerCartonCtrl.text.trim(),
              'netWt': i.netWtCtrl.text.trim(),
              'grossWt': i.grossWtCtrl.text.trim(),
              'amount': i.amountCtrl.text.trim(),
              'pallets': i.palletsCtrl.text.trim(),
            })
        .toList();
    final customer = _selectedCustomerId != null
        ? _customers.where((c) => c.id == _selectedCustomerId).firstOrNull
        : null;
    final agent = _selectedClearingAgentId != null
        ? _clearingAgents
            .where((a) => a.id == _selectedClearingAgentId)
            .firstOrNull
        : null;
    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InvoicePreviewPage(
            shipment: shipment,
            itemsData: itemsData,
            customer: customer,
            clearingAgent: agent,
          ),
        ));
  }

  String _getShipmentNo() {
    final year = _shipmentDate != null
        ? (_shipmentDate!.year % 100).toString().padLeft(2, '0')
        : (DateTime.now().year % 100).toString().padLeft(2, '0');
    final code = _customerCode.isNotEmpty ? _customerCode : '----';
    final manual =
        _manualCodeCtrl.text.isNotEmpty ? _manualCodeCtrl.text : '----';
    return '$year/$code/$manual';
  }

  void _openCreditNote() {
    final discount = double.tryParse(_discountAmountCtrl.text.trim()) ?? 0.0;
    if (discount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد خصم لإصدار إشعار دائن'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final shipment = ExportShipmentModel(
      id: widget.shipment?.id,
      shipmentNo: _getShipmentNo(),
      customerId: _selectedCustomerId?.toString(),
      customerName:
          _customerDisplayText.isNotEmpty ? _customerDisplayText : null,
      customerCode: _customerCode.isNotEmpty ? _customerCode : null,
      country:
          _countryCtrl.text.trim().isEmpty ? null : _countryCtrl.text.trim(),
      destinationAddress: _destinationAddressCtrl.text.trim().isEmpty
          ? null
          : _destinationAddressCtrl.text.trim(),
      vesselName: _transportMode == 'sea'
          ? (_vesselNameCtrl.text.trim().isNotEmpty
              ? _vesselNameCtrl.text.trim()
              : null)
          : null,
      containerNo: _transportMode == 'sea'
          ? (_containerNoCtrl.text.trim().isNotEmpty
              ? _containerNoCtrl.text.trim()
              : null)
          : null,
      blNumber: _awbCtrl.text.trim().isNotEmpty ? _awbCtrl.text.trim() : null,
      currencyCode: _currency,
      discountAmount: discount,
      discountReason: _discountReasonCtrl.text.trim().isEmpty
          ? null
          : _discountReasonCtrl.text.trim(),
      shipmentDate: _shipmentDate,
      transportMode: _transportMode,
      netWeight: _items.fold<double>(0.0, (sum, i) => sum + (double.tryParse(i.netWtCtrl.text) ?? 0)),
      totalRevenueForeign: _items.fold<double>(0.0, (sum, i) {
        final ep = double.tryParse(i.exportPricePerCartonCtrl.text) ?? 0;
        final qty = int.tryParse(i.qtyCtrl.text) ?? 0;
        return sum + (ep * qty);
      }),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('جاري إنشاء الإشعار الدائن...'),
        duration: Duration(seconds: 2),
      ),
    );
    
    CreditNotePdfService.savePdf(
      context: context,
      shipment: shipment,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.read<ExportShipmentCubit>();
    final paidAmtForBtn = double.tryParse(_paidAmountCtrl.text) ?? 0.0;
    final hasInvalidExportPrice = _items.isEmpty ||
        _items.any((item) {
          final text = item.exportPricePerCartonCtrl.text.trim();
          if (text.isEmpty) return true;
          final p = double.tryParse(text);
          return p == null || p <= 0;
        });
    final isSaveDisabled = (paidAmtForBtn > 0 &&
            _selectedTreasuryId == null &&
            _selectedBankAccountId == null) ||
        hasInvalidExportPrice;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.cyberBg : const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: isDark ? AppTheme.cyberSurface : Colors.white,
          elevation: isDark ? 0 : 1,
          title: Text(
            widget.shipment != null
                ? 'تعديل شحنة' // ${_getShipmentNo()}
                : 'شحنة جديدة',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
          ),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : const Color(0xFF0F172A)),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? AppTheme.neonCyan : AppTheme.primary,
                  side: BorderSide(color: isDark ? AppTheme.neonCyan : AppTheme.primary, width: 1.2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                label: const Text('معاينة',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                        fontSize: 11)),
                onPressed: _openPreview,
              ),
            ),
            if ((widget.shipment?.discountAmount ?? 0) > 0) ...[
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange, width: 1.2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: const Icon(Icons.receipt_long_outlined, size: 16),
                  label: const Text('إشعار',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                          fontSize: 11)),
                  onPressed: _openCreditNote,
                ),
              ),
            ],
            const SizedBox(width: 4),
            if (!widget.isReadOnly)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSaveDisabled
                        ? (isDark ? Colors.white38 : Colors.grey.shade300)
                        : (isDark ? Colors.white : AppTheme.primary),
                    foregroundColor: isSaveDisabled
                        ? Colors.white
                        : (isDark ? AppTheme.primary : Colors.white),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: _isSaving
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: isDark ? AppTheme.primary : Colors.white))
                      : const Icon(Icons.save_outlined, size: 16),
                  label: Text(_isSaving ? 'جاري...' : 'حفظ',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 11)),
                  onPressed: _isSaving || isSaveDisabled ? null : _save,
                ),
              ),
            const SizedBox(width: 4),
          ],
        ),
        body: BlocListener<ExportShipmentCubit, ExportShipmentState>(
          listener: (context, state) async {
            if (state is ExportShipmentOperationSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(state.message),
                    backgroundColor: AppTheme.success,
                    duration: const Duration(seconds: 3)),
              );
              context.pop(true);
            } else if (state is ExportShipmentError) {
              setState(() => _isSaving = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(state.message),
                    backgroundColor: AppTheme.danger,
                    duration: const Duration(seconds: 3)),
              );
            } else if (state is ExportShipmentFormLoaded) {
              if (_shipmentNoCtrl.text.isEmpty) {
                _shipmentNoCtrl.text = state.defaults.shipmentNo;
              }
              final s = state.shipment;
              if (s != null && mounted) {
                setState(() {
                  _selectedCustomerId = s.customerId;
                  _selectedInvoiceId = s.invoiceId;
                  _selectedClearingAgentId = s.clearingAgentId;
                  _customerCode = s.customerCode ?? '';
                  _customerDisplayText = s.customerName ?? '';
                  _customerSearchCtrl.text = s.customerName ?? '';
                  _countryCtrl.text = s.country ?? '';
                  _containerNoCtrl.text = s.containerNo ?? '';
                  _vesselNameCtrl.text = s.vesselName ?? '';
                  _dataLoggerNoCtrl.text = s.dataLoggerNo ?? '';
                  _awbCtrl.text = s.blNumber ?? '';
                  _portOfLoadingCtrl.text = s.portOfLoading ?? '';
                  _portOfDestCtrl.text = s.portOfDestination ?? '';
                  _destinationAddressCtrl.text = s.destinationAddress ?? '';
                  _contactPersonCtrl.text = s.contactPerson ?? '';
                  _paymentTermsCtrl.text = s.paymentTerms ?? '';
                  _termsConditionsCtrl.text = s.termsConditions ?? '';
                  _internalNotesCtrl.text = s.internalNotes ?? '';
                  _invoiceNoCtrl.text = s.invoiceNumber ?? '';
                  _countryOfOriginCtrl.text = s.countryOfOrigin ?? 'Egypt';
                  _transportMode = s.transportMode;
                  _transportModeCtrl.text = s.transportMode == 'air' ? 'By Air' : 'By Sea';
                  _incoterm = s.incoterm ?? 'FOB';
                  _currency = s.currency ?? s.currencyCode;
                  if (s.exchangeRate > 0) {
                    _exchangeRateCtrl.text = s.exchangeRate.toStringAsFixed(2);
                  } else if (_currency != 'EGP') {
                    CurrencyConversionService.instance.getRate(_currency).then((rate) {
                      if (mounted && rate > 0) {
                        setState(() => _exchangeRateCtrl.text = rate.toStringAsFixed(2));
                      }
                    });
                  }
                  _shipmentDate = s.shipmentDate;
                  if (s.clearingAgentName != null && s.clearingAgentName!.isNotEmpty) {
                    _clearingAgentSearchCtrl.text = s.clearingAgentName!;
                  }
                  final parts = s.shipmentNo.split('/');
                  if (parts.length == 3) {
                    _manualCodeCtrl.text = parts[2];
                  }
                });
              }
              final poIds = <int>[];
              setState(() {
                _customers = state.customers;
                _invoices = state.invoices;
                if (state.items.isNotEmpty) {
                  for (final item in _items) {
                    item.dispose();
                  }
                  _items.clear();
                  for (final row in state.items) {
                    final item = _ShipmentItem();
                    item.nameCtrl.text = row['product_name']?.toString() ?? '';
                    item.invoiceProductCtrl.text = row['invoice_product_name']?.toString() ?? '';
                    item.qtyCtrl.text = row['quantity']?.toString() ?? '';
                    item.priceCtrl.text = row['price']?.toString() ?? '';
                    item.exportPricePerCartonCtrl.text =
                        row['export_price_per_carton']?.toString() ?? '';
                    item.weightPerCartonCtrl.text =
                        row['weight_per_carton']?.toString() ?? '15';
                    item.netWtCtrl.text = row['net_weight']?.toString() ?? '';
                    item.grossWtCtrl.text =
                        row['gross_weight']?.toString() ?? '';
                    item.amountCtrl.text = row['amount']?.toString() ?? '';
                    item.palletsCtrl.text = row['pallets']?.toString() ?? '';
                    if (row['packing_order_id'] != null) {
                      item.packingOrderId =
                          int.tryParse(row['packing_order_id'].toString());
                      if (row['packing_order_line_id'] != null) {
                        item.lineId =
                            int.tryParse(row['packing_order_line_id'].toString());
                      }
                      if (item.packingOrderId != null) {
                        poIds.add(item.packingOrderId!);
                      }
                    }
                    _items.add(item);
                  }
                  _totalExtraCosts = state.totalExtraCosts;
                } else if (_items.isEmpty) {
                  _items.add(_ShipmentItem());
                  _totalExtraCosts = 0.0;
                }
              });
              if (poIds.isNotEmpty) {
                for (final poId in poIds) {
                  final freshPo = await _packingOrderDao.getById(poId);
                  if (freshPo != null) {
                    final matchingItems = _items.where((i) => i.packingOrderId == poId);
                    for (final mItem in matchingItems) {
                      mItem.packingOrderNumber = freshPo.orderNumber;
                      mItem.exportShipmentNo = freshPo.exportShipmentNo;
                      mItem.customerName = freshPo.customerName;
                      final currentQty = int.tryParse(mItem.qtyCtrl.text) ?? 0;
                      if (mItem.lineId != null && freshPo.lines.isNotEmpty) {
                        final line = freshPo.lines
                            .where((l) => l.id == mItem.lineId.toString())
                            .firstOrNull;
                        if (line != null) {
                          mItem._maxCartons =
                              (line.cartonCount - line.soldCartons) + currentQty;
                          continue;
                        }
                      }
                      mItem._maxCartons = freshPo.remainingCartons + currentQty;
                    }
                  }
                }
                if (mounted) setState(() {});
              }
              _restoreSelections();
              _refreshPackingOrderData();
            }
          },
          child: BlocBuilder<ExportShipmentCubit, ExportShipmentState>(
            builder: (context, state) {
              if (state is ExportShipmentLoading ||
                  (state is ExportShipmentInitial)) {
                return const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary));
              }
              return Form(
                key: _formKey,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    final isDesktop = w >= 1024;
                    final isTablet = w >= 700 && w < 1024;

                    if (isDesktop) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 320, child: _buildLeftPanel(c, true)),
                          const VerticalDivider(width: 1),
                          Expanded(child: _buildRightPanel()),
                        ],
                      );
                    }

                    // Tablet & Phone: stacked layout
                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLeftPanel(c, false),
                          const Divider(height: 1),
                          _buildRightPanelStacked(isTablet),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildRightPanelStacked(bool isTablet) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? AppTheme.cyberBg : const Color(0xFFF8FAFC),
      padding: const EdgeInsets.all(16),
      child: AbsorbPointer(
        absorbing: widget.isReadOnly,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSelectedCustomerCard(),
          _buildAddressPicker(),
          _sectionTitle('بيانات الشحن'),
          const SizedBox(height: 12),
          if (_transportMode == 'sea') ...[
            AppTextField(
                label: 'BL No.',
                controller: _awbCtrl,
                hint: 'رقم بوليصة الشحن',
                keyboardType: TextInputType.text),
            const SizedBox(height: 12),
            AppTextField(
                label: 'اسم السفينة',
                controller: _vesselNameCtrl,
                hint: 'TBA'),
            const SizedBox(height: 12),
            AppTextField(
                label: 'رقم الحاوية',
                controller: _containerNoCtrl,
                hint: 'مثال: MSCU1234567'),
            const SizedBox(height: 12),
            AppTextField(
                label: 'رقم مسجل البيانات (Data Logger)',
                controller: _dataLoggerNoCtrl,
                hint: 'TBA'),
          ] else ...[
            AppTextField(
              label: 'AWB',
              controller: _awbCtrl,
              hint: 'رقم بوليصة الشحن الجوي',
              keyboardType: TextInputType.text,
            ),
          ],
          const SizedBox(height: 12),
          AppTextField(
            label: 'بلد المنشأ',
            controller: _countryOfOriginCtrl,
            hint: 'Egypt',
          ),
          const SizedBox(height: 12),
          _buildCountrySearchField(),
          const SizedBox(height: 12),
          AppTextField(
            label: 'عنوان الوجهة / التفريغ',
            controller: _destinationAddressCtrl,
            hint: 'العنوان التفصيلي للوجهة',
            maxLines: 2,
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),
          _sectionTitle('الأصناف المشحونة'),
          const SizedBox(height: 12),
          ..._items
              .asMap()
              .entries
              .map((entry) => _buildItemCard(entry.key, entry.value)),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => setState(() => _items.add(_ShipmentItem())),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.neonCyan.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppTheme.neonCyan.withValues(alpha: 0.25),
                    width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle_outline,
                      color: AppTheme.neonCyan, size: 20),
                  const SizedBox(width: 8),
                  Text('إضافة صنف آخر',
                      style: TextStyle(
                          color: AppTheme.neonCyan,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildTotalsRow(),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),
          _sectionTitle('الشروط والأحكام'),
          const SizedBox(height: 12),
          _buildTermsSection(),
          const SizedBox(height: 80),
        ],
      ),
      ),
    );
  }

  Future<void> _refreshPackingOrderData() async {
    for (final item in _items) {
      if (item.packingOrderId == null) continue;
      try {
        int? remainingCartons;
        double? netWeightPerCarton;

        // Primary: use packing_order_line_id for exact per-line cost
        Map<String, dynamic>? lineData;
        if (item.lineId != null) {
          try {
            lineData = await Supabase.instance.client
                .from('packing_order_lines')
                .select()
                .eq('id', item.lineId!)
                .maybeSingle();
          } catch (e) {
            debugPrint('⚠️ Failed to fetch packing_order_line by lineId ${item.lineId}: $e');
          }
        }

        // Fallback: match by packing_order_id + product_name if lineId lookup failed
        if (lineData == null && item.nameCtrl.text.isNotEmpty) {
          try {
            final matches = await Supabase.instance.client
                .from('packing_order_lines')
                .select()
                .eq('packing_order_id', item.packingOrderId!)
                .eq('product_name', item.nameCtrl.text.trim())
                .limit(1);
            if (matches.isNotEmpty) {
              lineData = matches.first;
              debugPrint('ℹ️ Fallback: matched packing_order_line by product_name "${item.nameCtrl.text.trim()}"');
            }
          } catch (e) {
            debugPrint('⚠️ Fallback product_name match failed: $e');
          }
        }

        if (lineData != null) {
          final lineCartons = (lineData['carton_count'] as num?)?.toInt() ?? 0;
          final lineSold = (lineData['sold_cartons'] as num?)?.toInt() ?? 0;
          remainingCartons = lineCartons - lineSold;
          netWeightPerCarton = (lineData['net_weight_per_carton'] as num?)?.toDouble();

          // Auto-fix: persist correct line ID in memory for current session
          final correctLineId = lineData['id'] as int?;
          if (correctLineId != null && item.lineId != correctLineId) {
            item.lineId = correctLineId;
          }
        }

        // Primary: fetch packing order header (authoritative cost per carton after discounts)
        final po = await _packingOrderDao.getById(item.packingOrderId!);
        if (po == null || !mounted) continue;

        double cost = 0.0;
        if (lineData != null) {
          final unitCost = (lineData['final_unit_cost'] as num?)?.toDouble() ?? 0.0;
          final totalCost = (lineData['final_cost'] as num?)?.toDouble() ?? 0.0;
          final lineCartons = (lineData['carton_count'] as num?)?.toInt() ?? 0;
          if (unitCost > 0) {
            cost = unitCost;
          } else if (totalCost > 0 && lineCartons > 0) {
            cost = totalCost / lineCartons;
          }
        }
        if (cost <= 0) {
          cost = po.packingCostPerCarton;
        }
        if (cost <= 0 && po.fruitTypeId != null) {
          try {
            final fallbackLine = await Supabase.instance.client
                .from('packing_order_lines')
                .select('final_cost, carton_count, final_unit_cost')
                .eq('fruit_type_id', po.fruitTypeId!)
                .gt('final_cost', 0)
                .order('id', ascending: false)
                .limit(1)
                .maybeSingle();
            if (fallbackLine != null) {
              final fCost = (fallbackLine['final_cost'] as num?)?.toDouble() ?? 0.0;
              final fQty = (fallbackLine['carton_count'] as num?)?.toInt() ?? 0;
              if (fCost > 0 && fQty > 0) {
                cost = fCost / fQty;
              } else {
                cost = (fallbackLine['final_unit_cost'] as num?)?.toDouble() ?? 0.0;
              }
            }
          } catch (_) {}
        }

        setState(() {
          item.packingOrderNumber = po.orderNumber;
          item.priceCtrl.text = cost.toStringAsFixed(2);
          final currentQty = int.tryParse(item.qtyCtrl.text) ?? 0;
          if (currentQty == 0) {
            item.qtyCtrl.text = (remainingCartons ?? po.remainingCartons).toString();
          }
          item.weightPerCartonCtrl.text =
              (netWeightPerCarton ?? po.netWeightPerCarton).toStringAsFixed(0);
          item.recalculate();
        });
      } catch (_) {}
    }
  }

  Future<void> _refreshItemCost(_ShipmentItem item) async {
    if (item.packingOrderId == null) return;
    try {
      final po = await _packingOrderDao.getById(item.packingOrderId!);
      if (po == null || !mounted) return;

      double cost = po.packingCostPerCarton;
      if (cost <= 0 && item.lineId != null) {
        try {
          final lineData = await Supabase.instance.client
              .from('packing_order_lines')
              .select('final_unit_cost, final_cost, carton_count')
              .eq('id', item.lineId!)
              .maybeSingle();
          if (lineData != null) {
            final totalCost = (lineData['final_cost'] as num?)?.toDouble() ?? 0.0;
            final lineCartons = (lineData['carton_count'] as num?)?.toInt() ?? 0;
            if (totalCost > 0 && lineCartons > 0) {
              cost = totalCost / lineCartons;
            } else {
              final unitCost = (lineData['final_unit_cost'] as num?)?.toDouble() ?? 0.0;
              if (unitCost > 0) cost = unitCost;
            }
          }
        } catch (_) {}
      }

      setState(() {
        item.priceCtrl.text = cost.toStringAsFixed(2);
        item.recalculate();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تحديث تكلفة الكرتونة لأمر التعبئة (${po.orderNumber}) إلى ${cost.toStringAsFixed(2)} ج.م',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: AppTheme.success,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ _refreshItemCost error: $e');
    }
  }

  void _restoreSelections() {
    if (_selectedCustomerId != null) {
      final match = _customers.where((c) => c.id == _selectedCustomerId);
      if (match.isNotEmpty) {
        final cu = match.first;
        _customerDisplayText = cu.name;
        _customerCode = cu.code;
        _customerSearchCtrl.text = _customerDisplayText;
        if (widget.shipment != null && widget.shipment!.shipmentNo.isNotEmpty) {
          final parts = widget.shipment!.shipmentNo.split('/');
          if (parts.length == 3) {
            _manualCodeCtrl.text = parts[2];
          }
          _invoiceNoCtrl.text = widget.shipment!.shipmentNo;
        }
        
        if (_destinationAddressCtrl.text.isNotEmpty) {
          final addrText = _destinationAddressCtrl.text.trim();
          for (int i = 0; i < cu.addresses.length; i++) {
            final a = cu.addresses[i];
            final addrLine = a['address_line_1']?.toString() ?? '';
            if (addrLine.trim() == addrText) {
              _selectedAddressIndex = i;
              break;
            }
          }
        }
        setState(() {});
      }
    }
    if (_selectedInvoiceId != null) {
      final match = _invoices.where((inv) {
        final invId = inv is Map ? inv['id'] : null;
        return invId == _selectedInvoiceId;
      });
      if (match.isNotEmpty) {
        final inv = match.first;
        final invNo = inv is Map ? inv['invoice_number']?.toString() : '';
        _invoiceDisplayText = invNo ?? '';
        _invoiceSearchCtrl.text = _getShipmentNo();
        setState(() {});
      }
    }
    if (_selectedClearingAgentId != null &&
        _clearingAgentSearchCtrl.text.isEmpty) {
      final match =
          _clearingAgents.where((a) => a.id == _selectedClearingAgentId);
      if (match.isNotEmpty) {
        _clearingAgentSearchCtrl.text = match.first.name;
        setState(() {});
      }
    }
  }

  String? _buildTermsText() {
    final lines = <String>[
      'TERMS OF SALE AND OTHER COMMENTS',
      'TERMS AND CONDITIONS',
      '',
      'Fruity Farms',
      'Port Of Loading: ${_portOfLoadingCtrl.text}',
      'Port Of Destination: ${_portOfDestCtrl.text}',
      'Terms Of Payment: ${_paymentTermsCtrl.text}',
      'Mode Of Transport: ${_transportModeCtrl.text}',
      '',
      'All Banking Charges Out Of Egypt Including Remitting Charges Are On Applicants Account',
      'I Certify The Above To Be True And Correct To The Best Of My Knowledge',
    ];
    return lines.join('\n');
  }

  Widget _sectionTitle(String t) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fontSize = constraints.maxWidth < 400 ? 16.0 : 18.0;
        return Text(t,
            style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontFamily: 'Cairo'));
      },
    );
  }

  Widget _termsField(String label, TextEditingController ctrl) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            textAlign: TextAlign.left,
            style: TextStyle(
                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo')),
        const SizedBox(height: 2),
        TextField(
          controller: ctrl,
          textAlign: TextAlign.left,
          style: TextStyle(
              color: isDark ? AppTheme.textPrimary : const Color(0xFF0F172A), fontSize: 13, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
            filled: false,
            border: UnderlineInputBorder(
                borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
            focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppTheme.primary, width: 1.5)),
          ),
        ),
      ],
    );
  }

  Widget _formLabel(String t) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t,
            style: TextStyle(
                color: isDark ? AppTheme.textSecondary : const Color(0xFF1E293B),
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
                fontSize: 13)),
      );
  }

  Widget _buildLeftPanel(ExportShipmentCubit c, bool isDesktop) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Widget content = AbsorbPointer(
      absorbing: widget.isReadOnly,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('معلومات الشحنة'),
            const SizedBox(height: 12),
            _formLabel('رقم الشحنة'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.neonCyan.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.tag, size: 16, color: AppTheme.neonCyan),
                const SizedBox(width: 8),
                Expanded(
                  child: UIUtils.shipmentNoText(
                    _getShipmentNo(),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.neonCyan,
                        fontFamily: 'Cairo'),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Text('تلقائي',
                      style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.success,
                          fontFamily: 'Cairo')),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            AppTextField(
              label: 'الكود اليدوي',
              controller: _manualCodeCtrl,
              hint: 'مثال: 001',
              keyboardType: TextInputType.text,
              onChanged: (v) => setState(() {}),
            ),
            const SizedBox(height: 12),
            _formLabel('تاريخ الشحن'),
            InkWell(
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _shipmentDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                  builder: (context, child) => Theme(
                    data: isDark
                        ? ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppTheme.primary))
                        : ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: AppTheme.primary)),
                    child: child!,
                  ),
                );
                if (date != null) setState(() => _shipmentDate = date);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: isDark ? AppTheme.neonCyan.withValues(alpha: 0.3) : const Color(0xFFCBD5E1)),
                  borderRadius: BorderRadius.circular(8),
                  color: isDark ? AppTheme.cyberSurface : const Color(0xFFF1F5F9),
                ),
                child: Row(children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 16, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _shipmentDate != null
                          ? AppUtils.formatDate(_shipmentDate!)
                          : 'اختر التاريخ',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF0F172A), fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            AppSearchField<CustomerModel>(
              label: 'العميل (تصدير)',
              controller: _customerSearchCtrl,
              isRequired: true,
              hint: 'ابحث عن عميل تصدير بالاسم أو الكود...',
              prefixIcon: const Icon(Icons.flight_takeoff, size: 18, color: Colors.lightBlueAccent),
              highlightColor: AppTheme.primary.withValues(alpha: 0.5),
              suggestionsCallback: (pattern) {
                final exportList = _customers.where((cu) => cu.customerType != 'local').toList();
                if (pattern.isEmpty) return exportList;
                final lower = pattern.toLowerCase();
                return exportList
                    .where((cu) =>
                        cu.name.toLowerCase().contains(lower) ||
                        cu.code.toLowerCase().contains(lower))
                    .toList();
              },
              itemBuilder: (context, cu) {
                return ListTile(
                  title: Text(cu.name,
                      style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  subtitle: Text(cu.name,
                      style: TextStyle(
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                          fontFamily: 'Cairo',
                          fontSize: 13)),
                );
              },
              onSelected: _onCustomerSelected,
            ),
            const SizedBox(height: 12),
            _formLabel('وسيلة النقل'),
            _buildTransportRadios(),
            const SizedBox(height: 12),
            AppSearchField<ClearingAgentModel>(
              key: ValueKey('clearing_agent_$_transportMode'),
              label: _transportMode == 'sea' ? 'المخلص البحري' : 'المخلص الجوي',
              controller: _clearingAgentSearchCtrl,
              hint: _transportMode == 'sea'
                  ? 'ابحث عن مخلص بحري...'
                  : 'ابحث عن مخلص جوي...',
              prefixIcon: Icon(
                  _transportMode == 'sea' ? Icons.sailing : Icons.flight,
                  size: 18),
              highlightColor: AppTheme.primary.withValues(alpha: 0.5),
              suggestionsCallback: (pattern) {
                final typeFilter = _transportMode == 'sea' ? 'بحري' : 'جوي';
                return _clearingAgents
                    .where((a) =>
                        a.brokerType == typeFilter &&
                        (pattern.isEmpty ||
                            a.name
                                .toLowerCase()
                                .contains(pattern.toLowerCase())))
                    .toList();
              },
              itemBuilder: (context, agent) {
                return ListTile(
                  title: Text(agent.name,
                      style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  subtitle: Text('${agent.phone} - ${agent.city}',
                      style: TextStyle(
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                          fontFamily: 'Cairo',
                          fontSize: 13)),
                );
              },
              onSelected: (agent) {
                setState(() {
                  _selectedClearingAgentId = agent.id;
                  _clearingAgentSearchCtrl.text = agent.name;
                });
              },
            ),
            const SizedBox(height: 12),
            _formLabel('العملة'),
            _buildCurrencyRadios(),
            if (_currency != 'EGP') ...[
              const SizedBox(height: 12),
              AppTextField(
                label: 'سعر الصرف ($_currency → ج.م)',
                controller: _exchangeRateCtrl,
                readOnly: true,
                hint: '50.00',
                helperText: 'سعر تحويل 1 $_currency إلى الجنيه معتمد ومقفل تلقائياً',
                prefixIcon: const Icon(Icons.currency_exchange,
                    size: 18, color: AppTheme.neonCyan),
                suffixIcon: const Tooltip(
                  message: 'سعر الصرف مقفل لمنع التعديل اليدوي',
                  child: Icon(Icons.lock_outline, size: 18, color: Color(0xFF64748B)),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Builder(builder: (context) {
              final rate = _currency == 'EGP'
                  ? 1.0
                  : (double.tryParse(_exchangeRateCtrl.text.trim()) ?? 1.0);
              final grossRevForeign = _items.fold<double>(0.0, (sum, i) => sum + i.totalRevenueForeign);
              final dVal = double.tryParse(_discountAmountCtrl.text.trim()) ?? 0.0;
              String? dHelper;
              if (dVal > 0) {
                final dEgp = dVal * rate;
                final pct = grossRevForeign > 0 ? (dVal / grossRevForeign * 100) : 0.0;
                dHelper = _currency != 'EGP'
                    ? 'يخصم ${dVal.toStringAsFixed(2)} $_currency (${dEgp.toStringAsFixed(2)} ج.م) — نسبة: ${pct.toStringAsFixed(1)}%'
                    : 'يخصم ${dVal.toStringAsFixed(2)} ج.م — نسبة: ${pct.toStringAsFixed(1)}%';
              }
              return AppTextField(
                label: 'مبلغ الخصم (اختياري)',
                controller: _discountAmountCtrl,
                hint: '0.00',
                prefixIcon: const Icon(Icons.discount_outlined, size: 18, color: AppTheme.warning),
                helperText: dHelper,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              );
            }),
            const SizedBox(height: 16),
            Builder(builder: (context) {
              final grossRevForeign = _items.fold<double>(0.0, (sum, i) => sum + i.totalRevenueForeign);
              final dVal = double.tryParse(_discountAmountCtrl.text.trim()) ?? 0.0;
              final netRevForeign = (grossRevForeign - dVal).clamp(0.0, double.infinity);
              final pVal = double.tryParse(_paidAmountCtrl.text.trim()) ?? 0.0;
              final remaining = netRevForeign - pVal;
              String? pHelper;
              if (grossRevForeign > 0) {
                if (pVal == 0) {
                  pHelper = 'المتبقي بالكامل على العميل: ${_currencySymbol()} ${netRevForeign.toStringAsFixed(2)}';
                } else if (remaining > 0) {
                  pHelper = 'المتبقي بعد السداد: ${_currencySymbol()} ${remaining.toStringAsFixed(2)}';
                } else if (remaining == 0) {
                  pHelper = 'تم سداد كامل صافي الفاتورة';
                } else {
                  pHelper = 'تنبيه: تم سداد زيادة بمقدار ${_currencySymbol()} ${(-remaining).toStringAsFixed(2)}';
                }
              }
              return AppTextField(
                label: 'المبلغ المدفوع من العميل ($_currency)',
                controller: _paidAmountCtrl,
                hint: '0.00',
                prefixIcon: const Icon(Icons.payments_outlined, size: 18, color: Color(0xFF10B981)),
                helperText: pHelper,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
              );
            }),
            if ((double.tryParse(_paidAmountCtrl.text) ?? 0) > 0) ...[
              const SizedBox(height: 12),
              _buildPaymentSourceDropdown(),
            ],
            const SizedBox(height: 16),
            _buildBankInfo(),
          ],
        ),
    );

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cyberSurface : Colors.white,
        border: isDark || !isDesktop ? null : const Border(left: BorderSide(color: Color(0xFFCBD5E1))),
      ),
      padding: const EdgeInsets.all(16),
      child: isDesktop ? SingleChildScrollView(child: content) : content,
    );
  }

  Widget _buildPaymentSourceDropdown() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final paid = double.tryParse(_paidAmountCtrl.text) ?? 0.0;
    if (paid <= 0) return const SizedBox.shrink();
    if (_bankAccounts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'لا توجد حسابات بنكية. قم بإنشائها من إعدادات النظام أولاً.',
          style: TextStyle(color: AppTheme.warning, fontFamily: 'Cairo', fontSize: 12),
        ),
      );
    }
    final currency = _currency.toUpperCase();
    final matchingBanks = _bankAccounts.where((b) {
      final bc = (b['currency']?.toString() ?? '').toUpperCase();
      return bc == currency;
    }).toList();

    if (matchingBanks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'لا يوجد حساب بنكي بعملة $currency. أضف حساباً بنكياً بالعملة المطلوبة أولاً.',
          style: const TextStyle(color: AppTheme.warning, fontFamily: 'Cairo', fontSize: 12),
        ),
      );
    }

    String? dropdownValue;
    if (_selectedPaymentSourceType == 'bank' && _selectedBankAccountId != null) {
      final hasBank = matchingBanks.any((b) => b['id']?.toString() == _selectedBankAccountId.toString());
      if (hasBank) {
        dropdownValue = 'bank_$_selectedBankAccountId';
      }
    }
    // Auto-select if only 1 matching bank and none selected yet
    if (dropdownValue == null && matchingBanks.length == 1) {
      dropdownValue = 'bank_${matchingBanks.first['id']}';
      _selectedPaymentSourceType = 'bank';
      _selectedBankAccountId = int.tryParse(matchingBanks.first['id']?.toString() ?? '');
      _selectedTreasuryId = null;
      _selectedTreasuryCurrency = null;
    }

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: dropdownValue,
            isExpanded: true,
            dropdownColor: isDark ? const Color(0xFF0A2A4A) : Colors.white,
            style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              labelText: 'اختر الحساب البنكي',
              labelStyle: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B), fontFamily: 'Cairo'),
              filled: true,
              fillColor: isDark ? const Color(0x3805192D) : const Color(0xFFF1F5F9),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1))),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            ),
            items: matchingBanks.map((b) {
              final balance = num.tryParse(b['balance']?.toString() ?? '0')?.toDouble() ?? 0.0;
              final bName = b['name']?.toString() ?? '';
              final bCurr = (b['currency']?.toString() ?? '').toUpperCase();
              return DropdownMenuItem<String>(
                value: 'bank_${b['id']}',
                child: Row(
                  children: [
                    Icon(Icons.account_balance, size: 14, color: isDark ? AppTheme.cyan : AppTheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'بنك - $bName ($bCurr) — ${balance.toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 12, color: isDark ? Colors.white : const Color(0xFF0F172A), fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (v) {
              setState(() {
                if (v != null && v.startsWith('bank_')) {
                  _selectedPaymentSourceType = 'bank';
                  _selectedBankAccountId = int.tryParse(v.replaceFirst('bank_', ''));
                  _selectedTreasuryId = null;
                  _selectedTreasuryCurrency = null;
                }
              });
            },
            validator: (v) {
              if (paid > 0 && (v == null || v.isEmpty)) {
                return 'يرجى اختيار الحساب البنكي';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBankInfo() {
    final bank = BankDetails.forCurrency(_currency);
    if (bank == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.neonCyan.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.account_balance,
                size: 14, color: AppTheme.neonCyan),
            const SizedBox(width: 6),
            Text('الحساب البنكي (${bank.currency})',
                style: const TextStyle(
                  color: AppTheme.neonCyan,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                )),
          ]),
          const SizedBox(height: 6),
          _bankRow('البنك', bank.bankName),
          _bankRow('الحساب', bank.accountNumber),
          _bankRow('IBAN', bank.iban),
          _bankRow('SWIFT', bank.swiftCode),
        ],
      ),
    );
  }

  Widget _bankRow(String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(children: [
        Text('$label: ',
            style: TextStyle(
                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                fontSize: 11,
                fontFamily: 'Cairo')),
        Expanded(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 11, fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
      ]),
    );
  }

  Widget _buildTransportRadios() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const modes = ['sea', 'air'];
    const labels = ['بحري', 'جوي'];
    return Row(
        children: List.generate(2, (i) {
      final selected = _transportMode == modes[i];
      return Expanded(
        child: GestureDetector(
          onTap: () => _onTransportModeChanged(modes[i]),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: EdgeInsets.only(left: i == 0 ? 4 : 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? (isDark ? AppTheme.neonCyan.withValues(alpha: 0.08) : const Color(0xFFE0F2FE))
                  : (isDark ? AppTheme.cyberSurface : const Color(0xFFF1F5F9)),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: selected
                      ? (isDark ? AppTheme.neonCyan : AppTheme.primary)
                      : (isDark ? AppTheme.border : const Color(0xFFCBD5E1)),
                  width: selected ? 1.5 : 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 18,
                  color: selected ? (isDark ? AppTheme.neonCyan : AppTheme.primary) : Colors.grey,
                ),
                const SizedBox(width: 6),
                Text(labels[i],
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      color: selected
                          ? (isDark ? AppTheme.neonCyan : AppTheme.primary)
                          : (isDark ? AppTheme.textSecondary : const Color(0xFF475569)),
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                    )),
              ],
            ),
          ),
        ),
      );
    }));
  }

  Widget _buildCurrencyRadios() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const values = ['EGP', 'USD', 'EUR', 'GBP'];
    const labels = ['جنيه', 'دولار', 'يورو', 'جنيه إسترليني'];
    final locked = _selectedCustomerId != null;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List.generate(4, (i) {
        final selected = _currency == values[i];
        return GestureDetector(
          onTap: locked
              ? null
              : () async {
                  final newCurr = values[i];
                  double newRate = 1.0;
                  if (newCurr != 'EGP') {
                    try {
                      newRate = await CurrencyConversionService.instance
                          .getRate(newCurr);
                      if (newRate <= 0) newRate = 50.0;
                    } catch (_) {
                      newRate = 50.0;
                    }
                  }
                  if (!mounted) return;
                  setState(() {
                    _currency = newCurr;
                    _exchangeRateCtrl.text = newRate.toStringAsFixed(2);
                  });
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? (isDark ? AppTheme.neonCyan.withValues(alpha: 0.08) : const Color(0xFFE0F2FE))
                  : (isDark ? AppTheme.cyberSurface : const Color(0xFFF1F5F9)),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: selected
                      ? (isDark ? AppTheme.neonCyan : AppTheme.primary)
                      : (isDark ? AppTheme.border : const Color(0xFFCBD5E1)),
                  width: selected ? 1.5 : 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 14,
                  color: selected ? (isDark ? AppTheme.neonCyan : AppTheme.primary) : Colors.grey,
                ),
                const SizedBox(width: 3),
                Text(labels[i],
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: selected
                          ? (isDark ? AppTheme.neonCyan : AppTheme.primary)
                          : (isDark ? AppTheme.textSecondary : const Color(0xFF475569)),
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                    )),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildItemCard(int index, _ShipmentItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final symbol = _currencySymbol();
    final qty = int.tryParse(item.qtyCtrl.text) ?? 0;
    final wpc = double.tryParse(item.weightPerCartonCtrl.text) ?? 0;
    final price = double.tryParse(item.priceCtrl.text) ?? 0;
    final exportPrice =
        double.tryParse(item.exportPricePerCartonCtrl.text) ?? 0;
    final netWt = double.tryParse(item.netWtCtrl.text) ?? 0;
    final activeExportPrice = exportPrice > 0 ? exportPrice : price;
    final totalValue = qty * activeExportPrice;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.neonCyan.withValues(alpha: 0.03)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? AppTheme.neonCyan.withValues(alpha: 0.12)
              : const Color(0xFFCBD5E1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: badges + delete
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: AppTheme.neonCyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6)),
                child: Text('الصنف رقم (${index + 1})',
                    style: const TextStyle(
                        color: AppTheme.neonCyan,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo')),
              ),
              if (item.packingOrderNumber != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text('أمر التعبئة: ${item.packingOrderNumber}',
                      style: const TextStyle(
                          color: AppTheme.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo')),
                ),
              if (item.exportShipmentNo != null && item.exportShipmentNo!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text('شحنة: ${item.exportShipmentNo}',
                      style: const TextStyle(
                          color: Colors.blue,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo')),
                ),
              if (item.customerName != null && item.customerName!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text('عميل: ${item.customerName}',
                      style: const TextStyle(
                          color: Colors.teal,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo')),
                ),
              if (item.grade.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: AppTheme.emerald.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text('الدرجة ${item.grade}',
                      style: const TextStyle(
                          color: AppTheme.emerald,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo')),
                ),
              if (item.recipeName != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text('وصفة: ${item.recipeName}',
                      style: const TextStyle(
                          color: AppTheme.primary,
                          fontSize: 11,
                          fontFamily: 'Cairo')),
                ),
              if (_items.length > 1)
                GestureDetector(
                  onTap: () => setState(() {
                    item.dispose();
                    _items.removeAt(index);
                  }),
                  child: Icon(Icons.delete_outline,
                      color: AppTheme.danger, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // 1- Product data
          _sectionLabel('بيانات المنتج'),
          const SizedBox(height: 8),
          AppSearchField<PackingOrderModel>(
            label: 'امر التعبئة',
            controller: item.nameCtrl,
            isRequired: true,
            displayStringForOption: (po) {
              if (po.lineId != null && po.productName != null && po.productName!.isNotEmpty) {
                return '${po.productName} (أمر #${po.orderNumber})';
              }
              return po.productName ?? po.orderNumber;
            },
            suggestionsCallback: (pattern) async {
              List<PackingOrderModel> orders;
              try {
                orders = await _packingOrderDao.getAvailableForShipment();
                _availablePackingOrders = orders;
              } catch (_) {
                orders = _availablePackingOrders;
              }

              final selectedKeys = _items
                  .where((i) =>
                      i != item &&
                      (i.lineId != null || i.packingOrderId != null))
                  .map((i) => i.lineId != null
                      ? 'line_${i.lineId}'
                      : 'po_${i.packingOrderId}')
                  .toSet();

              return PackingOrderDao.filterAvailableOrdersForSelector(
                orders: orders,
                excludedSelectionKeys: selectedKeys,
                pattern: pattern,
              );
            },
            itemBuilder: (context, po) => Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(po.orderNumber,
                          style: const TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                              fontSize: 13)),
                      if (po.exportShipmentNo != null &&
                          po.exportShipmentNo!.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'شحنة: ${po.exportShipmentNo}',
                            style: const TextStyle(
                              color: Colors.blue,
                              fontSize: 10,
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                      if (po.customerName != null &&
                          po.customerName!.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'عميل: ${po.customerName}',
                            style: const TextStyle(
                              color: Colors.teal,
                              fontSize: 10,
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                      if (po.lineId != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: AppTheme.primary.withValues(alpha: 0.4)),
                          ),
                          child: const Text(
                            'بند محصول',
                            style: TextStyle(
                              color: AppTheme.primary,
                              fontSize: 10,
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(po.productName ?? po.orderNumber,
                      style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                          fontSize: 14)),
                  Text(
                      'متبقي: ${po.remainingCartons} كرتونة من ${po.cartonCount} | Net: ${po.totalNetWeight.toStringAsFixed(1)} KG',
                      style: TextStyle(
                          color: isDark ? AppTheme.textMuted : const Color(0xFF475569),
                          fontFamily: 'Cairo',
                          fontSize: 12)),
                  if (po.packedAt != null || po.createdAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                        'تاريخ التعبئة: ${AppUtils.formatDate(po.packedAt ?? po.createdAt!)}',
                        style: TextStyle(
                            color: isDark ? AppTheme.textMuted : const Color(0xFF64748B),
                            fontFamily: 'Cairo',
                            fontSize: 11)),
                  ],
                ],
              ),
            ),
            onSelected: (po) async {
              if (!mounted) return;
              
              // 1. Fetch fresh packing order from DB by ID
              final poId = int.tryParse(po.id ?? '');
              PackingOrderModel freshPo = po;
              PackingOrderLineModel? matchingLine;
              if (poId != null) {
                try {
                  final dbPo = await _packingOrderDao.getById(poId);
                  if (dbPo != null) {
                    freshPo = dbPo;
                    if (po.lineId != null) {
                      for (final l in dbPo.lines) {
                        if (l.id == po.lineId.toString()) {
                          matchingLine = l;
                          break;
                        }
                      }
                    }
                  }
                } catch (e) {
                  debugPrint('Error fetching fresh packing order: $e');
                }
              }

              // 2. Authoritative cost per carton for this line or header
              double packingCostPerCarton = 0.0;
              if (matchingLine != null) {
                if (matchingLine.finalCost > 0 && matchingLine.cartonCount > 0) {
                  packingCostPerCarton = matchingLine.finalCost / matchingLine.cartonCount;
                } else if (matchingLine.finalUnitCost > 0) {
                  packingCostPerCarton = matchingLine.finalUnitCost;
                }
              }
              
              if (packingCostPerCarton <= 0 && po.packingCostPerCarton > 0) {
                packingCostPerCarton = po.packingCostPerCarton;
              }

              if (packingCostPerCarton <= 0 && freshPo.packingCostPerCarton > 0) {
                packingCostPerCarton = freshPo.packingCostPerCarton;
              }
              
              // 3. Fallback only if cost is still 0
              if (packingCostPerCarton <= 0 && po.lineId != null) {
                try {
                  final lineData = await Supabase.instance.client
                      .from('packing_order_lines')
                      .select('final_unit_cost, final_cost, carton_count')
                      .eq('id', po.lineId!)
                      .maybeSingle();
                  if (lineData != null) {
                    final totalCost = (lineData['final_cost'] as num?)?.toDouble() ?? 0.0;
                    final lineCartons = (lineData['carton_count'] as num?)?.toInt() ?? 0;
                    if (totalCost > 0 && lineCartons > 0) {
                      packingCostPerCarton = totalCost / lineCartons;
                    } else {
                      final unitCost = (lineData['final_unit_cost'] as num?)?.toDouble() ?? 0.0;
                      if (unitCost > 0) packingCostPerCarton = unitCost;
                    }
                  }
                } catch (e) {
                  debugPrint('Line cost fetch error: $e');
                }
              }

              if (packingCostPerCarton <= 0 && (freshPo.fruitTypeId != null || po.fruitTypeId != null)) {
                try {
                  final fruitId = freshPo.fruitTypeId ?? po.fruitTypeId!;
                  final fallbackLine = await Supabase.instance.client
                      .from('packing_order_lines')
                      .select('final_cost, carton_count, final_unit_cost')
                      .eq('fruit_type_id', fruitId)
                      .gt('final_cost', 0)
                      .order('id', ascending: false)
                      .limit(1)
                      .maybeSingle();
                  if (fallbackLine != null) {
                    final fCost = (fallbackLine['final_cost'] as num?)?.toDouble() ?? 0.0;
                    final fQty = (fallbackLine['carton_count'] as num?)?.toInt() ?? 0;
                    if (fCost > 0 && fQty > 0) {
                      packingCostPerCarton = fCost / fQty;
                    } else {
                      packingCostPerCarton = (fallbackLine['final_unit_cost'] as num?)?.toDouble() ?? 0.0;
                    }
                  }
                } catch (_) {}
              }

              // 4. Resolve remaining cartons, total cartons, weights, and product name
              final int remaining;
              final int totalCartons;
              final double netWtPerCarton;
              final double grossWtPerCarton;
              final String selectedProductName;
              final int? fruitTypeId;
              final String grade;
              final String? recipeName;
              final int? recipeVersion;

              if (matchingLine != null) {
                totalCartons = matchingLine.cartonCount;
                remaining = (matchingLine.cartonCount - matchingLine.soldCartons).clamp(0, matchingLine.cartonCount);
                netWtPerCarton = matchingLine.netWeightPerCarton > 0
                    ? matchingLine.netWeightPerCarton
                    : (po.netWeightPerCarton > 0 ? po.netWeightPerCarton : freshPo.netWeightPerCarton);
                grossWtPerCarton = matchingLine.grossWeightPerCarton > 0
                    ? matchingLine.grossWeightPerCarton
                    : (po.grossWeightPerCarton > 0 ? po.grossWeightPerCarton : freshPo.grossWeightPerCarton);
                selectedProductName = matchingLine.productName.isNotEmpty
                    ? matchingLine.productName
                    : (po.productName ?? freshPo.productName ?? freshPo.orderNumber);
                fruitTypeId = matchingLine.fruitTypeId ?? int.tryParse(freshPo.fruitTypeId ?? po.fruitTypeId ?? '');
                grade = matchingLine.grade.isNotEmpty
                    ? matchingLine.grade
                    : (freshPo.grade.isNotEmpty ? freshPo.grade : po.grade);
                recipeName = freshPo.recipeName ?? po.recipeName;
                recipeVersion = freshPo.recipeVersion ?? po.recipeVersion;
              } else if (po.lineId != null) {
                totalCartons = po.cartonCount;
                remaining = po.remainingCartons;
                netWtPerCarton = po.netWeightPerCarton > 0 ? po.netWeightPerCarton : freshPo.netWeightPerCarton;
                grossWtPerCarton = po.grossWeightPerCarton > 0 ? po.grossWeightPerCarton : freshPo.grossWeightPerCarton;
                selectedProductName = po.productName ?? freshPo.productName ?? freshPo.orderNumber;
                fruitTypeId = int.tryParse(po.fruitTypeId ?? freshPo.fruitTypeId ?? '');
                grade = po.grade.isNotEmpty ? po.grade : freshPo.grade;
                recipeName = po.recipeName ?? freshPo.recipeName;
                recipeVersion = po.recipeVersion ?? freshPo.recipeVersion;
              } else {
                totalCartons = freshPo.cartonCount;
                remaining = freshPo.remainingCartons;
                netWtPerCarton = freshPo.netWeightPerCarton > 0 ? freshPo.netWeightPerCarton : po.netWeightPerCarton;
                grossWtPerCarton = freshPo.grossWeightPerCarton > 0 ? freshPo.grossWeightPerCarton : po.grossWeightPerCarton;
                selectedProductName = freshPo.productName ?? freshPo.orderNumber;
                fruitTypeId = int.tryParse(freshPo.fruitTypeId ?? po.fruitTypeId ?? '');
                grade = freshPo.grade.isNotEmpty ? freshPo.grade : po.grade;
                recipeName = freshPo.recipeName ?? po.recipeName;
                recipeVersion = freshPo.recipeVersion ?? po.recipeVersion;
              }

              final weightRatio = remaining > 0 && totalCartons > 0
                  ? remaining / totalCartons
                  : 1.0;

              setState(() {
                item.packingOrderId = int.tryParse(freshPo.id ?? po.id ?? '');
                item.packingOrderNumber = freshPo.orderNumber;
                item.exportShipmentNo = freshPo.exportShipmentNo ?? po.exportShipmentNo;
                item.customerName = freshPo.customerName ?? po.customerName;
                item.lineId = po.lineId;
                item.productId = fruitTypeId;
                item.grade = grade;
                item.recipeName = recipeName;
                item.recipeVersion = recipeVersion;
                item.nameCtrl.text = selectedProductName;
                item.invoiceProductCtrl.text = selectedProductName;
                item._maxCartons = remaining;
                item.qtyCtrl.text = remaining.toString();
                item.weightPerCartonCtrl.text =
                    (netWtPerCarton > 0 ? netWtPerCarton : 15.0).toStringAsFixed(0);
                item.priceCtrl.text = packingCostPerCarton.toStringAsFixed(2);
                item.hsCode = '';
                item.hsCodeCtrl.text = '';
                item.recalculate();

                final remainingGross = grossWtPerCarton > 0
                    ? (remaining * grossWtPerCarton)
                    : (freshPo.totalGrossWeight * weightRatio);
                if (remainingGross > 0) {
                  item.grossWtCtrl.text = remainingGross.toStringAsFixed(0);
                } else if (netWtPerCarton > 0) {
                  item.grossWtCtrl.text = (remaining * netWtPerCarton).toStringAsFixed(0);
                }
              });
            },
            emptyBuilder: (context) => Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: isDark ? AppTheme.warning : const Color(0xFFD97706)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'لا توجد أوامر تعبئة جاهزة للشحن',
                          style: TextStyle(
                            color: isDark ? AppTheme.textMuted : const Color(0xFF64748B),
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• تأكد من أن أمر التعبئة تم اعتماده نهائياً\n• تأكد أن الكراتين لم تُباع بالكامل في شحنات سابقة',
                    style: TextStyle(
                      color: isDark ? AppTheme.textMuted : const Color(0xFF94A3B8),
                      fontFamily: 'Cairo',
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (item.hsCode.isNotEmpty) ...[
            const SizedBox(height: 6),
            _infoLabel('كود HS الجمركي: ${item.hsCode}'),
          ],
          if ((item.exportShipmentNo != null &&
                  item.exportShipmentNo!.isNotEmpty) ||
              (item.customerName != null && item.customerName!.isNotEmpty)) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (item.exportShipmentNo != null &&
                    item.exportShipmentNo!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'رقم شحنة أمر التعبئة: ${item.exportShipmentNo}',
                      style: const TextStyle(
                        color: Colors.blue,
                        fontSize: 11,
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (item.customerName != null && item.customerName!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: Colors.teal.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'عميل أمر التعبئة: ${item.customerName}',
                      style: const TextStyle(
                        color: Colors.teal,
                        fontSize: 11,
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          AppTextField(
            label: 'اسم المنتج التصديري في الفاتورة',
            controller: item.invoiceProductCtrl,
            hint: 'اسم المنتج كما سيظهر في الفاتورة',
            helperText: 'سيظهر هذا الاسم في الفاتورة بدل اسم أمر التعبئة',
          ),
          const SizedBox(height: 8),

          // 2- Quantities & weights
          _sectionLabel('الكميات والأوزان'),
          const SizedBox(height: 8),
          _infoLabel('$qty كرتون × $wpc كجم', bold: true, primary: true),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 500;
              if (isNarrow) {
                return Column(
                  children: [
                    _buildReadOnlyField(
                        'الوزن الصافي', '${netWt.toStringAsFixed(0)} كجم'),
                    const SizedBox(height: 8),
                    AppTextField(
                      label: 'الوزن الإجمالي (كجم)',
                      controller: item.grossWtCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      hint: '0',
                      helperText: 'للطباعة فقط',
                      onChanged: (_) => setState(() {}),
                    ),
                    if (_transportMode != 'air') ...[
                      const SizedBox(height: 8),
                      AppTextField(
                        label: 'عدد البالتات',
                        controller: item.palletsCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d*')),
                        ],
                        hint: '0',
                        helperText: 'عدد الطبالي المستخدمة للشحنة',
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ],
                );
              }
              return Row(children: [
                Expanded(
                    child: _buildReadOnlyField(
                        'الوزن الصافي', '${netWt.toStringAsFixed(0)} كجم')),
                const SizedBox(width: 8),
                Expanded(
                    child: AppTextField(
                  label: 'الوزن الإجمالي (كجم)',
                  controller: item.grossWtCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  hint: '0',
                  helperText: 'للطباعة فقط',
                  onChanged: (_) => setState(() {}),
                )),
                if (_transportMode != 'air') ...[
                  const SizedBox(width: 8),
                  Expanded(
                      child: AppTextField(
                    label: 'عدد البالتات',
                    controller: item.palletsCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*')),
                    ],
                    hint: '0',
                    helperText: 'عدد الطبالي المستخدمة للشحنة',
                    onChanged: (_) => setState(() {}),
                  )),
                ],
              ]);
            },
          ),
          const SizedBox(height: 8),

          // 3- Prices
          _sectionLabel('الأسعار'),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 500;
              if (isNarrow) {
                return Column(
                  children: [
                    _buildReadOnlyField(
                        'تكلفة الإنتاج للكرتونة (مركز التكلفة)',
                        '${(double.tryParse(item.priceCtrl.text) ?? 0).toStringAsFixed(2)} ج.م',
                        onRefresh: item.packingOrderId != null ? () => _refreshItemCost(item) : null),
                    const SizedBox(height: 8),
                    AppTextField(
                      label: 'سعر الكرتونة التصديري ($symbol)',
                      controller: item.exportPricePerCartonCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*')),
                      ],
                      hint: 'السعر المتفق عليه',
                      helperText: 'السعر المتفق عليه مع العميل',
                      onChanged: (_) => setState(() {
                        item.recalculate();
                      }),
                    ),
                    const SizedBox(height: 8),
                    AppTextField(
                      controller: item.qtyCtrl,
                      label: 'عدد الكراتين',
                      keyboardType: TextInputType.number,
                      hint: '${item._maxCartons ?? ""}',
                      onChanged: (_) => setState(() {
                        item.recalculate();
                      }),
                    ),
                  ],
                );
              }
              return Row(children: [
                Expanded(
                    child: _buildReadOnlyField(
                        'تكلفة الإنتاج للكرتونة (مركز التكلفة)',
                        '${(double.tryParse(item.priceCtrl.text) ?? 0).toStringAsFixed(2)} ج.م',
                        onRefresh: item.packingOrderId != null ? () => _refreshItemCost(item) : null)),
                const SizedBox(width: 8),
                Expanded(
                    child: AppTextField(
                  label: 'سعر الكرتونة التصديري ($symbol)',
                  controller: item.exportPricePerCartonCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d*')),
                  ],
                  hint: 'السعر المتفق عليه',
                  helperText: 'السعر المتفق عليه مع العميل',
                  onChanged: (_) => setState(() {
                    item.recalculate();
                  }),
                )),
                const SizedBox(width: 8),
                Expanded(
                    child: AppTextField(
                      controller: item.qtyCtrl,
                      label: 'عدد الكراتين',
                      keyboardType: TextInputType.number,
                      hint: '${item._maxCartons ?? ""}',
                      onChanged: (_) => setState(() {
                        item.recalculate();
                      }),
                    )),
              ]);
            },
          ),
          const SizedBox(height: 8),

          // 4- Summary
          _sectionLabel('بيانات التصدير والربحية'),
          const SizedBox(height: 8),
          _buildSummaryRow(item, symbol),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(text,
        style: TextStyle(
            color: isDark ? AppTheme.textSecondary : const Color(0xFF334155),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cairo',
            letterSpacing: 0.5));
  }

  Widget _buildSummaryRow(_ShipmentItem item, String symbol) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rate = _currency == 'EGP'
        ? 1.0
        : (double.tryParse(_exchangeRateCtrl.text.trim()) ?? 1.0);
    final qty = item.qty;
    final netWt = double.tryParse(item.netWtCtrl.text) ?? 0;
    final grossWt = double.tryParse(item.grossWtCtrl.text) ?? 0;
    final unitCost = item.unitCostEgp;
    final totalCost = item.totalCostEgp;
    final exportPrice = item.exportPrice;
    final revenueForeign = item.totalRevenueForeign;
    final revenueEgp = item.totalRevenueEgp(rate);
    final netProfit = item.netProfitEgp(rate);
    final marginPct = item.profitMarginPct(rate);
    final isProfit = netProfit >= 0;
    final hasMetrics = qty > 0 && (revenueForeign > 0 || totalCost > 0);

    const profitGreen = Color(0xFF10B981);
    const lossRed = Color(0xFFEF4444);
    final profitColor = isProfit ? profitGreen : lossRed;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasMetrics
            ? profitColor.withValues(alpha: isDark ? 0.04 : 0.06)
            : (isDark ? AppTheme.neonCyan.withValues(alpha: 0.05) : const Color(0xFFF1F5F9)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasMetrics
              ? profitColor.withValues(alpha: isDark ? 0.3 : 0.5)
              : (isDark ? AppTheme.neonCyan.withValues(alpha: 0.15) : const Color(0xFFCBD5E1)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    hasMetrics
                        ? (isProfit ? Icons.trending_up : Icons.trending_down)
                        : Icons.analytics_outlined,
                    size: 16,
                    color: hasMetrics ? profitColor : (isDark ? AppTheme.neonCyan : const Color(0xFF0284C7)),
                  ),
                  const SizedBox(width: 6),
                  Text('ملخص الصنف والربحية التقديرية',
                      style: TextStyle(
                          color: isDark ? AppTheme.neonCyan : const Color(0xFF0284C7),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo')),
                ],
              ),
              if (hasMetrics)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: profitColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border:
                        Border.all(color: profitColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isProfit
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        size: 13,
                        color: profitColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isProfit
                            ? 'صافي ربح: +${netProfit.toStringAsFixed(2)} ج.م (${marginPct.toStringAsFixed(1)}%)'
                            : 'صافي خسارة: ${netProfit.toStringAsFixed(2)} ج.م (${marginPct.toStringAsFixed(1)}%)',
                        style: TextStyle(
                          color: profitColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _summaryCell('عدد الكراتين', '$qty كرتونة'),
              _summaryCell('الوزن الصافي', '${netWt.toStringAsFixed(0)} كجم'),
              _summaryCell('الوزن الإجمالي', '${grossWt.toStringAsFixed(0)} كجم'),
              _summaryCell(
                'تكلفة الوحدة (مركز التكلفة)',
                unitCost > 0 ? '${unitCost.toStringAsFixed(2)} ج.م' : '—',
              ),
              _summaryCell(
                'إجمالي التكلفة (ج.م)',
                totalCost > 0 ? '${totalCost.toStringAsFixed(2)} ج.م' : '0.00 ج.م',
                valueColor: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
              ),
              _summaryCell(
                'سعر الكرتونة التصديري',
                exportPrice > 0 ? '$symbol ${exportPrice.toStringAsFixed(2)}' : '—',
              ),
              _summaryCell(
                'إيراد التصدير ($_currency)',
                revenueForeign > 0 ? '$symbol ${revenueForeign.toStringAsFixed(2)}' : '—',
              ),
              if (_currency != 'EGP') ...[
                _summaryCell('سعر الصرف المعتمد', '${rate.toStringAsFixed(2)} ج.م'),
                _summaryCell(
                  'الإيراد بالمصري (ج.م)',
                  '${revenueEgp.toStringAsFixed(2)} ج.م',
                  valueColor: isDark ? AppTheme.neonCyan : const Color(0xFF0284C7),
                ),
              ],
              _summaryCell(
                'صافي الربح / الخسارة',
                hasMetrics
                    ? '${isProfit ? '+' : ''}${netProfit.toStringAsFixed(2)} ج.م'
                    : '—',
                valueColor: hasMetrics ? profitColor : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryCell(String label, String value,
      {Color? valueColor, Widget? customValue}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 130,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                  fontFamily: 'Cairo')),
          const SizedBox(height: 2),
          customValue ??
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: valueColor ?? (isDark ? AppTheme.textPrimary : const Color(0xFF0F172A)),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo')),
        ],
      ),
    );
  }

  Widget _infoLabel(String text, {bool bold = false, bool primary = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            color: primary
                ? (isDark ? AppTheme.primary : const Color(0xFF0284C7))
                : (isDark ? AppTheme.textPrimary : const Color(0xFF0F172A)),
            fontSize: 13,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            fontFamily: 'Cairo'));
  }

  Widget _buildReadOnlyField(String label, String value, {VoidCallback? onRefresh}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Cairo')),
                const SizedBox(height: 2),
                Text(value.isEmpty ? '0' : value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: isDark ? AppTheme.textPrimary : const Color(0xFF0F172A),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo')),
              ],
            ),
          ),
          if (onRefresh != null)
            IconButton(
              icon: const Icon(Icons.refresh, size: 18, color: AppTheme.primary),
              tooltip: 'تحديث التكلفة من أمر التعبئة',
              onPressed: onRefresh,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
            ),
        ],
      ),
    );
  }

  Widget _buildTotalsRow() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final symbol = _currencySymbol();
    final rate = _currency == 'EGP'
        ? 1.0
        : (double.tryParse(_exchangeRateCtrl.text.trim()) ?? 1.0);
    final itemsCount =
        _items.where((i) => i.nameCtrl.text.trim().isNotEmpty).length;
    final totalCartons = _items.fold(0, (sum, i) => sum + i.qty);
    final totalNetWt = _items.fold(
        0.0, (sum, i) => sum + (double.tryParse(i.netWtCtrl.text) ?? 0));
    final totalGrossWt = _items.fold(
        0.0, (sum, i) => sum + (double.tryParse(i.grossWtCtrl.text) ?? 0));
    final totalPallets = _items.fold(
        0, (sum, i) => sum + (int.tryParse(i.palletsCtrl.text) ?? 0));

    // Production cost dynamically fetched from product cost centers
    final totalCostEgp =
        _items.fold<double>(0.0, (sum, i) => sum + i.totalCostEgp);

    // Export revenue in foreign currency (e.g., USD / EUR)
    final totalExportRevenueForeign =
        _items.fold<double>(0.0, (sum, i) => sum + i.totalRevenueForeign);

    // Converted revenue in EGP
    final totalRevenueEgp = totalExportRevenueForeign * rate;

    // Optional discount
    final discountForeign =
        double.tryParse(_discountAmountCtrl.text.trim()) ?? 0.0;
    final discountEgp = discountForeign * rate;
    final netRevenueForeign =
        (totalExportRevenueForeign - discountForeign).clamp(0.0, double.infinity);
    final netRevenueEgp =
        (totalRevenueEgp - discountEgp).clamp(0.0, double.infinity);

    // Customer payment and remaining balance
    final paidForeign =
        double.tryParse(_paidAmountCtrl.text.trim()) ?? 0.0;
    final paidEgp = paidForeign * rate;
    final remainingDueForeign = netRevenueForeign - paidForeign;
    final remainingDueEgp = netRevenueEgp - paidEgp;

    // Net Profit / Loss & Margin Calculation
    final totalNetProfitEgp = netRevenueEgp - totalCostEgp;
    final totalMarginPct =
        netRevenueEgp > 0 ? (totalNetProfitEgp / netRevenueEgp) * 100 : 0.0;
    final isOverallProfit = totalNetProfitEgp >= 0;
    final hasMetrics = totalCartons > 0 &&
        (totalExportRevenueForeign > 0 || totalCostEgp > 0);

    const profitGreen = Color(0xFF10B981);
    const lossRed = Color(0xFFEF4444);
    final profitColor = isOverallProfit ? profitGreen : lossRed;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.cyberSurface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? (hasMetrics
                  ? profitColor.withValues(alpha: 0.35)
                  : AppTheme.primary.withValues(alpha: 0.25))
              : const Color(0xFFCBD5E1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Icon(Icons.analytics_outlined,
                  size: 18, color: isDark ? AppTheme.neonCyan : const Color(0xFF0284C7)),
              const SizedBox(width: 8),
              Text(
                'ملخص الشحنة ككل وحساب الربحية التقديرية',
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
              ),
              const Spacer(),
              if (_currency != 'EGP')
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.neonCyan.withValues(alpha: 0.08) : const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: isDark ? AppTheme.neonCyan.withValues(alpha: 0.25) : const Color(0xFFBAE6FD)),
                  ),
                  child: Text(
                    '1 $_currency = ${rate.toStringAsFixed(2)} ج.م',
                    style: TextStyle(
                      color: isDark ? AppTheme.neonCyan : const Color(0xFF0284C7),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Real-time Profitability Dashboard Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: hasMetrics
                  ? profitColor.withValues(alpha: isDark ? 0.07 : 0.05)
                  : (isDark ? Colors.white.withValues(alpha: 0.02) : const Color(0xFFF8FAFC)),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: hasMetrics
                    ? profitColor.withValues(alpha: isDark ? 0.4 : 0.5)
                    : (isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0)),
                width: 1.2,
              ),
            ),
            child: Column(
              children: [
                LayoutBuilder(builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 650;
                  final costBlock = _profitKpiBlock(
                    title: 'إجمالي تكلفة الإنتاج (مراكز التكلفة)',
                    value: '${totalCostEgp.toStringAsFixed(2)} ج.م',
                    valueColor: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
                    icon: Icons.inventory_2_outlined,
                    iconColor: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
                    subtitle: totalCartons > 0
                        ? 'متوسط: ${(totalCostEgp / totalCartons).toStringAsFixed(2)} ج.م / كرتونة'
                        : '—',
                  );
                  final revenueBlock = _profitKpiBlock(
                    title: discountForeign > 0
                        ? 'صافي إيراد التصدير (بعد الخصم)'
                        : 'إجمالي إيراد التصدير',
                    value: _currency != 'EGP'
                        ? '$symbol ${netRevenueForeign.toStringAsFixed(2)}'
                        : '${netRevenueEgp.toStringAsFixed(2)} ج.م',
                    valueColor: isDark ? AppTheme.neonCyan : const Color(0xFF0284C7),
                    icon: Icons.monetization_on_outlined,
                    iconColor: isDark ? AppTheme.neonCyan : const Color(0xFF0284C7),
                    subtitle: discountForeign > 0
                        ? 'إجمالي: $symbol ${totalExportRevenueForeign.toStringAsFixed(2)} | خصم: $symbol ${discountForeign.toStringAsFixed(2)}'
                        : (_currency != 'EGP'
                            ? 'يعادل بالمصري: ${totalRevenueEgp.toStringAsFixed(2)} ج.م'
                            : 'العملة الأساسية: جنيه مصري'),
                  );
                  final profitBlock = _profitKpiBlock(
                    title: isOverallProfit
                        ? 'صافي الربح المتوقع'
                        : 'صافي الخسارة المتوقعة',
                    value: hasMetrics
                        ? '${isOverallProfit ? '+' : ''}${totalNetProfitEgp.toStringAsFixed(2)} ج.م'
                        : '—',
                    valueColor: hasMetrics ? profitColor : (isDark ? AppTheme.textMuted : const Color(0xFF64748B)),
                    icon: hasMetrics
                        ? (isOverallProfit
                            ? Icons.trending_up
                            : Icons.trending_down)
                        : Icons.hourglass_empty,
                    iconColor: hasMetrics ? profitColor : (isDark ? AppTheme.textMuted : const Color(0xFF64748B)),
                    subtitle: hasMetrics
                        ? (isOverallProfit
                            ? 'هامش ربح إيجابي: ${totalMarginPct.toStringAsFixed(1)}%'
                            : 'نسبة خسارة: ${totalMarginPct.toStringAsFixed(1)}%')
                        : 'أدخل الكراتين والأسعار',
                    isEmphasized: true,
                  );

                  if (isNarrow) {
                    return Column(
                      children: [
                        costBlock,
                        const SizedBox(height: 10),
                        revenueBlock,
                        const SizedBox(height: 10),
                        profitBlock,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: costBlock),
                      const SizedBox(width: 12),
                      Expanded(child: revenueBlock),
                      const SizedBox(width: 12),
                      Expanded(child: profitBlock),
                    ],
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Logistics & shipment specs row
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _totalItem('الأصناف', '$itemsCount صنف'),
              _totalItem('عدد الكراتين', '$totalCartons كرتونة'),
              if (_transportMode != 'air')
                _totalItem('عدد البالتات', '$totalPallets طبلية'),
              _totalItem('الوزن الصافي', '${totalNetWt.toStringAsFixed(0)} كجم'),
              _totalItem(
                  'الوزن الإجمالي', '${totalGrossWt.toStringAsFixed(0)} كجم'),
              if (discountForeign > 0)
                _totalItem('الخصم المطبق',
                    '$symbol ${discountForeign.toStringAsFixed(2)} (${discountEgp.toStringAsFixed(2)} ج.م)',
                    valueColor: isDark ? AppTheme.warning : const Color(0xFFD97706)),
              if (paidForeign > 0) ...[
                _totalItem('المسدد من العميل',
                    '$symbol ${paidForeign.toStringAsFixed(2)} (${paidEgp.toStringAsFixed(2)} ج.م)',
                    valueColor: const Color(0xFF10B981)),
                _totalItem(
                    remainingDueForeign >= 0
                        ? 'المتبقي على العميل'
                        : 'فائض دفع العميل',
                    '$symbol ${remainingDueForeign.abs().toStringAsFixed(2)} (${remainingDueEgp.abs().toStringAsFixed(2)} ج.م)',
                    valueColor: remainingDueForeign > 0
                        ? (isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309))
                        : const Color(0xFF10B981)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _profitKpiBlock({
    required String title,
    required String value,
    required Color valueColor,
    required IconData icon,
    required Color iconColor,
    required String subtitle,
    bool isEmphasized = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isEmphasized
            ? valueColor.withValues(alpha: isDark ? 0.1 : 0.12)
            : (isDark ? Colors.black.withValues(alpha: 0.2) : Colors.white),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isEmphasized
              ? valueColor.withValues(alpha: 0.4)
              : (isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFCBD5E1)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                    fontSize: 10,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor,
              fontSize: isEmphasized ? 16 : 14,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isEmphasized
                  ? valueColor.withValues(alpha: 0.85)
                  : (isDark ? AppTheme.textMuted : const Color(0xFF64748B)),
              fontSize: 10,
              fontFamily: 'Cairo',
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalItem(String label, String value, {Color? valueColor}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 155,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Text('$label: ',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Cairo')),
            Expanded(
                child: Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: valueColor ?? (isDark ? AppTheme.textPrimary : const Color(0xFF0F172A)),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo'))),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedCustomerCard() {
    if (_selectedCustomerId == null) return const SizedBox.shrink();
    final match = _customers.where((c) => c.id == _selectedCustomerId);
    if (match.isEmpty) return const SizedBox.shrink();
    final cu = match.first;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('بيانات العميل'),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? AppTheme.neonCyan.withValues(alpha: 0.04)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: isDark
                      ? AppTheme.neonCyan.withValues(alpha: 0.15)
                      : const Color(0xFFCBD5E1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow('الاسم', cu.name),
                _infoRow('الكود', cu.code),
                _infoRow('الهاتف', cu.phone),
                if (cu.city.isNotEmpty) _infoRow('المدينة', cu.city),
                if (cu.country.isNotEmpty) _infoRow('الدولة', cu.country),
                if (cu.gmail.isNotEmpty) _infoRow('البريد', cu.gmail),
                if (cu.vatNumber.isNotEmpty) _infoRow('VAT', cu.vatNumber),
                if (cu.eoriNo.isNotEmpty) _infoRow('EORI', cu.eoriNo),
                if (cu.contactPersonName.isNotEmpty) ...[
                  Divider(
                      height: 16,
                      color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0)),
                  Text('جهة الاتصال',
                      style: TextStyle(
                          color: isDark ? AppTheme.neonCyan : const Color(0xFF0284C7),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo')),
                  const SizedBox(height: 4),
                  _infoRow('الاسم', cu.contactPersonName),
                  if (cu.contactPersonPhone.isNotEmpty)
                    _infoRow('الهاتف', cu.contactPersonPhone),
                  if (cu.contactPersonEmail.isNotEmpty)
                    _infoRow('البريد', cu.contactPersonEmail),
                ],
                if (cu.addresses.isNotEmpty) ...[
                  Divider(
                      height: 16,
                      color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0)),
                  Text('العناوين',
                      style: TextStyle(
                          color: isDark ? AppTheme.neonCyan : const Color(0xFF0284C7),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo')),
                  const SizedBox(height: 4),
                  ...cu.addresses.map((a) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                            '• ${a['full_address'] ?? a['address_line_1'] ?? ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: isDark ? AppTheme.textPrimary : const Color(0xFF0F172A),
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                fontFamily: 'Cairo')),
                      )),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Divider(color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0)),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildAddressPicker() {
    if (_selectedCustomerId == null) return const SizedBox.shrink();
    final match = _customers.where((c) => c.id == _selectedCustomerId);
    if (match.isEmpty) return const SizedBox.shrink();
    final cu = match.first;
    if (cu.addresses.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('اختيار عنوان الشحن'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(
                  color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
              borderRadius: BorderRadius.circular(12),
              color: isDark ? AppTheme.cyberSurface : Colors.white,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _selectedAddressIndex != null &&
                        _selectedAddressIndex! < cu.addresses.length
                    ? _selectedAddressIndex.toString()
                    : null,
                hint: const Text('اختر عنوان الشحن',
                    style: TextStyle(
                        color: AppTheme.textMuted,
                        fontFamily: 'Cairo',
                        fontSize: 14)),
                dropdownColor: isDark ? const Color(0xCC05192D) : Colors.white,
                items: List.generate(cu.addresses.length, (i) {
                  final a = cu.addresses[i];
                  final addr = a['address_line_1']?.toString() ?? '';
                  final city = a['city']?.toString() ?? '';
                  final country = a['country']?.toString() ?? '';
                  final display = [addr, city, country]
                      .where((s) => s.isNotEmpty)
                      .join(', ');
                  return DropdownMenuItem(
                    value: i.toString(),
                    child: Text(
                      display.isNotEmpty ? '(${i + 1}) $display' : 'عنوان ${i + 1}',
                      style: TextStyle(
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                          fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }),
                onChanged: (value) {
                  if (value == null) return;
                  final idx = int.tryParse(value);
                  if (idx == null) return;
                  final a = cu.addresses[idx];
                  final addr = a['address_line_1']?.toString() ?? '';
                  setState(() {
                    _selectedAddressIndex = idx;
                    _destinationAddressCtrl.text = addr;
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Flexible(
            flex: 0,
            child: Text('$label: ',
                style: TextStyle(
                    color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Cairo')),
          ),
          Expanded(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: isDark ? AppTheme.textPrimary : const Color(0xFF0F172A),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  Widget _buildCountrySearchField() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppSearchField<String>(
      label: 'دولة الوجهة',
      isRequired: true,
      controller: _countryCtrl,
      hint: 'أدخل الدولة الوجهة',
      emptyBuilder: (context) => Padding(
        padding: const EdgeInsets.all(12.0),
        child: Text('اكتب اسم الدولة مباشرة',
            style: TextStyle(
                color: isDark ? AppTheme.textMuted : const Color(0xFF64748B),
                fontFamily: 'Cairo')),
      ),
      suggestionsCallback: (pattern) async {
        try {
          final results = await Supabase.instance.client
              .from('export_shipments')
              .select('destination_country')
              .not('destination_country', 'is', null)
              .neq('destination_country', '')
              .ilike('destination_country', '%$pattern%')
              .limit(10);
          final seen = <String>{};
          return results
              .map((r) => r['destination_country']?.toString() ?? '')
              .where((v) => v.isNotEmpty && seen.add(v))
              .toList();
        } catch (_) {
          return [];
        }
      },
      itemBuilder: (context, country) => ListTile(
        dense: true,
        leading: const Icon(Icons.public, size: 16, color: AppTheme.primary),
        title: Text(country,
            style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontWeight: FontWeight.bold,
                fontSize: 14,
                fontFamily: 'Cairo')),
      ),
      onSelected: (country) {
        _countryCtrl.text = country;
      },
      displayStringForOption: (s) => s,
    );
  }

  Widget _buildRightPanel() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? AppTheme.cyberBg : const Color(0xFFF8FAFC),
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: AbsorbPointer(
          absorbing: widget.isReadOnly,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSelectedCustomerCard(),
            _buildAddressPicker(),
            _sectionTitle('بيانات الشحن'),
            const SizedBox(height: 12),
            if (_transportMode == 'sea') ...[
              AppTextField(
                  label: 'BL No.',
                  controller: _awbCtrl,
                  hint: 'رقم بوليصة الشحن',
                  keyboardType: TextInputType.text),
              const SizedBox(height: 12),
              AppTextField(
                  label: 'اسم السفينة',
                  controller: _vesselNameCtrl,
                  hint: 'TBA'),
              const SizedBox(height: 12),
              AppTextField(
                  label: 'رقم الحاوية',
                  controller: _containerNoCtrl,
                  hint: 'مثال: MSCU1234567'),
              const SizedBox(height: 12),
              AppTextField(
                  label: 'رقم مسجل البيانات (Data Logger)',
                  controller: _dataLoggerNoCtrl,
                  hint: 'TBA'),
            ] else ...[
              AppTextField(
                label: 'AWB',
                controller: _awbCtrl,
                hint: 'رقم بوليصة الشحن الجوي',
                keyboardType: TextInputType.text,
              ),
            ],
            const SizedBox(height: 12),
            AppTextField(
              label: 'بلد المنشأ',
              controller: _countryOfOriginCtrl,
              hint: 'Egypt',
            ),
            const SizedBox(height: 12),
            _buildCountrySearchField(),
            const SizedBox(height: 12),
            AppTextField(
              label: 'عنوان الوجهة / التفريغ',
              controller: _destinationAddressCtrl,
              hint: 'العنوان التفصيلي للوجهة',
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            Divider(color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0)),
            const SizedBox(height: 12),
            _sectionTitle('الأصناف المشحونة'),
            const SizedBox(height: 12),
            ..._items
                .asMap()
                .entries
                .map((entry) => _buildItemCard(entry.key, entry.value)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => setState(() => _items.add(_ShipmentItem())),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppTheme.neonCyan.withValues(alpha: 0.06)
                      : const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: isDark
                          ? AppTheme.neonCyan.withValues(alpha: 0.25)
                          : const Color(0xFF0284C7),
                      width: 1.5,
                      style: BorderStyle.solid),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_circle_outline,
                        color: isDark ? AppTheme.neonCyan : const Color(0xFF0284C7),
                        size: 20),
                    const SizedBox(width: 8),
                    Text('إضافة صنف آخر',
                        style: TextStyle(
                            color: isDark ? AppTheme.neonCyan : const Color(0xFF0284C7),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildTotalsRow(),
            const SizedBox(height: 20),
            Divider(color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0)),
            const SizedBox(height: 12),
            _sectionTitle('الشروط والأحكام'),
            const SizedBox(height: 12),
            _buildTermsSection(),
            const SizedBox(height: 80),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildTermsSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isDark ? AppTheme.glassBorder : const Color(0xFFCBD5E1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0))),
              ),
              child: Text('TERMS OF SALE AND OTHER COMMENTS',
                  textAlign: TextAlign.left,
                  style: TextStyle(
                      color: isDark ? AppTheme.textPrimary : const Color(0xFF0F172A),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo')),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: isDark ? AppTheme.glassBorder : const Color(0xFFE2E8F0))),
              ),
              child: Text('TERMS AND CONDITIONS',
                  textAlign: TextAlign.left,
                  style: TextStyle(
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF334155),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo')),
            ),
            const SizedBox(height: 6),
            Text('Fruity Farms',
                textAlign: TextAlign.left,
                style: TextStyle(
                    color: isDark ? AppTheme.textPrimary : const Color(0xFF0F172A),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo')),
            const SizedBox(height: 12),
            _termsField('Port Of Loading', _portOfLoadingCtrl),
            const SizedBox(height: 10),
            _termsField('Port Of Destination', _portOfDestCtrl),
            const SizedBox(height: 10),
            _termsField('Terms Of Payment', _paymentTermsCtrl),
            const SizedBox(height: 10),
            _termsField('Mode Of Transport', _transportModeCtrl),
            const SizedBox(height: 12),
            Text(
                'All Banking Charges Out Of Egypt Including Remitting Charges Are On Applicants Account',
                textAlign: TextAlign.left,
                style: TextStyle(
                    color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                    fontSize: 11,
                    fontFamily: 'Cairo')),
            const SizedBox(height: 6),
            Text(
                'I Certify The Above To Be True And Correct To The Best Of My Knowledge',
                textAlign: TextAlign.left,
                style: TextStyle(
                    color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                    fontSize: 11,
                    fontFamily: 'Cairo')),
          ],
        ),
      ),
    );
  }
}

class _ShipmentItem {
  int? packingOrderId;
  int? lineId;
  int? productId;
  String grade;
  String? recipeName;
  int? recipeVersion;
  String hsCode;
  String countryOfOrigin;
  int? _maxCartons;
  final TextEditingController nameCtrl;
  final TextEditingController hsCodeCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController exportPricePerCartonCtrl;
  final TextEditingController weightPerCartonCtrl;
  final TextEditingController netWtCtrl;
  final TextEditingController grossWtCtrl;
  final TextEditingController amountCtrl;
  final TextEditingController palletsCtrl;
  final TextEditingController invoiceProductCtrl;

  String? packingOrderNumber;
  String? exportShipmentNo;
  String? customerName;

  _ShipmentItem(
      {this.packingOrderId,
      this.packingOrderNumber,
      this.exportShipmentNo,
      this.customerName,
      this.productId,
      this.grade = '',
      this.recipeName,
      this.recipeVersion,
      this.hsCode = '',
      this.countryOfOrigin = 'Egypt'})
      : nameCtrl = TextEditingController(),
        hsCodeCtrl = TextEditingController(text: hsCode),
        qtyCtrl = TextEditingController(text: '0'),
        priceCtrl = TextEditingController(text: '0'),
        exportPricePerCartonCtrl = TextEditingController(),
        weightPerCartonCtrl = TextEditingController(text: '15'),
        netWtCtrl = TextEditingController(text: '0'),
        grossWtCtrl = TextEditingController(text: '0'),
        amountCtrl = TextEditingController(text: '0'),
        palletsCtrl = TextEditingController(text: '0'),
        invoiceProductCtrl = TextEditingController();

  /// Number of cartons
  int get qty => int.tryParse(qtyCtrl.text.trim()) ?? 0;

  /// Production cost per carton in EGP (from product cost center / packing order)
  double get unitCostEgp => double.tryParse(priceCtrl.text.trim()) ?? 0.0;

  /// Total production cost in EGP = cartons * unit cost
  double get totalCostEgp => qty * unitCostEgp;

  /// Export price per carton in foreign currency (e.g., USD / EUR)
  double get exportPrice =>
      double.tryParse(exportPricePerCartonCtrl.text.trim()) ?? 0.0;

  /// Total export revenue in foreign currency (e.g., USD / EUR)
  double get totalRevenueForeign => qty * exportPrice;

  /// Total export revenue normalized into EGP using shipment active exchange rate
  double totalRevenueEgp(double exchangeRate) {
    final rate = exchangeRate > 0 ? exchangeRate : 1.0;
    return totalRevenueForeign * rate;
  }

  /// Net Profit / Loss in EGP = Converted Revenue (EGP) - Total Production Cost (EGP)
  double netProfitEgp(double exchangeRate) {
    return totalRevenueEgp(exchangeRate) - totalCostEgp;
  }

  /// Profit Margin % = (Net Profit (EGP) / Converted Revenue (EGP)) * 100
  double profitMarginPct(double exchangeRate) {
    final rev = totalRevenueEgp(exchangeRate);
    if (rev <= 0) return 0.0;
    return (netProfitEgp(exchangeRate) / rev) * 100;
  }

  void recalculate() {
    final q = qty;
    final activePrice = exportPrice > 0 ? exportPrice : unitCostEgp;
    final wpc = double.tryParse(weightPerCartonCtrl.text.trim()) ?? 0;
    final totalNet = wpc * q;
    netWtCtrl.text = totalNet.toStringAsFixed(0);
    amountCtrl.text = (q * activePrice).toStringAsFixed(2);
  }

  void dispose() {
    nameCtrl.dispose();
    hsCodeCtrl.dispose();
    qtyCtrl.dispose();
    priceCtrl.dispose();
    exportPricePerCartonCtrl.dispose();
    weightPerCartonCtrl.dispose();
    netWtCtrl.dispose();
    grossWtCtrl.dispose();
    amountCtrl.dispose();
    palletsCtrl.dispose();
    invoiceProductCtrl.dispose();
  }
}
