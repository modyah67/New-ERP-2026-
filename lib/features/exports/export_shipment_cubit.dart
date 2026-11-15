import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/models/export_shipment_model.dart';
import '../../../data/models/customer_model.dart';
import '../../../data/dao/export_shipment_dao.dart';
import '../../../data/dao/export_shipment_item_dao.dart';
import '../../../data/dao/customer_dao.dart';
import '../../../data/dao/invoice_dao.dart';
import '../../../data/services/cogs_automation_service.dart';
import '../../../data/services/shipment_deletion_service.dart';
import '../../../data/services/recipe_snapshot_service.dart';
import '../../../data/services/shipment_payment_service.dart';
import '../../../data/services/cost_allocation_service.dart';

// States
abstract class ExportShipmentState {
  const ExportShipmentState();
}

class ExportShipmentInitial extends ExportShipmentState {}

class ExportShipmentLoading extends ExportShipmentState {}

class ExportShipmentListLoaded extends ExportShipmentState {
  final List<ExportShipmentModel> shipments;
  final String? statusFilter;
  final String? searchQuery;
  final bool isLoadingMore;
  const ExportShipmentListLoaded(this.shipments,
      {this.statusFilter, this.searchQuery, this.isLoadingMore = false});
}

class ExportShipmentDetailLoaded extends ExportShipmentState {
  final ExportShipmentModel shipment;
  const ExportShipmentDetailLoaded(this.shipment);
}

class ExportShipmentFormLoaded extends ExportShipmentState {
  final ExportShipmentModel? shipment;
  final ExportShipmentModel defaults;
  final List<CustomerModel> customers;
  final List<dynamic> invoices;
  final List<Map<String, dynamic>> items;
  final double totalExtraCosts;
  const ExportShipmentFormLoaded(this.shipment, this.defaults,
      {this.customers = const [],
      this.invoices = const [],
      this.items = const [],
      this.totalExtraCosts = 0.0});
}

class ExportShipmentOperationSuccess extends ExportShipmentState {
  final String message;
  const ExportShipmentOperationSuccess(this.message);
}

class ExportShipmentError extends ExportShipmentState {
  final String message;
  const ExportShipmentError(this.message);
}

class ExportShipmentCubit extends Cubit<ExportShipmentState> {
  final _dao = ExportShipmentDao();
  final _itemDao = ExportShipmentItemDao();
  final _customerDao = CustomerDao();
  final _invoiceDao = InvoiceDao();
  final _cogsService = CogsAutomationService();
  final _deletionService = ShipmentDeletionService();
  int _currentPage = 0;
  static const _pageSize = 50;

  ExportShipmentCubit() : super(ExportShipmentInitial());

  void loadLatest() async {
    emit(ExportShipmentLoading());
    try {
      final latest = await _dao.getLatest();
      emit(ExportShipmentListLoaded(latest != null ? [latest] : []));
    } catch (e, stack) {
      debugPrint('ExportShipment.loadLatest failed: $e\n$stack');
      emit(ExportShipmentError(e.toString()));
    }
  }

  void load(
      {String? status,
      String? search,
      String? fromDate,
      String? toDate,
      String? excludeStatus}) {
    _currentPage = 0;
    emit(ExportShipmentLoading());
    _fetch(
        status: status,
        search: search,
        fromDate: fromDate,
        toDate: toDate,
        excludeStatus: excludeStatus);
  }

  void loadMore(
      {String? status,
      String? search,
      String? fromDate,
      String? toDate,
      String? excludeStatus}) {
    if (state is ExportShipmentListLoaded &&
        (state as ExportShipmentListLoaded).isLoadingMore) return;
    _currentPage++;
    final current = state is ExportShipmentListLoaded
        ? (state as ExportShipmentListLoaded).shipments
        : <ExportShipmentModel>[];
    emit(ExportShipmentListLoaded(current,
        statusFilter: status, searchQuery: search, isLoadingMore: true));
    _fetch(
        status: status,
        search: search,
        fromDate: fromDate,
        toDate: toDate,
        append: true,
        excludeStatus: excludeStatus);
  }

