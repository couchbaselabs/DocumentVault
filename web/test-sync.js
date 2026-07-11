import { Database, Replicator } from "@couchbase/lite-js";

async function runTest() {
  console.log("🚀 Testing Couchbase Lite connection for austin@acmecorp.com...");
  const tenantId = "acmecorp";
  
  const config = {
    name: "test-vault-db",
    directory: "./test-db-dir",
    version: 7,
    collections: {
      [`${tenantId}.documents`]: {},
      [`${tenantId}.folders`]: {},
      [`${tenantId}.annotations`]: {},
    }
  };

  try {
    console.log("💾 Opening Couchbase Lite database...");
    const db = await Database.open(config);
    console.log("✅ Database opened successfully");

    const syncUrl = "wss://gal7pf8dclbqfk.apps.cloud.couchbase.com:4984/docvault-acmecorp";
    console.log("📡 Connecting to Sync Endpoint:", syncUrl);

    const collectionConfig = {
      pull: { continuous: false },
      push: { continuous: false }
    };

    const repConfig = {
      database: db,
      url: syncUrl,
      credentials: {
        username: "austin@acmecorp.com",
        password: "Password123!"
      },
      collections: {
        [`${tenantId}.documents`]: collectionConfig,
        [`${tenantId}.folders`]: collectionConfig,
        [`${tenantId}.annotations`]: collectionConfig
      }
    };

    console.log("🔧 Initializing Replicator...");
    const replicator = new Replicator(repConfig);

    replicator.onStatusChange = (status) => {
      console.log(`🔄 Replicator status: ${status.status || status.activity}`);
      if (status.error) {
        console.error("❌ Replicator error:", status.error);
      }
    };

    replicator.onDocuments = (collection, direction, documents) => {
      console.log(`⬇️ Received ${documents.length} documents in ${collection.name}`);
    };

    console.log("🚀 Running Replicator...");
    await replicator.run();
    console.log("✅ Replication run completed!");

    const docCount = await db.collections[`${tenantId}.documents`].count();
    console.log(`📊 Final documents count: ${docCount}`);

    await db.close();
  } catch (err) {
    console.error("💥 Test failed with error:", err);
  }
}

runTest();
