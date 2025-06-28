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

### 3. Run the Development Server

Once your environment is configured and dependencies are installed, you can start the development server:

```bash
npm run dev
```

The application will be available at `http://localhost:9003`.

### 4. Database Setup

For the application to function correctly, you must run a one-time setup script in your Supabase project's SQL Editor. This script is required to handle new user signups and enable the AI's ability to query your data.

If you sign up and see a "Setup Incomplete" page, copy the SQL code provided on that page and run it in the Supabase SQL Editor. After running the script, you will need to sign out and sign up with a **new user account**.

## Core Technologies

*   **Framework**: [Next.js](https://nextjs.org/)
*   **Styling**: [Tailwind CSS](https://tailwindcss.com/)
*   **UI Components**: [ShadCN UI](https://ui.shadcn.com/)
*   **Database**: [Supabase](https://supabase.com/)
*   **AI**: [Google AI & Genkit](https://firebase.google.com/docs/genkit)
*   **Authentication**: [Supabase Auth](https://supabase.com/docs/guides/auth)