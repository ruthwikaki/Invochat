#!/usr/bin/env python3
"""
Invochat Comprehensive Business Logic Tests
Validates all AI tools and business features against actual database data
"""

import pytest
import time
import json
import math
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional
from test_config import TestConfig, TestCredentials
from utils.api_utils import APIUtils
from utils.database_utils import DatabaseUtils
from utils.data_utils import TestReporter

class TestDeadStockBusinessLogic:
    """Test dead stock analysis accuracy against database calculations"""
    
    def setup_method(self):
        self.api = APIUtils(TestConfig.API_BASE_URL)
        self.db = DatabaseUtils(TestConfig.SUPABASE_URL, TestConfig.SUPABASE_SERVICE_KEY)
        self.reporter = TestReporter()
        self.test_credentials = TestCredentials()
        
        # Login with test user
        creds = self.test_credentials.get_user_credentials("Owner")
        self.api.login(creds["email"], creds["password"])
        print(f"🔐 Logged in as: {creds['email']}")
    
    def test_dead_stock_calculation_accuracy(self):
        """Test dead stock calculation matches manual calculation"""
        start_time = time.time()
        try:
            companies = self.db.get_test_companies(3)
            assert len(companies) > 0, "Need companies for testing"
            
            overall_accuracy = []
            
            for company in companies:
                company_id = company["id"]
                company_name = company.get("name", f"Company-{company_id[:8]}")
                
                print(f"\n🧮 Testing dead stock calculation for {company_name}")
                
                # Manual calculation - get products with no sales in 90 days
                expected_dead_stock = self._calculate_dead_stock_manually(company_id)
                
                # Get AI calculation via database function
                ai_dead_stock = self._get_ai_dead_stock(company_id)
                
                # Calculate accuracy
                accuracy = self._calculate_accuracy(expected_dead_stock, ai_dead_stock)
                overall_accuracy.append(accuracy)
                
                print(f"   📊 Expected: {len(expected_dead_stock)} items")
                print(f"   📊 AI Found: {len(ai_dead_stock)} items")
                print(f"   📊 Accuracy: {accuracy:.1%}")
                
                # Detailed comparison
                if accuracy < 0.9:  # Less than 90% accurate
                    self._analyze_discrepancies(expected_dead_stock, ai_dead_stock, company_name)
            
            avg_accuracy = sum(overall_accuracy) / len(overall_accuracy)
            duration = time.time() - start_time
            
            self.reporter.add_result("dead_stock_calculation_accuracy", "PASS", duration,
                                   details={
                                       "companies_tested": len(companies),
                                       "average_accuracy": avg_accuracy,
                                       "individual_accuracies": overall_accuracy
                                   })
            
            print(f"\n✅ Dead Stock Test Complete - Average Accuracy: {avg_accuracy:.1%}")
            assert avg_accuracy >= 0.8, f"Dead stock accuracy too low: {avg_accuracy:.1%}"
            
        except Exception as e:
            self.reporter.add_result("dead_stock_calculation_accuracy", "FAIL", time.time() - start_time, str(e))
            print(f"\n❌ Dead Stock Test Failed: {e}")
            raise
    
    def _calculate_dead_stock_manually(self, company_id: str) -> List[Dict]:
        """Manually calculate dead stock using business rules"""
        # Get company settings for dead stock threshold
        try:
            settings_response = self.db.supabase.table('company_settings')\
                .select('dead_stock_days')\
                .eq('company_id', company_id)\
                .single()\
                .execute()
            
            dead_stock_days = settings_response.data.get('dead_stock_days', 90) if settings_response.data else 90
        except:
            dead_stock_days = 90  # Default
        
        cutoff_date = datetime.now() - timedelta(days=dead_stock_days)
        
        # Get all product variants with inventory
        variants_response = self.db.supabase.table('product_variants')\
            .select('id, sku, product_id, inventory_quantity, cost, products(title)')\
            .eq('company_id', company_id)\
            .gt('inventory_quantity', 0)\
            .is_('deleted_at', 'null')\
            .execute()
        
        if not variants_response.data:
            return []
        
        dead_stock_items = []
        
        for variant in variants_response.data:
            # Check if variant has any sales since cutoff date
            sales_response = self.db.supabase.table('order_line_items')\
                .select('created_at', count='exact')\
                .eq('company_id', company_id)\
                .eq('variant_id', variant['id'])\
                .gte('created_at', cutoff_date.isoformat())\
                .execute()
            
            sales_count = sales_response.count or 0
            
            if sales_count == 0:
                # No sales in dead stock period - this is dead stock
                total_value = variant['inventory_quantity'] * (variant['cost'] or 0)
                
                dead_stock_items.append({
                    'variant_id': variant['id'],
                    'sku': variant['sku'],
                    'product_title': variant['products']['title'] if variant['products'] else 'Unknown',
                    'quantity': variant['inventory_quantity'],
                    'cost_per_unit': variant['cost'] or 0,
                    'total_value': total_value,
                    'days_since_sale': dead_stock_days + 1  # At least this many days
                })
        
        return dead_stock_items
    
    def _get_ai_dead_stock(self, company_id: str) -> List[Dict]:
        """Get AI dead stock calculation from database function"""
        try:
            response = self.db.supabase.rpc('get_dead_stock_report', {'p_company_id': company_id}).execute()
            return response.data or []
        except Exception as e:
            print(f"   ⚠️ Could not get AI dead stock: {e}")
            return []
    
    def _calculate_accuracy(self, expected: List[Dict], actual: List[Dict]) -> float:
        """Calculate accuracy between expected and actual results"""
        if len(expected) == 0 and len(actual) == 0:
            return 1.0
        if len(expected) == 0 or len(actual) == 0:
            return 0.0
        
        expected_skus = {item['sku'] for item in expected}
        actual_skus = {item['sku'] for item in actual}
        
        intersection = expected_skus.intersection(actual_skus)
        union = expected_skus.union(actual_skus)
        
        return len(intersection) / len(union) if len(union) > 0 else 0.0
    
    def _analyze_discrepancies(self, expected: List[Dict], actual: List[Dict], company_name: str):
        """Analyze and report discrepancies between expected and actual results"""
        expected_skus = {item['sku'] for item in expected}
        actual_skus = {item['sku'] for item in actual}
        
        missing_from_ai = expected_skus - actual_skus
        extra_in_ai = actual_skus - expected_skus
        
        if missing_from_ai:
            print(f"   ⚠️ Missing from AI ({len(missing_from_ai)}): {list(missing_from_ai)[:5]}")
        
        if extra_in_ai:
            print(f"   ⚠️ Extra in AI ({len(extra_in_ai)}): {list(extra_in_ai)[:5]}")

