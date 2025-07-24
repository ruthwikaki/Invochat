
-- Enable UUID generation
create extension if not exists "uuid-ossp" with schema extensions;

-- Create custom types
create type "public"."company_role" as enum ('Owner', 'Admin', 'Member');
create type "public"."integration_platform" as enum ('shopify', 'woocommerce', 'amazon_fba');
create type "public"."message_role" as enum ('user', 'assistant', 'tool');
create type "public"."feedback_type" as enum ('helpful', 'unhelpful');


-- Companies Table
create table "public"."companies" (
    "id" uuid not null default uuid_generate_v4(),
    "created_at" timestamp with time zone not null default now(),
    "name" text not null,
    "owner_id" uuid not null
);
alter table "public"."companies" enable row level security;
CREATE UNIQUE INDEX companies_pkey ON public.companies USING btree (id);
alter table "public"."companies" add constraint "companies_pkey" PRIMARY KEY using index "companies_pkey";
alter table "public"."companies" add constraint "companies_owner_id_fkey" FOREIGN KEY (owner_id) REFERENCES auth.users(id) ON DELETE CASCADE;
grant delete on table "public"."companies" to "authenticated";
grant insert on table "public"."companies" to "authenticated";
grant references on table "public"."companies" to "authenticated";
grant select on table "public"."companies" to "authenticated";
grant trigger on table "public"."companies" to "authenticated";
grant truncate on table "public"."companies" to "authenticated";
grant update on table "public"."companies" to "authenticated";

-- Company Users Join Table
create table "public"."company_users" (
    "user_id" uuid not null,
    "company_id" uuid not null,
    "role" "public"."company_role" not null default 'Member'::company_role
);
alter table "public"."company_users" enable row level security;
CREATE UNIQUE INDEX company_users_pkey ON public.company_users USING btree (user_id, company_id);
alter table "public"."company_users" add constraint "company_users_pkey" PRIMARY KEY using index "company_users_pkey";
alter table "public"."company_users" add constraint "company_users_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table "public"."company_users" add constraint "company_users_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
grant delete on table "public"."company_users" to "authenticated";
grant insert on table "public"."company_users" to "authenticated";
grant references on table "public"."company_users" to "authenticated";
grant select on table "public"."company_users" to "authenticated";
grant trigger on table "public"."company_users" to "authenticated";
grant truncate on table "public"."company_users" to "authenticated";
grant update on table "public"."company_users" to "authenticated";

-- Company Settings Table
create table "public"."company_settings" (
    "company_id" uuid not null,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone,
    "dead_stock_days" integer not null default 90,
    "fast_moving_days" integer not null default 30,
    "currency" text not null default 'USD'::text,
    "timezone" text not null default 'UTC'::text,
    "tax_rate" real not null default 0,
    "predictive_stock_days" integer not null default 7,
    "overstock_multiplier" real not null default 3,
    "high_value_threshold" integer not null default 100000
);
alter table "public"."company_settings" enable row level security;
CREATE UNIQUE INDEX company_settings_pkey ON public.company_settings USING btree (company_id);
alter table "public"."company_settings" add constraint "company_settings_pkey" PRIMARY KEY using index "company_settings_pkey";
alter table "public"."company_settings" add constraint "company_settings_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
grant delete on table "public"."company_settings" to "authenticated";
grant insert on table "public"."company_settings" to "authenticated";
grant references on table "public"."company_settings" to "authenticated";
grant select on table "public"."company_settings" to "authenticated";
grant trigger on table "public"."company_settings" to "authenticated";
grant truncate on table "public"."company_settings" to "authenticated";
grant update on table "public"."company_settings" to "authenticated";

-- Integrations Table
create table "public"."integrations" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "platform" "public"."integration_platform" not null,
    "shop_domain" text,
    "is_active" boolean not null default true,
    "last_sync_at" timestamp with time zone,
    "sync_status" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone,
    "shop_name" text
);
alter table "public"."integrations" enable row level security;
CREATE UNIQUE INDEX integrations_pkey ON public.integrations USING btree (id);
CREATE UNIQUE INDEX integrations_company_id_platform_key ON public.integrations USING btree (company_id, platform);
alter table "public"."integrations" add constraint "integrations_pkey" PRIMARY KEY using index "integrations_pkey";
alter table "public"."integrations" add constraint "integrations_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table "public"."integrations" add constraint "integrations_company_id_platform_key" UNIQUE using index "integrations_company_id_platform_key";
grant delete on table "public"."integrations" to "authenticated";
grant insert on table "public"."integrations" to "authenticated";
grant references on table "public"."integrations" to "authenticated";
grant select on table "public"."integrations" to "authenticated";
grant trigger on table "public"."integrations" to "authenticated";
grant truncate on table "public"."integrations" to "authenticated";
grant update on table "public"."integrations" to "authenticated";


