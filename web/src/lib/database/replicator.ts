import { Replicator, type ReplicatorConfig, type ReplicatorCollectionConfig, type ReplicatorStatus } from "@couchbase/lite-js";
import type { VaultDatabase } from "./types";
import { getAppServicesUrl, getStoredCredentials } from "../auth";

export interface ReplicatorOptions {
  continuous?: boolean;
  username?: string;
  password?: string;
  onStatusChange?: (status: ReplicatorStatus) => void;
  onError?: (error: Error) => void;
}

export function createReplicator(
  db: VaultDatabase,
  tenantId: string,
  options: ReplicatorOptions = {}
): Replicator {
  const { continuous = false, onStatusChange, onError } = options;

  const credentials = getStoredCredentials();
  const username = options.username || credentials?.email || "guest@local.com";
  let password = options.password || credentials?.password || "Password123!";

  if (password === "password" || password === "offline_password") {
    password = "Password123!";
  }

  const collectionConfig: ReplicatorCollectionConfig = {
    pull: { continuous },
    push: { continuous },
  };

  const syncUrl = getAppServicesUrl(tenantId);
  console.log('📡 Syncing to App Services URL:', syncUrl, 'as user:', username);

  const scopeName = tenantId || "_default";

  const config: any = {
    database: db,
    url: syncUrl,
    credentials: {
      username,
      password,
    },
    collections: {
      [`${scopeName}.documents`]: collectionConfig,
      [`${scopeName}.folders`]: collectionConfig,
      [`${scopeName}.annotations`]: collectionConfig,
    },
  };

  const replicator = new Replicator(config);

  if (onStatusChange) {
    replicator.onStatusChange = onStatusChange;
  }

  if (onError) {
    replicator.onStatusChange = (status: ReplicatorStatus) => {
      if (onStatusChange) onStatusChange(status);

      if (status.status === 'error' && status.error) {
        onError(status.error);
      }
    };
  }

  return replicator;
}

export async function syncOnce(
  db: VaultDatabase,
  tenantId: string,
  username?: string,
  password?: string
): Promise<void> {
  const replicator = createReplicator(db, tenantId, {
    continuous: false,
    username,
    password,
    onStatusChange: (status) => {
      console.log(`Sync status: ${status.status}`);
    },
    onError: (error) => {
      console.error('Sync error:', error);
    },
  });

  await replicator.run();
}

export function startContinuousSync(db: VaultDatabase, tenantId: string): Replicator {
  const replicator = createReplicator(db, tenantId, {
    continuous: true,
    onStatusChange: (status) => {
      console.log(`Continuous sync status: ${status.status}`);
    },
    onError: (error) => {
      console.error('Continuous sync error:', error);
    },
  });

  void replicator.run();

  return replicator;
}
