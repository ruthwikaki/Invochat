--
-- PostgreSQL database dump
--

-- Dumped from database version 16.2
-- Dumped by pg_dump version 16.2

-- Started on 2024-07-13 17:34:04 UTC

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 6 (class 2615 OID 16386)
-- Name: heroku_ext; Type: SCHEMA; Schema: -; Owner: postgres
--

-- CREATE SCHEMA heroku_ext;


-- ALTER SCHEMA heroku_ext OWNER TO postgres;

--
-- TOC entry 525 (class 1247 OID 16671)
-- Name: user_role; Type: TYPE; Schema: public; Owner: supabase_admin
--

CREATE TYPE public.user_role AS ENUM (
    'Owner',
    'Admin',
    'Member'
);


-- ALTER TYPE public.user_role OWNER TO supabase_admin;

--
-- TOC entry 988 (class 1255 OID 16677)
-- Name: get_current_company_id(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.get_current_company_id() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'company_id', '')::uuid;
$$;


-- ALTER FUNCTION public.get_current_company_id() OWNER TO supabase_admin;

--
-- TOC entry 991 (class 1255 OID 16678)
-- Name: get_current_user_role(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.get_current_user_role() RETURNS public.user_role
    LANGUAGE sql STABLE
    AS $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'role', '')::user_role;
$$;


-- ALTER FUNCTION public.get_current_user_role() OWNER TO supabase_admin;

--
-- TOC entry 1007 (class 1255 OID 16679)
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  new_company_id uuid;
  user_email text;
begin
  -- First, check if the user is being invited to an existing company
  if new.raw_app_meta_data ->> 'company_id' is not null then
    insert into public.users (id, company_id, email, role)
    values (
      new.id,
      (new.raw_app_meta_data ->> 'company_id')::uuid,
      new.email,
      'Member' -- Invited users default to Member role
    );
  -- Otherwise, create a new company for the new user
  else
    user_email := new.email;
    insert into public.companies (name)
    values (coalesce(new.raw_user_meta_data ->> 'company_name', user_email))
    returning id into new_company_id;

    insert into public.users (id, company_id, email, role)
    values (
      new.id,
      new_company_id,
      new.email,
      'Owner' -- The user who creates the company is the Owner
    );

    update auth.users
    set raw_app_meta_data = jsonb_set(
      coalesce(raw_app_meta_data, '{}'::jsonb),
      '{company_id}',
      to_jsonb(new_company_id)
    )
    where id = new.id;
  end if;

  return new;
end;
$$;


-- ALTER FUNCTION public.handle_new_user() OWNER TO supabase_admin;

DROP FUNCTION IF EXISTS public.record_order_from_platform(uuid, text, jsonb);
--
-- TOC entry 1008 (class 1255 OID 16680)
-- Name: record_order_from_platform(uuid, text, jsonb); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.record_order_from_platform(p_company_id uuid, p_platform text, p_order_payload jsonb) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
declare
  v_customer_id uuid;
  v_order_id uuid;
  v_customer_name text;
  v_customer_email text;
  line_item jsonb;
  v_variant_id uuid;
  v_cost_at_time integer;
