# DocumentVault (FileVault) - Development Roadmap & Status

DocumentVault is an offline-first, secure document management system built on **Couchbase Lite** (featuring vector and hybrid search) and designed to align with professional document discovery, profiling, and compliance workflows like **NetDocuments**.

---

## 🗺️ Execution Roadmap

### 📦 Phase 1: Foundation (Completed)
*   **Database Schema**: SQLite/Couchbase Lite documents collection storing `VaultDocument` metadata, folders, and annotations.
*   **AI Processing Pipeline**: Offline local ingestion supporting text extraction (PDF/TXT), Vision classification (images), and metadata indexing.
*   **Hybrid Search Engine**: Combined Full-Text Search (FTS) and vector retrieval using Reciprocal Rank Fusion (RRF) with session-level Rocchio relevance feedback (boosting query vectors toward selected documents).
*   **Tenant Separation**: Client-side domain-based tenant resolution (e.g., `you@acme-corp.com` resolves to the `acme-corp` database scope).

---

### 🚀 Phase 2: Semantic Search & Profiling (Completed)
*   **Image Semantic Search Integration**:
    *   Unified text and image embeddings. Visual classification tags, dominant colors, and image descriptions are automatically generated and converted to vectors by the embedding service.
*   **Vector Index Optimization**:
    *   Configured the database vector index `vector_idx` to use the `.cosine` distance metric (Cosine similarity) to align similarity search with unit L2-normalized vectors.
*   **NetDocuments-Style Metadata Profiling**:
    *   Added fields for custom profile attributes: `Client`, `Matter`, `Author`, and `Document Type` (implemented in `VaultDocument`).
    *   Implemented parent-child profile field validation.
*   **Case Matter Annotation Vector Steering**:
    *   Unresolved annotations are automatically appended to the document's embedding target on-the-fly, auto-triggering re-vectorization to dynamically steer semantic search scores as new facts arise.

---

### 🔄 Phase 3: Sync, Web Portal & Multi-Platform (Completed)
*   **Capella App Services Sync**:
    *   Configured active real-time, bi-directional sync to Couchbase Capella cluster App Services (`docvault-acmecorp`).
    *   Implemented multi-collection replication syncing 6 collections (`documents`, `folders`, `annotations`, `profile`, `senders`, `threads`) in parallel.
*   **DocumentVault Web Portal**:
    *   Launched a React + TypeScript + Vite web portal on port `8081` to manage and monitor cases.
    *   Configured Vite WebSocket proxies to support secure SSL handshakes with Capella App Services.
*   **Live Sync Activity Log**:
    *   Embedded a live sync log feed directly in the web dashboard, listening to Couchbase Lite `onDocuments` events to display pulled and pushed packets in real-time.
*   **RAG Agent Chat (iOS & Web)**:
    *   **iOS**: Integrated LLM chat with native tool calling (`publish_document`, `add_annotation`) executing directly on Couchbase Lite.
    *   **Web**: Developed a browser RAG interface. Performs in-browser TF-IDF document context search on IndexedDB, automatically resolves synonyms (like `"Price Waterhouse Cooper"` to `"pwc"`), and forwards prompt contexts to Gemini, OpenAI, or a local **LM Studio/Ollama** server with automatic CORS handling.
*   **Sync Diagnostic Badges & Tab Badging**:
    *   **Web**: Live Sync Status badge reflecting status and error tooltips.
    *   **iOS**: Tightly integrated red change-count notification badges on the Tab Bar Reports tab that clear when viewed.

---

### 🛡️ Phase 4: Compliance & Advanced Intelligence (Long-Term / In-Progress)
*   **Audit Trail Custody Vectorization** (Completed):
    *   Document custody logs are vectorized alongside summary data to allow semantic and RAG queries over a file's audit trail.
*   **Immutable Audit Trail & Governance**:
    *   Cryptographically sign and hash document custody chain logs (uploads, reviews, downloads, edits).
*   **Secure Document Quarantine**:
    *   Detect sensitive or suspicious documents and route them to a quarantined state.
    *   Support quarantine-specific actions (admin review, deletion, decrypt).
*   **Advanced Local CoreML/WebAssembly Embeddings**:
    *   Transition from the Apple `NaturalLanguage` sentence embedding to a custom local transformer model to provide specialized legal domain embeddings offline.
