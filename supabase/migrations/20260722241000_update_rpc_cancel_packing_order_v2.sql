-- ============================================================================
-- Migration: Phase 2 - Update rpc_cancel_packing_order (v2 fix - correct supplier reversal)
-- Applied as a separate file to override the v1 that was already pushed.
--
-- Key fix: For paid cost items, the net supplier balance change during confirmation
-- is ZERO (credit +amount via step 2, then debit -amount via spend_custody).
-- Therefore, during cancellation of paid items, we must NOT touch supplier balance.
-- Only unpaid/credit items (no treasury/bank stamp) need their supplier credit reversed.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.rpc_cancel_packing_order(p_packing_order_id bigint)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_order           RECORD;
  v_notes           JSONB;
  v_station_id      INTEGER;
  v_allocations     JSONB := '[]'::jsonb;
  v_el              JSONB;
  r_cost            RECORD;
  -- treasury reversal
  v_treasury_tx     RECORD;
  v_new_safe_bal    NUMERIC;
  -- bank reversal
  v_bank_tx         RECORD;
  v_bank_bal_diff   NUMERIC;
  -- supplier reversal (for credit/unpaid items only)
  v_supplier_id     UUID;
  v_rate            NUMERIC;
  v_amt_foreign     NUMERIC;
  v_curr            TEXT;
  -- local flags to track ORIGINAL stamp state before modifications
  v_had_treasury_tx BOOLEAN;
  v_had_bank_tx     BOOLEAN;
