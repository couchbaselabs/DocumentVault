import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthenticationManager

    @State private var email        = ""
    @State private var password     = ""
    @State private var orgName      = ""
    @State private var showOrgField = false
    @FocusState private var focused: Field?

    private enum Field { case email, password, org }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(.systemIndigo), Color(.systemBlue).opacity(0.7)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    Spacer(minLength: 60)

                    VStack(spacing: 8) {
                        Image(systemName: "doc.badge.gearshape")
                            .font(.system(size: 64))
                            .foregroundColor(.white)
                        Text("Document Vault")
                            .font(.largeTitle.bold())
                            .foregroundColor(.white)
                        Text("Secure. Offline-first. Chain of custody.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.75))
                    }

                    VStack(spacing: 20) {
                        field(label: "Email", icon: "envelope") {
                            TextField("you@yourcompany.com", text: $email)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .focused($focused, equals: .email)
                                .onChange(of: email) { _, v in
                                    withAnimation { showOrgField = authManager.requiresOrgPicker(for: v) }
                                }
                        }

                        if showOrgField {
                            field(label: "Organisation", icon: "building.2") {
                                TextField("acme-corp", text: $orgName)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .focused($focused, equals: .org)
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        field(label: "Password", icon: "lock") {
                            SecureField("Password", text: $password)
                                .textContentType(.password)
                                .focused($focused, equals: .password)
                        }

                        if let err = authManager.loginError {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text(err).font(.caption)
                            }
                            .foregroundColor(.red)
                        }

                        Button {
                            focused = nil
                            authManager.login(email: email, password: password,
                                              orgOverride: showOrgField ? orgName : nil)
                        } label: {
                            Group {
                                if authManager.isLoggingIn {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Sign In").fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canSubmit ? Color.indigo : Color.gray)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(!canSubmit || authManager.isLoggingIn)
                        .animation(.easeInOut(duration: 0.2), value: canSubmit)

                        Button {
                            focused = nil
                            authManager.loginAsGuest()
                        } label: {
                            Text("Try Offline Sandbox")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.white.opacity(0.2))
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(authManager.isLoggingIn)
                    }
                    .padding(24)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(radius: 12)
                    .padding(.horizontal, 24)

                    Spacer(minLength: 40)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showOrgField)
    }

    @ViewBuilder
    private func field<F: View>(label: String, icon: String, @ViewBuilder content: () -> F) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon).font(.caption).foregroundColor(.secondary)
            content()
                .padding(12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty && (!showOrgField || !orgName.isEmpty)
    }
}