-- Suppliers Table
create table "public"."suppliers" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "name" text not null,
    "email" text,
    "phone" text,
    "notes" text,
    "default_lead_time_days" integer,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."suppliers" enable row level security;
CREATE UNIQUE INDEX suppliers_pkey ON public.suppliers USING btree (id);
alter table "public"."suppliers" add constraint "suppliers_pkey" PRIMARY KEY using index "suppliers_pkey";
alter table "public"."suppliers" add constraint "suppliers_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
grant delete on table "public"."suppliers" to "authenticated";
grant insert on table "public"."suppliers" to "authenticated";
grant references on table "public"."suppliers" to "authenticated";
grant select on table "public"."suppliers" to "authenticated";
grant trigger on table "public"."suppliers" to "authenticated";
grant truncate on table "public"."suppliers" to "authenticated";
grant update on table "public"."suppliers" to "authenticated";

-- Products Table
create table "public"."products" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "title" text not null,
    "description" text,
    "product_type" text,
    "tags" text[],
    "image_url" text,
    "status" text,
    "handle" text,
    "external_product_id" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."products" enable row level security;
CREATE UNIQUE INDEX products_pkey ON public.products USING btree (id);
CREATE UNIQUE INDEX products_company_id_external_product_id_key ON public.products USING btree (company_id, external_product_id);
alter table "public"."products" add constraint "products_pkey" PRIMARY KEY using index "products_pkey";
alter table "public"."products" add constraint "products_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table "public"."products" add constraint "products_company_id_external_product_id_key" UNIQUE using index "products_company_id_external_product_id_key";
grant delete on table "public"."products" to "authenticated";
grant insert on table "public"."products" to "authenticated";
grant references on table "public"."products" to "authenticated";
grant select on table "public"."products" to "authenticated";
grant trigger on table "public"."products" to "authenticated";
grant truncate on table "public"."products" to "authenticated";
grant update on table "public"."products" to "authenticated";


