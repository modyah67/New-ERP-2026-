-- ============================================================================
-- 042_fix_customer_account_cleanup.sql
-- ============================================================================
-- This migration fixes the customer account cleanup issue:
-- 1. Removes existing orphan customer accounts
-- 2. Fixes customer account creation to properly link accounts
-- 3. Adds DELETE trigger to remove accounts when customers are deleted
-- ============================================================================

BEGIN;

-- ============================================================================
-- STEP 1: Remove existing orphan customer accounts
-- ============================================================================

-- First, identify and remove orphan customer accounts
DELETE FROM accounts 
WHERE account_code LIKE '111%'
  AND account_name ILIKE '%عميل%'
  AND NOT EXISTS (
    SELECT 1 FROM customers c 
    WHERE c.deleted_at IS NULL
      AND (c.account_id = accounts.id OR c.account_id::TEXT = accounts.id::TEXT)
  );

-- ============================================================================
-- STEP 2: Fix the customer account creation function
-- ============================================================================

DROP TRIGGER IF EXISTS trg_customer_create_account ON customers;
DROP FUNCTION IF EXISTS public.create_customer_account();

CREATE OR REPLACE FUNCTION public.create_customer_account()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_next_code INTEGER;
  v_new_account_id INTEGER;
BEGIN
  -- Get next code: find max 11xxx customer account code and add 1
  SELECT COALESCE(MAX(account_code::int), 11000) + 1
  INTO v_next_code
  FROM accounts
  WHERE account_code ~ '^11[0-9]{3}$'
    AND company_id = NEW.company_id;

  -- Insert the account and get the new ID
  INSERT INTO accounts (account_code, name, account_name, account_type, sort_order, company_id, parent_id, level, is_leaf, allow_posting)
  VALUES (
    LPAD(v_next_code::TEXT, 5, '0'),
    'Customer - ' || COALESCE(NEW.name, ''),
    'عميل - ' || COALESCE(NEW.name, ''),
    'asset', 10,
    NEW.company_id,
    (SELECT id FROM accounts WHERE account_code = '1020' AND company_id = NEW.company_id LIMIT 1),
    4, true, true
  )
  RETURNING id INTO v_new_account_id;

  -- Link the account back to the customer
  UPDATE customers
  SET account_id = v_new_account_id
  WHERE id = NEW.id;

  RETURN NEW;
END;
$function$;

-- ============================================================================
-- STEP 3: Add DELETE trigger to remove customer accounts
-- ============================================================================

CREATE OR REPLACE FUNCTION public.delete_customer_account()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Delete the associated account if it exists
  IF OLD.account_id IS NOT NULL THEN
    DELETE FROM accounts WHERE id = OLD.account_id;
  END IF;
  
  -- Also try to find account by name pattern as fallback
  DELETE FROM accounts 
  WHERE account_code LIKE '111%'
    AND account_name ILIKE '%' || OLD.name || '%'
    AND company_id = OLD.company_id;
  
  RETURN OLD;
END;
$function$;

DROP TRIGGER IF EXISTS trg_customer_delete_account ON customers;

CREATE TRIGGER trg_customer_delete_account
AFTER DELETE ON customers
FOR EACH ROW
EXECUTE FUNCTION public.delete_customer_account();

-- ============================================================================
-- STEP 4: Add supplier account cleanup if needed
-- ============================================================================

-- Remove orphan supplier accounts
DELETE FROM accounts 
WHERE account_code LIKE '21%'
  AND account_name ILIKE '%مورد%'
  AND NOT EXISTS (
    SELECT 1 FROM suppliers s 
    WHERE s.deleted_at IS NULL
      AND (s.account_id = accounts.id OR s.account_id::TEXT = accounts.id::TEXT)
  );

-- Add DELETE trigger for suppliers
CREATE OR REPLACE FUNCTION public.delete_supplier_account()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- Delete the associated account if it exists
  IF OLD.account_id IS NOT NULL THEN
    DELETE FROM accounts WHERE id = OLD.account_id;
  END IF;
  
  -- Also try to find account by name pattern as fallback
  DELETE FROM accounts 
  WHERE account_code LIKE '21%'
    AND account_name ILIKE '%' || OLD.name || '%'
    AND company_id = OLD.company_id;
  
  RETURN OLD;
END;
$function$;

DROP TRIGGER IF EXISTS trg_supplier_delete_account ON suppliers;

CREATE TRIGGER trg_supplier_delete_account
AFTER DELETE ON suppliers
FOR EACH ROW
EXECUTE FUNCTION public.delete_supplier_account();

-- ============================================================================
-- STEP 5: Verification
-- ============================================================================

DO $$
DECLARE
  v_orphan_customers INT;
  v_orphan_suppliers INT;
BEGIN
  SELECT COUNT(*) INTO v_orphan_customers
  FROM accounts a
  WHERE a.account_code LIKE '111%'
    AND a.account_name ILIKE '%عميل%'
    AND NOT EXISTS (
      SELECT 1 FROM customers c 
      WHERE c.deleted_at IS NULL
        AND (c.account_id = a.id OR c.account_id::TEXT = a.id::TEXT)
    );
  
  SELECT COUNT(*) INTO v_orphan_suppliers
  FROM accounts a
  WHERE a.account_code LIKE '21%'
    AND a.account_name ILIKE '%مورد%'
    AND NOT EXISTS (
      SELECT 1 FROM suppliers s 
      WHERE s.deleted_at IS NULL
        AND (s.account_id = a.id OR s.account_id::TEXT = a.id::TEXT)
    );
  
  RAISE NOTICE 'Customer/Supplier Account Cleanup Summary:';
  RAISE NOTICE '  Orphan customer accounts: % (expected: 0)', v_orphan_customers;
  RAISE NOTICE '  Orphan supplier accounts: % (expected: 0)', v_orphan_suppliers;
  
  IF v_orphan_customers = 0 AND v_orphan_suppliers = 0 THEN
    RAISE NOTICE 'Account cleanup completed successfully';
  ELSE
    RAISE WARNING 'Some orphan accounts may remain - please review';
  END IF;
END $$;

COMMIT;