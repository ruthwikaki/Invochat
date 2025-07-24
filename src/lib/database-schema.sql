
-- ### Extensions ###
create extension if not exists "uuid-ossp" with schema "extensions";
create extension if not exists "pg_stat_statements" with schema "extensions";

-- ### Types ###
drop type if exists public.company_role;
create type public.company_role as enum ('Owner', 'Admin', 'Member');

drop type if exists public.integration_platform;
create type public.integration_platform as enum ('shopify', 'woocommerce', 'amazon_fba');

drop type if exists public.message_role;
create type public.message_role as enum ('user', 'assistant', 'tool');

drop type if exists public.feedback_type;
create type public.feedback_type as enum ('helpful', 'unhelpful');


-- ### Tables ###

-- Companies Table: Stores company information.
create table if not exists public.companies (
    id uuid not null default uuid_generate_v4(),
    name text not null,
    owner_id uuid not null,
    created_at timestamp with time zone not null default now(),
    constraint companies_pkey primary key (id),
    constraint companies_owner_id_fkey foreign key (owner_id) references auth.users (id) on delete cascade
);
comment on table public.companies is 'Stores company information, linking them to a primary owner in the auth schema.';

-- Company Users Table: Junction table for many-to-many relationship between users and companies.
create table if not exists public.company_users (
    company_id uuid not null,
    user_id uuid not null,
    role public.company_role not null default 'Member'::public.company_role,
    constraint company_users_pkey primary key (company_id, user_id),
    constraint company_users_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade,
    constraint company_users_user_id_fkey foreign key (user_id) references auth.users (id) on delete cascade
);
comment on table public.company_users is 'Junction table for a many-to-many relationship between users and companies, defining user roles within a company.';


-- Company Settings Table: Stores business logic settings for each company.
create table if not exists public.company_settings (
    company_id uuid not null,
    dead_stock_days integer not null default 90,
    fast_moving_days integer not null default 30,
    predictive_stock_days integer not null default 7,
    currency text null default 'USD'::text,
    timezone text null default 'UTC'::text,
    tax_rate numeric null default 0,
    created_at timestamp with time zone not null default now(),
    updated_at timestamp with time zone null,
    overstock_multiplier real not null default 2.5,
    high_value_threshold integer not null default 1000,
    constraint company_settings_pkey primary key (company_id),
    constraint company_settings_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade
);
comment on table public.company_settings is 'Stores business logic parameters for each company.';


-- Products Table: Stores product information.
create table if not exists public.products (
    id uuid not null default uuid_generate_v4(),
    company_id uuid not null,
    title text not null,
    description text null,
    handle text null,
    product_type text null,
    tags text[] null,
    status text null,
    image_url text null,
    external_product_id text null,
    created_at timestamp with time zone not null default now(),
    updated_at timestamp with time zone null,
    deleted_at timestamp with time zone null,
    constraint products_pkey primary key (id),
    constraint products_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade,
    constraint products_company_id_external_product_id_key unique (company_id, external_product_id)
);
comment on table public.products is 'Stores base product information.';


-- Suppliers Table: Stores supplier information.
create table if not exists public.suppliers (
    id uuid not null default uuid_generate_v4(),
    company_id uuid not null,
    name text not null,
    email text null,
    phone text null,
    default_lead_time_days integer null,
    notes text null,
    created_at timestamp with time zone not null default now(),
    updated_at timestamp with time zone null,
    constraint suppliers_pkey primary key (id),
    constraint suppliers_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade
);
comment on table public.suppliers is 'Stores supplier and vendor information.';

