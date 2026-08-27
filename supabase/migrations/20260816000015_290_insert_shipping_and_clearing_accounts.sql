-- Migration 290: Insert standard shipping & clearing accounts and link them

BEGIN;

-- 1. Insert Parent 2103 & 2104
INSERT INTO public.accounts (account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order, company_id, parent_id, level)
SELECT '2103', 'Shipping Companies', 'شركات الشحن', 'liability', true, false, false, 2103, 
       (SELECT id FROM sys_companies ORDER BY created_at ASC LIMIT 1),
       (SELECT id FROM accounts WHERE account_code = '20' LIMIT 1), 1
WHERE NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = '2103');

INSERT INTO public.accounts (account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order, company_id, parent_id, level)
SELECT '2104', 'Customs Clearance', 'التخليص الجمركي', 'liability', true, false, false, 2104, 
       (SELECT id FROM sys_companies ORDER BY created_at ASC LIMIT 1),
       (SELECT id FROM accounts WHERE account_code = '20' LIMIT 1), 1
WHERE NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = '2104');

-- 2. Insert Leaf 210301 (DHL)
INSERT INTO public.accounts (account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order, company_id, parent_id, level)
SELECT '210301', 'Shipping - DHL', 'شركة شحن - DHL', 'liability', true, true, true, 210301, 
       (SELECT id FROM sys_companies ORDER BY created_at ASC LIMIT 1),
       (SELECT id FROM accounts WHERE account_code = '2103' LIMIT 1), 2
WHERE NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = '210301');

-- 3. Insert Leaf 210401 (SEA)
INSERT INTO public.accounts (account_code, name, account_name, account_type, is_active, is_leaf, allow_posting, sort_order, company_id, parent_id, level)
SELECT '210401', 'Clearing - SEA', 'مخلص جمركي - SEA', 'liability', true, true, true, 210401, 
       (SELECT id FROM sys_companies ORDER BY created_at ASC LIMIT 1),
       (SELECT id FROM accounts WHERE account_code = '2104' LIMIT 1), 2
WHERE NOT EXISTS (SELECT 1 FROM public.accounts WHERE account_code = '210401');

-- 4. Update shipping_companies.account_id
UPDATE public.shipping_companies
SET account_id = (SELECT id FROM public.accounts WHERE account_code = '210301' LIMIT 1)
WHERE id = 1 OR code = '00001';

-- 5. Update clearing_agents.account_id
UPDATE public.clearing_agents
SET account_id = (SELECT id FROM public.accounts WHERE account_code = '210401' LIMIT 1)
WHERE id = 1 OR code = '00001';

NOTIFY pgrst, 'reload schema';

COMMIT;
