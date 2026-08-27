-- Migration 034: Phase A — spend_custody + treasury expense subledger
-- SUPERSEDED by Migration 035: subledger logic merged into spend_custody/spend_with_category.
-- This migration drops the old signatures so 035 can recreate with new return types.

BEGIN;

-- Drop old functions to allow return type change (void → bigint)
DROP FUNCTION IF EXISTS public.spend_custody(bigint, varchar, numeric, text, bigint, uuid, bigint, bigint, uuid);
DROP FUNCTION IF EXISTS public.spend_with_category(bigint, varchar, numeric, text, bigint, bigint, uuid, bigint, bigint, uuid);

-- The actual recreation is done by Migration 035.

COMMIT;
