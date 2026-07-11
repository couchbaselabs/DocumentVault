# Contributing to DocumentVault (FileVault)

Welcome to DocumentVault! This guide will help you understand the architecture, data models, and contribution guidelines for the project.

## Table of Contents
- [Architecture Overview](#architecture-overview)
- [Server-Side Configuration](#server-side-configuration)
- [App Flow](#app-flow)
- [Data Models](#data-models)
- [Development Setup](#development-setup)
- [Contributing Guidelines](#contributing-guidelines)

---

## Architecture Overview

DocumentVault is a distributed corporate document discovery and profiling management system built with:
- **Frontend**: iOS (Swift/SwiftUI) and Web (React/TypeScript/Vite)
- **Backend**: Couchbase Capella with App Services (Sync Gateway)
- **Sync**: Bi-directional replication of 6 scope collections with Couchbase Lite
- **AI RAG Agent**: iOS native chat tools and Web local LM Studio/Ollama redirection with browser-level IndexedDB TF-IDF retrieval.

---

## Server-Side Configuration

### 1. Couchbase Bucket Structure

The `docvault` bucket contains:
- **Scope**: `acmecorp`
- **6 collections per scope**:
  - `documents`: Metadata, text content, embeddings, and custody chain events.
  - `folders`: Folder organization hierarchy.
  - `annotations`: User notes, highlights, and reviews.
  - `profile`: User account profiles.
  - `senders`: Inbound email / source identities.
  - `threads`: Case conversation logs.

```
📦 docvault (bucket)
└── 📁 acmecorp (scope)
    ├── 📚 documents
    ├── 📚 folders
    ├── 📚 annotations
    ├── 📚 profile
    ├── 📚 senders
    └── 📚 threads
```

### 2. App Service Setup

**App Endpoint**: `docvault-acmecorp` → `acmecorp` scope.

**Linked Collections**:
- ✅ `documents`
- ✅ `folders`
- ✅ `annotations`
- ✅ `profile`
- ✅ `senders`
- ✅ `threads`

### 3. User Configuration

**Username Format**: `<username>@acmecorp.com`
*   **Default profile**: `austin@acmecorp.com` / `Password123!`

---

## App Flow

### 1. Domain Resolution & Initialization
When a user logs in (e.g. `austin@acmecorp.com`):
*   The application parses the domain (`acmecorp`) and resolves it as the tenant identifier.
*   The Couchbase Lite database initializes collections dynamically matching the `acmecorp` scope.

### 2. Bi-directional Synchronization
*   The client establishes a WebSocket connection (`wss://...`) directly to the Capella App Endpoint.
*   Documents, folder trees, and annotations are synchronized in real-time.
*   On Web, the **Live Sync Activity Log** intercepts `onDocuments` replication events to display synced packets instantly.

### 3. Case Annotations Vector Steering
*   When a user writes an annotation note on a file, the system appends the comment to the file's description and triggers a recalculation of the vector embedding.
*   This shifts the document's position in vector space, immediately updating future hybrid searches and RAG prompt injections.

---

## Data Models

### 📚 documents
*   `id`: `Doc_{UUID}`
*   `docType`: `"Document"`
*   `name`: Filename (e.g., `PwC Corporate Tax Return 2026.pdf`)
*   `fileExtension`: Extension string
*   `status`: `draft`, `review`, `published`, `archived`, `quarantine` (mapped via `DocumentStatus` enum)
*   `custodyChain`: Array of custody action events.

### 📚 annotations
*   `id`: `Ann_{UUID}`
*   `docType`: `"Annotation"`
*   `documentId`: Reference ID of the document
*   `tenantId`: Resolved scope ID
*   `body`: Note content text
*   `resolved`: Boolean

---

## Contributing Guidelines

### Pull Requests
1.  **Scope Validation**: Ensure all profile and file operations conform to tenant-separated scopes.
2.  **Mock Seeding**: Keep JSON sample datasets up-to-date if adding new metadata attributes.
3.  **Cross-Platform Alignment**: If changing database schemas, modify the types in both Swift (`Models/`) and TypeScript (`lib/database/types.ts`).
