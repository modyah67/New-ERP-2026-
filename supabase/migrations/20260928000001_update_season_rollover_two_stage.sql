-- Migration: Update rpc_close_and_rollover_cost_center for strict two-stage seasonal closing
-- Stage 1: Period 1 -> Period 2 within the SAME cost center card (no new card created).
-- Stage 2: Final Year-End closure locks current card permanently and creates a NEW card for the next agricultural year.

CREATE OR REPLACE FUNCTION public.rpc_close_and_rollover_cost_center(
    p_cost_center_id BIGINT,
    p_next_season TEXT DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
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
    SELECT * INTO v_old_cc
    FROM public.cost_centers
    WHERE id = p_cost_center_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'مركز التكلفة برقم % غير موجود', p_cost_center_id;
    END IF;

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

    SELECT COALESCE(SUM(
      CASE 
        WHEN source_type = 'season_rollover' AND source_id ~ '^rollover_([0-9]+)_to_\1$' THEN 0
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
          AND source_type IN ('opening_balance', 'season_rollover')
          AND is_confirmed = TRUE
    ) THEN
        v_net_balance := v_net_balance + COALESCE(v_old_cc.opening_balance, 0);
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

        -- Record rollover transaction inside the same cost center
        IF v_net_balance <> 0 THEN
            v_tx_source_id := 'rollover_' || p_cost_center_id::TEXT || '_to_' || p_cost_center_id::TEXT;
            INSERT INTO public.cost_center_transactions (
                cost_center_id, cost_center_name, cost_center_type,
                source_type, source_id, transaction_date, supplier_name, product_id,
                item_name, category, quantity, unit_price, currency, exchange_rate,
                total_in_currency, amount, notes, is_confirmed
            ) VALUES (
                v_new_code, v_new_name_ar, v_old_cc.cost_center_type,
                'season_rollover', v_tx_source_id, CURRENT_DATE,
                'رصيد مرحل من الفترة الأولى', v_old_cc.product_id,
                'رصيد مرحل من الفترة الأولى (الموسم الأول)',
                'رصيد افتتاحي / مرحل',
                1, v_net_balance, 'EGP', 1.0, v_net_balance, v_net_balance,
                'ترحيل رصيد الفترة الأولى إلى الفترة الثانية داخل نفس الكارت',
                TRUE
            )
            ON CONFLICT (source_type, source_id) DO UPDATE SET
                cost_center_id = EXCLUDED.cost_center_id,
                cost_center_name = EXCLUDED.cost_center_name,
                category = EXCLUDED.category,
                amount = EXCLUDED.amount,
                total_in_currency = EXCLUDED.total_in_currency,
                quantity = EXCLUDED.quantity,
                unit_price = EXCLUDED.unit_price,
                item_name = EXCLUDED.item_name,
                notes = EXCLUDED.notes,
                updated_at = NOW();
        END IF;

    ELSE
        -- ══════════════════════════════════════════════════════════════════════
        -- STAGE 2: FINAL CLOSURE (Locks current card, creates NEW card for next year)
        -- ══════════════════════════════════════════════════════════════════════
        v_new_code := 'CC-' || v_slug || '-' || v_calc_next_season;
        v_new_name_ar := v_clean_crop_name || ' (موسم ' || v_calc_next_season || ')';
        v_new_name_en := COALESCE(v_old_cc.name_en, v_slug) || ' (Season ' || v_calc_next_season || ')';

        INSERT INTO public.cost_centers (
            code, name, name_ar, name_en, cost_center_type, product_id, entity_type,
            color, icon, is_active, status, crop_name, crop_code, season, season_status,
            opening_balance, current_balance, branch_id, description,
            closure_count, season_number
        ) VALUES (
            v_new_code, v_new_name_ar, v_new_name_ar, v_new_name_en,
            v_old_cc.cost_center_type, v_old_cc.product_id, v_old_cc.entity_type,
            v_old_cc.color, v_old_cc.icon, TRUE, 'active',
            v_clean_crop_name, v_slug, v_calc_next_season, 'active',
            v_net_balance, v_net_balance, v_old_cc.branch_id,
            COALESCE(p_notes, 'مرحل تلقائياً من موسم ' || COALESCE(v_old_cc.season, 'السابق')),
            0, 1
        )
        ON CONFLICT (code) DO UPDATE SET
            opening_balance = EXCLUDED.opening_balance,
            current_balance = EXCLUDED.current_balance,
            is_active = TRUE,
            status = 'active',
            season_status = 'active',
            crop_name = EXCLUDED.crop_name,
            closure_count = 0,
            season_number = 1,
            updated_at = NOW()
        RETURNING id INTO v_new_cc_id;

        UPDATE public.cost_centers
        SET status = 'permanently_closed',
            season_status = 'permanently_closed',
            is_active = FALSE,
            closed_at = NOW(),
            closed_by = auth.uid(),
            current_balance = v_net_balance,
            rollover_cost_center_id = v_new_cc_id,
            closure_count = 2,
            updated_at = NOW()
        WHERE id = p_cost_center_id;

        IF v_net_balance <> 0 THEN
            -- Variety breakdown or lump sum into NEW cost center
            FOR v_var IN
                SELECT 
                    product_id,
                    COALESCE(NULLIF(TRIM(item_name), ''), v_clean_crop_name) AS var_item_name,
                    SUM(CASE 
                        WHEN source_type = 'season_rollover' AND source_id ~ '^rollover_([0-9]+)_to_\1$' THEN 0
                        ELSE amount
                    END) AS var_net_amount,
                    SUM(COALESCE(quantity, 0)) AS var_quantity
                FROM public.cost_center_transactions
                WHERE (cost_center_id = v_old_cc.code
                   OR cost_center_id = v_old_cc.id::TEXT
                   OR cost_center_name = v_old_cc.name_ar)
                  AND is_confirmed = TRUE
                GROUP BY product_id, COALESCE(NULLIF(TRIM(item_name), ''), v_clean_crop_name)
                HAVING SUM(CASE 
                        WHEN source_type = 'season_rollover' AND source_id ~ '^rollover_([0-9]+)_to_\1$' THEN 0
                        ELSE amount
                    END) <> 0
            LOOP
                v_variety_count := v_variety_count + 1;
                v_sum_variety_amounts := v_sum_variety_amounts + v_var.var_net_amount;
                v_tx_source_id := 'rollover_' || p_cost_center_id::TEXT || '_to_' || v_new_cc_id::TEXT || '_' || md5(v_var.var_item_name);

                INSERT INTO public.cost_center_transactions (
                    cost_center_id, cost_center_name, cost_center_type,
                    source_type, source_id, transaction_date, supplier_name, product_id,
                    item_name, category, quantity, unit_price, currency, exchange_rate,
                    total_in_currency, amount, notes, is_confirmed
                ) VALUES (
                    v_new_code, v_new_name_ar, v_old_cc.cost_center_type,
                    'season_rollover', v_tx_source_id, CURRENT_DATE,
                    'رصيد افتتاحي للموسم الجديد', v_var.product_id,
                    v_var.var_item_name,
                    'رصيد افتتاحي منقول من الموسم السابق',
                    CASE WHEN v_var.var_quantity > 0 THEN v_var.var_quantity ELSE 1 END,
                    CASE WHEN v_var.var_quantity > 0 THEN ROUND(v_var.var_net_amount / v_var.var_quantity, 2) ELSE v_var.var_net_amount END,
                    'EGP', 1.0, v_var.var_net_amount, v_var.var_net_amount,
                    'رصيد مرحل نهائي للصنف (' || v_var.var_item_name || ') من السنة الزراعية ' || COALESCE(v_old_cc.season, ''),
                    TRUE
                )
                ON CONFLICT (source_type, source_id) DO UPDATE SET
                    cost_center_id = EXCLUDED.cost_center_id,
                    cost_center_name = EXCLUDED.cost_center_name,
                    category = 'رصيد افتتاحي منقول من الموسم السابق',
                    amount = EXCLUDED.amount,
                    total_in_currency = EXCLUDED.total_in_currency,
                    quantity = EXCLUDED.quantity,
                    unit_price = EXCLUDED.unit_price,
                    item_name = EXCLUDED.item_name,
                    notes = EXCLUDED.notes,
                    updated_at = NOW();
            END LOOP;

            IF v_variety_count = 0 THEN
                v_tx_source_id := 'rollover_' || p_cost_center_id::TEXT || '_to_' || v_new_cc_id::TEXT;

                INSERT INTO public.cost_center_transactions (
                    cost_center_id, cost_center_name, cost_center_type,
                    source_type, source_id, transaction_date, supplier_name, product_id,
                    item_name, category, quantity, unit_price, currency, exchange_rate,
                    total_in_currency, amount, notes, is_confirmed
                ) VALUES (
                    v_new_code, v_new_name_ar, v_old_cc.cost_center_type,
                    'season_rollover', v_tx_source_id, CURRENT_DATE,
                    'رصيد افتتاحي للموسم الجديد', v_old_cc.product_id,
                    'رصيد مرحل نهائي من السنة الزراعية ' || COALESCE(v_old_cc.season, ''),
                    'رصيد افتتاحي منقول من الموسم السابق',
                    1, v_net_balance, 'EGP', 1.0, v_net_balance, v_net_balance,
                    'ترحيل نهائي - إقفال السنة الزراعية من مركز #' || p_cost_center_id::TEXT || ' (' || v_old_cc.name_ar || ')',
                    TRUE
                )
                ON CONFLICT (source_type, source_id) DO UPDATE SET
                    cost_center_id = EXCLUDED.cost_center_id,
                    cost_center_name = EXCLUDED.cost_center_name,
                    category = 'رصيد افتتاحي منقول من الموسم السابق',
                    amount = EXCLUDED.amount,
                    total_in_currency = EXCLUDED.total_in_currency,
                    item_name = EXCLUDED.item_name,
                    notes = EXCLUDED.notes,
                    updated_at = NOW();
            ELSIF (v_net_balance - v_sum_variety_amounts) <> 0 THEN
                v_remainder := v_net_balance - v_sum_variety_amounts;
                v_tx_source_id := 'rollover_' || p_cost_center_id::TEXT || '_to_' || v_new_cc_id::TEXT || '_remainder';

                INSERT INTO public.cost_center_transactions (
                    cost_center_id, cost_center_name, cost_center_type,
                    source_type, source_id, transaction_date, supplier_name, product_id,
                    item_name, category, quantity, unit_price, currency, exchange_rate,
                    total_in_currency, amount, notes, is_confirmed
                ) VALUES (
                    v_new_code, v_new_name_ar, v_old_cc.cost_center_type,
                    'season_rollover', v_tx_source_id, CURRENT_DATE,
                    'رصيد افتتاحي للموسم الجديد', v_old_cc.product_id,
                    v_clean_crop_name || ' (رصيد عام غير مخصص)',
                    'رصيد افتتاحي منقول من الموسم السابق',
                    1, v_remainder, 'EGP', 1.0, v_remainder, v_remainder,
                    'رصيد مرحل عام غير مخصص لأصناف محددة من الفترة السابقة',
                    TRUE
                )
                ON CONFLICT (source_type, source_id) DO UPDATE SET
                    cost_center_id = EXCLUDED.cost_center_id,
                    cost_center_name = EXCLUDED.cost_center_name,
                    amount = EXCLUDED.amount,
                    total_in_currency = EXCLUDED.total_in_currency,
                    notes = EXCLUDED.notes,
                    updated_at = NOW();
            END IF;
        END IF;

        -- Auto-update fruit_types pointer to new season
        UPDATE public.fruit_types
        SET cost_center_id = v_new_code
        WHERE cost_center_id = v_old_cc.code
           OR cost_center_id = p_cost_center_id::TEXT;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'message', CASE WHEN v_is_final_closure
            THEN 'تم إقفال السنة الزراعية نهائياً وترحيل الرصيد للسنة الجديدة بنجاح'
            ELSE 'تم ترحيل رصيد الفترة الأولى إلى الفترة الثانية بنجاح داخل نفس الكارت'
        END,
        'closure_stage', v_closure_stage,
        'is_final_closure', v_is_final_closure,
        'closed_cost_center_id', p_cost_center_id,
        'closed_season', v_old_cc.season,
        'closed_season_number', COALESCE(v_old_cc.season_number, 1),
        'new_cost_center_id', v_new_cc_id,
        'new_cost_center_code', v_new_code,
        'new_cost_center_name', v_new_name_ar,
        'rollover_balance', v_net_balance
    );
END;
$$;
