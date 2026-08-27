-- Migration 292: Shipment Cost Accrual Journal Entries (Individual Per-Item Accruals)
-- 1. Register shipment_cost_accrual document type (Prefix: SCA)
-- 2. Create function to generate / sync individual cost accrual JEs
-- 3. Create trigger on shipment_cost_items for automatic accrual lifecycle
-- 4. Idempotently sync existing unpaid cost items

BEGIN;

-- ── 1. Document Type & Sequence for shipment_cost_accrual ──
INSERT INTO public.sys_document_types (code, name, prefix, is_active)
VALUES ('shipment_cost_accrual', 'استحقاق تكلفة شحنة', 'SCA', true)
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name,
    prefix = EXCLUDED.prefix,
    is_active = true;

INSERT INTO public.sys_sequences (company_id, document_type_code, current_value, padding_length)
SELECT c.id, 'shipment_cost_accrual', 0, 5
FROM public.sys_companies c
WHERE NOT EXISTS (
  SELECT 1 FROM public.sys_sequences s
  WHERE s.company_id = c.id AND s.document_type_code = 'shipment_cost_accrual'
);


-- ── 2. Core Function: Sync Accrual Journal Entry for a Single Cost Item ──
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

  -- 1. Resolve Vendor Liability Account (Credit side)
  v_vendor_acct := NULL;
  IF r_item.shipping_company_id IS NOT NULL THEN
    SELECT sc.account_id INTO v_vendor_acct FROM public.shipping_companies sc WHERE sc.id = r_item.shipping_company_id;
  ELSIF r_item.clearing_agent_id IS NOT NULL THEN
    SELECT ca.account_id INTO v_vendor_acct FROM public.clearing_agents ca WHERE ca.id = r_item.clearing_agent_id;
  ELSIF r_item.supplier_id IS NOT NULL AND r_item.supplier_id != '' THEN
    BEGIN
      SELECT s.account_id INTO v_vendor_acct FROM public.suppliers s WHERE s.id = r_item.supplier_id::uuid;
    EXCEPTION WHEN OTHERS THEN
      v_vendor_acct := NULL;
    END;
  ELSIF r_item.vendor_type = 'shipping_company' AND r_item.vendor_id IS NOT NULL THEN
    SELECT sc.account_id INTO v_vendor_acct FROM public.shipping_companies sc WHERE sc.id = r_item.vendor_id;
  ELSIF r_item.vendor_type = 'clearing_agent' AND r_item.vendor_id IS NOT NULL THEN
    SELECT ca.account_id INTO v_vendor_acct FROM public.clearing_agents ca WHERE ca.id = r_item.vendor_id;
  ELSIF r_item.vendor_type = 'supplier' AND r_item.vendor_id IS NOT NULL THEN
    SELECT s.account_id INTO v_vendor_acct FROM public.suppliers s WHERE s.id = r_item.vendor_id::text::uuid;
  END IF;

  -- If no entity account resolved, we cannot post entity accrual
  IF v_vendor_acct IS NULL THEN
    RETURN NULL;
  END IF;

  -- 2. Resolve Expense Account (Debit side)
  v_expense_acct := NULL;
  IF r_item.expense_account_id IS NOT NULL THEN
    SELECT a.id INTO v_expense_acct FROM public.accounts a
    WHERE a.id = r_item.expense_account_id AND a.is_leaf = true AND a.is_active = true AND a.allow_posting = true;
  END IF;

  IF v_expense_acct IS NULL THEN
    IF r_item.category = 'freight' OR r_item.report_category_id = 4 OR r_item.shipping_company_id IS NOT NULL OR r_item.vendor_type = 'shipping_company' THEN
      SELECT a.id INTO v_expense_acct FROM public.accounts a WHERE a.account_code = '6130' AND a.is_leaf = true LIMIT 1;
    ELSIF r_item.category = 'clearance' OR r_item.report_category_id = 5 OR r_item.clearing_agent_id IS NOT NULL OR r_item.vendor_type = 'clearing_agent' THEN
      SELECT a.id INTO v_expense_acct FROM public.accounts a WHERE a.account_code = '6130' AND a.is_leaf = true LIMIT 1;
    ELSIF r_item.category = 'packing' OR r_item.report_category_id = 2 THEN
      SELECT a.id INTO v_expense_acct FROM public.accounts a WHERE a.account_code = '6120' AND a.is_leaf = true LIMIT 1;
    ELSE
      SELECT a.id INTO v_expense_acct FROM public.accounts a WHERE a.account_code = '6130' AND a.is_leaf = true LIMIT 1;
    END IF;
  END IF;

  IF v_expense_acct IS NULL THEN
    SELECT a.id INTO v_expense_acct FROM public.accounts a WHERE a.account_type = 'expense' AND a.is_leaf = true AND a.is_active = true LIMIT 1;
  END IF;

  v_amount   := COALESCE(NULLIF(r_item.total_price, 0), r_item.quantity * r_item.unit_price, 0);
  v_currency := COALESCE(NULLIF(r_item.original_currency, ''), NULLIF(r_item.supplier_currency, ''), 'EGP');

  IF v_amount <= 0 THEN
    RETURN NULL;
  END IF;

  -- Check existing accrual JE idempotency
  v_old_je_id := r_item.journal_entry_id;
  IF v_old_je_id IS NOT NULL THEN
    -- Check if existing JE matches amount, currency, and accounts
    IF EXISTS (
      SELECT 1 FROM public.journal_entries je
      WHERE je.id = v_old_je_id AND je.source_type = 'shipment_cost_accrual'
    ) THEN
      SELECT COALESCE(SUM(debit), 0), COALESCE(SUM(credit), 0)
      INTO v_existing_dr, v_existing_cr
      FROM public.account_ledger_entries
      WHERE journal_entry_id = v_old_je_id AND account_id = v_expense_acct;

      IF v_existing_dr = v_amount THEN
        -- Perfectly matching, no re-posting needed!
        RETURN v_old_je_id;
      END IF;

      -- Amount or account changed: Cleanly remove old accrual lines before reposting
      DELETE FROM public.account_ledger_entries WHERE journal_entry_id = v_old_je_id;
      DELETE FROM public.journal_entries WHERE id = v_old_je_id;
    END IF;
  END IF;

  -- Build Accrual Lines
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


