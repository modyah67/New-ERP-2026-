-- Migration: 20261102000001_sync_sorting_on_crop_disbursement.sql
-- Description:
-- 1. Ensure columns export_shipment_no, customer_name, and customer_id exist on public.packing_order_sortings.
-- 2. Add indices for fast lookup by export_shipment_no and customer_name.
-- 3. Notify PostgREST schema reload.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'packing_order_sortings' AND column_name = 'export_shipment_no'
  ) THEN
    ALTER TABLE public.packing_order_sortings ADD COLUMN export_shipment_no text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'packing_order_sortings' AND column_name = 'customer_name'
  ) THEN
    ALTER TABLE public.packing_order_sortings ADD COLUMN customer_name text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'packing_order_sortings' AND column_name = 'customer_id'
  ) THEN
    ALTER TABLE public.packing_order_sortings ADD COLUMN customer_id integer;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_packing_order_sortings_export_shipment_no
  ON public.packing_order_sortings(export_shipment_no);

CREATE INDEX IF NOT EXISTS idx_packing_order_sortings_customer_name
  ON public.packing_order_sortings(customer_name);

CREATE INDEX IF NOT EXISTS idx_packing_order_sortings_station_id
  ON public.packing_order_sortings(station_id);

NOTIFY pgrst, 'reload_schema';

