-- Migration 087: Add missing columns to journal_entries required by packing order RPCs.
-- The journal_entries table was created in 000000_unified_journal_entries.sql without
-- company_id or updated_at. The RPCs rpc_confirm_packing_order and rpc_cancel_packing_order
-- INSERT/UPDATE these columns.

ALTER TABLE public.journal_entries
ADD COLUMN IF NOT EXISTS company_id uuid,
ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();
