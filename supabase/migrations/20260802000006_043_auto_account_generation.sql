-- 043: Auto-account generation for Shipping Companies, Clearing Agents, Shareholders
-- Unified trigger-based approach matching existing Customer/Supplier pattern.

-- ============================================================================
-- 1. ADD account_id AND company_id COLUMNS
-- ============================================================================

ALTER TABLE shipping_companies
  ADD COLUMN IF NOT EXISTS account_id INTEGER REFERENCES accounts(id),
  ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES sys_companies(id);

ALTER TABLE clearing_agents
  ADD COLUMN IF NOT EXISTS account_id INTEGER REFERENCES accounts(id),
  ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES sys_companies(id);

ALTER TABLE shareholders
  ADD COLUMN IF NOT EXISTS account_id INTEGER REFERENCES accounts(id),
  ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES sys_companies(id);

CREATE INDEX IF NOT EXISTS idx_shipping_companies_account_id ON shipping_companies(account_id) WHERE account_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_clearing_agents_account_id ON clearing_agents(account_id) WHERE account_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_shareholders_account_id ON shareholders(account_id) WHERE account_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_shipping_companies_company_id ON shipping_companies(company_id);
CREATE INDEX IF NOT EXISTS idx_clearing_agents_company_id ON clearing_agents(company_id);
CREATE INDEX IF NOT EXISTS idx_shareholders_company_id ON shareholders(company_id);

-- ============================================================================
-- 2. HELPER: next account code per entity type
-- ============================================================================

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
BEGIN
  CASE p_entity_type
    WHEN 'shipping_company' THEN v_pattern := '^200[0-9]{2}$'; v_start := 20000;
    WHEN 'clearing_agent'   THEN v_pattern := '^201[0-9]{2}$'; v_start := 20100;
    WHEN 'shareholder'      THEN v_pattern := '^300[0-9]{2}$'; v_start := 30000;
    ELSE RAISE EXCEPTION 'Unknown entity type: %', p_entity_type;
  END CASE;

  SELECT COALESCE(MAX(account_code::int), v_start) + 1 INTO v_next
  FROM accounts
  WHERE account_code ~ v_pattern
    AND company_id = p_company_id;

  RETURN LPAD(v_next::TEXT, 5, '0');
END;
$$;

-- ============================================================================
-- 3. UNIFIED TRIGGER: create account after entity insert
-- ============================================================================

CREATE OR REPLACE FUNCTION public.create_entity_account()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_entity_type   TEXT;
  v_name_label    TEXT;
  v_name_ar_label TEXT;
  v_account_type  TEXT;
  v_parent_code   TEXT;
  v_next_code     TEXT;
  v_new_account_id INTEGER;
  v_parent_id     INTEGER;
  v_company_id    UUID;
BEGIN
  -- Determine entity type from table name
  CASE TG_TABLE_NAME
    WHEN 'shipping_companies' THEN
      v_entity_type   := 'shipping_company';
      v_name_label    := 'Shipping - ' || COALESCE(NEW.name, '');
      v_name_ar_label := 'شركة شحن - ' || COALESCE(NEW.name, '');
      v_account_type  := 'liability';
      v_parent_code   := '2000';
    WHEN 'clearing_agents' THEN
      v_entity_type   := 'clearing_agent';
      v_name_label    := 'Agent - ' || COALESCE(NEW.name, '');
      v_name_ar_label := 'مخلص جمركي - ' || COALESCE(NEW.name, '');
      v_account_type  := 'liability';
      v_parent_code   := '2000';
    WHEN 'shareholders' THEN
      v_entity_type   := 'shareholder';
      v_name_label    := 'Shareholder - ' || COALESCE(NEW.name, '');
      v_name_ar_label := 'مساهم - ' || COALESCE(NEW.name, '');
      v_account_type  := 'equity';
      v_parent_code   := '3000';
    ELSE
      RETURN NEW;
  END CASE;

  -- Skip if account already linked
  IF NEW.account_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- Get company_id from the new row
  v_company_id := NEW.company_id;

  -- If company_id is null, try to get from first company
  IF v_company_id IS NULL THEN
    SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
  END IF;

  IF v_company_id IS NULL THEN
    RAISE WARNING 'No company found for entity account creation';
    RETURN NEW;
  END IF;

  -- Get next code
  v_next_code := public.get_next_entity_account_code(v_entity_type, v_company_id);

  -- Get parent account
  SELECT id INTO v_parent_id
  FROM accounts
  WHERE account_code = v_parent_code
    AND company_id = v_company_id
  LIMIT 1;

  IF v_parent_id IS NULL THEN
    RAISE WARNING 'Parent account % not found for company %', v_parent_code, v_company_id;
    RETURN NEW;
  END IF;

  -- Create the account
  INSERT INTO accounts (
    account_code, name, account_name, account_type,
    sort_order, company_id, parent_id, level, is_leaf, allow_posting
  ) VALUES (
    v_next_code, v_name_label, v_name_ar_label, v_account_type,
    10, v_company_id, v_parent_id, 5, true, true
  )
  RETURNING id INTO v_new_account_id;

  -- Link back to entity (use dynamic SQL for column reference)
  IF NEW.company_id IS NULL THEN
    EXECUTE format(
      'UPDATE %I SET account_id = %s, company_id = %L WHERE id = %L',
      TG_TABLE_NAME, v_new_account_id, v_company_id, NEW.id
    );
  ELSE
    EXECUTE format(
      'UPDATE %I SET account_id = %s WHERE id = %L',
      TG_TABLE_NAME, v_new_account_id, NEW.id
    );
  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================================
