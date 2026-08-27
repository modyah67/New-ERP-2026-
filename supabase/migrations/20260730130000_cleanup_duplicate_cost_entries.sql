-- Cleanup: Remove duplicate cost item ledger entries
-- The RPC creates entries with reference_type='packing_cost', Dart code with 'packing_cost_item'
-- Keep only the one with notes (statement_notes), delete the other

-- For each packing order that has duplicate cost entries, keep the one that has a statement_note
DELETE FROM ledger_entries le
WHERE le.reference_type = 'packing_cost'
  AND le.entry_type = 'credit'
  AND EXISTS (
    SELECT 1 FROM ledger_entries le2
    WHERE le2.reference_type = 'packing_cost_item'
      AND le2.entity_id = le.entity_id
      AND le2.amount = le.amount
  );

-- Also clean up any remaining entries with packing_cost that have a matching packing_cost_item
DELETE FROM ledger_entries le
WHERE le.reference_type = 'packing_cost'
  AND le.entry_type = 'credit'
  AND le.description LIKE 'بند تكلفة أمر تعبئة%'
  AND EXISTS (
    SELECT 1 FROM ledger_entries le2
    WHERE le2.reference_type = 'packing_cost_item'
      AND le2.entity_id = le.entity_id
  );
