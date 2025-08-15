
#!/usr/bin/env python3
"""
Pytest configuration and fixtures for AIVentory test suite
Global configuration, fixtures, and test utilities
"""

import pytest
import os
import sys
import time
import tempfile
from datetime import datetime
from typing import Dict, List, Any, Generator

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from test_config import TestConfig, TestCredentials
from utils.api_utils import APIUtils
from utils.database_utils import DatabaseUtils
from utils.browser_utils import BrowserUtils
from utils.data_utils import TestReporter

# Pytest configuration
def pytest_configure(config):
    """Configure pytest with custom markers and settings"""
    
    # Add custom markers
    config.addinivalue_line(
        "markers", "slow: marks tests as slow (deselect with '-m \"not slow\"')"
    )
    config.addinivalue_line(
        "markers", "integration: marks tests as integration tests"
    )
    config.addinivalue_line(
        "markers", "frontend: marks tests as frontend/UI tests"
    )
    config.addinivalue_line(
        "markers", "api: marks tests as API tests"
    )
    config.addinivalue_line(
        "markers", "database: marks tests as database tests"
    )
    config.addinivalue_line(
        "markers", "business_logic: marks tests as business logic validation"
    )
    config.addinivalue_line(
        "markers", "ai: marks tests as AI functionality tests"
    )
    config.addinivalue_line(
        "markers", "requires_data: marks tests that require existing test data"
    )
    config.addinivalue_line(
        "markers", "requires_login: marks tests that require user authentication"
    )
    
    # Set up test environment
    TestConfig.create_directories()
    
    print("\n🧪 AIVentory Test Suite Configuration")
    print("=" * 50)
    print(f"Base URL: {TestConfig.BASE_URL}")
    print(f"Browser Headless: {os.getenv('BROWSER_HEADLESS', 'true')}")
    print(f"Test Timeout: {TestConfig.MAX_RETRIES}s")
    print("=" * 50)

def pytest_collection_modifyitems(config, items):
    """Modify test collection to add markers automatically"""
    
    for item in items:
        # Auto-mark based on file names
        if "frontend" in item.fspath.basename:
            item.add_marker(pytest.mark.frontend)
        elif "api" in item.fspath.basename:
            item.add_marker(pytest.mark.api)
        elif "database" in item.fspath.basename:
            item.add_marker(pytest.mark.database)
        elif "business_logic" in item.fspath.basename:
            item.add_marker(pytest.mark.business_logic)
        elif "ai" in item.fspath.basename:
            item.add_marker(pytest.mark.ai)
        
        # Auto-mark integration tests
        if any(keyword in item.name.lower() for keyword in ['integration', 'end_to_end', 'e2e']):
            item.add_marker(pytest.mark.integration)
        
        # Auto-mark slow tests
        if any(keyword in item.name.lower() for keyword in ['performance', 'load', 'stress', 'comprehensive']):
            item.add_marker(pytest.mark.slow)
        
        # Auto-mark tests that require data
        if any(keyword in item.name.lower() for keyword in ['business_logic', 'calculation', 'accuracy']):
            item.add_marker(pytest.mark.requires_data)
        
        # Auto-mark tests that require login
        if any(keyword in item.name.lower() for keyword in ['dashboard', 'navigation', 'authenticated', 'chat']):
            item.add_marker(pytest.mark.requires_login)

@pytest.fixture(scope="session")
def test_config():
    """Global test configuration fixture"""
    try:
        TestConfig.validate_environment()
        return TestConfig
    except Exception as e:
        pytest.skip(f"Environment validation failed: {e}")

@pytest.fixture(scope="session")
def test_credentials():
    """Test credentials fixture"""
    try:
        return TestCredentials()
    except Exception as e:
        pytest.skip(f"Test credentials not available: {e}")

