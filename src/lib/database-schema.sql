-- --------------------------------------------------------------------------------
--  ARVO Database Schema
--
--  This schema is designed to be multi-tenant, with all data primarily
--  isolated by a `company_id`. Row-Level Security (RLS) is used extensively
--  to enforce this data separation.
-- --------------------------------------------------------------------------------

-- --------------------------------------------------------------------------------
--  Extensions
-- --------------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";
CREATE EXTENSION IF NOT EXISTS "vector" WITH SCHEMA "extensions";

-- --------------------------------------------------------------------------------
--  Enums
-- --------------------------------------------------------------------------------
CREATE TYPE "public"."company_role" AS ENUM ('Owner', 'Admin', 'Member');
CREATE TYPE "public"."feedback_type" AS ENUM ('helpful', 'unhelpful');
CREATE TYPE "public"."integration_platform" AS ENUM ('shopify', 'woocommerce', 'amazon_fba');
CREATE TYPE "public"."message_role" AS ENUM ('user', 'assistant', 'tool');


-- --------------------------------------------------------------------------------
--  Tables
-- --------------------------------------------------------------------------------

-- Stores company information
CREATE TABLE "public"."companies" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "name" "text" NOT NULL,
    "owner_id" "uuid" NOT NULL
);
ALTER TABLE "public"."companies" OWNER TO "postgres";
ALTER TABLE "public"."companies" ENABLE ROW LEVEL SECURITY;

-- Maps users to companies and their roles
CREATE TABLE "public"."company_users" (
    "user_id" "uuid" NOT NULL,
    "company_id" "uuid" NOT NULL,
    "role" "public"."company_role" DEFAULT 'Member'::"public"."company_role" NOT NULL
);
ALTER TABLE "public"."company_users" OWNER TO "postgres";
ALTER TABLE "public"."company_users" ENABLE ROW LEVEL SECURITY;

-- Stores company-specific settings and business logic parameters
CREATE TABLE "public"."company_settings" (
    "company_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT now() NOT NULL,
    "updated_at" timestamp with time zone,
    "dead_stock_days" integer DEFAULT 90 NOT NULL,
    "fast_moving_days" integer DEFAULT 30 NOT NULL,
    "overstock_multiplier" real DEFAULT 3 NOT NULL,
    "high_value_threshold" integer DEFAULT 100000 NOT NULL, -- Stored in cents
    "predictive_stock_days" integer DEFAULT 7 NOT NULL,
    "currency" character varying DEFAULT 'USD'::character varying NOT NULL,
    "tax_rate" real DEFAULT 0 NOT NULL,
    "timezone" text DEFAULT 'UTC'::text NOT NULL
);
ALTER TABLE "public"."company_settings" OWNER TO "postgres";
ALTER TABLE "public"."company_settings" ENABLE ROW LEVEL SECURITY;


-- Stores products
CREATE TABLE "public"."products" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "external_product_id" "text",
    "title" "text" NOT NULL,
    "description" "text",
    "status" "text",
    "image_url" "text",
    "handle" "text",
    "product_type" "text",
    "tags" "text"[],
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone
);
ALTER TABLE "public"."products" OWNER TO "postgres";
ALTER TABLE "public"."products" ENABLE ROW LEVEL SECURITY;

-- Stores product variants (SKUs)
CREATE TABLE "public"."product_variants" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "product_id" "uuid" NOT NULL,
    "company_id" "uuid" NOT NULL,
    "supplier_id" "uuid",
    "external_variant_id" "text",
    "title" "text",
    "sku" "text" NOT NULL,
    "barcode" "text",
    "price" integer, -- Stored in cents
    "cost" integer, -- Stored in cents
    "compare_at_price" integer, -- Stored in cents
    "inventory_quantity" integer DEFAULT 0 NOT NULL,
    "reorder_point" integer,
    "reorder_quantity" integer,
    "location" "text",
    "option1_name" "text",
    "option1_value" "text",
    "option2_name" "text",
    "option2_value" "text",
    "option3_name" "text",
    "option3_value" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone
);
ALTER TABLE "public"."product_variants" OWNER TO "postgres";
ALTER TABLE "public"."product_variants" ENABLE ROW LEVEL SECURITY;


