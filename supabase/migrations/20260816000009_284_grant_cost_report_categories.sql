BEGIN;

ALTER TABLE public.cost_report_categories ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow read access on cost_report_categories" ON public.cost_report_categories;
CREATE POLICY "Allow read access on cost_report_categories" ON public.cost_report_categories FOR SELECT USING (true);
GRANT SELECT ON public.cost_report_categories TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.list_cost_report_categories(text) TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload_schema';

COMMIT;
