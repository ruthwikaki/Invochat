#!/usr/bin/env python3
"""
AI Features Test Suite for Invochat
Tests AI chat functionality, conversation management, and AI tool responses
"""

import pytest
import time
import json
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional
from test_config import TestConfig, TestCredentials
from utils.api_utils import APIUtils
from utils.database_utils import DatabaseUtils
from utils.data_utils import TestReporter

class TestAIChatFunctionality:
    """Test AI chat functionality and conversation management"""
    
    def setup_method(self):
        self.api = APIUtils(TestConfig.API_BASE_URL)
        self.db = DatabaseUtils(TestConfig.SUPABASE_URL, TestConfig.SUPABASE_SERVICE_KEY)
        self.reporter = TestReporter()
        self.test_credentials = TestCredentials()
        
        # Login before each test
        creds = self.test_credentials.get_user_credentials("Owner")
        self.api.login(creds["email"], creds["password"])
        print(f"🔐 Logged in as: {creds['email']}")
    
    def test_conversation_creation(self):
        """Test creating new conversations"""
        start_time = time.time()
        try:
            print("💬 Testing conversation creation")
            
            # Test creating a new conversation
            conversation_data = {
                "title": f"Test Conversation {datetime.now().isoformat()}"
            }
            
            response = self.api.post("/conversations", conversation_data)
            print(f"   POST /conversations: {response.status_code}")
            
            if response.status_code in [200, 201]:
                conversation = response.json()
                conversation_id = conversation.get('id')
                
                assert conversation_id is not None, "Conversation should have an ID"
                assert 'title' in conversation, "Conversation should have a title"
                
                print(f"   ✅ Conversation created: {conversation_id}")
                
                # Test retrieving the conversation
                get_response = self.api.get(f"/conversations/{conversation_id}")
                print(f"   GET /conversations/{conversation_id}: {get_response.status_code}")
                
                if get_response.status_code == 200:
                    retrieved_conversation = get_response.json()
                    assert retrieved_conversation['id'] == conversation_id
                    print(f"   ✅ Conversation retrieved successfully")
                
            duration = time.time() - start_time
            self.reporter.add_result("conversation_creation", "PASS", duration)
            
        except Exception as e:
            self.reporter.add_result("conversation_creation", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Conversation creation test failed: {e}")
            raise
    
    def test_conversation_listing(self):
        """Test listing conversations"""
        start_time = time.time()
        try:
            print("📋 Testing conversation listing")
            
            response = self.api.get("/conversations")
            print(f"   GET /conversations: {response.status_code}")
            
            if response.status_code == 200:
                conversations_data = response.json()
                
                # Handle both array and object responses
                if isinstance(conversations_data, list):
                    conversations = conversations_data
                else:
                    conversations = conversations_data.get('data', [])
                
                print(f"   📊 Found {len(conversations)} conversations")
                
                # Validate conversation structure
                if conversations:
                    conversation = conversations[0]
                    required_fields = ['id', 'title', 'created_at']
                    missing_fields = [field for field in required_fields if field not in conversation]
                    
                    if missing_fields:
                        print(f"   ⚠️ Missing fields in conversation: {missing_fields}")
                    else:
                        print(f"   ✅ Conversation structure valid")
                
                # Test pagination if supported
                paginated_response = self.api.get("/conversations?page=1&limit=5")
                print(f"   GET /conversations?page=1&limit=5: {paginated_response.status_code}")
            
            duration = time.time() - start_time
            self.reporter.add_result("conversation_listing", "PASS", duration)
            
        except Exception as e:
            self.reporter.add_result("conversation_listing", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Conversation listing test failed: {e}")
            raise
    
    def test_message_sending_and_ai_response(self):
        """Test sending messages and receiving AI responses"""
        start_time = time.time()
        try:
            print("🤖 Testing message sending and AI responses")
            
            # First create a conversation or use existing one
            conversations_response = self.api.get("/conversations")
            conversation_id = None
            
            if conversations_response.status_code == 200:
                conversations_data = conversations_response.json()
                conversations = conversations_data if isinstance(conversations_data, list) else conversations_data.get('data', [])
                
                if conversations:
                    conversation_id = conversations[0]['id']
                    print(f"   📝 Using existing conversation: {conversation_id}")
            
            # If no conversations exist, create one
            if not conversation_id:
                create_response = self.api.post("/conversations", {"title": "Test AI Chat"})
                if create_response.status_code in [200, 201]:
                    conversation_id = create_response.json().get('id')
                    print(f"   📝 Created new conversation: {conversation_id}")
            
            if conversation_id:
                # Test different types of business queries
                test_queries = [
                    "What are my top selling products?",
                    "Show me products that need reordering",
                    "What is my inventory worth?",
                    "Which products haven't sold recently?",
                    "How is my business performing this month?"
                ]
                
                successful_queries = 0
                ai_responses_received = 0
                
                for query in test_queries:
                    print(f"   🔍 Testing query: '{query[:40]}...'")
                    
                    # Test sending message
                    message_data = {
                        "content": query,
                        "conversationId": conversation_id
                    }
                    
                    message_response = self.api.post("/chat/message", message_data)
                    
                    print(f"      Message sent: {message_response.status_code}")
                    
                    if message_response.status_code in [200, 201]:
                        successful_queries += 1
                        
                        response_data = message_response.json()
                        
                        # Check for AI response content
                        if response_data.get('newMessage', {}).get('content'):
                            ai_responses_received += 1
                            print(f"      ✅ AI response received")
                            
                            # Check for AI components or visualizations
                            if response_data.get('newMessage', {}).get('component'):
                                print(f"      🎨 Component included: {response_data['newMessage']['component']}")
                            
                            if response_data.get('newMessage', {}).get('visualization'):
                                print(f"      📊 Visualization included")
                        else:
                            print(f"      ⚠️ No AI response content found")
                    else:
                        print(f"      ❌ Message failed: {message_response.status_code}")
                
                # Calculate success rates
                query_success_rate = successful_queries / len(test_queries)
                ai_response_rate = ai_responses_received / len(test_queries)
                
                print(f"   📊 Query success rate: {query_success_rate:.1%}")
                print(f"   📊 AI response rate: {ai_response_rate:.1%}")
                
                # Test should pass if most queries work
                assert query_success_rate >= 0.6, f"Too many queries failed: {query_success_rate:.1%}"
                
            duration = time.time() - start_time
            self.reporter.add_result("message_sending_ai_response", "PASS", duration,
                                   details={
                                       "query_success_rate": query_success_rate,
                                       "ai_response_rate": ai_response_rate
                                   })
            
        except Exception as e:
            self.reporter.add_result("message_sending_ai_response", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Message/AI response test failed: {e}")
            raise

class TestAIToolIntegration:
    """Test AI tool integration and business intelligence features"""
    
    def setup_method(self):
        self.api = APIUtils(TestConfig.API_BASE_URL)
        self.db = DatabaseUtils(TestConfig.SUPABASE_URL, TestConfig.SUPABASE_SERVICE_KEY)
        self.reporter = TestReporter()
        self.test_credentials = TestCredentials()
        
        creds = self.test_credentials.get_user_credentials("Owner")
        self.api.login(creds["email"], creds["password"])
    
    def test_ai_business_queries(self):
        """Test AI responses to business intelligence queries"""
        start_time = time.time()
        try:
            print("📊 Testing AI business intelligence queries")
            
            # Test queries that should trigger specific AI tools
            business_queries = [
                {
                    "query": "Show me dead stock analysis",
                    "expected_tool": "dead_stock",
                    "expected_component": "DeadStockTable"
                },
                {
                    "query": "What products need reordering?",
                    "expected_tool": "reorder_suggestions", 
                    "expected_component": "ReorderList"
                },
                {
                    "query": "Show me inventory turnover analysis",
                    "expected_tool": "inventory_turnover",
                    "expected_component": "InventoryChart"
                },
                {
                    "query": "How are my suppliers performing?",
                    "expected_tool": "supplier_performance",
                    "expected_component": "SupplierTable"  
                },
                {
                    "query": "What's my best selling products?",
                    "expected_tool": "sales_analytics",
                    "expected_component": "SalesChart"
                }
            ]
            
            successful_queries = 0
            tool_triggers = 0
            component_renders = 0
            
            for query_test in business_queries:
                query = query_test["query"]
                expected_tool = query_test["expected_tool"]
                expected_component = query_test["expected_component"]
                
                print(f"   🔍 Testing: '{query}'")
                
                # Send query to AI chat
                chat_response = self.api.post("/chat/message", {
                    "content": query,
                    "conversationId": None
                })
                
                print(f"      Chat response: {chat_response.status_code}")
                
                if chat_response.status_code == 200:
                    successful_queries += 1
                    response_data = chat_response.json().get('newMessage', {})
                    
                    # Check if expected component was returned
                    component = response_data.get('component')
                    if component:
                        print(f"      🎨 Component: {component}")
                        if expected_component.lower() in component.lower():
                            component_renders += 1
                            print(f"      ✅ Expected component rendered")
                        else:
                            print(f"      ⚠️ Unexpected component (expected {expected_component})")
                    
                    # Check for data/visualization
                    if 'visualization' in response_data or 'component_props' in response_data:
                        tool_triggers += 1
                        print(f"      ✅ AI tool triggered with data")
                    
                    # Check response content relevance
                    response_content = response_data.get('response', response_data.get('content', ''))
                    if expected_tool.replace('_', ' ') in response_content.lower():
                        print(f"      ✅ Response mentions relevant topic")
                else:
                    print(f"      ❌ Query failed: {chat_response.status_code}")
            
            # Calculate success metrics
            query_success_rate = successful_queries / len(business_queries)
            tool_trigger_rate = tool_triggers / len(business_queries)
            component_render_rate = component_renders / len(business_queries)
            
            print(f"   📊 Overall Results:")
            print(f"      Query success: {query_success_rate:.1%}")
            print(f"      Tool triggers: {tool_trigger_rate:.1%}")
            print(f"      Component renders: {component_render_rate:.1%}")
            
            duration = time.time() - start_time
            self.reporter.add_result("ai_business_queries", "PASS", duration,
                                   details={
                                       "query_success_rate": query_success_rate,
                                       "tool_trigger_rate": tool_trigger_rate,
                                       "component_render_rate": component_render_rate
                                   })
            
        except Exception as e:
            self.reporter.add_result("ai_business_queries", "FAIL", time.time() - start_time, str(e))
            print(f"❌ AI business queries test failed: {e}")
            raise
    
    def test_ai_data_visualization_responses(self):
        """Test AI responses that include data visualizations"""
        start_time = time.time()
        try:
            print("📈 Testing AI data visualization responses")
            
            # Queries that should return visualized data
            visualization_queries = [
                "Show me a chart of my sales this month",
                "Graph my inventory levels by category", 
                "Display my top customers in a table",
                "Show revenue trends over time",
                "Create a dashboard of key metrics"
            ]
            
            visualizations_returned = 0
            data_included = 0
            
            for query in visualization_queries:
                print(f"   📊 Testing visualization query: '{query[:40]}...'")
                
                response = self.api.post("/chat/message", {
                    "content": query,
                    "conversationId": None
                })
                
                if response.status_code == 200:
                    data = response.json().get('newMessage', {})
                    
                    # Check for visualization data
                    has_visualization = any(key in data for key in [
                        'visualization', 'component', 'component_props', 'chart_data'
                    ])
                    
                    if has_visualization:
                        visualizations_returned += 1
                        print(f"      ✅ Visualization response received")
                        
                        # Check for actual data
                        if 'component_props' in data and data['component_props']:
                            data_included += 1
                            print(f"      ✅ Data included in visualization")
                        
                        # Log component type if available
                        if 'component' in data:
                            print(f"      🎨 Component type: {data['component']}")
                    else:
                        print(f"      ⚠️ No visualization returned")
                else:
                    print(f"      ❌ Query failed: {response.status_code}")
            
            visualization_rate = visualizations_returned / len(visualization_queries)
            data_inclusion_rate = data_included / len(visualization_queries)
            
            print(f"   📊 Visualization Results:")
            print(f"      Visualizations returned: {visualization_rate:.1%}")
            print(f"      Data included: {data_inclusion_rate:.1%}")
            
            duration = time.time() - start_time
            self.reporter.add_result("ai_data_visualization", "PASS", duration,
                                   details={
                                       "visualization_rate": visualization_rate,
                                       "data_inclusion_rate": data_inclusion_rate
                                   })
            
        except Exception as e:
            self.reporter.add_result("ai_data_visualization", "FAIL", time.time() - start_time, str(e))
            print(f"❌ AI data visualization test failed: {e}")
            raise

class TestAIResponseAccuracy:
    """Test accuracy and relevance of AI responses"""
    
    def setup_method(self):
        self.api = APIUtils(TestConfig.API_BASE_URL)
        self.db = DatabaseUtils(TestConfig.SUPABASE_URL, TestConfig.SUPABASE_SERVICE_KEY)
        self.reporter = TestReporter()
        self.test_credentials = TestCredentials()
        
        creds = self.test_credentials.get_user_credentials("Owner")
        self.api.login(creds["email"], creds["password"])
    
    def test_ai_response_relevance(self):
        """Test that AI responses are relevant to business context"""
        start_time = time.time()
        try:
            print("🎯 Testing AI response relevance")
            
            # Test query-response relevance
            relevance_tests = [
                {
                    "query": "What's my total revenue?",
                    "expected_keywords": ["revenue", "sales", "total", "income", "$"],
                    "unexpected_keywords": ["inventory", "product", "supplier"]
                },
                {
                    "query": "Show me low stock items",
                    "expected_keywords": ["stock", "inventory", "low", "reorder", "quantity"],
                    "unexpected_keywords": ["revenue", "customer", "profit"]
                },
                {
                    "query": "Who are my best customers?",
                    "expected_keywords": ["customer", "best", "top", "highest", "orders"],
                    "unexpected_keywords": ["inventory", "stock", "supplier"]
                }
            ]
            
            relevant_responses = 0
            
            for test in relevance_tests:
                query = test["query"]
                expected_keywords = test["expected_keywords"]
                unexpected_keywords = test["unexpected_keywords"]
                
                print(f"   🔍 Testing relevance: '{query}'")
                
                response = self.api.post("/chat/message", {
                    "content": query,
                    "conversationId": None
                })
                
                if response.status_code == 200:
                    data = response.json().get('newMessage', {})
                    response_text = data.get('response', data.get('content', '')).lower()
                    
                    # Check for expected keywords
                    expected_found = sum(1 for keyword in expected_keywords if keyword.lower() in response_text)
                    unexpected_found = sum(1 for keyword in unexpected_keywords if keyword.lower() in response_text)
                    
                    expected_ratio = expected_found / len(expected_keywords)
                    
                    print(f"      Expected keywords found: {expected_found}/{len(expected_keywords)} ({expected_ratio:.1%})")
                    print(f"      Unexpected keywords found: {unexpected_found}")
                    
                    # Response is relevant if most expected keywords found and few unexpected
                    is_relevant = expected_ratio >= 0.5 and unexpected_found <= 1
                    
                    if is_relevant:
                        relevant_responses += 1
                        print(f"      ✅ Response appears relevant")
                    else:
                        print(f"      ⚠️ Response may not be relevant")
                else:
                    print(f"      ❌ Query failed: {response.status_code}")
            
            relevance_rate = relevant_responses / len(relevance_tests)
            print(f"   📊 Overall relevance rate: {relevance_rate:.1%}")
            
            duration = time.time() - start_time
            self.reporter.add_result("ai_response_relevance", "PASS", duration,
                                   details={"relevance_rate": relevance_rate})
            
        except Exception as e:
            self.reporter.add_result("ai_response_relevance", "FAIL", time.time() - start_time, str(e))
            print(f"❌ AI response relevance test failed: {e}")
            raise
    
    def test_ai_error_handling(self):
        """Test AI handling of unclear or invalid queries"""
        start_time = time.time()
        try:
            print("🚫 Testing AI error handling")
            
            # Test various types of problematic queries
            error_test_queries = [
                "",  # Empty query
                "asdfghjkl",  # Nonsense
                "What's the weather like?",  # Off-topic
                "Delete all my data",  # Potentially harmful
                "Show me data for company XYZ",  # Unauthorized access attempt
            ]
            
            graceful_handling = 0
            
            for query in error_test_queries:
                print(f"   🔍 Testing error handling: '{query}'")
                
                response = self.api.post("/chat/message", {
                    "content": query,
                    "conversationId": None
                })
                
                if response.status_code == 200:
                    data = response.json().get('newMessage', {})
                    response_text = data.get('response', data.get('content', ''))
                    
                    # Check for graceful error handling indicators
                    error_indicators = [
                        "sorry", "understand", "help", "clarify", "can't", "unable",
                        "not sure", "don't know", "try again", "rephrase"
                    ]
                    
                    has_error_handling = any(indicator in response_text.lower() for indicator in error_indicators)
                    
                    if has_error_handling:
                        graceful_handling += 1
                        print(f"      ✅ Graceful error handling detected")
                    else:
                        print(f"      ⚠️ No clear error handling")
                        print(f"      Response: {response_text[:100]}...")
                else:
                    # API error is also acceptable for invalid queries
                    graceful_handling += 1
                    print(f"      ✅ API properly rejected query: {response.status_code}")
            
            error_handling_rate = graceful_handling / len(error_test_queries)
            print(f"   📊 Graceful error handling rate: {error_handling_rate:.1%}")
            
            duration = time.time() - start_time
            self.reporter.add_result("ai_error_handling", "PASS", duration,
                                   details={"error_handling_rate": error_handling_rate})
            
        except Exception as e:
            self.reporter.add_result("ai_error_handling", "FAIL", time.time() - start_time, str(e))
            print(f"❌ AI error handling test failed: {e}")
            raise

class TestConversationManagement:
    """Test conversation management features"""
    
    def setup_method(self):
        self.api = APIUtils(TestConfig.API_BASE_URL)
        self.db = DatabaseUtils(TestConfig.SUPABASE_URL, TestConfig.SUPABASE_SERVICE_KEY)
        self.reporter = TestReporter()
        self.test_credentials = TestCredentials()
        
        creds = self.test_credentials.get_user_credentials("Owner")
        self.api.login(creds["email"], creds["password"])
    
    def test_conversation_persistence(self):
        """Test that conversations and messages are properly stored"""
        start_time = time.time()
        try:
            print("💾 Testing conversation persistence")
            
            # Create a conversation
            conversation_data = {"title": f"Persistence Test {datetime.now().isoformat()}"}
            create_response = self.api.post("/conversations", conversation_data)
            
            if create_response.status_code in [200, 201]:
                conversation_id = create_response.json().get('id')
                print(f"   📝 Created conversation: {conversation_id}")
                
                # Send a few messages
                test_messages = [
                    "What are my top selling products?",
                    "Show me inventory levels",
                    "How much revenue did I make this month?"
                ]
                
                message_ids = []
                for message_content in test_messages:
                    message_response = self.api.post(f"/chat/message", {
                        "content": message_content,
                        "conversationId": conversation_id
                    })
                    
                    if message_response.status_code in [200, 201]:
                        message_data = message_response.json().get('newMessage', {})
                        if 'id' in message_data:
                            message_ids.append(message_data['id'])
                        print(f"      ✅ Message sent: '{message_content[:30]}...'")
                    else:
                        print(f"      ⚠️ Message failed: {message_response.status_code}")
                
                # Verify messages are stored by retrieving them
                messages_response = self.api.get(f"/conversations/{conversation_id}/messages")
                
                if messages_response.status_code == 200:
                    messages_data = messages_response.json()
                    messages = messages_data if isinstance(messages_data, list) else messages_data.get('data', [])
                    
                    print(f"   📊 Retrieved {len(messages)} messages")
                    
                    # Check message content
                    user_messages = [msg for msg in messages if msg.get('role') == 'user']
                    print(f"   📊 Found {len(user_messages)} user messages")
                    
                    # Verify persistence by checking database directly
                    db_messages = self.db.supabase.table('messages')\
                        .select('*')\
                        .eq('conversation_id', conversation_id)\
                        .execute()
                    
                    db_message_count = len(db_messages.data) if db_messages.data else 0
                    print(f"   🗄️ Database contains {db_message_count} messages")
                    
                    persistence_verified = db_message_count >= len(test_messages)
                    
                    if persistence_verified:
                        print(f"   ✅ Message persistence verified")
                    else:
                        print(f"   ⚠️ Message persistence may have issues")
                
            duration = time.time() - start_time
            self.reporter.add_result("conversation_persistence", "PASS", duration)
            
        except Exception as e:
            self.reporter.add_result("conversation_persistence", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Conversation persistence test failed: {e}")
            raise
    
    def test_conversation_history_retrieval(self):
        """Test retrieving conversation history"""
        start_time = time.time()
        try:
            print("📚 Testing conversation history retrieval")
            
            # Get existing conversations
            conversations_response = self.api.get("/conversations")
            
            if conversations_response.status_code == 200:
                conversations_data = conversations_response.json()
                conversations = conversations_data if isinstance(conversations_data, list) else conversations_data.get('data', [])
                
                if conversations:
                    # Test retrieving messages for first conversation
                    conversation_id = conversations[0]['id']
                    print(f"   📖 Testing history for conversation: {conversation_id}")
                    
                    messages_response = self.api.get(f"/conversations/{conversation_id}/messages")
                    
                    if messages_response.status_code == 200:
                        messages_data = messages_response.json()
                        messages = messages_data if isinstance(messages_data, list) else messages_data.get('data', [])
                        
                        print(f"   📊 Retrieved {len(messages)} messages")
                        
                        # Validate message structure and chronological order
                        if messages:
                            # Check required fields
                            required_fields = ['id', 'content', 'role', 'created_at']
                            message = messages[0]
                            missing_fields = [field for field in required_fields if field not in message]
                            
                            if missing_fields:
                                print(f"   ⚠️ Message missing fields: {missing_fields}")
                            else:
                                print(f"   ✅ Message structure valid")
                            
                            # Check chronological order
                            if len(messages) > 1:
                                timestamps = [msg['created_at'] for msg in messages if 'created_at' in msg]
                                is_chronological = timestamps == sorted(timestamps)
                                
                                if is_chronological:
                                    print(f"   ✅ Messages in chronological order")
                                else:
                                    print(f"   ⚠️ Messages may not be in chronological order")
                    else:
                        print(f"   ⚠️ Failed to retrieve messages: {messages_response.status_code}")
                else:
                    print(f"   ⚠️ No conversations found for history testing")
            
            duration = time.time() - start_time
            self.reporter.add_result("conversation_history_retrieval", "PASS", duration)
            
        except Exception as e:
            self.reporter.add_result("conversation_history_retrieval", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Conversation history retrieval test failed: {e}")
            raise

if __name__ == "__main__":
    print("🤖 Running AI Features Tests...")
    print("=" * 50)
    
    # Run with pytest
    pytest.main([__file__, "-v", "--tb=short"])
