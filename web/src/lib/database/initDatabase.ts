import { Database } from "@couchbase/lite-js";
import { createVaultConfig } from "./types";

export async function initializeDatabase(tenantId: string) {
  try {
    console.log('Opening Couchbase Lite database for tenant:', tenantId);
    
    const config = createVaultConfig(tenantId);
    const db = await Database.open(config);
    
    console.log('✅ Database opened successfully');

    const scopeName = tenantId || "_default";
    const documentsColName = `${scopeName}.documents` as any;
    const foldersColName = `${scopeName}.folders` as any;
    const annotationsColName = `${scopeName}.annotations` as any;

    // Check current collection counts safely
    const docCount = await db.collections[documentsColName]?.count() || 0;
    const folderCount = await db.collections[foldersColName]?.count() || 0;
    const annotationCount = await db.collections[annotationsColName]?.count() || 0;
    
    console.log(`Current documents count: ${docCount}`);
    console.log(`Current folders count: ${folderCount}`);
    console.log(`Current annotations count: ${annotationCount}`);

    return db;
  } catch (error) {
    console.error('Error initializing database:', error);
    throw error;
  }
}