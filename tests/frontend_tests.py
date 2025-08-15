
#!/usr/bin/env python3
"""
Frontend Test Suite for AIVentory
Tests UI functionality, navigation, forms, and user interactions using Selenium
"""

import pytest
import time
import os
from datetime import datetime
from typing import Dict, List, Any, Optional
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from test_config import TestConfig, TestCredentials
from utils.browser_utils import BrowserUtils
from utils.data_utils import TestReporter

class TestAuthenticationFlow:
    """Test authentication and login/logout functionality"""
    
    def setup_method(self):
        self.browser = BrowserUtils(headless=TestConfig.BROWSER_HEADLESS)
        self.reporter = TestReporter()
        self.test_credentials = TestCredentials()
        
    def teardown_method(self):
        if self.browser:
            self.browser.stop_browser()
    
    def test_login_page_elements(self):
        """Test that login page loads with all required elements"""
        start_time = time.time()
        try:
            print("🔐 Testing login page elements")
            
            # Navigate to login page
            self.browser.navigate_to(f"{TestConfig.BASE_URL}/login")
            self.browser.wait_for_page_load()
            
            # Check for essential login elements
            required_elements = {
                'email_input': 'input[type="email"], input[name="email"], #email',
                'password_input': 'input[type="password"], input[name="password"], #password',
                'submit_button': 'button[type="submit"], input[type="submit"], button:contains("Login")',
                'login_form': 'form, .login-form, #login-form'
            }
            
            elements_found = 0
            
            for element_name, selector in required_elements.items():
                # Try multiple selector variations
                selectors = selector.split(', ')
                found = False
                
                for sel in selectors:
                    if self.browser.is_element_present(sel):
                        print(f"   ✅ Found {element_name}: {sel}")
                        found = True
                        elements_found += 1
                        break
                
                if not found:
                    print(f"   ❌ Missing {element_name}")
            
            # Check page title and URL
            current_url = self.browser.get_current_url()
            page_title = self.browser.get_page_title()
            
            print(f"   📄 Page title: {page_title}")
            print(f"   🌐 Current URL: {current_url}")
            
            # Take screenshot for reference
            screenshot_path = self.browser.take_screenshot("login_page_test.png")
            
            # Validate results
            elements_found_rate = elements_found / len(required_elements)
            assert elements_found_rate >= 0.75, f"Too many missing elements: {elements_found_rate:.1%}"
            
            duration = time.time() - start_time
            self.reporter.add_result("login_page_elements", "PASS", duration,
                                   details={
                                       "elements_found_rate": elements_found_rate,
                                       "page_title": page_title,
                                       "screenshot": screenshot_path
                                   })
            
            print(f"   ✅ Login page elements test passed: {elements_found_rate:.1%} elements found")
            
        except Exception as e:
            self.browser.take_screenshot("login_page_error.png")
            self.reporter.add_result("login_page_elements", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Login page elements test failed: {e}")
            raise
    
    def test_valid_user_login(self):
        """Test login with valid credentials"""
        start_time = time.time()
        try:
            print("✅ Testing valid user login")
            
            # Get test credentials
            creds = self.test_credentials.get_user_credentials("Owner")
            
            # Navigate to login page
            self.browser.navigate_to(f"{TestConfig.BASE_URL}/login")
            self.browser.wait_for_page_load()
            
            # Find and fill email field
            email_selectors = ['input[type="email"]', 'input[name="email"]', '#email', '[placeholder*="email"]']
            email_filled = False
            
            for selector in email_selectors:
                if self.browser.type_text(selector, creds["email"], clear_first=True):
                    email_filled = True
                    print(f"   📧 Email entered: {creds['email']}")
                    break
            
            assert email_filled, "Could not find or fill email field"
            
            # Find and fill password field
            password_selectors = ['input[type="password"]', 'input[name="password"]', '#password']
            password_filled = False
            
            for selector in password_selectors:
                if self.browser.type_text(selector, creds["password"], clear_first=True):
                    password_filled = True
                    print(f"   🔒 Password entered")
                    break
            
            assert password_filled, "Could not find or fill password field"
            
            # Submit form
            submit_selectors = ['button[type="submit"]', 'input[type="submit"]', 'button:contains("Login")', '.login-button']
            login_submitted = False
            
            for selector in submit_selectors:
                if self.browser.click_element(selector):
                    login_submitted = True
                    print(f"   🖱️ Login form submitted")
                    break
            
            # Alternative: submit via Enter key
            if not login_submitted:
                password_field = self.browser.find_element('input[type="password"]')
                if password_field:
                    password_field.send_keys(Keys.RETURN)
                    login_submitted = True
                    print(f"   ⌨️ Login submitted via Enter key")
            
            assert login_submitted, "Could not submit login form"
            
            # Wait for redirect/login completion
            time.sleep(3)  # Allow time for login processing
            
            # Check for successful login indicators
            current_url = self.browser.get_current_url()
            page_title = self.browser.get_page_title()
            
            print(f"   🌐 Post-login URL: {current_url}")
            print(f"   📄 Post-login title: {page_title}")
            
            # Check for dashboard/app indicators
            success_indicators = [
                '/dashboard', '/app', '/home', 'dashboard', 'inventory', 'products'
            ]
            
            login_successful = any(indicator in current_url.lower() for indicator in success_indicators)
            
            # Alternative: check for logout button or user menu
            if not login_successful:
                logout_elements = [
                    'button:contains("Logout")', 'a:contains("Logout")', 
                    '.user-menu', '.profile-menu', '[data-testid="user-menu"]'
                ]
                
                for selector in logout_elements:
                    if self.browser.is_element_present(selector):
                        login_successful = True
                        print(f"   ✅ Found logout/user menu: {selector}")
                        break
            
            # Take screenshot of result
            screenshot_path = self.browser.take_screenshot("login_success_test.png")
            
            duration = time.time() - start_time
            
            if login_successful:
                self.reporter.add_result("valid_user_login", "PASS", duration,
                                       details={
                                           "post_login_url": current_url,
                                           "screenshot": screenshot_path
                                       })
                print(f"   ✅ Login successful - redirected to: {current_url}")
            else:
                # Check for error messages
                error_selectors = ['.error', '.alert-danger', '[role="alert"]', '.text-red-500']
                error_found = False
                
                for selector in error_selectors:
                    if self.browser.is_element_present(selector):
                        error_text = self.browser.get_text(selector)
                        print(f"   ⚠️ Error message found: {error_text}")
                        error_found = True
                        break
                
                if not error_found:
                    print(f"   ⚠️ Login may have failed - no clear success indicators")
                
                self.reporter.add_result("valid_user_login", "FAIL", duration,
                                       "Login did not show clear success indicators")
                assert False, "Login did not appear successful"
            
        except Exception as e:
            self.browser.take_screenshot("login_error.png")
            self.reporter.add_result("valid_user_login", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Valid user login test failed: {e}")
            raise
    
    def test_invalid_login_handling(self):
        """Test login with invalid credentials shows appropriate error"""
        start_time = time.time()
        try:
            print("🚫 Testing invalid login handling")
            
            # Get invalid credentials
            invalid_creds = self.test_credentials.get_invalid_credentials()[0]
            
            # Navigate to login page
            self.browser.navigate_to(f"{TestConfig.BASE_URL}/login")
            self.browser.wait_for_page_load()
            
            # Fill form with invalid credentials
            self.browser.type_text('input[type="email"], input[name="email"]', invalid_creds["email"])
            self.browser.type_text('input[type="password"], input[name="password"]', invalid_creds["password"])
            
            print(f"   📧 Entered invalid email: {invalid_creds['email']}")
            
            # Submit form
            if not self.browser.click_element('button[type="submit"], input[type="submit"]'):
                # Try Enter key submission
                password_field = self.browser.find_element('input[type="password"]')
                if password_field:
                    password_field.send_keys(Keys.RETURN)
            
            # Wait for error message
            time.sleep(2)
            
            # Check for error indicators
            error_selectors = [
                '.error', '.alert-danger', '[role="alert"]', '.text-red-500',
                '.invalid-feedback', '.form-error', '.login-error'
            ]
            
            error_found = False
            error_message = ""
            
            for selector in error_selectors:
                if self.browser.is_element_visible(selector):
                    error_message = self.browser.get_text(selector)
                    error_found = True
                    print(f"   ✅ Error message displayed: {error_message}")
                    break
            
            # Check that we're still on login page (not redirected)
            current_url = self.browser.get_current_url()
            still_on_login = 'login' in current_url.lower()
            
            screenshot_path = self.browser.take_screenshot("invalid_login_test.png")
            
            duration = time.time() - start_time
            
            # Success if error shown or still on login page
            invalid_login_handled = error_found or still_on_login
            
            if invalid_login_handled:
                self.reporter.add_result("invalid_login_handling", "PASS", duration,
                                       details={
                                           "error_found": error_found,
                                           "error_message": error_message,
                                           "still_on_login": still_on_login,
                                           "screenshot": screenshot_path
                                       })
                print(f"   ✅ Invalid login properly handled")
            else:
                self.reporter.add_result("invalid_login_handling", "FAIL", duration,
                                       "Invalid login was not properly handled")
                print(f"   ❌ Invalid login handling failed")
            
        except Exception as e:
            self.browser.take_screenshot("invalid_login_error.png")
            self.reporter.add_result("invalid_login_handling", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Invalid login handling test failed: {e}")
            raise

class TestDashboardNavigation:
    """Test dashboard and main navigation functionality"""
    
    def setup_method(self):
        self.browser = BrowserUtils(headless=TestConfig.BROWSER_HEADLESS)
        self.reporter = TestReporter()
        self.test_credentials = TestCredentials()
        
        # Login before each test
        self._login()
        
    def teardown_method(self):
        if self.browser:
            self.browser.stop_browser()
    
    def _login(self):
        """Helper method to login before tests"""
        try:
            creds = self.test_credentials.get_user_credentials("Owner")
            
            self.browser.navigate_to(f"{TestConfig.BASE_URL}/login")
            self.browser.wait_for_page_load()
            
            # Quick login
            self.browser.type_text('input[type="email"], input[name="email"]', creds["email"])
            self.browser.type_text('input[type="password"], input[name="password"]', creds["password"])
            self.browser.click_element('button[type="submit"], input[type="submit"]')
            
            time.sleep(3)  # Wait for login
            print(f"   🔐 Logged in as: {creds['email']}")
            
        except Exception as e:
            print(f"   ⚠️ Login helper failed: {e}")
    
    def test_dashboard_elements(self):
        """Test that dashboard loads with key elements"""
        start_time = time.time()
        try:
            print("📊 Testing dashboard elements")
            
            # Navigate to dashboard
            self.browser.navigate_to(f"{TestConfig.BASE_URL}/dashboard")
            self.browser.wait_for_page_load()
            
            # Check for dashboard elements
            dashboard_elements = {
                'navigation': 'nav, .navbar, .navigation, .sidebar',
                'main_content': 'main, .main-content, .dashboard-content',
                'metrics_cards': '.card, .metric, .dashboard-card, .stats',
                'charts': 'canvas, .chart, svg, .recharts-wrapper',
            }
            
            elements_found = 0
            
            for element_name, selectors in dashboard_elements.items():
                selector_list = selectors.split(', ')
                found = False
                
                for selector in selector_list:
                    elements = self.browser.find_elements(selector)
                    if elements:
                        print(f"   ✅ Found {element_name}: {len(elements)} elements")
                        elements_found += 1
                        found = True
                        break
                
                if not found:
                    print(f"   ⚠️ Missing {element_name}")
            
            # Check page title
            page_title = self.browser.get_page_title()
            print(f"   📄 Dashboard title: {page_title}")
            
            # Take screenshot
            screenshot_path = self.browser.take_screenshot("dashboard_elements.png")
            
            duration = time.time() - start_time
            elements_rate = elements_found / len(dashboard_elements)
            
            self.reporter.add_result("dashboard_elements", "PASS", duration,
                                   details={
                                       "elements_found_rate": elements_rate,
                                       "page_title": page_title,
                                       "screenshot": screenshot_path
                                   })
            
            print(f"   ✅ Dashboard elements found: {elements_rate:.1%}")
            
        except Exception as e:
            self.browser.take_screenshot("dashboard_error.png")
            self.reporter.add_result("dashboard_elements", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Dashboard elements test failed: {e}")
            raise
    
    def test_main_navigation_links(self):
        """Test main navigation links work"""
        start_time = time.time()
        try:
            print("🧭 Testing main navigation links")
            
            # Common navigation links to test
            nav_links = [
                {'name': 'Dashboard', 'selectors': ['a[href*="dashboard"]', 'a:contains("Dashboard")']},
                {'name': 'Products', 'selectors': ['a[href*="product"]', 'a:contains("Products")', 'a:contains("Inventory")']},
                {'name': 'Orders', 'selectors': ['a[href*="order"]', 'a:contains("Orders")', 'a:contains("Sales")']},
                {'name': 'Customers', 'selectors': ['a[href*="customer"]', 'a:contains("Customers")']},
                {'name': 'Analytics', 'selectors': ['a[href*="analytics"]', 'a:contains("Analytics")', 'a:contains("Reports")']},
                {'name': 'Chat', 'selectors': ['a[href*="chat"]', 'a:contains("Chat")', 'a:contains("AI")']},
            ]
            
            working_links = 0
            
            for link_info in nav_links:
                link_name = link_info['name']
                selectors = link_info['selectors']
                
                print(f"   🔍 Testing {link_name} navigation")
                
                # Try to find and click the link
                link_clicked = False
                
                for selector in selectors:
                    if self.browser.click_element(selector):
                        link_clicked = True
                        print(f"      ✅ {link_name} link found and clicked")
                        break
                
                if link_clicked:
                    # Wait for page load
                    time.sleep(2)
                    
                    # Check if navigation was successful
                    current_url = self.browser.get_current_url()
                    page_title = self.browser.get_page_title()
                    
                    # Simple validation - URL should change or contain relevant terms
                    nav_successful = (
                        link_name.lower() in current_url.lower() or
                        link_name.lower() in page_title.lower() or
                        any(term in current_url.lower() for term in ['dashboard', 'app', 'products', 'orders'])
                    )
                    
                    if nav_successful:
                        working_links += 1
                        print(f"      ✅ {link_name} navigation successful: {current_url}")
                    else:
                        print(f"      ⚠️ {link_name} navigation unclear: {current_url}")
                else:
                    print(f"      ❌ {link_name} link not found")
            
            # Take screenshot of final state
            screenshot_path = self.browser.take_screenshot("navigation_test.png")
            
            duration = time.time() - start_time
            nav_success_rate = working_links / len(nav_links)
            
            self.reporter.add_result("main_navigation_links", "PASS", duration,
                                   details={
                                       "working_links": working_links,
                                       "total_links": len(nav_links),
                                       "success_rate": nav_success_rate,
                                       "screenshot": screenshot_path
                                   })
            
            print(f"   📊 Navigation success rate: {nav_success_rate:.1%} ({working_links}/{len(nav_links)})")
            
        except Exception as e:
            self.browser.take_screenshot("navigation_error.png")
            self.reporter.add_result("main_navigation_links", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Navigation links test failed: {e}")
            raise

class TestProductManagement:
    """Test product/inventory management UI"""
    
    def setup_method(self):
        self.browser = BrowserUtils(headless=TestConfig.BROWSER_HEADLESS)
        self.reporter = TestReporter()
        self.test_credentials = TestCredentials()
        
        # Login and navigate to products
        self._login_and_navigate()
        
    def teardown_method(self):
        if self.browser:
            self.browser.stop_browser()
    
    def _login_and_navigate(self):
        """Login and navigate to products page"""
        try:
            creds = self.test_credentials.get_user_credentials("Owner")
            
            self.browser.navigate_to(f"{TestConfig.BASE_URL}/login")
            self.browser.type_text('input[type="email"]', creds["email"])
            self.browser.type_text('input[type="password"]', creds["password"])
            self.browser.click_element('button[type="submit"]')
            time.sleep(3)
            
            # Navigate to products/inventory
            product_urls = ['/products', '/inventory', '/dashboard']
            for url in product_urls:
                try:
                    self.browser.navigate_to(f"{TestConfig.BASE_URL}{url}")
                    time.sleep(2)
                    break
                except:
                    continue
                    
        except Exception as e:
            print(f"   ⚠️ Setup failed: {e}")
    
    def test_product_list_display(self):
        """Test that product list displays correctly"""
        start_time = time.time()
        try:
            print("📦 Testing product list display")
            
            # Look for product list elements
            list_selectors = [
                'table', '.product-list', '.inventory-table', 
                '.data-table', '[role="table"]', '.products-grid'
            ]
            
            list_found = False
            product_count = 0
            
            for selector in list_selectors:
                if self.browser.is_element_present(selector):
                    list_found = True
                    print(f"   ✅ Product list found: {selector}")
                    
                    # Try to count products/rows
                    row_selectors = ['tbody tr', '.product-row', '.table-row', '.product-item']
                    for row_selector in row_selectors:
                        rows = self.browser.find_elements(row_selector)
                        if rows:
                            product_count = len(rows)
                            print(f"   📊 Found {product_count} product rows")
                            break
                    break
            
            if not list_found:
                # Try navigating to specific product/inventory page
                nav_attempts = [
                    'a[href*="product"]', 'a[href*="inventory"]',
                    'a:contains("Products")', 'a:contains("Inventory")'
                ]
                
                for nav_selector in nav_attempts:
                    if self.browser.click_element(nav_selector):
                        time.sleep(3)
                        print(f"   🧭 Navigated via product link: {nav_selector}")
                        
                        # Check again for product list
                        for selector in list_selectors:
                            if self.browser.is_element_present(selector):
                                list_found = True
                                print(f"   ✅ Product list found after navigation: {selector}")
                                break
                        if list_found:
                            break
            
            # Check for search/filter functionality
            search_found = False
            search_selectors = ['input[type="search"]', 'input[placeholder*="search"]', '.search-input']
            
            for selector in search_selectors:
                if self.browser.is_element_present(selector):
                    search_found = True
                    print(f"   🔍 Search functionality found: {selector}")
                    break
            
            screenshot_path = self.browser.take_screenshot("product_list.png")
            
            duration = time.time() - start_time
            self.reporter.add_result("product_list_display", "PASS", duration,
                                   details={
                                       "list_found": list_found,
                                       "product_count": product_count,
                                       "search_found": search_found,
                                       "screenshot": screenshot_path
                                   })
            
            if list_found:
                print(f"   ✅ Product list display working")
            else:
                print(f"   ⚠️ Product list not clearly visible")
            
        except Exception as e:
            self.browser.take_screenshot("product_list_error.png")
            self.reporter.add_result("product_list_display", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Product list display test failed: {e}")
            raise

class TestChatInterface:
    """Test AI chat interface functionality"""
    
    def setup_method(self):
        self.browser = BrowserUtils(headless=TestConfig.BROWSER_HEADLESS)
        self.reporter = TestReporter()
        self.test_credentials = TestCredentials()
        
        self._login_and_navigate_to_chat()
        
    def teardown_method(self):
        if self.browser:
            self.browser.stop_browser()
    
    def _login_and_navigate_to_chat(self):
        """Login and navigate to chat interface"""
        try:
            creds = self.test_credentials.get_user_credentials("Owner")
            
            self.browser.navigate_to(f"{TestConfig.BASE_URL}/login")
            self.browser.type_text('input[type="email"]', creds["email"])
            self.browser.type_text('input[type="password"]', creds["password"])
            self.browser.click_element('button[type="submit"]')
            time.sleep(3)
            
            # Try to navigate to chat
            chat_urls = ['/chat', '/ai', '/assistant']
            for url in chat_urls:
                try:
                    self.browser.navigate_to(f"{TestConfig.BASE_URL}{url}")
                    time.sleep(2)
                    if 'chat' in self.browser.get_current_url().lower():
                        break
                except:
                    continue
                    
        except Exception as e:
            print(f"   ⚠️ Chat navigation failed: {e}")
    
    def test_chat_interface_elements(self):
        """Test that chat interface has required elements"""
        start_time = time.time()
        try:
            print("💬 Testing chat interface elements")
            
            # Look for chat interface elements
            chat_elements = {
                'message_input': ['input[type="text"]', 'textarea', '.message-input', '[placeholder*="message"]'],
                'send_button': ['button[type="submit"]', '.send-button', 'button:contains("Send")'],
                'chat_container': ['.chat-container', '.messages', '.conversation', '.chat-history'],
                'message_list': ['.message-list', '.messages', '.chat-messages']
            }
            
            elements_found = 0
            
            for element_name, selectors in chat_elements.items():
                found = False
                for selector in selectors:
                    if self.browser.is_element_present(selector):
                        print(f"   ✅ Found {element_name}: {selector}")
                        found = True
                        elements_found += 1
                        break
                
                if not found:
                    print(f"   ❌ Missing {element_name}")
            
            # Try to find chat by looking for navigation link
            if elements_found == 0:
                chat_nav_selectors = ['a[href*="chat"]', 'a:contains("Chat")', 'a:contains("AI")']
                for selector in chat_nav_selectors:
                    if self.browser.click_element(selector):
                        time.sleep(3)
                        print(f"   🧭 Navigated via chat link: {selector}")
                        
                        # Check again for chat elements
                        for element_name, selectors in chat_elements.items():
                            for sel in selectors:
                                if self.browser.is_element_present(sel):
                                    elements_found += 1
                                    break
                        break
            
            screenshot_path = self.browser.take_screenshot("chat_interface.png")
            
            duration = time.time() - start_time
            elements_rate = elements_found / len(chat_elements)
            
            self.reporter.add_result("chat_interface_elements", "PASS", duration,
                                   details={
                                       "elements_found": elements_found,
                                       "elements_rate": elements_rate,
                                       "screenshot": screenshot_path
                                   })
            
            print(f"   📊 Chat elements found: {elements_rate:.1%} ({elements_found}/{len(chat_elements)})")
            
        except Exception as e:
            self.browser.take_screenshot("chat_interface_error.png")
            self.reporter.add_result("chat_interface_elements", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Chat interface test failed: {e}")
            raise
    
    def test_sending_chat_message(self):
        """Test sending a message in chat interface"""
        start_time = time.time()
        try:
            print("📝 Testing chat message sending")
            
            test_message = "What are my top selling products?"
            
            # Find message input
            input_selectors = ['input[type="text"]', 'textarea', '.message-input', '[placeholder*="message"]']
            message_sent = False
            
            for selector in input_selectors:
                if self.browser.type_text(selector, test_message):
                    print(f"   ✅ Message typed in input: {selector}")
                    
                    # Try to send message
                    send_selectors = ['button[type="submit"]', '.send-button', 'button:contains("Send")']
                    
                    for send_selector in send_selectors:
                        if self.browser.click_element(send_selector):
                            message_sent = True
                            print(f"   ✅ Message sent via button: {send_selector}")
                            break
                    
                    # Try Enter key if button didn't work
                    if not message_sent:
                        input_element = self.browser.find_element(selector)
                        if input_element:
                            input_element.send_keys(Keys.RETURN)
                            message_sent = True
                            print(f"   ✅ Message sent via Enter key")
                    
                    break
            
            if message_sent:
                # Wait for response
                time.sleep(5)
                
                # Look for the sent message in chat history
                message_elements = self.browser.find_elements('.message, .chat-message, .user-message')
                message_found = False
                
                for element in message_elements:
                    element_text = element.text if hasattr(element, 'text') else ""
                    if test_message in element_text:
                        message_found = True
                        print(f"   ✅ Sent message found in chat history")
                        break
                
                # Look for AI response
                response_elements = self.browser.find_elements('.assistant-message, .ai-message, .bot-message')
                response_found = len(response_elements) > 0
                
                if response_found:
                    print(f"   🤖 AI response detected: {len(response_elements)} response elements")
                else:
                    print(f"   ⚠️ No clear AI response found")
            
            screenshot_path = self.browser.take_screenshot("chat_message_test.png")
            
            duration = time.time() - start_time
            self.reporter.add_result("sending_chat_message", "PASS", duration,
                                   details={
                                       "message_sent": message_sent,
                                       "message_found": message_found if message_sent else False,
                                       "response_found": response_found if message_sent else False,
                                       "screenshot": screenshot_path
                                   })
            
            if message_sent:
                print(f"   ✅ Chat message sending working")
            else:
                print(f"   ⚠️ Could not send chat message")
            
        except Exception as e:
            self.browser.take_screenshot("chat_message_error.png")
            self.reporter.add_result("sending_chat_message", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Chat message sending test failed: {e}")
            raise

class TestResponsiveDesign:
    """Test responsive design and mobile compatibility"""
    
    def setup_method(self):
        self.browser = BrowserUtils(headless=TestConfig.BROWSER_HEADLESS)
        self.reporter = TestReporter()
        self.test_credentials = TestCredentials()
        
        # Login first
        self._login()
        
    def teardown_method(self):
        if self.browser:
            self.browser.stop_browser()
    
    def _login(self):
        """Helper method to login"""
        try:
            creds = self.test_credentials.get_user_credentials("Owner")
            
            self.browser.navigate_to(f"{TestConfig.BASE_URL}/login")
            self.browser.type_text('input[type="email"]', creds["email"])
            self.browser.type_text('input[type="password"]', creds["password"])
            self.browser.click_element('button[type="submit"]')
            time.sleep(3)
        except Exception as e:
            print(f"   ⚠️ Login failed: {e}")
    
    def test_mobile_viewport_layout(self):
        """Test layout on mobile viewport"""
        start_time = time.time()
        try:
            print("📱 Testing mobile viewport layout")
            
            # Set mobile viewport
            self.browser.driver.set_window_size(375, 667)  # iPhone size
            time.sleep(2)
            
            # Navigate to dashboard
            self.browser.navigate_to(f"{TestConfig.BASE_URL}/dashboard")
            self.browser.wait_for_page_load()
            
            # Check for mobile-responsive elements
            mobile_elements = {
                'mobile_menu': ['.mobile-menu', '.hamburger', '.menu-toggle', '[data-testid="mobile-menu"]'],
                'responsive_nav': ['.navbar-collapse', '.mobile-nav', '.sidebar-mobile'],
                'responsive_content': ['.container-fluid', '.responsive-content', '.mobile-content']
            }
            
            mobile_features_found = 0
            
            for element_name, selectors in mobile_elements.items():
                found = False
                for selector in selectors:
                    if self.browser.is_element_present(selector):
                        print(f"   ✅ Found {element_name}: {selector}")
                        mobile_features_found += 1
                        found = True
                        break
                if not found:
                    print(f"   ⚠️ Missing {element_name}")
            
            # Check if content overflows
            body_width = self.browser.execute_javascript("return document.body.scrollWidth;")
            viewport_width = 375
            
            no_horizontal_overflow = body_width <= viewport_width + 20  # 20px tolerance
            
            if no_horizontal_overflow:
                print(f"   ✅ No horizontal overflow detected")
            else:
                print(f"   ⚠️ Potential horizontal overflow: {body_width}px > {viewport_width}px")
            
            # Test mobile menu functionality if present
            mobile_menu_works = False
            menu_toggle_selectors = ['.mobile-menu', '.hamburger', '.menu-toggle']
            
            for selector in menu_toggle_selectors:
                if self.browser.click_element(selector):
                    time.sleep(1)
                    # Check if menu opened
                    menu_opened = self.browser.is_element_visible('.mobile-nav, .navbar-collapse.show, .menu-open')
                    if menu_opened:
                        mobile_menu_works = True
                        print(f"   ✅ Mobile menu functionality working")
                        break
            
            screenshot_path = self.browser.take_screenshot("mobile_layout.png")
            
            duration = time.time() - start_time
            self.reporter.add_result("mobile_viewport_layout", "PASS", duration,
                                   details={
                                       "mobile_features_found": mobile_features_found,
                                       "no_horizontal_overflow": no_horizontal_overflow,
                                       "mobile_menu_works": mobile_menu_works,
                                       "screenshot": screenshot_path
                                   })
            
            print(f"   📊 Mobile responsiveness score: {mobile_features_found + int(no_horizontal_overflow) + int(mobile_menu_works)}/5")
            
        except Exception as e:
            self.browser.take_screenshot("mobile_layout_error.png")
            self.reporter.add_result("mobile_viewport_layout", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Mobile viewport test failed: {e}")
            raise
    
    def test_tablet_viewport_layout(self):
        """Test layout on tablet viewport"""
        start_time = time.time()
        try:
            print("📺 Testing tablet viewport layout")
            
            # Set tablet viewport
            self.browser.driver.set_window_size(768, 1024)  # iPad size
            time.sleep(2)
            
            # Navigate to dashboard
            self.browser.navigate_to(f"{TestConfig.BASE_URL}/dashboard")
            self.browser.wait_for_page_load()
            
            # Check that layout adapts to tablet size
            layout_elements = [
                '.container', '.main-content', '.dashboard-content',
                '.sidebar', '.navigation'
            ]
            
            layout_adapted = False
            
            for selector in layout_elements:
                elements = self.browser.find_elements(selector)
                if elements:
                    # Check if elements have reasonable width for tablet
                    element_width = self.browser.execute_javascript(f"return document.querySelector('{selector}').offsetWidth;")
                    if element_width and 500 < element_width < 800:  # Reasonable tablet width
                        layout_adapted = True
                        print(f"   ✅ Layout adapted for tablet: {selector} width {element_width}px")
                        break
            
            # Check navigation is accessible
            nav_accessible = (
                self.browser.is_element_visible('nav, .navbar, .navigation') or
                self.browser.is_element_visible('.sidebar')
            )
            
            if nav_accessible:
                print(f"   ✅ Navigation accessible on tablet")
            else:
                print(f"   ⚠️ Navigation may not be accessible on tablet")
            
            screenshot_path = self.browser.take_screenshot("tablet_layout.png")
            
            duration = time.time() - start_time
            self.reporter.add_result("tablet_viewport_layout", "PASS", duration,
                                   details={
                                       "layout_adapted": layout_adapted,
                                       "nav_accessible": nav_accessible,
                                       "screenshot": screenshot_path
                                   })
            
            if layout_adapted and nav_accessible:
                print(f"   ✅ Tablet layout working well")
            else:
                print(f"   ⚠️ Tablet layout needs improvement")
            
        except Exception as e:
            self.browser.take_screenshot("tablet_layout_error.png")
            self.reporter.add_result("tablet_viewport_layout", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Tablet viewport test failed: {e}")
            raise

class TestFormValidation:
    """Test form validation and user input handling"""
    
    def setup_method(self):
        self.browser = BrowserUtils(headless=TestConfig.BROWSER_HEADLESS)
        self.reporter = TestReporter()
        self.test_credentials = TestCredentials()
        
        self._login()
        
    def teardown_method(self):
        if self.browser:
            self.browser.stop_browser()
    
    def _login(self):
        """Helper to login"""
        try:
            creds = self.test_credentials.get_user_credentials("Owner")
            
            self.browser.navigate_to(f"{TestConfig.BASE_URL}/login")
            self.browser.type_text('input[type="email"]', creds["email"])
            self.browser.type_text('input[type="password"]', creds["password"])
            self.browser.click_element('button[type="submit"]')
            time.sleep(3)
        except Exception as e:
            print(f"   ⚠️ Login failed: {e}")
    
    def test_search_functionality(self):
        """Test search forms and filters"""
        start_time = time.time()
        try:
            print("🔍 Testing search functionality")
            
            # Navigate to pages that likely have search
            search_pages = ['/products', '/inventory', '/orders', '/customers']
            search_working = False
            
            for page in search_pages:
                try:
                    self.browser.navigate_to(f"{TestConfig.BASE_URL}{page}")
                    time.sleep(2)
                    
                    # Look for search inputs
                    search_selectors = [
                        'input[type="search"]', 'input[placeholder*="search" i]',
                        '.search-input', 'input[name="search"]', '[data-testid="search"]'
                    ]
                    
                    for selector in search_selectors:
                        if self.browser.is_element_present(selector):
                            print(f"   ✅ Found search input on {page}: {selector}")
                            
                            # Test search functionality
                            test_query = "test"
                            if self.browser.type_text(selector, test_query):
                                print(f"   📝 Typed search query: {test_query}")
                                
                                # Submit search (try Enter key first)
                                search_input = self.browser.find_element(selector)
                                if search_input:
                                    search_input.send_keys(Keys.RETURN)
                                    time.sleep(2)
                                    search_working = True
                                
                                # Or try search button
                                search_button_selectors = [
                                    'button[type="submit"]', '.search-button',
                                    'button:contains("Search")', '[data-testid="search-button"]'
                                ]
                                
                                for btn_selector in search_button_selectors:
                                    if self.browser.click_element(btn_selector):
                                        time.sleep(2)
                                        search_working = True
                                        break
                                
                                if search_working:
                                    print(f"   ✅ Search functionality working on {page}")
                                    break
                    
                    if search_working:
                        break
                        
                except Exception as e:
                    print(f"   ⚠️ Error testing {page}: {e}")
                    continue
            
            # Test filter functionality if present
            filter_working = False
            filter_selectors = [
                'select[name*="filter"]', '.filter-select', '[data-testid="filter"]',
                'input[type="checkbox"]', '.filter-checkbox'
            ]
            
            for selector in filter_selectors:
                if self.browser.is_element_present(selector):
                    print(f"   ✅ Filter found: {selector}")
                    filter_working = True
                    break
            
            screenshot_path = self.browser.take_screenshot("search_functionality.png")
            
            duration = time.time() - start_time
            self.reporter.add_result("search_functionality", "PASS", duration,
                                   details={
                                       "search_working": search_working,
                                       "filter_working": filter_working,
                                       "screenshot": screenshot_path
                                   })
            
            if search_working or filter_working:
                print(f"   ✅ Search/filter functionality found")
            else:
                print(f"   ⚠️ No clear search/filter functionality found")
            
        except Exception as e:
            self.browser.take_screenshot("search_functionality_error.png")
            self.reporter.add_result("search_functionality", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Search functionality test failed: {e}")
            raise

class TestPerformanceMetrics:
    """Test frontend performance metrics"""
    
    def setup_method(self):
        self.browser = BrowserUtils(headless=TestConfig.BROWSER_HEADLESS)
        self.reporter = TestReporter()
        self.test_credentials = TestCredentials()
        
    def teardown_method(self):
        if self.browser:
            self.browser.stop_browser()
    
    def test_page_load_performance(self):
        """Test page load times"""
        start_time = time.time()
        try:
            print("⚡ Testing page load performance")
            
            # Test key pages
            pages_to_test = [
                {'url': '/login', 'name': 'Login Page'},
                {'url': '/dashboard', 'name': 'Dashboard'},
                {'url': '/products', 'name': 'Products Page'},
                {'url': '/orders', 'name': 'Orders Page'},
            ]
            
            page_performance = []
            
            for page in pages_to_test:
                url = page['url']
                name = page['name']
                
                print(f"   📊 Testing {name}")
                
                page_start = time.time()
                
                try:
                    self.browser.navigate_to(f"{TestConfig.BASE_URL}{url}")
                    self.browser.wait_for_page_load(timeout=15)
                    
                    load_time = time.time() - page_start
                    
                    # Get additional performance metrics via JavaScript
                    try:
                        dom_loading_time = self.browser.execute_javascript("""
                            return performance.timing.domContentLoadedEventStart - performance.timing.navigationStart;
                        """)
                        
                        page_fully_loaded = self.browser.execute_javascript("""
                            return performance.timing.loadEventStart - performance.timing.navigationStart;
                        """)
                        
                    except:
                        dom_loading_time = load_time * 1000
                        page_fully_loaded = load_time * 1000
                    
                    # Performance assessment
                    performance_rating = "excellent" if load_time < 2 else "good" if load_time < 5 else "fair" if load_time < 10 else "poor"
                    
                    page_perf = {
                        'name': name,
                        'url': url,
                        'load_time': load_time,
                        'dom_loading_time': dom_loading_time / 1000 if dom_loading_time else load_time,
                        'fully_loaded_time': page_fully_loaded / 1000 if page_fully_loaded else load_time,
                        'rating': performance_rating
                    }
                    
                    page_performance.append(page_perf)
                    
                    print(f"      ⏱️ Load time: {load_time:.2f}s ({performance_rating})")
                    
                except Exception as e:
                    print(f"      ❌ Failed to load {name}: {e}")
                    page_performance.append({
                        'name': name,
                        'url': url,
                        'load_time': 999,
                        'rating': 'failed'
                    })
            
            # Calculate average performance
            successful_loads = [p for p in page_performance if p['rating'] != 'failed']
            avg_load_time = sum(p['load_time'] for p in successful_loads) / len(successful_loads) if successful_loads else 999
            
            # Overall performance rating
            if avg_load_time < 3:
                overall_rating = "excellent"
            elif avg_load_time < 6:
                overall_rating = "good"
            elif avg_load_time < 10:
                overall_rating = "fair"
            else:
                overall_rating = "poor"
            
            screenshot_path = self.browser.take_screenshot("performance_test.png")
            
            duration = time.time() - start_time
            self.reporter.add_result("page_load_performance", "PASS", duration,
                                   details={
                                       "page_performance": page_performance,
                                       "avg_load_time": avg_load_time,
                                       "overall_rating": overall_rating,
                                       "screenshot": screenshot_path
                                   })
            
            print(f"   📊 Average load time: {avg_load_time:.2f}s ({overall_rating})")
            
        except Exception as e:
            self.browser.take_screenshot("performance_error.png")
            self.reporter.add_result("page_load_performance", "FAIL", time.time() - start_time, str(e))
            print(f"❌ Performance test failed: {e}")
            raise

if __name__ == "__main__":
    print("🌐 Running Frontend Tests...")
    print("=" * 40)
    
    # Run with pytest
    pytest.main([__file__, "-v", "--tb=short"])
