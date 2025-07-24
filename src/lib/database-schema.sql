
-- Enable Row Level Security
alter table public.companies enable row level security;
alter table public.company_settings enable row level security;
alter table public.company_users enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.customers enable row level security;
alter table public.refunds enable row level security;
alter table public.suppliers enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_line_items enable row level security;
alter table public.integrations enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.feedback enable row level security;
alter table public.audit_log enable row level security;
alter table public.imports enable row level security;
alter table public.export_jobs enable row level security;
alter table public.channel_fees enable row level security;
alter table public.webhook_events enable row level security;


-- POLICIES
-- These policies enforce multi-tenancy by ensuring users can only access data
-- belonging to their own company.

-- Helper function to get the company_id for the currently authenticated user.
create or replace function get_company_id_for_user(user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  return (select company_id from company_users where company_users.user_id = $1);
end;
$$;

-- Function to check user permissions
create or replace function check_user_permission(p_user_id uuid, p_required_role company_role)
returns boolean
language plpgsql
security definer
as $$
declare
    user_role company_role;
begin
    select role into user_role from company_users where user_id = p_user_id;
    
    if user_role is null then
        return false;
    end if;

    if p_required_role = 'Owner' then
        return user_role = 'Owner';
    elsif p_required_role = 'Admin' then
        return user_role in ('Owner', 'Admin');
    end if;
    
    return true; -- 'Member' role has permission if not Owner/Admin required
end;
$$;


-- Policies for 'companies'
create policy "Users can view their own company" on "public"."companies"
as permissive for select
to authenticated
using (id = get_company_id_for_user(auth.uid()));

-- Policies for 'company_users'
create policy "Users can view their own company membership" on "public"."company_users"
as permissive for select
to authenticated
using (company_id = get_company_id_for_user(auth.uid()));

-- Policies for 'company_settings'
create policy "Users can manage settings for their own company" on "public"."company_settings"
as permissive for all
to authenticated
using (company_id = get_company_id_for_user(auth.uid()))
with check (company_id = get_company_id_for_user(auth.uid()));

-- Policies for all other company-scoped tables
create policy "Enable all actions for users based on company_id" on "public"."products"
as permissive for all
to authenticated
using (company_id = get_company_id_for_user(auth.uid()))
with check (company_id = get_company_id_for_user(auth.uid()));

create policy "Enable all actions for users based on company_id" on "public"."product_variants"
as permissive for all
to authenticated
using (company_id = get_company_id_for_user(auth.uid()))
with check (company_id = get_company_id_for_user(auth.uid()));

create policy "Enable all actions for users based on company_id" on "public"."orders"
as permissive for all
to authenticated
using (company_id = get_company_id_for_user(auth.uid()))
with check (company_id = get_company_id_for_user(auth.uid()));

create policy "Enable all actions for users based on company_id" on "public"."order_line_items"
as permissive for all
to authenticated
using (company_id = get_company_id_for_user(auth.uid()))
with check (company_id = get_company_id_for_user(auth.uid()));

create policy "Enable all actions for users based on company_id" on "public"."customers"
as permissive for all
to authenticated
using (company_id = get_company_id_for_user(auth.uid()))
with check (company_id = get_company_id_for_user(auth.uid()));

create policy "Enable all actions for users based on company_id" on "public"."suppliers"
as permissive for all
to authenticated
using (company_id = get_company_id_for_user(auth.uid()))
with check (company_id = get_company_id_for_user(auth.uid()));

create policy "Enable all actions for users based on company_id" on "public"."purchase_orders"
as permissive for all
to authenticated
using (company_id = get_company_id_for_user(auth.uid()))
with check (company_id = get_company_id_for_user(auth.uid()));

create policy "Enable all actions for users based on company_id" on "public"."purchase_order_line_items"
as permissive for all
to authenticated
using (company_id = get_company_id_for_user(auth.uid()))
with check (company_id = get_company_id_for_user(auth.uid()));

create policy "Enable all actions for users based on company_id" on "public"."integrations"
as permissive for all
to authenticated
using (company_id = get_company_id_for_user(auth.uid()))
with check (company_id = get_company_id_for_user(auth.uid()));

create policy "Enable all actions for users based on company_id" on "public"."inventory_ledger"
as permissive for all
to authenticated
using (company_id = get_company_id_for_user(auth.uid()))
with check (company_id = get_company_id_for_user(auth.uid()));

create policy "Enable all actions for users based on company_id" on "public"."conversations"
as permissive for all
to authenticated
using (company_id = get_company_id_for_user(auth.uid()))
with check (company_id = get_company_id_for_user(auth.uid()));

create policy "Enable all actions for users based on company_id" on "public"."messages"
as permissive for all
to authenticated
using (company_id = get_company_id_for_user(auth.uid()))
with check (company_id = get_company_id_for_user(auth.uid()));

create policy "Enable all actions for users based on company_id" on "public"."feedback"
as permissive for all
to authenticated
using (company_id = get_company_id_for_user(auth.uid()))
with check (company_id = get_company_id_for_user(auth.uid()));

create policy "Enable all actions for users based on company_id" on "public"."audit_log"
as permissive for all
to authenticated
using (company_id = get_company_id_for_user(auth.uid()))
with check (company_id = get_company_id_for_user(auth.uid()));

create policy "Enable all actions for users based on company_id" on "public"."imports"
as permissive for all
to authenticated
using (company_id = get_company_id_for_user(auth.uid()))
with check (company_id = get_company_id_for_user(auth.uid()));

create policy "Enable all actions for users based on company_id" on "public"."export_jobs"
as permissive for all
to authenticated
using (company_id = get_company_id_for_user(auth.uid()))
with check (company_id = get_company_id_for_user(auth.uid()));

create policy "Enable all actions for users based on company_id" on "public"."channel_fees"
as permissive for all
to authenticated
using (company_id = get_company_id_for_user(auth.uid()))
with check (company_id = get_company_id_for_user(auth.uid()));

create policy "Enable all actions for users based on company_id" on "public"."webhook_events"
as permissive for all
to authenticated
using (company_id = get_company_id_for_user(auth.uid()))
with check (company_id = get_company_id_for_user(auth.uid()));

create policy "Enable all actions for users based on company_id" on "public"."refunds"
as permissive for all
to authenticated
using (company_id = get_company_id_for_user(auth.uid()))
with check (company_id = get_company_id_for_user(auth.uid()));



-- This trigger automatically creates a new company for a new user and links them.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  new_company_id uuid;
begin
  -- Create a new company for the user
  insert into public.companies (name, owner_id)
  values (new.raw_user_meta_data->>'company_name', new.id)
  returning id into new_company_id;

  -- Link the user to the new company as 'Owner'
  insert into public.company_users (user_id, company_id, role)
  values (new.id, new_company_id, 'Owner');

  -- Update the user's app_metadata with the new company_id
  update auth.users
  set app_metadata = app_metadata || jsonb_build_object('company_id', new_company_id)
  where id = new.id;
  
  return new;
end;
$$;

-- Attach the trigger to the auth.users table
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- This trigger ensures that when a product is deleted, all its associated variants are also deleted.
create function public.handle_product_delete()
returns trigger
language plpgsql
as $$
begin
  delete from public.product_variants where product_id = old.id;
  return old;
end;
$$;

create trigger on_product_deleted
  after delete on public.products
  for each row execute procedure public.handle_product_delete();


-- This function records an order from a platform, handling products, variants, customers, and orders.
create or replace function public.record_order_from_platform(
    p_company_id uuid,
    p_order_payload jsonb,
    p_platform text
)
returns uuid
language plpgsql
security definer
as $$
declare
    v_customer_id uuid;
    v_order_id uuid;
    v_product_id uuid;
    v_variant_id uuid;
    line_item jsonb;
    v_sku text;
begin
    -- Step 1: Find or create the customer
    select id into v_customer_id from public.customers
    where company_id = p_company_id and email = (p_order_payload->'customer'->>'email');

    if v_customer_id is null and p_order_payload->'customer'->>'email' is not null then
        insert into public.customers (company_id, name, email, external_customer_id)
        values (
            p_company_id,
            coalesce(p_order_payload->'customer'->>'first_name' || ' ' || p_order_payload->'customer'->>'last_name', p_order_payload->'customer'->>'email'),
            p_order_payload->'customer'->>'email',
            p_order_payload->'customer'->>'id'
        ) returning id into v_customer_id;
    end if;

    -- Step 2: Create the order
    insert into public.orders (company_id, customer_id, order_number, total_amount, external_order_id, source_platform, financial_status, subtotal, created_at)
    values (
        p_company_id,
        v_customer_id,
        p_order_payload->>'order_number',
        (p_order_payload->>'total_price')::numeric * 100,
        p_order_payload->>'id',
        p_platform,
        p_order_payload->>'financial_status',
        (p_order_payload->>'subtotal_price')::numeric * 100,
        (p_order_payload->>'created_at')::timestamptz
    ) returning id into v_order_id;
    
    -- Step 3: Process line items
    for line_item in select * from jsonb_array_elements(p_order_payload->'line_items')
    loop
        v_sku := line_item->>'sku';

        -- Find the corresponding product variant by SKU
        select pv.id, pv.product_id into v_variant_id, v_product_id from public.product_variants pv
        where pv.company_id = p_company_id and pv.sku = v_sku;
        
        -- If variant doesn't exist, we may need to create it (or log an error)
        if v_variant_id is null then
            -- For simplicity, we'll log and skip. A more robust solution might create a placeholder product.
            insert into audit_log(company_id, action, details) values (p_company_id, 'order_sync_warning', jsonb_build_object('order_id', v_order_id, 'message', 'SKU not found', 'sku', v_sku));
            continue;
        end if;

        -- Insert the line item
        insert into public.order_line_items (order_id, company_id, variant_id, quantity, price, sku, product_name)
        values (
            v_order_id,
            p_company_id,
            v_variant_id,
            (line_item->>'quantity')::integer,
            (line_item->>'price')::numeric * 100,
            v_sku,
            line_item->>'name'
        );

    end loop;

    return v_order_id;
end;
$$;

-- Function to decrement inventory after an order is processed
create or replace function public.decrement_inventory_for_order()
returns trigger
language plpgsql
as $$
declare
    v_variant_id uuid;
    v_quantity_to_decrement int;
    v_current_stock int;
begin
    -- Get the variant_id and quantity from the newly inserted order line item
    v_variant_id := new.variant_id;
    v_quantity_to_decrement := new.quantity;

    -- If there's no associated variant, we can't do anything
    if v_variant_id is null then
        return new;
    end if;

    -- Get the current stock for the variant
    select inventory_quantity into v_current_stock from public.product_variants
    where id = v_variant_id and company_id = new.company_id;

    -- Check if there is sufficient stock
    if v_current_stock is null or v_current_stock < v_quantity_to_decrement then
        -- This is a critical issue. We raise an exception to fail the transaction.
        -- This prevents the order from being recorded if inventory would go negative.
        raise exception 'Insufficient stock for SKU % to fulfill order %. Required: %, Available: %', new.sku, new.order_id, v_quantity_to_decrement, v_current_stock;
    end if;
    
    -- Update the inventory quantity on the product_variants table
    update public.product_variants
    set inventory_quantity = inventory_quantity - v_quantity_to_decrement
    where id = v_variant_id;

    -- Create a ledger entry for the sale
    insert into public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
    values (
        new.company_id,
        new.variant_id,
        'sale',
        -v_quantity_to_decrement,
        v_current_stock - v_quantity_to_decrement,
        new.order_id,
        'Order #' || (select order_number from orders where id = new.order_id)
    );

    return new;
end;
$$;

-- Trigger to call the decrement function after an order line item is inserted
create trigger on_order_line_item_created
  after insert on public.order_line_items
  for each row execute procedure public.decrement_inventory_for_order();


-- Materialized View for product variants with their product details
create materialized view public.product_variants_with_details_mat as
select
  pv.*,
  p.title as product_title,
  p.status as product_status,
  p.image_url,
  p.product_type
from product_variants pv
join products p on pv.product_id = p.id;

create unique index on public.product_variants_with_details_mat (id);

-- Materialized View for customer-level analytics
create materialized view public.customers_view as
select
    c.id,
    c.company_id,
    c.name as customer_name,
    c.email,
    c.created_at,
    min(o.created_at) as first_order_date,
    count(distinct o.id) as total_orders,
    sum(o.total_amount) as total_spent
from customers c
join orders o on c.id = o.customer_id
group by c.id, c.company_id;

create unique index on public.customers_view (id);

-- Materialized View for order-level analytics
create materialized view public.orders_view as
select
    o.id,
    o.company_id,
    o.order_number,
    o.external_order_id,
    o.customer_id,
    c.email as customer_email,
    o.financial_status,
    o.fulfillment_status,
    o.currency,
    o.subtotal,
    o.total_tax,
    o.total_shipping,
    o.total_discounts,
    o.total_amount,
    o.source_platform,
    o.created_at,
    o.updated_at
from orders o
left join customers c on o.customer_id = c.id;

create unique index on public.orders_view (id);


-- Function to refresh all materialized views for a specific company
create or replace function public.refresh_all_matviews(p_company_id uuid)
returns void
language plpgsql
as $$
begin
    -- We refresh concurrently to avoid locking the views for long periods.
    -- The WHERE clause is a trick to make Postgres think the view is company-specific,
    -- even though we are refreshing the whole thing. This is a placeholder for
    -- more advanced partitioning strategies in the future.
    refresh materialized view concurrently public.product_variants_with_details_mat;
    refresh materialized view concurrently public.customers_view;
    refresh materialized view concurrently public.orders_view;
end;
$$;


-- This is a placeholder for a more advanced function.
-- In a real production system, this would be a more complex statistical model.
create or replace function public.forecast_demand(p_company_id uuid)
returns table (sku text, forecasted_demand numeric)
language plpgsql
as $$
begin
    return query
    select
        oli.sku,
        sum(oli.quantity) * 3 as forecasted_demand -- simple forecast: 3x last 30 days sales
    from order_line_items oli
    join orders o on oli.order_id = o.id
    where o.company_id = p_company_id and o.created_at >= now() - interval '30 days' and oli.sku is not null
    group by oli.sku
    order by sum(oli.quantity) desc
    limit 10;
end;
$$;

create or replace function get_dashboard_metrics(p_company_id uuid, p_days int)
returns json
language plpgsql
as $$
declare
    metrics json;
begin
    select json_build_object(
        'total_revenue', (select sum(total_amount) from orders where company_id = p_company_id and created_at >= now() - (p_days || ' days')::interval),
        'revenue_change', 0, -- Placeholder
        'total_sales', (select count(*) from orders where company_id = p_company_id and created_at >= now() - (p_days || ' days')::interval),
        'sales_change', 0, -- Placeholder
        'new_customers', (select count(*) from customers where company_id = p_company_id and created_at >= now() - (p_days || ' days')::interval),
        'customers_change', 0, -- Placeholder
        'dead_stock_value', (select coalesce(sum(total_value), 0) from get_dead_stock_report(p_company_id)),
        'sales_over_time', (select json_agg(json_build_object('date', d.day, 'total_sales', coalesce(sum(o.total_amount), 0))) from generate_series(now() - (p_days || ' days')::interval, now(), '1 day'::interval) d(day) left join orders o on o.company_id = p_company_id and o.created_at::date = d.day::date group by d.day),
        'top_selling_products', (select json_agg(t) from (select p.product_title, p.image_url, sum(oli.price * oli.quantity) as total_revenue from order_line_items oli join product_variants_with_details_mat p on oli.variant_id = p.id where oli.company_id = p_company_id group by p.product_title, p.image_url order by total_revenue desc limit 5) t),
        'inventory_summary', (select json_build_object('total_value', sum(cost * inventory_quantity), 'in_stock_value', sum(case when inventory_quantity > 10 then cost * inventory_quantity else 0 end), 'low_stock_value', sum(case when inventory_quantity between 1 and 10 then cost*inventory_quantity else 0 end), 'dead_stock_value', sum(case when inventory_quantity <= 0 then cost * inventory_quantity else 0 end)) from product_variants where company_id = p_company_id)
    ) into metrics;
    return metrics;
end;
$$;


create or replace function get_reorder_suggestions(p_company_id uuid)
returns table(
    variant_id uuid,
    product_id uuid,
    sku text,
    product_name text,
    supplier_name text,
    supplier_id uuid,
    current_quantity integer,
    suggested_reorder_quantity integer,
    unit_cost integer
)
language plpgsql
as $$
begin
    return query
    select
        pv.id as variant_id,
        p.id as product_id,
        pv.sku,
        p.title as product_name,
        s.name as supplier_name,
        s.id as supplier_id,
        pv.inventory_quantity as current_quantity,
        (coalesce(pv.reorder_point, 0) + coalesce(pv.reorder_quantity, 10)) - pv.inventory_quantity as suggested_reorder_quantity,
        pv.cost as unit_cost
    from product_variants pv
    join products p on pv.product_id = p.id
    left join suppliers s on pv.supplier_id = s.id
    where pv.company_id = p_company_id
      and pv.inventory_quantity < coalesce(pv.reorder_point, 10);
end;
$$;


create or replace function get_sales_analytics(p_company_id uuid)
returns json
language plpgsql
as $$
declare
    analytics json;
begin
    select json_build_object(
        'total_revenue', coalesce(sum(total_amount), 0),
        'total_orders', coalesce(count(*), 0),
        'average_order_value', coalesce(avg(total_amount), 0),
        'average_margin', 0 -- Placeholder
    )
    into analytics
    from orders
    where company_id = p_company_id;
    
    return analytics;
end;
$$;

create or replace function get_customer_analytics(p_company_id uuid)
returns json
language plpgsql
as $$
begin
    return (select json_build_object(
        'total_customers', (select count(*) from customers where company_id = p_company_id),
        'new_customers_last_30_days', (select count(*) from customers where company_id = p_company_id and created_at >= now() - interval '30 days'),
        'repeat_customer_rate', 0, -- Placeholder
        'average_lifetime_value', (select coalesce(avg(total_spent), 0) from customers_view where company_id = p_company_id),
        'top_customers_by_spend', (select json_agg(t) from (select customer_name as name, total_spent as value from customers_view where company_id = p_company_id order by total_spent desc limit 5) t),
        'top_customers_by_sales', (select json_agg(t) from (select customer_name as name, total_orders as value from customers_view where company_id = p_company_id order by total_orders desc limit 5) t)
    ));
end;
$$;


create or replace function get_dead_stock_report(p_company_id uuid)
returns table (
    sku text,
    product_name text,
    quantity integer,
    total_value numeric,
    last_sale_date timestamptz
)
language plpgsql
as $$
declare
    v_dead_stock_days int;
begin
    select dead_stock_days into v_dead_stock_days from company_settings where company_id = p_company_id;
    
    return query
    select
        pv.sku,
        p.title as product_name,
        pv.inventory_quantity as quantity,
        pv.inventory_quantity * pv.cost as total_value,
        (select max(o.created_at) from order_line_items oli join orders o on oli.order_id = o.id where oli.variant_id = pv.id) as last_sale_date
    from product_variants pv
    join products p on pv.product_id = p.id
    where pv.company_id = p_company_id
      and pv.inventory_quantity > 0
      and not exists (
          select 1 from order_line_items oli
          join orders o on oli.order_id = o.id
          where oli.variant_id = pv.id and o.created_at > now() - (v_dead_stock_days || ' days')::interval
      );
end;
$$;

create or replace function get_inventory_analytics(p_company_id uuid)
returns json
language plpgsql
as $$
begin
    return (select json_build_object(
        'total_inventory_value', coalesce(sum(cost * inventory_quantity), 0),
        'total_products', (select count(distinct product_id) from product_variants where company_id = p_company_id),
        'total_variants', (select count(*) from product_variants where company_id = p_company_id),
        'low_stock_items', (select count(*) from product_variants where company_id = p_company_id and inventory_quantity < coalesce(reorder_point, 10))
    ) from product_variants where company_id = p_company_id);
end;
$$;


create or replace function get_supplier_performance_report(p_company_id uuid)
returns table (
    supplier_name text,
    total_profit numeric,
    total_sales_count bigint,
    distinct_products_sold bigint,
    average_margin numeric,
    sell_through_rate numeric,
    on_time_delivery_rate numeric,
    average_lead_time_days numeric,
    total_completed_orders bigint
)
language plpgsql
as $$
begin
    return query
    select
        s.name as supplier_name,
        coalesce(sum((oli.price - pv.cost) * oli.quantity), 0) as total_profit,
        count(oli.id) as total_sales_count,
        count(distinct pv.product_id) as distinct_products_sold,
        coalesce(avg((oli.price - pv.cost) / NULLIF(oli.price, 0)) * 100, 0) as average_margin,
        0.0 as sell_through_rate, -- Placeholder
        0.0 as on_time_delivery_rate, -- Placeholder
        s.default_lead_time_days as average_lead_time_days, -- Placeholder
        0 as total_completed_orders -- Placeholder
    from suppliers s
    join product_variants pv on s.id = pv.supplier_id
    join order_line_items oli on pv.id = oli.variant_id
    where s.company_id = p_company_id and pv.cost is not null and oli.price > 0
    group by s.id;
end;
$$;

create or replace function get_inventory_turnover(p_company_id uuid, p_days int)
returns json
language plpgsql
as $$
declare
    v_cogs numeric;
    v_avg_inventory_value numeric;
begin
    select coalesce(sum(oli.cost_at_time * oli.quantity), 0) into v_cogs
    from order_line_items oli
    join orders o on oli.order_id = o.id
    where o.company_id = p_company_id and o.created_at >= now() - (p_days || ' days')::interval;

    select coalesce(avg(daily_value), 0) into v_avg_inventory_value from (
        select date_trunc('day', created_at) as day, sum(new_quantity * cost) as daily_value
        from inventory_ledger il
        join product_variants pv on il.variant_id = pv.id
        where il.company_id = p_company_id
        group by day
    ) as daily_values;

    return json_build_object(
        'turnover_rate', case when v_avg_inventory_value > 0 then v_cogs / v_avg_inventory_value else 0 end,
        'total_cogs', v_cogs,
        'average_inventory_value', v_avg_inventory_value,
        'period_days', p_days
    );
end;
$$;


create or replace function create_purchase_orders_from_suggestions(
    p_company_id uuid,
    p_user_id uuid,
    p_suggestions jsonb,
    p_idempotency_key uuid default null
)
returns integer
language plpgsql
as $$
declare
    suggestion jsonb;
    v_supplier_id uuid;
    v_po_id uuid;
    v_total_cost numeric;
    v_po_count int := 0;
    grouped_suggestions jsonb;
begin
    -- Check for idempotency
    if p_idempotency_key is not null and exists (select 1 from purchase_orders where idempotency_key = p_idempotency_key) then
        return 0; -- Request already processed
    end if;

    -- Group suggestions by supplier_id
    select jsonb_object_agg(s.supplier_id, s.items) into grouped_suggestions
    from (
        select
            (item->>'supplier_id')::uuid as supplier_id,
            jsonb_agg(item) as items
        from jsonb_array_elements(p_suggestions) as item
        group by item->>'supplier_id'
    ) as s;

    -- Loop through each supplier group
    for v_supplier_id, suggestion in select * from jsonb_each(grouped_suggestions)
    loop
        v_total_cost := 0;
        
        -- Create a new Purchase Order for the supplier
        insert into purchase_orders (company_id, supplier_id, po_number, total_cost, status)
        values (p_company_id, v_supplier_id, 'PO-' || nextval('po_number_seq'), 0, 'Draft')
        returning id into v_po_id;

        v_po_count := v_po_count + 1;

        -- Loop through suggestions for this supplier to create line items and calculate total cost
        for suggestion in select * from jsonb_array_elements(suggestion)
        loop
            insert into purchase_order_line_items (purchase_order_id, company_id, variant_id, quantity, cost)
            values (
                v_po_id,
                p_company_id,
                (suggestion->>'variant_id')::uuid,
                (suggestion->>'suggested_reorder_quantity')::integer,
                (suggestion->>'unit_cost')::integer
            );
            v_total_cost := v_total_cost + ((suggestion->>'suggested_reorder_quantity')::integer * (suggestion->>'unit_cost')::integer);
        end loop;

        -- Update the total cost of the PO
        update purchase_orders set total_cost = v_total_cost where id = v_po_id;
    end loop;
    
    return v_po_count;
end;
$$;


create or replace function get_historical_sales_for_sku(p_company_id uuid, p_sku text)
returns table (sale_date timestamptz, total_quantity bigint)
language plpgsql
as $$
begin
    return query
    select
        date_trunc('day', o.created_at) as sale_date,
        sum(oli.quantity) as total_quantity
    from order_line_items oli
    join orders o on oli.order_id = o.id
    where oli.company_id = p_company_id and oli.sku = p_sku
    group by sale_date
    order by sale_date;
end;
$$;

create or replace function get_historical_sales_for_skus(p_company_id uuid, p_skus text[])
returns json
language plpgsql
as $$
begin
    return (
        select json_agg(
            json_build_object(
                'sku', sku_data.sku,
                'monthly_sales', sku_data.monthly_sales
            )
        )
        from (
            select
                oli.sku,
                json_agg(
                    json_build_object(
                        'month', to_char(date_trunc('month', o.created_at), 'YYYY-MM'),
                        'total_quantity', sum(oli.quantity)
                    ) order by date_trunc('month', o.created_at)
                ) as monthly_sales
            from order_line_items oli
            join orders o on oli.order_id = o.id
            where oli.company_id = p_company_id and oli.sku = any(p_skus)
            group by oli.sku
        ) as sku_data
    );
end;
$$;


create or replace function reconcile_inventory_from_integration(
    p_company_id uuid,
    p_integration_id uuid,
    p_user_id uuid
)
returns void
language plpgsql
as $$
declare
    rec record;
    v_external_quantity int;
    v_current_quantity int;
    v_quantity_change int;
begin
    -- This function would need to call the external API to get quantities.
    -- For this example, we'll simulate it with a placeholder.
    -- In a real implementation, you would replace the simulated value
    -- with an API call result inside the loop.

    for rec in (select id, inventory_quantity from product_variants where company_id = p_company_id)
    loop
        -- SIMULATED API CALL
        v_external_quantity := rec.inventory_quantity + floor(random() * 10 - 5);
        v_current_quantity := rec.inventory_quantity;
        v_quantity_change := v_external_quantity - v_current_quantity;

        if v_quantity_change != 0 then
            update product_variants
            set inventory_quantity = v_external_quantity
            where id = rec.id;

            insert into inventory_ledger(company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
            values (p_company_id, rec.id, 'reconciliation', v_quantity_change, v_external_quantity, p_integration_id, 'Reconciled from integration by user ' || p_user_id);
        end if;
    end loop;
end;
$$;


create or replace function get_net_margin_by_channel(
    p_company_id uuid,
    p_channel_name text
)
returns table (net_margin numeric)
language plpgsql
as $$
begin
    -- Placeholder function. A real implementation would be more complex.
    return query
    select 0.15 as net_margin;
end;
$$;

create or replace function get_sales_velocity(
    p_company_id uuid,
    p_days int,
    p_limit int
)
returns table (
    fast_sellers json,
    slow_sellers json
)
language plpgsql
as $$
begin
    -- Placeholder function
    fast_sellers := '[]'::json;
    slow_sellers := '[]'::json;
    return;
end;
$$;

create or replace function get_abc_analysis(p_company_id uuid)
returns json
language plpgsql
as $$
begin
    return '[]'::json;
end;
$$;


create or replace function get_gross_margin_analysis(p_company_id uuid)
returns jsonb
as $$
begin
  return '{}'::jsonb;
end;
$$ language plpgsql;

create or replace function get_margin_trends(p_company_id uuid)
returns json
as $$
begin
    return '[]'::json;
end;
$$;

create or replace function get_financial_impact_of_promotion(
    p_company_id uuid,
    p_skus text[],
    p_discount_percentage numeric,
    p_duration_days int
)
returns json
as $$
begin
    return '{}'::json;
end;
$$;

-- Sequences for auto-incrementing numbers
create sequence if not exists po_number_seq;
create sequence if not exists refund_number_seq;

