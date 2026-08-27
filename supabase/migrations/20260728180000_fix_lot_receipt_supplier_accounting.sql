-- Migration 20260728180000: Fix lot receipt supplier accounting and currency
--
-- ROOT CAUSE of 3 problems:
--   1. sync_supplier_ledger_for_lot hardcodes 'EGP' as currency
--   2. LotPaymentService was removed from confirmLot() → no payment processing at all
--   3. Trigger calls sync_warehouse_stock_for_lot which duplicates rpc_process_lot_receipt's
--      station_products update (RPC sets quantity from batch sum, trigger adds net_weight_kg on top)
--
-- FIX:
--   A. Fix sync_supplier_ledger_for_lot to use lot's currency
--   B. Remove sync_warehouse_stock_for_lot from trigger INSERT path (RPC handles it)
--   C. Remove sync_inventory_stock_for_lot from trigger INSERT path (different from station_product_batches)
--      -- the trigger creates stock_batches (old inventory system) while RPC creates station_product_batches
--      -- keeping both is fine, they serve different systems
--   D. Clean up wrong data from trigger firing on drafts

-- ============================================================
-- A. Fix sync_supplier_ledger_for_lot: use lot currency + fix UUID type
--    lot_receipts.id is BIGSERIAL (BIGINT), NOT UUID!
--    The old function expected UUID, causing silent failure in the trigger.
--    Only handles the CREDIT (purchase amount).
--    DEBIT (payment) is handled by LotPaymentService in Dart.
-- ============================================================
DROP FUNCTION IF EXISTS public.sync_supplier_ledger_for_lot(UUID, TEXT) CASCADE;
DROP FUNCTION IF EXISTS public.sync_supplier_ledger_for_lot(BIGINT, TEXT) CASCADE;

CREATE OR REPLACE FUNCTION public.sync_supplier_ledger_for_lot(p_lot_id BIGINT, p_action TEXT)
RETURNS VOID AS $$
DECLARE
  v_lot RECORD;
BEGIN
  IF p_action = 'DELETE' THEN
    DELETE FROM public.ledger_entries WHERE reference_type = 'lot_receipt' AND reference_text = p_lot_id::TEXT;
    SELECT * INTO v_lot FROM public.lot_receipts WHERE id = p_lot_id;
    IF FOUND THEN
      UPDATE public.suppliers
      SET outstanding_balance = COALESCE(outstanding_balance, 0) - COALESCE(v_lot.total_fruit_cost, 0)
      WHERE id = v_lot.supplier_id;
    END IF;
  ELSIF p_action = 'INSERT' OR p_action = 'UPDATE' THEN
    SELECT * INTO v_lot FROM public.lot_receipts WHERE id = p_lot_id;

    -- Reverse old entries first (for UPDATE case)
    IF p_action = 'UPDATE' THEN
      DELETE FROM public.ledger_entries WHERE reference_type = 'lot_receipt' AND reference_text = p_lot_id::TEXT;
      UPDATE public.suppliers
      SET outstanding_balance = COALESCE(outstanding_balance, 0) - COALESCE(v_lot.total_fruit_cost, 0)
      WHERE id = v_lot.supplier_id;
    END IF;

    -- Credit: total purchase amount (what we owe the supplier)
    IF COALESCE(v_lot.total_fruit_cost, 0) > 0 THEN
      INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_text, description)
      VALUES ('supplier', v_lot.supplier_id::TEXT, 'credit', v_lot.total_fruit_cost, COALESCE(v_lot.currency, 'EGP'), 'lot_receipt', p_lot_id::TEXT, 'شراء محصول خام - إذن رقم ' || v_lot.lot_number::TEXT);
    END IF;

    -- Update outstanding_balance
    UPDATE public.suppliers
    SET outstanding_balance = COALESCE(outstanding_balance, 0) + COALESCE(v_lot.total_fruit_cost, 0)
    WHERE id = v_lot.supplier_id;
  END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- B. Fix trigger: keep only supplier ledger (station_products is managed by
--    rpc_process_lot_receipt, stock_batches/stock_movements is legacy and broken)
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_on_harvest_receipt_saved()
RETURNS TRIGGER AS $$
BEGIN
  -- DELETE: only reverse if the deleted lot was confirmed
  IF TG_OP = 'DELETE' THEN
    IF OLD.is_confirmed = true THEN
      PERFORM public.sync_supplier_ledger_for_lot(OLD.id, 'DELETE');
    END IF;
    RETURN OLD;
  END IF;

  -- UPDATE: reverse old if confirmed, apply new if confirmed
  IF TG_OP = 'UPDATE' THEN
    IF OLD.is_confirmed = true THEN
      PERFORM public.sync_supplier_ledger_for_lot(OLD.id, 'DELETE');
    END IF;
    IF NEW.is_confirmed = true THEN
      -- sync_supplier_ledger_for_lot creates supplier credit + updates outstanding_balance
      PERFORM public.sync_supplier_ledger_for_lot(NEW.id, 'INSERT');
    END IF;
    RETURN NEW;
  END IF;

  -- INSERT: only apply side effects if confirmed (rare — usually lots are created as drafts)
  IF TG_OP = 'INSERT' THEN
    IF NEW.is_confirmed = true THEN
      PERFORM public.sync_supplier_ledger_for_lot(NEW.id, 'INSERT');
    END IF;
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- B2. Ensure trigger exists (CASCADE may have dropped it)
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_on_lot_receipt_saved') THEN
    CREATE TRIGGER trg_on_lot_receipt_saved
      AFTER INSERT OR UPDATE OR DELETE ON public.lot_receipts
      FOR EACH ROW EXECUTE FUNCTION public.fn_on_harvest_receipt_saved();
  END IF;
