
-- ### Crunched: Squeezing your SQL into a single file.
-- ### For more info, see https://github.com/elibosley/crunched


-- public.company_role
drop type if exists public.company_role;
create type public.company_role as enum ('Owner', 'Admin', 'Member');

-- public.feedback_type
drop type if exists public.feedback_type;
create type public.feedback_type as enum ('helpful', 'unhelpful');

-- public.integration_platform
drop type if exists public.integration_platform;
create type public.integration_platform as enum ('shopify', 'woocommerce', 'amazon_fba');

-- public.message_role
drop type if exists public.message_role;
create type public.message_role as enum ('user', 'assistant', 'tool');

-- public.companies
drop table if exists public.companies;
create table public.companies (
  id uuid default gen_random_uuid() not null,
  created_at timestamp with time zone default now() not null,
  name text not null,
  owner_id uuid not null
);
alter table public.companies add constraint companies_name_check check ((length(name) > 0));

-- public.company_settings
drop table if exists public.company_settings;
create table public.company_settings (
  company_id uuid not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone null,
  dead_stock_days integer default 90 not null,
  fast_moving_days integer default 30 not null,
  predictive_stock_days integer default 7 not null,
  currency text default 'USD'::text not null,
  timezone text default 'UTC'::text not null,
  overstock_multiplier real default 3 not null,
  high_value_threshold integer default 100000 not null,
  tax_rate real default 0 not null
);

-- public.company_users
drop table if exists public.company_users;
create table public.company_users (
  user_id uuid not null,
  company_id uuid not null,
  role public.company_role default 'Member'::public.company_role not null
);

-- public.customers
drop table if exists public.customers;
create table public.customers (
  id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  external_customer_id text null,
  name text null,
  email text null,
  phone text null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone null,
  deleted_at timestamp with time zone null
);

-- public.integrations
drop table if exists public.integrations;
create table public.integrations (
  id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  platform public.integration_platform not null,
  shop_domain text null,
  is_active boolean default true not null,
  last_sync_at timestamp with time zone null,
  sync_status text null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone null,
  shop_name text null
);

-- public.products
drop table if exists public.products;
create table public.products (
  id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  external_product_id text null,
  title text not null,
  description text null,
  handle text null,
  product_type text null,
  tags text[] null,
  image_url text null,
  status text null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone null
);
alter table public.products add constraint products_title_check check ((length(title) > 0));

-- public.product_variants
drop table if exists public.product_variants;
create table public.product_variants (
  id uuid default gen_random_uuid() not null,
  product_id uuid not null,
  company_id uuid not null,
  external_variant_id text null,
  sku text not null,
  title text null,
  option1_name text null,
  option1_value text null,
  option2_name text null,
  option2_value text null,
  option3_name text null,
  option3_value text null,
  barcode text null,
  price integer null,
  compare_at_price integer null,
  cost integer null,
  inventory_quantity integer default 0 not null,
  location text null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone null,
  supplier_id uuid null,
  reorder_point integer null,
  reorder_quantity integer null
);

-- public.suppliers
drop table if exists public.suppliers;
create table public.suppliers (
  id uuid default gen_random_uuid() not null,
  name text not null,
  email text null,
  phone text null,
  default_lead_time_days integer null,
  notes text null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone null,
  company_id uuid not null
);

-- vault.secrets
-- not supported

-- public.audit_log
drop table if exists public.audit_log;
create table public.audit_log (
  id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  user_id uuid null,
  action text not null,
  details jsonb null,
  created_at timestamp with time zone default now() not null
);

-- public.channel_fees
drop table if exists public.channel_fees;
create table public.channel_fees (
  id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  channel_name text not null,
  percentage_fee real null,
  fixed_fee integer null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone null
);

-- public.conversations
drop table if exists public.conversations;
create table public.conversations (
  id uuid default gen_random_uuid() not null,
  user_id uuid not null,
  company_id uuid not null,
  title text not null,
  created_at timestamp with time zone default now() not null,
  last_accessed_at timestamp with time zone default now() not null,
  is_starred boolean default false not null
);

-- public.export_jobs
drop table if exists public.export_jobs;
create table public.export_jobs (
  id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  requested_by_user_id uuid not null,
  status text default 'pending'::text not null,
  download_url text null,
  expires_at timestamp with time zone null,
  created_at timestamp with time zone default now() not null,
  completed_at timestamp with time zone null,
  error_message text null
);

