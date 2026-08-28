-- Migration 424: Fix timezone offset in shipment costing journal entries (admin expenses, taxes, cost items)
-- Ensuring all journal entries use Cairo local date (UTC+3) instead of server UTC CURRENT_DATE.

-- 1. Update rpc_save_shipment_admin_expenses
DROP FUNCTION IF EXISTS public.rpc_save_shipment_admin_expenses(INTEGER, NUMERIC, UUID);
DROP FUNCTION IF EXISTS public.rpc_save_shipment_taxes(INTEGER, NUMERIC, UUID);

CREATE OR REPLACE FUNCTION public.rpc_save_shipment_admin_expenses(
    p_shipment_id BIGINT,
    p_allocated_admin_expenses NUMERIC,
    p_user_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_shipment RECORD;
    v_has_distribution BOOLEAN;
    v_company_id UUID;
    v_admin_exp_account_id BIGINT;
    v_provision_account_id BIGINT;
    v_je_id BIGINT;
    v_entry_num TEXT;
    v_entry_date DATE;
    v_amount NUMERIC := COALESCE(p_allocated_admin_expenses, 0.00);
BEGIN
    -- ── A. Check Profit Distribution Lock ──
    SELECT EXISTS (
        SELECT 1 FROM public.shareholder_profit_distributions
        WHERE shipment_id = p_shipment_id AND deleted_at IS NULL
    ) INTO v_has_distribution;

    IF v_has_distribution THEN
        RAISE EXCEPTION 'تم توزيع أرباح هذه الشحنة على المساهمين - لا يمكن تعديل التكاليف أو المصروفات الإدارية';
    END IF;

    -- ── B. Fetch Shipment ──
    SELECT * INTO v_shipment FROM public.export_shipments WHERE id = p_shipment_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'الشحنة غير موجودة');
    END IF;

    -- ── Calculate Safe Local Entry Date (Cairo UTC+3) ──
    v_entry_date := COALESCE(
        v_shipment.shipment_date,
        (v_shipment.created_at AT TIME ZONE 'Africa/Cairo')::DATE,
        (NOW() AT TIME ZONE 'Africa/Cairo')::DATE
    );

    -- ── C. Update Export Shipment Record ──
    UPDATE public.export_shipments
    SET allocated_admin_expenses = v_amount,
        net_profit_egp = COALESCE(total_revenue_egp, 0) - COALESCE(total_landed_cost, 0) - v_amount - COALESCE(allocated_taxes, 0),
        net_profit = COALESCE(total_revenue_egp, 0) - COALESCE(total_landed_cost, 0) - v_amount - COALESCE(allocated_taxes, 0)
    WHERE id = p_shipment_id;

    -- ── D. Resolve Accounts ──
    SELECT company_id INTO v_company_id FROM public.accounts WHERE account_code = '5210' LIMIT 1;
    IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1; END IF;

    -- 5210: Allocated Admin Expenses (مصروفات إدارية محملة)
    SELECT id INTO v_admin_exp_account_id FROM public.accounts WHERE account_code = '5210' LIMIT 1;
    IF v_admin_exp_account_id IS NULL THEN
        SELECT id INTO v_admin_exp_account_id FROM public.accounts WHERE account_code = '6002' LIMIT 1;
    END IF;
    IF v_admin_exp_account_id IS NULL THEN
        SELECT id INTO v_admin_exp_account_id FROM public.accounts WHERE account_code = '6000' LIMIT 1;
    END IF;
    IF v_admin_exp_account_id IS NULL THEN
        SELECT id INTO v_admin_exp_account_id FROM public.accounts WHERE account_type = 'expense' LIMIT 1;
    END IF;

    -- 2105: Admin Expenses Provision (مخصص / وسيط مصروفات إدارية)
    SELECT id INTO v_provision_account_id FROM public.accounts WHERE account_code = '2105' LIMIT 1;
    IF v_provision_account_id IS NULL THEN
        SELECT id INTO v_provision_account_id FROM public.accounts WHERE account_code = '2100' LIMIT 1;
    END IF;
    IF v_provision_account_id IS NULL THEN
        SELECT id INTO v_provision_account_id FROM public.accounts WHERE account_type = 'liability' LIMIT 1;
    END IF;

    -- ── E. Manage GL Journal Entry ──
    SELECT id INTO v_je_id
    FROM public.journal_entries
    WHERE source_type = 'shipment_admin_expenses' AND source_id = p_shipment_id::text AND deleted_at IS NULL
    LIMIT 1;

    IF v_amount > 0 THEN
        IF v_je_id IS NOT NULL THEN
            UPDATE public.journal_entries
            SET description = 'مصروفات إدارية محملة على شحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                entry_date = v_entry_date,
                updated_at = now()
            WHERE id = v_je_id;

            DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id;

            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_je_id, v_admin_exp_account_id, v_amount, 0, 'EGP', v_amount,
                'تحميل مصروفات إدارية على شحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                v_company_id
            );

            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_je_id, v_provision_account_id, 0, v_amount, 'EGP', v_amount,
                'مخصص مصروفات إدارية لشحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                v_company_id
            );
        ELSE
            INSERT INTO public.journal_entries (
                entry_number, entry_date, description, status,
                is_auto_generated, source_type, source_id, company_id,
                created_by, created_at, updated_at
            ) VALUES (
                'PENDING',
                v_entry_date,
                'مصروفات إدارية محملة على شحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                'posted', true, 'shipment_admin_expenses', p_shipment_id::text, v_company_id,
                COALESCE(p_user_id, auth.uid()), now(), now()
            ) RETURNING id INTO v_je_id;

            v_entry_num := public.fn_get_next_sequence(v_company_id, 'shipment_admin_expenses', NULL, NULL);
            IF v_entry_num IS NULL OR v_entry_num = '' THEN
                v_entry_num := 'ADM-' || LPAD(v_je_id::text, 5, '0');
            END IF;
            UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_je_id, v_admin_exp_account_id, v_amount, 0, 'EGP', v_amount,
                'تحميل مصروفات إدارية على شحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                v_company_id
            );

            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_je_id, v_provision_account_id, 0, v_amount, 'EGP', v_amount,
                'مخصص مصروفات إدارية لشحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                v_company_id
            );
        END IF;
    ELSE
        IF v_je_id IS NOT NULL THEN
            UPDATE public.journal_entries SET deleted_at = now() WHERE id = v_je_id;
            DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'shipment_id', p_shipment_id,
        'allocated_admin_expenses', v_amount,
        'journal_entry_id', v_je_id
    );
