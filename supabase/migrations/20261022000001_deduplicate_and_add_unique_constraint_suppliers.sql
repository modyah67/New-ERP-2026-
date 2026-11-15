-- ============================================================================
-- Migration: Deduplicate suppliers & Add Unique Indexes/Constraints
-- Problem: Network drops and repeated clicks (double-submit) cause duplicate
--          suppliers with identical codes (e.g., code '50000').
-- Solution:
--   1. Clean up existing duplicate suppliers (keep the oldest record per code).
--   2. Enforce UNIQUE indexes on suppliers(code) and suppliers(supplier_code)
--      for active records (WHERE deleted_at IS NULL).
--   3. Reload PostgREST schema cache.
-- ============================================================================

BEGIN;

-- 1. Deduplicate suppliers: Keep the earliest created record, delete later duplicates
DELETE FROM public.suppliers
WHERE id IN (
    SELECT id
    FROM (
        SELECT id,
               ROW_NUMBER() OVER (
                   PARTITION BY COALESCE(NULLIF(code, ''), NULLIF(supplier_code, ''))
                   ORDER BY created_at ASC
               ) AS rn
        FROM public.suppliers
        WHERE COALESCE(NULLIF(code, ''), NULLIF(supplier_code, '')) IS NOT NULL
          AND deleted_at IS NULL
    ) t
    WHERE t.rn > 1
);

-- 2. Deduplicate transport_suppliers if any duplicate codes exist
DELETE FROM public.transport_suppliers
WHERE id IN (
    SELECT id
    FROM (
        SELECT id,
               ROW_NUMBER() OVER (
                   PARTITION BY code
                   ORDER BY created_at ASC
               ) AS rn
        FROM public.transport_suppliers
        WHERE code IS NOT NULL
          AND deleted_at IS NULL
    ) t
    WHERE t.rn > 1
);

-- 3. Create Unique Indexes on suppliers (with partial filter on active records)
CREATE UNIQUE INDEX IF NOT EXISTS idx_suppliers_unique_code
    ON public.suppliers (code)
    WHERE deleted_at IS NULL AND code IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_suppliers_unique_supplier_code
    ON public.suppliers (supplier_code)
    WHERE deleted_at IS NULL AND supplier_code IS NOT NULL;

-- 4. Ensure transport_suppliers has unique index on active records
CREATE UNIQUE INDEX IF NOT EXISTS idx_transport_suppliers_unique_code
    ON public.transport_suppliers (code)
    WHERE deleted_at IS NULL AND code IS NOT NULL;

-- 5. Force PostgREST schema reload
NOTIFY pgrst, 'reload schema';

COMMIT;
