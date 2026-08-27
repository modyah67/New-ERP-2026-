-- Migration 222: Fix all sequences
-- This resets all sequences to ensure they are synchronized with the max id of their respective tables.
-- Useful after a script inserts explicit IDs without advancing the sequence.

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT pg_get_serial_sequence('public.' || t.relname, a.attname) AS seq_name,
           'public.' || quote_ident(t.relname) AS table_name
    FROM pg_class t
    JOIN pg_attribute a ON a.attrelid = t.oid
    WHERE t.relkind = 'r'
      AND a.attnum > 0
      AND NOT a.attisdropped
      AND pg_get_serial_sequence('public.' || t.relname, a.attname) IS NOT NULL
      AND t.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  LOOP
    BEGIN
      EXECUTE format('SELECT setval(%L, COALESCE((SELECT MAX(id) FROM %s), 0) + 1, false)', r.seq_name, r.table_name);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
END $$;
