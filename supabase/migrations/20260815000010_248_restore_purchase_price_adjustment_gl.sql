BEGIN;

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
  v_delta_egp NUMERIC;
  v_exchange_rate NUMERIC;
  v_product_code TEXT;
  v_product_name TEXT;
  v_raw_material_id UUID;
  v_inventory_account_id BIGINT;
  v_supplier_leaf_account_id BIGINT;
  v_company_id UUID;
  v_je_id BIGINT;
  v_supplier_name TEXT;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'يجب توفير معرف المستخدم';
  END IF;

  -- Get the item
  SELECT * INTO v_item
  FROM purchase_invoice_items
  WHERE id::TEXT = p_item_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'عنصر الفاتورة غير موجود';
  END IF;

  -- Get the purchase
  SELECT * INTO v_purchase
  FROM purchase_invoices
  WHERE id::TEXT = p_purchase_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'فاتورة المشتريات غير موجودة';
  END IF;

  -- Calculate delta
  v_old_total := COALESCE(v_item.unit_cost, 0) * COALESCE(v_item.quantity, 0);
  v_new_item_total := p_new_price * COALESCE(v_item.quantity, 0);
  v_delta := v_new_item_total - v_old_total;
  v_raw_material_id := v_item.raw_material_id;
  
  v_exchange_rate := COALESCE(NULLIF(v_item.exchange_rate, 0), 1.0);
  IF v_exchange_rate = 1.0 AND COALESCE(v_purchase.currency, 'EGP') != 'EGP' THEN
      v_exchange_rate := COALESCE((SELECT exchange_rate FROM purchase_invoice_items WHERE invoice_id::TEXT = p_purchase_id LIMIT 1), 1.0);
  END IF;

  v_delta_egp := v_delta * v_exchange_rate;

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

  -- 3. Update stock_batches
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
      (product_name = COALESCE(v_product_name, '') || ' (مادة تعبئة)')
      OR
      (product_code = '' AND COALESCE(v_product_code, '') = '')
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

  -- 8. Create GL Entry if confirmed
  IF v_purchase.status = 'confirmed' AND ABS(v_delta) >= 0.01 THEN
      SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
      
      -- Get Inventory Account
      SELECT id INTO v_inventory_account_id FROM accounts WHERE account_code = '1030' AND company_id = v_company_id LIMIT 1;
      IF v_inventory_account_id IS NULL THEN
         SELECT id INTO v_inventory_account_id FROM accounts WHERE account_code = '1200' AND company_id = v_company_id LIMIT 1;
      END IF;

      -- Get Supplier Account
      SELECT s.account_id, s.name INTO v_supplier_leaf_account_id, v_supplier_name
      FROM suppliers s WHERE s.id = v_purchase.supplier_id;
      
      IF v_supplier_leaf_account_id IS NULL THEN
         SELECT id INTO v_supplier_leaf_account_id FROM accounts WHERE account_code = '2000' AND company_id = v_company_id LIMIT 1;
      END IF;

      v_je_id := public.post_journal_entry(
         p_source_type := 'purchase_price_adjustment',
         p_description := 'تسوية سعر مشتريات - فاتورة ' || COALESCE(v_purchase.invoice_number, ''),
         p_entry_date  := COALESCE(v_purchase.invoice_date::date, now()::date),
         p_company_id  := v_company_id,
         p_created_by  := p_user_id,
         p_lines       := CASE 
             WHEN v_delta > 0 THEN 
                 jsonb_build_array(
                     jsonb_build_object('account_id', v_inventory_account_id, 'debit', v_delta, 'credit', 0, 'base_debit', v_delta_egp, 'base_credit', 0, 'currency', COALESCE(v_purchase.currency, 'EGP'), 'description', 'تسوية بالزيادة - صنف ' || COALESCE(v_product_name, '')),
                     jsonb_build_object('account_id', v_supplier_leaf_account_id, 'debit', 0, 'credit', v_delta, 'base_debit', 0, 'base_credit', v_delta_egp, 'currency', COALESCE(v_purchase.currency, 'EGP'), 'description', 'مورد: ' || COALESCE(v_supplier_name, ''))
                 )
             ELSE 
                 jsonb_build_array(
                     jsonb_build_object('account_id', v_inventory_account_id, 'debit', 0, 'credit', ABS(v_delta), 'base_debit', 0, 'base_credit', ABS(v_delta_egp), 'currency', COALESCE(v_purchase.currency, 'EGP'), 'description', 'تسوية بالنقصان - صنف ' || COALESCE(v_product_name, '')),
                     jsonb_build_object('account_id', v_supplier_leaf_account_id, 'debit', ABS(v_delta), 'credit', 0, 'base_debit', ABS(v_delta_egp), 'base_credit', 0, 'currency', COALESCE(v_purchase.currency, 'EGP'), 'description', 'مورد: ' || COALESCE(v_supplier_name, ''))
                 )
         END,
         p_source_id   := p_purchase_id::TEXT
      );
  END IF;

  NOTIFY pgrst, 'reload schema';

  RETURN jsonb_build_object(
    'success', true,
    'delta', v_delta,
    'je_id', v_je_id
  );
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'حدث خطأ أثناء تعديل السعر: %', SQLERRM;
END;
$$;

-- Register purchase_price_adjustment document type if missing
INSERT INTO sys_document_types (code, name, prefix)
VALUES ('purchase_price_adjustment', 'تسوية سعر مشتريات', 'PPADJ')
ON CONFLICT (code) DO NOTHING;

COMMIT;
