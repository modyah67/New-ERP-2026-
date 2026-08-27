import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../../core/theme.dart';
import '../../core/ui_utils.dart';
import '../../core/auth_state_notifier.dart';
import '../../features/auth/auth_cubit.dart';
import '../../data/dao/export_shipment_dao.dart';
import '../../data/dao/shipment_cost_item_dao.dart';
import '../../data/dao/packing_order_dao.dart';
import '../../data/dao/lot_dao.dart';
import '../../data/dao/export_shipment_item_dao.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/models/supplier_model.dart';
import '../../data/services/cost_allocation_service.dart';
import '../../data/services/shipment_breakdown_service.dart';
import '../../data/models/export_shipment_model.dart';
import '../../data/models/shipment_cost_item_model.dart';
import '../../data/models/packing_order_model.dart';
import '../../data/models/shipping_company_model.dart';
import '../../data/dao/shipping_company_dao.dart';
import '../../data/models/clearing_agent_model.dart';
import '../../data/dao/clearing_agent_dao.dart';
import '../../data/services/currency_conversion_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'shipment_cost_pdf_service.dart';

class ShipmentCostingPage extends StatefulWidget {
  final int shipmentId;
  const ShipmentCostingPage({super.key, required this.shipmentId});

  @override
  State<ShipmentCostingPage> createState() => _ShipmentCostingPageState();
}

class _ShipmentCostingPageState extends State<ShipmentCostingPage> {
  final _shipmentDao = ExportShipmentDao();
  final _costItemDao = ShipmentCostItemDao();
  final _packingOrderDao = PackingOrderDao();
  final _exportItemDao = ExportShipmentItemDao();
  final _lotDao = LotDao();
  final _costService = CostAllocationService();
  final _breakdownService = ShipmentBreakdownService();
  final _exportPriceCtrl = TextEditingController();
  final _exchangeRateCtrl = TextEditingController();
  final _adminExpensesCtrl = TextEditingController(text: '0.00');
  final _taxesCtrl = TextEditingController(text: '0.00');

  ExportShipmentModel? _shipment;
  bool _isDistributed = false;
  List<ShipmentCostItemModel> _items = [];
  List<Map<String, dynamic>> _categoriesList = [];

  int? get _shippingCatId => _categoriesList.firstWhere(
        (c) => (c['name'] as String) == 'تكلفة شركات الشحن' ||
               (c['name'] as String) == 'تكاليف الشحن والتخليص' ||
               (c['name'] as String).contains('شحن'),
        orElse: () => <String, dynamic>{},
      )['id'] as int?;

  int? get _clearanceCatId => _categoriesList.firstWhere(
        (c) => (c['name'] as String) == 'تكلفة المخلصين' ||
               (c['name'] as String) == 'تكاليف التخليص' ||
               (c['name'] as String).contains('تخليص') ||
               (c['name'] as String).contains('مخلص'),
        orElse: () => <String, dynamic>{},
      )['id'] as int?;

  int? get _cropCatId => _categoriesList.firstWhere(
        (c) => (c['name'] as String) == 'تكلفة المحاصيل' ||
               (c['name'] as String).contains('محصول') ||
               (c['name'] as String).contains('محاصيل'),
        orElse: () => <String, dynamic>{},
      )['id'] as int?;

  int? get _packingCatId => _categoriesList.firstWhere(
        (c) => (c['name'] as String) == 'تعبئة وتغليف' ||
               (c['name'] as String).contains('تعبئة'),
        orElse: () => <String, dynamic>{},
      )['id'] as int?;

  List<Map<String, dynamic>> _treasuries = [];
  List<Map<String, dynamic>> _bankAccounts = [];
  String _currency = 'USD';
  bool _loading = true;
  bool _saving = false;
  double _liveTotalRevenueForeign = 0.0;
  double _packingCostPerCartonFromOrders = 0.0;

