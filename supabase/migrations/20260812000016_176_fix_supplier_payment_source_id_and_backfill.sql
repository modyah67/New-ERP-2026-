-- ============================================================================
-- 176: Fix treasury transactions journal_entry_id links and pass source_id properly.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.record_supplier_payment(
    p_supplier_id   UUID,
    p_amount        NUMERIC,
    p_currency      TEXT DEFAULT 'EGP',
    p_description   TEXT DEFAULT '',
    p_treasury_id   INTEGER DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_ledger_id     BIGINT;
    v_tx_id         INTEGER;
    v_company_id    UUID;
    v_treasury_acct BIGINT;
    v_ap_acct       BIGINT;
    v_je_id         BIGINT;
    v_desc          TEXT;
BEGIN
    IF NOT public._is_admin() THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    v_desc := COALESCE(NULLIF(p_description, ''), 'دفع مورد');

    UPDATE suppliers SET outstanding_balance = outstanding_balance - p_amount WHERE id = p_supplier_id;

    INSERT INTO ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by)
    VALUES ('supplier', p_supplier_id::TEXT, 'debit', p_amount, p_currency, 'payment', v_desc, auth.uid())
    RETURNING id INTO v_ledger_id;

    IF p_treasury_id IS NOT NULL THEN
        -- Resolve company from treasury
        SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;

        -- Treasury balance check + update
        DECLARE
            v_bal NUMERIC;
        BEGIN
            SELECT balance INTO v_bal
            FROM treasury_balances
            WHERE treasury_id = p_treasury_id AND currency = p_currency
            FOR UPDATE;

            IF v_bal IS NULL OR v_bal < p_amount THEN
                RAISE EXCEPTION 'الرصيد غير كافٍ في الخزنة (المتوفر: %)', COALESCE(v_bal, 0);
            END IF;

            UPDATE treasury_balances
            SET balance = balance - p_amount
            WHERE treasury_id = p_treasury_id AND currency = p_currency;
        END;

        INSERT INTO treasury_transactions (treasury_id, type, currency, amount, description, supplier_id, created_by)
        VALUES (p_treasury_id, 'supplier_payment', p_currency, p_amount, v_desc, p_supplier_id, auth.uid())
        RETURNING id INTO v_tx_id;

        -- GL: Dr.AP / Cr.Treasury
        v_treasury_acct := public.resolve_gl_account(
            CASE p_currency WHEN 'EGP' THEN '11101' WHEN 'USD' THEN '11102' WHEN 'EUR' THEN '11103' WHEN 'GBP' THEN '11104' END,
            v_company_id
        );
        v_ap_acct := public.resolve_gl_account('2000', v_company_id);

        v_je_id := public.post_journal_entry(
            'supplier_payment', v_desc, CURRENT_DATE, v_company_id, auth.uid(),
            jsonb_build_array(
                jsonb_build_object('account_id', v_ap_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
                jsonb_build_object('account_id', v_treasury_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
            ),
            v_tx_id::TEXT
        );

        -- Write journal_entry_id back to treasury_transactions
        IF v_je_id IS NOT NULL AND v_tx_id IS NOT NULL THEN
            UPDATE treasury_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;
        END IF;
    END IF;

    RETURN jsonb_build_object('ledger_entry_id', v_ledger_id, 'treasury_tx_id', v_tx_id, 'journal_entry_id', v_je_id);
END;
$$;


-- Backfill journal entries where the amounts match exactly for the same day and user
UPDATE treasury_transactions tt
SET journal_entry_id = sub.id
FROM (
    SELECT je.id, je.description, je.created_at, je.created_by, ale.credit, ale.currency
    FROM journal_entries je
    JOIN account_ledger_entries ale ON ale.journal_entry_id = je.id
    WHERE je.source_type = 'supplier_payment'
      AND ale.credit > 0
) sub
WHERE tt.type = 'supplier_payment'
  AND tt.journal_entry_id IS NULL
  AND tt.amount = sub.credit
  AND tt.currency = sub.currency
  AND tt.created_by = sub.created_by
  AND tt.created_at::DATE = sub.created_at::DATE
  AND (tt.description = sub.description OR sub.description = 'دفع مورد');

-- Fix any source_id references to point to the correct tx_id
UPDATE journal_entries je
SET source_id = tt.id::TEXT
FROM treasury_transactions tt
WHERE je.source_type = 'supplier_payment'
  AND tt.journal_entry_id = je.id
  AND je.source_id IS DISTINCT FROM tt.id::TEXT;
