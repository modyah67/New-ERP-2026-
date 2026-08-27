-- Migration 113: Lot Price Adjustment GL Entry + dropdown support
--
-- 1. Update rpc_edit_lot_price to create price adjustment journal entry
-- 2. Update rpc_get_lot_journal_entries to include lot_price_adjustment
-- 3. Register lot_price_adjustment document type

BEGIN;

-- 1. Register document type
INSERT INTO sys_document_types (code, name, prefix)
VALUES ('lot_price_adjustment', 'Lot Price Adjustment', 'LPAD')
ON CONFLICT (code) DO NOTHING;

-- 2. Updated rpc_edit_lot_price — creates price adjustment GL entry
DROP FUNCTION IF EXISTS public.rpc_edit_lot_price(BIGINT, NUMERIC, NUMERIC, TEXT, UUID);

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
  v_delta NUMERIC;
  v_effective_cost NUMERIC;
  v_total_graded NUMERIC := 0;
  v_grading RECORD;
  v_batch_number TEXT;
  v_net_wt NUMERIC;
  v_company_id UUID;
  v_inventory_account_id BIGINT;
  v_supplier_account_id BIGINT;
  v_desc TEXT;
  v_product_name TEXT;
  v_je_id BIGINT;
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

    -- Create price adjustment journal entry (delta-based)
    v_delta := v_new_total_cost - v_old_total_cost;
    IF v_delta != 0 THEN
      v_product_name := COALESCE(v_lot.product_name, 'محصول');

      SELECT a.company_id INTO v_company_id
      FROM accounts a WHERE a.account_code = '1030' LIMIT 1;
      IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
      END IF;

      -- Inventory account (1030)
      v_inventory_account_id := public.resolve_gl_account('1030', v_company_id);

      -- Supplier account
      v_supplier_account_id := NULL;
      IF v_lot.supplier_id IS NOT NULL THEN
        SELECT account_id INTO v_supplier_account_id
        FROM suppliers WHERE id = v_lot.supplier_id;
      END IF;
      IF v_supplier_account_id IS NULL THEN
        v_supplier_account_id := public.resolve_gl_account('2000', v_company_id);
      END IF;

      v_desc := 'تعديل سعر المحصول ' || v_product_name
                || ' — لوط رقم ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT)
                || ' (الفرق: ' || v_delta::TEXT || ' ' || COALESCE(p_currency, 'EGP') || ')';

      IF v_delta > 0 THEN
        v_je_id := public.post_journal_entry(
          'lot_price_adjustment',
          v_desc,
          CURRENT_DATE,
          v_company_id,
          p_user_id,
          jsonb_build_array(
            jsonb_build_object('account_id', v_inventory_account_id, 'debit', v_delta, 'credit', 0, 'currency', COALESCE(p_currency, 'EGP'), 'description', v_desc),
            jsonb_build_object('account_id', v_supplier_account_id, 'debit', 0, 'credit', v_delta, 'currency', COALESCE(p_currency, 'EGP'), 'description', v_desc)
          ),
          p_lot_id::TEXT
        );
      ELSE
        v_je_id := public.post_journal_entry(
          'lot_price_adjustment',
          v_desc,
          CURRENT_DATE,
          v_company_id,
          p_user_id,
          jsonb_build_array(
            jsonb_build_object('account_id', v_supplier_account_id, 'debit', ABS(v_delta), 'credit', 0, 'currency', COALESCE(p_currency, 'EGP'), 'description', v_desc),
            jsonb_build_object('account_id', v_inventory_account_id, 'debit', 0, 'credit', ABS(v_delta), 'currency', COALESCE(p_currency, 'EGP'), 'description', v_desc)
          ),
          p_lot_id::TEXT
        );
      END IF;
    END IF;
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
    'effective_cost', v_effective_cost,
    'journal_entry_id', v_je_id
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_edit_lot_price(BIGINT, NUMERIC, NUMERIC, TEXT, UUID) TO authenticated;

-- 3. Update rpc_get_lot_journal_entries to include lot_price_adjustment
DROP FUNCTION IF EXISTS public.rpc_get_lot_journal_entries(TEXT);

CREATE OR REPLACE FUNCTION public.rpc_get_lot_journal_entries(
  p_lot_id TEXT
)
RETURNS TABLE (
  journal_entry_id BIGINT,
  entry_number     TEXT,
  entry_date       DATE,
  description      TEXT,
  source_type      TEXT,
  source_id        TEXT,
  total_debit      NUMERIC,
  total_credit     NUMERIC,
  currency         TEXT,
  created_at       TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lot_number TEXT;
BEGIN
  SELECT lot_number INTO v_lot_number
  FROM lot_receipts WHERE id::TEXT = p_lot_id;

  RETURN QUERY
  SELECT DISTINCT ON (je.id)
    je.id AS journal_entry_id,
    je.entry_number,
    je.entry_date,
    je.description,
    je.source_type,
    je.source_id,
    COALESCE(SUM(ale.debit) OVER (PARTITION BY je.id), 0) AS total_debit,
    COALESCE(SUM(ale.credit) OVER (PARTITION BY je.id), 0) AS total_credit,
    (SELECT ale2.currency FROM public.account_ledger_entries ale2
     WHERE ale2.journal_entry_id = je.id AND ale2.currency IS NOT NULL
     ORDER BY ale2.id LIMIT 1) AS currency,
    je.created_at
  FROM public.journal_entries je
  INNER JOIN public.account_ledger_entries ale ON ale.journal_entry_id = je.id
  WHERE je.deleted_at IS NULL
    AND ale.deleted_at IS NULL
    AND (
      -- Match by source_id (lot_receipt + lot_price_adjustment entries)
      (je.source_id = p_lot_id AND je.source_type IN ('lot_receipt', 'lot_price_adjustment'))
      OR
      -- Match by description containing lot number (payment entries)
      (v_lot_number IS NOT NULL AND v_lot_number != ''
       AND je.description LIKE '%لوت رقم ' || v_lot_number || '%'
       AND je.source_type IN ('custody_expense', 'bank_expense'))
    )
  ORDER BY je.id, je.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_lot_journal_entries(TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
