-- Add payment tracking columns to lot_receipts.
-- Enables selecting a treasury/bank account to deduct from when recording paid amount.

ALTER TABLE public.lot_receipts
ADD COLUMN IF NOT EXISTS paid_amount double precision DEFAULT 0,
ADD COLUMN IF NOT EXISTS payment_source_type text DEFAULT 'treasury',
ADD COLUMN IF NOT EXISTS payment_treasury_id text,
ADD COLUMN IF NOT EXISTS payment_bank_account_id integer;

COMMENT ON COLUMN public.lot_receipts.paid_amount IS 'Amount paid to supplier at time of receipt (in supplier currency)';
COMMENT ON COLUMN public.lot_receipts.payment_source_type IS 'treasury or bank';
COMMENT ON COLUMN public.lot_receipts.payment_treasury_id IS 'FK to treasuries.id when source is treasury';
COMMENT ON COLUMN public.lot_receipts.payment_bank_account_id IS 'FK to bank_accounts.id when source is bank';
