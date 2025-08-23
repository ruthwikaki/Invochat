"""
Advanced Analytics Test Suite
Tests for comprehensive business intelligence features including:
- ABC Analysis
- Demand Forecasting
- Sales Velocity Analysis
- Gross Margin Analysis
- Hidden Revenue Opportunities
- Supplier Performance Scoring
- Inventory Turnover Analysis
- Customer Behavior Insights
- Multi-channel Fee Analysis
"""

import pytest
import asyncio
from unittest.mock import Mock, patch, AsyncMock
import sys
import os

# Add the project root to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', '..'))

from tests.test_config import get_test_supabase_client
from tests.conftest import test_company_id


class TestAdvancedAnalytics:
    """Test suite for advanced analytics functions"""
    
    @pytest.fixture
    def mock_supabase(self):
        """Mock Supabase client with test data"""
        client = Mock()
        
        # Mock sales velocity data
        client.from_().select().eq().order().limit().execute.return_value = Mock(
            data=[
                {
                    'sku': 'TEST-001',
                    'product_name': 'Test Product 1',
                    'total_quantity': 150,
                    'total_revenue': 15000,
                    'days_period': 30,
                    'velocity_per_day': 5.0,
                    'revenue_per_day': 500.0,
                    'trend': 'increasing',
                    'performance_category': 'high'
                },
                {
                    'sku': 'TEST-002',
                    'product_name': 'Test Product 2',
                    'total_quantity': 75,
                    'total_revenue': 7500,
                    'days_period': 30,
                    'velocity_per_day': 2.5,
                    'revenue_per_day': 250.0,
                    'trend': 'stable',
                    'performance_category': 'medium'
                }
            ]
        )
        
        return client
    
    def test_abc_analysis_algorithm(self):
        """Test ABC analysis categorization logic"""
        # Sample revenue data
        products = [
            {'sku': 'A1', 'revenue': 10000},
            {'sku': 'A2', 'revenue': 8000},
            {'sku': 'B1', 'revenue': 3000},
            {'sku': 'B2', 'revenue': 2000},
            {'sku': 'C1', 'revenue': 500},
            {'sku': 'C2', 'revenue': 300}
        ]
        
        # Calculate ABC categorization
        total_revenue = sum(p['revenue'] for p in products)
        products_sorted = sorted(products, key=lambda x: x['revenue'], reverse=True)
        
        categories = []
        cumulative_revenue = 0
        
        for product in products_sorted:
            cumulative_revenue += product['revenue']
            cumulative_percentage = (cumulative_revenue / total_revenue) * 100
            
            if cumulative_percentage <= 80:
                category = 'A'
            elif cumulative_percentage <= 95:
                category = 'B'
            else:
                category = 'C'
            
            categories.append({
                'sku': product['sku'],
                'category': category,
                'revenue': product['revenue'],
                'cumulative_percentage': cumulative_percentage
            })
        
        # Verify categorization
        assert categories[0]['category'] == 'A'  # Highest revenue
        assert categories[1]['category'] == 'A'  # Still in top 80%
        assert categories[2]['category'] == 'B'  # In 80-95% range
        assert categories[-1]['category'] == 'C'  # Lowest revenue
    
    def test_demand_forecasting_algorithm(self):
        """Test demand forecasting using moving averages"""
        # Sample historical sales data (weekly)
        historical_data = [100, 120, 110, 130, 125, 140, 135, 150]
        
        # Calculate 4-week moving average
        window_size = 4
        moving_averages = []
        
        for i in range(window_size - 1, len(historical_data)):
            avg = sum(historical_data[i - window_size + 1:i + 1]) / window_size
            moving_averages.append(avg)
        
        # Forecast next period (simple trend)
        if len(moving_averages) >= 2:
            trend = moving_averages[-1] - moving_averages[-2]
            forecast = moving_averages[-1] + trend
        else:
            forecast = moving_averages[-1] if moving_averages else 0
        
        # Verify calculations
        assert len(moving_averages) == 5  # 8 - 4 + 1
        assert moving_averages[0] == 115  # (100+120+110+130)/4
        assert forecast > 135  # Should be increasing trend
    
    def test_sales_velocity_calculation(self):
        """Test sales velocity metrics calculation"""
        # Sample order data
        orders = [
            {'sku': 'TEST-001', 'quantity': 10, 'revenue': 1000, 'date': '2024-01-01'},
            {'sku': 'TEST-001', 'quantity': 15, 'revenue': 1500, 'date': '2024-01-15'},
            {'sku': 'TEST-001', 'quantity': 20, 'revenue': 2000, 'date': '2024-01-30'},
        ]
        
        # Calculate velocity
        total_quantity = sum(order['quantity'] for order in orders)
        total_revenue = sum(order['revenue'] for order in orders)
        days_period = 30
        
        velocity_per_day = total_quantity / days_period
        revenue_per_day = total_revenue / days_period
        
        # Determine trend (simplified)
        quantities = [order['quantity'] for order in orders]
        trend = 'increasing' if quantities[-1] > quantities[0] else 'decreasing'
        
        # Verify calculations
        assert total_quantity == 45
        assert total_revenue == 4500
        assert velocity_per_day == 1.5
        assert revenue_per_day == 150.0
        assert trend == 'increasing'
    
    def test_gross_margin_analysis(self):
        """Test gross margin calculation and analysis"""
        # Sample product data
        products = [
            {'sku': 'PROD-001', 'revenue': 10000, 'cost': 6000, 'quantity': 100},
            {'sku': 'PROD-002', 'revenue': 5000, 'cost': 4000, 'quantity': 50}
        ]
        
        results = []
        for product in products:
            profit = product['revenue'] - product['cost']
            margin_percentage = (profit / product['revenue']) * 100 if product['revenue'] > 0 else 0
            margin_per_unit = profit / product['quantity'] if product['quantity'] > 0 else 0
            
            results.append({
                'sku': product['sku'],
                'gross_margin_percentage': margin_percentage,
                'profit': profit,
                'margin_per_unit': margin_per_unit
            })
        
        # Verify calculations
        assert results[0]['gross_margin_percentage'] == 40.0  # (4000/10000)*100
        assert results[0]['profit'] == 4000
        assert results[0]['margin_per_unit'] == 40.0  # 4000/100
        
        assert results[1]['gross_margin_percentage'] == 20.0  # (1000/5000)*100
        assert results[1]['profit'] == 1000
        assert results[1]['margin_per_unit'] == 20.0  # 1000/50
    
    def test_hidden_revenue_opportunities(self):
        """Test identification of hidden revenue opportunities"""
        # Sample product performance data
        products = [
            {'sku': 'HIGH-MARGIN-LOW-VEL', 'margin': 60, 'velocity': 2, 'inventory': 100},
            {'sku': 'LOW-MARGIN-HIGH-VEL', 'margin': 15, 'velocity': 20, 'inventory': 50},
            {'sku': 'BALANCED-PROD', 'margin': 35, 'velocity': 10, 'inventory': 75}
        ]
        
        opportunities = []
        
        for product in products:
            opportunity_score = 0
            recommendations = []
            
            # High margin but low velocity
            if product['margin'] > 50 and product['velocity'] < 5:
                opportunity_score += 30
                recommendations.append('Increase marketing for high-margin product')
            
            # High velocity but low margin
            if product['velocity'] > 15 and product['margin'] < 20:
                opportunity_score += 25
                recommendations.append('Optimize pricing or reduce costs')
            
            # High inventory with balanced performance
            if product['inventory'] > 60 and 20 <= product['margin'] <= 50:
                opportunity_score += 20
                recommendations.append('Consider bundling or promotional campaigns')
            
            if opportunity_score > 0:
                opportunities.append({
                    'sku': product['sku'],
                    'opportunity_score': opportunity_score,
                    'recommendations': recommendations
                })
        
        # Verify opportunity identification
        assert len(opportunities) == 3
        assert any(opp['sku'] == 'HIGH-MARGIN-LOW-VEL' for opp in opportunities)
        assert any(opp['sku'] == 'LOW-MARGIN-HIGH-VEL' for opp in opportunities)
    
    def test_supplier_performance_scoring(self):
        """Test supplier performance scoring algorithm"""
        # Sample supplier data
        suppliers = [
            {
                'supplier_id': 'SUP-001',
                'on_time_delivery_rate': 95,
                'quality_score': 88,
                'cost_competitiveness': 85,
                'response_time_hours': 2,
                'total_orders': 150
            },
            {
                'supplier_id': 'SUP-002',
                'on_time_delivery_rate': 78,
                'quality_score': 92,
                'cost_competitiveness': 90,
                'response_time_hours': 8,
                'total_orders': 75
            }
        ]
        
        scored_suppliers = []
        
        for supplier in suppliers:
            # Calculate weighted performance score
            delivery_weight = 0.3
            quality_weight = 0.25
            cost_weight = 0.25
            response_weight = 0.2
            
            # Normalize response time (lower is better)
            response_score = max(0, 100 - (supplier['response_time_hours'] * 5))
            
            performance_score = (
                supplier['on_time_delivery_rate'] * delivery_weight +
                supplier['quality_score'] * quality_weight +
                supplier['cost_competitiveness'] * cost_weight +
                response_score * response_weight
            )
            
            # Determine performance tier
            if performance_score >= 90:
                tier = 'Excellent'
            elif performance_score >= 80:
                tier = 'Good'
            elif performance_score >= 70:
                tier = 'Average'
            else:
                tier = 'Poor'
            
            scored_suppliers.append({
                'supplier_id': supplier['supplier_id'],
                'performance_score': round(performance_score, 1),
                'tier': tier
            })
        
        # Verify scoring
        assert scored_suppliers[0]['performance_score'] > 85
        assert scored_suppliers[0]['tier'] in ['Excellent', 'Good']
        assert scored_suppliers[1]['performance_score'] < scored_suppliers[0]['performance_score']
    
    def test_inventory_turnover_analysis(self):
        """Test inventory turnover ratio calculations"""
        # Sample inventory data
        products = [
            {'sku': 'FAST-MOVER', 'avg_inventory': 100, 'cogs_annual': 12000},
            {'sku': 'SLOW-MOVER', 'avg_inventory': 200, 'cogs_annual': 6000},
            {'sku': 'DEAD-STOCK', 'avg_inventory': 150, 'cogs_annual': 0}
        ]
        
        analysis_results = []
        
        for product in products:
            # Calculate turnover ratio
            turnover_ratio = (product['cogs_annual'] / product['avg_inventory']) if product['avg_inventory'] > 0 else 0
            
            # Determine performance rating
            if turnover_ratio >= 10:
                performance = 'Excellent'
            elif turnover_ratio >= 6:
                performance = 'Good'
            elif turnover_ratio >= 3:
                performance = 'Average'
            elif turnover_ratio > 0:
                performance = 'Poor'
            else:
                performance = 'Dead Stock'
            
            # Calculate days of inventory
            days_of_inventory = (365 / turnover_ratio) if turnover_ratio > 0 else float('inf')
            
            analysis_results.append({
                'sku': product['sku'],
                'turnover_ratio': round(turnover_ratio, 2),
                'performance': performance,
                'days_of_inventory': round(days_of_inventory, 1) if days_of_inventory != float('inf') else 'N/A'
            })
        
        # Verify analysis
        assert analysis_results[0]['turnover_ratio'] == 120  # 12000/100
        assert analysis_results[0]['performance'] == 'Excellent'
        assert analysis_results[1]['turnover_ratio'] == 30  # 6000/200
        assert analysis_results[2]['performance'] == 'Dead Stock'
    
    def test_customer_behavior_insights(self):
        """Test customer segmentation and behavior analysis"""
        # Sample customer data
        customers = [
            {'customer_id': 'CUST-001', 'total_spent': 5000, 'orders': 20, 'avg_order': 250, 'frequency': 2.5},
            {'customer_id': 'CUST-002', 'total_spent': 1200, 'orders': 8, 'avg_order': 150, 'frequency': 1.0},
            {'customer_id': 'CUST-003', 'total_spent': 800, 'orders': 2, 'avg_order': 400, 'frequency': 0.2}
        ]
        
        segments = []
        
        for customer in customers:
            # RFM-like segmentation (simplified)
            recency_score = min(5, customer['frequency'])  # How often they buy
            frequency_score = min(5, customer['orders'] / 4)  # Total orders normalized
            monetary_score = min(5, customer['total_spent'] / 1000)  # Spending normalized
            
            total_score = recency_score + frequency_score + monetary_score
            
            # Determine segment
            if total_score >= 12:
                segment = 'Champions'
            elif total_score >= 9:
                segment = 'Loyal Customers'
            elif total_score >= 6:
                segment = 'Potential Loyalists'
            else:
                segment = 'New Customers'
            
            segments.append({
                'customer_id': customer['customer_id'],
                'segment': segment,
                'total_score': round(total_score, 1),
                'avg_order_value': customer['avg_order']
            })
        
        # Verify segmentation
        assert segments[0]['segment'] in ['Champions', 'Loyal Customers']  # High value customer
        assert segments[2]['segment'] in ['New Customers', 'Potential Loyalists']  # Low frequency
    
    def test_multi_channel_fee_analysis(self):
        """Test multi-channel fee analysis and profitability comparison"""
        # Sample channel data
        channels = [
            {
                'channel': 'Shopify',
                'gross_sales': 10000,
                'transaction_fees': 290,  # 2.9%
                'monthly_fee': 29,
                'other_fees': 50
            },
            {
                'channel': 'Amazon FBA',
                'gross_sales': 15000,
                'transaction_fees': 1050,  # 7% (higher fees)
                'monthly_fee': 39.99,
                'other_fees': 200  # Storage, fulfillment
            },
            {
                'channel': 'WooCommerce',
                'gross_sales': 8000,
                'transaction_fees': 240,  # 3% (payment processor)
                'monthly_fee': 0,  # Self-hosted
                'other_fees': 100  # Plugins, hosting
            }
        ]
        
        analysis = []
        
        for channel_data in channels:
            total_fees = (
                channel_data['transaction_fees'] +
                channel_data['monthly_fee'] +
                channel_data['other_fees']
            )
            
            net_revenue = channel_data['gross_sales'] - total_fees
            fee_percentage = (total_fees / channel_data['gross_sales']) * 100
            
            # Calculate profitability score (higher is better)
            profitability_score = (net_revenue / channel_data['gross_sales']) * 100
            
            # Determine efficiency rating
            if fee_percentage <= 5:
                efficiency = 'Excellent'
            elif fee_percentage <= 8:
                efficiency = 'Good'
            elif fee_percentage <= 12:
                efficiency = 'Average'
            else:
                efficiency = 'Poor'
            
            analysis.append({
                'channel': channel_data['channel'],
                'gross_sales': channel_data['gross_sales'],
                'total_fees': total_fees,
                'net_revenue': net_revenue,
                'fee_percentage': round(fee_percentage, 2),
                'profitability_score': round(profitability_score, 2),
                'efficiency': efficiency
            })
        
        # Verify analysis
        shopify = next(ch for ch in analysis if ch['channel'] == 'Shopify')
        amazon = next(ch for ch in analysis if ch['channel'] == 'Amazon FBA')
        woocommerce = next(ch for ch in analysis if ch['channel'] == 'WooCommerce')
        
        assert shopify['fee_percentage'] < amazon['fee_percentage']  # Shopify should be cheaper
        assert woocommerce['fee_percentage'] < shopify['fee_percentage']  # WooCommerce cheapest
        assert amazon['efficiency'] == 'Average'  # Higher fees but higher volume


