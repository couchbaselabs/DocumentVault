# DocumentVault Web Portal

A secure, modern web dashboard and case portal for **DocumentVault**, built with React, TypeScript, and Vite. It integrates directly with **Couchbase Lite for JavaScript** to manage document lifecycles offline and synchronizes in real-time with cloud backend App Services on Couchbase Capella.

---

## 🚀 Key Features

*   **📊 Document & Matter Analytics**: Instantly displays total document counts, folder structures, and annotations retrieved from Couchbase Lite local collections.
*   **📡 Real-Time Sync Indicators**: Integrates a live **Sync Status Badge** showing connection states (`Syncing`, `Synced`, `Sync Error` with hover diagnostics) by listening directly to replicator status events.
*   **📡 Live Sync Activity Log**: Renders a scrolling, monospaced logs panel showing Couchbase Lite `onDocuments` push/pull transactions (packet sizes and collection names) in real-time.
*   **💬 Local RAG Agent Chat**:
    *   **Local Search Retrieval**: Performs fast, local TF-IDF document search on IndexedDB inside the browser to compile context.
    *   **Synonym Expansion**: Automatically expands common litigation search terms (e.g. mapping `"Price Waterhouse Cooper"` to `"pwc"`) to retrieve the right files.
    *   **LLM Choice**: Connects to **Google Gemini** or **OpenAI** APIs.
    *   **Local LLM Integration (LM Studio / Ollama)**: Configurable endpoints to route prompt completions to local offline models (like Llama 3 on `http://localhost:1234/v1`).
    *   **AI Tool Calling**: Resolves LLM bracket tags to execute database operations (`publish_document` or `add_annotation`) locally.
    *   **Auto-Ingest Fallback**: If the agent is instructed to annotate a non-existent file, it automatically ingests a new draft document record first to keep the action successful.
*   **🌱 Offline Sandbox Seeder**: Includes a developer seeding panel to immediately populate IndexedDB with mock folders and document nodes if starting without a Capella connection.

---

## 🛠️ Tech Stack

*   **Frontend**: React 18 + TypeScript + Vite
*   **UI System**: Tailwind CSS + Lucide Icons + Radix (via shadcn/ui)
*   **Local Database**: `@couchbase/lite-js` (Dexie.js / IndexedDB storage)
*   **State & Sync Management**: TanStack React Query + Replicator Event Dispatchers

---

## 🏃 Prerequisites

1.  **Node.js**: Version 18 or higher.
2.  **Couchbase Capella App Endpoint**: Ensure your App Services endpoint (`docvault-acmecorp`) is active and has enabled CORS origins:
    *   **Allowed Origin**: `http://localhost:8081` (and/or `http://localhost:8080`)
    *   **Login Origin**: `http://localhost:8081`
    *   **Allowed Headers**: `Authorization, Content-Type`
    *(No trailing slashes in CORS URLs!)*

---

## 📥 Setup & Installation

### 1. Configure Environment
Copy the example environment template:
```bash
cp .env.example .env
```
Ensure your Capella App Services WebSocket URL is defined:
```env
VITE_APP_SERVICES_URL=wss://your-endpoint-id.apps.cloud.couchbase.com:4984
```

### 2. Install Dependencies
```bash
npm install
```

### 3. Start Development Server
```bash
npm run dev
```
By default, if port `8080` is occupied, Vite will serve the portal on **`http://localhost:8081`**.

---

## 👤 Authentication
Log in using your resolved tenant email profile matching Capella App Users:
*   **Email**: `austin@acmecorp.com`
*   **Password**: `Password123!`

The domain resolver automatically maps `@acmecorp.com` to the Couchbase database scope `acmecorp` to establish secure sync partitions.
