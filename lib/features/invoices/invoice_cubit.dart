import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/dao/invoice_dao.dart';
import '../../data/dao/customer_dao.dart';
import '../../data/dao/item_dao.dart';
import '../../data/models/invoice_model.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/item_model.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../core/data_change_event_bus.dart';
import '../../core/ui_utils.dart';
import 'invoice_state.dart';

class InvoiceCubit extends Cubit<InvoiceState> {
  final InvoiceDao _dao = InvoiceDao();
  final CustomerDao _customerDao = CustomerDao();
  final ItemDao _itemDao = ItemDao();
  final _client = Supabase.instance.client;
  final String type;

  int _offset = 0;
  static const _limit = 50;
  String _currentQuery = '';
  Timer? _debounce;

  // ── List state ─────────────────────────────
  List<InvoiceModel> _invoices = [];
  List<CustomerModel> _customers = [];
  List<ItemModel> _allItems = [];
  bool _hasMore = true;
  bool _isFetchingMore = false;
  DateTime? _fromDate;
  DateTime? _toDate;
  int _nextInvoiceNumber = 0;
  String _searchQuery = '';

  // ── Form state ─────────────────────────────
  CustomerModel? _selectedCustomer;
  DateTime _invoiceDate = DateTime.now();
  List<InvoiceLine> _invoiceLines = [];
  DiscountMode _discountMode = DiscountMode.none;
  bool _isSaving = false;

  // ── Controllers ────────────────────────────
  final formKey = GlobalKey<FormState>();
  final customerSearchController = TextEditingController();
  final paidController = TextEditingController(text: '0');
  final notesController = TextEditingController();
  final discountController = TextEditingController(text: '0');
  final FocusNode customerFocusNode = FocusNode();
  final FocusNode paidFocusNode = FocusNode();
  final FocusNode notesFocusNode = FocusNode();
  final FocusNode discountFocusNode = FocusNode();
  List<TextEditingController> quantityControllers = [];
  List<TextEditingController> priceControllers = [];

  // ── Subscriptions ──────────────────────────
  StreamSubscription? _itemsSubscription;
  StreamSubscription? _customersSubscription;

  bool get isReturn => type == 'return';

  // ── Public getters ─────────────────────────
  List<InvoiceModel> get invoices => _invoices;
  List<CustomerModel> get customers => _customers;
  List<ItemModel> get allItems => _allItems;
  bool get hasMore => _hasMore;
  bool get isFetchingMore => _isFetchingMore;
  DateTime? get fromDate => _fromDate;
  DateTime? get toDate => _toDate;
  int get nextInvoiceNumber => _nextInvoiceNumber;
  String get searchQuery => _searchQuery;
  CustomerModel? get selectedCustomer => _selectedCustomer;
  DateTime get invoiceDate => _invoiceDate;
  List<InvoiceLine> get invoiceLines => _invoiceLines;
  DiscountMode get discountMode => _discountMode;
  bool get isSaving => _isSaving;

  void setSelectedCustomer(CustomerModel? customer) {
    _selectedCustomer = customer;
    emit(_formState());
  }

  // ── Computed totals ────────────────────────
  double get subtotal =>
      AppUtils.roundDouble(_invoiceLines.fold(0.0, (s, l) => s + l.totalPrice));

  double get discountAmount {
    final raw = double.tryParse(discountController.text) ?? 0.0;
    switch (_discountMode) {
      case DiscountMode.fixed:
        return raw.clamp(0.0, subtotal);
      case DiscountMode.percentage:
        return (subtotal * raw / 100).clamp(0.0, subtotal);
      case DiscountMode.none:
        return 0;
    }
  }

  double get netTotal => AppUtils.roundDouble(subtotal - discountAmount);
  double get paidAmount =>
      AppUtils.roundDouble(double.tryParse(paidController.text) ?? 0.0);
  double get remainingAmount => AppUtils.roundDouble(netTotal - paidAmount);
  double get totalMeters => _invoiceLines
      .where((l) => l.unit == 'متر')
      .fold(0.0, (s, l) => s + l.quantity);

