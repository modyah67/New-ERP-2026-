-- ============================================================================
-- 080_lot_receipt_enterprise_journal_entries.sql
--
-- Integrates Lot / Harvest Purchases with the Unified Enterprise Accounting Engine:
-- 1. Adds journal_entry_id to lot_receipts
-- 2. Registers 'lot_receipt' document type in sys_document_types
-- 3. Updates sync_supplier_ledger_for_lot to post double-entry GL (Dr. 1030, Cr. Supplier)
-- 4. Updates rpc_edit_lot_price to sync GL journal entries on price changes
-- 5. Updates fn_on_harvest_receipt_saved trigger to prevent recursion
-- 6. Backfills existing confirmed lot receipts
-- ============================================================================

BEGIN;

-- 1. Add journal_entry_id column to lot_receipts
ALTER TABLE public.lot_receipts 
ADD COLUMN IF NOT EXISTS journal_entry_id BIGINT REFERENCES public.journal_entries(id) ON DELETE SET NULL;

-- 2. Register document type for lot purchases
INSERT INTO public.sys_document_types (code, name, prefix)
VALUES ('lot_receipt', 'شراء محصول', 'LOT')
ON CONFLICT (code) DO UPDATE 
SET name = EXCLUDED.name, 
    prefix = EXCLUDED.prefix;

-- 3. Enterprise GL sync function for Lot Receipts
DROP FUNCTION IF EXISTS public.sync_supplier_ledger_for_lot(bigint, text) CASCADE;
DROP FUNCTION IF EXISTS public.sync_supplier_ledger_for_lot(bigint) CASCADE;

