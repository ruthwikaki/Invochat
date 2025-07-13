
-- Enable UUID extension
create extension if not exists "uuid-ossp" with schema "extensions";

-- #################################################################
-- #############            TABLES            ######################
-- #################################################################

-- Table: companies
create table if not exists "public"."companies" (
    "id" uuid not null default uuid_generate_v4(),
    "name" text not null,
    "created_at" timestamp with time zone not null default now()
);
alter table "public"."companies" enable row level security;
CREATE UNIQUE INDEX companies_pkey ON public.companies USING btree (id);
alter table "public"."companies" add constraint "companies_pkey" PRIMARY KEY using index "companies_pkey";


-- Table: users (custom user data)
create table if not exists "public"."users" (
    "id" uuid not null,
    "company_id" uuid not null,
    "email" text,
    "role" text default 'member'::text,
    "deleted_at" timestamp with time zone,
    "created_at" timestamp with time zone default now()
);
alter table "public"."users" enable row level security;
CREATE UNIQUE INDEX users_pkey ON public.users USING btree (id);
alter table "public"."users" add constraint "users_pkey" PRIMARY KEY using index "users_pkey";
alter table "public"."users" add constraint "users_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;
alter table "public"."users" validate constraint "users_company_id_fkey";
alter table "public"."users" add constraint "users_id_fkey" FOREIGN KEY (id) REFERENCES auth.users(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;
alter table "public"."users" validate constraint "users_id_fkey";


-- Table: company_settings
create table if not exists "public"."company_settings" (
    "company_id" uuid not null,
    "dead_stock_days" integer not null default 90,
    "overstock_multiplier" integer not null default 3,
    "high_value_threshold" integer not null default 1000,
    "fast_moving_days" integer not null default 30,
    "predictive_stock_days" integer not null default 7,
    "currency" text default 'USD'::text,
    "timezone" text default 'UTC'::text,
    "tax_rate" numeric default 0,
    "custom_rules" jsonb,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone,
    "subscription_status" text default 'trial'::text,
    "subscription_plan" text default 'starter'::text,
    "subscription_expires_at" timestamp with time zone,
    "stripe_customer_id" text,
    "stripe_subscription_id" text,
    "promo_sales_lift_multiplier" real not null default 2.5
);
alter table "public"."company_settings" enable row level security;
CREATE UNIQUE INDEX company_settings_pkey ON public.company_settings USING btree (company_id);
alter table "public"."company_settings" add constraint "company_settings_pkey" PRIMARY KEY using index "company_settings_pkey";
alter table "public"."company_settings" add constraint "company_settings_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;
alter table "public"."company_settings" validate constraint "company_settings_company_id_fkey";


-- Table: products
create table if not exists "public"."products" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "title" text not null,
    "description" text,
    "handle" text,
    "product_type" text,
    "tags" text[],
    "status" text,
    "image_url" text,
    "external_product_id" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."products" enable row level security;
CREATE UNIQUE INDEX products_pkey ON public.products USING btree (id);
CREATE UNIQUE INDEX products_company_external_id_unique ON public.products USING btree (company_id, external_product_id) WHERE (external_product_id IS NOT NULL);
alter table "public"."products" add constraint "products_pkey" PRIMARY KEY using index "products_pkey";
alter table "public"."products" add constraint "products_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;
alter table "public"."products" validate constraint "products_company_id_fkey";


-- Table: product_variants
create table if not exists "public"."product_variants" (
    "id" uuid not null default gen_random_uuid(),
    "product_id" uuid not null,
    "company_id" uuid not null,
    "sku" text,
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
    "weight" numeric,
    "weight_unit" text,
    "inventory_quantity" integer default 0,
    "external_variant_id" text,
    "created_at" timestamp with time zone default now(),
    "updated_at" timestamp with time zone default now()
);
alter table "public"."product_variants" enable row level security;
CREATE UNIQUE INDEX product_variants_pkey ON public.product_variants USING btree (id);
CREATE INDEX product_variants_company_id_idx ON public.product_variants USING btree (company_id);
CREATE UNIQUE INDEX product_variants_company_id_sku_key ON public.product_variants USING btree (company_id, sku) WHERE (sku IS NOT NULL);
alter table "public"."product_variants" add constraint "product_variants_pkey" PRIMARY KEY using index "product_variants_pkey";
alter table "public"."product_variants" add constraint "product_variants_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;
alter table "public"."product_variants" validate constraint "product_variants_company_id_fkey";
alter table "public"."product_variants" add constraint "product_variants_product_id_fkey" FOREIGN KEY (product_id) REFERENCES products(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;
alter table "public"."product_variants" validate constraint "product_variants_product_id_fkey";


-- Table: suppliers
create table if not exists "public"."suppliers" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "name" text not null,
    "email" text,
    "phone" text,
    "default_lead_time_days" integer,
    "notes" text,
    "created_at" timestamp with time zone not null default now()
);
alter table "public"."suppliers" enable row level security;
CREATE UNIQUE INDEX suppliers_pkey ON public.suppliers USING btree (id);
alter table "public"."suppliers" add constraint "suppliers_pkey" PRIMARY KEY using index "suppliers_pkey";
alter table "public"."suppliers" add constraint "suppliers_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;
alter table "public"."suppliers" validate constraint "suppliers_company_id_fkey";


-- Table: inventory_ledger
create table if not exists "public"."inventory_ledger" (
    "id" uuid not null default gen_random_uuid(),
    "company_id" uuid not null,
    "variant_id" uuid not null,
    "change_type" text not null,
    "quantity_change" integer not null,
    "new_quantity" integer not null,
    "related_id" uuid,
    "notes" text,
    "created_at" timestamp with time zone not null default now()
);
alter table "public"."inventory_ledger" enable row level security;
CREATE UNIQUE INDEX inventory_ledger_pkey ON public.inventory_ledger USING btree (id);
CREATE INDEX inventory_ledger_variant_id_idx ON public.inventory_ledger USING btree (variant_id);
alter table "public"."inventory_ledger" add constraint "inventory_ledger_pkey" PRIMARY KEY using index "inventory_ledger_pkey";
alter table "public"."inventory_ledger" add constraint "inventory_ledger_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;
alter table "public"."inventory_ledger" validate constraint "inventory_ledger_company_id_fkey";
alter table "public"."inventory_ledger" add constraint "inventory_ledger_variant_id_fkey" FOREIGN KEY (variant_id) REFERENCES product_variants(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;
alter table "public"."inventory_ledger" validate constraint "inventory_ledger_variant_id_fkey";


-- Table: customers
create table if not exists "public"."customers" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "customer_name" text,
    "email" text,
    "total_orders" integer default 0,
    "total_spent" integer default 0,
    "first_order_date" date,
    "deleted_at" timestamp with time zone,
    "created_at" timestamp with time zone default now()
);
alter table "public"."customers" enable row level security;
CREATE UNIQUE INDEX customers_pkey ON public.customers USING btree (id);
CREATE UNIQUE INDEX customers_company_id_email_key ON public.customers USING btree (company_id, email);
alter table "public"."customers" add constraint "customers_pkey" PRIMARY KEY using index "customers_pkey";
alter table "public"."customers" add constraint "customers_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;
alter table "public"."customers" validate constraint "customers_company_id_fkey";


-- Table: customer_addresses
create table if not exists "public"."customer_addresses" (
    "id" uuid not null default gen_random_uuid(),
    "customer_id" uuid not null,
    "address_type" text not null default 'shipping'::text,
    "first_name" text,
    "last_name" text,
    "company" text,
    "address1" text,
    "address2" text,
    "city" text,
    "province_code" text,
    "country_code" text,
    "zip" text,
    "phone" text,
    "is_default" boolean default false
);
alter table "public"."customer_addresses" enable row level security;
CREATE UNIQUE INDEX customer_addresses_pkey ON public.customer_addresses USING btree (id);
alter table "public"."customer_addresses" add constraint "customer_addresses_pkey" PRIMARY KEY using index "customer_addresses_pkey";
alter table "public"."customer_addresses" add constraint "customer_addresses_customer_id_fkey" FOREIGN KEY (customer_id) REFERENCES customers(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;
alter table "public"."customer_addresses" validate constraint "customer_addresses_customer_id_fkey";


-- Table: orders
create table if not exists "public"."orders" (
    "id" uuid not null default gen_random_uuid(),
    "company_id" uuid not null,
    "order_number" text not null,
    "external_order_id" text,
    "customer_id" uuid,
    "status" text not null default 'pending'::text,
    "financial_status" text default 'pending'::text,
    "fulfillment_status" text default 'unfulfilled'::text,
    "currency" text default 'USD'::text,
    "subtotal" integer not null default 0,
    "total_tax" integer default 0,
    "total_shipping" integer default 0,
    "total_discounts" integer default 0,
    "total_amount" integer not null,
    "source_platform" text,
    "source_name" text,
    "tags" text[],
    "notes" text,
    "cancelled_at" timestamp with time zone,
    "created_at" timestamp with time zone default now(),
    "updated_at" timestamp with time zone default now()
);
alter table "public"."orders" enable row level security;
CREATE UNIQUE INDEX orders_pkey ON public.orders USING btree (id);
alter table "public"."orders" add constraint "orders_pkey" PRIMARY KEY using index "orders_pkey";
alter table "public"."orders" add constraint "orders_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;
alter table "public"."orders" validate constraint "orders_company_id_fkey";
alter table "public"."orders" add constraint "orders_customer_id_fkey" FOREIGN KEY (customer_id) REFERENCES customers(id) ON UPDATE CASCADE ON DELETE SET NULL not valid;
alter table "public"."orders" validate constraint "orders_customer_id_fkey";


-- Table: order_line_items
create table if not exists "public"."order_line_items" (
    "id" uuid not null default gen_random_uuid(),
    "order_id" uuid not null,
    "company_id" uuid not null,
    "variant_id" uuid,
    "product_name" text,
    "variant_title" text,
    "sku" text,
    "quantity" integer not null,
    "price" integer not null,
    "total_discount" integer default 0,
    "tax_amount" integer default 0,
    "cost_at_time" integer,
    "external_line_item_id" text
);
alter table "public"."order_line_items" enable row level security;
CREATE UNIQUE INDEX order_line_items_pkey ON public.order_line_items USING btree (id);
alter table "public"."order_line_items" add constraint "order_line_items_pkey" PRIMARY KEY using index "order_line_items_pkey";
alter table "public"."order_line_items" add constraint "order_line_items_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;
alter table "public"."order_line_items" validate constraint "order_line_items_company_id_fkey";
alter table "public"."order_line_items" add constraint "order_line_items_order_id_fkey" FOREIGN KEY (order_id) REFERENCES orders(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;
alter table "public"."order_line_items" validate constraint "order_line_items_order_id_fkey";
alter table "public"."order_line_items" add constraint "order_line_items_variant_id_fkey" FOREIGN KEY (variant_id) REFERENCES product_variants(id) ON UPDATE CASCADE ON DELETE SET NULL not valid;
alter table "public"."order_line_items" validate constraint "order_line_items_variant_id_fkey";


-- Table: conversations
create table if not exists "public"."conversations" (
    "id" uuid not null default uuid_generate_v4(),
    "user_id" uuid not null,
    "company_id" uuid not null,
    "title" text not null,
    "created_at" timestamp with time zone default now(),
    "last_accessed_at" timestamp with time zone default now(),
    "is_starred" boolean default false
);
alter table "public"."conversations" enable row level security;
CREATE UNIQUE INDEX conversations_pkey ON public.conversations USING btree (id);
alter table "public"."conversations" add constraint "conversations_pkey" PRIMARY KEY using index "conversations_pkey";
alter table "public"."conversations" add constraint "conversations_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;
alter table "public"."conversations" validate constraint "conversations_company_id_fkey";
alter table "public"."conversations" add constraint "conversations_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;
alter table "public"."conversations" validate constraint "conversations_user_id_fkey";


-- Table: messages
create table if not exists "public"."messages" (
    "id" uuid not null default uuid_generate_v4(),
    "conversation_id" uuid not null,
    "company_id" uuid not null,
    "role" text not null,
    "content" text,
    "component" text,
    "component_props" jsonb,
    "visualization" jsonb,
    "confidence" numeric,
    "assumptions" text[],
    "is_error" boolean default false,
    "created_at" timestamp with time zone default now()
);
alter table "public"."messages" enable row level security;
CREATE UNIQUE INDEX messages_pkey ON public.messages USING btree (id);
alter table "public"."messages" add constraint "messages_pkey" PRIMARY KEY using index "messages_pkey";
alter table "public"."messages" add constraint "messages_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;
alter table "public"."messages" validate constraint "messages_company_id_fkey";
alter table "public"."messages" add constraint "messages_conversation_id_fkey" FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;
alter table "public"."messages" validate constraint "messages_conversation_id_fkey";


-- Table: integrations
create table if not exists "public"."integrations" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "platform" text not null,
    "shop_domain" text,
    "shop_name" text,
    "is_active" boolean default false,
    "last_sync_at" timestamp with time zone,
    "sync_status" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."integrations" enable row level security;
CREATE UNIQUE INDEX integrations_pkey ON public.integrations USING btree (id);
CREATE UNIQUE INDEX integrations_company_platform_unique ON public.integrations USING btree (company_id, platform);
alter table "public"."integrations" add constraint "integrations_pkey" PRIMARY KEY using index "integrations_pkey";
alter table "public"."integrations" add constraint "integrations_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;
alter table "public"."integrations" validate constraint "integrations_company_id_fkey";


-- Table: webhook_events
create table if not exists "public"."webhook_events" (
    "id" uuid not null default gen_random_uuid(),
    "integration_id" uuid not null,
    "webhook_id" text not null,
    "created_at" timestamp with time zone default now()
);
alter table "public"."webhook_events" enable row level security;
CREATE UNIQUE INDEX webhook_events_pkey ON public.webhook_events USING btree (id);
CREATE UNIQUE INDEX webhook_events_integration_id_webhook_id_key ON public.webhook_events USING btree (integration_id, webhook_id);
alter table "public"."webhook_events" add constraint "webhook_events_pkey" PRIMARY KEY using index "webhook_events_pkey";
alter table "public"."webhook_events" add constraint "webhook_events_integration_id_fkey" FOREIGN KEY (integration_id) REFERENCES integrations(id) ON DELETE CASCADE;


-- Table: audit_log
create table if not exists "public"."audit_log" (
    "id" bigserial primary key,
    "company_id" uuid,
    "user_id" uuid,
    "action" text not null,
    "details" jsonb,
    "created_at" timestamp with time zone default now()
);
alter table "public"."audit_log" enable row level security;
alter table "public"."audit_log" add constraint "audit_log_company_id_fkey" FOREIGN KEY (company_id) REFERENCES companies(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;
alter table "public"."audit_log" validate constraint "audit_log_company_id_fkey";
alter table "public"."audit_log" add constraint "audit_log_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON UPDATE CASCADE ON DELETE SET NULL not valid;
alter table "public"."audit_log" validate constraint "audit_log_user_id_fkey";


-- #################################################################
-- ############      FUNCTIONS & TRIGGERS       ####################
-- #################################################################

-- Get company_id from session claims
create or replace function get_current_company_id()
returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;


-- Handle new user signup
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  new_company_id uuid;
  company_name_from_meta text;
begin
  -- Create a new company for the new user
  company_name_from_meta := new.raw_app_meta_data->>'company_name';
  if company_name_from_meta is null or company_name_from_meta = '' then
    company_name_from_meta := new.email || '''s Company';
  end if;

  insert into public.companies (name)
  values (company_name_from_meta)
  returning id into new_company_id;

  -- Create a user record in the public users table
  insert into public.users (id, company_id, email, role)
  values (new.id, new_company_id, new.email, 'Owner');

  -- Update the user's app_metadata with the new company_id
  update auth.users
  set raw_app_meta_data = jsonb_set(
    new.raw_app_meta_data,
    '{company_id}',
    to_jsonb(new_company_id),
    true
  ) || jsonb_set(
    new.raw_app_meta_data,
    '{role}',
    to_jsonb('Owner'::text),
    true
  )
  where id = new.id;

  return new;
end;
$$;

-- Trigger for handle_new_user
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  when (new.raw_app_meta_data->>'is_invited_user' is null)
  execute procedure public.handle_new_user();


-- #################################################################
-- ############        ROW LEVEL SECURITY        ###################
-- #################################################################

-- Policies for companies
alter table "public"."companies" drop constraint if exists "companies_id_fkey";
drop policy if exists "Allow read access to own company" on "public"."companies";
create policy "Allow read access to own company" on "public"."companies"
as permissive for select to authenticated using (id = get_current_company_id());

-- Policies for users
drop policy if exists "Allow owner to see their own team" on "public"."users";
create policy "Allow owner to see their own team" on "public"."users"
as permissive for select to authenticated using (company_id = get_current_company_id());

-- Policies for company_settings
drop policy if exists "Allow full access to own settings" on "public"."company_settings";
create policy "Allow full access to own settings" on "public"."company_settings"
as permissive for all to authenticated using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

-- Policies for products
drop policy if exists "Allow full access to own products" on "public"."products";
create policy "Allow full access to own products" on "public"."products"
as permissive for all to authenticated using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

-- Policies for product_variants
drop policy if exists "Allow full access to own product_variants" on "public"."product_variants";
create policy "Allow full access to own product_variants" on "public"."product_variants"
as permissive for all to authenticated using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

-- Policies for suppliers
drop policy if exists "Allow full access to own suppliers" on "public"."suppliers";
create policy "Allow full access to own suppliers" on "public"."suppliers"
as permissive for all to authenticated using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

-- Policies for inventory_ledger
drop policy if exists "Allow full access to own ledger" on "public"."inventory_ledger";
create policy "Allow full access to own ledger" on "public"."inventory_ledger"
as permissive for all to authenticated using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

-- Policies for customers
drop policy if exists "Allow full access to own customers" on "public"."customers";
create policy "Allow full access to own customers" on "public"."customers"
as permissive for all to authenticated using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

-- Policies for customer_addresses
drop policy if exists "Allow access to own company addresses" on "public"."customer_addresses";
create policy "Allow access to own company addresses" on "public"."customer_addresses"
as permissive for all to authenticated
using ((select company_id from public.customers where id = customer_addresses.customer_id) = get_current_company_id())
with check ((select company_id from public.customers where id = customer_addresses.customer_id) = get_current_company_id());

-- Policies for orders
drop policy if exists "Allow full access to own orders" on "public"."orders";
create policy "Allow full access to own orders" on "public"."orders"
as permissive for all to authenticated using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

-- Policies for order_line_items
drop policy if exists "Allow full access to own line items" on "public"."order_line_items";
create policy "Allow full access to own line items" on "public"."order_line_items"
as permissive for all to authenticated using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

-- Policies for conversations
drop policy if exists "Allow access to own conversations" on "public"."conversations";
create policy "Allow access to own conversations" on "public"."conversations"
as permissive for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Policies for messages
drop policy if exists "Allow access to own messages" on "public"."messages";
create policy "Allow access to own messages" on "public"."messages"
as permissive for all to authenticated using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

-- Policies for integrations
drop policy if exists "Allow full access to own integrations" on "public"."integrations";
create policy "Allow full access to own integrations" on "public"."integrations"
as permissive for all to authenticated using (company_id = get_current_company_id()) with check (company_id = get_current_company_id());

-- Policies for webhook_events
drop policy if exists "Allow full access to own webhook events" on "public"."webhook_events";
create policy "Allow full access to own webhook events" on "public"."webhook_events"
as permissive for all to authenticated
using ((select company_id from public.integrations where id = webhook_events.integration_id) = get_current_company_id())
with check ((select company_id from public.integrations where id = webhook_events.integration_id) = get_current_company_id());

-- Policies for audit_log
drop policy if exists "Allow admins to read audit log" on "public"."audit_log";
create policy "Allow admins to read audit log" on "public"."audit_log"
as permissive for select to authenticated
using (company_id = get_current_company_id());

-- Make sure service_role can bypass RLS
alter table public.companies bypass row level security;
alter table public.users bypass row level security;
alter table public.company_settings bypass row level security;
alter table public.products bypass row level security;
alter table public.product_variants bypass row level security;
alter table public.suppliers bypass row level security;
alter table public.inventory_ledger bypass row level security;
alter table public.customers bypass row level security;
alter table public.customer_addresses bypass row level security;
alter table public.orders bypass row level security;
alter table public.order_line_items bypass row level security;
alter table public.conversations bypass row level security;
alter table public.messages bypass row level security;
alter table public.integrations bypass row level security;
alter table public.webhook_events bypass row level security;
alter table public.audit_log bypass row level security;
