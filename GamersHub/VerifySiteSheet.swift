//
//  VerifySiteSheet.swift
//  GamersHub
//
//  Created by Jaiden Kumar on 13/11/26.
//


import SwiftUI

/// Walks an advertiser through proving they own the site.
struct VerifySiteSheet: View {
    let listing: Listing
    let store: ListingsStore
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var token: String?
    @State private var message: String?
    @State private var checking = false
    @State private var done = false

    private var host: String { URL(string: listing.url)?.host ?? listing.url }
    private var metaTag: String { "<meta name=\"gamershub-verify\" content=\"\(token ?? "")\">" }

    var body: some View {
        NavigationStack {
            Form {
                if done {
                    Section {
                        Label("Verified! Your listing now shows the badge.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                } else if let token {
                    Section("Step 1: add this code to \(host)") {
                        Text("Pick one:").font(.subheadline).foregroundStyle(.secondary)
                        Text("A. Put this in the <head> of the page you listed (\(listing.url)) or your home page:")
                            .font(.subheadline)
                        copyable(metaTag)
                        Text("B. Or create a text file at /.well-known/gamershub-verify.txt on your site that contains only:")
                            .font(.subheadline)
                        copyable(token)
                    }
                    Section("Step 2") {
                        Button {
                            Task { await check() }
                        } label: {
                            HStack {
                                Text(checking ? "Checking..." : "Verify my site")
                                if checking { ProgressView() }
                            }
                        }
                        .disabled(checking)
                        Text("Changing your site's address later removes the badge and gives you a new code.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView()
                }

                if let message {
                    Text(message).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Verify site")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(done ? "Done" : "Close") { onDone(); dismiss() }
                }
            }
            .task { await loadToken() }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 440)
        #endif
    }

    private func copyable(_ text: String) -> some View {
        HStack(alignment: .top) {
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button {
                #if os(iOS)
                UIPasteboard.general.string = text
                #else
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                #endif
            } label: { Image(systemName: "doc.on.doc") }
            .buttonStyle(.borderless)
        }
    }

    private func loadToken() async {
        do { token = try await store.verifyToken(for: listing) }
        catch { message = "Couldn't get your code: \(error.localizedDescription)" }
    }

    private func check() async {
        checking = true
        message = nil
        defer { checking = false }
        if let problem = await store.verifySite(listing) {
            message = problem
        } else {
            done = true
        }
    }
}