import SwiftUI
import CouchbaseLiteSwift
#if canImport(FoundationModels)
import FoundationModels
#endif

struct ChatView: View {
    @EnvironmentObject var dbManager: DatabaseManager
    @EnvironmentObject var authManager: AuthenticationManager
    
    @State private var messages: [ChatMessage] = [
        ChatMessage(sender: .assistant, text: "Hello! I am your local Document Vault Agent. Ask me anything about your secure matters or case files.")
    ]
    @State private var input = ""
    @State private var isResponding = false
    @State private var selectedDoc: VaultDocument? = nil
    @State private var useRAG = true
    @State private var folders: [Folder] = []
    @State private var selectedFolderId: String? = nil
    
    @AppStorage("AppConfig.llmProvider") private var llmProviderRaw = AppConfig.LLMProvider.appleIntelligence.rawValue
    @AppStorage("AppConfig.openAIEndpoint") private var openAIEndpoint = "https://api.openai.com/v1"
    @AppStorage("AppConfig.openAIKey") private var openAIKey = ""
    @AppStorage("AppConfig.openAIModel") private var openAIModel = "gpt-4o-mini"
    
    private var activeProvider: AppConfig.LLMProvider {
        AppConfig.LLMProvider(rawValue: llmProviderRaw) ?? .appleIntelligence
    }
    
    struct ChatMessage: Identifiable, Hashable {
        let id = UUID()
        let sender: ChatSender
        let text: String
        let timestamp = Date()
        
        enum ChatSender {
            case user
            case assistant
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Agent RAG and Scope Controls
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: activeProvider == .appleIntelligence ? "cpu" : "network")
                            .foregroundColor(.indigo)
                        Text("LLM: \(activeProvider.rawValue)")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Toggle("Couchbase RAG", isOn: $useRAG)
                            .toggleStyle(SwitchToggleStyle(tint: .indigo))
                            .font(.caption.bold())
                            .labelsHidden()
                        Text(useRAG ? "RAG Enabled" : "RAG Disabled")
                            .font(.caption.bold())
                            .foregroundColor(useRAG ? .indigo : .gray)
                    }
                    
