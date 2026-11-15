SELECT proname, proargtypes::text, proallargtypes::text, prosrc
FROM pg_proc 
WHERE proname ILIKE '%resolve_bank%';
