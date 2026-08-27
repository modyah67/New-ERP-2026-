-- Migration 144: Ensure sys_companies table exists
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'sys_companies') THEN
    CREATE TABLE public.sys_companies (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      name TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );
    RAISE NOTICE 'Created sys_companies table';
  END IF;
END $$;

-- Notify PostgREST schema reload
NOTIFY pgrst, 'reload schema';
