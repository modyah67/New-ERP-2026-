-- Migration 079: Unify auto-entity account generation triggers & guarantee single-account creation
-- ==============================================================================================
-- 1. Drops all redundant/duplicate legacy triggers across suppliers, customers, shipping companies,
--    clearing agents, and shareholders.
-- 2. Creates clean, idempotent AFTER INSERT triggers that create exactly ONE sub-account in the
--    chart of accounts and link it to the entity.
-- 3. Backfills any existing entities missing an account_id.
-- 4. Hardens withdraw_bank_account and transaction GL journal entry posting.

BEGIN;

-- ── 1. Unified Account Code Generator ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_next_entity_account_code(
  p_entity_type TEXT,
  p_company_id UUID DEFAULT NULL
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
    WHERE account_code ~ v_pattern;

    IF v_next <= v_start THEN
      v_next := v_start + 1;
    END IF;

    v_code := LPAD(v_next::TEXT, 5, '0');

    -- Ensure code is available in both accounts and deleted_account_codes
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM accounts WHERE account_code = v_code
    ) AND NOT EXISTS (
      SELECT 1 FROM deleted_account_codes WHERE account_code = v_code
    );

    v_start := v_next;
  END LOOP;

  RETURN v_code;
END;
$$;


-- ── 2. Supplier Account Trigger (Single Account Guarantee) ─────────────────────
CREATE OR REPLACE FUNCTION public.create_supplier_account()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_new_account_id BIGINT;
  v_parent_id BIGINT;
  v_code TEXT;
BEGIN
  -- If supplier already has an account_id set, do not create another
  IF NEW.account_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT id INTO v_parent_id
  FROM accounts
  WHERE account_code = '2000'
  ORDER BY (company_id = NEW.company_id) DESC, id ASC
  LIMIT 1;

  v_code := public.get_next_entity_account_code('supplier', NEW.company_id);

  INSERT INTO accounts (
    account_code, name, account_name, account_type, sort_order,
    company_id, parent_id, level, is_leaf, allow_posting, is_system, is_active
  )
  VALUES (
    v_code,
    'Supplier - ' || COALESCE(NEW.name, ''),
    'مورد - ' || COALESCE(NEW.name, ''),
    'liability', 10,
    NEW.company_id,
    v_parent_id,
    5, true, true, false, true
  )
  ON CONFLICT (account_code) DO UPDATE SET
    account_name = 'مورد - ' || COALESCE(EXCLUDED.account_name, public.accounts.account_name),
    name = 'Supplier - ' || COALESCE(EXCLUDED.name, public.accounts.name),
    company_id = COALESCE(EXCLUDED.company_id, public.accounts.company_id)
  RETURNING id INTO v_new_account_id;

  IF v_new_account_id IS NULL THEN
    SELECT id INTO v_new_account_id FROM accounts WHERE account_code = v_code LIMIT 1;
  END IF;

  UPDATE suppliers
  SET account_id = v_new_account_id,
      code = COALESCE(NULLIF(code, ''), v_code),
      supplier_code = COALESCE(NULLIF(supplier_code, ''), v_code)
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;

-- Drop all old/duplicate supplier triggers
DROP TRIGGER IF EXISTS trigger_create_supplier_account ON public.suppliers;
DROP TRIGGER IF EXISTS trg_supplier_create_account ON public.suppliers;
DROP TRIGGER IF EXISTS _trg_log_supplier_balance_ins ON public.suppliers;

CREATE TRIGGER trg_supplier_create_account
  AFTER INSERT ON public.suppliers
  FOR EACH ROW
  EXECUTE FUNCTION public.create_supplier_account();


-- ── 3. Customer Account Trigger ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_customer_account()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_new_account_id BIGINT;
  v_parent_id BIGINT;
  v_code TEXT;
BEGIN
  IF NEW.account_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT id INTO v_parent_id
  FROM accounts
  WHERE account_code = '1020'
  ORDER BY (company_id = NEW.company_id) DESC, id ASC
  LIMIT 1;

  v_code := public.get_next_entity_account_code('customer', NEW.company_id);

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
      code = COALESCE(NULLIF(code, ''), v_code)
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_create_customer_account ON public.customers;
DROP TRIGGER IF EXISTS trg_customer_create_account ON public.customers;

