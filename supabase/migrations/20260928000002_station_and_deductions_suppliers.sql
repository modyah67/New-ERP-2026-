-- Migration: 20260928000002_station_and_deductions_suppliers.sql
-- Description:
-- 1. Create Control Accounts 21117 (Station Suppliers) and 21118 (Deductions Suppliers) in public.accounts.
-- 2. Update suppliers constraint suppliers_supplier_type_check to support 'station' and 'deduction'.
-- 3. Update trg_fn_validate_supplier_category_code_range for 80000-89999 (station) and 40000-49999 (deduction).
-- 4. Update create_supplier_account() trigger to map station to 21117 and deduction to 21118.
-- 5. Add supplier_type column to public.cost_report_categories.
-- 6. Seed and link the 9 Station Categories and 9 Deductions Categories.
-- 7. Update list_cost_report_categories, create_cost_report_category, and update_cost_report_category RPCs.
-- 8. Enhance rpc_confirm_packing_order to route liabilities to 21117 and 21118.

BEGIN;

-- ============================================================================
-- 1. Control Accounts: 21117 (موردي المحطات) & 21118 (موردي التخصيمات)
-- ============================================================================

DO $$
DECLARE
    v_parent_id BIGINT;
    v_company_id UUID;
BEGIN
    SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;
    SELECT id INTO v_parent_id FROM public.accounts WHERE account_code = '2111' LIMIT 1;

    -- 21117: Station Suppliers (موردي المحطات)
    INSERT INTO public.accounts (
        account_code, name, account_name, account_type,
        normal_balance, is_leaf, is_active, level, parent_id, company_id
    ) VALUES (
        '21117', 'Station Suppliers Sub-ledger', 'موردي المحطات', 'liability',
        'Credit', TRUE, TRUE, 5, v_parent_id, v_company_id
    )
    ON CONFLICT (account_code) DO UPDATE
    SET is_active = TRUE,
        name = EXCLUDED.name,
        account_name = EXCLUDED.account_name;

    -- 21118: Deductions Suppliers (موردي التخصيمات)
    INSERT INTO public.accounts (
        account_code, name, account_name, account_type,
        normal_balance, is_leaf, is_active, level, parent_id, company_id
    ) VALUES (
        '21118', 'Deductions Suppliers Sub-ledger', 'موردي التخصيمات', 'liability',
        'Credit', TRUE, TRUE, 5, v_parent_id, v_company_id
    )
    ON CONFLICT (account_code) DO UPDATE
    SET is_active = TRUE,
        name = EXCLUDED.name,
        account_name = EXCLUDED.account_name;
END $$;

-- ============================================================================
-- 2. Update suppliers constraint & code range validation trigger
-- ============================================================================

ALTER TABLE public.suppliers
DROP CONSTRAINT IF EXISTS suppliers_supplier_type_check;

ALTER TABLE public.suppliers
ADD CONSTRAINT suppliers_supplier_type_check 
CHECK (supplier_type IN ('crop', 'packaging', 'shared', 'station', 'deduction', 'deductions', 'transport'));

ALTER TABLE public.suppliers
ADD COLUMN IF NOT EXISTS categories text[] DEFAULT '{}';