-- Product Variants Table
create table "public"."product_variants" (
    "id" uuid not null default uuid_generate_v4(),
    "product_id" uuid not null,
    "company_id" uuid not null,
    "sku" text not null,
    "title" text,
    "price" integer,
    "cost" integer,
    "inventory_quantity" integer not null default 0,
    "barcode" text,
    "supplier_id" uuid,
    "location" text,
    "reorder_point" integer,
    "reorder_quantity" integer,
    "external_variant_id" text,
    "compare_at_price" integer,
    "option1_name" text,
    "option1_value" text,
    "option2_name" text,
    "option2_value" text,
    "option3_name" text,
    "option3_value" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."product_variants" enable row level security;
CREATE UNIQUE INDEX product_variants_pkey ON public.product_variants USING btree (id);
CREATE UNIQUE INDEX product_variants_company_id_sku_key ON public.product_variants USING btree (company_id, sku);
CREATE UNIQUE INDEX product_variants_company_id_external_variant_id_key ON public.product_variants USING btree (company_id, external_variant_id);
alter table "public"."product_variants" add constraint "product_variants_pkey" PRIMARY KEY using index "product_variants_pkey";
alter table "public"."product_variants" add constraint "product_variants_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table "public"."product_variants" add constraint "product_variants_company_id_external_variant_id_key" UNIQUE using index "product_variants_company_id_external_variant_id_key";
alter table "public"."product_variants" add constraint "product_variants_company_id_sku_key" UNIQUE using index "product_variants_company_id_sku_key";
alter table "public"."product_variants" add constraint "product_variants_product_id_fkey" FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE;
alter table "public"."product_variants" add constraint "product_variants_supplier_id_fkey" FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL;
grant delete on table "public"."product_variants" to "authenticated";
grant insert on table "public"."product_variants" to "authenticated";
grant references on table "public"."product_variants" to "authenticated";
grant select on table "public"."product_variants" to "authenticated";
grant trigger on table "public"."product_variants" to "authenticated";
grant truncate on table "public"."product_variants" to "authenticated";
grant update on table "public"."product_variants" to "authenticated";


-- Inventory Ledger Table
create table "public"."inventory_ledger" (
    "id" uuid not null default uuid_generate_v4(),
    "variant_id" uuid not null,
    "company_id" uuid not null,
    "change_type" text not null,
    "quantity_change" integer not null,
    "new_quantity" integer not null,
    "related_id" uuid,
    "notes" text,
    "created_at" timestamp with time zone not null default now()
);
alter table "public"."inventory_ledger" enable row level security;
CREATE UNIQUE INDEX inventory_ledger_pkey ON public.inventory_ledger USING btree (id);
alter table "public"."inventory_ledger" add constraint "inventory_ledger_pkey" PRIMARY KEY using index "inventory_ledger_pkey";
alter table "public"."inventory_ledger" add constraint "inventory_ledger_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table "public"."inventory_ledger" add constraint "inventory_ledger_variant_id_fkey" FOREIGN KEY (variant_id) REFERENCES product_variants(id) ON DELETE CASCADE;
grant delete on table "public"."inventory_ledger" to "authenticated";
grant insert on table "public"."inventory_ledger" to "authenticated";
grant references on table "public"."inventory_ledger" to "authenticated";
grant select on table "public"."inventory_ledger" to "authenticated";
grant trigger on table "public"."inventory_ledger" to "authenticated";
grant truncate on table "public"."inventory_ledger" to "authenticated";
grant update on table "public"."inventory_ledger" to "authenticated";


-- Customers Table
create table "public"."customers" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "name" text,
    "email" text,
    "phone" text,
    "external_customer_id" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone,
    "deleted_at" timestamp with time zone
);
alter table "public"."customers" enable row level security;
CREATE UNIQUE INDEX customers_pkey ON public.customers USING btree (id);
CREATE UNIQUE INDEX customers_company_id_external_customer_id_key ON public.customers USING btree (company_id, external_customer_id);
alter table "public"."customers" add constraint "customers_pkey" PRIMARY KEY using index "customers_pkey";
alter table "public"."customers" add constraint "customers_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table "public"."customers" add constraint "customers_company_id_external_customer_id_key" UNIQUE using index "customers_company_id_external_customer_id_key";
grant delete on table "public"."customers" to "authenticated";
grant insert on table "public"."customers" to "authenticated";
grant references on table "public"."customers" to "authenticated";
grant select on table "public"."customers" to "authenticated";
grant trigger on table "public"."customers" to "authenticated";
grant truncate on table "public"."customers" to "authenticated";
grant update on table "public"."customers" to "authenticated";


-- Orders Table
create table "public"."orders" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "order_number" text not null,
    "customer_id" uuid,
    "total_amount" integer not null,
    "currency" text,
    "financial_status" text,
    "fulfillment_status" text,
    "subtotal" integer not null,
    "total_discounts" integer,
    "total_shipping" integer,
    "total_tax" integer,
    "external_order_id" text,
    "source_platform" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."orders" enable row level security;
CREATE UNIQUE INDEX orders_pkey ON public.orders USING btree (id);
CREATE UNIQUE INDEX orders_company_id_external_order_id_key ON public.orders USING btree (company_id, external_order_id);
alter table "public"."orders" add constraint "orders_pkey" PRIMARY KEY using index "orders_pkey";
alter table "public"."orders" add constraint "orders_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table "public"."orders" add constraint "orders_company_id_external_order_id_key" UNIQUE using index "orders_company_id_external_order_id_key";
alter table "public"."orders" add constraint "orders_customer_id_fkey" FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL;
grant delete on table "public"."orders" to "authenticated";
grant insert on table "public"."orders" to "authenticated";
grant references on table "public"."orders" to "authenticated";
grant select on table "public"."orders" to "authenticated";
grant trigger on table "public"."orders" to "authenticated";
grant truncate on table "public"."orders" to "authenticated";
grant update on table "public"."orders" to "authenticated";


