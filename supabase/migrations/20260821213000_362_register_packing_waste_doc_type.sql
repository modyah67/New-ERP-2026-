-- ============================================================================
-- Migration: 362_register_packing_waste_doc_type
-- Description: Register 'packing_waste' in sys_document_types and initialize sequence
-- ============================================================================

BEGIN;

-- 1. Insert or update packing_waste document type
INSERT INTO public.sys_document_types (code, name, prefix, is_active)
VALUES ('packing_waste', 'إذن هالك تعبئة', 'PW', true)
ON CONFLICT (code) DO UPDATE
SET name = EXCLUDED.name,
    prefix = EXCLUDED.prefix,
    is_active = true;

-- 2. Initialize sequence for all active companies
INSERT INTO public.sys_sequences (company_id, document_type_code, current_value, padding_length)
SELECT c.id, 'packing_waste', 0, 5
FROM public.sys_companies c
WHERE NOT EXISTS (
  SELECT 1 FROM public.sys_sequences s
  WHERE s.company_id = c.id AND s.document_type_code = 'packing_waste'
);

COMMIT;