                    if useRAG {
                        HStack {
                            Text("Context Scope:")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            
                            Picker("Scope", selection: $selectedFolderId) {
                                Text("Global (All Folders)").tag(nil as String?)
                                ForEach(folders, id: \.id) { folder in
                                    Text(folder.name).tag(folder.id as String?)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.indigo)
                            .labelsHidden()
                            
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(Color(.systemGray6))
                .animation(.easeInOut, value: useRAG)
                
                // Messages List
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(messages) { message in
                                bubble(for: message)
                            }
                            if isResponding {
                                HStack {
                                    ProgressView()
                                        .padding()
                                    Spacer()
                                }
                                .id("thinking")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
                
                Divider()
                
                // Input Bar
                HStack(spacing: 12) {
                    TextField("Ask the document agent...", text: $input)
                        .padding(10)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .onSubmit { sendMessage() }
                        .disabled(isResponding)
                    
                    Button(action: sendMessage) {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(.white)
                            .padding(10)
                            .background(input.isEmpty || isResponding ? Color.gray : Color.indigo)
                            .clipShape(Circle())
                    }
                    .disabled(input.isEmpty || isResponding)
                }
                .padding()
            }
            .navigationTitle("Vault Agent Chat")
            .onOpenURL { url in
                if url.scheme == "vault", url.host == "doc" {
                    let docId = url.lastPathComponent
                    if let doc = try? dbManager.fetchDocument(id: docId) {
                        selectedDoc = doc
                    }
                }
            }
            .sheet(item: $selectedDoc) { doc in
                NavigationStack {
                    DocumentDetailView(document: doc)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") {
                                    selectedDoc = nil
                                }
                            }
                        }
                }
            }
            .onAppear {
                loadFolders()
            }
            .onReceive(NotificationCenter.default.publisher(for: .vaultFoldersChanged)) { _ in
                loadFolders()
            }
        }
    }
    
    // MARK: - Bubble UI
    
    @ViewBuilder
    private func bubble(for msg: ChatMessage) -> some View {
        HStack {
            if msg.sender == .user { Spacer() }
            
            let displayText = msg.sender == .assistant ? formatAssistantResponse(msg.text) : msg.text
            Text(markdownString(displayText))
                .padding(12)
                .background(msg.sender == .user ? Color.indigo : Color(.systemGray5))
                .foregroundColor(msg.sender == .user ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .textSelection(.enabled)
                .frame(maxWidth: 550, alignment: msg.sender == .user ? .trailing : .leading)
            
            if msg.sender == .assistant { Spacer() }
        }
    }

    private func formatAssistantResponse(_ text: String) -> String {
        var formatted = text
        
        let headers = [
            "Summary of Findings",
            "Relevant Documents",
            "Logical Details / Fact Synthesis",
            "Metadata/ Custody Details",
            "Metadata/Custody Details",
            "Audit Trace Details",
            "Last Modified",
            "Modified By",
            "Actions"
        ]
        
        for header in headers {
            let pattern = "(\\*\\*)?\\s*\(header)\\s*(\\*\\*)?\\s*(:)?\\s*"
            
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(formatted.startIndex..<formatted.endIndex, in: formatted)
                formatted = regex.stringByReplacingMatches(
                    in: formatted,
                    options: [],
                    range: range,
                    withTemplate: "\n\n**\(header)**:\n"
                )
            }
        }
        
        // Normalize paragraph breaks vs line breaks to prevent SwiftUI from collapsing lists
        formatted = formatted.replacingOccurrences(of: "\n\n", with: "||P_BREAK||")
        formatted = formatted.replacingOccurrences(of: "\n", with: "  \n")
        formatted = formatted.replacingOccurrences(of: "||P_BREAK||", with: "\n\n")
        
        return formatted.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func markdownString(_ text: String) -> AttributedString {
        do {
            return try AttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full))
        } catch {
            return AttributedString(text)
        }
    }
    
    // MARK: - Send Message & Agent Execution
    
    private func sendMessage() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        input = ""
        messages.append(ChatMessage(sender: .user, text: text))
        isResponding = true
        
        Task {
            // 1. Generate response using selected LLM Provider
            let response: String
            switch activeProvider {
            case .appleIntelligence:
                // Exclude raw snippet to prevent Apple Intelligence safety refusals and use compact context
                let context = await buildRAGContext(for: text, includeSnippets: false, isAppleIntelligence: true)
                response = await generateAppleIntelligenceResponse(prompt: text, context: context)
            case .openAI:
                // Include raw snippet for more details on open endpoints
                let context = await buildRAGContext(for: text, includeSnippets: true, isAppleIntelligence: false)
                response = await generateOpenAIResponse(prompt: text, context: context)
            }
            
            NSLog("🤖 Raw Assistant Response:\n%@", response)
            
            await MainActor.run {
                messages.append(ChatMessage(sender: .assistant, text: response))
                isResponding = false
            }
        }
    }
    
    // MARK: - RAG Context Assembly
    
    private func buildRAGContext(for userPrompt: String, includeSnippets: Bool, isAppleIntelligence: Bool) async -> String {
        guard useRAG else {
            print("🚫 RAG Disabled: Skipping Couchbase Lite context injection")
            return ""
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        
        var contextStr = ""
        
        // 1. Fetch recently modified files for metadata/audit queries (fewer for local device memory constraints)
        let recentLimit = isAppleIntelligence ? 2 : 5
        let recentDocs = (try? dbManager.fetchRecentlyModified(folderId: selectedFolderId, limit: recentLimit)) ?? []
        if !recentDocs.isEmpty {
            contextStr += "Recently modified files/activity in the vault:\n"
            for doc in recentDocs {
                let dateStr = formatter.string(from: doc.updatedAt)
                let actor = doc.author ?? doc.ownerId
                contextStr += "- File: \(doc.name) (Format: \(doc.fileExtension.uppercased())), ID: \(doc.id), Type: \(doc.docType), Last Modified: \(dateStr), Modified By: \(actor), Status: \(doc.status.rawValue), Matter: \(doc.matter ?? "None")\n"
            }
            contextStr += "\n"
        }
        
        // Generate embedding for query (optional)
        let queryEmbedding = await EmbeddingManager.shared.generateTextEmbedding(from: userPrompt)
        
        // Hybrid search matches (FTS + Vector) (limit to 1 match for local device context constraints)
        let relatedLimit = isAppleIntelligence ? 1 : 3
        let relatedDocs = (try? dbManager.hybridSearch(query: userPrompt, queryEmbedding: queryEmbedding, folderId: selectedFolderId, limit: relatedLimit)) ?? []
        if !relatedDocs.isEmpty {
            contextStr += "Matching files from the secure database relevant to the user query:\n\n"
            for doc in relatedDocs {
                contextStr += "- File Name: \(doc.name) (Format: \(doc.fileExtension.uppercased())), ID: \(doc.id)\n"
                contextStr += "  Document Type: \(doc.docType)\n"
                if let m = doc.matter { contextStr += "  Matter: \(m)\n" }
                if let c = doc.client { contextStr += "  Client: \(c)\n" }
                if let s = doc.summary { contextStr += "  Summary: \(s)\n" }
                contextStr += "  Last Modified: \(formatter.string(from: doc.updatedAt)) by \(doc.author ?? doc.ownerId)\n"
                if !isAppleIntelligence && !doc.custodyChain.isEmpty {
                    contextStr += "  Custody History:\n"
                    for event in doc.custodyChain.suffix(3) {
                        contextStr += "    - [\(formatter.string(from: event.timestamp))] \(event.action.rawValue) by \(event.actor) (Details: \(event.notes ?? "None"))\n"
                    }
                }
                if includeSnippets, let text = doc.textContent {
                    let snippet = String(text.prefix(600)).replacingOccurrences(of: "\n", with: " ")
                    contextStr += "  Snippet: \(snippet)...\n"
                }
                contextStr += "\n"
            }
        }
        return contextStr
    }

    private func loadFolders() {
        folders = (try? dbManager.fetchAllFolders()) ?? []
    }
    
    // MARK: - Apple Intelligence Response
    
    private func generateAppleIntelligenceResponse(prompt: String, context: String) async -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                return "On-device Apple Intelligence model is still downloading or not available on this device. Please check Settings → Apple Intelligence."
            }
            
            let systemInstruction = """
            You are an elite legal assistant and paralegal. Your role is to read, analyze, and synthesize secure database files to prepare summaries, briefs, and reports.
            
            Reference the provided local document database context:
            \(context)
            
            Guidelines:
            1. Act like a highly competent legal professional. Be precise, formal, and objective.
            2. For search questions, you MUST provide a well-structured brief. Separate each section with exactly TWO newlines (a blank line) so they render correctly in markdown:
               
               **Summary of Findings**
               [Provide the summary of findings here]
               
               **Relevant Documents**
               - [Document Name](vault://doc/document_id) (Format: PDF, Author: Judge/Court/etc.)
               - [Another Document Name](vault://doc/another_id) (Format: DOCX, Author: Presiding Court/etc.)
               
               **Logical Details / Fact Synthesis**
               [Provide logical details here]
               
               **Audit Trace Details**
               - **Last Modified**: [date/time]
               - **Modified By**: [actor name]
               - **Actions**: [actions taken]
            3. For metadata/custody questions, provide the exact audit trace details formatted as bullet points separated by double newlines.
            4. Stick strictly to facts in the context. If the database does not contain the answer, state that clearly.
            5. When referencing any document, you MUST include a clickable in-app markdown link to it using the exact format: [Document Name](vault://doc/document_id). Example: [Broderick Complaint](vault://doc/Doc_1234567890). This is critical so the user can click directly to view the document.
            """
            
            let fullPrompt = "\(systemInstruction)\n\nUser Question: \(prompt)"
            
            do {
                let session = LanguageModelSession()
                let response = try await session.respond(to: fullPrompt)
                return response.content
            } catch {
                return "On-device Apple Intelligence generation failed: \(error.localizedDescription)"
            }
        } else {
            return "Apple Intelligence is only available on iOS 26+ or macOS 17+."
        }
        #else
        return "Apple Intelligence framework not loaded in this environment."
        #endif
    }
    
    // MARK: - OpenAI / Custom Endpoint Response
    
    private func generateOpenAIResponse(prompt: String, context: String) async -> String {
        let endpoint = AppConfig.openAIEndpoint.trimmingCharacters(in: .whitespaces)
        let key = AppConfig.openAIKey.trimmingCharacters(in: .whitespaces)
        
        guard let url = URL(string: "\(endpoint)/chat/completions") else {
            return "Invalid API Endpoint configured in LLM settings."
        }
        
        let systemPrompt = """
        You are an elite legal assistant and paralegal. Your role is to read, analyze, and synthesize secure database files to prepare summaries, briefs, and reports.
        
        You have access to the following tools which you can invoke to interact with the local database:
        - `publish_document(documentId)`: Publishes a document. Call this when the user asks to publish, release, or finalize a document.
        - `add_annotation(documentId, note)`: Adds an annotation/note to a document. Call this when the user asks to add a note, comment, or annotation.
        
        Reference the provided local document database context:
        \(context)
        
        Guidelines:
        1. Act like a highly competent legal professional. Be precise, formal, and objective.
        2. When a user asks you to perform an action (like publishing or writing a note), you MUST invoke the corresponding tool.
        3. For search questions, you MUST provide a well-structured brief. Separate each section with exactly TWO newlines (a blank line) so they render correctly in markdown:
           
           **Summary of Findings**
           [Provide the summary of findings here]
           
           **Relevant Documents**
           - [Document Name](vault://doc/document_id) (Format: PDF, Author: Judge/Court/etc.)
           - [Another Document Name](vault://doc/another_id) (Format: DOCX, Author: Presiding Court/etc.)
           
           **Logical Details / Fact Synthesis**
           [Provide logical details here]
           
           **Audit Trace Details**
           - **Last Modified**: [date/time]
           - **Modified By**: [actor name]
           - **Actions**: [actions taken]
        4. When referencing any document, you MUST include a clickable in-app markdown link to it using the exact format: [Document Name](vault://doc/document_id). Example: [Broderick Complaint](vault://doc/Doc_1234567890). This is critical so the user can click directly to view the document.
        """
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        
        let messagesPayload: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": prompt]
        ]
        
        let publishTool: [String: Any] = [
            "type": "function",
            "function": [
                "name": "publish_document",
                "description": "Changes the status of a document to 'published'. Use this when the user asks to publish or release a document.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "documentId": [
                            "type": "string",
                            "description": "The exact ID of the document to publish (e.g. Doc_06A0A42E-29ED-4A17-A663-C8FC26589D36)."
                        ]
                    ],
                    "required": ["documentId"]
                ]
            ]
        ]
        
        let annotateTool: [String: Any] = [
            "type": "function",
            "function": [
                "name": "add_annotation",
                "description": "Adds a note/annotation comment to a document. Use this when the user asks to add a note, comment, or annotation to a document.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "documentId": [
                            "type": "string",
                            "description": "The exact ID of the document to annotate."
                        ],
                        "note": [
                            "type": "string",
                            "description": "The content of the note or comment to add."
                        ]
                    ],
                    "required": ["documentId", "note"]
                ]
            ]
        ]
        
        let payload: [String: Any] = [
            "model": AppConfig.openAIModel,
            "messages": messagesPayload,
            "temperature": 0.3,
            "tools": [publishTool, annotateTool],
            "tool_choice": "auto"
        ]
        
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return "Failed to serialize API request payload."
        }
        request.httpBody = body
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let errorStr = String(data: data, encoding: .utf8) ?? "unknown error"
                return "API server returned error code \(status): \(errorStr)"
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any] else {
                return "Failed to parse completion payload from API response."
            }
            
            // Check for tool/function calls generated by LLM
            if let toolCalls = message["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
                var toolExecutionLog = ""
                for toolCall in toolCalls {
                    guard let function = toolCall["function"] as? [String: Any],
                          let name = function["name"] as? String,
                          let argumentsStr = function["arguments"] as? String,
                          let argData = argumentsStr.data(using: .utf8),
                          let args = try? JSONSerialization.jsonObject(with: argData) as? [String: Any] else { continue }
                    
                    if name == "publish_document", let docId = args["documentId"] as? String {
                        if var doc = try? dbManager.fetchDocument(id: docId) {
                            doc.status = .published
                            doc.updatedAt = Date()
                            doc.custodyChain.append(CustodyEvent(
                                actor: "AI Agent",
                                action: .statusChanged,
                                notes: "Document status updated to Published via RAG tool call."
                            ))
                            try? dbManager.saveDocument(doc)
                            toolExecutionLog += "⚙️ **Tool Executed**: Successfully published [\(doc.name)](vault://doc/\(docId)).\n\n"
                        } else {
                            toolExecutionLog += "⚠️ **Tool Error**: Could not locate document ID \(docId).\n\n"
                        }
                    } else if name == "add_annotation",
                              let docId = args["documentId"] as? String,
                              let note = args["note"] as? String {
                        if let doc = try? dbManager.fetchDocument(id: docId) {
                            let annotation = Annotation(
                                id: "Ann_Agent_\(UUID().uuidString.prefix(8).lowercased())",
                                documentId: docId,
                                tenantId: AppConfig.currentTenantId,
                                authorId: "AI Agent",
                                authorEmail: "ai-agent@acmecorp.com",
                                body: note
                            )
                            try? dbManager.saveAnnotation(annotation)
                            toolExecutionLog += "⚙️ **Tool Executed**: Added case note to [\(doc.name)](vault://doc/\(docId)): \"*\(note)*\".\n\n"
                        } else {
                            toolExecutionLog += "⚠️ **Tool Error**: Could not locate document ID \(docId) to annotate.\n\n"
                        }
                    }
                }
                
                return toolExecutionLog.isEmpty ? "AI Agent executed tool calls, but no database changes occurred." : toolExecutionLog
            }
            
            // Standard conversational response
            if let text = message["content"] as? String {
                return text
            }
            
            return "No response received from model."
        } catch {
            return "Network API request failed: \(error.localizedDescription)"
        }
    }
}
