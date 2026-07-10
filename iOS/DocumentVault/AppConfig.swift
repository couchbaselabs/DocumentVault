import Foundation

struct AppConfig {

    // MARK: - Tenant (set after login, persisted across launches)

    private static let persistedTenantKey   = "AppConfig.tenantId"
    private static let persistedUsernameKey = "AppConfig.username"

    static var currentTenantId: String = {
        UserDefaults.standard.string(forKey: persistedTenantKey) ?? ""
    }() {
        didSet { UserDefaults.standard.set(currentTenantId, forKey: persistedTenantKey) }
    }

    static var currentUsername: String = {
        UserDefaults.standard.string(forKey: persistedUsernameKey) ?? ""
    }() {
        didSet { UserDefaults.standard.set(currentUsername, forKey: persistedUsernameKey) }
    }

    // MARK: - Tenant Resolution

    /// Derives a tenant ID from an email domain.
    /// Returns nil for public mail providers — those users must pick an org manually.
    static func tenantId(from email: String) -> String? {
        let parts = email.lowercased().split(separator: "@")
        guard parts.count == 2 else { return nil }
        let domain = String(parts[1])
        let publicDomains: Set<String> = [
            "gmail.com", "yahoo.com", "outlook.com",
            "hotmail.com", "icloud.com", "me.com", "mac.com"
        ]
        guard !publicDomains.contains(domain) else { return nil }
        // "acme-corp.com" → "acme-corp"
        return domain.components(separatedBy: ".").first
    }

    // MARK: - Capella App Services (ENV / Info.plist driven)

    private static func configValue(for key: String) -> String {
        ProcessInfo.processInfo.environment[key]
            ?? (Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "")
    }

    static var baseURL: String      { configValue(for: "CBL_BASE_URL") }
    static var password: String     { configValue(for: "CBL_PASSWORD") }
    static var username: String     { currentUsername }

    static var syncGatewayURL: String {
        "\(baseURL)/docvault-\(currentTenantId)"
    }

    // MARK: - Database

    static let databaseName = "DocumentVaultDB"

    static var scopeName: String {
        currentTenantId.isEmpty ? "_default" : currentTenantId
    }

    // MARK: - Collection Names

    static let documentsCollection   = "documents"
    static let foldersCollection     = "folders"
    static let annotationsCollection = "annotations"
    static let profileCollection     = "profile"
    static let sendersCollection     = "senders"
    static let threadsCollection     = "threads"

    static var allCollections: [String] {
        [documentsCollection, foldersCollection, annotationsCollection,
         profileCollection, sendersCollection, threadsCollection]
    }

    // MARK: - Sync

    static let syncHeartbeat: UInt16       = 60
    static let syncMaxAttempts: Int        = 10
    static let syncMaxAttemptWaitTime: TimeInterval = 300
    static let syncContinuous: Bool        = true
    static let syncAllowBackground: Bool   = true

    // MARK: - Feature Flags

    static let enableAppServicesSync: Bool = true
    static let enableP2PSync: Bool         = false  // Phase 2

    // MARK: - Debug

    static let debugLogging: Bool = true

    static func printConfiguration() {
        print("📋 === DocumentVault Config ===")
        print("📋 Tenant:   \(currentTenantId)")
        print("📋 User:     \(username)")
        print("📋 Sync URL: \(syncGatewayURL)")
        print("📋 DB:       \(databaseName)  Scope: \(scopeName)")
        print("📋 ==============================")
    }

    // MARK: - LLM Config (Admins can toggle and configure)
    
    enum LLMProvider: String, CaseIterable, Identifiable {
        case appleIntelligence = "Apple Intelligence (Local)"
        case openAI = "OpenAI / Custom Endpoint"
        
        var id: String { self.rawValue }
    }
    
    private static let llmProviderKey = "AppConfig.llmProvider"
    private static let openAIEndpointKey = "AppConfig.openAIEndpoint"
    private static let openAIKeyKey = "AppConfig.openAIKey"
    
    static var llmProvider: LLMProvider {
        get {
            guard let raw = UserDefaults.standard.string(forKey: llmProviderKey),
                  let val = LLMProvider(rawValue: raw) else { return .appleIntelligence }
            return val
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: llmProviderKey)
        }
    }
    
    static var openAIEndpoint: String {
        get { UserDefaults.standard.string(forKey: openAIEndpointKey) ?? "https://api.openai.com/v1" }
        set { UserDefaults.standard.set(newValue, forKey: openAIEndpointKey) }
    }
    
    static var openAIKey: String {
        get { UserDefaults.standard.string(forKey: openAIKeyKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: openAIKeyKey) }
    }
    
    private static let openAIModelKey = "AppConfig.openAIModel"
    static var openAIModel: String {
        get { UserDefaults.standard.string(forKey: openAIModelKey) ?? "gpt-4o-mini" }
        set { UserDefaults.standard.set(newValue, forKey: openAIModelKey) }
    }
}