begin
  -- Step 1: Extract customer information
  if p_platform = 'shopify' then
    v_customer_name := p_order_payload -> 'customer' ->> 'first_name' || ' ' || p_order_payload -> 'customer' ->> 'last_name';
    v_customer_email := p_order_payload -> 'customer' ->> 'email';
  elsif p_platform = 'woocommerce' then
    v_customer_name := p_order_payload -> 'billing' ->> 'first_name' || ' ' || p_order_payload -> 'billing' ->> 'last_name';
    v_customer_email := p_order_payload -> 'billing' ->> 'email';
  else
    v_customer_name := 'Unknown';
    v_customer_email := null;
  end if;
  
  -- Step 2: Find or Create Customer
  if v_customer_email is not null then
    select id into v_customer_id from public.customers where email = v_customer_email and company_id = p_company_id;
    if not found then
      insert into public.customers (company_id, customer_name, email, first_order_date)
      values (p_company_id, v_customer_name, v_customer_email, (p_order_payload ->> 'created_at')::date)
      returning id into v_customer_id;
    end if;
  end if;
  
  -- Step 3: Insert or Update Order
  insert into public.orders (
    company_id, order_number, external_order_id, customer_id, financial_status, fulfillment_status,
    currency, subtotal, total_tax, total_shipping, total_discounts, total_amount, source_platform, created_at
  )
  values (
    p_company_id,
    p_order_payload ->> 'id', -- Using external ID as order number for simplicity
    p_order_payload ->> 'id',
    v_customer_id,
    coalesce(p_order_payload ->> 'financial_status', 'paid'),
    coalesce(p_order_payload ->> 'fulfillment_status', 'unfulfilled'),
    p_order_payload ->> 'currency',
    (coalesce(p_order_payload ->> 'subtotal_price', '0')::numeric * 100)::integer,
    (coalesce(p_order_payload ->> 'total_tax', '0')::numeric * 100)::integer,
    (coalesce(p_order_payload -> 'shipping_lines' -> 0 ->> 'price', '0')::numeric * 100)::integer,
    (coalesce(p_order_payload ->> 'total_discounts', '0')::numeric * 100)::integer,
    (coalesce(p_order_payload ->> 'total_price', '0')::numeric * 100)::integer,
    p_platform,
    (p_order_payload ->> 'created_at')::timestamptz
  )
  on conflict (company_id, external_order_id)
  do update set
    financial_status = excluded.financial_status,
    fulfillment_status = excluded.fulfillment_status,
    updated_at = now()
  returning id into v_order_id;
  
  -- Step 4: Process Line Items
  for line_item in select * from jsonb_array_elements(p_order_payload -> 'line_items')
  loop
    -- Find variant by external ID or SKU
    select id into v_variant_id from public.product_variants
    where external_variant_id = line_item ->> 'variant_id' and company_id = p_company_id;
    
    if v_variant_id is null then
      select id into v_variant_id from public.product_variants
      where sku = line_item ->> 'sku' and company_id = p_company_id;
    end if;
    
    -- Get current cost of the variant
    select cost into v_cost_at_time from public.product_variants where id = v_variant_id;
    
    -- Insert line item
    insert into public.order_line_items (
      order_id, company_id, variant_id, product_name, sku, quantity, price,
      cost_at_time, external_line_item_id
    )
    values (
      v_order_id,
      p_company_id,
      v_variant_id,
      line_item ->> 'title',
      line_item ->> 'sku',
      (line_item ->> 'quantity')::integer,
      (coalesce(line_item ->> 'price', '0')::numeric * 100)::integer,
      v_cost_at_time,
      line_item ->> 'id'
    )
    on conflict (order_id, external_line_item_id)
    do nothing; -- Or UPDATE if necessary
  end loop;

  return v_order_id;
end;
$$;


-- ALTER FUNCTION public.record_order_from_platform(p_company_id uuid, p_platform text, p_order_payload jsonb) OWNER TO supabase_admin;

--
-- TOC entry 1009 (class 1255 OID 16681)
-- Name: update_inventory_from_sale(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.update_inventory_from_sale() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  v_new_quantity int;
begin
  update public.product_variants
  set inventory_quantity = inventory_quantity - new.quantity
  where id = new.variant_id
  returning inventory_quantity into v_new_quantity;
  
  insert into public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id)
  values (new.company_id, new.variant_id, 'sale', -new.quantity, v_new_quantity, new.order_id);
  
  return new;
end;
$$;


-- ALTER FUNCTION public.update_inventory_from_sale() OWNER TO supabase_admin;

--
-- TOC entry 1010 (class 1255 OID 16682)
-- Name: update_inventory_on_restock(); Type: FUNCTION; Schema: public; Owner: supabase_admin
--

CREATE FUNCTION public.update_inventory_on_restock() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  v_new_quantity int;
  v_variant_id uuid;
begin
  select oli.variant_id into v_variant_id
  from public.order_line_items oli
  where oli.id = new.order_line_item_id;

  if v_variant_id is not null then
    update public.product_variants
    set inventory_quantity = inventory_quantity + new.quantity
    where id = v_variant_id
    returning inventory_quantity into v_new_quantity;
    
    insert into public.inventory_ledger (company_id, variant_id, change_type, quantity_change, new_quantity, related_id, notes)
    values (new.company_id, v_variant_id, 'return', new.quantity, v_new_quantity, new.refund_id, 'Refund restock');
  end if;
  
  return new;
end;
$$;


