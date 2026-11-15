import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/models/customer_model.dart';
import '../../data/dao/customer_dao.dart';
import '../../data/dao/clearing_agent_dao.dart';
import '../../data/models/clearing_agent_model.dart';
import 'proforma_invoice_model.dart';
import 'proforma_invoice_dao.dart';

abstract class ProformaInvoiceState {
  const ProformaInvoiceState();
}

class ProformaInvoiceInitial extends ProformaInvoiceState {}

class ProformaInvoiceLoading extends ProformaInvoiceState {}

class ProformaInvoiceListLoaded extends ProformaInvoiceState {
  final List<ProformaInvoiceModel> invoices;
  final bool isLoadingMore;
  const ProformaInvoiceListLoaded(this.invoices, {this.isLoadingMore = false});
}

class ProformaInvoiceFormLoaded extends ProformaInvoiceState {
  final ProformaInvoiceModel? invoice;
  final List<CustomerModel> customers;
  final List<ClearingAgentModel> clearingAgents;
  final List<ProformaInvoiceItem> items;
  const ProformaInvoiceFormLoaded(this.invoice,
      {this.customers = const [],
      this.clearingAgents = const [],
      this.items = const []});
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
  final _customerDao = CustomerDao();
  final _clearingAgentDao = ClearingAgentDao();
  int _currentPage = 0;
  static const _pageSize = 50;

  ProformaInvoiceCubit() : super(ProformaInvoiceInitial());

  void load({String? search, String? fromDate, String? toDate}) {
    _currentPage = 0;
    emit(ProformaInvoiceLoading());
    _fetch(search: search, fromDate: fromDate, toDate: toDate);
  }

  void loadMore({String? search, String? fromDate, String? toDate}) {
    if (state is ProformaInvoiceListLoaded &&
        (state as ProformaInvoiceListLoaded).isLoadingMore) return;
    _currentPage++;
    final current = state is ProformaInvoiceListLoaded
        ? (state as ProformaInvoiceListLoaded).invoices
        : <ProformaInvoiceModel>[];
    emit(ProformaInvoiceListLoaded(current, isLoadingMore: true));
    _fetch(
        search: search, fromDate: fromDate, toDate: toDate, append: true);
  }

  Future<void> _fetch({
    String? search,
    String? fromDate,
    String? toDate,
    bool append = false,
  }) async {
    try {
      final result = await _dao.getAll(
        searchQuery: search,
        fromDate: fromDate,
        toDate: toDate,
        limit: _pageSize,
        offset: _currentPage * _pageSize,
      );
      final current = append && state is ProformaInvoiceListLoaded
          ? (state as ProformaInvoiceListLoaded).invoices
          : <ProformaInvoiceModel>[];
      current.addAll(result);
      emit(ProformaInvoiceListLoaded(current.toSet().toList()));
    } catch (e, stack) {
      emit(ProformaInvoiceError(e.toString()));
    }
  }

  void loadForm(dynamic id) async {
    emit(ProformaInvoiceLoading());
    try {
      ProformaInvoiceModel? invoice;
      List<ProformaInvoiceItem> items = [];
      if (id != null) {
        invoice = await _dao.getById(id);
        items = await _dao.getItems(id);
      }
      final results = await Future.wait([
        _customerDao.getAll(limit: 2000, customerType: 'export'),
        _clearingAgentDao.getAll(limit: 2000),
      ]);
      final customers = results[0] as List<CustomerModel>;
      final clearingAgents = results[1] as List<ClearingAgentModel>;
      emit(ProformaInvoiceFormLoaded(invoice,
          customers: customers,
          clearingAgents: clearingAgents,
          items: items));
    } catch (e, stack) {
      emit(ProformaInvoiceError(e.toString()));
    }
  }

  Future<String> getNextInvoiceNo(int year) async {
    return await _dao.getNextInvoiceNo(year);
  }

  Future<void> save(ProformaInvoiceModel invoice,
      {List<ProformaInvoiceItem> items = const []}) async {
    emit(ProformaInvoiceLoading());
    try {
      if (invoice.id != null) {
        await _dao.update(invoice, items: items);
        emit(const ProformaInvoiceOperationSuccess('تم تحديث الفاتورة بنجاح'));
      } else {
        await _dao.insert(invoice, items: items);
        emit(const ProformaInvoiceOperationSuccess('تم إنشاء الفاتورة بنجاح'));
      }
    } catch (e, stack) {
      emit(ProformaInvoiceError(e.toString()));
    }
  }

  Future<void> delete(dynamic id) async {
    try {
      await _dao.delete(id);
      emit(const ProformaInvoiceOperationSuccess('تم حذف الفاتورة بنجاح'));
    } catch (e, stack) {
      emit(ProformaInvoiceError(e.toString()));
    }
  }
}
