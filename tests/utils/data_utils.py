
"""
Enhanced data utility functions for testing
"""

import json
import time
import uuid
import random
import os
from datetime import datetime
from typing import Dict, List, Any, Optional

class TestReporter:
    """Enhanced test reporting utilities"""
    
    def __init__(self):
        self.results = []
        self.start_time = datetime.now()
        self.test_summary = {
            "total_tests": 0,
            "passed": 0,
            "failed": 0,
            "skipped": 0,
            "errors": []
        }
    
    def add_result(self, test_name: str, status: str, duration: float = 0,
                   error: str = None, details: Dict = None):
        """Add test result"""
        result = {
            "test_name": test_name,
            "status": status,
            "duration": duration,
            "timestamp": datetime.now().isoformat(),
            "error": error,
            "details": details or {}
        }
        self.results.append(result)
        
        # Update summary
        self.test_summary["total_tests"] += 1
        if status == "PASS":
            self.test_summary["passed"] += 1
        elif status == "FAIL":
            self.test_summary["failed"] += 1
            if error:
                self.test_summary["errors"].append({
                    "test": test_name,
                    "error": error
                })
        elif status == "SKIP":
            self.test_summary["skipped"] += 1
    
    def generate_summary(self) -> Dict:
        """Generate comprehensive test summary"""
        total_duration = sum(r["duration"] for r in self.results)
        
        summary = {
            **self.test_summary,
            "total_duration": total_duration,
            "average_duration": total_duration / len(self.results) if self.results else 0,
            "pass_rate": (self.test_summary["passed"] / self.test_summary["total_tests"] * 100) if self.test_summary["total_tests"] > 0 else 0,
            "start_time": self.start_time.isoformat(),
            "end_time": datetime.now().isoformat()
        }
        
        return summary
    
    def save_results(self, filename: str = None):
        """Save results to JSON file"""
        if not filename:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"test_results_{timestamp}.json"
        
        filepath = os.path.join("test_reports", filename)
        os.makedirs("test_reports", exist_ok=True)
        
        report_data = {
            "summary": self.generate_summary(),
            "results": self.results
        }
        
        with open(filepath, 'w') as f:
            json.dump(report_data, f, indent=2)
        
        print(f"📄 Test results saved: {filepath}")
        return filepath
    
    def generate_html_report(self, filename: str = None) -> str:
        """Generate HTML test report"""
        if not filename:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"test_report_{timestamp}.html"
        
        filepath = os.path.join("test_reports", filename)
        os.makedirs("test_reports", exist_ok=True)
        
        summary = self.generate_summary()
        
        html_content = f"""
<!DOCTYPE html>
<html>
<head>
    <title>AIVentory Test Report</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 20px; }}
        .header {{ background: #f0f0f0; padding: 20px; border-radius: 5px; }}
        .summary {{ display: flex; gap: 20px; margin: 20px 0; }}
        .metric {{ background: #fff; border: 1px solid #ddd; padding: 15px; border-radius: 5px; text-align: center; }}
        .metric h3 {{ margin: 0; color: #333; }}
        .metric .value {{ font-size: 24px; font-weight: bold; margin: 5px 0; }}
        .pass {{ color: #28a745; }}
        .fail {{ color: #dc3545; }}
        .skip {{ color: #ffc107; }}
        .results-table {{ width: 100%; border-collapse: collapse; margin: 20px 0; }}
        .results-table th, .results-table td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
        .results-table th {{ background: #f8f9fa; }}
        .status-pass {{ background: #d4edda; }}
        .status-fail {{ background: #f8d7da; }}
        .status-skip {{ background: #fff3cd; }}
    </style>
</head>
<body>
    <div class="header">
        <h1>🧪 AIVentory Test Report</h1>
        <p>Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
        <p>Duration: {summary['total_duration']:.2f} seconds</p>
    </div>
    
    <div class="summary">
        <div class="metric">
            <h3>Total Tests</h3>
            <div class="value">{summary['total_tests']}</div>
        </div>
        <div class="metric">
            <h3>Passed</h3>
            <div class="value pass">{summary['passed']}</div>
        </div>
        <div class="metric">
            <h3>Failed</h3>
            <div class="value fail">{summary['failed']}</div>
        </div>
        <div class="metric">
            <h3>Skipped</h3>
            <div class="value skip">{summary['skipped']}</div>
        </div>
        <div class="metric">
            <h3>Pass Rate</h3>
            <div class="value">{summary['pass_rate']:.1f}%</div>
        </div>
    </div>
    
    <h2>Test Results</h2>
    <table class="results-table">
        <thead>
            <tr>
                <th>Test Name</th>
                <th>Status</th>
                <th>Duration (s)</th>
                <th>Timestamp</th>
                <th>Details</th>
            </tr>
        </thead>
        <tbody>
"""
        
        for result in self.results:
            status_class = f"status-{result['status'].lower()}"
            details = json.dumps(result.get('details', {}), indent=2) if result.get('details') else ""
            error_info = f"<br><strong>Error:</strong> {result['error']}" if result.get('error') else ""
            
            html_content += f"""
            <tr class="{status_class}">
                <td>{result['test_name']}</td>
                <td>{result['status']}</td>
                <td>{result['duration']:.2f}</td>
                <td>{result['timestamp']}</td>
                <td><pre>{details}</pre>{error_info}</td>
            </tr>
"""
        
        html_content += """
        </tbody>
    </table>
</body>
</html>
"""
        
        with open(filepath, 'w') as f:
            f.write(html_content)
        
        print(f"📊 HTML report generated: {filepath}")
        return filepath
    
    def print_summary(self):
        """Print test summary to console"""
        summary = self.generate_summary()
        
        print("\n" + "=" * 60)
        print("📊 TEST SUMMARY")
        print("=" * 60)
        print(f"✅ Passed: {summary['passed']}")
        print(f"❌ Failed: {summary['failed']}")
        print(f"⚠️ Skipped: {summary['skipped']}")
        print(f"📈 Pass Rate: {summary['pass_rate']:.1f}%")
        print(f"⏱️ Total Duration: {summary['total_duration']:.2f}s")
        
        if summary['errors']:
            print(f"\n❌ ERRORS ({len(summary['errors'])}):")
            for error in summary['errors'][:5]:  # Show first 5 errors
                print(f"   • {error['test']}: {error['error'][:100]}...")

