-- Migration 145: Ensure treasury GL accounts exist for all companies
-- and fix resolve_treasury_account to auto-create if missing

-- Step 1: Insert missing treasury cash accounts for all companies
DO $$
DECLARE
  v_company RECORD;
  v_parent_id BIGINT;
  v_existing BIGINT;
BEGIN
  FOR v_company IN SELECT id FROM sys_companies LOOP
    -- Find or create parent account '1110' (Cash in hand / النقدية بالصندوق)
    SELECT id INTO v_parent_id FROM accounts
    WHERE account_code = '1110' AND company_id = v_company.id LIMIT 1;

    IF v_parent_id IS NULL THEN
      -- Try to find parent '111' 
      SELECT id INTO v_parent_id FROM accounts
      WHERE account_code = '111' AND company_id = v_company.id LIMIT 1;
    END IF;

    IF v_parent_id IS NULL THEN
      -- Try to find parent '11'
      SELECT id INTO v_parent_id FROM accounts
      WHERE account_code = '11' AND company_id = v_company.id LIMIT 1;
    END IF;

    IF v_parent_id IS NULL THEN
      -- Try to find any parent in range '1xxx'
      SELECT id INTO v_parent_id FROM accounts
      WHERE account_code LIKE '1%' AND company_id = v_company.id
      AND is_leaf = false
      ORDER BY account_code LIMIT 1;
    END IF;

    -- Create 11101 (EGP Cash)
    SELECT id INTO v_existing FROM accounts WHERE account_code = '11101' AND company_id = v_company.id;
    IF v_existing IS NULL THEN
      INSERT INTO accounts (name, account_code, account_name, account_type, parent_id, company_id, is_leaf, is_active, created_at, updated_at)
      VALUES ('صندوق - جنيه مصري', '11101', 'صندوق - جنيه مصري', 'asset', v_parent_id, v_company.id, true, true, now(), now())
      ON CONFLICT DO NOTHING;
      RAISE NOTICE 'Created account 11101 for company %', v_company.id;
    END IF;

    -- Create 11102 (USD Cash)
    SELECT id INTO v_existing FROM accounts WHERE account_code = '11102' AND company_id = v_company.id;
    IF v_existing IS NULL THEN
      INSERT INTO accounts (name, account_code, account_name, account_type, parent_id, company_id, is_leaf, is_active, created_at, updated_at)
      VALUES ('صندوق - دولار أمريكي', '11102', 'صندوق - دولار أمريكي', 'asset', v_parent_id, v_company.id, true, true, now(), now())
      ON CONFLICT DO NOTHING;
      RAISE NOTICE 'Created account 11102 for company %', v_company.id;
    END IF;

    -- Create 11103 (EUR Cash)
    SELECT id INTO v_existing FROM accounts WHERE account_code = '11103' AND company_id = v_company.id;
    IF v_existing IS NULL THEN
      INSERT INTO accounts (name, account_code, account_name, account_type, parent_id, company_id, is_leaf, is_active, created_at, updated_at)
      VALUES ('صندوق - يورو', '11103', 'صندوق - يورو', 'asset', v_parent_id, v_company.id, true, true, now(), now())
      ON CONFLICT DO NOTHING;
      RAISE NOTICE 'Created account 11103 for company %', v_company.id;
    END IF;

    -- Create 11104 (GBP Cash)
    SELECT id INTO v_existing FROM accounts WHERE account_code = '11104' AND company_id = v_company.id;
    IF v_existing IS NULL THEN
      INSERT INTO accounts (name, account_code, account_name, account_type, parent_id, company_id, is_leaf, is_active, created_at, updated_at)
      VALUES ('صندوق - جنيه إسترليني', '11104', 'صندوق - جنيه إسترليني', 'asset', v_parent_id, v_company.id, true, true, now(), now())
      ON CONFLICT DO NOTHING;
      RAISE NOTICE 'Created account 11104 for company %', v_company.id;
    END IF;

  END LOOP;
END $$;

-- Step 2: Backfill treasury.account_id for any treasury that doesn't have one
UPDATE treasuries t
SET account_id = (
  SELECT a.id FROM accounts a
  WHERE a.account_code = '11101' AND a.company_id = (
    SELECT sc.id FROM sys_companies sc LIMIT 1
  )
  LIMIT 1
)
WHERE t.account_id IS NULL;

