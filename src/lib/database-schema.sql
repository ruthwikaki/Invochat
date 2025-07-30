--
-- PostgreSQL database dump
--

-- Dumped from database version 16.3 (Ubuntu 16.3-1.pgdg22.04+1)
-- Dumped by pg_dump version 16.3 (Ubuntu 16.3-1.pgdg22.04+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgsodium; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "pgsodium" WITH SCHEMA "pgsodium";


--
-- Name: pg_graphql; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";


--
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";


--
-- Name: pgjwt; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "pgjwt" WITH SCHEMA "extensions";


--
-- Name: supabase_vault; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";


--
-- Name: company_role; Type: ENUM; Schema: public; Owner: supabase_admin
--

CREATE TYPE "public"."company_role" AS ENUM (
    'Owner',
    'Admin',
    'Member'
);


--
-- Name: feedback_type; Type: ENUM; Schema: public; Owner: supabase_admin
--

CREATE TYPE "public"."feedback_type" AS ENUM (
    'helpful',
    'unhelpful'
);


--
-- Name: integration_platform; Type: ENUM; Schema: public; Owner: supabase_admin
--

CREATE TYPE "public"."integration_platform" AS ENUM (
    'shopify',
    'woocommerce',
    'amazon_fba'
);


--
-- Name: message_role; Type: ENUM; Schema: public; Owner: supabase_admin
--

CREATE TYPE "public"."message_role" AS ENUM (
    'user',
    'assistant',
    'tool'
);


--
-- Name: po_status; Type: ENUM; Schema: public; Owner: supabase_admin
--

CREATE TYPE "public"."po_status" AS ENUM (
    'Draft',
    'Ordered',
    'Partially Received',
    'Received',
    'Cancelled'
);


--
-- Name: create_company_and_user(text, text, text); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE OR REPLACE FUNCTION "public"."create_company_and_user"(p_company_name text, p_user_email text, p_user_password text) RETURNS "uuid"
    LANGUAGE "plpgsql"
    SECURITY DEFINER
    AS $$
DECLARE
  v_company_id UUID;
  v_user_id UUID;
BEGIN
  -- Create a new company
  INSERT INTO public.companies (name)
  VALUES (p_company_name)
  RETURNING id INTO v_company_id;

  -- Create a new user in the auth.users table
  v_user_id := auth.uid FROM auth.users WHERE email = p_user_email;

  IF v_user_id IS NULL THEN
      v_user_id := (SELECT auth.uid() FROM auth.users ORDER BY created_at DESC LIMIT 1);
  END IF;

  INSERT INTO public.users (id, company_id, email, role)
  VALUES (v_user_id, v_company_id, p_user_email, 'Owner');
  
  -- Update the company with the owner's ID
  UPDATE public.companies
  SET owner_id = v_user_id
  WHERE id = v_company_id;

  RETURN v_user_id;
END;
$$;


--
-- Name: get_users_for_company(uuid); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION "public"."get_users_for_company"(p_company_id "uuid") RETURNS TABLE(id "uuid", email "text", role "public"."company_role")
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  RETURN QUERY
  SELECT u.id, u.email, cu.role
  FROM auth.users u
  JOIN public.company_users cu ON u.id = cu.user_id
  WHERE cu.company_id = p_company_id;
END;
$$;


--
-- Name: remove_user_from_company(uuid, uuid); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION "public"."remove_user_from_company"(p_user_id "uuid", p_company_id "uuid") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  DELETE FROM public.company_users
  WHERE user_id = p_user_id AND company_id = p_company_id;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = "heap";

--
-- Name: alert_history; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE "public"."alert_history" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "alert_id" "text" NOT NULL,
    "status" "text" DEFAULT 'unread'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "read_at" timestamp with time zone,
    "dismissed_at" timestamp with time zone,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb"
);


--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE "public"."audit_log" (
    "id" bigint NOT NULL,
    "user_id" "uuid",
    "action" "text" NOT NULL,
    "details" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "company_id" "uuid"
);


--
-- Name: audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: supabase_admin
--

