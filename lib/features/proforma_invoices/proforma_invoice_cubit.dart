import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/models/proforma_invoice_model.dart';
import '../../../data/models/customer_model.dart';
import '../../../data/dao/proforma_invoice_dao.dart';
import '../../../data/dao/proforma_invoice_item_dao.dart';
import '../../../data/dao/customer_dao.dart';
import '../../../data/dao/invoice_dao.dart';
import '../../../data/services/cogs_automation_service.dart';
import '../../../data/services/shipment_deletion_service.dart';
import '../../../data/services/recipe_snapshot_service.dart';

// States
abstract class ProformaInvoiceState {
  const ProformaInvoiceState();
}
class ProformaInvoiceInitial extends ProformaInvoiceState {}
class ProformaInvoiceLoading extends ProformaInvoiceState {}
class ProformaInvoiceListLoaded extends ProformaInvoiceState {
  final List<ProformaInvoiceModel> shipments;
  final String? statusFilter;
  final String? searchQuery;
  final bool isLoadingMore;
  const ProformaInvoiceListLoaded(this.shipments, {this.statusFilter, this.searchQuery, this.isLoadingMore = false});
}
class ProformaInvoiceDetailLoaded extends ProformaInvoiceState {
  final ProformaInvoiceModel shipment;
  const ProformaInvoiceDetailLoaded(this.shipment);
}
class ProformaInvoiceFormLoaded extends ProformaInvoiceState {
  final ProformaInvoiceModel? shipment;
  final ProformaInvoiceModel defaults;
  final List<CustomerModel> customers;
  final List<dynamic> invoices;
  final List<Map<String, dynamic>> items;
  final double totalExtraCosts;
  const ProformaInvoiceFormLoaded(this.shipment, this.defaults, {this.customers = const [], this.invoices = const [], this.items = const [], this.totalExtraCosts = 0.0});
}
class ProformaInvoiceOperationSuccess extends ProformaInvoiceState {
  final String message;
  const ProformaInvoiceOperationSuccess(this.message);
}
class ProformaInvoiceError extends ProformaInvoiceState {
  final String message;
  const ProformaInvoiceError(this.message);
}

class ProformaInvoiceCubit extends Cubit<ProformaInvoiceState> {
  final _dao = ProformaInvoiceDao();
  final _itemDao = ProformaInvoiceItemDao();
  final _customerDao = CustomerDao();
  final _invoiceDao = InvoiceDao();
  final _cogsService = CogsAutomationService();
  final _deletionService = ShipmentDeletionService();
  int _currentPage = 0;
  static const _pageSize = 50;

  ProformaInvoiceCubit() : super(ProformaInvoiceInitial());

  void loadLatest() async {
    emit(ProformaInvoiceLoading());
    try {
      final latest = await _dao.getLatest();
      emit(ProformaInvoiceListLoaded(latest != null ? [latest] : []));
    } catch (e, stack) {
      debugPrint('ProformaInvoice.loadLatest failed: $e\n$stack');
      emit(ProformaInvoiceError(e.toString()));
    }
  }

  void load({String? status, String? search, String? fromDate, String? toDate, String? excludeStatus}) {
    _currentPage = 0;
    emit(ProformaInvoiceLoading());
    _fetch(status: status, search: search, fromDate: fromDate, toDate: toDate, excludeStatus: excludeStatus);
  }

  void loadMore({String? status, String? search, String? fromDate, String? toDate, String? excludeStatus}) {
    if (state is ProformaInvoiceListLoaded && (state as ProformaInvoiceListLoaded).isLoadingMore) return;
    _currentPage++;
    final current = state is ProformaInvoiceListLoaded ? (state as ProformaInvoiceListLoaded).shipments : <ProformaInvoiceModel>[];
    emit(ProformaInvoiceListLoaded(current, statusFilter: status, searchQuery: search, isLoadingMore: true));
    _fetch(status: status, search: search, fromDate: fromDate, toDate: toDate, append: true, excludeStatus: excludeStatus);
  }

  Future<void> _fetch({
    String? status, String? search, String? fromDate, String? toDate, bool append = false, String? excludeStatus,
  }) async {
    try {
      final result = await _dao.getAll(
        status: status,
        searchQuery: search,
        fromDate: fromDate,
        toDate: toDate,
        limit: _pageSize,
        offset: _currentPage * _pageSize,
        excludeStatus: excludeStatus,
      );
      final current = append && state is ProformaInvoiceListLoaded
          ? (state as ProformaInvoiceListLoaded).shipments
          : <ProformaInvoiceModel>[];
      current.addAll(result);
      emit(ProformaInvoiceListLoaded(
        current.toSet().toList(),
        statusFilter: status,
        searchQuery: search,
      ));
    } catch (e, stack) {
      debugPrint('ProformaInvoice._fetch failed: $e\n$stack');
      emit(ProformaInvoiceError(e.toString()));
    }
  }

