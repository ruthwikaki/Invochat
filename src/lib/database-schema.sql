-- Migration: Add product_id foreign key to sale_items table
-- This migration updates the sale_items table to reference inventory by ID instead of SKU

-- Step 1: Add the product_id column to sale_items table
ALTER TABLE public.sale_items 
ADD COLUMN product_id uuid;

-- Step 2: Populate product_id based on existing SKU values
-- This matches sale_items to inventory using SKU and company_id
UPDATE public.sale_items si
SET product_id = i.id
FROM public.inventory i
WHERE si.sku = i.sku 
  AND si.company_id = i.company_id
  AND i.deleted_at IS NULL;

-- Step 3: Check for any sale_items that couldn't be matched
-- This helps identify orphaned records before enforcing the constraint
DO $$
DECLARE
    unmatched_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO unmatched_count
    FROM public.sale_items
    WHERE product_id IS NULL;
    
    IF unmatched_count > 0 THEN
        RAISE NOTICE 'Warning: % sale_items records could not be matched to inventory', unmatched_count;
        RAISE NOTICE 'These records will need to be handled before making product_id NOT NULL';
    END IF;
END $$;

-- Step 4: Add foreign key constraint (without NOT NULL for now)
ALTER TABLE public.sale_items
ADD CONSTRAINT sale_items_product_id_fkey 
FOREIGN KEY (product_id) 
REFERENCES public.inventory(id)
ON DELETE RESTRICT;

-- Step 5: Create index for better query performance
CREATE INDEX idx_sale_items_product_id ON public.sale_items(product_id);

-- Step 6: Drop the old function before creating the new one
-- This is necessary if the function signature or return type changes.
DROP FUNCTION IF EXISTS record_sale_transaction(uuid,uuid,jsonb,text,text,text,text,text);

-- Step 7: Update the record_sale_transaction function
CREATE OR REPLACE FUNCTION record_sale_transaction(
    p_company_id uuid,
    p_user_id uuid, -- Added for consistency
    p_sale_items jsonb,
    p_customer_name text DEFAULT NULL,
    p_customer_email text DEFAULT NULL,
    p_payment_method text DEFAULT 'other',
    p_notes text DEFAULT NULL,
    p_external_id text DEFAULT NULL
)
RETURNS uuid AS $$
DECLARE
    v_sale_id uuid;
    v_item jsonb;
    v_product_id uuid;
    v_sku text;
    v_product_name text;
    v_quantity integer;
    v_unit_price numeric;
    v_total_amount numeric := 0;
    v_new_sale_number text;
