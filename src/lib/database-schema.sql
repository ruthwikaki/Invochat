-- InvoChat Schema Setup
-- Version: 1.1
-- Description: This script sets up the necessary tables, types, functions, and triggers for the InvoChat application.
-- It is designed to be idempotent, meaning it can be run multiple times without causing errors.

-- Enable UUID generation
create extension if not exists "uuid-ossp" with schema extensions;

-- Create a custom user role type if it doesn't exist
do $$
begin
    if not exists (select 1 from pg_type where typname = 'user_role') then
        create type public.user_role as enum ('Owner', 'Admin', 'Member');
    end if;
end$$;

-- Create Companies Table
create table if not exists public.companies (
    id uuid primary key default uuid_generate_v4(),
    name text not null,
    created_at timestamptz not null default now()
);

-- Create Users Table (mirrors auth.users but with public access and company link)
create table if not exists public.users (
    id uuid primary key references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    email text,
    role public.user_role not null default 'Member',
    deleted_at timestamptz,
    created_at timestamptz default now()
);
alter table public.users enable row level security;
create policy "Allow users to see themselves" on public.users for select using (auth.uid() = id);
create policy "Allow company owners/admins to see team members" on public.users for select using (
    company_id in (
        select company_id from public.users where id = auth.uid() and (role = 'Owner' or role = 'Admin')
    )
);


-- Create Company Settings Table
create table if not exists public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
    dead_stock_days int not null default 90,
    fast_moving_days int not null default 30,
    predictive_stock_days int not null default 7,
    overstock_multiplier numeric not null default 3,
    high_value_threshold numeric not null default 100000,
    currency text default 'USD',
    timezone text default 'UTC',
    created_at timestamptz not null default now(),
    updated_at timestamptz
);
alter table public.company_settings enable row level security;
create policy "Allow users to read their own company settings" on public.company_settings for select using (company_id = (select company_id from public.users where id = auth.uid()));
create policy "Allow owner/admin to update their own company settings" on public.company_settings for update using (company_id = (select company_id from public.users where id = auth.uid() and role in ('Owner', 'Admin')));


-- Create Suppliers Table
create table if not exists public.suppliers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days int,
    notes text,
    created_at timestamptz not null default now()
);
alter table public.suppliers enable row level security;
create policy "Enable all actions for users based on company" on public.suppliers for all using (company_id = (select company_id from public.users where id = auth.uid()));


-- Create Inventory Table
create table if not exists public.inventory (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    supplier_id uuid references public.suppliers(id) on delete set null,
    sku text not null,
    name text not null,
    category text,
    quantity int not null default 0 check (quantity >= 0),
    cost numeric not null default 0, -- in cents
    price numeric, -- in cents
    reorder_point int,
    last_sold_date date,
    barcode text,
    source_platform text,
    external_product_id text,
    external_variant_id text,
    external_quantity int,
    deleted_at timestamptz,
    deleted_by uuid references auth.users(id),
    created_at timestamptz default now(),
    updated_at timestamptz
);
-- Unique constraint for a product within a company
alter table public.inventory add constraint inventory_company_id_sku_key unique (company_id, sku);
alter table public.inventory enable row level security;
create policy "Enable all actions for users based on company" on public.inventory for all using (company_id = (select company_id from public.users where id = auth.uid()));


-- Create Sales Table
create table if not exists public.sales (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    sale_number text not null,
    customer_name text,
    customer_email text,
    total_amount numeric not null,
    payment_method text,
    notes text,
    external_id text,
    created_at timestamptz default now()
);
alter table public.sales add constraint sales_company_id_sale_number_key unique (company_id, sale_number);
alter table public.sales enable row level security;
create policy "Enable all actions for users based on company" on public.sales for all using (company_id = (select company_id from public.users where id = auth.uid()));


-- Create Sale Items Table
create table if not exists public.sale_items (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    sale_id uuid not null references public.sales(id) on delete cascade,
    sku text not null,
    product_name text,
    quantity int not null,
    unit_price numeric not null,
    cost_at_time numeric
);
alter table public.sale_items enable row level security;
create policy "Enable all actions for users based on company" on public.sale_items for all using (company_id = (select company_id from public.users where id = auth.uid()));


-- Create Customers Table
create table if not exists public.customers (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_name text not null,
    email text,
    total_orders int default 0,
    total_spent numeric default 0,
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz default now()
);
alter table public.customers enable row level security;
create policy "Enable all actions for users based on company" on public.customers for all using (company_id = (select company_id from public.users where id = auth.uid()));


