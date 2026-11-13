import SwiftUI
import StoreKit

struct FeatureSheet: View {
    let listing: Listing
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    private let purchases = PurchaseManager.shared
    @State private var succeeded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Sponsor \"\(listing.title)\"") {
                    Text("Sponsored listings get the large spotlight cards at the top of the feed, labeled Sponsored. Buying again while sponsored adds to your remaining time. The Featured spot is separate and earned through ratings and visits.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                if succeeded {
                    Section { Label("Your listing is sponsored.", systemImage: "checkmark.circle.fill") }
                } else {
                    Section("Choose a length") {
                        if purchases.products.isEmpty {
                            ProgressView()
                        }
                        ForEach(purchases.products) { product in
                            HStack {
                                let d = PurchaseManager.days(for: product.id)
                                Text("\(d) day\(d == 1 ? "" : "s")")
                                Spacer()
                                Button(product.displayPrice) {
                                    Task {
                                        if await purchases.buy(product, for: listing) {
                                            succeeded = true
                                            onDone()
                                        }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(purchases.isWorking)
                            }
                        }
                    }
                }

                if let message = purchases.message {
                    Section { Text(message).foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Get sponsored")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(succeeded ? "Done" : "Cancel") { dismiss() }
                }
            }
            .task { await purchases.loadProducts() }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 420)
        #endif
    }
}