-- ALTER FUNCTION public.update_inventory_on_restock() OWNER TO supabase_admin;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 268 (class 1259 OID 16683)
-- Name: companies; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.companies (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


-- ALTER TABLE public.companies OWNER TO supabase_admin;

--
-- TOC entry 269 (class 1259 OID 16690)
-- Name: company_settings; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.company_settings (
    company_id uuid NOT NULL,
    dead_stock_days integer DEFAULT 90 NOT NULL,
    overstock_multiplier integer DEFAULT 3 NOT NULL,
    high_value_threshold integer DEFAULT 1000 NOT NULL,
    fast_moving_days integer DEFAULT 30 NOT NULL,
    predictive_stock_days integer DEFAULT 7 NOT NULL,
    currency text DEFAULT 'USD'::text,
    timezone text DEFAULT 'UTC'::text,
    tax_rate numeric DEFAULT 0,
    custom_rules jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone,
    subscription_status text DEFAULT 'trial'::text,
    subscription_plan text DEFAULT 'starter'::text,
    subscription_expires_at timestamp with time zone,
    stripe_customer_id text,
    stripe_subscription_id text,
    promo_sales_lift_multiplier real DEFAULT 2.5 NOT NULL
);


-- ALTER TABLE public.company_settings OWNER TO supabase_admin;

--
-- TOC entry 270 (class 1259 OID 16705)
-- Name: users; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.users (
    id uuid NOT NULL,
    company_id uuid NOT NULL,
    email text,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    role public.user_role DEFAULT 'Member'::public.user_role NOT NULL
);


-- ALTER TABLE public.users OWNER TO supabase_admin;

--
-- TOC entry 271 (class 1259 OID 16712)
-- Name: audit_log; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.audit_log AS
 SELECT u.email,
    c.name AS company_name,
    a.action,
    a.details,
    a.created_at
   FROM ((public.audit_log a
     LEFT JOIN public.users u ON ((a.user_id = u.id)))
     LEFT JOIN public.companies c ON ((a.company_id = c.id)));


-- ALTER VIEW public.audit_log OWNER TO supabase_admin;

--
-- TOC entry 272 (class 1259 OID 16717)
-- Name: conversations; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.conversations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    company_id uuid NOT NULL,
    title text NOT NULL,
    created_at timestamp with time zone DEFAULT now(),
    last_accessed_at timestamp with time zone DEFAULT now(),
    is_starred boolean DEFAULT false
);


-- ALTER TABLE public.conversations OWNER TO supabase_admin;

--
-- TOC entry 273 (class 1259 OID 16726)
-- Name: customers; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.customers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    customer_name text,
    email text,
    total_orders integer DEFAULT 0,
    total_spent numeric DEFAULT 0,
    first_order_date date,
    deleted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);


-- ALTER TABLE public.customers OWNER TO supabase_admin;

--
-- TOC entry 274 (class 1259 OID 16735)
-- Name: integrations; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.integrations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    platform text NOT NULL,
    shop_domain text,
    shop_name text,
    is_active boolean DEFAULT false,
    last_sync_at timestamp with time zone,
    sync_status text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);


-- ALTER TABLE public.integrations OWNER TO supabase_admin;

--
-- TOC entry 275 (class 1259 OID 16743)
-- Name: messages; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    conversation_id uuid NOT NULL,
    company_id uuid NOT NULL,
    role text NOT NULL,
    content text,
    component text,
    component_props jsonb,
    visualization jsonb,
    confidence numeric,
    assumptions text[],
    created_at timestamp with time zone DEFAULT now(),
    is_error boolean DEFAULT false
);


-- ALTER TABLE public.messages OWNER TO supabase_admin;

--
-- TOC entry 276 (class 1259 OID 16752)
-- Name: orders; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.orders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    order_number text NOT NULL,
    external_order_id text,
    customer_id uuid,
    financial_status text DEFAULT 'pending'::text,
    fulfillment_status text DEFAULT 'unfulfilled'::text,
    currency text DEFAULT 'USD'::text,
    subtotal integer DEFAULT 0 NOT NULL,
    total_tax integer DEFAULT 0,
    total_shipping integer DEFAULT 0,
    total_discounts integer DEFAULT 0,
    total_amount integer NOT NULL,
    source_platform text,
    source_name text,
    tags text[],
    notes text,
    cancelled_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


-- ALTER TABLE public.orders OWNER TO supabase_admin;

--
-- TOC entry 277 (class 1259 OID 16769)
-- Name: order_line_items; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.order_line_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    variant_id uuid,
    company_id uuid NOT NULL,
    product_name text,
    variant_title text,
    sku text,
    quantity integer NOT NULL,
    price integer NOT NULL,
    total_discount integer DEFAULT 0,
    tax_amount integer DEFAULT 0,
    cost_at_time integer,
    external_line_item_id text,
    product_id uuid
);


