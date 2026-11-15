-- ==============================================================================
-- Migration: Complete Supplier Advances, Cash Receipts & Balance Sync Deployment
-- ==============================================================================

-- 1. Function: sync_supplier_balances
CREATE OR REPLACE FUNCTION public.sync_supplier_balances(p_supplier_id uuid DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_cur_balances jsonb := '{}'::jsonb;
  v_total_egp numeric := 0;
  r RECORD;
  c RECORD;
  sup_rec RECORD;
BEGIN
  IF p_supplier_id IS NULL THEN
    FOR sup_rec IN SELECT id FROM public.suppliers LOOP
      PERFORM public.sync_supplier_balances(sup_rec.id);
    END LOOP;
    RETURN;
  END IF;

  -- Pre-populate supported currencies (TEXT[]) and currencies with initial balances with 0.0
  FOR c IN
    SELECT DISTINCT cur
    FROM public.suppliers s,
    LATERAL (
      SELECT unnest(COALESCE(s.supported_currencies, ARRAY[]::text[])) AS cur
      UNION
      SELECT jsonb_object_keys(s.initial_balances_by_currency) AS cur
      WHERE s.initial_balances_by_currency IS NOT NULL 
        AND jsonb_typeof(s.initial_balances_by_currency) = 'object'
    ) sub
    WHERE s.id = p_supplier_id 
      AND s.is_multi_currency = true 
      AND cur IS NOT NULL 
      AND cur <> ''
  LOOP
    v_cur_balances := v_cur_balances || jsonb_build_object(UPPER(c.cur), 0.0);
  END LOOP;

  IF to_regproc('public.get_supplier_true_balances_by_currency') IS NOT NULL THEN
    FOR r IN 
      SELECT currency, true_balance, true_balance_egp
      FROM public.get_supplier_true_balances_by_currency()
      WHERE supplier_id = p_supplier_id
    LOOP
      v_cur_balances := v_cur_balances || jsonb_build_object(UPPER(r.currency), r.true_balance);
      v_total_egp := v_total_egp + COALESCE(r.true_balance_egp, 0);
    END LOOP;

    UPDATE public.suppliers
    SET 
      current_balances_by_currency = v_cur_balances,
      outstanding_balance = v_total_egp,
      updated_at = NOW()
    WHERE id = p_supplier_id;
  ELSIF to_regproc('public.get_supplier_true_balances') IS NOT NULL THEN
    UPDATE public.suppliers
    SET outstanding_balance = COALESCE((SELECT true_balance FROM public.get_supplier_true_balances() WHERE supplier_id = p_supplier_id), 0),
        updated_at = NOW()
    WHERE id = p_supplier_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.sync_supplier_balances(uuid) TO authenticated, anon, service_role;

-- 2. Function: receive_payment (Advance deposits & Cash receipts from suppliers)
CREATE OR REPLACE FUNCTION public.receive_payment(
    p_receipt_type character varying,
    p_amount numeric,
    p_currency character varying,
    p_counterparty_type character varying DEFAULT NULL::character varying,
    p_counterparty_id bigint DEFAULT NULL::bigint,
    p_supplier_id uuid DEFAULT NULL::uuid,
    p_shareholder_id uuid DEFAULT NULL::uuid,
    p_description text DEFAULT NULL::text,
    p_notes text DEFAULT NULL::text,
    p_treasury_id bigint DEFAULT NULL::bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_treasury_id       BIGINT;
    v_current_balance   NUMERIC := 0;
    v_current_cost_base NUMERIC := 0;
    v_current_book_rate NUMERIC := 1.0;
    v_new_balance       NUMERIC := 0;
    v_new_cost_base     NUMERIC := 0;
    v_new_book_rate     NUMERIC := 1.0;
    v_tx_id             BIGINT;
    v_company_id        UUID;
    v_treasury_acct     BIGINT;
    v_ar_acct           BIGINT;
    v_je_id             BIGINT;
    v_desc              TEXT;
    v_counterparty_name TEXT;
    v_source_type       TEXT;
    v_treasury_name     TEXT;
    v_je_source         TEXT;
    v_credit_acct       BIGINT;
    v_rate              NUMERIC := 1.0;
    v_base_amount       NUMERIC;
    v_snapshot          JSONB;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    IF p_treasury_id IS NOT NULL THEN
        v_treasury_id := p_treasury_id;
    ELSE
        SELECT id INTO v_treasury_id
        FROM public.treasuries
        WHERE type = 'main' AND user_id = auth.uid()
        LIMIT 1;
        IF v_treasury_id IS NULL THEN
            SELECT id INTO v_treasury_id FROM public.treasuries WHERE type = 'main' LIMIT 1;
        END IF;
        IF v_treasury_id IS NULL THEN
            RAISE EXCEPTION 'لم يتم العثور على الخزينة الرئيسية.';
        END IF;
    END IF;

    SELECT t.company_id INTO v_company_id FROM public.treasuries t WHERE t.id = v_treasury_id;

    -- 1. Lock treasury balance row & retrieve current cost_base and book_rate
    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_current_balance, v_current_cost_base, v_current_book_rate
    FROM public.treasury_balances
    WHERE treasury_id::TEXT = v_treasury_id::TEXT AND currency = p_currency
    FOR UPDATE;

    -- 2. Calculate spot exchange rate & base amount
    IF p_currency = 'EGP' THEN
        v_rate := 1.0;
        v_base_amount := p_amount;
        v_new_cost_base := COALESCE(v_current_cost_base, 0) + p_amount;
        v_new_book_rate := 1.0;
    ELSE
        v_rate := public.fn_get_exchange_rate(p_currency);
        v_base_amount := ROUND(p_amount * v_rate, 2);
        v_new_cost_base := COALESCE(v_current_cost_base, 0) + v_base_amount;
    END IF;

    v_new_balance := COALESCE(v_current_balance, 0) + p_amount;

    IF v_new_balance > 0 AND p_currency != 'EGP' THEN
        v_new_book_rate := ROUND(v_new_cost_base / v_new_balance, 4);
    ELSIF p_currency = 'EGP' THEN
        v_new_book_rate := 1.0;
    ELSE
        v_new_book_rate := v_rate;
    END IF;

    IF p_counterparty_type IS NULL OR p_counterparty_type = 'opening' THEN
        v_source_type := 'opening_balance';
        SELECT name INTO v_treasury_name FROM public.treasuries WHERE id = v_treasury_id;
        v_desc := COALESCE(
            NULLIF(p_description, ''),
            'الرصيد الافتتاحي لل' || COALESCE(v_treasury_name, 'الخزينة الرئيسية')
        );
    ELSE
        v_source_type := p_counterparty_type;
        v_desc := COALESCE(NULLIF(p_description, ''), 'استلام ' || p_receipt_type);
    END IF;

    v_treasury_acct := public.resolve_treasury_account(v_treasury_id, p_currency, v_company_id);

    IF p_counterparty_type = 'customer' THEN
        SELECT c.account_id, c.name INTO v_credit_acct, v_counterparty_name FROM public.customers c WHERE c.id = p_counterparty_id;
        IF v_counterparty_name IS NOT NULL AND v_counterparty_name != '' THEN
            IF p_description IS NOT NULL AND p_description != '' AND p_description NOT LIKE '%' || v_counterparty_name || '%' THEN
                v_desc := p_description || ' - العميل: ' || v_counterparty_name || ' (سداد حساب العميل)';
            ELSIF p_description IS NULL OR p_description = '' OR p_description = 'استلام ' || p_receipt_type THEN
                v_desc := 'استلام نقدية من العميل ' || v_counterparty_name || ' (سداد حساب العميل)';
            END IF;
        END IF;
        IF v_credit_acct IS NOT NULL THEN
            SELECT id INTO v_credit_acct FROM public.accounts WHERE id = v_credit_acct AND is_leaf = true AND is_active = true;
        END IF;
        IF v_credit_acct IS NULL THEN
            v_credit_acct := public.resolve_gl_account('12511', v_company_id);
        END IF;
    ELSIF p_counterparty_type = 'supplier' THEN
        SELECT s.account_id, s.name INTO v_credit_acct, v_counterparty_name FROM public.suppliers s WHERE s.id = p_supplier_id;
        IF v_counterparty_name IS NOT NULL AND v_counterparty_name != '' THEN
            IF p_description IS NOT NULL AND p_description != '' AND p_description NOT LIKE '%' || v_counterparty_name || '%' THEN
                v_desc := p_description || ' - المورد: ' || v_counterparty_name || ' (إيداع نقدي / دفعة مقدمة)';
            ELSIF p_description IS NULL OR p_description = '' OR p_description = 'استلام ' || p_receipt_type OR p_description LIKE 'استلام % من ' || v_counterparty_name THEN
                v_desc := 'إيداع نقدي / دفعة مقدمة من المورد ' || v_counterparty_name;
            END IF;
        END IF;
        IF v_credit_acct IS NOT NULL THEN
            SELECT id INTO v_credit_acct FROM public.accounts WHERE id = v_credit_acct AND is_leaf = true AND is_active = true;
        END IF;
        IF v_credit_acct IS NULL THEN
            v_credit_acct := public.resolve_gl_account('21113', v_company_id);
        END IF;
        IF v_credit_acct IS NULL THEN
            v_credit_acct := public.resolve_gl_account('2000', v_company_id);
        END IF;
    ELSIF p_counterparty_type = 'clearing_agent' THEN
        SELECT ca.account_id INTO v_credit_acct FROM public.clearing_agents ca WHERE ca.id = p_counterparty_id;
        IF v_credit_acct IS NOT NULL THEN
            SELECT id INTO v_credit_acct FROM public.accounts WHERE id = v_credit_acct AND is_leaf = true AND is_active = true;
        END IF;
        IF v_credit_acct IS NULL THEN
            v_credit_acct := public.resolve_gl_account('2000', v_company_id);
        END IF;
    ELSIF p_counterparty_type = 'shipping_company' THEN
        SELECT sc.account_id INTO v_credit_acct FROM public.shipping_companies sc WHERE sc.id = p_counterparty_id;
        IF v_credit_acct IS NOT NULL THEN
            SELECT id INTO v_credit_acct FROM public.accounts WHERE id = v_credit_acct AND is_leaf = true AND is_active = true;
        END IF;
        IF v_credit_acct IS NULL THEN
            v_credit_acct := public.resolve_gl_account('2000', v_company_id);
        END IF;
    ELSIF p_counterparty_type = 'shareholder' THEN
        SELECT account_id INTO v_credit_acct FROM public.shareholders WHERE id = p_shareholder_id;
        IF v_credit_acct IS NOT NULL THEN
            SELECT id INTO v_credit_acct FROM public.accounts WHERE id = v_credit_acct AND is_leaf = true AND is_active = true;
        END IF;
        IF v_credit_acct IS NULL THEN
            v_credit_acct := public.resolve_equity_account(p_currency, v_company_id);
        END IF;
    ELSE
        v_credit_acct := public.resolve_opening_balance_equity_account(p_currency, v_company_id);
    END IF;

    v_snapshot := jsonb_build_object(
        'currency', p_currency,
        'exchange_rate', v_rate,
        'book_rate', v_new_book_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'rate_date', CURRENT_DATE,
        'rate_source', 'exchange_rates_table'
    );

    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description, source_type,
        customer_id, supplier_id, clearing_agent_id, shipping_company_id, shareholder_id,
        balance_before, balance_after,
        created_by, revenue_account_id, notes,
        exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        v_treasury_id, 'deposit', p_amount, p_currency, v_desc, v_source_type,
        CASE WHEN p_counterparty_type = 'customer' THEN p_counterparty_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'supplier' THEN p_supplier_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'clearing_agent' THEN p_counterparty_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'shipping_company' THEN p_counterparty_id ELSE NULL END,
        CASE WHEN p_counterparty_type = 'shareholder' THEN p_shareholder_id ELSE NULL END,
        v_current_balance, v_new_balance,
        auth.uid(),
        v_credit_acct, p_notes,
        v_rate, v_base_amount, v_snapshot
    ) RETURNING id INTO v_tx_id;

    IF p_counterparty_type = 'customer' AND p_counterparty_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance - p_amount WHERE id = p_counterparty_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('customer', p_counterparty_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_ar_acct := v_credit_acct;
        v_je_id := public.post_journal_entry(
            'customer_payment', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSIF p_counterparty_type = 'supplier' AND p_supplier_id IS NOT NULL THEN
        -- Cash received from supplier is an advance payment / deposit by the supplier
        -- It reduces outstanding payable (or creates a negative/debit advance balance)
        UPDATE public.suppliers 
        SET outstanding_balance = outstanding_balance - p_amount 
        WHERE id = p_supplier_id;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('supplier', p_supplier_id::TEXT, 'debit', p_amount, p_currency, 'supplier_deposit', v_tx_id, v_desc, auth.uid());

        v_ar_acct := v_credit_acct;
        v_je_id := public.post_journal_entry(
            'supplier_advance_deposit', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

        -- Synchronize multi-currency balance maps
        IF to_regproc('public.sync_supplier_balances') IS NOT NULL THEN
            PERFORM public.sync_supplier_balances(p_supplier_id);
        END IF;

    ELSIF p_counterparty_type = 'clearing_agent' AND p_counterparty_id IS NOT NULL THEN
        UPDATE public.clearing_agents
        SET manual_adjustment = COALESCE(manual_adjustment, 0) + p_amount,
            balance = COALESCE(balance, 0) + p_amount
        WHERE id = p_counterparty_id;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('clearing_agent', p_counterparty_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_ar_acct := v_credit_acct;
        v_je_id := public.post_journal_entry(
            'clearing_agent_payment_received', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSIF p_counterparty_type = 'shipping_company' AND p_counterparty_id IS NOT NULL THEN
        UPDATE public.shipping_companies
        SET manual_adjustment = COALESCE(manual_adjustment, 0) + p_amount,
            balance = COALESCE(balance, 0) + p_amount
        WHERE id = p_counterparty_id;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('shipping_company', p_counterparty_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_ar_acct := v_credit_acct;
        v_je_id := public.post_journal_entry(
            'shipping_company_payment_received', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
            )
        );

    ELSIF p_counterparty_type = 'shareholder' AND p_shareholder_id IS NOT NULL THEN
        IF p_currency = 'EGP' THEN
            UPDATE public.shareholders SET current_balance_egp = current_balance_egp + p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'USD' THEN
            UPDATE public.shareholders SET current_balance_usd = current_balance_usd + p_amount WHERE id = p_shareholder_id;
        END IF;

        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('shareholder', p_shareholder_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, v_desc, auth.uid());

        v_ar_acct := v_credit_acct;
        v_je_id := public.post_journal_entry(
            'shareholder_deposit', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
            )
        );
    ELSE
        -- Opening balance / other
        v_ar_acct := v_credit_acct;
        v_je_id := public.post_journal_entry(
            'opening_balance', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_ar_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
            )
        );
    END IF;

    -- Update treasury_transactions with journal entry ID
    IF v_je_id IS NOT NULL THEN
        UPDATE public.treasury_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'transaction_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'new_balance', v_new_balance
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.receive_payment(character varying, numeric, character varying, character varying, bigint, uuid, uuid, text, text, bigint) TO authenticated, anon, service_role;

-- 3. Resync all suppliers now
DO $$
DECLARE
  sup_rec RECORD;
BEGIN
  FOR sup_rec IN SELECT id FROM public.suppliers LOOP
    PERFORM public.sync_supplier_balances(sup_rec.id);
  END LOOP;
END;
$$;

-- 4. Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
