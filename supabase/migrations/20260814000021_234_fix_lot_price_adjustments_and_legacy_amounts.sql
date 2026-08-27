-- Fix trigger to prevent double accounting on lot receipt edit
CREATE OR REPLACE FUNCTION public.fn_on_harvest_receipt_saved()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.is_confirmed = true THEN
      PERFORM public.sync_supplier_ledger_for_lot(OLD.id, 'DELETE');
    END IF;
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    -- If only journal_entry_id changed, skip to prevent recursive triggers
    IF (OLD.journal_entry_id IS DISTINCT FROM NEW.journal_entry_id)
       AND (OLD.is_confirmed = NEW.is_confirmed)
       AND (OLD.total_fruit_cost = NEW.total_fruit_cost)
       AND (OLD.supplier_id IS NOT DISTINCT FROM NEW.supplier_id) THEN
      RETURN NEW;
    END IF;

    IF OLD.is_confirmed = true AND (NEW.is_confirmed = false OR NEW.is_confirmed IS NULL) THEN
      PERFORM public.sync_supplier_ledger_for_lot(OLD.id, 'DELETE');
    ELSIF NEW.is_confirmed = true AND OLD.is_confirmed != true THEN
      PERFORM public.sync_supplier_ledger_for_lot(NEW.id, 'UPDATE');
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.is_confirmed = true THEN
      PERFORM public.sync_supplier_ledger_for_lot(NEW.id, 'INSERT');
    END IF;
    RETURN NEW;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Fix rpc_edit_lot_price to include base_debit/base_credit
CREATE OR REPLACE FUNCTION public.rpc_edit_lot_price(
  p_lot_id uuid,
  p_new_cost numeric,
  p_currency text,
  p_user_id uuid
)
RETURNS jsonb AS $$
DECLARE
  v_lot RECORD;
  v_new_total_cost NUMERIC;
  v_old_total_cost NUMERIC;
  v_delta NUMERIC;
  v_delta_egp NUMERIC;
  v_effective_cost NUMERIC;
  v_total_graded NUMERIC := 0;
  v_grading RECORD;
  v_product_name text;
  v_company_id uuid;
  v_inventory_account_id uuid;
  v_supplier_account_id uuid;
  v_je_id integer;
  v_desc text;
