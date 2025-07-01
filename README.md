
# InvoChat - Conversational Inventory Intelligence

This is a Next.js starter project for InvoChat, an AI-powered inventory management application.

## Getting Started

To run the application locally, you'll need to set up your environment variables and install the dependencies.

### 1. Configuration

This project requires a few environment variables to connect to its services.

1.  Make a copy of the example environment file:
    ```bash
    cp .env.example .env
    ```
2.  Open the newly created `.env` file and add your credentials. The file contains comments explaining where to find each value.

### 2. Install Dependencies

Install the project dependencies using npm:
```bash
npm install
```

### 3. Database Setup

For the application to function correctly, you must run a one-time setup script in your Supabase project's SQL Editor. This script is required to handle new user signups and enable the AI's ability to query your data.

1. Navigate to the **SQL Editor** in your Supabase project dashboard.
2. Open the file `src/lib/database-schema.ts` in this project.
3. Copy the entire content of the `SETUP_SQL_SCRIPT` constant.
4. Paste the SQL code into the Supabase SQL Editor and click **"Run"**.

After running the script, you will need to sign out and sign up with a **new user account**. This new account will be correctly configured by the database trigger you just created.

### 4. Run the Development Server

Once your environment is configured and dependencies are installed, you can start the development server:

```bash
npm run dev
```

The application will be available at `http://localhost:3000`.

## Core Technologies

*   **Framework**: [Next.js](https://nextjs.org/)
*   **Styling**: [Tailwind CSS](https://tailwindcss.com/)
*   **UI Components**: [ShadCN UI](https://ui.shadcn.com/)
*   **Database**: [Supabase](https://supabase.com/)
*   **AI**: [Google AI & Genkit](https://firebase.google.com/docs/genkit)
*   **Authentication**: [Supabase Auth](https://supabase.com/docs/guides/auth)

## Deployment & Scaling

This application is configured for deployment on Firebase App Hosting.

### Auto-scaling

For production environments with a large number of users, you may need to adjust the auto-scaling configuration. In the `apphosting.yaml` file, you can increase the `maxInstances` value to allow App Hosting to automatically spin up more server instances in response to increased traffic.

```yaml
# apphosting.yaml
runConfig:
  # Increase this value for better performance under load
  maxInstances: 10
```

### Database Performance

The application's dashboard has been optimized to perform expensive calculations at the database level, and it uses a Redis-based caching layer to reduce redundant queries. For even larger datasets, consider implementing materialized views for your most frequent and complex analytical queries.
