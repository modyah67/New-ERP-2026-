-- Migration 341: Sync all database primary key sequences and fix company_id resolution in rpc_edit_purchase_item_price
-- Description: Automatically resyncs all sequence counters to prevent duplicate key errors in audit_logs_text and purchase tables, and fixes company_id resolution in rpc_edit_purchase_item_price.

BEGIN;

-- 1. Resync all primary key sequences in public schema
DO $$
DECLARE
    r RECORD;
    v_max BIGINT;
    v_seq TEXT;
BEGIN
    FOR r IN
        SELECT 
            t.table_schema,
            t.table_name,
            c.column_name,
            pg_get_serial_sequence(t.table_schema || '.' || t.table_name, c.column_name) AS seq_name
        FROM information_schema.tables t
        JOIN information_schema.columns c 
          ON c.table_name = t.table_name AND c.table_schema = t.table_schema
        WHERE t.table_schema = 'public'
          AND pg_get_serial_sequence(t.table_schema || '.' || t.table_name, c.column_name) IS NOT NULL
    LOOP
        v_seq := r.seq_name;
        EXECUTE format('SELECT COALESCE(MAX(%I), 0) FROM %I.%I', r.column_name, r.table_schema, r.table_name) INTO v_max;
        EXECUTE format('SELECT setval(%L, GREATEST(%s + 1, 1), false)', v_seq, v_max);
    END LOOP;
END;
$$;

