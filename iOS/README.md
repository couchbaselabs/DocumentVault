# Couchbase Lite DocumentVault - iOS

An offline-first, secure document management vault (FileVault) for iOS demonstrating Couchbase Lite's vector search, hybrid search, real-time sync with Capella App Services, and peer-to-peer collaboration.

---

## 📂 DocumentVault Features & Architectural Updates

### 🧠 Semantic & Hybrid Search Engines
* **Vector Configuration**: The database vector index `vector_idx` has been optimized to use the `.cosine` (Cosine similarity) metric to align similarity search with the unit L2-normalized query and document vectors.
* **Scanned Image Vectorization**: Removed image constraints from the embedding service to generate semantic text-based embeddings for image/camera documents based on their name, visual classification tags, and summary descriptors.
* **Hybrid Search Integration**: Merges Full-Text Search (FTS) and vector retrieval using Reciprocal Rank Fusion (RRF) and leverages session-level Rocchio relevance feedback to dynamically adjust user query vectors.

### 🌱 Seed Sample Dataset
* Includes a precompiled corporate legal dataset ([document_vault_sample_dataset.json](../datasets/document_vault_sample_dataset.json)) featuring folders and metadata-rich records (NDAs, CEO tax filings, Deloitte audits, HR handbooks, DB specs).
* Accessible from the **Developer Tools** section in [ProfileView.swift](./DocumentVault/ProfileView.swift), developers can trigger **"Seed Sample Corporate Data"** to automatically insert documents and folders and generate vector embeddings on-device on-the-fly.

---

## 🗺️ DocumentVault Development Roadmap

### Phase 1: Foundation (Completed)
* Local SQLite/Couchbase Lite schema for document metadata, folders, and custody events.
* Local processing pipeline supporting PDF/TXT OCR, Vision categorization, and summaries.
* Hybrid search with Rocchio query refinement and domain-based tenant scopes.

### Phase 2: Enhanced Profiling (Completed)
* Added custom NetDocuments-style profile metadata: `Client`, `Matter`, `Author`, and `Document Type` to local SQLite collections.
* Implemented parent-child profile field validation logic in detail views.
* Enabled case matter annotation vector steering, appending unresolved notes to document descriptions.

### Phase 3: Sync & Multi-Platform (Completed)
* Real-time tenant-scoped sync configuration to Couchbase Capella cluster endpoints (`docvault-acmecorp`).
* Replicated 6 collections (documents, folders, annotations, user profile, senders, threads) in parallel.
* Created web companion portal on port `8081` with live activity telemetry.
* Enabled iPad RAG Chat tool calling to save annotations and publish local files directly from AI conversation.

### Phase 4: Compliance & Advanced Intelligence (Long-Term / In-Progress)
* **Audit Trail Custody Vectorization** (Completed): Document custody chain is appended to embedding text targets to make audit logs searchable via vector space.
* Cryptographically sign and hash document custody chain logs (uploads, reviews, downloads, edits).
* Expose visual history timeline graphs for documents.
* Implement a CoreML-based local transformer (e.g., legal-BERT) for highly specialized domain embeddings offline.

---

## 🏗️ System & Data Architecture

### 1. Couchbase Server / Capella Database Topology
The cloud backend stores data inside a single bucket mapped to dynamic corporate scopes representing tenants:
```
📦 DocumentVault (Bucket)
├── 📁 acme-corp (Scope / Tenant ID)
│   ├── 📚 documents (Collection: metadata, embeddings, FTS texts)
│   ├── 📚 folders (Collection: folder configurations)
│   ├── 📚 annotations (Collection: highlights and reviews)
│   ├── 📚 profile (Collection: user/tenant settings)
│   ├── 📚 senders (Collection: email/ingest identities)
│   └── 📚 threads (Collection: conversation threads)
```

### 2. In-App Couchbase Lite Data Structure
Couchbase Lite mirrors the Capella structure locally inside `DocumentVaultDB.cblite2` with optimized indexing for quick offline retrieval:
* **Collections**:
  * `documents`: Main model (`VaultDocument`) storing the document hash, text extraction `textContent`, LLM `summary`, 512-dimension vector `embedding`, and full append-only `custodyChain`.
  * `folders`: Workspace hierarchies (`Folder`).
  * `annotations`: User highlights/reviews (`Annotation`).
* **Indexes**:
  * `vector_idx`: Vector search index configured on the `embedding` property utilizing **Cosine similarity** (512 dimensions, centroids = 1). Vector embeddings are generated on-device from a combined target of the cleaned filename and the AI summary (or tag surrogate fallback for images), enabling highly precise semantic search targets.
  * `fts_idx`: Full-Text Search index tracking `name`, `textContent`, `summary`, and `tags` to power keyword queries.
  * `folder_idx`, `updated_idx`, `owner_idx`: Value indexes for fast folder hierarchy navigation.