-- public.feedback
drop table if exists public.feedback;
create table public.feedback (
  id uuid default gen_random_uuid() not null,
  user_id uuid not null,
  company_id uuid not null,
  subject_id text not null,
  subject_type text not null,
  feedback public.feedback_type not null,
  created_at timestamp with time zone default now() not null
);

-- public.imports
drop table if exists public.imports;
create table public.imports (
  id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  created_by uuid not null,
  import_type text not null,
  file_name text not null,
  status text default 'processing'::text not null,
  total_rows integer null,
  processed_rows integer null,
  error_count integer null,
  errors jsonb null,
  summary jsonb null,
  created_at timestamp with time zone default now() not null,
  completed_at timestamp with time zone null
);

-- public.inventory_ledger
drop table if exists public.inventory_ledger;
create table public.inventory_ledger (
  id uuid default gen_random_uuid() not null,
  variant_id uuid not null,
  company_id uuid not null,
  quantity_change integer not null,
  new_quantity integer not null,
  change_type text not null,
  related_id text null,
  notes text null,
  created_at timestamp with time zone default now() not null
);

-- public.messages
drop table if exists public.messages;
create table public.messages (
  id uuid default gen_random_uuid() not null,
  conversation_id uuid not null,
  company_id uuid not null,
  role public.message_role not null,
  content text not null,
  visualization jsonb null,
  created_at timestamp with time zone default now() not null,
  confidence real null,
  assumptions text[] null,
  "isError" boolean null,
  "componentProps" jsonb null,
  component text null
);

-- public.order_line_items
drop table if exists public.order_line_items;
create table public.order_line_items (
  id uuid default gen_random_uuid() not null,
  order_id uuid not null,
  variant_id uuid null,
  company_id uuid not null,
  product_name text null,
  variant_title text null,
  sku text null,
  quantity integer not null,
  price integer not null,
  total_discount integer null,
  tax_amount integer null,
  cost_at_time integer null,
  external_line_item_id text null
);

-- public.orders
drop table if exists public.orders;
create table public.orders (
  id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  external_order_id text null,
  order_number text not null,
  customer_id uuid null,
  financial_status text null,
  fulfillment_status text null,
  currency text null,
  subtotal integer not null,
  total_tax integer null,
  total_shipping integer null,
  total_discounts integer null,
  total_amount integer not null,
  source_platform text null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone null
);

-- public.purchase_order_line_items
drop table if exists public.purchase_order_line_items;
create table public.purchase_order_line_items (
  id uuid default gen_random_uuid() not null,
  purchase_order_id uuid not null,
  variant_id uuid not null,
  company_id uuid not null,
  quantity integer not null,
  cost integer not null
);

-- public.purchase_orders
drop table if exists public.purchase_orders;
create table public.purchase_orders (
  id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  supplier_id uuid null,
  status text default 'Draft'::text not null,
  po_number text not null,
  total_cost integer not null,
  expected_arrival_date date null,
  notes text null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone null,
  idempotency_key uuid null
);

-- public.refunds
drop table if exists public.refunds;
create table public.refunds (
  id uuid default gen_random_uuid() not null,
  order_id uuid not null,
  company_id uuid not null,
  refund_number text not null,
  status text not null,
  reason text null,
  note text null,
  total_amount integer not null,
  created_by_user_id uuid null,
  external_refund_id text null,
  created_at timestamp with time zone default now() not null
);

-- public.webhook_events
drop table if exists public.webhook_events;
create table public.webhook_events (
  id uuid default gen_random_uuid() not null,
  integration_id uuid not null,
  webhook_id text not null,
  created_at timestamp with time zone default now() not null
);

