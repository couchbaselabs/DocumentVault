import Foundation
import UIKit
import CouchbaseLiteSwift

@MainActor
private func generateSeededFileData(forText text: String, fileExtension ext: String) -> Data {
    let lowerExt = ext.lowercased()
    if lowerExt == "pdf" {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        return renderer.pdfData { context in
            context.beginPage()
            let font = UIFont.systemFont(ofSize: 13)
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 4
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .paragraphStyle: style
            ]
            let attributedString = NSAttributedString(string: text, attributes: attrs)
            attributedString.draw(in: CGRect(x: 54, y: 54, width: 504, height: 684))
        }
    } else if lowerExt == "png" || lowerExt == "jpg" || lowerExt == "jpeg" {
        let size = CGSize(width: 200, height: 200)
        UIGraphicsBeginImageContext(size)
        defer { UIGraphicsEndImageContext() }
        if let context = UIGraphicsGetCurrentContext() {
            context.setFillColor(UIColor.systemIndigo.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
            
            // Draw some mock text on the image
            let font = UIFont.boldSystemFont(ofSize: 14)
            let textRect = CGRect(x: 10, y: 80, width: 180, height: 40)
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white,
                .paragraphStyle: style
            ]
            let attrStr = NSAttributedString(string: "MOCK IMAGE SCALE", attributes: attrs)
            attrStr.draw(in: textRect)
            
            if let image = UIGraphicsGetImageFromCurrentImageContext(),
               let pngData = image.pngData() {
                return pngData
            }
        }
        return Data()
    } else {
        return text.data(using: .utf8) ?? Data()
    }
}

extension DatabaseManager {
    
