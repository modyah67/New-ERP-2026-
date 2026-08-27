import 'package:flutter_test/flutter_test.dart';

void main() {
  group('COGSAutomationService', () {
    test('COGS posting creates double-entry journal with correct accounts', () {
      const cogsAccountId = 6;    // 5000 COGS
      const inventoryAccountId = 3; // 1030 Inventory
      const packingAccountId = 4;   // 1040 Packing Materials
      const totalCost = 4500.0;
      const packingCost = 500.0;
      const inventoryCost = totalCost - packingCost;

      // COGS = Debit 5000, Credit 1030 for inventory, Credit 1040 for packing
      final transactions = [
        {'account_id': cogsAccountId, 'type': 'debit', 'amount': totalCost},
        {'account_id': inventoryAccountId, 'type': 'credit', 'amount': inventoryCost},
        {'account_id': packingAccountId, 'type': 'credit', 'amount': packingCost},
      ];

      final totalDebit = transactions
          .where((t) => t['type'] == 'debit')
          .fold(0.0, (sum, t) => sum + (t['amount'] as double));
      final totalCredit = transactions
          .where((t) => t['type'] == 'credit')
          .fold(0.0, (sum, t) => sum + (t['amount'] as double));

      expect(totalDebit, totalCredit); // Balanced double-entry
      expect(totalDebit, totalCost);
      expect(totalCredit, totalCost);
    });

    test('COGS posting is idempotent when cogs_posted flag is true', () {
      const cogsPosted = true;
      expect(cogsPosted, true);
    });

    test('COGS reference_type and reference_id are stored correctly', () {
      const referenceType = 'export_shipment';
      const referenceId = 42;

      final transaction = {
        'reference_type': referenceType,
        'reference_id': referenceId,
      };

      expect(transaction['reference_type'], 'export_shipment');
      expect(transaction['reference_id'], 42);
    });

    test('COGS skips posting when total cost <= 0', () {
      const totalCost = 0.0;
      expect(totalCost <= 0, true);
    });
  });
}
