-- ============================================================================
-- Migration 058: Production-Grade Account Deletion System
-- ============================================================================
-- Generic, metadata-driven, future-proof account deletion validation.
-- No hardcoded table names. Discovers all FK references dynamically.
-- ============================================================================

-- ============================================================================
-- 1. SOFT DELETE: Add deleted_at column to accounts
-- ============================================================================
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ DEFAULT NULL;
CREATE INDEX IF NOT EXISTS idx_accounts_deleted_at ON accounts(deleted_at) WHERE deleted_at IS NOT NULL;

-- ============================================================================
-- 2. GENERIC FK DISCOVERY: Find all references to accounts(id)
-- ============================================================================
-- Returns every table/column that references accounts, with row counts.
-- This is the single source of truth — no hardcoded table lists.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_discover_account_references(
    p_account_id BIGINT
) RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_result    JSONB := '[]'::jsonb;
    v_ref       RECORD;
    v_count     BIGINT;
    v_col_type  TEXT;
    v_sql       TEXT;
BEGIN
    -- Iterate over every FK constraint referencing accounts(id)
    FOR v_ref IN
        SELECT
            tc.table_name                       AS tbl,
            kcu.column_name                     AS col,
            tc.constraint_name                  AS con,
            rc.delete_rule                      AS on_delete,
            ccu.column_name                     AS referenced_col
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
            ON tc.constraint_name = kcu.constraint_name
            AND tc.table_schema = kcu.table_schema
        JOIN information_schema.constraint_column_usage ccu
            ON ccu.constraint_name = tc.constraint_name
            AND ccu.table_schema = tc.table_schema
        JOIN information_schema.referential_constraints rc
            ON rc.constraint_name = tc.constraint_name
            AND rc.constraint_schema = tc.constraint_schema
        WHERE tc.constraint_type = 'FOREIGN KEY'
            AND tc.table_schema = 'public'
            AND ccu.table_name = 'accounts'
            AND ccu.column_name = 'id'
        ORDER BY tc.table_name, kcu.column_name
    LOOP
        -- Skip self-references (accounts.parent_id)
        CONTINUE WHEN v_ref.tbl = 'accounts';

        -- Skip views
        CONTINUE WHEN v_ref.tbl LIKE 'v_%';

        -- Dynamically count rows referencing this account
        -- Handle both integer and bigint column types
        v_sql := format(
            'SELECT COUNT(*) FROM %I WHERE %I = $1',
            v_ref.tbl, v_ref.col
        );

        BEGIN
            EXECUTE v_sql INTO v_count USING p_account_id;
        EXCEPTION WHEN OTHERS THEN
            v_count := 0;
        END;

        IF v_count > 0 THEN
            v_result := v_result || jsonb_build_object(
                'table',        v_ref.tbl,
                'column',       v_ref.col,
                'constraint',   v_ref.con,
                'on_delete',    v_ref.on_delete,
                'row_count',    v_count
            );
        END IF;
    END LOOP;

    RETURN v_result;
END;
$$;

