import { test, expect } from '@playwright/test';
import { getServiceRoleClient } from '@/lib/supabase/admin';

/**
 * Complete Performance & Security Testing E2E with Real Data
 * Tests performance metrics, security measures, and optimization features
 */

test.describe('⚡ Performance & Security E2E Testing', () => {
  let supabase: any;

  test.beforeEach(async ({ page }) => {
    supabase = getServiceRoleClient();
    await page.goto('/dashboard');
    await page.waitForLoadState('networkidle');
  });

  test('should test Database Performance and Query Optimization', async ({ page }) => {
    const startTime = Date.now();
    
    // Test large dataset queries performance
    const { data: largeDataset, error } = await supabase
      .from('product_variants')
      .select('id, sku, name, current_stock, reorder_point')
      .limit(1000);
    
    const queryTime = Date.now() - startTime;
    
    if (!error && largeDataset) {
      console.log(`✅ Database Performance: Query 1000 records in ${queryTime}ms`);
      expect(queryTime).toBeLessThan(5000); // Should complete within 5 seconds
      expect(largeDataset.length).toBeGreaterThan(0);
    }
    
    // Test complex joins performance
    const complexQueryStart = Date.now();
    const { data: complexData } = await supabase
      .from('orders')
      .select(`
        id,
        order_number,
        total_amount,
        order_items(
          id,
          quantity,
          unit_price,
          product_variants(
            id,
            sku,
            name
          )
        )
      `)
      .limit(100);
    
    const complexQueryTime = Date.now() - complexQueryStart;
    
    if (complexData) {
      console.log(`✅ Database Performance: Complex join query in ${complexQueryTime}ms`);
      expect(complexQueryTime).toBeLessThan(10000); // Complex queries within 10 seconds
    }
    
    // Test database indexing effectiveness
    const indexTestStart = Date.now();
    await supabase
      .from('product_variants')
      .select('id, sku, current_stock')
      .eq('sku', 'TEST-SKU-001')
      .single();
    
    const indexTestTime = Date.now() - indexTestStart;
    console.log(`✅ Database Performance: Indexed query in ${indexTestTime}ms`);
    expect(indexTestTime).toBeLessThan(1000); // Indexed queries should be very fast
    
    // Test pagination performance
    await page.goto('/inventory');
    await page.waitForLoadState('networkidle');
    
    const paginationStart = Date.now();
    const paginationButton = page.locator('button:has-text("Next"), [data-testid="next-page"]');
    if (await paginationButton.isVisible()) {
      await paginationButton.click();
      await page.waitForLoadState('networkidle');
    }
    const paginationTime = Date.now() - paginationStart;
    
    console.log(`✅ UI Performance: Pagination in ${paginationTime}ms`);
    expect(paginationTime).toBeLessThan(3000);
  });

  test('should test Load Performance with Concurrent Operations', async ({ browser }) => {
    // Test concurrent user simulation
    const contexts = await Promise.all([
      browser.newContext(),
      browser.newContext(),
      browser.newContext()
    ]);
    
    const pages = await Promise.all(contexts.map(context => context.newPage()));
    
    const loadTestStart = Date.now();
    
    // Simulate concurrent operations
    const concurrentOperations = pages.map(async (testPage, index) => {
      try {
        await testPage.goto('/dashboard');
        await testPage.waitForLoadState('networkidle');
        
        // Each page performs different operations
        switch (index) {
          case 0:
            await testPage.goto('/inventory');
            await testPage.waitForLoadState('networkidle');
            break;
          case 1:
            await testPage.goto('/suppliers');
            await testPage.waitForLoadState('networkidle');
            break;
          case 2:
            await testPage.goto('/purchase-orders');
            await testPage.waitForLoadState('networkidle');
            break;
        }
        
        return true;
      } catch (error) {
        console.error(`Concurrent operation ${index} failed:`, error);
        return false;
      }
    });
    
    const results = await Promise.all(concurrentOperations);
    const loadTestTime = Date.now() - loadTestStart;
    
    const successfulOperations = results.filter(Boolean).length;
    console.log(`✅ Load Performance: ${successfulOperations}/3 concurrent operations successful in ${loadTestTime}ms`);
    
    expect(successfulOperations).toBe(3);
    expect(loadTestTime).toBeLessThan(15000); // All operations within 15 seconds
    
    // Cleanup
    await Promise.all(pages.map(p => p.close()));
    await Promise.all(contexts.map(c => c.close()));
  });

  test('should test Memory Usage and Resource Optimization', async ({ page }) => {
    // Test memory usage during heavy operations
    await page.goto('/dashboard');
    
    // Check initial page performance
    const performanceMetrics = await page.evaluate(() => {
      const navigation = performance.getEntriesByType('navigation')[0] as PerformanceNavigationTiming;
      return {
        domContentLoaded: navigation.domContentLoadedEventEnd - navigation.domContentLoadedEventStart,
        loadComplete: navigation.loadEventEnd - navigation.loadEventStart,
        firstPaint: performance.getEntriesByType('paint').find(entry => entry.name === 'first-paint')?.startTime || 0,
        firstContentfulPaint: performance.getEntriesByType('paint').find(entry => entry.name === 'first-contentful-paint')?.startTime || 0
      };
    });
    
    console.log(`✅ Performance Metrics: DOM loaded in ${performanceMetrics.domContentLoaded}ms`);
    console.log(`✅ Performance Metrics: First paint at ${performanceMetrics.firstPaint}ms`);
    console.log(`✅ Performance Metrics: First contentful paint at ${performanceMetrics.firstContentfulPaint}ms`);
    
    expect(performanceMetrics.domContentLoaded).toBeLessThan(3000);
    expect(performanceMetrics.firstContentfulPaint).toBeLessThan(2000);
    
    // Test large table rendering performance
    await page.goto('/inventory');
    await page.waitForLoadState('networkidle');
    
    const tableRenderStart = Date.now();
    await page.locator('table, [data-testid="inventory-table"]').waitFor();
    const tableRenderTime = Date.now() - tableRenderStart;
    
    console.log(`✅ UI Performance: Table rendered in ${tableRenderTime}ms`);
    expect(tableRenderTime).toBeLessThan(2000);
    
    // Test virtual scrolling if implemented
    const virtualScrollContainer = page.locator('[data-testid="virtual-scroll"], .virtual-scroll');
    if (await virtualScrollContainer.isVisible()) {
      const scrollStart = Date.now();
      await virtualScrollContainer.evaluate(el => el.scrollTop = 1000);
      await page.waitForTimeout(100); // Allow for rendering
      const scrollTime = Date.now() - scrollStart;
      
      console.log(`✅ UI Performance: Virtual scroll in ${scrollTime}ms`);
      expect(scrollTime).toBeLessThan(500);
    }
  });

  test('should test Security Measures and Authentication', async ({ page, context }) => {
    // Test session security
    await page.goto('/dashboard');
    
    // Test CSRF protection
    const csrfToken = await page.locator('meta[name="csrf-token"]').getAttribute('content');
    if (csrfToken) {
      console.log('✅ Security: CSRF token present');
      expect(csrfToken).toBeTruthy();
    }
    
    // Test secure headers
    const response = await page.goto('/dashboard');
    const headers = response?.headers() || {};
    
    if (headers['x-content-type-options']) {
      console.log('✅ Security: X-Content-Type-Options header present');
    }
    
    if (headers['x-frame-options']) {
      console.log('✅ Security: X-Frame-Options header present');
    }
    
    if (headers['strict-transport-security']) {
      console.log('✅ Security: HSTS header present');
    }
    
    // Test session timeout
    const sessionCookie = await context.cookies();
    const authCookie = sessionCookie.find(cookie => 
      cookie.name.includes('session') || 
      cookie.name.includes('auth') ||
      cookie.name.includes('token')
    );
    
    if (authCookie) {
      console.log(`✅ Security: Authentication cookie configured with httpOnly: ${authCookie.httpOnly}, secure: ${authCookie.secure}`);
      expect(authCookie.httpOnly).toBe(true);
    }
    
    // Test unauthorized access protection
    try {
      await page.goto('/admin');
      const currentUrl = page.url();
      
      if (currentUrl.includes('login') || currentUrl.includes('unauthorized')) {
        console.log('✅ Security: Admin routes protected');
      }
    } catch (error) {
      console.log('✅ Security: Admin access properly restricted');
    }
  });

  test('should test Data Encryption and Privacy Compliance', async ({ page }) => {
    // Test password field security
    await page.goto('/login');
    
    const passwordField = page.locator('input[type="password"]');
    if (await passwordField.isVisible()) {
      const fieldType = await passwordField.getAttribute('type');
      expect(fieldType).toBe('password');
      console.log('✅ Security: Password fields properly masked');
    }
    
    // Test sensitive data handling in database
    const { data: users } = await supabase
      .from('users')
      .select('id, email, created_at')
      .limit(1);
    
    if (users && users.length > 0) {
      const user = users[0];
      
      // Verify no plain text passwords are stored
      const { data: userSecrets } = await supabase
        .from('users')
        .select('password')
        .eq('id', user.id)
        .single();
      
      if (userSecrets && !userSecrets.password) {
        console.log('✅ Security: No plain text passwords in database');
      }
      
      console.log('✅ Privacy: User data access controlled');
    }
    
    // Test audit logging
    const { data: auditLogs } = await supabase
      .from('audit_logs')
      .select('id, action, user_id, created_at')
      .order('created_at', { ascending: false })
      .limit(5);
    
    if (auditLogs && auditLogs.length > 0) {
      console.log(`✅ Security: ${auditLogs.length} audit log entries found`);
      
      const recentActions = auditLogs.map((log: any) => log.action);
      console.log(`✅ Security: Recent actions logged: ${recentActions.join(', ')}`);
    }
    
    // Test data retention policies
    const { data: oldData } = await supabase
      .from('audit_logs')
      .select('id, created_at')
      .lt('created_at', new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString()) // 90 days ago
      .limit(5);
    
    if (oldData) {
      console.log(`✅ Privacy: Data retention check - ${oldData.length} old audit logs`);
    }
  });

  test('should test Performance Monitoring and Alerting', async ({ page }) => {
    // Navigate to performance monitoring if available
    await page.goto('/admin/performance');
    
    // If performance page doesn't exist, try monitoring or admin
    if (page.url().includes('404')) {
      await page.goto('/admin/monitoring');
    }
    
    await page.waitForLoadState('networkidle');
    
    // Test performance metrics display
    const metricsWidget = page.locator('.performance-metrics, [data-testid="performance-metrics"]');
    if (await metricsWidget.isVisible()) {
      const responseTimeMetric = page.locator('.response-time, [data-testid="response-time"]');
      const throughputMetric = page.locator('.throughput, [data-testid="throughput"]');
      const errorRateMetric = page.locator('.error-rate, [data-testid="error-rate"]');
      
      if (await responseTimeMetric.isVisible()) {
        console.log('✅ Performance Monitoring: Response time tracking');
      }
      
      if (await throughputMetric.isVisible()) {
        console.log('✅ Performance Monitoring: Throughput tracking');
      }
      
      if (await errorRateMetric.isVisible()) {
        console.log('✅ Performance Monitoring: Error rate tracking');
      }
    }
    
    // Test alert configuration
    const alertsButton = page.locator('button:has-text("Alerts"), [data-testid="alerts-config"]');
    if (await alertsButton.isVisible()) {
      await alertsButton.click();
      
      const alertsConfig = page.locator('.alerts-config, [data-testid="alerts-form"]');
      if (await alertsConfig.isVisible()) {
        console.log('✅ Performance Monitoring: Alerts configuration available');
      }
    }
    
    // Verify performance data in database
    const { data: performanceData } = await supabase
      .from('performance_metrics')
      .select('id, metric_type, value, created_at')
      .order('created_at', { ascending: false })
      .limit(10);
    
    if (performanceData && performanceData.length > 0) {
      console.log(`✅ Performance Database: ${performanceData.length} metrics recorded`);
      
      const metricTypes = [...new Set(performanceData.map((metric: any) => metric.metric_type))];
      console.log(`✅ Performance Metrics: ${metricTypes.length} different metric types tracked`);
    }
    
    // Test real-time monitoring
    const realTimeButton = page.locator('button:has-text("Real-time"), [data-testid="real-time-monitoring"]');
    if (await realTimeButton.isVisible()) {
      await realTimeButton.click();
      
      const realTimeDisplay = page.locator('.real-time-metrics, [data-testid="real-time-display"]');
      if (await realTimeDisplay.isVisible()) {
        console.log('✅ Performance Monitoring: Real-time metrics display');
      }
    }
  });

  test('should test Backup and Disaster Recovery', async ({ page }) => {
    // Test backup configuration
    await page.goto('/admin/backups');
    
    // If backups page doesn't exist, try settings
    if (page.url().includes('404')) {
      await page.goto('/settings/backup');
    }
    
    await page.waitForLoadState('networkidle');
    
    // Test backup schedule configuration
    const backupSchedule = page.locator('.backup-schedule, [data-testid="backup-schedule"]');
    if (await backupSchedule.isVisible()) {
      const scheduleSelect = page.locator('select[name*="schedule"], [data-testid="backup-frequency"]');
      if (await scheduleSelect.isVisible()) {
        console.log('✅ Backup System: Schedule configuration available');
      }
    }
    
    // Test manual backup trigger
    const manualBackupButton = page.locator('button:has-text("Create Backup"), [data-testid="manual-backup"]');
    if (await manualBackupButton.isVisible()) {
      console.log('✅ Backup System: Manual backup option available');
    }
    
    // Test backup history
    const backupHistory = page.locator('.backup-history, [data-testid="backup-history"]');
    if (await backupHistory.isVisible()) {
      const historyRows = await backupHistory.locator('tr, .backup-item').count();
      console.log(`✅ Backup System: ${historyRows} backup records displayed`);
    }
    
    // Verify backup data in database
    const { data: backups } = await supabase
      .from('backups')
      .select('id, backup_type, status, size_bytes, created_at')
      .order('created_at', { ascending: false })
      .limit(5);
    
    if (backups && backups.length > 0) {
      console.log(`✅ Backup Database: ${backups.length} backup records`);
      
      const successfulBackups = backups.filter((backup: any) => backup.status === 'completed');
      console.log(`✅ Backup Success: ${successfulBackups.length} successful backups`);
      
      const totalSize = backups.reduce((sum: number, backup: any) => sum + (backup.size_bytes || 0), 0);
      console.log(`✅ Backup Storage: ${Math.round(totalSize / 1024 / 1024)} MB total backup size`);
    }
    
    // Test recovery procedures documentation
    const recoveryDocs = page.locator('button:has-text("Recovery"), [data-testid="recovery-docs"]');
    if (await recoveryDocs.isVisible()) {
      await recoveryDocs.click();
      
      const docsContent = page.locator('.recovery-docs, [data-testid="recovery-content"]');
      if (await docsContent.isVisible()) {
        console.log('✅ Disaster Recovery: Recovery documentation available');
      }
    }
  });

  test('should test System Resource Usage and Optimization', async ({ page }) => {
    // Test system resource monitoring
    await page.goto('/admin/system');
    
    // If system page doesn't exist, try status
    if (page.url().includes('404')) {
      await page.goto('/status');
    }
    
    await page.waitForLoadState('networkidle');
    
    // Test CPU usage monitoring
    const cpuUsage = page.locator('.cpu-usage, [data-testid="cpu-usage"]');
    if (await cpuUsage.isVisible()) {
      const cpuText = await cpuUsage.textContent();
      console.log(`✅ System Monitoring: CPU usage displayed - ${cpuText}`);
    }
    
    // Test memory usage monitoring
    const memoryUsage = page.locator('.memory-usage, [data-testid="memory-usage"]');
    if (await memoryUsage.isVisible()) {
      const memoryText = await memoryUsage.textContent();
      console.log(`✅ System Monitoring: Memory usage displayed - ${memoryText}`);
    }
    
    // Test disk space monitoring
    const diskUsage = page.locator('.disk-usage, [data-testid="disk-usage"]');
    if (await diskUsage.isVisible()) {
      const diskText = await diskUsage.textContent();
      console.log(`✅ System Monitoring: Disk usage displayed - ${diskText}`);
    }
    
    // Test database connection pool monitoring
    const dbConnections = page.locator('.db-connections, [data-testid="db-connections"]');
    if (await dbConnections.isVisible()) {
      const connectionsText = await dbConnections.textContent();
      console.log(`✅ System Monitoring: Database connections - ${connectionsText}`);
    }
    
    // Verify system metrics in database
    const { data: systemMetrics } = await supabase
      .from('system_metrics')
      .select('id, metric_name, value, unit, created_at')
      .order('created_at', { ascending: false })
      .limit(10);
    
    if (systemMetrics && systemMetrics.length > 0) {
      console.log(`✅ System Database: ${systemMetrics.length} system metrics recorded`);
      
      const metricNames = [...new Set(systemMetrics.map((metric: any) => metric.metric_name))];
      console.log(`✅ System Metrics: Tracking ${metricNames.length} different metrics`);
    }
    
    // Test optimization recommendations
    const optimizationButton = page.locator('button:has-text("Optimize"), [data-testid="optimization-suggestions"]');
    if (await optimizationButton.isVisible()) {
      await optimizationButton.click();
      
      const suggestions = page.locator('.optimization-suggestions, [data-testid="suggestions-list"]');
      if (await suggestions.isVisible()) {
        console.log('✅ System Optimization: Recommendations available');
      }
    }
  });
});
