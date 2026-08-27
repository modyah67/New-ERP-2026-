-- =============================================================================
-- UNIFIED LEDGER TRANSACTIONS VIEW WITH EXACT DATABASE COLUMN MATCHING
-- =============================================================================

CREATE OR REPLACE VIEW public.v_unified_ledger_transactions AS
SELECT 
    tt.id AS tx_id,
    je.id AS journal_entry_id,
    je.entry_number AS entry_number,
    'treasury' AS account_category,
    tt.treasury_id AS account_source_id,
    t.name AS account_source_name,
    tt.type AS transaction_type,
    tt.currency AS currency,
    tt.amount AS amount,
    tt.balance_before AS balance_before,
    tt.balance_after AS balance_after,
    tt.description AS description,
    ec.name AS category_name,
    NULL::text AS reference_number,
    tt.created_by AS created_by,
    p.full_name AS creator_name,
    tt.created_at AS created_at
FROM treasury_transactions tt
JOIN journal_entries je ON tt.journal_entry_id = je.id
LEFT JOIN treasuries t ON tt.treasury_id = t.id
LEFT JOIN expense_categories ec ON tt.category_id = ec.id
LEFT JOIN profiles p ON tt.created_by = p.id

UNION ALL

SELECT 
    bt.id AS tx_id,
    je.id AS journal_entry_id,
    je.entry_number AS entry_number,
    'bank' AS account_category,
    bt.bank_account_id AS account_source_id,
    COALESCE(ba.name, 'حساب بنكي') AS account_source_name,
    bt.type AS transaction_type,
    'EGP' AS currency,
    bt.amount AS amount,
    bt.balance_before AS balance_before,
    bt.balance_after AS balance_after,
    bt.description AS description,
    NULL::text AS category_name,
    NULL::text AS reference_number,
    bt.created_by AS created_by,
    p.full_name AS creator_name,
    bt.created_at AS created_at
FROM bank_account_transactions bt
JOIN journal_entries je ON bt.journal_entry_id = je.id
LEFT JOIN bank_accounts ba ON bt.bank_account_id = ba.id
LEFT JOIN profiles p ON bt.created_by = p.id;