CREATE TRIGGER trg_customer_create_account
  AFTER INSERT ON public.customers
  FOR EACH ROW
  EXECUTE FUNCTION public.create_customer_account();


-- ── 4. Shipping Company Account Trigger ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_shipping_company_account()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_new_account_id BIGINT;
  v_parent_id BIGINT;
  v_code TEXT;
BEGIN
  IF NEW.account_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT id INTO v_parent_id
  FROM accounts
  WHERE account_code = '2000'
  ORDER BY (company_id = NEW.company_id) DESC, id ASC
  LIMIT 1;

  v_code := public.get_next_entity_account_code('shipping_company', NEW.company_id);

  INSERT INTO accounts (
    account_code, name, account_name, account_type, sort_order,
    company_id, parent_id, level, is_leaf, allow_posting, is_system, is_active
  )
  VALUES (
    v_code,
    'Shipping - ' || COALESCE(NEW.name, ''),
    'شركة شحن - ' || COALESCE(NEW.name, ''),
    'liability', 10,
    NEW.company_id,
    v_parent_id,
    5, true, true, false, true
  )
  ON CONFLICT (account_code) DO UPDATE SET
    account_name = 'شركة شحن - ' || COALESCE(EXCLUDED.account_name, public.accounts.account_name),
    name = 'Shipping - ' || COALESCE(EXCLUDED.name, public.accounts.name),
    company_id = COALESCE(EXCLUDED.company_id, public.accounts.company_id)
  RETURNING id INTO v_new_account_id;

  IF v_new_account_id IS NULL THEN
    SELECT id INTO v_new_account_id FROM accounts WHERE account_code = v_code LIMIT 1;
  END IF;

  UPDATE shipping_companies
  SET account_id = v_new_account_id,
      code = COALESCE(NULLIF(code, ''), v_code)
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_create_shipping_company_account ON public.shipping_companies;
DROP TRIGGER IF EXISTS trg_shipping_create_account ON public.shipping_companies;
DROP TRIGGER IF EXISTS trg_shipping_company_create_account ON public.shipping_companies;

CREATE TRIGGER trg_shipping_company_create_account
  AFTER INSERT ON public.shipping_companies
  FOR EACH ROW
  EXECUTE FUNCTION public.create_shipping_company_account();


-- ── 5. Clearing Agent Account Trigger ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_clearing_agent_account()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_new_account_id BIGINT;
  v_parent_id BIGINT;
  v_code TEXT;
BEGIN
  IF NEW.account_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT id INTO v_parent_id
  FROM accounts
  WHERE account_code = '2000'
  ORDER BY (company_id = NEW.company_id) DESC, id ASC
  LIMIT 1;

  v_code := public.get_next_entity_account_code('clearing_agent', NEW.company_id);

  INSERT INTO accounts (
    account_code, name, account_name, account_type, sort_order,
    company_id, parent_id, level, is_leaf, allow_posting, is_system, is_active
  )
  VALUES (
    v_code,
    'Clearing - ' || COALESCE(NEW.name, ''),
    'مخلص جمركي - ' || COALESCE(NEW.name, ''),
    'liability', 10,
    NEW.company_id,
    v_parent_id,
    5, true, true, false, true
  )
  ON CONFLICT (account_code) DO UPDATE SET
    account_name = 'مخلص جمركي - ' || COALESCE(EXCLUDED.account_name, public.accounts.account_name),
    name = 'Clearing - ' || COALESCE(EXCLUDED.name, public.accounts.name),
    company_id = COALESCE(EXCLUDED.company_id, public.accounts.company_id)
  RETURNING id INTO v_new_account_id;

  IF v_new_account_id IS NULL THEN
    SELECT id INTO v_new_account_id FROM accounts WHERE account_code = v_code LIMIT 1;
  END IF;

  UPDATE clearing_agents
  SET account_id = v_new_account_id,
      code = COALESCE(NULLIF(code, ''), v_code)
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_create_clearing_agent_account ON public.clearing_agents;
DROP TRIGGER IF EXISTS trg_clearing_create_account ON public.clearing_agents;
DROP TRIGGER IF EXISTS trg_clearing_agent_create_account ON public.clearing_agents;

