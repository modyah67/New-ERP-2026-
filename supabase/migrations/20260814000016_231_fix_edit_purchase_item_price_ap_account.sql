DROP FUNCTION IF EXISTS rpc_edit_purchase_item_price(TEXT, TEXT, NUMERIC, UUID);

CREATE OR REPLACE FUNCTION rpc_edit_purchase_item_price(
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
  v_product_code TEXT;
  v_product_name TEXT;
  v_raw_material_id UUID;
  v_batch_record RECORD;
  v_company_id UUID;
  v_supplier_account_id BIGINT;
  v_inventory_account_id BIGINT;
  v_currency TEXT;
  v_je_id BIGINT;
  v_je_desc TEXT;
  v_item_name TEXT;
  v_exchange_rate NUMERIC;
  v_base_delta NUMERIC;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح لك بإجراء هذه العملية';
  END IF;

  -- Get the item
  SELECT * INTO v_item
  FROM purchase_invoice_items
  WHERE id::TEXT = p_item_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'صنف المشتريات غير موجود';
  END IF;

  -- Get the purchase
  SELECT * INTO v_purchase
  FROM purchase_invoices
  WHERE id::TEXT = p_purchase_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'فاتورة المشتريات غير موجودة';
  END IF;

  -- Only adjust confirmed purchases
  IF v_purchase.status != 'confirmed' THEN
    RAISE EXCEPTION 'يمكن تعديل السعر فقط بعد تأكيد الفاتورة';
  END IF;

  -- Calculate delta
  v_old_total := COALESCE(v_item.unit_cost, 0) * COALESCE(v_item.quantity, 0);
  v_new_item_total := p_new_price * COALESCE(v_item.quantity, 0);
  v_delta := v_new_item_total - v_old_total;
  v_raw_material_id := v_item.raw_material_id;

  -- Get product name for description
  SELECT name INTO v_item_name FROM raw_materials WHERE id = v_raw_material_id;
  IF v_item_name IS NULL THEN v_item_name := 'صنف'; END IF;

  -- 1. Update item
  UPDATE purchase_invoice_items
  SET unit_cost = p_new_price,
      total_cost = v_new_item_total
  WHERE id::TEXT = p_item_id;

  -- 2. Update purchase totals
  UPDATE purchase_invoices
  SET subtotal = COALESCE(subtotal, 0) + v_delta,
      total_amount = COALESCE(total_amount, 0) + v_delta,
      remaining_amount = COALESCE(remaining_amount, 0) + v_delta,
      updated_at = now()
  WHERE id::TEXT = p_purchase_id;

  -- 3. Update EXACTLY ONE matching stock_batches record
  FOR v_batch_record IN
      SELECT id FROM stock_batches
      WHERE purchase_invoice_id::TEXT = p_purchase_id 
        AND product_id::TEXT = v_raw_material_id::TEXT
        AND ABS(purchase_cost::numeric - COALESCE(v_item.unit_cost, 0)) < 0.001
        AND quantity = COALESCE(v_item.quantity, 0)
      LIMIT 1
  LOOP
      PERFORM rpc_flag_packing_orders_for_refresh('fruit', v_batch_record.id);

      UPDATE stock_batches
      SET purchase_cost = p_new_price,
          average_cost = p_new_price,
          updated_at = now()
      WHERE id = v_batch_record.id;
  END LOOP;

  -- 4. Get product code and name for station_product_batches
  SELECT code, name INTO v_product_code, v_product_name
  FROM raw_materials
  WHERE id = v_raw_material_id;

  -- 5. Update EXACTLY ONE matching station_product_batches record
  FOR v_batch_record IN
      SELECT id FROM station_product_batches
      WHERE source_type = 'purchase'
        AND purchase_invoice_id::TEXT = p_purchase_id
        AND ABS(unit_cost::numeric - COALESCE(v_item.unit_cost, 0)) < 0.001
        AND quantity = COALESCE(v_item.quantity, 0)
        AND (
          (v_product_code IS NOT NULL AND v_product_code != '' AND product_code = v_product_code)
          OR
          (product_name = COALESCE(v_product_name, '') || ' (مادة تعبئة)')
          OR
          (product_code = '' AND COALESCE(v_product_code, '') = '')
        )
      LIMIT 1
  LOOP
      PERFORM rpc_flag_packing_orders_for_refresh('material', v_batch_record.id);

      UPDATE station_product_batches
      SET unit_cost = p_new_price
      WHERE id = v_batch_record.id;
  END LOOP;

  -- 6. Recalculate raw_materials.default_purchase_price
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

  -- 7. Update supplier outstanding_balance
  IF v_purchase.supplier_id IS NOT NULL THEN
    UPDATE suppliers
    SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_delta
    WHERE id = v_purchase.supplier_id;
  END IF;

  -- 8. CREATE PRICE ADJUSTMENT JOURNAL ENTRY (if delta != 0)
  IF v_delta != 0 THEN
    -- Resolve company_id
    SELECT company_id INTO v_company_id
    FROM accounts WHERE account_code = '1010' LIMIT 1;
    IF v_company_id IS NULL THEN
      SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
    END IF;

    v_currency := COALESCE(v_purchase.currency, 'EGP');
    v_exchange_rate := COALESCE(NULLIF((v_purchase.currency_snapshot->>'exchange_rate')::NUMERIC, 0), 1);
    v_base_delta := v_delta * v_exchange_rate;

    -- Resolve accounts
    -- Inventory account: 1010 (default) or 1040 (packaging materials)
    v_inventory_account_id := public.resolve_gl_account('1010', v_company_id);
    v_supplier_account_id := public.resolve_gl_account('2000', v_company_id);

    v_je_desc := 'تسوية سعر مشتريات - ' || v_item_name || ' (فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ')';

    IF v_delta > 0 THEN
      v_je_id := public.post_journal_entry(
        'purchase_price_adjustment',
        v_je_desc,
        CURRENT_DATE,
        v_company_id,
        p_user_id,
        jsonb_build_array(
          jsonb_build_object('account_id', v_inventory_account_id, 'debit', v_delta, 'credit', 0, 'base_debit', v_base_delta, 'base_credit', 0, 'currency', v_currency, 'description', v_je_desc),
          jsonb_build_object('account_id', v_supplier_account_id, 'debit', 0, 'credit', v_delta, 'base_debit', 0, 'base_credit', v_base_delta, 'currency', v_currency, 'description', v_je_desc)
        ),
        v_purchase.id::TEXT
      );
    ELSE
      v_je_id := public.post_journal_entry(
        'purchase_price_adjustment',
        v_je_desc,
        CURRENT_DATE,
        v_company_id,
        p_user_id,
        jsonb_build_array(
          jsonb_build_object('account_id', v_inventory_account_id, 'debit', 0, 'credit', ABS(v_delta), 'base_debit', 0, 'base_credit', ABS(v_base_delta), 'currency', v_currency, 'description', v_je_desc),
          jsonb_build_object('account_id', v_supplier_account_id, 'debit', ABS(v_delta), 'credit', 0, 'base_debit', ABS(v_base_delta), 'base_credit', 0, 'currency', v_currency, 'description', v_je_desc)
        ),
        v_purchase.id::TEXT
      );
    END IF;
  END IF;

  -- 9. Refresh PostgREST schema cache
  NOTIFY pgrst, 'reload schema';

  RETURN jsonb_build_object(
    'success', true,
    'delta', v_delta
  );
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'حدث خطأ أثناء تعديل السعر: %', SQLERRM;
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_edit_purchase_item_price(TEXT, TEXT, NUMERIC, UUID) TO authenticated;


