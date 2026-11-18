import Foundation
import Observation
import StoreKit
import Supabase

@MainActor
@Observable
final class PurchaseManager {
    static let shared = PurchaseManager()

    /// Must match the Product IDs in App Store Connect (and your .storekit file) exactly.
    static let productIDs = [
        "com.gamershub.feature.1day",
        "com.gamershub.feature.3day",
        "com.gamershub.feature.7day",
        "com.gamershub.feature.14day",
        "com.gamershub.feature.30day",
    ]

    var products: [Product] = []
    var isWorking = false
    var message: String?

    private var listener: Task<Void, Never>?

    static func days(for productID: String) -> Int {
        let digits = productID.split(separator: ".").last?.filter(\.isNumber) ?? ""
        return Int(digits) ?? 0
    }

    /// Call once at app launch.
    func start() {
        guard listener == nil else { return }
        listener = Task {
            // Purchases that were paid for but never finished (e.g. network died mid-redeem).
            for await result in Transaction.unfinished { await handle(result) }
        }
        Task {
            // Purchases that arrive while the app is running (Ask to Buy approvals, etc).
            for await result in Transaction.updates { await handle(result) }
        }
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: Self.productIDs)
                .sorted { Self.days(for: $0.id) < Self.days(for: $1.id) }
            if products.isEmpty { message = "No products found. Check the product IDs." }
        } catch {
            message = error.localizedDescription
        }
    }

    /// Returns true once the server has applied the purchase.
    func buy(_ product: Product, reservation: UUID) async -> Bool {
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            // The slot reservation id rides inside the signed transaction, so the server knows
            // which listing and start date were paid for and the client can't redirect it.
            let result = try await product.purchase(options: [.appAccountToken(reservation)])
            switch result {
            case .success(let verification):
                guard case .verified(let txn) = verification else {
                    message = "Purchase couldn't be verified."
                    return false
                }
                try await redeem(verification.jwsRepresentation)
                await txn.finish()
                return true
            case .pending:
                message = "Purchase is pending approval."
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            message = "Payment went through but activating it failed: \(error.localizedDescription). It will retry next time you open the app."
            return false
        }
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let txn) = result,
              Self.productIDs.contains(txn.productID) else { return }
        do {
            try await redeem(result.jwsRepresentation)
            await txn.finish()
        } catch {
            // Leave unfinished so it retries on next launch.
        }
    }

    private func redeem(_ signedTransaction: String) async throws {
        try await supabase.functions.invoke(
            "verify-purchase",
            options: FunctionInvokeOptions(body: ["signed_transaction": signedTransaction])
        )
    }
}
