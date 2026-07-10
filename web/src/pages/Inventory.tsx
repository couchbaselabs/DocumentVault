import { useNavigate } from "react-router-dom";
import { useState, useEffect } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription } from "@/components/ui/sheet";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { SyncStatus } from "@/components/SyncStatus";
import { FileText, ArrowLeft, Plus, Search, Loader2, Send } from "lucide-react";
import { useDatabase } from "@/lib/database/DatabaseProvider";
import { getStoredCredentials } from "@/lib/auth";
import { convertCBLToPlain } from "@/lib/database/utils";
import { MutableDocument } from "@couchbase/lite-js";
import type { VaultDocument, Annotation } from "@/lib/database/types";
import { toast } from "sonner";

const Inventory = () => {
  const navigate = useNavigate();
  const db = useDatabase();
  
  const [documents, setDocuments] = useState<VaultDocument[]>([]);
  const [search, setSearch] = useState("");
  const [loading, setLoading] = useState(true);
  
  const [selectedDoc, setSelectedDoc] = useState<VaultDocument | null>(null);
  const [annotations, setAnnotations] = useState<Annotation[]>([]);
  const [newAnnotationText, setNewAnnotationText] = useState("");
  const [submittingAnn, setSubmittingAnn] = useState(false);

  const credentials = getStoredCredentials();
  const scopeName = credentials?.tenantId || "_default";
  const docsColName = `${scopeName}.documents` as any;
  const annotationsColName = `${scopeName}.annotations` as any;

  const loadDocuments = async () => {
    try {
      setLoading(true);
      const count = await db.collections[docsColName]?.count() || 0;
      if (count === 0) {
        setDocuments([]);
        return;
      }

      const query = await db.createQuery(
        `SELECT META().id, * FROM \`${scopeName}\`.\`documents\` WHERE isDeleted = false ORDER BY name ASC`
      );
      const rows = await query.execute();
      const docs: VaultDocument[] = [];
      for (const row of rows) {
        const plain = convertCBLToPlain(row);
        if (plain.documents) {
          docs.push(plain.documents as VaultDocument);
        }
      }
      setDocuments(docs);
    } catch (err) {
      console.error("Error loading documents:", err);
    } finally {
      setLoading(false);
    }
  };

  const loadAnnotationsForSelectedDoc = async (docId: string) => {
    try {
      const count = await db.collections[annotationsColName]?.count() || 0;
      if (count === 0) {
        setAnnotations([]);
        return;
      }

      const query = await db.createQuery(
        `SELECT META().id, * FROM \`${scopeName}\`.\`annotations\` WHERE documentId = '${docId}' ORDER BY createdAt ASC`
      );
      const rows = await query.execute();
      const anns: Annotation[] = [];
      for (const row of rows) {
        const plain = convertCBLToPlain(row);
        if (plain.annotations) {
          anns.push(plain.annotations as Annotation);
        }
      }
      setAnnotations(anns);
    } catch (err) {
      console.error("Error loading annotations:", err);
    }
  };

  useEffect(() => {
    if (!credentials) {
      navigate("/");
      return;
    }

    void loadDocuments();

    // Setup collection listeners for real-time table sync
    const docListener = db.collections[docsColName]?.addChangeListener(() => {
      loadDocuments();
    });

    return () => {
      docListener?.then(tok => tok.remove());
    };
  }, [navigate, db]);

  // Keep annotations updated in real-time when drawer is open
  useEffect(() => {
    if (!selectedDoc) return;
    
    void loadAnnotationsForSelectedDoc(selectedDoc.id);

    const annListener = db.collections[annotationsColName]?.addChangeListener(() => {
      loadAnnotationsForSelectedDoc(selectedDoc.id);
    });

    return () => {
      annListener?.then(tok => tok.remove());
    };
  }, [selectedDoc]);

  const handleAddAnnotation = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedDoc || !newAnnotationText.trim()) return;

    setSubmittingAnn(true);
    try {
      const annId = `Ann_Web_${Math.random().toString(36).substring(2, 11)}`;
      
      const newAnn = {
        id: annId,
        docType: "Annotation" as const,
        documentId: selectedDoc.id,
        tenantId: scopeName,
        authorId: credentials?.email || "web-user",
        authorEmail: credentials?.email || "web-user",
        body: newAnnotationText.trim(),
        resolved: false,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      };

      const mutableDoc = new MutableDocument(annId, newAnn);
      
      // Save directly to the annotations collection in Couchbase Lite JS
      await db.collections[annotationsColName].save(mutableDoc);

      setNewAnnotationText("");
      toast.success("Case update annotation added!", {
        description: "Replicating to Capella and syncing to iPad in background."
      });
    } catch (err) {
      console.error("Failed to save annotation:", err);
      toast.error("Failed to add annotation");
    } finally {
      setSubmittingAnn(false);
    }
  };

  const filteredDocs = documents.filter((doc) => {
    const term = search.toLowerCase();
    return (
      doc.name.toLowerCase().includes(term) ||
      (doc.matter?.toLowerCase() || "").includes(term) ||
      (doc.client?.toLowerCase() || "").includes(term) ||
      (doc.textContent?.toLowerCase() || "").includes(term)
    );
  });

  return (
    <div className="min-h-screen bg-slate-50 text-slate-900">
      {/* Header */}
      <header className="border-b bg-white shadow-sm sticky top-0 z-10">
        <div className="container mx-auto px-6 py-4 flex justify-between items-center">
          <div className="flex items-center gap-4">
            <Button variant="ghost" onClick={() => navigate("/dashboard")} className="p-2 text-slate-600 hover:text-slate-900">
              <ArrowLeft className="h-5 w-5" />
            </Button>
            <div>
              <h1 className="text-xl font-bold">Document Explorer</h1>
              <p className="text-xs text-slate-500">Matter files & secure case search</p>
            </div>
          </div>
          <div className="flex items-center gap-4">
            <SyncStatus />
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="container mx-auto px-6 py-8 space-y-6">
        {/* Search Bar */}
        <div className="flex gap-4">
          <div className="relative flex-grow">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
            <Input
              type="text"
              placeholder="Search documents by filename, content, matter, or client..."
              className="pl-10 h-11 bg-white border-slate-200 rounded-xl"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </div>
        </div>

        {/* Table Card */}
        <div className="bg-white border border-slate-200 rounded-2xl shadow-sm overflow-hidden">
          {loading ? (
            <div className="py-20 flex flex-col items-center justify-center text-slate-400 gap-2">
              <Loader2 className="h-8 w-8 animate-spin text-indigo-600" />
              <span>Loading documents...</span>
            </div>
          ) : filteredDocs.length === 0 ? (
            <div className="py-20 text-center text-slate-400">
              No matter documents found. Please seed corporate data in the iPad app first.
            </div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow className="hover:bg-transparent">
                  <TableHead className="font-semibold text-slate-700">Filename</TableHead>
                  <TableHead className="font-semibold text-slate-700">Format</TableHead>
                  <TableHead className="font-semibold text-slate-700">Case Matter</TableHead>
                  <TableHead className="font-semibold text-slate-700">Client</TableHead>
                  <TableHead className="font-semibold text-slate-700 text-center">Status</TableHead>
                  <TableHead className="font-semibold text-slate-700 text-right">Modified</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filteredDocs.map((doc) => (
                  <TableRow
                    key={doc.id}
                    className="cursor-pointer hover:bg-slate-50 transition-colors"
                    onClick={() => setSelectedDoc(doc)}
                  >
                    <TableCell className="font-semibold text-slate-900">
                      <div className="flex items-center gap-2">
                        <FileText className="h-4 w-4 text-indigo-600 flex-shrink-0" />
                        <span>{doc.name}</span>
                      </div>
                    </TableCell>
                    <TableCell className="uppercase text-xs font-bold text-slate-500">
                      {doc.fileExtension}
                    </TableCell>
                    <TableCell className="text-slate-600">{doc.matter || "—"}</TableCell>
                    <TableCell className="text-slate-600">{doc.client || "—"}</TableCell>
                    <TableCell className="text-center">
                      <span className="text-xs px-2.5 py-1 bg-slate-100 border text-slate-600 font-semibold rounded-full uppercase tracking-wider">
                        {doc.status}
                      </span>
                    </TableCell>
                    <TableCell className="text-right text-xs font-medium text-slate-500">
                      {new Date(doc.updatedAt).toLocaleDateString()}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </div>
      </main>

      {/* Document Detail Drawer */}
      <Sheet open={selectedDoc !== null} onOpenChange={(open) => { if (!open) setSelectedDoc(null); }}>
        {selectedDoc && (
          <SheetContent className="bg-white border-l w-full sm:max-w-xl overflow-y-auto p-6 space-y-6">
            <SheetHeader className="border-b pb-4">
              <div className="flex items-center gap-2 text-indigo-600 font-bold text-xs uppercase tracking-wide">
                <FileText className="h-4 w-4" />
                <span>Document Details</span>
              </div>
              <SheetTitle className="text-xl font-bold text-slate-900 pt-1">{selectedDoc.name}</SheetTitle>
              <SheetDescription className="text-slate-500">
                Matter: {selectedDoc.matter} • Client: {selectedDoc.client}
              </SheetDescription>
            </SheetHeader>

            {/* AI Summary Section */}
            <div className="space-y-2">
              <h3 className="text-sm font-semibold text-slate-700">AI Summary</h3>
              <p className="text-sm text-slate-600 bg-slate-50 border p-4 rounded-xl leading-relaxed">
                {selectedDoc.summary || "No AI summary generated for this document yet."}
              </p>
            </div>

            {/* Annotations Section */}
            <div className="space-y-4 pt-4 border-t">
              <h3 className="text-sm font-semibold text-slate-700">Case matter annotations & Updates</h3>
              
              {annotations.length === 0 ? (
                <div className="text-center py-4 bg-slate-50 border border-dashed rounded-xl text-slate-400 text-xs">
                  No annotations added yet. Submit an update below to test real-time RAG sync!
                </div>
              ) : (
                <div className="space-y-3 max-h-60 overflow-y-auto pr-1">
                  {annotations.map((ann) => (
                    <div key={ann.id} className="p-3 bg-slate-50 border rounded-xl space-y-1">
                      <div className="flex justify-between text-xs font-semibold text-slate-400">
                        <span>{ann.authorEmail}</span>
                        <span>{new Date(ann.createdAt).toLocaleDateString()}</span>
                      </div>
                      <p className="text-sm text-slate-800 leading-relaxed italic">
                        "{ann.body}"
                      </p>
                    </div>
                  ))}
                </div>
              )}

              {/* Add Annotation Form */}
              <form onSubmit={handleAddAnnotation} className="flex gap-2">
                <Input
                  type="text"
                  placeholder="Simulate case email update or legal annotation..."
                  className="bg-white border-slate-200 rounded-xl"
                  value={newAnnotationText}
                  onChange={(e) => setNewAnnotationText(e.target.value)}
                  disabled={submittingAnn}
                />
                <Button
                  type="submit"
                  className="bg-indigo-600 hover:bg-indigo-700 text-white rounded-xl"
                  disabled={submittingAnn || !newAnnotationText.trim()}
                >
                  {submittingAnn ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
                </Button>
              </form>
            </div>
          </SheetContent>
        )}
      </Sheet>
    </div>
  );
};

export default Inventory;