-- Stores suppliers
CREATE TABLE "public"."suppliers" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "email" "text",
    "phone" "text",
    "default_lead_time_days" integer,
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone
);
ALTER TABLE "public"."suppliers" OWNER TO "postgres";
ALTER TABLE "public"."suppliers" ENABLE ROW LEVEL SECURITY;

-- Stores purchase orders
CREATE TABLE "public"."purchase_orders" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "supplier_id" "uuid",
    "po_number" "text" NOT NULL,
    "status" "text" DEFAULT 'Draft'::"text" NOT NULL,
    "total_cost" integer NOT NULL, -- Stored in cents
    "expected_arrival_date" "date",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone,
    "idempotency_key" "uuid"
);
ALTER TABLE "public"."purchase_orders" OWNER TO "postgres";
ALTER TABLE "public"."purchase_orders" ENABLE ROW LEVEL SECURITY;

-- Stores line items for purchase orders
CREATE TABLE "public"."purchase_order_line_items" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "purchase_order_id" "uuid" NOT NULL,
    "company_id" "uuid" NOT NULL,
    "variant_id" "uuid" NOT NULL,
    "quantity" integer NOT NULL,
    "cost" integer NOT NULL -- Stored in cents
);
ALTER TABLE "public"."purchase_order_line_items" OWNER TO "postgres";
ALTER TABLE "public"."purchase_order_line_items" ENABLE ROW LEVEL SECURITY;


-- Stores customers
CREATE TABLE "public"."customers" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "external_customer_id" "text",
    "name" "text",
    "email" "text",
    "phone" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone,
    "deleted_at" timestamp with time zone
);
ALTER TABLE "public"."customers" OWNER TO "postgres";
ALTER TABLE "public"."customers" ENABLE ROW LEVEL SECURITY;


-- Stores orders
CREATE TABLE "public"."orders" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "customer_id" "uuid",
    "external_order_id" "text",
    "order_number" "text" NOT NULL,
    "subtotal" integer NOT NULL, -- Stored in cents
    "total_tax" integer, -- Stored in cents
    "total_shipping" integer, -- Stored in cents
    "total_discounts" integer, -- Stored in cents
    "total_amount" integer NOT NULL, -- Stored in cents
    "financial_status" "text",
    "fulfillment_status" "text",
    "currency" "text",
    "source_platform" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone
);
ALTER TABLE "public"."orders" OWNER TO "postgres";
ALTER TABLE "public"."orders" ENABLE ROW LEVEL SECURITY;

-- Stores line items for orders
CREATE TABLE "public"."order_line_items" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "variant_id" "uuid",
    "company_id" "uuid" NOT NULL,
    "external_line_item_id" "text",
    "product_name" "text",
    "variant_title" "text",
    "sku" "text",
    "quantity" integer NOT NULL,
    "price" integer NOT NULL, -- Stored in cents
    "total_discount" integer, -- Stored in cents
    "tax_amount" integer, -- Stored in cents
    "cost_at_time" integer -- Stored in cents
);
ALTER TABLE "public"."order_line_items" OWNER TO "postgres";
ALTER TABLE "public"."order_line_items" ENABLE ROW LEVEL SECURITY;

-- Stores refunds
CREATE TABLE "public"."refunds" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "order_id" "uuid" NOT NULL,
    "external_refund_id" "text",
    "refund_number" "text" NOT NULL,
    "status" "text" NOT NULL,
    "reason" "text",
    "note" "text",
    "total_amount" integer NOT NULL, -- Stored in cents
    "created_by_user_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);