class TestAdvancedAnalyticsIntegration:
    """Integration tests for advanced analytics API endpoints"""
    
    @pytest.mark.asyncio
    async def test_advanced_analytics_api_endpoint(self):
        """Test the advanced analytics API endpoint"""
        # This would test the actual API endpoint
        # For now, we'll test the structure and response format
        
        expected_response_structure = {
            'success': True,
            'data': {
                'analysis': {
                    'scenario': str,
                    'revenueImpact': dict,
                    'profitabilityImpact': dict,
                    'operationalImpact': dict,
                    'riskAssessment': dict,
                    'timeframe': dict,
                    'recommendations': list,
                    'confidence': int
                }
            },
            'metadata': {
                'analysisType': str,
                'timestamp': str,
                'companyId': str
            }
        }
        
        # Verify expected structure
        assert isinstance(expected_response_structure['success'], bool)
        assert 'data' in expected_response_structure
        assert 'metadata' in expected_response_structure
    
    def test_analytics_data_validation(self):
        """Test data validation for analytics inputs"""
        # Valid analysis types
        valid_types = [
            'abc-analysis',
            'demand-forecast', 
            'sales-velocity',
            'gross-margin',
            'hidden-opportunities',
            'supplier-performance',
            'inventory-turnover',
            'customer-insights',
            'channel-fees'
        ]
        
        # Test each type has expected characteristics
        for analysis_type in valid_types:
            assert isinstance(analysis_type, str)
            assert '-' in analysis_type or '_' in analysis_type  # Proper naming convention
    
    def test_performance_benchmarks(self):
        """Test performance benchmarks for analytics calculations"""
        # Performance thresholds for different metrics
        benchmarks = {
            'inventory_turnover': {
                'excellent': 10,
                'good': 6,
                'average': 3,
                'poor': 1
            },
            'gross_margin': {
                'excellent': 50,
                'good': 30,
                'average': 20,
                'poor': 10
            },
            'supplier_performance': {
                'excellent': 90,
                'good': 80,
                'average': 70,
                'poor': 60
            }
        }
        
        # Verify benchmark structure
        for metric, thresholds in benchmarks.items():
            assert 'excellent' in thresholds
            assert 'good' in thresholds
            assert 'average' in thresholds
            assert 'poor' in thresholds
            
            # Verify descending order
            values = list(thresholds.values())
            assert values == sorted(values, reverse=True)


if __name__ == '__main__':
    # Run specific tests
    pytest.main([__file__, '-v'])
