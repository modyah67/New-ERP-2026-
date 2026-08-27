-- ============================================================================
-- Migration: Full Financial Integration for Packing Order Cost Items Payment
-- Ensures treasury/bank deduction, transaction logging, and ledger entries.
-- ============================================================================

-- Redefine rpc_confirm_packing_order to process direct cost item payments safely
CREATE OR REPLACE FUNCTION public.rpc_confirm_packing_order(
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
  v_rate            NUMERIC;
  v_amt_egp         NUMERIC;
  v_amt_foreign     NUMERIC;
  v_curr            TEXT;
  r_cost            RECORD;
  v_supplier_id     UUID;
  v_tx_desc         TEXT;
  v_current_balance NUMERIC;
  v_treasury_tx_id  BIGINT;
  v_bank_tx_id      INTEGER;
BEGIN
  -- Fetch the packing order
  SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  IF v_order.status NOT IN ('draft', 'pending') THEN
    RETURN json_build_object('success', false, 'error', 'لا يمكن تأكيد أمر تعبئة بحالة ' || v_order.status);
  END IF;

  v_station_id := v_order.station_id;
  IF v_station_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'لم يتم تحديد المحطة');
  END IF;

  v_notes := CASE WHEN v_order.notes IS NOT NULL AND v_order.notes != ''
    THEN v_order.notes::jsonb ELSE '{}'::jsonb END;

  -- Sync legacy cost items from JSON notes to table if table is empty
  IF NOT EXISTS (SELECT 1 FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id) THEN
    IF v_notes ? 'cost_items' THEN
      FOR v_el IN SELECT jsonb_array_elements(v_notes->'cost_items')
      LOOP
        v_rate := COALESCE(NULLIF((v_el->>'exchange_rate')::numeric, 0), 1.0);
        v_amt_egp := COALESCE((v_el->>'total_egp')::numeric, (v_el->>'total')::numeric, 0);
        v_curr := COALESCE(NULLIF(v_el->>'supplier_currency', ''), 'EGP');

        INSERT INTO public.packing_order_cost_items (
          packing_order_id, name, category, report_category_id,
          original_currency, original_amount, exchange_rate, base_amount,
          currency_snapshot, payment_source_type, payment_source_id
        ) VALUES (
          p_packing_order_id,
          COALESCE(v_el->>'name', 'بند تكلفة'),
          'other',
          (v_el->>'report_category_id')::integer,
          v_curr,
          COALESCE((v_el->>'quantity')::numeric, 1.0) * COALESCE((v_el->>'unit_price')::numeric, v_amt_egp),
          v_rate,
          v_amt_egp,
          v_el,
          v_el->>'payment_source_type',
          NULLIF(v_el->>'payment_source_id', '')::bigint
        );
      END LOOP;
    END IF;
  END IF;

  -- Build fruit allocation entry
  IF v_notes ? 'fruit_allocation' THEN
    v_el := v_notes->'fruit_allocation';
    IF jsonb_typeof(v_el) = 'array' THEN
      FOR i IN 0..jsonb_array_length(v_el) - 1 LOOP
        v_allocations := v_allocations || jsonb_build_array(v_el->i);
      END LOOP;
    ELSIF jsonb_typeof(v_el) = 'object' THEN
      v_allocations := v_allocations || jsonb_build_array(v_el);
    END IF;
  END IF;

  -- Build material allocation entries
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

  -- Deduct from warehouse via existing RPC
  IF jsonb_array_length(v_allocations) > 0 THEN
    PERFORM deduct_station_batch_allocations(v_station_id, v_allocations);
  END IF;

  -- Process cost items for supplier balances and direct payments
  FOR r_cost IN
    SELECT poci.*, cr.name AS report_category_name
    FROM public.packing_order_cost_items poci
    LEFT JOIN public.cost_report_categories cr ON cr.id = poci.report_category_id
    WHERE poci.packing_order_id = p_packing_order_id
  LOOP
    -- 1. Fetch supplier ID from currency_snapshot
    v_supplier_id := NULL;
    IF r_cost.currency_snapshot IS NOT NULL AND r_cost.currency_snapshot ? 'supplier_id' THEN
      v_supplier_id := NULLIF(r_cost.currency_snapshot->>'supplier_id', '')::uuid;
    END IF;

    -- 2. Process Supplier outstanding balance and ledger entries if supplier is selected
    IF v_supplier_id IS NOT NULL THEN
      v_rate := COALESCE(NULLIF(r_cost.exchange_rate, 0), 1.0);
      v_amt_foreign := ROUND(r_cost.base_amount / v_rate, 2);
      v_curr := COALESCE(NULLIF(r_cost.original_currency, ''), 'EGP');

      IF v_amt_foreign > 0 THEN
        UPDATE public.suppliers
        SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_amt_foreign,
            updated_at = now()
        WHERE id = v_supplier_id;

        INSERT INTO public.ledger_entries (
          entity_type, entity_id, entry_type, amount, currency,
          reference_type, reference_text, description, created_by
        ) VALUES (
          'supplier', v_supplier_id::text, 'credit', v_amt_foreign, v_curr,
          'packing_cost', p_packing_order_id::text,
          'بند تكلفة أمر تعبئة: ' || COALESCE(r_cost.name, 'غير محدد') || ' (أمر ' || p_packing_order_id::text || ')',
          auth.uid()
        );
      END IF;
    END IF;

    -- 3. Direct payment processing if payment source is selected and not already paid
    IF r_cost.payment_source_type IS NOT NULL AND r_cost.payment_source_id IS NOT NULL 
       AND r_cost.treasury_transaction_id IS NULL AND r_cost.bank_transaction_id IS NULL THEN
      
      v_tx_desc := 'سداد بند تكلفة أمر تعبئة: ' || COALESCE(r_cost.name, 'غير محدد') || ' (أمر ' || p_packing_order_id::text || ')';

      IF r_cost.payment_source_type = 'treasury' THEN
        -- Check Safe balance first (FOR UPDATE lock)
        SELECT balance INTO v_current_balance
        FROM public.treasury_balances
        WHERE treasury_id = r_cost.payment_source_id AND currency = r_cost.original_currency
        FOR UPDATE;

        IF v_current_balance IS NULL OR v_current_balance < r_cost.original_amount THEN
          RAISE EXCEPTION 'الرصيد غير كافٍ في الخزينة المحددة للبند % (المتوفر: %, المطلوب: %)', r_cost.name, COALESCE(v_current_balance, 0), r_cost.original_amount;
        END IF;

        -- Deduct custody from treasury & log transaction
        PERFORM public.spend_custody(
          r_cost.payment_source_id,
          r_cost.original_currency,
          r_cost.original_amount,
          v_tx_desc,
          NULL, -- customer_id
          v_supplier_id,
          NULL, -- clearing_agent_id
          NULL, -- shipping_company_id
          NULL  -- shareholder_id
        );

        -- Retrieve newly generated transaction ID
        SELECT id INTO v_treasury_tx_id
        FROM public.treasury_transactions
        WHERE treasury_id = r_cost.payment_source_id
          AND type = 'expense'
          AND amount = r_cost.original_amount
          AND currency = r_cost.original_currency
        ORDER BY created_at DESC
        LIMIT 1;

        -- Stamp cost item with transaction ID
        UPDATE public.packing_order_cost_items
        SET treasury_transaction_id = v_treasury_tx_id
        WHERE id = r_cost.id;

      ELSIF r_cost.payment_source_type = 'bank' THEN
        -- Check Bank Account balance first (FOR UPDATE lock)
        SELECT balance INTO v_current_balance 
        FROM public.bank_accounts 
        WHERE id = r_cost.payment_source_id
        FOR UPDATE;

        IF v_current_balance IS NULL OR v_current_balance < r_cost.original_amount THEN
          RAISE EXCEPTION 'الرصيد غير كافٍ في البنك المحدد للبند % (المتوفر: %, المطلوب: %)', r_cost.name, COALESCE(v_current_balance, 0), r_cost.original_amount;
        END IF;

        -- Withdraw from bank account & log transaction
        SELECT (public.withdraw_bank_account(
          r_cost.payment_source_id::integer,
          r_cost.original_amount,
          v_tx_desc,
          CASE WHEN v_supplier_id IS NOT NULL THEN 'supplier' ELSE NULL END,
          v_supplier_id::text,
          NULL -- counterparty_name
        )->>'id')::integer INTO v_bank_tx_id;

        -- Stamp bank transaction metadata
        UPDATE public.bank_account_transactions
        SET currency_snapshot = r_cost.currency_snapshot
        WHERE id = v_bank_tx_id;

        -- Stamp cost item with transaction ID
        UPDATE public.packing_order_cost_items
        SET bank_transaction_id = v_bank_tx_id
        WHERE id = r_cost.id;

      END IF;
    END IF;
  END LOOP;

  -- Set packing order status to completed
  UPDATE public.packing_orders
    SET status = 'completed',
        packed_at = NOW(),
        updated_at = NOW()
  WHERE id = p_packing_order_id;

  RETURN json_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_confirm_packing_order(bigint) TO authenticated;
