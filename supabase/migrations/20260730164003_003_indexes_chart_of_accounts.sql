-- Migration 003: Indexes for Enterprise Chart of Accounts
-- Purpose: Create performance indexes only.
-- Standards: Idempotent, Transactional, Safe.

BEGIN;

-- Hierarchy Indexes
CREATE INDEX IF NOT EXISTS idx_accounts_parent_id ON public.accounts (parent_id);
CREATE INDEX IF NOT EXISTS idx_accounts_level ON public.accounts (level);
CREATE INDEX IF NOT EXISTS idx_accounts_path_ids ON public.accounts (path_ids);
CREATE INDEX IF NOT EXISTS idx_accounts_display_order ON public.accounts (display_order);

-- Business Indexes
CREATE INDEX IF NOT EXISTS idx_accounts_account_type ON public.accounts (account_type);
CREATE INDEX IF NOT EXISTS idx_accounts_account_category ON public.accounts (account_category);

-- Composite Indexes
CREATE INDEX IF NOT EXISTS idx_accounts_parent_display ON public.accounts (parent_id, display_order);

COMMIT;
