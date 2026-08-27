-- Migration 314: Full Inventory Item Identity Scoping
-- Eliminates product_name/code collision between raw_materials and fruit_types
-- Establishes (item_type, raw_material_id) and (item_type, fruit_type_id) as true identities

BEGIN;

-- 1. Alter station_products
ALTER TABLE public.station_products
  ADD COLUMN IF NOT EXISTS item_type TEXT,
  ADD COLUMN IF NOT EXISTS raw_material_id UUID REFERENCES public.raw_materials(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS fruit_type_id BIGINT REFERENCES public.fruit_types(id) ON DELETE CASCADE;

-- Drop old name/code unique constraints
ALTER TABLE public.station_products
  DROP CONSTRAINT IF EXISTS station_products_station_id_product_name_key,
  DROP CONSTRAINT IF EXISTS station_products_station_id_code_name_key;

DROP INDEX IF EXISTS public.station_products_station_id_product_name_key;
DROP INDEX IF EXISTS public.station_products_station_id_code_name_key;
DROP INDEX IF EXISTS public.idx_station_products_material;
DROP INDEX IF EXISTS public.idx_station_products_fruit;

-- Add partial unique indexes ensuring absolute integrity per item type
CREATE UNIQUE INDEX idx_station_products_material 
  ON public.station_products (station_id, raw_material_id) 
  WHERE item_type = 'material' AND raw_material_id IS NOT NULL;

CREATE UNIQUE INDEX idx_station_products_fruit 
  ON public.station_products (station_id, fruit_type_id) 
  WHERE item_type = 'fruit' AND fruit_type_id IS NOT NULL;

-- 2. Alter station_product_batches
ALTER TABLE public.station_product_batches
  ADD COLUMN IF NOT EXISTS item_type TEXT,
  ADD COLUMN IF NOT EXISTS raw_material_id UUID REFERENCES public.raw_materials(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS fruit_type_id BIGINT REFERENCES public.fruit_types(id) ON DELETE CASCADE;

-- 3. Data Repair: Link existing batches to their exact entity IDs
-- 3a. Link purchase batches via purchase_invoice_items
UPDATE public.station_product_batches spb
SET item_type = 'material',
    raw_material_id = pii.raw_material_id
FROM public.purchase_invoice_items pii
WHERE spb.purchase_invoice_id = pii.invoice_id
  AND pii.raw_material_id IS NOT NULL
  AND spb.raw_material_id IS NULL;

-- 3b. Link batches matching raw_materials by code or name
UPDATE public.station_product_batches spb
SET item_type = 'material',
    raw_material_id = rm.id
FROM public.raw_materials rm
WHERE spb.raw_material_id IS NULL
  AND (spb.product_code = rm.code OR spb.product_name LIKE '%' || rm.name || '%');

-- 3c. Link lot receipt batches to fruit_types
UPDATE public.station_product_batches spb
SET item_type = 'fruit',
    fruit_type_id = lr.fruit_type_id
FROM public.lot_receipts lr
WHERE spb.source_type = 'lot_receipt'
  AND (spb.product_code = lr.lot_number OR spb.product_name = lr.product_name)
  AND spb.fruit_type_id IS NULL;

-- 3d. Link remaining fruit batches
UPDATE public.station_product_batches spb
SET item_type = 'fruit',
    fruit_type_id = ft.id
FROM public.fruit_types ft
WHERE spb.fruit_type_id IS NULL
  AND spb.raw_material_id IS NULL
  AND (spb.product_code = ft.code OR spb.product_name = ft.name);

-- Default any unlinked batch with raw_material_id to material
UPDATE public.station_product_batches
SET item_type = 'material'
WHERE raw_material_id IS NOT NULL AND item_type IS NULL;

-- Default any unlinked batch with fruit_type_id to fruit
UPDATE public.station_product_batches
SET item_type = 'fruit'
WHERE fruit_type_id IS NOT NULL AND item_type IS NULL;

-- 4. Rebuild station_products table cleanly without any merged rows
DELETE FROM public.station_products;

-- Insert material products
INSERT INTO public.station_products (station_id, item_type, raw_material_id, product_name, product_code, quantity, unit)
SELECT
  spb.station_id,
  'material',
  spb.raw_material_id,
  rm.name,
  COALESCE(rm.code, ''),
  COALESCE(SUM(spb.remaining_quantity), 0),
  COALESCE(rm.unit, 'piece')
FROM public.station_product_batches spb
JOIN public.raw_materials rm ON rm.id = spb.raw_material_id
WHERE spb.raw_material_id IS NOT NULL
GROUP BY spb.station_id, spb.raw_material_id, rm.name, rm.code, rm.unit
HAVING COALESCE(SUM(spb.remaining_quantity), 0) > 0;

-- Insert fruit products
INSERT INTO public.station_products (station_id, item_type, fruit_type_id, product_name, product_code, quantity, unit)
SELECT
  spb.station_id,
  'fruit',
  spb.fruit_type_id,
  ft.name,
  COALESCE(ft.code, ''),
  COALESCE(SUM(spb.remaining_quantity), 0),
  'kg'
FROM public.station_product_batches spb
JOIN public.fruit_types ft ON ft.id = spb.fruit_type_id
WHERE spb.fruit_type_id IS NOT NULL
GROUP BY spb.station_id, spb.fruit_type_id, ft.name, ft.code
HAVING COALESCE(SUM(spb.remaining_quantity), 0) > 0;

-- 5. Helper function to upsert station product safely by item identity
CREATE OR REPLACE FUNCTION public.upsert_station_product(
  p_station_id BIGINT,
  p_item_type TEXT,
  p_raw_material_id UUID,
  p_fruit_type_id BIGINT,
  p_product_name TEXT,
  p_product_code TEXT,
  p_delta NUMERIC,
  p_unit TEXT DEFAULT 'piece'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF p_item_type = 'material' AND p_raw_material_id IS NOT NULL THEN
    INSERT INTO public.station_products (
      station_id, item_type, raw_material_id, product_name, product_code, quantity, unit
    ) VALUES (
      p_station_id, 'material', p_raw_material_id, p_product_name, p_product_code, GREATEST(p_delta, 0), p_unit
    )
    ON CONFLICT (station_id, raw_material_id) WHERE item_type = 'material' AND raw_material_id IS NOT NULL
    DO UPDATE SET
      quantity = public.station_products.quantity + p_delta,
      product_name = EXCLUDED.product_name,
      product_code = EXCLUDED.product_code,
      updated_at = now();

    DELETE FROM public.station_products
    WHERE station_id = p_station_id AND raw_material_id = p_raw_material_id AND item_type = 'material' AND quantity <= 0;

  ELSIF p_item_type = 'fruit' AND p_fruit_type_id IS NOT NULL THEN
    INSERT INTO public.station_products (
      station_id, item_type, fruit_type_id, product_name, product_code, quantity, unit
    ) VALUES (
      p_station_id, 'fruit', p_fruit_type_id, p_product_name, p_product_code, GREATEST(p_delta, 0), p_unit
    )
    ON CONFLICT (station_id, fruit_type_id) WHERE item_type = 'fruit' AND fruit_type_id IS NOT NULL
    DO UPDATE SET
      quantity = public.station_products.quantity + p_delta,
      product_name = EXCLUDED.product_name,
      product_code = EXCLUDED.product_code,
      updated_at = now();

    DELETE FROM public.station_products
    WHERE station_id = p_station_id AND fruit_type_id = p_fruit_type_id AND item_type = 'fruit' AND quantity <= 0;
  END IF;
END;
$$;

COMMIT;
