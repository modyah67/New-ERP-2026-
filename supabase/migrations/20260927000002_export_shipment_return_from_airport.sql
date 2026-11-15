-- ==============================================================================
-- Migration: 20260927000002_export_shipment_return_from_airport.sql
-- Description: Export Shipment Return from Airport & Waste Settlement Workflow
--              - Table: export_shipment_returns
--              - Trigger: exclude returned/cancelled shipments from packing order sold_cartons
--              - Function: rpc_process_export_shipment_return
-- ==============================================================================

BEGIN;

-- 0. Update export_shipments status check constraint to include returned_from_airport
ALTER TABLE public.export_shipments
DROP CONSTRAINT IF EXISTS export_shipments_status_check;

ALTER TABLE public.export_shipments
ADD CONSTRAINT export_shipments_status_check
CHECK (status = ANY (ARRAY[
    'draft'::text,
    'booked'::text,
    'loaded'::text,
    'sailed'::text,
    'arrived'::text,
    'completed'::text,
    'cancelled'::text,
    'preparing'::text,
    'ready'::text,
    'shipped'::text,
    'in_transit'::text,
    'delivered'::text,
    'returned_from_airport'::text,
    'returned'::text,
    'rejected'::text
]));

-- 0.b Update packing_orders status check constraint to include returned
ALTER TABLE public.packing_orders
DROP CONSTRAINT IF EXISTS packing_orders_status_check;

ALTER TABLE public.packing_orders
ADD CONSTRAINT packing_orders_status_check
CHECK (status = ANY (ARRAY[
    'draft'::text,
    'pending'::text,
    'in_progress'::text,
    'completed'::text,
    'cancelled'::text,
    'returned'::text
]));