-- Order Line Items Table
create table "public"."order_line_items" (
    "id" uuid not null default uuid_generate_v4(),
    "order_id" uuid not null,
    "variant_id" uuid,
    "company_id" uuid not null,
    "quantity" integer not null,
    "price" integer not null,
    "total_discount" integer,
    "tax_amount" integer,
    "cost_at_time" integer,
    "product_name" text,
    "variant_title" text,
    "sku" text,
    "external_line_item_id" text
);
alter table "public"."order_line_items" enable row level security;
CREATE UNIQUE INDEX order_line_items_pkey ON public.order_line_items USING btree (id);
alter table "public"."order_line_items" add constraint "order_line_items_pkey" PRIMARY KEY using index "order_line_items_pkey";
alter table "public"."order_line_items" add constraint "order_line_items_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table "public"."order_line_items" add constraint "order_line_items_order_id_fkey" FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE;
alter table "public"."order_line_items" add constraint "order_line_items_variant_id_fkey" FOREIGN KEY (variant_id) REFERENCES product_variants(id) ON DELETE SET NULL;
grant delete on table "public"."order_line_items" to "authenticated";
grant insert on table "public"."order_line_items" to "authenticated";
grant references on table "public"."order_line_items" to "authenticated";
grant select on table "public"."order_line_items" to "authenticated";
grant trigger on table "public"."order_line_items" to "authenticated";
grant truncate on table "public"."order_line_items" to "authenticated";
grant update on table "public"."order_line_items" to "authenticated";


-- Purchase Orders Table
create table "public"."purchase_orders" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "supplier_id" uuid,
    "status" text not null default 'Draft'::text,
    "total_cost" integer not null,
    "po_number" text not null,
    "notes" text,
    "expected_arrival_date" date,
    "idempotency_key" uuid,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."purchase_orders" enable row level security;
CREATE UNIQUE INDEX purchase_orders_pkey ON public.purchase_orders USING btree (id);
CREATE UNIQUE INDEX purchase_orders_company_id_po_number_key ON public.purchase_orders USING btree (company_id, po_number);
CREATE UNIQUE INDEX purchase_orders_idempotency_key_key ON public.purchase_orders USING btree (idempotency_key);
alter table "public"."purchase_orders" add constraint "purchase_orders_pkey" PRIMARY KEY using index "purchase_orders_pkey";
alter table "public"."purchase_orders" add constraint "purchase_orders_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table "public"."purchase_orders" add constraint "purchase_orders_company_id_po_number_key" UNIQUE using index "purchase_orders_company_id_po_number_key";
alter table "public"."purchase_orders" add constraint "purchase_orders_idempotency_key_key" UNIQUE using index "purchase_orders_idempotency_key_key";
alter table "public"."purchase_orders" add constraint "purchase_orders_supplier_id_fkey" FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL;
grant delete on table "public"."purchase_orders" to "authenticated";
grant insert on table "public"."purchase_orders" to "authenticated";
grant references on table "public"."purchase_orders" to "authenticated";
grant select on table "public"."purchase_orders" to "authenticated";
grant trigger on table "public"."purchase_orders" to "authenticated";
grant truncate on table "public"."purchase_orders" to "authenticated";
grant update on table "public"."purchase_orders" to "authenticated";


-- Purchase Order Line Items Table
create table "public"."purchase_order_line_items" (
    "id" uuid not null default uuid_generate_v4(),
    "purchase_order_id" uuid not null,
    "variant_id" uuid not null,
    "company_id" uuid not null,
    "quantity" integer not null,
    "cost" integer not null
);
alter table "public"."purchase_order_line_items" enable row level security;
CREATE UNIQUE INDEX purchase_order_line_items_pkey ON public.purchase_order_line_items USING btree (id);
alter table "public"."purchase_order_line_items" add constraint "purchase_order_line_items_pkey" PRIMARY KEY using index "purchase_order_line_items_pkey";
alter table "public"."purchase_order_line_items" add constraint "purchase_order_line_items_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table "public"."purchase_order_line_items" add constraint "purchase_order_line_items_purchase_order_id_fkey" FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders(id) ON DELETE CASCADE;
alter table "public"."purchase_order_line_items" add constraint "purchase_order_line_items_variant_id_fkey" FOREIGN KEY (variant_id) REFERENCES product_variants(id) ON DELETE CASCADE;
grant delete on table "public"."purchase_order_line_items" to "authenticated";
grant insert on table "public"."purchase_order_line_items" to "authenticated";
grant references on table "public"."purchase_order_line_items" to "authenticated";
grant select on table "public"."purchase_order_line_items" to "authenticated";
grant trigger on table "public"."purchase_order_line_items" to "authenticated";
grant truncate on table "public"."purchase_order_line_items" to "authenticated";
grant update on table "public"."purchase_order_line_items" to "authenticated";


