-- ==============================================================================
-- MIGRATION: 20260819000013_349_reparent_fx_accounts_hierarchy.sql
-- Description: Re-parent FX Gain/Loss accounts to proper COA Sub-categories
--   - 4310 (Realized FX Gains) & 4320 (Unrealized FX Gains) -> Parent 4300 (Other Revenue)
--   - 6151 (Realized FX Losses) & 6152 (Unrealized FX Losses) -> Parent 6150 (Currency Differences)
-- ==============================================================================

BEGIN;

-- 1. Re-parent FX Gains (4310, 4320) under 4300 (Other Revenue)
UPDATE public.accounts
SET parent_id = (SELECT id FROM public.accounts WHERE account_code = '4300' LIMIT 1),
    updated_at = NOW()
WHERE account_code IN ('4310', '4320');

-- 2. Re-parent FX Losses (6151, 6152) under 6150 (Currency Differences)
UPDATE public.accounts
SET parent_id = COALESCE(
        (SELECT id FROM public.accounts WHERE account_code = '6150' LIMIT 1),
        (SELECT id FROM public.accounts WHERE account_code = '6000' LIMIT 1)
    ),
    updated_at = NOW()
WHERE account_code IN ('6151', '6152');

-- 3. Update is_leaf flags for parent accounts
UPDATE public.accounts
SET is_leaf = false,
    updated_at = NOW()
WHERE account_code IN ('4300', '6150')
  AND EXISTS (SELECT 1 FROM public.accounts WHERE parent_id = public.accounts.id);

COMMIT;
