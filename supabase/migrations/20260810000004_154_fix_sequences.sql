-- Migration 154: Fix Sequences
-- Syncs all sequences to the max id of their respective tables to fix "duplicate key" errors

DO $$
DECLARE
    seq_record RECORD;
BEGIN
    FOR seq_record IN 
        SELECT 
            t.oid::regclass AS table_name, 
            a.attname AS column_name, 
            s.relname AS sequence_name
        FROM pg_class s
        JOIN pg_depend d ON d.objid = s.oid
        JOIN pg_class t ON d.refobjid = t.oid
        JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = d.refobjsubid
        WHERE s.relkind = 'S' AND t.relnamespace = 'public'::regnamespace
    LOOP
        EXECUTE format(
            'SELECT setval(%L, COALESCE((SELECT MAX(%I) FROM %s), 0) + 1, false)', 
            seq_record.sequence_name, 
            seq_record.column_name, 
            seq_record.table_name
        );
    END LOOP;
END $$;