### 3. iOS Application Folder Structure
```
iOS/
├── DocumentVault/
│   ├── DocumentVaultApp.swift           # Application entry point (@main)
│   ├── AppConfig.swift                 # Configuration & tenant resolver
│   ├── DatabaseManager.swift           # Database lifecycle, indexes, and queries
│   ├── SampleSeeder.swift              # Local corporate sample data seeder
│   ├── DocumentProcessingPipeline.swift # Ingestion pipeline
│   ├── EmbeddingManager.swift          # CoreML-based word/sentence vector extractor
│   ├── EmbeddingService.swift          # Embedding routing interface
│   ├── Views/
│   │   ├── SearchView.swift            # Keyword & hybrid RRF search
│   │   ├── FolderBrowserView.swift     # Hierarchy explorer
│   │   └── ProfileView.swift           # User settings and developer tools
│   └── Models/
│       ├── VaultDocument.swift         # Metadata, custody chains, and status
│       └── StoreProfile.swift          # Folders, annotations, and profiles
```

---

## Prerequisites

> [!IMPORTANT]
> Before proceeding with the iOS setup, you **must** complete the Capella backend configuration described in the [root README](../README.md). This includes creating a Capella cluster, deploying an App Service, setting up the bucket/scopes/collections, importing the sample dataset, creating App Endpoints and App Users, and recording the public connection URL. If you skip these steps, the app will fail to authenticate and sync.

## Requirements

- **Xcode**: 16.4 or later
- **iOS**: 18.5 or later
- **Swift**: 6.0 (included with Xcode)
- **macOS**: Sonoma or later (for running Xcode 16.4)

## Dependencies

The project uses Swift Package Manager (SPM) for dependency management. Dependencies are automatically resolved when you open the project:

- **Couchbase Lite Swift**: 3.3.0 (Enterprise Edition)

## Getting Started

### 1. Create Info.plist (Required Before Building)

> [!IMPORTANT]
> `Info.plist` is **not** included in the repository but is required by the Xcode project. You must create it before attempting to build, or the build will fail with:
> ```
> unable to read input file '.../GroceryApp/Info.plist': Operation not permitted
> ```

Create the file at `GroceryApp/Info.plist` with your Capella App Services credentials:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CBL_BASE_URL</key>
    <string>wss://your-endpoint.apps.cloud.couchbase.com:4984</string>
    <key>CBL_AA_DB</key>
    <string>supermarket-aa</string>
    <key>CBL_NYC_DB</key>
    <string>supermarket-nyc</string>
    <key>CBL_AA_USER</key>
    <string>aa-store-01@supermarket.com</string>
    <key>CBL_NYC_USER</key>
    <string>nyc-store-01@supermarket.com</string>
    <key>CBL_PASSWORD</key>
    <string>P@ssword1</string>
</dict>
</plist>
```

**Where to find `CBL_BASE_URL`**: In your Capella dashboard, go to **App Services** > select your App Endpoint (e.g. `supermarket-nyc`) > **Connect** tab. Copy the **Public Connection URL** — it will look like `wss://<id>.apps.cloud.couchbase.com:4984`. Use only the base URL; do **not** append the database name (that is handled separately by `CBL_AA_DB` / `CBL_NYC_DB`).

### 2. Open the Project

Open the Xcode project:

```bash
cd iOS
open GroceryApp.xcodeproj
```

Xcode will automatically resolve and download the required Swift packages when you first open the project.

### 3. Configure Capella App Services (Alternative Methods)

If you prefer not to use `Info.plist` for configuration, you have two other options. The app checks environment variables first, then falls back to Info.plist.

#### Option A: Environment Variables (Terminal Launch)

Set environment variables in your shell:

```bash
export CBL_BASE_URL="wss://your-endpoint.apps.cloud.couchbase.com:4984"
export CBL_AA_DB="supermarket-aa"
export CBL_NYC_DB="supermarket-nyc"
export CBL_AA_USER="aa-store-01@supermarket.com"
export CBL_NYC_USER="nyc-store-01@supermarket.com"
export CBL_PASSWORD="P@ssword1"
```

Then launch Xcode from the terminal to inherit these variables:

```bash
open GroceryApp.xcodeproj
```

#### Option B: Xcode Scheme Configuration

1. In Xcode, select **Product** > **Scheme** > **Edit Scheme**
2. Go to **Run** > **Arguments** tab
3. Add the environment variables under **Environment Variables**:
   - `CBL_BASE_URL`: `wss://your-endpoint.apps.cloud.couchbase.com:4984`
   - `CBL_AA_DB`: `supermarket-aa`
   - `CBL_NYC_DB`: `supermarket-nyc`
   - `CBL_AA_USER`: `aa-store-01@supermarket.com`
   - `CBL_NYC_USER`: `nyc-store-01@supermarket.com`
   - `CBL_PASSWORD`: `P@ssword1`

