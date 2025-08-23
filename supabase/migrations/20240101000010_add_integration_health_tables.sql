-- Database Performance Optimization Script
-- Run this in Supabase SQL Editor (Fixed - Using actual schema table names)

-- Core table performance indexes (using actual schema)
CREATE INDEX IF NOT EXISTS idx_companies_created_at 
ON companies(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_companies_name 
ON companies(name);

-- Inventory performance indexes
CREATE INDEX IF NOT EXISTS idx_inventory_company_sku 
ON inventory(company_id, sku);

CREATE INDEX IF NOT EXISTS idx_inventory_category 
ON inventory(company_id, category);

CREATE INDEX IF NOT EXISTS idx_inventory_low_stock 
ON inventory(company_id, quantity) 
WHERE quantity <= reorder_point;

CREATE INDEX IF NOT EXISTS idx_inventory_created_at 
ON inventory(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_inventory_last_sold 
ON inventory(last_sold_date DESC NULLS LAST);

-- Purchase orders performance indexes
CREATE INDEX IF NOT EXISTS idx_purchase_orders_company_date 
ON purchase_orders(company_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_purchase_orders_vendor 
ON purchase_orders(vendor_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_purchase_orders_expected_date 
ON purchase_orders(company_id, expected_date);

-- Vendors performance indexes
CREATE INDEX IF NOT EXISTS idx_vendors_company_name 
ON vendors(company_id, vendor_name);

CREATE INDEX IF NOT EXISTS idx_vendors_created_at 
ON vendors(created_at DESC);

-- Users performance indexes
CREATE INDEX IF NOT EXISTS idx_users_company 
ON users(company_id);

CREATE INDEX IF NOT EXISTS idx_users_email 
ON users(email);

-- Additional useful indexes for queries
CREATE INDEX IF NOT EXISTS idx_inventory_warehouse 
ON inventory(company_id, warehouse_name);

CREATE INDEX IF NOT EXISTS idx_inventory_supplier 
ON inventory(company_id, supplier_name);

CREATE INDEX IF NOT EXISTS idx_inventory_reorder 
ON inventory(company_id, reorder_point, quantity);