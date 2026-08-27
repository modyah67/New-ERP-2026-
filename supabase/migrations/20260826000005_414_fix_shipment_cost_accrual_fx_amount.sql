-- Migration 414: Fix shipment cost accrual foreign currency calculation in fn_sync_cost_item_accrual

CREATE OR REPLACE FUNCTION public.fn_sync_cost_item_accrual(p_cost_item_id bigint)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r_item          RECORD;
  v_shipment      RECORD;
  v_vendor_acct   bigint;
  v_expense_acct  bigint;
  v_accrued_liab  bigint;
  v_currency      text;
  v_amount        numeric;
  v_amount_egp    numeric;
  v_exchange_rate numeric;
  v_je_id         bigint;
  v_old_je_id     bigint;
  v_desc          text;
  v_company_id    uuid;
  v_user_id       uuid := auth.uid();
  v_lines         jsonb;
BEGIN
  -- 1. Get Company ID
  SELECT a.company_id INTO v_company_id FROM accounts a WHERE a.account_code = '1030' LIMIT 1;
  IF v_company_id IS NULL THEN 
    SELECT id INTO v_company_id FROM sys_companies LIMIT 1; 
  END IF;

  -- Fetch the cost item
  SELECT * INTO r_item
  FROM public.shipment_cost_items
  WHERE id = p_cost_item_id;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- If this item was paid via treasury or bank, its GL entry is handled by payment flow
  IF r_item.treasury_transaction_id IS NOT NULL OR r_item.bank_transaction_id IS NOT NULL THEN
    RETURN NULL;
  END IF;

  -- Fetch shipment details
  SELECT id, shipment_no, shipment_date
  INTO v_shipment
  FROM public.export_shipments
  WHERE id = r_item.shipment_id;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- ═══════════════════════════════════════════════════════════════════
  -- 1. Resolve Vendor Account (Credit side)
  -- ═══════════════════════════════════════════════════════════════════
  v_vendor_acct := NULL;

  IF r_item.supplier_id IS NOT NULL AND r_item.supplier_id != '' THEN
    BEGIN
      SELECT s.account_id INTO v_vendor_acct
      FROM public.suppliers s WHERE s.id = r_item.supplier_id::uuid;
    EXCEPTION WHEN OTHERS THEN
      v_vendor_acct := NULL;
    END;

  ELSIF r_item.vendor_type = 'shipping_company' AND r_item.vendor_id IS NOT NULL THEN
    SELECT sc.account_id INTO v_vendor_acct
    FROM public.shipping_companies sc WHERE sc.id = r_item.vendor_id;

  ELSIF r_item.vendor_type = 'clearing_agent' AND r_item.vendor_id IS NOT NULL THEN
    SELECT ca.account_id INTO v_vendor_acct
    FROM public.clearing_agents ca WHERE ca.id = r_item.vendor_id;
  END IF;

  -- Fallback to Accrued Liabilities (2300) if no specific entity
  IF v_vendor_acct IS NULL THEN
    SELECT a.id INTO v_accrued_liab
    FROM public.accounts a
    WHERE a.account_code = '2300'
      AND a.is_leaf = true
      AND a.allow_posting = true
    LIMIT 1;

    IF v_accrued_liab IS NULL THEN
      RETURN NULL;
    END IF;

    v_vendor_acct := v_accrued_liab;
  END IF;

  -- ═══════════════════════════════════════════════════════════════════
  -- 2. Resolve Expense Account (Debit side)
  -- ═══════════════════════════════════════════════════════════════════
  v_expense_acct := NULL;

  IF r_item.expense_account_id IS NOT NULL THEN
    SELECT a.id INTO v_expense_acct FROM public.accounts a
    WHERE a.id = r_item.expense_account_id
      AND a.is_leaf = true AND a.is_active = true AND a.allow_posting = true;
  END IF;

  IF v_expense_acct IS NULL THEN
    IF r_item.category = 'freight'
       OR r_item.report_category_id = 4
       OR r_item.shipping_company_id IS NOT NULL
       OR r_item.vendor_type = 'shipping_company' THEN
      SELECT a.id INTO v_expense_acct FROM public.accounts a
      WHERE a.account_code = '6130' AND a.is_leaf = true LIMIT 1;

    ELSIF r_item.category = 'clearance'
       OR r_item.report_category_id = 5
       OR r_item.clearing_agent_id IS NOT NULL
       OR r_item.vendor_type = 'clearing_agent' THEN
      SELECT a.id INTO v_expense_acct FROM public.accounts a
      WHERE a.account_code = '6130' AND a.is_leaf = true LIMIT 1;

    ELSIF r_item.category = 'packing'
       OR r_item.report_category_id = 2 THEN
      SELECT a.id INTO v_expense_acct FROM public.accounts a
      WHERE a.account_code = '51101' AND a.is_leaf = true LIMIT 1;

    ELSE
      SELECT a.id INTO v_expense_acct FROM public.accounts a
      WHERE a.account_code = '6130' AND a.is_leaf = true LIMIT 1;
    END IF;
  END IF;

  -- Final safety net
  IF v_expense_acct IS NULL THEN
    SELECT a.id INTO v_expense_acct FROM public.accounts a
    WHERE a.account_type = 'expense' AND a.is_leaf = true AND a.is_active = true LIMIT 1;
  END IF;

  -- ═══════════════════════════════════════════════════════════════════
  -- 3. Calculate amount and currency
  -- total_price in DB is in base currency (EGP).
  -- If vendor is foreign currency, v_amount in foreign currency is total_price / exchange_rate.
  -- ═══════════════════════════════════════════════════════════════════
  v_currency      := COALESCE(NULLIF(r_item.original_currency, ''), NULLIF(r_item.supplier_currency, ''), 'EGP');
  v_exchange_rate := COALESCE(r_item.exchange_rate, 1.0);
  v_amount_egp    := COALESCE(NULLIF(r_item.total_price, 0), r_item.quantity * r_item.unit_price, 0);

  IF v_amount_egp <= 0 THEN
    RETURN NULL;
  END IF;

  IF v_currency != 'EGP' AND v_exchange_rate > 0 THEN
    v_amount := ROUND(v_amount_egp / v_exchange_rate, 2);
  ELSE
    v_amount := v_amount_egp;
  END IF;

  -- ═══════════════════════════════════════════════════════════════════
  -- 4. Idempotency: check existing accrual JE
  -- ═══════════════════════════════════════════════════════════════════
  v_old_je_id := r_item.journal_entry_id;
  IF v_old_je_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM public.journal_entries je
      WHERE je.id = v_old_je_id AND je.source_type = 'shipment_cost_accrual'
    ) THEN
      IF EXISTS (
        SELECT 1 FROM public.account_ledger_entries
        WHERE journal_entry_id = v_old_je_id AND account_id = v_expense_acct AND debit = v_amount AND currency = v_currency
      ) AND EXISTS (
        SELECT 1 FROM public.account_ledger_entries
        WHERE journal_entry_id = v_old_je_id AND account_id = v_vendor_acct AND credit = v_amount AND currency = v_currency
      ) THEN
        RETURN v_old_je_id;
      END IF;

      -- Amount or account changed: Cleanly remove old accrual lines before reposting
      DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_old_je_id;
      DELETE FROM public.journal_entries WHERE id = v_old_je_id;
    END IF;
  END IF;

  -- ═══════════════════════════════════════════════════════════════════
  -- 5. Build and post accrual JE
  -- ═══════════════════════════════════════════════════════════════════
  v_desc := 'استحقاق تكلفة شحنة ' || COALESCE(v_shipment.shipment_no, '') || ' - ' || COALESCE(r_item.description, 'تكلفة');

  v_lines := jsonb_build_array(
    jsonb_build_object(
      'account_id', v_expense_acct,
      'debit', v_amount,
      'credit', 0,
      'base_debit', v_amount_egp,
      'base_credit', 0,
      'currency', v_currency,
      'description', v_desc
    ),
    jsonb_build_object(
      'account_id', v_vendor_acct,
      'debit', 0,
      'credit', v_amount,
      'base_debit', 0,
      'base_credit', v_amount_egp,
      'currency', v_currency,
      'description', v_desc
    )
  );

  v_je_id := public.post_journal_entry(
    'shipment_cost_accrual',
    v_desc,
    COALESCE(v_shipment.shipment_date, CURRENT_DATE),
    v_company_id,
    v_user_id,
    v_lines,
    r_item.shipment_id::text
  );

  UPDATE public.shipment_cost_items
  SET journal_entry_id = v_je_id
  WHERE id = p_cost_item_id;

  RETURN v_je_id;
END;
$function$;

-- Re-sync all unpaid cost items now
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT id FROM public.shipment_cost_items
    WHERE treasury_transaction_id IS NULL
      AND bank_transaction_id IS NULL
    ORDER BY id ASC
  LOOP
    PERFORM public.fn_sync_cost_item_accrual(r.id);
  END LOOP;
END $$;