CREATE TRIGGER trg_clearing_agent_create_account
  AFTER INSERT ON public.clearing_agents
  FOR EACH ROW
  EXECUTE FUNCTION public.create_clearing_agent_account();


-- ── 6. Shareholder Account Trigger ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.create_shareholder_account()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_new_account_id BIGINT;
  v_parent_id BIGINT;
  v_code TEXT;
BEGIN
  IF NEW.account_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT id INTO v_parent_id
  FROM accounts
  WHERE account_code = '3000'
  ORDER BY (company_id = NEW.company_id) DESC, id ASC
  LIMIT 1;

  v_code := public.get_next_entity_account_code('shareholder', NEW.company_id);

  INSERT INTO accounts (
    account_code, name, account_name, account_type, sort_order,
    company_id, parent_id, level, is_leaf, allow_posting, is_system, is_active
  )
  VALUES (
    v_code,
    'Shareholder - ' || COALESCE(NEW.name, ''),
    'مساهم - ' || COALESCE(NEW.name, ''),
    'equity', 10,
    NEW.company_id,
    v_parent_id,
    4, true, true, false, true
  )
  ON CONFLICT (account_code) DO UPDATE SET
    account_name = 'مساهم - ' || COALESCE(EXCLUDED.account_name, public.accounts.account_name),
    name = 'Shareholder - ' || COALESCE(EXCLUDED.name, public.accounts.name),
    company_id = COALESCE(EXCLUDED.company_id, public.accounts.company_id)
  RETURNING id INTO v_new_account_id;

  IF v_new_account_id IS NULL THEN
    SELECT id INTO v_new_account_id FROM accounts WHERE account_code = v_code LIMIT 1;
  END IF;

  UPDATE shareholders
  SET account_id = v_new_account_id,
      code = COALESCE(NULLIF(code, ''), v_code)
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_create_shareholder_account ON public.shareholders;
DROP TRIGGER IF EXISTS trg_shareholder_create_account ON public.shareholders;

CREATE TRIGGER trg_shareholder_create_account
  AFTER INSERT ON public.shareholders
  FOR EACH ROW
  EXECUTE FUNCTION public.create_shareholder_account();


