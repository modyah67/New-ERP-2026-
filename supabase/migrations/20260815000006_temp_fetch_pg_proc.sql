CREATE OR REPLACE FUNCTION public.fetch_post_journal_entry_overloads()
RETURNS TABLE (oid oid, proname name, args text)
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT oid, proname, pg_get_function_identity_arguments(oid) AS args
  FROM pg_proc WHERE proname = 'post_journal_entry' AND pronamespace = 'public'::regnamespace;
$$;

NOTIFY pgrst, 'reload schema';
