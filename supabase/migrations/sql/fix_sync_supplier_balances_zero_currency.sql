-- ==============================================================================
-- Migration: Fix sync_supplier_balances Zero-Balance Multi-Currency Omission
-- Problem:
--   When get_supplier_true_balances_by_currency() groups balances by currency,
--   it filters with `HAVING SUM(net_amt) <> 0`.
--   When a supplier's currency balance becomes 0 (e.g. paying off opening balance),
--   that currency is omitted from the function results.
--   Consequently, sync_supplier_balances() omitted the currency from
--   current_balances_by_currency entirely (instead of setting it to 0.0),
--   causing the frontend to fall back to the initial payable and show the
--   opening balance card again until a second payment was made.
-- Fix:
--   1. Pre-populate supported currencies (TEXT[]) and initial balance currencies with 0.0.
--   2. Update existing multi-currency suppliers to re-sync their balance maps.
-- ==============================================================================

CREATE OR REPLACE FUNCTION public.sync_supplier_balances(p_supplier_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_cur_balances jsonb := '{}'::jsonb;
  v_total_egp numeric := 0;
  r RECORD;
  c RECORD;
BEGIN
  -- Pre-populate supported currencies (TEXT[]) and currencies with initial balances with 0.0
  FOR c IN
    SELECT DISTINCT cur
    FROM public.suppliers s,
    LATERAL (
      SELECT unnest(COALESCE(s.supported_currencies, ARRAY[]::text[])) AS cur
      UNION
      SELECT jsonb_object_keys(s.initial_balances_by_currency) AS cur
      WHERE s.initial_balances_by_currency IS NOT NULL 
        AND jsonb_typeof(s.initial_balances_by_currency) = 'object'
    ) sub
    WHERE s.id = p_supplier_id 
      AND s.is_multi_currency = true 
      AND cur IS NOT NULL 
      AND cur <> ''
  LOOP
    v_cur_balances := v_cur_balances || jsonb_build_object(UPPER(c.cur), 0.0);
  END LOOP;

  IF to_regproc('public.get_supplier_true_balances_by_currency') IS NOT NULL THEN
    FOR r IN 
      SELECT currency, true_balance, true_balance_egp
      FROM public.get_supplier_true_balances_by_currency()
      WHERE supplier_id = p_supplier_id
    LOOP
      v_cur_balances := v_cur_balances || jsonb_build_object(UPPER(r.currency), r.true_balance);
      v_total_egp := v_total_egp + COALESCE(r.true_balance_egp, 0);
    END LOOP;

    UPDATE public.suppliers
    SET 
      current_balances_by_currency = v_cur_balances,
      outstanding_balance = v_total_egp,
      updated_at = NOW()
    WHERE id = p_supplier_id;
  ELSIF to_regproc('public.get_supplier_true_balances') IS NOT NULL THEN
    UPDATE public.suppliers
    SET outstanding_balance = (SELECT true_balance FROM public.get_supplier_true_balances() WHERE supplier_id = p_supplier_id)
    WHERE id = p_supplier_id;
  END IF;
END;
$$;

-- Resync all multi-currency suppliers so 0-balance currencies are properly reflected as 0.0
DO $$
DECLARE
  sup_rec RECORD;
BEGIN
  FOR sup_rec IN SELECT id FROM public.suppliers WHERE is_multi_currency = true LOOP
    PERFORM public.sync_supplier_balances(sup_rec.id);
  END LOOP;
END;
$$;
