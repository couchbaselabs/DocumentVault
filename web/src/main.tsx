import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App.tsx";
import "./index.css";
import { initializeDatabase } from "./lib/database/initDatabase";
import { DatabaseProvider } from "./lib/database/DatabaseProvider";
import { startContinuousSync as setupContinuousSync } from "./lib/database/replicator";
import { getStoredCredentials } from "./lib/auth";
import type { VaultDatabase } from "./lib/database/types";
import { initializeLogging } from "./lib/logging";

/**
 * Start continuous sync for documents and annotations after successful login
 */
export async function startContinuousSync(db: VaultDatabase) {
  const credentials = getStoredCredentials();
  if (!credentials) {
    console.log('⚠️ No credentials found - cannot start sync');
    return null;
  }

  console.log('🔄 Starting continuous sync for DocumentVault...');
  console.log('🏢 Tenant ID:', credentials.tenantId);

  try {
    const replicator = setupContinuousSync(db, credentials.tenantId);
    console.log('✅ Continuous sync started successfully');

    // Store replicator instance globally
    (window as any).__replicator = replicator;

    return replicator;
  } catch (syncError) {
    console.error('⚠️ Continuous sync setup failed:', syncError);
    return null;
  }
}

async function bootstrap() {
  try {
    await initializeLogging();
    console.log('🚀 Bootstrapping DocumentVault Web application...');

    const credentials = getStoredCredentials();
    let db: VaultDatabase | null = null;

    try {
      if (credentials) {
        console.log('🔑 Found stored credentials for tenant:', credentials.tenantId);
        db = await initializeDatabase(credentials.tenantId);
        console.log('✅ Database initialized for', credentials.tenantId);

        console.log('🚀 Bootstrap: Starting continuous sync...');
        await startContinuousSync(db);
      } else {
        console.log('📝 No stored credentials - database will initialize after login');
      }
    } catch (initError) {
      console.error('❌ Bootstrap database/sync initialization failed:', initError);
    }

    const rootElement = document.getElementById("root");
    if (rootElement) {
      const root = createRoot(rootElement);
      root.render(
        <StrictMode>
          {db ? (
            <DatabaseProvider db={db}>
              <App />
            </DatabaseProvider>
          ) : (
            <App />
          )}
        </StrictMode>
      );
    }
  } catch (error) {
    console.error('❌ Critical bootstrap failure:', error);
  }
}

void bootstrap();
