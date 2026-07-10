import Foundation
import FoundationModels

// MARK: - Document Analysis (structured output for Foundation Models)

@available(iOS 26, *)
@Generable
struct DocumentAnalysis {
    @Guide(description: "A highly detailed summary of at least 6-8 sentences, comprehensively capturing key facts, litigation parties, corporate entities, legal/financial allegations, and main outcomes")
    var summary: String

    @Guide(description: "5-10 lowercase keyword tags representing topics, entities, themes, or domain terms found in the document")
    var topics: [String]

    @Guide(description: "Primary content category — choose one: legal, financial, medical, technical, personal, correspondence, media, research, other")
    var category: String

    @Guide(description: "The author, Judge, Court, Clerk, preparing attorney, or preparing entity of the document, if identifiable. Otherwise empty.")
    var author: String

    @Guide(description: "The type of document (e.g., Complaint, Court Order, Letter, Audit Report, Contract, Financial Statement, etc.), if identifiable. Otherwise empty.")
    var docType: String
}

// MARK: - Document Summary Service
// Uses Apple Foundation Models (on-device, iOS 26+) to generate a structured
// summary, topic tags, and category for any ingested document.
// Falls back to an extractive summary on unsupported devices.

actor DocumentSummaryService {
    static let shared = DocumentSummaryService()
    private init() {}

    // MARK: - Analyze

    /// Returns a summary, topics, and category for the given content.
    /// - Parameters:
    ///   - text: Raw extracted text (transcript, OCR output, etc.)
    ///   - name: Original file name — helps the model infer context
    ///   - mimeType: e.g. "application/pdf", "audio/mp4"
    func analyze(text: String, name: String, mimeType: String) async -> (summary: String, topics: [String], category: String, author: String?, docType: String?) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ("", [], "other", nil, nil)
        }

        if AppConfig.llmProvider == .openAI {
            if let result = await openAIAnalysis(text: text, name: name, mimeType: mimeType) {
                return result
            }
        } else if #available(iOS 26, *) {
            if let result = await foundationModelsAnalysis(text: text, name: name, mimeType: mimeType) {
                return result
            }
        }

        // Fallback: smart extractive summary + legal topics fallback
        let fallbackSummary = extractiveSummary(from: text, name: name)
        
        var fallbackTopics: [String] = []
        let lowerText = text.lowercased()
        let legalKeywords = ["pricewaterhousecoopers", "pwc", "negligence", "malpractice", "audit", "securities", "whistleblower", "jurisdiction", "liability", "judgment", "opinion", "court"]
        for word in legalKeywords {
            if lowerText.contains(word) {
                fallbackTopics.append(word == "pricewaterhousecoopers" ? "PwC" : word.capitalized)
            }
        }
        
        let isLegal = !fallbackTopics.isEmpty || name.lowercased().contains("pwc") || name.lowercased().contains("v_") || name.lowercased().contains("v.")
        let category = isLegal ? "legal" : "other"
        
        // Fallback: simple heuristic docType & author extraction
        var extractedDocType: String? = nil
        if lowerText.contains("order") && (lowerText.contains("it is ordered") || lowerText.contains("adjudged")) {
            extractedDocType = "Court Order"
        } else if lowerText.contains("complaint") {
            extractedDocType = "Complaint"
        } else if lowerText.contains("audit report") || (lowerText.contains("independent auditor") && lowerText.contains("report")) {
            extractedDocType = "Audit Report"
        } else if lowerText.contains("agreement") || lowerText.contains("contract") {
            extractedDocType = "Agreement"
        } else if lowerText.contains("email") || (lowerText.contains("from:") && lowerText.contains("to:") && lowerText.contains("subject:")) {
            extractedDocType = "Email"
        }
        
        var extractedAuthor: String? = nil
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for line in lines.prefix(40) {
            let lowerLine = line.lowercased()
            if lowerLine.contains("prepared by") || lowerLine.hasPrefix("by:") {
                let cleaned = line.replacingOccurrences(of: "prepared by:", with: "", options: .caseInsensitive, range: nil)
                    .replacingOccurrences(of: "prepared by", with: "", options: .caseInsensitive, range: nil)
                    .replacingOccurrences(of: "by:", with: "", options: .caseInsensitive, range: nil)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    extractedAuthor = cleaned
                    break
                }
            }
        }
        
        if fallbackSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if mimeType.hasPrefix("image/") || mimeType.hasPrefix("video/") {
                let cleanedText = text.replacingOccurrences(of: "Visual labels:", with: "")
                let tagsList = cleanedText.components(separatedBy: .whitespacesAndNewlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                let summary = "Visual media asset named '\(name)' containing: \(tagsList)."
                return (summary, [], "media", extractedAuthor, extractedDocType)
            } else {
                let summary = "Content for '\(name)': \(text.prefix(200))."
                return (summary, fallbackTopics, category, extractedAuthor, extractedDocType)
            }
        }
        return (fallbackSummary, fallbackTopics, category, extractedAuthor, extractedDocType)
    }

    // MARK: - Foundation Models Path

    @available(iOS 26, *)
    private func foundationModelsAnalysis(
        text: String,
        name: String,
        mimeType: String
    ) async -> (summary: String, topics: [String], category: String, author: String?, docType: String?)? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            print("⚠️ DocumentSummaryService: Apple Intelligence not available on this device")
            return nil
        }

        // Truncate to ~3 000 chars — stays well within the model's context window
        let truncated = String(text.prefix(3_000))
        let prompt = """
        You are analyzing a document for a secure document vault application.
        File name: \(name)
        File type: \(mimeType)

        Document content:
        \(truncated)

        Provide a structured analysis of this document.
        """

        do {
            let session  = LanguageModelSession()
            let response = try await session.respond(to: prompt, generating: DocumentAnalysis.self)
            let analysis = response.content
            return (analysis.summary, analysis.topics, analysis.category, analysis.author.isEmpty ? nil : analysis.author, analysis.docType.isEmpty ? nil : analysis.docType)
        } catch {
            // Code 1026 = model assets still downloading / initializing
            let nsError = error as NSError
            let isAssetLoading = nsError.code == 1026 ||
                nsError.underlyingErrors.contains { ($0 as NSError).code == 1026 } ||
                (nsError.userInfo["NSMultipleUnderlyingErrors"] as? [NSError])?.contains { $0.code == 1026 } == true
            
            if isAssetLoading {
                print("⏳ DocumentSummaryService: Apple Intelligence model assets still initializing — will retry on next document")
            } else {
                print("⚠️ DocumentSummaryService: Foundation Models error — \(error)")
            }
            return nil
        }
    }

    // MARK: - OpenAI / Custom Endpoint Path
    
    private func openAIAnalysis(
        text: String,
        name: String,
        mimeType: String
    ) async -> (summary: String, topics: [String], category: String, author: String?, docType: String?)? {
        let endpoint = AppConfig.openAIEndpoint.trimmingCharacters(in: .whitespaces)
        let key = AppConfig.openAIKey.trimmingCharacters(in: .whitespaces)
        let modelName = AppConfig.openAIModel.trimmingCharacters(in: .whitespaces)
        
        guard let url = URL(string: "\(endpoint)/chat/completions") else {
            print("⚠️ DocumentSummaryService: Invalid custom LLM endpoint configured")
            return nil
        }
        
        let truncated = String(text.prefix(3_000))
        let prompt = """
        Analyze this document for a secure vault application.
        File Name: \(name)
        Mime Type: \(mimeType)
        Content:
        \(truncated)
        
        You must return a structured JSON object strictly matching this format:
        {
          "summary": "A highly detailed summary of at least 6-8 sentences comprehensively detailing the key facts, litigation parties, corporate clients, specific legal/financial allegations, and main outcomes of the document. Do not truncate.",
          "topics": ["lowercase-topic-1", "lowercase-topic-2"],
          "category": "legal, financial, medical, technical, or other",
          "author": "The Judge, Court, Clerk, preparing attorney, company, or authoring entity of the document, if identifiable. Otherwise null.",
          "docType": "The specific document type (e.g., Complaint, Court Order, Letter, Audit Report, Contract, etc.), if identifiable. Otherwise null."
        }
        Do not add any explanations or markdown backticks, return only raw JSON.
        """
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        
        let messages = [
            ["role": "system", "content": "You are a professional legal and document analysis AI assistant. Always output valid raw JSON matching the requested schema. Do not output markdown code blocks."],
            ["role": "user", "content": prompt]
        ]
        
        let payload: [String: Any] = [
            "model": modelName,
            "messages": messages,
            "temperature": 0.2
        ]
        
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        request.httpBody = body
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                print("⚠️ DocumentSummaryService: Custom LLM API returned status \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return nil
            }
            
            if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = jsonObject["choices"] as? [[String: Any]],
               let first = choices.first,
               let message = first["message"] as? [String: Any],
               var content = message["content"] as? String {
                
                content = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if content.hasPrefix("```") {
                    content = content.components(separatedBy: "\n")
                        .filter { !$0.hasPrefix("```") }
                        .joined(separator: "\n")
                }
                
                if let jsonData = content.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let summary = dict["summary"] as? String,
                   let topics = dict["topics"] as? [String],
                   let category = dict["category"] as? String {
                    let author = dict["author"] as? String
                    let docType = dict["docType"] as? String
                    return (summary, topics, category, author, docType)
                }
            }
            print("⚠️ DocumentSummaryService: Failed to parse structured JSON from custom LLM response")
            return nil
        } catch {
            print("⚠️ DocumentSummaryService: Custom LLM request failed: \(error)")
            return nil
        }
    }

    // MARK: - Extractive Fallback

    private func extractiveSummary(from text: String, name: String, maxSentences: Int = 8) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var parties: String? = nil
        for line in lines.prefix(40) {
            let lower = line.lowercased()
            if lower.contains(" v. ") || lower.contains(" v ") || lower.contains(" vs. ") || lower.contains(" vs ") {
                parties = line
                break
            }
        }
        
        var court: String? = nil
        for line in lines.prefix(40) {
            let lower = line.lowercased()
            if lower.contains("court") || lower.contains("district") || lower.contains("appeals") {
                court = line
                break
            }
        }
        
        var caseNo: String? = nil
        for line in lines.prefix(40) {
            let lower = line.lowercased()
            if lower.contains("case no") || lower.contains("no.") || lower.contains("cause no") {
                caseNo = line
                break
            }
        }
        
        var summaryPrefix = "Legal court document relating to public litigation"
        if let p = parties {
            summaryPrefix += " in the matter of \(p)"
        } else {
            let cleanName = name.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".pdf", with: "")
            summaryPrefix += " regarding \(cleanName)"
        }
        
        if let c = court {
            summaryPrefix += ", filed in the \(c)"
        }
        
        if let cn = caseNo {
            summaryPrefix += " (\(cn))"
        }
        
        summaryPrefix += "."
        
        let cleanText = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        
        let sentences = cleanText
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 25 && !$0.contains("Reporter") && !$0.contains("v.") && !$0.contains("vs.") }
        
        let contentSummary = sentences.prefix(maxSentences).joined(separator: ". ")
        
        return "\(summaryPrefix) Summary: \(contentSummary)."
    }
}
