-- ============================================================================
-- 083_multi_product_packing_orders_enterprise.sql
--
-- Enterprise Multi-Product Packing Order System:
-- 1. Adds journal_entry_id and relaxes single-lot constraints on packing_orders
-- 2. Registers 'packing_order' document type in sys_document_types
-- 3. Creates packing_order_lines table for unlimited products per order
-- 4. Extends packing_order_cost_items & packing_order_sortings
-- 5. Backfills existing packing_orders into packing_order_lines
-- 6. Implements Enterprise rpc_confirm_packing_order with double-entry GL posting
-- 7. Implements Enterprise rpc_cancel_packing_order with safe reversal
-- ============================================================================

BEGIN;

-- 1. Ensure journal_entry_id on packing_orders & make lot_id nullable
ALTER TABLE public.packing_orders 
ADD COLUMN IF NOT EXISTS journal_entry_id BIGINT REFERENCES public.journal_entries(id) ON DELETE SET NULL;

ALTER TABLE public.packing_orders 
ALTER COLUMN lot_id DROP NOT NULL;

-- 2. Register document type for packing orders
INSERT INTO public.sys_document_types (code, name, prefix)
VALUES ('packing_order', 'أمر تعبئة', 'PK')
ON CONFLICT (code) DO UPDATE 
SET name = EXCLUDED.name, 
    prefix = EXCLUDED.prefix;

