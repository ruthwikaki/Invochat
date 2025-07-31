-- supabase/migrations/20240726120000_initial_schema.sql

-- 1. Enable UUID extension
create extension if not exists "uuid-ossp" with schema "extensions";

-- 2. Enumerated Types
create type "public"."company_role" as enum ('Owner', 'Admin', 'Member');
create type "public"."integration_platform" as enum ('shopify', 'woocommerce', 'amazon_fba');
create type "public"."message_role" as enum ('user', 'assistant', 'tool');
create type "public"."feedback_type" as enum ('helpful', 'unhelpful');


-- 3. Companies Table
create table "public"."companies" (
    "id" uuid not null default uuid_generate_v4(),
    "name" text not null,
    "created_at" timestamp with time zone not null default now(),
    "owner_id" uuid
);
alter table "public"."companies" enable row level security;
create unique index companies_pkey on public.companies using btree (id);
alter table "public"."companies" add constraint "companies_pkey" primary key using index "companies_pkey";
alter table "public"."companies" add constraint "companies_owner_id_fkey" foreign key (owner_id) references auth.users(id) on delete set null;


-- 4. Company Users Join Table (for roles)
create table "public"."company_users" (
    "company_id" uuid not null,
    "user_id" uuid not null,
    "role" company_role not null default 'Member'::company_role
);
alter table "public"."company_users" enable row level security;
create unique index company_users_pkey on public.company_users using btree (company_id, user_id);
alter table "public"."company_users" add constraint "company_users_pkey" primary key using index "company_users_pkey";
alter table "public"."company_users" add constraint "company_users_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;
alter table "public"."company_users" add constraint "company_users_user_id_fkey" foreign key (user_id) references auth.users(id) on delete cascade;


-- 5. Company Settings Table
create table "public"."company_settings" (
    "company_id" uuid not null,
    "dead_stock_days" integer not null default 90,
    "fast_moving_days" integer not null default 30,
    "predictive_stock_days" integer not null default 7,
    "currency" text default 'USD'::text,
    "timezone" text default 'UTC'::text,
    "tax_rate" numeric default 0,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone default null,
    "overstock_multiplier" integer not null default 3,
    "high_value_threshold" integer not null default 1000,
    "alert_settings" jsonb default '{"dismissal_hours": 24, "email_notifications": true, "enabled_alert_types": ["low_stock", "out_of_stock", "overstock"], "low_stock_threshold": 10, "morning_briefing_time": "09:00", "critical_stock_threshold": 5, "morning_briefing_enabled": true}'::jsonb
);
alter table "public"."company_settings" enable row level security;
create unique index company_settings_pkey on public.company_settings using btree (company_id);
alter table "public"."company_settings" add constraint "company_settings_pkey" primary key using index "company_settings_pkey";
alter table "public"."company_settings" add constraint "company_settings_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;


-- 6. Helper Function to Get User's Company ID
-- This function securely gets the company_id from the session JWT.
-- It is essential for RLS policies.
create or replace function public.get_company_id_for_user(p_user_id uuid)
returns uuid
language sql
security definer
set search_path = public
as $$
    select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'app_metadata', '')::jsonb ->> 'company_id' as "company_id"
$$;


-- 7. Suppliers Table
create table "public"."suppliers" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "name" text not null,
    "email" text,
    "phone" text,
    "default_lead_time_days" integer,
    "notes" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone default now()
);
alter table "public"."suppliers" enable row level security;
create unique index suppliers_pkey on public.suppliers using btree (id);
alter table "public"."suppliers" add constraint "suppliers_pkey" primary key using index "suppliers_pkey";
alter table "public"."suppliers" add constraint "suppliers_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;


-- 8. Products and Variants Tables
create table "public"."products" (
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
    "updated_at" timestamp with time zone,
    "deleted_at" timestamp with time zone
);
alter table "public"."products" enable row level security;
create unique index products_pkey on public.products using btree (id);
create unique index products_company_id_external_product_id_key on public.products using btree (company_id, external_product_id);
alter table "public"."products" add constraint "products_pkey" primary key using index "products_pkey";
alter table "public"."products" add constraint "products_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;

