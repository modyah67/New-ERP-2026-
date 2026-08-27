-- ============================================================================
-- 081_lot_return_enterprise_journal_entries.sql
--
-- Integrates Lot Returns (مرتجع شراء محصول) with the Enterprise Accounting Engine:
-- 1. Adds journal_entry_id to lot_returns
-- 2. Registers 'lot_return' document type in sys_document_types
-- 3. Updates rpc_process_lot_return to post balanced double-entry GL:
--      Dr. Supplier Leaf Account (2000s) -> reduces supplier payable
--      Cr. Raw Inventory Account (1030)  -> reduces raw materials inventory
-- 4. Backfills existing lot_returns with GL entries
-- ============================================================================

BEGIN;

-- 1. Add journal_entry_id column to lot_returns
ALTER TABLE public.lot_returns 
ADD COLUMN IF NOT EXISTS journal_entry_id BIGINT REFERENCES public.journal_entries(id) ON DELETE SET NULL;

-- 2. Register document type for lot returns
INSERT INTO public.sys_document_types (code, name, prefix)
VALUES ('lot_return', 'مرتجع شراء محصول', 'RET')
ON CONFLICT (code) DO UPDATE 
SET name = EXCLUDED.name, 
    prefix = EXCLUDED.prefix;

-- 3. Drop existing overloaded functions for rpc_process_lot_return
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT oid::regprocedure AS sig
    FROM pg_proc
    WHERE proname = 'rpc_process_lot_return'
      AND pronamespace = 'public'::regnamespace
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || r.sig || ' CASCADE';
    RAISE NOTICE 'Dropped: %', r.sig;
  END LOOP;
END $$;

