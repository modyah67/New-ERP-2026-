-- Migration 107: Fix Export Shipment Ledger & Deposit Document Types
-- 
-- Fixes:
-- 1. Adds missing document types: customer_treasury_deposit, customer_treasury_withdrawal, export_shipment
-- 2. Upgrades rpc_process_export_shipment_ledger to generate enterprise journal entries (for "Show Journal Entry" button)

INSERT INTO public.sys_document_types (code, name, prefix)
VALUES 
  ('export_shipment', 'شحنة تصدير', 'EXP'),
  ('customer_treasury_deposit', 'إيداع خزينة عميل', 'CTD'),
  ('customer_treasury_withdrawal', 'سحب خزينة عميل', 'CTW')
ON CONFLICT (code) DO UPDATE 
SET name = EXCLUDED.name, 
    prefix = EXCLUDED.prefix;

CREATE OR REPLACE FUNCTION public.rpc_process_export_shipment_ledger(
  p_shipment_id BIGINT,
  p_user_id UUID DEFAULT auth.uid()
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_shipment RECORD;
  v_total_revenue NUMERIC := 0;
  v_discount NUMERIC := 0;
  v_net_amount NUMERIC := 0;
  v_old_amount NUMERIC := 0;
  v_desc TEXT;
  v_company_id UUID;
  v_je_id BIGINT;
  v_ar_acct BIGINT;
  v_rev_acct BIGINT;
  v_disc_acct BIGINT;
  v_lines JSONB := '[]'::jsonb;
BEGIN
  SELECT * INTO v_shipment
  FROM export_shipments
  WHERE id = p_shipment_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Shipment not found');
  END IF;

  IF v_shipment.customer_id IS NULL THEN
    RETURN jsonb_build_object('success', true, 'message', 'No customer assigned');
  END IF;

  SELECT COALESCE(SUM(amount), 0)
  INTO v_total_revenue
  FROM export_shipment_items
  WHERE shipment_id = p_shipment_id;

  v_discount := COALESCE(v_shipment.discount_amount, 0);
  v_net_amount := GREATEST(v_total_revenue - v_discount, 0);

  SELECT
    COALESCE(SUM(CASE WHEN entry_type = 'debit' THEN amount ELSE -amount END), 0)
  INTO v_old_amount
  FROM ledger_entries
  WHERE entity_type = 'customer'
    AND entity_id = v_shipment.customer_id::TEXT
    AND reference_type = 'export_shipment'
    AND reference_text = p_shipment_id::TEXT;

  -- Update customer balance (legacy support)
  UPDATE customers
  SET balance = COALESCE(balance, 0) - v_old_amount + v_net_amount,
      updated_at = now()
  WHERE id = v_shipment.customer_id;

  -- Delete legacy ledger entries
  DELETE FROM ledger_entries
  WHERE entity_type = 'customer'
    AND entity_id = v_shipment.customer_id::TEXT
    AND reference_type = 'export_shipment'
    AND reference_text = p_shipment_id::TEXT;

  -- Reverse old enterprise journal entry if exists
  FOR v_je_id IN 
      SELECT id FROM journal_entries WHERE source_type = 'export_shipment' AND source_id = p_shipment_id::text
  LOOP
      PERFORM public.reverse_journal_entry(v_je_id, p_user_id, 'تحديث الشحنة');
  END LOOP;

  -- Delete reversed journal entries to keep it clean (optional, but good for idempotency)
  DELETE FROM account_ledger_entries WHERE journal_entry_id IN (SELECT id FROM journal_entries WHERE source_type = 'export_shipment' AND source_id = p_shipment_id::text);
  DELETE FROM journal_entries WHERE source_type = 'export_shipment' AND source_id = p_shipment_id::text;

  IF v_total_revenue > 0 THEN
    v_desc := 'شحنة تصدير رقم ' || v_shipment.shipment_no;
    
    -- Re-insert legacy ledger entry for backward compatibility
    INSERT INTO ledger_entries (
      entity_type, entity_id, entry_type, amount, currency,
      reference_type, reference_text, description, created_by
    ) VALUES (
      'customer', v_shipment.customer_id::TEXT, 'debit', v_total_revenue,
      COALESCE(v_shipment.currency_code, 'USD'),
      'export_shipment', p_shipment_id::TEXT, v_desc, p_user_id
    );

    IF v_discount > 0 THEN
      -- Legacy discount ledger entry
      INSERT INTO ledger_entries (
        entity_type, entity_id, entry_type, amount, currency,
        reference_type, reference_text, description, created_by
      ) VALUES (
        'customer', v_shipment.customer_id::TEXT, 'credit', v_discount,
        COALESCE(v_shipment.currency_code, 'USD'),
        'export_shipment', p_shipment_id::TEXT, v_desc || ' (خصم)', p_user_id
      );
    END IF;

    -- Enterprise Journal Entry
    -- Get Company ID from user or system default
    SELECT id INTO v_company_id FROM sys_companies LIMIT 1;
    
    -- Resolve GL Accounts
    v_ar_acct := public.resolve_gl_account('1020', v_company_id);
    SELECT id INTO v_rev_acct FROM accounts WHERE company_id = v_company_id AND account_type = 'revenue' ORDER BY account_code ASC LIMIT 1;
    IF v_rev_acct IS NULL THEN v_rev_acct := v_ar_acct; END IF; -- Fallback to prevent crash
    
    SELECT id INTO v_disc_acct FROM accounts WHERE company_id = v_company_id AND (account_code = '4105' OR account_name ILIKE '%خصم%') LIMIT 1;
    IF v_disc_acct IS NULL THEN v_disc_acct := v_rev_acct; END IF;

    -- Build lines (Dr. AR, Cr. Revenue)
    v_lines := jsonb_build_array(
        jsonb_build_object('account_id', v_ar_acct, 'debit', v_net_amount, 'credit', 0, 'currency', COALESCE(v_shipment.currency_code, 'USD'), 'description', v_desc),
        jsonb_build_object('account_id', v_rev_acct, 'debit', 0, 'credit', v_total_revenue, 'currency', COALESCE(v_shipment.currency_code, 'USD'), 'description', v_desc)
    );

    -- If discount, Dr. Discount
    IF v_discount > 0 THEN
        v_lines := v_lines || jsonb_build_array(
            jsonb_build_object('account_id', v_disc_acct, 'debit', v_discount, 'credit', 0, 'currency', COALESCE(v_shipment.currency_code, 'USD'), 'description', v_desc || ' (خصم)')
        );
    END IF;

    -- Post the journal entry
    BEGIN
        v_je_id := public.post_journal_entry(
            'export_shipment', v_desc, COALESCE(v_shipment.shipment_date, CURRENT_DATE), v_company_id, p_user_id, v_lines
        );
        
        -- Link the journal entry to the shipment by setting source_id
        UPDATE journal_entries SET source_id = p_shipment_id::text WHERE id = v_je_id;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Enterprise journal entry failed for export shipment %: %', p_shipment_id, SQLERRM;
    END;
  END IF;

  UPDATE export_shipments
  SET applied_discount_amount = v_discount
  WHERE id = p_shipment_id;

  RETURN jsonb_build_object(
    'success', true,
    'total_revenue', v_total_revenue,
    'discount', v_discount,
    'net_amount', v_net_amount,
    'journal_entry_id', v_je_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_process_export_shipment_ledger(BIGINT, UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
