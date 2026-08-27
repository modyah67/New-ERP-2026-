-- Migration 108: Phase 2 — Profitability Edit/Revision Workflow + Journal History
--
-- 0. Add revision_number column to shipment_cost_items
-- 1. Fix post_journal_entry to store source_id in journal_entries
-- 2. Update spend_custody to accept p_reference_type/p_reference_id and forward to journal_entries
-- 3. Create rpc_edit_profitability_expense: atomic reversal + new entry + financial correction
-- 4. Create rpc_get_profitability_journal_entries: fetch all entries for a shipment's cost items
-- 5. Backfill: link existing journal entries to cost items via treasury_transactions/bank_account_transactions

-- ============================================================================
-- SECTION 0: Add revision_number column
-- ============================================================================

ALTER TABLE public.shipment_cost_items
  ADD COLUMN IF NOT EXISTS revision_number INTEGER DEFAULT 0;

-- ============================================================================
-- SECTION 1: Fix post_journal_entry — store source_id
-- ============================================================================

DROP FUNCTION IF EXISTS public.post_journal_entry(TEXT, TEXT, DATE, UUID, UUID, JSONB);

CREATE OR REPLACE FUNCTION public.post_journal_entry(
    p_source_type  TEXT,
    p_description  TEXT,
    p_entry_date   DATE,
    p_company_id   UUID,
    p_created_by   UUID,
    p_lines        JSONB,
    p_source_id    TEXT DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_je_id         BIGINT;
    v_entry_number  TEXT;
    v_total_debit   NUMERIC := 0;
    v_total_credit  NUMERIC := 0;
    v_line          JSONB;
    v_account_id    BIGINT;
    v_debit         NUMERIC;
    v_credit        NUMERIC;
    v_currency      TEXT;
    v_desc          TEXT;
    v_line_count    INT;
BEGIN
    v_line_count := jsonb_array_length(p_lines);
    IF v_line_count IS NULL OR v_line_count < 2 THEN
        RAISE EXCEPTION 'Journal entry must have at least 2 lines (got %)', v_line_count;
    END IF;

    IF p_company_id IS NULL THEN
        RAISE EXCEPTION 'Company ID cannot be NULL';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM sys_companies WHERE id = p_company_id) THEN
        RAISE EXCEPTION 'Company % not found in sys_companies', p_company_id;
    END IF;

    v_entry_number := public.fn_get_next_sequence(p_company_id, p_source_type, NULL, NULL);

    INSERT INTO journal_entries (
        entry_number, entry_date, description, status,
        is_auto_generated, source_type, source_id, created_by, company_id
    ) VALUES (
        v_entry_number, p_entry_date, p_description, 'posted',
        true, p_source_type, p_source_id, p_created_by, p_company_id
    ) RETURNING id INTO v_je_id;

    FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines)
    LOOP
        v_account_id := (v_line->>'account_id')::BIGINT;
        v_debit      := COALESCE((v_line->>'debit')::NUMERIC, 0);
        v_credit     := COALESCE((v_line->>'credit')::NUMERIC, 0);
        v_currency   := COALESCE(v_line->>'currency', 'EGP');
        v_desc       := COALESCE(v_line->>'description', p_description);

        IF NOT EXISTS (SELECT 1 FROM accounts WHERE id = v_account_id) THEN
            RAISE EXCEPTION 'GL Account ID % not found in accounts table', v_account_id;
        END IF;

        IF v_debit < 0 OR v_credit < 0 THEN
            RAISE EXCEPTION 'Debit and credit amounts must be non-negative';
        END IF;
        IF v_debit = 0 AND v_credit = 0 THEN
            RAISE EXCEPTION 'Both debit and credit cannot be zero for a single line';
        END IF;
        IF v_debit > 0 AND v_credit > 0 THEN
            RAISE EXCEPTION 'A single line cannot have both debit and credit';
        END IF;

        v_total_debit  := v_total_debit + v_debit;
        v_total_credit := v_total_credit + v_credit;

        INSERT INTO account_ledger_entries (
            journal_entry_id, account_id, debit, credit,
            currency, amount_in_base_currency, description, company_id
        ) VALUES (
            v_je_id, v_account_id, v_debit, v_credit,
            v_currency, COALESCE(v_debit, 0) + COALESCE(v_credit, 0), v_desc, p_company_id
        );
    END LOOP;

    IF v_total_debit != v_total_credit THEN
        RAISE EXCEPTION 'Journal entry is not balanced: total debit % != total credit %', v_total_debit, v_total_credit;
    END IF;
    IF v_total_debit = 0 THEN
        RAISE EXCEPTION 'Journal entry has zero total amount';
    END IF;

    RETURN v_je_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.post_journal_entry(TEXT, TEXT, DATE, UUID, UUID, JSONB, TEXT) TO authenticated, service_role, anon;