-- ALTER TABLE public.order_line_items OWNER TO supabase_admin;

--
-- TOC entry 278 (class 1259 OID 16777)
-- Name: product_variants; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.product_variants (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    product_id uuid NOT NULL,
    company_id uuid NOT NULL,
    sku text,
    title text,
    option1_name text,
    option1_value text,
    option2_name text,
    option2_value text,
    option3_name text,
    option3_value text,
    barcode text,
    price integer,
    compare_at_price integer,
    cost integer,
    inventory_quantity integer DEFAULT 0,
    external_variant_id text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    weight numeric,
    weight_unit text
);


-- ALTER TABLE public.product_variants OWNER TO supabase_admin;

--
-- TOC entry 279 (class 1259 OID 16787)
-- Name: company_dashboard_metrics; Type: VIEW; Schema: public; Owner: supabase_admin
--

CREATE VIEW public.company_dashboard_metrics AS
 SELECT c.id AS company_id,
    c.name AS company_name,
    COALESCE(s.total_sales_value, (0)::numeric) AS total_sales_value,
    COALESCE(s.total_profit, (0)::numeric) AS total_profit,
    COALESCE(s.total_orders, (0)::bigint) AS total_orders,
    COALESCE(s.average_order_value, (0)::numeric) AS average_order_value,
    COALESCE(i.total_inventory_value, (0)::bigint) AS total_inventory_value,
    COALESCE(i.total_skus, (0)::bigint) AS total_skus,
    COALESCE(i.low_stock_items_count, (0)::bigint) AS low_stock_items_count,
    COALESCE(i.dead_stock_items_count, (0)::bigint) AS dead_stock_items_count
   FROM ((public.companies c
     LEFT JOIN ( SELECT o.company_id,
            sum(o.total_amount) AS total_sales_value,
            sum((oli.price - oli.cost_at_time)) AS total_profit,
            count(DISTINCT o.id) AS total_orders,
            avg(o.total_amount) AS average_order_value
           FROM (public.orders o
             JOIN public.order_line_items oli ON ((o.id = oli.order_id)))
          WHERE (o.created_at >= (now() - '30 days'::interval))
          GROUP BY o.company_id) s ON ((c.id = s.company_id)))
     LEFT JOIN ( SELECT pv.company_id,
            sum((pv.cost * pv.inventory_quantity)) AS total_inventory_value,
            count(pv.id) AS total_skus,
            count(NULLIF(false, (pv.inventory_quantity <= 0))) AS low_stock_items_count,
            count(NULLIF(false, (pv.updated_at < (now() - '90 days'::interval)))) AS dead_stock_items_count
           FROM public.product_variants pv
          GROUP BY pv.company_id) i ON ((c.id = i.company_id)));


-- ALTER VIEW public.company_dashboard_metrics OWNER TO supabase_admin;

--
-- TOC entry 280 (class 1259 OID 16792)
-- Name: inventory_lots; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.inventory_lots (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    variant_id uuid NOT NULL,
    lot_number text,
    quantity integer NOT NULL,
    received_date date DEFAULT now() NOT NULL,
    expiration_date date
);


-- ALTER TABLE public.inventory_lots OWNER TO supabase_admin;

--
-- TOC entry 281 (class 1259 OID 16800)
-- Name: suppliers; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.suppliers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    company_id uuid NOT NULL,
    name text NOT NULL,
    email text,
    phone text,
    default_lead_time_days integer,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


-- ALTER TABLE public.suppliers OWNER TO supabase_admin;

--
-- TOC entry 282 (class 1259 OID 16807)
-- Name: webhook_events; Type: TABLE; Schema: public; Owner: supabase_admin
--

CREATE TABLE public.webhook_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    integration_id uuid NOT NULL,
    webhook_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


-- ALTER TABLE public.webhook_events OWNER TO supabase_admin;

--
-- TOC entry 5064 (class 2606 OID 16814)
-- Name: companies companies_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_pkey PRIMARY KEY (id);


--
-- TOC entry 5066 (class 2606 OID 16816)
-- Name: company_settings company_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.company_settings
    ADD CONSTRAINT company_settings_pkey PRIMARY KEY (company_id);


--
-- TOC entry 5104 (class 2606 OID 16818)
-- Name: customer_addresses customer_addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.customer_addresses
    ADD CONSTRAINT customer_addresses_pkey PRIMARY KEY (id);