CREATE OR REPLACE FUNCTION public.trg_fn_validate_supplier_category_code_range()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_code_num INTEGER;
BEGIN
  IF NEW.code ~ '^[0-9]+$' THEN
    v_code_num := NEW.code::INTEGER;
    -- Preserve existing legacy codes (< 1000) safely
    IF v_code_num < 1000 THEN
      RETURN NEW;
    END IF;
  ELSE
    RETURN NEW;
  END IF;

  CASE NEW.supplier_type
    WHEN 'crop' THEN
      IF v_code_num < 50000 OR v_code_num > 59999 THEN
        RAISE EXCEPTION 'كود مورد المحاصيل غير صالح: (%) يجب أن يكون بين 50000 و 59999 (سعة: 10000 سجل)', NEW.code;
      END IF;

    WHEN 'transport' THEN
      IF v_code_num < 60000 OR v_code_num > 69999 THEN
        RAISE EXCEPTION 'كود مورد النقل غير صالح: (%) يجب أن يكون بين 60000 و 69999 (سعة: 10000 سجل)', NEW.code;
      END IF;

    WHEN 'packaging' THEN
      IF v_code_num < 70000 OR v_code_num > 74999 THEN
        RAISE EXCEPTION 'كود مورد مواد التعبئة والتغليف غير صالح: (%) يجب أن يكون بين 70000 و 74999 (سعة: 5000 سجل)', NEW.code;
      END IF;

    WHEN 'shared' THEN
      IF v_code_num < 75000 OR v_code_num > 79999 THEN
        RAISE EXCEPTION 'كود المورد المشترك غير صالح: (%) يجب أن يكون في النطاق 75000 إلى 79999 لمنع التداخل (سعة: 5000 سجل)', NEW.code;
      END IF;

    WHEN 'station' THEN
      IF v_code_num < 80000 OR v_code_num > 89999 THEN
        RAISE EXCEPTION 'كود مورد المحطة غير صالح: (%) يجب أن يكون في النطاق 80000 إلى 89999 (سعة: 10000 سجل)', NEW.code;
      END IF;

    WHEN 'deduction', 'deductions' THEN
      IF v_code_num < 40000 OR v_code_num > 49999 THEN
        RAISE EXCEPTION 'كود مورد التخصيمات غير صالح: (%) يجب أن يكون في النطاق 40000 إلى 49999 (سعة: 10000 سجل)', NEW.code;
      END IF;

    ELSE
      -- Default allow
  END CASE;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_supplier_code_range ON public.suppliers;
CREATE TRIGGER trg_validate_supplier_code_range
BEFORE INSERT OR UPDATE OF code, supplier_type ON public.suppliers
FOR EACH ROW
EXECUTE FUNCTION public.trg_fn_validate_supplier_category_code_range();

-- ============================================================================
-- 3. Automatic Master Account Mapping Trigger for Suppliers
-- ============================================================================

CREATE OR REPLACE FUNCTION public.create_supplier_account()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_raw_type TEXT;
  v_target_account_code TEXT;
  v_target_account_id BIGINT;
BEGIN
  IF NEW.account_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  v_raw_type := LOWER(TRIM(COALESCE(NEW.supplier_type, 'crop')));

  -- تحديد كود الحساب الرئيسي المستوى الخامس بناءً على فئة المورد:
  -- موردي النقل والسيارات -> 21111
  -- موردي مواد التعبئة -> 21112
  -- موردي مشتريات محاصيل -> 21113
  -- موردين مشتركين -> 21114
  -- شركات الشحن -> 21115
  -- مخلصي الجمارك -> 21116
  -- موردي المحطات -> 21117
  -- موردي التخصيمات -> 21118
  IF v_raw_type IN ('transport', 'transporter', 'مورد نقل', 'نقل', 'سيارات') 
     OR (NEW.code)::text LIKE '6%' THEN
    v_target_account_code := '21111';
  ELSIF v_raw_type IN ('station', 'stations', 'مورد محطة', 'موردي المحطات', 'محطة', 'محطات')
     OR (NEW.code)::text LIKE '8%' THEN
    v_target_account_code := '21117';
  ELSIF v_raw_type IN ('deduction', 'deductions', 'مورد تخصيم', 'موردي التخصيمات', 'تخصيم', 'تخصيمات')
     OR (NEW.code)::text LIKE '4%' THEN
    v_target_account_code := '21118';
  ELSIF v_raw_type IN ('packaging', 'packing', 'sticker', 'تعبئة', 'مواد تعبئة', 'استيكر')
     OR (NEW.code)::text LIKE '70%' OR (NEW.code)::text LIKE '71%' OR (NEW.code)::text LIKE '72%' OR (NEW.code)::text LIKE '73%' OR (NEW.code)::text LIKE '74%' THEN
    v_target_account_code := '21112';
  ELSIF v_raw_type IN ('shared', 'مشترك', 'مشتركين')
     OR (NEW.code)::text LIKE '75%' OR (NEW.code)::text LIKE '76%' OR (NEW.code)::text LIKE '77%' OR (NEW.code)::text LIKE '78%' OR (NEW.code)::text LIKE '79%' THEN
    v_target_account_code := '21114';
  ELSIF v_raw_type IN ('shipping', 'shipping_company', 'شحن', 'شركات الشحن')
     OR (NEW.code)::text LIKE '9%' THEN
    v_target_account_code := '21115';
  ELSIF v_raw_type IN ('clearing', 'clearance', 'customs', 'جمارك', 'تخليص') THEN
    v_target_account_code := '21116';
  ELSE
    -- الافتراضي: موردي مشتريات محاصيل
    v_target_account_code := '21113';
  END IF;

  SELECT id INTO v_target_account_id
  FROM public.accounts
  WHERE account_code = v_target_account_code
    AND (company_id = NEW.company_id OR company_id = 'a0000000-0000-0000-0000-000000000001'::uuid OR company_id IS NULL)
  ORDER BY (company_id = NEW.company_id) DESC NULLS LAST
  LIMIT 1;

  IF v_target_account_id IS NULL THEN
    SELECT id INTO v_target_account_id
    FROM public.accounts
    WHERE account_code = v_target_account_code
    LIMIT 1;
  END IF;

  IF v_target_account_id IS NULL THEN
    SELECT id INTO v_target_account_id
    FROM public.accounts
    WHERE account_code = '2111'
    LIMIT 1;
  END IF;

  IF v_target_account_id IS NOT NULL THEN
    NEW.account_id := v_target_account_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_create_supplier_account ON public.suppliers;
