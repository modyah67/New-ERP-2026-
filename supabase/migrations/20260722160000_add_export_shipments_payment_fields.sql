-- Add payment tracking columns to export_shipments.
-- Export shipments receive payments from customers (DEPOSIT to treasury/bank).

ALTER TABLE public.export_shipments
ADD COLUMN IF NOT EXISTS paid_amount double precision DEFAULT 0,
ADD COLUMN IF NOT EXISTS payment_source_type text DEFAULT 'treasury',
ADD COLUMN IF NOT EXISTS payment_treasury_id text,
ADD COLUMN IF NOT EXISTS payment_bank_account_id integer;

COMMENT ON COLUMN public.export_shipments.paid_amount IS 'Amount received from customer for this shipment';
COMMENT ON COLUMN public.export_shipments.payment_source_type IS 'treasury or bank';
COMMENT ON COLUMN public.export_shipments.payment_treasury_id IS 'FK to treasuries.id when source is treasury';
COMMENT ON COLUMN public.export_shipments.payment_bank_account_id IS 'FK to bank_accounts.id when source is bank';