--
-- TOC entry 5074 (class 2606 OID 16820)
-- Name: conversations conversations_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_pkey PRIMARY KEY (id);


--
-- TOC entry 5078 (class 2606 OID 16822)
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- TOC entry 5106 (class 2606 OID 16824)
-- Name: discounts discounts_code_key; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.discounts
    ADD CONSTRAINT discounts_code_key UNIQUE (code);


--
-- TOC entry 5108 (class 2606 OID 16826)
-- Name: discounts discounts_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.discounts
    ADD CONSTRAINT discounts_pkey PRIMARY KEY (id);


--
-- TOC entry 5110 (class 2606 OID 16828)
-- Name: export_jobs export_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.export_jobs
    ADD CONSTRAINT export_jobs_pkey PRIMARY KEY (id);


--
-- TOC entry 5112 (class 2606 OID 16830)
-- Name: channel_fees fee_manager_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.channel_fees
    ADD CONSTRAINT fee_manager_pkey PRIMARY KEY (id);


--
-- TOC entry 5082 (class 2606 OID 16832)
-- Name: integrations integrations_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.integrations
    ADD CONSTRAINT integrations_pkey PRIMARY KEY (id);


--
-- TOC entry 5102 (class 2606 OID 16834)
-- Name: inventory_ledger inventory_ledger_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.inventory_ledger
    ADD CONSTRAINT inventory_ledger_pkey PRIMARY KEY (id);


--
-- TOC entry 5116 (class 2606 OID 16836)
-- Name: inventory_lots inventory_lots_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.inventory_lots
    ADD CONSTRAINT inventory_lots_pkey PRIMARY KEY (id);


--
-- TOC entry 5088 (class 2606 OID 16838)
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id);


--
-- TOC entry 5096 (class 2606 OID 16840)
-- Name: order_line_items order_line_items_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.order_line_items
    ADD CONSTRAINT order_line_items_pkey PRIMARY KEY (id);


--
-- TOC entry 5092 (class 2606 OID 16842)
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- TOC entry 5098 (class 2606 OID 16844)
-- Name: product_variants product_variants_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.product_variants
    ADD CONSTRAINT product_variants_pkey PRIMARY KEY (id);


--
-- TOC entry 5094 (class 2606 OID 16846)
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- TOC entry 5100 (class 2606 OID 16848)
-- Name: product_variants unique_sku_per_company; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.product_variants
    ADD CONSTRAINT unique_sku_per_company UNIQUE (company_id, sku);


--
-- TOC entry 5118 (class 2606 OID 16850)
-- Name: suppliers suppliers_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_pkey PRIMARY KEY (id);


--
-- TOC entry 5070 (class 2606 OID 16852)
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- TOC entry 5120 (class 2606 OID 16854)
-- Name: webhook_events webhook_events_pkey; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.webhook_events
    ADD CONSTRAINT webhook_events_pkey PRIMARY KEY (id);


--
-- TOC entry 5122 (class 2606 OID 16856)
-- Name: webhook_events webhook_events_webhook_id_key; Type: CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.webhook_events
    ADD CONSTRAINT webhook_events_webhook_id_key UNIQUE (webhook_id);


--
-- TOC entry 5071 (class 1259 OID 16857)
-- Name: audit_log_company_id_idx; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX audit_log_company_id_idx ON public.audit_log USING btree (company_id);


--
-- TOC entry 5075 (class 1259 OID 16858)
-- Name: conversations_company_id_idx; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX conversations_company_id_idx ON public.conversations USING btree (company_id);


--
-- TOC entry 5076 (class 1259 OID 16859)
-- Name: conversations_user_id_idx; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX conversations_user_id_idx ON public.conversations USING btree (user_id);


--
-- TOC entry 5079 (class 1259 OID 16860)
-- Name: customers_company_id_idx; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX customers_company_id_idx ON public.customers USING btree (company_id);


--
-- TOC entry 5080 (class 1259 OID 16861)
-- Name: customers_email_idx; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX customers_email_idx ON public.customers USING btree (email);


--
-- TOC entry 5083 (class 1259 OID 16862)
-- Name: integrations_company_id_idx; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX integrations_company_id_idx ON public.integrations USING btree (company_id);


--
-- TOC entry 5084 (class 1259 OID 16863)
-- Name: integrations_platform_idx; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX integrations_platform_idx ON public.integrations USING btree (platform);