-- ============================================================================
-- SECTION 2: Update spend_custody — accept reference params, forward to JE
-- ============================================================================

DROP FUNCTION IF EXISTS public.spend_custody(BIGINT, TEXT, NUMERIC, TEXT, INTEGER, UUID, BIGINT, BIGINT, UUID, INTEGER, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.spend_custody(
    p_treasury_id          BIGINT,
    p_currency             TEXT,
    p_amount               NUMERIC,
    p_description          TEXT DEFAULT '',
    p_customer_id          INTEGER DEFAULT NULL,
    p_supplier_id          UUID DEFAULT NULL,
    p_clearing_agent_id    BIGINT DEFAULT NULL,
    p_shipping_company_id  BIGINT DEFAULT NULL,
    p_shareholder_id       UUID DEFAULT NULL,
    p_expense_account_id   INTEGER DEFAULT NULL,
    p_reference_type       TEXT DEFAULT NULL,
    p_reference_id         TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_current_balance NUMERIC;
    v_new_balance     NUMERIC;
    v_tx_id           BIGINT;
    v_company_id      UUID;
    v_treasury_acct   BIGINT;
    v_expense_acct    BIGINT;
    v_je_id           BIGINT;
    v_desc            TEXT;
    v_tx_type         TEXT;
    v_supplier_leaf   INTEGER;
BEGIN
    -- Resolve GL account
    IF p_expense_account_id IS NOT NULL THEN
        SELECT id INTO v_expense_acct FROM accounts
        WHERE id = p_expense_account_id AND is_leaf = true AND is_active = true AND account_type = 'expense';
        IF v_expense_acct IS NULL THEN
            RAISE EXCEPTION 'الحساب المحدد غير صالح — يجب أن يكون حساب مصروفات ورقي ونشط';
        END IF;
        v_tx_type := 'expense';
    ELSIF p_supplier_id IS NOT NULL THEN
        SELECT s.account_id INTO v_supplier_leaf
        FROM suppliers s WHERE s.id = p_supplier_id;
        IF v_supplier_leaf IS NULL THEN
            RAISE EXCEPTION 'المورد لا يمتلك حساب في شجرة الحسابات';
        END IF;
        SELECT id INTO v_expense_acct FROM accounts
        WHERE id = v_supplier_leaf AND is_leaf = true AND is_active = true;
        IF v_expense_acct IS NULL THEN
            RAISE EXCEPTION 'حساب المورد غير موجود أو غير نشط في شجرة الحسابات';
        END IF;
        v_tx_type := 'supplier_payment';
    ELSE
        RAISE EXCEPTION 'يجب اختيار حساب مصروفات من شجرة الحسابات أو تحديد مورد';
    END IF;

    SELECT balance INTO v_current_balance
    FROM public.treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    IF v_current_balance IS NULL OR v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ في % (المتوفر: %)', p_currency, COALESCE(v_current_balance, 0);
    END IF;

    v_new_balance := v_current_balance - p_amount;

    UPDATE public.treasury_balances
    SET balance = v_new_balance, updated_at = NOW()
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;

    v_desc := COALESCE(NULLIF(p_description, ''), 'صرف خزينة');

    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description,
        expense_account_id,
        customer_id, supplier_id, clearing_agent_id, shipping_company_id, shareholder_id,
        balance_before, balance_after,
        reference_type, reference_id,
        created_by
    ) VALUES (
        p_treasury_id, v_tx_type, p_amount, p_currency, v_desc,
        p_expense_account_id,
        p_customer_id, p_supplier_id, p_clearing_agent_id, p_shipping_company_id, p_shareholder_id,
        v_current_balance, v_new_balance,
        p_reference_type, p_reference_id,
        auth.uid()
    ) RETURNING id INTO v_tx_id;

    -- Update Counterparty balances and ledger entries
    IF p_customer_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance + p_amount WHERE id = p_customer_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('customer', p_customer_id::TEXT, 'debit', p_amount, p_currency, v_tx_type, v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_supplier_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance - p_amount WHERE id = p_supplier_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('supplier', p_supplier_id::TEXT, 'credit', p_amount, p_currency, v_tx_type, v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_clearing_agent_id IS NOT NULL THEN
        UPDATE public.clearing_agents SET balance = balance - p_amount WHERE id = p_clearing_agent_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('clearing_agent', p_clearing_agent_id::TEXT, 'debit', p_amount, p_currency, v_tx_type, v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_shipping_company_id IS NOT NULL THEN
        UPDATE public.shipping_companies SET balance = balance - p_amount WHERE id = p_shipping_company_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('shipping_company', p_shipping_company_id::TEXT, 'debit', p_amount, p_currency, v_tx_type, v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_shareholder_id IS NOT NULL THEN
        IF p_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - p_amount WHERE id = p_shareholder_id;
        END IF;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('shareholder', p_shareholder_id::TEXT, 'debit', p_amount, p_currency, v_tx_type, v_tx_id, v_desc, auth.uid());
    END IF;

    -- Update Purchase Invoice if reference provided
    IF p_reference_type = 'purchase_invoice' AND p_reference_id IS NOT NULL THEN
        UPDATE public.purchase_invoices
        SET paid_amount = COALESCE(paid_amount, 0) + p_amount,
            remaining_amount = GREATEST(0, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - (COALESCE(paid_amount, 0) + p_amount)),
            payment_status = CASE
                WHEN GREATEST(0, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - (COALESCE(paid_amount, 0) + p_amount)) <= 0.001 THEN 'paid'
                ELSE 'partial'
            END,
            updated_at = NOW()
        WHERE id::TEXT = p_reference_id OR invoice_number = p_reference_id;
    END IF;

    v_treasury_acct := public.resolve_gl_account(
        CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
        v_company_id
    );

    -- Journal entry: Dr. Expense/Supplier / Cr. Treasury
    v_je_id := public.post_journal_entry(
        CASE v_tx_type WHEN 'supplier_payment' THEN 'purchase_payment' ELSE 'expense_payment' END,
        v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_expense_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_treasury_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
        ),
        p_source_id  -- NEW: forward reference_id as source_id to journal_entries
    );

    -- Link journal entry to treasury transaction
    UPDATE public.treasury_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;

    RETURN v_tx_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.spend_custody(BIGINT, TEXT, NUMERIC, TEXT, INTEGER, UUID, BIGINT, BIGINT, UUID, INTEGER, TEXT, TEXT) TO authenticated, service_role;

-- ============================================================================
-- SECTION 3: rpc_edit_profitability_expense — atomic reversal + new entry
-- ============================================================================

CREATE OR REPLACE FUNCTION public.rpc_edit_profitability_expense(
  p_cost_item_id       BIGINT,
  p_new_description    TEXT,
  p_new_quantity       NUMERIC,
  p_new_unit_price     NUMERIC,
  p_new_source_type    TEXT,        -- 'treasury' | 'bank'
  p_new_source_id      BIGINT       -- treasury_id or bank_account_id
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r_item            RECORD;
  v_old_amount      NUMERIC;
  v_new_amount      NUMERIC;
  v_currency        TEXT;
  v_company_id      UUID;
  v_supplier_uuid   UUID;
  v_old_supplier_uuid UUID;
  v_desc            TEXT;

  -- Reversal fields
  v_old_je_id       BIGINT;
  v_old_expense_acct BIGINT;
  v_old_treasury_acct BIGINT;
  v_reversal_je_id  BIGINT;
  v_reversal_desc   TEXT;

  -- New payment fields
  v_new_treasury_tx_id BIGINT;
  v_new_bank_tx_id  INTEGER;
  v_new_je_id       BIGINT;
  v_new_tx_desc     TEXT;
  v_new_treasury_acct BIGINT;
  v_new_expense_acct BIGINT;
  v_current_bal     NUMERIC;
  v_new_revision    INTEGER;
  v_bank_res        JSONB;
BEGIN
  -- 1. Load and validate the cost item
  SELECT * INTO r_item
  FROM public.shipment_cost_items
  WHERE id = p_cost_item_id;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'بند التكلفة غير موجود');
  END IF;

  IF r_item.treasury_transaction_id IS NULL AND r_item.bank_transaction_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'لا يمكن تعديل بند لم يُسدّد بعد — استخدم الإضافة بدلاً من ذلك');
  END IF;

  v_old_amount := COALESCE(r_item.total_price, 0);
  v_new_amount := COALESCE(p_new_quantity, 1) * COALESCE(p_new_unit_price, 0);
  v_currency   := COALESCE(NULLIF(r_item.original_currency, ''), 'EGP');
  v_new_revision := COALESCE(r_item.revision_number, 0) + 1;

  IF v_new_amount <= 0 THEN
    RETURN json_build_object('success', false, 'error', 'المبلغ الجديد يجب أن يكون أكبر من صفر');
  END IF;

  -- Resolve supplier uuid
  v_old_supplier_uuid := NULL;
  IF r_item.supplier_id IS NOT NULL AND r_item.supplier_id != '' THEN
    BEGIN v_old_supplier_uuid := r_item.supplier_id::uuid; EXCEPTION WHEN OTHERS THEN v_old_supplier_uuid := NULL; END;
  END IF;

  v_supplier_uuid := v_old_supplier_uuid;

  -- 2. Resolve company_id from the new source
  IF p_new_source_type = 'treasury' THEN
    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_new_source_id;
  ELSE
    SELECT ba.company_id INTO v_company_id FROM bank_accounts ba WHERE ba.id = p_new_source_id::integer;
  END IF;

  IF v_company_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'لم يتم العثور على الشركة');
  END IF;

  -- 3. REVERSAL of old payment (if item was paid)
  IF r_item.journal_entry_id IS NOT NULL THEN
    v_old_je_id := r_item.journal_entry_id;

    -- Find the expense account and treasury account from old journal entry lines
    SELECT ale.account_id INTO v_old_expense_acct
    FROM public.account_ledger_entries ale
    WHERE ale.journal_entry_id = v_old_je_id AND ale.debit > 0
    ORDER BY ale.id LIMIT 1;

    v_old_treasury_acct := public.resolve_gl_account(
      CASE v_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
      v_company_id
    );

    IF v_old_expense_acct IS NULL THEN
      v_old_expense_acct := public.resolve_gl_account('51101', v_company_id);
    END IF;

    v_reversal_desc := 'عكس سداد بند تكلفة: ' || COALESCE(r_item.description, '') || ' (بند ' || p_cost_item_id::text || ')';

    -- Create reversal journal entry: Dr. Treasury / Cr. Expense (opposite of original)
    v_reversal_je_id := public.post_journal_entry(
      'expense_reversal',
      v_reversal_desc, CURRENT_DATE, v_company_id, auth.uid(),
      jsonb_build_array(
        jsonb_build_object('account_id', v_old_treasury_acct, 'debit', v_old_amount, 'credit', 0, 'currency', v_currency, 'description', v_reversal_desc),
        jsonb_build_object('account_id', v_old_expense_acct, 'debit', 0, 'credit', v_old_amount, 'currency', v_currency, 'description', v_reversal_desc)
      ),
      p_cost_item_id::TEXT
    );

    -- Restore treasury/bank balance
    IF r_item.treasury_transaction_id IS NOT NULL AND r_item.payment_source_type = 'treasury' THEN
      UPDATE public.treasury_balances
      SET balance = balance + v_old_amount, updated_at = NOW()
      WHERE treasury_id = r_item.payment_source_id AND currency = v_currency;

      -- Create reversal treasury transaction (deposit = reverse of expense)
      INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description,
        balance_before, balance_after,
        journal_entry_id, created_by
      ) VALUES (
        r_item.payment_source_id, 'reversal', v_old_amount, v_currency,
        v_reversal_desc,
        (SELECT balance FROM public.treasury_balances WHERE treasury_id = r_item.payment_source_id AND currency = v_currency) - v_old_amount,
        (SELECT balance FROM public.treasury_balances WHERE treasury_id = r_item.payment_source_id AND currency = v_currency),
        v_reversal_je_id, auth.uid()
      );

    ELSIF r_item.bank_transaction_id IS NOT NULL AND r_item.payment_source_type = 'bank' THEN
      UPDATE public.bank_accounts
      SET balance = balance + v_old_amount, updated_at = NOW()
      WHERE id = r_item.payment_source_id::integer;

      INSERT INTO public.bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, journal_entry_id, source_type, created_at, created_by
      ) VALUES (
        r_item.payment_source_id::integer, 'deposit', v_old_amount,
        (SELECT balance FROM public.bank_accounts WHERE id = r_item.payment_source_id::integer) - v_old_amount,
        (SELECT balance FROM public.bank_accounts WHERE id = r_item.payment_source_id::integer),
        v_reversal_desc, v_reversal_je_id, 'reversal', NOW(), auth.uid()
      );
    END IF;
  END IF;

  -- 4. UPDATE cost item with new values
  UPDATE public.shipment_cost_items
  SET description    = p_new_description,
      quantity       = COALESCE(p_new_quantity, 1),
      revision_number = v_new_revision,
      -- NOTE: total_price is GENERATED ALWAYS, so we update quantity × unit_price
      -- We need to update unit_price such that quantity × unit_price = v_new_amount
      unit_price     = v_new_amount / GREATEST(COALESCE(p_new_quantity, 1), 0.0001)
  WHERE id = p_cost_item_id;

  -- Since total_price is GENERATED, we need a workaround: update via a direct UPDATE
  -- Actually, GENERATED ALWAYS columns cannot be updated directly.
  -- We need to use a trigger or modify the column. For now, update quantity and unit_price.
  -- The total_price will auto-compute as quantity × unit_price.
  -- BUT if quantity changed, total_price = new_quantity × old_unit_price, not new_amount.
  -- So we compute unit_price = v_new_amount / new_quantity.

  v_desc := COALESCE(NULLIF(r_item.description, ''), '');

  -- 5. NEW PAYMENT
  v_new_tx_desc := 'سداد بند تكلفة شحنة: ' || COALESCE(p_new_description, 'غير محدد')
                   || ' (بند ' || p_cost_item_id::text || ', تعديل ' || v_new_revision || ')';

  IF p_new_source_type = 'treasury' THEN
    -- Check balance
    SELECT balance INTO v_current_bal
    FROM public.treasury_balances
    WHERE treasury_id = p_new_source_id AND currency = v_currency
    FOR UPDATE;

    IF v_current_bal IS NULL OR v_current_bal < v_new_amount THEN
      RAISE EXCEPTION 'الرصيد غير كافٍ في الخزينة (المتوفر: %, المطلوب: %)',
        COALESCE(v_current_bal, 0), v_new_amount;
    END IF;

    -- Spend new amount from treasury
    PERFORM public.spend_custody(
      p_new_source_id, v_currency, v_new_amount, v_new_tx_desc,
      NULL, v_supplier_uuid, NULL, NULL, NULL,
      NULL, 'shipment_expense', p_cost_item_id::TEXT
    );

    -- Get treasury transaction id
    SELECT id INTO v_new_treasury_tx_id
    FROM public.treasury_transactions
    WHERE treasury_id = p_new_source_id
      AND type = 'expense' AND amount = v_new_amount AND currency = v_currency
    ORDER BY created_at DESC LIMIT 1;

    -- Get journal entry id from treasury transaction
    SELECT journal_entry_id INTO v_new_je_id
    FROM public.treasury_transactions
    WHERE id = v_new_treasury_tx_id;

    -- If spend_custody didn't link it, find by source
    IF v_new_je_id IS NULL THEN
      SELECT je.id INTO v_new_je_id
      FROM public.journal_entries je
      WHERE je.source_type IN ('expense_payment', 'purchase_payment')
        AND je.source_id = p_cost_item_id::TEXT
      ORDER BY je.id DESC LIMIT 1;
    END IF;

    -- Update cost item with new payment stamps
    UPDATE public.shipment_cost_items
    SET treasury_transaction_id = v_new_treasury_tx_id,
        payment_source_type     = 'treasury',
        payment_source_id       = p_new_source_id,
        journal_entry_id        = v_new_je_id
    WHERE id = p_cost_item_id;

    RETURN json_build_object(
      'success', true,
      'cost_item_id', p_cost_item_id,
      'reversal_je_id', v_reversal_je_id,
      'new_je_id', v_new_je_id,
      'new_tx_id', v_new_treasury_tx_id,
      'revision', v_new_revision,
      'old_amount', v_old_amount,
      'new_amount', v_new_amount
    );

  ELSIF p_new_source_type = 'bank' THEN
    -- Check balance
    SELECT balance INTO v_current_bal
    FROM public.bank_accounts
    WHERE id = p_new_source_id::integer
    FOR UPDATE;

    IF v_current_bal IS NULL OR v_current_bal < v_new_amount THEN
      RAISE EXCEPTION 'الرصيد غير كافٍ في الحساب البنكي (المتوفر: %, المطلوب: %)',
        COALESCE(v_current_bal, 0), v_new_amount;
    END IF;

    -- Withdraw new amount from bank
    v_bank_res := public.withdraw_bank_account(
      p_new_source_id::integer, v_new_amount, v_new_tx_desc,
      CASE WHEN v_supplier_uuid IS NOT NULL THEN 'supplier' ELSE NULL END,
      v_supplier_uuid::text, NULL
    );

    v_new_bank_tx_id := (v_bank_res ->> 'transaction_id')::integer;
    v_new_je_id      := (v_bank_res ->> 'journal_entry_id')::bigint;

    -- Update cost item with new payment stamps
    UPDATE public.shipment_cost_items
    SET bank_transaction_id     = v_new_bank_tx_id,
        payment_source_type     = 'bank',
        payment_source_id       = p_new_source_id,
        journal_entry_id        = v_new_je_id
    WHERE id = p_cost_item_id;

    RETURN json_build_object(
      'success', true,
      'cost_item_id', p_cost_item_id,
      'reversal_je_id', v_reversal_je_id,
      'new_je_id', v_new_je_id,
      'new_tx_id', v_new_bank_tx_id,
      'revision', v_new_revision,
      'old_amount', v_old_amount,
      'new_amount', v_new_amount
    );
  END IF;

  RETURN json_build_object('success', false, 'error', 'خطأ داخلي غير متوقع');
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_edit_profitability_expense(
  BIGINT, TEXT, NUMERIC, NUMERIC, TEXT, BIGINT
) TO authenticated, service_role;

