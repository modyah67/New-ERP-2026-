-- Migration 077: Fix create_customer_account trigger
--
-- ROOT CAUSE:
-- Migration 068 recreated create_customer_account() with references to
-- NEW.customer_code which does NOT exist on the customers table.
-- The customers table only has 'code', not 'customer_code'.
--
-- This causes: column "customer_code" does not exist (42703)
-- when inserting into customers.
--
-- FIX:
-- Remove the customer_code branch and UPDATE reference.

BEGIN;

CREATE OR REPLACE FUNCTION public.create_customer_account()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new_account_id BIGINT;
  v_parent_id BIGINT;
  v_code TEXT;
BEGIN
  SELECT id INTO v_parent_id
  FROM accounts
  WHERE account_code = '1020'
  ORDER BY (company_id = NEW.company_id) DESC, id ASC
  LIMIT 1;

  IF NEW.code IS NOT NULL AND NEW.code <> '' AND NOT EXISTS (SELECT 1 FROM accounts WHERE account_code = NEW.code) THEN
    v_code := NEW.code;
  ELSE
    v_code := public.get_next_entity_account_code('customer', NEW.company_id);
  END IF;

  INSERT INTO accounts (
    account_code, name, account_name, account_type, sort_order,
    company_id, parent_id, level, is_leaf, allow_posting, is_system, is_active
  )
  VALUES (
    v_code,
    'Customer - ' || COALESCE(NEW.name, ''),
    'عميل - ' || COALESCE(NEW.name, ''),
    'asset', 10,
    NEW.company_id,
    v_parent_id,
    4, true, true, false, true
  )
  ON CONFLICT (account_code) DO UPDATE SET
    account_name = 'عميل - ' || COALESCE(EXCLUDED.account_name, public.accounts.account_name),
    name = 'Customer - ' || COALESCE(EXCLUDED.name, public.accounts.name),
    company_id = COALESCE(EXCLUDED.company_id, public.accounts.company_id)
  RETURNING id INTO v_new_account_id;

  IF v_new_account_id IS NULL THEN
    SELECT id INTO v_new_account_id FROM accounts WHERE account_code = v_code LIMIT 1;
  END IF;

  UPDATE customers
  SET account_id = v_new_account_id,
      code = COALESCE(code, v_code)
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;

NOTIFY pgrst, 'reload schema';

COMMIT;
