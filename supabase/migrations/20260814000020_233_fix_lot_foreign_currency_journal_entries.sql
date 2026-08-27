-- Migration 233: Fix LOT receipts foreign currency bug in journal entries

BEGIN;

CREATE OR REPLACE FUNCTION public.sync_supplier_ledger_for_lot(
  p_lot_id UUID,
  p_action TEXT DEFAULT 'INSERT'
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lot RECORD;
  v_company_id UUID;
  v_je_id BIGINT;
  v_supplier_leaf_account_id BIGINT;
  v_inventory_account_id BIGINT;
  v_total_cost NUMERIC;
  v_total_egp NUMERIC;
  v_desc TEXT;
  v_product_name TEXT;
  v_old_je_id BIGINT;
BEGIN
  -- 1. Get the lot record
  SELECT l.* INTO v_lot
  FROM lot_receipts l
  WHERE l.id = p_lot_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  v_old_je_id := v_lot.journal_entry_id;

  -- 2. Handle DELETE or reversal
  IF p_action = 'DELETE' OR (v_lot.is_confirmed = false OR v_lot.is_confirmed IS NULL) THEN
    IF v_old_je_id IS NOT NULL THEN
      UPDATE journal_entries SET deleted_at = now() WHERE id = v_old_je_id;
      UPDATE account_ledger_entries SET deleted_at = now() WHERE journal_entry_id = v_old_je_id;
      
      UPDATE lot_receipts SET journal_entry_id = NULL WHERE id = p_lot_id;
    END IF;
    RETURN;
  END IF;

  -- 3. Handle INSERT or UPDATE (when confirmed)
  IF p_action IN ('INSERT', 'UPDATE') AND v_lot.is_confirmed = true THEN
    -- If there's an existing JE, mark it deleted to recreate a fresh one
    IF v_old_je_id IS NOT NULL THEN
      UPDATE journal_entries SET deleted_at = now() WHERE id = v_old_je_id;
      UPDATE account_ledger_entries SET deleted_at = now() WHERE journal_entry_id = v_old_je_id;
    END IF;

    v_total_cost := COALESCE(v_lot.total_fruit_cost, 0);

    IF v_total_cost > 0 THEN
      -- Resolve company
      SELECT r.company_id, r.name INTO v_company_id, v_product_name
      FROM raw_materials r
      WHERE r.id = v_lot.raw_material_id;

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
              'debit', v_total_cost,
              'base_debit', v_total_egp,
              'credit', 0,
              'base_credit', 0,
              'currency', COALESCE(v_lot.currency, 'EGP'),
              'description', 'شراء محصول رقم ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT)
            ),
            jsonb_build_object(
              'account_id', v_supplier_leaf_account_id,
              'debit', 0,
              'base_debit', 0,
              'credit', v_total_cost,
              'base_credit', v_total_egp,
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

COMMIT;