--
-- TOC entry 5089 (class 1259 OID 16864)
-- Name: messages_company_id_idx; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX messages_company_id_idx ON public.messages USING btree (company_id);


--
-- TOC entry 5090 (class 1259 OID 16865)
-- Name: messages_conversation_id_idx; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX messages_conversation_id_idx ON public.messages USING btree (conversation_id);


--
-- TOC entry 5072 (class 1259 OID 16866)
-- Name: users_company_id_idx; Type: INDEX; Schema: public; Owner: supabase_admin
--

CREATE INDEX users_company_id_idx ON public.users USING btree (company_id);


--
-- TOC entry 5123 (class 2620 OID 16867)
-- Name: users on_auth_user_created; Type: TRIGGER; Schema: auth; Owner: supabase_admin
--

CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


--
-- TOC entry 5124 (class 2620 OID 16868)
-- Name: order_line_items on_sale_insert; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER on_sale_insert AFTER INSERT ON public.order_line_items FOR EACH ROW EXECUTE FUNCTION public.update_inventory_from_sale();


--
-- TOC entry 5125 (class 2620 OID 16869)
-- Name: refund_line_items on_refund_restock; Type: TRIGGER; Schema: public; Owner: supabase_admin
--

CREATE TRIGGER on_refund_restock AFTER INSERT ON public.refund_line_items FOR EACH ROW WHEN ((new.restock = true)) EXECUTE FUNCTION public.update_inventory_on_restock();


--
-- TOC entry 5114 (class 2606 OID 16870)
-- Name: channel_fees channel_fees_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.channel_fees
    ADD CONSTRAINT channel_fees_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5067 (class 2606 OID 16875)
-- Name: company_settings company_settings_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.company_settings
    ADD CONSTRAINT company_settings_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5085 (class 2606 OID 16880)
-- Name: integrations integrations_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.integrations
    ADD CONSTRAINT integrations_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5111 (class 2606 OID 16885)
-- Name: export_jobs jobs_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.export_jobs
    ADD CONSTRAINT jobs_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5068 (class 2606 OID 16890)
-- Name: users users_company_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_company_id_fkey FOREIGN KEY (company_id) REFERENCES public.companies(id) ON DELETE CASCADE;


--
-- TOC entry 5069 (class 2606 OID 16895)
-- Name: users users_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- TOC entry 5121 (class 2606 OID 16900)
-- Name: webhook_events webhook_events_integration_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: supabase_admin
--

ALTER TABLE ONLY public.webhook_events
    ADD CONSTRAINT webhook_events_integration_id_fkey FOREIGN KEY (integration_id) REFERENCES public.integrations(id) ON DELETE CASCADE;


--
-- TOC entry 5127 (class 0 OID 0)
-- Dependencies: 268
-- Name: TABLE companies; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.companies TO anon;
GRANT ALL ON TABLE public.companies TO authenticated;
GRANT ALL ON TABLE public.companies TO service_role;


--
-- TOC entry 5128 (class 0 OID 0)
-- Dependencies: 269
-- Name: TABLE company_settings; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.company_settings TO anon;
GRANT ALL ON TABLE public.company_settings TO authenticated;
GRANT ALL ON TABLE public.company_settings TO service_role;


--
-- TOC entry 5129 (class 0 OID 0)
-- Dependencies: 270
-- Name: TABLE users; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.users TO anon;
GRANT ALL ON TABLE public.users TO authenticated;
GRANT ALL ON TABLE public.users TO service_role;


--
-- TOC entry 5130 (class 0 OID 0)
-- Dependencies: 271
-- Name: VIEW audit_log; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.audit_log TO anon;
GRANT ALL ON TABLE public.audit_log TO authenticated;
GRANT ALL ON TABLE public.audit_log TO service_role;


--
-- TOC entry 5131 (class 0 OID 0)
-- Dependencies: 272
-- Name: TABLE conversations; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.conversations TO anon;
GRANT ALL ON TABLE public.conversations TO authenticated;
GRANT ALL ON TABLE public.conversations TO service_role;


--
-- TOC entry 5132 (class 0 OID 0)
-- Dependencies: 273
-- Name: TABLE customers; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.customers TO anon;
GRANT ALL ON TABLE public.customers TO authenticated;
GRANT ALL ON TABLE public.customers TO service_role;


