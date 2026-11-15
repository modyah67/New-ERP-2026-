-- ============================================================================
-- Migration: 20261003000002_add_admin_expenses_cost_type.sql
-- Description: Add Administrative Expenses ("مصاريف إدارية") Cost Type
--              under Root 3 (313 -> 3133 -> 31331) with proper Account Mapping,
--              Cost Center, and idempotent GL processing without touching suppliers.
-- ============================================================================

DO $$
DECLARE
    v_company_id UUID;
    v_parent_313_id BIGINT;
    v_parent_3133_id BIGINT;
    v_leaf_account_id BIGINT;
    v_cost_category_id INTEGER;
    v_cost_center_code TEXT := 'CC-ADMIN-EXPENSES';
BEGIN
    SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;

    -- 1. Locate Parent Branch 313 (مصروفات إداريه)
    SELECT id INTO v_parent_313_id 
    FROM public.accounts 
    WHERE account_code = '313' 
      AND (company_id = v_company_id OR company_id IS NULL)
      AND deleted_at IS NULL
    LIMIT 1;

    IF v_parent_313_id IS NULL THEN
        SELECT id INTO v_parent_313_id 
        FROM public.accounts 
        WHERE account_code = '313'
        LIMIT 1;
    END IF;

    IF v_parent_313_id IS NULL THEN
        RAISE EXCEPTION 'Parent account 313 (مصروفات إداريه) not found in Chart of Accounts';
    END IF;

    -- 2. Verify or create Level 4 Control Account: 3133 (مصاريف إدارية)
    SELECT id INTO v_parent_3133_id
    FROM public.accounts
    WHERE account_code = '3133'
      AND (company_id = v_company_id OR company_id IS NULL)
      AND deleted_at IS NULL
    LIMIT 1;

    IF v_parent_3133_id IS NULL THEN
        INSERT INTO public.accounts (
            account_code, name, account_name, account_type,
            normal_balance, is_leaf, allow_posting, is_active, level,
            parent_id, company_id
        ) VALUES (
            '3133',
            'Administrative Expenses Control',
            'مصاريف إدارية',
            'expense',
            'Debit',
            FALSE,
            FALSE,
            TRUE,
            4,
            v_parent_313_id,
            v_company_id
        )
        ON CONFLICT (account_code) DO UPDATE
        SET is_active = TRUE
        RETURNING id INTO v_parent_3133_id;
    END IF;

    -- 3. Verify or create Level 5 Leaf Account: 31331 (مصاريف إدارية)
    SELECT id INTO v_leaf_account_id
    FROM public.accounts
    WHERE account_code = '31331'
      AND (company_id = v_company_id OR company_id IS NULL)
      AND deleted_at IS NULL
    LIMIT 1;

    IF v_leaf_account_id IS NULL THEN
        INSERT INTO public.accounts (
            account_code, name, account_name, account_type,
            normal_balance, is_leaf, allow_posting, is_active, level,
            parent_id, company_id
        ) VALUES (
            '31331',
            'مصاريف إدارية',
            'مصاريف إدارية',
            'expense',
            'Debit',
            TRUE,
            TRUE,
            TRUE,
            5,
            v_parent_3133_id,
            v_company_id
        )
        ON CONFLICT (account_code) DO UPDATE
        SET is_active = TRUE,
            allow_posting = TRUE,
            account_name = 'مصاريف إدارية'
        RETURNING id INTO v_leaf_account_id;
    END IF;

    -- 4. Create or update Cost Center for Administrative Expenses
    INSERT INTO public.cost_centers (
        code, name, name_ar, name_en, cost_center_type, is_active, color, icon, description
    ) VALUES (
        v_cost_center_code,
        'مصاريف إدارية',
        'مصاريف إدارية',
        'Administrative Expenses',
        'operational',
        TRUE,
        '#0284C7',
        'business_center_rounded',
        'مركز تكلفة مخصص للمصاريف الإدارية والعمومية'
    )
    ON CONFLICT (code) DO UPDATE
    SET is_active = TRUE,
        name_ar = 'مصاريف إدارية';

    -- 5. Insert or update in cost_report_categories
    INSERT INTO public.cost_report_categories (
        name, scope, is_system, type, account_id, supplier_type, cost_center_id
    ) VALUES (
        'مصاريف إدارية',
        'all',
        FALSE,
        'indirect',
        v_leaf_account_id,
        'admin',
        v_cost_center_code
    )
    ON CONFLICT (name) DO UPDATE
    SET scope = 'all',
        account_id = v_leaf_account_id,
        supplier_type = 'admin',
        cost_center_id = v_cost_center_code
    RETURNING id INTO v_cost_category_id;

    -- Link account to cost center
    UPDATE public.accounts
    SET cost_center_id = v_cost_center_code
    WHERE id = v_leaf_account_id;

    RAISE NOTICE 'Administrative Expenses Cost Type registered successfully: cat_id=%, account_id=%, code=31331', 
        v_cost_category_id, v_leaf_account_id;
