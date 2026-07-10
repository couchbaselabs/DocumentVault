import { type Database, type DatabaseConfig } from "@couchbase/lite-js";

export interface VaultDocument {
  id: string;
  docType: "Document";
  name: string;
  fileExtension: string;
  mimeType: string;
  size: number;
  folderId?: string;
  ownerId: string;
  tenantId: string;
  tags: string[];
  status: "published" | "draft" | "archived";
  version: number;
  textContent?: string;
  summary?: string;
  contentCategory?: string;
  matter?: string;
  client?: string;
  author?: string;
  profileDocType?: string;
  isDeleted: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface Folder {
  id: string;
  docType: "Folder";
  name: string;
  parentId?: string;
  ownerId: string;
  tenantId: string;
  createdAt: string;
  updatedAt: string;
}

export interface Annotation {
  id: string;
  docType: "Annotation";
  documentId: string;
  tenantId: string;
  authorId: string;
  authorEmail?: string;
  body: string;
  page?: number;
  resolved: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface DBSchema {
  documents: VaultDocument;
  folders: Folder;
  annotations: Annotation;
}

/**
 * Create database configuration for a specific tenant
 */
export function createVaultConfig(tenantId: string): DatabaseConfig<DBSchema> {
  const scopeName = tenantId || "_default";
  
  return {
    name: "documentvault-local",
    version: 7,
    collections: {
      [`${scopeName}.documents`]: {},
      [`${scopeName}.folders`]: {},
      [`${scopeName}.annotations`]: {},
    },
  };
}

export type VaultDatabase = Database<DBSchema>;
