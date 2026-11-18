import SwiftUI
import Supabase

@main
struct GamersHubApp: App {
    var body: some Scene {
        WindowGroup {
            BrowseView()
                .task { PurchaseManager.shared.start() }
                // Finishes Google sign-in when the browser hands control back to the app.
                // Also opens shared links (gamershub://listing/<id>).
                .onOpenURL { url in
                    if DeepLinkRouter.shared.handle(url) { return }
                    // Email confirmation and password-reset links land here.
                    Task {
                        let anon = await AuthFlow.anonymousToken()
                        if let session = try? await supabase.auth.session(from: url) {
                            await AuthFlow.mergeProgress(from: anon)
                            // A reset link signs you in. If one was just requested, ask for the new password.
                            if let sent = session.user.recoverySentAt, abs(sent.timeIntervalSinceNow) < 3600 {
                                DeepLinkRouter.shared.showNewPassword = true
                            }
                        }
                    }
                }
                #if os(macOS)
                .frame(minWidth: 760, minHeight: 600)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 800)
        #endif
    }
}
