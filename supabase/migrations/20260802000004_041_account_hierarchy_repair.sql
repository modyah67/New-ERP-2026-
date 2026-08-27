-- ============================================================================
-- 20260802000004_041_account_hierarchy_repair.sql
-- ============================================================================
-- This migration repairs the corrupted account hierarchy by:
-- 1. Deleting demo/test accounts
-- 2. Moving misplaced root accounts to correct parents
-- 3. Fixing account levels
-- 4. Updating hierarchy paths
-- ============================================================================

BEGIN;

-- ============================================================================
-- STEP 1: Delete demo/test accounts (no ledger entries)
-- ============================================================================

-- Delete demo customer accounts
DELETE FROM accounts WHERE id IN (44, 45, 46, 81, 83, 53, 22);

-- Delete demo revenue/expense accounts
DELETE FROM accounts WHERE id IN (133, 136);

-- ============================================================================
-- STEP 2: Move misplaced root accounts to correct parents
-- ============================================================================

-- Move supplier advances (2120) to Suppliers (2000)
UPDATE accounts 
SET parent_id = 14, 
    level = 5,
    updated_at = NOW()
WHERE id = 52;

-- Move treasury accounts to Cash (1000)
UPDATE accounts 
SET parent_id = 16, 
    level = 5,
    updated_at = NOW()
WHERE id IN (7, 15);

-- Move customer accounts to Accounts Receivable (1020)
UPDATE accounts 
SET parent_id = 5, 
    level = 4,
    updated_at = NOW()
WHERE id IN (80, 82, 23, 24, 25);

-- ============================================================================
-- STEP 3: Fix account levels for all accounts
-- ============================================================================

-- Reset root accounts to level 0
UPDATE accounts 
SET level = 0,
    updated_at = NOW()
WHERE parent_id IS NULL OR parent_id::TEXT = '';

-- Recalculate levels for all child accounts
WITH RECURSIVE account_hierarchy AS (
  -- Base case: root accounts
  SELECT 
    id, 
    parent_id, 
    0 as correct_level,
    ARRAY[id] as id_path,
    ARRAY[account_code::text] as code_path
  FROM accounts
  WHERE parent_id IS NULL OR parent_id::TEXT = ''
  
  UNION ALL
  
  -- Recursive case: children
  SELECT 
    a.id,
    a.parent_id,
    ah.correct_level + 1,
    ah.id_path || a.id,
    ah.code_path || a.account_code::text
  FROM accounts a
  INNER JOIN account_hierarchy ah ON a.parent_id = ah.id
)
UPDATE accounts a
SET level = ah.correct_level,
    path_ids = array_to_string(ah.id_path, ','),
    path_codes = array_to_string(ah.code_path, ','),
    updated_at = NOW()
FROM account_hierarchy ah
WHERE a.id = ah.id;

-- ============================================================================
-- STEP 4: Update is_leaf and is_system flags
-- ============================================================================

-- Update is_leaf based on whether account has children
UPDATE accounts a
SET is_leaf = NOT EXISTS (
  SELECT 1 FROM accounts c WHERE c.parent_id = a.id
),
updated_at = NOW();

-- ============================================================================
-- STEP 5: Verify the repairs
-- ============================================================================

-- Check for remaining root accounts (should only be main categories)
DO $$
DECLARE
  v_root_count INT;
  v_orphan_count INT;
  v_level_issues INT;
BEGIN
  SELECT COUNT(*) INTO v_root_count 
  FROM accounts 
  WHERE (parent_id IS NULL OR parent_id::TEXT = '');
  
  SELECT COUNT(*) INTO v_orphan_count
  FROM accounts a
  WHERE a.parent_id IS NOT NULL
    AND a.parent_id::TEXT != ''
    AND NOT EXISTS (SELECT 1 FROM accounts p WHERE p.id::TEXT = a.parent_id::TEXT);
  
  SELECT COUNT(*) INTO v_level_issues
  FROM accounts a
  WHERE a.parent_id IS NOT NULL
    AND a.level <= (SELECT level FROM accounts p WHERE p.id = a.parent_id);
  
  RAISE NOTICE 'Hierarchy Repair Summary:';
  RAISE NOTICE '  Root accounts: % (expected: 6)', v_root_count;
  RAISE NOTICE '  Orphan accounts: % (expected: 0)', v_orphan_count;
  RAISE NOTICE '  Level issues: % (expected: 0)', v_level_issues;
  
  IF v_orphan_count > 0 OR v_level_issues > 0 THEN
    RAISE WARNING 'Hierarchy repair may have issues - please review';
  ELSE
    RAISE NOTICE 'Hierarchy repair completed successfully';
  END IF;
END $$;

COMMIT;