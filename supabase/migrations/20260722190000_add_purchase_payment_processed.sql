-- ============================================================================
-- Migration: Add payment_processed flag to purchase_invoices
-- Date: 2026-07-22
-- Reason: Enable immediate payment processing on purchase save (like lot form),
--         while preventing double-processing on confirm.
-- ============================================================================

-- Add payment_processed column (boolean, default false)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'purchase_invoices' AND column_name = 'payment_processed'
  ) THEN
    ALTER TABLE public.purchase_invoices
      ADD COLUMN payment_processed boolean DEFAULT false;
  END IF;
END $$;

-- Mark all existing confirmed purchases as payment_processed = true
-- (their payments were already processed via rpc_confirm_purchase)
UPDATE public.purchase_invoices
SET payment_processed = true
WHERE status = 'confirmed' AND paid_amount > 0;
