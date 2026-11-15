-- ============================================================================
-- Migration: Add entity tracking to account_ledger_entries and fix Customer Statement
-- ============================================================================

-- 1. Add entity_type and entity_id to account_ledger_entries if they do not exist
ALTER TABLE public.account_ledger_entries 
ADD COLUMN IF NOT EXISTS entity_type text,
ADD COLUMN IF NOT EXISTS entity_id text;

-- Create index for fast statement queries by customer / supplier
CREATE INDEX IF NOT EXISTS idx_account_ledger_entries_entity 
ON public.account_ledger_entries (entity_type, entity_id);

-- 2. Trigger Function: Automatically resolve entity_type and entity_id for any line
CREATE OR REPLACE FUNCTION public.fn_auto_set_ledger_entry_entity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_cust_id text;
    v_supp_id text;
    v_source_id text;
    v_source_type text;
BEGIN
    -- If entity_id is already provided, keep it
    IF NEW.entity_id IS NOT NULL AND NEW.entity_id <> '' THEN
        IF NEW.entity_type IS NULL OR NEW.entity_type = '' THEN
            NEW.entity_type := 'customer';
        END IF;
        RETURN NEW;
    END IF;

    -- 1. Check if account_id belongs to a customer
    SELECT id INTO v_cust_id
    FROM public.customers
    WHERE account_id = NEW.account_id
    LIMIT 1;

    IF v_cust_id IS NOT NULL THEN
        NEW.entity_type := 'customer';
        NEW.entity_id := v_cust_id::text;
        RETURN NEW;
    END IF;

    -- 2. Check if account_id belongs to a supplier
    SELECT id INTO v_supp_id
    FROM public.suppliers
    WHERE account_id = NEW.account_id
    LIMIT 1;

    IF v_supp_id IS NOT NULL THEN
        NEW.entity_type := 'supplier';
        NEW.entity_id := v_supp_id::text;
        RETURN NEW;
    END IF;

    -- 3. Check parent journal_entries source_id
    SELECT source_id, source_type INTO v_source_id, v_source_type
    FROM public.journal_entries
    WHERE id = NEW.journal_entry_id;

    IF v_source_id IS NOT NULL AND v_source_id <> '' THEN
        IF v_source_id LIKE 'customers_%' THEN
            NEW.entity_type := 'customer';
            NEW.entity_id := REPLACE(v_source_id, 'customers_', '');
            RETURN NEW;
        ELSIF v_source_id LIKE 'suppliers_%' THEN
            NEW.entity_type := 'supplier';
            NEW.entity_id := REPLACE(v_source_id, 'suppliers_', '');
            RETURN NEW;
        ELSIF v_source_type IN ('cash_receipt', 'customer_payment', 'receipt', 'sale_sorting', 'sorting_sale') THEN
            NEW.entity_type := 'customer';
            NEW.entity_id := v_source_id;
            RETURN NEW;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_set_ledger_entry_entity ON public.account_ledger_entries;
CREATE TRIGGER trg_auto_set_ledger_entry_entity
BEFORE INSERT OR UPDATE ON public.account_ledger_entries
FOR EACH ROW
EXECUTE FUNCTION public.fn_auto_set_ledger_entry_entity();

-- 3. Backfill existing account_ledger_entries
UPDATE public.account_ledger_entries ale
SET entity_type = 'customer',
    entity_id = c.id::text
FROM public.customers c
WHERE ale.account_id = c.account_id
  AND (ale.entity_id IS NULL OR ale.entity_id = '');

UPDATE public.account_ledger_entries ale
SET entity_type = 'supplier',
    entity_id = s.id::text
FROM public.suppliers s
WHERE ale.account_id = s.account_id
  AND (ale.entity_id IS NULL OR ale.entity_id = '');

UPDATE public.account_ledger_entries ale
SET entity_type = 'customer',
    entity_id = REPLACE(je.source_id, 'customers_', '')
