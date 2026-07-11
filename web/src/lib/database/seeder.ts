import type { VaultDatabase } from "./types";

export async function seedWebSampleData(db: VaultDatabase, tenantId: string): Promise<{ folders: number; documents: number }> {
  const scopeName = tenantId || "_default";
  const foldersColName = `${scopeName}.folders` as any;
  const docsColName = `${scopeName}.documents` as any;

  console.log("🌱 Web Seeding: Starting local database population for scope:", scopeName);

  // 1. Folders
  const foldersData = [
    { id: "F_Legal_Contracts", name: "Legal Contracts", parentId: undefined },
    { id: "F_Financial_Records", name: "Financial Records & Audits", parentId: undefined },
    { id: "F_Case_Matters", name: "Case Matters", parentId: undefined },
    { id: "F_PwC_Audit_2026", name: "PwC Audit 2026", parentId: "F_Financial_Records" }
  ];

  let foldersCreated = 0;
  for (const f of foldersData) {
    const docId = f.id;
    const col = db.collections[foldersColName];
    if (!col) continue;
    
    const exists = await col.getDocument(docId);
    if (!exists) {
      const doc = col.createDocument(docId, {
        id: docId,
        docType: "Folder",
        name: f.name,
        parentId: f.parentId,
        ownerId: "system-seeder",
        tenantId: scopeName,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      });
      await col.save(doc);
      foldersCreated++;
    }
  }

  // 2. Documents
  const docsData = [
    {
      id: "D_PwC_Tax_Return",
      name: "PwC Corporate Tax Return 2026.pdf",
      fileExtension: "pdf",
      mimeType: "application/pdf",
      size: 154200,
      folderId: "F_PwC_Audit_2026",
      ownerId: "system-seeder",
      tenantId: scopeName,
      tags: ["tax", "audit", "pwc"],
      status: "published" as const,
      version: 1,
      textContent: "PwC Tax Return AN-01. Negligence observed in deferred tax liability assessments. The audit team noted an unexplained $15M variance in calculated deferred liabilities during Q1 review.",
      summary: "Baseline audit review of PwC corporate tax return 2026 (Matter AN-01). Focuses on negligence in deferred tax assessments.",
      contentCategory: "Financial Records",
      matter: "AN-01",
      client: "PwC",
      author: "Internal Audit Team",
      isDeleted: false
    },
    {
      id: "D_Legal_Brief_01",
      name: "Employment Agreement - Acme Corp.docx",
      fileExtension: "docx",
      mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      size: 45000,
      folderId: "F_Legal_Contracts",
      ownerId: "system-seeder",
      tenantId: scopeName,
      tags: ["employment", "acme", "hr"],
      status: "published" as const,
      version: 1,
      textContent: "Standard Executive Employment Agreement for Acme Corp. Governs terms of executive officers including intellectual property assignments and non-compete covenants.",
      summary: "Standard executive employment agreement template for Acme Corp.",
      contentCategory: "Legal Contracts",
      matter: "HR-99",
      client: "Acme Corp",
      author: "Legal Dept",
      isDeleted: false
    },
    {
      id: "D_Case_Brief_03",
      name: "PwC Negligence Case Brief.txt",
      fileExtension: "txt",
      mimeType: "text/plain",
      size: 12500,
      folderId: "F_Case_Matters",
      ownerId: "system-seeder",
      tenantId: scopeName,
      tags: ["litigation", "brief", "pwc"],
      status: "published" as const,
      version: 1,
      textContent: "Matter AN-01 Litigation brief regarding PwC tax negligence. Outlines the primary case theories and evidentiary documents supporting the liability claim.",
      summary: "Case brief detailing the legal strategy for the PwC tax negligence lawsuit (Matter AN-01).",
      contentCategory: "Case Matters",
      matter: "AN-01",
      client: "PwC",
      author: "External Counsel",
      isDeleted: false
    }
  ];

  let docsCreated = 0;
  for (const d of docsData) {
    const docId = d.id;
    const col = db.collections[docsColName];
    if (!col) continue;

    const exists = await col.getDocument(docId);
    if (!exists) {
      const doc = col.createDocument(docId, {
        ...d,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      });
      await col.save(doc);
      docsCreated++;
    }
  }

  console.log(`🌱 Web Seeding Complete: Seeded ${foldersCreated} folders and ${docsCreated} documents.`);
  return { folders: foldersCreated, documents: docsCreated };
}