-- Refunds Table
create table "public"."refunds" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "order_id" uuid not null,
    "refund_number" text not null,
    "total_amount" integer not null,
    "reason" text,
    "note" text,
    "status" text not null,
    "created_by_user_id" uuid,
    "external_refund_id" text,
    "created_at" timestamp with time zone not null default now()
);
alter table "public"."refunds" enable row level security;
CREATE UNIQUE INDEX refunds_pkey ON public.refunds USING btree (id);
alter table "public"."refunds" add constraint "refunds_pkey" PRIMARY KEY using index "refunds_pkey";
alter table "public"."refunds" add constraint "refunds_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table "public"."refunds" add constraint "refunds_created_by_user_id_fkey" FOREIGN KEY (created_by_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table "public"."refunds" add constraint "refunds_order_id_fkey" FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE;
grant delete on table "public"."refunds" to "authenticated";
grant insert on table "public"."refunds" to "authenticated";
grant references on table "public"."refunds" to "authenticated";
grant select on table "public"."refunds" to "authenticated";
grant trigger on table "public"."refunds" to "authenticated";
grant truncate on table "public"."refunds" to "authenticated";
grant update on table "public"."refunds" to "authenticated";


-- Audit Log Table
create table "public"."audit_log" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "user_id" uuid,
    "action" text not null,
    "details" jsonb,
    "created_at" timestamp with time zone not null default now()
);
alter table "public"."audit_log" enable row level security;
CREATE UNIQUE INDEX audit_log_pkey ON public.audit_log USING btree (id);
alter table "public"."audit_log" add constraint "audit_log_pkey" PRIMARY KEY using index "audit_log_pkey";
alter table "public"."audit_log" add constraint "audit_log_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table "public"."audit_log" add constraint "audit_log_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
grant delete on table "public"."audit_log" to "authenticated";
grant insert on table "public"."audit_log" to "authenticated";
grant references on table "public"."audit_log" to "authenticated";
grant select on table "public"."audit_log" to "authenticated";
grant trigger on table "public"."audit_log" to "authenticated";
grant truncate on table "public"."audit_log" to "authenticated";
grant update on table "public"."audit_log" to "authenticated";

-- Conversations Table
create table "public"."conversations" (
    "id" uuid not null default uuid_generate_v4(),
    "user_id" uuid not null,
    "company_id" uuid not null,
    "title" text not null,
    "created_at" timestamp with time zone not null default now(),
    "last_accessed_at" timestamp with time zone not null default now(),
    "is_starred" boolean not null default false
);
alter table "public"."conversations" enable row level security;
CREATE UNIQUE INDEX conversations_pkey ON public.conversations USING btree (id);
alter table "public"."conversations" add constraint "conversations_pkey" PRIMARY KEY using index "conversations_pkey";
alter table "public"."conversations" add constraint "conversations_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table "public"."conversations" add constraint "conversations_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
grant delete on table "public"."conversations" to "authenticated";
grant insert on table "public"."conversations" to "authenticated";
grant references on table "public"."conversations" to "authenticated";
grant select on table "public"."conversations" to "authenticated";
grant trigger on table "public"."conversations" to "authenticated";
grant truncate on table "public"."conversations" to "authenticated";
grant update on table "public"."conversations" to "authenticated";


-- Messages Table
create table "public"."messages" (
    "id" uuid not null default uuid_generate_v4(),
    "conversation_id" uuid not null,
    "company_id" uuid not null,
    "role" "public"."message_role" not null,
    "content" text not null,
    "visualization" jsonb,
    "confidence" real,
    "assumptions" text[],
    "isError" boolean,
    "component" text,
    "componentProps" jsonb,
    "created_at" timestamp with time zone not null default now()
);
alter table "public"."messages" enable row level security;
CREATE UNIQUE INDEX messages_pkey ON public.messages USING btree (id);
alter table "public"."messages" add constraint "messages_pkey" PRIMARY KEY using index "messages_pkey";
alter table "public"."messages" add constraint "messages_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table "public"."messages" add constraint "messages_conversation_id_fkey" FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE;
grant delete on table "public"."messages" to "authenticated";
grant insert on table "public"."messages" to "authenticated";
grant references on table "public"."messages" to "authenticated";
grant select on table "public"."messages" to "authenticated";
grant trigger on table "public"."messages" to "authenticated";
grant truncate on table "public"."messages" to "authenticated";
grant update on table "public"."messages" to "authenticated";