ALTER TABLE "public"."audit_log" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."audit_log_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: channel_fees; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE "public"."channel_fees" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "channel_name" "text" NOT NULL,
    "percentage_fee" "numeric" NOT NULL,
    "fixed_fee" "numeric" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone
);


--
-- Name: companies; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE "public"."companies" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "owner_id" "uuid"
);


--
-- Name: company_settings; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE "public"."company_settings" (
    "company_id" "uuid" NOT NULL,
    "dead_stock_days" integer DEFAULT 90 NOT NULL,
    "fast_moving_days" integer DEFAULT 30 NOT NULL,
    "predictive_stock_days" integer DEFAULT 7 NOT NULL,
    "currency" "text" DEFAULT 'USD'::"text",
    "timezone" "text" DEFAULT 'UTC'::"text",
    "tax_rate" "numeric" DEFAULT 0,
    "custom_rules" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone,
    "subscription_status" "text" DEFAULT 'trial'::"text",
    "subscription_plan" "text" DEFAULT 'starter'::"text",
    "subscription_expires_at" timestamp with time zone,
    "stripe_customer_id" "text",
    "stripe_subscription_id" "text",
    "promo_sales_lift_multiplier" "real" DEFAULT 2.5 NOT NULL,
    "overstock_multiplier" integer DEFAULT 3 NOT NULL,
    "high_value_threshold" integer DEFAULT 1000 NOT NULL,
    "alert_settings" "jsonb" DEFAULT '{"dismissal_hours": 24, "email_notifications": true, "enabled_alert_types": ["low_stock", "out_of_stock", "overstock"], "low_stock_threshold": 10, "morning_briefing_time": "09:00", "critical_stock_threshold": 5, "morning_briefing_enabled": true}'::"jsonb"
);


--
-- Name: company_users; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE "public"."company_users" (
    "company_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "public"."company_role" DEFAULT 'Member'::"public"."company_role" NOT NULL
);


--
-- Name: conversations; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE "public"."conversations" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "company_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "last_accessed_at" timestamp with time zone DEFAULT "now"(),
    "is_starred" boolean DEFAULT "false"
);


--
-- Name: customer_addresses; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE "public"."customer_addresses" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "customer_id" "uuid" NOT NULL,
    "address_type" "text" DEFAULT 'shipping'::"text" NOT NULL,
    "first_name" "text",
    "last_name" "text",
    "company" "text",
    "address1" "text",
    "address2" "text",
    "city" "text",
    "province_code" "text",
    "country_code" "text",
    "zip" "text",
    "phone" "text",
    "is_default" boolean DEFAULT "false"
);


--
-- Name: customers; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE "public"."customers" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "customer_name" "text" NOT NULL,
    "email" "text",
    "total_orders" integer DEFAULT 0,
    "total_spent" integer DEFAULT 0,
    "first_order_date" "date",
    "deleted_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"()
);


--
-- Name: discounts; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE "public"."discounts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "code" "text" NOT NULL,
    "type" "text" NOT NULL,
    "value" integer NOT NULL,
    "minimum_purchase" integer,
    "usage_limit" integer,
    "usage_count" integer DEFAULT 0,
    "applies_to" "text" DEFAULT 'all'::"text",
    "starts_at" timestamp with time zone,
    "ends_at" timestamp with time zone,
    "is_active" boolean DEFAULT "true",
    "created_at" timestamp with time zone DEFAULT "now"()
);


--
-- Name: export_jobs; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE "public"."export_jobs" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "requested_by_user_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "download_url" "text",
    "expires_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


--
-- Name: feedback; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE "public"."feedback" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "company_id" "uuid" NOT NULL,
    "subject_id" "text" NOT NULL,
    "subject_type" "text" NOT NULL,
    "feedback" "public"."feedback_type" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


--
-- Name: imports; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE "public"."imports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "import_type" "text" NOT NULL,
    "file_name" "text" NOT NULL,
    "total_rows" integer,
    "processed_rows" integer,
    "failed_rows" integer,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "errors" "jsonb",
    "summary" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "completed_at" timestamp with time zone
);


