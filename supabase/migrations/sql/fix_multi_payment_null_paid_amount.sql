-- ============================================================================
-- Migration: Fix Multi-Invoice Payment COALESCE, Transport Supplier & Data Reconciliation
-- Date: 2026-09-22
-- Description:
-- 1. Updates `rpc_entity_multi_payment` with robust COALESCE handling:
--    - Prevents `NULL + number = NULL` on initial invoice/receipt payments.
--    - Safeguards discount_amount, total_amount, and original_amount against NULLs.
--    - Adds native support for `transport_supplier` and `transport` entity types.
-- 2. Updates `vw_unpaid_liabilities` to safely COALESCE total_amount and discount_amount.
-- 3. Performs data reconciliation for existing purchase_invoices, lot_receipts,
--    packing_order_cost_items, and shipment_cost_items to restore correct
--    `paid_amount` and `payment_status` based on historical allocations.
-- ============================================================================

-- ── 1. Recreate vw_unpaid_liabilities with Robust COALESCE ─────────────────
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
    (COALESCE(purchase_invoices.total_amount, 0) - COALESCE(purchase_invoices.discount_amount, 0) - COALESCE(purchase_invoices.paid_amount, 0::numeric))::double precision AS due_amount,
    purchase_invoices.invoice_date AS liability_date
FROM public.purchase_invoices
WHERE (purchase_invoices.payment_status IS NULL OR (purchase_invoices.payment_status = ANY (ARRAY['unpaid'::text, 'partial'::text]))) 
  AND (COALESCE(purchase_invoices.total_amount, 0) - COALESCE(purchase_invoices.discount_amount, 0) - COALESCE(purchase_invoices.paid_amount, 0::numeric)) > 0.001

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

-- ── 2. Create or Replace rpc_entity_multi_payment ──────────────────────────
DROP FUNCTION IF EXISTS public.rpc_entity_multi_payment(text, bigint, text, numeric, text, text, text, integer, text);
DROP FUNCTION IF EXISTS public.rpc_entity_multi_payment(text, bigint, text, numeric, text, text, text, bigint, text);

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
    ELSIF v_norm_entity_type IN ('transport_supplier', 'transport') THEN
        SELECT 
            name, COALESCE(initial_balance, 0), COALESCE(initial_balance_direction, 'CREDIT'), company_id, account_id
        INTO v_entity_name, v_initial_balance, v_initial_direction, v_company_id, v_entity_acct
        FROM public.transport_suppliers WHERE id = p_entity_id::integer;
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

    -- 4. Calculate Remaining Opening Balance to Allocate
    IF v_norm_entity_type = 'supplier' AND v_initial_balance > 0 AND UPPER(v_initial_direction) = 'CREDIT' THEN
        SELECT COALESCE(SUM(amount), 0) INTO v_opening_paid
        FROM public.supplier_payment_allocations
        WHERE supplier_id = v_supplier_uuid AND allocation_type = 'opening_balance';

        v_opening_remaining := GREATEST(0, v_initial_balance - v_opening_paid);
    ELSIF v_norm_entity_type IN ('shipping_company', 'clearing_agent', 'transport_supplier', 'transport') AND v_initial_balance > 0 AND UPPER(v_initial_direction) = 'CREDIT' THEN
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

        -- Update the specific liability table with strict COALESCE
        IF v_liab.liability_type = 'purchase_invoice' THEN
            IF v_norm_entity_type = 'supplier' THEN
                INSERT INTO public.supplier_payment_allocations (
                    source_type, source_id, purchase_invoice_id, supplier_id, allocation_type, amount
                ) VALUES (
                    p_source_type, v_tx_id, v_liab.liability_id::integer, v_supplier_uuid, 'invoice', v_allocation_amount
                );
            END IF;
            UPDATE public.purchase_invoices
            SET paid_amount = COALESCE(paid_amount, 0) + v_allocation_amount,
                payment_status = CASE 
                    WHEN (COALESCE(paid_amount, 0) + v_allocation_amount) >= (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0) - 0.001) THEN 'paid' 
                    ELSE 'partial' 
                END,
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
            IF v_norm_entity_type = 'supplier' THEN
                INSERT INTO public.supplier_payment_allocations (
                    source_type, source_id, packing_order_cost_item_id, supplier_id, allocation_type, amount
                ) VALUES (
                    p_source_type, v_tx_id, v_liab.liability_id::bigint, v_supplier_uuid, 'packing_cost', v_allocation_amount
                );
            END IF;
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
            IF v_norm_entity_type = 'supplier' THEN
                INSERT INTO public.supplier_payment_allocations (
                    source_type, source_id, shipment_cost_item_id, supplier_id, allocation_type, amount
                ) VALUES (
                    p_source_type, v_tx_id, v_liab.liability_id::bigint, v_supplier_uuid, 'shipment_cost', v_allocation_amount
                );
            END IF;
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
    ELSIF v_norm_entity_type IN ('transport_supplier', 'transport') THEN
        UPDATE public.transport_suppliers
        SET current_balance = COALESCE(current_balance, 0) - p_amount,
            balance = COALESCE(balance, 0) - p_amount,
            updated_at = NOW()
        WHERE id = p_entity_id::integer;
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

GRANT EXECUTE ON FUNCTION public.rpc_entity_multi_payment(text, bigint, text, numeric, text, text, text, bigint, text) TO authenticated, anon, service_role;

-- ── 3. Data Reconciliation (تصحيح البيانات السابقة) ──────────────────────────

