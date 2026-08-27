-- Migration 059: Fix get_next_entity_account_code to support supplier/customer
-- and skip deleted codes

CREATE OR REPLACE FUNCTION public.get_next_entity_account_code(
  p_entity_type TEXT,
  p_company_id UUID
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_pattern TEXT;
  v_start   INTEGER;
  v_next    INTEGER;
  v_code    TEXT;
BEGIN
  CASE p_entity_type
    WHEN 'customer'         THEN v_pattern := '^11[0-9]{3}$'; v_start := 11000;
    WHEN 'supplier'         THEN v_pattern := '^21[0-9]{3}$'; v_start := 21000;
    WHEN 'shipping_company' THEN v_pattern := '^200[0-9]{2}$'; v_start := 20000;
    WHEN 'clearing_agent'   THEN v_pattern := '^201[0-9]{2}$'; v_start := 20100;
    WHEN 'shareholder'      THEN v_pattern := '^300[0-9]{2}$'; v_start := 30000;
    ELSE RAISE EXCEPTION 'Unknown entity type: %', p_entity_type;
  END CASE;

  LOOP
    SELECT COALESCE(MAX(account_code::int), v_start) + 1 INTO v_next
    FROM accounts
    WHERE account_code ~ v_pattern
      AND company_id = p_company_id;

    v_code := LPAD(v_next::TEXT, 5, '0');

    -- Skip codes that were previously deleted
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM deleted_account_codes WHERE account_code = v_code
    );

    v_start := v_next;
  END LOOP;

  RETURN v_code;
END;
$$;

-- Fix create_supplier_account to use the centralized code generator
-- (old version did MAX+1 without checking deleted_account_codes)
CREATE OR REPLACE FUNCTION create_supplier_account()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_new_account_id INTEGER;
  v_parent_id INTEGER;
  v_code TEXT;
BEGIN
  SELECT id INTO v_parent_id
  FROM accounts
  WHERE account_code = '2000'
    AND company_id = NEW.company_id
  LIMIT 1;

  v_code := public.get_next_entity_account_code('supplier', NEW.company_id);

  INSERT INTO accounts (account_code, name, account_name, account_type, sort_order, company_id, parent_id, level, is_leaf, allow_posting)
  VALUES (
    v_code,
    'Supplier - ' || COALESCE(NEW.name, ''),
    'مورد - ' || COALESCE(NEW.name, ''),
    'liability', 10,
    NEW.company_id,
    v_parent_id,
    5, true, true
  )
  RETURNING id INTO v_new_account_id;

  UPDATE suppliers
  SET account_id = v_new_account_id
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;

-- Fix create_customer_account to use the centralized code generator
CREATE OR REPLACE FUNCTION create_customer_account()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_new_account_id INTEGER;
  v_code TEXT;
BEGIN
  v_code := public.get_next_entity_account_code('customer', NEW.company_id);

  INSERT INTO accounts (account_code, name, account_name, account_type, sort_order, company_id, parent_id, level, is_leaf, allow_posting)
  VALUES (
    v_code,
    'Customer - ' || COALESCE(NEW.name, ''),
    'عميل - ' || COALESCE(NEW.name, ''),
    'asset', 10,
    NEW.company_id,
    (SELECT id FROM accounts WHERE account_code = '1020' AND company_id = NEW.company_id LIMIT 1),
    4, true, true
  )
  RETURNING id INTO v_new_account_id;

  UPDATE customers
  SET account_id = v_new_account_id
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;