-- data
alter table public.companies add constraint companies_pkey primary key (id);
alter table public.companies add constraint companies_owner_id_fkey foreign key (owner_id) references auth.users (id);
alter table public.company_settings add constraint company_settings_pkey primary key (company_id);
alter table public.company_settings add constraint company_settings_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade;
alter table public.company_users add constraint company_users_pkey primary key (user_id, company_id);
alter table public.company_users add constraint company_users_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade;
alter table public.company_users add constraint company_users_user_id_fkey foreign key (user_id) references auth.users (id) on delete cascade;
alter table public.customers add constraint customers_pkey primary key (id);
alter table public.customers add constraint customers_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade;
alter table public.integrations add constraint integrations_pkey primary key (id);
alter table public.integrations add constraint integrations_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade;
alter table public.integrations add constraint integrations_company_id_platform_key unique (company_id, platform);
alter table public.products add constraint products_pkey primary key (id);
alter table public.products add constraint products_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade;
alter table public.products add constraint products_company_id_external_product_id_key unique (company_id, external_product_id);
alter table public.product_variants add constraint product_variants_pkey primary key (id);
alter table public.product_variants add constraint product_variants_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade;
alter table public.product_variants add constraint product_variants_company_id_sku_key unique (company_id, sku);
alter table public.product_variants add constraint product_variants_product_id_fkey foreign key (product_id) references public.products (id) on delete cascade;
alter table public.product_variants add constraint product_variants_supplier_id_fkey foreign key (supplier_id) references public.suppliers (id) on delete set null;
alter table public.suppliers add constraint suppliers_pkey primary key (id);
alter table public.suppliers add constraint suppliers_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade;
alter table public.audit_log add constraint audit_log_pkey primary key (id);
alter table public.audit_log add constraint audit_log_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade;
alter table public.audit_log add constraint audit_log_user_id_fkey foreign key (user_id) references auth.users (id) on delete set null;
alter table public.channel_fees add constraint channel_fees_pkey primary key (id);
alter table public.channel_fees add constraint channel_fees_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade;
alter table public.channel_fees add constraint channel_fees_company_id_channel_name_key unique (company_id, channel_name);
alter table public.conversations add constraint conversations_pkey primary key (id);
alter table public.conversations add constraint conversations_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade;
alter table public.conversations add constraint conversations_user_id_fkey foreign key (user_id) references auth.users (id) on delete cascade;
alter table public.export_jobs add constraint export_jobs_pkey primary key (id);
alter table public.export_jobs add constraint export_jobs_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade;
alter table public.export_jobs add constraint export_jobs_requested_by_user_id_fkey foreign key (requested_by_user_id) references auth.users (id) on delete cascade;
alter table public.feedback add constraint feedback_pkey primary key (id);
alter table public.feedback add constraint feedback_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade;
alter table public.feedback add constraint feedback_user_id_fkey foreign key (user_id) references auth.users (id) on delete cascade;
alter table public.imports add constraint imports_pkey primary key (id);
alter table public.imports add constraint imports_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade;
alter table public.imports add constraint imports_created_by_fkey foreign key (created_by) references auth.users (id) on delete cascade;
alter table public.inventory_ledger add constraint inventory_ledger_pkey primary key (id);
alter table public.inventory_ledger add constraint inventory_ledger_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade;
alter table public.inventory_ledger add constraint inventory_ledger_variant_id_fkey foreign key (variant_id) references public.product_variants (id) on delete cascade;
alter table public.messages add constraint messages_pkey primary key (id);
alter table public.messages add constraint messages_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade;
alter table public.messages add constraint messages_conversation_id_fkey foreign key (conversation_id) references public.conversations (id) on delete cascade;
alter table public.order_line_items add constraint order_line_items_pkey primary key (id);
alter table public.order_line_items add constraint order_line_items_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade;
alter table public.order_line_items add constraint order_line_items_order_id_fkey foreign key (order_id) references public.orders (id) on delete cascade;
alter table public.order_line_items add constraint order_line_items_variant_id_fkey foreign key (variant_id) references public.product_variants (id) on delete set null;
alter table public.orders add constraint orders_pkey primary key (id);
alter table public.orders add constraint orders_company_id_external_order_id_key unique (company_id, external_order_id);
alter table public.orders add constraint orders_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade;
alter table public.orders add constraint orders_customer_id_fkey foreign key (customer_id) references public.customers (id) on delete set null;
alter table public.purchase_order_line_items add constraint purchase_order_line_items_pkey primary key (id);
alter table public.purchase_order_line_items add constraint purchase_order_line_items_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade;
alter table public.purchase_order_line_items add constraint purchase_order_line_items_purchase_order_id_fkey foreign key (purchase_order_id) references public.purchase_orders (id) on delete cascade;
alter table public.purchase_order_line_items add constraint purchase_order_line_items_variant_id_fkey foreign key (variant_id) references public.product_variants (id) on delete cascade;
alter table public.purchase_orders add constraint purchase_orders_pkey primary key (id);
alter table public.purchase_orders add constraint purchase_orders_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade;
alter table public.purchase_orders add constraint purchase_orders_idempotency_key_key unique (idempotency_key);
alter table public.purchase_orders add constraint purchase_orders_supplier_id_fkey foreign key (supplier_id) references public.suppliers (id) on delete set null;
alter table public.refunds add constraint refunds_pkey primary key (id);
alter table public.refunds add constraint refunds_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade;
alter table public.refunds add constraint refunds_created_by_user_id_fkey foreign key (created_by_user_id) references auth.users (id) on delete set null;
alter table public.refunds add constraint refunds_order_id_fkey foreign key (order_id) references public.orders (id) on delete cascade;
alter table public.webhook_events add constraint webhook_events_pkey primary key (id);
alter table public.webhook_events add constraint webhook_events_integration_id_fkey foreign key (integration_id) references public.integrations (id) on delete cascade;
alter table public.webhook_events add constraint webhook_events_integration_id_webhook_id_key unique (integration_id, webhook_id);

