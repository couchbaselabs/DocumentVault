# Couchbase Mobile & DocumentVault (FileVault) Demo Application

This repository contains a multi-platform application built with [Couchbase Lite](https://docs.couchbase.com/couchbase-lite/current/index.html) for web and mobile (iOS). It features **DocumentVault (FileVault)**, a secure, offline-first corporate document management and matter profiling system. It showcases Couchbase Lite's vector search, hybrid search, real-time sync with Capella App Services, and advanced RAG (Retrieval-Augmented Generation) agent integrations.

---

## 📖 Reference Guides & Value Details
To help run a live demonstration or understand the business value, review these interactive resources in the repository root:
*   👉 **[Interactive Demonstration Guide (documentvault_demonstration_guide.html)](file:///Users/austin.gonyou/Downloads/Apps/CBDemoChallengeApp/documentvault_demonstration_guide.html)** — A step-by-step interactive script for presenting offline capabilities, hybrid searches, and multi-platform RAG chat syncing.
*   👉 **[System Architecture & Value Detail Guide (documentvault_architecture.html)](file:///Users/austin.gonyou/Downloads/Apps/CBDemoChallengeApp/documentvault_architecture.html)** — A deep dive into the secure offline-first topology, vector index setups, and Couchbase Lite's technical business value.

---

## 📂 DocumentVault Features Overview

### 🧠 Semantic & Hybrid Search (iOS & Web)
* **Vector Configuration**: The iOS database vector index `vector_idx` has been optimized to use the `.cosine` (Cosine similarity) metric to align similarity search with the unit L2-normalized query and document vectors.
* **Scanned Image Vectorization**: Generates semantic text-based embeddings for image/camera documents based on their name, visual classification tags, and summary descriptors.
* **Hybrid Search Integration**: Merges Full-Text Search (FTS) and vector retrieval using Reciprocal Rank Fusion (RRF) and leverages session-level Rocchio relevance feedback to dynamically adjust user query vectors.

### 🌱 Seed Sample Dataset
* Includes a precompiled corporate legal dataset ([document_vault_sample_dataset.json](./datasets/document_vault_sample_dataset.json)) featuring folders and metadata-rich records (NDAs, PwC tax filings, Deloitte audits, HR handbooks, DB specs).
* Accessible from the developer settings, developers can trigger **"Seed Sample Corporate Data"** to automatically insert documents and folders and generate vector embeddings on-device on-the-fly.

### 🔄 Multi-Collection Real-Time Sync
* Synchronizes 6 tenant-scoped collections (`documents`, `folders`, `annotations`, `profile`, `senders`, `threads`) in parallel across the cloud (Couchbase Capella App Services) and client platforms.
* Features a domain-based tenant resolver: logging in with `austin@acmecorp.com` automatically maps the user to the `acmecorp` database scope on Capella.

---

## 🏗️ Cloud Backend Setup (Couchbase Capella)

### 1. Bucket, Scopes & Collections Setup
Create your Bucket on Couchbase Capella with the following hierarchy:
* **Bucket name**: `docvault`
* **Scope name**: `acmecorp`
* **Collections**:
  * `documents`
  * `folders`
  * `annotations`
  * `profile`
  * `senders`
  * `threads`

### 2. Capella App Services Configuration
* **App Endpoint name**: `docvault-acmecorp`
* **App User**: `austin@acmecorp.com` / `Password123!`
* **CORS Settings**:
  * **Allowed Origin**: `http://localhost:8081` (Vite Web App port)
  * **Login Origin**: `http://localhost:8081`
  * **Allowed Headers**: `Authorization, Content-Type`
  *(No trailing slashes in CORS URLs!)*

---

## 📂 Repository Structure

* **[iOS](./iOS/)**: Swift source code for the native iOS iPad application. Includes details on CoreML vector embeddings, native RAG tool calling, and reports tab badging.
* **[web](./web/)**: React + TypeScript + Vite web dashboard application. Features the local relevance RAG chat, LM Studio endpoint redirect config, and live sync activity console.