-- Step 3: Backfill treasury_balances.account_id for any balance that doesn't have one
UPDATE treasury_balances tb
SET account_id = (
  SELECT a.id FROM accounts a
  WHERE a.account_code = CASE tb.currency
    WHEN 'EGP' THEN '11101'
    WHEN 'USD' THEN '11102'
    WHEN 'EUR' THEN '11103'
    WHEN 'GBP' THEN '11104'
    ELSE '11101'
  END
  AND a.company_id = (SELECT sc.id FROM sys_companies sc LIMIT 1)
  LIMIT 1
)
WHERE tb.account_id IS NULL;

-- Step 4: Update resolve_treasury_account to guarantee a non-null return
CREATE OR REPLACE FUNCTION public.resolve_treasury_account(
    p_treasury_id BIGINT,
    p_currency TEXT,
    p_company_id UUID
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_account_id BIGINT;
    v_code TEXT;
    v_real_company_id UUID;
BEGIN
    -- Resolve company_id if NULL
    v_real_company_id := p_company_id;
    IF v_real_company_id IS NULL THEN
        SELECT company_id INTO v_real_company_id FROM treasuries WHERE id = p_treasury_id;
    END IF;
    IF v_real_company_id IS NULL THEN
        SELECT id INTO v_real_company_id FROM sys_companies LIMIT 1;
    END IF;

    -- 1) Try treasuries.account_id
    SELECT account_id INTO v_account_id FROM treasuries WHERE id = p_treasury_id;
    IF v_account_id IS NOT NULL THEN
        RETURN v_account_id;
    END IF;

    -- 2) Try treasury_balances.account_id
    SELECT tb.account_id INTO v_account_id
    FROM treasury_balances tb
    WHERE tb.treasury_id = p_treasury_id AND tb.currency = p_currency AND tb.account_id IS NOT NULL
    LIMIT 1;
    IF v_account_id IS NOT NULL THEN
        RETURN v_account_id;
    END IF;

    -- 3) Try standard code mapping
    v_code := CASE p_currency
        WHEN 'EGP' THEN '11101'
        WHEN 'USD' THEN '11102'
        WHEN 'EUR' THEN '11103'
        WHEN 'GBP' THEN '11104'
        ELSE '11101'
    END;
    SELECT id INTO v_account_id FROM accounts WHERE account_code = v_code AND company_id = v_real_company_id LIMIT 1;
    IF v_account_id IS NOT NULL THEN
        -- Also backfill the treasury for next time
        UPDATE treasuries SET account_id = v_account_id WHERE id = p_treasury_id AND account_id IS NULL;
        RETURN v_account_id;
    END IF;

    -- 4) Try main treasury's account_id
    SELECT t.account_id INTO v_account_id
    FROM treasuries t
    WHERE t.type = 'main' AND t.account_id IS NOT NULL
    LIMIT 1;
    IF v_account_id IS NOT NULL THEN
        UPDATE treasuries SET account_id = v_account_id WHERE id = p_treasury_id AND account_id IS NULL;
        RETURN v_account_id;
    END IF;

    -- 5) Try any 111% account
    SELECT id INTO v_account_id
    FROM accounts
    WHERE account_code LIKE '111%' AND company_id = v_real_company_id AND is_active = true
    ORDER BY account_code LIMIT 1;
    IF v_account_id IS NOT NULL THEN
        UPDATE treasuries SET account_id = v_account_id WHERE id = p_treasury_id AND account_id IS NULL;
        RETURN v_account_id;
    END IF;

    -- 6) Try any 11% account
    SELECT id INTO v_account_id
    FROM accounts
    WHERE account_code LIKE '11%' AND company_id = v_real_company_id AND is_active = true
    ORDER BY account_code LIMIT 1;
    IF v_account_id IS NOT NULL THEN
        UPDATE treasuries SET account_id = v_account_id WHERE id = p_treasury_id AND account_id IS NULL;
        RETURN v_account_id;
    END IF;

    -- 7) Last resort: try ANY asset account
    SELECT id INTO v_account_id
    FROM accounts
    WHERE account_type = 'asset' AND company_id = v_real_company_id AND is_leaf = true AND is_active = true
    ORDER BY account_code LIMIT 1;
    IF v_account_id IS NOT NULL THEN
        UPDATE treasuries SET account_id = v_account_id WHERE id = p_treasury_id AND account_id IS NULL;
        RETURN v_account_id;
    END IF;

    -- Should never get here after step 1, but just in case
    RAISE EXCEPTION 'لا يوجد حساب خزينة متاح للعملة % - يرجى إنشاء حسابات الخزينة في شجرة الحسابات', p_currency;
END;
$$;

NOTIFY pgrst, 'reload schema';