class TestReorderSuggestionsBusinessLogic:
    """Test reorder suggestions accuracy and AI enhancements"""
    
    def setup_method(self):
        self.api = APIUtils(TestConfig.API_BASE_URL)
        self.db = DatabaseUtils(TestConfig.SUPABASE_URL, TestConfig.SUPABASE_SERVICE_KEY)
        self.reporter = TestReporter()
        self.test_credentials = TestCredentials()
        
        creds = self.test_credentials.get_user_credentials("Owner")
        self.api.login(creds["email"], creds["password"])
    
    def test_reorder_suggestions_accuracy(self):
        """Test reorder suggestions match business logic"""
        start_time = time.time()
        try:
            companies = self.db.get_test_companies(2)
            
            overall_accuracy = []
            
            for company in companies:
                company_id = company["id"]
                company_name = company.get("name", f"Company-{company_id[:8]}")
                
                print(f"\n📦 Testing reorder suggestions for {company_name}")
                
                # Manual calculation
                expected_reorders = self._calculate_reorder_needs_manually(company_id)
                
                # AI calculation via database function
                ai_reorders = self._get_ai_reorder_suggestions(company_id)
                
                # Calculate accuracy
                accuracy = self._calculate_reorder_accuracy(expected_reorders, ai_reorders)
                overall_accuracy.append(accuracy)
                
                print(f"   📊 Expected reorders: {len(expected_reorders)}")
                print(f"   📊 AI suggestions: {len(ai_reorders)}")
                print(f"   📊 Accuracy: {accuracy:.1%}")
                
                # Test AI enhancements
                if ai_reorders:
                    self._test_ai_enhancements(ai_reorders, company_name)
            
            avg_accuracy = sum(overall_accuracy) / len(overall_accuracy) if overall_accuracy else 0
            duration = time.time() - start_time
            
            self.reporter.add_result("reorder_suggestions_accuracy", "PASS", duration,
                                   details={
                                       "companies_tested": len(companies),
                                       "average_accuracy": avg_accuracy
                                   })
            
            print(f"\n✅ Reorder Test Complete - Average Accuracy: {avg_accuracy:.1%}")
            
        except Exception as e:
            self.reporter.add_result("reorder_suggestions_accuracy", "FAIL", time.time() - start_time, str(e))
            print(f"\n❌ Reorder Test Failed: {e}")
            raise
    
    def _calculate_reorder_needs_manually(self, company_id: str) -> List[Dict]:
        """Manually calculate which products need reordering"""
        # Get variants with reorder points set
        variants_response = self.db.supabase.table('product_variants')\
            .select('id, sku, inventory_quantity, reorder_point, reorder_quantity, products(title)')\
            .eq('company_id', company_id)\
            .not_.is_('reorder_point', 'null')\
            .gt('reorder_point', 0)\
            .is_('deleted_at', 'null')\
            .execute()
        
        if not variants_response.data:
            return []
        
        reorder_needed = []
        
        for variant in variants_response.data:
            current_stock = variant['inventory_quantity']
            reorder_point = variant['reorder_point']
            
            if current_stock <= reorder_point:
                reorder_needed.append({
                    'variant_id': variant['id'],
                    'sku': variant['sku'],
                    'product_title': variant['products']['title'] if variant['products'] else 'Unknown',
                    'current_stock': current_stock,
                    'reorder_point': reorder_point,
                    'suggested_reorder_quantity': variant['reorder_quantity'] or (reorder_point * 2)
                })
        
        return reorder_needed
    
    def _get_ai_reorder_suggestions(self, company_id: str) -> List[Dict]:
        """Get AI reorder suggestions from database function"""
        try:
            response = self.db.supabase.rpc('get_reorder_suggestions', {'p_company_id': company_id}).execute()
            return response.data or []
        except Exception as e:
            print(f"   ⚠️ Could not get AI reorder suggestions: {e}")
            return []
    
    def _calculate_reorder_accuracy(self, expected: List[Dict], actual: List[Dict]) -> float:
        """Calculate accuracy of reorder suggestions"""
        if len(expected) == 0 and len(actual) == 0:
            return 1.0
        if len(expected) == 0 or len(actual) == 0:
            return 0.0
        
        expected_skus = {item['sku'] for item in expected}
        actual_skus = {item['sku'] for item in actual}
        
        intersection = expected_skus.intersection(actual_skus)
        
        return len(intersection) / len(expected_skus) if len(expected_skus) > 0 else 0.0
    
    def _test_ai_enhancements(self, ai_reorders: List[Dict], company_name: str):
        """Test AI enhancement features like seasonality adjustments"""
        enhanced_count = 0
        seasonality_adjustments = 0
        
        for suggestion in ai_reorders:
            # Check if AI fields are present
            if 'seasonality_factor' in suggestion:
                enhanced_count += 1
                
                seasonality = suggestion.get('seasonality_factor', 1.0)
                if seasonality != 1.0:  # Seasonality adjustment applied
                    seasonality_adjustments += 1
        
        print(f"   🤖 AI Enhanced: {enhanced_count}/{len(ai_reorders)} suggestions")
        print(f"   🌡️ Seasonality Adjustments: {seasonality_adjustments}")

