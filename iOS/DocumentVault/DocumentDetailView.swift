import SwiftUI
import QuickLook

struct DocumentDetailView: View {
    let document: VaultDocument
    @EnvironmentObject var dbManager: DatabaseManager
    @EnvironmentObject var authManager: AuthenticationManager

    @State private var currentDoc: VaultDocument? = nil
    @State private var quickLookURL: URL? = nil
    @State private var showCustody      = false
    @State private var selectedPanel    = Panel.info
    @State private var showDeleteAlert  = false
    @State private var showMoveSheet    = false
    @State private var isReprocessing   = false
    @State private var showFileNotFound   = false
    @State private var showIntegrityError = false
    @State private var isLoadingPreview   = false
    @State private var blobInfo: (present: Bool, length: Int, localBytes: Int)? = nil
    @State private var isEditingProfile = false
    @State private var client = ""
    @State private var matter = ""
    @State private var author = ""
    @State private var profileDocType = ""
    @State private var validationError: String? = nil
    @State private var annotations: [Annotation] = []
    @State private var newAnnotationText = ""
    @Environment(\.dismiss) private var dismiss

    private var doc: VaultDocument { currentDoc ?? document }

    private var resolvedLocalPath: String {
        ContentStorageService.shared.resolveActualPath(forDocumentId: doc.id, fileExtension: doc.fileExtension)
    }

    private enum Panel: String, CaseIterable {
        case info = "Info"
        case custody = "Custody"
        case annotations = "Notes"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                previewHeader
                    .padding(.bottom, 12)

                Picker("Panel", selection: $selectedPanel) {
                    ForEach(Panel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 12)

                switch selectedPanel {
                case .info:       infoPanel
                case .custody:    CustodyTimelineView(document: doc)
                                      .environmentObject(authManager)
                case .annotations: annotationsPanel
                }
            }
        }
        .navigationTitle(doc.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !doc.isDeleted {
                    Menu {
                        Button {
                            showMoveSheet = true
                        } label: {
                            Label("Move to Folder", systemImage: "folder")
                        }

                        Button {
                            reprocess()
                        } label: {
                            Label("Reprocess", systemImage: "arrow.clockwise")
                        }

                        Divider()

                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .alert("Delete Document?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) { deleteDocument() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will be recorded in the chain of custody and cannot be undone.")
        }
        .alert("File Not Found", isPresented: $showFileNotFound) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The local file for this document is missing and no stored copy was found.")
        }
        .alert("Integrity Check Failed", isPresented: $showIntegrityError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The file's content does not match its stored hash. It may be corrupted. Use Reprocess to re-ingest.")
        }
        .sheet(isPresented: $showMoveSheet) {
            MoveFolderSheet(document: doc, dbManager: dbManager, authManager: authManager)
        }
        .sheet(item: $quickLookURL) { url in
            QuickLookView(url: url)
        }
        .onAppear { refreshDoc(); refreshBlobInfo(); loadAnnotations(); autoHealLocalFile() }
        .onReceive(NotificationCenter.default.publisher(for: .vaultDocumentsChanged)) { _ in refreshDoc(); refreshBlobInfo(); loadAnnotations(); autoHealLocalFile() }
        .onReceive(NotificationCenter.default.publisher(for: .vaultAnnotationsChanged)) { _ in loadAnnotations() }
    }

    // MARK: - Preview Header