--
-- TOC entry 5133 (class 0 OID 0)
-- Dependencies: 274
-- Name: TABLE integrations; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.integrations TO anon;
GRANT ALL ON TABLE public.integrations TO authenticated;
GRANT ALL ON TABLE public.integrations TO service_role;


--
-- TOC entry 5134 (class 0 OID 0)
-- Dependencies: 275
-- Name: TABLE messages; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.messages TO anon;
GRANT ALL ON TABLE public.messages TO authenticated;
GRANT ALL ON TABLE public.messages TO service_role;


--
-- TOC entry 5135 (class 0 OID 0)
-- Dependencies: 276
-- Name: TABLE orders; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.orders TO anon;
GRANT ALL ON TABLE public.orders TO authenticated;
GRANT ALL ON TABLE public.orders TO service_role;


--
-- TOC entry 5136 (class 0 OID 0)
-- Dependencies: 277
-- Name: TABLE order_line_items; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.order_line_items TO anon;
GRANT ALL ON TABLE public.order_line_items TO authenticated;
GRANT ALL ON TABLE public.order_line_items TO service_role;


--
-- TOC entry 5137 (class 0 OID 0)
-- Dependencies: 278
-- Name: TABLE product_variants; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.product_variants TO anon;
GRANT ALL ON TABLE public.product_variants TO authenticated;
GRANT ALL ON TABLE public.product_variants TO service_role;


--
-- TOC entry 5138 (class 0 OID 0)
-- Dependencies: 279
-- Name: VIEW company_dashboard_metrics; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.company_dashboard_metrics TO anon;
GRANT ALL ON TABLE public.company_dashboard_metrics TO authenticated;
GRANT ALL ON TABLE public.company_dashboard_metrics TO service_role;


--
-- TOC entry 5139 (class 0 OID 0)
-- Dependencies: 280
-- Name: TABLE inventory_lots; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.inventory_lots TO anon;
GRANT ALL ON TABLE public.inventory_lots TO authenticated;
GRANT ALL ON TABLE public.inventory_lots TO service_role;


--
-- TOC entry 5140 (class 0 OID 0)
-- Dependencies: 281
-- Name: TABLE suppliers; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.suppliers TO anon;
GRANT ALL ON TABLE public.suppliers TO authenticated;
GRANT ALL ON TABLE public.suppliers TO service_role;


--
-- TOC entry 5141 (class 0 OID 0)
-- Dependencies: 282
-- Name: TABLE webhook_events; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.webhook_events TO anon;
GRANT ALL ON TABLE public.webhook_events TO authenticated;
GRANT ALL ON TABLE public.webhook_events TO service_role;

alter table public.companies enable row level security;
alter table public.users enable row level security;
alter table public.company_settings enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.inventory_ledger enable row level security;
alter table public.inventory_lots enable row level security;
alter table public.suppliers enable row level security;
alter table public.orders enable row level security;
alter table public.order_line_items enable row level security;
alter table public.customers enable row level security;
alter table public.customer_addresses enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.integrations enable row level security;
alter table public.webhook_events enable row level security;
alter table public.audit_log enable row level security;
alter table public.channel_fees enable row level security;
alter table public.export_jobs enable row level security;

-- Policies for companies
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.companies;
CREATE POLICY "Allow full access based on company_id" ON public.companies FOR ALL USING (id = get_current_company_id()) WITH CHECK (id = get_current_company_id());

-- Policies for users
DROP POLICY IF EXISTS "Allow full access to own company users" ON public.users;
CREATE POLICY "Allow full access to own company users" ON public.users FOR ALL USING (company_id = get_current_company_id());

-- Policies for company_settings
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.company_settings;
CREATE POLICY "Allow full access based on company_id" ON public.company_settings FOR ALL USING (company_id = get_current_company_id());

-- Policies for products
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.products;
CREATE POLICY "Allow full access based on company_id" ON public.products FOR ALL USING (company_id = get_current_company_id());

-- Policies for product_variants
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.product_variants;
CREATE POLICY "Allow full access based on company_id" ON public.product_variants FOR ALL USING (company_id = get_current_company_id());

-- Policies for inventory_ledger
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.inventory_ledger;
CREATE POLICY "Allow full access based on company_id" ON public.inventory_ledger FOR ALL USING (company_id = get_current_company_id());

-- Policies for inventory_lots
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.inventory_lots;
CREATE POLICY "Allow full access based on company_id" ON public.inventory_lots FOR ALL USING (company_id = get_current_company_id());

