import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme.dart';
import 'proforma_invoice_model.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/clearing_agent_model.dart';
import '../../ui/widgets/app_text_field.dart';
import '../../ui/widgets/app_search_field.dart';
import 'proforma_invoice_cubit.dart';
import '../exports/shipment_constants.dart';
import '../../core/utils.dart';
import 'proforma_invoice_word_service.dart';

class ProformaInvoiceFormPage extends StatefulWidget {
  final ProformaInvoiceModel? invoice;
  const ProformaInvoiceFormPage({super.key, this.invoice});

  @override
  State<ProformaInvoiceFormPage> createState() =>
      _ProformaInvoiceFormPageState();
}

class _ProformaInvoiceFormPageState extends State<ProformaInvoiceFormPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _manualCodeCtrl;
  late TextEditingController _customerSearchCtrl;
  late TextEditingController _contactPersonCtrl;
  late TextEditingController _countryCtrl;
  late TextEditingController _destinationAddressCtrl;
  late TextEditingController _containerNoCtrl;
  late TextEditingController _vesselNameCtrl;
  late TextEditingController _blNoCtrl;
  late TextEditingController _dataLoggerCtrl;
  late TextEditingController _portOfLoadingCtrl;
  late TextEditingController _portOfDestCtrl;
  late TextEditingController _paymentTermsCtrl;
  late TextEditingController _clearingAgentSearchCtrl;

  String _transportMode = 'sea';
  String? _currency;
  DateTime? _invoiceDate;
  bool _isSaving = false;

  String? _selectedCustomerId;
  CustomerModel? _selectedCustomer;
  String _customerDisplayText = '';
  String _customerCode = '';
  String? _selectedClearingAgentId;
  String? _selectedClearingAgentName;
  int? _selectedAddressIndex;

  List<_ProformaItem> _items = [];

  @override
  void initState() {
    super.initState();
    _manualCodeCtrl = TextEditingController();
    _customerSearchCtrl = TextEditingController();
    _contactPersonCtrl = TextEditingController();
    _countryCtrl = TextEditingController();
    _destinationAddressCtrl = TextEditingController();
    _containerNoCtrl = TextEditingController();
    _vesselNameCtrl = TextEditingController();
    _blNoCtrl = TextEditingController();
    _dataLoggerCtrl = TextEditingController();
    _portOfLoadingCtrl = TextEditingController();
    _portOfDestCtrl = TextEditingController();
    _paymentTermsCtrl = TextEditingController();
    _clearingAgentSearchCtrl = TextEditingController();
    _invoiceDate = DateTime.now();
    _dataLoggerCtrl.text = 'TBA';
    _items.add(_ProformaItem());

    if (widget.invoice != null) {
      _populateFromInvoice(widget.invoice!);
    }
  }

  void _populateFromInvoice(ProformaInvoiceModel inv) {
    final parts = inv.invoiceNo.split('/');
    if (parts.length >= 3) {
      if (parts[0].length == 2 && int.tryParse(parts[0]) != null) {
        _manualCodeCtrl.text = parts.last; // 26/CUST/1
      } else if (parts.last.length == 2 && int.tryParse(parts.last) != null) {
        _manualCodeCtrl.text = parts.first; // 1/CUST/26
      } else if (parts[1].length == 2 && int.tryParse(parts[1]) != null) {
        _manualCodeCtrl.text = parts.last; // CUST/26/1
      } else {
        _manualCodeCtrl.text = parts.last;
      }
    } else if (parts.isNotEmpty) {
      _manualCodeCtrl.text = parts.first;
    }
    _customerDisplayText = inv.customerName ?? '';
    _customerCode = inv.customerCode ?? '';
    _customerSearchCtrl.text = inv.customerName ?? '';
    _contactPersonCtrl.text = inv.contactPerson ?? '';
    _countryCtrl.text = inv.country ?? '';
    _destinationAddressCtrl.text = inv.destinationAddress ?? '';
    _containerNoCtrl.text = inv.containerNo ?? '';
    _vesselNameCtrl.text = inv.vesselName ?? '';
    _blNoCtrl.text = inv.blNumber ?? '';
    _dataLoggerCtrl.text = inv.dataLoggerNo ?? 'TBA';
    _portOfLoadingCtrl.text = inv.portOfLoading ?? '';
    _portOfDestCtrl.text = inv.portOfDestination ?? '';
    _transportMode = inv.transportMode;
    _currency = inv.currency;
    _selectedCustomerId = inv.customerId;
    _selectedClearingAgentId = inv.clearingAgentId;
    _selectedClearingAgentName = inv.clearingAgentName;
    _paymentTermsCtrl.text = inv.paymentTerms ?? '';
    _invoiceDate = inv.invoiceDate;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final st = context.read<ProformaInvoiceCubit>().state;
      if (st is ProformaInvoiceFormLoaded) {
        final found = st.customers.where((c) => c.id == inv.customerId);
        if (found.isNotEmpty) {
          setState(() => _selectedCustomer = found.first);
        }
        if (inv.clearingAgentId != null) {
          final agentFound =
              st.clearingAgents.where((a) => a.id == inv.clearingAgentId);
          if (agentFound.isNotEmpty) {
            _selectedClearingAgentName = agentFound.first.name;
            _clearingAgentSearchCtrl.text = agentFound.first.name;
          }
        }
      }
    });

    _updateInvoiceNo();
  }

  String get _invoiceNo {
    final manual = _manualCodeCtrl.text.trim();
    final year = _invoiceDate != null
        ? (_invoiceDate!.year % 100).toString().padLeft(2, '0')
        : '--';
    final invCode = manual.isEmpty ? '--' : manual;
    final custCode = _customerCode.isEmpty ? '----' : _customerCode;
    return '$year/$custCode/$invCode';
  }

  void _updateInvoiceNo() {
    setState(() {});
  }



  @override
  void dispose() {
    _manualCodeCtrl.dispose();
    _customerSearchCtrl.dispose();
    _contactPersonCtrl.dispose();
    _countryCtrl.dispose();
    _destinationAddressCtrl.dispose();
    _containerNoCtrl.dispose();
    _vesselNameCtrl.dispose();
    _blNoCtrl.dispose();
    _dataLoggerCtrl.dispose();
    _portOfLoadingCtrl.dispose();
    _portOfDestCtrl.dispose();
    _paymentTermsCtrl.dispose();
    _clearingAgentSearchCtrl.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.cyberBg,
        appBar: AppBar(
          backgroundColor: AppTheme.cyberSurface,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            widget.invoice != null
                ? 'تعديل فاتورة مبدئية'
                : 'فاتورة مبدئية جديدة',
            style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
                fontSize: 16),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            _buildSaveButton(),
            const SizedBox(width: 4),
          ],
        ),
        body: BlocListener<ProformaInvoiceCubit, ProformaInvoiceState>(
          listener: (context, state) {
            if (state is ProformaInvoiceFormLoaded) {
              if (widget.invoice != null && state.invoice != null) {
                if (state.items.isNotEmpty) {
                  setState(() {
                    _items = state.items.map((item) {
                      final pItem = _ProformaItem();
                      pItem.nameCtrl.text = item.productName;
                      pItem.qtyCtrl.text = item.quantity.toString();
                      pItem.priceCtrl.text = item.pricePerCarton.toString();
                      pItem.netWtCtrl.text = item.netWeight.toString();
                      pItem.grossWtCtrl.text = item.grossWeight.toString();
                      pItem.palletsCtrl.text = item.palletsCount.toString();
                      return pItem;
                    }).toList();
                  });
                }

                if (widget.invoice!.customerId != null) {
                  final found = state.customers
                      .where((c) => c.id == widget.invoice!.customerId);
                  if (found.isNotEmpty) {
                    setState(() {
                      _selectedCustomer = found.first;
                    });
                  }
                }

                if (widget.invoice!.clearingAgentId != null) {
                  final agentFound = state.clearingAgents
                      .where((a) => a.id == widget.invoice!.clearingAgentId);
                  if (agentFound.isNotEmpty) {
                    setState(() {
                      _selectedClearingAgentName = agentFound.first.name;
                      _clearingAgentSearchCtrl.text =
                          '${agentFound.first.code} - ${agentFound.first.name}';
                    });
                  }
                }
              }
            } else if (state is ProformaInvoiceOperationSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(state.message),
                    backgroundColor: AppTheme.success),
              );
              Navigator.pop(context, true);
            } else if (state is ProformaInvoiceError) {
              setState(() => _isSaving = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(state.message),
                    backgroundColor: AppTheme.danger),
              );
            }
          },
          child: Form(
            key: _formKey,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 1024;
                if (isWide) {
                  return _buildWideLayout();
                }
                return _buildStackedLayout();
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 320, child: _buildSidebar()),
        const VerticalDivider(width: 1),
        Expanded(child: _buildMainContent()),
      ],
    );
  }

  Widget _buildStackedLayout() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSidebar(),
          const Divider(height: 1),
          _buildMainContentStacked(),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    final st = context.watch<ProformaInvoiceCubit>().state;
    final customers =
        st is ProformaInvoiceFormLoaded ? st.customers : <CustomerModel>[];
    final agents = st is ProformaInvoiceFormLoaded
        ? st.clearingAgents
        : <ClearingAgentModel>[];
    final bank = _currency != null ? BankDetails.forCurrency(_currency!) : null;

    return Container(
      color: AppTheme.cyberSurface,
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('معلومات الفاتورة'),
            const SizedBox(height: 12),
            _formLabel('رقم الفاتورة'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.neonCyan.withAlpha(8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.neonCyan.withAlpha(50)),
              ),
              child: Row(
                children: [
                  Icon(Icons.tag, color: AppTheme.neonCyan, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        _invoiceNo,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: AppTheme.neonCyan,
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withAlpha(20),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('تلقائي',
                        style: TextStyle(
                            color: AppTheme.success,
                            fontSize: 10,
                            fontFamily: 'Cairo')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _formLabel('الكود اليدوي'),
            AppTextField(
              controller: _manualCodeCtrl,
              label: 'مثال: 001',
              onChanged: (_) => _updateInvoiceNo(),
            ),
            const SizedBox(height: 12),
            _formLabel('تاريخ الفاتورة'),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _invoiceDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (picked != null) {
                  setState(() => _invoiceDate = picked);
                  _updateInvoiceNo();
                }
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.cyberSurface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today,
                        color: AppTheme.textMuted, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      _invoiceDate != null
                          ? '${_invoiceDate!.year}/${_invoiceDate!.month.toString().padLeft(2, '0')}/${_invoiceDate!.day.toString().padLeft(2, '0')}'
                          : 'اختر التاريخ',
                      style: TextStyle(
                          color: _invoiceDate != null
                              ? AppTheme.textPrimary
                              : AppTheme.textMuted,
                          fontFamily: 'Cairo',
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _formLabel('العميل', required: true),
            AppSearchField<CustomerModel>(
              controller: _customerSearchCtrl,
              label: 'ابحث بالاسم أو الكود...',
              suggestionsCallback: (query) async {
                if (query.isEmpty) return customers;
                return customers
                    .where((c) =>
                        c.name.toLowerCase().contains(query.toLowerCase()) ||
                        (c.code.toLowerCase().contains(query.toLowerCase())))
                    .toList();
              },
              itemBuilder: (context, c) => ListTile(
                title:
                    Text(c.name, style: const TextStyle(fontFamily: 'Cairo')),
                subtitle: Text(c.code,
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 11)),
              ),
              onSelected: (c) {
                setState(() {
                  _selectedCustomerId = c.id;
                  _selectedCustomer = c;
                  _customerDisplayText = c.name;
                  _customerCode = c.code;
                  _customerSearchCtrl.text = c.name;
                  _contactPersonCtrl.text = c.contactPersonName;
                  _countryCtrl.text = c.country;
                  _destinationAddressCtrl.text = c.addresses.isNotEmpty
                      ? (c.addresses[0]['full_address'] ??
                          c.addresses[0]['address'] ??
                          '')
                      : '';
                  _selectedAddressIndex = c.addresses.isNotEmpty ? 0 : null;
                  if (c.currency.isNotEmpty) _currency = c.currency;
                });
                _updateInvoiceNo();
              },
            ),
            Builder(
              builder: (ctx) {
                CustomerModel? currentCustomer = _selectedCustomer;
                if (currentCustomer == null && _selectedCustomerId != null) {
                  final match =
                      customers.where((c) => c.id == _selectedCustomerId);
                  if (match.isNotEmpty) {
                    currentCustomer = match.first;
                  }
                }
                if (currentCustomer != null) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      _buildCustomerCard(currentCustomer),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            const SizedBox(height: 12),
            _formLabel('وسيلة النقل'),
            _buildTransportRadios(),
            const SizedBox(height: 12),
            AppSearchField<ClearingAgentModel>(
              controller: _clearingAgentSearchCtrl,
              label: _transportMode == 'sea'
                  ? 'المخلص البحري'
                  : _transportMode == 'air'
                      ? 'المخلص الجوي'
                      : 'المخلص البري',
              hint: _transportMode == 'sea'
                  ? 'ابحث عن مخلص بحري...'
                  : _transportMode == 'air'
                      ? 'ابحث عن مخلص جوي...'
                      : 'ابحث عن مخلص بري...',
              suggestionsCallback: (query) async {
                final targetType = _transportMode == 'sea' ? 'بحري' : 'جوي';
                var filtered =
                    agents.where((a) => a.brokerType == targetType).toList();
                if (query.isEmpty) return filtered;
                return filtered
                    .where((a) =>
                        a.name.toLowerCase().contains(query.toLowerCase()) ||
                        a.code.toLowerCase().contains(query.toLowerCase()))
                    .toList();
              },
              itemBuilder: (context, a) => ListTile(
                title: Text('${a.code} - ${a.name}',
                    style: const TextStyle(fontFamily: 'Cairo')),
              ),
              onSelected: (a) {
                setState(() {
                  _selectedClearingAgentId = a.id;
                  _selectedClearingAgentName = a.name;
                  _clearingAgentSearchCtrl.text = '${a.code} - ${a.name}';
                  if (a.currency.isNotEmpty) _currency = a.currency;
                });
              },
            ),
            if (_selectedClearingAgentId != null) ...[
              const SizedBox(height: 12),
              _buildClearingAgentCard(agents.firstWhere(
                  (a) => a.id == _selectedClearingAgentId,
                  orElse: () =>
                      ClearingAgentModel(name: 'Unknown', createdAt: ''))),
            ],
            const SizedBox(height: 12),
            _formLabel('العملة'),
            _buildCurrencyRadios(),
            if (bank != null) ...[
              const SizedBox(height: 12),
              _buildBankInfo(bank),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return Container(
      color: AppTheme.cyberBg,
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('بيانات الشحن'),
            const SizedBox(height: 12),
            _formLabel(_transportMode == 'sea' ? 'رقم بوليصة الشحن (BL)' : 'رقم بوليصة الشحن (AWB)'),
            AppTextField(controller: _blNoCtrl, label: _transportMode == 'sea' ? 'رقم بوليصة الشحن (BL)' : 'AWB Number'),
            const SizedBox(height: 12),
            if (_transportMode == 'sea') ...[
              _formLabel('اسم السفينة'),
              AppTextField(controller: _vesselNameCtrl, label: 'TBA'),
              const SizedBox(height: 12),
              _formLabel('رقم الحاوية'),
              AppTextField(
                  controller: _containerNoCtrl, label: 'مثال: MSCU1234567'),
              const SizedBox(height: 12),
              _formLabel('رقم مسجل البيانات (Data Logger)'),
              AppTextField(controller: _dataLoggerCtrl, label: 'TBA'),
              const SizedBox(height: 12),
            ],
            _formLabel('بلد المنشأ'),
            AppTextField(controller: _countryCtrl, label: 'Egypt'),
            const SizedBox(height: 12),
            _formLabel('عنوان الوصول / التفريغ'),
            AppTextField(
              controller: _destinationAddressCtrl,
              label: 'العنوان التفصيلي للوصول',
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            const Divider(),
            _sectionTitle('الأصناف المشحونة'),
            const SizedBox(height: 12),
            _buildItemsTable(),
            const SizedBox(height: 12),
            _buildAddItemButton(),
            const SizedBox(height: 20),
            _buildTotalsSummary(),
            const SizedBox(height: 20),
            const Divider(),
            _sectionTitle('الشروط والأحكام'),
            const SizedBox(height: 12),
            _buildTermsSection(),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContentStacked() {
    return Container(
      color: AppTheme.cyberBg,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('بيانات الشحن'),
          const SizedBox(height: 12),
          _formLabel(_transportMode == 'sea' ? 'رقم بوليصة الشحن (BL)' : 'رقم بوليصة الشحن (AWB)'),
          AppTextField(controller: _blNoCtrl, label: _transportMode == 'sea' ? 'رقم بوليصة الشحن (BL)' : 'AWB Number'),
          const SizedBox(height: 12),
          if (_transportMode == 'sea') ...[
            _formLabel('اسم السفينة'),
            AppTextField(controller: _vesselNameCtrl, label: 'TBA'),
            const SizedBox(height: 12),
            _formLabel('رقم الحاوية'),
            AppTextField(
                controller: _containerNoCtrl, label: 'مثال: MSCU1234567'),
            const SizedBox(height: 12),
            _formLabel('رقم مسجل البيانات (Data Logger)'),
            AppTextField(controller: _dataLoggerCtrl, label: 'TBA'),
            const SizedBox(height: 12),
          ],
          _formLabel('بلد المنشأ'),
          AppTextField(controller: _countryCtrl, label: 'Egypt'),
          const SizedBox(height: 12),
          _formLabel('عنوان الوصول / التفريغ'),
          AppTextField(
            controller: _destinationAddressCtrl,
            label: 'العنوان التفصيلي للوصول',
            maxLines: 2,
          ),
          const SizedBox(height: 20),
          const Divider(),
          _sectionTitle('الأصناف المشحونة'),
          const SizedBox(height: 12),
          _buildItemsTable(),
          const SizedBox(height: 12),
          _buildAddItemButton(),
          const SizedBox(height: 20),
          _buildTotalsSummary(),
          const SizedBox(height: 20),
          const Divider(),
          _sectionTitle('الشروط والأحكام'),
          const SizedBox(height: 12),
          _buildTermsSection(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title,
        style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cairo'));
  }

  Widget _formLabel(String label, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Cairo')),
          if (required) ...[
            const SizedBox(width: 4),
            const Text('*',
                style: TextStyle(color: AppTheme.danger, fontSize: 13)),
          ],
        ],
      ),
    );
  }

  Widget _buildTransportRadios() {
    return Row(
      children: [
        _buildRadioOption('بحري', 'sea', _transportMode == 'sea', () {
          setState(() {
            if (_transportMode != 'sea') {
              _selectedClearingAgentId = null;
              _clearingAgentSearchCtrl.clear();
            }
            _transportMode = 'sea';
          });
        }),
        const SizedBox(width: 8),
        _buildRadioOption('جوي', 'air', _transportMode == 'air', () {
          setState(() {
            if (_transportMode != 'air') {
              _selectedClearingAgentId = null;
              _clearingAgentSearchCtrl.clear();
            }
            _transportMode = 'air';
          });
        }),
      ],
    );
  }

  Widget _buildCurrencyRadios() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _buildRadioOption('جنيه', 'EGP', _currency == 'EGP', () {
          setState(() => _currency = 'EGP');
        }),
        _buildRadioOption('دولار', 'USD', _currency == 'USD', () {
          setState(() => _currency = 'USD');
        }),
        _buildRadioOption('يورو', 'EUR', _currency == 'EUR', () {
          setState(() => _currency = 'EUR');
        }),
        _buildRadioOption('جنيه استرالي', 'GBP', _currency == 'GBP', () {
          setState(() => _currency = 'GBP');
        }),
      ],
    );
  }

  Widget _buildRadioOption(
      String label, String value, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.neonCyan.withAlpha(20)
              : AppTheme.cyberSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                selected ? AppTheme.neonCyan.withAlpha(180) : AppTheme.border,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppTheme.neonCyan : AppTheme.textMuted,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color:
                        selected ? AppTheme.neonCyan : AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    fontFamily: 'Cairo')),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerCard(CustomerModel c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('بيانات العميل',
            style: TextStyle(
                color: AppTheme.neonCyan,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo')),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.neonCyan.withAlpha(15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.neonCyan.withAlpha(50)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _customerInfoRow('الاسم', c.name),
              if (c.code.isNotEmpty) _customerInfoRow('الكود', c.code),
              if (c.phone.isNotEmpty) _customerInfoRow('الهاتف', c.phone),
              if (c.city.isNotEmpty) _customerInfoRow('المدينة', c.city),
              if (c.country.isNotEmpty) _customerInfoRow('الدولة', c.country),
              if (c.addresses.isNotEmpty) ...[
                const Divider(height: 16, color: AppTheme.glassBorder),
                const Text('العناوين',
                    style: TextStyle(
                        color: AppTheme.neonCyan,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo')),
                const SizedBox(height: 4),
                ...c.addresses.map((a) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                          '• ${a['full_address'] ?? a['address_line_1'] ?? a['address'] ?? ''}',
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
        if (c.addresses.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('اختيار عنوان الشحن',
              style: TextStyle(
                  color: AppTheme.neonCyan,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo')),
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
                        _selectedAddressIndex! < c.addresses.length
                    ? _selectedAddressIndex.toString()
                    : null,
                hint: const Text('اختر عنوان الشحن',
                    style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 13,
                        fontFamily: 'Cairo')),
                dropdownColor: AppTheme.cyberSurface,
                items: List.generate(c.addresses.length, (i) {
                  final addr = c.addresses[i];
                  final addrText =
                      addr['address'] ?? addr['name'] ?? 'عنوان ${i + 1}';
                  return DropdownMenuItem(
                    value: i.toString(),
                    child: Text(addrText,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontFamily: 'Cairo')),
                  );
                }),
                onChanged: (val) {
                  if (val != null) {
                    final idx = int.tryParse(val) ?? 0;
                    setState(() {
                      _selectedAddressIndex = idx;
                      _destinationAddressCtrl.text = c.addresses[idx]
                              ['full_address'] ??
                          c.addresses[idx]['address'] ??
                          '';
                    });
                  }
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _customerInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$label: ',
            style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontFamily: 'Cairo')),
        Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: Colors.white, fontSize: 11, fontFamily: 'Cairo'))),
      ]),
    );
  }

  Widget _buildClearingAgentCard(ClearingAgentModel a) {
    if (a.id == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.neonCyan.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.neonCyan.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.support_agent, size: 14, color: AppTheme.neonCyan),
            const SizedBox(width: 6),
            Expanded(
              child: Text('${a.code} - ${a.name}',
                  style: const TextStyle(
                      color: AppTheme.neonCyan,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo')),
            ),
          ]),
          if (a.phone.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.phone, size: 12, color: AppTheme.textSecondary),
              const SizedBox(width: 6),
              Text(a.phone,
                  style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                      fontFamily: 'Cairo')),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _buildBankInfo(BankDetails bank) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.neonCyan.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.neonCyan.withAlpha(50)),
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

  static const _colName = 180.0;
  static const _colQty = 80.0;
  static const _colPallet = 80.0;
  static const _colNetWt = 90.0;
  static const _colGrossWt = 90.0;
  static const _colPrice = 100.0;
  static const _colTotal = 110.0;
  static const _colDel = 32.0;
  static const _colGap = 4.0;

  double _tableWidth() {
    var cols = _colName + _colQty + _colNetWt + _colGrossWt + _colPrice + _colTotal + _colDel + _colGap * 6;
    if (_transportMode == 'sea') cols += _colPallet + _colGap;
    return cols + 24;
  }

  Widget _buildItemsTable() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cyberSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: _tableWidth(),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.neonCyan.withAlpha(10),
                  ),
                  child: Row(
                    children: [
                      _tableHeader('الصنف', _colName),
                      _tableHeader('الكراتين', _colQty),
                      if (_transportMode == 'sea') _tableHeader('البالتات', _colPallet),
                      _tableHeader('الوزن الصافي', _colNetWt),
                      _tableHeader('الوزن الإجمالي', _colGrossWt),
                      _tableHeader('سعر الكرتونة', _colPrice),
                      _tableHeader('الإجمالي', _colTotal),
                      SizedBox(width: _colDel),
                    ],
                  ),
                ),
                ..._items.asMap().entries.map((e) => _buildItemRow(e.key, e.value)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tableHeader(String text, double width) {
    return SizedBox(
      width: width,
      child: Text(text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: AppTheme.neonCyan,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo')),
    );
  }

  Widget _buildItemRow(int index, _ProformaItem item) {
    final qty = double.tryParse(item.qtyCtrl.text) ?? 0;
    final price = double.tryParse(item.priceCtrl.text) ?? 0;
    final total = qty * price;
    final isSea = _transportMode == 'sea';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: AppTheme.glassBorder.withAlpha(100))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _colName,
            child: AppTextField(
              controller: item.nameCtrl,
              label: 'اسم الصنف',
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(width: _colGap),
          SizedBox(
            width: _colQty,
            child: AppTextField(
              controller: item.qtyCtrl,
              label: '0',
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (isSea) ...[
            SizedBox(width: _colGap),
            SizedBox(
              width: _colPallet,
              child: AppTextField(
                controller: item.palletsCtrl,
                label: '0',
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
          SizedBox(width: _colGap),
          SizedBox(
            width: _colNetWt,
            child: AppTextField(
              controller: item.netWtCtrl,
              label: '0',
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(width: _colGap),
          SizedBox(
            width: _colGrossWt,
            child: AppTextField(
              controller: item.grossWtCtrl,
              label: '0',
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(width: _colGap),
          SizedBox(
            width: _colPrice,
            child: AppTextField(
              controller: item.priceCtrl,
              label: '0',
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(width: _colGap),
          SizedBox(
            width: _colTotal,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: Text(
                '${_currencySymbol()} ${total.toStringAsFixed(2)}',
                textAlign: TextAlign.center,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Cairo'),
              ),
            ),
          ),
          SizedBox(
            width: _colDel,
            child: _items.length > 1
                ? GestureDetector(
                    onTap: () {
                      setState(() => _items.removeAt(index));
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        item.dispose();
                      });
                    },
                    child: Icon(Icons.delete_outline,
                        color: AppTheme.danger, size: 18),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildAddItemButton() {
    return GestureDetector(
      onTap: () => setState(() => _items.add(_ProformaItem())),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.neonCyan.withAlpha(15),
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: AppTheme.neonCyan.withAlpha(60), width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, color: AppTheme.neonCyan, size: 20),
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
    );
  }

  Widget _buildTotalsSummary() {
    int totalItems = _items.length;
    int totalCartons = 0;
    double totalNet = 0;
    double totalGross = 0;
    double totalValue = 0;
    int totalPallets = 0;
    final isSea = _transportMode == 'sea';

    for (final item in _items) {
      final qty = double.tryParse(item.qtyCtrl.text) ?? 0;
      final price = double.tryParse(item.priceCtrl.text) ?? 0;
      final netWt = double.tryParse(item.netWtCtrl.text) ?? 0;
      final grossWt = double.tryParse(item.grossWtCtrl.text) ?? 0;
      final pallets = int.tryParse(item.palletsCtrl.text) ?? 0;
      totalCartons += qty.toInt();
      totalNet += netWt;
      totalGross += grossWt;
      totalValue += qty * price;
      totalPallets += pallets;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calculate_outlined, color: AppTheme.primary, size: 16),
              const SizedBox(width: 6),
              Text('ملخص الفاتورة ككل',
                  style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Cairo')),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _totalItem('الأصناف:', '$totalItems'),
              _totalItem('عدد الكراتين:', '$totalCartons'),
              if (isSea) _totalItem('عدد الباليتات:', '$totalPallets'),
              _totalItem('الوزن الصافي:', '${totalNet.toStringAsFixed(1)} كجم'),
              _totalItem(
                  'الوزن الإجمالي:', '${totalGross.toStringAsFixed(1)} كجم'),
              _totalItem('إجمالي التصدير:',
                  '${_currencySymbol()} ${totalValue.toStringAsFixed(2)}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _totalItem(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontFamily: 'Cairo')),
        const SizedBox(width: 4),
        Text(value,
            style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                fontFamily: 'Cairo')),
      ],
    );
  }

  Widget _buildTermsSection() {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cyberSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(bottom: 8),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.glassBorder)),
              ),
              child: const Text('TERMS OF SALE AND OTHER COMMENTS',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(bottom: 6),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.glassBorder)),
              ),
              child: const Text('TERMS AND CONDITIONS',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
            ),
            const SizedBox(height: 6),
            const Text('Fruity Farms',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
            const SizedBox(height: 12),
            _termsField('Port Of Loading', _portOfLoadingCtrl),
            const SizedBox(height: 10),
            _termsField('Port Of Destination', _portOfDestCtrl),
            const SizedBox(height: 10),
            _termsField('Terms Of Payment', _paymentTermsCtrl),
            const SizedBox(height: 10),
            _termsField(
                'Mode Of Transport',
                TextEditingController(
                    text: _transportMode == 'sea' ? 'By Sea' : 'By Air')),
            const SizedBox(height: 12),
            const Text(
                'All Banking Charges Out Of Egypt Including Remitting Charges Are On Applicants Account',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
            const SizedBox(height: 6),
            const Text(
                'I Certify The Above To Be True And Correct To The Best Of My Knowledge',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _termsField(String label, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 12)),
        const SizedBox(height: 2),
        TextField(
          controller: ctrl,
          textAlign: TextAlign.left,
          style: const TextStyle(
              color: AppTheme.textPrimary, fontSize: 13, fontFamily: 'Cairo'),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 0, vertical: 6),
            filled: false,
            border: UnderlineInputBorder(
                borderSide: BorderSide(color: AppTheme.glassBorder)),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppTheme.glassBorder)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppTheme.primary, width: 1.5)),
          ),
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton.icon(
      onPressed: _isSaving ? null : _save,
      icon: _isSaving
          ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(
                  color: AppTheme.primary, strokeWidth: 2))
          : const Icon(Icons.save_outlined, size: 16),
      label: Text(_isSaving ? 'جاري...' : 'حفظ',
          style: const TextStyle(
              color: AppTheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo')),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildWordButton() {
    return ElevatedButton.icon(
      onPressed: _isSaving ? null : _exportToWord,
      icon: const Icon(Icons.description_outlined, size: 16, color: Colors.white),
      label: const Text('تصدير Word',
          style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              fontFamily: 'Cairo')),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String _currencySymbol() {
    switch (_currency) {
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      default:
        return 'ج.م';
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCustomerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('اختر العميل'), backgroundColor: AppTheme.warning),
      );
      return;
    }

    setState(() => _isSaving = true);

    double totalAmount = 0;
    final items = <_ProformaItem>[];
    for (final item in _items) {
      if (item.nameCtrl.text.isEmpty) continue;
      final qty = double.tryParse(item.qtyCtrl.text) ?? 0;
      final price = double.tryParse(item.priceCtrl.text) ?? 0;
      totalAmount += qty * price;
      items.add(item);
    }

    if (items.isEmpty) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('أضف صنف واحد على الأقل'),
            backgroundColor: AppTheme.danger),
      );
      return;
    }

    final invoice = ProformaInvoiceModel(
      id: widget.invoice?.id,
      invoiceNo: _invoiceNo,
      customerId: _selectedCustomerId,
      customerName: _customerDisplayText,
      customerCode: _customerCode,
      clearingAgentId: _selectedClearingAgentId,
      clearingAgentName: _selectedClearingAgentName,
      contactPerson: _contactPersonCtrl.text,
      country: _countryCtrl.text,
      destinationAddress: _destinationAddressCtrl.text,
      containerNo: _containerNoCtrl.text,
      vesselName: _vesselNameCtrl.text,
      blNumber: _blNoCtrl.text,
      dataLoggerNo: _dataLoggerCtrl.text,
      portOfLoading: _portOfLoadingCtrl.text,
      portOfDestination: _portOfDestCtrl.text,
      transportMode: _transportMode,
      currency: _currency,
      paymentTerms: _paymentTermsCtrl.text,
      totalAmount: totalAmount,
      invoiceDate: _invoiceDate,
    );

    final itemModels = items.map((item) {
      final qty = double.tryParse(item.qtyCtrl.text) ?? 0;
      final price = double.tryParse(item.priceCtrl.text) ?? 0;
      return ProformaInvoiceItem(
        productName: item.nameCtrl.text,
        quantity: qty,
        pricePerCarton: price,
        netWeight: double.tryParse(item.netWtCtrl.text) ?? 0,
        grossWeight: double.tryParse(item.grossWtCtrl.text) ?? 0,
        palletsCount: int.tryParse(item.palletsCtrl.text) ?? 0,
      );
    }).toList();

    context.read<ProformaInvoiceCubit>().save(invoice, items: itemModels);
  }

  Future<void> _exportToWord() async {
    if (_selectedCustomerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر العميل أولاً'), backgroundColor: AppTheme.warning),
      );
      return;
    }

    double totalAmount = 0;
    final items = <_ProformaItem>[];
    for (final item in _items) {
      if (item.nameCtrl.text.isEmpty) continue;
      final qty = double.tryParse(item.qtyCtrl.text) ?? 0;
      final price = double.tryParse(item.priceCtrl.text) ?? 0;
      totalAmount += qty * price;
      items.add(item);
    }

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف صنف واحد على الأقل'), backgroundColor: AppTheme.danger),
      );
      return;
    }

    final invoice = ProformaInvoiceModel(
      id: widget.invoice?.id,
      invoiceNo: _invoiceNo,
      customerId: _selectedCustomerId,
      customerName: _customerDisplayText,
      customerCode: _customerCode,
      clearingAgentId: _selectedClearingAgentId,
      clearingAgentName: _selectedClearingAgentName,
      contactPerson: _contactPersonCtrl.text,
      country: _countryCtrl.text,
      destinationAddress: _destinationAddressCtrl.text,
      containerNo: _containerNoCtrl.text,
      vesselName: _vesselNameCtrl.text,
      blNumber: _blNoCtrl.text,
      dataLoggerNo: _dataLoggerCtrl.text,
      portOfLoading: _portOfLoadingCtrl.text,
      portOfDestination: _portOfDestCtrl.text,
      transportMode: _transportMode,
      currency: _currency,
      paymentTerms: _paymentTermsCtrl.text,
      totalAmount: totalAmount,
      invoiceDate: _invoiceDate,
    );

    final itemModels = items.map((item) {
      final qty = double.tryParse(item.qtyCtrl.text) ?? 0;
      final price = double.tryParse(item.priceCtrl.text) ?? 0;
      return ProformaInvoiceItem(
        productName: item.nameCtrl.text,
        quantity: qty,
        pricePerCarton: price,
        netWeight: double.tryParse(item.netWtCtrl.text) ?? 0,
        grossWeight: double.tryParse(item.grossWtCtrl.text) ?? 0,
        palletsCount: int.tryParse(item.palletsCtrl.text) ?? 0,
      );
    }).toList();

    CustomerModel? customer = _selectedCustomer;

    ClearingAgentModel? agent;
    final st = context.read<ProformaInvoiceCubit>().state;
    final agents = st is ProformaInvoiceFormLoaded ? st.clearingAgents : <ClearingAgentModel>[];
    try {
      if (_selectedClearingAgentId != null) {
        agent = agents.firstWhere((a) => a.id == _selectedClearingAgentId);
      }
    } catch (_) {}

    await ProformaInvoiceWordService.exportWord(
      context: context, 
      invoice: invoice, 
      items: itemModels,
      customer: customer,
      clearingAgent: agent,
    );
  }
}

class _ProformaItem {
  final nameCtrl = TextEditingController();
  final qtyCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  final netWtCtrl = TextEditingController();
  final grossWtCtrl = TextEditingController();
  final palletsCtrl = TextEditingController();

  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
    priceCtrl.dispose();
    netWtCtrl.dispose();
    grossWtCtrl.dispose();
    palletsCtrl.dispose();
  }
}