    private var previewHeader: some View {
        VStack(spacing: 12) {
            Button {
                openPreview()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemGray6))
                        .frame(height: 120)
                        .padding(.horizontal)
                    VStack(spacing: 6) {
                        Image(systemName: fileIcon)
                            .font(.system(size: 40))
                            .foregroundColor(.accentColor)
                        Text(doc.displayMimeType)
                            .font(.caption).foregroundColor(.secondary)
                        Text("Tap to open")
                            .font(.caption2).foregroundColor(.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(doc.isDeleted)

            Button {
                openPreview()
            } label: {
                if isLoadingPreview {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text("Loading…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label("Open Document", systemImage: "eye")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .disabled(doc.isDeleted || isLoadingPreview)

            // Status + source badges
            HStack(spacing: 8) {
                if doc.isDeleted {
                    Label("Deleted", systemImage: "trash.fill")
                        .font(.caption2)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.red.opacity(0.12))
                        .foregroundColor(.red)
                        .clipShape(Capsule())
                } else {
                    StatusBadge(status: doc.status)
                }
                if doc.isFromEmail {
                    Label("Email", systemImage: "envelope.fill")
                        .font(.caption2)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                }
                if !doc.isDeleted {
                    if isReprocessing {
                        Label("Reprocessing…", systemImage: "arrow.clockwise")
                            .font(.caption2)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.orange.opacity(0.1))
                            .foregroundColor(.orange)
                            .clipShape(Capsule())
                    } else if doc.processingStatus == .complete {
                        Label("Indexed", systemImage: "sparkle.magnifyingglass")
                            .font(.caption2)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Info Panel

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Profile & Metadata")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                if !doc.isDeleted {
                    Button(isEditingProfile ? "Cancel" : "Edit Profile") {
                        if isEditingProfile {
                            isEditingProfile = false
                        } else {
                            startEditing()
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)

            if isEditingProfile {
                VStack(alignment: .leading, spacing: 12) {
                    // Client Picker
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Client").font(.caption).foregroundColor(.secondary)
                        Picker("Select Client", selection: $client) {
                            Text("None").tag("")
                            ForEach(Array(ProfileMetadata.clients.keys).sorted(), id: \.self) { c in
                                Text(c).tag(c)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: client) { _, newClient in
                            // Auto-select first matter or clear if client changes to prevent invalid combo
                            if let firstMatter = ProfileMetadata.clients[newClient]?.first {
                                matter = firstMatter
                            } else {
                                matter = ""
                            }
                        }
                    }
                    
                    // Matter Picker
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Matter").font(.caption).foregroundColor(.secondary)
                        if !client.isEmpty, let matters = ProfileMetadata.clients[client] {
                            Picker("Select Matter", selection: $matter) {
                                Text("None").tag("")
                                ForEach(matters, id: \.self) { m in
                                    Text(m).tag(m)
                                }
                            }
                            .pickerStyle(.menu)
                        } else {
                            Text("Select a Client first").font(.caption2).foregroundColor(.orange)
                        }
                    }
                    
                    // Author Picker
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Author").font(.caption).foregroundColor(.secondary)
                        Picker("Select Author", selection: $author) {
                            Text("None").tag("")
                            ForEach(ProfileMetadata.authors, id: \.self) { a in
                                Text(a).tag(a)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    // Doc Type Picker
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Document Type").font(.caption).foregroundColor(.secondary)
                        Picker("Select Doc Type", selection: $profileDocType) {
                            Text("None").tag("")
                            ForEach(ProfileMetadata.documentTypes, id: \.self) { dt in
                                Text(dt).tag(dt)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    // Suggestions Section
                    let suggestions = dbManager.getSuggestedMatters(forDocument: doc)
                    if !suggestions.isEmpty {
                        Divider().padding(.vertical, 4)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Suggested Case Matters")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.indigo)
                            
                            ForEach(suggestions.prefix(3)) { suggestion in
                                Button(action: {
                                    self.client = suggestion.client
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        self.matter = suggestion.matter
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "lightbulb.fill")
                                            .foregroundColor(.amber)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(suggestion.matter)
                                                .font(.caption.bold())
                                                .foregroundColor(.primary)
                                            Text("Client: \(suggestion.client)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Text(String(format: "%.0f%% Match", suggestion.score * 100))
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.indigo.opacity(0.1))
                                            .foregroundColor(.indigo)
                                            .clipShape(Capsule())
                                    }
                                    .padding(8)
                                    .background(Color(.systemBackground))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.indigo.opacity(0.2), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if let error = validationError {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.red)
                            .padding(.top, 4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack {
                        Spacer()
                        Button("Save Profile Changes") {
                            saveProfile()
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                    .padding(.top, 8)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.bottom, 16)
            } else {
                infoRow("Client", doc.client ?? "Not Profiled")
                infoRow("Matter", doc.matter ?? "Not Profiled")
                infoRow("Author", doc.author ?? "Not Profiled")
                infoRow("Doc Type", doc.profileDocType ?? "Not Profiled")
                
                Divider().padding(.vertical, 8)
            }

            infoRow("File", doc.name)
            infoRow("Type", doc.displayMimeType)
            infoRow("Size", ByteCountFormatter.string(fromByteCount: Int64(doc.size), countStyle: .file))
            infoRow("Version", "v\(doc.version)")
            infoRow("Created", doc.createdAt.formatted(date: .abbreviated, time: .shortened))
            infoRow("Updated", doc.updatedAt.formatted(date: .abbreviated, time: .shortened))
            infoRow("Owner", doc.ownerId)
            if let category = doc.contentCategory {
                infoRow("Category", category.capitalized)
            }

            if let summary = doc.summary {
                Divider().padding(.vertical, 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Summary")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(summary)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }

            if doc.isDeleted, let deletedAt = doc.deletedAt {
                infoRow("Deleted", deletedAt.formatted(date: .abbreviated, time: .shortened))
            }

            if let meta = doc.source.emailMetadata {
                Divider().padding(.vertical, 8)
                Text("Email Source").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                    .padding(.horizontal).padding(.top, 4)
                infoRow("From",    meta.from)
                infoRow("Subject", meta.subject)
                infoRow("Thread",  meta.threadId)
                infoRow("Received", meta.receivedAt.formatted(date: .abbreviated, time: .shortened))
            }

            if !doc.tags.isEmpty {
                Divider().padding(.vertical, 8)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 6) {
                    ForEach(doc.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption2)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.1))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            if let hash = doc.contentHash {
                Divider().padding(.vertical, 8)
                infoRow("Integrity", String(hash.prefix(16)) + "…")
                infoRow("Custody ID", String(doc.custodyId.prefix(16)) + "…")
            }

            Divider().padding(.vertical, 8)
            storageStatusSection
        }
        .padding(.bottom, 24)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption).foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: - Storage Diagnostics

    @ViewBuilder
    private var storageStatusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Storage")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal)

            if let info = blobInfo {
                // CBL blob
                HStack(spacing: 6) {
                    Image(systemName: info.present ? "internaldrive.fill" : "internaldrive")
                        .foregroundColor(info.present && info.length > 0 ? .green : .red)
                        .font(.caption)
                    if info.present && info.length > 0 {
                        Text("CBL blob · \(ByteCountFormatter.string(fromByteCount: Int64(info.length), countStyle: .file))")
                            .font(.caption).foregroundColor(.primary)
                    } else if info.present {
                        Text("CBL blob present but 0 bytes — re-upload to repair")
                            .font(.caption).foregroundColor(.orange)
                    } else {
                        Text("No CBL blob — tap Reprocess if local file exists")
                            .font(.caption).foregroundColor(.red)
                    }
                }
                .padding(.horizontal)

                // Local file
                HStack(spacing: 6) {
                    Image(systemName: info.localBytes > 0 ? "doc.fill" : (info.localBytes == 0 ? "doc.badge.exclamationmark" : "doc"))
                        .foregroundColor(info.localBytes > 0 ? .green : (info.localBytes == 0 ? .orange : .secondary))
                        .font(.caption)
                    if info.localBytes > 0 {
                        Text("Local file · \(ByteCountFormatter.string(fromByteCount: Int64(info.localBytes), countStyle: .file))")
                            .font(.caption).foregroundColor(.primary)
                    } else if info.localBytes == 0 {
                        Text("Local file is 0 bytes — re-upload to repair")
                            .font(.caption).foregroundColor(.orange)
                    } else {
                        Text("No local file — will use CBL blob on open")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
            } else {
                Text("Checking…").font(.caption).foregroundColor(.secondary).padding(.horizontal)
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Annotations Panel

    private var annotationsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Add Annotation Input Area
            VStack(alignment: .leading, spacing: 8) {
                Text("Add Case Note / Annotation")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                
                HStack(alignment: .top) {
                    TextField("Enter facts, notes, or findings...", text: $newAnnotationText, axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Add") {
                        addAnnotation()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newAnnotationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            Divider()
            
            if annotations.isEmpty {
                VStack(spacing: 8) {
                    Spacer().frame(height: 20)
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No annotations yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Adding facts here will automatically re-vectorize the document to steer search results.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 24)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Active Case Notes (\(annotations.filter { !$0.resolved }.count))")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                    
                    ForEach(annotations) { ann in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(ann.authorEmail ?? ann.authorId, systemImage: "person.circle.fill")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(ann.createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(ann.body)
                                .font(.subheadline)
                                .foregroundColor(ann.resolved ? .secondary : .primary)
                                .strikethrough(ann.resolved, color: .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            HStack {
                                Spacer()
                                Button(action: {
                                    toggleResolveAnnotation(ann)
                                }) {
                                    Label(
                                        ann.resolved ? "Re-open (Influence Index)" : "Resolve (Remove from Index)",
                                        systemImage: ann.resolved ? "arrow.uturn.backward.circle" : "checkmark.circle"
                                    )
                                    .font(.caption2)
                                    .foregroundColor(ann.resolved ? .accentColor : .green)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding()
                        .background(ann.resolved ? Color(.systemGray6).opacity(0.5) : Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Actions

    private func openPreview() {
        let path = resolvedLocalPath
        if FileManager.default.fileExists(atPath: path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           (attrs[.size] as? Int ?? 0) > 0 {
            quickLookURL = URL(fileURLWithPath: path)
            recordViewed()
            return
        }

        // Slow path: extract from CBL blob, verify integrity, write to temp file
        isLoadingPreview = true
        Task {
            do {
                let url = try dbManager.extractBlobToURL(
                    forDocumentId: doc.id,
                    fileExtension: doc.fileExtension,
                    expectedHash: doc.contentHash
                )
                await MainActor.run {
                    isLoadingPreview = false
                    if let url {
                        quickLookURL = url
                        recordViewed()
                    } else {
                        showFileNotFound = true
                    }
                }
            } catch VaultError.integrityCheckFailed {
                await MainActor.run { isLoadingPreview = false; showIntegrityError = true }
            } catch {
                await MainActor.run { isLoadingPreview = false; showFileNotFound = true }
            }
        }
    }

    private func recordViewed() {
        CustodyService.shared.recordViewed(
            docId: doc.id,
            actor: authManager.currentUser?.email ?? "unknown",
            actorEmail: authManager.currentUser?.email,
            db: dbManager
        )
    }

    private func refreshDoc() {
        if let fresh = try? dbManager.fetchDocument(id: document.id) {
            currentDoc = fresh
        }
    }

    private func refreshBlobInfo() {
        let info = dbManager.fetchBlobInfo(forDocumentId: doc.id, localPath: resolvedLocalPath)
        blobInfo = (present: info.blobPresent, length: info.blobLength, localBytes: info.localFileBytes)
    }

    private func deleteDocument() {
        let actor = authManager.currentUser?.email ?? "unknown"
        try? dbManager.deleteDocument(id: doc.id, actor: actor)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { dismiss() }
    }

    private func reprocess() {
        guard !isReprocessing else { return }
        isReprocessing = true
        let actor = authManager.currentUser?.email ?? "unknown"
        CustodyService.shared.recordReprocessed(docId: doc.id, actor: actor, db: dbManager)
        Task {
            await DocumentProcessingPipeline.shared.retryProcessing(for: doc.id, db: dbManager)
            await MainActor.run { isReprocessing = false }
        }
    }
    
    private func autoHealLocalFile() {
        Task {
            if let _ = await ContentStorageService.shared.ensureLocalFileExists(
                forDocumentId: doc.id,
                fileExtension: doc.fileExtension,
                db: dbManager
            ) {
                await MainActor.run {
                    refreshDoc()
                    refreshBlobInfo()
                }
            }
        }
    }

    private func startEditing() {
        client = doc.client ?? ""
        matter = doc.matter ?? ""
        author = doc.author ?? ""
        profileDocType = doc.profileDocType ?? ""
        validationError = nil
        isEditingProfile = true
    }

    private func saveProfile() {
        // Enforce parent-child validation:
        // The selected matter must belong to the selected client in ProfileMetadata.clients
        if !client.isEmpty {
            if let validMatters = ProfileMetadata.clients[client] {
                if !matter.isEmpty && !validMatters.contains(matter) {
                    validationError = "Validation Error: Selected Matter does not belong to the selected Client (\(client))."
                    return
                }
            } else {
                validationError = "Validation Error: Selected Client is invalid."
                return
            }
        } else if !matter.isEmpty {
            validationError = "Validation Error: Matter cannot be specified without a Client."
            return
        }

        // Proceed with save
        guard var updated = try? dbManager.fetchDocument(id: doc.id) else { return }
        updated.client = client.isEmpty ? nil : client
        updated.matter = matter.isEmpty ? nil : matter
        updated.author = author.isEmpty ? nil : author
        updated.profileDocType = profileDocType.isEmpty ? nil : profileDocType
        updated.updatedAt = Date()
        
        do {
            try dbManager.saveDocument(updated)
            CustodyService.shared.recordMoved(
                docId: document.id,
                actor: authManager.currentUser?.email ?? "unknown",
                to: "Metadata Profile: \(client)/\(matter)",
                db: dbManager
            )
            isEditingProfile = false
            validationError = nil
            currentDoc = updated
            NotificationCenter.default.post(name: .vaultDocumentsChanged, object: nil)
        } catch {
            validationError = "Failed to save profile details."
        }
    }

    private func loadAnnotations() {
        annotations = (try? dbManager.fetchAnnotations(forDocumentId: doc.id)) ?? []
    }

    private func addAnnotation() {
        let cleaned = newAnnotationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        
        let author = authManager.currentUser?.email ?? "unknown"
        let tenant = authManager.currentUser?.tenantId ?? AppConfig.currentTenantId
        let newAnn = Annotation(
            documentId: doc.id,
            tenantId: tenant,
            authorId: author,
            authorEmail: author,
            body: cleaned
        )
        
        do {
            try dbManager.saveAnnotation(newAnn)
            newAnnotationText = ""
            loadAnnotations()
            
            CustodyService.shared.recordMoved(
                docId: doc.id,
                actor: author,
                to: "Added annotation fact: \(cleaned.prefix(20))…",
                db: dbManager
            )
            
            // Re-vectorize document in background
            Task {
                await DocumentProcessingPipeline.shared.retryProcessing(for: doc.id, db: dbManager)
            }
        } catch {
            print("⚠️ Failed to save annotation: \(error)")
        }
    }

    private func toggleResolveAnnotation(_ ann: Annotation) {
        var updated = ann
        updated.resolved.toggle()
        updated.updatedAt = Date()
        
        do {
            try dbManager.saveAnnotation(updated)
            loadAnnotations()
            
            let author = authManager.currentUser?.email ?? "unknown"
            let actionText = updated.resolved ? "Resolved annotation" : "Re-opened annotation"
            CustodyService.shared.recordMoved(
                docId: doc.id,
                actor: author,
                to: "\(actionText): \(ann.body.prefix(20))…",
                db: dbManager
            )
            
            // Re-vectorize document in background
            Task {
                await DocumentProcessingPipeline.shared.retryProcessing(for: doc.id, db: dbManager)
            }
        } catch {
            print("⚠️ Failed to toggle resolve annotation: \(error)")
        }
    }

    private var fileIcon: String {
        switch doc.fileExtension.lowercased() {
        case "pdf":               return "doc.richtext.fill"
        case "doc", "docx":       return "doc.text.fill"
        case "xls", "xlsx", "csv": return "tablecells.fill"
        case "jpg", "jpeg", "png", "heic": return "photo.fill"
        default:                  return "doc.fill"
        }
    }
}

// MARK: - NetDocuments Metadata Definition

struct ProfileMetadata {
    static let clients = [
        "Acme Corp (1000)": ["General (G01)", "SaaS Agreement (S02)", "Board Resolutions (B03)"],
        "Globex Corp (2000)": ["NDA (N01)", "IP Assignment (I02)"],
        "Deloitte & Touche (3000)": ["Audit (A01)", "Consulting (C02)"],
        "IRS (4000)": ["Form 1120 (F01)", "Audit Response (R02)"]
    ]
    
    static let authors = [
        "John Doe", "Sarah Jenkins", "Harold Finch", "hr-manager@acme-corp.com",
        "legal-admin@acme-corp.com", "finance-lead@acme-corp.com", "tech-architect@acme-corp.com"
    ]
    
    static let documentTypes = [
        "Agreement / NDA", "Board Minute", "Audit Report", "Tax Return", "Handbook", "Technical Spec", "General Correspondence"
    ]
}

// MARK: - Move Folder Sheet

struct MoveFolderSheet: View {
    let document: VaultDocument
    let dbManager: DatabaseManager
    let authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss
    @State private var folders: [Folder] = []

    var body: some View {
        NavigationStack {
            List {
                // Root (no folder)
                Button {
                    move(to: nil, folderName: "Root")
                } label: {
                    HStack {
                        Image(systemName: "tray").foregroundColor(.accentColor)
                        Text("Root (no folder)")
                        Spacer()
                        if document.folderId == nil {
                            Image(systemName: "checkmark").foregroundColor(.accentColor)
                        }
                    }
                }
                .foregroundColor(.primary)

                ForEach(folders) { folder in
                    Button {
                        move(to: folder.id, folderName: folder.name)
                    } label: {
                        HStack {
                            Image(systemName: folder.icon ?? "folder.fill").foregroundColor(.accentColor)
                            Text(folder.name)
                            Spacer()
                            if document.folderId == folder.id {
                                Image(systemName: "checkmark").foregroundColor(.accentColor)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .navigationTitle("Move to Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                folders = (try? dbManager.fetchFolders()) ?? []
            }
        }
    }

    private func move(to folderId: String?, folderName: String) {
        guard var updated = try? dbManager.fetchDocument(id: document.id) else { dismiss(); return }
        updated.folderId  = folderId
        updated.updatedAt = Date()
        try? dbManager.saveDocument(updated)
        CustodyService.shared.recordMoved(
            docId: document.id,
            actor: authManager.currentUser?.email ?? "unknown",
            to: folderName,
            db: dbManager
        )
        NotificationCenter.default.post(name: .vaultDocumentsChanged, object: nil)
        dismiss()
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: DocumentStatus
    var body: some View {
        Label(status.displayName, systemImage: status.systemImage)
            .font(.caption2)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(backgroundColor.opacity(0.12))
            .foregroundColor(backgroundColor)
            .clipShape(Capsule())
    }
    private var backgroundColor: Color {
        switch status {
        case .draft:      return .gray
        case .review:     return .blue
        case .published:  return .green
        case .archived:   return .brown
        case .quarantine: return .orange
        }
    }
}

// MARK: - QuickLook Wrapper

struct QuickLookView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> QLPreviewController {
        let vc = QLPreviewController()
        vc.dataSource = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: QLPreviewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in: QLPreviewController) -> Int { 1 }
        func previewController(_: QLPreviewController, previewItemAt: Int) -> QLPreviewItem { url as QLPreviewItem }
    }
}

extension URL: Identifiable {
    public var id: String { self.absoluteString }
}
