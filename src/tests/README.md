# AIventory Testing Guide

This document provides instructions on how to run the different test suites for the AIventory application. The project uses a combination of Vitest for unit tests, Playwright for End-to-End (E2E) tests, and a Python-based suite for comprehensive business logic and data integrity validation.

## Prerequisites

Before running any tests, ensure you have installed all the necessary dependencies.

### 1. Node.js Dependencies

Install all the required `npm` packages, including Playwright browsers:

```bash
npm install
npx playwright install --with-deps
```

### 2. Python Dependencies

The advanced business logic tests are written in Python. Install the required packages using pip:

```bash
# Navigate to the root of the project first
pip install -r tests/requirements.txt
```

### 3. Environment Variables

Ensure your `.env` file is properly configured with your Supabase credentials and a `TESTING_API_KEY`. The tests will fail if these are not set up correctly.

---

## Running JavaScript/TypeScript Tests

These tests use the `npm` scripts defined in `package.json`.

### End-to-End (E2E) Tests with Playwright

These tests simulate real user interactions in a browser.

-   **Run all E2E tests in headless mode (for CI/CD):**
    ```bash
    npm run test:e2e
    ```

-   **Run E2E tests with the Playwright UI for debugging:**
    ```bash
    npm run test:e2e:ui
    ```

### Unit Tests with Vitest

These tests check individual functions and components in isolation.

-   **Run all unit tests once:**
    ```bash
    npm run test:unit
    ```

-   **Run unit tests in watch mode for active development:**
    ```bash
    npm run test:unit:watch
    ```

### Run All JavaScript Tests

To run both the unit and E2E tests sequentially:
```bash
npm run test:all
```

---

## Running the Python Test Suite

This is a comprehensive suite that tests API endpoints, business logic against the database, and AI features.

To run the master test script, execute the following command from the **root directory of the project**:

```bash
python3 tests/run_all_tests.py
```

This will:
1.  Validate the test environment.
2.  Run all Python-based test suites (`api_tests.py`, `business_logic_tests.py`, etc.).
3.  Generate a detailed HTML and JSON report in the `test_reports/` directory.
