--
-- Create a new user and assign them to a company.
-- This function is called when a new user signs up.
--
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  company_id uuid;
  user_id uuid;
  company_name text;
begin
  -- Extract user ID and company name from the new user's metadata
  user_id := new.id;
  company_name := new.raw_user_meta_data->>'company_name';

  -- Create a new company for the user
  insert into public.companies (name, owner_id)
  values (company_name, user_id)
  returning id into company_id;
  
  -- Create default settings for the new company
  insert into public.company_settings(company_id)
  values (company_id);

  -- Link the user to the new company with the 'Owner' role
  insert into public.company_users (user_id, company_id, role)
  values (user_id, company_id, 'Owner');
  
  -- Update the user's app_metadata with the new company_id
  update auth.users
  set raw_app_meta_data = jsonb_set(
    coalesce(raw_app_meta_data, '{}'::jsonb),
    '{company_id}',
    to_jsonb(company_id)
  )
  where id = user_id;

  return new;
end;
$$;

--
-- Trigger the function when a new user is created
--
create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


--
-- Decrement inventory when an order is placed.
-- This function is called by the record_order_from_platform function.
--
create or replace function private.decrement_inventory_for_order(
    p_company_id uuid,
    p_line_items jsonb
)
returns void
language plpgsql
as $$
declare
    line_item jsonb;
    v_variant_id uuid;
    v_quantity_to_decrement int;
    v_current_quantity int;
begin
    for line_item in select * from jsonb_array_elements(p_line_items)
    loop
        -- Find the corresponding product variant using the SKU
        select id into v_variant_id
        from public.product_variants
        where sku = line_item->>'sku'
        and company_id = p_company_id;

        if v_variant_id is not null then
            v_quantity_to_decrement := (line_item->>'quantity')::int;

            -- Check for sufficient inventory before decrementing
            select inventory_quantity into v_current_quantity
            from public.product_variants
            where id = v_variant_id;
            
            if v_current_quantity < v_quantity_to_decrement then
                raise exception 'Insufficient inventory for SKU %: Tried to sell %, but only % available.', line_item->>'sku', v_quantity_to_decrement, v_current_quantity;
            end if;

            -- Insert into the ledger, which will trigger the inventory update
            insert into public.inventory_ledger(company_id, variant_id, quantity_change, change_type, notes)
            values (p_company_id, v_variant_id, -v_quantity_to_decrement, 'sale', 'Order placed');
        end if;
    end loop;
end;
$$;


--
-- This trigger function automatically updates the inventory quantity on a product_variant
-- whenever a new entry is added to the inventory_ledger. It also adds a version number
-- for optimistic locking to prevent race conditions.
--
create or replace function private.update_inventory_from_ledger()
returns trigger
language plpgsql
as $$
declare
    v_current_version int;
begin
    -- Get the current version of the product variant
    select version into v_current_version
    from public.product_variants
    where id = new.variant_id;

    -- Update the inventory quantity and increment the version number
    update public.product_variants
    set 
        inventory_quantity = inventory_quantity + new.quantity_change,
        version = version + 1 -- Increment version for optimistic locking
    where id = new.variant_id
      and version = v_current_version; -- Only update if the version has not changed

    -- If no rows were updated, it means a concurrent modification occurred.
    if not found then
        raise exception 'Conflict: Product variant with ID % was modified by another process. Please retry the operation.', new.variant_id;
    end if;

    return new;
end;
$$;


-- Create the trigger that calls the function
create or replace trigger on_inventory_ledger_insert
after insert on public.inventory_ledger
for each row
execute function private.update_inventory_from_ledger();



-- This is the primary table for companies. Each user who signs up creates a new company.
create table if not exists public.companies (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null references auth.users(id),
    name text not null,
    created_at timestamptz not null default now()
);

-- This table links users to companies and defines their role.
create table if not exists public.company_users (
    user_id uuid not null references auth.users(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    role company_role not null default 'Member',
    primary key (user_id, company_id)
);

-- This table stores settings for each company, such as business logic parameters.
create table if not exists public.company_settings (
    company_id uuid primary key references public.companies(id) on delete cascade,
    dead_stock_days int not null default 90,
    fast_moving_days int not null default 30,
    predictive_stock_days int not null default 7,
    overstock_multiplier numeric(10, 2) not null default 3.0,
    high_value_threshold int not null default 100000,
    currency text not null default 'USD',
    tax_rate numeric(5, 4) not null default 0.0000,
    timezone text not null default 'UTC',
    created_at timestamptz not null default now(),
    updated_at timestamptz
);

-- This table stores products, which are the parent entities for variants.
create table if not exists public.products (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    title text not null,
    description text,
    handle text,
    product_type text,
    tags text[],
    status text,
    image_url text,
    external_product_id text,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique(company_id, external_product_id)
);

-- This table stores suppliers for each company.
create table if not exists public.suppliers (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text not null,
    email text,
    phone text,
    default_lead_time_days int,
    notes text,
    created_at timestamptz not null default now(),
    updated_at timestamptz
);

-- This table stores product variants, which represent the actual sellable items (SKUs).
create table if not exists public.product_variants (
    id uuid primary key default gen_random_uuid(),
    product_id uuid not null references public.products(id) on delete cascade,
    company_id uuid not null references public.companies(id) on delete cascade,
    supplier_id uuid references public.suppliers(id) on delete set null,
    sku text not null,
    title text,
    option1_name text,
    option1_value text,
    option2_name text,
    option2_value text,
    option3_name text,
    option3_value text,
    barcode text,
    price int, -- in cents
    compare_at_price int, -- in cents
    cost int, -- in cents
    inventory_quantity int not null default 0,
    location text,
    external_variant_id text,
    reorder_point int,
    reorder_quantity int,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    version int not null default 1, -- For optimistic locking
    unique(company_id, sku),
    unique(company_id, external_variant_id)
);

-- This table stores customers associated with each company.
create table if not exists public.customers (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    name text,
    email text,
    phone text,
    external_customer_id text,
    deleted_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique(company_id, email),
    unique(company_id, external_customer_id)
);

-- This table stores sales orders.
create table if not exists public.orders (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    customer_id uuid references public.customers(id) on delete set null,
    order_number text not null,
    external_order_id text,
    financial_status text,
    fulfillment_status text,
    currency text,
    subtotal int not null,
    total_tax int,
    total_shipping int,
    total_discounts int,
    total_amount int not null,
    source_platform text,
    created_at timestamptz not null default now(),
    updated_at timestamptz,
    unique(company_id, external_order_id)
);

-- This table stores line items for each order.
create table if not exists public.order_line_items (
    id uuid primary key default gen_random_uuid(),
    order_id uuid not null references public.orders(id) on delete cascade,
    variant_id uuid references public.product_variants(id) on delete set null,
    company_id uuid not null references public.companies(id) on delete cascade,
    product_name text,
    variant_title text,
    sku text,
    quantity int not null,
    price int not null, -- in cents
    total_discount int, -- in cents
    tax_amount int, -- in cents
    cost_at_time int, -- in cents
    external_line_item_id text
);

-- This table is a ledger for all inventory movements.
create table if not exists public.inventory_ledger (
    id uuid primary key default gen_random_uuid(),
    company_id uuid not null references public.companies(id) on delete cascade,
    variant_id uuid not null references public.product_variants(id) on delete cascade,
    quantity_change int not null,
    new_quantity int not null,
    change_type text not null, -- e.g., 'sale', 'purchase_order', 'manual_adjustment'
    related_id text, -- e.g., order_id, purchase_order_id
    notes text,
    created_at timestamptz not null default now()
);