create table "public"."product_variants" (
    "id" uuid not null default gen_random_uuid(),
    "product_id" uuid not null,
    "company_id" uuid not null,
    "sku" text not null,
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
    "inventory_quantity" integer not null default 0,
    "supplier_id" uuid,
    "reorder_point" integer,
    "reorder_quantity" integer,
    "location" text,
    "external_variant_id" text,
    "created_at" timestamp with time zone default now(),
    "updated_at" timestamp with time zone default now(),
    "deleted_at" timestamp with time zone
);
alter table "public"."product_variants" enable row level security;
create unique index product_variants_pkey on public.product_variants using btree (id);
create unique index product_variants_company_id_sku_key on public.product_variants using btree (company_id, sku);
create unique index product_variants_company_id_external_variant_id_key on public.product_variants using btree (company_id, external_variant_id);
alter table "public"."product_variants" add constraint "product_variants_pkey" primary key using index "product_variants_pkey";
alter table "public"."product_variants" add constraint "product_variants_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;
alter table "public"."product_variants" add constraint "product_variants_product_id_fkey" foreign key (product_id) references products(id) on delete cascade;
alter table "public"."product_variants" add constraint "product_variants_supplier_id_fkey" foreign key (supplier_id) references suppliers(id) on delete set null;


-- 9. Customers Table
create table "public"."customers" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "name" text,
    "email" text,
    "phone" text,
    "external_customer_id" text,
    "created_at" timestamp with time zone default now(),
    "updated_at" timestamp with time zone,
    "deleted_at" timestamp with time zone
);
alter table "public"."customers" enable row level security;
create unique index customers_pkey on public.customers using btree (id);
create unique index customers_company_id_external_customer_id_key on public.customers using btree (company_id, external_customer_id);
alter table "public"."customers" add constraint "customers_pkey" primary key using index "customers_pkey";
alter table "public"."customers" add constraint "customers_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;


