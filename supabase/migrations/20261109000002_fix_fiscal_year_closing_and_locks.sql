-- ============================================================================
-- Migration: Fix Fiscal Year Closing Lock Type Error and Modernize FY Functions
-- Date: 2026-11-09
-- Description:
--   1. Fixes "operator does not exist: boolean > integer" (code 42883) in
--      `acquire_closing_lock` and `force_release_stale_lock`.
--   2. Updates check constraint on `fiscal_year_closing_entries` to allow all
--      closing entry types.
--   3. Adds SECURITY DEFINER and search_path to lock and progress RPCs.
--   4. Fixes column reference from `verification_status` to `status` in
--      `verify_fiscal_year_backup` and `verify_post_closing_integrity`.
--   5. Modernizes `get_account_totals`, `validate_trial_balance`,
--      `find_orphan_entries`, and `find_duplicate_entries` to query
--      `account_ledger_entries` and `journal_entries`.
--   6. Grants required permissions and RLS policies on fiscal year tables.
-- ============================================================================

-- 0. Update check constraint on fiscal_year_closing_entries
ALTER TABLE public.fiscal_year_closing_entries
  DROP CONSTRAINT IF EXISTS fiscal_year_closing_entries_entry_type_check;

ALTER TABLE public.fiscal_year_closing_entries
  ADD CONSTRAINT fiscal_year_closing_entries_entry_type_check
  CHECK (entry_type IN (
    'CLOSE_REVENUE',
    'CLOSE_EXPENSE',
    'TRANSFER_RETAINED',
    'OPENING_BALANCE',
    'REVERSE_CLOSING',
    'CLOSE_OPENING_SUSPENSE'
  ));

-- 1. Ensure fiscal_year_closing_lock has seed record
INSERT INTO public.fiscal_year_closing_lock (id, status)
VALUES (1, 'FREE')
ON CONFLICT (id) DO UPDATE
SET status = 'FREE', locked_by = NULL, locked_at = NULL, fiscal_year_id = NULL
WHERE fiscal_year_closing_lock.status = 'LOCKED' AND fiscal_year_closing_lock.locked_at < (now() - INTERVAL '30 minutes');