-- 3. Create packing_order_lines table
CREATE TABLE IF NOT EXISTS public.packing_order_lines (
    id BIGSERIAL PRIMARY KEY,
    packing_order_id BIGINT NOT NULL REFERENCES public.packing_orders(id) ON DELETE CASCADE,
    product_id INTEGER,
    fruit_type_id INTEGER,
    product_name TEXT,
    grade TEXT DEFAULT 'A',
    source_lot_id BIGINT REFERENCES public.lot_receipts(id) ON DELETE SET NULL,
    batch_id INTEGER REFERENCES public.station_product_batches(id) ON DELETE SET NULL,
    quantity NUMERIC(15,3) DEFAULT 0,
    carton_count INTEGER DEFAULT 0 NOT NULL,
    net_weight_per_carton NUMERIC(10,3) DEFAULT 0 NOT NULL,
    gross_weight_per_carton NUMERIC(10,3) DEFAULT 0 NOT NULL,
    total_net_weight NUMERIC(15,3) GENERATED ALWAYS AS ((carton_count::numeric * net_weight_per_carton)) STORED,
    total_gross_weight NUMERIC(15,3) GENERATED ALWAYS AS ((carton_count::numeric * gross_weight_per_carton)) STORED,
    unit_cost NUMERIC(15,4) DEFAULT 0,
    raw_material_cost NUMERIC(15,2) DEFAULT 0,
    expected_loss_percent NUMERIC(5,2) DEFAULT 0,
    waste_weight_kg NUMERIC(15,3) DEFAULT 0,
    waste_cost NUMERIC(15,2) DEFAULT 0,
    sorted_weight_kg NUMERIC(15,3) DEFAULT 0,
    sorting_cost NUMERIC(15,2) DEFAULT 0,
    specific_packaging_cost NUMERIC(15,2) DEFAULT 0,
    allocated_shared_packaging NUMERIC(15,2) DEFAULT 0,
    allocated_cost_items NUMERIC(15,2) DEFAULT 0,
    final_cost NUMERIC(15,2) DEFAULT 0,
    final_unit_cost NUMERIC(15,4) DEFAULT 0,
    sold_cartons INTEGER DEFAULT 0 NOT NULL,
    notes JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_packing_order_lines_order_id ON public.packing_order_lines(packing_order_id);
CREATE INDEX IF NOT EXISTS idx_packing_order_lines_lot_id ON public.packing_order_lines(source_lot_id);
CREATE INDEX IF NOT EXISTS idx_packing_order_lines_batch_id ON public.packing_order_lines(batch_id);

-- Enable RLS
ALTER TABLE public.packing_order_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow all for authenticated on packing_order_lines" ON public.packing_order_lines;
CREATE POLICY "Allow all for authenticated on packing_order_lines"
ON public.packing_order_lines
FOR ALL
TO authenticated
USING (true)
WITH CHECK (true);

-- 4. Extend sorting and cost items
ALTER TABLE public.packing_order_sortings 
ADD COLUMN IF NOT EXISTS packing_order_line_id BIGINT REFERENCES public.packing_order_lines(id) ON DELETE SET NULL;

ALTER TABLE public.packing_order_cost_items 
ADD COLUMN IF NOT EXISTS allocation_method TEXT DEFAULT 'BY_NET_WEIGHT';

ALTER TABLE public.packing_order_cost_items 
ADD COLUMN IF NOT EXISTS target_line_id BIGINT REFERENCES public.packing_order_lines(id) ON DELETE SET NULL;

-- 5. Backfill historical packing_orders into packing_order_lines
INSERT INTO public.packing_order_lines (
    packing_order_id,
    product_id,
    fruit_type_id,
    product_name,
    grade,
    source_lot_id,
    batch_id,
    quantity,
    carton_count,
    net_weight_per_carton,
    gross_weight_per_carton,
    unit_cost,
    raw_material_cost,
    waste_weight_kg,
    waste_cost,
    sorted_weight_kg,
    sorting_cost,
    specific_packaging_cost,
    allocated_shared_packaging,
    allocated_cost_items,
    final_cost,
    final_unit_cost,
    sold_cartons,
    notes,
    created_at,
    updated_at
)
SELECT 
    po.id AS packing_order_id,
    NULL AS product_id,
    po.fruit_type_id,
    COALESCE(po.product_name, lr.product_name, 'محصول'),
    COALESCE(po.grade, 'A'),
    po.lot_id AS source_lot_id,
    po.batch_id,
    COALESCE(
        (po.notes::jsonb->>'partial_weight_kg')::numeric,
        lr.gross_weight_kg,
        (po.carton_count::numeric * po.net_weight_per_carton)
    ) AS quantity,
    po.carton_count,
    po.net_weight_per_carton,
    po.gross_weight_per_carton,
    CASE 
        WHEN COALESCE(lr.gross_weight_kg, 0) > 0 THEN (COALESCE(po.fruit_cost_allocated, po.fruit_cost_base, 0) / lr.gross_weight_kg)
        ELSE 0
    END AS unit_cost,
    COALESCE(po.fruit_cost_allocated, po.fruit_cost_base, 0) AS raw_material_cost,
    COALESCE((po.notes::jsonb->>'waste_weight_kg')::numeric, 0) AS waste_weight_kg,
    COALESCE((po.notes::jsonb->>'waste_cost')::numeric, 0) AS waste_cost,
    COALESCE((po.notes::jsonb->>'sorted_weight_kg')::numeric, 0) AS sorted_weight_kg,
    COALESCE((po.notes::jsonb->>'sorting_cost')::numeric, 0) AS sorting_cost,
    COALESCE(po.actual_material_cost, po.material_cost_base, 0) AS specific_packaging_cost,
    0 AS allocated_shared_packaging,
    COALESCE(po.other_cost_base, 0) AS allocated_cost_items,
    COALESCE(po.total_packing_cost, 0) AS final_cost,
    COALESCE(po.packing_cost_per_carton, 0) AS final_unit_cost,
    COALESCE(po.sold_cartons, 0) AS sold_cartons,
    po.notes::jsonb AS notes,
    po.created_at,
    po.updated_at
FROM public.packing_orders po
LEFT JOIN public.lot_receipts lr ON lr.id = po.lot_id
WHERE NOT EXISTS (
    SELECT 1 FROM public.packing_order_lines pol WHERE pol.packing_order_id = po.id
);

-- Backfill sortings line links where possible
UPDATE public.packing_order_sortings pos
SET packing_order_line_id = (
    SELECT pol.id FROM public.packing_order_lines pol 
    WHERE pol.packing_order_id = pos.packing_order_id 
    LIMIT 1
)
WHERE pos.packing_order_line_id IS NULL;

-- 6. Enterprise rpc_confirm_packing_order
CREATE OR REPLACE FUNCTION public.rpc_confirm_packing_order(
  p_packing_order_id bigint
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order               RECORD;
  v_notes               JSONB;
  v_station_id          INTEGER;
  v_allocations         JSONB := '[]'::jsonb;
  v_el                  JSONB;
  v_rate                NUMERIC;
  v_amt_egp             NUMERIC;
  v_amt_foreign         NUMERIC;
  v_curr                TEXT;
  r_cost                RECORD;
  r_line                RECORD;
  v_supplier_id         UUID;
  v_tx_desc             TEXT;
  v_current_balance     NUMERIC;
  v_treasury_tx_id      BIGINT;
  v_bank_tx_id          INTEGER;
  v_company_id          UUID;
  v_je_id               BIGINT;
  v_entry_num           TEXT;
  v_finished_inv_acc    BIGINT;
  v_raw_inv_acc         BIGINT;
  v_pkg_inv_acc         BIGINT;
  v_supp_acc            BIGINT;
  v_treasury_acc        BIGINT;
  v_bank_acc            BIGINT;
  v_tot_raw_cost        NUMERIC := 0;
  v_tot_pkg_cost        NUMERIC := 0;
  v_tot_cost_items      NUMERIC := 0;
  v_tot_final_cost      NUMERIC := 0;
  v_lines_count         INTEGER := 0;
BEGIN
  -- A. Load order
  SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  IF v_order.status NOT IN ('draft', 'pending') THEN
    RETURN json_build_object('success', false, 'error', 'لا يمكن تأكيد أمر تعبئة بحالة ' || v_order.status);
  END IF;

  v_station_id := v_order.station_id;
  IF v_station_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'لم يتم تحديد المحطة');
  END IF;

  v_notes := CASE WHEN v_order.notes IS NOT NULL AND v_order.notes != ''
    THEN v_order.notes::jsonb ELSE '{}'::jsonb END;

  -- B. Sync & Save Cost Items from notes if present
  IF v_notes ? 'cost_items' THEN
    DELETE FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id;

    FOR v_el IN SELECT jsonb_array_elements(v_notes->'cost_items')
    LOOP
      v_rate := COALESCE(NULLIF((v_el->>'exchange_rate')::numeric, 0), 1.0);
      v_curr := COALESCE(NULLIF(v_el->>'supplier_currency', ''), 'EGP');

      v_amt_egp := COALESCE((v_el->>'total_egp')::numeric, 0);
      IF v_amt_egp = 0 THEN
        v_amt_egp := COALESCE((v_el->>'total')::numeric, 0);
      END IF;

      IF v_curr = 'EGP' THEN
        v_amt_foreign := v_amt_egp;
      ELSIF v_rate > 0 THEN
        v_amt_foreign := ROUND(v_amt_egp / v_rate, 2);
      ELSE
        v_amt_foreign := v_amt_egp;
      END IF;

      INSERT INTO public.packing_order_cost_items (
        packing_order_id, name, category, report_category_id,
        original_currency, original_amount, exchange_rate, base_amount,
        currency_snapshot, payment_source_type, payment_source_id,
        allocation_method, target_line_id
      ) VALUES (
        p_packing_order_id,
        COALESCE(v_el->>'name', 'بند تكلفة'),
        COALESCE(v_el->>'category', 'other'),
        (v_el->>'report_category_id')::integer,
        v_curr,
        v_amt_foreign,
        v_rate,
        v_amt_egp,
        v_el,
        v_el->>'payment_source_type',
        NULLIF(v_el->>'payment_source_id', '')::bigint,
        COALESCE(v_el->>'allocation_method', 'BY_NET_WEIGHT'),
        NULLIF(v_el->>'target_line_id', '')::bigint
      );
    END LOOP;
  END IF;

  -- C. Prepare stock deductions: Fruit Raw Materials
  IF v_notes ? 'fruit_allocation' THEN
    v_el := v_notes->'fruit_allocation';
    IF jsonb_typeof(v_el) = 'array' THEN
      FOR i IN 0..jsonb_array_length(v_el) - 1 LOOP
        v_allocations := v_allocations || jsonb_build_array(v_el->i);
      END LOOP;
    ELSIF jsonb_typeof(v_el) = 'object' THEN
      v_allocations := v_allocations || jsonb_build_array(v_el);
    END IF;
  ELSE
    -- Build allocations directly from packing_order_lines if not in notes
    FOR r_line IN SELECT * FROM public.packing_order_lines WHERE packing_order_id = p_packing_order_id LOOP
      IF r_line.batch_id IS NOT NULL AND r_line.quantity > 0 THEN
        v_allocations := v_allocations || jsonb_build_array(
          jsonb_build_object(
            'batch_id', r_line.batch_id,
            'quantity', r_line.quantity,
            'product_name', r_line.product_name,
            'product_code', ''
          )
        );
      END IF;
    END LOOP;
  END IF;

  -- Packaging Materials
  IF v_notes ? 'materials' THEN
    FOR v_el IN SELECT jsonb_array_elements(v_notes->'materials')
    LOOP
      v_allocations := v_allocations || jsonb_build_array(
        jsonb_build_object(
          'batch_id', v_el->>'batch_id',
          'quantity', v_el->>'used_qty',
          'product_name', v_el->>'product_name',
          'product_code', COALESCE(v_el->>'product_code', '')
        )
      );
    END LOOP;
  END IF;

  -- Perform stock deductions at the station
  IF jsonb_array_length(v_allocations) > 0 THEN
    PERFORM deduct_station_batch_allocations(v_station_id, v_allocations);
  END IF;

  -- D. Process Cost Items Financial Payments & Subsidiary Ledgers
  FOR r_cost IN
    SELECT poci.*, cr.name AS report_category_name
    FROM public.packing_order_cost_items poci
    LEFT JOIN public.cost_report_categories cr ON cr.id = poci.report_category_id
    WHERE poci.packing_order_id = p_packing_order_id
  LOOP
    v_supplier_id := NULL;
    IF r_cost.currency_snapshot IS NOT NULL AND r_cost.currency_snapshot ? 'supplier_id' THEN
      v_supplier_id := NULLIF(r_cost.currency_snapshot->>'supplier_id', '')::uuid;
    END IF;

    v_tx_desc := 'سداد بند تكلفة أمر تعبئة: ' || COALESCE(r_cost.name, 'غير محدد') || ' (أمر ' || p_packing_order_id::text || ')';

    IF v_supplier_id IS NOT NULL AND r_cost.original_amount > 0 THEN
      IF r_cost.payment_source_type = 'bank' THEN
        UPDATE public.suppliers
        SET outstanding_balance = COALESCE(outstanding_balance, 0) + r_cost.original_amount,
            updated_at = now()
        WHERE id = v_supplier_id;

        INSERT INTO public.ledger_entries (
          entity_type, entity_id, entry_type, amount, currency,
          reference_type, reference_text, description, created_by
        ) VALUES (
          'supplier', v_supplier_id::text, 'credit', r_cost.original_amount, r_cost.original_currency,
          'packing_cost', p_packing_order_id::text,
          'بند تكلفة أمر تعبئة: ' || COALESCE(r_cost.name, 'غير محدد') || ' (أمر ' || p_packing_order_id::text || ')',
          auth.uid()
        );

        UPDATE public.suppliers
        SET outstanding_balance = COALESCE(outstanding_balance, 0) - r_cost.original_amount,
            updated_at = now()
        WHERE id = v_supplier_id;

        INSERT INTO public.ledger_entries (
          entity_type, entity_id, entry_type, amount, currency,
          reference_type, reference_text, description, created_by
        ) VALUES (
          'supplier', v_supplier_id::text, 'debit', r_cost.original_amount, r_cost.original_currency,
          'packing_cost', p_packing_order_id::text,
          v_tx_desc,
          auth.uid()
        );

      ELSIF r_cost.payment_source_type IS NULL OR r_cost.payment_source_type = 'none' THEN
        UPDATE public.suppliers
        SET outstanding_balance = COALESCE(outstanding_balance, 0) + r_cost.original_amount,
            updated_at = now()
        WHERE id = v_supplier_id;

        INSERT INTO public.ledger_entries (
          entity_type, entity_id, entry_type, amount, currency,
          reference_type, reference_text, description, created_by
        ) VALUES (
          'supplier', v_supplier_id::text, 'credit', r_cost.original_amount, r_cost.original_currency,
          'packing_cost', p_packing_order_id::text,
          'بند تكلفة أمر تعبئة: ' || COALESCE(r_cost.name, 'غير محدد') || ' (أمر ' || p_packing_order_id::text || ')',
          auth.uid()
        );

      ELSIF r_cost.payment_source_type = 'treasury' THEN
        UPDATE public.suppliers
        SET outstanding_balance = COALESCE(outstanding_balance, 0) + r_cost.original_amount,
            updated_at = now()
        WHERE id = v_supplier_id;

        INSERT INTO public.ledger_entries (
          entity_type, entity_id, entry_type, amount, currency,
          reference_type, reference_text, description, created_by
        ) VALUES (
          'supplier', v_supplier_id::text, 'credit', r_cost.original_amount, r_cost.original_currency,
          'packing_cost', p_packing_order_id::text,
          'بند تكلفة أمر تعبئة: ' || COALESCE(r_cost.name, 'غير محدد') || ' (أمر ' || p_packing_order_id::text || ')',
          auth.uid()
        );
      END IF;
    END IF;

    -- Treasury and Bank disbursements
    IF r_cost.payment_source_type IS NOT NULL AND r_cost.payment_source_id IS NOT NULL 
       AND r_cost.treasury_transaction_id IS NULL AND r_cost.bank_transaction_id IS NULL THEN

      IF r_cost.payment_source_type = 'treasury' THEN
        SELECT balance INTO v_current_balance
        FROM public.treasury_balances
        WHERE treasury_id = r_cost.payment_source_id AND currency = r_cost.original_currency
        FOR UPDATE;

        IF v_current_balance IS NULL OR v_current_balance < r_cost.original_amount THEN
          RAISE EXCEPTION 'الرصيد غير كافٍ في الخزينة المحددة للبند % (المتوفر: % %, المطلوب: % %)', 
            r_cost.name, COALESCE(v_current_balance, 0), r_cost.original_currency, r_cost.original_amount, r_cost.original_currency;
        END IF;

        PERFORM public.spend_custody(
          r_cost.payment_source_id,
          r_cost.original_currency,
          r_cost.original_amount,
          v_tx_desc,
          NULL,
          v_supplier_id,
          NULL,
          NULL,
          NULL
        );

        SELECT id INTO v_treasury_tx_id
        FROM public.treasury_transactions
        WHERE treasury_id = r_cost.payment_source_id
          AND type = 'expense'
          AND amount = r_cost.original_amount
          AND currency = r_cost.original_currency
        ORDER BY created_at DESC
        LIMIT 1;

        UPDATE public.packing_order_cost_items
        SET treasury_transaction_id = v_treasury_tx_id
        WHERE id = r_cost.id;

      ELSIF r_cost.payment_source_type = 'bank' THEN
        SELECT balance INTO v_current_balance 
        FROM public.bank_accounts 
        WHERE id = r_cost.payment_source_id
        FOR UPDATE;

        IF v_current_balance IS NULL OR v_current_balance < r_cost.original_amount THEN
          RAISE EXCEPTION 'الرصيد غير كافٍ في البنك المحدد للبند % (المتوفر: %, المطلوب: %)', 
            r_cost.name, COALESCE(v_current_balance, 0), r_cost.original_amount;
        END IF;

        SELECT (public.withdraw_bank_account(
          r_cost.payment_source_id::integer,
          r_cost.original_amount,
          v_tx_desc,
          CASE WHEN v_supplier_id IS NOT NULL THEN 'supplier' ELSE NULL END,
          v_supplier_id::text,
          NULL
        )->>'id')::integer INTO v_bank_tx_id;

        UPDATE public.bank_account_transactions
        SET currency_snapshot = r_cost.currency_snapshot
        WHERE id = v_bank_tx_id;

        UPDATE public.packing_order_cost_items
        SET bank_transaction_id = v_bank_tx_id
        WHERE id = r_cost.id;
      END IF;
    END IF;
  END LOOP;

  -- E. Calculate Totals from lines & cost items
  SELECT 
    COALESCE(SUM(pol.raw_material_cost), 0),
    COALESCE(SUM(pol.specific_packaging_cost + pol.allocated_shared_packaging), 0),
    COALESCE(SUM(pol.allocated_cost_items), 0),
    COALESCE(SUM(pol.final_cost), 0),
    COUNT(*)
  INTO 
    v_tot_raw_cost,
    v_tot_pkg_cost,
    v_tot_cost_items,
    v_tot_final_cost,
    v_lines_count
  FROM public.packing_order_lines pol
  WHERE pol.packing_order_id = p_packing_order_id;

  -- If no lines or totals are 0, fallback to order totals
  IF v_tot_final_cost = 0 THEN
    v_tot_raw_cost   := COALESCE(v_order.fruit_cost_allocated, v_order.fruit_cost_base, 0);
    v_tot_pkg_cost   := COALESCE(v_order.actual_material_cost, v_order.material_cost_base, 0);
    v_tot_cost_items := COALESCE(v_order.other_cost_base, 0);
    v_tot_final_cost := COALESCE(v_order.total_packing_cost, (v_tot_raw_cost + v_tot_pkg_cost + v_tot_cost_items));
  END IF;

  -- F. Enterprise Double-Entry GL Posting
  -- Company ID
  SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;
  IF v_company_id IS NULL THEN
    SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
  END IF;

  -- Accounts Resolution
  SELECT id INTO v_finished_inv_acc FROM accounts WHERE account_code = '1030' LIMIT 1;
  SELECT id INTO v_raw_inv_acc      FROM accounts WHERE account_code = '1030' LIMIT 1;
  SELECT id INTO v_pkg_inv_acc      FROM accounts WHERE account_code = '1040' LIMIT 1;
  IF v_pkg_inv_acc IS NULL THEN v_pkg_inv_acc := v_raw_inv_acc; END IF;

  -- Clean old journal entry if exists
  IF v_order.journal_entry_id IS NOT NULL THEN
    DELETE FROM account_ledger_entries WHERE journal_entry_id = v_order.journal_entry_id;
    DELETE FROM journal_entries WHERE id = v_order.journal_entry_id;
    v_je_id := NULL;
  END IF;

  -- Create new posted journal entry
  INSERT INTO public.journal_entries (
    entry_number,
    entry_date,
    description,
    status,
    is_auto_generated,
    source_type,
    source_id,
    company_id,
    created_by,
    created_at,
    updated_at
  ) VALUES (
    'PENDING',
    COALESCE(v_order.packed_at::date, v_order.created_at::date, CURRENT_DATE),
    'قيد أمر تعبئة رقم ' || COALESCE(v_order.order_number, p_packing_order_id::text) || ' (تكلفة تعبئة ومخزون تام)',
    'posted',
    true,
    'packing_order',
    p_packing_order_id::text,
    v_company_id,
    auth.uid(),
    NOW(),
    NOW()
  ) RETURNING id INTO v_je_id;

  v_entry_num := fn_generate_journal_entry_number(v_je_id);
  UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

  -- 1. DEBIT: Finished Goods Inventory (Total Finished Production Cost)
  IF v_tot_final_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description
    ) VALUES (
      v_je_id,
      v_finished_inv_acc,
      v_tot_final_cost,
      0,
      COALESCE(v_order.display_currency, 'EGP'),
      v_tot_final_cost,
      'إضافة مخزون إنتاج تام - أمر تعبئة: ' || COALESCE(v_order.order_number, p_packing_order_id::text)
    );
  END IF;

  -- 2. CREDIT: Raw Materials Inventory (Fruit Cost)
  IF v_tot_raw_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description
    ) VALUES (
      v_je_id,
      v_raw_inv_acc,
      0,
      v_tot_raw_cost,
      COALESCE(v_order.display_currency, 'EGP'),
      v_tot_raw_cost,
      'صرف مواد خام/محاصيل لأمر التعبئة: ' || COALESCE(v_order.order_number, p_packing_order_id::text)
    );
  END IF;

  -- 3. CREDIT: Packaging Materials Inventory (Packaging Cost)
  IF v_tot_pkg_cost > 0 THEN
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description
    ) VALUES (
      v_je_id,
      v_pkg_inv_acc,
      0,
      v_tot_pkg_cost,
      COALESCE(v_order.display_currency, 'EGP'),
      v_tot_pkg_cost,
      'صرف مواد تعبئة وتغليف لأمر التعبئة: ' || COALESCE(v_order.order_number, p_packing_order_id::text)
    );
  END IF;

  -- 4. CREDIT: Direct Cost Items (By payment source)
  FOR r_cost IN
    SELECT poci.*, cr.name AS report_category_name
    FROM public.packing_order_cost_items poci
    LEFT JOIN public.cost_report_categories cr ON cr.id = poci.report_category_id
    WHERE poci.packing_order_id = p_packing_order_id
  LOOP
    IF r_cost.base_amount > 0 THEN
      -- Resolve offset account
      v_treasury_acc := NULL;
      IF r_cost.payment_source_type = 'treasury' AND r_cost.payment_source_id IS NOT NULL THEN
        SELECT a.id INTO v_treasury_acc 
        FROM public.treasuries t
        JOIN public.accounts a ON a.id = t.account_id
        WHERE t.id = r_cost.payment_source_id;
        IF v_treasury_acc IS NULL THEN
          SELECT id INTO v_treasury_acc FROM accounts WHERE account_code = '1000' LIMIT 1;
        END IF;
      ELSIF r_cost.payment_source_type = 'bank' AND r_cost.payment_source_id IS NOT NULL THEN
        SELECT a.id INTO v_treasury_acc 
        FROM public.bank_accounts b
        JOIN public.accounts a ON a.id = b.account_id
        WHERE b.id = r_cost.payment_source_id;
        IF v_treasury_acc IS NULL THEN
          SELECT id INTO v_treasury_acc FROM accounts WHERE account_code = '1010' LIMIT 1;
        END IF;
      ELSE
        -- Supplier Account / Accounts Payable 2000
        IF r_cost.currency_snapshot IS NOT NULL AND r_cost.currency_snapshot ? 'supplier_id' THEN
          SELECT a.id INTO v_treasury_acc
          FROM public.suppliers s
          JOIN public.accounts a ON a.id = s.account_id
          WHERE s.id = (r_cost.currency_snapshot->>'supplier_id')::uuid;
        END IF;
        IF v_treasury_acc IS NULL THEN
          SELECT id INTO v_treasury_acc FROM accounts WHERE account_code = '2000' LIMIT 1;
        END IF;
      END IF;

      IF v_treasury_acc IS NOT NULL THEN
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description
        ) VALUES (
          v_je_id,
          v_treasury_acc,
          0,
          r_cost.base_amount,
          COALESCE(r_cost.original_currency, 'EGP'),
          r_cost.base_amount,
          'مصاريف مباشرة أمر تعبئة: ' || COALESCE(r_cost.name, 'بند تكلفة')
        );
      END IF;
    END IF;
  END LOOP;

  -- G. Mark Order Completed
  UPDATE public.packing_orders
  SET status = 'completed',
      journal_entry_id = v_je_id,
      packed_at = NOW(),
      updated_at = NOW()
  WHERE id = p_packing_order_id;

  RETURN json_build_object('success', true, 'journal_entry_id', v_je_id);
