-- ==============================================================================
-- Migration: fix_multi_payment_multi_currency_and_balance_sync.sql
-- Description:
--   Comprehensive fix for multi-invoice payment, multi-currency balance tracking,
--   and supplier balance synchronization:
--   1. Ensures supplier_payment_allocations has currency, entity_type, entity_id columns.
--   2. Adds public.sync_supplier_balances(p_supplier_id uuid) to sync both:
--      - current_balances_by_currency (JSONB map of balances per currency)
--      - outstanding_balance (total balance in EGP)
--   3. Updates rpc_entity_multi_payment:
--      - Handles multi-currency opening balance extraction from initial_balances_by_currency.
--      - Sums previous opening balance payments per currency.
--      - Records currency in supplier_payment_allocations for opening balance, invoices, and advance.
--      - Calls sync_supplier_balances() on payment completion so UI immediately sees fresh balances.
--   4. Re-syncs all suppliers' balances immediately.
-- ==============================================================================

-- 1. Ensure required columns on supplier_payment_allocations
ALTER TABLE public.supplier_payment_allocations 
  ADD COLUMN IF NOT EXISTS currency TEXT,
  ADD COLUMN IF NOT EXISTS entity_type TEXT,
  ADD COLUMN IF NOT EXISTS entity_id TEXT;

