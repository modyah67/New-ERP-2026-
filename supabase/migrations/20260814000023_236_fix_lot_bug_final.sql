BEGIN;

-- 1. Restore post_journal_entry to its correct signature
DROP FUNCTION IF EXISTS public.post_journal_entry(bigint, date, text, text, text, jsonb, uuid) CASCADE;

CREATE OR REPLACE FUNCTION public.post_journal_entry(
    p_source_type   TEXT,
    p_description   TEXT,
    p_entry_date    DATE,
    p_company_id    UUID,
    p_created_by    UUID,
    p_lines         JSONB,
    p_source_id     TEXT DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_je_id         BIGINT;
    v_entry_number  TEXT;
    v_total_debit   NUMERIC := 0;
    v_total_credit  NUMERIC := 0;
    v_line          JSONB;
    v_account_id    BIGINT;
    v_debit         NUMERIC;
    v_credit        NUMERIC;
    v_base_debit    NUMERIC;
    v_base_credit   NUMERIC;
    v_currency      TEXT;
    v_desc          TEXT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys_companies WHERE id = p_company_id) THEN
        RAISE EXCEPTION 'Company % not found', p_company_id;
    END IF;

    v_entry_number := public.fn_get_next_sequence(p_company_id, p_source_type, NULL, NULL);

    INSERT INTO journal_entries (
        entry_number, entry_date, description, status,
        is_auto_generated, source_type, source_id, created_by, company_id
    ) VALUES (
        v_entry_number, p_entry_date, p_description, 'posted',
        true, p_source_type, p_source_id, p_created_by, p_company_id
    ) RETURNING id INTO v_je_id;

    FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines)
    LOOP
        v_account_id := (v_line->>'account_id')::BIGINT;
        v_debit      := COALESCE((v_line->>'debit')::NUMERIC, 0);
        v_credit     := COALESCE((v_line->>'credit')::NUMERIC, 0);
        v_base_debit := COALESCE((v_line->>'base_debit')::NUMERIC, v_debit);
        v_base_credit:= COALESCE((v_line->>'base_credit')::NUMERIC, v_credit);
        v_currency   := COALESCE(v_line->>'currency', 'EGP');
        v_desc       := COALESCE(v_line->>'description', p_description);

        IF NOT EXISTS (SELECT 1 FROM accounts WHERE id = v_account_id) THEN
            RAISE EXCEPTION 'GL Account ID % not found in accounts table', v_account_id;
        END IF;

        IF v_debit < 0 OR v_credit < 0 THEN
            RAISE EXCEPTION 'Debit and credit amounts must be non-negative';
        END IF;
        IF v_debit = 0 AND v_credit = 0 THEN
            RAISE EXCEPTION 'Both debit and credit cannot be zero for a single line';
        END IF;
        IF v_debit > 0 AND v_credit > 0 THEN
            RAISE EXCEPTION 'A single line cannot have both debit and credit';
        END IF;

        v_total_debit  := v_total_debit + v_base_debit;
        v_total_credit := v_total_credit + v_base_credit;

        INSERT INTO account_ledger_entries (
            journal_entry_id, account_id, debit, credit,
            currency, amount_in_base_currency, description, company_id
        ) VALUES (
            v_je_id, v_account_id, v_debit, v_credit,
            v_currency, COALESCE(v_base_debit, 0) + COALESCE(v_base_credit, 0), v_desc, p_company_id
        );
    END LOOP;

    IF v_total_debit != v_total_credit THEN
        RAISE EXCEPTION 'Journal entry is not balanced: total debit % != total credit %', v_total_debit, v_total_credit;
    END IF;

    RETURN v_je_id;
END;
$$;

-- 2. Update sync_supplier_ledger_for_lot
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
  v_company_id UUID;
  v_inventory_account_id BIGINT;
  v_supplier_leaf_account_id BIGINT;
  v_je_id BIGINT;
  v_desc TEXT;
  v_total_cost NUMERIC;
  v_product_name TEXT;
  v_total_egp NUMERIC;
  v_old_debit NUMERIC;
  v_old_base_debit NUMERIC;
  v_delta_debit NUMERIC;
  v_delta_base_debit NUMERIC;
  v_je_desc TEXT;
