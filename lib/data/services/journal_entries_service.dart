import 'supplier_settlement_service.dart';

class JournalEntriesService {
  static final JournalEntriesService instance = JournalEntriesService._();
  JournalEntriesService._();

  String formatDescription(String description, ViewType viewType) {
    return SupplierSettlementService.instance.getDisplayDescription(description, viewType);
  }
}
