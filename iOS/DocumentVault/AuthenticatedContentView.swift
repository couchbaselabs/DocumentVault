import SwiftUI
import CouchbaseLiteSwift

// MARK: - Main Tab Container (post-login)

struct AuthenticatedContentView: View {
    @EnvironmentObject var dbManager: DatabaseManager
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            FolderBrowserView()
                .tabItem { Label("Browse", systemImage: "folder") }
                .tag(0)

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(1)

            ChatView()
                .tabItem { Label("Agent Chat", systemImage: "bubble.left.and.bubble.right") }
                .tag(5)

            UploadView()
                .tabItem { Label("Upload", systemImage: "plus.circle") }
                .tag(2)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.circle") }
                .tag(3)

            ReportsView()
                .tabItem { Label("Reports", systemImage: "chart.bar.doc.horizontal") }
                .tag(4)
                .badge(dbManager.unreadChangesCount)
        }
        .onAppear {
            dbManager.setupIndexes()
        }
        .onChange(of: selectedTab) { newValue in
            if newValue == 4 {
                dbManager.unreadChangesCount = 0
            }
        }
    }
}