-- Create Inventory Ledger Table
create table if not exists public.inventory_ledger (
    id uuid primary key default uuid_generate_v4(),
    company_id uuid not null references public.companies(id) on delete cascade,
    product_id uuid not null references public.inventory(id) on delete cascade,
    change_type text not null,
    quantity_change int not null,
    new_quantity int not null,
    related_id uuid,
    notes text,
    created_at timestamptz not null default now()
);
alter table public.inventory_ledger enable row level security;
create policy "Enable all actions for users based on company" on public.inventory_ledger for all using (company_id = (select company_id from public.users where id = auth.uid()));


-- Create Audit Log
create table if not exists public.audit_log (
    id bigserial primary key,
    company_id uuid references public.companies(id) on delete cascade,
    user_id uuid references auth.users(id) on delete set null,
    action text not null,
    details jsonb,
    created_at timestamptz default now()
);
alter table public.audit_log enable row level security;
create policy "Enable read for users of their own company" on public.audit_log for select using (company_id = (select company_id from public.users where id = auth.uid()));


-- Create Conversations Table
create table if not exists public.conversations (
    id uuid primary key default uuid_generate_v4(),
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    is_starred boolean default false,
    created_at timestamptz default now(),
    last_accessed_at timestamptz default now()
);
alter table public.conversations enable row level security;
create policy "Enable all actions for user's own conversations" on public.conversations for all using (user_id = auth.uid());


