-- ============================================================================
-- Migration 383: Include Crop Purchase Lots in Multi-Payment & Unpaid Liabilities
-- ============================================================================
-- 1. Adds payment tracking columns to lot_receipts and foreign key to supplier_payment_allocations.
-- 2. Updates vw_unpaid_liabilities to include confirmed crop purchases (lot_receipts).
-- 3. Updates rpc_entity_multi_payment to allocate payments to lot_receipts,
--    track book rates, deduct lot dues, and calculate realized FX gain/loss (IAS 21).
-- ============================================================================

BEGIN;

-- 1. Ensure columns exist on lot_receipts
ALTER TABLE public.lot_receipts 
ADD COLUMN IF NOT EXISTS paid_amount NUMERIC(15,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'unpaid',
ADD COLUMN IF NOT EXISTS payment_treasury_id TEXT,
ADD COLUMN IF NOT EXISTS payment_bank_account_id INTEGER,
ADD COLUMN IF NOT EXISTS payment_source_type TEXT;

-- 2. Ensure foreign key exists on supplier_payment_allocations
ALTER TABLE public.supplier_payment_allocations 
ADD COLUMN IF NOT EXISTS lot_receipt_id BIGINT REFERENCES public.lot_receipts(id) ON DELETE SET NULL;

-- 3. Ensure columns exist on packing and shipment cost items
ALTER TABLE public.packing_order_cost_items 
ADD COLUMN IF NOT EXISTS paid_amount NUMERIC(15,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'unpaid',
ADD COLUMN IF NOT EXISTS payment_treasury_id TEXT,
ADD COLUMN IF NOT EXISTS payment_bank_account_id INTEGER,
ADD COLUMN IF NOT EXISTS payment_source_type TEXT;

ALTER TABLE public.shipment_cost_items 
ADD COLUMN IF NOT EXISTS paid_amount NUMERIC(15,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'unpaid',
ADD COLUMN IF NOT EXISTS payment_treasury_id TEXT,
ADD COLUMN IF NOT EXISTS payment_bank_account_id INTEGER,
ADD COLUMN IF NOT EXISTS payment_source_type TEXT;

-- 4. Drop and Recreate Unified View for Unpaid Liabilities (including Lot Receipts)
DROP VIEW IF EXISTS public.vw_unpaid_liabilities CASCADE;

CREATE OR REPLACE VIEW public.vw_unpaid_liabilities AS
-- 1. Purchase Invoices (مشتريات خامات)
SELECT 
    'purchase_invoice'::text as liability_type,
    id::bigint as liability_id,
    invoice_number as reference_number,
    'supplier'::text as entity_type,
    supplier_id::text as entity_id,
    currency,
    jsonb_build_object('exchange_rate', COALESCE((currency_snapshot->>'exchange_rate')::numeric, 1.0)) as currency_snapshot,
    (total_amount - discount_amount - COALESCE(paid_amount, 0)) as due_amount,
    invoice_date as liability_date
FROM public.purchase_invoices
WHERE payment_status IN ('unpaid', 'partial')
  AND (total_amount - discount_amount - COALESCE(paid_amount, 0)) > 0.001

UNION ALL

-- 2. Crop Purchases / Lot Receipts (مشتريات محاصيل)
SELECT 
    'lot_receipt'::text as liability_type,
    id::bigint as liability_id,
    COALESCE(lot_number, 'لوت #' || id::text) as reference_number,
    'supplier'::text as entity_type,
    supplier_id::text as entity_id,
    COALESCE(currency, 'EGP') as currency,
    jsonb_build_object('exchange_rate', COALESCE(exchange_rate, 1.0)) as currency_snapshot,
    (COALESCE(total_fruit_cost, 0) - COALESCE(paid_amount, 0)) as due_amount,
    receipt_date as liability_date
FROM public.lot_receipts
WHERE is_confirmed = true
  AND (COALESCE(total_fruit_cost, 0) - COALESCE(paid_amount, 0)) > 0.001
  AND supplier_id IS NOT NULL

UNION ALL

-- 3. Packing Order Cost Items (تكاليف تعبئة)
SELECT 
    'packing_cost_item'::text as liability_type,
    id::bigint as liability_id,
    COALESCE(name, 'تكلفة تعبئة') as reference_number,
    'supplier'::text as entity_type,
    supplier_id as entity_id,
    COALESCE(NULLIF(original_currency, ''), 'EGP') as currency,
    jsonb_build_object('exchange_rate', COALESCE(exchange_rate, 1.0)) as currency_snapshot,
    (COALESCE(original_amount, 0) - COALESCE(paid_amount, 0)) as due_amount,
    created_at::date as liability_date
FROM public.packing_order_cost_items
WHERE supplier_id IS NOT NULL 
  AND supplier_id != '' 
  AND payment_source_type IN (NULL, 'none') 
  AND treasury_transaction_id IS NULL 
  AND bank_transaction_id IS NULL
  AND payment_status IN ('unpaid', 'partial')
  AND (COALESCE(original_amount, 0) - COALESCE(paid_amount, 0)) > 0.001

UNION ALL

-- 4. Shipment Cost Items (تكاليف شحن، تخليص، وبنود تكلفة موردين من صفحة الربحية)
SELECT 
    'shipment_cost_item'::text as liability_type,
    id::bigint as liability_id,
    COALESCE(description, 'تكلفة شحن/تخليص') as reference_number,
    CASE 
        WHEN shipping_company_id IS NOT NULL THEN 'shipping_company'
        WHEN clearing_agent_id IS NOT NULL THEN 'clearing_agent'
        WHEN supplier_id IS NOT NULL AND supplier_id != '' THEN 'supplier'
        ELSE LOWER(COALESCE(vendor_type, 'supplier'))
    END as entity_type,
    CASE 
        WHEN shipping_company_id IS NOT NULL THEN shipping_company_id::text
        WHEN clearing_agent_id IS NOT NULL THEN clearing_agent_id::text
        WHEN supplier_id IS NOT NULL AND supplier_id != '' THEN supplier_id
        ELSE vendor_id::text
    END as entity_id,
    COALESCE(NULLIF(original_currency, ''), NULLIF(supplier_currency, ''), 'EGP') as currency,
    jsonb_build_object('exchange_rate', COALESCE(exchange_rate, 1.0)) as currency_snapshot,
    (COALESCE(NULLIF(total_price, 0), quantity * unit_price, 0) - COALESCE(paid_amount, 0)) as due_amount,
    created_at::date as liability_date
FROM public.shipment_cost_items
WHERE treasury_transaction_id IS NULL 
  AND bank_transaction_id IS NULL
  AND payment_source_type IN (NULL, 'none')
  AND payment_status IN ('unpaid', 'partial')
  AND (COALESCE(NULLIF(total_price, 0), quantity * unit_price, 0) - COALESCE(paid_amount, 0)) > 0.001;

-- 5. Unified Entity Multi-Payment Function
CREATE OR REPLACE FUNCTION public.rpc_entity_multi_payment(
    p_source_type text,
    p_source_id bigint,
    p_currency text,
    p_amount numeric,
    p_entity_type text,
    p_entity_id text,
    p_description text,
    p_expense_account_id integer DEFAULT NULL::integer,
    p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_tx_id BIGINT;
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
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'مبلغ السداد يجب أن يكون أكبر من صفر';
    END IF;

    v_norm_entity_type := LOWER(p_entity_type);

    -- 1. Fetch entity info & GL account based on normalized entity type
    IF v_norm_entity_type = 'supplier' THEN
        v_supplier_uuid := p_entity_id::uuid;
        SELECT 
            name, COALESCE(initial_balance, 0), COALESCE(initial_balance_direction, 'CREDIT'), company_id, account_id
        INTO v_entity_name, v_initial_balance, v_initial_direction, v_company_id, v_entity_acct
        FROM public.suppliers WHERE id = v_supplier_uuid;
    ELSIF v_norm_entity_type = 'shipping_company' THEN
        SELECT 
            name, COALESCE(initial_balance, 0), COALESCE(initial_balance_direction, 'CREDIT'), company_id, account_id
        INTO v_entity_name, v_initial_balance, v_initial_direction, v_company_id, v_entity_acct
        FROM public.shipping_companies WHERE id = p_entity_id::integer;
    ELSIF v_norm_entity_type = 'clearing_agent' THEN
        SELECT 
            name, COALESCE(initial_balance, 0), COALESCE(initial_balance_direction, 'CREDIT'), company_id, account_id
        INTO v_entity_name, v_initial_balance, v_initial_direction, v_company_id, v_entity_acct
        FROM public.clearing_agents WHERE id = p_entity_id::integer;
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
        END IF;
    END IF;

    -- 2. Resolve Source Book Rate and GL Account
    IF p_source_type = 'treasury' THEN
        SELECT COALESCE(NULLIF(book_rate, 0), public.fn_get_exchange_rate(p_currency))
        INTO v_book_rate
        FROM public.treasury_balances
        WHERE treasury_id::text = p_source_id::text AND currency = p_currency;

        SELECT name INTO v_source_name FROM public.treasuries WHERE id = p_source_id;
        v_source_acct := public.resolve_treasury_account(p_source_id::integer, p_currency, v_company_id);
    ELSIF p_source_type = 'bank' THEN
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
        v_tx_id := public.withdraw_treasury(
            p_treasury_id := p_source_id::integer,
            p_currency := p_currency,
            p_amount := p_amount,
            p_description := COALESCE(NULLIF(p_description, ''), 'سداد مديونيات متعددة: ' || v_entity_name),
            p_customer_id := NULL,
            p_supplier_id := CASE WHEN v_norm_entity_type = 'supplier' THEN v_supplier_uuid END,
            p_clearing_agent_id := CASE WHEN v_norm_entity_type = 'clearing_agent' THEN p_entity_id::bigint END,
            p_shipping_company_id := CASE WHEN v_norm_entity_type = 'shipping_company' THEN p_entity_id::bigint END,
            p_expense_account_id := p_expense_account_id,
            p_notes := p_notes
        );
    ELSIF p_source_type = 'bank' THEN
        v_tx_id := public.withdraw_bank_account(
            p_bank_account_id := p_source_id::integer,
            p_amount := p_amount,
            p_description := COALESCE(NULLIF(p_description, ''), 'سداد مديونيات متعددة: ' || v_entity_name),
            p_customer_id := NULL,
            p_supplier_id := CASE WHEN v_norm_entity_type = 'supplier' THEN v_supplier_uuid END,
            p_clearing_agent_id := CASE WHEN v_norm_entity_type = 'clearing_agent' THEN p_entity_id::bigint END,
            p_shipping_company_id := CASE WHEN v_norm_entity_type = 'shipping_company' THEN p_entity_id::bigint END,
            p_expense_account_id := p_expense_account_id,
            p_notes := p_notes
        );
    END IF;

    -- 4. Calculate Remaining Opening Balance to Allocate
    IF v_norm_entity_type = 'supplier' AND v_initial_balance > 0 AND UPPER(v_initial_direction) = 'CREDIT' THEN
        SELECT COALESCE(SUM(amount), 0) INTO v_opening_paid
        FROM public.supplier_payment_allocations
        WHERE supplier_id = v_supplier_uuid AND allocation_type = 'opening_balance';

        v_opening_remaining := GREATEST(0, v_initial_balance - v_opening_paid);
    ELSIF v_norm_entity_type IN ('shipping_company', 'clearing_agent') AND v_initial_balance > 0 AND UPPER(v_initial_direction) = 'CREDIT' THEN
        v_opening_remaining := v_initial_balance;
    ELSE
        v_opening_remaining := 0;
    END IF;

    -- 5. Allocation Priority 1: Opening Balance
    IF v_opening_remaining > 0 AND v_remaining_to_allocate > 0 THEN
        IF v_remaining_to_allocate >= v_opening_remaining THEN
            v_opening_alloc := v_opening_remaining;
        ELSE
            v_opening_alloc := v_remaining_to_allocate;
        END IF;

        IF v_norm_entity_type = 'supplier' THEN
            INSERT INTO public.supplier_payment_allocations (
                source_type, source_id, purchase_invoice_id, supplier_id, allocation_type, amount
            ) VALUES (
                p_source_type, v_tx_id, NULL, v_supplier_uuid, 'opening_balance', v_opening_alloc
            );
        END IF;

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

        IF v_remaining_to_allocate >= v_liab.due_amount THEN
            v_allocation_amount := v_liab.due_amount;
        ELSE
            v_allocation_amount := v_remaining_to_allocate;
        END IF;

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
            IF v_norm_entity_type = 'supplier' THEN
                INSERT INTO public.supplier_payment_allocations (
                    source_type, source_id, purchase_invoice_id, supplier_id, allocation_type, amount
                ) VALUES (
                    p_source_type, v_tx_id, v_liab.liability_id, v_supplier_uuid, 'invoice', v_allocation_amount
                );
            END IF;
            UPDATE public.purchase_invoices
            SET paid_amount = paid_amount + v_allocation_amount,
                payment_status = CASE WHEN (paid_amount + v_allocation_amount) >= (total_amount - discount_amount) THEN 'paid' ELSE 'partial' END,
                payment_treasury_id = CASE WHEN p_source_type = 'treasury' THEN p_source_id::text END,
                payment_bank_account_id = CASE WHEN p_source_type = 'bank' THEN p_source_id::integer END,
                payment_source_type = p_source_type
            WHERE id = v_liab.liability_id;
            
        ELSIF v_liab.liability_type = 'lot_receipt' THEN
            IF v_norm_entity_type = 'supplier' THEN
                INSERT INTO public.supplier_payment_allocations (
                    source_type, source_id, lot_receipt_id, supplier_id, allocation_type, amount
                ) VALUES (
                    p_source_type, v_tx_id, v_liab.liability_id, v_supplier_uuid, 'lot_receipt', v_allocation_amount
                );
            END IF;
            UPDATE public.lot_receipts
            SET paid_amount = COALESCE(paid_amount, 0) + v_allocation_amount,
                payment_status = CASE WHEN (COALESCE(paid_amount, 0) + v_allocation_amount) >= COALESCE(total_fruit_cost, 0) THEN 'paid' ELSE 'partial' END,
                payment_treasury_id = CASE WHEN p_source_type = 'treasury' THEN p_source_id::text END,
                payment_bank_account_id = CASE WHEN p_source_type = 'bank' THEN p_source_id::integer END,
                payment_source_type = p_source_type,
                updated_at = NOW()
            WHERE id = v_liab.liability_id;
            
        ELSIF v_liab.liability_type = 'packing_cost_item' THEN
            IF v_norm_entity_type = 'supplier' THEN
                INSERT INTO public.supplier_payment_allocations (
                    source_type, source_id, packing_order_cost_item_id, supplier_id, allocation_type, amount
                ) VALUES (
                    p_source_type, v_tx_id, v_liab.liability_id, v_supplier_uuid, 'packing_cost', v_allocation_amount
                );
            END IF;
            UPDATE public.packing_order_cost_items
            SET paid_amount = COALESCE(paid_amount, 0) + v_allocation_amount,
                payment_status = CASE WHEN (COALESCE(paid_amount, 0) + v_allocation_amount) >= COALESCE(original_amount, 0) THEN 'paid' ELSE 'partial' END,
                payment_treasury_id = CASE WHEN p_source_type = 'treasury' THEN p_source_id::text END,
                payment_bank_account_id = CASE WHEN p_source_type = 'bank' THEN p_source_id::integer END,
                payment_source_type = p_source_type
            WHERE id = v_liab.liability_id;
            
        ELSIF v_liab.liability_type = 'shipment_cost_item' THEN
            IF v_norm_entity_type = 'supplier' THEN
                INSERT INTO public.supplier_payment_allocations (
                    source_type, source_id, shipment_cost_item_id, supplier_id, allocation_type, amount
                ) VALUES (
                    p_source_type, v_tx_id, v_liab.liability_id, v_supplier_uuid, 'shipment_cost', v_allocation_amount
                );
            END IF;
            UPDATE public.shipment_cost_items
            SET paid_amount = COALESCE(paid_amount, 0) + v_allocation_amount,
                payment_status = CASE WHEN (COALESCE(paid_amount, 0) + v_allocation_amount) >= COALESCE(NULLIF(total_price, 0), quantity * unit_price, 0) THEN 'paid' ELSE 'partial' END,
                payment_treasury_id = CASE WHEN p_source_type = 'treasury' THEN p_source_id::text END,
                payment_bank_account_id = CASE WHEN p_source_type = 'bank' THEN p_source_id::integer END,
                payment_source_type = p_source_type
            WHERE id = v_liab.liability_id;
        END IF;

        v_invoices_allocated_count := v_invoices_allocated_count + 1;
        v_remaining_to_allocate := v_remaining_to_allocate - v_allocation_amount;
    END LOOP;

    -- 7. Allocation Priority 3: Advance Payment / Credit Balance
    IF v_remaining_to_allocate > 0 THEN
        v_advance_alloc := v_remaining_to_allocate;
        IF v_norm_entity_type = 'supplier' THEN
            INSERT INTO public.supplier_payment_allocations (
                source_type, source_id, supplier_id, allocation_type, amount
            ) VALUES (
                p_source_type, v_tx_id, v_supplier_uuid, 'advance', v_advance_alloc
            );
        END IF;
        v_total_ap_base := v_total_ap_base + ROUND(v_advance_alloc * v_book_rate, 2);
    END IF;

    -- 8. Post / Adjust GL Journal Entry for Realized FX Differences
    IF v_total_realized_gain > 0 OR v_total_realized_loss > 0 THEN
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
        IF p_source_type = 'treasury' THEN
            SELECT journal_entry_id INTO v_je_id FROM public.treasury_transactions WHERE id = v_tx_id;
        ELSIF p_source_type = 'bank' THEN
            SELECT journal_entry_id INTO v_je_id FROM public.bank_account_transactions WHERE id = v_tx_id;
        END IF;
    END IF;

    -- 9. Recalculate & update outstanding_balance
    IF v_norm_entity_type = 'supplier' THEN
        UPDATE public.suppliers
        SET outstanding_balance = (SELECT true_balance FROM public.get_supplier_true_balances() WHERE supplier_id = v_supplier_uuid)
        WHERE id = v_supplier_uuid;
    ELSIF v_norm_entity_type = 'shipping_company' THEN
        UPDATE public.shipping_companies
        SET balance = balance - p_amount
        WHERE id = p_entity_id::integer;
    ELSIF v_norm_entity_type = 'clearing_agent' THEN
        UPDATE public.clearing_agents
        SET balance = balance - p_amount
        WHERE id = p_entity_id::integer;
    END IF;

    RETURN jsonb_build_object(
        'transaction_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'opening_balance_allocated', v_opening_alloc,
        'liabilities_allocated_count', v_invoices_allocated_count,
        'liabilities_allocated_amount', p_amount - v_opening_alloc - v_advance_alloc,
        'advance_amount', v_advance_alloc,
        'realized_fx_gain', v_total_realized_gain,
        'realized_fx_loss', v_total_realized_loss
    );
END;
$$;

-- Replace old wrapper
CREATE OR REPLACE FUNCTION public.rpc_supplier_multi_payment(
    p_source_type text,
    p_source_id bigint,
    p_currency text,
    p_amount numeric,
    p_supplier_id uuid,
    p_description text,
    p_expense_account_id integer DEFAULT NULL::integer,
    p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN public.rpc_entity_multi_payment(
        p_source_type, p_source_id, p_currency, p_amount, 'supplier', p_supplier_id::text, p_description, p_expense_account_id, p_notes
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_entity_multi_payment(text, bigint, text, numeric, text, text, text, integer, text) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.rpc_supplier_multi_payment(text, bigint, text, numeric, uuid, text, integer, text) TO authenticated, anon, service_role;
GRANT SELECT ON public.vw_unpaid_liabilities TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload_schema';

COMMIT;
