-- Migration 005: Create Rebuild Chart Function
-- Purpose: Introduce the reusable hierarchy rebuilding function as a single source of truth.
-- Standards: No CREATE OR REPLACE in data migrations. Isolated responsibility.

BEGIN;

CREATE OR REPLACE FUNCTION public.rebuild_chart_of_accounts_hierarchy()
RETURNS void AS $$
BEGIN
    WITH RECURSIVE account_tree AS (
        -- Base case: Roots
        SELECT 
            id, 
            parent_id, 
            account_code, 
            1 AS calc_level, 
            id::text AS calc_path_ids, 
            account_code::text AS calc_path_codes,
            ARRAY[id] AS id_array
        FROM public.accounts
        WHERE parent_id IS NULL

        UNION ALL

        -- Recursive step: Children (protected against circular loops)
        SELECT 
            a.id, 
            a.parent_id, 
            a.account_code, 
            t.calc_level + 1, 
            t.calc_path_ids || '/' || a.id::text, 
            t.calc_path_codes || '/' || a.account_code::text,
            t.id_array || a.id
        FROM public.accounts a
        INNER JOIN account_tree t ON a.parent_id = t.id
        WHERE a.id <> ALL(t.id_array)
    )
    UPDATE public.accounts a
    SET 
        level = t.calc_level,
        path_ids = t.calc_path_ids,
        path_codes = t.calc_path_codes
    FROM account_tree t
    WHERE a.id = t.id;

    -- Single pass UPDATE for leaf detection and posting rules
    UPDATE public.accounts a
    SET 
        is_leaf = NOT EXISTS (SELECT 1 FROM public.accounts c WHERE c.parent_id = a.id),
        allow_posting = NOT EXISTS (SELECT 1 FROM public.accounts c WHERE c.parent_id = a.id);
END;
$$ LANGUAGE plpgsql;

COMMIT;
