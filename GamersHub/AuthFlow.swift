//
//  AuthFlow.swift
//  GamersHub
//
//  Created by Jaiden Kumar on 14/11/26.
//


import Foundation
import Supabase

/// Carries what someone did as a viewer (reviews, helpful votes, so their level) into the account
/// they sign in to, so progress belongs to the account and follows it to any device.
enum AuthFlow {
    /// The viewer session's token, if this device is currently browsing as a viewer. Grab it BEFORE signing in.
    static func anonymousToken() async -> String? {
        guard let s = try? await supabase.auth.session, s.user.isAnonymous else { return nil }
        return s.accessToken
    }

    /// Call after a successful sign-in with whatever `anonymousToken()` returned beforehand.
    static func mergeProgress(from anonymousToken: String?) async {
        guard let anonymousToken,
              let s = try? await supabase.auth.session, !s.user.isAnonymous else { return }
        try? await supabase.functions.invoke(
            "merge-progress",
            options: FunctionInvokeOptions(
                headers: ["Authorization": "Bearer \(s.accessToken)"],
                body: ["anonymous_token": anonymousToken]
            )
        )
    }
}
