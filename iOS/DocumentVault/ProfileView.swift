import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var dbManager: DatabaseManager

    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isSeeding = false
    @State private var isSimulatingEmail = false
    @State private var llmProvider = AppConfig.llmProvider
    @State private var openAIEndpoint = AppConfig.openAIEndpoint
    @State private var openAIKey = AppConfig.openAIKey
    @State private var openAIModel = AppConfig.openAIModel
    @State private var availableModels: [String] = []
    @State private var isFetchingModels = false

    var body: some View {
        NavigationStack {
            List {
                // User section
                Section {
                    if let user = authManager.currentUser {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 52, height: 52)
                                Text(String(user.displayName.prefix(1)).uppercased())
                                    .font(.title2.bold()).foregroundColor(.accentColor)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(user.displayName).font(.headline)
                                  Text(user.email).font(.caption).foregroundColor(.secondary)
                                Text("\(user.role.displayName) · \(user.tenantId)")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Sync
                Section("Synchronisation") {
                    SyncStatusView()
                        .environmentObject(dbManager)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }

                // LLM Configuration
                Section("LLM & Agent Configuration") {
                    Picker("Provider", selection: $llmProvider) {
                        ForEach(AppConfig.LLMProvider.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .onChange(of: llmProvider) { _, newValue in
                        AppConfig.llmProvider = newValue
                    }
                    
                    if llmProvider == .openAI {
                        TextField("API Endpoint", text: $openAIEndpoint)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: openAIEndpoint) { _, newValue in
                                AppConfig.openAIEndpoint = newValue
                                loadModels()
                            }
                        
                        SecureField("API Key / Token", text: $openAIKey)
                            .onChange(of: openAIKey) { _, newValue in
                                AppConfig.openAIKey = newValue
                                loadModels()
                            }
                        
                        if isFetchingModels {
                            HStack {
                                Text("Fetching available models...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                ProgressView()
                            }
                        } else if !availableModels.isEmpty {
                            Picker("Model Name", selection: $openAIModel) {
                                ForEach(availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: openAIModel) { _, newValue in
                                AppConfig.openAIModel = newValue
                            }
                        } else {
                            TextField("Model Name", text: $openAIModel)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .onChange(of: openAIModel) { _, newValue in
                                    AppConfig.openAIModel = newValue
                                }
                        }
                    }
                }

                // Developer Tools
                Section("Developer Tools") {
                    Button(action: {
                        isSeeding = true
                        Task {
                            do {
                                let result = try await dbManager.seedSampleData()
                                alertMessage = "Seeded \(result.folders) folders and \(result.documents) documents successfully!"
                                showAlert = true
                            } catch {
                                alertMessage = "Failed to seed: \(error.localizedDescription)"
                                showAlert = true
                            }
                            isSeeding = false
                        }
                    }) {
                        HStack {
                            Label("Seed Sample Corporate Data", systemImage: "square.and.arrow.down.on.square")
                            if isSeeding {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isSeeding)

                    Button(action: {
                        isSimulatingEmail = true
                        Task {
                            do {
                                try await dbManager.simulateIncomingEmail()
                                alertMessage = "Simulated incoming email from Jane Doe! Saved as a new .eml document and linked to Matter AN-01 (triggering automatic re-vectorization and re-summarization)."
                                showAlert = true
                            } catch {
                                alertMessage = "Failed to simulate email: \(error.localizedDescription)"
                                showAlert = true
                            }
                            isSimulatingEmail = false
                        }
                    }) {
                        HStack {
                            Label("Simulate Email from Jane (Matter AN-01)", systemImage: "envelope.badge")
                            if isSimulatingEmail {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isSimulatingEmail)

                    Button(role: .destructive, action: {
                        do {
                            try dbManager.resetDatabase()
                            alertMessage = "Local database completely reset and re-initialized!"
                            showAlert = true
                        } catch {
                            alertMessage = "Failed to reset database: \(error.localizedDescription)"
                            showAlert = true
                        }
                    }) {
                        Label("Reset Local Database", systemImage: "trash")
                    }
                }

                // App info
                Section("App") {
                    LabeledContent("Database", value: AppConfig.databaseName)
                    LabeledContent("Scope", value: AppConfig.scopeName)
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                }

                // Sign out
                Section {
                    Button(role: .destructive) {
                        authManager.logout()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Profile")
            .alert("Data Seeder", isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                if llmProvider == .openAI {
                    loadModels()
                }
            }
        }
    }

    private func loadModels() {
        let endpoint = openAIEndpoint.trimmingCharacters(in: .whitespaces)
        let key = openAIKey.trimmingCharacters(in: .whitespaces)
        
        guard !endpoint.isEmpty else { return }
        
        isFetchingModels = true
        Task {
            guard let url = URL(string: "\(endpoint)/models") else {
                await MainActor.run { isFetchingModels = false }
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !key.isEmpty {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let dataArray = json["data"] as? [[String: Any]] {
                    let ids = dataArray.compactMap { $0["id"] as? String }.sorted()
                    await MainActor.run {
                        self.availableModels = ids
                        self.isFetchingModels = false
                        if !ids.isEmpty && !ids.contains(openAIModel) {
                            openAIModel = ids.first!
                            AppConfig.openAIModel = ids.first!
                        }
                    }
                } else {
                    await MainActor.run {
                        self.availableModels = []
                        self.isFetchingModels = false
                    }
                }
            } catch {
                print("⚠️ Error loading models: \(error)")
                await MainActor.run {
                    self.availableModels = []
                    self.isFetchingModels = false
                }
            }
        }
    }
}