-- Feedback Table
create table "public"."feedback" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "user_id" uuid not null,
    "subject_id" uuid not null,
    "subject_type" text not null,
    "feedback" "public"."feedback_type" not null,
    "created_at" timestamp with time zone not null default now()
);
alter table "public"."feedback" enable row level security;
CREATE UNIQUE INDEX feedback_pkey ON public.feedback USING btree (id);
alter table "public"."feedback" add constraint "feedback_pkey" PRIMARY KEY using index "feedback_pkey";
alter table "public"."feedback" add constraint "feedback_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table "public"."feedback" add constraint "feedback_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
grant delete on table "public"."feedback" to "authenticated";
grant insert on table "public"."feedback" to "authenticated";
grant references on table "public"."feedback" to "authenticated";
grant select on table "public"."feedback" to "authenticated";
grant trigger on table "public"."feedback" to "authenticated";
grant truncate on table "public"."feedback" to "authenticated";
grant update on table "public"."feedback" to "authenticated";

-- Channel Fees Table
create table "public"."channel_fees" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "channel_name" text not null,
    "fixed_fee" integer,
    "percentage_fee" real,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."channel_fees" enable row level security;
CREATE UNIQUE INDEX channel_fees_pkey ON public.channel_fees USING btree (id);
CREATE UNIQUE INDEX channel_fees_company_id_channel_name_key ON public.channel_fees USING btree (company_id, channel_name);
alter table "public"."channel_fees" add constraint "channel_fees_pkey" PRIMARY KEY using index "channel_fees_pkey";
alter table "public"."channel_fees" add constraint "channel_fees_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table "public"."channel_fees" add constraint "channel_fees_company_id_channel_name_key" UNIQUE using index "channel_fees_company_id_channel_name_key";
grant delete on table "public"."channel_fees" to "authenticated";
grant insert on table "public"."channel_fees" to "authenticated";
grant references on table "public"."channel_fees" to "authenticated";
grant select on table "public"."channel_fees" to "authenticated";
grant trigger on table "public"."channel_fees" to "authenticated";
grant truncate on table "public"."channel_fees" to "authenticated";
grant update on table "public"."channel_fees" to "authenticated";


-- Webhook Events Table
create table "public"."webhook_events" (
    "id" uuid not null default uuid_generate_v4(),
    "integration_id" uuid not null,
    "webhook_id" text not null,
    "created_at" timestamp with time zone not null default now()
);
alter table "public"."webhook_events" enable row level security;
CREATE UNIQUE INDEX webhook_events_pkey ON public.webhook_events USING btree (id);
CREATE UNIQUE INDEX webhook_events_integration_id_webhook_id_key ON public.webhook_events USING btree (integration_id, webhook_id);
alter table "public"."webhook_events" add constraint "webhook_events_pkey" PRIMARY KEY using index "webhook_events_pkey";
alter table "public"."webhook_events" add constraint "webhook_events_integration_id_fkey" FOREIGN KEY (integration_id) REFERENCES integrations(id) ON DELETE CASCADE;
alter table "public"."webhook_events" add constraint "webhook_events_integration_id_webhook_id_key" UNIQUE using index "webhook_events_integration_id_webhook_id_key";
grant delete on table "public"."webhook_events" to "authenticated";
grant insert on table "public"."webhook_events" to "authenticated";
grant references on table "public"."webhook_events" to "authenticated";
grant select on table "public"."webhook_events" to "authenticated";
grant trigger on table "public"."webhook_events" to "authenticated";
grant truncate on table "public"."webhook_events" to "authenticated";
grant update on table "public"."webhook_events" to "authenticated";