BEGIN
    -- Calculate total amount from items
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_sale_items)
    LOOP
        v_total_amount := v_total_amount + ((v_item->>'quantity')::integer * (v_item->>'unit_price')::numeric);
    END LOOP;

    -- Generate a new sale number
    SELECT 'SALE-' || TO_CHAR(CURRENT_DATE, 'YYMMDD') || '-' || LPAD((COUNT(*) + 1)::text, 4, '0')
    INTO v_new_sale_number
    FROM sales
    WHERE company_id = p_company_id AND created_at >= CURRENT_DATE;

    -- Insert the sale record
    INSERT INTO public.sales (
        company_id, 
        sale_number, 
        customer_name, 
        customer_email, 
        total_amount, 
        payment_method, 
        notes, 
        external_id
    ) VALUES (
        p_company_id,
        v_new_sale_number,
        p_customer_name,
        p_customer_email,
        v_total_amount,
        p_payment_method,
        p_notes,
        p_external_id
    ) RETURNING id INTO v_sale_id;

    -- Process each item in the sale
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_sale_items)
    LOOP
        v_product_id := (v_item->>'product_id')::uuid;
        v_quantity := (v_item->>'quantity')::integer;
        v_unit_price := (v_item->>'unit_price')::numeric;
        v_product_name := v_item->>'product_name';

        -- Get current SKU from inventory table
        SELECT sku INTO v_sku
        FROM public.inventory
        WHERE id = v_product_id;
        
        IF v_sku IS NULL THEN
            RAISE EXCEPTION 'Product with ID % not found in inventory', v_product_id;
        END IF;
        
        -- Insert sale item with product_id
        INSERT INTO public.sale_items (
            sale_id,
            product_id,
            sku,
            product_name,
            quantity,
            unit_price,
            cost_at_time,
            company_id
        ) VALUES (
            v_sale_id,
            v_product_id,
            v_sku, -- Store SKU for historical reference
            v_product_name,
            v_quantity,
            v_unit_price,
            (SELECT cost FROM public.inventory WHERE id = v_product_id),
            p_company_id
        );
        
        -- Update inventory quantity
        UPDATE public.inventory
        SET quantity = quantity - v_quantity,
            last_sold_date = CURRENT_DATE,
            updated_at = NOW()
        WHERE id = v_product_id;
        
        -- Record in inventory ledger
        INSERT INTO public.inventory_ledger (
            company_id,
            product_id,
            change_type,
            quantity_change,
            new_quantity,
            related_id,
            notes
        ) VALUES (
            p_company_id,
            v_product_id,
            'sale',
            -v_quantity,
            (SELECT quantity FROM public.inventory WHERE id = v_product_id),
            v_sale_id,
            'Sale #' || v_new_sale_number
        );
    END LOOP;
    
    RETURN v_sale_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Optional Step 8: After verifying all data is correct, make product_id NOT NULL
-- Only run this after handling any NULL product_id values identified in Step 3
-- ALTER TABLE public.sale_items ALTER COLUMN product_id SET NOT NULL;


