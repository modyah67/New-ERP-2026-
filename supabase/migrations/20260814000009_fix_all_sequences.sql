DO $$
DECLARE
    seq_record RECORD;
BEGIN
    FOR seq_record IN 
        SELECT 
            t.oid::regclass AS table_name, 
            a.attname AS column_name, 
            s.relname AS sequence_name
        FROM pg_class AS t
        JOIN pg_attribute AS a ON a.attrelid = t.oid
        JOIN pg_depend AS d ON d.refobjid = t.oid AND d.refobjsubid = a.attnum
        JOIN pg_class AS s ON s.oid = d.objid
        WHERE t.relkind = 'r' 
        AND s.relkind = 'S'
        AND t.relnamespace = 'public'::regnamespace
    LOOP
        EXECUTE format(
            'SELECT setval(%L, COALESCE((SELECT MAX(%I) FROM %s), 0) + 1, false)', 
            seq_record.sequence_name, 
            seq_record.column_name, 
            seq_record.table_name
        );
    END LOOP;
END $$;