-- Product Variants Table: Stores individual product variants (SKUs).
create table if not exists public.product_variants (
    id uuid not null default gen_random_uuid(),
    product_id uuid not null,
    company_id uuid not null,
    supplier_id uuid null,
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
    inventory_quantity integer not null default 0,
    external_variant_id text null,
    created_at timestamp with time zone null default now(),
    updated_at timestamp with time zone null default now(),
    location text null,
    reorder_point integer null,
    reorder_quantity integer null,
    constraint product_variants_pkey primary key (id),
    constraint product_variants_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade,
    constraint product_variants_product_id_fkey foreign key (product_id) references public.products (id) on delete cascade,
    constraint product_variants_supplier_id_fkey foreign key (supplier_id) references public.suppliers (id) on delete set null,
    constraint product_variants_company_id_sku_key unique (company_id, sku),
    constraint product_variants_company_id_external_variant_id_key unique (company_id, external_variant_id)
);
comment on table public.product_variants is 'Stores individual product variants (SKUs), including stock levels and pricing.';


-- Customers Table: Stores customer information.
create table if not exists public.customers (
    id uuid not null default uuid_generate_v4(),
    company_id uuid not null,
    name text null,
    email text null,
    phone text null,
    external_customer_id text null,
    created_at timestamp with time zone null default now(),
    updated_at timestamp with time zone null,
    deleted_at timestamp with time zone null,
    constraint customers_pkey primary key (id),
    constraint customers_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade
);
comment on table public.customers is 'Stores customer information from sales channels.';


-- Orders Table: Stores order information.
create table if not exists public.orders (
    id uuid not null default gen_random_uuid(),
    company_id uuid not null,
    order_number text not null,
    external_order_id text null,
    customer_id uuid null,
    financial_status text null default 'pending'::text,
    fulfillment_status text null default 'unfulfilled'::text,
    currency text null default 'USD'::text,
    subtotal integer not null default 0,
    total_tax integer null default 0,
    total_shipping integer null default 0,
    total_discounts integer null default 0,
    total_amount integer not null,
    source_platform text null,
    created_at timestamp with time zone null default now(),
    updated_at timestamp with time zone null default now(),
    constraint orders_pkey primary key (id),
    constraint orders_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade,
    constraint orders_customer_id_fkey foreign key (customer_id) references public.customers (id) on delete set null,
    constraint orders_company_id_external_order_id_key unique (company_id, external_order_id)
);
comment on table public.orders is 'Stores sales order information.';


-- Order Line Items Table: Stores line items for each order.
create table if not exists public.order_line_items (
    id uuid not null default gen_random_uuid(),
    order_id uuid not null,
    variant_id uuid null,
    company_id uuid not null,
    product_name text null,
    variant_title text null,
    sku text null,
    quantity integer not null,
    price integer not null,
    total_discount integer null default 0,
    tax_amount integer null default 0,
    cost_at_time integer null,
    external_line_item_id text null,
    constraint order_line_items_pkey primary key (id),
    constraint order_line_items_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade,
    constraint order_line_items_order_id_fkey foreign key (order_id) references public.orders (id) on delete cascade,
    constraint order_line_items_variant_id_fkey foreign key (variant_id) references public.product_variants (id) on delete set null
);
comment on table public.order_line_items is 'Stores line items for each sales order.';


-- Inventory Ledger Table: Tracks all inventory movements.
create table if not exists public.inventory_ledger (
    id uuid not null default gen_random_uuid(),
    company_id uuid not null,
    variant_id uuid not null,
    change_type text not null,
    quantity_change integer not null,
    new_quantity integer not null,
    created_at timestamp with time zone not null default now(),
    related_id uuid null,
    notes text null,
    constraint inventory_ledger_pkey primary key (id),
    constraint inventory_ledger_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade,
    constraint inventory_ledger_variant_id_fkey foreign key (variant_id) references public.product_variants (id) on delete cascade
);
comment on table public.inventory_ledger is 'Tracks all inventory movements for auditing and history.';