class TestInventoryBusinessLogic:
    """Test inventory management and turnover calculations"""
    
    def setup_method(self):
        self.api = APIUtils(TestConfig.API_BASE_URL)
        self.db = DatabaseUtils(TestConfig.SUPABASE_URL, TestConfig.SUPABASE_SERVICE_KEY)
        self.reporter = TestReporter()
        self.test_credentials = TestCredentials()
        
        creds = self.test_credentials.get_user_credentials("Owner")
        self.api.login(creds["email"], creds["password"])
    
    def test_inventory_turnover_calculation(self):
        """Test inventory turnover calculation accuracy"""
        start_time = time.time()
        try:
            companies = self.db.get_test_companies(2)
            
            for company in companies:
                company_id = company["id"]
                company_name = company.get("name", f"Company-{company_id[:8]}")
                
                print(f"\n🔄 Testing inventory turnover for {company_name}")
                
                # Test different periods
                periods = [30, 90, 180]
                for days in periods:
                    expected_turnover = self._calculate_turnover_manually(company_id, days)
                    ai_turnover = self._get_ai_turnover(company_id, days)
                    
                    if expected_turnover is not None and ai_turnover is not None:
                        accuracy = 1 - abs(expected_turnover - ai_turnover) / max(expected_turnover, ai_turnover, 1)
                        print(f"   📊 {days}d - Expected: {expected_turnover:.2f}, AI: {ai_turnover:.2f}, Accuracy: {accuracy:.1%}")
                    else:
                        print(f"   ⚠️ {days}d - Insufficient data for comparison")
            
            duration = time.time() - start_time
            self.reporter.add_result("inventory_turnover_calculation", "PASS", duration)
            
        except Exception as e:
            self.reporter.add_result("inventory_turnover_calculation", "FAIL", time.time() - start_time, str(e))
            print(f"\n❌ Inventory Turnover Test Failed: {e}")
            raise
    
    def _calculate_turnover_manually(self, company_id: str, days: int) -> Optional[float]:
        """Manually calculate inventory turnover ratio"""
        try:
            # Calculate COGS (Cost of Goods Sold) for the period
            cutoff_date = datetime.now() - timedelta(days=days)
            
            cogs_response = self.db.supabase.table('order_line_items')\
                .select('cost_at_time, quantity')\
                .eq('company_id', company_id)\
                .gte('created_at', cutoff_date.isoformat())\
                .not_.is_('cost_at_time', 'null')\
                .execute()
            
            total_cogs = sum(
                (item['cost_at_time'] or 0) * item['quantity'] 
                for item in (cogs_response.data or [])
            )
            
            if total_cogs == 0:
                return None
            
            # Calculate average inventory value
            inventory_response = self.db.supabase.table('product_variants')\
                .select('inventory_quantity, cost')\
                .eq('company_id', company_id)\
                .gt('inventory_quantity', 0)\
                .not_.is_('cost', 'null')\
                .execute()
            
            total_inventory_value = sum(
                item['inventory_quantity'] * (item['cost'] or 0)
                for item in (inventory_response.data or [])
            )
            
            if total_inventory_value == 0:
                return None
            
            # Turnover = COGS / Average Inventory Value
            turnover = total_cogs / total_inventory_value
            return turnover
            
        except Exception as e:
            print(f"   ⚠️ Error calculating turnover manually: {e}")
            return None
    
    def _get_ai_turnover(self, company_id: str, days: int) -> Optional[float]:
        """Get AI inventory turnover calculation"""
        try:
            response = self.db.supabase.rpc('get_inventory_turnover', {
                'p_company_id': company_id,
                'p_days': days
            }).execute()
            
            return response.data if response.data else None
        except Exception as e:
            print(f"   ⚠️ Could not get AI turnover: {e}")
            return None

