-- Migration 293: Fix trigger recursion on shipment_cost_items

BEGIN;

CREATE OR REPLACE FUNCTION public.trg_shipment_cost_items_accrual_handler()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Prevent recursive trigger execution when updating journal_entry_id
  IF pg_trigger_depth() > 1 THEN
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    ELSE
      RETURN NEW;
    END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN
    -- If deleted before payment, remove the accrual JE cleanly
    IF OLD.journal_entry_id IS NOT NULL AND OLD.treasury_transaction_id IS NULL AND OLD.bank_transaction_id IS NULL THEN
      DELETE FROM public.account_ledger_entries WHERE journal_entry_id = OLD.journal_entry_id;
      DELETE FROM public.journal_entries WHERE id = OLD.journal_entry_id AND source_type = 'shipment_cost_accrual';
    END IF;
    RETURN OLD;
  END IF;

  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    -- If item is unpaid, sync accrual
    IF NEW.treasury_transaction_id IS NULL AND NEW.bank_transaction_id IS NULL THEN
      PERFORM public.fn_sync_cost_item_accrual(NEW.id);
    END IF;
    RETURN NEW;
  END IF;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_cost_items_accrual_sync ON public.shipment_cost_items;
CREATE TRIGGER trg_cost_items_accrual_sync
AFTER INSERT OR UPDATE OF quantity, unit_price, total_price, category, report_category_id, vendor_type, vendor_id, supplier_id, shipping_company_id, clearing_agent_id, expense_account_id, original_currency OR DELETE ON public.shipment_cost_items
FOR EACH ROW
EXECUTE FUNCTION public.trg_shipment_cost_items_accrual_handler();

NOTIFY pgrst, 'reload schema';

COMMIT;