-- Policies for suppliers
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.suppliers;
CREATE POLICY "Allow full access based on company_id" ON public.suppliers FOR ALL USING (company_id = get_current_company_id());

-- Policies for orders
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.orders;
CREATE POLICY "Allow full access based on company_id" ON public.orders FOR ALL USING (company_id = get_current_company_id());

-- Policies for order_line_items
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.order_line_items;
CREATE POLICY "Allow full access based on company_id" ON public.order_line_items FOR ALL USING (company_id = get_current_company_id());

-- Policies for customers
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.customers;
CREATE POLICY "Allow full access based on company_id" ON public.customers FOR ALL USING (company_id = get_current_company_id());

-- Policies for customer_addresses
DROP POLICY IF EXISTS "Allow full access based on customer's company" ON public.customer_addresses;
CREATE POLICY "Allow full access based on customer's company" ON public.customer_addresses FOR ALL USING ((SELECT company_id FROM public.customers WHERE id = customer_id) = get_current_company_id());

-- Policies for conversations
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.conversations;
CREATE POLICY "Allow full access based on company_id" ON public.conversations FOR ALL USING (company_id = get_current_company_id());

-- Policies for messages
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.messages;
CREATE POLICY "Allow full access based on company_id" ON public.messages FOR ALL USING (company_id = get_current_company_id());

-- Policies for integrations
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.integrations;
CREATE POLICY "Allow full access based on company_id" ON public.integrations FOR ALL USING (company_id = get_current_company_id());

-- Policies for webhook_events
DROP POLICY IF EXISTS "Allow access based on integration's company" ON public.webhook_events;
CREATE POLICY "Allow access based on integration's company" ON public.webhook_events FOR ALL USING ((SELECT company_id FROM public.integrations WHERE id = integration_id) = get_current_company_id());

-- Policies for audit_log
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.audit_log;
CREATE POLICY "Allow full access based on company_id" ON public.audit_log FOR ALL USING (company_id = get_current_company_id());

-- Policies for channel_fees
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.channel_fees;
CREATE POLICY "Allow full access based on company_id" ON public.channel_fees FOR ALL USING (company_id = get_current_company_id());

-- Policies for export_jobs
DROP POLICY IF EXISTS "Allow full access based on company_id" ON public.export_jobs;
CREATE POLICY "Allow full access based on company_id" ON public.export_jobs FOR ALL USING (company_id = get_current_company_id());


--
-- TOC entry 5126 (class 0 OID 0)
-- Dependencies: 7
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE USAGE ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO PUBLIC;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- TOC entry 5142 (class 0 OID 0)
-- Dependencies: 1007
-- Name: FUNCTION handle_new_user(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.handle_new_user() TO anon;
GRANT ALL ON FUNCTION public.handle_new_user() TO authenticated;
GRANT ALL ON FUNCTION public.handle_new_user() TO service_role;


--
-- TOC entry 5143 (class 0 OID 0)
-- Dependencies: 1008
-- Name: FUNCTION record_order_from_platform(p_company_id uuid, p_platform text, p_order_payload jsonb); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.record_order_from_platform(p_company_id uuid, p_platform text, p_order_payload jsonb) TO anon;
GRANT ALL ON FUNCTION public.record_order_from_platform(p_company_id uuid, p_platform text, p_order_payload jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.record_order_from_platform(p_company_id uuid, p_platform text, p_order_payload jsonb) TO service_role;


--
-- TOC entry 5144 (class 0 OID 0)
-- Dependencies: 1009
-- Name: FUNCTION update_inventory_from_sale(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.update_inventory_from_sale() TO anon;
GRANT ALL ON FUNCTION public.update_inventory_from_sale() TO authenticated;
GRANT ALL ON FUNCTION public.update_inventory_from_sale() TO service_role;


--
-- TOC entry 5145 (class 0 OID 0)
-- Dependencies: 1010
-- Name: FUNCTION update_inventory_on_restock(); Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON FUNCTION public.update_inventory_on_restock() TO anon;
GRANT ALL ON FUNCTION public.update_inventory_on_restock() TO authenticated;
GRANT ALL ON FUNCTION public.update_inventory_on_restock() TO service_role;


--
-- TOC entry 5146 (class 0 OID 0)
-- Dependencies: 274
-- Name: TABLE integrations; Type: ACL; Schema: public; Owner: supabase_admin
--

GRANT ALL ON TABLE public.integrations TO postgres;


-- Completed on 2024-07-13 17:34:04 UTC

--
-- PostgreSQL database dump complete
--

