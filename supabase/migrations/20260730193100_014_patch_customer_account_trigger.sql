-- Migration 014: Patch Customer Account Trigger
-- Purpose: Injects company_id into the accounts table when dynamically creating a customer account.

BEGIN;

CREATE OR REPLACE FUNCTION "public"."create_customer_account"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_next_code INTEGER;
BEGIN
  -- Get next code: find max 11xxx customer account code and add 1
  SELECT COALESCE(MAX(account_code::int), 11000) + 1
  INTO v_next_code
  FROM accounts
  WHERE account_code ~ '^11[0-9]{3}$'
    AND company_id = NEW.company_id;

  INSERT INTO accounts (account_code, name, account_name, account_type, sort_order, company_id)
  VALUES (
    LPAD(v_next_code::TEXT, 5, '0'),
    'Customer - ' || COALESCE(NEW.name, ''),
    'عميل - ' || COALESCE(NEW.name, ''),
    'asset', 10,
    NEW.company_id
  );

  RETURN NEW;
END;
$$;

COMMIT;
