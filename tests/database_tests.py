
#!/usr/bin/env python3
"""
Enhanced Database Tests for AIVentory
Tests all database functions and stored procedures against actual data
"""

import pytest
import time
import json
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional
from test_config import TestConfig, TestCredentials
from utils.database_utils import DatabaseUtils
from utils.data_utils import TestReporter

class TestDatabaseFunctions:
    """Test all database RPC functions and queries"""
    
    def setup_method(self):
        self.db = DatabaseUtils(TestConfig.SUPABASE_URL, TestConfig.SUPABASE_SERVICE_KEY)
        self.reporter = TestReporter()
        self.test_credentials = TestCredentials()
    
    def test_get_dashboard_metrics_function(self):
        """Test get_dashboard_metrics RPC function"""
        start_time = time.time()
        try:
            companies = self.db.get_test_companies(3)
            
            for company in companies:
                company_id = company["id"]
                company_name = company.get("name", f"Company-{company_id[:8]}")
                
                print(f"\n📊 Testing dashboard metrics for {company_name}")
                
                # Test different periods
                periods = [7, 30, 90]
                for days in periods:
                    response = self.db.supabase.rpc('get_dashboard_metrics', {
                        'p_company_id': company_id,
                        'p_days': days
                    }).execute()
                    
                    if response.data:
                        metrics = response.data
                        
                        # Validate required fields
                        required_fields = ['total_revenue', 'total_orders', 'total_products', 'low_stock_count']
                        missing_fields = [field for field in required_fields if field not in metrics]
                        
                        if missing_fields:
                            print(f"   ⚠️ {days}d - Missing fields: {missing_fields}")
                        else:
                            print(f"   ✅ {days}d - Revenue: ${metrics['total_revenue']}, Orders: {metrics['total_orders']}")
                        
                        # Validate data types and ranges
                        if metrics.get('total_revenue') is not None:
                            assert isinstance(metrics['total_revenue'], (int, float)), "Revenue should be numeric"
                            assert metrics['total_revenue'] >= 0, "Revenue should be non-negative"
                        
                        if metrics.get('total_orders') is not None:
                            assert isinstance(metrics['total_orders'], int), "Order count should be integer"
                            assert metrics['total_orders'] >= 0, "Order count should be non-negative"
                    else:
                        print(f"   ⚠️ {days}d - No metrics data returned")
            
            duration = time.time() - start_time
            self.reporter.add_result("dashboard_metrics_function", "PASS", duration)
            
        except Exception as e:
            self.reporter.add_result("dashboard_metrics_function", "FAIL", time.time() - start_time, str(e))
            print(f"\n❌ Dashboard Metrics Test Failed: {e}")
            raise
    
    def test_sales_analytics_functions(self):
        """Test sales analytics RPC functions"""
        start_time = time.time()
        try:
            companies = self.db.get_test_companies(2)
            
            for company in companies:
                company_id = company["id"]
                company_name = company.get("name", f"Company-{company_id[:8]}")
                
                print(f"\n💰 Testing sales analytics for {company_name}")
                
                # Test get_sales_analytics
                sales_response = self.db.supabase.rpc('get_sales_analytics', {
                    'p_company_id': company_id
                }).execute()
                
                if sales_response.data:
                    sales_data = sales_response.data
                    print(f"   ✅ Sales analytics: {len(sales_data.get('daily_sales', []))} daily records")
                else:
                    print(f"   ⚠️ No sales analytics data")
                
                # Test get_customer_analytics
                customer_response = self.db.supabase.rpc('get_customer_analytics', {
                    'p_company_id': company_id
                }).execute()
                
                if customer_response.data:
                    customer_data = customer_response.data
                    print(f"   ✅ Customer analytics: {customer_data.get('total_customers', 0)} customers")
                else:
                    print(f"   ⚠️ No customer analytics data")
                
                # Test get_sales_velocity
                velocity_response = self.db.supabase.rpc('get_sales_velocity', {
                    'p_company_id': company_id,
                    'p_days': 30,
                    'p_limit': 10
                }).execute()
                
                if velocity_response.data:
                    velocity_data = velocity_response.data
                    print(f"   ✅ Sales velocity: {len(velocity_data)} products analyzed")
                else:
                    print(f"   ⚠️ No sales velocity data")
            
            duration = time.time() - start_time
            self.reporter.add_result("sales_analytics_functions", "PASS", duration)
            
        except Exception as e:
            self.reporter.add_result("sales_analytics_functions", "FAIL", time.time() - start_time, str(e))
            print(f"\n❌ Sales Analytics Test Failed: {e}")
            raise
    
    def test_inventory_analytics_functions(self):
        """Test inventory analytics RPC functions"""
        start_time = time.time()
        try:
            companies = self.db.get_test_companies(2)
            
            for company in companies:
                company_id = company["id"]
                company_name = company.get("name", f"Company-{company_id[:8]}")
                
                print(f"\n📦 Testing inventory analytics for {company_name}")
                
                # Test get_inventory_analytics
                inventory_response = self.db.supabase.rpc('get_inventory_analytics', {
                    'p_company_id': company_id
                }).execute()
                
                if inventory_response.data:
                    inventory_data = inventory_response.data
                    total_value = inventory_data.get('total_inventory_value', 0)
                    print(f"   ✅ Inventory analytics: ${total_value} total value")
                else:
                    print(f"   ⚠️ No inventory analytics data")
                
                # Test get_abc_analysis
                abc_response = self.db.supabase.rpc('get_abc_analysis', {
                    'p_company_id': company_id
                }).execute()
                
                if abc_response.data:
                    abc_data = abc_response.data
                    print(f"   ✅ ABC analysis: {len(abc_data)} products categorized")
                    
                    # Validate ABC categories
                    categories = {}
                    for item in abc_data:
                        category = item.get('category', 'Unknown')
                        categories[category] = categories.get(category, 0) + 1
                    
                    print(f"      Categories: {categories}")
                else:
                    print(f"   ⚠️ No ABC analysis data")
                
                # Test get_gross_margin_analysis
                margin_response = self.db.supabase.rpc('get_gross_margin_analysis', {
                    'p_company_id': company_id
                }).execute()
                
                if margin_response.data:
                    margin_data = margin_response.data
                    print(f"   ✅ Margin analysis: {len(margin_data)} products analyzed")
                else:
                    print(f"   ⚠️ No margin analysis data")
            
            duration = time.time() - start_time
            self.reporter.add_result("inventory_analytics_functions", "PASS", duration)
            
        except Exception as e:
            self.reporter.add_result("inventory_analytics_functions", "FAIL", time.time() - start_time, str(e))
            print(f"\n❌ Inventory Analytics Test Failed: {e}")
            raise
    
    def test_supplier_and_purchase_order_functions(self):
        """Test supplier and purchase order related functions"""
        start_time = time.time()
        try:
            companies = self.db.get_test_companies(2)
            
            for company in companies:
                company_id = company["id"]
                company_name = company.get("name", f"Company-{company_id[:8]}")
                
                print(f"\n🏭 Testing supplier functions for {company_name}")
                
                # Test get_supplier_performance_report
                supplier_response = self.db.supabase.rpc('get_supplier_performance_report', {
                    'p_company_id': company_id
                }).execute()
                
                if supplier_response.data:
                    supplier_data = supplier_response.data
                    print(f"   ✅ Supplier performance: {len(supplier_data)} suppliers analyzed")
                    
                    # Validate supplier data structure
                    for supplier in supplier_data[:3]:  # Check first 3
                        required_fields = ['supplier_id', 'supplier_name']
                        missing_fields = [field for field in required_fields if field not in supplier]
                        if missing_fields:
                            print(f"      ⚠️ Supplier missing fields: {missing_fields}")
                else:
                    print(f"   ⚠️ No supplier performance data")
                
                # Test purchase order views
                po_response = self.db.supabase.table('purchase_orders_view')\
                    .select('*')\
                    .eq('company_id', company_id)\
                    .limit(5)\
                    .execute()
                
                if po_response.data:
                    po_data = po_response.data
                    print(f"   ✅ Purchase orders view: {len(po_data)} orders found")
                    
                    # Validate PO structure
                    for po in po_data:
                        assert 'id' in po, "PO should have ID"
                        assert 'company_id' in po, "PO should have company_id"
                        assert po['company_id'] == company_id, "PO should belong to correct company"
                else:
                    print(f"   ⚠️ No purchase orders data")
            
            duration = time.time() - start_time
            self.reporter.add_result("supplier_purchase_order_functions", "PASS", duration)
            
        except Exception as e:
            self.reporter.add_result("supplier_purchase_order_functions", "FAIL", time.time() - start_time, str(e))
            print(f"\n❌ Supplier/PO Test Failed: {e}")
            raise
    
    def test_historical_data_functions(self):
        """Test historical data and forecasting functions"""
        start_time = time.time()
        try:
            companies = self.db.get_test_companies(2)
            
            for company in companies:
                company_id = company["id"]
                company_name = company.get("name", f"Company-{company_id[:8]}")
                
                print(f"\n📈 Testing historical data functions for {company_name}")
                
                # Get some SKUs to test with
                products = self.db.get_test_products(company_id, 10)
                if not products:
                    print(f"   ⚠️ No products found for testing")
                    continue
                
                # Get SKUs from variants
                skus = []
                for product in products:
                    for variant in product.get('product_variants', []):
                        if variant.get('sku'):
                            skus.append(variant['sku'])
                
                if not skus:
                    print(f"   ⚠️ No SKUs found for testing")
                    continue
                
                # Test get_historical_sales_for_skus
                historical_response = self.db.supabase.rpc('get_historical_sales_for_skus', {
                    'p_company_id': company_id,
                    'p_skus': skus[:5]  # Test with first 5 SKUs
                }).execute()
                
                if historical_response.data:
                    historical_data = historical_response.data
                    print(f"   ✅ Historical sales: {len(historical_data)} SKU records")
                else:
                    print(f"   ⚠️ No historical sales data")
                
                # Test get_historical_sales_for_sku (single SKU)
                if skus:
                    single_sku_response = self.db.supabase.rpc('get_historical_sales_for_sku', {
                        'p_company_id': company_id,
                        'p_sku': skus[0]
                    }).execute()
                    
                    if single_sku_response.data:
                        single_sku_data = single_sku_response.data
                        print(f"   ✅ Single SKU history: {len(single_sku_data)} records for {skus[0]}")
                    else:
                        print(f"   ⚠️ No single SKU history for {skus[0]}")
                
                # Test forecast_demand
                forecast_response = self.db.supabase.rpc('forecast_demand', {
                    'p_company_id': company_id
                }).execute()
                
                if forecast_response.data:
                    forecast_data = forecast_response.data
                    print(f"   ✅ Demand forecast: {len(forecast_data)} products forecasted")
                else:
                    print(f"   ⚠️ No demand forecast data")
            
            duration = time.time() - start_time
            self.reporter.add_result("historical_data_functions", "PASS", duration)
            
        except Exception as e:
            self.reporter.add_result("historical_data_functions", "FAIL", time.time() - start_time, str(e))
            print(f"\n❌ Historical Data Test Failed: {e}")
            raise

