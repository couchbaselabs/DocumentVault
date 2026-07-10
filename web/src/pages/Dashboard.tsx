import { useNavigate } from "react-router-dom";
import { useState, useEffect } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { SyncStatus } from "@/components/SyncStatus";
import { FileText, FolderClosed, MessageSquare, LogOut, ChevronRight } from "lucide-react";
import { useDatabase } from "@/lib/database/DatabaseProvider";
import { getStoredCredentials, clearCredentials } from "@/lib/auth";
import { startContinuousSync } from "@/main";
import { convertCBLToPlain } from "@/lib/database/utils";
import type { VaultDocument, Folder, Annotation } from "@/lib/database/types";

const Dashboard = () => {
  const navigate = useNavigate();
  const db = useDatabase();
  const [docCount, setDocCount] = useState(0);
  const [folderCount, setFolderCount] = useState(0);
  const [annotationCount, setAnnotationCount] = useState(0);
  const [recentDocs, setRecentDocs] = useState<VaultDocument[]>([]);
  const [recentAnnotations, setRecentAnnotations] = useState<Annotation[]>([]);
  const [loading, setLoading] = useState(true);

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
      docListener?.then(tok => tok.remove());
      annListener?.then(tok => tok.remove());
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
        <div className="flex justify-between items-center bg-indigo-600 text-white rounded-2xl p-6 shadow-md shadow-indigo-600/10">
          <div className="space-y-1">
            <h2 className="text-lg font-bold">Secure Document Explorer</h2>
            <p className="text-indigo-100 text-sm">View files, read summaries, and add case matter annotations directly.</p>
          </div>
          <Button onClick={() => navigate("/inventory")} className="bg-white hover:bg-slate-50 text-indigo-600 font-semibold gap-2 rounded-xl h-11 px-5">
            <span>Explore Documents</span>
            <ChevronRight className="h-4 w-4" />
          </Button>
        </div>

        {/* Recent items grid */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
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
                  {recentDocs.map((doc) => (
                    <div key={doc.id} className="py-3 flex justify-between items-center first:pt-0 last:pb-0">
                      <div className="space-y-1">
                        <div className="font-semibold text-sm text-slate-800">{doc.name}</div>
                        <div className="text-xs text-slate-500">
                          Matter: {doc.matter || "None"} • Client: {doc.client || "None"}
                        </div>
                      </div>
                      <span className="text-xs px-2.5 py-1 bg-slate-100 border text-slate-600 font-semibold rounded-full uppercase tracking-wider">
                        {doc.status}
                      </span>
                    </div>
                  ))}
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
        </div>
      </main>
    </div>
  );
};

import { Shield } from "lucide-react";

export default Dashboard;