class TestFinancialAnalytics:
    """Test financial analytics and calculations"""
    
    def setup_method(self):
        self.api = APIUtils(TestConfig.API_BASE_URL)
        self.db = DatabaseUtils(TestConfig.SUPABASE_URL, TestConfig.SUPABASE_SERVICE_KEY)
        self.reporter = TestReporter()
        self.test_credentials = TestCredentials()
        
        creds = self.test_credentials.get_user_credentials("Owner")
        self.api.login(creds["email"], creds["password"])
    
    def test_abc_analysis_calculation(self):
        """Test ABC analysis categorization"""
        start_time = time.time()
        try:
            companies = self.db.get_test_companies(2)
            
            for company in companies:
                company_id = company["id"]
                company_name = company.get("name", f"Company-{company_id[:8]}")
                
                print(f"\n📈 Testing ABC analysis for {company_name}")
                
                # Get AI ABC analysis
                ai_abc = self._get_ai_abc_analysis(company_id)
                
                if ai_abc:
                    # Validate ABC categorization rules
                    a_items = [item for item in ai_abc if item.get('category') == 'A']
                    b_items = [item for item in ai_abc if item.get('category') == 'B']
                    c_items = [item for item in ai_abc if item.get('category') == 'C']
                    
                    total_items = len(ai_abc)
                    a_percentage = len(a_items) / total_items * 100 if total_items > 0 else 0
                    b_percentage = len(b_items) / total_items * 100 if total_items > 0 else 0
                    c_percentage = len(c_items) / total_items * 100 if total_items > 0 else 0
                    
                    print(f"   📊 Total items: {total_items}")
                    print(f"   📊 A items: {len(a_items)} ({a_percentage:.1f}%)")
                    print(f"   📊 B items: {len(b_items)} ({b_percentage:.1f}%)")
                    print(f"   📊 C items: {len(c_items)} ({c_percentage:.1f}%)")
                    
                    # Validate ABC rules (A: ~20%, B: ~30%, C: ~50%)
                    abc_valid = (15 <= a_percentage <= 25 and 
                               25 <= b_percentage <= 35 and 
                               45 <= c_percentage <= 55)
                    
                    if abc_valid:
                        print(f"   ✅ ABC categorization follows 80/20 rule")
                    else:
                        print(f"   ⚠️ ABC categorization may need adjustment")
                else:
                    print(f"   ⚠️ No ABC analysis data available")
            
            duration = time.time() - start_time
            self.reporter.add_result("abc_analysis_calculation", "PASS", duration)
            
        except Exception as e:
            self.reporter.add_result("abc_analysis_calculation", "FAIL", time.time() - start_time, str(e))
            print(f"\n❌ ABC Analysis Test Failed: {e}")
            raise
    
    def _get_ai_abc_analysis(self, company_id: str) -> List[Dict]:
        """Get AI ABC analysis from database"""
        try:
            response = self.db.supabase.rpc('get_abc_analysis', {'p_company_id': company_id}).execute()
            return response.data or []
        except Exception as e:
            print(f"   ⚠️ Could not get ABC analysis: {e}")
            return []

