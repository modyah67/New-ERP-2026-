-- Migration: Full Schema Integrity Restoration
-- Date: 2026-07-22
-- Idempotent script restoring all missing database objects

-- ==========================================
-- 1. RESTORE MISSING SEQUENCES & DEFAULTS
-- ==========================================

-- Sequence and default for public.clearing_agents
CREATE SEQUENCE IF NOT EXISTS public.clearing_agents_id_seq;
SELECT setval('public.clearing_agents_id_seq', COALESCE((SELECT MAX(id) FROM public.clearing_agents), 0) + 1, false);
ALTER TABLE public.clearing_agents ALTER COLUMN id SET DEFAULT nextval('public.clearing_agents_id_seq'::regclass);
ALTER SEQUENCE public.clearing_agents_id_seq OWNED BY public.clearing_agents.id;
GRANT ALL ON SEQUENCE public.clearing_agents_id_seq TO anon, authenticated, service_role;

-- Sequence and default for public.export_shipment_items
CREATE SEQUENCE IF NOT EXISTS public.export_shipment_items_id_seq;
SELECT setval('public.export_shipment_items_id_seq', COALESCE((SELECT MAX(id) FROM public.export_shipment_items), 0) + 1, false);
ALTER TABLE public.export_shipment_items ALTER COLUMN id SET DEFAULT nextval('public.export_shipment_items_id_seq'::regclass);
ALTER SEQUENCE public.export_shipment_items_id_seq OWNED BY public.export_shipment_items.id;
GRANT ALL ON SEQUENCE public.export_shipment_items_id_seq TO anon, authenticated, service_role;

-- Sequence and default for public.lot_returns
CREATE SEQUENCE IF NOT EXISTS public.lot_returns_id_seq;
SELECT setval('public.lot_returns_id_seq', COALESCE((SELECT MAX(id) FROM public.lot_returns), 0) + 1, false);
ALTER TABLE public.lot_returns ALTER COLUMN id SET DEFAULT nextval('public.lot_returns_id_seq'::regclass);
ALTER SEQUENCE public.lot_returns_id_seq OWNED BY public.lot_returns.id;
GRANT ALL ON SEQUENCE public.lot_returns_id_seq TO anon, authenticated, service_role;

-- Sequence and default for public.station_product_batches
CREATE SEQUENCE IF NOT EXISTS public.station_product_batches_id_seq;
SELECT setval('public.station_product_batches_id_seq', COALESCE((SELECT MAX(id) FROM public.station_product_batches), 0) + 1, false);
ALTER TABLE public.station_product_batches ALTER COLUMN id SET DEFAULT nextval('public.station_product_batches_id_seq'::regclass);
ALTER SEQUENCE public.station_product_batches_id_seq OWNED BY public.station_product_batches.id;
GRANT ALL ON SEQUENCE public.station_product_batches_id_seq TO anon, authenticated, service_role;

-- Sequence and default for public.station_products
CREATE SEQUENCE IF NOT EXISTS public.station_products_id_seq;
SELECT setval('public.station_products_id_seq', COALESCE((SELECT MAX(id) FROM public.station_products), 0) + 1, false);
ALTER TABLE public.station_products ALTER COLUMN id SET DEFAULT nextval('public.station_products_id_seq'::regclass);
ALTER SEQUENCE public.station_products_id_seq OWNED BY public.station_products.id;
GRANT ALL ON SEQUENCE public.station_products_id_seq TO anon, authenticated, service_role;