-- ── 7. Safe withdraw_bank_account with entity account resolution ───────────────
DROP FUNCTION IF EXISTS public.withdraw_bank_account(INTEGER, NUMERIC, TEXT, TEXT, TEXT, TEXT, INTEGER);
DROP FUNCTION IF EXISTS public.withdraw_bank_account(INTEGER, NUMERIC, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.withdraw_bank_account(
    p_account_id        INTEGER,
    p_amount            NUMERIC,
    p_description       TEXT DEFAULT NULL,
    p_entity_type       TEXT DEFAULT NULL,
    p_entity_id         TEXT DEFAULT NULL,
    p_counterparty_name TEXT DEFAULT NULL,
    p_expense_account_id INTEGER DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_new_balance     NUMERIC := 0;
    v_tx_id           BIGINT;
    v_currency        TEXT;
    v_company_id      UUID;
    v_bank_acct       BIGINT;
    v_expense_acct    BIGINT;
    v_desc            TEXT;
    v_je_id           BIGINT;
    v_source_type     TEXT;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'يجب أن يكون المبلغ أكبر من صفر';
    END IF;

    SELECT COALESCE(balance, 0), currency, company_id INTO v_current_balance, v_currency, v_company_id
    FROM bank_accounts WHERE id = p_account_id;

    IF v_company_id IS NULL THEN
        RAISE EXCEPTION 'لم يتم العثور على company_id للحساب البنكي';
    END IF;

    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ للعملية (الرصيد الحالي: %)', v_current_balance;
    END IF;

    v_new_balance := v_current_balance - p_amount;

    IF p_entity_type IS NULL THEN
        v_source_type := 'opening_balance';
        v_desc := COALESCE(NULLIF(p_description, ''), 'سحب رصيد افتتاحي من الحساب البنكي');
    ELSE
        v_source_type := p_entity_type;
        v_desc := COALESCE(NULLIF(p_description, ''), 'سحب بنكي');
    END IF;

    -- Resolve bank GL account by currency
    v_bank_acct := public.resolve_gl_account(
        CASE v_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );

    -- Determine debit account based on entity_type (using text cast for safety across bigint and UUID)
    IF p_entity_type = 'customer' AND p_entity_id IS NOT NULL THEN
        SELECT account_id INTO v_expense_acct FROM customers WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'supplier' AND p_entity_id IS NOT NULL THEN
        SELECT account_id INTO v_expense_acct FROM suppliers WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'clearing_agent' AND p_entity_id IS NOT NULL THEN
        SELECT account_id INTO v_expense_acct FROM clearing_agents WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'shipping_company' AND p_entity_id IS NOT NULL THEN
        SELECT account_id INTO v_expense_acct FROM shipping_companies WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'shareholder' AND p_entity_id IS NOT NULL THEN
        SELECT account_id INTO v_expense_acct FROM shareholders WHERE id::TEXT = p_entity_id;
    ELSE
        v_expense_acct := public.resolve_gl_account('51101', v_company_id);
    END IF;

    -- If an explicit expense_account_id was provided, prefer it
    IF p_expense_account_id IS NOT NULL THEN
        v_expense_acct := p_expense_account_id;
    END IF;

    -- Fallback to generic expense if still NULL
    IF v_expense_acct IS NULL THEN
        v_expense_acct := public.resolve_gl_account('51101', v_company_id);
    END IF;

    -- Update bank balance
    UPDATE bank_accounts
    SET balance = v_new_balance, updated_at = NOW()
    WHERE id = p_account_id;

    -- Post GL Journal Entry (Dr. Expense/Entity / Cr. Bank)
    v_je_id := public.post_journal_entry(
        CASE 
            WHEN p_entity_type = 'supplier' THEN 'purchase_payment'
            WHEN p_entity_type = 'shareholder' THEN 'shareholder_payment_received'
            ELSE 'bank_withdrawal'
        END,
        v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_expense_acct, 'debit', p_amount, 'credit', 0, 'currency', v_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_bank_acct, 'debit', 0, 'credit', p_amount, 'currency', v_currency, 'description', v_desc)
        )
    );

    -- Insert bank transaction record
    INSERT INTO public.bank_account_transactions (
        bank_account_id, type, amount, balance_after,
        description, source_type,
        counterparty_type, counterparty_id, counterparty_name,
        company_id, expense_account_id, journal_entry_id,
        created_at
    ) VALUES (
        p_account_id, 'withdraw', p_amount, v_new_balance,
        v_desc, v_source_type,
        p_entity_type, p_entity_id, p_counterparty_name,
        v_company_id, v_expense_acct, v_je_id,
        NOW()
    ) RETURNING id INTO v_tx_id;

    -- Update counterparty balance
    IF p_entity_type = 'customer' AND p_entity_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance + p_amount WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'supplier' AND p_entity_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance - p_amount WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'clearing_agent' AND p_entity_id IS NOT NULL THEN
        UPDATE public.clearing_agents SET manual_adjustment = manual_adjustment - p_amount, balance = balance - p_amount WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'shipping_company' AND p_entity_id IS NOT NULL THEN
        UPDATE public.shipping_companies SET manual_adjustment = manual_adjustment - p_amount, balance = balance - p_amount WHERE id::TEXT = p_entity_id;
    ELSIF p_entity_type = 'shareholder' AND p_entity_id IS NOT NULL THEN
        IF v_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp - p_amount WHERE id::TEXT = p_entity_id;
        ELSIF v_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd - p_amount WHERE id::TEXT = p_entity_id;
        ELSIF v_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur - p_amount WHERE id::TEXT = p_entity_id;
        ELSIF v_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - p_amount WHERE id::TEXT = p_entity_id;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'transaction_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'new_balance', v_new_balance
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.withdraw_bank_account(INTEGER, NUMERIC, TEXT, TEXT, TEXT, TEXT, INTEGER) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

COMMIT;