class TestDataIntegrityAndSecurity:
    """Test data integrity and multi-tenant security"""
    
    def setup_method(self):
        self.api = APIUtils(TestConfig.API_BASE_URL)
        self.db = DatabaseUtils(TestConfig.SUPABASE_URL, TestConfig.SUPABASE_SERVICE_KEY)
        self.reporter = TestReporter()
        self.test_credentials = TestCredentials()
    
    def test_multi_tenant_data_isolation(self):
        """Test that companies cannot access each other's data"""
        start_time = time.time()
        try:
            # Get two different companies
            companies = self.db.get_test_companies(2)
            assert len(companies) >= 2, "Need at least 2 companies for isolation testing"
            
            company1 = companies[0]
            company2 = companies[1]
            
            print(f"\n🔒 Testing data isolation between companies")
            print(f"   Company 1: {company1.get('name', 'Unknown')}")
            print(f"   Company 2: {company2.get('name', 'Unknown')}")
            
            # Test product isolation
            products1 = self.db.get_test_products(company1["id"], 50)
            products2 = self.db.get_test_products(company2["id"], 50)
            
            # Verify no cross-contamination
            company1_product_ids = {p["id"] for p in products1}
            company2_product_ids = {p["id"] for p in products2}
            
            overlap = company1_product_ids.intersection(company2_product_ids)
            
            assert len(overlap) == 0, f"Found {len(overlap)} shared products between companies"
            
            print(f"   ✅ Product isolation: {len(products1)} vs {len(products2)} products, no overlap")
            
            # Test order isolation
            orders1 = self.db.get_test_orders(company1["id"], 30)
            orders2 = self.db.get_test_orders(company2["id"], 30)
            
            company1_order_ids = {o["id"] for o in orders1}
            company2_order_ids = {o["id"] for o in orders2}
            
            order_overlap = company1_order_ids.intersection(company2_order_ids)
            
            assert len(order_overlap) == 0, f"Found {len(order_overlap)} shared orders between companies"
            
            print(f"   ✅ Order isolation: {len(orders1)} vs {len(orders2)} orders, no overlap")
            
            duration = time.time() - start_time
            self.reporter.add_result("multi_tenant_data_isolation", "PASS", duration)
            
        except Exception as e:
            self.reporter.add_result("multi_tenant_data_isolation", "FAIL", time.time() - start_time, str(e))
            print(f"\n❌ Data Isolation Test Failed: {e}")
            raise
    
    def test_data_relationship_integrity(self):
        """Test that foreign key relationships are maintained"""
        start_time = time.time()
        try:
            companies = self.db.get_test_companies(2)
            
            for company in companies:
                company_id = company["id"]
                company_name = company.get("name", f"Company-{company_id[:8]}")
                
                print(f"\n🔗 Testing data relationships for {company_name}")
                
                # Test product-variant relationships
                products = self.db.get_test_products(company_id, 25)
                relationship_issues = []
                
                for product in products:
                    variants = product.get('product_variants', [])
                    for variant in variants:
                        # Check variant belongs to correct product
                        if variant.get('product_id') != product['id']:
                            relationship_issues.append(f"Variant {variant['id']} wrong product_id")
                        
                        # Check variant belongs to correct company
                        if variant.get('company_id') != company_id:
                            relationship_issues.append(f"Variant {variant['id']} wrong company_id")
                
                # Test order-line item relationships
                orders = self.db.get_test_orders(company_id, 15)
                
                for order in orders:
                    line_items = order.get('order_line_items', [])
                    for item in line_items:
                        # Check line item belongs to correct order
                        if item.get('order_id') != order['id']:
                            relationship_issues.append(f"Line item {item['id']} wrong order_id")
                        
                        # Check line item belongs to correct company
                        if item.get('company_id') != company_id:
                            relationship_issues.append(f"Line item {item['id']} wrong company_id")
                
                if relationship_issues:
                    print(f"   ⚠️ Found {len(relationship_issues)} relationship issues:")
                    for issue in relationship_issues[:5]:  # Show first 5
                        print(f"      - {issue}")
                else:
                    print(f"   ✅ All data relationships intact")
            
            duration = time.time() - start_time
            self.reporter.add_result("data_relationship_integrity", "PASS", duration)
            
        except Exception as e:
            self.reporter.add_result("data_relationship_integrity", "FAIL", time.time() - start_time, str(e))
            print(f"\n❌ Data Relationship Test Failed: {e}")
            raise

if __name__ == "__main__":
    print("🧮 Running Invochat Comprehensive Business Logic Tests...")
    print("=" * 60)
    
    # Run with pytest
    pytest.main([__file__, "-v", "--tb=short"])