class TestDatabaseViews:
    """Test database views and materialized views"""
    
    def setup_method(self):
        self.db = DatabaseUtils(TestConfig.SUPABASE_URL, TestConfig.SUPABASE_SERVICE_KEY)
        self.reporter = TestReporter()
    
    def test_inventory_views(self):
        """Test inventory-related views"""
        start_time = time.time()
        try:
            companies = self.db.get_test_companies(2)
            
            for company in companies:
                company_id = company["id"]
                company_name = company.get("name", f"Company-{company_id[:8]}")
                
                print(f"\n👁️ Testing inventory views for {company_name}")
                
                # Test product_variants_with_details view
                variants_response = self.db.supabase.table('product_variants_with_details')\
                    .select('*')\
                    .eq('company_id', company_id)\
                    .limit(10)\
                    .execute()
                
                if variants_response.data:
                    variants_data = variants_response.data
                    print(f"   ✅ Variants with details: {len(variants_data)} records")
                    
                    # Validate view structure
                    required_fields = ['id', 'sku', 'product_title', 'inventory_quantity']
                    for variant in variants_data[:3]:
                        missing_fields = [field for field in required_fields if field not in variant]
                        if missing_fields:
                            print(f"      ⚠️ Variant missing fields: {missing_fields}")
                else:
                    print(f"   ⚠️ No variants with details found")
            
            duration = time.time() - start_time
            self.reporter.add_result("inventory_views", "PASS", duration)
            
        except Exception as e:
            self.reporter.add_result("inventory_views", "FAIL", time.time() - start_time, str(e))
            print(f"\n❌ Inventory Views Test Failed: {e}")
            raise
    
    def test_order_views(self):
        """Test order-related views"""
        start_time = time.time()
        try:
            companies = self.db.get_test_companies(2)
            
            for company in companies:
                company_id = company["id"]
                company_name = company.get("name", f"Company-{company_id[:8]}")
                
                print(f"\n🛒 Testing order views for {company_name}")
                
                # Test orders_view
                orders_response = self.db.supabase.table('orders_view')\
                    .select('*')\
                    .eq('company_id', company_id)\
                    .limit(10)\
                    .execute()
                
                if orders_response.data:
                    orders_data = orders_response.data
                    print(f"   ✅ Orders view: {len(orders_data)} records")
                    
                    # Validate order view structure
                    required_fields = ['id', 'order_number', 'total_amount', 'created_at']
                    for order in orders_data[:3]:
                        missing_fields = [field for field in required_fields if field not in order]
                        if missing_fields:
                            print(f"      ⚠️ Order missing fields: {missing_fields}")
                else:
                    print(f"   ⚠️ No orders found in view")
            
            duration = time.time() - start_time
            self.reporter.add_result("order_views", "PASS", duration)
            
        except Exception as e:
            self.reporter.add_result("order_views", "FAIL", time.time() - start_time, str(e))
            print(f"\n❌ Order Views Test Failed: {e}")
            raise
    
    def test_customer_views(self):
        """Test customer-related views"""
        start_time = time.time()
        try:
            companies = self.db.get_test_companies(2)
            
            for company in companies:
                company_id = company["id"]
                company_name = company.get("name", f"Company-{company_id[:8]}")
                
                print(f"\n👥 Testing customer views for {company_name}")
                
                # Test customers_view
                customers_response = self.db.supabase.table('customers_view')\
                    .select('*')\
                    .eq('company_id', company_id)\
                    .limit(10)\
                    .execute()
                
                if customers_response.data:
                    customers_data = customers_response.data
                    print(f"   ✅ Customers view: {len(customers_data)} records")
                    
                    # Validate customer view structure
                    required_fields = ['id', 'customer_name', 'total_orders', 'total_spent']
                    for customer in customers_data[:3]:
                        missing_fields = [field for field in required_fields if field not in customer]
                        if missing_fields:
                            print(f"      ⚠️ Customer missing fields: {missing_fields}")
                        
                        # Validate data types
                        if 'total_spent' in customer and customer['total_spent'] is not None:
                            assert isinstance(customer['total_spent'], (int, float)), "total_spent should be numeric"
                        
                        if 'total_orders' in customer and customer['total_orders'] is not None:
                            assert isinstance(customer['total_orders'], int), "total_orders should be integer"
                else:
                    print(f"   ⚠️ No customers found in view")
            
            duration = time.time() - start_time
            self.reporter.add_result("customer_views", "PASS", duration)
            
        except Exception as e:
            self.reporter.add_result("customer_views", "FAIL", time.time() - start_time, str(e))
            print(f"\n❌ Customer Views Test Failed: {e}")
            raise

