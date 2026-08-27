-- Migration 294: Fix accrual logic for vendor-less cost items
-- Problem: Items without vendor/entity should credit "Accrued Liabilities" (2300, ID 143),
--          not fall back to a supplier account or return NULL.
-- Also: Administrative category items should debit 6140 (not 6130).

BEGIN;

-- ── 1. Rebuild fn_sync_cost_item_accrual with correct vendor-less handling ──
CREATE OR REPLACE FUNCTION public.fn_sync_cost_item_accrual(
  p_cost_item_id BIGINT
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r_item          RECORD;
  v_shipment      RECORD;
  v_company_id    UUID;
  v_vendor_acct   BIGINT;
  v_expense_acct  BIGINT;
  v_amount        NUMERIC;
  v_currency      TEXT;
  v_desc          TEXT;
  v_lines         JSONB;
  v_je_id         BIGINT;
  v_old_je_id     BIGINT;
  v_existing_dr   NUMERIC;
  v_existing_cr   NUMERIC;
  v_user_id       UUID;
  v_accrued_liab  BIGINT;  -- Accrued Expenses Liability account
BEGIN
  SELECT * INTO r_item FROM public.shipment_cost_items WHERE id = p_cost_item_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- If already paid through treasury or bank, accrual lifecycle is complete
  IF r_item.treasury_transaction_id IS NOT NULL OR r_item.bank_transaction_id IS NOT NULL THEN
    RETURN r_item.journal_entry_id;
  END IF;

  -- Fetch shipment details
  SELECT * INTO v_shipment FROM public.export_shipments WHERE id = r_item.shipment_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  SELECT id INTO v_company_id FROM public.sys_companies ORDER BY created_at ASC LIMIT 1;
  v_user_id := auth.uid();

  -- ═══════════════════════════════════════════════════════════════════
  -- 1. Resolve Vendor/Liability Account (Credit side)
  -- ═══════════════════════════════════════════════════════════════════
  -- Priority:
  --   a) shipping_company_id → shipping_companies.account_id
  --   b) clearing_agent_id  → clearing_agents.account_id
  --   c) supplier_id        → suppliers.account_id
  --   d) vendor_type + vendor_id fallback
  --   e) NO vendor at all   → Accrued Liabilities account (2300)
  -- ═══════════════════════════════════════════════════════════════════
  v_vendor_acct := NULL;

  IF r_item.shipping_company_id IS NOT NULL THEN
    SELECT sc.account_id INTO v_vendor_acct
    FROM public.shipping_companies sc WHERE sc.id = r_item.shipping_company_id;

  ELSIF r_item.clearing_agent_id IS NOT NULL THEN
    SELECT ca.account_id INTO v_vendor_acct
    FROM public.clearing_agents ca WHERE ca.id = r_item.clearing_agent_id;

  ELSIF r_item.supplier_id IS NOT NULL AND r_item.supplier_id != '' THEN
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
  -- NOTE: Removed the old "vendor_type = 'supplier'" fallback that would pick
  -- any supplier. If supplier_id is NULL and vendor_type is NULL, we use
  -- the Accrued Liabilities account below.

  -- If no specific entity found, use the general Accrued Liabilities account (2300)
  IF v_vendor_acct IS NULL THEN
    SELECT a.id INTO v_accrued_liab
    FROM public.accounts a
    WHERE a.account_code = '2300'
      AND a.is_leaf = true
      AND a.allow_posting = true
    LIMIT 1;

    IF v_accrued_liab IS NULL THEN
      -- Should never happen since 2300 exists, but safety fallback
      RETURN NULL;
    END IF;

    v_vendor_acct := v_accrued_liab;
  END IF;

  -- ═══════════════════════════════════════════════════════════════════
  -- 2. Resolve Expense Account (Debit side)
  -- ═══════════════════════════════════════════════════════════════════
  -- Priority:
  --   a) expense_account_id explicitly set on the item
  --   b) Category-based mapping:
  --      freight / shipping_company → 6130
  --      clearance / clearing_agent → 6130
  --      packing                    → 6120
  --      administrative             → 6140
  --      other (with no vendor)     → 6140 (administrative default for generic)
  --      other (with vendor)        → 6130 (operating expenses)
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
      -- Freight / Shipping → 6130
      SELECT a.id INTO v_expense_acct FROM public.accounts a
      WHERE a.account_code = '6130' AND a.is_leaf = true LIMIT 1;

    ELSIF r_item.category = 'clearance'
       OR r_item.report_category_id = 5
       OR r_item.clearing_agent_id IS NOT NULL
       OR r_item.vendor_type = 'clearing_agent' THEN
      -- Clearance → 6130
      SELECT a.id INTO v_expense_acct FROM public.accounts a
      WHERE a.account_code = '6130' AND a.is_leaf = true LIMIT 1;

    ELSIF r_item.category = 'packing'
       OR r_item.report_category_id = 2 THEN
      -- Packing → 6120
      SELECT a.id INTO v_expense_acct FROM public.accounts a
      WHERE a.account_code = '6120' AND a.is_leaf = true LIMIT 1;

    ELSIF r_item.category = 'administrative'
       OR r_item.report_category_id = 6 THEN
      -- Administrative → 6140
      SELECT a.id INTO v_expense_acct FROM public.accounts a
      WHERE a.account_code = '6140' AND a.is_leaf = true LIMIT 1;

    ELSE
      -- Generic "other" category:
      -- If linked to a vendor → operating expenses 6130
      -- If no vendor at all  → administrative expenses 6140
      IF r_item.shipping_company_id IS NOT NULL
         OR r_item.clearing_agent_id IS NOT NULL
         OR (r_item.supplier_id IS NOT NULL AND r_item.supplier_id != '')
         OR r_item.vendor_type IS NOT NULL THEN
        SELECT a.id INTO v_expense_acct FROM public.accounts a
        WHERE a.account_code = '6130' AND a.is_leaf = true LIMIT 1;
      ELSE
        SELECT a.id INTO v_expense_acct FROM public.accounts a
        WHERE a.account_code = '6140' AND a.is_leaf = true LIMIT 1;
      END IF;
    END IF;
  END IF;

  -- Final safety net
  IF v_expense_acct IS NULL THEN
    SELECT a.id INTO v_expense_acct FROM public.accounts a
    WHERE a.account_type = 'expense' AND a.is_leaf = true AND a.is_active = true LIMIT 1;
  END IF;

  -- ═══════════════════════════════════════════════════════════════════
  -- 3. Calculate amount and currency
  -- ═══════════════════════════════════════════════════════════════════
  v_amount   := COALESCE(NULLIF(r_item.total_price, 0), r_item.quantity * r_item.unit_price, 0);
  v_currency := COALESCE(NULLIF(r_item.original_currency, ''), NULLIF(r_item.supplier_currency, ''), 'EGP');

  IF v_amount <= 0 THEN
    RETURN NULL;
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
      -- Check if the existing JE already matches the correct amount AND correct accounts
      -- We check BOTH the debit account and credit account match
      IF EXISTS (
        SELECT 1 FROM public.account_ledger_entries
        WHERE journal_entry_id = v_old_je_id AND account_id = v_expense_acct AND debit = v_amount
      ) AND EXISTS (
        SELECT 1 FROM public.account_ledger_entries
        WHERE journal_entry_id = v_old_je_id AND account_id = v_vendor_acct AND credit = v_amount
      ) THEN
        -- Perfectly matching amount AND accounts, no re-posting needed!
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
      'currency', v_currency,
      'description', v_desc
    ),
    jsonb_build_object(
      'account_id', v_vendor_acct,
      'debit', 0,
      'credit', v_amount,
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
$$;


-- ── 2. Re-sync ALL existing unpaid cost items to pick up the corrected logic ──
-- This will fix any items that were previously assigned to wrong accounts.
-- Items that already have correct JEs will be detected by idempotency and skipped.
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

NOTIFY pgrst, 'reload schema';

COMMIT;
