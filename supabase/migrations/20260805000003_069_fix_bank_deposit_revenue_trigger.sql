-- Migration 069: Fix bank deposit trigger — only require revenue_account_id for 'revenue' source
-- The trigger trg_require_revenue_acct_bank currently requires revenue_account_id on ALL deposits.
-- With source-based accounting, only 'revenue' source needs a revenue_account_id.

BEGIN;

-- Update the trigger function to check source_type
CREATE OR REPLACE FUNCTION public.fn_require_revenue_account_bank()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    IF NEW.type = 'deposit' AND COALESCE(NEW.source_type, NEW.entity_type) = 'revenue' AND NEW.revenue_account_id IS NULL THEN
        RAISE EXCEPTION 'يجب اختيار حساب إيرادات واحد على الأقل من فضلك';
    END IF;
    RETURN NEW;
END;
$$;

-- Recreate trigger with updated WHEN clause
DROP TRIGGER IF EXISTS trg_require_revenue_acct_bank ON bank_account_transactions;
CREATE TRIGGER trg_require_revenue_acct_bank
    BEFORE INSERT ON bank_account_transactions
    FOR EACH ROW
    WHEN (NEW.type = 'deposit')
    EXECUTE FUNCTION public.fn_require_revenue_account_bank();

COMMIT;
