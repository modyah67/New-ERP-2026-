-- Baseline Schema Migration (v3)
-- Strictly ordered according to dependency requirements:

-- 1. Extensions, Types, Sequences
-- 2. Group A Functions (Used in DEFAULT / CHECK / GENERATED)
-- 3. ALL CREATE TABLE Statements (Topologically Sorted)
-- 4. Constraints (PRIMARY KEYS, UNIQUE, CHECK, FOREIGN KEYS)
-- 5. Group B Functions (Functions that read/write tables)
-- 6. Triggers
-- 7. Views & Materialized Views
-- 8. View-Dependent Functions
-- 9. Indexes

-- ==========================================
-- 1. EXTENSIONS, TYPES & SEQUENCES
-- ==========================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

--
-- Name: audit_logs_text_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."audit_logs_text_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: bank_account_transactions_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."bank_account_transactions_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: bank_accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."bank_accounts_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: cheques_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."cheques_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: entry_number_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."entry_number_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: financial_audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."financial_audit_log_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: fiscal_year_audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."fiscal_year_audit_log_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: fiscal_year_backup_metadata_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."fiscal_year_backup_metadata_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: fiscal_year_closing_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."fiscal_year_closing_entries_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: fiscal_year_closing_progress_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."fiscal_year_closing_progress_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: fiscal_year_inventory_snapshot_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."fiscal_year_inventory_snapshot_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: fiscal_years_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."fiscal_years_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: fruit_type_code_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."fruit_type_code_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: fruit_types_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."fruit_types_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: general_cost_items_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."general_cost_items_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: ledger_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."ledger_entries_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: lot_grading_results_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."lot_grading_results_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: lot_receipts_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."lot_receipts_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: packing_order_cost_items_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."packing_order_cost_items_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: packing_order_sortings_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."packing_order_sortings_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: packing_orders_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."packing_orders_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: packing_recipes_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."packing_recipes_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: prep_center_cost_items_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."prep_center_cost_items_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: raw_material_code_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."raw_material_code_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: shipment_cost_allocations_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."shipment_cost_allocations_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: shipment_cost_breakdown_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."shipment_cost_breakdown_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: shipment_cost_items_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."shipment_cost_items_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: shipment_profitability_snapshots_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."shipment_profitability_snapshots_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: shipment_recipe_snapshots_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."shipment_recipe_snapshots_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: shipping_companies_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."shipping_companies_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: stations_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."stations_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: stock_batches_id_seq1; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."stock_batches_id_seq1"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: stock_movements_id_seq1; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."stock_movements_id_seq1"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: stock_transfers_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."stock_transfers_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: supplier_settlements_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."supplier_settlements_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: treasuries_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."treasuries_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: treasury_balances_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."treasury_balances_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: treasury_transactions_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE "public"."treasury_transactions_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

-- ==========================================
-- 2. GROUP A FUNCTIONS (REFERENCED BY DEFAULT/CHECK/GENERATED)
-- ==========================================
--
-- Name: generate_raw_material_code(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."generate_raw_material_code"() RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  next_val INTEGER;
BEGIN
  next_val := nextval('public.raw_material_code_seq');
  RETURN 'FT' || LPAD(next_val::TEXT, 3, '0');
END;
$$;

-- ==========================================
-- 3. ALL CREATE TABLE STATEMENTS
-- ==========================================
--
-- Name: purchase_invoice_items_backup; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."purchase_invoice_items_backup" (
    "id" integer,
    "invoice_id" integer,
    "product_id" "uuid",
    "batch_id" "uuid",
    "quantity" numeric(15,3),
    "received_quantity" numeric(15,3),
    "unit_cost" numeric(15,4),
    "total_cost" numeric(15,2),
    "discount_percent" numeric(5,2),
    "discount_amount" numeric(15,2),
    "tax_percent" numeric(5,2),
    "tax_amount" numeric(15,2),
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);

--
-- Name: fiscal_years; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."fiscal_years" (
    "id" bigint NOT NULL,
    "year" integer NOT NULL,
    "name" "text" NOT NULL,
    "start_date" "date" NOT NULL,
    "end_date" "date" NOT NULL,
    "status" "text" DEFAULT 'OPEN'::"text" NOT NULL,
    "is_current" boolean DEFAULT false NOT NULL,
    "is_closed" boolean DEFAULT false NOT NULL,
    "closed_by" "uuid",
    "closed_at" timestamp with time zone,
    "opened_by" "uuid",
    "opened_at" timestamp with time zone,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone,
    CONSTRAINT "fiscal_years_status_check" CHECK (("status" = ANY (ARRAY['DRAFT'::"text", 'ACTIVE'::"text", 'CLOSING'::"text", 'CLOSED'::"text", 'ARCHIVED'::"text"])))
);

--
-- Name: fruit_types; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."fruit_types" (
    "id" integer NOT NULL,
    "code" "text" DEFAULT ('FRT-'::"text" || "lpad"(("nextval"('"public"."fruit_type_code_seq"'::"regclass"))::"text", 3, '0'::"text")) NOT NULL,
    "name" "text" NOT NULL,
    "icon" "text" DEFAULT 'eco'::"text" NOT NULL,
    "product_id" integer,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "color" "text" DEFAULT '#FF9800'::"text" NOT NULL,
    "currency" "text" DEFAULT 'EGP'::"text",
    "purchase_mode" "text"
);

--
-- Name: accounts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."accounts" (
    "id" integer NOT NULL,
    "account_code" character varying(50) NOT NULL,
    "name" character varying(255) NOT NULL,
    "account_name" character varying(255) NOT NULL,
    "parent_id" integer,
    "account_type" character varying(50) NOT NULL,
    "sort_order" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "balance" numeric(15,4) DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "name_ar" "text" GENERATED ALWAYS AS ("account_name") STORED,
    "code" "text" GENERATED ALWAYS AS ("account_code") STORED
);

--
-- Name: packing_order_sortings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."packing_order_sortings" (
    "id" bigint NOT NULL,
    "packing_order_id" "uuid" NOT NULL,
    "product_name" "text" NOT NULL,
    "lot_number" "text",
    "weight_kg" double precision DEFAULT 0 NOT NULL,
    "cost_per_kg" double precision DEFAULT 0 NOT NULL,
    "total_cost" double precision DEFAULT 0 NOT NULL,
    "sale_amount" double precision DEFAULT 0,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "sold_at" timestamp with time zone,
    "station_id" integer,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "remaining_weight_kg" double precision,
    "total_sale_amount" double precision DEFAULT 0,
    "treasury_names" "text",
    CONSTRAINT "packing_order_sortings_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'sold'::"text"])))
);

--
-- Name: system_settings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."system_settings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "setting_key" "text" NOT NULL,
    "setting_value" "text" NOT NULL,
    "description" "text",
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

--
-- Name: packing_recipes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."packing_recipes" (
    "id" bigint NOT NULL,
    "product_id" integer NOT NULL,
    "grade" "text" NOT NULL,
    "raw_material_id" integer NOT NULL,
    "quantity_per_carton" numeric(10,4) DEFAULT 0 NOT NULL,
    "unit" "text" DEFAULT 'قطعة'::"text" NOT NULL,
    "notes" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "material_type" "text" DEFAULT 'other_material'::"text",
    "unit_cost" numeric(15,4) DEFAULT 0 NOT NULL,
    CONSTRAINT "packing_recipes_grade_check" CHECK (("grade" = ANY (ARRAY['A'::"text", 'B'::"text", 'C'::"text"]))),
    CONSTRAINT "packing_recipes_material_type_check" CHECK (("material_type" = ANY (ARRAY['carton'::"text", 'label'::"text", 'pallet'::"text", 'corner'::"text", 'bag'::"text", 'stretch_film'::"text", 'staple'::"text", 'other_material'::"text"])))
);

--
-- Name: cash_payments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."cash_payments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "payment_number" "text" NOT NULL,
    "supplier_id" "uuid" NOT NULL,
    "amount" numeric(15,4) NOT NULL,
    "payment_method" "text" DEFAULT 'cash'::"text" NOT NULL,
    "reference_number" "text",
    "notes" "text",
    "payment_date" "date" DEFAULT CURRENT_DATE,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);

--
-- Name: shareholders; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."shareholders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "initial_balance_egp" numeric DEFAULT 0,
    "current_balance_egp" numeric DEFAULT 0,
    "initial_balance_usd" numeric DEFAULT 0,
    "current_balance_usd" numeric DEFAULT 0,
    "initial_balance_eur" numeric DEFAULT 0,
    "current_balance_eur" numeric DEFAULT 0,
    "initial_balance_gbp" numeric DEFAULT 0,
    "current_balance_gbp" numeric DEFAULT 0
);

--
-- Name: profit_distribution_settings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."profit_distribution_settings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "person1_name" "text" DEFAULT 'إسلام'::"text" NOT NULL,
    "person2_name" "text" DEFAULT 'الشخص 2'::"text" NOT NULL,
    "person3_name" "text" DEFAULT 'الشخص 3'::"text" NOT NULL,
    "percentages" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "person1_id" "uuid",
    "person2_id" "uuid",
    "person3_id" "uuid",
    "person4_for_shipment" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "currency_conversions" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL
);

--
-- Name: raw_material_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."raw_material_categories" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

--
-- Name: suppliers_backup; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."suppliers_backup" (
    "supplier_code" "text",
    "name" "text",
    "phone" "text",
    "address" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "initial_balance" numeric(15,2),
    "code" "text",
    "outstanding_balance" numeric(15,2),
    "legacy_id" "uuid",
    "id" "uuid"
);

--
-- Name: audit_logs_text; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."audit_logs_text" (
    "id" bigint NOT NULL,
    "table_name" "text" NOT NULL,
    "record_id" "text" NOT NULL,
    "action" "text" NOT NULL,
    "old_data" "jsonb",
    "new_data" "jsonb",
    "changed_fields" "text"[],
    "user_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "audit_logs_text_action_check" CHECK (("action" = ANY (ARRAY['INSERT'::"text", 'UPDATE'::"text", 'DELETE'::"text"])))
);

--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."audit_logs" (
    "id" "uuid" DEFAULT gen_random_uuid() NOT NULL,
    "table_name" "text" NOT NULL,
    "record_id" "text" NOT NULL,
    "action" "text" NOT NULL,
    "old_data" "jsonb",
    "new_data" "jsonb",
    "changed_fields" "text"[],
    "user_id" "uuid",
    "ip_address" "inet",
    "user_agent" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "audit_logs_action_check" CHECK (("action" = ANY (ARRAY['INSERT'::"text", 'UPDATE'::"text", 'DELETE'::"text"])))
);

--
-- Name: invoice_edits; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."invoice_edits" (
    "id" "uuid" DEFAULT gen_random_uuid() NOT NULL,
    "invoice_type" "text" NOT NULL,
    "invoice_id" "uuid" NOT NULL,
    "field_name" "text" NOT NULL,
    "old_value" "text",
    "new_value" "text",
    "edited_by" "uuid",
    "edited_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "reason" "text",
    CONSTRAINT "invoice_edits_invoice_type_check" CHECK (("invoice_type" = ANY (ARRAY['purchase'::"text", 'sale'::"text"])))
);

--
-- Name: cost_report_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."cost_report_categories" (
    "id" integer NOT NULL,
    "name" "text" NOT NULL,
    "is_system" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "type" character varying DEFAULT 'direct'::character varying NOT NULL
);

--
-- Name: stations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."stations" (
    "id" bigint NOT NULL,
    "code" character varying(50) NOT NULL,
    "name" character varying(255) NOT NULL,
    "description" "text",
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "type" "text" DEFAULT 'sub'::"text" NOT NULL,
    CONSTRAINT "stations_type_check" CHECK (("type" = ANY (ARRAY['main'::"text", 'sub'::"text"])))
);

--
-- Name: unit_conversions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."unit_conversions" (
    "id" "uuid" DEFAULT gen_random_uuid() NOT NULL,
    "from_unit" "text" NOT NULL,
    "to_unit" "text" NOT NULL,
    "conversion_factor" numeric(15,4) NOT NULL,
    "product_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

--
-- Name: statement_notes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."statement_notes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "entity_type" "text" NOT NULL,
    "entity_id" "text" NOT NULL,
    "reference_id" "text" NOT NULL,
    "note" "text" DEFAULT ''::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "statement_notes_entity_type_check" CHECK (("entity_type" = ANY (ARRAY['shareholder'::"text", 'supplier'::"text", 'customer'::"text", 'clearing_agent'::"text", 'shipping_company'::"text"])))
);

--
-- Name: profiles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."profiles" (
    "id" "uuid" NOT NULL,
    "full_name" "text",
    "is_admin" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_verified_at" timestamp with time zone,
    "email" "text",
    "subscription_status" "text" DEFAULT 'trial'::"text",
    "trial_ends_at" timestamp with time zone,
    "subscription_ends_at" timestamp with time zone
);

--
-- Name: clearing_agents; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."clearing_agents" (
    "id" bigint NOT NULL,
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "phone" "text" DEFAULT ''::"text",
    "city" "text" DEFAULT ''::"text",
    "country" "text" DEFAULT ''::"text",
    "gmail" "text" DEFAULT ''::"text",
    "broker_type" "text" DEFAULT 'بحري'::"text" NOT NULL,
    "contact_person_name" "text" DEFAULT ''::"text",
    "contact_person_phone" "text" DEFAULT ''::"text",
    "contact_person_email" "text" DEFAULT ''::"text",
    "initial_balance" numeric(15,2) DEFAULT 0,
    "balance" numeric(15,2) DEFAULT 0,
    "addresses" "jsonb" DEFAULT '[]'::"jsonb",
    "created_at" "text" DEFAULT ''::"text",
    "currency" "text" DEFAULT 'EGP'::"text" NOT NULL,
    "manual_adjustment" numeric(19,4) DEFAULT 0.00 NOT NULL,
    "initial_balance_snapshot" "jsonb",
    CONSTRAINT "clearing_agents_broker_type_check" CHECK (("broker_type" = ANY (ARRAY['بحري'::"text", 'جوي'::"text"])))
);

--
-- Name: ledger_entries; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."ledger_entries" (
    "id" bigint NOT NULL,
    "entity_type" "text" NOT NULL,
    "entity_id" "text" NOT NULL,
    "entry_type" "text" NOT NULL,
    "amount" numeric(12,2) NOT NULL,
    "currency" "text" DEFAULT 'EGP'::"text" NOT NULL,
    "reference_type" "text",
    "reference_id" integer,
    "description" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "reversal_of_id" bigint,
    "reference_text" "text",
    "currency_snapshot" "jsonb",
    CONSTRAINT "ledger_entries_entity_type_check" CHECK (("entity_type" = ANY (ARRAY['customer'::"text", 'supplier'::"text", 'clearing_agent'::"text", 'shipping_company'::"text", 'shareholder'::"text"]))),
    CONSTRAINT "ledger_entries_entry_type_check" CHECK (("entry_type" = ANY (ARRAY['debit'::"text", 'credit'::"text"])))
);

--
-- Name: shipping_companies; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."shipping_companies" (
    "id" bigint NOT NULL,
    "code" character varying(50) NOT NULL,
    "name" character varying(255) NOT NULL,
    "phone" character varying(50) DEFAULT ''::character varying,
    "email" character varying(255) DEFAULT ''::character varying,
    "initial_balance" numeric(19,4) DEFAULT 0.00,
    "balance" numeric(19,4) DEFAULT 0.00,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "currency" "text" DEFAULT 'EGP'::"text" NOT NULL,
    "manual_adjustment" numeric(19,4) DEFAULT 0.00 NOT NULL,
    "initial_balance_snapshot" "jsonb"
);

--
-- Name: products_backup; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."products_backup" (
    "id" integer,
    "sku" character varying(100),
    "barcode" character varying(100),
    "name" character varying(255),
    "name_ar" character varying(255),
    "name_en" character varying(255),
    "category_id" integer,
    "unit" character varying(50),
    "purchase_cost" numeric(10,4),
    "sale_price" numeric(10,4),
    "wholesale_price" numeric(10,4),
    "export_price" numeric(10,4),
    "net_weight_per_carton" numeric(10,2),
    "min_stock_level" integer,
    "is_active" boolean,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "default_carton_net_weight" numeric,
    "sort_order" integer,
    "min_stock" integer,
    "track_expiry" boolean,
    "notes" "text",
    "user_id" "uuid",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "quantity" integer,
    "supplier_name" "text"
);

--
-- Name: warehouses; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."warehouses" (
    "id" "uuid" DEFAULT gen_random_uuid() NOT NULL,
    "name" "text" NOT NULL,
    "name_en" "text",
    "address" "text",
    "city" "text",
    "country" "text" DEFAULT 'Egypt'::"text",
    "phone" "text",
    "manager_name" "text",
    "capacity" numeric(15,3) DEFAULT 0,
    "is_active" boolean DEFAULT true NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

--
-- Name: fruit_catalog; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."fruit_catalog" (
    "id" "text" NOT NULL,
    "arabic_name" "text" NOT NULL,
    "english_name" "text" NOT NULL,
    "scientific_name" "text" NOT NULL,
    "category" "text" NOT NULL,
    "origin_country" "text" NOT NULL,
    "season" "text" NOT NULL,
    "shelf_life" "text" NOT NULL,
    "storage_temperature" "text" NOT NULL,
    "hs_code" "text" NOT NULL,
    "unit" "text" DEFAULT 'kg'::"text" NOT NULL,
    "search_keywords" "text"[] DEFAULT '{}'::"text"[],
    "is_imported" boolean DEFAULT false,
    "is_seasonal" boolean DEFAULT false,
    "is_organic_supported" boolean DEFAULT false,
    "is_export_supported" boolean DEFAULT false,
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);

--
-- Name: settings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."settings" (
    "id" integer NOT NULL,
    "company_name" character varying(100) DEFAULT 'Fruity Farms'::character varying,
    "company_address" "text",
    "company_phone" character varying(50),
    "created_at" timestamp with time zone DEFAULT "now"()
);

--
-- Name: stock_batches_uuid_legacy; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."stock_batches_uuid_legacy" (
    "id" integer NOT NULL,
    "product_id" integer,
    "batch_no" character varying(100) NOT NULL,
    "initial_qty" integer DEFAULT 0,
    "current_qty" integer DEFAULT 0,
    "expiry_date" "date",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "batch_number" "text" DEFAULT ''::"text",
    "supplier_id" bigint,
    "supplier_name" "text"
);

--
-- Name: bank_accounts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."bank_accounts" (
    "id" integer NOT NULL,
    "name" "text" NOT NULL,
    "name_en" "text",
    "currency" "text" NOT NULL,
    "balance" numeric(18,2) DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

--
-- Name: packing_order_cost_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."packing_order_cost_items" (
    "id" bigint NOT NULL,
    "packing_order_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "category" "text" NOT NULL,
    "original_currency" "text" DEFAULT 'EGP'::"text" NOT NULL,
    "original_amount" numeric DEFAULT 0 NOT NULL,
    "exchange_rate" numeric DEFAULT 1.0 NOT NULL,
    "base_amount" numeric DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "currency_snapshot" "jsonb",
    CONSTRAINT "packing_order_cost_items_category_check" CHECK (("category" = ANY (ARRAY['fruit'::"text", 'material'::"text", 'logistics'::"text", 'other'::"text"])))
);

--
-- Name: subscription_plans; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."subscription_plans" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "price_egp" numeric(12,2) DEFAULT 0 NOT NULL,
    "duration_months" integer DEFAULT 1 NOT NULL,
    "max_users" integer DEFAULT 5 NOT NULL,
    "period" "text" DEFAULT 'monthly'::"text" NOT NULL,
    "features" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "subscription_plans_period_check" CHECK (("period" = ANY (ARRAY['monthly'::"text", 'yearly'::"text"])))
);

--
-- Name: product_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."product_categories" (
    "id" integer NOT NULL,
    "name" character varying(100) NOT NULL,
    "category_name" character varying(100),
    "sort_order" integer DEFAULT 0,
    "parent_id" integer,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "category_type" "text" DEFAULT 'material'::"text" NOT NULL,
    CONSTRAINT "product_categories_category_type_check" CHECK (("category_type" = ANY (ARRAY['fruit'::"text", 'material'::"text"])))
);

--
-- Name: exchange_rates; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."exchange_rates" (
    "id" integer NOT NULL,
    "currency_code" character varying(10) NOT NULL,
    "currency_name" character varying(50) NOT NULL,
    "rate_to_egp" numeric(10,4) NOT NULL,
    "sort_order" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "name_ar" character varying(100) DEFAULT ''::character varying,
    "effective_from" timestamp with time zone DEFAULT "now"(),
    "effective_to" timestamp with time zone,
    "source" "text" DEFAULT 'system'::"text",
    "updated_by" "text"
);

--
-- Name: financial_audit_log; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."financial_audit_log" (
    "id" bigint NOT NULL,
    "table_name" "text" NOT NULL,
    "record_id" "text" NOT NULL,
    "action" "text" NOT NULL,
    "old_snapshot" "jsonb",
    "new_snapshot" "jsonb",
    "changed_by" "text",
    "changed_at" timestamp with time zone DEFAULT "now"(),
    "reason" "text",
    "ip_address" "text",
    CONSTRAINT "financial_audit_log_action_check" CHECK (("action" = ANY (ARRAY['insert'::"text", 'update'::"text", 'delete'::"text"])))
);

--
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."users" (
    "id" "uuid" NOT NULL,
    "full_name" "text",
    "email" "text",
    "is_admin" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "username" "text",
    "phone" "text",
    "is_blocked" boolean DEFAULT false,
    "read_only_mode" boolean DEFAULT false,
    "subscription_active" boolean DEFAULT true
);

--
-- Name: sales_invoice_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."sales_invoice_items" (
    "id" integer NOT NULL,
    "invoice_id" integer NOT NULL,
    "finished_product_id" integer NOT NULL,
    "batch_id" "uuid",
    "quantity" numeric(15,3) DEFAULT 0 NOT NULL,
    "unit_price" numeric(15,2) DEFAULT 0 NOT NULL,
    "cost_price" numeric(15,4) DEFAULT 0,
    "total_price" numeric(15,2) DEFAULT 0 NOT NULL,
    "discount_percent" numeric(5,2) DEFAULT 0,
    "discount_amount" numeric(15,2) DEFAULT 0,
    "tax_percent" numeric(5,2) DEFAULT 0,
    "tax_amount" numeric(15,2) DEFAULT 0,
    "profit_amount" numeric(15,2) DEFAULT 0,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

--
-- Name: currencies; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."currencies" (
    "id" "uuid" DEFAULT gen_random_uuid() NOT NULL,
    "code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "name_en" "text",
    "symbol" "text" NOT NULL,
    "exchange_rate" numeric(15,6) DEFAULT 1.0 NOT NULL,
    "is_default" boolean DEFAULT false NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

--
-- Name: purchases_backup; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."purchases_backup" (
    "id" integer,
    "invoice_number" "text",
    "supplier_id" "uuid",
    "warehouse_id" "uuid",
    "currency_id" "uuid",
    "invoice_date" "date",
    "due_date" "date",
    "subtotal" numeric(15,2),
    "discount_amount" numeric(15,2),
    "tax_percent" numeric(5,2),
    "tax_amount" numeric(15,2),
    "total_amount" numeric(15,2),
    "paid_amount" numeric(15,2),
    "remaining_amount" numeric(15,2),
    "payment_status" "text",
    "status" "text",
    "received_date" "date",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "user_id" "uuid",
    "supplier_name" "text",
    "supplier_code" "text"
);

--
-- Name: proforma_invoices; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."proforma_invoices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "invoice_no" "text" NOT NULL,
    "customer_id" "text",
    "customer_name" "text" DEFAULT ''::"text",
    "customer_code" "text" DEFAULT ''::"text",
    "clearing_agent_id" "text",
    "clearing_agent_name" "text" DEFAULT ''::"text",
    "contact_person" "text",
    "country" "text" DEFAULT ''::"text",
    "destination_address" "text",
    "container_no" "text",
    "container_type" "text",
    "bl_number" "text",
    "vessel_name" "text",
    "port_of_loading" "text",
    "port_of_destination" "text",
    "transport_mode" "text" DEFAULT 'sea'::"text",
    "currency" "text",
    "payment_terms" "text",
    "terms_conditions" "text",
    "internal_notes" "text",
    "status" "text" DEFAULT 'draft'::"text",
    "total_amount" numeric DEFAULT 0,
    "invoice_date" "date",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "user_id" "text" DEFAULT ("auth"."uid"())::"text",
    "data_logger_no" "text"
);

--
-- Name: fiscal_year_audit_log; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."fiscal_year_audit_log" (
    "id" bigint NOT NULL,
    "fiscal_year_id" bigint NOT NULL,
    "action" "text" NOT NULL,
    "performed_by" "uuid",
    "performed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "old_status" "jsonb",
    "new_status" "jsonb",
    "reason" "text",
    "machine_info" "text",
    "ip_address" "inet",
    "details" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "duration_ms" bigint,
    "execution_time_ms" integer,
    "rows_affected" integer,
    "memory_usage_bytes" bigint,
    CONSTRAINT "fiscal_year_audit_log_action_check" CHECK (("action" = ANY (ARRAY['CLOSE'::"text", 'REOPEN'::"text", 'SET_CURRENT'::"text", 'VALIDATE'::"text", 'CREATE'::"text", 'UPDATE'::"text", 'ARCHIVE'::"text", 'DRAFT'::"text", 'OPENING_ENTRIES'::"text", 'REVERSE_CLOSING'::"text", 'BACKUP_CREATED'::"text", 'LOCK_ACQUIRED'::"text", 'LOCK_RELEASED'::"text", 'PROGRESS_UPDATE'::"text", 'CLOSING_FAILED'::"text"])))
);

--
-- Name: fiscal_year_backup_metadata; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."fiscal_year_backup_metadata" (
    "id" bigint NOT NULL,
    "fiscal_year_id" bigint NOT NULL,
    "backup_time" timestamp with time zone DEFAULT "now"() NOT NULL,
    "performed_by" "uuid",
    "db_version" "text",
    "migration_version" "text",
    "backup_identifier" "text" NOT NULL,
    "status" "text" DEFAULT 'CREATED'::"text" NOT NULL,
    "details" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "fiscal_year_backup_metadata_status_check" CHECK (("status" = ANY (ARRAY['CREATED'::"text", 'VERIFIED'::"text", 'FAILED'::"text"])))
);

--
-- Name: fiscal_year_closing_entries; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."fiscal_year_closing_entries" (
    "id" bigint NOT NULL,
    "fiscal_year_id" bigint NOT NULL,
    "entry_type" "text" NOT NULL,
    "account_code" "text" NOT NULL,
    "account_name" "text",
    "account_type" "text",
    "debit" numeric DEFAULT 0 NOT NULL,
    "credit" numeric DEFAULT 0 NOT NULL,
    "currency_snapshot" "jsonb",
    "entry_number" bigint,
    "transaction_id" bigint,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "fiscal_year_closing_entries_entry_type_check" CHECK (("entry_type" = ANY (ARRAY['CLOSE_REVENUE'::"text", 'CLOSE_EXPENSE'::"text", 'TRANSFER_RETAINED'::"text", 'OPENING_BALANCE'::"text", 'REVERSE_CLOSING'::"text"])))
);

--
-- Name: fiscal_year_closing_lock; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."fiscal_year_closing_lock" (
    "id" integer DEFAULT 1 NOT NULL,
    "locked_by" "uuid",
    "locked_at" timestamp with time zone,
    "fiscal_year_id" bigint,
    "released_at" timestamp with time zone,
    "status" "text" DEFAULT 'FREE'::"text" NOT NULL,
    CONSTRAINT "fiscal_year_closing_lock_status_check" CHECK (("status" = ANY (ARRAY['FREE'::"text", 'LOCKED'::"text", 'RECOVERING'::"text"])))
);

--
-- Name: fiscal_year_closing_progress; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."fiscal_year_closing_progress" (
    "id" bigint NOT NULL,
    "fiscal_year_id" bigint NOT NULL,
    "status" "text" DEFAULT 'PENDING'::"text" NOT NULL,
    "progress_pct" integer DEFAULT 0 NOT NULL,
    "current_step" "text",
    "started_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "completed_at" timestamp with time zone,
    "performed_by" "uuid",
    "error_message" "text",
    "details" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "fiscal_year_closing_progress_progress_pct_check" CHECK ((("progress_pct" >= 0) AND ("progress_pct" <= 100))),
    CONSTRAINT "fiscal_year_closing_progress_status_check" CHECK (("status" = ANY (ARRAY['PENDING'::"text", 'VALIDATING'::"text", 'CLOSING_GL'::"text", 'CLOSING_INVENTORY'::"text", 'GENERATING_OPENING'::"text", 'WRITING_AUDIT'::"text", 'FINALIZING'::"text", 'COMPLETED'::"text", 'FAILED'::"text", 'ROLLED_BACK'::"text"])))
);

--
-- Name: fiscal_year_inventory_snapshot; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."fiscal_year_inventory_snapshot" (
    "id" bigint NOT NULL,
    "fiscal_year_id" bigint NOT NULL,
    "snapshot_type" "text" NOT NULL,
    "product_id" bigint,
    "warehouse_id" bigint,
    "batch_id" bigint,
    "quantity" numeric DEFAULT 0 NOT NULL,
    "unit_cost" numeric DEFAULT 0 NOT NULL,
    "total_cost" numeric DEFAULT 0 NOT NULL,
    "cost_method" "text",
    "currency_snapshot" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "fiscal_year_inventory_snapshot_cost_method_check" CHECK (("cost_method" = ANY (ARRAY['FIFO'::"text", 'WAC'::"text"]))),
    CONSTRAINT "fiscal_year_inventory_snapshot_snapshot_type_check" CHECK (("snapshot_type" = ANY (ARRAY['CLOSING'::"text", 'OPENING'::"text"])))
);

--
-- Name: customers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."customers" (
    "id" integer NOT NULL,
    "name" character varying(255) NOT NULL,
    "phone" character varying(50),
    "company_type" character varying(50) DEFAULT 'export'::character varying,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "balance" numeric(12,2) DEFAULT 0.00,
    "code" "text",
    "company_name" "text",
    "gmail" "text",
    "vat_no" "text",
    "eori_no" "text",
    "contact_person_name" "text",
    "contact_person_phone" "text",
    "contact_person_email" "text",
    "contact_person" "text",
    "city" "text",
    "country" "text",
    "initial_balance" numeric(15,2) DEFAULT 0.00,
    "addresses" "jsonb" DEFAULT '[]'::"jsonb",
    "account_id" integer,
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "currency" "text" DEFAULT 'EGP'::"text" NOT NULL,
    "initial_balance_snapshot" "jsonb"
);

--
-- Name: suppliers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."suppliers" (
    "supplier_code" "text" NOT NULL,
    "name" "text" NOT NULL,
    "phone" "text",
    "address" "text",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "initial_balance" numeric(15,2) DEFAULT 0.00,
    "code" "text",
    "outstanding_balance" numeric(15,2) DEFAULT 0,
    "legacy_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "account_id" integer,
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "currency" "text" DEFAULT 'EGP'::"text" NOT NULL,
    "initial_balance_snapshot" "jsonb"
);

--
-- Name: transactions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."transactions" (
    "id" integer NOT NULL,
    "account_id" integer,
    "debit" numeric(15,4) DEFAULT 0.0,
    "credit" numeric(15,4) DEFAULT 0.0,
    "description" "text",
    "date" timestamp with time zone DEFAULT "now"(),
    "created_at" timestamp with time zone DEFAULT "now"(),
    "supplier_code" "text",
    "supplier_id" "uuid",
    "purchase_id" "uuid",
    "entry_number" "text",
    "amount" numeric(15,4) DEFAULT 0,
    "transaction_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "currency_snapshot" "jsonb",
    "purchase_invoice_ref" integer
);

--
-- Name: general_cost_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."general_cost_items" (
    "id" integer NOT NULL,
    "name" character varying NOT NULL,
    "amount" numeric NOT NULL,
    "cost_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "report_category_id" integer,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "general_cost_items_amount_check" CHECK (("amount" >= (0)::numeric))
);

--
-- Name: station_products; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."station_products" (
    "id" bigint NOT NULL,
    "station_id" bigint NOT NULL,
    "product_name" "text" NOT NULL,
    "product_code" "text" DEFAULT ''::"text" NOT NULL,
    "quantity" numeric(15,3) DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "fruit_type_id" integer,
    "unit" "text" DEFAULT 'kg'::"text" NOT NULL
);

--
-- Name: stock_transfers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."stock_transfers" (
    "id" bigint NOT NULL,
    "from_station_id" bigint,
    "to_station_id" bigint,
    "product_code" character varying(100) NOT NULL,
    "product_name" character varying(255) NOT NULL,
    "quantity" numeric(19,4) NOT NULL,
    "notes" "text",
    "transferred_by" character varying(255) DEFAULT ''::character varying,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "stock_transfers_check" CHECK (("from_station_id" <> "to_station_id")),
    CONSTRAINT "stock_transfers_quantity_check" CHECK (("quantity" > (0)::numeric))
);

--
-- Name: stock_movements_uuid_legacy; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."stock_movements_uuid_legacy" (
    "id" integer NOT NULL,
    "product_id" integer,
    "batch_id" integer,
    "movement_type" character varying(20),
    "quantity" integer NOT NULL,
    "date" timestamp with time zone DEFAULT "now"(),
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "stock_movements_movement_type_check" CHECK ((("movement_type")::"text" = ANY ((ARRAY['IN'::character varying, 'OUT'::character varying])::"text"[])))
);

--
-- Name: bank_account_transactions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."bank_account_transactions" (
    "id" integer NOT NULL,
    "bank_account_id" integer NOT NULL,
    "type" "text" NOT NULL,
    "amount" numeric(18,2) NOT NULL,
    "balance_before" numeric(18,2) NOT NULL,
    "balance_after" numeric(18,2) NOT NULL,
    "description" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "entity_type" "text",
    "entity_id" "text",
    "counterparty_name" "text",
    "currency_snapshot" "jsonb",
    CONSTRAINT "bank_account_transactions_amount_check" CHECK (("amount" > (0)::numeric))
);

--
-- Name: tenants; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."tenants" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "email" "text",
    "plan_id" "uuid",
    "is_active" boolean DEFAULT true NOT NULL,
    "is_read_only" boolean DEFAULT false NOT NULL,
    "max_users" integer DEFAULT 5 NOT NULL,
    "current_users" integer DEFAULT 0 NOT NULL,
    "subscription_expires_at" timestamp with time zone,
    "tenant_type" "text" DEFAULT 'erp'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "tenants_tenant_type_check" CHECK (("tenant_type" = ANY (ARRAY['erp'::"text", 'pharmacy'::"text"])))
);

--
-- Name: expense_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."expense_categories" (
    "id" integer NOT NULL,
    "name" "text" NOT NULL,
    "color" "text" DEFAULT '#10B981'::"text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "currency" "text" DEFAULT 'EGP'::"text"
);

--
-- Name: treasuries; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."treasuries" (
    "id" bigint NOT NULL,
    "name" "text" NOT NULL,
    "type" "text" NOT NULL,
    "employee_id" "uuid",
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "user_id" "uuid",
    "notes" "text",
    "account_id" integer,
    "approval_status" "text" DEFAULT 'draft'::"text" NOT NULL,
    CONSTRAINT "treasuries_approval_status_check" CHECK (("approval_status" = ANY (ARRAY['draft'::"text", 'pending'::"text", 'approved'::"text", 'rejected'::"text"]))),
    CONSTRAINT "treasuries_type_check" CHECK (("type" = ANY (ARRAY['main'::"text", 'employee'::"text"])))
);

--
-- Name: user_roles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."user_roles" (
    "id" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "user_id" "uuid",
    "allowed_pages" "jsonb" DEFAULT '[]'::"jsonb",
    "edit_time_limit_hours" integer DEFAULT 24,
    "role" "text" DEFAULT 'sales'::"text" NOT NULL,
    "can_edit_invoice_prices" boolean DEFAULT false,
    "can_edit_after_save" boolean DEFAULT false,
    "can_edit_quantity" boolean DEFAULT false,
    "can_edit_discounts" boolean DEFAULT false,
    "can_delete_invoices" boolean DEFAULT false,
    "can_manage_products" boolean DEFAULT false,
    "can_manage_users" boolean DEFAULT false,
    "can_view_reports" boolean DEFAULT false,
    "can_manage_exports" boolean DEFAULT false,
    CONSTRAINT "user_roles_role_check" CHECK (("role" = ANY (ARRAY['owner'::"text", 'manager'::"text", 'accountant'::"text", 'warehouse'::"text", 'sales'::"text", 'cashier'::"text", 'employee'::"text"])))
);

--
-- Name: cashbox_transactions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."cashbox_transactions" (
    "id" "uuid" DEFAULT gen_random_uuid() NOT NULL,
    "transaction_type" "text" NOT NULL,
    "amount" numeric(15,2) NOT NULL,
    "currency_id" "uuid",
    "reference_type" "text",
    "reference_id" "uuid",
    "description" "text",
    "payment_method" "text" DEFAULT 'cash'::"text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_id" "uuid",
    CONSTRAINT "cashbox_transactions_payment_method_check" CHECK (("payment_method" = ANY (ARRAY['cash'::"text", 'bank_transfer'::"text", 'cheque'::"text", 'card'::"text", 'mobile'::"text"]))),
    CONSTRAINT "cashbox_transactions_transaction_type_check" CHECK (("transaction_type" = ANY (ARRAY['income'::"text", 'expense'::"text", 'transfer'::"text", 'refund'::"text"])))
);

--
-- Name: pricing_rules; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."pricing_rules" (
    "id" "uuid" DEFAULT gen_random_uuid() NOT NULL,
    "name" "text" NOT NULL,
    "finished_product_id" "uuid",
    "category_id" "uuid",
    "customer_type" "text",
    "min_quantity" numeric(15,3) DEFAULT 0,
    "max_quantity" numeric(15,3),
    "price_override" numeric(15,2),
    "discount_percent" numeric(5,2) DEFAULT 0,
    "discount_amount" numeric(15,2) DEFAULT 0,
    "currency_id" "uuid",
    "valid_from" timestamp with time zone,
    "valid_until" timestamp with time zone,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "pricing_rules_customer_type_check" CHECK (("customer_type" = ANY (ARRAY['retail'::"text", 'wholesale'::"text", 'export'::"text", 'government'::"text"])))
);

--
-- Name: proforma_invoice_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."proforma_invoice_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "proforma_invoice_id" "uuid" NOT NULL,
    "product_name" "text" NOT NULL,
    "quantity" numeric DEFAULT 0,
    "price_per_carton" numeric DEFAULT 0,
    "net_weight" numeric DEFAULT 0,
    "gross_weight" numeric DEFAULT 0,
    "pallets_count" integer DEFAULT 0,
    "total_amount" numeric DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"()
);

--
-- Name: company_addresses; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."company_addresses" (
    "id" integer NOT NULL,
    "customer_id" integer,
    "governorate_id" integer,
    "address_details" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "company_id" integer DEFAULT 0,
    "company_type" "text",
    CONSTRAINT "company_addresses_company_type_check" CHECK (("company_type" = ANY (ARRAY['customer'::"text", 'supplier'::"text"])))
);

--
-- Name: customer_addresses; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."customer_addresses" (
    "id" integer NOT NULL,
    "customer_id" integer,
    "title" "text",
    "city" "text",
    "country" "text",
    "address_line" "text",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);

--
-- Name: export_invoices; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."export_invoices" (
    "id" integer NOT NULL,
    "invoice_no" character varying(100) NOT NULL,
    "customer_id" integer,
    "currency_code" character varying(10) DEFAULT 'EGP'::character varying,
    "total_cartons" integer DEFAULT 0,
    "export_price_per_carton" numeric(10,4) DEFAULT 0.0,
    "purchase_cost_per_carton" numeric(10,4) DEFAULT 0.0,
    "total_amount_foreign" numeric(15,4) DEFAULT 0.0,
    "exchange_rate_used" numeric(10,4) DEFAULT 1.0,
    "total_amount_egp" numeric(15,4) DEFAULT 0.0,
    "total_cost_egp" numeric(15,4) DEFAULT 0.0,
    "net_profit_egp" numeric(15,4) DEFAULT 0.0,
    "date" "date" DEFAULT CURRENT_DATE,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);

--
-- Name: export_shipments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."export_shipments" (
    "id" integer NOT NULL,
    "shipment_no" character varying(100) NOT NULL,
    "invoice_id" integer,
    "shipping_type" character varying(20),
    "vessel_or_flight_name" character varying(100),
    "container_no" character varying(100),
    "booking_no" character varying(100),
    "created_at" timestamp with time zone DEFAULT "now"(),
    "customer_id" integer,
    "shipment_number" "text",
    "shipping_method" "text",
    "container_number" "text",
    "container_type" "text",
    "bl_number" "text",
    "vessel_name" "text",
    "port_of_loading" "text",
    "port_of_destination" "text",
    "shipment_date" "date",
    "status" "text",
    "customer_name" "text" DEFAULT ''::"text",
    "customer_code" "text" DEFAULT ''::"text",
    "invoice_number" "text" DEFAULT ''::"text",
    "contact_person" "text",
    "destination_address" "text",
    "data_logger_no" "text",
    "transport_mode" "text" DEFAULT 'sea'::"text" NOT NULL,
    "incoterm" "text" DEFAULT 'FOB'::"text",
    "currency" "text" DEFAULT 'EGP'::"text",
    "terms_conditions" "text",
    "internal_notes" "text",
    "shipping_company" "text",
    "carton_count" integer DEFAULT 0,
    "net_weight" numeric(15,3) DEFAULT 0,
    "gross_weight" numeric(15,3) DEFAULT 0,
    "pallet_count" integer DEFAULT 0,
    "payment_terms" "text",
    "destination_country" "text",
    "clearing_agent_id" integer,
    "clearing_agent_name" "text" DEFAULT ''::"text",
    "freight_cost" numeric(15,2) DEFAULT 0,
    "insurance_cost" numeric(15,2) DEFAULT 0,
    "clearance_cost" numeric(15,2) DEFAULT 0,
    "other_costs" numeric(15,2) DEFAULT 0,
    "total_landed_cost" numeric(15,2) DEFAULT 0,
    "cost_per_carton" numeric(15,4) DEFAULT 0,
    "export_price_per_carton" numeric(15,4) DEFAULT 0,
    "currency_code" "text" DEFAULT 'USD'::"text",
    "exchange_rate" numeric(10,4) DEFAULT 1,
    "total_revenue_foreign" numeric(15,2) DEFAULT 0,
    "total_revenue_egp" numeric(15,2) DEFAULT 0,
    "net_profit_egp" numeric(15,2) DEFAULT 0,
    "total_fruit_cost" numeric(15,2) DEFAULT 0,
    "total_packing_material_cost" numeric(15,2) DEFAULT 0,
    "gross_profit" numeric(15,2) DEFAULT 0,
    "net_profit" numeric(15,2) DEFAULT 0,
    "packing_recipe_id" bigint,
    "country_of_origin" "text" DEFAULT 'Egypt'::"text",
    "discount_amount" numeric DEFAULT 0,
    "discount_reason" "text",
    "applied_discount_amount" numeric DEFAULT 0,
    "needs_profit_redistribution" boolean DEFAULT false,
    "currency_snapshot" "jsonb",
    CONSTRAINT "export_shipments_currency_check" CHECK (("currency" = ANY (ARRAY['EGP'::"text", 'USD'::"text", 'EUR'::"text", 'GBP'::"text"]))),
    CONSTRAINT "export_shipments_shipping_type_check" CHECK ((("shipping_type")::"text" = ANY ((ARRAY['Sea'::character varying, 'Air'::character varying])::"text"[]))),
    CONSTRAINT "export_shipments_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'booked'::"text", 'loaded'::"text", 'sailed'::"text", 'arrived'::"text", 'completed'::"text", 'cancelled'::"text", 'preparing'::"text", 'ready'::"text", 'shipped'::"text", 'in_transit'::"text", 'delivered'::"text"])))
);

--
-- Name: sales_invoices; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."sales_invoices" (
    "id" integer NOT NULL,
    "invoice_number" "text" NOT NULL,
    "customer_id" integer NOT NULL,
    "currency_id" "uuid",
    "invoice_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "due_date" "date",
    "subtotal" numeric(15,2) DEFAULT 0 NOT NULL,
    "discount_amount" numeric(15,2) DEFAULT 0,
    "tax_percent" numeric(5,2) DEFAULT 0,
    "tax_amount" numeric(15,2) DEFAULT 0,
    "total_amount" numeric(15,2) DEFAULT 0 NOT NULL,
    "paid_amount" numeric(15,2) DEFAULT 0,
    "remaining_amount" numeric(15,2) DEFAULT 0,
    "payment_status" "text" DEFAULT 'unpaid'::"text" NOT NULL,
    "sale_type" "text" DEFAULT 'retail'::"text" NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "delivery_date" "date",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_id" "uuid",
    CONSTRAINT "sales_invoices_payment_status_check" CHECK (("payment_status" = ANY (ARRAY['unpaid'::"text", 'partial'::"text", 'paid'::"text", 'overpaid'::"text"]))),
    CONSTRAINT "sales_invoices_sale_type_check" CHECK (("sale_type" = ANY (ARRAY['retail'::"text", 'wholesale'::"text", 'export'::"text"]))),
    CONSTRAINT "sales_invoices_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'confirmed'::"text", 'delivered'::"text", 'cancelled'::"text"])))
);

--
-- Name: purchase_invoices; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."purchase_invoices" (
    "id" integer NOT NULL,
    "invoice_number" "text" NOT NULL,
    "supplier_id" "uuid",
    "warehouse_id" "uuid",
    "currency_id" "uuid",
    "invoice_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "due_date" "date",
    "subtotal" numeric(15,2) DEFAULT 0 NOT NULL,
    "discount_amount" numeric(15,2) DEFAULT 0,
    "tax_percent" numeric(5,2) DEFAULT 0,
    "tax_amount" numeric(15,2) DEFAULT 0,
    "total_amount" numeric(15,2) DEFAULT 0 NOT NULL,
    "paid_amount" numeric(15,2) DEFAULT 0,
    "remaining_amount" numeric(15,2) DEFAULT 0,
    "payment_status" "text" DEFAULT 'unpaid'::"text" NOT NULL,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "received_date" "date",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_id" "uuid",
    "currency" "text" DEFAULT 'EGP'::"text",
    "currency_snapshot" "jsonb",
    "payment_treasury_id" "text",
    "payment_source_type" "text" DEFAULT 'treasury'::"text",
    "payment_bank_account_id" integer,
    CONSTRAINT "purchase_invoices_payment_status_check" CHECK (("payment_status" = ANY (ARRAY['unpaid'::"text", 'partial'::"text", 'paid'::"text", 'overpaid'::"text"]))),
    CONSTRAINT "purchase_invoices_status_check" CHECK (("status" = ANY (ARRAY['draft'::"text", 'confirmed'::"text", 'received'::"text", 'cancelled'::"text"])))
);

--
-- Name: raw_materials; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."raw_materials" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text" DEFAULT "public"."generate_raw_material_code"() NOT NULL,
    "name" "text" NOT NULL,
    "unit" "text" DEFAULT 'piece'::"text" NOT NULL,
    "quantity" double precision DEFAULT 0 NOT NULL,
    "default_purchase_price" double precision DEFAULT 0 NOT NULL,
    "minimum_stock" double precision DEFAULT 0 NOT NULL,
    "default_supplier_id" "uuid",
    "is_active" boolean DEFAULT true NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "category_id" "uuid",
    "initial_quantity" double precision DEFAULT 0 NOT NULL,
    "initial_avg_price" double precision DEFAULT 0 NOT NULL,
    "currency" "text" DEFAULT 'EGP'::"text" NOT NULL,
    "exchange_rate" numeric(10,4) DEFAULT 1.0 NOT NULL,
    "last_purchase_price_snapshot" "jsonb"
);

--
-- Name: tenant_users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."tenant_users" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tenant_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "text" DEFAULT 'user'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "tenant_users_role_check" CHECK (("role" = ANY (ARRAY['owner'::"text", 'admin'::"text", 'user'::"text"])))
);

--
-- Name: cheques; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."cheques" (
    "id" bigint NOT NULL,
    "cheque_number" "text" NOT NULL,
    "type" "text" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "amount" numeric(18,2) NOT NULL,
    "currency" "text" NOT NULL,
    "issue_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "due_date" "date" NOT NULL,
    "counterparty_type" "text",
    "counterparty_id" bigint,
    "notes" "text",
    "receipt_type" "text",
    "created_by" "uuid" NOT NULL,
    "cleared_at" timestamp with time zone,
    "cancelled_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "supplier_id" "uuid",
    "clearing_agent_id" bigint,
    "shipping_company_id" bigint,
    "category_id" integer,
    "shareholder_id" "uuid",
    "currency_snapshot" "jsonb",
    CONSTRAINT "cheques_counterparty_type_check" CHECK (("counterparty_type" = ANY (ARRAY['customer'::"text", 'supplier'::"text", 'clearing_agent'::"text", 'shipping_company'::"text", 'treasury'::"text", 'shareholder'::"text"]))),
    CONSTRAINT "cheques_currency_check" CHECK (("currency" = ANY (ARRAY['EGP'::"text", 'USD'::"text", 'EUR'::"text", 'GBP'::"text"]))),
    CONSTRAINT "cheques_receipt_type_check" CHECK (("receipt_type" = ANY (ARRAY['cash'::"text", 'e_wallet'::"text", 'instapay'::"text", 'cheque'::"text"]))),
    CONSTRAINT "cheques_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'cleared'::"text", 'cancelled'::"text"]))),
    CONSTRAINT "cheques_type_check" CHECK (("type" = ANY (ARRAY['outgoing'::"text", 'incoming'::"text"])))
);

--
-- Name: treasury_balances; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."treasury_balances" (
    "id" bigint NOT NULL,
    "treasury_id" bigint,
    "currency" "text" NOT NULL,
    "balance" numeric(15,2) DEFAULT 0.00,
    "account_id" integer,
    CONSTRAINT "treasury_balances_balance_check" CHECK (("balance" >= (0)::numeric)),
    CONSTRAINT "treasury_balances_currency_check" CHECK (("currency" = ANY (ARRAY['EGP'::"text", 'USD'::"text", 'EUR'::"text", 'GBP'::"text"])))
);

--
-- Name: treasury_transactions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."treasury_transactions" (
    "id" bigint NOT NULL,
    "treasury_id" bigint,
    "from_treasury_id" bigint,
    "to_treasury_id" bigint,
    "amount" numeric(15,2) NOT NULL,
    "currency" "text" NOT NULL,
    "type" "text" NOT NULL,
    "description" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "transaction_type" "text",
    "balance_before" numeric(15,2),
    "balance_after" numeric(15,2),
    "related_treasury_id" bigint,
    "category_id" integer,
    "customer_id" integer,
    "supplier_id" "uuid",
    "clearing_agent_id" bigint,
    "shipping_company_id" bigint,
    "shareholder_id" "uuid",
    "currency_snapshot" "jsonb",
    CONSTRAINT "chk_tx_customer_supplier_mutex" CHECK ((NOT (("customer_id" IS NOT NULL) AND ("supplier_id" IS NOT NULL)))),
    CONSTRAINT "treasury_transactions_currency_check" CHECK (("currency" = ANY (ARRAY['EGP'::"text", 'USD'::"text", 'EUR'::"text", 'GBP'::"text"])))
);

--
-- Name: prep_center_cost_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."prep_center_cost_items" (
    "id" bigint NOT NULL,
    "shipment_id" integer NOT NULL,
    "cost_type" "text" NOT NULL,
    "description" "text" DEFAULT ''::"text" NOT NULL,
    "qty" numeric(15,3) DEFAULT 1 NOT NULL,
    "unit_price" numeric(15,4) DEFAULT 0 NOT NULL,
    "total_cost" numeric(15,2) GENERATED ALWAYS AS (("qty" * "unit_price")) STORED,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "prep_center_cost_items_cost_type_check" CHECK (("cost_type" = ANY (ARRAY['PACKAGING'::"text", 'LABOR'::"text", 'DIESEL'::"text", 'AGRICULTURE'::"text", 'TRANSPORT'::"text", 'COOLING'::"text", 'LABELS'::"text", 'STICKERS'::"text", 'OTHER'::"text"])))
);

--
-- Name: shareholder_profit_distributions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."shareholder_profit_distributions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "shipment_id" integer NOT NULL,
    "shareholder_id" "uuid" NOT NULL,
    "person_index" integer NOT NULL,
    "percentage" numeric NOT NULL,
    "amount_egp" numeric NOT NULL,
    "currency" character varying(3) DEFAULT 'EGP'::character varying NOT NULL,
    "converted_amount" numeric,
    "rate_to_egp" numeric,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "created_by" "uuid",
    "currency_snapshot" "jsonb"
);

--
-- Name: shipment_cost_breakdown; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."shipment_cost_breakdown" (
    "id" bigint NOT NULL,
    "shipment_id" integer NOT NULL,
    "cost_type" "text" NOT NULL,
    "cost_category" "text",
    "item_name" "text" NOT NULL,
    "quantity" numeric(15,3) DEFAULT 0 NOT NULL,
    "unit_cost" numeric(15,4) DEFAULT 0 NOT NULL,
    "total_cost" numeric(15,2) DEFAULT 0 NOT NULL,
    "currency" "text" DEFAULT 'EGP'::"text" NOT NULL,
    "notes" "text",
    "sort_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "product_id" integer,
    "supplier" "text",
    "fruit_cost_per_kg" numeric(15,4) DEFAULT 0,
    "base_amount" numeric,
    "original_currency" "text",
    "exchange_rate" numeric DEFAULT 1.0,
    "currency_snapshot" "jsonb",
    CONSTRAINT "shipment_cost_breakdown_cost_type_check" CHECK (("cost_type" = ANY (ARRAY['fruit'::"text", 'packing_material'::"text", 'logistics'::"text", 'export_cost'::"text", 'admin'::"text", 'other'::"text"])))
);

--
-- Name: shipment_cost_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."shipment_cost_items" (
    "id" bigint NOT NULL,
    "shipment_id" integer NOT NULL,
    "category" "text" DEFAULT 'other'::"text" NOT NULL,
    "description" "text" NOT NULL,
    "quantity" numeric(15,3) DEFAULT 1 NOT NULL,
    "unit_price" numeric(15,4) DEFAULT 0 NOT NULL,
    "total_price" numeric(15,2) GENERATED ALWAYS AS (("quantity" * "unit_price")) STORED,
    "sort_order" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "product_id" integer,
    "vendor_type" "text",
    "vendor_id" integer,
    "report_category_id" integer,
    "exchange_rate" numeric(12,6) DEFAULT 1.0 NOT NULL,
    "base_amount" numeric,
    "original_currency" "text",
    "currency_snapshot" "jsonb",
    "supplier_id" "text",
    "supplier_currency" "text",
    CONSTRAINT "shipment_cost_items_vendor_type_check" CHECK (("vendor_type" = ANY (ARRAY['shipping_company'::"text", 'clearing_agent'::"text"])))
);

--
-- Name: shipment_profitability_snapshots; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."shipment_profitability_snapshots" (
    "id" bigint NOT NULL,
    "shipment_id" integer NOT NULL,
    "shipment_no" "text" NOT NULL,
    "revenue_foreign" numeric(15,2) DEFAULT 0 NOT NULL,
    "revenue_local" numeric(15,2) DEFAULT 0 NOT NULL,
    "fruit_cost" numeric(15,2) DEFAULT 0 NOT NULL,
    "packing_cost" numeric(15,2) DEFAULT 0 NOT NULL,
    "logistics_cost" numeric(15,2) DEFAULT 0 NOT NULL,
    "administrative_cost" numeric(15,2) DEFAULT 0 NOT NULL,
    "other_cost" numeric(15,2) DEFAULT 0 NOT NULL,
    "total_cost" numeric(15,2) DEFAULT 0 NOT NULL,
    "gross_profit" numeric(15,2) DEFAULT 0 NOT NULL,
    "net_profit" numeric(15,2) DEFAULT 0 NOT NULL,
    "gross_margin" numeric(10,2) DEFAULT 0 NOT NULL,
    "net_margin" numeric(10,2) DEFAULT 0 NOT NULL,
    "cost_per_carton" numeric(15,4) DEFAULT 0 NOT NULL,
    "cost_per_kg" numeric(15,4) DEFAULT 0 NOT NULL,
    "cost_per_pallet" numeric(15,4) DEFAULT 0 NOT NULL,
    "cartons" integer DEFAULT 0 NOT NULL,
    "net_weight" numeric(15,3) DEFAULT 0 NOT NULL,
    "pallets" integer DEFAULT 0 NOT NULL,
    "exchange_rate" numeric(15,6) DEFAULT 1 NOT NULL,
    "currency_code" "text" DEFAULT 'USD'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid"
);

--
-- Name: shipment_recipe_snapshots; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."shipment_recipe_snapshots" (
    "id" bigint NOT NULL,
    "shipment_id" integer NOT NULL,
    "packing_recipe_id" bigint,
    "recipe_name" "text",
    "product_id" integer,
    "grade" "text",
    "recipe_version" integer DEFAULT 1,
    "material_id" integer,
    "material_name" "text",
    "unit" "text",
    "quantity_per_carton" numeric(15,4),
    "unit_cost" numeric(15,4),
    "total_quantity" numeric(15,4),
    "total_cost" numeric(15,2),
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

--
-- Name: supplier_settlements; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."supplier_settlements" (
    "id" bigint NOT NULL,
    "shipment_id" integer NOT NULL,
    "supplier_id" "uuid" NOT NULL,
    "product_id" integer NOT NULL,
    "grade" "text" DEFAULT 'A'::"text" NOT NULL,
    "weight_kg" numeric(15,3) DEFAULT 0 NOT NULL,
    "unit_price" numeric(15,4) DEFAULT 0 NOT NULL,
    "total_amount" numeric(15,2) GENERATED ALWAYS AS (("weight_kg" * "unit_price")) STORED,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "supplier_settlements_grade_check" CHECK (("grade" = ANY (ARRAY['A'::"text", 'B'::"text", 'C'::"text", 'waste'::"text"])))
);

--
-- Name: purchase_invoice_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."purchase_invoice_items" (
    "id" integer NOT NULL,
    "invoice_id" integer NOT NULL,
    "batch_id" "uuid",
    "quantity" numeric(15,3) DEFAULT 0 NOT NULL,
    "received_quantity" numeric(15,3) DEFAULT 0,
    "unit_cost" numeric(15,4) DEFAULT 0 NOT NULL,
    "total_cost" numeric(15,2) DEFAULT 0 NOT NULL,
    "discount_percent" numeric(5,2) DEFAULT 0,
    "discount_amount" numeric(15,2) DEFAULT 0,
    "tax_percent" numeric(5,2) DEFAULT 0,
    "tax_amount" numeric(15,2) DEFAULT 0,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "raw_material_id" "uuid",
    "remaining_quantity" numeric NOT NULL,
    "exchange_rate" numeric DEFAULT 1.0 NOT NULL,
    "currency_snapshot" "jsonb",
    "station_id" bigint,
    CONSTRAINT "chk_purchase_items_remaining_non_negative" CHECK (("remaining_quantity" >= (0)::numeric))
);

--
-- Name: station_product_batches; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."station_product_batches" (
    "id" bigint NOT NULL,
    "station_id" bigint NOT NULL,
    "product_name" "text" NOT NULL,
    "product_code" "text" DEFAULT ''::"text" NOT NULL,
    "quantity" numeric(15,3) NOT NULL,
    "remaining_quantity" numeric(15,3) NOT NULL,
    "unit_cost" double precision DEFAULT 0 NOT NULL,
    "source_type" "text" DEFAULT 'purchase'::"text" NOT NULL,
    "source_date" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "supplier_name" "text" DEFAULT ''::"text",
    "source_station_name" "text" DEFAULT ''::"text",
    "exchange_rate" numeric DEFAULT 1.0 NOT NULL,
    "currency" "text" DEFAULT 'EGP'::"text",
    "currency_snapshot" "jsonb",
    "purchase_invoice_id" integer,
    CONSTRAINT "chk_station_batches_remaining_non_negative" CHECK (("remaining_quantity" >= (0)::numeric))
);

--
-- Name: stock_batches; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."stock_batches" (
    "id" bigint NOT NULL,
    "batch_number" "text" NOT NULL,
    "product_id" "uuid",
    "supplier_id" "uuid",
    "quantity" numeric(15,3) DEFAULT 0 NOT NULL,
    "remaining_quantity" numeric(15,3) DEFAULT 0 NOT NULL,
    "purchase_cost" double precision DEFAULT 0 NOT NULL,
    "average_cost" double precision DEFAULT 0 NOT NULL,
    "production_date" "date",
    "expiry_date" "date",
    "quality_grade" "text" DEFAULT 'A'::"text",
    "fruit_category" "text",
    "notes" "text",
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_id" "uuid",
    "supplier_name" "text",
    "exchange_rate" numeric DEFAULT 1.0 NOT NULL,
    "currency" "text" DEFAULT 'EGP'::"text",
    "currency_snapshot" "jsonb",
    "purchase_invoice_id" integer,
    CONSTRAINT "chk_stock_batches_remaining_non_negative" CHECK (("remaining_quantity" >= (0)::numeric)),
    CONSTRAINT "stock_batches_quality_grade_check" CHECK (("quality_grade" = ANY (ARRAY['A'::"text", 'B'::"text", 'C'::"text", 'D'::"text"]))),
    CONSTRAINT "stock_batches_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'depleted'::"text", 'expired'::"text", 'damaged'::"text", 'quarantine'::"text"])))
);

--
-- Name: shipment_cost_allocations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."shipment_cost_allocations" (
    "id" bigint NOT NULL,
    "shipment_id" integer NOT NULL,
    "source_cost_item_id" integer,
    "finished_product_id" integer NOT NULL,
    "allocation_basis" "text" NOT NULL,
    "allocated_amount" numeric(15,2) DEFAULT 0 NOT NULL,
    "allocation_percentage" numeric(7,4) DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "currency_snapshot" "jsonb",
    CONSTRAINT "shipment_cost_allocations_allocation_basis_check" CHECK (("allocation_basis" = ANY (ARRAY['weight_based'::"text", 'carton_based'::"text", 'manual'::"text"])))
);

--
-- Name: lot_receipts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."lot_receipts" (
    "id" bigint NOT NULL,
    "lot_number" "text" NOT NULL,
    "supplier_id" "uuid",
    "receipt_date" "date" DEFAULT CURRENT_DATE NOT NULL,
    "gross_weight_kg" numeric(15,3) DEFAULT 0 NOT NULL,
    "net_weight_kg" numeric(15,3) DEFAULT 0 NOT NULL,
    "status" "text" DEFAULT 'received'::"text" NOT NULL,
    "station_id" integer,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "waste_weight_kg" numeric(15,3) DEFAULT 0 NOT NULL,
    "waste_percentage" numeric(8,3) DEFAULT 0 NOT NULL,
    "purchase_invoice_item_id" integer,
    "fruit_cost_per_kg" double precision DEFAULT 0,
    "total_fruit_cost" double precision DEFAULT 0,
    "processed_gross_weight_kg" numeric(15,3) DEFAULT 0,
    "product_name" "text",
    "fruit_type_id" integer,
    "purchase_mode" "text" DEFAULT 'weight'::"text",
    "carton_count" integer,
    "weight_per_carton_kg" numeric(10,3),
    "price_per_carton" numeric(10,2),
    "gross_weight_per_carton_kg" numeric(10,3),
    "currency" "text" DEFAULT 'EGP'::"text",
    "exchange_rate" numeric DEFAULT 1.0 NOT NULL,
    "currency_snapshot" "jsonb",
    "is_confirmed" boolean DEFAULT false NOT NULL,
    "confirmed_at" timestamp with time zone,
    CONSTRAINT "lot_receipts_purchase_mode_check" CHECK (("purchase_mode" = ANY (ARRAY['weight'::"text", 'carton'::"text"]))),
    CONSTRAINT "lot_receipts_status_check" CHECK (("status" = ANY (ARRAY['received'::"text", 'sorting'::"text", 'packed'::"text", 'shipped'::"text", 'closed'::"text"])))
);

--
-- Name: stock_movements; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."stock_movements" (
    "id" bigint NOT NULL,
    "movement_type" "text" NOT NULL,
    "product_id" "uuid",
    "batch_id" integer,
    "quantity" numeric(15,3) NOT NULL,
    "before_quantity" numeric(15,3) DEFAULT 0 NOT NULL,
    "after_quantity" numeric(15,3) DEFAULT 0 NOT NULL,
    "unit_cost" numeric(15,4) DEFAULT 0,
    "total_cost" numeric(15,2) DEFAULT 0,
    "reference_type" "text",
    "reference_id" "text",
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_id" "uuid",
    CONSTRAINT "stock_movements_movement_type_check1" CHECK (("movement_type" = ANY (ARRAY['purchase'::"text", 'sale'::"text", 'return'::"text", 'damage'::"text", 'transfer'::"text", 'export'::"text", 'adjustment'::"text", 'packaging_usage'::"text", 'quarantine'::"text", 'release'::"text"])))
);

--
-- Name: lot_grading_results; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."lot_grading_results" (
    "id" bigint NOT NULL,
    "lot_id" bigint NOT NULL,
    "grade" "text" NOT NULL,
    "weight_kg" numeric(15,3) DEFAULT 0 NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "stock_batch_id" integer,
    CONSTRAINT "lot_grading_results_grade_check" CHECK (("grade" = ANY (ARRAY['A'::"text", 'B'::"text", 'C'::"text", 'waste'::"text"])))
);

--
-- Name: lot_returns; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."lot_returns" (
    "id" bigint NOT NULL,
    "lot_receipt_id" bigint NOT NULL,
    "supplier_id" "uuid",
    "station_id" bigint,
    "returned_quantity" numeric(15,3) NOT NULL,
    "return_value" numeric(15,2) DEFAULT 0 NOT NULL,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_by" "uuid",
    CONSTRAINT "lot_returns_returned_quantity_check" CHECK (("returned_quantity" > (0)::numeric))
);

--
-- Name: packing_orders; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."packing_orders" (
    "id" bigint NOT NULL,
    "order_number" "text" NOT NULL,
    "lot_id" bigint NOT NULL,
    "grade" "text" NOT NULL,
    "fruit_type_id" integer,
    "carton_count" integer DEFAULT 0 NOT NULL,
    "net_weight_per_carton" numeric(10,3) DEFAULT 0 NOT NULL,
    "gross_weight_per_carton" numeric(10,3) DEFAULT 0 NOT NULL,
    "total_net_weight" numeric(15,3) GENERATED ALWAYS AS ((("carton_count")::numeric * "net_weight_per_carton")) STORED,
    "total_gross_weight" numeric(15,3) GENERATED ALWAYS AS ((("carton_count")::numeric * "gross_weight_per_carton")) STORED,
    "status" "text" DEFAULT 'draft'::"text" NOT NULL,
    "packed_at" timestamp with time zone,
    "station_id" integer,
    "export_shipment_id" integer,
    "batch_id" integer,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "packing_cost_per_carton" numeric(15,4) DEFAULT 0,
    "total_packing_cost" numeric(15,2) DEFAULT 0,
    "fruit_cost_allocated" numeric(15,2) DEFAULT 0,
    "actual_material_cost" numeric(15,2) DEFAULT 0,
    "estimated_material_cost" numeric(15,2) DEFAULT 0,
    "recipe_id" integer,
    "recipe_name" "text",
    "recipe_version" integer DEFAULT 1,
    "product_name" "text",
    "sold_cartons" integer DEFAULT 0 NOT NULL,
    "fruit_cost_base" numeric DEFAULT 0,
    "material_cost_base" numeric DEFAULT 0,
    "other_cost_base" numeric DEFAULT 0,
    "display_currency" "text" DEFAULT 'EGP'::"text",
    "display_exchange_rate" numeric DEFAULT 1.0,
    "currency_snapshot" "jsonb",
    CONSTRAINT "packing_orders_grade_check" CHECK (("grade" = ANY (ARRAY['A'::"text", 'B'::"text", 'C'::"text"]))),
    CONSTRAINT "packing_orders_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'in_progress'::"text", 'completed'::"text", 'cancelled'::"text"])))
);

--
-- Name: export_shipment_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE "public"."export_shipment_items" (
    "id" bigint NOT NULL,
    "shipment_id" integer NOT NULL,
    "product_name" "text" DEFAULT ''::"text" NOT NULL,
    "quantity" integer DEFAULT 0 NOT NULL,
    "price" numeric(15,2) DEFAULT 0 NOT NULL,
    "weight_per_carton" numeric(15,2) DEFAULT 15 NOT NULL,
    "net_weight" numeric(15,2) DEFAULT 0 NOT NULL,
    "gross_weight" numeric(15,2) DEFAULT 0 NOT NULL,
    "amount" numeric(15,2) DEFAULT 0 NOT NULL,
    "pallets" integer DEFAULT 0 NOT NULL,
    "sort_order" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "export_price_per_carton" numeric(15,2),
    "finished_product_id" integer,
    "grade" "text",
    "country_of_origin" "text" DEFAULT 'Egypt'::"text",
    "hs_code" "text",
    "packing_order_id" integer,
    "invoice_product_name" "text" DEFAULT ''::"text" NOT NULL,
    "currency_snapshot" "jsonb"
);

-- ==========================================
-- 4. PRIMARY KEYS, UNIQUE & CHECK CONSTRAINTS
-- ==========================================
--
-- Name: accounts_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE "public"."accounts" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."accounts_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: company_addresses_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE "public"."company_addresses" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."company_addresses_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: cost_report_categories_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE "public"."cost_report_categories" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."cost_report_categories_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: customer_addresses_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE "public"."customer_addresses" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."customer_addresses_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: customers_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE "public"."customers" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."customers_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: exchange_rates_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE "public"."exchange_rates" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."exchange_rates_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: expense_categories_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE "public"."expense_categories" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."expense_categories_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: export_invoices_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE "public"."export_invoices" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."export_invoices_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: export_shipments_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE "public"."export_shipments" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."export_shipments_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: product_categories_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE "public"."product_categories" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."product_categories_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: purchase_invoice_items_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE "public"."purchase_invoice_items" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."purchase_invoice_items_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: purchase_invoices_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE "public"."purchase_invoices" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."purchase_invoices_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: sales_invoice_items_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE "public"."sales_invoice_items" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."sales_invoice_items_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: sales_invoices_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE "public"."sales_invoices" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."sales_invoices_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: settings_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE "public"."settings" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."settings_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: stock_batches_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE "public"."stock_batches_uuid_legacy" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."stock_batches_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: stock_movements_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE "public"."stock_movements_uuid_legacy" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."stock_movements_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: transactions_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE "public"."transactions" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."transactions_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: user_roles_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE "public"."user_roles" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."user_roles_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: audit_logs_text id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."audit_logs_text" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."audit_logs_text_id_seq"'::"regclass");

--
-- Name: bank_account_transactions id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."bank_account_transactions" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."bank_account_transactions_id_seq"'::"regclass");

--
-- Name: bank_accounts id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."bank_accounts" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."bank_accounts_id_seq"'::"regclass");

--
-- Name: cheques id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."cheques" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."cheques_id_seq"'::"regclass");

--
-- Name: financial_audit_log id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."financial_audit_log" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."financial_audit_log_id_seq"'::"regclass");

--
-- Name: fiscal_year_audit_log id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."fiscal_year_audit_log" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."fiscal_year_audit_log_id_seq"'::"regclass");

--
-- Name: fiscal_year_backup_metadata id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."fiscal_year_backup_metadata" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."fiscal_year_backup_metadata_id_seq"'::"regclass");

--
-- Name: fiscal_year_closing_entries id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."fiscal_year_closing_entries" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."fiscal_year_closing_entries_id_seq"'::"regclass");

--
-- Name: fiscal_year_closing_progress id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."fiscal_year_closing_progress" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."fiscal_year_closing_progress_id_seq"'::"regclass");

--
-- Name: fiscal_year_inventory_snapshot id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."fiscal_year_inventory_snapshot" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."fiscal_year_inventory_snapshot_id_seq"'::"regclass");

--
-- Name: fiscal_years id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."fiscal_years" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."fiscal_years_id_seq"'::"regclass");

--
-- Name: fruit_types id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."fruit_types" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."fruit_types_id_seq"'::"regclass");

--
-- Name: general_cost_items id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."general_cost_items" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."general_cost_items_id_seq"'::"regclass");

--
-- Name: ledger_entries id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."ledger_entries" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."ledger_entries_id_seq"'::"regclass");

--
-- Name: lot_grading_results id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."lot_grading_results" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."lot_grading_results_id_seq"'::"regclass");

--
-- Name: lot_receipts id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."lot_receipts" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."lot_receipts_id_seq"'::"regclass");

--
-- Name: packing_order_cost_items id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."packing_order_cost_items" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."packing_order_cost_items_id_seq"'::"regclass");

--
-- Name: packing_order_sortings id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."packing_order_sortings" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."packing_order_sortings_id_seq"'::"regclass");

--
-- Name: packing_orders id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."packing_orders" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."packing_orders_id_seq"'::"regclass");

--
-- Name: packing_recipes id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."packing_recipes" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."packing_recipes_id_seq"'::"regclass");

--
-- Name: prep_center_cost_items id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."prep_center_cost_items" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."prep_center_cost_items_id_seq"'::"regclass");

--
-- Name: shipment_cost_allocations id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shipment_cost_allocations" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."shipment_cost_allocations_id_seq"'::"regclass");

--
-- Name: shipment_cost_breakdown id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shipment_cost_breakdown" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."shipment_cost_breakdown_id_seq"'::"regclass");

--
-- Name: shipment_cost_items id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shipment_cost_items" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."shipment_cost_items_id_seq"'::"regclass");

--
-- Name: shipment_profitability_snapshots id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shipment_profitability_snapshots" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."shipment_profitability_snapshots_id_seq"'::"regclass");

--
-- Name: shipment_recipe_snapshots id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shipment_recipe_snapshots" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."shipment_recipe_snapshots_id_seq"'::"regclass");

--
-- Name: shipping_companies id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shipping_companies" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."shipping_companies_id_seq"'::"regclass");

--
-- Name: stations id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."stations" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."stations_id_seq"'::"regclass");

--
-- Name: stock_batches id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."stock_batches" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."stock_batches_id_seq1"'::"regclass");

--
-- Name: stock_movements id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."stock_movements" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."stock_movements_id_seq1"'::"regclass");

--
-- Name: stock_transfers id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."stock_transfers" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."stock_transfers_id_seq"'::"regclass");

--
-- Name: supplier_settlements id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."supplier_settlements" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."supplier_settlements_id_seq"'::"regclass");

--
-- Name: treasuries id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."treasuries" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."treasuries_id_seq"'::"regclass");

--
-- Name: treasury_balances id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."treasury_balances" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."treasury_balances_id_seq"'::"regclass");

--
-- Name: treasury_transactions id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."treasury_transactions" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."treasury_transactions_id_seq"'::"regclass");

--
-- Name: accounts accounts_account_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."accounts"
    ADD CONSTRAINT "accounts_account_code_key" UNIQUE ("account_code");

--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."accounts"
    ADD CONSTRAINT "accounts_pkey" PRIMARY KEY ("id");

--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."audit_logs"
    ADD CONSTRAINT "audit_logs_pkey" PRIMARY KEY ("id");

--
-- Name: audit_logs_text audit_logs_text_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."audit_logs_text"
    ADD CONSTRAINT "audit_logs_text_pkey" PRIMARY KEY ("id");

--
-- Name: bank_account_transactions bank_account_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."bank_account_transactions"
    ADD CONSTRAINT "bank_account_transactions_pkey" PRIMARY KEY ("id");

--
-- Name: bank_account_transactions bank_account_transactions_type_check; Type: CHECK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE "public"."bank_account_transactions"
    ADD CONSTRAINT "bank_account_transactions_type_check" CHECK (("type" = ANY (ARRAY['deposit'::"text", 'withdraw'::"text", 'currency_exchange_out'::"text", 'currency_exchange_in'::"text"]))) NOT VALID;

--
-- Name: bank_accounts bank_accounts_currency_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."bank_accounts"
    ADD CONSTRAINT "bank_accounts_currency_key" UNIQUE ("currency");

--
-- Name: bank_accounts bank_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."bank_accounts"
    ADD CONSTRAINT "bank_accounts_pkey" PRIMARY KEY ("id");

--
-- Name: cash_payments cash_payments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."cash_payments"
    ADD CONSTRAINT "cash_payments_pkey" PRIMARY KEY ("id");

--
-- Name: cashbox_transactions cashbox_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."cashbox_transactions"
    ADD CONSTRAINT "cashbox_transactions_pkey" PRIMARY KEY ("id");

--
-- Name: cheques cheques_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."cheques"
    ADD CONSTRAINT "cheques_pkey" PRIMARY KEY ("id");

--
-- Name: clearing_agents clearing_agents_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."clearing_agents"
    ADD CONSTRAINT "clearing_agents_code_key" UNIQUE ("code");

--
-- Name: clearing_agents clearing_agents_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."clearing_agents"
    ADD CONSTRAINT "clearing_agents_pkey" PRIMARY KEY ("id");

--
-- Name: company_addresses company_addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."company_addresses"
    ADD CONSTRAINT "company_addresses_pkey" PRIMARY KEY ("id");

--
-- Name: cost_report_categories cost_report_categories_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."cost_report_categories"
    ADD CONSTRAINT "cost_report_categories_name_key" UNIQUE ("name");

--
-- Name: cost_report_categories cost_report_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."cost_report_categories"
    ADD CONSTRAINT "cost_report_categories_pkey" PRIMARY KEY ("id");

--
-- Name: currencies currencies_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."currencies"
    ADD CONSTRAINT "currencies_code_key" UNIQUE ("code");

--
-- Name: currencies currencies_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."currencies"
    ADD CONSTRAINT "currencies_pkey" PRIMARY KEY ("id");

--
-- Name: customer_addresses customer_addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."customer_addresses"
    ADD CONSTRAINT "customer_addresses_pkey" PRIMARY KEY ("id");

--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_pkey" PRIMARY KEY ("id");

--
-- Name: exchange_rates exchange_rates_currency_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."exchange_rates"
    ADD CONSTRAINT "exchange_rates_currency_code_key" UNIQUE ("currency_code");

--
-- Name: exchange_rates exchange_rates_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."exchange_rates"
    ADD CONSTRAINT "exchange_rates_pkey" PRIMARY KEY ("id");

--
-- Name: expense_categories expense_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."expense_categories"
    ADD CONSTRAINT "expense_categories_pkey" PRIMARY KEY ("id");

--
-- Name: export_invoices export_invoices_invoice_no_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."export_invoices"
    ADD CONSTRAINT "export_invoices_invoice_no_key" UNIQUE ("invoice_no");

--
-- Name: export_invoices export_invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."export_invoices"
    ADD CONSTRAINT "export_invoices_pkey" PRIMARY KEY ("id");

--
-- Name: export_shipment_items export_shipment_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."export_shipment_items"
    ADD CONSTRAINT "export_shipment_items_pkey" PRIMARY KEY ("id");

--
-- Name: export_shipments export_shipments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."export_shipments"
    ADD CONSTRAINT "export_shipments_pkey" PRIMARY KEY ("id");

--
-- Name: export_shipments export_shipments_shipment_no_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."export_shipments"
    ADD CONSTRAINT "export_shipments_shipment_no_key" UNIQUE ("shipment_no");

--
-- Name: export_shipments export_shipments_shipment_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."export_shipments"
    ADD CONSTRAINT "export_shipments_shipment_number_key" UNIQUE ("shipment_number");

--
-- Name: financial_audit_log financial_audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."financial_audit_log"
    ADD CONSTRAINT "financial_audit_log_pkey" PRIMARY KEY ("id");

--
-- Name: fiscal_year_audit_log fiscal_year_audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."fiscal_year_audit_log"
    ADD CONSTRAINT "fiscal_year_audit_log_pkey" PRIMARY KEY ("id");

--
-- Name: fiscal_year_backup_metadata fiscal_year_backup_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."fiscal_year_backup_metadata"
    ADD CONSTRAINT "fiscal_year_backup_metadata_pkey" PRIMARY KEY ("id");

--
-- Name: fiscal_year_closing_entries fiscal_year_closing_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."fiscal_year_closing_entries"
    ADD CONSTRAINT "fiscal_year_closing_entries_pkey" PRIMARY KEY ("id");

--
-- Name: fiscal_year_closing_lock fiscal_year_closing_lock_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."fiscal_year_closing_lock"
    ADD CONSTRAINT "fiscal_year_closing_lock_pkey" PRIMARY KEY ("id");

--
-- Name: fiscal_year_closing_progress fiscal_year_closing_progress_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."fiscal_year_closing_progress"
    ADD CONSTRAINT "fiscal_year_closing_progress_pkey" PRIMARY KEY ("id");

--
-- Name: fiscal_year_inventory_snapshot fiscal_year_inventory_snapshot_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."fiscal_year_inventory_snapshot"
    ADD CONSTRAINT "fiscal_year_inventory_snapshot_pkey" PRIMARY KEY ("id");

--
-- Name: fiscal_years fiscal_years_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."fiscal_years"
    ADD CONSTRAINT "fiscal_years_pkey" PRIMARY KEY ("id");

--
-- Name: fruit_catalog fruit_catalog_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."fruit_catalog"
    ADD CONSTRAINT "fruit_catalog_pkey" PRIMARY KEY ("id");

--
-- Name: fruit_types fruit_types_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."fruit_types"
    ADD CONSTRAINT "fruit_types_code_key" UNIQUE ("code");

--
-- Name: fruit_types fruit_types_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."fruit_types"
    ADD CONSTRAINT "fruit_types_name_key" UNIQUE ("name");

--
-- Name: fruit_types fruit_types_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."fruit_types"
    ADD CONSTRAINT "fruit_types_pkey" PRIMARY KEY ("id");

--
-- Name: general_cost_items general_cost_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."general_cost_items"
    ADD CONSTRAINT "general_cost_items_pkey" PRIMARY KEY ("id");

--
-- Name: invoice_edits invoice_edits_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."invoice_edits"
    ADD CONSTRAINT "invoice_edits_pkey" PRIMARY KEY ("id");

--
-- Name: ledger_entries ledger_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."ledger_entries"
    ADD CONSTRAINT "ledger_entries_pkey" PRIMARY KEY ("id");

--
-- Name: lot_grading_results lot_grading_results_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."lot_grading_results"
    ADD CONSTRAINT "lot_grading_results_pkey" PRIMARY KEY ("id");

--
-- Name: lot_receipts lot_receipts_lot_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."lot_receipts"
    ADD CONSTRAINT "lot_receipts_lot_number_key" UNIQUE ("lot_number");

--
-- Name: lot_receipts lot_receipts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."lot_receipts"
    ADD CONSTRAINT "lot_receipts_pkey" PRIMARY KEY ("id");

--
-- Name: lot_returns lot_returns_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."lot_returns"
    ADD CONSTRAINT "lot_returns_pkey" PRIMARY KEY ("id");

--
-- Name: packing_order_cost_items packing_order_cost_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."packing_order_cost_items"
    ADD CONSTRAINT "packing_order_cost_items_pkey" PRIMARY KEY ("id");

--
-- Name: packing_order_sortings packing_order_sortings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."packing_order_sortings"
    ADD CONSTRAINT "packing_order_sortings_pkey" PRIMARY KEY ("id");

--
-- Name: packing_orders packing_orders_order_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."packing_orders"
    ADD CONSTRAINT "packing_orders_order_number_key" UNIQUE ("order_number");

--
-- Name: packing_orders packing_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."packing_orders"
    ADD CONSTRAINT "packing_orders_pkey" PRIMARY KEY ("id");

--
-- Name: packing_recipes packing_recipes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."packing_recipes"
    ADD CONSTRAINT "packing_recipes_pkey" PRIMARY KEY ("id");

--
-- Name: packing_recipes packing_recipes_product_id_grade_raw_material_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."packing_recipes"
    ADD CONSTRAINT "packing_recipes_product_id_grade_raw_material_id_key" UNIQUE ("product_id", "grade", "raw_material_id");

--
-- Name: prep_center_cost_items prep_center_cost_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."prep_center_cost_items"
    ADD CONSTRAINT "prep_center_cost_items_pkey" PRIMARY KEY ("id");

--
-- Name: pricing_rules pricing_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."pricing_rules"
    ADD CONSTRAINT "pricing_rules_pkey" PRIMARY KEY ("id");

--
-- Name: product_categories product_categories_category_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."product_categories"
    ADD CONSTRAINT "product_categories_category_name_key" UNIQUE ("category_name");

--
-- Name: product_categories product_categories_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."product_categories"
    ADD CONSTRAINT "product_categories_name_key" UNIQUE ("name");

--
-- Name: product_categories product_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."product_categories"
    ADD CONSTRAINT "product_categories_pkey" PRIMARY KEY ("id");

--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");

--
-- Name: profit_distribution_settings profit_distribution_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."profit_distribution_settings"
    ADD CONSTRAINT "profit_distribution_settings_pkey" PRIMARY KEY ("id");

--
-- Name: profit_distribution_settings profit_distribution_settings_user_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."profit_distribution_settings"
    ADD CONSTRAINT "profit_distribution_settings_user_id_key" UNIQUE ("user_id");

--
-- Name: proforma_invoice_items proforma_invoice_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."proforma_invoice_items"
    ADD CONSTRAINT "proforma_invoice_items_pkey" PRIMARY KEY ("id");

--
-- Name: proforma_invoices proforma_invoices_invoice_no_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."proforma_invoices"
    ADD CONSTRAINT "proforma_invoices_invoice_no_key" UNIQUE ("invoice_no");

--
-- Name: proforma_invoices proforma_invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."proforma_invoices"
    ADD CONSTRAINT "proforma_invoices_pkey" PRIMARY KEY ("id");

--
-- Name: purchase_invoice_items purchase_invoice_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."purchase_invoice_items"
    ADD CONSTRAINT "purchase_invoice_items_pkey" PRIMARY KEY ("id");

--
-- Name: purchase_invoices purchase_invoices_invoice_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."purchase_invoices"
    ADD CONSTRAINT "purchase_invoices_invoice_number_key" UNIQUE ("invoice_number");

--
-- Name: purchase_invoices purchase_invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."purchase_invoices"
    ADD CONSTRAINT "purchase_invoices_pkey" PRIMARY KEY ("id");

--
-- Name: raw_material_categories raw_material_categories_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."raw_material_categories"
    ADD CONSTRAINT "raw_material_categories_name_key" UNIQUE ("name");

--
-- Name: raw_material_categories raw_material_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."raw_material_categories"
    ADD CONSTRAINT "raw_material_categories_pkey" PRIMARY KEY ("id");

--
-- Name: raw_materials raw_materials_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."raw_materials"
    ADD CONSTRAINT "raw_materials_code_key" UNIQUE ("code");

--
-- Name: raw_materials raw_materials_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."raw_materials"
    ADD CONSTRAINT "raw_materials_pkey" PRIMARY KEY ("id");

--
-- Name: sales_invoice_items sales_invoice_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."sales_invoice_items"
    ADD CONSTRAINT "sales_invoice_items_pkey" PRIMARY KEY ("id");

--
-- Name: sales_invoices sales_invoices_invoice_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."sales_invoices"
    ADD CONSTRAINT "sales_invoices_invoice_number_key" UNIQUE ("invoice_number");

--
-- Name: sales_invoices sales_invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."sales_invoices"
    ADD CONSTRAINT "sales_invoices_pkey" PRIMARY KEY ("id");

--
-- Name: settings settings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."settings"
    ADD CONSTRAINT "settings_pkey" PRIMARY KEY ("id");

--
-- Name: shareholder_profit_distributions shareholder_profit_distributions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shareholder_profit_distributions"
    ADD CONSTRAINT "shareholder_profit_distributions_pkey" PRIMARY KEY ("id");

--
-- Name: shareholders shareholders_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shareholders"
    ADD CONSTRAINT "shareholders_code_key" UNIQUE ("code");

--
-- Name: shareholders shareholders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shareholders"
    ADD CONSTRAINT "shareholders_pkey" PRIMARY KEY ("id");

--
-- Name: shipment_cost_allocations shipment_cost_allocations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shipment_cost_allocations"
    ADD CONSTRAINT "shipment_cost_allocations_pkey" PRIMARY KEY ("id");

--
-- Name: shipment_cost_breakdown shipment_cost_breakdown_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shipment_cost_breakdown"
    ADD CONSTRAINT "shipment_cost_breakdown_pkey" PRIMARY KEY ("id");

--
-- Name: shipment_cost_items shipment_cost_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shipment_cost_items"
    ADD CONSTRAINT "shipment_cost_items_pkey" PRIMARY KEY ("id");

--
-- Name: shipment_profitability_snapshots shipment_profitability_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shipment_profitability_snapshots"
    ADD CONSTRAINT "shipment_profitability_snapshots_pkey" PRIMARY KEY ("id");

--
-- Name: shipment_recipe_snapshots shipment_recipe_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shipment_recipe_snapshots"
    ADD CONSTRAINT "shipment_recipe_snapshots_pkey" PRIMARY KEY ("id");

--
-- Name: shipping_companies shipping_companies_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shipping_companies"
    ADD CONSTRAINT "shipping_companies_code_key" UNIQUE ("code");

--
-- Name: shipping_companies shipping_companies_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shipping_companies"
    ADD CONSTRAINT "shipping_companies_pkey" PRIMARY KEY ("id");

--
-- Name: statement_notes statement_notes_entity_type_entity_id_reference_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."statement_notes"
    ADD CONSTRAINT "statement_notes_entity_type_entity_id_reference_id_key" UNIQUE ("entity_type", "entity_id", "reference_id");

--
-- Name: statement_notes statement_notes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."statement_notes"
    ADD CONSTRAINT "statement_notes_pkey" PRIMARY KEY ("id");

--
-- Name: station_product_batches station_product_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."station_product_batches"
    ADD CONSTRAINT "station_product_batches_pkey" PRIMARY KEY ("id");

--
-- Name: station_products station_products_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."station_products"
    ADD CONSTRAINT "station_products_pkey" PRIMARY KEY ("id");

--
-- Name: station_products station_products_station_id_fruit_type_id_unit_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."station_products"
    ADD CONSTRAINT "station_products_station_id_fruit_type_id_unit_key" UNIQUE ("station_id", "fruit_type_id", "unit");

--
-- Name: station_products station_products_station_id_product_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."station_products"
    ADD CONSTRAINT "station_products_station_id_product_name_key" UNIQUE ("station_id", "product_name");

--
-- Name: stations stations_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."stations"
    ADD CONSTRAINT "stations_code_key" UNIQUE ("code");

--
-- Name: stations stations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."stations"
    ADD CONSTRAINT "stations_pkey" PRIMARY KEY ("id");

--
-- Name: stock_batches stock_batches_batch_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."stock_batches"
    ADD CONSTRAINT "stock_batches_batch_number_key" UNIQUE ("batch_number");

--
-- Name: stock_batches_uuid_legacy stock_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."stock_batches_uuid_legacy"
    ADD CONSTRAINT "stock_batches_pkey" PRIMARY KEY ("id");

--
-- Name: stock_batches stock_batches_pkey1; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."stock_batches"
    ADD CONSTRAINT "stock_batches_pkey1" PRIMARY KEY ("id");

--
-- Name: stock_movements_uuid_legacy stock_movements_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."stock_movements_uuid_legacy"
    ADD CONSTRAINT "stock_movements_pkey" PRIMARY KEY ("id");

--
-- Name: stock_movements stock_movements_pkey1; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."stock_movements"
    ADD CONSTRAINT "stock_movements_pkey1" PRIMARY KEY ("id");

--
-- Name: stock_transfers stock_transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."stock_transfers"
    ADD CONSTRAINT "stock_transfers_pkey" PRIMARY KEY ("id");

--
-- Name: subscription_plans subscription_plans_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."subscription_plans"
    ADD CONSTRAINT "subscription_plans_pkey" PRIMARY KEY ("id");

--
-- Name: supplier_settlements supplier_settlements_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."supplier_settlements"
    ADD CONSTRAINT "supplier_settlements_pkey" PRIMARY KEY ("id");

--
-- Name: suppliers suppliers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_pkey" PRIMARY KEY ("id");

--
-- Name: system_settings system_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."system_settings"
    ADD CONSTRAINT "system_settings_pkey" PRIMARY KEY ("id");

--
-- Name: system_settings system_settings_setting_key_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."system_settings"
    ADD CONSTRAINT "system_settings_setting_key_key" UNIQUE ("setting_key");

--
-- Name: tenant_users tenant_users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."tenant_users"
    ADD CONSTRAINT "tenant_users_pkey" PRIMARY KEY ("id");

--
-- Name: tenant_users tenant_users_tenant_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."tenant_users"
    ADD CONSTRAINT "tenant_users_tenant_id_user_id_key" UNIQUE ("tenant_id", "user_id");

--
-- Name: tenants tenants_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."tenants"
    ADD CONSTRAINT "tenants_pkey" PRIMARY KEY ("id");

--
-- Name: transactions transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."transactions"
    ADD CONSTRAINT "transactions_pkey" PRIMARY KEY ("id");

--
-- Name: treasuries treasuries_name_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."treasuries"
    ADD CONSTRAINT "treasuries_name_unique" UNIQUE ("name");

--
-- Name: treasuries treasuries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."treasuries"
    ADD CONSTRAINT "treasuries_pkey" PRIMARY KEY ("id");

--
-- Name: treasury_balances treasury_balances_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."treasury_balances"
    ADD CONSTRAINT "treasury_balances_pkey" PRIMARY KEY ("id");

--
-- Name: treasury_balances treasury_balances_treasury_id_currency_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."treasury_balances"
    ADD CONSTRAINT "treasury_balances_treasury_id_currency_key" UNIQUE ("treasury_id", "currency");

--
-- Name: treasury_transactions treasury_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."treasury_transactions"
    ADD CONSTRAINT "treasury_transactions_pkey" PRIMARY KEY ("id");

--
-- Name: treasury_transactions treasury_transactions_type_check; Type: CHECK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE "public"."treasury_transactions"
    ADD CONSTRAINT "treasury_transactions_type_check" CHECK (("type" = ANY (ARRAY['deposit'::"text", 'expense'::"text", 'withdrawal'::"text", 'disbursement'::"text", 'disbursement_out'::"text", 'transfer_in'::"text", 'transfer_out'::"text", 'return_in'::"text", 'return_out'::"text", 'currency_exchange_out'::"text", 'currency_exchange_in'::"text"]))) NOT VALID;

--
-- Name: unit_conversions unit_conversions_from_unit_to_unit_product_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."unit_conversions"
    ADD CONSTRAINT "unit_conversions_from_unit_to_unit_product_id_key" UNIQUE ("from_unit", "to_unit", "product_id");

--
-- Name: unit_conversions unit_conversions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."unit_conversions"
    ADD CONSTRAINT "unit_conversions_pkey" PRIMARY KEY ("id");

--
-- Name: station_products uq_station_products_station_product_name; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."station_products"
    ADD CONSTRAINT "uq_station_products_station_product_name" UNIQUE ("station_id", "product_name");

--
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_pkey" PRIMARY KEY ("id");

--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");

--
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_username_key" UNIQUE ("username");

--
-- Name: warehouses warehouses_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."warehouses"
    ADD CONSTRAINT "warehouses_pkey" PRIMARY KEY ("id");

--
-- Name: audit_logs_text_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."audit_logs_text_id_seq" OWNED BY "public"."audit_logs_text"."id";

--
-- Name: bank_account_transactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."bank_account_transactions_id_seq" OWNED BY "public"."bank_account_transactions"."id";

--
-- Name: bank_accounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."bank_accounts_id_seq" OWNED BY "public"."bank_accounts"."id";

--
-- Name: cheques_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."cheques_id_seq" OWNED BY "public"."cheques"."id";

--
-- Name: financial_audit_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."financial_audit_log_id_seq" OWNED BY "public"."financial_audit_log"."id";

--
-- Name: fiscal_year_audit_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."fiscal_year_audit_log_id_seq" OWNED BY "public"."fiscal_year_audit_log"."id";

--
-- Name: fiscal_year_backup_metadata_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."fiscal_year_backup_metadata_id_seq" OWNED BY "public"."fiscal_year_backup_metadata"."id";

--
-- Name: fiscal_year_closing_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."fiscal_year_closing_entries_id_seq" OWNED BY "public"."fiscal_year_closing_entries"."id";

--
-- Name: fiscal_year_closing_progress_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."fiscal_year_closing_progress_id_seq" OWNED BY "public"."fiscal_year_closing_progress"."id";

--
-- Name: fiscal_year_inventory_snapshot_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."fiscal_year_inventory_snapshot_id_seq" OWNED BY "public"."fiscal_year_inventory_snapshot"."id";

--
-- Name: fiscal_years_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."fiscal_years_id_seq" OWNED BY "public"."fiscal_years"."id";

--
-- Name: fruit_types_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."fruit_types_id_seq" OWNED BY "public"."fruit_types"."id";

--
-- Name: general_cost_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."general_cost_items_id_seq" OWNED BY "public"."general_cost_items"."id";

--
-- Name: ledger_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."ledger_entries_id_seq" OWNED BY "public"."ledger_entries"."id";

--
-- Name: lot_grading_results_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."lot_grading_results_id_seq" OWNED BY "public"."lot_grading_results"."id";

--
-- Name: lot_receipts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."lot_receipts_id_seq" OWNED BY "public"."lot_receipts"."id";

--
-- Name: packing_order_cost_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."packing_order_cost_items_id_seq" OWNED BY "public"."packing_order_cost_items"."id";

--
-- Name: packing_order_sortings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."packing_order_sortings_id_seq" OWNED BY "public"."packing_order_sortings"."id";

--
-- Name: packing_orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."packing_orders_id_seq" OWNED BY "public"."packing_orders"."id";

--
-- Name: packing_recipes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."packing_recipes_id_seq" OWNED BY "public"."packing_recipes"."id";

--
-- Name: prep_center_cost_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."prep_center_cost_items_id_seq" OWNED BY "public"."prep_center_cost_items"."id";

--
-- Name: shipment_cost_allocations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."shipment_cost_allocations_id_seq" OWNED BY "public"."shipment_cost_allocations"."id";

--
-- Name: shipment_cost_breakdown_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."shipment_cost_breakdown_id_seq" OWNED BY "public"."shipment_cost_breakdown"."id";

--
-- Name: shipment_cost_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."shipment_cost_items_id_seq" OWNED BY "public"."shipment_cost_items"."id";

--
-- Name: shipment_profitability_snapshots_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."shipment_profitability_snapshots_id_seq" OWNED BY "public"."shipment_profitability_snapshots"."id";

--
-- Name: shipment_recipe_snapshots_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."shipment_recipe_snapshots_id_seq" OWNED BY "public"."shipment_recipe_snapshots"."id";

--
-- Name: shipping_companies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."shipping_companies_id_seq" OWNED BY "public"."shipping_companies"."id";

--
-- Name: stations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."stations_id_seq" OWNED BY "public"."stations"."id";

--
-- Name: stock_batches_id_seq1; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."stock_batches_id_seq1" OWNED BY "public"."stock_batches"."id";

--
-- Name: stock_movements_id_seq1; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."stock_movements_id_seq1" OWNED BY "public"."stock_movements"."id";

--
-- Name: stock_transfers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."stock_transfers_id_seq" OWNED BY "public"."stock_transfers"."id";

--
-- Name: supplier_settlements_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."supplier_settlements_id_seq" OWNED BY "public"."supplier_settlements"."id";

--
-- Name: treasuries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."treasuries_id_seq" OWNED BY "public"."treasuries"."id";

--
-- Name: treasury_balances_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."treasury_balances_id_seq" OWNED BY "public"."treasury_balances"."id";

--
-- Name: treasury_transactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE "public"."treasury_transactions_id_seq" OWNED BY "public"."treasury_transactions"."id";

-- ==========================================
-- 5. FOREIGN KEY CONSTRAINTS
-- ==========================================
--
-- Name: accounts accounts_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."accounts"
    ADD CONSTRAINT "accounts_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "public"."accounts"("id") ON DELETE SET NULL;

--
-- Name: ledger_entries ledger_entries_reversal_of_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."ledger_entries"
    ADD CONSTRAINT "ledger_entries_reversal_of_id_fkey" FOREIGN KEY ("reversal_of_id") REFERENCES "public"."ledger_entries"("id") ON DELETE SET NULL;

--
-- Name: product_categories product_categories_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."product_categories"
    ADD CONSTRAINT "product_categories_parent_id_fkey" FOREIGN KEY ("parent_id") REFERENCES "public"."product_categories"("id") ON DELETE SET NULL;

--
-- Name: fiscal_year_audit_log fiscal_year_audit_log_fiscal_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."fiscal_year_audit_log"
    ADD CONSTRAINT "fiscal_year_audit_log_fiscal_year_id_fkey" FOREIGN KEY ("fiscal_year_id") REFERENCES "public"."fiscal_years"("id") ON DELETE CASCADE;

--
-- Name: fiscal_year_backup_metadata fiscal_year_backup_metadata_fiscal_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."fiscal_year_backup_metadata"
    ADD CONSTRAINT "fiscal_year_backup_metadata_fiscal_year_id_fkey" FOREIGN KEY ("fiscal_year_id") REFERENCES "public"."fiscal_years"("id");

--
-- Name: fiscal_year_closing_entries fiscal_year_closing_entries_fiscal_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."fiscal_year_closing_entries"
    ADD CONSTRAINT "fiscal_year_closing_entries_fiscal_year_id_fkey" FOREIGN KEY ("fiscal_year_id") REFERENCES "public"."fiscal_years"("id");

--
-- Name: fiscal_year_closing_lock fiscal_year_closing_lock_fiscal_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."fiscal_year_closing_lock"
    ADD CONSTRAINT "fiscal_year_closing_lock_fiscal_year_id_fkey" FOREIGN KEY ("fiscal_year_id") REFERENCES "public"."fiscal_years"("id");

--
-- Name: fiscal_year_closing_progress fiscal_year_closing_progress_fiscal_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."fiscal_year_closing_progress"
    ADD CONSTRAINT "fiscal_year_closing_progress_fiscal_year_id_fkey" FOREIGN KEY ("fiscal_year_id") REFERENCES "public"."fiscal_years"("id");

--
-- Name: fiscal_year_inventory_snapshot fiscal_year_inventory_snapshot_fiscal_year_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."fiscal_year_inventory_snapshot"
    ADD CONSTRAINT "fiscal_year_inventory_snapshot_fiscal_year_id_fkey" FOREIGN KEY ("fiscal_year_id") REFERENCES "public"."fiscal_years"("id");

--
-- Name: customers customers_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id");

--
-- Name: suppliers suppliers_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id");

--
-- Name: transactions transactions_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."transactions"
    ADD CONSTRAINT "transactions_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id");

--
-- Name: general_cost_items general_cost_items_report_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."general_cost_items"
    ADD CONSTRAINT "general_cost_items_report_category_id_fkey" FOREIGN KEY ("report_category_id") REFERENCES "public"."cost_report_categories"("id") ON DELETE SET NULL;

--
-- Name: station_products station_products_fruit_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."station_products"
    ADD CONSTRAINT "station_products_fruit_type_id_fkey" FOREIGN KEY ("fruit_type_id") REFERENCES "public"."fruit_types"("id") ON DELETE CASCADE;

--
-- Name: station_products station_products_station_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."station_products"
    ADD CONSTRAINT "station_products_station_id_fkey" FOREIGN KEY ("station_id") REFERENCES "public"."stations"("id") ON DELETE CASCADE;

--
-- Name: stock_transfers stock_transfers_to_station_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."stock_transfers"
    ADD CONSTRAINT "stock_transfers_to_station_id_fkey" FOREIGN KEY ("to_station_id") REFERENCES "public"."stations"("id") ON DELETE SET NULL;

--
-- Name: stock_movements_uuid_legacy stock_movements_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."stock_movements_uuid_legacy"
    ADD CONSTRAINT "stock_movements_batch_id_fkey" FOREIGN KEY ("batch_id") REFERENCES "public"."stock_batches_uuid_legacy"("id");

--
-- Name: bank_account_transactions bank_account_transactions_bank_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."bank_account_transactions"
    ADD CONSTRAINT "bank_account_transactions_bank_account_id_fkey" FOREIGN KEY ("bank_account_id") REFERENCES "public"."bank_accounts"("id") ON DELETE CASCADE;

--
-- Name: tenants tenants_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."tenants"
    ADD CONSTRAINT "tenants_plan_id_fkey" FOREIGN KEY ("plan_id") REFERENCES "public"."subscription_plans"("id") ON DELETE SET NULL;

--
-- Name: expense_categories expense_categories_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."expense_categories"
    ADD CONSTRAINT "expense_categories_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id");

--
-- Name: treasuries treasuries_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."treasuries"
    ADD CONSTRAINT "treasuries_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id");

--
-- Name: treasuries treasuries_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."treasuries"
    ADD CONSTRAINT "treasuries_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE SET NULL;

--
-- Name: user_roles user_roles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."user_roles"
    ADD CONSTRAINT "user_roles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;

--
-- Name: cashbox_transactions cashbox_transactions_currency_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."cashbox_transactions"
    ADD CONSTRAINT "cashbox_transactions_currency_id_fkey" FOREIGN KEY ("currency_id") REFERENCES "public"."currencies"("id");

--
-- Name: pricing_rules pricing_rules_currency_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."pricing_rules"
    ADD CONSTRAINT "pricing_rules_currency_id_fkey" FOREIGN KEY ("currency_id") REFERENCES "public"."currencies"("id");

--
-- Name: proforma_invoice_items proforma_invoice_items_proforma_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."proforma_invoice_items"
    ADD CONSTRAINT "proforma_invoice_items_proforma_invoice_id_fkey" FOREIGN KEY ("proforma_invoice_id") REFERENCES "public"."proforma_invoices"("id") ON DELETE CASCADE;

--
-- Name: company_addresses company_addresses_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."company_addresses"
    ADD CONSTRAINT "company_addresses_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE CASCADE;

--
-- Name: customer_addresses customer_addresses_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."customer_addresses"
    ADD CONSTRAINT "customer_addresses_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE CASCADE;

--
-- Name: export_invoices export_invoices_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."export_invoices"
    ADD CONSTRAINT "export_invoices_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id");

--
-- Name: export_shipments export_shipments_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."export_shipments"
    ADD CONSTRAINT "export_shipments_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE CASCADE;

--
-- Name: export_shipments export_shipments_packing_recipe_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."export_shipments"
    ADD CONSTRAINT "export_shipments_packing_recipe_id_fkey" FOREIGN KEY ("packing_recipe_id") REFERENCES "public"."packing_recipes"("id");

--
-- Name: sales_invoices sales_invoices_currency_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."sales_invoices"
    ADD CONSTRAINT "sales_invoices_currency_id_fkey" FOREIGN KEY ("currency_id") REFERENCES "public"."currencies"("id");

--
-- Name: sales_invoices sales_invoices_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."sales_invoices"
    ADD CONSTRAINT "sales_invoices_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE CASCADE;

--
-- Name: purchase_invoices fk_purchase_invoices_supplier; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."purchase_invoices"
    ADD CONSTRAINT "fk_purchase_invoices_supplier" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id");

--
-- Name: purchase_invoices purchase_invoices_currency_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."purchase_invoices"
    ADD CONSTRAINT "purchase_invoices_currency_id_fkey" FOREIGN KEY ("currency_id") REFERENCES "public"."currencies"("id");

--
-- Name: purchase_invoices purchase_invoices_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."purchase_invoices"
    ADD CONSTRAINT "purchase_invoices_warehouse_id_fkey" FOREIGN KEY ("warehouse_id") REFERENCES "public"."warehouses"("id") ON DELETE SET NULL;

--
-- Name: raw_materials raw_materials_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."raw_materials"
    ADD CONSTRAINT "raw_materials_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."raw_material_categories"("id") ON DELETE SET NULL;

--
-- Name: raw_materials raw_materials_default_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."raw_materials"
    ADD CONSTRAINT "raw_materials_default_supplier_id_fkey" FOREIGN KEY ("default_supplier_id") REFERENCES "public"."suppliers"("id") ON DELETE SET NULL;

--
-- Name: tenant_users tenant_users_tenant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."tenant_users"
    ADD CONSTRAINT "tenant_users_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "public"."tenants"("id") ON DELETE CASCADE;

--
-- Name: cheques cheques_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."cheques"
    ADD CONSTRAINT "cheques_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."expense_categories"("id") ON DELETE SET NULL;

--
-- Name: cheques cheques_clearing_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."cheques"
    ADD CONSTRAINT "cheques_clearing_agent_id_fkey" FOREIGN KEY ("clearing_agent_id") REFERENCES "public"."clearing_agents"("id") ON DELETE SET NULL;

--
-- Name: cheques cheques_shareholder_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."cheques"
    ADD CONSTRAINT "cheques_shareholder_id_fkey" FOREIGN KEY ("shareholder_id") REFERENCES "public"."shareholders"("id") ON DELETE SET NULL;

--
-- Name: cheques cheques_shipping_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."cheques"
    ADD CONSTRAINT "cheques_shipping_company_id_fkey" FOREIGN KEY ("shipping_company_id") REFERENCES "public"."shipping_companies"("id") ON DELETE SET NULL;

--
-- Name: cheques cheques_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."cheques"
    ADD CONSTRAINT "cheques_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id") ON DELETE SET NULL;

--
-- Name: treasury_balances treasury_balances_account_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."treasury_balances"
    ADD CONSTRAINT "treasury_balances_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id");

--
-- Name: treasury_balances treasury_balances_treasury_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."treasury_balances"
    ADD CONSTRAINT "treasury_balances_treasury_id_fkey" FOREIGN KEY ("treasury_id") REFERENCES "public"."treasuries"("id") ON DELETE CASCADE;

--
-- Name: treasury_transactions treasury_transactions_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."treasury_transactions"
    ADD CONSTRAINT "treasury_transactions_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."expense_categories"("id");

--
-- Name: treasury_transactions treasury_transactions_clearing_agent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."treasury_transactions"
    ADD CONSTRAINT "treasury_transactions_clearing_agent_id_fkey" FOREIGN KEY ("clearing_agent_id") REFERENCES "public"."clearing_agents"("id") ON DELETE SET NULL;

--
-- Name: treasury_transactions treasury_transactions_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."treasury_transactions"
    ADD CONSTRAINT "treasury_transactions_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."users"("id") ON DELETE SET NULL;

--
-- Name: treasury_transactions treasury_transactions_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."treasury_transactions"
    ADD CONSTRAINT "treasury_transactions_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE SET NULL;

--
-- Name: treasury_transactions treasury_transactions_treasury_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."treasury_transactions"
    ADD CONSTRAINT "treasury_transactions_treasury_id_fkey" FOREIGN KEY ("treasury_id") REFERENCES "public"."treasuries"("id") ON DELETE CASCADE;

--
-- Name: treasury_transactions treasury_transactions_shareholder_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."treasury_transactions"
    ADD CONSTRAINT "treasury_transactions_shareholder_id_fkey" FOREIGN KEY ("shareholder_id") REFERENCES "public"."shareholders"("id") ON DELETE SET NULL;

--
-- Name: treasury_transactions treasury_transactions_shipping_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."treasury_transactions"
    ADD CONSTRAINT "treasury_transactions_shipping_company_id_fkey" FOREIGN KEY ("shipping_company_id") REFERENCES "public"."shipping_companies"("id") ON DELETE SET NULL;

--
-- Name: treasury_transactions treasury_transactions_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."treasury_transactions"
    ADD CONSTRAINT "treasury_transactions_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id") ON DELETE SET NULL;

--
-- Name: prep_center_cost_items prep_center_cost_items_shipment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."prep_center_cost_items"
    ADD CONSTRAINT "prep_center_cost_items_shipment_id_fkey" FOREIGN KEY ("shipment_id") REFERENCES "public"."export_shipments"("id") ON DELETE CASCADE;

--
-- Name: shareholder_profit_distributions shareholder_profit_distributions_shareholder_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shareholder_profit_distributions"
    ADD CONSTRAINT "shareholder_profit_distributions_shareholder_id_fkey" FOREIGN KEY ("shareholder_id") REFERENCES "public"."shareholders"("id");

--
-- Name: shareholder_profit_distributions shareholder_profit_distributions_shipment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shareholder_profit_distributions"
    ADD CONSTRAINT "shareholder_profit_distributions_shipment_id_fkey" FOREIGN KEY ("shipment_id") REFERENCES "public"."export_shipments"("id");

--
-- Name: shipment_cost_breakdown shipment_cost_breakdown_shipment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shipment_cost_breakdown"
    ADD CONSTRAINT "shipment_cost_breakdown_shipment_id_fkey" FOREIGN KEY ("shipment_id") REFERENCES "public"."export_shipments"("id") ON DELETE CASCADE;

--
-- Name: shipment_cost_items shipment_cost_items_report_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shipment_cost_items"
    ADD CONSTRAINT "shipment_cost_items_report_category_id_fkey" FOREIGN KEY ("report_category_id") REFERENCES "public"."cost_report_categories"("id");

--
-- Name: shipment_cost_items shipment_cost_items_shipment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shipment_cost_items"
    ADD CONSTRAINT "shipment_cost_items_shipment_id_fkey" FOREIGN KEY ("shipment_id") REFERENCES "public"."export_shipments"("id") ON DELETE CASCADE;

--
-- Name: shipment_profitability_snapshots shipment_profitability_snapshots_shipment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shipment_profitability_snapshots"
    ADD CONSTRAINT "shipment_profitability_snapshots_shipment_id_fkey" FOREIGN KEY ("shipment_id") REFERENCES "public"."export_shipments"("id") ON DELETE CASCADE;

--
-- Name: shipment_recipe_snapshots shipment_recipe_snapshots_packing_recipe_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shipment_recipe_snapshots"
    ADD CONSTRAINT "shipment_recipe_snapshots_packing_recipe_id_fkey" FOREIGN KEY ("packing_recipe_id") REFERENCES "public"."packing_recipes"("id");

--
-- Name: shipment_recipe_snapshots shipment_recipe_snapshots_shipment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shipment_recipe_snapshots"
    ADD CONSTRAINT "shipment_recipe_snapshots_shipment_id_fkey" FOREIGN KEY ("shipment_id") REFERENCES "public"."export_shipments"("id") ON DELETE CASCADE;

--
-- Name: supplier_settlements supplier_settlements_shipment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."supplier_settlements"
    ADD CONSTRAINT "supplier_settlements_shipment_id_fkey" FOREIGN KEY ("shipment_id") REFERENCES "public"."export_shipments"("id") ON DELETE CASCADE;

--
-- Name: supplier_settlements supplier_settlements_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."supplier_settlements"
    ADD CONSTRAINT "supplier_settlements_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id") ON DELETE RESTRICT;

--
-- Name: purchase_invoice_items purchase_invoice_items_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."purchase_invoice_items"
    ADD CONSTRAINT "purchase_invoice_items_invoice_id_fkey" FOREIGN KEY ("invoice_id") REFERENCES "public"."purchase_invoices"("id");

--
-- Name: station_product_batches station_product_batches_purchase_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."station_product_batches"
    ADD CONSTRAINT "station_product_batches_purchase_invoice_id_fkey" FOREIGN KEY ("purchase_invoice_id") REFERENCES "public"."purchase_invoices"("id") ON DELETE SET NULL;

--
-- Name: station_product_batches station_product_batches_station_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."station_product_batches"
    ADD CONSTRAINT "station_product_batches_station_id_fkey" FOREIGN KEY ("station_id") REFERENCES "public"."stations"("id") ON DELETE CASCADE;

--
-- Name: stock_batches stock_batches_purchase_invoice_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."stock_batches"
    ADD CONSTRAINT "stock_batches_purchase_invoice_id_fkey" FOREIGN KEY ("purchase_invoice_id") REFERENCES "public"."purchase_invoices"("id") ON DELETE SET NULL;

--
-- Name: stock_batches stock_batches_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."stock_batches"
    ADD CONSTRAINT "stock_batches_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id") ON DELETE RESTRICT;

--
-- Name: shipment_cost_allocations shipment_cost_allocations_shipment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shipment_cost_allocations"
    ADD CONSTRAINT "shipment_cost_allocations_shipment_id_fkey" FOREIGN KEY ("shipment_id") REFERENCES "public"."export_shipments"("id") ON DELETE CASCADE;

--
-- Name: shipment_cost_allocations shipment_cost_allocations_source_cost_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."shipment_cost_allocations"
    ADD CONSTRAINT "shipment_cost_allocations_source_cost_item_id_fkey" FOREIGN KEY ("source_cost_item_id") REFERENCES "public"."shipment_cost_items"("id") ON DELETE CASCADE;

--
-- Name: lot_receipts fk_lot_receipts_purchase_item; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."lot_receipts"
    ADD CONSTRAINT "fk_lot_receipts_purchase_item" FOREIGN KEY ("purchase_invoice_item_id") REFERENCES "public"."purchase_invoice_items"("id") ON DELETE SET NULL;

--
-- Name: lot_receipts lot_receipts_fruit_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."lot_receipts"
    ADD CONSTRAINT "lot_receipts_fruit_type_id_fkey" FOREIGN KEY ("fruit_type_id") REFERENCES "public"."fruit_types"("id") ON DELETE SET NULL;

--
-- Name: lot_receipts lot_receipts_station_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."lot_receipts"
    ADD CONSTRAINT "lot_receipts_station_id_fkey" FOREIGN KEY ("station_id") REFERENCES "public"."stations"("id") ON DELETE SET NULL;

--
-- Name: lot_receipts lot_receipts_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."lot_receipts"
    ADD CONSTRAINT "lot_receipts_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id") ON DELETE RESTRICT;

--
-- Name: stock_movements stock_movements_batch_id_fkey1; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."stock_movements"
    ADD CONSTRAINT "stock_movements_batch_id_fkey1" FOREIGN KEY ("batch_id") REFERENCES "public"."stock_batches"("id") ON DELETE SET NULL;

--
-- Name: lot_grading_results fk_lot_grading_stock_batch; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."lot_grading_results"
    ADD CONSTRAINT "fk_lot_grading_stock_batch" FOREIGN KEY ("stock_batch_id") REFERENCES "public"."stock_batches"("id") ON DELETE SET NULL;

--
-- Name: lot_grading_results lot_grading_results_lot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."lot_grading_results"
    ADD CONSTRAINT "lot_grading_results_lot_id_fkey" FOREIGN KEY ("lot_id") REFERENCES "public"."lot_receipts"("id") ON DELETE CASCADE;

--
-- Name: lot_returns lot_returns_lot_receipt_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."lot_returns"
    ADD CONSTRAINT "lot_returns_lot_receipt_id_fkey" FOREIGN KEY ("lot_receipt_id") REFERENCES "public"."lot_receipts"("id") ON DELETE CASCADE;

--
-- Name: lot_returns lot_returns_station_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."lot_returns"
    ADD CONSTRAINT "lot_returns_station_id_fkey" FOREIGN KEY ("station_id") REFERENCES "public"."stations"("id") ON DELETE SET NULL;

--
-- Name: lot_returns lot_returns_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."lot_returns"
    ADD CONSTRAINT "lot_returns_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id") ON DELETE SET NULL;

--
-- Name: packing_orders packing_orders_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."packing_orders"
    ADD CONSTRAINT "packing_orders_batch_id_fkey" FOREIGN KEY ("batch_id") REFERENCES "public"."stock_batches"("id") ON DELETE SET NULL;

--
-- Name: packing_orders packing_orders_export_shipment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."packing_orders"
    ADD CONSTRAINT "packing_orders_export_shipment_id_fkey" FOREIGN KEY ("export_shipment_id") REFERENCES "public"."export_shipments"("id") ON DELETE SET NULL;

--
-- Name: packing_orders packing_orders_fruit_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."packing_orders"
    ADD CONSTRAINT "packing_orders_fruit_type_id_fkey" FOREIGN KEY ("fruit_type_id") REFERENCES "public"."fruit_types"("id") ON DELETE RESTRICT;

--
-- Name: packing_orders packing_orders_lot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."packing_orders"
    ADD CONSTRAINT "packing_orders_lot_id_fkey" FOREIGN KEY ("lot_id") REFERENCES "public"."lot_receipts"("id") ON DELETE RESTRICT;

--
-- Name: packing_orders packing_orders_recipe_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."packing_orders"
    ADD CONSTRAINT "packing_orders_recipe_id_fkey" FOREIGN KEY ("recipe_id") REFERENCES "public"."packing_recipes"("id") ON DELETE SET NULL;

--
-- Name: packing_orders packing_orders_station_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."packing_orders"
    ADD CONSTRAINT "packing_orders_station_id_fkey" FOREIGN KEY ("station_id") REFERENCES "public"."stations"("id") ON DELETE SET NULL;

--
-- Name: export_shipment_items export_shipment_items_packing_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."export_shipment_items"
    ADD CONSTRAINT "export_shipment_items_packing_order_id_fkey" FOREIGN KEY ("packing_order_id") REFERENCES "public"."packing_orders"("id") ON DELETE SET NULL;

--
-- Name: export_shipment_items export_shipment_items_shipment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY "public"."export_shipment_items"
    ADD CONSTRAINT "export_shipment_items_shipment_id_fkey" FOREIGN KEY ("shipment_id") REFERENCES "public"."export_shipments"("id") ON DELETE CASCADE;

-- ==========================================
-- 6. GROUP B FUNCTIONS (TABLE/VIEW READERS)
-- ==========================================
--
-- Name: recalculate_all_supplier_balances_from_ledger(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."recalculate_all_supplier_balances_from_ledger"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_rec RECORD;
  v_new_balance NUMERIC;
  v_count INTEGER := 0;
BEGIN
  FOR v_rec IN SELECT id FROM suppliers
  LOOP
    v_new_balance := COALESCE((SELECT initial_balance FROM suppliers WHERE id = v_rec.id), 0);

    v_new_balance := v_new_balance + COALESCE((
      SELECT SUM(le.amount) FROM ledger_entries le
      WHERE le.entity_type = 'supplier' AND le.entity_id = v_rec.id::TEXT AND le.entry_type = 'credit'
    ), 0);

    v_new_balance := v_new_balance - COALESCE((
      SELECT SUM(le.amount) FROM ledger_entries le
      WHERE le.entity_type = 'supplier' AND le.entity_id = v_rec.id::TEXT AND le.entry_type = 'debit'
    ), 0);

    UPDATE suppliers SET outstanding_balance = v_new_balance, updated_at = now() WHERE id = v_rec.id;
    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'suppliers_recalculated', v_count);
END;
$$;

--
-- Name: validate_status_transition("text", "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."validate_status_transition"("p_current_status" "text", "p_new_status" "text") RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
BEGIN
  -- Valid transitions:
  -- DRAFT -> ACTIVE
  -- ACTIVE -> CLOSING, ARCHIVED
  -- CLOSING -> CLOSED, ACTIVE (if closing fails)
  -- CLOSED -> ARCHIVED, ACTIVE (reopen - emergency)
  -- ARCHIVED -> (no transition allowed)

  IF p_new_status = 'DRAFT' AND p_current_status = 'DRAFT' THEN
    RETURN TRUE;
  ELSIF p_new_status = 'ACTIVE' AND p_current_status IN ('DRAFT','CLOSING','CLOSED') THEN
    RETURN TRUE;
  ELSIF p_new_status = 'CLOSING' AND p_current_status = 'ACTIVE' THEN
    RETURN TRUE;
  ELSIF p_new_status = 'CLOSED' AND p_current_status = 'CLOSING' THEN
    RETURN TRUE;
  ELSIF p_new_status = 'ARCHIVED' AND p_current_status = 'CLOSED' THEN
    RETURN TRUE;
  ELSE
    RETURN FALSE;
  END IF;
END;
$$;

--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

--
-- Name: generate_shipment_number(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."generate_shipment_number"() RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_count BIGINT;
BEGIN
  SELECT COUNT(*) + 1 INTO v_count FROM export_shipments;
  RETURN 'EXP-' || lpad(v_count::TEXT, 4, '0');
END;
$$;

--
-- Name: find_duplicate_entries(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."find_duplicate_entries"("p_fiscal_year_id" bigint) RETURNS integer
    LANGUAGE "sql" STABLE
    AS $$
  SELECT COALESCE(SUM(duplicate_count - 1), 0)
  FROM (
    SELECT COUNT(*) AS duplicate_count
    FROM public.transactions t
    JOIN public.fiscal_years fy ON fy.id = p_fiscal_year_id
    WHERE COALESCE(t.transaction_date, t.created_at::date) BETWEEN fy.start_date AND fy.end_date
    GROUP BY
      COALESCE(t.transaction_date, t.created_at::date),
      t.account_id,
      t.debit,
      t.credit,
      COALESCE(t.description, '')
    HAVING COUNT(*) > 1
  ) dupes;
$$;

--
-- Name: get_pending_cheques_for_notification(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_pending_cheques_for_notification"("p_days_ahead" integer DEFAULT 3) RETURNS TABLE("id" bigint, "cheque_number" "text", "type" "text", "amount" numeric, "currency" "text", "due_date" "date", "counterparty_type" "text", "counterparty_id" bigint, "supplier_id" "uuid", "clearing_agent_id" bigint, "shipping_company_id" bigint, "shareholder_id" bigint, "counterparty_name" "text", "days_remaining" integer)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.id, c.cheque_number, c.type, c.amount, c.currency, c.due_date,
        c.counterparty_type, c.counterparty_id, c.supplier_id,
        c.clearing_agent_id, c.shipping_company_id, c.shareholder_id,
        COALESCE(
            CASE
                WHEN c.counterparty_type = 'customer' THEN (SELECT name FROM public.customers WHERE id = c.counterparty_id)
                WHEN c.counterparty_type = 'supplier' THEN (SELECT name FROM public.suppliers WHERE id = c.supplier_id)
                WHEN c.counterparty_type = 'clearing_agent' THEN (SELECT name FROM public.clearing_agents WHERE id = c.clearing_agent_id)
                WHEN c.counterparty_type = 'shipping_company' THEN (SELECT name FROM public.shipping_companies WHERE id = c.shipping_company_id)
                WHEN c.counterparty_type = 'shareholder' THEN (SELECT name FROM public.shareholders WHERE id = c.shareholder_id)
                ELSE NULL
            END,
            '—'
        ) AS counterparty_name,
        (c.due_date - CURRENT_DATE)::INTEGER AS days_remaining
    FROM public.cheques c
    WHERE c.status = 'pending'
      AND c.due_date BETWEEN CURRENT_DATE AND (CURRENT_DATE + p_days_ahead)
    ORDER BY c.due_date ASC;
END;
$$;

--
-- Name: update_last_verified_at("uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."update_last_verified_at"("p_user_id" "uuid") RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    AS $$ UPDATE profiles SET last_verified_at = now() WHERE id = p_user_id; $$;

--
-- Name: count_draft_transactions(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."count_draft_transactions"("p_fiscal_year_id" bigint) RETURNS integer
    LANGUAGE "sql" STABLE
    AS $$
  SELECT COUNT(*)::INTEGER
  FROM public.transactions t
  JOIN public.fiscal_years fy ON fy.id = p_fiscal_year_id
  WHERE COALESCE(t.transaction_date, t.created_at::date) BETWEEN fy.start_date AND fy.end_date
    AND (t.description ILIKE '%draft%' OR t.description ILIKE '%مسودة%');
$$;

--
-- Name: get_closing_progress(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_closing_progress"("p_fiscal_year_id" bigint) RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    AS $$
  SELECT COALESCE(
    (SELECT jsonb_build_object(
      'status', status,
      'progress_pct', progress_pct,
      'current_step', current_step,
      'started_at', started_at,
      'completed_at', completed_at,
      'error_message', error_message
    ) FROM public.fiscal_year_closing_progress
    WHERE fiscal_year_id = p_fiscal_year_id
    ORDER BY id DESC LIMIT 1),
    '{}'::jsonb
  );
$$;

--
-- Name: validate_trial_balance(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."validate_trial_balance"("p_fiscal_year_id" bigint) RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $$
  SELECT COALESCE(SUM(t.debit), 0) = COALESCE(SUM(t.credit), 0)
  FROM public.transactions t
  JOIN public.fiscal_years fy ON fy.id = p_fiscal_year_id
  WHERE COALESCE(t.transaction_date, t.created_at::date) BETWEEN fy.start_date AND fy.end_date;
$$;

--
-- Name: rpc_cancel_export_shipment(bigint, "uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."rpc_cancel_export_shipment"("p_shipment_id" bigint, "p_user_id" "uuid" DEFAULT "auth"."uid"()) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_shipment RECORD;
  v_total_revenue NUMERIC := 0;
  v_discount NUMERIC := 0;
  v_net_amount NUMERIC := 0;
  v_old_ledger_net NUMERIC := 0;
  v_desc TEXT;
  v_entry_number INTEGER;
  v_revenue_account_id INTEGER;
  v_ar_account_id INTEGER;
  v_treasury_id INTEGER;
BEGIN
  SELECT * INTO v_shipment FROM export_shipments WHERE id = p_shipment_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Shipment not found');
  END IF;

  IF v_shipment.status = 'cancelled' THEN
    RETURN jsonb_build_object('success', true, 'message', 'Already cancelled');
  END IF;

  IF v_shipment.status NOT IN ('confirmed', 'shipped', 'in_transit') THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Cannot cancel shipment in status: ' || v_shipment.status);
  END IF;

  SELECT COALESCE(SUM(amount), 0) INTO v_total_revenue
  FROM export_shipment_items WHERE shipment_id = p_shipment_id;

  v_discount := COALESCE(v_shipment.discount_amount, 0);
  v_net_amount := GREATEST(v_total_revenue - v_discount, 0);

  SELECT COALESCE(SUM(CASE WHEN entry_type = 'debit' THEN amount ELSE -amount END), 0)
  INTO v_old_ledger_net
  FROM ledger_entries
  WHERE entity_type = 'customer'
    AND entity_id = v_shipment.customer_id::TEXT
    AND reference_type = 'export_shipment'
    AND reference_text = p_shipment_id::TEXT;

  IF v_shipment.customer_id IS NOT NULL THEN
    UPDATE customers
    SET balance = COALESCE(balance, 0) - v_old_ledger_net, updated_at = now()
    WHERE id = v_shipment.customer_id;
  END IF;

  DELETE FROM ledger_entries
  WHERE entity_type = 'customer'
    AND entity_id = v_shipment.customer_id::TEXT
    AND reference_type = 'export_shipment'
    AND reference_text = p_shipment_id::TEXT;

  IF v_net_amount > 0 THEN
    v_desc := 'إلغاء شحنة تصدير رقم ' || v_shipment.shipment_number || ' - ' ||
              COALESCE(v_shipment.customer_name, '');
    INSERT INTO ledger_entries (
      entity_type, entity_id, entry_type, amount, currency,
      reference_type, reference_text, description, created_by
    ) VALUES (
      'customer', v_shipment.customer_id::TEXT, 'credit', v_net_amount,
      COALESCE(v_shipment.currency, 'USD'),
      'export_shipment_cancel', p_shipment_id::TEXT, v_desc, p_user_id
    );
  END IF;

  -- Dynamic account lookup from chart of accounts
  SELECT id INTO v_revenue_account_id FROM accounts WHERE account_code = '4000' LIMIT 1;
  IF v_revenue_account_id IS NULL THEN
    SELECT id INTO v_revenue_account_id FROM accounts WHERE account_type = 'revenue' LIMIT 1;
  END IF;

  SELECT id INTO v_ar_account_id FROM accounts WHERE account_code = '1020' LIMIT 1;
  IF v_ar_account_id IS NULL THEN
    SELECT id INTO v_ar_account_id FROM accounts WHERE account_type = 'asset' AND name LIKE '%عملاء%' LIMIT 1;
  END IF;

  SELECT COALESCE(MAX(entry_number), 0) + 1 INTO v_entry_number FROM transactions;
  v_desc := 'إلغاء شحنة تصدير رقم ' || v_shipment.shipment_number;

  IF v_net_amount > 0 AND v_revenue_account_id IS NOT NULL AND v_ar_account_id IS NOT NULL THEN
    BEGIN
      INSERT INTO transactions (
        account_id, debit, credit, description, date, created_at,
        entry_number, amount, transaction_date, currency_snapshot
      ) VALUES (
        v_revenue_account_id, v_net_amount, 0, v_desc, now(), now(),
        v_entry_number, v_net_amount, now(),
        jsonb_build_object('currency', COALESCE(v_shipment.currency, 'USD'), 'rate', 1)
      );

      INSERT INTO transactions (
        account_id, debit, credit, description, date, created_at,
        entry_number, amount, transaction_date, currency_snapshot
      ) VALUES (
        v_ar_account_id, 0, v_net_amount, v_desc, now(), now(),
        v_entry_number, v_net_amount, now(),
        jsonb_build_object('currency', COALESCE(v_shipment.currency, 'USD'), 'rate', 1)
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'journal entries insert failed: %', SQLERRM;
    END;
  END IF;

  -- Dynamic treasury lookup: use shipment's treasury_id if available, else first treasury
  v_treasury_id := v_shipment.treasury_id;
  IF v_treasury_id IS NULL THEN
    SELECT id INTO v_treasury_id FROM treasuries ORDER BY id LIMIT 1;
  END IF;

  IF v_treasury_id IS NOT NULL THEN
    BEGIN
      INSERT INTO treasury_transactions (
        treasury_id, type, amount, currency, description,
        reference_type, created_at, created_by, date, exchange_rate
      ) VALUES (
        v_treasury_id, 'expense', v_net_amount, COALESCE(v_shipment.currency, 'USD'),
        'إلغاء شحنة تصدير رقم ' || v_shipment.shipment_number ||
          COALESCE(' - ' || v_shipment.customer_name, ''),
        'export_shipment_cancel', now(), p_user_id, now(), 1
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'treasury_transactions insert failed: %', SQLERRM;
    END;
  END IF;

  UPDATE export_shipments
  SET status = 'cancelled', applied_discount_amount = v_discount, updated_at = now()
  WHERE id = p_shipment_id;

  RETURN jsonb_build_object(
    'success', true,
    'shipment_id', p_shipment_id,
    'total_revenue', v_total_revenue,
    'discount', v_discount,
    'net_amount', v_net_amount,
    'old_ledger_net', v_old_ledger_net,
    'message', 'Shipment cancelled with full accounting reversal'
  );
END;
$$;

--
-- Name: reverse_transaction(integer, "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."reverse_transaction"("p_treasury_tx_id" integer, "p_reason" "text" DEFAULT ''::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_tx RECORD;
    v_new_tx_id INTEGER;
    v_new_balance NUMERIC;
    v_old_balance NUMERIC;
    v_ledger_entry_id BIGINT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;

    SELECT * INTO v_tx FROM treasury_transactions WHERE id = p_treasury_tx_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'الحركة غير موجودة (id=%)', p_treasury_tx_id;
    END IF;

    IF v_tx.type NOT IN ('expense', 'withdrawal', 'deposit') THEN
        RAISE EXCEPTION 'لا يمكن عكس حركة من نوع %', v_tx.type;
    END IF;

    SELECT balance INTO v_old_balance
    FROM treasury_balances
    WHERE treasury_id = v_tx.treasury_id AND currency = v_tx.currency
    FOR UPDATE;

    IF v_tx.type IN ('expense', 'withdrawal') THEN
        v_new_balance := v_old_balance + v_tx.amount;
    ELSE
        v_new_balance := v_old_balance - v_tx.amount;
    END IF;

    IF v_new_balance < 0 THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ لعكس الحركة (المتوفر: %)', v_old_balance;
    END IF;

    UPDATE treasury_balances
    SET balance = v_new_balance
    WHERE treasury_id = v_tx.treasury_id AND currency = v_tx.currency;

    INSERT INTO treasury_transactions (
        treasury_id, type, currency, amount,
        balance_before, balance_after, description,
        category_id, customer_id, supplier_id, created_by
    ) VALUES (
        v_tx.treasury_id, v_tx.type || '_reversal', v_tx.currency, v_tx.amount,
        v_old_balance, v_new_balance,
        COALESCE(p_reason, 'إلغاء: ') || v_tx.description,
        v_tx.category_id, v_tx.customer_id, v_tx.supplier_id, auth.uid()
    )
    RETURNING id INTO v_new_tx_id;

    -- Reverse customer/supplier balance
    IF v_tx.customer_id IS NOT NULL THEN
        UPDATE customers SET balance = balance - v_tx.amount WHERE id = v_tx.customer_id;
        INSERT INTO ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('customer', v_tx.customer_id::TEXT, 'credit', v_tx.amount, v_tx.currency, 'reversal', v_new_tx_id, COALESCE(p_reason, 'إلغاء'), auth.uid())
        RETURNING id INTO v_ledger_entry_id;
    ELSIF v_tx.supplier_id IS NOT NULL THEN
        UPDATE suppliers SET outstanding_balance = outstanding_balance + v_tx.amount WHERE id = v_tx.supplier_id;
        INSERT INTO ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
        VALUES ('supplier', v_tx.supplier_id::TEXT, 'debit', v_tx.amount, v_tx.currency, 'reversal', v_new_tx_id, COALESCE(p_reason, 'إلغاء'), auth.uid())
        RETURNING id INTO v_ledger_entry_id;
    END IF;

    RETURN jsonb_build_object(
        'reversal_tx_id', v_new_tx_id,
        'ledger_entry_id', v_ledger_entry_id
    );
END;
$$;

--
-- Name: is_admin(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."is_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT COALESCE(
    (SELECT is_admin FROM public.users WHERE id = auth.uid() LIMIT 1),
    false
  );
$$;

--
-- Name: reverse_supplier_ledger_payment("uuid", numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."reverse_supplier_ledger_payment"("p_supplier_id" "uuid", "p_amount" numeric) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_deleted_id BIGINT;
BEGIN
    SELECT id INTO v_deleted_id
    FROM public.ledger_entries
    WHERE entity_type = 'supplier'
      AND entity_id = p_supplier_id::TEXT
      AND reference_type = 'payment'
      AND entry_type = 'credit'
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_deleted_id IS NOT NULL THEN
        DELETE FROM public.ledger_entries WHERE id = v_deleted_id;
    END IF;

    UPDATE public.suppliers
    SET outstanding_balance = outstanding_balance - p_amount
    WHERE id = p_supplier_id;

    RETURN jsonb_build_object('success', true, 'deleted_id', v_deleted_id);
END;
$$;

--
-- Name: _has_owner_safe(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."_has_owner_safe"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_roles ur
    WHERE ur.user_id = auth.uid()
      AND ur.allowed_pages ? '/owner-safe'
  )
$$;

--
-- Name: get_complete_dashboard_data(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_complete_dashboard_data"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_today_sales NUMERIC;
  v_monthly_sales NUMERIC;
  v_total_sales NUMERIC;
  v_total_purchases NUMERIC;
  v_total_expenses NUMERIC;
  v_net_profit NUMERIC;
  v_active_shipments INT;
  v_customer_count INT;
  v_supplier_count INT;
  v_product_count INT;
  v_low_stock_count INT;
  v_inventory_value NUMERIC;

  v_avg_invoice NUMERIC;
  v_profit_margin NUMERIC;
  v_collection_rate NUMERIC;
  v_inventory_turnover NUMERIC;

  v_monthly_sales_list JSONB;
  v_expense_dist_list JSONB;
  v_destinations_list JSONB;
  v_top_customers_list JSONB;
  v_top_products_list JSONB;
  v_recent_activities_list JSONB;
  v_upcoming_shipments_list JSONB;
  v_treasuries_list JSONB;
  v_banks_list JSONB;

  v_now DATE := CURRENT_DATE;
BEGIN
  -- 1. Sales Calculation
  v_today_sales :=
    (SELECT COALESCE(SUM(total_revenue_egp), 0) FROM public.export_shipments WHERE shipment_date = v_now AND status != 'cancelled') +
    (SELECT COALESCE(SUM(total_amount), 0) FROM public.sales_invoices WHERE invoice_date = v_now AND status != 'cancelled');

  v_monthly_sales :=
    (SELECT COALESCE(SUM(total_revenue_egp), 0) FROM public.export_shipments WHERE shipment_date >= date_trunc('month', v_now) AND status != 'cancelled') +
    (SELECT COALESCE(SUM(total_amount), 0) FROM public.sales_invoices WHERE invoice_date >= date_trunc('month', v_now) AND status != 'cancelled');

  v_total_sales :=
    (SELECT COALESCE(SUM(total_revenue_egp), 0) FROM public.export_shipments WHERE status != 'cancelled') +
    (SELECT COALESCE(SUM(total_amount), 0) FROM public.sales_invoices WHERE status != 'cancelled');

  -- 2. Purchases
  v_total_purchases := (SELECT COALESCE(SUM(total_amount), 0) FROM public.purchase_invoices WHERE status != 'cancelled');

  -- 3. Expenses
  v_total_expenses :=
    (SELECT COALESCE(SUM(amount), 0) FROM public.treasury_transactions WHERE type = 'expense') +
    (SELECT COALESCE(SUM(amount), 0) FROM public.cashbox_transactions WHERE transaction_type = 'expense');

  -- 4. Net Profit
  v_net_profit :=
    (SELECT COALESCE(SUM(net_profit_egp), 0) FROM public.export_shipments WHERE status != 'cancelled') - v_total_expenses;

  -- 5. Counts
  v_active_shipments := (SELECT COUNT(*) FROM public.export_shipments WHERE status IN ('preparing', 'ready', 'shipped', 'in_transit'));
  v_customer_count := (SELECT COUNT(*) FROM public.customers);
  v_supplier_count := (SELECT COUNT(*) FROM public.suppliers);
  v_product_count := (SELECT COUNT(*) FROM public.fruit_types);

  -- 6. Low stock: skip (fruit_types has no minimum_stock)
  v_low_stock_count := 0;

  -- 7. Inventory Value
  v_inventory_value := (SELECT COALESCE(SUM(remaining_quantity * purchase_cost), 0) FROM public.stock_batches WHERE status = 'active');

  -- 8. Analytics KPIs
  v_avg_invoice := COALESCE(
    v_total_sales / NULLIF(
      (SELECT COUNT(*) FROM public.export_shipments WHERE status != 'cancelled') +
      (SELECT COUNT(*) FROM public.sales_invoices WHERE status != 'cancelled'), 0
    ), 0
  );
  v_profit_margin := COALESCE((v_net_profit / NULLIF(v_total_sales, 0)) * 100, 0);
  v_collection_rate := COALESCE(
    (
      (SELECT COALESCE(SUM(total_revenue_egp), 0) FROM public.export_shipments WHERE status != 'cancelled' AND payment_terms = 'Cash')
      + (SELECT COALESCE(SUM(paid_amount), 0) FROM public.sales_invoices WHERE status != 'cancelled')
    ) / NULLIF(v_total_sales, 0) * 100, 100
  );
  v_inventory_turnover := COALESCE(
    (SELECT COALESCE(SUM(total_fruit_cost), 0) FROM public.export_shipments WHERE status != 'cancelled') /
    NULLIF(v_inventory_value, 0), 1.2
  );

  -- 9. Sales Last 30 Days
  SELECT COALESCE(jsonb_agg(t), '[]'::jsonb) INTO v_monthly_sales_list FROM (
    SELECT
      to_char(d, 'MM/DD') as date,
      COALESCE(SUM(s.val), 0) as sales
    FROM generate_series(CURRENT_DATE - INTERVAL '29 days', CURRENT_DATE, '1 day'::interval) d
    LEFT JOIN (
      SELECT shipment_date as dt, total_revenue_egp as val FROM public.export_shipments WHERE status != 'cancelled'
      UNION ALL
      SELECT invoice_date as dt, total_amount as val FROM public.sales_invoices WHERE status != 'cancelled'
    ) s ON s.dt = d::date
    GROUP BY d ORDER BY d
  ) t;

  -- 10. Expense Distribution
  SELECT COALESCE(jsonb_agg(t), '[]'::jsonb) INTO v_expense_dist_list FROM (
    SELECT
      COALESCE(c.name, tx.description, 'أخرى') as name,
      SUM(tx.amount) as value
    FROM (
      SELECT amount, description, category_id FROM public.treasury_transactions WHERE type = 'expense'
      UNION ALL
      SELECT amount, description, NULL as category_id FROM public.cashbox_transactions WHERE transaction_type = 'expense'
    ) tx
    LEFT JOIN public.expense_categories c ON tx.category_id = c.id
    GROUP BY COALESCE(c.name, tx.description, 'أخرى')
    ORDER BY value DESC LIMIT 8
  ) t;

  -- 11. Destinations
  SELECT COALESCE(jsonb_agg(t), '[]'::jsonb) INTO v_destinations_list FROM (
    SELECT COALESCE(NULLIF(destination_country, ''), 'أخرى') as name, COUNT(*) as count
    FROM public.export_shipments WHERE status != 'cancelled'
    GROUP BY COALESCE(NULLIF(destination_country, ''), 'أخرى')
    ORDER BY count DESC LIMIT 6
  ) t;

  -- 12. Top Customers
  SELECT COALESCE(jsonb_agg(t), '[]'::jsonb) INTO v_top_customers_list FROM (
    SELECT name, SUM(val) as total
    FROM (
      SELECT customer_name as name, total_revenue_egp as val FROM public.export_shipments WHERE status != 'cancelled' AND customer_name IS NOT NULL
      UNION ALL
      SELECT c.name, inv.total_amount as val FROM public.sales_invoices inv JOIN public.customers c ON inv.customer_id = c.id WHERE inv.status != 'cancelled'
    ) s
    GROUP BY name ORDER BY total DESC LIMIT 5
  ) t;

  -- 13. Top Products
  SELECT COALESCE(jsonb_agg(t), '[]'::jsonb) INTO v_top_products_list FROM (
    SELECT product_name as name, SUM(quantity) as quantity, SUM(amount) as value
    FROM public.export_shipment_items
    GROUP BY product_name ORDER BY quantity DESC LIMIT 10
  ) t;

  -- 14. Upcoming Shipments
  SELECT COALESCE(jsonb_agg(t), '[]'::jsonb) INTO v_upcoming_shipments_list FROM (
    SELECT id, shipment_no, COALESCE(port_of_destination, destination_country, '—') as destination, shipment_date::text as date, status
    FROM public.export_shipments
    WHERE shipment_date >= CURRENT_DATE AND status IN ('preparing', 'ready')
    ORDER BY shipment_date ASC LIMIT 10
  ) t;

  -- 15. Treasury Balances
  SELECT COALESCE(jsonb_agg(t), '[]'::jsonb) INTO v_treasuries_list FROM (
    SELECT tr.name, tb.balance, tb.currency
    FROM public.treasuries tr
    JOIN public.treasury_balances tb ON tr.id = tb.treasury_id
  ) t;

  -- 16. Bank Balances
  SELECT COALESCE(jsonb_agg(t), '[]'::jsonb) INTO v_banks_list FROM (
    SELECT name, balance, currency FROM public.bank_accounts
  ) t;

  -- 17. Recent Activities
  SELECT COALESCE(jsonb_agg(t), '[]'::jsonb) INTO v_recent_activities_list FROM (
    SELECT type, title, created_at::text as time FROM (
      SELECT 'shipment' as type, 'تم إنشاء شحنة ' || shipment_no as title, created_at FROM public.export_shipments
      UNION ALL
      SELECT 'customer' as type, 'تم إضافة عميل ' || name as title, created_at FROM public.customers
      UNION ALL
      SELECT 'supplier' as type, 'تم إضافة مورد ' || name as title, created_at FROM public.suppliers
      UNION ALL
      SELECT 'purchase' as type, 'تم تسجيل فاتورة شراء ' || invoice_number as title, created_at FROM public.purchase_invoices
      UNION ALL
      SELECT 'invoice' as type, 'تم تسجيل فاتورة مبيعات ' || invoice_number as title, created_at FROM public.sales_invoices
    ) act
    ORDER BY created_at DESC LIMIT 10
  ) t;

  RETURN jsonb_build_object(
    'today_sales', v_today_sales,
    'monthly_sales_val', v_monthly_sales,
    'total_sales_val', v_total_sales,
    'total_purchases', v_total_purchases,
    'total_expenses', v_total_expenses,
    'net_profit', v_net_profit,
    'active_shipments_count', v_active_shipments,
    'customer_count', v_customer_count,
    'supplier_count', v_supplier_count,
    'product_count', v_product_count,
    'low_stock_count', v_low_stock_count,
    'inventory_value', v_inventory_value,
    'quick_analytics', jsonb_build_object(
      'avgInvoice', v_avg_invoice,
      'profitMargin', v_profit_margin,
      'collectionRate', v_collection_rate,
      'inventoryTurnover', v_inventory_turnover
    ),
    'monthly_sales', v_monthly_sales_list,
    'expense_distribution', v_expense_dist_list,
    'export_destinations', v_destinations_list,
    'top_customers', v_top_customers_list,
    'top_products', v_top_products_list,
    'upcoming_shipments', v_upcoming_shipments_list,
    'treasury_balances', v_treasuries_list,
    'bank_balances', v_banks_list,
    'recent_activities', v_recent_activities_list
  );
END;
$$;

--
-- Name: withdraw_bank_account(integer, numeric, "text", "text", "text", "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."withdraw_bank_account"("p_account_id" integer, "p_amount" numeric, "p_description" "text" DEFAULT NULL::"text", "p_entity_type" "text" DEFAULT NULL::"text", "p_entity_id" "text" DEFAULT NULL::"text", "p_counterparty_name" "text" DEFAULT NULL::"text") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_current_balance NUMERIC;
  v_new_balance     NUMERIC;
  v_tx_id           INTEGER;
BEGIN
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
  END IF;

  SELECT balance INTO v_current_balance FROM public.bank_accounts WHERE id = p_account_id;
  IF v_current_balance < p_amount THEN
    RAISE EXCEPTION 'الرصيد غير كافٍ (المتوفر: %)', v_current_balance;
  END IF;

  UPDATE public.bank_accounts
  SET balance = balance - p_amount
  WHERE id = p_account_id
  RETURNING balance INTO v_new_balance;

  INSERT INTO public.bank_account_transactions
    (bank_account_id, type, amount, balance_before, balance_after, description, created_by, entity_type, entity_id, counterparty_name)
  VALUES
    (p_account_id, 'withdraw', p_amount, v_new_balance + p_amount, v_new_balance, p_description, auth.uid(), p_entity_type, p_entity_id, p_counterparty_name)
  RETURNING id INTO v_tx_id;

  RETURN json_build_object('id', v_tx_id, 'balance', v_new_balance);
END;
$$;

--
-- Name: rpc_update_packing_costs_for_lot(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."rpc_update_packing_costs_for_lot"("p_lot_id" bigint) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_lot RECORD;
  v_order RECORD;
  v_updated INTEGER := 0;
  v_batches_updated INTEGER := 0;
  v_new_fruit_cost NUMERIC;
  v_new_packing_per_carton NUMERIC;
  v_is_carton BOOLEAN;
  v_cost_per_kg_egp NUMERIC;
  v_new_batch_unit_cost NUMERIC;
  v_qty NUMERIC;
BEGIN
  SELECT * INTO v_lot FROM lot_receipts WHERE id = p_lot_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Lot not found');
  END IF;

  v_is_carton := COALESCE(v_lot.purchase_mode, 'weight') = 'carton';
  v_cost_per_kg_egp := COALESCE(v_lot.fruit_cost_per_kg, 0) * COALESCE(v_lot.exchange_rate, 1);

  IF v_is_carton THEN
    v_qty := 0;
    IF COALESCE(v_lot.weight_per_carton_kg, 0) > 0 THEN
      v_qty := COALESCE(v_lot.net_weight_kg, 0) / v_lot.weight_per_carton_kg;
    END IF;
    IF v_qty = 0 THEN
      v_qty := COALESCE(v_lot.carton_count, 0);
    END IF;
  ELSE
    v_qty := COALESCE(NULLIF(v_lot.net_weight_kg, 0), v_lot.gross_weight_kg, 0);
  END IF;

  IF v_qty > 0 THEN
    v_new_batch_unit_cost := COALESCE(v_lot.total_fruit_cost, 0) / v_qty;
  ELSE
    v_new_batch_unit_cost := CASE WHEN v_is_carton THEN COALESCE(v_lot.price_per_carton, 0) ELSE COALESCE(v_lot.fruit_cost_per_kg, 0) END;
  END IF;

  UPDATE station_product_batches
  SET unit_cost = v_new_batch_unit_cost,
      currency = COALESCE(v_lot.currency, (SELECT currency FROM suppliers WHERE id = v_lot.supplier_id), 'EGP'),
      exchange_rate = COALESCE(v_lot.exchange_rate, 1)
  WHERE product_code = v_lot.lot_number;

  GET DIAGNOSTICS v_batches_updated = ROW_COUNT;

  FOR v_order IN
    SELECT id, carton_count, total_net_weight, actual_material_cost, notes
    FROM packing_orders
    WHERE lot_id = p_lot_id
  LOOP
    IF COALESCE(v_order.total_net_weight, 0) > 0 THEN
      v_new_fruit_cost := v_order.total_net_weight * v_cost_per_kg_egp;
    ELSE
      DECLARE
        v_notes_used NUMERIC := 0;
        v_notes_sorted NUMERIC := 0;
        v_notes_net NUMERIC := 0;
      BEGIN
        IF v_order.notes IS NOT NULL THEN
          BEGIN
            v_notes_used := COALESCE((v_order.notes->>'used_crop_weight')::NUMERIC, 0);
            v_notes_sorted := COALESCE((v_order.notes->>'sorted_waste_weight')::NUMERIC, 0);
            v_notes_net := v_notes_used - v_notes_sorted;
          EXCEPTION WHEN OTHERS THEN
            v_notes_net := 0;
          END;
        END IF;

        IF v_notes_net > 0 THEN
          v_new_fruit_cost := v_notes_net * v_cost_per_kg_egp;
        ELSE
          v_new_fruit_cost := 0;
        END IF;
      END;
    END IF;

    IF COALESCE(v_order.carton_count, 0) > 0 THEN
      v_new_packing_per_carton := (v_new_fruit_cost + COALESCE(v_order.actual_material_cost, 0)) / v_order.carton_count;
    ELSE
      v_new_packing_per_carton := 0;
    END IF;

    UPDATE packing_orders
    SET fruit_cost_allocated = v_new_fruit_cost,
        fruit_cost_base = v_new_fruit_cost,
        total_cost = v_new_fruit_cost + COALESCE(actual_material_cost, 0) + COALESCE(other_cost_base, 0),
        cost_per_carton = CASE WHEN carton_count > 0 THEN (v_new_fruit_cost + COALESCE(actual_material_cost, 0) + COALESCE(other_cost_base, 0)) / carton_count ELSE 0 END,
        updated_at = now()
    WHERE id = v_order.id;

    v_updated := v_updated + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'packing_orders_updated', v_updated,
    'station_batches_updated', v_batches_updated,
    'new_batch_unit_cost', v_new_batch_unit_cost
  );
END;
$$;

--
-- Name: auto_link_user_to_tenant(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."auto_link_user_to_tenant"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_tenant_id UUID;
BEGIN
  -- Find first active ERP tenant
  SELECT id INTO v_tenant_id
  FROM public.tenants
  WHERE is_active = true AND tenant_type = 'erp'
  ORDER BY created_at ASC
  LIMIT 1;

  IF v_tenant_id IS NOT NULL THEN
    -- Insert only if not already linked
    INSERT INTO public.tenant_users (tenant_id, user_id, role)
    VALUES (v_tenant_id, NEW.id, 'user')
    ON CONFLICT (tenant_id, user_id) DO NOTHING;

    -- Increment current_users
    UPDATE public.tenants
    SET current_users = (
      SELECT COUNT(*) FROM public.tenant_users WHERE tenant_id = v_tenant_id
    )
    WHERE id = v_tenant_id;
  END IF;

  RETURN NEW;
END;
$$;

--
-- Name: delete_treasury_ledger(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."delete_treasury_ledger"("p_reference_id" bigint) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_count INTEGER := 0;
BEGIN
    DELETE FROM public.ledger_entries
    WHERE reference_id = p_reference_id;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    RETURN jsonb_build_object('success', true, 'entries_deleted', v_count);
END;
$$;

--
-- Name: replace_supplier_ledger_payment("uuid", numeric, numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."replace_supplier_ledger_payment"("p_supplier_id" "uuid", "p_old_amount" numeric, "p_new_amount" numeric) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_deleted_id BIGINT;
BEGIN
    -- حذف القيد القديم
    SELECT id INTO v_deleted_id
    FROM public.ledger_entries
    WHERE entity_type = 'supplier'
      AND entity_id = p_supplier_id::TEXT
      AND reference_type = 'payment'
      AND entry_type = 'credit'
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_deleted_id IS NOT NULL THEN
        DELETE FROM public.ledger_entries WHERE id = v_deleted_id;
    END IF;

    -- إنشاء قيد جديد بالقيمة الصحيحة
    INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, reference_type, description, created_by)
    VALUES ('supplier', p_supplier_id::TEXT, 'credit', p_new_amount, 'payment', 'استلام من المورد', auth.uid());

    -- تعديل outstanding_balance: طرح القديم + إضافة الجديد
    UPDATE public.suppliers
    SET outstanding_balance = outstanding_balance - p_old_amount + p_new_amount
    WHERE id = p_supplier_id;

    RETURN jsonb_build_object('success', true, 'deleted_id', v_deleted_id);
END;
$$;

--
-- Name: cancel_cheque(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."cancel_cheque"("p_cheque_id" bigint) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_status TEXT;
BEGIN
    SELECT status INTO v_status
    FROM public.cheques
    WHERE id = p_cheque_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'الشيك غير موجود';
    END IF;

    IF v_status != 'pending' THEN
        RAISE EXCEPTION 'لا يمكن إلغاء شيك بحالة %', v_status;
    END IF;

    UPDATE public.cheques
    SET status = 'cancelled', cancelled_at = NOW()
    WHERE id = p_cheque_id;

    RETURN jsonb_build_object('success', true);
END;
$$;

--
-- Name: rpc_process_lot_receipt(bigint, numeric, "uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."rpc_process_lot_receipt"("p_lot_id" bigint, "p_unit_cost_kg" numeric DEFAULT NULL::numeric, "p_user_id" "uuid" DEFAULT "auth"."uid"()) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_lot                  RECORD;
  v_is_first_time       BOOLEAN := FALSE;
  v_old_total_cost       NUMERIC := 0;
  v_total_cartons        NUMERIC := 0;
  v_net_cartons          NUMERIC := 0;
  v_unit_cost            NUMERIC := 0;
  v_total_cost           NUMERIC := 0;
  v_total_graded         NUMERIC := 0;
  v_actual_graded        NUMERIC := 0;
  v_effective_cost       NUMERIC := 0;
  v_grading              RECORD;
  v_batch_id             INTEGER;
  v_batch_cost           NUMERIC;
  v_batch_number         TEXT;
  v_product_name         TEXT;
  v_desc                 TEXT;
  v_station_rows_affected INTEGER := 0;
  v_station_product_qty  NUMERIC := 0;
  v_batches_created      INTEGER := 0;
  v_unit_str             TEXT := 'kg';
  v_reverse_gross        NUMERIC := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'غير مصرح لك بإجراء هذه العملية';
  END IF;

  SELECT lr.* INTO v_lot FROM lot_receipts lr WHERE lr.id = p_lot_id FOR UPDATE OF lr;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'رقم استلام المحصول غير موجود (id=%)', p_lot_id;
  END IF;

  IF COALESCE(v_lot.purchase_mode, 'weight') = 'carton' THEN
    v_unit_str := 'carton';
    v_total_cartons := COALESCE(v_lot.carton_count, 0);
    v_unit_cost := COALESCE(v_lot.price_per_carton, 0);
    v_reverse_gross := COALESCE(v_lot.processed_gross_weight_kg, 0);

    -- Net cartons = net_weight_kg / weight_per_carton_kg (user-entered net field)
    IF COALESCE(v_lot.weight_per_carton_kg, 0) > 0 THEN
      v_net_cartons := ROUND(COALESCE(v_lot.net_weight_kg, 0) / v_lot.weight_per_carton_kg);
    ELSE
      v_net_cartons := v_total_cartons;
    END IF;
    IF v_net_cartons < 0 THEN v_net_cartons := 0; END IF;
  ELSE
    v_unit_str := 'kg';
    v_net_cartons := COALESCE(v_lot.net_weight_kg, v_lot.gross_weight_kg, 0);
    v_unit_cost := COALESCE(NULLIF(p_unit_cost_kg, 0), 0);
    IF v_unit_cost <= 0 AND v_lot.purchase_invoice_item_id IS NOT NULL THEN
      SELECT COALESCE(unit_cost, 0) INTO v_unit_cost FROM purchase_invoice_items WHERE id = v_lot.purchase_invoice_item_id;
    END IF;
    IF v_unit_cost <= 0 THEN
      v_unit_cost := COALESCE(v_lot.fruit_cost_per_kg, 0);
    END IF;
    v_reverse_gross := COALESCE(v_lot.processed_gross_weight_kg, 0);
  END IF;

  IF v_lot.processed_gross_weight_kg IS NULL OR v_lot.processed_gross_weight_kg = 0 THEN
    v_is_first_time := TRUE;
    v_old_total_cost := 0;
  ELSE
    v_is_first_time := FALSE;
    v_old_total_cost := COALESCE(v_lot.total_fruit_cost, 0);
  END IF;

  v_product_name := COALESCE(v_lot.product_name, 'منتجل');
  -- Cost: carton mode uses total_cartons * price_per_carton; weight mode uses gross_weight_kg * unit_cost
  v_total_cost := CASE WHEN v_unit_str = 'carton' THEN v_total_cartons * v_unit_cost ELSE COALESCE(v_net_cartons, 0) * v_unit_cost END;

  IF v_lot.supplier_id IS NOT NULL AND v_total_cost <= 0 AND v_net_cartons > 0 THEN
    RAISE EXCEPTION 'يرجى إدخال سعر التكلفة';
  END IF;

  -- Reverse OLD RAW STOCK from station_products using processed_gross_weight_kg
  IF NOT v_is_first_time AND v_lot.station_id IS NOT NULL AND v_reverse_gross > 0 THEN
    UPDATE station_products
      SET quantity = GREATEST(COALESCE(quantity, 0) - v_reverse_gross, 0),
          updated_at = now()
    WHERE station_id = v_lot.station_id AND fruit_type_id = v_lot.fruit_type_id AND unit = v_unit_str;

    DELETE FROM station_products
    WHERE station_id = v_lot.station_id AND fruit_type_id = v_lot.fruit_type_id AND unit = v_unit_str
      AND COALESCE(quantity, 0) <= 0;
  END IF;

  DELETE FROM stock_movements WHERE reference_type = 'lot_grading' AND description LIKE ('%' || v_lot.lot_number || '%');
  UPDATE lot_grading_results SET stock_batch_id = NULL WHERE lot_id = p_lot_id;
  DELETE FROM stock_batches WHERE batch_number LIKE ('G-' || v_lot.lot_number || '-%');

  UPDATE lot_receipts
  SET fruit_cost_per_kg = CASE WHEN v_unit_str = 'carton' THEN v_lot.fruit_cost_per_kg ELSE v_unit_cost END,
      total_fruit_cost = v_total_cost,
      processed_gross_weight_kg = CASE WHEN v_unit_str = 'carton' THEN v_net_cartons ELSE COALESCE(v_lot.net_weight_kg, v_net_cartons) END,
      updated_at = now()
  WHERE id = p_lot_id;

  IF v_lot.supplier_id IS NOT NULL THEN
    IF NOT v_is_first_time AND v_old_total_cost > 0 THEN
      DELETE FROM ledger_entries
      WHERE entity_type = 'supplier'
        AND entity_id = v_lot.supplier_id::TEXT
        AND reference_type = 'lot_receipt'
        AND reference_text = p_lot_id::TEXT;
    END IF;

    IF v_total_cost > 0 THEN
      v_desc := 'استلام محصول ' || v_lot.lot_number || ' - ' || v_product_name;
      INSERT INTO ledger_entries
        (entity_type, entity_id, entry_type, amount, currency,
         reference_type, reference_text, description, created_by)
      VALUES
        ('supplier', v_lot.supplier_id::TEXT, 'credit',
         v_total_cost, 'EGP',
         'lot_receipt', p_lot_id::TEXT,
         v_desc, p_user_id);
    END IF;

    UPDATE suppliers SET outstanding_balance = COALESCE(outstanding_balance, 0) - v_old_total_cost + v_total_cost WHERE id = v_lot.supplier_id;
  END IF;

  IF v_lot.station_id IS NOT NULL THEN
    INSERT INTO station_products (station_id, fruit_type_id, product_name, product_code, quantity, unit)
    VALUES (v_lot.station_id, v_lot.fruit_type_id, v_product_name, v_lot.lot_number, v_net_cartons, v_unit_str)
    ON CONFLICT (station_id, fruit_type_id, unit) DO UPDATE
      SET quantity     = station_products.quantity + EXCLUDED.quantity,
          product_name = EXCLUDED.product_name,
          product_code = EXCLUDED.product_code,
          updated_at   = now();

    GET DIAGNOSTICS v_station_rows_affected = ROW_COUNT;

    SELECT COALESCE(quantity, 0)
    INTO v_station_product_qty
    FROM station_products
    WHERE station_id = v_lot.station_id AND fruit_type_id = v_lot.fruit_type_id AND unit = v_unit_str
    LIMIT 1;
  END IF;

  SELECT COALESCE(SUM(weight_kg), 0) INTO v_actual_graded
  FROM lot_grading_results
  WHERE lot_id = p_lot_id AND grade IN ('A','B','C') AND weight_kg > 0;

  IF v_actual_graded <= 0 THEN
    v_total_graded := CASE WHEN v_unit_str = 'carton' THEN v_net_cartons ELSE COALESCE(v_lot.net_weight_kg, 0) END;
    v_effective_cost := CASE WHEN v_total_graded > 0 THEN v_total_cost / v_total_graded ELSE 0 END;

    UPDATE lot_receipts SET status = 'received', updated_at = now() WHERE id = p_lot_id;
    RETURN jsonb_build_object(
      'success', true,
      'lot_id', p_lot_id,
      'lot_number', v_lot.lot_number,
      'station_id', v_lot.station_id,
      'fruit_type_id', v_lot.fruit_type_id,
      'total_cost', v_total_cost,
      'unit_cost_kg', v_unit_cost,
      'effective_cost_kg', v_effective_cost,
      'total_graded', v_total_graded,
      'batches_created', 0,
      'station_products_upserted', v_station_rows_affected,
      'station_product_qty', v_station_product_qty,
      'message', 'No grading rows'
    );
  END IF;

  v_total_graded := v_actual_graded;
  v_effective_cost := CASE WHEN v_total_graded > 0 THEN v_total_cost / v_total_graded ELSE 0 END;

  FOR v_grading IN
    SELECT id, grade, weight_kg FROM lot_grading_results
    WHERE lot_id = p_lot_id AND grade IN ('A','B','C') AND weight_kg > 0
    ORDER BY grade
  LOOP
    v_batch_cost := v_grading.weight_kg * v_effective_cost;
    v_batch_number := 'G-' || v_lot.lot_number || '-' || v_grading.grade;
    INSERT INTO stock_batches
      (batch_number, supplier_id, quantity, remaining_quantity,
       purchase_cost, quality_grade, fruit_category,
       notes, status, user_id)
    VALUES
      (v_batch_number, v_lot.supplier_id,
       v_grading.weight_kg, v_grading.weight_kg,
       v_effective_cost, v_grading.grade, v_product_name,
       'من محصول ' || v_lot.lot_number || ' - فرز ' || v_grading.grade,
       'active', p_user_id)
    RETURNING id INTO v_batch_id;
    v_batches_created := v_batches_created + 1;
    UPDATE lot_grading_results SET stock_batch_id = v_batch_id WHERE id = v_grading.id;
    INSERT INTO stock_movements
      (movement_type, batch_id, quantity, before_quantity, after_quantity,
       unit_cost, total_cost, reference_type, description, user_id)
    VALUES
      ('adjustment', v_batch_id, v_grading.weight_kg, 0, 0,
       v_effective_cost, v_batch_cost, 'lot_grading',
       'إضافة رصيد من محصول ' || v_lot.lot_number || ' فرز ' || v_grading.grade,
       p_user_id);
  END LOOP;

  UPDATE lot_receipts SET status = 'sorting', updated_at = now() WHERE id = p_lot_id;

  RETURN jsonb_build_object(
    'success', true,
    'lot_id', p_lot_id,
    'lot_number', v_lot.lot_number,
    'station_id', v_lot.station_id,
    'fruit_type_id', v_lot.fruit_type_id,
    'total_cost', v_total_cost,
    'unit_cost_kg', v_unit_cost,
    'effective_cost_kg', v_effective_cost,
    'total_graded', v_total_graded,
    'batches_created', v_batches_created,
    'station_products_upserted', v_station_rows_affected,
    'station_product_qty', v_station_product_qty
  );
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'حدث خطأ أثناء معالجة المحصول: %', SQLERRM;
END;
$$;

--
-- Name: get_account_totals("text", bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_account_totals"("p_account_code" "text", "p_fiscal_year_id" bigint) RETURNS TABLE("total_debit" numeric, "total_credit" numeric)
    LANGUAGE "sql" STABLE
    AS $$
  SELECT
    COALESCE(SUM(t.debit), 0)::numeric,
    COALESCE(SUM(t.credit), 0)::numeric
  FROM public.transactions t
  JOIN public.accounts a ON t.account_id::text = a.id::text
  JOIN public.fiscal_years fy ON fy.id = p_fiscal_year_id
  WHERE a.account_code = p_account_code
    AND COALESCE(t.transaction_date, t.created_at::date) BETWEEN fy.start_date AND fy.end_date;
$$;

--
-- Name: count_broken_fifo_layers(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."count_broken_fifo_layers"() RETURNS integer
    LANGUAGE "sql" STABLE
    AS $$
  SELECT COUNT(*)::INTEGER
  FROM public.stock_batches
  WHERE quantity < remaining_quantity;
$$;

--
-- Name: update_treasury_ledger(bigint, numeric, "text", "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."update_treasury_ledger"("p_reference_id" bigint, "p_new_amount" numeric, "p_new_entry_type" "text" DEFAULT NULL::"text", "p_new_reference_type" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_rec RECORD;
BEGIN
    SELECT id, entity_type, entity_id, entry_type, amount INTO v_rec
    FROM public.ledger_entries
    WHERE reference_id = p_reference_id
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_rec IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'entry_not_found');
    END IF;

    -- Reverse old effect
    IF v_rec.entity_type = 'customer' THEN
        IF v_rec.entry_type = 'debit' THEN
            UPDATE public.customers SET balance = balance - v_rec.amount WHERE id = v_rec.entity_id::INTEGER;
        ELSE
            UPDATE public.customers SET balance = balance + v_rec.amount WHERE id = v_rec.entity_id::INTEGER;
        END IF;
    ELSIF v_rec.entity_type = 'supplier' THEN
        IF v_rec.entry_type = 'credit' THEN
            UPDATE public.suppliers SET outstanding_balance = outstanding_balance - v_rec.amount WHERE id = v_rec.entity_id::UUID;
        ELSE
            UPDATE public.suppliers SET outstanding_balance = outstanding_balance + v_rec.amount WHERE id = v_rec.entity_id::UUID;
        END IF;
    ELSIF v_rec.entity_type = 'clearing_agent' THEN
        UPDATE public.clearing_agents
        SET manual_adjustment = COALESCE(manual_adjustment, 0) + CASE WHEN v_rec.entry_type = 'credit' THEN -v_rec.amount ELSE v_rec.amount END,
            balance = COALESCE(balance, 0) + CASE WHEN v_rec.entry_type = 'credit' THEN -v_rec.amount ELSE v_rec.amount END
        WHERE id = v_rec.entity_id::INTEGER;
    ELSIF v_rec.entity_type = 'shipping_company' THEN
        UPDATE public.shipping_companies
        SET manual_adjustment = COALESCE(manual_adjustment, 0) + CASE WHEN v_rec.entry_type = 'credit' THEN -v_rec.amount ELSE v_rec.amount END,
            balance = COALESCE(balance, 0) + CASE WHEN v_rec.entry_type = 'credit' THEN -v_rec.amount ELSE v_rec.amount END
        WHERE id = v_rec.entity_id::INTEGER;
    END IF;

    -- Update the entry
    UPDATE public.ledger_entries
    SET amount = p_new_amount,
        entry_type = COALESCE(p_new_entry_type, entry_type),
        reference_type = COALESCE(p_new_reference_type, reference_type)
    WHERE id = v_rec.id;

    -- Apply new effect
    IF v_rec.entity_type = 'customer' THEN
        IF COALESCE(p_new_entry_type, v_rec.entry_type) = 'debit' THEN
            UPDATE public.customers SET balance = balance + p_new_amount WHERE id = v_rec.entity_id::INTEGER;
        ELSE
            UPDATE public.customers SET balance = balance - p_new_amount WHERE id = v_rec.entity_id::INTEGER;
        END IF;
    ELSIF v_rec.entity_type = 'supplier' THEN
        IF COALESCE(p_new_entry_type, v_rec.entry_type) = 'credit' THEN
            UPDATE public.suppliers SET outstanding_balance = outstanding_balance + p_new_amount WHERE id = v_rec.entity_id::UUID;
        ELSE
            UPDATE public.suppliers SET outstanding_balance = outstanding_balance - p_new_amount WHERE id = v_rec.entity_id::UUID;
        END IF;
    ELSIF v_rec.entity_type = 'clearing_agent' THEN
        UPDATE public.clearing_agents
        SET manual_adjustment = COALESCE(manual_adjustment, 0) + CASE WHEN COALESCE(p_new_entry_type, v_rec.entry_type) = 'credit' THEN -p_new_amount ELSE p_new_amount END,
            balance = COALESCE(balance, 0) + CASE WHEN COALESCE(p_new_entry_type, v_rec.entry_type) = 'credit' THEN -p_new_amount ELSE p_new_amount END
        WHERE id = v_rec.entity_id::INTEGER;
    ELSIF v_rec.entity_type = 'shipping_company' THEN
        UPDATE public.shipping_companies
        SET manual_adjustment = COALESCE(manual_adjustment, 0) + CASE WHEN COALESCE(p_new_entry_type, v_rec.entry_type) = 'credit' THEN -p_new_amount ELSE p_new_amount END,
            balance = COALESCE(balance, 0) + CASE WHEN COALESCE(p_new_entry_type, v_rec.entry_type) = 'credit' THEN -p_new_amount ELSE p_new_amount END
        WHERE id = v_rec.entity_id::INTEGER;
    END IF;

    RETURN jsonb_build_object('success', true, 'updated_id', v_rec.id);
END;
$$;

--
-- Name: get_account_totals_rpc("date", "date"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_account_totals_rpc"("p_from" "date" DEFAULT NULL::"date", "p_to" "date" DEFAULT NULL::"date") RETURNS TABLE("account_id" "text", "debit" numeric, "credit" numeric)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
  SELECT
    account_id::text,
    COALESCE(SUM(debit), 0)::numeric,
    COALESCE(SUM(credit), 0)::numeric
  FROM transactions
  WHERE (p_from IS NULL OR transaction_date::date >= p_from)
    AND (p_to IS NULL OR transaction_date::date <= p_to)
  GROUP BY account_id;
$$;

--
-- Name: debug_distributions(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."debug_distributions"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_res JSONB;
BEGIN
  SELECT json_build_object(
    'settings', (SELECT row_to_json(s) FROM public.profit_distribution_settings s LIMIT 1),
    'distributions', (SELECT json_agg(row_to_json(d)) FROM public.shareholder_profit_distributions d WHERE shipment_id = 60),
    'type_of_percentages', (SELECT jsonb_typeof(percentages) FROM public.profit_distribution_settings LIMIT 1)
  ) INTO v_res;
  RETURN v_res;
END;
$$;

--
-- Name: deposit_treasury(bigint, "text", numeric, "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."deposit_treasury"("p_treasury_id" bigint, "p_currency" "text", "p_amount" numeric, "p_description" "text" DEFAULT ''::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_current_balance NUMERIC := 0;
    v_new_balance NUMERIC;
    v_tx_id BIGINT;
BEGIN
    -- إنشاء أو تحديث الرصيد
    INSERT INTO treasury_balances (treasury_id, currency, balance, account_id)
    VALUES (
        p_treasury_id, 
        p_currency, 
        p_amount,
        (SELECT id FROM accounts WHERE account_code = 
            CASE p_currency 
                WHEN 'EGP' THEN '11101'
                WHEN 'USD' THEN '11102'
                WHEN 'EUR' THEN '11103'
                WHEN 'GBP' THEN '11104'
            END
        )
    )
    ON CONFLICT (treasury_id, currency) 
    DO UPDATE 
    SET balance = treasury_balances.balance + p_amount,
        account_id = EXCLUDED.account_id
    RETURNING balance INTO v_new_balance;

    -- تسجيل الحركة
    INSERT INTO treasury_transactions (
        treasury_id, type, currency, amount, 
        balance_before, balance_after, description, created_by
    ) VALUES (
        p_treasury_id, 'deposit', p_currency, p_amount,
        v_current_balance, v_new_balance, p_description, auth.uid()
    )
    RETURNING id INTO v_tx_id;

    RETURN jsonb_build_object(
        'success', true,
        'treasury_tx_id', v_tx_id,
        'new_balance', v_new_balance
    );
END;
$$;

--
-- Name: debug_profit_distribution("text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."debug_profit_distribution"("p_shipment_id_str" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_settings RECORD;
  v_pcts JSONB;
  v_shipment_pcts JSONB;
  v_res JSONB;
BEGIN
  SELECT * INTO v_settings FROM public.profit_distribution_settings LIMIT 1;
  v_pcts := COALESCE(v_settings.percentages, '{}'::JSONB);
  v_shipment_pcts := COALESCE(v_pcts -> p_shipment_id_str, '[]'::JSONB);
  
  SELECT json_build_object(
    'person1_id', v_settings.person1_id,
    'person2_id', v_settings.person2_id,
    'person3_id', v_settings.person3_id,
    'pcts_type', jsonb_typeof(v_settings.percentages),
    'v_pcts', v_pcts,
    'v_shipment_pcts', v_shipment_pcts,
    'p1_pct', (v_shipment_pcts -> 0)::TEXT::NUMERIC,
    'p2_pct', (v_shipment_pcts -> 1)::TEXT::NUMERIC,
    'p3_pct', (v_shipment_pcts -> 2)::TEXT::NUMERIC
  ) INTO v_res;
  RETURN v_res;
END;
$$;

--
-- Name: trg_before_delete_lot_receipt(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."trg_before_delete_lot_receipt"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_old_qty NUMERIC := 0;
BEGIN
  IF OLD.supplier_id IS NOT NULL AND COALESCE(OLD.total_fruit_cost, 0) > 0 THEN
    UPDATE public.suppliers
    SET outstanding_balance = GREATEST(COALESCE(outstanding_balance, 0) - OLD.total_fruit_cost, 0),
        updated_at = now()
    WHERE id = OLD.supplier_id;
  END IF;
  DELETE FROM public.ledger_entries WHERE reference_type = 'lot_receipt' AND reference_text = OLD.id::TEXT;
  SELECT COALESCE(SUM(remaining_quantity), 0) INTO v_old_qty FROM public.stock_batches WHERE batch_number LIKE ('G-' || OLD.lot_number || '-%');
  IF v_old_qty > 0 AND OLD.station_id IS NOT NULL THEN
    UPDATE public.station_products SET quantity = GREATEST(COALESCE(quantity, 0) - v_old_qty, 0), updated_at = now()
    WHERE station_id = OLD.station_id AND fruit_type_id = OLD.fruit_type_id;
    DELETE FROM public.station_products WHERE station_id = OLD.station_id AND fruit_type_id = OLD.fruit_type_id AND COALESCE(quantity, 0) <= 0;
  END IF;
  DELETE FROM public.stock_movements WHERE reference_type = 'lot_grading' AND description LIKE ('%' || OLD.lot_number || '%');
  DELETE FROM public.stock_batches WHERE batch_number LIKE ('G-' || OLD.lot_number || '-%');
  
  -- Delete the batch from station_product_batches
  DELETE FROM public.station_product_batches WHERE source_type = 'lot_receipt' AND product_code = OLD.lot_number;
  
  RETURN OLD;
END;
$$;

--
-- Name: check_entry_balance(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."check_entry_balance"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  -- Check all entries that have unbalanced debit/credit
  -- This fires AFTER the statement, so all rows are visible
  IF EXISTS (
    SELECT entry_number
    FROM transactions
    WHERE entry_number IS NOT NULL
    GROUP BY entry_number
    HAVING ABS(SUM(COALESCE(debit, 0)) - SUM(COALESCE(credit, 0))) > 0.01
  ) THEN
    RAISE EXCEPTION 'القيد المحاسبي غير متوازن: المدين لا يساوي الدائن. تحقق من جميع القيود النشطة.';
  END IF;

  RETURN NULL;
END;
$$;

--
-- Name: distribute_profit_for_shipment("text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."distribute_profit_for_shipment"("p_shipment_id_text" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_shipment_id BIGINT;
  v_profit NUMERIC;
  v_settings RECORD;
  v_pcts JSONB;
  v_conv JSONB;
  v_p4_map JSONB;
  v_share NUMERIC;
  v_pct NUMERIC;
  v_target_currency TEXT;
  v_rate NUMERIC;
  v_person_id UUID;
  v_final_currency TEXT;
  v_final_amount NUMERIC;
  v_treasury_id UUID;
  v_i INT;
  v_person_ids UUID[];
  v_shipment_pcts JSONB;
  v_key TEXT;
  v_sid TEXT;
BEGIN
  -- Cast TEXT to BIGINT safely
  v_shipment_id := p_shipment_id_text::BIGINT;
  v_sid := p_shipment_id_text;

  SELECT net_profit_egp INTO v_profit
  FROM public.export_shipments WHERE id = v_shipment_id AND status != 'cancelled';

  IF v_profit IS NULL OR v_profit <= 0 THEN
    RAISE EXCEPTION 'الشحنة غير موجودة أو لا تحتوي على أرباح.';
  END IF;

  SELECT * INTO v_settings FROM public.profit_distribution_settings LIMIT 1;
  IF v_settings IS NULL THEN
    RAISE EXCEPTION 'لم يتم العثور على إعدادات توزيع الأرباح.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.shareholder_profit_distributions WHERE shipment_id = v_shipment_id
  ) THEN
    RAISE EXCEPTION 'تم توزيع أرباح هذه الشحنة مسبقاً.';
  END IF;

  v_pcts := COALESCE(v_settings.percentages, '{}'::JSONB);
  v_conv := COALESCE(v_settings.currency_conversions, '{}'::JSONB);
  v_p4_map := COALESCE(v_settings.person4_for_shipment, '{}'::JSONB);
  v_shipment_pcts := COALESCE(v_pcts -> v_sid, '[]'::JSONB);

  v_person_ids := ARRAY[
    v_settings.person1_id,
    v_settings.person2_id,
    v_settings.person3_id
  ];

  SELECT id INTO v_treasury_id
  FROM public.treasuries WHERE type = 'main' AND user_id = auth.uid()
  LIMIT 1;

  IF v_treasury_id IS NULL THEN
    SELECT id INTO v_treasury_id
    FROM public.treasuries WHERE type = 'main' LIMIT 1;
  END IF;

  FOR v_i IN 1..3 LOOP
    v_person_id := v_person_ids[v_i];
    CONTINUE WHEN v_person_id IS NULL;

    v_pct := COALESCE((v_shipment_pcts -> (v_i - 1))::TEXT::NUMERIC, 0);
    CONTINUE WHEN v_pct <= 0;

    v_share := ROUND(v_profit * v_pct / 100, 2);

    v_key := (v_i - 1)::TEXT;
    v_target_currency := v_conv -> v_sid -> v_key ->> 'currency';
    v_rate := COALESCE((v_conv -> v_sid -> v_key ->> 'rate')::NUMERIC, 0);

    IF v_target_currency IS NOT NULL AND v_rate > 0 THEN
      v_final_currency := v_target_currency;
      v_final_amount := ROUND(v_share / v_rate, 2);
    ELSE
      v_final_currency := 'EGP';
      v_final_amount := v_share;
    END IF;

    INSERT INTO public.shareholder_profit_distributions (
      shipment_id, shareholder_id, person_index, percentage, amount_egp,
      currency, converted_amount, rate_to_egp, created_by
    ) VALUES (
      v_shipment_id, v_person_id, v_i - 1, v_pct, v_share,
      v_final_currency, v_final_amount, NULLIF(v_rate, 0), auth.uid()
    );

    IF v_treasury_id IS NOT NULL THEN
      INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description, shareholder_id, created_by
      ) VALUES (
        v_treasury_id, 'deposit', v_final_amount, v_final_currency,
        'توزيع أرباح - شحنة ' || v_sid,
        v_person_id, auth.uid()
      );
    END IF;

    IF v_final_currency = 'EGP' THEN
      UPDATE public.shareholders SET current_balance_egp = COALESCE(current_balance_egp,0) + v_final_amount WHERE id = v_person_id;
    ELSIF v_final_currency = 'USD' THEN
      UPDATE public.shareholders SET current_balance_usd = COALESCE(current_balance_usd,0) + v_final_amount WHERE id = v_person_id;
    ELSIF v_final_currency = 'EUR' THEN
      UPDATE public.shareholders SET current_balance_eur = COALESCE(current_balance_eur,0) + v_final_amount WHERE id = v_person_id;
    ELSIF v_final_currency = 'GBP' THEN
      UPDATE public.shareholders SET current_balance_gbp = COALESCE(current_balance_gbp,0) + v_final_amount WHERE id = v_person_id;
    END IF;
  END LOOP;

  -- Person 4 (with safe UUID cast)
  BEGIN
    v_person_id := (v_p4_map ->> v_sid)::UUID;
  EXCEPTION WHEN OTHERS THEN
    v_person_id := NULL;
  END;

  IF v_person_id IS NOT NULL THEN
    v_pct := GREATEST(100
      - COALESCE((v_shipment_pcts ->> '0')::NUMERIC, 0)
      - COALESCE((v_shipment_pcts ->> '1')::NUMERIC, 0)
      - COALESCE((v_shipment_pcts ->> '2')::NUMERIC, 0), 0);

    v_share := ROUND(v_profit * v_pct / 100, 2);

    v_target_currency := v_conv -> v_sid -> '3' ->> 'currency';
    v_rate := COALESCE((v_conv -> v_sid -> '3' ->> 'rate')::NUMERIC, 0);

    IF v_target_currency IS NOT NULL AND v_rate > 0 THEN
      v_final_currency := v_target_currency;
      v_final_amount := ROUND(v_share / v_rate, 2);
    ELSE
      v_final_currency := 'EGP';
      v_final_amount := v_share;
    END IF;

    INSERT INTO public.shareholder_profit_distributions (
      shipment_id, shareholder_id, person_index, percentage, amount_egp,
      currency, converted_amount, rate_to_egp, created_by
    ) VALUES (
      v_shipment_id, v_person_id, 3, v_pct, v_share,
      v_final_currency, v_final_amount, NULLIF(v_rate, 0), auth.uid()
    );

    IF v_treasury_id IS NOT NULL THEN
      INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description, shareholder_id, created_by
      ) VALUES (
        v_treasury_id, 'deposit', v_final_amount, v_final_currency,
        'توزيع أرباح - شحنة ' || v_sid,
        v_person_id, auth.uid()
      );
    END IF;

    IF v_final_currency = 'EGP' THEN
      UPDATE public.shareholders SET current_balance_egp = COALESCE(current_balance_egp,0) + v_final_amount WHERE id = v_person_id;
    ELSIF v_final_currency = 'USD' THEN
      UPDATE public.shareholders SET current_balance_usd = COALESCE(current_balance_usd,0) + v_final_amount WHERE id = v_person_id;
    ELSIF v_final_currency = 'EUR' THEN
      UPDATE public.shareholders SET current_balance_eur = COALESCE(current_balance_eur,0) + v_final_amount WHERE id = v_person_id;
    ELSIF v_final_currency = 'GBP' THEN
      UPDATE public.shareholders SET current_balance_gbp = COALESCE(current_balance_gbp,0) + v_final_amount WHERE id = v_person_id;
    END IF;
  END IF;
END;
$$;

--
-- Name: replace_supplier_ledger_entry("uuid", numeric, numeric, "text", "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."replace_supplier_ledger_entry"("p_supplier_id" "uuid", "p_old_amount" numeric, "p_new_amount" numeric, "p_entry_type" "text" DEFAULT 'credit'::"text", "p_reference_type" "text" DEFAULT 'payment'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_deleted_id BIGINT;
BEGIN
    SELECT id INTO v_deleted_id
    FROM public.ledger_entries
    WHERE entity_type = 'supplier'
      AND entity_id = p_supplier_id::TEXT
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_deleted_id IS NOT NULL THEN
        IF (SELECT entry_type FROM public.ledger_entries WHERE id = v_deleted_id) = 'credit' THEN
            UPDATE public.suppliers SET outstanding_balance = outstanding_balance - (SELECT amount FROM public.ledger_entries WHERE id = v_deleted_id) WHERE id = p_supplier_id;
        ELSE
            UPDATE public.suppliers SET outstanding_balance = outstanding_balance + (SELECT amount FROM public.ledger_entries WHERE id = v_deleted_id) WHERE id = p_supplier_id;
        END IF;
        DELETE FROM public.ledger_entries WHERE id = v_deleted_id;
    END IF;

    INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, reference_type, description, created_by)
    VALUES ('supplier', p_supplier_id::TEXT, p_entry_type, p_new_amount, p_reference_type, 'تعديل حركة خزينة', auth.uid());

    IF p_entry_type = 'credit' THEN
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance + p_new_amount WHERE id = p_supplier_id;
    ELSE
        UPDATE public.suppliers SET outstanding_balance = outstanding_balance - p_new_amount WHERE id = p_supplier_id;
    END IF;

    RETURN jsonb_build_object('success', true, 'deleted_id', v_deleted_id);
END;
$$;

--
-- Name: create_treasury("text", "text", "uuid", "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."create_treasury"("p_name" "text", "p_type" "text", "p_employee_id" "uuid" DEFAULT NULL::"uuid", "p_notes" "text" DEFAULT NULL::"text") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_new_id INTEGER;
    v_account_id INTEGER;
    v_currency TEXT;
BEGIN
    INSERT INTO public.treasuries (name, type, user_id, notes)
    VALUES (p_name, p_type, p_employee_id, p_notes)
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
            END;

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

--
-- Name: get_ledger_page_rpc("text", "text", "text", "text", "text", integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_ledger_page_rpc"("p_account_id" "text" DEFAULT NULL::"text", "p_from_date" "text" DEFAULT NULL::"text", "p_to_date" "text" DEFAULT NULL::"text", "p_cursor_date" "text" DEFAULT NULL::"text", "p_cursor_id" "text" DEFAULT NULL::"text", "p_limit" integer DEFAULT 50) RETURNS TABLE("id" "text", "date" "text", "entry_number" bigint, "account_id" "text", "account_code" "text", "account_name" "text", "description" "text", "debit" numeric, "credit" numeric, "reference_type" "text", "reference_id" "text", "next_cursor_date" "text", "next_cursor_id" "text", "has_more" boolean, "opening_balance_debit" numeric, "opening_balance_credit" numeric)
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_cursor_ts TIMESTAMPTZ;
  v_has_more BOOLEAN := FALSE;
  v_next_cursor_date TEXT;
  v_next_cursor_id TEXT;
  v_ob_debit NUMERIC := 0;
  v_ob_credit NUMERIC := 0;
BEGIN
  -- Parse cursor timestamp
  IF p_cursor_date IS NOT NULL AND p_cursor_id IS NOT NULL THEN
    v_cursor_ts := p_cursor_date::TIMESTAMPTZ;
  END IF;

  -- Compute opening balance at cursor position (before cursor)
  IF v_cursor_ts IS NOT NULL THEN
    SELECT
      COALESCE(SUM(COALESCE(debit, CASE WHEN type='debit' THEN amount ELSE 0 END)), 0),
      COALESCE(SUM(COALESCE(credit, CASE WHEN type='credit' THEN amount ELSE 0 END)), 0)
    INTO v_ob_debit, v_ob_credit
    FROM transactions
    WHERE (p_account_id IS NULL OR account_id = p_account_id)
      AND transaction_date < v_cursor_ts;

    -- Subtract current page opening balance from total opening balance
    -- (we want opening balance BEFORE the cursor, not before the date range)
  ELSE
    -- No cursor = first page: compute opening balance before fromDate
    IF p_from_date IS NOT NULL THEN
      SELECT
        COALESCE(SUM(COALESCE(debit, CASE WHEN type='debit' THEN amount ELSE 0 END)), 0),
        COALESCE(SUM(COALESCE(credit, CASE WHEN type='credit' THEN amount ELSE 0 END)), 0)
      INTO v_ob_debit, v_ob_credit
      FROM transactions
      WHERE (p_account_id IS NULL OR account_id = p_account_id)
        AND transaction_date < p_from_date::TIMESTAMPTZ;
    END IF;
  END IF;

  RETURN QUERY
  WITH page AS (
    SELECT
      t.id::TEXT AS t_id,
      t.transaction_date::TEXT AS t_date,
      t.entry_number AS t_entry_number,
      t.account_id::TEXT AS t_account_id,
      COALESCE(a.account_code, '') AS t_account_code,
      COALESCE(a.name, '') AS t_account_name,
      COALESCE(t.description, '') AS t_description,
      COALESCE(t.debit, 0) AS t_debit,
      COALESCE(t.credit, 0) AS t_credit,
      COALESCE(t.reference_type, '') AS t_reference_type,
      COALESCE(t.reference_id, '') AS t_reference_id
    FROM transactions t
    LEFT JOIN accounts a ON a.id = t.account_id
    WHERE (p_account_id IS NULL OR t.account_id = p_account_id)
      AND (p_from_date IS NULL OR t.transaction_date >= p_from_date::TIMESTAMPTZ)
      AND (p_to_date IS NULL OR t.transaction_date <= p_to_date::TIMESTAMPTZ)
      AND (
        v_cursor_ts IS NULL
        OR t.transaction_date > v_cursor_ts
        OR (t.transaction_date = v_cursor_ts AND t.id::TEXT > p_cursor_id)
      )
    ORDER BY t.transaction_date ASC, t.id ASC
    LIMIT (p_limit + 1)
  ),
  page_data AS (
    SELECT * FROM page LIMIT p_limit
  ),
  has_more_check AS (
    SELECT COUNT(*) > 0 AS has_more FROM page WHERE NOT EXISTS (SELECT 1 FROM page_data)
  )
  SELECT
    pd.t_id AS id,
    pd.t_date AS date,
    pd.t_entry_number AS entry_number,
    pd.t_account_id AS account_id,
    pd.t_account_code AS account_code,
    pd.t_account_name AS account_name,
    pd.t_description AS description,
    pd.t_debit AS debit,
    pd.t_credit AS credit,
    pd.t_reference_type AS reference_type,
    pd.t_reference_id AS reference_id,
    (SELECT p2.t_date FROM page p2 ORDER BY p2.t_date DESC, p2.t_id DESC LIMIT 1) AS next_cursor_date,
    (SELECT p2.t_id FROM page p2 ORDER BY p2.t_date DESC, p2.t_id DESC LIMIT 1) AS next_cursor_id,
    hmc.has_more,
    v_ob_debit AS opening_balance_debit,
    v_ob_credit AS opening_balance_credit
  FROM page_data pd
  CROSS JOIN has_more_check hmc;
END;
$$;

--
-- Name: get_fiscal_year_for_date("date"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_fiscal_year_for_date"("p_date" "date") RETURNS bigint
    LANGUAGE "sql" STABLE
    AS $$
  SELECT id FROM public.fiscal_years
  WHERE p_date BETWEEN start_date AND end_date
  LIMIT 1;
$$;

--
-- Name: get_next_shareholder_code(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_next_shareholder_code"() RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  last_code text;
  next_num integer;
BEGIN
  -- جلب آخر كود تم إضافته
  SELECT code INTO last_code 
  FROM public.shareholders 
  WHERE code LIKE 'SHR%' 
  ORDER BY code DESC 
  LIMIT 1;

  -- إذا لم يكن هناك مساهمين، نبدأ من SHR0001
  IF last_code IS NULL THEN
    RETURN 'SHR0001';
  END IF;
  
  -- استخراج الرقم من الكود الأخير وزيادته بمقدار 1
  -- الكود مكون من 3 حروف 'SHR' متبوعة برقم
  next_num := CAST(SUBSTRING(last_code FROM 4) AS integer) + 1;
  
  -- إعادة الكود الجديد مع تنسيق الأصفار
  RETURN 'SHR' || LPAD(next_num::text, 4, '0');
END;
$$;

--
-- Name: rpc_post_shipment_with_cogs(integer, "text", "uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."rpc_post_shipment_with_cogs"("p_shipment_id" integer, "p_new_status" "text", "p_user_id" "uuid" DEFAULT "auth"."uid"()) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_shipment RECORD;
  v_total_cost NUMERIC;
  v_inventory_cost NUMERIC;
  v_packing_cost NUMERIC;
  v_cogs_account_id INT := 6;   -- 5000 COGS
  v_inv_account_id INT := 3;     -- 1030 Inventory
  v_pack_account_id INT := 4;    -- 1040 Packing Materials
  v_result JSONB;
BEGIN
  -- Lock shipment row
  SELECT * INTO v_shipment FROM export_shipments WHERE id = p_shipment_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'shipment not found');
  END IF;

  -- Validate status transition
  IF p_new_status NOT IN ('shipped', 'in_transit') THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid status');
  END IF;

  -- Update status
  UPDATE export_shipments
  SET status = p_new_status, updated_at = NOW()
  WHERE id = p_shipment_id;

  -- Post COGS if not already posted and has positive cost
  IF NOT v_shipment.cogs_posted AND v_shipment.total_cost > 0 THEN
    -- Calculate breakdown from shipment_cost_breakdown
    SELECT COALESCE(SUM(CASE WHEN category IN ('fruit','labor','logistics','export_costs','admin','other') THEN amount ELSE 0 END), 0)
      INTO v_inventory_cost
      FROM shipment_cost_breakdown
      WHERE export_shipment_id = p_shipment_id;

    SELECT COALESCE(SUM(CASE WHEN category = 'packing_material' THEN amount ELSE 0 END), 0)
      INTO v_packing_cost
      FROM shipment_cost_breakdown
      WHERE export_shipment_id = p_shipment_id;

    v_total_cost := v_inventory_cost + v_packing_cost;

    -- Insert double-entry COGS journal
    INSERT INTO transactions (account_id, transaction_date, type, amount, description, reference_type, reference_id, created_by)
    VALUES
      (v_cogs_account_id, CURRENT_DATE, 'debit', v_total_cost,
       CONCAT('COGS for shipment #', p_shipment_id), 'export_shipment', p_shipment_id, p_user_id),
      (v_inv_account_id, CURRENT_DATE, 'credit', v_inventory_cost,
       CONCAT('Inventory COGS for shipment #', p_shipment_id), 'export_shipment', p_shipment_id, p_user_id),
      (v_pack_account_id, CURRENT_DATE, 'credit', v_packing_cost,
       CONCAT('Packing materials COGS for shipment #', p_shipment_id), 'export_shipment', p_shipment_id, p_user_id);

    -- Mark COGS as posted
    UPDATE export_shipments SET cogs_posted = TRUE WHERE id = p_shipment_id;

    -- Log audit
    INSERT INTO audit_logs_text (table_name, record_id, action, old_values, new_values, performed_by)
    VALUES ('export_shipments', p_shipment_id::TEXT, 'post_cogs',
      jsonb_build_object('cogs_posted', false, 'status', v_shipment.status),
      jsonb_build_object('cogs_posted', true, 'status', p_new_status, 'cogs_amount', v_total_cost),
      p_user_id);
  END IF;

  v_result := jsonb_build_object(
    'success', true,
    'shipment_id', p_shipment_id,
    'status', p_new_status,
    'cogs_posted', COALESCE(v_shipment.cogs_posted, false) OR (v_shipment.total_cost > 0),
    'cogs_amount', v_total_cost
  );

  RETURN v_result;
END;
$$;

--
-- Name: distribute_shipment_profit("text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."distribute_shipment_profit"("p_shipment_id_str" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_shipment_id BIGINT;
  v_profit NUMERIC;
  v_settings RECORD;
  v_pcts JSONB;
  v_conv JSONB;
  v_p4_map JSONB;
  v_share NUMERIC;
  v_pct NUMERIC;
  v_target_currency TEXT;
  v_rate NUMERIC;
  v_person_id UUID;
  v_final_currency TEXT;
  v_final_amount NUMERIC;
  v_treasury_id BIGINT;
  v_i INT;
  v_person_ids UUID[];
  v_shipment_pcts JSONB;
  v_key TEXT;
BEGIN
  v_shipment_id := p_shipment_id_str::BIGINT;

  SELECT net_profit_egp INTO v_profit
  FROM public.export_shipments WHERE id = v_shipment_id AND status != 'cancelled';

  IF v_profit IS NULL OR v_profit <= 0 THEN
    RAISE EXCEPTION 'لا يوجد أرباح مسجلة لهذه الشحنة أو أنها ملغاة.';
  END IF;

  SELECT * INTO v_settings FROM public.profit_distribution_settings LIMIT 1;
  IF v_settings IS NULL THEN
    RAISE EXCEPTION 'لم يتم إعداد إعدادات توزيع الأرباح.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.shareholder_profit_distributions WHERE shipment_id = v_shipment_id
  ) THEN
    RAISE EXCEPTION 'تم توزيع أرباح هذه الشحنة مسبقاً.';
  END IF;

  v_pcts := COALESCE(v_settings.percentages, '{}'::JSONB);
  v_conv := COALESCE(v_settings.currency_conversions, '{}'::JSONB);
  v_p4_map := COALESCE(v_settings.person4_for_shipment, '{}'::JSONB);
  v_shipment_pcts := COALESCE(v_pcts -> p_shipment_id_str, '[]'::JSONB);

  v_person_ids := ARRAY[
    v_settings.person1_id,
    v_settings.person2_id,
    v_settings.person3_id
  ];

  SELECT id INTO v_treasury_id
  FROM public.treasuries WHERE type = 'main' AND user_id = auth.uid()
  LIMIT 1;

  IF v_treasury_id IS NULL THEN
    SELECT id INTO v_treasury_id
    FROM public.treasuries WHERE type = 'main' LIMIT 1;
  END IF;

  FOR v_i IN 1..3 LOOP
    v_person_id := v_person_ids[v_i];
    CONTINUE WHEN v_person_id IS NULL;

    -- Use integer index for JSON array
    v_pct := COALESCE((v_shipment_pcts -> (v_i - 1))::TEXT::NUMERIC, 0);
    CONTINUE WHEN v_pct <= 0;

    v_share := ROUND(v_profit * v_pct / 100, 2);

    v_key := (v_i - 1)::TEXT;
    v_target_currency := v_conv -> p_shipment_id_str -> v_key ->> 'currency';
    v_rate := COALESCE((v_conv -> p_shipment_id_str -> v_key ->> 'rate')::NUMERIC, 0);

    IF v_target_currency IS NOT NULL AND v_rate > 0 THEN
      v_final_currency := v_target_currency;
      v_final_amount := ROUND(v_share / v_rate, 2);
    ELSE
      v_final_currency := 'EGP';
      v_final_amount := v_share;
    END IF;

    INSERT INTO public.shareholder_profit_distributions (
      shipment_id, shareholder_id, person_index, percentage, amount_egp,
      currency, converted_amount, rate_to_egp, created_by
    ) VALUES (
      v_shipment_id, v_person_id, v_i - 1, v_pct, v_share,
      v_final_currency, v_final_amount, NULLIF(v_rate, 0), auth.uid()
    );

    IF v_treasury_id IS NOT NULL THEN
      INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description, shareholder_id, created_by
      ) VALUES (
        v_treasury_id, 'deposit', v_final_amount, v_final_currency,
        'توزيع أرباح شحنة - ' || p_shipment_id_str,
        v_person_id, auth.uid()
      );
    END IF;

    IF v_final_currency = 'EGP' THEN
      UPDATE public.shareholders SET current_balance_egp = COALESCE(current_balance_egp,0) + v_final_amount WHERE id = v_person_id;
    ELSIF v_final_currency = 'USD' THEN
      UPDATE public.shareholders SET current_balance_usd = COALESCE(current_balance_usd,0) + v_final_amount WHERE id = v_person_id;
    ELSIF v_final_currency = 'EUR' THEN
      UPDATE public.shareholders SET current_balance_eur = COALESCE(current_balance_eur,0) + v_final_amount WHERE id = v_person_id;
    ELSIF v_final_currency = 'GBP' THEN
      UPDATE public.shareholders SET current_balance_gbp = COALESCE(current_balance_gbp,0) + v_final_amount WHERE id = v_person_id;
    END IF;
  END LOOP;

  -- Person 4 safe block
  BEGIN
    -- We parse it and verify it's a valid UUID
    IF (v_p4_map ->> p_shipment_id_str) IS NOT NULL AND (v_p4_map ->> p_shipment_id_str) != '' THEN
      v_person_id := (v_p4_map ->> p_shipment_id_str)::UUID;
    ELSE
      v_person_id := NULL;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_person_id := NULL;
  END;

  IF v_person_id IS NOT NULL THEN
    -- FIXED: Use integer indices 0, 1, 2 instead of string keys '0', '1', '2'
    v_pct := GREATEST(100
      - COALESCE((v_shipment_pcts ->> 0)::NUMERIC, 0)
      - COALESCE((v_shipment_pcts ->> 1)::NUMERIC, 0)
      - COALESCE((v_shipment_pcts ->> 2)::NUMERIC, 0), 0);

    v_share := ROUND(v_profit * v_pct / 100, 2);

    v_target_currency := v_conv -> p_shipment_id_str -> '3' ->> 'currency';
    v_rate := COALESCE((v_conv -> p_shipment_id_str -> '3' ->> 'rate')::NUMERIC, 0);

    IF v_target_currency IS NOT NULL AND v_rate > 0 THEN
      v_final_currency := v_target_currency;
      v_final_amount := ROUND(v_share / v_rate, 2);
    ELSE
      v_final_currency := 'EGP';
      v_final_amount := v_share;
    END IF;

    INSERT INTO public.shareholder_profit_distributions (
      shipment_id, shareholder_id, person_index, percentage, amount_egp,
      currency, converted_amount, rate_to_egp, created_by
    ) VALUES (
      v_shipment_id, v_person_id, 3, v_pct, v_share,
      v_final_currency, v_final_amount, NULLIF(v_rate, 0), auth.uid()
    );

    IF v_treasury_id IS NOT NULL THEN
      INSERT INTO public.treasury_transactions (
        treasury_id, type, amount, currency, description, shareholder_id, created_by
      ) VALUES (
        v_treasury_id, 'deposit', v_final_amount, v_final_currency,
        'توزيع أرباح شحنة - ' || p_shipment_id_str,
        v_person_id, auth.uid()
      );
    END IF;

    IF v_final_currency = 'EGP' THEN
      UPDATE public.shareholders SET current_balance_egp = COALESCE(current_balance_egp,0) + v_final_amount WHERE id = v_person_id;
    ELSIF v_final_currency = 'USD' THEN
      UPDATE public.shareholders SET current_balance_usd = COALESCE(current_balance_usd,0) + v_final_amount WHERE id = v_person_id;
    ELSIF v_final_currency = 'EUR' THEN
      UPDATE public.shareholders SET current_balance_eur = COALESCE(current_balance_eur,0) + v_final_amount WHERE id = v_person_id;
    ELSIF v_final_currency = 'GBP' THEN
      UPDATE public.shareholders SET current_balance_gbp = COALESCE(current_balance_gbp,0) + v_final_amount WHERE id = v_person_id;
    END IF;
  END IF;
END;
$$;

--
-- Name: create_balanced_entry(integer, integer, numeric, "text", "date", "text", "uuid", "jsonb", integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."create_balanced_entry"("p_debit_account_id" integer, "p_credit_account_id" integer, "p_amount" numeric, "p_description" "text" DEFAULT NULL::"text", "p_transaction_date" "date" DEFAULT CURRENT_DATE, "p_reference_type" "text" DEFAULT NULL::"text", "p_reference_id" "uuid" DEFAULT NULL::"uuid", "p_currency_snapshot" "jsonb" DEFAULT NULL::"jsonb", "p_purchase_invoice_ref" integer DEFAULT NULL::integer) RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
DECLARE
  v_entry_number TEXT;
BEGIN
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be positive, got %', p_amount;
  END IF;

  IF p_debit_account_id = p_credit_account_id THEN
    RAISE EXCEPTION 'Debit and credit accounts must be different';
  END IF;

  v_entry_number := 'J' || LPAD(nextval('entry_number_seq')::TEXT, 6, '0');

  INSERT INTO transactions (
    entry_number, transaction_date, account_id,
    debit, credit, description,
    currency_snapshot, purchase_invoice_ref
  ) VALUES
    (v_entry_number, p_transaction_date, p_debit_account_id,
     p_amount, 0, p_description,
     COALESCE(p_currency_snapshot, jsonb_build_object('currency', 'EGP', 'amount', p_amount, 'exchangeRate', 1.0)),
     p_purchase_invoice_ref),
    (v_entry_number, p_transaction_date, p_credit_account_id,
     0, p_amount, p_description,
     COALESCE(p_currency_snapshot, jsonb_build_object('currency', 'EGP', 'amount', p_amount, 'exchangeRate', 1.0)),
     p_purchase_invoice_ref);

  UPDATE accounts SET balance = COALESCE(balance, 0) + p_amount WHERE id = p_debit_account_id;
  UPDATE accounts SET balance = COALESCE(balance, 0) - p_amount WHERE id = p_credit_account_id;

  RETURN v_entry_number;
END;
$$;

--
-- Name: rpc_process_approval("text", integer, "text", "text", "uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."rpc_process_approval"("p_entity_type" "text", "p_entity_id" integer, "p_action" "text", "p_comment" "text" DEFAULT NULL::"text", "p_user_id" "uuid" DEFAULT "auth"."uid"()) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $_$
DECLARE
  v_table_name TEXT;
  v_status_col TEXT;
  v_from_status TEXT;
  v_to_status TEXT;
  v_result JSONB;
BEGIN
  -- Validate action
  IF p_action NOT IN ('submit', 'approve', 'reject') THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid action');
  END IF;

  -- Determine target table and status values
  CASE p_entity_type
    WHEN 'purchase_invoice' THEN
      v_table_name := 'purchase_invoices';
      v_status_col := 'approval_status';
    WHEN 'export_shipment' THEN
      v_table_name := 'export_shipments';
      v_status_col := 'approval_status';
    WHEN 'treasury' THEN
      v_table_name := 'treasuries';
      v_status_col := 'approval_status';
    ELSE
      RETURN jsonb_build_object('success', false, 'error', 'unknown entity type');
  END CASE;

  -- Determine target status
  CASE p_action
    WHEN 'submit' THEN v_to_status := 'pending';
    WHEN 'approve' THEN v_to_status := 'approved';
    WHEN 'reject' THEN v_to_status := 'rejected';
  END CASE;

  -- Execute dynamic status update
  EXECUTE format('
    WITH old AS (
      SELECT %I AS old_status FROM %I WHERE id = $1 FOR UPDATE
    )
    UPDATE %I SET %I = $2, updated_at = NOW() WHERE id = $1
    RETURNING %I AS new_status', v_status_col, v_table_name, v_table_name, v_status_col, v_status_col)
    INTO v_to_status USING p_entity_id, v_to_status;

  -- Cannot easily get from_status dynamically, use a default
  v_from_status := CASE p_action
    WHEN 'submit' THEN 'draft'
    WHEN 'approve' THEN 'pending'
    WHEN 'reject' THEN 'pending'
  END;

  -- Log approval history
  INSERT INTO approval_history (entity_type, entity_id, from_status, to_status, action, comment, performed_by)
  VALUES (p_entity_type, p_entity_id, v_from_status, v_to_status, p_action, p_comment, p_user_id);

  -- Notify all admin users
  INSERT INTO notifications (user_id, type, severity, title, message)
  SELECT
    u.id::TEXT,
    'approval',
    CASE WHEN p_action = 'reject' THEN 'error' ELSE 'info' END,
    CASE
      WHEN p_action = 'submit' THEN CONCAT('موافقة مطلوبة: ', p_entity_type)
      WHEN p_action = 'approve' THEN CONCAT('تمت الموافقة: ', p_entity_type)
      WHEN p_action = 'reject' THEN CONCAT('تم الرفض: ', p_entity_type)
    END,
    CONCAT(p_entity_type, ' #', p_entity_id, ' - ', p_action, CASE WHEN p_comment IS NOT NULL THEN CONCAT(': ', p_comment) ELSE '' END)
  FROM users u
  WHERE u.role IN ('admin', 'manager');

  v_result := jsonb_build_object(
    'success', true,
    'entity_type', p_entity_type,
    'entity_id', p_entity_id,
    'action', p_action,
    'from_status', v_from_status,
    'to_status', v_to_status
  );

  RETURN v_result;
END;
$_$;

--
-- Name: debug_lot_triggers(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."debug_lot_triggers"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  RETURN jsonb_build_object(
    'triggers_on_lot_receipts', (
      SELECT jsonb_agg(row_to_json(t))
      FROM (
        SELECT trigger_name, event_manipulation, action_timing, action_statement
        FROM information_schema.triggers
        WHERE event_object_table = 'lot_receipts'
          AND event_object_schema = 'public'
      ) t
    ),
    'triggers_on_suppliers', (
      SELECT jsonb_agg(row_to_json(t))
      FROM (
        SELECT trigger_name, event_manipulation, action_timing, action_statement
        FROM information_schema.triggers
        WHERE event_object_table = 'suppliers'
          AND event_object_schema = 'public'
      ) t
    ),
    'lot_count', (SELECT count(*) FROM lot_receipts),
    'supplier_with_negative_balance', (
      SELECT jsonb_agg(row_to_json(t))
      FROM (
        SELECT id, name, outstanding_balance
        FROM suppliers
        WHERE outstanding_balance < 0
      ) t
    )
  );
END;
$$;

--
-- Name: search_customers("text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."search_customers"("search_term" "text") RETURNS SETOF "public"."customers"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    RETURN QUERY
    SELECT *
    FROM customers
    WHERE 
        name ILIKE '%' || search_term || '%'
        OR code ILIKE '%' || search_term || '%'
        OR phone ILIKE '%' || search_term || '%';
END;
$$;

--
-- Name: get_account_balances_for_fy(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_account_balances_for_fy"("p_fiscal_year_id" bigint) RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    AS $$
  SELECT COALESCE(jsonb_object_agg(
    account_code,
    jsonb_build_object('debit', debit, 'credit', credit)
  ), '{}'::jsonb)
  FROM (
    SELECT
      a.account_code,
      COALESCE(SUM(t.debit), 0)::numeric AS debit,
      COALESCE(SUM(t.credit), 0)::numeric AS credit
    FROM public.transactions t
    JOIN public.accounts a ON t.account_id::text = a.id::text
    JOIN public.fiscal_years fy ON fy.id = p_fiscal_year_id
    WHERE COALESCE(t.transaction_date, t.created_at::date) BETWEEN fy.start_date AND fy.end_date
    GROUP BY a.account_code
  ) totals;
$$;

--
-- Name: undo_shipment_profit("text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."undo_shipment_profit"("p_shipment_id_str" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_shipment_id BIGINT;
  v_dist RECORD;
BEGIN
  v_shipment_id := p_shipment_id_str::BIGINT;

  FOR v_dist IN
    SELECT * FROM public.shareholder_profit_distributions WHERE shipment_id = v_shipment_id
  LOOP
    DELETE FROM public.treasury_transactions
    WHERE shareholder_id = v_dist.shareholder_id
      AND description = 'توزيع أرباح - شحنة ' || p_shipment_id_str
      AND type = 'deposit'
      AND currency = v_dist.currency;

    IF v_dist.currency = 'EGP' THEN
      UPDATE public.shareholders SET current_balance_egp = COALESCE(current_balance_egp,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;
    ELSIF v_dist.currency = 'USD' THEN
      UPDATE public.shareholders SET current_balance_usd = COALESCE(current_balance_usd,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;
    ELSIF v_dist.currency = 'EUR' THEN
      UPDATE public.shareholders SET current_balance_eur = COALESCE(current_balance_eur,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;
    ELSIF v_dist.currency = 'GBP' THEN
      UPDATE public.shareholders SET current_balance_gbp = COALESCE(current_balance_gbp,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;
    END IF;
  END LOOP;

  DELETE FROM public.shareholder_profit_distributions WHERE shipment_id = v_shipment_id;
END;
$$;

--
-- Name: test_echo("jsonb"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."test_echo"("p_data" "jsonb") RETURNS "jsonb"
    LANGUAGE "sql"
    AS $$ SELECT p_data; $$;

--
-- Name: verify_fiscal_year_backup(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."verify_fiscal_year_backup"("p_fiscal_year_id" bigint) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  _backup record;
  _result jsonb;
BEGIN
  SELECT * INTO _backup
  FROM public.fiscal_year_backup_metadata
  WHERE fiscal_year_id = p_fiscal_year_id
    AND verification_status = 'VERIFIED'
  ORDER BY created_at DESC
  LIMIT 1;

  IF _backup IS NULL THEN
    RETURN jsonb_build_object(
      'verified', false,
      'reason', 'لا توجد نسخة احتياطية موثقة',
      'available_backups', (
        SELECT count(*)::int FROM public.fiscal_year_backup_metadata
        WHERE fiscal_year_id = p_fiscal_year_id
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'verified', true,
    'backup_id', _backup.id,
    'backup_date', _backup.created_at,
    'backup_type', _backup.backup_type,
    'records_count', _backup.records_count,
    'verification_status', _backup.verification_status
  );
END;
$$;

--
-- Name: reverse_customer_ledger_entry(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."reverse_customer_ledger_entry"("p_customer_id" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_deleted_id BIGINT;
    v_amount NUMERIC;
    v_entry_type TEXT;
BEGIN
    SELECT id, amount, entry_type INTO v_deleted_id, v_amount, v_entry_type
    FROM public.ledger_entries
    WHERE entity_type = 'customer'
      AND entity_id = p_customer_id::TEXT
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_deleted_id IS NOT NULL THEN
        DELETE FROM public.ledger_entries WHERE id = v_deleted_id;

        IF v_entry_type = 'debit' THEN
            UPDATE public.customers SET balance = balance - v_amount WHERE id = p_customer_id;
        ELSE
            UPDATE public.customers SET balance = balance + v_amount WHERE id = p_customer_id;
        END IF;
    END IF;

    RETURN jsonb_build_object('success', true, 'deleted_id', v_deleted_id, 'amount', v_amount, 'entry_type', v_entry_type);
END;
$$;

--
-- Name: log_fiscal_year_audit_with_metrics(bigint, "text", "jsonb", "text", integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."log_fiscal_year_audit_with_metrics"("p_fiscal_year_id" bigint, "p_action" "text", "p_details" "jsonb" DEFAULT '{}'::"jsonb", "p_user_id" "text" DEFAULT 'system'::"text", "p_execution_time_ms" integer DEFAULT NULL::integer, "p_rows_affected" integer DEFAULT NULL::integer) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  INSERT INTO public.fiscal_year_audit_log (
    fiscal_year_id, action, details, performed_by,
    execution_time_ms, rows_affected
  ) VALUES (
    p_fiscal_year_id, p_action, p_details, p_user_id::uuid,
    p_execution_time_ms, p_rows_affected
  );
EXCEPTION WHEN OTHERS THEN NULL;
END;
$$;

--
-- Name: create_raw_material_with_opening("text", "text", "text", "uuid", double precision, double precision); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."create_raw_material_with_opening"("p_code" "text", "p_name" "text", "p_unit" "text", "p_category_id" "uuid", "p_initial_quantity" double precision DEFAULT 0, "p_initial_avg_price" double precision DEFAULT 0) RETURNS "uuid"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_id uuid;
  v_min_stock double precision := 3000;
BEGIN
  INSERT INTO raw_materials (code, name, unit, category_id, quantity, default_purchase_price, minimum_stock, initial_quantity, initial_avg_price)
  VALUES (p_code, p_name, p_unit, p_category_id, p_initial_quantity, p_initial_avg_price, v_min_stock, p_initial_quantity, p_initial_avg_price)
  RETURNING id INTO v_id;

  -- Create opening batch if initial quantity > 0
  IF p_initial_quantity > 0 THEN
    INSERT INTO stock_batches (product_id, quantity, remaining_quantity, purchase_cost, entry_date, notes)
    VALUES (v_id, p_initial_quantity, p_initial_quantity, p_initial_avg_price, CURRENT_DATE, 'رصيد افتتاحي');
  END IF;

  RETURN v_id;
END;
$$;

--
-- Name: update_system_setting("text", "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."update_system_setting"("p_key" "text", "p_value" "text") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  UPDATE public.system_settings
  SET setting_value = p_value, updated_at = now()
  WHERE setting_key = p_key;

  RETURN json_build_object('success', true);
END;
$$;

--
-- Name: _safe_uuid("text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."_safe_uuid"("p_val" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
BEGIN
  RETURN p_val::UUID;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END;
$$;

--
-- Name: fiscal_years_before_upsert(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."fiscal_years_before_upsert"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  overlapping_count INT;
  current_count INT;
BEGIN
  -- Ensure start_date < end_date
  IF NEW.start_date >= NEW.end_date THEN
    RAISE EXCEPTION 'Fiscal year start_date must be before end_date.';
  END IF;

  -- Check for overlapping periods (exclude self on UPDATE)
  SELECT COUNT(*) INTO overlapping_count
  FROM public.fiscal_years
  WHERE id <> COALESCE(NEW.id, 0)
    AND NEW.start_date <= end_date
    AND NEW.end_date >= start_date;
  IF overlapping_count > 0 THEN
    RAISE EXCEPTION 'Fiscal year period overlaps with existing fiscal year.';
  END IF;

  -- Enforce only one current fiscal year
  IF NEW.is_current THEN
    SELECT COUNT(*) INTO current_count
    FROM public.fiscal_years
    WHERE id <> COALESCE(NEW.id, 0) AND is_current = TRUE;
    IF current_count > 0 THEN
      RAISE EXCEPTION 'Only one fiscal year can be marked as current.';
    END IF;
  END IF;

  -- Auto‑update timestamp
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

--
-- Name: increment_sold_cartons(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."increment_sold_cartons"("p_packing_order_id" integer, "p_additional" integer) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  UPDATE public.packing_orders
  SET sold_cartons = LEAST(sold_cartons + p_additional, carton_count)
  WHERE id = p_packing_order_id;
END;
$$;

--
-- Name: transfer_custody(integer, integer, "text", numeric, "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."transfer_custody"("p_from_treasury_id" integer, "p_to_treasury_id" integer, "p_currency" "text", "p_amount" numeric, "p_description" "text" DEFAULT ''::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_from_balance NUMERIC;
    v_to_balance   NUMERIC;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    SELECT balance INTO v_from_balance
    FROM treasury_balances
    WHERE treasury_id = p_from_treasury_id AND currency = p_currency
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'لا يوجد رصيد للخزنة المصدرة بهذه العملة';
    END IF;

    IF v_from_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ (المتوفر: %)', v_from_balance;
    END IF;

    SELECT balance INTO v_to_balance
    FROM treasury_balances
    WHERE treasury_id = p_to_treasury_id AND currency = p_currency
    FOR UPDATE;

    UPDATE treasury_balances SET balance = balance - p_amount
    WHERE treasury_id = p_from_treasury_id AND currency = p_currency;

    IF v_to_balance IS NULL THEN
        INSERT INTO treasury_balances (treasury_id, currency, balance)
        VALUES (p_to_treasury_id, p_currency, p_amount);
    ELSE
        UPDATE treasury_balances SET balance = balance + p_amount
        WHERE treasury_id = p_to_treasury_id AND currency = p_currency;
    END IF;

    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by)
    VALUES (p_from_treasury_id, 'transfer_out', p_currency, p_amount,
        v_from_balance, v_from_balance - p_amount, p_description, p_to_treasury_id, auth.uid());

    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by)
    VALUES (p_to_treasury_id, 'transfer_in', p_currency, p_amount,
        COALESCE(v_to_balance, 0), COALESCE(v_to_balance, 0) + p_amount, p_description,
        p_from_treasury_id, auth.uid());
END;
$$;

--
-- Name: create_purchase_workflow("text", "text", numeric, numeric, numeric, "text", "text", "jsonb", "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."create_purchase_workflow"("p_purchase_date" "text", "p_supplier_id" "text", "p_total_amount" numeric DEFAULT 0, "p_paid_amount" numeric DEFAULT 0, "p_discount_amount" numeric DEFAULT 0, "p_status" "text" DEFAULT 'confirmed'::"text", "p_notes" "text" DEFAULT NULL::"text", "p_items" "jsonb" DEFAULT '[]'::"jsonb", "p_warehouse_id" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_purchase_id uuid;
    v_invoice_number text;
    v_item jsonb;
    v_subtotal numeric := 0;
    v_batch_id uuid;
    v_batch_number text;
    v_current_stock numeric;
    v_new_wac numeric;
    v_seq_num integer;
    v_item_id uuid;
    v_ap_account_id uuid;
    v_inv_account_id uuid;
    v_cash_account_id uuid;
    v_material_id uuid;
BEGIN
    if auth.uid() is null then
        raise exception 'غير مصرح بهذه العملية - يرجى تسجيل الدخول';
    end if;

    v_invoice_number := 'PUR-' || to_char(now(), 'YYYYMMDD') || '-' || lpad(
        (SELECT COALESCE(MAX(CAST(substring(invoice_number FROM 14) AS integer)), 0) + 1
         FROM public.purchase_invoices
         WHERE invoice_number LIKE 'PUR-' || to_char(now(), 'YYYYMMDD') || '-%')::text, 4, '0');

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_subtotal := v_subtotal + ((v_item->>'quantity')::numeric * (v_item->>'unit_cost')::numeric);
    END LOOP;

    INSERT INTO public.purchase_invoices (
        supplier_id, invoice_number, invoice_date, due_date,
        subtotal, tax_percent, tax_amount, discount_amount,
        total_amount, paid_amount, remaining_amount,
        payment_status, status, notes, user_id, warehouse_id
    ) VALUES (
        p_supplier_id::uuid, v_invoice_number, p_purchase_date::date,
        (p_purchase_date::date + interval '30 days')::date,
        v_subtotal, 0, 0, p_discount_amount,
        p_total_amount, p_paid_amount, GREATEST(p_total_amount - p_paid_amount, 0),
        CASE WHEN p_paid_amount >= p_total_amount THEN 'paid' WHEN p_paid_amount > 0 THEN 'partial' ELSE 'unpaid' END,
        p_status, p_notes, auth.uid(), p_warehouse_id::uuid
    ) RETURNING id INTO v_purchase_id;

    v_seq_num := 1;
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_material_id := (v_item->>'product_id')::uuid;

        INSERT INTO public.purchase_invoice_items (
            invoice_id, raw_material_id, quantity, unit_cost, total_cost
        ) VALUES (
            v_purchase_id, v_material_id,
            (v_item->>'quantity')::numeric, (v_item->>'unit_cost')::numeric,
            (v_item->>'quantity')::numeric * (v_item->>'unit_cost')::numeric
        ) RETURNING id INTO v_item_id;

        v_batch_number := 'B-' || v_invoice_number || '-' || v_seq_num::text;
        INSERT INTO public.stock_batches (
            batch_number, product_id, supplier_id, warehouse_id, purchase_invoice_id,
            quantity, remaining_quantity, purchase_cost, average_cost, status
        ) VALUES (
            v_batch_number, v_material_id, p_supplier_id::uuid, p_warehouse_id::uuid, v_purchase_id,
            (v_item->>'quantity')::numeric, (v_item->>'quantity')::numeric,
            (v_item->>'unit_cost')::numeric, (v_item->>'unit_cost')::numeric, 'active'
        ) RETURNING id INTO v_batch_id;

        SELECT COALESCE(quantity, 0) INTO v_current_stock
        FROM public.raw_materials WHERE id = v_material_id;

        INSERT INTO public.stock_movements (
            movement_type, product_id, batch_id, from_warehouse_id, to_warehouse_id,
            quantity, before_quantity, after_quantity, unit_cost, total_cost,
            reference_type, reference_id, description
        ) VALUES (
            'purchase', v_material_id, v_batch_id, null, p_warehouse_id::uuid,
            (v_item->>'quantity')::numeric, v_current_stock, v_current_stock + (v_item->>'quantity')::numeric,
            (v_item->>'unit_cost')::numeric, (v_item->>'quantity')::numeric * (v_item->>'unit_cost')::numeric,
            'purchase_invoice', v_purchase_id, 'فاتورة شراء رقم ' || v_invoice_number
        );

        UPDATE public.raw_materials
        SET quantity = quantity + (v_item->>'quantity')::numeric,
            default_purchase_price = (v_item->>'unit_cost')::numeric
        WHERE id = v_material_id;

        SELECT COALESCE(SUM(remaining_quantity * purchase_cost) / NULLIF(SUM(remaining_quantity), 0), 0)
        INTO v_new_wac
        FROM public.stock_batches
        WHERE product_id = v_material_id AND status = 'active';

        UPDATE public.raw_materials
        SET default_purchase_price = COALESCE(NULLIF(v_new_wac, 0), default_purchase_price)
        WHERE id = v_material_id;

        v_seq_num := v_seq_num + 1;
    END LOOP;

    UPDATE public.suppliers
    SET outstanding_balance = outstanding_balance + (p_total_amount - p_paid_amount)
    WHERE id = p_supplier_id::uuid;

    SELECT id INTO v_ap_account_id FROM public.accounts WHERE code = '20101' OR name = 'الموردون' LIMIT 1;
    SELECT id INTO v_inv_account_id FROM public.accounts WHERE code = '10201' OR name = 'مخزن البضائع' LIMIT 1;
    SELECT id INTO v_cash_account_id FROM public.accounts WHERE code = '10101' OR name = 'الخزينة' LIMIT 1;

    if v_inv_account_id is not null then
        INSERT INTO public.transactions (transaction_date, transaction_type, reference_id, reference_type, account_id, account_name, debit, credit, description, created_by)
        VALUES (p_purchase_date::date, 'purchase', v_purchase_id, 'purchase_invoice', v_inv_account_id, 'مخزن البضائع', p_total_amount, 0, 'فاتورة شراء رقم ' || v_invoice_number, auth.uid());
        UPDATE public.accounts SET balance = balance + p_total_amount WHERE id = v_inv_account_id;
    end if;

    if v_ap_account_id is not null then
        INSERT INTO public.transactions (transaction_date, transaction_type, reference_id, reference_type, account_id, account_name, debit, credit, description, created_by)
        VALUES (p_purchase_date::date, 'purchase', v_purchase_id, 'purchase_invoice', v_ap_account_id, 'الموردون', 0, p_total_amount, 'فاتورة شراء رقم ' || v_invoice_number, auth.uid());
        UPDATE public.accounts SET balance = balance + p_total_amount WHERE id = v_ap_account_id;
    end if;

    if p_paid_amount > 0 then
        if v_ap_account_id is not null then
            INSERT INTO public.transactions (transaction_date, transaction_type, reference_id, reference_type, account_id, account_name, debit, credit, description, created_by)
            VALUES (p_purchase_date::date, 'payment', v_purchase_id, 'purchase_invoice', v_ap_account_id, 'الموردون', p_paid_amount, 0, 'سداد جزء من فاتورة شراء رقم ' || v_invoice_number, auth.uid());
            UPDATE public.accounts SET balance = balance - p_paid_amount WHERE id = v_ap_account_id;
        end if;
        if v_cash_account_id is not null then
            INSERT INTO public.transactions (transaction_date, transaction_type, reference_id, reference_type, account_id, account_name, debit, credit, description, created_by)
            VALUES (p_purchase_date::date, 'payment', v_purchase_id, 'purchase_invoice', v_cash_account_id, 'الخزينة', 0, p_paid_amount, 'سداد جزء من فاتورة شراء رقم ' || v_invoice_number, auth.uid());
            UPDATE public.accounts SET balance = balance - p_paid_amount WHERE id = v_cash_account_id;
        end if;
        INSERT INTO public.cashbox_transactions (transaction_type, amount, currency_id, reference_type, reference_id, description, payment_method, created_by)
        VALUES ('expense', p_paid_amount, (SELECT currency_id FROM public.suppliers WHERE id = p_supplier_id::uuid), 'purchase_invoice', v_purchase_id, 'سداد جزء من فاتورة شراء رقم ' || v_invoice_number, 'cash', auth.uid());
    end if;

    RETURN v_purchase_id;
END;
$$;

--
-- Name: get_my_tenant(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_my_tenant"() RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_result JSON;
BEGIN
  SELECT json_build_object(
    'tenant_id', t.id,
    'tenant_name', t.name,
    'is_active', t.is_active,
    'is_read_only', t.is_read_only,
    'max_users', t.max_users,
    'subscription_expires_at', t.subscription_expires_at,
    'plan_name', sp.name,
    'plan_period', sp.period
  ) INTO v_result
  FROM public.tenant_users tu
  JOIN public.tenants t ON t.id = tu.tenant_id
  LEFT JOIN public.subscription_plans sp ON sp.id = t.plan_id
  WHERE tu.user_id = auth.uid() AND t.is_active = true
  LIMIT 1;

  RETURN COALESCE(v_result, '{"error": "no tenant found"}'::json);
END;
$$;

--
-- Name: rpc_process_treasury_transaction(integer, "text", numeric, "text", "text", integer, "uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."rpc_process_treasury_transaction"("p_treasury_id" integer, "p_type" "text", "p_amount" numeric, "p_description" "text" DEFAULT NULL::"text", "p_reference_type" "text" DEFAULT NULL::"text", "p_reference_id" integer DEFAULT NULL::integer, "p_user_id" "uuid" DEFAULT "auth"."uid"()) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_treasury RECORD;
  v_new_balance NUMERIC;
  v_result JSONB;
BEGIN
  -- Lock treasury row
  SELECT * INTO v_treasury FROM treasuries WHERE id = p_treasury_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'treasury not found');
  END IF;

  -- Validate type
  IF p_type NOT IN ('receipt', 'payment') THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid type, must be receipt or payment');
  END IF;

  -- Validate balance for payments
  IF p_type = 'payment' AND v_treasury.balance < p_amount THEN
    RETURN jsonb_build_object('success', false, 'error', 'insufficient balance');
  END IF;

  -- Calculate new balance
  IF p_type = 'receipt' THEN
    v_new_balance := v_treasury.balance + p_amount;
  ELSE
    v_new_balance := v_treasury.balance - p_amount;
  END IF;

  -- Update treasury balance
  UPDATE treasuries SET balance = v_new_balance, updated_at = NOW() WHERE id = p_treasury_id;

  -- Insert transaction record
  INSERT INTO treasury_transactions (treasury_id, type, amount, balance_before, balance_after, description, reference_type, reference_id, created_by)
  VALUES (p_treasury_id, p_type, p_amount, v_treasury.balance, v_new_balance, p_description, p_reference_type, p_reference_id, p_user_id);

  -- Log audit
  INSERT INTO audit_logs_text (table_name, record_id, action, old_values, new_values, performed_by)
  VALUES ('treasuries', p_treasury_id::TEXT, p_type,
    jsonb_build_object('balance', v_treasury.balance),
    jsonb_build_object('balance', v_new_balance, 'amount', p_amount),
    p_user_id);

  v_result := jsonb_build_object(
    'success', true,
    'treasury_id', p_treasury_id,
    'type', p_type,
    'amount', p_amount,
    'balance_before', v_treasury.balance,
    'balance_after', v_new_balance
  );

  RETURN v_result;
END;
$$;

--
-- Name: reverse_supplier_ledger_entry("uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."reverse_supplier_ledger_entry"("p_supplier_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_deleted_id BIGINT;
    v_amount NUMERIC;
    v_entry_type TEXT;
    v_reference_type TEXT;
BEGIN
    SELECT id, amount, entry_type, reference_type INTO v_deleted_id, v_amount, v_entry_type, v_reference_type
    FROM public.ledger_entries
    WHERE entity_type = 'supplier'
      AND entity_id = p_supplier_id::TEXT
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_deleted_id IS NOT NULL THEN
        DELETE FROM public.ledger_entries WHERE id = v_deleted_id;

        IF v_entry_type = 'credit' THEN
            UPDATE public.suppliers SET outstanding_balance = outstanding_balance - v_amount WHERE id = p_supplier_id;
        ELSE
            UPDATE public.suppliers SET outstanding_balance = outstanding_balance + v_amount WHERE id = p_supplier_id;
        END IF;
    END IF;

    RETURN jsonb_build_object('success', true, 'deleted_id', v_deleted_id, 'amount', v_amount, 'entry_type', v_entry_type, 'reference_type', v_reference_type);
END;
$$;

--
-- Name: exchange_currency(bigint, character varying, character varying, numeric, numeric, numeric, "uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."exchange_currency"("p_treasury_id" bigint, "p_from_currency" character varying, "p_to_currency" character varying, "p_amount_from" numeric, "p_amount_to" numeric, "p_exchange_rate" numeric, "p_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_balance_before_from DECIMAL(15,2);
  v_balance_after_from DECIMAL(15,2);
  v_balance_before_to DECIMAL(15,2);
  v_balance_after_to DECIMAL(15,2);
BEGIN
  -- Validate amounts
  IF p_amount_from <= 0 OR p_amount_to <= 0 THEN
    RAISE EXCEPTION 'المبالغ يجب أن تكون أكبر من صفر';
  END IF;

  IF p_from_currency = p_to_currency THEN
    RAISE EXCEPTION 'لا يمكن التحويل لنفس العملة';
  END IF;

  -- Ensure from_currency balance exists and get current balance
  SELECT balance INTO v_balance_before_from
  FROM treasury_balances
  WHERE treasury_id = p_treasury_id AND currency = p_from_currency
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'لا يوجد رصيد بعملة % في هذه الخزينة', p_from_currency;
  END IF;

  IF v_balance_before_from < p_amount_from THEN
    RAISE EXCEPTION 'الرصيد غير كافٍ. المتوفر: %، المطلوب: %', v_balance_before_from, p_amount_from;
  END IF;

  -- Ensure to_currency balance exists or insert 0
  INSERT INTO treasury_balances (treasury_id, currency, balance)
  VALUES (p_treasury_id, p_to_currency, 0.00)
  ON CONFLICT (treasury_id, currency) DO NOTHING;

  SELECT balance INTO v_balance_before_to
  FROM treasury_balances
  WHERE treasury_id = p_treasury_id AND currency = p_to_currency
  FOR UPDATE;

  -- Calculate new balances
  v_balance_after_from := v_balance_before_from - p_amount_from;
  v_balance_after_to := v_balance_before_to + p_amount_to;

  -- Update balances
  UPDATE treasury_balances
  SET balance = v_balance_after_from
  WHERE treasury_id = p_treasury_id AND currency = p_from_currency;

  UPDATE treasury_balances
  SET balance = v_balance_after_to
  WHERE treasury_id = p_treasury_id AND currency = p_to_currency;

  -- Insert OUT transaction (from_currency)
  INSERT INTO treasury_transactions (
    treasury_id,
    type,
    amount,
    currency,
    balance_before,
    balance_after,
    description,
    created_by
  ) VALUES (
    p_treasury_id,
    'currency_exchange_out',
    p_amount_from,
    p_from_currency,
    v_balance_before_from,
    v_balance_after_from,
    'تحويل عملة إلى ' || p_to_currency || ' بسعر صرف ' || p_exchange_rate,
    p_user_id
  );

  -- Insert IN transaction (to_currency)
  INSERT INTO treasury_transactions (
    treasury_id,
    type,
    amount,
    currency,
    balance_before,
    balance_after,
    description,
    created_by
  ) VALUES (
    p_treasury_id,
    'currency_exchange_in',
    p_amount_to,
    p_to_currency,
    v_balance_before_to,
    v_balance_after_to,
    'تحويل عملة من ' || p_from_currency || ' بسعر صرف ' || p_exchange_rate,
    p_user_id
  );

END;
$$;

--
-- Name: create_cashbox_transaction("text", numeric, "text", "uuid", "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."create_cashbox_transaction"("p_type" "text", "p_amount" numeric, "p_description" "text" DEFAULT NULL::"text", "p_reference_id" "uuid" DEFAULT NULL::"uuid", "p_reference_type" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_id uuid;
BEGIN
    if auth.uid() is null then raise exception 'غير مصرح بهذه العملية'; end if;
    INSERT INTO public.cashbox_transactions (transaction_type, amount, description, reference_id, reference_type, user_id)
    VALUES (p_type, p_amount, p_description, p_reference_id, p_reference_type, auth.uid()) RETURNING id INTO v_id;
    RETURN v_id;
END; $$;

--
-- Name: deduct_stock_fifo(integer, numeric, "text", "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."deduct_stock_fifo"("p_product_id" integer, "p_quantity" numeric, "p_reason" "text" DEFAULT 'sale'::"text", "p_reference_id" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_remaining     NUMERIC := p_quantity;
  v_batch         RECORD;
  v_deducted      NUMERIC;
  v_before_total  NUMERIC;
  v_after_total   NUMERIC;
  v_movements     JSONB := '[]'::JSONB;
BEGIN
  -- التحقق إن في مخزون كافي
  SELECT COALESCE(SUM(remaining_quantity), 0)
  INTO v_before_total
  FROM stock_batches
  WHERE product_id = p_product_id AND status = 'active';

  IF v_before_total < p_quantity THEN
    RAISE EXCEPTION 'Insufficient stock: available=%, requested=%', v_before_total, p_quantity;
  END IF;

  -- FIFO: من أقدم batch أولاً
  FOR v_batch IN
    SELECT id, remaining_quantity, purchase_cost
    FROM stock_batches
    WHERE product_id = p_product_id AND status = 'active' AND remaining_quantity > 0
    ORDER BY created_at ASC
  LOOP
    EXIT WHEN v_remaining <= 0;

    v_deducted := LEAST(v_remaining, v_batch.remaining_quantity);

    -- تحديث الـ batch
    UPDATE stock_batches
    SET
      remaining_quantity = remaining_quantity - v_deducted,
      status = CASE
        WHEN remaining_quantity - v_deducted <= 0 THEN 'depleted'
        ELSE 'active'
      END,
      updated_at = now()
    WHERE id = v_batch.id;

    -- تسجيل حركة
    INSERT INTO stock_movements (
      movement_type, product_id, batch_id,
      quantity, before_quantity, after_quantity,
      unit_cost, total_cost, reference_type, reference_id
    ) VALUES (
      p_reason, p_product_id, v_batch.id,
      -v_deducted, v_batch.remaining_quantity, v_batch.remaining_quantity - v_deducted,
      v_batch.purchase_cost, v_deducted * v_batch.purchase_cost,
      p_reason, p_reference_id
    );

    v_movements := v_movements || jsonb_build_object(
      'batch_id', v_batch.id,
      'deducted', v_deducted
    );

    v_remaining := v_remaining - v_deducted;
  END LOOP;

  SELECT COALESCE(SUM(remaining_quantity), 0)
  INTO v_after_total
  FROM stock_batches
  WHERE product_id = p_product_id AND status = 'active';

  RETURN jsonb_build_object(
    'success', true,
    'deducted', p_quantity,
    'before_stock', v_before_total,
    'after_stock', v_after_total,
    'movements', v_movements
  );
END;
$$;

--
-- Name: is_fiscal_year_closed(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."is_fiscal_year_closed"("p_fiscal_year_id" bigint) RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $$
  SELECT COALESCE(
    (SELECT is_closed FROM public.fiscal_years WHERE id = p_fiscal_year_id),
    TRUE
  );
$$;

--
-- Name: release_closing_lock(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."release_closing_lock"() RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  UPDATE public.fiscal_year_closing_lock
  SET locked_by = NULL,
      released_at = now(),
      status = 'FREE'
  WHERE id = 1;
END;
$$;

--
-- Name: get_schema_diagnostics(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_schema_diagnostics"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_res JSONB;
BEGIN
  SELECT json_build_object(
    'pds_person1_id', (SELECT data_type FROM information_schema.columns WHERE table_name = 'profit_distribution_settings' AND column_name = 'person1_id' LIMIT 1),
    'pds_person4', (SELECT data_type FROM information_schema.columns WHERE table_name = 'profit_distribution_settings' AND column_name = 'person4_for_shipment' LIMIT 1),
    'treasuries_id', (SELECT data_type FROM information_schema.columns WHERE table_name = 'treasuries' AND column_name = 'id' LIMIT 1)
  ) INTO v_res;
  RETURN v_res;
END;
$$;

--
-- Name: get_account_balances_with_currency(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_account_balances_with_currency"("p_fiscal_year_id" bigint) RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    AS $$
  SELECT COALESCE(jsonb_object_agg(
    account_code,
    jsonb_build_object('debit', debit, 'credit', credit, 'balance', balance)
  ), '{}'::jsonb)
  FROM (
    SELECT
      a.account_code,
      COALESCE(SUM(t.debit), 0)::numeric AS debit,
      COALESCE(SUM(t.credit), 0)::numeric AS credit,
      (COALESCE(SUM(t.debit), 0) - COALESCE(SUM(t.credit), 0))::numeric AS balance
    FROM public.transactions t
    JOIN public.accounts a ON t.account_id::text = a.id::text
    JOIN public.fiscal_years fy ON fy.id = p_fiscal_year_id
    WHERE COALESCE(t.transaction_date, t.created_at::date) BETWEEN fy.start_date AND fy.end_date
    GROUP BY a.account_code
  ) totals;
$$;

--
-- Name: adjust_supplier_ledger_entry("uuid", numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."adjust_supplier_ledger_entry"("p_supplier_id" "uuid", "p_delta" numeric) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_entry_type TEXT;
BEGIN
    IF p_delta = 0 THEN
        RETURN jsonb_build_object('success', true);
    END IF;

    IF p_delta > 0 THEN
        v_entry_type := 'credit';
    ELSE
        v_entry_type := 'debit';
    END IF;

    INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, reference_type, description, created_by)
    VALUES ('supplier', p_supplier_id::TEXT, v_entry_type, ABS(p_delta), 'payment', 'تعديل حركة خزينة', auth.uid());

    UPDATE public.suppliers
    SET outstanding_balance = outstanding_balance + p_delta
    WHERE id = p_supplier_id;

    RETURN jsonb_build_object('success', true);
END;
$$;

--
-- Name: update_closing_progress(bigint, "text", integer, "text", "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."update_closing_progress"("p_fiscal_year_id" bigint, "p_status" "text", "p_progress_pct" integer, "p_current_step" "text", "p_error_message" "text" DEFAULT NULL::"text") RETURNS bigint
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  new_id BIGINT;
BEGIN
  INSERT INTO public.fiscal_year_closing_progress
    (fiscal_year_id, status, progress_pct, current_step, performed_by, error_message)
  VALUES
    (p_fiscal_year_id, p_status, p_progress_pct, p_current_step,
     auth.uid(), p_error_message)
  RETURNING id INTO new_id;

  IF p_status IN ('COMPLETED','FAILED','ROLLED_BACK') THEN
    UPDATE public.fiscal_year_closing_progress
    SET completed_at = now()
    WHERE id = new_id;
  END IF;

  RETURN new_id;
END;
$$;

--
-- Name: archive_fiscal_year(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."archive_fiscal_year"("p_fiscal_year_id" bigint) RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  UPDATE public.fiscal_years
  SET status = 'ARCHIVED', updated_at = now()
  WHERE id = p_fiscal_year_id AND status = 'CLOSED';

  RETURN FOUND;
END;
$$;

--
-- Name: deposit_bank_account(integer, numeric, "text", "text", "text", "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."deposit_bank_account"("p_account_id" integer, "p_amount" numeric, "p_description" "text" DEFAULT NULL::"text", "p_entity_type" "text" DEFAULT NULL::"text", "p_entity_id" "text" DEFAULT NULL::"text", "p_counterparty_name" "text" DEFAULT NULL::"text") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_new_balance NUMERIC;
  v_tx_id       INTEGER;
BEGIN
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
  END IF;

  UPDATE public.bank_accounts
  SET balance = balance + p_amount
  WHERE id = p_account_id
  RETURNING balance INTO v_new_balance;

  INSERT INTO public.bank_account_transactions
    (bank_account_id, type, amount, balance_before, balance_after, description, created_by, entity_type, entity_id, counterparty_name)
  VALUES
    (p_account_id, 'deposit', p_amount, v_new_balance - p_amount, v_new_balance, p_description, auth.uid(), p_entity_type, p_entity_id, p_counterparty_name)
  RETURNING id INTO v_tx_id;

  RETURN json_build_object('id', v_tx_id, 'balance', v_new_balance);
END;
$$;

--
-- Name: decrement_sold_cartons(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."decrement_sold_cartons"("p_packing_order_id" integer, "p_amount" integer) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  UPDATE public.packing_orders
  SET sold_cartons = GREATEST(sold_cartons - p_amount, 0)
  WHERE id = p_packing_order_id;
END;
$$;

--
-- Name: get_next_entry_number(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_next_entry_number"() RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
DECLARE
  v_num TEXT;
BEGIN
  v_num := 'J' || LPAD(nextval('entry_number_seq')::TEXT, 6, '0');
  RETURN v_num;
END;
$$;

--
-- Name: get_system_settings(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_system_settings"() RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_result JSON;
BEGIN
  SELECT json_object_agg(setting_key, setting_value)
  INTO v_result
  FROM public.system_settings;
  RETURN COALESCE(v_result, '{}'::json);
END;
$$;

--
-- Name: get_next_invoice_number(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_next_invoice_number"() RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    if auth.uid() is null then raise exception 'غير مصرح بهذه العملية'; end if;
    RETURN 'INV-' || to_char(now(), 'YYYYMMDD') || '-' || lpad(
        (SELECT COALESCE(MAX(CAST(substring(invoice_number FROM 10) AS integer)), 0) + 1
         FROM public.sales_invoices WHERE invoice_number LIKE 'INV-' || to_char(now(), 'YYYYMMDD') || '-%')::text,
        4, '0');
END; $$;

--
-- Name: set_updated_at(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;

--
-- Name: deduct_station_batch_allocations(integer, "jsonb"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."deduct_station_batch_allocations"("p_station_id" integer, "p_allocations" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_batch_id INTEGER;
  v_qty NUMERIC;
  v_remaining NUMERIC;
  v_unit_cost NUMERIC;
  el JSONB;
  rec RECORD;
BEGIN
  -- Phase 1: Lock and validate all batches
  FOR el IN SELECT jsonb_array_elements(p_allocations)
  LOOP
    v_batch_id  := (el->>'batch_id')::INTEGER;
    v_qty       := (el->>'quantity')::NUMERIC;

    IF v_batch_id IS NULL OR v_qty <= 0 THEN
      CONTINUE;
    END IF;

    SELECT remaining_quantity, unit_cost
      INTO v_remaining, v_unit_cost
      FROM public.station_product_batches
      WHERE id = v_batch_id
      FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'الدفعة غير موجودة: batch_id=%', v_batch_id;
    END IF;

    IF v_remaining < v_qty THEN
      RAISE EXCEPTION 'الكمية المتبقية في الدفعة % غير كافية (المتوفر: %، المطلوب: %)',
        v_batch_id, v_remaining, v_qty;
    END IF;
  END LOOP;

  -- Phase 2: Deduct from station_product_batches
  FOR el IN SELECT jsonb_array_elements(p_allocations)
  LOOP
    v_batch_id  := (el->>'batch_id')::INTEGER;
    v_qty       := (el->>'quantity')::NUMERIC;
    
    IF v_batch_id IS NOT NULL AND v_qty > 0 THEN
      UPDATE public.station_product_batches
         SET remaining_quantity = remaining_quantity - v_qty
       WHERE id = v_batch_id;
    END IF;
  END LOOP;

  -- Phase 3: Update station_products + raw_materials + stock_batches per unique product
  FOR rec IN (
    SELECT DISTINCT a->>'product_name' AS pname,
                     a->>'product_code' AS pcode
    FROM jsonb_array_elements(p_allocations) AS a
  )
  LOOP
    DECLARE
      v_mat_id     UUID;
      v_sum        NUMERIC;
      v_rem        NUMERIC;
      v_take       NUMERIC;
      v_sb         RECORD;
    BEGIN
      -- Match raw_material
      IF rec.pcode IS NOT NULL AND rec.pcode != '' THEN
        SELECT id INTO v_mat_id FROM public.raw_materials WHERE (name = rec.pname OR name = REPLACE(rec.pname, ' (مادة تعبئة)', '')) AND code = rec.pcode LIMIT 1;
      END IF;
      IF v_mat_id IS NULL THEN
        SELECT id INTO v_mat_id FROM public.raw_materials WHERE (name = rec.pname OR name = REPLACE(rec.pname, ' (مادة تعبئة)', '')) LIMIT 1;
      END IF;

      SELECT SUM((c->>'quantity')::NUMERIC) INTO v_sum
      FROM jsonb_array_elements(p_allocations) AS c
      WHERE c->>'product_name' = rec.pname;

      -- update station_products EXACT MATCH
      UPDATE public.station_products
         SET quantity = GREATEST(0, quantity - v_sum),
             updated_at = NOW()
       WHERE station_id = p_station_id
         AND product_name = rec.pname;

      -- Update raw_materials using exact mat ID
      IF v_mat_id IS NOT NULL THEN
        UPDATE public.raw_materials
           SET quantity = GREATEST(0, quantity - v_sum),
               updated_at = NOW()
         WHERE id = v_mat_id;

        -- deduct from stock_batches (FIFO)
        DECLARE
          v_rem NUMERIC;
          v_sb RECORD;
          v_take NUMERIC;
        BEGIN
          v_rem := v_sum;
          FOR v_sb IN (
             SELECT * FROM public.stock_batches
             WHERE product_id = v_mat_id
               AND remaining_quantity > 0
             ORDER BY created_at ASC
          ) LOOP
             IF v_rem <= 0 THEN EXIT; END IF;
             v_take := LEAST(v_sb.remaining_quantity, v_rem);
             UPDATE public.stock_batches
                SET remaining_quantity = remaining_quantity - v_take
              WHERE id = v_sb.id;
             v_rem := v_rem - v_take;
          END LOOP;
        END;

        
      END IF;
    END;
  END LOOP;
END;
$$;

--
-- Name: reverse_vendor_ledger_entry("text", integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."reverse_vendor_ledger_entry"("p_vendor_type" "text", "p_vendor_id" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_deleted_id BIGINT;
    v_amount NUMERIC;
    v_entry_type TEXT;
    v_table TEXT;
BEGIN
    SELECT id, amount, entry_type INTO v_deleted_id, v_amount, v_entry_type
    FROM public.ledger_entries
    WHERE entity_type = p_vendor_type
      AND entity_id = p_vendor_id::TEXT
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_deleted_id IS NOT NULL THEN
        DELETE FROM public.ledger_entries WHERE id = v_deleted_id;

        IF p_vendor_type = 'clearing_agent' THEN
            UPDATE public.clearing_agents
            SET manual_adjustment = COALESCE(manual_adjustment, 0) + CASE WHEN v_entry_type = 'credit' THEN -v_amount ELSE v_amount END,
                balance = COALESCE(balance, 0) + CASE WHEN v_entry_type = 'credit' THEN -v_amount ELSE v_amount END
            WHERE id = p_vendor_id;
        ELSIF p_vendor_type = 'shipping_company' THEN
            UPDATE public.shipping_companies
            SET manual_adjustment = COALESCE(manual_adjustment, 0) + CASE WHEN v_entry_type = 'credit' THEN -v_amount ELSE v_amount END,
                balance = COALESCE(balance, 0) + CASE WHEN v_entry_type = 'credit' THEN -v_amount ELSE v_amount END
            WHERE id = p_vendor_id;
        END IF;
    END IF;

    RETURN jsonb_build_object('success', true, 'deleted_id', v_deleted_id, 'amount', v_amount, 'entry_type', v_entry_type);
END;
$$;

--
-- Name: create_batch_from_purchase(integer, "uuid", integer, numeric, numeric, "text", "date", "date", "text", "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."create_batch_from_purchase"("p_product_id" integer, "p_supplier_id" "uuid", "p_purchase_invoice_id" integer, "p_quantity" numeric, "p_purchase_cost" numeric, "p_batch_number" "text" DEFAULT NULL::"text", "p_production_date" "date" DEFAULT NULL::"date", "p_expiry_date" "date" DEFAULT NULL::"date", "p_fruit_category" "text" DEFAULT NULL::"text", "p_notes" "text" DEFAULT NULL::"text") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_batch_id    INTEGER;
  v_batch_num   TEXT;
  v_before_qty  NUMERIC;
BEGIN
  -- توليد batch number لو مش موجود
  v_batch_num := COALESCE(
    p_batch_number,
    'BATCH-' || p_product_id::TEXT || '-' || TO_CHAR(now(), 'YYYYMMDD-HH24MISS')
  );

  -- إنشاء الـ batch
  INSERT INTO stock_batches (
    batch_number, product_id, supplier_id, purchase_invoice_id,
    quantity, remaining_quantity, purchase_cost, average_cost,
    production_date, expiry_date, fruit_category, notes, status
  ) VALUES (
    v_batch_num, p_product_id, p_supplier_id, p_purchase_invoice_id,
    p_quantity, p_quantity, p_purchase_cost, p_purchase_cost,
    p_production_date, p_expiry_date, p_fruit_category, p_notes, 'active'
  )
  RETURNING id INTO v_batch_id;

  -- تسجيل حركة المخزون
  SELECT COALESCE(SUM(remaining_quantity), 0)
  INTO v_before_qty
  FROM stock_batches
  WHERE product_id = p_product_id AND id != v_batch_id AND status = 'active';

  INSERT INTO stock_movements (
    movement_type, product_id, batch_id,
    quantity, before_quantity, after_quantity,
    unit_cost, total_cost, reference_type, reference_id
  ) VALUES (
    'purchase', p_product_id, v_batch_id,
    p_quantity, v_before_qty, v_before_qty + p_quantity,
    p_purchase_cost, p_quantity * p_purchase_cost,
    'purchase_invoice', p_purchase_invoice_id::TEXT
  );

  RETURN v_batch_id;
END;
$$;

--
-- Name: rpc_update_vendor_balances_from_costs(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."rpc_update_vendor_balances_from_costs"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  r RECORD;
BEGIN
  -- شركات الشحن
  FOR r IN
    SELECT sci.vendor_id AS comp_id,
           COALESCE(SUM(sci.total_price / NULLIF(sci.exchange_rate, 0)), 0) AS total_cost
    FROM public.shipment_cost_items sci
    WHERE sci.vendor_type = 'shipping_company'
      AND sci.vendor_id IS NOT NULL
    GROUP BY sci.vendor_id
  LOOP
    UPDATE public.shipping_companies
    SET balance = COALESCE(initial_balance, 0) + r.total_cost + COALESCE(manual_adjustment, 0)
    WHERE id = r.comp_id;
  END LOOP;

  UPDATE public.shipping_companies sc
  SET balance = COALESCE(sc.initial_balance, 0) + COALESCE(sc.manual_adjustment, 0)
  WHERE sc.id NOT IN (
    SELECT DISTINCT vendor_id
    FROM public.shipment_cost_items
    WHERE vendor_type = 'shipping_company' AND vendor_id IS NOT NULL
  );

  -- المخلصون الجمركيون
  FOR r IN
    SELECT sci.vendor_id AS agent_id,
           COALESCE(SUM(sci.total_price / NULLIF(sci.exchange_rate, 0)), 0) AS total_cost
    FROM public.shipment_cost_items sci
    WHERE sci.vendor_type = 'clearing_agent'
      AND sci.vendor_id IS NOT NULL
    GROUP BY sci.vendor_id
  LOOP
    UPDATE public.clearing_agents
    SET balance = COALESCE(initial_balance, 0) + r.total_cost + COALESCE(manual_adjustment, 0)
    WHERE id = r.agent_id;
  END LOOP;

  UPDATE public.clearing_agents ca
  SET balance = COALESCE(ca.initial_balance, 0) + COALESCE(ca.manual_adjustment, 0)
  WHERE ca.id NOT IN (
    SELECT DISTINCT vendor_id
    FROM public.shipment_cost_items
    WHERE vendor_type = 'clearing_agent' AND vendor_id IS NOT NULL
  );
END;
$$;

--
-- Name: create_invoice("text", "text", numeric, numeric, numeric, "text", "text", "text", "jsonb"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."create_invoice"("p_invoice_date" "text", "p_customer_id" "text", "p_total_amount" numeric DEFAULT 0, "p_paid_amount" numeric DEFAULT 0, "p_discount_amount" numeric DEFAULT 0, "p_status" "text" DEFAULT 'draft'::"text", "p_type" "text" DEFAULT 'retail'::"text", "p_notes" "text" DEFAULT NULL::"text", "p_items" "jsonb" DEFAULT '[]'::"jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_invoice_id uuid; v_invoice_number text; v_item jsonb; v_subtotal numeric := 0;
BEGIN
    if auth.uid() is null then raise exception 'غير مصرح بهذه العملية'; end if;
    v_invoice_number := 'INV-' || to_char(now(), 'YYYYMMDD') || '-' || lpad(
        (SELECT COALESCE(MAX(CAST(substring(invoice_number FROM 10) AS integer)), 0) + 1
         FROM public.sales_invoices WHERE invoice_number LIKE 'INV-' || to_char(now(), 'YYYYMMDD') || '-%')::text,
        4, '0');
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_subtotal := v_subtotal + ((v_item->>'quantity')::numeric * (v_item->>'unit_price')::numeric);
    END LOOP;
    INSERT INTO public.sales_invoices (
        customer_id, invoice_number, invoice_date, due_date,
        subtotal, tax_percent, tax_amount, discount_amount,
        total_amount, paid_amount, remaining_amount,
        payment_status, sale_type, status, notes, user_id
    ) VALUES (
        p_customer_id::uuid, v_invoice_number, p_invoice_date::date,
        (p_invoice_date::date + interval '30 days')::date,
        v_subtotal, 0, 0, p_discount_amount,
        p_total_amount, p_paid_amount, GREATEST(p_total_amount - p_paid_amount, 0),
        CASE WHEN p_paid_amount >= p_total_amount THEN 'paid' WHEN p_paid_amount > 0 THEN 'partial' ELSE 'unpaid' END,
        p_type, p_status, p_notes, auth.uid()
    ) RETURNING id INTO v_invoice_id;
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        INSERT INTO public.sales_invoice_items (
            invoice_id, product_id, batch_id, quantity,
            unit_price, discount_amount, total_price, cost_price
        ) VALUES (
            v_invoice_id, (v_item->>'product_id')::uuid,
            CASE WHEN v_item->>'batch_id' IS NOT NULL AND v_item->>'batch_id' != 'null' THEN (v_item->>'batch_id')::uuid ELSE NULL END,
            (v_item->>'quantity')::numeric, (v_item->>'unit_price')::numeric,
            COALESCE((v_item->>'discount')::numeric, 0),
            (v_item->>'quantity')::numeric * (v_item->>'unit_price')::numeric - COALESCE((v_item->>'discount')::numeric, 0),
            COALESCE((v_item->>'cost_price')::numeric, 0));
    END LOOP;
    UPDATE public.customers SET current_balance = current_balance + p_total_amount WHERE id = p_customer_id::uuid;
    RETURN v_invoice_id;
END; $$;

--
-- Name: generate_next_customer_code(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."generate_next_customer_code"() RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    next_id int;
BEGIN
    SELECT COALESCE(MAX(id), 0) + 1 INTO next_id FROM customers;
    RETURN 'CUST-' || LPAD(next_id::text, 4, '0');
END;
$$;

--
-- Name: update_updated_at(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."update_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

--
-- Name: acquire_closing_lock("uuid", bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."acquire_closing_lock"("p_user_id" "uuid", "p_fiscal_year_id" bigint) RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  acquired BOOLEAN := FALSE;
BEGIN
  UPDATE public.fiscal_year_closing_lock
  SET locked_by = p_user_id,
      locked_at = now(),
      fiscal_year_id = p_fiscal_year_id,
      status = 'LOCKED',
      released_at = NULL
  WHERE id = 1 AND status = 'FREE';

  GET DIAGNOSTICS acquired = ROW_COUNT;
  RETURN acquired > 0;
END;
$$;

--
-- Name: rpc_sync_station_product_batch("text", "text", "text", numeric, numeric, "text", numeric, "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."rpc_sync_station_product_batch"("p_station_id" "text", "p_product_name" "text", "p_product_code" "text", "p_quantity" numeric, "p_unit_cost" numeric, "p_supplier_name" "text" DEFAULT ''::"text", "p_exchange_rate" numeric DEFAULT 1.0, "p_currency" "text" DEFAULT 'EGP'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  -- We don't cast p_station_id manually. We rely on implicit casting for INSERT.
  -- For UPDATE, we cast the table column to TEXT to match reliably.
  UPDATE station_product_batches
  SET unit_cost = p_unit_cost,
      product_name = p_product_name,
      supplier_name = p_supplier_name,
      remaining_quantity = GREATEST(p_quantity - GREATEST(quantity - remaining_quantity, 0), 0),
      quantity = p_quantity,
      exchange_rate = p_exchange_rate,
      currency = p_currency,
      source_type = 'lot_receipt'
  WHERE station_id::TEXT = p_station_id
    AND product_code = p_product_code
    AND product_name = p_product_name
    AND (source_type = 'lot_receipt' OR source_type IS NULL);
  
  IF NOT FOUND THEN
    EXECUTE format('
      INSERT INTO station_product_batches (
        station_id, product_name, product_code, quantity, remaining_quantity, 
        unit_cost, source_type, supplier_name, exchange_rate, currency
      )
      VALUES (
        %L, %L, %L, %L, %L, %L, %L, %L, %L, %L
      )', 
      p_station_id, p_product_name, p_product_code, p_quantity, p_quantity, 
      p_unit_cost, 'lot_receipt', p_supplier_name, p_exchange_rate, p_currency
    );
  END IF;

  RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

--
-- Name: sync_customer_balance_on_initial_balance_change(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."sync_customer_balance_on_initial_balance_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.balance = COALESCE(NEW.balance, 0) + COALESCE(NEW.initial_balance, 0);
    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.initial_balance IS DISTINCT FROM OLD.initial_balance THEN
            NEW.balance = COALESCE(OLD.balance, 0) + (COALESCE(NEW.initial_balance, 0) - COALESCE(OLD.initial_balance, 0));
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

--
-- Name: rpc_reprocess_lot_receipt("text", numeric, "text", "text", "text", "uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."rpc_reprocess_lot_receipt"("p_lot_id" "text", "p_unit_cost_kg" numeric DEFAULT NULL::numeric, "p_old_station_id" "text" DEFAULT NULL::"text", "p_old_fruit_type_id" "text" DEFAULT NULL::"text", "p_old_supplier_id" "text" DEFAULT NULL::"text", "p_user_id" "uuid" DEFAULT "auth"."uid"()) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_lot                  RECORD;
  v_old_total_cost       NUMERIC := 0;
  v_total_cartons        NUMERIC := 0;
  v_net_cartons          NUMERIC := 0;
  v_unit_cost            NUMERIC := 0;
  v_total_cost           NUMERIC := 0;
  v_total_graded         NUMERIC := 0;
  v_actual_graded        NUMERIC := 0;
  v_effective_cost       NUMERIC := 0;
  v_grading              RECORD;
  v_batch_id             UUID;
  v_batch_cost           NUMERIC;
  v_batch_number         TEXT;
  v_product_name         TEXT;
  v_desc                 TEXT;
  v_station_rows_affected INTEGER := 0;
  v_station_product_qty  NUMERIC := 0;
  v_unit_str             TEXT := 'kg';
  v_reverse_station_id   BIGINT;
  v_lot_id_int           BIGINT;
  v_old_supplier_uuid    UUID;
  v_old_fruit_id         BIGINT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'غير مصرح لك بإجراء هذه العملية';
  END IF;

  v_lot_id_int := p_lot_id::BIGINT;
  SELECT lr.* INTO v_lot FROM lot_receipts lr WHERE lr.id = v_lot_id_int FOR UPDATE OF lr;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'رقم استلام المحصول غير موجود (id=%)', p_lot_id;
  END IF;

  IF COALESCE(v_lot.purchase_mode, 'weight') = 'carton' THEN
    v_unit_str := 'carton';
    v_total_cartons := COALESCE(v_lot.carton_count, 0);
    v_unit_cost := COALESCE(v_lot.price_per_carton, 0);

    -- Net cartons = net_weight_kg / weight_per_carton_kg (user-entered net field)
    IF COALESCE(v_lot.weight_per_carton_kg, 0) > 0 THEN
      v_net_cartons := ROUND(COALESCE(v_lot.net_weight_kg, 0) / v_lot.weight_per_carton_kg);
    ELSE
      v_net_cartons := v_total_cartons;
    END IF;
    IF v_net_cartons < 0 THEN v_net_cartons := 0; END IF;
  ELSE
    v_unit_str := 'kg';
    v_net_cartons := COALESCE(v_lot.net_weight_kg, v_lot.gross_weight_kg, 0);
    v_unit_cost := COALESCE(NULLIF(p_unit_cost_kg, 0), 0);
    IF v_unit_cost <= 0 AND v_lot.purchase_invoice_item_id IS NOT NULL THEN
      SELECT COALESCE(unit_cost, 0) INTO v_unit_cost FROM purchase_invoice_items WHERE id = v_lot.purchase_invoice_item_id;
    END IF;
    IF v_unit_cost <= 0 THEN
      v_unit_cost := COALESCE(v_lot.fruit_cost_per_kg, 0);
    END IF;
  END IF;

  -- Cost: carton mode uses total_cartons * price_per_carton; weight mode uses gross_weight_kg * unit_cost
  v_total_cost := CASE WHEN v_unit_str = 'carton' THEN v_total_cartons * v_unit_cost ELSE COALESCE(v_net_cartons, 0) * v_unit_cost END;

  IF v_lot.processed_gross_weight_kg IS NULL OR v_lot.processed_gross_weight_kg = 0 THEN
    v_old_total_cost := 0;
  ELSE
    v_old_total_cost := COALESCE(v_lot.total_fruit_cost, 0);
  END IF;

  v_product_name := COALESCE(v_lot.product_name, 'منتجل');
  v_reverse_station_id := COALESCE(p_old_station_id::BIGINT, v_lot.station_id);
  v_old_fruit_id := COALESCE(p_old_fruit_type_id::BIGINT, v_lot.fruit_type_id);

  BEGIN v_old_supplier_uuid := p_old_supplier_id::UUID; EXCEPTION WHEN OTHERS THEN v_old_supplier_uuid := NULL; END;

  IF v_old_supplier_uuid IS NOT NULL AND v_old_supplier_uuid <> v_lot.supplier_id THEN
    UPDATE suppliers SET outstanding_balance = GREATEST(COALESCE(outstanding_balance, 0) - v_old_total_cost, 0), updated_at = now() WHERE id = v_old_supplier_uuid;
    IF v_lot.supplier_id IS NOT NULL THEN
      UPDATE suppliers SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_total_cost, updated_at = now() WHERE id = v_lot.supplier_id;
    END IF;
  ELSE
    IF v_lot.supplier_id IS NOT NULL THEN
      UPDATE suppliers SET outstanding_balance = COALESCE(outstanding_balance, 0) - v_old_total_cost + v_total_cost, updated_at = now() WHERE id = v_lot.supplier_id;
    END IF;
  END IF;

  IF v_reverse_station_id IS NOT NULL AND COALESCE(v_lot.processed_gross_weight_kg, 0) > 0 THEN
    UPDATE station_products
      SET quantity = GREATEST(COALESCE(quantity, 0) - v_lot.processed_gross_weight_kg, 0), updated_at = now()
    WHERE station_id = v_reverse_station_id AND fruit_type_id = v_old_fruit_id AND unit = v_unit_str;

    DELETE FROM station_products WHERE station_id = v_reverse_station_id AND fruit_type_id = v_old_fruit_id AND unit = v_unit_str AND COALESCE(quantity, 0) <= 0;
  END IF;

  UPDATE lot_receipts
  SET fruit_cost_per_kg = CASE WHEN v_unit_str = 'carton' THEN v_lot.fruit_cost_per_kg ELSE v_unit_cost END,
      total_fruit_cost = v_total_cost,
      processed_gross_weight_kg = CASE WHEN v_unit_str = 'carton' THEN v_net_cartons ELSE COALESCE(v_lot.net_weight_kg, v_net_cartons) END,
      updated_at = now()
  WHERE id = v_lot_id_int;

  DELETE FROM ledger_entries WHERE entity_type = 'supplier' AND reference_type = 'lot_receipt' AND reference_text = p_lot_id;

  IF v_lot.supplier_id IS NOT NULL AND v_total_cost > 0 THEN
    v_desc := 'استلام محصول ' || v_lot.lot_number || ' - ' || v_product_name;
    INSERT INTO ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_text, description, created_by)
    VALUES ('supplier', v_lot.supplier_id::TEXT, 'credit', v_total_cost, 'EGP', 'lot_receipt', p_lot_id, v_desc, p_user_id);
  END IF;

  IF v_lot.station_id IS NOT NULL THEN
    INSERT INTO station_products (station_id, fruit_type_id, product_name, product_code, quantity, unit)
      VALUES (v_lot.station_id, v_lot.fruit_type_id, v_product_name, v_lot.lot_number, v_net_cartons, v_unit_str)
    ON CONFLICT (station_id, fruit_type_id, unit) DO UPDATE SET quantity = station_products.quantity + EXCLUDED.quantity, product_name = EXCLUDED.product_name, product_code = EXCLUDED.product_code, updated_at = now();

    GET DIAGNOSTICS v_station_rows_affected = ROW_COUNT;
    SELECT COALESCE(quantity, 0) INTO v_station_product_qty FROM station_products WHERE station_id = v_lot.station_id AND fruit_type_id = v_lot.fruit_type_id AND unit = v_unit_str LIMIT 1;
  END IF;

  SELECT COALESCE(SUM(weight_kg), 0) INTO v_actual_graded FROM lot_grading_results WHERE lot_id = v_lot_id_int AND grade IN ('A','B','C') AND weight_kg > 0;

  IF v_actual_graded <= 0 THEN
    v_total_graded := CASE WHEN v_unit_str = 'carton' THEN v_net_cartons ELSE COALESCE(v_lot.net_weight_kg, 0) END;
    v_effective_cost := CASE WHEN v_total_graded > 0 THEN v_total_cost / v_total_graded ELSE 0 END;

    UPDATE lot_receipts SET status = 'received', updated_at = now() WHERE id = v_lot_id_int;
    RETURN jsonb_build_object('success', true, 'lot_id', p_lot_id, 'lot_number', v_lot.lot_number, 'station_id', v_lot.station_id, 'fruit_type_id', v_lot.fruit_type_id, 'total_cost', v_total_cost, 'unit_cost_kg', v_unit_cost, 'effective_cost_kg', v_effective_cost, 'total_graded', v_total_graded, 'batches_created', 0, 'station_products_upserted', v_station_rows_affected, 'station_product_qty', v_station_product_qty, 'message', 'No grading rows');
  END IF;

  v_total_graded := v_actual_graded;
  v_effective_cost := CASE WHEN v_total_graded > 0 THEN v_total_cost / v_total_graded ELSE 0 END;

  FOR v_grading IN
    SELECT id, grade, weight_kg, stock_batch_id FROM lot_grading_results WHERE lot_id = v_lot_id_int AND grade IN ('A','B','C') AND weight_kg > 0 ORDER BY grade
  LOOP
    v_batch_cost := v_grading.weight_kg * v_effective_cost;
    v_batch_number := 'G-' || v_lot.lot_number || '-' || v_grading.grade;

    BEGIN
      v_batch_id := v_grading.stock_batch_id::UUID;
    EXCEPTION WHEN OTHERS THEN
      v_batch_id := NULL;
    END;

    IF v_batch_id IS NULL THEN
      SELECT id INTO v_batch_id FROM stock_batches WHERE batch_number = v_batch_number LIMIT 1;
    END IF;

    IF v_batch_id IS NOT NULL THEN
      UPDATE stock_batches
      SET purchase_cost = v_effective_cost,
          remaining_quantity = remaining_quantity + (v_grading.weight_kg - quantity),
          quantity = v_grading.weight_kg,
          supplier_name = COALESCE((SELECT name FROM suppliers WHERE id = v_lot.supplier_id), supplier_name),
          updated_at = now()
      WHERE id = v_batch_id;
    ELSE
      BEGIN
        INSERT INTO stock_batches (
          batch_number, product_name, quantity, remaining_quantity,
          purchase_cost, supplier_name, created_at, updated_at, currency, exchange_rate
        ) VALUES (
          v_batch_number, v_product_name, v_grading.weight_kg, v_grading.weight_kg,
          v_effective_cost, COALESCE((SELECT name FROM suppliers WHERE id = v_lot.supplier_id), ''),
          now(), now(),
          COALESCE(v_lot.currency, (SELECT currency FROM suppliers WHERE id = v_lot.supplier_id), 'EGP'),
          COALESCE(v_lot.exchange_rate, 1)
        )
        RETURNING id INTO v_batch_id;
      EXCEPTION WHEN OTHERS THEN
        v_batch_id := NULL;
      END;
    END IF;

    IF v_batch_id IS NOT NULL THEN
      UPDATE lot_grading_results SET stock_batch_id = v_batch_id WHERE id = v_grading.id;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'lot_id', p_lot_id,
    'lot_number', v_lot.lot_number,
    'station_id', v_lot.station_id,
    'fruit_type_id', v_lot.fruit_type_id,
    'total_cost', v_total_cost,
    'unit_cost_kg', v_unit_cost,
    'effective_cost_kg', v_effective_cost,
    'total_graded', v_total_graded,
    'batches_created', 1,
    'station_products_upserted', v_station_rows_affected,
    'station_product_qty', v_station_product_qty
  );
END;
$$;

--
-- Name: generate_invoice_number("text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."generate_invoice_number"("p_prefix" "text" DEFAULT 'INV'::"text") RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_count BIGINT;
  v_date_str TEXT;
BEGIN
  v_date_str := to_char(now(), 'YYYYMM');
  SELECT COUNT(*) + 1 INTO v_count FROM sales_invoices;
  RETURN p_prefix || '-' || v_date_str || '-' || lpad(v_count::TEXT, 6, '0');
END;
$$;

--
-- Name: spend_custody(bigint, character varying, numeric, "text", bigint, "uuid", bigint, bigint, "uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."spend_custody"("p_treasury_id" bigint, "p_currency" character varying, "p_amount" numeric, "p_description" "text", "p_customer_id" bigint DEFAULT NULL::bigint, "p_supplier_id" "uuid" DEFAULT NULL::"uuid", "p_clearing_agent_id" bigint DEFAULT NULL::bigint, "p_shipping_company_id" bigint DEFAULT NULL::bigint, "p_shareholder_id" "uuid" DEFAULT NULL::"uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_current_balance NUMERIC;
BEGIN
  SELECT balance INTO v_current_balance
  FROM public.treasury_balances
  WHERE treasury_id = p_treasury_id AND currency = p_currency;

  IF v_current_balance IS NULL OR v_current_balance < p_amount THEN
    RAISE EXCEPTION 'الرصيد غير كافٍ في % (المتوفر: %)', p_currency, COALESCE(v_current_balance, 0);
  END IF;

  UPDATE public.treasury_balances
  SET balance = balance - p_amount, updated_at = NOW()
  WHERE treasury_id = p_treasury_id AND currency = p_currency;

  INSERT INTO public.treasury_transactions (
    treasury_id, type, amount, currency, description,
    customer_id, supplier_id, clearing_agent_id, shipping_company_id, shareholder_id,
    created_by
  ) VALUES (
    p_treasury_id, 'expense', p_amount, p_currency, p_description,
    p_customer_id, p_supplier_id, p_clearing_agent_id, p_shipping_company_id, p_shareholder_id,
    auth.uid()
  );

  IF p_customer_id IS NOT NULL THEN
    UPDATE public.customers SET balance = balance + p_amount WHERE id = p_customer_id;
  END IF;
  IF p_supplier_id IS NOT NULL THEN
    UPDATE public.suppliers SET outstanding_balance = outstanding_balance - p_amount WHERE id = p_supplier_id;
  END IF;
  IF p_clearing_agent_id IS NOT NULL THEN
    UPDATE public.clearing_agents SET balance = balance - p_amount WHERE id = p_clearing_agent_id;
  END IF;
  IF p_shipping_company_id IS NOT NULL THEN
    UPDATE public.shipping_companies SET balance = balance - p_amount WHERE id = p_shipping_company_id;
  END IF;
  IF p_shareholder_id IS NOT NULL THEN
    IF p_currency = 'EGP' THEN
      UPDATE public.shareholders SET current_balance_egp = current_balance_egp - p_amount WHERE id = p_shareholder_id;
    ELSIF p_currency = 'USD' THEN
      UPDATE public.shareholders SET current_balance_usd = current_balance_usd - p_amount WHERE id = p_shareholder_id;
    ELSIF p_currency = 'EUR' THEN
      UPDATE public.shareholders SET current_balance_eur = current_balance_eur - p_amount WHERE id = p_shareholder_id;
    ELSIF p_currency = 'GBP' THEN
      UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - p_amount WHERE id = p_shareholder_id;
    END IF;
  END IF;
END;
$$;

--
-- Name: exchange_bank_currency(integer, integer, numeric, numeric, numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."exchange_bank_currency"("p_from_account_id" integer, "p_to_account_id" integer, "p_amount_from" numeric, "p_amount_to" numeric, "p_exchange_rate" numeric) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_balance_before_from NUMERIC(18,2);
  v_balance_after_from NUMERIC(18,2);
  v_balance_before_to NUMERIC(18,2);
  v_balance_after_to NUMERIC(18,2);
  v_from_currency TEXT;
  v_to_currency TEXT;
  v_user_id UUID := auth.uid();
BEGIN
  -- Validate amounts
  IF p_amount_from <= 0 OR p_amount_to <= 0 THEN
    RAISE EXCEPTION 'المبالغ يجب أن تكون أكبر من صفر';
  END IF;

  IF p_from_account_id = p_to_account_id THEN
    RAISE EXCEPTION 'لا يمكن التحويل لنفس الحساب';
  END IF;

  -- 1. Get and lock source account
  SELECT balance, currency INTO v_balance_before_from, v_from_currency
  FROM bank_accounts
  WHERE id = p_from_account_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'حساب المصدر غير موجود';
  END IF;

  IF v_balance_before_from < p_amount_from THEN
    RAISE EXCEPTION 'الرصيد غير كافٍ في حساب المصدر (المتوفر: %)', v_balance_before_from;
  END IF;

  -- 2. Get and lock destination account
  SELECT balance, currency INTO v_balance_before_to, v_to_currency
  FROM bank_accounts
  WHERE id = p_to_account_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'الحساب الهدف غير موجود';
  END IF;

  IF v_from_currency = v_to_currency THEN
    RAISE EXCEPTION 'لا يمكن التحويل بين حسابات بنفس العملة (يجب أن تكون العملات مختلفة)';
  END IF;

  -- Calculate new balances
  v_balance_after_from := v_balance_before_from - p_amount_from;
  v_balance_after_to := v_balance_before_to + p_amount_to;

  -- 3. Update source account
  UPDATE bank_accounts
  SET balance = v_balance_after_from, updated_at = now()
  WHERE id = p_from_account_id;

  -- 4. Update destination account
  UPDATE bank_accounts
  SET balance = v_balance_after_to, updated_at = now()
  WHERE id = p_to_account_id;

  -- 5. Insert transaction for source (Withdraw)
  INSERT INTO bank_account_transactions (
    bank_account_id,
    type,
    amount,
    balance_before,
    balance_after,
    description,
    created_by
  ) VALUES (
    p_from_account_id,
    'currency_exchange_out',
    p_amount_from,
    v_balance_before_from,
    v_balance_after_from,
    'تحويل عملة إلى ' || v_to_currency || ' بسعر صرف ' || p_exchange_rate::TEXT,
    v_user_id
  );

  -- 6. Insert transaction for destination (Deposit)
  INSERT INTO bank_account_transactions (
    bank_account_id,
    type,
    amount,
    balance_before,
    balance_after,
    description,
    created_by
  ) VALUES (
    p_to_account_id,
    'currency_exchange_in',
    p_amount_to,
    v_balance_before_to,
    v_balance_after_to,
    'تحويل عملة من ' || v_from_currency || ' بسعر صرف ' || p_exchange_rate::TEXT,
    v_user_id
  );

END;
$$;

--
-- Name: update_last_verified(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."update_last_verified"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE profiles
  SET last_verified_at = now()
  WHERE id = auth.uid();
END;
$$;

--
-- Name: rpc_get_export_shipment_cancel_info(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."rpc_get_export_shipment_cancel_info"("p_shipment_id" bigint) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_shipment RECORD;
  v_total_revenue NUMERIC := 0;
  v_ledger_net NUMERIC := 0;
  v_treasury_exists BOOLEAN := FALSE;
BEGIN
  SELECT * INTO v_shipment
  FROM export_shipments
  WHERE id = p_shipment_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Shipment not found');
  END IF;

  SELECT COALESCE(SUM(amount), 0)
  INTO v_total_revenue
  FROM export_shipment_items
  WHERE shipment_id = p_shipment_id;

  SELECT COALESCE(SUM(CASE WHEN entry_type = 'debit' THEN amount ELSE -amount END), 0)
  INTO v_ledger_net
  FROM ledger_entries
  WHERE entity_type = 'customer'
    AND entity_id = v_shipment.customer_id::TEXT
    AND reference_type = 'export_shipment'
    AND reference_text = p_shipment_id::TEXT;

  SELECT EXISTS(
    SELECT 1 FROM treasury_transactions
    WHERE reference_type = 'export_shipment_cancel'
      AND reference_id = p_shipment_id
  ) INTO v_treasury_exists;

  RETURN jsonb_build_object(
    'success', true,
    'status', v_shipment.status,
    'customer_id', v_shipment.customer_id,
    'customer_name', v_shipment.customer_name,
    'currency', COALESCE(v_shipment.currency, 'USD'),
    'total_revenue', v_total_revenue,
    'discount', COALESCE(v_shipment.discount_amount, 0),
    'net_amount', GREATEST(v_total_revenue - COALESCE(v_shipment.discount_amount, 0), 0),
    'ledger_net', v_ledger_net,
    'treasury_exists', v_treasury_exists,
    'is_cancellable', v_shipment.status IN ('confirmed', 'shipped', 'in_transit')
  );
END;
$$;

--
-- Name: deposit_bank_with_counterparty(integer, numeric, "text", "text", "text", "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."deposit_bank_with_counterparty"("p_account_id" integer, "p_amount" numeric, "p_description" "text" DEFAULT NULL::"text", "p_counterparty_type" "text" DEFAULT NULL::"text", "p_entity_id" "text" DEFAULT NULL::"text", "p_counterparty_name" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_currency TEXT;
  v_user_id  UUID := auth.uid();
  v_desc     TEXT;
BEGIN
  -- 1. Get account currency
  SELECT currency INTO v_currency
  FROM public.bank_accounts
  WHERE id = p_account_id;

  IF v_currency IS NULL THEN
    RAISE EXCEPTION 'Bank account % not found', p_account_id;
  END IF;

  v_desc := COALESCE(p_description, 'تحويل بنكي من ' || COALESCE(p_counterparty_name, ''));

  -- 2. Update bank account balance
  UPDATE public.bank_accounts
  SET balance = balance + p_amount
  WHERE id = p_account_id;

  -- 3. Insert transaction record
  INSERT INTO public.bank_account_transactions
    (bank_account_id, type, amount, balance_after, description, entity_type, entity_id, counterparty_name, created_by)
  VALUES (
    p_account_id,
    'deposit',
    p_amount,
    (SELECT balance FROM public.bank_accounts WHERE id = p_account_id),
    v_desc,
    p_counterparty_type,
    p_entity_id,
    p_counterparty_name,
    v_user_id
  );

  -- 4. Update counterparty balance + ledger entry (if applicable)
  IF p_counterparty_type IS NOT NULL AND p_entity_id IS NOT NULL THEN

    IF p_counterparty_type = 'customer' THEN
      UPDATE public.customers
      SET balance = balance - p_amount
      WHERE id = p_entity_id::BIGINT;

      INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by)
      VALUES ('customer', p_entity_id, 'credit', p_amount, v_currency, 'bank_transfer', v_desc, v_user_id);

    ELSIF p_counterparty_type = 'supplier' THEN
      UPDATE public.suppliers
      SET outstanding_balance = outstanding_balance + p_amount
      WHERE id = p_entity_id::UUID;

      INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by)
      VALUES ('supplier', p_entity_id, 'credit', p_amount, v_currency, 'bank_transfer', v_desc, v_user_id);

    ELSIF p_counterparty_type = 'clearing_agent' THEN
      UPDATE public.clearing_agents
      SET manual_adjustment = COALESCE(manual_adjustment, 0) + p_amount,
          balance = COALESCE(balance, 0) + p_amount
      WHERE id = p_entity_id::BIGINT;

      INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by)
      VALUES ('clearing_agent', p_entity_id, 'credit', p_amount, v_currency, 'bank_transfer', v_desc, v_user_id);

    ELSIF p_counterparty_type = 'shipping_company' THEN
      UPDATE public.shipping_companies
      SET manual_adjustment = COALESCE(manual_adjustment, 0) + p_amount,
          balance = COALESCE(balance, 0) + p_amount
      WHERE id = p_entity_id::BIGINT;

      INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by)
      VALUES ('shipping_company', p_entity_id, 'credit', p_amount, v_currency, 'bank_transfer', v_desc, v_user_id);

    ELSIF p_counterparty_type = 'shareholder' THEN
      IF v_currency = 'EGP' THEN
        UPDATE public.shareholders SET current_balance_egp = COALESCE(current_balance_egp, 0) + p_amount WHERE id = p_entity_id::UUID;
      ELSIF v_currency = 'USD' THEN
        UPDATE public.shareholders SET current_balance_usd = COALESCE(current_balance_usd, 0) + p_amount WHERE id = p_entity_id::UUID;
      ELSIF v_currency = 'EUR' THEN
        UPDATE public.shareholders SET current_balance_eur = COALESCE(current_balance_eur, 0) + p_amount WHERE id = p_entity_id::UUID;
      ELSIF v_currency = 'GBP' THEN
        UPDATE public.shareholders SET current_balance_gbp = COALESCE(current_balance_gbp, 0) + p_amount WHERE id = p_entity_id::UUID;
      END IF;

      INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by)
      VALUES ('shareholder', p_entity_id, 'credit', p_amount, v_currency, 'bank_transfer', v_desc, v_user_id);

    END IF;
  END IF;
END;
$$;

--
-- Name: return_custody(integer, integer, "text", numeric, "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."return_custody"("p_from_treasury_id" integer, "p_to_treasury_id" integer, "p_currency" "text", "p_amount" numeric, "p_description" "text" DEFAULT ''::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_from_balance NUMERIC;
    v_to_balance   NUMERIC;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    SELECT balance INTO v_from_balance
    FROM treasury_balances
    WHERE treasury_id = p_from_treasury_id AND currency = p_currency
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'لا يوجد رصيد للخزنة المصدرة بهذه العملة';
    END IF;

    IF v_from_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ (المتوفر: %)', v_from_balance;
    END IF;

    SELECT balance INTO v_to_balance
    FROM treasury_balances
    WHERE treasury_id = p_to_treasury_id AND currency = p_currency
    FOR UPDATE;

    UPDATE treasury_balances SET balance = balance - p_amount
    WHERE treasury_id = p_from_treasury_id AND currency = p_currency;

    IF v_to_balance IS NULL THEN
        INSERT INTO treasury_balances (treasury_id, currency, balance)
        VALUES (p_to_treasury_id, p_currency, p_amount);
    ELSE
        UPDATE treasury_balances SET balance = balance + p_amount
        WHERE treasury_id = p_to_treasury_id AND currency = p_currency;
    END IF;

    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by)
    VALUES (p_from_treasury_id, 'return_out', p_currency, p_amount,
        v_from_balance, v_from_balance - p_amount, p_description, p_to_treasury_id, auth.uid());

    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by)
    VALUES (p_to_treasury_id, 'return_in', p_currency, p_amount,
        COALESCE(v_to_balance, 0), COALESCE(v_to_balance, 0) + p_amount, p_description,
        p_from_treasury_id, auth.uid());
END;
$$;

--
-- Name: create_customer_account(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."create_customer_account"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $_$
DECLARE
  v_next_code INTEGER;
BEGIN
  -- Get next code: find max 11xxx customer account code and add 1
  SELECT COALESCE(MAX(account_code::int), 11000) + 1
  INTO v_next_code
  FROM accounts
  WHERE account_code ~ '^11[0-9]{3}$';

  INSERT INTO accounts (account_code, name, account_name, account_type, sort_order)
  VALUES (
    LPAD(v_next_code::TEXT, 5, '0'),
    'Customer - ' || COALESCE(NEW.name, ''),
    'عميل - ' || COALESCE(NEW.name, ''),
    'asset', 10
  );

  RETURN NEW;
END;
$_$;

--
-- Name: undo_profit_distribution("text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."undo_profit_distribution"("p_shipment_id_text" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_shipment_id BIGINT;
  v_dist RECORD;
  v_sid TEXT;
BEGIN
  v_shipment_id := p_shipment_id_text::BIGINT;
  v_sid := p_shipment_id_text;

  FOR v_dist IN
    SELECT * FROM public.shareholder_profit_distributions WHERE shipment_id = v_shipment_id
  LOOP
    DELETE FROM public.treasury_transactions
    WHERE shareholder_id = v_dist.shareholder_id
      AND description = 'توزيع أرباح - شحنة ' || v_sid
      AND type = 'deposit'
      AND currency = v_dist.currency;

    IF v_dist.currency = 'EGP' THEN
      UPDATE public.shareholders SET current_balance_egp = COALESCE(current_balance_egp,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;
    ELSIF v_dist.currency = 'USD' THEN
      UPDATE public.shareholders SET current_balance_usd = COALESCE(current_balance_usd,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;
    ELSIF v_dist.currency = 'EUR' THEN
      UPDATE public.shareholders SET current_balance_eur = COALESCE(current_balance_eur,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;
    ELSIF v_dist.currency = 'GBP' THEN
      UPDATE public.shareholders SET current_balance_gbp = COALESCE(current_balance_gbp,0) - v_dist.converted_amount WHERE id = v_dist.shareholder_id;
    END IF;
  END LOOP;

  DELETE FROM public.shareholder_profit_distributions WHERE shipment_id = v_shipment_id;
END;
$$;

--
-- Name: create_expense_category("text", "text", "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."create_expense_category"("p_name" "text", "p_color" "text", "p_currency" "text" DEFAULT 'EGP'::"text") RETURNS bigint
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  new_id bigint;
BEGIN
  INSERT INTO expense_categories (name, color, currency)
  VALUES (p_name, p_color, p_currency)
  RETURNING id INTO new_id;
  
  RETURN new_id;
END;
$$;

--
-- Name: create_purchase("text", "text", numeric, numeric, numeric, "text", "text", "jsonb"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."create_purchase"("p_purchase_date" "text", "p_supplier_id" "text", "p_total_amount" numeric DEFAULT 0, "p_paid_amount" numeric DEFAULT 0, "p_discount_amount" numeric DEFAULT 0, "p_status" "text" DEFAULT 'draft'::"text", "p_notes" "text" DEFAULT NULL::"text", "p_items" "jsonb" DEFAULT '[]'::"jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_purchase_id uuid; v_invoice_number text; v_item jsonb; v_subtotal numeric := 0;
BEGIN
    if auth.uid() is null then raise exception 'غير مصرح بهذه العملية'; end if;
    v_invoice_number := 'PUR-' || to_char(now(), 'YYYYMMDD') || '-' || lpad(
        (SELECT COALESCE(MAX(CAST(substring(invoice_number FROM 10) AS integer)), 0) + 1
         FROM public.purchase_invoices WHERE invoice_number LIKE 'PUR-' || to_char(now(), 'YYYYMMDD') || '-%')::text,
        4, '0');
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_subtotal := v_subtotal + ((v_item->>'quantity')::numeric * (v_item->>'unit_cost')::numeric);
    END LOOP;
    INSERT INTO public.purchase_invoices (
        supplier_id, invoice_number, invoice_date, due_date,
        subtotal, tax_percent, tax_amount, discount_amount,
        total_amount, paid_amount, remaining_amount,
        payment_status, status, notes, user_id
    ) VALUES (
        p_supplier_id::uuid, v_invoice_number, p_purchase_date::date,
        (p_purchase_date::date + interval '30 days')::date,
        v_subtotal, 0, 0, p_discount_amount,
        p_total_amount, p_paid_amount, GREATEST(p_total_amount - p_paid_amount, 0),
        CASE WHEN p_paid_amount >= p_total_amount THEN 'paid' WHEN p_paid_amount > 0 THEN 'partial' ELSE 'unpaid' END,
        p_status, p_notes, auth.uid()
    ) RETURNING id INTO v_purchase_id;
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        INSERT INTO public.purchase_invoice_items (
            invoice_id, product_id, quantity, unit_cost, total_cost
        ) VALUES (
            v_purchase_id, (v_item->>'product_id')::uuid,
            (v_item->>'quantity')::numeric, (v_item->>'unit_cost')::numeric,
            (v_item->>'quantity')::numeric * (v_item->>'unit_cost')::numeric);
    END LOOP;
    UPDATE public.suppliers SET outstanding_balance = outstanding_balance + p_total_amount WHERE id = p_supplier_id::uuid;
    RETURN v_purchase_id;
END; $$;

--
-- Name: get_treasury_stats(integer, boolean, "date", "date"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_treasury_stats"("p_main_treasury_id" integer, "p_all_treasuries" boolean DEFAULT false, "p_start_date" "date" DEFAULT ((CURRENT_DATE - '365 days'::interval))::"date", "p_end_date" "date" DEFAULT CURRENT_DATE) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_result JSONB;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;

    WITH stats AS (
        SELECT
            COALESCE(SUM(CASE WHEN tt.type = 'expense' THEN tt.amount ELSE 0 END), 0) AS total_expenses,
            COALESCE(SUM(CASE WHEN tt.type = 'disbursement_out' THEN tt.amount ELSE 0 END), 0) AS total_disbursements,
            COALESCE(SUM(CASE WHEN tt.type = 'return_in' THEN tt.amount ELSE 0 END), 0) AS total_returns,
            COALESCE(SUM(CASE WHEN tt.type = 'transfer_out' THEN tt.amount ELSE 0 END), 0) AS total_transfers,
            COALESCE(SUM(CASE WHEN tt.type = 'deposit' THEN tt.amount ELSE 0 END), 0) AS total_deposits,
            COUNT(*) AS total_transactions
        FROM treasury_transactions tt
        WHERE (p_all_treasuries OR tt.treasury_id = p_main_treasury_id OR tt.related_treasury_id = p_main_treasury_id)
          AND created_at::DATE >= p_start_date AND created_at::DATE <= p_end_date
    ),
    category_breakdown AS (
        SELECT ec.id, ec.name, ec.color, COALESCE(SUM(tt.amount), 0) AS total
        FROM expense_categories ec
        LEFT JOIN treasury_transactions tt ON tt.category_id = ec.id
            AND tt.type IN ('expense', 'deposit', 'withdrawal')
            AND (p_all_treasuries OR tt.treasury_id = p_main_treasury_id OR tt.related_treasury_id = p_main_treasury_id)
            AND tt.created_at::DATE >= p_start_date AND tt.created_at::DATE <= p_end_date
        GROUP BY ec.id, ec.name, ec.color ORDER BY total DESC
    ),
    currency_totals AS (
        SELECT currency, COALESCE(SUM(balance), 0) AS total
        FROM treasury_balances GROUP BY currency ORDER BY currency
    ),
    employee_custody_breakdown AS (
        SELECT tb.currency, COALESCE(SUM(tb.balance), 0) AS total
        FROM treasury_balances tb
        JOIN treasuries t ON t.id = tb.treasury_id
        WHERE t.type = 'employee'
        GROUP BY tb.currency
        ORDER BY tb.currency
    ),
    employee_custody_total AS (
        SELECT COALESCE(SUM(balance), 0) AS total
        FROM treasury_balances tb
        JOIN treasuries t ON t.id = tb.treasury_id
        WHERE t.type = 'employee'
    )
    SELECT jsonb_build_object(
        'total_expenses',         (SELECT total_expenses FROM stats),
        'total_disbursements',    (SELECT total_disbursements FROM stats),
        'total_returns',          (SELECT total_returns FROM stats),
        'total_transfers',        (SELECT total_transfers FROM stats),
        'total_deposits',         (SELECT total_deposits FROM stats),
        'total_transactions',     (SELECT total_transactions FROM stats),
        'category_breakdown',     (SELECT jsonb_agg(jsonb_build_object('id', id, 'name', name, 'color', color, 'total', total)) FROM category_breakdown),
        'currency_totals',        (SELECT jsonb_agg(jsonb_build_object('currency', currency, 'total', total)) FROM currency_totals),
        'total_employee_custody', (SELECT total FROM employee_custody_total),
        'employee_custody_breakdown', (SELECT jsonb_agg(jsonb_build_object('currency', currency, 'total', total)) FROM employee_custody_breakdown)
    ) INTO v_result;

    RETURN v_result;
END;
$$;

--
-- Name: create_supplier_journal_entry(integer, "text", numeric, boolean, "text", "date", "jsonb"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."create_supplier_journal_entry"("p_account_id" integer, "p_supplier_code" "text", "p_amount" numeric, "p_is_debit" boolean, "p_description" "text" DEFAULT NULL::"text", "p_transaction_date" "date" DEFAULT CURRENT_DATE, "p_currency_snapshot" "jsonb" DEFAULT NULL::"jsonb") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
DECLARE
  v_entry_number TEXT;
  v_counterparty_account_id INTEGER;
  v_account_delta NUMERIC;
  v_party_delta NUMERIC;
  v_ledger_type TEXT;
  v_supplier_id UUID;
BEGIN
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be positive, got %', p_amount;
  END IF;

  v_entry_number := 'J' || LPAD(nextval('entry_number_seq')::TEXT, 6, '0');

  IF p_is_debit THEN
    v_account_delta := p_amount;
    v_party_delta := p_amount;
    v_ledger_type := 'debit';
  ELSE
    v_account_delta := -p_amount;
    v_party_delta := -p_amount;
    v_ledger_type := 'credit';
  END IF;

  SELECT id, account_id INTO v_supplier_id, v_counterparty_account_id
  FROM suppliers WHERE code = p_supplier_code OR supplier_code = p_supplier_code LIMIT 1;

  INSERT INTO transactions (
    entry_number, transaction_date, account_id,
    debit, credit, description,
    currency_snapshot
  ) VALUES
    (v_entry_number, p_transaction_date, p_account_id,
     CASE WHEN p_is_debit THEN p_amount ELSE 0 END,
     CASE WHEN p_is_debit THEN 0 ELSE p_amount END,
     p_description,
     COALESCE(p_currency_snapshot, jsonb_build_object('currency', 'EGP', 'amount', p_amount, 'exchangeRate', 1.0))),
    (v_entry_number, p_transaction_date, v_counterparty_account_id,
     CASE WHEN p_is_debit THEN 0 ELSE p_amount END,
     CASE WHEN p_is_debit THEN p_amount ELSE 0 END,
     p_description,
     COALESCE(p_currency_snapshot, jsonb_build_object('currency', 'EGP', 'amount', p_amount, 'exchangeRate', 1.0)));

  UPDATE accounts SET balance = COALESCE(balance, 0) + v_account_delta WHERE id = p_account_id;
  UPDATE suppliers SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_party_delta
  WHERE code = p_supplier_code OR supplier_code = p_supplier_code;

  INSERT INTO ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by, currency_snapshot)
  VALUES ('supplier', p_supplier_code, v_ledger_type, p_amount, 'EGP', 'entry', p_description, auth.uid(), COALESCE(p_currency_snapshot, jsonb_build_object('currency', 'EGP', 'amount', p_amount, 'exchangeRate', 1.0)));

  RETURN v_entry_number;
END;
$$;

--
-- Name: create_cash_receipt("uuid", numeric, "text", "text", "text", "date"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."create_cash_receipt"("p_customer_id" "uuid", "p_amount" numeric, "p_payment_method" "text" DEFAULT 'cash'::"text", "p_reference_number" "text" DEFAULT NULL::"text", "p_notes" "text" DEFAULT NULL::"text", "p_receipt_date" "date" DEFAULT CURRENT_DATE) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_id uuid; v_num text;
BEGIN
    if auth.uid() is null then raise exception 'غير مصرح بهذه العملية'; end if;
    v_num := 'RCP-' || to_char(now(), 'YYYYMMDD') || '-' || lpad(
        (SELECT COALESCE(MAX(CAST(substring(receipt_number FROM 10) AS integer)), 0) + 1
         FROM public.cash_receipts WHERE receipt_number LIKE 'RCP-' || to_char(now(), 'YYYYMMDD') || '-%')::text, 4, '0');
    INSERT INTO public.cash_receipts (receipt_number, customer_id, amount, payment_method, reference_number, notes, receipt_date, created_by)
    VALUES (v_num, p_customer_id, p_amount, p_payment_method, p_reference_number, p_notes, p_receipt_date, auth.uid()) RETURNING id INTO v_id;
    UPDATE public.customers SET current_balance = current_balance - p_amount WHERE id = p_customer_id;
    INSERT INTO public.cashbox_transactions (transaction_type, amount, description, reference_id, reference_type, user_id)
    VALUES ('income', p_amount, 'receipt #' || v_num, v_id, 'cash_receipt', auth.uid());
    RETURN v_id;
END; $$;

--
-- Name: generate_purchase_number(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."generate_purchase_number"() RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_count BIGINT;
  v_date_str TEXT;
BEGIN
  v_date_str := to_char(now(), 'YYYYMM');
  SELECT COUNT(*) + 1 INTO v_count FROM purchase_invoices;
  RETURN 'PUR-' || v_date_str || '-' || lpad(v_count::TEXT, 6, '0');
END;
$$;

--
-- Name: verify_post_closing_integrity(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."verify_post_closing_integrity"("p_fiscal_year_id" bigint) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  _issues jsonb := '[]'::jsonb;
  _opening_entry record;
  _fy record;
BEGIN
  SELECT * INTO _fy FROM public.fiscal_years WHERE id = p_fiscal_year_id;

  -- Check FY is actually closed
  IF _fy.status != 'CLOSED' THEN
    _issues := _issues || jsonb_build_object(
      'check', 'fiscal_year_status',
      'passed', false,
      'message', 'السنة المالية ليست مغلقة'
    );
  ELSE
    _issues := _issues || jsonb_build_object(
      'check', 'fiscal_year_status',
      'passed', true,
      'message', 'الحالة مغلقة'
    );
  END IF;

  -- Check opening entries exist
  SELECT * INTO _opening_entry
  FROM public.fiscal_year_closing_entries
  WHERE fiscal_year_id = p_fiscal_year_id
    AND entry_type = 'OPENING_BALANCE'
  LIMIT 1;

  IF _opening_entry IS NULL THEN
    _issues := _issues || jsonb_build_object(
      'check', 'opening_entries',
      'passed', false,
      'message', 'لا توجد قيود افتتاحية'
    );
  ELSE
    _issues := _issues || jsonb_build_object(
      'check', 'opening_entries',
      'passed', true,
      'message', 'قيود افتتاحية موجودة'
    );
  END IF;

  -- Check backup exists
  IF EXISTS (
    SELECT 1 FROM public.fiscal_year_backup_metadata
    WHERE fiscal_year_id = p_fiscal_year_id
      AND verification_status = 'VERIFIED'
  ) THEN
    _issues := _issues || jsonb_build_object(
      'check', 'backup_verification',
      'passed', true,
      'message', 'النسخة الاحتياطية موثقة'
    );
  ELSE
    _issues := _issues || jsonb_build_object(
      'check', 'backup_verification',
      'passed', false,
      'message', 'النسخة الاحتياطية غير موثقة'
    );
  END IF;

  -- Check audit log completeness
  IF EXISTS (
    SELECT 1 FROM public.fiscal_year_audit_log
    WHERE fiscal_year_id = p_fiscal_year_id
      AND action = 'CLOSE'
  ) THEN
    _issues := _issues || jsonb_build_object(
      'check', 'audit_completeness',
      'passed', true,
      'message', 'سجل التدقيق مكتمل'
    );
  ELSE
    _issues := _issues || jsonb_build_object(
      'check', 'audit_completeness',
      'passed', false,
      'message', 'سجل التدقيق ناقص'
    );
  END IF;

  RETURN jsonb_build_object(
    'fiscal_year_id', p_fiscal_year_id,
    'all_passed', NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(_issues) AS item
      WHERE (item->>'passed')::boolean = false
    ),
    'issues', _issues,
    'checked_at', now()
  );
END;
$$;

--
-- Name: check_fiscal_year_allows_financial(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."check_fiscal_year_allows_financial"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  _fy_status text;
BEGIN
  SELECT fy.status INTO _fy_status
  FROM public.fiscal_years fy
  WHERE fy.is_current = true
    AND fy.deleted_at IS NULL
  LIMIT 1;

  IF _fy_status IN ('CLOSING', 'CLOSED') THEN
    RAISE EXCEPTION 'لا يمكن إنشاء مستندات مالية في سنة مالية %', _fy_status;
  END IF;

  RETURN NEW;
END;
$$;

--
-- Name: generate_next_station_code(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."generate_next_station_code"() RETURNS character varying
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    next_code VARCHAR(50);
    max_num INTEGER;
BEGIN
    SELECT COALESCE(MAX(CAST(SUBSTRING(code FROM 4) AS INTEGER)), 0) + 1
    INTO max_num
    FROM public.stations
    WHERE code LIKE 'STA%';
    
    next_code := 'STA' || LPAD(max_num::TEXT, 4, '0');
    RETURN next_code;
END;
$$;

--
-- Name: get_cashbox_total_out(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_cashbox_total_out"() RETURNS numeric
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    if auth.uid() is null then raise exception 'غير مصرح بهذه العملية'; end if;
    RETURN COALESCE((SELECT SUM(amount) FROM public.cashbox_transactions WHERE transaction_type = 'expense'), 0);
END; $$;

--
-- Name: rpc_edit_purchase_item_price("text", "text", numeric, "uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."rpc_edit_purchase_item_price"("p_purchase_id" "text", "p_item_id" "text", "p_new_price" numeric, "p_user_id" "uuid" DEFAULT "auth"."uid"()) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_item RECORD;
  v_purchase RECORD;
  v_old_total NUMERIC;
  v_new_item_total NUMERIC;
  v_delta NUMERIC;
  v_product_code TEXT;
  v_raw_material_id UUID;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح لك بإجراء هذه العملية';
  END IF;

  -- Get the item
  SELECT * INTO v_item
  FROM purchase_invoice_items
  WHERE id::TEXT = p_item_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'صنف المشتريات غير موجود';
  END IF;

  -- Get the purchase
  SELECT * INTO v_purchase
  FROM purchase_invoices
  WHERE id::TEXT = p_purchase_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'فاتورة المشتريات غير موجودة';
  END IF;

  -- Calculate delta
  v_old_total := COALESCE(v_item.unit_cost, 0) * COALESCE(v_item.quantity, 0);
  v_new_item_total := p_new_price * COALESCE(v_item.quantity, 0);
  v_delta := v_new_item_total - v_old_total;
  v_raw_material_id := v_item.raw_material_id;

  -- 1. Update item
  UPDATE purchase_invoice_items
  SET unit_cost = p_new_price,
      total_cost = v_new_item_total
  WHERE id::TEXT = p_item_id;

  -- 2. Update purchase totals
  UPDATE purchase_invoices
  SET subtotal = COALESCE(subtotal, 0) + v_delta,
      total_amount = COALESCE(total_amount, 0) + v_delta,
      remaining_amount = COALESCE(remaining_amount, 0) + v_delta,
      updated_at = now()
  WHERE id::TEXT = p_purchase_id;

  -- 3. Update stock_batches (match by purchase_invoice_id + product_id)
  UPDATE stock_batches
  SET purchase_cost = p_new_price,
      average_cost = p_new_price,
      updated_at = now()
  WHERE purchase_invoice_id::TEXT = p_purchase_id
    AND product_id::TEXT = v_raw_material_id::TEXT;

  -- 4. Get product code for station_product_batches
  SELECT code INTO v_product_code
  FROM raw_materials
  WHERE id = v_raw_material_id;

  -- 5. Update station_product_batches
  IF v_product_code IS NOT NULL AND v_product_code != '' THEN
    UPDATE station_product_batches
    SET unit_cost = p_new_price
    WHERE product_code = v_product_code
      AND source_type = 'purchase'
      AND (purchase_invoice_id::TEXT = p_purchase_id OR purchase_invoice_id IS NULL);
  END IF;

  -- 6. Recalculate raw_materials.default_purchase_price (weighted avg from active batches)
  -- FIX: Cast product_id to TEXT to match UUID safely
  IF v_raw_material_id IS NOT NULL THEN
    UPDATE raw_materials
    SET default_purchase_price = COALESCE(
      (SELECT SUM(purchase_cost * remaining_quantity) / NULLIF(SUM(remaining_quantity), 0)
       FROM stock_batches
       WHERE product_id::TEXT = v_raw_material_id::TEXT AND status = 'active'),
      default_purchase_price
    ),
    updated_at = now()
    WHERE id = v_raw_material_id;
  END IF;

  -- 7. Update supplier outstanding_balance
  IF v_purchase.supplier_id IS NOT NULL THEN
    UPDATE suppliers
    SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_delta
    WHERE id = v_purchase.supplier_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'delta', v_delta,
    'new_total', COALESCE(v_purchase.total_amount, 0) + v_delta
  );
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'حدث خطأ أثناء تعديل السعر: %', SQLERRM;
END;
$$;

--
-- Name: sync_supplier_outstanding_on_initial_balance_change(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."sync_supplier_outstanding_on_initial_balance_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.outstanding_balance = COALESCE(NEW.outstanding_balance, 0) + COALESCE(NEW.initial_balance, 0);
    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.initial_balance IS DISTINCT FROM OLD.initial_balance THEN
            NEW.outstanding_balance = COALESCE(OLD.outstanding_balance, 0) + (COALESCE(NEW.initial_balance, 0) - COALESCE(OLD.initial_balance, 0));
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

--
-- Name: ensure_main_treasury_currencies(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."ensure_main_treasury_currencies"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    v_account_id INTEGER;
    v_currency TEXT;
BEGIN
    IF NEW.type = 'main' THEN
        FOREACH v_currency IN ARRAY ARRAY['EGP', 'USD', 'EUR', 'GBP']
        LOOP
            SELECT id INTO v_account_id FROM accounts 
            WHERE account_code = CASE v_currency
                WHEN 'EGP' THEN '11101'
                WHEN 'USD' THEN '11102'
                WHEN 'EUR' THEN '11103'
                WHEN 'GBP' THEN '11104'
            END;

            INSERT INTO treasury_balances (treasury_id, currency, balance, account_id)
            VALUES (NEW.id, v_currency, 0, v_account_id)
            ON CONFLICT (treasury_id, currency) DO NOTHING;
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$;

--
-- Name: link_user_to_tenant("uuid", "uuid", "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."link_user_to_tenant"("p_user_id" "uuid", "p_tenant_id" "uuid", "p_role" "text" DEFAULT 'user'::"text") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_max INTEGER; v_cur INTEGER;
BEGIN
  IF EXISTS (SELECT 1 FROM public.tenant_users WHERE user_id = p_user_id AND tenant_id = p_tenant_id) THEN
    RETURN '{"success": false, "error": "already linked"}';
  END IF;
  SELECT max_users, current_users INTO v_max, v_cur FROM public.tenants WHERE id = p_tenant_id;
  IF v_cur >= v_max THEN
    RETURN json_build_object('success', false, 'error', 'تم الوصول للحد الأقصى');
  END IF;
  INSERT INTO public.tenant_users (tenant_id, user_id, role) VALUES (p_tenant_id, p_user_id, p_role);
  UPDATE public.tenants SET current_users = (SELECT COUNT(*) FROM public.tenant_users WHERE tenant_id = p_tenant_id) WHERE id = p_tenant_id;
  RETURN json_build_object('success', true);
END;
$$;

--
-- Name: force_release_stale_lock(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."force_release_stale_lock"() RETURNS boolean
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  released BOOLEAN := FALSE;
BEGIN
  UPDATE public.fiscal_year_closing_lock
  SET locked_by = NULL,
      released_at = now(),
      status = 'FREE'
  WHERE id = 1
    AND status = 'LOCKED'
    AND locked_at < (now() - INTERVAL '30 minutes');

  GET DIAGNOSTICS released = ROW_COUNT;
  RETURN released > 0;
END;
$$;

--
-- Name: rpc_validate_backup_readiness(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."rpc_validate_backup_readiness"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_table_count INT;
  v_total_rows BIGINT;
  v_recent_backups INT;
  v_result JSONB;
BEGIN
  SELECT COUNT(*) INTO v_table_count
  FROM information_schema.tables
  WHERE table_schema = 'public';

  SELECT SUM(n_live_tup)::BIGINT INTO v_total_rows
  FROM pg_stat_user_tables
  WHERE schemaname = 'public';

  SELECT COUNT(*) INTO v_recent_backups
  FROM backup_history
  WHERE created_at >= NOW() - INTERVAL '24 hours';

  v_result := jsonb_build_object(
    'success', true,
    'table_count', v_table_count,
    'total_rows', v_total_rows,
    'backups_last_24h', v_recent_backups,
    'is_ready', (v_table_count > 0)
  );

  RETURN v_result;
END;
$$;

--
-- Name: rpc_get_inventory_valuation(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."rpc_get_inventory_valuation"("p_product_id" integer DEFAULT NULL::integer, "p_warehouse_id" integer DEFAULT NULL::integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    AS $$
DECLARE
  v_result JSONB;
BEGIN
  WITH valuation AS (
    SELECT
      COALESCE(p.name, 'Unknown') AS product_name,
      p.id AS product_id,
      SUM(sb.quantity) AS total_quantity,
      SUM(sb.quantity * sb.unit_cost) AS total_value
    FROM stock_batches sb
    LEFT JOIN products p ON p.id = sb.product_id
    WHERE sb.status = 'active'
      AND (p_product_id IS NULL OR sb.product_id = p_product_id)
      AND (p_warehouse_id IS NULL OR sb.warehouse_id = p_warehouse_id)
    GROUP BY p.id, p.name
  )
  SELECT jsonb_agg(
    jsonb_build_object(
      'product_id', product_id,
      'product_name', product_name,
      'total_quantity', total_quantity,
      'total_value', total_value,
      'average_cost', CASE WHEN total_quantity > 0 THEN total_value / total_quantity ELSE 0 END
    )
  ) INTO v_result FROM valuation;

  RETURN COALESCE(v_result, '[]'::JSONB);
END;
$$;

--
-- Name: rpc_process_lot_return(bigint, numeric, "text", "uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."rpc_process_lot_return"("p_lot_id" bigint, "p_return_quantity" numeric, "p_notes" "text" DEFAULT NULL::"text", "p_user_id" "uuid" DEFAULT "auth"."uid"()) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_lot RECORD;
  v_product_name TEXT;
  v_unit_cost NUMERIC := 0;
  v_return_value NUMERIC := 0;
  v_remaining_in_batches NUMERIC := 0;
  v_batch RECORD;
  v_qty_to_deduct NUMERIC;
  v_desc TEXT;
BEGIN
  IF p_return_quantity <= 0 THEN
    RAISE EXCEPTION 'الكمية المرتجعة يجب أن تكون أكبر من الصفر';
  END IF;

  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'يجب تسجيل الدخول لإتمام المرتجع';
  END IF;

  -- 1. Get the lot details
  SELECT lr.*, p.name AS product_name_ar, p.name AS product_name_en
  INTO v_lot
  FROM lot_receipts lr
  LEFT JOIN fruit_types p ON p.id = lr.fruit_type_id
  WHERE lr.id = p_lot_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'سجل الاستلام غير موجود';
  END IF;

  v_product_name := COALESCE(NULLIF(v_lot.product_name_ar, ''), NULLIF(v_lot.product_name_en, ''), 'منتج');
  
  -- USE THE ORIGINAL PRICE (Gross Weight basis) instead of the inflated net price (fruit_cost_per_kg)
  v_unit_cost := COALESCE(v_lot.total_fruit_cost / NULLIF(v_lot.gross_weight_kg, 0), 0);
  
  v_return_value := p_return_quantity * v_unit_cost;

  -- 2. Check remaining quantity in station_product_batches
  SELECT COALESCE(SUM(remaining_quantity), 0)
  INTO v_remaining_in_batches
  FROM station_product_batches
  WHERE product_code = v_lot.lot_number
    AND station_id = v_lot.station_id;

  IF v_remaining_in_batches < p_return_quantity THEN
    RAISE EXCEPTION 'الكمية المرتجعة أكبر من الكمية المتبقية من المحصول (%)', v_remaining_in_batches;
  END IF;

  -- 3. Deduct from station_product_batches (FIFO-style for the same lot)
  v_qty_to_deduct := p_return_quantity;
  
  FOR v_batch IN 
    SELECT id, remaining_quantity 
    FROM station_product_batches 
    WHERE product_code = v_lot.lot_number 
      AND station_id = v_lot.station_id 
      AND remaining_quantity > 0
    ORDER BY id ASC
    FOR UPDATE
  LOOP
    IF v_qty_to_deduct <= 0 THEN
      EXIT;
    END IF;

    IF v_batch.remaining_quantity >= v_qty_to_deduct THEN
      UPDATE station_product_batches 
      SET remaining_quantity = remaining_quantity - v_qty_to_deduct 
      WHERE id = v_batch.id;
      
      v_qty_to_deduct := 0;
    ELSE
      v_qty_to_deduct := v_qty_to_deduct - v_batch.remaining_quantity;
      
      UPDATE station_product_batches 
      SET remaining_quantity = 0 
      WHERE id = v_batch.id;
    END IF;
  END LOOP;

  -- 4. Deduct from overall station_products
  UPDATE station_products
  SET quantity = GREATEST(COALESCE(quantity, 0) - p_return_quantity, 0),
      updated_at = now()
  WHERE station_id = v_lot.station_id
    AND product_name = v_product_name;

  -- Delete zero-quantity station products
  DELETE FROM station_products
  WHERE station_id = v_lot.station_id
    AND product_name = v_product_name
    AND COALESCE(quantity, 0) <= 0;

  -- 5. Insert into lot_returns
  INSERT INTO lot_returns (
    lot_receipt_id, supplier_id, station_id, returned_quantity, return_value, notes, created_by
  ) VALUES (
    v_lot.id, v_lot.supplier_id, v_lot.station_id, p_return_quantity, v_return_value, p_notes, p_user_id
  );

  -- 6. Supplier Financials
  IF v_lot.supplier_id IS NOT NULL THEN
    -- Decrease what we owe the supplier (we gave them back goods, so our debt decreases)
    UPDATE suppliers
    SET outstanding_balance = COALESCE(outstanding_balance, 0) - v_return_value,
        updated_at = now()
    WHERE id = v_lot.supplier_id;

    -- Debit entry (lowers the credit balance we owe)
    v_desc := 'مرتجع محصول ' || v_lot.lot_number || ' - ' || v_product_name;
    INSERT INTO ledger_entries (
      entity_type, entity_id, entry_type, amount, reference_type, reference_text, description, created_by
    ) VALUES (
      'supplier', v_lot.supplier_id::TEXT, 'debit', v_return_value, 'lot_return', v_lot.id::TEXT, v_desc, p_user_id
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'returned_quantity', p_return_quantity,
    'return_value', v_return_value,
    'unit_cost_used', v_unit_cost
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$$;

--
-- Name: upgrade_tenant_subscription("uuid", "uuid", integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."upgrade_tenant_subscription"("p_tenant_id" "uuid", "p_plan_id" "uuid", "p_duration_months" integer DEFAULT NULL::integer) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_months INTEGER;
  v_expires_at TIMESTAMPTZ;
BEGIN
  -- Get plan duration if not specified
  IF p_duration_months IS NULL THEN
    SELECT duration_months INTO v_months
    FROM public.subscription_plans
    WHERE id = p_plan_id;
  ELSE
    v_months := p_duration_months;
  END IF;

  v_expires_at := now() + (v_months || ' months')::INTERVAL;

  UPDATE public.tenants
  SET plan_id = p_plan_id,
      subscription_expires_at = v_expires_at,
      is_active = true,
      updated_at = now()
  WHERE id = p_tenant_id;

  RETURN json_build_object(
    'success', true,
    'expires_at', v_expires_at,
    'plan_id', p_plan_id
  );
END;
$$;

--
-- Name: get_cashbox_balance(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_cashbox_balance"() RETURNS numeric
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_bal numeric := 0;
BEGIN
    if auth.uid() is null then raise exception 'غير مصرح بهذه العملية'; end if;
    SELECT COALESCE(SUM(CASE WHEN transaction_type = 'income' THEN amount ELSE 0 END) -
        SUM(CASE WHEN transaction_type = 'expense' THEN amount ELSE 0 END), 0) INTO v_bal
    FROM public.cashbox_transactions;
    RETURN v_bal;
END; $$;

--
-- Name: create_profitability_snapshot_on_close(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."create_profitability_snapshot_on_close"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  IF NEW.status = 'closed' AND OLD.status != 'closed' THEN
    INSERT INTO shipment_profitability_snapshots (
      shipment_id,
      shipment_no,
      revenue_foreign,
      revenue_local,
      fruit_cost,
      packing_cost,
      logistics_cost,
      administrative_cost,
      other_cost,
      total_cost,
      gross_profit,
      net_profit,
      gross_margin,
      net_margin,
      cost_per_carton,
      cost_per_kg,
      cost_per_pallet,
      cartons,
      net_weight,
      pallets,
      exchange_rate,
      currency_code,
      created_by
    )
    SELECT 
      NEW.id,
      NEW.shipment_no,
      COALESCE(NEW.total_revenue_foreign, 0),
      COALESCE(NEW.total_revenue_egp, 0),
      COALESCE(NEW.total_fruit_cost, 0),
      COALESCE(NEW.total_packing_material_cost, 0),
      COALESCE(NEW.freight_cost, 0) + COALESCE(NEW.insurance_cost, 0) + COALESCE(NEW.clearance_cost, 0),
      0, -- administrative_cost (from breakdown)
      COALESCE(NEW.other_costs, 0),
      COALESCE(NEW.total_landed_cost, 0),
      COALESCE(NEW.gross_profit, 0),
      COALESCE(NEW.net_profit, 0),
      CASE WHEN COALESCE(NEW.total_revenue_egp, 0) > 0 
           THEN (COALESCE(NEW.gross_profit, 0) / COALESCE(NEW.total_revenue_egp, 1) * 100) 
           ELSE 0 END,
      CASE WHEN COALESCE(NEW.total_revenue_egp, 0) > 0 
           THEN (COALESCE(NEW.net_profit, 0) / COALESCE(NEW.total_revenue_egp, 1) * 100) 
           ELSE 0 END,
      CASE WHEN COALESCE(NEW.carton_count, 0) > 0 
           THEN (COALESCE(NEW.total_landed_cost, 0) / COALESCE(NEW.carton_count, 1)) 
           ELSE 0 END,
      CASE WHEN COALESCE(NEW.net_weight, 0) > 0 
           THEN (COALESCE(NEW.total_landed_cost, 0) / COALESCE(NEW.net_weight, 1)) 
           ELSE 0 END,
      CASE WHEN COALESCE(NEW.pallet_count, 0) > 0 
           THEN (COALESCE(NEW.total_landed_cost, 0) / COALESCE(NEW.pallet_count, 1)) 
           ELSE 0 END,
      COALESCE(NEW.carton_count, 0),
      COALESCE(NEW.net_weight, 0),
      COALESCE(NEW.pallet_count, 0),
      COALESCE(NEW.exchange_rate, 1),
      COALESCE(NEW.currency_code, 'USD'),
      auth.uid();
  END IF;
  RETURN NEW;
END;
$$;

--
-- Name: check_tenant_read_only("uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."check_tenant_read_only"("p_user_id" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_is_read_only BOOLEAN;
BEGIN
  SELECT t.is_read_only INTO v_is_read_only
  FROM public.tenant_users tu
  JOIN public.tenants t ON t.id = tu.tenant_id
  WHERE tu.user_id = p_user_id AND t.is_active = true
  LIMIT 1;
  RETURN COALESCE(v_is_read_only, false);
END;
$$;

--
-- Name: clear_cheque(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."clear_cheque"("p_cheque_id" bigint) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_cheque RECORD;
    v_desc TEXT;
    v_bank_id INTEGER;
    v_bank_bal NUMERIC;
BEGIN
    SELECT * INTO v_cheque
    FROM public.cheques
    WHERE id = p_cheque_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'الشيك غير موجود';
    END IF;

    IF v_cheque.status != 'pending' THEN
        RAISE EXCEPTION 'لا يمكن تسوية شيك بحالة %', v_cheque.status;
    END IF;

    IF v_cheque.type = 'outgoing' THEN
        v_desc := 'صرف شيك رقم: ' || v_cheque.cheque_number;
    ELSE
        v_desc := 'تحصيل شيك رقم: ' || v_cheque.cheque_number;
    END IF;

    IF v_cheque.type = 'outgoing' THEN
        SELECT id, balance INTO v_bank_id, v_bank_bal
        FROM public.bank_accounts
        WHERE currency = v_cheque.currency
        LIMIT 1
        FOR UPDATE;

        IF v_bank_id IS NULL THEN
            RAISE EXCEPTION 'لا توجد حساب بنكي بهذه العملة';
        END IF;

        IF v_bank_bal < v_cheque.amount THEN
            RAISE EXCEPTION 'الرصيد غير كافٍ في الحساب البنكي (% متوفر)', v_bank_bal;
        END IF;

        UPDATE public.bank_accounts
        SET balance = balance - v_cheque.amount, updated_at = now()
        WHERE id = v_bank_id;

        INSERT INTO public.bank_account_transactions
            (bank_account_id, type, amount, balance_before, balance_after, description, created_by)
        VALUES (v_bank_id, 'withdraw', v_cheque.amount, v_bank_bal, v_bank_bal - v_cheque.amount, v_desc, auth.uid());

        IF v_cheque.counterparty_type = 'customer' AND v_cheque.counterparty_id IS NOT NULL THEN
            UPDATE public.customers
            SET balance = balance + v_cheque.amount
            WHERE id = v_cheque.counterparty_id;
            INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by)
            VALUES ('customer', v_cheque.counterparty_id::TEXT, 'debit', v_cheque.amount, v_cheque.currency, 'cheque_cleared_outgoing', v_desc, auth.uid());
        END IF;

        IF v_cheque.counterparty_type = 'supplier' AND v_cheque.supplier_id IS NOT NULL THEN
            UPDATE public.suppliers
            SET outstanding_balance = outstanding_balance - v_cheque.amount
            WHERE id = v_cheque.supplier_id;
            INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by)
            VALUES ('supplier', v_cheque.supplier_id, 'debit', v_cheque.amount, v_cheque.currency, 'cheque_cleared_outgoing', v_desc, auth.uid());
        END IF;

        IF v_cheque.counterparty_type = 'clearing_agent' AND v_cheque.clearing_agent_id IS NOT NULL THEN
            UPDATE public.clearing_agents
            SET balance = balance - v_cheque.amount
            WHERE id = v_cheque.clearing_agent_id;
            INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by)
            VALUES ('clearing_agent', v_cheque.clearing_agent_id::TEXT, 'debit', v_cheque.amount, v_cheque.currency, 'cheque_cleared_outgoing', v_desc, auth.uid());
        END IF;

        IF v_cheque.counterparty_type = 'shipping_company' AND v_cheque.shipping_company_id IS NOT NULL THEN
            UPDATE public.shipping_companies
            SET balance = balance - v_cheque.amount
            WHERE id = v_cheque.shipping_company_id;
            INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by)
            VALUES ('shipping_company', v_cheque.shipping_company_id::TEXT, 'debit', v_cheque.amount, v_cheque.currency, 'cheque_cleared_outgoing', v_desc, auth.uid());
        END IF;

        IF v_cheque.counterparty_type = 'shareholder' AND v_cheque.shareholder_id IS NOT NULL THEN
            IF v_cheque.currency = 'EGP' THEN
                UPDATE public.shareholders SET current_balance_egp = current_balance_egp - v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_cheque.currency = 'USD' THEN
                UPDATE public.shareholders SET current_balance_usd = current_balance_usd - v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_cheque.currency = 'EUR' THEN
                UPDATE public.shareholders SET current_balance_eur = current_balance_eur - v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_cheque.currency = 'GBP' THEN
                UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - v_cheque.amount WHERE id = v_cheque.shareholder_id;
            END IF;
            INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by)
            VALUES ('shareholder', v_cheque.shareholder_id::TEXT, 'debit', v_cheque.amount, v_cheque.currency, 'cheque_cleared_outgoing', v_desc, auth.uid());
        END IF;

    ELSIF v_cheque.type = 'incoming' THEN
        SELECT id, balance INTO v_bank_id, v_bank_bal
        FROM public.bank_accounts
        WHERE currency = v_cheque.currency
        LIMIT 1
        FOR UPDATE;

        IF v_bank_id IS NULL THEN
            RAISE EXCEPTION 'لا توجد حساب بنكي بهذه العملة';
        END IF;

        UPDATE public.bank_accounts
        SET balance = balance + v_cheque.amount, updated_at = now()
        WHERE id = v_bank_id;

        INSERT INTO public.bank_account_transactions
            (bank_account_id, type, amount, balance_before, balance_after, description, created_by)
        VALUES (v_bank_id, 'deposit', v_cheque.amount, v_bank_bal, v_bank_bal + v_cheque.amount, v_desc, auth.uid());

        IF v_cheque.counterparty_type = 'customer' AND v_cheque.counterparty_id IS NOT NULL THEN
            UPDATE public.customers
            SET balance = balance - v_cheque.amount
            WHERE id = v_cheque.counterparty_id;
            INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by)
            VALUES ('customer', v_cheque.counterparty_id::TEXT, 'credit', v_cheque.amount, v_cheque.currency, 'cheque_cleared_incoming', v_desc, auth.uid());
        END IF;

        IF v_cheque.counterparty_type = 'supplier' AND v_cheque.supplier_id IS NOT NULL THEN
            UPDATE public.suppliers
            SET outstanding_balance = outstanding_balance + v_cheque.amount
            WHERE id = v_cheque.supplier_id;
            INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by)
            VALUES ('supplier', v_cheque.supplier_id, 'credit', v_cheque.amount, v_cheque.currency, 'cheque_cleared_incoming', v_desc, auth.uid());
        END IF;

        IF v_cheque.counterparty_type = 'clearing_agent' AND v_cheque.clearing_agent_id IS NOT NULL THEN
            UPDATE public.clearing_agents
            SET balance = balance + v_cheque.amount
            WHERE id = v_cheque.clearing_agent_id;
            INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by)
            VALUES ('clearing_agent', v_cheque.clearing_agent_id::TEXT, 'credit', v_cheque.amount, v_cheque.currency, 'cheque_cleared_incoming', v_desc, auth.uid());
        END IF;

        IF v_cheque.counterparty_type = 'shipping_company' AND v_cheque.shipping_company_id IS NOT NULL THEN
            UPDATE public.shipping_companies
            SET balance = balance + v_cheque.amount
            WHERE id = v_cheque.shipping_company_id;
            INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by)
            VALUES ('shipping_company', v_cheque.shipping_company_id::TEXT, 'credit', v_cheque.amount, v_cheque.currency, 'cheque_cleared_incoming', v_desc, auth.uid());
        END IF;

        IF v_cheque.counterparty_type = 'shareholder' AND v_cheque.shareholder_id IS NOT NULL THEN
            IF v_cheque.currency = 'EGP' THEN
                UPDATE public.shareholders SET current_balance_egp = current_balance_egp + v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_cheque.currency = 'USD' THEN
                UPDATE public.shareholders SET current_balance_usd = current_balance_usd + v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_cheque.currency = 'EUR' THEN
                UPDATE public.shareholders SET current_balance_eur = current_balance_eur + v_cheque.amount WHERE id = v_cheque.shareholder_id;
            ELSIF v_cheque.currency = 'GBP' THEN
                UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp + v_cheque.amount WHERE id = v_cheque.shareholder_id;
            END IF;
            INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by)
            VALUES ('shareholder', v_cheque.shareholder_id::TEXT, 'credit', v_cheque.amount, v_cheque.currency, 'cheque_cleared_incoming', v_desc, auth.uid());
        END IF;

    END IF;

    UPDATE public.cheques
    SET status = 'cleared', cleared_at = NOW()
    WHERE id = p_cheque_id;

    RETURN jsonb_build_object('success', true);
END;
$$;

--
-- Name: get_balance_before_date_rpc("text", "date"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_balance_before_date_rpc"("p_account_id" "text", "p_before_date" "date") RETURNS TABLE("debit" numeric, "credit" numeric)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
  SELECT
    COALESCE(SUM(debit), 0)::numeric,
    COALESCE(SUM(credit), 0)::numeric
  FROM transactions
  WHERE account_id::text = p_account_id
    AND transaction_date::date < p_before_date;
$$;

--
-- Name: get_account_total_by_id_rpc("text", "date", "date"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_account_total_by_id_rpc"("p_account_id" "text", "p_from" "date" DEFAULT NULL::"date", "p_to" "date" DEFAULT NULL::"date") RETURNS TABLE("debit" numeric, "credit" numeric)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
  SELECT
    COALESCE(SUM(debit), 0)::numeric,
    COALESCE(SUM(credit), 0)::numeric
  FROM transactions
  WHERE account_id::text = p_account_id
    AND (p_from IS NULL OR transaction_date::date >= p_from)
    AND (p_to IS NULL OR transaction_date::date <= p_to);
$$;

--
-- Name: check_fiscal_year_allows_inventory(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."check_fiscal_year_allows_inventory"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  _fy_status text;
BEGIN
  SELECT fy.status INTO _fy_status
  FROM public.fiscal_years fy
  WHERE fy.is_current = true
    AND fy.deleted_at IS NULL
  LIMIT 1;

  IF _fy_status IN ('CLOSING', 'CLOSED') THEN
    RAISE EXCEPTION 'لا يمكن إجراء حركات مخزون في سنة مالية %', _fy_status;
  END IF;

  RETURN NEW;
END;
$$;

--
-- Name: update_cheques_updated_at(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."update_cheques_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

--
-- Name: get_server_time(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_server_time"() RETURNS timestamp with time zone
    LANGUAGE "sql" STABLE
    AS $$ SELECT now(); $$;

--
-- Name: get_cashbox_total_in(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_cashbox_total_in"() RETURNS numeric
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    if auth.uid() is null then raise exception 'غير مصرح بهذه العملية'; end if;
    RETURN COALESCE((SELECT SUM(amount) FROM public.cashbox_transactions WHERE transaction_type = 'income'), 0);
END; $$;

--
-- Name: get_next_supplier_code(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_next_supplier_code"() RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
declare
  next_num int;
  next_code text;
begin
  select coalesce(
    max(substring(coalesce(code, supplier_code) from '[0-9]+')::int), 
    0
  ) + 1 
  into next_num 
  from public.suppliers;

  next_code := 'SUPP-' || lpad(next_num::text, 4, '0');
  return next_code;
end;
$$;

--
-- Name: receive_payment(character varying, numeric, character varying, character varying, bigint, "uuid", "uuid", "text", "text", bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."receive_payment"("p_receipt_type" character varying, "p_amount" numeric, "p_currency" character varying, "p_counterparty_type" character varying DEFAULT NULL::character varying, "p_counterparty_id" bigint DEFAULT NULL::bigint, "p_supplier_id" "uuid" DEFAULT NULL::"uuid", "p_shareholder_id" "uuid" DEFAULT NULL::"uuid", "p_description" "text" DEFAULT NULL::"text", "p_notes" "text" DEFAULT NULL::"text", "p_treasury_id" bigint DEFAULT NULL::bigint) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_treasury_id BIGINT;
  v_balance     NUMERIC;
  v_tx_id       BIGINT;
BEGIN
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
  END IF;

  IF p_treasury_id IS NOT NULL THEN
    v_treasury_id := p_treasury_id;
  ELSE
    SELECT id INTO v_treasury_id
    FROM public.treasuries
    WHERE type = 'main' AND user_id = auth.uid()
    LIMIT 1;
    IF v_treasury_id IS NULL THEN
      SELECT id INTO v_treasury_id FROM public.treasuries WHERE type = 'main' LIMIT 1;
    END IF;
    IF v_treasury_id IS NULL THEN
      RAISE EXCEPTION 'لم يتم العثور على الخزينة الرئيسية.';
    END IF;
  END IF;

  INSERT INTO public.treasury_balances (treasury_id, currency, balance)
  VALUES (v_treasury_id, p_currency, p_amount)
  ON CONFLICT (treasury_id, currency) DO UPDATE
  SET balance = treasury_balances.balance + p_amount
  RETURNING balance INTO v_balance;

  INSERT INTO public.treasury_transactions (
    treasury_id, type, amount, currency, description,
    customer_id, supplier_id, clearing_agent_id, shipping_company_id, shareholder_id,
    created_by
  ) VALUES (
    v_treasury_id, 'deposit', p_amount, p_currency, COALESCE(p_description, 'استلام ' || p_receipt_type),
    CASE WHEN p_counterparty_type = 'customer' THEN p_counterparty_id ELSE NULL END,
    CASE WHEN p_counterparty_type = 'supplier' THEN p_supplier_id ELSE NULL END,
    CASE WHEN p_counterparty_type = 'clearing_agent' THEN p_counterparty_id ELSE NULL END,
    CASE WHEN p_counterparty_type = 'shipping_company' THEN p_counterparty_id ELSE NULL END,
    CASE WHEN p_counterparty_type = 'shareholder' THEN p_shareholder_id ELSE NULL END,
    auth.uid()
  ) RETURNING id INTO v_tx_id;

  IF p_counterparty_type = 'customer' AND p_counterparty_id IS NOT NULL THEN
    UPDATE public.customers SET balance = balance - p_amount WHERE id = p_counterparty_id;
    INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
    VALUES ('customer', p_counterparty_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, COALESCE(p_description, 'استلام ' || p_receipt_type), auth.uid());
  END IF;

  IF p_counterparty_type = 'supplier' AND p_supplier_id IS NOT NULL THEN
    UPDATE public.suppliers SET outstanding_balance = outstanding_balance + p_amount WHERE id = p_supplier_id;
    INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
    VALUES ('supplier', p_supplier_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, COALESCE(p_description, 'استلام ' || p_receipt_type), auth.uid());
  END IF;

  IF p_counterparty_type = 'clearing_agent' AND p_counterparty_id IS NOT NULL THEN
    UPDATE public.clearing_agents
    SET manual_adjustment = COALESCE(manual_adjustment, 0) + p_amount,
        balance = COALESCE(balance, 0) + p_amount
    WHERE id = p_counterparty_id;
    INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
    VALUES ('clearing_agent', p_counterparty_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, COALESCE(p_description, 'استلام ' || p_receipt_type), auth.uid());
  END IF;

  IF p_counterparty_type = 'shipping_company' AND p_counterparty_id IS NOT NULL THEN
    UPDATE public.shipping_companies
    SET manual_adjustment = COALESCE(manual_adjustment, 0) + p_amount,
        balance = COALESCE(balance, 0) + p_amount
    WHERE id = p_counterparty_id;
    INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
    VALUES ('shipping_company', p_counterparty_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, COALESCE(p_description, 'استلام ' || p_receipt_type), auth.uid());
  END IF;

  IF p_counterparty_type = 'shareholder' AND p_shareholder_id IS NOT NULL THEN
    IF p_currency = 'EGP' THEN
      UPDATE public.shareholders SET current_balance_egp = current_balance_egp + p_amount WHERE id = p_shareholder_id;
    ELSIF p_currency = 'USD' THEN
      UPDATE public.shareholders SET current_balance_usd = current_balance_usd + p_amount WHERE id = p_shareholder_id;
    ELSIF p_currency = 'EUR' THEN
      UPDATE public.shareholders SET current_balance_eur = current_balance_eur + p_amount WHERE id = p_shareholder_id;
    ELSIF p_currency = 'GBP' THEN
      UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp + p_amount WHERE id = p_shareholder_id;
    END IF;
    INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, reference_id, description, created_by)
    VALUES ('shareholder', p_shareholder_id::TEXT, 'credit', p_amount, p_currency, 'receive', v_tx_id, COALESCE(p_description, 'استلام ' || p_receipt_type), auth.uid());
  END IF;

  RETURN jsonb_build_object('success', true, 'treasury_tx_id', v_tx_id);
END;
$$;

--
-- Name: insert_packing_cost_ledger_entry("text", numeric, "text", "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."insert_packing_cost_ledger_entry"("p_supplier_id" "text", "p_amount" numeric, "p_description" "text", "p_currency" "text" DEFAULT 'EGP'::"text") RETURNS bigint
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_id BIGINT;
BEGIN
    INSERT INTO public.ledger_entries (
        entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by
    ) VALUES (
        'supplier', p_supplier_id, 'credit', p_amount, p_currency, 'packing_cost_item', p_description, auth.uid()
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

--
-- Name: audit_trigger_func(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."audit_trigger_func"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $_$
DECLARE
    v_old_data jsonb;
    v_new_data jsonb;
    v_changed_fields text[];
    v_record_id_text text;
    v_is_uuid boolean;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_old_data := to_jsonb(OLD);
        v_record_id_text := OLD.id::text;
    ELSIF TG_OP IN ('UPDATE', 'INSERT') THEN
        v_new_data := to_jsonb(NEW);
        v_record_id_text := NEW.id::text;
        IF TG_OP = 'UPDATE' THEN
            v_old_data := to_jsonb(OLD);
            SELECT array_agg(key) INTO v_changed_fields
            FROM jsonb_each(v_new_data)
            WHERE v_old_data->>key IS DISTINCT FROM v_new_data->>key
              AND key != 'updated_at';
        END IF;
    END IF;

    -- Check if record_id looks like a UUID
    v_is_uuid := v_record_id_text ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';

    IF v_is_uuid THEN
        -- UUID PKs go to audit_logs (has UUID record_id)
        IF TG_OP = 'DELETE' THEN
            INSERT INTO public.audit_logs (table_name, record_id, action, old_data, user_id)
            VALUES (TG_TABLE_NAME, v_record_id_text::uuid, TG_OP, v_old_data, auth.uid());
        ELSIF TG_OP = 'UPDATE' THEN
            IF v_changed_fields IS NOT NULL AND array_length(v_changed_fields, 1) > 0 THEN
                INSERT INTO public.audit_logs (table_name, record_id, action, old_data, new_data, changed_fields, user_id)
                VALUES (TG_TABLE_NAME, v_record_id_text::uuid, TG_OP, v_old_data, v_new_data, v_changed_fields, auth.uid());
            END IF;
        ELSIF TG_OP = 'INSERT' THEN
            INSERT INTO public.audit_logs (table_name, record_id, action, new_data, user_id)
            VALUES (TG_TABLE_NAME, v_record_id_text::uuid, TG_OP, v_new_data, auth.uid());
        END IF;
    ELSE
        -- Non-UUID PKs go to audit_logs_text (has TEXT record_id)
        IF TG_OP = 'DELETE' THEN
            INSERT INTO public.audit_logs_text (table_name, record_id, action, old_data, user_id)
            VALUES (TG_TABLE_NAME, v_record_id_text, TG_OP, v_old_data, auth.uid());
        ELSIF TG_OP = 'UPDATE' THEN
            IF v_changed_fields IS NOT NULL AND array_length(v_changed_fields, 1) > 0 THEN
                INSERT INTO public.audit_logs_text (table_name, record_id, action, old_data, new_data, changed_fields, user_id)
                VALUES (TG_TABLE_NAME, v_record_id_text, TG_OP, v_old_data, v_new_data, v_changed_fields, auth.uid());
            END IF;
        ELSIF TG_OP = 'INSERT' THEN
            INSERT INTO public.audit_logs_text (table_name, record_id, action, new_data, user_id)
            VALUES (TG_TABLE_NAME, v_record_id_text, TG_OP, v_new_data, auth.uid());
        END IF;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$_$;

--
-- Name: calculate_packing_cost(integer, "text", integer, numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."calculate_packing_cost"("p_product_id" integer, "p_grade" "text", "p_carton_count" integer, "p_net_weight_per_carton" numeric) RETURNS TABLE("raw_material_id" integer, "raw_material_name" "text", "quantity_per_carton" numeric, "unit" "text", "total_quantity" numeric, "unit_cost" numeric, "total_cost" numeric)
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  RETURN QUERY
  SELECT
    pr.raw_material_id,
    p.name AS raw_material_name,
    pr.quantity_per_carton,
    pr.unit,
    pr.quantity_per_carton * p_carton_count AS total_quantity,
    COALESCE(p.purchase_cost, 0) AS unit_cost,
    pr.quantity_per_carton * p_carton_count * COALESCE(p.purchase_cost, 0) AS total_cost
  FROM packing_recipes pr
  JOIN products p ON p.id = pr.raw_material_id
  WHERE pr.product_id = p_product_id
    AND pr.grade = p_grade
    AND pr.is_active = true;
END;
$$;

--
-- Name: get_latest_exchange_rates_rpc(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_latest_exchange_rates_rpc"() RETURNS TABLE("currency_code" "text", "rate" numeric)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
  SELECT DISTINCT ON (er.currency_code)
    er.currency_code,
    er.rate_to_egp
  FROM exchange_rates er
  ORDER BY er.currency_code, er.updated_at DESC;
$$;

--
-- Name: upsert_station_product_quantity(bigint, "text", "text", integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."upsert_station_product_quantity"("p_station_id" bigint, "p_product_name" "text", "p_product_code" "text", "p_delta" integer) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_existing_id BIGINT;
  v_cur_qty INT;
BEGIN
  SELECT id, quantity INTO v_existing_id, v_cur_qty
  FROM station_products
  WHERE station_id = p_station_id
    AND product_code = p_product_code
  LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    v_cur_qty := COALESCE(v_cur_qty, 0) + p_delta;
    IF v_cur_qty <= 0 THEN
      DELETE FROM station_products WHERE id = v_existing_id;
    ELSE
      UPDATE station_products SET quantity = v_cur_qty WHERE id = v_existing_id;
    END IF;
  ELSE
    IF p_delta > 0 THEN
      INSERT INTO station_products (station_id, product_name, product_code, quantity)
      VALUES (p_station_id, p_product_name, p_product_code, p_delta);
    END IF;
  END IF;
END;
$$;

--
-- Name: rpc_get_dashboard_kpis(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."rpc_get_dashboard_kpis"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    AS $$
DECLARE
  v_total_revenue NUMERIC;
  v_total_cost NUMERIC;
  v_shipment_count INT;
  v_active_batches INT;
  v_result JSONB;
BEGIN
  SELECT COALESCE(SUM(total_revenue), 0), COALESCE(SUM(total_cost), 0), COUNT(*)
    INTO v_total_revenue, v_total_cost, v_shipment_count
    FROM export_shipments
    WHERE status IN ('shipped', 'in_transit', 'delivered');

  SELECT COUNT(*) INTO v_active_batches
  FROM stock_batches WHERE status = 'active';

  v_result := jsonb_build_object(
    'total_revenue', v_total_revenue,
    'total_cost', v_total_cost,
    'gross_profit', v_total_revenue - v_total_cost,
    'gross_margin', CASE WHEN v_total_revenue > 0 THEN ((v_total_revenue - v_total_cost) / v_total_revenue * 100)::NUMERIC(10,2) ELSE 0 END,
    'shipment_count', v_shipment_count,
    'active_batches', v_active_batches
  );

  RETURN v_result;
END;
$$;

--
-- Name: validate_balance_sheet(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."validate_balance_sheet"("p_fiscal_year_id" bigint) RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $$
  WITH balances AS (
    SELECT
      SUM(CASE WHEN a.account_type = 'asset' THEN (t.debit - t.credit) ELSE 0 END) AS asset_total,
      SUM(CASE WHEN a.account_type IN ('liability','equity') THEN (t.credit - t.debit) ELSE 0 END) AS liab_equity_total
    FROM public.transactions t
    JOIN public.accounts a ON t.account_id::text = a.id::text
    JOIN public.fiscal_years fy ON fy.id = p_fiscal_year_id
    WHERE COALESCE(t.transaction_date, t.created_at::date) BETWEEN fy.start_date AND fy.end_date
  )
  SELECT COALESCE(asset_total, 0) = COALESCE(liab_equity_total, 0)
  FROM balances;
$$;

--
-- Name: get_expiring_items(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_expiring_items"("p_days_threshold" integer DEFAULT 7) RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN (
    SELECT COALESCE(jsonb_agg(row_to_json(t)), '[]'::jsonb)
    FROM (
      SELECT
        sb.id as batch_id,
        sb.batch_number,
        p.id as product_id,
        p.name as product_name,
        p.sku,
        sb.remaining_quantity,
        sb.expiry_date,
        sb.quality_grade,
        s.name as supplier_name,
        (sb.expiry_date - CURRENT_DATE) as days_until_expiry
      FROM stock_batches sb
      JOIN products p ON sb.product_id = p.id
      LEFT JOIN suppliers s ON sb.supplier_id = s.id
      WHERE sb.expiry_date IS NOT NULL
        AND sb.expiry_date <= CURRENT_DATE + (p_days_threshold || ' days')::INTERVAL
        AND sb.remaining_quantity > 0
        AND sb.status = 'active'
      ORDER BY sb.expiry_date ASC
    ) t
  );
END;
$$;

--
-- Name: find_orphan_entries(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."find_orphan_entries"("p_fiscal_year_id" bigint) RETURNS integer
    LANGUAGE "sql" STABLE
    AS $$
  SELECT COUNT(*)
  FROM public.transactions t
  LEFT JOIN public.accounts a ON t.account_id::text = a.id::text
  JOIN public.fiscal_years fy ON fy.id = p_fiscal_year_id
  WHERE COALESCE(t.transaction_date, t.created_at::date) BETWEEN fy.start_date AND fy.end_date
    AND (t.account_id IS NULL OR a.id IS NULL);
$$;

--
-- Name: spend_with_category(bigint, character varying, numeric, "text", bigint, bigint, "uuid", bigint, bigint, "uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."spend_with_category"("p_treasury_id" bigint, "p_currency" character varying, "p_amount" numeric, "p_description" "text", "p_category_id" bigint, "p_customer_id" bigint DEFAULT NULL::bigint, "p_supplier_id" "uuid" DEFAULT NULL::"uuid", "p_clearing_agent_id" bigint DEFAULT NULL::bigint, "p_shipping_company_id" bigint DEFAULT NULL::bigint, "p_shareholder_id" "uuid" DEFAULT NULL::"uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_current_balance NUMERIC;
BEGIN
  SELECT balance INTO v_current_balance
  FROM public.treasury_balances
  WHERE treasury_id = p_treasury_id AND currency = p_currency;

  IF v_current_balance IS NULL OR v_current_balance < p_amount THEN
    RAISE EXCEPTION 'الرصيد غير كافٍ في % (المتوفر: %)', p_currency, COALESCE(v_current_balance, 0);
  END IF;

  UPDATE public.treasury_balances
  SET balance = balance - p_amount, updated_at = NOW()
  WHERE treasury_id = p_treasury_id AND currency = p_currency;

  INSERT INTO public.treasury_transactions (
    treasury_id, type, amount, currency, description, category_id,
    customer_id, supplier_id, clearing_agent_id, shipping_company_id, shareholder_id,
    created_by
  ) VALUES (
    p_treasury_id, 'expense', p_amount, p_currency, p_description, p_category_id,
    p_customer_id, p_supplier_id, p_clearing_agent_id, p_shipping_company_id, p_shareholder_id,
    auth.uid()
  );

  IF p_customer_id IS NOT NULL THEN
    UPDATE public.customers SET balance = balance + p_amount WHERE id = p_customer_id;
  END IF;
  IF p_supplier_id IS NOT NULL THEN
    UPDATE public.suppliers SET outstanding_balance = outstanding_balance - p_amount WHERE id = p_supplier_id;
  END IF;
  IF p_clearing_agent_id IS NOT NULL THEN
    UPDATE public.clearing_agents SET balance = balance - p_amount WHERE id = p_clearing_agent_id;
  END IF;
  IF p_shipping_company_id IS NOT NULL THEN
    UPDATE public.shipping_companies SET balance = balance - p_amount WHERE id = p_shipping_company_id;
  END IF;
  IF p_shareholder_id IS NOT NULL THEN
    IF p_currency = 'EGP' THEN
      UPDATE public.shareholders SET current_balance_egp = current_balance_egp - p_amount WHERE id = p_shareholder_id;
    ELSIF p_currency = 'USD' THEN
      UPDATE public.shareholders SET current_balance_usd = current_balance_usd - p_amount WHERE id = p_shareholder_id;
    ELSIF p_currency = 'EUR' THEN
      UPDATE public.shareholders SET current_balance_eur = current_balance_eur - p_amount WHERE id = p_shareholder_id;
    ELSIF p_currency = 'GBP' THEN
      UPDATE public.shareholders SET current_balance_gbp = current_balance_gbp - p_amount WHERE id = p_shareholder_id;
    END IF;
  END IF;
END;
$$;

--
-- Name: create_cash_payment("uuid", numeric, "text", "text", "text", "date"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."create_cash_payment"("p_supplier_id" "uuid", "p_amount" numeric, "p_payment_method" "text" DEFAULT 'cash'::"text", "p_reference_number" "text" DEFAULT NULL::"text", "p_notes" "text" DEFAULT NULL::"text", "p_payment_date" "date" DEFAULT CURRENT_DATE) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_id uuid; v_num text;
BEGIN
    if auth.uid() is null then raise exception 'غير مصرح بهذه العملية'; end if;
    v_num := 'PAY-' || to_char(now(), 'YYYYMMDD') || '-' || lpad(
        (SELECT COALESCE(MAX(CAST(substring(payment_number FROM 10) AS integer)), 0) + 1
         FROM public.cash_payments WHERE payment_number LIKE 'PAY-' || to_char(now(), 'YYYYMMDD') || '-%')::text, 4, '0');
    INSERT INTO public.cash_payments (payment_number, supplier_id, amount, payment_method, reference_number, notes, payment_date, created_by)
    VALUES (v_num, p_supplier_id, p_amount, p_payment_method, p_reference_number, p_notes, p_payment_date, auth.uid()) RETURNING id INTO v_id;
    UPDATE public.suppliers SET outstanding_balance = outstanding_balance - p_amount WHERE id = p_supplier_id;
    INSERT INTO public.cashbox_transactions (transaction_type, amount, description, reference_id, reference_type, user_id)
    VALUES ('expense', p_amount, 'payment #' || v_num, v_id, 'cash_payment', auth.uid());
    RETURN v_id;
END; $$;

--
-- Name: restore_station_batch_allocations(integer, "jsonb"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."restore_station_batch_allocations"("p_station_id" integer, "p_allocations" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_batch_id INTEGER;
  v_qty NUMERIC;
  el JSONB;
  rec RECORD;
BEGIN
  -- Phase 1: Restore station_product_batches
  FOR el IN SELECT jsonb_array_elements(p_allocations)
  LOOP
    v_batch_id := (el->>'batch_id')::INTEGER;
    v_qty      := (el->>'quantity')::NUMERIC;

    IF v_batch_id IS NOT NULL AND v_qty > 0 THEN
      UPDATE public.station_product_batches
         SET remaining_quantity = remaining_quantity + v_qty
       WHERE id = v_batch_id;
    END IF;
  END LOOP;

  -- Phase 2: Restore station_products + raw_materials per unique product
  FOR rec IN (
    SELECT DISTINCT a->>'product_name' AS pname,
                     a->>'product_code' AS pcode
    FROM jsonb_array_elements(p_allocations) AS a
  )
  LOOP
    DECLARE
      v_sum NUMERIC;
      v_mat_id UUID;
    BEGIN
      IF rec.pcode IS NOT NULL AND rec.pcode != '' THEN
        SELECT id INTO v_mat_id FROM public.raw_materials WHERE (name = rec.pname OR name = REPLACE(rec.pname, ' (مادة تعبئة)', '')) AND code = rec.pcode LIMIT 1;
      END IF;
      IF v_mat_id IS NULL THEN
        SELECT id INTO v_mat_id FROM public.raw_materials WHERE (name = rec.pname OR name = REPLACE(rec.pname, ' (مادة تعبئة)', '')) LIMIT 1;
      END IF;

      SELECT SUM((c->>'quantity')::NUMERIC) INTO v_sum
      FROM jsonb_array_elements(p_allocations) AS c
      WHERE c->>'product_name' = rec.pname;

      UPDATE public.station_products
         SET quantity = quantity + v_sum,
             updated_at = NOW()
       WHERE station_id = p_station_id
         AND product_name = rec.pname;

      IF v_mat_id IS NOT NULL THEN
        UPDATE public.raw_materials
           SET quantity = quantity + v_sum,
               updated_at = NOW()
         WHERE id = v_mat_id;

        DECLARE
          v_last RECORD;
        BEGIN
          SELECT * INTO v_last FROM public.stock_batches
          WHERE product_id = v_mat_id
          ORDER BY created_at DESC LIMIT 1
          FOR UPDATE;

          IF FOUND THEN
            UPDATE public.stock_batches
               SET remaining_quantity = remaining_quantity + v_sum
             WHERE id = v_last.id;
          END IF;
        END;
      END IF;
    END;
  END LOOP;

  
END;
$$;

--
-- Name: create_cheque("text", "text", numeric, "text", "date", "date", "text", bigint, "text", "uuid", bigint, bigint, bigint, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."create_cheque"("p_cheque_number" "text", "p_type" "text", "p_amount" numeric, "p_currency" "text", "p_issue_date" "date", "p_due_date" "date", "p_counterparty_type" "text" DEFAULT NULL::"text", "p_counterparty_id" bigint DEFAULT NULL::bigint, "p_notes" "text" DEFAULT NULL::"text", "p_supplier_id" "uuid" DEFAULT NULL::"uuid", "p_clearing_agent_id" bigint DEFAULT NULL::bigint, "p_shipping_company_id" bigint DEFAULT NULL::bigint, "p_shareholder_id" bigint DEFAULT NULL::bigint, "p_category_id" integer DEFAULT NULL::integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_id BIGINT;
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    IF p_due_date < p_issue_date THEN
        RAISE EXCEPTION 'تاريخ الاستحقاق يجب أن يكون بعد تاريخ التحرير';
    END IF;

    INSERT INTO public.cheques (
        cheque_number, type, status, amount, currency,
        issue_date, due_date, counterparty_type, counterparty_id,
        supplier_id, clearing_agent_id, shipping_company_id, shareholder_id, notes, created_by, category_id
    ) VALUES (
        p_cheque_number, p_type, 'pending', p_amount, p_currency,
        p_issue_date, p_due_date, p_counterparty_type, p_counterparty_id,
        p_supplier_id, p_clearing_agent_id, p_shipping_company_id, p_shareholder_id, p_notes, auth.uid(), p_category_id
    ) RETURNING id INTO v_id;

    RETURN jsonb_build_object('id', v_id);
END;
$$;

--
-- Name: withdraw_bank_with_counterparty(integer, numeric, "text", "text", "text", "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."withdraw_bank_with_counterparty"("p_account_id" integer, "p_amount" numeric, "p_description" "text" DEFAULT NULL::"text", "p_counterparty_type" "text" DEFAULT NULL::"text", "p_entity_id" "text" DEFAULT NULL::"text", "p_counterparty_name" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_currency TEXT;
  v_user_id  UUID := auth.uid();
  v_desc     TEXT;
BEGIN
  -- 1. Get account currency
  SELECT currency INTO v_currency
  FROM public.bank_accounts
  WHERE id = p_account_id;

  IF v_currency IS NULL THEN
    RAISE EXCEPTION 'Bank account % not found', p_account_id;
  END IF;

  v_desc := COALESCE(p_description, 'تحويل بنكي إلى ' || COALESCE(p_counterparty_name, ''));

  -- 2. Update bank account balance
  UPDATE public.bank_accounts
  SET balance = balance - p_amount
  WHERE id = p_account_id;

  -- 3. Insert transaction record
  INSERT INTO public.bank_account_transactions
    (bank_account_id, type, amount, balance_after, description, entity_type, entity_id, counterparty_name, created_by)
  VALUES (
    p_account_id,
    'withdrawal',
    p_amount,
    (SELECT balance FROM public.bank_accounts WHERE id = p_account_id),
    v_desc,
    p_counterparty_type,
    p_entity_id,
    p_counterparty_name,
    v_user_id
  );

  -- 4. Update counterparty balance + ledger entry (if applicable)
  IF p_counterparty_type IS NOT NULL AND p_entity_id IS NOT NULL THEN

    IF p_counterparty_type = 'customer' THEN
      UPDATE public.customers
      SET balance = balance + p_amount
      WHERE id = p_entity_id::BIGINT;

      INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by)
      VALUES ('customer', p_entity_id, 'debit', p_amount, v_currency, 'bank_transfer', v_desc, v_user_id);

    ELSIF p_counterparty_type = 'supplier' THEN
      UPDATE public.suppliers
      SET outstanding_balance = outstanding_balance - p_amount
      WHERE id = p_entity_id::UUID;

      INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by)
      VALUES ('supplier', p_entity_id, 'debit', p_amount, v_currency, 'bank_transfer', v_desc, v_user_id);

    ELSIF p_counterparty_type = 'clearing_agent' THEN
      UPDATE public.clearing_agents
      SET manual_adjustment = COALESCE(manual_adjustment, 0) - p_amount,
          balance = COALESCE(balance, 0) - p_amount
      WHERE id = p_entity_id::BIGINT;

      INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by)
      VALUES ('clearing_agent', p_entity_id, 'debit', p_amount, v_currency, 'bank_transfer', v_desc, v_user_id);

    ELSIF p_counterparty_type = 'shipping_company' THEN
      UPDATE public.shipping_companies
      SET manual_adjustment = COALESCE(manual_adjustment, 0) - p_amount,
          balance = COALESCE(balance, 0) - p_amount
      WHERE id = p_entity_id::BIGINT;

      INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by)
      VALUES ('shipping_company', p_entity_id, 'debit', p_amount, v_currency, 'bank_transfer', v_desc, v_user_id);

    ELSIF p_counterparty_type = 'shareholder' THEN
      IF v_currency = 'EGP' THEN
        UPDATE public.shareholders SET current_balance_egp = COALESCE(current_balance_egp, 0) - p_amount WHERE id = p_entity_id::UUID;
      ELSIF v_currency = 'USD' THEN
        UPDATE public.shareholders SET current_balance_usd = COALESCE(current_balance_usd, 0) - p_amount WHERE id = p_entity_id::UUID;
      ELSIF v_currency = 'EUR' THEN
        UPDATE public.shareholders SET current_balance_eur = COALESCE(current_balance_eur, 0) - p_amount WHERE id = p_entity_id::UUID;
      ELSIF v_currency = 'GBP' THEN
        UPDATE public.shareholders SET current_balance_gbp = COALESCE(current_balance_gbp, 0) - p_amount WHERE id = p_entity_id::UUID;
      END IF;

      INSERT INTO public.ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by)
      VALUES ('shareholder', p_entity_id, 'debit', p_amount, v_currency, 'bank_transfer', v_desc, v_user_id);

    END IF;
  END IF;
END;
$$;

--
-- Name: unlink_user_from_tenant("uuid", "uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."unlink_user_from_tenant"("p_user_id" "uuid", "p_tenant_id" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  DELETE FROM public.tenant_users WHERE user_id = p_user_id AND tenant_id = p_tenant_id;
  UPDATE public.tenants SET current_users = (SELECT COUNT(*) FROM public.tenant_users WHERE tenant_id = p_tenant_id) WHERE id = p_tenant_id;
  RETURN '{"success": true}';
END;
$$;

--
-- Name: get_account_totals_for_fy("text", bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."get_account_totals_for_fy"("p_account_code" "text", "p_fiscal_year_id" bigint) RETURNS TABLE("total_debit" numeric, "total_credit" numeric)
    LANGUAGE "sql" STABLE
    AS $$
  SELECT
    COALESCE(SUM(t.debit), 0)::numeric,
    COALESCE(SUM(t.credit), 0)::numeric
  FROM public.transactions t
  JOIN public.accounts a ON t.account_id::text = a.id::text
  JOIN public.fiscal_years fy ON fy.id = p_fiscal_year_id
  WHERE a.account_code = p_account_code
    AND COALESCE(t.transaction_date, t.created_at::date) BETWEEN fy.start_date AND fy.end_date;
$$;

--
-- Name: rpc_process_export_shipment_ledger(bigint, "uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."rpc_process_export_shipment_ledger"("p_shipment_id" bigint, "p_user_id" "uuid" DEFAULT "auth"."uid"()) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_shipment RECORD;
  v_total_revenue NUMERIC := 0;
  v_discount NUMERIC := 0;
  v_net_amount NUMERIC := 0;
  v_old_amount NUMERIC := 0;
  v_desc TEXT;
BEGIN
  SELECT * INTO v_shipment
  FROM export_shipments
  WHERE id = p_shipment_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Shipment not found');
  END IF;

  IF v_shipment.customer_id IS NULL THEN
    RETURN jsonb_build_object('success', true, 'message', 'No customer assigned');
  END IF;

  SELECT COALESCE(SUM(amount), 0)
  INTO v_total_revenue
  FROM export_shipment_items
  WHERE shipment_id = p_shipment_id;

  v_discount := COALESCE(v_shipment.discount_amount, 0);
  v_net_amount := GREATEST(v_total_revenue - v_discount, 0);

  -- Calculate old amount as the net balance change (debit - credit) to handle existing discount entries
  SELECT 
    COALESCE(SUM(CASE WHEN entry_type = 'debit' THEN amount ELSE -amount END), 0)
  INTO v_old_amount
  FROM ledger_entries
  WHERE entity_type = 'customer'
    AND entity_id = v_shipment.customer_id::TEXT
    AND reference_type = 'export_shipment'
    AND reference_text = p_shipment_id::TEXT;

  -- Update customer balance by reverting the old net amount and applying the new net amount
  UPDATE customers
  SET balance = COALESCE(balance, 0) - v_old_amount + v_net_amount,
      updated_at = now()
  WHERE id = v_shipment.customer_id;

  -- Delete all old ledger entries for this shipment
  DELETE FROM ledger_entries
  WHERE entity_type = 'customer'
    AND entity_id = v_shipment.customer_id::TEXT
    AND reference_type = 'export_shipment'
    AND reference_text = p_shipment_id::TEXT;

  -- Insert DEBIT entry for the full revenue (before discount)
  IF v_total_revenue > 0 THEN
    v_desc := 'شحنة تصدير رقم ' || v_shipment.shipment_number;
    INSERT INTO ledger_entries (
      entity_type, entity_id, entry_type, amount, currency,
      reference_type, reference_text, description, created_by
    ) VALUES (
      'customer', v_shipment.customer_id::TEXT, 'debit', v_total_revenue,
      COALESCE(v_shipment.currency, 'USD'),
      'export_shipment', p_shipment_id::TEXT, v_desc, p_user_id
    );
  END IF;

  -- Insert CREDIT entry for the discount amount
  IF v_discount > 0 THEN
    v_desc := 'خصم شحنة تصدير رقم ' || v_shipment.shipment_number;
    IF COALESCE(v_shipment.discount_reason, '') != '' THEN
      v_desc := v_desc || ' (' || v_shipment.discount_reason || ')';
    END IF;

    INSERT INTO ledger_entries (
      entity_type, entity_id, entry_type, amount, currency,
      reference_type, reference_text, description, created_by
    ) VALUES (
      'customer', v_shipment.customer_id::TEXT, 'credit', v_discount,
      COALESCE(v_shipment.currency, 'USD'),
      'export_shipment', p_shipment_id::TEXT, v_desc, p_user_id
    );
  END IF;

  UPDATE export_shipments
  SET applied_discount_amount = v_discount
  WHERE id = p_shipment_id;

  RETURN jsonb_build_object(
    'success', true,
    'total_revenue', v_total_revenue,
    'discount', v_discount,
    'net_amount', v_net_amount
  );
END;
$$;

--
-- Name: create_customer_journal_entry(integer, "uuid", numeric, boolean, "text", "date", "jsonb"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."create_customer_journal_entry"("p_account_id" integer, "p_customer_id" "uuid", "p_amount" numeric, "p_is_debit" boolean, "p_description" "text" DEFAULT NULL::"text", "p_transaction_date" "date" DEFAULT CURRENT_DATE, "p_currency_snapshot" "jsonb" DEFAULT NULL::"jsonb") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
DECLARE
  v_entry_number TEXT;
  v_counterparty_account_id INTEGER;
  v_account_delta NUMERIC;
  v_party_delta NUMERIC;
  v_ledger_type TEXT;
  v_customer_code TEXT;
BEGIN
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be positive, got %', p_amount;
  END IF;

  v_entry_number := 'J' || LPAD(nextval('entry_number_seq')::TEXT, 6, '0');

  IF p_is_debit THEN
    v_account_delta := p_amount;
    v_party_delta := p_amount;
    v_ledger_type := 'debit';
  ELSE
    v_account_delta := -p_amount;
    v_party_delta := -p_amount;
    v_ledger_type := 'credit';
  END IF;

  SELECT account_id, code INTO v_counterparty_account_id, v_customer_code
  FROM customers WHERE id = p_customer_id;

  INSERT INTO transactions (
    entry_number, transaction_date, account_id,
    debit, credit, description,
    currency_snapshot
  ) VALUES
    (v_entry_number, p_transaction_date, p_account_id,
     CASE WHEN p_is_debit THEN p_amount ELSE 0 END,
     CASE WHEN p_is_debit THEN 0 ELSE p_amount END,
     p_description,
     COALESCE(p_currency_snapshot, jsonb_build_object('currency', 'EGP', 'amount', p_amount, 'exchangeRate', 1.0))),
    (v_entry_number, p_transaction_date, v_counterparty_account_id,
     CASE WHEN p_is_debit THEN 0 ELSE p_amount END,
     CASE WHEN p_is_debit THEN p_amount ELSE 0 END,
     p_description,
     COALESCE(p_currency_snapshot, jsonb_build_object('currency', 'EGP', 'amount', p_amount, 'exchangeRate', 1.0)));

  UPDATE accounts SET balance = COALESCE(balance, 0) + v_account_delta WHERE id = p_account_id;
  UPDATE customers SET balance = COALESCE(balance, 0) + v_party_delta WHERE id = p_customer_id;

  INSERT INTO ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by, currency_snapshot)
  VALUES ('customer', v_customer_code, v_ledger_type, p_amount, 'EGP', 'entry', p_description, auth.uid(), COALESCE(p_currency_snapshot, jsonb_build_object('currency', 'EGP', 'amount', p_amount, 'exchangeRate', 1.0)));

  RETURN v_entry_number;
END;
$$;

--
-- Name: rpc_confirm_packing(integer, "uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."rpc_confirm_packing"("p_packing_order_id" integer, "p_user_id" "uuid" DEFAULT "auth"."uid"()) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_packing RECORD;
  v_total_cost NUMERIC := 0;
  v_result JSONB;
BEGIN
  -- Lock the packing order row
  SELECT * INTO v_packing FROM packing_orders WHERE id = p_packing_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', ' packing order not found');
  END IF;

  IF v_packing.status = 'confirmed' THEN
    RETURN jsonb_build_object('success', false, 'error', 'already confirmed');
  END IF;

  -- Update status
  UPDATE packing_orders SET status = 'confirmed', updated_at = NOW() WHERE id = p_packing_order_id;

  -- Log audit
  INSERT INTO audit_logs_text (table_name, record_id, action, old_values, new_values, performed_by)
  VALUES ('packing_orders', p_packing_order_id::TEXT, 'confirm',
    jsonb_build_object('status', v_packing.status),
    jsonb_build_object('status', 'confirmed'),
    p_user_id);

  v_result := jsonb_build_object(
    'success', true,
    'packing_order_id', p_packing_order_id,
    'total_cost', v_total_cost
  );

  RETURN v_result;
END;
$$;

--
-- Name: rpc_confirm_purchase_debug("text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."rpc_confirm_purchase_debug"("p_purchase_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_purchase RECORD;
  v_item RECORD;
BEGIN
  SELECT * INTO v_purchase FROM purchase_invoices WHERE id::TEXT = p_purchase_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('step', 'find_purchase', 'error', 'not found'); END IF;

  FOR v_item IN
    SELECT pii.*, rm.id AS rm_uuid, rm.code AS rm_code
    FROM purchase_invoice_items pii
    LEFT JOIN raw_materials rm ON rm.id = pii.raw_material_id
    WHERE pii.invoice_id::TEXT = p_purchase_id
  LOOP
    -- Test: can we insert into stock_batches without UUID issues?
    BEGIN
      INSERT INTO stock_batches (
        batch_number, product_id, supplier_id, purchase_invoice_id,
        quantity, remaining_quantity, purchase_cost, average_cost,
        exchange_rate, currency, status, user_id
      ) VALUES (
        'TEST-BATCH', v_item.raw_material_id, v_purchase.supplier_id, v_purchase.id,
        0, 0, 0, 0, 1.0, 'EGP', 'test', auth.uid()
      );
      -- Delete the test row immediately
      DELETE FROM stock_batches WHERE batch_number = 'TEST-BATCH';
      RAISE NOTICE 'Step stock_batches: OK (product_id=%, supplier_id=%)', v_item.raw_material_id, v_purchase.supplier_id;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Step stock_batches: FAILED: %', SQLERRM;
    END;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'purchase_id', p_purchase_id);
END;
$$;

--
-- Name: count_negative_stock(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."count_negative_stock"() RETURNS integer
    LANGUAGE "sql" STABLE
    AS $$
  SELECT COUNT(*)::INTEGER
  FROM public.stock_batches
  WHERE remaining_quantity < 0;
$$;

--
-- Name: delete_expense_category(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."delete_expense_category"("p_id" integer) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;

    IF NOT (SELECT is_admin FROM public.users WHERE id = auth.uid()) THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;

    -- Set category_id to NULL on affected transactions
    UPDATE treasury_transactions SET category_id = NULL WHERE category_id = p_id;

    DELETE FROM public.expense_categories WHERE id = p_id;
END;
$$;

--
-- Name: admin_create_user("text", "text", "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."admin_create_user"("p_email" "text", "p_password" "text", "p_full_name" "text") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_user_id   UUID;
  v_result    JSON;
BEGIN
  -- تحقق لو الإيميل موجود أصلاً في auth.users
  SELECT id INTO v_user_id
  FROM auth.users
  WHERE email = p_email
  LIMIT 1;

  IF v_user_id IS NOT NULL THEN
    RAISE EXCEPTION 'البريد الإلكتروني مستخدم بالفعل: %', p_email;
  END IF;

  -- إنشاء UUID جديد
  v_user_id := gen_random_uuid();

  -- إنشاء المستخدم في auth.users
  INSERT INTO auth.users (
    id,
    instance_id,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    role,
    aud
  ) VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    p_email,
    crypt(p_password, gen_salt('bf')),
    now(),
    '{"provider": "email", "providers": ["email"]}'::jsonb,
    json_build_object('full_name', p_full_name)::jsonb,
    now(),
    now(),
    'authenticated',
    'authenticated'
  );

  -- إنشاء auth.identities مع provider_id
  INSERT INTO auth.identities (
    id,
    user_id,
    provider_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    v_user_id,
    p_email,
    json_build_object(
      'sub', v_user_id::text,
      'email', p_email
    )::jsonb,
    'email',
    now(),
    now(),
    now()
  );

  -- ✅ INSERT أو UPDATE في public.users
  INSERT INTO public.users (
    id,
    email,
    full_name,
    is_admin,
    created_at
  ) VALUES (
    v_user_id,
    p_email,
    p_full_name,
    false,
    now()
  )
  ON CONFLICT (id) DO UPDATE SET
    email     = EXCLUDED.email,
    full_name = EXCLUDED.full_name;

  SELECT row_to_json(u) INTO v_result
  FROM public.users u
  WHERE u.id = v_user_id;

  RETURN v_result;
END;
$$;

--
-- Name: admin_setup_user("uuid", "text", "text", integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."admin_setup_user"("p_user_id" "uuid", "p_full_name" "text", "p_email" "text", "p_trial_days" integer DEFAULT 0, "p_trial_minutes" integer DEFAULT 3) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_tenant_id UUID;
  v_expires_at TIMESTAMPTZ;
BEGIN
  INSERT INTO public.users (id, full_name, email, username, is_admin)
  VALUES (p_user_id, p_full_name, p_email, split_part(p_email, '@', 1), true)
  ON CONFLICT (id) DO UPDATE SET
    is_admin = true,
    full_name = p_full_name,
    email = p_email;

  v_expires_at := now() + (p_trial_days || ' days')::INTERVAL + (p_trial_minutes || ' minutes')::INTERVAL;

  INSERT INTO public.tenants (name, email, tenant_type, is_active, max_users, subscription_expires_at)
  VALUES (
    'متجر ' || p_full_name,
    p_email,
    'erp',
    true,
    50,
    v_expires_at
  )
  RETURNING id INTO v_tenant_id;

  DELETE FROM public.tenant_users WHERE user_id = p_user_id;

  INSERT INTO public.tenant_users (tenant_id, user_id, role)
  VALUES (v_tenant_id, p_user_id, 'owner');

  UPDATE public.tenants
  SET current_users = 1
  WHERE id = v_tenant_id;

  RETURN json_build_object(
    'success', true,
    'tenant_id', v_tenant_id,
    'expires_at', v_expires_at,
    'trial_days', p_trial_days,
    'trial_minutes', p_trial_minutes
  );
END;
$$;

--
-- Name: _is_admin(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."_is_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT COALESCE((SELECT is_admin FROM public.users WHERE id = auth.uid()), false);
$$;

--
-- Name: delete_customer_safe(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."delete_customer_safe"("p_customer_id" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_is_admin      BOOLEAN;
  v_has_deps      BOOLEAN;
  v_table_ok      BOOLEAN;
  v_exists        BOOLEAN;
BEGIN
  -- ── 1. Admin check ──
  SELECT COALESCE(is_admin, false) INTO v_is_admin
  FROM public.users WHERE id = auth.uid();
  IF NOT v_is_admin THEN
    RETURN jsonb_build_object('error', 'NOT_ADMIN');
  END IF;

  -- ── 2. Dependency check ──
  v_has_deps := false;

  -- ledger_entries exists unconditionally
  IF EXISTS (
    SELECT 1 FROM public.ledger_entries
    WHERE entity_type = 'customer' AND entity_id = p_customer_id::TEXT
  ) THEN
    v_has_deps := true;
  END IF;

  -- sales_invoices exists unconditionally
  IF NOT v_has_deps AND EXISTS (
    SELECT 1 FROM public.sales_invoices
    WHERE customer_id::TEXT = p_customer_id::TEXT
  ) THEN
    v_has_deps := true;
  END IF;

  -- treasury_transactions (optional table)
  IF NOT v_has_deps THEN
    SELECT EXISTS (
      SELECT FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = 'treasury_transactions'
    ) INTO v_table_ok;
    IF v_table_ok THEN
      EXECUTE format(
        'SELECT EXISTS (SELECT 1 FROM public.treasury_transactions WHERE customer_id::TEXT = %L)',
        p_customer_id::TEXT
      ) INTO v_exists;
      IF v_exists THEN v_has_deps := true; END IF;
    END IF;
  END IF;

  -- cash_receipts (optional table)
  IF NOT v_has_deps THEN
    SELECT EXISTS (
      SELECT FROM information_schema.tables
      WHERE table_schema = 'public' AND table_name = 'cash_receipts'
    ) INTO v_table_ok;
    IF v_table_ok THEN
      EXECUTE format(
        'SELECT EXISTS (SELECT 1 FROM public.cash_receipts WHERE customer_id::TEXT = %L)',
        p_customer_id::TEXT
      ) INTO v_exists;
      IF v_exists THEN v_has_deps := true; END IF;
    END IF;
  END IF;

  IF v_has_deps THEN
    RETURN jsonb_build_object('error', 'HAS_DEPENDENCIES');
  END IF;

  -- ── 3. Delete ──
  DELETE FROM public.customers WHERE id = p_customer_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

--
-- Name: recalculate_all_supplier_balances(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."recalculate_all_supplier_balances"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    if not exists (select 1 from public.users where id = auth.uid() and is_admin = true) then
        raise exception 'غير مصرح لك بهذه العملية';
    end if;
    UPDATE public.suppliers s SET outstanding_balance = COALESCE((
        SELECT SUM(pi.total_amount) FROM public.purchase_invoices pi WHERE pi.supplier_id = s.id AND pi.status != 'cancelled'
    ), 0) - COALESCE((SELECT SUM(cp.amount) FROM public.cash_payments cp WHERE cp.supplier_id = s.id), 0);
END; $$;

--
-- Name: handle_new_admin_treasury(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."handle_new_admin_treasury"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    IF NEW.is_admin = true THEN
        UPDATE public.treasuries
        SET user_id = NEW.id
        WHERE type = 'main'
          AND (user_id IS NULL OR user_id = '00000000-0000-0000-0000-000000000000');
    END IF;

    RETURN NEW;
END;
$$;

--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
BEGIN
  INSERT INTO public.users (id, email, full_name, is_admin)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data ->> 'full_name', NEW.email),
    false
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    full_name = EXCLUDED.full_name;
  RETURN NEW;
END;
$$;

--
-- Name: admin_delete_user("uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."admin_delete_user"("p_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  -- ── Authorization: caller MUST be admin ──
  if not exists (
    select 1 from public.users
    where id = auth.uid() and is_admin = true
  ) then
    raise exception 'غير مصرح لك بهذه العملية';
  end if;

  -- ── Input validation ──
  if p_user_id is null then
    raise exception 'معرف المستخدم مطلوب';
  end if;

  -- ── Prevent deleting admin accounts ──
  if exists (
    select 1 from public.users
    where id = p_user_id and is_admin = true
  ) then
    raise exception 'لا يمكن حذف مستخدم بصلاحية مالك';
  end if;

  -- ── Prevent self-deletion ──
  if p_user_id = auth.uid() then
    raise exception 'لا يمكن حذف حسابك الخاص';
  end if;

  -- ── Cascade delete ──
  delete from public.user_roles where user_id = p_user_id;
  delete from public.users where id = p_user_id;
  delete from auth.users where id = p_user_id;
end;
$$;

--
-- Name: recalculate_all_customer_balances(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."recalculate_all_customer_balances"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    if not exists (select 1 from public.users where id = auth.uid() and is_admin = true) then
        raise exception 'غير مصرح لك بهذه العملية';
    end if;
    UPDATE public.customers c SET current_balance = COALESCE((
        SELECT SUM(si.total_amount) FROM public.sales_invoices si WHERE si.customer_id = c.id AND si.status != 'cancelled'
    ), 0) - COALESCE((SELECT SUM(cr.amount) FROM public.cash_receipts cr WHERE cr.customer_id = c.id), 0);
END; $$;

--
-- Name: admin_create_employee("text", "text", "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."admin_create_employee"("p_username" "text", "p_password" "text", "p_full_name" "text") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
DECLARE
  v_user_id    UUID;
  v_email      TEXT;
  v_result     JSON;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND is_admin = true
  ) THEN
    RAISE EXCEPTION 'غير مصرح لك بهذه العملية';
  END IF;

  IF p_username IS NULL OR trim(p_username) = '' THEN
    RAISE EXCEPTION 'اسم المستخدم مطلوب';
  END IF;

  IF p_full_name IS NULL OR trim(p_full_name) = '' THEN
    RAISE EXCEPTION 'الاسم الكامل مطلوب';
  END IF;

  IF p_password IS NULL OR length(p_password) < 6 THEN
    RAISE EXCEPTION 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
  END IF;

  v_email := lower(trim(p_username)) || '@fruityfarms.local';
  v_user_id := gen_random_uuid();

  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at,
    confirmation_token, email_change, email_change_token_new, recovery_token
  ) VALUES (
    v_user_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    v_email,
    crypt(p_password, gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    jsonb_build_object('full_name', p_full_name),
    now(), now(),
    '', '', '', ''
  );

  INSERT INTO auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
  VALUES (
    v_user_id, v_user_id,
    jsonb_build_object('sub', v_user_id, 'email', v_email),
    'email', v_email, now(), now(), now()
  );

  INSERT INTO public.users (id, full_name, email, is_admin)
  VALUES (v_user_id, p_full_name, v_email, false)
  ON CONFLICT (id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    email = EXCLUDED.email;

  SELECT json_build_object(
    'id', v_user_id,
    'email', v_email,
    'full_name', p_full_name,
    'is_admin', false,
    'created_at', now()::text
  ) INTO v_result;

  RETURN v_result;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'اسم المستخدم أو البريد الإلكتروني مسجل بالفعل';
END;
$$;

--
-- Name: delete_invoice("text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."delete_invoice"("p_invoice_id" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE v_uuid uuid; v_cust uuid; v_tot numeric;
BEGIN
    if not exists (select 1 from public.users where id = auth.uid() and is_admin = true) then
        raise exception 'غير مصرح لك بهذه العملية';
    end if;
    v_uuid := p_invoice_id::uuid;
    SELECT customer_id, total_amount INTO v_cust, v_tot FROM public.sales_invoices WHERE id = v_uuid;
    DELETE FROM public.sales_invoice_items WHERE invoice_id = v_uuid;
    DELETE FROM public.sales_invoices WHERE id = v_uuid;
    IF v_cust IS NOT NULL THEN UPDATE public.customers SET current_balance = current_balance - v_tot WHERE id = v_cust; END IF;
    RETURN true;
END; $$;

--
-- Name: update_expense_category(integer, "text", "text", boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."update_expense_category"("p_id" integer, "p_name" "text" DEFAULT NULL::"text", "p_color" "text" DEFAULT NULL::"text", "p_is_active" boolean DEFAULT NULL::boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;

    IF NOT (SELECT is_admin FROM public.users WHERE id = auth.uid()) THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;

    UPDATE public.expense_categories
    SET
        name      = COALESCE(p_name, name),
        color     = COALESCE(p_color, color),
        is_active = COALESCE(p_is_active, is_active)
    WHERE id = p_id;
END;
$$;

--
-- Name: sign_up_new_tenant("uuid", "text", "text", "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."sign_up_new_tenant"("p_user_id" "uuid", "p_full_name" "text", "p_phone" "text", "p_email" "text" DEFAULT NULL::"text") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_tenant_id UUID;
  v_trial_days INTEGER;
  v_expires_at TIMESTAMPTZ;
  v_email TEXT;
BEGIN
  v_email := COALESCE(p_email, p_phone || '@erp.local');

  -- Get trial days from settings
  SELECT setting_value::INTEGER INTO v_trial_days
  FROM public.system_settings
  WHERE setting_key = 'trial_days';
  v_trial_days := COALESCE(v_trial_days, 7);

  -- Calculate expiry
  v_expires_at := now() + (v_trial_days || ' days')::INTERVAL;

  -- Create tenant for this user
  INSERT INTO public.tenants (name, email, tenant_type, is_active, max_users, subscription_expires_at)
  VALUES (
    'متجر ' || p_full_name,
    v_email,
    'erp',
    true,
    50,
    v_expires_at
  )
  RETURNING id INTO v_tenant_id;

  -- Safety check
  IF v_tenant_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'فشل إنشاء المتجر');
  END IF;

  -- Link user to their tenant as owner (delete any existing link first)
  DELETE FROM public.tenant_users WHERE user_id = p_user_id;

  INSERT INTO public.tenant_users (tenant_id, user_id, role)
  VALUES (v_tenant_id, p_user_id, 'owner');

  -- Update user record with phone, email, full_name and make them admin
  UPDATE public.users
  SET full_name = p_full_name, phone = p_phone, email = v_email, is_admin = true
  WHERE id = p_user_id;

  -- Update tenant user count
  UPDATE public.tenants
  SET current_users = 1
  WHERE id = v_tenant_id;

  RETURN json_build_object(
    'success', true,
    'tenant_id', v_tenant_id,
    'trial_days', v_trial_days,
    'expires_at', v_expires_at
  );
END;
$$;

--
-- Name: admin_delete_employee("uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."admin_delete_employee"("p_user_id" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
DECLARE
  v_result JSON;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND is_admin = true
  ) THEN
    RAISE EXCEPTION 'غير مصرح لك بهذه العملية';
  END IF;

  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'لا يمكنك حذف حسابك الخاص';
  END IF;

  DELETE FROM public.user_roles WHERE user_id = p_user_id;
  DELETE FROM public.users WHERE id = p_user_id;

  SELECT json_build_object('success', true, 'user_id', p_user_id) INTO v_result;
  RETURN v_result;
END;
$$;

--
-- Name: rpc_edit_lot_price(bigint, numeric, numeric, "text", "uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."rpc_edit_lot_price"("p_lot_id" bigint, "p_new_price" numeric, "p_exchange_rate" numeric, "p_currency" "text", "p_user_id" "uuid" DEFAULT "auth"."uid"()) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_lot RECORD;
  v_new_total_cost NUMERIC;
  v_old_total_cost NUMERIC;
  v_effective_cost NUMERIC;
  v_desc TEXT;
  v_product_name TEXT;
  v_total_graded NUMERIC := 0;
  v_grading RECORD;
  v_batch_cost NUMERIC;
  v_batch_number TEXT;
  v_net_wt NUMERIC;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'غير مصرح لك بتعديل سعر المحصول';
  END IF;

  SELECT lr.* INTO v_lot FROM lot_receipts lr WHERE lr.id = p_lot_id FOR UPDATE OF lr;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'رقم المحصول غير موجود (id=%)', p_lot_id;
  END IF;

  v_old_total_cost := COALESCE(v_lot.total_fruit_cost, 0);
  v_product_name := COALESCE(v_lot.product_name, 'صنف');
  v_net_wt := COALESCE(NULLIF(v_lot.net_weight_kg, 0), v_lot.gross_weight_kg, 0);

  IF COALESCE(v_lot.purchase_mode, 'weight') = 'carton' THEN
    v_new_total_cost := COALESCE(v_lot.carton_count, 0) * p_new_price;
    UPDATE lot_receipts 
    SET price_per_carton = p_new_price,
        fruit_cost_per_kg = CASE WHEN v_net_wt > 0 THEN v_new_total_cost / v_net_wt ELSE p_new_price END,
        exchange_rate = p_exchange_rate,
        currency = p_currency,
        total_fruit_cost = v_new_total_cost,
        updated_at = now()
    WHERE id = p_lot_id;
  ELSE
    v_new_total_cost := COALESCE(v_lot.gross_weight_kg, 0) * p_new_price;
    UPDATE lot_receipts 
    SET fruit_cost_per_kg = CASE WHEN v_net_wt > 0 THEN v_new_total_cost / v_net_wt ELSE p_new_price END,
        exchange_rate = p_exchange_rate,
        currency = p_currency,
        total_fruit_cost = v_new_total_cost,
        updated_at = now()
    WHERE id = p_lot_id;
  END IF;

  IF v_lot.supplier_id IS NOT NULL THEN
    IF v_old_total_cost > 0 THEN
      DELETE FROM ledger_entries
      WHERE entity_type = 'supplier'
        AND entity_id = v_lot.supplier_id::TEXT
        AND reference_type = 'lot_receipt'
        AND reference_text = p_lot_id::TEXT;
    END IF;

    IF v_new_total_cost > 0 THEN
      v_desc := 'تعديل سعر المحصول رقم ' || v_product_name || ' / رقم: ' || COALESCE(v_lot.lot_number, '');
      INSERT INTO ledger_entries (
        entity_type, entity_id, entry_type, amount,
        currency, reference_type, reference_text, description, created_by
      ) VALUES (
        'supplier', v_lot.supplier_id::TEXT, 'credit', v_new_total_cost,
        p_currency, 'lot_receipt', p_lot_id::TEXT, v_desc, p_user_id
      );
    END IF;

    UPDATE suppliers 
    SET outstanding_balance = COALESCE(outstanding_balance, 0) - v_old_total_cost + v_new_total_cost,
        updated_at = now()
    WHERE id = v_lot.supplier_id;
  END IF;

  SELECT COALESCE(SUM(weight_kg), 0) INTO v_total_graded
  FROM lot_grading_results
  WHERE lot_id = p_lot_id AND grade IN ('A','B','C') AND weight_kg > 0;

  v_effective_cost := CASE WHEN v_total_graded > 0 THEN v_new_total_cost / v_total_graded ELSE 0 END;

  FOR v_grading IN
    SELECT id, grade, weight_kg, stock_batch_id FROM lot_grading_results
    WHERE lot_id = p_lot_id AND grade IN ('A','B','C') AND weight_kg > 0
  LOOP
    v_batch_number := 'G-' || v_lot.lot_number || '-' || v_grading.grade;
    UPDATE stock_batches 
    SET purchase_cost = v_effective_cost,
        updated_at = now()
    WHERE batch_number = v_batch_number;
  END LOOP;

  PERFORM public.rpc_update_packing_costs_for_lot(p_lot_id);

  RETURN jsonb_build_object(
    'success', true,
    'lot_id', p_lot_id,
    'new_total_cost', v_new_total_cost,
    'effective_cost', v_effective_cost
  );
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'حدث خطأ أثناء تعديل سعر المحصول: %', SQLERRM;
END;
$$;

--
-- Name: distribute_all_profits(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."distribute_all_profits"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_shipment RECORD;
  v_count INT := 0;
BEGIN
  FOR v_shipment IN
    SELECT es.id
    FROM public.export_shipments es
    WHERE es.status != 'cancelled'
      AND es.net_profit_egp IS NOT NULL
      AND es.net_profit_egp > 0
      AND NOT EXISTS (
        SELECT 1 FROM public.shareholder_profit_distributions spd
        WHERE spd.shipment_id = es.id
      )
  LOOP
    BEGIN
      PERFORM public.distribute_profit_for_shipment(v_shipment.id::TEXT);
      v_count := v_count + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Error distributing shipment %: %', v_shipment.id, SQLERRM;
    END;
  END LOOP;
  RETURN v_count;
END;
$$;

--
-- Name: rpc_cancel_purchase("text", "uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."rpc_cancel_purchase"("p_purchase_id" "text", "p_user_id" "uuid" DEFAULT "auth"."uid"()) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_purchase RECORD;
  v_batch RECORD;
  v_total_egp NUMERIC := 0;
  v_inventory_account_id INTEGER;
  v_supplier_account_id INTEGER;
  v_remaining NUMERIC;
  v_paid_amount NUMERIC;
  v_cash_account_id INTEGER;
  v_treasury_id_int INTEGER;
  v_bank_account_id INTEGER;
  v_source_type TEXT;
  v_treasury_balance_id INTEGER;
  v_balance_before NUMERIC;
  v_balance_after NUMERIC;
  v_old_treasury_tx RECORD;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح لك بإجراء هذه العملية';
  END IF;

  SELECT * INTO v_purchase FROM purchase_invoices WHERE id::TEXT = p_purchase_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'فاتورة المشتريات غير موجودة';
  END IF;

  IF v_purchase.status != 'confirmed' THEN
    RAISE EXCEPTION 'يمكن إلغاء الفواتير المؤكدة فقط. الحالة الحالية: %', v_purchase.status;
  END IF;

  v_paid_amount := COALESCE(v_purchase.paid_amount, 0);
  v_bank_account_id := v_purchase.payment_bank_account_id;
  v_source_type := COALESCE(v_purchase.payment_source_type, 'treasury');
  v_treasury_id_int := v_purchase.payment_treasury_id::INTEGER;

  FOR v_batch IN
    SELECT sb.id, sb.remaining_quantity, rm.name AS raw_material_name
    FROM stock_batches sb
    LEFT JOIN raw_materials rm ON rm.id = sb.product_id
    WHERE sb.purchase_invoice_id = v_purchase.id
  LOOP
    IF v_batch.raw_material_name IS NOT NULL THEN
      UPDATE raw_materials
      SET quantity = GREATEST(COALESCE(quantity, 0) - v_batch.remaining_quantity, 0),
          updated_at = now()
      WHERE name = v_batch.raw_material_name;
    END IF;
    DELETE FROM stock_batches WHERE id = v_batch.id;
  END LOOP;

  IF v_purchase.supplier_id IS NOT NULL THEN
    v_remaining := COALESCE(v_purchase.total_amount, 0) - COALESCE(v_purchase.paid_amount, 0);
    IF v_remaining > 0 THEN
      UPDATE suppliers
      SET outstanding_balance = GREATEST(COALESCE(outstanding_balance, 0) - v_remaining, 0)
      WHERE id = v_purchase.supplier_id;
    END IF;
  END IF;

  -- BUG FIX: Calculate total_egp from items (was always 0 before!)
  SELECT COALESCE(SUM(pii.quantity * pii.unit_cost * COALESCE(NULLIF(pii.exchange_rate, 0), 1.0)), 0)
  INTO v_total_egp
  FROM purchase_invoice_items pii
  WHERE pii.invoice_id::TEXT = p_purchase_id;

  SELECT id INTO v_supplier_account_id FROM accounts WHERE account_code = '2000' LIMIT 1;

  IF v_total_egp > 0 THEN
    SELECT id INTO v_inventory_account_id FROM accounts WHERE account_code = '1030' LIMIT 1;
    IF v_inventory_account_id IS NULL THEN
      SELECT id INTO v_inventory_account_id FROM accounts WHERE account_code = '1040' LIMIT 1;
    END IF;

    IF v_inventory_account_id IS NOT NULL AND v_supplier_account_id IS NOT NULL THEN
      PERFORM create_balanced_entry(
        p_debit_account_id := v_supplier_account_id,
        p_credit_account_id := v_inventory_account_id,
        p_amount := v_total_egp,
        p_description := 'إلغاء مشتريات رقم ' || COALESCE(v_purchase.invoice_number, ''),
        p_transaction_date := now()::DATE,
        p_reference_type := 'purchase_cancel',
        p_reference_id := NULL,
        p_currency_snapshot := NULL,
        p_purchase_invoice_ref := NULL
      );
    END IF;
  END IF;

  IF v_paid_amount > 0 AND v_purchase.supplier_id IS NOT NULL THEN
    IF v_source_type = 'bank' AND v_bank_account_id IS NOT NULL THEN
      SELECT id INTO v_cash_account_id FROM accounts WHERE account_code = '1010' LIMIT 1;
      UPDATE bank_accounts SET balance = balance + v_paid_amount, updated_at = now() WHERE id = v_bank_account_id;

      IF v_cash_account_id IS NOT NULL AND v_supplier_account_id IS NOT NULL THEN
        PERFORM create_balanced_entry(
          p_debit_account_id := v_cash_account_id,
          p_credit_account_id := v_supplier_account_id,
          p_amount := v_paid_amount,
          p_description := 'إلغاء دفعة للمورد - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, ''),
          p_transaction_date := now()::DATE,
          p_reference_type := 'purchase_cancel_payment',
          p_reference_id := NULL,
          p_currency_snapshot := NULL,
          p_purchase_invoice_ref := NULL
        );
      END IF;

    ELSIF v_source_type = 'treasury' AND v_treasury_id_int IS NOT NULL THEN
      SELECT id INTO v_cash_account_id FROM accounts WHERE account_code = '1000' LIMIT 1;

      BEGIN
        SELECT id, balance INTO v_treasury_balance_id, v_balance_before
        FROM treasury_balances WHERE treasury_id = v_treasury_id_int AND currency = 'EGP' LIMIT 1;

        UPDATE treasury_balances SET balance = balance + v_paid_amount
        WHERE treasury_id = v_treasury_id_int AND currency = 'EGP';

        SELECT balance INTO v_balance_after
        FROM treasury_balances WHERE treasury_id = v_treasury_id_int AND currency = 'EGP';
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'treasury_balances reverse failed: %', SQLERRM;
        v_balance_before := 0;
        v_balance_after := v_paid_amount;
      END;

      SELECT * INTO v_old_treasury_tx
      FROM treasury_transactions
      WHERE description LIKE '%' || COALESCE(v_purchase.invoice_number, '') || '%'
        AND type = 'expense'
      ORDER BY created_at DESC LIMIT 1;

      IF v_old_treasury_tx IS NOT NULL THEN
        UPDATE treasury_transactions
        SET type = 'deposit',
            description = 'إلغاء دفعة - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, ''),
            balance_before = COALESCE(v_balance_before, 0),
            balance_after = COALESCE(v_balance_after, v_paid_amount)
        WHERE id = v_old_treasury_tx.id;
      ELSE
        BEGIN
          INSERT INTO treasury_transactions (
            treasury_id, type, currency, amount,
            balance_before, balance_after,
            description, supplier_id, created_by, created_at
          ) VALUES (
            v_treasury_id_int, 'deposit', 'EGP', v_paid_amount,
            COALESCE(v_balance_before, 0), COALESCE(v_balance_after, v_paid_amount),
            'إلغاء دفعة نقدية للمورد - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, ''),
            v_purchase.supplier_id, p_user_id, now()
          );
        EXCEPTION WHEN OTHERS THEN
          RAISE NOTICE 'treasury_transactions reverse insert failed: %', SQLERRM;
        END;
      END IF;

      IF v_cash_account_id IS NOT NULL AND v_supplier_account_id IS NOT NULL THEN
        PERFORM create_balanced_entry(
          p_debit_account_id := v_cash_account_id,
          p_credit_account_id := v_supplier_account_id,
          p_amount := v_paid_amount,
          p_description := 'إلغاء دفعة للمورد - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, ''),
          p_transaction_date := now()::DATE,
          p_reference_type := 'purchase_cancel_payment',
          p_reference_id := NULL,
          p_currency_snapshot := NULL,
          p_purchase_invoice_ref := NULL
        );
      END IF;
    END IF;
  END IF;

  UPDATE purchase_invoices SET status = 'cancelled', updated_at = now()
  WHERE id::TEXT = p_purchase_id;

  RETURN jsonb_build_object(
    'success', true,
    'purchase_id', p_purchase_id,
    'paid_amount_reversed', v_paid_amount,
    'inventory_reversed_egp', v_total_egp
  );
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'حدث خطأ أثناء إلغاء المشتريات: %', SQLERRM;
END;
$$;

--
-- Name: rpc_confirm_packing_order(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."rpc_confirm_packing_order"("p_packing_order_id" bigint) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_order RECORD;
  v_notes JSONB;
  v_station_id INTEGER;
  v_allocations JSONB := '[]'::jsonb;
  v_el JSONB;
  v_rate NUMERIC;
  v_amt_egp NUMERIC;
  v_amt_foreign NUMERIC;
  v_curr TEXT;
BEGIN
  SELECT * INTO v_order FROM packing_orders WHERE id = p_packing_order_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  IF v_order.status NOT IN ('draft', 'pending') THEN
    RETURN json_build_object('success', false, 'error', 'لا يمكن تأكيد أمر تعبئة بحالة ' || v_order.status);
  END IF;

  v_station_id := v_order.station_id;
  IF v_station_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'لم يتم تحديد المحطة');
  END IF;

  v_notes := CASE WHEN v_order.notes IS NOT NULL AND v_order.notes != ''
    THEN v_order.notes::jsonb ELSE '{}'::jsonb END;

  -- Build fruit allocation entry
  IF v_notes ? 'fruit_allocation' THEN
    v_el := v_notes->'fruit_allocation';
    IF jsonb_typeof(v_el) = 'array' THEN
      FOR i IN 0..jsonb_array_length(v_el) - 1 LOOP
        v_allocations := v_allocations || jsonb_build_array(v_el->i);
      END LOOP;
    ELSIF jsonb_typeof(v_el) = 'object' THEN
      v_allocations := v_allocations || jsonb_build_array(v_el);
    END IF;
  END IF;

  -- Build material allocation entries
  IF v_notes ? 'materials' THEN
    FOR v_el IN SELECT jsonb_array_elements(v_notes->'materials')
    LOOP
      v_allocations := v_allocations || jsonb_build_array(
        jsonb_build_object(
          'batch_id', v_el->>'batch_id',
          'quantity', v_el->>'used_qty',
          'product_name', v_el->>'product_name',
          'product_code', COALESCE(v_el->>'product_code', '')
        )
      );
    END LOOP;
  END IF;

  -- Deduct from warehouse via existing RPC
  IF jsonb_array_length(v_allocations) > 0 THEN
    PERFORM deduct_station_batch_allocations(v_station_id, v_allocations);
  END IF;

  -- Process cost items for supplier balances
  IF v_notes ? 'cost_items' THEN
    FOR v_el IN SELECT jsonb_array_elements(v_notes->'cost_items')
    LOOP
      IF v_el->>'supplier_id' IS NOT NULL AND v_el->>'supplier_id' != '' THEN
        v_rate := COALESCE(NULLIF((v_el->>'exchange_rate')::numeric, 0), 1.0);
        v_amt_egp := COALESCE((v_el->>'total_egp')::numeric, (v_el->>'total')::numeric, 0);
        v_amt_foreign := ROUND(v_amt_egp / v_rate, 2);
        v_curr := COALESCE(NULLIF(v_el->>'supplier_currency', ''), 'EGP');

        IF v_amt_foreign > 0 THEN
          UPDATE suppliers
          SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_amt_foreign,
              updated_at = now()
          WHERE id = (v_el->>'supplier_id')::uuid;

          INSERT INTO ledger_entries (
            entity_type, entity_id, entry_type, amount, currency,
            reference_type, reference_text, description, created_by
          ) VALUES (
            'supplier', v_el->>'supplier_id', 'credit', v_amt_foreign, v_curr,
            'packing_cost', p_packing_order_id::text,
            'بند تكلفة أمر تعبئة: ' || COALESCE(v_el->>'name', 'غير محدد') || ' (أمر ' || p_packing_order_id::text || ')',
            auth.uid()
          );
        END IF;
      END IF;
    END LOOP;
  END IF;

  UPDATE packing_orders
    SET status = 'completed',
        packed_at = NOW(),
        updated_at = NOW()
  WHERE id = p_packing_order_id;

  RETURN json_build_object('success', true);
END;
$$;

--
-- Name: enforce_read_only("uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."enforce_read_only"("p_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF public.check_tenant_read_only(p_user_id) THEN
    RAISE EXCEPTION 'النظام في وضع القراءة فقط — لا يمكن إجراء تعديلات';
  END IF;
END;
$$;

--
-- Name: rpc_confirm_purchase("text", "uuid"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."rpc_confirm_purchase"("p_purchase_id" "text", "p_user_id" "uuid" DEFAULT "auth"."uid"()) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_purchase RECORD;
  v_item RECORD;
  v_batch_number TEXT;
  v_date_str TEXT;
  v_seq INT := 0;
  v_station_product_name TEXT;
  v_cur_qty NUMERIC;
  v_cur_price NUMERIC;
  v_new_qty NUMERIC;
  v_new_price NUMERIC;
  v_total_egp NUMERIC := 0;
  v_item_egp NUMERIC;
  v_inventory_account_id INTEGER;
  v_supplier_account_id INTEGER;
  v_account_group RECORD;
  v_paid_amount NUMERIC;
  v_treasury_id_int INTEGER;
  v_bank_account_id INTEGER;
  v_source_type TEXT;
  v_cash_account_id INTEGER;
  v_treasury_name TEXT;
  v_bank_name TEXT;
  v_treasury_balance_id INTEGER;
  v_balance_before NUMERIC;
  v_balance_after NUMERIC;
  v_payment_number TEXT;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'غير مصرح لك بإجراء هذه العملية';
  END IF;

  SELECT * INTO v_purchase FROM purchase_invoices WHERE id::TEXT = p_purchase_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'فاتورة المشتريات غير موجودة';
  END IF;

  IF v_purchase.status = 'confirmed' THEN
    RAISE EXCEPTION 'الفاتورة مؤكدة بالفعل';
  END IF;

  v_date_str := COALESCE(to_char(v_purchase.invoice_date, 'YYYYMMDD'), to_char(now(), 'YYYYMMDD'));

  SELECT id INTO v_supplier_account_id FROM accounts WHERE account_code = '2000' LIMIT 1;
  IF v_supplier_account_id IS NULL THEN
    RAISE EXCEPTION 'حساب الموردين (2000) غير موجود في شجرة الحسابات';
  END IF;

  FOR v_item IN
    SELECT pii.*, rm.code AS rm_code, rm.name AS rm_name, rm.unit AS rm_unit,
           rmc.name AS category_name
    FROM purchase_invoice_items pii
    LEFT JOIN raw_materials rm ON rm.id = pii.raw_material_id
    LEFT JOIN raw_material_categories rmc ON rmc.id = rm.category_id
    WHERE pii.invoice_id::TEXT = p_purchase_id
  LOOP
    v_seq := v_seq + 1;
    v_batch_number := 'B-' || v_date_str || '-' || v_purchase.id::TEXT || '-' || lpad(v_seq::TEXT, 4, '0');

    BEGIN
      INSERT INTO stock_batches (
        batch_number, product_id, supplier_id, purchase_invoice_id,
        quantity, remaining_quantity, purchase_cost, average_cost,
        exchange_rate, currency, status, user_id
      ) VALUES (
        v_batch_number,
        v_item.raw_material_id,
        v_purchase.supplier_id,
        v_purchase.id,
        v_item.quantity,
        v_item.quantity,
        v_item.unit_cost,
        v_item.unit_cost,
        COALESCE(v_item.exchange_rate, 1.0),
        COALESCE(v_purchase.currency, 'EGP'),
        'active',
        p_user_id
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'stock_batches insert failed for batch %: %', v_batch_number, SQLERRM;
    END;

    IF v_item.raw_material_id IS NOT NULL THEN
      SELECT quantity, default_purchase_price INTO v_cur_qty, v_cur_price
      FROM raw_materials WHERE id = v_item.raw_material_id;

      IF FOUND THEN
        v_cur_qty := COALESCE(v_cur_qty, 0);
        v_cur_price := COALESCE(v_cur_price, 0);
        v_new_qty := v_cur_qty + v_item.quantity;
        IF v_new_qty > 0 THEN
          v_new_price := ((v_cur_qty * v_cur_price) + (v_item.quantity * v_item.unit_cost)) / v_new_qty;
        ELSE
          v_new_price := v_cur_price;
        END IF;
        UPDATE raw_materials
        SET quantity = v_new_qty, default_purchase_price = v_new_price, updated_at = now()
        WHERE id = v_item.raw_material_id;
      END IF;
    END IF;

    IF v_item.raw_material_id IS NOT NULL THEN
      DECLARE
        v_station_id BIGINT;
      BEGIN
        v_station_id := v_item.station_id;

        IF v_station_id IS NULL THEN
          SELECT spb.station_id INTO v_station_id
          FROM station_product_batches spb
          WHERE spb.product_code = COALESCE(v_item.rm_code, '') AND spb.source_type = 'purchase'
          LIMIT 1;
        END IF;

        IF v_station_id IS NULL THEN
          SELECT sp.id INTO v_station_id
          FROM station_products sp
          WHERE sp.product_code = COALESCE(v_item.rm_code, '') LIMIT 1;
        END IF;

        IF v_station_id IS NOT NULL THEN
          v_station_product_name := COALESCE(v_item.rm_name, '') || ' (مادة تعبئة)';
          PERFORM upsert_station_product_quantity(v_station_id, v_station_product_name, COALESCE(v_item.rm_code, ''), v_item.quantity::INT);

          BEGIN
            INSERT INTO station_product_batches (
              station_id, product_name, product_code, quantity, remaining_quantity,
              unit_cost, currency, exchange_rate, source_type, source_date,
              supplier_name, purchase_invoice_id
            ) VALUES (
              v_station_id, v_station_product_name, COALESCE(v_item.rm_code, ''),
              v_item.quantity, v_item.quantity,
              v_item.unit_cost, COALESCE(v_purchase.currency, 'EGP'),
              COALESCE(v_item.exchange_rate, 1.0), 'purchase', now(),
              (SELECT name FROM suppliers WHERE id = v_purchase.supplier_id),
              v_purchase.id
            );
          EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'station_product_batches insert failed: %', SQLERRM;
          END;
        END IF;
      END;
    END IF;

    v_item_egp := v_item.quantity * v_item.unit_cost * COALESCE(NULLIF(v_item.exchange_rate, 0), 1.0);
    v_total_egp := v_total_egp + v_item_egp;
  END LOOP;

  IF v_purchase.supplier_id IS NOT NULL THEN
    DECLARE
      v_remaining NUMERIC;
    BEGIN
      v_remaining := COALESCE(v_purchase.total_amount, 0) - COALESCE(v_purchase.paid_amount, 0);
      IF v_remaining > 0 THEN
        UPDATE suppliers
        SET outstanding_balance = COALESCE(outstanding_balance, 0) + v_remaining
        WHERE id = v_purchase.supplier_id;
      END IF;
    END;
  END IF;

  IF v_total_egp > 0 THEN
    FOR v_account_group IN
      SELECT
        CASE
          WHEN rmc.name = 'مواد تعبئة' THEN '1040'
          ELSE '1030'
        END AS account_code,
        SUM(pii.quantity * pii.unit_cost * COALESCE(NULLIF(pii.exchange_rate, 0), 1.0)) AS total_egp
      FROM purchase_invoice_items pii
      LEFT JOIN raw_materials rm ON rm.id = pii.raw_material_id
      LEFT JOIN raw_material_categories rmc ON rmc.id = rm.category_id
      WHERE pii.invoice_id::TEXT = p_purchase_id
      GROUP BY CASE WHEN rmc.name = 'مواد تعبئة' THEN '1040' ELSE '1030' END
    LOOP
      SELECT id INTO v_inventory_account_id
      FROM accounts WHERE account_code = v_account_group.account_code LIMIT 1;

      IF v_inventory_account_id IS NULL THEN
        RAISE EXCEPTION 'حساب المخزون (%) غير موجود في شجرة الحسابات', v_account_group.account_code;
      END IF;

      PERFORM create_balanced_entry(
        p_debit_account_id := v_inventory_account_id,
        p_credit_account_id := v_supplier_account_id,
        p_amount := v_account_group.total_egp,
        p_description := 'مشتريات رقم ' || COALESCE(v_purchase.invoice_number, ''),
        p_transaction_date := v_purchase.invoice_date,
        p_reference_type := 'purchase',
        p_reference_id := NULL,
        p_currency_snapshot := NULL,
        p_purchase_invoice_ref := v_purchase.id
      );
    END LOOP;
  END IF;

  v_paid_amount := COALESCE(v_purchase.paid_amount, 0);
  v_bank_account_id := v_purchase.payment_bank_account_id;
  v_source_type := COALESCE(v_purchase.payment_source_type, 'treasury');
  v_treasury_id_int := v_purchase.payment_treasury_id::INTEGER;

  IF v_paid_amount > 0 AND v_purchase.supplier_id IS NOT NULL THEN
    IF v_source_type = 'bank' AND v_bank_account_id IS NOT NULL THEN
      SELECT id INTO v_cash_account_id FROM accounts WHERE account_code = '1010' LIMIT 1;
      IF v_cash_account_id IS NULL THEN
        RAISE EXCEPTION 'حساب البنك (1010) غير موجود في شجرة الحسابات.';
      END IF;

      UPDATE bank_accounts
      SET balance = balance - v_paid_amount, updated_at = now()
      WHERE id = v_bank_account_id AND currency = COALESCE(v_purchase.currency, 'EGP');

      SELECT name INTO v_bank_name FROM bank_accounts WHERE id = v_bank_account_id;

      PERFORM create_balanced_entry(
        p_debit_account_id := v_supplier_account_id,
        p_credit_account_id := v_cash_account_id,
        p_amount := v_paid_amount,
        p_description := 'دفعة للمورد - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, '') || ' - من ' || COALESCE(v_bank_name, ''),
        p_transaction_date := v_purchase.invoice_date,
        p_reference_type := 'purchase_payment',
        p_reference_id := NULL,
        p_currency_snapshot := NULL,
        p_purchase_invoice_ref := v_purchase.id
      );

      BEGIN
        v_payment_number := 'PAY-' || to_char(now(), 'YYYYMMDD') || '-' || LPAD(nextval('entry_number_seq')::TEXT, 4, '0');
        INSERT INTO cash_payments (
          payment_number, supplier_id, amount, payment_method,
          notes, payment_date, created_by, created_at, updated_at
        ) VALUES (
          v_payment_number, v_purchase.supplier_id, v_paid_amount, 'bank',
          'دفعة من ' || COALESCE(v_bank_name, 'البنك') || ' - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, ''),
          v_purchase.invoice_date, p_user_id, now(), now()
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'cash_payments insert failed: %', SQLERRM;
      END;

    ELSIF v_source_type = 'treasury' AND v_treasury_id_int IS NOT NULL THEN
      SELECT id INTO v_cash_account_id FROM accounts WHERE account_code = '1000' LIMIT 1;
      IF v_cash_account_id IS NULL THEN
        RAISE EXCEPTION 'حساب الصندوق (1000) غير موجود في شجرة الحسابات.';
      END IF;

      BEGIN
        SELECT id, balance INTO v_treasury_balance_id, v_balance_before
        FROM treasury_balances
        WHERE treasury_id = v_treasury_id_int AND currency = 'EGP' LIMIT 1;

        UPDATE treasury_balances
        SET balance = balance - v_paid_amount
        WHERE treasury_id = v_treasury_id_int AND currency = 'EGP';

        SELECT balance INTO v_balance_after
        FROM treasury_balances
        WHERE treasury_id = v_treasury_id_int AND currency = 'EGP';
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'treasury_balances update failed: %', SQLERRM;
        v_balance_before := 0;
        v_balance_after := -v_paid_amount;
      END;

      SELECT name INTO v_treasury_name FROM treasuries WHERE id = v_treasury_id_int;

      BEGIN
        INSERT INTO treasury_transactions (
          treasury_id, type, currency, amount,
          balance_before, balance_after,
          description, supplier_id, created_by, created_at
        ) VALUES (
          v_treasury_id_int, 'expense', COALESCE(v_purchase.currency, 'EGP'), v_paid_amount,
          COALESCE(v_balance_before, 0), COALESCE(v_balance_after, -v_paid_amount),
          'دفعة نقدية للمورد - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, '') || ' - من ' || COALESCE(v_treasury_name, ''),
          v_purchase.supplier_id, p_user_id, now()
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'treasury_transactions insert failed: %', SQLERRM;
      END;

      PERFORM create_balanced_entry(
        p_debit_account_id := v_supplier_account_id,
        p_credit_account_id := v_cash_account_id,
        p_amount := v_paid_amount,
        p_description := 'دفعة للمورد - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, '') || ' - من ' || COALESCE(v_treasury_name, ''),
        p_transaction_date := v_purchase.invoice_date,
        p_reference_type := 'purchase_payment',
        p_reference_id := NULL,
        p_currency_snapshot := NULL,
        p_purchase_invoice_ref := v_purchase.id
      );

      BEGIN
        v_payment_number := 'PAY-' || to_char(now(), 'YYYYMMDD') || '-' || LPAD(nextval('entry_number_seq')::TEXT, 4, '0');
        INSERT INTO cash_payments (
          payment_number, supplier_id, amount, payment_method,
          notes, payment_date, created_by, created_at, updated_at
        ) VALUES (
          v_payment_number, v_purchase.supplier_id, v_paid_amount, 'cash',
          'دفعة من ' || COALESCE(v_treasury_name, 'الخزينة') || ' - فاتورة رقم ' || COALESCE(v_purchase.invoice_number, ''),
          v_purchase.invoice_date, p_user_id, now(), now()
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'cash_payments insert failed: %', SQLERRM;
      END;
    END IF;
  END IF;

  UPDATE purchase_invoices
  SET status = 'confirmed', updated_at = now()
  WHERE id::TEXT = p_purchase_id;

  RETURN jsonb_build_object(
    'success', true,
    'purchase_id', p_purchase_id,
    'paid_amount', v_paid_amount,
    'remaining', COALESCE(v_purchase.total_amount, 0) - v_paid_amount,
    'source_type', COALESCE(v_source_type, 'treasury'),
    'treasury_name', COALESCE(v_treasury_name, ''),
    'bank_name', COALESCE(v_bank_name, '')
  );
EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'حدث خطأ أثناء تأكيد المشتريات: %', SQLERRM;
END;
$$;

--
-- Name: rpc_cancel_packing_order(bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."rpc_cancel_packing_order"("p_packing_order_id" bigint) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_order RECORD;
  v_notes JSONB;
  v_station_id INTEGER;
  v_allocations JSONB := '[]'::jsonb;
  v_el JSONB;
  v_rate NUMERIC;
  v_amt_egp NUMERIC;
  v_amt_foreign NUMERIC;
  v_curr TEXT;
BEGIN
  SELECT * INTO v_order FROM packing_orders WHERE id = p_packing_order_id;
  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'أمر التعبئة غير موجود');
  END IF;

  IF v_order.status != 'completed' THEN
    RETURN json_build_object('success', false, 'error', 'لا يمكن إلغاء أمر تعبئة بحالة ' || v_order.status);
  END IF;

  v_station_id := v_order.station_id;
  IF v_station_id IS NULL THEN
    RETURN json_build_object('success', false, 'error', 'لم يتم تحديد المحطة');
  END IF;

  v_notes := CASE WHEN v_order.notes IS NOT NULL AND v_order.notes != ''
    THEN v_order.notes::jsonb ELSE '{}'::jsonb END;

  -- Build fruit allocation entry
  IF v_notes ? 'fruit_allocation' THEN
    v_el := v_notes->'fruit_allocation';
    IF jsonb_typeof(v_el) = 'array' THEN
      FOR i IN 0..jsonb_array_length(v_el) - 1 LOOP
        v_allocations := v_allocations || jsonb_build_array(v_el->i);
      END LOOP;
    ELSIF jsonb_typeof(v_el) = 'object' THEN
      v_allocations := v_allocations || jsonb_build_array(v_el);
    END IF;
  END IF;

  -- Build material allocation entries
  IF v_notes ? 'materials' THEN
    FOR v_el IN SELECT jsonb_array_elements(v_notes->'materials')
    LOOP
      v_allocations := v_allocations || jsonb_build_array(
        jsonb_build_object(
          'batch_id', v_el->>'batch_id',
          'quantity', v_el->>'used_qty',
          'product_name', v_el->>'product_name',
          'product_code', COALESCE(v_el->>'product_code', '')
        )
      );
    END LOOP;
  END IF;

  -- Restore to warehouse via existing RPC
  IF jsonb_array_length(v_allocations) > 0 THEN
    PERFORM restore_station_batch_allocations(v_station_id, v_allocations);
  END IF;

  -- Removed Reverse cost items logic as requested by user

  UPDATE packing_orders
    SET status = 'cancelled',
        updated_at = NOW()
  WHERE id = p_packing_order_id;

  RETURN json_build_object('success', true);
END;
$$;

--
-- Name: record_supplier_payment("uuid", numeric, "text", "text", integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."record_supplier_payment"("p_supplier_id" "uuid", "p_amount" numeric, "p_currency" "text" DEFAULT 'EGP'::"text", "p_description" "text" DEFAULT ''::"text", "p_treasury_id" integer DEFAULT NULL::integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_ledger_id BIGINT;
    v_tx_id     INTEGER;
    v_bal RECORD;
BEGIN
    IF NOT public._is_admin() THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    -- Reduce supplier outstanding (debit = we paid them)
    UPDATE suppliers SET outstanding_balance = outstanding_balance - p_amount WHERE id = p_supplier_id;

    INSERT INTO ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by)
    VALUES ('supplier', p_supplier_id::TEXT, 'debit', p_amount, p_currency, 'payment', p_description, auth.uid())
    RETURNING id INTO v_ledger_id;

    IF p_treasury_id IS NOT NULL THEN
        SELECT balance INTO v_bal
        FROM treasury_balances
        WHERE treasury_id = p_treasury_id AND currency = p_currency
        FOR UPDATE;

        IF v_bal.balance < p_amount THEN
            RAISE EXCEPTION 'الرصيد غير كافٍ في الخزنة (المتوفر: %)', v_bal.balance;
        END IF;

        UPDATE treasury_balances
        SET balance = balance - p_amount
        WHERE treasury_id = p_treasury_id AND currency = p_currency;

        INSERT INTO treasury_transactions (treasury_id, type, currency, amount, description, created_by)
        VALUES (p_treasury_id, 'supplier_payment', p_currency, p_amount, p_description, auth.uid())
        RETURNING id INTO v_tx_id;
    END IF;

    RETURN jsonb_build_object('ledger_entry_id', v_ledger_id, 'treasury_tx_id', v_tx_id);
END;
$$;

--
-- Name: delete_bank_account_transaction(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."delete_bank_account_transaction"("p_transaction_id" integer) RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_tx            RECORD;
  v_balance_diff  NUMERIC;
  v_ledger_entry  RECORD;
BEGIN
  IF NOT public._is_admin() THEN
    RAISE EXCEPTION 'غير مصرح لك بهذه العملية';
  END IF;

  SELECT id, bank_account_id, type, amount, balance_before, balance_after,
         entity_type, entity_id, counterparty_name, description
  INTO v_tx
  FROM public.bank_account_transactions
  WHERE id = p_transaction_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'الحركة غير موجودة';
  END IF;

  -- Reverse the amount from the bank account balance
  IF v_tx.type = 'deposit' THEN
    v_balance_diff := -v_tx.amount;
  ELSE
    v_balance_diff := v_tx.amount;
  END IF;

  -- Check if balance would go negative
  DECLARE
    v_current_balance NUMERIC;
  BEGIN
    SELECT balance INTO v_current_balance FROM public.bank_accounts WHERE id = v_tx.bank_account_id;
    IF v_current_balance + v_balance_diff < 0 THEN
      RAISE EXCEPTION 'لا يمكن حذف هذه الحركة لأن الرصيد سينخفض عن الصفر';
    END IF;
  END;

  -- Reverse counterparty balance if entity was tracked
  IF v_tx.entity_type IS NOT NULL AND v_tx.entity_id IS NOT NULL THEN
    IF v_tx.entity_type = 'customer' THEN
      UPDATE public.customers
      SET balance = CASE
        WHEN v_tx.type = 'deposit' THEN balance + v_tx.amount
        ELSE balance - v_tx.amount
      END
      WHERE id = v_tx.entity_id::INTEGER;
    ELSIF v_tx.entity_type = 'supplier' THEN
      UPDATE public.suppliers
      SET outstanding_balance = CASE
        WHEN v_tx.type = 'deposit' THEN outstanding_balance - v_tx.amount
        ELSE outstanding_balance + v_tx.amount
      END
      WHERE id = v_tx.entity_id::UUID;
    ELSIF v_tx.entity_type = 'clearing_agent' THEN
      UPDATE public.clearing_agents
      SET manual_adjustment = CASE
        WHEN v_tx.type = 'deposit' THEN manual_adjustment - v_tx.amount
        ELSE manual_adjustment + v_tx.amount
      END,
      balance = CASE
        WHEN v_tx.type = 'deposit' THEN balance - v_tx.amount
        ELSE balance + v_tx.amount
      END
      WHERE id = v_tx.entity_id::INTEGER;
    ELSIF v_tx.entity_type = 'shipping_company' THEN
      UPDATE public.shipping_companies
      SET manual_adjustment = CASE
        WHEN v_tx.type = 'deposit' THEN manual_adjustment - v_tx.amount
        ELSE manual_adjustment + v_tx.amount
      END,
      balance = CASE
        WHEN v_tx.type = 'deposit' THEN balance - v_tx.amount
        ELSE balance + v_tx.amount
      END
      WHERE id = v_tx.entity_id::INTEGER;
    END IF;

    -- Delete the linked ledger entry
    DELETE FROM public.ledger_entries
    WHERE id = (
      SELECT id FROM public.ledger_entries
      WHERE entity_type = v_tx.entity_type
        AND entity_id = v_tx.entity_id
        AND reference_type = 'bank_transfer'
        AND amount = v_tx.amount
        AND (
          (v_tx.type = 'deposit'   AND entry_type = 'credit')
          OR
          (v_tx.type = 'withdraw' AND entry_type = 'debit')
        )
      LIMIT 1
    );
  END IF;

  -- Update the bank account balance
  UPDATE public.bank_accounts
  SET balance = balance + v_balance_diff
  WHERE id = v_tx.bank_account_id;

  -- Delete the transaction
  DELETE FROM public.bank_account_transactions WHERE id = p_transaction_id;

  -- Fix subsequent transactions
  IF v_tx.type = 'deposit' THEN
    UPDATE public.bank_account_transactions
    SET balance_before = balance_before - v_tx.amount,
        balance_after = balance_after - v_tx.amount
    WHERE bank_account_id = v_tx.bank_account_id
      AND id > p_transaction_id;
  ELSE
    UPDATE public.bank_account_transactions
    SET balance_before = balance_before + v_tx.amount,
        balance_after = balance_after + v_tx.amount
    WHERE bank_account_id = v_tx.bank_account_id
      AND id > p_transaction_id;
  END IF;

  RETURN json_build_object(
    'id', v_tx.bank_account_id,
    'balance', (SELECT balance FROM public.bank_accounts WHERE id = v_tx.bank_account_id)
  );
END;
$$;

--
-- Name: disburse_custody(integer, integer, "text", numeric, "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."disburse_custody"("p_from_treasury_id" integer, "p_to_treasury_id" integer, "p_currency" "text", "p_amount" numeric, "p_description" "text" DEFAULT ''::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_from_balance NUMERIC;
    v_to_balance   NUMERIC;
BEGIN
    IF NOT public._is_admin() THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    -- Lock and check source treasury balance
    SELECT balance INTO v_from_balance
    FROM treasury_balances
    WHERE treasury_id::TEXT = p_from_treasury_id::TEXT AND currency = p_currency
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'لا يوجد رصيد للخزنة المصدرة بهذه العملة';
    END IF;

    IF v_from_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ في الخزنة المصدرة (المتوفر: %)', v_from_balance;
    END IF;

    -- Lock destination treasury balance
    SELECT balance INTO v_to_balance
    FROM treasury_balances
    WHERE treasury_id::TEXT = p_to_treasury_id::TEXT AND currency = p_currency
    FOR UPDATE;

    -- Deduct from source
    UPDATE treasury_balances SET balance = balance - p_amount
    WHERE treasury_id::TEXT = p_from_treasury_id::TEXT AND currency = p_currency;

    -- Add to destination
    IF v_to_balance IS NULL THEN
        INSERT INTO treasury_balances (treasury_id, currency, balance)
        VALUES (p_to_treasury_id, p_currency, p_amount);
    ELSE
        UPDATE treasury_balances SET balance = balance + p_amount
        WHERE treasury_id::TEXT = p_to_treasury_id::TEXT AND currency = p_currency;
    END IF;

    -- Record transactions
    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by)
    VALUES (p_from_treasury_id, 'disbursement_out', p_currency, p_amount,
        v_from_balance, v_from_balance - p_amount, p_description, p_to_treasury_id, auth.uid());

    INSERT INTO treasury_transactions (treasury_id, type, currency, amount,
        balance_before, balance_after, description, related_treasury_id, created_by)
    VALUES (p_to_treasury_id, 'disbursement', p_currency, p_amount,
        COALESCE(v_to_balance, 0), COALESCE(v_to_balance, 0) + p_amount, p_description,
        p_from_treasury_id, auth.uid());
END;
$$;

--
-- Name: record_customer_payment(integer, numeric, "text", "text", integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."record_customer_payment"("p_customer_id" integer, "p_amount" numeric, "p_currency" "text" DEFAULT 'EGP'::"text", "p_description" "text" DEFAULT ''::"text", "p_treasury_id" integer DEFAULT NULL::integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_ledger_id BIGINT;
    v_tx_id     INTEGER;
    v_bal RECORD;
BEGIN
    IF NOT public._is_admin() THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    -- Reduce customer balance (credit = they paid us)
    UPDATE customers SET balance = balance - p_amount WHERE id = p_customer_id;

    INSERT INTO ledger_entries (entity_type, entity_id, entry_type, amount, currency, reference_type, description, created_by)
    VALUES ('customer', p_customer_id::TEXT, 'credit', p_amount, p_currency, 'payment', p_description, auth.uid())
    RETURNING id INTO v_ledger_id;

    IF p_treasury_id IS NOT NULL THEN
        SELECT balance INTO v_bal
        FROM treasury_balances
        WHERE treasury_id = p_treasury_id AND currency = p_currency
        FOR UPDATE;

        IF NOT FOUND THEN
            INSERT INTO treasury_balances (treasury_id, currency, balance)
            VALUES (p_treasury_id, p_currency, p_amount);
        ELSE
            UPDATE treasury_balances
            SET balance = balance + p_amount
            WHERE treasury_id = p_treasury_id AND currency = p_currency;
        END IF;

        INSERT INTO treasury_transactions (treasury_id, type, currency, amount, description, created_by)
        VALUES (p_treasury_id, 'customer_payment', p_currency, p_amount, p_description, auth.uid())
        RETURNING id INTO v_tx_id;
    END IF;

    RETURN jsonb_build_object('ledger_entry_id', v_ledger_id, 'treasury_tx_id', v_tx_id);
END;
$$;

--
-- Name: update_bank_account_transaction(integer, numeric, "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."update_bank_account_transaction"("p_transaction_id" integer, "p_new_amount" numeric, "p_new_description" "text" DEFAULT NULL::"text") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_tx          RECORD;
  v_balance_diff NUMERIC;
  v_new_balance  NUMERIC;
BEGIN
  IF NOT public._is_admin() THEN
    RAISE EXCEPTION 'غير مصرح لك بهذه العملية';
  END IF;

  IF p_new_amount <= 0 THEN
    RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
  END IF;

  SELECT id, bank_account_id, type, amount, balance_before, balance_after
  INTO v_tx
  FROM public.bank_account_transactions
  WHERE id = p_transaction_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'الحركة غير موجودة';
  END IF;

  -- Calculate the difference between old and new amounts
  v_balance_diff := p_new_amount - v_tx.amount;

  -- Apply the difference to the balance_after
  IF v_tx.type = 'deposit' THEN
    v_new_balance := v_tx.balance_after + v_balance_diff;
  ELSE
    v_new_balance := v_tx.balance_after - v_balance_diff;
  END IF;

  -- Ensure balance doesn't go negative for withdraw corrections
  IF v_new_balance < 0 THEN
    RAISE EXCEPTION 'الرصيد لا يمكن أن يصبح سالباً (المتوفر: %)', v_tx.balance_after;
  END IF;

  -- Update the bank account balance
  UPDATE public.bank_accounts
  SET balance = v_new_balance
  WHERE id = v_tx.bank_account_id;

  -- Update the transaction
  UPDATE public.bank_account_transactions
  SET amount = p_new_amount,
      balance_after = v_new_balance,
      description = p_new_description
  WHERE id = p_transaction_id;

  -- Fix subsequent transactions' balance_before and balance_after
  IF v_tx.type = 'deposit' THEN
    UPDATE public.bank_account_transactions
    SET balance_before = balance_before + v_balance_diff,
        balance_after = balance_after + v_balance_diff
    WHERE bank_account_id = v_tx.bank_account_id
      AND id > p_transaction_id;
  ELSE
    UPDATE public.bank_account_transactions
    SET balance_before = balance_before - v_balance_diff,
        balance_after = balance_after - v_balance_diff
    WHERE bank_account_id = v_tx.bank_account_id
      AND id > p_transaction_id;
  END IF;

  RETURN json_build_object('id', v_tx.bank_account_id, 'balance', v_new_balance);
END;
$$;

--
-- Name: withdraw_treasury(integer, "text", numeric, "text"); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."withdraw_treasury"("p_treasury_id" integer, "p_currency" "text", "p_amount" numeric, "p_description" "text" DEFAULT ''::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    v_current_balance NUMERIC;
    v_new_balance     NUMERIC;
BEGIN
    IF NOT public._is_admin() THEN
        RAISE EXCEPTION 'غير مصرح بهذه العملية';
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر';
    END IF;

    SELECT balance INTO v_current_balance
    FROM treasury_balances
    WHERE treasury_id = p_treasury_id AND currency = p_currency
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'لا يوجد رصيد لهذه العملة';
    END IF;

    IF v_current_balance < p_amount THEN
        RAISE EXCEPTION 'الرصيد غير كافٍ (المتوفر: %)', v_current_balance;
    END IF;

    v_new_balance := v_current_balance - p_amount;

    UPDATE treasury_balances
    SET balance = v_new_balance
    WHERE treasury_id = p_treasury_id AND currency = p_currency;

    INSERT INTO treasury_transactions (
        treasury_id, type, currency, amount,
        balance_before, balance_after, description, created_by
    ) VALUES (
        p_treasury_id, 'withdrawal', p_currency, p_amount,
        v_current_balance, v_new_balance, p_description, auth.uid()
    );
END;
$$;

--
-- Name: on_auth_user_created_combined(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."on_auth_user_created_combined"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  -- Only create public.users record — sign_up_new_tenant RPC handles tenant creation + linking
  INSERT INTO public.users (id, full_name, email, username, is_admin)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
    NEW.email,
    split_part(NEW.email, '@', 1),
    false
  )
  ON CONFLICT (id) DO UPDATE SET
    full_name = COALESCE(EXCLUDED.full_name, public.users.full_name),
    email = EXCLUDED.email,
    username = EXCLUDED.username;

  -- Do NOT auto-link to any tenant — sign_up_new_tenant handles that

  RETURN NEW;
END;
$$;

-- ==========================================
-- 7. CREATE TRIGGER STATEMENTS
-- ==========================================
--
-- Name: purchase_invoices audit_purchase_invoices; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "audit_purchase_invoices" AFTER INSERT OR DELETE OR UPDATE ON "public"."purchase_invoices" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger_func"();

--
-- Name: sales_invoices audit_sales_invoices; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "audit_sales_invoices" AFTER INSERT OR DELETE OR UPDATE ON "public"."sales_invoices" FOR EACH ROW EXECUTE FUNCTION "public"."audit_trigger_func"();

--
-- Name: transactions check_entry_balance_trigger; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "check_entry_balance_trigger" AFTER INSERT OR DELETE OR UPDATE ON "public"."transactions" FOR EACH STATEMENT EXECUTE FUNCTION "public"."check_entry_balance"();

--
-- Name: users on_new_admin_treasury; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "on_new_admin_treasury" AFTER INSERT ON "public"."users" FOR EACH ROW EXECUTE FUNCTION "public"."handle_new_admin_treasury"();

--
-- Name: customers set_customers_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "set_customers_updated_at" BEFORE UPDATE ON "public"."customers" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();

--
-- Name: export_invoices set_export_invoices_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "set_export_invoices_updated_at" BEFORE UPDATE ON "public"."export_invoices" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();

--
-- Name: suppliers set_suppliers_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "set_suppliers_updated_at" BEFORE UPDATE ON "public"."suppliers" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();

--
-- Name: bank_account_transactions trg_check_fy_allows_bank_tx; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "trg_check_fy_allows_bank_tx" BEFORE INSERT OR UPDATE ON "public"."bank_account_transactions" FOR EACH ROW EXECUTE FUNCTION "public"."check_fiscal_year_allows_financial"();

--
-- Name: cashbox_transactions trg_check_fy_allows_cashbox; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "trg_check_fy_allows_cashbox" BEFORE INSERT OR UPDATE ON "public"."cashbox_transactions" FOR EACH ROW EXECUTE FUNCTION "public"."check_fiscal_year_allows_financial"();

--
-- Name: cheques trg_check_fy_allows_cheque; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "trg_check_fy_allows_cheque" BEFORE INSERT OR UPDATE ON "public"."cheques" FOR EACH ROW EXECUTE FUNCTION "public"."check_fiscal_year_allows_financial"();

--
-- Name: stock_batches trg_check_fy_allows_inventory; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "trg_check_fy_allows_inventory" BEFORE INSERT OR UPDATE ON "public"."stock_batches" FOR EACH ROW EXECUTE FUNCTION "public"."check_fiscal_year_allows_inventory"();

--
-- Name: lot_receipts trg_check_fy_allows_inventory_receipt; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "trg_check_fy_allows_inventory_receipt" BEFORE INSERT OR UPDATE ON "public"."lot_receipts" FOR EACH ROW EXECUTE FUNCTION "public"."check_fiscal_year_allows_inventory"();

--
-- Name: packing_orders trg_check_fy_allows_packing_order; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "trg_check_fy_allows_packing_order" BEFORE INSERT OR UPDATE ON "public"."packing_orders" FOR EACH ROW EXECUTE FUNCTION "public"."check_fiscal_year_allows_inventory"();

--
-- Name: proforma_invoices trg_check_fy_allows_proforma; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "trg_check_fy_allows_proforma" BEFORE INSERT OR UPDATE ON "public"."proforma_invoices" FOR EACH ROW EXECUTE FUNCTION "public"."check_fiscal_year_allows_financial"();

--
-- Name: purchase_invoices trg_check_fy_allows_purchase; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "trg_check_fy_allows_purchase" BEFORE INSERT OR UPDATE ON "public"."purchase_invoices" FOR EACH ROW EXECUTE FUNCTION "public"."check_fiscal_year_allows_financial"();

--
-- Name: station_product_batches trg_check_fy_allows_station_batch; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "trg_check_fy_allows_station_batch" BEFORE INSERT OR UPDATE ON "public"."station_product_batches" FOR EACH ROW EXECUTE FUNCTION "public"."check_fiscal_year_allows_inventory"();

--
-- Name: station_products trg_check_fy_allows_station_product; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "trg_check_fy_allows_station_product" BEFORE INSERT OR UPDATE ON "public"."station_products" FOR EACH ROW EXECUTE FUNCTION "public"."check_fiscal_year_allows_inventory"();

--
-- Name: treasury_transactions trg_check_fy_allows_treasury; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "trg_check_fy_allows_treasury" BEFORE INSERT OR UPDATE ON "public"."treasury_transactions" FOR EACH ROW EXECUTE FUNCTION "public"."check_fiscal_year_allows_financial"();

--
-- Name: cheques trg_cheques_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "trg_cheques_updated_at" BEFORE UPDATE ON "public"."cheques" FOR EACH ROW EXECUTE FUNCTION "public"."update_cheques_updated_at"();

--
-- Name: export_shipments trg_create_profitability_snapshot; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "trg_create_profitability_snapshot" AFTER UPDATE ON "public"."export_shipments" FOR EACH ROW EXECUTE FUNCTION "public"."create_profitability_snapshot_on_close"();

--
-- Name: customers trg_customer_create_account; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "trg_customer_create_account" AFTER INSERT ON "public"."customers" FOR EACH ROW EXECUTE FUNCTION "public"."create_customer_account"();

--
-- Name: customers trg_customer_initial_balance_sync; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "trg_customer_initial_balance_sync" BEFORE INSERT OR UPDATE ON "public"."customers" FOR EACH ROW EXECUTE FUNCTION "public"."sync_customer_balance_on_initial_balance_change"();

--
-- Name: lot_receipts trg_delete_lot_receipt; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "trg_delete_lot_receipt" BEFORE DELETE ON "public"."lot_receipts" FOR EACH ROW EXECUTE FUNCTION "public"."trg_before_delete_lot_receipt"();

--
-- Name: treasuries trg_ensure_main_currencies; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "trg_ensure_main_currencies" AFTER INSERT ON "public"."treasuries" FOR EACH ROW EXECUTE FUNCTION "public"."ensure_main_treasury_currencies"();

--
-- Name: fiscal_years trg_fiscal_years_before_insert; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "trg_fiscal_years_before_insert" BEFORE INSERT ON "public"."fiscal_years" FOR EACH ROW EXECUTE FUNCTION "public"."fiscal_years_before_upsert"();

--
-- Name: fiscal_years trg_fiscal_years_before_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "trg_fiscal_years_before_update" BEFORE UPDATE ON "public"."fiscal_years" FOR EACH ROW EXECUTE FUNCTION "public"."fiscal_years_before_upsert"();

--
-- Name: suppliers trg_supplier_initial_balance_sync; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "trg_supplier_initial_balance_sync" BEFORE INSERT OR UPDATE ON "public"."suppliers" FOR EACH ROW EXECUTE FUNCTION "public"."sync_supplier_outstanding_on_initial_balance_change"();

--
-- Name: purchase_invoices update_purchase_invoices_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "update_purchase_invoices_updated_at" BEFORE UPDATE ON "public"."purchase_invoices" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();

--
-- Name: sales_invoices update_sales_invoices_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "update_sales_invoices_updated_at" BEFORE UPDATE ON "public"."sales_invoices" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();

--
-- Name: treasuries update_treasuries_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "update_treasuries_updated_at" BEFORE UPDATE ON "public"."treasuries" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

--
-- Name: warehouses update_warehouses_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER "update_warehouses_updated_at" BEFORE UPDATE ON "public"."warehouses" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();

-- ==========================================
-- 8. CREATE VIEW & MATERIALIZED VIEW STATEMENTS
-- ==========================================
--
-- Name: export_shipments_view; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW "public"."export_shipments_view" AS
 SELECT "es"."id",
    "es"."shipment_number",
    "es"."customer_id",
    "c"."code" AS "customer_code",
    "c"."name" AS "customer_name",
    "es"."created_at"
   FROM ("public"."export_shipments" "es"
     LEFT JOIN "public"."customers" "c" ON (("es"."customer_id" = "c"."id")));

--
-- Name: invoice_items; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW "public"."invoice_items" AS
 SELECT "id",
    "invoice_id",
    "finished_product_id",
    "batch_id",
    "quantity",
    "unit_price",
    "cost_price",
    "total_price",
    "discount_percent",
    "discount_amount",
    "tax_percent",
    "tax_amount",
    "profit_amount",
    "created_at"
   FROM "public"."sales_invoice_items";

--
-- Name: invoices; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW "public"."invoices" AS
 SELECT "id",
    "invoice_number",
    "invoice_date",
    "customer_id",
    "total_amount",
    "paid_amount",
    "discount_amount",
    "status",
    'sale'::"text" AS "sale_type",
    "notes"
   FROM "public"."sales_invoices";

--
-- Name: latest_fruit_purchase_prices; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW "public"."latest_fruit_purchase_prices" AS
 SELECT "ft"."id" AS "fruit_type_id",
    "ft"."name",
    "ft"."code",
    "latest"."latest_price",
    "latest"."last_purchase_date",
    "avg_stats"."avg_price",
    "avg_stats"."total_purchases",
    "latest"."purchase_mode",
    "latest"."carton_count",
    "latest"."weight_per_carton_kg",
    "latest"."gross_weight_per_carton_kg",
    "latest"."price_per_carton",
    COALESCE("stock"."total_stock_quantity", (0)::double precision) AS "total_stock_quantity",
    COALESCE("stock"."total_stock_value", (0)::double precision) AS "total_stock_value"
   FROM ((("public"."fruit_types" "ft"
     LEFT JOIN LATERAL ( SELECT "lr"."fruit_cost_per_kg" AS "latest_price",
            ("lr"."receipt_date")::"text" AS "last_purchase_date",
            "lr"."purchase_mode",
            "lr"."carton_count",
            ("lr"."weight_per_carton_kg")::double precision AS "weight_per_carton_kg",
            ("lr"."gross_weight_per_carton_kg")::double precision AS "gross_weight_per_carton_kg",
            ("lr"."price_per_carton")::double precision AS "price_per_carton"
           FROM "public"."lot_receipts" "lr"
          WHERE (("lr"."fruit_type_id" = "ft"."id") AND ("lr"."fruit_cost_per_kg" > (0)::double precision))
          ORDER BY "lr"."receipt_date" DESC, "lr"."id" DESC
         LIMIT 1) "latest" ON (true))
     LEFT JOIN LATERAL ( SELECT ("round"(("avg"("lr2"."fruit_cost_per_kg"))::numeric, 2))::double precision AS "avg_price",
            ("count"(*))::integer AS "total_purchases"
           FROM "public"."lot_receipts" "lr2"
          WHERE (("lr2"."fruit_type_id" = "ft"."id") AND ("lr2"."fruit_cost_per_kg" > (0)::double precision))) "avg_stats" ON (true))
     LEFT JOIN LATERAL ( SELECT ("sum"("spb"."remaining_quantity"))::double precision AS "total_stock_quantity",
            "sum"((("spb"."remaining_quantity")::double precision * "spb"."unit_cost")) AS "total_stock_value"
           FROM "public"."station_product_batches" "spb"
          WHERE ("spb"."product_name" = "ft"."name")) "stock" ON (true));

--
-- Name: purchase_items; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW "public"."purchase_items" AS
 SELECT "pii"."id",
    "pii"."invoice_id" AS "purchase_id",
    "pii"."raw_material_id" AS "item_id",
    COALESCE("rm"."code", ''::"text") AS "item_code",
    COALESCE("rm"."name", ''::"text") AS "item_name",
    "pii"."quantity",
    "pii"."unit_cost" AS "purchase_price",
    0 AS "selling_price",
    "pii"."total_cost" AS "total_price",
    COALESCE("rm"."unit", 'كجم'::"text") AS "unit",
    0 AS "pieces_count"
   FROM ("public"."purchase_invoice_items" "pii"
     LEFT JOIN "public"."raw_materials" "rm" ON (("rm"."id" = "pii"."raw_material_id")));

--
-- Name: purchases; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW "public"."purchases" AS
 SELECT "pi"."id",
    "pi"."invoice_number",
    "pi"."supplier_id",
    "pi"."warehouse_id",
    "pi"."currency_id",
    "pi"."invoice_date",
    "pi"."due_date",
    "pi"."subtotal",
    "pi"."discount_amount",
    "pi"."tax_percent",
    "pi"."tax_amount",
    "pi"."total_amount",
    "pi"."paid_amount",
    "pi"."remaining_amount",
    "pi"."payment_status",
    "pi"."status",
    "pi"."received_date",
    "pi"."notes",
    "pi"."created_at",
    "pi"."updated_at",
    "pi"."user_id",
    "s"."name" AS "supplier_name",
    "s"."supplier_code"
   FROM ("public"."purchase_invoices" "pi"
     LEFT JOIN "public"."suppliers" "s" ON (("s"."id" = "pi"."supplier_id")));

--
-- Name: treasury_with_users; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW "public"."treasury_with_users" AS
 SELECT "t"."id",
    "t"."name",
    "t"."type",
    "t"."employee_id",
    "t"."is_active",
    "t"."created_at",
    "t"."updated_at",
    "t"."user_id",
    "t"."notes",
    "u"."email",
    COALESCE(("u"."raw_user_meta_data" ->> 'full_name'::"text"), ("u"."raw_user_meta_data" ->> 'name'::"text"), 'غير مسمى'::"text") AS "full_name",
    ("u"."raw_user_meta_data" ->> 'phone'::"text") AS "phone"
   FROM ("public"."treasuries" "t"
     LEFT JOIN "auth"."users" "u" ON ((("t"."employee_id" = "u"."id") OR ("t"."user_id" = "u"."id"))));

--
-- Name: v_shareholders; Type: VIEW; Schema: public; Owner: postgres
--

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
    ((
        CASE
            WHEN (COALESCE("initial_balance_egp", (0)::numeric) > (0)::numeric) THEN COALESCE("initial_balance_egp", (0)::numeric)
            ELSE (0)::numeric
        END + COALESCE(( SELECT "sum"("treasury_transactions"."amount") AS "sum"
           FROM "public"."treasury_transactions"
          WHERE (("treasury_transactions"."type" = 'deposit'::"text") AND ("treasury_transactions"."currency" = 'EGP'::"text") AND ("treasury_transactions"."shareholder_id" = "s"."id"))), (0)::numeric)) + COALESCE(( SELECT "sum"("bat"."amount") AS "sum"
           FROM ("public"."bank_account_transactions" "bat"
             JOIN "public"."bank_accounts" "ba" ON (("ba"."id" = "bat"."bank_account_id")))
          WHERE (("bat"."type" = 'deposit'::"text") AND ("bat"."entity_type" = 'shareholder'::"text") AND ("bat"."entity_id" = ("s"."id")::"text") AND ("ba"."currency" = 'EGP'::"text"))), (0)::numeric)) AS "total_deposits_egp",
    ((
        CASE
            WHEN (COALESCE("initial_balance_egp", (0)::numeric) < (0)::numeric) THEN "abs"(COALESCE("initial_balance_egp", (0)::numeric))
            ELSE (0)::numeric
        END + COALESCE(( SELECT "sum"("treasury_transactions"."amount") AS "sum"
           FROM "public"."treasury_transactions"
          WHERE (("treasury_transactions"."type" = 'expense'::"text") AND ("treasury_transactions"."currency" = 'EGP'::"text") AND ("treasury_transactions"."shareholder_id" = "s"."id"))), (0)::numeric)) + COALESCE(( SELECT "sum"("bat"."amount") AS "sum"
           FROM ("public"."bank_account_transactions" "bat"
             JOIN "public"."bank_accounts" "ba" ON (("ba"."id" = "bat"."bank_account_id")))
          WHERE (("bat"."type" = 'withdraw'::"text") AND ("bat"."entity_type" = 'shareholder'::"text") AND ("bat"."entity_id" = ("s"."id")::"text") AND ("ba"."currency" = 'EGP'::"text"))), (0)::numeric)) AS "total_withdrawals_egp",
    ((
        CASE
            WHEN (COALESCE("initial_balance_usd", (0)::numeric) > (0)::numeric) THEN COALESCE("initial_balance_usd", (0)::numeric)
            ELSE (0)::numeric
        END + COALESCE(( SELECT "sum"("treasury_transactions"."amount") AS "sum"
           FROM "public"."treasury_transactions"
          WHERE (("treasury_transactions"."type" = 'deposit'::"text") AND ("treasury_transactions"."currency" = 'USD'::"text") AND ("treasury_transactions"."shareholder_id" = "s"."id"))), (0)::numeric)) + COALESCE(( SELECT "sum"("bat"."amount") AS "sum"
           FROM ("public"."bank_account_transactions" "bat"
             JOIN "public"."bank_accounts" "ba" ON (("ba"."id" = "bat"."bank_account_id")))
          WHERE (("bat"."type" = 'deposit'::"text") AND ("bat"."entity_type" = 'shareholder'::"text") AND ("bat"."entity_id" = ("s"."id")::"text") AND ("ba"."currency" = 'USD'::"text"))), (0)::numeric)) AS "total_deposits_usd",
    ((
        CASE
            WHEN (COALESCE("initial_balance_usd", (0)::numeric) < (0)::numeric) THEN "abs"(COALESCE("initial_balance_usd", (0)::numeric))
            ELSE (0)::numeric
        END + COALESCE(( SELECT "sum"("treasury_transactions"."amount") AS "sum"
           FROM "public"."treasury_transactions"
          WHERE (("treasury_transactions"."type" = 'expense'::"text") AND ("treasury_transactions"."currency" = 'USD'::"text") AND ("treasury_transactions"."shareholder_id" = "s"."id"))), (0)::numeric)) + COALESCE(( SELECT "sum"("bat"."amount") AS "sum"
           FROM ("public"."bank_account_transactions" "bat"
             JOIN "public"."bank_accounts" "ba" ON (("ba"."id" = "bat"."bank_account_id")))
          WHERE (("bat"."type" = 'withdraw'::"text") AND ("bat"."entity_type" = 'shareholder'::"text") AND ("bat"."entity_id" = ("s"."id")::"text") AND ("ba"."currency" = 'USD'::"text"))), (0)::numeric)) AS "total_withdrawals_usd",
    ((
        CASE
            WHEN (COALESCE("initial_balance_eur", (0)::numeric) > (0)::numeric) THEN COALESCE("initial_balance_eur", (0)::numeric)
            ELSE (0)::numeric
        END + COALESCE(( SELECT "sum"("treasury_transactions"."amount") AS "sum"
           FROM "public"."treasury_transactions"
          WHERE (("treasury_transactions"."type" = 'deposit'::"text") AND ("treasury_transactions"."currency" = 'EUR'::"text") AND ("treasury_transactions"."shareholder_id" = "s"."id"))), (0)::numeric)) + COALESCE(( SELECT "sum"("bat"."amount") AS "sum"
           FROM ("public"."bank_account_transactions" "bat"
             JOIN "public"."bank_accounts" "ba" ON (("ba"."id" = "bat"."bank_account_id")))
          WHERE (("bat"."type" = 'deposit'::"text") AND ("bat"."entity_type" = 'shareholder'::"text") AND ("bat"."entity_id" = ("s"."id")::"text") AND ("ba"."currency" = 'EUR'::"text"))), (0)::numeric)) AS "total_deposits_eur",
    ((
        CASE
            WHEN (COALESCE("initial_balance_eur", (0)::numeric) < (0)::numeric) THEN "abs"(COALESCE("initial_balance_eur", (0)::numeric))
            ELSE (0)::numeric
        END + COALESCE(( SELECT "sum"("treasury_transactions"."amount") AS "sum"
           FROM "public"."treasury_transactions"
          WHERE (("treasury_transactions"."type" = 'expense'::"text") AND ("treasury_transactions"."currency" = 'EUR'::"text") AND ("treasury_transactions"."shareholder_id" = "s"."id"))), (0)::numeric)) + COALESCE(( SELECT "sum"("bat"."amount") AS "sum"
           FROM ("public"."bank_account_transactions" "bat"
             JOIN "public"."bank_accounts" "ba" ON (("ba"."id" = "bat"."bank_account_id")))
          WHERE (("bat"."type" = 'withdraw'::"text") AND ("bat"."entity_type" = 'shareholder'::"text") AND ("bat"."entity_id" = ("s"."id")::"text") AND ("ba"."currency" = 'EUR'::"text"))), (0)::numeric)) AS "total_withdrawals_eur",
    ((
        CASE
            WHEN (COALESCE("initial_balance_gbp", (0)::numeric) > (0)::numeric) THEN COALESCE("initial_balance_gbp", (0)::numeric)
            ELSE (0)::numeric
        END + COALESCE(( SELECT "sum"("treasury_transactions"."amount") AS "sum"
           FROM "public"."treasury_transactions"
          WHERE (("treasury_transactions"."type" = 'deposit'::"text") AND ("treasury_transactions"."currency" = 'GBP'::"text") AND ("treasury_transactions"."shareholder_id" = "s"."id"))), (0)::numeric)) + COALESCE(( SELECT "sum"("bat"."amount") AS "sum"
           FROM ("public"."bank_account_transactions" "bat"
             JOIN "public"."bank_accounts" "ba" ON (("ba"."id" = "bat"."bank_account_id")))
          WHERE (("bat"."type" = 'deposit'::"text") AND ("bat"."entity_type" = 'shareholder'::"text") AND ("bat"."entity_id" = ("s"."id")::"text") AND ("ba"."currency" = 'GBP'::"text"))), (0)::numeric)) AS "total_deposits_gbp",
    ((
        CASE
            WHEN (COALESCE("initial_balance_gbp", (0)::numeric) < (0)::numeric) THEN "abs"(COALESCE("initial_balance_gbp", (0)::numeric))
            ELSE (0)::numeric
        END + COALESCE(( SELECT "sum"("treasury_transactions"."amount") AS "sum"
           FROM "public"."treasury_transactions"
          WHERE (("treasury_transactions"."type" = 'expense'::"text") AND ("treasury_transactions"."currency" = 'GBP'::"text") AND ("treasury_transactions"."shareholder_id" = "s"."id"))), (0)::numeric)) + COALESCE(( SELECT "sum"("bat"."amount") AS "sum"
           FROM ("public"."bank_account_transactions" "bat"
             JOIN "public"."bank_accounts" "ba" ON (("ba"."id" = "bat"."bank_account_id")))
          WHERE (("bat"."type" = 'withdraw'::"text") AND ("bat"."entity_type" = 'shareholder'::"text") AND ("bat"."entity_id" = ("s"."id")::"text") AND ("ba"."currency" = 'GBP'::"text"))), (0)::numeric)) AS "total_withdrawals_gbp"
   FROM "public"."shareholders" "s";

--
-- Name: vw_cost_details_live; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW "public"."vw_cost_details_live" AS
 SELECT ("l"."receipt_date")::"text" AS "shipment_date",
    ( SELECT "string_agg"(DISTINCT ("s"."shipment_no")::"text", ', '::"text") AS "string_agg"
           FROM ("public"."packing_orders" "po"
             JOIN "public"."export_shipments" "s" ON (("s"."id" = "po"."export_shipment_id")))
          WHERE ("po"."lot_id" = "l"."id")) AS "shipment_no",
    ( SELECT "string_agg"(DISTINCT "s"."customer_name", ', '::"text") AS "string_agg"
           FROM ("public"."packing_orders" "po"
             JOIN "public"."export_shipments" "s" ON (("s"."id" = "po"."export_shipment_id")))
          WHERE ("po"."lot_id" = "l"."id")) AS "customer_name",
    'crop'::"text" AS "category",
    COALESCE("l"."product_name", 'محصول'::"text") AS "item_name",
    "l"."gross_weight_kg" AS "quantity",
    "round"(((("l"."total_fruit_cost" / (NULLIF("l"."gross_weight_kg", (0)::numeric))::double precision) * (COALESCE("l"."exchange_rate", 1.0))::double precision))::numeric, 2) AS "unit_price",
    "round"((("l"."total_fruit_cost" * (COALESCE("l"."exchange_rate", 1.0))::double precision))::numeric, 2) AS "amount",
    COALESCE("l"."currency", ( SELECT "suppliers"."currency"
           FROM "public"."suppliers"
          WHERE ("suppliers"."id" = "l"."supplier_id")), 'EGP'::"text") AS "currency",
    COALESCE("l"."exchange_rate", 1.0) AS "exchange_rate",
    "round"(("l"."total_fruit_cost")::numeric, 2) AS "total_in_currency",
    "l"."notes",
    ( SELECT "min"("po"."export_shipment_id") AS "min"
           FROM "public"."packing_orders" "po"
          WHERE ("po"."lot_id" = "l"."id")) AS "shipment_id"
   FROM "public"."lot_receipts" "l"
  WHERE ("l"."is_confirmed" = true)
UNION ALL
 SELECT (("r"."created_at")::"date")::"text" AS "shipment_date",
    ( SELECT "string_agg"(DISTINCT ("s"."shipment_no")::"text", ', '::"text") AS "string_agg"
           FROM ("public"."packing_orders" "po"
             JOIN "public"."export_shipments" "s" ON (("s"."id" = "po"."export_shipment_id")))
          WHERE ("po"."lot_id" = "l"."id")) AS "shipment_no",
    ( SELECT "string_agg"(DISTINCT "s"."customer_name", ', '::"text") AS "string_agg"
           FROM ("public"."packing_orders" "po"
             JOIN "public"."export_shipments" "s" ON (("s"."id" = "po"."export_shipment_id")))
          WHERE ("po"."lot_id" = "l"."id")) AS "customer_name",
    'crop'::"text" AS "category",
    ('مرتجع '::"text" || COALESCE("l"."product_name", 'محصول'::"text")) AS "item_name",
    (- "r"."returned_quantity") AS "quantity",
    "round"((("r"."return_value" / NULLIF("r"."returned_quantity", (0)::numeric)) * COALESCE("l"."exchange_rate", 1.0)), 2) AS "unit_price",
    "round"((- ("r"."return_value" * COALESCE("l"."exchange_rate", 1.0))), 2) AS "amount",
    COALESCE("l"."currency", ( SELECT "suppliers"."currency"
           FROM "public"."suppliers"
          WHERE ("suppliers"."id" = "l"."supplier_id")), 'EGP'::"text") AS "currency",
    COALESCE("l"."exchange_rate", 1.0) AS "exchange_rate",
    "round"((- ("r"."return_value")::numeric), 2) AS "total_in_currency",
    "r"."notes",
    ( SELECT "min"("po"."export_shipment_id") AS "min"
           FROM "public"."packing_orders" "po"
          WHERE ("po"."lot_id" = "l"."id")) AS "shipment_id"
   FROM ("public"."lot_returns" "r"
     JOIN "public"."lot_receipts" "l" ON (("l"."id" = "r"."lot_receipt_id")))
UNION ALL
 SELECT ((COALESCE("po"."packed_at", "po"."created_at"))::"date")::"text" AS "shipment_date",
    "s"."shipment_no",
    "s"."customer_name",
    'packing_material'::"text" AS "category",
    COALESCE(("mat"."m" ->> 'product_name'::"text"), 'مادة تعبئة'::"text") AS "item_name",
    (("mat"."m" ->> 'used_qty'::"text"))::numeric AS "quantity",
    "round"((((("mat"."m" ->> 'total'::"text"))::numeric / NULLIF(COALESCE((("mat"."m" ->> 'exchange_rate'::"text"))::numeric, 1.0), (0)::numeric)) / NULLIF((("mat"."m" ->> 'used_qty'::"text"))::numeric, (0)::numeric)), 2) AS "unit_price",
    "round"((("mat"."m" ->> 'total'::"text"))::numeric, 2) AS "amount",
    COALESCE(("mat"."m" ->> 'currency'::"text"), 'EGP'::"text") AS "currency",
    COALESCE((("mat"."m" ->> 'exchange_rate'::"text"))::numeric, 1.0) AS "exchange_rate",
    "round"(((("mat"."m" ->> 'total'::"text"))::numeric / NULLIF(COALESCE((("mat"."m" ->> 'exchange_rate'::"text"))::numeric, 1.0), (0)::numeric)), 2) AS "total_in_currency",
    "po"."notes",
    "s"."id" AS "shipment_id"
   FROM (("public"."packing_orders" "po"
     LEFT JOIN "public"."export_shipments" "s" ON (("s"."id" = "po"."export_shipment_id")))
     CROSS JOIN LATERAL ( SELECT "jsonb_array_elements"(COALESCE((("po"."notes")::"jsonb" -> 'materials'::"text"), '[]'::"jsonb")) AS "m") "mat")
  WHERE (((("mat"."m" ->> 'total'::"text"))::numeric > (0)::numeric) AND ("po"."status" = 'completed'::"text"))
UNION ALL
 SELECT ((COALESCE("po"."packed_at", "po"."created_at"))::"date")::"text" AS "shipment_date",
    "s"."shipment_no",
    "s"."customer_name",
    COALESCE(("cit"."c" ->> 'category'::"text"), 'other'::"text") AS "category",
    COALESCE(("cit"."c" ->> 'name'::"text"), 'بند تكلفة'::"text") AS "item_name",
    (("cit"."c" ->> 'quantity'::"text"))::numeric AS "quantity",
    "round"((((("cit"."c" ->> 'total'::"text"))::numeric / NULLIF(COALESCE((("cit"."c" ->> 'exchange_rate'::"text"))::numeric, 1.0), (0)::numeric)) / NULLIF((("cit"."c" ->> 'quantity'::"text"))::numeric, (0)::numeric)), 2) AS "unit_price",
    "round"((("cit"."c" ->> 'total'::"text"))::numeric, 2) AS "amount",
    COALESCE(("cit"."c" ->> 'supplier_currency'::"text"), ("cit"."c" ->> 'currency'::"text"), 'EGP'::"text") AS "currency",
    COALESCE((("cit"."c" ->> 'exchange_rate'::"text"))::numeric, 1.0) AS "exchange_rate",
    "round"(((("cit"."c" ->> 'total'::"text"))::numeric / NULLIF(COALESCE((("cit"."c" ->> 'exchange_rate'::"text"))::numeric, 1.0), (0)::numeric)), 2) AS "total_in_currency",
    "po"."notes",
    "s"."id" AS "shipment_id"
   FROM (("public"."packing_orders" "po"
     LEFT JOIN "public"."export_shipments" "s" ON (("s"."id" = "po"."export_shipment_id")))
     CROSS JOIN LATERAL ( SELECT "jsonb_array_elements"(COALESCE((("po"."notes")::"jsonb" -> 'cost_items'::"text"), '[]'::"jsonb")) AS "c") "cit")
  WHERE (((("cit"."c" ->> 'total'::"text"))::numeric > (0)::numeric) AND ("po"."status" = ANY (ARRAY['completed'::"text", 'cancelled'::"text"])))
UNION ALL
 SELECT ("s"."shipment_date")::"text" AS "shipment_date",
    "s"."shipment_no",
    "s"."customer_name",
    "sci"."category",
    "sci"."description" AS "item_name",
    "sci"."quantity",
    "sci"."unit_price",
    "sci"."total_price" AS "amount",
    'EGP'::"text" AS "currency",
    COALESCE("sci"."exchange_rate", 1.0) AS "exchange_rate",
    "round"(("sci"."total_price" / NULLIF(COALESCE("sci"."exchange_rate", 1.0), (0)::numeric)), 2) AS "total_in_currency",
    "sci"."description" AS "notes",
    "s"."id" AS "shipment_id"
   FROM ("public"."shipment_cost_items" "sci"
     JOIN "public"."export_shipments" "s" ON (("s"."id" = "sci"."shipment_id")))
  WHERE (("sci"."category" <> ALL (ARRAY['crop'::"text", 'packing'::"text"])) AND (NOT (("sci"."category" = 'other'::"text") AND ("sci"."description" ~~ 'محصول%'::"text"))))
UNION ALL
 SELECT ("s"."shipment_date")::"text" AS "shipment_date",
    "s"."shipment_no",
    "s"."customer_name",
    "pci"."cost_type" AS "category",
    "pci"."description" AS "item_name",
    "pci"."qty" AS "quantity",
    "pci"."unit_price",
    "pci"."total_cost" AS "amount",
    'EGP'::"text" AS "currency",
    1.0 AS "exchange_rate",
    "pci"."total_cost" AS "total_in_currency",
    "pci"."notes",
    "pci"."shipment_id"
   FROM ("public"."prep_center_cost_items" "pci"
     JOIN "public"."export_shipments" "s" ON (("s"."id" = "pci"."shipment_id")))
UNION ALL
 SELECT ("gci"."cost_date")::"text" AS "shipment_date",
    NULL::"text" AS "shipment_no",
    NULL::"text" AS "customer_name",
    'general'::"text" AS "category",
    "gci"."name" AS "item_name",
    1 AS "quantity",
    "gci"."amount" AS "unit_price",
    "gci"."amount",
    'EGP'::"text" AS "currency",
    1.0 AS "exchange_rate",
    "gci"."amount" AS "total_in_currency",
    NULL::"text" AS "notes",
    NULL::integer AS "shipment_id"
   FROM "public"."general_cost_items" "gci";

-- ==========================================
-- 9. VIEW-DEPENDENT FUNCTIONS
-- ==========================================
--
-- Name: verify_database(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION "public"."verify_database"() RETURNS TABLE("test_id" integer, "test_name" "text", "passed" boolean, "details" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
DECLARE
  v_count BIGINT;
  v_count2 BIGINT;
  v_pass BOOLEAN;
  v_detail TEXT;
  v_def TEXT;
  r RECORD;
BEGIN

  -- ============================================================================
  -- SECTION A: SCHEMA INTEGRITY (Tests 1-12)
  -- ============================================================================

  -- 1. CRITICAL FUNCTIONS EXIST
  v_pass := TRUE; v_detail := '';
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_confirm_purchase') THEN
    v_pass := FALSE; v_detail := v_detail || 'rpc_confirm_purchase MISSING; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_cancel_purchase') THEN
    v_pass := FALSE; v_detail := v_detail || 'rpc_cancel_purchase MISSING; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'create_balanced_entry') THEN
    v_pass := FALSE; v_detail := v_detail || 'create_balanced_entry MISSING; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_account_totals_rpc') THEN
    v_pass := FALSE; v_detail := v_detail || 'get_account_totals_rpc MISSING; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_cancel_export_shipment') THEN
    v_pass := FALSE; v_detail := v_detail || 'rpc_cancel_export_shipment MISSING; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'rpc_process_export_shipment_ledger') THEN
    v_pass := FALSE; v_detail := v_detail || 'rpc_process_export_shipment_ledger MISSING; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_balance_before_date_rpc') THEN
    v_pass := FALSE; v_detail := v_detail || 'get_balance_before_date_rpc MISSING; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_account_total_by_id_rpc') THEN
    v_pass := FALSE; v_detail := v_detail || 'get_account_total_by_id_rpc MISSING; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'get_latest_exchange_rates_rpc') THEN
    v_pass := FALSE; v_detail := v_detail || 'get_latest_exchange_rates_rpc MISSING; '; END IF;
  IF v_pass THEN v_detail := 'All 9 critical functions exist'; END IF;
  test_id := 1; test_name := 'Critical Functions Exist'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 2. SECURITY DEFINER on critical functions
  v_pass := TRUE; v_detail := '';
  FOR r IN
    SELECT p.proname FROM pg_proc p
    WHERE p.proname IN ('rpc_confirm_purchase','rpc_cancel_purchase','create_balanced_entry',
                         'get_account_totals_rpc','rpc_cancel_export_shipment')
  LOOP
    v_def := (SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname = r.proname LIMIT 1);
    IF v_def NOT LIKE '%SECURITY DEFINER%' THEN
      v_pass := FALSE; v_detail := v_detail || r.proname || ' missing SEC DEF; ';
    END IF;
  END LOOP;
  IF v_pass THEN v_detail := 'All checked functions have SECURITY DEFINER'; END IF;
  test_id := 2; test_name := 'SECURITY DEFINER Present'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 3. search_path set on critical functions
  v_pass := TRUE; v_detail := '';
  FOR r IN
    SELECT p.proname FROM pg_proc p
    WHERE p.proname IN ('rpc_confirm_purchase','rpc_cancel_purchase','create_balanced_entry',
                         'get_account_totals_rpc','rpc_cancel_export_shipment')
  LOOP
    v_def := (SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname = r.proname LIMIT 1);
    IF v_def NOT LIKE '%search_path%' THEN
      v_pass := FALSE; v_detail := v_detail || r.proname || ' missing search_path; ';
    END IF;
  END LOOP;
  IF v_pass THEN v_detail := 'All checked functions have search_path'; END IF;
  test_id := 3; test_name := 'search_path Set'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 4. NO DUPLICATE OVERLOADS
  v_pass := TRUE; v_detail := '';
  FOR r IN
    SELECT proname, COUNT(*) AS cnt FROM pg_proc
    WHERE proname IN ('rpc_confirm_purchase','rpc_cancel_purchase','create_balanced_entry')
    GROUP BY proname HAVING COUNT(*) > 1
  LOOP
    v_pass := FALSE; v_detail := v_detail || r.proname || ' has ' || r.cnt || ' overloads; ';
  END LOOP;
  IF v_pass THEN v_detail := 'No duplicate overloads'; END IF;
  test_id := 4; test_name := 'No Duplicate Overloads'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 5. GRANT EXECUTE to authenticated
  v_pass := TRUE; v_detail := '';
  FOR r IN
    SELECT proname FROM pg_proc WHERE proname IN (
      'rpc_confirm_purchase','rpc_cancel_purchase','create_balanced_entry',
      'get_account_totals_rpc','rpc_cancel_export_shipment',
      'rpc_process_export_shipment_ledger','get_balance_before_date_rpc',
      'get_account_total_by_id_rpc','get_latest_exchange_rates_rpc'
    )
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_proc p WHERE p.proname = r.proname
        AND p.proacl IS NOT NULL
        AND EXISTS (SELECT 1 FROM unnest(p.proacl) a WHERE a::TEXT LIKE '%authenticated%')
    ) THEN
      v_pass := FALSE; v_detail := v_detail || r.proname || ' missing GRANT; ';
    END IF;
  END LOOP;
  IF v_pass THEN v_detail := 'GRANTs verified for all critical RPCs'; END IF;
  test_id := 5; test_name := 'GRANT EXECUTE to authenticated'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 6. accounts.id TYPE = INTEGER
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM information_schema.columns
  WHERE table_name = 'accounts' AND column_name = 'id' AND data_type IN ('uuid','UUID');
  IF v_count > 0 THEN v_pass := FALSE; v_detail := 'accounts.id is UUID (expected INTEGER)'; ELSE v_detail := 'accounts.id is INTEGER'; END IF;
  test_id := 6; test_name := 'accounts.id Type = INTEGER'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 7. purchase_invoices.id TYPE = INTEGER
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM information_schema.columns
  WHERE table_name = 'purchase_invoices' AND column_name = 'id' AND data_type IN ('uuid','UUID');
  IF v_count > 0 THEN v_pass := FALSE; v_detail := 'purchase_invoices.id is UUID (expected INTEGER)'; ELSE v_detail := 'purchase_invoices.id is INTEGER'; END IF;
  test_id := 7; test_name := 'purchase_invoices.id Type = INTEGER'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 8. customers.id TYPE = UUID
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM information_schema.columns
  WHERE table_name = 'customers' AND column_name = 'id' AND data_type NOT IN ('uuid','UUID');
  IF v_count > 0 THEN v_pass := FALSE; v_detail := 'customers.id is not UUID'; ELSE v_detail := 'customers.id is UUID'; END IF;
  test_id := 8; test_name := 'customers.id Type = UUID'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 9. suppliers.id TYPE = UUID
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM information_schema.columns
  WHERE table_name = 'suppliers' AND column_name = 'id' AND data_type NOT IN ('uuid','UUID');
  IF v_count > 0 THEN v_pass := FALSE; v_detail := 'suppliers.id is not UUID'; ELSE v_detail := 'suppliers.id is UUID'; END IF;
  test_id := 9; test_name := 'suppliers.id Type = UUID'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 10. stock_batches.supplier_id TYPE = UUID (must match suppliers.id)
  v_pass := TRUE;
  SELECT data_type INTO v_detail FROM information_schema.columns
  WHERE table_name = 'stock_batches' AND column_name = 'supplier_id' AND table_schema = 'public';
  IF v_detail != 'uuid' THEN v_pass := FALSE; v_detail := 'stock_batches.supplier_id is ' || v_detail || ' (expected UUID)'; END IF;
  IF v_pass THEN v_detail := 'stock_batches.supplier_id is UUID'; END IF;
  test_id := 10; test_name := 'stock_batches.supplier_id = UUID'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 11. cash_payments.supplier_id TYPE = UUID
  v_pass := TRUE;
  SELECT data_type INTO v_detail FROM information_schema.columns
  WHERE table_name = 'cash_payments' AND column_name = 'supplier_id' AND table_schema = 'public';
  IF v_detail != 'uuid' THEN v_pass := FALSE; v_detail := 'cash_payments.supplier_id is ' || v_detail || ' (expected UUID)'; END IF;
  IF v_pass THEN v_detail := 'cash_payments.supplier_id is UUID'; END IF;
  test_id := 11; test_name := 'cash_payments.supplier_id = UUID'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 12. stock_batches.purchase_invoice_id TYPE = INTEGER
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM information_schema.columns
  WHERE table_name = 'stock_batches' AND column_name = 'purchase_invoice_id' AND data_type IN ('uuid','UUID');
  IF v_count > 0 THEN v_pass := FALSE; v_detail := 'purchase_invoice_id is UUID (expected INTEGER)'; ELSE v_detail := 'stock_batches.purchase_invoice_id is INTEGER'; END IF;
  test_id := 12; test_name := 'purchase_invoice_id = INTEGER'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- ============================================================================
  -- SECTION B: REFERENTIAL INTEGRITY (Tests 13-22)
  -- ============================================================================

  -- 13. FK: purchase_invoice_items -> purchase_invoices
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM purchase_invoice_items pii
  WHERE NOT EXISTS (SELECT 1 FROM purchase_invoices pi WHERE pi.id = pii.invoice_id);
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' orphans'; ELSE v_detail := 'OK'; END IF;
  test_id := 13; test_name := 'FK: purchase_invoice_items->purchase_invoices'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 14. FK: export_shipment_items -> export_shipments
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM export_shipment_items esi
  WHERE NOT EXISTS (SELECT 1 FROM export_shipments es WHERE es.id = esi.shipment_id);
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' orphans'; ELSE v_detail := 'OK'; END IF;
  test_id := 14; test_name := 'FK: export_shipment_items->export_shipments'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 15. FK: sales_invoice_items -> sales_invoices
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM sales_invoice_items sii
  WHERE NOT EXISTS (SELECT 1 FROM sales_invoices si WHERE si.id = sii.invoice_id);
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' orphans'; ELSE v_detail := 'OK'; END IF;
  test_id := 15; test_name := 'FK: sales_invoice_items->sales_invoices'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 16. FK: packing_order_sortings -> packing_orders
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM packing_order_sortings pos
  WHERE NOT EXISTS (SELECT 1 FROM packing_orders po WHERE po.id = pos.packing_order_id);
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' orphans'; ELSE v_detail := 'OK'; END IF;
  test_id := 16; test_name := 'FK: packing_order_sortings->packing_orders'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 17. FK: packing_order_cost_items -> packing_orders
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM packing_order_cost_items poci
  WHERE NOT EXISTS (SELECT 1 FROM packing_orders po WHERE po.id = poci.packing_order_id);
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' orphans'; ELSE v_detail := 'OK'; END IF;
  test_id := 17; test_name := 'FK: packing_order_cost_items->packing_orders'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 18. FK: lot_grading_results -> lot_receipts
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM lot_grading_results lgr
  WHERE NOT EXISTS (SELECT 1 FROM lot_receipts lr WHERE lr.id = lgr.lot_id);
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' orphans'; ELSE v_detail := 'OK'; END IF;
  test_id := 18; test_name := 'FK: lot_grading_results->lot_receipts'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 19. FK: transactions -> accounts
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM transactions t
  WHERE NOT EXISTS (SELECT 1 FROM accounts a WHERE a.id = t.account_id);
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' orphans'; ELSE v_detail := 'OK'; END IF;
  test_id := 19; test_name := 'FK: transactions->accounts'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 20. FK: ledger_entries -> customers
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM ledger_entries le
  WHERE le.entity_type = 'customer'
    AND NOT EXISTS (SELECT 1 FROM customers c WHERE c.id::TEXT = le.entity_id);
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' orphans'; ELSE v_detail := 'OK'; END IF;
  test_id := 20; test_name := 'FK: ledger_entries->customers'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 21. No NULL invoice_id in purchase_invoice_items
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM purchase_invoice_items WHERE invoice_id IS NULL;
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' items with NULL invoice_id'; ELSE v_detail := 'All items have invoice_id'; END IF;
  test_id := 21; test_name := 'No NULL invoice_id'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 22. purchase_invoices has payment columns
  v_pass := TRUE; v_detail := '';
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='purchase_invoices' AND column_name='payment_treasury_id') THEN
    v_pass := FALSE; v_detail := v_detail || 'payment_treasury_id MISSING; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='purchase_invoices' AND column_name='payment_source_type') THEN
    v_pass := FALSE; v_detail := v_detail || 'payment_source_type MISSING; '; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='purchase_invoices' AND column_name='payment_bank_account_id') THEN
    v_pass := FALSE; v_detail := v_detail || 'payment_bank_account_id MISSING; '; END IF;
  IF v_pass THEN v_detail := 'All payment columns present'; END IF;
  test_id := 22; test_name := 'Purchase Payment Columns'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- ============================================================================
  -- SECTION C: FINANCIAL INTEGRITY (Tests 23-35)
  -- ============================================================================

  -- 23. Trial Balance = 0
  v_pass := TRUE;
  SELECT COALESCE(SUM(debit - credit), 0) INTO v_count FROM transactions;
  IF v_count != 0 THEN v_pass := FALSE; v_detail := 'Difference: ' || v_count; ELSE v_detail := 'Balanced (sum = 0)'; END IF;
  test_id := 23; test_name := 'Trial Balance = 0'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 24. General Ledger Balanced
  v_pass := TRUE;
  SELECT COALESCE(SUM(debit), 0) INTO v_count FROM transactions;
  SELECT COALESCE(SUM(credit), 0) INTO v_count2 FROM transactions;
  IF v_count != v_count2 THEN
    v_pass := FALSE; v_detail := 'Debits=' || v_count || ' Credits=' || v_count2;
  ELSE
    v_detail := 'GL balanced: debits=' || v_count || ' credits=' || v_count2;
  END IF;
  test_id := 24; test_name := 'General Ledger Balanced'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 25. No Empty Journal Entries
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM transactions WHERE debit = 0 AND credit = 0;
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' empty entries'; ELSE v_detail := 'No empty entries'; END IF;
  test_id := 25; test_name := 'No Empty Journal Entries'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 26. No Negative Debit/Credit
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM transactions WHERE debit < 0 OR credit < 0;
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' negative entries'; ELSE v_detail := 'All non-negative'; END IF;
  test_id := 26; test_name := 'No Negative Debit/Credit'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 27. Ledger Entries Positive Amounts
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM ledger_entries WHERE amount <= 0;
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' non-positive'; ELSE v_detail := 'All positive'; END IF;
  test_id := 27; test_name := 'Ledger Entries Positive'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 28. Customer Balance vs Ledger
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM customers c
  WHERE c.balance != 0 AND NOT EXISTS (
    SELECT 1 FROM ledger_entries le WHERE le.entity_type = 'customer' AND le.entity_id = c.id::TEXT
  );
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' customers with balance but no ledger'; ELSE v_detail := 'Consistent'; END IF;
  test_id := 28; test_name := 'Customer Balance vs Ledger'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 29. Treasury Amounts Non-Negative
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM treasury_transactions WHERE amount < 0;
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' negative treasury amounts'; ELSE v_detail := 'All non-negative'; END IF;
  test_id := 29; test_name := 'Treasury Amounts Non-Negative'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 30. No Treasury Transactions Without Journal
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM treasury_transactions tt
  WHERE tt.type = 'expense' AND tt.amount > 0
    AND NOT EXISTS (
      SELECT 1 FROM transactions t
      WHERE t.description LIKE '%' || COALESCE(tt.description, '') || '%'
        AND t.debit > 0
    );
  IF v_count > 0 THEN v_detail := v_count || ' treasury txs without matching journal (soft check)'; ELSE v_detail := 'All treasury txs have journal entries'; END IF;
  test_id := 30; test_name := 'Treasury vs Journal (soft)'; passed := TRUE; details := v_detail;
  RETURN NEXT;

  -- 31. Supplier Outstanding Balance Consistency
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM suppliers s
  WHERE s.outstanding_balance != 0 AND NOT EXISTS (
    SELECT 1 FROM purchase_invoices pi
    WHERE pi.supplier_id = s.id AND pi.status = 'confirmed'
  );
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' suppliers with balance but no confirmed purchases'; ELSE v_detail := 'Consistent'; END IF;
  test_id := 31; test_name := 'Supplier Balance Consistency'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 32. Key Views Exist
  v_pass := TRUE; v_detail := '';
  FOR r IN SELECT table_name FROM information_schema.views WHERE table_schema = 'public'
    AND table_name IN ('invoices','invoice_items','purchases','purchase_items','cashbox')
  LOOP
    v_detail := v_detail || r.table_name || ' OK; ';
  END LOOP;
  IF v_detail = '' THEN v_pass := FALSE; v_detail := 'No views found'; END IF;
  test_id := 32; test_name := 'Key Views Exist'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 33. Key Sequences Exist
  v_pass := TRUE; v_detail := '';
  IF NOT EXISTS (SELECT 1 FROM pg_sequences WHERE sequencename = 'entry_number_seq') THEN
    v_pass := FALSE; v_detail := 'entry_number_seq MISSING; ';
  END IF;
  IF v_pass THEN v_detail := 'Key sequences exist'; END IF;
  test_id := 33; test_name := 'Key Sequences Exist'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 34. Triggers Valid
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM pg_trigger t
  JOIN pg_class c ON t.tgrelid = c.oid
  JOIN pg_namespace n ON c.relnamespace = n.oid
  WHERE n.nspname = 'public' AND NOT t.tgisinternal
    AND NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = t.tgfoid);
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' broken triggers'; ELSE v_detail := 'All triggers valid'; END IF;
  test_id := 34; test_name := 'Triggers Valid'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 35. No Fake UUID Functions
  v_pass := TRUE; v_detail := '';
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = '_int_to_uuid') THEN
    v_pass := FALSE; v_detail := v_detail || '_int_to_uuid exists (fake UUID); ';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = '_uuid_to_int') THEN
    v_pass := FALSE; v_detail := v_detail || '_uuid_to_int exists; ';
  END IF;
  IF v_pass THEN v_detail := 'No fake UUID functions found'; END IF;
  test_id := 35; test_name := 'No Fake UUID Functions'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- ============================================================================
  -- SECTION D: INVENTORY INTEGRITY (Tests 36-40)
  -- ============================================================================

  -- 36. Inventory Quantities Non-Negative
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM raw_materials WHERE quantity < 0;
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' negative quantities'; ELSE v_detail := 'All non-negative'; END IF;
  test_id := 36; test_name := 'Inventory Quantities Non-Negative'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 37. Stock Batch Quantities Consistent
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM stock_batches WHERE remaining_quantity > quantity;
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' inconsistent batches'; ELSE v_detail := 'All consistent'; END IF;
  test_id := 37; test_name := 'Stock Batch Quantities'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 38. No Batches Without Purchase
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM stock_batches sb
  WHERE sb.purchase_invoice_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM purchase_invoices pi WHERE pi.id = sb.purchase_invoice_id);
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' orphan batches'; ELSE v_detail := 'All batches have valid purchase'; END IF;
  test_id := 38; test_name := 'No Orphan Stock Batches'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 39. No Duplicate Batches
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM (
    SELECT batch_number, COUNT(*) AS cnt FROM stock_batches GROUP BY batch_number HAVING COUNT(*) > 1
  ) d;
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' duplicate batch numbers'; ELSE v_detail := 'No duplicates'; END IF;
  test_id := 39; test_name := 'No Duplicate Batches'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 40. Station Product Quantities Non-Negative
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM station_products WHERE quantity < 0;
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' negative'; ELSE v_detail := 'All non-negative'; END IF;
  test_id := 40; test_name := 'Station Product Quantities'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- ============================================================================
  -- SECTION E: MASTER DATA (Tests 41-48)
  -- ============================================================================

  -- 41. Accounts Exist
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM accounts;
  IF v_count = 0 THEN v_pass := FALSE; v_detail := 'NO accounts'; ELSE v_detail := v_count || ' accounts'; END IF;
  test_id := 41; test_name := 'Master: Accounts'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 42. Customers Exist
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM customers;
  IF v_count = 0 THEN v_pass := FALSE; v_detail := 'NO customers'; ELSE v_detail := v_count || ' customers'; END IF;
  test_id := 42; test_name := 'Master: Customers'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 43. Suppliers Exist
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM suppliers;
  IF v_count = 0 THEN v_pass := FALSE; v_detail := 'NO suppliers'; ELSE v_detail := v_count || ' suppliers'; END IF;
  test_id := 43; test_name := 'Master: Suppliers'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 44. Treasuries Exist
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM treasuries;
  IF v_count = 0 THEN v_pass := FALSE; v_detail := 'NO treasuries'; ELSE v_detail := v_count || ' treasuries'; END IF;
  test_id := 44; test_name := 'Master: Treasuries'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 45. Raw Materials Exist
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM raw_materials;
  IF v_count = 0 THEN v_pass := FALSE; v_detail := 'NO raw materials'; ELSE v_detail := v_count || ' raw materials'; END IF;
  test_id := 45; test_name := 'Master: Raw Materials'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 46. Stations Exist
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM stations;
  IF v_count = 0 THEN v_pass := FALSE; v_detail := 'NO stations'; ELSE v_detail := v_count || ' stations'; END IF;
  test_id := 46; test_name := 'Master: Stations'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 47. User Roles Exist
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM user_roles;
  IF v_count = 0 THEN v_pass := FALSE; v_detail := 'NO user roles'; ELSE v_detail := v_count || ' user roles'; END IF;
  test_id := 47; test_name := 'Master: User Roles'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 48. Bank Accounts Exist
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM bank_accounts;
  IF v_count = 0 THEN v_pass := FALSE; v_detail := 'NO bank accounts'; ELSE v_detail := v_count || ' bank accounts'; END IF;
  test_id := 48; test_name := 'Master: Bank Accounts'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- ============================================================================
  -- SECTION F: CURRENCY / EXCHANGE (Tests 49-52)
  -- ============================================================================

  -- 49. Currencies Exist
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM currencies;
  IF v_count = 0 THEN v_pass := FALSE; v_detail := 'NO currencies'; ELSE v_detail := v_count || ' currencies'; END IF;
  test_id := 49; test_name := 'Master: Currencies'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 50. Exchange Rates Exist
  v_pass := TRUE;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'exchange_rates') THEN
    SELECT COUNT(*) INTO v_count FROM exchange_rates;
    IF v_count = 0 THEN v_pass := FALSE; v_detail := 'NO exchange rates'; ELSE v_detail := v_count || ' exchange rates'; END IF;
  ELSE
    v_detail := 'exchange_rates table not found (soft check)';
  END IF;
  test_id := 50; test_name := 'Exchange Rates'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 51. Treasury Balances Exist
  v_pass := TRUE;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'treasury_balances') THEN
    SELECT COUNT(*) INTO v_count FROM treasury_balances;
    v_detail := v_count || ' treasury balances';
  ELSE
    v_detail := 'treasury_balances table not found';
  END IF;
  test_id := 51; test_name := 'Treasury Balances'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 52. No NULL currency on transactions
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM transactions WHERE currency_snapshot IS NULL AND (debit > 0 OR credit > 0);
  v_detail := v_count || ' transactions without currency snapshot';
  test_id := 52; test_name := 'Currency Snapshot (soft)'; passed := TRUE; details := v_detail;
  RETURN NEXT;

  -- ============================================================================
  -- SECTION G: SECURITY (Tests 53-54)
  -- ============================================================================

  -- 53. No functions with unexpected search_path
  v_pass := TRUE; v_detail := '';
  SELECT COUNT(*) INTO v_count FROM pg_proc p
  WHERE p.proconfig IS NOT NULL
    AND EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%' AND c != 'search_path=public, extensions' AND c != 'search_path=public');
  IF v_count > 0 THEN
    v_pass := FALSE; v_detail := v_count || ' functions with unexpected search_path';
  ELSE
    v_detail := 'All search_paths OK';
  END IF;
  test_id := 53; test_name := 'search_path Safe'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 54. RLS / Grants (soft check)
  v_pass := TRUE; v_detail := '';
  v_detail := 'Soft check -- review RLS policies separately';
  test_id := 54; test_name := 'RLS / Grants (soft)'; passed := TRUE; details := v_detail;
  RETURN NEXT;

  -- ============================================================================
  -- SECTION H: COMPREHENSIVE (Tests 55-60)
  -- ============================================================================

  -- 55. No confirmed invoices with zero items
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM purchase_invoices pi
  WHERE pi.status = 'confirmed'
    AND NOT EXISTS (SELECT 1 FROM purchase_invoice_items pii WHERE pii.invoice_id = pi.id);
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' confirmed invoices without items'; ELSE v_detail := 'All confirmed invoices have items'; END IF;
  test_id := 55; test_name := 'Confirmed Invoices Have Items'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 56. No duplicate invoice numbers
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM (
    SELECT invoice_number, COUNT(*) FROM purchase_invoices
    WHERE invoice_number IS NOT NULL
    GROUP BY invoice_number HAVING COUNT(*) > 1
  ) d;
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' duplicate invoice numbers'; ELSE v_detail := 'No duplicates'; END IF;
  test_id := 56; test_name := 'No Duplicate Invoice Numbers'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 57. No purchase invoices with mismatched totals
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM purchase_invoices pi
  WHERE pi.status = 'confirmed'
    AND ABS(pi.total_amount - (
      SELECT COALESCE(SUM(pii.quantity * pii.unit_cost), 0)
      FROM purchase_invoice_items pii WHERE pii.invoice_id = pi.id
    )) > 0.01;
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' invoices with mismatched totals'; ELSE v_detail := 'All totals match'; END IF;
  test_id := 57; test_name := 'Invoice Totals Match Items'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 58. No cancelled invoices with stock batches
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM stock_batches sb
  WHERE EXISTS (SELECT 1 FROM purchase_invoices pi WHERE pi.id = sb.purchase_invoice_id AND pi.status = 'cancelled');
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' batches for cancelled invoices'; ELSE v_detail := 'Clean'; END IF;
  test_id := 58; test_name := 'No Stock for Cancelled Invoices'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 59. No duplicate supplier codes
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM (
    SELECT code, COUNT(*) FROM suppliers WHERE code IS NOT NULL GROUP BY code HAVING COUNT(*) > 1
  ) d;
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' duplicate supplier codes'; ELSE v_detail := 'No duplicates'; END IF;
  test_id := 59; test_name := 'No Duplicate Supplier Codes'; passed := v_pass; details := v_detail;
  RETURN NEXT;

  -- 60. All export shipments have valid statuses
  v_pass := TRUE;
  SELECT COUNT(*) INTO v_count FROM export_shipments
  WHERE status NOT IN ('draft','confirmed','shipped','in_transit','delivered','cancelled');
  IF v_count > 0 THEN v_pass := FALSE; v_detail := v_count || ' invalid statuses'; ELSE v_detail := 'All valid'; END IF;
  test_id := 60; test_name := 'Valid Shipment Statuses'; passed := v_pass; details := v_detail;
  RETURN NEXT;

END;
$$;

-- ==========================================
-- 10. CREATE INDEX STATEMENTS
-- ==========================================
--
-- Name: idx_accounts_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_accounts_active" ON "public"."accounts" USING "btree" ("is_active");

--
-- Name: idx_accounts_code; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_accounts_code" ON "public"."accounts" USING "btree" ("code");

--
-- Name: idx_audit_log_action; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_audit_log_action" ON "public"."fiscal_year_audit_log" USING "btree" ("action");

--
-- Name: idx_audit_log_changed_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_audit_log_changed_at" ON "public"."financial_audit_log" USING "btree" ("changed_at");

--
-- Name: idx_audit_log_fy; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_audit_log_fy" ON "public"."fiscal_year_audit_log" USING "btree" ("fiscal_year_id");

--
-- Name: idx_audit_log_performed_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_audit_log_performed_at" ON "public"."fiscal_year_audit_log" USING "btree" ("performed_at");

--
-- Name: idx_audit_log_table_record; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_audit_log_table_record" ON "public"."financial_audit_log" USING "btree" ("table_name", "record_id");

--
-- Name: idx_audit_logs_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_audit_logs_created_at" ON "public"."audit_logs" USING "btree" ("created_at");

--
-- Name: idx_audit_logs_record_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_audit_logs_record_id" ON "public"."audit_logs" USING "btree" ("record_id");

--
-- Name: idx_audit_logs_table_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_audit_logs_table_name" ON "public"."audit_logs" USING "btree" ("table_name");

--
-- Name: idx_audit_logs_text_table_record; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_audit_logs_text_table_record" ON "public"."audit_logs_text" USING "btree" ("table_name", "record_id");

--
-- Name: idx_audit_logs_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_audit_logs_user_id" ON "public"."audit_logs" USING "btree" ("user_id");

--
-- Name: idx_cash_payments_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_cash_payments_date" ON "public"."cash_payments" USING "btree" ("payment_date");

--
-- Name: idx_cash_payments_supplier; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_cash_payments_supplier" ON "public"."cash_payments" USING "btree" ("supplier_id");

--
-- Name: idx_cashbox_transactions_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_cashbox_transactions_created_at" ON "public"."cashbox_transactions" USING "btree" ("created_at");

--
-- Name: idx_cashbox_transactions_reference; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_cashbox_transactions_reference" ON "public"."cashbox_transactions" USING "btree" ("reference_type", "reference_id");

--
-- Name: idx_cashbox_transactions_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_cashbox_transactions_type" ON "public"."cashbox_transactions" USING "btree" ("transaction_type");

--
-- Name: idx_cashbox_transactions_user_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_cashbox_transactions_user_id" ON "public"."cashbox_transactions" USING "btree" ("user_id");

--
-- Name: idx_cheques_clearing_agent_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_cheques_clearing_agent_id" ON "public"."cheques" USING "btree" ("clearing_agent_id") WHERE ("clearing_agent_id" IS NOT NULL);

--
-- Name: idx_cheques_counterparty; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_cheques_counterparty" ON "public"."cheques" USING "btree" ("counterparty_type", "counterparty_id", "supplier_id");

--
-- Name: idx_cheques_due_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_cheques_due_date" ON "public"."cheques" USING "btree" ("due_date");

--
-- Name: idx_cheques_shareholder_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_cheques_shareholder_id" ON "public"."cheques" USING "btree" ("shareholder_id") WHERE ("shareholder_id" IS NOT NULL);

--
-- Name: idx_cheques_shipping_company_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_cheques_shipping_company_id" ON "public"."cheques" USING "btree" ("shipping_company_id") WHERE ("shipping_company_id" IS NOT NULL);

--
-- Name: idx_cheques_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_cheques_status" ON "public"."cheques" USING "btree" ("status");

--
-- Name: idx_cheques_supplier_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_cheques_supplier_id" ON "public"."cheques" USING "btree" ("supplier_id") WHERE ("supplier_id" IS NOT NULL);

--
-- Name: idx_clearing_agents_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_clearing_agents_name" ON "public"."clearing_agents" USING "btree" ("name");

--
-- Name: idx_company_addresses_company; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_company_addresses_company" ON "public"."company_addresses" USING "btree" ("company_id", "company_type");

--
-- Name: idx_cost_breakdown_shipment; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_cost_breakdown_shipment" ON "public"."shipment_cost_breakdown" USING "btree" ("shipment_id");

--
-- Name: idx_cost_items_shipment; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_cost_items_shipment" ON "public"."shipment_cost_items" USING "btree" ("shipment_id");

--
-- Name: idx_cost_items_vendor; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_cost_items_vendor" ON "public"."shipment_cost_items" USING "btree" ("vendor_type", "vendor_id") WHERE ("vendor_type" IS NOT NULL);

--
-- Name: idx_expense_categories_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX "idx_expense_categories_name" ON "public"."expense_categories" USING "btree" ("name");

--
-- Name: idx_export_invoices_customer; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_export_invoices_customer" ON "public"."export_invoices" USING "btree" ("customer_id");

--
-- Name: idx_export_invoices_no; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX "idx_export_invoices_no" ON "public"."export_invoices" USING "btree" ("invoice_no");

--
-- Name: idx_export_shipment_items_packing_order; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_export_shipment_items_packing_order" ON "public"."export_shipment_items" USING "btree" ("packing_order_id");

--
-- Name: idx_export_shipment_items_shipment; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_export_shipment_items_shipment" ON "public"."export_shipment_items" USING "btree" ("shipment_id");

--
-- Name: idx_export_shipments_packing_recipe; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_export_shipments_packing_recipe" ON "public"."export_shipments" USING "btree" ("packing_recipe_id");

--
-- Name: idx_fiscal_years_closed; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_fiscal_years_closed" ON "public"."fiscal_years" USING "btree" ("is_closed") WHERE "is_closed";

--
-- Name: idx_fiscal_years_current; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_fiscal_years_current" ON "public"."fiscal_years" USING "btree" ("is_current") WHERE "is_current";

--
-- Name: idx_fiscal_years_dates; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_fiscal_years_dates" ON "public"."fiscal_years" USING "btree" ("start_date", "end_date");

--
-- Name: idx_fiscal_years_year; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX "idx_fiscal_years_year" ON "public"."fiscal_years" USING "btree" ("year");

--
-- Name: idx_fruit_catalog_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_fruit_catalog_active" ON "public"."fruit_catalog" USING "btree" ("is_active");

--
-- Name: idx_fruit_catalog_category; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_fruit_catalog_category" ON "public"."fruit_catalog" USING "btree" ("category");

--
-- Name: idx_fy_audit_action; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_fy_audit_action" ON "public"."fiscal_year_audit_log" USING "btree" ("action");

--
-- Name: idx_fy_audit_fy_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_fy_audit_fy_id" ON "public"."fiscal_year_audit_log" USING "btree" ("fiscal_year_id");

--
-- Name: idx_fy_audit_performed_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_fy_audit_performed_at" ON "public"."fiscal_year_audit_log" USING "btree" ("performed_at");

--
-- Name: idx_fy_backup_fy_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_fy_backup_fy_id" ON "public"."fiscal_year_backup_metadata" USING "btree" ("fiscal_year_id");

--
-- Name: idx_fy_closing_entries_fy; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_fy_closing_entries_fy" ON "public"."fiscal_year_closing_entries" USING "btree" ("fiscal_year_id");

--
-- Name: idx_fy_closing_entries_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_fy_closing_entries_type" ON "public"."fiscal_year_closing_entries" USING "btree" ("entry_type");

--
-- Name: idx_fy_closing_progress_fy; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_fy_closing_progress_fy" ON "public"."fiscal_year_closing_progress" USING "btree" ("fiscal_year_id");

--
-- Name: idx_fy_closing_progress_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_fy_closing_progress_status" ON "public"."fiscal_year_closing_progress" USING "btree" ("status");

--
-- Name: idx_fy_inv_snapshot_fy; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_fy_inv_snapshot_fy" ON "public"."fiscal_year_inventory_snapshot" USING "btree" ("fiscal_year_id");

--
-- Name: idx_fy_inv_snapshot_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_fy_inv_snapshot_type" ON "public"."fiscal_year_inventory_snapshot" USING "btree" ("snapshot_type");

--
-- Name: idx_invoice_edits_edited_by; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_invoice_edits_edited_by" ON "public"."invoice_edits" USING "btree" ("edited_by");

--
-- Name: idx_invoice_edits_invoice; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_invoice_edits_invoice" ON "public"."invoice_edits" USING "btree" ("invoice_type", "invoice_id");

--
-- Name: idx_ledger_entries_entity; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_ledger_entries_entity" ON "public"."ledger_entries" USING "btree" ("entity_type", "entity_id", "created_at" DESC);

--
-- Name: idx_ledger_entries_reference_text; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_ledger_entries_reference_text" ON "public"."ledger_entries" USING "btree" ("reference_type", "reference_text") WHERE ("reference_text" IS NOT NULL);

--
-- Name: idx_ledger_entries_reversal; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_ledger_entries_reversal" ON "public"."ledger_entries" USING "btree" ("reversal_of_id") WHERE ("reversal_of_id" IS NOT NULL);

--
-- Name: idx_lot_grading_lot; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_lot_grading_lot" ON "public"."lot_grading_results" USING "btree" ("lot_id");

--
-- Name: idx_lot_grading_stock_batch; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_lot_grading_stock_batch" ON "public"."lot_grading_results" USING "btree" ("stock_batch_id");

--
-- Name: idx_lot_receipts_confirmed; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_lot_receipts_confirmed" ON "public"."lot_receipts" USING "btree" ("is_confirmed");

--
-- Name: idx_lot_receipts_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_lot_receipts_date" ON "public"."lot_receipts" USING "btree" ("receipt_date");

--
-- Name: idx_lot_receipts_purchase_item; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_lot_receipts_purchase_item" ON "public"."lot_receipts" USING "btree" ("purchase_invoice_item_id");

--
-- Name: idx_lot_receipts_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_lot_receipts_status" ON "public"."lot_receipts" USING "btree" ("status");

--
-- Name: idx_packing_cost_items_order; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_packing_cost_items_order" ON "public"."packing_order_cost_items" USING "btree" ("packing_order_id");

--
-- Name: idx_packing_order_cost_items_packing_order_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_packing_order_cost_items_packing_order_id" ON "public"."packing_order_cost_items" USING "btree" ("packing_order_id");

--
-- Name: idx_packing_order_sortings_order_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_packing_order_sortings_order_id" ON "public"."packing_order_sortings" USING "btree" ("packing_order_id");

--
-- Name: idx_packing_order_sortings_packing_order_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_packing_order_sortings_packing_order_id" ON "public"."packing_order_sortings" USING "btree" ("packing_order_id");

--
-- Name: idx_packing_order_sortings_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_packing_order_sortings_status" ON "public"."packing_order_sortings" USING "btree" ("status");

--
-- Name: idx_packing_orders_lot; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_packing_orders_lot" ON "public"."packing_orders" USING "btree" ("lot_id");

--
-- Name: idx_packing_orders_shipment; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_packing_orders_shipment" ON "public"."packing_orders" USING "btree" ("export_shipment_id");

--
-- Name: idx_packing_orders_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_packing_orders_status" ON "public"."packing_orders" USING "btree" ("status");

--
-- Name: idx_packing_recipes_product_grade; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_packing_recipes_product_grade" ON "public"."packing_recipes" USING "btree" ("product_id", "grade");

--
-- Name: idx_packing_recipes_raw_material; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_packing_recipes_raw_material" ON "public"."packing_recipes" USING "btree" ("raw_material_id");

--
-- Name: idx_prep_center_cost_items_shipment; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_prep_center_cost_items_shipment" ON "public"."prep_center_cost_items" USING "btree" ("shipment_id");

--
-- Name: idx_pricing_rules_category_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_pricing_rules_category_id" ON "public"."pricing_rules" USING "btree" ("category_id");

--
-- Name: idx_pricing_rules_finished_product; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_pricing_rules_finished_product" ON "public"."pricing_rules" USING "btree" ("finished_product_id");

--
-- Name: idx_pricing_rules_is_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_pricing_rules_is_active" ON "public"."pricing_rules" USING "btree" ("is_active");

--
-- Name: idx_profitability_snapshots_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_profitability_snapshots_created_at" ON "public"."shipment_profitability_snapshots" USING "btree" ("created_at" DESC);

--
-- Name: idx_profitability_snapshots_shipment; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_profitability_snapshots_shipment" ON "public"."shipment_profitability_snapshots" USING "btree" ("shipment_id");

--
-- Name: idx_profitability_snapshots_shipment_no; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_profitability_snapshots_shipment_no" ON "public"."shipment_profitability_snapshots" USING "btree" ("shipment_no");

--
-- Name: idx_profitability_snapshots_unique_shipment; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX "idx_profitability_snapshots_unique_shipment" ON "public"."shipment_profitability_snapshots" USING "btree" ("shipment_id");

--
-- Name: idx_purchase_invoice_items_invoice_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_purchase_invoice_items_invoice_id" ON "public"."purchase_invoice_items" USING "btree" ("invoice_id");

--
-- Name: idx_purchase_invoices_invoice_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_purchase_invoices_invoice_date" ON "public"."purchase_invoices" USING "btree" ("invoice_date");

--
-- Name: idx_purchase_invoices_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_purchase_invoices_status" ON "public"."purchase_invoices" USING "btree" ("status");

--
-- Name: idx_purchase_invoices_supplier_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_purchase_invoices_supplier_id" ON "public"."purchase_invoices" USING "btree" ("supplier_id");

--
-- Name: idx_raw_materials_code; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_raw_materials_code" ON "public"."raw_materials" USING "btree" ("code");

--
-- Name: idx_raw_materials_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_raw_materials_name" ON "public"."raw_materials" USING "btree" ("name");

--
-- Name: idx_sales_invoice_items_finished_product; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_sales_invoice_items_finished_product" ON "public"."sales_invoice_items" USING "btree" ("finished_product_id");

--
-- Name: idx_sales_invoice_items_invoice_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_sales_invoice_items_invoice_id" ON "public"."sales_invoice_items" USING "btree" ("invoice_id");

--
-- Name: idx_sales_invoices_customer_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_sales_invoices_customer_id" ON "public"."sales_invoices" USING "btree" ("customer_id");

--
-- Name: idx_sales_invoices_invoice_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_sales_invoices_invoice_date" ON "public"."sales_invoices" USING "btree" ("invoice_date");

--
-- Name: idx_sales_invoices_sale_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_sales_invoices_sale_type" ON "public"."sales_invoices" USING "btree" ("sale_type");

--
-- Name: idx_sales_invoices_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_sales_invoices_status" ON "public"."sales_invoices" USING "btree" ("status");

--
-- Name: idx_shipment_cost_allocations_finished_product; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_shipment_cost_allocations_finished_product" ON "public"."shipment_cost_allocations" USING "btree" ("finished_product_id");

--
-- Name: idx_shipment_cost_allocations_shipment; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_shipment_cost_allocations_shipment" ON "public"."shipment_cost_allocations" USING "btree" ("shipment_id");

--
-- Name: idx_shipment_recipe_snapshots_recipe; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_shipment_recipe_snapshots_recipe" ON "public"."shipment_recipe_snapshots" USING "btree" ("packing_recipe_id");

--
-- Name: idx_shipment_recipe_snapshots_shipment; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_shipment_recipe_snapshots_shipment" ON "public"."shipment_recipe_snapshots" USING "btree" ("shipment_id");

--
-- Name: idx_shipping_companies_code; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_shipping_companies_code" ON "public"."shipping_companies" USING "btree" ("code");

--
-- Name: idx_shipping_companies_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_shipping_companies_name" ON "public"."shipping_companies" USING "btree" ("name");

--
-- Name: idx_shipping_companies_phone; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_shipping_companies_phone" ON "public"."shipping_companies" USING "btree" ("phone");

--
-- Name: idx_spd_shareholder; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_spd_shareholder" ON "public"."shareholder_profit_distributions" USING "btree" ("shareholder_id");

--
-- Name: idx_spd_shipment; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_spd_shipment" ON "public"."shareholder_profit_distributions" USING "btree" ("shipment_id");

--
-- Name: idx_spd_unique_dist; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX "idx_spd_unique_dist" ON "public"."shareholder_profit_distributions" USING "btree" ("shipment_id", "shareholder_id", "person_index");

--
-- Name: idx_statement_notes_lookup; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_statement_notes_lookup" ON "public"."statement_notes" USING "btree" ("entity_type", "entity_id", "reference_id");

--
-- Name: idx_station_product_batches_lookup; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_station_product_batches_lookup" ON "public"."station_product_batches" USING "btree" ("station_id", "product_name");

--
-- Name: idx_station_product_batches_purchase_invoice_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_station_product_batches_purchase_invoice_id" ON "public"."station_product_batches" USING "btree" ("purchase_invoice_id");

--
-- Name: idx_station_products_product_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_station_products_product_id" ON "public"."station_products" USING "btree" ("fruit_type_id");

--
-- Name: idx_station_products_station; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_station_products_station" ON "public"."station_products" USING "btree" ("station_id");

--
-- Name: idx_stations_code; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_stations_code" ON "public"."stations" USING "btree" ("code");

--
-- Name: idx_stations_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_stations_name" ON "public"."stations" USING "btree" ("name");

--
-- Name: idx_stations_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_stations_type" ON "public"."stations" USING "btree" ("type");

--
-- Name: idx_stock_batches_fifo; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_stock_batches_fifo" ON "public"."stock_batches" USING "btree" ("product_id", "status", "created_at");

--
-- Name: idx_stock_batches_product_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_stock_batches_product_id" ON "public"."stock_batches" USING "btree" ("product_id");

--
-- Name: idx_stock_batches_product_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_stock_batches_product_status" ON "public"."stock_batches" USING "btree" ("product_id", "status");

--
-- Name: idx_stock_batches_purchase_invoice_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_stock_batches_purchase_invoice_id" ON "public"."stock_batches" USING "btree" ("purchase_invoice_id");

--
-- Name: idx_stock_batches_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_stock_batches_status" ON "public"."stock_batches" USING "btree" ("status");

--
-- Name: idx_stock_movements_batch_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_stock_movements_batch_id" ON "public"."stock_movements" USING "btree" ("batch_id");

--
-- Name: idx_stock_movements_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_stock_movements_created_at" ON "public"."stock_movements" USING "btree" ("created_at");

--
-- Name: idx_stock_movements_movement_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_stock_movements_movement_type" ON "public"."stock_movements" USING "btree" ("movement_type");

--
-- Name: idx_stock_movements_product_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_stock_movements_product_id" ON "public"."stock_movements" USING "btree" ("product_id");

--
-- Name: idx_stock_transfers_created; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_stock_transfers_created" ON "public"."stock_transfers" USING "btree" ("created_at" DESC);

--
-- Name: idx_stock_transfers_from; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_stock_transfers_from" ON "public"."stock_transfers" USING "btree" ("from_station_id");

--
-- Name: idx_stock_transfers_to; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_stock_transfers_to" ON "public"."stock_transfers" USING "btree" ("to_station_id");

--
-- Name: idx_supplier_settlements_shipment; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_supplier_settlements_shipment" ON "public"."supplier_settlements" USING "btree" ("shipment_id");

--
-- Name: idx_supplier_settlements_supplier; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_supplier_settlements_supplier" ON "public"."supplier_settlements" USING "btree" ("supplier_id");

--
-- Name: idx_tenant_users_tenant; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_tenant_users_tenant" ON "public"."tenant_users" USING "btree" ("tenant_id");

--
-- Name: idx_tenant_users_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_tenant_users_user" ON "public"."tenant_users" USING "btree" ("user_id");

--
-- Name: idx_tenants_is_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_tenants_is_active" ON "public"."tenants" USING "btree" ("is_active");

--
-- Name: idx_tenants_is_read_only; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_tenants_is_read_only" ON "public"."tenants" USING "btree" ("is_read_only");

--
-- Name: idx_transactions_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_transactions_date" ON "public"."transactions" USING "btree" ("transaction_date");

--
-- Name: idx_transactions_purchase_invoice_ref; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_transactions_purchase_invoice_ref" ON "public"."transactions" USING "btree" ("purchase_invoice_ref");

--
-- Name: idx_treasury_balances_account; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_treasury_balances_account" ON "public"."treasury_balances" USING "btree" ("account_id");

--
-- Name: idx_treasury_balances_account_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_treasury_balances_account_id" ON "public"."treasury_balances" USING "btree" ("account_id");

--
-- Name: idx_treasury_balances_currency; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_treasury_balances_currency" ON "public"."treasury_balances" USING "btree" ("currency");

--
-- Name: idx_treasury_balances_treasury_currency; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_treasury_balances_treasury_currency" ON "public"."treasury_balances" USING "btree" ("treasury_id", "currency");

--
-- Name: idx_treasury_transactions_clearing_agent; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_treasury_transactions_clearing_agent" ON "public"."treasury_transactions" USING "btree" ("clearing_agent_id") WHERE ("clearing_agent_id" IS NOT NULL);

--
-- Name: idx_treasury_transactions_shipping_company; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_treasury_transactions_shipping_company" ON "public"."treasury_transactions" USING "btree" ("shipping_company_id") WHERE ("shipping_company_id" IS NOT NULL);

--
-- Name: idx_tt_currency_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_tt_currency_date" ON "public"."treasury_transactions" USING "btree" ("currency", "created_at" DESC);

--
-- Name: idx_tt_customer; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_tt_customer" ON "public"."treasury_transactions" USING "btree" ("customer_id") WHERE ("customer_id" IS NOT NULL);

--
-- Name: idx_tt_supplier; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_tt_supplier" ON "public"."treasury_transactions" USING "btree" ("supplier_id") WHERE ("supplier_id" IS NOT NULL);

--
-- Name: idx_tt_treasury_type_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_tt_treasury_type_date" ON "public"."treasury_transactions" USING "btree" ("treasury_id", "type", "created_at" DESC);

--
-- Name: idx_unit_conversions_product_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_unit_conversions_product_id" ON "public"."unit_conversions" USING "btree" ("product_id");

--
-- Name: idx_warehouses_is_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_warehouses_is_active" ON "public"."warehouses" USING "btree" ("is_active");

--
-- Name: idx_warehouses_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX "idx_warehouses_name" ON "public"."warehouses" USING "btree" ("name");

--
-- Name: uq_station_products_station_product_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX "uq_station_products_station_product_id" ON "public"."station_products" USING "btree" ("station_id", "fruit_type_id") WHERE ("fruit_type_id" IS NOT NULL);
