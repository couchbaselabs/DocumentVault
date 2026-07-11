import { useNavigate } from "react-router-dom";
import { useState, useEffect } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { SyncStatus } from "@/components/SyncStatus";
import { FileText, FolderClosed, MessageSquare, LogOut, ChevronRight, Shield, Sparkles } from "lucide-react";
import { useDatabase } from "@/lib/database/DatabaseProvider";
import { getStoredCredentials, clearCredentials } from "@/lib/auth";
import { startContinuousSync } from "@/main";
import { convertCBLToPlain } from "@/lib/database/utils";
import type { VaultDocument, Folder, Annotation } from "@/lib/database/types";
import { seedWebSampleData } from "@/lib/database/seeder";
import { toast } from "sonner";

const Dashboard = () => {
  const navigate = useNavigate();
  const db = useDatabase();
  const [docCount, setDocCount] = useState(0);
  const [folderCount, setFolderCount] = useState(0);
  const [annotationCount, setAnnotationCount] = useState(0);
  const [recentDocs, setRecentDocs] = useState<VaultDocument[]>([]);
  const [recentAnnotations, setRecentAnnotations] = useState<Annotation[]>([]);
  const [loading, setLoading] = useState(true);
  const [seeding, setSeeding] = useState(false);

  const handleSeedData = async () => {
    setSeeding(true);
    try {
      const creds = getStoredCredentials();
      const tenant = creds?.tenantId || "local";
      const result = await seedWebSampleData(db, tenant);
      toast.success("Database Seeded!", {
        description: `Successfully inserted ${result.folders} folders and ${result.documents} documents locally.`
      });
      // Force refresh data
      window.location.reload();
    } catch (err: any) {
      console.error(err);
      toast.error("Failed to seed data", { description: err.message });
    } finally {
      setSeeding(false);
    }
  };

  const [syncError, setSyncError] = useState<string | null>(null);
  const [syncLogs, setSyncLogs] = useState<string[]>([]);

  useEffect(() => {
    const handleSyncError = (e: Event) => {
      const err = (e as CustomEvent).detail;
      setSyncError(err.message || String(err));
    };
    
    const handleSyncStatus = (e: Event) => {
      const status = (e as CustomEvent).detail;
      const act = (status.status || status.activity || "").toLowerCase();
      if (act !== 'error') {
        setSyncError(null);
      }
    };

    const handleSyncDocs = (e: Event) => {
      const detail = (e as CustomEvent).detail;
      const time = new Date().toLocaleTimeString();
      const count = detail.documents.length;
      const direction = detail.direction === 'push' ? '📤 Pushed' : '📥 Pulled';
      const colName = detail.collection.split('.').pop() || detail.collection;
      
      const newLog = `[${time}] ${direction} ${count} item(s) in "${colName}"`;
      setSyncLogs(prev => [newLog, ...prev.slice(0, 19)]);
    };

    window.addEventListener('cbl-sync-error', handleSyncError);
    window.addEventListener('cbl-sync-status', handleSyncStatus);
    window.addEventListener('cbl-sync-documents', handleSyncDocs);
    
    return () => {
      window.removeEventListener('cbl-sync-error', handleSyncError);
      window.removeEventListener('cbl-sync-status', handleSyncStatus);
      window.removeEventListener('cbl-sync-documents', handleSyncDocs);
    };
  }, []);

  useEffect(() => {
    const credentials = getStoredCredentials();
    if (!credentials) {
      navigate("/");
      return;
    }

    const scopeName = credentials.tenantId || "_default";
    const docsColName = `${scopeName}.documents` as any;
    const foldersColName = `${scopeName}.folders` as any;
    const annotationsColName = `${scopeName}.annotations` as any;

    const loadDashboardStats = async () => {
      try {
        setLoading(true);

        // Fetch counts
        const docC = await db.collections[docsColName]?.count() || 0;
        const foldC = await db.collections[foldersColName]?.count() || 0;
        const annC = await db.collections[annotationsColName]?.count() || 0;

        setDocCount(docC);
        setFolderCount(foldC);
        setAnnotationCount(annC);

        // Load recent documents
        if (docC > 0) {
          const docQuery = await db.createQuery(
            `SELECT META().id, * FROM \`${scopeName}\`.\`documents\` WHERE isDeleted = false ORDER BY updatedAt DESC LIMIT 5`
          );
          const docRows = await docQuery.execute();
          const docs: VaultDocument[] = [];
          for (const row of docRows) {
            const plain = convertCBLToPlain(row);
            if (plain.documents) {
              docs.push(plain.documents as VaultDocument);
            }
          }
          setRecentDocs(docs);
        }

        // Load recent annotations
        if (annC > 0) {
          const annQuery = await db.createQuery(
            `SELECT META().id, * FROM \`${scopeName}\`.\`annotations\` ORDER BY createdAt DESC LIMIT 5`
          );
          const annRows = await annQuery.execute();
          const anns: Annotation[] = [];
          for (const row of annRows) {
            const plain = convertCBLToPlain(row);
            if (plain.annotations) {
              anns.push(plain.annotations as Annotation);
            }
          }
          setRecentAnnotations(anns);
        }

      } catch (error) {
        console.error('❌ Error loading dashboard stats:', error);
      } finally {
        setLoading(false);
      }
    };

    const initSync = async () => {
      if (!(window as any).__replicator) {
        await startContinuousSync(db);
      }
    };

    void loadDashboardStats();
    void initSync();

    // Listen to changes in annotations and documents to refresh dashboard
    const docListener = db.collections[docsColName]?.addChangeListener(() => {
      loadDashboardStats();
    });
    const annListener = db.collections[annotationsColName]?.addChangeListener(() => {
      loadDashboardStats();
    });

    return () => {
      docListener?.remove();
      annListener?.remove();
    };
  }, [navigate, db]);

  const handleLogout = () => {
    clearCredentials();
    navigate("/");
  };

  const credentials = getStoredCredentials();

  return (
    <div className="min-h-screen bg-slate-50 text-slate-900">
      {/* Header */}
      <header className="border-b bg-white shadow-sm sticky top-0 z-10">
        <div className="container mx-auto px-6 py-4 flex justify-between items-center">
          <div className="flex items-center gap-3">
            <div className="p-2.5 rounded-xl bg-indigo-600/10">
              <Shield className="h-6 w-6 text-indigo-600" />
            </div>
            <div>
              <h1 className="text-xl font-bold">DocumentVault</h1>
              <p className="text-xs text-slate-500">
                Tenant: {credentials?.tenantId || 'local'} • User: {credentials?.email}
              </p>
            </div>
          </div>
          <div className="flex items-center gap-4">
            <SyncStatus />
            <Button variant="ghost" onClick={handleLogout} className="gap-2 text-slate-600 hover:text-slate-900">
              <LogOut className="h-4 w-4" />
              <span>Sign Out</span>
            </Button>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="container mx-auto px-6 py-8 space-y-8">
        {syncError && (
          <div className="bg-red-50 border border-red-200 p-5 rounded-2xl flex gap-4 shadow-sm items-start animate-in fade-in slide-in-from-top-4 duration-300">
            <div className="p-3 bg-red-100 rounded-xl text-red-600 font-bold text-lg leading-none">💥</div>
            <div className="space-y-1.5 flex-1">
              <h3 className="text-sm font-bold text-red-900">Sync Connection Failure</h3>
              <p className="text-xs text-red-700 font-mono bg-white border border-red-100 p-3 rounded-lg overflow-x-auto break-all max-h-36">
                {syncError}
              </p>
              <p className="text-xs text-slate-500">
                Please ensure CORS allowed origins on your Capella App Services dashboard includes <strong>{window.location.origin}</strong> and allowed headers contains <strong>Authorization</strong>.
              </p>
            </div>
          </div>
        )}

        {/* Stats Grid */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <Card className="bg-white border-slate-200 shadow-sm rounded-2xl overflow-hidden relative">
            <div className="absolute top-0 left-0 w-1.5 h-full bg-indigo-600"></div>
            <CardHeader className="flex flex-row items-center justify-between pb-2">
              <CardTitle className="text-sm font-semibold text-slate-500">Total Documents</CardTitle>
              <FileText className="h-5 w-5 text-indigo-600" />
            </CardHeader>
            <CardContent>
              <div className="text-3xl font-bold">{loading ? "..." : docCount}</div>
            </CardContent>
          </Card>

          <Card className="bg-white border-slate-200 shadow-sm rounded-2xl overflow-hidden relative">
            <div className="absolute top-0 left-0 w-1.5 h-full bg-emerald-600"></div>
            <CardHeader className="flex flex-row items-center justify-between pb-2">
              <CardTitle className="text-sm font-semibold text-slate-500">Case Folders</CardTitle>
              <FolderClosed className="h-5 w-5 text-emerald-600" />
            </CardHeader>
            <CardContent>
              <div className="text-3xl font-bold">{loading ? "..." : folderCount}</div>
            </CardContent>
          </Card>

          <Card className="bg-white border-slate-200 shadow-sm rounded-2xl overflow-hidden relative">
            <div className="absolute top-0 left-0 w-1.5 h-full bg-amber-600"></div>
            <CardHeader className="flex flex-row items-center justify-between pb-2">
              <CardTitle className="text-sm font-semibold text-slate-500">Matter Annotations & updates</CardTitle>
              <MessageSquare className="h-5 w-5 text-amber-600" />
            </CardHeader>
            <CardContent>
              <div className="text-3xl font-bold">{loading ? "..." : annotationCount}</div>
            </CardContent>
          </Card>
        </div>

        {/* Action Button to Explorer */}
        <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center bg-indigo-600 text-white rounded-2xl p-6 shadow-md shadow-indigo-600/10 gap-4">
          <div className="space-y-1">
            <h2 className="text-lg font-bold">Secure Document Explorer</h2>
            <p className="text-indigo-100 text-sm">View files, read summaries, and add case matter annotations directly.</p>
          </div>
          <div className="flex flex-wrap gap-3 w-full sm:w-auto">
            <Button 
              onClick={handleSeedData} 
              disabled={seeding}
              className="bg-indigo-700 hover:bg-indigo-800 text-white border border-indigo-500 font-semibold gap-2 rounded-xl h-11 px-5 w-full sm:w-auto"
            >
              {seeding ? "Seeding..." : "Seed Local Data"}
            </Button>
            <Button 
              onClick={() => navigate("/chat")} 
              className="bg-indigo-500 hover:bg-indigo-600 text-white border border-indigo-400 font-semibold gap-2 rounded-xl h-11 px-5 w-full sm:w-auto"
            >
              <Sparkles className="h-4 w-4" />
              <span>Agent RAG Chat</span>
            </Button>
            <Button 
              onClick={() => navigate("/inventory")} 
              className="bg-white hover:bg-slate-50 text-indigo-600 font-semibold gap-2 rounded-xl h-11 px-5 w-full sm:w-auto"
            >
              <span>Explore Documents</span>
              <ChevronRight className="h-4 w-4" />
            </Button>
          </div>
        </div>

        {/* Recent items grid */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
          {/* Recent Documents */}
          <Card className="bg-white border-slate-200 shadow-sm rounded-2xl">
            <CardHeader className="border-b pb-4">
              <CardTitle className="text-base font-bold text-slate-800">Recently Modified Documents</CardTitle>
            </CardHeader>
            <CardContent className="pt-4">
              {recentDocs.length === 0 ? (
                <div className="text-center py-6 text-slate-400 text-sm">No documents found. Syncing...</div>
              ) : (
                <div className="divide-y divide-slate-100">
                  {recentDocs.map((doc) => {
                    const isRecentlyUpdated = (() => {
                      try {
                        const diff = Date.now() - new Date(doc.updatedAt).getTime();
                        return diff < 5 * 60 * 1000; // 5 minutes
                      } catch {
                        return false;
                      }
                    })();

                    return (
                      <div key={doc.id} className="py-3 flex justify-between items-center first:pt-0 last:pb-0">
                        <div className="space-y-1">
                          <div className="flex items-center gap-2 font-semibold text-sm text-slate-800">
                            <span>{doc.name}</span>
                            {isRecentlyUpdated && (
                              <span className="inline-flex items-center px-1.5 py-0.5 rounded-md text-[9px] font-bold bg-emerald-100 text-emerald-800 animate-pulse border border-emerald-200">
                                ● Synced Just Now
                              </span>
                            )}
                          </div>
                          <div className="text-xs text-slate-500">
                            Matter: {doc.matter || "None"} • Client: {doc.client || "None"}
                          </div>
                        </div>
                        <span className="text-xs px-2.5 py-1 bg-slate-100 border text-slate-600 font-semibold rounded-full uppercase tracking-wider">
                          {doc.status}
                        </span>
                      </div>
                    );
                  })}
                </div>
              )}
            </CardContent>
          </Card>

          {/* Recent Annotations */}
          <Card className="bg-white border-slate-200 shadow-sm rounded-2xl">
            <CardHeader className="border-b pb-4">
              <CardTitle className="text-base font-bold text-slate-800">Recent Case annotations & Updates</CardTitle>
            </CardHeader>
            <CardContent className="pt-4">
              {recentAnnotations.length === 0 ? (
                <div className="text-center py-6 text-slate-400 text-sm">No recent annotations found.</div>
              ) : (
                <div className="divide-y divide-slate-100">
                  {recentAnnotations.map((ann) => (
                    <div key={ann.id} className="py-3 first:pt-0 last:pb-0 space-y-1">
                      <div className="flex justify-between text-xs font-semibold text-slate-500">
                        <span>From: {ann.authorEmail || ann.authorId}</span>
                        <span>{new Date(ann.createdAt).toLocaleDateString()}</span>
                      </div>
                      <p className="text-sm text-slate-700 font-medium italic">
                        "{ann.body}"
                      </p>
                    </div>
                  ))}
                </div>
              )}
            </CardContent>
          </Card>

          {/* Live Sync Activity Log */}
          <Card className="bg-white border-slate-200 shadow-sm rounded-2xl">
            <CardHeader className="border-b pb-4">
              <CardTitle className="text-base font-bold text-slate-800">Live Sync Activity Log</CardTitle>
            </CardHeader>
            <CardContent className="pt-4">
              {syncLogs.length === 0 ? (
                <div className="text-center py-12 text-slate-400 text-sm space-y-2">
                  <div>Waiting for sync activity...</div>
                  <p className="text-[10px] text-slate-400 leading-normal max-w-xs mx-auto">
                    Replicate from iPad or submit an annotation/update to watch the CBL sync protocol stream in real-time.
                  </p>
                </div>
              ) : (
                <div className="space-y-2 max-h-64 overflow-y-auto font-mono text-xs pr-1">
                  {syncLogs.map((log, idx) => (
                    <div key={idx} className="p-2 bg-slate-50 border border-slate-100 rounded-xl text-slate-600 flex items-center justify-between gap-2">
                      <span className="truncate">{log}</span>
                      <span className="inline-flex h-1.5 w-1.5 rounded-full bg-indigo-600 animate-ping flex-shrink-0" />
                    </div>
                  ))}
                </div>
              )}
            </CardContent>
          </Card>
        </div>
      </main>
    </div>
  );
};

export default Dashboard;