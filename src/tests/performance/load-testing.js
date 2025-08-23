#!/usr/bin/env node

/**
 * Load Testing Suite
 * Tests application performance under various load conditions
 */

const { Worker, isMainThread, parentPort, workerData } = require('worker_threads')
const { performance } = require('perf_hooks')
const fs = require('fs').promises
const path = require('path')

class LoadTestRunner {
  constructor () {
    this.baseUrl = process.env.BASE_URL || 'http://localhost:3000'
    this.results = []
  }

  async runLoadTests () {
    console.log('🔥 Starting Load Testing Suite...\n')

    const testScenarios = [
      { name: 'Baseline Load', users: 10, duration: 30 },
      { name: 'Medium Load', users: 50, duration: 60 },
      { name: 'High Load', users: 100, duration: 90 },
      { name: 'Stress Test', users: 200, duration: 120 },
      { name: 'Spike Test', users: 500, duration: 30 }
    ]

    for (const scenario of testScenarios) {
      console.log(`🚀 Running ${scenario.name} (${scenario.users} users, ${scenario.duration}s)...`)

      try {
        const result = await this.runLoadTestScenario(scenario)
        this.results.push(result)

        console.log(`✅ ${scenario.name} completed`)
        console.log(`   Average Response Time: ${result.avgResponseTime.toFixed(2)}ms`)
        console.log(`   Throughput: ${result.throughput.toFixed(2)} req/s`)
        console.log(`   Error Rate: ${result.errorRate.toFixed(2)}%\n`)

        // Cool down period between tests
        if (scenario !== testScenarios[testScenarios.length - 1]) {
          console.log('😴 Cooling down for 30 seconds...\n')
          await this.sleep(30000)
        }
      } catch (error) {
        console.error(`❌ ${scenario.name} failed: ${error.message}\n`)
        this.results.push({
          ...scenario,
          status: 'failed',
          error: error.message,
          timestamp: new Date().toISOString()
        })
      }
    }

    await this.generateLoadTestReport()
  }

  async runLoadTestScenario (scenario) {
    const { users, duration } = scenario
    const startTime = performance.now()

    // Create worker threads to simulate concurrent users
    const workers = []
    const results = []

    for (let i = 0; i < users; i++) {
      const worker = new Worker(__filename, {
        workerData: {
          isWorker: true,
          userId: i,
          baseUrl: this.baseUrl,
          duration: duration * 1000, // Convert to milliseconds
          testScenario: scenario.name
        }
      })

      workers.push(worker)

      worker.on('message', (data) => {
        results.push(data)
      })

      worker.on('error', (error) => {
        console.error(`Worker ${i} error:`, error)
      })
    }

    // Wait for all workers to complete
    await Promise.all(workers.map(worker => new Promise((resolve) => {
      worker.on('exit', resolve)
    })))

    const endTime = performance.now()
    const totalDuration = endTime - startTime

    // Analyze results
    const successfulRequests = results.filter(r => r.success)
    const failedRequests = results.filter(r => !r.success)

    const avgResponseTime = successfulRequests.length > 0
      ? successfulRequests.reduce((sum, r) => sum + r.responseTime, 0) / successfulRequests.length
      : 0

    const throughput = results.length / (totalDuration / 1000)
    const errorRate = (failedRequests.length / results.length) * 100

    return {
      ...scenario,
      totalRequests: results.length,
      successfulRequests: successfulRequests.length,
      failedRequests: failedRequests.length,
      avgResponseTime,
      throughput,
      errorRate,
      duration: totalDuration,
      timestamp: new Date().toISOString(),
      status: 'completed'
    }
  }

  async generateLoadTestReport () {
    console.log('📊 Generating Load Test Report...')

    const report = {
      testRun: {
        timestamp: new Date().toISOString(),
        totalScenarios: this.results.length,
        baseUrl: this.baseUrl
      },
      scenarios: this.results,
      summary: {
        peakThroughput: Math.max(...this.results.map(r => r.throughput || 0)),
        lowestErrorRate: Math.min(...this.results.map(r => r.errorRate || 100)),
        avgResponseTime: this.results.reduce((sum, r) => sum + (r.avgResponseTime || 0), 0) / this.results.length,
        recommendations: this.generateLoadTestRecommendations()
      }
    }

    // Save report
    const reportPath = path.join(__dirname, '../../test-reports/load-test-report.json')
    await fs.mkdir(path.dirname(reportPath), { recursive: true })
    await fs.writeFile(reportPath, JSON.stringify(report, null, 2))

    console.log(`✅ Load test report saved to: ${reportPath}`)
    console.log('\n📈 Load Test Summary:')
    console.log(`   Peak Throughput: ${report.summary.peakThroughput.toFixed(2)} req/s`)
    console.log(`   Lowest Error Rate: ${report.summary.lowestErrorRate.toFixed(2)}%`)
    console.log(`   Average Response Time: ${report.summary.avgResponseTime.toFixed(2)}ms`)

    return report
  }

  generateLoadTestRecommendations () {
    const recommendations = []

    this.results.forEach(result => {
      if (result.errorRate > 5) {
        recommendations.push(`${result.name}: Error rate of ${result.errorRate.toFixed(2)}% is high - investigate server capacity`)
      }

      if (result.avgResponseTime > 2000) {
        recommendations.push(`${result.name}: Average response time of ${result.avgResponseTime.toFixed(2)}ms exceeds acceptable threshold`)
      }

      if (result.throughput < 10) {
        recommendations.push(`${result.name}: Low throughput of ${result.throughput.toFixed(2)} req/s - consider performance optimization`)
      }
    })

    if (recommendations.length === 0) {
      recommendations.push('All load tests passed acceptable thresholds - system performance is good')
    }

    return recommendations
  }

  sleep (ms) {
    return new Promise(resolve => setTimeout(resolve, ms))
  }
}

// Worker thread code for simulating user requests
async function runWorkerLoad () {
  const { userId, baseUrl, duration, testScenario } = workerData
  const endTime = Date.now() + duration

  const endpoints = [
    '/',
    '/dashboard',
    '/inventory',
    '/analytics',
    '/integrations'
  ]

  while (Date.now() < endTime) {
    for (const endpoint of endpoints) {
      const startTime = performance.now()

      try {
        const response = await fetch(`${baseUrl}${endpoint}`, {
          headers: {
            'User-Agent': `LoadTest-User-${userId}`,
            'X-Test-Scenario': testScenario
          },
          timeout: 10000
        })

        const endTime = performance.now()
        const responseTime = endTime - startTime

        parentPort.postMessage({
          userId,
          endpoint,
          responseTime,
          success: response.ok,
          status: response.status,
          timestamp: new Date().toISOString()
        })
      } catch (error) {
        parentPort.postMessage({
          userId,
          endpoint,
          responseTime: 0,
          success: false,
          error: error.message,
          timestamp: new Date().toISOString()
        })
      }

      // Small delay between requests from same user
      await new Promise(resolve => setTimeout(resolve, Math.random() * 1000 + 500))
    }
  }
}

// Entry point
if (isMainThread) {
  if (require.main === module) {
    const runner = new LoadTestRunner()
    runner.runLoadTests()
      .then(() => {
        console.log('\n✅ Load testing completed successfully')
        process.exit(0)
      })
      .catch(error => {
        console.error('\n❌ Load testing failed:', error)
        process.exit(1)
      })
  }

  module.exports = LoadTestRunner
} else {
  // Worker thread
  runWorkerLoad().catch(error => {
    console.error('Worker error:', error)
    process.exit(1)
  })
}
