import SwiftUI
import Supabase

@main
struct GamersHubApp: App {
    var body: some Scene {
        WindowGroup {
            BrowseView()
                .task { PurchaseManager.shared.start() }
                // Finishes Google sign-in when the browser hands control back to the app.
                .onOpenURL { url in
                    Task { try? await supabase.auth.session(from: url) }
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