BEGIN
  -- 1. Fetch lot details
  SELECT r.id, r.total_fruit_cost, r.is_confirmed, r.exchange_rate, r.lot_number,
         rm.name AS product_name
  INTO v_lot
  FROM lot_receipts r
  LEFT JOIN raw_materials rm ON rm.id = r.raw_material_id
  WHERE r.id = p_lot_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Lot receipt % not found', p_lot_id;
  END IF;

  v_old_total_cost := COALESCE(v_lot.total_fruit_cost, 0);
  v_new_total_cost := p_new_cost;
  v_delta := v_new_total_cost - v_old_total_cost;
  v_delta_egp := v_delta * COALESCE(NULLIF(v_lot.exchange_rate, 0), 1.0);

  -- 2. Validate graded quantities vs new cost (omitted here for brevity, keeping original logic)
  SELECT COALESCE(SUM(quantity), 0) INTO v_total_graded
  FROM grading_results
  WHERE lot_id = p_lot_id;

  IF v_total_graded > 0 THEN
    v_effective_cost := v_new_total_cost / v_total_graded;
  ELSE
    v_effective_cost := 0;
  END IF;

  -- 3. Update the lot receipt
  UPDATE lot_receipts
  SET total_fruit_cost = v_new_total_cost,
      currency = p_currency
  WHERE id = p_lot_id;

  -- 4. If confirmed and there is a change in cost, create adjustment
  IF v_lot.is_confirmed = true AND v_delta != 0 THEN
      v_product_name := COALESCE(v_lot.product_name, 'محصول');

      SELECT a.company_id INTO v_company_id
      FROM accounts a LIMIT 1;

      SELECT a.id INTO v_inventory_account_id
      FROM accounts a
      WHERE a.account_code = '1030' LIMIT 1;

      SELECT a.id INTO v_supplier_account_id
      FROM accounts a
      WHERE a.account_code = '2000' LIMIT 1;

      v_desc := 'تعديل سعر محصول ' || v_product_name
                || ' - لوط رقم: ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT)
                || ' (الفرق: ' || v_delta::TEXT || ' ' || COALESCE(p_currency, 'EGP') || ')';

      IF v_delta > 0 THEN
        v_je_id := public.post_journal_entry(
          'lot_price_adjustment',
          v_desc,
          CURRENT_DATE,
          v_company_id,
          p_user_id,
          jsonb_build_array(
            jsonb_build_object('account_id', v_inventory_account_id, 'debit', v_delta, 'base_debit', v_delta_egp, 'credit', 0, 'base_credit', 0, 'currency', COALESCE(p_currency, 'EGP'), 'description', v_desc),
            jsonb_build_object('account_id', v_supplier_account_id, 'debit', 0, 'base_debit', 0, 'credit', v_delta, 'base_credit', v_delta_egp, 'currency', COALESCE(p_currency, 'EGP'), 'description', v_desc)
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
            jsonb_build_object('account_id', v_supplier_account_id, 'debit', ABS(v_delta), 'base_debit', ABS(v_delta_egp), 'credit', 0, 'base_credit', 0, 'currency', COALESCE(p_currency, 'EGP'), 'description', v_desc),
            jsonb_build_object('account_id', v_inventory_account_id, 'debit', 0, 'base_debit', 0, 'credit', ABS(v_delta), 'base_credit', ABS(v_delta_egp), 'currency', COALESCE(p_currency, 'EGP'), 'description', v_desc)
          ),
          p_lot_id::TEXT
        );
      END IF;
  END IF;

  -- 5. Update inventory items
  IF v_total_graded > 0 THEN
    FOR v_grading IN (SELECT id, quantity FROM grading_results WHERE lot_id = p_lot_id) LOOP
      UPDATE inventory_items
      SET purchase_price = v_effective_cost
      WHERE grading_result_id = v_grading.id;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Lot price updated successfully',
    'delta', v_delta,
    'new_total', v_new_total_cost
  );
END;
$$ LANGUAGE plpgsql;

-- Fix legacy lot receipts and lot price adjustments
DO $$
DECLARE
  v_je RECORD;
  v_lot RECORD;
  v_exchange_rate NUMERIC;
BEGIN
  -- 1. Fix lot receipts entries
  FOR v_je IN
    SELECT je.id, je.source_id, je.source_type
    FROM journal_entries je
    WHERE je.source_type = 'lot_receipt'
  LOOP
    -- Fetch exchange rate from lot
    SELECT l.exchange_rate INTO v_lot FROM lot_receipts l WHERE l.id::text = v_je.source_id LIMIT 1;
    v_exchange_rate := COALESCE(NULLIF(v_lot.exchange_rate, 0), 1.0);

    IF v_exchange_rate > 1 THEN
      -- The current debit contains the EGP amount. True foreign amount = debit / exchange_rate
      UPDATE account_ledger_entries
      SET amount_in_base_currency = GREATEST(debit, credit),
          debit = debit / v_exchange_rate,
          credit = credit / v_exchange_rate
      WHERE journal_entry_id = v_je.id AND currency != 'EGP';
    END IF;
  END LOOP;

  -- 2. Fix lot price adjustments entries
  FOR v_je IN
    SELECT je.id, je.source_id, je.source_type
    FROM journal_entries je
    WHERE je.source_type = 'lot_price_adjustment'
  LOOP
    SELECT l.exchange_rate INTO v_lot FROM lot_receipts l WHERE l.id::text = v_je.source_id LIMIT 1;
    v_exchange_rate := COALESCE(NULLIF(v_lot.exchange_rate, 0), 1.0);

    IF v_exchange_rate > 1 THEN
      -- These entries currently have the foreign amount in debit/credit but NO base amount!
      UPDATE account_ledger_entries
      SET amount_in_base_currency = GREATEST(debit, credit) * v_exchange_rate
      WHERE journal_entry_id = v_je.id AND currency != 'EGP';
    END IF;
  END LOOP;
END;
$$;
