-- Fix create_cheque: DROP all overloads, CREATE correct version
-- Problems fixed:
-- 1. Dart sends p_number → SQL expects p_cheque_number
-- 2. Dart doesn't send p_issue_date (required param)
-- 3. p_shareholder_id was BIGINT but cheques.shareholder_id column is UUID
-- 4. Old overloaded versions from archived migrations may still exist

-- 1. Drop ALL existing overloads of create_cheque
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT oid::regprocedure
    FROM pg_proc
    WHERE proname = 'create_cheque'
      AND pronamespace = 'public'::regnamespace
  LOOP
    EXECUTE 'DROP FUNCTION IF EXISTS ' || r.oid || ' CASCADE';
  END LOOP;
END $$;

-- 2. Create the correct version (matches initial_schema canonical version)
CREATE OR REPLACE FUNCTION public.create_cheque(
    p_cheque_number         TEXT,
    p_type                  TEXT,
    p_amount                NUMERIC,
    p_currency              TEXT,
    p_issue_date            DATE,
    p_due_date              DATE,
    p_counterparty_type     TEXT DEFAULT NULL,
    p_counterparty_id       BIGINT DEFAULT NULL,
    p_notes                 TEXT DEFAULT NULL,
    p_supplier_id           UUID DEFAULT NULL,
    p_clearing_agent_id     BIGINT DEFAULT NULL,
    p_shipping_company_id   BIGINT DEFAULT NULL,
    p_shareholder_id        UUID DEFAULT NULL,
    p_category_id           INTEGER DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_id BIGINT;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    IF p_due_date < p_issue_date THEN
        RAISE EXCEPTION 'تاريخ الاستحقاق يجب أن يكون بعد تاريخ التحرير';
    END IF;

    INSERT INTO public.cheques (
        cheque_number, type, status, amount, currency,
        issue_date, due_date, counterparty_type, counterparty_id,
        supplier_id, clearing_agent_id, shipping_company_id, shareholder_id,
        notes, created_by, category_id
    ) VALUES (
        p_cheque_number, p_type, 'pending', p_amount, p_currency,
        p_issue_date, p_due_date, p_counterparty_type, p_counterparty_id,
        p_supplier_id, p_clearing_agent_id, p_shipping_company_id, p_shareholder_id,
        p_notes, auth.uid(), p_category_id
    ) RETURNING id INTO v_id;

    RETURN jsonb_build_object('id', v_id);
END;
$$;

-- 3. Grant execute
GRANT EXECUTE ON FUNCTION public.create_cheque(
    TEXT, TEXT, NUMERIC, TEXT, DATE, DATE,
    TEXT, BIGINT, TEXT, UUID, BIGINT, BIGINT, UUID, INTEGER
) TO authenticated;

-- 4. Fix get_pending_cheques_for_notification shareholder_id type in RETURNS TABLE
DROP FUNCTION IF EXISTS public.get_pending_cheques_for_notification(INTEGER);

CREATE OR REPLACE FUNCTION public.get_pending_cheques_for_notification(p_days_ahead INTEGER DEFAULT 3)
RETURNS TABLE (
    id                BIGINT,
    cheque_number     TEXT,
    type              TEXT,
    amount            NUMERIC,
    currency          TEXT,
    due_date          DATE,
    counterparty_type TEXT,
    counterparty_id   BIGINT,
    supplier_id       UUID,
    clearing_agent_id     BIGINT,
    shipping_company_id   BIGINT,
    shareholder_id        UUID,
    counterparty_name TEXT,
    days_remaining    INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.id, c.cheque_number, c.type, c.amount, c.currency, c.due_date,
        c.counterparty_type, c.counterparty_id, c.supplier_id,
        c.clearing_agent_id, c.shipping_company_id, c.shareholder_id,
        COALESCE(
            CASE
                WHEN c.counterparty_type = 'customer' THEN (SELECT name FROM public.customers WHERE id = c.counterparty_id)
                WHEN c.counterparty_type = 'supplier' THEN (SELECT name FROM public.suppliers WHERE id = c.supplier_id)
                WHEN c.counterparty_type = 'clearing_agent' THEN (SELECT name FROM public.clearing_agents WHERE id = c.clearing_agent_id)
                WHEN c.counterparty_type = 'shipping_company' THEN (SELECT name FROM public.shipping_companies WHERE id = c.shipping_company_id)
                WHEN c.counterparty_type = 'shareholder' THEN (SELECT name FROM public.shareholders WHERE id = c.shareholder_id)
                ELSE NULL
            END,
            '—'
        ) AS counterparty_name,
        (c.due_date - CURRENT_DATE)::INTEGER AS days_remaining
    FROM public.cheques c
    WHERE c.status = 'pending'
      AND c.due_date BETWEEN CURRENT_DATE AND (CURRENT_DATE + p_days_ahead)
    ORDER BY c.due_date ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_pending_cheques_for_notification(INTEGER) TO authenticated;

-- 5. Notify PostgREST to reload schema cache
NOTIFY pgrst, 'reload schema';

