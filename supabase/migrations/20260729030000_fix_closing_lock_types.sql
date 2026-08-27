CREATE OR REPLACE FUNCTION public.acquire_closing_lock(
  p_user_id UUID,
  p_fiscal_year_id BIGINT
)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_acquired_count INTEGER;
BEGIN
  UPDATE public.fiscal_year_closing_lock
  SET locked_by = p_user_id,
      locked_at = now(),
      fiscal_year_id = p_fiscal_year_id,
      status = 'LOCKED',
      released_at = NULL
  WHERE id = 1 AND status = 'FREE';

  GET DIAGNOSTICS v_acquired_count = ROW_COUNT;
  RETURN v_acquired_count > 0;
END;
$$;

CREATE OR REPLACE FUNCTION public.force_release_stale_lock()
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_released_count INTEGER;
BEGIN
  UPDATE public.fiscal_year_closing_lock
  SET locked_by = NULL,
      released_at = now(),
      status = 'FREE'
  WHERE status = 'LOCKED'
    AND locked_at < now() - interval '30 minutes';
    
  GET DIAGNOSTICS v_released_count = ROW_COUNT;
  RETURN v_released_count > 0;
END;
$$;
