-- ============================================================================
-- Migration: 20261005000001_add_engineer_expenses_cost_type_and_custody_settlement.sql
-- Description: Add "Engineer Expenses" ("مصاريف مهندسين") Cost Type
--              linked to Employee Cash Custodies (العهد النقدية للموظفين),
--              supporting two-stage workflow: Estimated Cost -> Actual Settlement,
--              with variance tracking, custody balance updates, and automated GL entries.
-- ============================================================================

-- 0. Widen category CHECK constraint (fixes error 23514
--    "violates check constraint packing_order_cost_items_category_check")
ALTER TABLE public.packing_order_cost_items
  DROP CONSTRAINT IF EXISTS packing_order_cost_items_category_check;
ALTER TABLE public.packing_order_cost_items
  ADD CONSTRAINT packing_order_cost_items_category_check
  CHECK (category = ANY (ARRAY['fruit','material','logistics','other','admin','engineer_expenses']));


-- 1. Add engineer expenses tracking columns to packing_order_cost_items
ALTER TABLE public.packing_order_cost_items
  ADD COLUMN IF NOT EXISTS custody_id INTEGER NULL,
  ADD COLUMN IF NOT EXISTS engineer_id TEXT NULL,
  ADD COLUMN IF NOT EXISTS engineer_name TEXT NULL,
  ADD COLUMN IF NOT EXISTS is_engineer_cost_settled BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS expense_account_id BIGINT NULL,
  ADD COLUMN IF NOT EXISTS expense_account_name TEXT NULL;

-- 2. Add engineer cost tracking column to packing_orders
ALTER TABLE public.packing_orders
  ADD COLUMN IF NOT EXISTS is_engineer_cost_settled BOOLEAN NOT NULL DEFAULT TRUE;

-- Add index for custody performance queries
CREATE INDEX IF NOT EXISTS idx_packing_order_cost_items_custody 
  ON public.packing_order_cost_items (custody_id)
  WHERE custody_id IS NOT NULL;

-- 3. Register Chart of Accounts, Cost Center, and Category in Supabase
DO $$
DECLARE
    v_company_id UUID;
    v_parent_312_id BIGINT;
    v_parent_3125_id BIGINT;
    v_leaf_account_id BIGINT;
    v_cost_category_id INTEGER;
    v_cost_center_code TEXT := 'CC-ENG-EXP';
BEGIN
    SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;

    -- 3.1 Locate Parent Operating Costs 312 (تكاليف ومصروفات التشغيل)
    SELECT id INTO v_parent_312_id 
    FROM public.accounts 
    WHERE account_code = '312' 
      AND (company_id = v_company_id OR company_id IS NULL)
      AND deleted_at IS NULL
    LIMIT 1;

    IF v_parent_312_id IS NULL THEN
        SELECT id INTO v_parent_312_id FROM public.accounts WHERE account_code = '312' LIMIT 1;
    END IF;

    -- If 312 is found, create 3125 (مصاريف مهندسين وإشراف موقع)
    IF v_parent_312_id IS NOT NULL THEN
        -- Control Level 4: 3125
        SELECT id INTO v_parent_3125_id
        FROM public.accounts
        WHERE account_code = '3125'
          AND (company_id = v_company_id OR company_id IS NULL)
          AND deleted_at IS NULL
        LIMIT 1;

        IF v_parent_3125_id IS NULL THEN
            INSERT INTO public.accounts (
                account_code, name, account_name, account_type,
                normal_balance, is_leaf, allow_posting, is_active, level,
                parent_id, company_id
            ) VALUES (
                '3125',
                'Engineer & Site Supervision Expenses Control',
                'مصاريف مهندسين وإشراف موقع',
                'expense',
                'Debit',
                FALSE,
                FALSE,
                TRUE,
                4,
                v_parent_312_id,
                v_company_id
            )
            ON CONFLICT (account_code) DO UPDATE
            SET is_active = TRUE
            RETURNING id INTO v_parent_3125_id;
        END IF;

        -- Leaf Level 5: 31251 (مصاريف مهندسين)
        SELECT id INTO v_leaf_account_id
        FROM public.accounts
        WHERE account_code = '31251'
          AND (company_id = v_company_id OR company_id IS NULL)
          AND deleted_at IS NULL
        LIMIT 1;

        IF v_leaf_account_id IS NULL THEN
            INSERT INTO public.accounts (
                account_code, name, account_name, account_type,
                normal_balance, is_leaf, allow_posting, is_active, level,
                parent_id, company_id
            ) VALUES (
                '31251',
                'مصاريف مهندسين',
                'مصاريف مهندسين',
                'expense',
                'Debit',
                TRUE,
                TRUE,
                TRUE,
                5,
                v_parent_3125_id,
                v_company_id
            )
            ON CONFLICT (account_code) DO UPDATE
            SET is_active = TRUE,
                allow_posting = TRUE,
                account_name = 'مصاريف مهندسين'
            RETURNING id INTO v_leaf_account_id;
        END IF;
    END IF;

    -- 3.2 Create or update Cost Center for Engineer Expenses
    INSERT INTO public.cost_centers (
        code, name, name_ar, name_en, cost_center_type, is_active, color, icon, description
    ) VALUES (
        v_cost_center_code,
        'مصاريف مهندسين',
        'مصاريف مهندسين',
        'Engineer Expenses',
        'operational',
        TRUE,
        '#D97706',
        'engineering_rounded',
        'مركز تكلفة مخصص لمصاريف المهندسين والإشراف ومأموريات المواقع'
    )
    ON CONFLICT (code) DO UPDATE
    SET is_active = TRUE,
        name_ar = 'مصاريف مهندسين';

    -- 3.3 Insert into cost_report_categories
    INSERT INTO public.cost_report_categories (
        name, scope, is_system, type, account_id, supplier_type, cost_center_id
    ) VALUES (
        'مصاريف مهندسين',
        'packing',
        FALSE,
        'direct',
        v_leaf_account_id,
        'engineer',
        v_cost_center_code
    )
    ON CONFLICT (name) DO UPDATE
    SET scope = 'packing',
        account_id = COALESCE(v_leaf_account_id, cost_report_categories.account_id),
        supplier_type = 'engineer',
        cost_center_id = v_cost_center_code
    RETURNING id INTO v_cost_category_id;

    IF v_leaf_account_id IS NOT NULL THEN
        UPDATE public.accounts
        SET cost_center_id = v_cost_center_code
        WHERE id = v_leaf_account_id;
    END IF;

    RAISE NOTICE 'Engineer Expenses Cost Type registered successfully: cat_id=%, code=31251', 
        v_cost_category_id;