-- Full initial schema for reference (should not be run on existing DB)
/*

CREATE TYPE user_role AS ENUM ('Owner', 'Admin', 'Member');

CREATE TABLE companies (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE users (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id uuid NOT NULL REFERENCES companies(id),
    email text,
    role user_role NOT NULL DEFAULT 'Member',
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now()
);

-- Function to create a public user profile from the auth user
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_company_id uuid;
begin
  -- Check if a company with the specified name already exists
  select id into v_company_id from companies where name = new.raw_app_meta_data->>'company_name';

  -- If company doesn't exist, create it
  if v_company_id is null then
    insert into public.companies (name)
    values (new.raw_app_meta_data->>'company_name')
    returning id into v_company_id;
  end if;

  insert into public.users (id, email, company_id, role)
  values (
    new.id,
    new.email,
    v_company_id,
    (new.raw_app_meta_data->>'role')::user_role
  );

  update auth.users
  set raw_app_meta_data = raw_app_meta_data || jsonb_build_object('company_id', v_company_id)
  where id = new.id;

  return new;
end;
$$;

-- Trigger to call the function on new user signup
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


CREATE TABLE company_settings (
    company_id uuid PRIMARY KEY REFERENCES companies(id),
    dead_stock_days integer NOT NULL DEFAULT 90,
    fast_moving_days integer NOT NULL DEFAULT 30,
    predictive_stock_days integer NOT NULL DEFAULT 7,
    overstock_multiplier numeric NOT NULL DEFAULT 3,
    high_value_threshold numeric NOT NULL DEFAULT 1000,
    currency text DEFAULT 'USD',
    timezone text DEFAULT 'UTC',
    tax_rate numeric DEFAULT 0,
    custom_rules jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    subscription_status text DEFAULT 'trial',
    subscription_plan text DEFAULT 'starter',
    subscription_expires_at timestamptz,
    stripe_customer_id text,
    stripe_subscription_id text,
    promo_sales_lift_multiplier real not null default 2.5
);

CREATE TABLE suppliers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES companies(id),
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE inventory (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES companies(id),
    sku text NOT NULL,
    name text NOT NULL,
    category text,
    quantity integer NOT NULL DEFAULT 0,
    cost numeric NOT NULL DEFAULT 0,
    price numeric,
    reorder_point integer,
    last_sold_date date,
    supplier_id uuid REFERENCES suppliers(id),
    barcode text,
    version integer NOT NULL DEFAULT 1,
    deleted_at timestamptz,
    deleted_by uuid REFERENCES users(id),
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    source_platform text,
    external_product_id text,
    external_variant_id text,
    external_quantity integer,
    UNIQUE(company_id, sku)
);


CREATE TABLE customers (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES companies(id),
    customer_name text NOT NULL,
    email text,
    total_orders integer DEFAULT 0,
    total_spent numeric DEFAULT 0,
    first_order_date date,
    deleted_at timestamptz,
    created_at timestamptz DEFAULT now(),
    UNIQUE(company_id, email)
);

CREATE TABLE sales (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES companies(id),
    sale_number text NOT NULL,
    customer_name text,
    customer_email text,
    total_amount numeric NOT NULL,
    payment_method text,
    notes text,
    created_at timestamptz DEFAULT now(),
    external_id text,
    UNIQUE(company_id, sale_number),
    UNIQUE(company_id, external_id)
);

CREATE TABLE sale_items (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    sale_id uuid NOT NULL REFERENCES sales(id),
    product_id uuid REFERENCES inventory(id), -- This is the new column
    sku text NOT NULL, -- Keep for historical reasons or redundancy
    product_name text,
    quantity integer NOT NULL,
    unit_price numeric NOT NULL,
    cost_at_time numeric,
    company_id uuid NOT NULL REFERENCES companies(id)
);

CREATE TABLE conversations (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id uuid NOT NULL REFERENCES auth.users(id),
    company_id uuid NOT NULL REFERENCES companies(id),
    title text NOT NULL,
    created_at timestamptz DEFAULT now(),
    last_accessed_at timestamptz DEFAULT now(),
    is_starred boolean DEFAULT false
);

CREATE TABLE messages (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id uuid NOT NULL REFERENCES conversations(id),
    company_id uuid NOT NULL REFERENCES companies(id),
    role text NOT NULL,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    is_error boolean default false,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE inventory_ledger (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id uuid NOT NULL REFERENCES companies(id),
    product_id uuid NOT NULL REFERENCES inventory(id),
    change_type text NOT NULL,
    quantity_change integer NOT NULL,
    new_quantity integer NOT NULL,
    related_id uuid, -- e.g., sale_id
    notes text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE audit_log (
    id bigserial PRIMARY KEY,
    company_id uuid REFERENCES companies(id),
    user_id uuid REFERENCES auth.users(id),
    action text NOT NULL,
    details jsonb,
    created_at timestamptz DEFAULT now()
);

CREATE TABLE integrations (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  platform text NOT NULL,
  shop_domain text,
  shop_name text,
  is_active boolean DEFAULT false,
  last_sync_at timestamptz,
  sync_status text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz
);

CREATE TABLE sync_state (
    integration_id UUID NOT NULL REFERENCES integrations(id) ON DELETE CASCADE,
    sync_type TEXT NOT NULL,
    last_processed_cursor TEXT,
    last_update TIMESTAMPTZ,
    PRIMARY KEY (integration_id, sync_type)
);

CREATE TABLE sync_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    integration_id UUID NOT NULL REFERENCES integrations(id) ON DELETE CASCADE,
    sync_type TEXT,
    status TEXT,
    records_synced INT,
    error_message TEXT,
    started_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

CREATE TABLE channel_fees (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES companies(id),
    channel_name text NOT NULL,
    percentage_fee numeric NOT NULL,
    fixed_fee numeric NOT NULL, -- In cents
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz,
    UNIQUE(company_id, channel_name)
);

CREATE TABLE export_jobs (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    requested_by_user_id uuid NOT NULL REFERENCES auth.users(id),
    status text NOT NULL DEFAULT 'pending', -- pending, processing, completed, failed
    download_url text,
    expires_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
);

*/
