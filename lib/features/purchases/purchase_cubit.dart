import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/dao/purchase_dao.dart';
import '../../data/dao/supplier_dao.dart';
import '../../data/dao/item_dao.dart';
import '../../data/dao/raw_material_dao.dart';
import '../../data/dao/station_dao.dart';
import '../../data/dao/station_product_dao.dart';
import '../../data/dao/station_product_batch_dao.dart';
import '../../data/services/inventory_service.dart';
import '../../data/services/currency_conversion_service.dart';
import '../../data/models/purchase_model.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/item_model.dart';
import '../../data/models/raw_material_model.dart';
import '../../data/models/station_model.dart';
import '../../core/utils.dart';
import '../../core/data_change_event_bus.dart';
import 'purchase_state.dart';

// ignore_for_file: unnecessary_getters_setters

class PurchaseCubit extends Cubit<PurchaseState> {
  final PurchaseDao _dao = PurchaseDao();
  final SupplierDao _supplierDao = SupplierDao();
  final ItemDao _itemDao = ItemDao();
  final RawMaterialDao _rawMaterialDao = RawMaterialDao();
  final StationDao _stationDao = StationDao();
  final StationProductDao _stationProductDao = StationProductDao();
  final StationProductBatchDao _stationProductBatchDao = StationProductBatchDao();
  final InventoryService _inventoryService = InventoryService();
  final _client = Supabase.instance.client;

  List<Map<String, dynamic>> treasuries = [];
  List<Map<String, dynamic>> bankAccounts = [];

  int _offset = 0;
  static const int _limit = 50;
  String _currentQuery = '';
  Timer? _debounce;

  late PurchaseFormState _formState;
  PurchaseFormState get formState => _formState;
  set formState(PurchaseFormState value) => _formState = value;

  void _safeEmit(PurchaseState newState) {
    if (!isClosed) emit(newState);
  }

  late final StreamSubscription<void> _itemsSub;
  late final StreamSubscription<void> _purchasesSub;
  late final StreamSubscription<void> _suppliersSub;
  late final StreamSubscription<void> _stationsSub;

  PurchaseCubit() : super(const PurchaseInitial()) {
    _formState = PurchaseFormState(
      purchaseDate: DateTime.now(),
      purchaseLines: const [],
      nextPurchaseNumber: '1',
      subtotal: 0.0,
      isSaving: false,
    );
    _itemsSub =
        DataChangeEventBus.instance.itemsStream.listen((_) => _loadItems());
    _purchasesSub = DataChangeEventBus.instance.purchasesStream
        .listen((_) => loadAll(reset: true));
    _suppliersSub = DataChangeEventBus.instance.suppliersStream
        .listen((_) => _loadSuppliers());
    _stationsSub = DataChangeEventBus.instance.stationsStream
        .listen((_) => _loadStations());
  }

  // ── Initialization ──

  Future<void> init() async {
    await Future.wait([
      loadAll(reset: true),
      _loadSuppliers(),
      _loadItems(),
      _loadStations(),
      _loadNextNumber(),
      _loadTreasuries(),
      _loadBankAccounts(),
    ]);
  }

  // ── Load data ──

  // Cache reference data so it survives PurchaseFormSaved state resets
  List<SupplierModel> _cachedSuppliers = const [];
  List<ItemModel> _cachedItems = const [];
  List<StationModel> _cachedStations = const [];
  List<RawMaterialModel> _cachedRawMaterials = const [];

