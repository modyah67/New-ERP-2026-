-- Migration 012: Patch Treasury RPC
-- Purpose: Inject company_id into create_treasury to respect the Multi-Company foundation.

BEGIN;

-- Drop the old function since the signature changes
DROP FUNCTION IF EXISTS "public"."create_treasury"("p_name" "text", "p_type" "text", "p_employee_id" "uuid", "p_notes" "text");

CREATE OR REPLACE FUNCTION "public"."create_treasury"(
    "p_name" "text", 
    "p_type" "text", 
    "p_company_id" "uuid", 
    "p_employee_id" "uuid" DEFAULT NULL::"uuid", 
    "p_notes" "text" DEFAULT NULL::"text"
) RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_new_id INTEGER;
    v_account_id INTEGER;
    v_currency TEXT;
BEGIN
    INSERT INTO public.treasuries (name, type, company_id, user_id, notes)
    VALUES (p_name, p_type, p_company_id, p_employee_id, p_notes)
    RETURNING id INTO v_new_id;

    IF p_type = 'main' THEN
        FOREACH v_currency IN ARRAY ARRAY['EGP','USD','EUR','GBP']
        LOOP
            SELECT id INTO v_account_id FROM accounts 
            WHERE account_code = CASE v_currency
                WHEN 'EGP' THEN '11101'
                WHEN 'USD' THEN '11102'
                WHEN 'EUR' THEN '11103'
                WHEN 'GBP' THEN '11104'
            END
            AND company_id = p_company_id;

            INSERT INTO treasury_balances (treasury_id, currency, balance, account_id)
            VALUES (v_new_id, v_currency, 0, v_account_id)
            ON CONFLICT (treasury_id, currency) DO NOTHING;
        END LOOP;
    ELSE
        INSERT INTO treasury_balances (treasury_id, currency, balance, account_id)
        VALUES (v_new_id, 'EGP', 0, NULL);
    END IF;

    RETURN v_new_id;
END;
$$;

COMMIT;
