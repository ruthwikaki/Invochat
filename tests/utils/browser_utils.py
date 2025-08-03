"""
Browser automation utilities for frontend testing
"""

import time
import os
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.chrome.options import Options
from webdriver_manager.chrome import ChromeDriverManager
from typing import Optional, List, Dict

class BrowserUtils:
    """Browser automation utilities"""
    
    def __init__(self, headless: bool = True, timeout: int = 30):
        self.headless = headless
        self.timeout = timeout
        self.driver: Optional[webdriver.Chrome] = None
        self.wait: Optional[WebDriverWait] = None
    
    def start_browser(self):
        """Initialize and start the browser"""
        chrome_options = Options()
        
        if self.headless:
            chrome_options.add_argument("--headless")
        
        chrome_options.add_argument("--no-sandbox")
        chrome_options.add_argument("--disable-dev-shm-usage")
        chrome_options.add_argument("--disable-gpu")
        chrome_options.add_argument("--window-size=1920,1080")
        chrome_options.add_argument("--disable-blink-features=AutomationControlled")
        chrome_options.add_experimental_option("excludeSwitches", ["enable-automation"])
        chrome_options.add_experimental_option('useAutomationExtension', False)
        
        # Set up Chrome driver
        service = Service(ChromeDriverManager().install())
        self.driver = webdriver.Chrome(service=service, options=chrome_options)
        self.driver.execute_script("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})")
        
        self.wait = WebDriverWait(self.driver, self.timeout)
        
        print(f"✅ Browser started ({'headless' if self.headless else 'visible'})")
    
    def stop_browser(self):
        """Stop and cleanup the browser"""
        if self.driver:
            self.driver.quit()
            print("✅ Browser stopped")
    
    def navigate_to(self, url: str):
        """Navigate to a URL"""
        if not self.driver:
            self.start_browser()
        
        self.driver.get(url)
        print(f"🌐 Navigated to: {url}")
    
    def wait_for_element(self, selector: str, by: By = By.CSS_SELECTOR, timeout: int = None) -> bool:
        """Wait for an element to be present"""
        try:
            wait_timeout = timeout or self.timeout
            wait = WebDriverWait(self.driver, wait_timeout)
            wait.until(EC.presence_of_element_located((by, selector)))
            return True
        except Exception as e:
            print(f"⚠️ Element not found: {selector} - {e}")
            return False
    
    def find_element(self, selector: str, by: By = By.CSS_SELECTOR):
        """Find an element"""
        try:
            return self.driver.find_element(by, selector)
        except Exception as e:
            print(f"⚠️ Element not found: {selector} - {e}")
            return None
    
    def find_elements(self, selector: str, by: By = By.CSS_SELECTOR):
        """Find multiple elements"""
        try:
            return self.driver.find_elements(by, selector)
        except Exception as e:
            print(f"⚠️ Elements not found: {selector} - {e}")
            return []
    
    def click_element(self, selector: str, by: By = By.CSS_SELECTOR) -> bool:
        """Click an element"""
        try:
            element = self.wait.until(EC.element_to_be_clickable((by, selector)))
            element.click()
            print(f"🖱️ Clicked: {selector}")
            return True
        except Exception as e:
            print(f"⚠️ Could not click: {selector} - {e}")
            return False
    
    def type_text(self, selector: str, text: str, by: By = By.CSS_SELECTOR, clear_first: bool = True) -> bool:
        """Type text into an element"""
        try:
            element = self.wait.until(EC.presence_of_element_located((by, selector)))
            if clear_first:
                element.clear()
            element.send_keys(text)
            print(f"⌨️ Typed '{text}' into: {selector}")
            return True
        except Exception as e:
            print(f"⚠️ Could not type into: {selector} - {e}")
            return False
    
    def get_text(self, selector: str, by: By = By.CSS_SELECTOR) -> Optional[str]:
        """Get text from an element"""
        try:
            element = self.wait.until(EC.presence_of_element_located((by, selector)))
            return element.text
        except Exception as e:
            print(f"⚠️ Could not get text from: {selector} - {e}")
            return None
    
    def get_attribute(self, selector: str, attribute: str, by: By = By.CSS_SELECTOR) -> Optional[str]:
        """Get attribute value from an element"""
        try:
            element = self.wait.until(EC.presence_of_element_located((by, selector)))
            return element.get_attribute(attribute)
        except Exception as e:
            print(f"⚠️ Could not get {attribute} from: {selector} - {e}")
            return None
    
    def is_element_present(self, selector: str, by: By = By.CSS_SELECTOR) -> bool:
        """Check if an element is present"""
        try:
            self.driver.find_element(by, selector)
            return True
        except:
            return False
    
    def is_element_visible(self, selector: str, by: By = By.CSS_SELECTOR) -> bool:
        """Check if an element is visible"""
        try:
            element = self.driver.find_element(by, selector)
            return element.is_displayed()
        except:
            return False
    
    def wait_for_page_load(self, timeout: int = None):
        """Wait for page to fully load"""
        wait_timeout = timeout or self.timeout
        try:
            WebDriverWait(self.driver, wait_timeout).until(
                lambda driver: driver.execute_script("return document.readyState") == "complete"
            )
            print("✅ Page loaded")
        except Exception as e:
            print(f"⚠️ Page load timeout: {e}")
    
    def take_screenshot(self, filename: str = None) -> str:
        """Take a screenshot"""
        if not filename:
            timestamp = int(time.time())
            filename = f"screenshot_{timestamp}.png"
        
        filepath = os.path.join("test_screenshots", filename)
        os.makedirs("test_screenshots", exist_ok=True)
        
        try:
            self.driver.save_screenshot(filepath)
            print(f"📸 Screenshot saved: {filepath}")
            return filepath
        except Exception as e:
            print(f"⚠️ Could not take screenshot: {e}")
            return ""
    
    def scroll_to_element(self, selector: str, by: By = By.CSS_SELECTOR) -> bool:
        """Scroll to an element"""
        try:
            element = self.driver.find_element(by, selector)
            self.driver.execute_script("arguments[0].scrollIntoView(true);", element)
            time.sleep(0.5)  # Small delay for smooth scrolling
            return True
        except Exception as e:
            print(f"⚠️ Could not scroll to: {selector} - {e}")
            return False
    
    def execute_javascript(self, script: str, *args):
        """Execute JavaScript"""
        try:
            return self.driver.execute_script(script, *args)
        except Exception as e:
            print(f"⚠️ JavaScript execution failed: {e}")
            return None
    
    def get_current_url(self) -> str:
        """Get current URL"""
        return self.driver.current_url if self.driver else ""
    
    def get_page_title(self) -> str:
        """Get page title"""
        return self.driver.title if self.driver else ""
    
    def refresh_page(self):
        """Refresh the current page"""
        if self.driver:
            self.driver.refresh()
            print("🔄 Page refreshed")
    
    def go_back(self):
        """Go back to previous page"""
        if self.driver:
            self.driver.back()
            print("⬅️ Navigated back")
    
    def switch_to_tab(self, tab_index: int = -1):
        """Switch to a different tab"""
        try:
            handles = self.driver.window_handles
            if tab_index == -1:  # Switch to last tab
                self.driver.switch_to.window(handles[-1])
            else:
                self.driver.switch_to.window(handles[tab_index])
            print(f"🔄 Switched to tab {tab_index}")
        except Exception as e:
            print(f"⚠️ Could not switch tab: {e}")

print("✅ Browser utilities loaded")