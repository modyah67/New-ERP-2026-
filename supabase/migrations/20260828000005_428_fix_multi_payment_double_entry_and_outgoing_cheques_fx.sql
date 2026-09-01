-- ==============================================================================
-- Migration: 20260828000005_428_fix_multi_payment_double_entry_and_outgoing_cheques_fx.sql
-- Description:
-- 1. Fix rpc_entity_multi_payment to eliminate duplicate journal entries (delete initial JE
--    before posting the comprehensive multi-payment JE with realized FX).
-- 2. Upgrade clear_cheque for outgoing cheques to suppliers, shipping companies,
--    and clearing agents to allocate unpaid liabilities and calculate Realized FX (IAS 21).
-- 3. Cleanup existing orphaned duplicate journal entries from previous multi-payments.
-- ==============================================================================

-- ── 0. Fix vw_unpaid_liabilities for partial payments & shipment cost items ──
DROP VIEW IF EXISTS public.vw_unpaid_liabilities CASCADE;

CREATE OR REPLACE VIEW public.vw_unpaid_liabilities AS
-- 1. Purchase Invoices (مشتريات خامات)
SELECT 
    'purchase_invoice'::text AS liability_type,
    purchase_invoices.id::text AS liability_id,
    purchase_invoices.invoice_number AS reference_number,
    'supplier'::text AS entity_type,
    purchase_invoices.supplier_id::text AS entity_id,
    purchase_invoices.currency,
    jsonb_build_object('exchange_rate', COALESCE((purchase_invoices.currency_snapshot ->> 'exchange_rate'::text)::numeric, 1.0)) AS currency_snapshot,
    (purchase_invoices.total_amount - purchase_invoices.discount_amount - COALESCE(purchase_invoices.paid_amount, 0::numeric))::double precision AS due_amount,
    purchase_invoices.invoice_date AS liability_date
FROM public.purchase_invoices
WHERE (purchase_invoices.payment_status IS NULL OR (purchase_invoices.payment_status = ANY (ARRAY['unpaid'::text, 'partial'::text]))) 
  AND (purchase_invoices.total_amount - purchase_invoices.discount_amount - COALESCE(purchase_invoices.paid_amount, 0::numeric)) > 0.001

UNION ALL

-- 2. Crop Purchases / Lot Receipts (مشتريات محاصيل)
SELECT 
    'lot_receipt'::text AS liability_type,
    lot_receipts.id::text AS liability_id,
    COALESCE(lot_receipts.lot_number, 'لوت #'::text || lot_receipts.id::text) AS reference_number,
    'supplier'::text AS entity_type,
    lot_receipts.supplier_id::text AS entity_id,
    COALESCE(lot_receipts.currency, 'EGP'::text) AS currency,
    jsonb_build_object('exchange_rate', COALESCE(lot_receipts.exchange_rate, 1.0)) AS currency_snapshot,
    (COALESCE(lot_receipts.total_fruit_cost, 0::double precision) - COALESCE(lot_receipts.paid_amount, 0::double precision)) AS due_amount,
    lot_receipts.receipt_date AS liability_date
FROM public.lot_receipts
WHERE lot_receipts.is_confirmed = true 
  AND lot_receipts.supplier_id IS NOT NULL 
  AND (lot_receipts.payment_status IS NULL OR (lot_receipts.payment_status = ANY (ARRAY['unpaid'::text, 'partial'::text]))) 
  AND (COALESCE(lot_receipts.total_fruit_cost, 0::double precision) - COALESCE(lot_receipts.paid_amount, 0::double precision)) > 0.001::double precision

UNION ALL

-- 3. Packing Order Cost Items (تكاليف تعبئة)
SELECT 
    'packing_cost_item'::text AS liability_type,
    packing_order_cost_items.id::text AS liability_id,
    COALESCE(packing_order_cost_items.name, 'تكلفة تعبئة'::text) AS reference_number,
    'supplier'::text AS entity_type,
    COALESCE(NULLIF(packing_order_cost_items.supplier_id, ''), packing_order_cost_items.currency_snapshot->>'supplier_id') AS entity_id,
    COALESCE(NULLIF(packing_order_cost_items.original_currency, ''::text), 'EGP'::text) AS currency,
    jsonb_build_object('exchange_rate', COALESCE(packing_order_cost_items.exchange_rate, 1.0)) AS currency_snapshot,
    (COALESCE(packing_order_cost_items.original_amount, 0::numeric) - COALESCE(packing_order_cost_items.paid_amount, 0::numeric))::double precision AS due_amount,
    packing_order_cost_items.created_at::date AS liability_date
FROM public.packing_order_cost_items
WHERE (
    (packing_order_cost_items.supplier_id IS NOT NULL AND packing_order_cost_items.supplier_id <> ''::text AND packing_order_cost_items.supplier_id <> 'null'::text)
    OR
    (packing_order_cost_items.currency_snapshot->>'supplier_id' IS NOT NULL AND packing_order_cost_items.currency_snapshot->>'supplier_id' <> ''::text AND packing_order_cost_items.currency_snapshot->>'supplier_id' <> 'null'::text)
  )
  AND (packing_order_cost_items.payment_status IS NULL OR (packing_order_cost_items.payment_status = ANY (ARRAY['unpaid'::text, 'partial'::text]))) 
  AND (COALESCE(packing_order_cost_items.original_amount, 0::numeric) - COALESCE(packing_order_cost_items.paid_amount, 0::numeric)) > 0.001

UNION ALL

-- 4. Shipment Cost Items (تكاليف شحن، تخليص، وبنود تكلفة موردين من صفحة الربحية)
SELECT 
    'shipment_cost_item'::text AS liability_type,
    shipment_cost_items.id::text AS liability_id,
    COALESCE((export_shipments.shipment_no::text || ' - '::text) || shipment_cost_items.description, shipment_cost_items.description, 'تكلفة شحن/تخليص'::text) AS reference_number,
    CASE
        WHEN shipment_cost_items.shipping_company_id IS NOT NULL THEN 'shipping_company'::text
        WHEN shipment_cost_items.clearing_agent_id IS NOT NULL THEN 'clearing_agent'::text
        WHEN shipment_cost_items.supplier_id IS NOT NULL AND shipment_cost_items.supplier_id <> ''::text THEN 'supplier'::text
        ELSE lower(COALESCE(shipment_cost_items.vendor_type, 'supplier'::text))
    END AS entity_type,
    CASE
        WHEN shipment_cost_items.shipping_company_id IS NOT NULL THEN shipment_cost_items.shipping_company_id::text
        WHEN shipment_cost_items.clearing_agent_id IS NOT NULL THEN shipment_cost_items.clearing_agent_id::text
        WHEN shipment_cost_items.supplier_id IS NOT NULL AND shipment_cost_items.supplier_id <> ''::text THEN shipment_cost_items.supplier_id
        ELSE shipment_cost_items.vendor_id::text
    END AS entity_id,
    COALESCE(NULLIF(shipment_cost_items.original_currency, ''::text), NULLIF(shipment_cost_items.supplier_currency, ''::text), 'EGP'::text) AS currency,
    jsonb_build_object('exchange_rate', COALESCE(shipment_cost_items.exchange_rate, 1.0)) AS currency_snapshot,
    round(
        (COALESCE(NULLIF(shipment_cost_items.total_price, 0::numeric), shipment_cost_items.quantity * shipment_cost_items.unit_price, 0::numeric) / COALESCE(NULLIF(shipment_cost_items.exchange_rate, 0::numeric), 1.0))
        - COALESCE(shipment_cost_items.paid_amount, 0::numeric), 2
    )::double precision AS due_amount,
    shipment_cost_items.created_at::date AS liability_date
FROM public.shipment_cost_items
LEFT JOIN public.export_shipments ON export_shipments.id = shipment_cost_items.shipment_id
WHERE (shipment_cost_items.payment_status IS NULL OR (shipment_cost_items.payment_status = ANY (ARRAY['unpaid'::text, 'partial'::text]))) 
  AND round((COALESCE(NULLIF(shipment_cost_items.total_price, 0::numeric), shipment_cost_items.quantity * shipment_cost_items.unit_price, 0::numeric) / COALESCE(NULLIF(shipment_cost_items.exchange_rate, 0::numeric), 1.0)) - COALESCE(shipment_cost_items.paid_amount, 0::numeric), 2) > 0.001;

GRANT SELECT ON public.vw_unpaid_liabilities TO authenticated, anon, service_role;

