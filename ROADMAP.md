# DocumentVault (FileVault) - Development Roadmap

DocumentVault is an offline-first, secure document management system built on **Couchbase Lite Swift** (featuring vector and hybrid search) and designed to align with professional document discovery, profiling, and compliance workflows like **NetDocuments**.

---

## 🗺️ Execution Roadmap

### 📦 Phase 1: Foundation (Current Implementation)
*   **Database Schema**: SQLite/Couchbase Lite documents collection storing `VaultDocument` metadata, folders, and annotations.
*   **AI Processing Pipeline**: Offline local ingestion supporting text extraction (PDF/TXT), Vision classification (images), and metadata indexing.
*   **Hybrid Search Engine**: Combined Full-Text Search (FTS) and vector retrieval using Reciprocal Rank Fusion (RRF) with session-level Rocchio relevance feedback (boosting query vectors toward selected documents).
*   **Tenant Separation**: Client-side domain-based tenant resolution (e.g., `you@acme-corp.com` resolves to the `acme-corp` database scope).

---

### 🚀 Phase 2: Semantic Search & Profiling Enhancements (Immediate Next Steps)
*   **Image Semantic Search Integration**:
    *   *Issue*: Currently, `EmbeddingService` returns `nil` for image extensions, meaning images are excluded from semantic searches.
    *   *Solution*: Remove the image exclusion block and allow the text embedder to embed the image's name, classification tags, dominant colors, and summaries. This yields a 512-dimension description embedding.
*   **Vector Index Optimization**:
    *   Configure the database vector index `vector_idx` to use the `.cosine` distance metric (Cosine similarity) rather than the default Euclidean (L2).
    *   Since embeddings are L2 normalized in `EmbeddingManager.l2Normalize`, Cosine distance is the industry standard and makes search results and score cutoffs much cleaner.
*   **NetDocuments-Style Metadata Profiling** (Completed):
    *   Add fields for custom profile attributes: `Client`, `Matter`, `Author`, and `Document Type` (implemented in `VaultDocument`).
    *   Support parent-child validation (implemented inline picker validation inside `DocumentDetailView`).
*   **Corporate & Legal Sample Dataset**:
    *   Generate a realistic sample JSON dataset (`document_vault_sample_dataset.json`) containing mock legal contracts, NDA templates, Q2 financial audits, and HR handbooks.
    *   Add a "Seed Sample Data" function in `DatabaseManager` accessible from `ProfileView` to populate the empty local database with rich folder trees, tagged documents, and custody chain events.
*   **Case Matter Annotation Vector Steering** (Completed):
    *   Enable users to add, resolve, and re-open annotations/case notes on documents.
    *   Unresolved annotations are automatically appended to the document's embedding target on-the-fly, auto-triggering re-vectorization to dynamically steer semantic search scores as new facts arise.

---

### 🔄 Phase 3: Sync & Peer-to-Peer Collaboration (Mid-Term)
*   **Capella App Services Sync**:
    *   Enable real-time, bi-directional sync to Couchbase Capella cluster endpoints.
    *   Enforce tenant-based access control (a user only syncs data from their resolved tenant scope).
*   **Offline Peer-to-Peer Replication**:
    *   Leverage Couchbase Lite P2P replication to sync documents directly between devices (using `MultipeerConnectivity` on iOS) over a local network.
    *   Implement folder hierarchy merging and conflict resolution policies using custom timestamps and CRDTs.

---

### 🛡️ Phase 4: Compliance & Advanced Intelligence (Long-Term)
*   **Immutable Audit Trail & Governance**:
    *   Strengthen the document `custodyChain` by hashing and signing custody events (uploaded, read, edited, archived).
    *   Expose a visual timeline view of a document's custody chain to users.
*   **Secure Document Quarantine**:
    *   Detect sensitive or suspicious documents and route them to a quarantined state.
    *   Support quarantine-specific actions (admin review, deletion, decrypt).
*   **Advanced Local CoreML Embeddings**:
    *   Transition from the Apple `NaturalLanguage` sentence embedding to a custom local CoreML transformer model (e.g., a distilled BERT variant) to provide domain-specific embeddings (such as legal-BERT) offline.

---

## 🔍 Code Improvements Checklist

- [ ] **EmbeddingService.swift**: Remove image file restriction and let visual description text fall back to the 512-dimension text embedding.
- [ ] **DatabaseManager.swift**: Add `.cosine` distance metric configuration to `VectorIndexConfiguration`.
- [ ] **DatabaseManager.swift**: Add a JSON parsing and seeding routine for the new corporate legal dataset.
- [ ] **ProfileView.swift**: Add a button to let users trigger "Seed Sample Data".