  Future<void> _fetch({
    String? status,
    String? search,
    String? fromDate,
    String? toDate,
    bool append = false,
    String? excludeStatus,
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
      final current = append && state is ExportShipmentListLoaded
          ? (state as ExportShipmentListLoaded).shipments
          : <ExportShipmentModel>[];
      current.addAll(result);
      emit(ExportShipmentListLoaded(
        current.toSet().toList(),
        statusFilter: status,
        searchQuery: search,
      ));
    } catch (e, stack) {
      debugPrint('ExportShipment._fetch failed: $e\n$stack');
      emit(ExportShipmentError(e.toString()));
    }
  }

  void loadDetail(dynamic id) async {
    emit(ExportShipmentLoading());
    try {
      final shipment = await _dao.getById(id);
      if (shipment != null) {
        emit(ExportShipmentDetailLoaded(shipment));
      } else {
        emit(const ExportShipmentError('الشحنة غير موجودة'));
      }
    } catch (e, stack) {
      debugPrint('ExportShipment.loadDetail failed: $e\n$stack');
      emit(ExportShipmentError(e.toString()));
    }
  }

  void loadForm(dynamic id) async {
    emit(ExportShipmentLoading());
    try {
      ExportShipmentModel? shipment;
      List<Map<String, dynamic>> items = [];
      double totalExtraCosts = 0.0;
      if (id != null) {
        shipment = await _dao.getById(id);
        try {
          items = await _itemDao.getByShipmentId(id);
          final costs = await Supabase.instance.client
              .from('shipment_cost_items')
              .select()
              .eq('shipment_id', id);
          for (final c in costs) {
            totalExtraCosts +=
                double.tryParse(c['amount']?.toString() ?? '0') ?? 0;
          }
        } catch (_) {}
      }
      final results = await Future.wait([
        _customerDao.getAll(limit: 2000, customerType: 'export'),
        _invoiceDao.getAll(limit: 2000),
      ]);
      final customers = results[0] as List<CustomerModel>;
      final rawInvoices = results[1] as List;
      final defaults =
          ExportShipmentModel(shipmentNo: '', transportMode: 'sea');
      emit(ExportShipmentFormLoaded(shipment, defaults,
          customers: customers,
          invoices: rawInvoices,
          items: items,
          totalExtraCosts: totalExtraCosts));
    } catch (e, stack) {
      debugPrint('ExportShipment.loadForm failed: $e\n$stack');
      emit(ExportShipmentError(e.toString()));
    }
  }

  Future<String> getNextShipmentNo(String customerCode, int year) async {
    return await _dao.getNextShipmentNo(customerCode, year);
  }