class TestDatabasePerformance:
    """Test database performance and query optimization"""
    
    def setup_method(self):
        self.db = DatabaseUtils(TestConfig.SUPABASE_URL, TestConfig.SUPABASE_SERVICE_KEY)
        self.reporter = TestReporter()
    
    def test_query_performance(self):
        """Test query performance for common operations"""
        start_time = time.time()
        try:
            companies = self.db.get_test_companies(1)
            if not companies:
                print("⚠️ No companies found for performance testing")
                return
            
            company_id = companies[0]["id"]
            company_name = companies[0].get("name", "Unknown")
            
            print(f"\n⚡ Testing query performance for {company_name}")
            
            # Test large inventory query performance
            inventory_start = time.time()
            inventory_response = self.db.supabase.table('product_variants_with_details')\
                .select('*')\
                .eq('company_id', company_id)\
                .limit(1000)\
                .execute()
            inventory_duration = time.time() - inventory_start
            
            print(f"   📦 Inventory query: {inventory_duration:.2f}s ({len(inventory_response.data or [])} records)")
            
            # Test large orders query performance
            orders_start = time.time()
            orders_response = self.db.supabase.table('orders_view')\
                .select('*')\
                .eq('company_id', company_id)\
                .limit(500)\
                .execute()
            orders_duration = time.time() - orders_start
            
            print(f"   🛒 Orders query: {orders_duration:.2f}s ({len(orders_response.data or [])} records)")
            
            # Test analytics RPC performance
            analytics_start = time.time()
            analytics_response = self.db.supabase.rpc('get_dashboard_metrics', {
                'p_company_id': company_id,
                'p_days': 90
            }).execute()
            analytics_duration = time.time() - analytics_start
            
            print(f"   📊 Analytics RPC: {analytics_duration:.2f}s")
            
            # Performance assertions
            assert inventory_duration < 5.0, f"Inventory query too slow: {inventory_duration:.2f}s"
            assert orders_duration < 3.0, f"Orders query too slow: {orders_duration:.2f}s"
            assert analytics_duration < 10.0, f"Analytics RPC too slow: {analytics_duration:.2f}s"
            
            duration = time.time() - start_time
            self.reporter.add_result("query_performance", "PASS", duration,
                                   details={
                                       "inventory_duration": inventory_duration,
                                       "orders_duration": orders_duration,
                                       "analytics_duration": analytics_duration
                                   })
            
            print(f"   ✅ All queries performed within acceptable limits")
            
        except Exception as e:
            self.reporter.add_result("query_performance", "FAIL", time.time() - start_time, str(e))
            print(f"\n❌ Query Performance Test Failed: {e}")
            raise

if __name__ == "__main__":
    print("🗄️ Running Enhanced Database Tests...")
    print("=" * 50)
    
    # Run with pytest
    pytest.main([__file__, "-v", "--tb=short"])
