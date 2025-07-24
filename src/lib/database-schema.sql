
-- Drop existing tables and views to start fresh
DROP VIEW IF EXISTS "public"."product_variants_with_details_mat";
DROP VIEW IF EXISTS "public"."orders_view";
DROP VIEW IF EXISTS "public"."customers_view";

DROP TABLE IF EXISTS "public"."audit_log";
DROP TABLE IF EXISTS "public"."channel_fees";
DROP TABLE IF EXISTS "public"."company_users";
DROP TABLE IF EXISTS "public"."company_settings";
DROP TABLE IF EXISTS "public"."conversations";
DROP TABLE IF EXISTS "public"."export_jobs";
DROP TABLE IF EXISTS "public"."feedback";
DROP TABLE IF EXISTS "public"."imports";
DROP TABLE IF EXISTS "public"."integrations";
DROP TABLE IF EXISTS "public"."inventory_ledger";
DROP TABLE IF EXISTS "public"."messages";
DROP TABLE IF EXISTS "public"."order_line_items";
DROP TABLE IF EXISTS "public"."orders";
DROP TABLE IF EXISTS "public"."product_variants";
DROP TABLE IF EXISTS "public"."products";
DROP TABLE IF EXISTS "public"."purchase_order_line_items";
DROP TABLE IF EXISTS "public"."purchase_orders";
DROP TABLE IF EXISTS "public"."refunds";
DROP TABLE IF EXISTS "public"."suppliers";
DROP TABLE IF EXISTS "public"."webhook_events";
DROP TABLE IF EXISTS "public"."customers";
DROP TABLE IF EXISTS "public"."companies";

-- Drop existing types
DROP TYPE IF EXISTS "public"."company_role";
DROP TYPE IF EXISTS "public"."feedback_type";
DROP TYPE IF EXISTS "public"."integration_platform";
DROP TYPE IF EXISTS "public"."message_role";

-- Create ENUM types
CREATE TYPE "public"."company_role" AS ENUM (
    'Owner',
    'Admin',
    'Member'
);

CREATE TYPE "public"."feedback_type" AS ENUM (
    'helpful',
    'unhelpful'
);

CREATE TYPE "public"."integration_platform" AS ENUM (
    'shopify',
    'woocommerce',
    'amazon_fba'
);

CREATE TYPE "public"."message_role" AS ENUM (
    'user',
    'assistant',
    'tool'
);

-- Create Tables
CREATE TABLE "public"."companies" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "created_at" timestamp with time zone NOT NULL DEFAULT now(),
    "name" text NOT NULL,
    "owner_id" uuid NOT NULL
);

CREATE TABLE "public"."customers" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "company_id" uuid NOT NULL,
    "external_customer_id" text,
    "name" text,
    "email" text,
    "phone" text,
    "created_at" timestamp with time zone NOT NULL DEFAULT now(),
    "updated_at" timestamp with time zone,
    "deleted_at" timestamp with time zone
);

CREATE TABLE "public"."product_variants" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "product_id" uuid NOT NULL,
    "company_id" uuid NOT NULL,
    "sku" text NOT NULL,
    "title" text,
    "option1_name" text,
    "option1_value" text,
    "option2_name" text,
    "option2_value" text,
    "option3_name" text,
    "option3_value" text,
    "barcode" text,
    "price" integer,
    "compare_at_price" integer,
    "cost" integer,
    "inventory_quantity" integer NOT NULL DEFAULT 0,
    "location" text,
    "reorder_point" integer,
    "reorder_quantity" integer,
    "supplier_id" uuid,
    "external_variant_id" text,
    "created_at" timestamp with time zone NOT NULL DEFAULT now(),
    "updated_at" timestamp with time zone
);

CREATE TABLE "public"."products" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "company_id" uuid NOT NULL,
    "title" text NOT NULL,
    "description" text,
    "handle" text,
    "product_type" text,
    "tags" text[],
    "status" text,
    "image_url" text,
    "external_product_id" text,
    "created_at" timestamp with time zone NOT NULL DEFAULT now(),
    "updated_at" timestamp with time zone
);

CREATE TABLE "public"."suppliers" (
    "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
    "name" text NOT NULL,
    "email" text,
    "phone" text,
    "default_lead_time_days" integer,
    "notes" text,
    "created_at" timestamp with time zone NOT NULL DEFAULT now(),
    "updated_at" timestamp with time zone,
    "company_id" uuid NOT NULL
);

