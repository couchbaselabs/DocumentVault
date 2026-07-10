import SwiftUI
import CouchbaseLiteSwift

struct ReportsView: View {
    @EnvironmentObject var dbManager: DatabaseManager
    @EnvironmentObject var authManager: AuthenticationManager
    
    @State private var totalDocs = 0
    @State private var totalFolders = 0
    @State private var totalSizeMB: Double = 0
    @State private var categoryCounts: [String: Int] = [:]
    @State private var matterCounts: [String: Int] = [:]
    
    // Custody logs search
    @State private var searchText = ""
    @State private var custodyEvents: [AggregatedCustodyLog] = []
    @State private var filteredEvents: [AggregatedCustodyLog] = []
    @State private var selectedDoc: VaultDocument? = nil
    
    struct AggregatedCustodyLog: Identifiable, Hashable {
        let id: String
        let document: VaultDocument
        let event: CustodyEvent
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Stat cards
                    HStack(spacing: 12) {
                        statCard(title: "Total Files", value: "\(totalDocs)", systemImage: "doc.on.doc", color: .blue)
                        statCard(title: "Active Matters", value: "\(totalFolders)", systemImage: "folder.badge.gearshape", color: .indigo)
                        statCard(title: "Storage Size", value: String(format: "%.2f MB", totalSizeMB), systemImage: "internaldrive", color: .emerald)
                    }
                    .padding(.horizontal)
                    