END;
$$;

-- 2. Update rpc_save_shipment_taxes
CREATE OR REPLACE FUNCTION public.rpc_save_shipment_taxes(
    p_shipment_id BIGINT,
    p_allocated_taxes NUMERIC,
    p_user_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_shipment RECORD;
    v_has_distribution BOOLEAN;
    v_company_id UUID;
    v_tax_debit_acc BIGINT;
    v_tax_credit_acc BIGINT;
    v_je_id BIGINT;
    v_entry_num TEXT;
    v_entry_date DATE;
    v_amount NUMERIC := COALESCE(p_allocated_taxes, 0.00);
BEGIN
    -- A. Check Profit Distribution Lock
    SELECT EXISTS (
        SELECT 1 FROM public.shareholder_profit_distributions
        WHERE shipment_id = p_shipment_id AND deleted_at IS NULL
    ) INTO v_has_distribution;

    IF v_has_distribution THEN
        RAISE EXCEPTION 'تم توزيع أرباح هذه الشحنة على المساهمين - لا يمكن تعديل التكاليف أو الضرائب';
    END IF;

    -- B. Fetch Shipment
    SELECT * INTO v_shipment FROM public.export_shipments WHERE id = p_shipment_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'الشحنة غير موجودة');
    END IF;

    -- ── Calculate Safe Local Entry Date (Cairo UTC+3) ──
    v_entry_date := COALESCE(
        v_shipment.shipment_date,
        (v_shipment.created_at AT TIME ZONE 'Africa/Cairo')::DATE,
        (NOW() AT TIME ZONE 'Africa/Cairo')::DATE
    );

    -- C. Update Export Shipment Record
    UPDATE public.export_shipments
    SET allocated_taxes = v_amount,
        net_profit_egp = COALESCE(total_revenue_egp, 0) - COALESCE(total_landed_cost, 0) - COALESCE(allocated_admin_expenses, 0) - v_amount,
        net_profit = COALESCE(total_revenue_egp, 0) - COALESCE(total_landed_cost, 0) - COALESCE(allocated_admin_expenses, 0) - v_amount
    WHERE id = p_shipment_id;

    -- D. Resolve Accounts
    SELECT company_id INTO v_company_id FROM public.accounts WHERE account_code = '2102' LIMIT 1;
    IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1; END IF;

    SELECT id INTO v_tax_debit_acc FROM public.accounts WHERE account_code = '2102' LIMIT 1;
    IF v_tax_debit_acc IS NULL THEN
        SELECT id INTO v_tax_debit_acc FROM public.accounts WHERE account_code = '2100' LIMIT 1;
    END IF;

    SELECT id INTO v_tax_credit_acc FROM public.accounts WHERE account_code = '2101' LIMIT 1;
    IF v_tax_credit_acc IS NULL THEN
        SELECT id INTO v_tax_credit_acc FROM public.accounts WHERE account_code = '2100' LIMIT 1;
    END IF;

    -- E. Manage GL Journal Entry
    SELECT id INTO v_je_id
    FROM public.journal_entries
    WHERE source_type = 'shipment_taxes' AND source_id = p_shipment_id::text AND deleted_at IS NULL
    LIMIT 1;

    IF v_amount > 0 THEN
        IF v_je_id IS NOT NULL THEN
            UPDATE public.journal_entries
            SET description = 'ضرائب محملة على شحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                entry_date = v_entry_date,
                updated_at = now()
            WHERE id = v_je_id;

            DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id;

            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_je_id, v_tax_debit_acc, v_amount, 0, 'EGP', v_amount,
                'تحميل ضرائب على شحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                v_company_id
            );

            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_je_id, v_tax_credit_acc, 0, v_amount, 'EGP', v_amount,
                'وسيط ضرائب لشحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                v_company_id
            );
        ELSE
            INSERT INTO public.journal_entries (
                entry_number, entry_date, description, status,
                is_auto_generated, source_type, source_id, company_id,
                created_by, created_at, updated_at
            ) VALUES (
                'PENDING',
                v_entry_date,
                'ضرائب محملة على شحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                'posted', true, 'shipment_taxes', p_shipment_id::text, v_company_id,
                COALESCE(p_user_id, auth.uid()), now(), now()
            ) RETURNING id INTO v_je_id;

            v_entry_num := public.fn_get_next_sequence(v_company_id, 'shipment_taxes', NULL, NULL);
            IF v_entry_num IS NULL OR v_entry_num = '' THEN
                v_entry_num := 'TAX-' || LPAD(v_je_id::text, 5, '0');
            END IF;
            UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_je_id, v_tax_debit_acc, v_amount, 0, 'EGP', v_amount,
                'تحميل ضرائب على شحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                v_company_id
            );

            INSERT INTO public.account_ledger_entries (
                journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
            ) VALUES (
                v_je_id, v_tax_credit_acc, 0, v_amount, 'EGP', v_amount,
                'وسيط ضرائب لشحنة رقم ' || COALESCE(v_shipment.shipment_no, p_shipment_id::text),
                v_company_id
            );
        END IF;
    ELSE
        IF v_je_id IS NOT NULL THEN
            UPDATE public.journal_entries SET deleted_at = now() WHERE id = v_je_id;
            DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_je_id;
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'shipment_id', p_shipment_id,
        'allocated_taxes', v_amount,
        'journal_entry_id', v_je_id
    );
