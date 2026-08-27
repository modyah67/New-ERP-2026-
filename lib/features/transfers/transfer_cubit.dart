import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/dao/transfer_dao.dart';
import '../../data/dao/station_dao.dart';
import '../../data/dao/station_product_dao.dart';
import '../../data/dao/station_product_batch_dao.dart';
import '../../data/models/stock_transfer_model.dart';
import '../../data/models/station_product_model.dart';
import '../../core/data_change_event_bus.dart';
import 'transfer_state.dart';

class TransferCubit extends Cubit<TransferState> {
  final TransferDao _transferDao = TransferDao();
  final StationDao _stationDao = StationDao();
  final StationProductDao _stationProductDao = StationProductDao();
  final StationProductBatchDao _batchDao = StationProductBatchDao();
  final _client = Supabase.instance.client;

  int _offset = 0;
  static const int _limit = 50;
  String _currentQuery = '';
  DateTime? _fromDate;
  DateTime? _toDate;

  TransferFormState _formState = const TransferFormState();
  TransferFormState get formState => _formState;

  final formKey = GlobalKey<FormState>();
  final notesController = TextEditingController();
  final quantityController = TextEditingController();
  final productSearchController = TextEditingController();

  int? _fromStationId;
  int? _toStationId;
  String? _selectedProductName;
  String? _selectedProductCode;

  final Map<int, String> _stationNameCache = {};

  Timer? _debounce;
  Timer? _productSearchDebounce;

  TransferCubit() : super(const TransferInitial());

  Future<void> init() async {
    await loadAll(reset: true);
  }

  Future<void> refreshDeletability() async {
    final currentState = state;
    if (currentState is! TransferLoaded) return;
    try {
      final deletableMap = await _resolveDeletableTransfers(currentState.transfers);
      if (!isClosed) {
        emit(currentState.copyWith(deletableTransfers: deletableMap));
      }
    } catch (_) {}
  }

  Future<void> prepareTransferForm() async {
    _formState = const TransferFormState(isSaving: true);
    emit(_formState);

    try {
      final allStations = await _stationDao.getAll(limit: 100);

      for (final s in allStations) {
        if (s.id != null) _stationNameCache[int.parse(s.id!)] = s.name;
      }

      _formState = TransferFormState(
        allStations: allStations,
      );
    } catch (e) {
      debugPrint('prepareTransferForm error: $e');
      _formState = const TransferFormState();
    }
    emit(_formState);
  }

  void setFromStation(int? id) {
    _fromStationId = id;
    _selectedProductName = null;
    _selectedProductCode = null;
    _loadSourceProducts();
  }

  void setToStation(int? id) {
    _toStationId = id;
  }

  void selectProduct(String name, String code) {
    _selectedProductName = name;
    _selectedProductCode = code;
  }

  void onProductSearchChanged(String query) {
    _productSearchDebounce?.cancel();
    _productSearchDebounce = Timer(const Duration(milliseconds: 300), () {
      _loadSourceProducts(query: query.trim());
    });
  }

  Future<void> _loadSourceProducts({String query = ''}) async {
    if (_fromStationId == null) {
      _formState = _formState.copyWith(sourceProducts: []);
      emit(_formState);
      return;
    }
    try {
      var products = await _stationProductDao.getByStation(_fromStationId!);

      try {
        final fruitTypes = await _client.from('fruit_types').select('name, code, purchase_mode');
        final fruitTypeMap = {
          for (final ft in fruitTypes) ...{
            ft['name']?.toString() ?? '': ft['purchase_mode']?.toString(),
            if (ft['code'] != null && (ft['code']?.toString() ?? '').isNotEmpty)
              ft['code']!.toString(): ft['purchase_mode']?.toString(),
          }
        };

        products = products.map((p) {
          final fruitKey = p.productCode.isNotEmpty ? p.productCode : p.productName;
          final isCarton = p.unit == 'carton' || fruitTypeMap[fruitKey] == 'carton' || fruitTypeMap[p.productName] == 'carton';
          return p.copyWith(
            unit: isCarton ? 'carton' : p.unit,
          );
        }).toList();
      } catch (e) {
        debugPrint('⚠️ Error loading available stock for transfers: $e');
      }

      if (query.isNotEmpty) {
        products = products.where((p) =>
          p.productName.toLowerCase().contains(query.toLowerCase()) ||
          p.productCode.toLowerCase().contains(query.toLowerCase())
        ).toList();
      }
      _formState = _formState.copyWith(sourceProducts: products);
    } catch (_) {
      _formState = _formState.copyWith(sourceProducts: []);
    }
    emit(_formState);
  }