-- 0.c Ensure return_journal_entry_id on export_shipments table
ALTER TABLE public.export_shipments
ADD COLUMN IF NOT EXISTS return_journal_entry_id BIGINT REFERENCES public.journal_entries(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_export_shipments_return_je
ON public.export_shipments(return_journal_entry_id);

-- 1. Register document type for sequence numbering if not present
INSERT INTO public.sys_document_types (code, name, prefix, is_active)
VALUES ('export_return', 'Export Shipment Return', 'EXR', true)
ON CONFLICT (code) DO NOTHING;

-- 2. Create export_shipment_returns table
CREATE TABLE IF NOT EXISTS public.export_shipment_returns (
    id BIGSERIAL PRIMARY KEY,
    return_number TEXT NOT NULL UNIQUE,
    shipment_id BIGINT NOT NULL REFERENCES public.export_shipments(id) ON DELETE CASCADE,
    station_id BIGINT REFERENCES public.stations(id),
    return_date DATE NOT NULL DEFAULT CURRENT_DATE,
    cost_center_id TEXT,
    total_cartons INTEGER NOT NULL DEFAULT 0,
    intact_cartons INTEGER NOT NULL DEFAULT 0,
    damaged_cartons INTEGER NOT NULL DEFAULT 0,
    total_crop_weight NUMERIC(15,2) NOT NULL DEFAULT 0,
    intact_crop_weight NUMERIC(15,2) NOT NULL DEFAULT 0,
    damaged_crop_weight NUMERIC(15,2) NOT NULL DEFAULT 0,
    crop_waste_cost NUMERIC(15,2) NOT NULL DEFAULT 0,
    material_waste_cost NUMERIC(15,2) NOT NULL DEFAULT 0,
    extra_expenses_cost NUMERIC(15,2) NOT NULL DEFAULT 0,
    reversed_revenue_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
    reversed_revenue_egp NUMERIC(15,2) NOT NULL DEFAULT 0,
    reversed_customer_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
    reversed_customer_egp NUMERIC(15,2) NOT NULL DEFAULT 0,
    currency TEXT NOT NULL DEFAULT 'USD',
    exchange_rate NUMERIC(15,6) NOT NULL DEFAULT 1.0,
    return_reason TEXT,
    notes TEXT,
    raw_data JSONB,
    journal_entry_id BIGINT REFERENCES public.journal_entries(id) ON DELETE SET NULL,
    company_id UUID REFERENCES public.sys_companies(id),
    created_by UUID DEFAULT auth.uid(),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_export_shipment_returns_shipment 
ON public.export_shipment_returns(shipment_id);

CREATE INDEX IF NOT EXISTS idx_export_shipment_returns_date 
ON public.export_shipment_returns(return_date);

-- 3. Enhance trg_sync_shipment_items_sold_cartons to ignore returned/cancelled shipments
CREATE OR REPLACE FUNCTION public.trg_sync_shipment_items_sold_cartons()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_po_id bigint;
  v_line_id bigint;
BEGIN
  v_po_id := COALESCE(NEW.packing_order_id, OLD.packing_order_id);
  v_line_id := COALESCE(NEW.packing_order_line_id, OLD.packing_order_line_id);

  IF v_po_id IS NOT NULL THEN
    UPDATE public.packing_orders
    SET sold_cartons = COALESCE((
      SELECT SUM(esi.quantity) 
      FROM public.export_shipment_items esi
      JOIN public.export_shipments es ON es.id = esi.shipment_id
      WHERE esi.packing_order_id = v_po_id
        AND es.status NOT IN ('cancelled', 'returned_from_airport', 'rejected')
    ), 0)
    WHERE id = v_po_id;
  END IF;

  IF v_line_id IS NOT NULL THEN
    UPDATE public.packing_order_lines
    SET sold_cartons = COALESCE((
      SELECT SUM(esi.quantity) 
      FROM public.export_shipment_items esi
      JOIN public.export_shipments es ON es.id = esi.shipment_id
      WHERE esi.packing_order_line_id = v_line_id
        AND es.status NOT IN ('cancelled', 'returned_from_airport', 'rejected')
    ), 0)
    WHERE id = v_line_id;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- 4. Status change trigger on export_shipments to automatically re-sync packing orders
CREATE OR REPLACE FUNCTION public.trg_sync_export_shipment_status_sold_cartons()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF (OLD.status IS DISTINCT FROM NEW.status) THEN
    -- Update all packing orders linked to this shipment's items
    UPDATE public.packing_orders po
    SET sold_cartons = COALESCE((
      SELECT SUM(esi.quantity)
      FROM public.export_shipment_items esi
      JOIN public.export_shipments es ON es.id = esi.shipment_id
      WHERE esi.packing_order_id = po.id
        AND es.status NOT IN ('cancelled', 'returned_from_airport', 'rejected')
    ), 0)
    WHERE po.id IN (
      SELECT DISTINCT esi2.packing_order_id 
      FROM public.export_shipment_items esi2 
      WHERE esi2.shipment_id = NEW.id AND esi2.packing_order_id IS NOT NULL
    );

    -- Update packing order lines
    UPDATE public.packing_order_lines pol
    SET sold_cartons = COALESCE((
      SELECT SUM(esi.quantity)
      FROM public.export_shipment_items esi
      JOIN public.export_shipments es ON es.id = esi.shipment_id
      WHERE esi.packing_order_line_id = pol.id
        AND es.status NOT IN ('cancelled', 'returned_from_airport', 'rejected')
    ), 0)
    WHERE pol.id IN (
      SELECT DISTINCT esi2.packing_order_line_id 
      FROM public.export_shipment_items esi2 
      WHERE esi2.shipment_id = NEW.id AND esi2.packing_order_line_id IS NOT NULL
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_export_shipments_status_sold_cartons ON public.export_shipments;
CREATE TRIGGER trg_export_shipments_status_sold_cartons
AFTER UPDATE OF status ON public.export_shipments
FOR EACH ROW EXECUTE FUNCTION public.trg_sync_export_shipment_status_sold_cartons();

-- 5. Stored Procedure: rpc_process_export_shipment_return
CREATE OR REPLACE FUNCTION public.rpc_process_export_shipment_return(
    p_shipment_id       BIGINT,
    p_station_id        BIGINT,
    p_return_date       DATE,
    p_cost_center_id    TEXT,
    p_return_reason     TEXT,
    p_items             JSONB,
    p_extra_expenses    JSONB DEFAULT '[]'::jsonb,
    p_notes             TEXT DEFAULT '',
    p_user_id           UUID DEFAULT auth.uid()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_shipment RECORD;
    v_customer RECORD;
    v_company_id UUID;
    v_return_id BIGINT;
    v_return_no TEXT;
    v_total_cartons INT := 0;
    v_intact_cartons INT := 0;
    v_damaged_cartons INT := 0;
    v_total_crop_weight NUMERIC := 0;
    v_intact_crop_weight NUMERIC := 0;
    v_damaged_crop_weight NUMERIC := 0;
    v_crop_waste_cost NUMERIC := 0;
    v_material_waste_cost NUMERIC := 0;
    v_extra_expenses_cost NUMERIC := 0;
    v_total_revenue NUMERIC := 0;
    v_discount NUMERIC := 0;
    v_net_revenue NUMERIC := 0;
    v_exchange_rate NUMERIC := 1.0;
    v_currency TEXT := 'USD';
    v_item JSONB;
    v_exp JSONB;
    v_je_id BIGINT;
    v_je_lines JSONB := '[]'::jsonb;
    v_ar_acct BIGINT;
    v_rev_acct BIGINT;
    v_disc_acct BIGINT;
    v_crop_inv_acct BIGINT;
    v_material_inv_acct BIGINT;
    v_crop_waste_acct BIGINT;
    v_material_waste_acct BIGINT;
    v_cogs_acct BIGINT;
    v_expense_acct BIGINT;
    v_intact_crop_cost NUMERIC := 0;
    v_intact_material_cost NUMERIC := 0;
    v_total_goods_cost NUMERIC := 0;
    v_desc TEXT;
    v_item_crop_waste NUMERIC;
    v_item_mat_waste NUMERIC;
    v_item_intact_crop NUMERIC;
    v_item_intact_mat NUMERIC;
    v_po_id BIGINT;
    v_po_line_id BIGINT;
    v_product_name TEXT;
    v_product_code TEXT;
    v_fruit_type_id INT;
    v_raw_material_id TEXT;
    v_carton_prod_name TEXT;
    v_carton_prod_code TEXT;
    v_target_fruit_id BIGINT;
    v_target_fruit_name TEXT;
    v_target_fruit_code TEXT;
    v_target_carton_id BIGINT;
    v_target_carton_name TEXT;
    v_target_carton_code TEXT;
    v_exp_amount NUMERIC := 0;
    v_exp_name TEXT;
    v_exp_supplier_id TEXT;
    v_exp_supplier_name TEXT;
    v_exp_supplier_type TEXT;
    v_exp_notes TEXT;
    v_supp_account_id BIGINT;
    v_clearing_acct BIGINT;
    v_temp_name TEXT;
    v_temp_type TEXT;
    v_revenue_code TEXT;
    v_final_cc_id TEXT;
    v_final_cc_name TEXT;
    v_i INT;
BEGIN
    -- 1. Fetch and validate shipment
    SELECT * INTO v_shipment FROM public.export_shipments WHERE id = p_shipment_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'الشحنة التصديرية غير موجودة');
    END IF;

    IF v_shipment.status = 'returned_from_airport' THEN
        RETURN jsonb_build_object('success', false, 'error', 'تم تسجيل رجوع هذه الشحنة من المطار مسبقاً');
    END IF;

    IF v_shipment.status = 'cancelled' THEN
        RETURN jsonb_build_object('success', false, 'error', 'لا يمكن تسجيل رجوع شحنة ملغاة');
    END IF;

    -- Resolve effective cost center ID
    IF p_cost_center_id IS NOT NULL AND p_cost_center_id <> '' THEN
        v_final_cc_id := p_cost_center_id;
    ELSE
        SELECT code INTO v_final_cc_id FROM public.cost_centers WHERE code = 'CC-MANGO-2026-2027' OR name_ar LIKE '%مانجو%' LIMIT 1;
        IF v_final_cc_id IS NULL THEN
            v_final_cc_id := 'CC-MANGO-2026-2027';
        END IF;
    END IF;

    SELECT name_ar INTO v_final_cc_name FROM public.cost_centers WHERE code = v_final_cc_id OR id::text = v_final_cc_id LIMIT 1;
    IF v_final_cc_name IS NULL THEN
        v_final_cc_name := 'مركز تكلفة الموسم';
    END IF;

    v_company_id := v_shipment.company_id;
    IF v_company_id IS NULL THEN
        SELECT id INTO v_company_id FROM public.sys_companies WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 1;
    END IF;

    v_currency := COALESCE(v_shipment.currency, 'USD');
    v_exchange_rate := COALESCE(v_shipment.exchange_rate, 1.0);
    IF v_exchange_rate <= 0 THEN v_exchange_rate := 1.0; END IF;

    -- 2. Generate Return Sequence Number
    BEGIN
        v_return_no := public.fn_get_next_sequence(v_company_id, 'export_return', NULL, NULL);
    EXCEPTION WHEN OTHERS THEN
        v_return_no := NULL;
    END;

    IF v_return_no IS NULL OR v_return_no = '' THEN
        SELECT COALESCE(MAX(id), 0) + 1 INTO v_return_id FROM public.export_shipment_returns;
        v_return_no := 'EXR-' || v_return_id::TEXT;
    END IF;

    -- 3. Calculate Item Breakdown & Stock Returns (MATCH EXISTING STATION PRODUCT CARDS ONLY)
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_total_cartons := v_total_cartons + COALESCE((v_item->>'total_cartons')::INT, 0);
        v_intact_cartons := v_intact_cartons + COALESCE((v_item->>'intact_cartons')::INT, 0);
        v_damaged_cartons := v_damaged_cartons + COALESCE((v_item->>'damaged_cartons')::INT, 0);

        v_total_crop_weight := v_total_crop_weight + COALESCE((v_item->>'total_weight')::NUMERIC, 0);
        v_intact_crop_weight := v_intact_crop_weight + COALESCE((v_item->>'intact_weight')::NUMERIC, 0);
        v_damaged_crop_weight := v_damaged_crop_weight + COALESCE((v_item->>'damaged_weight')::NUMERIC, 0);

        v_item_intact_crop := COALESCE((v_item->>'intact_weight')::NUMERIC, 0) * COALESCE((v_item->>'crop_unit_cost')::NUMERIC, 0);
        v_item_crop_waste := COALESCE((v_item->>'damaged_weight')::NUMERIC, 0) * COALESCE((v_item->>'crop_unit_cost')::NUMERIC, 0);

        v_item_intact_mat := COALESCE((v_item->>'intact_cartons')::NUMERIC, 0) * COALESCE((v_item->>'carton_unit_cost')::NUMERIC, 0);
        v_item_mat_waste := COALESCE((v_item->>'damaged_cartons')::NUMERIC, 0) * COALESCE((v_item->>'carton_unit_cost')::NUMERIC, 0);

        v_intact_crop_cost := v_intact_crop_cost + v_item_intact_crop;
        v_crop_waste_cost := v_crop_waste_cost + v_item_crop_waste;
        v_intact_material_cost := v_intact_material_cost + v_item_intact_mat;
        v_material_waste_cost := v_material_waste_cost + v_item_mat_waste;

        v_product_name := COALESCE(v_item->>'product_name', 'محصول مرتجع');
        v_product_code := COALESCE(v_item->>'product_code', '');
        v_fruit_type_id := (v_item->>'fruit_type_id')::INT;
        v_carton_prod_name := COALESCE(v_item->>'carton_product_name', '');
        v_carton_prod_code := COALESCE(v_item->>'carton_product_code', '');
        v_raw_material_id := v_item->>'raw_material_id';

        -- A. Restock Intact Crop: Find EXACT existing card in station_products (NEVER create duplicate cards)
        IF COALESCE((v_item->>'intact_weight')::NUMERIC, 0) > 0 AND p_station_id IS NOT NULL THEN
            v_target_fruit_id := NULL;
            v_target_fruit_name := v_product_name;
            v_target_fruit_code := v_product_code;

            SELECT id, product_name, product_code, fruit_type_id
            INTO v_target_fruit_id, v_target_fruit_name, v_target_fruit_code, v_fruit_type_id
            FROM public.station_products
            WHERE station_id = p_station_id
              AND (
                (v_fruit_type_id IS NOT NULL AND fruit_type_id = v_fruit_type_id)
                OR (v_product_code <> '' AND product_code = v_product_code AND (item_type = 'fruit' OR fruit_type_id IS NOT NULL))
                OR (product_name = v_product_name)
                OR (product_name ILIKE '%' || v_product_name || '%')
                OR (v_product_name ILIKE '%' || product_name || '%')
              )
            ORDER BY 
              CASE WHEN fruit_type_id = v_fruit_type_id THEN 1
                   WHEN product_code = v_product_code AND v_product_code <> '' THEN 2
                   WHEN product_name = v_product_name THEN 3
                   ELSE 4 END ASC
            LIMIT 1;

            -- Insert FIFO batch matching the EXACT station product card
            INSERT INTO public.station_product_batches (
                station_id, product_name, product_code, quantity, remaining_quantity,
                unit_cost, currency, exchange_rate, source_type, source_date,
                supplier_name, item_type, fruit_type_id, created_at
            ) VALUES (
                p_station_id, v_target_fruit_name, COALESCE(v_target_fruit_code, ''),
                (v_item->>'intact_weight')::NUMERIC, (v_item->>'intact_weight')::NUMERIC,
                COALESCE((v_item->>'crop_unit_cost')::NUMERIC, 0), 'EGP', 1.0,
                'export_return', COALESCE(p_return_date::timestamptz, now()),
                'مرتجع شحنة تصدير ' || v_shipment.shipment_no, 'fruit',
                v_fruit_type_id, now()
            );

            -- Update existing station_products card quantity directly
            IF v_target_fruit_id IS NOT NULL THEN
                UPDATE public.station_products
                SET quantity = quantity + (v_item->>'intact_weight')::NUMERIC,
                    updated_at = now()
                WHERE id = v_target_fruit_id;
            ELSE
                INSERT INTO public.station_products (
                    station_id, product_name, product_code, quantity, fruit_type_id, item_type, unit
                ) VALUES (
                    p_station_id, v_target_fruit_name, COALESCE(v_target_fruit_code, ''),
                    (v_item->>'intact_weight')::NUMERIC, v_fruit_type_id, 'fruit', 'kg'
                );
            END IF;
        END IF;

        -- B. Restock Intact Cartons: Find EXACT existing card in station_products (NEVER create duplicate cards)
        IF COALESCE((v_item->>'intact_cartons')::INT, 0) > 0 AND p_station_id IS NOT NULL THEN
            v_target_carton_id := NULL;
            v_target_carton_name := v_carton_prod_name;
            v_target_carton_code := v_carton_prod_code;

            SELECT id, product_name, product_code, raw_material_id::text
            INTO v_target_carton_id, v_target_carton_name, v_target_carton_code, v_raw_material_id
            FROM public.station_products
            WHERE station_id = p_station_id
              AND (
                (v_raw_material_id IS NOT NULL AND v_raw_material_id <> '' AND raw_material_id::text = v_raw_material_id)
                OR (v_carton_prod_code <> '' AND product_code = v_carton_prod_code AND item_type = 'material')
                OR (v_carton_prod_name <> '' AND product_name = v_carton_prod_name)
                OR (v_carton_prod_name <> '' AND (product_name ILIKE '%' || v_carton_prod_name || '%' OR v_carton_prod_name ILIKE '%' || product_name || '%'))
                OR (item_type = 'material' AND (product_name ILIKE '%كرتون%' OR product_name ILIKE '%carton%'))
              )
            ORDER BY
              CASE WHEN raw_material_id::text = v_raw_material_id AND v_raw_material_id IS NOT NULL THEN 1
                   WHEN product_code = v_carton_prod_code AND v_carton_prod_code <> '' THEN 2
                   WHEN product_name = v_carton_prod_name AND v_carton_prod_name <> '' THEN 3
                   ELSE 4 END ASC
            LIMIT 1;

            IF v_target_carton_name IS NULL OR v_target_carton_name = '' THEN
                v_target_carton_name := COALESCE(NULLIF(v_carton_prod_name, ''), 'كراتين تعبئة');
            END IF;

            -- Insert FIFO batch matching the EXACT carton product card
            INSERT INTO public.station_product_batches (
                station_id, product_name, product_code, quantity, remaining_quantity,
                unit_cost, currency, exchange_rate, source_type, source_date,
                supplier_name, item_type, raw_material_id, created_at
            ) VALUES (
                p_station_id, v_target_carton_name, COALESCE(v_target_carton_code, ''),
                (v_item->>'intact_cartons')::NUMERIC, (v_item->>'intact_cartons')::NUMERIC,
                COALESCE((v_item->>'carton_unit_cost')::NUMERIC, 0), 'EGP', 1.0,
                'export_return', COALESCE(p_return_date::timestamptz, now()),
                'مرتجع شحنة تصدير ' || v_shipment.shipment_no, 'material',
                CASE WHEN v_raw_material_id IS NOT NULL AND v_raw_material_id <> '' THEN v_raw_material_id::uuid ELSE NULL END,
                now()
            );

            -- Update existing station_products card quantity directly
            IF v_target_carton_id IS NOT NULL THEN
                UPDATE public.station_products
                SET quantity = quantity + (v_item->>'intact_cartons')::NUMERIC,
                    updated_at = now()
                WHERE id = v_target_carton_id;
            ELSE
                INSERT INTO public.station_products (
                    station_id, product_name, product_code, quantity, raw_material_id, item_type, unit
                ) VALUES (
                    p_station_id, v_target_carton_name, COALESCE(v_target_carton_code, ''),
                    (v_item->>'intact_cartons')::NUMERIC,
                    CASE WHEN v_raw_material_id IS NOT NULL AND v_raw_material_id <> '' THEN v_raw_material_id::uuid ELSE NULL END,
                    'material', 'piece'
                );
            END IF;
        END IF;
    END LOOP;

    -- Extra return freight/labor expenses
    FOR v_exp IN SELECT * FROM jsonb_array_elements(p_extra_expenses)
    LOOP
        v_extra_expenses_cost := v_extra_expenses_cost + COALESCE((v_exp->>'amount')::NUMERIC, 0);
    END LOOP;

    v_total_goods_cost := v_intact_crop_cost + v_intact_material_cost + v_crop_waste_cost + v_material_waste_cost;

    -- 4. Calculate Customer & Revenue Reversal Amounts
    SELECT COALESCE(SUM(amount), 0) INTO v_total_revenue
    FROM public.export_shipment_items WHERE shipment_id = p_shipment_id;

    v_discount := COALESCE(v_shipment.discount_amount, 0);
    v_net_revenue := GREATEST(v_total_revenue - v_discount, 0);

    -- 5. Customer Balance & Ledger Reversal
    IF v_shipment.customer_id IS NOT NULL AND v_net_revenue > 0 THEN
        UPDATE public.customers
        SET balance = COALESCE(balance, 0) - v_net_revenue,
            updated_at = now()
        WHERE id = v_shipment.customer_id;

        v_desc := 'مرتجع شحنة تصدير من المطار رقم ' || v_shipment.shipment_no || ' (' || v_return_no || ')';
        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_text, description, created_by
        ) VALUES (
            'customer', v_shipment.customer_id::TEXT, 'credit', v_net_revenue,
            v_currency, 'export_return', v_return_no, v_desc, p_user_id
        );
    END IF;

    -- 6. Resolve Accounts for Journal Entries (Strictly Level 5 Leaf Accounts)
    -- Customer AR Account:
    SELECT c.account_id INTO v_ar_acct FROM public.customers c WHERE c.id = v_shipment.customer_id;
    IF v_ar_acct IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.accounts WHERE id = v_ar_acct AND is_leaf = true) THEN
        v_ar_acct := NULL;
    END IF;
    IF v_ar_acct IS NULL THEN
        SELECT id INTO v_ar_acct FROM public.accounts WHERE account_code = '12511' AND is_leaf = true LIMIT 1;
    END IF;
    IF v_ar_acct IS NULL THEN
        SELECT id INTO v_ar_acct FROM public.accounts WHERE account_code = '12512' AND is_leaf = true LIMIT 1;
    END IF;
    IF v_ar_acct IS NULL THEN
        SELECT id INTO v_ar_acct FROM public.accounts WHERE account_code LIKE '125%' AND is_leaf = true ORDER BY account_code LIMIT 1;
    END IF;

    -- Export Revenue Account:
    SELECT 
      CASE 
        WHEN bool_or(LOWER(COALESCE(product_name, invoice_product_name, '')) LIKE '%مانجو%' OR LOWER(COALESCE(product_name, invoice_product_name, '')) LIKE '%mango%') THEN '41112'
        WHEN bool_or(LOWER(COALESCE(product_name, invoice_product_name, '')) LIKE '%بلح%' OR LOWER(COALESCE(product_name, invoice_product_name, '')) LIKE '%date%') THEN '41113'
        WHEN bool_or(LOWER(COALESCE(product_name, invoice_product_name, '')) LIKE '%بلو%' OR LOWER(COALESCE(product_name, invoice_product_name, '')) LIKE '%blue%') THEN '41114'
        ELSE '41111'
      END INTO v_revenue_code
    FROM public.export_shipment_items
    WHERE shipment_id = p_shipment_id;

    SELECT id INTO v_rev_acct FROM public.accounts WHERE account_code = v_revenue_code AND is_leaf = true LIMIT 1;
    IF v_rev_acct IS NULL THEN
        SELECT id INTO v_rev_acct FROM public.accounts WHERE account_code LIKE '4111%' AND is_leaf = true ORDER BY account_code LIMIT 1;
    END IF;
    IF v_rev_acct IS NULL THEN
        SELECT id INTO v_rev_acct FROM public.accounts WHERE account_code LIKE '411%' AND is_leaf = true ORDER BY account_code LIMIT 1;
    END IF;
    IF v_rev_acct IS NULL THEN
        SELECT id INTO v_rev_acct FROM public.accounts WHERE account_type = 'revenue' AND is_leaf = true ORDER BY account_code LIMIT 1;
    END IF;

    -- Discount Account:
    SELECT id INTO v_disc_acct FROM public.accounts WHERE account_code = '41131' AND is_leaf = true LIMIT 1;
    IF v_disc_acct IS NULL THEN
        SELECT id INTO v_disc_acct FROM public.accounts WHERE account_code LIKE '4113%' AND is_leaf = true LIMIT 1;
    END IF;
    IF v_disc_acct IS NULL THEN
        v_disc_acct := v_rev_acct;
    END IF;

    -- Raw Crop Inventory: 12413 / 12412
    SELECT id INTO v_crop_inv_acct FROM public.accounts WHERE account_code = '12413' AND is_leaf = true LIMIT 1;
    IF v_crop_inv_acct IS NULL THEN
        SELECT id INTO v_crop_inv_acct FROM public.accounts WHERE account_code = '12412' AND is_leaf = true LIMIT 1;
    END IF;
    IF v_crop_inv_acct IS NULL THEN
        SELECT id INTO v_crop_inv_acct FROM public.accounts WHERE account_code LIKE '1241%' AND is_leaf = true ORDER BY account_code LIMIT 1;
    END IF;

    -- Material Inventory: 12411 / 12414
    SELECT id INTO v_material_inv_acct FROM public.accounts WHERE account_code = '12411' AND is_leaf = true LIMIT 1;
    IF v_material_inv_acct IS NULL THEN
        SELECT id INTO v_material_inv_acct FROM public.accounts WHERE account_code = '12414' AND is_leaf = true LIMIT 1;
    END IF;
    IF v_material_inv_acct IS NULL THEN
        SELECT id INTO v_material_inv_acct FROM public.accounts WHERE account_code LIKE '1241%' AND is_leaf = true ORDER BY account_code LIMIT 1;
    END IF;

    -- Crop Waste Expense: 34110 / 12414 / 51102
    SELECT id INTO v_crop_waste_acct FROM public.accounts WHERE account_code = '34110' AND is_leaf = true LIMIT 1;
    IF v_crop_waste_acct IS NULL THEN
        SELECT id INTO v_crop_waste_acct FROM public.accounts WHERE account_code = '12414' AND is_leaf = true LIMIT 1;
    END IF;
    IF v_crop_waste_acct IS NULL THEN
        SELECT id INTO v_crop_waste_acct FROM public.accounts WHERE account_code = '51102' AND is_leaf = true LIMIT 1;
    END IF;
    IF v_crop_waste_acct IS NULL THEN
        SELECT id INTO v_crop_waste_acct FROM public.accounts WHERE (account_code LIKE '341%' OR account_code LIKE '511%') AND is_leaf = true ORDER BY account_code LIMIT 1;
    END IF;

    -- Material Waste Expense: 34110 / 33111 / 12414 / 51104
    SELECT id INTO v_material_waste_acct FROM public.accounts WHERE account_code = '34110' AND is_leaf = true LIMIT 1;
    IF v_material_waste_acct IS NULL THEN
        SELECT id INTO v_material_waste_acct FROM public.accounts WHERE account_code = '33111' AND is_leaf = true LIMIT 1;
    END IF;
    IF v_material_waste_acct IS NULL THEN
        SELECT id INTO v_material_waste_acct FROM public.accounts WHERE account_code = '12414' AND is_leaf = true LIMIT 1;
    END IF;
    IF v_material_waste_acct IS NULL THEN
        SELECT id INTO v_material_waste_acct FROM public.accounts WHERE account_code = '51104' AND is_leaf = true LIMIT 1;
    END IF;

    -- COGS / Goods Clearing: 34111 / 12413
    SELECT id INTO v_cogs_acct FROM public.accounts WHERE account_code = '34111' AND is_leaf = true LIMIT 1;
    IF v_cogs_acct IS NULL THEN
        SELECT id INTO v_cogs_acct FROM public.accounts WHERE account_code LIKE '3411%' AND is_leaf = true LIMIT 1;
    END IF;
    IF v_cogs_acct IS NULL THEN
        SELECT id INTO v_cogs_acct FROM public.accounts WHERE account_code LIKE '34%' AND is_leaf = true ORDER BY account_code LIMIT 1;
    END IF;

    -- Return Freight / Expense Account: 34114 / 34110 / 51101
    SELECT id INTO v_expense_acct FROM public.accounts WHERE account_code = '34114' AND is_leaf = true LIMIT 1;
    IF v_expense_acct IS NULL THEN
        SELECT id INTO v_expense_acct FROM public.accounts WHERE account_code = '34110' AND is_leaf = true LIMIT 1;
    END IF;
    IF v_expense_acct IS NULL THEN
        SELECT id INTO v_expense_acct FROM public.accounts WHERE account_code = '51101' AND is_leaf = true LIMIT 1;
    END IF;
    IF v_expense_acct IS NULL THEN
        SELECT id INTO v_expense_acct FROM public.accounts WHERE (account_code LIKE '341%' OR account_code LIKE '511%') AND is_leaf = true ORDER BY account_code LIMIT 1;
    END IF;

    -- 7. Build Journal Entry Lines
    v_je_lines := '[]'::jsonb;
    v_desc := 'قيد تسوية رجوع شحنة تصدير رقم ' || v_shipment.shipment_no || ' (' || v_return_no || ')';

    -- Part A: Reverse Export Revenue & Customer Receivable
    IF v_net_revenue > 0 AND v_rev_acct IS NOT NULL AND v_ar_acct IS NOT NULL THEN
        -- Debit: Export Sales Revenue (Reversing revenue)
        v_je_lines := v_je_lines || jsonb_build_array(
            jsonb_build_object(
                'account_id', v_rev_acct,
                'debit', (v_total_revenue * v_exchange_rate),
                'credit', 0,
                'base_debit', (v_total_revenue * v_exchange_rate),
                'base_credit', 0,
                'currency', 'EGP',
                'description', v_desc || ' - إلغاء إيراد التصدير',
                'cost_center_id', p_cost_center_id
            )
        );

        -- If discount existed, Credit Discount
        IF v_discount > 0 THEN
            v_je_lines := v_je_lines || jsonb_build_array(
                jsonb_build_object(
                    'account_id', COALESCE(v_disc_acct, v_rev_acct),
                    'debit', 0,
                    'credit', (v_discount * v_exchange_rate),
                    'base_debit', 0,
                    'base_credit', (v_discount * v_exchange_rate),
                    'currency', 'EGP',
                    'description', v_desc || ' - إلغاء الخصم المسموح به'
                )
            );
        END IF;

        -- Credit: Customer Receivable (Reversing customer debt)
        v_je_lines := v_je_lines || jsonb_build_array(
            jsonb_build_object(
                'account_id', v_ar_acct,
                'debit', 0,
                'credit', (v_net_revenue * v_exchange_rate),
                'base_debit', 0,
                'base_credit', (v_net_revenue * v_exchange_rate),
                'currency', 'EGP',
                'description', v_desc || ' - إلغاء مديونية العميل'
            )
        );
    END IF;

    -- Part B: Inventory Restock & Waste Allocation
    IF v_total_goods_cost > 0 THEN
        -- Debit: Intact Raw Crop to inventory
        IF v_intact_crop_cost > 0 AND v_crop_inv_acct IS NOT NULL THEN
            v_je_lines := v_je_lines || jsonb_build_array(
                jsonb_build_object(
                    'account_id', v_crop_inv_acct,
                    'debit', v_intact_crop_cost,
                    'credit', 0,
                    'base_debit', v_intact_crop_cost,
                    'base_credit', 0,
                    'currency', 'EGP',
                    'description', v_desc || ' - رد محصول خام سليم للمخزن (' || v_intact_crop_weight || ' كجم)'
                )
            );
        END IF;

        -- Debit: Intact Cartons to inventory
        IF v_intact_material_cost > 0 AND v_material_inv_acct IS NOT NULL THEN
            v_je_lines := v_je_lines || jsonb_build_array(
                jsonb_build_object(
                    'account_id', v_material_inv_acct,
                    'debit', v_intact_material_cost,
                    'credit', 0,
                    'base_debit', v_intact_material_cost,
                    'base_credit', 0,
                    'currency', 'EGP',
                    'description', v_desc || ' - رد كراتين تعبئة سليمة للمخزن (' || v_intact_cartons || ' كرتونة)'
                )
            );
        END IF;

        -- Debit: Crop Waste to Cost Center
        IF v_crop_waste_cost > 0 AND v_crop_waste_acct IS NOT NULL THEN
            v_je_lines := v_je_lines || jsonb_build_array(
                jsonb_build_object(
                    'account_id', v_crop_waste_acct,
                    'debit', v_crop_waste_cost,
                    'credit', 0,
                    'base_debit', v_crop_waste_cost,
                    'base_credit', 0,
                    'currency', 'EGP',
                    'description', v_desc || ' - مصروف هالك وتلف محصول (' || v_damaged_crop_weight || ' كجم)',
                    'cost_center_id', v_final_cc_id
                )
            );
        END IF;

        -- Debit: Material Waste to Cost Center
        IF v_material_waste_cost > 0 AND v_material_waste_acct IS NOT NULL THEN
            v_je_lines := v_je_lines || jsonb_build_array(
                jsonb_build_object(
                    'account_id', v_material_waste_acct,
                    'debit', v_material_waste_cost,
                    'credit', 0,
                    'base_debit', v_material_waste_cost,
                    'base_credit', 0,
                    'currency', 'EGP',
                    'description', v_desc || ' - مصروف هالك كراتين ومواد تعبئة (' || v_damaged_cartons || ' كرتونة)',
                    'cost_center_id', v_final_cc_id
                )
            );
        END IF;

        -- Credit: COGS / Finished Goods to offset the original goods cost
        IF v_cogs_acct IS NOT NULL THEN
            v_je_lines := v_je_lines || jsonb_build_array(
                jsonb_build_object(
                    'account_id', v_cogs_acct,
                    'debit', 0,
                    'credit', v_total_goods_cost,
                    'base_debit', 0,
                    'base_credit', v_total_goods_cost,
                    'currency', 'EGP',
                    'description', v_desc || ' - تسوية تكلفة بضاعة الشحنة المرتجعة'
                )
            );
        END IF;
    END IF;

    -- Part C: Extra Return Freight, Labor & Logistics Expenses
    IF p_extra_expenses IS NOT NULL AND jsonb_array_length(p_extra_expenses) > 0 THEN
        FOR v_exp IN SELECT * FROM jsonb_array_elements(p_extra_expenses)
        LOOP
            v_exp_amount := COALESCE((v_exp->>'amount')::NUMERIC, 0);
            IF v_exp_amount > 0 THEN
                v_exp_name := COALESCE(NULLIF(TRIM(v_exp->>'name'), ''), 'مصروفات رجوع شحنة إضافية');
                v_exp_supplier_id := NULLIF(TRIM(v_exp->>'supplier_id'), '');
                v_exp_supplier_name := NULLIF(TRIM(v_exp->>'supplier_name'), '');
                v_exp_supplier_type := NULLIF(TRIM(v_exp->>'supplier_type'), '');
                v_exp_notes := v_exp->>'notes';

                -- 1. Debit: Expense Account (Return transport/handling expense with cost center)
                IF v_expense_acct IS NOT NULL THEN
                    v_je_lines := v_je_lines || jsonb_build_array(
                        jsonb_build_object(
                            'account_id', v_expense_acct,
                            'debit', v_exp_amount,
                            'credit', 0,
                            'base_debit', v_exp_amount,
                            'base_credit', 0,
                            'currency', 'EGP',
                            'description', v_desc || ' - ' || v_exp_name || COALESCE(' (' || v_exp_supplier_name || ')', ''),
                            'cost_center_id', v_final_cc_id
                        )
                    );
                END IF;

                -- 2. Credit: Supplier Liability (or General Accruals if no supplier selected)
                IF v_exp_supplier_id IS NOT NULL THEN
                    v_supp_account_id := NULL;
                    v_temp_name := NULL;
                    v_temp_type := NULL;

                    -- Lookup from suppliers table
                    SELECT account_id, name, supplier_type INTO v_supp_account_id, v_temp_name, v_temp_type
                    FROM public.suppliers
                    WHERE id::text = v_exp_supplier_id OR code::text = v_exp_supplier_id OR supplier_code::text = v_exp_supplier_id
                    LIMIT 1;

                    -- If not found, lookup from transport_suppliers table
                    IF v_supp_account_id IS NULL THEN
                        SELECT account_id, name INTO v_supp_account_id, v_temp_name
                        FROM public.transport_suppliers
                        WHERE id::text = v_exp_supplier_id OR code::text = v_exp_supplier_id
                        LIMIT 1;
                        IF v_temp_name IS NOT NULL THEN
                            v_temp_type := 'transport';
                        END IF;
                    END IF;

                    -- If not found, lookup from shipping_companies table
                    IF v_supp_account_id IS NULL AND v_temp_name IS NULL THEN
                        SELECT account_id, name INTO v_supp_account_id, v_temp_name
                        FROM public.shipping_companies
                        WHERE id::text = v_exp_supplier_id OR code::text = v_exp_supplier_id
                        LIMIT 1;
                        IF v_temp_name IS NOT NULL THEN
                            v_temp_type := 'shipping';
                        END IF;
                    END IF;

                    -- If not found, lookup from clearing_agents table
                    IF v_supp_account_id IS NULL AND v_temp_name IS NULL THEN
                        SELECT account_id, name INTO v_supp_account_id, v_temp_name
                        FROM public.clearing_agents
                        WHERE id::text = v_exp_supplier_id OR code::text = v_exp_supplier_id
                        LIMIT 1;
                        IF v_temp_name IS NOT NULL THEN
                            v_temp_type := 'clearing';
                        END IF;
                    END IF;

                    IF v_temp_name IS NOT NULL AND (v_exp_supplier_name IS NULL OR v_exp_supplier_name = '') THEN
                        v_exp_supplier_name := v_temp_name;
                    END IF;

                    -- Fallback control accounts
                    IF v_supp_account_id IS NULL THEN
                        IF v_temp_type = 'transport' OR v_exp_supplier_type = 'transport' THEN
                            SELECT id INTO v_supp_account_id FROM public.accounts WHERE account_code = '21111' LIMIT 1;
                        ELSIF v_temp_type = 'packaging' OR v_exp_supplier_type = 'packaging' THEN
                            SELECT id INTO v_supp_account_id FROM public.accounts WHERE account_code = '21112' LIMIT 1;
                        ELSIF v_temp_type = 'shared' OR v_exp_supplier_type = 'shared' THEN
                            SELECT id INTO v_supp_account_id FROM public.accounts WHERE account_code = '21114' LIMIT 1;
                        ELSIF v_temp_type = 'shipping' OR v_exp_supplier_type = 'shipping' THEN
                            SELECT id INTO v_supp_account_id FROM public.accounts WHERE account_code = '21115' LIMIT 1;
                        ELSIF v_temp_type = 'clearing' OR v_exp_supplier_type = 'clearing' THEN
                            SELECT id INTO v_supp_account_id FROM public.accounts WHERE account_code = '21116' LIMIT 1;
                        ELSE
                            SELECT id INTO v_supp_account_id FROM public.accounts WHERE account_code = '21113' LIMIT 1;
                        END IF;
                        IF v_supp_account_id IS NULL THEN
                            SELECT id INTO v_supp_account_id FROM public.accounts WHERE account_code = '2111' LIMIT 1;
                        END IF;
                    END IF;

                    -- Credit Line in Journal Entry
                    v_je_lines := v_je_lines || jsonb_build_array(
                        jsonb_build_object(
                            'account_id', v_supp_account_id,
                            'debit', 0,
                            'credit', v_exp_amount,
                            'base_debit', 0,
                            'base_credit', v_exp_amount,
                            'currency', 'EGP',
                            'description', v_desc || ' - استحقاق مورد: ' || COALESCE(v_exp_supplier_name, 'مورد') || ' (' || v_exp_name || ')',
                            'entity_type', 'supplier',
                            'entity_id', v_exp_supplier_id
                        )
                    );

                    -- Supplier Sub-ledger Entry (directly queries by Supplier Account Statement)
                    INSERT INTO public.ledger_entries (
                        entity_type,
                        entity_id,
                        entry_type,
                        amount,
                        currency,
                        reference_type,
                        reference_text,
                        description,
                        created_by,
                        created_at
                    ) VALUES (
                        'supplier',
                        v_exp_supplier_id,
                        'credit',
                        v_exp_amount,
                        'EGP',
                        'export_return_expense',
                        v_return_no,
                        'مصروف رجوع شحنة: ' || v_exp_name || ' (شحنة #' || COALESCE(v_shipment.shipment_no, p_shipment_id::text) || ')',
                        p_user_id,
                        now()
                    );

                    -- Increase supplier payable balance
                    UPDATE public.suppliers
                    SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_exp_amount,
                        current_balances_by_currency = jsonb_set(
                            COALESCE(current_balances_by_currency, '{}'::jsonb),
                            array['EGP'],
                            to_jsonb(COALESCE((current_balances_by_currency->>'EGP')::numeric, 0) + v_exp_amount)
                        ),
                        updated_at = now()
                    WHERE id::text = v_exp_supplier_id OR code = v_exp_supplier_id OR supplier_code = v_exp_supplier_id;

                    -- Update transport_suppliers table if applicable
                    UPDATE public.transport_suppliers
                    SET balance = COALESCE(balance, 0) + v_exp_amount,
                        updated_at = now()
                    WHERE id::text = v_exp_supplier_id OR code = v_exp_supplier_id;

                    -- Update shipping_companies table if applicable
                    UPDATE public.shipping_companies
                    SET balance = COALESCE(balance, 0) + v_exp_amount,
                        current_balance = COALESCE(current_balance, balance, 0) + v_exp_amount
                    WHERE id::text = v_exp_supplier_id OR code = v_exp_supplier_id;

                    -- Update clearing_agents table if applicable
                    UPDATE public.clearing_agents
                    SET balance = COALESCE(balance, 0) + v_exp_amount,
                        current_balance = COALESCE(current_balance, balance, 0) + v_exp_amount
                    WHERE id::text = v_exp_supplier_id OR code = v_exp_supplier_id;

                    BEGIN
                        INSERT INTO public.transport_transactions (
                            supplier_id, date, transaction_type, credit, debit,
                            balance_after, reference_type, reference_id, notes
                        ) VALUES (
                            v_exp_supplier_id::integer,
                            p_return_date,
                            'credit',
                            v_exp_amount,
                            0,
                            COALESCE((SELECT balance FROM public.transport_suppliers WHERE id::text = v_exp_supplier_id LIMIT 1), 0),
                            'export_return',
                            v_return_no,
                            'مصروف رجوع شحنة: ' || v_exp_name
                        );
                    EXCEPTION WHEN OTHERS THEN NULL;
                    END;

                ELSE
                    -- No supplier selected: Credit General Accrued Expenses / Clearing
                    v_clearing_acct := NULL;
                    SELECT id INTO v_clearing_acct FROM public.accounts WHERE account_code = '21111' AND is_leaf = true LIMIT 1;
                    IF v_clearing_acct IS NULL THEN
                        SELECT id INTO v_clearing_acct FROM public.accounts WHERE account_code = '2111' LIMIT 1;
                    END IF;
                    IF v_clearing_acct IS NULL THEN
                        v_clearing_acct := v_cogs_acct;
                    END IF;

                    v_je_lines := v_je_lines || jsonb_build_array(
                        jsonb_build_object(
                            'account_id', v_clearing_acct,
                            'debit', 0,
                            'credit', v_exp_amount,
                            'base_debit', 0,
                            'base_credit', v_exp_amount,
                            'currency', 'EGP',
                            'description', v_desc || ' - مخصص مصروفات رجوع شحنة (' || v_exp_name || ')'
                        )
                    );
                END IF;
            END IF;
        END LOOP;
    END IF;

    -- Post Journal Entry if lines exist
    IF jsonb_array_length(v_je_lines) > 0 THEN
        BEGIN
            v_je_id := public.post_journal_entry(
                'export_return',
                v_desc,
                p_return_date,
                v_company_id,
                p_user_id,
                v_je_lines,
                p_shipment_id::text
            );
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'post_journal_entry error: %', SQLERRM;
        END;
    END IF;

    -- 8. Update Shipment Status & ZERO OUT Revenue/Profit
    UPDATE public.export_shipments
    SET status = 'returned_from_airport',
        return_journal_entry_id = v_je_id,
        total_revenue_foreign = 0,
        total_revenue_egp = 0,
        net_profit = 0,
        net_profit_egp = 0,
        gross_profit = 0,
        internal_notes = COALESCE(internal_notes, '') || E'\n' || 
            '[' || p_return_date || '] تم تسجيل رجوع الشحنة من المطار برقم ' || v_return_no || 
            ' (سليم: ' || v_intact_cartons || ' كرتونة / تالف: ' || v_damaged_cartons || ' كرتونة)',
        updated_at = now()
    WHERE id = p_shipment_id;

    -- 9. Trigger packing order unlinking, mark with #, and reset sold cartons
    UPDATE public.packing_orders po
    SET export_shipment_id = NULL,
        sold_cartons = 0,
        status = 'returned',
        order_number = CASE WHEN po.order_number NOT LIKE '#%' THEN '#' || po.order_number ELSE po.order_number END,
        notes = COALESCE(po.notes, '') || E'\n' || 
            '[مرتجع من المطار #' || v_return_no || '] تم إرجاع كامل البضاعة للمحطة وفك الارتباط التشغيلي مع الشحنة التصديرية',
        updated_at = now()
    WHERE po.id IN (
      SELECT DISTINCT esi2.packing_order_id 
      FROM public.export_shipment_items esi2 
      WHERE esi2.shipment_id = p_shipment_id AND esi2.packing_order_id IS NOT NULL
    );

    UPDATE public.packing_order_lines pol
    SET sold_cartons = 0,
        updated_at = now()
    WHERE pol.packing_order_id IN (
      SELECT DISTINCT esi2.packing_order_id 
      FROM public.export_shipment_items esi2 
      WHERE esi2.shipment_id = p_shipment_id AND esi2.packing_order_id IS NOT NULL
    );

    -- 10. Record in export_shipment_returns table
    INSERT INTO public.export_shipment_returns (
        return_number, shipment_id, station_id, return_date, cost_center_id,
        total_cartons, intact_cartons, damaged_cartons,
        total_crop_weight, intact_crop_weight, damaged_crop_weight,
        crop_waste_cost, material_waste_cost, extra_expenses_cost,
        reversed_revenue_amount, reversed_revenue_egp,
        reversed_customer_amount, reversed_customer_egp,
        currency, exchange_rate, return_reason, notes, raw_data,
        journal_entry_id, company_id, created_by
    ) VALUES (
        v_return_no, p_shipment_id, p_station_id, p_return_date, p_cost_center_id,
        v_total_cartons, v_intact_cartons, v_damaged_cartons,
        v_total_crop_weight, v_intact_crop_weight, v_damaged_crop_weight,
        v_crop_waste_cost, v_material_waste_cost, v_extra_expenses_cost,
        v_total_revenue, (v_total_revenue * v_exchange_rate),
        v_net_revenue, (v_net_revenue * v_exchange_rate),
        v_currency, v_exchange_rate, p_return_reason, p_notes,
        jsonb_build_object('items', p_items, 'extra_expenses', p_extra_expenses),
        v_je_id, v_company_id, p_user_id
    ) RETURNING id INTO v_return_id;

    -- Update reference_id on ledger_entries for extra return expenses
    UPDATE public.ledger_entries
    SET reference_id = v_return_id::integer
    WHERE reference_text = v_return_no AND reference_type = 'export_return_expense';

    -- 11. Record movements into cost_center_transactions under the Season Cost Center
    -- A. Crop Waste
    IF v_crop_waste_cost > 0 THEN
        INSERT INTO public.cost_center_transactions (
            cost_center_id, cost_center_name, cost_center_type,
            source_type, source_id, transaction_date,
            supplier_name, item_name, category,
            quantity, unit_price, currency, exchange_rate,
            total_in_currency, amount, notes, is_confirmed
        ) VALUES (
            v_final_cc_id,
            v_final_cc_name,
            'crop',
            'export_return_waste',
            'exr_crop_waste_' || v_return_no || '_0',
            p_return_date,
            COALESCE(v_shipment.customer_name, 'عميل شحنة #' || COALESCE(v_shipment.shipment_no, p_shipment_id::text)),
            'هالك رجوع شحنة (محصول) - شحنة #' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
            'تكلفة الهالك',
            CASE WHEN v_damaged_crop_weight > 0 THEN v_damaged_crop_weight ELSE 1.0 END,
            CASE WHEN v_damaged_crop_weight > 0 THEN v_crop_waste_cost / v_damaged_crop_weight ELSE v_crop_waste_cost END,
            'EGP', 1.0,
            v_crop_waste_cost, v_crop_waste_cost,
            'هالك وتلف محصول عند رجوع الشحنة التصديرية رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text) || ' (' || v_return_no || ')',
            true
        )
        ON CONFLICT (source_type, source_id) DO UPDATE
        SET amount = EXCLUDED.amount,
            quantity = EXCLUDED.quantity,
            unit_price = EXCLUDED.unit_price,
            cost_center_id = EXCLUDED.cost_center_id,
            updated_at = now();
    END IF;

    -- B. Material Waste
    IF v_material_waste_cost > 0 THEN
        INSERT INTO public.cost_center_transactions (
            cost_center_id, cost_center_name, cost_center_type,
            source_type, source_id, transaction_date,
            supplier_name, item_name, category,
            quantity, unit_price, currency, exchange_rate,
            total_in_currency, amount, notes, is_confirmed
        ) VALUES (
            v_final_cc_id,
            v_final_cc_name,
            'crop',
            'export_return_waste',
            'exr_mat_waste_' || v_return_no || '_0',
            p_return_date,
            COALESCE(v_shipment.customer_name, 'عميل شحنة #' || COALESCE(v_shipment.shipment_no, p_shipment_id::text)),
            'هالك رجوع شحنة (كراتين) - شحنة #' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
            'مواد التعبئة',
            CASE WHEN v_damaged_cartons > 0 THEN v_damaged_cartons::numeric ELSE 1.0 END,
            CASE WHEN v_damaged_cartons > 0 THEN v_material_waste_cost / v_damaged_cartons ELSE v_material_waste_cost END,
            'EGP', 1.0,
            v_material_waste_cost, v_material_waste_cost,
            'هالك كراتين ومواد تعبئة عند رجوع الشحنة التصديرية رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text) || ' (' || v_return_no || ')',
            true
        )
        ON CONFLICT (source_type, source_id) DO UPDATE
        SET amount = EXCLUDED.amount,
            quantity = EXCLUDED.quantity,
            unit_price = EXCLUDED.unit_price,
            cost_center_id = EXCLUDED.cost_center_id,
            updated_at = now();
    END IF;

    -- C. Extra Expenses
    IF p_extra_expenses IS NOT NULL AND jsonb_array_length(p_extra_expenses) > 0 THEN
        FOR v_i IN 0 .. (jsonb_array_length(p_extra_expenses) - 1)
        LOOP
            v_exp := p_extra_expenses->v_i;
            v_exp_amount := COALESCE((v_exp->>'amount')::NUMERIC, 0);
            IF v_exp_amount > 0 THEN
                INSERT INTO public.cost_center_transactions (
                    cost_center_id, cost_center_name, cost_center_type,
                    source_type, source_id, transaction_date,
                    supplier_id, supplier_name,
                    item_name, category,
                    quantity, unit_price, currency, exchange_rate,
                    total_in_currency, amount, notes, is_confirmed
                ) VALUES (
                    v_final_cc_id,
                    v_final_cc_name,
                    'crop',
                    'export_return_expense',
                    'exr_exp_' || v_return_no || '_' || v_i::text,
                    p_return_date,
                    NULLIF(TRIM(v_exp->>'supplier_id'), ''),
                    COALESCE(NULLIF(TRIM(v_exp->>'supplier_name'), ''), v_shipment.customer_name, 'مورد مصروف رجوع'),
                    COALESCE(NULLIF(TRIM(v_exp->>'name'), ''), 'مصروفات رجوع شحنة إضافية'),
                    'لوجستيك ونقل',
                    1.0, v_exp_amount,
                    'EGP', 1.0,
                    v_exp_amount, v_exp_amount,
                    'مصروف رجوع شحنة تصدير رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text) || ' (' || v_return_no || ')',
                    true
                )
                ON CONFLICT (source_type, source_id) DO UPDATE
                SET amount = EXCLUDED.amount,
                    quantity = EXCLUDED.quantity,
                    unit_price = EXCLUDED.unit_price,
                    cost_center_id = EXCLUDED.cost_center_id,
                    updated_at = now();
            END IF;
        END LOOP;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'return_id', v_return_id,
        'return_number', v_return_no,
        'journal_entry_id', v_je_id,
        'intact_cartons', v_intact_cartons,
        'damaged_cartons', v_damaged_cartons,
        'intact_crop_weight', v_intact_crop_weight,
        'damaged_crop_weight', v_damaged_crop_weight,
        'crop_waste_cost', v_crop_waste_cost,
        'material_waste_cost', v_material_waste_cost,
        'message', 'تم تسجيل رجوع الشحنة من المطار بنجاح وتسوية المخزون والهالك'
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_process_export_shipment_return(BIGINT, BIGINT, DATE, TEXT, TEXT, JSONB, JSONB, TEXT, UUID) TO authenticated, service_role, anon;

-- 11. One-time Cleanup for Previous Return Tests
-- Restore correct crop cards and delete any dummy duplicate cards
DO $$
DECLARE
    v_dup_id BIGINT;
    v_dup_qty NUMERIC;
BEGIN
    -- Check for duplicate card created with empty product_code or CARTON-RET or matching name
    FOR v_dup_id, v_dup_qty IN 
        SELECT id, quantity FROM public.station_products 
        WHERE (product_code = '' OR product_code = 'CARTON-RET' OR product_name LIKE 'كراتين مرتجعة%') 
          AND id NOT IN (1, 2, 3, 4, 5, 6)
    LOOP
        -- Add quantity back to true crop card (id: 2)
        UPDATE public.station_products SET quantity = 3000 WHERE id = 2;
        DELETE FROM public.station_products WHERE id = v_dup_id;
    END LOOP;

    -- Fix batches created during return test
    UPDATE public.station_product_batches
    SET product_code = '2', fruit_type_id = 2, item_type = 'fruit'
    WHERE source_type = 'export_return' AND (product_code = '' OR product_code IS NULL) AND product_name LIKE '%كراتين%';

    UPDATE public.station_product_batches
    SET product_code = '1', fruit_type_id = 1, item_type = 'fruit'
    WHERE source_type = 'export_return' AND (product_code = '' OR product_code IS NULL) AND product_name LIKE '%وزن%';

    UPDATE public.station_product_batches
    SET product_name = 'كراتين مانجو 5 ك (مادة تعبئة)',
        raw_material_id = '4787b8e9-29dd-41a1-8271-f1b96d36520c',
        item_type = 'material'
    WHERE source_type = 'export_return' AND product_name LIKE '%كراتين مانجو%';

    -- Zero out shipment 1 profit and revenue
    UPDATE public.export_shipments
    SET total_revenue_egp = 0,
        total_revenue_foreign = 0,
        net_profit = 0,
        net_profit_egp = 0,
        gross_profit = 0
    WHERE id = 1 AND status = 'returned_from_airport';

    -- Update packing order 1
    UPDATE public.packing_orders
    SET order_number = CASE WHEN order_number NOT LIKE '#%' THEN '#' || order_number ELSE order_number END,
        status = 'returned',
        export_shipment_id = NULL,
        sold_cartons = 0
    WHERE id = 1;

    UPDATE public.packing_order_lines
    SET sold_cartons = 0
    WHERE packing_order_id = 1;

    -- Backfill return_journal_entry_id on export_shipments and export_shipment_returns if missing
    UPDATE public.export_shipment_returns esr
    SET journal_entry_id = je.id
    FROM public.journal_entries je
    WHERE (je.source_type IN ('export_return', 'export_shipment_return') AND je.source_id = esr.shipment_id::text)
      AND esr.journal_entry_id IS NULL;

    UPDATE public.export_shipments s
    SET return_journal_entry_id = esr.journal_entry_id
    FROM public.export_shipment_returns esr
    WHERE esr.shipment_id = s.id AND esr.journal_entry_id IS NOT NULL AND s.return_journal_entry_id IS NULL;

    UPDATE public.export_shipments s
    SET return_journal_entry_id = je.id
    FROM public.journal_entries je
    WHERE (je.source_type IN ('export_return', 'export_shipment_return') AND je.source_id = s.id::text)
      AND s.return_journal_entry_id IS NULL;
END;
$$;

COMMIT;