ALTER TABLE "public"."refunds" OWNER TO "postgres";
ALTER TABLE "public"."refunds" ENABLE ROW LEVEL SECURITY;

-- Stores ledger of all inventory movements for auditing
CREATE TABLE "public"."inventory_ledger" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "variant_id" "uuid" NOT NULL,
    "company_id" "uuid" NOT NULL,
    "quantity_change" integer NOT NULL,
    "new_quantity" integer NOT NULL,
    "change_type" "text" NOT NULL,
    "related_id" "uuid",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);
ALTER TABLE "public"."inventory_ledger" OWNER TO "postgres";
ALTER TABLE "public"."inventory_ledger" ENABLE ROW LEVEL SECURITY;


-- Stores third-party integrations
CREATE TABLE "public"."integrations" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "platform" "public"."integration_platform" NOT NULL,
    "shop_domain" "text",
    "shop_name" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "last_sync_at" timestamp with time zone,
    "sync_status" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone
);
ALTER TABLE "public"."integrations" OWNER TO "postgres";
ALTER TABLE "public"."integrations" ENABLE ROW LEVEL SECURITY;


-- Stores AI chat conversation metadata
CREATE TABLE "public"."conversations" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "company_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_accessed_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "is_starred" boolean DEFAULT false NOT NULL
);
ALTER TABLE "public"."conversations" OWNER TO "postgres";
ALTER TABLE "public"."conversations" ENABLE ROW LEVEL SECURITY;


-- Stores individual messages within conversations
CREATE TABLE "public"."messages" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "conversation_id" "uuid" NOT NULL,
    "company_id" "uuid" NOT NULL,
    "role" "public"."message_role" NOT NULL,
    "content" "text" NOT NULL,
    "visualization" "jsonb",
    "confidence" real,
    "assumptions" "text"[],
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "isError" boolean,
    "component" "text",
    "componentProps" "jsonb"
);
ALTER TABLE "public"."messages" OWNER TO "postgres";
ALTER TABLE "public"."messages" ENABLE ROW LEVEL SECURITY;

-- Stores audit logs for important actions
CREATE TABLE "public"."audit_log" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "user_id" "uuid",
    "action" "text" NOT NULL,
    "details" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);
ALTER TABLE "public"."audit_log" OWNER TO "postgres";
ALTER TABLE "public"."audit_log" ENABLE ROW LEVEL SECURITY;


-- Stores feedback on AI responses
CREATE TABLE "public"."feedback" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "company_id" "uuid" NOT NULL,
    "subject_id" "uuid" NOT NULL,
    "subject_type" "text" NOT NULL,
    "feedback" "public"."feedback_type" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);
ALTER TABLE "public"."feedback" OWNER TO "postgres";
ALTER TABLE "public"."feedback" ENABLE ROW LEVEL SECURITY;


-- Stores data export job information
CREATE TABLE "public"."export_jobs" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "requested_by_user_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "download_url" "text",
    "expires_at" timestamp with time zone,
    "error_message" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "completed_at" timestamp with time zone
);
ALTER TABLE "public"."export_jobs" OWNER TO "postgres";
ALTER TABLE "public"."export_jobs" ENABLE ROW LEVEL SECURITY;


-- Stores fees associated with sales channels
CREATE TABLE "public"."channel_fees" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "channel_name" "text" NOT NULL,
    "fixed_fee" integer,
    "percentage_fee" real,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone
);
ALTER TABLE "public"."channel_fees" OWNER TO "postgres";
ALTER TABLE "public"."channel_fees" ENABLE ROW LEVEL SECURITY;

-- Stores webhook events to prevent duplicates
CREATE TABLE "public"."webhook_events" (
  "id" uuid DEFAULT "uuid_generate_v4"() NOT NULL,
  "integration_id" uuid NOT NULL,
  "webhook_id" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);
ALTER TABLE "public"."webhook_events" OWNER TO "postgres";
ALTER TABLE "public"."webhook_events" ENABLE ROW LEVEL SECURITY;

