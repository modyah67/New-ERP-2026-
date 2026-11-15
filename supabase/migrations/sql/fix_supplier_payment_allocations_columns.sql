-- ============================================================================
-- Migration: fix_supplier_payment_allocations_columns.sql
-- Description: Drop NOT NULL on allocated_amount and keep amount/allocated_amount
-- synchronized automatically.
-- ============================================================================

-- 1. Drop NOT NULL constraint on allocated_amount so inserts of 'amount' succeed
ALTER TABLE public.supplier_payment_allocations 
ALTER COLUMN allocated_amount DROP NOT NULL;

-- 2. Add any missing columns just in case
ALTER TABLE public.supplier_payment_allocations 
ADD COLUMN IF NOT EXISTS amount NUMERIC(15,2),
ADD COLUMN IF NOT EXISTS source_type TEXT,
ADD COLUMN IF NOT EXISTS source_id BIGINT,
ADD COLUMN IF NOT EXISTS purchase_invoice_id INTEGER,
ADD COLUMN IF NOT EXISTS lot_receipt_id BIGINT,
ADD COLUMN IF NOT EXISTS packing_order_cost_item_id BIGINT,
ADD COLUMN IF NOT EXISTS shipment_cost_item_id BIGINT,
ADD COLUMN IF NOT EXISTS supplier_id UUID,
ADD COLUMN IF NOT EXISTS allocation_type TEXT;

-- 3. Trigger to keep allocated_amount and amount identical automatically
CREATE OR REPLACE FUNCTION public.sync_supplier_allocation_amount()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.allocated_amount IS NULL AND NEW.amount IS NOT NULL THEN
        NEW.allocated_amount := NEW.amount;
    ELSIF NEW.amount IS NULL AND NEW.allocated_amount IS NOT NULL THEN
        NEW.amount := NEW.allocated_amount;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_supplier_allocation_amount ON public.supplier_payment_allocations;
CREATE TRIGGER trg_sync_supplier_allocation_amount
BEFORE INSERT OR UPDATE ON public.supplier_payment_allocations
FOR EACH ROW
EXECUTE FUNCTION public.sync_supplier_allocation_amount();
