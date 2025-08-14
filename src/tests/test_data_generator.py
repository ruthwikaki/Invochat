#!/usr/bin/env python3
"""
Invochat Data Generator for Existing Companies & Users
Generates test data for existing companies and users only
Does NOT create companies or users - uses existing ones
"""

import json
import os
import uuid
import random
from datetime import datetime, timedelta
from faker import Faker
from typing import List, Dict, Any
from dotenv import load_dotenv
from supabase import create_client, Client

# Load environment variables
load_dotenv()

# Initialize Faker
fake = Faker()
Faker.seed(42)
random.seed(42)

class InvochatDataGenerator:
    def __init__(self):
        self.supabase_url = os.getenv('NEXT_PUBLIC_SUPABASE_URL')
        self.supabase_key = os.getenv('SUPABASE_SERVICE_ROLE_KEY') or os.getenv('NEXT_PUBLIC_SUPABASE_ANON_KEY')
        
        if not self.supabase_url or not self.supabase_key:
            raise Exception("⚠️ Supabase credentials not found in .env file")
        
        try:
            self.supabase: Client = create_client(self.supabase_url, self.supabase_key)
            print("✅ Connected to Supabase database")
        except Exception as e:
            raise Exception(f"❌ Failed to connect to Supabase: {e}")
        
        # Will fetch existing companies and users from database
        self.companies = []
        self.users = []

    def fetch_existing_data(self):
        """Fetch existing companies and users from database"""
        print("📊 Fetching existing companies and users...")
        
        try:
            # Fetch companies
            companies_response = self.supabase.table('companies').select('*').execute()
            self.companies = companies_response.data
            print(f"   ✅ Found {len(self.companies)} companies")
            
            # Fetch users through company_users table (since users are in auth schema)
            # We'll get company_users which links auth.users to companies
            users_response = self.supabase.table('company_users').select('*').execute()
            
            # Create user objects with company_id for each company_user relationship
            self.users = []
            for company_user in users_response.data:
                # Create a user object that includes the company relationship
                user_obj = {
                    'id': company_user['user_id'],
                    'company_id': company_user['company_id'],
                    'role': company_user.get('role', 'Member'),
                    'deleted_at': None  # Assume active users
                }
                self.users.append(user_obj)
            
            print(f"   ✅ Found {len(self.users)} user-company relationships")
            
            if not self.companies:
                raise Exception("No companies found in database. Please create companies first.")
            if not self.users:
                raise Exception("No user-company relationships found in database. Please ensure users are properly linked to companies.")
                
        except Exception as e:
            print(f"❌ Error fetching existing data: {e}")
            raise

    def generate_suppliers(self, suppliers_per_company: int = 15):
        """Generate suppliers for existing companies"""
        print("🏭 Generating suppliers...")
        
        suppliers = []
        supplier_types = [
            "Electronics Wholesale", "Fashion Distributor", "Home Goods Supply", 
            "Sports Equipment Co", "Book Publisher", "Beauty Products Inc",
            "Kitchen Supplies Ltd", "Tech Accessories", "Outdoor Gear Supply",
            "Health & Wellness", "Pet Products Co", "Toy Distribution",
            "Jewelry Wholesale", "Baby Products Supply", "Office Furniture Co"
        ]
        
        for company in self.companies:
            for i in range(suppliers_per_company):
                base_name = random.choice(supplier_types)
                if i < len(supplier_types):
                    supplier_name = supplier_types[i]
                else:
                    supplier_name = f"{fake.company()} {random.choice(['Wholesale', 'Supply', 'Distribution'])}"
                
                supplier = {
                    "id": str(uuid.uuid4()),
                    "company_id": company["id"],
                    "name": supplier_name,
                    "email": fake.email(),
                    "phone": fake.phone_number(),
                    "default_lead_time_days": random.randint(3, 21),
                    "notes": fake.text(max_nb_chars=200) if random.random() > 0.3 else None,
                    "created_at": fake.date_time_between(start_date="-1y", end_date="now").isoformat()
                }
                suppliers.append(supplier)
        
        # Insert suppliers
        try:
            batch_size = 50
            for i in range(0, len(suppliers), batch_size):
                batch = suppliers[i:i + batch_size]
                result = self.supabase.table('suppliers').insert(batch).execute()
            print(f"   ✅ Inserted {len(suppliers)} suppliers")
        except Exception as e:
            print(f"   ❌ Error inserting suppliers: {e}")
        
        return suppliers

    def generate_customers(self, customers_per_company: int = 100):
        """Generate customers for existing companies"""
        print("🛒 Generating customers...")
        
        customers = []
        
        for company in self.companies:
            for i in range(customers_per_company):
                first_order_date = fake.date_time_between(start_date="-2y", end_date="-1d")
                
                customer = {
                    "id": str(uuid.uuid4()),
                    "company_id": company["id"],
                    "name": fake.name(),
                    "email": fake.email(),
                    "created_at": first_order_date.isoformat(),
                    "deleted_at": None if random.random() > 0.02 else fake.date_time_between(start_date="-30d", end_date="now").isoformat()
                }
                customers.append(customer)
        
        # Insert customers in batches
        try:
            batch_size = 100
            for i in range(0, len(customers), batch_size):
                batch = customers[i:i + batch_size]
                result = self.supabase.table('customers').insert(batch).execute()
            print(f"   ✅ Inserted {len(customers)} customers")
        except Exception as e:
            print(f"   ❌ Error inserting customers: {e}")
        
        return customers

    def generate_products(self, products_per_company: int = 200):
        """Generate products for existing companies"""
        print("📦 Generating products...")
        
        products = []
        categories = [
            "Electronics & Gadgets", "Fashion & Apparel", "Home & Living", 
            "Sports & Fitness", "Books & Media", "Health & Beauty", 
            "Kitchen & Dining", "Toys & Games", "Pet Supplies", 
            "Jewelry & Accessories", "Baby & Kids", "Office Supplies"
        ]
        
        # Product names by category
        product_names = {
            "Electronics & Gadgets": [
                "Wireless Bluetooth Earbuds Pro", "4K Smart TV 55-Inch", "Gaming Mechanical Keyboard", 
                "USB-C Fast Charger 65W", "Portable Power Bank 20000mAh", "Smart Fitness Watch",
                "Wireless Phone Charger Pad", "Bluetooth Speaker Waterproof", "HD Webcam 1080p",
                "Noise Cancelling Headphones", "Smartphone Gimbal Stabilizer", "LED Ring Light"
            ],
            "Fashion & Apparel": [
                "Premium Cotton T-Shirt", "High-Waisted Skinny Jeans", "Cozy Knit Sweater", 
                "Athletic Running Sneakers", "Classic Denim Jacket", "Floral Summer Dress",
                "Leather Crossbody Bag", "Silk Scarf Collection", "Winter Wool Coat",
                "Yoga Leggings High-Waist", "Business Casual Blazer", "Bohemian Maxi Dress"
            ],
            "Home & Living": [
                "Modern Table Lamp LED", "Ceramic Plant Pot Set", "Memory Foam Pillow", 
                "Scented Candle Gift Set", "Throw Blanket Chunky Knit", "Wall Art Print Set",
                "Essential Oil Diffuser", "Bamboo Cutting Board", "Decorative Mirror Round",
                "Blackout Curtains Thermal", "Storage Ottoman Bench", "Gallery Wall Frames"
            ],
            "Sports & Fitness": [
                "Non-Slip Yoga Mat", "Adjustable Dumbbells Set", "Resistance Bands Kit", 
                "Protein Shaker Bottle", "Athletic Gym Bag", "Foam Roller Massage",
                "Fitness Tracker Band", "Jump Rope Speed", "Kettlebell Cast Iron",
                "Exercise Ball Anti-Burst", "Workout Gloves Grip", "Yoga Block Set"
            ],
            "Books & Media": [
                "Self-Help Bestseller", "Cookbook Mediterranean", "Mystery Thriller Novel",
                "Business Strategy Guide", "Art Coffee Table Book", "Children's Picture Book",
                "Programming Learning Book", "History Documentary", "Poetry Collection",
                "Travel Photography Book", "DIY Craft Manual", "Mindfulness Journal"
            ],
            "Health & Beauty": [
                "Vitamin C Serum Anti-Aging", "Organic Face Mask Set", "Bamboo Toothbrush Pack", 
                "Essential Oils Starter Kit", "Silk Pillowcase Hair", "LED Light Therapy Mask",
                "Natural Deodorant", "Collagen Supplement", "Jade Facial Roller",
                "Dry Brush Body Exfoliating", "Aromatherapy Bath Salts", "Reusable Makeup Remover Pads"
            ]
        }
        
        for company in self.companies:
            for i in range(products_per_company):
                category = random.choice(categories)
                
                # Get product name
                if category in product_names:
                    product_name = random.choice(product_names[category])
                else:
                    product_name = f"{fake.catch_phrase()} {category.split()[0]}"
                
                ecommerce_tags = ["bestseller", "new-arrival", "sale", "featured", "limited-edition", 
                                "eco-friendly", "premium", "budget-friendly", "trending", "seasonal"]
                
                product = {
                    "id": str(uuid.uuid4()),
                    "company_id": company["id"],
                    "title": product_name,
                    "description": f"High-quality {category.lower()} product designed for everyday use. {fake.text(max_nb_chars=100)}",
                    "handle": product_name.lower().replace(" ", "-").replace("&", "and").replace("/", "-"),
                    "product_type": category,
                    "tags": random.sample(ecommerce_tags, k=random.randint(1, 3)),
                    "status": random.choices(["active", "archived", "draft"], weights=[85, 5, 10])[0],
                    "image_url": f"https://placehold.co/400x400.png",
                    "external_product_id": f"ext_{random.randint(1000000, 9999999)}",
                    "created_at": fake.date_time_between(start_date="-1y", end_date="now").isoformat(),
                    "updated_at": fake.date_time_between(start_date="-30d", end_date="now").isoformat(),
                    "deleted_at": None if random.random() > 0.03 else fake.date_time_between(start_date="-30d", end_date="now").isoformat()
                }
                products.append(product)
        
        # Insert products in batches
        try:
            batch_size = 100
            for i in range(0, len(products), batch_size):
                batch = products[i:i + batch_size]
                result = self.supabase.table('products').insert(batch).execute()
            print(f"   ✅ Inserted {len(products)} products")
        except Exception as e:
            print(f"   ❌ Error inserting products: {e}")
        
        return products

    def generate_product_variants(self, products: List[Dict]):
        """Generate product variants"""
        print("🏷️ Generating product variants...")
        
        variants = []
        sizes = ["XS", "S", "M", "L", "XL", "XXL"]
        colors = ["Red", "Blue", "Green", "Black", "White", "Gray", "Navy", "Brown"]
        
        for product in products:
            if product.get("deleted_at"):
                continue
                
            # Generate 1-3 variants per product
            variant_count = random.randint(1, 3)
            
            for i in range(variant_count):
                base_price = random.randint(500, 50000)  # in cents
                cost = int(base_price * random.uniform(0.3, 0.7))
                
                # Stock levels with realistic scenarios
                stock_scenarios = [
                    ("normal", random.randint(10, 500)),
                    ("low", random.randint(1, 9)),
                    ("out", 0),
                    ("overstocked", random.randint(1000, 5000))
                ]
                scenario, stock = random.choices(stock_scenarios, weights=[70, 15, 5, 10])[0]
                
                variant = {
                    "id": str(uuid.uuid4()),
                    "product_id": product["id"],
                    "company_id": product["company_id"],
                    "sku": f"SKU-{random.randint(100000, 999999)}",
                    "title": f"Variant {i+1}" if variant_count > 1 else None,
                    "option1_name": "Size" if variant_count > 1 else None,
                    "option1_value": random.choice(sizes) if variant_count > 1 else None,
                    "option2_name": "Color" if variant_count > 2 else None,
                    "option2_value": random.choice(colors) if variant_count > 2 else None,
                    "option3_name": None,
                    "option3_value": None,
                    "barcode": fake.ean13() if random.random() > 0.3 else None,
                    "price": base_price,
                    "compare_at_price": int(base_price * random.uniform(1.1, 1.5)) if random.random() > 0.7 else None,
                    "cost": cost,
                    "inventory_quantity": stock,
                    "reserved_quantity": random.randint(0, min(stock, 10)) if stock > 0 else 0,
                    "in_transit_quantity": random.randint(0, 50) if random.random() > 0.8 else 0,
                    "reorder_point": random.randint(5, 25),
                    "reorder_quantity": random.randint(50, 200),
                    "lead_time_days": random.randint(3, 21),
                    "location": random.choice(["Main Warehouse", "Store A", "Store B", "Overflow"]),
                    "external_variant_id": f"ext_var_{random.randint(1000000, 9999999)}",
                    "created_at": product["created_at"],
                    "updated_at": fake.date_time_between(start_date="-30d", end_date="now").isoformat(),
                    "deleted_at": None,
                    "version": random.randint(1, 5)
                }
                variants.append(variant)
        
        # Insert variants in batches
        try:
            batch_size = 100
            for i in range(0, len(variants), batch_size):
                batch = variants[i:i + batch_size]
                result = self.supabase.table('product_variants').insert(batch).execute()
            print(f"   ✅ Inserted {len(variants)} product variants")
        except Exception as e:
            print(f"   ❌ Error inserting product variants: {e}")
        
        return variants

    def generate_orders(self, customers: List[Dict], variants: List[Dict], orders_per_company: int = 300):
        """Generate orders for existing companies"""
        print("🛍️ Generating orders...")
        
        orders = []
        order_line_items = []
        
        financial_statuses = ["pending", "authorized", "paid", "partially_paid", "refunded", "voided"]
        fulfillment_statuses = ["unfulfilled", "partial", "fulfilled", "shipped", "delivered"]
        platforms = ["shopify", "woocommerce", "amazon_fba", "manual", "website", "mobile_app"]
        
        # Group customers and variants by company
        customers_by_company = {}
        variants_by_company = {}
        
        for customer in customers:
            if customer.get("deleted_at"):
                continue
            company_id = customer["company_id"]
            if company_id not in customers_by_company:
                customers_by_company[company_id] = []
            customers_by_company[company_id].append(customer)
        
        for variant in variants:
            if variant.get("deleted_at"):
                continue
            company_id = variant["company_id"]
            if company_id not in variants_by_company:
                variants_by_company[company_id] = []
            variants_by_company[company_id].append(variant)
        
        for company in self.companies:
            company_id = company["id"]
            
            if company_id not in customers_by_company or company_id not in variants_by_company:
                continue
                
            company_customers = customers_by_company[company_id]
            company_variants = variants_by_company[company_id]
            
            for i in range(orders_per_company):
                if not company_customers or not company_variants:
                    continue
                    
                customer = random.choice(company_customers)
                order_date = fake.date_time_between(start_date="-1y", end_date="now")
                
                # Order values
                subtotal = random.randint(1500, 50000)  # $15-500
                tax = int(subtotal * 0.08)
                shipping = 599 if subtotal < 5000 else 0  # Free shipping over $50
                discount = random.randint(0, int(subtotal * 0.1)) if random.random() > 0.8 else 0
                total = subtotal + tax + shipping - discount
                
                order = {
                    "id": str(uuid.uuid4()),
                    "company_id": company_id,
                    "order_number": f"#{random.randint(1000, 9999)}",
                    "external_order_id": f"ext_{random.randint(1000000, 9999999)}",
                    "customer_id": customer["id"],
                    "financial_status": random.choices(financial_statuses, weights=[5, 5, 80, 3, 5, 2])[0],
                    "fulfillment_status": random.choices(fulfillment_statuses, weights=[15, 10, 20, 30, 25])[0],
                    "currency": "USD",
                    "subtotal": subtotal,
                    "total_tax": tax,
                    "total_shipping": shipping,
                    "total_discounts": discount,
                    "total_amount": total,
                    "source_platform": random.choice(platforms),
                    "created_at": order_date.isoformat(),
                    "updated_at": fake.date_time_between(start_date=order_date, end_date="now").isoformat()
                }
                orders.append(order)
                
                # Generate 1-4 line items per order
                items_count = random.randint(1, 4)
                selected_variants = random.sample(company_variants, min(items_count, len(company_variants)))
                
                for variant in selected_variants:
                    quantity = random.randint(1, 5)
                    price = variant["price"]
                    discount = random.randint(0, int(price * 0.1)) if random.random() > 0.9 else 0
                    
                    line_item = {
                        "id": str(uuid.uuid4()),
                        "order_id": order["id"],
                        "variant_id": variant["id"],
                        "product_name": [p['title'] for p in products if p['id'] == variant['product_id']][0],
                        "variant_title": variant["title"],
                        "sku": variant["sku"],
                        "quantity": quantity,
                        "price": price,
                        "total_discount": discount * quantity,
                        "tax_amount": int(price * quantity * 0.08),
                        "fulfillment_status": order["fulfillment_status"],
                        "external_line_item_id": f"ext_line_{random.randint(1000000, 9999999)}",
                        "company_id": company_id,
                        "cost_at_time": variant["cost"]
                    }
                    order_line_items.append(line_item)
        
        # Insert orders and line items
        try:
            batch_size = 100
            for i in range(0, len(orders), batch_size):
                batch = orders[i:i + batch_size]
                result = self.supabase.table('orders').insert(batch).execute()
            print(f"   ✅ Inserted {len(orders)} orders")
            
            for i in range(0, len(order_line_items), batch_size):
                batch = order_line_items[i:i + batch_size]
                result = self.supabase.table('order_line_items').insert(batch).execute()
            print(f"   ✅ Inserted {len(order_line_items)} order line items")
            
        except Exception as e:
            print(f"   ❌ Error inserting orders: {e}")
        
        return orders, order_line_items

    def generate_purchase_orders(self, suppliers: List[Dict], variants: List[Dict], po_per_company: int = 50):
        """Generate purchase orders"""
        print("📋 Generating purchase orders...")
        
        purchase_orders = []
        po_line_items = []
        
        statuses = ["Draft", "Sent", "Confirmed", "Received", "Cancelled"]
        
        # Group suppliers and variants by company
        suppliers_by_company = {}
        variants_by_company = {}
        
        for supplier in suppliers:
            company_id = supplier["company_id"]
            if company_id not in suppliers_by_company:
                suppliers_by_company[company_id] = []
            suppliers_by_company[company_id].append(supplier)
        
        for variant in variants:
            if variant.get("deleted_at"):
                continue
            company_id = variant["company_id"]
            if company_id not in variants_by_company:
                variants_by_company[company_id] = []
            variants_by_company[company_id].append(variant)
        
        for company in self.companies:
            company_id = company["id"]
            
            if company_id not in suppliers_by_company or company_id not in variants_by_company:
                continue
                
            company_suppliers = suppliers_by_company[company_id]
            company_variants = variants_by_company[company_id]
            
            for i in range(po_per_company):
                supplier = random.choice(company_suppliers)
                created_date = fake.date_time_between(start_date="-6m", end_date="now")
                
                po = {
                    "id": str(uuid.uuid4()),
                    "company_id": company_id,
                    "supplier_id": supplier["id"],
                    "status": random.choices(statuses, weights=[20, 30, 25, 20, 5])[0],
                    "po_number": f"PO-{random.randint(100000, 999999)}",
                    "total_cost": random.randint(50000, 500000),  # in cents
                    "expected_arrival_date": fake.date_between(start_date=created_date, end_date="+30d").isoformat(),
                    "created_at": created_date.isoformat(),
                    "idempotency_key": str(uuid.uuid4()),
                    "notes": fake.text(max_nb_chars=200) if random.random() > 0.6 else None
                }
                purchase_orders.append(po)
                
                # Generate 1-5 line items per PO
                items_count = random.randint(1, 5)
                selected_variants = random.sample(company_variants, min(items_count, len(company_variants)))
                
                for variant in selected_variants:
                    quantity = random.randint(10, 100)
                    cost = variant["cost"]
                    
                    line_item = {
                        "id": str(uuid.uuid4()),
                        "purchase_order_id": po["id"],
                        "variant_id": variant["id"],
                        "quantity": quantity,
                        "cost": cost,
                        "company_id": company_id
                    }
                    po_line_items.append(line_item)
        
        # Insert purchase orders and line items
        try:
            batch_size = 100
            for i in range(0, len(purchase_orders), batch_size):
                batch = purchase_orders[i:i + batch_size]
                result = self.supabase.table('purchase_orders').insert(batch).execute()
            print(f"   ✅ Inserted {len(purchase_orders)} purchase orders")
            
            for i in range(0, len(po_line_items), batch_size):
                batch = po_line_items[i:i + batch_size]
                result = self.supabase.table('purchase_order_line_items').insert(batch).execute()
            print(f"   ✅ Inserted {len(po_line_items)} PO line items")
            
        except Exception as e:
            print(f"   ❌ Error inserting purchase orders: {e}")

    def generate_all_data(self):
        """Generate all test data for existing companies and users"""
        print("🚀 Starting Invochat data generation...")
        print("=" * 60)
        
        try:
            # Step 1: Fetch existing companies and users
            self.fetch_existing_data()
            
            # Step 2: Generate and upload suppliers
            suppliers = self.generate_suppliers()
            
            # Step 3: Generate and upload customers
            customers = self.generate_customers()
            
            # Step 4: Generate and upload products
            products = self.generate_products()
            
            # Step 5: Generate and upload product variants
            variants = self.generate_product_variants(products)
            
            # Step 6: Generate and upload orders
            orders, order_line_items = self.generate_orders(customers, variants)
            
            # Step 7: Generate and upload purchase orders
            self.generate_purchase_orders(suppliers, variants)
            
            print("\n🎉 Data generation completed successfully!")
            print("📊 Summary:")
            print(f"   • {len(self.companies)} existing companies used")
            print(f"   • {len(self.users)} existing user-company relationships used")
            print(f"   • {len(suppliers)} suppliers generated")
            print(f"   • {len(customers)} customers generated") 
            print(f"   • {len(products)} products generated")
            print(f"   • {len(variants)} product variants generated")
            print(f"   • {len(orders)} orders generated")
            print(f"   • {len(order_line_items)} order line items generated")
            print(f"   • Purchase orders and line items generated")
            
            print("\n✅ Your Invochat database is now populated with comprehensive test data!")
            
        except Exception as e:
            print(f"\n❌ Error during data generation: {e}")
            import traceback
            traceback.print_exc()
            raise

def main():
    """Main function to run the data generator"""
    print("🚀 Starting Invochat Data Generator...")
    print("=" * 50)
    
    try:
        generator = InvochatDataGenerator()
        generator.generate_all_data()
        print("\n✅ Data generation completed successfully!")
        print("🔗 You can now test your Invochat application with realistic data.")
        
    except Exception as e:
        print(f"\n❌ Error during data generation: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()