class DataUtils:
    """Enhanced data utility functions"""
    
    @staticmethod
    def generate_test_product() -> Dict:
        """Generate test product data"""
        categories = ["Electronics", "Clothing", "Books", "Home & Garden", "Sports"]
        
        return {
            "id": str(uuid.uuid4()),
            "title": f"Test Product {random.randint(1000, 9999)}",
            "description": f"Test product description {datetime.now().isoformat()}",
            "product_type": random.choice(categories),
            "status": "active",
            "tags": [f"tag{i}" for i in range(random.randint(1, 4))]
        }
    
    @staticmethod
    def generate_test_customer() -> Dict:
        """Generate test customer data"""
        first_names = ["John", "Jane", "Mike", "Sarah", "David", "Lisa", "Chris", "Emma"]
        last_names = ["Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller"]
        
        first_name = random.choice(first_names)
        last_name = random.choice(last_names)
        
        return {
            "id": str(uuid.uuid4()),
            "customer_name": f"{first_name} {last_name}",
            "email": f"{first_name.lower()}.{last_name.lower()}@example.com",
            "total_orders": random.randint(1, 20),
            "total_spent": random.randint(100, 5000)
        }
    
    @staticmethod
    def generate_test_supplier() -> Dict:
        """Generate test supplier data"""
        company_types = ["Corp", "Inc", "Ltd", "LLC", "Co"]
        business_names = ["Global", "International", "Supply", "Trading", "Manufacturing"]
        
        name = f"{random.choice(business_names)} {random.choice(company_types)}"
        
        return {
            "id": str(uuid.uuid4()),
            "name": name,
            "email": f"contact@{name.lower().replace(' ', '')}.com",
            "phone": f"555-{random.randint(1000, 9999)}",
            "default_lead_time_days": random.randint(7, 30)
        }
    
    @staticmethod
    def validate_record_structure(record: Dict, required_fields: List[str]) -> Dict:
        """Validate record has required fields"""
        missing_fields = []
        invalid_fields = []
        
        for field in required_fields:
            if field not in record:
                missing_fields.append(field)
            elif record[field] is None:
                invalid_fields.append(f"{field} is null")
        
        return {
            "valid": len(missing_fields) == 0 and len(invalid_fields) == 0,
            "missing_fields": missing_fields,
            "invalid_fields": invalid_fields,
            "record_id": record.get("id", "unknown")
        }
    
    @staticmethod
    def calculate_percentage_difference(expected: float, actual: float) -> float:
        """Calculate percentage difference between expected and actual values"""
        if expected == 0 and actual == 0:
            return 0.0
        if expected == 0:
            return 100.0
        
        return abs(expected - actual) / expected * 100.0
    
    @staticmethod
    def is_within_tolerance(expected: float, actual: float, tolerance_percent: float = 10.0) -> bool:
        """Check if actual value is within tolerance of expected value"""
        diff_percent = DataUtils.calculate_percentage_difference(expected, actual)
        return diff_percent <= tolerance_percent
    
    @staticmethod
    def format_currency(amount: int) -> str:
        """Format amount in cents to currency string"""
        return f"${amount / 100:.2f}"
    
    @staticmethod
    def parse_date_string(date_str: str) -> Optional[datetime]:
        """Parse date string to datetime object"""
        try:
            # Try ISO format first
            return datetime.fromisoformat(date_str.replace('Z', '+00:00'))
        except:
            try:
                # Try common formats
                for fmt in ['%Y-%m-%d', '%Y-%m-%d %H:%M:%S', '%m/%d/%Y']:
                    return datetime.strptime(date_str, fmt)
            except:
                return None
    
    @staticmethod
    def sanitize_filename(filename: str) -> str:
        """Sanitize filename for safe file operations"""
        invalid_chars = '<>:"/\\|?*'
        for char in invalid_chars:
            filename = filename.replace(char, '_')
        return filename
    
    @staticmethod
    def deep_compare_dicts(dict1: Dict, dict2: Dict, ignore_keys: List[str] = None) -> Dict:
        """Deep compare two dictionaries and return differences"""
        ignore_keys = ignore_keys or []
        differences = {
            "missing_in_dict2": [],
            "missing_in_dict1": [],
            "value_differences": []
        }
        
        # Check keys in dict1 but not in dict2
        for key in dict1:
            if key in ignore_keys:
                continue
            if key not in dict2:
                differences["missing_in_dict2"].append(key)
            elif dict1[key] != dict2[key]:
                differences["value_differences"].append({
                    "key": key,
                    "dict1_value": dict1[key],
                    "dict2_value": dict2[key]
                })
        
        # Check keys in dict2 but not in dict1
        for key in dict2:
            if key in ignore_keys:
                continue
            if key not in dict1:
                differences["missing_in_dict1"].append(key)
        
        return differences

print("✅ Enhanced data utilities loaded")