create policy "Allow all for service role" on public.companies for all to service_role;
create policy "Allow all for service role" on public.company_settings for all to service_role;
create policy "Allow all for service role" on public.company_users for all to service_role;
create policy "Allow all for service role" on public.customers for all to service_role;
create policy "Allow all for service role" on public.integrations for all to service_role;
create policy "Allow all for service role" on public.products for all to service_role;
create policy "Allow all for service role" on public.product_variants for all to service_role;
create policy "Allow all for service role" on public.suppliers for all to service_role;
create policy "Allow full access based on company_id" on public.audit_log for all using ((company_id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user)));
create policy "Allow full access based on company_id" on public.channel_fees for all using ((company_id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user)));
create policy "Allow full access based on company_id" on public.conversations for all using ((company_id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user)));
create policy "Allow full access based on company_id" on public.export_jobs for all using ((company_id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user)));
create policy "Allow full access based on company_id" on public.feedback for all using ((company_id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user)));
create policy "Allow full access based on company_id" on public.imports for all using ((company_id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user)));
create policy "Allow full access based on company_id" on public.inventory_ledger for all using ((company_id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user)));
create policy "Allow full access based on company_id" on public.messages for all using ((company_id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user)));
create policy "Allow full access based on company_id" on public.order_line_items for all using ((company_id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user)));
create policy "Allow full access based on company_id" on public.orders for all using ((company_id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user)));
create policy "Allow full access based on company_id" on public.purchase_order_line_items for all using ((company_id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user)));
create policy "Allow full access based on company_id" on public.purchase_orders for all using ((company_id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user)));
create policy "Allow full access based on company_id" on public.refunds for all using ((company_id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user)));
create policy "Allow read access based on company_id" on public.companies for select using ((id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user)));
create policy "Allow read access based on company_id" on public.company_settings for select using ((company_id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user)));
create policy "Allow read access based on company_id" on public.company_users for select using ((company_id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user)));
create policy "Allow read access based on company_id" on public.customers for select using ((company_id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user)));
create policy "Allow read access based on company_id" on public.integrations for select using ((company_id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user)));
create policy "Allow read access based on company_id" on public.products for select using ((company_id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user)));
create policy "Allow read access based on company_id" on public.product_variants for select using ((company_id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user)));
create policy "Allow read access based on company_id" on public.suppliers for select using ((company_id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user)));
create policy "Allow users to create companies" on public.companies for insert with check (true);
create policy "Allow users to manage their own company data" on public.companies for update using ((id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user)));
create policy "Allow users to manage their own settings" on public.company_settings for all using ((company_id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user)));
create policy "Allow users to view their own company users" on public.company_users for select using ((company_id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user)));
create policy "Allow full access based on company_id" on public.webhook_events for all using ((integration_id IN ( SELECT i.id
   FROM public.integrations i
  WHERE (i.company_id IN ( SELECT get_company_id_for_user(auth.uid()) AS get_company_id_for_user)))));

drop view if exists public.product_variants_with_details;
CREATE OR REPLACE VIEW public.product_variants_with_details AS
SELECT
    pv.*,
    p.title AS product_title,
    p.status AS product_status,
    p.image_url,
    p.product_type
FROM
    product_variants pv
JOIN
    products p ON pv.product_id = p.id;