-- Export Jobs Table
create table "public"."export_jobs" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "requested_by_user_id" uuid not null,
    "status" text not null default 'queued'::text,
    "download_url" text,
    "expires_at" timestamp with time zone,
    "error_message" text,
    "created_at" timestamp with time zone not null default now(),
    "completed_at" timestamp with time zone
);
alter table "public"."export_jobs" enable row level security;
CREATE UNIQUE INDEX export_jobs_pkey ON public.export_jobs USING btree (id);
alter table "public"."export_jobs" add constraint "export_jobs_pkey" PRIMARY KEY using index "export_jobs_pkey";
alter table "public"."export_jobs" add constraint "export_jobs_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table "public"."export_jobs" add constraint "export_jobs_requested_by_user_id_fkey" FOREIGN KEY (requested_by_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
grant delete on table "public"."export_jobs" to "authenticated";
grant insert on table "public"."export_jobs" to "authenticated";
grant references on table "public"."export_jobs" to "authenticated";
grant select on table "public"."export_jobs" to "authenticated";
grant trigger on table "public"."export_jobs" to "authenticated";
grant truncate on table "public"."export_jobs" to "authenticated";
grant update on table "public"."export_jobs" to "authenticated";

-- Imports Table
create table "public"."imports" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "created_by" uuid not null,
    "import_type" text not null,
    "file_name" text not null,
    "status" text not null default 'pending'::text,
    "total_rows" integer,
    "processed_rows" integer,
    "failed_rows" integer,
    "errors" jsonb,
    "summary" jsonb,
    "created_at" timestamp with time zone not null default now(),
    "completed_at" timestamp with time zone
);
alter table "public"."imports" enable row level security;
CREATE UNIQUE INDEX imports_pkey ON public.imports USING btree (id);
alter table "public"."imports" add constraint "imports_pkey" PRIMARY KEY using index "imports_pkey";
alter table "public"."imports" add constraint "imports_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table "public"."imports" add constraint "imports_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE CASCADE;
grant delete on table "public"."imports" to "authenticated";
grant insert on table "public"."imports" to "authenticated";
grant references on table "public"."imports" to "authenticated";
grant select on table "public"."imports" to "authenticated";
grant trigger on table "public"."imports" to "authenticated";
grant truncate on table "public"."imports" to "authenticated";
grant update on table "public"."imports" to "authenticated";


/****************************************************************
*                                                               *
*                    FUNCTIONS & TRIGGERS                       *
*                                                               *
****************************************************************/

-- Function to get company_id for the current user
create or replace function public.get_company_id_for_user(p_user_id uuid)
returns uuid
language sql
security definer
as $$
  select company_id from public.company_users where user_id = p_user_id limit 1;
$$;


-- Function to handle new user sign-ups
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
as $$
declare
  company_id uuid;
  company_name text;
begin
  -- Extract company name from metadata, default if not present
  company_name := coalesce(new.raw_user_meta_data->>'company_name', new.email);
  
  -- Create a new company for the user
  insert into public.companies (name, owner_id)
  values (company_name, new.id)
  returning id into company_id;

  -- Link the user to the new company as Owner
  insert into public.company_users (user_id, company_id, role)
  values (new.id, company_id, 'Owner');

  -- Update the user's app_metadata with the new company_id
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id, 'company_name', company_name)
  where id = new.id;
  
  return new;
end;
$$;

-- Trigger to call handle_new_user on new user creation
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Function to decrement inventory
create or replace function public.decrement_inventory_for_order(p_order_id uuid, p_company_id uuid)
returns void
language plpgsql
as $$
declare
    line_item record;
    current_stock integer;
begin
    for line_item in
        select oli.variant_id, oli.quantity
        from public.order_line_items oli
        where oli.order_id = p_order_id
        and oli.company_id = p_company_id
    loop
        if line_item.variant_id is not null then
            -- Check current stock
            select inventory_quantity into current_stock
            from public.product_variants
            where id = line_item.variant_id;

            -- Prevent inventory from going negative
            if current_stock is null or current_stock < line_item.quantity then
                raise exception 'Insufficient stock for variant ID %. Cannot fulfill order.', line_item.variant_id;
            end if;

            -- Update inventory quantity
            update public.product_variants
            set inventory_quantity = inventory_quantity - line_item.quantity
            where id = line_item.variant_id;

            -- Create a ledger entry
            insert into public.inventory_ledger(variant_id, company_id, change_type, quantity_change, new_quantity, related_id, notes)
            values (
                line_item.variant_id,
                p_company_id,
                'sale',
                -line_item.quantity,
                (select inventory_quantity from public.product_variants where id = line_item.variant_id),
                p_order_id,
                'Sale from order #' || (select order_number from public.orders where id = p_order_id)
            );
        end if;
    end loop;
end;
$$;

