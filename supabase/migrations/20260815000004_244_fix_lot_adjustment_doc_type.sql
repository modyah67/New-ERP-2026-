BEGIN;

-- Fix the incorrect document type 'lot_adjustment' to 'lot_price_adjustment' in sync_supplier_ledger_for_lot
DROP FUNCTION IF EXISTS public.sync_supplier_ledger_for_lot(BIGINT, TEXT);

CREATE OR REPLACE FUNCTION public.sync_supplier_ledger_for_lot(p_lot_id BIGINT, p_action TEXT DEFAULT 'UPDATE')
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lot RECORD;
  v_total_cost NUMERIC;
  v_company_id UUID;
  v_inventory_account_id BIGINT;
  v_supplier_account_id BIGINT;
  v_je_id BIGINT;
  v_je_desc TEXT;
  
  v_old_debit NUMERIC := 0;
  v_old_base_debit NUMERIC := 0;
  v_delta_debit NUMERIC := 0;
  v_delta_base_debit NUMERIC := 0;
  
  v_base_total_cost NUMERIC;
BEGIN
  SELECT * INTO v_lot FROM lot_receipts WHERE id = p_lot_id;
  IF NOT FOUND THEN RETURN; END IF;

  v_total_cost := COALESCE(v_lot.total_fruit_cost, 0);

  IF p_action = 'DELETE' THEN
      SELECT journal_entry_id INTO v_je_id FROM lot_receipts WHERE id = p_lot_id;
      IF v_je_id IS NOT NULL THEN
        DELETE FROM journal_entries
        WHERE source_type IN ('lot_receipt', 'lot_price_adjustment', 'lot_adjustment')
          AND source_id = p_lot_id::TEXT;
  
        UPDATE lot_receipts
        SET journal_entry_id = NULL
        WHERE id = p_lot_id;
      END IF;
      RETURN;
  END IF;

  IF COALESCE(v_lot.is_confirmed, false) = true THEN
      SELECT a.company_id INTO v_company_id
      FROM accounts a WHERE a.account_code = '1030' LIMIT 1;
      IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
      END IF;

      v_inventory_account_id := public.resolve_gl_account('1030', v_company_id);
      
      v_supplier_account_id := NULL;
      IF v_lot.supplier_id IS NOT NULL THEN
        SELECT account_id INTO v_supplier_account_id
        FROM suppliers WHERE id = v_lot.supplier_id;
      END IF;
      IF v_supplier_account_id IS NULL THEN
        v_supplier_account_id := public.resolve_gl_account('2000', v_company_id);
      END IF;

      v_base_total_cost := v_total_cost * COALESCE(v_lot.exchange_rate, 1.0);

      IF p_action = 'INSERT' OR (p_action = 'UPDATE' AND v_lot.journal_entry_id IS NULL) THEN
           v_je_desc := 'شراء محصول - لوط رقم: ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT);
           
           v_je_id := public.post_journal_entry(
              p_source_type := 'lot_receipt',
              p_description := v_je_desc,
              p_entry_date := COALESCE(v_lot.receipt_date, CURRENT_DATE),
              p_company_id := v_company_id,
              p_user_id := auth.uid(),
              p_lines := jsonb_build_array(
                  jsonb_build_object('account_id', v_inventory_account_id, 'debit', v_total_cost, 'credit', 0, 'base_debit', v_base_total_cost, 'base_credit', 0, 'currency', COALESCE(v_lot.currency, 'EGP'), 'description', v_je_desc),
                  jsonb_build_object('account_id', v_supplier_account_id, 'debit', 0, 'credit', v_total_cost, 'base_debit', 0, 'base_credit', v_base_total_cost, 'currency', COALESCE(v_lot.currency, 'EGP'), 'description', v_je_desc)
              ),
              p_source_id := p_lot_id::TEXT
           );
           UPDATE lot_receipts SET journal_entry_id = v_je_id WHERE id = p_lot_id;

      ELSIF p_action = 'UPDATE' THEN
            SELECT COALESCE(SUM(debit), 0), COALESCE(SUM(base_debit), 0) INTO v_old_debit, v_old_base_debit
            FROM account_ledger_entries
            WHERE journal_entry_id IN (
               SELECT id FROM journal_entries 
               WHERE source_type IN ('lot_receipt', 'lot_price_adjustment', 'lot_adjustment') AND source_id = p_lot_id::TEXT
            ) AND account_id = v_inventory_account_id;
  
            v_delta_debit := v_total_cost - v_old_debit;
            v_delta_base_debit := v_base_total_cost - v_old_base_debit;
            
            IF ABS(v_delta_debit) >= 0.01 OR ABS(v_delta_base_debit) >= 0.01 THEN
               v_je_desc := 'تسوية سعر المحصول - لوط رقم: ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT);
               
               v_je_id := public.post_journal_entry(
                  p_source_type := 'lot_price_adjustment',
                  p_description := v_je_desc,
                  p_entry_date := COALESCE(v_lot.receipt_date, CURRENT_DATE),
                  p_company_id := v_company_id,
                  p_user_id := auth.uid(),
                  p_lines := CASE 
                      WHEN v_delta_debit > 0 THEN 
                          jsonb_build_array(
                              jsonb_build_object('account_id', v_inventory_account_id, 'debit', v_delta_debit, 'credit', 0, 'base_debit', v_delta_base_debit, 'base_credit', 0, 'currency', COALESCE(v_lot.currency, 'EGP'), 'description', v_je_desc),
                              jsonb_build_object('account_id', v_supplier_account_id, 'debit', 0, 'credit', v_delta_debit, 'base_debit', 0, 'base_credit', v_delta_base_debit, 'currency', COALESCE(v_lot.currency, 'EGP'), 'description', v_je_desc)
                          )
                      ELSE 
                          jsonb_build_array(
                              jsonb_build_object('account_id', v_inventory_account_id, 'debit', 0, 'credit', ABS(v_delta_debit), 'base_debit', 0, 'base_credit', ABS(v_delta_base_debit), 'currency', COALESCE(v_lot.currency, 'EGP'), 'description', v_je_desc),
                              jsonb_build_object('account_id', v_supplier_account_id, 'debit', ABS(v_delta_debit), 'credit', 0, 'base_debit', ABS(v_delta_base_debit), 'base_credit', 0, 'currency', COALESCE(v_lot.currency, 'EGP'), 'description', v_je_desc)
                          )
                  END,
                  p_source_id := p_lot_id::TEXT
               );
            END IF;
      END IF;
  END IF;
END;
$$;

-- Also fix any journal entries that were incorrectly written as 'lot_adjustment' 
UPDATE journal_entries SET source_type = 'lot_price_adjustment' WHERE source_type = 'lot_adjustment';

COMMIT;
