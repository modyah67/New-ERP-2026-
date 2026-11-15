-- ============================================================================
-- Fix Supplier Types & Code Range Trigger for Station & Deduction Suppliers
-- ============================================================================

-- 1. Drop and recreate check constraint to allow station, deduction, deductions, transport
ALTER TABLE public.suppliers DROP CONSTRAINT IF EXISTS suppliers_supplier_type_check;

ALTER TABLE public.suppliers
ADD CONSTRAINT suppliers_supplier_type_check 
CHECK (supplier_type IN ('crop', 'packaging', 'shared', 'station', 'deduction', 'deductions', 'transport'));

-- 2. Ensure categories column exists
ALTER TABLE public.suppliers ADD COLUMN IF NOT EXISTS categories text[] DEFAULT '{}';

-- 3. Update the validation trigger function to recognize station (80000-89999) & deduction (40000-49999)
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
      -- Default allow other types
  END CASE;

  RETURN NEW;
END;
$$;