  Future<void> save(ExportShipmentModel shipment,
      {List<Map<String, dynamic>> items = const []}) async {
    emit(ExportShipmentLoading());
    try {
      if (shipment.id != null) {
        // Get old shipment for payment delta calculation
        ExportShipmentModel? oldShipment;
        try {
          oldShipment = await _dao.getById(shipment.id);
        } catch (_) {}

        await _dao.saveWithRpc(shipment, items);

        if (shipment.isConfirmed) {
          try {
            await CostAllocationService().accumulateShipmentCosts(shipment.id!);
          } catch (e) {
            debugPrint('Cost accumulation failed: $e');
          }
        }
        try {
          await _dao.syncLedger(shipment.id);
        } catch (e) {
          debugPrint('⚠️ Sync ledger on update: $e');
        }

        // Process treasury/bank payment delta (edit case)
        if (shipment.isConfirmed &&
            oldShipment != null &&
            (shipment.paidAmount != oldShipment.paidAmount ||
                shipment.paymentSourceType != oldShipment.paymentSourceType ||
                shipment.paymentTreasuryId != oldShipment.paymentTreasuryId ||
                shipment.paymentBankAccountId !=
                    oldShipment.paymentBankAccountId)) {
          try {
            await ShipmentPaymentService().processPayment(
              shipment: shipment,
              customerName: shipment.customerName,
              oldPaidAmount: oldShipment.paidAmount,
              oldPaymentSourceType: oldShipment.paymentSourceType,
              oldPaymentTreasuryId: oldShipment.paymentTreasuryId,
              oldPaymentBankAccountId: oldShipment.paymentBankAccountId,
            );
            debugPrint('✅ Shipment payment delta processed');
          } catch (e) {
            debugPrint('⚠️ Shipment payment delta failed (non-fatal): $e');
          }
        }

        emit(const ExportShipmentOperationSuccess('تم تحديث الشحنة بنجاح'));
      } else {
        final newId = await _dao.saveWithRpc(shipment, items);

        try {
          final sid = newId is int ? newId : int.tryParse('$newId');
          if (sid != null) {
            await RecipeSnapshotService().createSnapshot(sid);
          }
        } catch (e) {
          debugPrint('⚠️  Recipe snapshot creation failed: $e');
        }
        if (shipment.isConfirmed) {
          try {
            await CostAllocationService().accumulateShipmentCosts(newId.toString());
          } catch (e) {
            debugPrint('Cost accumulation failed: $e');
          }
        }
        try {
          await _dao.syncLedger(newId);
        } catch (e) {
          debugPrint('⚠️ Sync ledger on new shipment: $e');
        }

        // Process treasury/bank deposit (insert case)
        if (shipment.isConfirmed && shipment.paidAmount > 0) {
          try {
            final sid = newId is int ? newId : int.tryParse('$newId');
            await ShipmentPaymentService().processPayment(
              shipment: shipment.copyWith(id: sid?.toString()),
              customerName: shipment.customerName,
            );
            debugPrint('✅ Shipment payment processed: ${shipment.paidAmount}');
          } catch (e) {
            debugPrint('⚠️ Shipment payment failed (non-fatal): $e');
          }
        }

        emit(const ExportShipmentOperationSuccess('تم إنشاء الشحنة بنجاح'));
      }
    } catch (e, stack) {
      debugPrint('ExportShipment.save failed: $e\n$stack');
      emit(ExportShipmentError(e.toString()));
    }
  }

