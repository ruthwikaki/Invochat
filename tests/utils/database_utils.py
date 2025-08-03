# utils/database_utils.py (enhanced)
#!/usr/bin/env python3
"""
Enhanced database utility functions for comprehensive testing
"""

from supabase import create_client, Client
from typing import Dict, List, Any, Optional
import json
from datetime import datetime, timedelta

class DatabaseUtils:
    """Enhanced database utility functions for testing"""
    
    def __init__(self, supabase_url: str, supabase_key: str):
        self.supabase: Client = create_client(supabase_url, supabase_key)
        print("🗄️ Database connection established")
    
    def get_test_companies(self, limit: int = 5) -> List[Dict]:
        """Get test companies from database"""
        try:
            response = self.supabase.table('companies')\
                .select('*')\
                .order('created_at', desc=True)\
                .limit(limit)\
                .execute()
            
            companies = response.data or []
            print(f"📊 Found {len(companies)} companies")
            return companies
        except Exception as e:
            print(f"⚠️ Error fetching companies: {e}")
            return []
    
    def get_test_products(self, company_id: str, limit: int = 50) -> List[Dict]:
        """Get test products with variants for a company"""
        try:
            response = self.supabase.table('products')\
                .select('*, product_variants(*)')\
                .eq('company_id', company_id)\
                .is_('deleted_at', 'null')\
                .order('created_at', desc=True)\
                .limit(limit)\
                .execute()
            
            products = response.data or []
            total_variants = sum(len(p.get('product_variants', [])) for p in products)
            print(f"📦 Found {len(products)} products with {total_variants} variants for company {company_id[:8]}")
            return products
        except Exception as e:
            print(f"⚠️ Error fetching products: {e}")
            return []
    
    def get_test_orders(self, company_id: str, limit: int = 30) -> List[Dict]:
        """Get test orders with line items for a company"""
        try:
            response = self.supabase.table('orders')\
                .select('*, order_line_items(*)')\
                .eq('company_id', company_id)\
                .order('created_at', desc=True)\
                .limit(limit)\
                .execute()
            
            orders = response.data or []
            total_line_items = sum(len(o.get('order_line_items', [])) for o in orders)
            total_revenue = sum(o.get('total_amount', 0) for o in orders)
            print(f"🛒 Found {len(orders)} orders with {total_line_items} line items, total revenue: ${total_revenue/100:.2f}")
            return orders
        except Exception as e:
            print(f"⚠️ Error fetching orders: {e}")
            return []
    
    def get_test_customers(self, company_id: str, limit: int = 25) -> List[Dict]:
        """Get test customers for a company"""
        try:
            response = self.supabase.table('customers')\
                .select('*')\
                .eq('company_id', company_id)\
                .is_('deleted_at', 'null')\
                .order('created_at', desc=True)\
                .limit(limit)\
                .execute()
            
            customers = response.data or []
            total_spent = sum(c.get('total_spent', 0) for c in customers)
            print(f"👥 Found {len(customers)} customers, total spent: ${total_spent/100:.2f}")
            return customers
        except Exception as e:
            print(f"⚠️ Error fetching customers: {e}")
            return []
    
    def get_test_suppliers(self, company_id: str, limit: int = 15) -> List[Dict]:
        """Get test suppliers for a company"""
        try:
            response = self.supabase.table('suppliers')\
                .select('*')\
                .eq('company_id', company_id)\
                .order('created_at', desc=True)\
                .limit(limit)\
                .execute()
            
            suppliers = response.data or []
            print(f"🏭 Found {len(suppliers)} suppliers")
            return suppliers
        except Exception as e:
            print(f"⚠️ Error fetching suppliers: {e}")
            return []
    
    def get_inventory_summary(self, company_id: str) -> Dict:
        """Get inventory summary statistics"""
        try:
            # Get total inventory value and count
            inventory_response = self.supabase.table('product_variants')\
                .select('inventory_quantity, cost')\
                .eq('company_id', company_id)\
                .gt('inventory_quantity', 0)\
                .not_.is_('cost', 'null')\
                .execute()
            
            variants = inventory_response.data or []
            
            total_units = sum(v['inventory_quantity'] for v in variants)
            total_value = sum(v['inventory_quantity'] * (v['cost'] or 0) for v in variants)
            
            # Get low stock count (assuming reorder point exists)
            low_stock_response = self.supabase.table('product_variants')\
                .select('id')\
                .eq('company_id', company_id)\
                .filter('inventory_quantity', 'lte', 'reorder_point')\
                .not_.is_('reorder_point', 'null')\
                .execute()
            
            low_stock_count = len(low_stock_response.data or [])
            
            # Get out of stock count
            out_of_stock_response = self.supabase.table('product_variants')\
                .select('id')\
                .eq('company_id', company_id)\
                .eq('inventory_quantity', 0)\
                .execute()
            
            out_of_stock_count = len(out_of_stock_response.data or [])
            
            summary = {
                'total_products': len(variants),
                'total_units': total_units,
                'total_value': total_value,
                'low_stock_count': low_stock_count,
                'out_of_stock_count': out_of_stock_count,
                'average_unit_cost': total_value / total_units if total_units > 0 else 0
            }
            
            print(f"📊 Inventory summary: {summary['total_products']} products, ${summary['total_value']/100:.2f} value")
            return summary
            
        except Exception as e:
            print(f"⚠️ Error getting inventory summary: {e}")
            return {}
    
    def get_sales_summary(self, company_id: str, days: int = 30) -> Dict:
        """Get sales summary for specified period"""
        try:
            cutoff_date = datetime.now() - timedelta(days=days)
            
            # Get orders in period
            orders_response = self.supabase.table('orders')\
                .select('total_amount, created_at, financial_status')\
                .eq('company_id', company_id)\
                .gte('created_at', cutoff_date.isoformat())\
                .execute()
            
            orders = orders_response.data or []
            
            total_revenue = sum(o['total_amount'] for o in orders if o.get('financial_status') == 'paid')
            total_orders = len(orders)
            paid_orders = len([o for o in orders if o.get('financial_status') == 'paid'])
            
            # Get top selling products
            line_items_response = self.supabase.table('order_line_items')\
                .select('product_name, quantity, price')\
                .eq('company_id', company_id)\
                .gte('created_at', cutoff_date.isoformat())\
                .execute()
            
            line_items = line_items_response.data or []
            
            # Aggregate by product
            product_sales = {}
            for item in line_items:
                product_name = item['product_name']
                if product_name not in product_sales:
                    product_sales[product_name] = {'quantity': 0, 'revenue': 0}
                
                product_sales[product_name]['quantity'] += item['quantity']
                product_sales[product_name]['revenue'] += item['quantity'] * item['price']
            
            # Sort by revenue
            top_products = sorted(product_sales.items(), 
                                key=lambda x: x[1]['revenue'], 
                                reverse=True)[:5]
            
            summary = {
                'period_days': days,
                'total_orders': total_orders,
                'paid_orders': paid_orders,
                'total_revenue': total_revenue,
                'average_order_value': total_revenue / paid_orders if paid_orders > 0 else 0,
                'top_products': top_products
            }
            
            print(f"💰 Sales summary ({days}d): {total_orders} orders, ${total_revenue/100:.2f} revenue")
            return summary
            
        except Exception as e:
            print(f"⚠️ Error getting sales summary: {e}")
            return {}
    
    def get_conversation_summary(self, company_id: str) -> Dict:
        """Get AI conversation summary"""
        try:
            # Get conversations count
            conversations_response = self.supabase.table('conversations')\
                .select('id, created_at')\
                .eq('company_id', company_id)\
                .execute()
            
            conversations = conversations_response.data or []
            
            # Get messages count
            messages_response = self.supabase.table('messages')\
                .select('id, role, created_at')\
                .eq('company_id', company_id)\
                .execute()
            
            messages = messages_response.data or []
            
            user_messages = [m for m in messages if m['role'] == 'user']
            assistant_messages = [m for m in messages if m['role'] == 'assistant']
            
            # Recent activity (last 7 days)
            recent_cutoff = datetime.now() - timedelta(days=7)
            recent_conversations = [c for c in conversations 
                                  if datetime.fromisoformat(c['created_at'].replace('Z', '+00:00')) >= recent_cutoff]
            
            summary = {
                'total_conversations': len(conversations),
                'total_messages': len(messages),
                'user_messages': len(user_messages),
                'assistant_messages': len(assistant_messages),
                'recent_conversations': len(recent_conversations),
                'avg_messages_per_conversation': len(messages) / len(conversations) if conversations else 0
            }
            
            print(f"💬 Conversation summary: {summary['total_conversations']} conversations, {summary['total_messages']} messages")
            return summary
            
        except Exception as e:
            print(f"⚠️ Error getting conversation summary: {e}")
            return {}
    
    def test_database_functions(self, company_id: str) -> Dict:
        """Test various database functions and return results"""
        print(f"\n🧪 Testing database functions for company {company_id[:8]}")
        
        function_results = {}
        
        # Test dead stock function
        try:
            dead_stock_response = self.supabase.rpc('get_dead_stock_report', {
                'p_company_id': company_id
            }).execute()
            
            dead_stock_data = dead_stock_response.data or []
            function_results['dead_stock'] = {
                'success': True,
                'count': len(dead_stock_data),
                'total_value': sum(item.get('total_value', 0) for item in dead_stock_data)
            }
            print(f"   ✅ Dead stock function: {len(dead_stock_data)} items")
            
        except Exception as e:
            function_results['dead_stock'] = {'success': False, 'error': str(e)}
            print(f"   ❌ Dead stock function failed: {e}")
        
        # Test reorder suggestions function
        try:
            reorder_response = self.supabase.rpc('get_reorder_suggestions', {
                'p_company_id': company_id
            }).execute()
            
            reorder_data = reorder_response.data or []
            function_results['reorder_suggestions'] = {
                'success': True,
                'count': len(reorder_data),
                'total_suggested_quantity': sum(item.get('suggested_reorder_quantity', 0) for item in reorder_data)
            }
            print(f"   ✅ Reorder suggestions function: {len(reorder_data)} suggestions")
            
        except Exception as e:
            function_results['reorder_suggestions'] = {'success': False, 'error': str(e)}
            print(f"   ❌ Reorder suggestions function failed: {e}")
        
        # Test dashboard metrics function
        try:
            dashboard_response = self.supabase.rpc('get_dashboard_metrics', {
                'p_company_id': company_id,
                'p_days': 30
            }).execute()
            
            dashboard_data = dashboard_response.data
            function_results['dashboard_metrics'] = {
                'success': True,
                'has_data': dashboard_data is not None,
                'revenue': dashboard_data.get('total_revenue', 0) if dashboard_data else 0
            }
            print(f"   ✅ Dashboard metrics function: Revenue ${dashboard_data.get('total_revenue', 0)/100:.2f}" if dashboard_data else "   ✅ Dashboard metrics function: No data")
            
        except Exception as e:
            function_results['dashboard_metrics'] = {'success': False, 'error': str(e)}
            print(f"   ❌ Dashboard metrics function failed: {e}")
        
        # Test inventory analytics function
        try:
            inventory_response = self.supabase.rpc('get_inventory_analytics', {
                'p_company_id': company_id
            }).execute()
            
            inventory_data = inventory_response.data
            function_results['inventory_analytics'] = {
                'success': True,
                'has_data': inventory_data is not None,
                'total_value': inventory_data.get('total_inventory_value', 0) if inventory_data else 0
            }
            print(f"   ✅ Inventory analytics function: ${inventory_data.get('total_inventory_value', 0)/100:.2f}" if inventory_data else "   ✅ Inventory analytics function: No data")
            
        except Exception as e:
            function_results['inventory_analytics'] = {'success': False, 'error': str(e)}
            print(f"   ❌ Inventory analytics function failed: {e}")
        
        # Test sales analytics function
        try:
            sales_response = self.supabase.rpc('get_sales_analytics', {
                'p_company_id': company_id
            }).execute()
            
            sales_data = sales_response.data
            function_results['sales_analytics'] = {
                'success': True,
                'has_data': sales_data is not None,
                'daily_sales_count': len(sales_data.get('daily_sales', [])) if sales_data else 0
            }
            print(f"   ✅ Sales analytics function: {len(sales_data.get('daily_sales', [])) if sales_data else 0} daily records")
            
        except Exception as e:
            function_results['sales_analytics'] = {'success': False, 'error': str(e)}
            print(f"   ❌ Sales analytics function failed: {e}")
        
        # Test customer analytics function
        try:
            customer_response = self.supabase.rpc('get_customer_analytics', {
                'p_company_id': company_id
            }).execute()
            
            customer_data = customer_response.data
            function_results['customer_analytics'] = {
                'success': True,
                'has_data': customer_data is not None,
                'total_customers': customer_data.get('total_customers', 0) if customer_data else 0
            }
            print(f"   ✅ Customer analytics function: {customer_data.get('total_customers', 0) if customer_data else 0} customers")
            
        except Exception as e:
            function_results['customer_analytics'] = {'success': False, 'error': str(e)}
            print(f"   ❌ Customer analytics function failed: {e}")
        
        # Test supplier performance function
        try:
            supplier_response = self.supabase.rpc('get_supplier_performance_report', {
                'p_company_id': company_id
            }).execute()
            
            supplier_data = supplier_response.data or []
            function_results['supplier_performance'] = {
                'success': True,
                'count': len(supplier_data)
            }
            print(f"   ✅ Supplier performance function: {len(supplier_data)} suppliers")
            
        except Exception as e:
            function_results['supplier_performance'] = {'success': False, 'error': str(e)}
            print(f"   ❌ Supplier performance function failed: {e}")
        
        # Test inventory turnover function
        try:
            turnover_response = self.supabase.rpc('get_inventory_turnover', {
                'p_company_id': company_id,
                'p_days': 90
            }).execute()
            
            turnover_data = turnover_response.data
            function_results['inventory_turnover'] = {
                'success': True,
                'turnover_rate': turnover_data if turnover_data else 0
            }
            print(f"   ✅ Inventory turnover function: {turnover_data:.2f}" if turnover_data else "   ✅ Inventory turnover function: No data")
            
        except Exception as e:
            function_results['inventory_turnover'] = {'success': False, 'error': str(e)}
            print(f"   ❌ Inventory turnover function failed: {e}")
        
        # Test ABC analysis function
        try:
            abc_response = self.supabase.rpc('get_abc_analysis', {
                'p_company_id': company_id
            }).execute()
            
            abc_data = abc_response.data or []
            function_results['abc_analysis'] = {
                'success': True,
                'count': len(abc_data)
            }
            print(f"   ✅ ABC analysis function: {len(abc_data)} products categorized")
            
        except Exception as e:
            function_results['abc_analysis'] = {'success': False, 'error': str(e)}
            print(f"   ❌ ABC analysis function failed: {e}")
        
        # Test historical sales function
        try:
            # Get some SKUs first
            variants_response = self.supabase.table('product_variants')\
                .select('sku')\
                .eq('company_id', company_id)\
                .not_.is_('sku', 'null')\
                .limit(5)\
                .execute()
            
            skus = [v['sku'] for v in (variants_response.data or [])]
            
            if skus:
                historical_response = self.supabase.rpc('get_historical_sales_for_skus', {
                    'p_company_id': company_id,
                    'p_skus': skus
                }).execute()
                
                historical_data = historical_response.data or []
                function_results['historical_sales'] = {
                    'success': True,
                    'count': len(historical_data),
                    'skus_tested': len(skus)
                }
                print(f"   ✅ Historical sales function: {len(historical_data)} SKU records")
            else:
                function_results['historical_sales'] = {
                    'success': True,
                    'count': 0,
                    'skus_tested': 0
                }
                print(f"   ⚠️ Historical sales function: No SKUs to test")
            
        except Exception as e:
            function_results['historical_sales'] = {'success': False, 'error': str(e)}
            print(f"   ❌ Historical sales function failed: {e}")
        
        # Test demand forecast function
        try:
            forecast_response = self.supabase.rpc('forecast_demand', {
                'p_company_id': company_id
            }).execute()
            
            forecast_data = forecast_response.data or []
            function_results['demand_forecast'] = {
                'success': True,
                'count': len(forecast_data)
            }
            print(f"   ✅ Demand forecast function: {len(forecast_data)} products forecasted")
            
        except Exception as e:
            function_results['demand_forecast'] = {'success': False, 'error': str(e)}
            print(f"   ❌ Demand forecast function failed: {e}")
        
        # Test gross margin analysis function
        try:
            margin_response = self.supabase.rpc('get_gross_margin_analysis', {
                'p_company_id': company_id
            }).execute()
            
            margin_data = margin_response.data or []
            function_results['gross_margin_analysis'] = {
                'success': True,
                'count': len(margin_data)
            }
            print(f"   ✅ Gross margin analysis function: {len(margin_data)} products analyzed")
            
        except Exception as e:
            function_results['gross_margin_analysis'] = {'success': False, 'error': str(e)}
            print(f"   ❌ Gross margin analysis function failed: {e}")
        
        return function_results
    
    def validate_data_integrity(self, company_id: str) -> Dict:
        """Validate data integrity and relationships"""
        print(f"\n🔍 Validating data integrity for company {company_id[:8]}")
        
        integrity_results = {
            'checks_performed': 0,
            'checks_passed': 0,
            'issues_found': []
        }
        
        # Check product-variant relationships
        try:
            products_response = self.supabase.table('products')\
                .select('id, company_id')\
                .eq('company_id', company_id)\
                .execute()
            
            products = products_response.data or []
            
            for product in products[:10]:  # Check first 10 products
                variants_response = self.supabase.table('product_variants')\
                    .select('id, product_id, company_id')\
                    .eq('product_id', product['id'])\
                    .execute()
                
                variants = variants_response.data or []
                
                integrity_results['checks_performed'] += 1
                
                # Check if variants belong to correct product and company
                invalid_variants = [
                    v for v in variants 
                    if v['product_id'] != product['id'] or v['company_id'] != company_id
                ]
                
                if invalid_variants:
                    integrity_results['issues_found'].append(
                        f"Product {product['id'][:8]} has {len(invalid_variants)} variants with wrong references"
                    )
                else:
                    integrity_results['checks_passed'] += 1
            
            print(f"   ✅ Product-variant relationships: {len(products)} products checked")
            
        except Exception as e:
            integrity_results['issues_found'].append(f"Product-variant check failed: {e}")
            print(f"   ❌ Product-variant relationship check failed: {e}")
        
        # Check order-line item relationships
        try:
            orders_response = self.supabase.table('orders')\
                .select('id, company_id')\
                .eq('company_id', company_id)\
                .limit(10)\
                .execute()
            
            orders = orders_response.data or []
            
            for order in orders:
                line_items_response = self.supabase.table('order_line_items')\
                    .select('id, order_id, company_id')\
                    .eq('order_id', order['id'])\
                    .execute()
                
                line_items = line_items_response.data or []
                
                integrity_results['checks_performed'] += 1
                
                # Check if line items belong to correct order and company
                invalid_items = [
                    item for item in line_items 
                    if item['order_id'] != order['id'] or item['company_id'] != company_id
                ]
                
                if invalid_items:
                    integrity_results['issues_found'].append(
                        f"Order {order['id'][:8]} has {len(invalid_items)} line items with wrong references"
                    )
                else:
                    integrity_results['checks_passed'] += 1
            
            print(f"   ✅ Order-line item relationships: {len(orders)} orders checked")
            
        except Exception as e:
            integrity_results['issues_found'].append(f"Order-line item check failed: {e}")
            print(f"   ❌ Order-line item relationship check failed: {e}")
        
        # Check customer order relationships
        try:
            customers_response = self.supabase.table('customers')\
                .select('id, company_id, total_orders')\
                .eq('company_id', company_id)\
                .limit(10)\
                .execute()
            
            customers = customers_response.data or []
            
            for customer in customers:
                # Count actual orders for customer
                actual_orders_response = self.supabase.table('orders')\
                    .select('id')\
                    .eq('customer_id', customer['id'])\
                    .eq('company_id', company_id)\
                    .execute()
                
                actual_order_count = len(actual_orders_response.data or [])
                recorded_order_count = customer.get('total_orders', 0)
                
                integrity_results['checks_performed'] += 1
                
                if actual_order_count != recorded_order_count:
                    integrity_results['issues_found'].append(
                        f"Customer {customer['id'][:8]} order count mismatch: recorded {recorded_order_count}, actual {actual_order_count}"
                    )
                else:
                    integrity_results['checks_passed'] += 1
            
            print(f"   ✅ Customer-order relationships: {len(customers)} customers checked")
            
        except Exception as e:
            integrity_results['issues_found'].append(f"Customer-order check failed: {e}")
            print(f"   ❌ Customer-order relationship check failed: {e}")
        
        # Calculate integrity score
        integrity_score = (integrity_results['checks_passed'] / integrity_results['checks_performed'] * 100) if integrity_results['checks_performed'] > 0 else 0
        integrity_results['integrity_score'] = integrity_score
        
        print(f"   📊 Data integrity score: {integrity_score:.1f}% ({integrity_results['checks_passed']}/{integrity_results['checks_performed']} checks passed)")
        
        if integrity_results['issues_found']:
            print(f"   ⚠️ Issues found:")
            for issue in integrity_results['issues_found'][:5]:  # Show first 5 issues
                print(f"      - {issue}")
        
        return integrity_results
    
    def get_company_statistics(self, company_id: str) -> Dict:
        """Get comprehensive company statistics"""
        print(f"\n📈 Generating statistics for company {company_id[:8]}")
        
        stats = {}
        
        try:
            # Basic counts
            tables_to_count = [
                'products', 'product_variants', 'orders', 'order_line_items',
                'customers', 'suppliers', 'conversations', 'messages'
            ]
            
            for table in tables_to_count:
                try:
                    response = self.supabase.table(table)\
                        .select('id', count='exact')\
                        .eq('company_id', company_id)\
                        .execute()
                    
                    stats[f'{table}_count'] = response.count or 0
                except Exception as e:
                    stats[f'{table}_count'] = 0
                    print(f"   ⚠️ Could not count {table}: {e}")
            
            # Calculate derived statistics
            stats['products_per_supplier'] = (stats['products_count'] / stats['suppliers_count']) if stats['suppliers_count'] > 0 else 0
            stats['variants_per_product'] = (stats['product_variants_count'] / stats['products_count']) if stats['products_count'] > 0 else 0
            stats['line_items_per_order'] = (stats['order_line_items_count'] / stats['orders_count']) if stats['orders_count'] > 0 else 0
            stats['messages_per_conversation'] = (stats['messages_count'] / stats['conversations_count']) if stats['conversations_count'] > 0 else 0
            
            # Revenue statistics
            revenue_response = self.supabase.table('orders')\
                .select('total_amount, financial_status')\
                .eq('company_id', company_id)\
                .execute()
            
            orders = revenue_response.data or []
            paid_orders = [o for o in orders if o.get('financial_status') == 'paid']
            
            stats['total_revenue'] = sum(o['total_amount'] for o in paid_orders)
            stats['average_order_value'] = (stats['total_revenue'] / len(paid_orders)) if paid_orders else 0
            
            # Inventory value
            inventory_response = self.supabase.table('product_variants')\
                .select('inventory_quantity, cost')\
                .eq('company_id', company_id)\
                .gt('inventory_quantity', 0)\
                .not_.is_('cost', 'null')\
                .execute()
            
            variants = inventory_response.data or []
            stats['total_inventory_value'] = sum(v['inventory_quantity'] * (v['cost'] or 0) for v in variants)
            stats['total_inventory_units'] = sum(v['inventory_quantity'] for v in variants)
            
            print(f"   📊 Company statistics generated:")
            print(f"      Products: {stats['products_count']}")
            print(f"      Orders: {stats['orders_count']}")
            print(f"      Revenue: ${stats['total_revenue']/100:.2f}")
            print(f"      Inventory Value: ${stats['total_inventory_value']/100:.2f}")
            
            return stats
            
        except Exception as e:
            print(f"   ❌ Error generating statistics: {e}")
            return {}

print("✅ Enhanced database utilities loaded")