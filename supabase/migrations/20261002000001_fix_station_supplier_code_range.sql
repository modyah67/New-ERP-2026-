-- ============================================================================
-- Fix Station Supplier Code Range: 85000-89999 (was 80000-89999)
-- Stations (sub-warehouses) keep 80000-84999
-- This resolves the code collision between stations table and suppliers table
-- ============================================================================

-- 1. Ensure constraint allows 'station' type
ALTER TABLE public.suppliers DROP CONSTRAINT IF EXISTS suppliers_supplier_type_check;

ALTER TABLE public.suppliers
ADD CONSTRAINT suppliers_supplier_type_check 
CHECK (supplier_type IN ('crop', 'packaging', 'shared', 'station', 'deduction', 'deductions', 'transport'));

-- 1b. Ensure accounts 21117 and 21118 exist in accounts table
DO $$
DECLARE
  v_parent_id BIGINT;
  v_company_id UUID;
  v_path_ids TEXT;
BEGIN
  SELECT id, company_id, path_ids INTO v_parent_id, v_company_id, v_path_ids
  FROM public.accounts
  WHERE account_code = '2111'
  LIMIT 1;

  IF v_parent_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = '21117') THEN
      INSERT INTO public.accounts (
        account_code, name, account_name, parent_id, account_type, sort_order,
        company_id, level, path_ids, path_codes, allow_posting, is_leaf, is_active, normal_balance
      ) VALUES (
        '21117', 'Station Suppliers Sub-ledger', 'موردي المحطات', v_parent_id, 'liability', 21117,
        v_company_id, 5, COALESCE(v_path_ids, '') || '/', '2/21/211/2111/21117', true, true, true, 'Credit'
      );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = '21118') THEN
      INSERT INTO public.accounts (
        account_code, name, account_name, parent_id, account_type, sort_order,
        company_id, level, path_ids, path_codes, allow_posting, is_leaf, is_active, normal_balance
      ) VALUES (
        '21118', 'Deductions Suppliers Sub-ledger', 'موردي التخصيمات', v_parent_id, 'liability', 21118,
        v_company_id, 5, COALESCE(v_path_ids, '') || '/', '2/21/211/2111/21118', true, true, true, 'Credit'
      );
    END IF;
  END IF;
END $$;

-- 2. Update code range validation trigger to use 85000-89999 for station suppliers
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
      IF v_code_num < 85000 OR v_code_num > 89999 THEN
        RAISE EXCEPTION 'كود مورد المحطة غير صالح: (%) يجب أن يكون في النطاق 85000 إلى 89999 (سعة: 5000 سجل)', NEW.code;
      END IF;

    WHEN 'deduction', 'deductions' THEN
      IF v_code_num < 40000 OR v_code_num > 49999 THEN
        RAISE EXCEPTION 'كود مورد التخصيمات غير صالح: (%) يجب أن يكون في النطاق 40000 إلى 49999 (سعة: 10000 سجل)', NEW.code;
      END IF;

    ELSE
      -- Default allow other types
  END CASE;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_supplier_code_range ON public.suppliers;
CREATE TRIGGER trg_validate_supplier_code_range
BEFORE INSERT OR UPDATE OF code, supplier_type ON public.suppliers
FOR EACH ROW
EXECUTE FUNCTION public.trg_fn_validate_supplier_category_code_range();

-- 3. Update the automatic master account binding trigger
-- Ensure 'station' maps to 21117 (not grouped with packaging)
CREATE OR REPLACE FUNCTION public.create_supplier_account()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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
  -- 'transport' -> 21111 (موردي النقل والسيارات)
  -- 'packaging' / 'sticker' -> 21112 (موردي مواد التعبئة)
  -- 'crop' -> 21113 (موردي مشتريات محاصيل)
  -- 'shared' -> 21114 (موردين مشتركين)
  -- 'shipping' -> 21115 (شركات الشحن)
  -- 'clearing' -> 21116 (مخلصي الجمارك)
  -- 'station' -> 21117 (موردي المحطات)
  -- 'deduction' -> 21118 (موردي التخصيمات)
  IF v_raw_type IN ('transport', 'transporter', 'مورد نقل', 'نقل', 'سيارات') 
     OR (NEW.code)::text LIKE '6%' THEN
    v_target_account_code := '21111';
  ELSIF v_raw_type IN ('station', 'stations', 'مورد محطة', 'موردي المحطات', 'محطة', 'محطات')
     OR (NEW.code)::text LIKE '85%' OR (NEW.code)::text LIKE '86%' OR (NEW.code)::text LIKE '87%' OR (NEW.code)::text LIKE '88%' OR (NEW.code)::text LIKE '89%' THEN
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
