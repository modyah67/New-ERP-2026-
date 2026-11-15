import 'dart:async';
import 'package:flutter/foundation.dart';

/// A lightweight, type-safe event bus that replaces GetX SyncService.
/// Uses Dart Streams instead of RxInt counters.
///
/// Usage:
///   // Listen (in cubit or anywhere)
///   DataChangeEventBus.instance.customersStream.listen((_) => reload());
///
///   // Emit (after save/delete)
///   DataChangeEventBus.instance.notifyCustomersChanged();
class DataChangeEventBus {
  DataChangeEventBus._();
  static final DataChangeEventBus instance = DataChangeEventBus._();

  // ── Stream Controllers (broadcast = multiple listeners) ──

  final _customersController = StreamController<void>.broadcast();
  final _suppliersController = StreamController<void>.broadcast();
  final _itemsController = StreamController<void>.broadcast();
  final _accountsController = StreamController<void>.broadcast();
  final _invoicesController = StreamController<void>.broadcast();
  final _purchasesController = StreamController<void>.broadcast();
  final _stationsController = StreamController<void>.broadcast();
  final _transfersController = StreamController<void>.broadcast();
  final _clearingAgentsController = StreamController<void>.broadcast();
  final _shippingCompaniesController = StreamController<void>.broadcast();
  final _transportSuppliersController = StreamController<void>.broadcast();
  final _cropPurchasesController = StreamController<void>.broadcast();
  final _shareholdersController = StreamController<void>.broadcast();
  final _journalEntriesController = StreamController<void>.broadcast();
  final _packingWastesController = StreamController<void>.broadcast();
  final _costCentersController = StreamController<void>.broadcast();
  final _costCategoriesController = StreamController<void>.broadcast();
  final _packingOrdersController = StreamController<void>.broadcast();
  final _sortingController = StreamController<void>.broadcast();
  final _exportsController = StreamController<void>.broadcast();
  final _treasuriesController = StreamController<void>.broadcast();

  // ── Public Streams ──

  Stream<void> get customersStream => _customersController.stream;
  Stream<void> get suppliersStream => _suppliersController.stream;
  Stream<void> get itemsStream => _itemsController.stream;
  Stream<void> get accountsStream => _accountsController.stream;
  Stream<void> get invoicesStream => _invoicesController.stream;
  Stream<void> get purchasesStream => _purchasesController.stream;
  Stream<void> get stationsStream => _stationsController.stream;
  Stream<void> get transfersStream => _transfersController.stream;
  Stream<void> get clearingAgentsStream => _clearingAgentsController.stream;
  Stream<void> get shippingCompaniesStream => _shippingCompaniesController.stream;
  Stream<void> get transportSuppliersStream => _transportSuppliersController.stream;
  Stream<void> get cropPurchasesStream => _cropPurchasesController.stream;
  Stream<void> get shareholdersStream => _shareholdersController.stream;
  Stream<void> get journalEntriesStream => _journalEntriesController.stream;
  Stream<void> get packingWastesStream => _packingWastesController.stream;
  Stream<void> get costCentersStream => _costCentersController.stream;
  Stream<void> get costCategoriesStream => _costCategoriesController.stream;
  Stream<void> get packingOrdersStream => _packingOrdersController.stream;
  Stream<void> get sortingStream => _sortingController.stream;
  Stream<void> get exportsStream => _exportsController.stream;
  Stream<void> get treasuriesStream => _treasuriesController.stream;

  // ── Emitters ──

  void notifyCustomersChanged() {
    _customersController.add(null);
    debugPrint('[EventBus] customers changed');
  }

  void notifySuppliersChanged() {
    _suppliersController.add(null);
    debugPrint('[EventBus] suppliers changed');
  }

  void notifyItemsChanged() {
    _itemsController.add(null);
    debugPrint('[EventBus] items changed');
  }

  void notifyAccountsChanged() {
    _accountsController.add(null);
    debugPrint('[EventBus] accounts changed');
  }

  void notifyInvoicesChanged() {
    _invoicesController.add(null);
    debugPrint('[EventBus] invoices changed');
  }

  void notifyPurchasesChanged() {
    _purchasesController.add(null);
    debugPrint('[EventBus] purchases changed');
  }

  void notifyStationsChanged() {
    _stationsController.add(null);
    debugPrint('[EventBus] stations changed');
  }

  void notifyTransfersChanged() {
    _transfersController.add(null);
    debugPrint('[EventBus] transfers changed');
  }

  void notifyClearingAgentsChanged() {
    _clearingAgentsController.add(null);
    debugPrint('[EventBus] clearing agents changed');
  }

  void notifyShippingCompaniesChanged() {
    _shippingCompaniesController.add(null);
    debugPrint('[EventBus] shipping companies changed');
  }

  void notifyTransportSuppliersChanged() {
    _transportSuppliersController.add(null);
    debugPrint('[EventBus] transport suppliers changed');
  }

  void notifyCropPurchasesChanged() {
    _cropPurchasesController.add(null);
    debugPrint('[EventBus] crop purchases changed');
  }

  void notifyShareholdersChanged() {
    _shareholdersController.add(null);
    debugPrint('[EventBus] shareholders changed');
  }

  void notifyJournalEntriesChanged() {
    _journalEntriesController.add(null);
    debugPrint('[EventBus] journal entries changed');
  }

  void notifyPackingWastesChanged() {
    _packingWastesController.add(null);
    debugPrint('[EventBus] packing wastes changed');
  }

  void notifyCostCentersChanged() {
    _costCentersController.add(null);
    debugPrint('[EventBus] cost centers changed');
  }

  void notifyCostCategoriesChanged() {
    _costCategoriesController.add(null);
    debugPrint('[EventBus] cost categories changed');
  }

  void notifyPackingOrdersChanged() {
    _packingOrdersController.add(null);
    debugPrint('[EventBus] packing orders changed');
  }

  void notifySortingChanged() {
    _sortingController.add(null);
    debugPrint('[EventBus] sorting changed');
  }

  void notifyExportsChanged() {
    _exportsController.add(null);
    debugPrint('[EventBus] exports changed');
  }

  void notifyTreasuryChanged() {
    _treasuriesController.add(null);
    debugPrint('[EventBus] treasuries changed');
  }

  // ── Cleanup ──

  void dispose() {
    _customersController.close();
    _suppliersController.close();
    _itemsController.close();
    _accountsController.close();
    _invoicesController.close();
    _purchasesController.close();
    _stationsController.close();
    _transfersController.close();
    _clearingAgentsController.close();
    _shippingCompaniesController.close();
    _transportSuppliersController.close();
    _cropPurchasesController.close();
    _shareholdersController.close();
    _journalEntriesController.close();
    _packingWastesController.close();
    _costCentersController.close();
    _costCategoriesController.close();
    _packingOrdersController.close();
    _sortingController.close();
    _exportsController.close();
    _treasuriesController.close();
  }
}
