-- Ensure purchase_invoice_items has station_id column
-- The warehouse tracking page filters purchases by this column.
-- Without it, purchases never appear in the warehouse tracking page.

ALTER TABLE purchase_invoice_items
  ADD COLUMN IF NOT EXISTS station_id BIGINT;

-- Also ensure raw_material_id column exists (used by rpc_confirm_purchase)
ALTER TABLE purchase_invoice_items
  ADD COLUMN IF NOT EXISTS raw_material_id INTEGER;

-- Also ensure exchange_rate column exists
ALTER TABLE purchase_invoice_items
  ADD COLUMN IF NOT EXISTS exchange_rate NUMERIC(15,6) DEFAULT 1.0;

NOTIFY pgrst, 'reload schema';