--
-- Name: integrations; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE "public"."integrations" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "platform" "text" NOT NULL,
    "shop_domain" "text",
    "shop_name" "text",
    "is_active" boolean DEFAULT "false",
    "last_sync_at" timestamp with time zone,
    "sync_status" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone
);


--
-- Name: inventory_ledger; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE "public"."inventory_ledger" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "change_type" "text" NOT NULL,
    "quantity_change" integer NOT NULL,
    "new_quantity" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "related_id" "uuid",
    "notes" "text",
    "variant_id" "uuid" NOT NULL
);


--
-- Name: messages; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE "public"."messages" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "conversation_id" "uuid" NOT NULL,
    "company_id" "uuid" NOT NULL,
    "role" "text" NOT NULL,
    "content" "text",
    "component" "text",
    "component_props" "jsonb",
    "visualization" "jsonb",
    "confidence" "numeric",
    "assumptions" "text"[],
    "created_at" timestamp with time zone DEFAULT "now"(),
    "is_error" boolean DEFAULT "false"
);


--
-- Name: order_line_items; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE "public"."order_line_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "product_id" "uuid" NOT NULL,
    "variant_id" "uuid" NOT NULL,
    "product_name" "text" NOT NULL,
    "variant_title" "text",
    "sku" "text" NOT NULL,
    "quantity" integer NOT NULL,
    "price" integer NOT NULL,
    "total_discount" integer DEFAULT 0,
    "tax_amount" integer DEFAULT 0,
    "fulfillment_status" "text" DEFAULT 'unfulfilled'::"text",
    "requires_shipping" boolean DEFAULT "true",
    "external_line_item_id" "text",
    "company_id" "uuid" NOT NULL,
    "cost_at_time" integer
);


--
-- Name: orders; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE "public"."orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "order_number" "text" NOT NULL,
    "external_order_id" "text",
    "customer_id" "uuid",
    "financial_status" "text" DEFAULT 'pending'::"text",
    "fulfillment_status" "text" DEFAULT 'unfulfilled'::"text",
    "currency" "text" DEFAULT 'USD'::"text",
    "subtotal" integer DEFAULT 0 NOT NULL,
    "total_tax" integer DEFAULT 0,
    "total_shipping" integer DEFAULT 0,
    "total_discounts" integer DEFAULT 0,
    "total_amount" integer NOT NULL,
    "source_platform" "text",
    "source_name" "text",
    "tags" "text"[],
    "notes" "text",
    "cancelled_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


--
-- Name: product_variants; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE "public"."product_variants" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "product_id" "uuid" NOT NULL,
    "company_id" "uuid" NOT NULL,
    "sku" "text" NOT NULL,
    "title" "text",
    "option1_name" "text",
    "option1_value" "text",
    "option2_name" "text",
    "option2_value" "text",
    "option3_name" "text",
    "option3_value" "text",
    "barcode" "text",
    "price" integer,
    "compare_at_price" integer,
    "cost" integer,
    "inventory_quantity" integer DEFAULT 0 NOT NULL,
    "external_variant_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "location" "text",
    "deleted_at" timestamp with time zone,
    "version" integer DEFAULT 1 NOT NULL,
    "reorder_point" integer,
    "reorder_quantity" integer,
    "reserved_quantity" integer DEFAULT 0 NOT NULL,
    "in_transit_quantity" integer DEFAULT 0 NOT NULL
);


--
-- Name: products; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE "public"."products" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text",
    "handle" "text",
    "product_type" "text",
    "tags" "text"[],
    "status" "text",
    "image_url" "text",
    "external_product_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone,
    "fts_document" "tsvector",
    "deleted_at" timestamp with time zone
);


--
-- Name: purchase_order_line_items; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE "public"."purchase_order_line_items" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "purchase_order_id" "uuid" NOT NULL,
    "variant_id" "uuid" NOT NULL,
    "quantity" integer NOT NULL,
    "cost" integer NOT NULL,
    "company_id" "uuid" NOT NULL
);


--
-- Name: purchase_orders; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE "public"."purchase_orders" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "supplier_id" "uuid",
    "status" "text" DEFAULT 'Draft'::"text" NOT NULL,
    "po_number" "text" NOT NULL,
    "total_cost" integer NOT NULL,
    "expected_arrival_date" "date",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "idempotency_key" "uuid",
    "notes" "text"
);