-- Integrations Table: Stores information about connected platforms.
create table if not exists public.integrations (
    id uuid not null default uuid_generate_v4(),
    company_id uuid not null,
    platform public.integration_platform not null,
    shop_domain text null,
    shop_name text null,
    is_active boolean null default false,
    last_sync_at timestamp with time zone null,
    sync_status text null,
    created_at timestamp with time zone not null default now(),
    updated_at timestamp with time zone null,
    constraint integrations_pkey primary key (id),
    constraint integrations_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade
);
comment on table public.integrations is 'Stores information about connected e-commerce platforms.';


-- Purchase Orders Table: Stores purchase order information.
create table if not exists public.purchase_orders (
    id uuid not null default uuid_generate_v4(),
    company_id uuid not null,
    supplier_id uuid null,
    status text not null default 'Draft'::text,
    po_number text not null,
    total_cost integer not null,
    expected_arrival_date date null,
    created_at timestamp with time zone not null default now(),
    idempotency_key uuid null,
    notes text null,
    updated_at timestamp with time zone null,
    constraint purchase_orders_pkey primary key (id),
    constraint purchase_orders_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade,
    constraint purchase_orders_supplier_id_fkey foreign key (supplier_id) references public.suppliers (id) on delete set null
);
comment on table public.purchase_orders is 'Stores purchase orders for replenishing inventory.';


-- Purchase Order Line Items Table: Stores line items for each PO.
create table if not exists public.purchase_order_line_items (
    id uuid not null default uuid_generate_v4(),
    purchase_order_id uuid not null,
    variant_id uuid not null,
    quantity integer not null,
    cost integer not null,
    company_id uuid not null,
    constraint purchase_order_line_items_pkey primary key (id),
    constraint purchase_order_line_items_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade,
    constraint purchase_order_line_items_purchase_order_id_fkey foreign key (purchase_order_id) references public.purchase_orders (id) on delete cascade,
    constraint purchase_order_line_items_variant_id_fkey foreign key (variant_id) references public.product_variants (id) on delete cascade
);
comment on table public.purchase_order_line_items is 'Stores line items for each purchase order.';


-- Conversations Table: Stores AI chat conversation threads.
create table if not exists public.conversations (
    id uuid not null default uuid_generate_v4(),
    user_id uuid not null,
    company_id uuid not null,
    title text not null,
    created_at timestamp with time zone null default now(),
    last_accessed_at timestamp with time zone null default now(),
    is_starred boolean null default false,
    constraint conversations_pkey primary key (id),
    constraint conversations_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade,
    constraint conversations_user_id_fkey foreign key (user_id) references auth.users (id) on delete cascade
);
comment on table public.conversations is 'Stores AI chat conversation threads.';


-- Messages Table: Stores individual messages within a conversation.
create table if not exists public.messages (
    id uuid not null default uuid_generate_v4(),
    conversation_id uuid not null,
    company_id uuid not null,
    role public.message_role not null,
    content text not null,
    component text null,
    component_props jsonb null,
    visualization jsonb null,
    confidence numeric null,
    assumptions text[] null,
    created_at timestamp with time zone null default now(),
    is_error boolean null default false,
    constraint messages_pkey primary key (id),
    constraint messages_conversation_id_fkey foreign key (conversation_id) references public.conversations (id) on delete cascade,
    constraint messages_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade
);
comment on table public.messages is 'Stores individual messages within a conversation.';


-- Webhook Events Table: Logs incoming webhooks to prevent replay attacks.
create table if not exists public.webhook_events (
    id uuid not null default gen_random_uuid(),
    integration_id uuid not null,
    webhook_id text not null,
    created_at timestamp with time zone null default now(),
    constraint webhook_events_pkey primary key (id),
    constraint webhook_events_integration_id_webhook_id_key unique (integration_id, webhook_id),
    constraint webhook_events_integration_id_fkey foreign key (integration_id) references public.integrations (id) on delete cascade
);
comment on table public.webhook_events is 'Logs incoming webhooks to prevent replay attacks.';