-- ── 1. Fix rpc_entity_multi_payment ──
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
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'مبلغ السداد يجب أن يكون أكبر من صفر';
    END IF;

    v_norm_entity_type := LOWER(p_entity_type);
    v_entry_date := (NOW() AT TIME ZONE 'Africa/Cairo')::DATE;

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
            p_expense_account_id := COALESCE(p_expense_account_id, v_entity_acct::integer),
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
                    p_source_type, v_tx_id, v_liab.liability_id::integer, v_supplier_uuid, 'invoice', v_allocation_amount
                );
            END IF;
            UPDATE public.purchase_invoices
            SET paid_amount = paid_amount + v_allocation_amount,
                payment_status = CASE WHEN (paid_amount + v_allocation_amount) >= (total_amount - discount_amount) THEN 'paid' ELSE 'partial' END,
                payment_treasury_id = CASE WHEN p_source_type = 'treasury' THEN p_source_id::text END,
                payment_bank_account_id = CASE WHEN p_source_type = 'bank' THEN p_source_id::integer END,
                payment_source_type = p_source_type
            WHERE id::text = v_liab.liability_id;
            
        ELSIF v_liab.liability_type = 'lot_receipt' THEN
            IF v_norm_entity_type = 'supplier' THEN
                INSERT INTO public.supplier_payment_allocations (
                    source_type, source_id, lot_receipt_id, supplier_id, allocation_type, amount
                ) VALUES (
                    p_source_type, v_tx_id, v_liab.liability_id::bigint, v_supplier_uuid, 'lot_receipt', v_allocation_amount
                );
            END IF;
            UPDATE public.lot_receipts
            SET paid_amount = COALESCE(paid_amount, 0) + v_allocation_amount,
                payment_status = CASE WHEN (COALESCE(paid_amount, 0) + v_allocation_amount) >= COALESCE(total_fruit_cost, 0) THEN 'paid' ELSE 'partial' END,
                payment_treasury_id = CASE WHEN p_source_type = 'treasury' THEN p_source_id::text END,
                payment_bank_account_id = CASE WHEN p_source_type = 'bank' THEN p_source_id::integer END,
                payment_source_type = p_source_type,
                updated_at = NOW()
            WHERE id::text = v_liab.liability_id;
            
        ELSIF v_liab.liability_type = 'packing_cost_item' THEN
            IF v_norm_entity_type = 'supplier' THEN
                INSERT INTO public.supplier_payment_allocations (
                    source_type, source_id, packing_order_cost_item_id, supplier_id, allocation_type, amount
                ) VALUES (
                    p_source_type, v_tx_id, v_liab.liability_id::bigint, v_supplier_uuid, 'packing_cost', v_allocation_amount
                );
            END IF;
            UPDATE public.packing_order_cost_items
            SET paid_amount = paid_amount + v_allocation_amount,
                payment_status = CASE WHEN (paid_amount + v_allocation_amount) >= COALESCE(original_amount, 0) THEN 'paid' ELSE 'partial' END,
                payment_treasury_id = CASE WHEN p_source_type = 'treasury' THEN p_source_id::text END,
                payment_bank_account_id = CASE WHEN p_source_type = 'bank' THEN p_source_id::integer END,
                payment_source_type = p_source_type
            WHERE id::text = v_liab.liability_id;
            
        ELSIF v_liab.liability_type = 'shipment_cost_item' THEN
            IF v_norm_entity_type = 'supplier' THEN
                INSERT INTO public.supplier_payment_allocations (
                    source_type, source_id, shipment_cost_item_id, supplier_id, allocation_type, amount
                ) VALUES (
                    p_source_type, v_tx_id, v_liab.liability_id::bigint, v_supplier_uuid, 'shipment_cost', v_allocation_amount
                );
            END IF;
            UPDATE public.shipment_cost_items
            SET paid_amount = paid_amount + v_allocation_amount,
                payment_status = CASE WHEN (paid_amount + v_allocation_amount) >= ROUND(COALESCE(NULLIF(total_price, 0), quantity * unit_price, 0) / COALESCE(NULLIF(exchange_rate, 0), 1.0), 2) THEN 'paid' ELSE 'partial' END,
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
        -- CRITICAL: Delete initial journal entry to avoid double entry in ledger!
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

    -- 9. Recalculate & update true balance
    IF v_norm_entity_type = 'supplier' THEN
        UPDATE public.suppliers
        SET outstanding_balance = (SELECT true_balance FROM public.get_supplier_true_balances() WHERE supplier_id = v_supplier_uuid)
        WHERE id = v_supplier_uuid;
    ELSIF v_norm_entity_type = 'shipping_company' THEN
        UPDATE public.shipping_companies
        SET balance = (SELECT true_balance FROM public.get_shipping_company_true_balances() WHERE shipping_company_id = p_entity_id::bigint)
        WHERE id = p_entity_id::bigint;
    ELSIF v_norm_entity_type = 'clearing_agent' THEN
        UPDATE public.clearing_agents
        SET balance = (SELECT true_balance FROM public.get_clearing_agent_true_balances() WHERE clearing_agent_id = p_entity_id::bigint)
        WHERE id = p_entity_id::bigint;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'transaction_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'amount_paid', p_amount,
        'invoices_settled_count', v_invoices_allocated_count,
        'realized_fx_gain', v_total_realized_gain,
        'realized_fx_loss', v_total_realized_loss,
        'remaining_advance', v_advance_alloc
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_entity_multi_payment(text, bigint, text, numeric, text, text, text, integer, text) TO authenticated, service_role;

-- ── 1.4 Update treasury trigger to allow internal transfers & cheques ──
CREATE OR REPLACE FUNCTION public.fn_require_revenue_account_treasury()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    IF NEW.status = 'draft' THEN
        RETURN NEW;
    END IF;

    -- Skip revenue account check for internal transfers, cheque feedings, custody settlements, and opening balances
    IF NEW.source_type IN ('cheque', 'transfer', 'bank_transfer', 'treasury_transfer', 'opening_balance', 'custody_settlement')
       OR NEW.reference_type IN ('cheque', 'transfer', 'bank_transfer', 'custody_settlement') THEN
        RETURN NEW;
    END IF;

    IF NEW.type = 'deposit' 
       AND NEW.revenue_account_id IS NULL 
       AND NEW.customer_id IS NULL 
       AND NEW.supplier_id IS NULL 
       AND NEW.clearing_agent_id IS NULL 
       AND NEW.shipping_company_id IS NULL 
       AND NEW.shareholder_id IS NULL THEN
        RAISE EXCEPTION 'يجب اختيار حساب إيرادات من شجرة الحسابات — لا يسمح بالقيود الافتراضية';
    END IF;

    RETURN NEW;
END;
$$;

-- ── 1.5 Clean treasury deposit overloads ──
DROP FUNCTION IF EXISTS public.deposit_treasury(bigint, text, numeric, text, integer);
DROP FUNCTION IF EXISTS public.deposit_treasury(bigint, text, numeric, text, bigint);
DROP FUNCTION IF EXISTS public.deposit_treasury(integer, text, numeric, text, integer);
DROP FUNCTION IF EXISTS public.deposit_treasury(integer, text, numeric, text, integer, text, text);
DROP FUNCTION IF EXISTS public.deposit_treasury(integer, text, numeric, text, integer, text, text, text);
DROP FUNCTION IF EXISTS public.deposit_treasury(bigint, text, numeric, text, integer, text, text, text);
DROP FUNCTION IF EXISTS public.deposit_treasury(bigint, text, numeric, text, bigint, text, text, text);

