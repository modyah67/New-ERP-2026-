CREATE OR REPLACE FUNCTION public.rpc_cancel_packing_order(
  p_packing_order_id bigint
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order           RECORD;
  v_notes           JSONB;
  v_station_id      INTEGER;
  v_allocations     JSONB := '[]'::jsonb;
  v_el              JSONB;
  r_cost            RECORD;
  r_line            RECORD;
  r_ale             RECORD;
  v_treasury_tx     RECORD;
  v_treasury_bal    RECORD;
  v_reversal_tx_id  BIGINT;
  v_bank_tx         RECORD;
  v_bank_bal_diff   NUMERIC;
  v_supplier_id     UUID;
  v_rate            NUMERIC;
  v_amt_foreign     NUMERIC;
  v_curr            TEXT;
  v_had_treasury_tx BOOLEAN;
  v_had_bank_tx     BOOLEAN;
  v_je_id           BIGINT;
  v_rev_je_id       BIGINT;
  v_entry_num       TEXT;
  v_company_id      UUID;
  v_sold_sortings   INT;
  i                 INT;
BEGIN
  SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  IF v_order.status != 'completed' THEN
    RETURN json_build_object('success', false, 'error', 'لا يمكن إلغاء أمر تعبئة بحالة ' || v_order.status);
  END IF;

  SELECT COUNT(*) INTO v_sold_sortings
  FROM public.packing_order_sortings
  WHERE packing_order_id = p_packing_order_id
    AND (status = 'sold' OR COALESCE(total_sale_amount, 0) > 0);

  IF v_sold_sortings > 0 THEN
    RETURN json_build_object('success', false, 'error', 'لا يمكن الإلغاء: يوجد فرز مباع مرتبط بالأمر');
  END IF;

  v_station_id := v_order.station_id;
  IF v_station_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'لم يتم تحديد المحطة');
  END IF;

  -- 1. Create reversing journal entry (keep original for audit)
  v_je_id := v_order.journal_entry_id;
  IF v_je_id IS NULL THEN
    SELECT id INTO v_je_id
    FROM public.journal_entries
    WHERE source_type = 'packing_order' AND source_id = p_packing_order_id::text
    ORDER BY id DESC LIMIT 1;
  END IF;

  IF v_je_id IS NOT NULL THEN
    SELECT company_id INTO v_company_id FROM public.journal_entries WHERE id = v_je_id;

    INSERT INTO public.journal_entries (
      entry_number, entry_date, description, status,
      is_auto_generated, source_type, source_id, company_id,
      created_by, created_at, updated_at
    ) VALUES (
      'PENDING',
      CURRENT_DATE,
      'عكس قيد أمر تعبئة رقم ' || COALESCE(v_order.order_number, p_packing_order_id::text)
        || ' (مرجع القيد الأصلي #' || v_je_id::text || ')',
      'posted', true, 'packing_order_reversal', p_packing_order_id::text,
      v_company_id, auth.uid(), NOW(), NOW()
    ) RETURNING id INTO v_rev_je_id;

    v_entry_num := fn_generate_journal_entry_number(v_rev_je_id);
    UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_rev_je_id;

    FOR r_ale IN
      SELECT * FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id
    LOOP
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency,
        amount_in_base_currency, description
      ) VALUES (
        v_rev_je_id,
        r_ale.account_id,
        COALESCE(r_ale.credit, 0),
        COALESCE(r_ale.debit, 0),
        COALESCE(r_ale.currency, 'EGP'),
        COALESCE(r_ale.amount_in_base_currency, COALESCE(r_ale.debit, 0) + COALESCE(r_ale.credit, 0)),
        'عكس: ' || COALESCE(r_ale.description, '')
      );
    END LOOP;

    UPDATE public.journal_entries
    SET description = COALESCE(description, '') || ' [تم عكسه بالقيد #' || v_rev_je_id::text || ']'
    WHERE id = v_je_id;
  END IF;

  -- 2. Reverse payments
  -- 20260811: User requested NOT to reverse cost items when cancelling an order.
  -- They want the cost items and their payments/supplier credits to remain intact.
  -- (The loop for packing_order_cost_items reversal has been completely removed)

  -- 3. Restore stock
  v_notes := CASE WHEN v_order.notes IS NOT NULL AND v_order.notes != ''
    THEN v_order.notes::jsonb ELSE '{}'::jsonb END;

  IF v_notes ? 'fruit_allocation' THEN
    v_el := v_notes->'fruit_allocation';
    IF jsonb_typeof(v_el) = 'array' THEN
      FOR i IN 0..jsonb_array_length(v_el) - 1 LOOP
        v_allocations := v_allocations || jsonb_build_array(v_el->i);
      END LOOP;
    ELSIF jsonb_typeof(v_el) = 'object' THEN
      v_allocations := v_allocations || jsonb_build_array(v_el);
    END IF;
  ELSE
    FOR r_line IN SELECT * FROM public.packing_order_lines WHERE packing_order_id = p_packing_order_id LOOP
      IF r_line.batch_id IS NOT NULL AND r_line.quantity > 0 THEN
        v_allocations := v_allocations || jsonb_build_array(
          jsonb_build_object(
            'batch_id', r_line.batch_id,
            'quantity', r_line.quantity,
            'product_name', r_line.product_name,
            'product_code', ''
          )
        );
      END IF;
    END LOOP;
  END IF;

  IF v_notes ? 'materials' THEN
    FOR v_el IN SELECT jsonb_array_elements(v_notes->'materials')
    LOOP
      v_allocations := v_allocations || jsonb_build_array(
        jsonb_build_object(
          'batch_id', v_el->>'batch_id',
          'quantity', v_el->>'used_qty',
          'product_name', v_el->>'product_name',
          'product_code', COALESCE(v_el->>'product_code', '')
        )
      );
    END LOOP;
  END IF;

  IF jsonb_array_length(v_allocations) > 0 THEN
    PERFORM restore_station_batch_allocations(v_station_id, v_allocations);
  END IF;

  -- 4. Delete pending (unsold) sortings
  DELETE FROM public.packing_order_sortings
  WHERE packing_order_id = p_packing_order_id
    AND status = 'pending'
    AND COALESCE(total_sale_amount, 0) = 0;

  -- 5. Mark cancelled
  UPDATE public.packing_orders
  SET status = 'cancelled',
      reversal_journal_entry_id = v_rev_je_id,
      updated_at = NOW()
  WHERE id = p_packing_order_id;

  RETURN json_build_object(
    'success', true,
    'original_journal_entry_id', v_je_id,
    'reversal_journal_entry_id', v_rev_je_id
  );
END;
$$;