--
-- Name: refund_line_items; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE "public"."refund_line_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "refund_id" "uuid" NOT NULL,
    "order_line_item_id" "uuid" NOT NULL,
    "quantity" integer NOT NULL,
    "amount" integer NOT NULL,
    "restock" boolean DEFAULT "true",
    "company_id" "uuid" NOT NULL
);


--
-- Name: refunds; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE "public"."refunds" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "order_id" "uuid" NOT NULL,
    "refund_number" "text" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "reason" "text",
    "note" "text",
    "total_amount" integer NOT NULL,
    "created_by_user_id" "uuid",
    "external_refund_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


--
-- Name: suppliers; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE "public"."suppliers" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "email" "text",
    "phone" "text",
    "default_lead_time_days" integer,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "lead_time_days" integer
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE "public"."users" (
    "id" "uuid" NOT NULL,
    "company_id" "uuid" NOT NULL,
    "email" "text",
    "deleted_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"()
);


--
-- Name: alert_history alert_history_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."alert_history"
    ADD CONSTRAINT "alert_history_pkey" PRIMARY KEY ("id");


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."audit_log"
    ADD CONSTRAINT "audit_log_pkey" PRIMARY KEY ("id");


--
-- Name: channel_fees channel_fees_company_id_channel_name_key; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."channel_fees"
    ADD CONSTRAINT "channel_fees_company_id_channel_name_key" UNIQUE ("company_id", "channel_name");


--
-- Name: channel_fees channel_fees_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."channel_fees"
    ADD CONSTRAINT "channel_fees_pkey" PRIMARY KEY ("id");


--
-- Name: companies companies_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."companies"
    ADD CONSTRAINT "companies_pkey" PRIMARY KEY ("id");


--
-- Name: company_settings company_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."company_settings"
    ADD CONSTRAINT "company_settings_pkey" PRIMARY KEY ("company_id");


--
-- Name: company_users company_users_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."company_users"
    ADD CONSTRAINT "company_users_pkey" PRIMARY KEY ("company_id", "user_id");


--
-- Name: conversations conversations_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_pkey" PRIMARY KEY ("id");


--
-- Name: customer_addresses customer_addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."customer_addresses"
    ADD CONSTRAINT "customer_addresses_pkey" PRIMARY KEY ("id");


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_pkey" PRIMARY KEY ("id");


--
-- Name: discounts discounts_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."discounts"
    ADD CONSTRAINT "discounts_pkey" PRIMARY KEY ("id");


--
-- Name: export_jobs export_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."export_jobs"
    ADD CONSTRAINT "export_jobs_pkey" PRIMARY KEY ("id");


--
-- Name: feedback feedback_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."feedback"
    ADD CONSTRAINT "feedback_pkey" PRIMARY KEY ("id");


--
-- Name: imports imports_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."imports"
    ADD CONSTRAINT "imports_pkey" PRIMARY KEY ("id");


--
-- Name: integrations integrations_company_id_platform_key; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."integrations"
    ADD CONSTRAINT "integrations_company_id_platform_key" UNIQUE ("company_id", "platform");


--
-- Name: integrations integrations_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."integrations"
    ADD CONSTRAINT "integrations_pkey" PRIMARY KEY ("id");


--
-- Name: inventory_ledger inventory_ledger_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."inventory_ledger"
    ADD CONSTRAINT "inventory_ledger_pkey" PRIMARY KEY ("id");


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_pkey" PRIMARY KEY ("id");


--
-- Name: order_line_items order_line_items_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."order_line_items"
    ADD CONSTRAINT "order_line_items_pkey" PRIMARY KEY ("id");


--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_pkey" PRIMARY KEY ("id");


--
-- Name: product_variants product_variants_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."product_variants"
    ADD CONSTRAINT "product_variants_pkey" PRIMARY KEY ("id");


--
-- Name: product_variants product_variants_sku_company_id_key; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."product_variants"
    ADD CONSTRAINT "product_variants_sku_company_id_key" UNIQUE ("sku", "company_id");


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_pkey" PRIMARY KEY ("id");


