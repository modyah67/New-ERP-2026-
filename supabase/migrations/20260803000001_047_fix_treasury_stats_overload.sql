-- Phase 047: Fix get_treasury_stats function overload conflict
-- The old migration created get_treasury_stats(INTEGER, BOOLEAN, DATE, DATE)
-- The 045 migration created get_treasury_stats(TEXT, BOOLEAN, TEXT, TEXT)
-- PostgreSQL keeps both as overloads, Postgrest can't choose.

-- Drop ALL old overloads
DROP FUNCTION IF EXISTS public.get_treasury_stats(INTEGER, BOOLEAN, DATE, DATE);
DROP FUNCTION IF EXISTS public.get_treasury_stats(INTEGER, BOOLEAN, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.get_treasury_stats(BIGINT, BOOLEAN, DATE, DATE);
DROP FUNCTION IF EXISTS public.get_treasury_stats(BIGINT, BOOLEAN, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.get_treasury_stats(p_main_treasury_id INTEGER, p_all_treasuries BOOLEAN, p_start_date DATE, p_end_date DATE);
DROP FUNCTION IF EXISTS public.get_treasury_stats(p_main_treasury_id INTEGER, p_all_treasuries BOOLEAN, p_start_date TEXT, p_end_date TEXT);
DROP FUNCTION IF EXISTS public.get_treasury_stats(p_main_treasury_id BIGINT, p_all_treasuries BOOLEAN, p_start_date DATE, p_end_date DATE);
DROP FUNCTION IF EXISTS public.get_treasury_stats(p_main_treasury_id BIGINT, p_all_treasuries BOOLEAN, p_start_date TEXT, p_end_date TEXT);