-- Primary Key Constraints
ALTER TABLE "public"."companies" ADD CONSTRAINT "companies_pkey" PRIMARY KEY ("id");
ALTER TABLE "public"."customers" ADD CONSTRAINT "customers_pkey" PRIMARY KEY ("id");
ALTER TABLE "public"."product_variants" ADD CONSTRAINT "product_variants_pkey" PRIMARY KEY ("id");
ALTER TABLE "public"."products" ADD CONSTRAINT "products_pkey" PRIMARY KEY ("id");
ALTER TABLE "public"."suppliers" ADD CONSTRAINT "suppliers_pkey" PRIMARY KEY ("id");

-- Foreign Key Constraints
ALTER TABLE "public"."companies" ADD CONSTRAINT "companies_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES auth.users(id);
ALTER TABLE "public"."customers" ADD CONSTRAINT "customers_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id);
ALTER TABLE "public"."product_variants" ADD CONSTRAINT "product_variants_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id);
ALTER TABLE "public"."product_variants" ADD CONSTRAINT "product_variants_product_id_fkey" FOREIGN KEY (product_id) REFERENCES products(id);
ALTER TABLE "public"."product_variants" ADD CONSTRAINT "product_variants_supplier_id_fkey" FOREIGN KEY (supplier_id) REFERENCES suppliers(id);
ALTER TABLE "public"."products" ADD CONSTRAINT "products_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id);
ALTER TABLE "public"."suppliers" ADD CONSTRAINT "suppliers_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id);

-- Functions
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  new_company_id uuid;
  user_company_name text := new.raw_user_meta_data->>'company_name';
BEGIN
  -- Create a new company for the user
  INSERT INTO public.companies (name, owner_id)
  VALUES (user_company_name, new.id)
  RETURNING id INTO new_company_id;

  -- Add the user to the company_users table with the 'Owner' role
  INSERT INTO public.company_users (user_id, company_id, role)
  VALUES (new.id, new_company_id, 'Owner');
  
  -- Create a settings entry for the new company
  INSERT INTO public.company_settings (company_id)
  VALUES (new_company_id);

  -- Update the user's app_metadata with the new company_id
  UPDATE auth.users
  SET app_metadata = jsonb_set(
    COALESCE(app_metadata, '{}'::jsonb),
    '{company_id}',
    to_jsonb(new_company_id)
  )
  WHERE id = new.id;

  RETURN new;
END;
$function$;

-- Triggers
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Decrement inventory function
CREATE OR REPLACE FUNCTION public.decrement_inventory_for_order(
    p_order_id uuid,
    p_company_id uuid
)
RETURNS void AS $$
DECLARE
    line_item RECORD;
    current_stock INT;
BEGIN
    FOR line_item IN
        SELECT oli.variant_id, oli.quantity
        FROM public.order_line_items oli
        WHERE oli.order_id = p_order_id AND oli.company_id = p_company_id
    LOOP
        -- Check current stock
        SELECT inventory_quantity INTO current_stock
        FROM public.product_variants
        WHERE id = line_item.variant_id;

        -- Prevent stock from going negative
        IF current_stock IS NULL OR current_stock < line_item.quantity THEN
            RAISE EXCEPTION 'Insufficient stock for variant % to fulfill order %. Required: %, Available: %',
                line_item.variant_id, p_order_id, line_item.quantity, COALESCE(current_stock, 0);
        END IF;

        UPDATE public.product_variants
        SET inventory_quantity = inventory_quantity - line_item.quantity
        WHERE id = line_item.variant_id;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Other functions...
-- (Remaining functions would go here)

-- Enable RLS
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
-- ... and so on for all tables

-- RLS Policies
CREATE POLICY "Enable read access for company members" ON "public"."companies"
AS PERMISSIVE FOR SELECT
TO authenticated
USING (id IN (SELECT company_id FROM company_users WHERE user_id = auth.uid()));

CREATE POLICY "Enable all access for company owners" ON "public"."customers"
AS PERMISSIVE FOR ALL
TO authenticated
USING (company_id IN (SELECT company_id FROM company_users WHERE user_id = auth.uid() AND role = 'Owner'));

-- ... and so on for all tables and policies
