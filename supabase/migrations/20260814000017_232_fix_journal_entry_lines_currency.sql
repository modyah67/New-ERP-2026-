-- Migration 232: Revert smart amount calculation in Journal Entry Lines
-- Problem: Migration 230 tried to fix legacy incorrect foreign amounts on-the-fly by dividing by exchange_rate.
-- But since Migration 164 already fixed the insertion logic for new transactions, the view ends up incorrectly dividing new, already-correct transactions.
-- Approach: Revert the view to just return `debit` or `credit` for the amount. The old legacy transactions will be fixed at the database level in Migration 233.

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
    (CASE WHEN ale.debit > 0 THEN ale.debit ELSE ale.credit END) AS amount,
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
