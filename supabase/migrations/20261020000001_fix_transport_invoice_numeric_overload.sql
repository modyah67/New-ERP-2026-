-- ============================================================================
-- Migration: Fix rpc_add_transport_invoice Function Overload & NUMERIC Support
-- Problem: PostgREST error PGRST203 (Multiple Choices) when calling
--          rpc_add_transport_invoice because overloaded versions exist
--          (one with integer truck counts and one with numeric truck counts).
-- Fix:
--   1. Ensure transport_suppliers and transport_transactions support NUMERIC truck counts.
--   2. Drop ALL existing overloaded versions of rpc_add_transport_invoice dynamically.
--   3. Create a single, canonical rpc_add_transport_invoice supporting NUMERIC truck counts (e.g. 2.5).
--   4. Ensure get_transport_supplier_true_balances returns NUMERIC truck_balance.
-- ============================================================================

BEGIN;

-- 1. Ensure columns support fractional/decimal truck counts (e.g., 2.5)
ALTER TABLE IF EXISTS public.transport_suppliers 
  ALTER COLUMN truck_balance TYPE NUMERIC(12,2) USING truck_balance::numeric,
  ALTER COLUMN initial_truck_balance TYPE NUMERIC(12,2) USING initial_truck_balance::numeric;

ALTER TABLE IF EXISTS public.transport_transactions 
  ALTER COLUMN truck_count TYPE NUMERIC(12,2) USING truck_count::numeric;

ALTER TABLE IF EXISTS public.packing_order_cost_items 
  ALTER COLUMN truck_count TYPE NUMERIC(12,2) USING truck_count::numeric;

-- 2. Drop ALL existing overloaded signatures of rpc_add_transport_invoice
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT p.proname, pg_get_function_identity_arguments(p.oid) as args
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'rpc_add_transport_invoice'
    ) LOOP
        EXECUTE format('DROP FUNCTION IF EXISTS public.%I(%s) CASCADE;', r.proname, r.args);
    END LOOP;
END $$;

-- 3. Create the single canonical rpc_add_transport_invoice
CREATE OR REPLACE FUNCTION public.rpc_add_transport_invoice(
    p_supplier_id        integer,
    p_amount             numeric,
    p_number_of_trucks   numeric DEFAULT 1,
    p_truck_count        numeric DEFAULT 1,
    p_route_from         text    DEFAULT NULL,
    p_route_to           text    DEFAULT NULL,
    p_date               date    DEFAULT NULL,
    p_description        text    DEFAULT NULL,
    p_expense_account_id integer DEFAULT NULL,
    p_reference_number   text    DEFAULT NULL,
    p_notes              text    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_date             date;
    v_truck_count      numeric;
    v_desc             text;
    v_supplier         RECORD;
    v_journal_id       bigint;
    v_entry_number     text;
    v_transaction_id   integer;
    v_expense_acct_id  bigint;
    v_supplier_acct_id bigint;
BEGIN
    v_date := COALESCE(p_date, (NOW() AT TIME ZONE 'Africa/Cairo')::date);
    v_truck_count := COALESCE(NULLIF(p_truck_count, 0), NULLIF(p_number_of_trucks, 0), 1.0);

    IF p_amount IS NULL OR p_amount <= 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'المبلغ يجب أن يكون أكبر من صفر');
    END IF;

    SELECT id, name, account_id, balance, truck_balance
    INTO v_supplier
    FROM public.transport_suppliers
    WHERE id = p_supplier_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'مورد النقل غير موجود');
    END IF;

    v_desc := COALESCE(p_description, 'فاتورة نقل - ' || v_supplier.name);
    IF p_route_from IS NOT NULL AND p_route_to IS NOT NULL THEN
        v_desc := v_desc || ' (' || p_route_from || ' → ' || p_route_to || ')';
    END IF;

    v_expense_acct_id := p_expense_account_id;
    IF v_expense_acct_id IS NULL THEN
        SELECT id INTO v_expense_acct_id
        FROM public.accounts
        WHERE (code = '51311' OR account_code = '51311'
               OR name ILIKE '%مصاريف نقل%' OR name ILIKE '%نقل%')
          AND is_active = true
        ORDER BY
            CASE WHEN code = '51311' OR account_code = '51311' THEN 0 ELSE 1 END
        LIMIT 1;
    END IF;

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

    IF v_expense_acct_id IS NOT NULL AND v_supplier_acct_id IS NOT NULL THEN
        v_entry_number := 'TI-' || to_char(v_date, 'YYYYMMDD') || '-' ||
                          lpad((nextval('public.journal_entries_id_seq'::regclass) % 10000)::text, 4, '0');

        INSERT INTO public.journal_entries (
            entry_number, entry_date, description, status, source_type, source_id
        ) VALUES (
            v_entry_number, v_date, v_desc, 'posted',
            'transport_invoice', 'transport_suppliers_' || p_supplier_id::text
        ) RETURNING id INTO v_journal_id;

        INSERT INTO public.account_ledger_entries (
            journal_entry_id, account_id, debit, credit,
            currency, amount_in_base_currency, description,
            entity_type, entity_id
        ) VALUES (
            v_journal_id, v_expense_acct_id, p_amount, 0,
            'EGP', p_amount, v_desc,
            'transport_supplier', p_supplier_id::text
        );

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

    INSERT INTO public.transport_transactions (
        supplier_id, type, amount, truck_count, description,
        notes, journal_entry_id, date, reference_id, route_from, route_to
    ) VALUES (
        p_supplier_id, 'invoice', p_amount, v_truck_count, v_desc,
        p_notes, v_journal_id, v_date, p_reference_number, p_route_from, p_route_to
    ) RETURNING id INTO v_transaction_id;

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
    integer, numeric, numeric, numeric, text, text, date, text, integer, text, text
) TO authenticated, service_role, anon;

