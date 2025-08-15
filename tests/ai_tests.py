
#!/usr/bin/env python3
"""
AI Features Test Suite for AIVentory
Tests AI chat functionality, conversation management, and AI tool responses
"""

import pytest
import time
import json
import uuid
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
                    "conversationId": str(uuid.uuid4())
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
                    print(f"      ❌ Message failed: {message_response.status_code} - {message_response.text}")
            
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

if __name__ == "__main__":
    print("🤖 Running AI Features Tests...")
    print("=" * 50)
    
    # Run with pytest
    pytest.main([__file__, "-v", "--tb=short"])