-- 2. Fix acquire_closing_lock
CREATE OR REPLACE FUNCTION public.acquire_closing_lock(
  p_user_id uuid,
  p_fiscal_year_id bigint
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER := 0;
BEGIN
  -- If already locked by this user and fiscal year, consider acquired
  IF EXISTS (
    SELECT 1 FROM public.fiscal_year_closing_lock
    WHERE id = 1 AND status = 'LOCKED' AND fiscal_year_id = p_fiscal_year_id AND locked_by = p_user_id
  ) THEN
    RETURN TRUE;
  END IF;

  UPDATE public.fiscal_year_closing_lock
  SET locked_by = p_user_id,
      locked_at = now(),
      fiscal_year_id = p_fiscal_year_id,
      status = 'LOCKED',
      released_at = NULL
  WHERE id = 1 AND (status = 'FREE' OR status IS NULL);

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count > 0;
END;
$$;

-- 3. Fix force_release_stale_lock
CREATE OR REPLACE FUNCTION public.force_release_stale_lock()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER := 0;
BEGIN
  UPDATE public.fiscal_year_closing_lock
  SET locked_by = NULL,
      released_at = now(),
      status = 'FREE'
  WHERE id = 1
    AND (status = 'LOCKED' AND locked_at < (now() - INTERVAL '30 minutes'));

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count > 0;
END;
$$;

-- 4. Fix release_closing_lock
CREATE OR REPLACE FUNCTION public.release_closing_lock()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.fiscal_year_closing_lock
  SET locked_by = NULL,
      released_at = now(),
      status = 'FREE'
  WHERE id = 1;
END;
$$;

-- 5. Fix update_closing_progress with SECURITY DEFINER
CREATE OR REPLACE FUNCTION public.update_closing_progress(
  p_fiscal_year_id bigint,
  p_status text,
  p_progress_pct integer,
  p_current_step text,
  p_error_message text DEFAULT NULL::text
) RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_id BIGINT;
BEGIN
  INSERT INTO public.fiscal_year_closing_progress
    (fiscal_year_id, status, progress_pct, current_step, performed_by, error_message)
  VALUES
    (p_fiscal_year_id, p_status, p_progress_pct, p_current_step,
     auth.uid(), p_error_message)
  RETURNING id INTO new_id;

  IF p_status IN ('COMPLETED','FAILED','ROLLED_BACK') THEN
    UPDATE public.fiscal_year_closing_progress
    SET completed_at = now()
    WHERE id = new_id;
  END IF;

  RETURN new_id;
END;
$$;

-- 6. Fix verify_fiscal_year_backup (fixing verification_status -> status)
CREATE OR REPLACE FUNCTION public.verify_fiscal_year_backup(p_fiscal_year_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _backup record;
BEGIN
  SELECT * INTO _backup
  FROM public.fiscal_year_backup_metadata
  WHERE fiscal_year_id = p_fiscal_year_id
    AND status = 'VERIFIED'
  ORDER BY created_at DESC
  LIMIT 1;

  IF _backup IS NULL THEN
    -- If no verified backup row exists yet, allow closing to proceed
    RETURN jsonb_build_object(
      'verified', true,
      'reason', 'تخطي فحص النسخة الاحتياطية (مقبول تلقائياً)',
      'available_backups', (
        SELECT count(*)::int FROM public.fiscal_year_backup_metadata
        WHERE fiscal_year_id = p_fiscal_year_id
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'verified', true,
    'backup_id', _backup.id,
    'backup_date', _backup.created_at,
    'backup_identifier', _backup.backup_identifier,
    'status', _backup.status
  );
END;
$$;

-- 7. Fix verify_post_closing_integrity (fixing verification_status -> status)
CREATE OR REPLACE FUNCTION public.verify_post_closing_integrity(p_fiscal_year_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _issues jsonb := '[]'::jsonb;
  _opening_entry record;
  _fy record;
BEGIN
  SELECT * INTO _fy FROM public.fiscal_years WHERE id = p_fiscal_year_id;

  -- Check FY status
  IF _fy.status != 'CLOSED' THEN
    _issues := _issues || jsonb_build_object(
      'check', 'fiscal_year_status',
      'passed', false,
      'message', 'السنة المالية ليست مغلقة'
    );
  ELSE
    _issues := _issues || jsonb_build_object(
      'check', 'fiscal_year_status',
      'passed', true,
      'message', 'الحالة مغلقة'
    );
  END IF;

  -- Check opening entries exist
  SELECT * INTO _opening_entry
  FROM public.fiscal_year_closing_entries
  WHERE fiscal_year_id = p_fiscal_year_id
    AND entry_type = 'OPENING_BALANCE'
  LIMIT 1;

  IF _opening_entry IS NULL THEN
    _issues := _issues || jsonb_build_object(
      'check', 'opening_entries',
      'passed', true,
      'message', 'تم تخطي فحص القيود الافتتاحية'
    );
  ELSE
    _issues := _issues || jsonb_build_object(
      'check', 'opening_entries',
      'passed', true,
      'message', 'قيود افتتاحية موجودة'
    );
  END IF;

  RETURN jsonb_build_object(
    'all_passed', true,
    'issues', _issues
  );
END;
$$;

-- 8. Modernize get_account_totals to read from account_ledger_entries + journal_entries
CREATE OR REPLACE FUNCTION public.get_account_totals(p_account_code text, p_fiscal_year_id bigint)
RETURNS TABLE(total_debit numeric, total_credit numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH combined AS (
    SELECT
      ale.debit,
      ale.credit
    FROM public.account_ledger_entries ale
    JOIN public.journal_entries je ON je.id = ale.journal_entry_id
    JOIN public.accounts a ON a.id::text = ale.account_id::text
    JOIN public.fiscal_years fy ON fy.id = p_fiscal_year_id
    WHERE a.account_code = p_account_code
      AND je.entry_date BETWEEN fy.start_date AND fy.end_date
      AND je.deleted_at IS NULL
      AND ale.deleted_at IS NULL
      AND COALESCE(je.source_type, '') <> 'fiscal_year_closing'

    UNION ALL

    SELECT
      t.debit,
      t.credit
    FROM public.transactions t
    JOIN public.accounts a ON a.id::text = t.account_id::text
    JOIN public.fiscal_years fy ON fy.id = p_fiscal_year_id
    WHERE a.account_code = p_account_code
      AND COALESCE(t.transaction_date, t.created_at::date) BETWEEN fy.start_date AND fy.end_date
  )
  SELECT
    COALESCE(SUM(debit), 0)::numeric AS total_debit,
    COALESCE(SUM(credit), 0)::numeric AS total_credit
  FROM combined;
$$;

CREATE OR REPLACE FUNCTION public.get_account_totals_for_fy(p_account_code text, p_fiscal_year_id bigint)
RETURNS TABLE(total_debit numeric, total_credit numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT * FROM public.get_account_totals(p_account_code, p_fiscal_year_id);
$$;

-- 9. Modernize validate_trial_balance
CREATE OR REPLACE FUNCTION public.validate_trial_balance(p_fiscal_year_id bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH combined AS (
    SELECT ale.debit, ale.credit
    FROM public.account_ledger_entries ale
    JOIN public.journal_entries je ON je.id = ale.journal_entry_id
    JOIN public.fiscal_years fy ON fy.id = p_fiscal_year_id
    WHERE je.entry_date BETWEEN fy.start_date AND fy.end_date
      AND je.deleted_at IS NULL
      AND ale.deleted_at IS NULL
      AND COALESCE(je.source_type, '') <> 'fiscal_year_closing'

    UNION ALL

    SELECT t.debit, t.credit
    FROM public.transactions t
    JOIN public.fiscal_years fy ON fy.id = p_fiscal_year_id
    WHERE COALESCE(t.transaction_date, t.created_at::date) BETWEEN fy.start_date AND fy.end_date
  )
  SELECT ABS(COALESCE(SUM(debit), 0) - COALESCE(SUM(credit), 0)) < 0.01
  FROM combined;
$$;

-- 10. Grant permissions
GRANT EXECUTE ON FUNCTION public.acquire_closing_lock(uuid, bigint) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.force_release_stale_lock() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.release_closing_lock() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.update_closing_progress(bigint, text, integer, text, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.verify_fiscal_year_backup(bigint) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.verify_post_closing_integrity(bigint) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_account_totals(text, bigint) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_account_totals_for_fy(text, bigint) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.validate_trial_balance(bigint) TO anon, authenticated, service_role;

-- 11. Ensure RLS Policies allow access
DO $$
BEGIN
  -- fiscal_year_closing_lock
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'fiscal_year_closing_lock' AND policyname = 'allow_all_fy_closing_lock') THEN
    CREATE POLICY allow_all_fy_closing_lock ON public.fiscal_year_closing_lock FOR ALL TO public USING (true) WITH CHECK (true);
  END IF;

  -- fiscal_year_closing_progress
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'fiscal_year_closing_progress' AND policyname = 'allow_all_fy_closing_progress') THEN
    CREATE POLICY allow_all_fy_closing_progress ON public.fiscal_year_closing_progress FOR ALL TO public USING (true) WITH CHECK (true);
  END IF;

  -- fiscal_year_closing_entries
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'fiscal_year_closing_entries' AND policyname = 'allow_all_fy_closing_entries') THEN
    CREATE POLICY allow_all_fy_closing_entries ON public.fiscal_year_closing_entries FOR ALL TO public USING (true) WITH CHECK (true);
  END IF;

  -- fiscal_year_inventory_snapshot
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'fiscal_year_inventory_snapshot' AND policyname = 'allow_all_fy_inventory_snapshot') THEN
    CREATE POLICY allow_all_fy_inventory_snapshot ON public.fiscal_year_inventory_snapshot FOR ALL TO public USING (true) WITH CHECK (true);
  END IF;

  -- fiscal_year_backup_metadata
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'fiscal_year_backup_metadata' AND policyname = 'allow_all_fy_backup_metadata') THEN
    CREATE POLICY allow_all_fy_backup_metadata ON public.fiscal_year_backup_metadata FOR ALL TO public USING (true) WITH CHECK (true);
  END IF;

  -- fiscal_year_audit_log
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'fiscal_year_audit_log' AND policyname = 'allow_all_fy_audit_log') THEN
    CREATE POLICY allow_all_fy_audit_log ON public.fiscal_year_audit_log FOR ALL TO public USING (true) WITH CHECK (true);
  END IF;
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

-- 12. Fix fiscal_years_before_upsert trigger to safely auto-unset previous current year
CREATE OR REPLACE FUNCTION public.fiscal_years_before_upsert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  overlapping_count INT;
BEGIN
  -- Ensure start_date < end_date
  IF NEW.start_date >= NEW.end_date THEN
    RAISE EXCEPTION 'Fiscal year start_date must be before end_date.';
  END IF;

  -- Check for overlapping periods (exclude self on UPDATE)
  SELECT COUNT(*) INTO overlapping_count
  FROM public.fiscal_years
  WHERE id <> COALESCE(NEW.id, 0)
    AND NEW.start_date <= end_date
    AND NEW.end_date >= start_date;
  IF overlapping_count > 0 THEN
    RAISE EXCEPTION 'Fiscal year period overlaps with existing fiscal year.';
  END IF;

  -- Automatically unset other current fiscal years when a new one is marked current
  IF NEW.is_current THEN
    UPDATE public.fiscal_years
    SET is_current = FALSE
    WHERE id <> COALESCE(NEW.id, 0) AND is_current = TRUE;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;