@pytest.fixture(scope="session")
def database_connection(test_config):
    """Database connection fixture"""
    db = DatabaseUtils(test_config.SUPABASE_URL, test_config.SUPABASE_SERVICE_KEY)
    
    # Test connection
    try:
        companies = db.get_test_companies(1)
        if not companies:
            pytest.skip("No test companies found in database")
    except Exception as e:
        pytest.skip(f"Database connection failed: {e}")
    
    return db

@pytest.fixture(scope="session")
def api_client(test_config):
    """API client fixture"""
    return APIUtils(test_config.API_BASE_URL)

@pytest.fixture
def authenticated_api_client(api_client, test_credentials):
    """Authenticated API client fixture"""
    try:
        creds = test_credentials.get_user_credentials("Owner")
        api_client.login(creds["email"], creds["password"])
        return api_client
    except Exception as e:
        pytest.skip(f"Authentication failed: {e}")

@pytest.fixture
def browser(test_config):
    """Browser fixture for frontend tests"""
    browser_utils = BrowserUtils(
        headless=os.getenv('BROWSER_HEADLESS', 'true').lower() == 'true',
        timeout=test_config.BROWSER_TIMEOUT
    )
    
    try:
        browser_utils.start_browser()
        yield browser_utils
    except Exception as e:
        pytest.skip(f"Browser initialization failed: {e}")
    finally:
        browser_utils.stop_browser()

@pytest.fixture
def authenticated_browser(browser, test_credentials, test_config):
    """Authenticated browser fixture"""
    try:
        creds = test_credentials.get_user_credentials("Owner")
        
        # Navigate to login page
        browser.navigate_to(f"{test_config.BASE_URL}/login")
        browser.wait_for_page_load()
        
        # Login
        browser.type_text('input[type="email"], input[name="email"]', creds["email"])
        browser.type_text('input[type="password"], input[name="password"]', creds["password"])
        browser.click_element('button[type="submit"], input[type="submit"]')
        
        time.sleep(3)  # Wait for login
        
        return browser
    except Exception as e:
        pytest.skip(f"Browser authentication failed: {e}")

@pytest.fixture
def test_reporter():
    """Test reporter fixture"""
    return TestReporter()

@pytest.fixture(scope="session")
def test_companies(database_connection):
    """Test companies fixture"""
    companies = database_connection.get_test_companies(5)
    if not companies:
        pytest.skip("No test companies available")
    return companies

@pytest.fixture(scope="session")
def sample_company_data(database_connection, test_companies):
    """Sample company data fixture"""
    company = test_companies[0]
    company_id = company["id"]
    
    # Gather sample data for the company
    data = {
        'company': company,
        'products': database_connection.get_test_products(company_id, 20),
        'orders': database_connection.get_test_orders(company_id, 15),
        'customers': database_connection.get_test_customers(company_id, 10),
        'suppliers': database_connection.get_test_suppliers(company_id, 5)
    }
    
    return data

@pytest.fixture
def temp_screenshot_dir():
    """Temporary directory for test screenshots"""
    with tempfile.TemporaryDirectory(prefix="aiventory_test_screenshots_") as temp_dir:
        yield temp_dir

@pytest.fixture(autouse=True)
def test_timing():
    """Automatic fixture to time all tests"""
    start_time = time.time()
    yield
    duration = time.time() - start_time
    
    # You can log timing info here if needed
    # print(f"\n⏱️ Test completed in {duration:.2f}s")

# Session-scoped fixtures for expensive operations
@pytest.fixture(scope="session")
def environment_health_check(test_config, database_connection):
    """Check environment health before running tests"""
    health_status = {
        'database': False,
        'api': False,
        'application': False
    }
    
    # Test database
    try:
        companies = database_connection.get_test_companies(1)
        health_status['database'] = len(companies) > 0
    except:
        pass
    
    # Test API availability
    try:
        import requests
        response = requests.get(f"{test_config.BASE_URL}/api/health", timeout=5)
        health_status['api'] = response.status_code in [200, 404]  # 404 is OK if endpoint doesn't exist
    except:
        pass
    
    # Test application availability
    try:
        import requests
        response = requests.get(test_config.BASE_URL, timeout=5)
        health_status['application'] = response.status_code in [200, 404]
    except:
        pass
    
    # Skip tests if critical components are down
    if not health_status['database']:
        pytest.skip("Database is not accessible")
    
    if not health_status['application']:
        pytest.skip("Application is not accessible")
    
    return health_status

