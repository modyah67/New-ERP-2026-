-- Migration 20260728170000: Fix trigger firing on draft lots
--
-- PROBLEM:
--   The trigger fn_on_harvest_receipt_saved fires on EVERY INSERT/UPDATE/DELETE
--   on lot_receipts, including drafts. This causes:
--   1. stock_batches created for draft lots
--   2. station_products quantity accumulating on every save of a draft
--   3. ledger_entries + supplier outstanding_balance updated for draft lots
--
-- FIX:
--   1. Modify trigger to ONLY run side effects for confirmed lots (is_confirmed = true)
--   2. Clean up existing bad data from draft lots

-- Step 1: Fix the trigger function
CREATE OR REPLACE FUNCTION public.fn_on_harvest_receipt_saved()
RETURNS TRIGGER AS $$
BEGIN
  -- DELETE: only reverse if the deleted lot was confirmed
  IF TG_OP = 'DELETE' THEN
    IF OLD.is_confirmed = true THEN
      UPDATE public.station_products SET quantity = GREATEST(COALESCE(quantity, 0) - OLD.net_weight_kg, 0)
      WHERE station_id = OLD.station_id AND fruit_type_id = OLD.fruit_type_id;
      PERFORM public.sync_inventory_stock_for_lot(OLD.id, 'DELETE');
      PERFORM public.sync_supplier_ledger_for_lot(OLD.id, 'DELETE');
    END IF;
    RETURN OLD;
  END IF;

  -- UPDATE: reverse old if confirmed, apply new if confirmed
  IF TG_OP = 'UPDATE' THEN
    -- Reverse old lot's side effects (only if it was confirmed)
    IF OLD.is_confirmed = true THEN
      UPDATE public.station_products SET quantity = GREATEST(COALESCE(quantity, 0) - OLD.net_weight_kg, 0)
      WHERE station_id = OLD.station_id AND fruit_type_id = OLD.fruit_type_id;
      PERFORM public.sync_inventory_stock_for_lot(OLD.id, 'DELETE');
      PERFORM public.sync_supplier_ledger_for_lot(OLD.id, 'DELETE');
    END IF;
    -- Apply new lot's side effects (only if it is now confirmed)
    IF NEW.is_confirmed = true THEN
      PERFORM public.sync_inventory_stock_for_lot(NEW.id, 'INSERT');
      PERFORM public.sync_warehouse_stock_for_lot(NEW.id, 'INSERT');
      PERFORM public.sync_supplier_ledger_for_lot(NEW.id, 'INSERT');
    END IF;
    RETURN NEW;
  END IF;

  -- INSERT: only apply side effects if confirmed
  IF TG_OP = 'INSERT' THEN
    IF NEW.is_confirmed = true THEN
      PERFORM public.sync_inventory_stock_for_lot(NEW.id, 'INSERT');
      PERFORM public.sync_warehouse_stock_for_lot(NEW.id, 'INSERT');
      PERFORM public.sync_supplier_ledger_for_lot(NEW.id, 'INSERT');
    END IF;
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Step 2: Clean up bad data from draft lots
-- Remove station_products entries created by draft lots (via sync_warehouse_stock_for_lot)
-- These have product_name = 'Lot-<lot_number>' pattern
DELETE FROM station_products sp
USING lot_receipts lr
WHERE sp.product_name = 'Lot-' || lr.lot_number
  AND lr.is_confirmed = false
  AND sp.station_id = lr.station_id
  AND sp.fruit_type_id = lr.fruit_type_id;

-- Remove stock_batches created by draft lots (via sync_inventory_stock_for_lot)
-- Batch number format is 'B-LOT-<UUID without dashes>'
DELETE FROM stock_batches sb
USING lot_receipts lr
WHERE sb.batch_number = 'B-LOT-' || replace(lr.id::TEXT, '-', '')
  AND lr.is_confirmed = false;

-- Remove stock_movements created by draft lots
DELETE FROM stock_movements sm
USING lot_receipts lr
WHERE sm.reference_type = 'lot_receipt'
  AND sm.reference_id = lr.id::TEXT
  AND lr.is_confirmed = false;

-- Remove ledger_entries created by draft lots (via sync_supplier_ledger_for_lot)
-- reference_text stores the lot UUID (not lot_number)
DELETE FROM ledger_entries le
USING lot_receipts lr
WHERE le.entity_type = 'supplier'
  AND le.reference_type = 'lot_receipt'
  AND le.reference_text = lr.id::TEXT
  AND lr.is_confirmed = false;

-- Reverse supplier outstanding_balance for draft lots
UPDATE suppliers s
SET outstanding_balance = COALESCE(outstanding_balance, 0) - COALESCE(lr.total_fruit_cost, 0)
FROM lot_receipts lr
WHERE s.id = lr.supplier_id
  AND lr.is_confirmed = false
  AND COALESCE(lr.total_fruit_cost, 0) > 0;

-- Refresh PostgREST schema cache
NOTIFY pgrst, 'reload schema';
