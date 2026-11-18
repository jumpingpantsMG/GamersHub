import SwiftUI
import Supabase

/// Shown after someone opens a password-reset link.
struct NewPasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var repeated = ""
    @State private var busy = false
    @State private var message: String?
    @State private var done = false

    private var valid: Bool { password.count >= 8 && password == repeated }

    var body: some View {
        NavigationStack {
            Form {
                if done {
                    Section { Label("Password updated. You're signed in.", systemImage: "checkmark.circle.fill") }
                } else {
                    Section("Choose a new password") {
                        SecureField("New password (8+ characters)", text: $password)
                        SecureField("Repeat it", text: $repeated)
                        if !repeated.isEmpty && password != repeated {
                            Text("The two don't match.").font(.footnote).foregroundStyle(.red)
                        }
                        Button("Save password") { Task { await save() } }
                            .disabled(!valid || busy)
                    }
                }
                if let message { Section { Text(message).foregroundStyle(.red) } }
            }
            .formStyle(.grouped)
            .navigationTitle("Reset password")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(done ? "Done" : "Cancel") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }

    private func save() async {
        busy = true
        message = nil
        defer { busy = false }
        do {
            try await supabase.auth.update(user: UserAttributes(password: password))
            done = true
        } catch {
            message = error.localizedDescription
        }
    }
}

/// An account whose email isn't confirmed yet. Nothing else is available until it is.
struct VerifyEmailView: View {
    @Environment(\.dismiss) private var dismiss
    let email: String
    @State private var code = ""
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Confirm your email", systemImage: "envelope.badge")
                        .font(.headline)
                    Text("We sent a link and a code to \(email). Open the link on this device, or type the code below. Until then you can't add or manage listings.")
                        .font(.subheadline)
                }
                Section("Code from the email") {
                    TextField("Code", text: $code)
                    Button("Confirm with code") { Task { await confirm() } }
                        .disabled(busy || code.trimmingCharacters(in: .whitespaces).count < 6)
                }
                Section {
                    Button("I've confirmed it") { Task { await refresh() } }.disabled(busy)
                    Button("Resend the email") { Task { await resend() } }.disabled(busy || email.isEmpty)
                    Button("Sign out", role: .destructive) { Task { try? await supabase.auth.signOut() } }
                }
                if let message { Section { Text(message).foregroundStyle(.secondary) } }
            }
            .formStyle(.grouped)
            .navigationTitle("Almost there")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }

    private func refresh() async {
        busy = true
        defer { busy = false }
        do {
            let s = try await supabase.auth.refreshSession()
            if s.user.emailConfirmedAt == nil { message = "Not confirmed yet. Open the link in the email first." }
        } catch {
            message = error.localizedDescription
        }
    }

    private func confirm() async {
        busy = true
        defer { busy = false }
        do {
            _ = try await supabase.auth.verifyOTP(
                email: email, token: code.trimmingCharacters(in: .whitespaces), type: .signup)
        } catch {
            message = "That code didn't work. Check it, or resend the email."
        }
    }

    private func resend() async {
        busy = true
        defer { busy = false }
        do {
            try await supabase.auth.resend(email: email, type: .signup)
            message = "Sent again. Check your inbox and spam folder."
        } catch {
            message = error.localizedDescription
        }
    }
}

/// Deleting an account needs a code emailed to the account's address, so a borrowed phone can't do it.
struct DeleteAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: ListingsStore
    let onDeleted: () -> Void

    @State private var email = ""
    @State private var sent = false
    @State private var code = ""
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Delete your account", systemImage: "trash").font(.headline)
                    Text("This permanently deletes your account, all your listings, and your reviews. Purchases you've already made can't be refunded by deleting your account.")
                        .font(.subheadline)
                    Text("To make sure it's you, we'll email a code to \(email.isEmpty ? "your email" : email).")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                if !sent {
                    Section {
                        Button("Email me a code") { Task { await send() } }.disabled(busy || email.isEmpty)
                    }
                } else {
                    Section("Enter the code") {
                        TextField("Code from the email", text: $code)
                        Button("Delete my account", role: .destructive) { Task { await delete() } }
                            .disabled(busy || code.trimmingCharacters(in: .whitespaces).count < 6)
                        Button("Send a new code") { Task { await send() } }.disabled(busy)
                    }
                }

                if let message { Section { Text(message).foregroundStyle(.secondary) } }
            }
            .formStyle(.grouped)
            .navigationTitle("Delete account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task {
                email = (try? await supabase.auth.session)?.user.email ?? ""
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 380)
        #endif
    }

    private func send() async {
        busy = true
        message = nil
        defer { busy = false }
        do {
            try await supabase.auth.signInWithOTP(email: email, shouldCreateUser: false)
            sent = true
            message = "Code sent. It can take a minute. Check spam too."
        } catch {
            message = error.localizedDescription
        }
    }

    private func delete() async {
        busy = true
        message = nil
        defer { busy = false }
        do {
            try await store.deleteAccount(code: code.trimmingCharacters(in: .whitespaces))
            onDeleted()
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}