-- Stores data import job information
CREATE TABLE "public"."imports" (
    "id" "uuid" DEFAULT "uuid_generate_v4"() NOT NULL,
    "company_id" "uuid" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "import_type" "text" NOT NULL,
    "file_name" "text" NOT NULL,
    "total_rows" integer,
    "processed_rows" integer,
    "error_count" integer,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "errors" "jsonb",
    "summary" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "completed_at" timestamp with time zone
);
ALTER TABLE "public"."imports" OWNER TO "postgres";
ALTER TABLE "public"."imports" ENABLE ROW LEVEL SECURITY;



-- --------------------------------------------------------------------------------
--  Primary Keys and Constraints
-- --------------------------------------------------------------------------------

ALTER TABLE ONLY "public"."audit_log" ADD CONSTRAINT "audit_log_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."channel_fees" ADD CONSTRAINT "channel_fees_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."companies" ADD CONSTRAINT "companies_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."company_settings" ADD CONSTRAINT "company_settings_pkey" PRIMARY KEY ("company_id");
ALTER TABLE ONLY "public"."company_users" ADD CONSTRAINT "company_users_pkey" PRIMARY KEY ("user_id", "company_id");
ALTER TABLE ONLY "public"."conversations" ADD CONSTRAINT "conversations_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."customers" ADD CONSTRAINT "customers_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."export_jobs" ADD CONSTRAINT "export_jobs_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."feedback" ADD CONSTRAINT "feedback_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."imports" ADD CONSTRAINT "imports_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."integrations" ADD CONSTRAINT "integrations_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."inventory_ledger" ADD CONSTRAINT "inventory_ledger_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."messages" ADD CONSTRAINT "messages_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."order_line_items" ADD CONSTRAINT "order_line_items_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."orders" ADD CONSTRAINT "orders_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."product_variants" ADD CONSTRAINT "product_variants_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."products" ADD CONSTRAINT "products_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."purchase_order_line_items" ADD CONSTRAINT "purchase_order_line_items_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."purchase_orders" ADD CONSTRAINT "purchase_orders_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."refunds" ADD CONSTRAINT "refunds_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."suppliers" ADD CONSTRAINT "suppliers_pkey" PRIMARY KEY ("id");
ALTER TABLE ONLY "public"."webhook_events" ADD CONSTRAINT "webhook_events_pkey" PRIMARY KEY ("id");


-- Unique constraints
ALTER TABLE ONLY "public"."integrations" ADD CONSTRAINT "integrations_company_id_platform_key" UNIQUE ("company_id", "platform");
ALTER TABLE ONLY "public"."product_variants" ADD CONSTRAINT "product_variants_company_id_sku_key" UNIQUE ("company_id", "sku");
ALTER TABLE ONLY "public"."webhook_events" ADD CONSTRAINT "webhook_events_integration_id_webhook_id_key" UNIQUE ("integration_id", "webhook_id");
ALTER TABLE ONLY "public"."channel_fees" ADD CONSTRAINT "channel_fees_company_id_channel_name_key" UNIQUE (company_id, channel_name);

-- --------------------------------------------------------------------------------
--  Foreign Keys
-- --------------------------------------------------------------------------------

