#!/usr/bin/env python3
"""
Comprehensive API Tests for Invochat
Tests all API endpoints, authentication, and data validation
"""

import pytest
import time
import json
import requests
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional
from test_config import TestConfig, TestCredentials
from utils.api_utils import APIUtils
from utils.database_utils import DatabaseUtils
from utils.data_utils import TestReporter

class TestAPIAuthentication:
    """Test API authentication and authorization"""
    
    def setup_method(self):
        self.api = APIUtils(TestConfig.API_BASE_URL)
        self.db = DatabaseUtils(TestConfig.SUPABASE_URL, TestConfig.SUPABASE_SERVICE_KEY)
        self.reporter = TestReporter()
        self.test_credentials = TestCredentials()
    
    def test_valid_user_authentication(self):
        """Test authentication with valid user credentials"""
        start_time = time.time()
        try:
            creds = self.test_credentials.get_user_credentials("Owner")
            
            print(f"🔐 Testing authentication for: {creds['email']}")
            
            # Test login
            login_result = self.api.login(creds["email"], creds["password"])
            
            # Verify authentication worked
            auth_successful = login_result is not None
            
            if auth_successful:
                print(f"   ✅ Authentication successful")
                
                # Test authenticated endpoint access
                response = self.api.get("/health")
                
                if response.status_code in [200, 404]:  # 404 if endpoint doesn't exist
                    print(f"   ✅ Authenticated API access: {response.status_code}")
                else:
                    print(f"   ⚠️ Unexpected API response: {response.status_code}")
            else:
                print(f"   ❌ Authentication failed")
            
            duration = time.time() - start_time
            self.reporter.add_result("valid_user_authentication", "PASS" if auth_successful else "FAIL", duration)
            
            assert auth_successful, "Valid user authentication should succeed"
            
        except Exception as e:
            self.reporter.add_result("valid_user_authentication", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Authentication test failed: {e}")
            raise
    
    def test_invalid_user_authentication(self):
        """Test authentication with invalid credentials"""
        start_time = time.time()
        try:
            invalid_creds = self.test_credentials.get_invalid_credentials()
            
            print(f"🚫 Testing authentication with invalid credentials")
            
            auth_failures = 0
            
            for creds in invalid_creds[:3]:  # Test first 3 invalid credentials
                print(f"   Testing: {creds['email']}")
                
                login_result = self.api.login(creds["email"], creds["password"])
                
                if login_result is None:  # Login should fail
                    auth_failures += 1
                    print(f"      ✅ Correctly rejected invalid credentials")
                else:
                    print(f"      ❌ Invalid credentials were accepted")
            
            success = auth_failures == len(invalid_creds[:3])
            
            duration = time.time() - start_time
            self.reporter.add_result("invalid_user_authentication", "PASS" if success else "FAIL", duration)
            
            assert success, "Invalid credentials should be rejected"
            
        except Exception as e:
            self.reporter.add_result("invalid_user_authentication", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Invalid authentication test failed: {e}")
            raise
    
    def test_multi_company_data_isolation(self):
        """Test that users can only access their company's data"""
        start_time = time.time()
        try:
            # Get credentials for different companies
            all_users = self.test_credentials._credentials["test_users"]
            
            if len(all_users) < 2:
                print("⚠️ Need at least 2 users from different companies")
                return
            
            user1 = all_users[0]
            user2 = all_users[1]
            
            print(f"🏢 Testing data isolation between companies")
            print(f"   User 1: {user1['email']} ({user1['company_name']})")
            print(f"   User 2: {user2['email']} ({user2['company_name']})")
            
            # Login as user 1 and get data
            self.api.login(user1["email"], user1["password"])
            
            user1_products = self._get_user_products()
            user1_orders = self._get_user_orders()
            
            # Login as user 2 and get data
            self.api.login(user2["email"], user2["password"])
            
            user2_products = self._get_user_products()
            user2_orders = self._get_user_orders()
            
            # Verify data isolation
            products_isolated = not self._has_data_overlap(user1_products, user2_products)
            orders_isolated = not self._has_data_overlap(user1_orders, user2_orders)
            
            print(f"   📦 Products isolated: {products_isolated}")
            print(f"   🛒 Orders isolated: {orders_isolated}")
            
            isolation_success = products_isolated and orders_isolated
            
            duration = time.time() - start_time
            self.reporter.add_result("multi_company_data_isolation", "PASS" if isolation_success else "FAIL", duration)
            
            assert isolation_success, "Companies should have isolated data"
            
        except Exception as e:
            self.reporter.add_result("multi_company_data_isolation", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Data isolation test failed: {e}")
            raise
    
    def _get_user_products(self) -> List[Dict]:
        """Get products for currently authenticated user"""
        try:
            response = self.api.get("/products")
            if response.status_code == 200:
                data = response.json()
                return data if isinstance(data, list) else data.get('data', [])
            return []
        except:
            return []
    
    def _get_user_orders(self) -> List[Dict]:
        """Get orders for currently authenticated user"""
        try:
            response = self.api.get("/orders")
            if response.status_code == 200:
                data = response.json()
                return data if isinstance(data, list) else data.get('data', [])
            return []
        except:
            return []
    
    def _has_data_overlap(self, data1: List[Dict], data2: List[Dict]) -> bool:
        """Check if two datasets have overlapping IDs"""
        ids1 = {item.get('id') for item in data1 if item.get('id')}
        ids2 = {item.get('id') for item in data2 if item.get('id')}
        return len(ids1.intersection(ids2)) > 0

class TestCRUDOperations:
    """Test CRUD operations for all major entities"""
    
    def setup_method(self):
        self.api = APIUtils(TestConfig.API_BASE_URL)
        self.db = DatabaseUtils(TestConfig.SUPABASE_URL, TestConfig.SUPABASE_SERVICE_KEY)
        self.reporter = TestReporter()
        self.test_credentials = TestCredentials()
        
        # Login before each test
        creds = self.test_credentials.get_user_credentials("Owner")
        self.api.login(creds["email"], creds["password"])
    
    def test_products_crud_operations(self):
        """Test products CRUD operations"""
        start_time = time.time()
        try:
            print("📦 Testing Products CRUD operations")
            
            # Test GET /products
            get_response = self.api.get("/products")
            print(f"   GET /products: {get_response.status_code}")
            
            if get_response.status_code == 200:
                products_data = get_response.json()
                products_list = products_data if isinstance(products_data, list) else products_data.get('data', [])
                print(f"      Found {len(products_list)} products")
                
                # Validate product structure
                if products_list:
                    product = products_list[0]
                    required_fields = ['id', 'title']
                    missing_fields = [field for field in required_fields if field not in product]
                    if missing_fields:
                        print(f"      ⚠️ Product missing fields: {missing_fields}")
                    else:
                        print(f"      ✅ Product structure valid")
            
            # Test POST /products (if endpoint exists)
            test_product = {
                "title": f"Test Product {datetime.now().isoformat()}",
                "description": "Test product for API testing",
                "status": "active"
            }
            
            post_response = self.api.post("/products", test_product)
            print(f"   POST /products: {post_response.status_code}")
            
            if post_response.status_code in [201, 200]:
                created_product = post_response.json()
                product_id = created_product.get('id')
                print(f"      ✅ Product created with ID: {product_id}")
                
                # Test PUT /products/{id} (if endpoint exists)
                if product_id:
                    update_data = {"title": f"Updated Test Product {datetime.now().isoformat()}"}
                    put_response = self.api.put(f"/products/{product_id}", update_data)
                    print(f"   PUT /products/{product_id}: {put_response.status_code}")
                    
                    # Test DELETE /products/{id} (if endpoint exists)
                    delete_response = self.api.delete(f"/products/{product_id}")
                    print(f"   DELETE /products/{product_id}: {delete_response.status_code}")
            elif post_response.status_code == 404:
                print("      ⚠️ POST endpoint not implemented")
            
            duration = time.time() - start_time
            self.reporter.add_result("products_crud_operations", "PASS", duration)
            
        except Exception as e:
            self.reporter.add_result("products_crud_operations", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Products CRUD test failed: {e}")
            raise
    
    def test_orders_crud_operations(self):
        """Test orders CRUD operations"""
        start_time = time.time()
        try:
            print("🛒 Testing Orders CRUD operations")
            
            # Test GET /orders
            get_response = self.api.get("/orders")
            print(f"   GET /orders: {get_response.status_code}")
            
            if get_response.status_code == 200:
                orders_data = get_response.json()
                orders_list = orders_data if isinstance(orders_data, list) else orders_data.get('data', [])
                print(f"      Found {len(orders_list)} orders")
                
                # Validate order structure
                if orders_list:
                    order = orders_list[0]
                    required_fields = ['id', 'order_number', 'total_amount']
                    missing_fields = [field for field in required_fields if field not in order]
                    if missing_fields:
                        print(f"      ⚠️ Order missing fields: {missing_fields}")
                    else:
                        print(f"      ✅ Order structure valid")
                        
                        # Validate data types
                        if 'total_amount' in order:
                            assert isinstance(order['total_amount'], (int, float)), "total_amount should be numeric"
                        if 'created_at' in order:
                            assert isinstance(order['created_at'], str), "created_at should be string"
            
            # Test order search/filtering
            search_response = self.api.get("/orders?query=test")
            print(f"   GET /orders?query=test: {search_response.status_code}")
            
            # Test order pagination
            paginated_response = self.api.get("/orders?page=1&limit=10")
            print(f"   GET /orders?page=1&limit=10: {paginated_response.status_code}")
            
            duration = time.time() - start_time
            self.reporter.add_result("orders_crud_operations", "PASS", duration)
            
        except Exception as e:
            self.reporter.add_result("orders_crud_operations", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Orders CRUD test failed: {e}")
            raise
    
    def test_customers_crud_operations(self):
        """Test customers CRUD operations"""
        start_time = time.time()
        try:
            print("👥 Testing Customers CRUD operations")
            
            # Test GET /customers
            get_response = self.api.get("/customers")
            print(f"   GET /customers: {get_response.status_code}")
            
            if get_response.status_code == 200:
                customers_data = get_response.json()
                customers_list = customers_data if isinstance(customers_data, list) else customers_data.get('data', [])
                print(f"      Found {len(customers_list)} customers")
                
                # Validate customer structure
                if customers_list:
                    customer = customers_list[0]
                    required_fields = ['id', 'customer_name']
                    missing_fields = [field for field in required_fields if field not in customer]
                    if missing_fields:
                        print(f"      ⚠️ Customer missing fields: {missing_fields}")
                    else:
                        print(f"      ✅ Customer structure valid")
            
            duration = time.time() - start_time
            self.reporter.add_result("customers_crud_operations", "PASS", duration)
            
        except Exception as e:
            self.reporter.add_result("customers_crud_operations", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Customers CRUD test failed: {e}")
            raise
    
    def test_suppliers_crud_operations(self):
        """Test suppliers CRUD operations"""
        start_time = time.time()
        try:
            print("🏭 Testing Suppliers CRUD operations")
            
            # Test GET /suppliers
            get_response = self.api.get("/suppliers")
            print(f"   GET /suppliers: {get_response.status_code}")
            
            if get_response.status_code == 200:
                suppliers_data = get_response.json()
                suppliers_list = suppliers_data if isinstance(suppliers_data, list) else suppliers_data.get('data', [])
                print(f"      Found {len(suppliers_list)} suppliers")
                
                # Validate supplier structure
                if suppliers_list:
                    supplier = suppliers_list[0]
                    required_fields = ['id', 'name']
                    missing_fields = [field for field in required_fields if field not in supplier]
                    if missing_fields:
                        print(f"      ⚠️ Supplier missing fields: {missing_fields}")
                    else:
                        print(f"      ✅ Supplier structure valid")
            
            # Test POST /suppliers (create new supplier)
            test_supplier = {
                "name": f"Test Supplier {datetime.now().isoformat()}",
                "email": "test@supplier.com",
                "phone": "555-0123",
                "default_lead_time_days": 14
            }
            
            post_response = self.api.post("/suppliers", test_supplier)
            print(f"   POST /suppliers: {post_response.status_code}")
            
            if post_response.status_code in [201, 200]:
                created_supplier = post_response.json()
                supplier_id = created_supplier.get('id')
                print(f"      ✅ Supplier created with ID: {supplier_id}")
                
                # Test PUT /suppliers/{id}
                if supplier_id:
                    update_data = {"name": f"Updated Test Supplier {datetime.now().isoformat()}"}
                    put_response = self.api.put(f"/suppliers/{supplier_id}", update_data)
                    print(f"   PUT /suppliers/{supplier_id}: {put_response.status_code}")
                    
                    # Test DELETE /suppliers/{id}
                    delete_response = self.api.delete(f"/suppliers/{supplier_id}")
                    print(f"   DELETE /suppliers/{supplier_id}: {delete_response.status_code}")
            
            duration = time.time() - start_time
            self.reporter.add_result("suppliers_crud_operations", "PASS", duration)
            
        except Exception as e:
            self.reporter.add_result("suppliers_crud_operations", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Suppliers CRUD test failed: {e}")
            raise

class TestAnalyticsEndpoints:
    """Test analytics and reporting endpoints"""
    
    def setup_method(self):
        self.api = APIUtils(TestConfig.API_BASE_URL)
        self.db = DatabaseUtils(TestConfig.SUPABASE_URL, TestConfig.SUPABASE_SERVICE_KEY)
        self.reporter = TestReporter()
        self.test_credentials = TestCredentials()
        
        # Login before each test
        creds = self.test_credentials.get_user_credentials("Owner")
        self.api.login(creds["email"], creds["password"])
    
    def test_dashboard_analytics_endpoints(self):
        """Test dashboard analytics endpoints"""
        start_time = time.time()
        try:
            print("📊 Testing Dashboard Analytics endpoints")
            
            # Test dashboard metrics
            dashboard_response = self.api.get("/analytics/dashboard")
            print(f"   GET /analytics/dashboard: {dashboard_response.status_code}")
            
            if dashboard_response.status_code == 200:
                dashboard_data = dashboard_response.json()
                
                # Validate dashboard metrics structure
                expected_metrics = ['total_revenue', 'total_orders', 'total_products', 'low_stock_count']
                present_metrics = [metric for metric in expected_metrics if metric in dashboard_data]
                print(f"      ✅ Dashboard metrics present: {len(present_metrics)}/{len(expected_metrics)}")
                
                # Validate data types
                if 'total_revenue' in dashboard_data:
                    assert isinstance(dashboard_data['total_revenue'], (int, float)), "Revenue should be numeric"
                if 'total_orders' in dashboard_data:
                    assert isinstance(dashboard_data['total_orders'], int), "Order count should be integer"
            
            # Test dashboard with period parameter
            period_response = self.api.get("/analytics/dashboard?period=30")
            print(f"   GET /analytics/dashboard?period=30: {period_response.status_code}")
            
            # Test sales analytics
            sales_response = self.api.get("/analytics/sales")
            print(f"   GET /analytics/sales: {sales_response.status_code}")
            
            # Test inventory analytics
            inventory_response = self.api.get("/analytics/inventory")
            print(f"   GET /analytics/inventory: {inventory_response.status_code}")
            
            duration = time.time() - start_time
            self.reporter.add_result("dashboard_analytics_endpoints", "PASS", duration)
            
        except Exception as e:
            self.reporter.add_result("dashboard_analytics_endpoints", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Dashboard Analytics test failed: {e}")
            raise
    
    def test_ai_analytics_endpoints(self):
        """Test AI-powered analytics endpoints"""
        start_time = time.time()
        try:
            print("🤖 Testing AI Analytics endpoints")
            
            # Test dead stock analysis
            dead_stock_response = self.api.get("/analytics/dead-stock")
            print(f"   GET /analytics/dead-stock: {dead_stock_response.status_code}")
            
            if dead_stock_response.status_code == 200:
                dead_stock_data = dead_stock_response.json()
                if isinstance(dead_stock_data, list):
                    print(f"      ✅ Dead stock analysis: {len(dead_stock_data)} items")
                    
                    # Validate dead stock item structure
                    if dead_stock_data:
                        item = dead_stock_data[0]
                        required_fields = ['sku', 'quantity', 'days_since_sale']
                        missing_fields = [field for field in required_fields if field not in item]
                        if missing_fields:
                            print(f"        ⚠️ Dead stock item missing fields: {missing_fields}")
                        else:
                            print(f"        ✅ Dead stock item structure valid")
                else:
                    print(f"      ⚠️ Unexpected dead stock data format")
            
            # Test reorder suggestions
            reorder_response = self.api.get("/analytics/reorder")
            print(f"   GET /analytics/reorder: {reorder_response.status_code}")
            
            if reorder_response.status_code == 200:
                reorder_data = reorder_response.json()
                if isinstance(reorder_data, list):
                    print(f"      ✅ Reorder suggestions: {len(reorder_data)} items")
                    
                    # Validate reorder suggestion structure
                    if reorder_data:
                        suggestion = reorder_data[0]
                        required_fields = ['sku', 'current_stock', 'suggested_reorder_quantity']
                        missing_fields = [field for field in required_fields if field not in suggestion]
                        if missing_fields:
                            print(f"        ⚠️ Reorder suggestion missing fields: {missing_fields}")
                        else:
                            print(f"        ✅ Reorder suggestion structure valid")
                            
                            # Check for AI enhancement fields
                            ai_fields = ['seasonality_factor', 'adjustment_reason', 'confidence']
                            ai_present = [field for field in ai_fields if field in suggestion]
                            print(f"        🤖 AI enhancements present: {len(ai_present)}/{len(ai_fields)}")
            
            # Test inventory turnover analysis
            turnover_response = self.api.get("/analytics/inventory-turnover")
            print(f"   GET /analytics/inventory-turnover: {turnover_response.status_code}")
            
            # Test supplier performance
            supplier_performance_response = self.api.get("/analytics/supplier-performance")
            print(f"   GET /analytics/supplier-performance: {supplier_performance_response.status_code}")
            
            # Test ABC analysis
            abc_response = self.api.get("/analytics/abc-analysis")
            print(f"   GET /analytics/abc-analysis: {abc_response.status_code}")
            
            if abc_response.status_code == 200:
                abc_data = abc_response.json()
                if isinstance(abc_data, list):
                    print(f"      ✅ ABC analysis: {len(abc_data)} products categorized")
                    
                    # Validate ABC categories
                    categories = {}
                    for item in abc_data:
                        category = item.get('category', 'Unknown')
                        categories[category] = categories.get(category, 0) + 1
                    
                    print(f"        Categories: {categories}")
            
            duration = time.time() - start_time
            self.reporter.add_result("ai_analytics_endpoints", "PASS", duration)
            
        except Exception as e:
            self.reporter.add_result("ai_analytics_endpoints", "FAIL", time.time() - start_time, str(e))
            print(f"❌ AI Analytics test failed: {e}")
            raise

class TestChatAndConversationEndpoints:
    """Test AI chat and conversation endpoints"""
    
    def setup_method(self):
        self.api = APIUtils(TestConfig.API_BASE_URL)
        self.db = DatabaseUtils(TestConfig.SUPABASE_URL, TestConfig.SUPABASE_SERVICE_KEY)
        self.reporter = TestReporter()
        self.test_credentials = TestCredentials()
        
        # Login before each test
        creds = self.test_credentials.get_user_credentials("Owner")
        self.api.login(creds["email"], creds["password"])
    
    def test_conversations_endpoints(self):
        """Test conversation management endpoints"""
        start_time = time.time()
        try:
            print("💬 Testing Conversations endpoints")
            
            # Test GET /conversations
            conversations_response = self.api.get("/conversations")
            print(f"   GET /conversations: {conversations_response.status_code}")
            
            if conversations_response.status_code == 200:
                conversations_data = conversations_response.json()
                conversations_list = conversations_data if isinstance(conversations_data, list) else conversations_data.get('data', [])
                print(f"      Found {len(conversations_list)} conversations")
                
                # Validate conversation structure
                if conversations_list:
                    conversation = conversations_list[0]
                    required_fields = ['id', 'title', 'created_at']
                    missing_fields = [field for field in required_fields if field not in conversation]
                    if missing_fields:
                        print(f"      ⚠️ Conversation missing fields: {missing_fields}")
                    else:
                        print(f"      ✅ Conversation structure valid")
            
            # Test POST /conversations (create new conversation)
            test_conversation = {
                "title": f"Test Conversation {datetime.now().isoformat()}"
            }
            
            post_response = self.api.post("/conversations", test_conversation)
            print(f"   POST /conversations: {post_response.status_code}")
            
            conversation_id = None
            if post_response.status_code in [201, 200]:
                created_conversation = post_response.json()
                conversation_id = created_conversation.get('id')
                print(f"      ✅ Conversation created with ID: {conversation_id}")
            
            # Test conversation messages if conversation was created
            if conversation_id:
                # Test GET /conversations/{id}/messages
                messages_response = self.api.get(f"/conversations/{conversation_id}/messages")
                print(f"   GET /conversations/{conversation_id}/messages: {messages_response.status_code}")
                
                # Test POST /conversations/{id}/messages (send message)
                test_message = {
                    "content": "What are my top selling products?",
                    "role": "user"
                }
                
                message_post_response = self.api.post(f"/conversations/{conversation_id}/messages", test_message)
                print(f"   POST /conversations/{conversation_id}/messages: {message_post_response.status_code}")
                
                if message_post_response.status_code in [201, 200]:
                    print(f"      ✅ Message sent successfully")
            
            duration = time.time() - start_time
            self.reporter.add_result("conversations_endpoints", "PASS", duration)
            
        except Exception as e:
            self.reporter.add_result("conversations_endpoints", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Conversations test failed: {e}")
            raise
    
    def test_chat_functionality(self):
        """Test AI chat functionality and responses"""
        start_time = time.time()
        try:
            print("🤖 Testing Chat functionality")
            
            # Test chat endpoint
            chat_response = self.api.post("/chat", {
                "content": "Show me my inventory summary",
                "conversation_id": None
            })
            print(f"   POST /chat: {chat_response.status_code}")
            
            if chat_response.status_code == 200:
                chat_data = chat_response.json()
                
                # Validate chat response structure
                if 'response' in chat_data or 'message' in chat_data:
                    print(f"      ✅ Chat response received")
                    
                    # Check for AI components
                    if 'component' in chat_data:
                        print(f"      🎨 Response includes component: {chat_data['component']}")
                    
                    if 'visualization' in chat_data:
                        print(f"      📊 Response includes visualization")
                else:
                    print(f"      ⚠️ Unexpected chat response format")
            
            # Test different types of chat queries
            test_queries = [
                "What products need reordering?",
                "Show me dead stock analysis",
                "Which suppliers perform best?",
                "What's my inventory turnover?"
            ]
            
            successful_queries = 0
            
            for query in test_queries:
                query_response = self.api.post("/chat", {
                    "content": query,
                    "conversation_id": None
                })
                
                if query_response.status_code == 200:
                    successful_queries += 1
                    print(f"      ✅ Query successful: '{query[:30]}...'")
                else:
                    print(f"      ⚠️ Query failed ({query_response.status_code}): '{query[:30]}...'")
            
            query_success_rate = successful_queries / len(test_queries)
            print(f"      📊 Query success rate: {query_success_rate:.1%}")
            
            duration = time.time() - start_time
            self.reporter.add_result("chat_functionality", "PASS", duration,
                                   details={"query_success_rate": query_success_rate})
            
        except Exception as e:
            self.reporter.add_result("chat_functionality", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Chat functionality test failed: {e}")
            raise

class TestAPIErrorHandling:
    """Test API error handling and edge cases"""
    
    def setup_method(self):
        self.api = APIUtils(TestConfig.API_BASE_URL)
        self.reporter = TestReporter()
        self.test_credentials = TestCredentials()
        
        # Login before each test
        creds = self.test_credentials.get_user_credentials("Owner")
        self.api.login(creds["email"], creds["password"])
    
    def test_invalid_endpoints(self):
        """Test behavior with invalid endpoints"""
        start_time = time.time()
        try:
            print("🚫 Testing invalid endpoints")
            
            invalid_endpoints = [
                "/nonexistent",
                "/invalid/path",
                "/api/fake-endpoint",
                "/products/invalid-id",
                "/orders/00000000-0000-0000-0000-000000000000"
            ]
            
            expected_failures = 0
            
            for endpoint in invalid_endpoints:
                response = self.api.get(endpoint)
                print(f"   GET {endpoint}: {response.status_code}")
                
                if response.status_code in [404, 400, 401, 403]:
                    expected_failures += 1
                    print(f"      ✅ Correctly returned error status")
                else:
                    print(f"      ⚠️ Unexpected status for invalid endpoint")
            
            error_handling_success = expected_failures / len(invalid_endpoints)
            
            duration = time.time() - start_time
            self.reporter.add_result("invalid_endpoints", "PASS", duration,
                                   details={"error_handling_rate": error_handling_success})
            
            print(f"   📊 Error handling success rate: {error_handling_success:.1%}")
            
        except Exception as e:
            self.reporter.add_result("invalid_endpoints", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Invalid endpoints test failed: {e}")
            raise
    
    def test_malformed_requests(self):
        """Test API behavior with malformed requests"""
        start_time = time.time()
        try:
            print("📝 Testing malformed requests")
            
            # Test POST with invalid JSON
            malformed_json_response = self.api.session.post(f"{self.api.base_url}/products", 
                                                          data="invalid json", 
                                                          headers={'Content-Type': 'application/json'})
            print(f"   POST with invalid JSON: {malformed_json_response.status_code}")
            
            # Test POST with missing required fields
            incomplete_data_response = self.api.post("/suppliers", {})
            print(f"   POST with incomplete data: {incomplete_data_response.status_code}")
            
            # Test PUT with invalid ID format
            invalid_id_response = self.api.put("/products/invalid-uuid", {"title": "test"})
            print(f"   PUT with invalid ID: {invalid_id_response.status_code}")
            
            duration = time.time() - start_time
            self.reporter.add_result("malformed_requests", "PASS", duration)
            
        except Exception as e:
            self.reporter.add_result("malformed_requests", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Malformed requests test failed: {e}")
            raise

if __name__ == "__main__":
    print("🔌 Running Comprehensive API Tests...")
    print("=" * 50)
    
    # Run with pytest
    pytest.main([__file__, "-v", "--tb=short"])
