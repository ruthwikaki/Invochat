
-- ----
-- ## UNIVERSAL FUNCTIONS
-- ----

-- A function to safely get the current user's company_id from their claims.
create or replace function public.get_company_id_for_user(p_user_id uuid)
returns uuid
language sql
stable
as $$
  select coalesce(
    (select company_id from public.company_users where user_id = p_user_id limit 1),
    (select raw_app_meta_data->>'company_id' from auth.users where id = p_user_id)::uuid
  );
$$;

-- A function for RLS policies to check if a user is an admin or owner of their company.
create or replace function public.is_admin_or_owner(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from company_users
    where user_id = p_user_id and (role = 'Admin' or role = 'Owner')
  );
$$;

-- A function to lock a user account for a specified duration.
create or replace function public.lock_user_account(p_user_id uuid, p_lockout_duration interval)
returns void
language plpgsql
security definer
set search_path = auth
as $$
begin
  update users
  set banned_until = now() + p_lockout_duration
  where id = p_user_id;
end;
$$;


-- ----
-- ## COMPANY AND USER MANAGEMENT
-- ----
-- When a new user signs up, this function creates a company for them
-- and assigns them as the owner.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  new_company_id uuid;
  user_company_name text := new.raw_app_meta_data->>'company_name';
begin
  -- Create a new company for the user
  insert into companies (name)
  values (user_company_name)
  returning id into new_company_id;

  -- Link the user to the new company as an Owner
  insert into company_users (user_id, company_id, role)
  values (new.id, new_company_id, 'Owner');

  -- Update the user's app_metadata to include their company_id
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', new_company_id)
  where id = new.id;
  
  -- Create default settings for the new company
  insert into company_settings (company_id) values (new_company_id);

  return new;
end;
$$;


-- Drop the old trigger if it exists, before recreating it.
drop trigger if exists on_auth_user_created on auth.users;

-- This trigger automatically calls the handle_new_user function
-- after a new user is created in the auth.users table.
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ----
-- ## FULL-TEXT SEARCH
-- ----
-- This function updates the `fts_document` tsvector column for a product.
-- It's called by a trigger whenever a product is inserted or updated.
create or replace function public.update_fts_document()
returns trigger
language plpgsql
as $$
begin
  new.fts_document :=
    to_tsvector('english', coalesce(new.title, '')) ||
    to_tsvector('english', coalesce(new.description, '')) ||
    to_tsvector('english', coalesce(new.product_type, ''));
  return new;
end;
$$;

-- Drop the old trigger if it exists.
drop trigger if exists products_fts_update on public.products;

-- Create the trigger that uses the function above.
create trigger products_fts_update
before insert or update on public.products
for each row execute function public.update_fts_document();

-- ----
-- ## DATA SYNC AND INVENTORY MANAGEMENT
-- ----
-- This function is called by the application to record a sale from an external platform.
-- It handles creating or updating customers, orders, and line items, and it adjusts
-- inventory levels atomically.
create or replace function public.record_order_from_platform(p_company_id uuid, p_order_payload jsonb, p_platform text)
returns uuid as $$
declare
    v_customer_id uuid;
    v_order_id uuid;
    line_item jsonb;
    v_variant_id uuid;
begin
    -- Find or create the customer
    insert into customers (company_id, external_customer_id, name, email)
    values (
        p_company_id,
        p_order_payload->'customer'->>'id',
        p_order_payload->'customer'->>'first_name' || ' ' || p_order_payload->'customer'->>'last_name',
        p_order_payload->'customer'->>'email'
    )
    on conflict (company_id, external_customer_id) do update set
        name = excluded.name,
        email = excluded.email
    returning id into v_customer_id;

    -- Create the order
    insert into orders (company_id, external_order_id, customer_id, order_number, total_amount, subtotal, total_tax, total_discounts, total_shipping, currency, financial_status, fulfillment_status, source_platform, created_at)
    values (
        p_company_id,
        p_order_payload->>'id',
        v_customer_id,
        p_order_payload->>'order_number',
        (p_order_payload->>'total_price')::numeric * 100,
        (p_order_payload->>'subtotal_price')::numeric * 100,
        (p_order_payload->>'total_tax')::numeric * 100,
        (p_order_payload->>'total_discounts')::numeric * 100,
        (p_order_payload->'shipping_lines'->0->>'price')::numeric * 100,
        p_order_payload->>'currency',
        p_order_payload->>'financial_status',
        p_order_payload->>'fulfillment_status',
        p_platform,
        (p_order_payload->>'created_at')::timestamptz
    )
    on conflict (company_id, external_order_id) do update set
        total_amount = excluded.total_amount,
        financial_status = excluded.financial_status,
        fulfillment_status = excluded.fulfillment_status,
        updated_at = now()
    returning id into v_order_id;
    
    -- Loop through line items and update inventory
    for line_item in select * from jsonb_array_elements(p_order_payload->'line_items')
    loop
        -- Find the corresponding product variant by SKU
        select id into v_variant_id
        from product_variants
        where company_id = p_company_id and sku = line_item->>'sku'
        limit 1;

        if v_variant_id is not null then
            -- Insert the line item
            insert into order_line_items (order_id, variant_id, company_id, quantity, price, sku, product_name, variant_title, external_line_item_id)
            values (
                v_order_id,
                v_variant_id,
                p_company_id,
                (line_item->>'quantity')::integer,
                (line_item->>'price')::numeric * 100,
                line_item->>'sku',
                line_item->>'name',
                line_item->>'variant_title',
                line_item->>'id'
            );
        end if;
    end loop;
    
    return v_order_id;