  String get discountHint {
    switch (_discountMode) {
      case DiscountMode.fixed:
        return 'مبلغ الخصم (ج.م)';
      case DiscountMode.percentage:
        return 'نسبة الخصم (%)';
      case DiscountMode.none:
        return 'بدون خصم';
    }
  }

  // ── Constructor ────────────────────────────
  InvoiceCubit({this.type = 'sale'}) : super(InvoiceInitial()) {
    _itemsSubscription = DataChangeEventBus.instance.itemsStream.listen((_) {
      _itemDao.getAll(limit: 2000, offset: 0).then((val) {
        _allItems = val;
      });
    });
    _customersSubscription =
        DataChangeEventBus.instance.customersStream.listen((_) {
      _customerDao.getAll(limit: 2000, offset: 0).then((val) {
        _customers = val;
      });
    });

    customerFocusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.enter) {
        final q = customerSearchController.text.toLowerCase();
        final matches = _customers
            .where((cu) =>
                cu.name.toLowerCase().contains(q))
            .toList();
        if (matches.isNotEmpty) {
          _selectedCustomer = matches.first;
          customerSearchController.text =
              matches.first.name;
          emit(_formState());
          if (_invoiceLines.isNotEmpty) {
            _invoiceLines.first.itemFocus.requestFocus();
          }
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    };
  }

  @override
  void onChange(Change<InvoiceState> change) {
    super.onChange(change);
    debugPrint('[InvoiceCubit] $change');
  }

  @override
  Future<void> close() {
    _itemsSubscription?.cancel();
    _customersSubscription?.cancel();
    _debounce?.cancel();
    paidController.dispose();
    notesController.dispose();
    discountController.dispose();
    customerSearchController.dispose();
    customerFocusNode.dispose();
    paidFocusNode.dispose();
    notesFocusNode.dispose();
    discountFocusNode.dispose();
    for (final l in _invoiceLines) {
      l.dispose();
    }
    return super.close();
  }

  // ── State helpers ──────────────────────────
  InvoiceLoaded _loadedState() => InvoiceLoaded(
        invoices: List<InvoiceModel>.from(_invoices),
        customers: List<CustomerModel>.from(_customers),
        allItems: List<ItemModel>.from(_allItems),
        searchQuery: _searchQuery,
        hasMore: _hasMore,
        isFetchingMore: _isFetchingMore,
        fromDate: _fromDate,
        toDate: _toDate,
        nextInvoiceNumber: _nextInvoiceNumber,
      );

  InvoiceFormState _formState() => InvoiceFormState(
        selectedCustomer: _selectedCustomer,
        invoiceDate: _invoiceDate,
        invoiceLines: List<InvoiceLine>.from(_invoiceLines),
        discountMode: _discountMode,
        isSaving: _isSaving,
      );

  // ── Init ───────────────────────────────────
  Future<void> init() async {
    emit(const InvoiceLoading());
    await loadAll(reset: true);
    await loadFormData();
  }

  Future<void> loadFormData() async {
    _customers = await _customerDao.getAll(limit: 2000, offset: 0);
    _allItems = await _itemDao.getAll(limit: 2000, offset: 0);
    _nextInvoiceNumber = await _dao.getNextNumber();
  }

  // ── Load list ──────────────────────────────
  Future<void> loadAll({bool reset = false}) async {
    if (reset) {
      _offset = 0;
      _hasMore = true;
    }
    if (!_hasMore) return;

    try {
      final fromStr =
          _fromDate != null ? AppUtils.formatDateForDb(_fromDate!) : null;
      final toStr =
          _toDate != null ? AppUtils.formatDateForDb(_toDate!) : null;
      final newItems = await _dao.getAll(
        type: type,
        limit: _limit,
        offset: _offset,
        fromDate: fromStr,
        toDate: toStr,
      );
      if (newItems.length < _limit) {
        _hasMore = false;
      }
      if (reset) {
        _invoices = newItems;
      } else {
        _invoices = [..._invoices, ...newItems];
      }
      _offset += _limit;
      emit(_loadedState());
    } catch (e) {
      emit(InvoiceError('خطأ: $e'));
    }
  }

