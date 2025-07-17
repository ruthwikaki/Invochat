--
-- Enforce RLS for all tables in the public schema
--
create or replace function public.enable_rls_for_all_tables(schema_name text)
returns void
language plpgsql
as $$
declare
    table_record record;
begin
    for table_record in
        select tablename
        from pg_tables
        where schemaname = schema_name
    loop
        execute format('alter table %I.%I enable row level security', schema_name, table_record.tablename);
        
        -- Drop the policy if it exists, to ensure this script is re-runnable
        execute format('drop policy if exists "Allow all access to own company data" on %I.%I', schema_name, table_record.tablename);

        -- Create a generic policy assuming a `company_id` column exists
        if exists (
            select 1
            from information_schema.columns
            where table_schema = schema_name
            and table_name = table_record.tablename
            and column_name = 'company_id'
        ) then
             execute format('create policy "Allow all access to own company data" on %I.%I for all using (company_id = public.get_company_id());', schema_name, table_record.tablename);
        
        -- Special handling for the 'companies' table itself
        elsif table_record.tablename = 'companies' then
             execute format('create policy "Allow all access to own company data" on %I.%I for all using (id = public.get_company_id());', schema_name, table_record.tablename);
        
        -- Special handling for webhook_events table
        elsif table_record.tablename = 'webhook_events' then
             execute format('
                create policy "Allow all access to own company data" on %I.%I for all 
                using (
                    integration_id in (select id from public.integrations where company_id = public.get_company_id())
                );', schema_name, table_record.tablename);

        end if;
    end loop;
end;
$$;


--
-- Creates a company and a user profile upon new user signup.
-- This function is called by a trigger on the auth.users table.
--
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  company_id uuid;
  user_email text;
  company_name text;
  user_role text;
begin
  -- Extract details from the new user record
  user_email := new.email;
  company_name := new.raw_app_meta_data->>'company_name';
  user_role := 'Owner'; -- The first user is always the Owner

  -- Create a new company for the user
  insert into public.companies (name)
  values (company_name)
  returning id into company_id;

  -- Create a corresponding user profile in the public.users table
  insert into public.users (id, company_id, email, role)
  values (new.id, company_id, user_email, user_role);

  -- Update the user's app_metadata in the auth schema with the new company_id and role
  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', company_id, 'role', user_role)
  where id = new.id;

  return new;
end;
$$;

--
-- Trigger to call handle_new_user on new user creation
--
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


--
-- Utility function to get the current user's company_id
--
create or replace function public.get_company_id()
returns uuid
language sql
security definer
set search_path = public
as $$
    select nullif(current_setting('request.jwt.claims', true)::jsonb->'app_metadata'->>'company_id', '')::uuid;
$$;

--
-- Helper function to get a user's role within a company
--
create or replace function public.get_user_role(user_id uuid, company_id uuid)
returns text
language sql
security definer
as $$
  select role from public.users
  where id = user_id and company_id = company_id;
$$;


--
-- RPC to get users associated with a company
--
create or replace function public.get_users_for_company(p_company_id uuid)
returns table (id uuid, email text, role text)
language plpgsql
as $$
begin
  if (select public.get_company_id()) = p_company_id then
    return query
    select u.id, u.email, u.role
    from public.users u
    where u.company_id = p_company_id and u.deleted_at is null;
  else
    raise exception 'User is not authorized to access this company.';
  end if;
end;
$$;

--
-- RPC to remove a user from a company (soft delete)
--
create or replace function public.remove_user_from_company(
    p_user_id uuid,
    p_company_id uuid,
    p_performing_user_id uuid
)
returns void
language plpgsql
security definer
as $$
declare
    performing_user_role text;
begin
    -- Check if the performing user is an Admin or Owner of the company
    select get_user_role(p_performing_user_id, p_company_id) into performing_user_role;
    if performing_user_role not in ('Admin', 'Owner') then
        raise exception 'Only Admins or Owners can remove users.';
    end if;

    -- Update the user's record to mark as deleted
    update public.users
    set deleted_at = now()
    where id = p_user_id and company_id = p_company_id;

    -- Remove company-specific metadata from auth.users
    update auth.users
    set raw_app_meta_data = raw_app_meta_data - 'company_id' - 'role'
    where id = p_user_id;
end;
$$;

--
-- RPC to update a user's role
--
create or replace function public.update_user_role_in_company(
    p_user_id uuid,
    p_company_id uuid,
    p_new_role text
)
returns void
language plpgsql
security definer
as $$
begin
    -- Update the role in the public.users table
    update public.users
    set role = p_new_role
    where id = p_user_id and company_id = p_company_id;

    -- Update the role in the auth.users app_metadata
    update auth.users
    set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('role', p_new_role)
    where id = p_user_id;
end;
$$;

--
-- Full Text Search Setup for Products
--
alter table products
add column fts_document tsvector;

create or replace function update_fts_document()
returns trigger as $$
begin
    new.fts_document := to_tsvector('english',
        coalesce(new.title, '') || ' ' ||
        coalesce(new.description, '') || ' ' ||
        coalesce(array_to_string(new.tags, ' '), '')
    );
    return new;
end;
$$ language plpgsql;

create trigger fts_update_trigger
before insert or update on products
for each row
execute function update_fts_document();

-- Create a GIN index for faster full-text search
create index idx_products_fts on products using gin(fts_document);

--
-- Create indexes for performance
--
create index if not exists idx_product_variants_sku on product_variants(company_id, sku);
create index if not exists idx_orders_company_created on orders(company_id, created_at desc);
create index if not exists idx_order_line_items_order_id on order_line_items(order_id);
create index if not exists idx_inventory_ledger_variant_id on inventory_ledger(variant_id, created_at desc);
create index if not exists idx_orders_company_created_status ON orders(company_id, created_at DESC, status);
create index if not exists idx_order_line_items_variant_order ON order_line_items(variant_id, order_id);

--
-- Materialized Views for Performance
--
create materialized view if not exists daily_sales as
select
  date_trunc('day', o.created_at) as sale_date,
  o.company_id,
  sum(oli.quantity) as total_quantity,
  sum(oli.price * oli.quantity) as total_revenue
from orders o
join order_line_items oli on o.id = oli.order_id
group by 1, 2;

create unique index if not exists on daily_sales(sale_date, company_id);

--
-- View to unify product and variant details for easy querying
--
create or replace view product_variants_with_details with (security_invoker=true) as
select
    pv.*,
    p.title as product_title,
    p.status as product_status,
    p.image_url as image_url,
    p.product_type
from product_variants pv
join products p on pv.product_id = p.id;

--
-- View to unify orders with customer details
--
create or replace view orders_view as
select
    o.*,
    c.customer_name,
    c.email as customer_email,
    i.shop_name
from orders o
left join customers c on o.customer_id = c.id
left join integrations i on o.source_platform = i.platform and o.company_id = i.company_id;

--
-- View to unify customers with total spend and order counts
--
create or replace view customers_view as
select
    c.id,
    c.company_id,
    c.customer_name,
    c.email,
    c.first_order_date,
    c.created_at,
    coalesce(o.total_orders, 0) as total_orders,
    coalesce(o.total_spent, 0) as total_spent
from customers c
left join (
    select
        customer_id,
        count(*) as total_orders,
        sum(total_amount) as total_spent
    from orders
    group by customer_id
) o on c.id = o.customer_id
where c.deleted_at is null;


--
-- Create a transactionally-safe function to record a sale
--
create or replace function record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid, -- Can be null for automated syncs
    p_customer_name text,
    p_customer_email text,
    p_payment_method text,
    p_notes text,
    p_sale_items jsonb[],
    p_external_id text default null
)
returns void as $$
declare
    v_customer_id uuid;
    v_order_id uuid;
    sale_item jsonb;
    v_variant_id uuid;
    v_quantity int;
    v_unit_price int;
    v_cost_at_time int;
    v_product_name text;