-- ============================================================================
-- 3. GENERIC DELETION VALIDATOR
-- ============================================================================
-- Uses fn_discover_account_references to dynamically check all FKs.
-- No hardcoded table names. Future tables are automatically protected.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_validate_account_deletion_v2(
    p_account_id BIGINT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_account       RECORD;
    v_references    JSONB;
    v_ref           JSONB;
    v_reasons       TEXT[] := '{}';
    v_ref_details   JSONB := '[]'::jsonb;
    v_has_children  BOOLEAN;
    v_total_refs    INTEGER := 0;
BEGIN
    -- 1. Check account exists
    SELECT id, account_code, account_name, is_system, is_leaf, is_locked,
           balance, parent_id, deleted_at
    INTO v_account
    FROM accounts WHERE id = p_account_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'action', 'none',
            'reason', 'الحساب غير موجود'
        );
    END IF;

    -- 2. Already deleted check
    IF v_account.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'action', 'restore',
            'reason', 'الحساب محذوف — يمكن استعادته'
        );
    END IF;

    -- 3. System account check
    IF v_account.is_system = true THEN
        v_reasons := array_append(v_reasons, 'حساب نظامي');
    END IF;

    -- 4. Has children check
    SELECT EXISTS(SELECT 1 FROM accounts WHERE parent_id = p_account_id AND deleted_at IS NULL)
    INTO v_has_children;
    IF v_has_children THEN
        v_reasons := array_append(v_reasons, 'يحتوي على حسابات فرعية');
    END IF;

    -- 5. Non-zero balance check
    IF v_account.balance != 0 THEN
        v_reasons := array_append(v_reasons, 'رصيد الحساب غير صفر (' || v_account.balance || ')');
    END IF;

    -- 6. Dynamic FK reference check (GENERIC — no hardcoded tables)
    v_references := public.fn_discover_account_references(p_account_id);

    IF jsonb_array_length(v_references) > 0 THEN
        -- Collect all reference details
        FOR v_ref IN SELECT * FROM jsonb_array_elements(v_references)
        LOOP
            v_ref_details := v_ref_details || jsonb_build_object(
                'table',     v_ref->>'table',
                'column',    v_ref->>'column',
                'row_count', (v_ref->>'row_count')::bigint
            );
            v_total_refs := v_total_refs + (v_ref->>'row_count')::integer;
        END LOOP;

        v_reasons := array_append(v_reasons,
            'مرتبط بـ ' || v_total_refs || ' سجل في ' || jsonb_array_length(v_references) || ' جدول'
        );
    END IF;

    -- 7. Determine action
    IF array_length(v_reasons, 1) > 0 THEN
        -- Has blocking reasons — cannot hard delete
        -- If only FK references (no system/children/balance), suggest archive
        IF v_account.is_system = false
           AND NOT v_has_children
           AND v_account.balance = 0
           AND v_total_refs > 0
        THEN
            RETURN jsonb_build_object(
                'allowed', false,
                'action', 'archive',
                'reason', array_to_string(v_reasons, ' — '),
                'references', v_ref_details,
                'total_references', v_total_refs
            );
        END IF;

        RETURN jsonb_build_object(
            'allowed', false,
            'action', 'none',
            'reason', array_to_string(v_reasons, ' — '),
            'references', v_ref_details,
            'total_references', v_total_refs
        );
    END IF;

    -- 8. All clear — hard delete allowed
    RETURN jsonb_build_object(
        'allowed', true,
        'action', 'delete',
        'reason', null,
        'references', '[]'::jsonb,
        'total_references', 0
    );
END;
$$;

-- ============================================================================
-- 4. ARCHIVE ACCOUNT (Soft Delete)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_archive_account(
    p_account_id BIGINT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_account   RECORD;
BEGIN
    SELECT id, account_code, deleted_at
    INTO v_account
    FROM accounts WHERE id = p_account_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'reason', 'الحساب غير موجود');
    END IF;

    IF v_account.deleted_at IS NOT NULL THEN
        RETURN jsonb_build_object('success', false, 'reason', 'الحساب محذوف بالفعل');
    END IF;

    -- Perform soft delete
    UPDATE accounts
    SET deleted_at = NOW(),
        is_active = false
    WHERE id = p_account_id;

    RETURN jsonb_build_object(
        'success', true,
        'action', 'archived',
        'message', 'تم أرشفة الحساب بنجاح — لا يمكن استخدامه في معاملات جديدة'
    );
END;
$$;