END $$;

-- ============================================================
-- C. Clean up existing bad data from draft lots
-- ============================================================

-- Remove station_products created by draft lots
DELETE FROM station_products sp
USING lot_receipts lr
WHERE sp.product_name = 'Lot-' || lr.lot_number
  AND lr.is_confirmed = false
  AND sp.station_id = lr.station_id
  AND sp.fruit_type_id = lr.fruit_type_id;

-- Remove ledger_entries created by draft lots
DELETE FROM ledger_entries le
USING lot_receipts lr
WHERE le.entity_type = 'supplier'
  AND le.reference_type IN ('lot_receipt', 'lot_receipt_payment')
  AND le.reference_text = lr.id::TEXT
  AND lr.is_confirmed = false;

-- Reverse supplier outstanding_balance for draft lots
UPDATE suppliers s
SET outstanding_balance = COALESCE(outstanding_balance, 0) - COALESCE(lr.total_fruit_cost, 0)
FROM lot_receipts lr
WHERE s.id = lr.supplier_id
  AND lr.is_confirmed = false
  AND COALESCE(lr.total_fruit_cost, 0) > 0;

-- Fix existing confirmed lots: re-sync their credit ledger entries with correct currency
-- (debit entries were created by LotPaymentService with correct currency, so keep them)
DELETE FROM ledger_entries le
WHERE le.entity_type = 'supplier'
  AND le.reference_type = 'lot_receipt'
  AND EXISTS (
    SELECT 1 FROM lot_receipts lr
    WHERE lr.id::TEXT = le.reference_text
      AND lr.is_confirmed = true
  );

-- Re-create credit entries with correct currency
INSERT INTO ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_text, description)
SELECT
  'supplier',
  lr.supplier_id::TEXT,
  'credit',
  COALESCE(lr.total_fruit_cost, 0),
  COALESCE(lr.currency, 'EGP'),
  'lot_receipt',
  lr.id::TEXT,
  'شراء محصول خام - إذن رقم ' || lr.lot_number::TEXT
FROM lot_receipts lr
WHERE lr.is_confirmed = true
  AND COALESCE(lr.total_fruit_cost, 0) > 0;

-- Recalculate supplier outstanding_balance from all confirmed lots
-- First, set it to initial_balance
UPDATE suppliers s
SET outstanding_balance = COALESCE(s.initial_balance, 0);

-- Then add all confirmed lot credits and subtract debits
UPDATE suppliers s
SET outstanding_balance = COALESCE(s.outstanding_balance, 0) + lot_diff.total
FROM (
  SELECT
    lr.supplier_id,
    COALESCE(SUM(lr.total_fruit_cost), 0) - COALESCE(SUM(lr.paid_amount), 0) AS total
  FROM lot_receipts lr
  WHERE lr.is_confirmed = true
  GROUP BY lr.supplier_id
) lot_diff
WHERE s.id = lot_diff.supplier_id;

-- Also add purchase invoice outstanding (if any confirmed purchase invoices exist)
UPDATE suppliers s
SET outstanding_balance = COALESCE(s.outstanding_balance, 0) + pi_diff.total
FROM (
  SELECT
    pi.supplier_id,
    COALESCE(SUM(pi.total_amount - pi.paid_amount), 0) AS total
  FROM purchase_invoices pi
  WHERE pi.status = 'confirmed'
  GROUP BY pi.supplier_id
) pi_diff
WHERE s.id = pi_diff.supplier_id;

-- Refresh PostgREST schema cache
NOTIFY pgrst, 'reload schema';