FROM public.journal_entries je
WHERE ale.journal_entry_id = je.id
  AND je.source_id LIKE 'customers_%'
  AND (ale.entity_id IS NULL OR ale.entity_id = '');

UPDATE public.account_ledger_entries ale
SET entity_type = 'supplier',
    entity_id = REPLACE(je.source_id, 'suppliers_', '')
FROM public.journal_entries je
WHERE ale.journal_entry_id = je.id
  AND je.source_id LIKE 'suppliers_%'
  AND (ale.entity_id IS NULL OR ale.entity_id = '');

-- 4. Update view v_journal_entry_lines
DROP VIEW IF EXISTS public.v_journal_entry_lines CASCADE;

CREATE OR REPLACE VIEW public.v_journal_entry_lines AS
SELECT
    ale.id,
    ale.journal_entry_id,
    je.id AS entry_id,
    je.entry_number,
    je.entry_date AS transaction_date,
    ale.account_id,
    COALESCE(NULLIF(a.account_code, ''), NULLIF(a.code, ''), '') AS account_code,
    COALESCE(NULLIF(a.account_name, ''), NULLIF(a.name, ''), '') AS account_name,
    CASE WHEN ale.debit > 0 THEN 'debit' ELSE 'credit' END AS type,
    (CASE WHEN ale.debit > 0 THEN ale.debit ELSE ale.credit END) AS amount,
    ale.description,
    je.created_by,
    je.created_at,
    je.company_id,
    ale.debit,
    ale.credit,
    ale.currency,
    ale.amount_in_base_currency,
    je.source_type,
    je.source_id,
    je.status,
    ale.cost_center_id,
    ale.entity_type,
    ale.entity_id
FROM public.account_ledger_entries ale
JOIN public.journal_entries je ON je.id = ale.journal_entry_id
LEFT JOIN public.accounts a ON a.id = ale.account_id
WHERE je.deleted_at IS NULL
  AND ale.deleted_at IS NULL;

GRANT SELECT ON public.v_journal_entry_lines TO authenticated, service_role, anon;

-- 5. Create alias view journal_entry_lines pointing to v_journal_entry_lines
CREATE OR REPLACE VIEW public.journal_entry_lines AS
SELECT * FROM public.v_journal_entry_lines;

GRANT SELECT ON public.journal_entry_lines TO authenticated, service_role, anon;