-- ==========================================
-- 2. RESTORE MISSING FOREIGN KEYS
-- ==========================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'audit_logs_text_user_id_fkey' AND table_schema = 'public'
    ) THEN
        ALTER TABLE ONLY "public"."audit_logs_text" ADD CONSTRAINT "audit_logs_text_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'audit_logs_user_id_fkey' AND table_schema = 'public'
    ) THEN
        ALTER TABLE ONLY "public"."audit_logs" ADD CONSTRAINT "audit_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'bank_account_transactions_created_by_fkey' AND table_schema = 'public'
    ) THEN
        ALTER TABLE ONLY "public"."bank_account_transactions" ADD CONSTRAINT "bank_account_transactions_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'cash_payments_created_by_fkey' AND table_schema = 'public'
    ) THEN
        ALTER TABLE ONLY "public"."cash_payments" ADD CONSTRAINT "cash_payments_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'cashbox_transactions_user_id_fkey' AND table_schema = 'public'
    ) THEN
        ALTER TABLE ONLY "public"."cashbox_transactions" ADD CONSTRAINT "cashbox_transactions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'cheques_created_by_fkey' AND table_schema = 'public'
    ) THEN
        ALTER TABLE ONLY "public"."cheques" ADD CONSTRAINT "cheques_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'fk_treasury_balances_account_id' AND table_schema = 'public'
    ) THEN
        ALTER TABLE ONLY "public"."treasury_balances" ADD CONSTRAINT "fk_treasury_balances_account_id" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE SET NULL;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'fk_treasury_balances_treasury_id' AND table_schema = 'public'
    ) THEN
        ALTER TABLE ONLY "public"."treasury_balances" ADD CONSTRAINT "fk_treasury_balances_treasury_id" FOREIGN KEY ("treasury_id") REFERENCES "public"."treasuries"("id") ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'invoice_edits_edited_by_fkey' AND table_schema = 'public'
    ) THEN
        ALTER TABLE ONLY "public"."invoice_edits" ADD CONSTRAINT "invoice_edits_edited_by_fkey" FOREIGN KEY ("edited_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'ledger_entries_created_by_fkey' AND table_schema = 'public'
    ) THEN
        ALTER TABLE ONLY "public"."ledger_entries" ADD CONSTRAINT "ledger_entries_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'lot_returns_created_by_fkey' AND table_schema = 'public'
    ) THEN
        ALTER TABLE ONLY "public"."lot_returns" ADD CONSTRAINT "lot_returns_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'profiles_id_fkey' AND table_schema = 'public'
    ) THEN
        ALTER TABLE ONLY "public"."profiles" ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'profit_distribution_settings_user_id_fkey' AND table_schema = 'public'
    ) THEN
        ALTER TABLE ONLY "public"."profit_distribution_settings" ADD CONSTRAINT "profit_distribution_settings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'purchase_invoices_user_id_fkey' AND table_schema = 'public'
    ) THEN
        ALTER TABLE ONLY "public"."purchase_invoices" ADD CONSTRAINT "purchase_invoices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'sales_invoices_user_id_fkey' AND table_schema = 'public'
    ) THEN
        ALTER TABLE ONLY "public"."sales_invoices" ADD CONSTRAINT "sales_invoices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'shareholder_profit_distributions_created_by_fkey' AND table_schema = 'public'
    ) THEN
        ALTER TABLE ONLY "public"."shareholder_profit_distributions" ADD CONSTRAINT "shareholder_profit_distributions_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'shipment_profitability_snapshots_created_by_fkey' AND table_schema = 'public'
    ) THEN
        ALTER TABLE ONLY "public"."shipment_profitability_snapshots" ADD CONSTRAINT "shipment_profitability_snapshots_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'stock_batches_user_id_fkey' AND table_schema = 'public'
    ) THEN
        ALTER TABLE ONLY "public"."stock_batches" ADD CONSTRAINT "stock_batches_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'stock_movements_user_id_fkey' AND table_schema = 'public'
    ) THEN
        ALTER TABLE ONLY "public"."stock_movements" ADD CONSTRAINT "stock_movements_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'stock_transfers_from_station_id_fkey' AND table_schema = 'public'
    ) THEN
        ALTER TABLE ONLY "public"."stock_transfers" ADD CONSTRAINT "stock_transfers_from_station_id_fkey" FOREIGN KEY ("from_station_id") REFERENCES "public"."stations"("id") ON DELETE SET NULL;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'tenant_users_user_id_fkey' AND table_schema = 'public'
    ) THEN
        ALTER TABLE ONLY "public"."tenant_users" ADD CONSTRAINT "tenant_users_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'treasuries_employee_id_fkey' AND table_schema = 'public'
    ) THEN
        ALTER TABLE ONLY "public"."treasuries" ADD CONSTRAINT "treasuries_employee_id_fkey" FOREIGN KEY ("employee_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'treasury_transactions_from_treasury_id_fkey' AND table_schema = 'public'
    ) THEN
        ALTER TABLE ONLY "public"."treasury_transactions" ADD CONSTRAINT "treasury_transactions_from_treasury_id_fkey" FOREIGN KEY ("from_treasury_id") REFERENCES "public"."treasuries"("id");
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'treasury_transactions_related_treasury_id_fkey' AND table_schema = 'public'
    ) THEN
        ALTER TABLE ONLY "public"."treasury_transactions" ADD CONSTRAINT "treasury_transactions_related_treasury_id_fkey" FOREIGN KEY ("related_treasury_id") REFERENCES "public"."treasuries"("id");
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'treasury_transactions_to_treasury_id_fkey' AND table_schema = 'public'
    ) THEN
        ALTER TABLE ONLY "public"."treasury_transactions" ADD CONSTRAINT "treasury_transactions_to_treasury_id_fkey" FOREIGN KEY ("to_treasury_id") REFERENCES "public"."treasuries"("id");
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.table_constraints 
        WHERE constraint_name = 'users_id_fkey' AND table_schema = 'public'
    ) THEN
        ALTER TABLE ONLY "public"."users" ADD CONSTRAINT "users_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
    END IF;
END $$;

-- ==========================================
-- 3. RESTORE MISSING INDEXES
-- ==========================================

