-- ============================================================================
-- Migration 371: Bank Account Draft and Confirm Workflow
-- ============================================================================
-- Adds Draft & Confirm support to Bank Account transactions:
-- 1. Adds 'status' and 'payload' columns to bank_account_transactions.
-- 2. Softens fiscal-year trigger for draft rows.
-- 3. Implements rpc_save_bank_draft.
-- 4. Implements rpc_update_bank_draft.
-- 5. Implements rpc_delete_bank_draft.
-- 6. Implements rpc_confirm_bank_draft.
-- ============================================================================

DO $$
BEGIN
    -- 1. Add status column (default 'confirmed' so all existing rows remain confirmed)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'bank_account_transactions' AND column_name = 'status'
    ) THEN
        ALTER TABLE public.bank_account_transactions 
        ADD COLUMN status TEXT NOT NULL DEFAULT 'confirmed';
    END IF;

    -- 2. Add payload column (JSONB for storing draft parameters)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'bank_account_transactions' AND column_name = 'payload'
    ) THEN
        ALTER TABLE public.bank_account_transactions 
        ADD COLUMN payload JSONB DEFAULT '{}'::jsonb;
    END IF;

    -- 3. Fix foreign currency bank accounts default book_rate
    UPDATE public.bank_accounts ba
    SET book_rate = COALESCE(
        (SELECT rate_to_egp FROM public.exchange_rates er WHERE er.currency_code = ba.currency LIMIT 1),
        CASE ba.currency WHEN 'USD' THEN 50.0 WHEN 'EUR' THEN 54.0 WHEN 'GBP' THEN 63.0 ELSE 50.0 END
    )
    WHERE ba.currency != 'EGP' AND (ba.book_rate <= 1.0 OR ba.book_rate IS NULL);
END $$;

-- ── Soften fiscal-year trigger for 'draft' bank transactions ──
CREATE OR REPLACE FUNCTION public.check_fiscal_year_allows_financial()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _fy_status text;
BEGIN
  -- Skip draft rows
  IF TG_TABLE_NAME IN ('bank_account_transactions', 'treasury_transactions')
     AND NEW.status = 'draft' THEN
    RETURN NEW;
  END IF;

  SELECT fy.status INTO _fy_status
  FROM public.fiscal_years fy
  WHERE fy.is_current = true
    AND fy.deleted_at IS NULL
  LIMIT 1;

  IF _fy_status IN ('CLOSING', 'CLOSED') THEN
    RAISE EXCEPTION 'لا يمكن إنشاء مستندات مالية في سنة مالية %', _fy_status;
  END IF;

  RETURN NEW;
END;
$$;

