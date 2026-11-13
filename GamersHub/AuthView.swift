import SwiftUI
import Supabase
import AuthenticationServices
import CryptoKit

/// Flip to true once your Apple Developer membership is active and the
/// "Sign in with Apple" capability is added. Until then the button would only error.
private let appleSignInEnabled = false

/// Shows `content` only when an advertiser is signed in; otherwise shows the sign-in form.
/// The silent anonymous sessions viewers get for reviewing do not count as signed in.
struct AuthGate<Content: View>: View {
    @State private var signedIn = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if signedIn { content() } else { AuthView() }
        }
        .task {
            // Emits the current session first, then every sign-in / sign-out.
            for await (_, session) in supabase.auth.authStateChanges {
                signedIn = session.map { !$0.user.isAnonymous } ?? false
            }
        }
    }
}

struct AuthView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var busy = false
    @State private var message: String?
    @State private var rawNonce = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if appleSignInEnabled {
                        SignInWithAppleButton(.continue) { request in
                            // Apple gets a hashed nonce, Supabase gets the original, so a stolen token can't be replayed.
                            let nonce = Self.makeNonce()
                            rawNonce = nonce
                            request.requestedScopes = [.email]
                            request.nonce = Self.sha256(nonce)
                        } onCompletion: { result in
                            Task { await handleApple(result) }
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 46)
                    }

                    Button {
                        Task { await signInWithGoogle() }
                    } label: {
                        Label("Continue with Google", systemImage: "globe")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(busy)
                }

                Section(isSignUp ? "Or create an account with email" : "Or sign in with email") {
                    TextField("Email", text: $email)
                    SecureField("Password (6+ characters)", text: $password)
                    Button(isSignUp ? "Sign up" : "Sign in") { Task { await emailAuth() } }
                        .disabled(busy || email.isEmpty || password.count < 6)
                    Button(isSignUp ? "Have an account? Sign in" : "New here? Create account") {
                        isSignUp.toggle()
                        message = nil
                    }
                }

                if let message {
                    Section { Text(message).foregroundStyle(.secondary) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Advertise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        #endif
    }

    // MARK: Email

    private func emailAuth() async {
        busy = true
        message = nil
        defer { busy = false }
        do {
            if isSignUp {
                let result = try await supabase.auth.signUp(email: email, password: password)
                if result.session == nil {
                    message = "Check your email to confirm your account, then sign in."
                }
            } else {
                try await supabase.auth.signIn(email: email, password: password)
            }
        } catch {
            message = error.localizedDescription
        }
    }

    // MARK: Apple

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                message = error.localizedDescription
            }
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                message = "Apple sign-in didn't return a valid token."
                return
            }
            busy = true
            defer { busy = false }
            do {
                try await supabase.auth.signInWithIdToken(
                    credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: rawNonce)
                )
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private static func makeNonce() -> String {
        (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "")
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Google

    private func signInWithGoogle() async {
        busy = true
        message = nil
        defer { busy = false }
        do {
            _ = try await supabase.auth.signInWithOAuth(
                provider: .google,
                redirectTo: URL(string: "gamershub://auth-callback")
            )
        } catch {
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
            message = error.localizedDescription
        }
    }
}
