-- ═══════════════════════════════════════════════════════════════════
-- Migration: Fix packing_order child tables UUID → BIGINT mismatch
-- ═══════════════════════════════════════════════════════════════════
-- Problem: packing_orders.id is BIGINT, but child tables have
-- packing_order_id as UUID. This causes "operator does not exist: 
-- uuid = bigint" in rpc_confirm_packing_order.
--
-- Fix: ALTER the packing_order_id column in all child tables from
-- UUID to BIGINT, converting existing values.
-- ═══════════════════════════════════════════════════════════════════

-- 1. packing_order_cost_items
ALTER TABLE public.packing_order_cost_items 
  ALTER COLUMN packing_order_id TYPE BIGINT USING packing_order_id::text::bigint;

-- 2. packing_order_lines
ALTER TABLE public.packing_order_lines 
  ALTER COLUMN packing_order_id TYPE BIGINT USING packing_order_id::text::bigint;

-- 3. packing_order_sortings
ALTER TABLE public.packing_order_sortings 
  ALTER COLUMN packing_order_id TYPE BIGINT USING packing_order_id::text::bigint;

-- 4. packing_wastes
ALTER TABLE public.packing_wastes 
  ALTER COLUMN packing_order_id TYPE BIGINT USING packing_order_id::text::bigint;