-- 2. Update rpc_edit_purchase_item_price to resolve company_id properly
CREATE OR REPLACE FUNCTION public.rpc_edit_purchase_item_price(
  p_purchase_id TEXT,
  p_item_id TEXT,
  p_new_price NUMERIC,
  p_user_id UUID DEFAULT auth.uid()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item RECORD;
  v_purchase RECORD;
  v_old_total NUMERIC;
  v_new_item_total NUMERIC;
  v_delta NUMERIC;
  v_delta_base NUMERIC;
  v_exchange_rate NUMERIC := 1.0;
  v_currency TEXT := 'EGP';
  v_product_code TEXT;
  v_product_name TEXT;
  v_raw_material_id UUID;
  v_batch_record RECORD;
  r_po RECORD;
  v_company_id UUID;
  v_inventory_account_id BIGINT;
  v_supplier_account_id BIGINT;
  v_je_id BIGINT;
  v_je_desc TEXT;
  v_item_name TEXT;
BEGIN
  SELECT * INTO v_item FROM purchase_invoice_items WHERE id::TEXT = p_item_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'صنف المشتريات غير موجود'; END IF;

  SELECT * INTO v_purchase FROM purchase_invoices WHERE id::TEXT = p_purchase_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'فاتورة المشتريات غير موجودة'; END IF;

  v_currency := COALESCE(v_purchase.currency, 'EGP');
  IF v_purchase.currency_snapshot IS NOT NULL THEN
    v_exchange_rate := COALESCE(NULLIF((v_purchase.currency_snapshot->>'exchange_rate')::numeric, 0), 1.0);
  END IF;

  v_old_total := COALESCE(v_item.unit_cost, 0) * COALESCE(v_item.quantity, 0);
  v_new_item_total := p_new_price * COALESCE(v_item.quantity, 0);
  v_delta := v_new_item_total - v_old_total;
  v_delta_base := ROUND(v_delta * v_exchange_rate, 2);
  v_raw_material_id := v_item.raw_material_id;

  SELECT code, name INTO v_product_code, v_product_name FROM raw_materials WHERE id = v_raw_material_id;
  v_item_name := COALESCE(v_product_name, 'مواد تعبئة');

  -- 1. Update purchase invoice item
  UPDATE purchase_invoice_items
  SET unit_cost = p_new_price, total_cost = v_new_item_total
  WHERE id::TEXT = p_item_id;

  -- 2. Update purchase invoice totals
  UPDATE purchase_invoices
  SET subtotal = COALESCE(subtotal, 0) + v_delta,
      total_amount = COALESCE(total_amount, 0) + v_delta,
      remaining_amount = COALESCE(remaining_amount, 0) + v_delta,
      updated_at = now()
  WHERE id::TEXT = p_purchase_id;

  -- 3. Update stock_batches
  UPDATE stock_batches
  SET purchase_cost = p_new_price, average_cost = p_new_price, updated_at = now()
  WHERE purchase_invoice_id::TEXT = p_purchase_id AND product_id::TEXT = v_raw_material_id::TEXT;

  -- 4. Update station_product_batches & refresh packing orders
  FOR v_batch_record IN 
      SELECT id FROM station_product_batches 
      WHERE source_type = 'purchase'
        AND purchase_invoice_id::TEXT = p_purchase_id
        AND (
          (v_product_code IS NOT NULL AND v_product_code != '' AND product_code = v_product_code)
          OR (product_name = COALESCE(v_product_name, '') || ' (مادة تعبئة)')
          OR (product_code = '' AND COALESCE(v_product_code, '') = '')
        )
  LOOP
      UPDATE station_product_batches SET unit_cost = p_new_price WHERE id = v_batch_record.id;

      FOR r_po IN
          SELECT DISTINCT po.id FROM packing_orders po
          WHERE po.notes IS NOT NULL AND po.notes != '' AND EXISTS (
              SELECT 1 FROM jsonb_array_elements(
                  CASE 
                      WHEN jsonb_typeof(po.notes::jsonb -> 'materials') = 'object' THEN jsonb_build_array(po.notes::jsonb -> 'materials')
                      WHEN jsonb_typeof(po.notes::jsonb -> 'materials') = 'array' THEN po.notes::jsonb -> 'materials'
                      ELSE '[]'::jsonb 
                  END
              ) AS elem
              WHERE (elem->>'batch_id')::bigint = v_batch_record.id
          )
      LOOP
          PERFORM public.rpc_refresh_packing_order_prices(r_po.id);
      END LOOP;
  END LOOP;

  -- 5. Update raw_materials default_purchase_price
  IF v_raw_material_id IS NOT NULL THEN
    UPDATE raw_materials
    SET default_purchase_price = COALESCE(
      (SELECT SUM(purchase_cost * remaining_quantity) / NULLIF(SUM(remaining_quantity), 0)
       FROM stock_batches
       WHERE product_id::TEXT = v_raw_material_id::TEXT AND status = 'active'),
      default_purchase_price
    ),
    updated_at = now()
    WHERE id = v_raw_material_id;
  END IF;

  -- 6. Update supplier balance in native currency & subledger
  IF v_purchase.supplier_id IS NOT NULL THEN
    UPDATE suppliers
    SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_delta
    WHERE id = v_purchase.supplier_id;

    UPDATE public.ledger_entries
    SET amount = amount + v_delta
    WHERE entity_type = 'supplier'
      AND entity_id = v_purchase.supplier_id::text
      AND reference_type = 'purchase_invoice'
      AND reference_id::text = p_purchase_id;
  END IF;

  -- 7. Post Price Adjustment Journal Entry if confirmed and delta != 0
  IF v_purchase.status = 'confirmed' AND (ABS(v_delta) >= 0.01 OR ABS(v_delta_base) >= 0.01) THEN
    SELECT id INTO v_company_id FROM sys_companies LIMIT 1;

    -- Resolve Account 1040 (Packaging Materials Inventory)
    SELECT a.id INTO v_inventory_account_id
    FROM accounts a
    WHERE a.account_code = '1040'
    LIMIT 1;

    -- Resolve Supplier Leaf Account
    v_supplier_account_id := NULL;
    IF v_purchase.supplier_id IS NOT NULL THEN
      SELECT account_id INTO v_supplier_account_id FROM suppliers WHERE id = v_purchase.supplier_id;
    END IF;
    IF v_supplier_account_id IS NULL THEN
      SELECT a.id INTO v_supplier_account_id FROM accounts a WHERE a.account_code = '2000' LIMIT 1;
    END IF;

    v_je_desc := 'تأثير تعديل سعر مشتريات مواد تعبئة: ' || v_item_name
                 || ' — فاتورة رقم ' || COALESCE(v_purchase.invoice_number, p_purchase_id)
                 || ' (الفرق: ' || v_delta::TEXT || ' ' || v_currency || ')';

    IF v_inventory_account_id IS NOT NULL AND v_supplier_account_id IS NOT NULL THEN
      v_je_id := public.post_journal_entry(
        p_source_type := 'purchase_price_adjustment',
        p_description := v_je_desc,
        p_entry_date := CURRENT_DATE,
        p_company_id := v_company_id,
        p_created_by := p_user_id,
        p_lines := jsonb_build_array(
          jsonb_build_object(
            'account_id', v_inventory_account_id,
            'debit', CASE WHEN v_delta_base > 0 THEN v_delta_base ELSE 0 END,
            'base_debit', CASE WHEN v_delta_base > 0 THEN v_delta_base ELSE 0 END,
            'credit', CASE WHEN v_delta_base < 0 THEN ABS(v_delta_base) ELSE 0 END,
            'base_credit', CASE WHEN v_delta_base < 0 THEN ABS(v_delta_base) ELSE 0 END,
            'currency', 'EGP',
            'description', v_je_desc
          ),
          jsonb_build_object(
            'account_id', v_supplier_account_id,
            'debit', CASE WHEN v_delta < 0 THEN ABS(v_delta) ELSE 0 END,
            'base_debit', CASE WHEN v_delta_base < 0 THEN ABS(v_delta_base) ELSE 0 END,
            'credit', CASE WHEN v_delta > 0 THEN v_delta ELSE 0 END,
            'base_credit', CASE WHEN v_delta_base > 0 THEN v_delta_base ELSE 0 END,
            'currency', v_currency,
            'description', v_je_desc
          )
        ),
        p_source_id := p_purchase_id
      );
    END IF;
  END IF;

  NOTIFY pgrst, 'reload_schema';
  RETURN jsonb_build_object('success', true, 'delta', v_delta, 'delta_base', v_delta_base, 'journal_entry_id', v_je_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_edit_purchase_item_price(TEXT, TEXT, NUMERIC, UUID) TO authenticated;

COMMIT;