-- ==========================================
-- 4. RESTORE ROW LEVEL SECURITY & POLICIES
-- ==========================================

ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs_text ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bank_account_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bank_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cash_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cashbox_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cheques ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cost_report_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.currencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exchange_rates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_shipment_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.financial_audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fiscal_year_audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fiscal_year_backup_metadata ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fiscal_year_closing_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fiscal_year_closing_lock ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fiscal_year_closing_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fiscal_year_inventory_snapshot ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fiscal_years ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fruit_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fruit_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.general_cost_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoice_edits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ledger_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lot_grading_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lot_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lot_returns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.packing_order_cost_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.packing_order_sortings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.packing_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.packing_recipes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prep_center_cost_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pricing_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products_backup ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profit_distribution_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.proforma_invoice_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.proforma_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_invoice_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_invoice_items_backup ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchases_backup ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.raw_material_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.raw_materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_invoice_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sales_invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shareholder_profit_distributions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shipment_cost_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shipment_cost_breakdown ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shipment_cost_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shipment_profitability_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shipment_recipe_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.statement_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.station_product_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.station_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_batches_uuid_legacy ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_movements_uuid_legacy ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers_backup ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.treasuries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.treasury_balances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.treasury_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.unit_conversions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.warehouses ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Admin full access' AND tablename = 'treasuries' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Admin full access" ON "public"."treasuries" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."users"
  WHERE (("users"."id" = "auth"."uid"()) AND ("users"."is_admin" = true))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."users"
  WHERE (("users"."id" = "auth"."uid"()) AND ("users"."is_admin" = true)))));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Admin full access' AND tablename = 'treasury_balances' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Admin full access" ON "public"."treasury_balances" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."users"
  WHERE (("users"."id" = "auth"."uid"()) AND ("users"."is_admin" = true))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."users"
  WHERE (("users"."id" = "auth"."uid"()) AND ("users"."is_admin" = true)))));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'All authenticated' AND tablename = 'shareholder_profit_distributions' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "All authenticated" ON "public"."shareholder_profit_distributions" USING (("auth"."role"() = 'authenticated'::"text"));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all access' AND tablename = 'export_shipment_items' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all access" ON "public"."export_shipment_items" USING (true) WITH CHECK (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all access' AND tablename = 'lot_returns' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all access" ON "public"."lot_returns" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all access' AND tablename = 'station_product_batches' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all access" ON "public"."station_product_batches" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all access' AND tablename = 'station_products' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all access" ON "public"."station_products" USING (true) WITH CHECK (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all access to statement_notes' AND tablename = 'statement_notes' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all access to statement_notes" ON "public"."statement_notes" USING (true) WITH CHECK (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all authenticated' AND tablename = 'cost_report_categories' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all authenticated" ON "public"."cost_report_categories" TO "authenticated" USING (true) WITH CHECK (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all authenticated' AND tablename = 'fruit_types' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all authenticated" ON "public"."fruit_types" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all authenticated' AND tablename = 'general_cost_items' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all authenticated" ON "public"."general_cost_items" TO "authenticated" USING (true) WITH CHECK (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all authenticated' AND tablename = 'lot_grading_results' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all authenticated" ON "public"."lot_grading_results" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all authenticated' AND tablename = 'lot_receipts' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all authenticated" ON "public"."lot_receipts" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all authenticated' AND tablename = 'packing_orders' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all authenticated" ON "public"."packing_orders" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all authenticated' AND tablename = 'packing_recipes' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all authenticated" ON "public"."packing_recipes" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all authenticated' AND tablename = 'prep_center_cost_items' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all authenticated" ON "public"."prep_center_cost_items" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all authenticated' AND tablename = 'raw_material_categories' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all authenticated" ON "public"."raw_material_categories" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all authenticated' AND tablename = 'raw_materials' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all authenticated" ON "public"."raw_materials" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all authenticated' AND tablename = 'shipment_cost_allocations' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all authenticated" ON "public"."shipment_cost_allocations" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all authenticated' AND tablename = 'shipment_cost_breakdown' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all authenticated" ON "public"."shipment_cost_breakdown" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all authenticated' AND tablename = 'shipment_cost_items' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all authenticated" ON "public"."shipment_cost_items" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all authenticated' AND tablename = 'shipment_profitability_snapshots' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all authenticated" ON "public"."shipment_profitability_snapshots" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all authenticated' AND tablename = 'shipment_recipe_snapshots' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all authenticated" ON "public"."shipment_recipe_snapshots" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all authenticated' AND tablename = 'supplier_settlements' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all authenticated" ON "public"."supplier_settlements" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all categories' AND tablename = 'product_categories' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all categories" ON "public"."product_categories" TO "authenticated" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all customers' AND tablename = 'customers' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all customers" ON "public"."customers" TO "authenticated" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all exchange_rates' AND tablename = 'exchange_rates' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all exchange_rates" ON "public"."exchange_rates" TO "authenticated" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all export_invoices' AND tablename = 'export_invoices' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all export_invoices" ON "public"."export_invoices" TO "authenticated" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all for authenticated' AND tablename = 'audit_logs' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all for authenticated" ON "public"."audit_logs" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all for authenticated' AND tablename = 'cashbox_transactions' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all for authenticated" ON "public"."cashbox_transactions" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all for authenticated' AND tablename = 'currencies' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all for authenticated" ON "public"."currencies" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all for authenticated' AND tablename = 'invoice_edits' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all for authenticated" ON "public"."invoice_edits" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all for authenticated' AND tablename = 'pricing_rules' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all for authenticated" ON "public"."pricing_rules" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all for authenticated' AND tablename = 'profiles' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all for authenticated" ON "public"."profiles" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all for authenticated' AND tablename = 'purchase_invoice_items' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all for authenticated" ON "public"."purchase_invoice_items" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all for authenticated' AND tablename = 'purchase_invoices' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all for authenticated" ON "public"."purchase_invoices" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all for authenticated' AND tablename = 'sales_invoice_items' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all for authenticated" ON "public"."sales_invoice_items" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all for authenticated' AND tablename = 'sales_invoices' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all for authenticated" ON "public"."sales_invoices" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all for authenticated' AND tablename = 'stock_batches' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all for authenticated" ON "public"."stock_batches" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all for authenticated' AND tablename = 'stock_movements' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all for authenticated" ON "public"."stock_movements" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all for authenticated' AND tablename = 'unit_conversions' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all for authenticated" ON "public"."unit_conversions" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all for authenticated' AND tablename = 'user_roles' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all for authenticated" ON "public"."user_roles" USING (true) WITH CHECK (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all for authenticated' AND tablename = 'users' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all for authenticated" ON "public"."users" USING (true) WITH CHECK (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all for authenticated' AND tablename = 'warehouses' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all for authenticated" ON "public"."warehouses" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all for authenticated users' AND tablename = 'proforma_invoice_items' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all for authenticated users" ON "public"."proforma_invoice_items" USING (("auth"."role"() = 'authenticated'::"text"));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all for authenticated users' AND tablename = 'proforma_invoices' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all for authenticated users" ON "public"."proforma_invoices" USING (("auth"."role"() = 'authenticated'::"text"));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all operations' AND tablename = 'suppliers' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all operations" ON "public"."suppliers" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow all settings' AND tablename = 'settings' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow all settings" ON "public"."settings" TO "authenticated" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow delete for authenticated users' AND tablename = 'company_addresses' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow delete for authenticated users" ON "public"."company_addresses" FOR DELETE USING (("auth"."role"() = 'authenticated'::"text"));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow delete for authenticated users' AND tablename = 'export_invoices' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow delete for authenticated users" ON "public"."export_invoices" FOR DELETE USING (("auth"."role"() = 'authenticated'::"text"));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow insert for authenticated users' AND tablename = 'company_addresses' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow insert for authenticated users" ON "public"."company_addresses" FOR INSERT WITH CHECK (("auth"."role"() = 'authenticated'::"text"));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow insert for authenticated users' AND tablename = 'export_invoices' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow insert for authenticated users" ON "public"."export_invoices" FOR INSERT WITH CHECK (("auth"."role"() = 'authenticated'::"text"));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow select for authenticated users' AND tablename = 'company_addresses' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow select for authenticated users" ON "public"."company_addresses" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow select for authenticated users' AND tablename = 'export_invoices' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow select for authenticated users" ON "public"."export_invoices" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow update for authenticated users' AND tablename = 'company_addresses' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow update for authenticated users" ON "public"."company_addresses" FOR UPDATE USING (("auth"."role"() = 'authenticated'::"text"));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Allow update for authenticated users' AND tablename = 'export_invoices' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Allow update for authenticated users" ON "public"."export_invoices" FOR UPDATE USING (("auth"."role"() = 'authenticated'::"text"));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Employee sees only his own balances' AND tablename = 'treasury_balances' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Employee sees only his own balances" ON "public"."treasury_balances" FOR SELECT USING (("treasury_id" IN ( SELECT "treasuries"."id"
   FROM "public"."treasuries"
  WHERE (("treasuries"."employee_id" = "auth"."uid"()) OR (("treasuries"."type" = 'main'::"text") AND (("auth"."jwt"() ->> 'role'::"text") = ANY (ARRAY['admin'::"text", 'owner'::"text"])))))));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Employee sees only his own transactions' AND tablename = 'treasury_transactions' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Employee sees only his own transactions" ON "public"."treasury_transactions" FOR SELECT USING (("treasury_id" IN ( SELECT "treasuries"."id"
   FROM "public"."treasuries"
  WHERE (("treasuries"."employee_id" = "auth"."uid"()) OR (("treasuries"."type" = 'main'::"text") AND (("auth"."jwt"() ->> 'role'::"text") = ANY (ARRAY['admin'::"text", 'owner'::"text"])))))));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Employee sees only his own treasury' AND tablename = 'treasuries' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Employee sees only his own treasury" ON "public"."treasuries" FOR SELECT USING ((("employee_id" = "auth"."uid"()) OR (("type" = 'main'::"text") AND (("auth"."jwt"() ->> 'role'::"text") = ANY (ARRAY['admin'::"text", 'owner'::"text"])))));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Employee sees own balance' AND tablename = 'treasury_balances' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Employee sees own balance" ON "public"."treasury_balances" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."treasuries" "t"
  WHERE (("t"."id" = "treasury_balances"."treasury_id") AND (("t"."user_id" = "auth"."uid"()) OR ("t"."type" = 'main'::"text"))))));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Plans: admin manage' AND tablename = 'subscription_plans' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Plans: admin manage" ON "public"."subscription_plans" USING ((EXISTS ( SELECT 1
   FROM "public"."users"
  WHERE (("users"."id" = "auth"."uid"()) AND ("users"."is_admin" = true)))));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Plans: read all' AND tablename = 'subscription_plans' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Plans: read all" ON "public"."subscription_plans" FOR SELECT USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Settings: admin manage' AND tablename = 'system_settings' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Settings: admin manage" ON "public"."system_settings" USING ((EXISTS ( SELECT 1
   FROM "public"."users"
  WHERE (("users"."id" = "auth"."uid"()) AND ("users"."is_admin" = true)))));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Settings: read all' AND tablename = 'system_settings' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Settings: read all" ON "public"."system_settings" FOR SELECT USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Tenant users: admin manage' AND tablename = 'tenant_users' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Tenant users: admin manage" ON "public"."tenant_users" USING ((EXISTS ( SELECT 1
   FROM "public"."users"
  WHERE (("users"."id" = "auth"."uid"()) AND ("users"."is_admin" = true)))));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Tenant users: admin read' AND tablename = 'tenant_users' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Tenant users: admin read" ON "public"."tenant_users" FOR SELECT USING (((EXISTS ( SELECT 1
   FROM "public"."users"
  WHERE (("users"."id" = "auth"."uid"()) AND ("users"."is_admin" = true)))) OR ("user_id" = "auth"."uid"())));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Tenant users: read access' AND tablename = 'tenant_users' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Tenant users: read access" ON "public"."tenant_users" FOR SELECT USING (((EXISTS ( SELECT 1
   FROM "public"."users"
  WHERE (("users"."id" = "auth"."uid"()) AND ("users"."is_admin" = true)))) OR ("user_id" = "auth"."uid"())));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Tenants: admin manage' AND tablename = 'tenants' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Tenants: admin manage" ON "public"."tenants" USING ((EXISTS ( SELECT 1
   FROM "public"."users"
  WHERE (("users"."id" = "auth"."uid"()) AND ("users"."is_admin" = true)))));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Tenants: admin read all' AND tablename = 'tenants' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Tenants: admin read all" ON "public"."tenants" FOR SELECT USING (((EXISTS ( SELECT 1
   FROM "public"."users"
  WHERE (("users"."id" = "auth"."uid"()) AND ("users"."is_admin" = true)))) OR (EXISTS ( SELECT 1
   FROM "public"."tenant_users"
  WHERE (("tenant_users"."user_id" = "auth"."uid"()) AND ("tenant_users"."tenant_id" = "tenant_users"."id"))))));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Tenants: read access' AND tablename = 'tenants' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Tenants: read access" ON "public"."tenants" FOR SELECT USING (((EXISTS ( SELECT 1
   FROM "public"."users"
  WHERE (("users"."id" = "auth"."uid"()) AND ("users"."is_admin" = true)))) OR (EXISTS ( SELECT 1
   FROM "public"."tenant_users"
  WHERE (("tenant_users"."user_id" = "auth"."uid"()) AND ("tenant_users"."tenant_id" = "tenant_users"."id"))))));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Users can delete their own profit distribution settings' AND tablename = 'profit_distribution_settings' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Users can delete their own profit distribution settings" ON "public"."profit_distribution_settings" FOR DELETE USING (("auth"."uid"() = "user_id"));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Users can insert their own profit distribution settings' AND tablename = 'profit_distribution_settings' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Users can insert their own profit distribution settings" ON "public"."profit_distribution_settings" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Users can insert transactions' AND tablename = 'treasury_transactions' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Users can insert transactions" ON "public"."treasury_transactions" FOR INSERT WITH CHECK (("created_by" = "auth"."uid"()));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Users can update their own profit distribution settings' AND tablename = 'profit_distribution_settings' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Users can update their own profit distribution settings" ON "public"."profit_distribution_settings" FOR UPDATE USING (("auth"."uid"() = "user_id"));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'Users can view their own profit distribution settings' AND tablename = 'profit_distribution_settings' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "Users can view their own profit distribution settings" ON "public"."profit_distribution_settings" FOR SELECT USING (("auth"."uid"() = "user_id"));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'allow_authenticated' AND tablename = 'transactions' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "allow_authenticated" ON "public"."transactions" TO "authenticated" USING (true) WITH CHECK (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'audit_log_insert_authenticated' AND tablename = 'fiscal_year_audit_log' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "audit_log_insert_authenticated" ON "public"."fiscal_year_audit_log" FOR INSERT WITH CHECK (("auth"."role"() = 'authenticated'::"text"));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'audit_log_select_authenticated' AND tablename = 'fiscal_year_audit_log' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "audit_log_select_authenticated" ON "public"."fiscal_year_audit_log" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'authenticated can insert treasury_transactions' AND tablename = 'treasury_transactions' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "authenticated can insert treasury_transactions" ON "public"."treasury_transactions" FOR INSERT TO "authenticated" WITH CHECK (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'authenticated can read treasury_transactions' AND tablename = 'treasury_transactions' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "authenticated can read treasury_transactions" ON "public"."treasury_transactions" FOR SELECT TO "authenticated" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'authenticated_all' AND tablename = 'accounts' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "authenticated_all" ON "public"."accounts" USING (("auth"."role"() = 'authenticated'::"text"));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'authenticated_can_insert_cheques' AND tablename = 'cheques' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "authenticated_can_insert_cheques" ON "public"."cheques" FOR INSERT TO "authenticated" WITH CHECK (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'authenticated_can_read_cheques' AND tablename = 'cheques' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "authenticated_can_read_cheques" ON "public"."cheques" FOR SELECT TO "authenticated" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'authenticated_can_update_cheques' AND tablename = 'cheques' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "authenticated_can_update_cheques" ON "public"."cheques" FOR UPDATE TO "authenticated" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'bank_account_tx_admin_all' AND tablename = 'bank_account_transactions' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "bank_account_tx_admin_all" ON "public"."bank_account_transactions" TO "authenticated" USING ("public"."_is_admin"()) WITH CHECK ("public"."_is_admin"());
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'bank_account_tx_employee_select' AND tablename = 'bank_account_transactions' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "bank_account_tx_employee_select" ON "public"."bank_account_transactions" FOR SELECT TO "authenticated" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'bank_accounts_admin_all' AND tablename = 'bank_accounts' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "bank_accounts_admin_all" ON "public"."bank_accounts" TO "authenticated" USING ("public"."_is_admin"()) WITH CHECK ("public"."_is_admin"());
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'bank_accounts_employee_select' AND tablename = 'bank_accounts' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "bank_accounts_employee_select" ON "public"."bank_accounts" FOR SELECT TO "authenticated" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'clearing_agents_full_access' AND tablename = 'clearing_agents' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "clearing_agents_full_access" ON "public"."clearing_agents" USING (true) WITH CHECK (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'customers_full_access' AND tablename = 'customers' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "customers_full_access" ON "public"."customers" USING (true) WITH CHECK (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'enable_all_for_authenticated' AND tablename = 'shipping_companies' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "enable_all_for_authenticated" ON "public"."shipping_companies" TO "authenticated" USING (true) WITH CHECK (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'expense_categories_delete' AND tablename = 'expense_categories' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "expense_categories_delete" ON "public"."expense_categories" FOR DELETE TO "authenticated" USING (( SELECT "users"."is_admin"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'expense_categories_insert' AND tablename = 'expense_categories' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "expense_categories_insert" ON "public"."expense_categories" FOR INSERT TO "authenticated" WITH CHECK (( SELECT "users"."is_admin"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'expense_categories_select' AND tablename = 'expense_categories' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "expense_categories_select" ON "public"."expense_categories" FOR SELECT TO "authenticated" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'expense_categories_update' AND tablename = 'expense_categories' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "expense_categories_update" ON "public"."expense_categories" FOR UPDATE TO "authenticated" USING (( SELECT "users"."is_admin"
   FROM "public"."users"
  WHERE ("users"."id" = "auth"."uid"())));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'fy_audit_insert_admin' AND tablename = 'fiscal_year_audit_log' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "fy_audit_insert_admin" ON "public"."fiscal_year_audit_log" FOR INSERT TO "authenticated" WITH CHECK ("public"."_is_admin"());
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'fy_audit_select_authenticated' AND tablename = 'fiscal_year_audit_log' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "fy_audit_select_authenticated" ON "public"."fiscal_year_audit_log" FOR SELECT TO "authenticated" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'fy_insert_authenticated' AND tablename = 'fiscal_years' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "fy_insert_authenticated" ON "public"."fiscal_years" FOR INSERT WITH CHECK (("auth"."role"() = 'authenticated'::"text"));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'fy_select_authenticated' AND tablename = 'fiscal_years' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "fy_select_authenticated" ON "public"."fiscal_years" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'fy_update_authenticated' AND tablename = 'fiscal_years' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "fy_update_authenticated" ON "public"."fiscal_years" FOR UPDATE USING (("auth"."role"() = 'authenticated'::"text"));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'ledger_entries_delete' AND tablename = 'ledger_entries' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "ledger_entries_delete" ON "public"."ledger_entries" FOR DELETE TO "authenticated" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'ledger_entries_insert' AND tablename = 'ledger_entries' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "ledger_entries_insert" ON "public"."ledger_entries" FOR INSERT TO "authenticated" WITH CHECK (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'ledger_entries_select' AND tablename = 'ledger_entries' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "ledger_entries_select" ON "public"."ledger_entries" FOR SELECT TO "authenticated" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'ledger_entries_update' AND tablename = 'ledger_entries' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "ledger_entries_update" ON "public"."ledger_entries" FOR UPDATE TO "authenticated" USING (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'select_own_profile' AND tablename = 'profiles' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "select_own_profile" ON "public"."profiles" FOR SELECT USING (("auth"."uid"() = "id"));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'service_role_policy' AND tablename = 'users' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "service_role_policy" ON "public"."users" USING ((("auth"."jwt"() ->> 'role'::"text") = 'service_role'::"text"));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'shipping_companies_full_access' AND tablename = 'shipping_companies' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "shipping_companies_full_access" ON "public"."shipping_companies" USING (true) WITH CHECK (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'sortings_all_auth' AND tablename = 'packing_order_sortings' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "sortings_all_auth" ON "public"."packing_order_sortings" USING (("auth"."role"() = 'authenticated'::"text")) WITH CHECK (("auth"."role"() = 'authenticated'::"text"));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'stations_full_access' AND tablename = 'stations' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "stations_full_access" ON "public"."stations" USING (true) WITH CHECK (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'suppliers_full_access' AND tablename = 'suppliers' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "suppliers_full_access" ON "public"."suppliers" USING (true) WITH CHECK (true);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'treasuries_admin_all' AND tablename = 'treasuries' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "treasuries_admin_all" ON "public"."treasuries" TO "authenticated" USING ("public"."_is_admin"()) WITH CHECK ("public"."_is_admin"());
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'treasuries_employee_select' AND tablename = 'treasuries' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "treasuries_employee_select" ON "public"."treasuries" FOR SELECT TO "authenticated" USING ((("type" = 'employee'::"text") OR ("user_id" = "auth"."uid"())));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'treasuries_owner_safe_select' AND tablename = 'treasuries' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "treasuries_owner_safe_select" ON "public"."treasuries" FOR SELECT TO "authenticated" USING (("public"."_has_owner_safe"() AND ("type" = 'main'::"text")));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'treasuries_owner_safe_update' AND tablename = 'treasuries' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "treasuries_owner_safe_update" ON "public"."treasuries" FOR UPDATE TO "authenticated" USING (("public"."_has_owner_safe"() AND ("type" = 'main'::"text"))) WITH CHECK (("public"."_has_owner_safe"() AND ("type" = 'main'::"text")));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'treasury_balances_admin_all' AND tablename = 'treasury_balances' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "treasury_balances_admin_all" ON "public"."treasury_balances" TO "authenticated" USING ("public"."_is_admin"()) WITH CHECK ("public"."_is_admin"());
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'treasury_balances_employee_select' AND tablename = 'treasury_balances' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "treasury_balances_employee_select" ON "public"."treasury_balances" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."treasuries" "t"
  WHERE (("t"."id" = "treasury_balances"."treasury_id") AND ("t"."user_id" = "auth"."uid"())))));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'treasury_balances_employee_update' AND tablename = 'treasury_balances' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "treasury_balances_employee_update" ON "public"."treasury_balances" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."treasuries" "t"
  WHERE (("t"."id" = "treasury_balances"."treasury_id") AND ("t"."user_id" = "auth"."uid"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."treasuries" "t"
  WHERE (("t"."id" = "treasury_balances"."treasury_id") AND ("t"."user_id" = "auth"."uid"())))));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'treasury_balances_owner_safe_insert' AND tablename = 'treasury_balances' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "treasury_balances_owner_safe_insert" ON "public"."treasury_balances" FOR INSERT TO "authenticated" WITH CHECK (("public"."_has_owner_safe"() AND (EXISTS ( SELECT 1
   FROM "public"."treasuries" "t"
  WHERE (("t"."id" = "treasury_balances"."treasury_id") AND ("t"."type" = 'main'::"text"))))));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'treasury_balances_owner_safe_select' AND tablename = 'treasury_balances' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "treasury_balances_owner_safe_select" ON "public"."treasury_balances" FOR SELECT TO "authenticated" USING (("public"."_has_owner_safe"() AND (EXISTS ( SELECT 1
   FROM "public"."treasuries" "t"
  WHERE (("t"."id" = "treasury_balances"."treasury_id") AND ("t"."type" = 'main'::"text"))))));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'treasury_balances_owner_safe_update' AND tablename = 'treasury_balances' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "treasury_balances_owner_safe_update" ON "public"."treasury_balances" FOR UPDATE TO "authenticated" USING (("public"."_has_owner_safe"() AND (EXISTS ( SELECT 1
   FROM "public"."treasuries" "t"
  WHERE (("t"."id" = "treasury_balances"."treasury_id") AND ("t"."type" = 'main'::"text")))))) WITH CHECK (("public"."_has_owner_safe"() AND (EXISTS ( SELECT 1
   FROM "public"."treasuries" "t"
  WHERE (("t"."id" = "treasury_balances"."treasury_id") AND ("t"."type" = 'main'::"text"))))));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'treasury_transactions_admin_all' AND tablename = 'treasury_transactions' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "treasury_transactions_admin_all" ON "public"."treasury_transactions" TO "authenticated" USING ("public"."_is_admin"()) WITH CHECK ("public"."_is_admin"());
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'treasury_transactions_employee_delete' AND tablename = 'treasury_transactions' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "treasury_transactions_employee_delete" ON "public"."treasury_transactions" FOR DELETE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."treasuries" "t"
  WHERE (("t"."id" = "treasury_transactions"."treasury_id") AND ("t"."user_id" = "auth"."uid"())))));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'treasury_transactions_employee_select' AND tablename = 'treasury_transactions' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "treasury_transactions_employee_select" ON "public"."treasury_transactions" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."treasuries" "t"
  WHERE (("t"."id" = "treasury_transactions"."treasury_id") AND ("t"."user_id" = "auth"."uid"())))));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'treasury_transactions_owner_safe_delete' AND tablename = 'treasury_transactions' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "treasury_transactions_owner_safe_delete" ON "public"."treasury_transactions" FOR DELETE TO "authenticated" USING (("public"."_has_owner_safe"() AND (EXISTS ( SELECT 1
   FROM "public"."treasuries" "t"
  WHERE (("t"."id" = "treasury_transactions"."treasury_id") AND ("t"."type" = 'main'::"text"))))));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'treasury_transactions_owner_safe_insert' AND tablename = 'treasury_transactions' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "treasury_transactions_owner_safe_insert" ON "public"."treasury_transactions" FOR INSERT TO "authenticated" WITH CHECK (("public"."_has_owner_safe"() AND (EXISTS ( SELECT 1
   FROM "public"."treasuries" "t"
  WHERE (("t"."id" = "treasury_transactions"."treasury_id") AND ("t"."type" = 'main'::"text"))))));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'treasury_transactions_owner_safe_select' AND tablename = 'treasury_transactions' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "treasury_transactions_owner_safe_select" ON "public"."treasury_transactions" FOR SELECT TO "authenticated" USING (("public"."_has_owner_safe"() AND (EXISTS ( SELECT 1
   FROM "public"."treasuries" "t"
  WHERE (("t"."id" = "treasury_transactions"."treasury_id") AND ("t"."type" = 'main'::"text"))))));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'treasury_transactions_owner_safe_update' AND tablename = 'treasury_transactions' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "treasury_transactions_owner_safe_update" ON "public"."treasury_transactions" FOR UPDATE TO "authenticated" USING (("public"."_has_owner_safe"() AND (EXISTS ( SELECT 1
   FROM "public"."treasuries" "t"
  WHERE (("t"."id" = "treasury_transactions"."treasury_id") AND ("t"."type" = 'main'::"text")))))) WITH CHECK (("public"."_has_owner_safe"() AND (EXISTS ( SELECT 1
   FROM "public"."treasuries" "t"
  WHERE (("t"."id" = "treasury_transactions"."treasury_id") AND ("t"."type" = 'main'::"text"))))));
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_policies 
        WHERE policyname = 'users_select_policy' AND tablename = 'users' AND schemaname = 'public'
    ) THEN
        CREATE POLICY "users_select_policy" ON "public"."users" FOR SELECT USING ((("auth"."uid"() = "id") OR "public"."is_admin"()));
    END IF;
END $$;

-- ==========================================
-- 5. RESTORE REALTIME PUBLICATIONS
-- ==========================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'expense_categories'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.expense_categories;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Could not add table expense_categories to publication: %', SQLERRM;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'ledger_entries'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.ledger_entries;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Could not add table ledger_entries to publication: %', SQLERRM;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'profiles'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.profiles;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Could not add table profiles to publication: %', SQLERRM;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'treasury_balances'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.treasury_balances;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Could not add table treasury_balances to publication: %', SQLERRM;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'treasury_transactions'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.treasury_transactions;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Could not add table treasury_transactions to publication: %', SQLERRM;
END $$;

-- ==========================================
-- 6. RESTORE AUTH TRIGGER
-- ==========================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_trigger 
        WHERE tgname = 'on_auth_user_created'
    ) THEN
        CREATE TRIGGER "on_auth_user_created" AFTER INSERT ON "auth"."users" FOR EACH ROW EXECUTE FUNCTION "public"."on_auth_user_created_combined"();
    END IF;
END $$;