-- 4. Create updated rpc_process_lot_return with Enterprise Double-Entry GL
CREATE OR REPLACE FUNCTION public.rpc_process_lot_return(
  p_lot_id BIGINT,
  p_return_quantity NUMERIC,
  p_notes TEXT DEFAULT NULL,
  p_station_id BIGINT DEFAULT NULL,
  p_batch_id BIGINT DEFAULT NULL,
  p_user_id UUID DEFAULT auth.uid()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lot RECORD;
  v_product_name TEXT;
  v_unit_cost NUMERIC := 0;
  v_return_value NUMERIC := 0;
  v_remaining_in_batches NUMERIC := 0;
  v_batch RECORD;
  v_qty_to_deduct NUMERIC;
  v_desc TEXT;
  v_target_station BIGINT;
  v_return_id BIGINT;
  v_company_id UUID;
  v_supplier_leaf_account_id BIGINT;
  v_inventory_account_id BIGINT;
  v_return_value_egp NUMERIC;
  v_je_id BIGINT;
BEGIN
  IF p_return_quantity <= 0 THEN
    RAISE EXCEPTION 'الكمية المرتجعة يجب أن تكون أكبر من الصفر';
  END IF;

  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'يجب تسجيل الدخول لإتمام المرتجع';
  END IF;

  SELECT lr.*, ft.name AS fruit_type_name
  INTO v_lot
  FROM lot_receipts lr
  LEFT JOIN fruit_types ft ON ft.id = lr.fruit_type_id
  WHERE lr.id = p_lot_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'سجل شراء المحصول غير موجود';
  END IF;

  v_product_name := COALESCE(
    NULLIF(v_lot.product_name, ''),
    NULLIF(v_lot.fruit_type_name, ''),
    'محصول'
  );

  v_target_station := COALESCE(p_station_id, v_lot.station_id);

  v_unit_cost := COALESCE(v_lot.total_fruit_cost / NULLIF(v_lot.gross_weight_kg, 0), 0);
  v_return_value := p_return_quantity * v_unit_cost;

  -- 1. Deduct from station inventory / batches
  IF p_batch_id IS NOT NULL THEN
    SELECT remaining_quantity INTO v_remaining_in_batches
    FROM station_product_batches
    WHERE id = p_batch_id
      AND product_code = v_lot.lot_number
      AND station_id = v_target_station;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'الدفعة غير موجودة';
    END IF;

    IF v_remaining_in_batches < p_return_quantity THEN
      RAISE EXCEPTION 'الكمية المرتجعة (%) أكبر من الكمية المتبقية (%) في الدفعة', p_return_quantity, v_remaining_in_batches;
    END IF;

    UPDATE station_product_batches
    SET remaining_quantity = remaining_quantity - p_return_quantity
    WHERE id = p_batch_id;
  ELSE
    SELECT COALESCE(SUM(remaining_quantity), 0)
    INTO v_remaining_in_batches
    FROM station_product_batches
    WHERE product_code = v_lot.lot_number
      AND station_id = v_target_station;

    IF v_remaining_in_batches < p_return_quantity THEN
      RAISE EXCEPTION 'الكمية المرتجعة (%) أكبر من الكمية المتبقية (%) في المحطة', p_return_quantity, v_remaining_in_batches;
    END IF;

    v_qty_to_deduct := p_return_quantity;

    FOR v_batch IN
      SELECT id, remaining_quantity
      FROM station_product_batches
      WHERE product_code = v_lot.lot_number
        AND station_id = v_target_station
        AND remaining_quantity > 0
      ORDER BY id ASC
      FOR UPDATE
    LOOP
      IF v_qty_to_deduct <= 0 THEN EXIT; END IF;

      IF v_batch.remaining_quantity >= v_qty_to_deduct THEN
        UPDATE station_product_batches
        SET remaining_quantity = remaining_quantity - v_qty_to_deduct
        WHERE id = v_batch.id;
        v_qty_to_deduct := 0;
      ELSE
        v_qty_to_deduct := v_qty_to_deduct - v_batch.remaining_quantity;
        UPDATE station_product_batches
        SET remaining_quantity = 0
        WHERE id = v_batch.id;
      END IF;
    END LOOP;
  END IF;

  UPDATE station_products
  SET quantity = GREATEST(COALESCE(quantity, 0) - p_return_quantity, 0),
      updated_at = now()
  WHERE station_id = v_target_station
    AND product_name = v_product_name;

  IF NOT FOUND THEN
    UPDATE station_products
    SET quantity = GREATEST(COALESCE(quantity, 0) - p_return_quantity, 0),
        updated_at = now()
    WHERE station_id = v_target_station
      AND product_name = v_lot.fruit_type_name;
  END IF;

  DELETE FROM station_products
  WHERE station_id = v_target_station
    AND (product_name = v_product_name OR product_name = v_lot.fruit_type_name)
    AND COALESCE(quantity, 0) <= 0;

  -- 2. Insert into lot_returns
  INSERT INTO lot_returns (
    lot_receipt_id, supplier_id, station_id, returned_quantity, return_value, notes, created_by
  ) VALUES (
    v_lot.id, v_lot.supplier_id, v_target_station, p_return_quantity, v_return_value, p_notes, p_user_id
  ) RETURNING id INTO v_return_id;

  -- 3. Update legacy supplier ledger
  IF v_lot.supplier_id IS NOT NULL THEN
    UPDATE suppliers
    SET outstanding_balance = COALESCE(outstanding_balance, 0) - v_return_value,
        updated_at = now()
    WHERE id = v_lot.supplier_id;

    v_desc := 'مرتجع شراء محصول ' || v_lot.lot_number || ' - ' || v_product_name;
    INSERT INTO ledger_entries (
      entity_type, entity_id, entry_type, amount, reference_type, reference_text, description, created_by
    ) VALUES (
      'supplier', v_lot.supplier_id::TEXT, 'debit', v_return_value, 'lot_return', v_return_id::TEXT, v_desc, p_user_id
    );
  END IF;

  -- 4. Post Enterprise Double-Entry Journal Entry
  -- Dr. Supplier Leaf Account (2000s) -> Debit Supplier (decreases liability)
  -- Cr. Inventory Account (1030)       -> Credit Inventory (decreases asset)
  IF v_return_value > 0 THEN
    SELECT a.company_id INTO v_company_id
    FROM accounts a
    WHERE a.account_code = '1030'
    LIMIT 1;

    IF v_company_id IS NULL THEN
      SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
    END IF;

    -- Resolve Inventory leaf account
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

    -- Resolve Supplier leaf account
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
            'debit', v_return_value_egp,
            'credit', 0,
            'currency', COALESCE(v_lot.currency, 'EGP'),
            'description', 'تخفيض مستحقات مورد عن مرتجع شراء محصول رقم ' || COALESCE(v_lot.lot_number, v_lot.id::TEXT)
          ),
          jsonb_build_object(
            'account_id', v_inventory_account_id,
            'debit', 0,
            'credit', v_return_value_egp,
            'currency', COALESCE(v_lot.currency, 'EGP'),
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

GRANT EXECUTE ON FUNCTION public.rpc_process_lot_return(BIGINT, NUMERIC, TEXT, BIGINT, BIGINT, UUID) TO authenticated;

-- 5. Backfill existing lot returns
DO $$
DECLARE
  r RECORD;
  v_lot RECORD;
  v_company_id UUID;
  v_supplier_leaf_account_id BIGINT;
  v_inventory_account_id BIGINT;
  v_return_value_egp NUMERIC;
  v_product_name TEXT;
  v_je_id BIGINT;
  v_desc TEXT;
BEGIN
  -- Resolve company
  SELECT id INTO v_company_id FROM sys_companies LIMIT 1;

  -- Resolve Inventory account
  SELECT a.id INTO v_inventory_account_id
  FROM accounts a
  WHERE a.account_code = '1030'
  LIMIT 1;

  FOR r IN
    SELECT lr.* FROM lot_returns lr
    WHERE lr.journal_entry_id IS NULL 
       OR NOT EXISTS (SELECT 1 FROM journal_entries WHERE id = lr.journal_entry_id)
  LOOP
    BEGIN
      SELECT * INTO v_lot FROM lot_receipts WHERE id = r.lot_receipt_id;
      IF FOUND AND r.return_value > 0 THEN
        v_product_name := COALESCE(v_lot.product_name, 'محصول');

        -- Resolve supplier account
        v_supplier_leaf_account_id := NULL;
        IF r.supplier_id IS NOT NULL THEN
          SELECT s.account_id INTO v_supplier_leaf_account_id
          FROM suppliers s
          WHERE s.id = r.supplier_id;
        END IF;

        IF v_supplier_leaf_account_id IS NULL THEN
          SELECT a.id INTO v_supplier_leaf_account_id
          FROM accounts a
          WHERE a.account_code = '2000'
          LIMIT 1;
        END IF;

        IF v_inventory_account_id IS NOT NULL AND v_supplier_leaf_account_id IS NOT NULL THEN
          v_return_value_egp := r.return_value * COALESCE(NULLIF(v_lot.exchange_rate, 0), 1.0);
          v_desc := 'مرتجع شراء محصول خام ' || v_product_name || ' - لوط رقم: ' || COALESCE(v_lot.lot_number, v_lot.id::TEXT);

          v_je_id := public.post_journal_entry(
            p_company_id := v_company_id,
            p_entry_date := COALESCE(r.created_at::DATE, CURRENT_DATE),
            p_source_type := 'lot_return',
            p_description := v_desc,
            p_created_by := COALESCE(r.created_by, auth.uid()),
            p_lines := jsonb_build_array(
              jsonb_build_object(
                'account_id', v_supplier_leaf_account_id,
                'debit', v_return_value_egp,
                'credit', 0,
                'currency', COALESCE(v_lot.currency, 'EGP'),
                'description', 'تخفيض مستحقات مورد عن مرتجع شراء محصول رقم ' || COALESCE(v_lot.lot_number, v_lot.id::TEXT)
              ),
              jsonb_build_object(
                'account_id', v_inventory_account_id,
                'debit', 0,
                'credit', v_return_value_egp,
                'currency', COALESCE(v_lot.currency, 'EGP'),
                'description', 'تخفيض مخزون محصول خام عن مرتجع رقم ' || COALESCE(v_lot.lot_number, v_lot.id::TEXT)
              )
            )
          );

          UPDATE journal_entries
          SET source_id = r.id::TEXT
          WHERE id = v_je_id;

          UPDATE lot_returns
          SET journal_entry_id = v_je_id
          WHERE id = r.id;
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Skipping lot_return %: %', r.id, SQLERRM;
    END;
  END LOOP;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';
