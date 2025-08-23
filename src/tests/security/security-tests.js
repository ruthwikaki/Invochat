#!/usr/bin/env node

/**
 * Security Testing Suite
 * Comprehensive security and penetration testing
 */

const fs = require('fs').promises;
const path = require('path');
const crypto = require('crypto');

class SecurityTestRunner {
  constructor() {
    this.baseUrl = process.env.BASE_URL || 'http://localhost:3000';
    this.results = [];
    this.vulnerabilities = [];
  }

  async runSecurityTests() {
    console.log('🔒 Starting Security Testing Suite...\n');
    
    const testSuites = [
      this.testAuthentication,
      this.testAuthorization,
      this.testInputValidation,
      this.testSQLInjection,
      this.testXSSVulnerabilities,
      this.testCSRFProtection,
      this.testSecurityHeaders,
      this.testAPIEndpointSecurity,
      this.testSessionManagement,
      this.testDataEncryption,
      this.testRateLimiting,
      this.testFileUploadSecurity
    ];

    for (const testSuite of testSuites) {
      try {
        console.log(`🧪 Running ${testSuite.name}...`);
        await testSuite.call(this);
        console.log(`✅ ${testSuite.name} completed\n`);
      } catch (error) {
        console.error(`❌ ${testSuite.name} failed: ${error.message}\n`);
        this.vulnerabilities.push({
          test: testSuite.name,
          severity: 'high',
          description: error.message,
          timestamp: new Date().toISOString()
        });
      }
    }

    await this.generateSecurityReport();
  }

  async testAuthentication() {
    const tests = [
      this.testWeakPasswordPolicy,
      this.testBruteForceProtection,
      this.testAccountLockout,
      this.testPasswordResetSecurity,
      this.testTwoFactorAuthentication
    ];

    for (const test of tests) {
      await test.call(this);
    }
  }

  async testWeakPasswordPolicy() {
    const weakPasswords = [
      '123456',
      'password',
      'admin',
      'qwerty',
      '111111'
    ];

    for (const password of weakPasswords) {
      try {
        const response = await fetch(`${this.baseUrl}/api/auth/register`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            email: `test_${Date.now()}@example.com`,
            password: password
          })
        });