CREATE TRIGGER trg_create_supplier_account
BEFORE INSERT OR UPDATE OF supplier_type, code ON public.suppliers
FOR EACH ROW
EXECUTE FUNCTION public.create_supplier_account();

-- ============================================================================
-- 4. Cost Classifications Enhancements (public.cost_report_categories)
-- ============================================================================

ALTER TABLE public.cost_report_categories
ADD COLUMN IF NOT EXISTS supplier_type VARCHAR(50) DEFAULT 'general';

-- Note: Pre-configured Station and Deduction categories can be seeded on-demand from the UI.
-- Automatic insertion is commented out to allow clients to register custom categories cleanly.
/*
-- Seed / Update Station Categories (9 categories)
INSERT INTO public.cost_report_categories (name, type, scope, supplier_type, is_system)
VALUES
  ('تشغيل', 'direct', 'packing', 'station', TRUE),
  ('تبريد', 'direct', 'packing', 'station', TRUE),
  ('حفظ مبرد', 'direct', 'packing', 'station', TRUE),
  ('تقفيل كرتون', 'direct', 'packing', 'station', TRUE),
  ('تعتيق صادر', 'direct', 'packing', 'station', TRUE),
  ('اعادة تدوير', 'direct', 'packing', 'station', TRUE),
  ('عماله', 'direct', 'packing', 'station', TRUE),
  ('تبخير', 'direct', 'packing', 'station', TRUE),
  ('تدوير خام', 'direct', 'packing', 'station', TRUE)
ON CONFLICT (name) DO UPDATE
SET supplier_type = 'station',
    scope = CASE WHEN cost_report_categories.scope = 'all' THEN 'all' ELSE 'packing' END;

-- Seed / Update Deductions Categories (9 categories)
INSERT INTO public.cost_report_categories (name, type, scope, supplier_type, is_system)
VALUES
  ('رسوم فحص', 'direct', 'all', 'deduction', TRUE),
  ('تخصيم عربي', 'direct', 'all', 'deduction', TRUE),
  ('تخصيم اوروبي', 'direct', 'all', 'deduction', TRUE),
  ('تحليل خاص', 'direct', 'all', 'deduction', TRUE),
  ('تحليل هيئه', 'direct', 'all', 'deduction', TRUE),
  ('سحب عينه عربي', 'direct', 'all', 'deduction', TRUE),
  ('تعديل وجات', 'direct', 'all', 'deduction', TRUE),
  ('دفتر حجر زراعي', 'direct', 'all', 'deduction', TRUE),
  ('دفتر حجر سلامه غذاء', 'direct', 'all', 'deduction', TRUE)
ON CONFLICT (name) DO UPDATE
SET supplier_type = 'deduction';
*/

-- ============================================================================
-- 5. Updated RPCs: list_cost_report_categories, create_cost_report_category, update_cost_report_category
-- ============================================================================

DROP FUNCTION IF EXISTS public.list_cost_report_categories(TEXT) CASCADE;
DROP FUNCTION IF EXISTS public.list_cost_report_categories() CASCADE;

