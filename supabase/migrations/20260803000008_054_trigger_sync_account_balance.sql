CREATE OR REPLACE FUNCTION public.fn_sync_account_balance_on_ledger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE accounts
        SET balance = balance + COALESCE(NEW.debit, 0) - COALESCE(NEW.credit, 0),
            updated_at = now()
        WHERE id = NEW.account_id;
        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        UPDATE accounts
        SET balance = balance - COALESCE(OLD.debit, 0) + COALESCE(OLD.credit, 0),
            updated_at = now()
        WHERE id = OLD.account_id;
        RETURN OLD;

    ELSIF TG_OP = 'UPDATE' THEN
        -- Reverse old entry
        UPDATE accounts
        SET balance = balance - COALESCE(OLD.debit, 0) + COALESCE(OLD.credit, 0),
            updated_at = now()
        WHERE id = OLD.account_id;
        -- Apply new entry
        UPDATE accounts
        SET balance = balance + COALESCE(NEW.debit, 0) - COALESCE(NEW.credit, 0),
            updated_at = now()
        WHERE id = NEW.account_id;
        RETURN NEW;
    END IF;
END;
$function$;

DROP TRIGGER IF EXISTS trg_sync_account_balance ON account_ledger_entries;
CREATE TRIGGER trg_sync_account_balance
    AFTER INSERT OR UPDATE OR DELETE ON account_ledger_entries
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_sync_account_balance_on_ledger();