-- 4. Update get_transport_supplier_true_balances with NUMERIC truck_balance
DROP FUNCTION IF EXISTS public.get_transport_supplier_true_balances();

CREATE OR REPLACE FUNCTION public.get_transport_supplier_true_balances()
RETURNS TABLE (
  supplier_id integer,
  true_balance numeric,
  financial_balance numeric,
  truck_balance numeric
)
LANGUAGE sql
SECURITY DEFINER
AS $func$
  SELECT
    ts.id AS supplier_id,
    (
      (CASE WHEN ts.initial_balance_direction = 'CREDIT' THEN COALESCE(ts.initial_balance, 0) ELSE -COALESCE(ts.initial_balance, 0) END)
      + COALESCE((
          SELECT SUM(tt.amount)
          FROM public.transport_transactions tt
          WHERE tt.supplier_id = ts.id AND tt.type IN ('invoice', 'packing_order_invoice')
        ), 0)
      - COALESCE((
          SELECT SUM(tt.amount)
          FROM public.transport_transactions tt
          WHERE tt.supplier_id = ts.id AND tt.type IN ('cash_payment', 'bank_payment')
        ), 0)
    )::numeric AS true_balance,

    (
      (CASE WHEN ts.initial_balance_direction = 'CREDIT' THEN COALESCE(ts.initial_balance, 0) ELSE -COALESCE(ts.initial_balance, 0) END)
      + COALESCE((
          SELECT SUM(tt.amount)
          FROM public.transport_transactions tt
          WHERE tt.supplier_id = ts.id AND tt.type IN ('invoice', 'packing_order_invoice')
        ), 0)
      - COALESCE((
          SELECT SUM(tt.amount)
          FROM public.transport_transactions tt
          WHERE tt.supplier_id = ts.id AND tt.type IN ('cash_payment', 'bank_payment')
        ), 0)
    )::numeric AS financial_balance,

    (
      COALESCE(ts.initial_truck_balance, 0)
      + COALESCE((
          SELECT SUM(COALESCE(tt.truck_count, 1))
          FROM public.transport_transactions tt
          WHERE tt.supplier_id = ts.id AND tt.type IN ('invoice')
        ), 0)
      - COALESCE((
          SELECT SUM(COALESCE(tt.truck_count, 1))
          FROM public.transport_transactions tt
          WHERE tt.supplier_id = ts.id AND tt.type IN ('packing_consumption')
        ), 0)
    )::numeric AS truck_balance
  FROM public.transport_suppliers ts;
$func$;

GRANT EXECUTE ON FUNCTION public.get_transport_supplier_true_balances() TO authenticated, anon, service_role;

-- 5. Force PostgREST schema cache reload
NOTIFY pgrst, 'reload schema';

COMMIT;