-- ── 3. Function: Sync All Accruals For a Shipment ──
CREATE OR REPLACE FUNCTION public.rpc_sync_shipment_cost_accruals(
  p_shipment_id BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r_item RECORD;
  v_count INT := 0;
BEGIN
  FOR r_item IN
    SELECT id FROM public.shipment_cost_items
    WHERE shipment_id = p_shipment_id
      AND treasury_transaction_id IS NULL
      AND bank_transaction_id IS NULL
    ORDER BY id ASC
  LOOP
    PERFORM public.fn_sync_cost_item_accrual(r_item.id);
    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'synced_count', v_count);
END;
$$;


-- ── 4. Trigger on shipment_cost_items for Automatic Accruals Lifecycle ──
CREATE OR REPLACE FUNCTION public.trg_shipment_cost_items_accrual_handler()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- If deleted before payment, remove the accrual JE cleanly
    IF OLD.journal_entry_id IS NOT NULL AND OLD.treasury_transaction_id IS NULL AND OLD.bank_transaction_id IS NULL THEN
      DELETE FROM public.account_ledger_entries WHERE journal_entry_id = OLD.journal_entry_id;
      DELETE FROM public.journal_entries WHERE id = OLD.journal_entry_id AND source_type = 'shipment_cost_accrual';
    END IF;
    RETURN OLD;
  END IF;

  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    -- If item is unpaid, sync accrual
    IF NEW.treasury_transaction_id IS NULL AND NEW.bank_transaction_id IS NULL THEN
      PERFORM public.fn_sync_cost_item_accrual(NEW.id);
    END IF;
    RETURN NEW;
  END IF;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_cost_items_accrual_sync ON public.shipment_cost_items;
CREATE TRIGGER trg_cost_items_accrual_sync
AFTER INSERT OR UPDATE OR DELETE ON public.shipment_cost_items
FOR EACH ROW
EXECUTE FUNCTION public.trg_shipment_cost_items_accrual_handler();


-- ── 5. Sync Existing Unpaid Cost Items Idempotently ──
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT id FROM public.shipment_cost_items WHERE treasury_transaction_id IS NULL AND bank_transaction_id IS NULL LOOP
    PERFORM public.fn_sync_cost_item_accrual(r.id);
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';

COMMIT;