CREATE OR REPLACE FUNCTION public.deposit_treasury(
    p_treasury_id bigint,
    p_currency text,
    p_amount numeric,
    p_description text DEFAULT NULL::text,
    p_revenue_account_id bigint DEFAULT NULL::bigint,
    p_reference_type text DEFAULT NULL::text,
    p_reference_id text DEFAULT NULL::text,
    p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_current_cost_base NUMERIC := 0;
    v_current_book_rate NUMERIC := 1.0;
    v_new_balance NUMERIC := 0;
    v_new_cost_base NUMERIC := 0;
    v_new_book_rate NUMERIC := 1.0;
    v_tx_id BIGINT;
    v_company_id UUID;
    v_treasury_acct BIGINT;
    v_revenue_acct BIGINT;
    v_desc TEXT;
    v_je_id BIGINT;
    v_source_type TEXT;
    v_rate NUMERIC := 1.0;
    v_base_amount NUMERIC;
    v_snapshot JSONB;
    v_entry_date DATE;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    v_entry_date := (NOW() AT TIME ZONE 'Africa/Cairo')::DATE;

    -- 1. Lock treasury balance row
    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
    INTO v_current_balance, v_current_cost_base, v_current_book_rate
    FROM public.treasury_balances
    WHERE treasury_id::TEXT = p_treasury_id::TEXT AND currency = p_currency
    FOR UPDATE;

    SELECT company_id INTO v_company_id FROM public.treasuries WHERE id = p_treasury_id;
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

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

    v_new_balance := v_current_balance + p_amount;

    IF v_new_balance > 0 AND p_currency != 'EGP' THEN
        v_new_book_rate := ROUND(v_new_cost_base / v_new_balance, 4);
    ELSIF p_currency = 'EGP' THEN
        v_new_book_rate := 1.0;
    ELSE
        v_new_book_rate := v_rate;
    END IF;

    -- 3. Resolve GL accounts
    v_source_type := CASE WHEN p_revenue_account_id IS NOT NULL THEN 'revenue' ELSE 'opening_balance' END;
    v_desc := COALESCE(NULLIF(p_description, ''), 'إيداع في الخزينة');

    v_treasury_acct := public.resolve_treasury_account(p_treasury_id::integer, p_currency, v_company_id);

    IF p_revenue_account_id IS NOT NULL THEN
        v_revenue_acct := p_revenue_account_id;
    ELSE
        v_revenue_acct := public.resolve_opening_balance_equity_account(p_currency, v_company_id);
    END IF;

    -- 4. Post Journal Entry
    v_je_id := public.post_journal_entry(
        'treasury_deposit',
        v_desc,
        v_entry_date,
        v_company_id,
        auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_treasury_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_revenue_acct,  'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', p_currency, 'description', v_desc)
        )
    );

    -- 5. Update / Upsert treasury_balances
    INSERT INTO public.treasury_balances (treasury_id, currency, balance, cost_base, book_rate, account_id, updated_at)
    VALUES (p_treasury_id, p_currency, v_new_balance, v_new_cost_base, v_new_book_rate, v_treasury_acct, NOW())
    ON CONFLICT (treasury_id, currency) DO UPDATE
    SET balance = v_new_balance,
        cost_base = v_new_cost_base,
        book_rate = v_new_book_rate,
        updated_at = NOW();

    -- 6. Insert transaction
    v_snapshot := jsonb_build_object(
        'currency', p_currency,
        'exchange_rate', v_rate,
        'book_rate', v_new_book_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'rate_date', v_entry_date,
        'rate_source', 'exchange_rates_table'
    );

    INSERT INTO public.treasury_transactions (
        treasury_id, type, currency, amount,
        balance_before, balance_after, description, source_type, journal_entry_id, created_by,
        revenue_account_id, reference_type, reference_id, notes, exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        p_treasury_id, 'deposit', p_currency, p_amount,
        v_current_balance, v_new_balance, v_desc, v_source_type, v_je_id, auth.uid(),
        CASE WHEN p_revenue_account_id IS NOT NULL THEN p_revenue_account_id ELSE NULL END,
        p_reference_type, p_reference_id, p_notes,
        v_rate, v_base_amount, v_snapshot
    ) RETURNING id INTO v_tx_id;

    RETURN jsonb_build_object(
        'success', true,
        'tx_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'new_balance', v_new_balance,
        'cost_base', v_new_cost_base,
        'book_rate', v_new_book_rate
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.deposit_treasury(bigint, text, numeric, text, bigint, text, text, text) TO authenticated, service_role;

-- ── 1.6 Clean bank deposit and withdraw overloads ──
DROP FUNCTION IF EXISTS public.deposit_bank_account(bigint, numeric, text, bigint, text, text, text, text, text);
DROP FUNCTION IF EXISTS public.deposit_bank_account(integer, numeric, text, text, text, text, text, text, text);
DROP FUNCTION IF EXISTS public.deposit_bank_account(integer, numeric, text, integer, text, text, text, text, text);
DROP FUNCTION IF EXISTS public.deposit_bank_account(bigint, numeric, text, text, text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.deposit_bank_account(
    p_account_id bigint,
    p_amount numeric,
    p_description text DEFAULT NULL::text,
    p_revenue_account_id bigint DEFAULT NULL::bigint,
    p_entity_type text DEFAULT NULL::text,
    p_entity_id text DEFAULT NULL::text,
    p_counterparty_name text DEFAULT NULL::text,
    p_source_type text DEFAULT 'deposit'::text,
    p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_current_cost_base NUMERIC := 0;
    v_current_book_rate NUMERIC := 1.0;
    v_new_balance     NUMERIC := 0;
    v_new_cost_base   NUMERIC := 0;
    v_new_book_rate   NUMERIC := 1.0;
    v_tx_id           BIGINT;
    v_currency        TEXT;
    v_company_id      UUID;
    v_bank_acct       BIGINT;
    v_credit_acct     BIGINT;
    v_realized_gain_acct BIGINT;
    v_realized_loss_acct BIGINT;
    v_desc            TEXT;
    v_je_id           BIGINT;
    v_source_type     TEXT;
    v_rate            NUMERIC := 1.0;
    v_base_amount     NUMERIC;
    v_snapshot        JSONB;
    v_entry_date      DATE;
    v_je_lines        JSONB;
    v_total_cust_base NUMERIC;
    v_total_gain      NUMERIC := 0;
    v_total_loss      NUMERIC := 0;
    v_remaining_alloc NUMERIC;
    v_alloc           NUMERIC;
    v_alloc_bank_base NUMERIC;
    v_alloc_cust_base NUMERIC;
    v_diff            NUMERIC;
    v_spec_shipment   RECORD;
    v_shipment        RECORD;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'يجب أن يكون المبلغ أكبر من صفر';
    END IF;

    v_entry_date := (NOW() AT TIME ZONE 'Africa/Cairo')::DATE;

    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0), currency, company_id
      INTO v_current_balance, v_current_cost_base, v_current_book_rate, v_currency, v_company_id
    FROM public.bank_accounts WHERE id = p_account_id
    FOR UPDATE;

    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    IF v_currency = 'EGP' THEN
        v_rate := 1.0;
        v_base_amount := p_amount;
        v_new_cost_base := COALESCE(v_current_cost_base, 0) + p_amount;
        v_new_book_rate := 1.0;
    ELSE
        v_rate := public.fn_get_exchange_rate(v_currency);
        v_base_amount := ROUND(p_amount * v_rate, 2);
        v_new_cost_base := COALESCE(v_current_cost_base, 0) + v_base_amount;
    END IF;

    v_new_balance := v_current_balance + p_amount;

    IF v_new_balance > 0 AND v_currency != 'EGP' THEN
        v_new_book_rate := ROUND(v_new_cost_base / v_new_balance, 4);
    ELSIF v_currency = 'EGP' THEN
        v_new_book_rate := 1.0;
    ELSE
        v_new_book_rate := v_rate;
    END IF;

    IF p_entity_type IS NULL THEN
        v_source_type := 'opening_balance';
        v_desc := COALESCE(NULLIF(p_description, ''), 'رصيد افتتاحي');
    ELSIF p_entity_type = 'revenue' THEN
        v_source_type := 'revenue';
        v_desc := COALESCE(NULLIF(p_description, ''), 'إيراد');
    ELSE
        v_source_type := p_entity_type;
        v_desc := COALESCE(NULLIF(p_description, ''), 'إيداع بنكي');
    END IF;

    v_bank_acct := public.resolve_gl_account(
        CASE v_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );

    v_credit_acct := NULL;

    IF p_entity_type IS NULL OR p_entity_type = 'opening_balance' THEN
        v_credit_acct := public.resolve_opening_balance_equity_account(v_currency, v_company_id);
    ELSIF p_entity_type = 'revenue' THEN
        IF p_revenue_account_id IS NULL THEN
            RAISE EXCEPTION 'يجب تحديد حساب الإيرادات';
        END IF;
        v_credit_acct := p_revenue_account_id;
    ELSIF p_entity_type = 'customer' THEN
        SELECT account_id INTO v_credit_acct FROM public.customers WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'supplier' THEN
        SELECT account_id INTO v_credit_acct FROM public.suppliers WHERE id::text = p_entity_id;
    ELSIF p_entity_type = 'shareholder' THEN
        SELECT account_id INTO v_credit_acct FROM public.shareholders WHERE id::text = p_entity_id;
    ELSIF p_entity_type = 'clearing_agent' THEN
        SELECT account_id INTO v_credit_acct FROM public.clearing_agents WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'shipping_company' THEN
        SELECT account_id INTO v_credit_acct FROM public.shipping_companies WHERE id = p_entity_id::bigint;
    ELSE
        v_credit_acct := public.resolve_opening_balance_equity_account(v_currency, v_company_id);
    END IF;

    IF v_credit_acct IS NULL THEN
        v_credit_acct := public.resolve_opening_balance_equity_account(v_currency, v_company_id);
    END IF;

    v_total_cust_base := v_base_amount;
    v_total_gain := 0;
    v_total_loss := 0;

    IF p_entity_type = 'customer' AND v_currency != 'EGP' AND p_entity_id IS NOT NULL THEN
        v_remaining_alloc := p_amount;
        v_total_cust_base := 0;

        SELECT id, shipment_no, COALESCE(exchange_rate, v_rate) as shipment_rate,
               (total_revenue_foreign - COALESCE(discount_amount, 0) - COALESCE(paid_amount, 0)) as due_foreign
        INTO v_spec_shipment
        FROM public.export_shipments
        WHERE customer_id = p_entity_id::bigint
          AND is_confirmed = true
          AND status != 'cancelled'
          AND (
              (p_description IS NOT NULL AND p_description LIKE '%' || shipment_no || '%')
              OR (p_notes IS NOT NULL AND p_notes LIKE '%' || shipment_no || '%')
          )
        ORDER BY id DESC
        LIMIT 1;

        IF v_spec_shipment.id IS NOT NULL AND v_spec_shipment.due_foreign > 0.001 THEN
            v_alloc := LEAST(v_remaining_alloc, v_spec_shipment.due_foreign);
            v_alloc_bank_base := ROUND(v_alloc * v_rate, 2);
            v_alloc_cust_base := ROUND(v_alloc * v_spec_shipment.shipment_rate, 2);
            v_diff := v_alloc_bank_base - v_alloc_cust_base;

            v_total_cust_base := v_total_cust_base + v_alloc_cust_base;

            IF v_diff > 0 THEN
                v_total_gain := v_total_gain + v_diff;
            ELSIF v_diff < 0 THEN
                v_total_loss := v_total_loss + ABS(v_diff);
            END IF;

            UPDATE public.export_shipments
            SET paid_amount = COALESCE(paid_amount, 0) + v_alloc,
                updated_at = NOW()
            WHERE id = v_spec_shipment.id;

            v_remaining_alloc := v_remaining_alloc - v_alloc;
        END IF;

        IF v_remaining_alloc > 0.001 THEN
            FOR v_shipment IN
                SELECT id, shipment_no, COALESCE(exchange_rate, v_rate) as shipment_rate,
                       (total_revenue_foreign - COALESCE(discount_amount, 0) - COALESCE(paid_amount, 0)) as due_foreign
                FROM public.export_shipments
                WHERE customer_id = p_entity_id::bigint
                  AND is_confirmed = true
                  AND status != 'cancelled'
                  AND (v_spec_shipment.id IS NULL OR id != v_spec_shipment.id)
                  AND (total_revenue_foreign - COALESCE(discount_amount, 0) - COALESCE(paid_amount, 0)) > 0.001
                ORDER BY created_at ASC, id ASC
            LOOP
                EXIT WHEN v_remaining_alloc <= 0.001;

                v_alloc := LEAST(v_remaining_alloc, v_shipment.due_foreign);
                v_alloc_bank_base := ROUND(v_alloc * v_rate, 2);
                v_alloc_cust_base := ROUND(v_alloc * v_shipment.shipment_rate, 2);
                v_diff := v_alloc_bank_base - v_alloc_cust_base;

                v_total_cust_base := v_total_cust_base + v_alloc_cust_base;

                IF v_diff > 0 THEN
                    v_total_gain := v_total_gain + v_diff;
                ELSIF v_diff < 0 THEN
                    v_total_loss := v_total_loss + ABS(v_diff);
                END IF;

                UPDATE public.export_shipments
                SET paid_amount = COALESCE(paid_amount, 0) + v_alloc,
                    updated_at = NOW()
                WHERE id = v_shipment.id;

                v_remaining_alloc := v_remaining_alloc - v_alloc;
            END LOOP;
        END IF;

        IF v_remaining_alloc > 0.001 THEN
            v_total_cust_base := v_total_cust_base + ROUND(v_remaining_alloc * v_rate, 2);
        END IF;
    END IF;

    v_je_lines := jsonb_build_array(
        jsonb_build_object('account_id', v_bank_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', v_currency, 'description', v_desc)
    );

    IF v_total_loss > 0 THEN
        v_realized_loss_acct := public.resolve_realized_fx_loss_account(v_company_id);
        v_je_lines := v_je_lines || jsonb_build_array(
            jsonb_build_object(
                'account_id', v_realized_loss_acct,
                'debit', v_total_loss,
                'credit', 0,
                'base_debit', v_total_loss,
                'base_credit', 0,
                'currency', 'EGP',
                'description', 'خسائر فروق أسعار عملة محققة - عميل ' || COALESCE(p_counterparty_name, '')
            )
        );
    END IF;

    v_je_lines := v_je_lines || jsonb_build_array(
        jsonb_build_object('account_id', v_credit_acct, 'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_total_cust_base, 'currency', v_currency, 'description', v_desc)
    );

    IF v_total_gain > 0 THEN
        v_realized_gain_acct := public.resolve_realized_fx_gain_account(v_company_id);
        v_je_lines := v_je_lines || jsonb_build_array(
            jsonb_build_object(
                'account_id', v_realized_gain_acct,
                'debit', 0,
                'credit', v_total_gain,
                'base_debit', 0,
                'base_credit', v_total_gain,
                'currency', 'EGP',
                'description', 'أرباح فروق أسعار عملة محققة - عميل ' || COALESCE(p_counterparty_name, '')
            )
        );
    END IF;

    v_je_id := public.post_journal_entry(
        'bank_deposit',
        v_desc, v_entry_date, v_company_id, auth.uid(),
        v_je_lines
    );

    UPDATE public.bank_accounts 
    SET balance = v_new_balance,
        cost_base = v_new_cost_base,
        book_rate = v_new_book_rate,
        updated_at = NOW()
    WHERE id = p_account_id;

    v_snapshot := jsonb_build_object(
        'currency', v_currency,
        'exchange_rate', v_rate,
        'book_rate', v_new_book_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'rate_date', v_entry_date,
        'rate_source', 'exchange_rates_table',
        'realized_fx_gain', v_total_gain,
        'realized_fx_loss', v_total_loss
    );

    INSERT INTO public.bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, created_by, entity_type, entity_id, counterparty_name,
        source_type, journal_entry_id, revenue_account_id, notes,
        exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        p_account_id, 'deposit', p_amount, v_current_balance, v_new_balance,
        v_desc, auth.uid(), p_entity_type, p_entity_id, p_counterparty_name,
        v_source_type, v_je_id,
        CASE WHEN p_entity_type = 'revenue' THEN p_revenue_account_id ELSE NULL END,
        p_notes,
        v_rate, v_base_amount, v_snapshot
    ) RETURNING id INTO v_tx_id;

    IF p_entity_type = 'customer' AND p_entity_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance - p_amount WHERE id = p_entity_id::bigint;

        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_id, reference_text, description, created_by
        ) VALUES (
            'customer', p_entity_id::text, 'credit', p_amount, v_currency,
            'payment', v_tx_id, v_desc, v_desc, auth.uid()
        );
    ELSIF p_entity_type = 'supplier' AND p_entity_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance + p_amount WHERE id::text = p_entity_id;

        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_id, reference_text, description, created_by
        ) VALUES (
            'supplier', p_entity_id::text, 'debit', p_amount, v_currency,
            'payment', v_tx_id, v_desc, v_desc, auth.uid()
        );
    ELSIF p_entity_type = 'clearing_agent' AND p_entity_id IS NOT NULL THEN
        UPDATE public.clearing_agents SET manual_adjustment = manual_adjustment + p_amount, balance = balance + p_amount WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'shipping_company' AND p_entity_id IS NOT NULL THEN
        UPDATE public.shipping_companies SET manual_adjustment = manual_adjustment + p_amount, balance = balance + p_amount WHERE id = p_entity_id::bigint;
    ELSIF p_entity_type = 'shareholder' AND p_entity_id IS NOT NULL THEN
        IF v_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur + p_amount WHERE id = p_entity_id::uuid;
        ELSIF v_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp + p_amount WHERE id = p_entity_id::uuid;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'tx_id', v_tx_id,
        'new_balance', v_new_balance,
        'cost_base', v_new_cost_base,
        'book_rate', v_new_book_rate,
        'journal_entry_id', v_je_id,
        'realized_fx_gain', v_total_gain,
        'realized_fx_loss', v_total_loss
    );