END;
$$;

-- 3. Update rpc_pay_shipment_cost_item (ensure Cairo date is used for payment search)
CREATE OR REPLACE FUNCTION public.rpc_pay_shipment_cost_item(
  p_cost_item_id        BIGINT,
  p_source_type         TEXT,
  p_source_id           BIGINT,
  p_expense_account_id  BIGINT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  r_item           RECORD;
  v_supplier_id    UUID;
  v_amount         NUMERIC;
  v_currency       TEXT;
  v_current_bal    NUMERIC;
  v_treasury_tx_id BIGINT;
  v_bank_tx_id     INTEGER;
  v_tx_desc        TEXT;
  v_je_id          BIGINT;
  v_company_id     UUID;
  v_bank_res       JSONB;
  v_liability_acct INTEGER;
BEGIN
  SELECT * INTO r_item
  FROM public.shipment_cost_items
  WHERE id = p_cost_item_id;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'بند التكلفة غير موجود');
  END IF;

  IF r_item.treasury_transaction_id IS NOT NULL OR r_item.bank_transaction_id IS NOT NULL THEN
    RETURN json_build_object('success', false, 'error', 'هذا البند مدفوع مسبقاً');
  END IF;

  IF p_source_type NOT IN ('treasury', 'bank') THEN
    RETURN json_build_object('success', false, 'error', 'نوع مصدر الدفع غير صحيح: ' || p_source_type);
  END IF;

  v_currency := COALESCE(NULLIF(r_item.original_currency, ''), 'EGP');
  
  IF v_currency != 'EGP' AND COALESCE(r_item.exchange_rate, 1.0) > 0 THEN
    v_amount := ROUND(COALESCE(NULLIF(r_item.total_price, 0), r_item.quantity * r_item.unit_price, 0) / r_item.exchange_rate, 2);
  ELSE
    v_amount := COALESCE(NULLIF(r_item.total_price, 0), r_item.quantity * r_item.unit_price, 0);
  END IF;

  v_tx_desc  := 'سداد بند تكلفة شحنة: ' || COALESCE(r_item.description, 'غير محدد')
                 || ' (بند ' || p_cost_item_id::text || ')';

  IF v_amount <= 0 THEN
    RETURN json_build_object('success', false, 'error', 'مبلغ البند يجب أن يكون أكبر من صفر');
  END IF;

  v_liability_acct := NULL;
  v_supplier_id := NULL;
  IF p_expense_account_id IS NOT NULL THEN
    v_liability_acct := p_expense_account_id;
  ELSIF r_item.shipping_company_id IS NOT NULL THEN
    SELECT sc.account_id INTO v_liability_acct FROM public.shipping_companies sc WHERE sc.id = r_item.shipping_company_id;
  ELSIF r_item.clearing_agent_id IS NOT NULL THEN
    SELECT ca.account_id INTO v_liability_acct FROM public.clearing_agents ca WHERE ca.id = r_item.clearing_agent_id;
  ELSIF r_item.supplier_id IS NOT NULL AND r_item.supplier_id != '' THEN
    BEGIN
      v_supplier_id := r_item.supplier_id::uuid;
      SELECT s.account_id INTO v_liability_acct FROM public.suppliers s WHERE s.id = v_supplier_id;
    EXCEPTION WHEN OTHERS THEN
      v_supplier_id := NULL;
      v_liability_acct := NULL;
    END;
  ELSIF r_item.vendor_type = 'shipping_company' AND r_item.vendor_id IS NOT NULL THEN
    SELECT sc.account_id INTO v_liability_acct FROM public.shipping_companies sc WHERE sc.id = r_item.vendor_id;
  ELSIF r_item.vendor_type = 'clearing_agent' AND r_item.vendor_id IS NOT NULL THEN
    SELECT ca.account_id INTO v_liability_acct FROM public.clearing_agents ca WHERE ca.id = r_item.vendor_id;
  ELSIF r_item.vendor_type = 'supplier' AND r_item.vendor_id IS NOT NULL THEN
    BEGIN
      v_supplier_id := r_item.vendor_id::text::uuid;
      SELECT s.account_id INTO v_liability_acct FROM public.suppliers s WHERE s.id = v_supplier_id;
    EXCEPTION WHEN OTHERS THEN
      v_supplier_id := NULL;
      v_liability_acct := NULL;
    END;
  END IF;

  IF v_liability_acct IS NULL THEN
    SELECT a.id INTO v_liability_acct FROM public.accounts a
    WHERE a.account_code = '2300' AND a.is_leaf = true AND a.is_active = true LIMIT 1;
  END IF;

  IF p_source_type = 'treasury' THEN
    SELECT t.company_id INTO v_company_id FROM treasuries t WHERE t.id = p_source_id;
  ELSE
    SELECT ba.company_id INTO v_company_id FROM bank_accounts ba WHERE ba.id = p_source_id::integer;
  END IF;

  IF v_company_id IS NULL THEN
    SELECT id INTO v_company_id FROM sys_companies ORDER BY created_at ASC LIMIT 1;
  END IF;

  IF p_source_type = 'treasury' THEN
    SELECT balance INTO v_current_bal
    FROM public.treasury_balances
    WHERE treasury_id = p_source_id AND currency = v_currency
    FOR UPDATE;

    IF v_current_bal IS NULL OR v_current_bal < v_amount THEN
      RAISE EXCEPTION 'الرصيد غير كافٍ في الخزينة (المتوفر: %, المطلوب: %)',
        COALESCE(v_current_bal, 0), v_amount;
    END IF;

    PERFORM public.spend_custody(
      p_source_id, v_currency, v_amount, v_tx_desc,
      NULL, v_supplier_id, NULL, r_item.clearing_agent_id, r_item.shipping_company_id,
      v_liability_acct
    );

    SELECT id INTO v_treasury_tx_id
    FROM public.treasury_transactions
    WHERE treasury_id = p_source_id
      AND type = 'expense' AND amount = v_amount AND currency = v_currency
    ORDER BY created_at DESC LIMIT 1;

    SELECT je.id INTO v_je_id
    FROM public.journal_entries je
    WHERE je.source_type IN ('expense_payment', 'purchase_payment')
      AND je.company_id IS NOT DISTINCT FROM v_company_id
      AND je.entry_date = (NOW() AT TIME ZONE 'Africa/Cairo')::DATE
    ORDER BY je.id DESC LIMIT 1;

    UPDATE public.shipment_cost_items
    SET treasury_transaction_id = v_treasury_tx_id,
        payment_source_type     = 'treasury',
        payment_source_id       = p_source_id,
        payment_status          = 'paid',
        paid_amount             = v_amount,
        journal_entry_id        = v_je_id
    WHERE id = p_cost_item_id;

    RETURN json_build_object('success', true, 'tx_id', v_treasury_tx_id, 'type', 'treasury', 'journal_entry_id', v_je_id);

  ELSIF p_source_type = 'bank' THEN
    SELECT balance INTO v_current_bal
    FROM public.bank_accounts
    WHERE id = p_source_id::integer
    FOR UPDATE;

    IF v_current_bal IS NULL OR v_current_bal < v_amount THEN
      RAISE EXCEPTION 'الرصيد غير كافٍ في الحساب البنكي (المتوفر: %, المطلوب: %)',
        COALESCE(v_current_bal, 0), v_amount;
    END IF;

    v_bank_res := public.withdraw_bank_account(
      p_source_id::integer, v_amount, v_tx_desc,
      CASE 
        WHEN v_supplier_id IS NOT NULL THEN 'supplier' 
        WHEN r_item.shipping_company_id IS NOT NULL THEN 'shipping_company'
        WHEN r_item.clearing_agent_id IS NOT NULL THEN 'clearing_agent'
        ELSE NULL 
      END,
      CASE 
        WHEN v_supplier_id IS NOT NULL THEN v_supplier_id::text 
        WHEN r_item.shipping_company_id IS NOT NULL THEN r_item.shipping_company_id::text
        WHEN r_item.clearing_agent_id IS NOT NULL THEN r_item.clearing_agent_id::text
        ELSE NULL 
      END,
      NULL,
      v_liability_acct
    );

    v_bank_tx_id := (v_bank_res ->> 'transaction_id')::integer;
    v_je_id      := (v_bank_res ->> 'journal_entry_id')::bigint;

    UPDATE public.shipment_cost_items
    SET bank_transaction_id     = v_bank_tx_id,
        payment_source_type     = 'bank',
        payment_source_id       = p_source_id,
        payment_status          = 'paid',
        paid_amount             = v_amount,
        journal_entry_id        = v_je_id
    WHERE id = p_cost_item_id;

    RETURN json_build_object('success', true, 'tx_id', v_bank_tx_id, 'type', 'bank', 'journal_entry_id', v_je_id);
  END IF;

  RETURN json_build_object('success', false, 'error', 'خطأ داخلي غير متوقع');
