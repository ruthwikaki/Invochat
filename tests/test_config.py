#!/usr/bin/env python3
"""
Invochat Test Automation Suite - Configuration and Setup
Production-ready test automation for Invochat application
"""

import os
import json
import pytest
from datetime import datetime, timedelta
from dotenv import load_dotenv
from typing import Dict, List, Any, Optional

# Load environment variables
load_dotenv()

class TestConfig:
    """Test configuration and constants"""
    
    # Base URLs
    BASE_URL = os.getenv("BASE_URL", "http://localhost:3000")
    API_BASE_URL = f"{BASE_URL}/api"
    
    # Database Configuration
    SUPABASE_URL = os.getenv("NEXT_PUBLIC_SUPABASE_URL")
    SUPABASE_ANON_KEY = os.getenv("NEXT_PUBLIC_SUPABASE_ANON_KEY")
    SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
    
    # Test Data Paths
    TEST_DATA_DIR = "test_data"
    TEST_CREDENTIALS_FILE = os.path.join(TEST_DATA_DIR, "test_credentials.json")
    
    # Browser Configuration
    BROWSER_TIMEOUT = 30
    IMPLICIT_WAIT = 10
    EXPLICIT_WAIT = 20
    
    # Test Settings
    MAX_RETRIES = 3
    RETRY_DELAY = 2
    SCREENSHOT_DIR = "test_screenshots"
    REPORTS_DIR = "test_reports"
    
    # Performance Thresholds
    API_RESPONSE_THRESHOLD = 5.0  # seconds
    PAGE_LOAD_THRESHOLD = 10.0    # seconds
    DATABASE_QUERY_THRESHOLD = 2.0  # seconds
    
    @classmethod
    def validate_environment(cls) -> bool:
        """Validate that all required environment variables are set"""
        required_vars = [
            "NEXT_PUBLIC_SUPABASE_URL",
            "NEXT_PUBLIC_SUPABASE_ANON_KEY"
        ]
        
        missing_vars = []
        for var in required_vars:
            if not os.getenv(var):
                missing_vars.append(var)
        
        if missing_vars:
            raise EnvironmentError(f"Missing required environment variables: {', '.join(missing_vars)}")
        
        return True
    
    @classmethod
    def create_directories(cls):
        """Create necessary test directories"""
        directories = [cls.SCREENSHOT_DIR, cls.REPORTS_DIR, cls.TEST_DATA_DIR]
        for directory in directories:
            os.makedirs(directory, exist_ok=True)

class TestCredentials:
    """Test credentials management"""
    
    def __init__(self):
        self.credentials_file = TestConfig.TEST_CREDENTIALS_FILE
        self._credentials = self._load_credentials()
    
    def _load_credentials(self) -> Dict[str, Any]:
        """Load test credentials from file"""
        try:
            if os.path.exists(self.credentials_file):
                with open(self.credentials_file, 'r') as f:
                    return json.load(f)
            else:
                raise FileNotFoundError(f"Test credentials file not found: {self.credentials_file}")
        except Exception as e:
            print(f"Error loading credentials: {e}")
            raise
    
    def get_user_credentials(self, role: str = "Owner") -> Dict[str, str]:
        """Get credentials for a specific user role"""
        for user in self._credentials.get("test_users", []):
            if user.get("role") == role:
                return {
                    "email": user["email"],
                    "password": user["password"],
                    "company_name": user["company_name"]
                }
        
        # Return first user if role not found
        if self._credentials.get("test_users"):
            user = self._credentials["test_users"][0]
            return {
                "email": user["email"],
                "password": user["password"],
                "company_name": user["company_name"]
            }
        
        raise ValueError("No test users configured")
    
    def get_different_company_user(self, exclude_email: str = None) -> Dict[str, str]:
        """Get credentials for a user from a different company"""
        available_users = [user for user in self._credentials.get("test_users", []) 
                          if user.get("email") != exclude_email]
        
        if not available_users:
            raise ValueError("No alternative test users available")
        
        user = available_users[0]
        return {
            "email": user["email"],
            "password": user["password"],
            "company_name": user["company_name"]
        }
    
    def get_invalid_credentials(self) -> List[Dict[str, str]]:
        """Get invalid credentials for negative testing"""
        return self._credentials.get("invalid_credentials", [])

print("✅ Test configuration loaded successfully")
print(f"📊 Base URL: {TestConfig.BASE_URL}")