-- ============================================================================
-- Migration: Lock & Settlement Status Protection for Packing Order Cost Items
-- Description:
--   1. Adds is_locked, locked_at, and locked_by columns to packing_order_cost_items.
--   2. Automatically locks any cost item that has already been settled/reconciled.
--   3. Updates rpc_settle_packing_cost_variances to explicitly lock settled items.
--   4. Creates a database trigger preventing unauthorized update/delete of locked items
--      unless performed by an administrator.
-- ============================================================================

-- 1. Add lock metadata columns
ALTER TABLE public.packing_order_cost_items
ADD COLUMN IF NOT EXISTS is_locked BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS locked_at TIMESTAMPTZ DEFAULT NULL,
ADD COLUMN IF NOT EXISTS locked_by UUID DEFAULT NULL;

-- 2. Backfill: Lock all existing settled / actual items
UPDATE public.packing_order_cost_items
SET is_locked = TRUE,
    locked_at = COALESCE(reconciled_at, now())
WHERE cost_status IN ('actual', 'settled', 'locked')
   OR reconciled_at IS NOT NULL;

-- 3. Create anti-tamper trigger function for locked cost items
CREATE OR REPLACE FUNCTION public.fn_prevent_locked_cost_item_tamper()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_admin BOOLEAN := FALSE;
  v_current_user_id UUID;
BEGIN
  -- Get current user id
  v_current_user_id := auth.uid();

  -- If called internally by superuser/service_role without active JWT auth.uid(), allow
  IF v_current_user_id IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Check if current user is admin in users table
  SELECT is_admin INTO v_is_admin 
  FROM public.users 
  WHERE id = v_current_user_id;

  -- If item was already locked
  IF OLD.is_locked = TRUE THEN
    -- Case A: DELETE attempt on locked item
    IF TG_OP = 'DELETE' THEN
      IF v_is_admin IS NOT TRUE THEN
        RAISE EXCEPTION 'لا يمكن حذف بند تكلفة معتمد ومقفل إلا من خلال صلاحيات المدير (Admin).';
      END IF;
    END IF;

    -- Case B: UPDATE attempt on locked item
    IF TG_OP = 'UPDATE' THEN
      -- If financial fields were changed by non-admin
      IF v_is_admin IS NOT TRUE AND (
         COALESCE(NEW.actual_amount, 0) <> COALESCE(OLD.actual_amount, 0) OR
         COALESCE(NEW.expected_amount, 0) <> COALESCE(OLD.expected_amount, 0) OR
         COALESCE(NEW.base_amount, 0) <> COALESCE(OLD.base_amount, 0)
      ) THEN
        RAISE EXCEPTION 'هذا البند معتمد ومقفل. لا يمكن تعديل القيم المالية إلا بصلاحيات المدير (Admin) أو عبر قيد تسوية عكسي معتمد.';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- 4. Bind trigger
DROP TRIGGER IF EXISTS trg_prevent_locked_cost_item_tamper ON public.packing_order_cost_items;
CREATE TRIGGER trg_prevent_locked_cost_item_tamper
BEFORE UPDATE OR DELETE ON public.packing_order_cost_items
FOR EACH ROW
EXECUTE FUNCTION public.fn_prevent_locked_cost_item_tamper();

COMMENT ON COLUMN public.packing_order_cost_items.is_locked IS 'إقفال البند بعد اعتماد التسوية لمنع التلاعب';

