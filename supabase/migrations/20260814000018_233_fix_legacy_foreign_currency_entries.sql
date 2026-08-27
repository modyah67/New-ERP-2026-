-- Migration 233: Fix legacy account_ledger_entries for foreign currency purchases
-- Problem: Before migration 164, the system multiplied the foreign currency total by the exchange rate
-- and stored the EGP amount in the `debit` (or `credit`) column of account_ledger_entries.
-- Approach: Find entries where currency != EGP and debit = amount_in_base_currency (indicating they were stored as EGP).
-- Divide the debit and credit by the invoice's exchange rate to restore the true foreign currency amount.

DO $$
DECLARE
    v_rec RECORD;
    v_exchange_rate NUMERIC;
    v_inv_num TEXT;
    v_is_purchase_inventory BOOLEAN;
BEGIN
    FOR v_rec IN 
        SELECT 
            je.id AS je_id, 
            je.source_id, 
            je.source_type, 
            je.description, 
            ale.id AS ale_id, 
            ale.debit, 
            ale.credit 
        FROM journal_entries je
        JOIN account_ledger_entries ale ON ale.journal_entry_id = je.id
        WHERE ale.currency != 'EGP' 
          AND ( 
                (ale.debit > 0 AND ale.debit = ale.amount_in_base_currency) 
                OR 
                (ale.credit > 0 AND ale.credit = ale.amount_in_base_currency) 
              )
          AND je.source_type IN ('purchase_inventory', 'purchase_payment')
    LOOP
        v_exchange_rate := NULL;
        
        -- Try to get exchange rate from source_id (if available)
        IF v_rec.source_id IS NOT NULL THEN
            SELECT COALESCE(NULLIF((currency_snapshot->>'exchange_rate')::NUMERIC, 0), NULL) 
            INTO v_exchange_rate
            FROM purchase_invoices 
            WHERE id::TEXT = v_rec.source_id;
            
            IF v_exchange_rate IS NULL THEN
                SELECT COALESCE(NULLIF(exchange_rate, 0), NULL) 
                INTO v_exchange_rate
                FROM purchase_invoice_items 
                WHERE invoice_id::TEXT = v_rec.source_id 
                LIMIT 1;
            END IF;
        ELSE
            -- Extract invoice number from description (e.g. "مشتريات رقم 000006 - مخزون")
            -- We look for exactly 6 digits
            v_inv_num := substring(v_rec.description from '[0-9]{6}');
            IF v_inv_num IS NOT NULL THEN
                SELECT COALESCE(NULLIF((currency_snapshot->>'exchange_rate')::NUMERIC, 0), NULL) 
                INTO v_exchange_rate
                FROM purchase_invoices 
                WHERE invoice_number = v_inv_num 
                LIMIT 1;
                
                IF v_exchange_rate IS NULL THEN
                    SELECT COALESCE(NULLIF(pii.exchange_rate, 0), NULL) 
                    INTO v_exchange_rate
                    FROM purchase_invoice_items pii
                    JOIN purchase_invoices p ON p.id = pii.invoice_id
                    WHERE p.invoice_number = v_inv_num 
                    LIMIT 1;
                END IF;
            END IF;
        END IF;

        -- If an exchange rate > 1 is found, fix the entry by dividing back to the original foreign currency
        IF v_exchange_rate IS NOT NULL AND v_exchange_rate > 1 THEN
            UPDATE account_ledger_entries
            SET debit = ROUND((debit / v_exchange_rate)::NUMERIC, 2),
                credit = ROUND((credit / v_exchange_rate)::NUMERIC, 2)
            WHERE id = v_rec.ale_id;
        END IF;
    END LOOP;
END;
$$;
