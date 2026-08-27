-- Migration 093: Diagnostic — add debug logging to rpc_confirm_purchase
-- and ensure post_journal_entry has the correct UUID signature

-- First, check how many overloads of post_journal_entry exist
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT oid, proname, pg_get_function_arguments(oid) AS args
    FROM pg_proc WHERE proname = 'post_journal_entry' AND pronamespace = 'public'::regnamespace
  LOOP
    RAISE NOTICE 'post_journal_entry overload: oid=% args=%', r.oid, r.args;
  END LOOP;
END $$;

-- Drop ALL overloads of post_journal_entry to start fresh
DROP FUNCTION IF EXISTS public.post_journal_entry(TEXT, TEXT, DATE, UUID, UUID, JSONB) CASCADE;
DROP FUNCTION IF EXISTS public.post_journal_entry(UUID, DATE, TEXT, TEXT, UUID, JSONB) CASCADE;

-- Recreate with the correct signature
CREATE OR REPLACE FUNCTION public.post_journal_entry(
    p_source_type  TEXT,
    p_description  TEXT,
    p_entry_date   DATE,
    p_company_id   UUID,
    p_created_by   UUID,
    p_lines        JSONB
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
        is_auto_generated, source_type, created_by, company_id
    ) VALUES (
        v_entry_number, p_entry_date, p_description, 'posted',
        true, p_source_type, p_created_by, p_company_id
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

GRANT EXECUTE ON FUNCTION public.post_journal_entry(TEXT, TEXT, DATE, UUID, UUID, JSONB) TO authenticated, service_role, anon;

NOTIFY pgrst, 'reload schema';
