import SwiftUI

struct FolderBrowserView: View {
    @EnvironmentObject var dbManager: DatabaseManager
    @EnvironmentObject var authManager: AuthenticationManager

    @State private var folders: [Folder] = []
    @State private var rootDocuments: [VaultDocument] = []
    @State private var showDeletedView = false
    @State private var deletedDocCount = 0
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var isGridView = true
    @State private var folderToRename: Folder? = nil
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            Group {
                if folders.isEmpty && rootDocuments.isEmpty && deletedDocCount == 0 {
                    emptyState
                } else {
                    content
                }
            }
            .navigationTitle("Documents")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    SyncStatusBadge()
                        .environmentObject(dbManager)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { withAnimation { isGridView.toggle() } } label: {
                        Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                    }
                    Button { showNewFolder = true } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    Button { showDeletedView = true } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "trash")
                            if deletedDocCount > 0 {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 4, y: -4)
                            }
                        }
                    }
                }
            }
            .alert("New Folder", isPresented: $showNewFolder) {
                TextField("Folder name", text: $newFolderName)
                Button("Create") { createFolder() }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Rename Folder", isPresented: Binding(
                get: { folderToRename != nil },
                set: { if !$0 { folderToRename = nil } }
            )) {
                TextField("Folder name", text: $renameText)
                Button("Rename") { renameFolder() }
                Button("Cancel", role: .cancel) { folderToRename = nil }
            }
            .onAppear(perform: load)
            .onReceive(NotificationCenter.default.publisher(for: .vaultDocumentsChanged)) { _ in load() }
            .onReceive(NotificationCenter.default.publisher(for: .vaultFoldersChanged))   { _ in load() }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if !folders.isEmpty || deletedDocCount > 0 {
                    Section {
                        if isGridView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 12) {
                                ForEach(folders) { folder in
                                    NavigationLink {
                                        DocumentListView(folder: folder)
                                            .environmentObject(dbManager)
                                            .environmentObject(authManager)
                                    } label: {
                                        FolderCard(folder: folder)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button { beginRename(folder) } label: {
                                            Label("Rename", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) { deleteFolder(folder) } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                                if deletedDocCount > 0 {
                                    DeletedSystemFolderCard(count: deletedDocCount) {
                                        showDeletedView = true
                                    }
                                }
                            }
                        } else {
                            ForEach(folders) { folder in
                                NavigationLink {
                                    DocumentListView(folder: folder)
                                        .environmentObject(dbManager)
                                        .environmentObject(authManager)
                                } label: {
                                    FolderRow(folder: folder)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { beginRename(folder) } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) { deleteFolder(folder) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                            if deletedDocCount > 0 {
                                DeletedSystemFolderRow(count: deletedDocCount) {
                                    showDeletedView = true
                                }
                            }
                        }
                    } header: {
                        sectionHeader("Folders")
                    }
                }

                if !rootDocuments.isEmpty {
                    Section {
                        ForEach(rootDocuments) { doc in
                            NavigationLink {
                                DocumentDetailView(document: doc)
                                    .environmentObject(dbManager)
                                    .environmentObject(authManager)
                            } label: {
                                DocumentRow(document: doc)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        sectionHeader("Root Documents")
                    }
                }
            }
            .padding()
        }
        .navigationDestination(isPresented: $showDeletedView) {
            DeletedDocumentsView()
                .environmentObject(dbManager)
                .environmentObject(authManager)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text("No documents yet")
                .font(.headline)
            Text("Upload a file or capture a document to get started.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.primary)
            .padding(.top, 4)
    }

    // MARK: - Actions

    private func load() {
        folders          = (try? dbManager.fetchFolders()) ?? []
        rootDocuments    = (try? dbManager.fetchDocuments(inFolder: nil)) ?? []
        deletedDocCount  = (try? dbManager.fetchDeletedDocuments())?.count ?? 0
    }

    private func createFolder() {
        guard !newFolderName.isEmpty,
              let user = authManager.currentUser else { return }
        let folder = Folder(name: newFolderName, ownerId: user.email, tenantId: user.tenantId)
        try? dbManager.saveFolder(folder)
        newFolderName = ""
        load()
    }

    private func beginRename(_ folder: Folder) {
        folderToRename = folder
        renameText = folder.name
    }

    private func renameFolder() {
        guard var folder = folderToRename, !renameText.isEmpty else { return }
        folder.name = renameText
        folder.updatedAt = Date()
        try? dbManager.saveFolder(folder)
        folderToRename = nil
        load()
    }

    private func deleteFolder(_ folder: Folder) {
        try? dbManager.deleteFolder(id: folder.id)
        load()
    }
}

// MARK: - Deleted System Folder Card

struct DeletedSystemFolderCard: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "trash.fill")
                        .font(.title)
                        .foregroundColor(.red)
                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .offset(x: 8, y: -4)
                }
                Text("Deleted")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.red.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.red.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct DeletedSystemFolderRow: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "trash.fill")
                    .foregroundColor(.red)
                    .frame(width: 32)
                Text("Deleted")
                    .font(.body)
                Text("\(count) item\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(.secondary).font(.caption)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(Color.red.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.red.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Folder Card

struct FolderCard: View {
    let folder: Folder
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: folder.icon ?? "folder.fill")
                .font(.title)
                .foregroundColor(.accentColor)
            Text(folder.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Folder Row

struct FolderRow: View {
    let folder: Folder
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: folder.icon ?? "folder.fill")
                .foregroundColor(.accentColor)
                .frame(width: 32)
            Text(folder.name).font(.body)
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(.secondary).font(.caption)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