-- 6. RPC: Build and Post Cash Receipt Journal Entry
CREATE OR REPLACE FUNCTION public.rpc_build_cash_receipt_journal(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_date date;
    v_amount numeric;
    v_mode text;
    v_customer_id bigint;
    v_supplier_id bigint;
    v_desc text;
    v_idempotency_key text;
    v_journal_id bigint;
    v_entry_number text;
    v_cash_account_id bigint;
    v_credit_account_id bigint;
BEGIN
    v_date := COALESCE((payload->>'date')::date, CURRENT_DATE);
    v_amount := (payload->>'amount')::numeric;
    v_mode := COALESCE(payload->>'mode', 'customer');
    v_customer_id := (payload->>'customer_id')::bigint;
    v_supplier_id := (payload->>'supplier_id')::bigint;
    v_desc := COALESCE(payload->>'description', 'سند قبض نقدي');
    v_idempotency_key := payload->>'idempotency_key';

    IF v_amount IS NULL OR v_amount <= 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'المبلغ يجب أن يكون أكبر من صفر');
    END IF;

    -- Check idempotency
    IF v_idempotency_key IS NOT NULL THEN
        SELECT id, entry_number INTO v_journal_id, v_entry_number
        FROM public.journal_entries
        WHERE idempotency_key = v_idempotency_key
        LIMIT 1;

        IF FOUND THEN
            RETURN jsonb_build_object('success', true, 'journal_id', v_journal_id, 'journal_number', v_entry_number);
        END IF;
    END IF;

    -- 1. Find Cash/Treasury GL Account (e.g., 12111 or first cash account)
    SELECT id INTO v_cash_account_id
    FROM public.accounts
    WHERE (code = '12111' OR account_code = '12111' OR name LIKE '%صندوق%' OR name LIKE '%خزينة%')
      AND is_active = true
    ORDER BY id ASC LIMIT 1;

    IF v_cash_account_id IS NULL THEN
        SELECT id INTO v_cash_account_id FROM public.accounts WHERE is_active = true LIMIT 1;
    END IF;

    -- 2. Find Credit GL Account based on mode
    IF v_mode = 'customer' AND v_customer_id IS NOT NULL THEN
        SELECT account_id INTO v_credit_account_id FROM public.customers WHERE id = v_customer_id;
    ELSIF v_mode = 'supplier' AND v_supplier_id IS NOT NULL THEN
        SELECT account_id INTO v_credit_account_id FROM public.suppliers WHERE id = v_supplier_id;
    END IF;

    IF v_credit_account_id IS NULL THEN
        -- Fallback to AR / Customers control account (12511)
        SELECT id INTO v_credit_account_id FROM public.accounts WHERE (code = '12511' OR account_code = '12511') LIMIT 1;
    END IF;

    -- Generate sequence entry number
    v_entry_number := 'CR-' || to_char(now(), 'YYYYMMDD') || '-' || lpad((nextval('public.journal_entries_id_seq'::regclass) % 10000)::text, 4, '0');

    -- Insert journal entry
    INSERT INTO public.journal_entries (
        entry_number, entry_date, description, status, source_type, source_id, idempotency_key
    ) VALUES (
        v_entry_number, v_date, v_desc, 'posted', 'cash_receipt', 
        CASE WHEN v_customer_id IS NOT NULL THEN 'customers_' || v_customer_id::text ELSE NULL END,
        v_idempotency_key
    ) RETURNING id INTO v_journal_id;

    -- Debit line: Cash in hand
    INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description
    ) VALUES (
        v_journal_id, v_cash_account_id, v_amount, 0, 'EGP', v_amount, v_desc
    );

    -- Credit line: Customer / Entity (With explicit entity_type and entity_id)
    INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description,
        entity_type, entity_id
    ) VALUES (
        v_journal_id, v_credit_account_id, 0, v_amount, 'EGP', v_amount, v_desc,
        CASE WHEN v_customer_id IS NOT NULL THEN 'customer' WHEN v_supplier_id IS NOT NULL THEN 'supplier' ELSE NULL END,
        CASE WHEN v_customer_id IS NOT NULL THEN v_customer_id::text WHEN v_supplier_id IS NOT NULL THEN v_supplier_id::text ELSE NULL END
    );

    RETURN jsonb_build_object(
        'success', true,
        'journal_id', v_journal_id,
        'journal_number', v_entry_number
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_build_cash_receipt_journal(jsonb) TO authenticated, service_role, anon;

-- 7. RPC: Build and Post Cash Payment Journal Entry
CREATE OR REPLACE FUNCTION public.rpc_build_cash_payment_journal(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_date date;
    v_amount numeric;
    v_mode text;
    v_customer_id bigint;
    v_supplier_id bigint;
    v_desc text;
    v_idempotency_key text;
    v_journal_id bigint;
    v_entry_number text;
    v_cash_account_id bigint;
    v_debit_account_id bigint;
BEGIN
    v_date := COALESCE((payload->>'date')::date, CURRENT_DATE);
    v_amount := (payload->>'amount')::numeric;
    v_mode := COALESCE(payload->>'mode', 'supplier');
    v_customer_id := (payload->>'customer_id')::bigint;
    v_supplier_id := (payload->>'supplier_id')::bigint;
    v_desc := COALESCE(payload->>'description', 'سند صرف نقدي');
    v_idempotency_key := payload->>'idempotency_key';

    IF v_amount IS NULL OR v_amount <= 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'المبلغ يجب أن يكون أكبر من صفر');
    END IF;

    -- Check idempotency
    IF v_idempotency_key IS NOT NULL THEN
        SELECT id, entry_number INTO v_journal_id, v_entry_number
        FROM public.journal_entries
        WHERE idempotency_key = v_idempotency_key
        LIMIT 1;

        IF FOUND THEN
            RETURN jsonb_build_object('success', true, 'journal_id', v_journal_id, 'journal_number', v_entry_number);
        END IF;
    END IF;

    -- 1. Find Cash/Treasury GL Account
    SELECT id INTO v_cash_account_id
    FROM public.accounts
    WHERE (code = '12111' OR account_code = '12111' OR name LIKE '%صندوق%' OR name LIKE '%خزينة%')
      AND is_active = true
    ORDER BY id ASC LIMIT 1;

    IF v_cash_account_id IS NULL THEN
        SELECT id INTO v_cash_account_id FROM public.accounts WHERE is_active = true LIMIT 1;
    END IF;

    -- 2. Find Debit GL Account based on mode
    IF v_mode = 'customer' AND v_customer_id IS NOT NULL THEN
        SELECT account_id INTO v_debit_account_id FROM public.customers WHERE id = v_customer_id;
    ELSIF v_mode = 'supplier' AND v_supplier_id IS NOT NULL THEN
        SELECT account_id INTO v_debit_account_id FROM public.suppliers WHERE id = v_supplier_id;
    END IF;

    IF v_debit_account_id IS NULL THEN
        -- Fallback to Accounts Payable (21111) or Accounts Receivable (12511)
        IF v_mode = 'customer' THEN
            SELECT id INTO v_debit_account_id FROM public.accounts WHERE (code = '12511' OR account_code = '12511') LIMIT 1;
        ELSE
            SELECT id INTO v_debit_account_id FROM public.accounts WHERE (code = '21111' OR account_code = '21111') LIMIT 1;
        END IF;
    END IF;

    -- Generate sequence entry number
    v_entry_number := 'CP-' || to_char(now(), 'YYYYMMDD') || '-' || lpad((nextval('public.journal_entries_id_seq'::regclass) % 10000)::text, 4, '0');

    -- Insert journal entry
    INSERT INTO public.journal_entries (
        entry_number, entry_date, description, status, source_type, source_id, idempotency_key
    ) VALUES (
        v_entry_number, v_date, v_desc, 'posted', 'cash_payment',
        CASE WHEN v_customer_id IS NOT NULL THEN 'customers_' || v_customer_id::text WHEN v_supplier_id IS NOT NULL THEN 'suppliers_' || v_supplier_id::text ELSE NULL END,
        v_idempotency_key
    ) RETURNING id INTO v_journal_id;

    -- Debit line: Customer / Supplier / Expense (With explicit entity_type and entity_id)
    INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description,
        entity_type, entity_id
    ) VALUES (
        v_journal_id, v_debit_account_id, v_amount, 0, 'EGP', v_amount, v_desc,
        CASE WHEN v_customer_id IS NOT NULL THEN 'customer' WHEN v_supplier_id IS NOT NULL THEN 'supplier' ELSE NULL END,
        CASE WHEN v_customer_id IS NOT NULL THEN v_customer_id::text WHEN v_supplier_id IS NOT NULL THEN v_supplier_id::text ELSE NULL END
    );

    -- Credit line: Cash in hand
    INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description
    ) VALUES (
        v_journal_id, v_cash_account_id, 0, v_amount, 'EGP', v_amount, v_desc
    );

    RETURN jsonb_build_object(
        'success', true,
        'journal_id', v_journal_id,
        'journal_number', v_entry_number
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_build_cash_payment_journal(jsonb) TO authenticated, service_role, anon;