  void loadDetail(dynamic id) async {
    emit(ProformaInvoiceLoading());
    try {
      final shipment = await _dao.getById(id);
      if (shipment != null) {
        emit(ProformaInvoiceDetailLoaded(shipment));
      } else {
        emit(const ProformaInvoiceError('الشحنة غير موجودة'));
      }
    } catch (e, stack) {
      debugPrint('ProformaInvoice.loadDetail failed: $e\n$stack');
      emit(ProformaInvoiceError(e.toString()));
    }
  }

  void loadForm(dynamic id) async {
    emit(ProformaInvoiceLoading());
    try {
      ProformaInvoiceModel? shipment;
      List<Map<String, dynamic>> items = [];
      double totalExtraCosts = 0.0;
      if (id != null) {
        shipment = await _dao.getById(id);
        try {
          items = await _itemDao.getByShipmentId(id);
          final costs = await Supabase.instance.client.from('shipment_cost_items').select().eq('shipment_id', id);
          for (final c in costs) {
            totalExtraCosts += double.tryParse(c['amount']?.toString() ?? '0') ?? 0;
          }
        } catch (_) {}
      }
      final results = await Future.wait([
        _customerDao.getAll(limit: 2000, customerType: 'export'),
        _invoiceDao.getAll(limit: 2000),
      ]);
      final customers = results[0] as List<CustomerModel>;
      final rawInvoices = results[1] as List;
      final defaults = ProformaInvoiceModel(shipmentNo: '', transportMode: 'sea');
      emit(ProformaInvoiceFormLoaded(shipment, defaults, customers: customers, invoices: rawInvoices, items: items, totalExtraCosts: totalExtraCosts));
    } catch (e, stack) {
      debugPrint('ProformaInvoice.loadForm failed: $e\n$stack');
      emit(ProformaInvoiceError(e.toString()));
    }
  }

  Future<String> getNextShipmentNo(String customerCode, int year) async {
    return await _dao.getNextShipmentNo(customerCode, year);
  }

  Future<void> save(ProformaInvoiceModel shipment, {List<Map<String, dynamic>> items = const []}) async {
    emit(ProformaInvoiceLoading());
    try {
      final packingOrderIds = items
          .map((i) => i['packingOrderId'])
          .where((id) => id != null)
          .map((id) => id is int ? id : int.tryParse('$id'))
          .where((id) => id != null)
          .cast<int>()
          .toList();

      if (shipment.id != null) {
        // Restore old sold_cartons before re-linking
        await _restoreSoldCartons(shipment.id);
        await _dao.update(shipment);
        await _itemDao.deleteByShipmentId(shipment.id);
        if (items.isNotEmpty) {
          await _itemDao.insertAll(shipment.id, items);
        }
        await _linkPackingOrders(shipment.id, packingOrderIds);
        await _updateSoldCartons(items);
        await _dao.syncLedger(shipment.id);
        emit(const ProformaInvoiceOperationSuccess('تم تحديث الشحنة بنجاح'));
      } else {
        final newId = await _dao.insert(shipment);
        if (items.isNotEmpty) {
          await _itemDao.insertAll(newId, items);
        }
        await _linkPackingOrders(newId, packingOrderIds);
        await _updateSoldCartons(items);

        try {
          final sid = newId is int ? newId : int.tryParse('$newId');
          if (sid != null) {
            await RecipeSnapshotService().createSnapshot(sid);
          }
        } catch (e) {
          debugPrint('⚠️ Recipe snapshot creation failed: $e');
        }
        await _dao.syncLedger(newId);
        emit(const ProformaInvoiceOperationSuccess('تم إنشاء الشحنة بنجاح'));
      }
    } catch (e, stack) {
      debugPrint('ProformaInvoice.save failed: $e\n$stack');
      emit(ProformaInvoiceError(e.toString()));
    }
  }