  Future<void> loadAll({bool reset = false}) async {
    // Read filter values from current state BEFORE emitting PurchaseLoading,
    // otherwise state becomes PurchaseLoading and the values are lost.
    final prevState = state;
    final fromDate = prevState is PurchaseLoaded ? prevState.fromDate : null;
    final toDate = prevState is PurchaseLoaded ? prevState.toDate : null;
    final selectedProductId =
        prevState is PurchaseLoaded ? prevState.selectedProductId : null;
    var prevSuppliers =
        prevState is PurchaseLoaded ? prevState.suppliers : _cachedSuppliers;
    var prevItems =
        prevState is PurchaseLoaded ? prevState.allItems : _cachedItems;
    var prevStations =
        prevState is PurchaseLoaded ? prevState.stations : _cachedStations;
    var prevRawMaterials =
        prevState is PurchaseLoaded ? prevState.rawMaterials : _cachedRawMaterials;

    if (reset) {
      _offset = 0;
      _currentQuery = '';
      _safeEmit(const PurchaseLoading());
    }

    final currentState = state;
    if (currentState is PurchaseLoaded && !currentState.hasMore && !reset) {
      return;
    }

    try {
      final fromStr =
          fromDate != null ? AppUtils.formatDateForDb(fromDate) : null;
      final toStr = toDate != null ? AppUtils.formatDateForDb(toDate) : null;

      debugPrint(
          '📌 loadAll: offset=$_offset limit=$_limit fromDate=$fromStr toDate=$toStr productId=$selectedProductId reset=$reset');
      final purchasesFuture = _dao.getAll(
        limit: _limit,
        offset: _offset,
        fromDate: fromStr,
        toDate: toStr,
        productId: selectedProductId,
      );

      // If reference data is empty (e.g. after PurchaseFormSaved), reload in parallel
      final refFutures = <Future>[];
      if (reset && prevSuppliers.isEmpty) refFutures.add(_supplierDao.getAll(limit: 2000, offset: 0).then((s) => prevSuppliers = s));
      if (reset && prevItems.isEmpty) refFutures.add(_reloadItemsCache().then((items) => prevItems = items));
      if (reset && prevStations.isEmpty) refFutures.add(_stationDao.getAll(limit: 100).then((s) => prevStations = s));

      final results = await Future.wait([purchasesFuture, ...refFutures]);
      final newItems = results[0] as List<PurchaseModel>;

      debugPrint('📌 loadAll: got ${newItems.length} items');
      final hasMore = newItems.length >= _limit;
      _offset += _limit;

      // Cache reference data for future loadAll calls
      _cachedSuppliers = prevSuppliers;
      _cachedItems = prevItems;
      _cachedStations = prevStations;
      _cachedRawMaterials = prevRawMaterials;

      if (reset) {
        _safeEmit(PurchaseLoaded(
          purchases: newItems,
          suppliers: prevSuppliers,
          allItems: prevItems,
          stations: prevStations,
          rawMaterials: prevRawMaterials,
          hasMore: hasMore,
          fromDate: fromDate,
          toDate: toDate,
          selectedProductId: selectedProductId,
        ));
      } else if (currentState is PurchaseLoaded) {
        _safeEmit(currentState.copyWith(
          purchases: [...currentState.purchases, ...newItems],
          hasMore: hasMore,
          isFetchingMore: false,
        ));
      }
    } catch (e) {
      _safeEmit(PurchaseError(message: 'حدث خطأ أثناء تحميل البيانات: $e'));
    } finally {
      final s = state;
      if (s is PurchaseLoaded && (s.isFetchingMore)) {
        _safeEmit(s.copyWith(isFetchingMore: false));
      }
    }
  }

  Future<List<ItemModel>> _reloadItemsCache() async {
    final results = await Future.wait([
      _itemDao.getAll(limit: 2000, offset: 0),
      _rawMaterialDao.getAll(),
    ]);
    final items = results[0] as List<ItemModel>;
    final rawMaterials = results[1] as List<RawMaterialModel>;
    final rawAsItems = rawMaterials.map((rm) => ItemModel(
      id: rm.id?.toString(),
      code: rm.code,
      name: rm.name,
      type: 'raw_material',
      pricePerUnit: rm.defaultPurchasePrice,
      costPrice: rm.defaultPurchasePrice,
      unit: rm.unit,
      stockQuantity: rm.quantity,
      currency: rm.currency,
      createdAt: rm.createdAt?.toIso8601String() ?? '',
    )).toList();
    return [...items, ...rawAsItems];
  }

  // ── Search ──

  void onSearchChanged(String query) {
    _currentQuery = query.trim();
    _debounceSearch();
  }