END;
$$;

-- 4. Update rpc_apply_packing_order_item_debit_note (use Cairo date)
CREATE OR REPLACE FUNCTION public.rpc_apply_packing_order_item_debit_note(
    p_order_id BIGINT,
    p_item_type TEXT,
    p_item_id BIGINT,
    p_batch_id BIGINT,
    p_discount_amount NUMERIC,
    p_reason TEXT,
    p_user_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_order RECORD;
    v_company_id UUID;
    v_supplier_uuid UUID;
    v_supplier_currency TEXT;
    v_source_account_id BIGINT;
    v_dest_account_id BIGINT;
    v_dest_account_code TEXT;
    v_exchange_rate NUMERIC;
    v_foreign_discount NUMERIC;
    v_je_id BIGINT;
    v_entry_num TEXT;
    v_item_name TEXT;
    v_target_desc TEXT;
    v_target_line_id BIGINT;
    v_has_shipped_items BOOLEAN;
    v_old_total_pkg_cost NUMERIC := 0;
    v_new_total_pkg_cost NUMERIC := 0;
    v_carton_count NUMERIC := 0;
    v_new_cost_per_carton NUMERIC := 0;
    v_line RECORD;
    r_ship RECORD;
BEGIN
    IF p_discount_amount IS NULL OR p_discount_amount <= 0 THEN
        RAISE EXCEPTION 'مبلغ الخصم يجب أن يكون أكبر من الصفر';
    END IF;

    SELECT * INTO v_order FROM public.packing_orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'أمر التعبئة رقم % غير موجود', p_order_id;
    END IF;

    SELECT company_id INTO v_company_id FROM public.sys_companies LIMIT 1;

    SELECT EXISTS (
        SELECT 1 FROM public.export_shipment_items WHERE packing_order_id = p_order_id
    ) INTO v_has_shipped_items;

    IF v_has_shipped_items THEN
        v_dest_account_code := '5000';
        v_target_desc := 'تخفيض تكلفة بضاعة مباعة عن أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text);
    ELSE
        v_dest_account_code := '1031';
        v_target_desc := 'تخفيض مخزون إنتاج تام عن أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text);
    END IF;

    IF p_item_type = 'material' THEN
        SELECT spb.supplier_id, p.name INTO v_supplier_uuid, v_item_name
        FROM public.station_product_batches spb
        JOIN public.products p ON p.id = spb.product_id
        WHERE spb.id = p_batch_id;

        IF v_item_name IS NULL THEN
            SELECT p.name INTO v_item_name
            FROM public.packing_order_materials pom
            JOIN public.products p ON p.id = pom.material_id
            WHERE pom.id = p_item_id;
        END IF;

        UPDATE public.packing_order_materials
        SET unit_cost = GREATEST(0, (COALESCE(unit_cost, 0) * COALESCE(quantity_used, 1) - p_discount_amount) / GREATEST(COALESCE(quantity_used, 1), 0.0001))
        WHERE id = p_item_id;

    ELSIF p_item_type = 'crop' THEN
        IF p_item_id > 0 THEN
            SELECT pol.source_lot_id, pol.id, COALESCE(pol.carton_count, 0)
            INTO v_target_desc, v_target_line_id, v_carton_count
            FROM public.packing_order_lines pol
            WHERE pol.id = p_item_id;

            IF v_target_desc IS NOT NULL AND v_target_desc != '' THEN
                SELECT lr.supplier_id, 'محصول لوط ' || COALESCE(lr.lot_number, v_target_desc)
                INTO v_supplier_uuid, v_item_name
                FROM public.lot_receipts lr
                WHERE lr.id::text = v_target_desc;
            END IF;

            UPDATE public.packing_order_lines
            SET final_cost = GREATEST(0, COALESCE(final_cost, 0) - p_discount_amount),
                cost_per_carton = CASE WHEN COALESCE(carton_count, 0) > 0 THEN GREATEST(0, COALESCE(final_cost, 0) - p_discount_amount) / carton_count ELSE 0 END
            WHERE id = p_item_id;
        ELSE
            SELECT lr.supplier_id, 'محصول لوط ' || COALESCE(lr.lot_number, v_order.lot_id::text)
            INTO v_supplier_uuid, v_item_name
            FROM public.lot_receipts lr
            WHERE lr.id::text = v_order.lot_id::text;
        END IF;
    END IF;

    IF v_supplier_uuid IS NOT NULL THEN
        SELECT account_id, COALESCE(currency, 'EGP')
        INTO v_source_account_id, v_supplier_currency
        FROM public.suppliers WHERE id = v_supplier_uuid;

        IF v_source_account_id IS NULL THEN
            v_source_account_id := public.resolve_gl_account('2000', v_company_id);
        END IF;
    ELSE
        v_supplier_currency := 'EGP';
        v_source_account_id := public.resolve_gl_account('3901', v_company_id);
        IF v_source_account_id IS NULL THEN
            v_source_account_id := public.resolve_gl_account('3900', v_company_id);
        END IF;
        IF v_source_account_id IS NULL THEN
            v_source_account_id := public.resolve_gl_account('3000', v_company_id);
        END IF;
    END IF;

    IF p_batch_id > 0 AND p_item_type = 'material' THEN
        SELECT COALESCE(exchange_rate, 1.0)
        INTO v_exchange_rate
        FROM public.station_product_batches
        WHERE id = p_batch_id;
    ELSIF p_item_type = 'crop' AND v_target_line_id IS NOT NULL THEN
        SELECT COALESCE(lr.exchange_rate, 1.0)
        INTO v_exchange_rate
        FROM public.packing_order_lines pol
        JOIN public.lot_receipts lr ON lr.id::text = pol.source_lot_id::text
        WHERE pol.id = v_target_line_id;
    ELSIF p_item_type = 'crop' AND v_order.lot_id IS NOT NULL THEN
        SELECT COALESCE(exchange_rate, 1.0)
        INTO v_exchange_rate
        FROM public.lot_receipts
        WHERE id::text = v_order.lot_id::text;
    END IF;

    IF v_exchange_rate IS NULL OR v_exchange_rate <= 0 THEN
        v_exchange_rate := 1.0;
    END IF;

    v_foreign_discount := ROUND(p_discount_amount / v_exchange_rate, 4);

    v_dest_account_id := public.resolve_gl_account(v_dest_account_code, v_company_id);

    -- ── Post Adjustment Journal Entry (Debit Note) with Cairo Local Date ──
    INSERT INTO public.journal_entries (
        entry_number, entry_date, description, status,
        is_auto_generated, source_type, source_id, company_id,
        created_by, created_at, updated_at
    ) VALUES (
        'PENDING',
        (NOW() AT TIME ZONE 'Africa/Cairo')::DATE,
        COALESCE(NULLIF(p_reason, ''), 
            CASE 
                WHEN v_supplier_uuid IS NOT NULL THEN 'إشعار تسوية مورد (' || COALESCE(v_item_name, '') || ') - أمر تعبئة رقم ' || COALESCE(v_order.order_number, p_order_id::text)
                ELSE 'تسوية تكلفة رصيد افتتاحي (' || COALESCE(v_item_name, '') || ') - أمر تعبئة رقم ' || COALESCE(v_order.order_number, p_order_id::text)
            END
        ),
        'posted', true, 'packing_order_debit_note', p_order_id::text, v_company_id,
        COALESCE(p_user_id, auth.uid()), now(), now()
    ) RETURNING id INTO v_je_id;

    v_entry_num := public.fn_get_next_sequence(v_company_id, 'packing_order_debit_note', NULL, NULL);
    IF v_entry_num IS NULL OR v_entry_num = '' THEN
        v_entry_num := 'PKDN-' || LPAD(v_je_id::text, 5, '0');
    END IF;
    UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;

    IF v_source_account_id IS NOT NULL THEN
        INSERT INTO public.account_ledger_entries (
            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
            v_je_id, v_source_account_id,
            CASE WHEN v_supplier_currency != 'EGP' THEN v_foreign_discount ELSE p_discount_amount END,
            0,
            v_supplier_currency,
            p_discount_amount,
            COALESCE(NULLIF(p_reason, ''), 
                CASE 
                    WHEN v_supplier_uuid IS NOT NULL THEN 'تسوية سعر / إشعار خصم مورد عن أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text)
                    ELSE 'تسوية تكلفة رصيد افتتاحي عن أمر تعبئة ' || COALESCE(v_order.order_number, p_order_id::text)
                END
            ),
            v_company_id
        );
    END IF;

    IF v_dest_account_id IS NOT NULL THEN
        INSERT INTO public.account_ledger_entries (
            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id
        ) VALUES (
            v_je_id, v_dest_account_id, 0, p_discount_amount, 'EGP', p_discount_amount,
            COALESCE(NULLIF(p_reason, ''), v_target_desc),
            v_company_id
        );
    END IF;

    IF v_supplier_uuid IS NOT NULL THEN
        UPDATE public.suppliers
        SET outstanding_balance = COALESCE(outstanding_balance, 0) - 
            CASE WHEN v_supplier_currency != 'EGP' THEN v_foreign_discount ELSE p_discount_amount END
        WHERE id = v_supplier_uuid;

        INSERT INTO public.ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_id, description, created_by
        ) VALUES (
            'supplier',
            v_supplier_uuid::TEXT,
            'debit',
            CASE WHEN v_supplier_currency != 'EGP' THEN v_foreign_discount ELSE p_discount_amount END,
            v_supplier_currency,
            'packing_order_debit_note',
            v_je_id,
            COALESCE(NULLIF(p_reason, ''), 'إشعار خصم وتسوية مورد (' || COALESCE(v_item_name, '') || ') عن أمر تعبئة رقم ' || COALESCE(v_order.order_number, p_order_id::text)),
            COALESCE(p_user_id, auth.uid())
        );
    END IF;

    UPDATE public.export_shipment_items
    SET price = v_new_cost_per_carton
    WHERE packing_order_id = p_order_id
      AND (packing_order_line_id IS NULL OR packing_order_line_id NOT IN (SELECT id FROM public.packing_order_lines WHERE packing_order_id = p_order_id));

    FOR v_line IN SELECT * FROM public.packing_order_lines WHERE packing_order_id = p_order_id LOOP
        IF COALESCE(v_line.carton_count, 0) > 0 THEN
            UPDATE public.export_shipment_items
            SET price = ROUND(v_line.final_cost / v_line.carton_count, 4)
            WHERE packing_order_line_id = v_line.id;
        END IF;
    END LOOP;

    FOR r_ship IN 
        SELECT DISTINCT es.id
        FROM public.export_shipment_items esi
        JOIN public.export_shipments es ON es.id = esi.shipment_id
        WHERE esi.packing_order_id = p_order_id
          AND es.status != 'cancelled'
    LOOP
        UPDATE public.export_shipments es
        SET net_profit_egp = COALESCE(es.total_revenue_egp, 0) - COALESCE(es.total_landed_cost, 0) - COALESCE(es.allocated_admin_expenses, 0) - COALESCE(es.allocated_taxes, 0),
            net_profit = COALESCE(es.total_revenue_egp, 0) - COALESCE(es.total_landed_cost, 0) - COALESCE(es.allocated_admin_expenses, 0) - COALESCE(es.allocated_taxes, 0),
            updated_at = now()
        WHERE es.id = r_ship.id;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'journal_entry_id', v_je_id,
        'entry_number', v_entry_num,
        'old_packing_cost_per_carton', ROUND(v_old_total_pkg_cost / v_carton_count, 4),
        'new_packing_cost_per_carton', v_new_cost_per_carton,
        'old_total_packing_cost', v_old_total_pkg_cost,
        'new_total_packing_cost', v_new_total_pkg_cost,
        'discount_amount', p_discount_amount,
        'foreign_discount_amount', v_foreign_discount,
        'supplier_currency', v_supplier_currency
    );
END;
$$;

-- 5. Fix dates on existing journal entries created tonight after 21:00 UTC (past midnight in Egypt)
UPDATE public.journal_entries
SET entry_date = (created_at AT TIME ZONE 'Africa/Cairo')::DATE
WHERE entry_date != (created_at AT TIME ZONE 'Africa/Cairo')::DATE
  AND created_at >= '2026-08-27 21:00:00+00';
