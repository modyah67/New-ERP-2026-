BEGIN;

CREATE INDEX IF NOT EXISTS idx_journal_entries_entry_date_id ON public.journal_entries(entry_date DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_journal_entries_entry_number ON public.journal_entries(entry_number DESC);
CREATE INDEX IF NOT EXISTS idx_account_ledger_entries_account_id ON public.account_ledger_entries(account_id);

COMMIT;