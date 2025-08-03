#!/usr/bin/env python3
"""
Master Test Runner for Invochat
Orchestrates all test suites and generates comprehensive reports
"""

import os
import sys
import time
import subprocess
import json
from datetime import datetime
from typing import Dict, List, Any
from test_config import TestConfig, TestCredentials
from utils.database_utils import DatabaseUtils
from utils.data_utils import TestReporter

class MasterTestRunner:
    """Master test runner that orchestrates all test suites"""
    
    def __init__(self):
        self.start_time = datetime.now()
        self.reporter = TestReporter()
        self.results = {}
        self.companies_tested = []
        
    def validate_environment(self) -> bool:
        """Validate test environment before running tests"""
        print("🔧 Validating test environment...")
        
        try:
            # Validate configuration
            TestConfig.validate_environment()
            TestConfig.create_directories()
            print("   ✅ Configuration valid")
            
            # Test database connection
            db = DatabaseUtils(TestConfig.SUPABASE_URL, TestConfig.SUPABASE_SERVICE_KEY)
            companies = db.get_test_companies(1)
            if not companies:
                print("   ⚠️ No companies found in database")
                return False
            print("   ✅ Database connection successful")
            
            # Test credentials
            creds = TestCredentials()
            test_users = creds._credentials.get("test_users", [])
            if not test_users:
                print("   ❌ No test users configured")
                return False
            print(f"   ✅ {len(test_users)} test users configured")
            
            # Test application accessibility
            import requests
            try:
                response = requests.get(TestConfig.BASE_URL, timeout=10)
                if response.status_code in [200, 404]:  # 404 is OK for root path
                    print("   ✅ Application accessible")
                else:
                    print(f"   ⚠️ Application responded with {response.status_code}")
            except Exception as e:
                print(f"   ❌ Application not accessible: {e}")
                return False
            
            return True
            
        except Exception as e:
            print(f"   ❌ Environment validation failed: {e}")
            return False
    
    def run_test_module(self, module_name: str, description: str, timeout: int = 600) -> Dict:
        """Run a single test module"""
        print(f"\n📋 Running {description}...")
        
        start_time = time.time()
        
        try:
            # Construct pytest command
            cmd = [
                "python", "-m", "pytest", 
                f"{module_name}.py", 
                "-v", 
                "--tb=short",
                f"--timeout={timeout}"
            ]
            
            # Run the test
            result = subprocess.run(
                cmd, 
                capture_output=True, 
                text=True, 
                timeout=timeout,
                cwd=os.getcwd()
            )
            
            duration = time.time() - start_time
            
            # Parse output for detailed results
            output_lines = result.stdout.split('\n') if result.stdout else []
            error_lines = result.stderr.split('\n') if result.stderr else []
            
            # Count test results from pytest output
            test_counts = self._parse_pytest_output(output_lines)
            
            if result.returncode == 0:
                status = "PASSED"
                print(f"   ✅ {description} completed successfully ({duration:.1f}s)")
                print(f"      Tests: {test_counts['passed']} passed, {test_counts['failed']} failed, {test_counts['skipped']} skipped")
            else:
                status = "FAILED"
                print(f"   ❌ {description} failed ({duration:.1f}s)")
                print(f"      Tests: {test_counts['passed']} passed, {test_counts['failed']} failed, {test_counts['skipped']} skipped")
                
                # Show first few error lines
                if error_lines:
                    print(f"      Errors:")
                    for line in error_lines[:5]:
                        if line.strip():
                            print(f"        {line}")
            
            return {
                "status": status,
                "duration": duration,
                "return_code": result.returncode,
                "test_counts": test_counts,
                "stdout": result.stdout,
                "stderr": result.stderr
            }
            
        except subprocess.TimeoutExpired:
            duration = timeout
            print(f"   ⏱️ {description} timed out after {timeout} seconds")
            return {
                "status": "TIMEOUT",
                "duration": duration,
                "return_code": -1,
                "test_counts": {"passed": 0, "failed": 0, "skipped": 0},
                "stdout": "",
                "stderr": "Test timed out"
            }
            
        except Exception as e:
            duration = time.time() - start_time
            print(f"   ❌ {description} execution error: {e}")
            return {
                "status": "ERROR",
                "duration": duration,
                "return_code": -1,
                "test_counts": {"passed": 0, "failed": 0, "skipped": 0},
                "stdout": "",
                "stderr": str(e)
            }
    
    def _parse_pytest_output(self, output_lines: List[str]) -> Dict[str, int]:
        """Parse pytest output to extract test counts"""
        counts = {"passed": 0, "failed": 0, "skipped": 0}
        
        for line in output_lines:
            line = line.strip()
            if "passed" in line and "failed" in line:
                # Look for pattern like "5 passed, 2 failed, 1 skipped"
                parts = line.split(',')
                for part in parts:
                    part = part.strip()
                    if "passed" in part:
                        try:
                            counts["passed"] = int(part.split()[0])
                        except:
                            pass
                    elif "failed" in part:
                        try:
                            counts["failed"] = int(part.split()[0])
                        except:
                            pass
                    elif "skipped" in part:
                        try:
                            counts["skipped"] = int(part.split()[0])
                        except:
                            pass
                break
        
        return counts
    
    def generate_company_analysis(self) -> Dict:
        """Generate analysis of test companies"""
        print("\n🏢 Analyzing test companies...")
        
        try:
            db = DatabaseUtils(TestConfig.SUPABASE_URL, TestConfig.SUPABASE_SERVICE_KEY)
            companies = db.get_test_companies(5)
            
            company_analysis = []
            
            for company in companies:
                company_id = company["id"]
                company_name = company.get("name", f"Company-{company_id[:8]}")
                
                print(f"   📊 Analyzing {company_name}")
                
                # Get company statistics
                stats = db.get_company_statistics(company_id)
                
                # Test database functions
                function_results = db.test_database_functions(company_id)
                
                # Validate data integrity
                integrity_results = db.validate_data_integrity(company_id)
                
                company_info = {
                    "id": company_id,
                    "name": company_name,
                    "statistics": stats,
                    "function_results": function_results,
                    "integrity_results": integrity_results,
                    "data_quality_score": integrity_results.get('integrity_score', 0)
                }
                
                company_analysis.append(company_info)
                self.companies_tested.append(company_info)
            
            return {
                "companies_analyzed": len(company_analysis),
                "companies": company_analysis,
                "average_data_quality": sum(c["data_quality_score"] for c in company_analysis) / len(company_analysis) if company_analysis else 0
            }
            
        except Exception as e:
            print(f"   ❌ Company analysis failed: {e}")
            return {"error": str(e)}
    
    def run_all_tests(self) -> Dict:
        """Run all test suites"""
        print("🧪 Invochat Comprehensive Test Suite")
        print("=" * 60)
        print(f"📅 Started: {self.start_time.strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"🌐 Base URL: {TestConfig.BASE_URL}")
        print("=" * 60)
        
        # Validate environment first
        if not self.validate_environment():
            print("❌ Environment validation failed. Aborting tests.")
            sys.exit(1)
        
        # Generate company analysis
        company_analysis = self.generate_company_analysis()
        
        # Define test modules to run - UPDATED WITH CORRECT FILENAMES
        test_modules = [
            ("business_logic_tests", "Business Logic Validation Tests", 900),
            ("database_tests", "Database Function Tests", 600),
            ("api_tests", "API Endpoint Tests", 600),
            ("ai_tests", "AI Integration Tests", 600),
            ("frontend_tests", "Frontend Integration Tests", 600),
        ]
        
        # Run each test module
        for module, description, timeout in test_modules:
            if os.path.exists(f"{module}.py"):
                self.results[module] = self.run_test_module(module, description, timeout)
            else:
                print(f"\n⚠️ Skipping {description} - file {module}.py not found")
                self.results[module] = {
                    "status": "SKIPPED",
                    "duration": 0,
                    "return_code": 0,
                    "test_counts": {"passed": 0, "failed": 0, "skipped": 1},
                    "stdout": "",
                    "stderr": "File not found"
                }
        
        # Calculate overall results
        total_duration = time.time() - self.start_time.timestamp()
        
        # Aggregate test counts
        total_counts = {"passed": 0, "failed": 0, "skipped": 0}
        for result in self.results.values():
            counts = result.get("test_counts", {})
            total_counts["passed"] += counts.get("passed", 0)
            total_counts["failed"] += counts.get("failed", 0)
            total_counts["skipped"] += counts.get("skipped", 0)
        
        # Generate comprehensive report
        final_report = {
            "test_run_info": {
                "start_time": self.start_time.isoformat(),
                "end_time": datetime.now().isoformat(),
                "total_duration": total_duration,
                "base_url": TestConfig.BASE_URL
            },
            "test_summary": {
                "modules_run": len(self.results),
                "total_tests": sum(total_counts.values()),
                **total_counts,
                "pass_rate": (total_counts["passed"] / sum(total_counts.values()) * 100) if sum(total_counts.values()) > 0 else 0
            },
            "module_results": self.results,
            "company_analysis": company_analysis,
            "environment_info": {
                "python_version": sys.version,
                "platform": sys.platform,
                "working_directory": os.getcwd()
            }
        }
        
        # Save detailed report
        self._save_detailed_report(final_report)
        
        # Print summary
        self._print_final_summary(final_report)
        
        return final_report
    
    def _save_detailed_report(self, report: Dict):
        """Save detailed test report to file"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        # Save JSON report
        json_filename = f"test_report_{timestamp}.json"
        json_filepath = os.path.join("test_reports", json_filename)
        
        with open(json_filepath, 'w') as f:
            json.dump(report, f, indent=2)
        
        print(f"\n📄 Detailed report saved: {json_filepath}")
        
        # Generate HTML report
        html_filepath = self._generate_html_report(report, timestamp)
        print(f"📊 HTML report generated: {html_filepath}")
        
        # Create latest symlinks
        try:
            latest_json = os.path.join("test_reports", "test_report_latest.json")
            latest_html = os.path.join("test_reports", "test_report_latest.html")
            
            if os.path.exists(latest_json):
                os.remove(latest_json)
            if os.path.exists(latest_html):
                os.remove(latest_html)
            
            os.symlink(json_filename, latest_json)
            os.symlink(f"test_report_{timestamp}.html", latest_html)
            
            print(f"📎 Latest reports linked")
        except:
            pass  # Symlinks may not work on all systems
    
    def _generate_html_report(self, report: Dict, timestamp: str) -> str:
        """Generate comprehensive HTML test report"""
        filename = f"test_report_{timestamp}.html"
        filepath = os.path.join("test_reports", filename)
        
        summary = report["test_summary"]
        company_analysis = report.get("company_analysis", {})
        
        html_content = f"""
<!DOCTYPE html>
<html>
<head>
    <title>Invochat Comprehensive Test Report</title>
    <style>
        body {{ font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }}
        .container {{ max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }}
        .header {{ background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; border-radius: 10px; margin-bottom: 30px; }}
        .header h1 {{ margin: 0; font-size: 2.5em; }}
        .header p {{ margin: 5px 0; opacity: 0.9; }}
        .summary {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin: 30px 0; }}
        .metric {{ background: #fff; border: 2px solid #e0e0e0; padding: 20px; border-radius: 10px; text-align: center; transition: transform 0.2s; }}
        .metric:hover {{ transform: translateY(-5px); }}
        .metric h3 {{ margin: 0 0 10px 0; color: #333; font-size: 1.1em; }}
        .metric .value {{ font-size: 2.5em; font-weight: bold; margin: 10px 0; }}
        .pass {{ color: #28a745; }}
        .fail {{ color: #dc3545; }}
        .skip {{ color: #ffc107; }}
        .section {{ margin: 30px 0; }}
        .section h2 {{ color: #333; border-bottom: 3px solid #667eea; padding-bottom: 10px; }}
        .module-results {{ display: grid; gap: 20px; }}
        .module {{ background: #f8f9fa; border: 1px solid #dee2e6; border-radius: 8px; padding: 20px; }}
        .module h3 {{ margin: 0 0 15px 0; color: #495057; }}
        .status-badge {{ display: inline-block; padding: 5px 15px; border-radius: 20px; color: white; font-weight: bold; margin-left: 10px; }}
        .status-passed {{ background: #28a745; }}
        .status-failed {{ background: #dc3545; }}
        .status-skipped {{ background: #6c757d; }}
        .company-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }}
        .company-card {{ background: #fff; border: 1px solid #ddd; border-radius: 8px; padding: 20px; }}
        .company-card h4 {{ margin: 0 0 15px 0; color: #333; }}
        .progress-bar {{ background: #e9ecef; border-radius: 10px; height: 20px; overflow: hidden; }}
        .progress-fill {{ height: 100%; transition: width 0.3s ease; }}
        .excellent {{ background: #28a745; }}
        .good {{ background: #17a2b8; }}
        .fair {{ background: #ffc107; }}
        .poor {{ background: #dc3545; }}
        .stats-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 10px; margin: 15px 0; }}
        .stat-item {{ text-align: center; padding: 10px; background: #f8f9fa; border-radius: 5px; }}
        .stat-value {{ font-weight: bold; font-size: 1.2em; color: #495057; }}
        .stat-label {{ font-size: 0.9em; color: #6c757d; }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🧪 Invochat Test Report</h1>
            <p>📅 Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
            <p>⏱️ Duration: {report['test_run_info']['total_duration']:.2f} seconds</p>
            <p>🌐 Base URL: {report['test_run_info']['base_url']}</p>
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
        
        <div class="section">
            <h2>📋 Module Results</h2>
            <div class="module-results">
"""
        
        # Add module results
        for module_name, result in report["module_results"].items():
            status_class = f"status-{result['status'].lower()}"
            counts = result['test_counts']
            
            html_content += f"""
                <div class="module">
                    <h3>{module_name.replace('_', ' ').title()}<span class="status-badge {status_class}">{result['status']}</span></h3>
                    <p><strong>Duration:</strong> {result['duration']:.2f}s</p>
                    <div class="stats-grid">
                        <div class="stat-item">
                            <div class="stat-value pass">{counts['passed']}</div>
                            <div class="stat-label">Passed</div>
                        </div>
                        <div class="stat-item">
                            <div class="stat-value fail">{counts['failed']}</div>
                            <div class="stat-label">Failed</div>
                        </div>
                        <div class="stat-item">
                            <div class="stat-value skip">{counts['skipped']}</div>
                            <div class="stat-label">Skipped</div>
                        </div>
                    </div>
                </div>
"""
        
        html_content += """
            </div>
        </div>
"""
        
        # Add company analysis if available
        if company_analysis and company_analysis.get("companies"):
            html_content += """
        <div class="section">
            <h2>🏢 Company Analysis</h2>
            <div class="company-grid">
"""
            
            for company in company_analysis["companies"]:
                quality_score = company.get("data_quality_score", 0)
                quality_class = "excellent" if quality_score >= 90 else "good" if quality_score >= 75 else "fair" if quality_score >= 50 else "poor"
                
                stats = company.get("statistics", {})
                
                html_content += f"""
                <div class="company-card">
                    <h4>{company['name']}</h4>
                    <p><strong>Data Quality Score:</strong></p>
                    <div class="progress-bar">
                        <div class="progress-fill {quality_class}" style="width: {quality_score}%"></div>
                    </div>
                    <p style="text-align: center; margin: 10px 0;">{quality_score:.1f}%</p>
                    
                    <div class="stats-grid">
                        <div class="stat-item">
                            <div class="stat-value">{stats.get('products_count', 0)}</div>
                            <div class="stat-label">Products</div>
                        </div>
                        <div class="stat-item">
                            <div class="stat-value">{stats.get('orders_count', 0)}</div>
                            <div class="stat-label">Orders</div>
                        </div>
                        <div class="stat-item">
                            <div class="stat-value">${stats.get('total_revenue', 0)/100:.0f}</div>
                            <div class="stat-label">Revenue</div>
                        </div>
                        <div class="stat-item">
                            <div class="stat-value">${stats.get('total_inventory_value', 0)/100:.0f}</div>
                            <div class="stat-label">Inventory</div>
                        </div>
                    </div>
                </div>
"""
            
            html_content += """
            </div>
        </div>
"""
        
        html_content += """
    </div>
</body>
</html>
"""
        
        with open(filepath, 'w') as f:
            f.write(html_content)
        
        return filepath
    
    def _print_final_summary(self, report: Dict):
        """Print final test summary"""
        summary = report["test_summary"]
        
        print("\n" + "=" * 60)
        print("📊 FINAL TEST SUMMARY")
        print("=" * 60)
        
        # Test results
        print(f"✅ Passed: {summary['passed']}")
        print(f"❌ Failed: {summary['failed']}")
        print(f"⚠️ Skipped: {summary['skipped']}")
        print(f"📈 Pass Rate: {summary['pass_rate']:.1f}%")
        print(f"⏱️ Total Duration: {report['test_run_info']['total_duration']:.2f}s")
        
        # Module breakdown
        print(f"\n📋 MODULE BREAKDOWN:")
        for module_name, result in report["module_results"].items():
            status_emoji = {"PASSED": "✅", "FAILED": "❌", "SKIPPED": "⚠️", "TIMEOUT": "⏱️", "ERROR": "🚫"}
            emoji = status_emoji.get(result["status"], "❓")
            counts = result['test_counts']
            print(f"   {emoji} {module_name}: {result['status']} ({counts['passed']}P/{counts['failed']}F/{counts['skipped']}S) - {result['duration']:.1f}s")
        
        # Company analysis
        company_analysis = report.get("company_analysis", {})
        if company_analysis and company_analysis.get("companies"):
            print(f"\n🏢 COMPANY ANALYSIS:")
            print(f"   Companies tested: {company_analysis['companies_analyzed']}")
            print(f"   Average data quality: {company_analysis['average_data_quality']:.1f}%")
            
            for company in company_analysis["companies"][:3]:  # Show first 3
                quality = company.get("data_quality_score", 0)
                stats = company.get("statistics", {})
                print(f"   📊 {company['name']}: {quality:.1f}% quality, {stats.get('products_count', 0)} products, ${stats.get('total_revenue', 0)/100:.0f} revenue")
        
        # Overall assessment
        if summary['pass_rate'] >= 90:
            print(f"\n🎉 EXCELLENT: All systems functioning properly!")
        elif summary['pass_rate'] >= 75:
            print(f"\n✅ GOOD: Most features working with minor issues")
        elif summary['pass_rate'] >= 50:
            print(f"\n⚠️ FAIR: Several issues need attention")
        else:
            print(f"\n❌ POOR: Major issues require immediate attention")
        
        # Exit code
        exit_code = 0 if summary['failed'] == 0 else 1
        
        if exit_code == 0:
            print(f"\n✅ All tests completed successfully!")
        else:
            print(f"\n❌ Some tests failed - check the detailed report")
        
        return exit_code


def main():
    """Main function"""
    runner = MasterTestRunner()
    
    try:
        final_report = runner.run_all_tests()
        exit_code = runner._print_final_summary(final_report)
        sys.exit(exit_code)
        
    except KeyboardInterrupt:
        print("\n\n⏹️ Tests interrupted by user")
        sys.exit(1)
        
    except Exception as e:
        print(f"\n\n💥 Unexpected error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()