END;
$$;

-- 4. Update fn_resolve_category_parent_account to route 'engineer' properly
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
    -- 0. Engineer Expenses -> 3125 (مصاريف مهندسين وإشراف موقع)
    IF v_clean_type = 'engineer' OR v_clean_name ~* '(مهندس|مهندسين|اشراف|إشراف)' THEN
        RETURN '3125';
    END IF;

    -- Administrative Expenses -> 3133
    IF v_clean_type = 'admin' OR v_clean_scope IN ('general_admin', 'admin') OR v_clean_name ~* '(إدار|ادار|admin)' THEN
        RETURN '3133';
    END IF;

    -- Station Suppliers / Operation Costs -> Level 4 Control: 3124
    IF v_clean_type IN ('station', 'stations') OR v_clean_name ~* '(محطة|تبريد|تشغيل|حفظ مبرد|تقفيل كرتون|تعتيق|تدوير|تبخير|station)' THEN
        RETURN '3124';
    END IF;

    -- Deduction Suppliers / Inspection Fees -> Level 4 Control: 3126
    IF v_clean_type IN ('deduction', 'deductions') OR v_clean_name ~* '(تخصيم|فحص|تحليل|عينة|عينات|حجر زراعي|سلامة غذاء|وجات|deduction|inspection)' THEN
        RETURN '3126';
    END IF;

    -- Packaging waste / scrap -> 3124
    IF v_clean_scope = 'packing_waste' OR v_clean_name ~* '(هالك|فاقد|تالف|توالف|waste|scrap)' THEN
        RETURN '3124';
    END IF;

    -- Direct Sales Costs / Produce purchases -> 3411
    IF v_clean_name ~* '(محصول|محاصيل|شراء خام|فراولة|مانجو|مبيعات|خام|produce|crop)' THEN
        RETURN '3411';
    END IF;

    -- Shipping, Freight, Customs, Logistics -> 3411
    IF v_clean_scope = 'shipment' OR v_clean_name ~* '(شحن|نولون|تخليص|لوجست|مشال|نقل|جمارك|مخلص|shipping|freight|customs|logistics)' THEN
        RETURN '3411';
    END IF;

    -- Fallback based on scope
    IF v_clean_scope = 'packing' THEN
        RETURN '3124';
    ELSIF v_clean_scope = 'shipment' THEN
        RETURN '3411';
    ELSE
        RETURN '3133';
    END IF;
END;
$$;