drop view if exists public.orders_view;
CREATE OR REPLACE VIEW public.orders_view AS
SELECT
    o.*,
    c.email as customer_email
FROM
    orders o
LEFT JOIN
    customers c ON o.customer_id = c.id;

drop view if exists public.customers_view;
CREATE OR REPLACE VIEW public.customers_view AS
SELECT 
    c.id,
    c.company_id,
    c.name as customer_name,
    c.email,
    c.created_at,
    COUNT(o.id) as total_orders,
    COALESCE(SUM(o.total_amount), 0) as total_spent,
    MIN(o.created_at) as first_order_date
FROM 
    customers c
LEFT JOIN 
    orders o ON c.id = o.customer_id
GROUP BY 
    c.id;

-- public.get_company_id_for_user(p_user_id)
drop function if exists public.get_company_id_for_user;
create function public.get_company_id_for_user(p_user_id uuid)
returns uuid
language plpgsql
security definer
as $$
BEGIN
    RETURN (
        SELECT company_id
        FROM public.company_users
        WHERE user_id = p_user_id
    );
END;
$$;

-- public.handle_new_user()
drop function if exists public.handle_new_user;
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    new_company_id UUID;
BEGIN
    -- Create a new company for the new user
    INSERT INTO public.companies (name, owner_id)
    VALUES (new.raw_user_meta_data->>'company_name', new.id)
    RETURNING id INTO new_company_id;

    -- Link the user to the new company as 'Owner'
    INSERT INTO public.company_users (user_id, company_id, role)
    VALUES (new.id, new_company_id, 'Owner');

    -- Create default settings for the new company
    INSERT INTO public.company_settings (company_id)
    VALUES (new_company_id);

    -- Update the user's app_metadata with the new company_id
    -- This is critical for RLS policies
    UPDATE auth.users
    SET app_metadata = app_metadata || jsonb_build_object('company_id', new_company_id)
    WHERE id = new.id;
    
    RETURN new;
END;
$$;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();