-- 3.1 تعيين 0 لأي مبالغ مسددة فارغة NULL
UPDATE public.purchase_invoices
SET paid_amount = 0
WHERE paid_amount IS NULL;

UPDATE public.lot_receipts
SET paid_amount = 0
WHERE paid_amount IS NULL;

UPDATE public.packing_order_cost_items
SET paid_amount = 0
WHERE paid_amount IS NULL;

UPDATE public.shipment_cost_items
SET paid_amount = 0
WHERE paid_amount IS NULL;

-- 3.2 إعادة تسوية فواتير المشتريات (purchase_invoices) استناداً إلى جدول السدادات الفعلي (supplier_payment_allocations)
WITH alloc_summary AS (
    SELECT 
        purchase_invoice_id,
        SUM(amount) AS total_allocated
    FROM public.supplier_payment_allocations
    WHERE purchase_invoice_id IS NOT NULL
    GROUP BY purchase_invoice_id
)
UPDATE public.purchase_invoices pi
SET 
    paid_amount = alloc.total_allocated,
    payment_status = CASE 
        WHEN alloc.total_allocated >= (COALESCE(pi.total_amount, 0) - COALESCE(pi.discount_amount, 0) - 0.001) THEN 'paid'
        WHEN alloc.total_allocated > 0 THEN 'partial'
        ELSE 'unpaid'
    END
FROM alloc_summary alloc
WHERE pi.id = alloc.purchase_invoice_id;

-- 3.3 إعادة تسوية إيصالات الاستلام (lot_receipts) استناداً إلى جدول السدادات الفعلي
WITH alloc_summary AS (
    SELECT 
        lot_receipt_id,
        SUM(amount) AS total_allocated
    FROM public.supplier_payment_allocations
    WHERE lot_receipt_id IS NOT NULL
    GROUP BY lot_receipt_id
)
UPDATE public.lot_receipts lr
SET 
    paid_amount = alloc.total_allocated,
    payment_status = CASE 
        WHEN alloc.total_allocated >= (COALESCE(lr.total_fruit_cost, 0) - 0.001) THEN 'paid'
        WHEN alloc.total_allocated > 0 THEN 'partial'
        ELSE 'unpaid'
    END
FROM alloc_summary alloc
WHERE lr.id = alloc.lot_receipt_id;

-- 3.4 إعادة تسوية تكاليف التعبئة (packing_order_cost_items) استناداً إلى جدول السدادات الفعلي
WITH alloc_summary AS (
    SELECT 
        packing_order_cost_item_id,
        SUM(amount) AS total_allocated
    FROM public.supplier_payment_allocations
    WHERE packing_order_cost_item_id IS NOT NULL
    GROUP BY packing_order_cost_item_id
)
UPDATE public.packing_order_cost_items poci
SET 
    paid_amount = alloc.total_allocated,
    payment_status = CASE 
        WHEN alloc.total_allocated >= (COALESCE(poci.original_amount, 0) - 0.001) THEN 'paid'
        WHEN alloc.total_allocated > 0 THEN 'partial'
        ELSE 'unpaid'
    END
FROM alloc_summary alloc
WHERE poci.id = alloc.packing_order_cost_item_id;

-- 3.5 إعادة تسوية تكاليف الشحن (shipment_cost_items) استناداً إلى جدول السدادات الفعلي
WITH alloc_summary AS (
    SELECT 
        shipment_cost_item_id,
        SUM(amount) AS total_allocated
    FROM public.supplier_payment_allocations
    WHERE shipment_cost_item_id IS NOT NULL
    GROUP BY shipment_cost_item_id
)
UPDATE public.shipment_cost_items sci
SET 
    paid_amount = alloc.total_allocated,
    payment_status = CASE 
        WHEN alloc.total_allocated >= (ROUND(COALESCE(NULLIF(sci.total_price, 0), sci.quantity * sci.unit_price, 0) / COALESCE(NULLIF(sci.exchange_rate, 0), 1.0), 2) - 0.001) THEN 'paid'
        WHEN alloc.total_allocated > 0 THEN 'partial'
        ELSE 'unpaid'
    END
FROM alloc_summary alloc
WHERE sci.id = alloc.shipment_cost_item_id;

-- 3.6 ضبط الحالات للفواتير والإيصالات التي لم تسدد بعد
UPDATE public.purchase_invoices
SET payment_status = 'unpaid'
WHERE (paid_amount IS NULL OR paid_amount = 0)
  AND (payment_status IS NULL OR payment_status = 'partial');

UPDATE public.lot_receipts
SET payment_status = 'unpaid'
WHERE (paid_amount IS NULL OR paid_amount = 0)
  AND (payment_status IS NULL OR payment_status = 'partial');

UPDATE public.packing_order_cost_items
SET payment_status = 'unpaid'
WHERE (paid_amount IS NULL OR paid_amount = 0)
  AND (payment_status IS NULL OR payment_status = 'partial');

UPDATE public.shipment_cost_items
SET payment_status = 'unpaid'
WHERE (paid_amount IS NULL OR paid_amount = 0)
  AND (payment_status IS NULL OR payment_status = 'partial');

-- 3.7 تحديث الأرصدة الحقيقية لكافة الموردين
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT id FROM public.suppliers LOOP
        UPDATE public.suppliers
        SET outstanding_balance = (SELECT true_balance FROM public.get_supplier_true_balances() WHERE supplier_id = r.id)
        WHERE id = r.id;
    END LOOP;
END;
$$;