  Future<void> loadAll({bool reset = false}) async {
    if (isClosed) return;
    if (reset) {
      _offset = 0;
      _currentQuery = '';
      emit(const TransferLoading());
    }

    final currentState = state;
    if (currentState is TransferLoaded && !currentState.hasMore && !reset) return;

    try {
      final newItems = await _transferDao.getAll(limit: _limit, offset: _offset);
      final hasMore = newItems.length >= _limit;
      _offset += _limit;

      await _resolveStationNames(newItems);
      final deletableMap = await _resolveDeletableTransfers(newItems);

      if (isClosed) return;

      if (reset) {
        emit(TransferLoaded(
          transfers: newItems, 
          stationNames: _stationNameCache, 
          deletableTransfers: deletableMap,
          hasMore: hasMore
        ));
      } else if (currentState is TransferLoaded) {
        final mergedDeletables = Map<int, bool>.from(currentState.deletableTransfers)..addAll(deletableMap);
        emit(currentState.copyWith(
          transfers: [...currentState.transfers, ...newItems],
          stationNames: _stationNameCache,
          deletableTransfers: mergedDeletables,
          hasMore: hasMore,
          isFetchingMore: false,
        ));
      }
    } catch (e) {
      if (isClosed) return;
      emit(TransferError(message: 'حدث خطأ أثناء تحميل البيانات: $e'));
    }
  }

  Future<void> _resolveStationNames(List<StockTransferModel> transfers) async {
    final neededIds = <int>{};
    for (final t in transfers) {
      if (!_stationNameCache.containsKey(t.fromStationId)) {
        neededIds.add(t.fromStationId);
      }
      if (!_stationNameCache.containsKey(t.toStationId)) {
        neededIds.add(t.toStationId);
      }
    }

    for (final id in neededIds) {
      try {
        final station = await _stationDao.getById(id.toString());
        if (station != null) {
          _stationNameCache[id] = station.name;
        } else {
          _stationNameCache[id] = 'محطة #$id';
        }
      } catch (_) {
        _stationNameCache[id] = 'محطة #$id';
      }
    }
  }

  Future<Map<int, bool>> _resolveDeletableTransfers(List<StockTransferModel> transfers) async {
    final Map<int, bool> deletableTransfers = {};
    final toStationIds = transfers.map((t) => t.toStationId).where((id) => id > 0).toSet().toList();
    if (toStationIds.isEmpty) return deletableTransfers;

    try {
      final batchesData = await _client
          .from('station_product_batches')
          .select('station_id, product_name, product_code, remaining_quantity')
          .eq('source_type', 'transfer')
          .inFilter('station_id', toStationIds);

      final Map<String, double> remainingMap = {};
      for (final b in batchesData) {
        final stId = b['station_id']?.toString() ?? '';
        final pName = b['product_name']?.toString() ?? '';
        final pCode = b['product_code']?.toString() ?? '';
        final rem = (b['remaining_quantity'] as num?)?.toDouble() ?? 0.0;
        final key = '${stId}_${pName}_$pCode';
        remainingMap[key] = (remainingMap[key] ?? 0.0) + rem;
      }

      for (final t in transfers) {
        if (t.id != null) {
          final key = '${t.toStationId}_${t.productName}_${t.productCode}';
          final available = remainingMap[key] ?? 0.0;
          deletableTransfers[t.id!] = available >= (t.quantity - 0.001); // floating point tolerance
        }
      }
    } catch (e) {
      debugPrint('Error resolving deletable transfers: $e');
      for (final t in transfers) {
        if (t.id != null) deletableTransfers[t.id!] = false;
      }
    }
    return deletableTransfers;
  }

