-- Migration 230: Fix Journal Entry view to show original amount for foreign currency transactions
-- Problem: For purchases in foreign currency, the ledger sometimes stores the EGP-converted
-- amount in both debit/credit AND amount_in_base_currency. The journal entry page should
-- show the ORIGINAL foreign currency amount (e.g. 3000 USD not 150000 EGP).
--
-- Approach: For non-EGP entries where debit/credit looks like an EGP value (matches or is 
-- close to amount_in_base_currency), divide by exchange rate from the purchase invoice.

-- Helper: get exchange rate for a journal entry source
CREATE OR REPLACE FUNCTION public.fn_get_je_exchange_rate(p_source_type TEXT, p_source_id TEXT) RETURNS NUMERIC AS $$
DECLARE
    v_rate NUMERIC;
BEGIN
    IF p_source_type IN ('purchase', 'purchase_inventory', 'purchase_payment') AND p_source_id IS NOT NULL THEN
        -- Try currency_snapshot first
        SELECT COALESCE(NULLIF((currency_snapshot->>'exchange_rate')::NUMERIC, 0), NULL) INTO v_rate
        FROM purchase_invoices WHERE id::TEXT = p_source_id;
        
        -- Fallback to purchase_invoice_items.exchange_rate
        IF v_rate IS NULL THEN
            SELECT COALESCE(NULLIF(exchange_rate, 0), NULL) INTO v_rate
            FROM purchase_invoice_items WHERE invoice_id::TEXT = p_source_id LIMIT 1;
        END IF;
    END IF;
    
    RETURN COALESCE(v_rate, 1);
END;
$$ LANGUAGE plpgsql STABLE;

-- Recreate the view with smart amount logic
DROP VIEW IF EXISTS public.v_journal_entry_lines;
CREATE OR REPLACE VIEW public.v_journal_entry_lines AS
SELECT
    ale.id,
    ale.journal_entry_id,
    je.id AS entry_id,
    je.entry_number,
    je.entry_date AS transaction_date,
    ale.account_id,
    COALESCE(a.account_code, '') AS account_code,
    COALESCE(a.account_name, a.name, '') AS account_name,
    CASE WHEN ale.debit > 0 THEN 'debit' ELSE 'credit' END AS type,
    -- Smart amount: if currency is NOT EGP and exchange rate > 1, divide to get original amount
    (CASE 
        WHEN COALESCE(ale.currency, 'EGP') != 'EGP' 
             AND public.fn_get_je_exchange_rate(je.source_type, je.source_id) > 1
        THEN
            ROUND(
                (CASE WHEN ale.debit > 0 THEN ale.debit ELSE ale.credit END)::NUMERIC
                / public.fn_get_je_exchange_rate(je.source_type, je.source_id),
                2
            )
        ELSE
            (CASE WHEN ale.debit > 0 THEN ale.debit ELSE ale.credit END)
    END) AS amount,
    ale.description,
    je.created_by,
    je.created_at,
    je.company_id,
    ale.debit,
    ale.credit,
    ale.currency,
    ale.amount_in_base_currency,
    je.source_type,
    je.source_id,
    je.status
FROM account_ledger_entries ale
JOIN journal_entries je ON je.id = ale.journal_entry_id
LEFT JOIN accounts a ON a.id = ale.account_id
WHERE je.deleted_at IS NULL
  AND ale.deleted_at IS NULL;

GRANT SELECT ON public.v_journal_entry_lines TO authenticated, service_role, anon;
