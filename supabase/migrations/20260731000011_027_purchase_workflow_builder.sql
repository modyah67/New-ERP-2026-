-- Migration 027: Phase 2 - Purchase Workflow Builder
-- Purpose: Rewrite create_purchase_workflow to use the Enterprise Engine

BEGIN;

DO $$
DECLARE
    v_company record;
    v_role_inv uuid;
    v_role_ap uuid;
BEGIN
    FOR v_company IN SELECT id FROM public.sys_companies
    LOOP
        SELECT id INTO v_role_inv FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'INVENTORY';
        SELECT id INTO v_role_ap FROM public.posting_account_roles WHERE company_id = v_company.id AND code = 'AP';
        
        -- Add templates for PURCHASE_WORKFLOW
        INSERT INTO public.document_posting_templates (company_id, document_type_code, role_id, is_required, sign_multiplier)
        VALUES 
            (v_company.id, 'PURCHASE_WORKFLOW', v_role_inv, true, 1),
            (v_company.id, 'PURCHASE_WORKFLOW', v_role_ap, true, -1)
        ON CONFLICT (company_id, document_type_code, role_id) DO NOTHING;
    END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.create_purchase_workflow(
    p_purchase_date text,
    p_supplier_id text,
    p_total_amount numeric DEFAULT 0,
    p_paid_amount numeric DEFAULT 0,
    p_discount_amount numeric DEFAULT 0,
    p_status text DEFAULT 'confirmed'::text,
    p_notes text DEFAULT NULL::text,
    p_items jsonb DEFAULT '[]'::jsonb,
    p_warehouse_id text DEFAULT NULL::text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_purchase_id uuid;
    v_invoice_number text;
    v_item jsonb;
    v_subtotal numeric := 0;
    v_batch_id uuid;
    v_batch_number text;
    v_current_stock numeric;
    v_new_wac numeric;
    v_seq_num integer;
    v_item_id uuid;
    v_material_id uuid;
    v_company_id UUID;
    v_journal_payload JSONB;
    v_result JSONB;
BEGIN
    if auth.uid() is null then
        raise exception 'User not authenticated';
    end if;
    
    v_company_id := public.get_current_company_id();

    v_invoice_number := 'PUR-' || to_char(now(), 'YYYYMMDD') || '-' || lpad(
        (SELECT COALESCE(MAX(CAST(substring(invoice_number FROM 14) AS integer)), 0) + 1
         FROM public.purchase_invoices
         WHERE invoice_number LIKE 'PUR-' || to_char(now(), 'YYYYMMDD') || '-%')::text, 4, '0');

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_subtotal := v_subtotal + ((v_item->>'quantity')::numeric * (v_item->>'unit_cost')::numeric);
    END LOOP;

    INSERT INTO public.purchase_invoices (
        supplier_id, invoice_number, invoice_date, due_date,
        subtotal, tax_percent, tax_amount, discount_amount,
        total_amount, paid_amount, remaining_amount,
        payment_status, status, notes, user_id, warehouse_id
    ) VALUES (
        p_supplier_id::uuid, v_invoice_number, p_purchase_date::date,
        (p_purchase_date::date + interval '30 days')::date,
        v_subtotal, 0, 0, p_discount_amount,
        p_total_amount, p_paid_amount, GREATEST(p_total_amount - p_paid_amount, 0),
        CASE WHEN p_paid_amount >= p_total_amount THEN 'paid' WHEN p_paid_amount > 0 THEN 'partial' ELSE 'unpaid' END,
        p_status, p_notes, auth.uid(), p_warehouse_id::uuid
    ) RETURNING id INTO v_purchase_id;

    v_seq_num := 1;
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_material_id := (v_item->>'product_id')::uuid;

        INSERT INTO public.purchase_invoice_items (
            purchase_invoice_id, raw_material_id, quantity, unit_cost, total_cost
        ) VALUES (
            v_purchase_id, v_material_id,
            (v_item->>'quantity')::numeric, (v_item->>'unit_cost')::numeric,
            (v_item->>'quantity')::numeric * (v_item->>'unit_cost')::numeric
        ) RETURNING id INTO v_item_id;

        v_batch_number := 'B-' || v_invoice_number || '-' || v_seq_num::text;
        INSERT INTO public.stock_batches (
            batch_number, product_id, supplier_id, warehouse_id, purchase_invoice_id,
            quantity, remaining_quantity, purchase_cost, average_cost, status
        ) VALUES (
            v_batch_number, v_material_id, p_supplier_id::uuid, p_warehouse_id::uuid, v_purchase_id,
            (v_item->>'quantity')::numeric, (v_item->>'quantity')::numeric,
            (v_item->>'unit_cost')::numeric, (v_item->>'unit_cost')::numeric, 'active'
        ) RETURNING id INTO v_batch_id;

        SELECT COALESCE(quantity, 0) INTO v_current_stock
        FROM public.raw_materials WHERE id = v_material_id;

        INSERT INTO public.stock_movements (
            movement_type, product_id, batch_id, from_warehouse_id, to_warehouse_id,
            quantity, before_quantity, after_quantity, unit_cost, total_cost,
            reference_type, reference_id, description
        ) VALUES (
            'purchase', v_material_id, v_batch_id, null, p_warehouse_id::uuid,
            (v_item->>'quantity')::numeric, v_current_stock, v_current_stock + (v_item->>'quantity')::numeric,
            (v_item->>'unit_cost')::numeric, (v_item->>'quantity')::numeric * (v_item->>'unit_cost')::numeric,
            'purchase_invoice', v_purchase_id, 'Purchase ' || v_invoice_number
        );

        UPDATE public.raw_materials
        SET quantity = quantity + (v_item->>'quantity')::numeric,
            default_purchase_price = (v_item->>'unit_cost')::numeric
        WHERE id = v_material_id;

        SELECT COALESCE(SUM(remaining_quantity * purchase_cost) / NULLIF(SUM(remaining_quantity), 0), 0)
        INTO v_new_wac
        FROM public.stock_batches
        WHERE product_id = v_material_id AND status = 'active';

        UPDATE public.raw_materials
        SET default_purchase_price = COALESCE(NULLIF(v_new_wac, 0), default_purchase_price)
        WHERE id = v_material_id;

        v_seq_num := v_seq_num + 1;
    END LOOP;

    -- Update supplier balance for the FULL invoice amount
    UPDATE public.suppliers
    SET outstanding_balance = COALESCE(outstanding_balance, 0) + p_total_amount
    WHERE id = p_supplier_id::uuid;

    -- Enterprise Journal for the Invoice (Dr INVENTORY, Cr AP)
    IF p_total_amount > 0 THEN
        v_journal_payload := jsonb_build_object(
            'company_id', v_company_id,
            'document_type', 'PURCHASE_WORKFLOW',
            'posting_date', p_purchase_date::date,
            'reference', v_invoice_number,
            'description', 'Purchase Invoice ' || v_invoice_number,
            'currency', jsonb_build_object('code', 'EGP', 'exchange_rate', 1.0),
            'idempotency_key', 'pur_inv_' || v_purchase_id || '_' || EXTRACT(EPOCH FROM clock_timestamp())::BIGINT::TEXT,
            'lines', jsonb_build_array(
                jsonb_build_object('role', 'INVENTORY', 'debit', p_total_amount, 'credit', 0, 'description', 'Inventory Receipt'),
                jsonb_build_object('role', 'AP', 'debit', 0, 'credit', p_total_amount, 'description', 'Accounts Payable')
            )
        );
        PERFORM public.rpc_post_journal(v_journal_payload);
    END IF;

    -- If there's an immediate payment, process it via CASH_PAYMENT
    IF p_paid_amount > 0 THEN
        -- The payment decreases the supplier balance that was just increased
        UPDATE public.suppliers
        SET outstanding_balance = COALESCE(outstanding_balance, 0) - p_paid_amount
        WHERE id = p_supplier_id::uuid;
        
        v_journal_payload := jsonb_build_object(
            'company_id', v_company_id,
            'document_type', 'CASH_PAYMENT',
            'posting_date', p_purchase_date::date,
            'reference', v_invoice_number,
            'description', 'Payment for ' || v_invoice_number,
            'currency', jsonb_build_object('code', 'EGP', 'exchange_rate', 1.0),
            'idempotency_key', 'pur_pay_' || v_purchase_id || '_' || EXTRACT(EPOCH FROM clock_timestamp())::BIGINT::TEXT,
            'lines', jsonb_build_array(
                jsonb_build_object('role', 'AP', 'debit', p_paid_amount, 'credit', 0, 'description', 'Supplier Payment'),
                jsonb_build_object('role', 'CASH', 'debit', 0, 'credit', p_paid_amount, 'description', 'Cash Outflow')
            )
        );
        PERFORM public.rpc_post_journal(v_journal_payload);

        INSERT INTO public.cashbox_transactions (
            transaction_type, amount, currency_id, reference_type, 
            reference_id, description, payment_method, created_by
        )
        VALUES (
            'expense', p_paid_amount, (SELECT currency_id FROM public.suppliers WHERE id = p_supplier_id::uuid), 
            'purchase_invoice', v_purchase_id, 'Payment for ' || v_invoice_number, 'cash', auth.uid()
        );
    END IF;

    RETURN v_purchase_id;
END;
$$;

COMMIT;
