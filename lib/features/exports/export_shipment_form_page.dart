import 'dart:convert';
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
import '../../data/dao/packing_order_dao.dart';
import '../../data/models/packing_order_model.dart';
import '../../data/services/packing_calculation_service.dart';
import 'export_shipment_cubit.dart';
import 'shipment_constants.dart';
import 'invoice_preview_page.dart';
import 'credit_note_pdf_service.dart';

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
  List<PackingOrderModel>? _cachedAvailableOrders;

  List<CustomerModel> _customers = [];
  List<dynamic> _invoices = [];
  List<ClearingAgentModel> _clearingAgents = [];
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
    _selectedPaymentSourceType = s?.paymentSourceType ?? 'bank';
    _selectedTreasuryId = s?.paymentTreasuryId;
    _selectedBankAccountId = s?.paymentBankAccountId;
    _selectedTreasuryCurrency = s?.currency ?? s?.currencyCode ?? 'EGP';

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ExportShipmentCubit>().loadForm(widget.shipment?.id);
      _loadClearingAgents();
      _loadTreasuriesAndBanks();
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
    _discountAmountCtrl.dispose();
    _discountReasonCtrl.dispose();
    _paidAmountCtrl.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
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
      termsConditions: _termsConditionsCtrl.text.trim().isEmpty
          ? null
          : _termsConditionsCtrl.text.trim(),
      internalNotes: _internalNotesCtrl.text.trim().isEmpty
          ? null
          : _internalNotesCtrl.text.trim(),
      status: widget.shipment?.status ?? 'draft',
      shipmentDate: _shipmentDate ?? DateTime.now(),
      discountAmount: double.tryParse(_discountAmountCtrl.text.trim()) ?? 0.0,
      discountReason: _discountReasonCtrl.text.trim().isEmpty
          ? null
          : _discountReasonCtrl.text.trim(),
      paidAmount: double.tryParse(_paidAmountCtrl.text.trim()) ?? 0.0,
      paymentSourceType: _selectedPaymentSourceType ?? 'bank',
      paymentTreasuryId: _selectedTreasuryId,
      paymentBankAccountId: _selectedBankAccountId,
    );
    context.read<ExportShipmentCubit>().save(shipment, items: itemsData);
  }

  void _openPreview() {
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
      termsConditions: _buildTermsText(),
      status: widget.shipment?.status ?? 'draft',
      shipmentDate: _shipmentDate,
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

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.cyberBg,
        appBar: AppBar(
          title: Text(
            widget.shipment != null
                ? 'تعديل شحنة' // ${_getShipmentNo()}
                : 'شحنة جديدة',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.neonCyan,
                  side: const BorderSide(color: AppTheme.neonCyan, width: 1.2),
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
                    backgroundColor: isSaveDisabled ? Colors.white38 : Colors.white,
                    foregroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.primary))
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
                  _transportMode = s.transportMode ?? 'sea';
                  _transportModeCtrl.text = s.transportMode == 'air' ? 'By Air' : 'By Sea';
                  _incoterm = s.incoterm ?? 'FOB';
                  _currency = s.currency ?? s.currencyCode ?? 'EGP';
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
                    final item = _items.firstWhere((i) => i.packingOrderId == poId, orElse: () => _ShipmentItem());
                    final currentQty = int.tryParse(item.qtyCtrl.text) ?? 0;
                    item._maxCartons = freshPo.remainingCartons + currentQty;
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
    return Container(
      color: AppTheme.cyberBg,
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

        // Fallback: fetch packing order header (legacy behavior)
        final po = await _packingOrderDao.getById(item.packingOrderId!);
        if (po == null || !mounted) continue;

        setState(() {
          item.packingOrderNumber = po.orderNumber;
          double cost = po.packingCostPerCarton;
          if (lineData != null) {
            final totalCost = (lineData['final_cost'] as num?)?.toDouble() ?? 0.0;
            final lineCartons = (lineData['carton_count'] as num?)?.toInt() ?? 0;
            if (totalCost > 0 && lineCartons > 0) {
              cost = totalCost / lineCartons;
            } else if (po.packingCostPerCarton > 0) {
              cost = po.packingCostPerCarton;
            } else {
              final unitCost = (lineData['final_unit_cost'] as num?)?.toDouble() ?? 0.0;
              if (unitCost > 0) cost = unitCost;
            }
          } else {
            cost = po.packingCostPerCarton;
          }
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final fontSize = constraints.maxWidth < 400 ? 16.0 : 18.0;
        return Text(t,
            style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontFamily: 'Cairo'));
      },
    );
  }

  Widget _termsField(String label, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            textAlign: TextAlign.left,
            style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'Cairo')),
        const SizedBox(height: 2),
        TextField(
          controller: ctrl,
          textAlign: TextAlign.left,
          style: const TextStyle(
              color: AppTheme.textPrimary, fontSize: 13, fontFamily: 'Cairo'),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
            filled: false,
            border: UnderlineInputBorder(
                borderSide: BorderSide(color: AppTheme.glassBorder)),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppTheme.glassBorder)),
            focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppTheme.primary, width: 1.5)),
          ),
        ),
      ],
    );
  }

  Widget _formLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t,
            style: const TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
                fontFamily: 'Cairo',
                fontSize: 13)),
      );

  Widget _buildLeftPanel(ExportShipmentCubit c, bool isDesktop) {
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
                );
                if (date != null) setState(() => _shipmentDate = date);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: AppTheme.neonCyan.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(8),
                  color: AppTheme.cyberSurface,
                ),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 16, color: AppTheme.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _shipmentDate != null
                          ? AppUtils.formatDate(_shipmentDate!)
                          : 'اختر التاريخ',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontFamily: 'Cairo', fontSize: 14),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            AppSearchField<CustomerModel>(
              label: 'العميل',
              controller: _customerSearchCtrl,
              isRequired: true,
              hint: 'ابحث بالاسم أو الكود...',
              prefixIcon: const Icon(Icons.person_outline, size: 18),
              highlightColor: AppTheme.primary.withValues(alpha: 0.5),
              suggestionsCallback: (pattern) {
                if (pattern.isEmpty) return _customers;
                return _customers
                    .where((cu) =>
                        cu.name.toLowerCase().contains(pattern.toLowerCase()))
                    .toList();
              },
              itemBuilder: (context, cu) {
                return ListTile(
                  title: Text(cu.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Cairo',
                          fontSize: 15)),
                  subtitle: Text(cu.name,
                      style: const TextStyle(
                          color: AppTheme.textSecondary,
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
                      style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Cairo',
                          fontSize: 15)),
                  subtitle: Text('${agent.phone} - ${agent.city}',
                      style: const TextStyle(
                          color: AppTheme.textSecondary,
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
            const SizedBox(height: 12),
            _formLabel('مبلغ الخصم (اختياري)'),
            AppTextField(
              label: 'مبلغ الخصم (اختياري)',
              controller: _discountAmountCtrl,
              hint: '0.00',
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            // AppTextField(
            //   label: 'سبب الخصم (اختياري)',
            //   controller: _discountReasonCtrl,
            //   hint: 'سبب الخصم...',
            //   maxLines: 2,
            // ),
            const SizedBox(height: 16),
            _formLabel('المبلغ المدفوع من العميل ($_currency)'),
            AppTextField(
              label: 'المبلغ المدفوع من العميل ($_currency)',
              controller: _paidAmountCtrl,
              hint: '0',
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
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
      color: AppTheme.cyberSurface,
      padding: const EdgeInsets.all(16),
      child: isDesktop ? SingleChildScrollView(child: content) : content,
    );
  }

  Widget _buildPaymentSourceDropdown() {
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
            dropdownColor: const Color(0xFF0A2A4A),
            style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
            decoration: InputDecoration(
              labelText: 'اختر الحساب البنكي',
              labelStyle: const TextStyle(color: AppTheme.textSecondary, fontFamily: 'Cairo'),
              filled: true,
              fillColor: const Color(0x3805192D),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.glassBorder)),
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
                    const Icon(Icons.account_balance, size: 14, color: AppTheme.cyan),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'بنك - $bName ($bCurr) — ${balance.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 12),
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
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(children: [
        Text('$label: ',
            style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontFamily: 'Cairo')),
        Expanded(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white, fontSize: 11, fontFamily: 'Cairo'))),
      ]),
    );
  }

  Widget _buildTransportRadios() {
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
                  ? AppTheme.neonCyan.withValues(alpha: 0.08)
                  : AppTheme.cyberSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: selected ? AppTheme.neonCyan : AppTheme.border,
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
                  color: selected ? AppTheme.neonCyan : Colors.grey,
                ),
                const SizedBox(width: 6),
                Text(labels[i],
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      color:
                          selected ? AppTheme.neonCyan : AppTheme.textSecondary,
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
    const values = ['EGP', 'USD', 'EUR', 'GBP'];
    const labels = ['جنيه', 'دولار', 'يورو', 'جنيه إسترليني'];
    final locked = _selectedCustomerId != null;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List.generate(4, (i) {
        final selected = _currency == values[i];
        return GestureDetector(
          onTap: locked ? null : () => setState(() => _currency = values[i]),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.neonCyan.withValues(alpha: 0.08)
                  : AppTheme.cyberSurface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: selected ? AppTheme.neonCyan : AppTheme.border,
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
                  color: selected ? AppTheme.neonCyan : Colors.grey,
                ),
                const SizedBox(width: 3),
                Text(labels[i],
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: selected
                          ? AppTheme.neonCyan
                          : AppTheme.textSecondary,
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
        color: AppTheme.neonCyan.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.12)),
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
            displayStringForOption: (po) => po.productName ?? po.orderNumber,
            suggestionsCallback: (pattern) async {
              _cachedAvailableOrders ??=
                  await _packingOrderDao.getAvailableForShipment();
                  
              final selectedIds = _items
                  .where((i) => i != item && (i.lineId != null || i.packingOrderId != null))
                  .map((i) => i.lineId?.toString() ?? i.packingOrderId?.toString())
                  .toSet();

              final filteredOrders = _cachedAvailableOrders!
                  .where((po) => !selectedIds.contains(po.lineId?.toString() ?? po.id?.toString()))
                  .toList();

              if (pattern.isEmpty) return filteredOrders;
              final lower = pattern.toLowerCase();
              return filteredOrders
                  .where((po) =>
                      (po.productName?.toLowerCase().contains(lower) ??
                          false) ||
                      po.orderNumber.toLowerCase().contains(lower))
                  .toList();
            },
            itemBuilder: (context, po) => Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(po.orderNumber,
                      style: const TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                          fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(po.productName ?? po.orderNumber,
                      style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Cairo',
                          fontSize: 14)),
                  Text(
                      'متبقي: ${po.remainingCartons} كرتونة من ${po.cartonCount} | Net: ${po.totalNetWeight.toStringAsFixed(1)} KG',
                      style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontFamily: 'Cairo',
                          fontSize: 12)),
                  if (po.packedAt != null || po.createdAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                        'تاريخ التعبئة: ${AppUtils.formatDate(po.packedAt ?? po.createdAt!)}',
                        style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontFamily: 'Cairo',
                            fontSize: 11)),
                  ],
                ],
              ),
            ),
            onSelected: (po) async {
              if (!mounted) return;
              _cachedAvailableOrders = null;
              
              double packingCostPerCarton = po.packingCostPerCarton;
              
              if (po.lineId != null) {
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
                    } else if (po.packingCostPerCarton > 0) {
                      packingCostPerCarton = po.packingCostPerCarton;
                    } else {
                      final unitCost = (lineData['final_unit_cost'] as num?)?.toDouble() ?? 0.0;
                      if (unitCost > 0) packingCostPerCarton = unitCost;
                    }
                  }
                } catch (e) {
                  debugPrint('Line cost fetch error: $e');
                }
              }

              final remaining = po.remainingCartons;
              final weightRatio = remaining > 0 && po.cartonCount > 0
                  ? remaining / po.cartonCount
                  : 1.0;

              setState(() {
                item.packingOrderId = int.tryParse(po.id ?? '');
                item.packingOrderNumber = po.orderNumber;
                item.lineId = po.lineId;
                item.productId = int.tryParse(po.fruitTypeId ?? '');
                item.grade = po.grade;
                item.recipeName = po.recipeName;
                item.recipeVersion = po.recipeVersion;
                item.nameCtrl.text = po.productName ?? po.orderNumber;
                item.invoiceProductCtrl.text = po.productName ?? '';
                item._maxCartons = remaining;
                item.qtyCtrl.text = remaining.toString();
                item.weightPerCartonCtrl.text =
                    po.netWeightPerCarton.toStringAsFixed(0);
                item.priceCtrl.text = packingCostPerCarton.toStringAsFixed(2);
                if (po.productName != null) {
                  item.hsCode = '';
                  item.hsCodeCtrl.text = '';
                }
                item.recalculate();
                final remainingGross = po.totalGrossWeight * weightRatio;
                if (remainingGross > 0) {
                  item.grossWtCtrl.text = remainingGross.toStringAsFixed(0);
                } else if (po.totalNetWeight > 0) {
                  item.grossWtCtrl.text =
                      (po.totalNetWeight * weightRatio).toStringAsFixed(0);
                }
              });
            },
            emptyBuilder: (context) => const Padding(
              padding: EdgeInsets.all(12),
              child: Text('لا توجد أوامر تعبئة جاهزة للشحن',
                  style: TextStyle(
                      color: AppTheme.textMuted, fontFamily: 'Cairo')),
            ),
          ),
          if (item.hsCode.isNotEmpty) ...[
            const SizedBox(height: 6),
            _infoLabel('كود HS الجمركي: ${item.hsCode}'),
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
                        'تكلفة التعبئة للكرتونة (ج.م)',
                        '${(double.tryParse(item.priceCtrl.text) ?? 0).toStringAsFixed(2)} ج.م'),
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
                        'تكلفة التعبئة للكرتونة (ج.م)',
                        '${(double.tryParse(item.priceCtrl.text) ?? 0).toStringAsFixed(2)} ج.م')),
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
          _sectionLabel('بيانات التصدير'),
          const SizedBox(height: 8),
          _buildSummaryRow(item, symbol),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(text,
        style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cairo',
            letterSpacing: 0.5));
  }

  Widget _buildSummaryRow(_ShipmentItem item, String symbol) {
    final qty = int.tryParse(item.qtyCtrl.text) ?? 0;
    final netWt = double.tryParse(item.netWtCtrl.text) ?? 0;
    final grossWt = double.tryParse(item.grossWtCtrl.text) ?? 0;
    final exportPrice =
        double.tryParse(item.exportPricePerCartonCtrl.text) ?? 0;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.neonCyan.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ملخص الصنف',
              style: TextStyle(
                  color: AppTheme.neonCyan,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 8,
            children: [
              _summaryCell('عدد الكراتين', '$qty'),
              _summaryCell('الوزن الصافي', '${netWt.toStringAsFixed(0)} كجم'),
              _summaryCell('الوزن الإجمالي', '${grossWt.toStringAsFixed(0)} كجم'),
              _summaryCell('سعر الكرتونة التصديري', exportPrice > 0 ? '$symbol ${exportPrice.toStringAsFixed(2)}' : '—'),
              _summaryCell('إجمالي القيمة',
                  '$symbol ${(qty * exportPrice).toStringAsFixed(2)}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryCell(String label, String value) {
    return SizedBox(
      width: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 10,
                  fontFamily: 'Cairo')),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
        ],
      ),
    );
  }

  Widget _infoLabel(String text, {bool bold = false, bool primary = false}) {
    return Text(text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            color: primary ? AppTheme.primary : AppTheme.textPrimary,
            fontSize: 13,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            fontFamily: 'Cairo'));
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  fontFamily: 'Cairo')),
          const SizedBox(height: 2),
          Text(value.isEmpty ? '0' : value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Cairo')),
        ],
      ),
    );
  }

  Widget _buildTotalsRow() {
    final symbol = _currencySymbol();
    final itemsCount =
        _items.where((i) => i.nameCtrl.text.trim().isNotEmpty).length;
    final totalCartons =
        _items.fold(0, (sum, i) => sum + (int.tryParse(i.qtyCtrl.text) ?? 0));
    final totalNetWt = _items.fold(
        0.0, (sum, i) => sum + (double.tryParse(i.netWtCtrl.text) ?? 0));
    final totalGrossWt = _items.fold(
        0.0, (sum, i) => sum + (double.tryParse(i.grossWtCtrl.text) ?? 0));
    final totalAmount = _items.fold(
        0.0, (sum, i) => sum + (double.tryParse(i.amountCtrl.text) ?? 0));
    final totalPallets = _items.fold(
        0, (sum, i) => sum + (int.tryParse(i.palletsCtrl.text) ?? 0));
    final totalCostEgp = _items.fold<double>(0.0, (sum, i) {
      final cost = double.tryParse(i.priceCtrl.text) ?? 0;
      final qty = int.tryParse(i.qtyCtrl.text) ?? 0;
      return sum + (cost * qty);
    });
    final totalExportRevenue = _items.fold<double>(0.0, (sum, i) {
      final ep = double.tryParse(i.exportPricePerCartonCtrl.text) ?? 0;
      final qty = int.tryParse(i.qtyCtrl.text) ?? 0;
      return sum + (ep * qty);
    });
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.calculate_outlined,
                size: 16, color: AppTheme.primary),
            const SizedBox(width: 6),
            const Text('ملخص الشحنة ككل',
                style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo')),
          ]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _totalItem('الأصناف', '$itemsCount'),
              _totalItem('عدد الكراتين', '$totalCartons'),
              if (_transportMode != 'air')
                _totalItem('عدد البالتات', '$totalPallets'),
              _totalItem('الوزن الصافي', '${totalNetWt.toStringAsFixed(0)} كجم'),
              _totalItem('الوزن الإجمالي', '${totalGrossWt.toStringAsFixed(0)} كجم'),
              _totalItem('إجمالي القيمة',
                  '$symbol ${totalAmount.toStringAsFixed(2)} $_currency'),
              _totalItem('إجمالي التكلفة', '${totalCostEgp.toStringAsFixed(2)} ج.م'),
              _totalItem('إجمالي التصدير', totalExportRevenue > 0 ? '$symbol ${totalExportRevenue.toStringAsFixed(2)}' : '—'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _totalItem(String label, String value) {
    return SizedBox(
      width: 140,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Text('$label: ',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontFamily: 'Cairo')),
            Expanded(
                child: Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
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
              color: AppTheme.neonCyan.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppTheme.neonCyan.withValues(alpha: 0.15)),
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
                  const Divider(height: 16, color: AppTheme.glassBorder),
                  const Text('جهة الاتصال',
                      style: TextStyle(
                          color: AppTheme.neonCyan,
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
                  const Divider(height: 16, color: AppTheme.glassBorder),
                  const Text('العناوين',
                      style: TextStyle(
                          color: AppTheme.neonCyan,
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
                            style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 12,
                                fontFamily: 'Cairo')),
                      )),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Divider(),
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
              border: Border.all(color: AppTheme.glassBorder),
              borderRadius: BorderRadius.circular(12),
              color: AppTheme.cyberSurface,
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
                dropdownColor: const Color(0xCC05192D),
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
                      style: const TextStyle(
                          color: Colors.white,
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Flexible(
            flex: 0,
            child: Text('$label: ',
                style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontFamily: 'Cairo')),
          ),
          Expanded(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  Widget _buildCountrySearchField() {
    return AppSearchField<String>(
      label: 'دولة الوجهة',
      isRequired: true,
      controller: _countryCtrl,
      hint: 'أدخل الدولة الوجهة',
      emptyBuilder: (context) => const Padding(
        padding: EdgeInsets.all(12.0),
        child: Text('اكتب اسم الدولة مباشرة',
            style: TextStyle(
                color: AppTheme.textMuted, fontFamily: 'Cairo')),
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
            style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'Cairo')),
      ),
      onSelected: (country) {
        _countryCtrl.text = country;
      },
      displayStringForOption: (s) => s,
    );
  }

  Widget _buildRightPanel() {
    return Container(
      color: AppTheme.cyberBg,
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
                      width: 1.5,
                      style: BorderStyle.solid),
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
      ),
    );
  }

  Widget _buildTermsSection() {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: AppTheme.glassBorder)),
              ),
              child: const Text('TERMS OF SALE AND OTHER COMMENTS',
                  textAlign: TextAlign.left,
                  style: TextStyle(
                      color: AppTheme.textPrimary,
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
                    bottom: BorderSide(color: AppTheme.glassBorder)),
              ),
              child: const Text('TERMS AND CONDITIONS',
                  textAlign: TextAlign.left,
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo')),
            ),
            const SizedBox(height: 6),
            const Text('Fruity Farms',
                textAlign: TextAlign.left,
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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
            const Text(
                'All Banking Charges Out Of Egypt Including Remitting Charges Are On Applicants Account',
                textAlign: TextAlign.left,
                style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontFamily: 'Cairo')),
            const SizedBox(height: 6),
            const Text(
                'I Certify The Above To Be True And Correct To The Best Of My Knowledge',
                textAlign: TextAlign.left,
                style: TextStyle(
                    color: AppTheme.textSecondary,
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

  _ShipmentItem(
      {this.packingOrderId,
      this.packingOrderNumber,
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

  void recalculate() {
    final qty = int.tryParse(qtyCtrl.text) ?? 0;
    final price = double.tryParse(exportPricePerCartonCtrl.text.isNotEmpty
            ? exportPricePerCartonCtrl.text
            : priceCtrl.text) ??
        0;
    final wpc = double.tryParse(weightPerCartonCtrl.text) ?? 0;
    final totalNet = wpc * qty;
    netWtCtrl.text = totalNet.toStringAsFixed(0);
    amountCtrl.text = (qty * price).toStringAsFixed(2);
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
