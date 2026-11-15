

BEGIN;



-- =========================================================================

-- المرحلة 0: متطلبات العمليات والمخازن واستلامات اللوطات

-- =========================================================================

ALTER TABLE IF EXISTS public.lot_receipts 

    ADD COLUMN IF NOT EXISTS journal_entry_id BIGINT REFERENCES public.journal_entries(id) ON DELETE SET NULL,

    ADD COLUMN IF NOT EXISTS paid_amount NUMERIC(15,2) DEFAULT 0,

    ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'unpaid',

    ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'EGP',

    ADD COLUMN IF NOT EXISTS exchange_rate NUMERIC(15, 6) DEFAULT 1.0,

    ADD COLUMN IF NOT EXISTS currency_snapshot JSONB DEFAULT '{}'::jsonb,

    ADD COLUMN IF NOT EXISTS payment_source_type TEXT DEFAULT 'treasury',

    ADD COLUMN IF NOT EXISTS payment_treasury_id TEXT,

    ADD COLUMN IF NOT EXISTS payment_bank_account_id INTEGER,

    ADD COLUMN IF NOT EXISTS payment_processed BOOLEAN DEFAULT false,

    ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES public.sys_companies(id),

    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;



ALTER TABLE IF EXISTS public.purchase_invoices 

    ADD COLUMN IF NOT EXISTS journal_entry_id BIGINT REFERENCES public.journal_entries(id) ON DELETE SET NULL,

    ADD COLUMN IF NOT EXISTS payment_processed BOOLEAN DEFAULT false,

    ADD COLUMN IF NOT EXISTS exchange_rate NUMERIC(15, 6) DEFAULT 1.0;



ALTER TABLE IF EXISTS public.stock_transfers

    ADD COLUMN IF NOT EXISTS journal_entry_id BIGINT REFERENCES public.journal_entries(id) ON DELETE SET NULL,

    ADD COLUMN IF NOT EXISTS unit_cost NUMERIC(19,4) DEFAULT 0,

    ADD COLUMN IF NOT EXISTS total_cost NUMERIC(19,4) DEFAULT 0,

    ADD COLUMN IF NOT EXISTS currency VARCHAR(10) DEFAULT 'EGP';



ALTER TABLE IF EXISTS public.stations

    ADD COLUMN IF NOT EXISTS inventory_account_id BIGINT REFERENCES public.accounts(id) ON DELETE SET NULL,

    ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES public.sys_companies(id);



ALTER TABLE IF EXISTS public.suppliers 

    ADD COLUMN IF NOT EXISTS crop_currency VARCHAR(10) DEFAULT 'USD',

    ADD COLUMN IF NOT EXISTS packaging_currency VARCHAR(10) DEFAULT 'EGP',

    ADD COLUMN IF NOT EXISTS supported_currencies TEXT[] DEFAULT ARRAY['EGP', 'USD', 'EUR'],

    ADD COLUMN IF NOT EXISTS initial_balance_direction TEXT DEFAULT 'CREDIT',

    ADD COLUMN IF NOT EXISTS pending_expected_balance NUMERIC DEFAULT 0;



ALTER TABLE IF EXISTS public.lot_returns 

    ADD COLUMN IF NOT EXISTS journal_entry_id BIGINT REFERENCES public.journal_entries(id) ON DELETE SET NULL,

    ADD COLUMN IF NOT EXISTS lot_number TEXT,

    ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES public.sys_companies(id),

    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;



ALTER TABLE IF EXISTS public.fruit_types 

    ADD COLUMN IF NOT EXISTS cost_center_id TEXT,

    ADD COLUMN IF NOT EXISTS purchase_mode TEXT;



ALTER TABLE IF EXISTS public.fruit_types 

    ALTER COLUMN cost_center_id TYPE TEXT USING cost_center_id::TEXT;



DROP TRIGGER IF EXISTS trg_fruit_types_cost_center ON public.fruit_types;

DROP FUNCTION IF EXISTS public.fn_sync_fruit_type_cost_center();



GRANT ALL ON TABLE public.fruit_types TO authenticated, anon, service_role;

DO $$

BEGIN

    IF EXISTS (SELECT 1 FROM pg_sequences WHERE schemaname = 'public' AND sequencename = 'fruit_types_id_seq') THEN

        EXECUTE 'GRANT ALL ON SEQUENCE public.fruit_types_id_seq TO authenticated, anon, service_role';

    END IF;

    IF EXISTS (SELECT 1 FROM pg_sequences WHERE schemaname = 'public' AND sequencename = 'fruit_type_code_seq') THEN

        EXECUTE 'GRANT ALL ON SEQUENCE public.fruit_type_code_seq TO authenticated, anon, service_role';

    END IF;

END $$;



ALTER TABLE IF EXISTS public.station_products

    ADD COLUMN IF NOT EXISTS item_type TEXT DEFAULT 'material',

    ADD COLUMN IF NOT EXISTS raw_material_id UUID REFERENCES public.raw_materials(id) ON DELETE CASCADE,

    ADD COLUMN IF NOT EXISTS fruit_type_id BIGINT REFERENCES public.fruit_types(id) ON DELETE CASCADE;



ALTER TABLE IF EXISTS public.station_products

    DROP CONSTRAINT IF EXISTS station_products_station_id_product_name_key,

    DROP CONSTRAINT IF EXISTS station_products_station_id_code_name_key,

    DROP CONSTRAINT IF EXISTS uq_station_products_station_product_name;



DROP INDEX IF EXISTS public.station_products_station_id_product_name_key;

DROP INDEX IF EXISTS public.station_products_station_id_code_name_key;

DROP INDEX IF EXISTS public.idx_station_products_material;

DROP INDEX IF EXISTS public.idx_station_products_fruit;



CREATE UNIQUE INDEX IF NOT EXISTS idx_station_products_material 

    ON public.station_products (station_id, raw_material_id) 

    WHERE item_type = 'material' AND raw_material_id IS NOT NULL;



CREATE UNIQUE INDEX IF NOT EXISTS idx_station_products_fruit 

    ON public.station_products (station_id, fruit_type_id) 

    WHERE item_type = 'fruit' AND fruit_type_id IS NOT NULL;



ALTER TABLE IF EXISTS public.station_product_batches

    ADD COLUMN IF NOT EXISTS item_type TEXT,

    ADD COLUMN IF NOT EXISTS raw_material_id UUID REFERENCES public.raw_materials(id) ON DELETE CASCADE,

    ADD COLUMN IF NOT EXISTS fruit_type_id BIGINT REFERENCES public.fruit_types(id) ON DELETE CASCADE,

    ADD COLUMN IF NOT EXISTS supplier_id TEXT,

    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW(),

    ADD COLUMN IF NOT EXISTS source_id TEXT;





INSERT INTO public.sys_document_types (code, name, prefix, is_active)

VALUES 

    ('lot_receipt', 'شراء محصول', 'LOT', true),

    ('stock_transfer', 'Warehouse Stock Transfer / تحويل مخزني بين المحطات', 'WTR', true)

ON CONFLICT (code) DO UPDATE 

SET name = EXCLUDED.name, 

    prefix = EXCLUDED.prefix,

    is_active = true;



-- =========================================================================

-- Migration 424: Fix timezone offset in shipment costing journal entries (admin expenses, taxes, cost items)

-- Ensuring all journal entries use Cairo local date (UTC+3) instead of server UTC CURRENT_DATE.



-- 1. Update rpc_save_shipment_admin_expenses

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

    SELECT company_id INTO v_company_id FROM public.accounts WHERE account_code IN ('9124', '9210', '5210') LIMIT 1;

    IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1; END IF;



    -- 9124 / 9210 / 5210: Allocated Admin Expenses (مصروفات إدارية محملة)

    v_admin_exp_account_id := public.resolve_gl_account('9124', v_company_id);

    IF v_admin_exp_account_id IS NULL THEN

        SELECT id INTO v_admin_exp_account_id FROM public.accounts WHERE account_code IN ('9124', '9210', '5210', '6002', '6000') LIMIT 1;

    END IF;

    IF v_admin_exp_account_id IS NULL THEN

        SELECT id INTO v_admin_exp_account_id FROM public.accounts WHERE account_type = 'expense' LIMIT 1;

    END IF;



    -- 9123 / 9105 / 2105: Admin Expenses Provision (مخصص / وسيط مصروفات إدارية)

    v_provision_account_id := public.resolve_gl_account('9123', v_company_id);

    IF v_provision_account_id IS NULL THEN

        SELECT id INTO v_provision_account_id FROM public.accounts WHERE account_code IN ('9123', '9105', '2105', '2100') LIMIT 1;

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

    SELECT company_id INTO v_company_id FROM public.accounts WHERE account_code IN ('9122', '9102', '2102') LIMIT 1;

    IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1; END IF;



    -- 9122 / 9102 / 2102: Allocated Taxes (ضرائب محملة)

    v_tax_debit_acc := public.resolve_gl_account('9122', v_company_id);

    IF v_tax_debit_acc IS NULL THEN

        SELECT id INTO v_tax_debit_acc FROM public.accounts WHERE account_code IN ('9122', '9102', '2102', '2100') LIMIT 1;

    END IF;



    -- 9121 / 9101 / 2101: Tax Intermediary (وسيط ضرائب)

    v_tax_credit_acc := public.resolve_gl_account('9121', v_company_id);

    IF v_tax_credit_acc IS NULL THEN

        SELECT id INTO v_tax_credit_acc FROM public.accounts WHERE account_code IN ('9121', '9101', '2101', '2100') LIMIT 1;

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



-- (Canonical rpc_apply_packing_order_item_debit_note defined above)



-- 5. Fix dates on existing journal entries created tonight after 21:00 UTC (past midnight in Egypt)

UPDATE public.journal_entries

SET entry_date = (created_at AT TIME ZONE 'Africa/Cairo')::DATE

WHERE entry_date != (created_at AT TIME ZONE 'Africa/Cairo')::DATE

  AND created_at >= '2026-08-27 21:00:00+00';



-- 5.9. Helper function: allocate overhead shares across lines

CREATE OR REPLACE FUNCTION public._packing_allocate_shares(p_method text, p_bases numeric[])

 RETURNS numeric[]

 LANGUAGE plpgsql

 IMMUTABLE

AS $function$

DECLARE

  v_n INT;

  v_total NUMERIC := 0;

  v_shares NUMERIC[];

  i INT;

BEGIN

  v_n := COALESCE(array_length(p_bases, 1), 0);

  IF v_n = 0 THEN

    RETURN ARRAY[]::NUMERIC[];

  END IF;



  FOR i IN 1..v_n LOOP

    v_total := v_total + COALESCE(p_bases[i], 0);

  END LOOP;



  IF v_total <= 0 THEN

    v_shares := ARRAY[]::NUMERIC[];

    FOR i IN 1..v_n LOOP

      v_shares := v_shares || ARRAY[ROUND((1.0 / v_n)::numeric, 8)];

    END LOOP;

    RETURN v_shares;

  END IF;



  v_shares := ARRAY[]::NUMERIC[];

  FOR i IN 1..v_n LOOP

    v_shares := v_shares || ARRAY[ROUND((COALESCE(p_bases[i], 0) / v_total)::numeric, 8)];

  END LOOP;

  RETURN v_shares;

END;

$function$;



GRANT EXECUTE ON FUNCTION public._packing_allocate_shares(text, numeric[]) TO authenticated, anon, service_role;



-- Resolve supplier liability account for packing cost item

CREATE OR REPLACE FUNCTION public.fn_resolve_packing_cost_supplier_account(

    p_supplier_id UUID,

    p_company_id UUID

)

RETURNS BIGINT

LANGUAGE plpgsql

STABLE

AS $$

DECLARE

    v_acc_id BIGINT;

    v_supp_type TEXT;

    v_supp_code TEXT;

    v_target_code TEXT;

BEGIN

    IF p_supplier_id IS NULL THEN

        RETURN public.resolve_gl_account('2111', p_company_id);

    END IF;



    SELECT account_id, supplier_type, code INTO v_acc_id, v_supp_type, v_supp_code

    FROM public.suppliers

    WHERE id = p_supplier_id;



    IF v_acc_id IS NOT NULL THEN

        RETURN v_acc_id;

    END IF;



    -- Infer code from supplier_type

    IF v_supp_type = 'station' OR v_supp_code LIKE '85%' OR v_supp_code LIKE '86%' OR v_supp_code LIKE '87%' OR v_supp_code LIKE '88%' OR v_supp_code LIKE '89%' THEN

        v_target_code := '21117';

    ELSIF v_supp_type IN ('deduction', 'deductions') OR v_supp_code LIKE '4%' THEN

        v_target_code := '21118';

    ELSIF v_supp_type = 'transport' OR v_supp_code LIKE '6%' THEN

        v_target_code := '21111';

    ELSIF v_supp_type = 'packaging' OR v_supp_code LIKE '70%' OR v_supp_code LIKE '71%' THEN

        v_target_code := '21112';

    ELSIF v_supp_type = 'shared' OR v_supp_code LIKE '75%' THEN

        v_target_code := '21114';

    ELSIF v_supp_type = 'shipping' OR v_supp_code LIKE '9%' THEN

        v_target_code := '21115';

    ELSE

        v_target_code := '21113';

    END IF;



    RETURN public.resolve_gl_account(v_target_code, p_company_id);

END;

$$;



GRANT EXECUTE ON FUNCTION public.fn_resolve_packing_cost_supplier_account(UUID, UUID) TO authenticated, anon, service_role;



-- 6. Canonical rpc_confirm_packing_order with supplier_id population

CREATE OR REPLACE FUNCTION public.rpc_confirm_packing_order(p_packing_order_id bigint)

 RETURNS json

 LANGUAGE plpgsql

 SECURITY DEFINER

AS $function$

DECLARE

  v_order RECORD;

  v_notes JSONB;

  v_order_num TEXT;

  v_station_id INT;

  v_packed_at TIMESTAMPTZ;

  v_company_id UUID;



  -- Cost components

  v_tot_raw_cost NUMERIC := 0;

  v_tot_waste_cost NUMERIC := 0;

  v_tot_sorting_cost NUMERIC := 0;

  v_fruit_net_cost NUMERIC := 0;

  v_mat_waste_pct NUMERIC := 0;

  v_tot_pkg_drawn NUMERIC := 0;

  v_tot_pkg_waste NUMERIC := 0;

  v_tot_pkg_consumed NUMERIC := 0;

  v_tot_cost_items NUMERIC := 0;

  v_finished_goods_cost NUMERIC := 0;



  -- Account IDs

  v_finished_inv_acc INT;

  v_raw_inv_acc INT;

  v_sorting_inv_acc INT;

  v_pkg_inv_acc INT;

  v_pkg_waste_inter_acc INT;    -- 2106

  v_crop_waste_inter_acc INT;   -- 2107

  v_credit_acc INT;

  v_supp_leaf_acc INT;



  -- Journal entry tracking

  v_je_id INT;

  v_entry_num TEXT;

  v_sum_debit NUMERIC := 0;

  v_sum_credit NUMERIC := 0;



  -- Loop variables

  v_el JSONB;

  r_cost RECORD;

  v_supplier_id UUID;

  v_supp_str TEXT;

  v_amt_egp NUMERIC;

  v_target_line_idx INT;



  -- Inventory deduction variables

  v_alloc JSONB;

  v_batch_id BIGINT;

  v_used_qty NUMERIC;

  v_pname TEXT;

  v_pcode TEXT;

  v_curr_rem NUMERIC;

  v_sp_qty NUMERIC;

  v_rem_needed NUMERIC;

  r_b RECORD;

  v_take NUMERIC;



  -- Cost allocation arrays

  v_n INT := 0;

  v_lines RECORD;

  v_line_ids BIGINT[];

  v_line_raw NUMERIC[];

  v_line_net NUMERIC[];

  v_line_overhead NUMERIC[];

  v_bases NUMERIC[];

  v_shares NUMERIC[];

  v_amount NUMERIC;

  v_method TEXT;

  v_assigned NUMERIC;

  v_part NUMERIC;

  v_max_cost_item_id BIGINT;

  v_posted_cost_items NUMERIC := 0;

BEGIN

  -- ── A. Validate Packing Order ──

  SELECT * INTO v_order FROM public.packing_orders WHERE id = p_packing_order_id FOR UPDATE;

  IF NOT FOUND THEN

    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');

  END IF;



  IF v_order.status = 'completed' THEN

    RETURN json_build_object(

      'success', true,

      'message', 'أمر التعبئة مؤكد بالفعل',

      'journal_entry_id', v_order.journal_entry_id

    );

  END IF;



  IF v_order.status != 'draft' AND v_order.status != 'pending' THEN

    RETURN json_build_object('success', false, 'error', 'حالة أمر التعبئة لا تسمح بالتأكيد: ' || v_order.status);

  END IF;



  BEGIN

    v_notes := COALESCE(v_order.notes::jsonb, '{}'::jsonb);

    IF jsonb_typeof(v_notes) = 'string' THEN

      v_notes := (v_notes #>> '{}')::jsonb;

    END IF;

  EXCEPTION WHEN OTHERS THEN

    v_notes := '{}'::jsonb;

  END;



  v_order_num := COALESCE(v_order.order_number, p_packing_order_id::text);

  v_station_id := v_order.station_id;

  v_packed_at := COALESCE(v_order.packed_at, now());



  -- ── B. Fruit Inventory Deduction ──

  IF v_notes ? 'fruit_allocation' THEN

    v_alloc := v_notes->'fruit_allocation';

    IF jsonb_typeof(v_alloc) = 'object' THEN v_alloc := jsonb_build_array(v_alloc); END IF;



    FOR v_el IN SELECT * FROM jsonb_array_elements(v_alloc)

    LOOP

      v_batch_id := (v_el->>'batch_id')::bigint;

      v_used_qty := COALESCE((v_el->>'quantity')::numeric, (v_el->>'used_qty')::numeric, 0);

      v_pname := v_el->>'product_name';

      v_pcode := v_el->>'product_code';



      IF v_batch_id IS NOT NULL AND v_batch_id > 0 AND v_used_qty > 0 THEN

        SELECT remaining_quantity INTO v_curr_rem

        FROM public.station_product_batches

        WHERE id = v_batch_id

        FOR UPDATE;



        IF FOUND AND v_curr_rem >= v_used_qty THEN

          UPDATE public.station_product_batches

          SET remaining_quantity = remaining_quantity - v_used_qty

          WHERE id = v_batch_id;



          SELECT COALESCE(SUM(remaining_quantity), 0) INTO v_sp_qty

          FROM public.station_product_batches

          WHERE station_id = v_station_id

            AND (product_name = v_pname OR (v_pcode IS NOT NULL AND v_pcode != '' AND product_code = v_pcode));



          UPDATE public.station_products

          SET quantity = v_sp_qty, updated_at = NOW()

          WHERE station_id = v_station_id

            AND (product_name = v_pname OR (v_pcode IS NOT NULL AND v_pcode != '' AND product_code = v_pcode));

        END IF;

      END IF;

    END LOOP;

  END IF;



  -- ── C. Material Inventory Deduction ──

  IF v_notes ? 'materials' AND jsonb_typeof(v_notes->'materials') = 'array' THEN

    FOR v_el IN SELECT * FROM jsonb_array_elements(v_notes->'materials')

    LOOP

      v_batch_id := (v_el->>'batch_id')::bigint;

      v_used_qty := COALESCE((v_el->>'used_qty')::numeric, (v_el->>'quantity')::numeric, 0);

      v_pname := v_el->>'product_name';

      v_pcode := v_el->>'product_code';



      IF v_used_qty > 0 THEN

        IF v_batch_id IS NOT NULL AND v_batch_id > 0 THEN

          SELECT remaining_quantity INTO v_curr_rem

          FROM public.station_product_batches

          WHERE id = v_batch_id

          FOR UPDATE;



          IF FOUND AND v_curr_rem >= v_used_qty THEN

            UPDATE public.station_product_batches

            SET remaining_quantity = remaining_quantity - v_used_qty

            WHERE id = v_batch_id;

          ELSE

            v_rem_needed := v_used_qty;

            FOR r_b IN (

              SELECT id, remaining_quantity

              FROM public.station_product_batches

              WHERE station_id = v_station_id

                AND (product_name = v_pname OR product_code = v_pcode)

                AND remaining_quantity > 0

              ORDER BY id ASC

              FOR UPDATE

            ) LOOP

              IF v_rem_needed <= 0 THEN EXIT; END IF;

              v_take := LEAST(r_b.remaining_quantity, v_rem_needed);

              UPDATE public.station_product_batches

              SET remaining_quantity = remaining_quantity - v_take

              WHERE id = r_b.id;

              v_rem_needed := v_rem_needed - v_take;

            END LOOP;

          END IF;

        ELSE

          v_rem_needed := v_used_qty;

          FOR r_b IN (

            SELECT id, remaining_quantity

            FROM public.station_product_batches

            WHERE station_id = v_station_id

              AND (product_name = v_pname OR product_code = v_pcode)

              AND remaining_quantity > 0

            ORDER BY id ASC

            FOR UPDATE

          ) LOOP

            IF v_rem_needed <= 0 THEN EXIT; END IF;

            v_take := LEAST(r_b.remaining_quantity, v_rem_needed);

            UPDATE public.station_product_batches

            SET remaining_quantity = remaining_quantity - v_take

            WHERE id = r_b.id;

            v_rem_needed := v_rem_needed - v_take;

          END LOOP;

        END IF;



        SELECT COALESCE(SUM(remaining_quantity), 0) INTO v_sp_qty

        FROM public.station_product_batches

        WHERE station_id = v_station_id

          AND (product_name = v_pname OR product_code = v_pcode);



        UPDATE public.station_products

        SET quantity = v_sp_qty, updated_at = NOW()

        WHERE station_id = v_station_id

          AND (product_name = v_pname OR product_code = v_pcode);

      END IF;

    END LOOP;

  END IF;



  -- ── D. Rebuild Cost Items from Notes ──

  IF v_notes ? 'cost_items' AND jsonb_typeof(v_notes->'cost_items') = 'array' THEN

    DELETE FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id;

    SELECT COALESCE(MAX(id), 0) INTO v_max_cost_item_id FROM public.packing_order_cost_items;

    IF v_max_cost_item_id > 0 THEN

      PERFORM setval(pg_get_serial_sequence('public.packing_order_cost_items', 'id'), v_max_cost_item_id);

    ELSE

      PERFORM setval(pg_get_serial_sequence('public.packing_order_cost_items', 'id'), 1, false);

    END IF;



    FOR v_el IN SELECT jsonb_array_elements(v_notes->'cost_items')

    LOOP

      v_amt_egp := COALESCE((v_el->>'total_egp')::numeric, 0);

      IF v_amt_egp > 0 THEN

        v_supplier_id := NULL;

        v_supp_str := v_el->>'supplier_id';

        IF v_supp_str IS NOT NULL AND v_supp_str != '' AND v_supp_str != 'null' THEN

          v_supplier_id := v_supp_str::uuid;

        END IF;



        v_target_line_idx := NULL;

        IF v_el ? 'target_line_index' AND v_el->>'target_line_index' != '' AND v_el->>'target_line_index' != 'null' THEN

          v_target_line_idx := (v_el->>'target_line_index')::integer;

        END IF;



        INSERT INTO public.packing_order_cost_items (

          packing_order_id, name, category,

          base_amount, original_amount, original_currency,

          payment_source_type, payment_source_id,

          allocation_method, target_line_id,

          currency_snapshot, supplier_id, payment_status, paid_amount

        ) VALUES (

          p_packing_order_id,

          v_el->>'name',

          CASE WHEN v_el->>'category' IN ('fruit', 'material', 'logistics', 'other') THEN v_el->>'category' ELSE 'other' END,

          v_amt_egp,

          COALESCE((v_el->>'total')::numeric, v_amt_egp),

          COALESCE(NULLIF(v_el->>'currency', ''), COALESCE(v_el->>'supplier_currency', 'EGP')),

          'none',

          NULL,

          v_el->>'allocation_method',

          v_target_line_idx,

          jsonb_build_object(

            'supplier_id', v_supplier_id,

            'supplier_name', v_el->>'supplier_name',

            'target_line_index', v_target_line_idx

          ),

          v_supplier_id::text,

          'unpaid',

          0

        );

      END IF;

    END LOOP;

  END IF;



  -- ── E. Allocate Cost Items Across Lines ──

  v_n := 0;

  v_bases := ARRAY[]::NUMERIC[];

  FOR v_lines IN

    SELECT id, COALESCE(raw_material_cost, 0) as rc, COALESCE(total_net_weight, 0) as nw

    FROM public.packing_order_lines

    WHERE packing_order_id = p_packing_order_id

    ORDER BY id

  LOOP

    v_n := v_n + 1;

    v_line_ids[v_n] := v_lines.id;

    v_line_raw[v_n] := v_lines.rc;

    v_line_net[v_n] := v_lines.nw;

    v_line_overhead[v_n] := 0;

    v_bases[v_n] := v_lines.rc;

  END LOOP;



  FOR r_cost IN

    SELECT * FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id

  LOOP

    v_amount := COALESCE(r_cost.base_amount, 0);

    IF v_amount <= 0 THEN CONTINUE; END IF;



    IF r_cost.target_line_id IS NOT NULL THEN

      IF r_cost.target_line_id >= 0 AND r_cost.target_line_id < v_n THEN

        v_line_overhead[r_cost.target_line_id + 1] := v_line_overhead[r_cost.target_line_id + 1] + v_amount;

      END IF;

      CONTINUE;

    END IF;



    v_method := COALESCE(r_cost.allocation_method, 'EQUAL');

    IF v_method = 'WEIGHT' THEN

      FOR v_i IN 1..v_n LOOP v_bases[v_i] := v_line_net[v_i]; END LOOP;

    ELSIF v_method = 'COST' THEN

      FOR v_i IN 1..v_n LOOP v_bases[v_i] := v_line_raw[v_i]; END LOOP;

    ELSE

      FOR v_i IN 1..v_n LOOP v_bases[v_i] := 1; END LOOP;

    END IF;



    IF v_n > 0 THEN

      v_shares := public._packing_allocate_shares(v_method, v_bases);

      v_assigned := 0;

      FOR v_i IN 1..v_n LOOP

        IF v_i = v_n THEN

          v_part := ROUND(v_amount - v_assigned, 2);

        ELSE

          v_part := ROUND(v_amount * v_shares[v_i], 2);

        END IF;

        v_line_overhead[v_i] := v_line_overhead[v_i] + v_part;

        v_assigned := v_assigned + v_part;

      END LOOP;

    END IF;

  END LOOP;



  -- ══════════════════════════════════════════════════════════════════════════

  -- F. Calculate Cost Values Directly from Packing Order Data

  -- ══════════════════════════════════════════════════════════════════════════



  -- 1. Produce Raw Cost & Sorting

  v_tot_raw_cost := ROUND(COALESCE(v_order.fruit_cost_base, 0), 4);

  IF v_tot_raw_cost = 0 THEN

    IF v_notes ? 'fruit_allocation' THEN

      DECLARE

        v_f_elem JSONB;

        v_f_arr JSONB := v_notes->'fruit_allocation';

      BEGIN

        IF jsonb_typeof(v_f_arr) = 'object' THEN v_f_arr := jsonb_build_array(v_f_arr); END IF;

        FOR v_f_elem IN SELECT * FROM jsonb_array_elements(v_f_arr) LOOP

          v_tot_raw_cost := v_tot_raw_cost + (

            COALESCE((v_f_elem->>'quantity')::numeric, 0) *

            COALESCE((v_notes->>'product_cost_per_kg')::numeric, 0)

          );

        END LOOP;

      END;

    END IF;

  END IF;

  IF v_tot_raw_cost = 0 THEN

    v_tot_raw_cost := ROUND(COALESCE(v_order.fruit_cost_allocated, 0), 4);

  END IF;



  v_tot_sorting_cost := ROUND(COALESCE((v_notes->>'sorting_cost')::numeric, 0), 4);

  IF v_tot_sorting_cost = 0 THEN

    SELECT COALESCE(SUM(sorting_cost), 0) INTO v_tot_sorting_cost

    FROM public.packing_order_lines WHERE packing_order_id = p_packing_order_id;

  END IF;

  IF v_tot_sorting_cost = 0 THEN

    SELECT COALESCE(SUM(total_cost), 0) INTO v_tot_sorting_cost

    FROM public.packing_order_sortings WHERE packing_order_id = p_packing_order_id;

  END IF;



  -- 2. Produce Waste Cost

  v_tot_waste_cost := ROUND(COALESCE((v_notes->>'waste_cost')::numeric, 0), 4);

  IF v_tot_waste_cost = 0 THEN

    SELECT COALESCE(SUM(waste_cost), 0) INTO v_tot_waste_cost

    FROM public.packing_order_lines WHERE packing_order_id = p_packing_order_id;

  END IF;



  -- Net Fruit Cost (Good Fruit entering product)

  v_fruit_net_cost := ROUND(GREATEST(0, v_tot_raw_cost - v_tot_sorting_cost - v_tot_waste_cost), 4);



  -- 3. Packaging Materials Base Cost (1040) & Waste

  v_mat_waste_pct := COALESCE((v_notes->>'material_waste_percent')::numeric, 0);

  v_tot_pkg_drawn := 0;



  IF v_notes ? 'materials' AND jsonb_typeof(v_notes->'materials') = 'array' THEN

    DECLARE

      v_m_el JSONB;

    BEGIN

      FOR v_m_el IN SELECT * FROM jsonb_array_elements(v_notes->'materials') LOOP

        v_tot_pkg_drawn := v_tot_pkg_drawn + COALESCE(

          (v_m_el->>'total')::numeric,

          (COALESCE((v_m_el->>'used_qty')::numeric, (v_m_el->>'quantity')::numeric, 0) *

           COALESCE((v_m_el->>'unit_cost')::numeric, 0))

        );

      END LOOP;

    END;

  END IF;



  IF v_tot_pkg_drawn = 0 THEN

    v_tot_pkg_drawn := COALESCE(v_order.actual_material_cost, v_order.material_cost_base, 0);

    IF v_mat_waste_pct > 0 THEN

      v_tot_pkg_drawn := ROUND(v_tot_pkg_drawn / (1.0 + (v_mat_waste_pct / 100.0)), 4);

    END IF;

  END IF;



  -- 4. Packaging Waste Cost

  v_tot_pkg_waste := ROUND(v_tot_pkg_drawn * (v_mat_waste_pct / 100.0), 4);

  v_tot_pkg_consumed := v_tot_pkg_drawn + v_tot_pkg_waste;



  -- 5. Additional Cost Items

  v_tot_cost_items := 0;

  FOR r_cost IN SELECT * FROM public.packing_order_cost_items WHERE packing_order_id = p_packing_order_id

  LOOP

    v_tot_cost_items := v_tot_cost_items + COALESCE(r_cost.base_amount, 0);

  END LOOP;

  IF v_tot_cost_items = 0 THEN

    v_tot_cost_items := COALESCE(v_order.other_cost_base, 0);

  END IF;



  -- 6. Total Finished Goods Cost (1031)

  v_finished_goods_cost := ROUND(COALESCE(v_order.total_packing_cost, 0), 4);

  IF v_finished_goods_cost = 0 THEN

    v_finished_goods_cost := ROUND(v_fruit_net_cost + v_tot_waste_cost + v_tot_pkg_drawn + v_tot_pkg_waste + v_tot_cost_items, 4);

  END IF;



  -- ── G. Resolve COA Accounts ──

  SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;

  IF v_company_id IS NULL THEN SELECT id INTO v_company_id FROM sys_companies LIMIT 1; END IF;



  v_finished_inv_acc     := COALESCE(public.resolve_gl_account('12413', v_company_id), public.resolve_gl_account('1031', v_company_id));

  v_sorting_inv_acc      := COALESCE(public.resolve_gl_account('12414', v_company_id), public.resolve_gl_account('1032', v_company_id));

  v_raw_inv_acc          := COALESCE(public.resolve_gl_account('12412', v_company_id), public.resolve_gl_account('1030', v_company_id));

  v_pkg_inv_acc          := COALESCE(public.resolve_gl_account('12411', v_company_id), public.resolve_gl_account('1040', v_company_id));

  v_pkg_waste_inter_acc  := COALESCE(public.resolve_gl_account('9111', v_company_id), public.resolve_gl_account('2106', v_company_id));

  v_crop_waste_inter_acc := COALESCE(public.resolve_gl_account('9112', v_company_id), public.resolve_gl_account('2107', v_company_id));



  -- Clean up previous JE if exists

  IF v_order.journal_entry_id IS NOT NULL THEN

    DELETE FROM account_ledger_entries WHERE journal_entry_id = v_order.journal_entry_id;

    DELETE FROM journal_entries WHERE id = v_order.journal_entry_id;

  END IF;



  -- ── J. Create Journal Entry (Egypt Cairo Timezone) ──

  INSERT INTO public.journal_entries (

    entry_number, entry_date, description, status,

    is_auto_generated, source_type, source_id, company_id,

    created_by, created_at, updated_at

  ) VALUES (

    'PENDING',

    COALESCE((v_order.packed_at AT TIME ZONE 'Africa/Cairo')::date, (v_order.created_at AT TIME ZONE 'Africa/Cairo')::date, (CURRENT_TIMESTAMP AT TIME ZONE 'Africa/Cairo')::date),

    'قيد أمر تعبئة رقم ' || v_order_num,

    'posted', true, 'packing_order', p_packing_order_id::text, v_company_id,

    auth.uid(), now(), now()

  ) RETURNING id INTO v_je_id;



  v_entry_num := public.fn_get_next_sequence(v_company_id, 'packing_order', NULL, NULL);

  IF v_entry_num IS NULL OR v_entry_num = '' THEN

    v_entry_num := 'PO-JE-' || LPAD(v_je_id::text, 5, '0');

  END IF;

  UPDATE public.journal_entries SET entry_number = v_entry_num WHERE id = v_je_id;



  -- ══════════════════════════════════════════════════════════════════════════

  -- H. JOURNAL ENTRY LINES (NEW SPECIFICATION)

  -- ══════════════════════════════════════════════════════════════════════════



  -- ── 1. DR 1031: إجمالي تكلفة أمر التعبئة بالكامل ──

  IF v_finished_goods_cost > 0 THEN

    INSERT INTO public.account_ledger_entries (

      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

    ) VALUES (

      v_je_id, v_finished_inv_acc, v_finished_goods_cost, 0, 'EGP', v_finished_goods_cost,

      'إجمالي تكلفة أمر تعبئة ' || v_order_num || ' (' || COALESCE(v_order.carton_count, 0) || ' كرتونة)',

      v_company_id

    );

    v_sum_debit := v_sum_debit + v_finished_goods_cost;

  END IF;



  -- ── 2. DR 1032: تكلفة مخزون الفرز ──

  IF v_tot_sorting_cost > 0 AND v_sorting_inv_acc IS NOT NULL THEN

    INSERT INTO public.account_ledger_entries (

      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

    ) VALUES (

      v_je_id, v_sorting_inv_acc, v_tot_sorting_cost, 0, 'EGP', v_tot_sorting_cost,

      'مخزون الفرز - أمر تعبئة ' || v_order_num,

      v_company_id

    );

    v_sum_debit := v_sum_debit + v_tot_sorting_cost;

  END IF;



  -- ── 3. CR 1030: تكلفة المحصول المستخدم بالكامل ──

  IF v_tot_raw_cost > 0 THEN

    INSERT INTO public.account_ledger_entries (

      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

    ) VALUES (

      v_je_id, v_raw_inv_acc, 0, v_tot_raw_cost, 'EGP', v_tot_raw_cost,

      'صرف محصول خام بالكامل - أمر تعبئة ' || v_order_num,

      v_company_id

    );

    v_sum_credit := v_sum_credit + v_tot_raw_cost;

  END IF;



  -- ── 4. CR 1040: تكلفة مواد التعبئة المستخدمة فقط بدون الهالك ──

  IF v_tot_pkg_drawn > 0 THEN

    INSERT INTO public.account_ledger_entries (

      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

    ) VALUES (

      v_je_id, v_pkg_inv_acc, 0, v_tot_pkg_drawn, 'EGP', v_tot_pkg_drawn,

      'صرف مواد تعبئة وتغليف (بدون الهالك) - أمر تعبئة ' || v_order_num,

      v_company_id

    );

    v_sum_credit := v_sum_credit + v_tot_pkg_drawn;

  END IF;



  -- ── 5. CR 2106: وسيط هالك مواد التعبئة ──

  IF v_tot_pkg_waste > 0 AND v_pkg_waste_inter_acc IS NOT NULL THEN

    INSERT INTO public.account_ledger_entries (

      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

    ) VALUES (

      v_je_id, v_pkg_waste_inter_acc, 0, v_tot_pkg_waste, 'EGP', v_tot_pkg_waste,

      'وسيط هالك مواد التعبئة والتغليف - أمر تعبئة ' || v_order_num,

      v_company_id

    );

    v_sum_credit := v_sum_credit + v_tot_pkg_waste;

  END IF;



  -- ── 6. CR 2107: وسيط هالك المحاصيل ──

  IF v_tot_waste_cost > 0 AND v_crop_waste_inter_acc IS NOT NULL THEN

    INSERT INTO public.account_ledger_entries (

      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

    ) VALUES (

      v_je_id, v_crop_waste_inter_acc, 0, v_tot_waste_cost, 'EGP', v_tot_waste_cost,

      'وسيط هالك وفاقد المحاصيل - أمر تعبئة ' || v_order_num,

      v_company_id

    );

    v_sum_credit := v_sum_credit + v_tot_waste_cost;

  END IF;



  -- ── 7. CR حسابات الموردين وبنود التكلفة ──

  v_posted_cost_items := 0;

  FOR r_cost IN

    SELECT * FROM public.packing_order_cost_items

    WHERE packing_order_id = p_packing_order_id AND COALESCE(base_amount, 0) > 0

  LOOP

    v_credit_acc := NULL;

    v_supplier_id := NULL;



    IF r_cost.currency_snapshot IS NOT NULL THEN

      v_supp_str := r_cost.currency_snapshot->>'supplier_id';

      IF v_supp_str IS NOT NULL AND v_supp_str != '' AND v_supp_str != 'null' THEN

        v_supplier_id := v_supp_str::uuid;

        SELECT account_id INTO v_supp_leaf_acc FROM public.suppliers WHERE id = v_supplier_id;

        IF v_supp_leaf_acc IS NOT NULL THEN v_credit_acc := v_supp_leaf_acc; END IF;

      END IF;

    END IF;



    IF v_credit_acc IS NULL THEN

      v_credit_acc := public.fn_resolve_packing_cost_supplier_account(v_supplier_id, v_company_id);

    END IF;



    IF v_credit_acc IS NULL THEN

      v_credit_acc := public.resolve_gl_account('2111', v_company_id);

    END IF;



    INSERT INTO public.account_ledger_entries (

      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

    ) VALUES (

      v_je_id, v_credit_acc, 0, r_cost.base_amount, 'EGP', r_cost.base_amount,

      'مصروفات أمر تعبئة ' || v_order_num || ' - ' || COALESCE(r_cost.name, 'تكلفة إضافية'), v_company_id

    );

    v_sum_credit := v_sum_credit + r_cost.base_amount;

    v_posted_cost_items := v_posted_cost_items + r_cost.base_amount;



    IF v_supplier_id IS NOT NULL THEN

      INSERT INTO public.ledger_entries (

        entity_id, entity_type, amount, currency, entry_type, reference_id, reference_type, reference_text, description, created_at

      ) VALUES (

        v_supplier_id::text, 'supplier', r_cost.original_amount, r_cost.original_currency,

        'credit', p_packing_order_id, 'packing_cost', p_packing_order_id::text,

        'بند تكلفة أمر تعبئة: ' || COALESCE(r_cost.name, '') || ' (أمر ' || v_order_num || ')', now()

      );

      UPDATE public.suppliers SET outstanding_balance = COALESCE(outstanding_balance, 0) + r_cost.base_amount WHERE id = v_supplier_id;

    END IF;

  END LOOP;



  -- Fallback credit for other_cost_base

  IF v_tot_cost_items > v_posted_cost_items THEN

    v_credit_acc := public.resolve_gl_account('2111', v_company_id);

    INSERT INTO public.account_ledger_entries (

      journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

    ) VALUES (

      v_je_id, v_credit_acc, 0, (v_tot_cost_items - v_posted_cost_items), 'EGP', (v_tot_cost_items - v_posted_cost_items),

      'مصروفات إضافية أمر تعبئة ' || v_order_num, v_company_id

    );

    v_sum_credit := v_sum_credit + (v_tot_cost_items - v_posted_cost_items);

  END IF;



  -- ══════════════════════════════════════════════════════════════════════════

  -- VALIDATION

  -- ══════════════════════════════════════════════════════════════════════════

  IF ABS(v_sum_debit - v_sum_credit) > 0.01 THEN

    RAISE EXCEPTION 'فشل تأكيد أمر التعبئة: القيد غير متزن (مدين=% ≠ دائن=%)', v_sum_debit, v_sum_credit;

  END IF;



  -- Absorb sub-cent penny rounding into the finished-goods debit line

  IF v_sum_debit != v_sum_credit AND v_finished_goods_cost > 0 THEN

    UPDATE public.account_ledger_entries

    SET debit = debit + (v_sum_credit - v_sum_debit),

        amount_in_base_currency = amount_in_base_currency + (v_sum_credit - v_sum_debit)

    WHERE journal_entry_id = v_je_id

      AND account_id = v_finished_inv_acc

      AND debit > 0;

    v_sum_debit := v_sum_credit;

  END IF;



  UPDATE public.packing_orders

  SET status = 'completed',

      journal_entry_id = v_je_id,

      reversal_journal_entry_id = NULL,

      updated_at = now()

  WHERE id = p_packing_order_id;



  RETURN json_build_object(

    'success', true,

    'journal_entry_id', v_je_id,

    'finished_goods_cost', v_finished_goods_cost,

    'fruit_net_cost', v_fruit_net_cost,

    'sorting_inventory_cost', v_tot_sorting_cost,

    'crop_waste_cost', v_tot_waste_cost,

    'packaging_base_cost', v_tot_pkg_drawn,

    'packaging_waste_cost', v_tot_pkg_waste,

    'packaging_total_cost', v_tot_pkg_consumed,

    'supplier_costs', v_tot_cost_items,

    'debit', v_sum_debit,

    'credit', v_sum_credit

  );

END;

$function$;



GRANT EXECUTE ON FUNCTION public.rpc_confirm_packing_order(bigint) TO authenticated, service_role;



-- ==============================================================================

-- Migration 443: Ensure explicit initial_balance, current_balance, and currency

--                on clearing_agents and shipping_companies tables.

-- ==============================================================================

ALTER TABLE public.clearing_agents ADD COLUMN IF NOT EXISTS initial_balance NUMERIC DEFAULT 0;

ALTER TABLE public.clearing_agents ADD COLUMN IF NOT EXISTS current_balance NUMERIC DEFAULT 0;

ALTER TABLE public.clearing_agents ADD COLUMN IF NOT EXISTS currency VARCHAR(10) DEFAULT 'EGP';



DO $$

BEGIN

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'clearing_agents' AND column_name = 'balance') THEN

    UPDATE public.clearing_agents 

    SET current_balance = balance 

    WHERE (current_balance IS NULL OR current_balance = 0) AND balance != 0;

  END IF;

END $$;



ALTER TABLE public.shipping_companies ADD COLUMN IF NOT EXISTS initial_balance NUMERIC DEFAULT 0;

ALTER TABLE public.shipping_companies ADD COLUMN IF NOT EXISTS current_balance NUMERIC DEFAULT 0;

ALTER TABLE public.shipping_companies ADD COLUMN IF NOT EXISTS currency VARCHAR(10) DEFAULT 'EGP';



DO $$

BEGIN

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'shipping_companies' AND column_name = 'balance') THEN

    UPDATE public.shipping_companies 

    SET current_balance = balance 

    WHERE (current_balance IS NULL OR current_balance = 0) AND balance != 0;

  END IF;

END $$;



-- ==============================================================================

-- Migration 444: Fix Purchase Confirmation Balanced Double-Entry Journal Entry

--                Aligned with 4-Level Chart of Accounts (1234, 1231, 2112, 1211, 1212)

-- ==============================================================================



CREATE OR REPLACE FUNCTION public.rpc_confirm_purchase(

  p_purchase_id TEXT,

  p_user_id UUID DEFAULT auth.uid()

)

RETURNS JSONB

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path = public

AS $$

DECLARE

  v_purchase RECORD;

  v_item RECORD;

  v_batch_number TEXT;

  v_date_str TEXT;

  v_seq INT := 0;

  v_station_product_name TEXT;

  v_cur_qty NUMERIC;

  v_cur_price NUMERIC;

  v_new_qty NUMERIC;

  v_new_price NUMERIC;

  v_total_foreign NUMERIC := 0;

  v_total_egp NUMERIC := 0;

  v_exchange_rate NUMERIC := 1.0;

  v_inventory_account_id INTEGER;

  v_supplier_leaf_account_id INTEGER;

  v_account_group RECORD;

  v_paid_amount NUMERIC;

  v_treasury_id TEXT;

  v_bank_account_id INTEGER;

  v_source_type TEXT;

  v_cash_account_id INTEGER;

  v_treasury_name TEXT;

  v_bank_name TEXT;

  v_treasury_balance_id BIGINT;

  v_balance_before NUMERIC;

  v_balance_after NUMERIC;

  v_payment_number TEXT;

  v_inv_currency TEXT;

  v_batches_created INT := 0;

  v_company_id UUID;

  v_inventory_je_id BIGINT;

  v_payment_je_id BIGINT;

  v_supplier_name TEXT;

BEGIN

  -- ── PHASE 0a: Load Purchase Invoice ─────────────────────────────────────────

  SELECT * INTO v_purchase FROM purchase_invoices WHERE id::TEXT = p_purchase_id;

  IF NOT FOUND THEN

    RETURN jsonb_build_object('success', false, 'error', 'لم يتم العثور على الفاتورة');

  END IF;

  IF v_purchase.status = 'confirmed' THEN

    RETURN jsonb_build_object('success', true, 'message', 'تم التأكيد مسبقاً');

  END IF;



  v_date_str := to_char(COALESCE(v_purchase.invoice_date::date, now()::date), 'YYYYMMDD');

  v_inv_currency := COALESCE(v_purchase.currency, 'EGP');



  -- Determine transaction exchange rate

  SELECT COALESCE(NULLIF(exchange_rate, 0), 1.0) INTO v_exchange_rate 

  FROM purchase_invoice_items 

  WHERE invoice_id::TEXT = p_purchase_id 

  LIMIT 1;

  IF v_exchange_rate IS NULL OR v_exchange_rate <= 0 THEN v_exchange_rate := 1.0; END IF;



  -- ── PHASE 0a2: Resolve Company ID ──────────────────────────────────────────

  SELECT company_id INTO v_company_id FROM suppliers WHERE id = v_purchase.supplier_id;

  IF v_company_id IS NULL THEN

    SELECT id INTO v_company_id FROM sys_companies WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 1;

  END IF;

  IF v_company_id IS NULL THEN

    SELECT id INTO v_company_id FROM sys_companies LIMIT 1;

  END IF;

  IF v_company_id IS NULL THEN

    RAISE EXCEPTION 'لم يتم العثور على شركة صالحة';

  END IF;



  -- ── PHASE 0b: Resolve Supplier Leaf Account (Credit Account) ────────────────

  SELECT name INTO v_supplier_name FROM suppliers WHERE id = v_purchase.supplier_id;



  -- Priority 1: Use supplier's assigned account if valid, active, and allows posting

  SELECT a.id INTO v_supplier_leaf_account_id

  FROM suppliers s

  JOIN accounts a ON a.id = s.account_id

  WHERE s.id = v_purchase.supplier_id

    AND a.deleted_at IS NULL

    AND (a.allow_posting = TRUE OR a.is_leaf = TRUE);



  -- Priority 2: Lookup supplier's dedicated leaf sub-account under 2111

  IF v_supplier_leaf_account_id IS NULL THEN

    SELECT a.id INTO v_supplier_leaf_account_id

    FROM accounts a

    WHERE (a.account_code LIKE '2111%' OR a.parent_id = (SELECT id FROM accounts WHERE account_code = '2111' AND deleted_at IS NULL LIMIT 1))

      AND (a.account_name ILIKE '%' || v_supplier_name || '%' OR a.name ILIKE '%' || v_supplier_name || '%')

      AND a.deleted_at IS NULL

    ORDER BY a.id ASC

    LIMIT 1;

  END IF;



  -- Priority 3: Auto-create leaf account under 2111 if missing

  IF v_supplier_leaf_account_id IS NULL AND v_purchase.supplier_id IS NOT NULL THEN

    DECLARE

      v_p2111_id BIGINT;

      v_next_num INT;

      v_next_code TEXT;

    BEGIN

      SELECT id INTO v_p2111_id FROM accounts WHERE account_code = '2111' AND deleted_at IS NULL LIMIT 1;

      IF v_p2111_id IS NOT NULL THEN

        SELECT COALESCE(MAX(SUBSTRING(account_code FROM 5)::INT), 0) + 1

        INTO v_next_num

        FROM accounts

        WHERE account_code ~ '^2111[0-9]+$' AND deleted_at IS NULL;



        v_next_code := '2111' || LPAD(COALESCE(v_next_num, 1)::TEXT, 2, '0');



        INSERT INTO accounts (

          account_code, name, account_name, account_type,

          parent_id, level, is_leaf, allow_posting, is_active, is_system, company_id

        ) VALUES (

          v_next_code,

          'Supplier - ' || COALESCE(v_supplier_name, 'Unknown'),

          'مورد - ' || COALESCE(v_supplier_name, 'غير محدد'),

          'liability',

          v_p2111_id,

          5,

          TRUE,

          TRUE,

          TRUE,

          FALSE,

          v_company_id

        ) RETURNING id INTO v_supplier_leaf_account_id;



        UPDATE suppliers SET account_id = v_supplier_leaf_account_id WHERE id = v_purchase.supplier_id;

      END IF;

    END;

  END IF;



  -- Priority 4: Fallback to Level 4 parent account 2111 (enable posting if needed)

  IF v_supplier_leaf_account_id IS NULL THEN

    SELECT id INTO v_supplier_leaf_account_id FROM accounts WHERE account_code = '2111' AND deleted_at IS NULL LIMIT 1;

    IF v_supplier_leaf_account_id IS NOT NULL THEN

      UPDATE accounts SET allow_posting = TRUE WHERE id = v_supplier_leaf_account_id;

    END IF;

  END IF;



  -- Priority 5: Fallback to legacy 2000

  IF v_supplier_leaf_account_id IS NULL THEN

    SELECT id INTO v_supplier_leaf_account_id FROM accounts WHERE account_code = '2000' AND deleted_at IS NULL LIMIT 1;

  END IF;



  IF v_supplier_leaf_account_id IS NULL THEN

    RAISE EXCEPTION 'لم يتم العثور على حساب المورد في شجرة الحسابات (دليل الحسابات)';

  END IF;



  -- ── PHASE 1: Stock Batches + Raw Materials + Station Products ───────────────

  FOR v_item IN

    SELECT pii.*, rm.code AS rm_code, rm.name AS rm_name, rm.unit AS rm_unit,

           rmc.name AS category_name

    FROM purchase_invoice_items pii

    LEFT JOIN raw_materials rm ON rm.id = pii.raw_material_id

    LEFT JOIN raw_material_categories rmc ON rmc.id = rm.category_id

    WHERE pii.invoice_id::TEXT = p_purchase_id

  LOOP

    v_seq := v_seq + 1;

    v_batch_number := 'B-' || v_date_str || '-' || v_purchase.id::TEXT || '-' || lpad(v_seq::TEXT, 4, '0');



    INSERT INTO stock_batches (

      batch_number, product_id, supplier_id, supplier_name, purchase_invoice_id,

      quantity, remaining_quantity, purchase_cost, average_cost,

      exchange_rate, currency, status, user_id

    ) VALUES (

      v_batch_number,

      v_item.raw_material_id,

      v_purchase.supplier_id,

      v_supplier_name,

      v_purchase.id,

      COALESCE(v_item.quantity, 0),

      COALESCE(v_item.quantity, 0),

      COALESCE(v_item.unit_cost, 0),

      COALESCE(v_item.unit_cost, 0),

      v_exchange_rate,

      v_inv_currency,

      'active',

      p_user_id

    );

    v_batches_created := v_batches_created + 1;



    IF v_item.raw_material_id IS NOT NULL THEN

      SELECT quantity, default_purchase_price INTO v_cur_qty, v_cur_price

      FROM raw_materials WHERE id = v_item.raw_material_id;



      IF FOUND THEN

        v_cur_qty := COALESCE(v_cur_qty, 0);

        v_cur_price := COALESCE(v_cur_price, 0);

        v_new_qty := v_cur_qty + COALESCE(v_item.quantity, 0);

        IF v_new_qty > 0 THEN

          v_new_price := ((v_cur_qty * v_cur_price) + (COALESCE(v_item.quantity, 0) * COALESCE(v_item.unit_cost, 0))) / v_new_qty;

        ELSE

          v_new_price := COALESCE(v_item.unit_cost, 0);

        END IF;

        UPDATE raw_materials

        SET quantity = v_new_qty, default_purchase_price = v_new_price, updated_at = now()

        WHERE id = v_item.raw_material_id;

      END IF;



      DECLARE

        v_station_id BIGINT;

      BEGIN

        v_station_id := v_item.station_id;

        IF v_station_id IS NULL THEN

          SELECT spb.station_id INTO v_station_id

          FROM station_product_batches spb

          WHERE spb.product_code = COALESCE(v_item.rm_code, '') AND spb.source_type = 'purchase'

          LIMIT 1;

        END IF;

        IF v_station_id IS NULL THEN

          SELECT sp.station_id INTO v_station_id

          FROM station_products sp

          WHERE sp.product_code = COALESCE(v_item.rm_code, '') LIMIT 1;

        END IF;



        IF v_station_id IS NOT NULL THEN

          v_station_product_name := COALESCE(v_item.rm_name, '') || ' (مادة تعبئة)';

          PERFORM upsert_station_product_quantity(v_station_id, v_station_product_name, COALESCE(v_item.rm_code, ''), COALESCE(v_item.quantity, 0)::INT);



          INSERT INTO station_product_batches (

            station_id, product_name, product_code, quantity, remaining_quantity,

            unit_cost, currency, exchange_rate, source_type, source_date,

            supplier_name, purchase_invoice_id

          ) VALUES (

            v_station_id, v_station_product_name, COALESCE(v_item.rm_code, ''),

            COALESCE(v_item.quantity, 0), COALESCE(v_item.quantity, 0),

            COALESCE(v_item.unit_cost, 0), v_inv_currency, v_exchange_rate,

            'purchase', now(),

            v_supplier_name,

            v_purchase.id

          );

        END IF;

      END;

    END IF;



    v_total_foreign := v_total_foreign + (COALESCE(v_item.quantity, 0) * COALESCE(v_item.unit_cost, 0));

    v_total_egp := v_total_egp + (COALESCE(v_item.quantity, 0) * COALESCE(v_item.unit_cost, 0) * v_exchange_rate);

  END LOOP;



  v_paid_amount := COALESCE(v_purchase.paid_amount, 0);

  v_treasury_id := v_purchase.payment_treasury_id;

  v_bank_account_id := v_purchase.payment_bank_account_id;

  v_source_type := COALESCE(v_purchase.payment_source_type, 'treasury');



  IF v_purchase.supplier_id IS NOT NULL THEN

    DECLARE

      v_remaining NUMERIC;

      v_remaining_egp NUMERIC;

    BEGIN

      v_remaining := COALESCE(v_purchase.total_amount, 0) - v_paid_amount;

      v_remaining_egp := v_remaining * v_exchange_rate;

      IF v_remaining > 0 THEN

        UPDATE suppliers

        SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_remaining_egp

        WHERE id = v_purchase.supplier_id;

      END IF;

    END;

  END IF;



  -- ── PHASE 2: Granular Item-Level Inventory Journal Entry Lines ───────────────

  IF v_total_foreign > 0 THEN

    DECLARE

      v_lines_array JSONB := '[]'::jsonb;

      v_line_desc TEXT;

      v_item_line RECORD;

      v_item_foreign NUMERIC;

      v_item_egp NUMERIC;

      v_sum_debit_foreign NUMERIC := 0;

      v_sum_debit_egp NUMERIC := 0;

    BEGIN

      -- Loop through each purchased item to generate granular debit lines:

      FOR v_item_line IN

        SELECT

          pii.id,

          pii.quantity,

          pii.unit_cost,

          pii.raw_material_id,

          COALESCE(rm.name, rm.code, 'صنف غير محدد') AS item_name,

          COALESCE(rm.unit, '') AS item_unit,

          CASE 

            WHEN pii.raw_material_id IS NOT NULL THEN '12411'

            ELSE '12412'

          END AS inv_code

        FROM purchase_invoice_items pii

        LEFT JOIN raw_materials rm ON rm.id = pii.raw_material_id

        WHERE pii.invoice_id::TEXT = p_purchase_id

        ORDER BY pii.id ASC

      LOOP

        v_item_foreign := ROUND(COALESCE(v_item_line.quantity, 0) * COALESCE(v_item_line.unit_cost, 0), 2);

        v_item_egp := ROUND(v_item_foreign * v_exchange_rate, 2);



        v_sum_debit_foreign := v_sum_debit_foreign + v_item_foreign;

        v_sum_debit_egp := v_sum_debit_egp + v_item_egp;



        -- Resolve target inventory account (12411 packaging / 12412 produce)

        SELECT id INTO v_inventory_account_id 

        FROM accounts 

        WHERE account_code = v_item_line.inv_code 

          AND company_id = v_company_id 

          AND deleted_at IS NULL 

        LIMIT 1;



        IF v_inventory_account_id IS NULL THEN

          SELECT id INTO v_inventory_account_id 

          FROM accounts 

          WHERE account_code = v_item_line.inv_code 

            AND deleted_at IS NULL 

          LIMIT 1;

        END IF;



        -- Fallback between 12411 and 12412 or parent 1241

        IF v_inventory_account_id IS NULL THEN

          IF v_item_line.inv_code = '12411' THEN

            SELECT id INTO v_inventory_account_id 

            FROM accounts 

            WHERE account_code IN ('12412', '1241') AND deleted_at IS NULL 

            ORDER BY account_code ASC LIMIT 1;

          ELSE

            SELECT id INTO v_inventory_account_id 

            FROM accounts 

            WHERE account_code IN ('12411', '1241') AND deleted_at IS NULL 

            ORDER BY account_code ASC LIMIT 1;

          END IF;

        END IF;



        -- Fallback to any inventory asset account

        IF v_inventory_account_id IS NULL THEN

          SELECT id INTO v_inventory_account_id 

          FROM accounts 

          WHERE account_code LIKE '124%' AND allow_posting = TRUE AND deleted_at IS NULL 

          LIMIT 1;

        END IF;



        -- Hard validation: Never silently skip debit line

        IF v_inventory_account_id IS NULL THEN

          RAISE EXCEPTION 'لم يتم العثور على حساب المخزون (%) في شجرة الحسابات', v_item_line.inv_code;

        END IF;



        -- Granular line description with item details

        v_line_desc := 'مخزون - ' || v_item_line.item_name || 

          ' - كمية: ' || v_item_line.quantity || 

          CASE WHEN v_item_line.item_unit <> '' THEN ' ' || v_item_line.item_unit ELSE '' END || 

          ' - بسعر: ' || v_item_line.unit_cost || ' ' || v_inv_currency ||

          ' - فاتورة ' || COALESCE(v_purchase.invoice_number, '');



        -- Granular Debit Line (مدين): Inventory Account per purchased item

        v_lines_array := v_lines_array || jsonb_build_object(

          'account_id', v_inventory_account_id,

          'debit', v_item_foreign,

          'base_debit', v_item_egp,

          'credit', 0,

          'base_credit', 0,

          'currency', v_inv_currency,

          'description', v_line_desc

        );

      END LOOP;



      -- Credit Line (دائن): Supplier Sub-Account strictly balancing all debit lines

      v_lines_array := v_lines_array || jsonb_build_object(

        'account_id', v_supplier_leaf_account_id,

        'debit', 0,

        'base_debit', 0,

        'credit', v_sum_debit_foreign,

        'base_credit', v_sum_debit_egp,

        'currency', v_inv_currency,

        'description', 'مستحقات مورد: ' || COALESCE(v_supplier_name, '') || ' - فاتورة ' || COALESCE(v_purchase.invoice_number, '')

      );



      -- Post balanced inventory journal entry

      v_inventory_je_id := public.post_journal_entry(

        p_source_type := 'purchase_inventory',

        p_description := 'قيد مشتريات فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, ''),

        p_entry_date  := COALESCE(v_purchase.invoice_date::date, now()::date),

        p_company_id  := v_company_id,

        p_created_by  := p_user_id,

        p_lines       := v_lines_array,

        p_source_id   := v_purchase.id::TEXT

      );

      UPDATE purchase_invoices SET journal_entry_id = v_inventory_je_id WHERE id = v_purchase.id;

    END;

  END IF;



  -- ── PHASE 3: Payment Processing (Treasury or Bank) ─────────────────────────

  IF v_paid_amount > 0 AND COALESCE(v_purchase.payment_processed, false) = false THEN

    IF v_source_type = 'bank' AND v_bank_account_id IS NOT NULL THEN

      SELECT ba.name INTO v_bank_name FROM bank_accounts ba WHERE ba.id = v_bank_account_id;



      -- Resolve bank account under 1211 (12111 EGP, 12112 USD, 12113 EUR, 12114 GBP)

      SELECT id INTO v_cash_account_id FROM accounts

      WHERE account_code = (

        CASE v_inv_currency

          WHEN 'USD' THEN '12112'

          WHEN 'EUR' THEN '12113'

          WHEN 'GBP' THEN '12114'

          ELSE '12111'

        END

      ) AND company_id = v_company_id AND deleted_at IS NULL LIMIT 1;



      IF v_cash_account_id IS NULL THEN

        SELECT id INTO v_cash_account_id FROM accounts

        WHERE account_code = (

          CASE v_inv_currency

            WHEN 'USD' THEN '12112'

            WHEN 'EUR' THEN '12113'

            WHEN 'GBP' THEN '12114'

            ELSE '12111'

          END

        ) AND deleted_at IS NULL LIMIT 1;

      END IF;



      IF v_cash_account_id IS NULL THEN

        SELECT id INTO v_cash_account_id FROM accounts 

        WHERE account_code IN ('1211', '11201', '1010') AND deleted_at IS NULL LIMIT 1;

      END IF;



      UPDATE bank_accounts SET balance = balance - v_paid_amount WHERE id = v_bank_account_id;



      INSERT INTO bank_account_transactions (

        bank_account_id, type, amount, balance_before, balance_after, description, entity_type, entity_id, created_by, created_at

      ) VALUES (

        v_bank_account_id, 'withdraw', v_paid_amount,

        (SELECT balance + v_paid_amount FROM bank_accounts WHERE id = v_bank_account_id),

        (SELECT balance FROM bank_accounts WHERE id = v_bank_account_id),

        'دفعة للمورد - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, ''),

        'supplier', v_purchase.supplier_id::TEXT, p_user_id, COALESCE(v_purchase.invoice_date::date, now()::date)

      );



      v_payment_number := 'PAY-' || v_date_str || '-' || v_purchase.id::TEXT;

      INSERT INTO cash_payments (payment_number, supplier_id, amount, payment_method, payment_date, created_by)

      VALUES (v_payment_number, v_purchase.supplier_id, v_paid_amount, 'bank', COALESCE(v_purchase.invoice_date::date, now()::date), p_user_id);



      -- Balanced Bank Payment Journal Entry

      v_payment_je_id := public.post_journal_entry(

        p_source_type := 'purchase_payment',

        p_description := 'دفعة بنكية - فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, ''),

        p_entry_date  := COALESCE(v_purchase.invoice_date::date, now()::date),

        p_company_id  := v_company_id,

        p_created_by  := p_user_id,

        p_lines       := jsonb_build_array(

          jsonb_build_object(

            'account_id', v_supplier_leaf_account_id,

            'debit', v_paid_amount,

            'base_debit', v_paid_amount * v_exchange_rate,

            'credit', 0,

            'base_credit', 0,

            'currency', v_inv_currency,

            'description', 'سداد مورد: ' || COALESCE(v_supplier_name, '')

          ),

          jsonb_build_object(

            'account_id', v_cash_account_id,

            'debit', 0,

            'base_debit', 0,

            'credit', v_paid_amount,

            'base_credit', v_paid_amount * v_exchange_rate,

            'currency', v_inv_currency,

            'description', 'بنك: ' || COALESCE(v_bank_name, '')

          )

        ),

        p_source_id   := v_purchase.id::TEXT

      );



    ELSIF v_treasury_id IS NOT NULL THEN

      SELECT name INTO v_treasury_name FROM treasuries WHERE id = v_treasury_id::INTEGER;



      -- Resolve treasury account under 1221 (12211 EGP, 12212 USD, 12213 EUR, 12214 GBP)

      v_cash_account_id := public.resolve_treasury_account(v_treasury_id::INTEGER, v_inv_currency, v_company_id);

      IF v_cash_account_id IS NULL THEN

        SELECT id INTO v_cash_account_id FROM accounts

        WHERE account_code = (

          CASE v_inv_currency

            WHEN 'USD' THEN '12212'

            WHEN 'EUR' THEN '12213'

            WHEN 'GBP' THEN '12214'

            ELSE '12211'

          END

        ) AND deleted_at IS NULL LIMIT 1;

      END IF;

      IF v_cash_account_id IS NULL THEN

        SELECT id INTO v_cash_account_id FROM accounts

        WHERE account_code = (

          CASE v_inv_currency

            WHEN 'USD' THEN '12122'

            WHEN 'EUR' THEN '12123'

            WHEN 'GBP' THEN '12124'

            ELSE '12121'

          END

        ) AND deleted_at IS NULL LIMIT 1;

      END IF;

      IF v_cash_account_id IS NULL THEN

        SELECT id INTO v_cash_account_id FROM accounts 

        WHERE account_code IN ('1212', '11101', '1100') AND deleted_at IS NULL LIMIT 1;

      END IF;



      v_payment_number := 'PAY-' || v_date_str || '-' || v_purchase.id::TEXT;



      SELECT id, balance INTO v_treasury_balance_id, v_balance_before

      FROM treasury_balances WHERE treasury_id = v_treasury_id::INTEGER AND currency = v_inv_currency LIMIT 1;



      IF v_treasury_balance_id IS NULL THEN

        INSERT INTO treasury_balances (treasury_id, currency, balance, account_id)

        VALUES (v_treasury_id::INTEGER, v_inv_currency, 0, v_cash_account_id)

        RETURNING id, balance INTO v_treasury_balance_id, v_balance_before;

      END IF;



      v_balance_after := COALESCE(v_balance_before, 0) - v_paid_amount;

      UPDATE treasury_balances SET balance = v_balance_after, updated_at = now()

      WHERE id = v_treasury_balance_id;



      INSERT INTO treasury_transactions (

        treasury_id, type, currency, amount, balance_before, balance_after,

        description, supplier_id, created_by, created_at

      ) VALUES (

        v_treasury_id::INTEGER, 'supplier_payment', v_inv_currency, v_paid_amount, v_balance_before, v_balance_after,

        'دفعة خزنة - فاتورة ' || COALESCE(v_purchase.invoice_number, ''), v_purchase.supplier_id, p_user_id, COALESCE(v_purchase.invoice_date::date, now()::date)

      );



      INSERT INTO cash_payments (payment_number, supplier_id, amount, payment_method, payment_date, created_by)

      VALUES (v_payment_number, v_purchase.supplier_id, v_paid_amount, 'cash', COALESCE(v_purchase.invoice_date::date, now()::date), p_user_id);



      -- Balanced Treasury Payment Journal Entry

      v_payment_je_id := public.post_journal_entry(

        p_source_type := 'purchase_payment',

        p_description := 'دفعة نقدية - فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, ''),

        p_entry_date  := COALESCE(v_purchase.invoice_date::date, now()::date),

        p_company_id  := v_company_id,

        p_created_by  := p_user_id,

        p_lines       := jsonb_build_array(

          jsonb_build_object(

            'account_id', v_supplier_leaf_account_id,

            'debit', v_paid_amount,

            'base_debit', v_paid_amount * v_exchange_rate,

            'credit', 0,

            'base_credit', 0,

            'currency', v_inv_currency,

            'description', 'سداد مورد: ' || COALESCE(v_supplier_name, '')

          ),

          jsonb_build_object(

            'account_id', v_cash_account_id,

            'debit', 0,

            'base_debit', 0,

            'credit', v_paid_amount,

            'base_credit', v_paid_amount * v_exchange_rate,

            'currency', v_inv_currency,

            'description', 'خزنة: ' || COALESCE(v_treasury_name, '')

          )

        ),

        p_source_id   := v_purchase.id::TEXT

      );

    END IF;



    UPDATE purchase_invoices SET payment_processed = true WHERE id = v_purchase.id;

  END IF;



  -- ── PHASE 4: Mark Purchase Confirmed ───────────────────────────────────────

  UPDATE purchase_invoices

  SET status = 'confirmed',

      journal_entry_id = COALESCE(v_payment_je_id, v_inventory_je_id),

      updated_at = now()

  WHERE id = v_purchase.id;



  RETURN jsonb_build_object(

    'success', true,

    'purchase_id', v_purchase.id,

    'batches_created', v_batches_created,

    'total_foreign', v_total_foreign,

    'total_egp', v_total_egp,

    'paid_amount', v_paid_amount,

    'remaining', COALESCE(v_purchase.total_amount, 0) - v_paid_amount,

    'inventory_je_id', v_inventory_je_id,

    'payment_je_id', v_payment_je_id

  );

END;

$$;



GRANT EXECUTE ON FUNCTION public.rpc_confirm_purchase(TEXT, UUID) TO authenticated, anon, service_role;



-- ==============================================================================

-- Migration 445: Fix Crop Purchases (lot_receipts) Balanced Journal Entry & Linkage

-- Following Chart of Accounts 4-Level Alignment (Migration 439 & 444).

-- ==============================================================================



-- ── 1. Document Types Registration ──────────────────────────────────────────

INSERT INTO public.sys_document_types (code, name, prefix, is_active)

VALUES 

  ('lot_receipt',          'Crop Purchase / شراء محصول',          'LOT', true),

  ('lot_price_adjustment', 'Crop Price Adjustment / تعديل سعر محصول', 'ADJ', true)

ON CONFLICT (code) DO UPDATE SET 

  prefix = EXCLUDED.prefix,

  name = EXCLUDED.name,

  is_active = true;



-- ── 2. Ensure general fallback leaf account under 2112 ────────────────────────

DO $$

DECLARE

  v_p2112_id BIGINT;

  v_company_id UUID;

BEGIN

  SELECT id INTO v_p2112_id FROM public.accounts WHERE account_code = '2112' AND deleted_at IS NULL LIMIT 1;

  SELECT id INTO v_company_id FROM public.sys_companies WHERE deleted_at IS NULL LIMIT 1;



  IF v_p2112_id IS NOT NULL THEN

    IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = '211200' AND deleted_at IS NULL) THEN

      INSERT INTO public.accounts (

        account_code, name, account_name, account_type,

        parent_id, level, is_leaf, allow_posting, is_active, is_system, company_id

      ) VALUES (

        '211200',

        'General Crop Suppliers',

        'موردي محاصيل عام',

        'liability',

        v_p2112_id,

        5,

        TRUE,

        TRUE,

        TRUE,

        FALSE,

        v_company_id

      );

    END IF;

  END IF;

END $$;



-- ── 3. Update sync_supplier_ledger_for_lot Function ───────────────────────────

CREATE OR REPLACE FUNCTION public.sync_supplier_ledger_for_lot(

  p_lot_id BIGINT,

  p_action TEXT DEFAULT 'INSERT'

)

RETURNS VOID

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path = public

AS $$

DECLARE

  v_lot RECORD;

  v_company_id UUID;

  v_inventory_account_id BIGINT;

  v_supplier_leaf_account_id BIGINT;

  v_supplier_name TEXT;

  v_je_id BIGINT;

  v_desc TEXT;

  v_total_cost NUMERIC;

  v_product_name TEXT;

  v_total_egp NUMERIC;

  v_exchange_rate NUMERIC;

  v_lot_currency TEXT;

  v_old_supplier_cost NUMERIC;

  v_old_base_debit NUMERIC;

  v_delta_foreign NUMERIC;

  v_delta_egp NUMERIC;

  v_je_desc TEXT;

BEGIN

  -- Handle DELETE

  IF p_action = 'DELETE' THEN

    SELECT * INTO v_lot FROM lot_receipts WHERE id = p_lot_id;

    IF v_lot.journal_entry_id IS NOT NULL THEN

      DELETE FROM journal_entries

      WHERE source_type IN ('lot_receipt', 'lot_price_adjustment')

        AND (source_id = p_lot_id::TEXT OR id = v_lot.journal_entry_id);



      IF v_lot.supplier_id IS NOT NULL THEN

        UPDATE suppliers

        SET outstanding_balance = COALESCE(outstanding_balance, 0) - COALESCE(v_lot.total_fruit_cost, 0)

        WHERE id = v_lot.supplier_id;

      END IF;



      UPDATE lot_receipts

      SET journal_entry_id = NULL

      WHERE id = p_lot_id;

    END IF;

    RETURN;

  END IF;



  -- Handle INSERT or UPDATE

  IF p_action IN ('INSERT', 'UPDATE') THEN

    SELECT * INTO v_lot FROM lot_receipts WHERE id = p_lot_id;

    IF NOT FOUND THEN RETURN; END IF;



    -- Only confirmed lots trigger double-entry GL posting

    IF v_lot.is_confirmed = true THEN

      v_total_cost := COALESCE(v_lot.total_fruit_cost, 0);

      IF v_total_cost <= 0 THEN RETURN; END IF;



      v_exchange_rate := COALESCE(NULLIF(v_lot.exchange_rate, 0), 1.0);

      v_total_egp := v_total_cost * v_exchange_rate;

      v_lot_currency := COALESCE(NULLIF(v_lot.currency, ''), 'EGP');

      v_product_name := COALESCE(v_lot.product_name, 'محصول');



      -- ── Resolve Company ──

      IF v_lot.supplier_id IS NOT NULL THEN

        SELECT company_id, name INTO v_company_id, v_supplier_name FROM suppliers WHERE id = v_lot.supplier_id;

      END IF;

      IF v_company_id IS NULL THEN

        SELECT id INTO v_company_id FROM sys_companies WHERE deleted_at IS NULL LIMIT 1;

      END IF;

      IF v_company_id IS NULL THEN

        SELECT id INTO v_company_id FROM sys_companies LIMIT 1;

      END IF;



      -- ── Resolve Crop Inventory Account (12412 primary - مخزن مشتريات خام) ──

      SELECT a.id INTO v_inventory_account_id

      FROM accounts a

      WHERE a.account_code = '12412' AND a.is_leaf = true AND a.deleted_at IS NULL

      LIMIT 1;



      IF v_inventory_account_id IS NULL THEN

        SELECT a.id INTO v_inventory_account_id

        FROM accounts a

        WHERE a.account_code = '1241' AND a.deleted_at IS NULL

        LIMIT 1;

      END IF;



      IF v_inventory_account_id IS NULL THEN

        SELECT a.id INTO v_inventory_account_id

        FROM accounts a

        WHERE a.account_code LIKE '124%' AND a.is_leaf = true AND a.deleted_at IS NULL

        ORDER BY a.account_code ASC

        LIMIT 1;

      END IF;



      IF v_inventory_account_id IS NULL THEN

        SELECT a.id INTO v_inventory_account_id

        FROM accounts a

        WHERE a.account_code = '1030' AND a.deleted_at IS NULL

        LIMIT 1;

      END IF;



      IF v_inventory_account_id IS NULL THEN

        RAISE EXCEPTION 'لم يتم العثور على حساب مخزن مشتريات خام (12412)';

      END IF;



      -- ── Resolve Supplier Leaf Account (Credit Account) ──

      v_supplier_leaf_account_id := NULL;



      -- Priority 1: Assigned account on supplier if active and is_leaf

      IF v_lot.supplier_id IS NOT NULL THEN

        SELECT a.id INTO v_supplier_leaf_account_id

        FROM suppliers s

        JOIN accounts a ON a.id = s.account_id

        WHERE s.id = v_lot.supplier_id

          AND a.deleted_at IS NULL

          AND a.is_leaf = TRUE

          AND a.is_active = TRUE;

      END IF;



      -- Priority 2: Lookup active leaf sub-account under 2111 (Crop Suppliers) or legacy 2112

      IF v_supplier_leaf_account_id IS NULL AND v_supplier_name IS NOT NULL THEN

        SELECT a.id INTO v_supplier_leaf_account_id

        FROM accounts a

        WHERE (a.account_code LIKE '2111%' OR a.account_code LIKE '2112%' OR a.parent_id IN (SELECT id FROM accounts WHERE account_code IN ('2111', '2112') AND deleted_at IS NULL))

          AND (a.account_name ILIKE '%' || v_supplier_name || '%' OR a.name ILIKE '%' || v_supplier_name || '%')

          AND a.is_leaf = TRUE

          AND a.deleted_at IS NULL

        ORDER BY CASE WHEN a.account_code LIKE '2111%' THEN 1 ELSE 2 END, a.id ASC

        LIMIT 1;

      END IF;



      -- Priority 3: Auto-create leaf account under 2111 if missing

      IF v_supplier_leaf_account_id IS NULL AND v_lot.supplier_id IS NOT NULL THEN

        DECLARE

          v_p2111_id BIGINT;

          v_next_num INT;

          v_next_code TEXT;

        BEGIN

          SELECT id INTO v_p2111_id FROM accounts WHERE account_code = '2111' AND deleted_at IS NULL LIMIT 1;

          IF v_p2111_id IS NOT NULL THEN

            SELECT COALESCE(MAX(SUBSTRING(account_code FROM 5)::INT), 0) + 1

            INTO v_next_num

            FROM accounts

            WHERE account_code ~ '^2111[0-9]+$' AND deleted_at IS NULL;



            v_next_code := '2111' || LPAD(COALESCE(v_next_num, 1)::TEXT, 2, '0');



            INSERT INTO accounts (

              account_code, name, account_name, account_type,

              parent_id, level, is_leaf, allow_posting, is_active, is_system, company_id

            ) VALUES (

              v_next_code,

              'Supplier - ' || COALESCE(v_supplier_name, 'Crop Supplier'),

              'مورد - ' || COALESCE(v_supplier_name, 'مورد محاصيل'),

              'liability',

              v_p2111_id,

              5,

              TRUE,

              TRUE,

              TRUE,

              FALSE,

              v_company_id

            ) RETURNING id INTO v_supplier_leaf_account_id;



            UPDATE suppliers SET account_id = v_supplier_leaf_account_id WHERE id = v_lot.supplier_id;

          END IF;

        END;

      END IF;



      -- Priority 4: Fallback to general leaf account 21111 under 2111 or 211200

      IF v_supplier_leaf_account_id IS NULL THEN

        SELECT a.id INTO v_supplier_leaf_account_id

        FROM accounts a

        WHERE a.account_code IN ('21111', '211100', '211200', '2111', '2112') AND a.is_leaf = TRUE AND a.deleted_at IS NULL

        ORDER BY CASE WHEN a.account_code LIKE '2111%' THEN 1 ELSE 2 END, a.id ASC

        LIMIT 1;

      END IF;



      -- Priority 5: Fallback to any leaf under 2111 or 2112

      IF v_supplier_leaf_account_id IS NULL THEN

        SELECT a.id INTO v_supplier_leaf_account_id

        FROM accounts a

        WHERE (a.account_code LIKE '2111%' OR a.account_code LIKE '2112%') AND a.is_leaf = TRUE AND a.deleted_at IS NULL

        ORDER BY CASE WHEN a.account_code LIKE '2111%' THEN 1 ELSE 2 END, a.id ASC

        LIMIT 1;

      END IF;



      IF v_supplier_leaf_account_id IS NULL THEN

        RAISE EXCEPTION 'لم يتم العثور على حساب مورد المحاصيل في شجرة الحسابات';

      END IF;



      -- ── POST OR UPDATE JOURNAL ENTRY ──

      -- Idempotency Guard: Check if an initial journal entry already exists for this lot

      SELECT id INTO v_je_id

      FROM public.journal_entries

      WHERE source_type = 'lot_receipt'

        AND source_id = p_lot_id::TEXT

        AND deleted_at IS NULL

      ORDER BY id ASC

      LIMIT 1;



      IF v_je_id IS NOT NULL THEN

        -- Already exists: ensure lot_receipts is linked to it

        IF v_lot.journal_entry_id IS DISTINCT FROM v_je_id THEN

          UPDATE public.lot_receipts

          SET journal_entry_id = v_je_id

          WHERE id = p_lot_id;

          v_lot.journal_entry_id := v_je_id;

        END IF;



        -- If not UPDATE, do not create duplicate; exit immediately

        IF p_action != 'UPDATE' THEN

          RETURN;

        END IF;

      END IF;



      IF p_action = 'UPDATE' AND (v_lot.journal_entry_id IS NOT NULL OR v_je_id IS NOT NULL) THEN

        -- Price adjustment handling

        SELECT COALESCE(SUM(amount_in_base_currency * CASE WHEN debit > 0 THEN 1 WHEN credit > 0 THEN -1 ELSE 0 END), 0)

        INTO v_old_base_debit

        FROM account_ledger_entries

        WHERE journal_entry_id IN (

           SELECT id FROM journal_entries 

           WHERE source_type IN ('lot_receipt', 'lot_price_adjustment') AND source_id = p_lot_id::TEXT

        ) AND account_id = v_inventory_account_id;



        SELECT COALESCE(SUM(credit - debit), 0)

        INTO v_old_supplier_cost

        FROM account_ledger_entries

        WHERE journal_entry_id IN (

           SELECT id FROM journal_entries 

           WHERE source_type IN ('lot_receipt', 'lot_price_adjustment') AND source_id = p_lot_id::TEXT

        ) AND account_id = v_supplier_leaf_account_id;



        v_delta_foreign := v_total_cost - v_old_supplier_cost;

        v_delta_egp := v_total_egp - v_old_base_debit;



        IF ABS(v_delta_foreign) >= 0.01 OR ABS(v_delta_egp) >= 0.01 THEN

           v_je_desc := 'تأثير تعديل سعر لمحصول - لوط رقم: ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT);

           

           v_je_id := public.post_journal_entry(

              p_source_type := 'lot_price_adjustment',

              p_description := v_je_desc,

              p_entry_date := COALESCE(v_lot.receipt_date, CURRENT_DATE),

              p_company_id := v_company_id,

              p_created_by := auth.uid(),

              p_lines := jsonb_build_array(

                jsonb_build_object(

                  'account_id', v_inventory_account_id,

                  'debit', CASE WHEN v_delta_egp > 0 THEN v_delta_egp ELSE 0 END,

                  'base_debit', CASE WHEN v_delta_egp > 0 THEN v_delta_egp ELSE 0 END,

                  'credit', CASE WHEN v_delta_egp < 0 THEN ABS(v_delta_egp) ELSE 0 END,

                  'base_credit', CASE WHEN v_delta_egp < 0 THEN ABS(v_delta_egp) ELSE 0 END,

                  'currency', 'EGP',

                  'description', v_je_desc

                ),

                jsonb_build_object(

                  'account_id', v_supplier_leaf_account_id,

                  'debit', CASE WHEN v_delta_foreign < 0 THEN ABS(v_delta_foreign) ELSE 0 END,

                  'base_debit', CASE WHEN v_delta_egp < 0 THEN ABS(v_delta_egp) ELSE 0 END,

                  'credit', CASE WHEN v_delta_foreign > 0 THEN v_delta_foreign ELSE 0 END,

                  'base_credit', CASE WHEN v_delta_egp > 0 THEN v_delta_egp ELSE 0 END,

                  'currency', v_lot_currency,

                  'description', v_je_desc

                )

              ),

              p_source_id := p_lot_id::TEXT

           );



           IF v_lot.supplier_id IS NOT NULL THEN

              UPDATE suppliers

              SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_delta_foreign

              WHERE id = v_lot.supplier_id;

           END IF;

        END IF;



      ELSIF v_je_id IS NULL AND v_lot.journal_entry_id IS NULL THEN

        -- INSERT new original balanced journal entry (only if none exists)

        v_desc := 'إثبات شراء ' || v_product_name || ' - لوط رقم: ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT);



        v_je_id := public.post_journal_entry(

          p_source_type := 'lot_receipt',

          p_description := v_desc,

          p_entry_date := COALESCE(v_lot.receipt_date, CURRENT_DATE),

          p_company_id := v_company_id,

          p_created_by := auth.uid(),

          p_lines := jsonb_build_array(

            jsonb_build_object(

              'account_id', v_inventory_account_id,

              'debit', v_total_cost,

              'base_debit', v_total_egp,

              'credit', 0,

              'base_credit', 0,

              'currency', v_lot_currency,

              'description', 'إثبات شراء محصول - لوط رقم ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT)

            ),

            jsonb_build_object(

              'account_id', v_supplier_leaf_account_id,

              'debit', 0,

              'base_debit', 0,

              'credit', v_total_cost,

              'base_credit', v_total_egp,

              'currency', v_lot_currency,

              'description', 'مستحقات مورد عن شراء محصول - لوط رقم ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT)

            )

          ),

          p_source_id := p_lot_id::TEXT

        );



        UPDATE lot_receipts

        SET journal_entry_id = v_je_id

        WHERE id = p_lot_id;



        IF v_lot.supplier_id IS NOT NULL THEN

          UPDATE suppliers

          SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_total_cost

          WHERE id = v_lot.supplier_id;

        END IF;

      END IF;



    END IF;

  END IF;

END;

$$;



-- ── 3b. Trigger Function on lot_receipts ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_on_harvest_receipt_saved()

RETURNS TRIGGER AS $$

BEGIN

  IF TG_OP = 'DELETE' THEN

    IF OLD.is_confirmed = true THEN

      PERFORM public.sync_supplier_ledger_for_lot(OLD.id, 'DELETE');

    END IF;

    RETURN OLD;

  END IF;



  IF TG_OP = 'UPDATE' THEN

    -- If only journal_entry_id changed, skip to prevent recursive triggers

    IF (OLD.journal_entry_id IS DISTINCT FROM NEW.journal_entry_id)

       AND (OLD.is_confirmed = NEW.is_confirmed)

       AND (OLD.total_fruit_cost = NEW.total_fruit_cost)

       AND (OLD.supplier_id IS NOT DISTINCT FROM NEW.supplier_id) THEN

      RETURN NEW;

    END IF;



    IF OLD.is_confirmed = true AND (NEW.is_confirmed = false OR NEW.is_confirmed IS NULL) THEN

      PERFORM public.sync_supplier_ledger_for_lot(OLD.id, 'DELETE');

    ELSIF NEW.is_confirmed = true AND (OLD.is_confirmed = false OR OLD.is_confirmed IS NULL) THEN

      PERFORM public.sync_supplier_ledger_for_lot(NEW.id, 'INSERT');

    ELSIF NEW.is_confirmed = true AND OLD.is_confirmed = true THEN

      IF (OLD.total_fruit_cost IS DISTINCT FROM NEW.total_fruit_cost)

         OR (OLD.supplier_id IS DISTINCT FROM NEW.supplier_id) THEN

        PERFORM public.sync_supplier_ledger_for_lot(NEW.id, 'UPDATE');

      END IF;

    END IF;

    RETURN NEW;

  END IF;



  IF TG_OP = 'INSERT' THEN

    IF NEW.is_confirmed = true THEN

      PERFORM public.sync_supplier_ledger_for_lot(NEW.id, 'INSERT');

    END IF;

    RETURN NEW;

  END IF;



  RETURN NEW;

END;

$$ LANGUAGE plpgsql;



-- Explicitly drop legacy/duplicate trigger names to prevent double firing

DROP TRIGGER IF EXISTS trg_on_lot_receipt_saved ON public.lot_receipts;

DROP TRIGGER IF EXISTS trg_on_harvest_receipt_saved ON public.lot_receipts;



CREATE TRIGGER trg_on_harvest_receipt_saved

  AFTER INSERT OR UPDATE OR DELETE ON public.lot_receipts

  FOR EACH ROW

  EXECUTE FUNCTION public.fn_on_harvest_receipt_saved();



-- Partial unique constraint index: only one active initial journal entry per lot receipt

CREATE UNIQUE INDEX IF NOT EXISTS uq_journal_entries_lot_receipt

  ON public.journal_entries(source_type, source_id)

  WHERE (source_type = 'lot_receipt' AND deleted_at IS NULL);



-- ── 4. Update rpc_get_lot_journal_entries Function ───────────────────────────

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

#variable_conflict use_column

DECLARE

  v_lot_number TEXT;

  v_linked_je_id BIGINT;

BEGIN

  SELECT lr.lot_number, lr.journal_entry_id 

  INTO v_lot_number, v_linked_je_id

  FROM public.lot_receipts lr 

  WHERE lr.id::TEXT = p_lot_id;



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

      -- 1. Explicit linkage via lot_receipts.journal_entry_id

      (v_linked_je_id IS NOT NULL AND je.id = v_linked_je_id)

      OR

      -- 2. lot_receipt entries (inventory)

      (je.source_type = 'lot_receipt' AND (je.source_id = p_lot_id OR (v_lot_number IS NOT NULL AND v_lot_number != '' AND je.source_id = v_lot_number)))

      OR

      -- 3. lot_price_adjustment entries

      (je.source_type = 'lot_price_adjustment' AND (je.source_id = p_lot_id OR (v_lot_number IS NOT NULL AND v_lot_number != '' AND je.source_id = v_lot_number)))

      OR

      -- 4. Explicit Crop Payment entries ONLY

      (je.source_type = 'crop_payment' AND (je.source_id = p_lot_id OR (v_lot_number IS NOT NULL AND v_lot_number != '' AND je.source_id = v_lot_number)))

    )

  ORDER BY je.id, je.created_at DESC;

END;

$$;



GRANT EXECUTE ON FUNCTION public.rpc_get_lot_journal_entries(TEXT) TO authenticated, service_role, anon;



-- ── 5. Backfill existing confirmed lots missing journal_entry_id ──────────────

DO $$

DECLARE

  r RECORD;

BEGIN

  FOR r IN 

    SELECT id FROM lot_receipts 

    WHERE is_confirmed = true 

      AND journal_entry_id IS NULL 

      AND COALESCE(total_fruit_cost, 0) > 0

  LOOP

    BEGIN

      PERFORM public.sync_supplier_ledger_for_lot(r.id, 'INSERT');

    EXCEPTION WHEN OTHERS THEN

      RAISE NOTICE 'Backfill lot % failed: %', r.id, SQLERRM;

    END;

  END LOOP;

END $$;



-- ==============================================================================

-- Migration 448: Automated Warehouse Stock Transfer Double-Entry Accounting

-- ==============================================================================



-- ── 1. Register Document Type ────────────────────────────────────────────────

INSERT INTO public.sys_document_types (code, name, prefix, is_active)

VALUES (

  'stock_transfer',

  'Warehouse Stock Transfer / تحويل مخزني بين المحطات',

  'WTR',

  true

)

ON CONFLICT (code) DO UPDATE SET

  prefix = EXCLUDED.prefix,

  name = EXCLUDED.name,

  is_active = true;



-- ── 2. Add Columns to stock_transfers ────────────────────────────────────────

ALTER TABLE public.stock_transfers

  ADD COLUMN IF NOT EXISTS journal_entry_id BIGINT REFERENCES public.journal_entries(id) ON DELETE SET NULL,

  ADD COLUMN IF NOT EXISTS unit_cost NUMERIC(19,4) DEFAULT 0,

  ADD COLUMN IF NOT EXISTS total_cost NUMERIC(19,4) DEFAULT 0,

  ADD COLUMN IF NOT EXISTS currency VARCHAR(10) DEFAULT 'EGP';



CREATE INDEX IF NOT EXISTS idx_stock_transfers_journal_entry_id

  ON public.stock_transfers(journal_entry_id);



-- ── 3. Add Optional inventory_account_id to stations ─────────────────────────

ALTER TABLE public.stations

  ADD COLUMN IF NOT EXISTS inventory_account_id BIGINT REFERENCES public.accounts(id) ON DELETE SET NULL;



-- ── 4. Enforce Partial Unique Index on journal_entries for stock_transfer ────

CREATE UNIQUE INDEX IF NOT EXISTS uq_journal_entries_stock_transfer

  ON public.journal_entries(source_type, source_id)

  WHERE (source_type = 'stock_transfer' AND deleted_at IS NULL);



-- ── 5. Core Function: process_stock_transfer_journal ─────────────────────────

CREATE OR REPLACE FUNCTION public.process_stock_transfer_journal(

  p_transfer_id BIGINT

)

RETURNS BIGINT

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path = public

AS $$

DECLARE

  v_transfer RECORD;

  v_from_station_name TEXT;

  v_to_station_name TEXT;

  v_from_station_acc_id BIGINT;

  v_to_station_acc_id BIGINT;

  v_from_account_id BIGINT;

  v_to_account_id BIGINT;

  v_company_id UUID;

  v_unit_cost NUMERIC;

  v_total_cost NUMERIC;

  v_exchange_rate NUMERIC := 1.0;

  v_total_cost_base NUMERIC;

  v_currency TEXT;

  v_je_id BIGINT;

  v_desc TEXT;

  v_debit_desc TEXT;

  v_credit_desc TEXT;

  v_is_packaging BOOLEAN := false;

BEGIN

  -- 1. Fetch stock transfer record

  SELECT * INTO v_transfer FROM public.stock_transfers WHERE id = p_transfer_id;

  IF NOT FOUND THEN

    RETURN NULL;

  END IF;



  IF COALESCE(v_transfer.quantity, 0) <= 0 THEN

    RETURN NULL;

  END IF;



  -- 2. Resolve Company

  SELECT id INTO v_company_id FROM public.sys_companies WHERE deleted_at IS NULL LIMIT 1;

  IF v_company_id IS NULL THEN

    SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;

  END IF;



  -- 3. Resolve Stations

  SELECT name, inventory_account_id INTO v_from_station_name, v_from_station_acc_id

  FROM public.stations WHERE id = v_transfer.from_station_id;



  SELECT name, inventory_account_id INTO v_to_station_name, v_to_station_acc_id

  FROM public.stations WHERE id = v_transfer.to_station_id;



  v_from_station_name := COALESCE(v_from_station_name, 'محطة #' || v_transfer.from_station_id);

  v_to_station_name := COALESCE(v_to_station_name, 'محطة #' || v_transfer.to_station_id);



  -- 4. Check whether this product is packaging / raw material or fruit / produce

  IF v_transfer.product_name ILIKE '%تعبئة%' 

     OR v_transfer.product_name ILIKE '%كرتون%' 

     OR v_transfer.product_name ILIKE '%شريط%' 

     OR v_transfer.product_name ILIKE '%زاوية%' 

     OR v_transfer.product_name ILIKE '%بانيت%'

     OR v_transfer.product_name ILIKE '%مادة%' THEN

    v_is_packaging := true;

  END IF;



  -- 5. Resolve Valuation (Unit Cost & Total Cost)

  v_unit_cost := COALESCE(v_transfer.unit_cost, 0);

  v_total_cost := COALESCE(v_transfer.total_cost, 0);

  v_currency := COALESCE(NULLIF(v_transfer.currency, ''), 'EGP');



  -- If total cost is zero, try to look up from transferred batches in destination

  IF v_total_cost <= 0 THEN

    SELECT COALESCE(SUM(quantity * unit_cost), 0),

           COALESCE(MAX(currency), 'EGP'),

           COALESCE(MAX(exchange_rate), 1.0)

    INTO v_total_cost, v_currency, v_exchange_rate

    FROM public.station_product_batches

    WHERE station_id = v_transfer.to_station_id

      AND source_type = 'transfer'

      AND (product_code = v_transfer.product_code OR product_name = v_transfer.product_name)

      AND created_at >= (v_transfer.created_at - INTERVAL '1 minute')

      AND created_at <= (v_transfer.created_at + INTERVAL '1 minute');



    IF v_total_cost > 0 AND v_transfer.quantity > 0 THEN

      v_unit_cost := v_total_cost / v_transfer.quantity;

    END IF;

  END IF;



  -- If still zero, attempt to get latest unit_cost from source batches

  IF v_total_cost <= 0 THEN

    SELECT COALESCE(unit_cost, 0), COALESCE(currency, 'EGP'), COALESCE(exchange_rate, 1.0)

    INTO v_unit_cost, v_currency, v_exchange_rate

    FROM public.station_product_batches

    WHERE station_id = v_transfer.from_station_id

      AND (product_code = v_transfer.product_code OR product_name = v_transfer.product_name)

      AND unit_cost > 0

    ORDER BY created_at DESC

    LIMIT 1;



    IF v_unit_cost > 0 THEN

      v_total_cost := v_unit_cost * v_transfer.quantity;

    END IF;

  END IF;



  -- If still zero, fallback to fruit_types or raw_materials default

  IF v_total_cost <= 0 THEN

    IF v_is_packaging THEN

      SELECT COALESCE(unit_cost, 1.0) INTO v_unit_cost

      FROM public.raw_materials

      WHERE name = v_transfer.product_name OR code = v_transfer.product_code

      LIMIT 1;

    ELSE

      SELECT COALESCE(target_unit_price, 10.0) INTO v_unit_cost

      FROM public.fruit_types

      WHERE name = v_transfer.product_name OR code = v_transfer.product_code

      LIMIT 1;

    END IF;



    v_unit_cost := COALESCE(v_unit_cost, 1.0);

    v_total_cost := v_unit_cost * v_transfer.quantity;

  END IF;



  v_exchange_rate := COALESCE(NULLIF(v_exchange_rate, 0), 1.0);

  v_total_cost_base := v_total_cost * v_exchange_rate;



  -- 6. Resolve Sending Account (Credit)

  v_from_account_id := NULL;

  IF v_from_station_acc_id IS NOT NULL THEN

    SELECT id INTO v_from_account_id FROM public.accounts WHERE id = v_from_station_acc_id AND is_leaf = true AND deleted_at IS NULL;

  END IF;



  IF v_from_account_id IS NULL THEN

    IF v_is_packaging THEN

      SELECT id INTO v_from_account_id FROM public.accounts WHERE account_code = '12411' AND is_leaf = true AND deleted_at IS NULL LIMIT 1;

    ELSE

      SELECT id INTO v_from_account_id FROM public.accounts WHERE account_code = '12412' AND is_leaf = true AND deleted_at IS NULL LIMIT 1;

    END IF;

  END IF;



  IF v_from_account_id IS NULL THEN

    SELECT id INTO v_from_account_id FROM public.accounts WHERE account_code LIKE '124%' AND is_leaf = true AND deleted_at IS NULL ORDER BY account_code ASC LIMIT 1;

  END IF;



  -- 7. Resolve Receiving Account (Debit)

  v_to_account_id := NULL;

  IF v_to_station_acc_id IS NOT NULL THEN

    SELECT id INTO v_to_account_id FROM public.accounts WHERE id = v_to_station_acc_id AND is_leaf = true AND deleted_at IS NULL;

  END IF;



  IF v_to_account_id IS NULL THEN

    IF v_is_packaging THEN

      SELECT id INTO v_to_account_id FROM public.accounts WHERE account_code = '12411' AND is_leaf = true AND deleted_at IS NULL LIMIT 1;

    ELSE

      SELECT id INTO v_to_account_id FROM public.accounts WHERE account_code = '12412' AND is_leaf = true AND deleted_at IS NULL LIMIT 1;

    END IF;

  END IF;



  IF v_to_account_id IS NULL THEN

    SELECT id INTO v_to_account_id FROM public.accounts WHERE account_code LIKE '124%' AND is_leaf = true AND deleted_at IS NULL ORDER BY account_code ASC LIMIT 1;

  END IF;



  IF v_from_account_id IS NULL OR v_to_account_id IS NULL THEN

    RAISE EXCEPTION 'لم يتم العثور على حسابات المخزون المناسبة للتحويل';

  END IF;



  -- 8. Idempotency Check: does a journal entry already exist?

  SELECT id INTO v_je_id

  FROM public.journal_entries

  WHERE source_type = 'stock_transfer'

    AND source_id = p_transfer_id::TEXT

    AND deleted_at IS NULL

  LIMIT 1;



  IF v_je_id IS NOT NULL THEN

    UPDATE public.stock_transfers

    SET journal_entry_id = v_je_id,

        unit_cost = v_unit_cost,

        total_cost = v_total_cost,

        currency = v_currency

    WHERE id = p_transfer_id;

    RETURN v_je_id;

  END IF;



  -- 9. Construct Descriptions

  v_desc := 'تحويل مخزني من ' || v_from_station_name || ' إلى ' || v_to_station_name || ' - ' || v_transfer.product_name;

  v_debit_desc := 'إثبات تحويل مخزني وارد إلى ' || v_to_station_name || ' من ' || v_from_station_name || ' (' || v_transfer.product_name || ' - ' || v_transfer.quantity || ')';

  v_credit_desc := 'إثبات تحويل مخزني منصرف من ' || v_from_station_name || ' إلى ' || v_to_station_name || ' (' || v_transfer.product_name || ' - ' || v_transfer.quantity || ')';



  -- 10. Post Balanced Double-Entry Journal Entry

  v_je_id := public.post_journal_entry(

    p_source_type := 'stock_transfer',

    p_description := v_desc,

    p_entry_date := v_transfer.created_at::DATE,

    p_company_id := v_company_id,

    p_created_by := NULL,

    p_lines := jsonb_build_array(

      -- Debit (من د/): Receiving Warehouse

      jsonb_build_object(

        'account_id', v_to_account_id,

        'debit', v_total_cost,

        'base_debit', v_total_cost_base,

        'credit', 0,

        'base_credit', 0,

        'currency', v_currency,

        'description', v_debit_desc

      ),

      -- Credit (إلى د/): Sending Warehouse

      jsonb_build_object(

        'account_id', v_from_account_id,

        'debit', 0,

        'base_debit', 0,

        'credit', v_total_cost,

        'base_credit', v_total_cost_base,

        'currency', v_currency,

        'description', v_credit_desc

      )

    ),

    p_source_id := p_transfer_id::TEXT

  );



  -- 11. Link Journal Entry back to stock_transfers

  UPDATE public.stock_transfers

  SET journal_entry_id = v_je_id,

      unit_cost = v_unit_cost,

      total_cost = v_total_cost,

      currency = v_currency

  WHERE id = p_transfer_id;



  RETURN v_je_id;

END;

$$;



-- ── 6. RPC Endpoint for Flutter / DAO ────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.rpc_process_stock_transfer_journal(

  p_transfer_id BIGINT

)

RETURNS JSONB

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path = public

AS $$

DECLARE

  v_je_id BIGINT;

  v_entry_number TEXT;

BEGIN

  v_je_id := public.process_stock_transfer_journal(p_transfer_id);



  IF v_je_id IS NOT NULL THEN

    SELECT entry_number INTO v_entry_number FROM public.journal_entries WHERE id = v_je_id;

    RETURN jsonb_build_object(

      'success', true,

      'journal_entry_id', v_je_id,

      'entry_number', v_entry_number

    );

  ELSE

    RETURN jsonb_build_object(

      'success', false,

      'error', 'فشل إنشاء قيد التحويل المخزني'

    );

  END IF;

EXCEPTION WHEN OTHERS THEN

  RETURN jsonb_build_object(

    'success', false,

    'error', SQLERRM

  );

END;

$$;



GRANT EXECUTE ON FUNCTION public.process_stock_transfer_journal(BIGINT) TO authenticated, service_role, anon;

GRANT EXECUTE ON FUNCTION public.rpc_process_stock_transfer_journal(BIGINT) TO authenticated, service_role, anon;



-- ── 7. Automatic DB Trigger on stock_transfers ───────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_on_stock_transfer_changed()

RETURNS TRIGGER AS $$

BEGIN

  IF TG_OP = 'DELETE' THEN

    IF OLD.journal_entry_id IS NOT NULL THEN

      DELETE FROM public.account_ledger_entries WHERE journal_entry_id = OLD.journal_entry_id;

      DELETE FROM public.journal_entries WHERE id = OLD.journal_entry_id;

    ELSE

      DELETE FROM public.account_ledger_entries WHERE journal_entry_id IN (

        SELECT id FROM public.journal_entries WHERE source_type = 'stock_transfer' AND source_id = OLD.id::TEXT

      );

      DELETE FROM public.journal_entries WHERE source_type = 'stock_transfer' AND source_id = OLD.id::TEXT;

    END IF;

    RETURN OLD;

  END IF;



  IF TG_OP = 'INSERT' THEN

    IF NEW.journal_entry_id IS NULL THEN

      PERFORM public.process_stock_transfer_journal(NEW.id);

    END IF;

    RETURN NEW;

  END IF;



  RETURN NEW;

END;

$$ LANGUAGE plpgsql;



DROP TRIGGER IF EXISTS trg_on_stock_transfer_changed ON public.stock_transfers;

CREATE TRIGGER trg_on_stock_transfer_changed

  AFTER INSERT OR DELETE ON public.stock_transfers

  FOR EACH ROW

  EXECUTE FUNCTION public.fn_on_stock_transfer_changed();



-- ── 8. Backfill existing transfers missing journal_entry_id ──────────────────

DO $$

DECLARE

  r RECORD;

BEGIN

  FOR r IN SELECT id FROM public.stock_transfers WHERE journal_entry_id IS NULL LOOP

    BEGIN

      PERFORM public.process_stock_transfer_journal(r.id);

    EXCEPTION WHEN OTHERS THEN

      RAISE NOTICE 'Backfill transfer % failed: %', r.id, SQLERRM;

    END;

  END LOOP;

END $$;



-- ==============================================================================

-- Migration 449: Universal Journal Entry Idempotency & Single Source of Truth

-- ==============================================================================



-- ── 1. Partial Unique Indexes on Active Journal Entries ──────────────────────

CREATE UNIQUE INDEX IF NOT EXISTS uq_journal_entries_lot_receipt

  ON public.journal_entries(source_type, source_id)

  WHERE (source_type = 'lot_receipt' AND deleted_at IS NULL);



CREATE UNIQUE INDEX IF NOT EXISTS uq_journal_entries_stock_transfer

  ON public.journal_entries(source_type, source_id)

  WHERE (source_type = 'stock_transfer' AND deleted_at IS NULL);



CREATE UNIQUE INDEX IF NOT EXISTS uq_journal_entries_purchase

  ON public.journal_entries(source_type, source_id)

  WHERE (source_type = 'purchase' AND deleted_at IS NULL);



CREATE UNIQUE INDEX IF NOT EXISTS uq_journal_entries_waste

  ON public.journal_entries(source_type, source_id)

  WHERE (source_type = 'waste' AND deleted_at IS NULL);



CREATE UNIQUE INDEX IF NOT EXISTS uq_journal_entries_sorting_sale

  ON public.journal_entries(source_type, source_id)

  WHERE (source_type = 'sorting_sale' AND deleted_at IS NULL);



-- ── 2. Core post_journal_entry with Universal Idempotency Guard ───────────────

CREATE OR REPLACE FUNCTION public.post_journal_entry(

    p_source_type   TEXT,

    p_description   TEXT,

    p_entry_date    DATE,

    p_company_id    UUID,

    p_created_by    UUID,

    p_lines         JSONB,

    p_source_id     TEXT DEFAULT NULL

) RETURNS BIGINT

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path = public

AS $$

DECLARE

    v_je_id         BIGINT;

    v_entry_number  TEXT;

    v_total_debit   NUMERIC := 0;

    v_total_credit  NUMERIC := 0;

    v_line          JSONB;

    v_account_id    BIGINT;

    v_debit         NUMERIC;

    v_credit        NUMERIC;

    v_base_debit    NUMERIC;

    v_base_credit   NUMERIC;

    v_currency      TEXT;

    v_desc          TEXT;

    v_actual_date   DATE;

    v_base_amount   NUMERIC;

BEGIN

    -- ── IDEMPOTENCY SAFEGUARD ────────────────────────────────────────────────

    -- If an active journal entry already exists for this (source_type, source_id),

    -- skip sequence generation and lines insertion; return existing ID immediately!

    IF p_source_type IS NOT NULL AND p_source_id IS NOT NULL 

       AND p_source_type NOT IN ('manual', 'adjustment', 'lot_price_adjustment') THEN

        SELECT id INTO v_je_id

        FROM public.journal_entries

        WHERE source_type = p_source_type

          AND source_id = p_source_id

          AND deleted_at IS NULL

        ORDER BY id ASC

        LIMIT 1;



        IF v_je_id IS NOT NULL THEN

            RETURN v_je_id;

        END IF;

    END IF;



    -- Auto-provision or resolve company_id

    IF p_company_id IS NULL THEN

        SELECT id INTO p_company_id FROM public.sys_companies WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 1;

    END IF;



    IF p_company_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.sys_companies WHERE id = p_company_id) THEN

        BEGIN

            INSERT INTO public.sys_companies (id, name, is_active, created_at, updated_at)

            VALUES (p_company_id, 'شركة النظام', true, now(), now())

            ON CONFLICT (id) DO UPDATE SET 

                is_active = true,

                updated_at = now();

        EXCEPTION WHEN OTHERS THEN

            SELECT id INTO p_company_id FROM public.sys_companies WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 1;

        END;

    END IF;



    IF p_company_id IS NULL THEN

        INSERT INTO public.sys_companies (name, is_active, created_at, updated_at)

        VALUES ('الشركة الافتراضية', true, now(), now())

        RETURNING id INTO p_company_id;

    END IF;



    -- Timezone safeguard: if p_entry_date is null or matches UTC CURRENT_DATE while local Cairo date is ahead

    v_actual_date := COALESCE(p_entry_date, (NOW() AT TIME ZONE 'Africa/Cairo')::DATE);

    IF p_entry_date = CURRENT_DATE AND (NOW() AT TIME ZONE 'Africa/Cairo')::DATE != CURRENT_DATE THEN

        v_actual_date := (NOW() AT TIME ZONE 'Africa/Cairo')::DATE;

    END IF;



    v_entry_number := public.fn_get_next_sequence(p_company_id, p_source_type, NULL, NULL);



    INSERT INTO journal_entries (

        entry_number, entry_date, description, status,

        is_auto_generated, source_type, source_id, created_by, company_id

    ) VALUES (

        v_entry_number, v_actual_date, p_description, 'posted',

        true, p_source_type, p_source_id, p_created_by, p_company_id

    ) RETURNING id INTO v_je_id;



    FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines)

    LOOP

        v_account_id := (v_line->>'account_id')::BIGINT;

        v_debit      := COALESCE((v_line->>'debit')::NUMERIC, 0);

        v_credit     := COALESCE((v_line->>'credit')::NUMERIC, 0);

        v_base_debit := COALESCE((v_line->>'base_debit')::NUMERIC, v_debit);

        v_base_credit:= COALESCE((v_line->>'base_credit')::NUMERIC, v_credit);

        v_currency   := COALESCE(v_line->>'currency', 'EGP');

        v_desc       := COALESCE(v_line->>'description', p_description);



        IF NOT EXISTS (SELECT 1 FROM accounts WHERE id = v_account_id) THEN

            RAISE EXCEPTION 'GL Account ID % not found in accounts table', v_account_id;

        END IF;



        IF v_debit > 0 AND v_credit > 0 THEN

            RAISE EXCEPTION 'Single line cannot have both debit and credit';

        END IF;



        IF v_debit = 0 AND v_credit = 0 THEN

            CONTINUE;

        END IF;



        v_total_debit  := v_total_debit + v_base_debit;

        v_total_credit := v_total_credit + v_base_credit;

        v_base_amount  := CASE WHEN v_debit > 0 THEN v_base_debit ELSE v_base_credit END;



        INSERT INTO account_ledger_entries (

            journal_entry_id, account_id, debit, credit,

            currency, amount_in_base_currency, description, company_id

        ) VALUES (

            v_je_id, v_account_id, v_debit, v_credit,

            v_currency, v_base_amount, v_desc, p_company_id

        );

    END LOOP;



    IF ABS(v_total_debit - v_total_credit) > 0.05 THEN

        RAISE EXCEPTION 'Journal entry unbalanced in base currency: Total Base Debit = %, Total Base Credit = %', v_total_debit, v_total_credit;

    END IF;



    RETURN v_je_id;

END;

$$;



GRANT EXECUTE ON FUNCTION public.post_journal_entry(TEXT, TEXT, DATE, UUID, UUID, JSONB, TEXT) TO authenticated, service_role, anon;



-- ── 3. Reinforced sync_supplier_ledger_for_lot Idempotency ────────────────────

CREATE OR REPLACE FUNCTION public.sync_supplier_ledger_for_lot(

  p_lot_id BIGINT,

  p_action TEXT DEFAULT 'INSERT'

)

RETURNS VOID

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path = public

AS $$

DECLARE

  v_lot RECORD;

  v_company_id UUID;

  v_inventory_account_id BIGINT;

  v_supplier_leaf_account_id BIGINT;

  v_supplier_name TEXT;

  v_je_id BIGINT;

  v_desc TEXT;

  v_total_cost NUMERIC;

  v_product_name TEXT;

  v_lot_number TEXT;

  v_old_base_debit NUMERIC;

  v_old_supplier_credit NUMERIC;

  v_diff NUMERIC;

BEGIN

  -- 1. Fetch Lot details

  SELECT * INTO v_lot FROM public.lot_receipts WHERE id = p_lot_id;

  IF NOT FOUND THEN

    RETURN;

  END IF;



  v_total_cost := COALESCE(v_lot.total_fruit_cost, 0);

  v_product_name := COALESCE(v_lot.product_name, 'محصول');

  v_lot_number := COALESCE(v_lot.lot_number, p_lot_id::TEXT);



  -- 2. Resolve Company

  IF v_lot.supplier_id IS NOT NULL THEN

    SELECT company_id, name INTO v_company_id, v_supplier_name

    FROM public.suppliers WHERE id = v_lot.supplier_id;

  END IF;

  IF v_company_id IS NULL THEN

    SELECT id INTO v_company_id FROM public.sys_companies WHERE deleted_at IS NULL LIMIT 1;

  END IF;

  IF v_company_id IS NULL THEN

    SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;

  END IF;



  -- 3. Resolve Inventory Account (12412 Raw Produce Inventory - مخزن مشتريات خام)

  SELECT id INTO v_inventory_account_id

  FROM public.accounts

  WHERE account_code = '12412' AND is_leaf = true AND deleted_at IS NULL

  LIMIT 1;



  IF v_inventory_account_id IS NULL THEN

    SELECT id INTO v_inventory_account_id

    FROM public.accounts

    WHERE account_code = '1241' AND deleted_at IS NULL

    LIMIT 1;

  END IF;



  IF v_inventory_account_id IS NULL THEN

    SELECT id INTO v_inventory_account_id

    FROM public.accounts

    WHERE account_code LIKE '124%' AND is_leaf = true AND deleted_at IS NULL

    ORDER BY account_code ASC

    LIMIT 1;

  END IF;



  -- 4. Resolve Supplier Leaf Account under 2111 (or legacy 2112)

  IF v_lot.supplier_id IS NOT NULL THEN

    SELECT account_id INTO v_supplier_leaf_account_id

    FROM public.suppliers WHERE id = v_lot.supplier_id;

  END IF;



  IF v_supplier_leaf_account_id IS NULL AND v_lot.supplier_id IS NOT NULL THEN

    SELECT id INTO v_supplier_leaf_account_id

    FROM public.accounts

    WHERE (account_code LIKE '2111%' OR account_code LIKE '2112%') AND is_leaf = true AND deleted_at IS NULL

      AND account_name ILIKE '%' || v_supplier_name || '%'

    ORDER BY CASE WHEN account_code LIKE '2111%' THEN 1 ELSE 2 END, id ASC

    LIMIT 1;

  END IF;



  IF v_supplier_leaf_account_id IS NULL THEN

    SELECT id INTO v_supplier_leaf_account_id

    FROM public.accounts

    WHERE (account_code LIKE '2111%' OR account_code LIKE '2112%') AND is_leaf = true AND deleted_at IS NULL

    ORDER BY CASE WHEN account_code LIKE '2111%' THEN 1 ELSE 2 END, account_code ASC

    LIMIT 1;

  END IF;



  -- 5. IDEMPOTENCY SAFEGUARD FOR LOT

  SELECT id INTO v_je_id

  FROM public.journal_entries

  WHERE source_type = 'lot_receipt'

    AND source_id = p_lot_id::TEXT

    AND deleted_at IS NULL

  ORDER BY id ASC

  LIMIT 1;



  IF v_je_id IS NOT NULL THEN

    IF v_lot.journal_entry_id IS DISTINCT FROM v_je_id THEN

      UPDATE public.lot_receipts

      SET journal_entry_id = v_je_id

      WHERE id = p_lot_id;

    END IF;



    -- Exit immediately on INSERT if already present to completely eliminate duplicates

    IF p_action != 'UPDATE' THEN

      RETURN;

    END IF;

  END IF;



  -- 6. Price adjustment on UPDATE

  IF p_action = 'UPDATE' AND (v_lot.journal_entry_id IS NOT NULL OR v_je_id IS NOT NULL) THEN

    SELECT COALESCE(SUM(amount_in_base_currency * CASE WHEN debit > 0 THEN 1 WHEN credit > 0 THEN -1 ELSE 0 END), 0)

    INTO v_old_base_debit

    FROM public.account_ledger_entries

    WHERE journal_entry_id IN (

       SELECT id FROM public.journal_entries 

       WHERE source_type IN ('lot_receipt', 'lot_price_adjustment') AND source_id = p_lot_id::TEXT

    ) AND account_id = v_inventory_account_id;



    v_diff := v_total_cost - v_old_base_debit;

    IF ABS(v_diff) > 0.01 THEN

      v_desc := 'تسوية سعر شراء محصول ' || v_product_name || ' - تشغيلة ' || v_lot_number;

      IF v_diff > 0 THEN

        PERFORM public.post_journal_entry(

          p_source_type := 'lot_price_adjustment',

          p_description := v_desc,

          p_entry_date := COALESCE(v_lot.receipt_date, CURRENT_DATE),

          p_company_id := v_company_id,

          p_created_by := NULL,

          p_lines := jsonb_build_array(

            jsonb_build_object('account_id', v_inventory_account_id, 'debit', v_diff, 'base_debit', v_diff, 'credit', 0, 'base_credit', 0, 'currency', 'EGP', 'description', v_desc),

            jsonb_build_object('account_id', v_supplier_leaf_account_id, 'debit', 0, 'base_debit', 0, 'credit', v_diff, 'base_credit', v_diff, 'currency', 'EGP', 'description', v_desc)

          ),

          p_source_id := p_lot_id::TEXT

        );

      ELSE

        PERFORM public.post_journal_entry(

          p_source_type := 'lot_price_adjustment',

          p_description := v_desc,

          p_entry_date := COALESCE(v_lot.receipt_date, CURRENT_DATE),

          p_company_id := v_company_id,

          p_created_by := NULL,

          p_lines := jsonb_build_array(

            jsonb_build_object('account_id', v_supplier_leaf_account_id, 'debit', ABS(v_diff), 'base_debit', ABS(v_diff), 'credit', 0, 'base_credit', 0, 'currency', 'EGP', 'description', v_desc),

            jsonb_build_object('account_id', v_inventory_account_id, 'debit', 0, 'base_debit', 0, 'credit', ABS(v_diff), 'base_credit', ABS(v_diff), 'currency', 'EGP', 'description', v_desc)

          ),

          p_source_id := p_lot_id::TEXT

        );

      END IF;



      IF v_lot.supplier_id IS NOT NULL THEN

        UPDATE public.suppliers

        SET outstanding_balance = GREATEST(0, COALESCE(outstanding_balance, 0) + v_diff)

        WHERE id = v_lot.supplier_id;

      END IF;

    END IF;

    RETURN;

  END IF;



  -- 7. Initial Balanced Double-Entry for Lot Receipt

  IF v_total_cost > 0 AND v_inventory_account_id IS NOT NULL AND v_supplier_leaf_account_id IS NOT NULL THEN

    v_desc := 'إثبات شراء محصول ' || v_product_name || ' - تشغيلة ' || v_lot_number;

    v_je_id := public.post_journal_entry(

      p_source_type := 'lot_receipt',

      p_description := v_desc,

      p_entry_date := COALESCE(v_lot.receipt_date, CURRENT_DATE),

      p_company_id := v_company_id,

      p_created_by := NULL,

      p_lines := jsonb_build_array(

        jsonb_build_object(

          'account_id', v_inventory_account_id,

          'debit', v_total_cost,

          'base_debit', v_total_cost,

          'credit', 0,

          'base_credit', 0,

          'currency', COALESCE(v_lot.currency, 'EGP'),

          'description', 'إثبات مخزون محصول وارد - تشغيلة ' || v_lot_number

        ),

        jsonb_build_object(

          'account_id', v_supplier_leaf_account_id,

          'debit', 0,

          'base_debit', 0,

          'credit', v_total_cost,

          'base_credit', v_total_cost,

          'currency', COALESCE(v_lot.currency, 'EGP'),

          'description', 'مستحقات مورد عن محصول - تشغيلة ' || v_lot_number

        )

      ),

      p_source_id := p_lot_id::TEXT

    );



    UPDATE public.lot_receipts

    SET journal_entry_id = v_je_id

    WHERE id = p_lot_id;



    IF v_lot.supplier_id IS NOT NULL THEN

      UPDATE public.suppliers

      SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_total_cost

      WHERE id = v_lot.supplier_id;

    END IF;

  END IF;

END;

$$;



-- ============================================================================

-- ENFORCE SUPPLIER CATEGORY RANGES & SHARED SUPPLIERS (MIGRATION 450 PARITY)

-- ============================================================================



DO $$

BEGIN

    IF NOT EXISTS (

        SELECT 1 

        FROM information_schema.columns 

        WHERE table_schema = 'public' 

          AND table_name = 'suppliers' 

          AND column_name = 'supplier_type'

    ) THEN

        ALTER TABLE public.suppliers 

        ADD COLUMN supplier_type VARCHAR(20) NOT NULL DEFAULT 'crop';

    END IF;



    ALTER TABLE public.suppliers DROP CONSTRAINT IF EXISTS suppliers_supplier_type_check;

    ALTER TABLE public.suppliers

    ADD CONSTRAINT suppliers_supplier_type_check 

    CHECK (supplier_type IN ('crop', 'packaging', 'shared', 'station', 'deduction', 'deductions', 'transport'));



    ALTER TABLE public.suppliers ADD COLUMN IF NOT EXISTS categories text[] DEFAULT '{}';

END $$;



CREATE OR REPLACE FUNCTION public.trg_fn_validate_supplier_category_code_range()

RETURNS trigger

LANGUAGE plpgsql

AS $$

DECLARE

  v_code_num INTEGER;

BEGIN

  IF NEW.code ~ '^[0-9]+$' THEN

    v_code_num := NEW.code::INTEGER;

    -- Preserve existing legacy codes (< 1000) safely

    IF v_code_num < 1000 THEN

      RETURN NEW;

    END IF;

  ELSE

    RETURN NEW;

  END IF;



  CASE NEW.supplier_type

    WHEN 'crop' THEN

      IF v_code_num < 50000 OR v_code_num > 59999 THEN

        RAISE EXCEPTION 'كود مورد المحاصيل غير صالح: (%) يجب أن يكون بين 50000 و 59999 (سعة: 10000 سجل)', NEW.code;

      END IF;



    WHEN 'transport' THEN

      IF v_code_num < 60000 OR v_code_num > 69999 THEN

        RAISE EXCEPTION 'كود مورد النقل غير صالح: (%) يجب أن يكون بين 60000 و 69999 (سعة: 10000 سجل)', NEW.code;

      END IF;



    WHEN 'packaging' THEN

      IF v_code_num < 70000 OR v_code_num > 74999 THEN

        RAISE EXCEPTION 'كود مورد مواد التعبئة والتغليف غير صالح: (%) يجب أن يكون بين 70000 و 74999 (سعة: 5000 سجل)', NEW.code;

      END IF;



    WHEN 'shared' THEN

      IF v_code_num < 75000 OR v_code_num > 79999 THEN

        RAISE EXCEPTION 'كود المورد المشترك غير صالح: (%) يجب أن يكون في النطاق 75000 إلى 79999 لمنع التداخل (سعة: 5000 سجل)', NEW.code;

      END IF;



    WHEN 'station' THEN

      IF v_code_num < 85000 OR v_code_num > 89999 THEN

        RAISE EXCEPTION 'كود مورد المحطة غير صالح: (%) يجب أن يكون في النطاق 85000 إلى 89999 (سعة: 5000 سجل)', NEW.code;

      END IF;



    WHEN 'deduction', 'deductions' THEN

      IF v_code_num < 40000 OR v_code_num > 49999 THEN

        RAISE EXCEPTION 'كود مورد التخصيمات غير صالح: (%) يجب أن يكون في النطاق 40000 إلى 49999 (سعة: 10000 سجل)', NEW.code;

      END IF;



    ELSE

      -- Default allow

  END CASE;



  RETURN NEW;

END;

$$;



DROP TRIGGER IF EXISTS trg_validate_supplier_code_range ON public.suppliers;

CREATE TRIGGER trg_validate_supplier_code_range

BEFORE INSERT OR UPDATE OF code, supplier_type ON public.suppliers

FOR EACH ROW

EXECUTE FUNCTION public.trg_fn_validate_supplier_category_code_range();



CREATE OR REPLACE FUNCTION public.trg_fn_validate_transport_supplier_code_range()

RETURNS trigger

LANGUAGE plpgsql

AS $$

DECLARE

  v_code_num INTEGER;

BEGIN

  IF NEW.code ~ '^[0-9]+$' THEN

    v_code_num := NEW.code::INTEGER;

    IF v_code_num < 1000 THEN

      RETURN NEW;

    END IF;

    IF v_code_num < 60000 OR v_code_num > 69999 THEN

      RAISE EXCEPTION 'كود مورد النقل غير صالح: (%) يجب أن يكون بين 60000 و 69999 (سعة: 10000 سجل)', NEW.code;

    END IF;

  END IF;

  RETURN NEW;

END;

$$;



DROP TRIGGER IF EXISTS trg_validate_transport_code_range ON public.transport_suppliers;

CREATE TRIGGER trg_validate_transport_code_range

BEFORE INSERT OR UPDATE OF code ON public.transport_suppliers

FOR EACH ROW

EXECUTE FUNCTION public.trg_fn_validate_transport_supplier_code_range();



CREATE OR REPLACE FUNCTION public.trg_fn_validate_station_code_range()

RETURNS trigger

LANGUAGE plpgsql

AS $$

DECLARE

  v_code_num INTEGER;

BEGIN

  IF NEW.code ~ '^[0-9]+$' THEN

    v_code_num := NEW.code::INTEGER;

    IF v_code_num < 1000 THEN

      RETURN NEW;

    END IF;

    IF v_code_num < 80000 OR v_code_num > 89999 THEN

      RAISE EXCEPTION 'كود المحطة غير صالح: (%) يجب أن يكون بين 80000 و 89999 (سعة: 10000 سجل)', NEW.code;

    END IF;

  END IF;

  RETURN NEW;

END;

$$;



DROP TRIGGER IF EXISTS trg_validate_station_code_range ON public.stations;

CREATE TRIGGER trg_validate_station_code_range

BEFORE INSERT OR UPDATE OF code ON public.stations

FOR EACH ROW

EXECUTE FUNCTION public.trg_fn_validate_station_code_range();



CREATE OR REPLACE FUNCTION public.trg_fn_validate_shipping_company_code_range()

RETURNS trigger

LANGUAGE plpgsql

AS $$

DECLARE

  v_code_num INTEGER;

BEGIN

  IF NEW.code ~ '^[0-9]+$' THEN

    v_code_num := NEW.code::INTEGER;

    IF v_code_num < 1000 THEN

      RETURN NEW;

    END IF;

    IF v_code_num < 90000 OR v_code_num > 99999 THEN

      RAISE EXCEPTION 'كود شركة الشحن غير صالح: (%) يجب أن يكون بين 90000 و 99999 (سعة: 10000 سجل)', NEW.code;

    END IF;

  END IF;

  RETURN NEW;

END;

$$;



DROP TRIGGER IF EXISTS trg_validate_shipping_code_range ON public.shipping_companies;

CREATE TRIGGER trg_validate_shipping_code_range

BEFORE INSERT OR UPDATE OF code ON public.shipping_companies

FOR EACH ROW

EXECUTE FUNCTION public.trg_fn_validate_shipping_company_code_range();



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

    WHEN 'customer'                                  THEN v_pattern := '^1251[0-9]+$'; v_start := 125100;

    WHEN 'supplier', 'crop_supplier', 'crop',

         'shipping_company', 'clearing_agent',

         'packaging_supplier', 'packaging', 'station',

         'shared_supplier', 'shared',

         'transport_supplier', 'transport'           THEN v_pattern := '^2111[0-9]+$'; v_start := 211100;

    WHEN 'notes_payable', 'note_payable'             THEN v_pattern := '^2112[0-9]+$'; v_start := 211200;

    WHEN 'shareholder'                               THEN v_pattern := '^2321[0-9]+$'; v_start := 232100;

    WHEN 'custody', 'employee_custody', 'temporary_custody' THEN v_pattern := '^12612[0-9]+$'; v_start := 1261200;

    WHEN 'permanent_custody'                         THEN v_pattern := '^12613[0-9]+$'; v_start := 1261300;

    ELSE RAISE EXCEPTION 'Unknown entity type: %', p_entity_type;

  END CASE;



  LOOP

    SELECT COALESCE(MAX(account_code::bigint), v_start) + 1 INTO v_next

    FROM public.accounts

    WHERE account_code ~ v_pattern;



    IF v_next <= v_start THEN

      v_next := v_start + 1;

    END IF;



    v_code := v_next::TEXT;



    EXIT WHEN NOT EXISTS (

      SELECT 1 FROM public.accounts WHERE account_code = v_code

    );



    v_start := v_next;

  END LOOP;



  RETURN v_code;

END;

$$;



COMMIT;



-- ==============================================================================

-- Migration 453: Cost Center Transactions Ledger & Synchronization for Crop Purchases

-- ==============================================================================

BEGIN;



-- ── 1. Create cost_center_transactions table ──────────────────────────────────

CREATE TABLE IF NOT EXISTS public.cost_center_transactions (

  id BIGSERIAL PRIMARY KEY,

  cost_center_id TEXT NOT NULL,

  cost_center_name TEXT,

  cost_center_type TEXT DEFAULT 'variety', -- 'variety' or 'operational'

  source_type TEXT NOT NULL DEFAULT 'crop_purchase', -- 'crop_purchase', 'lot_receipt', 'packing_order'

  source_id TEXT,

  transaction_date DATE NOT NULL DEFAULT CURRENT_DATE,

  supplier_id TEXT,

  supplier_name TEXT,

  product_id BIGINT,

  item_name TEXT NOT NULL,

  category TEXT NOT NULL DEFAULT 'تكلفة المحاصيل',

  quantity NUMERIC NOT NULL DEFAULT 0,

  unit_price NUMERIC NOT NULL DEFAULT 0,

  currency TEXT NOT NULL DEFAULT 'EGP',

  exchange_rate NUMERIC NOT NULL DEFAULT 1.0,

  total_in_currency NUMERIC NOT NULL DEFAULT 0,

  amount NUMERIC NOT NULL DEFAULT 0, -- Total in local currency (EGP)

  notes TEXT,

  is_confirmed BOOLEAN DEFAULT TRUE,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()

);



-- Indexing for high performance querying & reporting

CREATE INDEX IF NOT EXISTS idx_cct_cost_center_id ON public.cost_center_transactions(cost_center_id);

CREATE INDEX IF NOT EXISTS idx_cct_date ON public.cost_center_transactions(transaction_date);

CREATE INDEX IF NOT EXISTS idx_cct_source ON public.cost_center_transactions(source_type, source_id);



-- Unique index to prevent duplicate transaction entries per source

CREATE UNIQUE INDEX IF NOT EXISTS uq_cct_source ON public.cost_center_transactions(source_type, source_id);



-- ── 2. Enable Row Level Security (RLS) ─────────────────────────────────────────

ALTER TABLE public.cost_center_transactions ENABLE ROW LEVEL SECURITY;



DO $$ 

BEGIN

  IF NOT EXISTS (

    SELECT 1 FROM pg_policies WHERE tablename = 'cost_center_transactions' AND policyname = 'Allow all authenticated to cost_center_transactions'

  ) THEN

    CREATE POLICY "Allow all authenticated to cost_center_transactions" ON public.cost_center_transactions FOR ALL TO authenticated USING (true) WITH CHECK (true);

  END IF;



  IF NOT EXISTS (

    SELECT 1 FROM pg_policies WHERE tablename = 'cost_center_transactions' AND policyname = 'Allow all service_role to cost_center_transactions'

  ) THEN

    CREATE POLICY "Allow all service_role to cost_center_transactions" ON public.cost_center_transactions FOR ALL TO service_role USING (true) WITH CHECK (true);

  END IF;



  IF NOT EXISTS (

    SELECT 1 FROM pg_policies WHERE tablename = 'cost_center_transactions' AND policyname = 'Allow read anon to cost_center_transactions'

  ) THEN

    CREATE POLICY "Allow read anon to cost_center_transactions" ON public.cost_center_transactions FOR SELECT TO anon USING (true);

  END IF;

END $$;



-- ── 3. تصفير كامل لمراكز التكلفة ومعاملاتها ─────────────────────────────────

-- العميل هو من ينشئ مراكز التكلفة حسب احتياجاته من واجهة التطبيق

DELETE FROM public.cost_center_transactions;

DELETE FROM public.cost_centers;



-- ── 4. تثبيت تريجر المزامنة التلقائية لمراكز التكلفة عند تسجيل استلام لوط مستقبلاً ──

CREATE OR REPLACE FUNCTION public.fn_sync_lot_receipt_cost_center_transaction()

RETURNS TRIGGER AS $$

DECLARE

  v_ft_code TEXT;

  v_ft_name TEXT;

  v_supplier_name TEXT;

  v_unit_price NUMERIC;

  v_amount NUMERIC;

  v_cc_id TEXT;

  v_ex_rate NUMERIC;

BEGIN

  -- Lookup fruit type details

  SELECT code, name INTO v_ft_code, v_ft_name

  FROM public.fruit_types

  WHERE id = NEW.fruit_type_id;



  v_cc_id := 'CC-' || COALESCE(v_ft_code, NEW.fruit_type_id::text);



  -- Lookup supplier name

  SELECT name INTO v_supplier_name

  FROM public.suppliers

  WHERE id::text = NEW.supplier_id::text;



  v_ex_rate := COALESCE(NEW.exchange_rate, 1.0);

  IF v_ex_rate <= 0 THEN

    v_ex_rate := 1.0;

  END IF;



  v_amount := ROUND((NEW.total_fruit_cost * v_ex_rate)::numeric, 2);

  v_unit_price := ROUND((v_amount / NULLIF(NEW.gross_weight_kg, 0))::numeric, 2);



  INSERT INTO public.cost_center_transactions (

    cost_center_id,

    cost_center_name,

    cost_center_type,

    source_type,

    source_id,

    transaction_date,

    supplier_id,

    supplier_name,

    product_id,

    item_name,

    category,

    quantity,

    unit_price,

    currency,

    exchange_rate,

    total_in_currency,

    amount,

    notes,

    is_confirmed

  ) VALUES (

    v_cc_id,

    COALESCE(NEW.product_name, v_ft_name, 'محصول'),

    'variety',

    'lot_receipt',

    NEW.id::text,

    NEW.receipt_date::date,

    NEW.supplier_id::text,

    v_supplier_name,

    NEW.fruit_type_id,

    COALESCE(NEW.product_name, v_ft_name, 'محصول'),

    'تكلفة المحاصيل',

    NEW.gross_weight_kg,

    v_unit_price,

    COALESCE(NEW.currency, 'EGP'),

    v_ex_rate,

    ROUND(NEW.total_fruit_cost::numeric, 2),

    v_amount,

    NEW.notes,

    COALESCE(NEW.is_confirmed, TRUE)

  )

  ON CONFLICT (source_type, source_id) DO UPDATE SET

    cost_center_id = EXCLUDED.cost_center_id,

    cost_center_name = EXCLUDED.cost_center_name,

    transaction_date = EXCLUDED.transaction_date,

    supplier_id = EXCLUDED.supplier_id,

    supplier_name = EXCLUDED.supplier_name,

    product_id = EXCLUDED.product_id,

    item_name = EXCLUDED.item_name,

    quantity = EXCLUDED.quantity,

    unit_price = EXCLUDED.unit_price,

    currency = EXCLUDED.currency,

    exchange_rate = EXCLUDED.exchange_rate,

    total_in_currency = EXCLUDED.total_in_currency,

    amount = EXCLUDED.amount,

    notes = EXCLUDED.notes,

    is_confirmed = EXCLUDED.is_confirmed,

    updated_at = NOW();



  RETURN NEW;

END;

$$ LANGUAGE plpgsql;



DROP TRIGGER IF EXISTS trg_lot_receipts_cost_center_transaction ON public.lot_receipts;

CREATE TRIGGER trg_lot_receipts_cost_center_transaction

AFTER INSERT OR UPDATE OF fruit_type_id, product_name, supplier_id, gross_weight_kg, total_fruit_cost, exchange_rate, receipt_date, is_confirmed

ON public.lot_receipts

FOR EACH ROW EXECUTE FUNCTION public.fn_sync_lot_receipt_cost_center_transaction();



COMMIT;



NOTIFY pgrst, 'reload schema';



-- ============================================================================

-- Migration 442: Multi-Currency Supplier Balances & Account 2112 EGP Rollup

-- ============================================================================

-- Purpose:

--   1. get_supplier_true_balances_by_currency()

--      Returns per-currency outstanding balances for every supplier so the

--      Flutter KPI strip can display native amounts without cross-currency mixing.

--

--   2. v_account_2112_egp_rollup (VIEW)

--      Aggregates all confirmed ledger activity under account code 2112

--      (حـ/ دائنون - مواد خام ومحاصيل) and converts each entry's currency to

--      EGP using the latest rate in exchange_rates.  Used by Trial Balance,

--      Balance Sheet and parent-level GL roll-ups.

-- ============================================================================



-- ── 1. Per-currency supplier balance RPC ─────────────────────────────────────



CREATE OR REPLACE FUNCTION public.get_supplier_true_balances_by_currency()

RETURNS TABLE (

    supplier_id        uuid,

    supplier_code      text,

    supplier_name      text,

    currency           text,

    true_balance       numeric,   -- native currency amount

    true_balance_egp   numeric    -- converted to EGP using latest rate

)

LANGUAGE sql

SECURITY DEFINER

STABLE

AS $func$

  WITH rates AS (

    SELECT DISTINCT ON (currency_code) currency_code, rate_to_egp 

    FROM (

      SELECT currency_code, rate_to_egp, updated_at FROM exchange_rates

      UNION ALL

      SELECT 'EGP'::character varying(10), 1.0::numeric(10,4), NOW()

    ) r_all

    ORDER BY currency_code, updated_at DESC NULLS LAST

  ),

  -- 1. Initial Balances

  init_balances AS (

    -- Multi-currency suppliers with initial_balances_by_currency

    SELECT 

      s.id AS supplier_id,

      UPPER(COALESCE(elem.value->>'currency', elem.key)) AS currency,

      COALESCE((elem.value->>'amount')::numeric, 0) * (CASE WHEN UPPER(COALESCE(elem.value->>'direction', 'CREDIT')) = 'DEBIT' THEN -1 ELSE 1 END) AS net_amt

    FROM suppliers s,

    LATERAL jsonb_each(s.initial_balances_by_currency) elem

    WHERE s.is_multi_currency = true 

      AND s.initial_balances_by_currency IS NOT NULL 

      AND jsonb_typeof(s.initial_balances_by_currency) = 'object'

      AND COALESCE((elem.value->>'amount')::numeric, 0) > 0

    

    UNION ALL

    

    -- Single-currency suppliers or multi without JSON map

    SELECT 

      s.id AS supplier_id,

      COALESCE(NULLIF(s.currency, ''), 'EGP') AS currency,

      COALESCE(s.initial_balance, 0) * (CASE WHEN s.initial_balance_direction = 'DEBIT' THEN -1 ELSE 1 END) AS net_amt

    FROM suppliers s

    WHERE (s.is_multi_currency = false OR s.initial_balances_by_currency IS NULL OR s.initial_balances_by_currency = '{}'::jsonb)

      AND COALESCE(s.initial_balance, 0) <> 0

  ),

  

  -- 2. Purchase Invoices (credit to supplier: increases payable)

  purchases AS (

    SELECT 

      supplier_id,

      COALESCE(NULLIF(currency, ''), 'EGP') AS currency,

      SUM(total_amount) AS net_amt

    FROM purchase_invoices

    WHERE status = 'confirmed' AND supplier_id IS NOT NULL

    GROUP BY supplier_id, COALESCE(NULLIF(currency, ''), 'EGP')

  ),

  

  -- 3. Treasury Transactions (payments to supplier and supplier advance deposits reduce liability: -amount)

  treasury AS (

    SELECT 

      supplier_id,

      COALESCE(NULLIF(currency, ''), 'EGP') AS currency,

      -SUM(amount) AS net_amt

    FROM treasury_transactions

    WHERE supplier_id IS NOT NULL 

      AND (status = 'confirmed' OR status IS NULL)

    GROUP BY supplier_id, COALESCE(NULLIF(currency, ''), 'EGP')

  ),

  

  -- 4. Bank Account Transactions (payments to supplier and supplier advance deposits reduce liability: -amount)

  bank_tx AS (

    SELECT 

      s.id AS supplier_id,

      COALESCE(NULLIF(ba.currency, ''), 'EGP') AS currency,

      -SUM(bat.amount) AS net_amt

    FROM bank_account_transactions bat

    JOIN suppliers s ON (s.id::text = bat.entity_id OR s.code = bat.entity_id OR s.supplier_code = bat.entity_id)

    LEFT JOIN bank_accounts ba ON ba.id = bat.bank_account_id

    WHERE bat.entity_type = 'supplier' 

      AND (bat.status = 'confirmed' OR bat.status IS NULL)

    GROUP BY s.id, COALESCE(NULLIF(ba.currency, ''), 'EGP')

  ),

  

  -- 5. Cheques (cheques linked to supplier reduce liability: -amount)

  cheque_tx AS (

    SELECT 

      supplier_id,

      COALESCE(NULLIF(currency, ''), 'EGP') AS currency,

      -SUM(amount) AS net_amt

    FROM cheques

    WHERE supplier_id IS NOT NULL 

      AND status IN ('cleared', 'collected')

    GROUP BY supplier_id, COALESCE(NULLIF(currency, ''), 'EGP')

  ),

  

  -- 6. Lot Receipts / Enterprise Account Ledger Entries (excluding lot_returns to avoid double counting with direct purchase_returns below)

  lot_tx AS (

    SELECT 

      s.id AS supplier_id,

      COALESCE(NULLIF(ale.currency, ''), 'EGP') AS currency,

      SUM(ale.credit - ale.debit) AS net_amt

    FROM account_ledger_entries ale

    JOIN journal_entries je ON je.id = ale.journal_entry_id

    JOIN suppliers s ON s.account_id = ale.account_id

    WHERE je.source_type IN ('lot_receipt','lot_adjustment','lot_price_adjustment','manual')

    GROUP BY s.id, COALESCE(NULLIF(ale.currency, ''), 'EGP')

  ),

  

  -- 7. Purchase Returns / Lot Returns (reduces supplier payable)

  purchase_returns AS (

    SELECT 

      lr.supplier_id,

      COALESCE(NULLIF(rec.currency, ''), COALESCE(NULLIF(s.crop_currency, ''), COALESCE(NULLIF(s.currency, ''), 'EGP'))) AS currency,

      -SUM(lr.return_value) AS net_amt

    FROM lot_returns lr

    LEFT JOIN lot_receipts rec ON rec.id = lr.lot_receipt_id

    JOIN suppliers s ON s.id = lr.supplier_id

    WHERE lr.supplier_id IS NOT NULL

    GROUP BY lr.supplier_id, COALESCE(NULLIF(rec.currency, ''), COALESCE(NULLIF(s.crop_currency, ''), COALESCE(NULLIF(s.currency, ''), 'EGP')))

  ),



  -- 8. Standalone Purchase Returns from Ledger Entries (if any not linked to lot_returns)

  ledger_returns AS (

    SELECT 

      s.id AS supplier_id,

      COALESCE(NULLIF(le.currency, ''), 'EGP') AS currency,

      -SUM(le.amount) AS net_amt

    FROM ledger_entries le

    JOIN suppliers s ON (s.id::text = le.entity_id OR s.code = le.entity_id OR s.supplier_code = le.entity_id)

    WHERE le.entity_type = 'supplier'

      AND le.reference_type = 'purchase_return'

    GROUP BY s.id, COALESCE(NULLIF(le.currency, ''), 'EGP')

  ),

  

  -- Combine all activity

  combined AS (

    SELECT supplier_id, currency, net_amt FROM init_balances

    UNION ALL

    SELECT supplier_id, currency, net_amt FROM purchases

    UNION ALL

    SELECT supplier_id, currency, net_amt FROM treasury

    UNION ALL

    SELECT supplier_id, currency, net_amt FROM bank_tx

    UNION ALL

    SELECT supplier_id, currency, net_amt FROM cheque_tx

    UNION ALL

    SELECT supplier_id, currency, net_amt FROM lot_tx

    UNION ALL

    SELECT supplier_id, currency, net_amt FROM purchase_returns

    UNION ALL

    SELECT supplier_id, currency, net_amt FROM ledger_returns

  ),

  

  aggregated AS (

    SELECT 

      supplier_id,

      currency,

      SUM(net_amt) AS true_balance

    FROM combined

    GROUP BY supplier_id, currency

    HAVING SUM(net_amt) <> 0

  )

  

  SELECT 

    s.id AS supplier_id,

    COALESCE(s.code, s.supplier_code, '') AS supplier_code,

    s.name AS supplier_name,

    a.currency,

    a.true_balance,

    a.true_balance * COALESCE(r.rate_to_egp, 1.0) AS true_balance_egp

  FROM aggregated a

  JOIN suppliers s ON s.id = a.supplier_id

  LEFT JOIN rates r ON r.currency_code = a.currency;

$func$;



GRANT EXECUTE ON FUNCTION public.get_supplier_true_balances_by_currency()

  TO authenticated, anon, service_role;



-- ── 2. Account 2112 — EGP Roll-up View ────────────────────────────────────────

-- Aggregates all confirmed journal activity under the 2112 sub-tree and converts

-- every entry to EGP using the most recent rate in exchange_rates.

--

-- This view is consumed by:

--   • Trial Balance builder  (total debit / credit in EGP)

--   • Balance Sheet rollup   (net balance EGP under Liabilities tree)

--   • Supplier Payables KPI  (total payables EGP across all currencies)

-- ─────────────────────────────────────────────────────────────────────────────



CREATE OR REPLACE VIEW public.v_account_2112_egp_rollup AS

WITH latest_rates AS (

    -- One rate row per currency; EGP is always 1.0

    SELECT currency_code, rate_to_egp

    FROM (

        SELECT currency_code, rate_to_egp,

               ROW_NUMBER() OVER (PARTITION BY currency_code ORDER BY updated_at DESC NULLS LAST) AS rn

        FROM exchange_rates

    ) sub

    WHERE rn = 1

    UNION ALL

    SELECT 'EGP', 1.0

),

account_tree AS (

    -- All accounts whose code starts with 2112 (the sub-tree)

    SELECT id, account_code, name

    FROM accounts

    WHERE account_code LIKE '2112%' OR account_code = '2112'

),

ledger_activity AS (

    -- All confirmed journal lines under the 2112 sub-tree

    SELECT

        ale.account_id,

        a.account_code,

        a.name            AS account_name,

        COALESCE(NULLIF(ale.currency,''), 'EGP') AS entry_currency,

        ale.debit         AS debit_native,

        ale.credit        AS credit_native,

        je.entry_date,

        je.source_type,

        je.source_id      AS reference_id,

        je.description    AS notes

    FROM account_ledger_entries ale

    JOIN journal_entries je ON je.id = ale.journal_entry_id

    JOIN account_tree a     ON a.id  = ale.account_id

    WHERE je.status = 'posted'

)

SELECT

    la.account_id,

    la.account_code,

    la.account_name,

    la.entry_currency,

    COALESCE(r.rate_to_egp, 1.0)            AS rate_to_egp,

    la.debit_native,

    la.credit_native,

    la.debit_native  * COALESCE(r.rate_to_egp, 1.0) AS debit_egp,

    la.credit_native * COALESCE(r.rate_to_egp, 1.0) AS credit_egp,

    (la.credit_native - la.debit_native)

        * COALESCE(r.rate_to_egp, 1.0)      AS net_balance_egp,

    la.entry_date,

    la.source_type,

    la.reference_id,

    la.notes

FROM ledger_activity la

LEFT JOIN latest_rates r ON r.currency_code = la.entry_currency;



-- Convenience aggregate view (one row per account under 2112)

CREATE OR REPLACE VIEW public.v_account_2112_summary_egp AS

SELECT

    account_id,

    account_code,

    account_name,

    entry_currency,

    rate_to_egp,

    SUM(debit_native)    AS total_debit_native,

    SUM(credit_native)   AS total_credit_native,

    SUM(debit_egp)       AS total_debit_egp,

    SUM(credit_egp)      AS total_credit_egp,

    SUM(net_balance_egp) AS net_balance_egp

FROM v_account_2112_egp_rollup

GROUP BY account_id, account_code, account_name, entry_currency, rate_to_egp

ORDER BY account_code, entry_currency;



-- Grand total across all 2112 sub-accounts (EGP-converted)

CREATE OR REPLACE VIEW public.v_account_2112_total_egp AS

SELECT

    SUM(debit_egp)       AS grand_debit_egp,

    SUM(credit_egp)      AS grand_credit_egp,

    SUM(net_balance_egp) AS grand_net_egp

FROM v_account_2112_egp_rollup;



GRANT SELECT ON public.v_account_2112_egp_rollup        TO authenticated, anon, service_role;

GRANT SELECT ON public.v_account_2112_summary_egp       TO authenticated, anon, service_role;

GRANT SELECT ON public.v_account_2112_total_egp         TO authenticated, anon, service_role;



-- ── 3. Helper: aggregate payables EGP for Trial Balance ───────────────────────



CREATE OR REPLACE FUNCTION public.get_account_2112_balance_egp()

RETURNS TABLE (

    total_debit_egp   numeric,

    total_credit_egp  numeric,

    net_balance_egp   numeric    -- positive = credit-heavy (normal for payables)

)

LANGUAGE sql

SECURITY DEFINER

STABLE

AS $func$

    SELECT grand_debit_egp, grand_credit_egp, grand_net_egp

    FROM v_account_2112_total_egp;

$func$;



GRANT EXECUTE ON FUNCTION public.get_account_2112_balance_egp()

  TO authenticated, anon, service_role;



NOTIFY pgrst, 'reload_schema';



-- ============================================================================

-- Migration 454: Generalized Multi-Currency Support for All Suppliers

-- ============================================================================

-- Purpose:

--   1. Allow ANY supplier category (crop, packaging, shared, etc.) to support

--      multi-currency transactions (USD, EUR, GBP, EGP).

--   2. Add columns to public.suppliers:

--      - is_multi_currency (BOOLEAN DEFAULT false)

--      - supported_currencies (TEXT[] DEFAULT ARRAY['EGP', 'USD', 'EUR'])

--      - crop_currency (VARCHAR(10) DEFAULT 'USD')

--      - packaging_currency (VARCHAR(10) DEFAULT 'EGP')

--   3. Keep standard suppliers defaulted to single-currency EGP unless toggled on.

--   4. Ensure shared suppliers default to multi-currency enabled.

-- ============================================================================



DO $$

BEGIN

    -- 1. Multi-currency flag

    IF NOT EXISTS (

        SELECT 1 FROM information_schema.columns 

        WHERE table_schema = 'public' AND table_name = 'suppliers' AND column_name = 'is_multi_currency'

    ) THEN

        ALTER TABLE public.suppliers 

        ADD COLUMN is_multi_currency BOOLEAN NOT NULL DEFAULT false;

    END IF;



    -- 2. Supported currencies array

    IF NOT EXISTS (

        SELECT 1 FROM information_schema.columns 

        WHERE table_schema = 'public' AND table_name = 'suppliers' AND column_name = 'supported_currencies'

    ) THEN

        ALTER TABLE public.suppliers 

        ADD COLUMN supported_currencies TEXT[] DEFAULT ARRAY['EGP', 'USD', 'EUR'];

    END IF;



    -- 3. Dynamic default currencies based on purchase stream

    IF NOT EXISTS (

        SELECT 1 FROM information_schema.columns 

        WHERE table_schema = 'public' AND table_name = 'suppliers' AND column_name = 'crop_currency'

    ) THEN

        ALTER TABLE public.suppliers 

        ADD COLUMN crop_currency VARCHAR(10) DEFAULT 'USD';

    END IF;



    IF NOT EXISTS (

        SELECT 1 FROM information_schema.columns 

        WHERE table_schema = 'public' AND table_name = 'suppliers' AND column_name = 'packaging_currency'

    ) THEN

        ALTER TABLE public.suppliers 

        ADD COLUMN packaging_currency VARCHAR(10) DEFAULT 'EGP';

    END IF;



    -- 4. Multi-currency initial balance storage columns

    IF NOT EXISTS (

        SELECT 1 FROM information_schema.columns 

        WHERE table_schema = 'public' AND table_name = 'suppliers' AND column_name = 'initial_balance_snapshot'

    ) THEN

        ALTER TABLE public.suppliers 

        ADD COLUMN initial_balance_snapshot JSONB DEFAULT '{}'::jsonb;

    END IF;



    IF NOT EXISTS (

        SELECT 1 FROM information_schema.columns 

        WHERE table_schema = 'public' AND table_name = 'suppliers' AND column_name = 'initial_balances_by_currency'

    ) THEN

        ALTER TABLE public.suppliers 

        ADD COLUMN initial_balances_by_currency JSONB DEFAULT '{}'::jsonb;

    END IF;



    IF NOT EXISTS (

        SELECT 1 FROM information_schema.columns 

        WHERE table_schema = 'public' AND table_name = 'suppliers' AND column_name = 'current_balances_by_currency'

    ) THEN

        ALTER TABLE public.suppliers 

        ADD COLUMN current_balances_by_currency JSONB DEFAULT '{}'::jsonb;

    END IF;

END $$;



-- 5. Automatically configure shared suppliers as multi-currency by default,

-- while keeping standard crop/packaging suppliers with their existing single currency

-- unless explicitly updated by the user.

UPDATE public.suppliers

SET 

    is_multi_currency = true,

    currency = 'MULTI',

    supported_currencies = ARRAY['EGP', 'USD', 'EUR', 'GBP'],

    crop_currency = COALESCE(crop_currency, 'USD'),

    packaging_currency = COALESCE(packaging_currency, 'EGP')

WHERE supplier_type = 'shared' AND (is_multi_currency IS NULL OR is_multi_currency = false);



-- 6. Central Resolver for Opening Balance Equity Account

-- Supports 4-Level Chart of Accounts (2331-2334), migration 343 accounts (3901-3904),

-- capital accounts (2311-2314), and legacy accounts (3001-3004).

CREATE OR REPLACE FUNCTION public.resolve_opening_balance_equity_account(

    p_currency TEXT,

    p_company_id UUID DEFAULT NULL

)

RETURNS BIGINT

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path TO 'public'

AS $$

DECLARE

    v_acct BIGINT;

BEGIN

    -- 1. المحاولة بحساب فروق الأرصدة الافتتاحية المخصص (23421) أولاً

    SELECT id INTO v_acct

    FROM public.accounts

    WHERE account_code = '23421'

      AND (p_company_id IS NULL OR company_id = p_company_id OR company_id IS NULL OR company_id = 'a0000000-0000-0000-0000-000000000001'::uuid)

    ORDER BY (company_id IS NOT NULL AND company_id = p_company_id) DESC, id ASC

    LIMIT 1;



    IF v_acct IS NOT NULL THEN

        RETURN v_acct;

    END IF;



    -- 2. احتياطي في حال عدم وجوده: الأرباح والخسائر المرحلة (23411) أو الاحتياطي القانوني (23311)

    SELECT id INTO v_acct

    FROM public.accounts

    WHERE account_code IN ('23411', '23311', '23111', '2341', '2331', '2311')

      AND (p_company_id IS NULL OR company_id = p_company_id OR company_id IS NULL OR company_id = 'a0000000-0000-0000-0000-000000000001'::uuid)

    ORDER BY (company_id IS NOT NULL AND company_id = p_company_id) DESC, 

             CASE account_code WHEN '23411' THEN 1 WHEN '23311' THEN 2 WHEN '23111' THEN 3 ELSE 4 END

    LIMIT 1;



    IF v_acct IS NOT NULL THEN

        RETURN v_acct;

    END IF;



    -- 3. احتياطي: أي حساب حقوق ملكية نشط ويقبل الترحيل

    SELECT id INTO v_acct

    FROM public.accounts

    WHERE account_type = 'equity'

      AND (allow_posting = true OR is_leaf = true)

      AND (p_company_id IS NULL OR company_id = p_company_id OR company_id IS NULL OR company_id = 'a0000000-0000-0000-0000-000000000001'::uuid)

    ORDER BY (company_id IS NOT NULL AND company_id = p_company_id) DESC, id ASC

    LIMIT 1;



    IF v_acct IS NOT NULL THEN

        RETURN v_acct;

    END IF;



    -- 4. احتياطي مطلق: حساب 23421 أو 2342 دون أي تقييد على الشركة

    SELECT id INTO v_acct

    FROM public.accounts

    WHERE account_code IN ('23421', '2342', '2331', '3001')

    ORDER BY (account_code = '23421') DESC, id ASC

    LIMIT 1;



    RETURN v_acct;

END;

$$;



CREATE OR REPLACE FUNCTION public.resolve_opening_balance_equity_account(

    p_currency TEXT,

    p_company_id TEXT

)

RETURNS BIGINT

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path TO 'public'

AS $$

BEGIN

    RETURN public.resolve_opening_balance_equity_account(p_currency, NULLIF(p_company_id, '')::UUID);

EXCEPTION WHEN OTHERS THEN

    RETURN public.resolve_opening_balance_equity_account(p_currency, NULL::UUID);

END;

$$;



-- 7. Update sync_entity_opening_balance_gl to support multi-currency supplier opening balances

CREATE OR REPLACE FUNCTION public.sync_entity_opening_balance_gl()

RETURNS TRIGGER

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path TO 'public'

AS $$

DECLARE

    v_equity_account_id BIGINT;

    v_je_id BIGINT;

    v_desc TEXT;

    v_account_id BIGINT;

    v_company_id UUID;

    v_new_balance NUMERIC;

    v_direction TEXT;

    v_currency TEXT;

    v_source_id TEXT;

    v_entry_number TEXT;

    v_new_json JSONB;

    v_old_json JSONB;

    v_is_multi BOOLEAN := false;

    v_balances_map JSONB := NULL;

    r_key TEXT;

    r_item JSONB;

    r_cur TEXT;

    r_amt NUMERIC;

    r_dir TEXT;

    r_rate NUMERIC;

    r_base_amt NUMERIC;

    r_has_entries BOOLEAN := false;

    v_base_balance NUMERIC;

BEGIN

    v_new_json := to_jsonb(NEW);

    IF TG_OP = 'UPDATE' THEN

        v_old_json := to_jsonb(OLD);

    END IF;



    -- Check if initial_balance or direction or multi-currency map changed on UPDATE

    IF TG_OP = 'UPDATE' THEN

        IF TG_TABLE_NAME = 'shareholders' THEN

            IF (v_new_json->>'initial_balance_egp') IS NOT DISTINCT FROM (v_old_json->>'initial_balance_egp') 

               AND (v_new_json->>'initial_balance_usd') IS NOT DISTINCT FROM (v_old_json->>'initial_balance_usd')

               AND (v_new_json->>'initial_balance_eur') IS NOT DISTINCT FROM (v_old_json->>'initial_balance_eur')

               AND (v_new_json->>'initial_balance_gbp') IS NOT DISTINCT FROM (v_old_json->>'initial_balance_gbp')

               AND (v_new_json->>'initial_balance_direction') IS NOT DISTINCT FROM (v_old_json->>'initial_balance_direction')

               AND (v_new_json->>'initial_balance_direction_egp') IS NOT DISTINCT FROM (v_old_json->>'initial_balance_direction_egp')

               AND (v_new_json->>'account_id') IS NOT DISTINCT FROM (v_old_json->>'account_id') THEN

                RETURN NEW;

            END IF;

        ELSIF TG_TABLE_NAME = 'suppliers' THEN

            IF (v_new_json->>'initial_balance') IS NOT DISTINCT FROM (v_old_json->>'initial_balance') 

               AND (v_new_json->>'initial_balance_direction') IS NOT DISTINCT FROM (v_old_json->>'initial_balance_direction')

               AND (v_new_json->'initial_balances_by_currency') IS NOT DISTINCT FROM (v_old_json->'initial_balances_by_currency')

               AND (v_new_json->>'account_id') IS NOT DISTINCT FROM (v_old_json->>'account_id') THEN

                RETURN NEW;

            END IF;

        ELSE

            IF (v_new_json->>'initial_balance') IS NOT DISTINCT FROM (v_old_json->>'initial_balance') 

               AND (v_new_json->>'initial_balance_direction') IS NOT DISTINCT FROM (v_old_json->>'initial_balance_direction')

               AND (v_new_json->>'account_id') IS NOT DISTINCT FROM (v_old_json->>'account_id') THEN

                RETURN NEW;

            END IF;

        END IF;

    END IF;



    -- Extract balance & description by table

    IF TG_TABLE_NAME = 'shareholders' THEN

        v_new_balance := COALESCE((v_new_json->>'initial_balance_egp')::numeric, 0);

        v_desc := 'رصيد افتتاحي - ' || COALESCE(v_new_json->>'name', '');

    ELSIF TG_TABLE_NAME = 'customers' THEN

        v_new_balance := COALESCE((v_new_json->>'initial_balance')::numeric, 0);

        v_desc := 'رصيد افتتاحي - ' || COALESCE(v_new_json->>'name', '');

    ELSIF TG_TABLE_NAME = 'clearing_agents' THEN

        v_new_balance := COALESCE((v_new_json->>'initial_balance')::numeric, 0);

        v_desc := 'رصيد افتتاحي - ' || COALESCE(v_new_json->>'name', '');

    ELSIF TG_TABLE_NAME = 'shipping_companies' THEN

        v_new_balance := COALESCE((v_new_json->>'initial_balance')::numeric, 0);

        v_desc := 'رصيد افتتاحي - ' || COALESCE(v_new_json->>'name', '');

    ELSIF TG_TABLE_NAME = 'transport_suppliers' THEN

        v_new_balance := COALESCE((v_new_json->>'initial_balance')::numeric, 0);

        v_desc := 'رصيد افتتاحي - ' || COALESCE(v_new_json->>'name', '');

    ELSIF TG_TABLE_NAME = 'suppliers' THEN

        v_new_balance := COALESCE((v_new_json->>'initial_balance')::numeric, 0);

        v_desc := 'رصيد أول المدة للمورد: ' || COALESCE(v_new_json->>'name', '');

    ELSE

        v_new_balance := COALESCE((v_new_json->>'initial_balance')::numeric, 0);

        v_desc := 'رصيد افتتاحي - ' || COALESCE(v_new_json->>'name', '');

    END IF;



    IF (v_new_json->>'account_id') IS NOT NULL THEN

        v_account_id := (v_new_json->>'account_id')::bigint;

    END IF;

    IF (v_new_json->>'company_id') IS NOT NULL THEN

        v_company_id := (v_new_json->>'company_id')::uuid;

    END IF;

    

    -- Direction default

    IF TG_TABLE_NAME = 'customers' THEN

        v_direction := COALESCE(v_new_json->>'initial_balance_direction', 'DEBIT');

    ELSIF TG_TABLE_NAME = 'shareholders' THEN

        v_direction := COALESCE(v_new_json->>'initial_balance_direction_egp', v_new_json->>'initial_balance_direction', 'CREDIT');

    ELSE

        v_direction := COALESCE(v_new_json->>'initial_balance_direction', 'CREDIT');

    END IF;

    

    -- Extract currency

    v_currency := UPPER(COALESCE(v_new_json->>'currency', 'EGP'));

    IF v_currency = '' OR v_currency = 'MULTI' THEN

        v_currency := 'EGP';

    END IF;



    -- Resolve account_id if missing

    IF v_account_id IS NULL THEN

        IF TG_TABLE_NAME = 'customers' THEN

            SELECT id INTO v_account_id FROM accounts 

            WHERE (

                (COALESCE(v_new_json->>'company_type', v_new_json->>'customer_type', 'export') IN ('local', 'محلي', 'local_customer', 'عملاء محلي') AND account_code = '12512')

                OR (COALESCE(v_new_json->>'company_type', v_new_json->>'customer_type', 'export') NOT IN ('local', 'محلي', 'local_customer', 'عملاء محلي') AND account_code = '12511')

                OR account_code IN ('12511', '12512', '1251')

            )

              AND (company_id = v_company_id OR company_id IS NULL) 

            ORDER BY (company_id = v_company_id) DESC, id ASC 

            LIMIT 1;

        ELSIF TG_TABLE_NAME = 'suppliers' THEN

            -- Resolve exact Level-5 account based on supplier_type, category, or code range

            IF (v_new_json->>'supplier_type' IN ('packaging', 'sticker')

                OR v_new_json->>'category' IN ('packaging', 'مواد تعبئة', 'تعبئة', 'كرتون', 'استيكر')

                OR (v_new_json->>'code')::text LIKE '70%' OR (v_new_json->>'code')::text LIKE '71%'

                OR (v_new_json->>'code')::text LIKE '72%' OR (v_new_json->>'code')::text LIKE '73%'

                OR (v_new_json->>'code')::text LIKE '74%') THEN

                SELECT id INTO v_account_id FROM accounts WHERE account_code = '21112' AND (company_id = v_company_id OR company_id IS NULL) ORDER BY (company_id = v_company_id) DESC, id ASC LIMIT 1;

            ELSIF (v_new_json->>'supplier_type' IN ('shared')

                OR v_new_json->>'category' IN ('shared', 'مشترك', 'مشتركين')

                OR (v_new_json->>'code')::text LIKE '75%' OR (v_new_json->>'code')::text LIKE '76%'

                OR (v_new_json->>'code')::text LIKE '77%' OR (v_new_json->>'code')::text LIKE '78%'

                OR (v_new_json->>'code')::text LIKE '79%') THEN

                SELECT id INTO v_account_id FROM accounts WHERE account_code = '21114' AND (company_id = v_company_id OR company_id IS NULL) ORDER BY (company_id = v_company_id) DESC, id ASC LIMIT 1;

            ELSIF (v_new_json->>'supplier_type' IN ('transport') OR (v_new_json->>'code')::text LIKE '6%') THEN

                SELECT id INTO v_account_id FROM accounts WHERE account_code = '21111' AND (company_id = v_company_id OR company_id IS NULL) ORDER BY (company_id = v_company_id) DESC, id ASC LIMIT 1;

            ELSIF (v_new_json->>'supplier_type' IN ('shipping') OR (v_new_json->>'code')::text LIKE '9%') THEN

                SELECT id INTO v_account_id FROM accounts WHERE account_code = '21115' AND (company_id = v_company_id OR company_id IS NULL) ORDER BY (company_id = v_company_id) DESC, id ASC LIMIT 1;

            ELSIF (v_new_json->>'supplier_type' IN ('clearing', 'customs')) THEN

                SELECT id INTO v_account_id FROM accounts WHERE account_code = '21116' AND (company_id = v_company_id OR company_id IS NULL) ORDER BY (company_id = v_company_id) DESC, id ASC LIMIT 1;

            ELSE

                -- Default: Crop Purchase Suppliers (50000-59999)

                SELECT id INTO v_account_id FROM accounts WHERE account_code = '21113' AND (company_id = v_company_id OR company_id IS NULL) ORDER BY (company_id = v_company_id) DESC, id ASC LIMIT 1;

            END IF;



            IF v_account_id IS NULL THEN

                SELECT id INTO v_account_id FROM accounts WHERE account_code IN ('21113', '2111', '2110') AND (company_id = v_company_id OR company_id IS NULL) ORDER BY (company_id = v_company_id) DESC, id ASC LIMIT 1;

            END IF;

        ELSIF TG_TABLE_NAME = 'clearing_agents' THEN

            SELECT id INTO v_account_id FROM accounts 

            WHERE account_code = '21116'

              AND (company_id = v_company_id OR company_id IS NULL) 

            ORDER BY (company_id = v_company_id) DESC, id ASC 

            LIMIT 1;

        ELSIF TG_TABLE_NAME = 'shipping_companies' THEN

            SELECT id INTO v_account_id FROM accounts 

            WHERE account_code = '21115'

              AND (company_id = v_company_id OR company_id IS NULL) 

            ORDER BY (company_id = v_company_id) DESC, id ASC 

            LIMIT 1;

        ELSIF TG_TABLE_NAME = 'transport_suppliers' THEN

            SELECT id INTO v_account_id FROM accounts 

            WHERE account_code = '21111'

              AND (company_id = v_company_id OR company_id IS NULL) 

            ORDER BY (company_id = v_company_id) DESC, id ASC 

            LIMIT 1;

        END IF;

    END IF;



    IF v_account_id IS NULL THEN

        RETURN NEW;

    END IF;



    -- Unique source_id per table to prevent entity collision

    v_source_id := TG_TABLE_NAME || '_' || (v_new_json->>'id');



    -- Check for existing journal entry for this entity

    SELECT id INTO v_je_id

    FROM journal_entries

    WHERE source_type::text = 'opening_balance' 

      AND (source_id::text = v_source_id OR source_id::text = (v_new_json->>'id'))

      AND (company_id = v_company_id OR company_id IS NULL)

    ORDER BY id DESC

    LIMIT 1;



    -- Setup Multi-Currency branch (Suppliers or Shareholders)

    IF TG_TABLE_NAME = 'suppliers' THEN

        v_is_multi := COALESCE((v_new_json->>'is_multi_currency')::boolean, false);

        v_balances_map := v_new_json->'initial_balances_by_currency';

    ELSIF TG_TABLE_NAME = 'shareholders' THEN

        v_is_multi := true;

        v_balances_map := jsonb_build_object(

            'EGP', jsonb_build_object('amount', COALESCE((v_new_json->>'initial_balance_egp')::numeric, 0), 'direction', COALESCE(v_new_json->>'initial_balance_direction_egp', v_new_json->>'initial_balance_direction', 'CREDIT')),

            'USD', jsonb_build_object('amount', COALESCE((v_new_json->>'initial_balance_usd')::numeric, 0), 'direction', COALESCE(v_new_json->>'initial_balance_direction', 'CREDIT')),

            'EUR', jsonb_build_object('amount', COALESCE((v_new_json->>'initial_balance_eur')::numeric, 0), 'direction', COALESCE(v_new_json->>'initial_balance_direction', 'CREDIT')),

            'GBP', jsonb_build_object('amount', COALESCE((v_new_json->>'initial_balance_gbp')::numeric, 0), 'direction', COALESCE(v_new_json->>'initial_balance_direction', 'CREDIT'))

        );

    END IF;



    IF (TG_TABLE_NAME = 'suppliers' AND v_is_multi = true AND v_balances_map IS NOT NULL AND jsonb_typeof(v_balances_map) = 'object')

       OR (TG_TABLE_NAME = 'shareholders' AND v_balances_map IS NOT NULL) THEN

        

        -- Check if any balance is non-zero

        FOR r_key, r_item IN SELECT * FROM jsonb_each(v_balances_map) LOOP

            IF COALESCE((r_item->>'amount')::numeric, 0) > 0 THEN

                r_has_entries := true;

            END IF;

        END LOOP;



        IF NOT r_has_entries THEN

            IF v_je_id IS NOT NULL THEN

                DELETE FROM account_ledger_entries WHERE journal_entry_id = v_je_id;

                DELETE FROM journal_entries WHERE id = v_je_id;

            END IF;

            RETURN NEW;

        END IF;



        IF v_je_id IS NOT NULL THEN

            DELETE FROM account_ledger_entries WHERE journal_entry_id = v_je_id;

            UPDATE journal_entries 

            SET description = v_desc,

                source_id = v_source_id,

                entry_date = CURRENT_DATE,

                status = 'posted'

            WHERE id = v_je_id;

        ELSE

            -- Deterministic sequence without race conditions

            v_entry_number := public.fn_get_next_sequence(v_company_id, 'opening_balance', NULL, NULL);

            IF v_entry_number IS NULL OR v_entry_number = '' THEN

                RAISE EXCEPTION 'Failed to generate entry_number via fn_get_next_sequence for opening_balance (company_id: %)', v_company_id;

            END IF;



            INSERT INTO journal_entries (

                source_type, source_id, entry_date, description, created_by, company_id, entry_number, status

            ) VALUES (

                'opening_balance', v_source_id, CURRENT_DATE, v_desc, auth.uid(), v_company_id, v_entry_number, 'posted'

            ) RETURNING id INTO v_je_id;

        END IF;



        -- Insert ledger entries for each currency with non-zero balance

        FOR r_key, r_item IN SELECT * FROM jsonb_each(v_balances_map) LOOP

            r_cur := UPPER(COALESCE(r_item->>'currency', r_key));

            r_amt := COALESCE((r_item->>'amount')::numeric, 0);

            r_dir := UPPER(COALESCE(r_item->>'direction', 'CREDIT'));

            

            -- Deterministic exchange rate lookup

            IF r_cur = 'EGP' THEN

                r_rate := 1.0;

            ELSE

                r_rate := COALESCE((r_item->>'exchange_rate')::numeric, NULL);

                IF r_rate IS NULL OR r_rate <= 0 THEN

                    SELECT rate_to_egp INTO r_rate 

                    FROM exchange_rates 

                    WHERE currency_code = r_cur 

                    ORDER BY effective_from DESC, updated_at DESC, id DESC 

                    LIMIT 1;

                END IF;

                IF r_rate IS NULL OR r_rate <= 0 THEN r_rate := 1.0; END IF;

            END IF;



            r_base_amt := r_amt * r_rate;



            IF r_amt > 0 THEN

                -- Resolve corresponding equity account

                v_equity_account_id := public.resolve_opening_balance_equity_account(r_cur, v_company_id);



                IF v_equity_account_id IS NULL THEN

                    SELECT id INTO v_equity_account_id

                    FROM accounts

                    WHERE account_code::text = ANY(

                        CASE r_cur

                            WHEN 'USD' THEN ARRAY['23421', '2332', '3902', '2312', '3002']

                            WHEN 'EUR' THEN ARRAY['23421', '2333', '3903', '2313', '3003']

                            WHEN 'GBP' THEN ARRAY['23421', '2334', '3904', '2314', '3004']

                            ELSE ARRAY['23421', '2331', '3901', '2311', '3001']

                        END

                    )

                    AND (company_id = v_company_id OR company_id IS NULL)

                    ORDER BY (company_id = v_company_id) DESC, id ASC

                    LIMIT 1;

                END IF;



                IF v_equity_account_id IS NULL THEN

                    SELECT id INTO v_equity_account_id

                    FROM accounts

                    WHERE account_code::text IN ('23421', '2342', '2330', '233', '2310', '231', '3900', '3901', '3001', '3000', '3300')

                      AND (company_id = v_company_id OR company_id IS NULL)

                    ORDER BY (company_id = v_company_id) DESC, id ASC

                    LIMIT 1;

                END IF;



                IF v_equity_account_id IS NULL THEN

                    SELECT id INTO v_equity_account_id

                    FROM accounts

                    WHERE account_type = 'equity' AND (allow_posting = true OR is_leaf = true)

                      AND (company_id = v_company_id OR company_id IS NULL)

                    ORDER BY (company_id = v_company_id) DESC, id ASC

                    LIMIT 1;

                END IF;



                -- Insert balanced double-entry lines

                IF v_account_id IS NOT NULL AND v_equity_account_id IS NOT NULL THEN

                    IF r_dir = 'DEBIT' THEN

                        INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)

                        VALUES (v_je_id, v_account_id, r_amt, 0, r_cur, r_base_amt, v_desc || ' (' || r_cur || ')', v_company_id);

                        INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)

                        VALUES (v_je_id, v_equity_account_id, 0, r_amt, r_cur, r_base_amt, v_desc || ' (' || r_cur || ')', v_company_id);

                    ELSE

                        INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)

                        VALUES (v_je_id, v_account_id, 0, r_amt, r_cur, r_base_amt, v_desc || ' (' || r_cur || ')', v_company_id);

                        INSERT INTO account_ledger_entries (journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id)

                        VALUES (v_je_id, v_equity_account_id, r_amt, 0, r_cur, r_base_amt, v_desc || ' (' || r_cur || ')', v_company_id);

                    END IF;

                END IF;

            END IF;

        END LOOP;



        RETURN NEW;

    END IF;



    -- =========================================================================

    -- Standard single-currency path (Customers, Clearing, Shipping, Transport, Single-currency Suppliers)

    -- =========================================================================

    v_equity_account_id := public.resolve_opening_balance_equity_account(v_currency, v_company_id);



    IF v_equity_account_id IS NULL THEN

        SELECT id INTO v_equity_account_id

        FROM accounts

        WHERE account_code::text = ANY(

            CASE v_currency

                WHEN 'USD' THEN ARRAY['23421', '2332', '3902', '2312', '3002']

                WHEN 'EUR' THEN ARRAY['23421', '2333', '3903', '2313', '3003']

                WHEN 'GBP' THEN ARRAY['23421', '2334', '3904', '2314', '3004']

                ELSE ARRAY['23421', '2331', '3901', '2311', '3001']

            END

        )

        AND (company_id = v_company_id OR company_id IS NULL)

        ORDER BY (company_id = v_company_id) DESC, id ASC

        LIMIT 1;

    END IF;



    IF v_equity_account_id IS NULL THEN

        SELECT id INTO v_equity_account_id

        FROM accounts

        WHERE account_code::text IN ('23421', '2342', '2330', '233', '2310', '231', '3900', '3901', '3001', '3000', '3300')

          AND (company_id = v_company_id OR company_id IS NULL)

        ORDER BY (company_id = v_company_id) DESC, id ASC

        LIMIT 1;

    END IF;



    IF v_equity_account_id IS NULL THEN

        SELECT id INTO v_equity_account_id

        FROM accounts

        WHERE account_type = 'equity' AND (allow_posting = true OR is_leaf = true)

          AND (company_id = v_company_id OR company_id IS NULL)

        ORDER BY (company_id = v_company_id) DESC, id ASC

        LIMIT 1;

    END IF;

    

    IF v_equity_account_id IS NULL OR v_account_id IS NULL THEN

        RETURN NEW;

    END IF;



    IF v_je_id IS NOT NULL THEN

        DELETE FROM account_ledger_entries WHERE journal_entry_id = v_je_id;

        

        IF v_new_balance = 0 THEN

            DELETE FROM journal_entries WHERE id = v_je_id;

            RETURN NEW;

        END IF;



        UPDATE journal_entries 

        SET description = v_desc,

            source_id = v_source_id,

            entry_date = CURRENT_DATE,

            status = 'posted'

        WHERE id = v_je_id;

    ELSE

        IF v_new_balance = 0 THEN

            RETURN NEW;

        END IF;

        

        -- Deterministic sequence without race conditions

        v_entry_number := public.fn_get_next_sequence(v_company_id, 'opening_balance', NULL, NULL);

        IF v_entry_number IS NULL OR v_entry_number = '' THEN

            RAISE EXCEPTION 'Failed to generate entry_number via fn_get_next_sequence for opening_balance (company_id: %)', v_company_id;

        END IF;



        INSERT INTO journal_entries (

            source_type, source_id, entry_date, description, created_by, company_id, entry_number, status

        ) VALUES (

            'opening_balance', v_source_id, CURRENT_DATE, v_desc, auth.uid(), v_company_id, v_entry_number, 'posted'

        ) RETURNING id INTO v_je_id;

    END IF;



    -- Calculate base currency balance using deterministic exchange rate

    r_rate := 1.0;

    IF v_currency IS NOT NULL AND v_currency <> 'EGP' THEN

        SELECT rate_to_egp INTO r_rate 

        FROM exchange_rates 

        WHERE currency_code = v_currency 

        ORDER BY effective_from DESC, updated_at DESC, id DESC 

        LIMIT 1;

        IF r_rate IS NULL OR r_rate <= 0 THEN r_rate := 1.0; END IF;

    END IF;

    v_base_balance := v_new_balance * r_rate;



    -- Create double-entry lines based strictly on chosen direction

    IF v_direction = 'DEBIT' THEN

        INSERT INTO account_ledger_entries (

            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

        ) VALUES (

            v_je_id, v_account_id, v_new_balance, 0, v_currency, v_base_balance, v_desc, v_company_id

        );

        INSERT INTO account_ledger_entries (

            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

        ) VALUES (

            v_je_id, v_equity_account_id, 0, v_new_balance, v_currency, v_base_balance, v_desc, v_company_id

        );

    ELSE

        INSERT INTO account_ledger_entries (

            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

        ) VALUES (

            v_je_id, v_account_id, 0, v_new_balance, v_currency, v_base_balance, v_desc, v_company_id

        );

        INSERT INTO account_ledger_entries (

            journal_entry_id, account_id, debit, credit, currency, amount_in_base_currency, description, company_id

        ) VALUES (

            v_je_id, v_equity_account_id, v_new_balance, 0, v_currency, v_base_balance, v_desc, v_company_id

        );

    END IF;



    RETURN NEW;

END;

$$;



-- Ensure supplier account_id is bound before insert/update

DROP TRIGGER IF EXISTS trg_create_supplier_account ON public.suppliers;

CREATE TRIGGER trg_create_supplier_account

BEFORE INSERT OR UPDATE OF supplier_type, code ON public.suppliers

FOR EACH ROW

EXECUTE FUNCTION public.create_supplier_account();



-- Ensure triggers on all entities sync opening balances to GL

DROP TRIGGER IF EXISTS trg_supplier_opening_balance_gl ON public.suppliers;

CREATE TRIGGER trg_supplier_opening_balance_gl

AFTER INSERT OR UPDATE OF initial_balance, initial_balance_direction, initial_balances_by_currency, account_id

ON public.suppliers

FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();



DROP TRIGGER IF EXISTS trg_customer_opening_balance_gl ON public.customers;

CREATE TRIGGER trg_customer_opening_balance_gl

AFTER INSERT OR UPDATE OF initial_balance, initial_balance_direction, account_id

ON public.customers

FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();



-- ⚠️ ORDER-DEPENDENT: assumes trg_create_shareholder_account (alphabetically

-- earlier) fires first on the same AFTER INSERT event and populates account_id

-- via its own UPDATE, which re-triggers this trigger. Renaming either trigger

-- breaks this chain silently.

DROP TRIGGER IF EXISTS trg_shareholder_opening_balance_gl ON public.shareholders;

CREATE TRIGGER trg_shareholder_opening_balance_gl

AFTER INSERT OR UPDATE OF initial_balance_egp, initial_balance_usd, initial_balance_eur, initial_balance_gbp, initial_balance_direction, initial_balance_direction_egp, account_id

ON public.shareholders

FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();



DROP TRIGGER IF EXISTS trg_shipping_company_opening_balance_gl ON public.shipping_companies;

CREATE TRIGGER trg_shipping_company_opening_balance_gl

AFTER INSERT OR UPDATE OF initial_balance, initial_balance_direction, account_id

ON public.shipping_companies

FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();



DROP TRIGGER IF EXISTS trg_clearing_agent_opening_balance_gl ON public.clearing_agents;

CREATE TRIGGER trg_clearing_agent_opening_balance_gl

AFTER INSERT OR UPDATE OF initial_balance, initial_balance_direction, account_id

ON public.clearing_agents

FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();



DROP TRIGGER IF EXISTS trg_transport_supplier_opening_balance_gl ON public.transport_suppliers;

CREATE TRIGGER trg_transport_supplier_opening_balance_gl

AFTER INSERT OR UPDATE OF initial_balance, initial_balance_direction, account_id

ON public.transport_suppliers

FOR EACH ROW EXECUTE FUNCTION public.sync_entity_opening_balance_gl();



-- 5. Per-currency supplier balance RPC

-- Enables fetching native balances per currency for any multi-currency supplier.

CREATE OR REPLACE FUNCTION public.get_supplier_balances_per_currency(p_supplier_id UUID)

RETURNS TABLE (

    currency            TEXT,

    total_invoiced      NUMERIC,

    total_paid          NUMERIC,

    outstanding_balance NUMERIC,

    rate_to_egp         NUMERIC,

    balance_in_egp      NUMERIC

)

LANGUAGE plpgsql

SECURITY DEFINER

AS $$

BEGIN

    RETURN QUERY

    WITH inv AS (

        SELECT 

            COALESCE(pi.currency, 'EGP') AS cur,

            SUM(pi.total_amount) AS inv_amt,

            SUM(COALESCE(pi.paid_amount, 0)) AS paid_amt

        FROM purchase_invoices pi

        WHERE pi.supplier_id = p_supplier_id

          AND pi.status = 'confirmed'

        GROUP BY COALESCE(pi.currency, 'EGP')

    ),

    rates AS (

        SELECT currency_code, rate_to_egp FROM exchange_rates

        UNION ALL

        SELECT 'EGP', 1.0

    )

    SELECT 

        inv.cur,

        inv.inv_amt,

        inv.paid_amt,

        (inv.inv_amt - inv.paid_amt) AS outstanding_balance,

        COALESCE(r.rate_to_egp, 1.0) AS rate_to_egp,

        (inv.inv_amt - inv.paid_amt) * COALESCE(r.rate_to_egp, 1.0) AS balance_in_egp

    FROM inv

    LEFT JOIN rates r ON r.currency_code = inv.cur;

END;

$$;



GRANT EXECUTE ON FUNCTION public.get_supplier_balances_per_currency(UUID) TO authenticated, anon, service_role;



-- ==============================================================================

-- Migration: 20260908000003_455_purchase_item_level_journal_entries.sql

-- Description: Update purchase invoice confirmation (rpc_confirm_purchase) to generate

--              granular, item-level journal entry lines (journal_entry_lines) instead

--              of an aggregated summary row.

--

-- Core Changes:

-- 1. Granular Inventory Debit Lines:

--    - Iterates over each item in purchase_invoice_items (valid lines).

--    - Resolves appropriate inventory account (1234 Packaging Materials / 1231 Produce Crops).

--    - Creates distinct debit lines with structured descriptions containing item name,

--      quantity, unit, unit cost, and invoice number.

--

-- 2. Strict Double-Entry Balance Equation:

--    - Calculates exact line-by-line foreign and base (EGP) debit amounts.

--    - Accumulates exact totals to construct the supplier credit line.

--    - Total Base Debit strictly equals Total Base Credit, satisfying P0001 constraint.

-- ==============================================================================



CREATE OR REPLACE FUNCTION public.rpc_confirm_purchase(

  p_purchase_id TEXT,

  p_user_id UUID DEFAULT auth.uid()

)

RETURNS JSONB

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path = public

AS $$

DECLARE

  v_purchase RECORD;

  v_item RECORD;

  v_batch_number TEXT;

  v_date_str TEXT;

  v_seq INT := 0;

  v_station_product_name TEXT;

  v_cur_qty NUMERIC;

  v_cur_price NUMERIC;

  v_new_qty NUMERIC;

  v_new_price NUMERIC;

  v_total_foreign NUMERIC := 0;

  v_total_egp NUMERIC := 0;

  v_exchange_rate NUMERIC := 1.0;

  v_inventory_account_id INTEGER;

  v_supplier_leaf_account_id INTEGER;

  v_paid_amount NUMERIC;

  v_treasury_id TEXT;

  v_bank_account_id INTEGER;

  v_source_type TEXT;

  v_cash_account_id INTEGER;

  v_treasury_name TEXT;

  v_bank_name TEXT;

  v_treasury_balance_id BIGINT;

  v_balance_before NUMERIC;

  v_balance_after NUMERIC;

  v_payment_number TEXT;

  v_inv_currency TEXT;

  v_batches_created INT := 0;

  v_company_id UUID;

  v_inventory_je_id BIGINT;

  v_payment_je_id BIGINT;

  v_supplier_name TEXT;

BEGIN

  -- ── PHASE 0a: Load Purchase Invoice ─────────────────────────────────────────

  SELECT * INTO v_purchase FROM purchase_invoices WHERE id::TEXT = p_purchase_id;

  IF NOT FOUND THEN

    RETURN jsonb_build_object('success', false, 'error', 'لم يتم العثور على الفاتورة');

  END IF;

  IF v_purchase.status = 'confirmed' THEN

    RETURN jsonb_build_object('success', true, 'message', 'تم التأكيد مسبقاً');

  END IF;



  v_date_str := to_char(COALESCE(v_purchase.invoice_date::date, now()::date), 'YYYYMMDD');

  v_inv_currency := COALESCE(v_purchase.currency, 'EGP');



  -- Determine transaction exchange rate

  SELECT COALESCE(NULLIF(exchange_rate, 0), 1.0) INTO v_exchange_rate 

  FROM purchase_invoice_items 

  WHERE invoice_id::TEXT = p_purchase_id 

  LIMIT 1;

  IF v_exchange_rate IS NULL OR v_exchange_rate <= 0 THEN v_exchange_rate := 1.0; END IF;



  -- ── PHASE 0a2: Resolve Company ID ──────────────────────────────────────────

  SELECT company_id INTO v_company_id FROM suppliers WHERE id = v_purchase.supplier_id;

  IF v_company_id IS NULL THEN

    SELECT id INTO v_company_id FROM sys_companies WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 1;

  END IF;

  IF v_company_id IS NULL THEN

    SELECT id INTO v_company_id FROM sys_companies LIMIT 1;

  END IF;

  IF v_company_id IS NULL THEN

    RAISE EXCEPTION 'لم يتم العثور على شركة صالحة';

  END IF;



  -- ── PHASE 0b: Resolve Supplier Leaf Account (Credit Account) ────────────────

  SELECT name INTO v_supplier_name FROM suppliers WHERE id = v_purchase.supplier_id;



  -- Priority 1: Use supplier's assigned account if valid, active, and allows posting

  SELECT a.id INTO v_supplier_leaf_account_id

  FROM suppliers s

  JOIN accounts a ON a.id = s.account_id

  WHERE s.id = v_purchase.supplier_id

    AND a.deleted_at IS NULL

    AND (a.allow_posting = TRUE OR a.is_leaf = TRUE);



  -- Priority 2: Lookup supplier's dedicated leaf sub-account under 2112

  IF v_supplier_leaf_account_id IS NULL THEN

    SELECT a.id INTO v_supplier_leaf_account_id

    FROM accounts a

    WHERE (a.account_code LIKE '2112%' OR a.parent_id = (SELECT id FROM accounts WHERE account_code = '2112' AND deleted_at IS NULL LIMIT 1))

      AND (a.account_name ILIKE '%' || v_supplier_name || '%' OR a.name ILIKE '%' || v_supplier_name || '%')

      AND a.deleted_at IS NULL

    ORDER BY a.id ASC

    LIMIT 1;

  END IF;



  -- Priority 3: Auto-create leaf account under 2112 if missing

  IF v_supplier_leaf_account_id IS NULL AND v_purchase.supplier_id IS NOT NULL THEN

    DECLARE

      v_p2112_id BIGINT;

      v_next_num INT;

      v_next_code TEXT;

    BEGIN

      SELECT id INTO v_p2112_id FROM accounts WHERE account_code = '2112' AND deleted_at IS NULL LIMIT 1;

      IF v_p2112_id IS NOT NULL THEN

        SELECT COALESCE(MAX(SUBSTRING(account_code FROM 5)::INT), 0) + 1

        INTO v_next_num

        FROM accounts

        WHERE account_code ~ '^2112[0-9]+$' AND deleted_at IS NULL;



        v_next_code := '2112' || LPAD(COALESCE(v_next_num, 1)::TEXT, 2, '0');



        INSERT INTO accounts (

          account_code, name, account_name, account_type,

          parent_id, level, is_leaf, allow_posting, is_active, is_system, company_id

        ) VALUES (

          v_next_code,

          'Supplier - ' || COALESCE(v_supplier_name, 'Unknown'),

          'مورد - ' || COALESCE(v_supplier_name, 'غير محدد'),

          'liability',

          v_p2112_id,

          5,

          TRUE,

          TRUE,

          TRUE,

          FALSE,

          v_company_id

        ) RETURNING id INTO v_supplier_leaf_account_id;



        UPDATE suppliers SET account_id = v_supplier_leaf_account_id WHERE id = v_purchase.supplier_id;

      END IF;

    END;

  END IF;



  -- Priority 4: Fallback to Level 4 parent account 2112 (enable posting if needed)

  IF v_supplier_leaf_account_id IS NULL THEN

    SELECT id INTO v_supplier_leaf_account_id FROM accounts WHERE account_code = '2112' AND deleted_at IS NULL LIMIT 1;

    IF v_supplier_leaf_account_id IS NOT NULL THEN

      UPDATE accounts SET allow_posting = TRUE WHERE id = v_supplier_leaf_account_id;

    END IF;

  END IF;



  -- Priority 5: Fallback to legacy 2000

  IF v_supplier_leaf_account_id IS NULL THEN

    SELECT id INTO v_supplier_leaf_account_id FROM accounts WHERE account_code = '2000' AND deleted_at IS NULL LIMIT 1;

  END IF;



  IF v_supplier_leaf_account_id IS NULL THEN

    RAISE EXCEPTION 'لم يتم العثور على حساب المورد في شجرة الحسابات (دليل الحسابات)';

  END IF;



  -- ── PHASE 1: Stock Batches + Raw Materials + Station Products ───────────────

  FOR v_item IN

    SELECT pii.*, rm.code AS rm_code, rm.name AS rm_name, rm.unit AS rm_unit,

           rmc.name AS category_name

    FROM purchase_invoice_items pii

    LEFT JOIN raw_materials rm ON rm.id = pii.raw_material_id

    LEFT JOIN raw_material_categories rmc ON rmc.id = rm.category_id

    WHERE pii.invoice_id::TEXT = p_purchase_id

  LOOP

    v_seq := v_seq + 1;

    v_batch_number := 'B-' || v_date_str || '-' || v_purchase.id::TEXT || '-' || lpad(v_seq::TEXT, 4, '0');



    INSERT INTO stock_batches (

      batch_number, product_id, supplier_id, supplier_name, purchase_invoice_id,

      quantity, remaining_quantity, purchase_cost, average_cost,

      exchange_rate, currency, status, user_id

    ) VALUES (

      v_batch_number,

      v_item.raw_material_id,

      v_purchase.supplier_id,

      v_supplier_name,

      v_purchase.id,

      COALESCE(v_item.quantity, 0),

      COALESCE(v_item.quantity, 0),

      COALESCE(v_item.unit_cost, 0),

      COALESCE(v_item.unit_cost, 0),

      v_exchange_rate,

      v_inv_currency,

      'active',

      p_user_id

    );

    v_batches_created := v_batches_created + 1;



    IF v_item.raw_material_id IS NOT NULL THEN

      SELECT quantity, default_purchase_price INTO v_cur_qty, v_cur_price

      FROM raw_materials WHERE id = v_item.raw_material_id;



      IF FOUND THEN

        v_cur_qty := COALESCE(v_cur_qty, 0);

        v_cur_price := COALESCE(v_cur_price, 0);

        v_new_qty := v_cur_qty + COALESCE(v_item.quantity, 0);

        IF v_new_qty > 0 THEN

          v_new_price := ((v_cur_qty * v_cur_price) + (COALESCE(v_item.quantity, 0) * COALESCE(v_item.unit_cost, 0))) / v_new_qty;

        ELSE

          v_new_price := COALESCE(v_item.unit_cost, 0);

        END IF;

        UPDATE raw_materials

        SET quantity = v_new_qty, default_purchase_price = v_new_price, updated_at = now()

        WHERE id = v_item.raw_material_id;

      END IF;



      DECLARE

        v_station_id BIGINT;

      BEGIN

        v_station_id := v_item.station_id;

        IF v_station_id IS NULL THEN

          SELECT spb.station_id INTO v_station_id

          FROM station_product_batches spb

          WHERE spb.product_code = COALESCE(v_item.rm_code, '') AND spb.source_type = 'purchase'

          LIMIT 1;

        END IF;

        IF v_station_id IS NULL THEN

          SELECT sp.station_id INTO v_station_id

          FROM station_products sp

          WHERE sp.product_code = COALESCE(v_item.rm_code, '') LIMIT 1;

        END IF;



        IF v_station_id IS NOT NULL THEN

          v_station_product_name := COALESCE(v_item.rm_name, '') || ' (مادة تعبئة)';

          PERFORM upsert_station_product_quantity(v_station_id, v_station_product_name, COALESCE(v_item.rm_code, ''), COALESCE(v_item.quantity, 0)::INT);



          INSERT INTO station_product_batches (

            station_id, product_name, product_code, quantity, remaining_quantity,

            unit_cost, currency, exchange_rate, source_type, source_date,

            supplier_name, purchase_invoice_id

          ) VALUES (

            v_station_id, v_station_product_name, COALESCE(v_item.rm_code, ''),

            COALESCE(v_item.quantity, 0), COALESCE(v_item.quantity, 0),

            COALESCE(v_item.unit_cost, 0), v_inv_currency, v_exchange_rate,

            'purchase', now(),

            v_supplier_name,

            v_purchase.id

          );

        END IF;

      END;

    END IF;



    v_total_foreign := v_total_foreign + (COALESCE(v_item.quantity, 0) * COALESCE(v_item.unit_cost, 0));

    v_total_egp := v_total_egp + (COALESCE(v_item.quantity, 0) * COALESCE(v_item.unit_cost, 0) * v_exchange_rate);

  END LOOP;



  v_paid_amount := COALESCE(v_purchase.paid_amount, 0);

  v_treasury_id := v_purchase.payment_treasury_id;

  v_bank_account_id := v_purchase.payment_bank_account_id;

  v_source_type := COALESCE(v_purchase.payment_source_type, 'treasury');



  IF v_purchase.supplier_id IS NOT NULL THEN

    DECLARE

      v_remaining NUMERIC;

    BEGIN

      v_remaining := COALESCE(v_purchase.total_amount, 0) - v_paid_amount;

      IF v_remaining > 0 THEN

        UPDATE suppliers

        SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_remaining

        WHERE id = v_purchase.supplier_id;

      END IF;

    END;

  END IF;



  -- ── PHASE 2: Granular Item-Level Inventory Journal Entry Lines ───────────────

  IF v_total_foreign > 0 THEN

    DECLARE

      v_lines_array JSONB := '[]'::jsonb;

      v_line_desc TEXT;

      v_item_line RECORD;

      v_item_foreign NUMERIC;

      v_item_egp NUMERIC;

      v_sum_debit_foreign NUMERIC := 0;

      v_sum_debit_egp NUMERIC := 0;

    BEGIN

      -- Loop through each purchased item to generate granular debit lines:

      FOR v_item_line IN

        SELECT

          pii.id,

          pii.quantity,

          pii.unit_cost,

          pii.raw_material_id,

          COALESCE(rm.name, rm.code, 'صنف غير محدد') AS item_name,

          COALESCE(rm.unit, '') AS item_unit,

          CASE 

            WHEN pii.raw_material_id IS NOT NULL THEN '12411'

            ELSE '12412'

          END AS inv_code

        FROM purchase_invoice_items pii

        LEFT JOIN raw_materials rm ON rm.id = pii.raw_material_id

        WHERE pii.invoice_id::TEXT = p_purchase_id

        ORDER BY pii.id ASC

      LOOP

        v_item_foreign := ROUND(COALESCE(v_item_line.quantity, 0) * COALESCE(v_item_line.unit_cost, 0), 2);

        v_item_egp := ROUND(v_item_foreign * v_exchange_rate, 2);



        v_sum_debit_foreign := v_sum_debit_foreign + v_item_foreign;

        v_sum_debit_egp := v_sum_debit_egp + v_item_egp;



        -- Resolve target inventory account (12411 packaging / 12412 produce)

        SELECT id INTO v_inventory_account_id 

        FROM accounts 

        WHERE account_code = v_item_line.inv_code 

          AND company_id = v_company_id 

          AND deleted_at IS NULL 

        LIMIT 1;



        IF v_inventory_account_id IS NULL THEN

          SELECT id INTO v_inventory_account_id 

          FROM accounts 

          WHERE account_code = v_item_line.inv_code 

            AND deleted_at IS NULL 

          LIMIT 1;

        END IF;



        -- Fallback between 12411 and 12412 or parent 1241

        IF v_inventory_account_id IS NULL THEN

          IF v_item_line.inv_code = '12411' THEN

            SELECT id INTO v_inventory_account_id 

            FROM accounts 

            WHERE account_code IN ('12412', '1241') AND deleted_at IS NULL 

            ORDER BY account_code ASC LIMIT 1;

          ELSE

            SELECT id INTO v_inventory_account_id 

            FROM accounts 

            WHERE account_code IN ('12411', '1241') AND deleted_at IS NULL 

            ORDER BY account_code ASC LIMIT 1;

          END IF;

        END IF;



        -- Fallback to any inventory asset account

        IF v_inventory_account_id IS NULL THEN

          SELECT id INTO v_inventory_account_id 

          FROM accounts 

          WHERE account_code LIKE '124%' AND allow_posting = TRUE AND deleted_at IS NULL 

          LIMIT 1;

        END IF;



        -- Hard validation: Never silently skip debit line

        IF v_inventory_account_id IS NULL THEN

          RAISE EXCEPTION 'لم يتم العثور على حساب المخزون (%) في شجرة الحسابات', v_item_line.inv_code;

        END IF;



        -- Granular line description with item details

        v_line_desc := 'مخزون - ' || v_item_line.item_name || 

          ' - كمية: ' || v_item_line.quantity || 

          CASE WHEN v_item_line.item_unit <> '' THEN ' ' || v_item_line.item_unit ELSE '' END || 

          ' - بسعر: ' || v_item_line.unit_cost || ' ' || v_inv_currency ||

          ' - فاتورة ' || COALESCE(v_purchase.invoice_number, '');



        -- Granular Debit Line (مدين): Inventory Account per purchased item

        v_lines_array := v_lines_array || jsonb_build_object(

          'account_id', v_inventory_account_id,

          'debit', v_item_foreign,

          'base_debit', v_item_egp,

          'credit', 0,

          'base_credit', 0,

          'currency', v_inv_currency,

          'description', v_line_desc

        );

      END LOOP;



      -- Credit Line (دائن): Supplier Sub-Account strictly balancing all debit lines

      v_lines_array := v_lines_array || jsonb_build_object(

        'account_id', v_supplier_leaf_account_id,

        'debit', 0,

        'base_debit', 0,

        'credit', v_sum_debit_foreign,

        'base_credit', v_sum_debit_egp,

        'currency', v_inv_currency,

        'description', 'مستحقات مورد: ' || COALESCE(v_supplier_name, '') || ' - فاتورة ' || COALESCE(v_purchase.invoice_number, '')

      );



      -- Post balanced inventory journal entry

      v_inventory_je_id := public.post_journal_entry(

        p_source_type := 'purchase_inventory',

        p_description := 'قيد مشتريات فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, ''),

        p_entry_date  := COALESCE(v_purchase.invoice_date::date, now()::date),

        p_company_id  := v_company_id,

        p_created_by  := p_user_id,

        p_lines       := v_lines_array,

        p_source_id   := v_purchase.id::TEXT

      );

      UPDATE purchase_invoices SET journal_entry_id = v_inventory_je_id WHERE id = v_purchase.id;

    END;

  END IF;



  -- ── PHASE 3: Payment Processing (Treasury or Bank) ─────────────────────────

  IF v_paid_amount > 0 AND COALESCE(v_purchase.payment_processed, false) = false THEN

    IF v_source_type = 'bank' AND v_bank_account_id IS NOT NULL THEN

      SELECT ba.name INTO v_bank_name FROM bank_accounts ba WHERE ba.id = v_bank_account_id;



      -- Resolve bank account under 1211 (12111 EGP, 12112 USD, 12113 EUR, 12114 GBP)

      SELECT id INTO v_cash_account_id FROM accounts

      WHERE account_code = (

        CASE v_inv_currency

          WHEN 'USD' THEN '12112'

          WHEN 'EUR' THEN '12113'

          WHEN 'GBP' THEN '12114'

          ELSE '12111'

        END

      ) AND company_id = v_company_id AND deleted_at IS NULL LIMIT 1;



      IF v_cash_account_id IS NULL THEN

        SELECT id INTO v_cash_account_id FROM accounts

        WHERE account_code = (

          CASE v_inv_currency

            WHEN 'USD' THEN '12112'

            WHEN 'EUR' THEN '12113'

            WHEN 'GBP' THEN '12114'

            ELSE '12111'

          END

        ) AND deleted_at IS NULL LIMIT 1;

      END IF;



      IF v_cash_account_id IS NULL THEN

        SELECT id INTO v_cash_account_id FROM accounts

        WHERE (account_code LIKE '1211%' OR account_code LIKE '121%') AND allow_posting = TRUE AND deleted_at IS NULL

        LIMIT 1;

      END IF;



      INSERT INTO bank_transactions (

        bank_account_id, type, amount, description, transaction_date,

        currency, exchange_rate, amount_in_base_currency, company_id

      ) VALUES (

        v_bank_account_id, 'withdrawal', v_paid_amount,

        'سداد فاتورة مشتريات رقم ' || COALESCE(v_purchase.invoice_number, '') || ' - المورد: ' || COALESCE(v_supplier_name, ''),

        COALESCE(v_purchase.invoice_date::date, now()::date),

        v_inv_currency, v_exchange_rate, (v_paid_amount * v_exchange_rate), v_company_id

      );



      UPDATE bank_accounts

      SET current_balance = COALESCE(current_balance, 0) - v_paid_amount, updated_at = now()

      WHERE id = v_bank_account_id;



      -- Post payment journal entry

      IF v_cash_account_id IS NOT NULL THEN

        v_payment_je_id := public.post_journal_entry(

          p_source_type := 'purchase_payment',

          p_description := 'سداد بنكي لمشتريات فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, ''),

          p_entry_date  := COALESCE(v_purchase.invoice_date::date, now()::date),

          p_company_id  := v_company_id,

          p_created_by  := p_user_id,

          p_lines       := jsonb_build_array(

            jsonb_build_object(

              'account_id', v_supplier_leaf_account_id,

              'debit', v_paid_amount,

              'base_debit', (v_paid_amount * v_exchange_rate),

              'credit', 0,

              'base_credit', 0,

              'currency', v_inv_currency,

              'description', 'سداد مستحقات مورد: ' || COALESCE(v_supplier_name, '')

            ),

            jsonb_build_object(

              'account_id', v_cash_account_id,

              'debit', 0,

              'base_debit', 0,

              'credit', v_paid_amount,

              'base_credit', (v_paid_amount * v_exchange_rate),

              'currency', v_inv_currency,

              'description', 'صرف من بنك: ' || COALESCE(v_bank_name, '')

            )

          ),

          p_source_id   := v_purchase.id::TEXT

        );

      END IF;



    ELSIF v_treasury_id IS NOT NULL THEN

      SELECT name INTO v_treasury_name FROM treasuries WHERE id::TEXT = v_treasury_id;



      -- Resolve treasury GL account under 1221 (12211 EGP, 12212 USD, 12213 EUR, 12214 GBP)

      SELECT id INTO v_cash_account_id FROM accounts

      WHERE account_code = (

        CASE v_inv_currency

          WHEN 'USD' THEN '12212'

          WHEN 'EUR' THEN '12213'

          WHEN 'GBP' THEN '12214'

          ELSE '12211'

        END

      ) AND company_id = v_company_id AND deleted_at IS NULL LIMIT 1;



      IF v_cash_account_id IS NULL THEN

        SELECT id INTO v_cash_account_id FROM accounts

        WHERE account_code = (

          CASE v_inv_currency

            WHEN 'USD' THEN '12212'

            WHEN 'EUR' THEN '12213'

            WHEN 'GBP' THEN '12214'

            ELSE '12211'

          END

        ) AND deleted_at IS NULL LIMIT 1;

      END IF;



      IF v_cash_account_id IS NULL THEN

        SELECT id INTO v_cash_account_id FROM accounts

        WHERE account_code = (

          CASE v_inv_currency

            WHEN 'USD' THEN '12122'

            WHEN 'EUR' THEN '12123'

            WHEN 'GBP' THEN '12124'

            ELSE '12121'

          END

        ) AND deleted_at IS NULL LIMIT 1;

      END IF;



      IF v_cash_account_id IS NULL THEN

        SELECT id INTO v_cash_account_id FROM accounts

        WHERE (account_code LIKE '1212%' OR account_code LIKE '121%') AND allow_posting = TRUE AND deleted_at IS NULL

        LIMIT 1;

      END IF;



      -- Update treasury balance

      SELECT id, balance INTO v_treasury_balance_id, v_balance_before

      FROM treasury_balances

      WHERE treasury_id::TEXT = v_treasury_id AND currency = v_inv_currency

      LIMIT 1;



      IF v_treasury_balance_id IS NOT NULL THEN

        v_balance_after := v_balance_before - v_paid_amount;

        UPDATE treasury_balances SET balance = v_balance_after, updated_at = now() WHERE id = v_treasury_balance_id;

      ELSE

        v_balance_before := 0;

        v_balance_after := -v_paid_amount;

        INSERT INTO treasury_balances (treasury_id, currency, balance, created_at, updated_at)

        VALUES (v_treasury_id::UUID, v_inv_currency, v_balance_after, now(), now());

      END IF;



      v_payment_number := 'PAY-' || v_date_str || '-' || lpad(COALESCE(v_purchase.id, 0)::TEXT, 4, '0');



      INSERT INTO treasury_transactions (

        transaction_number, transaction_type, treasury_id, amount,

        balance_before, balance_after, transaction_date, notes, user_id,

        currency, exchange_rate, amount_in_base_currency, source_id, source_type,

        supplier_id, company_id

      ) VALUES (

        v_payment_number, 'supplier_payment', v_treasury_id::UUID, v_paid_amount,

        v_balance_before, v_balance_after,

        COALESCE(v_purchase.invoice_date::date, now()::date),

        'سداد فاتورة مشتريات رقم ' || COALESCE(v_purchase.invoice_number, '') || ' - المورد: ' || COALESCE(v_supplier_name, ''),

        p_user_id, v_inv_currency, v_exchange_rate, (v_paid_amount * v_exchange_rate),

        v_purchase.id::TEXT, 'purchase_payment', v_purchase.supplier_id, v_company_id

      );



      -- Post payment journal entry

      IF v_cash_account_id IS NOT NULL THEN

        v_payment_je_id := public.post_journal_entry(

          p_source_type := 'purchase_payment',

          p_description := 'سداد نقدي لمشتريات فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, ''),

          p_entry_date  := COALESCE(v_purchase.invoice_date::date, now()::date),

          p_company_id  := v_company_id,

          p_created_by  := p_user_id,

          p_lines       := jsonb_build_array(

            jsonb_build_object(

              'account_id', v_supplier_leaf_account_id,

              'debit', v_paid_amount,

              'base_debit', (v_paid_amount * v_exchange_rate),

              'credit', 0,

              'base_credit', 0,

              'currency', v_inv_currency,

              'description', 'سداد مستحقات مورد: ' || COALESCE(v_supplier_name, '')

            ),

            jsonb_build_object(

              'account_id', v_cash_account_id,

              'debit', 0,

              'base_debit', 0,

              'credit', v_paid_amount,

              'base_credit', (v_paid_amount * v_exchange_rate),

              'currency', v_inv_currency,

              'description', 'صرف من خزينة: ' || COALESCE(v_treasury_name, '')

            )

          ),

          p_source_id   := v_purchase.id::TEXT

        );

      END IF;

    END IF;



    UPDATE purchase_invoices SET payment_processed = true WHERE id = v_purchase.id;

  END IF;



  -- ── PHASE 4: Finalize Purchase Invoice Status ──────────────────────────────

  UPDATE purchase_invoices

  SET status = 'confirmed',

      updated_at = now()

  WHERE id = v_purchase.id;



  RETURN jsonb_build_object(

    'success', true,

    'message', 'تم تأكيد المشتريات وتوليد بنود القيد المحاسبي التفصيلية بنجاح',

    'batches_created', v_batches_created,

    'inventory_journal_entry_id', v_inventory_je_id,

    'payment_journal_entry_id', v_payment_je_id

  );

END;

$$;



GRANT EXECUTE ON FUNCTION public.rpc_confirm_purchase(TEXT, UUID) TO authenticated, anon, service_role;



-- ============================================================================

-- Migration 456: Strict Currency-Specific Supplier Balances & Running Balances

-- ============================================================================

-- Purpose:

--   1. Update rpc_confirm_purchase to convert foreign currency invoice balance

--      to EGP using active exchange rate before incrementing suppliers.outstanding_balance.

--   2. Update get_supplier_true_balances_by_currency() to aggregate all transactions

--      strictly by (supplier_id, currency) without mixing or conflating currencies.

--   3. Update get_supplier_true_balances() to derive base EGP true balance directly

--      from the per-currency streams.

-- ============================================================================



-- ── 0. Ensure Tables & Columns ─────────────────────────────────────────────

ALTER TABLE public.purchase_invoices ADD COLUMN IF NOT EXISTS exchange_rate NUMERIC(15, 6) DEFAULT 1.0;



-- ── 1. Per-Currency Supplier Balance RPC ────────────────────────────────────



DROP FUNCTION IF EXISTS public.get_supplier_true_balances_by_currency();



CREATE OR REPLACE FUNCTION public.get_supplier_true_balances_by_currency()

RETURNS TABLE (

    supplier_id        uuid,

    supplier_code      text,

    supplier_name      text,

    currency           text,

    true_balance       numeric,   -- native currency amount

    true_balance_egp   numeric    -- converted to EGP using latest rate

)

LANGUAGE sql

SECURITY DEFINER

STABLE

AS $func$

  WITH rates AS (

    SELECT DISTINCT ON (currency_code) currency_code, rate_to_egp 

    FROM (

      SELECT currency_code, rate_to_egp, updated_at FROM exchange_rates

      UNION ALL

      SELECT 'EGP'::character varying(10), 1.0::numeric(10,4), NOW()

    ) r_all

    ORDER BY currency_code, updated_at DESC NULLS LAST

  ),

  -- 1. Initial Balances

  init_balances AS (

    -- Multi-currency suppliers with initial_balances_by_currency

    SELECT 

      s.id AS supplier_id,

      UPPER(COALESCE(elem.value->>'currency', elem.key)) AS currency,

      COALESCE((elem.value->>'amount')::numeric, 0) * (CASE WHEN UPPER(COALESCE(elem.value->>'direction', 'CREDIT')) = 'DEBIT' THEN -1 ELSE 1 END) AS net_amt

    FROM suppliers s,

    LATERAL jsonb_each(s.initial_balances_by_currency) elem

    WHERE s.is_multi_currency = true 

      AND s.initial_balances_by_currency IS NOT NULL 

      AND jsonb_typeof(s.initial_balances_by_currency) = 'object'

      AND COALESCE((elem.value->>'amount')::numeric, 0) > 0

    

    UNION ALL

    

    -- Single-currency suppliers or multi without JSON map

    SELECT 

      s.id AS supplier_id,

      COALESCE(NULLIF(s.currency, ''), 'EGP') AS currency,

      COALESCE(s.initial_balance, 0) * (CASE WHEN s.initial_balance_direction = 'DEBIT' THEN -1 ELSE 1 END) AS net_amt

    FROM suppliers s

    WHERE (s.is_multi_currency = false OR s.initial_balances_by_currency IS NULL OR s.initial_balances_by_currency = '{}'::jsonb)

      AND COALESCE(s.initial_balance, 0) <> 0

  ),

  

  -- 2. Purchase Invoices (credit to supplier: increases payable)

  purchases AS (

    SELECT 

      supplier_id,

      COALESCE(NULLIF(currency, ''), 'EGP') AS currency,

      SUM(total_amount) AS net_amt

    FROM purchase_invoices

    WHERE status = 'confirmed' AND supplier_id IS NOT NULL

    GROUP BY supplier_id, COALESCE(NULLIF(currency, ''), 'EGP')

  ),

  

  -- 3. Treasury Transactions (cash receipts/deposits from supplier increase credit: +amount, payments to supplier: -amount)

  treasury AS (

    SELECT 

      supplier_id,

      COALESCE(NULLIF(currency, ''), 'EGP') AS currency,

      SUM(CASE WHEN LOWER(COALESCE(type, '')) IN ('deposit', 'receive', 'income', 'supplier_refund') THEN amount ELSE -amount END) AS net_amt

    FROM treasury_transactions

    WHERE supplier_id IS NOT NULL 

      AND (status = 'confirmed' OR status IS NULL)

    GROUP BY supplier_id, COALESCE(NULLIF(currency, ''), 'EGP')

  ),

  

  -- 4. Bank Account Transactions (deposits/receipts from supplier: +amount, payments to supplier: -amount)

  bank_tx AS (

    SELECT 

      s.id AS supplier_id,

      COALESCE(NULLIF(ba.currency, ''), 'EGP') AS currency,

      SUM(CASE WHEN LOWER(COALESCE(bat.type, '')) IN ('deposit', 'receive', 'income') THEN bat.amount ELSE -bat.amount END) AS net_amt

    FROM bank_account_transactions bat

    JOIN suppliers s ON (s.id::text = bat.entity_id OR s.code = bat.entity_id OR s.supplier_code = bat.entity_id)

    LEFT JOIN bank_accounts ba ON ba.id = bat.bank_account_id

    WHERE bat.entity_type = 'supplier' 

      AND (bat.status = 'confirmed' OR bat.status IS NULL)

    GROUP BY s.id, COALESCE(NULLIF(ba.currency, ''), 'EGP')

  ),

  

  -- 5. Cheques (incoming cheques from supplier: +amount, outgoing cheques to supplier: -amount)

  cheque_tx AS (

    SELECT 

      supplier_id,

      COALESCE(NULLIF(currency, ''), 'EGP') AS currency,

      SUM(CASE WHEN LOWER(COALESCE(type, '')) = 'incoming' THEN amount ELSE -amount END) AS net_amt

    FROM cheques

    WHERE supplier_id IS NOT NULL 

      AND status IN ('cleared', 'collected')

    GROUP BY supplier_id, COALESCE(NULLIF(currency, ''), 'EGP')

  ),

  

  -- 6. Lot Receipts / Enterprise Account Ledger Entries (excluding lot_returns to avoid double counting with direct purchase_returns below)

  lot_tx AS (

    SELECT 

      s.id AS supplier_id,

      COALESCE(NULLIF(ale.currency, ''), 'EGP') AS currency,

      SUM(ale.credit - ale.debit) AS net_amt

    FROM account_ledger_entries ale

    JOIN journal_entries je ON je.id = ale.journal_entry_id

    JOIN suppliers s ON s.account_id = ale.account_id

    WHERE je.source_type IN ('lot_receipt','lot_adjustment','lot_price_adjustment','manual')

    GROUP BY s.id, COALESCE(NULLIF(ale.currency, ''), 'EGP')

  ),

  

  -- 7. Purchase Returns / Lot Returns (reduces supplier payable)

  purchase_returns AS (

    SELECT 

      lr.supplier_id,

      COALESCE(NULLIF(rec.currency, ''), COALESCE(NULLIF(s.crop_currency, ''), COALESCE(NULLIF(s.currency, ''), 'EGP'))) AS currency,

      -SUM(lr.return_value) AS net_amt

    FROM lot_returns lr

    LEFT JOIN lot_receipts rec ON rec.id = lr.lot_receipt_id

    JOIN suppliers s ON s.id = lr.supplier_id

    WHERE lr.supplier_id IS NOT NULL

    GROUP BY lr.supplier_id, COALESCE(NULLIF(rec.currency, ''), COALESCE(NULLIF(s.crop_currency, ''), COALESCE(NULLIF(s.currency, ''), 'EGP')))

  ),



  -- 8. Standalone Purchase Returns from Ledger Entries (if any not linked to lot_returns)

  ledger_returns AS (

    SELECT 

      s.id AS supplier_id,

      COALESCE(NULLIF(le.currency, ''), 'EGP') AS currency,

      -SUM(le.amount) AS net_amt

    FROM ledger_entries le

    JOIN suppliers s ON (s.id::text = le.entity_id OR s.code = le.entity_id OR s.supplier_code = le.entity_id)

    WHERE le.entity_type = 'supplier'

      AND le.reference_type = 'purchase_return'

    GROUP BY s.id, COALESCE(NULLIF(le.currency, ''), 'EGP')

  ),

  

  -- Combine all activity

  combined AS (

    SELECT supplier_id, currency, net_amt FROM init_balances

    UNION ALL

    SELECT supplier_id, currency, net_amt FROM purchases

    UNION ALL

    SELECT supplier_id, currency, net_amt FROM treasury

    UNION ALL

    SELECT supplier_id, currency, net_amt FROM bank_tx

    UNION ALL

    SELECT supplier_id, currency, net_amt FROM cheque_tx

    UNION ALL

    SELECT supplier_id, currency, net_amt FROM lot_tx

    UNION ALL

    SELECT supplier_id, currency, net_amt FROM purchase_returns

    UNION ALL

    SELECT supplier_id, currency, net_amt FROM ledger_returns

  ),

  

  aggregated AS (

    SELECT 

      supplier_id,

      currency,

      SUM(net_amt) AS true_balance

    FROM combined

    GROUP BY supplier_id, currency

    HAVING SUM(net_amt) <> 0

  )

  

  SELECT 

    s.id AS supplier_id,

    COALESCE(s.code, s.supplier_code, '') AS supplier_code,

    s.name AS supplier_name,

    a.currency,

    a.true_balance,

    a.true_balance * COALESCE(r.rate_to_egp, 1.0) AS true_balance_egp

  FROM aggregated a

  JOIN suppliers s ON s.id = a.supplier_id

  LEFT JOIN rates r ON r.currency_code = a.currency;

$func$;



GRANT EXECUTE ON FUNCTION public.get_supplier_true_balances_by_currency() TO authenticated, anon, service_role;



-- ── 2. Derived Base-EGP Supplier True Balance RPC ────────────────────────────



DROP FUNCTION IF EXISTS public.get_supplier_true_balances();



CREATE OR REPLACE FUNCTION public.get_supplier_true_balances()

RETURNS TABLE (

  supplier_id uuid,

  true_balance numeric

)

LANGUAGE sql

SECURITY DEFINER

AS $func$

  WITH cur_balances AS (

    SELECT 

      supplier_id,

      SUM(true_balance_egp) AS total_egp

    FROM public.get_supplier_true_balances_by_currency()

    GROUP BY supplier_id

  )

  SELECT 

    s.id AS supplier_id,

    COALESCE(cb.total_egp, 0) AS true_balance

  FROM public.suppliers s

  LEFT JOIN cur_balances cb ON cb.supplier_id = s.id;

$func$;



GRANT EXECUTE ON FUNCTION public.get_supplier_true_balances() TO authenticated, anon, service_role;



-- ── 3. Update rpc_confirm_purchase Supplier Balance Conversion ──────────────



DROP FUNCTION IF EXISTS public.rpc_confirm_purchase(TEXT, UUID);

DROP FUNCTION IF EXISTS public.rpc_confirm_purchase(TEXT);



CREATE OR REPLACE FUNCTION public.rpc_confirm_purchase(

  p_purchase_id TEXT,

  p_user_id UUID DEFAULT NULL

)

RETURNS JSONB

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path = public

AS $$

DECLARE

  v_purchase RECORD;

  v_item RECORD;

  v_batch_number TEXT;

  v_date_str TEXT;

  v_seq INT := 0;

  v_station_product_name TEXT;

  v_cur_qty NUMERIC;

  v_cur_price NUMERIC;

  v_new_qty NUMERIC;

  v_new_price NUMERIC;

  v_total_foreign NUMERIC := 0;

  v_total_egp NUMERIC := 0;

  v_exchange_rate NUMERIC := 1.0;

  v_inventory_account_id INTEGER;

  v_supplier_leaf_account_id INTEGER;

  v_paid_amount NUMERIC;

  v_treasury_id TEXT;

  v_bank_account_id INTEGER;

  v_source_type TEXT;

  v_cash_account_id INTEGER;

  v_treasury_name TEXT;

  v_bank_name TEXT;

  v_treasury_balance_id BIGINT;

  v_balance_before NUMERIC;

  v_balance_after NUMERIC;

  v_payment_number TEXT;

  v_inv_currency TEXT;

  v_batches_created INT := 0;

  v_company_id UUID;

  v_inventory_je_id BIGINT;

  v_payment_je_id BIGINT;

  v_supplier_name TEXT;

  v_effective_user_id UUID;

BEGIN

  v_effective_user_id := COALESCE(p_user_id, auth.uid());



  -- ── PHASE 0a: Load Purchase Invoice ─────────────────────────────────────────

  SELECT * INTO v_purchase FROM purchase_invoices WHERE id::TEXT = p_purchase_id;

  IF NOT FOUND THEN

    RETURN jsonb_build_object('success', false, 'error', 'لم يتم العثور على الفاتورة');

  END IF;

  IF v_purchase.status = 'confirmed' THEN

    RETURN jsonb_build_object('success', true, 'message', 'تم التأكيد مسبقاً');

  END IF;



  v_date_str := to_char(COALESCE(v_purchase.invoice_date::date, now()::date), 'YYYYMMDD');

  v_inv_currency := COALESCE(v_purchase.currency, 'EGP');



  -- Determine transaction exchange rate

  SELECT COALESCE(NULLIF(exchange_rate, 0), 1.0) INTO v_exchange_rate 

  FROM purchase_invoice_items 

  WHERE invoice_id::TEXT = p_purchase_id 

  LIMIT 1;

  IF v_exchange_rate IS NULL OR v_exchange_rate <= 0 THEN 

    v_exchange_rate := COALESCE(NULLIF(v_purchase.exchange_rate, 0), 1.0);

  END IF;

  IF v_exchange_rate IS NULL OR v_exchange_rate <= 0 THEN v_exchange_rate := 1.0; END IF;



  -- ── PHASE 0a2: Resolve Company ID (from suppliers or sys_companies) ────────

  SELECT company_id INTO v_company_id FROM suppliers WHERE id = v_purchase.supplier_id;

  IF v_company_id IS NULL THEN

    SELECT id INTO v_company_id FROM sys_companies WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 1;

  END IF;

  IF v_company_id IS NULL THEN

    SELECT id INTO v_company_id FROM sys_companies LIMIT 1;

  END IF;

  IF v_company_id IS NULL THEN

    RAISE EXCEPTION 'لم يتم العثور على شركة صالحة';

  END IF;



  -- ── PHASE 0b: Resolve Supplier Leaf Account (Credit Account) ────────────────

  SELECT name INTO v_supplier_name FROM suppliers WHERE id = v_purchase.supplier_id;



  -- Priority 1: Use supplier's assigned account if valid, active, and allows posting

  SELECT a.id INTO v_supplier_leaf_account_id

  FROM suppliers s

  JOIN accounts a ON a.id = s.account_id

  WHERE s.id = v_purchase.supplier_id

    AND a.deleted_at IS NULL

    AND (a.allow_posting = TRUE OR a.is_leaf = TRUE);



  -- Priority 2: Lookup supplier's dedicated leaf sub-account under 2112

  IF v_supplier_leaf_account_id IS NULL THEN

    SELECT a.id INTO v_supplier_leaf_account_id

    FROM accounts a

    WHERE (a.account_code LIKE '2112%' OR a.parent_id = (SELECT id FROM accounts WHERE account_code = '2112' AND deleted_at IS NULL LIMIT 1))

      AND (a.account_name ILIKE '%' || v_supplier_name || '%' OR a.name ILIKE '%' || v_supplier_name || '%')

      AND a.deleted_at IS NULL

    ORDER BY a.id ASC

    LIMIT 1;

  END IF;



  -- Priority 3: Auto-create leaf account under 2112 if missing

  IF v_supplier_leaf_account_id IS NULL AND v_purchase.supplier_id IS NOT NULL THEN

    DECLARE

      v_p2112_id BIGINT;

      v_next_num INT;

      v_next_code TEXT;

    BEGIN

      SELECT id FROM accounts WHERE account_code = '2112' AND deleted_at IS NULL LIMIT 1 INTO v_p2112_id;

      IF v_p2112_id IS NOT NULL THEN

        SELECT COALESCE(MAX(SUBSTRING(account_code FROM 5)::INT), 0) + 1

        INTO v_next_num

        FROM accounts

        WHERE account_code ~ '^2112[0-9]+$' AND deleted_at IS NULL;



        v_next_code := '2112' || LPAD(COALESCE(v_next_num, 1)::TEXT, 2, '0');



        INSERT INTO accounts (

          account_code, name, account_name, account_type,

          parent_id, level, is_leaf, allow_posting, is_active, is_system, company_id

        ) VALUES (

          v_next_code,

          'Supplier - ' || COALESCE(v_supplier_name, 'Unknown'),

          'مورد - ' || COALESCE(v_supplier_name, 'غير محدد'),

          'liability',

          v_p2112_id,

          5,

          TRUE,

          TRUE,

          TRUE,

          FALSE,

          v_company_id

        ) RETURNING id INTO v_supplier_leaf_account_id;



        UPDATE suppliers SET account_id = v_supplier_leaf_account_id WHERE id = v_purchase.supplier_id;

      END IF;

    END;

  END IF;



  -- Priority 4: Fallback to Level 4 parent account 2112 (enable posting if needed)

  IF v_supplier_leaf_account_id IS NULL THEN

    SELECT id INTO v_supplier_leaf_account_id FROM accounts WHERE account_code = '2112' AND deleted_at IS NULL LIMIT 1;

    IF v_supplier_leaf_account_id IS NOT NULL THEN

      UPDATE accounts SET allow_posting = TRUE WHERE id = v_supplier_leaf_account_id;

    END IF;

  END IF;



  -- Priority 5: Fallback to legacy 2000

  IF v_supplier_leaf_account_id IS NULL THEN

    SELECT id INTO v_supplier_leaf_account_id FROM accounts WHERE account_code = '2000' AND deleted_at IS NULL LIMIT 1;

  END IF;



  IF v_supplier_leaf_account_id IS NULL THEN

    RAISE EXCEPTION 'لم يتم العثور على حساب المورد في شجرة الحسابات (دليل الحسابات)';

  END IF;



  -- ── PHASE 1: Stock Batches + Raw Materials + Station Products ───────────────

  FOR v_item IN

    SELECT pii.*, rm.code AS rm_code, rm.name AS rm_name, rm.unit AS rm_unit,

           rmc.name AS category_name

    FROM purchase_invoice_items pii

    LEFT JOIN raw_materials rm ON rm.id = pii.raw_material_id

    LEFT JOIN raw_material_categories rmc ON rmc.id = rm.category_id

    WHERE pii.invoice_id::TEXT = p_purchase_id

  LOOP

    v_seq := v_seq + 1;

    v_batch_number := 'B-' || v_date_str || '-' || v_purchase.id::TEXT || '-' || lpad(v_seq::TEXT, 4, '0');



    INSERT INTO stock_batches (

      batch_number, product_id, supplier_id, supplier_name, purchase_invoice_id,

      quantity, remaining_quantity, purchase_cost, average_cost,

      exchange_rate, currency, status, user_id

    ) VALUES (

      v_batch_number,

      v_item.raw_material_id,

      v_purchase.supplier_id,

      v_supplier_name,

      v_purchase.id,

      COALESCE(v_item.quantity, 0),

      COALESCE(v_item.quantity, 0),

      COALESCE(v_item.unit_cost, 0),

      COALESCE(v_item.unit_cost, 0),

      v_exchange_rate,

      v_inv_currency,

      'active',

      v_effective_user_id

    );

    v_batches_created := v_batches_created + 1;



    IF v_item.raw_material_id IS NOT NULL THEN

      SELECT quantity, default_purchase_price INTO v_cur_qty, v_cur_price

      FROM raw_materials WHERE id = v_item.raw_material_id;



      IF FOUND THEN

        v_cur_qty := COALESCE(v_cur_qty, 0);

        v_cur_price := COALESCE(v_cur_price, 0);

        v_new_qty := v_cur_qty + COALESCE(v_item.quantity, 0);

        IF v_new_qty > 0 THEN

          v_new_price := ((v_cur_qty * v_cur_price) + (COALESCE(v_item.quantity, 0) * COALESCE(v_item.unit_cost, 0))) / v_new_qty;

        ELSE

          v_new_price := COALESCE(v_item.unit_cost, 0);

        END IF;

        UPDATE raw_materials

        SET quantity = v_new_qty, default_purchase_price = v_new_price, updated_at = now()

        WHERE id = v_item.raw_material_id;

      END IF;



      DECLARE

        v_station_id BIGINT;

      BEGIN

        v_station_id := v_item.station_id;

        IF v_station_id IS NULL THEN

          SELECT spb.station_id INTO v_station_id

          FROM station_product_batches spb

          WHERE spb.product_code = COALESCE(v_item.rm_code, '') AND spb.source_type = 'purchase'

          LIMIT 1;

        END IF;

        IF v_station_id IS NULL THEN

          SELECT sp.station_id INTO v_station_id

          FROM station_products sp

          WHERE sp.product_code = COALESCE(v_item.rm_code, '') LIMIT 1;

        END IF;



        IF v_station_id IS NOT NULL THEN

          v_station_product_name := COALESCE(v_item.rm_name, '') || ' (مادة تعبئة)';

          PERFORM upsert_station_product_quantity(v_station_id, v_station_product_name, COALESCE(v_item.rm_code, ''), COALESCE(v_item.quantity, 0)::INT);



          INSERT INTO station_product_batches (

            station_id, product_name, product_code, quantity, remaining_quantity,

            unit_cost, currency, exchange_rate, source_type, source_date,

            supplier_name, purchase_invoice_id

          ) VALUES (

            v_station_id, v_station_product_name, COALESCE(v_item.rm_code, ''),

            COALESCE(v_item.quantity, 0), COALESCE(v_item.quantity, 0),

            COALESCE(v_item.unit_cost, 0), v_inv_currency, v_exchange_rate,

            'purchase', now(),

            v_supplier_name,

            v_purchase.id

          );

        END IF;

      END;

    END IF;



    v_total_foreign := v_total_foreign + (COALESCE(v_item.quantity, 0) * COALESCE(v_item.unit_cost, 0));

    v_total_egp := v_total_egp + (COALESCE(v_item.quantity, 0) * COALESCE(v_item.unit_cost, 0) * v_exchange_rate);

  END LOOP;



  v_paid_amount := COALESCE(v_purchase.paid_amount, 0);

  v_treasury_id := v_purchase.payment_treasury_id;

  v_bank_account_id := v_purchase.payment_bank_account_id;

  v_source_type := COALESCE(v_purchase.payment_source_type, 'treasury');



  -- Update Supplier Outstanding Balance in converted EGP to preserve multi-currency integrity

  IF v_purchase.supplier_id IS NOT NULL THEN

    DECLARE

      v_remaining NUMERIC;

      v_remaining_egp NUMERIC;

    BEGIN

      v_remaining := COALESCE(v_purchase.total_amount, 0) - v_paid_amount;

      v_remaining_egp := v_remaining * v_exchange_rate;

      IF v_remaining > 0 THEN

        UPDATE suppliers

        SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_remaining_egp

        WHERE id = v_purchase.supplier_id;

      END IF;

    END;

  END IF;



  -- ── PHASE 2: Granular Item-Level Inventory Journal Entry Lines ───────────────

  IF v_total_foreign > 0 THEN

    DECLARE

      v_lines_array JSONB := '[]'::jsonb;

      v_line_desc TEXT;

      v_item_line RECORD;

      v_item_foreign NUMERIC;

      v_item_egp NUMERIC;

      v_sum_debit_foreign NUMERIC := 0;

      v_sum_debit_egp NUMERIC := 0;

      v_items_summary TEXT := '';

      v_item_count INT := 0;

    BEGIN

      -- Loop through each purchased item to generate granular debit lines:

      FOR v_item_line IN

        SELECT

          pii.id,

          pii.quantity,

          pii.unit_cost,

          pii.raw_material_id,

          COALESCE(rm.name, rm.code, 'صنف غير محدد') AS item_name,

          COALESCE(rm.unit, '') AS item_unit,

          CASE 

            WHEN pii.raw_material_id IS NOT NULL THEN '12411'

            ELSE '12412'

          END AS inv_code

        FROM purchase_invoice_items pii

        LEFT JOIN raw_materials rm ON rm.id = pii.raw_material_id

        WHERE pii.invoice_id::TEXT = p_purchase_id

        ORDER BY pii.id ASC

      LOOP

        v_item_foreign := ROUND(COALESCE(v_item_line.quantity, 0) * COALESCE(v_item_line.unit_cost, 0), 2);

        v_item_egp := ROUND(v_item_foreign * v_exchange_rate, 2);



        v_sum_debit_foreign := v_sum_debit_foreign + v_item_foreign;

        v_sum_debit_egp := v_sum_debit_egp + v_item_egp;



        v_item_count := v_item_count + 1;

        IF v_item_count <= 3 THEN

          IF v_items_summary <> '' THEN

            v_items_summary := v_items_summary || ' + ';

          END IF;

          v_items_summary := v_items_summary || v_item_line.item_name || ' (' || v_item_line.quantity || 

            CASE WHEN v_item_line.item_unit <> '' THEN ' ' || v_item_line.item_unit ELSE '' END || 

            ' بسعر ' || v_item_line.unit_cost || ' ' || v_inv_currency || ')';

        END IF;



        -- Resolve target inventory account (12411 packaging / 12412 produce)

        SELECT id INTO v_inventory_account_id 

        FROM accounts 

        WHERE account_code = v_item_line.inv_code 

          AND company_id = v_company_id 

          AND deleted_at IS NULL 

        LIMIT 1;



        IF v_inventory_account_id IS NULL THEN

          SELECT id INTO v_inventory_account_id 

          FROM accounts 

          WHERE account_code = v_item_line.inv_code 

            AND deleted_at IS NULL 

          LIMIT 1;

        END IF;



        -- Fallback between 12411 and 12412 or parent 1241

        IF v_inventory_account_id IS NULL THEN

          IF v_item_line.inv_code = '12411' THEN

            SELECT id INTO v_inventory_account_id 

            FROM accounts 

            WHERE account_code IN ('12412', '1241') AND deleted_at IS NULL 

            ORDER BY account_code ASC LIMIT 1;

          ELSE

            SELECT id INTO v_inventory_account_id 

            FROM accounts 

            WHERE account_code IN ('12411', '1241') AND deleted_at IS NULL 

            ORDER BY account_code ASC LIMIT 1;

          END IF;

        END IF;



        -- Fallback to any inventory asset account

        IF v_inventory_account_id IS NULL THEN

          SELECT id INTO v_inventory_account_id 

          FROM accounts 

          WHERE account_code LIKE '124%' AND allow_posting = TRUE AND deleted_at IS NULL 

          LIMIT 1;

        END IF;



        -- Hard validation: Never silently skip debit line

        IF v_inventory_account_id IS NULL THEN

          RAISE EXCEPTION 'لم يتم العثور على حساب المخزون (%) في شجرة الحسابات', v_item_line.inv_code;

        END IF;



        -- Granular line description with item details

        v_line_desc := 'مخزون - ' || v_item_line.item_name || 

          ' - كمية: ' || v_item_line.quantity || 

          CASE WHEN v_item_line.item_unit <> '' THEN ' ' || v_item_line.item_unit ELSE '' END || 

          ' - بسعر: ' || v_item_line.unit_cost || ' ' || v_inv_currency ||

          ' - فاتورة ' || COALESCE(v_purchase.invoice_number, '');



        -- Granular Debit Line (مدين): Inventory Account per purchased item

        v_lines_array := v_lines_array || jsonb_build_object(

          'account_id', v_inventory_account_id,

          'debit', v_item_foreign,

          'base_debit', v_item_egp,

          'credit', 0,

          'base_credit', 0,

          'currency', v_inv_currency,

          'description', v_line_desc

        );

      END LOOP;



      IF v_item_count > 3 THEN

        v_items_summary := v_items_summary || ' (+ ' || (v_item_count - 3)::TEXT || ' أصناف أخرى)';

      END IF;



      -- Credit Line (دائن): Supplier Sub-Account strictly balancing all debit lines

      v_lines_array := v_lines_array || jsonb_build_object(

        'account_id', v_supplier_leaf_account_id,

        'debit', 0,

        'base_debit', 0,

        'credit', v_sum_debit_foreign,

        'base_credit', v_sum_debit_egp,

        'currency', v_inv_currency,

        'description', 'مستحقات مورد: ' || COALESCE(v_supplier_name, '') || ' - فاتورة ' || COALESCE(v_purchase.invoice_number, '') ||

                       CASE WHEN v_items_summary <> '' THEN ' [' || v_items_summary || ']' ELSE '' END

      );



      -- Post balanced inventory journal entry

      v_inventory_je_id := public.post_journal_entry(

        p_source_type := 'purchase_inventory',

        p_description := 'قيد مشتريات فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, '') ||

                         CASE WHEN v_items_summary <> '' THEN ': ' || v_items_summary ELSE '' END,

        p_entry_date  := COALESCE(v_purchase.invoice_date::date, now()::date),

        p_company_id  := v_company_id,

        p_created_by  := v_effective_user_id,

        p_lines       := v_lines_array,

        p_source_id   := v_purchase.id::TEXT

      );

      UPDATE purchase_invoices SET journal_entry_id = v_inventory_je_id WHERE id = v_purchase.id;

    END;

  END IF;



  -- ── PHASE 3: Payment Processing (Treasury or Bank) ─────────────────────────

  IF v_paid_amount > 0 AND COALESCE(v_purchase.payment_processed, false) = false THEN

    IF v_source_type = 'bank' AND v_bank_account_id IS NOT NULL THEN

      SELECT ba.name INTO v_bank_name FROM bank_accounts ba WHERE ba.id = v_bank_account_id;



      -- Resolve bank account under 1211 (12111 EGP, 12112 USD, 12113 EUR, 12114 GBP)

      SELECT id INTO v_cash_account_id FROM accounts

      WHERE account_code = (

        CASE v_inv_currency

          WHEN 'USD' THEN '12112'

          WHEN 'EUR' THEN '12113'

          WHEN 'GBP' THEN '12114'

          ELSE '12111'

        END

      ) AND company_id = v_company_id AND deleted_at IS NULL LIMIT 1;



      IF v_cash_account_id IS NULL THEN

        SELECT id INTO v_cash_account_id FROM accounts

        WHERE account_code = (

          CASE v_inv_currency

            WHEN 'USD' THEN '12112'

            WHEN 'EUR' THEN '12113'

            WHEN 'GBP' THEN '12114'

            ELSE '12111'

          END

        ) AND deleted_at IS NULL LIMIT 1;

      END IF;



      IF v_cash_account_id IS NULL THEN

        SELECT id INTO v_cash_account_id FROM accounts

        WHERE (account_code LIKE '1211%' OR account_code LIKE '121%') AND allow_posting = TRUE AND deleted_at IS NULL

        LIMIT 1;

      END IF;



      INSERT INTO bank_transactions (

        bank_account_id, type, amount, description, transaction_date,

        currency, exchange_rate, amount_in_base_currency, company_id

      ) VALUES (

        v_bank_account_id, 'withdrawal', v_paid_amount,

        'سداد فاتورة مشتريات رقم ' || COALESCE(v_purchase.invoice_number, '') || ' - المورد: ' || COALESCE(v_supplier_name, ''),

        COALESCE(v_purchase.invoice_date::date, now()::date),

        v_inv_currency, v_exchange_rate, (v_paid_amount * v_exchange_rate), v_company_id

      );



      UPDATE bank_accounts

      SET current_balance = COALESCE(current_balance, 0) - v_paid_amount, updated_at = now()

      WHERE id = v_bank_account_id;



      -- Post payment journal entry

      IF v_cash_account_id IS NOT NULL THEN

        v_payment_je_id := public.post_journal_entry(

          p_source_type := 'purchase_payment',

          p_description := 'سداد بنكي لمشتريات فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, ''),

          p_entry_date  := COALESCE(v_purchase.invoice_date::date, now()::date),

          p_company_id  := v_company_id,

          p_created_by  := v_effective_user_id,

          p_lines       := jsonb_build_array(

            jsonb_build_object(

              'account_id', v_supplier_leaf_account_id,

              'debit', v_paid_amount,

              'base_debit', (v_paid_amount * v_exchange_rate),

              'credit', 0,

              'base_credit', 0,

              'currency', v_inv_currency,

              'description', 'سداد مستحقات مورد: ' || COALESCE(v_supplier_name, '')

            ),

            jsonb_build_object(

              'account_id', v_cash_account_id,

              'debit', 0,

              'base_debit', 0,

              'credit', v_paid_amount,

              'base_credit', (v_paid_amount * v_exchange_rate),

              'currency', v_inv_currency,

              'description', 'صرف من بنك: ' || COALESCE(v_bank_name, '')

            )

          ),

          p_source_id   := v_purchase.id::TEXT

        );

      END IF;



    ELSIF v_treasury_id IS NOT NULL THEN

      SELECT name INTO v_treasury_name FROM treasuries WHERE id::TEXT = v_treasury_id;



      -- Resolve treasury GL account under 1221 (12211 EGP, 12212 USD, 12213 EUR, 12214 GBP)

      SELECT id INTO v_cash_account_id FROM accounts

      WHERE account_code = (

        CASE v_inv_currency

          WHEN 'USD' THEN '12212'

          WHEN 'EUR' THEN '12213'

          WHEN 'GBP' THEN '12214'

          ELSE '12211'

        END

      ) AND company_id = v_company_id AND deleted_at IS NULL LIMIT 1;



      IF v_cash_account_id IS NULL THEN

        SELECT id INTO v_cash_account_id FROM accounts

        WHERE account_code = (

          CASE v_inv_currency

            WHEN 'USD' THEN '12212'

            WHEN 'EUR' THEN '12213'

            WHEN 'GBP' THEN '12214'

            ELSE '12211'

          END

        ) AND deleted_at IS NULL LIMIT 1;

      END IF;



      IF v_cash_account_id IS NULL THEN

        SELECT id INTO v_cash_account_id FROM accounts

        WHERE account_code = (

          CASE v_inv_currency

            WHEN 'USD' THEN '12122'

            WHEN 'EUR' THEN '12123'

            WHEN 'GBP' THEN '12124'

            ELSE '12121'

          END

        ) AND deleted_at IS NULL LIMIT 1;

      END IF;



      IF v_cash_account_id IS NULL THEN

        SELECT id INTO v_cash_account_id FROM accounts

        WHERE (account_code LIKE '1212%' OR account_code LIKE '121%') AND allow_posting = TRUE AND deleted_at IS NULL

        LIMIT 1;

      END IF;



      -- Update treasury balance

      SELECT id, balance INTO v_treasury_balance_id, v_balance_before

      FROM treasury_balances

      WHERE treasury_id::TEXT = v_treasury_id AND currency = v_inv_currency

      LIMIT 1;



      IF v_treasury_balance_id IS NOT NULL THEN

        v_balance_after := v_balance_before - v_paid_amount;

        UPDATE treasury_balances SET balance = v_balance_after, updated_at = now() WHERE id = v_treasury_balance_id;

      ELSE

        v_balance_before := 0;

        v_balance_after := -v_paid_amount;

        INSERT INTO treasury_balances (treasury_id, currency, balance, created_at, updated_at)

        VALUES (v_treasury_id::UUID, v_inv_currency, v_balance_after, now(), now());

      END IF;



      v_payment_number := 'PAY-' || v_date_str || '-' || lpad(COALESCE(v_purchase.id, 0)::TEXT, 4, '0');



      INSERT INTO treasury_transactions (

        transaction_number, transaction_type, treasury_id, amount,

        balance_before, balance_after, transaction_date, notes, user_id,

        currency, exchange_rate, amount_in_base_currency, source_id, source_type,

        supplier_id, company_id

      ) VALUES (

        v_payment_number, 'supplier_payment', v_treasury_id::UUID, v_paid_amount,

        v_balance_before, v_balance_after,

        COALESCE(v_purchase.invoice_date::date, now()::date),

        'سداد فاتورة مشتريات رقم ' || COALESCE(v_purchase.invoice_number, '') || ' - المورد: ' || COALESCE(v_supplier_name, ''),

        v_effective_user_id, v_inv_currency, v_exchange_rate, (v_paid_amount * v_exchange_rate),

        v_purchase.id::TEXT, 'purchase_payment', v_purchase.supplier_id, v_company_id

      );



      -- Post payment journal entry

      IF v_cash_account_id IS NOT NULL THEN

        v_payment_je_id := public.post_journal_entry(

          p_source_type := 'purchase_payment',

          p_description := 'سداد نقدي لمشتريات فاتورة ' || COALESCE(v_purchase.invoice_number, '') || ' - ' || COALESCE(v_supplier_name, ''),

          p_entry_date  := COALESCE(v_purchase.invoice_date::date, now()::date),

          p_company_id  := v_company_id,

          p_created_by  := v_effective_user_id,

          p_lines       := jsonb_build_array(

            jsonb_build_object(

              'account_id', v_supplier_leaf_account_id,

              'debit', v_paid_amount,

              'base_debit', (v_paid_amount * v_exchange_rate),

              'credit', 0,

              'base_credit', 0,

              'currency', v_inv_currency,

              'description', 'سداد مستحقات مورد: ' || COALESCE(v_supplier_name, '')

            ),

            jsonb_build_object(

              'account_id', v_cash_account_id,

              'debit', 0,

              'base_debit', 0,

              'credit', v_paid_amount,

              'base_credit', (v_paid_amount * v_exchange_rate),

              'currency', v_inv_currency,

              'description', 'صرف من خزينة: ' || COALESCE(v_treasury_name, '')

            )

          ),

          p_source_id   := v_purchase.id::TEXT

        );

      END IF;

    END IF;



    UPDATE purchase_invoices SET payment_processed = true WHERE id = v_purchase.id;

  END IF;



  -- ── PHASE 4: Finalize Purchase Invoice Status ──────────────────────────────

  UPDATE purchase_invoices

  SET status = 'confirmed',

      updated_at = now()

  WHERE id = v_purchase.id;



  RETURN jsonb_build_object(

    'success', true,

    'message', 'تم تأكيد المشتريات وتوليد بنود القيد المحاسبي التفصيلية بنجاح',

    'batches_created', v_batches_created,

    'inventory_journal_entry_id', v_inventory_je_id,

    'payment_journal_entry_id', v_payment_je_id

  );

END;

$$;



GRANT EXECUTE ON FUNCTION public.rpc_confirm_purchase(TEXT, UUID) TO authenticated, anon, service_role;



-- ==============================================================================

-- Migration: 20260909000001_457_granular_crop_journal_entry_descriptions.sql

-- Description: Enhance sync_supplier_ledger_for_lot to generate item-level

--              granular journal entry line descriptions for crop purchases.

--

-- Changes:

--   1. Journal entry header: includes lot number, product name, supplier name

--   2. Debit line (inventory): includes crop item name, quantity (kg or cartons),

--      purchase mode, unit price, and currency

--   3. Credit line (supplier): includes supplier name, total amount in native

--      currency, and exchange rate info for foreign currencies

--   4. Price adjustment entries: include delta amounts and item name

-- ==============================================================================



BEGIN;



CREATE OR REPLACE FUNCTION public.sync_supplier_ledger_for_lot(

  p_lot_id BIGINT,

  p_action TEXT DEFAULT 'INSERT'

)

RETURNS VOID

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path = public

AS $$

DECLARE

  v_lot RECORD;

  v_company_id UUID;

  v_inventory_account_id BIGINT;

  v_supplier_leaf_account_id BIGINT;

  v_supplier_name TEXT;

  v_je_id BIGINT;

  v_desc TEXT;

  v_total_cost NUMERIC;

  v_product_name TEXT;

  v_total_egp NUMERIC;

  v_exchange_rate NUMERIC;

  v_lot_currency TEXT;

  v_old_supplier_cost NUMERIC;

  v_old_base_debit NUMERIC;

  v_delta_foreign NUMERIC;

  v_delta_egp NUMERIC;

  v_je_desc TEXT;

  -- New: item-level description variables

  v_debit_desc TEXT;

  v_credit_desc TEXT;

  v_qty_desc TEXT;

  v_unit_price_desc TEXT;

  v_currency_symbol TEXT;

  v_formula_desc TEXT;

  v_effective_weight NUMERIC;

BEGIN

  -- Handle DELETE

  IF p_action = 'DELETE' THEN

    SELECT * INTO v_lot FROM lot_receipts WHERE id = p_lot_id;

    IF v_lot.journal_entry_id IS NOT NULL THEN

      DELETE FROM journal_entries

      WHERE source_type IN ('lot_receipt', 'lot_price_adjustment')

        AND (source_id = p_lot_id::TEXT OR id = v_lot.journal_entry_id);



      IF v_lot.supplier_id IS NOT NULL THEN

        UPDATE suppliers

        SET outstanding_balance = COALESCE(outstanding_balance, 0) - COALESCE(v_lot.total_fruit_cost, 0)

        WHERE id = v_lot.supplier_id;

      END IF;



      UPDATE lot_receipts

      SET journal_entry_id = NULL

      WHERE id = p_lot_id;

    END IF;

    RETURN;

  END IF;



  -- Handle INSERT or UPDATE

  IF p_action IN ('INSERT', 'UPDATE') THEN

    SELECT * INTO v_lot FROM lot_receipts WHERE id = p_lot_id;

    IF NOT FOUND THEN RETURN; END IF;



    -- Only confirmed lots trigger double-entry GL posting

    IF v_lot.is_confirmed = true THEN

      v_total_cost := COALESCE(v_lot.total_fruit_cost, 0);

      IF v_total_cost <= 0 THEN RETURN; END IF;



      v_exchange_rate := COALESCE(NULLIF(v_lot.exchange_rate, 0), 1.0);

      v_total_egp := v_total_cost * v_exchange_rate;

      v_lot_currency := COALESCE(NULLIF(v_lot.currency, ''), 'EGP');

      v_product_name := COALESCE(v_lot.product_name, 'محصول');



      -- ── Resolve currency symbol for display ──

      v_currency_symbol := CASE UPPER(v_lot_currency)

        WHEN 'EGP' THEN 'ج.م'

        WHEN 'USD' THEN '$'

        WHEN 'EUR' THEN '€'

        WHEN 'GBP' THEN '£'

        ELSE v_lot_currency

      END;



      -- ── Build quantity description and active formula based on purchase mode ──

      IF COALESCE(v_lot.purchase_mode, 'weight') = 'carton' THEN

        v_qty_desc := COALESCE(v_lot.carton_count, 0)::TEXT || ' كرتونة';

        IF COALESCE(v_lot.price_per_carton, 0) > 0 THEN

          v_unit_price_desc := ROUND(v_lot.price_per_carton::NUMERIC, 2)::TEXT || ' ' || v_currency_symbol || '/كرتونة';

        ELSE

          v_unit_price_desc := '';

        END IF;

        -- Formula strictly cartons: e.g. 1000 كرتونة × 2.00 $ = 2,000.00 $

        v_formula_desc := COALESCE(v_lot.carton_count, 0)::TEXT || ' كرتونة × '

          || CASE 

               WHEN COALESCE(v_lot.price_per_carton, 0) > 0 THEN ROUND(v_lot.price_per_carton::NUMERIC, 2)::TEXT

               WHEN COALESCE(v_lot.carton_count, 0) > 0 THEN ROUND((v_total_cost / v_lot.carton_count)::NUMERIC, 2)::TEXT

               ELSE '0.00'

             END

          || ' ' || v_currency_symbol

          || ' = ' || ROUND(v_total_cost::NUMERIC, 2)::TEXT || ' ' || v_currency_symbol;

      ELSE

        -- Weight mode: Total Amount = Net Weight (الوزن الصافي) × Price per Unit/Kg (سعر الكيلو)

        v_effective_weight := CASE 

          WHEN COALESCE(v_lot.net_weight_kg, 0) > 0 THEN v_lot.net_weight_kg 

          ELSE COALESCE(v_lot.gross_weight_kg, 0) 

        END;

        v_qty_desc := ROUND(v_effective_weight::NUMERIC, 2)::TEXT || ' كجم (صافي)';

        IF v_effective_weight > 0 THEN

          v_unit_price_desc := ROUND((v_total_cost / v_effective_weight)::NUMERIC, 2)::TEXT || ' ' || v_currency_symbol || '/كجم';

        ELSE

          v_unit_price_desc := '';

        END IF;

        -- Formula: e.g. 500.00 كجم × 25.00 $ = 12,500.00 $

        v_formula_desc := ROUND(v_effective_weight::NUMERIC, 2)::TEXT || ' كجم × '

          || CASE 

               WHEN v_effective_weight > 0 THEN ROUND((v_total_cost / v_effective_weight)::NUMERIC, 2)::TEXT 

               ELSE '0.00' 

             END

          || ' ' || v_currency_symbol

          || ' = ' || ROUND(v_total_cost::NUMERIC, 2)::TEXT || ' ' || v_currency_symbol;

      END IF;



      -- ── Resolve Company ──

      IF v_lot.supplier_id IS NOT NULL THEN

        SELECT company_id, name INTO v_company_id, v_supplier_name FROM suppliers WHERE id = v_lot.supplier_id;

      END IF;

      IF v_company_id IS NULL THEN

        SELECT id INTO v_company_id FROM sys_companies WHERE deleted_at IS NULL LIMIT 1;

      END IF;

      IF v_company_id IS NULL THEN

        SELECT id INTO v_company_id FROM sys_companies LIMIT 1;

      END IF;



      -- ── Build granular line descriptions ──

      -- Debit: "مخزون المحاصيل - مانجو - كمية: 1000 كرتونة - سعر: 2.00 $/كرتونة (1000 كرتونة × 2.00 $ = 2,000.00 $) - لوط: LOT-00001"

      v_debit_desc := 'مخزون المحاصيل - ' || v_product_name

        || ' - كمية: ' || v_qty_desc;

      IF v_unit_price_desc != '' THEN

        v_debit_desc := v_debit_desc || ' - سعر: ' || v_unit_price_desc;

      END IF;

      v_debit_desc := v_debit_desc || ' (' || v_formula_desc || ')';

      v_debit_desc := v_debit_desc || ' - لوط: ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT);



      -- Credit: "مستحقات مورد - أحمد - مانجو (1000 كرتونة × 2.00 $ = 2,000.00 $) - لوط: LOT-00001"

      v_credit_desc := 'مستحقات مورد'

        || CASE WHEN v_supplier_name IS NOT NULL THEN ' - ' || v_supplier_name ELSE '' END

        || ' - ' || v_product_name

        || ' (' || v_formula_desc || ')';

      IF UPPER(v_lot_currency) != 'EGP' AND v_exchange_rate > 1.0 THEN

        v_credit_desc := v_credit_desc || ' [سعر صرف ' || ROUND(v_exchange_rate::NUMERIC, 2)::TEXT || ' ج.م]';

      END IF;

      v_credit_desc := v_credit_desc || ' - لوط: ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT);



      -- Header description: "شراء مانجو من أحمد - 1000 كرتونة × 2.00 $ = 2,000.00 $ - لوط: LOT-00001"

      v_desc := 'شراء ' || v_product_name

        || CASE WHEN v_supplier_name IS NOT NULL THEN ' من ' || v_supplier_name ELSE '' END

        || ' - ' || v_formula_desc

        || ' - لوط: ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT);



      -- ── Resolve Crop Inventory Account (12412 primary - مخزن مشتريات خام) ──

      SELECT a.id INTO v_inventory_account_id

      FROM accounts a

      WHERE a.account_code = '12412' AND a.is_leaf = true AND a.deleted_at IS NULL

      LIMIT 1;



      IF v_inventory_account_id IS NULL THEN

        SELECT a.id INTO v_inventory_account_id

        FROM accounts a

        WHERE a.account_code = '1241' AND a.deleted_at IS NULL

        LIMIT 1;

      END IF;



      IF v_inventory_account_id IS NULL THEN

        SELECT a.id INTO v_inventory_account_id

        FROM accounts a

        WHERE a.account_code LIKE '124%' AND a.is_leaf = true AND a.deleted_at IS NULL

        ORDER BY a.account_code ASC

        LIMIT 1;

      END IF;



      IF v_inventory_account_id IS NULL THEN

        SELECT a.id INTO v_inventory_account_id

        FROM accounts a

        WHERE a.account_code = '1030' AND a.deleted_at IS NULL

        LIMIT 1;

      END IF;



      IF v_inventory_account_id IS NULL THEN

        RAISE EXCEPTION 'لم يتم العثور على حساب مخزن مشتريات خام (12412)';

      END IF;



      -- ── Resolve Supplier Leaf Account (Credit Account) ──

      v_supplier_leaf_account_id := NULL;



      -- Priority 1: Assigned account on supplier if active and is_leaf

      IF v_lot.supplier_id IS NOT NULL THEN

        SELECT a.id INTO v_supplier_leaf_account_id

        FROM suppliers s

        JOIN accounts a ON a.id = s.account_id

        WHERE s.id = v_lot.supplier_id

          AND a.deleted_at IS NULL

          AND a.is_leaf = TRUE

          AND a.is_active = TRUE;

      END IF;



      -- Priority 2: Lookup active leaf sub-account under 2111 (Crop Suppliers) or legacy 2112

      IF v_supplier_leaf_account_id IS NULL AND v_supplier_name IS NOT NULL THEN

        SELECT a.id INTO v_supplier_leaf_account_id

        FROM accounts a

        WHERE (a.account_code LIKE '2111%' OR a.account_code LIKE '2112%' OR a.parent_id IN (SELECT id FROM accounts WHERE account_code IN ('2111', '2112') AND deleted_at IS NULL))

          AND (a.account_name ILIKE '%' || v_supplier_name || '%' OR a.name ILIKE '%' || v_supplier_name || '%')

          AND a.is_leaf = TRUE

          AND a.deleted_at IS NULL

        ORDER BY CASE WHEN a.account_code LIKE '2111%' THEN 1 ELSE 2 END, a.id ASC

        LIMIT 1;

      END IF;



      -- Priority 3: Auto-create leaf account under 2111 if missing

      IF v_supplier_leaf_account_id IS NULL AND v_lot.supplier_id IS NOT NULL THEN

        DECLARE

          v_p2111_id BIGINT;

          v_next_num INT;

          v_next_code TEXT;

        BEGIN

          SELECT id INTO v_p2111_id FROM accounts WHERE account_code = '2111' AND deleted_at IS NULL LIMIT 1;

          IF v_p2111_id IS NOT NULL THEN

            SELECT COALESCE(MAX(SUBSTRING(account_code FROM 5)::INT), 0) + 1

            INTO v_next_num

            FROM accounts

            WHERE account_code ~ '^2111[0-9]+$' AND deleted_at IS NULL;



            v_next_code := '2111' || LPAD(COALESCE(v_next_num, 1)::TEXT, 2, '0');



            INSERT INTO accounts (

              account_code, name, account_name, account_type,

              parent_id, level, is_leaf, allow_posting, is_active, is_system, company_id

            ) VALUES (

              v_next_code,

              'Supplier - ' || COALESCE(v_supplier_name, 'Crop Supplier'),

              'مورد - ' || COALESCE(v_supplier_name, 'مورد محاصيل'),

              'liability',

              v_p2111_id,

              5,

              TRUE,

              TRUE,

              TRUE,

              FALSE,

              v_company_id

            ) RETURNING id INTO v_supplier_leaf_account_id;



            UPDATE suppliers SET account_id = v_supplier_leaf_account_id WHERE id = v_lot.supplier_id;

          END IF;

        END;

      END IF;



      -- Priority 4: Fallback to general leaf account 21111 under 2111 or 211200

      IF v_supplier_leaf_account_id IS NULL THEN

        SELECT a.id INTO v_supplier_leaf_account_id

        FROM accounts a

        WHERE a.account_code IN ('21111', '211100', '211200', '2111', '2112') AND a.is_leaf = TRUE AND a.deleted_at IS NULL

        ORDER BY CASE WHEN a.account_code LIKE '2111%' THEN 1 ELSE 2 END, a.id ASC

        LIMIT 1;

      END IF;



      -- Priority 5: Fallback to any leaf under 2111 or 2112

      IF v_supplier_leaf_account_id IS NULL THEN

        SELECT a.id INTO v_supplier_leaf_account_id

        FROM accounts a

        WHERE (a.account_code LIKE '2111%' OR a.account_code LIKE '2112%') AND a.is_leaf = TRUE AND a.deleted_at IS NULL

        ORDER BY CASE WHEN a.account_code LIKE '2111%' THEN 1 ELSE 2 END, a.id ASC

        LIMIT 1;

      END IF;



      IF v_supplier_leaf_account_id IS NULL THEN

        RAISE EXCEPTION 'لم يتم العثور على حساب مورد المحاصيل في شجرة الحسابات';

      END IF;



      -- ── Check if an initial journal entry already exists for this lot ──

      SELECT id INTO v_je_id

      FROM public.journal_entries

      WHERE source_type = 'lot_receipt'

        AND source_id = p_lot_id::TEXT

        AND deleted_at IS NULL

      ORDER BY id ASC

      LIMIT 1;



      IF v_je_id IS NOT NULL THEN

        IF v_lot.journal_entry_id IS DISTINCT FROM v_je_id THEN

          UPDATE public.lot_receipts

          SET journal_entry_id = v_je_id

          WHERE id = p_lot_id;

          v_lot.journal_entry_id := v_je_id;

        END IF;



        -- Update existing journal entry description to granular format

        UPDATE public.journal_entries

        SET description = v_desc

        WHERE id = v_je_id;



        -- Update existing ledger line descriptions to granular format

        UPDATE public.account_ledger_entries

        SET description = v_debit_desc

        WHERE journal_entry_id = v_je_id AND account_id = v_inventory_account_id;



        UPDATE public.account_ledger_entries

        SET description = v_credit_desc

        WHERE journal_entry_id = v_je_id AND account_id = v_supplier_leaf_account_id;



        IF p_action != 'UPDATE' THEN

          RETURN;

        END IF;

      END IF;



      -- ── POST OR UPDATE JOURNAL ENTRY ──

      IF p_action = 'UPDATE' AND (v_lot.journal_entry_id IS NOT NULL OR v_je_id IS NOT NULL) THEN

        -- Price adjustment handling

        SELECT COALESCE(SUM(amount_in_base_currency * CASE WHEN debit > 0 THEN 1 WHEN credit > 0 THEN -1 ELSE 0 END), 0)

        INTO v_old_base_debit

        FROM account_ledger_entries

        WHERE journal_entry_id IN (

           SELECT id FROM journal_entries 

           WHERE source_type IN ('lot_receipt', 'lot_price_adjustment') AND source_id = p_lot_id::TEXT

        ) AND account_id = v_inventory_account_id;



        SELECT COALESCE(SUM(credit - debit), 0)

        INTO v_old_supplier_cost

        FROM account_ledger_entries

        WHERE journal_entry_id IN (

           SELECT id FROM journal_entries 

           WHERE source_type IN ('lot_receipt', 'lot_price_adjustment') AND source_id = p_lot_id::TEXT

        ) AND account_id = v_supplier_leaf_account_id;



        v_delta_foreign := v_total_cost - v_old_supplier_cost;

        v_delta_egp := v_total_egp - v_old_base_debit;



        IF ABS(v_delta_foreign) >= 0.01 OR ABS(v_delta_egp) >= 0.01 THEN

           v_je_desc := 'تعديل سعر ' || v_product_name

             || CASE WHEN v_supplier_name IS NOT NULL THEN ' - ' || v_supplier_name ELSE '' END

             || ' - فرق: ' || ROUND(ABS(v_delta_foreign)::NUMERIC, 2)::TEXT || ' ' || v_currency_symbol

             || CASE WHEN v_delta_foreign > 0 THEN ' (زيادة)' ELSE ' (نقص)' END

             || ' - لوط: ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT);

           

           v_je_id := public.post_journal_entry(

              p_source_type := 'lot_price_adjustment',

              p_description := v_je_desc,

              p_entry_date := COALESCE(v_lot.receipt_date, CURRENT_DATE),

              p_company_id := v_company_id,

              p_created_by := auth.uid(),

              p_lines := jsonb_build_array(

                jsonb_build_object(

                  'account_id', v_inventory_account_id,

                  'debit', CASE WHEN v_delta_egp > 0 THEN v_delta_egp ELSE 0 END,

                  'base_debit', CASE WHEN v_delta_egp > 0 THEN v_delta_egp ELSE 0 END,

                  'credit', CASE WHEN v_delta_egp < 0 THEN ABS(v_delta_egp) ELSE 0 END,

                  'base_credit', CASE WHEN v_delta_egp < 0 THEN ABS(v_delta_egp) ELSE 0 END,

                  'currency', 'EGP',

                  'description', 'تعديل مخزون - ' || v_product_name || ' - فرق: '

                    || ROUND(ABS(v_delta_egp)::NUMERIC, 2)::TEXT || ' ج.م'

                    || ' - لوط: ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT)

                ),

                jsonb_build_object(

                  'account_id', v_supplier_leaf_account_id,

                  'debit', CASE WHEN v_delta_foreign < 0 THEN ABS(v_delta_foreign) ELSE 0 END,

                  'base_debit', CASE WHEN v_delta_egp < 0 THEN ABS(v_delta_egp) ELSE 0 END,

                  'credit', CASE WHEN v_delta_foreign > 0 THEN v_delta_foreign ELSE 0 END,

                  'base_credit', CASE WHEN v_delta_egp > 0 THEN v_delta_egp ELSE 0 END,

                  'currency', v_lot_currency,

                  'description', 'تعديل مستحقات'

                    || CASE WHEN v_supplier_name IS NOT NULL THEN ' - ' || v_supplier_name ELSE '' END

                    || ' - ' || v_product_name || ' - فرق: '

                    || ROUND(ABS(v_delta_foreign)::NUMERIC, 2)::TEXT || ' ' || v_currency_symbol

                    || ' - لوط: ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT)

                )

              ),

              p_source_id := p_lot_id::TEXT

           );



           IF v_lot.supplier_id IS NOT NULL THEN

              UPDATE suppliers

              SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_delta_foreign

              WHERE id = v_lot.supplier_id;

           END IF;

        END IF;



      ELSIF v_je_id IS NULL AND v_lot.journal_entry_id IS NULL THEN

        -- INSERT new original balanced journal entry (only if none exists)

        v_je_id := public.post_journal_entry(

          p_source_type := 'lot_receipt',

          p_description := v_desc,

          p_entry_date := COALESCE(v_lot.receipt_date, CURRENT_DATE),

          p_company_id := v_company_id,

          p_created_by := auth.uid(),

          p_lines := jsonb_build_array(

            jsonb_build_object(

              'account_id', v_inventory_account_id,

              'debit', v_total_cost,

              'base_debit', v_total_egp,

              'credit', 0,

              'base_credit', 0,

              'currency', v_lot_currency,

              'description', v_debit_desc

            ),

            jsonb_build_object(

              'account_id', v_supplier_leaf_account_id,

              'debit', 0,

              'base_debit', 0,

              'credit', v_total_cost,

              'base_credit', v_total_egp,

              'currency', v_lot_currency,

              'description', v_credit_desc

            )

          ),

          p_source_id := p_lot_id::TEXT

        );



        UPDATE lot_receipts

        SET journal_entry_id = v_je_id

        WHERE id = p_lot_id;



        IF v_lot.supplier_id IS NOT NULL THEN

          UPDATE suppliers

          SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_total_cost

          WHERE id = v_lot.supplier_id;

        END IF;

      END IF;



    END IF;

  END IF;

END;

$$;



-- ── Backfill: Update existing crop journal entry descriptions to granular format ──

-- This updates all existing lot_receipt journal entries and their ledger lines

DO $$

DECLARE

  r RECORD;

  v_lot RECORD;

  v_supplier_name TEXT;

  v_product_name TEXT;

  v_currency_symbol TEXT;

  v_qty_desc TEXT;

  v_unit_price_desc TEXT;

  v_debit_desc TEXT;

  v_credit_desc TEXT;

  v_header_desc TEXT;

  v_exchange_rate NUMERIC;

  v_total_cost NUMERIC;

  v_lot_currency TEXT;

  v_inventory_account_id BIGINT;

  v_supplier_account_id BIGINT;

  v_formula_desc TEXT;

  v_effective_weight NUMERIC;

BEGIN

  -- Resolve inventory account (12412 Raw Crop Inventory - مخزن مشتريات خام)

  SELECT a.id INTO v_inventory_account_id

  FROM accounts a

  WHERE a.account_code = '12412' AND a.is_leaf = true AND a.deleted_at IS NULL

  LIMIT 1;



  IF v_inventory_account_id IS NULL THEN

    SELECT a.id INTO v_inventory_account_id

    FROM accounts a

    WHERE a.account_code = '1241' AND a.deleted_at IS NULL

    LIMIT 1;

  END IF;



  IF v_inventory_account_id IS NULL THEN

    SELECT a.id INTO v_inventory_account_id

    FROM accounts a

    WHERE a.account_code LIKE '124%' AND a.is_leaf = true AND a.deleted_at IS NULL

    ORDER BY a.account_code ASC

    LIMIT 1;

  END IF;



  IF v_inventory_account_id IS NULL THEN

    SELECT a.id INTO v_inventory_account_id

    FROM accounts a

    WHERE a.account_code = '1030' AND a.deleted_at IS NULL

    LIMIT 1;

  END IF;



  IF v_inventory_account_id IS NULL THEN

    RAISE NOTICE 'Skipping backfill: no inventory account found';

    RETURN;

  END IF;



  FOR r IN

    SELECT je.id AS je_id, je.source_id

    FROM journal_entries je

    WHERE je.source_type = 'lot_receipt'

      AND je.deleted_at IS NULL

  LOOP

    SELECT * INTO v_lot FROM lot_receipts WHERE id::TEXT = r.source_id;

    IF NOT FOUND THEN CONTINUE; END IF;



    v_product_name := COALESCE(v_lot.product_name, 'محصول');

    v_lot_currency := COALESCE(NULLIF(v_lot.currency, ''), 'EGP');

    v_exchange_rate := COALESCE(NULLIF(v_lot.exchange_rate, 0), 1.0);

    v_total_cost := COALESCE(v_lot.total_fruit_cost, 0);



    SELECT name INTO v_supplier_name FROM suppliers WHERE id = v_lot.supplier_id;



    v_currency_symbol := CASE UPPER(v_lot_currency)

      WHEN 'EGP' THEN 'ج.م'

      WHEN 'USD' THEN '$'

      WHEN 'EUR' THEN '€'

      WHEN 'GBP' THEN '£'

      ELSE v_lot_currency

    END;



    IF COALESCE(v_lot.purchase_mode, 'weight') = 'carton' THEN

      v_qty_desc := COALESCE(v_lot.carton_count, 0)::TEXT || ' كرتونة';

      IF COALESCE(v_lot.price_per_carton, 0) > 0 THEN

        v_unit_price_desc := ROUND(v_lot.price_per_carton::NUMERIC, 2)::TEXT || ' ' || v_currency_symbol || '/كرتونة';

      ELSE

        v_unit_price_desc := '';

      END IF;

      -- Formula strictly cartons: e.g. 1000 كرتونة × 2.00 $ = 2,000.00 $

      v_formula_desc := COALESCE(v_lot.carton_count, 0)::TEXT || ' كرتونة × '

        || CASE 

             WHEN COALESCE(v_lot.price_per_carton, 0) > 0 THEN ROUND(v_lot.price_per_carton::NUMERIC, 2)::TEXT

             WHEN COALESCE(v_lot.carton_count, 0) > 0 THEN ROUND((v_total_cost / v_lot.carton_count)::NUMERIC, 2)::TEXT

             ELSE '0.00'

           END

        || ' ' || v_currency_symbol

        || ' = ' || ROUND(v_total_cost::NUMERIC, 2)::TEXT || ' ' || v_currency_symbol;

    ELSE

      -- Weight mode: Total Amount = Net Weight (الوزن الصافي) × Price per Unit/Kg (سعر الكيلو)

      v_effective_weight := CASE 

        WHEN COALESCE(v_lot.net_weight_kg, 0) > 0 THEN v_lot.net_weight_kg 

        ELSE COALESCE(v_lot.gross_weight_kg, 0) 

      END;

      v_qty_desc := ROUND(v_effective_weight::NUMERIC, 2)::TEXT || ' كجم (صافي)';

      IF v_effective_weight > 0 THEN

        v_unit_price_desc := ROUND((v_total_cost / v_effective_weight)::NUMERIC, 2)::TEXT || ' ' || v_currency_symbol || '/كجم';

      ELSE

        v_unit_price_desc := '';

      END IF;

      -- Formula: e.g. 500.00 كجم × 25.00 $ = 12,500.00 $

      v_formula_desc := ROUND(v_effective_weight::NUMERIC, 2)::TEXT || ' كجم × '

        || CASE 

             WHEN v_effective_weight > 0 THEN ROUND((v_total_cost / v_effective_weight)::NUMERIC, 2)::TEXT 

             ELSE '0.00' 

           END

        || ' ' || v_currency_symbol

        || ' = ' || ROUND(v_total_cost::NUMERIC, 2)::TEXT || ' ' || v_currency_symbol;

    END IF;



    -- Debit: "مخزون المحاصيل - مانجو - كمية: 1000 كرتونة - سعر: 2.00 $/كرتونة (1000 كرتونة × 2.00 $ = 2,000.00 $) - لوط: LOT-00001"

    v_debit_desc := 'مخزون المحاصيل - ' || v_product_name

      || ' - كمية: ' || v_qty_desc;

    IF v_unit_price_desc != '' THEN

      v_debit_desc := v_debit_desc || ' - سعر: ' || v_unit_price_desc;

    END IF;

    v_debit_desc := v_debit_desc || ' (' || v_formula_desc || ')';

    v_debit_desc := v_debit_desc || ' - لوط: ' || COALESCE(v_lot.lot_number, r.source_id);



    -- Credit: "مستحقات مورد - أحمد - مانجو (1000 كرتونة × 2.00 $ = 2,000.00 $) - لوط: LOT-00001"

    v_credit_desc := 'مستحقات مورد'

      || CASE WHEN v_supplier_name IS NOT NULL THEN ' - ' || v_supplier_name ELSE '' END

      || ' - ' || v_product_name

      || ' (' || v_formula_desc || ')';

    IF UPPER(v_lot_currency) != 'EGP' AND v_exchange_rate > 1.0 THEN

      v_credit_desc := v_credit_desc || ' [سعر صرف ' || ROUND(v_exchange_rate::NUMERIC, 2)::TEXT || ' ج.م]';

    END IF;

    v_credit_desc := v_credit_desc || ' - لوط: ' || COALESCE(v_lot.lot_number, r.source_id);



    -- Header description: "شراء مانجو من أحمد - 1000 كرتونة × 2.00 $ = 2,000.00 $ - لوط: LOT-00001"

    v_header_desc := 'شراء ' || v_product_name

      || CASE WHEN v_supplier_name IS NOT NULL THEN ' من ' || v_supplier_name ELSE '' END

      || ' - ' || v_formula_desc

      || ' - لوط: ' || COALESCE(v_lot.lot_number, r.source_id);



    -- Update header

    UPDATE journal_entries SET description = v_header_desc WHERE id = r.je_id;



    -- Update debit line (inventory)

    UPDATE account_ledger_entries

    SET description = v_debit_desc

    WHERE journal_entry_id = r.je_id AND account_id = v_inventory_account_id;



    -- Update credit line (supplier) — match any account that is NOT the inventory account

    UPDATE account_ledger_entries

    SET description = v_credit_desc

    WHERE journal_entry_id = r.je_id AND account_id != v_inventory_account_id;



  END LOOP;



  RAISE NOTICE 'Backfill complete: updated all lot_receipt journal entry descriptions to granular format';

END $$;



COMMIT;



-- ============================================================================

-- Migration: 20260909000002_458_warehouse_transfer_explicit_descriptions.sql

-- Description: Refine inventory transfer journal entries to explicitly specify

--              source and destination warehouses in line descriptions and metadata.

-- ============================================================================



-- ── 1. Update Core Function: process_stock_transfer_journal ─────────────────

CREATE OR REPLACE FUNCTION public.process_stock_transfer_journal(

  p_transfer_id BIGINT

)

RETURNS BIGINT

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path = public

AS $$

DECLARE

  v_transfer RECORD;

  v_from_station_name TEXT;

  v_to_station_name TEXT;

  v_from_station_acc_id BIGINT;

  v_to_station_acc_id BIGINT;

  v_from_account_id BIGINT;

  v_to_account_id BIGINT;

  v_company_id UUID;

  v_unit_cost NUMERIC;

  v_total_cost NUMERIC;

  v_exchange_rate NUMERIC := 1.0;

  v_total_cost_base NUMERIC;

  v_currency TEXT;

  v_je_id BIGINT;

  v_desc TEXT;

  v_debit_desc TEXT;

  v_credit_desc TEXT;

  v_is_packaging BOOLEAN := false;

BEGIN

  -- 1. Fetch stock transfer record

  SELECT * INTO v_transfer FROM public.stock_transfers WHERE id = p_transfer_id;

  IF NOT FOUND THEN

    RETURN NULL;

  END IF;



  IF COALESCE(v_transfer.quantity, 0) <= 0 THEN

    RETURN NULL;

  END IF;



  -- 2. Resolve Company

  SELECT id INTO v_company_id FROM public.sys_companies WHERE deleted_at IS NULL LIMIT 1;

  IF v_company_id IS NULL THEN

    SELECT id INTO v_company_id FROM public.sys_companies LIMIT 1;

  END IF;



  -- 3. Resolve Stations

  SELECT name, inventory_account_id INTO v_from_station_name, v_from_station_acc_id

  FROM public.stations WHERE id = v_transfer.from_station_id;



  SELECT name, inventory_account_id INTO v_to_station_name, v_to_station_acc_id

  FROM public.stations WHERE id = v_transfer.to_station_id;



  v_from_station_name := COALESCE(NULLIF(TRIM(v_from_station_name), ''), 'مخزن #' || v_transfer.from_station_id);

  v_to_station_name := COALESCE(NULLIF(TRIM(v_to_station_name), ''), 'مخزن #' || v_transfer.to_station_id);



  -- 4. Check whether this product is packaging / raw material or fruit / produce

  IF v_transfer.product_name ILIKE '%تعبئة%' 

     OR v_transfer.product_name ILIKE '%كرتون%' 

     OR v_transfer.product_name ILIKE '%شريط%' 

     OR v_transfer.product_name ILIKE '%زاوية%' 

     OR v_transfer.product_name ILIKE '%بانيت%'

     OR v_transfer.product_name ILIKE '%مادة%' THEN

    v_is_packaging := true;

  END IF;



  -- 5. Resolve Valuation (Unit Cost & Total Cost)

  v_unit_cost := COALESCE(v_transfer.unit_cost, 0);

  v_total_cost := COALESCE(v_transfer.total_cost, 0);

  v_currency := COALESCE(NULLIF(v_transfer.currency, ''), 'EGP');



  -- If total cost is zero, try to look up from transferred batches in destination

  IF v_total_cost <= 0 THEN

    SELECT COALESCE(SUM(quantity * unit_cost), 0),

           COALESCE(MAX(currency), 'EGP'),

           COALESCE(MAX(exchange_rate), 1.0)

    INTO v_total_cost, v_currency, v_exchange_rate

    FROM public.station_product_batches

    WHERE station_id = v_transfer.to_station_id

      AND source_type = 'transfer'

      AND (product_code = v_transfer.product_code OR product_name = v_transfer.product_name)

      AND created_at >= (v_transfer.created_at - INTERVAL '1 minute')

      AND created_at <= (v_transfer.created_at + INTERVAL '1 minute');



    IF v_total_cost > 0 AND v_transfer.quantity > 0 THEN

      v_unit_cost := v_total_cost / v_transfer.quantity;

    END IF;

  END IF;



  -- If still zero, attempt to get latest unit_cost from source batches

  IF v_total_cost <= 0 THEN

    SELECT COALESCE(unit_cost, 0), COALESCE(currency, 'EGP'), COALESCE(exchange_rate, 1.0)

    INTO v_unit_cost, v_currency, v_exchange_rate

    FROM public.station_product_batches

    WHERE station_id = v_transfer.from_station_id

      AND (product_code = v_transfer.product_code OR product_name = v_transfer.product_name)

      AND unit_cost > 0

    ORDER BY created_at DESC

    LIMIT 1;



    IF v_unit_cost > 0 THEN

      v_total_cost := v_unit_cost * v_transfer.quantity;

    END IF;

  END IF;



  -- Fallback to fruit_types or raw_materials default

  IF v_total_cost <= 0 THEN

    IF v_is_packaging THEN

      SELECT COALESCE(unit_cost, 1.0) INTO v_unit_cost

      FROM public.raw_materials

      WHERE name = v_transfer.product_name OR code = v_transfer.product_code

      LIMIT 1;

    ELSE

      SELECT COALESCE(target_unit_price, 10.0) INTO v_unit_cost

      FROM public.fruit_types

      WHERE name = v_transfer.product_name OR code = v_transfer.product_code

      LIMIT 1;

    END IF;



    v_unit_cost := COALESCE(v_unit_cost, 1.0);

    v_total_cost := v_unit_cost * v_transfer.quantity;

  END IF;



  v_exchange_rate := COALESCE(NULLIF(v_exchange_rate, 0), 1.0);

  v_total_cost_base := v_total_cost * v_exchange_rate;



  -- 6. Resolve Sending Account (Credit)

  v_from_account_id := NULL;

  IF v_from_station_acc_id IS NOT NULL THEN

    SELECT id INTO v_from_account_id FROM public.accounts WHERE id = v_from_station_acc_id AND is_leaf = true AND deleted_at IS NULL;

  END IF;



  IF v_from_account_id IS NULL THEN

    IF v_is_packaging THEN

      SELECT id INTO v_from_account_id FROM public.accounts WHERE account_code = '12411' AND is_leaf = true AND deleted_at IS NULL LIMIT 1;

    ELSE

      SELECT id INTO v_from_account_id FROM public.accounts WHERE account_code = '12412' AND is_leaf = true AND deleted_at IS NULL LIMIT 1;

    END IF;

  END IF;



  IF v_from_account_id IS NULL THEN

    SELECT id INTO v_from_account_id FROM public.accounts WHERE account_code LIKE '124%' AND is_leaf = true AND deleted_at IS NULL ORDER BY account_code ASC LIMIT 1;

  END IF;



  -- 7. Resolve Receiving Account (Debit)

  v_to_account_id := NULL;

  IF v_to_station_acc_id IS NOT NULL THEN

    SELECT id INTO v_to_account_id FROM public.accounts WHERE id = v_to_station_acc_id AND is_leaf = true AND deleted_at IS NULL;

  END IF;



  IF v_to_account_id IS NULL THEN

    IF v_is_packaging THEN

      SELECT id INTO v_to_account_id FROM public.accounts WHERE account_code = '12411' AND is_leaf = true AND deleted_at IS NULL LIMIT 1;

    ELSE

      SELECT id INTO v_to_account_id FROM public.accounts WHERE account_code = '12412' AND is_leaf = true AND deleted_at IS NULL LIMIT 1;

    END IF;

  END IF;



  IF v_to_account_id IS NULL THEN

    SELECT id INTO v_to_account_id FROM public.accounts WHERE account_code LIKE '124%' AND is_leaf = true AND deleted_at IS NULL ORDER BY account_code ASC LIMIT 1;

  END IF;



  IF v_from_account_id IS NULL OR v_to_account_id IS NULL THEN

    RAISE EXCEPTION 'لم يتم العثور على حسابات المخزون المناسبة للتحويل';

  END IF;



  -- 8. Explicit Warehouse Descriptions

  v_desc := 'تحويل مخزني من ' || v_from_station_name || ' إلى ' || v_to_station_name || ' - ' || v_transfer.product_name;

  v_debit_desc := 'مخزون المحاصيل - مخزن ' || v_to_station_name || ' | إثبات تحويل مخزني وارد [إلى مخزن ' || v_to_station_name || '] من [مخزن ' || v_from_station_name || '] (' || v_transfer.product_name || ' - ' || v_transfer.quantity || ')';

  v_credit_desc := 'مخزون المحاصيل - مخزن ' || v_from_station_name || ' | إثبات تحويل مخزني منصرف [من مخزن ' || v_from_station_name || '] إلى [مخزن ' || v_to_station_name || '] (' || v_transfer.product_name || ' - ' || v_transfer.quantity || ')';



  -- 9. Idempotency Check: update lines if entry already exists

  SELECT id INTO v_je_id

  FROM public.journal_entries

  WHERE source_type = 'stock_transfer'

    AND source_id = p_transfer_id::TEXT

    AND deleted_at IS NULL

  LIMIT 1;



  IF v_je_id IS NOT NULL THEN

    -- Update entry description

    UPDATE public.journal_entries

    SET description = v_desc

    WHERE id = v_je_id;



    -- Update lines with explicit descriptions

    UPDATE public.journal_entry_lines

    SET description = v_debit_desc

    WHERE journal_entry_id = v_je_id AND debit > 0;



    UPDATE public.journal_entry_lines

    SET description = v_credit_desc

    WHERE journal_entry_id = v_je_id AND credit > 0;



    UPDATE public.stock_transfers

    SET journal_entry_id = v_je_id,

        unit_cost = v_unit_cost,

        total_cost = v_total_cost,

        currency = v_currency

    WHERE id = p_transfer_id;



    RETURN v_je_id;

  END IF;



  -- 10. Post Balanced Double-Entry Journal Entry

  v_je_id := public.post_journal_entry(

    p_source_type := 'stock_transfer',

    p_description := v_desc,

    p_entry_date := v_transfer.created_at::DATE,

    p_company_id := v_company_id,

    p_created_by := NULL,

    p_lines := jsonb_build_array(

      -- Debit: Receiving Warehouse

      jsonb_build_object(

        'account_id', v_to_account_id,

        'debit', v_total_cost,

        'base_debit', v_total_cost_base,

        'credit', 0,

        'base_credit', 0,

        'currency', v_currency,

        'description', v_debit_desc

      ),

      -- Credit: Sending Warehouse

      jsonb_build_object(

        'account_id', v_from_account_id,

        'debit', 0,

        'base_debit', 0,

        'credit', v_total_cost,

        'base_credit', v_total_cost_base,

        'currency', v_currency,

        'description', v_credit_desc

      )

    ),

    p_source_id := p_transfer_id::TEXT

  );



  -- 11. Link Journal Entry back to stock_transfers

  UPDATE public.stock_transfers

  SET journal_entry_id = v_je_id,

      unit_cost = v_unit_cost,

      total_cost = v_total_cost,

      currency = v_currency

  WHERE id = p_transfer_id;



  RETURN v_je_id;

END;

$$;



-- ── 2. Backfill Existing Transfer Entries ─────────────────────────────────────

DO $$

DECLARE

  r RECORD;

BEGIN

  FOR r IN (

    SELECT id FROM public.stock_transfers WHERE journal_entry_id IS NOT NULL

  ) LOOP

    BEGIN

      PERFORM public.process_stock_transfer_journal(r.id);

    EXCEPTION WHEN OTHERS THEN

      -- Silently continue loop

    END;

  END LOOP;

END;

$$;



-- ==============================================================================

-- Migration: 20260909000003_459_crop_purchase_gross_financial_net_inventory.sql

-- Description: Segregate Crop Purchase calculations so that supplier liability

--              and accounts payable credit lines are computed based on the Gross Total

--              (الوزن الإجمالي القائم × السعر), while inventory debit entries and physical

--              quantities track the Net Weight (الوزن الصافي), absorbing the full

--              contractual cost into an effective net unit cost.

-- ==============================================================================



BEGIN;



CREATE OR REPLACE FUNCTION public.sync_supplier_ledger_for_lot(

  p_lot_id BIGINT,

  p_action TEXT DEFAULT 'INSERT'

)

RETURNS VOID

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path = public

AS $$

DECLARE

  v_lot RECORD;

  v_company_id UUID;

  v_inventory_account_id BIGINT;

  v_supplier_leaf_account_id BIGINT;

  v_supplier_name TEXT;

  v_je_id BIGINT;

  v_desc TEXT;

  v_total_cost NUMERIC;

  v_product_name TEXT;

  v_total_egp NUMERIC;

  v_exchange_rate NUMERIC;

  v_lot_currency TEXT;

  v_old_supplier_cost NUMERIC;

  v_old_base_debit NUMERIC;

  v_delta_foreign NUMERIC;

  v_delta_egp NUMERIC;

  v_je_desc TEXT;

  v_debit_desc TEXT;

  v_credit_desc TEXT;

  v_qty_desc TEXT;

  v_unit_price_desc TEXT;

  v_currency_symbol TEXT;

  v_formula_desc TEXT;

  v_gross_weight NUMERIC;

  v_net_weight NUMERIC;

  v_price_per_kg NUMERIC;

  v_effective_cost_per_net_kg NUMERIC;

BEGIN

  -- Handle DELETE

  IF p_action = 'DELETE' THEN

    SELECT * INTO v_lot FROM lot_receipts WHERE id = p_lot_id;

    IF v_lot.journal_entry_id IS NOT NULL THEN

      DELETE FROM journal_entries

      WHERE source_type IN ('lot_receipt', 'lot_price_adjustment')

        AND (source_id = p_lot_id::TEXT OR id = v_lot.journal_entry_id);



      IF v_lot.supplier_id IS NOT NULL THEN

        UPDATE suppliers

        SET outstanding_balance = COALESCE(outstanding_balance, 0) - COALESCE(v_lot.total_fruit_cost, 0)

        WHERE id = v_lot.supplier_id;

      END IF;



      UPDATE lot_receipts

      SET journal_entry_id = NULL

      WHERE id = p_lot_id;

    END IF;

    RETURN;

  END IF;



  -- Handle INSERT or UPDATE

  IF p_action IN ('INSERT', 'UPDATE') THEN

    SELECT * INTO v_lot FROM lot_receipts WHERE id = p_lot_id;

    IF NOT FOUND THEN RETURN; END IF;



    -- Only confirmed lots trigger double-entry GL posting

    IF v_lot.is_confirmed = true THEN

      v_total_cost := COALESCE(v_lot.total_fruit_cost, 0);

      IF v_total_cost <= 0 THEN RETURN; END IF;



      v_exchange_rate := COALESCE(NULLIF(v_lot.exchange_rate, 0), 1.0);

      v_total_egp := v_total_cost * v_exchange_rate;

      v_lot_currency := COALESCE(NULLIF(v_lot.currency, ''), 'EGP');

      v_product_name := COALESCE(v_lot.product_name, 'محصول');



      -- Resolve currency symbol

      v_currency_symbol := CASE UPPER(v_lot_currency)

        WHEN 'EGP' THEN 'ج.م'

        WHEN 'USD' THEN '$'

        WHEN 'EUR' THEN '€'

        WHEN 'GBP' THEN '£'

        ELSE v_lot_currency

      END;



      -- Build quantity description and active formula based on purchase mode

      IF COALESCE(v_lot.purchase_mode, 'weight') = 'carton' THEN

        v_qty_desc := COALESCE(v_lot.carton_count, 0)::TEXT || ' كرتونة';

        IF COALESCE(v_lot.price_per_carton, 0) > 0 THEN

          v_unit_price_desc := ROUND(v_lot.price_per_carton::NUMERIC, 2)::TEXT || ' ' || v_currency_symbol || '/كرتونة';

        ELSE

          v_unit_price_desc := '';

        END IF;



        v_formula_desc := COALESCE(v_lot.carton_count, 0)::TEXT || ' كرتونة (إجمالي) × '

          || CASE 

               WHEN COALESCE(v_lot.price_per_carton, 0) > 0 THEN ROUND(v_lot.price_per_carton::NUMERIC, 2)::TEXT

               WHEN COALESCE(v_lot.carton_count, 0) > 0 THEN ROUND((v_total_cost / v_lot.carton_count)::NUMERIC, 2)::TEXT

               ELSE '0.00'

             END

          || ' ' || v_currency_symbol

          || ' = ' || ROUND(v_total_cost::NUMERIC, 2)::TEXT || ' ' || v_currency_symbol;

      ELSE

        -- Weight mode: Financial total credited to supplier is based on Gross Weight (الوزن الإجمالي)

        v_gross_weight := CASE 

          WHEN COALESCE(v_lot.gross_weight_kg, 0) > 0 THEN v_lot.gross_weight_kg 

          ELSE COALESCE(v_lot.net_weight_kg, 0) 

        END;

        v_net_weight := CASE 

          WHEN COALESCE(v_lot.net_weight_kg, 0) > 0 THEN v_lot.net_weight_kg 

          ELSE v_gross_weight 

        END;



        v_price_per_kg := CASE 

          WHEN v_gross_weight > 0 THEN (v_total_cost / v_gross_weight)

          ELSE 0 

        END;



        v_effective_cost_per_net_kg := CASE 

          WHEN v_net_weight > 0 THEN (v_total_cost / v_net_weight)

          ELSE v_price_per_kg 

        END;



        -- Inventory tracks physical Net Weight

        v_qty_desc := ROUND(v_net_weight::NUMERIC, 2)::TEXT || ' كجم (صافي)';

        v_unit_price_desc := ROUND(v_effective_cost_per_net_kg::NUMERIC, 2)::TEXT || ' ' || v_currency_symbol || '/كجم (صافي)';



        -- Formula explicitly shows Gross metric used for financial liability

        v_formula_desc := ROUND(v_gross_weight::NUMERIC, 2)::TEXT || ' كجم (إجمالي) × '

          || ROUND(v_price_per_kg::NUMERIC, 2)::TEXT || ' ' || v_currency_symbol

          || ' = ' || ROUND(v_total_cost::NUMERIC, 2)::TEXT || ' ' || v_currency_symbol;



        IF v_net_weight > 0 AND ABS(v_gross_weight - v_net_weight) > 0.001 THEN

          v_formula_desc := v_formula_desc || ' [صافي المخزن: ' || ROUND(v_net_weight::NUMERIC, 2)::TEXT || ' كجم]';

        END IF;

      END IF;



      -- Resolve Company

      IF v_lot.supplier_id IS NOT NULL THEN

        SELECT company_id, name INTO v_company_id, v_supplier_name FROM suppliers WHERE id = v_lot.supplier_id;

      END IF;

      IF v_company_id IS NULL THEN

        SELECT id INTO v_company_id FROM sys_companies WHERE deleted_at IS NULL LIMIT 1;

      END IF;

      IF v_company_id IS NULL THEN

        SELECT id INTO v_company_id FROM sys_companies LIMIT 1;

      END IF;



      -- Build granular line descriptions

      -- Debit (Inventory): explicitly documents Net physical quantity and absorbed cost

      v_debit_desc := 'مخزن مشتريات خام - ' || v_product_name

        || ' - كمية: ' || v_qty_desc;

      IF v_unit_price_desc != '' THEN

        v_debit_desc := v_debit_desc || ' - تكلفة: ' || v_unit_price_desc;

      END IF;

      v_debit_desc := v_debit_desc || ' (' || v_formula_desc || ')';

      v_debit_desc := v_debit_desc || ' - لوط: ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT);



      -- Credit (Supplier): explicitly documents gross total liability

      v_credit_desc := 'مستحقات مورد (إجمالي)'

        || CASE WHEN v_supplier_name IS NOT NULL THEN ' - ' || v_supplier_name ELSE '' END

        || ' - ' || v_product_name

        || ' (' || v_formula_desc || ')';

      IF UPPER(v_lot_currency) != 'EGP' AND v_exchange_rate > 1.0 THEN

        v_credit_desc := v_credit_desc || ' [سعر صرف ' || ROUND(v_exchange_rate::NUMERIC, 2)::TEXT || ' ج.م]';

      END IF;

      v_credit_desc := v_credit_desc || ' - لوط: ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT);



      -- Header description

      v_desc := 'شراء ' || v_product_name

        || CASE WHEN v_supplier_name IS NOT NULL THEN ' من ' || v_supplier_name ELSE '' END

        || ' (حساب إجمالي) - ' || v_formula_desc

        || ' - لوط: ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT);



      -- ── Resolve Crop Inventory Account (12412 primary - مخزن مشتريات خام) ──

      SELECT a.id INTO v_inventory_account_id

      FROM accounts a

      WHERE a.account_code = '12412' AND a.is_leaf = true AND a.deleted_at IS NULL

      LIMIT 1;



      IF v_inventory_account_id IS NULL THEN

        SELECT a.id INTO v_inventory_account_id

        FROM accounts a

        WHERE a.account_code = '1241' AND a.deleted_at IS NULL

        LIMIT 1;

      END IF;



      IF v_inventory_account_id IS NULL THEN

        SELECT a.id INTO v_inventory_account_id

        FROM accounts a

        WHERE a.account_code LIKE '124%' AND a.is_leaf = true AND a.deleted_at IS NULL

        ORDER BY a.account_code ASC

        LIMIT 1;

      END IF;



      IF v_inventory_account_id IS NULL THEN

        SELECT a.id INTO v_inventory_account_id

        FROM accounts a

        WHERE a.account_code = '1030' AND a.deleted_at IS NULL

        LIMIT 1;

      END IF;



      IF v_inventory_account_id IS NULL THEN

        RAISE EXCEPTION 'لم يتم العثور على حساب مخزن مشتريات خام (12412)';

      END IF;



      -- ── Resolve Supplier Leaf Account (Credit Account) ──

      v_supplier_leaf_account_id := NULL;



      -- Priority 1: Assigned account on supplier if active and is_leaf

      IF v_lot.supplier_id IS NOT NULL THEN

        SELECT a.id INTO v_supplier_leaf_account_id

        FROM suppliers s

        JOIN accounts a ON a.id = s.account_id

        WHERE s.id = v_lot.supplier_id

          AND a.deleted_at IS NULL

          AND a.is_leaf = TRUE

          AND a.is_active = TRUE;

      END IF;



      -- Priority 2: Lookup active leaf sub-account under 2111 (Crop Suppliers) or legacy 2112

      IF v_supplier_leaf_account_id IS NULL AND v_supplier_name IS NOT NULL THEN

        SELECT a.id INTO v_supplier_leaf_account_id

        FROM accounts a

        WHERE (a.account_code LIKE '2111%' OR a.account_code LIKE '2112%' OR a.parent_id IN (SELECT id FROM accounts WHERE account_code IN ('2111', '2112') AND deleted_at IS NULL))

          AND (a.account_name ILIKE '%' || v_supplier_name || '%' OR a.name ILIKE '%' || v_supplier_name || '%')

          AND a.is_leaf = TRUE

          AND a.deleted_at IS NULL

        ORDER BY CASE WHEN a.account_code LIKE '2111%' THEN 1 ELSE 2 END, a.id ASC

        LIMIT 1;

      END IF;



      -- Priority 3: Auto-create leaf account under 2111 if missing

      IF v_supplier_leaf_account_id IS NULL AND v_lot.supplier_id IS NOT NULL THEN

        DECLARE

          v_p2111_id BIGINT;

          v_next_num INT;

          v_next_code TEXT;

        BEGIN

          SELECT id INTO v_p2111_id FROM accounts WHERE account_code = '2111' AND deleted_at IS NULL LIMIT 1;

          IF v_p2111_id IS NOT NULL THEN

            SELECT COALESCE(MAX(SUBSTRING(account_code FROM 5)::INT), 0) + 1

            INTO v_next_num

            FROM accounts

            WHERE account_code ~ '^2111[0-9]+$' AND deleted_at IS NULL;



            v_next_code := '2111' || LPAD(COALESCE(v_next_num, 1)::TEXT, 2, '0');



            INSERT INTO accounts (

              account_code, name, account_name, account_type,

              parent_id, level, is_leaf, allow_posting, is_active, is_system, company_id

            ) VALUES (

              v_next_code,

              'Supplier - ' || COALESCE(v_supplier_name, 'Crop Supplier'),

              'مورد - ' || COALESCE(v_supplier_name, 'مورد محاصيل'),

              'liability',

              v_p2111_id,

              5,

              TRUE,

              TRUE,

              TRUE,

              TRUE,

              v_company_id

            ) RETURNING id INTO v_supplier_leaf_account_id;



            UPDATE suppliers SET account_id = v_supplier_leaf_account_id WHERE id = v_lot.supplier_id;

          END IF;

        END;

      END IF;



      -- Priority 4: Fallback to general leaf account 21111 under 2111 or 211200

      IF v_supplier_leaf_account_id IS NULL THEN

        SELECT a.id INTO v_supplier_leaf_account_id

        FROM accounts a

        WHERE a.account_code IN ('21111', '211100', '211200', '2111', '2112') AND a.is_leaf = TRUE AND a.deleted_at IS NULL

        ORDER BY CASE WHEN a.account_code LIKE '2111%' THEN 1 ELSE 2 END, a.id ASC

        LIMIT 1;

      END IF;



      -- Priority 5: Fallback to any leaf under 2111 or 2112

      IF v_supplier_leaf_account_id IS NULL THEN

        SELECT a.id INTO v_supplier_leaf_account_id

        FROM accounts a

        WHERE (a.account_code LIKE '2111%' OR a.account_code LIKE '2112%') AND a.is_leaf = TRUE AND a.deleted_at IS NULL

        ORDER BY CASE WHEN a.account_code LIKE '2111%' THEN 1 ELSE 2 END, a.id ASC

        LIMIT 1;

      END IF;



      IF v_supplier_leaf_account_id IS NULL THEN

        RAISE EXCEPTION 'لم يتم العثور على حساب مورد المحاصيل في شجرة الحسابات';

      END IF;



      -- Check if an initial journal entry already exists for this lot

      SELECT id INTO v_je_id

      FROM public.journal_entries

      WHERE source_type = 'lot_receipt'

        AND source_id = p_lot_id::TEXT

        AND deleted_at IS NULL

      ORDER BY id ASC

      LIMIT 1;



      IF v_je_id IS NOT NULL THEN

        IF v_lot.journal_entry_id IS DISTINCT FROM v_je_id THEN

          UPDATE public.lot_receipts

          SET journal_entry_id = v_je_id

          WHERE id = p_lot_id;

          v_lot.journal_entry_id := v_je_id;

        END IF;



        -- Update existing journal entry description to gross/net granular format

        UPDATE public.journal_entries

        SET description = v_desc

        WHERE id = v_je_id;



        -- Update existing ledger line descriptions

        UPDATE public.account_ledger_entries

        SET description = v_debit_desc

        WHERE journal_entry_id = v_je_id AND account_id = v_inventory_account_id;



        UPDATE public.account_ledger_entries

        SET description = v_credit_desc

        WHERE journal_entry_id = v_je_id AND account_id = v_supplier_leaf_account_id;



        IF p_action != 'UPDATE' THEN

          RETURN;

        END IF;

      END IF;



      -- POST OR UPDATE JOURNAL ENTRY

      IF p_action = 'UPDATE' AND (v_lot.journal_entry_id IS NOT NULL OR v_je_id IS NOT NULL) THEN

        -- Price adjustment handling

        SELECT COALESCE(SUM(amount_in_base_currency * CASE WHEN debit > 0 THEN 1 WHEN credit > 0 THEN -1 ELSE 0 END), 0)

        INTO v_old_base_debit

        FROM account_ledger_entries

        WHERE journal_entry_id IN (

           SELECT id FROM journal_entries 

           WHERE source_type IN ('lot_receipt', 'lot_price_adjustment') AND source_id = p_lot_id::TEXT

        ) AND account_id = v_inventory_account_id;



        SELECT COALESCE(SUM(credit - debit), 0)

        INTO v_old_supplier_cost

        FROM account_ledger_entries

        WHERE journal_entry_id IN (

           SELECT id FROM journal_entries 

           WHERE source_type IN ('lot_receipt', 'lot_price_adjustment') AND source_id = p_lot_id::TEXT

        ) AND account_id = v_supplier_leaf_account_id;



        v_delta_foreign := v_total_cost - v_old_supplier_cost;

        v_delta_egp := v_total_egp - v_old_base_debit;



        IF ABS(v_delta_foreign) > 0.001 OR ABS(v_delta_egp) > 0.001 THEN

           v_je_desc := 'تعديل سعر محصول ' || v_product_name

             || CASE WHEN v_supplier_name IS NOT NULL THEN ' للمورد ' || v_supplier_name ELSE '' END

             || ' - فرق: ' || ROUND(v_delta_foreign::NUMERIC, 2)::TEXT || ' ' || v_currency_symbol

             || ' (' || v_formula_desc || ')'

             || ' - لوط: ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT);



           PERFORM public.post_journal_entry(

              p_source_type := 'lot_price_adjustment',

              p_description := v_je_desc,

              p_entry_date := CURRENT_DATE,

              p_company_id := v_company_id,

              p_created_by := auth.uid(),

              p_lines := jsonb_build_array(

                jsonb_build_object(

                  'account_id', v_inventory_account_id,

                  'debit', CASE WHEN v_delta_egp > 0 THEN v_delta_egp ELSE 0 END,

                  'base_debit', CASE WHEN v_delta_egp > 0 THEN v_delta_egp ELSE 0 END,

                  'credit', CASE WHEN v_delta_egp < 0 THEN ABS(v_delta_egp) ELSE 0 END,

                  'base_credit', CASE WHEN v_delta_egp < 0 THEN ABS(v_delta_egp) ELSE 0 END,

                  'currency', 'EGP',

                  'description', 'تعديل مخزون - ' || v_product_name || ' - فرق: '

                    || ROUND(ABS(v_delta_egp)::NUMERIC, 2)::TEXT || ' ج.م'

                    || ' - لوط: ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT)

                ),

                jsonb_build_object(

                  'account_id', v_supplier_leaf_account_id,

                  'debit', CASE WHEN v_delta_foreign < 0 THEN ABS(v_delta_foreign) ELSE 0 END,

                  'base_debit', CASE WHEN v_delta_egp < 0 THEN ABS(v_delta_egp) ELSE 0 END,

                  'credit', CASE WHEN v_delta_foreign > 0 THEN v_delta_foreign ELSE 0 END,

                  'base_credit', CASE WHEN v_delta_egp > 0 THEN v_delta_egp ELSE 0 END,

                  'currency', v_lot_currency,

                  'description', 'تعديل مستحقات مورد (إجمالي)'

                    || CASE WHEN v_supplier_name IS NOT NULL THEN ' - ' || v_supplier_name ELSE '' END

                    || ' - ' || v_product_name || ' - فرق: '

                    || ROUND(ABS(v_delta_foreign)::NUMERIC, 2)::TEXT || ' ' || v_currency_symbol

                    || ' - لوط: ' || COALESCE(v_lot.lot_number, p_lot_id::TEXT)

                )

              ),

              p_source_id := p_lot_id::TEXT

           );



           IF v_lot.supplier_id IS NOT NULL THEN

              UPDATE suppliers

              SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_delta_foreign

              WHERE id = v_lot.supplier_id;

           END IF;

        END IF;



      ELSIF v_je_id IS NULL AND v_lot.journal_entry_id IS NULL THEN

        -- INSERT new original balanced journal entry (only if none exists)

        v_je_id := public.post_journal_entry(

          p_source_type := 'lot_receipt',

          p_description := v_desc,

          p_entry_date := COALESCE(v_lot.receipt_date, CURRENT_DATE),

          p_company_id := v_company_id,

          p_created_by := auth.uid(),

          p_lines := jsonb_build_array(

            jsonb_build_object(

              'account_id', v_inventory_account_id,

              'debit', v_total_cost,

              'base_debit', v_total_egp,

              'credit', 0,

              'base_credit', 0,

              'currency', v_lot_currency,

              'description', v_debit_desc

            ),

            jsonb_build_object(

              'account_id', v_supplier_leaf_account_id,

              'debit', 0,

              'base_debit', 0,

              'credit', v_total_cost,

              'base_credit', v_total_egp,

              'currency', v_lot_currency,

              'description', v_credit_desc

            )

          ),

          p_source_id := p_lot_id::TEXT

        );



        UPDATE public.lot_receipts

        SET journal_entry_id = v_je_id

        WHERE id = p_lot_id;



        IF v_lot.supplier_id IS NOT NULL THEN

          UPDATE suppliers

          SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_total_cost

          WHERE id = v_lot.supplier_id;

        END IF;

      END IF;



    END IF; -- is_confirmed

  END IF; -- INSERT or UPDATE

END;

$$;



-- ── Balance Calculator for Transport Suppliers (Financial & Operational) ──

DROP FUNCTION IF EXISTS public.get_transport_supplier_true_balances();



CREATE OR REPLACE FUNCTION public.get_transport_supplier_true_balances()

RETURNS TABLE (

  supplier_id integer,

  true_balance numeric,

  financial_balance numeric,

  truck_balance numeric

)

LANGUAGE sql

SECURITY DEFINER

AS $func$

  SELECT

    ts.id AS supplier_id,

    (

      (CASE WHEN ts.initial_balance_direction = 'CREDIT' THEN COALESCE(ts.initial_balance, 0) ELSE -COALESCE(ts.initial_balance, 0) END)

      + COALESCE((

          SELECT SUM(tt.amount)

          FROM public.transport_transactions tt

          WHERE tt.supplier_id = ts.id AND tt.type = 'invoice'

        ), 0)

      - COALESCE((

          SELECT SUM(tt.amount)

          FROM public.transport_transactions tt

          WHERE tt.supplier_id = ts.id AND tt.type IN ('cash_payment', 'bank_payment')

        ), 0)

    )::numeric AS true_balance,



    (

      (CASE WHEN ts.initial_balance_direction = 'CREDIT' THEN COALESCE(ts.initial_balance, 0) ELSE -COALESCE(ts.initial_balance, 0) END)

      + COALESCE((

          SELECT SUM(tt.amount)

          FROM public.transport_transactions tt

          WHERE tt.supplier_id = ts.id AND tt.type = 'invoice'

        ), 0)

      - COALESCE((

          SELECT SUM(tt.amount)

          FROM public.transport_transactions tt

          WHERE tt.supplier_id = ts.id AND tt.type IN ('cash_payment', 'bank_payment')

        ), 0)

    )::numeric AS financial_balance,



    (

      COALESCE(ts.initial_truck_balance, 0)

      + COALESCE((

          SELECT SUM(COALESCE(tt.truck_count, 1))

          FROM public.transport_transactions tt

          WHERE tt.supplier_id = ts.id AND tt.type IN ('invoice')

        ), 0)

      - COALESCE((

          SELECT SUM(COALESCE(tt.truck_count, 1))

          FROM public.transport_transactions tt

          WHERE tt.supplier_id = ts.id AND tt.type IN ('packing_consumption', 'packing_order_consumption', 'packing_order_invoice')

        ), 0)

    )::numeric AS truck_balance

  FROM public.transport_suppliers ts;

$func$;



GRANT EXECUTE ON FUNCTION public.get_transport_supplier_true_balances() TO authenticated, anon, service_role;



-- ── rpc_sync_vendor_balances_and_ledger: Vendor Balance Recalc + Ledger Sync ──

CREATE OR REPLACE FUNCTION public.rpc_sync_vendor_balances_and_ledger()

RETURNS JSONB

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path = public

AS $$

DECLARE

    r RECORD;

    v_total_cost NUMERIC;

    v_shipping_updated INT := 0;

    v_ca_updated INT := 0;

    v_le_upserted INT := 0;

    v_le_deleted INT := 0;

BEGIN

    -- Shipping companies: recalculate balance

    FOR r IN

        SELECT sci.vendor_id AS comp_id,

               COALESCE(SUM(sci.total_price / NULLIF(sci.exchange_rate, 0)), 0) AS total_cost

        FROM public.shipment_cost_items sci

        WHERE sci.vendor_type = 'shipping_company' AND sci.vendor_id IS NOT NULL

        GROUP BY sci.vendor_id

    LOOP

        UPDATE public.shipping_companies

        SET balance = COALESCE(initial_balance, 0) + r.total_cost + COALESCE(manual_adjustment, 0)

        WHERE id = r.comp_id;

        v_shipping_updated := v_shipping_updated + 1;

    END LOOP;



    UPDATE public.shipping_companies sc

    SET balance = COALESCE(sc.initial_balance, 0) + COALESCE(sc.manual_adjustment, 0)

    WHERE sc.id NOT IN (

        SELECT DISTINCT vendor_id FROM public.shipment_cost_items

        WHERE vendor_type = 'shipping_company' AND vendor_id IS NOT NULL

    );



    -- Clearing agents: recalculate balance

    FOR r IN

        SELECT sci.vendor_id AS agent_id,

               COALESCE(SUM(sci.total_price / NULLIF(sci.exchange_rate, 0)), 0) AS total_cost

        FROM public.shipment_cost_items sci

        WHERE sci.vendor_type = 'clearing_agent' AND sci.vendor_id IS NOT NULL

        GROUP BY sci.vendor_id

    LOOP

        UPDATE public.clearing_agents

        SET balance = COALESCE(initial_balance, 0) + r.total_cost + COALESCE(manual_adjustment, 0)

        WHERE id = r.agent_id;

        v_ca_updated := v_ca_updated + 1;

    END LOOP;



    UPDATE public.clearing_agents ca

    SET balance = COALESCE(ca.initial_balance, 0) + COALESCE(ca.manual_adjustment, 0)

    WHERE ca.id NOT IN (

        SELECT DISTINCT vendor_id FROM public.shipment_cost_items

        WHERE vendor_type = 'clearing_agent' AND vendor_id IS NOT NULL

    );



    -- Upsert ledger_entries for shipment_cost_items

    DELETE FROM public.ledger_entries le

    WHERE le.reference_type = 'shipment_cost_item'

      AND le.reference_id IS NOT NULL

      AND NOT EXISTS (

          SELECT 1 FROM public.shipment_cost_items sci

          WHERE sci.id = le.reference_id::bigint

      );

    GET DIAGNOSTICS v_le_deleted = ROW_COUNT;



    FOR r IN

        SELECT sci.id AS item_id,

               sci.vendor_type,

               sci.vendor_id,

               sci.supplier_id,

               sci.total_price,

               sci.exchange_rate,

               sci.original_currency,

               sci.description

        FROM public.shipment_cost_items sci

        WHERE sci.total_price > 0

    LOOP

        DECLARE

            v_entity_type TEXT;

            v_entity_id   TEXT;

            v_ledger_amount NUMERIC;

            v_ledger_currency TEXT;

            v_exists BIGINT;

        BEGIN

            IF r.vendor_type = 'shipping_company' AND r.vendor_id IS NOT NULL THEN

                v_entity_type := 'shipping_company';

                v_entity_id := r.vendor_id::text;

            ELSIF r.vendor_type = 'clearing_agent' AND r.vendor_id IS NOT NULL THEN

                v_entity_type := 'clearing_agent';

                v_entity_id := r.vendor_id::text;

            ELSIF r.supplier_id IS NOT NULL AND r.supplier_id != '' THEN

                v_entity_type := 'supplier';

                v_entity_id := r.supplier_id;

            ELSE

                CONTINUE;

            END IF;



            v_ledger_currency := COALESCE(NULLIF(r.original_currency, ''), 'EGP');

            IF v_ledger_currency != 'EGP' AND r.exchange_rate > 0 THEN

                v_ledger_amount := r.total_price / r.exchange_rate;

            ELSE

                v_ledger_amount := r.total_price;

            END IF;



            SELECT COUNT(*) INTO v_exists FROM public.ledger_entries

            WHERE reference_type = 'shipment_cost_item' AND reference_id = r.item_id;



            IF v_exists > 0 THEN

                UPDATE public.ledger_entries

                SET entity_type = v_entity_type,

                    entity_id = v_entity_id,

                    amount = v_ledger_amount,

                    currency = v_ledger_currency,

                    description = 'بند تكلفة شحنة: ' || COALESCE(r.description, '')

                WHERE reference_type = 'shipment_cost_item' AND reference_id = r.item_id;

            ELSE

                INSERT INTO public.ledger_entries (

                    entity_type, entity_id, entry_type, amount, currency,

                    reference_type, reference_id, description, created_by

                ) VALUES (

                    v_entity_type, v_entity_id, 'credit', v_ledger_amount, v_ledger_currency,

                    'shipment_cost_item', r.item_id,

                    'بند تكلفة شحنة: ' || COALESCE(r.description, ''),

                    auth.uid()

                );

            END IF;

            v_le_upserted := v_le_upserted + 1;

        END;

    END LOOP;



    RETURN jsonb_build_object(

        'success', true,

        'shipping_updated', v_shipping_updated,

        'ca_updated', v_ca_updated,

        'ledger_upserted', v_le_upserted,

        'ledger_deleted', v_le_deleted

    );

END;

$$;



-- ── Retroactive Data Healing: Re-map produce lot inventory debit lines to 12412 ──

DO $$

DECLARE

  v_raw_inv_id BIGINT;

BEGIN

  SELECT id INTO v_raw_inv_id FROM accounts WHERE account_code = '12412' AND deleted_at IS NULL LIMIT 1;

  IF v_raw_inv_id IS NOT NULL THEN

    UPDATE account_ledger_entries ale

    SET account_id = v_raw_inv_id

    FROM journal_entries je, accounts a

    WHERE ale.journal_entry_id = je.id

      AND ale.account_id = a.id

      AND je.source_type IN ('lot_receipt', 'lot_price_adjustment')

      AND ale.debit > 0

      AND a.account_code IN ('1231', '12311', '1234', '1030');

  END IF;

END $$;



-- ══════════════════════════════════════════════════════════════════════════════

-- Multi-Crop Packing Order Lines & Sold Cartons Synchronization

-- ══════════════════════════════════════════════════════════════════════════════



DROP FUNCTION IF EXISTS public.rpc_save_packing_order_lines(bigint, jsonb);



CREATE OR REPLACE FUNCTION public.rpc_save_packing_order_lines(

  p_packing_order_id bigint,

  p_lines jsonb

)

RETURNS jsonb

LANGUAGE plpgsql

SECURITY DEFINER

SET search_path TO 'public'

AS $$

DECLARE

  v_line jsonb;

  v_count int := 0;

  v_line_id bigint;

  v_existing_ids bigint[];

BEGIN

  IF p_packing_order_id IS NULL THEN

    RETURN jsonb_build_object('success', false, 'error', 'packing_order_id is required');

  END IF;



  SELECT COALESCE(array_agg((elem->>'id')::bigint), ARRAY[]::bigint[])

  INTO v_existing_ids

  FROM jsonb_array_elements(COALESCE(p_lines, '[]'::jsonb)) elem

  WHERE elem ? 'id' AND elem->>'id' IS NOT NULL AND elem->>'id' != '';



  DELETE FROM public.packing_order_lines

  WHERE packing_order_id = p_packing_order_id

    AND id NOT IN (SELECT unnest(v_existing_ids))

    AND id NOT IN (SELECT packing_order_line_id FROM public.export_shipment_items WHERE packing_order_line_id IS NOT NULL);



  IF p_lines IS NOT NULL AND jsonb_array_length(p_lines) > 0 THEN

    FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines)

    LOOP

      v_line_id := NULLIF(v_line->>'id', '')::bigint;



      IF v_line_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.packing_order_lines WHERE id = v_line_id AND packing_order_id = p_packing_order_id) THEN

        UPDATE public.packing_order_lines

        SET

          product_id = (NULLIF(v_line->>'product_id', ''))::bigint,

          fruit_type_id = (NULLIF(v_line->>'fruit_type_id', ''))::int,

          product_name = COALESCE(v_line->>'product_name', product_name),

          grade = COALESCE(v_line->>'grade', grade, 'A'),

          source_lot_id = v_line->>'source_lot_id',

          batch_id = v_line->>'batch_id',

          quantity = COALESCE((NULLIF(v_line->>'quantity', ''))::numeric, 0),

          carton_count = COALESCE((NULLIF(v_line->>'carton_count', ''))::int, 0),

          net_weight_per_carton = COALESCE((NULLIF(v_line->>'net_weight_per_carton', ''))::numeric, 0),

          gross_weight_per_carton = COALESCE((NULLIF(v_line->>'gross_weight_per_carton', ''))::numeric, 0),

          total_net_weight = COALESCE((NULLIF(v_line->>'total_net_weight', ''))::numeric, 0),

          total_gross_weight = COALESCE((NULLIF(v_line->>'total_gross_weight', ''))::numeric, 0),

          unit_cost = COALESCE((NULLIF(v_line->>'unit_cost', ''))::numeric, 0),

          raw_material_cost = COALESCE((NULLIF(v_line->>'raw_material_cost', ''))::numeric, 0),

          expected_loss_percent = COALESCE((NULLIF(v_line->>'expected_loss_percent', ''))::numeric, 0),

          waste_weight_kg = COALESCE((NULLIF(v_line->>'waste_weight_kg', ''))::numeric, 0),

          waste_cost = COALESCE((NULLIF(v_line->>'waste_cost', ''))::numeric, 0),

          sorted_weight_kg = COALESCE((NULLIF(v_line->>'sorted_weight_kg', ''))::numeric, 0),

          sorting_cost = COALESCE((NULLIF(v_line->>'sorting_cost', ''))::numeric, 0),

          specific_packaging_cost = COALESCE((NULLIF(v_line->>'specific_packaging_cost', ''))::numeric, 0),

          allocated_shared_packaging = COALESCE((NULLIF(v_line->>'allocated_shared_packaging', ''))::numeric, 0),

          allocated_cost_items = COALESCE((NULLIF(v_line->>'allocated_cost_items', ''))::numeric, 0),

          final_cost = COALESCE((NULLIF(v_line->>'final_cost', ''))::numeric, 0),

          final_unit_cost = COALESCE((NULLIF(v_line->>'final_unit_cost', ''))::numeric, 0),

          notes = COALESCE(v_line->'notes', notes, '{}'::jsonb),

          updated_at = now()

        WHERE id = v_line_id;

      ELSE

        INSERT INTO public.packing_order_lines (

          packing_order_id,

          product_id,

          fruit_type_id,

          product_name,

          grade,

          source_lot_id,

          batch_id,

          quantity,

          carton_count,

          net_weight_per_carton,

          gross_weight_per_carton,

          total_net_weight,

          total_gross_weight,

          unit_cost,

          raw_material_cost,

          expected_loss_percent,

          waste_weight_kg,

          waste_cost,

          sorted_weight_kg,

          sorting_cost,

          specific_packaging_cost,

          allocated_shared_packaging,

          allocated_cost_items,

          final_cost,

          final_unit_cost,

          sold_cartons,

          notes,

          created_at,

          updated_at

        ) VALUES (

          p_packing_order_id,

          (NULLIF(v_line->>'product_id', ''))::bigint,

          (NULLIF(v_line->>'fruit_type_id', ''))::int,

          COALESCE(v_line->>'product_name', ''),

          COALESCE(v_line->>'grade', 'A'),

          v_line->>'source_lot_id',

          v_line->>'batch_id',

          COALESCE((NULLIF(v_line->>'quantity', ''))::numeric, 0),

          COALESCE((NULLIF(v_line->>'carton_count', ''))::int, 0),

          COALESCE((NULLIF(v_line->>'net_weight_per_carton', ''))::numeric, 0),

          COALESCE((NULLIF(v_line->>'gross_weight_per_carton', ''))::numeric, 0),

          COALESCE((NULLIF(v_line->>'total_net_weight', ''))::numeric, 0),

          COALESCE((NULLIF(v_line->>'total_gross_weight', ''))::numeric, 0),

          COALESCE((NULLIF(v_line->>'unit_cost', ''))::numeric, 0),

          COALESCE((NULLIF(v_line->>'raw_material_cost', ''))::numeric, 0),

          COALESCE((NULLIF(v_line->>'expected_loss_percent', ''))::numeric, 0),

          COALESCE((NULLIF(v_line->>'waste_weight_kg', ''))::numeric, 0),

          COALESCE((NULLIF(v_line->>'waste_cost', ''))::numeric, 0),

          COALESCE((NULLIF(v_line->>'sorted_weight_kg', ''))::numeric, 0),

          COALESCE((NULLIF(v_line->>'sorting_cost', ''))::numeric, 0),

          COALESCE((NULLIF(v_line->>'specific_packaging_cost', ''))::numeric, 0),

          COALESCE((NULLIF(v_line->>'allocated_shared_packaging', ''))::numeric, 0),

          COALESCE((NULLIF(v_line->>'allocated_cost_items', ''))::numeric, 0),

          COALESCE((NULLIF(v_line->>'final_cost', ''))::numeric, 0),

          COALESCE((NULLIF(v_line->>'final_unit_cost', ''))::numeric, 0),

          COALESCE((NULLIF(v_line->>'sold_cartons', ''))::int, 0),

          COALESCE(v_line->'notes', '{}'::jsonb),

          now(),

          now()

        );

      END IF;

      v_count := v_count + 1;

    END LOOP;

  END IF;



  RETURN jsonb_build_object('success', true, 'count', v_count);

END;

$$;



GRANT EXECUTE ON FUNCTION public.rpc_save_packing_order_lines(bigint, jsonb) TO authenticated, service_role, anon;



CREATE OR REPLACE FUNCTION public.increment_sold_cartons(

  p_packing_order_id integer,

  p_additional integer,

  p_line_id bigint DEFAULT NULL

) RETURNS void

LANGUAGE plpgsql SECURITY DEFINER

SET search_path TO 'public'

AS $$

BEGIN

  UPDATE public.packing_orders

  SET sold_cartons = LEAST(sold_cartons + p_additional, carton_count)

  WHERE id = p_packing_order_id;



  IF p_line_id IS NOT NULL THEN

    UPDATE public.packing_order_lines

    SET sold_cartons = LEAST(sold_cartons + p_additional, carton_count)

    WHERE id = p_line_id;

  END IF;

END;

$$;



GRANT EXECUTE ON FUNCTION public.increment_sold_cartons(integer, integer, bigint) TO authenticated, service_role, anon;



CREATE OR REPLACE FUNCTION public.decrement_sold_cartons(

  p_packing_order_id integer,

  p_amount integer,

  p_line_id bigint DEFAULT NULL

) RETURNS void

LANGUAGE plpgsql SECURITY DEFINER

SET search_path TO 'public'

AS $$

BEGIN

  UPDATE public.packing_orders

  SET sold_cartons = GREATEST(sold_cartons - p_amount, 0)

  WHERE id = p_packing_order_id;



  IF p_line_id IS NOT NULL THEN

    UPDATE public.packing_order_lines

    SET sold_cartons = GREATEST(sold_cartons - p_amount, 0)

    WHERE id = p_line_id;

  END IF;

END;

$$;



GRANT EXECUTE ON FUNCTION public.decrement_sold_cartons(integer, integer, bigint) TO authenticated, service_role, anon;



CREATE OR REPLACE FUNCTION public.trg_sync_shipment_items_sold_cartons()

RETURNS TRIGGER

LANGUAGE plpgsql

SECURITY DEFINER

AS $$

DECLARE

  v_po_id bigint;

  v_line_id bigint;

BEGIN

  v_po_id := COALESCE(NEW.packing_order_id, OLD.packing_order_id);

  v_line_id := COALESCE(NEW.packing_order_line_id, OLD.packing_order_line_id);



  IF v_po_id IS NOT NULL THEN

    UPDATE public.packing_orders

    SET sold_cartons = COALESCE((

      SELECT SUM(quantity) FROM public.export_shipment_items WHERE packing_order_id = v_po_id

    ), 0)

    WHERE id = v_po_id;

  END IF;



  IF v_line_id IS NOT NULL THEN

    UPDATE public.packing_order_lines

    SET sold_cartons = COALESCE((

      SELECT SUM(quantity) FROM public.export_shipment_items WHERE packing_order_line_id = v_line_id

    ), 0)

    WHERE id = v_line_id;

  END IF;



  RETURN COALESCE(NEW, OLD);

END;

$$;



DROP TRIGGER IF EXISTS trg_export_shipment_items_sold_cartons ON public.export_shipment_items;

CREATE TRIGGER trg_export_shipment_items_sold_cartons

AFTER INSERT OR UPDATE OR DELETE ON public.export_shipment_items

FOR EACH ROW EXECUTE FUNCTION public.trg_sync_shipment_items_sold_cartons();



COMMIT;