-- ============================================================================
-- 5. RESTORE ACCOUNT
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_restore_account(
    p_account_id BIGINT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_account RECORD;
BEGIN
    SELECT id, account_code, deleted_at, parent_id
    INTO v_account
    FROM accounts WHERE id = p_account_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'reason', 'الحساب غير موجود');
    END IF;

    IF v_account.deleted_at IS NULL THEN
        RETURN jsonb_build_object('success', false, 'reason', 'الحساب غير محذوف');
    END IF;

    -- Check if parent exists and is not deleted
    IF v_account.parent_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM accounts
            WHERE id = v_account.parent_id AND deleted_at IS NULL
        ) THEN
            RETURN jsonb_build_object(
                'success', false,
                'reason', 'لا يمكن الاستعادة — الحساب الأب محذوف. استعادته أولاً.'
            );
        END IF;
    END IF;

    -- Check if code would conflict with an active account
    IF EXISTS (
        SELECT 1 FROM accounts
        WHERE account_code = v_account.account_code
          AND id != p_account_id
          AND deleted_at IS NULL
    ) THEN
        RETURN jsonb_build_object(
            'success', false,
            'reason', 'كود الحساب مستخدم حالياً oleh حساب آخر نشط'
        );
    END IF;

    -- Restore
    UPDATE accounts
    SET deleted_at = NULL,
        is_active = true
    WHERE id = p_account_id;

    RETURN jsonb_build_object(
        'success', true,
        'action', 'restored',
        'message', 'تمت استعادة الحساب بنجاح'
    );
END;
$$;

-- ============================================================================
-- 6. PERMANENT DELETE (only for accounts with zero references)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_permanent_delete_account(
    p_account_id BIGINT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_account   RECORD;
    v_result    JSONB;
    v_has_children BOOLEAN;
BEGIN
    SELECT id, account_code, is_system, balance, deleted_at
    INTO v_account
    FROM accounts WHERE id = p_account_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'reason', 'الحساب غير موجود');
    END IF;

    -- System accounts can never be permanently deleted
    IF v_account.is_system = true THEN
        RETURN jsonb_build_object('success', false, 'reason', 'لا يمكن حذف حساب نظامي نهائياً');
    END IF;

    -- Has children check
    SELECT EXISTS(SELECT 1 FROM accounts WHERE parent_id = p_account_id) INTO v_has_children;
    IF v_has_children THEN
        RETURN jsonb_build_object('success', false, 'reason', 'يحتوي على حسابات فرعية');
    END IF;

    -- Non-zero balance check
    IF v_account.balance != 0 THEN
        RETURN jsonb_build_object('success', false, 'reason', 'رصيد الحساب غير صفر');
    END IF;

    -- FK reference check
    v_result := public.fn_discover_account_references(p_account_id);
    IF jsonb_array_length(v_result) > 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'reason', 'الحساب مرجع في جداول أخرى — لا يمكن حذفه نهائياً',
            'references', v_result
        );
    END IF;

    -- Safe to permanently delete
    DELETE FROM accounts WHERE id = p_account_id;

    RETURN jsonb_build_object(
        'success', true,
        'action', 'permanently_deleted',
        'message', 'تم حذف الحساب نهائياً'
    );
END;
$$;

-- ============================================================================
-- 7. UNIFIED ACCOUNT ACTION (delete / archive / restore / permanent_delete)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_account_action(
    p_action    TEXT,       -- 'delete', 'archive', 'restore', 'permanent_delete'
    p_account_id BIGINT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    CASE p_action
        WHEN 'delete' THEN
            -- Smart delete: hard delete if unused, archive if used
            DECLARE v_result JSONB;
            BEGIN
                v_result := public.fn_validate_account_deletion_v2(p_account_id);

                IF (v_result->>'allowed') = 'true' THEN
                    -- Hard delete
                    RETURN public.fn_permanent_delete_account(p_account_id);
                ELSIF (v_result->>'action') = 'archive' THEN
                    -- Archive
                    RETURN public.fn_archive_account(p_account_id);
                ELSE
                    -- Cannot delete or archive
                    RETURN v_result;
                END IF;
            END;

        WHEN 'archive' THEN
            RETURN public.fn_archive_account(p_account_id);

        WHEN 'restore' THEN
            RETURN public.fn_restore_account(p_account_id);

        WHEN 'permanent_delete' THEN
            RETURN public.fn_permanent_delete_account(p_account_id);

        ELSE
            RETURN jsonb_build_object('success', false, 'reason', 'عملية غير معروفة: ' || p_action);
    END CASE;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.fn_discover_account_references(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_validate_account_deletion_v2(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_archive_account(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_restore_account(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_permanent_delete_account(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_account_action(TEXT, BIGINT) TO authenticated;
