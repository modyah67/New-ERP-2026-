-- View that joins journal_entries + account_ledger_entries for the journal entry page
CREATE OR REPLACE VIEW public.v_journal_entry_lines AS
SELECT
    ale.id,
    je.entry_number,
    je.entry_date AS transaction_date,
    ale.account_id,
    CASE WHEN ale.debit > 0 THEN 'debit' ELSE 'credit' END AS type,
    CASE WHEN ale.debit > 0 THEN ale.debit ELSE ale.credit END AS amount,
    ale.description,
    je.created_by,
    je.created_at,
    je.company_id,
    ale.debit,
    ale.credit,
    je.source_type,
    je.status
FROM account_ledger_entries ale
JOIN journal_entries je ON je.id = ale.journal_entry_id
WHERE je.deleted_at IS NULL
  AND ale.deleted_at IS NULL;

GRANT SELECT ON public.v_journal_entry_lines TO authenticated, service_role, anon;