END;
$$;

DROP FUNCTION IF EXISTS public.withdraw_bank_account(bigint, numeric, text, bigint, text, text, text, text, text, text);
DROP FUNCTION IF EXISTS public.withdraw_bank_account(integer, numeric, text, text, text, text, integer, text, text, text);
DROP FUNCTION IF EXISTS public.withdraw_bank_account(integer, numeric, text, integer, text, text, text, text, text, text);
DROP FUNCTION IF EXISTS public.withdraw_bank_account(bigint, numeric, text, text, text, text, text, text, text, text);

CREATE OR REPLACE FUNCTION public.withdraw_bank_account(
    p_account_id bigint,
    p_amount numeric,
    p_description text DEFAULT NULL::text,
    p_expense_account_id bigint DEFAULT NULL::bigint,
    p_entity_type text DEFAULT NULL::text,
    p_entity_id text DEFAULT NULL::text,
    p_counterparty_name text DEFAULT NULL::text,
    p_reference_type text DEFAULT NULL::text,
    p_reference_id text DEFAULT NULL::text,
    p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_current_cost_base NUMERIC := 0;
    v_current_book_rate NUMERIC := 1.0;
    v_new_balance     NUMERIC := 0;
    v_new_cost_base   NUMERIC := 0;
    v_new_book_rate   NUMERIC := 1.0;
    v_tx_id           BIGINT;
    v_currency        TEXT;
    v_company_id      UUID;
    v_bank_acct       BIGINT;
    v_expense_acct    BIGINT;
    v_desc            TEXT;
    v_je_id           BIGINT;
    v_je_source_type  TEXT;
    v_source_type     TEXT;
    v_book_rate       NUMERIC := 1.0;
    v_base_amount     NUMERIC;
    v_snapshot        JSONB;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0), currency, company_id
      INTO v_current_balance, v_current_cost_base, v_current_book_rate, v_currency, v_company_id
    FROM public.bank_accounts WHERE id = p_account_id
    FOR UPDATE;

    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'رصيد الحساب البنكي غير كافٍ. الرصيد الحالي: %', v_current_balance;
    END IF;

    IF v_currency = 'EGP' THEN
        v_book_rate := 1.0;
        v_base_amount := p_amount;
        v_new_cost_base := GREATEST(0, COALESCE(v_current_cost_base, 0) - p_amount);
        v_new_book_rate := 1.0;
    ELSE
        v_book_rate := COALESCE(NULLIF(v_current_book_rate, 0), public.fn_get_exchange_rate(v_currency));
        v_base_amount := ROUND(p_amount * v_book_rate, 2);
        v_new_cost_base := GREATEST(0, COALESCE(v_current_cost_base, 0) - v_base_amount);
    END IF;

    v_new_balance := v_current_balance - p_amount;

    IF v_new_balance > 0 AND v_currency != 'EGP' THEN
        v_new_book_rate := ROUND(v_new_cost_base / v_new_balance, 4);
    ELSIF v_currency = 'EGP' THEN
        v_new_book_rate := 1.0;
    ELSE
        v_new_book_rate := v_book_rate;
        v_new_cost_base := 0;
    END IF;

    IF p_entity_type IS NULL THEN
        v_source_type := 'opening_balance';
        v_desc := COALESCE(NULLIF(p_description, ''), 'سحب رصيد افتتاحي من الحساب البنكي');
    ELSE
        v_source_type := p_entity_type;
        v_desc := COALESCE(NULLIF(p_description, ''), 'سحب بنكي');
    END IF;

    v_bank_acct := public.resolve_gl_account(
        CASE v_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );

    IF p_entity_type = 'customer' AND p_entity_id IS NOT NULL THEN
        SELECT account_id INTO v_expense_acct FROM public.customers WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'supplier' AND p_entity_id IS NOT NULL THEN
        SELECT account_id INTO v_expense_acct FROM public.suppliers WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'clearing_agent' AND p_entity_id IS NOT NULL THEN
        SELECT account_id INTO v_expense_acct FROM public.clearing_agents WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'shipping_company' AND p_entity_id IS NOT NULL THEN
        SELECT account_id INTO v_expense_acct FROM public.shipping_companies WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'shareholder' AND p_entity_id IS NOT NULL THEN
        SELECT account_id INTO v_expense_acct FROM public.shareholders WHERE id::TEXT = p_entity_id;
    ELSE
        v_expense_acct := public.resolve_gl_account('51101', v_company_id);
    END IF;

    IF p_expense_account_id IS NOT NULL THEN
        v_expense_acct := p_expense_account_id;
    END IF;

    IF v_expense_acct IS NULL THEN
        v_expense_acct := public.resolve_gl_account('51101', v_company_id);
    END IF;

    UPDATE public.bank_accounts
    SET balance = v_new_balance,
        cost_base = v_new_cost_base,
        book_rate = v_new_book_rate,
        updated_at = NOW()
    WHERE id = p_account_id;

    IF p_reference_type = 'purchase_invoice' AND p_reference_id IS NOT NULL THEN
        UPDATE public.purchase_invoices
        SET paid_amount = COALESCE(paid_amount, 0) + p_amount,
            remaining_amount = GREATEST(0, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - (COALESCE(paid_amount, 0) + p_amount)),
            payment_status = CASE
                WHEN GREATEST(0, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - (COALESCE(paid_amount, 0) + p_amount)) <= 0.001 THEN 'paid'
                ELSE 'partial'
            END,
            updated_at = NOW()
        WHERE id::TEXT = p_reference_id OR invoice_number = p_reference_id;
    ELSIF (p_reference_type = 'lot_receipt' OR p_reference_type = 'crop_purchase') AND p_reference_id IS NOT NULL THEN
        UPDATE public.lot_receipts
        SET paid_amount = COALESCE(paid_amount, 0) + p_amount,
            updated_at = NOW()
        WHERE id::TEXT = p_reference_id OR lot_number = p_reference_id;
    END IF;

    v_je_source_type := CASE
        WHEN p_entity_type = 'supplier' THEN
            CASE
                WHEN p_reference_type IN ('lot_receipt', 'crop_purchase') THEN 'crop_payment'
                WHEN p_reference_type = 'purchase_invoice' THEN 'purchase_payment'
                ELSE 'supplier_payment'
            END
        WHEN p_entity_type = 'shareholder' THEN 'shareholder_payment_received'
        ELSE 'bank_withdrawal'
    END;

    v_je_id := public.post_journal_entry(
        p_source_type := v_je_source_type,
        p_description := v_desc,
        p_entry_date := CURRENT_DATE,
        p_company_id := v_company_id,
        p_created_by := auth.uid(),
        p_lines := jsonb_build_array(
            jsonb_build_object('account_id', v_expense_acct, 'debit', p_amount, 'credit', 0, 'base_debit', v_base_amount, 'base_credit', 0, 'currency', v_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_bank_acct,    'debit', 0, 'credit', p_amount, 'base_debit', 0, 'base_credit', v_base_amount, 'currency', v_currency, 'description', v_desc)
        ),
        p_source_id := p_reference_id
    );

    v_snapshot := jsonb_build_object(
        'currency', v_currency,
        'exchange_rate', v_book_rate,
        'book_rate', v_new_book_rate,
        'amount', p_amount,
        'amount_in_base_currency', v_base_amount,
        'rate_date', CURRENT_DATE,
        'rate_source', 'bank_book_rate'
    );

    INSERT INTO public.bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, entity_type, entity_id, counterparty_name,
        source_type, journal_entry_id, created_at, created_by, notes,
        exchange_rate, amount_in_base_currency, currency_snapshot
    ) VALUES (
        p_account_id, 'withdraw', p_amount, v_current_balance, v_new_balance,
        v_desc, p_entity_type, p_entity_id, p_counterparty_name,
        v_source_type, v_je_id, NOW(), auth.uid(), p_notes,
        v_book_rate, v_base_amount, v_snapshot
    ) RETURNING id INTO v_tx_id;

    IF p_entity_type = 'customer' AND p_entity_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance + p_amount WHERE id::TEXT = p_entity_id;

        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_id, reference_text, description, created_by
        ) VALUES (
            'customer', p_entity_id::text, 'debit', p_amount, v_currency,
            'refund', v_tx_id, v_desc, v_desc, auth.uid()
        );
    ELSIF p_entity_type = 'supplier' AND p_entity_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance - p_amount WHERE id::TEXT = p_entity_id;

        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_id, reference_text, description, created_by
        ) VALUES (
            'supplier', p_entity_id::text, 'credit', p_amount, v_currency,
            'supplier_payment', v_tx_id, v_desc, v_desc, auth.uid()
        );
    ELSIF p_entity_type = 'clearing_agent' AND p_entity_id IS NOT NULL THEN
        UPDATE public.clearing_agents SET manual_adjustment = manual_adjustment - p_amount, balance = balance - p_amount WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'shipping_company' AND p_entity_id IS NOT NULL THEN
        UPDATE public.shipping_companies SET manual_adjustment = manual_adjustment - p_amount, balance = balance - p_amount WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'shareholder' AND p_entity_id IS NOT NULL THEN
        IF v_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp - p_amount WHERE id::TEXT = p_entity_id;
        ELSIF v_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd - p_amount WHERE id::TEXT = p_entity_id;
        ELSIF v_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur - p_amount WHERE id::TEXT = p_entity_id;
        ELSIF v_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - p_amount WHERE id::TEXT = p_entity_id;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'transaction_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'balance', v_new_balance,
        'cost_base', v_new_cost_base,
        'book_rate', v_new_book_rate
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.deposit_bank_account(bigint, numeric, text, bigint, text, text, text, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.withdraw_bank_account(bigint, numeric, text, bigint, text, text, text, text, text, text) TO authenticated, service_role;

-- ── Ensure all columns exist on public.cheques ──
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'cheques' AND column_name = 'bank_account_id'
    ) THEN
        ALTER TABLE public.cheques ADD COLUMN bank_account_id INTEGER REFERENCES public.bank_accounts(id) ON DELETE SET NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'cheques' AND column_name = 'journal_entry_id'
    ) THEN
        ALTER TABLE public.cheques ADD COLUMN journal_entry_id BIGINT REFERENCES public.journal_entries(id) ON DELETE SET NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'cheques' AND column_name = 'exchange_rate'
    ) THEN
        ALTER TABLE public.cheques ADD COLUMN exchange_rate NUMERIC(15,6) DEFAULT 1.0;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'cheques' AND column_name = 'amount_in_base_currency'
    ) THEN
        ALTER TABLE public.cheques ADD COLUMN amount_in_base_currency NUMERIC(15,2);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'cheques' AND column_name = 'treasury_id'
    ) THEN
        ALTER TABLE public.cheques ADD COLUMN treasury_id BIGINT REFERENCES public.treasuries(id) ON DELETE SET NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'cheques' AND column_name = 'bank_transaction_id'
    ) THEN
        ALTER TABLE public.cheques ADD COLUMN bank_transaction_id BIGINT;
    END IF;