ALTER TABLE ONLY "public"."audit_log" ADD CONSTRAINT "audit_log_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."audit_log" ADD CONSTRAINT "audit_log_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."channel_fees" ADD CONSTRAINT "channel_fees_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."companies" ADD CONSTRAINT "companies_owner_id_fkey" FOREIGN KEY ("owner_id") REFERENCES "auth"."users"("id");
ALTER TABLE ONLY "public"."company_settings" ADD CONSTRAINT "company_settings_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."company_users" ADD CONSTRAINT "company_users_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."company_users" ADD CONSTRAINT "company_users_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."conversations" ADD CONSTRAINT "conversations_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."conversations" ADD CONSTRAINT "conversations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."customers" ADD CONSTRAINT "customers_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."export_jobs" ADD CONSTRAINT "export_jobs_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."export_jobs" ADD CONSTRAINT "export_jobs_requested_by_user_id_fkey" FOREIGN KEY ("requested_by_user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."feedback" ADD CONSTRAINT "feedback_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."feedback" ADD CONSTRAINT "feedback_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."imports" ADD CONSTRAINT "imports_company_id_fkey" FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;
ALTER TABLE ONLY "public"."imports" ADD CONSTRAINT "imports_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE ONLY "public"."integrations" ADD CONSTRAINT "integrations_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."inventory_ledger" ADD CONSTRAINT "inventory_ledger_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."inventory_ledger" ADD CONSTRAINT "inventory_ledger_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "public"."product_variants"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."messages" ADD CONSTRAINT "messages_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."messages" ADD CONSTRAINT "messages_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "public"."conversations"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."order_line_items" ADD CONSTRAINT "order_line_items_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."order_line_items" ADD CONSTRAINT "order_line_items_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."order_line_items" ADD CONSTRAINT "order_line_items_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "public"."product_variants"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."orders" ADD CONSTRAINT "orders_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."orders" ADD CONSTRAINT "orders_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."product_variants" ADD CONSTRAINT "product_variants_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."product_variants" ADD CONSTRAINT "product_variants_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "public"."products"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."product_variants" ADD CONSTRAINT "product_variants_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."products" ADD CONSTRAINT "products_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."purchase_order_line_items" ADD CONSTRAINT "purchase_order_line_items_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."purchase_order_line_items" ADD CONSTRAINT "purchase_order_line_items_purchase_order_id_fkey" FOREIGN KEY ("purchase_order_id") REFERENCES "public"."purchase_orders"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."purchase_order_line_items" ADD CONSTRAINT "purchase_order_line_items_variant_id_fkey" FOREIGN KEY ("variant_id") REFERENCES "public"."product_variants"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."purchase_orders" ADD CONSTRAINT "purchase_orders_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."purchase_orders" ADD CONSTRAINT "purchase_orders_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."refunds" ADD CONSTRAINT "refunds_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."refunds" ADD CONSTRAINT "refunds_created_by_user_id_fkey" FOREIGN KEY ("created_by_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;
ALTER TABLE ONLY "public"."refunds" ADD CONSTRAINT "refunds_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."suppliers" ADD CONSTRAINT "suppliers_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "public"."companies"("id") ON DELETE CASCADE;
ALTER TABLE ONLY "public"."webhook_events" ADD CONSTRAINT "webhook_events_integration_id_fkey" FOREIGN KEY ("integration_id") REFERENCES "public"."integrations"("id") ON DELETE CASCADE;

-- --------------------------------------------------------------------------------
--  Functions and Triggers
-- --------------------------------------------------------------------------------

