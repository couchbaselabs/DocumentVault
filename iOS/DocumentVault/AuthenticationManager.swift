import Foundation
import SwiftUI
import CouchbaseLiteSwift

// MARK: - Session User

struct SessionUser {
    let email: String
    let displayName: String
    let role: UserRole
    let tenantId: String
}

// MARK: - Authentication Manager

class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: SessionUser?
    @Published var loginError: String?
    @Published var isLoggingIn = false

    private var authDB: Database?
    private let sessionDocID = "vault_session"

    weak var databaseManager: DatabaseManager?

    init() {
        openAuthDatabase()
    }

    // MARK: - Auth Database

    private func openAuthDatabase() {
        do {
            authDB = try Database(name: "VaultAuthDB")
        } catch {
            print("❌ Auth DB init failed: \(error)")
        }
    }

    // MARK: - Login

    /// Authenticates the user. Tenant is resolved from the email domain;
    /// if the domain is a public provider, `orgOverride` must be supplied.
    func login(email: String, password: String, orgOverride: String? = nil) {
        guard !isLoggingIn else { return }

        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard cleanEmail.contains("@") else {
            loginError = "Enter a valid email address"
            return
        }

        let resolvedTenant: String
        if let tenant = AppConfig.tenantId(from: cleanEmail) {
            resolvedTenant = tenant
        } else if let override = orgOverride, !override.isEmpty {
            resolvedTenant = override.lowercased().replacingOccurrences(of: " ", with: "-")
        } else {
            loginError = "Your email domain is a public provider.\nPlease enter your organisation name."
            return
        }

        isLoggingIn = true
        loginError = nil

        // Validate credentials against Capella App Services via a one-shot pull.
        // We configure AppConfig first so the URL is correct, then attempt a
        // minimal replication. If auth fails the sync error surfaces in the UI.
        // For the PoC we accept credentials optimistically and surface errors
        // through the sync status indicator.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let displayName = cleanEmail.components(separatedBy: "@").first ?? cleanEmail
            let user = SessionUser(
                email: cleanEmail,
                displayName: displayName,
                role: .contributor,
                tenantId: resolvedTenant
            )

            self.databaseManager?.reconfigure(for: resolvedTenant, username: cleanEmail)
            self.persistSession(user: user, password: password)

            withAnimation(.easeInOut(duration: 0.3)) {
                self.currentUser = user
                self.isAuthenticated = true
                self.isLoggingIn = false
            }

            print("✅ Logged in: \(cleanEmail) → tenant: \(resolvedTenant)")
        }
    }

    /// Logs the user in as a local offline guest, letting them bypass authentication
    /// to run the pipeline and classify files right away.
    func loginAsGuest() {
        guard !isLoggingIn else { return }
        isLoggingIn = true
        loginError = nil
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let user = SessionUser(
                email: "guest@local.com",
                displayName: "Guest User",
                role: .contributor,
                tenantId: "local"
            )
            self.databaseManager?.reconfigure(for: "local", username: "guest@local.com")
            self.persistSession(user: user, password: "offline_password")
            
            withAnimation(.easeInOut(duration: 0.3)) {
                self.currentUser = user
                self.isAuthenticated = true
                self.isLoggingIn = false
            }
            print("✅ Logged in as offline guest")
        }
    }

    // MARK: - Logout

    func logout() {
        databaseManager?.disableAppServices()

        withAnimation(.easeInOut(duration: 0.3)) {
            isAuthenticated = false
            currentUser = nil
            loginError = nil
        }

        clearSession()
        print("🚪 Logged out")
    }

    // MARK: - Session Restore

    func restoreSessionIfAny() {
        guard let authDB,
              let doc = try? authDB.defaultCollection().document(id: sessionDocID),
              doc.boolean(forKey: "isAuthenticated"),
              let email    = doc.string(forKey: "email"),
              let tenant   = doc.string(forKey: "tenantId"),
              let roleRaw  = doc.string(forKey: "role"),
              let role     = UserRole(rawValue: roleRaw)
        else {
            print("ℹ️ No valid session found")
            return
        }

        let displayName = doc.string(forKey: "displayName") ?? email
        let user = SessionUser(email: email, displayName: displayName, role: role, tenantId: tenant)

        databaseManager?.reconfigure(for: tenant, username: email)

        currentUser = user
        isAuthenticated = true
        print("🔄 Session restored: \(email) (\(tenant))")
    }

    // MARK: - Persistence

    private func persistSession(user: SessionUser, password: String) {
        guard let authDB else { return }
        do {
            let doc = MutableDocument(id: sessionDocID)
            doc.setString(user.email,       forKey: "email")
            doc.setString(user.displayName, forKey: "displayName")
            doc.setString(user.role.rawValue, forKey: "role")
            doc.setString(user.tenantId,    forKey: "tenantId")
            doc.setBoolean(true,            forKey: "isAuthenticated")
            doc.setDate(Date(),             forKey: "loginTime")
            try authDB.defaultCollection().save(document: doc)
        } catch {
            print("❌ Failed to persist session: \(error)")
        }
    }

    private func clearSession() {
        guard let authDB,
              let doc = try? authDB.defaultCollection().document(id: sessionDocID)
        else { return }
        try? authDB.defaultCollection().delete(document: doc)
    }

    // MARK: - Helpers

    /// Whether the current user has admin rights
    var isAdmin: Bool { currentUser?.role == .admin }

    /// Whether an org picker should be shown for public-domain emails
    func requiresOrgPicker(for email: String) -> Bool {
        AppConfig.tenantId(from: email) == nil && email.contains("@")
    }
}