-- Channel Fees Table: Stores sales channel fees for profit calculations.
create table if not exists public.channel_fees (
    id uuid not null default uuid_generate_v4(),
    company_id uuid not null,
    channel_name text not null,
    percentage_fee numeric null,
    fixed_fee numeric null,
    created_at timestamp with time zone null default now(),
    updated_at timestamp with time zone null,
    constraint channel_fees_pkey primary key (id),
    constraint channel_fees_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade,
    constraint channel_fees_company_id_channel_name_key unique (company_id, channel_name)
);
comment on table public.channel_fees is 'Stores sales channel fees for accurate profit calculations.';


-- Audit Log Table: Tracks important events in the system.
create table if not exists public.audit_log (
    id bigint generated by default as identity,
    company_id uuid null,
    user_id uuid null,
    action text not null,
    details jsonb null,
    created_at timestamp with time zone null default now(),
    constraint audit_log_pkey primary key (id),
    constraint audit_log_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade,
    constraint audit_log_user_id_fkey foreign key (user_id) references auth.users (id) on delete set null
);
comment on table public.audit_log is 'Tracks important events in the system for security and auditing.';


-- Export Jobs Table: Manages data export jobs.
create table if not exists public.export_jobs (
    id uuid not null default uuid_generate_v4(),
    company_id uuid not null,
    requested_by_user_id uuid not null,
    status text not null default 'pending'::text,
    download_url text null,
    expires_at timestamp with time zone null,
    error_message text null,
    created_at timestamp with time zone not null default now(),
    completed_at timestamp with time zone null,
    constraint export_jobs_pkey primary key (id),
    constraint export_jobs_company_id_fkey foreign key (company_id) references public.companies (id) on delete cascade,
    constraint export_jobs_requested_by_user_id_fkey foreign key (requested_by_user_id) references auth.users (id) on delete cascade
);
comment on table public.export_jobs is 'Manages background jobs for exporting company data.';

-- ### RLS Policies ###
alter table public.companies enable row level security;
create policy "Users can view their own company" on public.companies for select using (id in (select company_id from public.company_users where user_id = auth.uid()));

alter table public.company_users enable row level security;
create policy "Users can view their own company associations" on public.company_users for select using (user_id = auth.uid());
create policy "Owners can manage users in their company" on public.company_users for all using (company_id in (select company_id from public.company_users where user_id = auth.uid() and role = 'Owner'::public.company_role));

alter table public.products enable row level security;
create policy "All users can manage products in their own company" on public.products for all using (company_id in (select company_id from public.company_users where user_id = auth.uid())) with check (company_id in (select company_id from public.company_users where user_id = auth.uid()));

alter table public.product_variants enable row level security;
create policy "All users can manage variants in their own company" on public.product_variants for all using (company_id in (select company_id from public.company_users where user_id = auth.uid())) with check (company_id in (select company_id from public.company_users where user_id = auth.uid()));

alter table public.suppliers enable row level security;
create policy "All users can manage suppliers in their own company" on public.suppliers for all using (company_id in (select company_id from public.company_users where user_id = auth.uid())) with check (company_id in (select company_id from public.company_users where user_id = auth.uid()));

alter table public.orders enable row level security;
create policy "All users can view orders in their own company" on public.orders for select using (company_id in (select company_id from public.company_users where user_id = auth.uid()));

alter table public.order_line_items enable row level security;
create policy "All users can view order line items in their own company" on public.order_line_items for select using (company_id in (select company_id from public.company_users where user_id = auth.uid()));

alter table public.purchase_orders enable row level security;
create policy "All users can manage purchase orders in their company" on public.purchase_orders for all using (company_id in (select company_id from public.company_users where user_id = auth.uid())) with check (company_id in (select company_id from public.company_users where user_id = auth.uid()));

alter table public.purchase_order_line_items enable row level security;
create policy "All users can manage PO line items in their company" on public.purchase_order_line_items for all using (company_id in (select company_id from public.company_users where user_id = auth.uid())) with check (company_id in (select company_id from public.company_users where user_id = auth.uid()));

