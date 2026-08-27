BEGIN;

-- Revert rpc_edit_purchase_item_price to its previous state without post_journal_entry
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
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION '??? ???? ?? ?????? ??? ???????';
  END IF;

  -- Get the item
  SELECT * INTO v_item
  FROM purchase_invoice_items
  WHERE id::TEXT = p_item_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION '??? ????????? ??? ?????';
  END IF;

  -- Get the purchase
  SELECT * INTO v_purchase
  FROM purchase_invoices
  WHERE id::TEXT = p_purchase_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION '?????? ????????? ??? ??????';
  END IF;

  -- Calculate delta
  v_old_total := COALESCE(v_item.unit_cost, 0) * COALESCE(v_item.quantity, 0);
  v_new_item_total := p_new_price * COALESCE(v_item.quantity, 0);
  v_delta := v_new_item_total - v_old_total;
  v_raw_material_id := v_item.raw_material_id;

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

  -- 3. Update stock_batches (match by purchase_invoice_id + product_id)
  UPDATE stock_batches
  SET purchase_cost = p_new_price,
      average_cost = p_new_price,
      updated_at = now()
  WHERE purchase_invoice_id::TEXT = p_purchase_id
    AND product_id::TEXT = v_raw_material_id::TEXT;

  -- 4. Get product code and name for station_product_batches
  SELECT code, name INTO v_product_code, v_product_name
  FROM raw_materials
  WHERE id = v_raw_material_id;

  -- 5. Update station_product_batches
  UPDATE station_product_batches
  SET unit_cost = p_new_price
  WHERE source_type = 'purchase'
    AND purchase_invoice_id::TEXT = p_purchase_id
    AND (
      (v_product_code IS NOT NULL AND v_product_code != '' AND product_code = v_product_code)
      OR
      (product_name = COALESCE(v_product_name, '') || ' (???? ?????)')
      OR
      (product_code = '' AND COALESCE(v_product_code, '') = '') -- fallback if both have empty code
    );

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

  -- 8. Refresh PostgREST schema cache
  NOTIFY pgrst, 'reload schema';

  RETURN jsonb_build_object(
    'success', true,
    'delta', v_delta
  );
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION '??? ??? ????? ????? ?????: %', SQLERRM;
END;
$$;

-- Clean up the erroneously created purchase price adjustment journal entries
DELETE FROM account_ledger_entries 
WHERE journal_entry_id IN (
    SELECT id FROM journal_entries WHERE source_type = 'purchase_price_adjustment'
);

DELETE FROM journal_entries WHERE source_type = 'purchase_price_adjustment';

COMMIT;