  void onSearchChanged(String query) {
    _currentQuery = query.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(reset: true);
    });
  }

  void onFromDateChanged(DateTime? date) {
    _fromDate = date;
    _runSearch(reset: true);
  }

  void onToDateChanged(DateTime? date) {
    _toDate = date;
    _runSearch(reset: true);
  }

  void clearDateFilter() {
    _fromDate = null;
    _toDate = null;
    _runSearch(reset: true);
  }

  Future<void> _runSearch({bool reset = false}) async {
    if (reset) _offset = 0;

    final currentState = state;
    if (currentState is TransferLoaded && !currentState.hasMore && !reset) return;

    try {
      final hasDateFilter = _fromDate != null || _toDate != null;
      final hasSearch = _currentQuery.isNotEmpty;

      List<StockTransferModel> newItems;

      if (hasDateFilter) {
        final start = _fromDate ?? DateTime(2020);
        final end = _toDate != null ? _toDate!.add(const Duration(days: 1)) : DateTime.now();
        newItems = await _transferDao.getByDateRange(start, end, limit: _limit, offset: _offset);
        if (hasSearch) {
          newItems = newItems.where((t) =>
            t.productName.toLowerCase().contains(_currentQuery.toLowerCase()) ||
            t.productCode.toLowerCase().contains(_currentQuery.toLowerCase()) ||
            (t.notes?.toLowerCase().contains(_currentQuery.toLowerCase()) ?? false)
          ).toList();
        }
      } else if (hasSearch) {
        newItems = await _transferDao.search(_currentQuery, limit: _limit, offset: _offset);
      } else {
        await loadAll(reset: reset);
        return;
      }

      final hasMore = newItems.length >= _limit;
      _offset += _limit;

      await _resolveStationNames(newItems);
      final deletableMap = await _resolveDeletableTransfers(newItems);

      if (reset) {
        emit(TransferLoaded(
          transfers: newItems,
          stationNames: _stationNameCache,
          deletableTransfers: deletableMap,
          searchQuery: _currentQuery,
          fromDate: _fromDate,
          toDate: _toDate,
          hasMore: hasMore,
        ));
      } else if (currentState is TransferLoaded) {
        final mergedDeletables = Map<int, bool>.from(currentState.deletableTransfers)..addAll(deletableMap);
        emit(currentState.copyWith(
          transfers: [...currentState.transfers, ...newItems],
          stationNames: _stationNameCache,
          deletableTransfers: mergedDeletables,
          searchQuery: _currentQuery,
          fromDate: _fromDate,
          toDate: _toDate,
          hasMore: hasMore,
          isFetchingMore: false,
        ));
      }
    } catch (e) {
      emit(TransferError(message: 'حدث خطأ أثناء البحث: $e'));
    }
  }

  Future<bool> saveTransfer(String userId) async {
    if (!formKey.currentState!.validate()) return false;

    if (_fromStationId == null) {
      debugPrint('TransferCubit: no source station');
      return false;
    }
    if (_toStationId == null) {
      debugPrint('TransferCubit: no destination station');
      return false;
    }
    if (_fromStationId == _toStationId) {
      debugPrint('TransferCubit: source and destination are the same');
      return false;
    }

    final quantity = double.tryParse(quantityController.text.trim());
    if (quantity == null || quantity <= 0) {
      debugPrint('TransferCubit: invalid quantity');
      return false;
    }

    if (_selectedProductName == null || _selectedProductName!.isEmpty) {
      debugPrint('TransferCubit: no product selected');
      return false;
    }

    _formState = _formState.copyWith(isSaving: true);
    emit(_formState);

    try {
      final transfer = StockTransferModel(
        fromStationId: _fromStationId!,
        toStationId: _toStationId!,
        productCode: _selectedProductCode ?? '',
        productName: _selectedProductName ?? '',
        quantity: quantity,
        notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
        transferredBy: userId,
        createdAt: DateTime.now().toIso8601String(),
      );

      await _transferDao.insert(transfer);

      final product = _formState.sourceProducts.firstWhere(
        (p) => p.productName == _selectedProductName && p.productCode == (_selectedProductCode ?? ''),
        orElse: () => StationProductModel(
          stationId: _fromStationId!,
          productName: _selectedProductName ?? '',
          productCode: _selectedProductCode ?? '',
          quantity: 0,
        ),
      );

      final deductions = await _batchDao.deductFIFODetailed(
        stationId: _fromStationId!,
        productName: _selectedProductName!,
        productCode: _selectedProductCode,
        quantity: quantity,
        itemType: product.itemType,
        rawMaterialId: product.rawMaterialId,
        fruitTypeId: product.fruitTypeId,
      );

      await _stationProductDao.upsertQuantity(
        stationId: _fromStationId!,
        productName: _selectedProductName!,
        productCode: _selectedProductCode ?? '',
        delta: -quantity,
        itemType: product.itemType,
        rawMaterialId: product.rawMaterialId,
        fruitTypeId: product.fruitTypeId,
      );

      await _stationProductDao.upsertQuantity(
        stationId: _toStationId!,
        productName: _selectedProductName!,
        productCode: _selectedProductCode ?? '',
        delta: quantity,
        itemType: product.itemType,
        rawMaterialId: product.rawMaterialId,
        fruitTypeId: product.fruitTypeId,
      );

      for (final d in deductions) {
        await _batchDao.insertBatch(
          stationId: _toStationId!,
          productName: _selectedProductName!,
          productCode: d.productCode.isNotEmpty ? d.productCode : (_selectedProductCode ?? ''),
          quantity: d.quantity,
          unitCost: d.unitCost,
          currency: d.currency,
          exchangeRate: d.exchangeRate,
          sourceType: 'transfer',
          sourceDate: d.sourceDate,
          supplierName: d.supplierName,
          purchaseInvoiceId: d.purchaseInvoiceId,
          sourceStationName: _stationNameCache[_fromStationId] ?? '',
          itemType: d.itemType,
          rawMaterialId: d.rawMaterialId,
          fruitTypeId: d.fruitTypeId,
        );
      }

      _clearForm();
      await loadAll(reset: true);

      DataChangeEventBus.instance.notifyTransfersChanged();
      DataChangeEventBus.instance.notifyStationsChanged();
      return true;
    } catch (e) {
      debugPrint('TransferCubit.saveTransfer error: $e');
      _formState = _formState.copyWith(isSaving: false);
      emit(_formState);
      return false;
    }
  }

  Future<bool> deleteTransfer(int id) async {
    Future<void> _reverseDestinationBatches(StockTransferModel transfer) async {
      try {
        var query = _client
            .from('station_product_batches')
            .select('id, remaining_quantity, quantity')
            .eq('station_id', transfer.toStationId)
            .eq('source_type', 'transfer');

        if (transfer.productCode.isNotEmpty) {
          query = query.eq('product_code', transfer.productCode);
        } else {
          query = query.eq('product_name', transfer.productName);
        }

        final batches = await query.order('created_at', ascending: false);

        double toRemove = transfer.quantity;
        for (final b in batches) {
          if (toRemove <= 0) break;
          final batchId = (b['id'] as num?)?.toInt();
          final remaining = (b['remaining_quantity'] as num?)?.toDouble() ?? 0.0;
          if (batchId == null || remaining <= 0) continue;

          if (remaining >= toRemove) {
            await _client
                .from('station_product_batches')
                .update({'remaining_quantity': remaining - toRemove})
                .eq('id', batchId);
            toRemove = 0;
          } else {
            await _client
                .from('station_product_batches')
                .delete()
                .eq('id', batchId);
            toRemove -= remaining;
          }
        }
      } catch (e) {
        debugPrint('⚠️ transfer_cubit: Failed to delete destination batches: $e');
      }
    }

    try {
      final transfer = await _transferDao.getById(id);
      if (transfer == null) {
        await _transferDao.delete(id);
        await loadAll(reset: true);
        DataChangeEventBus.instance.notifyTransfersChanged();
        return true;
      }

      await Future.wait([
        if (transfer.fromStationId > 0)
          _batchDao.restoreFIFO(
            stationId: transfer.fromStationId,
            productName: transfer.productName,
            productCode: transfer.productCode,
            quantity: transfer.quantity,
          ).catchError((e) {
            debugPrint('⚠️ Failed to restore FIFO: $e');
          }),
        if (transfer.fromStationId > 0)
          _stationProductDao.upsertQuantity(
            stationId: transfer.fromStationId,
            productName: transfer.productName,
            productCode: transfer.productCode,
            delta: transfer.quantity,
          ),
        if (transfer.toStationId > 0)
          _stationProductDao.upsertQuantity(
            stationId: transfer.toStationId,
            productName: transfer.productName,
            productCode: transfer.productCode,
            delta: -transfer.quantity,
          ),
        if (transfer.toStationId > 0)
          _reverseDestinationBatches(transfer),
      ]);
      await _transferDao.delete(id);
      await loadAll(reset: true);

      DataChangeEventBus.instance.notifyTransfersChanged();
      DataChangeEventBus.instance.notifyStationsChanged();
      return true;
    } catch (e) {
      debugPrint('TransferCubit.deleteTransfer error: $e');
      return false;
    }
  }

  Future<bool> editTransfer(int transferId, String userId) async {
    if (!formKey.currentState!.validate()) return false;
    if (_fromStationId == null || _toStationId == null) return false;
    if (_fromStationId == _toStationId) return false;

    final quantity = double.tryParse(quantityController.text.trim());
    if (quantity == null || quantity <= 0) return false;
    if (_selectedProductName == null || _selectedProductName!.isEmpty) return false;

    _formState = _formState.copyWith(isSaving: true);
    emit(_formState);

    try {
      // 1. Load old transfer
      final oldTransfer = await _transferDao.getById(transferId);
      if (oldTransfer == null) return false;

      // 2. Reverse old effects
      // 2a. Restore FIFO batches at OLD source station
      try {
        await _batchDao.restoreFIFO(
          stationId: oldTransfer.fromStationId,
          productName: oldTransfer.productName,
          productCode: oldTransfer.productCode,
          quantity: oldTransfer.quantity,
        );
      } catch (e) {
        debugPrint('⚠️ transfer_cubit: Failed to restore FIFO batches at old source station: $e');
      }

      // 2b. Restore old source station_products
      if (oldTransfer.fromStationId > 0) {
        await _stationProductDao.upsertQuantity(
          stationId: oldTransfer.fromStationId,
          productName: oldTransfer.productName,
          productCode: oldTransfer.productCode,
          delta: oldTransfer.quantity,
        );
      }

      // 2c. Deduct old dest station_products
      if (oldTransfer.toStationId > 0) {
        await _stationProductDao.upsertQuantity(
          stationId: oldTransfer.toStationId,
          productName: oldTransfer.productName,
          productCode: oldTransfer.productCode,
          delta: -oldTransfer.quantity,
        );
      }

      // 2d. Remove ALL old dest batches (source_type='transfer')
      try {
        var query = _client
            .from('station_product_batches')
            .select('id')
            .eq('station_id', oldTransfer.toStationId)
            .eq('source_type', 'transfer');

        if (oldTransfer.productCode.isNotEmpty) {
          query = query.eq('product_code', oldTransfer.productCode);
        } else {
          query = query.eq('product_name', oldTransfer.productName);
        }

        final batches = await query.order('created_at', ascending: false);
        for (final b in batches) {
          final batchId = (b['id'] as num?)?.toInt();
          if (batchId != null) {
            await _client.from('station_product_batches').delete().eq('id', batchId);
          }
        }
      } catch (e) {
        debugPrint('⚠️ transfer_cubit: Failed to delete old destination batches during edit: $e');
      }

      // 3. Apply new effects
      // 3a. Deduct FIFO at NEW source station (per-batch)
      final deductions = await _batchDao.deductFIFODetailed(
        stationId: _fromStationId!,
        productName: _selectedProductName!,
        productCode: _selectedProductCode,
        quantity: quantity,
      );

      // 3b. Deduct new source station_products
      await _stationProductDao.upsertQuantity(
        stationId: _fromStationId!,
        productName: _selectedProductName!,
        productCode: _selectedProductCode ?? '',
        delta: -quantity,
      );

      // 3c. Add new dest station_products
      await _stationProductDao.upsertQuantity(
        stationId: _toStationId!,
        productName: _selectedProductName!,
        productCode: _selectedProductCode ?? '',
        delta: quantity,
      );

      // 3d. Insert new dest batches (per-batch with original cost & origin metadata)
      for (final d in deductions) {
        await _batchDao.insertBatch(
          stationId: _toStationId!,
          productName: _selectedProductName!,
          productCode: d.productCode.isNotEmpty ? d.productCode : (_selectedProductCode ?? ''),
          quantity: d.quantity,
          unitCost: d.unitCost,
          currency: d.currency,
          exchangeRate: d.exchangeRate,
          sourceType: 'transfer',
          sourceDate: d.sourceDate,
          supplierName: d.supplierName,
          purchaseInvoiceId: d.purchaseInvoiceId,
          sourceStationName: _stationNameCache[_fromStationId] ?? '',
        );
      }

      // 4. Update transfer record
      await _transferDao.update(transferId, {
        'from_station_id': _fromStationId,
        'to_station_id': _toStationId,
        'product_code': _selectedProductCode ?? '',
        'product_name': _selectedProductName ?? '',
        'quantity': quantity,
        'notes': notesController.text.trim().isEmpty ? null : notesController.text.trim(),
      });

      _clearForm();
      await loadAll(reset: true);

      DataChangeEventBus.instance.notifyTransfersChanged();
      DataChangeEventBus.instance.notifyStationsChanged();
      return true;
    } catch (e) {
      debugPrint('TransferCubit.editTransfer error: $e');
      _formState = _formState.copyWith(isSaving: false);
      emit(_formState);
      return false;
    }
  }

  void _clearForm() {
    notesController.clear();
    quantityController.clear();
    productSearchController.clear();
    _fromStationId = null;
    _toStationId = null;
    _selectedProductName = null;
    _selectedProductCode = null;
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    _productSearchDebounce?.cancel();
    // Delay disposal to avoid assertion error when text selection is active
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notesController.dispose();
      quantityController.dispose();
      productSearchController.dispose();
    });
    return super.close();
  }
}