BEGIN
  -- ── 1. Load and validate order ──
  SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  IF v_order.status != 'completed' THEN
    RETURN json_build_object('success', false, 'error', 'لا يمكن إلغاء أمر تعبئة بحالة ' || v_order.status);
  END IF;

  v_station_id := v_order.station_id;
  IF v_station_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'لم يتم تحديد المحطة');
  END IF;

  -- ── 2. Reverse cost items ──
  FOR r_cost IN
    SELECT * FROM public.packing_order_cost_items
    WHERE packing_order_id = p_packing_order_id
  LOOP
    -- Snapshot original stamp flags from the SELECT (immutable within loop)
    v_had_treasury_tx := (r_cost.treasury_transaction_id IS NOT NULL);
    v_had_bank_tx     := (r_cost.bank_transaction_id IS NOT NULL);

    -- Extract supplier ID from currency_snapshot
    v_supplier_id := NULL;
    IF r_cost.currency_snapshot IS NOT NULL AND r_cost.currency_snapshot ? 'supplier_id' THEN
      v_supplier_id := NULLIF(r_cost.currency_snapshot->>'supplier_id', '')::uuid;
    END IF;

    -- ── 2a. Reverse treasury payment (if stamped) ──
    -- IMPORTANT: Do NOT touch supplier balance here.
    -- Reason: at confirmation time, the confirm RPC did:
    --   1) suppliers.outstanding_balance += amount  (credit entry for all items)
    --   2) spend_custody() → suppliers.outstanding_balance -= amount  (payment debit)
    -- Net effect = 0. So cancelling a paid item requires 0 supplier balance change.
    IF v_had_treasury_tx THEN
      SELECT * INTO v_treasury_tx
      FROM public.treasury_transactions
      WHERE id = r_cost.treasury_transaction_id;

      IF FOUND THEN
        -- Recalculate safe balance from remaining transactions (excluding this one)
        SELECT COALESCE(SUM(
          CASE
            WHEN type IN ('expense', 'withdrawal', 'transfer_out', 'return_out', 'disbursement_out')
            THEN -amount
            ELSE amount
          END
        ), 0) INTO v_new_safe_bal
        FROM public.treasury_transactions
        WHERE treasury_id = v_treasury_tx.treasury_id
          AND currency   = v_treasury_tx.currency
          AND id         != r_cost.treasury_transaction_id;

        UPDATE public.treasury_balances
        SET balance = v_new_safe_bal, updated_at = NOW()
        WHERE treasury_id = v_treasury_tx.treasury_id
          AND currency   = v_treasury_tx.currency;

        DELETE FROM public.treasury_transactions WHERE id = r_cost.treasury_transaction_id;

        UPDATE public.packing_order_cost_items
        SET treasury_transaction_id = NULL
        WHERE id = r_cost.id;
      END IF;
    END IF;

    -- ── 2b. Reverse bank payment (if stamped) ──
    -- IMPORTANT: Same principle — do NOT touch supplier balance here.
    IF v_had_bank_tx THEN
      SELECT * INTO v_bank_tx
      FROM public.bank_account_transactions
      WHERE id = r_cost.bank_transaction_id;

      IF FOUND THEN
        IF v_bank_tx.type = 'deposit' THEN
          v_bank_bal_diff := -v_bank_tx.amount;
        ELSE
          v_bank_bal_diff := v_bank_tx.amount;
        END IF;

        UPDATE public.bank_accounts
        SET balance = balance + v_bank_bal_diff
        WHERE id = v_bank_tx.bank_account_id;

        -- Fix subsequent transaction balance trail
        IF v_bank_tx.type = 'deposit' THEN
          UPDATE public.bank_account_transactions
          SET balance_before = balance_before - v_bank_tx.amount,
              balance_after  = balance_after  - v_bank_tx.amount
          WHERE bank_account_id = v_bank_tx.bank_account_id
            AND id > r_cost.bank_transaction_id;
        ELSE
          UPDATE public.bank_account_transactions
          SET balance_before = balance_before + v_bank_tx.amount,
              balance_after  = balance_after  + v_bank_tx.amount
          WHERE bank_account_id = v_bank_tx.bank_account_id
            AND id > r_cost.bank_transaction_id;
        END IF;

        DELETE FROM public.bank_account_transactions WHERE id = r_cost.bank_transaction_id;

        UPDATE public.packing_order_cost_items
        SET bank_transaction_id = NULL
        WHERE id = r_cost.id;
      END IF;
    END IF;

    -- ── 2c. Reverse supplier credit for UNPAID/CREDIT items only ──
    -- These items had their supplier outstanding_balance increased (+amount) at
    -- confirmation but were never paid, so we subtract that credit back.
    IF NOT v_had_treasury_tx AND NOT v_had_bank_tx AND v_supplier_id IS NOT NULL THEN
      v_rate        := COALESCE(NULLIF(r_cost.exchange_rate, 0), 1.0);
      v_curr        := COALESCE(NULLIF(r_cost.original_currency, ''), 'EGP');
      v_amt_foreign := ROUND(r_cost.base_amount / v_rate, 2);

      IF v_amt_foreign > 0 THEN
        UPDATE public.suppliers
        SET outstanding_balance = GREATEST(0, COALESCE(outstanding_balance, 0) - v_amt_foreign)
        WHERE id = v_supplier_id;

        -- Delete the matching ledger credit entry created at confirmation time
        DELETE FROM public.ledger_entries
        WHERE id = (
          SELECT id FROM public.ledger_entries
          WHERE entity_type    = 'supplier'
            AND entity_id      = v_supplier_id::text
            AND entry_type     = 'credit'
            AND reference_type = 'packing_cost'
            AND reference_text = p_packing_order_id::text
            AND amount         = v_amt_foreign
          ORDER BY created_at DESC
          LIMIT 1
        );
      END IF;
    END IF;
  END LOOP;

  -- ── 3. Restore stock / material allocations ──
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
  END IF;

  IF v_notes ? 'materials' THEN
    FOR v_el IN SELECT jsonb_array_elements(v_notes->'materials')
    LOOP
      v_allocations := v_allocations || jsonb_build_array(
        jsonb_build_object(
          'batch_id',    v_el->>'batch_id',
          'quantity',    v_el->>'used_qty',
          'product_name',v_el->>'product_name',
          'product_code',COALESCE(v_el->>'product_code', '')
        )
      );
    END LOOP;
  END IF;

  IF jsonb_array_length(v_allocations) > 0 THEN
    PERFORM restore_station_batch_allocations(v_station_id, v_allocations);
  END IF;

  -- ── 4. Mark order as cancelled ──
  UPDATE public.packing_orders
  SET status = 'cancelled', updated_at = NOW()
  WHERE id = p_packing_order_id;

  RETURN json_build_object('success', true);
END;
$$;