-- 10. Orders and Line Items Tables
create table "public"."orders" (
    "id" uuid not null default gen_random_uuid(),
    "company_id" uuid not null,
    "order_number" text not null,
    "external_order_id" text,
    "customer_id" uuid,
    "financial_status" text default 'pending'::text,
    "fulfillment_status" text default 'unfulfilled'::text,
    "currency" text default 'USD'::text,
    "subtotal" integer not null default 0,
    "total_tax" integer default 0,
    "total_shipping" integer default 0,
    "total_discounts" integer default 0,
    "total_amount" integer not null,
    "source_platform" text,
    "created_at" timestamp with time zone default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."orders" enable row level security;
create unique index orders_pkey on public.orders using btree (id);
create unique index orders_company_id_external_order_id_key on public.orders using btree (company_id, external_order_id);
alter table "public"."orders" add constraint "orders_pkey" primary key using index "orders_pkey";
alter table "public"."orders" add constraint "orders_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;
alter table "public"."orders" add constraint "orders_customer_id_fkey" foreign key (customer_id) references customers(id) on delete set null;

create table "public"."order_line_items" (
    "id" uuid not null default gen_random_uuid(),
    "order_id" uuid not null,
    "variant_id" uuid,
    "company_id" uuid not null,
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
create unique index order_line_items_pkey on public.order_line_items using btree (id);
alter table "public"."order_line_items" add constraint "order_line_items_pkey" primary key using index "order_line_items_pkey";
alter table "public"."order_line_items" add constraint "order_line_items_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;
alter table "public"."order_line_items" add constraint "order_line_items_order_id_fkey" foreign key (order_id) references orders(id) on delete cascade;
alter table "public"."order_line_items" add constraint "order_line_items_variant_id_fkey" foreign key (variant_id) references product_variants(id) on delete set null;


-- 11. Purchase Orders and Line Items Tables
create table "public"."purchase_orders" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "supplier_id" uuid,
    "status" text not null default 'Draft'::text,
    "po_number" text not null,
    "total_cost" integer not null,
    "expected_arrival_date" date,
    "notes" text,
    "idempotency_key" uuid,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."purchase_orders" enable row level security;
create unique index purchase_orders_pkey on public.purchase_orders using btree (id);
alter table "public"."purchase_orders" add constraint "purchase_orders_pkey" primary key using index "purchase_orders_pkey";
alter table "public"."purchase_orders" add constraint "purchase_orders_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;
alter table "public"."purchase_orders" add constraint "purchase_orders_supplier_id_fkey" foreign key (supplier_id) references suppliers(id) on delete set null;

create table "public"."purchase_order_line_items" (
    "id" uuid not null default uuid_generate_v4(),
    "purchase_order_id" uuid not null,
    "variant_id" uuid not null,
    "quantity" integer not null,
    "cost" integer not null,
    "company_id" uuid not null
);
alter table "public"."purchase_order_line_items" enable row level security;
create unique index purchase_order_line_items_pkey on public.purchase_order_line_items using btree (id);
alter table "public"."purchase_order_line_items" add constraint "purchase_order_line_items_pkey" primary key using index "purchase_order_line_items_pkey";
alter table "public"."purchase_order_line_items" add constraint "purchase_order_line_items_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;
alter table "public"."purchase_order_line_items" add constraint "purchase_order_line_items_purchase_order_id_fkey" foreign key (purchase_order_id) references purchase_orders(id) on delete cascade;
alter table "public"."purchase_order_line_items" add constraint "purchase_order_line_items_variant_id_fkey" foreign key (variant_id) references product_variants(id) on delete cascade;


-- 12. Integrations Table
create table "public"."integrations" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "platform" integration_platform not null,
    "shop_domain" text,
    "shop_name" text,
    "is_active" boolean default false,
    "last_sync_at" timestamp with time zone,
    "sync_status" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."integrations" enable row level security;
create unique index integrations_pkey on public.integrations using btree (id);
create unique index integrations_company_id_platform_key on public.integrations using btree (company_id, platform);
alter table "public"."integrations" add constraint "integrations_pkey" primary key using index "integrations_pkey";
alter table "public"."integrations" add constraint "integrations_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;

-- 13. AI-related Tables (Conversations, Messages, Feedback)
create table "public"."conversations" (
    "id" uuid not null default uuid_generate_v4(),
    "user_id" uuid not null,
    "company_id" uuid not null,
    "title" text not null,
    "created_at" timestamp with time zone default now(),
    "last_accessed_at" timestamp with time zone default now(),
    "is_starred" boolean default false
);
alter table "public"."conversations" enable row level security;
create unique index conversations_pkey on public.conversations using btree (id);
alter table "public"."conversations" add constraint "conversations_pkey" primary key using index "conversations_pkey";
alter table "public"."conversations" add constraint "conversations_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;
alter table "public"."conversations" add constraint "conversations_user_id_fkey" foreign key (user_id) references auth.users(id) on delete cascade;

create table "public"."messages" (
    "id" uuid not null default uuid_generate_v4(),
    "conversation_id" uuid not null,
    "company_id" uuid not null,
    "role" message_role not null,
    "content" text not null,
    "visualization" jsonb,
    "component" text,
    "component_props" jsonb,
    "confidence" numeric,
    "assumptions" text[],
    "is_error" boolean default false,
    "created_at" timestamp with time zone default now()
);
alter table "public"."messages" enable row level security;
create unique index messages_pkey on public.messages using btree (id);
alter table "public"."messages" add constraint "messages_pkey" primary key using index "messages_pkey";
alter table "public"."messages" add constraint "messages_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;
alter table "public"."messages" add constraint "messages_conversation_id_fkey" foreign key (conversation_id) references conversations(id) on delete cascade;

create table "public"."feedback" (
    "id" uuid not null default gen_random_uuid(),
    "user_id" uuid not null,
    "company_id" uuid not null,
    "subject_id" text not null,
    "subject_type" text not null,
    "feedback" feedback_type not null,
    "created_at" timestamp with time zone default now()
);
alter table "public"."feedback" enable row level security;
create unique index feedback_pkey on public.feedback using btree (id);
alter table "public"."feedback" add constraint "feedback_pkey" primary key using index "feedback_pkey";
alter table "public"."feedback" add constraint "feedback_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;
alter table "public"."feedback" add constraint "feedback_user_id_fkey" foreign key (user_id) references auth.users(id) on delete cascade;


-- 14. Audit Log Table
create table "public"."audit_log" (
    "id" uuid not null default gen_random_uuid(),
    "company_id" uuid not null,
    "user_id" uuid,
    "action" text not null,
    "details" jsonb,
    "created_at" timestamp with time zone default now()
);
alter table "public"."audit_log" enable row level security;
create index audit_log_company_id_idx on public.audit_log using btree (company_id);
create unique index audit_log_pkey on public.audit_log using btree (id);
alter table "public"."audit_log" add constraint "audit_log_pkey" primary key using index "audit_log_pkey";
alter table "public"."audit_log" add constraint "audit_log_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;
alter table "public"."audit_log" add constraint "audit_log_user_id_fkey" foreign key (user_id) references auth.users(id) on delete set null;

-- 15. Channel Fees Table
create table "public"."channel_fees" (
    "id" uuid not null default uuid_generate_v4(),
    "company_id" uuid not null,
    "channel_name" text not null,
    "percentage_fee" numeric,
    "fixed_fee" integer, -- in cents
    "created_at" timestamp with time zone default now(),
    "updated_at" timestamp with time zone
);
alter table "public"."channel_fees" enable row level security;
create unique index channel_fees_pkey on public.channel_fees using btree (id);
create unique index channel_fees_company_id_channel_name_key on public.channel_fees using btree (company_id, channel_name);
alter table "public"."channel_fees" add constraint "channel_fees_pkey" primary key using index "channel_fees_pkey";
alter table "public"."channel_fees" add constraint "channel_fees_company_id_fkey" foreign key (company_id) references companies(id) on delete cascade;

-- 16. Webhook Events Table
create table "public"."webhook_events" (
    "id" uuid not null default gen_random_uuid(),
    "integration_id" uuid not null,
    "webhook_id" text not null,
    "created_at" timestamp with time zone default now()
);
alter table "public"."webhook_events" enable row level security;
create unique index webhook_events_pkey on public.webhook_events using btree (id);
create unique index webhook_events_integration_id_webhook_id_key on public.webhook_events using btree (integration_id, webhook_id);
alter table "public"."webhook_events" add constraint "webhook_events_pkey" primary key using index "webhook_events_pkey";
alter table "public"."webhook_events" add constraint "webhook_events_integration_id_fkey" foreign key (integration_id) references integrations(id) on delete cascade;


-- =================================================================
-- RLS POLICIES
-- =================================================================

-- Generic policy for most tables: User must be part of the company.
create policy "Enable access for company members" on "public"."companies" for select using (id = get_company_id_for_user(auth.uid()));
create policy "Enable access for company members" on "public"."company_users" for select using (company_id = get_company_id_for_user(auth.uid()));
create policy "Enable access for company members" on "public"."company_settings" for all using (company_id = get_company_id_for_user(auth.uid()));
create policy "Enable access for company members" on "public"."suppliers" for all using (company_id = get_company_id_for_user(auth.uid()));
create policy "Enable access for company members" on "public"."products" for all using (company_id = get_company_id_for_user(auth.uid()));
create policy "Enable access for company members" on "public"."product_variants" for all using (company_id = get_company_id_for_user(auth.uid()));
create policy "Enable access for company members" on "public"."customers" for all using (company_id = get_company_id_for_user(auth.uid()));
create policy "Enable access for company members" on "public"."orders" for all using (company_id = get_company_id_for_user(auth.uid()));
create policy "Enable access for company members" on "public"."order_line_items" for all using (company_id = get_company_id_for_user(auth.uid()));
create policy "Enable access for company members" on "public"."purchase_orders" for all using (company_id = get_company_id_for_user(auth.uid()));
create policy "Enable access for company members" on "public"."purchase_order_line_items" for all using (company_id = get_company_id_for_user(auth.uid()));
create policy "Enable access for company members" on "public"."integrations" for all using (company_id = get_company_id_for_user(auth.uid()));
create policy "Enable access for company members" on "public"."conversations" for all using (company_id = get_company_id_for_user(auth.uid()));
create policy "Enable access for company members" on "public"."messages" for all using (company_id = get_company_id_for_user(auth.uid()));
create policy "Enable access for company members" on "public"."audit_log" for select using (company_id = get_company_id_for_user(auth.uid()));
create policy "Enable access for company members" on "public"."channel_fees" for all using (company_id = get_company_id_for_user(auth.uid()));
create policy "Enable access for feedback" on "public"."feedback" for all using (company_id = get_company_id_for_user(auth.uid()));

-- Policy for webhook events: any authenticated user can insert if they know the integration ID
alter table "public"."webhook_events" drop constraint if exists "webhook_events_integration_id_fkey";
alter table "public"."webhook_events" add constraint "webhook_events_integration_id_fkey" foreign key ("integration_id") references "public"."integrations"("id") on delete cascade;
create policy "Allow insert for authenticated users" on "public"."webhook_events" for insert to authenticated with check (true);


-- =================================================================
-- TRIGGERS AND FUNCTIONS
-- =================================================================

-- 1. Function to create a company and link it to the new user on signup
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  new_company_id uuid;
  user_company_name text;
begin
  -- Extract company name from user metadata, fallback to a default
  user_company_name := new.raw_user_meta_data ->> 'company_name';
  if user_company_name is null or user_company_name = '' then
    user_company_name := new.email;
  end if;

  -- Create a new company for the new user
  insert into public.companies (name, owner_id)
  values (user_company_name, new.id)
  returning id into new_company_id;

  -- Link the new user to the new company as 'Owner'
  insert into public.company_users (user_id, company_id, role)
  values (new.id, new_company_id, 'Owner');

  -- Update the user's app_metadata with the new company_id
  -- This is critical for RLS policies
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
  where id = new.id;
  
  -- Create default settings for the new company
  insert into public.company_settings (company_id)
  values (new_company_id);

  return new;
end;
$$;

-- 2. Trigger to call handle_new_user on new user creation
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- 3. Function to update `updated_at` timestamps automatically
create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

-- 4. Triggers for `updated_at`
create trigger handle_updated_at before update on public.companies for each row execute procedure public.set_updated_at();
create trigger handle_updated_at before update on public.company_settings for each row execute procedure public.set_updated_at();
create trigger handle_updated_at before update on public.suppliers for each row execute procedure public.set_updated_at();
create trigger handle_updated_at before update on public.products for each row execute procedure public.set_updated_at();
create trigger handle_updated_at before update on public.product_variants for each row execute procedure public.set_updated_at();
create trigger handle_updated_at before update on public.customers for each row execute procedure public.set_updated_at();
create trigger handle_updated_at before update on public.orders for each row execute procedure public.set_updated_at();
create trigger handle_updated_at before update on public.purchase_orders for each row execute procedure public.set_updated_at();
create trigger handle_updated_at before update on public.integrations for each row execute procedure public.set_updated_at();
create trigger handle_updated_at before update on public.channel_fees for each row execute procedure public.set_updated_at();

-- 5. Function to automatically create an audit log entry on certain table changes
CREATE OR REPLACE FUNCTION log_change()
RETURNS TRIGGER AS $$
DECLARE
    audit_details jsonb;
    action_type TEXT;
BEGIN
    action_type := TG_OP; -- INSERT, UPDATE, DELETE

    IF (TG_OP = 'UPDATE') THEN
        audit_details := jsonb_build_object('old', to_jsonb(OLD), 'new', to_jsonb(NEW));
    ELSIF (TG_OP = 'DELETE') THEN
        audit_details := jsonb_build_object('deleted', to_jsonb(OLD));
    ELSIF (TG_OP = 'INSERT') THEN
        audit_details := jsonb_build_object('new', to_jsonb(NEW));
    END IF;

    INSERT INTO public.audit_log (company_id, user_id, action, details)
    VALUES (
        NEW.company_id,
        auth.uid(),
        action_type || '_' || TG_TABLE_NAME,
        audit_details
    );

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- 6. Trigger for audit log (Example for suppliers)
-- You can add more triggers for other tables as needed.
CREATE TRIGGER suppliers_audit_trigger
AFTER INSERT OR UPDATE OR DELETE ON public.suppliers
FOR EACH ROW EXECUTE FUNCTION log_change();
