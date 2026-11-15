-- ============================================================================
-- Migration: Transport Supplier RPC Functions
-- Creates rpc_add_transport_invoice and rpc_pay_transport_supplier
-- ============================================================================
BEGIN;

-- ============================================================================
-- 1. rpc_add_transport_invoice
--    Records a transport invoice (فاتورة نقل) against a transport supplier.
--    - Inserts a transport_transaction of type 'invoice'
--    - Creates a GL journal entry (debit expense, credit supplier)
--    - Updates supplier balance and truck_balance
-- ============================================================================
DROP FUNCTION IF EXISTS public.rpc_add_transport_invoice(
    integer, numeric, integer, integer, text, text, date, text, integer, text, text
);

CREATE OR REPLACE FUNCTION public.rpc_add_transport_invoice(
    p_supplier_id      integer,
    p_amount           numeric,
    p_number_of_trucks integer DEFAULT 1,
    p_truck_count      integer DEFAULT 1,
    p_route_from       text    DEFAULT NULL,
    p_route_to         text    DEFAULT NULL,
    p_date             date    DEFAULT NULL,
    p_description      text    DEFAULT NULL,
    p_expense_account_id integer DEFAULT NULL,
    p_reference_number text    DEFAULT NULL,
    p_notes            text    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_date             date;
    v_truck_count      integer;
    v_desc             text;
    v_supplier         RECORD;
    v_journal_id       bigint;
    v_entry_number     text;
    v_transaction_id   integer;
    v_expense_acct_id  bigint;
    v_supplier_acct_id bigint;
BEGIN
    -- Resolve date
    v_date := COALESCE(p_date, (NOW() AT TIME ZONE 'Africa/Cairo')::date);

    -- Use whichever truck count is provided (prefer p_truck_count over p_number_of_trucks)
    v_truck_count := COALESCE(NULLIF(p_truck_count, 0), NULLIF(p_number_of_trucks, 0), 1);

    -- Validate amount
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'المبلغ يجب أن يكون أكبر من صفر');
    END IF;

    -- Validate supplier exists
    SELECT id, name, account_id, balance, truck_balance
    INTO v_supplier
    FROM public.transport_suppliers
    WHERE id = p_supplier_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'مورد النقل غير موجود');
    END IF;

    -- Build description
    v_desc := COALESCE(p_description, 'فاتورة نقل - ' || v_supplier.name);
    IF p_route_from IS NOT NULL AND p_route_to IS NOT NULL THEN
        v_desc := v_desc || ' (' || p_route_from || ' → ' || p_route_to || ')';
    END IF;

    -- Resolve expense account (debit side)
    v_expense_acct_id := p_expense_account_id;
    IF v_expense_acct_id IS NULL THEN
        -- Default: look for transport expense account
        SELECT id INTO v_expense_acct_id
        FROM public.accounts
        WHERE (code = '51311' OR account_code = '51311'
               OR name ILIKE '%مصاريف نقل%' OR name ILIKE '%نقل%')
          AND is_active = true
        ORDER BY
            CASE WHEN code = '51311' OR account_code = '51311' THEN 0 ELSE 1 END
        LIMIT 1;
    END IF;

    -- Resolve supplier account (credit side)
    v_supplier_acct_id := v_supplier.account_id;
    IF v_supplier_acct_id IS NULL THEN
        -- Fallback: generic transport suppliers payable
        SELECT id INTO v_supplier_acct_id
        FROM public.accounts
        WHERE (code = '21311' OR account_code = '21311'
               OR name ILIKE '%موردي نقل%' OR name ILIKE '%دائنو نقل%')
          AND is_active = true
        ORDER BY id ASC
        LIMIT 1;
    END IF;

    -- Create GL journal entry if both accounts exist
    IF v_expense_acct_id IS NOT NULL AND v_supplier_acct_id IS NOT NULL THEN
        v_entry_number := 'TI-' || to_char(v_date, 'YYYYMMDD') || '-' ||
                          lpad((nextval('public.journal_entries_id_seq'::regclass) % 10000)::text, 4, '0');

        INSERT INTO public.journal_entries (
            entry_number, entry_date, description, status, source_type, source_id
        ) VALUES (
            v_entry_number, v_date, v_desc, 'posted',
            'transport_invoice', 'transport_suppliers_' || p_supplier_id::text
        ) RETURNING id INTO v_journal_id;

        -- Debit: expense account
        INSERT INTO public.account_ledger_entries (
            journal_entry_id, account_id, debit, credit,
            currency, amount_in_base_currency, description,
            entity_type, entity_id
        ) VALUES (
            v_journal_id, v_expense_acct_id, p_amount, 0,
            'EGP', p_amount, v_desc,
            'transport_supplier', p_supplier_id::text
        );

        -- Credit: supplier account
        INSERT INTO public.account_ledger_entries (
            journal_entry_id, account_id, debit, credit,
            currency, amount_in_base_currency, description,
            entity_type, entity_id
        ) VALUES (
            v_journal_id, v_supplier_acct_id, 0, p_amount,
            'EGP', p_amount, v_desc,
            'transport_supplier', p_supplier_id::text
        );
    END IF;

    -- Insert transport transaction
    INSERT INTO public.transport_transactions (
        supplier_id, type, amount, truck_count, description,
        notes, journal_entry_id, date, reference_id, route_from, route_to
    ) VALUES (
        p_supplier_id, 'invoice', p_amount, v_truck_count, v_desc,
        p_notes, v_journal_id, v_date, p_reference_number, p_route_from, p_route_to
    ) RETURNING id INTO v_transaction_id;

    -- Update supplier balance and truck_balance
    UPDATE public.transport_suppliers
    SET balance = COALESCE(balance, 0) + p_amount,
        current_balance = COALESCE(current_balance, 0) + p_amount,
        truck_balance = COALESCE(truck_balance, 0) + v_truck_count,
        updated_at = NOW()
    WHERE id = p_supplier_id;

    RETURN jsonb_build_object(
        'success', true,
        'transaction_id', v_transaction_id,
        'journal_id', v_journal_id,
        'journal_number', v_entry_number,
        'amount', p_amount,
        'truck_count', v_truck_count
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_add_transport_invoice(
    integer, numeric, integer, integer, text, text, date, text, integer, text, text
) TO authenticated, service_role, anon;


-- ============================================================================
-- 2. rpc_pay_transport_supplier
--    Records a payment (سداد) to a transport supplier.
--    - Inserts a transport_transaction of type 'cash_payment' or 'bank_payment'
--    - Creates a GL journal entry (debit supplier, credit cash/bank)
--    - Updates supplier balance
-- ============================================================================
DROP FUNCTION IF EXISTS public.rpc_pay_transport_supplier(
    integer, text, integer, numeric, date, text, text
);

CREATE OR REPLACE FUNCTION public.rpc_pay_transport_supplier(
    p_supplier_id   integer,
    p_source_type   text,       -- 'treasury' or 'bank'
    p_source_id     integer,
    p_amount        numeric,
    p_date          date    DEFAULT NULL,
    p_description   text    DEFAULT NULL,
    p_notes         text    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_date             date;
    v_desc             text;
    v_txn_type         text;
    v_supplier         RECORD;
    v_journal_id       bigint;
    v_entry_number     text;
    v_transaction_id   integer;
    v_supplier_acct_id bigint;
    v_source_acct_id   bigint;
BEGIN
    -- Resolve date
    v_date := COALESCE(p_date, (NOW() AT TIME ZONE 'Africa/Cairo')::date);

    -- Validate amount
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'المبلغ يجب أن يكون أكبر من صفر');
    END IF;

    -- Validate supplier exists
    SELECT id, name, account_id, balance
    INTO v_supplier
    FROM public.transport_suppliers
    WHERE id = p_supplier_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'مورد النقل غير موجود');
    END IF;

    -- Determine transaction type
    IF p_source_type = 'bank' THEN
        v_txn_type := 'bank_payment';
    ELSE
        v_txn_type := 'cash_payment';
    END IF;

    -- Build description
    v_desc := COALESCE(p_description, 'سداد لمورد نقل - ' || v_supplier.name);

    -- Resolve supplier account (debit side - reduce payable)
    v_supplier_acct_id := v_supplier.account_id;
    IF v_supplier_acct_id IS NULL THEN
        SELECT id INTO v_supplier_acct_id
        FROM public.accounts
        WHERE (code = '21311' OR account_code = '21311'
               OR name ILIKE '%موردي نقل%' OR name ILIKE '%دائنو نقل%')
          AND is_active = true
        ORDER BY id ASC
        LIMIT 1;
    END IF;

    -- Resolve source account (credit side - cash or bank)
    IF p_source_type = 'bank' THEN
        -- Try to find bank account from bank_accounts table
        SELECT account_id INTO v_source_acct_id
        FROM public.bank_accounts
        WHERE id = p_source_id;

        IF v_source_acct_id IS NULL THEN
            SELECT id INTO v_source_acct_id
            FROM public.accounts
            WHERE (code = '12211' OR account_code = '12211' OR name ILIKE '%بنك%')
              AND is_active = true
            ORDER BY id ASC LIMIT 1;
        END IF;
    ELSE
        -- Treasury / cash
        IF p_source_id IS NOT NULL THEN
            SELECT account_id INTO v_source_acct_id
            FROM public.treasuries
            WHERE id = p_source_id;
        END IF;

        IF v_source_acct_id IS NULL THEN
            SELECT id INTO v_source_acct_id
            FROM public.accounts
            WHERE (code = '12111' OR account_code = '12111'
                   OR name ILIKE '%صندوق%' OR name ILIKE '%خزينة%')
              AND is_active = true
            ORDER BY id ASC LIMIT 1;
        END IF;
    END IF;

    -- Create GL journal entry if both accounts exist
    IF v_supplier_acct_id IS NOT NULL AND v_source_acct_id IS NOT NULL THEN
        v_entry_number := 'TP-' || to_char(v_date, 'YYYYMMDD') || '-' ||
                          lpad((nextval('public.journal_entries_id_seq'::regclass) % 10000)::text, 4, '0');

        INSERT INTO public.journal_entries (
            entry_number, entry_date, description, status, source_type, source_id
        ) VALUES (
            v_entry_number, v_date, v_desc, 'posted',
            'transport_payment', 'transport_suppliers_' || p_supplier_id::text
        ) RETURNING id INTO v_journal_id;

        -- Debit: supplier account (reduce payable)
        INSERT INTO public.account_ledger_entries (
            journal_entry_id, account_id, debit, credit,
            currency, amount_in_base_currency, description,
            entity_type, entity_id
        ) VALUES (
            v_journal_id, v_supplier_acct_id, p_amount, 0,
            'EGP', p_amount, v_desc,
            'transport_supplier', p_supplier_id::text
        );

        -- Credit: cash/bank account
        INSERT INTO public.account_ledger_entries (
            journal_entry_id, account_id, debit, credit,
            currency, amount_in_base_currency, description,
            entity_type, entity_id
        ) VALUES (
            v_journal_id, v_source_acct_id, 0, p_amount,
            'EGP', p_amount, v_desc,
            'transport_supplier', p_supplier_id::text
        );
    END IF;

    -- Insert transport transaction
    INSERT INTO public.transport_transactions (
        supplier_id, type, amount, description,
        notes, journal_entry_id, date
    ) VALUES (
        p_supplier_id, v_txn_type, p_amount, v_desc,
        p_notes, v_journal_id, v_date
    ) RETURNING id INTO v_transaction_id;

    -- Update supplier balance (payment reduces balance)
    UPDATE public.transport_suppliers
    SET balance = COALESCE(balance, 0) - p_amount,
        current_balance = COALESCE(current_balance, 0) - p_amount,
        updated_at = NOW()
    WHERE id = p_supplier_id;

    RETURN jsonb_build_object(
        'success', true,
        'transaction_id', v_transaction_id,
        'journal_id', v_journal_id,
        'journal_number', v_entry_number,
        'amount', p_amount,
        'payment_type', v_txn_type
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_pay_transport_supplier(
    integer, text, integer, numeric, date, text, text
) TO authenticated, service_role, anon;


NOTIFY pgrst, 'reload_schema';

COMMIT;