> [!NOTE]
> An `Info.plist` file is still required for the build to succeed, even when using environment variables. You can create a minimal **valid** plist (containing a root dict) if you prefer to configure credentials via environment variables only.

### 4. Build and Run

Select a simulator or connected device and click **Run** (⌘R).

## Project Structure

```
iOS/
├── GroceryApp/
│   ├── GroceryAppApp.swift              # Main app entry point (@main)
│   ├── App.swift                        # P2P sync helper (GrocerySyncApp, Network Framework)
│   ├── AppConfig.swift                  # Configuration (database, sync, stores)
│   ├── DatabaseManager.swift            # Couchbase Lite database operations
│   ├── AppServicesSyncManager.swift     # Sync with Capella App Services
│   ├── GroceryMultipeerSyncManager.swift # Peer-to-peer sync
│   ├── AuthenticationManager.swift      # User authentication
│   ├── Views/
│   │   ├── LoginView.swift
│   │   ├── InventoryView.swift
│   │   ├── OrdersView.swift
│   │   └── StoreProfileView.swift
│   └── Models/
│       ├── GroceryItem.swift
│       ├── Order.swift
│       └── StoreProfile.swift
└── GroceryApp.xcodeproj
```

## Configuration Details

### Database Settings

- **Database Name**: `GroceryInventoryDB`
- **Scopes**: `AA-Store`, `NYC-Store` (based on selected store)
- **Collections**: 
  - `inventory` - Product inventory items
  - `orders` - Customer orders
  - `profile` - Store profile information

### Sync Configuration

The app uses continuous replication, which is event-driven (not polling). Changes are pushed and pulled immediately over a persistent WebSocket connection to Capella App Services.

Key settings in `AppConfig.swift`:
- `syncContinuous`: Enables real-time bidirectional sync
- `enableAppServicesSync`: Toggle cloud sync on/off
- `enableP2PSync`: Toggle peer-to-peer sync on/off

## Features

### Real-Time Sync with Capella

The app syncs inventory, orders, and store profile data with your Capella cluster through App Services. Changes made in the app are immediately synced to the cloud and to other connected devices.

### Peer-to-Peer Sync

Devices on the same local network can sync directly with each other without going through the cloud. This is useful for:
- Demo scenarios with multiple devices
- Offline collaboration between nearby devices
- Reducing cloud bandwidth usage

To enable P2P sync, ensure `enableP2PSync` is set to `true` in `AppConfig.swift`.

### Offline-First Architecture

The app works fully offline using Couchbase Lite as the local database. All operations (create, read, update, delete) work without network connectivity. When connectivity is restored, changes automatically sync to the cloud.

## Troubleshooting

### Build Errors

**"Cannot find 'CouchbaseLiteSwift' in scope"**
- Wait for SPM to finish resolving packages (check progress in Xcode's top status bar)
- Try **File** > **Packages** > **Reset Package Caches**
- Clean build folder: **Product** > **Clean Build Folder** (⇧⌘K)

**"Could not resolve package dependencies"**
- Ensure you have an active internet connection
- Check that the package URLs in `Package.resolved` are accessible
- Try removing and re-adding the packages in **File** > **Packages**

### Sync Issues

**Sync not working**
- Verify your `CBL_BASE_URL` is correct and includes `wss://` protocol
- Check that environment variables are set correctly
- Verify your App Services endpoint is running in Capella
- Check Xcode console for sync-related error messages

**Authentication failures**
- Ensure the user credentials match those configured in Capella App Services
- Verify the database name (`CBL_AA_DB` or `CBL_NYC_DB`) matches your App Endpoint

### Runtime Issues

**App crashes on launch**
- Check Xcode console for crash logs
- Verify all required environment variables are set
- Ensure the selected iOS simulator/device meets the minimum iOS version (18.5)

**Data not appearing**
- Confirm your Capella cluster has data imported into the correct scope/collection
- Check that `scopeName` and collection names in `AppConfig.swift` match your Capella setup
- Look for database errors in the console output


## Additional Notes

### Enterprise vs Community Edition

This project uses Couchbase Lite Enterprise Edition, which includes additional features like encrypted sync and delta sync. If you need to use the Community Edition, update the package dependency in Xcode to point to the community repository.

### P2P Network Discovery

Peer-to-peer sync uses Bonjour/mDNS for device discovery on the local network. Make sure:
- Devices are on the same Wi-Fi network
- Local network permissions are granted to the app
- Firewall settings allow Bonjour traffic


## Related Documentation

- [Main Project README](../README.md) - Complete setup including Capella cluster configuration
- [Android App README](../Android/README.md) - Android version of this app
- [Web App README](../web/README.md) - Web version of this app
- [Couchbase Lite iOS Documentation](https://docs.couchbase.com/couchbase-lite/current/swift/quickstart.html)