CREATE OR REPLACE FUNCTION public.list_cost_report_categories(
    p_scope TEXT DEFAULT NULL
)
RETURNS TABLE (
    id INTEGER,
    name TEXT,
    scope TEXT,
    is_system BOOLEAN,
    type TEXT,
    account_id BIGINT,
    account_code TEXT,
    account_name TEXT,
    cost_center_id TEXT,
    cost_center_name TEXT,
    supplier_type TEXT,
    created_at TIMESTAMPTZ
)
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
    SELECT 
        c.id,
        c.name,
        c.scope,
        c.is_system,
        c.type,
        c.account_id,
        a.account_code,
        COALESCE(a.account_name, a.name) AS account_name,
        c.cost_center_id,
        COALESCE(cc.name_ar, cc.name, c.cost_center_id) AS cost_center_name,
        COALESCE(c.supplier_type, 'general') AS supplier_type,
        c.created_at
    FROM public.cost_report_categories c
    LEFT JOIN public.accounts a ON a.id = c.account_id
    LEFT JOIN public.cost_centers cc ON cc.code = c.cost_center_id
    WHERE (p_scope IS NULL OR p_scope = 'all' OR c.scope = p_scope OR c.scope = 'both' OR c.scope = 'all')
    ORDER BY c.id;
$$;

GRANT EXECUTE ON FUNCTION public.list_cost_report_categories(TEXT) TO authenticated, service_role, anon;

-- 4. Helper: Resolve Parent Account under Root 3 (Expenses / Costs)
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
    v_clean_scope TEXT := LOWER(TRIM(COALESCE(p_scope, 'all')));
    v_clean_type TEXT := LOWER(TRIM(COALESCE(p_supplier_type, '')));
BEGIN
    -- 1. Station Suppliers / Operation Costs -> Level 4 Control: 3124 (تكاليف ومصروفات تشغيل المحطات)
    IF v_clean_type = 'station' OR v_clean_name ~* '(محطة|تبريد|تشغيل|حفظ مبرد|تقفيل كرتون|تعتيق|تدوير|تبخير|station)' THEN
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

    -- 6. General & Administrative -> 3131 / 3132
    IF v_clean_scope IN ('general_admin', 'admin') THEN
        IF v_clean_name ~* '(استشار|اشتراك|رسوم|أتعاب|مراجعة|legal|consulting)' THEN
            RETURN '3132';
        END IF;
        RETURN '3131';
    END IF;

    -- 7. Fallback based on scope
    IF v_clean_scope = 'packing' THEN
        RETURN '3124';
    ELSIF v_clean_scope = 'shipment' THEN
        RETURN '3411';
    ELSE
        RETURN '3131';
    END IF;
END;
$$;

