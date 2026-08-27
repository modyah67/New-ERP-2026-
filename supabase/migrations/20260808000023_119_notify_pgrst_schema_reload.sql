-- Migration 119: Force PostgREST schema cache reload
-- This ensures the schema cache matches the actual database after all fixes

-- Notify PostgREST to reload its schema cache
DO $$
BEGIN
  PERFORM pg_notify('pgrst', 'reload schema');
END
$$;
