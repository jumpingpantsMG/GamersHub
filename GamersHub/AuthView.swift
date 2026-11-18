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
    private enum Phase { case signedOut, needsVerification(String), signedIn }

    @State private var phase: Phase = .signedOut
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            switch phase {
            case .signedIn: content()
            case .needsVerification(let email): VerifyEmailView(email: email)
            case .signedOut: AuthView()
            }
        }
        .task {
            // Emits the current session first, then every sign-in / sign-out.
            for await (_, session) in supabase.auth.authStateChanges {
                phase = Self.phase(for: session)
            }
        }
    }

    /// Viewer sessions don't count. Email accounts must have confirmed their email.
    private static func phase(for session: Session?) -> Phase {
        guard let s = session, !s.user.isAnonymous, !s.isExpired else { return .signedOut }
        if s.user.emailConfirmedAt == nil { return .needsVerification(s.user.email ?? "") }
        return .signedIn
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
    @State private var pendingEmail: String?   // signed up (or tried to sign in) but not confirmed yet
    @State private var signupCode = ""
    @State private var resetEmail: String?     // a reset code was sent here
    @State private var resetCode = ""
    @State private var newPassword = ""

    var body: some View {
        NavigationStack {
            Form {
                if let pendingEmail {
                    Section("Check your email") {
                        Text("We sent a link and a code to \(pendingEmail). Open the link on this device, or type the code here. You can't use your account until your email is confirmed.")
                            .font(.subheadline)
                        TextField("Code from the email", text: $signupCode)
                        Button("Confirm with code") { Task { await confirmSignup(pendingEmail) } }
                            .disabled(busy || signupCode.trimmingCharacters(in: .whitespaces).count < 6)
                        Button("Resend the email") { Task { await resend(pendingEmail) } }.disabled(busy)
                        Button("Use a different email") { self.pendingEmail = nil; message = nil }
                    }
                }

                if let resetEmail {
                    Section("Reset your password") {
                        Text("We sent a code to \(resetEmail). Enter it with your new password.")
                            .font(.subheadline)
                        TextField("Code from the email", text: $resetCode)
                        SecureField("New password (8+ characters)", text: $newPassword)
                        Button("Reset password") { Task { await finishReset(resetEmail) } }
                            .disabled(busy || resetCode.trimmingCharacters(in: .whitespaces).count < 6 || newPassword.count < 8)
                        Button("Cancel") { self.resetEmail = nil; resetCode = ""; newPassword = ""; message = nil }
                    }
                }

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
                    SecureField(isSignUp ? "Password (8+ characters)" : "Password", text: $password)
                    Button(isSignUp ? "Sign up" : "Sign in") { Task { await emailAuth() } }
                        .disabled(busy || email.isEmpty || password.count < (isSignUp ? 8 : 6))
                    if !isSignUp {
                        Button("Forgot password?") { Task { await forgotPassword() } }
                            .disabled(busy || email.isEmpty)
                    }
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
        let anon = await AuthFlow.anonymousToken()   // reviews made as a viewer move into the account
        do {
            if isSignUp {
                let result = try await supabase.auth.signUp(
                    email: email, password: password,
                    redirectTo: URL(string: "gamershub://auth-callback")
                )
                if result.session == nil {
                    pendingEmail = email   // must confirm before they can sign in
                } else {
                    await AuthFlow.mergeProgress(from: anon)
                }
            } else {
                try await supabase.auth.signIn(email: email, password: password)
                await AuthFlow.mergeProgress(from: anon)
            }
        } catch {
            if error.localizedDescription.lowercased().contains("not confirmed") {
                pendingEmail = email
                message = nil
            } else {
                message = error.localizedDescription
            }
        }
    }

    private func resend(_ address: String) async {
        busy = true
        defer { busy = false }
        do {
            try await supabase.auth.resend(email: address, type: .signup)
            message = "Sent again. Check your inbox and spam folder."
        } catch {
            message = error.localizedDescription
        }
    }

    private func confirmSignup(_ address: String) async {
        busy = true
        message = nil
        defer { busy = false }
        let anon = await AuthFlow.anonymousToken()
        do {
            _ = try await supabase.auth.verifyOTP(
                email: address, token: signupCode.trimmingCharacters(in: .whitespaces), type: .signup)
            await AuthFlow.mergeProgress(from: anon)
        } catch {
            message = "That code didn't work. Check it, or resend the email."
        }
    }

    private func forgotPassword() async {
        busy = true
        message = nil
        defer { busy = false }
        do {
            try await supabase.auth.resetPasswordForEmail(
                email, redirectTo: URL(string: "gamershub://auth-callback")
            )
        } catch {
            // Don't hint whether an account exists. Only real problems (like no network) show.
            if (error as? URLError) != nil { message = error.localizedDescription; return }
        }
        resetEmail = email
        pendingEmail = nil
        message = "If there's an account for that email, a code is on its way."
    }

    /// Checks the emailed code, then sets the new password.
    private func finishReset(_ address: String) async {
        busy = true
        message = nil
        defer { busy = false }
        let anon = await AuthFlow.anonymousToken()
        do {
            _ = try await supabase.auth.verifyOTP(
                email: address, token: resetCode.trimmingCharacters(in: .whitespaces), type: .recovery)
        } catch {
            message = "That code didn't work. Check it, or ask for a new one."
            return
        }
        do {
            try await supabase.auth.update(user: UserAttributes(password: newPassword))
            await AuthFlow.mergeProgress(from: anon)
        } catch {
            // The code worked but the password didn't save. Don't leave them signed in with the old one.
            try? await supabase.auth.signOut(scope: .local)
            message = "Couldn't set the new password: \(error.localizedDescription)"
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
                let anon = await AuthFlow.anonymousToken()
                try await supabase.auth.signInWithIdToken(
                    credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: rawNonce)
                )
                await AuthFlow.mergeProgress(from: anon)
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
            let anon = await AuthFlow.anonymousToken()
            let runner = WebAuthRunner()   // kept alive for the length of the sign-in
            _ = try await supabase.auth.signInWithOAuth(
                provider: .google,
                redirectTo: URL(string: "gamershub://auth-callback")
            ) { url in
                try await runner.run(url: url, callbackScheme: "gamershub")
            }
            await AuthFlow.mergeProgress(from: anon)
        } catch {
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
            message = error.localizedDescription
        }
    }
}
