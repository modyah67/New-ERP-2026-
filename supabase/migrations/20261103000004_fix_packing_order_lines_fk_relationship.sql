-- ==============================================================================
-- Migration: 20261103000004_fix_packing_order_lines_fk_relationship.sql
-- Description:
-- 1. Ensure foreign key fk_packing_order_lines_packing_order exists between
--    public.packing_order_lines(packing_order_id) and public.packing_orders(id).
-- 2. Ensure foreign keys for other packing child tables are properly defined.
-- 3. Notify PostgREST to reload schema cache so relationships are recognized.
-- ==============================================================================

BEGIN;

-- 1. Fix packing_order_lines foreign key
DO $$
BEGIN
  -- Check if table exists
  IF EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name = 'packing_order_lines'
  ) THEN
    -- Ensure packing_order_id column type is BIGINT
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'packing_order_lines'
        AND column_name = 'packing_order_id' AND data_type = 'uuid'
    ) THEN
      ALTER TABLE public.packing_order_lines
        ALTER COLUMN packing_order_id TYPE BIGINT USING packing_order_id::text::bigint;
    END IF;

    -- Remove any orphaned rows where packing_order_id doesn't match an existing packing order
    DELETE FROM public.packing_order_lines
    WHERE packing_order_id NOT IN (SELECT id FROM public.packing_orders);

    -- Add the foreign key constraint if it doesn't exist
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint WHERE conname = 'fk_packing_order_lines_packing_order'
    ) THEN
      ALTER TABLE public.packing_order_lines
        ADD CONSTRAINT fk_packing_order_lines_packing_order
        FOREIGN KEY (packing_order_id) REFERENCES public.packing_orders(id)
        ON DELETE CASCADE;
    END IF;
  END IF;
END $$;

-- 2. Ensure packing_order_cost_items foreign key exists
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name = 'packing_order_cost_items'
  ) THEN
    -- Ensure packing_order_id column type is BIGINT
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'packing_order_cost_items'
        AND column_name = 'packing_order_id' AND data_type = 'uuid'
    ) THEN
      ALTER TABLE public.packing_order_cost_items
        ALTER COLUMN packing_order_id TYPE BIGINT USING packing_order_id::text::bigint;
    END IF;

    DELETE FROM public.packing_order_cost_items
    WHERE packing_order_id NOT IN (SELECT id FROM public.packing_orders);

    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint WHERE conname = 'fk_packing_order_cost_items_packing_order'
    ) THEN
      ALTER TABLE public.packing_order_cost_items
        ADD CONSTRAINT fk_packing_order_cost_items_packing_order
        FOREIGN KEY (packing_order_id) REFERENCES public.packing_orders(id)
        ON DELETE CASCADE;
    END IF;
  END IF;
END $$;

-- 3. Ensure packing_order_sortings foreign key exists
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name = 'packing_order_sortings'
  ) THEN
    -- Ensure packing_order_id column type is BIGINT
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'packing_order_sortings'
        AND column_name = 'packing_order_id' AND data_type = 'uuid'
    ) THEN
      ALTER TABLE public.packing_order_sortings
        ALTER COLUMN packing_order_id TYPE BIGINT USING packing_order_id::text::bigint;
    END IF;

    DELETE FROM public.packing_order_sortings
    WHERE packing_order_id NOT IN (SELECT id FROM public.packing_orders);

    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint WHERE conname = 'fk_packing_order_sortings_packing_order'
    ) THEN
      ALTER TABLE public.packing_order_sortings
        ADD CONSTRAINT fk_packing_order_sortings_packing_order
        FOREIGN KEY (packing_order_id) REFERENCES public.packing_orders(id)
        ON DELETE CASCADE;
    END IF;
  END IF;
END $$;

-- 4. Ensure packing_wastes foreign key exists
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name = 'packing_wastes'
  ) THEN
    -- Ensure packing_order_id column type is BIGINT
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'packing_wastes'
        AND column_name = 'packing_order_id' AND data_type = 'uuid'
    ) THEN
      ALTER TABLE public.packing_wastes
        ALTER COLUMN packing_order_id TYPE BIGINT USING packing_order_id::text::bigint;
    END IF;

    DELETE FROM public.packing_wastes
    WHERE packing_order_id NOT IN (SELECT id FROM public.packing_orders);

    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint WHERE conname = 'fk_packing_wastes_packing_order'
    ) THEN
      ALTER TABLE public.packing_wastes
        ADD CONSTRAINT fk_packing_wastes_packing_order
        FOREIGN KEY (packing_order_id) REFERENCES public.packing_orders(id)
        ON DELETE CASCADE;
    END IF;
  END IF;
END $$;

-- 5. Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';

COMMIT;

