-- ============================================================================
-- Migration: Phase 2 v3 - Fix rpc_cancel_packing_order
--
-- Critical fixes over v2:
--   1. AUDIT TRAIL: Instead of DELETE-ing the original treasury_transaction,
--      we now INSERT a new 'return_in' record to restore the balance.
--      The original expense record is preserved for full historical audit.
--   2. LOCKING: Use SELECT ... FOR UPDATE on treasury_balances to prevent
--      Race Conditions when two cancellations or a cancel + confirm hit
--      the same treasury concurrently.
--   3. CORRECTNESS: The cost_item stamp (treasury_transaction_id) is still
--      cleared to NULL so the UI knows payment was reversed.
--   4. Supplier balance logic unchanged from v2 (correct):
--      - Paid items → no supplier balance change on cancel (net was 0).
--      - Credit items → subtract outstanding_balance + delete ledger entry.
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
  v_treasury_bal    RECORD;
  v_reversal_tx_id  BIGINT;
  -- bank reversal
  v_bank_tx         RECORD;
  v_bank_bal_diff   NUMERIC;
  -- supplier reversal (credit items only)
  v_supplier_id     UUID;
  v_rate            NUMERIC;
  v_amt_foreign     NUMERIC;
  v_curr            TEXT;
  -- snapshot flags
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
    v_had_treasury_tx := (r_cost.treasury_transaction_id IS NOT NULL);
    v_had_bank_tx     := (r_cost.bank_transaction_id IS NOT NULL);

    -- Extract supplier ID
    v_supplier_id := NULL;
    IF r_cost.currency_snapshot IS NOT NULL AND r_cost.currency_snapshot ? 'supplier_id' THEN
      v_supplier_id := NULLIF(r_cost.currency_snapshot->>'supplier_id', '')::uuid;
    END IF;

    -- ── 2a. Reverse treasury payment ──
    -- Strategy: INSERT a new 'return_in' record (preserves audit history).
    -- The original 'expense' record stays. We lock the balance row first
    -- to prevent concurrent modifications (Race Condition protection).
    IF v_had_treasury_tx THEN
      SELECT * INTO v_treasury_tx
      FROM public.treasury_transactions
      WHERE id = r_cost.treasury_transaction_id;

      IF FOUND THEN
        -- Lock the balance row FOR UPDATE to prevent Race Condition
        SELECT * INTO v_treasury_bal
        FROM public.treasury_balances
        WHERE treasury_id = v_treasury_tx.treasury_id
          AND currency   = v_treasury_tx.currency
        FOR UPDATE;

        IF NOT FOUND THEN
          RAISE EXCEPTION 'سجل رصيد الخزينة غير موجود للخزينة % عملة %',
            v_treasury_tx.treasury_id, v_treasury_tx.currency;
        END IF;

        -- Restore the balance by adding back the original expense amount
        UPDATE public.treasury_balances
        SET balance    = v_treasury_bal.balance + v_treasury_tx.amount,
            updated_at = NOW()
        WHERE treasury_id = v_treasury_tx.treasury_id
          AND currency   = v_treasury_tx.currency;

        -- Insert reversal record (NEW record, original preserved)
        INSERT INTO public.treasury_transactions (
          treasury_id, type, currency, amount,
          balance_before, balance_after,
          description, supplier_id, created_by
        ) VALUES (
          v_treasury_tx.treasury_id,
          'return_in',
          v_treasury_tx.currency,
          v_treasury_tx.amount,
          v_treasury_bal.balance,
          v_treasury_bal.balance + v_treasury_tx.amount,
          'عكس سداد بند تكلفة أمر تعبئة ملغي: أمر ' || p_packing_order_id::text
            || ' (مرجع قيد: ' || v_treasury_tx.id::text || ')',
          v_treasury_tx.supplier_id,
          auth.uid()
        ) RETURNING id INTO v_reversal_tx_id;

        -- Clear stamp on cost item (mark as reversed)
        UPDATE public.packing_order_cost_items
        SET treasury_transaction_id = NULL
        WHERE id = r_cost.id;
      END IF;
    END IF;

    -- ── 2b. Reverse bank payment ──
    -- Same strategy: restore balance + insert reversal record, no DELETE.
    IF v_had_bank_tx THEN
      SELECT * INTO v_bank_tx
      FROM public.bank_account_transactions
      WHERE id = r_cost.bank_transaction_id;

      IF FOUND THEN
        -- Restore bank balance (expense was a withdrawal, so add back)
        IF v_bank_tx.type = 'deposit' THEN
          v_bank_bal_diff := -v_bank_tx.amount;
        ELSE
          v_bank_bal_diff := v_bank_tx.amount;
        END IF;

        UPDATE public.bank_accounts
        SET balance = balance + v_bank_bal_diff
        WHERE id = v_bank_tx.bank_account_id;

        -- Insert bank reversal record (balance_before = restored balance minus the diff already applied)
        INSERT INTO public.bank_account_transactions (
          bank_account_id, type, amount,
          balance_before, balance_after,
          description, entity_type, entity_id, created_by
        )
        SELECT
          v_bank_tx.bank_account_id,
          CASE WHEN v_bank_tx.type = 'deposit' THEN 'withdrawal' ELSE 'deposit' END,
          v_bank_tx.amount,
          ba.balance - v_bank_bal_diff,   -- what it was just before our UPDATE
          ba.balance,                      -- what it is now (after our UPDATE)
          'عكس سداد بند تكلفة أمر تعبئة ملغي: أمر ' || p_packing_order_id::text
            || ' (مرجع قيد: ' || v_bank_tx.id::text || ')',
          v_bank_tx.entity_type,
          v_bank_tx.entity_id,
          auth.uid()
        FROM public.bank_accounts ba
        WHERE ba.id = v_bank_tx.bank_account_id;

        -- Clear stamp on cost item
        UPDATE public.packing_order_cost_items
        SET bank_transaction_id = NULL
        WHERE id = r_cost.id;
      END IF;
    END IF;

    -- ── 2c. Reverse supplier credit for UNPAID/CREDIT items only ──
    -- Net supplier effect for paid items was 0 at confirmation → no change needed here.
    -- For credit (unpaid) items, outstanding_balance was increased → subtract it back.
    IF NOT v_had_treasury_tx AND NOT v_had_bank_tx AND v_supplier_id IS NOT NULL THEN
      v_rate        := COALESCE(NULLIF(r_cost.exchange_rate, 0), 1.0);
      v_curr        := COALESCE(NULLIF(r_cost.original_currency, ''), 'EGP');
      v_amt_foreign := ROUND(r_cost.base_amount / v_rate, 2);

      IF v_amt_foreign > 0 THEN
        UPDATE public.suppliers
        SET outstanding_balance = GREATEST(0, COALESCE(outstanding_balance, 0) - v_amt_foreign)
        WHERE id = v_supplier_id;

        -- Delete the matching ledger credit entry from confirmation time
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
