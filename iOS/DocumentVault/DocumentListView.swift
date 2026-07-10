import SwiftUI

struct DocumentListView: View {
    let folder: Folder
    @EnvironmentObject var dbManager: DatabaseManager
    @EnvironmentObject var authManager: AuthenticationManager

    @State private var documents: [VaultDocument] = []
    @State private var searchText = ""

    var body: some View {
        Group {
            if documents.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48)).foregroundColor(.secondary)
                    Text("No documents in this folder").foregroundColor(.secondary)
                }
            } else {
                List {
                    ForEach(filtered) { doc in
                        NavigationLink {
                            DocumentDetailView(document: doc)
                                .environmentObject(dbManager)
                                .environmentObject(authManager)
                        } label: {
                            DocumentRow(document: doc)
                        }
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(folder.name)
        .searchable(text: $searchText, prompt: "Search documents")
        .onAppear(perform: load)
        .onReceive(NotificationCenter.default.publisher(for: .vaultDocumentsChanged)) { _ in load() }
    }

    private var filtered: [VaultDocument] {
        guard !searchText.isEmpty else { return documents }
        let q = searchText.lowercased()
        return documents.filter {
            $0.name.lowercased().contains(q) ||
            $0.tags.joined(separator: " ").lowercased().contains(q) ||
            ($0.textContent ?? "").lowercased().contains(q)
        }
    }

    private func load() {
        documents = (try? dbManager.fetchDocuments(inFolder: folder.id)) ?? []
    }

    private func delete(at offsets: IndexSet) {
        let actor = authManager.currentUser?.email ?? "unknown"
        offsets.forEach { i in
            let doc = filtered[i]
            try? dbManager.deleteDocument(id: doc.id, actor: actor)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { load() }
    }
}

// MARK: - Document Row (shared)

struct DocumentRow: View {
    let document: VaultDocument

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(document.isDeleted ? 0.07 : 0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: document.isDeleted ? "trash" : iconName)
                    .foregroundColor(document.isDeleted ? .secondary : iconColor)
                    .font(.title3)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(document.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .strikethrough(document.isDeleted, color: .secondary)
                    .foregroundColor(document.isDeleted ? .secondary : .primary)

                HStack(spacing: 6) {
                    if document.isDeleted {
                        Label("Deleted", systemImage: "trash.fill")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red.opacity(0.12))
                            .foregroundColor(.red)
                            .clipShape(Capsule())
                        if let deletedAt = document.deletedAt {
                            Text(deletedAt, style: .date)
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    } else {
                        Text(document.displayMimeType)
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())

                        if !document.hasBlob {
                            Label("Metadata only", systemImage: "externaldrive.badge.exclamationmark")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }

                        statusBadge

                        if document.processingStatus != .complete && document.processingStatus != .failed {
                            processingIndicator
                        }
                    }
                }

                if !document.isDeleted, document.isFromEmail,
                   let meta = document.source.emailMetadata {
                    Text(meta.from)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(document.isDeleted ? (document.deletedAt ?? document.updatedAt) : document.updatedAt,
                 style: .relative)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .opacity(document.isDeleted ? 0.6 : 1.0)
    }

    private var iconName: String {
        let ext = document.fileExtension.lowercased()
        switch ext {
        case "pdf":                          return "doc.richtext"
        case "doc", "docx":                  return "doc.text"
        case "xls", "xlsx", "csv":           return "tablecells"
        case "jpg", "jpeg", "png", "heic":   return "photo"
        case "txt", "md":                    return "doc.plaintext"
        default:                             return "doc"
        }
    }

    private var iconColor: Color {
        let ext = document.fileExtension.lowercased()
        switch ext {
        case "pdf":                return .red
        case "doc", "docx":        return .blue
        case "xls", "xlsx", "csv": return .green
        case "jpg", "jpeg", "png", "heic": return .purple
        default:                   return .gray
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if document.status == .quarantine {
            Label("Quarantined", systemImage: "exclamationmark.shield.fill")
                .font(.caption2).foregroundColor(.orange)
        } else if document.status == .review {
            Text(document.status.displayName)
                .font(.caption2).foregroundColor(.blue)
        }
    }

    @ViewBuilder
    private var processingIndicator: some View {
        HStack(spacing: 3) {
            ProgressView().scaleEffect(0.6)
            Text(document.processingStatus == .extracting ? "Extracting" : "Indexing")
                .font(.caption2).foregroundColor(.secondary)
        }
    }
}
