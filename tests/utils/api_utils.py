#!/usr/bin/env python3
"""
API utility functions for testing
"""

import requests
import time
from typing import Dict, Optional

class APIUtils:
    """API utility functions"""
    
    def __init__(self, base_url: str):
        self.base_url = base_url
        self.session = requests.Session()
        self.session.headers.update({
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        })
    
    def login(self, email: str, password: str) -> Optional[Dict]:
        """Login and get session token"""
        try:
            login_data = {"email": email, "password": password}
            response = self.session.post(f"{self.base_url}/auth/login", json=login_data)
            
            if response.status_code == 200:
                return response.json()
            else:
                print(f"Login failed: {response.status_code} - {response.text}")
                return None
        except Exception as e:
            print(f"Login error: {e}")
            return None
    
    def logout(self) -> bool:
        """Logout current session"""
        try:
            response = self.session.post(f"{self.base_url}/auth/logout")
            return response.status_code == 200
        except Exception as e:
            print(f"Logout error: {e}")
            return False
    
    def get(self, endpoint: str, params: Dict = None) -> requests.Response:
        """Make GET request"""
        url = f"{self.base_url}{endpoint}"
        return self.session.get(url, params=params)
    
    def post(self, endpoint: str, data: Dict = None) -> requests.Response:
        """Make POST request"""
        url = f"{self.base_url}{endpoint}"
        return self.session.post(url, json=data)
    
    def put(self, endpoint: str, data: Dict = None) -> requests.Response:
        """Make PUT request"""
        url = f"{self.base_url}{endpoint}"
        return self.session.put(url, json=data)
    
    def delete(self, endpoint: str) -> requests.Response:
        """Make DELETE request"""
        url = f"{self.base_url}{endpoint}"
        return self.session.delete(url)

print("✅ API utilities loaded")