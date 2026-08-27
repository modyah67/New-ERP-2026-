-- Migration 311: Isolate Crop Payments (CPAY) and Separate from Regular Purchase Payments (PPAY)
-- 1. Register 'crop_payment' document type with dedicated prefix 'CPAY' in sys_document_types.
-- 2. Update spend_custody and withdraw_bank_account to generate 'crop_payment' (CPAY) when paying crop invoices.
-- 3. Update rpc_get_lot_journal_entries to ONLY query 'lot_receipt', 'lot_price_adjustment', and 'crop_payment'.
-- 4. Update rpc_get_purchase_journal_entries to strictly query purchase-specific source types.

BEGIN;

-- ============================================================================
-- 1. Register Document Types and Prefixes
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.sys_document_types (
    code TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    prefix TEXT NOT NULL,
    description TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

INSERT INTO public.sys_document_types (code, name, prefix, is_active)
VALUES 
  ('crop_payment',     'Crop Purchase Payment / سداد مشتريات محاصيل', 'CPAY', true),
  ('supplier_payment', 'Supplier Advance / دفعة مقدمة لمورد',         'PMT',  true),
  ('purchase_payment', 'Purchase Payment / سداد مشتريات خامات',       'PPAY', true)
ON CONFLICT (code) DO UPDATE SET 
  prefix = EXCLUDED.prefix,
  name = EXCLUDED.name,
  is_active = true;

-- ============================================================================
-- 2. Update spend_custody
-- ============================================================================
CREATE OR REPLACE FUNCTION public.spend_custody(
    p_treasury_id          BIGINT,
    p_currency             TEXT,
    p_amount               NUMERIC,
    p_description          TEXT DEFAULT '',
    p_customer_id          INTEGER DEFAULT NULL,
    p_supplier_id          UUID DEFAULT NULL,
    p_clearing_agent_id    BIGINT DEFAULT NULL,
    p_shipping_company_id  BIGINT DEFAULT NULL,
    p_shareholder_id       UUID DEFAULT NULL,
    p_expense_account_id   INTEGER DEFAULT NULL,
    p_reference_type       TEXT DEFAULT NULL,
    p_reference_id         TEXT DEFAULT NULL,
    p_notes                TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_current_balance NUMERIC;
    v_new_balance     NUMERIC;
    v_tx_id           BIGINT;
    v_company_id      UUID;
    v_treasury_acct   BIGINT;
    v_expense_acct    BIGINT;
    v_je_id           BIGINT;
    v_desc            TEXT;
    v_tx_type         TEXT;
    v_je_source_type  TEXT;
    v_entity_leaf     INTEGER;
BEGIN
    -- Resolve GL account
    IF p_expense_account_id IS NOT NULL THEN
        SELECT id INTO v_expense_acct FROM accounts 
        WHERE id = p_expense_account_id AND is_leaf = true AND is_active = true AND account_type = 'expense';
        IF v_expense_acct IS NULL THEN
            RAISE EXCEPTION 'الحساب المحدد غير صالح — يجب أن يكون حساب مصروفات ورقي ونشط';
        END IF;
        v_tx_type := 'expense';

    ELSIF p_supplier_id IS NOT NULL THEN
        SELECT s.account_id INTO v_entity_leaf
        FROM suppliers s WHERE s.id = p_supplier_id;
        IF v_entity_leaf IS NULL THEN
            RAISE EXCEPTION 'المورد لا يمتلك حساب في شجرة الحسابات';
        END IF;
        SELECT id INTO v_expense_acct FROM accounts
        WHERE id = v_entity_leaf AND is_leaf = true AND is_active = true;
        IF v_expense_acct IS NULL THEN
            RAISE EXCEPTION 'حساب المورد غير موجود أو غير نشط في شجرة الحسابات';
        END IF;
        v_tx_type := 'supplier_payment';

    ELSIF p_customer_id IS NOT NULL THEN
        SELECT c.account_id INTO v_entity_leaf
        FROM customers c WHERE c.id = p_customer_id;
        IF v_entity_leaf IS NULL THEN
            RAISE EXCEPTION 'العميل لا يمتلك حساب في شجرة الحسابات';
        END IF;
        SELECT id INTO v_expense_acct FROM accounts
        WHERE id = v_entity_leaf AND is_leaf = true AND is_active = true;
        IF v_expense_acct IS NULL THEN
            RAISE EXCEPTION 'حساب العميل غير موجود أو غير نشط في شجرة الحسابات';
        END IF;
        v_tx_type := 'customer_payment';

    ELSIF p_clearing_agent_id IS NOT NULL THEN
        SELECT ca.account_id INTO v_entity_leaf
        FROM clearing_agents ca WHERE ca.id = p_clearing_agent_id;
        IF v_entity_leaf IS NULL THEN
            RAISE EXCEPTION 'المخلص لا يمتلك حساب في شجرة الحسابات';
        END IF;
        SELECT id INTO v_expense_acct FROM accounts
        WHERE id = v_entity_leaf AND is_leaf = true AND is_active = true;
        IF v_expense_acct IS NULL THEN
            RAISE EXCEPTION 'حساب المخلص غير موجود أو غير نشط في شجرة الحسابات';
        END IF;
        v_tx_type := 'clearing_agent_payment';

    ELSIF p_shipping_company_id IS NOT NULL THEN
        SELECT sc.account_id INTO v_entity_leaf
        FROM shipping_companies sc WHERE sc.id = p_shipping_company_id;
        IF v_entity_leaf IS NULL THEN
            RAISE EXCEPTION 'شركة الشحن لا تمتلك حساب في شجرة الحسابات';
        END IF;
        SELECT id INTO v_expense_acct FROM accounts
        WHERE id = v_entity_leaf AND is_leaf = true AND is_active = true;
        IF v_expense_acct IS NULL THEN
            RAISE EXCEPTION 'حساب شركة الشحن غير موجود أو غير نشط في شجرة الحسابات';
        END IF;
        v_tx_type := 'shipping_company_payment';

    ELSIF p_shareholder_id IS NOT NULL THEN
        v_tx_type := 'shareholder_withdrawal';
        SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;
        SELECT account_id INTO v_expense_acct FROM public.shareholders WHERE id = p_shareholder_id;
        IF v_expense_acct IS NOT NULL THEN
            SELECT id INTO v_expense_acct FROM public.accounts WHERE id = v_expense_acct AND is_leaf = true AND is_active = true;
        END IF;
        IF v_expense_acct IS NULL THEN
            v_expense_acct := public.resolve_equity_account(p_currency, v_company_id);
        END IF;

    ELSE
        RAISE EXCEPTION 'يجب اختيار حساب مصروفات من شجرة الحسابات أو تحديد جهة للصرف';
    END IF;

    SELECT balance INTO v_current_balance
    FROM public.treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    IF v_current_balance IS NULL OR v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ في % (المتوفر: %)', p_currency, COALESCE(v_current_balance, 0);
    END IF;

    v_new_balance := v_current_balance - p_amount;

    UPDATE public.treasury_balances
    SET balance = v_new_balance, updated_at = NOW()
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    IF v_company_id IS NULL THEN
        SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_treasury_id;
    END IF;

    v_desc := COALESCE(NULLIF(p_description, ''), 'صرف خزينة');

    INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description,
        expense_account_id,
        customer_id, supplier_id, clearing_agent_id, shipping_company_id, shareholder_id,
        balance_before, balance_after,
        reference_type, reference_id,
        created_by, notes
    ) VALUES (
        p_treasury_id, v_tx_type, p_amount, p_currency, v_desc,
        p_expense_account_id,
        p_customer_id, p_supplier_id, p_clearing_agent_id, p_shipping_company_id, p_shareholder_id,
        v_current_balance, v_new_balance,
        p_reference_type, p_reference_id,
        auth.uid(), p_notes
    ) RETURNING id INTO v_tx_id;

    -- Update Counterparty balances and ledger entries
    IF p_customer_id IS NOT NULL THEN
        UPDATE public.customers SET balance = balance + p_amount WHERE id = p_customer_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('customer', p_customer_id::TEXT, 'debit', p_amount, p_currency, v_tx_type, v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_supplier_id IS NOT NULL THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance - p_amount WHERE id = p_supplier_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('supplier', p_supplier_id::TEXT, 'credit', p_amount, p_currency, v_tx_type, v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_clearing_agent_id IS NOT NULL THEN
        UPDATE public.clearing_agents SET balance = balance - p_amount WHERE id = p_clearing_agent_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('clearing_agent', p_clearing_agent_id::TEXT, 'debit', p_amount, p_currency, v_tx_type, v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_shipping_company_id IS NOT NULL THEN
        UPDATE public.shipping_companies SET balance = balance - p_amount WHERE id = p_shipping_company_id;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('shipping_company', p_shipping_company_id::TEXT, 'debit', p_amount, p_currency, v_tx_type, v_tx_id, v_desc, auth.uid());
    END IF;
    IF p_shareholder_id IS NOT NULL THEN
        IF p_currency = 'EGP' THEN UPDATE public.shareholders SET current_balance_egp = current_balance_egp - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'USD' THEN UPDATE public.shareholders SET current_balance_usd = current_balance_usd - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'EUR' THEN UPDATE public.shareholders SET current_balance_eur = current_balance_eur - p_amount WHERE id = p_shareholder_id;
        ELSIF p_currency = 'GBP' THEN UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - p_amount WHERE id = p_shareholder_id;
        END IF;
        INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('shareholder', p_shareholder_id::TEXT, 'debit', p_amount, p_currency, v_tx_type, v_tx_id, v_desc, auth.uid());
    END IF;

    -- Update Purchase Invoice or Lot Receipt if reference provided
    IF p_reference_type = 'purchase_invoice' AND p_reference_id IS NOT NULL THEN
        UPDATE public.purchase_invoices
        SET paid_amount = COALESCE(paid_amount, 0) + p_amount,
            remaining_amount = GREATEST(0, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - (COALESCE(paid_amount, 0) + p_amount)),
            payment_status = CASE
                WHEN GREATEST(0, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - (COALESCE(paid_amount, 0) + p_amount)) <= 0.001 THEN 'paid'
                ELSE 'partial'
            END,
            updated_at = NOW()
        WHERE id::TEXT = p_reference_id OR invoice_number = p_reference_id;
    ELSIF (p_reference_type = 'lot_receipt' OR p_reference_type = 'crop_purchase') AND p_reference_id IS NOT NULL THEN
        UPDATE public.lot_receipts
        SET paid_amount = COALESCE(paid_amount, 0) + p_amount,
            updated_at = NOW()
        WHERE id::TEXT = p_reference_id OR lot_number = p_reference_id;
    END IF;

    v_treasury_acct := public.resolve_treasury_account(p_treasury_id, p_currency, v_company_id);

    -- Distinct Journal Entry source_type resolution
    v_je_source_type := CASE v_tx_type
        WHEN 'supplier_payment' THEN
            CASE
                WHEN p_reference_type IN ('lot_receipt', 'crop_purchase') THEN 'crop_payment'
                WHEN p_reference_type = 'purchase_invoice' THEN 'purchase_payment'
                ELSE 'supplier_payment'
            END
        WHEN 'customer_payment' THEN 'customer_refund'
        WHEN 'clearing_agent_payment' THEN 'clearing_agent_payment'
        WHEN 'shipping_company_payment' THEN 'shipping_company_payment'
        WHEN 'shareholder_withdrawal' THEN 'shareholder_withdrawal'
        ELSE 'expense_payment'
    END;

    -- Journal entry: Dr. Entity/Expense / Cr. Treasury
    v_je_id := public.post_journal_entry(
        v_je_source_type,
        v_desc, CURRENT_DATE, v_company_id, auth.uid(),
        jsonb_build_array(
            jsonb_build_object('account_id', v_expense_acct, 'debit', p_amount, 'credit', 0, 'currency', p_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_treasury_acct, 'debit', 0, 'credit', p_amount, 'currency', p_currency, 'description', v_desc)
        ),
        p_reference_id
    );

    -- Link journal entry to treasury transaction
    UPDATE public.treasury_transactions SET journal_entry_id = v_je_id WHERE id = v_tx_id;

    RETURN v_tx_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.spend_custody(BIGINT, TEXT, NUMERIC, TEXT, INTEGER, UUID, BIGINT, BIGINT, UUID, INTEGER, TEXT, TEXT, TEXT) TO authenticated, service_role;

-- ============================================================================
-- 3. Update withdraw_bank_account
-- ============================================================================
CREATE OR REPLACE FUNCTION public.withdraw_bank_account(
    p_account_id        INTEGER,
    p_amount            NUMERIC,
    p_description       TEXT DEFAULT NULL,
    p_entity_type       TEXT DEFAULT NULL,
    p_entity_id         TEXT DEFAULT NULL,
    p_counterparty_name TEXT DEFAULT NULL,
    p_expense_account_id INTEGER DEFAULT NULL,
    p_notes             TEXT DEFAULT NULL,
    p_reference_type    TEXT DEFAULT NULL,
    p_reference_id      TEXT DEFAULT NULL
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
    v_je_source_type  TEXT;
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

    v_bank_acct := public.resolve_gl_account(
        CASE v_currency WHEN 'EGP' THEN '11201' WHEN 'USD' THEN '11202' WHEN 'EUR' THEN '11203' WHEN 'GBP' THEN '11204' ELSE '11201' END,
        v_company_id
    );

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

    IF p_expense_account_id IS NOT NULL THEN
        v_expense_acct := p_expense_account_id;
    END IF;

    IF v_expense_acct IS NULL THEN
        v_expense_acct := public.resolve_gl_account('51101', v_company_id);
    END IF;

    UPDATE bank_accounts
    SET balance = v_new_balance, updated_at = NOW()
    WHERE id = p_account_id;

    -- Update Purchase Invoice or Lot Receipt if reference provided
    IF p_reference_type = 'purchase_invoice' AND p_reference_id IS NOT NULL THEN
        UPDATE public.purchase_invoices
        SET paid_amount = COALESCE(paid_amount, 0) + p_amount,
            remaining_amount = GREATEST(0, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - (COALESCE(paid_amount, 0) + p_amount)),
            payment_status = CASE
                WHEN GREATEST(0, (COALESCE(total_amount, 0) - COALESCE(discount_amount, 0)) - (COALESCE(paid_amount, 0) + p_amount)) <= 0.001 THEN 'paid'
                ELSE 'partial'
            END,
            updated_at = NOW()
        WHERE id::TEXT = p_reference_id OR invoice_number = p_reference_id;
    ELSIF (p_reference_type = 'lot_receipt' OR p_reference_type = 'crop_purchase') AND p_reference_id IS NOT NULL THEN
        UPDATE public.lot_receipts
        SET paid_amount = COALESCE(paid_amount, 0) + p_amount,
            updated_at = NOW()
        WHERE id::TEXT = p_reference_id OR lot_number = p_reference_id;
    END IF;

    -- Distinct Journal Entry source_type resolution
    v_je_source_type := CASE
        WHEN p_entity_type = 'supplier' THEN
            CASE
                WHEN p_reference_type IN ('lot_receipt', 'crop_purchase') THEN 'crop_payment'
                WHEN p_reference_type = 'purchase_invoice' THEN 'purchase_payment'
                ELSE 'supplier_payment'
            END
        WHEN p_entity_type = 'shareholder' THEN 'shareholder_payment_received'
        ELSE 'bank_withdrawal'
    END;

    v_je_id := public.post_journal_entry(
        p_source_type := v_je_source_type,
        p_description := v_desc,
        p_entry_date := CURRENT_DATE,
        p_company_id := v_company_id,
        p_created_by := auth.uid(),
        p_lines := jsonb_build_array(
            jsonb_build_object('account_id', v_expense_acct, 'debit', p_amount, 'credit', 0, 'currency', v_currency, 'description', v_desc),
            jsonb_build_object('account_id', v_bank_acct, 'debit', 0, 'credit', p_amount, 'currency', v_currency, 'description', v_desc)
        ),
        p_source_id := p_reference_id
    );

    INSERT INTO public.bank_account_transactions (
        bank_account_id, type, amount, balance_before, balance_after,
        description, entity_type, entity_id, counterparty_name,
        source_type, journal_entry_id, created_at, created_by, notes
    ) VALUES (
        p_account_id, 'withdraw', p_amount, v_current_balance, v_new_balance,
        v_desc, p_entity_type, p_entity_id, p_counterparty_name,
        v_source_type, v_je_id, NOW(), auth.uid(), p_notes
    ) RETURNING id INTO v_tx_id;

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
        'transaction_id', v_tx_id,
        'journal_entry_id', v_je_id,
        'balance', v_new_balance
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.withdraw_bank_account(INTEGER, NUMERIC, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT) TO authenticated, service_role;

-- ============================================================================
-- 4. Update rpc_get_lot_journal_entries (Strict Crop Isolation)
-- ============================================================================
DROP FUNCTION IF EXISTS public.rpc_get_lot_journal_entries(TEXT);

CREATE OR REPLACE FUNCTION public.rpc_get_lot_journal_entries(
  p_lot_id TEXT
)
RETURNS TABLE (
  journal_entry_id BIGINT,
  entry_number     TEXT,
  entry_date       DATE,
  description      TEXT,
  source_type      TEXT,
  source_id        TEXT,
  total_debit      NUMERIC,
  total_credit     NUMERIC,
  currency         TEXT,
  created_at       TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lot_number TEXT;
BEGIN
  SELECT lot_number INTO v_lot_number
  FROM lot_receipts WHERE id::TEXT = p_lot_id;

  RETURN QUERY
  SELECT DISTINCT ON (je.id)
    je.id AS journal_entry_id,
    je.entry_number,
    je.entry_date,
    je.description,
    je.source_type,
    je.source_id,
    COALESCE(SUM(ale.debit) OVER (PARTITION BY je.id), 0) AS total_debit,
    COALESCE(SUM(ale.credit) OVER (PARTITION BY je.id), 0) AS total_credit,
    (SELECT ale2.currency FROM public.account_ledger_entries ale2
     WHERE ale2.journal_entry_id = je.id AND ale2.currency IS NOT NULL
     ORDER BY ale2.id LIMIT 1) AS currency,
    je.created_at
  FROM public.journal_entries je
  INNER JOIN public.account_ledger_entries ale ON ale.journal_entry_id = je.id
  WHERE je.deleted_at IS NULL
    AND ale.deleted_at IS NULL
    AND (
      -- 1. lot_receipt entries (inventory)
      (je.source_id = p_lot_id AND je.source_type = 'lot_receipt')
      OR
      -- 2. lot_price_adjustment entries
      (je.source_id = p_lot_id AND je.source_type = 'lot_price_adjustment')
      OR
      -- 3. Explicit Crop Payment entries ONLY (source_type = 'crop_payment' and explicit relation)
      (je.source_type = 'crop_payment' AND (je.source_id = p_lot_id OR (v_lot_number IS NOT NULL AND v_lot_number != '' AND je.source_id = v_lot_number)))
    )
  ORDER BY je.id, je.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_lot_journal_entries(TEXT) TO authenticated;

-- ============================================================================
-- 5. Update rpc_get_purchase_journal_entries (Strict Purchase Isolation)
-- ============================================================================
DROP FUNCTION IF EXISTS public.rpc_get_purchase_journal_entries(TEXT);

CREATE OR REPLACE FUNCTION public.rpc_get_purchase_journal_entries(
  p_purchase_id TEXT
)
RETURNS TABLE (
  journal_entry_id BIGINT,
  entry_number     TEXT,
  entry_date       DATE,
  description      TEXT,
  source_type      TEXT,
  source_id        TEXT,
  total_debit      NUMERIC,
  total_credit     NUMERIC,
  currency         TEXT,
  created_at       TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invoice_number TEXT;
BEGIN
  -- Get the invoice number to match entries
  SELECT invoice_number INTO v_invoice_number
  FROM purchase_invoices WHERE id::TEXT = p_purchase_id;

  RETURN QUERY
  SELECT DISTINCT ON (je.id)
    je.id AS journal_entry_id,
    je.entry_number,
    je.entry_date,
    je.description,
    je.source_type,
    je.source_id,
    COALESCE(SUM(ale.debit) OVER (PARTITION BY je.id), 0) AS total_debit,
    COALESCE(SUM(ale.credit) OVER (PARTITION BY je.id), 0) AS total_credit,
    (SELECT ale2.currency FROM public.account_ledger_entries ale2
     WHERE ale2.journal_entry_id = je.id AND ale2.currency IS NOT NULL
     ORDER BY ale2.id LIMIT 1) AS currency,
    je.created_at
  FROM public.journal_entries je
  INNER JOIN public.account_ledger_entries ale ON ale.journal_entry_id = je.id
  WHERE je.deleted_at IS NULL
    AND ale.deleted_at IS NULL
    AND (
      -- 1. Match by source_id for purchase_inventory, purchase_payment, purchase_price_adjustment
      (je.source_id = p_purchase_id AND je.source_type IN ('purchase_inventory', 'purchase_payment', 'purchase_price_adjustment'))
      OR
      -- 2. Match by description containing invoice number for entries created without source_id
      (v_invoice_number IS NOT NULL AND v_invoice_number != ''
       AND je.description LIKE '%' || v_invoice_number || '%'
       AND je.source_type IN ('purchase_inventory', 'purchase_payment'))
    )
  ORDER BY je.id, je.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_get_purchase_journal_entries(TEXT) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
