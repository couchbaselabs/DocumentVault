import SwiftUI

struct DeletedDocumentsView: View {
    @EnvironmentObject var dbManager: DatabaseManager
    @EnvironmentObject var authManager: AuthenticationManager

    @State private var documents: [VaultDocument] = []
    @State private var docToRestore: VaultDocument?
    @State private var showRestoreConfirm = false

    private var recoverable: [VaultDocument] { documents.filter { $0.hasBlob } }
    private var metadataOnly: [VaultDocument] { documents.filter { !$0.hasBlob } }

    var body: some View {
        Group {
            if documents.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "trash.slash")
                        .font(.system(size: 52))
                        .foregroundColor(.secondary)
                    Text("No deleted documents")
                        .font(.headline)
                    Text("Deleted documents are retained here as historical records.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else {
                List {
                    if !recoverable.isEmpty {
                        Section {
                            ForEach(recoverable) { doc in
                                row(for: doc)
                            }
                        } header: {
                            Label("Recoverable (\(recoverable.count))", systemImage: "arrow.uturn.backward.circle.fill")
                                .foregroundColor(.green)
                        } footer: {
                            Text("File content is retained on this device. Swipe right to restore.")
                                .font(.caption2)
                        }
                    }

                    if !metadataOnly.isEmpty {
                        Section {
                            ForEach(metadataOnly) { doc in
                                row(for: doc)
                            }
                        } header: {
                            Label("Metadata Only (\(metadataOnly.count))", systemImage: "externaldrive.badge.exclamationmark")
                                .foregroundColor(.orange)
                        } footer: {
                            Text("No file content on this device. Chain of custody and metadata are preserved. Swipe right to restore the record.")
                                .font(.caption2)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Restore Document?", isPresented: $showRestoreConfirm) {
            Button("Restore") { restoreConfirmed() }
            Button("Cancel", role: .cancel) { docToRestore = nil }
        } message: {
            if let doc = docToRestore {
                Text("\"\(doc.name)\" will be restored to the active list. This action will be recorded in the chain of custody.")
            }
        }
        .onAppear { load() }
        .onReceive(NotificationCenter.default.publisher(for: .vaultDocumentsChanged)) { _ in load() }
    }

    @ViewBuilder
    private func row(for doc: VaultDocument) -> some View {
        NavigationLink {
            DocumentDetailView(document: doc)
                .environmentObject(dbManager)
                .environmentObject(authManager)
        } label: {
            DeletedDocumentRow(document: doc)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                docToRestore = doc
                showRestoreConfirm = true
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward.circle")
            }
            .tint(.green)
        }
    }

    private func load() {
        documents = (try? dbManager.fetchDeletedDocuments()) ?? []
    }

    private func restoreConfirmed() {
        guard let doc = docToRestore else { return }
        let actor = authManager.currentUser?.email ?? "unknown"
        try? dbManager.restoreDocument(id: doc.id, actor: actor)
        docToRestore = nil
    }
}

// MARK: - Deleted Document Row

struct DeletedDocumentRow: View {
    let document: VaultDocument

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: document.hasBlob ? "trash.fill" : "trash.slash.fill")
                    .foregroundColor(.red.opacity(0.7))
                    .font(.title3)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(document.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .strikethrough(true, color: .red.opacity(0.6))
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    Text(document.displayMimeType)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())

                    if document.hasBlob {
                        Label("Recoverable", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    } else {
                        Label("No content", systemImage: "externaldrive.badge.exclamationmark")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }

                if let deletedAt = document.deletedAt {
                    Text("Deleted \(deletedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundColor(.red.opacity(0.7))
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