end;
$$ language plpgsql;

-- This function is called by a trigger whenever a new order line item is created.
-- It ensures that inventory is decremented and an audit trail is created in the ledger.
create or replace function public.handle_inventory_on_sale()
returns trigger
language plpgsql
security definer
as $$
declare
  v_new_quantity int;
begin
  update product_variants
  set inventory_quantity = inventory_quantity - new.quantity
  where id = new.variant_id
  returning inventory_quantity into v_new_quantity;
  
  insert into inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
  values (new.company_id, new.variant_id, 'sale', -new.quantity, v_new_quantity, new.order_id, 'Order #' || (select order_number from orders where id = new.order_id));
  
  return new;
end;
$$;

drop trigger if exists on_new_order_line_item on public.order_line_items;

create trigger on_new_order_line_item
  after insert on public.order_line_items
  for each row execute procedure public.handle_inventory_on_sale();


-- ----
-- ## RLS (ROW-LEVEL SECURITY)
-- ----
-- Enable RLS for all relevant tables
alter table public.companies enable row level security;
alter table public.company_users enable row level security;
alter table public.company_settings enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.customers enable row level security;
alter table public.suppliers enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_line_items enable row level security;
alter table public.integrations enable row level security;
alter table public.webhook_events enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.messages enable row level security;
alter table public.audit_log enable row level security;

-- Drop existing policies before creating new ones to ensure a clean slate.
drop policy if exists "Users can see their own company" on public.companies;
drop policy if exists "Users can see other users in their company" on public.company_users;
drop policy if exists "User can access their own company data" on public.products;
drop policy if exists "User can access their own company data" on public.product_variants;
drop policy if exists "User can access their own company data" on public.orders;
drop policy if exists "User can access their own company data" on public.order_line_items;
drop policy if exists "User can access their own company data" on public.customers;
drop policy if exists "User can access their own company data" on public.suppliers;
drop policy if exists "User can access their own company data" on public.purchase_orders;
drop policy if exists "User can access their own company data" on public.purchase_order_line_items;
drop policy if exists "User can access their own company data" on public.integrations;
drop policy if exists "User can access their own company data" on public.webhook_events;
drop policy if exists "User can access their own company data" on public.inventory_ledger;
drop policy if exists "User can access their own company data" on public.messages;
drop policy if exists "User can access their own company data" on public.audit_log;
drop policy if exists "User can access their own company settings" on public.company_settings;
drop policy if exists "User can see other users in their company" on auth.users;


-- RLS Policies
create policy "Users can see their own company" on public.companies
  for select using (id = get_company_id_for_user(auth.uid()));

create policy "Users can see other users in their company" on public.company_users
  for select using (company_id = get_company_id_for_user(auth.uid()));
  
create policy "User can access their own company data" on public.products
  for all using (company_id = get_company_id_for_user(auth.uid()));

create policy "User can access their own company data" on public.product_variants
  for all using (company_id = get_company_id_for_user(auth.uid()));

create policy "User can access their own company data" on public.orders
  for all using (company_id = get_company_id_for_user(auth.uid()));

create policy "User can access their own company data" on public.order_line_items
  for all using (company_id = get_company_id_for_user(auth.uid()));

create policy "User can access their own company data" on public.customers
  for all using (company_id = get_company_id_for_user(auth.uid()));

create policy "User can access their own company data" on public.suppliers
  for all using (company_id = get_company_id_for_user(auth.uid()));

create policy "User can access their own company data" on public.purchase_orders
  for all using (company_id = get_company_id_for_user(auth.uid()));
  
create policy "User can access their own company data" on public.purchase_order_line_items
  for all using (company_id = get_company_id_for_user(auth.uid()));

create policy "User can access their own company data" on public.integrations
  for all using (company_id = get_company_id_for_user(auth.uid()));

create policy "User can access their own company data" on public.webhook_events
  for all using (integration_id in (select id from integrations where company_id = get_company_id_for_user(auth.uid())));

create policy "User can access their own company data" on public.inventory_ledger
  for all using (company_id = get_company_id_for_user(auth.uid()));

create policy "User can access their own company data" on public.messages
  for all using (company_id = get_company_id_for_user(auth.uid()));

create policy "User can access their own company data" on public.audit_log
  for all using (company_id = get_company_id_for_user(auth.uid()));

create policy "User can access their own company settings" on public.company_settings
  for all using (company_id = get_company_id_for_user(auth.uid()));

-- This policy allows users to see other users that belong to the same company.
create policy "User can see other users in their company" on auth.users
  for select using (
    id in (
      select user_id from public.company_users where company_id = public.get_company_id_for_user(auth.uid())
    )
  );

-- Add a CHECK constraint to prevent negative inventory
alter table public.product_variants add constraint check_inventory_quantity_non_negative check (inventory_quantity >= 0);