-- 2. Helper function to sync supplier balances across all currencies
CREATE OR REPLACE FUNCTION public.sync_supplier_balances(p_supplier_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_cur_balances jsonb := '{}'::jsonb;
  v_total_egp numeric := 0;
  r RECORD;
BEGIN
  IF to_regproc('public.get_supplier_true_balances_by_currency') IS NOT NULL THEN
    FOR r IN 
      SELECT currency, true_balance, true_balance_egp
      FROM public.get_supplier_true_balances_by_currency()
      WHERE supplier_id = p_supplier_id
    LOOP
      v_cur_balances := v_cur_balances || jsonb_build_object(r.currency, r.true_balance);
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
    SET outstanding_balance = (SELECT true_balance FROM public.get_supplier_true_balances() WHERE supplier_id = p_supplier_id)
    WHERE id = p_supplier_id;
  END IF;
END;
$$;

-- 3. Update rpc_entity_multi_payment
CREATE OR REPLACE FUNCTION public.rpc_entity_multi_payment(
    p_source_type text,
    p_source_id bigint,
    p_currency text,
    p_amount numeric,
    p_entity_type text,
    p_entity_id text,
    p_description text,
    p_expense_account_id bigint DEFAULT NULL::bigint,
    p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_tx_id BIGINT;
    v_initial_je_id BIGINT;
    v_je_id BIGINT;
    v_company_id UUID;
    v_source_acct BIGINT;
    v_entity_acct BIGINT;
    v_realized_gain_acct BIGINT;
    v_realized_loss_acct BIGINT;
    v_book_rate NUMERIC := 1.0;
    v_remaining_to_allocate NUMERIC := p_amount;
    v_liab RECORD;
    v_allocation_amount NUMERIC;
    v_inv_rate NUMERIC;
    v_inv_base NUMERIC;
    v_paid_base NUMERIC;
    v_diff NUMERIC;
    v_total_realized_gain NUMERIC := 0.0;
    v_total_realized_loss NUMERIC := 0.0;
    v_total_ap_base NUMERIC := 0.0;
    v_total_cash_base NUMERIC := 0.0;
    v_initial_balance NUMERIC := 0;
    v_initial_direction TEXT := 'CREDIT';
    v_is_multi_curr BOOLEAN := false;
    v_opening_paid NUMERIC := 0;
    v_opening_remaining NUMERIC := 0;
    v_opening_alloc NUMERIC := 0;
    v_advance_alloc NUMERIC := 0;
    v_invoices_allocated_count INT := 0;
    v_je_lines JSONB := '[]'::jsonb;
    v_entity_name TEXT;
    v_source_name TEXT;
    v_desc TEXT;
    v_supplier_uuid UUID;
    v_norm_entity_type TEXT;
    v_doc_type TEXT;
    v_entry_date DATE;
    v_sup_record RECORD;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'مبلغ السداد يجب أن يكون أكبر من صفر';
    END IF;

    v_norm_entity_type := LOWER(p_entity_type);
    v_entry_date := (NOW() AT TIME ZONE 'Africa/Cairo')::DATE;

    -- 1. Fetch entity info & GL account based on normalized entity type
    IF v_norm_entity_type = 'supplier' THEN
        v_supplier_uuid := p_entity_id::uuid;
        SELECT * INTO v_sup_record FROM public.suppliers WHERE id = v_supplier_uuid;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'المورد غير موجود: %', p_entity_id;
        END IF;

        v_entity_name := v_sup_record.name;
        v_company_id := v_sup_record.company_id;
        v_entity_acct := v_sup_record.account_id;
        v_is_multi_curr := COALESCE(v_sup_record.is_multi_currency, false);

        IF v_is_multi_curr AND v_sup_record.initial_balances_by_currency IS NOT NULL THEN
            IF v_sup_record.initial_balances_by_currency ? p_currency THEN
                v_initial_balance := COALESCE((v_sup_record.initial_balances_by_currency->p_currency->>'amount')::numeric, 0);
                v_initial_direction := UPPER(COALESCE(v_sup_record.initial_balances_by_currency->p_currency->>'direction', 'CREDIT'));
            ELSIF v_sup_record.initial_balances_by_currency ? UPPER(p_currency) THEN
                v_initial_balance := COALESCE((v_sup_record.initial_balances_by_currency->UPPER(p_currency)->>'amount')::numeric, 0);
                v_initial_direction := UPPER(COALESCE(v_sup_record.initial_balances_by_currency->UPPER(p_currency)->>'direction', 'CREDIT'));
            END IF;
        ELSE
            IF UPPER(COALESCE(v_sup_record.currency, 'EGP')) = UPPER(p_currency) THEN
                v_initial_balance := COALESCE(v_sup_record.initial_balance, 0);
                v_initial_direction := UPPER(COALESCE(v_sup_record.initial_balance_direction, 'CREDIT'));
            END IF;
        END IF;

    ELSIF v_norm_entity_type = 'shipping_company' THEN
        SELECT 
            name, 
            CASE WHEN UPPER(COALESCE(currency, 'EGP')) = UPPER(p_currency) THEN COALESCE(initial_balance, 0) ELSE 0 END,
            COALESCE(initial_balance_direction, 'CREDIT'), 
            company_id, 
            account_id
        INTO v_entity_name, v_initial_balance, v_initial_direction, v_company_id, v_entity_acct
        FROM public.shipping_companies WHERE id = p_entity_id::bigint;
    ELSIF v_norm_entity_type = 'clearing_agent' THEN
        SELECT 
            name, 
            CASE WHEN UPPER(COALESCE(currency, 'EGP')) = UPPER(p_currency) THEN COALESCE(initial_balance, 0) ELSE 0 END,
            COALESCE(initial_balance_direction, 'CREDIT'), 
            company_id, 
            account_id
        INTO v_entity_name, v_initial_balance, v_initial_direction, v_company_id, v_entity_acct
        FROM public.clearing_agents WHERE id = p_entity_id::bigint;
    ELSIF v_norm_entity_type IN ('transport_supplier', 'transport') THEN
        v_norm_entity_type := 'transport_supplier';
        SELECT 
            name, 
            CASE WHEN UPPER(COALESCE(currency, 'EGP')) = UPPER(p_currency) THEN COALESCE(initial_balance, 0) ELSE 0 END,
            COALESCE(initial_balance_direction, 'CREDIT'), 
            company_id, 
            account_id
        INTO v_entity_name, v_initial_balance, v_initial_direction, v_company_id, v_entity_acct
        FROM public.transport_suppliers WHERE id = p_entity_id::bigint;
    ELSE
        RAISE EXCEPTION 'نوع الجهة غير صالح: %', p_entity_type;
    END IF;

    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    IF v_entity_acct IS NULL THEN
        IF v_norm_entity_type = 'supplier' THEN
            v_entity_acct := public.resolve_gl_account('2000', v_company_id);
        ELSIF v_norm_entity_type = 'shipping_company' THEN
            v_entity_acct := public.resolve_gl_account('2103', v_company_id);
        ELSIF v_norm_entity_type = 'clearing_agent' THEN
            v_entity_acct := public.resolve_gl_account('2104', v_company_id);
        ELSIF v_norm_entity_type IN ('transport_supplier', 'transport') THEN
            v_entity_acct := public.resolve_gl_account('2105', v_company_id);
            IF v_entity_acct IS NULL THEN
                v_entity_acct := public.resolve_gl_account('2000', v_company_id);
            END IF;
        END IF;
    END IF;

    -- 2. Resolve Source Book Rate and GL Account
    IF p_source_type = 'treasury' THEN
        v_doc_type := 'treasury_multi_payment';

        SELECT COALESCE(NULLIF(book_rate, 0), public.fn_get_exchange_rate(p_currency))
        INTO v_book_rate
        FROM public.treasury_balances
        WHERE treasury_id::text = p_source_id::text AND currency = p_currency;

        SELECT name INTO v_source_name FROM public.treasuries WHERE id = p_source_id;
        v_source_acct := public.resolve_treasury_account(p_source_id::integer, p_currency, v_company_id);
    ELSIF p_source_type = 'bank' THEN
        v_doc_type := 'bank_multi_payment';

        SELECT COALESCE(NULLIF(book_rate, 0), public.fn_get_exchange_rate(p_currency))
        INTO v_book_rate
        FROM public.bank_accounts
        WHERE id = p_source_id::integer;

        SELECT name INTO v_source_name FROM public.bank_accounts WHERE id = p_source_id::integer;
        v_source_acct := public.resolve_gl_account(
            CASE p_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
            v_company_id
        );
    ELSE
        RAISE EXCEPTION 'نوع المصدر غير صالح: %', p_source_type;
    END IF;

    IF v_book_rate IS NULL OR v_book_rate <= 0 THEN
        v_book_rate := public.fn_get_exchange_rate(p_currency);
    END IF;

    v_total_cash_base := ROUND(p_amount * v_book_rate, 2);

    -- 3. Execute Cash / Bank Payment (Withdrawal)
    IF p_source_type = 'treasury' THEN
        v_tx_id := public.spend_custody(
            p_treasury_id := p_source_id,
            p_currency := p_currency,
            p_amount := p_amount,
            p_description := COALESCE(NULLIF(p_description, ''), 'سداد مديونيات متعددة: ' || v_entity_name),
            p_supplier_id := CASE WHEN v_norm_entity_type = 'supplier' THEN v_supplier_uuid ELSE NULL END,
            p_clearing_agent_id := CASE WHEN v_norm_entity_type = 'clearing_agent' THEN p_entity_id::bigint ELSE NULL END,
            p_shipping_company_id := CASE WHEN v_norm_entity_type = 'shipping_company' THEN p_entity_id::bigint ELSE NULL END,
            p_expense_account_id := (COALESCE(p_expense_account_id, v_entity_acct))::integer,
            p_reference_type := v_norm_entity_type || '_payment',
            p_reference_id := p_entity_id,
            p_notes := p_notes
        );
        SELECT journal_entry_id INTO v_initial_je_id FROM public.treasury_transactions WHERE id = v_tx_id;
    ELSIF p_source_type = 'bank' THEN
        DECLARE
            v_bank_res JSONB;
        BEGIN
            v_bank_res := public.withdraw_bank_account(
                p_account_id := p_source_id::INTEGER,
                p_amount := p_amount,
                p_description := COALESCE(NULLIF(p_description, ''), 'سداد مديونيات متعددة: ' || v_entity_name),
                p_entity_type := v_norm_entity_type,
                p_entity_id := p_entity_id,
                p_counterparty_name := v_entity_name,
                p_expense_account_id := COALESCE(p_expense_account_id, v_entity_acct::integer),
                p_notes := p_notes,
                p_reference_type := v_norm_entity_type || '_payment',
                p_reference_id := p_entity_id
            );
            v_tx_id := (v_bank_res->>'transaction_id')::BIGINT;
            v_initial_je_id := (v_bank_res->>'journal_entry_id')::BIGINT;
        END;
    END IF;

    -- 4. Calculate Remaining Opening Balance to Allocate (Filtered by currency!)
    IF UPPER(v_initial_direction) = 'CREDIT' AND v_initial_balance > 0 THEN
        IF v_norm_entity_type = 'supplier' THEN
            SELECT COALESCE(SUM(amount), 0) INTO v_opening_paid
            FROM public.supplier_payment_allocations
            WHERE supplier_id = v_supplier_uuid 
              AND allocation_type = 'opening_balance'
              AND (currency = p_currency OR currency IS NULL);

            v_opening_remaining := GREATEST(0, v_initial_balance - v_opening_paid);
        ELSE
            SELECT COALESCE(SUM(amount), 0) INTO v_opening_paid
            FROM public.supplier_payment_allocations
            WHERE entity_type = v_norm_entity_type 
              AND entity_id = p_entity_id
              AND allocation_type = 'opening_balance'
              AND (currency = p_currency OR currency IS NULL);

            v_opening_remaining := GREATEST(0, v_initial_balance - v_opening_paid);
        END IF;
    ELSE
        v_opening_remaining := 0;
    END IF;

    -- 5. Allocation Priority 1: Opening Balance
    IF v_opening_remaining > 0 AND v_remaining_to_allocate > 0 THEN
        v_opening_alloc := LEAST(v_remaining_to_allocate, v_opening_remaining);

        INSERT INTO public.supplier_payment_allocations (
            source_type, source_id, supplier_id, entity_type, entity_id, allocation_type, amount, currency, allocated_amount
        ) VALUES (
            p_source_type, v_tx_id, v_supplier_uuid, v_norm_entity_type, p_entity_id, 'opening_balance', v_opening_alloc, p_currency, v_opening_alloc
        );

        v_total_ap_base := v_total_ap_base + ROUND(v_opening_alloc * v_book_rate, 2);
        v_remaining_to_allocate := v_remaining_to_allocate - v_opening_alloc;
    END IF;

    -- 6. Allocation Priority 2: Unpaid Liabilities (FIFO by liability_date)
    FOR v_liab IN 
        SELECT liability_type, liability_id, reference_number, currency, currency_snapshot, due_amount
        FROM public.vw_unpaid_liabilities
        WHERE LOWER(entity_type) = v_norm_entity_type
          AND entity_id = p_entity_id
          AND currency = p_currency
        ORDER BY liability_date ASC, liability_id ASC
    LOOP
        EXIT WHEN v_remaining_to_allocate <= 0;

        v_allocation_amount := LEAST(v_remaining_to_allocate, v_liab.due_amount);

        -- Extract Invoice Original Pegged Exchange Rate
        v_inv_rate := COALESCE(
            (v_liab.currency_snapshot->>'exchange_rate')::NUMERIC,
            public.fn_get_exchange_rate(p_currency)
        );

        -- Realized FX Math (IAS 21):
        v_inv_base  := ROUND(v_allocation_amount * v_inv_rate, 2);
        v_paid_base := ROUND(v_allocation_amount * v_book_rate, 2);
        v_diff      := v_paid_base - v_inv_base;

        v_total_ap_base := v_total_ap_base + v_inv_base;

        IF v_diff < 0 THEN
            v_total_realized_gain := v_total_realized_gain + ABS(v_diff);
        ELSIF v_diff > 0 THEN
            v_total_realized_loss := v_total_realized_loss + v_diff;
        END IF;

        -- Update the specific liability table
        IF v_liab.liability_type = 'purchase_invoice' THEN
            INSERT INTO public.supplier_payment_allocations (
                source_type, source_id, purchase_invoice_id, supplier_id, entity_type, entity_id, allocation_type, amount, currency, allocated_amount
            ) VALUES (
                p_source_type, v_tx_id, v_liab.liability_id::bigint, v_supplier_uuid, v_norm_entity_type, p_entity_id, 'invoice', v_allocation_amount, p_currency, v_allocation_amount
            );

            UPDATE public.purchase_invoices
            SET paid_amount = COALESCE(paid_amount, 0) + v_allocation_amount,
                payment_status = CASE 
                    WHEN (COALESCE(paid_amount, 0) + v_allocation_amount) >= (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0) - 0.001) THEN 'paid' 
                    ELSE 'partial' 
                END,
                payment_treasury_id = CASE WHEN p_source_type = 'treasury' THEN p_source_id::text END,
                payment_bank_account_id = CASE WHEN p_source_type = 'bank' THEN p_source_id::integer END,
                payment_source_type = p_source_type,
                updated_at = NOW()
            WHERE id::text = v_liab.liability_id;
            
        ELSIF v_liab.liability_type = 'lot_receipt' THEN
            INSERT INTO public.supplier_payment_allocations (
                source_type, source_id, lot_receipt_id, supplier_id, entity_type, entity_id, allocation_type, amount, currency, allocated_amount
            ) VALUES (
                p_source_type, v_tx_id, v_liab.liability_id::bigint, v_supplier_uuid, v_norm_entity_type, p_entity_id, 'lot_receipt', v_allocation_amount, p_currency, v_allocation_amount
            );

            UPDATE public.lot_receipts
            SET paid_amount = COALESCE(paid_amount, 0) + v_allocation_amount,
                payment_status = CASE 
                    WHEN (COALESCE(paid_amount, 0) + v_allocation_amount) >= (COALESCE(total_fruit_cost, 0) - 0.001) THEN 'paid' 
                    ELSE 'partial' 
                END,
                payment_treasury_id = CASE WHEN p_source_type = 'treasury' THEN p_source_id::text END,
                payment_bank_account_id = CASE WHEN p_source_type = 'bank' THEN p_source_id::integer END,
                payment_source_type = p_source_type,
                updated_at = NOW()
            WHERE id::text = v_liab.liability_id;
            
        ELSIF v_liab.liability_type = 'packing_cost_item' THEN
            INSERT INTO public.supplier_payment_allocations (
                source_type, source_id, packing_order_cost_item_id, supplier_id, entity_type, entity_id, allocation_type, amount, currency, allocated_amount
            ) VALUES (
                p_source_type, v_tx_id, v_liab.liability_id::bigint, v_supplier_uuid, v_norm_entity_type, p_entity_id, 'packing_cost', v_allocation_amount, p_currency, v_allocation_amount
            );

            UPDATE public.packing_order_cost_items
            SET paid_amount = COALESCE(paid_amount, 0) + v_allocation_amount,
                payment_status = CASE 
                    WHEN (COALESCE(paid_amount, 0) + v_allocation_amount) >= (COALESCE(original_amount, 0) - 0.001) THEN 'paid' 
                    ELSE 'partial' 
                END,
                payment_treasury_id = CASE WHEN p_source_type = 'treasury' THEN p_source_id::text END,
                payment_bank_account_id = CASE WHEN p_source_type = 'bank' THEN p_source_id::integer END,
                payment_source_type = p_source_type
            WHERE id::text = v_liab.liability_id;
            
        ELSIF v_liab.liability_type = 'shipment_cost_item' THEN
            INSERT INTO public.supplier_payment_allocations (
                source_type, source_id, shipment_cost_item_id, supplier_id, entity_type, entity_id, allocation_type, amount, currency, allocated_amount
            ) VALUES (
                p_source_type, v_tx_id, v_liab.liability_id::bigint, v_supplier_uuid, v_norm_entity_type, p_entity_id, 'shipment_cost', v_allocation_amount, p_currency, v_allocation_amount
            );

            UPDATE public.shipment_cost_items
            SET paid_amount = COALESCE(paid_amount, 0) + v_allocation_amount,
                payment_status = CASE 
                    WHEN (COALESCE(paid_amount, 0) + v_allocation_amount) >= (ROUND(COALESCE(NULLIF(total_price, 0), quantity * unit_price, 0) / COALESCE(NULLIF(exchange_rate, 0), 1.0), 2) - 0.001) THEN 'paid' 
                    ELSE 'partial' 
                END,
                payment_treasury_id = CASE WHEN p_source_type = 'treasury' THEN p_source_id::text END,
                payment_bank_account_id = CASE WHEN p_source_type = 'bank' THEN p_source_id::integer END,
                payment_source_type = p_source_type
            WHERE id::text = v_liab.liability_id;
        END IF;

        v_invoices_allocated_count := v_invoices_allocated_count + 1;
        v_remaining_to_allocate := v_remaining_to_allocate - v_allocation_amount;
    END LOOP;

    -- 7. Allocation Priority 3: Advance Payment / Credit Balance
    IF v_remaining_to_allocate > 0 THEN
        v_advance_alloc := v_remaining_to_allocate;

        INSERT INTO public.supplier_payment_allocations (
            source_type, source_id, supplier_id, entity_type, entity_id, allocation_type, amount, currency, allocated_amount
        ) VALUES (
            p_source_type, v_tx_id, v_supplier_uuid, v_norm_entity_type, p_entity_id, 'advance', v_advance_alloc, p_currency, v_advance_alloc
        );

        v_total_ap_base := v_total_ap_base + ROUND(v_advance_alloc * v_book_rate, 2);
    END IF;

    -- 8. Post / Adjust GL Journal Entry for Realized FX Differences
    IF v_total_realized_gain > 0 OR v_total_realized_loss > 0 THEN
        IF v_initial_je_id IS NOT NULL THEN
            DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_initial_je_id;
            DELETE FROM public.journal_entries WHERE id = v_initial_je_id;
        END IF;

        v_realized_gain_acct := public.resolve_realized_fx_gain_account(v_company_id);
        v_realized_loss_acct := public.resolve_realized_fx_loss_account(v_company_id);

        v_desc := COALESCE(NULLIF(p_description, ''), 'سداد مديونيات مع تسوية فروق عملة محققة: ' || v_entity_name);

        v_je_lines := jsonb_build_array(
            jsonb_build_object(
                'account_id', v_entity_acct,
                'debit', p_amount,
                'credit', 0,
                'base_debit', v_total_ap_base,
                'base_credit', 0,
                'currency', p_currency,
                'description', v_desc || ' (تسوية ذمم دائنة)'
            )
        );

        IF v_total_realized_loss > 0 THEN
            v_je_lines := v_je_lines || jsonb_build_array(
                jsonb_build_object(
                    'account_id', v_realized_loss_acct,
                    'debit', v_total_realized_loss,
                    'credit', 0,
                    'base_debit', v_total_realized_loss,
                    'base_credit', 0,
                    'currency', 'EGP',
                    'description', 'خسائر فروق أسعار عملة محققة - ' || v_entity_name
                )
            );
        END IF;

        v_je_lines := v_je_lines || jsonb_build_array(
            jsonb_build_object(
                'account_id', v_source_acct,
                'debit', 0,
                'credit', p_amount,
                'base_debit', 0,
                'base_credit', v_total_cash_base,
                'currency', p_currency,
                'description', v_desc || ' (صرف من ' || v_source_name || ')'
            )
        );

        IF v_total_realized_gain > 0 THEN
            v_je_lines := v_je_lines || jsonb_build_array(
                jsonb_build_object(
                    'account_id', v_realized_gain_acct,
                    'debit', 0,
                    'credit', v_total_realized_gain,
                    'base_debit', 0,
                    'base_credit', v_total_realized_gain,
                    'currency', 'EGP',
                    'description', 'أرباح فروق أسعار عملة محققة - ' || v_entity_name
                )
            );
        END IF;

        v_je_id := public.post_journal_entry(
            v_norm_entity_type || '_payment',
            v_desc,
            CURRENT_DATE,
            v_company_id,
            auth.uid(),
            v_je_lines,
            p_entity_id
        );

        IF p_source_type = 'treasury' THEN
            UPDATE public.treasury_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;
        ELSIF p_source_type = 'bank' THEN
            UPDATE public.bank_account_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;
        END IF;
    ELSE
        v_je_id := v_initial_je_id;
    END IF;

    -- 9. Synchronize true balances immediately (both outstanding_balance and current_balances_by_currency)
    IF v_norm_entity_type = 'supplier' THEN
        PERFORM public.sync_supplier_balances(v_supplier_uuid);
    ELSIF v_norm_entity_type = 'shipping_company' THEN
        UPDATE public.shipping_companies
        SET balance = (SELECT true_balance FROM public.get_shipping_company_true_balances() WHERE shipping_company_id = p_entity_id::bigint)
        WHERE id = p_entity_id::bigint;
    ELSIF v_norm_entity_type = 'clearing_agent' THEN
        UPDATE public.clearing_agents
        SET balance = (SELECT true_balance FROM public.get_clearing_agent_true_balances() WHERE clearing_agent_id = p_entity_id::bigint)
        WHERE id = p_entity_id::bigint;
    ELSIF v_norm_entity_type IN ('transport_supplier', 'transport') THEN
        UPDATE public.transport_suppliers
        SET current_balance = COALESCE(current_balance, 0) - p_amount,
            balance = COALESCE(balance, 0) - p_amount,
            updated_at = NOW()
        WHERE id = p_entity_id::bigint;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'transaction_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'amount_paid', p_amount,
        'currency', p_currency,
        'opening_balance_allocated', v_opening_alloc,
        'invoices_allocated_count', v_invoices_allocated_count,
        'advance_allocated', v_advance_alloc
    );
END;
$$;

-- 4. Initial one-time sync for all suppliers in the system
DO $$
DECLARE
  sup_rec RECORD;
BEGIN
  FOR sup_rec IN SELECT id FROM public.suppliers LOOP
    PERFORM public.sync_supplier_balances(sup_rec.id);
  END LOOP;
END;
$$;
