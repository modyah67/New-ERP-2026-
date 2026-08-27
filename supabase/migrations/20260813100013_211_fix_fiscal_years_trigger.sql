CREATE OR REPLACE FUNCTION public.fiscal_years_before_upsert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  overlapping_count INT;
  current_count INT;
BEGIN
  -- Ensure start_date < end_date
  IF NEW.start_date >= NEW.end_date THEN
    RAISE EXCEPTION 'Fiscal year start_date must be before end_date.';
  END IF;

  -- Check for overlapping periods (exclude self on UPDATE)
  SELECT COUNT(*) INTO overlapping_count
  FROM public.fiscal_years
  WHERE id <> COALESCE(NEW.id, 0)
    AND company_id = NEW.company_id
    AND NEW.start_date <= end_date
    AND NEW.end_date >= start_date;
  IF overlapping_count > 0 THEN
    RAISE EXCEPTION 'Fiscal year period overlaps with existing fiscal year.';
  END IF;

  -- Enforce only one current fiscal year per company
  IF NEW.is_current THEN
    SELECT COUNT(*) INTO current_count
    FROM public.fiscal_years
    WHERE id <> COALESCE(NEW.id, 0)
      AND company_id = NEW.company_id
      AND is_current = TRUE;
    IF current_count > 0 THEN
      RAISE EXCEPTION 'Only one fiscal year can be marked as current.';
    END IF;
  END IF;

  -- Auto-update timestamp
  NEW.updated_at := now();
  RETURN NEW;
END;
$function$;