-- ── 1. RPC: Save Bank Draft ──
CREATE OR REPLACE FUNCTION public.rpc_save_bank_draft(
    p_bank_account_id BIGINT,
    p_type TEXT,
    p_amount NUMERIC,
    p_description TEXT DEFAULT NULL,
    p_notes TEXT DEFAULT NULL,
    p_entity_type TEXT DEFAULT NULL,
    p_entity_id TEXT DEFAULT NULL,
    p_counterparty_name TEXT DEFAULT NULL,
    p_payload JSONB DEFAULT '{}'::jsonb
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_tx_id BIGINT;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    INSERT INTO public.bank_account_transactions (
        bank_account_id,
        type,
        amount,
        balance_before,
        balance_after,
        description,
        notes,
        entity_type,
        entity_id,
        counterparty_name,
        status,
        payload,
        created_by,
        created_at
    ) VALUES (
        p_bank_account_id,
        p_type,
        p_amount,
        0,       -- draft: no balance impact
        0,       -- draft: no balance impact
        p_description,
        p_notes,
        p_entity_type,
        p_entity_id,
        p_counterparty_name,
        'draft',
        COALESCE(p_payload, '{}'::jsonb),
        auth.uid(),
        NOW()
    )
    RETURNING id INTO v_tx_id;

    RETURN v_tx_id;
END;
$$;

-- ── 2. RPC: Update Bank Draft ──
CREATE OR REPLACE FUNCTION public.rpc_update_bank_draft(
    p_transaction_id BIGINT,
    p_bank_account_id BIGINT DEFAULT NULL,
    p_type TEXT DEFAULT NULL,
    p_amount NUMERIC DEFAULT NULL,
    p_description TEXT DEFAULT NULL,
    p_notes TEXT DEFAULT NULL,
    p_entity_type TEXT DEFAULT NULL,
    p_entity_id TEXT DEFAULT NULL,
    p_counterparty_name TEXT DEFAULT NULL,
    p_payload JSONB DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    UPDATE public.bank_account_transactions
    SET
        bank_account_id = COALESCE(p_bank_account_id, bank_account_id),
        type = COALESCE(p_type, type),
        amount = COALESCE(p_amount, amount),
        description = COALESCE(p_description, description),
        notes = p_notes,
        entity_type = p_entity_type,
        entity_id = p_entity_id,
        counterparty_name = p_counterparty_name,
        payload = CASE WHEN p_payload IS NOT NULL THEN p_payload ELSE payload END
    WHERE id = p_transaction_id AND status = 'draft';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'لم يتم العثور على المسودة أو أنها مؤكدة بالفعل';
    END IF;

    RETURN TRUE;
END;
$$;

-- ── 3. RPC: Delete Bank Draft ──
CREATE OR REPLACE FUNCTION public.rpc_delete_bank_draft(
    p_transaction_id BIGINT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_deleted_count INT;
BEGIN
    DELETE FROM public.bank_account_transactions
    WHERE id = p_transaction_id AND status = 'draft';

    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    IF v_deleted_count = 0 THEN
        RAISE EXCEPTION 'لم يتم العثور على المسودة أو تم تأكيدها مسبقاً';
    END IF;

    RETURN TRUE;
END;
$$;

-- ── 4. RPC: Confirm Bank Draft ──
CREATE OR REPLACE FUNCTION public.rpc_confirm_bank_draft(
    p_transaction_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_tx RECORD;
    v_res JSONB;
BEGIN
    SELECT * INTO v_tx
    FROM public.bank_account_transactions
    WHERE id = p_transaction_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'الحركة غير موجودة';
    END IF;

    IF v_tx.status != 'draft' THEN
        RAISE EXCEPTION 'هذه الحركة مؤكدة بالفعل وليست مسودة';
    END IF;

    -- Case 1: Deposit
    IF v_tx.type = 'deposit' THEN
        v_res := public.deposit_bank_account(
            p_account_id        := v_tx.bank_account_id::bigint,
            p_amount            := v_tx.amount,
            p_description       := v_tx.description,
            p_revenue_account_id := COALESCE((v_tx.payload->>'revenue_account_id')::bigint, NULL),
            p_entity_type       := v_tx.entity_type,
            p_entity_id         := v_tx.entity_id,
            p_counterparty_name := v_tx.counterparty_name,
            p_source_type       := COALESCE(v_tx.payload->>'source_type', 'deposit'),
            p_notes             := v_tx.notes
        );

        -- Delete the original draft row since deposit_bank_account creates the confirmed transaction row
        DELETE FROM public.bank_account_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد الإيداع وترحيل القيد بنجاح', 'result', v_res);

    -- Case 2: Withdraw
    ELSIF v_tx.type = 'withdraw' THEN
        v_res := public.withdraw_bank_account(
            p_account_id        := v_tx.bank_account_id,
            p_amount            := v_tx.amount,
            p_description       := v_tx.description,
            p_entity_type       := v_tx.entity_type,
            p_entity_id         := v_tx.entity_id,
            p_counterparty_name := v_tx.counterparty_name,
            p_expense_account_id := COALESCE((v_tx.payload->>'expense_account_id')::integer, NULL),
            p_notes             := v_tx.notes,
            p_reference_type    := v_tx.payload->>'reference_type',
            p_reference_id      := v_tx.payload->>'reference_id'
        );

        -- Delete the original draft row
        DELETE FROM public.bank_account_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد الصرف وترحيل القيد بنجاح', 'result', v_res);

    -- Case 3: Currency Exchange
    ELSIF v_tx.type IN ('currency_exchange_out', 'currency_exchange_in', 'exchange') THEN
        v_res := public.exchange_bank_currency(
            p_from_account_id := v_tx.bank_account_id::integer,
            p_to_account_id   := (v_tx.payload->>'to_account_id')::integer,
            p_amount_from     := COALESCE((v_tx.payload->>'amount_from')::numeric, v_tx.amount),
            p_amount_to       := (v_tx.payload->>'amount_to')::numeric,
            p_exchange_rate   := (v_tx.payload->>'exchange_rate')::numeric
        );

        -- Delete the original draft row
        DELETE FROM public.bank_account_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد تحويل العملة وترحيل القيد بنجاح', 'result', v_res);

    -- Case 4: Bank Transfer (same currency)
    ELSIF v_tx.type = 'transfer' THEN
        PERFORM public.bank_transfer(
            p_from_account_id := v_tx.bank_account_id::integer,
            p_to_account_id   := (v_tx.payload->>'to_account_id')::integer,
            p_amount          := v_tx.amount,
            p_description     := v_tx.description,
            p_bank_fee        := COALESCE((v_tx.payload->>'bank_fee')::numeric, 0),
            p_notes           := v_tx.notes
        );

        -- Delete the original draft row
        DELETE FROM public.bank_account_transactions WHERE id = p_transaction_id;

        RETURN jsonb_build_object('success', true, 'message', 'تم تأكيد التحويل البنكي وترحيل القيد بنجاح');

    ELSE
        RAISE EXCEPTION 'نوع الحركة غير مدعوم: %', v_tx.type;
    END IF;
END;
$$;
