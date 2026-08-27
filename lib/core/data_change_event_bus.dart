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
  final _cropPurchasesController = StreamController<void>.broadcast();
  final _shareholdersController = StreamController<void>.broadcast();
  final _journalEntriesController = StreamController<void>.broadcast();
  final _packingWastesController = StreamController<void>.broadcast();

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
  Stream<void> get cropPurchasesStream => _cropPurchasesController.stream;
  Stream<void> get shareholdersStream => _shareholdersController.stream;
  Stream<void> get journalEntriesStream => _journalEntriesController.stream;
  Stream<void> get packingWastesStream => _packingWastesController.stream;

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
    _cropPurchasesController.close();
    _shareholdersController.close();
    _journalEntriesController.close();
    _packingWastesController.close();
  }
}