begin
    -- Find or create the customer
    select id into v_customer_id from customers where email = p_customer_email and company_id = p_company_id;
    if v_customer_id is null then
        insert into customers (company_id, customer_name, email)
        values (p_company_id, p_customer_name, p_customer_email)
        returning id into v_customer_id;
    end if;

    -- Create the order
    insert into orders (company_id, customer_id, order_number, total_amount, source_platform, external_order_id, financial_status, fulfillment_status)
    values (p_company_id, v_customer_id, 'SALE-' || substr(uuid_generate_v4()::text, 1, 8), 0, 'manual', p_external_id, 'paid', 'fulfilled')
    returning id into v_order_id;
    
    -- Loop through sale items
    foreach sale_item in array p_sale_items
    loop
        select id, product_title into v_variant_id, v_product_name from product_variants_with_details where sku = sale_item->>'sku' and company_id = p_company_id;
        v_quantity := (sale_item->>'quantity')::int;
        v_unit_price := (sale_item->>'unit_price')::int;
        v_cost_at_time := (sale_item->>'cost_at_time')::int;

        if v_variant_id is null then
            -- In a real app, might want to handle this more gracefully
            raise exception 'Product with SKU % not found', sale_item->>'sku';
        end if;
        
        -- Insert into order_line_items
        insert into order_line_items (order_id, company_id, variant_id, product_name, sku, quantity, price, cost_at_time)
        values (v_order_id, p_company_id, v_variant_id, v_product_name, sale_item->>'sku', v_quantity, v_unit_price, v_cost_at_time);
        
        -- Update inventory (will trigger ledger insert)
        update product_variants set inventory_quantity = inventory_quantity - v_quantity where id = v_variant_id;
    end loop;
    
    -- Update the order total
    update orders set total_amount = (
        select sum(quantity * price) from order_line_items where order_id = v_order_id
    ) where id = v_order_id;

    -- Create audit log
    insert into audit_log (company_id, user_id, action, details)
    values (p_company_id, p_user_id, 'manual_sale_created', jsonb_build_object('order_id', v_order_id));