-- Trigger to decrement inventory after an order is created
create or replace function public.handle_order_creation()
returns trigger
language plpgsql
as $$
begin
  -- Call the function to decrement inventory
  perform public.decrement_inventory_for_order(new.id, new.company_id);
  return new;
end;
$$;

create trigger on_order_created
  after insert on public.orders
  for each row execute procedure public.handle_order_creation();

-- Function to check user permissions
create or replace function public.check_user_permission(p_user_id uuid, p_required_role company_role)
returns boolean
language plpgsql
security definer
as $$
declare
    user_role company_role;
begin
    select role into user_role from public.company_users where user_id = p_user_id;
    if user_role is null then
        return false;
    end if;
    if p_required_role = 'Owner' then
        return user_role = 'Owner';
    elsif p_required_role = 'Admin' then
        return user_role in ('Owner', 'Admin');
    end if;
    return true; -- If no specific role is required, or if role is 'Member'
end;
$$;

/****************************************************************
*                                                               *
*                     ROW LEVEL SECURITY                        *
*                                                               *
****************************************************************/

-- Generic RLS policy for tables with a company_id column
create or replace function create_company_based_rls(table_name text)
returns void as $$
begin
  execute format('
    alter table public.%I enable row level security;

    create policy "Allow full access to own company data"
    on public.%I
    for all
    using (company_id = (select public.get_company_id_for_user(auth.uid())))
    with check (company_id = (select public.get_company_id_for_user(auth.uid())));
  ', table_name, table_name);
end;
$$ language plpgsql;

-- Apply RLS to all company-scoped tables
select create_company_based_rls(table_name)
from information_schema.tables
where table_schema = 'public'
  and table_name not in ('company_users') -- Special handling for company_users
  and table_name not like 'pg_%'
  and table_name not like 'sql_%'
  and exists (
    select 1 from information_schema.columns
    where columns.table_name = tables.table_name and column_name = 'company_id'
  );

-- RLS for company_users table (users can see other users in their own company)
create policy "Users can see other members of their own company"
on "public"."company_users"
as permissive
for select
to authenticated
using ((company_id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user)));

-- RLS for company_users (Admins/Owners can manage users in their own company)
create policy "Admins can manage users in their own company"
on "public"."company_users"
as permissive
for insert, update, delete
to authenticated
using ((check_user_permission(auth.uid(), 'Admin'::company_role) AND (company_id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user))));
  

/****************************************************************
*                                                               *
*                           VIEWS                               *
*                                                               *
****************************************************************/

-- A view to unify product and variant details for easier querying
create or replace view "public"."product_variants_with_details" as
select
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url,
    p.product_type
from
    public.product_variants pv
join
    public.products p on pv.product_id = p.id;

-- A materialized view for performance on the unified product data
create materialized view "public"."product_variants_with_details_mat" as
select * from public.product_variants_with_details;
create unique index on public.product_variants_with_details_mat (id);


-- A view for customer analytics
create or replace view "public"."customers_view" as
select
    c.id,
    c.company_id,
    c.name as customer_name,
    c.email,
    count(o.id) as total_orders,
    sum(o.total_amount) as total_spent,
    min(o.created_at) as first_order_date,
    c.created_at
from
    public.customers c
left join
    public.orders o on c.id = o.customer_id
group by
    c.id, c.company_id;

-- A view for orders with customer email for easier searching
create or replace view public.orders_view as
select
    o.*,
    c.email as customer_email
from
    public.orders o
left join
    public.customers c on o.customer_id = c.id;
    

-- Function to refresh all materialized views for a specific company
-- Note: This is a simplified approach. For very large tables, consider CONCURRENTLY refresh.
create or replace function public.refresh_all_matviews(p_company_id uuid)
returns void as $$
begin
    refresh materialized view public.product_variants_with_details_mat;
    -- Add other materialized views here in the future
end;
$$ language plpgsql;

-- Grant usage on all functions to the authenticated role
grant execute on function public.handle_new_user() to authenticated;
grant execute on function public.get_company_id_for_user(uuid) to authenticated;
grant execute on function public.check_user_permission(uuid, company_role) to authenticated;
grant execute on function public.refresh_all_matviews(uuid) to authenticated;
grant execute on function public.decrement_inventory_for_order(uuid, uuid) to authenticated;
grant execute on function public.handle_order_creation() to authenticated;

-- Ensure the service_role can execute all functions
grant execute on all functions in schema public to service_role;
