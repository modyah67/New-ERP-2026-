-- Migration 160: Retroactively fix amounts and currencies in old purchase journal entries

DO $$
DECLARE
    v_je RECORD;
    v_pi RECORD;
    v_exchange_rate NUMERIC;
    v_foreign NUMERIC;
    v_egp NUMERIC;
    v_currency TEXT;
BEGIN
    -- Fix purchase_payment journal entries
    FOR v_je IN
        SELECT id, source_id
        FROM journal_entries
        WHERE source_type = 'purchase_payment'
    LOOP
        SELECT * INTO v_pi FROM purchase_invoices WHERE id::TEXT = v_je.source_id LIMIT 1;
        IF FOUND THEN
            -- Get exchange rate from the first item
            SELECT COALESCE(NULLIF(exchange_rate, 0), 1.0) INTO v_exchange_rate FROM purchase_invoice_items WHERE invoice_id = v_pi.id LIMIT 1;
            IF v_exchange_rate IS NULL THEN v_exchange_rate := 1.0; END IF;
            
            v_currency := COALESCE(v_pi.currency, 'EGP');
            v_foreign := COALESCE(v_pi.paid_amount, 0);
            v_egp := v_foreign * v_exchange_rate;

            -- Update Debit leg (Supplier)
            UPDATE account_ledger_entries
            SET debit = v_foreign,
                amount_in_base_currency = v_egp,
                currency = v_currency
            WHERE journal_entry_id = v_je.id AND debit > 0;

            -- Update Credit leg (Bank/Cash)
            UPDATE account_ledger_entries
            SET credit = v_foreign,
                amount_in_base_currency = v_egp,
                currency = v_currency
            WHERE journal_entry_id = v_je.id AND credit > 0;
        END IF;
    END LOOP;

    -- Fix purchase_inventory journal entries (simplified fix to just set currency and update amounts)
    FOR v_je IN
        SELECT id, source_id
        FROM journal_entries
        WHERE source_type IN ('purchase_inventory', 'purchase')
    LOOP
        SELECT * INTO v_pi FROM purchase_invoices WHERE id::TEXT = v_je.source_id LIMIT 1;
        IF FOUND THEN
            -- Get exchange rate from the first item
            SELECT COALESCE(NULLIF(exchange_rate, 0), 1.0) INTO v_exchange_rate FROM purchase_invoice_items WHERE invoice_id = v_pi.id LIMIT 1;
            IF v_exchange_rate IS NULL THEN v_exchange_rate := 1.0; END IF;

            v_currency := COALESCE(v_pi.currency, 'EGP');
            
            -- Set currency on all legs
            UPDATE account_ledger_entries
            SET currency = v_currency
            WHERE journal_entry_id = v_je.id;

            -- If it was recorded with EGP in the debit/credit field, calculate the correct foreign amount
            -- We assume the current debit is the EGP amount (which was recorded incorrectly as foreign amount)
            UPDATE account_ledger_entries
            SET debit = amount_in_base_currency / NULLIF(v_exchange_rate, 0),
                credit = 0
            WHERE journal_entry_id = v_je.id AND debit > 0 AND amount_in_base_currency > 0;

            UPDATE account_ledger_entries
            SET credit = amount_in_base_currency / NULLIF(v_exchange_rate, 0),
                debit = 0
            WHERE journal_entry_id = v_je.id AND credit > 0 AND amount_in_base_currency > 0;
            
            -- If amount_in_base_currency wasn't set, fallback to calculating it from debit
            UPDATE account_ledger_entries
            SET amount_in_base_currency = debit * v_exchange_rate
            WHERE journal_entry_id = v_je.id AND debit > 0 AND COALESCE(amount_in_base_currency, 0) = 0;

            UPDATE account_ledger_entries
            SET amount_in_base_currency = credit * v_exchange_rate
            WHERE journal_entry_id = v_je.id AND credit > 0 AND COALESCE(amount_in_base_currency, 0) = 0;
            
        END IF;
    END LOOP;
END $$;
