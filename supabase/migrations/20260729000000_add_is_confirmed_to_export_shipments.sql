ALTER TABLE export_shipments ADD COLUMN IF NOT EXISTS is_confirmed BOOLEAN DEFAULT FALSE;
UPDATE export_shipments SET is_confirmed = TRUE;