END;
$$;

-- Ensure fn_resolve_category_parent_account routes 'admin' / 'general_admin' properly
CREATE OR REPLACE FUNCTION public.fn_resolve_category_parent_account(
    p_scope TEXT,
    p_name TEXT,
    p_supplier_type TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_clean_name TEXT := LOWER(TRIM(COALESCE(p_name, '')));
    v_clean_scope TEXT := LOWER(TRIM(COALESCE(p_scope, '')));
    v_clean_type TEXT := LOWER(TRIM(COALESCE(p_supplier_type, '')));
BEGIN
    -- 0. Administrative Expenses -> 3133
    IF v_clean_type = 'admin' OR v_clean_scope IN ('general_admin', 'admin') OR v_clean_name ~* '(إدار|ادار|admin)' THEN
        RETURN '3133';
    END IF;

    -- 1. Station Suppliers / Operation Costs -> Level 4 Control: 3124 (تكاليف ومصروفات تشغيل المحطات)
    IF v_clean_type IN ('station', 'stations') OR v_clean_name ~* '(محطة|تبريد|تشغيل|حفظ مبرد|تقفيل كرتون|تعتيق|تدوير|تبخير|station)' THEN
        RETURN '3124';
    END IF;

    -- 2. Deduction Suppliers / Inspection Fees -> Level 4 Control: 3126 (رسوم فحص وتخصيمات التشغيل)
    IF v_clean_type IN ('deduction', 'deductions') OR v_clean_name ~* '(تخصيم|فحص|تحليل|عينة|عينات|حجر زراعي|سلامة غذاء|وجات|deduction|inspection)' THEN
        RETURN '3126';
    END IF;

    -- 3. Packaging waste / scrap -> 3124 (هالك وفاقد التشغيل)
    IF v_clean_scope = 'packing_waste' OR v_clean_name ~* '(هالك|فاقد|تالف|توالف|waste|scrap)' THEN
        RETURN '3124';
    END IF;

    -- 4. Direct Sales Costs / Produce purchases -> 3411 (تكاليف المبيعات)
    IF v_clean_name ~* '(محصول|محاصيل|شراء خام|فراولة|مانجو|مبيعات|خام|produce|crop)' THEN
        RETURN '3411';
    END IF;

    -- 5. Shipping, Freight, Customs, Logistics -> 3411 (مصروفات الشحن والتخليص واللوجستيات)
    IF v_clean_scope = 'shipment' OR v_clean_name ~* '(شحن|نولون|تخليص|لوجست|مشال|نقل|جمارك|مخلص|shipping|freight|customs|logistics)' THEN
        RETURN '3411';
    END IF;

    -- 6. Fallback based on scope
    IF v_clean_scope = 'packing' THEN
        RETURN '3124';
    ELSIF v_clean_scope = 'shipment' THEN
        RETURN '3411';
    ELSE
        RETURN '3133';
    END IF;
END;
$$;

-- Ensure rpc_confirm_packing_costs properly handles admin costs mapped to account_id
CREATE OR REPLACE FUNCTION public.rpc_confirm_packing_costs(p_packing_order_id bigint)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_order RECORD;
  v_notes JSONB;
  v_order_num TEXT;
  v_company_id UUID;

  v_tot_cost_items NUMERIC := 0;
  v_posted_cost_items NUMERIC := 0;

  v_finished_inv_acc INT;
  v_credit_acc INT;
  v_supp_leaf_acc INT;

  v_je_id INT;
  v_entry_num TEXT;
  v_sum_debit NUMERIC := 0;
  v_sum_credit NUMERIC := 0;

  v_el JSONB;
  r_cost RECORD;
  r_prev_trans RECORD;
  v_supplier_id UUID;
  v_trans_supplier_id INT;
  v_supp_str TEXT;
  v_amt_egp NUMERIC;
  v_target_line_idx INT;
  v_max_cost_item_id BIGINT;
  v_existing_item RECORD;
  v_status_to_set TEXT;
  v_expected_to_set NUMERIC;
  v_actual_to_set NUMERIC;
  v_variance_to_set NUMERIC;
  v_consumed_trucks NUMERIC;
  v_category_account_id BIGINT;
BEGIN
  SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  -- Validate prerequisite: packaging must be confirmed first
  IF (v_order.status IN ('draft', 'pending', 'crops_confirmed')) AND v_order.packaging_confirmed_at IS NULL AND v_order.packaging_journal_entry_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'يجب تأكيد مواد التعبئة أولاً قبل تأكيد بنود التكلفة');
  END IF;

  -- Idempotency check: only block if final approved
  IF v_order.status IN ('final_approved', 'completed') THEN
    RETURN json_build_object(
      'success', true,
      'message', 'أمر التعبئة معتمد نهائياً ومقفل بالكامل',
      'status', v_order.status,
      'journal_entry_id', v_order.costs_journal_entry_id
    );
  END IF;

  BEGIN
    v_notes := COALESCE(v_order.notes::jsonb, '{}'::jsonb);
    IF jsonb_typeof(v_notes) = 'string' THEN
      v_notes := (v_notes #>> '{}')::jsonb;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_notes := '{}'::jsonb;
  END;

  v_order_num := COALESCE(v_order.order_number, p_packing_order_id::text);

  -- A. Revert previously deducted trip stock for idempotency if re-confirming this order
  FOR r_prev_trans IN 
    SELECT supplier_id, SUM(truck_count) as total_prev_trucks 
    FROM public.transport_transactions 
    WHERE reference_id = p_packing_order_id::text 
      AND type IN ('packing_consumption', 'packing_order_consumption')
    GROUP BY supplier_id
  LOOP
    UPDATE public.transport_suppliers
    SET truck_balance = COALESCE(truck_balance, 0) + r_prev_trans.total_prev_trucks,
        updated_at = now()
    WHERE id = r_prev_trans.supplier_id;
  END LOOP;

  DELETE FROM public.transport_transactions 
  WHERE reference_id = p_packing_order_id::text 
    AND type IN ('packing_consumption', 'packing_order_consumption');

  -- B. Rebuild Cost Items from Notes preserving any existing actual settlements
  IF v_notes ? 'cost_items' AND jsonb_typeof(v_notes->'cost_items') = 'array' THEN
    DELETE FROM public.packing_order_cost_items 
    WHERE packing_order_id = p_packing_order_id AND cost_status <> 'actual';

    SELECT COALESCE(MAX(id), 0) INTO v_max_cost_item_id FROM public.packing_order_cost_items;
    IF v_max_cost_item_id > 0 THEN
      PERFORM setval(pg_get_serial_sequence('public.packing_order_cost_items', 'id'), v_max_cost_item_id);
    ELSE
      PERFORM setval(pg_get_serial_sequence('public.packing_order_cost_items', 'id'), 1, false);
    END IF;

    FOR v_el IN SELECT jsonb_array_elements(v_notes->'cost_items')
    LOOP
      v_amt_egp := COALESCE((v_el->>'total_egp')::numeric, (v_el->>'total')::numeric, 0);
      IF v_amt_egp > 0 THEN
        v_supplier_id := NULL;
        v_supp_str := v_el->>'supplier_id';
        IF v_supp_str IS NOT NULL AND v_supp_str != '' AND v_supp_str != 'null' THEN
          BEGIN
            v_supplier_id := v_supp_str::uuid;
          EXCEPTION WHEN OTHERS THEN
            v_supplier_id := NULL;
          END;
        END IF;

        v_target_line_idx := NULL;
        IF v_el ? 'target_line_index' AND v_el->>'target_line_index' != '' AND v_el->>'target_line_index' != 'null' THEN
          v_target_line_idx := (v_el->>'target_line_index')::integer;
        END IF;

        v_status_to_set := COALESCE(NULLIF(v_el->>'cost_status', ''), 'expected');
        v_expected_to_set := COALESCE((v_el->>'expected_amount')::numeric, v_amt_egp);
        v_actual_to_set := (v_el->>'actual_amount')::numeric;
        v_variance_to_set := COALESCE((v_el->>'variance_amount')::numeric, 0);

        -- Check if an item already exists with this name and supplier to avoid duplicate insert
        SELECT * INTO v_existing_item 
        FROM public.packing_order_cost_items 
        WHERE packing_order_id = p_packing_order_id 
          AND name = (v_el->>'name')
          AND (supplier_id = COALESCE(v_supp_str, v_supplier_id::text) OR (supplier_id IS NULL AND v_supp_str IS NULL))
        LIMIT 1;

        IF v_existing_item.id IS NOT NULL THEN
          UPDATE public.packing_order_cost_items
          SET base_amount = CASE WHEN v_existing_item.cost_status = 'actual' THEN v_existing_item.base_amount ELSE v_amt_egp END,
              original_amount = CASE WHEN v_existing_item.cost_status = 'actual' THEN v_existing_item.original_amount ELSE COALESCE((v_el->>'total')::numeric, v_amt_egp) END,
              expected_amount = COALESCE(v_existing_item.expected_amount, v_amt_egp),
              truck_count = COALESCE((v_el->>'truck_count')::numeric, (v_el->>'quantity')::numeric, 1.0),
              quantity = (v_el->>'quantity')::numeric,
              unit_price = (v_el->>'unit_price')::numeric,
              transport_supplier_id = (v_el->>'transport_supplier_id')::integer,
              report_category_id = COALESCE((v_el->>'report_category_id')::integer, v_existing_item.report_category_id),
              currency_snapshot = jsonb_build_object(
                'supplier_id', COALESCE(v_supp_str, v_supplier_id::text),
                'supplier_name', v_el->>'supplier_name',
                'supplier_type', v_el->>'supplier_type',
                'transport_supplier_id', v_el->>'transport_supplier_id',
                'report_category_id', v_el->>'report_category_id',
                'truck_count', COALESCE((v_el->>'truck_count')::numeric, (v_el->>'quantity')::numeric, 1.0),
                'quantity', (v_el->>'quantity')::numeric,
                'unit_price', (v_el->>'unit_price')::numeric,
                'target_line_index', v_target_line_idx,
                'cost_status', v_status_to_set,
                'expected_amount', v_expected_to_set
              )
          WHERE id = v_existing_item.id;
        ELSE
          INSERT INTO public.packing_order_cost_items (
            packing_order_id, name, category,
            base_amount, original_amount, original_currency,
            payment_source_type, payment_source_id,
            allocation_method, target_line_id,
            currency_snapshot, supplier_id, payment_status, paid_amount,
            cost_status, expected_amount, actual_amount, variance_amount, invoice_ref,
            truck_count, quantity, unit_price, transport_supplier_id, report_category_id
          ) VALUES (
            p_packing_order_id,
            v_el->>'name',
            CASE 
              WHEN v_el->>'category' IN ('fruit', 'material', 'logistics', 'admin', 'other') THEN v_el->>'category' 
              WHEN (v_el->>'supplier_type') = 'admin' OR (v_el->>'name') = 'مصاريف إدارية' THEN 'admin'
              ELSE 'other' 
            END,
            v_amt_egp,
            COALESCE((v_el->>'total')::numeric, v_amt_egp),
            COALESCE(NULLIF(v_el->>'currency', ''), COALESCE(v_el->>'supplier_currency', 'EGP')),
            'none',
            NULL,
            v_el->>'allocation_method',
            v_target_line_idx,
            jsonb_build_object(
              'supplier_id', COALESCE(v_supp_str, v_supplier_id::text),
              'supplier_name', v_el->>'supplier_name',
              'supplier_type', v_el->>'supplier_type',
              'transport_supplier_id', v_el->>'transport_supplier_id',
              'report_category_id', v_el->>'report_category_id',
              'truck_count', COALESCE((v_el->>'truck_count')::numeric, (v_el->>'quantity')::numeric, 1.0),
              'quantity', (v_el->>'quantity')::numeric,
              'unit_price', (v_el->>'unit_price')::numeric,
              'target_line_index', v_target_line_idx,
              'cost_status', v_status_to_set,
              'expected_amount', v_expected_to_set
            ),
            COALESCE(v_supp_str, v_supplier_id::text),
            'unpaid',
            0,
            v_status_to_set,
            v_expected_to_set,
            v_actual_to_set,
            v_variance_to_set,
            v_el->>'invoice_ref',
            COALESCE((v_el->>'truck_count')::numeric, (v_el->>'quantity')::numeric, 1.0),
            (v_el->>'quantity')::numeric,
            (v_el->>'unit_price')::numeric,
            (v_el->>'transport_supplier_id')::integer,
            (v_el->>'report_category_id')::integer
          );
        END IF;
      END IF;
    END LOOP;
  END IF;

  -- 2. Calculate Total Cost Items
  v_tot_cost_items := 0;
  FOR r_cost IN SELECT * FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id
  LOOP
    v_tot_cost_items := v_tot_cost_items + COALESCE(r_cost.base_amount, 0);
  END LOOP;
  IF v_tot_cost_items = 0 THEN
    v_tot_cost_items := COALESCE(v_order.other_cost_base, 0);
  END IF;

  -- 3. Resolve GL Accounts
  SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;
  IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM sys_companies LIMIT 1; END IF;

  v_finished_inv_acc := COALESCE(public.resolve_gl_account('12413', v_company_id), public.resolve_gl_account('1031', v_company_id));

  -- 4. Create Costs Confirmation Journal Entry & Post Liabilities
  IF v_tot_cost_items > 0 THEN
    IF v_order.costs_journal_entry_id IS NOT NULL THEN
      v_je_id := v_order.costs_journal_entry_id;
      DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id;
      UPDATE public.journal_entries
      SET description = 'قيد إثبات تكاليف ومصروفات وموردي أمر تعبئة رقم ' || v_order_num,
          updated_at = now()
      WHERE id = v_je_id;
    ELSE
      INSERT INTO public.journal_entries (
        entry_number, entry_date, description, status,
        is_auto_generated, source_type, source_id, company_id,
        created_by, created_at, updated_at
      ) VALUES (
        'PENDING',
        COALESCE((v_order.packed_at AT TIME ZONE 'Africa/Cairo')::date, (v_order.created_at AT TIME ZONE 'Africa/Cairo')::date, (CURRENT_TIMESTAMP AT TIME ZONE 'Africa/Cairo')::date),
        'قيد إثبات تكاليف ومصروفات وموردي أمر تعبئة رقم ' || v_order_num,
        'posted', true, 'packing_order_costs', p_packing_order_id::text, v_company_id,
        auth.uid(), now(), now()
      ) RETURNING id INTO v_je_id;

      v_entry_num := public.fn_get_next_sequence(v_company_id, 'packing_cost', NULL, NULL);
      IF v_entry_num IS NULL OR v_entry_num = '' THEN
        v_entry_num := 'POCST-' || LPAD(v_je_id::text, 5, '0');
      END IF;
      UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;
    END IF;

    -- DR Finished Goods Inventory (12413 / 1031)
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_finished_inv_acc, v_tot_cost_items, 0, 'EGP', v_tot_cost_items,
      'تكاليف ومصروفات أمر تعبئة ' || v_order_num, v_company_id
    );
    v_sum_debit := v_sum_debit + v_tot_cost_items;

    -- CR Balancing Accounts & Sub-Ledger Posting
    v_posted_cost_items := 0;
    FOR r_cost IN
      SELECT * FROM public.packing_order_cost_items
      WHERE packing_order_id = p_packing_order_id AND COALESCE(base_amount, 0) > 0
    LOOP
      v_credit_acc := NULL;
      v_supplier_id := NULL;
      v_trans_supplier_id := NULL;
      v_supp_str := NULL;
      v_category_account_id := NULL;

      IF r_cost.currency_snapshot IS NOT NULL THEN
        v_supp_str := r_cost.currency_snapshot->>'supplier_id';
      END IF;
      IF v_supp_str IS NULL OR v_supp_str = '' OR v_supp_str = 'null' THEN
        v_supp_str := r_cost.supplier_id;
      END IF;

      IF v_supp_str IS NOT NULL AND v_supp_str != '' AND v_supp_str != 'null' THEN
        BEGIN
          v_supplier_id := v_supp_str::uuid;
        EXCEPTION WHEN OTHERS THEN
          v_supplier_id := NULL;
        END;

        IF v_supplier_id IS NOT NULL THEN
          SELECT account_id INTO v_supp_leaf_acc FROM public.suppliers WHERE id = v_supplier_id;
          IF v_supp_leaf_acc IS NOT NULL THEN v_credit_acc := v_supp_leaf_acc; END IF;
        ELSE
          -- Check transport supplier (integer ID)
          BEGIN
            v_trans_supplier_id := v_supp_str::integer;
          EXCEPTION WHEN OTHERS THEN
            v_trans_supplier_id := NULL;
          END;
        END IF;
      END IF;

      -- CASE 1: Standard Supplier (General, Station, Deduction, Packaging)
      IF v_supplier_id IS NOT NULL THEN
        IF v_credit_acc IS NULL THEN
          v_credit_acc := public.fn_resolve_packing_cost_supplier_account(v_supplier_id, v_company_id);
        END IF;
        IF v_credit_acc IS NULL THEN
          v_credit_acc := public.resolve_gl_account('2000', v_company_id);
        END IF;

        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_je_id, v_credit_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,
          'مصروفات أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'تكلفة إضافية'), v_company_id
        );
        v_sum_credit := v_sum_credit + r_cost.base_amount;
        v_posted_cost_items := v_posted_cost_items + r_cost.base_amount;

        -- Post Sub-Ledger Entry for Supplier
        IF NOT EXISTS (
          SELECT 1 FROM public.ledger_entries 
          WHERE entity_id = v_supplier_id::text 
            AND reference_type = 'packing_cost' 
            AND reference_id = p_packing_order_id
            AND description LIKE '%' || COALESCE(r_cost.name, '') || '%'
        ) THEN
          INSERT INTO public.ledger_entries (
            entity_id, entity_type, amount, currency, entry_type, reference_id, reference_type, reference_text, description, created_at
          ) VALUES (
            v_supplier_id::text, 'supplier', r_cost.original_amount, r_cost.original_currency,
            'credit', p_packing_order_id, 'packing_cost', p_packing_order_id::text,
            'بند تكلفة تقديرية: ' || COALESCE(r_cost.name, '') || ' (أمر ' || v_order_num || ')', now()
          );
          UPDATE public.suppliers SET outstanding_balance = COALESCE(outstanding_balance, 0) + r_cost.base_amount WHERE id = v_supplier_id;
        END IF;

      -- CASE 2: Transport Supplier
      ELSIF v_trans_supplier_id IS NOT NULL THEN
        SELECT id INTO v_credit_acc
        FROM public.accounts
        WHERE (code = '51311' OR account_code = '51311' OR name ILIKE '%مصاريف نقل%' OR name ILIKE '%نقل%')
          AND is_active = true
        ORDER BY CASE WHEN code = '51311' OR account_code = '51311' THEN 0 ELSE 1 END
        LIMIT 1;
        IF v_credit_acc IS NULL THEN
          v_credit_acc := public.resolve_gl_account('51311', v_company_id);
        END IF;
        IF v_credit_acc IS NULL THEN
          v_credit_acc := public.resolve_gl_account('5100', v_company_id);
        END IF;
        IF v_credit_acc IS NULL THEN
          v_credit_acc := public.resolve_gl_account('2000', v_company_id);
        END IF;

        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_je_id, v_credit_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,
          'تحميل تكلفة نقل أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'نقل'), v_company_id
        );
        v_sum_credit := v_sum_credit + r_cost.base_amount;
        v_posted_cost_items := v_posted_cost_items + r_cost.base_amount;

        v_consumed_trucks := COALESCE(
          NULLIF(r_cost.truck_count, 0),
          NULLIF((r_cost.currency_snapshot->>'truck_count')::numeric, 0),
          NULLIF((r_cost.currency_snapshot->>'quantity')::numeric, 0),
          1.0
        );

        UPDATE public.transport_suppliers
        SET truck_balance = COALESCE(truck_balance, 0) - v_consumed_trucks,
            updated_at = now()
        WHERE id = v_trans_supplier_id;

        INSERT INTO public.transport_transactions (
          supplier_id, type, amount, currency, reference_id,
          description, truck_count, notes, journal_entry_id, date, created_at
        ) VALUES (
          v_trans_supplier_id,
          'packing_consumption',
          0,
          'EGP',
          p_packing_order_id::text,
          'استهلاك نقلات أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'نقل'),
          v_consumed_trucks,
          'استهلاك تشغيلي ' || v_consumed_trucks::text || ' نقلة من الرصيد بدون أثر مالي على كشف الحساب',
          v_je_id,
          (COALESCE(v_order.packed_at, now()) AT TIME ZONE 'Africa/Cairo')::date,
          now()
        );

      -- CASE 3: Administrative / Category-Mapped / Unassigned General Cost
      ELSE
        -- Priority 1: Check category mapped account (e.g. 31331 for مصاريف إدارية)
        IF r_cost.report_category_id IS NOT NULL THEN
          SELECT account_id INTO v_category_account_id
          FROM public.cost_report_categories
          WHERE id = r_cost.report_category_id;
        END IF;

        IF v_category_account_id IS NULL THEN
          SELECT account_id INTO v_category_account_id
          FROM public.cost_report_categories
          WHERE name = r_cost.name
          LIMIT 1;
        END IF;

        IF v_category_account_id IS NOT NULL THEN
          v_credit_acc := v_category_account_id;
        ELSE
          v_credit_acc := public.resolve_gl_account('2000', v_company_id);
        END IF;

        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_je_id, v_credit_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,
          'مصروفات أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'تكلفة إضافية'), v_company_id
        );
        v_sum_credit := v_sum_credit + r_cost.base_amount;
        v_posted_cost_items := v_posted_cost_items + r_cost.base_amount;
      END IF;
    END LOOP;

    -- Fallback for unallocated general costs
    IF v_tot_cost_items > v_posted_cost_items THEN
      v_credit_acc := public.resolve_gl_account('2000', v_company_id);
      INSERT INTO public.account_ledger_entries (
        journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
      ) VALUES (
        v_je_id, v_credit_acc, 0, (v_tot_cost_items - v_posted_cost_items), 'EGP', (v_tot_cost_items - v_posted_cost_items),
        'مصروفات إضافية أمر تعبئة ' || v_order_num, v_company_id
      );
      v_sum_credit := v_sum_credit + (v_tot_cost_items - v_posted_cost_items);
    END IF;

    -- Sub-cent penny rounding absorption
    IF v_sum_debit != v_sum_credit AND v_tot_cost_items > 0 THEN
      UPDATE public.account_ledger_entries
      SET debit = debit + (v_sum_credit - v_sum_debit),
          amount_in_base_currency = amount_in_base_currency + (v_sum_credit - v_sum_debit)
      WHERE journal_entry_id = v_je_id
        AND account_id = v_finished_inv_acc
        AND debit > 0;
      v_sum_debit := v_sum_credit;
    END IF;
  END IF;

  -- 5. Update packing order status and stage tracking
  v_notes := jsonb_set(v_notes, '{workflow_stages,costs}', jsonb_build_object(
    'confirmed_at', now(),
    'journal_entry_id', v_je_id,
    'total_cost_items', v_tot_cost_items
  ), true);

  UPDATE public.packing_orders
  SET status = CASE
        WHEN status IN ('final_approved', 'completed') THEN status
        ELSE 'costs_confirmed'
      END,
      other_cost_base = v_tot_cost_items,
      costs_confirmed_at = COALESCE(costs_confirmed_at, now()),
      costs_journal_entry_id = v_je_id,
      notes = v_notes::text,
      updated_at = now()
  WHERE id = p_packing_order_id;

  RETURN json_build_object(
    'success', true,
    'status', 'costs_confirmed',
    'journal_entry_id', v_je_id,
    'total_cost_items', v_tot_cost_items,
    'message', 'تم تأكيد التكاليف والمصروفات الإضافية بنجاح'
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_confirm_packing_costs(bigint) TO authenticated, service_role, anon;

NOTIFY pgrst, 'reload schema';
