import SwiftUI

struct SearchView: View {
    @EnvironmentObject var dbManager: DatabaseManager
    @EnvironmentObject var authManager: AuthenticationManager

    @State private var query         = ""
    @State private var results: [VaultDocument] = []
    @State private var mode: SearchMode = .hybrid
    @State private var isSearching   = false
    @State private var markedIds: Set<String> = []
    @State private var allFolders: [Folder] = []

    enum SearchMode: String, CaseIterable {
        case keyword = "Keyword"
        case hybrid  = "Hybrid"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(SearchMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: mode) { _, _ in if !query.isEmpty { performSearch() } }

                if results.isEmpty && !query.isEmpty && !isSearching {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 48)).foregroundColor(.secondary)
                        Text("No results for \"\(query)\"").foregroundColor(.secondary)
                    }
                    Spacer()
                } else if results.isEmpty && query.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48)).foregroundColor(.secondary)
                        Text(mode == .keyword
                             ? "Search document names, text content, and tags."
                             : "Keyword + semantic search, ranked by relevance.")
                            .font(.subheadline).foregroundColor(.secondary)
                            .multilineTextAlignment(.center).padding(.horizontal)
                    }
                    Spacer()
                } else {
                    List {
                    if !matchingMatters.isEmpty {
                        Section {
                            ForEach(matchingMatters, id: \.self) { matter in
                                NavigationLink {
                                    MatterDocumentListView(matterName: matter)
                                        .environmentObject(dbManager)
                                        .environmentObject(authManager)
                                } label: {
                                    HStack {
                                        Image(systemName: "briefcase.fill").foregroundColor(.indigo)
                                        Text(matter).font(.body)
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        } header: {
                            Label("Matters & Cases (\(matchingMatters.count))", systemImage: "briefcase")
                                .foregroundColor(.indigo)
                                .font(.caption.weight(.semibold))
                        }
                    }

                    resultSection(
                            title: "Documents",
                            icon: "doc.fill",
                            color: .accentColor,
                            docs: fullDocs
                        )
                        resultSection(
                            title: "Metadata Only",
                            icon: "doc.badge.ellipsis",
                            color: .orange,
                            docs: metadataOnlyDocs
                        )
                        resultSection(
                            title: "Deleted",
                            icon: "trash.fill",
                            color: .red,
                            docs: deletedDocs
                        )
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: mode == .keyword ? "Search keywords…" : "Search anything…")
            .onSubmit(of: .search) { performSearch() }
            .onChange(of: query) { _, v in
                if v.isEmpty { results = []; markedIds = [] } else { performSearch() }
            }
            .overlay {
                if isSearching { ProgressView().padding() }
            }
        }
    }

    // MARK: - Grouped result sets (preserve relevance order within each group)

    private var fullDocs: [VaultDocument] {
        results.filter { !$0.isDeleted && $0.hasBlob }
    }
    private var metadataOnlyDocs: [VaultDocument] {
        results.filter { !$0.isDeleted && !$0.hasBlob }
    }
    private var deletedDocs: [VaultDocument] {
        results.filter { $0.isDeleted }
    }

    @ViewBuilder
    private func resultSection(title: String, icon: String, color: Color, docs: [VaultDocument]) -> some View {
        if !docs.isEmpty {
            Section {
                ForEach(docs) { doc in
                    NavigationLink {
                        DocumentDetailView(document: doc)
                            .environmentObject(dbManager)
                            .environmentObject(authManager)
                    } label: {
                        HStack {
                            DocumentRow(document: doc)
                            if markedIds.contains(doc.id) {
                                Image(systemName: "hand.thumbsup.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button { markRelevant(doc) } label: {
                            Label("Relevant", systemImage: markedIds.contains(doc.id)
                                  ? "hand.thumbsup.fill" : "hand.thumbsup")
                        }
                        .tint(.green)
                    }
                }
            } header: {
                Label("\(title) (\(docs.count))", systemImage: icon)
                    .foregroundColor(color)
                    .font(.caption.weight(.semibold))
            }
        }
    }

    private var matchingMatters: [String] {
        guard !query.isEmpty else { return [] }
        let queryLower = query.lowercased()
        var uniqueMatters = Set<String>()
        for doc in results {
            if let m = doc.matter, !m.isEmpty {
                uniqueMatters.insert(m)
            }
        }
        if let allDocs = try? dbManager.fetchAllDocuments() {
            for doc in allDocs {
                if let m = doc.matter, m.lowercased().contains(queryLower) {
                    uniqueMatters.insert(m)
                }
            }
        }
        return Array(uniqueMatters).sorted()
    }

    private func performSearch() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        let currentQuery = query

        Task {
            let folders = (try? dbManager.fetchFolders()) ?? []
            let found: [VaultDocument]
            if mode == .keyword {
                found = (try? dbManager.searchDocuments(query: currentQuery)) ?? []
            } else {
                let embedding = await EmbeddingManager.shared.generateTextEmbedding(from: currentQuery)
                found = (try? dbManager.hybridSearch(query: currentQuery, queryEmbedding: embedding)) ?? []
            }
            await MainActor.run { 
                self.allFolders = folders
                self.results = found
                self.isSearching = false 
            }
        }
    }

    private func markRelevant(_ doc: VaultDocument) {
        let currentQuery = query
        markedIds.insert(doc.id)
        Task {
            await dbManager.markDocumentRelevant(doc.id, forQuery: currentQuery)
            // Re-run search so Rocchio adjustment takes effect immediately
            await MainActor.run { performSearch() }
        }
    }
}

// MARK: - Matter Document List View
struct MatterDocumentListView: View {
    let matterName: String
    @EnvironmentObject var dbManager: DatabaseManager
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var documents: [VaultDocument] = []
    
    var body: some View {
        List(documents) { doc in
            NavigationLink {
                DocumentDetailView(document: doc)
                    .environmentObject(dbManager)
                    .environmentObject(authManager)
            } label: {
                DocumentRow(document: doc)
            }
        }
        .navigationTitle(matterName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadDocuments()
        }
    }
    
    private func loadDocuments() {
        do {
            let all = try dbManager.fetchAllDocuments()
            documents = all.filter { $0.matter == matterName }
        } catch {
            print("❌ Failed to load matter documents: \(error)")
        }
    }
}