--
-- Name: purchase_order_line_items purchase_order_line_items_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."purchase_order_line_items"
    ADD CONSTRAINT "purchase_order_line_items_pkey" PRIMARY KEY ("id");


--
-- Name: purchase_orders purchase_orders_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."purchase_orders"
    ADD CONSTRAINT "purchase_orders_pkey" PRIMARY KEY ("id");


--
-- Name: refund_line_items refund_line_items_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."refund_line_items"
    ADD CONSTRAINT "refund_line_items_pkey" PRIMARY KEY ("id");


--
-- Name: refunds refunds_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."refunds"
    ADD CONSTRAINT "refunds_pkey" PRIMARY KEY ("id");


--
-- Name: suppliers suppliers_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_pkey" PRIMARY KEY ("id");


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");


--
-- Name: webhook_events webhook_events_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."webhook_events"
    ADD CONSTRAINT "webhook_events_pkey" PRIMARY KEY ("id");


--
-- Name: webhook_events webhook_events_webhook_id_integration_id_key; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."webhook_events"
    ADD CONSTRAINT "webhook_events_webhook_id_integration_id_key" UNIQUE ("webhook_id", "integration_id");


--
-- Name: alert_history_company_id_alert_id_idx; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX "alert_history_company_id_alert_id_idx" ON "public"."alert_history" USING "btree" ("company_id", "alert_id");


--
-- Name: audit_log_company_id_idx; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX "audit_log_company_id_idx" ON "public"."audit_log" USING "btree" ("company_id");


--
-- Name: customers_company_id_email_idx; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX "customers_company_id_email_idx" ON "public"."customers" USING "btree" ("company_id", "email");


--
-- Name: products_fts_document_idx; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX "products_fts_document_idx" ON "public"."products" USING "gin" ("fts_document");


--
-- Name: purchase_orders_po_number_key; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE UNIQUE INDEX "purchase_orders_po_number_key" ON "public"."purchase_orders" USING "btree" ("po_number");


--
-- Name: audit_log_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."audit_log"
    ADD CONSTRAINT "audit_log_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");


--
-- Name: audit_log audit_log_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."audit_log"
    ADD CONSTRAINT "audit_log_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");


--
-- Name: channel_fees channel_fees_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."channel_fees"
    ADD CONSTRAINT "channel_fees_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");


--
-- Name: companies companies_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."companies"
    ADD CONSTRAINT "companies_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "auth"."users"("id");


--
-- Name: company_settings company_settings_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."company_settings"
    ADD CONSTRAINT "company_settings_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;


--
-- Name: company_users company_users_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."company_users"
    ADD CONSTRAINT "company_users_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;


--
-- Name: company_users company_users_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."company_users"
    ADD CONSTRAINT "company_users_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;


--
-- Name: conversations conversations_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");


--
-- Name: conversations conversations_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."conversations"
    ADD CONSTRAINT "conversations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");


--
-- Name: customer_addresses customer_addresses_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."customer_addresses"
    ADD CONSTRAINT "customer_addresses_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE CASCADE;


--
-- Name: customers customers_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."customers"
    ADD CONSTRAINT "customers_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");


--
-- Name: discounts discounts_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."discounts"
    ADD CONSTRAINT "discounts_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");


--
-- Name: export_jobs export_jobs_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."export_jobs"
    ADD CONSTRAINT "export_jobs_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");


--
-- Name: export_jobs export_jobs_requested_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."export_jobs"
    ADD CONSTRAINT "export_jobs_requested_by_user_id_fkey" FOREIGN KEY ("requested_by_user_id") REFERENCES "auth"."users"("id");


--
-- Name: feedback feedback_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."feedback"
    ADD CONSTRAINT "feedback_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");


--
-- Name: feedback feedback_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."feedback"
    ADD CONSTRAINT "feedback_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");


--
-- Name: imports fk_imports_company; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."imports"
    ADD CONSTRAINT "fk_imports_company" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");


--
-- Name: imports fk_imports_user; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."imports"
    ADD CONSTRAINT "fk_imports_user" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id");


