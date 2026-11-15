SELECT n.nspname, p.proname, oidvectortypes(p.proargtypes) as argtypes
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE p.proname ILIKE '%resolve_bank%';
