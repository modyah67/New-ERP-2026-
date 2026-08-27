-- ============================================================================
-- Migration: Add updated_at to treasury_balances
-- ============================================================================

ALTER TABLE "public"."treasury_balances" ADD COLUMN IF NOT EXISTS "updated_at" TIMESTAMPTZ DEFAULT now();