alter table public.customers enable row level security;
create policy "All users can manage customers in their company" on public.customers for all using (company_id in (select company_id from public.company_users where user_id = auth.uid())) with check (company_id in (select company_id from public.company_users where user_id = auth.uid()));

alter table public.inventory_ledger enable row level security;
create policy "All users can view inventory ledger in their company" on public.inventory_ledger for select using (company_id in (select company_id from public.company_users where user_id = auth.uid()));

alter table public.integrations enable row level security;
create policy "All users can manage integrations in their company" on public.integrations for all using (company_id in (select company_id from public.company_users where user_id = auth.uid())) with check (company_id in (select company_id from public.company_users where user_id = auth.uid()));

alter table public.conversations enable row level security;
create policy "Users can manage their own conversations" on public.conversations for all using (user_id = auth.uid()) with check (user_id = auth.uid());

alter table public.messages enable row level security;
create policy "Users can manage messages in their own conversations" on public.messages for all using (company_id in (select company_id from public.company_users where user_id = auth.uid())) with check (company_id in (select company_id from public.company_users where user_id = auth.uid()));

alter table public.channel_fees enable row level security;
create policy "Users can manage channel fees in their company" on public.channel_fees for all using (company_id in (select company_id from public.company_users where user_id = auth.uid())) with check (company_id in (select company_id from public.company_users where user_id = auth.uid()));

alter table public.company_settings enable row level security;
create policy "Users can manage settings for their own company" on public.company_settings for all using (company_id in (select company_id from public.company_users where user_id = auth.uid())) with check (company_id in (select company_id from public.company_users where user_id = auth.uid()));


-- ### Functions & Triggers ###

-- Function to handle new user signup and company creation
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  company_id uuid;
begin
  -- Create a new company for the user
  insert into public.companies (name, owner_id)
  values (new.raw_user_meta_data->>'company_name', new.id)
  returning id into company_id;

  -- Link the user to the new company as Owner
  insert into public.company_users (user_id, company_id, role)
  values (new.id, company_id, 'Owner');

  -- Update the user's app_metadata with the new company_id
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id)
  where id = new.id;

  return new;
end;
$$;

-- Trigger to execute the function on new user signup
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- Function to decrement inventory after an order is placed
create or replace function public.decrement_inventory_for_order()
returns trigger
language plpgsql
as $$
declare
  variant_record record;
  current_stock integer;
