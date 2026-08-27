-- Migration 336: Complete Purchase Invoice & Lot Price GL and Packing Synchronization
-- Date: 2026-08-18

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Edit Purchase Item Price with Full GL & Packing Cascade
-- ─────────────────────────────────────────────────────────────────────────────
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
  v_inv_acc INT;
  v_supp_acc INT;
  r_ale RECORD;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح لك بإجراء هذه العملية';
  END IF;

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

  -- 4. Get product code and name for station_product_batches
  SELECT code, name INTO v_product_code, v_product_name FROM raw_materials WHERE id = v_raw_material_id;

  -- 5. Update station_product_batches & refresh packing orders
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

      -- Cascade update immediately to all affected packing orders
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

  -- 6. Update supplier balance and subledger
  IF v_purchase.supplier_id IS NOT NULL THEN
    UPDATE suppliers
    SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_delta_base
    WHERE id = v_purchase.supplier_id;

    -- Update supplier subledger entry
    UPDATE public.ledger_entries
    SET amount = amount + v_delta
    WHERE entity_type = 'supplier'
      AND entity_id = v_purchase.supplier_id::text
      AND reference_type = 'purchase_invoice'
      AND reference_id::text = p_purchase_id;
  END IF;

  -- 7. Update purchase invoice GL journal entry lines in account_ledger_entries
  IF v_purchase.journal_entry_id IS NOT NULL THEN
    -- Update Debit line (Inventory 1040/1030)
    UPDATE public.account_ledger_entries
    SET debit = debit + v_delta,
        amount_in_base_currency = amount_in_base_currency + v_delta_base
    WHERE journal_entry_id = v_purchase.journal_entry_id
      AND debit > 0;

    -- Update Credit line (Supplier / AP)
    UPDATE public.account_ledger_entries
    SET credit = credit + v_delta,
        amount_in_base_currency = amount_in_base_currency + v_delta_base
    WHERE journal_entry_id = v_purchase.journal_entry_id
      AND credit > 0;
  END IF;

  NOTIFY pgrst, 'reload_schema';
  RETURN jsonb_build_object('success', true, 'delta', v_delta, 'delta_base', v_delta_base);
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Edit Lot Price with Full GL & Packing Cascade
-- ─────────────────────────────────────────────────────────────────────────────
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
    v_delta_cost NUMERIC;
    v_delta_base NUMERIC;
    v_effective_cost NUMERIC;
    v_total_graded NUMERIC := 0;
    v_grading RECORD;
    v_net_wt NUMERIC;
    v_new_fruit_cost_per_kg NUMERIC;
    v_batch_record RECORD;
    r_po RECORD;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'غير مصرح لك بتعديل سعر المحصول'; END IF;

    SELECT lr.* INTO v_lot FROM lot_receipts lr WHERE lr.id = p_lot_id FOR UPDATE OF lr;
    IF NOT FOUND THEN RAISE EXCEPTION 'رقم المحصول غير موجود (id=%)', p_lot_id; END IF;

    v_old_total_cost := COALESCE(v_lot.total_fruit_cost, 0);
    v_net_wt := COALESCE(NULLIF(v_lot.net_weight_kg, 0), v_lot.gross_weight_kg, 0);

    IF COALESCE(v_lot.purchase_mode, 'weight') = 'carton' THEN
      v_new_total_cost := COALESCE(v_lot.carton_count, 0) * p_new_price;
    ELSE
      v_new_total_cost := COALESCE(v_lot.gross_weight_kg, 0) * p_new_price;
    END IF;

    v_delta_cost := v_new_total_cost - v_old_total_cost;
    v_delta_base := ROUND(v_delta_cost * COALESCE(NULLIF(p_exchange_rate, 0), 1.0), 2);
    v_new_fruit_cost_per_kg := CASE WHEN v_net_wt > 0 THEN v_new_total_cost / v_net_wt ELSE p_new_price END;

    UPDATE lot_receipts
    SET price_per_carton = CASE WHEN COALESCE(v_lot.purchase_mode, 'weight') = 'carton' THEN p_new_price ELSE price_per_carton END,
        fruit_cost_per_kg = v_new_fruit_cost_per_kg,
        exchange_rate = p_exchange_rate,
        currency = p_currency,
        total_fruit_cost = v_new_total_cost,
        updated_at = now()
    WHERE id = p_lot_id;

    IF v_lot.is_confirmed = true THEN
      PERFORM public.sync_supplier_ledger_for_lot(p_lot_id, 'UPDATE');
    END IF;

    -- Update stock batches
    SELECT COALESCE(SUM(weight_kg), 0) INTO v_total_graded FROM lot_grading_results WHERE lot_id = p_lot_id;
    IF v_total_graded > 0 THEN
      v_effective_cost := v_new_total_cost / v_total_graded;
      FOR v_grading IN (SELECT stock_batch_id FROM lot_grading_results WHERE lot_id = p_lot_id AND stock_batch_id IS NOT NULL) LOOP
        UPDATE stock_batches
        SET purchase_cost = v_effective_cost, average_cost = v_effective_cost
        WHERE id = v_grading.stock_batch_id;
      END LOOP;
    END IF;

    -- Update station product batches and cascade to packing orders
    FOR v_batch_record IN 
        SELECT id FROM station_product_batches 
        WHERE source_type = 'lot_receipt' AND (product_code = v_lot.lot_number OR lot_id = p_lot_id)
    LOOP
        UPDATE station_product_batches
        SET unit_cost = v_new_fruit_cost_per_kg,
            exchange_rate = p_exchange_rate,
            currency = p_currency
        WHERE id = v_batch_record.id;
        
        -- Cascade update immediately to all affected packing orders
        FOR r_po IN
            SELECT DISTINCT po.id FROM packing_orders po
            WHERE po.notes IS NOT NULL AND po.notes != '' AND EXISTS (
                SELECT 1 FROM jsonb_array_elements(
                    CASE 
                        WHEN jsonb_typeof(po.notes::jsonb -> 'fruit_allocation') = 'object' THEN jsonb_build_array(po.notes::jsonb -> 'fruit_allocation')
                        WHEN jsonb_typeof(po.notes::jsonb -> 'fruit_allocation') = 'array' THEN po.notes::jsonb -> 'fruit_allocation'
                        ELSE '[]'::jsonb 
                    END
                ) AS elem
                WHERE (elem->>'batch_id')::bigint = v_batch_record.id
            )
        LOOP
            PERFORM public.rpc_refresh_packing_order_prices(r_po.id);
        END LOOP;
    END LOOP;

    -- Update lot GL journal entry if exists
    IF v_lot.journal_entry_id IS NOT NULL THEN
      -- Update Debit (Produce 1030)
      UPDATE public.account_ledger_entries
      SET debit = debit + v_delta_cost,
          amount_in_base_currency = amount_in_base_currency + v_delta_base
      WHERE journal_entry_id = v_lot.journal_entry_id
        AND debit > 0;

      -- Update Credit (Supplier / AP)
      UPDATE public.account_ledger_entries
      SET credit = credit + v_delta_cost,
          amount_in_base_currency = amount_in_base_currency + v_delta_base
      WHERE journal_entry_id = v_lot.journal_entry_id
        AND credit > 0;
    END IF;

    NOTIFY pgrst, 'reload_schema';
    RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_edit_purchase_item_price(TEXT, TEXT, NUMERIC, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_edit_lot_price(BIGINT, NUMERIC, NUMERIC, TEXT, UUID) TO authenticated;
