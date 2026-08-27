-- Migration 141: Include cleared cheques in shareholder deposits and withdrawals
-- ============================================================================
-- The v_shareholders view previously only summed treasury_transactions and
-- bank_account_transactions. Cleared cheques create bank_account_transactions
-- under entity_type='cheque', so they were being ignored in the shareholder's
-- total_deposits and total_withdrawals, causing a discrepancy with the balance.
-- This also includes currency exchange transactions.

BEGIN;

DROP VIEW IF EXISTS "public"."v_shareholders";

CREATE VIEW "public"."v_shareholders" AS
 SELECT "id",
    "code",
    "name",
    "created_at",
    "initial_balance_egp",
    "current_balance_egp",
    "initial_balance_usd",
    "current_balance_usd",
    "initial_balance_eur",
    "current_balance_eur",
    "initial_balance_gbp",
    "current_balance_gbp",
    
    -- EGP
    ((
        CASE WHEN (COALESCE("initial_balance_egp", 0) > 0) THEN COALESCE("initial_balance_egp", 0) ELSE 0 END
        + COALESCE((SELECT sum(amount) FROM public.treasury_transactions WHERE type = 'deposit' AND currency = 'EGP' AND shareholder_id = s.id), 0)
        + COALESCE((SELECT sum(bat.amount) FROM public.bank_account_transactions bat JOIN public.bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type IN ('deposit','currency_exchange_in') AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::text AND ba.currency = 'EGP'), 0)
        + COALESCE((SELECT sum(amount) FROM public.cheques WHERE type = 'incoming' AND status = 'cleared' AND currency = 'EGP' AND counterparty_type = 'shareholder' AND shareholder_id = s.id), 0)
    )) AS "total_deposits_egp",
    ((
        CASE WHEN (COALESCE("initial_balance_egp", 0) < 0) THEN abs(COALESCE("initial_balance_egp", 0)) ELSE 0 END
        + COALESCE((SELECT sum(amount) FROM public.treasury_transactions WHERE type = 'expense' AND currency = 'EGP' AND shareholder_id = s.id), 0)
        + COALESCE((SELECT sum(bat.amount) FROM public.bank_account_transactions bat JOIN public.bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type IN ('withdraw','withdrawal','currency_exchange_out') AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::text AND ba.currency = 'EGP'), 0)
        + COALESCE((SELECT sum(amount) FROM public.cheques WHERE type = 'outgoing' AND status = 'cleared' AND currency = 'EGP' AND counterparty_type = 'shareholder' AND shareholder_id = s.id), 0)
    )) AS "total_withdrawals_egp",

    -- USD
    ((
        CASE WHEN (COALESCE("initial_balance_usd", 0) > 0) THEN COALESCE("initial_balance_usd", 0) ELSE 0 END
        + COALESCE((SELECT sum(amount) FROM public.treasury_transactions WHERE type = 'deposit' AND currency = 'USD' AND shareholder_id = s.id), 0)
        + COALESCE((SELECT sum(bat.amount) FROM public.bank_account_transactions bat JOIN public.bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type IN ('deposit','currency_exchange_in') AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::text AND ba.currency = 'USD'), 0)
        + COALESCE((SELECT sum(amount) FROM public.cheques WHERE type = 'incoming' AND status = 'cleared' AND currency = 'USD' AND counterparty_type = 'shareholder' AND shareholder_id = s.id), 0)
    )) AS "total_deposits_usd",
    ((
        CASE WHEN (COALESCE("initial_balance_usd", 0) < 0) THEN abs(COALESCE("initial_balance_usd", 0)) ELSE 0 END
        + COALESCE((SELECT sum(amount) FROM public.treasury_transactions WHERE type = 'expense' AND currency = 'USD' AND shareholder_id = s.id), 0)
        + COALESCE((SELECT sum(bat.amount) FROM public.bank_account_transactions bat JOIN public.bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type IN ('withdraw','withdrawal','currency_exchange_out') AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::text AND ba.currency = 'USD'), 0)
        + COALESCE((SELECT sum(amount) FROM public.cheques WHERE type = 'outgoing' AND status = 'cleared' AND currency = 'USD' AND counterparty_type = 'shareholder' AND shareholder_id = s.id), 0)
    )) AS "total_withdrawals_usd",

    -- EUR
    ((
        CASE WHEN (COALESCE("initial_balance_eur", 0) > 0) THEN COALESCE("initial_balance_eur", 0) ELSE 0 END
        + COALESCE((SELECT sum(amount) FROM public.treasury_transactions WHERE type = 'deposit' AND currency = 'EUR' AND shareholder_id = s.id), 0)
        + COALESCE((SELECT sum(bat.amount) FROM public.bank_account_transactions bat JOIN public.bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type IN ('deposit','currency_exchange_in') AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::text AND ba.currency = 'EUR'), 0)
        + COALESCE((SELECT sum(amount) FROM public.cheques WHERE type = 'incoming' AND status = 'cleared' AND currency = 'EUR' AND counterparty_type = 'shareholder' AND shareholder_id = s.id), 0)
    )) AS "total_deposits_eur",
    ((
        CASE WHEN (COALESCE("initial_balance_eur", 0) < 0) THEN abs(COALESCE("initial_balance_eur", 0)) ELSE 0 END
        + COALESCE((SELECT sum(amount) FROM public.treasury_transactions WHERE type = 'expense' AND currency = 'EUR' AND shareholder_id = s.id), 0)
        + COALESCE((SELECT sum(bat.amount) FROM public.bank_account_transactions bat JOIN public.bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type IN ('withdraw','withdrawal','currency_exchange_out') AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::text AND ba.currency = 'EUR'), 0)
        + COALESCE((SELECT sum(amount) FROM public.cheques WHERE type = 'outgoing' AND status = 'cleared' AND currency = 'EUR' AND counterparty_type = 'shareholder' AND shareholder_id = s.id), 0)
    )) AS "total_withdrawals_eur",

    -- GBP
    ((
        CASE WHEN (COALESCE("initial_balance_gbp", 0) > 0) THEN COALESCE("initial_balance_gbp", 0) ELSE 0 END
        + COALESCE((SELECT sum(amount) FROM public.treasury_transactions WHERE type = 'deposit' AND currency = 'GBP' AND shareholder_id = s.id), 0)
        + COALESCE((SELECT sum(bat.amount) FROM public.bank_account_transactions bat JOIN public.bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type IN ('deposit','currency_exchange_in') AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::text AND ba.currency = 'GBP'), 0)
        + COALESCE((SELECT sum(amount) FROM public.cheques WHERE type = 'incoming' AND status = 'cleared' AND currency = 'GBP' AND counterparty_type = 'shareholder' AND shareholder_id = s.id), 0)
    )) AS "total_deposits_gbp",
    ((
        CASE WHEN (COALESCE("initial_balance_gbp", 0) < 0) THEN abs(COALESCE("initial_balance_gbp", 0)) ELSE 0 END
        + COALESCE((SELECT sum(amount) FROM public.treasury_transactions WHERE type = 'expense' AND currency = 'GBP' AND shareholder_id = s.id), 0)
        + COALESCE((SELECT sum(bat.amount) FROM public.bank_account_transactions bat JOIN public.bank_accounts ba ON ba.id = bat.bank_account_id WHERE bat.type IN ('withdraw','withdrawal','currency_exchange_out') AND bat.entity_type = 'shareholder' AND bat.entity_id = s.id::text AND ba.currency = 'GBP'), 0)
        + COALESCE((SELECT sum(amount) FROM public.cheques WHERE type = 'outgoing' AND status = 'cleared' AND currency = 'GBP' AND counterparty_type = 'shareholder' AND shareholder_id = s.id), 0)
    )) AS "total_withdrawals_gbp"
    
   FROM public.shareholders s;

-- Recalculate balances to ensure any cleared cheques that were wiped
-- in migration 138 are now properly restored to the balances.
DO $$
BEGIN
    UPDATE public.shareholders s
    SET 
        current_balance_egp = v.total_deposits_egp - v.total_withdrawals_egp,
        current_balance_usd = v.total_deposits_usd - v.total_withdrawals_usd,
        current_balance_eur = v.total_deposits_eur - v.total_withdrawals_eur,
        current_balance_gbp = v.total_deposits_gbp - v.total_withdrawals_gbp
    FROM public.v_shareholders v
    WHERE s.id = v.id;
END;
$$;

COMMIT;