end;
$$ language plpgsql;


--
-- Create a transactionally-safe function to create Purchase Orders from suggestions
--
create or replace function create_purchase_orders_from_suggestions(
    p_company_id uuid,
    p_user_id uuid,
    p_suggestions jsonb,
    p_idempotency_key uuid default null
)
returns integer as $$
declare
    supplier_id uuid;
    new_po_id uuid;
    suggestion jsonb;
    total_cost integer;
    po_count integer := 0;
begin
    -- Check for idempotency
    if p_idempotency_key is not null and exists (select 1 from purchase_orders where idempotency_key = p_idempotency_key) then
        return 0; -- A previous request with the same key was already processed.
    end if;

    -- Group suggestions by supplier
    for supplier_id in select distinct (value->>'supplier_id')::uuid from jsonb_array_elements(p_suggestions)
    loop
        -- Begin a transaction for this supplier's PO
        begin
            total_cost := 0;

            insert into purchase_orders (company_id, supplier_id, status, po_number, total_cost, idempotency_key)
            values (p_company_id, supplier_id, 'Ordered', 'PO-' || to_char(now(), 'YYYYMMDD') || '-' || substr(uuid_generate_v4()::text, 1, 4), 0, p_idempotency_key)
            returning id into new_po_id;

            for suggestion in select * from jsonb_array_elements(p_suggestions) where (value->>'supplier_id')::uuid = supplier_id
            loop
                insert into purchase_order_line_items (purchase_order_id, company_id, variant_id, quantity, cost)
                values (new_po_id, p_company_id, (suggestion->>'variant_id')::uuid, (suggestion->>'suggested_reorder_quantity')::integer, (suggestion->>'unit_cost')::integer);

                total_cost := total_cost + ((suggestion->>'suggested_reorder_quantity')::integer * (suggestion->>'unit_cost')::integer);
            end loop;

            update purchase_orders set total_cost = total_cost where id = new_po_id;
            
            po_count := po_count + 1;
        exception 
            when others then
                -- Log the error and rollback this PO's transaction
                insert into audit_log (company_id, user_id, action, details)
                values (p_company_id, p_user_id, 'po_creation_failed', jsonb_build_object('supplier_id', supplier_id, 'error', SQLERRM));
                -- Let the overall function continue to the next supplier
        end;
    end loop;
    
    return po_count;
end;
$$ language plpgsql;


-- Final step: Enable RLS on all tables in the public schema
select public.enable_rls_for_all_tables('public');