--
-- Name: integrations integrations_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."integrations"
    ADD CONSTRAINT "integrations_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");


--
-- Name: inventory_ledger inventory_ledger_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."inventory_ledger"
    ADD CONSTRAINT "inventory_ledger_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");


--
-- Name: inventory_ledger inventory_ledger_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."inventory_ledger"
    ADD CONSTRAINT "inventory_ledger_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "public"."product_variants"("id") ON DELETE CASCADE;


--
-- Name: messages messages_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");


--
-- Name: messages messages_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."messages"
    ADD CONSTRAINT "messages_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "public"."conversations"("id") ON DELETE CASCADE;


--
-- Name: order_line_items order_line_items_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."order_line_items"
    ADD CONSTRAINT "order_line_items_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");


--
-- Name: order_line_items order_line_items_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."order_line_items"
    ADD CONSTRAINT "order_line_items_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE CASCADE;


--
-- Name: order_line_items order_line_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."order_line_items"
    ADD CONSTRAINT "order_line_items_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id");


--
-- Name: order_line_items order_line_items_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."order_line_items"
    ADD CONSTRAINT "order_line_items_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "public"."product_variants"("id");


--
-- Name: orders orders_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");


--
-- Name: orders orders_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id");


--
-- Name: product_variants product_variants_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."product_variants"
    ADD CONSTRAINT "product_variants_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");


--
-- Name: product_variants product_variants_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."product_variants"
    ADD CONSTRAINT "product_variants_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;


--
-- Name: products products_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");


--
-- Name: purchase_order_line_items purchase_order_line_items_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."purchase_order_line_items"
    ADD CONSTRAINT "purchase_order_line_items_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");


--
-- Name: purchase_order_line_items purchase_order_line_items_purchase_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."purchase_order_line_items"
    ADD CONSTRAINT "purchase_order_line_items_purchase_order_id_fkey" FOREIGN KEY ("purchase_order_id") REFERENCES "public"."purchase_orders"("id") ON DELETE CASCADE;


--
-- Name: purchase_order_line_items purchase_order_line_items_variant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."purchase_order_line_items"
    ADD CONSTRAINT "purchase_order_line_items_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "public"."product_variants"("id");


--
-- Name: purchase_orders purchase_orders_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."purchase_orders"
    ADD CONSTRAINT "purchase_orders_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");


--
-- Name: purchase_orders purchase_orders_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."purchase_orders"
    ADD CONSTRAINT "purchase_orders_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id");


--
-- Name: refund_line_items refund_line_items_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."refund_line_items"
    ADD CONSTRAINT "refund_line_items_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");


--
-- Name: refund_line_items refund_line_items_order_line_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."refund_line_items"
    ADD CONSTRAINT "refund_line_items_order_line_item_id_fkey" FOREIGN KEY ("order_line_item_id") REFERENCES "public"."order_line_items"("id");


--
-- Name: refund_line_items refund_line_items_refund_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."refund_line_items"
    ADD CONSTRAINT "refund_line_items_refund_id_fkey" FOREIGN KEY ("refund_id") REFERENCES "public"."refunds"("id") ON DELETE CASCADE;


--
-- Name: refunds refunds_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."refunds"
    ADD CONSTRAINT "refunds_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");


--
-- Name: refunds refunds_created_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."refunds"
    ADD CONSTRAINT "refunds_created_by_user_id_fkey" FOREIGN KEY ("created_by_user_id") REFERENCES "auth"."users"("id");


--
-- Name: refunds refunds_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."refunds"
    ADD CONSTRAINT "refunds_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id");


--
-- Name: suppliers suppliers_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."suppliers"
    ADD CONSTRAINT "suppliers_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");


--
-- Name: users users_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id");


--
-- Name: users users_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;


--
-- Name: webhook_events webhook_events_integration_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY "public"."webhook_events"
    ADD CONSTRAINT "webhook_events_integration_id_fkey" FOREIGN KEY ("integration_id") REFERENCES "public"."integrations"("id") ON DELETE CASCADE;

--
-- PostgreSQL database dump complete
--