END;
$$;

-- 7. Enterprise rpc_cancel_packing_order
CREATE OR REPLACE FUNCTION public.rpc_cancel_packing_order(
  p_packing_order_id bigint
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order           RECORD;
  v_notes           JSONB;
  v_station_id      INTEGER;
  v_allocations     JSONB := '[]'::jsonb;
  v_el              JSONB;
  r_cost            RECORD;
  r_line            RECORD;
  -- treasury reversal
  v_treasury_tx     RECORD;
  v_treasury_bal    RECORD;
  v_reversal_tx_id  BIGINT;
  -- bank reversal
  v_bank_tx         RECORD;
  v_bank_bal_diff   NUMERIC;
  -- supplier reversal
  v_supplier_id     UUID;
  v_rate            NUMERIC;
  v_amt_foreign     NUMERIC;
  v_curr            TEXT;
  v_had_treasury_tx BOOLEAN;
  v_had_bank_tx     BOOLEAN;
  v_je_id           BIGINT;
BEGIN
  -- 1. Load and validate order
  SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  IF v_order.status != 'completed' THEN
    RETURN json_build_object('success', false, 'error', 'لا يمكن إلغاء أمر تعبئة بحالة ' || v_order.status);
  END IF;

  v_station_id := v_order.station_id;
  IF v_station_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'لم يتم تحديد المحطة');
  END IF;

  -- 2. Reverse Double-Entry Journal Entry
  IF v_order.journal_entry_id IS NOT NULL THEN
    DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_order.journal_entry_id;
    DELETE FROM public.journal_entries WHERE id = v_order.journal_entry_id;
  ELSE
    FOR v_je_id IN
      SELECT id FROM public.journal_entries WHERE source_type = 'packing_order' AND source_id = p_packing_order_id::text
    LOOP
      DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id;
      DELETE FROM public.journal_entries WHERE id = v_je_id;
    END LOOP;
  END IF;

  -- 3. Reverse Cost Items Payments
  FOR r_cost IN
    SELECT * FROM public.packing_order_cost_items
    WHERE packing_order_id = p_packing_order_id
  LOOP
    v_had_treasury_tx := (r_cost.treasury_transaction_id IS NOT NULL);
    v_had_bank_tx     := (r_cost.bank_transaction_id IS NOT NULL);

    v_supplier_id := NULL;
    IF r_cost.currency_snapshot IS NOT NULL AND r_cost.currency_snapshot ? 'supplier_id' THEN
      v_supplier_id := NULLIF(r_cost.currency_snapshot->>'supplier_id', '')::uuid;
    END IF;

    -- Treasury Reversal
    IF v_had_treasury_tx THEN
      SELECT * INTO v_treasury_tx
      FROM public.treasury_transactions
      WHERE id = r_cost.treasury_transaction_id;

      IF FOUND THEN
        SELECT * INTO v_treasury_bal
        FROM public.treasury_balances
        WHERE treasury_id = v_treasury_tx.treasury_id
          AND currency   = v_treasury_tx.currency
        FOR UPDATE;

        IF FOUND THEN
          UPDATE public.treasury_balances
          SET balance    = v_treasury_bal.balance + v_treasury_tx.amount,
              updated_at = NOW()
          WHERE treasury_id = v_treasury_tx.treasury_id
            AND currency   = v_treasury_tx.currency;

          INSERT INTO public.treasury_transactions (
            treasury_id, type, currency, amount,
            balance_before, balance_after,
            description, supplier_id, created_by
          ) VALUES (
            v_treasury_tx.treasury_id,
            'return_in',
            v_treasury_tx.currency,
            v_treasury_tx.amount,
            v_treasury_bal.balance,
            v_treasury_bal.balance + v_treasury_tx.amount,
            'عكس سداد بند تكلفة أمر تعبئة ملغي: أمر ' || p_packing_order_id::text
              || ' (مرجع قيد: ' || v_treasury_tx.id::text || ')',
            v_treasury_tx.supplier_id,
            auth.uid()
          ) RETURNING id INTO v_reversal_tx_id;
        END IF;

        UPDATE public.packing_order_cost_items
        SET treasury_transaction_id = NULL
        WHERE id = r_cost.id;
      END IF;
    END IF;

    -- Bank Reversal
    IF v_had_bank_tx THEN
      SELECT * INTO v_bank_tx
      FROM public.bank_account_transactions
      WHERE id = r_cost.bank_transaction_id;

      IF FOUND THEN
        IF v_bank_tx.type = 'deposit' THEN
          v_bank_bal_diff := -v_bank_tx.amount;
        ELSE
          v_bank_bal_diff := v_bank_tx.amount;
        END IF;

        UPDATE public.bank_accounts
        SET balance = balance + v_bank_bal_diff
        WHERE id = v_bank_tx.bank_account_id;

        INSERT INTO public.bank_account_transactions (
          bank_account_id, type, amount,
          balance_before, balance_after,
          description, entity_type, entity_id, created_by
        )
        SELECT
          v_bank_tx.bank_account_id,
          CASE WHEN v_bank_tx.type = 'deposit' THEN 'withdrawal' ELSE 'deposit' END,
          v_bank_tx.amount,
          ba.balance - v_bank_bal_diff,
          ba.balance,
          'عكس سداد بند تكلفة أمر تعبئة ملغي: أمر ' || p_packing_order_id::text
            || ' (مرجع قيد: ' || v_bank_tx.id::text || ')',
          v_bank_tx.entity_type,
          v_bank_tx.entity_id,
          auth.uid()
        FROM public.bank_accounts ba
        WHERE ba.id = v_bank_tx.bank_account_id;

        UPDATE public.packing_order_cost_items
        SET bank_transaction_id = NULL
        WHERE id = r_cost.id;
      END IF;
    END IF;

    -- Supplier Credit Reversal
    IF NOT v_had_treasury_tx AND NOT v_had_bank_tx AND v_supplier_id IS NOT NULL THEN
      v_rate        := COALESCE(NULLIF(r_cost.exchange_rate, 0), 1.0);
      v_curr        := COALESCE(NULLIF(r_cost.original_currency, ''), 'EGP');
      v_amt_foreign := ROUND(r_cost.base_amount / v_rate, 2);

      IF v_amt_foreign > 0 THEN
        UPDATE public.suppliers
        SET outstanding_balance = GREATEST(0, COALESCE(outstanding_balance, 0) - v_amt_foreign)
        WHERE id = v_supplier_id;

        DELETE FROM public.ledger_entries
        WHERE id = (
          SELECT id FROM public.ledger_entries
          WHERE entity_type    = 'supplier'
            AND entity_id      = v_supplier_id::text
            AND entry_type     = 'credit'
            AND reference_type = 'packing_cost'
            AND reference_text = p_packing_order_id::text
            AND amount         = v_amt_foreign
          ORDER BY created_at DESC
          LIMIT 1
        );
      END IF;
    END IF;
  END LOOP;

  -- 4. Restore Stock Allocations (Fruit Batches & Packaging Materials)
  v_notes := CASE WHEN v_order.notes IS NOT NULL AND v_order.notes != ''
    THEN v_order.notes::jsonb ELSE '{}'::jsonb END;

  IF v_notes ? 'fruit_allocation' THEN
    v_el := v_notes->'fruit_allocation';
    IF jsonb_typeof(v_el) = 'array' THEN
      FOR i IN 0..jsonb_array_length(v_el) - 1 LOOP
        v_allocations := v_allocations || jsonb_build_array(v_el->i);
      END LOOP;
    ELSIF jsonb_typeof(v_el) = 'object' THEN
      v_allocations := v_allocations || jsonb_build_array(v_el);
    END IF;
  ELSE
    FOR r_line IN SELECT * FROM public.packing_order_lines WHERE packing_order_id = p_packing_order_id LOOP
      IF r_line.batch_id IS NOT NULL AND r_line.quantity > 0 THEN
        v_allocations := v_allocations || jsonb_build_array(
          jsonb_build_object(
            'batch_id', r_line.batch_id,
            'quantity', r_line.quantity,
            'product_name', r_line.product_name,
            'product_code', ''
          )
        );
      END IF;
    END LOOP;
  END IF;

  IF v_notes ? 'materials' THEN
    FOR v_el IN SELECT jsonb_array_elements(v_notes->'materials')
    LOOP
      v_allocations := v_allocations || jsonb_build_array(
        jsonb_build_object(
          'batch_id',    v_el->>'batch_id',
          'quantity',    v_el->>'used_qty',
          'product_name',v_el->>'product_name',
          'product_code',COALESCE(v_el->>'product_code', '')
        )
      );
    END LOOP;
  END IF;

  IF jsonb_array_length(v_allocations) > 0 THEN
    PERFORM restore_station_batch_allocations(v_station_id, v_allocations);
  END IF;

  -- 5. Mark order cancelled
  UPDATE public.packing_orders
  SET status = 'cancelled',
      journal_entry_id = NULL,
      updated_at = NOW()
  WHERE id = p_packing_order_id;

  RETURN json_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_confirm_packing_order(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_cancel_packing_order(bigint) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