-- ============================================================================
-- SECTION 4: rpc_get_profitability_journal_entries — all entries for shipment
-- ============================================================================

CREATE OR REPLACE FUNCTION public.rpc_get_profitability_journal_entries(
  p_shipment_id INTEGER
)
RETURNS TABLE (
  journal_entry_id BIGINT,
  entry_number     TEXT,
  entry_date       DATE,
  description      TEXT,
  source_type      TEXT,
  source_id        TEXT,
  total_debit      NUMERIC,
  total_credit     NUMERIC,
  currency         TEXT,
  cost_item_id     BIGINT,
  cost_description TEXT,
  revision_number  INTEGER,
  created_at       TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT DISTINCT
    je.id AS journal_entry_id,
    je.entry_number,
    je.entry_date,
    je.description,
    je.source_type,
    je.source_id,
    COALESCE(SUM(ale.debit) OVER (PARTITION BY je.id), 0) AS total_debit,
    COALESCE(SUM(ale.credit) OVER (PARTITION BY je.id), 0) AS total_credit,
    (SELECT ale2.currency FROM public.account_ledger_entries ale2
     WHERE ale2.journal_entry_id = je.id AND ale2.currency IS NOT NULL
     ORDER BY ale2.id LIMIT 1) AS currency,
    sci.id AS cost_item_id,
    sci.description AS cost_description,
    COALESCE(sci.revision_number, 0) AS revision_number,
    je.created_at
  FROM public.journal_entries je
  INNER JOIN public.account_ledger_entries ale ON ale.journal_entry_id = je.id
  LEFT JOIN public.shipment_cost_items sci ON sci.journal_entry_id = je.id
  WHERE sci.shipment_id = p_shipment_id
    AND je.deleted_at IS NULL
    AND ale.deleted_at IS NULL
  ORDER BY je.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_profitability_journal_entries(INTEGER) TO authenticated, service_role;

-- ============================================================================
-- SECTION 5: Backfill — link existing journal entries to cost items
-- ============================================================================

-- For bank-paid items: update journal_entries.source_type and source_id
UPDATE public.journal_entries je
SET source_type = 'shipment_expense',
    source_id = sci.id::TEXT
FROM public.shipment_cost_items sci
WHERE sci.bank_transaction_id IS NOT NULL
  AND sci.journal_entry_id = je.id
  AND (je.source_type IS NULL OR je.source_type NOT IN ('expense_payment', 'purchase_payment', 'shipment_expense'));

-- For treasury-paid items: update journal_entries.source_type and source_id
UPDATE public.journal_entries je
SET source_type = 'shipment_expense',
    source_id = sci.id::TEXT
FROM public.shipment_cost_items sci
WHERE sci.treasury_transaction_id IS NOT NULL
  AND sci.journal_entry_id = je.id
  AND (je.source_type IS NULL OR je.source_type NOT IN ('expense_payment', 'purchase_payment', 'shipment_expense'));

NOTIFY pgrst, 'reload schema';