  void _debounceSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _runSearch(reset: true);
    });
  }

  Future<void> _runSearch({bool reset = false}) async {
    if (reset) {
      _offset = 0;
    }

    final currentState = state;
    if (currentState is PurchaseLoaded && !currentState.hasMore && !reset) {
      return;
    }

    try {
      if (_currentQuery.isEmpty) {
        await loadAll(reset: reset);
        return;
      }

      final fromDate =
          currentState is PurchaseLoaded ? currentState.fromDate : null;
      final toDate =
          currentState is PurchaseLoaded ? currentState.toDate : null;
      final selectedProductId = currentState is PurchaseLoaded
          ? currentState.selectedProductId
          : null;
      final prevSuppliers = currentState is PurchaseLoaded
          ? currentState.suppliers
          : <SupplierModel>[];
      final prevItems = currentState is PurchaseLoaded
          ? currentState.allItems
          : <ItemModel>[];
      final fromStr =
          fromDate != null ? AppUtils.formatDateForDb(fromDate) : null;
      final toStr = toDate != null ? AppUtils.formatDateForDb(toDate) : null;

      debugPrint(
          '📌 _runSearch: query=$_currentQuery fromDate=$fromStr toDate=$toStr productId=$selectedProductId');
      final newItems = await _dao.search(
        _currentQuery,
        limit: _limit,
        offset: _offset,
        fromDate: fromStr,
        toDate: toStr,
        productId: selectedProductId,
      );
      final hasMore = newItems.length >= _limit;
      _offset += _limit;

      if (reset) {
        _safeEmit(PurchaseLoaded(
          purchases: newItems,
          suppliers: prevSuppliers,
          allItems: prevItems,
          searchQuery: _currentQuery,
          hasMore: hasMore,
          fromDate: fromDate,
          toDate: toDate,
          selectedProductId: selectedProductId,
        ));
      } else if (currentState is PurchaseLoaded) {
        _safeEmit(currentState.copyWith(
          purchases: [...currentState.purchases, ...newItems],
          searchQuery: _currentQuery,
          hasMore: hasMore,
          isFetchingMore: false,
        ));
      }
    } catch (e) {
      _safeEmit(PurchaseError(message: 'حدث خطأ أثناء البحث: $e'));
    } finally {
      final s = state;
      if (s is PurchaseLoaded && s.isFetchingMore) {
        _safeEmit(s.copyWith(isFetchingMore: false));
      }
    }
  }

  // ── Date filtering ──

  Future<void> pickFromDate(BuildContext context) async {
    final currentState = state;
    final fromDate =
        currentState is PurchaseLoaded ? currentState.fromDate : null;

    final picked = await showDatePicker(
      context: context,
      initialDate: fromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && currentState is PurchaseLoaded) {
      _safeEmit(currentState.copyWith(fromDate: picked));
      await loadAll(reset: true);
    }
  }

  Future<void> pickToDate(BuildContext context) async {
    final currentState = state;
    final toDate = currentState is PurchaseLoaded ? currentState.toDate : null;

    final picked = await showDatePicker(
      context: context,
      initialDate: toDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && currentState is PurchaseLoaded) {
      _safeEmit(currentState.copyWith(toDate: picked));
      await loadAll(reset: true);
    }
  }

  void onProductFilterChanged(String? productId) {
    final currentState = state;
    if (currentState is PurchaseLoaded) {
      _safeEmit(currentState.copyWith(selectedProductId: productId));
      loadAll(reset: true);
    }
  }

  void clearFilters() {
    final currentState = state;
    if (currentState is PurchaseLoaded) {
      _safeEmit(currentState.copyWith(
        clearFromDate: true,
        clearToDate: true,
        clearProductId: true,
      ));
      loadAll(reset: true);
    }
  }

  // ── Infinite scroll ──

  Future<void> fetchMore() async {
    final currentState = state;
    if (currentState is! PurchaseLoaded) return;
    if (currentState.isFetchingMore || !currentState.hasMore) return;

    _safeEmit(currentState.copyWith(isFetchingMore: true));

    if (_currentQuery.isEmpty) {
      await loadAll();
    } else {
      await _runSearch();
    }
  }

  // ── Load suppliers ──

  Future<void> _loadSuppliers() async {
    final suppliers = await _supplierDao.getAll(limit: 2000, offset: 0);
    _cachedSuppliers = suppliers;
    final currentState = state;
    if (currentState is PurchaseLoaded) {
      _safeEmit(currentState.copyWith(suppliers: suppliers));
    } else {
      _safeEmit(PurchaseLoaded(
        purchases: const [],
        suppliers: suppliers,
        allItems: const [],
      ));
    }
  }

  // ── Load items ──

  Future<void> _loadItems() async {
    final results = await Future.wait([
      _itemDao.getAll(limit: 2000, offset: 0),
      _rawMaterialDao.getAll(),
    ]);
    final items = results[0] as List<ItemModel>;
    final rawMaterials = results[1] as List<RawMaterialModel>;
    final rawAsItems = rawMaterials.map((rm) => ItemModel(
      id: rm.id?.toString(),
      code: rm.code,
      name: rm.name,
      type: 'raw_material',
      pricePerUnit: rm.defaultPurchasePrice,
      costPrice: rm.defaultPurchasePrice,
      unit: rm.unit,
      stockQuantity: rm.quantity,
      currency: rm.currency,
      createdAt: rm.createdAt?.toIso8601String() ?? '',
    )).toList();
    final allItems = [...items, ...rawAsItems];
    _cachedItems = allItems;
    _cachedRawMaterials = rawMaterials;
    final currentState = state;
    if (currentState is PurchaseLoaded) {
      _safeEmit(currentState.copyWith(allItems: allItems, rawMaterials: rawMaterials));
    } else {
      _safeEmit(PurchaseLoaded(
        purchases: const [],
        suppliers:
            currentState is PurchaseLoaded ? currentState.suppliers : const [],
        allItems: allItems,
        rawMaterials: rawMaterials,
      ));
    }
  }

  Future<void> _loadStations() async {
    try {
      final stations = await _stationDao.getAll(limit: 100);
      _cachedStations = stations;
      final currentState = state;
      if (currentState is PurchaseLoaded) {
        _safeEmit(currentState.copyWith(stations: stations));
      } else {
        _safeEmit(PurchaseLoaded(
          purchases: const [],
          suppliers: const [],
          allItems: const [],
          stations: stations,
        ));
      }
    } catch (e) {
      debugPrint('⚠️ purchase_cubit: Failed to load initial data: $e');
    }
  }

  Future<void> _loadTreasuries() async {
    try {
      final data = await _client
          .from('treasuries')
          .select('id, name, type, treasury_balances(currency, balance)')
          .order('name');
      final allTreasuries = List<Map<String, dynamic>>.from(data);
      treasuries = allTreasuries.where((t) => t['type'] != 'employee').toList();
    } catch (e) {
      debugPrint('⚠️ purchase_cubit: Failed to load treasuries: $e');
      // fallback without balances
      try {
        final data = await _client.from('treasuries').select('id, name, type').order('name');
        final allTreasuries = List<Map<String, dynamic>>.from(data);
        treasuries = allTreasuries.where((t) => t['type'] != 'employee').toList();
      } catch (_) {
        treasuries = [];
      }
    }
  }

  Future<void> _loadBankAccounts() async {
    try {
      final data = await _client.from('bank_accounts').select('id, name, currency, balance').order('name');
      bankAccounts = List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('⚠️ purchase_cubit: Failed to load bank accounts: $e');
      bankAccounts = [];
    }
  }

  // ── Load next purchase number ──

  Future<void> _loadNextNumber() async {
    final nextNum = await _dao.getNextNumber();
    _formState = _formState.copyWith(nextPurchaseNumber: nextNum);
  }

  // ── Form: Select supplier ──

  void selectSupplier(SupplierModel supplier) {
    _formState = _formState.copyWith(selectedSupplier: supplier);
  }

  // ── Build preview purchase ──

  PurchaseModel? buildPreviewPurchase(List<PurchaseLineData> lines) {
    final validLines = lines
        .where(
            (l) => l.quantity > 0 && l.purchasePrice > 0 && l.code.isNotEmpty)
        .toList();
    if (validLines.isEmpty || _formState.selectedSupplier == null) return null;

    final total = AppUtils.roundDouble(
      validLines.fold(0.0, (sum, l) => sum + l.totalPrice),
    );
    final items = validLines
        .map((l) => PurchaseItemModel(
              purchaseId: '',
              itemId: l.existingItemId,
              itemCode: l.code,
              itemName: l.name.isEmpty ? l.code : l.name,
              quantity: l.quantity,
              purchasePrice: l.purchasePrice,
              sellingPrice: 0,
              totalPrice: l.totalPrice,
              unit: l.unit,
              exchangeRate: l.exchangeRate,
            ))
        .toList();

    return PurchaseModel(
      purchaseNumber: _formState.nextPurchaseNumber,
      purchaseDate: AppUtils.formatDateForDb(_formState.purchaseDate),
      supplierId: _formState.selectedSupplier!.id,
      supplierName: _formState.selectedSupplier!.name,
      totalAmount: total,
      paidAmount: 0.0,
      status: 'confirmed',
      currency: _formState.selectedSupplier!.currency,
      createdAt: DateTime.now().toIso8601String(),
      items: items,
    );
  }

  // ── Save purchase ──

  Future<bool> savePurchase({
    required List<PurchaseLineData> lines,
    required double paidAmount,
    String? notes,
    String? paymentTreasuryId,
    String? paymentSourceType,
    int? paymentBankAccountId,
  }) async {
    if (_formState.isSaving) return false;
    if (_formState.selectedSupplier == null) return false;

    final validLines =
        lines.where((l) => l.quantity > 0 && l.code.isNotEmpty).toList();
    if (validLines.isEmpty) {
      debugPrint('❌ savePurchase: validLines is EMPTY — no items to save');
      return false;
    }
    debugPrint('📌 validLines count = ${validLines.length}');
    for (int i = 0; i < validLines.length; i++) {
      final l = validLines[i];
      debugPrint(
          '📌 Line $i: code="${l.code}" qty=${l.quantity} price=${l.purchasePrice} total=${l.totalPrice}');
    }

    _formState = _formState.copyWith(isSaving: true);

    // Fetch fresh invoice number right before saving
    await _loadNextNumber();

    final now = DateTime.now().toIso8601String();

    final tempItems = validLines
        .map((l) => PurchaseItemModel(
              purchaseId: '',
              itemId: l.existingItemId,
              itemCode: l.code,
              itemName: l.name.isEmpty ? l.code : l.name,
              piecesCount: 1.0,
              quantity: l.quantity,
              purchasePrice: l.purchasePrice,
              sellingPrice: 0,
              totalPrice: l.totalPrice,
              unit: l.unit,
            ))
        .toList();

    final netTotal = AppUtils.roundDouble(
      validLines.fold(0.0, (sum, l) => sum + l.totalPrice),
    );

    final purchase = PurchaseModel(
      purchaseNumber: _formState.nextPurchaseNumber,
      purchaseDate: AppUtils.formatDateForDb(_formState.purchaseDate),
      supplierId: _formState.selectedSupplier!.id,
      supplierName: _formState.selectedSupplier!.name,
      totalAmount: netTotal,
      paidAmount: paidAmount,
      status: 'confirmed',
      notes: (notes != null && notes.trim().isEmpty) ? null : notes?.trim(),
      createdAt: now,
      items: tempItems,
    );

    try {
      final selectedSupplier = _formState.selectedSupplier!;

      final String? supplierId = selectedSupplier.id?.toString();
      debugPrint('🟢 savePurchase: supplierId = $supplierId');

      if (supplierId == null || supplierId.isEmpty) {
        throw Exception('Supplier UUID is missing');
      }

      debugPrint('🔵 auth.userId = ${_client.auth.currentUser?.id}');

      final purchaseDataMap = {
        'invoice_number': purchase.purchaseNumber,
        'invoice_date': purchase.purchaseDate,
        'supplier_id': supplierId,
        'total_amount': purchase.totalAmount,
        'paid_amount': purchase.paidAmount,
        'discount_amount': purchase.discountAmount,
        'remaining_amount': purchase.totalAmount - purchase.paidAmount,
        'payment_status': purchase.paidAmount >= purchase.totalAmount
            ? 'paid'
            : purchase.paidAmount > 0
                ? 'partial'
                : 'unpaid',
        'status': 'draft',
        'notes': purchase.notes,
        'currency': selectedSupplier.currency,
        'user_id': _client.auth.currentUser?.id,
        'payment_treasury_id': paymentTreasuryId,
        'payment_source_type': paymentSourceType ?? 'treasury',
        'payment_bank_account_id': paymentBankAccountId,
        'currency_snapshot': CurrencyConversionService.instance.createSnapshot(
          currency: selectedSupplier.currency,
          amount: purchase.totalAmount,
          exchangeRate: validLines.isNotEmpty ? validLines.first.exchangeRate : 1.0,
          createdBy: _client.auth.currentUser?.id,
        ).toJson(),
      };

      debugPrint('📦 PURCHASE PAYLOAD: ${jsonEncode(purchaseDataMap)}');
      debugPrint('📌 Attempting purchase_invoices insert...');

      final purchaseData = await _client
          .from('purchase_invoices')
          .insert(purchaseDataMap)
          .select('id')
          .single();

      final int purchaseId = (purchaseData['id'] as num).toInt();
      debugPrint('✅ Invoice inserted successfully, id = $purchaseId');

      final purchaseItemMaps = <Map<String, dynamic>>[];

      for (final l in validLines) {
        final code = l.code;
        final stationIdInt = int.tryParse(l.stationId ?? '');

        final snapshot = CurrencyConversionService.instance.createSnapshot(
          currency: selectedSupplier.currency,
          amount: l.totalPrice,
          exchangeRate: l.exchangeRate,
          createdBy: _client.auth.currentUser?.id,
        ).toJson();
        if (stationIdInt != null) {
          snapshot['station_id'] = stationIdInt;
        }

        purchaseItemMaps.add({
          'invoice_id': purchaseId.toString(),
          'raw_material_id': l.existingItemId ?? code,
          'quantity': l.quantity.toInt(),
          'remaining_quantity': l.quantity.toInt(),
          'unit_cost': l.purchasePrice,
          'total_cost': l.totalPrice,
          'exchange_rate': l.exchangeRate,
          'station_id': stationIdInt,
          'currency_snapshot': snapshot,
        });
      }

      if (purchaseItemMaps.isNotEmpty) {
        try {
          await _client.from('purchase_invoice_items').insert(purchaseItemMaps);
        } catch (e) {
          debugPrint('⚠️ insert with station_id failed, retrying without: $e');
          final noStationMaps = purchaseItemMaps.map((m) => {
            ...m,
          }).toList();
          for (final m in noStationMaps) { m.remove('station_id'); }
          try {
            await _client.from('purchase_invoice_items').insert(noStationMaps);
          } catch (e2) {
            debugPrint('⚠️ insert without station_id also failed, retrying without raw_material_id: $e2');
            final fallbackMaps = noStationMaps.map((m) => {
              ...m,
              'raw_material_id': null,
            }).toList();
            await _client.from('purchase_invoice_items').insert(fallbackMaps);
          }
        }
      }

      // Try to persist station_id (column may not exist yet — migration 262)
      if (purchaseItemMaps.isNotEmpty) {
        try {
          final rows = await _client
              .from('purchase_invoice_items')
              .select('id')
              .eq('invoice_id', purchaseId.toString());
          for (int i = 0; i < rows.length && i < validLines.length; i++) {
            final stationId = validLines[i].stationId;
            if (stationId != null) {
              try {
                await _client.from('purchase_invoice_items')
                    .update({'station_id': int.tryParse(stationId)})
                    .eq('id', rows[i]['id']);
              } catch (e) {
                debugPrint('⚠️ purchase_cubit: Failed to update station_id on item: $e');
              }
            }
          }
        } catch (e) {
          debugPrint('⚠️ purchase_cubit: Failed to query purchase items for station_id update: $e');
        }
      }

      // ══════════════════════════════════════════════════════════════
      // Payment is NOT processed here. It is deferred to the confirm
      // step (rpc_confirm_purchase) when the user clicks the checkmark.
      // payment_processed stays false so confirm handles treasury/bank.
      // ══════════════════════════════════════════════════════════════

      _safeEmit(const PurchaseFormSaved());
      _formState = PurchaseFormState(
        purchaseDate: DateTime.now(),
        purchaseLines: const [],
        nextPurchaseNumber: _formState.nextPurchaseNumber,
        subtotal: 0.0,
        isSaving: false,
      );

      DataChangeEventBus.instance.notifyItemsChanged();
      DataChangeEventBus.instance.notifySuppliersChanged();
      DataChangeEventBus.instance.notifyPurchasesChanged();
      DataChangeEventBus.instance.notifyStationsChanged();

      await _loadNextNumber();

      // Reload list after form reset signal so list BlocBuilder sees PurchaseLoaded
      await loadAll(reset: true);

      return true;
    } catch (e, st) {
      debugPrint('🔴 PurchaseCubit.savePurchase error: $e');
      debugPrint('   stackTrace: $st');
      return false;
    } finally {
      _formState = _formState.copyWith(isSaving: false);
    }
  }

  // ── Delete purchase ──

  /// DEPRECATED: Use PurchaseDao.cancelPurchase() instead for safe reversal.
  /// This method does not reverse stock, balances, or journal entries.
  Future<void> deletePurchase(PurchaseModel p) async {
    try {
      await _client.rpc('rpc_delete_purchase', params: {
        'p_purchase_id': p.id!,
      });

      await loadAll(reset: true);
      DataChangeEventBus.instance.notifyItemsChanged();
      DataChangeEventBus.instance.notifySuppliersChanged();
      DataChangeEventBus.instance.notifyPurchasesChanged();
      DataChangeEventBus.instance.notifyStationsChanged();
    } catch (e) {
      rethrow;
    }
  }

  // ── Prepare new form ──

  Future<void> prepareNewForm() async {
    _formState = PurchaseFormState(
      purchaseDate: DateTime.now(),
      purchaseLines: const [],
      nextPurchaseNumber: _formState.nextPurchaseNumber,
      subtotal: 0.0,
      isSaving: false,
    );
    await Future.wait([
      _loadNextNumber(),
      _loadSuppliers(),
      _loadItems(),
      _loadStations(),
    ]);
  }

  // ── Check if purchase is consumed ──

  Future<bool> checkPurchaseConsumed(int purchaseId) async {
    try {
      final items = await _client
          .from('purchase_invoice_items')
          .select('id, raw_material_id, quantity')
          .eq('invoice_id', purchaseId.toString());

      final itemIds = <String>[];
      final productCodes = <String>[];

      for (final item in items) {
        final itemId = item['id']?.toString();
        if (itemId != null) itemIds.add(itemId);

        final productId = item['raw_material_id']?.toString();
        if (productId == null || productId.isEmpty) continue;

        final mat = await _client
            .from('raw_materials')
            .select('code')
            .eq('id', productId)
            .maybeSingle();
        final code = mat?['code']?.toString();
        if (code != null && code.isNotEmpty) productCodes.add(code);
      }

      if (productCodes.isNotEmpty) {
        final transfers = await _client
            .from('stock_transfers')
            .select('id')
            .inFilter('product_code', productCodes)
            .limit(1);
        if (transfers.isNotEmpty) return true;
      }

      if (itemIds.isNotEmpty) {
        final lots = await _client
            .from('lot_receipts')
            .select('id')
            .inFilter('purchase_invoice_item_id', itemIds);
        if (lots.isNotEmpty) {
          final lotIds = lots.map((l) => l['id'].toString()).toList();
          final packings = await _client
              .from('packing_orders')
              .select('id')
              .inFilter('lot_id', lotIds)
              .limit(1);
          if (packings.isNotEmpty) return true;
        }
      }

      return false;
    } catch (e) {
      debugPrint('⚠️ checkPurchaseConsumed error: $e');
      return false;
    }
  }

  // ── Prepare edit form ──

  Future<void> prepareEditForm(int purchaseId) async {
    try {
      debugPrint('📝 prepareEditForm: loading purchase $purchaseId');
      final purchase = await _dao.getById(purchaseId);
      if (purchase == null) {
        debugPrint('⚠️ prepareEditForm: purchase $purchaseId not found');
        return;
      }
      debugPrint('📝 prepareEditForm: purchase loaded, ${purchase.items.length} items');

      // Ensure suppliers + stations + items are loaded in cubit state for the form
      final currentState = state;
      final currentSuppliers = currentState is PurchaseLoaded ? currentState.suppliers : <SupplierModel>[];
      final currentItems = currentState is PurchaseLoaded ? currentState.allItems : <ItemModel>[];
      final currentStations = currentState is PurchaseLoaded ? currentState.stations : <StationModel>[];

      if (currentSuppliers.isEmpty || currentStations.isEmpty || currentItems.isEmpty) {
        final futures = <Future>[];
        List<SupplierModel> suppliers = currentSuppliers;
        List<StationModel> stations = currentStations;
        List<ItemModel> items = currentItems;
        if (currentSuppliers.isEmpty) futures.add(_supplierDao.getAll(limit: 2000, offset: 0).then((s) => suppliers = s));
        if (currentStations.isEmpty) futures.add(_stationDao.getAll(limit: 100).then((s) => stations = s));
        if (currentItems.isEmpty) futures.add(_reloadItemsCache().then((i) => items = i));
        await Future.wait(futures);

        _cachedSuppliers = suppliers;
        _cachedStations = stations;
        _cachedItems = items;

        if (currentState is PurchaseLoaded) {
          _safeEmit(currentState.copyWith(suppliers: suppliers, stations: stations, allItems: items));
        } else {
          _safeEmit(PurchaseLoaded(
            purchases: const [],
            suppliers: suppliers,
            allItems: items,
            stations: stations,
          ));
        }
      }

      _formState = PurchaseFormState(
        selectedSupplier: SupplierModel(
          id: purchase.supplierId?.toString(),
          supplierCode: purchase.supplierCode ?? '',
          name: purchase.supplierName ?? '',
          currency: purchase.currency,
        ),
        purchaseDate: DateTime.tryParse(purchase.purchaseDate ?? '') ?? DateTime.now(),
        purchaseLines: purchase.items.map((i) => PurchaseLineData(
          code: i.itemCode,
          name: i.itemName,
          quantity: i.quantity,
          purchasePrice: i.purchasePrice,
          unit: i.unit,
          existingItemId: i.itemId,
          stationId: i.stationId?.toString(),
          exchangeRate: i.exchangeRate,
        )).toList(),
        nextPurchaseNumber: purchase.purchaseNumber,
        subtotal: purchase.totalAmount,
        paidAmount: purchase.paidAmount,
        isSaving: false,
        editingPurchaseId: purchaseId,
        paymentTreasuryId: purchase.paymentTreasuryId,
        paymentSourceType: purchase.paymentSourceType,
        paymentBankAccountId: purchase.paymentBankAccountId,
      );
      debugPrint('📝 prepareEditForm: formState set with ${_formState.purchaseLines.length} lines');
    } catch (e, st) {
      debugPrint('⚠️ prepareEditForm error: $e');
      debugPrint('⚠️ prepareEditForm stackTrace: $st');
    }
  }

  // ── Update purchase ──

  Future<bool> updatePurchase({
    required int purchaseId,
    required List<PurchaseLineData> lines,
    required double paidAmount,
    String? notes,
    String? paymentTreasuryId,
    String? paymentSourceType,
    int? paymentBankAccountId,
  }) async {
    if (_formState.isSaving) return false;
    _formState = _formState.copyWith(isSaving: true);
    try {
      final validLines = lines.where((l) => l.quantity > 0 && l.code.isNotEmpty).toList();
      if (validLines.isEmpty) return false;

      // ═══════════════════════════════════════════════
      // Draft update: save data only, no stock changes
      // Stock changes happen on confirm via rpc_confirm_purchase
      // ═══════════════════════════════════════════════

      // Delete old items
      await _client.from('purchase_invoice_items').delete().eq('invoice_id', purchaseId);

      // Re-insert items
      final insertedIds = <int>[];
      final supplierCurrency = _formState.selectedSupplier?.currency ?? 'EGP';
      for (final l in validLines) {
        final stationIdInt = int.tryParse(l.stationId ?? '');
        final snapshot = CurrencyConversionService.instance.createSnapshot(
          currency: supplierCurrency,
          amount: l.totalPrice,
          exchangeRate: l.exchangeRate,
          createdBy: _client.auth.currentUser?.id,
        ).toJson();
        if (stationIdInt != null) {
          snapshot['station_id'] = stationIdInt;
        }
        final fullMap = {
          'invoice_id': purchaseId.toString(), 'raw_material_id': l.existingItemId ?? l.code,
          'quantity': l.quantity.toInt(), 'remaining_quantity': l.quantity,
          'unit_cost': l.purchasePrice, 'total_cost': l.totalPrice,
          'exchange_rate': l.exchangeRate,
          'station_id': stationIdInt,
          'currency_snapshot': snapshot,
        };
        bool ok = false;
        try {
          final row = await _client.from('purchase_invoice_items').insert(fullMap).select('id').single();
          insertedIds.add((row['id'] as num).toInt());
          ok = true;
        } catch (e) {
          debugPrint('⚠️ Insert with station_id failed, retrying without: $e');
        }
        if (!ok) {
          final noStationMap = Map<String, dynamic>.from(fullMap)..remove('station_id');
          try {
            final row = await _client.from('purchase_invoice_items').insert(noStationMap).select('id').single();
            insertedIds.add((row['id'] as num).toInt());
            ok = true;
          } catch (e) {
            debugPrint('⚠️ Insert without station_id failed, retrying without raw_material_id: $e');
          }
        }
        if (!ok) {
          final fallbackMap = {
            'invoice_id': purchaseId.toString(), 'raw_material_id': null,
            'quantity': l.quantity.toInt(), 'remaining_quantity': l.quantity,
            'unit_cost': l.purchasePrice, 'total_cost': l.totalPrice,
            'exchange_rate': l.exchangeRate,
            'currency_snapshot': snapshot,
          };
          final row = await _client.from('purchase_invoice_items').insert(fallbackMap).select('id').single();
          insertedIds.add((row['id'] as num).toInt());
        }
      }

      // Try to persist station_id via separate UPDATE if not saved in insert
      for (int i = 0; i < insertedIds.length && i < validLines.length; i++) {
        final stationId = validLines[i].stationId;
        if (stationId != null) {
          try {
            await _client.from('purchase_invoice_items')
                .update({'station_id': int.tryParse(stationId)})
                .eq('id', insertedIds[i]);
          } catch (_) {
            debugPrint('⚠️ Could not save station_id (column may not exist yet)');
          }
        }
      }

      // Update invoice header
      final totalAmount = AppUtils.roundDouble(validLines.fold(0.0, (s, l) => s + l.totalPrice));
      final paymentStatus = paidAmount >= totalAmount
          ? 'paid'
          : paidAmount > 0
              ? 'partial'
              : 'unpaid';
      await _client.from('purchase_invoices').update({
        'total_amount': totalAmount,
        'paid_amount': paidAmount,
        'remaining_amount': totalAmount - paidAmount,
        'payment_status': paymentStatus,
        'notes': notes,
        'supplier_id': _formState.selectedSupplier?.id,
        'currency': supplierCurrency,
        'payment_treasury_id': paymentTreasuryId,
        'payment_source_type': paymentSourceType ?? 'treasury',
        'payment_bank_account_id': paymentBankAccountId,
      }).eq('id', purchaseId.toString());

      // ══════════════════════════════════════════════════════════════
      // PAYMENT DELTA PROCESSING: Handle delta between old and new paid amounts
      // ══════════════════════════════════════════════════════════════
      // Payment is NOT processed here on update. Treasury/bank
      // deduction is deferred to the confirm step (rpc_confirm_purchase).
      // payment_processed stays false so confirm handles it.
      // ══════════════════════════════════════════════════════════════
      if (paidAmount > 0) {
        await _client.from('purchase_invoices').update({
          'payment_processed': false,
        }).eq('id', purchaseId.toString());
      } else {
        await _client.from('purchase_invoices').update({
          'payment_processed': false,
        }).eq('id', purchaseId.toString());
      }

      _safeEmit(const PurchaseFormSaved());
      await loadAll(reset: true);
      DataChangeEventBus.instance.notifyPurchasesChanged();
      return true;
    } catch (e, st) {
      debugPrint('🔴 PurchaseCubit.updatePurchase error: $e\n$st');
      return false;
    } finally {
      _formState = _formState.copyWith(isSaving: false);
    }
  }

  @override
  Future<void> close() {
    _itemsSub.cancel();
    _purchasesSub.cancel();
    _suppliersSub.cancel();
    _stationsSub.cancel();
    _debounce?.cancel();
    return super.close();
  }
}