-- Function to get company_id for the current user
CREATE OR REPLACE FUNCTION public.get_company_id_for_user(p_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN (SELECT company_id FROM public.company_users WHERE user_id = p_user_id LIMIT 1);
END;
$$;

-- Function to lock a user account for a specified duration
CREATE OR REPLACE FUNCTION public.lock_user_account(p_user_id uuid, p_lockout_duration text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE auth.users
  SET banned_until = now() + p_lockout_duration::interval
  WHERE id = p_user_id;
END;
$$;

-- Trigger function to create a company and associate the user after signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  company_id uuid;
  company_name text;
BEGIN
  -- Get company name from user metadata, fallback to a default
  company_name := COALESCE(new.raw_user_meta_data->>'company_name', new.email);
  
  -- Create a new company for the user
  INSERT INTO public.companies (name, owner_id)
  VALUES (company_name, new.id)
  RETURNING id INTO company_id;

  -- Link the user to the new company as 'Owner'
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (new.id, company_id, 'Owner');
  
  -- Create default settings for the new company
  INSERT INTO public.company_settings (company_id)
  VALUES (company_id);
  
  -- Update the user's app_metadata with the company_id
  UPDATE auth.users
  SET app_metadata = jsonb_set(COALESCE(app_metadata, '{}'::jsonb), '{company_id}', to_jsonb(company_id))
  WHERE id = new.id;
  
  RETURN new;
END;
$$;

-- Trigger to execute the function after a new user is created
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Trigger function to handle inventory changes on sale
CREATE OR REPLACE FUNCTION public.handle_inventory_change_on_sale()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_new_quantity int;
BEGIN
  -- Check for sufficient inventory before updating
  IF (SELECT inventory_quantity FROM public.product_variants WHERE id = NEW.variant_id) < NEW.quantity THEN
    RAISE EXCEPTION 'Insufficient stock for SKU %. Cannot fulfill order.', (SELECT sku FROM public.product_variants WHERE id = NEW.variant_id);
  END IF;

  UPDATE public.product_variants
  SET inventory_quantity = inventory_quantity - NEW.quantity,
      updated_at = now()
  WHERE id = NEW.variant_id
  RETURNING inventory_quantity INTO v_new_quantity;
  
  INSERT INTO public.inventory_ledger (variant_id, company_id, quantity_change, new_quantity, change_type, related_id, notes)
  VALUES (NEW.variant_id, NEW.company_id, -NEW.quantity, v_new_quantity, 'sale', NEW.order_id, 'Order #' || (SELECT order_number FROM public.orders WHERE id = NEW.order_id));
  
  RETURN NEW;
END;
$$;

-- Trigger to execute the function after a new order line item is created
CREATE TRIGGER on_order_line_item_created
  AFTER INSERT ON public.order_line_items
  FOR EACH ROW EXECUTE PROCEDURE public.handle_inventory_change_on_sale();


-- --------------------------------------------------------------------------------
--  Row-Level Security (RLS) Policies
-- --------------------------------------------------------------------------------

-- Helper function to get the current user's company ID
CREATE OR REPLACE FUNCTION public.current_user_company_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT (auth.jwt()->>'app_metadata')::jsonb->>'company_id'
$$;

-- Policies for companies
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can only see their own company" ON public.companies FOR SELECT USING (id = public.current_user_company_id());

-- Policies for company_users
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can see other members of their own company" ON public.company_users FOR SELECT USING (company_id = public.current_user_company_id());

-- Generic policy for most tables
CREATE OR REPLACE FUNCTION apply_rls_to_table(table_name text)
RETURNS void AS $$
BEGIN
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', table_name);
  EXECUTE format('CREATE POLICY "Users can only access their own company''s data" ON public.%I FOR ALL USING (company_id = public.current_user_company_id()) WITH CHECK (company_id = public.current_user_company_id());', table_name);
END;
$$ LANGUAGE plpgsql;

-- Apply generic policy to all tables with a company_id column
SELECT apply_rls_to_table(table_name)
FROM information_schema.columns
WHERE table_schema = 'public' AND column_name = 'company_id'
  AND table_name NOT IN ('companies', 'company_users'); -- These have custom policies

-- --------------------------------------------------------------------------------
--  Materialized Views for Performance
-- --------------------------------------------------------------------------------

CREATE MATERIALIZED VIEW public.product_variants_with_details_mat AS
SELECT 
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url as image_url,
    p.product_type
FROM 
    public.product_variants pv
JOIN 
    public.products p ON pv.product_id = p.id;

CREATE UNIQUE INDEX ON public.product_variants_with_details_mat (id);

-- Function to refresh all materialized views
CREATE OR REPLACE FUNCTION refresh_all_matviews(p_company_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY public.product_variants_with_details_mat;
    -- Add other materialized views here in the future
END;
$$;

-- (Initial population of the view)
REFRESH MATERIALIZED VIEW public.product_variants_with_details_mat;