-- public.record_order_from_platform(p_company_id, p_order_payload, p_platform)
drop function if exists public.record_order_from_platform;
CREATE OR REPLACE FUNCTION public.record_order_from_platform(
    p_company_id UUID,
    p_order_payload JSONB,
    p_platform TEXT
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_customer_id UUID;
    v_order_id UUID;
    v_line_item JSONB;
    v_variant_id UUID;
BEGIN
    -- Find or create the customer
    IF p_order_payload->'customer'->>'email' IS NOT NULL THEN
        SELECT id INTO v_customer_id
        FROM public.customers
        WHERE company_id = p_company_id AND email = p_order_payload->'customer'->>'email';

        IF v_customer_id IS NULL THEN
            INSERT INTO public.customers (company_id, external_customer_id, name, email, phone)
            VALUES (
                p_company_id,
                p_order_payload->'customer'->>'id',
                p_order_payload->'customer'->>'first_name' || ' ' || p_order_payload->'customer'->>'last_name',
                p_order_payload->'customer'->>'email',
                p_order_payload->'customer'->>'phone'
            )
            RETURNING id INTO v_customer_id;
        END IF;
    END IF;

    -- Upsert the order
    INSERT INTO public.orders (
        company_id, external_order_id, order_number, customer_id,
        financial_status, fulfillment_status, currency, subtotal,
        total_tax, total_shipping, total_discounts, total_amount,
        source_platform, created_at
    )
    VALUES (
        p_company_id,
        p_order_payload->>'id',
        p_order_payload->>'name',
        v_customer_id,
        p_order_payload->>'financial_status',
        p_order_payload->>'fulfillment_status',
        p_order_payload->>'currency',
        (p_order_payload->>'subtotal_price')::numeric * 100,
        (p_order_payload->>'total_tax')::numeric * 100,
        (p_order_payload->>'total_shipping_price')::numeric * 100,
        (p_order_payload->>'total_discounts')::numeric * 100,
        (p_order_payload->>'total_price')::numeric * 100,
        p_platform,
        (p_order_payload->>'created_at')::timestamptz
    )
    ON CONFLICT (company_id, external_order_id) DO UPDATE SET
        financial_status = EXCLUDED.financial_status,
        fulfillment_status = EXCLUDED.fulfillment_status,
        total_amount = EXCLUDED.total_amount,
        updated_at = NOW()
    RETURNING id INTO v_order_id;

    -- Process line items
    FOR v_line_item IN SELECT * FROM jsonb_array_elements(p_order_payload->'line_items')
    LOOP
        -- Find the corresponding product variant
        SELECT id INTO v_variant_id
        FROM public.product_variants
        WHERE company_id = p_company_id AND sku = v_line_item->>'sku';
        
        -- If variant exists, insert line item and decrement inventory
        IF v_variant_id IS NOT NULL THEN
            INSERT INTO public.order_line_items (
                order_id, variant_id, company_id, product_name, variant_title,
                sku, quantity, price, total_discount, tax_amount, external_line_item_id
            )
            VALUES (
                v_order_id,
                v_variant_id,
                p_company_id,
                v_line_item->>'name',
                v_line_item->>'title',
                v_line_item->>'sku',
                (v_line_item->>'quantity')::int,
                (v_line_item->>'price')::numeric * 100,
                (v_line_item->'discount_allocations'->0->>'amount')::numeric * 100,
                (v_line_item->'tax_lines'->0->>'price')::numeric * 100,
                v_line_item->>'id'
            );
            
            -- Decrement inventory
            PERFORM public.decrement_inventory_for_order(
                p_company_id,
                v_variant_id,
                (v_line_item->>'quantity')::int,
                v_order_id
            );

        END IF;
    END LOOP;

    RETURN v_order_id;
END;
$$;


-- public.decrement_inventory_for_order(p_company_id, p_variant_id, p_quantity, p_order_id)
drop function if exists public.decrement_inventory_for_order;
CREATE OR REPLACE FUNCTION public.decrement_inventory_for_order(
    p_company_id UUID,
    p_variant_id UUID,
    p_quantity INT,
    p_order_id UUID
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    current_stock INT;
BEGIN
    -- Check for sufficient stock before decrementing
    SELECT inventory_quantity INTO current_stock
    FROM public.product_variants
    WHERE id = p_variant_id AND company_id = p_company_id;

    IF current_stock IS NULL THEN
        -- Variant not found, do nothing or raise a notice
        RETURN;
    END IF;

    IF current_stock < p_quantity THEN
        -- Not enough stock. Log an error but do not decrement.
        -- In a real system, this might raise an exception or create a backorder.
        INSERT INTO public.audit_log (company_id, action, details)
        VALUES (p_company_id, 'insufficient_stock_for_sale', jsonb_build_object(
            'variant_id', p_variant_id,
            'order_id', p_order_id,
            'requested_quantity', p_quantity,
            'available_quantity', current_stock
        ));
        RETURN;
    END IF;

    -- Proceed with decrementing inventory
    UPDATE public.product_variants
    SET inventory_quantity = inventory_quantity - p_quantity
    WHERE id = p_variant_id AND company_id = p_company_id;

    -- Create a ledger entry for the sale
    INSERT INTO public.inventory_ledger (
        variant_id, company_id, quantity_change, new_quantity, change_type, related_id, notes
    )
    VALUES (
        p_variant_id,
        p_company_id,
        -p_quantity,
        current_stock - p_quantity,
        'sale',
        p_order_id,
        'Sale transaction'
    );
END;
$$;

-- public.check_user_permission(p_user_id, p_required_role)
drop function if exists public.check_user_permission;
CREATE OR REPLACE FUNCTION public.check_user_permission(
    p_user_id UUID,
    p_required_role public.company_role
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    user_role public.company_role;
BEGIN
    SELECT role INTO user_role
    FROM public.company_users cu
    WHERE cu.user_id = p_user_id;

    IF user_role IS NULL THEN
        RETURN FALSE;
    END IF;

    IF p_required_role = 'Admin' THEN
        RETURN user_role IN ('Admin', 'Owner');
    ELSIF p_required_role = 'Owner' THEN
        RETURN user_role = 'Owner';
    END IF;
    
    RETURN FALSE;
END;
$$;

-- Finally, enable RLS on all tables where it's needed
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.integrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.channel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.imports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_line_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;

-- Grant usage on the schema to the authenticated role
GRANT USAGE ON SCHEMA public TO authenticated;

-- Grant select on all tables to the authenticated role
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT INSERT ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT UPDATE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT DELETE ON ALL TABLES IN SCHEMA public TO authenticated;

-- Grant usage on all sequences to the authenticated role
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Grant execute on all functions to the authenticated role
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
