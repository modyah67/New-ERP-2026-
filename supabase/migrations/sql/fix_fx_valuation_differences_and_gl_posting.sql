-- ============================================================================
-- Migration: fix_fx_valuation_differences_and_gl_posting.sql
-- Description: Audit and Fix for Foreign Exchange Valuation Differences (Account: 32211)
-- Standards: IAS 21 / EAS 13 (The Effects of Changes in Foreign Exchange Rates)
-- ============================================================================

-- ── 1. Create Helper Functions for Resolving FX Accounts ───────────────────

CREATE OR REPLACE FUNCTION public.resolve_realized_fx_loss_account(p_company_id UUID DEFAULT NULL)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_acct BIGINT;
BEGIN
    -- 1. Search for leaf account 32211 (فروق تقويم عمله)
    SELECT id INTO v_acct
    FROM public.accounts
    WHERE account_code = '32211'
      AND (p_company_id IS NULL OR company_id = p_company_id OR company_id IS NULL)
    ORDER BY (company_id IS NOT NULL AND company_id = p_company_id) DESC, id ASC
    LIMIT 1;

    -- 2. Fallback to control account 3221 if leaf not found
    IF v_acct IS NULL THEN
        SELECT id INTO v_acct
        FROM public.accounts
        WHERE account_code = '3221'
          AND (p_company_id IS NULL OR company_id = p_company_id OR company_id IS NULL)
        ORDER BY (company_id IS NOT NULL AND company_id = p_company_id) DESC, id ASC
        LIMIT 1;
    END IF;

    -- 3. Fallback to any account with 32211 anywhere in database
    IF v_acct IS NULL THEN
        SELECT id INTO v_acct
        FROM public.accounts
        WHERE account_code = '32211'
        LIMIT 1;
    END IF;

    RETURN v_acct;
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_realized_fx_gain_account(p_company_id UUID DEFAULT NULL)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_acct BIGINT;
BEGIN
    -- In this Chart of Accounts, Account 32211 serves as the unified FX valuation differences account.
    -- Gains are posted as CREDIT to 32211, and Losses are posted as DEBIT to 32211.
    SELECT public.resolve_realized_fx_loss_account(p_company_id) INTO v_acct;
    RETURN v_acct;
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_realized_fx_loss_account(UUID) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.resolve_realized_fx_gain_account(UUID) TO authenticated, anon, service_role;


-- ── 2. Update resolve_gl_account to map FX codes properly to 32211 ─────────

DROP FUNCTION IF EXISTS public.resolve_gl_account(text, uuid);

CREATE OR REPLACE FUNCTION public.resolve_gl_account(
    p_account_code TEXT,
    p_company_id UUID DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_id BIGINT;
    v_target_code TEXT;
BEGIN
    -- 1. البحث المباشر بالكود الأصلي
    SELECT id INTO v_id 
    FROM public.accounts 
    WHERE account_code = p_account_code 
      AND (p_company_id IS NULL OR company_id = p_company_id)
    LIMIT 1;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;

    -- 2. البحث بدون قيد الشركة للكود الأصلي
    SELECT id INTO v_id FROM public.accounts WHERE account_code = p_account_code LIMIT 1;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;

    -- 3. خريطة التحويل للأكواد القديمة
    v_target_code := CASE p_account_code
        WHEN '2101' THEN '9121'
        WHEN '9101' THEN '9121'
        WHEN '2102' THEN '9122'
        WHEN '9102' THEN '9122'
        WHEN '2103' THEN '21115'
        WHEN '2104' THEN '21116'
        WHEN '2105' THEN '9123'
        WHEN '9105' THEN '9123'
        WHEN '2106' THEN '9111'
        WHEN '9106' THEN '9111'
        WHEN '2107' THEN '9112'
        WHEN '9107' THEN '9112'
        WHEN '3000' THEN '23111'
        WHEN '3101' THEN '2321'
        WHEN '5000' THEN '3111'
        WHEN '1030' THEN '12412'
        WHEN '1031' THEN '12413'
        WHEN '1032' THEN '12414'
        WHEN '1040' THEN '12411'
        WHEN '4105' THEN '4131'
        WHEN '4200' THEN '4114'
        -- تصحيح أكواد فروق العملة إلى 32211 بدلاً من فوائد دائنة أو تكاليف مخزنية
        WHEN '4310' THEN '32211'
        WHEN '6151' THEN '32211'
        WHEN '3221' THEN '32211'
        WHEN '5210' THEN '9124'
        WHEN '9210' THEN '9124'
        WHEN '51101' THEN '3211'
        WHEN '51102' THEN '3211'
        WHEN '51104' THEN '3213'
        WHEN '6000' THEN '3211'
        WHEN '6001' THEN '3211'
        WHEN '6002' THEN '3213'
        WHEN '11101' THEN '12121'
        WHEN '11102' THEN '12122'
        WHEN '11103' THEN '12123'
        WHEN '11104' THEN '12124'
        WHEN '11201' THEN '12111'
        WHEN '11202' THEN '12112'
        WHEN '11203' THEN '12113'
        WHEN '11204' THEN '12114'
        WHEN '3900' THEN '2330'
        WHEN '3901' THEN '2331'
        WHEN '3902' THEN '2332'
        WHEN '3903' THEN '2333'
        WHEN '3904' THEN '2334'
        ELSE p_account_code
    END;

    -- 4. البحث بعد التحويل
    SELECT id INTO v_id FROM public.accounts WHERE account_code = v_target_code AND company_id = p_company_id LIMIT 1;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;

    SELECT id INTO v_id FROM public.accounts WHERE account_code = v_target_code LIMIT 1;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;

    -- 5. بديل الخزينة الرئيسية إذا كان المطلوب خزينة أو بنك
    IF v_target_code LIKE '111%' OR v_target_code LIKE '121%' THEN
        SELECT t.account_id INTO v_id
        FROM public.treasuries t
        WHERE t.type = 'main' AND t.account_id IS NOT NULL
        LIMIT 1;
        IF v_id IS NOT NULL THEN RETURN v_id; END IF;
    END IF;

    RETURN v_id;
END;
$$;
