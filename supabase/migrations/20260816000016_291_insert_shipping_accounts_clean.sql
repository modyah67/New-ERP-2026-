-- Migration 291: Insert 2103, 2104, 210301, 210401 with ON CONFLICT DO UPDATE

BEGIN;

-- 1. Insert/Update 2103
INSERT INTO public.accounts (
  account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order, company_id, parent_id, level
) VALUES (
  '2103', 'Shipping Companies', 'شركات الشحن', 'liability', true, false, false, 2103, 
  'cc6c170b-7115-4a3f-8e26-96b682bbf4e5'::uuid, 58, 1
)
ON CONFLICT (account_code) DO UPDATE
SET name = EXCLUDED.name,
    account_name = EXCLUDED.account_name,
    account_type = EXCLUDED.account_type,
    is_active = true,
    is_leaf = false,
    allow_posting = false,
    sort_order = EXCLUDED.sort_order,
    company_id = EXCLUDED.company_id,
    parent_id = EXCLUDED.parent_id,
    level = EXCLUDED.level;

-- 2. Insert/Update 2104
INSERT INTO public.accounts (
  account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order, company_id, parent_id, level
) VALUES (
  '2104', 'Customs Clearance', 'التخليص الجمركي', 'liability', true, false, false, 2104, 
  'cc6c170b-7115-4a3f-8e26-96b682bbf4e5'::uuid, 58, 1
)
ON CONFLICT (account_code) DO UPDATE
SET name = EXCLUDED.name,
    account_name = EXCLUDED.account_name,
    account_type = EXCLUDED.account_type,
    is_active = true,
    is_leaf = false,
    allow_posting = false,
    sort_order = EXCLUDED.sort_order,
    company_id = EXCLUDED.company_id,
    parent_id = EXCLUDED.parent_id,
    level = EXCLUDED.level;

-- 3. Insert/Update 210301 (DHL)
INSERT INTO public.accounts (
  account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order, company_id, parent_id, level
) VALUES (
  '210301', 'Shipping - DHL', 'شركة شحن - DHL', 'liability', true, true, true, 210301, 
  'cc6c170b-7115-4a3f-8e26-96b682bbf4e5'::uuid, (SELECT id FROM accounts WHERE account_code = '2103' LIMIT 1), 2
)
ON CONFLICT (account_code) DO UPDATE
SET name = EXCLUDED.name,
    account_name = EXCLUDED.account_name,
    account_type = EXCLUDED.account_type,
    is_active = true,
    is_leaf = true,
    allow_posting = true,
    sort_order = EXCLUDED.sort_order,
    company_id = EXCLUDED.company_id,
    parent_id = (SELECT id FROM accounts WHERE account_code = '2103' LIMIT 1),
    level = EXCLUDED.level;

-- 4. Insert/Update 210401 (SEA)
INSERT INTO public.accounts (
  account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order, company_id, parent_id, level
) VALUES (
  '210401', 'Clearing - SEA', 'مخلص جمركي - SEA', 'liability', true, true, true, 210401, 
  'cc6c170b-7115-4a3f-8e26-96b682bbf4e5'::uuid, (SELECT id FROM accounts WHERE account_code = '2104' LIMIT 1), 2
)
ON CONFLICT (account_code) DO UPDATE
SET name = EXCLUDED.name,
    account_name = EXCLUDED.account_name,
    account_type = EXCLUDED.account_type,
    is_active = true,
    is_leaf = true,
    allow_posting = true,
    sort_order = EXCLUDED.sort_order,
    company_id = EXCLUDED.company_id,
    parent_id = (SELECT id FROM accounts WHERE account_code = '2104' LIMIT 1),
    level = EXCLUDED.level;

-- 5. Update shipping_companies and clearing_agents
UPDATE public.shipping_companies
SET account_id = (SELECT id FROM public.accounts WHERE account_code = '210301' LIMIT 1)
WHERE id = 1 OR code = '00001';

UPDATE public.clearing_agents
SET account_id = (SELECT id FROM public.accounts WHERE account_code = '210401' LIMIT 1)
WHERE id = 1 OR code = '00001';

NOTIFY pgrst, 'reload schema';

COMMIT;
