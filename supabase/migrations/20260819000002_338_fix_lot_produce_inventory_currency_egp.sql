-- Migration 338: Unify Produce Inventory (1030) currency to local base currency (EGP) on Lot Receipts & Returns
-- Description: Ensures account 1030 (Produce Inventory) is always recorded in EGP (local currency), while the supplier account (20000x) stays in the original transaction currency (e.g. USD).

BEGIN;

-- 1. Update sync_supplier_ledger_for_lot
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
  v_old_supplier_cost NUMERIC;
  v_old_base_debit NUMERIC;
  v_delta_foreign NUMERIC;
  v_delta_egp NUMERIC;
  v_je_desc TEXT;
BEGIN
  IF p_action = 'DELETE' THEN
    SELECT * INTO v_lot FROM lot_receipts WHERE id = p_lot_id;
    IF v_lot.journal_entry_id IS NOT NULL THEN
      DELETE FROM journal_entries
      WHERE source_type IN ('lot_receipt', 'lot_price_adjustment')
        AND source_id = p_lot_id::TEXT;

      IF v_lot.supplier_id IS NOT NULL THEN
        UPDATE suppliers
        SET outstanding_balance = COALESCE(outstanding_balance, 0) - COALESCE(v_lot.total_fruit_cost, 0)
        WHERE id = v_lot.supplier_id;
      END IF;

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

      v_product_name := v_lot.product_name;

      v_total_cost := COALESCE(v_lot.total_fruit_cost, 0);
      v_total_egp := v_total_cost * COALESCE(NULLIF(v_lot.exchange_rate, 0), 1.0);

      -- Skip if cost is zero (user hasn't set price yet)
      IF v_total_cost <= 0 THEN RETURN; END IF;

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
          -- Query old base amount on inventory account
          SELECT COALESCE(SUM(amount_in_base_currency * CASE WHEN debit > 0 THEN 1 WHEN credit > 0 THEN -1 ELSE 0 END), 0)
          INTO v_old_base_debit
          FROM account_ledger_entries
          WHERE journal_entry_id IN (
             SELECT id FROM journal_entries 
             WHERE source_type IN ('lot_receipt', 'lot_price_adjustment') AND source_id = p_lot_id::TEXT
          ) AND account_id = v_inventory_account_id;

          -- Query old foreign amount on supplier account
          SELECT COALESCE(SUM(credit - debit), 0)
          INTO v_old_supplier_cost
          FROM account_ledger_entries
          WHERE journal_entry_id IN (
             SELECT id FROM journal_entries 
             WHERE source_type IN ('lot_receipt', 'lot_price_adjustment') AND source_id = p_lot_id::TEXT
          ) AND account_id = v_supplier_leaf_account_id;

          v_delta_foreign := v_total_cost - v_old_supplier_cost;
          v_delta_egp := v_total_egp - v_old_base_debit;

          IF ABS(v_delta_foreign) >= 0.01 OR ABS(v_delta_egp) >= 0.01 THEN
             v_je_desc := 'تأثير تعديل سعر لمحصول - لوط رقم: ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT);
             
             v_je_id := public.post_journal_entry(
                p_source_type := 'lot_price_adjustment',
                p_description := v_je_desc,
                p_entry_date := COALESCE(v_lot.receipt_date, CURRENT_DATE),
                p_company_id := v_company_id,
                p_created_by := auth.uid(),
                p_lines := jsonb_build_array(
                  jsonb_build_object(
                    'account_id', v_inventory_account_id,
                    'debit', CASE WHEN v_delta_egp > 0 THEN v_delta_egp ELSE 0 END,
                    'base_debit', CASE WHEN v_delta_egp > 0 THEN v_delta_egp ELSE 0 END,
                    'credit', CASE WHEN v_delta_egp < 0 THEN ABS(v_delta_egp) ELSE 0 END,
                    'base_credit', CASE WHEN v_delta_egp < 0 THEN ABS(v_delta_egp) ELSE 0 END,
                    'currency', 'EGP',
                    'description', v_je_desc
                  ),
                  jsonb_build_object(
                    'account_id', v_supplier_leaf_account_id,
                    'debit', CASE WHEN v_delta_foreign < 0 THEN ABS(v_delta_foreign) ELSE 0 END,
                    'base_debit', CASE WHEN v_delta_egp < 0 THEN ABS(v_delta_egp) ELSE 0 END,
                    'credit', CASE WHEN v_delta_foreign > 0 THEN v_delta_foreign ELSE 0 END,
                    'base_credit', CASE WHEN v_delta_egp > 0 THEN v_delta_egp ELSE 0 END,
                    'currency', COALESCE(v_lot.currency, 'EGP'),
                    'description', v_je_desc
                  )
                ),
                p_source_id := p_lot_id::TEXT
             );

             IF v_lot.supplier_id IS NOT NULL THEN
                UPDATE suppliers
                SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_delta_foreign
                WHERE id = v_lot.supplier_id;
             END IF;
          END IF;
          
        ELSE
          -- INSERT new original journal entry
          v_desc := 'إثبات شراء ' || COALESCE(v_product_name, 'محصول') || ' - لوط رقم: ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT);
          v_je_id := public.post_journal_entry(
            p_source_type := 'lot_receipt',
            p_description := v_desc,
            p_entry_date := COALESCE(v_lot.receipt_date, CURRENT_DATE),
            p_company_id := v_company_id,
            p_created_by := auth.uid(),
            p_lines := jsonb_build_array(
              jsonb_build_object(
                'account_id', v_inventory_account_id,
                'debit', v_total_egp,
                'base_debit', v_total_egp,
                'credit', 0,
                'base_credit', 0,
                'currency', 'EGP',
                'description', 'إثبات شراء محصول - لوط رقم ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT)
              ),
              jsonb_build_object(
                'account_id', v_supplier_leaf_account_id,
                'debit', 0,
                'base_debit', 0,
                'credit', v_total_cost,
                'base_credit', v_total_egp,
                'currency', COALESCE(v_lot.currency, 'EGP'),
                'description', 'موردين أمانة عن شراء محصول - لوط رقم ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT)
              )
            ),
            p_source_id := p_lot_id::TEXT
          );

          UPDATE lot_receipts
          SET journal_entry_id = v_je_id
          WHERE id = p_lot_id;

          IF v_lot.supplier_id IS NOT NULL THEN
            UPDATE suppliers
            SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_total_cost
            WHERE id = v_lot.supplier_id;
          END IF;
        END IF;

      END IF;
    END IF;
  END IF;
END;
$$;

-- 2. Update rpc_process_lot_return
CREATE OR REPLACE FUNCTION public.rpc_process_lot_return(
  p_lot_id bigint,
  p_return_quantity numeric,
  p_return_price numeric DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_user_id uuid DEFAULT NULL,
  p_batch_id bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lot record;
  v_unit_cost numeric;
  v_return_value numeric;
  v_return_value_egp numeric;
  v_return_id bigint;
  v_target_station bigint;
  v_product_name text;
  v_company_id uuid;
  v_inventory_account_id bigint;
  v_supplier_leaf_account_id bigint;
  v_je_id bigint;
  v_desc text;
BEGIN
  -- 1. Load lot and validate
  SELECT * INTO v_lot FROM lot_receipts WHERE id = p_lot_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'اللوط غير موجود');
  END IF;

  IF v_lot.is_confirmed != true THEN
    RETURN jsonb_build_object('success', false, 'error', 'لا يمكن إرجاع لوط غير مؤكد');
  END IF;

  IF p_return_quantity <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'كمية الإرجاع يجب أن تكون أكبر من صفر');
  END IF;

  -- Determine unit cost
  IF p_return_price IS NOT NULL AND p_return_price > 0 THEN
    v_unit_cost := p_return_price;
  ELSE
    v_unit_cost := COALESCE(v_lot.fruit_cost_per_kg, 0);
  END IF;

  v_return_value := p_return_quantity * v_unit_cost;
  v_product_name := COALESCE(v_lot.product_name, 'محصول خام');

  -- 2. Insert lot_return record
  INSERT INTO lot_returns (
    lot_receipt_id,
    supplier_id,
    station_id,
    returned_quantity,
    return_value,
    notes,
    created_by,
    created_at
  ) VALUES (
    v_lot.id,
    v_lot.supplier_id,
    v_lot.station_id,
    p_return_quantity,
    v_return_value,
    p_notes,
    p_user_id,
    now()
  )
  RETURNING id INTO v_return_id;

  -- 3. Adjust supplier outstanding balance (stored in supplier's native currency)
  IF v_lot.supplier_id IS NOT NULL AND v_return_value > 0 THEN
    UPDATE suppliers
    SET outstanding_balance = COALESCE(outstanding_balance, 0) - v_return_value
    WHERE id = v_lot.supplier_id;

    v_desc := 'مرتجع محصول - لوط رقم: ' || COALESCE(v_lot.lot_number, v_lot.id::TEXT) || ' (كمية: ' || p_return_quantity || ')';
    INSERT INTO ledger_entries (
      entity_type, entity_id, entry_type, amount, reference_type, reference_text, description, created_by
    ) VALUES (
      'supplier', v_lot.supplier_id::TEXT, 'debit', v_return_value, 'lot_return', v_return_id::TEXT, v_desc, p_user_id
    );
  END IF;

  -- 4. Post Double-Entry Journal Entry
  -- Dr. Supplier Leaf Account (2000s) -> Debit Supplier in foreign currency (e.g. USD)
  -- Cr. Inventory Account (1030)       -> Credit Inventory in local base currency (EGP)
  IF v_return_value > 0 THEN
    SELECT a.company_id INTO v_company_id
    FROM accounts a
    WHERE a.account_code = '1030'
    LIMIT 1;

    IF v_company_id IS NULL THEN
      SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
    END IF;

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
      v_return_value_egp := v_return_value * COALESCE(NULLIF(v_lot.exchange_rate, 0), 1.0);
      v_desc := 'مرتجع شراء محصول خام ' || v_product_name || ' - لوط رقم: ' || COALESCE(v_lot.lot_number, v_lot.id::TEXT);

      v_je_id := public.post_journal_entry(
        p_company_id := v_company_id,
        p_entry_date := CURRENT_DATE,
        p_source_type := 'lot_return',
        p_description := v_desc,
        p_created_by := p_user_id,
        p_lines := jsonb_build_array(
          jsonb_build_object(
            'account_id', v_supplier_leaf_account_id,
            'debit', v_return_value,
            'credit', 0,
            'base_debit', v_return_value_egp,
            'base_credit', 0,
            'currency', COALESCE(v_lot.currency, 'EGP'),
            'description', 'تخفيض مستحقات مورد عن مرتجع شراء محصول رقم ' || COALESCE(v_lot.lot_number, v_lot.id::TEXT)
          ),
          jsonb_build_object(
            'account_id', v_inventory_account_id,
            'debit', 0,
            'credit', v_return_value_egp,
            'base_debit', 0,
            'base_credit', v_return_value_egp,
            'currency', 'EGP',
            'description', 'تخفيض مخزون محصول خام عن مرتجع رقم ' || COALESCE(v_lot.lot_number, v_lot.id::TEXT)
          )
        )
      );

      UPDATE journal_entries
      SET source_id = v_return_id::TEXT
      WHERE id = v_je_id;

      UPDATE lot_returns
      SET journal_entry_id = v_je_id
      WHERE id = v_return_id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'return_id', v_return_id,
    'returned_quantity', p_return_quantity,
    'return_value', v_return_value,
    'unit_cost_used', v_unit_cost,
    'station_id', v_target_station,
    'batch_id', p_batch_id,
    'journal_entry_id', v_je_id
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$$;

COMMIT;