  Future<void> _linkPackingOrders(dynamic shipmentId, List<int> packingOrderIds) async {
    if (packingOrderIds.isEmpty) return;
    final sid = shipmentId is int ? shipmentId : int.tryParse('$shipmentId');
    if (sid == null) return;
    try {
      final client = Supabase.instance.client;
      // Unlink any previously linked orders for this shipment
      await client
          .from('packing_orders')
          .update({'proforma_invoice_id': null})
          .eq('proforma_invoice_id', sid);
      // Link selected orders and update sold_cartons
      for (final poId in packingOrderIds) {
        await client
            .from('packing_orders')
            .update({'proforma_invoice_id': sid})
            .eq('id', poId);
      }
      debugPrint('✅ Linked $shipmentId <- packing orders: $packingOrderIds');
    } catch (e) {
      debugPrint('⚠️ Failed to link packing orders: $e');
    }
  }

  Future<void> _updateSoldCartons(List<Map<String, dynamic>> items) async {
    try {
      final client = Supabase.instance.client;
      for (final item in items) {
        final poId = item['packingOrderId'];
        final qty = item['quantity'];
        if (poId == null || qty == null) continue;
        final poIdInt = poId is int ? poId : int.tryParse('$poId');
        final qtyInt = qty is int ? qty : int.tryParse('$qty');
        if (poIdInt == null || qtyInt == null || qtyInt <= 0) continue;
        await client.rpc('increment_sold_cartons', params: {
          'p_packing_order_id': poIdInt,
          'p_additional': qtyInt,
        });
      }
    } catch (e) {
      debugPrint('⚠️ Failed to update sold_cartons: $e');
    }
  }

  Future<void> _restoreSoldCartons(dynamic shipmentId) async {
    try {
      final client = Supabase.instance.client;
      final sid = shipmentId is int ? shipmentId : int.tryParse('$shipmentId');
      if (sid == null) return;
      final items = await client
          .from('proforma_invoice_items')
          .select('packing_order_id, quantity')
          .eq('shipment_id', sid);
      for (final item in items) {
        final poId = item['packing_order_id'];
        final qty = item['quantity'];
        if (poId == null || qty == null) continue;
        final poIdInt = poId is int ? poId : int.tryParse('$poId');
        final qtyInt = qty is int ? qty : int.tryParse('$qty');
        if (poIdInt == null || qtyInt == null || qtyInt <= 0) continue;
        await client.rpc('decrement_sold_cartons', params: {
          'p_packing_order_id': poIdInt,
          'p_amount': qtyInt,
        });
      }
    } catch (e) {
      debugPrint('⚠️ Failed to restore sold_cartons: $e');
    }
  }

  /// Permanently and completely removes shipment [id] and ALL related records
  /// from every known FK table.  Transactional steps:
  ///   1. Mark COGS as un-posted
  ///   2. Unlink packing_orders
  ///   3. Delete proforma_invoice_items, cost_breakdown, allocations, etc.
  ///   4. Delete the proforma_invoice row
  ///   5. Verify zero remaining references
  Future<void> delete(dynamic id) async {
    debugPrint('>>> ProformaInvoiceCubit.delete: id=$id (type=${id.runtimeType})');
    try {
      final sid = id is int ? id : int.tryParse('$id');
      if (sid == null) throw Exception('Invalid shipment id: $id');

      // Restore sold_cartons before deletion removes the items
      await _restoreSoldCartons(sid);

      await _cogsService.reverseCogsForShipment(sid);
      final report = await _deletionService.delete(sid);

      debugPrint('<<< ProformaInvoiceCubit.delete: complete, '
          'success=${report.success}, errors=${report.errors.length}');
      emit(const ProformaInvoiceOperationSuccess('تم حذف الشحنة بنجاح'));
    } catch (e, stack) {
      debugPrint('<<< ProformaInvoiceCubit.delete FAILED: id=$id, error=$e\n$stack');
      emit(ProformaInvoiceError(e.toString()));
    }
  }

  Future<void> updateStatus(dynamic id, String status) async {
    try {
      await _dao.updateStatus(id, status);

      final sid = id is int ? id : int.tryParse('$id');
      // Auto-post COGS when shipment is confirmed as shipped
      if (status == 'shipped' || status == 'in_transit') {
        if (sid != null) {
          await _cogsService.postCogsForShipment(sid);
        }
      }
      // Reverse COGS when shipment is cancelled
      if (status == 'cancelled' && sid != null) {
        await _cogsService.reverseCogsForShipment(sid);
        debugPrint('ProformaInvoiceCubit.updateStatus: COGS reversed for cancelled shipment $sid');
      }

      emit(const ProformaInvoiceOperationSuccess('تم تحديث حالة الشحنة بنجاح'));
    } catch (e, stack) {
      debugPrint('ProformaInvoice.updateStatus failed: $e\n$stack');
      emit(ProformaInvoiceError(e.toString()));
    }
  }
}