-- Create Messages Table
create table if not exists public.messages (
    id uuid primary key default uuid_generate_v4(),
    conversation_id uuid not null references public.conversations(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    role text not null,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    is_error boolean default false,
    created_at timestamptz default now()
);
alter table public.messages enable row level security;
create policy "Enable all actions for user's own messages" on public.messages for all using (company_id = (select company_id from public.users where id = auth.uid()));

-- Create Integrations Table
create table if not exists public.integrations (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  platform text not null,
  shop_domain text,
  shop_name text,
  is_active boolean default false,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
alter table public.integrations add constraint integrations_company_id_platform_key unique (company_id, platform);
alter table public.integrations enable row level security;
create policy "Enable all actions for users of their company" on public.integrations for all using (company_id = (select company_id from public.users where id = auth.uid()));


-- Create Sync State and Log Tables
create table if not exists public.sync_state (
  integration_id uuid not null references public.integrations(id) on delete cascade,
  sync_type text not null,
  last_processed_cursor text,
  last_update timestamptz,
  primary key (integration_id, sync_type)
);
alter table public.sync_state enable row level security;
create policy "Enable all actions for users of the integration's company" on public.sync_state for all using (
    exists (select 1 from public.integrations where id = integration_id and company_id = (select company_id from public.users where id = auth.uid()))
);

create table if not exists public.sync_logs (
    id uuid primary key default uuid_generate_v4(),
    integration_id uuid not null references public.integrations(id) on delete cascade,
    sync_type text,
    status text,
    records_synced int,
    error_message text,
    started_at timestamptz default now(),
    completed_at timestamptz
);
alter table public.sync_logs enable row level security;
create policy "Enable read for users of the integration's company" on public.sync_logs for select using (
    exists (select 1 from public.integrations where id = integration_id and company_id = (select company_id from public.users where id = auth.uid()))
);


-- Create Channel Fees Table
create table if not exists public.channel_fees (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  channel_name text not null,
  percentage_fee numeric not null,
  fixed_fee numeric not null,
  created_at timestamptz default now(),
  updated_at timestamptz
);
alter table public.channel_fees add constraint channel_fees_company_id_channel_name_key unique (company_id, channel_name);
alter table public.channel_fees enable row level security;
create policy "Enable all actions for users of their company" on public.channel_fees for all using (company_id = (select company_id from public.users where id = auth.uid()));


-- Create Export Jobs Table
create table if not exists public.export_jobs (
  id uuid primary key default uuid_generate_v4(),
  company_id uuid not null references public.companies(id) on delete cascade,
  requested_by_user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending',
  download_url text,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.export_jobs enable row level security;
create policy "Enable all actions for user's own export jobs" on public.export_jobs for all using (requested_by_user_id = auth.uid());



-- =================================================================
-- Handle New User Function & Trigger
-- =================================================================
-- This function runs when a new user signs up.
-- It creates a new company for them and links it to their user account.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer -- IMPORTANT: Allows this function to run with elevated privileges
set search_path = public
as $$
declare
  new_company_id uuid;
begin
  -- Create a new company for the user
  insert into public.companies (name)
  values (new.raw_user_meta_data->>'company_name')
  returning id into new_company_id;

  -- Insert a corresponding entry into the public.users table
  insert into public.users (id, company_id, email, role)
  values (new.id, new_company_id, new.email, 'Owner');
  
  -- Update the user's app_metadata in the auth schema
  update auth.users
  set app_metadata = jsonb_set(
    coalesce(app_metadata, '{}'::jsonb),
    '{company_id}',
    to_jsonb(new_company_id)
  )
  where id = new.id;

  return new;
end;
$$;

-- Drop the existing trigger if it exists, to prevent errors on re-run
drop trigger if exists on_auth_user_created on auth.users;

-- Create the trigger that calls the function
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Grant usage on the auth schema to the postgres user
-- This is necessary to allow the trigger to be created on the auth.users table
grant usage on schema auth to postgres;
grant all on table auth.users to postgres;

-- =================================================================
-- Stored Procedures and Functions
-- =================================================================

-- Function to get distinct categories for a company
create or replace function public.get_distinct_categories(p_company_id uuid)
returns table(category text) as $$
begin
    return query
    select distinct i.category
    from public.inventory i
    where i.company_id = p_company_id and i.category is not null and i.deleted_at is null
    order by i.category;
end;
$$ language plpgsql;

-- Function to record a sale and update inventory atomically
create or replace function public.record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid,
    p_sale_items jsonb,
    p_customer_name text default null,
    p_customer_email text default null,
    p_payment_method text default 'other',
    p_notes text default null,
    p_external_id text default null
)
returns sales as $$
declare
    new_sale sales;
    new_customer_id uuid;
    item record;
    inv_record inventory;
begin
    -- If an external ID is provided, check if the sale already exists
    if p_external_id is not null then
        select * into new_sale from public.sales s
        where s.company_id = p_company_id and s.external_id = p_external_id;

        if found then
            -- Sale already exists, return it without doing anything else
            return new_sale;
        end if;
    end if;
    
    -- Handle customer creation/update
    if p_customer_email is not null then
        select id into new_customer_id from public.customers c
        where c.company_id = p_company_id and c.email = p_customer_email;
        
        if not found then
            insert into public.customers (company_id, customer_name, email)
            values (p_company_id, coalesce(p_customer_name, p_customer_email), p_customer_email)
            returning id into new_customer_id;
        end if;
    end if;

    -- Insert the new sale
    insert into public.sales (company_id, sale_number, customer_name, customer_email, total_amount, payment_method, notes, external_id)
    values (
        p_company_id,
        'INV-' || to_char(now(), 'YYYYMMDD-HH24MISS') || '-' || substr(md5(random()::text), 1, 4),
        p_customer_name,
        p_customer_email,
        (select sum((i->>'unit_price')::numeric * (i->>'quantity')::int) from jsonb_array_elements(p_sale_items) i),
        p_payment_method,
        p_notes,
        p_external_id
    ) returning * into new_sale;

    -- Loop through sale items to update inventory and create sale_items records
    for item in select * from jsonb_to_recordset(p_sale_items) as x(sku text, product_name text, quantity int, unit_price numeric, cost_at_time numeric)
    loop
        -- Find the inventory record
        select * into inv_record from public.inventory i
        where i.company_id = p_company_id and i.sku = item.sku and i.deleted_at is null;

        if found then
            -- Create sale_items entry
            insert into public.sale_items (company_id, sale_id, sku, product_name, quantity, unit_price, cost_at_time)
            values (p_company_id, new_sale.id, item.sku, item.product_name, item.quantity, item.unit_price, inv_record.cost);
            
            -- Update inventory quantity and create ledger entry
            update public.inventory
            set 
                quantity = quantity - item.quantity,
                last_sold_date = now()::date,
                updated_at = now()
            where id = inv_record.id;
            
            insert into public.inventory_ledger (company_id, product_id, change_type, quantity_change, new_quantity, related_id, notes)
            values (p_company_id, inv_record.id, 'sale', -item.quantity, inv_record.quantity - item.quantity, new_sale.id, 'Sale #' || new_sale.sale_number);
        else
            -- Log a warning if SKU not found, but don't fail the transaction
             insert into public.sale_items (company_id, sale_id, sku, product_name, quantity, unit_price, cost_at_time)
            values (p_company_id, new_sale.id, item.sku, item.product_name, item.quantity, item.unit_price, 0);
        end if;
    end loop;
    
    return new_sale;
end;
$$ language plpgsql;

-- Final check on permissions
grant execute on function public.handle_new_user() to supabase_auth_admin;
revoke execute on function public.handle_new_user() from authenticated, anon;