  bool get _isCostingReadOnly {
    final authState = authNotifier.value;
    if (authState is AuthAuthenticated) {
      if (authState.isAdmin) return false;
      return authState.allowedPages.contains('/exports/costing-readonly');
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _exportPriceCtrl.dispose();
    _exchangeRateCtrl.dispose();
    _adminExpensesCtrl.dispose();
    _taxesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final client = Supabase.instance.client;
      final results = await Future.wait([
        _shipmentDao.getById(widget.shipmentId),
        _costItemDao.getForShipment(widget.shipmentId),
        _packingOrderDao.getByShipmentIdViaItems(widget.shipmentId),
        _exportItemDao.getByShipmentId(widget.shipmentId),
        client.rpc('list_cost_report_categories',
            params: {'p_scope': 'shipment'}),
        client
            .from('treasuries')
            .select('id, name, treasury_balances(balance, currency)')
            .order('name'),
        client
            .from('bank_accounts')
            .select('id, name, currency, balance')
            .order('name'),
        _shipmentDao.isShipmentProfitDistributed(widget.shipmentId),
      ]);
      final s = results[0] as ExportShipmentModel?;
      var items = results[1] as List<ShipmentCostItemModel>;
      final packingOrders = results[2] as List<PackingOrderModel>;
      final shipmentItems = results[3] as List<Map<String, dynamic>>;
      final cats = (results[4] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .where((c) => c['name'] != 'مصاريف إدارية')
          .toList();
      _treasuries = List<Map<String, dynamic>>.from(results[5] as List);
      _bankAccounts = List<Map<String, dynamic>>.from(results[6] as List);
      final isDistributed = results[7] as bool;

      double liveRevenue = 0.0;
      for (final item in shipmentItems) {
        final qty = int.tryParse(item['quantity']?.toString() ?? '0') ?? 0;
        final ep = double.tryParse(
                item['export_price_per_carton']?.toString() ?? '0') ??
            0;
        liveRevenue += qty * ep;
      }
      _liveTotalRevenueForeign = liveRevenue;

      if (s != null) {
        _exportPriceCtrl.text = s.exportPricePerCarton.toString();
        _exchangeRateCtrl.text = s.exchangeRate.toString();
        _adminExpensesCtrl.text = s.allocatedAdminExpenses.toStringAsFixed(2);
        _taxesCtrl.text = s.allocatedTaxes.toStringAsFixed(2);
        _currency = s.currency ?? s.currencyCode;
      }
      _isDistributed = isDistributed;

      int? cartonCostCatId;
      try {
        final cat = cats.firstWhere(
            (c) => c['name'] == 'تكلفة الكراتين' || c['name'] == 'تكلفة كراتين',
            orElse: () => <String, dynamic>{});
        if (cat.isNotEmpty) cartonCostCatId = cat['id'];
      } catch (_) {}

      items.removeWhere((i) => i.description == 'تكلفة كراتين الشحنة' || i.description.contains('أمر تعبئة رقم'));

      double totalCartonCost = 0.0;
      double totalCartonQty = 0.0;

      if (shipmentItems.isNotEmpty) {
        for (final item in shipmentItems) {
          final prodName = (item['product_name']?.toString() ?? item['invoice_product_name']?.toString() ?? 'صنف').trim();
          final poId = item['packing_order_id']?.toString();
          final qty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
          final unitCost = (item['price'] as num?)?.toDouble() ?? 0.0;
          final itemTotal = qty * unitCost;

          totalCartonCost += itemTotal;
          totalCartonQty += qty;

          final desc = poId != null && poId.isNotEmpty
              ? '$prodName - أمر تعبئة رقم: $poId'
              : prodName;

          items.add(ShipmentCostItemModel(
            shipmentId: widget.shipmentId,
            reportCategoryId: cartonCostCatId,
            reportCategoryName: 'تكلفة الكراتين',
            category: 'packing',
            description: desc,
            quantity: qty,
            unitPrice: unitCost,
            totalPrice: itemTotal,
            isReadOnly: true,
          ));
        }
        _packingCostPerCartonFromOrders = totalCartonQty > 0 ? totalCartonCost / totalCartonQty : 0.0;
      } else if (s != null && s.cartonsCount > 0) {
        double avgPackingCost = 0.0;
        if (packingOrders.isNotEmpty) {
          double totalPoCost = 0.0;
          int totalPoCartons = 0;
          for (final po in packingOrders) {
            totalPoCost += po.packingCostPerCarton * po.cartonCount;
            totalPoCartons += po.cartonCount;
          }
          avgPackingCost = totalPoCartons > 0 ? totalPoCost / totalPoCartons : packingOrders.first.packingCostPerCarton;
        }
        _packingCostPerCartonFromOrders = avgPackingCost;

        if (avgPackingCost > 0) {
          String poDesc = 'تكلفة الكراتين';
          if (packingOrders.isNotEmpty) {
             poDesc = packingOrders.map((po) => '${po.productName ?? 'محصول'} - أمر تعبئة رقم: ${po.orderNumber}').join(' ، ');
          }
          items.add(ShipmentCostItemModel(
            shipmentId: widget.shipmentId,
            reportCategoryId: cartonCostCatId,
            reportCategoryName: 'تكلفة الكراتين',
            category: 'packing',
            description: poDesc,
            quantity: s.cartonsCount.toDouble(),
            unitPrice: avgPackingCost,
            totalPrice: avgPackingCost * s.cartonsCount,
            isReadOnly: true,
          ));
        }
      }


      if (mounted) {
        setState(() {
          _shipment = s;
          _items = items;
          _categoriesList = cats;
          _liveTotalRevenueForeign = liveRevenue;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _num(TextEditingController c) => double.tryParse(c.text) ?? 0;

  double get _allocatedAdminExpenses => _num(_adminExpensesCtrl);
  double get _allocatedTaxes => _num(_taxesCtrl);
  int get _cartonCount => _shipment?.cartonsCount ?? 0;
  double get _totalCost => _items.fold(0.0, (s, i) => s + i.totalPrice) + ((_shipment?.discountAmount ?? 0.0) * _num(_exchangeRateCtrl)) + _allocatedAdminExpenses + _allocatedTaxes;
  double get _totalRevenueForeign => _liveTotalRevenueForeign;
  double get _totalRevenueEgp => _totalRevenueForeign * _num(_exchangeRateCtrl);
  double get _costEgp => _totalCost;
  double get _cropCost => _items
      .where((i) => i.reportCategoryId == _cropCatId)
      .fold(0.0, (s, i) => s + i.totalPrice);
  double get _packingCostPerCarton => _packingCostPerCartonFromOrders;
  double get _packingCost => _packingCostPerCarton * _cartonCount;
  double get _discountEgp => (_shipment?.discountAmount ?? 0.0) * _num(_exchangeRateCtrl);
  double get _netProfitEgp => _totalRevenueEgp - _discountEgp - _costEgp;
  double get _netProfitUsd => _num(_exchangeRateCtrl) > 0 ? _netProfitEgp / _num(_exchangeRateCtrl) : 0.0;
  double get _profitMargin {
    final revAfterDiscount = _totalRevenueEgp - _discountEgp;
    return revAfterDiscount > 0 ? (_netProfitEgp / revAfterDiscount * 100) : 0;
  }

  double get _costPerCarton {
    if (_cartonCount == 0) return 0;
    final rate = _num(_exchangeRateCtrl) > 0 ? _num(_exchangeRateCtrl) : 1.0;
    return _costPerCartonEgp / rate;
  }

  double get _grossPerCarton => _cartonCount == 0
      ? 0
      : (_totalRevenueForeign / _cartonCount) - _costPerCarton;

  double get _costPerCartonEgp => _packingCostPerCartonFromOrders;
  double get _revenuePerCartonEgp =>
      _cartonCount == 0 ? 0 : _totalRevenueEgp / _cartonCount;
  double get _grossPerCartonEgp => _revenuePerCartonEgp - _costPerCartonEgp;

  Future<void> _save() async {
    if (_isDistributed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم توزيع أرباح هذه الشحنة على المساهمين - تم قفل تعديل التكاليف والمصروفات',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final savedItems = await _costItemDao.saveAll(widget.shipmentId, _items);

      // Auto-pay items that have a payment source specified and are not paid yet
      for (final savedItem in savedItems) {
        if (!savedItem.isPaid &&
            savedItem.paymentSourceType != null &&
            savedItem.paymentSourceType != 'none' &&
            savedItem.paymentSourceId != null &&
            savedItem.id != null) {
          try {
            await _costItemDao.payItem(
              costItemId: savedItem.id!,
              sourceType: savedItem.paymentSourceType!,
              sourceId: savedItem.paymentSourceId!,
            );
          } catch (e) {
            debugPrint('Error auto-paying item ${savedItem.id}: $e');
          }
        }
      }
      await _costItemDao.updateVendorBalances();
      await _costItemDao.upsertSupplierLedgerEntries(savedItems);
      final packingCostSum = _items
          .where((i) =>
              i.reportCategoryId == _packingCatId ||
              i.reportCategoryId == 1)
          .fold<double>(0.0, (s, i) => s + i.totalPrice);
      final nonPackingCost = _totalCost - packingCostSum;
      await _shipmentDao.updateCosting(
        shipmentId: widget.shipmentId,
        totalLandedCost: _totalCost,
        cartonCount: _cartonCount,
        exportPricePerCarton: _num(_exportPriceCtrl),
        currencyCode: _currency,
        exchangeRate: _num(_exchangeRateCtrl),
        nonPackingLandedCost: nonPackingCost,
      );

      // Save Allocated Admin Expenses & generate GL
      await _shipmentDao.saveAllocatedAdminExpenses(
        shipmentId: widget.shipmentId,
        allocatedAdminExpenses: _allocatedAdminExpenses,
      );

      // Save Allocated Taxes & generate GL
      await _shipmentDao.saveAllocatedTaxes(
        shipmentId: widget.shipmentId,
        allocatedTaxes: _allocatedTaxes,
      );

      await _costService.accumulateShipmentCosts(widget.shipmentId.toString());
      await _breakdownService.generateBreakdown(widget.shipmentId.toString());
      
      // Update the ledger with the newly calculated costs
      await _shipmentDao.syncLedger(widget.shipmentId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تم حفظ التكاليف'),
              backgroundColor: AppTheme.success),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _addItem({int? targetCategoryId, String? targetCategoryName, String? initialVendorType}) {
    final descCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController();
    final exchangeCtrl = TextEditingController(text: '1.0');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddItemSheet(
        targetCategoryId: targetCategoryId,
        targetCategoryName: targetCategoryName,
        initialVendorType: initialVendorType,
        shipment: _shipment,
        treasuries: _treasuries,
        bankAccounts: _bankAccounts,
        descCtrl: descCtrl,
        qtyCtrl: qtyCtrl,
        priceCtrl: priceCtrl,
        exchangeCtrl: exchangeCtrl,
        onConfirm: (selectedCategoryId, vendorType, vendorId, supplierId,
            supplierCurrency, paymentSourceType, paymentSourceId, expenseAccountId) {
          final qty = double.tryParse(qtyCtrl.text) ?? 0;
          final price = double.tryParse(priceCtrl.text) ?? 0;
          final rate = double.tryParse(exchangeCtrl.text) ?? 1.0;
          final catName = _categoriesList.firstWhere(
                  (c) => c['id'] == selectedCategoryId,
                  orElse: () => {})['name'] as String? ??
              '';
          var desc = descCtrl.text.trim();
          if (desc.isEmpty) {
            if (selectedCategoryId == _shippingCatId) {
              desc = 'شحن';
            } else if (selectedCategoryId == _clearanceCatId) {
              desc = 'تخليص جمركي';
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('يرجى إدخال البيان',
                      style: TextStyle(fontFamily: 'Cairo'))));
              return;
            }
          }
          if ((selectedCategoryId == _shippingCatId || selectedCategoryId == _clearanceCatId || vendorType == 'shipping_company' || vendorType == 'clearing_agent') &&
              vendorId == null) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('يرجى اختيار المورد/الشركة',
                    style: TextStyle(fontFamily: 'Cairo'))));
            return;
          }
          if (qty <= 0) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('يرجى إدخال كمية أكبر من صفر',
                    style: TextStyle(fontFamily: 'Cairo'))));
            return;
          }

          setState(() {
            _items.add(ShipmentCostItemModel(
              shipmentId: widget.shipmentId,
              reportCategoryId: selectedCategoryId,
              reportCategoryName: catName,
              category: (vendorType == 'shipping_company' || selectedCategoryId == _shippingCatId)
                  ? 'freight'
                  : ((vendorType == 'clearing_agent' || selectedCategoryId == _clearanceCatId) ? 'clearance' : 'other'),
              description: desc,
              quantity: qty,
              unitPrice: price,
              totalPrice: qty * price,
              isReadOnly: false,
              vendorType: vendorType,
              vendorId: vendorId ?? int.tryParse(supplierId ?? ''),
              exchangeRate: rate,
              supplierId: supplierId,
              supplierCurrency: supplierCurrency,
              paymentSourceType: paymentSourceType,
              paymentSourceId: paymentSourceId,
              expenseAccountId: expenseAccountId,
              shippingCompanyId: vendorType == 'shipping_company' ? vendorId : null,
              clearingAgentId: vendorType == 'clearing_agent' ? vendorId : null,
            ));
          });
          Navigator.pop(ctx);
        },
      ),
    );
  }

  void _editItem(int index) {
    final item = _items[index];
    final descCtrl = TextEditingController(text: item.description);
    final qtyCtrl = TextEditingController(text: item.quantity.toString());
    final priceCtrl = TextEditingController(text: item.unitPrice.toString());
    final exchangeCtrl =
        TextEditingController(text: item.exchangeRate.toStringAsFixed(2));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddItemSheet(
        targetCategoryId: item.reportCategoryId,
        shipment: _shipment,
        treasuries: _treasuries,
        bankAccounts: _bankAccounts,
        initialVendorId: item.vendorId,
        initialVendorType: item.vendorType,
        initialPaymentSourceType: item.paymentSourceType,
        initialPaymentSourceId: item.paymentSourceId,
        descCtrl: descCtrl,
        qtyCtrl: qtyCtrl,
        priceCtrl: priceCtrl,
        exchangeCtrl: exchangeCtrl,
        initialSupplierId: item.supplierId,
        initialExpenseAccountId: item.expenseAccountId,
        onConfirm: (selectedCategoryId, vendorType, vendorId, supplierId,
            supplierCurrency, paymentSourceType, paymentSourceId, expenseAccountId) {
          final qty = double.tryParse(qtyCtrl.text) ?? 0;
          final price = double.tryParse(priceCtrl.text) ?? 0;
          final rate = double.tryParse(exchangeCtrl.text) ?? 1.0;
          final catName = _categoriesList.firstWhere(
                  (c) => c['id'] == selectedCategoryId,
                  orElse: () => {})['name'] as String? ??
              '';
          var desc = descCtrl.text.trim();
          if (desc.isEmpty) {
            if (selectedCategoryId == _shippingCatId || vendorType == 'shipping_company') {
              desc = 'شحن';
            } else if (selectedCategoryId == _clearanceCatId || vendorType == 'clearing_agent') {
              desc = 'تخليص جمركي';
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('يرجى إدخال البيان',
                      style: TextStyle(fontFamily: 'Cairo'))));
              return;
            }
          }
          if ((selectedCategoryId == _shippingCatId || selectedCategoryId == _clearanceCatId || vendorType == 'shipping_company' || vendorType == 'clearing_agent') &&
              vendorId == null) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('يرجى اختيار المورد/الشركة',
                    style: TextStyle(fontFamily: 'Cairo'))));
            return;
          }
          if (qty <= 0) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('يرجى إدخال كمية أكبر من صفر',
                    style: TextStyle(fontFamily: 'Cairo'))));
            return;
          }

          setState(() {
            _items[index] = ShipmentCostItemModel(
              id: item.id,
              shipmentId: widget.shipmentId,
              reportCategoryId: selectedCategoryId,
              reportCategoryName: catName,
              category: (vendorType == 'shipping_company' || selectedCategoryId == _shippingCatId)
                  ? 'freight'
                  : ((vendorType == 'clearing_agent' || selectedCategoryId == _clearanceCatId) ? 'clearance' : 'other'),
              description: desc,
              quantity: qty,
              unitPrice: price,
              totalPrice: qty * price,
              isReadOnly: item.isReadOnly,
              vendorType: vendorType,
              vendorId: vendorId ?? int.tryParse(supplierId ?? ''),
              exchangeRate: rate,
              supplierId: supplierId,
              supplierCurrency: supplierCurrency,
              paymentSourceType: paymentSourceType,
              paymentSourceId: paymentSourceId,
              expenseAccountId: expenseAccountId,
              shippingCompanyId: vendorType == 'shipping_company' ? vendorId : null,
              clearingAgentId: vendorType == 'clearing_agent' ? vendorId : null,
              treasuryTransactionId: item.treasuryTransactionId,
              bankTransactionId: item.bankTransactionId,
            );
          });
          Navigator.pop(ctx);
        },
      ),
    );
  }

  void _removeItem(int index) {
    final item = _items[index];
    if (item.isPaid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يمكن حذف بند تم سداده مسبقاً',
              style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }
    setState(() => _items.removeAt(index));
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
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary))
              : _shipment == null
                  ? const Center(
                      child: Text('لم يتم العثور على الشحنة',
                          style: TextStyle(color: AppTheme.textSecondary)))
                  : _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final readOnly = _isCostingReadOnly || _isDistributed;
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_isDistributed) _buildDistributionLockBanner(),
                _buildInfoCard(),
                const SizedBox(height: 16),
                _buildCostItemsSection(),
                const SizedBox(height: 16),
                _buildTotalCostCard(),
                if (!readOnly) ...[
                  const SizedBox(height: 16),
                  _buildPriceSection(),
                ],
                const SizedBox(height: 16),
                _buildProfitPreview(),
                const SizedBox(height: 16),
                _buildSaveButton(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDistributionLockBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.danger.withAlpha(35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.danger.withAlpha(120), width: 1.5),
      ),
      child: const Row(
        children: [
          Icon(Icons.lock, color: AppTheme.danger, size: 24),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'تم توزيع أرباح هذه الشحنة على المساهمين - القراءة فقط',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    fontFamily: 'Cairo',
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'تم قفل تعديل التكاليف والمصروفات الإدارية لمنع تباين الأرباح الموزعة وقيود الحسابات.',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontFamily: 'Cairo',
                  ),
                ),
              ],
            ),
          ),
        ],
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
              left: 12,
              right: 12),
          decoration: BoxDecoration(
            color: const Color(0x3805192D),
            border: Border(
                bottom: BorderSide(color: AppTheme.glassBorder.withAlpha(50))),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 500;
              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withAlpha(20),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppTheme.primary.withAlpha(60)),
                          ),
                          child: const Icon(Icons.arrow_forward,
                              color: AppTheme.primary, size: 18),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                            color: AppTheme.warning.withAlpha(30),
                            borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.monetization_on_outlined,
                            color: AppTheme.warning, size: 18),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('تكلفة الشحنة',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo')),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: UIUtils.shipmentNoText(_shipment!.shipmentNo,
                            style: const TextStyle(
                                color: AppTheme.neonCyan,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo')),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _savePdf,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withAlpha(20),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppTheme.primary.withAlpha(50)),
                          ),
                          child: const Icon(Icons.download,
                              color: AppTheme.primary, size: 16),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: _printPdf,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withAlpha(20),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppTheme.success.withAlpha(50)),
                          ),
                          child: const Icon(Icons.print,
                              color: AppTheme.success, size: 16),
                        ),
                      ),
                    ]),
                  ],
                );
              }
              return Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: AppTheme.primary.withAlpha(60)),
                      ),
                      child: const Icon(Icons.arrow_forward,
                          color: AppTheme.primary, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: AppTheme.warning.withAlpha(30),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.monetization_on_outlined,
                        color: AppTheme.warning, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('تكلفة الشحنة — ${_shipment!.shipmentNo}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo')),
                  ),
                  GestureDetector(
                    onTap: _savePdf,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: AppTheme.primary.withAlpha(50)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.download,
                              color: AppTheme.primary, size: 18),
                          SizedBox(width: 6),
                          Text('حفظ PDF',
                              style: TextStyle(
                                  color: AppTheme.primary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo')),
                        ],
                      ),
                    ),
                  ),

                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _printPdf() async {
    if (!mounted) return;
    ShipmentCostPdfService.previewPdf(
      context: context,
      shipment: _shipment!,
      costItems: _items,
      revForeign: _totalRevenueForeign,
      revEgp: _totalRevenueEgp,
      //cropCostEgp: _cropCost,
      totalCostEgp: _costEgp,
      netProfitEgp: _netProfitEgp,
      margin: _profitMargin,
      revPerCartonForeign:
          _cartonCount == 0 ? 0 : (_totalRevenueForeign / _cartonCount),
      costPerCartonForeign: _costPerCarton,
      grossPerCartonForeign: _grossPerCarton,
      revPerCartonEgp: _revenuePerCartonEgp,
      costPerCartonEgp: _costPerCartonEgp,
      grossPerCartonEgp: _grossPerCartonEgp,
      currency: _currency,
      discount: (_shipment?.discountAmount ?? 0.0) * _num(_exchangeRateCtrl),
    );
  }

  void _savePdf() async {
    if (!mounted) return;
    ShipmentCostPdfService.savePdf(
      context: context,
      shipment: _shipment!,
      costItems: _items,
      revForeign: _totalRevenueForeign,
      revEgp: _totalRevenueEgp,
      //cropCostEgp: _cropCost,
      totalCostEgp: _costEgp,
      netProfitEgp: _netProfitEgp,
      margin: _profitMargin,
      revPerCartonForeign:
          _cartonCount == 0 ? 0 : (_totalRevenueForeign / _cartonCount),
      costPerCartonForeign: _costPerCarton,
      grossPerCartonForeign: _grossPerCarton,
      revPerCartonEgp: _revenuePerCartonEgp,
      costPerCartonEgp: _costPerCartonEgp,
      grossPerCartonEgp: _grossPerCartonEgp,
      currency: _currency,
      discount: (_shipment?.discountAmount ?? 0.0) * _num(_exchangeRateCtrl),
    );
  }

  Widget _buildInfoCard() {
    final s = _shipment!;
    return AppTheme.glassCardWidget(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 500;
          if (isNarrow) {
            return Wrap(spacing: 8, runSpacing: 8, children: [
              _infoItemNoExpand('العميل', s.customerName ?? '—',
                  (constraints.maxWidth - 8) / 2),
              _infoItemNoExpand('الكراتين', s.cartonsCount.toString(),
                  (constraints.maxWidth - 8) / 2),
              _infoItemNoExpand(
                  'الوجهة', s.country ?? '—', (constraints.maxWidth - 8) / 2),
              _infoItemNoExpand(
                  'التاريخ',
                  s.shipmentDate != null
                      ? '${s.shipmentDate!.day}/${s.shipmentDate!.month}/${s.shipmentDate!.year}'
                      : '—',
                  (constraints.maxWidth - 8) / 2),
            ]);
          }
          return Row(
            children: [
              _infoItem('العميل', s.customerName ?? '—'),
              _infoItem('الكراتين', s.cartonsCount.toString()),
              _infoItem('الوجهة', s.country ?? '—'),
              _infoItem(
                  'التاريخ',
                  s.shipmentDate != null
                      ? '${s.shipmentDate!.day}/${s.shipmentDate!.month}/${s.shipmentDate!.year}'
                      : '—'),
            ],
          );
        },
      ),
    );
  }

  Widget _infoItemNoExpand(String label, String value, double width) {
    return SizedBox(
      width: width,
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  fontFamily: 'Cairo')),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo'),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _infoItem(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  fontFamily: 'Cairo')),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo'),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Color _categoryColor(int cat) {
    if (cat == _shippingCatId && _shippingCatId != null) return Colors.orange;
    if (cat == _clearanceCatId && _clearanceCatId != null) return Colors.purple;
    if (cat == _cropCatId && _cropCatId != null) return const Color(0xFF84CC16);
    final colors = [
      const Color(0xFF3B82F6),
      const Color(0xFFF59E0B),
      const Color(0xFF8B5CF6),
      const Color(0xFFEF4444),
      const Color(0xFF06B6D4),
    ];
    return colors[cat % colors.length];
  }

  Widget _buildCostItemsSection() {
    return AppTheme.glassCardWidget(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.receipt_long_outlined,
                    color: AppTheme.primary, size: 16),
              ),
              const SizedBox(width: 8),
              const Text('بنود التكلفة',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo')),
            ],
          ),
          const SizedBox(height: 12),
          ...{..._items.map((i) => i.reportCategoryId ?? 17)}
              .toList()
              .map((catId) => _buildCategoryGroup(catId)),
          const SizedBox(height: 12),
          _buildAddItemRow(),
        ],
      ),
    );
  }

  Widget _buildCategoryGroup(int cat) {
    final catItems =
        _items.where((i) => (i.reportCategoryId ?? 17) == cat).toList();
    if (catItems.isEmpty) return const SizedBox.shrink();
    final color = _categoryColor(cat);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 6),
              Text(catItems.first.reportCategoryName ?? 'غير مصنف',
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo')),
            ],
          ),
        ),
        ...catItems.map(
            (item) => _buildCostItemRow(item, _items.indexOf(item), color)),
      ],
    );
  }

  Widget _buildCostItemRow(ShipmentCostItemModel item, int index, Color color) {
    final readOnly = _isCostingReadOnly || item.isReadOnly;
    final isPaid = item.isPaid;
    final paySource = item.paymentSourceType;

    return Container(
      width: MediaQuery.of(context).size.width < 500 ? null : double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isPaid ? AppTheme.success.withAlpha(10) : color.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color:
                isPaid ? AppTheme.success.withAlpha(60) : color.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(item.description,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo')),
              ),
              // Payment status badge
              if (isPaid)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withAlpha(25),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.success.withAlpha(80)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_outline,
                          color: AppTheme.success, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        paySource == 'treasury'
                            ? 'مدفوع (خزينة)'
                            : 'مدفوع (بنك)',
                        style: const TextStyle(
                            color: AppTheme.success,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo'),
                      ),
                    ],
                  ),
                )
              else if (!item.isReadOnly && item.id != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (item.paymentSourceType != null &&
                            item.paymentSourceType != 'none')
                        ? AppTheme.info.withAlpha(25)
                        : AppTheme.warning.withAlpha(20),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: (item.paymentSourceType != null &&
                              item.paymentSourceType != 'none')
                          ? AppTheme.info.withAlpha(80)
                          : AppTheme.warning.withAlpha(60),
                    ),
                  ),
                  child: Text(
                    item.paymentSourceType == 'treasury'
                        ? 'محدد (خزينة)'
                        : (item.paymentSourceType == 'bank'
                            ? 'محدد (بنك)'
                            : 'آجل'),
                    style: TextStyle(
                        color: (item.paymentSourceType != null &&
                                item.paymentSourceType != 'none')
                            ? AppTheme.info
                            : AppTheme.warning,
                        fontSize: 11,
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(6)),
                child: Text('الكمية: ${item.quantity.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontFamily: 'Cairo')),
              ),
              if (item.unitPrice > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text('سعر الوحدة: ${item.unitPrice.toStringAsFixed(2)} ج.م',
                      style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          fontFamily: 'Cairo')),
                ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: color.withAlpha(40),
                    borderRadius: BorderRadius.circular(6)),
                child: Text('${item.totalPrice.toStringAsFixed(2)} ج.م',
                    style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo')),
              ),
              // Pay button has been removed based on user request (all profitability costs are deferred).
              if (!readOnly && item.reportCategoryId != _cropCatId) ...[
                GestureDetector(
                  onTap: isPaid ? null : () => _editItem(index),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: isPaid
                            ? Colors.grey.withAlpha(20)
                            : AppTheme.primary.withAlpha(20),
                        borderRadius: BorderRadius.circular(6)),
                    child: Icon(Icons.edit,
                        color: isPaid ? Colors.grey : AppTheme.primary,
                        size: 16),
                  ),
                ),
                GestureDetector(
                  onTap: () => _removeItem(index),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: isPaid
                            ? Colors.grey.withAlpha(20)
                            : AppTheme.danger.withAlpha(20),
                        borderRadius: BorderRadius.circular(6)),
                    child: Icon(Icons.close,
                        color: isPaid ? Colors.grey : AppTheme.danger,
                        size: 16),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddItemRow() {
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        spacing: 8,
        children: [
          TextButton.icon(
            onPressed: () => _addItem(
                targetCategoryId: _shippingCatId, 
                targetCategoryName: 'تكلفة شركات الشحن', 
                initialVendorType: 'shipping_company'),
            icon:
                const Icon(Icons.local_shipping_outlined, color: Colors.orange),
            label: const Text('إضافة تكلفة شحن',
                style: TextStyle(
                    color: Colors.orange,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold)),
          ),
          TextButton.icon(
            onPressed: () => _addItem(
                targetCategoryId: _clearanceCatId, 
                targetCategoryName: 'تكلفة المخلصين', 
                initialVendorType: 'clearing_agent'),
            icon:
                const Icon(Icons.verified_user_outlined, color: Colors.purple),
            label: const Text('إضافة تكلفة تخليص',
                style: TextStyle(
                    color: Colors.purple,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold)),
          ),
          TextButton.icon(
            onPressed: () => _addItem(),
            icon: const Icon(Icons.add_circle_outline, color: AppTheme.primary),
            label: const Text('إضافة بند',
                style: TextStyle(
                    color: AppTheme.primary,
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalCostCard() {
    return AppTheme.glassCardWidget(
      child: Row(
        children: [
          const Text('إجمالي التكاليف',
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                  fontFamily: 'Cairo')),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.warning.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.warning.withAlpha(50)),
            ),
            child: Text('EGP ${_totalCost.toStringAsFixed(2)}',
                style: const TextStyle(
                    color: AppTheme.warning,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceSection() {
    return AppTheme.glassCardWidget(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.currency_exchange,
                    color: AppTheme.primary, size: 16),
              ),
              const SizedBox(width: 8),
              const Text('سعر الصرف',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo')),
            ],
          ),
          const SizedBox(height: 16),
          _buildField(
              'سعر الصرف ($_currency → جنيه)', _exchangeRateCtrl, '1.00',
              enabled: !_isDistributed),
          const SizedBox(height: 12),
          _buildField(
              'المصروفات الإدارية المحملة (ج.م)', _adminExpensesCtrl, '0.00',
              enabled: !_isDistributed),
          const SizedBox(height: 12),
          _buildField(
              'الضرائب (ج.م)', _taxesCtrl, '0.00',
              enabled: !_isDistributed),
        ],
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, String hint,
      {bool enabled = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontFamily: 'Cairo')),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style:
              const TextStyle(color: AppTheme.textPrimary, fontFamily: 'Cairo'),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppTheme.textMuted),
            isDense: true,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withAlpha(30))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withAlpha(30))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.primary)),
            disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withAlpha(10))),
            filled: true,
            fillColor: enabled ? Colors.white.withAlpha(10) : Colors.white.withAlpha(5),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          onChanged: (_) => setState(() {}),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
          ],
        ),
      ],
    );
  }

  Widget _buildProfitPreview() {
    final isProfit = _netProfitEgp >= 0;
    final profitColor = isProfit ? AppTheme.success : AppTheme.danger;
    return AppTheme.glassCardWidget(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.analytics_outlined,
                    color: AppTheme.primary, size: 16),
              ),
              const SizedBox(width: 8),
              const Text('ملخص الربحية',
                  style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo')),
            ],
          ),
          const SizedBox(height: 16),
          _profitRow('إجمالي الإيراد ($_currency)',
              _totalRevenueForeign.toStringAsFixed(2), AppTheme.primary),
          const SizedBox(height: 8),
          _profitRow('إجمالي الإيراد (ج.م)',
              _totalRevenueEgp.toStringAsFixed(2), AppTheme.primary),
          const SizedBox(height: 8),
          _profitRow(
              'الخصم (ج.م)',
              ((_shipment?.discountAmount ?? 0.0) * _num(_exchangeRateCtrl)).toStringAsFixed(2),
              Colors.orange,
              bold: true),
          const SizedBox(height: 8),
          _profitRow('إجمالي التكلفة (ج.م)', _costEgp.toStringAsFixed(2),
              AppTheme.warning),
          if (_allocatedAdminExpenses > 0) ...[
            const SizedBox(height: 8),
            _profitRow('المصروفات الإدارية المحملة (ج.م)',
                _allocatedAdminExpenses.toStringAsFixed(2), Colors.purpleAccent),
          ],
          if (_allocatedTaxes > 0) ...[
            const SizedBox(height: 8),
            _profitRow('الضرائب (ج.م)',
                _allocatedTaxes.toStringAsFixed(2), Colors.amber),
          ],
          const Divider(color: AppTheme.glassBorder, height: 20),
          _profitRow('صافي الربح (ج.م)', _netProfitEgp.toStringAsFixed(2),
              profitColor,
              bold: true),
          const SizedBox(height: 8),
          _profitRow('صافي الربح (بالعملة)',
              '$currencySymbol ${_netProfitUsd.toStringAsFixed(2)}', profitColor,
              bold: true),
          const SizedBox(height: 8),
          _profitRow('هامش الربح', '${_profitMargin.toStringAsFixed(1)}%',
              profitColor),
          const Divider(color: AppTheme.glassBorder, height: 20),
          _profitRow(
              'سعر بيع الكرتونة (بالعملة)',
              '$currencySymbol ${(_cartonCount == 0 ? 0 : _totalRevenueForeign / _cartonCount).toStringAsFixed(2)}',
              AppTheme.textPrimary),
          const SizedBox(height: 4),
          _profitRow(
              'تكلفة الكرتونة (بالعملة)',
              '$currencySymbol ${_costPerCarton.toStringAsFixed(2)}',
              AppTheme.textSecondary),
          const SizedBox(height: 4),
          _profitRow(
              'ربح الكرتونة (بالعملة)',
              '$currencySymbol ${_grossPerCarton.toStringAsFixed(2)}',
              profitColor,
              bold: true),
          const Divider(color: AppTheme.glassBorder, height: 20),
          _profitRow(
              'سعر بيع الكرتونة (ج.م)',
              _revenuePerCartonEgp.toStringAsFixed(2),
              AppTheme.textPrimary),
          const SizedBox(height: 4),
          _profitRow('تكلفة الكرتونة (ج.م)',
              _costPerCartonEgp.toStringAsFixed(2), AppTheme.warning),
          const SizedBox(height: 4),
          _profitRow('ربح الكرتونة (ج.م)',
              _grossPerCartonEgp.toStringAsFixed(2), profitColor,
              bold: true),
        ],
      ),
    );
  }

  String get currencySymbol {
    switch (_currency) {
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      default:
        return '\$';
    }
  }

  Widget _profitRow(String label, String value, Color color,
      {bool bold = false}) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontFamily: 'Cairo')),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withAlpha(15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withAlpha(40)),
          ),
          child: Text(value,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                fontFamily: 'Cairo',
              )),
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    if (_isDistributed) {
      return Container(
        width: double.infinity,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withAlpha(20)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, color: AppTheme.textSecondary, size: 20),
            SizedBox(width: 8),
            Text(
              'التكاليف مقفلة (تم توزيع الأرباح على المساهمين)',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.save_outlined),
        label: Text(_saving ? 'جاري الحفظ...' : 'حفظ التكاليف',
            style: const TextStyle(fontFamily: 'Cairo', fontSize: 15)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}



class _AddItemSheet extends StatefulWidget {
  final int? targetCategoryId;
  final String? targetCategoryName;
  final ExportShipmentModel? shipment;
  final int? initialVendorId;
  final String? initialVendorType;
  final String? initialSupplierId;
  final String? initialPaymentSourceType;
  final int? initialPaymentSourceId;
  final int? initialExpenseAccountId;
  final List<Map<String, dynamic>> treasuries;
  final List<Map<String, dynamic>> bankAccounts;
  final TextEditingController descCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController priceCtrl;
  final TextEditingController exchangeCtrl;
  final void Function(
    int? reportCategoryId,
    String? vendorType,
    int? vendorId,
    String? supplierId,
    String supplierCurrency,
    String? paymentSourceType,
    int? paymentSourceId,
    int? expenseAccountId,
  ) onConfirm;

  const _AddItemSheet({
    this.targetCategoryId,
    this.targetCategoryName,
    this.shipment,
    this.initialVendorId,
    this.initialVendorType,
    this.initialSupplierId,
    this.initialPaymentSourceType,
    this.initialPaymentSourceId,
    this.initialExpenseAccountId,
    this.treasuries = const [],
    this.bankAccounts = const [],
    required this.descCtrl,
    required this.qtyCtrl,
    required this.priceCtrl,
    required this.exchangeCtrl,
    required this.onConfirm,
  });

  @override
  State<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<_AddItemSheet> {
  int? _selectedCatId;
  String? _selectedVendorType;
  
  bool get _isShippingSelected => 
      _selectedVendorType == 'shipping_company' || 
      (_selectedCatId != null && ((_allCategories[_selectedCatId]?.contains('شحن') ?? false) || (_allCategories[_selectedCatId]?.contains('نقل') ?? false)));
      
  bool get _isClearanceSelected => 
      _selectedVendorType == 'clearing_agent' || 
      (_selectedCatId != null && ((_allCategories[_selectedCatId]?.contains('تخليص') ?? false) || (_allCategories[_selectedCatId]?.contains('مخلص') ?? false)));
      
  int? _selectedVendorId;
  List<ShippingCompanyModel> _shippingCompanies = [];
  List<ClearingAgentModel> _clearingAgents = [];
  List<SupplierModel> _suppliers = [];
  bool _isLoadingVendors = false;
  String? _selectedSupplierId;
  String? _selectedSupplierName;
  final _supplierSearchCtrl = TextEditingController();
  final _vendorSearchCtrl = TextEditingController();

  Map<int, String> _allCategories = {};
  bool _loadingCategories = true;
  String _vendorCurrency = 'EGP';
  String _paymentSourceType = 'none';
  int? _selectedPaymentSourceId;
  int? _selectedExpenseAccountId;

  @override
  void initState() {
    super.initState();
    _selectedCatId = widget.targetCategoryId;
    _selectedVendorId = widget.initialVendorId;
    _selectedVendorType = widget.initialVendorType;
    _selectedSupplierId = widget.initialSupplierId;
    _paymentSourceType = widget.initialPaymentSourceType ?? 'none';
    _selectedPaymentSourceId = widget.initialPaymentSourceId;
    _selectedExpenseAccountId = widget.initialExpenseAccountId;

    widget.qtyCtrl.addListener(_onFieldChanged);
    widget.priceCtrl.addListener(_onFieldChanged);
    widget.exchangeCtrl.addListener(_onFieldChanged);

    _loadCategories();
    _fetchVendorCurrency();
    _loadSuppliers();
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.qtyCtrl.removeListener(_onFieldChanged);
    widget.priceCtrl.removeListener(_onFieldChanged);
    widget.exchangeCtrl.removeListener(_onFieldChanged);
    _supplierSearchCtrl.dispose();
    _vendorSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    try {
      _suppliers = await SupplierDao().getAll();
      if (widget.initialSupplierId != null) {
        final match = _suppliers.where((s) => s.id == widget.initialSupplierId);
        if (match.isNotEmpty && mounted) {
          setState(() {
            _selectedSupplierName = match.first.displayName;
            _supplierSearchCtrl.text = match.first.displayName;
            _vendorCurrency = match.first.currency;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchVendorCurrency() async {
    if (_selectedVendorId == null) return;
    try {
      if (_isShippingSelected || _selectedVendorType == 'shipping_company') {
        final rows = await Supabase.instance.client
            .from('shipping_companies')
            .select('currency, display_name, code')
            .eq('id', _selectedVendorId!)
            .limit(1);
        if (rows.isNotEmpty && mounted) {
          setState(() {
            _vendorCurrency = rows[0]['currency'] as String? ?? 'EGP';
            if (_vendorSearchCtrl.text.isEmpty) {
              _vendorSearchCtrl.text = rows[0]['display_name'] as String? ?? '';
            }
          });
        }
      } else if (_isClearanceSelected || _selectedVendorType == 'clearing_agent') {
        final rows = await Supabase.instance.client
            .from('clearing_agents')
            .select('currency, name, code')
            .eq('id', _selectedVendorId!)
            .limit(1);
        if (rows.isNotEmpty && mounted) {
          setState(() {
            _vendorCurrency = rows[0]['currency'] as String? ?? 'EGP';
            if (_vendorSearchCtrl.text.isEmpty) {
              final code = rows[0]['code'] as String? ?? '';
              final name = rows[0]['name'] as String? ?? '';
              _vendorSearchCtrl.text = '$code - $name';
            }
          });
        }
      }
    } catch (_) {}
  }

   Future<void> _loadCategories() async {
    try {
      final List data = await Supabase.instance.client
          .rpc('list_cost_report_categories', params: {'p_scope': 'shipment'});
      final dbCats = <int, String>{};
      for (final row in data) {
        final name = row['name'] as String;
        final id = row['id'] as int;
        dbCats[id] = name;
      }
      _allCategories = dbCats;
    } catch (_) {
      _allCategories = {};
    }

    if (widget.targetCategoryId != null && _allCategories.containsKey(widget.targetCategoryId)) {
      _selectedCatId = widget.targetCategoryId;
    } else if (widget.targetCategoryName != null) {
      final key = _allCategories.keys.firstWhere(
        (id) => _allCategories[id] == widget.targetCategoryName ||
               _allCategories[id]!.contains(widget.targetCategoryName!) ||
               widget.targetCategoryName!.contains(_allCategories[id]!),
        orElse: () => 0,
      );
      if (key != 0) {
        _selectedCatId = key;
      }
    }

    if (_selectedCatId == null) {
      if (_isShippingSelected) {
        final key = _allCategories.keys.firstWhere(
          (id) => _allCategories[id]!.contains('شحن') || _allCategories[id]!.contains('نقل'),
          orElse: () => 0,
        );
        if (key != 0) _selectedCatId = key;
      } else if (_isClearanceSelected) {
        final key = _allCategories.keys.firstWhere(
          (id) => _allCategories[id]!.contains('تخليص') || _allCategories[id]!.contains('مخلص'),
          orElse: () => 0,
        );
        if (key != 0) _selectedCatId = key;
      }
    }

    if (_selectedCatId == null) {
      final key = _allCategories.keys.firstWhere(
        (id) => _allCategories[id]!.contains('اخر') || _allCategories[id]!.contains('أخر'),
        orElse: () => 0,
      );
      _selectedCatId = key != 0
          ? key
          : (_allCategories.isNotEmpty ? _allCategories.keys.first : null);
    }

    if (_isShippingSelected || _isClearanceSelected) {
      _fetchVendors();
    }

    if (mounted) setState(() => _loadingCategories = false);
  }

  Future<void> _fetchVendors() async {
    if (!mounted) return;
    setState(() => _isLoadingVendors = true);
    if (_isShippingSelected) {
      _shippingCompanies = await ShippingCompanyDao().getAll();
      _selectedVendorType = 'shipping_company';
      // Populate search field with existing vendor name when editing
      if (_selectedVendorId != null) {
        final match = _shippingCompanies.where((c) => c.id == _selectedVendorId);
        if (match.isNotEmpty) {
          _vendorSearchCtrl.text = match.first.displayName;
          _vendorCurrency = match.first.currency;
          if (widget.initialVendorId == null && _vendorCurrency != 'EGP') {
            try {
              final rate = await CurrencyConversionService.instance.getRate(_vendorCurrency);
              widget.exchangeCtrl.text = rate.toStringAsFixed(4);
            } catch (_) {}
          }
        }
      }
    } else if (_isClearanceSelected) {
      _clearingAgents = await ClearingAgentDao().getAll();
      _selectedVendorType = 'clearing_agent';
      if (_selectedVendorId == null &&
          widget.shipment?.clearingAgentId != null) {
        _selectedVendorId =
            int.tryParse(widget.shipment!.clearingAgentId ?? '');
      }
      // Populate search field with existing vendor name when editing or auto-selected
      if (_selectedVendorId != null) {
        final match = _clearingAgents.where((c) => int.tryParse(c.id ?? '') == _selectedVendorId);
        if (match.isNotEmpty) {
          _vendorSearchCtrl.text = '${match.first.code} - ${match.first.name}';
          _vendorCurrency = match.first.currency;
          if (widget.initialVendorId == null && _vendorCurrency != 'EGP') {
            try {
              final rate = await CurrencyConversionService.instance.getRate(_vendorCurrency);
              widget.exchangeCtrl.text = rate.toStringAsFixed(4);
            } catch (_) {}
          }
        }
      }
    }
    if (mounted) setState(() => _isLoadingVendors = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xE60D2818),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(top: BorderSide(color: AppTheme.glassBorder)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.white.withAlpha(40),
                            borderRadius: BorderRadius.circular(2))),
                  ),
                  const SizedBox(height: 16),
                  const Text('تعديل/إضافة بند',
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo')),
                  const SizedBox(height: 16),
                  if (_loadingCategories)
                    const Center(child: CircularProgressIndicator())
                  else if (!_isShippingSelected && !_isClearanceSelected)
                    DropdownButtonFormField<int>(
                      initialValue: _allCategories.containsKey(_selectedCatId)
                          ? _selectedCatId
                          : null,
                      dropdownColor: AppTheme.cardBg,
                      style: const TextStyle(
                          color: AppTheme.textPrimary, fontFamily: 'Cairo'),
                      decoration: InputDecoration(
                        labelText: 'التصنيف',
                        labelStyle: const TextStyle(fontFamily: 'Cairo'),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide(color: Colors.white.withAlpha(30))),
                      ),
                      items: _allCategories.entries.map((e) {
                        return DropdownMenuItem<int>(
                            value: e.key,
                            child: Text(e.value,
                                style: const TextStyle(fontFamily: 'Cairo')));
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _selectedCatId = v;
                            _selectedVendorId = null;
                            _selectedVendorType = null;
                            _vendorCurrency = 'EGP';
                            widget.exchangeCtrl.text = '1';
                          });
                          if (_isShippingSelected || _isClearanceSelected) {
                            _fetchVendors();
                          }
                        }
                      },
                    ),
                  if (_isShippingSelected || _isClearanceSelected) ...[
                    const SizedBox(height: 12),
                    if (_isLoadingVendors)
                      const Center(child: CircularProgressIndicator())
                    else
                      TypeAheadField<int>(
                        key: ValueKey('vendor_${_isShippingSelected ? "ship" : "clear"}_$_selectedVendorId'),
                        controller: _vendorSearchCtrl,
                        autoFlipDirection: true,
                        hideOnEmpty: true,
                        hideOnError: true,
                        suggestionsCallback: (query) {
                          if (_isShippingSelected) {
                            if (query.isEmpty) return _shippingCompanies.map((c) => c.id!).toList();
                            final q = query.toLowerCase();
                            return _shippingCompanies
                                .where((c) => c.name.toLowerCase().contains(q) || c.code.toLowerCase().contains(q))
                                .map((c) => c.id!)
                                .toList();
                          } else {
                            if (query.isEmpty) return _clearingAgents.map((c) => int.parse(c.id!)).toList();
                            final q = query.toLowerCase();
                            return _clearingAgents
                                .where((c) => c.name.toLowerCase().contains(q) || c.code.toLowerCase().contains(q))
                                .map((c) => int.parse(c.id!))
                                .toList();
                          }
                        },
                        itemBuilder: (context, vendorId) {
                          if (_isShippingSelected) {
                            final c = _shippingCompanies.firstWhere((c) => c.id == vendorId);
                            return Material(
                              color: Colors.transparent,
                              child: ListTile(
                                dense: true,
                                title: Text('${c.displayName} (${c.currency})',
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13)),
                              ),
                            );
                          } else {
                            final c = _clearingAgents.firstWhere((c) => int.tryParse(c.id ?? '') == vendorId);
                            return Material(
                              color: Colors.transparent,
                              child: ListTile(
                                dense: true,
                                title: Text('${c.code} - ${c.name} (${c.currency})',
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13)),
                              ),
                            );
                          }
                        },
                        onSelected: (vendorId) async {
                          String currency = 'EGP';
                          String displayName = '';
                          if (_isShippingSelected) {
                            final match = _shippingCompanies.where((c) => c.id == vendorId);
                            if (match.isNotEmpty) {
                              currency = match.first.currency;
                              displayName = match.first.displayName;
                            }
                          } else {
                            final match = _clearingAgents.where((c) => int.tryParse(c.id ?? '') == vendorId);
                            if (match.isNotEmpty) {
                              currency = match.first.currency;
                              displayName = '${match.first.code} - ${match.first.name}';
                            }
                          }
                          setState(() {
                            _selectedVendorId = vendorId;
                            _vendorSearchCtrl.text = displayName;
                            _vendorCurrency = currency;
                          });
                          if (currency != 'EGP') {
                            try {
                              final rate = await CurrencyConversionService.instance.getRate(currency);
                              setState(() => widget.exchangeCtrl.text = rate.toStringAsFixed(4));
                            } catch (_) {
                              setState(() => widget.exchangeCtrl.text = '1');
                            }
                          } else {
                            setState(() => widget.exchangeCtrl.text = '1');
                          }
                        },
                        builder: (context, controller, focusNode) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            enabled: true,
                            decoration: InputDecoration(
                              labelText: _isShippingSelected
                                  ? 'شركة الشحن - بحث بالاسم أو الكود'
                                  : 'المخلص الجمركي - بحث بالاسم أو الكود',
                              labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withAlpha(30))),
                            ),
                            style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontFamily: 'Cairo',
                                fontSize: 14),
                          );
                        },
                      ),
                    if (_selectedVendorId != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: AppTheme.success, size: 12),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'تم اختيار: ${_vendorSearchCtrl.text}',
                                style: const TextStyle(color: AppTheme.success, fontSize: 10, fontFamily: 'Cairo'),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedVendorId = null;
                                  _vendorSearchCtrl.clear();
                                  _vendorCurrency = 'EGP';
                                  widget.exchangeCtrl.text = '1';
                                });
                              },
                              child: const Icon(Icons.close, color: AppTheme.danger, size: 12),
                            ),
                          ],
                        ),
                      ),
                    if (_selectedVendorId != null && (_vendorCurrency != 'EGP' || _isClearanceSelected)) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withAlpha(20),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('عملة ${_isShippingSelected ? "شركة الشحن" : "المخلص"}: $_vendorCurrency',
                                  style: const TextStyle(
                                      color: AppTheme.primary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo')),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: widget.exchangeCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(color: AppTheme.textPrimary, fontFamily: 'Cairo'),
                              decoration: InputDecoration(
                                labelText: 'سعر الصرف ($_vendorCurrency → ج.م)',
                                labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: Colors.white.withAlpha(30))),
                              ),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                  if (!_isShippingSelected && !_isClearanceSelected) ...[
                    const SizedBox(height: 12),
                    TypeAheadField<String>(
                      key: ValueKey(_selectedSupplierId),
                      controller: _supplierSearchCtrl,
                      autoFlipDirection: true,
                      hideOnEmpty: true,
                      hideOnError: true,
                      suggestionsCallback: (query) {
                        if (query.isEmpty) {
                          return _suppliers.map((s) => s.id!).toList();
                        }
                        final q = query.toLowerCase();
                        return _suppliers
                            .where((s) =>
                                s.name.toLowerCase().contains(q) ||
                                s.displayName.toLowerCase().contains(q) ||
                                s.supplierCode.toLowerCase().contains(q))
                            .map((s) => s.id!)
                            .toList();
                      },
                      itemBuilder: (context, supplierId) {
                        final s =
                            _suppliers.firstWhere((s) => s.id == supplierId);
                        return Material(
                          color: Colors.transparent,
                          child: ListTile(
                            dense: true,
                            title: Text(s.displayName,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'Cairo',
                                    fontSize: 13)),
                          ),
                        );
                      },
                      onSelected: (supplierId) async {
                        final s =
                            _suppliers.firstWhere((s) => s.id == supplierId);
                        setState(() {
                          _selectedSupplierId = s.id;
                          _selectedSupplierName = s.displayName;
                          _supplierSearchCtrl.text = s.displayName;
                          _vendorCurrency = s.currency;
                        });
                        if (s.currency != 'EGP') {
                          try {
                            final rate = await CurrencyConversionService.instance
                                .getRate(s.currency);
                            setState(() => widget.exchangeCtrl.text =
                                rate.toStringAsFixed(4));
                          } catch (_) {
                            setState(() => widget.exchangeCtrl.text = '');
                          }
                        } else {
                          setState(() => widget.exchangeCtrl.text = '1');
                        }
                      },
                      builder: (context, controller, focusNode) {
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            labelText: 'المورد - بحث بالاسم أو الكود',
                            labelStyle: const TextStyle(
                                fontFamily: 'Cairo', fontSize: 12),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                    color: Colors.white.withAlpha(30))),
                          ),
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontFamily: 'Cairo',
                              fontSize: 14),
                        );
                      },
                    ),
                    if (_selectedSupplierId != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle,
                                color: AppTheme.success, size: 12),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'تم اختيار: ${_selectedSupplierName ?? "جاري التحميل..."}',
                                style: const TextStyle(
                                    color: AppTheme.success,
                                    fontSize: 10,
                                    fontFamily: 'Cairo'),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedSupplierId = null;
                                  _selectedSupplierName = null;
                                  _supplierSearchCtrl.clear();
                                  _vendorCurrency = 'EGP';
                                  widget.exchangeCtrl.text = '1';
                                });
                              },
                              child: const Icon(Icons.close,
                                  color: AppTheme.danger, size: 12),
                            ),
                          ],
                        ),
                      ),
                    if (_selectedSupplierId != null &&
                        _vendorCurrency != 'EGP') ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withAlpha(20),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('عملة المورد: $_vendorCurrency',
                                  style: const TextStyle(
                                      color: AppTheme.primary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo')),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: widget.exchangeCtrl,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontFamily: 'Cairo'),
                              decoration: InputDecoration(
                                labelText: 'سعر الصرف ($_vendorCurrency → ج.م)',
                                labelStyle: const TextStyle(
                                    fontFamily: 'Cairo', fontSize: 12),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: Colors.white.withAlpha(30))),
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[\d.]'))
                              ],
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: widget.descCtrl,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontFamily: 'Cairo'),
                    decoration: InputDecoration(
                      labelText: 'البيان',
                      labelStyle: const TextStyle(fontFamily: 'Cairo'),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: Colors.white.withAlpha(30))),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: widget.qtyCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: const TextStyle(color: AppTheme.textPrimary, fontFamily: 'Cairo'),
                          decoration: InputDecoration(
                            labelText: 'الكمية',
                            labelStyle: const TextStyle(fontFamily: 'Cairo'),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                    color: Colors.white.withAlpha(30))),
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                          ],
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: widget.priceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: const TextStyle(color: AppTheme.textPrimary, fontFamily: 'Cairo'),
                          decoration: InputDecoration(
                            labelText: 'سعر الوحدة (ج.م)',
                            labelStyle: const TextStyle(fontFamily: 'Cairo'),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                    color: Colors.white.withAlpha(30))),
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[-\d.]'))
                          ],
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Builder(
                    builder: (ctx) {
                      final qty = double.tryParse(widget.qtyCtrl.text) ?? 0;
                      final price = double.tryParse(widget.priceCtrl.text) ?? 0;
                      final rate =
                          double.tryParse(widget.exchangeCtrl.text) ?? 1.0;
                      final totalEgp = qty * price;
                      final totalSupplier = rate > 0
                          ? CurrencyConversionService.instance.fromBase(totalEgp, _vendorCurrency, rate)
                          : totalEgp;

                      final hasForeign = _vendorCurrency != 'EGP';
                      final vendorLabel = _isShippingSelected
                          ? 'شركة الشحن'
                          : (_isClearanceSelected ? 'المخلص' : 'المورد');

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withAlpha(15),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: AppTheme.primary.withAlpha(45), width: 1.2),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primary.withAlpha(30),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Icon(Icons.calculate_outlined,
                                          color: AppTheme.primary, size: 16),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text('المبلغ بالجنيه:',
                                        style: TextStyle(
                                            color: AppTheme.textSecondary,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            fontFamily: 'Cairo')),
                                  ],
                                ),
                                Text('ج.م ${totalEgp.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Cairo')),
                              ],
                            ),
                            if (hasForeign) ...[
                              const SizedBox(height: 8),
                              Container(height: 1, color: Colors.white.withAlpha(15)),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: AppTheme.accent.withAlpha(30),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Icon(Icons.currency_exchange,
                                            color: AppTheme.accent, size: 16),
                                      ),
                                      const SizedBox(width: 8),
                                      Text('المبلغ بعملة $vendorLabel ($_vendorCurrency):',
                                          style: const TextStyle(
                                              color: AppTheme.textSecondary,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              fontFamily: 'Cairo')),
                                    ],
                                  ),
                                  Text(
                                    '$_vendorCurrency ${totalSupplier.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        color: AppTheme.neonCyan,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Cairo'),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),

                  Builder(
                    builder: (ctx) {
                      final qty = double.tryParse(widget.qtyCtrl.text) ?? 0;
                      final price = double.tryParse(widget.priceCtrl.text) ?? 0;
                      final totalEgp = qty * price;

                      bool isOverBalance = false;
                      double avail = 0;
                      String sourceName = '';

                      if (_paymentSourceType != 'none' &&
                          _selectedPaymentSourceId != null) {
                        if (_paymentSourceType == 'treasury') {
                          final match = widget.treasuries.where((t) =>
                              (t['id'] as num).toInt() ==
                              _selectedPaymentSourceId);
                          if (match.isNotEmpty) {
                            sourceName = match.first['name']?.toString() ??
                                'الخزينة المختارة';
                            final balances = match.first['treasury_balances'];
                            if (balances is List && balances.isNotEmpty) {
                              final egp = balances
                                  .where((b) => b['currency'] == 'EGP')
                                  .toList();
                              if (egp.isNotEmpty) {
                                avail =
                                    (egp.first['balance'] as num?)?.toDouble() ??
                                        0;
                              } else {
                                avail = (balances.first['balance'] as num?)
                                        ?.toDouble() ??
                                    0;
                              }
                            }
                          }
                        } else if (_paymentSourceType == 'bank') {
                          final match = widget.bankAccounts.where((b) =>
                              (b['id'] as num).toInt() ==
                              _selectedPaymentSourceId);
                          if (match.isNotEmpty) {
                            sourceName = match.first['name']?.toString() ??
                                'الحساب البنكي';
                            avail =
                                (match.first['balance'] as num?)?.toDouble() ?? 0;
                          }
                        }
                        if (totalEgp > avail) {
                          isOverBalance = true;
                        }
                      }

                      final hasDesc = widget.descCtrl.text.trim().isNotEmpty;
                      final priceVal = double.tryParse(widget.priceCtrl.text);
                      final hasPrice = priceVal != null && priceVal > 0;
                      final qtyVal = double.tryParse(widget.qtyCtrl.text);
                      final hasQty = qtyVal != null && qtyVal > 0;
                      final rateVal = double.tryParse(widget.exchangeCtrl.text);
                      final hasRate = rateVal != null && rateVal > 0;
                      final hasVendor = (_isShippingSelected || _isClearanceSelected)
                          ? (_selectedVendorId != null)
                          : (_selectedSupplierId != null);

                      final canSubmit = hasDesc &&
                          hasPrice &&
                          hasQty &&
                          hasRate &&
                          hasVendor &&
                          !isOverBalance &&
                          (_paymentSourceType == 'none' ||
                              _selectedPaymentSourceId != null);

                      return Column(
                        children: [
                          if (isOverBalance) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.danger.withAlpha(30),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: AppTheme.danger.withAlpha(80)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.warning_amber_rounded,
                                      color: AppTheme.danger, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '⚠️ تنبيه: المبلغ الإجمالي للبند (${totalEgp.toStringAsFixed(2)} ج.م) أكبر من الرصيد المتوفر في $sourceName (${avail.toStringAsFixed(2)} ج.م)',
                                      style: const TextStyle(
                                          color: AppTheme.danger,
                                          fontSize: 11,
                                          fontFamily: 'Cairo',
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: canSubmit
                                  ? () => widget.onConfirm(
                                        _selectedCatId,
                                        _selectedVendorType,
                                        _selectedVendorId,
                                        _selectedSupplierId,
                                        _vendorCurrency,
                                        _paymentSourceType == 'none'
                                            ? null
                                            : _paymentSourceType,
                                        _paymentSourceType == 'none'
                                            ? null
                                            : _selectedPaymentSourceId,
                                        _isClearanceSelected ? _selectedExpenseAccountId : null,
                                      )
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: canSubmit
                                    ? AppTheme.primary
                                    : Colors.white.withAlpha(20),
                                foregroundColor: canSubmit
                                    ? Colors.white
                                    : Colors.white.withAlpha(80),
                                disabledBackgroundColor: Colors.white.withAlpha(15),
                                disabledForegroundColor: Colors.white.withAlpha(70),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('حفظ',
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