begin
  -- Get the associated variant and its current stock
  select v.id, v.inventory_quantity into variant_record
  from public.product_variants v
  where v.sku = new.sku and v.company_id = new.company_id;

  -- If a matching variant is found
  if found then
    -- Get current stock quantity
    select inventory_quantity into current_stock
    from public.product_variants
    where id = variant_record.id;

    -- Check if there is enough stock
    if current_stock < new.quantity then
      raise exception 'Insufficient stock for SKU %: Tried to sell %, but only % available.', new.sku, new.quantity, current_stock;
    end if;
  
    -- Update the product variant's quantity
    update public.product_variants
    set inventory_quantity = inventory_quantity - new.quantity
    where id = variant_record.id;

    -- Record the change in the inventory ledger
    insert into public.inventory_ledger(company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
    values (new.company_id, variant_record.id, 'sale', -new.quantity, (current_stock - new.quantity), new.order_id, 'Order #' || (select order_number from public.orders where id = new.order_id));
    
    -- Update the line item with the variant_id
    new.variant_id := variant_record.id;
  end if;

  return new;
end;
$$;


-- Trigger to decrement inventory
drop trigger if exists on_order_line_item_insert on public.order_line_items;
create trigger on_order_line_item_insert
  before insert on public.order_line_items
  for each row execute procedure public.decrement_inventory_for_order();


-- Function to get user's role in a company
create or replace function public.get_user_role(p_user_id uuid, p_company_id uuid)
returns text
language sql
security definer
as $$
  select role from public.company_users
  where user_id = p_user_id and company_id = p_company_id;
$$;

-- Function to get user's company ID
create or replace function public.get_company_id_for_user(p_user_id uuid)
returns uuid
language sql
security definer
as $$
  select company_id from public.company_users
  where user_id = p_user_id
  limit 1;
$$;


-- Function to update a user's role
create or replace function public.update_user_role_in_company(p_user_id uuid, p_company_id uuid, p_new_role public.company_role)
returns void
language plpgsql
security definer
as $$
begin
  if auth.uid() not in (
    select user_id from public.company_users
    where company_id = p_company_id and role = 'Owner'
  ) then
    raise exception 'Only the company owner can change roles.';
  end if;

  update public.company_users
  set role = p_new_role
  where user_id = p_user_id and company_id = p_company_id;
end;
$$;


-- Function for a user to remove another user from a company
create or replace function public.remove_user_from_company(p_user_id uuid, p_company_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  requesting_user_role public.company_role;
  target_user_role public.company_role;
begin
  -- Get the role of the user making the request
  select role into requesting_user_role from public.company_users
  where user_id = auth.uid() and company_id = p_company_id;
  
  -- Get the role of the user to be removed
  select role into target_user_role from public.company_users
  where user_id = p_user_id and company_id = p_company_id;

  -- Check permissions
  if requesting_user_role not in ('Owner', 'Admin') then
    raise exception 'You do not have permission to remove users.';
  end if;

  if target_user_role = 'Owner' then
    raise exception 'The company owner cannot be removed.';
  end if;

  -- Perform the deletion
  delete from public.company_users
  where user_id = p_user_id and company_id = p_company_id;
end;
$$;

-- ### Materialized Views for Analytics ###

-- View for unified inventory details
create materialized view if not exists public.product_variants_with_details_mat as
select
  pv.*,
  p.title as product_title,
  p.status as product_status,
  p.image_url,
  p.product_type
from public.product_variants as pv
join public.products as p on pv.product_id = p.id;

create index if not exists idx_product_variants_with_details_mat_company_id on public.product_variants_with_details_mat(company_id);


-- View for order details including customer info
create materialized view if not exists public.orders_with_customer_mat as
select
  o.*,
  c.name as customer_name,
  c.email as customer_email
from public.orders as o
left join public.customers as c on o.customer_id = c.id;

create index if not exists idx_orders_with_customer_mat_company_id on public.orders_with_customer_mat(company_id);


-- View for customer analytics
create materialized view if not exists public.customers_view as
select
  c.id,
  c.company_id,
  c.name as customer_name,
  c.email,
  count(o.id) as total_orders,
  sum(o.total_amount) as total_spent,
  min(o.created_at) as first_order_date,
  c.created_at
from public.customers as c
join public.orders as o on c.id = o.customer_id
group by c.id, c.company_id, c.name, c.email;

create index if not exists idx_customers_view_company_id on public.customers_view(company_id);


-- Function to refresh all materialized views for a company
create or replace function public.refresh_all_matviews(p_company_id uuid)
returns void
language plpgsql
as $$
begin
  refresh materialized view concurrently public.product_variants_with_details_mat;
  refresh materialized view concurrently public.orders_with_customer_mat;
  refresh materialized view concurrently public.customers_view;
end;
$$;

-- Set up initial table privileges
grant delete on table public.companies to service_role;
grant insert on table public.companies to service_role;
grant references on table public.companies to service_role;
grant select on table public.companies to service_role;
grant trigger on table public.companies to service_role;
grant truncate on table public.companies to service_role;
grant update on table public.companies to service_role;

grant delete on table public.company_users to service_role;
grant insert on table public.company_users to service_role;
grant references on table public.company_users to service_role;
grant select on table public.company_users to service_role;
grant trigger on table public.company_users to service_role;
grant truncate on table public.company_users to service_role;
grant update on table public.company_users to service_role;
