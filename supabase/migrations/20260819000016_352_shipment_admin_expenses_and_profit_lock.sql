-- ============================================================================
-- Migration 352: Shipment Admin Expenses Allocation & Profit Distribution Lock
-- Adds allocated_admin_expenses column to export_shipments
-- Creates rpc_save_shipment_admin_expenses to post GL entry (DR 5210 / CR 2105)
-- Enforces profit distribution lock against shareholder_profit_distributions
-- ============================================================================

BEGIN;

-- 1. Add column to export_shipments
ALTER TABLE public.export_shipments 
    ADD COLUMN IF NOT EXISTS allocated_admin_expenses NUMERIC(18,2) DEFAULT 0.00;

-- 2. Register Document Type
INSERT INTO public.sys_document_types (code, name, prefix)
VALUES ('shipment_admin_expenses', 'مصروفات إدارية محملة على الشحنة', 'ADM')
ON CONFLICT (code) DO NOTHING;

-- 3. Create RPC
CREATE OR REPLACE FUNCTION public.rpc_save_shipment_admin_expenses(
    p_shipment_id INT,
    p_allocated_admin_expenses NUMERIC,
    p_user_id UUID DEFAULT auth.uid()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_shipment RECORD;
    v_has_distribution BOOLEAN;
    v_company_id UUID;
    v_admin_exp_account_id BIGINT;
    v_provision_account_id BIGINT;
    v_je_id BIGINT;
    v_entry_num TEXT;
    v_amount NUMERIC := COALESCE(p_allocated_admin_expenses, 0.00);
BEGIN
    -- ── A. Check Profit Distribution Lock ──
    SELECT EXISTS (
        SELECT 1 FROM public.shareholder_profit_distributions
        WHERE shipment_id = p_shipment_id AND deleted_at IS NULL
    ) INTO v_has_distribution;

    IF v_has_distribution THEN
        RAISE EXCEPTION 'تم توزيع أرباح هذه الشحنة على المساهمين - لا يمكن تعديل التكاليف أو المصروفات الإدارية';
    END IF;

    -- ── B. Fetch Shipment ──
    SELECT * INTO v_shipment FROM public.export_shipments WHERE id = p_shipment_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'الشحنة غير موجودة');
    END IF;

    -- ── C. Update Export Shipment Record ──
    UPDATE public.export_shipments
    SET allocated_admin_expenses = v_amount,
        net_profit_egp = COALESCE(total_revenue_egp, 0) - COALESCE(total_landed_cost, 0) - v_amount,
        net_profit = COALESCE(total_revenue_egp, 0) - COALESCE(total_landed_cost, 0) - v_amount
    WHERE id = p_shipment_id;

    -- ── D. Resolve Accounts ──
    SELECT company_id INTO v_company_id FROM public.accounts WHERE account_code = '5210' LIMIT 1;
    IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1; END IF;

    -- 5210: Allocated Admin Expenses (مصروفات إدارية محملة)
    SELECT id INTO v_admin_exp_account_id FROM public.accounts WHERE account_code = '5210' LIMIT 1;
    IF v_admin_exp_account_id IS NULL THEN
        SELECT id INTO v_admin_exp_account_id FROM public.accounts WHERE account_code = '6000' LIMIT 1;
    END IF;

    -- 2105: Admin Expenses Provision (مخصص / وسيط مصروفات إدارية)
    SELECT id INTO v_provision_account_id FROM public.accounts WHERE account_code = '2105' LIMIT 1;
    IF v_provision_account_id IS NULL THEN
        SELECT id INTO v_provision_account_id FROM public.accounts WHERE account_code = '2100' LIMIT 1;
    END IF;

    -- ── E. Manage GL Journal Entry ──
    SELECT id INTO v_je_id
    FROM public.journal_entries
    WHERE source_type = 'shipment_admin_expenses' AND source_id = p_shipment_id::text AND deleted_at IS NULL
    LIMIT 1;

    IF v_amount > 0 THEN
        IF v_je_id IS NOT NULL THEN
            -- Update existing entry
            UPDATE public.journal_entries
            SET description = 'مصروفات إدارية محملة على شحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                updated_at = now()
            WHERE id = v_je_id;

            -- Replace ledger lines
            DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id;

            -- DR 5210
            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_je_id, v_admin_exp_account_id, v_amount, 0, 'EGP', v_amount,
                'تحميل مصروفات إدارية على شحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                v_company_id
            );

            -- CR 2105
            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_je_id, v_provision_account_id, 0, v_amount, 'EGP', v_amount,
                'مخصص مصروفات إدارية لشحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                v_company_id
            );
        ELSE
            -- Create new journal entry
            INSERT INTO public.journal_entries (
                entry_number, entry_date, description, status,
                is_auto_generated, source_type, source_id, company_id,
                created_by, created_at, updated_at
            ) VALUES (
                'PENDING',
                COALESCE(v_shipment.shipment_date, CURRENT_DATE),
                'مصروفات إدارية محملة على شحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                'posted', true, 'shipment_admin_expenses', p_shipment_id::text, v_company_id,
                COALESCE(p_user_id, auth.uid()), now(), now()
            ) RETURNING id INTO v_je_id;

            v_entry_num := public.fn_get_next_sequence(v_company_id, 'shipment_admin_expenses', NULL, NULL);
            IF v_entry_num IS NULL OR v_entry_num = '' THEN
                v_entry_num := 'ADM-' || LPAD(v_je_id::text, 5, '0');
            END IF;
            UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

            -- DR 5210
            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_je_id, v_admin_exp_account_id, v_amount, 0, 'EGP', v_amount,
                'تحميل مصروفات إدارية على شحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                v_company_id
            );

            -- CR 2105
            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_je_id, v_provision_account_id, 0, v_amount, 'EGP', v_amount,
                'مخصص مصروفات إدارية لشحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                v_company_id
            );
        END IF;
    ELSE
        -- If amount is 0 and JE exists, soft delete it
        IF v_je_id IS NOT NULL THEN
            UPDATE public.journal_entries SET deleted_at = now() WHERE id = v_je_id;
            DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'shipment_id', p_shipment_id,
        'allocated_admin_expenses', v_amount,
        'journal_entry_id', v_je_id
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_save_shipment_admin_expenses(INT, NUMERIC, UUID) TO authenticated;

COMMIT;