END $$;

-- ── 2. Upgrade clear_cheque for Outgoing Cheques & Customer Realized FX ──
CREATE OR REPLACE FUNCTION public.clear_cheque(p_cheque_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_cheque RECORD;
    v_desc TEXT;
    v_bank_id INTEGER;
    v_bank_bal NUMERIC;
    v_current_cost_base NUMERIC := 0;
    v_current_book_rate NUMERIC := 1.0;
    v_new_cost_base NUMERIC := 0;
    v_new_book_rate NUMERIC := 1.0;
    v_cost_released NUMERIC := 0;
    v_currency TEXT;
    v_company_id UUID;
    v_new_bank_bal NUMERIC;
    v_bank_acct BIGINT;
    v_counterparty_acct BIGINT;
    v_realized_gain_acct BIGINT;
    v_realized_loss_acct BIGINT;
    v_je_id BIGINT;
    v_bank_tx_id BIGINT;
    v_rate NUMERIC := 1.0;
    v_base_amount NUMERIC;
    v_book_rate NUMERIC := 1.0;
    v_snapshot JSONB;
    v_entity_id TEXT;
    v_norm_counterparty_type TEXT;
    v_je_lines JSONB := '[]'::jsonb;
    v_treasury_id BIGINT;
    v_tr_bal NUMERIC := 0;
    v_tr_cost_base NUMERIC := 0;
    v_tr_book_rate NUMERIC := 1.0;
    v_new_tr_bal NUMERIC := 0;
    v_new_tr_cost_base NUMERIC := 0;
    v_new_tr_book_rate NUMERIC := 1.0;

    -- Liability matching & FX calculation variables
    v_total_ap_base   NUMERIC := 0.0;
    v_total_gain      NUMERIC := 0.0;
    v_total_loss      NUMERIC := 0.0;
    v_remaining_alloc NUMERIC;
    v_alloc           NUMERIC;
    v_inv_rate        NUMERIC;
    v_inv_base        NUMERIC;
    v_paid_base       NUMERIC;
    v_diff            NUMERIC;
    v_liab            RECORD;
    v_shipment        RECORD;
    v_spec_shipment   RECORD;
    v_total_cust_base NUMERIC;
    v_alloc_bank_base NUMERIC;
    v_alloc_cust_base NUMERIC;
BEGIN
    SELECT * INTO v_cheque
    FROM public.cheques
    WHERE id = p_cheque_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'الشيك غير موجود';
    END IF;

    IF v_cheque.status != 'pending' THEN
        RAISE EXCEPTION 'لا يمكن تسوية شيك بحالة %', v_cheque.status;
    END IF;

    v_currency := v_cheque.currency;
    v_rate := public.fn_get_exchange_rate(v_currency);
    v_base_amount := ROUND(v_cheque.amount * v_rate, 2);
    v_norm_counterparty_type := LOWER(COALESCE(v_cheque.counterparty_type, ''));

    IF v_cheque.type = 'outgoing' THEN
        v_desc := 'صرف شيك رقم: ' || v_cheque.cheque_number;
    ELSE
        v_desc := 'تحصيل شيك رقم: ' || v_cheque.cheque_number;
    END IF;

    -- Get bank account (use cheque's assigned bank if present, otherwise match currency)
    IF v_cheque.bank_account_id IS NOT NULL THEN
        SELECT id, balance, COALESCE(cost_base, 0), COALESCE(book_rate, 1.0), ba.company_id
        INTO v_bank_id, v_bank_bal, v_current_cost_base, v_current_book_rate, v_company_id
        FROM public.bank_accounts ba
        WHERE ba.id = v_cheque.bank_account_id
        FOR UPDATE;
    ELSE
        SELECT id, balance, COALESCE(cost_base, 0), COALESCE(book_rate, 1.0), ba.company_id
        INTO v_bank_id, v_bank_bal, v_current_cost_base, v_current_book_rate, v_company_id
        FROM public.bank_accounts ba
        WHERE ba.currency = v_currency AND ba.deleted_at IS NULL
        ORDER BY ba.id ASC
        LIMIT 1
        FOR UPDATE;
    END IF;

    IF v_bank_id IS NULL THEN
        RAISE EXCEPTION 'لم يتم العثور على حساب بنكي بعملة %', v_currency;
    END IF;

    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    END IF;

    -- ================================================================
    -- 1. OUTGOING CHEQUE: Dr Counterparty / Cr Bank (With Liability Allocation & Realized FX)
    -- ================================================================
    IF v_cheque.type = 'outgoing' THEN
        IF v_bank_bal < v_cheque.amount THEN
            RAISE EXCEPTION 'رصيد الحساب البنكي غير كافٍ. الرصيد الحالي: %', v_bank_bal;
        END IF;

        IF v_currency = 'EGP' THEN
            v_book_rate := 1.0;
            v_cost_released := v_cheque.amount;
            v_new_cost_base := GREATEST(0, v_current_cost_base - v_cheque.amount);
            v_new_book_rate := 1.0;
        ELSE
            v_book_rate := COALESCE(NULLIF(v_current_book_rate, 0), v_rate);
            v_cost_released := ROUND(v_cheque.amount * v_book_rate, 2);
            v_new_cost_base := GREATEST(0, v_current_cost_base - v_cost_released);
        END IF;

        v_new_bank_bal := v_bank_bal - v_cheque.amount;

        IF v_new_bank_bal > 0 AND v_currency != 'EGP' THEN
            v_new_book_rate := ROUND(v_new_cost_base / v_new_bank_bal, 4);
        ELSIF v_currency = 'EGP' THEN
            v_new_book_rate := 1.0;
        ELSE
            v_new_book_rate := v_book_rate;
            v_new_cost_base := 0;
        END IF;

        v_counterparty_acct := NULL;
        v_entity_id := NULL;
        v_treasury_id := NULL;

        IF v_norm_counterparty_type = 'supplier' AND v_cheque.supplier_id IS NOT NULL THEN
            v_entity_id := v_cheque.supplier_id::text;
            SELECT account_id INTO v_counterparty_acct FROM public.suppliers WHERE id = v_cheque.supplier_id;
        ELSIF v_norm_counterparty_type = 'shipping_company' AND COALESCE(v_cheque.shipping_company_id, v_cheque.counterparty_id) IS NOT NULL THEN
            v_entity_id := COALESCE(v_cheque.shipping_company_id, v_cheque.counterparty_id)::text;
            SELECT account_id INTO v_counterparty_acct FROM public.shipping_companies WHERE id = v_entity_id::bigint;
        ELSIF v_norm_counterparty_type = 'clearing_agent' AND COALESCE(v_cheque.clearing_agent_id, v_cheque.counterparty_id) IS NOT NULL THEN
            v_entity_id := COALESCE(v_cheque.clearing_agent_id, v_cheque.counterparty_id)::text;
            SELECT account_id INTO v_counterparty_acct FROM public.clearing_agents WHERE id = v_entity_id::bigint;
        ELSIF v_norm_counterparty_type = 'customer' AND v_cheque.counterparty_id IS NOT NULL THEN
            v_entity_id := v_cheque.counterparty_id::text;
            SELECT account_id INTO v_counterparty_acct FROM public.customers WHERE id = v_cheque.counterparty_id;
        ELSIF v_norm_counterparty_type = 'shareholder' AND v_cheque.shareholder_id IS NOT NULL THEN
            v_entity_id := v_cheque.shareholder_id::text;
            SELECT account_id INTO v_counterparty_acct FROM public.shareholders WHERE id = v_cheque.shareholder_id;
        ELSIF v_norm_counterparty_type = 'treasury' OR v_cheque.treasury_id IS NOT NULL THEN
            v_treasury_id := COALESCE(v_cheque.treasury_id, v_cheque.counterparty_id::bigint);
            v_entity_id := v_treasury_id::text;
            v_counterparty_acct := public.resolve_treasury_account(v_treasury_id::integer, v_currency, v_company_id);
        END IF;

        IF v_counterparty_acct IS NULL THEN
            IF v_norm_counterparty_type = 'supplier' THEN
                v_counterparty_acct := public.resolve_gl_account('2000', v_company_id);
            ELSIF v_norm_counterparty_type = 'shipping_company' THEN
                v_counterparty_acct := public.resolve_gl_account('2103', v_company_id);
            ELSIF v_norm_counterparty_type = 'clearing_agent' THEN
                v_counterparty_acct := public.resolve_gl_account('2104', v_company_id);
            ELSE
                v_counterparty_acct := public.resolve_gl_account('51101', v_company_id);
            END IF;
        END IF;

        v_bank_acct := public.resolve_gl_account(
            CASE v_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
            v_company_id
        );

        -- Multi-liability allocation and FX Calculation for Supplier / Shipping Company / Clearing Agent
        v_remaining_alloc := v_cheque.amount;
        v_total_ap_base := 0.0;
        v_total_gain := 0.0;
        v_total_loss := 0.0;

        IF v_norm_counterparty_type IN ('supplier', 'shipping_company', 'clearing_agent') AND v_entity_id IS NOT NULL THEN
            FOR v_liab IN 
                SELECT liability_type, liability_id, reference_number, currency, currency_snapshot, due_amount
                FROM public.vw_unpaid_liabilities
                WHERE LOWER(entity_type) = v_norm_counterparty_type
                  AND entity_id = v_entity_id
                  AND currency = v_currency
                ORDER BY liability_date ASC, liability_id ASC
            LOOP
                EXIT WHEN v_remaining_alloc <= 0;

                IF v_remaining_alloc >= v_liab.due_amount THEN
                    v_alloc := v_liab.due_amount;
                ELSE
                    v_alloc := v_remaining_alloc;
                END IF;

                v_inv_rate := COALESCE(
                    (v_liab.currency_snapshot->>'exchange_rate')::NUMERIC,
                    v_rate
                );

                v_inv_base  := ROUND(v_alloc * v_inv_rate, 2);
                v_paid_base := ROUND(v_alloc * v_book_rate, 2);
                v_diff      := v_paid_base - v_inv_base;

                v_total_ap_base := v_total_ap_base + v_inv_base;

                IF v_diff < 0 THEN
                    v_total_gain := v_total_gain + ABS(v_diff);
                ELSIF v_diff > 0 THEN
                    v_total_loss := v_total_loss + v_diff;
                END IF;

                -- Update individual liability records
                IF v_liab.liability_type = 'purchase_invoice' THEN
                    IF v_norm_counterparty_type = 'supplier' THEN
                        INSERT INTO public.supplier_payment_allocations (
                            source_type, source_id, purchase_invoice_id, supplier_id, allocation_type, amount
                        ) VALUES (
                            'bank', p_cheque_id, v_liab.liability_id::integer, v_cheque.supplier_id, 'invoice', v_alloc
                        );
                    END IF;
                    UPDATE public.purchase_invoices
                    SET paid_amount = paid_amount + v_alloc,
                        payment_status = CASE WHEN (paid_amount + v_alloc) >= (total_amount - discount_amount) THEN 'paid' ELSE 'partial' END,
                        payment_bank_account_id = v_bank_id,
                        payment_source_type = 'bank'
                    WHERE id::text = v_liab.liability_id;
                    
                ELSIF v_liab.liability_type = 'lot_receipt' THEN
                    IF v_norm_counterparty_type = 'supplier' THEN
                        INSERT INTO public.supplier_payment_allocations (
                            source_type, source_id, lot_receipt_id, supplier_id, allocation_type, amount
                        ) VALUES (
                            'bank', p_cheque_id, v_liab.liability_id::bigint, v_cheque.supplier_id, 'lot_receipt', v_alloc
                        );
                    END IF;
                    UPDATE public.lot_receipts
                    SET paid_amount = COALESCE(paid_amount, 0) + v_alloc,
                        payment_status = CASE WHEN (COALESCE(paid_amount, 0) + v_alloc) >= COALESCE(total_fruit_cost, 0) THEN 'paid' ELSE 'partial' END,
                        payment_bank_account_id = v_bank_id,
                        payment_source_type = 'bank',
                        updated_at = NOW()
                    WHERE id::text = v_liab.liability_id;
                    
                ELSIF v_liab.liability_type = 'packing_cost_item' THEN
                    IF v_norm_counterparty_type = 'supplier' THEN
                        INSERT INTO public.supplier_payment_allocations (
                            source_type, source_id, packing_order_cost_item_id, supplier_id, allocation_type, amount
                        ) VALUES (
                            'bank', p_cheque_id, v_liab.liability_id::bigint, v_cheque.supplier_id, 'packing_cost', v_alloc
                        );
                    END IF;
                    UPDATE public.packing_order_cost_items
                    SET paid_amount = paid_amount + v_alloc,
                        payment_status = CASE WHEN (paid_amount + v_alloc) >= COALESCE(original_amount, 0) THEN 'paid' ELSE 'partial' END,
                        payment_bank_account_id = v_bank_id,
                        payment_source_type = 'bank'
                    WHERE id::text = v_liab.liability_id;
                    
                ELSIF v_liab.liability_type = 'shipment_cost_item' THEN
                    IF v_norm_counterparty_type = 'supplier' THEN
                        INSERT INTO public.supplier_payment_allocations (
                            source_type, source_id, shipment_cost_item_id, supplier_id, allocation_type, amount
                        ) VALUES (
                            'bank', p_cheque_id, v_liab.liability_id::bigint, v_cheque.supplier_id, 'shipment_cost', v_alloc
                        );
                    END IF;
                    UPDATE public.shipment_cost_items
                    SET paid_amount = paid_amount + v_alloc,
                        payment_status = CASE WHEN (paid_amount + v_alloc) >= ROUND(COALESCE(NULLIF(total_price, 0), quantity * unit_price, 0) / COALESCE(NULLIF(exchange_rate, 0), 1.0), 2) THEN 'paid' ELSE 'partial' END,
                        payment_bank_account_id = v_bank_id,
                        payment_source_type = 'bank'
                    WHERE id::text = v_liab.liability_id;
                END IF;

                v_remaining_alloc := v_remaining_alloc - v_alloc;
            END LOOP;

            IF v_remaining_alloc > 0 THEN
                v_total_ap_base := v_total_ap_base + ROUND(v_remaining_alloc * v_book_rate, 2);
            END IF;
        ELSE
            v_total_ap_base := v_cost_released;
        END IF;

        -- Build Journal Entry with single balanced structure & Realized FX
        v_je_lines := jsonb_build_array(
            jsonb_build_object(
                'account_id', v_counterparty_acct,
                'debit', v_cheque.amount,
                'credit', 0,
                'base_debit', v_total_ap_base,
                'base_credit', 0,
                'currency', v_currency,
                'description', v_desc || ' (تسوية ذمم دائنة)'
            )
        );

        IF v_total_loss > 0 THEN
            v_realized_loss_acct := public.resolve_realized_fx_loss_account(v_company_id);
            v_je_lines := v_je_lines || jsonb_build_array(
                jsonb_build_object(
                    'account_id', v_realized_loss_acct,
                    'debit', v_total_loss,
                    'credit', 0,
                    'base_debit', v_total_loss,
                    'base_credit', 0,
                    'currency', 'EGP',
                    'description', 'خسائر فروق أسعار عملة محققة - ' || v_desc
                )
            );
        END IF;

        v_je_lines := v_je_lines || jsonb_build_array(
            jsonb_build_object(
                'account_id', v_bank_acct,
                'debit', 0,
                'credit', v_cheque.amount,
                'base_debit', 0,
                'base_credit', v_cost_released,
                'currency', v_currency,
                'description', v_desc || ' (صرف شيك من البنك)'
            )
        );

        IF v_total_gain > 0 THEN
            v_realized_gain_acct := public.resolve_realized_fx_gain_account(v_company_id);
            v_je_lines := v_je_lines || jsonb_build_array(
                jsonb_build_object(
                    'account_id', v_realized_gain_acct,
                    'debit', 0,
                    'credit', v_total_gain,
                    'base_debit', 0,
                    'base_credit', v_total_gain,
                    'currency', 'EGP',
                    'description', 'أرباح فروق أسعار عملة محققة - ' || v_desc
                )
            );
        END IF;

        v_je_id := public.post_journal_entry(
            'bank_withdrawal',
            v_desc,
            CURRENT_DATE,
            v_company_id,
            auth.uid(),
            v_je_lines,
            v_entity_id
        );

        UPDATE public.bank_accounts
        SET balance = v_new_bank_bal,
            cost_base = v_new_cost_base,
            book_rate = v_new_book_rate,
            updated_at = now()
        WHERE id = v_bank_id;

        INSERT INTO public.bank_account_transactions
            (bank_account_id, type, amount, balance_before, balance_after,
             description, created_by, journal_entry_id, entity_type, entity_id, source_type,
             exchange_rate, amount_in_base_currency, currency_snapshot)
        VALUES
            (v_bank_id, 'withdraw', v_cheque.amount, v_bank_bal, v_new_bank_bal,
             v_desc, auth.uid(), v_je_id, 'cheque', p_cheque_id::TEXT, 'cheque',
             v_book_rate, v_cost_released, jsonb_build_object(
                'currency', v_currency,
                'exchange_rate', v_book_rate,
                'book_rate', v_new_book_rate,
                'cost_base', v_new_cost_base,
                'amount', v_cheque.amount,
                'amount_in_base_currency', v_cost_released,
                'rate_date', CURRENT_DATE,
                'rate_source', 'bank_book_rate',
                'realized_fx_gain', v_total_gain,
                'realized_fx_loss', v_total_loss
             ))
        RETURNING id INTO v_bank_tx_id;

        -- If outgoing cheque feeds a treasury
        IF v_treasury_id IS NOT NULL THEN
            SELECT COALESCE(balance, 0), COALESCE(cost_base, 0), COALESCE(book_rate, 1.0)
            INTO v_tr_bal, v_tr_cost_base, v_tr_book_rate
            FROM public.treasury_balances
            WHERE treasury_id = v_treasury_id AND currency = v_currency
            FOR UPDATE;

            IF NOT FOUND THEN
                v_tr_bal := 0;
                v_tr_cost_base := 0;
                v_tr_book_rate := 1.0;
            END IF;

            v_new_tr_bal := v_tr_bal + v_cheque.amount;
            v_new_tr_cost_base := v_tr_cost_base + v_cost_released;

            IF v_currency = 'EGP' THEN
                v_new_tr_book_rate := 1.0;
            ELSIF v_new_tr_bal > 0 THEN
                v_new_tr_book_rate := ROUND(v_new_tr_cost_base / v_new_tr_bal, 4);
            ELSE
                v_new_tr_book_rate := v_book_rate;
            END IF;

            INSERT INTO public.treasury_balances (treasury_id, currency, balance, cost_base, book_rate, account_id, updated_at)
            VALUES (v_treasury_id, v_currency, v_new_tr_bal, v_new_tr_cost_base, v_new_tr_book_rate, v_counterparty_acct, NOW())
            ON CONFLICT (treasury_id, currency) DO UPDATE
            SET balance = v_new_tr_bal,
                cost_base = v_new_tr_cost_base,
                book_rate = v_new_tr_book_rate,
                updated_at = NOW();

            INSERT INTO public.treasury_transactions (
                treasury_id, type, currency, amount,
                balance_before, balance_after, description, source_type, journal_entry_id, created_by,
                reference_type, reference_id, exchange_rate, amount_in_base_currency, currency_snapshot
            ) VALUES (
                v_treasury_id, 'deposit', v_currency, v_cheque.amount,
                v_tr_bal, v_new_tr_bal, 'تغذية الخزينة من صرف شيك رقم: ' || COALESCE(v_cheque.cheque_number, ''), 'cheque', v_je_id, auth.uid(),
                'cheque', p_cheque_id::text, v_book_rate, v_cost_released,
                jsonb_build_object(
                    'currency', v_currency,
                    'exchange_rate', v_book_rate,
                    'book_rate', v_new_tr_book_rate,
                    'cost_base', v_new_tr_cost_base,
                    'amount', v_cheque.amount,
                    'amount_in_base_currency', v_cost_released,
                    'rate_date', CURRENT_DATE,
                    'rate_source', 'bank_book_rate'
                )
            );
        END IF;

        -- Sync Entity True Balance
        IF v_norm_counterparty_type = 'supplier' AND v_cheque.supplier_id IS NOT NULL THEN
            UPDATE public.suppliers
            SET outstanding_balance = (SELECT true_balance FROM public.get_supplier_true_balances() WHERE supplier_id = v_cheque.supplier_id)
            WHERE id = v_cheque.supplier_id;
        ELSIF v_norm_counterparty_type = 'shipping_company' AND v_entity_id IS NOT NULL THEN
            UPDATE public.shipping_companies
            SET balance = (SELECT true_balance FROM public.get_shipping_company_true_balances() WHERE shipping_company_id = v_entity_id::bigint)
            WHERE id = v_entity_id::bigint;
        ELSIF v_norm_counterparty_type = 'clearing_agent' AND v_entity_id IS NOT NULL THEN
            UPDATE public.clearing_agents
            SET balance = (SELECT true_balance FROM public.get_clearing_agent_true_balances() WHERE clearing_agent_id = v_entity_id::bigint)
            WHERE id = v_entity_id::bigint;
        END IF;

    -- ================================================================
    -- 2. INCOMING CHEQUE: Dr Bank / Cr Counterparty (Customer Shipment Matching & FX)
    -- ================================================================
    ELSIF v_cheque.type = 'incoming' THEN
        IF v_currency = 'EGP' THEN
            v_new_cost_base := v_current_cost_base + v_cheque.amount;
            v_new_book_rate := 1.0;
        ELSE
            v_new_cost_base := v_current_cost_base + v_base_amount;
        END IF;

        v_new_bank_bal := v_bank_bal + v_cheque.amount;

        IF v_new_bank_bal > 0 AND v_currency != 'EGP' THEN
            v_new_book_rate := ROUND(v_new_cost_base / v_new_bank_bal, 4);
        ELSIF v_currency = 'EGP' THEN
            v_new_book_rate := 1.0;
        ELSE
            v_new_book_rate := v_rate;
            v_new_cost_base := v_base_amount;
        END IF;

        v_counterparty_acct := NULL;

        IF v_norm_counterparty_type = 'customer' AND v_cheque.counterparty_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct FROM public.customers WHERE id = v_cheque.counterparty_id;
        ELSIF v_norm_counterparty_type = 'supplier' AND v_cheque.supplier_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct FROM public.suppliers WHERE id = v_cheque.supplier_id;
        ELSIF v_norm_counterparty_type = 'clearing_agent' AND v_cheque.clearing_agent_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct FROM public.clearing_agents WHERE id = v_cheque.clearing_agent_id;
        ELSIF v_norm_counterparty_type = 'shipping_company' AND v_cheque.shipping_company_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct FROM public.shipping_companies WHERE id = v_cheque.shipping_company_id;
        ELSIF v_norm_counterparty_type = 'shareholder' AND v_cheque.shareholder_id IS NOT NULL THEN
            SELECT account_id INTO v_counterparty_acct FROM public.shareholders WHERE id = v_cheque.shareholder_id;
        ELSIF v_norm_counterparty_type = 'treasury' OR v_cheque.treasury_id IS NOT NULL THEN
            v_counterparty_acct := public.resolve_treasury_account(COALESCE(v_cheque.treasury_id, v_cheque.counterparty_id::bigint)::integer, v_currency, v_company_id);
        END IF;

        IF v_counterparty_acct IS NULL THEN
            IF v_norm_counterparty_type = 'customer' THEN
                v_counterparty_acct := public.resolve_gl_account('1020', v_company_id);
            ELSE
                v_counterparty_acct := public.resolve_gl_account('41101', v_company_id);
            END IF;
        END IF;

        v_bank_acct := public.resolve_gl_account(
            CASE v_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
            v_company_id
        );

        -- IAS 21 Realized FX for Customer Export Shipments
        v_remaining_alloc := v_cheque.amount;
        v_total_gain      := 0;
        v_total_loss      := 0;
        v_total_cust_base := 0;

        IF v_norm_counterparty_type = 'customer' AND v_cheque.counterparty_id IS NOT NULL AND v_currency != 'EGP' THEN
            -- Check specific shipment attached to cheque
            IF v_cheque.export_shipment_id IS NOT NULL THEN
                SELECT id, shipment_no, currency,
                       COALESCE(final_amount_currency, total_amount, 0) AS total_amt,
                       COALESCE(paid_amount, 0) AS already_paid,
                       currency_snapshot
                INTO v_spec_shipment
                FROM public.export_shipments
                WHERE id = v_cheque.export_shipment_id AND currency = v_currency;

                IF FOUND AND (v_spec_shipment.total_amt - v_spec_shipment.already_paid) > 0.01 THEN
                    v_alloc := LEAST(v_remaining_alloc, v_spec_shipment.total_amt - v_spec_shipment.already_paid);
                    v_inv_rate := COALESCE(
                        (v_spec_shipment.currency_snapshot->>'exchange_rate')::NUMERIC,
                        (v_spec_shipment.currency_snapshot->>'rate')::NUMERIC,
                        v_rate
                    );

                    v_alloc_bank_base := ROUND(v_alloc * v_rate, 2);
                    v_alloc_cust_base := ROUND(v_alloc * v_inv_rate, 2);
                    v_diff := v_alloc_bank_base - v_alloc_cust_base;

                    IF v_diff > 0 THEN v_total_gain := v_total_gain + v_diff;
                    ELSIF v_diff < 0 THEN v_total_loss := v_total_loss + ABS(v_diff);
                    END IF;

                    v_total_cust_base := v_total_cust_base + v_alloc_cust_base;
                    v_remaining_alloc := v_remaining_alloc - v_alloc;

                    UPDATE public.export_shipments
                    SET paid_amount = paid_amount + v_alloc,
                        payment_status = CASE WHEN (paid_amount + v_alloc) >= v_spec_shipment.total_amt - 0.01 THEN 'paid' ELSE 'partial' END
                    WHERE id = v_spec_shipment.id;
                END IF;
            END IF;

            -- FIFO on other open shipments
            IF v_remaining_alloc > 0.01 THEN
                FOR v_shipment IN
                    SELECT id, shipment_no, currency,
                           COALESCE(final_amount_currency, total_amount, 0) AS total_amt,
                           COALESCE(paid_amount, 0) AS already_paid,
                           currency_snapshot
                    FROM public.export_shipments
                    WHERE customer_id = v_cheque.counterparty_id
                      AND currency = v_currency
                      AND (v_cheque.export_shipment_id IS NULL OR id != v_cheque.export_shipment_id)
                      AND (payment_status IS NULL OR payment_status IN ('unpaid', 'partial'))
                      AND (COALESCE(final_amount_currency, total_amount, 0) - COALESCE(paid_amount, 0)) > 0.01
                    ORDER BY created_at ASC, id ASC
                LOOP
                    EXIT WHEN v_remaining_alloc <= 0.01;
                    v_alloc := LEAST(v_remaining_alloc, v_shipment.total_amt - v_shipment.already_paid);
                    v_inv_rate := COALESCE(
                        (v_shipment.currency_snapshot->>'exchange_rate')::NUMERIC,
                        (v_shipment.currency_snapshot->>'rate')::NUMERIC,
                        v_rate
                    );

                    v_alloc_bank_base := ROUND(v_alloc * v_rate, 2);
                    v_alloc_cust_base := ROUND(v_alloc * v_inv_rate, 2);
                    v_diff := v_alloc_bank_base - v_alloc_cust_base;

                    IF v_diff > 0 THEN v_total_gain := v_total_gain + v_diff;
                    ELSIF v_diff < 0 THEN v_total_loss := v_total_loss + ABS(v_diff);
                    END IF;

                    v_total_cust_base := v_total_cust_base + v_alloc_cust_base;
                    v_remaining_alloc := v_remaining_alloc - v_alloc;

                    UPDATE public.export_shipments
                    SET paid_amount = paid_amount + v_alloc,
                        payment_status = CASE WHEN (paid_amount + v_alloc) >= v_shipment.total_amt - 0.01 THEN 'paid' ELSE 'partial' END
                    WHERE id = v_shipment.id;
                END LOOP;
            END IF;

            IF v_remaining_alloc > 0.01 THEN
                v_total_cust_base := v_total_cust_base + ROUND(v_remaining_alloc * v_rate, 2);
            END IF;
        ELSE
            v_total_cust_base := v_base_amount;
        END IF;

        v_je_lines := jsonb_build_array(
            jsonb_build_object(
                'account_id', v_bank_acct,
                'debit', v_cheque.amount,
                'credit', 0,
                'base_debit', v_base_amount,
                'base_credit', 0,
                'currency', v_currency,
                'description', v_desc
            ),
            jsonb_build_object(
                'account_id', v_counterparty_acct,
                'debit', 0,
                'credit', v_cheque.amount,
                'base_debit', 0,
                'base_credit', v_total_cust_base,
                'currency', v_currency,
                'description', v_desc || ' (تسوية ذمم مدينة)'
            )
        );

        IF v_total_gain > 0 THEN
            v_realized_gain_acct := public.resolve_realized_fx_gain_account(v_company_id);
            v_je_lines := v_je_lines || jsonb_build_array(
                jsonb_build_object(
                    'account_id', v_realized_gain_acct,
                    'debit', 0,
                    'credit', v_total_gain,
                    'base_debit', 0,
                    'base_credit', v_total_gain,
                    'currency', 'EGP',
                    'description', 'أرباح فروق أسعار عملة محققة - ' || v_desc
                )
            );
        END IF;

        IF v_total_loss > 0 THEN
            v_realized_loss_acct := public.resolve_realized_fx_loss_account(v_company_id);
            v_je_lines := v_je_lines || jsonb_build_array(
                jsonb_build_object(
                    'account_id', v_realized_loss_acct,
                    'debit', v_total_loss,
                    'credit', 0,
                    'base_debit', v_total_loss,
                    'base_credit', 0,
                    'currency', 'EGP',
                    'description', 'خسائر فروق أسعار عملة محققة - ' || v_desc
                )
            );
        END IF;

        v_je_id := public.post_journal_entry(
            'bank_deposit',
            v_desc,
            CURRENT_DATE,
            v_company_id,
            auth.uid(),
            v_je_lines
        );

        UPDATE public.bank_accounts
        SET balance = v_new_bank_bal,
            cost_base = v_new_cost_base,
            book_rate = v_new_book_rate,
            updated_at = now()
        WHERE id = v_bank_id;

        INSERT INTO public.bank_account_transactions
            (bank_account_id, type, amount, balance_before, balance_after,
             description, created_by, journal_entry_id, entity_type, entity_id, source_type,
             exchange_rate, amount_in_base_currency, currency_snapshot)
        VALUES
            (v_bank_id, 'deposit', v_cheque.amount, v_bank_bal, v_new_bank_bal,
             v_desc, auth.uid(), v_je_id, 'cheque', p_cheque_id::TEXT, 'cheque',
             v_rate, v_base_amount, jsonb_build_object(
                'currency', v_currency,
                'exchange_rate', v_rate,
                'cost_base', v_new_cost_base,
                'book_rate', v_new_book_rate,
                'amount', v_cheque.amount,
                'amount_in_base_currency', v_base_amount,
                'rate_date', CURRENT_DATE,
                'realized_fx_gain', v_total_gain,
                'realized_fx_loss', v_total_loss
             ))
        RETURNING id INTO v_bank_tx_id;
    END IF;

    -- Update Cheque Record Status
    UPDATE public.cheques
    SET status = 'cleared',
        cleared_at = now(),
        journal_entry_id = v_je_id,
        bank_transaction_id = v_bank_tx_id,
        currency_snapshot = jsonb_build_object(
            'currency', v_currency,
            'exchange_rate', CASE WHEN v_cheque.type = 'outgoing' THEN v_book_rate ELSE v_rate END,
            'amount_in_base_currency', CASE WHEN v_cheque.type = 'outgoing' THEN v_cost_released ELSE v_base_amount END,
            'realized_fx_gain', v_total_gain,
            'realized_fx_loss', v_total_loss
        )
    WHERE id = p_cheque_id;

    RETURN jsonb_build_object(
        'success', true,
        'cheque_id', p_cheque_id,
        'journal_entry_id', v_je_id,
        'bank_transaction_id', v_bank_tx_id,
        'realized_fx_gain', v_total_gain,
        'realized_fx_loss', v_total_loss
    );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.clear_cheque(bigint) TO authenticated, service_role;

-- ── 3. Cleanup existing orphaned duplicate JEs from previous multi-payments ──
DO $$
DECLARE
    r RECORD;
BEGIN
    -- Remove orphaned preliminary JEs where the transaction was updated to a newer multi-payment JE
    FOR r IN
        SELECT DISTINCT je.id as dup_je_id
        FROM public.journal_entries je
        WHERE je.source_type IN ('treasury_payment', 'bank_withdrawal')
          AND (je.description LIKE 'سداد مستحقات%' OR je.description LIKE 'سداد مديونيات%')
          AND NOT EXISTS (
              SELECT 1 FROM public.treasury_transactions tt WHERE tt.journal_entry_id = je.id
          )
          AND NOT EXISTS (
              SELECT 1 FROM public.bank_account_transactions bt WHERE bt.journal_entry_id = je.id
          )
          AND NOT EXISTS (
              SELECT 1 FROM public.cheques ch WHERE ch.journal_entry_id = je.id
          )
    LOOP
        DELETE FROM public.account_ledger_entries WHERE journal_entry_id = r.dup_je_id;
        DELETE FROM public.journal_entries WHERE id = r.dup_je_id;
    END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