  Future<void> _restoreSoldCartons(dynamic shipmentId) async {
    try {
      final client = Supabase.instance.client;
      final sid = shipmentId is int ? shipmentId : int.tryParse('$shipmentId');
      if (sid == null) return;
      final items = await client
          .from('export_shipment_items')
          .select('packing_order_id, cartons')
          .eq('shipment_id', sid);
      for (final item in items) {
        final poId = item['packing_order_id'];
        final qty = item['cartons'];
        if (poId == null || qty == null) continue;
        final poIdInt = poId is int ? poId : int.tryParse('$poId');
        final qtyInt = qty is int ? qty : int.tryParse('$qty');
        if (poIdInt == null || qtyInt == null || qtyInt <= 0) continue;
        await client.rpc('increment_sold_cartons', params: {
          'p_order_id': poIdInt,
          'p_additional_cartons': -qtyInt,
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
  ///   3. Delete export_shipment_items, cost_breakdown, allocations, etc.
  ///   4. Delete the export_shipment row
  ///   5. Verify zero remaining references
  Future<void> delete(dynamic id) async {
    debugPrint(
        '>>> ExportShipmentCubit.delete: id=$id (type=${id.runtimeType})');
    try {
      final sid = id is int ? id : int.tryParse('$id');
      if (sid == null) throw Exception('Invalid shipment id: $id');

      // Restore sold_cartons before deletion removes the items
      await _restoreSoldCartons(sid);

      await _cogsService.reverseCogsForShipment(sid);
      final report = await _deletionService.delete(sid);

      debugPrint('<<< ExportShipmentCubit.delete: complete, '
          'success=${report.success}, errors=${report.errors.length}');
      emit(const ExportShipmentOperationSuccess('تم حذف الشحنة بنجاح'));
    } catch (e, stack) {
      debugPrint(
          '<<< ExportShipmentCubit.delete FAILED: id=$id, error=$e\n$stack');
      emit(ExportShipmentError(e.toString()));
    }
  }

  Future<void> updateStatus(dynamic id, String status) async {
    try {
      // Cancellation now uses dedicated RPC with full accounting reversal
      if (status == 'cancelled') {
        await cancelShipment(id);
        return;
      }

      await _dao.updateStatus(id, status);

      final sid = id is int ? id : int.tryParse('$id');
      // Auto-post COGS when shipment is confirmed as shipped
      if (status == 'shipped' || status == 'in_transit') {
        if (sid != null) {
          await _cogsService.postCogsForShipment(sid);
        }
      }

      emit(const ExportShipmentOperationSuccess('تم تحديث حالة الشحنة بنجاح'));
    } catch (e, stack) {
      debugPrint('ExportShipment.updateStatus failed: $e\n$stack');
      emit(ExportShipmentError(e.toString()));
    }
  }

  /// Cancel shipment with full accounting reversal via SQL RPC.
  /// Reverses customer balance, ledger entries, creates journal entries
  /// and treasury transaction for cancellation audit trail.
  Future<void> cancelShipment(dynamic id) async {
    try {
      final result = await _dao.cancelShipment(id);

      final netAmount = result['net_amount'] ?? 0;
      final message = 'تم إلغاء الشحنة بنجاح - '
          'قيمة الإلغاء: $netAmount '
          '${result['currency'] ?? ''}';

      emit(ExportShipmentOperationSuccess(message));
    } catch (e, stack) {
      debugPrint('ExportShipment.cancelShipment failed: $e\n$stack');
      emit(ExportShipmentError(e.toString()));
    }
  }

  Future<void> confirmShipment(ExportShipmentModel shipment) async {
    emit(ExportShipmentLoading());
    try {
      final client = Supabase.instance.client;
      await client
          .from('export_shipments')
          .update({'is_confirmed': true}).eq('id', shipment.id.toString());

      // Reload fresh from DB to get latest paidAmount (may have been updated in form)
      final fresh = await _dao.getById(shipment.id);
      final freshShipment = fresh ?? shipment;

      await _dao.syncLedger(shipment.id);

      if (freshShipment.paidAmount > 0) {
        debugPrint(
            '💰 Processing payment: ${freshShipment.paidAmount} via ${freshShipment.paymentSourceType}');
        try {
          await ShipmentPaymentService().processPayment(
            shipment: freshShipment.copyWith(isConfirmed: true),
            customerName: freshShipment.customerName,
          );
          debugPrint('✅ Payment processed successfully');
        } catch (e) {
          debugPrint('⚠️ Shipment payment failed during confirm: $e');
        }
      } else {
        debugPrint('ℹ️ No paid amount, skipping payment processing');
      }

      // Emit success so the list page listener reloads via _applyAllFilters()
      emit(const ExportShipmentOperationSuccess('تم تأكيد الشحنة بنجاح'));
    } catch (e, stack) {
      debugPrint('ExportShipment.confirmShipment failed: $e\n$stack');
      emit(ExportShipmentError(e.toString()));
    }
  }

  Future<void> updateDiscount(
      dynamic id, double discountAmount, String? reason) async {
    emit(ExportShipmentLoading());
    try {
      await _dao.applyDiscount(
        shipmentId: id,
        discountAmount: discountAmount,
        reason: reason,
      );
      emit(const ExportShipmentOperationSuccess(
          'تم تعديل الخصم وتحديث القيود بنجاح'));
    } catch (e, stack) {
      debugPrint('ExportShipment.updateDiscount failed: $e\n$stack');
      emit(ExportShipmentError(e.toString()));
    }
  }
}