CREATE OR REPLACE FUNCTION public.sync_supplier_ledger_for_lot(
  p_lot_id BIGINT,
  p_action TEXT DEFAULT 'INSERT'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lot RECORD;
  v_total_cost NUMERIC;
  v_desc TEXT;
  v_product_name TEXT;
  v_company_id UUID;
  v_supplier_leaf_account_id BIGINT;
  v_inventory_account_id BIGINT;
  v_total_egp NUMERIC;
  v_je_id BIGINT;
  v_existing_je_id BIGINT;
BEGIN
  SELECT lr.* INTO v_lot FROM lot_receipts lr WHERE lr.id = p_lot_id;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  v_product_name := COALESCE(v_lot.product_name, 'محصول');
  v_total_cost := COALESCE(v_lot.total_fruit_cost, 0);
  v_existing_je_id := v_lot.journal_entry_id;

  -- =========================================================================
  -- 1. HANDLE DELETE OPERATION
  -- =========================================================================
  IF p_action = 'DELETE' THEN
    -- A. Revert legacy supplier ledger entry
    DELETE FROM ledger_entries
    WHERE reference_type = 'lot_receipt'
      AND reference_text = p_lot_id::TEXT;

    -- B. Update legacy supplier outstanding balance
    IF v_lot.supplier_id IS NOT NULL THEN
      UPDATE suppliers
      SET outstanding_balance = COALESCE((
        SELECT COALESCE(SUM(CASE WHEN entry_type = 'credit' THEN amount ELSE -amount END), 0)
        FROM ledger_entries
        WHERE entity_type = 'supplier' AND entity_id = v_lot.supplier_id::TEXT
      ), 0),
      updated_at = now()
      WHERE id = v_lot.supplier_id;
    END IF;

    -- C. Delete existing enterprise journal entry & ledger lines
    IF v_existing_je_id IS NOT NULL THEN
      DELETE FROM account_ledger_entries WHERE journal_entry_id = v_existing_je_id;
      DELETE FROM journal_entries WHERE id = v_existing_je_id;
      UPDATE lot_receipts SET journal_entry_id = NULL WHERE id = p_lot_id;
    ELSE
      FOR v_je_id IN
        SELECT id FROM journal_entries WHERE source_type = 'lot_receipt' AND source_id = p_lot_id::TEXT
      LOOP
        DELETE FROM account_ledger_entries WHERE journal_entry_id = v_je_id;
        DELETE FROM journal_entries WHERE id = v_je_id;
      END LOOP;
    END IF;

    RETURN;
  END IF;

  -- =========================================================================
  -- 2. HANDLE INSERT OR UPDATE OPERATION
  -- =========================================================================
  IF p_action IN ('INSERT', 'UPDATE') THEN
    -- A. Clean up old entries if any exist
    IF v_existing_je_id IS NOT NULL THEN
      DELETE FROM account_ledger_entries WHERE journal_entry_id = v_existing_je_id;
      DELETE FROM journal_entries WHERE id = v_existing_je_id;
      v_existing_je_id := NULL;
    ELSE
      FOR v_je_id IN
        SELECT id FROM journal_entries WHERE source_type = 'lot_receipt' AND source_id = p_lot_id::TEXT
      LOOP
        DELETE FROM account_ledger_entries WHERE journal_entry_id = v_je_id;
        DELETE FROM journal_entries WHERE id = v_je_id;
      END LOOP;
    END IF;

    DELETE FROM ledger_entries
    WHERE reference_type = 'lot_receipt'
      AND reference_text = p_lot_id::TEXT;

    -- B. Insert legacy ledger entry & update supplier balance
    IF v_lot.supplier_id IS NOT NULL AND v_total_cost > 0 THEN
      v_desc := 'شراء محصول خام ' || v_product_name || ' - لوط رقم: ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT);
      INSERT INTO ledger_entries (
        entity_type, entity_id, entry_type, amount,
        currency, reference_type, reference_text, description, created_by
      ) VALUES (
        'supplier', v_lot.supplier_id::TEXT, 'credit', v_total_cost,
        COALESCE(v_lot.currency, 'EGP'), 'lot_receipt', p_lot_id::TEXT, v_desc, auth.uid()
      );

      UPDATE suppliers
      SET outstanding_balance = COALESCE((
        SELECT COALESCE(SUM(CASE WHEN entry_type = 'credit' THEN amount ELSE -amount END), 0)
        FROM ledger_entries
        WHERE entity_type = 'supplier' AND entity_id = v_lot.supplier_id::TEXT
      ), 0),
      updated_at = now()
      WHERE id = v_lot.supplier_id;
    END IF;

    -- C. Post Enterprise Double-Entry Journal Entry
    IF v_total_cost > 0 THEN
      -- Resolve company
      SELECT a.company_id INTO v_company_id
      FROM accounts a
      WHERE a.account_code = '1030'
      LIMIT 1;

      IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
      END IF;

      -- Resolve inventory leaf account (1030 - المخزون)
      SELECT a.id INTO v_inventory_account_id
      FROM accounts a
      WHERE a.account_code = '1030' AND a.company_id = v_company_id
      LIMIT 1;

      IF v_inventory_account_id IS NULL THEN
        SELECT a.id INTO v_inventory_account_id
        FROM accounts a
        WHERE a.account_code = '1030'
        LIMIT 1;
      END IF;

      -- Resolve supplier leaf account
      v_supplier_leaf_account_id := NULL;
      IF v_lot.supplier_id IS NOT NULL THEN
        SELECT s.account_id INTO v_supplier_leaf_account_id
        FROM suppliers s
        WHERE s.id = v_lot.supplier_id;
      END IF;

      IF v_supplier_leaf_account_id IS NULL THEN
        SELECT a.id INTO v_supplier_leaf_account_id
        FROM accounts a
        WHERE a.account_code = '2000' AND a.company_id = v_company_id
        LIMIT 1;

        IF v_supplier_leaf_account_id IS NULL THEN
          SELECT a.id INTO v_supplier_leaf_account_id
          FROM accounts a
          WHERE a.account_code = '2000'
          LIMIT 1;
        END IF;
      END IF;

      IF v_inventory_account_id IS NOT NULL AND v_supplier_leaf_account_id IS NOT NULL THEN
        v_total_egp := v_total_cost * COALESCE(NULLIF(v_lot.exchange_rate, 0), 1.0);
        v_desc := 'شراء محصول خام ' || v_product_name || ' - لوط رقم: ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT);

        v_je_id := public.post_journal_entry(
          p_company_id := v_company_id,
          p_entry_date := COALESCE(v_lot.receipt_date, CURRENT_DATE),
          p_source_type := 'lot_receipt',
          p_description := v_desc,
          p_created_by := auth.uid(),
          p_lines := jsonb_build_array(
            jsonb_build_object(
              'account_id', v_inventory_account_id,
              'debit', v_total_egp,
              'credit', 0,
              'currency', COALESCE(v_lot.currency, 'EGP'),
              'description', 'شراء محصول رقم ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT)
            ),
            jsonb_build_object(
              'account_id', v_supplier_leaf_account_id,
              'debit', 0,
              'credit', v_total_egp,
              'currency', COALESCE(v_lot.currency, 'EGP'),
              'description', 'مستحقات مورد عن شراء محصول رقم ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT)
            )
          )
        );

        UPDATE journal_entries
        SET source_id = p_lot_id::TEXT
        WHERE id = v_je_id;

        UPDATE lot_receipts
        SET journal_entry_id = v_je_id
        WHERE id = p_lot_id;
      END IF;
    END IF;
  END IF;
END;
$$;

-- 4. Update Trigger Function to avoid infinite recursion
CREATE OR REPLACE FUNCTION public.fn_on_harvest_receipt_saved()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.is_confirmed = true THEN
      PERFORM public.sync_supplier_ledger_for_lot(OLD.id, 'DELETE');
    END IF;
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    -- If only journal_entry_id changed, skip to prevent recursive triggers
    IF (OLD.journal_entry_id IS DISTINCT FROM NEW.journal_entry_id)
       AND (OLD.is_confirmed = NEW.is_confirmed)
       AND (OLD.total_fruit_cost = NEW.total_fruit_cost)
       AND (OLD.supplier_id IS NOT DISTINCT FROM NEW.supplier_id) THEN
      RETURN NEW;
    END IF;

    IF OLD.is_confirmed = true AND (NEW.is_confirmed = false OR NEW.is_confirmed IS NULL) THEN
      PERFORM public.sync_supplier_ledger_for_lot(OLD.id, 'DELETE');
    ELSIF NEW.is_confirmed = true THEN
      PERFORM public.sync_supplier_ledger_for_lot(NEW.id, 'UPDATE');
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.is_confirmed = true THEN
      PERFORM public.sync_supplier_ledger_for_lot(NEW.id, 'INSERT');
    END IF;
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Ensure trigger is attached
DROP TRIGGER IF EXISTS trg_on_harvest_receipt_saved ON public.lot_receipts;
CREATE TRIGGER trg_on_harvest_receipt_saved
  AFTER INSERT OR UPDATE OR DELETE ON public.lot_receipts
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_on_harvest_receipt_saved();

-- 5. Update rpc_edit_lot_price to keep GL entries synced
DROP FUNCTION IF EXISTS public.rpc_edit_lot_price CASCADE;

CREATE OR REPLACE FUNCTION public.rpc_edit_lot_price(
  p_lot_id BIGINT,
  p_new_price NUMERIC,
  p_exchange_rate NUMERIC,
  p_currency TEXT,
  p_user_id UUID DEFAULT auth.uid()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lot RECORD;
  v_new_total_cost NUMERIC;
  v_old_total_cost NUMERIC;
  v_effective_cost NUMERIC;
  v_total_graded NUMERIC := 0;
  v_grading RECORD;
  v_batch_number TEXT;
  v_net_wt NUMERIC;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'غير مصرح لك بتعديل سعر المحصول';
  END IF;

  SELECT lr.* INTO v_lot FROM lot_receipts lr WHERE lr.id = p_lot_id FOR UPDATE OF lr;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'رقم المحصول غير موجود (id=%)', p_lot_id;
  END IF;

  v_old_total_cost := COALESCE(v_lot.total_fruit_cost, 0);
  v_net_wt := COALESCE(NULLIF(v_lot.net_weight_kg, 0), v_lot.gross_weight_kg, 0);

  IF COALESCE(v_lot.purchase_mode, 'weight') = 'carton' THEN
    v_new_total_cost := COALESCE(v_lot.carton_count, 0) * p_new_price;
    UPDATE lot_receipts 
    SET price_per_carton = p_new_price,
        fruit_cost_per_kg = CASE WHEN v_net_wt > 0 THEN v_new_total_cost / v_net_wt ELSE p_new_price END,
        exchange_rate = p_exchange_rate,
        currency = p_currency,
        total_fruit_cost = v_new_total_cost,
        updated_at = now()
    WHERE id = p_lot_id;
  ELSE
    v_new_total_cost := COALESCE(v_lot.gross_weight_kg, 0) * p_new_price;
    UPDATE lot_receipts 
    SET fruit_cost_per_kg = CASE WHEN v_net_wt > 0 THEN v_new_total_cost / v_net_wt ELSE p_new_price END,
        exchange_rate = p_exchange_rate,
        currency = p_currency,
        total_fruit_cost = v_new_total_cost,
        updated_at = now()
    WHERE id = p_lot_id;
  END IF;

  -- Sync GL entries and supplier balance if confirmed
  IF v_lot.is_confirmed = true THEN
    PERFORM public.sync_supplier_ledger_for_lot(p_lot_id, 'UPDATE');
  END IF;

  SELECT COALESCE(SUM(weight_kg), 0) INTO v_total_graded
  FROM lot_grading_results
  WHERE lot_id = p_lot_id AND grade IN ('A','B','C') AND weight_kg > 0;

  v_effective_cost := CASE WHEN v_total_graded > 0 THEN v_new_total_cost / v_total_graded ELSE 0 END;

  FOR v_grading IN
    SELECT id, grade, weight_kg, stock_batch_id FROM lot_grading_results
    WHERE lot_id = p_lot_id AND grade IN ('A','B','C') AND weight_kg > 0
  LOOP
    v_batch_number := 'G-' || v_lot.lot_number || '-' || v_grading.grade;
    UPDATE stock_batches 
    SET purchase_cost = v_effective_cost,
        updated_at = now()
    WHERE batch_number = v_batch_number;
  END LOOP;

  PERFORM public.rpc_update_packing_costs_for_lot(p_lot_id);

  RETURN jsonb_build_object(
    'success', true,
    'lot_id', p_lot_id,
    'new_total_cost', v_new_total_cost,
    'effective_cost', v_effective_cost
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$$;

-- 6. Backfill existing confirmed lot receipts
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN 
    SELECT id FROM lot_receipts 
    WHERE is_confirmed = true 
      AND (journal_entry_id IS NULL OR NOT EXISTS (SELECT 1 FROM journal_entries WHERE id = lot_receipts.journal_entry_id))
  LOOP
    BEGIN
      PERFORM public.sync_supplier_ledger_for_lot(r.id, 'UPDATE');
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Skipping lot_receipt % due to error: %', r.id, SQLERRM;
    END;
  END LOOP;
END;
$$;

COMMIT;
