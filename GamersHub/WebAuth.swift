//
//  WebAuth.swift
//  GamersHub
//
//  Created by Jaiden Kumar on 14/11/26.
//


import AuthenticationServices
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Runs the browser sign-in window. The library's own version crashes on macOS 26 because the browser
/// calls back on a background thread. The callback below is marked @Sendable, so it makes no
/// assumption about which thread it runs on.
@MainActor
final class WebAuthRunner: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func run(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let finish: @Sendable (URL?, Error?) -> Void = { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? URLError(.cancelled))
                }
            }
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme,
                                               completionHandler: finish)
            s.presentationContextProvider = self
            session = s
            if !s.start() {
                continuation.resume(throwing: URLError(.cannotConnectToHost))
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(macOS)
        return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #else
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.keyWindow ?? ASPresentationAnchor()
        #endif
    }
}