-- 4. TRIGGER: delete account after entity delete
-- ============================================================================

CREATE OR REPLACE FUNCTION public.delete_entity_account()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF OLD.account_id IS NOT NULL THEN
    DELETE FROM accounts WHERE id = OLD.account_id;
  END IF;
  RETURN OLD;
END;
$$;

-- ============================================================================
-- 5. SAFE DELETE: check balance before allowing deletion
-- ============================================================================

CREATE OR REPLACE FUNCTION public.validate_entity_account_deletion(
  p_entity_type TEXT,
  p_entity_id   TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_account_id INTEGER;
  v_balance    NUMERIC;
  v_table_name TEXT;
BEGIN
  CASE p_entity_type
    WHEN 'shipping_company' THEN v_table_name := 'shipping_companies';
    WHEN 'clearing_agent'   THEN v_table_name := 'clearing_agents';
    WHEN 'shareholder'      THEN v_table_name := 'shareholders';
    ELSE RETURN jsonb_build_object('error', 'UNKNOWN_ENTITY_TYPE');
  END CASE;

  -- Get account_id
  EXECUTE format(
    'SELECT account_id FROM %I WHERE id::TEXT = %L',
    v_table_name, p_entity_id
  ) INTO v_account_id;

  IF v_account_id IS NULL THEN
    RETURN jsonb_build_object('success', true, 'message', 'No linked account');
  END IF;

  -- Check account balance
  SELECT balance INTO v_balance FROM accounts WHERE id = v_account_id;

  IF v_balance IS NOT NULL AND v_balance != 0 THEN
    RETURN jsonb_build_object(
      'error', 'HAS_BALANCE',
      'message', 'Cannot delete: account balance is ' || v_balance::TEXT
    );
  END IF;

  -- Check for ledger entries
  IF EXISTS (
    SELECT 1 FROM account_ledger_entries WHERE account_id = v_account_id
  ) THEN
    RETURN jsonb_build_object(
      'error', 'HAS_ENTRIES',
      'message', 'Cannot delete: account has ledger entries'
    );
  END IF;

  -- Delete entity (cascades to account via trigger)
  EXECUTE format(
    'DELETE FROM %I WHERE id::TEXT = %L',
    v_table_name, p_entity_id
  );

  RETURN jsonb_build_object('success', true);
END;
$$;

-- ============================================================================
-- 6. BIND TRIGGERS
-- ============================================================================

-- Shipping Companies
DROP TRIGGER IF EXISTS trg_shipping_create_account ON shipping_companies;
CREATE TRIGGER trg_shipping_create_account
  AFTER INSERT ON shipping_companies
  FOR EACH ROW
  WHEN (NEW.account_id IS NULL)
  EXECUTE FUNCTION public.create_entity_account();

DROP TRIGGER IF EXISTS trg_shipping_delete_account ON shipping_companies;
CREATE TRIGGER trg_shipping_delete_account
  AFTER DELETE ON shipping_companies
  FOR EACH ROW
  EXECUTE FUNCTION public.delete_entity_account();

-- Clearing Agents
DROP TRIGGER IF EXISTS trg_clearing_create_account ON clearing_agents;
CREATE TRIGGER trg_clearing_create_account
  AFTER INSERT ON clearing_agents
  FOR EACH ROW
  WHEN (NEW.account_id IS NULL)
  EXECUTE FUNCTION public.create_entity_account();

DROP TRIGGER IF EXISTS trg_clearing_delete_account ON clearing_agents;
CREATE TRIGGER trg_clearing_delete_account
  AFTER DELETE ON clearing_agents
  FOR EACH ROW
  EXECUTE FUNCTION public.delete_entity_account();

-- Shareholders
DROP TRIGGER IF EXISTS trg_shareholder_create_account ON shareholders;
CREATE TRIGGER trg_shareholder_create_account
  AFTER INSERT ON shareholders
  FOR EACH ROW
  WHEN (NEW.account_id IS NULL)
  EXECUTE FUNCTION public.create_entity_account();

DROP TRIGGER IF EXISTS trg_shareholder_delete_account ON shareholders;
CREATE TRIGGER trg_shareholder_delete_account
  AFTER DELETE ON shareholders
  FOR EACH ROW
  EXECUTE FUNCTION public.delete_entity_account();

-- ============================================================================
-- 7. MIGRATE EXISTING ENTITIES (create accounts for rows without account_id)
-- ============================================================================

-- Shipping Companies
DO $$
DECLARE
  r RECORD;
  v_next_code TEXT;
  v_parent_id INTEGER;
  v_new_id    INTEGER;
  v_company   UUID;
BEGIN
  FOR r IN SELECT sc.id, sc.name
           FROM shipping_companies sc
           WHERE sc.account_id IS NULL
  LOOP
    -- Get company_id (from row or default)
    SELECT COALESCE(
      (SELECT company_id FROM shipping_companies WHERE id = r.id),
      (SELECT id FROM sys_companies LIMIT 1)
    ) INTO v_company;

    IF v_company IS NULL THEN CONTINUE; END IF;

    v_next_code := public.get_next_entity_account_code('shipping_company', v_company);

    SELECT id INTO v_parent_id
    FROM accounts WHERE account_code = '2000' AND company_id = v_company LIMIT 1;

    IF v_parent_id IS NOT NULL THEN
      INSERT INTO accounts (account_code, name, account_name, account_type, sort_order, company_id, parent_id, level, is_leaf, allow_posting)
      VALUES (v_next_code, 'Shipping - ' || r.name, 'شركة شحن - ' || r.name, 'liability', 10, v_company, v_parent_id, 5, true, true)
      RETURNING id INTO v_new_id;

      UPDATE shipping_companies SET account_id = v_new_id, company_id = v_company WHERE id = r.id;
    END IF;
  END LOOP;
END $$;

-- Clearing Agents
DO $$
DECLARE
  r RECORD;
  v_next_code TEXT;
  v_parent_id INTEGER;
  v_new_id    INTEGER;
  v_company   UUID;
BEGIN
  FOR r IN SELECT ca.id, ca.name
           FROM clearing_agents ca
           WHERE ca.account_id IS NULL
  LOOP
    SELECT COALESCE(
      (SELECT company_id FROM clearing_agents WHERE id = r.id),
      (SELECT id FROM sys_companies LIMIT 1)
    ) INTO v_company;

    IF v_company IS NULL THEN CONTINUE; END IF;

    v_next_code := public.get_next_entity_account_code('clearing_agent', v_company);

    SELECT id INTO v_parent_id
    FROM accounts WHERE account_code = '2000' AND company_id = v_company LIMIT 1;

    IF v_parent_id IS NOT NULL THEN
      INSERT INTO accounts (account_code, name, account_name, account_type, sort_order, company_id, parent_id, level, is_leaf, allow_posting)
      VALUES (v_next_code, 'Agent - ' || r.name, 'مخلص جمركي - ' || r.name, 'liability', 10, v_company, v_parent_id, 5, true, true)
      RETURNING id INTO v_new_id;

      UPDATE clearing_agents SET account_id = v_new_id, company_id = v_company WHERE id = r.id;
    END IF;
  END LOOP;
END $$;

-- Shareholders
DO $$
DECLARE
  r RECORD;
  v_next_code TEXT;
  v_parent_id INTEGER;
  v_new_id    INTEGER;
  v_company   UUID;
BEGIN
  FOR r IN SELECT sh.id, sh.name
           FROM shareholders sh
           WHERE sh.account_id IS NULL
  LOOP
    SELECT COALESCE(
      (SELECT company_id FROM shareholders WHERE id = r.id),
      (SELECT id FROM sys_companies LIMIT 1)
    ) INTO v_company;

    IF v_company IS NULL THEN CONTINUE; END IF;

    v_next_code := public.get_next_entity_account_code('shareholder', v_company);

    SELECT id INTO v_parent_id
    FROM accounts WHERE account_code = '3000' AND company_id = v_company LIMIT 1;

    IF v_parent_id IS NOT NULL THEN
      INSERT INTO accounts (account_code, name, account_name, account_type, sort_order, company_id, parent_id, level, is_leaf, allow_posting)
      VALUES (v_next_code, 'Shareholder - ' || r.name, 'مساهم - ' || r.name, 'equity', 10, v_company, v_parent_id, 5, true, true)
      RETURNING id INTO v_new_id;

      UPDATE shareholders SET account_id = v_new_id, company_id = v_company WHERE id = r.id;
    END IF;
  END LOOP;
END $$;
