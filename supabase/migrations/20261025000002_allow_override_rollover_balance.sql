-- ==============================================================================
-- Migration: 20261025000002_allow_override_rollover_balance.sql
-- Description:
--   1. Update rpc_close_and_rollover_cost_center to accept p_override_balance.
--      This allows caller to pass the exact operational and ledger net balance
--      (e.g. from CostReportDao/report details) so carried-forward balances
--      match precisely without omitting operational packing/waste items.
--   2. Correct existing Mango cost center (id=1) and rollover_1_to_1 to 58555.56.
-- ==============================================================================

DROP FUNCTION IF EXISTS public.rpc_close_and_rollover_cost_center(BIGINT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.rpc_close_and_rollover_cost_center(BIGINT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.rpc_close_and_rollover_cost_center(BIGINT, TEXT, TEXT, TEXT, NUMERIC);

CREATE OR REPLACE FUNCTION public.rpc_close_and_rollover_cost_center(
    p_cost_center_id BIGINT,
    p_next_season TEXT DEFAULT NULL,
    p_notes TEXT DEFAULT NULL,
    p_target_stage TEXT DEFAULT NULL,
    p_override_balance NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_old_cc RECORD;
    v_net_balance NUMERIC := 0;
    v_new_cc_id BIGINT;
    v_new_code TEXT;
    v_new_name_ar TEXT;
    v_new_name_en TEXT;
    v_clean_crop_name TEXT;
    v_slug TEXT;
    v_tx_source_id TEXT;
    v_old_start_year INT;
    v_calc_next_season TEXT;
    v_year_matches TEXT[];
    v_closure_stage TEXT;
    v_new_season_number INT;
    v_new_closure_count INT;
    v_is_final_closure BOOLEAN := FALSE;
    v_var RECORD;
    v_variety_count INT := 0;
    v_sum_variety_amounts NUMERIC := 0;
    v_remainder NUMERIC := 0;
BEGIN
    -- Lock row for concurrency control & idempotency
    SELECT * INTO v_old_cc
    FROM public.cost_centers
    WHERE id = p_cost_center_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'مركز التكلفة برقم % غير موجود', p_cost_center_id;
    END IF;

    -- Strict Idempotency & Lifecycle validation
    IF COALESCE(v_old_cc.is_closed, FALSE) = TRUE AND COALESCE(v_old_cc.season_status, 'active') = 'permanently_closed' THEN
        RAISE EXCEPTION 'مركز التكلفة (%) مقفل نهائياً للسنة الزراعية (%): تم استنفاد الموسمين المسموح بهما ولا يمكن الترحيل مرة أخرى.',
            v_old_cc.name_ar, COALESCE(v_old_cc.season, 'السابق');
    END IF;

    IF COALESCE(v_old_cc.is_closed, FALSE) = TRUE OR v_old_cc.season_status = 'closed' OR v_old_cc.is_active = FALSE OR COALESCE(v_old_cc.status, 'active') = 'closed' THEN
        RAISE EXCEPTION 'مركز التكلفة (%) مقفل بالفعل لهذا الموسم (%) ولا يمكن تكرار إقفاله أو ترحيله',
            v_old_cc.name_ar, COALESCE(v_old_cc.season, 'السابق');
    END IF;

    IF COALESCE(v_old_cc.closure_count, 0) >= 2 THEN
        RAISE EXCEPTION 'مركز التكلفة (%) وصل للحد الأقصى من الإقفالات الموسمية (٢ موسم). السنة الزراعية مقفلة نهائياً.',
            v_old_cc.name_ar;
    END IF;

    -- Stage determination:
    -- If season_number == 1 and closure_count == 0 => Stage 1: intra-card rollover (P1 -> P2, no new card)
    -- If season_number == 2 or closure_count >= 1 => Stage 2: final closure (creates new card for next season)
    IF COALESCE(v_old_cc.season_number, 1) = 1 AND COALESCE(v_old_cc.closure_count, 0) = 0 THEN
        v_closure_stage := 'season_1_to_2';
        v_new_season_number := 2;
        v_new_closure_count := 1;
        v_is_final_closure := FALSE;
    ELSE
        v_closure_stage := 'final_closure';
        v_new_season_number := 1;
        v_new_closure_count := 0;
        v_is_final_closure := TRUE;
    END IF;

    -- Strict stage validation against user request to prevent double-click stage escalation
    IF p_target_stage IS NOT NULL AND TRIM(p_target_stage) <> '' THEN
        IF p_target_stage = 'season_1_to_2' AND v_closure_stage <> 'season_1_to_2' THEN
            RAISE EXCEPTION 'تم ترحيل الفترة الأولى بالفعل لمركز التكلفة (%) ولا يمكن تكرار ترحيلها.', v_old_cc.name_ar;
        ELSIF p_target_stage = 'final_closure' AND v_closure_stage <> 'final_closure' THEN
            RAISE EXCEPTION 'يجب ترحيل الفترة الأولى أولاً قبل تنفيذ الإقفال النهائي للسنة لمركز التكلفة (%).', v_old_cc.name_ar;
        END IF;
    END IF;

    v_year_matches := regexp_matches(COALESCE(v_old_cc.season, v_old_cc.name_ar, '2026-2027'), '(\d{4})');
    IF v_year_matches IS NOT NULL AND array_length(v_year_matches, 1) >= 1 THEN
        v_old_start_year := v_year_matches[1]::INT;
    ELSE
        v_old_start_year := EXTRACT(YEAR FROM CURRENT_DATE)::INT;
    END IF;

    -- IF final closure: increment to next year. IF NOT final closure: preserve current season!
    IF v_is_final_closure THEN
        v_calc_next_season := (v_old_start_year + 1)::TEXT || '-' || (v_old_start_year + 2)::TEXT;
    ELSE
        v_calc_next_season := v_old_start_year::TEXT || '-' || (v_old_start_year + 1)::TEXT;
    END IF;

    IF p_next_season IS NOT NULL AND TRIM(p_next_season) <> '' THEN
        v_year_matches := regexp_matches(TRIM(p_next_season), '(\d{4})');
        IF v_year_matches IS NOT NULL AND array_length(v_year_matches, 1) >= 1 THEN
            DECLARE
                v_user_start_year INT := v_year_matches[1]::INT;
            BEGIN
                v_calc_next_season := v_user_start_year::TEXT || '-' || (v_user_start_year + 1)::TEXT;
            END;
        END IF;
    END IF;

    v_clean_crop_name := COALESCE(NULLIF(v_old_cc.crop_name, ''), v_old_cc.name_ar);
    v_clean_crop_name := REGEXP_REPLACE(v_clean_crop_name, '\s*[\(\[\{]?(موسم|season)\s*[^)\]\}]*[\)\]\}]?', '', 'gi');
    v_clean_crop_name := REGEXP_REPLACE(v_clean_crop_name, '\s*[\(\[\{]?\d{4}\s*[-/–]\s*\d{4}[\)\]\}]?', '', 'g');
    v_clean_crop_name := REGEXP_REPLACE(v_clean_crop_name, '\s*[\(\[\{]?\d{4}[\)\]\}]?', '', 'g');
    v_clean_crop_name := public.fn_canonical_crop_name(v_clean_crop_name);

    v_slug := COALESCE(NULLIF(v_old_cc.crop_code, ''), public.fn_resolve_crop_slug(v_clean_crop_name));

    -- Determine net balance:
    -- If p_override_balance is explicitly provided, use it directly (ensures 100% exact match with operational report)
    IF p_override_balance IS NOT NULL THEN
        v_net_balance := p_override_balance;
    ELSE
        -- Exclude any intra-card rollover transaction ('rollover_X_to_X') to prevent double-counting
        SELECT COALESCE(SUM(
          CASE 
            WHEN (source_type = 'season_rollover' AND source_id ~ '^rollover_([0-9]+)_to_\1$') THEN 0
            ELSE amount
          END
        ), 0) INTO v_net_balance
        FROM public.cost_center_transactions
        WHERE (cost_center_id = v_old_cc.code
           OR cost_center_id = v_old_cc.id::TEXT
           OR cost_center_name = v_old_cc.name_ar)
          AND is_confirmed = TRUE;

        IF NOT EXISTS (
            SELECT 1 FROM public.cost_center_transactions
            WHERE (cost_center_id = v_old_cc.code OR cost_center_id = v_old_cc.id::TEXT OR cost_center_name = v_old_cc.name_ar)
              AND (source_type IN ('opening_balance', 'season_rollover') OR is_opening_balance = TRUE)
              AND is_confirmed = TRUE
        ) THEN
            v_net_balance := v_net_balance + COALESCE(v_old_cc.opening_balance, 0);
        END IF;
    END IF;

    IF NOT v_is_final_closure THEN
        -- ══════════════════════════════════════════════════════════════════════
        -- STAGE 1: INTRA-CARD ROLLOVER (P1 -> P2 inside SAME card, NO new card)
        -- ══════════════════════════════════════════════════════════════════════
        v_new_cc_id := p_cost_center_id;
        v_new_code := v_old_cc.code;
        v_new_name_ar := v_old_cc.name_ar;
        v_new_name_en := v_old_cc.name_en;

        UPDATE public.cost_centers
        SET season_number = 2,
            closure_count = 1,
            is_active = TRUE,
            status = 'active',
            season_status = 'active',
            opening_balance = v_net_balance,
            current_balance = v_net_balance,
            closed_at = NOW(),
            closed_by = auth.uid(),
            description = COALESCE(p_notes, description, 'تم ترحيل الفترة الأولى إلى الفترة الثانية داخل نفس الكارت'),
            updated_at = NOW()
        WHERE id = p_cost_center_id;

        -- Record carried-forward rollover transaction inside the same cost center
        IF v_net_balance <> 0 THEN
            v_tx_source_id := 'rollover_' || p_cost_center_id::TEXT || '_to_' || p_cost_center_id::TEXT;
            INSERT INTO public.cost_center_transactions (
                cost_center_id,
                cost_center_name,
                cost_center_type,
                source_type,
                source_id,
                transaction_date,
                supplier_name,
                product_id,
                item_name,
                category,
                quantity,
                unit_price,
                currency,
                exchange_rate,
                total_in_currency,
                amount,
                notes,
                is_confirmed,
                is_opening_balance,
                transaction_type
            ) VALUES (
                v_old_cc.code,
                v_old_cc.name_ar,
                v_old_cc.cost_center_type,
                'season_rollover',
                v_tx_source_id,
                CURRENT_DATE,
                'رصيد مرحل من الفترة الأولى',
                v_old_cc.product_id,
                'رصيد مرحل من الفترة الأولى إلى الفترة الثانية',
                'رصيد مرحل من الفترة الأولى',
                1,
                v_net_balance,
                'EGP',
                1.0,
                v_net_balance,
                v_net_balance,
                COALESCE(p_notes, 'ترحيل رصيد الفترة الأولى إلى الفترة الثانية داخل نفس كارت مركز التكلفة (' || v_old_cc.name_ar || ')'),
                TRUE,
                TRUE,
                'carried_forward'
            )
            ON CONFLICT (source_type, source_id) DO UPDATE SET
                cost_center_id = EXCLUDED.cost_center_id,
                cost_center_name = EXCLUDED.cost_center_name,
                amount = EXCLUDED.amount,
                unit_price = EXCLUDED.unit_price,
                total_in_currency = EXCLUDED.total_in_currency,
                notes = EXCLUDED.notes,
                transaction_date = EXCLUDED.transaction_date,
                is_opening_balance = TRUE,
                transaction_type = 'carried_forward',
                updated_at = NOW();
        END IF;

    ELSE
        -- ══════════════════════════════════════════════════════════════════════
        -- STAGE 2: FINAL CLOSURE (Current card locked; NEW card created)
        -- ══════════════════════════════════════════════════════════════════════
        UPDATE public.cost_centers
        SET is_closed = TRUE,
            is_active = FALSE,
            status = 'closed',
            season_status = 'permanently_closed',
            closed_at = NOW(),
            closed_by = auth.uid(),
            closure_count = 2,
            season_number = 2,
            updated_at = NOW()
        WHERE id = p_cost_center_id;

        v_new_code := 'CC-' || v_slug || '-' || v_calc_next_season;
        v_new_name_ar := v_clean_crop_name || ' (موسم ' || v_calc_next_season || ')';
        v_new_name_en := COALESCE(v_old_cc.name_en, v_slug) || ' (Season ' || v_calc_next_season || ')';

        INSERT INTO public.cost_centers (
            code,
            name,
            name_ar,
            name_en,
            cost_center_type,
            season,
            season_number,
            closure_count,
            crop_name,
            crop_code,
            product_id,
            is_active,
            status,
            season_status,
            is_closed,
            opening_balance,
            current_balance,
            description,
            color,
            icon,
            company_id,
            created_at,
            updated_at
        ) VALUES (
            v_new_code,
            v_new_name_ar,
            v_new_name_ar,
            v_new_name_en,
            v_old_cc.cost_center_type,
            v_calc_next_season,
            1,
            0,
            v_clean_crop_name,
            v_slug,
            v_old_cc.product_id,
            TRUE,
            'active',
            'active',
            FALSE,
            v_net_balance,
            v_net_balance,
            COALESCE(p_notes, 'رصيد مرحل من إقفال السنة الزراعية السابقة ' || COALESCE(v_old_cc.season, '')),
            v_old_cc.color,
            v_old_cc.icon,
            v_old_cc.company_id,
            NOW(),
            NOW()
        )
        ON CONFLICT (code) DO UPDATE SET
            name = EXCLUDED.name,
            name_ar = EXCLUDED.name_ar,
            name_en = EXCLUDED.name_en,
            season = EXCLUDED.season,
            season_number = 1,
            closure_count = 0,
            opening_balance = EXCLUDED.opening_balance,
            current_balance = EXCLUDED.current_balance,
            is_active = TRUE,
            status = 'active',
            season_status = 'active',
            is_closed = FALSE,
            description = EXCLUDED.description,
            updated_at = NOW()
        RETURNING id INTO v_new_cc_id;

        UPDATE public.cost_centers
        SET rollover_cost_center_id = v_new_cc_id
        WHERE id = p_cost_center_id;

        IF v_net_balance <> 0 THEN
            v_tx_source_id := 'rollover_' || p_cost_center_id::TEXT || '_to_' || v_new_cc_id::TEXT;
            INSERT INTO public.cost_center_transactions (
                cost_center_id,
                cost_center_name,
                cost_center_type,
                source_type,
                source_id,
                transaction_date,
                supplier_name,
                product_id,
                item_name,
                category,
                quantity,
                unit_price,
                currency,
                exchange_rate,
                total_in_currency,
                amount,
                notes,
                is_confirmed,
                is_opening_balance,
                transaction_type
            ) VALUES (
                v_new_code,
                v_new_name_ar,
                v_old_cc.cost_center_type,
                'season_rollover',
                v_tx_source_id,
                CURRENT_DATE,
                'رصيد مرحل من موسم سابق',
                v_old_cc.product_id,
                'رصيد مرحل من السنة الزراعية السابقة (' || COALESCE(v_old_cc.season, '') || ')',
                'رصيد مرحل',
                1,
                v_net_balance,
                'EGP',
                1.0,
                v_net_balance,
                v_net_balance,
                COALESCE(p_notes, 'ترحيل رصيد إقفال السنة الزراعية السابقة ' || COALESCE(v_old_cc.season, '') || ' لمركز ' || v_old_cc.name_ar),
                TRUE,
                TRUE,
                'carried_forward'
            )
            ON CONFLICT (source_type, source_id) DO UPDATE SET
                cost_center_id = EXCLUDED.cost_center_id,
                cost_center_name = EXCLUDED.cost_center_name,
                amount = EXCLUDED.amount,
                unit_price = EXCLUDED.unit_price,
                total_in_currency = EXCLUDED.total_in_currency,
                notes = EXCLUDED.notes,
                transaction_date = EXCLUDED.transaction_date,
                is_opening_balance = TRUE,
                transaction_type = 'carried_forward',
                updated_at = NOW();
        END IF;

    END IF;

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', CASE 
            WHEN NOT v_is_final_closure THEN 'تم إقفال الفترة الأولى بنجاح والترحيل إلى الفترة الثانية داخل نفس الكارت (' || v_old_cc.name_ar || ')'
            ELSE 'تم إقفال السنة الزراعية نهائياً وتعيين الكارت للاطلاع فقط، وإنشاء مركز تكلفة جديد: ' || v_new_name_ar 
        END,
        'closure_stage', v_closure_stage,
        'is_final_closure', v_is_final_closure,
        'closed_cost_center_id', p_cost_center_id,
        'new_cost_center_id', v_new_cc_id,
        'new_cost_center_code', v_new_code,
        'new_cost_center_name', v_new_name_ar,
        'rollover_balance', v_net_balance
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.rpc_close_and_rollover_cost_center(BIGINT, TEXT, TEXT, TEXT, NUMERIC) TO authenticated, service_role, anon;

-- Fix existing Mango cost center id=1 and rollover_1_to_1 if needed
UPDATE public.cost_center_transactions
SET amount = 58555.56,
    unit_price = 58555.56,
    total_in_currency = 58555.56,
    notes = 'ترحيل رصيد الفترة الأولى إلى الفترة الثانية داخل نفس كارت مركز التكلفة (مانجو (موسم 2026-2027))'
WHERE source_id = 'rollover_1_to_1';

UPDATE public.cost_centers
SET opening_balance = 58555.56,
    current_balance = 58555.56
WHERE id = 1;
