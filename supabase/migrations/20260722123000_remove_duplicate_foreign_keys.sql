DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'treasury_balances_account_id_fkey'
    ) THEN
        ALTER TABLE public.treasury_balances
        DROP CONSTRAINT treasury_balances_account_id_fkey;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'treasury_balances_treasury_id_fkey'
    ) THEN
        ALTER TABLE public.treasury_balances
        DROP CONSTRAINT treasury_balances_treasury_id_fkey;
    END IF;
END $$;