-- ============================================================================
-- 5. Canonical rpc_confirm_packing_costs Function
--    (Routing Engineer Expenses to Employee Custody Account instead of Suppliers)
-- ============================================================================
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
  v_transport_default_acc INT;
  v_custody_default_acc INT;

  v_je_id INT;
  v_entry_num TEXT;
  v_sum_debit NUMERIC := 0;
  v_sum_credit NUMERIC := 0;

  v_el JSONB;
  r_cost RECORD;
  v_supplier_id UUID;
  v_trans_supplier_id INT;
  v_custody_id INT;
  v_engineer_name TEXT;
  v_supp_str TEXT;
  v_amt_egp NUMERIC;
  v_target_line_idx INT;
  v_existing_item RECORD;
  v_status_to_set TEXT;
  v_expected_to_set NUMERIC;
  v_actual_to_set NUMERIC;
  v_variance_to_set NUMERIC;
  v_consumed_trucks NUMERIC;
  v_category_account_id BIGINT;
  v_is_transport BOOLEAN;
  v_is_engineer BOOLEAN;
  v_rep_cat_id INT;
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

  v_order_num := COALESCE(v_order.order_number, '#' || p_packing_order_id::text);
  SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
  IF v_company_id IS NULL THEN
    SELECT company_id INTO v_company_id FROM public.accounts WHERE account_code = '1030' LIMIT 1;
  END IF;

  -- Resolve Standard Chart of Accounts
  SELECT id INTO v_finished_inv_acc FROM public.accounts WHERE account_code = '12413' LIMIT 1;
  IF v_finished_inv_acc IS NULL THEN v_finished_inv_acc := public.resolve_gl_account('12413', v_company_id); END IF;

  SELECT id INTO v_transport_default_acc FROM public.accounts WHERE account_code = '21111' LIMIT 1;
  IF v_transport_default_acc IS NULL THEN v_transport_default_acc := public.resolve_gl_account('21111', v_company_id); END IF;

  SELECT id INTO v_custody_default_acc FROM public.accounts WHERE account_code = '1261201' LIMIT 1;
  IF v_custody_default_acc IS NULL THEN
    SELECT id INTO v_custody_default_acc FROM public.accounts WHERE account_code = '12612' LIMIT 1;
  END IF;
  IF v_custody_default_acc IS NULL THEN v_custody_default_acc := public.resolve_gl_account('12612', v_company_id); END IF;

  -- 1. Sync / Materialize Cost Items from notes to packing_order_cost_items
  v_notes := NULL;
  IF v_order.notes IS NOT NULL AND v_order.notes <> '' THEN
    BEGIN
      v_notes := v_order.notes::jsonb;
    EXCEPTION WHEN OTHERS THEN
      v_notes := NULL;
    END;
  END IF;

  IF v_notes IS NOT NULL AND (v_notes ? 'cost_items') AND jsonb_typeof(v_notes->'cost_items') = 'array' THEN
    FOR v_el IN SELECT jsonb_array_elements(v_notes->'cost_items')
    LOOP
      v_amt_egp := COALESCE((v_el->>'total_egp')::numeric, (v_el->>'total')::numeric, 0);
      IF v_amt_egp > 0 THEN
        v_supplier_id := NULL;
        v_trans_supplier_id := NULL;
        v_custody_id := NULL;
        v_engineer_name := NULL;
        v_supp_str := v_el->>'supplier_id';

        IF (v_el->>'category') = 'engineer_expenses' 
           OR (v_el->>'supplier_type') = 'engineer'
           OR (v_el->>'name') ILIKE '%مهندس%'
           OR (v_el->>'name') ILIKE '%اشراف%'
           OR (v_el->>'name') ILIKE '%إشراف%' THEN
          v_is_engineer := true;
          IF v_el ? 'custody_id' AND (v_el->>'custody_id') IS NOT NULL AND (v_el->>'custody_id') <> '' THEN
            v_custody_id := (v_el->>'custody_id')::integer;
          ELSIF v_supp_str ~ '^[0-9]+$' THEN
            v_custody_id := v_supp_str::integer;
          END IF;
          v_engineer_name := COALESCE(v_el->>'engineer_name', v_el->>'supplier_name');
        ELSE
          v_is_engineer := false;
        END IF;

        IF NOT v_is_engineer AND v_supp_str IS NOT NULL AND v_supp_str != '' AND v_supp_str != 'null' THEN
          BEGIN
            v_supplier_id := v_supp_str::uuid;
          EXCEPTION WHEN OTHERS THEN
            v_supplier_id := NULL;
          END;

          IF v_supplier_id IS NULL AND v_supp_str ~ '^[0-9]+$' THEN
            BEGIN
              v_trans_supplier_id := v_supp_str::integer;
            EXCEPTION WHEN OTHERS THEN
              v_trans_supplier_id := NULL;
            END;
          END IF;
        END IF;

        IF v_trans_supplier_id IS NULL AND v_el ? 'transport_supplier_id' 
           AND (v_el->>'transport_supplier_id') IS NOT NULL 
           AND (v_el->>'transport_supplier_id') <> '' 
           AND (v_el->>'transport_supplier_id') <> 'null' THEN
          BEGIN
            v_trans_supplier_id := (v_el->>'transport_supplier_id')::integer;
          EXCEPTION WHEN OTHERS THEN
            v_trans_supplier_id := NULL;
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

        v_rep_cat_id := NULL;
        IF (v_el ? 'report_category_id') AND (v_el->>'report_category_id') ~ '^[0-9]+$' THEN
          v_rep_cat_id := (v_el->>'report_category_id')::integer;
          IF v_rep_cat_id > 100 OR NOT EXISTS (SELECT 1 FROM public.cost_report_categories WHERE id = v_rep_cat_id) THEN
            IF v_is_engineer THEN
              SELECT id INTO v_rep_cat_id FROM public.cost_report_categories WHERE name ILIKE '%مهندس%' LIMIT 1;
              IF v_rep_cat_id IS NULL THEN v_rep_cat_id := 19; END IF;
            ELSE
              v_rep_cat_id := NULL;
            END IF;
          END IF;
        ELSIF v_is_engineer THEN
          SELECT id INTO v_rep_cat_id FROM public.cost_report_categories WHERE name ILIKE '%مهندس%' LIMIT 1;
          IF v_rep_cat_id IS NULL THEN v_rep_cat_id := 19; END IF;
        END IF;

        SELECT * INTO v_existing_item 
        FROM public.packing_order_cost_items 
        WHERE packing_order_id = p_packing_order_id 
          AND name = (v_el->>'name')
        LIMIT 1;

        IF v_existing_item.id IS NOT NULL THEN
          UPDATE public.packing_order_cost_items
          SET base_amount = CASE WHEN v_existing_item.cost_status = 'actual' THEN v_existing_item.base_amount ELSE v_amt_egp END,
              original_amount = CASE WHEN v_existing_item.cost_status = 'actual' THEN v_existing_item.original_amount ELSE COALESCE((v_el->>'total')::numeric, v_amt_egp) END,
              expected_amount = COALESCE(v_existing_item.expected_amount, v_amt_egp),
              truck_count = COALESCE((v_el->>'truck_count')::numeric, (v_el->>'quantity')::numeric, 1.0),
              quantity = (v_el->>'quantity')::numeric,
              unit_price = (v_el->>'unit_price')::numeric,
              custody_id = COALESCE(v_custody_id, v_existing_item.custody_id),
              engineer_name = COALESCE(v_engineer_name, v_existing_item.engineer_name),
              transport_supplier_id = COALESCE(v_trans_supplier_id, v_existing_item.transport_supplier_id),
              report_category_id = COALESCE(v_rep_cat_id, v_existing_item.report_category_id)
          WHERE id = v_existing_item.id;
        ELSE
          INSERT INTO public.packing_order_cost_items (
            packing_order_id, name, category,
            base_amount, original_amount, original_currency,
            payment_source_type, payment_source_id,
            allocation_method, target_line_id,
            currency_snapshot, supplier_id, payment_status, paid_amount,
            cost_status, expected_amount, actual_amount, variance_amount, invoice_ref,
            truck_count, quantity, unit_price, transport_supplier_id, custody_id, engineer_name, report_category_id
          ) VALUES (
            p_packing_order_id,
            v_el->>'name',
            CASE 
              WHEN v_is_engineer THEN 'engineer_expenses'
              WHEN v_trans_supplier_id IS NOT NULL OR (v_el->>'supplier_type') = 'transport' OR (v_el->>'category') = 'logistics' OR (v_el->>'name') ILIKE '%نقل%' THEN 'logistics'
              WHEN v_el->>'category' IN ('fruit', 'material', 'logistics', 'admin', 'other', 'engineer_expenses') THEN v_el->>'category' 
              WHEN (v_el->>'supplier_type') = 'admin' OR (v_el->>'name') = 'مصاريف إدارية' THEN 'admin'
              ELSE 'other' 
            END,
            v_amt_egp,
            COALESCE((v_el->>'total')::numeric, v_amt_egp),
            COALESCE(NULLIF(v_el->>'currency', ''), COALESCE(v_el->>'supplier_currency', 'EGP')),
            CASE WHEN v_is_engineer THEN 'treasury' ELSE 'none' END,
            v_custody_id,
            v_el->>'allocation_method',
            v_target_line_idx,
            v_el,
            CASE WHEN v_is_engineer THEN NULL ELSE COALESCE(v_supp_str, v_supplier_id::text) END,
            'pending',
            0,
            v_status_to_set,
            v_expected_to_set,
            v_actual_to_set,
            v_variance_to_set,
            v_el->>'invoice_ref',
            COALESCE((v_el->>'truck_count')::numeric, (v_el->>'quantity')::numeric, 1.0),
            (v_el->>'quantity')::numeric,
            (v_el->>'unit_price')::numeric,
            v_trans_supplier_id,
            v_custody_id,
            v_engineer_name,
            v_rep_cat_id
          );
        END IF;
      END IF;
    END LOOP;
  END IF;

  -- 2. Calculate Total Additional Costs
  SELECT COALESCE(SUM(base_amount), 0) INTO v_tot_cost_items
  FROM public.packing_order_cost_items
  WHERE packing_order_id = p_packing_order_id AND COALESCE(base_amount, 0) > 0;

  IF v_tot_cost_items > 0 THEN
    -- 3. Manage Journal Entry
    v_je_id := v_order.costs_journal_entry_id;
    IF v_je_id IS NOT NULL THEN
      DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id;
    ELSE
      INSERT INTO public.journal_entries (
        entry_number, entry_date, description, status, is_auto_generated,
        source_type, source_id, company_id
      ) VALUES (
        'PENDING', (COALESCE(v_order.packed_at, now()) AT TIME ZONE 'Africa/Cairo')::date,
        'إثبات بنود التكاليف الإضافية والموردين والعهد - أمر تعبئة ' || v_order_num,
        'posted', true, 'packing_order_costs', p_packing_order_id::text, v_company_id
      ) RETURNING id INTO v_je_id;

      v_entry_num := 'POX-' || LPAD(v_je_id::text, 5, '0');
      UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;
    END IF;

    -- Debit Finished Goods Inventory 12413
    INSERT INTO public.account_ledger_entries (
      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
    ) VALUES (
      v_je_id, v_finished_inv_acc, v_tot_cost_items, 0, 'EGP', v_tot_cost_items,
      'إثبات تكاليف تشغيل إضافية - أمر تعبئة ' || v_order_num, v_company_id
    );
    v_sum_debit := v_tot_cost_items;

    -- 4. Credit Lines
    FOR r_cost IN
      SELECT * FROM public.packing_order_cost_items
      WHERE packing_order_id = p_packing_order_id AND COALESCE(base_amount, 0) > 0
    LOOP
      v_credit_acc := NULL;
      v_supplier_id := NULL;
      v_trans_supplier_id := NULL;
      v_custody_id := NULL;
      v_supp_str := NULL;
      v_category_account_id := NULL;
      v_is_transport := false;
      v_is_engineer := false;

      IF r_cost.currency_snapshot IS NOT NULL THEN
        v_supp_str := r_cost.currency_snapshot->>'supplier_id';
      END IF;
      IF v_supp_str IS NULL OR v_supp_str = '' OR v_supp_str = 'null' THEN
        v_supp_str := r_cost.supplier_id;
      END IF;

      -- Check Engineer Expenses
      v_is_engineer := (
        r_cost.category = 'engineer_expenses'
        OR (r_cost.currency_snapshot IS NOT NULL AND r_cost.currency_snapshot->>'supplier_type' = 'engineer')
        OR r_cost.name ILIKE '%مهندس%'
        OR r_cost.name ILIKE '%اشراف%'
        OR r_cost.name ILIKE '%إشراف%'
        OR r_cost.custody_id IS NOT NULL
        OR (r_cost.currency_snapshot IS NOT NULL AND (r_cost.currency_snapshot ? 'custody_id'))
      );

      IF v_is_engineer THEN
        v_custody_id := r_cost.custody_id;
        IF v_custody_id IS NULL AND r_cost.currency_snapshot IS NOT NULL AND (r_cost.currency_snapshot ? 'custody_id') THEN
          v_custody_id := (r_cost.currency_snapshot->>'custody_id')::integer;
        END IF;
        IF v_custody_id IS NULL AND v_supp_str ~ '^[0-9]+$' THEN
          v_custody_id := v_supp_str::integer;
        END IF;
        IF v_custody_id IS NULL AND r_cost.engineer_name IS NOT NULL THEN
          SELECT id INTO v_custody_id FROM public.treasuries WHERE name ILIKE '%' || r_cost.engineer_name || '%' LIMIT 1;
        END IF;
        IF v_custody_id IS NULL THEN
          SELECT id INTO v_custody_id FROM public.treasuries WHERE type IN ('employee', 'custody') LIMIT 1;
        END IF;

        IF v_custody_id IS NOT NULL THEN
          SELECT account_id INTO v_credit_acc FROM public.treasuries WHERE id = v_custody_id;
        END IF;
        IF v_credit_acc IS NULL THEN v_credit_acc := v_custody_default_acc; END IF;

        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id,
          entity_type, entity_id
        ) VALUES (
          v_je_id, v_credit_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,
          'عهدة موظف - مصاريف مهندسين وإشراف تقديرية (أمر ' || v_order_num || '): ' || COALESCE(r_cost.name, 'مصاريف مهندسين'), v_company_id,
          'treasury', v_custody_id::text
        );
        v_sum_credit := v_sum_credit + r_cost.base_amount;
        v_posted_cost_items := v_posted_cost_items + r_cost.base_amount;

      ELSE
        -- Transport Check
        IF v_supp_str IS NOT NULL AND v_supp_str != '' AND v_supp_str != 'null' THEN
          BEGIN
            v_supplier_id := v_supp_str::uuid;
          EXCEPTION WHEN OTHERS THEN
            v_supplier_id := NULL;
          END;

          IF v_supplier_id IS NULL AND v_supp_str ~ '^[0-9]+$' THEN
            BEGIN
              v_trans_supplier_id := v_supp_str::integer;
            EXCEPTION WHEN OTHERS THEN
              v_trans_supplier_id := NULL;
            END;
          END IF;
        END IF;

        IF v_trans_supplier_id IS NULL AND r_cost.transport_supplier_id IS NOT NULL THEN
          v_trans_supplier_id := r_cost.transport_supplier_id;
        END IF;

        v_is_transport := (
          v_trans_supplier_id IS NOT NULL
          OR r_cost.category = 'logistics'
          OR (r_cost.currency_snapshot IS NOT NULL AND r_cost.currency_snapshot->>'supplier_type' = 'transport')
          OR r_cost.name ILIKE '%نقل%'
          OR r_cost.name ILIKE '%شحن%'
          OR r_cost.name ILIKE '%نولون%'
          OR (v_supplier_id IS NOT NULL AND EXISTS (
                SELECT 1 FROM public.suppliers 
                WHERE id = v_supplier_id AND (supplier_type = 'transport' OR code LIKE '6%')
             ))
        );

        IF v_is_transport THEN
          IF v_trans_supplier_id IS NOT NULL THEN
            SELECT account_id INTO v_credit_acc FROM public.transport_suppliers WHERE id = v_trans_supplier_id;
          END IF;
          IF v_credit_acc IS NULL AND v_supplier_id IS NOT NULL THEN
            SELECT account_id INTO v_credit_acc FROM public.suppliers WHERE id = v_supplier_id;
          END IF;
          IF v_credit_acc IS NULL THEN v_credit_acc := v_transport_default_acc; END IF;
          IF v_credit_acc IS NULL THEN v_credit_acc := public.resolve_gl_account('21111', v_company_id); END IF;

          INSERT INTO public.account_ledger_entries (
            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id,
            entity_type, entity_id
          ) VALUES (
            v_je_id, v_credit_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,
            'تحميل تكلفة نقل أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'نقل'), v_company_id,
            'transport_supplier', COALESCE(v_trans_supplier_id::text, v_supplier_id::text, '')
          );
          v_sum_credit := v_sum_credit + r_cost.base_amount;
          v_posted_cost_items := v_posted_cost_items + r_cost.base_amount;

          IF v_trans_supplier_id IS NOT NULL THEN
            v_consumed_trucks := COALESCE(NULLIF(r_cost.truck_count, 0), 1.0);
            UPDATE public.transport_suppliers
            SET truck_balance = COALESCE(truck_balance, 0) - v_consumed_trucks,
                updated_at = now()
            WHERE id = v_trans_supplier_id;

            INSERT INTO public.transport_transactions (
              supplier_id, type, amount, currency, reference_id,
              description, truck_count, notes, journal_entry_id, date, created_at
            ) VALUES (
              v_trans_supplier_id, 'packing_consumption', 0, 'EGP',
              p_packing_order_id::text,
              'استهلاك نقلات أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'نقل'),
              v_consumed_trucks,
              'استهلاك تشغيلي ' || v_consumed_trucks::text || ' نقلة من الرصيد',
              v_je_id, (COALESCE(v_order.packed_at, now()) AT TIME ZONE 'Africa/Cairo')::date, now()
            );
          END IF;

        ELSIF v_supplier_id IS NOT NULL THEN
          SELECT account_id INTO v_supp_leaf_acc FROM public.suppliers WHERE id = v_supplier_id;
          IF v_supp_leaf_acc IS NOT NULL THEN v_credit_acc := v_supp_leaf_acc; END IF;
          IF v_credit_acc IS NULL THEN v_credit_acc := public.fn_resolve_packing_cost_supplier_account(v_supplier_id, v_company_id); END IF;
          IF v_credit_acc IS NULL THEN v_credit_acc := public.resolve_gl_account('21113', v_company_id); END IF;
          IF v_credit_acc IS NULL THEN v_credit_acc := public.resolve_gl_account('2111', v_company_id); END IF;

          INSERT INTO public.account_ledger_entries (
            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id,
            entity_type, entity_id
          ) VALUES (
            v_je_id, v_credit_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,
            'مصروفات أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'تكلفة إضافية'), v_company_id,
            'supplier', v_supplier_id::text
          );
          v_sum_credit := v_sum_credit + r_cost.base_amount;
          v_posted_cost_items := v_posted_cost_items + r_cost.base_amount;

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

        ELSE
          -- Admin or general
          IF r_cost.category = 'admin' OR r_cost.name ILIKE '%إدار%' OR r_cost.name ILIKE '%ادار%' THEN
            v_credit_acc := public.resolve_gl_account('31331', v_company_id);
          ELSE
            v_credit_acc := public.resolve_gl_account('2111', v_company_id);
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
      END IF;
    END LOOP;

    -- Sub-cent penny rounding
    IF v_sum_debit != v_sum_credit AND v_tot_cost_items > 0 THEN
      UPDATE public.account_ledger_entries
      SET amount_in_base_currency = amount_in_base_currency + (v_sum_debit - v_sum_credit),
          credit = credit + (v_sum_debit - v_sum_credit)
      WHERE id = (
        SELECT id FROM public.account_ledger_entries
        WHERE journal_entry_id = v_je_id AND credit > 0
        ORDER BY id DESC LIMIT 1
      );
      v_sum_credit := v_sum_debit;
    END IF;

    -- 5. Mark Costs Stage Confirmed
    UPDATE public.packing_orders
    SET costs_journal_entry_id = v_je_id,
        costs_confirmed_at = COALESCE(costs_confirmed_at, now()),
        status = CASE 
          WHEN status IN ('draft', 'pending', 'crops_confirmed', 'packaging_confirmed') THEN 'costs_confirmed'
          ELSE status 
        END,
        updated_at = now()
    WHERE id = p_packing_order_id;
  END IF;

  RETURN json_build_object(
    'success', true,
    'message', 'تم تأكيد بنود التكاليف وإثبات قيود العهد والموردين بنجاح',
    'status', 'costs_confirmed',
    'journal_entry_id', v_je_id,
    'total_costs', v_tot_cost_items
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_confirm_packing_costs(bigint) TO authenticated, service_role, anon;


-- ============================================================================
-- 6. Canonical rpc_settle_packing_cost_variances Function
--    (Settling Engineer Expenses to Custody Ledger & Real Balance Deduction)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.rpc_settle_packing_cost_variances(
  p_packing_order_id BIGINT,
  p_settlements JSONB,
  p_general_notes TEXT DEFAULT NULL,
  p_settled_by UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  r_order RECORD;
  v_order_num TEXT;
  v_company_id UUID;
  v_finished_inv_acc INT;
  v_engineer_exp_acc INT;

  v_item_elem JSONB;
  v_cost_item_id BIGINT;
  v_actual_amt NUMERIC;
  v_inv_ref TEXT;
  v_item_notes TEXT;

  r_item RECORD;
  v_expected NUMERIC;
  v_old_actual NUMERIC;
  v_baseline NUMERIC;
  v_incremental_variance NUMERIC;
  v_total_variance NUMERIC;
  v_abs_variance NUMERIC;

  v_is_admin BOOLEAN;
  v_is_transport BOOLEAN;
  v_is_engineer BOOLEAN;
  v_supplier_id UUID;
  v_supp_str TEXT;
  v_trans_supplier_id INT;
  v_custody_id INT;
  v_supplier RECORD;
  v_target_acc INT;
  v_debit_acc INT;
  v_category_acc INT;

  v_je_id BIGINT := NULL;
  v_entry_num TEXT;
  v_total_inc_variance NUMERIC := 0;
  v_settled_count INT := 0;

  v_amount_to_deduct NUMERIC;
  v_cur_bal NUMERIC;
  v_new_bal NUMERIC;
  v_note_text TEXT;
  v_existing_tx_id BIGINT;
  v_tx_status TEXT;

  v_cartons_count NUMERIC := 0;
  v_new_other_cost_base NUMERIC := 0;
  v_new_total_cost NUMERIC := 0;
  v_new_carton_cost NUMERIC := 0;
BEGIN
  IF p_settlements IS NULL OR jsonb_typeof(p_settlements) <> 'array' OR jsonb_array_length(p_settlements) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'قائمة تسوية البنود فارغة');
  END IF;

  SELECT * INTO r_order FROM public.packing_orders WHERE id = p_packing_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  v_order_num := COALESCE(r_order.order_number, '#' || p_packing_order_id::text);
  SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
  IF v_company_id IS NULL THEN
    SELECT company_id INTO v_company_id FROM public.accounts WHERE account_code = '1030' LIMIT 1;
  END IF;

  SELECT id INTO v_finished_inv_acc FROM public.accounts WHERE account_code = '12413' LIMIT 1;
  IF v_finished_inv_acc IS NULL THEN v_finished_inv_acc := public.resolve_gl_account('12413', v_company_id); END IF;

  SELECT id INTO v_engineer_exp_acc FROM public.accounts WHERE account_code = '31251' LIMIT 1;
  IF v_engineer_exp_acc IS NULL THEN v_engineer_exp_acc := v_finished_inv_acc; END IF;

  -- Calculate total incremental variance
  FOR v_item_elem IN SELECT jsonb_array_elements(p_settlements)
  LOOP
    v_cost_item_id := (v_item_elem->>'cost_item_id')::bigint;
    v_actual_amt := (v_item_elem->>'actual_amount')::numeric;
    IF v_actual_amt IS NOT NULL AND v_actual_amt >= 0 THEN
      SELECT * INTO r_item FROM public.packing_order_cost_items WHERE id = v_cost_item_id;
      IF FOUND THEN
        v_expected := COALESCE(r_item.expected_amount, r_item.base_amount, 0);
        v_old_actual := r_item.actual_amount;
        IF r_item.cost_status = 'actual' AND v_old_actual IS NOT NULL THEN
          v_baseline := v_old_actual;
        ELSE
          v_baseline := v_expected;
        END IF;
        v_total_inc_variance := v_total_inc_variance + (v_actual_amt - v_baseline);
      END IF;
    END IF;
  END LOOP;

  -- Create Journal Entry if variance exists
  IF v_total_inc_variance <> 0 THEN
    INSERT INTO public.journal_entries (
      entry_number, entry_date, description, status, is_auto_generated,
      source_type, source_id, company_id, created_by
    ) VALUES (
      'PENDING', (COALESCE(r_order.packed_at, now()) AT TIME ZONE 'Africa/Cairo')::date,
      'قيد تسوية فروق التكاليف الفعلية والعهد - أمر تعبئة ' || v_order_num || COALESCE(' - ' || p_general_notes, ''),
      'posted', true, 'packing_cost_settlement', p_packing_order_id::text, v_company_id,
      COALESCE(p_settled_by, auth.uid())
    ) RETURNING id INTO v_je_id;

    v_entry_num := 'SETTL-' || LPAD(v_je_id::text, 5, '0');
    UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;
  END IF;

  -- Process settlements
  FOR v_item_elem IN SELECT jsonb_array_elements(p_settlements)
  LOOP
    v_cost_item_id := (v_item_elem->>'cost_item_id')::bigint;
    v_actual_amt := (v_item_elem->>'actual_amount')::numeric;
    v_inv_ref := v_item_elem->>'invoice_ref';
    v_item_notes := v_item_elem->>'notes';

    IF v_actual_amt IS NULL OR v_actual_amt < 0 THEN CONTINUE; END IF;

    SELECT * INTO r_item FROM public.packing_order_cost_items WHERE id = v_cost_item_id FOR UPDATE;
    IF NOT FOUND THEN CONTINUE; END IF;

    v_expected := COALESCE(r_item.expected_amount, r_item.base_amount, 0);
    v_old_actual := r_item.actual_amount;
    IF r_item.cost_status = 'actual' AND v_old_actual IS NOT NULL THEN
      v_baseline := v_old_actual;
    ELSE
      v_baseline := v_expected;
    END IF;

    v_incremental_variance := ROUND(v_actual_amt - v_baseline, 2);
    v_total_variance := ROUND(v_actual_amt - v_expected, 2);
    v_abs_variance := ABS(v_incremental_variance);

    -- Category Detection
    v_is_engineer := (
      LOWER(COALESCE(r_item.category, '')) = 'engineer_expenses'
      OR (r_item.currency_snapshot IS NOT NULL AND r_item.currency_snapshot->>'supplier_type' = 'engineer')
      OR r_item.name ILIKE '%مهندس%'
      OR r_item.name ILIKE '%اشراف%'
      OR r_item.name ILIKE '%إشراف%'
      OR r_item.custody_id IS NOT NULL
      OR (v_item_elem ? 'custody_id')
    );
    v_is_admin := NOT v_is_engineer AND (LOWER(COALESCE(r_item.category, '')) = 'admin' OR r_item.name ILIKE '%إدار%' OR r_item.name ILIKE '%ادار%');
    v_is_transport := NOT v_is_engineer AND NOT v_is_admin AND (LOWER(COALESCE(r_item.category, '')) = 'logistics' OR r_item.name ILIKE '%نقل%' OR r_item.name ILIKE '%سيار%' OR r_item.name ILIKE '%شحن%');

    v_custody_id := NULL;
    v_supplier_id := NULL;
    v_target_acc := NULL;
    v_debit_acc := v_finished_inv_acc;

    IF v_is_engineer THEN
      v_custody_id := (v_item_elem->>'custody_id')::integer;
      IF v_custody_id IS NULL THEN v_custody_id := r_item.custody_id; END IF;
      IF v_custody_id IS NULL AND r_item.currency_snapshot IS NOT NULL AND (r_item.currency_snapshot ? 'custody_id') THEN
        v_custody_id := (r_item.currency_snapshot->>'custody_id')::integer;
      END IF;
      IF v_custody_id IS NULL AND r_item.engineer_name IS NOT NULL THEN
        SELECT id INTO v_custody_id FROM public.treasuries WHERE name ILIKE '%' || r_item.engineer_name || '%' LIMIT 1;
      END IF;
      IF v_custody_id IS NULL THEN
        SELECT id INTO v_custody_id FROM public.treasuries WHERE type IN ('employee', 'custody') LIMIT 1;
      END IF;

      IF v_custody_id IS NOT NULL THEN
        SELECT account_id INTO v_target_acc FROM public.treasuries WHERE id = v_custody_id;
      END IF;
      IF v_target_acc IS NULL THEN
        SELECT id INTO v_target_acc FROM public.accounts WHERE account_code = '1261201' LIMIT 1;
      END IF;
      IF v_target_acc IS NULL THEN
        SELECT id INTO v_target_acc FROM public.accounts WHERE account_code = '12612' LIMIT 1;
      END IF;

      -- Debit Expense Account: 31251 or specified on item
      IF v_item_elem ? 'expense_account_id' AND (v_item_elem->>'expense_account_id') IS NOT NULL THEN
        v_debit_acc := (v_item_elem->>'expense_account_id')::integer;
      ELSIF r_item.expense_account_id IS NOT NULL THEN
        v_debit_acc := r_item.expense_account_id::integer;
      ELSE
        v_debit_acc := v_engineer_exp_acc;
      END IF;

      -- Direct Impact on Custody Balance & Movement (Requirement #2)
      IF v_custody_id IS NOT NULL THEN
        -- Check if an existing draft or confirmed transaction exists
        v_existing_tx_id := r_item.treasury_transaction_id;
        v_tx_status := NULL;
        IF v_existing_tx_id IS NOT NULL THEN
          SELECT status INTO v_tx_status FROM public.treasury_transactions WHERE id = v_existing_tx_id;
        END IF;

        IF v_existing_tx_id IS NULL THEN
          SELECT id, status INTO v_existing_tx_id, v_tx_status
          FROM public.treasury_transactions
          WHERE reference_id = p_packing_order_id::text
            AND treasury_id = v_custody_id
            AND cost_center_id = 'CC-ENG-EXP'
            AND status = 'draft'
          LIMIT 1;
        END IF;

        IF v_existing_tx_id IS NOT NULL AND v_tx_status = 'draft' THEN
          -- Previously a draft: nothing was deducted, so deduct full actual amount
          v_amount_to_deduct := v_actual_amt;
        ELSIF r_item.is_engineer_cost_settled AND v_old_actual IS NOT NULL THEN
          v_amount_to_deduct := v_incremental_variance;
        ELSE
          v_amount_to_deduct := v_actual_amt;
        END IF;

        SELECT balance INTO v_cur_bal FROM public.treasury_balances WHERE treasury_id = v_custody_id AND currency = 'EGP' FOR UPDATE;
        v_cur_bal := COALESCE(v_cur_bal, 0);

        IF v_amount_to_deduct <> 0 THEN
          v_new_bal := v_cur_bal - v_amount_to_deduct;
          IF v_new_bal < 0 THEN v_new_bal := 0; END IF;

          INSERT INTO public.treasury_balances (treasury_id, currency, balance, account_id, updated_at)
          VALUES (v_custody_id, 'EGP', v_new_bal, v_target_acc, now())
          ON CONFLICT (treasury_id, currency) DO UPDATE
          SET balance = v_new_bal, updated_at = now();
        ELSE
          v_new_bal := v_cur_bal;
        END IF;

        v_note_text := CASE 
          WHEN v_amount_to_deduct >= 0 THEN 
            'تسوية عهدة مهندس - مصاريف مهندسين وإشراف فعلية - بند: ' || r_item.name || ' (أمر ' || v_order_num || ') - مستند: ' || COALESCE(v_inv_ref, '-')
          ELSE 
            'تسوية عهدة مهندس (استرداد وفر عهدة) - بند: ' || r_item.name || ' (أمر ' || v_order_num || ') - مستند: ' || COALESCE(v_inv_ref, '-')
        END;

        IF v_existing_tx_id IS NOT NULL THEN
          UPDATE public.treasury_transactions
          SET amount = v_actual_amt,
              type = 'expense',
              status = 'confirmed',
              balance_before = CASE WHEN v_tx_status = 'draft' THEN v_cur_bal ELSE (v_cur_bal + v_amount_to_deduct) END,
              balance_after = v_new_bal,
              description = v_note_text,
              notes = v_note_text,
              cost_center_id = 'CC-ENG-EXP'
          WHERE id = v_existing_tx_id;
        ELSE
          INSERT INTO public.treasury_transactions (
            treasury_id, amount, type, currency, balance_before, balance_after,
            description, reference_id, notes, cost_center_id, created_at, status
          ) VALUES (
            v_custody_id, v_actual_amt,
            'expense', 'EGP', v_cur_bal, v_new_bal,
            v_note_text, p_packing_order_id::text, v_note_text, 'CC-ENG-EXP', now(), 'confirmed'
          ) RETURNING id INTO v_existing_tx_id;
        END IF;
      END IF;

    ELSIF v_is_transport THEN
      v_target_acc := public.resolve_gl_account('21111', v_company_id);
      IF v_target_acc IS NULL THEN v_target_acc := public.resolve_gl_account('2111', v_company_id); END IF;
    ELSIF v_is_admin THEN
      v_target_acc := public.resolve_gl_account('31331', v_company_id);
    ELSE
      -- Standard supplier
      v_supp_str := COALESCE(r_item.supplier_id, (r_item.currency_snapshot->>'supplier_id'));
      IF v_supp_str IS NOT NULL AND v_supp_str <> '' AND v_supp_str <> 'null' THEN
        BEGIN v_supplier_id := v_supp_str::uuid; EXCEPTION WHEN OTHERS THEN v_supplier_id := NULL; END;
      END IF;
      IF v_supplier_id IS NOT NULL THEN
        SELECT * INTO v_supplier FROM public.suppliers WHERE id = v_supplier_id;
        IF v_supplier.account_id IS NOT NULL THEN
          v_target_acc := v_supplier.account_id;
        ELSE
          v_target_acc := public.fn_resolve_packing_cost_supplier_account(v_supplier_id, v_company_id);
        END IF;
      END IF;
      IF v_target_acc IS NULL THEN v_target_acc := public.resolve_gl_account('2111', v_company_id); END IF;

      -- Update supplier balance & ledger entry
      IF v_incremental_variance <> 0 AND v_supplier_id IS NOT NULL THEN
        UPDATE public.suppliers 
        SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_incremental_variance
        WHERE id = v_supplier_id;

        INSERT INTO public.ledger_entries (
          entity_id, entity_type, amount, currency, entry_type,
          reference_id, reference_type, reference_text, description, created_at
        ) VALUES (
          v_supplier_id::text, 'supplier', v_abs_variance, 'EGP',
          CASE WHEN v_incremental_variance > 0 THEN 'credit' ELSE 'debit' END,
          p_packing_order_id, 'cost_settlement', COALESCE(v_inv_ref, r_item.name),
          CASE WHEN v_incremental_variance > 0 
            THEN 'تسوية تكلفة فعلية (زيادة) بند: ' || r_item.name || ' (أمر ' || v_order_num || ') - مستند: ' || COALESCE(v_inv_ref, '-')
            ELSE 'تسوية تكلفة فعلية (وفر) بند: ' || r_item.name || ' (أمر ' || v_order_num || ') - مستند: ' || COALESCE(v_inv_ref, '-')
          END, now()
        );
      END IF;
    END IF;

    -- Post GL entries if variance exists
    IF v_incremental_variance <> 0 AND v_je_id IS NOT NULL THEN
      IF v_incremental_variance > 0 THEN
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_je_id, v_debit_acc, v_abs_variance, 0, 'EGP', v_abs_variance,
          'فروق تكلفة فعلية إضافية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id
        );
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_je_id, v_target_acc, 0, v_abs_variance, 'EGP', v_abs_variance,
          'مستحقات تسوية تكلفة فعلية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id
        );
      ELSE
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_je_id, v_target_acc, v_abs_variance, 0, 'EGP', v_abs_variance,
          'تخفيض مستحقات تسوية تكلفة فعلية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id
        );
        INSERT INTO public.account_ledger_entries (
          journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
          v_je_id, v_debit_acc, 0, v_abs_variance, 'EGP', v_abs_variance,
          'وفر تكلفة فعلية - ' || r_item.name || ' (أمر ' || v_order_num || ')', v_company_id
        );
      END IF;
    END IF;

    -- Update row in packing_order_cost_items
    UPDATE public.packing_order_cost_items
    SET cost_status = 'actual',
        actual_amount = v_actual_amt,
        base_amount = v_actual_amt,
        original_amount = v_actual_amt,
        expected_amount = v_expected,
        variance_amount = v_total_variance,
        invoice_ref = COALESCE(NULLIF(v_inv_ref, ''), invoice_ref),
        settlement_notes = COALESCE(NULLIF(v_item_notes, ''), settlement_notes),
        reconciled_at = now(),
        reconciled_by = COALESCE(p_settled_by, auth.uid()),
        variance_journal_entry_id = COALESCE(v_je_id, variance_journal_entry_id),
        custody_id = COALESCE(v_custody_id, custody_id),
        treasury_transaction_id = COALESCE(v_existing_tx_id, treasury_transaction_id),
        is_engineer_cost_settled = CASE WHEN v_is_engineer THEN true ELSE is_engineer_cost_settled END
    WHERE id = v_cost_item_id;

    v_settled_count := v_settled_count + 1;
  END LOOP;

  -- Update packing orders total cost and carton cost
  SELECT COALESCE(SUM(base_amount), 0) INTO v_new_other_cost_base
  FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id;

  v_new_total_cost := COALESCE(r_order.fruit_cost_base, 0) + COALESCE(r_order.actual_material_cost, 0) + v_new_other_cost_base;

  SELECT COALESCE(SUM(carton_count), 0) INTO v_cartons_count
  FROM public.packing_order_lines WHERE packing_order_id = p_packing_order_id;
  IF v_cartons_count <= 0 THEN
    v_cartons_count := COALESCE(r_order.final_carton_count, r_order.planned_carton_count, r_order.carton_count, 1);
  END IF;

  v_new_carton_cost := CASE WHEN v_cartons_count > 0 THEN ROUND(v_new_total_cost / v_cartons_count, 4) ELSE 0 END;

  UPDATE public.packing_orders
  SET other_cost_base = v_new_other_cost_base,
      total_cost = v_new_total_cost,
      packing_cost_per_carton = v_new_carton_cost,
      is_engineer_cost_settled = true,
      updated_at = now()
  WHERE id = p_packing_order_id;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'تمت تسوية بنود التكاليف وفروق العهد والموردين بنجاح',
    'settled_count', v_settled_count,
    'journal_entry_id', v_je_id,
    'total_variance', v_total_inc_variance,
    'new_carton_cost', v_new_carton_cost,
    'new_total_cost', v_new_total_cost
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_settle_packing_cost_variances(BIGINT, JSONB, TEXT, UUID) TO authenticated, service_role, anon;

