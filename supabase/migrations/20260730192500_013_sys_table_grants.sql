-- Grant permissions for sys_companies and other sys tables created in recent migrations

GRANT SELECT ON public.sys_companies TO anon, authenticated, service_role;
GRANT SELECT ON public.tax_codes TO anon, authenticated, service_role;
GRANT SELECT ON public.tax_rates TO anon, authenticated, service_role;
GRANT SELECT ON public.posting_profiles TO anon, authenticated, service_role;
GRANT SELECT ON public.posting_account_roles TO anon, authenticated, service_role;
GRANT SELECT ON public.posting_profile_rules TO anon, authenticated, service_role;
GRANT SELECT ON public.accounting_periods TO anon, authenticated, service_role;
GRANT SELECT ON public.sys_document_types TO anon, authenticated, service_role;
GRANT SELECT ON public.sys_sequences TO anon, authenticated, service_role;
GRANT SELECT ON public.document_posting_templates TO anon, authenticated, service_role;
GRANT SELECT ON public.posting_validation_rules TO anon, authenticated, service_role;
