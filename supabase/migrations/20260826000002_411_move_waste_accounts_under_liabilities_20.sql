-- Migration 411: Move 2106 and 2107 directly under Liabilities (20)

DO $$
DECLARE
  v_parent_id bigint;
BEGIN
  -- Find account 20 (الخصوم)
  SELECT id INTO v_parent_id 
  FROM public.accounts 
  WHERE code = '20' OR account_code = '20' 
  LIMIT 1;

  IF v_parent_id IS NOT NULL THEN
    -- Move 2106 under 20
    UPDATE public.accounts
    SET parent_id = v_parent_id,
        updated_at = now()
    WHERE code = '2106' OR account_code = '2106';

    -- Move 2107 under 20
    UPDATE public.accounts
    SET parent_id = v_parent_id,
        updated_at = now()
    WHERE code = '2107' OR account_code = '2107';
  END IF;
END $$;
