import SwiftUI
import Observation

/// Where shared links point. Deploy the `site` folder, then put your real address here.
enum ShareConfig {
    static let base = "https://gamershub-2e9.pages.dev"

    /// The web page for a listing. It has an "Open in GamersHub" button (gamershub://listing/<id>).
    static func url(for l: Listing) -> URL {
        URL(string: "\(base)/l/?id=\(l.id.uuidString)") ?? URL(string: "https://example.com")!
    }
}

/// A listing someone asked to open from a link. BrowseView watches this and opens it.
@MainActor
@Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()
    var listingID: UUID?
    var showNewPassword = false   // set when a password-reset link was just opened

    /// Handles gamershub://listing/<id>. Returns false for anything else (like the sign-in callback).
    func handle(_ url: URL) -> Bool {
        guard url.scheme == "gamershub", url.host == "listing",
              let id = UUID(uuidString: url.lastPathComponent) else { return false }
        listingID = id
        return true
    }
}