    @MainActor
    func seedSampleData() async throws -> (folders: Int, documents: Int) {
        let tenant = AppConfig.currentTenantId.isEmpty ? "acme-corp" : AppConfig.currentTenantId
        let currentUserEmail = AppConfig.username.isEmpty ? "admin@acme-corp.com" : AppConfig.username
        
        print("🌱 Seeding sample dataset for tenant: \(tenant), user: \(currentUserEmail)")
        
        // 1. Folders
        let sampleFolders = [
            Folder(id: "Folder_Legal_Contracts", name: "Legal & Contracts", ownerId: "legal-admin@acme-corp.com", tenantId: tenant, color: "#4F46E5", icon: "briefcase"),
            Folder(id: "Folder_Financial_Audits", name: "Financial Records & Audits", ownerId: "finance-lead@acme-corp.com", tenantId: tenant, color: "#059669", icon: "dollarsign"),
            Folder(id: "Folder_HR_Operations", name: "HR & Operations", ownerId: "hr-manager@acme-corp.com", tenantId: tenant, color: "#D97706", icon: "person.2"),
            Folder(id: "Folder_Technical_Specs", name: "Technical Specifications", ownerId: "tech-architect@acme-corp.com", tenantId: tenant, color: "#2563EB", icon: "cpu")
        ]
        
        var seededFoldersCount = 0
        for folder in sampleFolders {
            // Check if folder already exists
            if (try? collection(named: AppConfig.foldersCollection).document(id: folder.id)) == nil {
                try saveFolder(folder)
                seededFoldersCount += 1
            }
        }
        
        // 2. Documents
        var doc1 = VaultDocument(
            id: "Doc_Globex_NDA",
            name: "Globex_NDA_Executed.pdf",
            fileExtension: "pdf",
            mimeType: "application/pdf",
            size: 124500,
            folderId: "Folder_Legal_Contracts",
            ownerId: "legal-admin@acme-corp.com",
            tenantId: tenant,
            tags: ["legal", "contract", "nda", "globex", "executed", "confidential"],
            status: .published,
            version: 1,
            source: DocumentSource(type: .filePicker, capturedBy: "legal-admin@acme-corp.com", capturedAt: Date()),
            processingStatus: .complete,
            ocrProcessed: true,
            custodyId: "Cust_Globex_NDA",
            client: "Globex Corp (2000)",
            matter: "NDA (N01)",
            author: "John Doe",
            profileDocType: "Agreement / NDA"
        )
        doc1.textContent = "MUTUAL NON-DISCLOSURE AGREEMENT\nThis Mutual Non-Disclosure Agreement (the 'Agreement') is entered into by and between Acme Corporation, a Delaware corporation ('Acme'), and Globex Corporation, a California corporation ('Globex').\n1. Purpose: The parties wish to explore a potential business relationship under which each party may disclose proprietary and confidential information.\n2. Confidential Information: Includes all technical, business, financial, or other information marked as confidential or that should reasonably be understood to be confidential.\n3. Non-Use and Non-Disclosure: Each party agrees to use the other's confidential information solely for the purpose of evaluating the relationship and to maintain its confidentiality using reasonable care.\n4. Term: The obligations of confidentiality shall survive for 3 years from the date of disclosure.\n5. Governing Law: State of New York.\nExecuted by John Doe (Acme President) and Jane Smith (Globex VP Operations) on May 12, 2026."
        doc1.summary = "Executed Mutual Non-Disclosure Agreement (NDA) between Acme Corp and Globex Corp signed on May 12, 2026. Governing law is New York. Three-year term for confidentiality."
        doc1.contentCategory = "legal"
        doc1.hasBlob = true
        doc1.custodyChain = [
            CustodyEvent(actor: "legal-admin@acme-corp.com", action: .uploaded, deviceId: "MacBook_Legal_01", notes: "Original PDF ingested via desktop client.")
        ]
        
        var doc2 = VaultDocument(
            id: "Doc_Acme_Board_Min_Q1_2026",
            name: "Q1_2026_Board_Minutes.pdf",
            fileExtension: "pdf",
            mimeType: "application/pdf",
            size: 84200,
            folderId: "Folder_Legal_Contracts",
            ownerId: "legal-admin@acme-corp.com",
            tenantId: tenant,
            tags: ["board", "minutes", "q1", "governance", "meeting"],
            status: .published,
            version: 1,
            source: DocumentSource(type: .filePicker, capturedBy: "legal-admin@acme-corp.com", capturedAt: Date()),
            processingStatus: .complete,
            ocrProcessed: true,
            custodyId: "Cust_Q1_Board_Min",
            client: "Acme Corp (1000)",
            matter: "Board Resolutions (B03)",
            author: "Sarah Jenkins",
            profileDocType: "Board Minute"
        )
        doc2.textContent = "ACME CORPORATION\nMINUTES OF THE Q1 BOARD OF DIRECTORS MEETING\nDate: March 15, 2026\nTime: 10:00 AM EST\nAttendees:\n- John Doe (Chairman of the Board)\n- Sarah Jenkins (CEO)\n- Robert Vance (Independent Director)\n- Emily Watson (Independent Director)\n- Harold Finch (CFO)\n\nProceedings:\n1. Call to Order: Chairman John Doe called the meeting to order. A quorum was declared present.\n2. CEO Report: Sarah Jenkins presented the Q1 performance metrics. Global sales grew by 14% year-over-year, primarily driven by enterprise software subscriptions.\n3. Financial Overview: CFO Harold Finch reviewed Q1 cash flows and balance sheet. Gross margins remained stable at 72.4%. Capital expenditures of $4.2M were approved for server capacity expansion.\n4. New Business: The Board discussed potential strategic acquisition options. Robert Vance proposed forming a special committee to evaluate SaaS acquisitions.\n5. Adjournment: The meeting was adjourned at 12:45 PM EST."
        doc2.summary = "Official minutes of Acme Corp's Q1 Board of Directors meeting held on March 15, 2026. Highlights CEO's report of 14% YoY sales growth and CFO's CAPEX approval of $4.2M for server capacity expansion."
        doc2.contentCategory = "legal"
        doc2.hasBlob = true
        doc2.custodyChain = [
            CustodyEvent(actor: "legal-admin@acme-corp.com", action: .uploaded, deviceId: "MacBook_Legal_01", notes: "Ingested draft version for board review."),
            CustodyEvent(actor: "legal-admin@acme-corp.com", action: .contentReplaced, notes: "Approved final version published. Status set to published.")
        ]
        
        var doc3 = VaultDocument(
            id: "Doc_Q2_Audit_Report_2026",
            name: "Q2_2026_Audit_Report.pdf",
            fileExtension: "pdf",
            mimeType: "application/pdf",
            size: 256800,
            folderId: "Folder_Financial_Audits",
            ownerId: "finance-lead@acme-corp.com",
            tenantId: tenant,
            tags: ["finance", "audit", "compliance", "q2", "balance-sheet"],
            status: .published,
            version: 1,
            source: DocumentSource(type: .filePicker, capturedBy: "finance-lead@acme-corp.com", capturedAt: Date()),
            processingStatus: .complete,
            ocrProcessed: true,
            custodyId: "Cust_Q2_Audit",
            client: "Deloitte & Touche (3000)",
            matter: "Audit (A01)",
            author: "Harold Finch",
            profileDocType: "Audit Report"
        )
        doc3.textContent = "ACME CORP - INTERNAL FINANCIAL AUDIT REPORT\nQuarter Ending June 30, 2026\nPrepared by: Deloitte & Touche LLP\nExecutive Summary:\nWe have conducted an internal audit of the financial accounts, ledger reconciliations, and transactions of Acme Corp for Q2 2026. Our examination was designed to evaluate internal controls and verify the accuracy of the financial reports.\nAudit Findings:\n- Revenue Reconciliation: Reconciled revenue of $24,850,230 matches invoices and cash deposits with zero material discrepancies.\n- Expense Discrepancies: Discovered minor payroll alignment errors ($1,250) in the European subsidiary which have since been corrected.\n- Internal Controls: General controls over accounts receivable and payable are highly effective. Recommend upgrading the purchase order authorization threshold from $5,000 to $10,000 to improve operational throughput.\nConclusion: Acme Corp's financial statements present fairly, in all material respects, the financial position of the company as of June 30, 2026."
        doc3.summary = "Internal financial audit report of Acme Corp for Q2 2026, prepared by Deloitte. Confirms accurate revenue reconciliation of $24.85M and highly effective internal controls."
        doc3.contentCategory = "financial"
        doc3.hasBlob = true
        doc3.custodyChain = [
            CustodyEvent(actor: "finance-lead@acme-corp.com", action: .uploaded, deviceId: "iMac_Finance_01", notes: "Uploaded final signed PDF report from Deloitte.")
        ]
        
        var doc4 = VaultDocument(
            id: "Doc_IRS_Form_1120_2025",
            name: "2025_IRS_Form_1120.pdf",
            fileExtension: "pdf",
            mimeType: "application/pdf",
            size: 412000,
            folderId: "Folder_Financial_Audits",
            ownerId: "finance-lead@acme-corp.com",
            tenantId: tenant,
            tags: ["tax", "irs", "form-1120", "2025", "financial"],
            status: .archived,
            version: 1,
            source: DocumentSource(type: .filePicker, capturedBy: "finance-lead@acme-corp.com", capturedAt: Date()),
            processingStatus: .complete,
            ocrProcessed: true,
            custodyId: "Cust_Tax_Form",
            client: "IRS (4000)",
            matter: "Form 1120 (F01)",
            author: "Harold Finch",
            profileDocType: "Tax Return"
        )
        doc4.textContent = "Form 1120 - U.S. Corporation Income Tax Return (2025)\nAcme Corporation\nEmployer Identification Number (EIN): 12-3456789\nState of Incorporation: Delaware\nGross Receipts or Sales: $84,320,150\nCost of Goods Sold: $21,120,400\nGross Profit: $63,199,750\nTotal Deductions (Salaries, Rent, Taxes, Benefits): $48,150,000\nTaxable Income: $15,049,750\nTotal Tax Liability (21% corporate rate): $3,160,447\nTax Payments and Credits: $3,200,000\nOverpayment / Refund Due: $39,553\nSigned: Harold Finch (CFO) and Prepared by PwC LLP on April 10, 2026."
        doc4.summary = "U.S. Corporation Income Tax Return (IRS Form 1120) for Acme Corp for the tax year 2025. Reports gross receipts of $84.3M, taxable income of $15.0M, corporate tax liability of $3.16M, and an overpayment refund of $39.5K."
        doc4.contentCategory = "financial"
        doc4.hasBlob = true
        doc4.custodyChain = [
            CustodyEvent(actor: "finance-lead@acme-corp.com", action: .uploaded, deviceId: "iMac_Finance_01", notes: "Filing tax copy saved to archive.")
        ]
        
        var doc5 = VaultDocument(
            id: "Doc_Employee_Handbook_2026",
            name: "Acme_Employee_Handbook_2026.pdf",
            fileExtension: "pdf",
            mimeType: "application/pdf",
            size: 512000,
            folderId: "Folder_HR_Operations",
            ownerId: "hr-manager@acme-corp.com",
            tenantId: tenant,
            tags: ["hr", "employee", "handbook", "policy", "operations", "onboarding"],
            status: .published,
            version: 1,
            source: DocumentSource(type: .filePicker, capturedBy: "hr-manager@acme-corp.com", capturedAt: Date()),
            processingStatus: .complete,
            ocrProcessed: true,
            custodyId: "Cust_Handbook",
            client: "Acme Corp (1000)",
            matter: "General (G01)",
            author: "hr-manager@acme-corp.com",
            profileDocType: "Handbook"
        )
        doc5.textContent = "ACME CORPORATION - EMPLOYEE HANDBOOK\nEdition: 2026\nWelcome to Acme Corp! We are excited to have you on our team.\nCore Policies:\n1. Code of Conduct: Acme is committed to providing a workspace free of harassment and discrimination. All employees must act with integrity, professionalism, and respect.\n2. Work Hours & Remote Work: Our remote work options are available up to 3 days per week with manager approval.\n3. Leave Policy: Employees receive 20 days of Paid Time Off (PTO), 10 days of sick leave.\n4. Secure Data Usage: Employees must use company-provided hardware and VPNs when accessing internal networks. Passwords must be updated quarterly.\n5. Benefits: Health, dental, and vision insurance are fully covered. 401(k) retirement matching is provided up to 4% of salary."
        doc5.summary = "Employee handbook for Acme Corp (2026 edition). Outlines core codes of conduct, 20 days PTO leave policy, remote work guidelines, data security requirements, and benefits (health insurance, 4% 401k matching)."
        doc5.contentCategory = "hr"
        doc5.hasBlob = true
        doc5.custodyChain = [
            CustodyEvent(actor: "hr-manager@acme-corp.com", action: .uploaded, deviceId: "iPad_HR_01", notes: "Uploaded final approved edition of handbook for all employees.")
        ]
        
        var doc6 = VaultDocument(
            id: "Doc_CBL_Database_Schema_Spec",
            name: "CBL_Database_Schema_Spec.txt",
            fileExtension: "txt",
            mimeType: "text/plain",
            size: 15400,
            folderId: "Folder_Technical_Specs",
            ownerId: "tech-architect@acme-corp.com",
            tenantId: tenant,
            tags: ["technical", "database", "schema", "couchbase", "spec", "sqlite"],
            status: .published,
            version: 2,
            source: DocumentSource(type: .filePicker, capturedBy: "tech-architect@acme-corp.com", capturedAt: Date()),
            processingStatus: .complete,
            ocrProcessed: true,
            custodyId: "Cust_CBL_Schema",
            client: "Acme Corp (1000)",
            matter: "General (G01)",
            author: "tech-architect@acme-corp.com",
            profileDocType: "Technical Spec"
        )
        doc6.textContent = "COUCHBASE LITE SYNCED OFFLINE DATABASE SCHEMA SPECIFICATION\nVersion: 2.1\nDocument Type definitions for the DocumentVault database.\n1. Collections Structure:\n- `documents`: Stores document metadata and search indexes.\n- `folders`: Stores workspace directory names and hierarchy.\n- `annotations`: Stores annotations, highlights, and reviewer comments.\n- `profile`: User profiles, local settings, and sync credentials.\n2. Document Schema definition:\n- `id` (String): Prefix `Doc_` + UUID.\n- `docType` (String): Constant 'Document'.\n- `name` (String): e.g. 'CBL_Database_Schema_Spec.txt'.\n- `embedding` (Array of 512 Floats): L2 normalized vector embedding.\n- `processingStatus` (String): 'complete'.\n3. Sync Gateway Configuration:\n- Documents are dynamically routed to channels based on tenantId and folderId."
        doc6.summary = "Technical specification of Couchbase Lite offline database schemas, collections, document structures (metadata, embeddings, custody chains), and Sync Gateway routing for DocumentVault."
        doc6.contentCategory = "technical"
        doc6.hasBlob = true
        doc6.custodyChain = [
            CustodyEvent(actor: "tech-architect@acme-corp.com", action: .uploaded, deviceId: "MacBook_Tech_01", notes: "Ingested v1.0 version."),
            CustodyEvent(actor: "tech-architect@acme-corp.com", action: .contentReplaced, notes: "Updated to v2.1 including collections and vector index specification.")
        ]
        
        var sampleDocs = [doc1, doc2, doc3, doc4, doc5, doc6]
        
        // Generate 200 more files of various types to satisfy the 200 vector index training limit!
        for i in 1...200 {
            let folderIndex = i % 4
            let docId = "Doc_Scale_Mock_\(i)"
            let folderId: String
            let owner: String
            let category: String
            let ext: String
            let mime: String
            let client: String
            let matter: String
            let author: String
            let docType: String
            let content: String
            let summary: String
            let tags: [String]
            let actor: String
            
            // Choose type and metadata based on folder index
            switch folderIndex {
            case 0:
                folderId = "Folder_Legal_Contracts"
                owner = "legal-admin@acme-corp.com"
                category = "legal"
                ext = i % 2 == 0 ? "pdf" : "txt"
                mime = i % 2 == 0 ? "application/pdf" : "text/plain"
                client = i % 3 == 0 ? "Hooli Inc (4500)" : "Initech Corp (5000)"
                matter = "Litigation Dispute (L0\(i % 5 + 1))"
                author = "Sarah Jenkins"
                docType = "Legal Agreement"
                content = "LEGAL AGREEMENT & SETTLEMENT DISCLOSURE\nThis document outlines the settlement details between Acme Corporation and our client regarding the software dispute of 2026. The terms mandate that both parties keep all proprietary code secret under penalty of law. Matter reference code \(matter)."
                summary = "Legal settlement agreement between Acme Corp and client regarding software dispute. Reference matter \(matter)."
                tags = ["legal", "settlement", "agreement", "dispute", "confidential"]
                actor = "legal-admin@acme-corp.com"
            case 1:
                folderId = "Folder_Financial_Audits"
                owner = "finance-lead@acme-corp.com"
                category = "financial"
                ext = i % 2 == 0 ? "csv" : "pdf"
                mime = i % 2 == 0 ? "text/csv" : "application/pdf"
                client = "PricewaterhouseCoopers (6000)"
                matter = "Corporate Tax (T0\(i % 5 + 1))"
                author = "Harold Finch"
                docType = "Tax Schedule"
                content = "ACME CORP TAX AUDIT SCHEDULE\nFY2025/2026 tax computations showing gross assets of $142,500,000 and total liabilities of $45,000,000. Under review by PwC audits group for compliance verification."
                summary = "Financial tax compliance schedule reviewed by PwC. Total assets listed at $142.5M. Reference matter \(matter)."
                tags = ["tax", "audit", "finance", "compliance", "balance-sheet"]
                actor = "finance-lead@acme-corp.com"
            case 2:
                folderId = "Folder_HR_Operations"
                owner = "hr-manager@acme-corp.com"
                category = "hr"
                ext = "txt"
                mime = "text/plain"
                client = "Internal Staff"
                matter = "Performance Review (HR0\(i % 5 + 1))"
                author = "HR Operations Team"
                docType = "Policy Guideline"
                content = "ACME CORPORATE HR PERFORMANCE STANDARDS\nThis technical guidance handbook establishes the standard parameters for employee evaluations, quarterly goals, performance metrics, and compliance training requirements."
                summary = "HR guidelines detailing standard employee quarterly performance evaluations and compliance standards."
                tags = ["hr", "policy", "handbook", "performance", "operations"]
                actor = "hr-manager@acme-corp.com"
            default:
                folderId = "Folder_Technical_Specs"
                owner = "tech-architect@acme-corp.com"
                category = "technical"
                ext = i % 2 == 0 ? "png" : "txt"
                mime = i % 2 == 0 ? "image/png" : "text/plain"
                client = "Acme Engineering"
                matter = "Cloud Infrastructure (ENG0\(i % 5 + 1))"
                author = "tech-architect@acme-corp.com"
                docType = "Technical Spec"
                content = "CLOUD INFRASTRUCTURE AND COUCHBASE ARCHITECTURE SPECIFICATION\nTechnical document outlining the node configuration, deployment clusters, sync gateways, and replication parameters for the cloud database. Matter reference \(matter)."
                summary = "Technical specification mapping node deployments and database sync rules. Reference matter \(matter)."
                tags = ["technical", "cloud", "architecture", "database", "spec", "couchbase"]
                actor = "tech-architect@acme-corp.com"
            }
            
            var generatedDoc = VaultDocument(
                id: docId,
                name: "Document_Scale_Reference_\(i).\(ext)",
                fileExtension: ext,
                mimeType: mime,
                size: 15000 + i * 230,
                folderId: folderId,
                ownerId: owner,
                tenantId: tenant,
                tags: tags,
                status: .published,
                version: 1,
                source: DocumentSource(type: .filePicker, capturedBy: owner, capturedAt: Date()),
                processingStatus: .complete,
                ocrProcessed: true,
                custodyId: "Cust_Scale_\(i)",
                client: client,
                matter: matter,
                author: author,
                profileDocType: docType
            )
            generatedDoc.textContent = content
            generatedDoc.summary = summary
            generatedDoc.contentCategory = category
            generatedDoc.hasBlob = true
            
            // Add a mock chain of custody with some multi-step timelines to make search interesting!
            var custody = [
                CustodyEvent(actor: actor, action: .uploaded, deviceId: "MacBook_Pro_Scale_\(i % 3 + 1)", notes: "Ingested via programmatic seeder.")
            ]
            if i % 3 == 0 {
                custody.append(CustodyEvent(actor: "system", action: .viewed, notes: "Automated indexing pipeline completed successfully."))
            } else if i % 3 == 1 {
                custody.append(CustodyEvent(actor: "compliance-officer@acme-corp.com", action: .moved, notes: "Moved to folder \(folderId)."))
            }
            generatedDoc.custodyChain = custody
            
            sampleDocs.append(generatedDoc)
        }

        var seededDocsCount = 0
        
        for var doc in sampleDocs {
            // Generate vector embedding for semantic search
            let namePrefix = doc.name.replacingOccurrences(of: ".", with: " ")
            let bodyText = doc.summary ?? doc.textContent ?? doc.tags.joined(separator: " ")
            let embeddingText = "\(namePrefix) \(bodyText)"
            
            print("🧠 Generating embedding for seeded doc: \(doc.name)")
            if let embedding = await EmbeddingManager.shared.generateTextEmbedding(from: embeddingText) {
                doc.embedding = embedding
            }
            
            // Generate and save dynamic local file bytes
            let mockData = generateSeededFileData(forText: doc.textContent ?? "No content", fileExtension: doc.fileExtension)
            if let localPath = try? await ContentStorageService.shared.save(data: mockData, for: doc.id, extension: doc.fileExtension) {
                doc.contentLocalPath = localPath
            }
            
            try saveDocument(doc)
            
            // Attach CBL blob so database has the actual file data for previews and syncing
            let blob = Blob(contentType: doc.mimeType, data: mockData)
            try? attachBlob(blob, toDocumentId: doc.id)
            
            seededDocsCount += 1
        }
        
        print("✅ Seeding completed: seeded \(seededFoldersCount) folders and \(seededDocsCount) documents.")
        
        // Notify views to reload
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .vaultDocumentsChanged, object: nil)
            NotificationCenter.default.post(name: .vaultFoldersChanged, object: nil)
        }
        
        return (seededFoldersCount, seededDocsCount)
    }
}
