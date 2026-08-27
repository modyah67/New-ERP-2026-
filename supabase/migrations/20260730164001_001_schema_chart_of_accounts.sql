-- Migration 001: Schema Modifications for Enterprise Chart of Accounts
-- Purpose: Safely adds structural columns only.
-- Standards: Idempotent, Transactional, No Constraints, No Indexes, No Updates.

BEGIN;

DO $$
BEGIN
    -- Hierarchical Meta-data
    ALTER TABLE IF EXISTS public.accounts ADD COLUMN IF NOT EXISTS level INTEGER DEFAULT 1;
    ALTER TABLE IF EXISTS public.accounts ADD COLUMN IF NOT EXISTS path_ids TEXT;
    ALTER TABLE IF EXISTS public.accounts ADD COLUMN IF NOT EXISTS path_codes TEXT;
    ALTER TABLE IF EXISTS public.accounts ADD COLUMN IF NOT EXISTS display_order INTEGER DEFAULT 0;

    -- Financial & Behavioral Meta-data
    ALTER TABLE IF EXISTS public.accounts ADD COLUMN IF NOT EXISTS allow_posting BOOLEAN DEFAULT true;
    ALTER TABLE IF EXISTS public.accounts ADD COLUMN IF NOT EXISTS is_leaf BOOLEAN DEFAULT true;
    ALTER TABLE IF EXISTS public.accounts ADD COLUMN IF NOT EXISTS is_system BOOLEAN DEFAULT false;
    ALTER TABLE IF EXISTS public.accounts ADD COLUMN IF NOT EXISTS is_locked BOOLEAN DEFAULT false;
    ALTER TABLE IF EXISTS public.accounts ADD COLUMN IF NOT EXISTS normal_balance TEXT;
    ALTER TABLE IF EXISTS public.accounts ADD COLUMN IF NOT EXISTS account_category TEXT;

    -- System Contract & Migration Meta-data
    ALTER TABLE IF EXISTS public.accounts ADD COLUMN IF NOT EXISTS system_key TEXT;
    ALTER TABLE IF EXISTS public.accounts ADD COLUMN IF NOT EXISTS account_origin TEXT DEFAULT 'USER_GENERATED';
    ALTER TABLE IF EXISTS public.accounts ADD COLUMN IF NOT EXISTS migration_source TEXT;

    -- Audit & Operational Meta-data
    ALTER TABLE IF EXISTS public.accounts ADD COLUMN IF NOT EXISTS notes TEXT;
    ALTER TABLE IF EXISTS public.accounts ADD COLUMN IF NOT EXISTS created_by UUID;
    ALTER TABLE IF EXISTS public.accounts ADD COLUMN IF NOT EXISTS updated_by UUID;
END $$;

COMMIT;