# Utility functions for tests
def skip_if_no_data(data, message="Test data not available"):
    """Skip test if required data is not available"""
    if not data or (isinstance(data, (list, dict)) and len(data) == 0):
        pytest.skip(message)

def require_environment_vars(*var_names):
    """Decorator to require environment variables"""
    def decorator(func):
        missing_vars = [var for var in var_names if not os.getenv(var)]
        if missing_vars:
            return pytest.mark.skip(f"Missing environment variables: {', '.join(missing_vars)}")(func)
        return func
    return decorator

# Pytest hooks for custom behavior
def pytest_runtest_setup(item):
    """Setup hook for each test"""
    # Check for skip conditions based on markers
    
    if item.get_closest_marker("requires_data"):
        # Verify test data is available
        try:
            db = DatabaseUtils(TestConfig.SUPABASE_URL, TestConfig.SUPABASE_SERVICE_KEY)
            companies = db.get_test_companies(1)
            if not companies:
                pytest.skip("Test requires data but no companies found")
        except:
            pytest.skip("Test requires data but database is not accessible")
    
    if item.get_closest_marker("frontend"):
        # Check if browser testing is enabled
        if os.getenv("SKIP_FRONTEND_TESTS", "false").lower() == "true":
            pytest.skip("Frontend tests disabled")

def pytest_runtest_teardown(item, nextitem):
    """Teardown hook for each test"""
    # Clean up any test artifacts
    pass

def pytest_sessionstart(session):
    """Session start hook"""
    print(f"\n🚀 Starting AIVentory test session at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

def pytest_sessionfinish(session, exitstatus):
    """Session finish hook"""
    print(f"\n🏁 Test session finished with exit status: {exitstatus}")
    
    # Generate final report summary
    if hasattr(session, 'testscollected'):
        print(f"📊 Total tests collected: {session.testscollected}")

# Custom test result handling
@pytest.hookimpl(tryfirst=True, hookwrapper=True)
def pytest_runtest_makereport(item, call):
    """Custom test result reporting"""
    outcome = yield
    report = outcome.get_result()
    
    # Add custom information to test reports
    if report.when == "call":
        # Add timing information
        if hasattr(report, 'duration'):
            if report.duration > 30:  # Long running test
                report.sections.append(('Performance Warning', f'Test took {report.duration:.2f}s'))
        
        # Add screenshot info for frontend tests
        if item.get_closest_marker("frontend") and report.failed:
            report.sections.append(('Frontend Test Info', 'Screenshot may be available in test_screenshots/'))

# Test data validation
def validate_test_environment():
    """Validate test environment is properly set up"""
    issues = []
    
    # Check required environment variables
    required_vars = ['NEXT_PUBLIC_SUPABASE_URL', 'NEXT_PUBLIC_SUPABASE_ANON_KEY']
    for var in required_vars:
        if not os.getenv(var):
            issues.append(f"Missing environment variable: {var}")
    
    # Check test credentials
    try:
        TestCredentials()
    except Exception as e:
        issues.append(f"Test credentials issue: {e}")
    
    # Check directories
    required_dirs = ['test_reports', 'test_screenshots', 'test_data']
    for dir_name in required_dirs:
        if not os.path.exists(dir_name):
            try:
                os.makedirs(dir_name, exist_ok=True)
            except Exception as e:
                issues.append(f"Cannot create directory {dir_name}: {e}")
    
    return issues

# Run validation on import
_validation_issues = validate_test_environment()
if _validation_issues:
    print("⚠️ Test Environment Issues:")
    for issue in _validation_issues:
        print(f"   - {issue}")

print("✅ Pytest configuration loaded")