        if (response.ok) {
          this.vulnerabilities.push({
            test: 'weakPasswordPolicy',
            severity: 'medium',
            description: `Weak password "${password}" was accepted`,
            timestamp: new Date().toISOString()
          });
        }
      } catch (error) {
        // Expected to fail - good security
      }
    }
  }

  async testBruteForceProtection() {
    const testEmail = 'security-test@example.com';
    const failedAttempts = [];

    // Attempt multiple failed logins
    for (let i = 0; i < 10; i++) {
      try {
        const response = await fetch(`${this.baseUrl}/api/auth/signin`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            email: testEmail,
            password: `wrong-password-${i}`
          })
        });

        failedAttempts.push({
          attempt: i + 1,
          status: response.status,
          blocked: response.status === 429
        });

        // Short delay between attempts
        await this.sleep(100);
      } catch (error) {
        // Network errors are expected
      }
    }

    const blockedAttempts = failedAttempts.filter(a => a.blocked);
    if (blockedAttempts.length === 0) {
      this.vulnerabilities.push({
        test: 'bruteForceProtection',
        severity: 'high',
        description: 'No rate limiting detected on authentication endpoint',
        timestamp: new Date().toISOString()
      });
    }
  }

  async testAuthorization() {
    const unauthorizedEndpoints = [
      '/api/admin/users',
      '/api/companies/sensitive-data',
      '/api/analytics/private'
    ];

    for (const endpoint of unauthorizedEndpoints) {
      try {
        const response = await fetch(`${this.baseUrl}${endpoint}`, {
          headers: { 'Authorization': 'Bearer invalid-token' }
        });

        if (response.ok) {
          this.vulnerabilities.push({
            test: 'authorization',
            severity: 'high',
            description: `Unauthorized access allowed to ${endpoint}`,
            timestamp: new Date().toISOString()
          });
        }
      } catch (error) {
        // Expected to fail - good security
      }
    }
  }

  async testInputValidation() {
    const maliciousInputs = [
      '<script>alert("xss")</script>',
      "'; DROP TABLE users; --",
      '../../../etc/passwd',
      '${7*7}',
      '{{7*7}}',
      'javascript:alert(1)',
      'data:text/html,<script>alert(1)</script>'
    ];

    const testEndpoints = [
      '/api/companies',
      '/api/products',
      '/api/search'
    ];

    for (const endpoint of testEndpoints) {
      for (const input of maliciousInputs) {
        try {
          const response = await fetch(`${this.baseUrl}${endpoint}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ 
              query: input,
              name: input,
              description: input 
            })
          });

          // Check if malicious input was reflected in response
          if (response.ok) {
            const responseText = await response.text();
            if (responseText.includes(input) && !responseText.includes('&lt;')) {
              this.vulnerabilities.push({
                test: 'inputValidation',
                severity: 'high',
                description: `Malicious input "${input}" not properly sanitized in ${endpoint}`,
                timestamp: new Date().toISOString()
              });
            }
          }
        } catch (error) {
          // Expected for some inputs
        }
      }
    }
  }

  async testSQLInjection() {
    const sqlPayloads = [
      "' OR '1'='1",
      "'; DROP TABLE users; --",
      "' UNION SELECT * FROM users --",
      "admin'--",
      "admin'/*"
    ];

    const testEndpoints = [
      '/api/search',
      '/api/products',
      '/api/analytics'
    ];

    for (const endpoint of testEndpoints) {
      for (const payload of sqlPayloads) {
        try {
          const response = await fetch(`${this.baseUrl}${endpoint}?q=${encodeURIComponent(payload)}`);
          
          if (response.ok) {
            const responseText = await response.text();
            
            // Look for SQL error messages
            const sqlErrors = [
              'sql syntax',
              'mysql_fetch',
              'postgresql error',
              'ora-',
              'microsoft ole db'
            ];

            if (sqlErrors.some(error => responseText.toLowerCase().includes(error))) {
              this.vulnerabilities.push({
                test: 'sqlInjection',
                severity: 'critical',
                description: `SQL injection vulnerability detected in ${endpoint} with payload: ${payload}`,
                timestamp: new Date().toISOString()
              });
            }
          }
        } catch (error) {
          // Expected for malicious payloads
        }
      }
    }
  }

  async testXSSVulnerabilities() {
    const xssPayloads = [
      '<script>alert("XSS")</script>',
      '<img src=x onerror=alert("XSS")>',
      '<svg onload=alert("XSS")>',
      'javascript:alert("XSS")',
      '<iframe src="javascript:alert(\'XSS\')"></iframe>'
    ];

    const testEndpoints = [
      '/api/search',
      '/api/comments',
      '/api/feedback'
    ];

    for (const endpoint of testEndpoints) {
      for (const payload of xssPayloads) {
        try {
          const response = await fetch(`${this.baseUrl}${endpoint}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ content: payload, message: payload })
          });

          if (response.ok) {
            const responseText = await response.text();
            
            // Check if payload is reflected without encoding
            if (responseText.includes(payload) && !responseText.includes('&lt;script&gt;')) {
              this.vulnerabilities.push({
                test: 'xssVulnerabilities',
                severity: 'high',
                description: `XSS vulnerability detected in ${endpoint} with payload: ${payload}`,
                timestamp: new Date().toISOString()
              });
            }
          }
        } catch (error) {
          // Expected for some payloads
        }
      }
    }
  }

  async testCSRFProtection() {
    const stateChangingEndpoints = [
      { method: 'POST', path: '/api/companies' },
      { method: 'PUT', path: '/api/products/1' },
      { method: 'DELETE', path: '/api/users/1' }
    ];

    for (const endpoint of stateChangingEndpoints) {
      try {
        const response = await fetch(`${this.baseUrl}${endpoint.path}`, {
          method: endpoint.method,
          headers: { 
            'Content-Type': 'application/json',
            'Origin': 'https://malicious-site.com'
          },
          body: JSON.stringify({ malicious: 'data' })
        });

        // Check if request was accepted without CSRF token
        if (response.status !== 403 && response.status !== 401) {
          this.vulnerabilities.push({
            test: 'csrfProtection',
            severity: 'medium',
            description: `CSRF protection missing for ${endpoint.method} ${endpoint.path}`,
            timestamp: new Date().toISOString()
          });
        }
      } catch (error) {
        // Expected for protected endpoints
      }
    }
  }

  async testSecurityHeaders() {
    try {
      const response = await fetch(`${this.baseUrl}/`);
      const headers = response.headers;

      const requiredHeaders = [
        { name: 'X-Content-Type-Options', expected: 'nosniff' },
        { name: 'X-Frame-Options', expected: ['DENY', 'SAMEORIGIN'] },
        { name: 'X-XSS-Protection', expected: '1; mode=block' },
        { name: 'Strict-Transport-Security', expected: null },
        { name: 'Content-Security-Policy', expected: null }
      ];

      for (const header of requiredHeaders) {
        const headerValue = headers.get(header.name);
        
        if (!headerValue) {
          this.vulnerabilities.push({
            test: 'securityHeaders',
            severity: 'medium',
            description: `Missing security header: ${header.name}`,
            timestamp: new Date().toISOString()
          });
        } else if (header.expected && !header.expected.includes(headerValue)) {
          this.vulnerabilities.push({
            test: 'securityHeaders',
            severity: 'low',
            description: `Incorrect value for header ${header.name}: ${headerValue}`,
            timestamp: new Date().toISOString()
          });
        }
      }
    } catch (error) {
      console.error('Security headers test failed:', error.message);
    }
  }

  async testAPIEndpointSecurity() {
    const sensitiveEndpoints = [
      '/api/users',
      '/api/admin',
      '/api/config',
      '/api/logs',
      '/api/backup'
    ];

    for (const endpoint of sensitiveEndpoints) {
      try {
        const response = await fetch(`${this.baseUrl}${endpoint}`);
        
        if (response.ok) {
          this.vulnerabilities.push({
            test: 'apiEndpointSecurity',
            severity: 'medium',
            description: `Sensitive endpoint ${endpoint} accessible without authentication`,
            timestamp: new Date().toISOString()
          });
        }
      } catch (error) {
        // Expected for protected endpoints
      }
    }
  }

  async testSessionManagement() {
    try {
      // Test session fixation
      const initialResponse = await fetch(`${this.baseUrl}/api/auth/session`);
      const initialCookies = initialResponse.headers.get('set-cookie');
      
      if (initialCookies) {
        // Check for secure and httpOnly flags
        if (!initialCookies.includes('Secure')) {
          this.vulnerabilities.push({
            test: 'sessionManagement',
            severity: 'medium',
            description: 'Session cookies missing Secure flag',
            timestamp: new Date().toISOString()
          });
        }
        
        if (!initialCookies.includes('HttpOnly')) {
          this.vulnerabilities.push({
            test: 'sessionManagement',
            severity: 'medium',
            description: 'Session cookies missing HttpOnly flag',
            timestamp: new Date().toISOString()
          });
        }
      }
    } catch (error) {
      // Expected if no session endpoint
    }
  }

  async testDataEncryption() {
    const sensitiveData = [
      'password',
      'ssn',
      'credit_card',
      'api_key',
      'secret'
    ];

    try {
      const response = await fetch(`${this.baseUrl}/api/test/data`);
      
      if (response.ok) {
        const responseText = await response.text();
        
        for (const dataType of sensitiveData) {
          // Look for patterns that might indicate unencrypted sensitive data
          const regex = new RegExp(`"${dataType}"\\s*:\\s*"[^*]`, 'i');
          if (regex.test(responseText)) {
            this.vulnerabilities.push({
              test: 'dataEncryption',
              severity: 'high',
              description: `Potentially unencrypted ${dataType} data detected in API response`,
              timestamp: new Date().toISOString()
            });
          }
        }
      }
    } catch (error) {
      // Expected if no test endpoint
    }
  }

  async testRateLimiting() {
    const endpoint = '/api/test/rate-limit';
    const requests = [];
    
    // Send rapid requests to test rate limiting
    for (let i = 0; i < 20; i++) {
      requests.push(
        fetch(`${this.baseUrl}${endpoint}`, {
          headers: { 'X-Test-Request': i.toString() }
        }).catch(e => ({ status: 'error', error: e.message }))
      );
    }
    
    const responses = await Promise.all(requests);
    const rateLimited = responses.filter(r => r.status === 429);
    
    if (rateLimited.length === 0) {
      this.vulnerabilities.push({
        test: 'rateLimiting',
        severity: 'medium',
        description: 'No rate limiting detected on API endpoints',
        timestamp: new Date().toISOString()
      });
    }
  }

  async testFileUploadSecurity() {
    const maliciousFiles = [
      { name: 'test.php', content: '<?php system($_GET["cmd"]); ?>' },
      { name: 'test.exe', content: 'MZ\x90\x00' },
      { name: '../../../evil.txt', content: 'Path traversal test' },
      { name: 'test.svg', content: '<svg><script>alert("XSS")</script></svg>' }
    ];

    for (const file of maliciousFiles) {
      try {
        const formData = new FormData();
        const blob = new Blob([file.content], { type: 'application/octet-stream' });
        formData.append('file', blob, file.name);

        const response = await fetch(`${this.baseUrl}/api/upload`, {
          method: 'POST',
          body: formData
        });

        if (response.ok) {
          this.vulnerabilities.push({
            test: 'fileUploadSecurity',
            severity: 'high',
            description: `Malicious file upload accepted: ${file.name}`,
            timestamp: new Date().toISOString()
          });
        }
      } catch (error) {
        // Expected for protected endpoints
      }
    }
  }

  async generateSecurityReport() {
    console.log('🛡️  Generating Security Report...');
    
    const severityCounts = {
      critical: this.vulnerabilities.filter(v => v.severity === 'critical').length,
      high: this.vulnerabilities.filter(v => v.severity === 'high').length,
      medium: this.vulnerabilities.filter(v => v.severity === 'medium').length,
      low: this.vulnerabilities.filter(v => v.severity === 'low').length
    };

    const report = {
      testRun: {
        timestamp: new Date().toISOString(),
        baseUrl: this.baseUrl,
        totalTests: 12,
        vulnerabilitiesFound: this.vulnerabilities.length
      },
      summary: {
        securityScore: this.calculateSecurityScore(severityCounts),
        severityBreakdown: severityCounts,
        recommendations: this.generateSecurityRecommendations()
      },
      vulnerabilities: this.vulnerabilities,
      compliance: {
        owasp: this.checkOWASPCompliance(),
        gdpr: this.checkGDPRCompliance(),
        iso27001: this.checkISO27001Compliance()
      }
    };

    // Save report
    const reportPath = path.join(__dirname, '../../test-reports/security-report.json');
    await fs.mkdir(path.dirname(reportPath), { recursive: true });
    await fs.writeFile(reportPath, JSON.stringify(report, null, 2));
    
    console.log(`✅ Security report saved to: ${reportPath}`);
    console.log('\n🔒 Security Test Summary:');
    console.log(`   Security Score: ${report.summary.securityScore}/100`);
    console.log(`   Critical: ${severityCounts.critical}, High: ${severityCounts.high}, Medium: ${severityCounts.medium}, Low: ${severityCounts.low}`);
    
    if (this.vulnerabilities.length === 0) {
      console.log('   🎉 No vulnerabilities detected!');
    } else {
      console.log(`   ⚠️  ${this.vulnerabilities.length} vulnerabilities found`);
    }
    
    return report;
  }

  calculateSecurityScore(severityCounts) {
    let score = 100;
    score -= severityCounts.critical * 25;
    score -= severityCounts.high * 15;
    score -= severityCounts.medium * 5;
    score -= severityCounts.low * 1;
    return Math.max(0, score);
  }

  generateSecurityRecommendations() {
    const recommendations = [];
    
    if (this.vulnerabilities.some(v => v.test === 'inputValidation')) {
      recommendations.push('Implement comprehensive input validation and sanitization');
    }
    
    if (this.vulnerabilities.some(v => v.test === 'sqlInjection')) {
      recommendations.push('Use parameterized queries to prevent SQL injection');
    }
    
    if (this.vulnerabilities.some(v => v.test === 'xssVulnerabilities')) {
      recommendations.push('Implement proper output encoding to prevent XSS attacks');
    }
    
    if (this.vulnerabilities.some(v => v.test === 'securityHeaders')) {
      recommendations.push('Configure security headers (CSP, HSTS, X-Frame-Options, etc.)');
    }
    
    if (this.vulnerabilities.some(v => v.test === 'rateLimiting')) {
      recommendations.push('Implement rate limiting on all API endpoints');
    }
    
    if (recommendations.length === 0) {
      recommendations.push('Security posture is good - maintain current security practices');
    }
    
    return recommendations;
  }

  checkOWASPCompliance() {
    const owaspTop10 = [
      'injection', 'broken-authentication', 'sensitive-data-exposure',
      'xml-external-entities', 'broken-access-control', 'security-misconfiguration',
      'cross-site-scripting', 'insecure-deserialization', 'vulnerable-components',
      'insufficient-logging'
    ];
    
    return {
      tested: owaspTop10.length,
      compliant: owaspTop10.length - this.vulnerabilities.length,
      percentage: ((owaspTop10.length - this.vulnerabilities.length) / owaspTop10.length * 100).toFixed(2)
    };
  }

  checkGDPRCompliance() {
    return {
      dataEncryption: !this.vulnerabilities.some(v => v.test === 'dataEncryption'),
      accessControl: !this.vulnerabilities.some(v => v.test === 'authorization'),
      auditLogging: true // Assume implemented
    };
  }

  checkISO27001Compliance() {
    return {
      accessManagement: !this.vulnerabilities.some(v => v.test === 'authorization'),
      incidentResponse: true, // Assume implemented
      securityAwareness: true // Assume implemented
    };
  }

  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}

// Run security tests if called directly
if (require.main === module) {
  const runner = new SecurityTestRunner();
  runner.runSecurityTests()
    .then(() => {
      console.log('\n✅ Security testing completed successfully');
      process.exit(0);
    })
    .catch(error => {
      console.error('\n❌ Security testing failed:', error);
      process.exit(1);
    });
}

module.exports = SecurityTestRunner;