BEGIN
  IF p_action = 'DELETE' THEN
    SELECT journal_entry_id INTO v_je_id FROM lot_receipts WHERE id = p_lot_id;
    IF v_je_id IS NOT NULL THEN
      DELETE FROM journal_entries
      WHERE source_type IN ('lot_receipt', 'lot_adjustment')
        AND source_id = p_lot_id::TEXT;

      UPDATE lot_receipts
      SET journal_entry_id = NULL
      WHERE id = p_lot_id;
    END IF;
  END IF;

  IF p_action = 'INSERT' OR p_action = 'UPDATE' THEN
    SELECT * INTO v_lot FROM lot_receipts WHERE id = p_lot_id;
    
    IF v_lot.is_confirmed = true THEN
      SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
      IF v_company_id IS NULL THEN RETURN; END IF;

      SELECT name INTO v_product_name FROM raw_materials WHERE id = v_lot.fruit_type_id;

      v_total_cost := COALESCE(v_lot.total_fruit_cost, 0);
      v_total_egp := v_total_cost * COALESCE(NULLIF(v_lot.exchange_rate, 0), 1.0);

      SELECT a.id INTO v_inventory_account_id
      FROM accounts a
      WHERE a.account_code = '1030' AND a.company_id = v_company_id
      LIMIT 1;
      IF v_inventory_account_id IS NULL THEN
        SELECT a.id INTO v_inventory_account_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;
      END IF;

      v_supplier_leaf_account_id := NULL;
      IF v_lot.supplier_id IS NOT NULL THEN
        SELECT s.account_id INTO v_supplier_leaf_account_id FROM suppliers s WHERE s.id = v_lot.supplier_id;
      END IF;
      IF v_supplier_leaf_account_id IS NULL THEN
        SELECT a.id INTO v_supplier_leaf_account_id FROM accounts a WHERE a.account_code = '2000' AND a.company_id = v_company_id LIMIT 1;
        IF v_supplier_leaf_account_id IS NULL THEN
          SELECT a.id INTO v_supplier_leaf_account_id FROM accounts a WHERE a.account_code = '2000' LIMIT 1;
        END IF;
      END IF;

      IF v_inventory_account_id IS NOT NULL AND v_supplier_leaf_account_id IS NOT NULL THEN
        
        IF p_action = 'UPDATE' AND v_lot.journal_entry_id IS NOT NULL THEN
          -- Calculate adjustment delta
          SELECT 
            COALESCE(SUM(debit - credit), 0), 
            COALESCE(SUM(amount_in_base_currency * CASE WHEN debit > 0 THEN 1 WHEN credit > 0 THEN -1 ELSE 0 END), 0)
          INTO v_old_debit, v_old_base_debit
          FROM account_ledger_entries
          WHERE journal_entry_id IN (
             SELECT id FROM journal_entries 
             WHERE source_type IN ('lot_receipt', 'lot_adjustment') AND source_id = p_lot_id::TEXT
          ) AND account_id = v_inventory_account_id;

          v_delta_debit := v_total_cost - v_old_debit;
          v_delta_base_debit := v_total_egp - v_old_base_debit;

          IF ABS(v_delta_debit) >= 0.01 OR ABS(v_delta_base_debit) >= 0.01 THEN
             v_je_desc := '????? ????? ??? ?????? - ??? ???: ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT);
             
             v_je_id := public.post_journal_entry(
                p_source_type := 'lot_adjustment',
                p_description := v_je_desc,
                p_entry_date := COALESCE(v_lot.receipt_date, CURRENT_DATE),
                p_company_id := v_company_id,
                p_created_by := auth.uid(),
                p_lines := jsonb_build_array(
                  jsonb_build_object(
                    'account_id', v_inventory_account_id,
                    'debit', CASE WHEN v_delta_debit > 0 THEN v_delta_debit ELSE 0 END,
                    'base_debit', CASE WHEN v_delta_base_debit > 0 THEN v_delta_base_debit ELSE 0 END,
                    'credit', CASE WHEN v_delta_debit < 0 THEN ABS(v_delta_debit) ELSE 0 END,
                    'base_credit', CASE WHEN v_delta_base_debit < 0 THEN ABS(v_delta_base_debit) ELSE 0 END,
                    'currency', COALESCE(v_lot.currency, 'EGP'),
                    'description', v_je_desc
                  ),
                  jsonb_build_object(
                    'account_id', v_supplier_leaf_account_id,
                    'debit', CASE WHEN v_delta_debit < 0 THEN ABS(v_delta_debit) ELSE 0 END,
                    'base_debit', CASE WHEN v_delta_base_debit < 0 THEN ABS(v_delta_base_debit) ELSE 0 END,
                    'credit', CASE WHEN v_delta_debit > 0 THEN v_delta_debit ELSE 0 END,
                    'base_credit', CASE WHEN v_delta_base_debit > 0 THEN v_delta_base_debit ELSE 0 END,
                    'currency', COALESCE(v_lot.currency, 'EGP'),
                    'description', v_je_desc
                  )
                ),
                p_source_id := p_lot_id::TEXT
             );
          END IF;
          
        ELSE
          -- INSERT new original journal entry
          v_desc := '???? ????? ??? ' || v_product_name || ' - ??? ???: ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT);
          v_je_id := public.post_journal_entry(
            p_source_type := 'lot_receipt',
            p_description := v_desc,
            p_entry_date := COALESCE(v_lot.receipt_date, CURRENT_DATE),
            p_company_id := v_company_id,
            p_created_by := auth.uid(),
            p_lines := jsonb_build_array(
              jsonb_build_object(
                'account_id', v_inventory_account_id,
                'debit', v_total_cost,
                'base_debit', v_total_egp,
                'credit', 0,
                'base_credit', 0,
                'currency', COALESCE(v_lot.currency, 'EGP'),
                'description', '???? ????? ??? ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT)
              ),
              jsonb_build_object(
                'account_id', v_supplier_leaf_account_id,
                'debit', 0,
                'base_debit', 0,
                'credit', v_total_cost,
                'base_credit', v_total_egp,
                'currency', COALESCE(v_lot.currency, 'EGP'),
                'description', '??????? ???? ?? ???? ????? ??? ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT)
              )
            ),
            p_source_id := p_lot_id::TEXT
          );

          UPDATE lot_receipts
          SET journal_entry_id = v_je_id
          WHERE id = p_lot_id;
        END IF;

      END IF;
    END IF;
  END IF;
END;
$$;

-- 3. Cleanup Legacy Historical Data
DO $$
DECLARE
  v_je RECORD;
  v_lot RECORD;
  v_exchange_rate NUMERIC;
BEGIN
  FOR v_je IN
    SELECT je.id, je.source_id, je.source_type
    FROM journal_entries je
    WHERE je.source_type IN ('lot_receipt', 'lot_adjustment')
  LOOP
    SELECT * INTO v_lot FROM lot_receipts WHERE id = v_je.source_id::BIGINT;
    IF FOUND AND v_lot.currency != 'EGP' THEN
      v_exchange_rate := COALESCE(NULLIF(v_lot.exchange_rate, 0), 1.0);
      
      IF v_exchange_rate > 1 THEN
        UPDATE account_ledger_entries
        SET amount_in_base_currency = GREATEST(debit, credit),
            debit = debit / v_exchange_rate,
            credit = credit / v_exchange_rate
        WHERE journal_entry_id = v_je.id 
          AND currency != 'EGP'
          AND (debit = amount_in_base_currency OR credit = amount_in_base_currency)
          AND (debit > 0 OR credit > 0);
      END IF;
    END IF;
  END LOOP;
END;
$$;

NOTIFY pgrst, 'reload schema';

COMMIT;