  Future<void> _runSearch({bool reset = false}) async {
    final q = _searchQuery.trim();
    if (q.isEmpty) {
      await loadAll(reset: reset);
      return;
    }
    if (reset) {
      _offset = 0;
      _hasMore = true;
    }
    if (!_hasMore) return;
    try {
      final fromStr =
          _fromDate != null ? AppUtils.formatDateForDb(_fromDate!) : null;
      final toStr =
          _toDate != null ? AppUtils.formatDateForDb(_toDate!) : null;
      final results = await _dao.search(
        q,
        type: type,
        fromDate: fromStr,
        toDate: toStr,
        limit: _limit,
        offset: _offset,
      );
      if (results.length < _limit) _hasMore = false;
      if (reset) {
        _invoices = results;
      } else {
        _invoices = [..._invoices, ...results];
      }
      _offset += _limit;
      emit(_loadedState());
    } catch (e) {
      emit(InvoiceError('خطأ: $e'));
    }
  }

  // ── Search ─────────────────────────────────
  void onSearchChanged(String q) {
    _searchQuery = q;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(reset: true);
    });
  }

  // ── Date filtering ─────────────────────────
  Future<void> pickFromDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      _fromDate = picked;
      await loadAll(reset: true);
    }
  }

  Future<void> pickToDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      _toDate = picked;
      await loadAll(reset: true);
    }
  }

  void clearDateFilter() {
    _fromDate = null;
    _toDate = null;
    loadAll(reset: true);
  }

  // ── Fetch more ─────────────────────────────
  Future<void> fetchMore() async {
    if (_isFetchingMore || !_hasMore) return;
    _isFetchingMore = true;
    if (_searchQuery.trim().isEmpty) {
      await loadAll();
    } else {
      await _runSearch();
    }
    _isFetchingMore = false;
  }

  // ── Prepare new invoice ────────────────────
  Future<void> prepareNewInvoice() async {
    _selectedCustomer = null;
    _invoiceDate = DateTime.now();
    for (final l in _invoiceLines) {
      l.dispose();
    }
    _invoiceLines.clear();
    quantityControllers.clear();
    priceControllers.clear();
    paidController.text = '0';
    notesController.text = '';
    discountController.text = '0';
    _discountMode = DiscountMode.none;

    await loadFormData();
    _nextInvoiceNumber = await _dao.getNextNumber();
    emit(_formState());
  }

  Future<void> prepareNewForm() async {
    await prepareNewInvoice();
    _customers = await _customerDao.getAll(limit: 2000, offset: 0);
    _allItems = await _itemDao.getAll(limit: 2000, offset: 0);
    addNewLine();
  }

  // ── Line management ────────────────────────
  void addNewLine() {
    final line = InvoiceLine();
    _setupLineKeyEvents(line, _invoiceLines.length);
    _invoiceLines.add(line);
    quantityControllers.add(line.quantityController);
    priceControllers.add(line.priceController);
    emit(_formState());
  }

  void removeLine(int index) {
    if (_invoiceLines.length > 1) {
      final line = _invoiceLines.removeAt(index);
      quantityControllers.removeAt(index);
      priceControllers.removeAt(index);
      emit(_formState());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        line.dispose();
      });
    }
  }

  void onItemSelected(int idx, ItemModel item) {
    final line = _invoiceLines[idx];
    line.selectedItem = item;
    line.unit = item.unit;
    line.unitPrice = item.pricePerUnit;
    line.priceController.text = item.pricePerUnit.toStringAsFixed(2);
    line.itemSearchController.text = '${item.code} - ${item.name}';
    _recalcLine(idx);
    emit(_formState());
  }

  void onQuantityChanged(int idx, String v) {
    _invoiceLines[idx].quantity = double.tryParse(v) ?? 0.0;
    _recalcLine(idx);
    emit(_formState());
  }

  void onPriceChanged(int idx, String v) {
    _invoiceLines[idx].unitPrice = double.tryParse(v) ?? 0.0;
    _recalcLine(idx);
    emit(_formState());
  }

  void _recalcLine(int idx) {
    final l = _invoiceLines[idx];
    l.totalPrice = AppUtils.roundDouble(l.quantity * l.unitPrice);
  }

  void refreshTotals() => emit(_formState());

  // ── Discount ───────────────────────────────
  void setDiscountMode(DiscountMode mode) {
    _discountMode = mode;
    discountController.text = '0';
    emit(_formState());
  }

  // ── Build preview invoice (NOT saved) ──────
  InvoiceModel? buildPreviewInvoice() {
    final validLines = _invoiceLines
        .where((l) => l.selectedItem != null && l.quantity > 0)
        .toList();
    if (validLines.isEmpty || _selectedCustomer == null) return null;

    final items = validLines.map((l) {
      final pc = double.tryParse(l.piecesController.text) ?? 0.0;
      return InvoiceItemModel(
        invoiceId: '',
        itemId: l.selectedItem!.id,
        itemName: l.selectedItem!.name,
        itemCode: l.selectedItem!.code,
        quantity: l.quantity,
        unitPrice: l.unitPrice,
        totalPrice: l.totalPrice,
        unit: l.unit,
        piecesCount: pc,
      );
    }).toList();

    return InvoiceModel(
      invoiceNumber: _nextInvoiceNumber,
      invoiceDate: _fmtDate(_invoiceDate),
      customerId: _selectedCustomer!.id,
      customerName: _selectedCustomer!.name,
      totalAmount: subtotal,
      paidAmount: paidAmount,
      discountAmount: discountAmount,
      status: InvoiceStatus.confirmed,
      type: isReturn ? 'return' : 'sale',
      notes: notesController.text.trim().isEmpty
          ? null
          : notesController.text.trim(),
      createdAt: DateTime.now().toIso8601String(),
      items: items,
    );
  }

  // ── Save to DB ─────────────────────────────
  Future<bool> saveInvoice() async {
    if (_isSaving) return false;
    if (_selectedCustomer == null) {
      _err('يرجى اختيار العميل');
      return false;
    }
    final validLines = _invoiceLines
        .where((l) => l.selectedItem != null && l.quantity > 0)
        .toList();
    if (validLines.isEmpty) {
      _err('يرجى إضافة صنف واحد على الأقل');
      return false;
    }

    _isSaving = true;
    emit(_formState());

    final now = DateTime.now().toIso8601String();
    final items = validLines.map((l) {
      final pc = double.tryParse(l.piecesController.text) ?? 0.0;
      return InvoiceItemModel(
        invoiceId: '',
        itemId: l.selectedItem!.id,
        itemName: l.selectedItem!.name,
        itemCode: l.selectedItem!.code,
        quantity: l.quantity,
        unitPrice: l.unitPrice,
        totalPrice: l.totalPrice,
        unit: l.unit,
        piecesCount: pc,
      );
    }).toList();

    final invoice = InvoiceModel(
      invoiceNumber: _nextInvoiceNumber,
      invoiceDate: _fmtDate(_invoiceDate),
      customerId: _selectedCustomer!.id,
      customerName: _selectedCustomer!.name,
      totalAmount: subtotal,
      paidAmount: paidAmount,
      discountAmount: discountAmount,
      status: InvoiceStatus.confirmed,
      type: isReturn ? 'return' : 'sale',
      notes: notesController.text.trim().isEmpty
          ? null
          : notesController.text.trim(),
      createdAt: now,
      items: items,
    );

    try {
      // Use the DAO's RPC-based method which handles the full transaction
      final invoiceId = await _dao.insertWithItems(invoice);

      if (!isReturn) {
        final itemsJson = items.map((item) {
          return {
            'product_id': item.itemId!,
            'quantity': item.quantity,
          };
        }).toList();
        final result = await _client.rpc('deduct_fifo', params: {
          'p_items': itemsJson,
        });
        final data = Map<String, dynamic>.from(result as Map);
        debugPrint('🧾 FIFO RPC result: success=${data['success']}, total_cogs=${data['total_cogs']}');
      }

      await loadAll(reset: true);
      await loadFormData();
      _nextInvoiceNumber = await _dao.getNextNumber();

      DataChangeEventBus.instance.notifyItemsChanged();
      DataChangeEventBus.instance.notifyCustomersChanged();
      DataChangeEventBus.instance.notifyAccountsChanged();

      _ok('تم حفظ الفاتورة رقم ${invoice.invoiceNumber} بنجاح');
      _isSaving = false;
      emit(_formState());
      return true;
    } catch (e) {
      _err('حدث خطأ أثناء الحفظ: $e');
      _isSaving = false;
      emit(_formState());
      return false;
    }
  }

  // ── Delete invoice ─────────────────────────
  Future<void> deleteInvoice(InvoiceModel invoice) async {
    try {
      // Use the DAO's RPC-based method which handles the full transaction
      await _dao.delete(invoice.id!);

      await loadAll(reset: true);

      DataChangeEventBus.instance.notifyItemsChanged();
      DataChangeEventBus.instance.notifyCustomersChanged();
      DataChangeEventBus.instance.notifySuppliersChanged();

      _ok('تم حذف الفاتورة');
    } catch (e) {
      _err('خطأ: $e');
    }
  }

  // ── Get invoice with items ─────────────────
  Future<InvoiceModel?> getInvoiceWithItems(int id) => _dao.getById(id.toString());

  // ── Pick invoice date ──────────────────────
  Future<void> pickDate(BuildContext context) async {
    final p = await showDatePicker(
      context: context,
      initialDate: _invoiceDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (p != null) {
      _invoiceDate = p;
      emit(_formState());
    }
  }

  // ── Key event setup (mirrors InvoiceLine.setupKeyEvents) ──
  void _setupLineKeyEvents(InvoiceLine line, int index) {
    line.itemFocus.onKeyEvent = (node, event) {
      if (event is KeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          final q = line.itemSearchController.text.trim().toLowerCase();
          final matches = _allItems
              .where((it) =>
                  it.name.toLowerCase().contains(q) ||
                  it.code.toLowerCase().contains(q))
              .toList();
          if (matches.isNotEmpty) {
            onItemSelected(index, matches.first);
          }
          Future.microtask(() => line.piecesFocus.requestFocus());
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          if (index < _invoiceLines.length - 1) {
            Future.microtask(
                () => _invoiceLines[index + 1].itemFocus.requestFocus());
          } else {
            addNewLine();
            Future.delayed(const Duration(milliseconds: 50), () {
              _invoiceLines.last.itemFocus.requestFocus();
            });
          }
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    };

    line.piecesFocus.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.enter) {
        Future.microtask(() => line.quantityFocus.requestFocus());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    line.quantityFocus.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.enter) {
        Future.microtask(() => line.priceFocus.requestFocus());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };

    line.priceFocus.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.enter) {
        if (index < _invoiceLines.length - 1) {
          Future.microtask(
              () => _invoiceLines[index + 1].itemFocus.requestFocus());
        } else {
          addNewLine();
          Future.delayed(const Duration(milliseconds: 50), () {
            _invoiceLines.last.itemFocus.requestFocus();
          });
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  // ── Helpers ────────────────────────────────
  String _fmtDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  // ── Callbacks for page feedback ────────────
  void Function(String msg)? onOk;
  void Function(String msg)? onErr;

  void _ok(String msg) => onOk?.call(msg);
  void _err(String msg) => onErr?.call(msg);
}