                    // Categories
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Category Distribution").font(.headline).padding(.horizontal)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            categoryCard(name: "Legal", count: categoryCounts["legal"] ?? 0, icon: "briefcase", color: .indigo)
                            categoryCard(name: "Financial", count: categoryCounts["financial"] ?? 0, icon: "dollarsign", color: .emerald)
                            categoryCard(name: "HR / Ops", count: categoryCounts["hr"] ?? 0, icon: "person.2", color: .amber)
                            categoryCard(name: "Technical", count: categoryCounts["technical"] ?? 0, icon: "cpu", color: .blue)
                            categoryCard(name: "Media", count: categoryCounts["media"] ?? 0, icon: "play.rectangle", color: .rose)
                            categoryCard(name: "Other", count: categoryCounts["other"] ?? 0, icon: "doc.text", color: .secondary)
                        }
                        .padding(.horizontal)
                    }
                    
                    // Matter breakdown
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Matter File Count").font(.headline).padding(.horizontal)
                        VStack(spacing: 0) {
                            if matterCounts.isEmpty {
                                Text("No active matters found").foregroundColor(.secondary).padding()
                            } else {
                                ForEach(matterCounts.sorted(by: { $0.value > $1.value }), id: \.key) { matter, count in
                                    HStack {
                                        Image(systemName: "briefcase.fill").foregroundColor(.indigo)
                                        Text(matter).font(.subheadline)
                                        Spacer()
                                        Text("\(count) files")
                                            .font(.caption.bold())
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.indigo.opacity(0.1))
                                            .foregroundColor(.indigo)
                                            .clipShape(Capsule())
                                    }
                                    .padding()
                                    Divider()
                                }
                            }
                        }
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }
                    
                    // Custody Log Search
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Search Custody & Audit Logs").font(.headline).padding(.horizontal)
                        
                        // Search bar
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                            TextField("Search by actor, action, or document...", text: $searchText)
                                .textFieldStyle(.plain)
                                .onChange(of: searchText) { _, _ in filterLogs() }
                            if !searchText.isEmpty {
                                Button(action: { searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal)
                        
                        // Event list
                        VStack(spacing: 0) {
                            if filteredEvents.isEmpty {
                                Text("No matching custody events found")
                                    .foregroundColor(.secondary)
                                    .padding()
                            } else {
                                ForEach(filteredEvents.prefix(30), id: \.id) { log in
                                    Button(action: {
                                        selectedDoc = log.document
                                    }) {
                                        HStack(alignment: .top, spacing: 12) {
                                            Image(systemName: log.event.action.systemImage)
                                                .font(.title3)
                                                .foregroundColor(.indigo)
                                                .frame(width: 24, height: 24)
                                                .background(Color.indigo.opacity(0.1))
                                                .clipShape(Circle())
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack {
                                                    Text(log.event.action.displayName)
                                                        .font(.subheadline.bold())
                                                        .foregroundColor(.primary)
                                                    Spacer()
                                                    Text(formatDate(log.event.timestamp))
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                
                                                Text("Actor: \(log.event.actor)")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                
                                                if let notes = log.event.notes, !notes.isEmpty {
                                                    Text(notes)
                                                        .font(.caption)
                                                        .foregroundColor(.indigo)
                                                }
                                                
                                                Text("File: \(log.document.name)")
                                                    .font(.caption.bold())
                                                    .foregroundColor(.accentColor)
                                            }
                                        }
                                        .padding()
                                    }
                                    .buttonStyle(.plain)
                                    Divider()
                                }
                            }
                        }
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                    }
                    
                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("Reports & Audit")
            .onAppear {
                loadReportData()
            }
            .refreshable {
                loadReportData()
            }
            .sheet(item: $selectedDoc) { doc in
                DocumentDetailView(document: doc)
                    .environmentObject(dbManager)
                    .environmentObject(authManager)
            }
        }
    }
    
    // MARK: - Data Load
    
    private func loadReportData() {
        do {
            let allDocs = try dbManager.fetchAllDocuments()
            totalDocs = allDocs.count
            
            // Calculate sizes
            let totalBytes = allDocs.reduce(0) { $0 + $1.size }
            totalSizeMB = Double(totalBytes) / (1024.0 * 1024.0)
            
            // Group by category
            var catGroup: [String: Int] = [:]
            for doc in allDocs {
                let cat = doc.contentCategory ?? "other"
                catGroup[cat, default: 0] += 1
            }
            categoryCounts = catGroup
            
            // Group by matter
            var matGroup: [String: Int] = [:]
            for doc in allDocs {
                if let m = doc.matter, !m.isEmpty {
                    matGroup[m, default: 0] += 1
                }
            }
            matterCounts = matGroup
            totalFolders = matGroup.count
            
            // Aggregate custody events
            var eventsList: [AggregatedCustodyLog] = []
            for doc in allDocs {
                for event in doc.custodyChain {
                    eventsList.append(AggregatedCustodyLog(
                        id: "\(doc.id)_\(event.id)",
                        document: doc,
                        event: event
                    ))
                }
            }
            // Sort by timestamp desc
            eventsList.sort { $0.event.timestamp > $1.event.timestamp }
            custodyEvents = eventsList
            filterLogs()
            
        } catch {
            print("❌ Reports load failed: \(error)")
        }
    }
    
    private func filterLogs() {
        if searchText.isEmpty {
            filteredEvents = custodyEvents
        } else {
            let query = searchText.lowercased()
            filteredEvents = custodyEvents.filter { log in
                log.event.actor.lowercased().contains(query) ||
                log.event.action.displayName.lowercased().contains(query) ||
                (log.event.notes?.lowercased().contains(query) ?? false) ||
                log.document.name.lowercased().contains(query)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    @ViewBuilder
    private func statCard(title: String, value: String, systemImage: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage).foregroundColor(color).font(.headline)
                Spacer()
            }
            Text(value).font(.title3.bold()).foregroundColor(.primary)
            Text(title).font(.caption).foregroundColor(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    @ViewBuilder
    private func categoryCard(name: String, count: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundColor(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.bold()).foregroundColor(.primary)
                Text("\(count) files").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// Colors for visual cards
extension Color {
    static let emerald = Color(red: 16/255, green: 185/255, blue: 129/255)
    static let rose = Color(red: 244/255, green: 63/255, blue: 94/255)
    static let amber = Color(red: 245/255, green: 158/255, blue: 11/255)
}