-- Backward compatible 2-arg signature
CREATE OR REPLACE FUNCTION public.fn_resolve_category_parent_account(
    p_scope TEXT,
    p_name TEXT
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT public.fn_resolve_category_parent_account(p_scope, p_name, NULL);
$$;

GRANT EXECUTE ON FUNCTION public.fn_resolve_category_parent_account(TEXT, TEXT, TEXT) TO authenticated, service_role, anon;
GRANT EXECUTE ON FUNCTION public.fn_resolve_category_parent_account(TEXT, TEXT) TO authenticated, service_role, anon;

-- Drop previous signatures of create_cost_report_category
DROP FUNCTION IF EXISTS public.create_cost_report_category(TEXT, TEXT, TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS public.create_cost_report_category(TEXT, TEXT, TEXT) CASCADE;

CREATE OR REPLACE FUNCTION public.create_cost_report_category(
    p_name        TEXT,
    p_scope       TEXT,
    p_parent_code TEXT DEFAULT NULL,
    p_supplier_type TEXT DEFAULT 'general'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_parent_code   TEXT;
    v_next_code     TEXT;
    v_account_id    BIGINT;
    v_cost_center_id TEXT;
    v_cat_id        INTEGER;
    v_company_id    UUID;
    v_parent_id     BIGINT;
    v_row           RECORD;
BEGIN
    SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;

    -- 1. Resolve parent account code under Root 3
    IF p_parent_code IS NOT NULL AND p_parent_code != '' AND p_parent_code != '312' THEN
        v_parent_code := p_parent_code;
    ELSE
        v_parent_code := public.fn_resolve_category_parent_account(p_scope, p_name, p_supplier_type);
    END IF;

    -- 2. Verify or create parent control account (Level 4: 3124 or 3126)
    SELECT id INTO v_parent_id
    FROM public.accounts
    WHERE account_code = v_parent_code
      AND (company_id = v_company_id OR company_id IS NULL)
      AND deleted_at IS NULL
    LIMIT 1;

    IF v_parent_id IS NULL AND v_parent_code IN ('3124', '3126') THEN
        INSERT INTO public.accounts (
            account_code, name, account_name, account_type,
            normal_balance, is_leaf, allow_posting, is_active, level,
            parent_id, company_id
        ) VALUES (
            v_parent_code,
            CASE WHEN v_parent_code = '3124' THEN 'Station Packing & Operations Control' ELSE 'Inspection & Deduction Fees Control' END,
            CASE WHEN v_parent_code = '3124' THEN 'تكاليف ومصروفات تشغيل المحطات' ELSE 'رسوم فحص وتخصيمات التشغيل' END,
            'expense', 'Debit', FALSE, FALSE, TRUE, 4,
            (SELECT id FROM public.accounts WHERE account_code = '312' LIMIT 1),
            v_company_id
        ) RETURNING id INTO v_parent_id;
    END IF;

    -- 3. Get next 5-digit sub-account code
    v_next_code := public.get_next_sub_account_code(v_parent_code, v_company_id);

    -- 4. Find or create sub-account at Level 5
    IF v_next_code IS NOT NULL THEN
        SELECT id INTO v_account_id
        FROM public.accounts
        WHERE account_code = v_next_code
          AND (company_id = v_company_id OR company_id IS NULL)
        LIMIT 1;

        IF v_account_id IS NULL THEN
            INSERT INTO public.accounts (
                account_code, name, account_name, account_type,
                normal_balance, is_leaf, allow_posting, is_active, level,
                parent_id, company_id
            ) VALUES (
                v_next_code, TRIM(p_name), TRIM(p_name), 'expense',
                'Debit', TRUE, TRUE, TRUE, 5,
                v_parent_id,
                v_company_id
            )
            ON CONFLICT (account_code) DO UPDATE
            SET is_active = TRUE,
                allow_posting = TRUE
            RETURNING id INTO v_account_id;
        END IF;
    END IF;

    -- 5. Insert or update category
    INSERT INTO public.cost_report_categories (name, scope, is_system, type, account_id, supplier_type)
    VALUES (TRIM(p_name), p_scope, FALSE, 'direct', v_account_id, COALESCE(p_supplier_type, 'general'))
    ON CONFLICT (name) DO UPDATE 
    SET scope = CASE 
            WHEN cost_report_categories.scope != EXCLUDED.scope THEN 'both' 
            ELSE cost_report_categories.scope 
        END,
        account_id = COALESCE(cost_report_categories.account_id, EXCLUDED.account_id),
        supplier_type = COALESCE(EXCLUDED.supplier_type, cost_report_categories.supplier_type)
    RETURNING id INTO v_cat_id;

    -- 6. Generate Cost Center Token & Record
    IF p_scope IN ('general_admin', 'admin') THEN
        v_cost_center_id := 'CC-ADMIN-' || v_cat_id::TEXT;
    ELSE
        v_cost_center_id := 'CC-CAT-' || v_cat_id::TEXT;
    END IF;

    INSERT INTO public.cost_centers (code, name, name_ar, name_en, cost_center_type, is_active, color, icon, description)
    VALUES (
        v_cost_center_id,
        TRIM(p_name),
        TRIM(p_name),
        TRIM(p_name),
        'operational',
        TRUE,
        CASE WHEN p_scope IN ('general_admin', 'admin') THEN '#06B6D4' ELSE '#10B981' END,
        CASE WHEN p_scope IN ('general_admin', 'admin') THEN 'business_center_rounded' ELSE 'inventory_2_rounded' END,
        'مركز تكلفة مولد لتصنيف بنود التكلفة: ' || TRIM(p_name)
    )
    ON CONFLICT (code) DO NOTHING;

    -- 7. Link cost center to category & account
    UPDATE public.cost_report_categories
    SET cost_center_id = v_cost_center_id
    WHERE id = v_cat_id;

    IF v_account_id IS NOT NULL THEN
        UPDATE public.accounts
        SET cost_center_id = v_cost_center_id
        WHERE id = v_account_id;
    END IF;

    -- 8. Fetch the full updated record
    SELECT 
        c.id,
        c.name,
        c.scope,
        c.is_system,
        c.type,
        c.account_id,
        a.account_code,
        COALESCE(a.account_name, a.name) AS account_name,
        c.cost_center_id,
        COALESCE(cc.name_ar, cc.name, c.cost_center_id) AS cost_center_name,
        c.supplier_type
    INTO v_row
    FROM public.cost_report_categories c
    LEFT JOIN public.accounts a ON a.id = c.account_id
    LEFT JOIN public.cost_centers cc ON cc.code = c.cost_center_id
    WHERE c.id = v_cat_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'id', v_row.id,
        'name', v_row.name,
        'scope', v_row.scope,
        'is_system', v_row.is_system,
        'account_id', v_row.account_id,
        'account_code', v_row.account_code,
        'account_name', v_row.account_name,
        'cost_center_id', v_row.cost_center_id,
        'cost_center_name', v_row.cost_center_name,
        'supplier_type', v_row.supplier_type
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_cost_report_category(TEXT, TEXT, TEXT, TEXT) TO authenticated, service_role, anon;

DROP FUNCTION IF EXISTS public.update_cost_report_category(INTEGER, TEXT, TEXT, BIGINT, TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS public.update_cost_report_category(INTEGER, TEXT, TEXT, BIGINT, TEXT) CASCADE;

CREATE OR REPLACE FUNCTION public.update_cost_report_category(
    p_id            INTEGER,
    p_name          TEXT DEFAULT NULL,
    p_scope         TEXT DEFAULT NULL,
    p_account_id    BIGINT DEFAULT NULL,
    p_cost_center_id TEXT DEFAULT NULL,
    p_supplier_type TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    UPDATE public.cost_report_categories
    SET name  = COALESCE(NULLIF(TRIM(p_name), ''), name),
        scope = COALESCE(NULLIF(TRIM(p_scope), ''), scope),
        account_id = COALESCE(p_account_id, account_id),
        cost_center_id = COALESCE(NULLIF(TRIM(p_cost_center_id), ''), cost_center_id),
        supplier_type = COALESCE(NULLIF(TRIM(p_supplier_type), ''), supplier_type)
    WHERE id = p_id;

    IF p_account_id IS NOT NULL AND p_cost_center_id IS NOT NULL THEN
        UPDATE public.accounts
        SET cost_center_id = p_cost_center_id
        WHERE id = p_account_id;
    END IF;

    RETURN jsonb_build_object('success', TRUE, 'id', p_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_cost_report_category(INTEGER, TEXT, TEXT, BIGINT, TEXT, TEXT) TO authenticated, service_role, anon;

-- Function to delete cost report category
CREATE OR REPLACE FUNCTION public.delete_cost_report_category(p_id INT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    DELETE FROM public.cost_report_categories WHERE id = p_id;
    RETURN jsonb_build_object('success', TRUE, 'id', p_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_cost_report_category(INT) TO authenticated, service_role, anon;

-- ============================================================================
-- 6. Enhance rpc_confirm_packing_order supplier sub-ledger resolution
-- ============================================================================

-- Function to resolve supplier liability account for packing cost item
CREATE OR REPLACE FUNCTION public.fn_resolve_packing_cost_supplier_account(
    p_supplier_id UUID,
    p_company_id UUID
)
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_acc_id BIGINT;
    v_supp_type TEXT;
    v_supp_code TEXT;
    v_target_code TEXT;
BEGIN
    IF p_supplier_id IS NULL THEN
        RETURN public.resolve_gl_account('2111', p_company_id);
    END IF;

    SELECT account_id, supplier_type, code INTO v_acc_id, v_supp_type, v_supp_code
    FROM public.suppliers
    WHERE id = p_supplier_id;

    IF v_acc_id IS NOT NULL THEN
        RETURN v_acc_id;
    END IF;

    -- Infer code from supplier_type
    IF v_supp_type = 'station' OR v_supp_code LIKE '8%' THEN
        v_target_code := '21117';
    ELSIF v_supp_type IN ('deduction', 'deductions') OR v_supp_code LIKE '4%' THEN
        v_target_code := '21118';
    ELSIF v_supp_type = 'transport' OR v_supp_code LIKE '6%' THEN
        v_target_code := '21111';
    ELSIF v_supp_type = 'packaging' OR v_supp_code LIKE '70%' OR v_supp_code LIKE '71%' THEN
        v_target_code := '21112';
    ELSIF v_supp_type = 'shared' OR v_supp_code LIKE '75%' THEN
        v_target_code := '21114';
    ELSIF v_supp_type = 'shipping' OR v_supp_code LIKE '9%' THEN
        v_target_code := '21115';
    ELSE
        v_target_code := '21113';
    END IF;

    RETURN public.resolve_gl_account(v_target_code, p_company_id);
END;
$$;

NOTIFY pgrst, 'reload schema';

COMMIT;
