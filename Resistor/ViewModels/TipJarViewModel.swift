import Foundation
import StoreKit

@Observable
final class TipJarViewModel {
    private(set) var products: [Product] = []
    private(set) var purchaseState: PurchaseState = .idle
    private var updates: Task<Void, Never>?

    enum PurchaseState {
        case idle
        case purchasing
        case thanked
    }

    static let productIds: [String] = [
        "com.resistor.tip.small",
        "com.resistor.tip.medium",
        "com.resistor.tip.large"
    ]

    init() {
        updates = observeTransactions()
        Task { await loadProducts() }
    }

    deinit {
        updates?.cancel()
    }

    @MainActor
    func loadProducts() async {
        do {
            let storeProducts = try await Product.products(for: Self.productIds)
            products = storeProducts.sorted { $0.price < $1.price }
        } catch {
            print("Failed to load products: \(error)")
        }
    }

    @MainActor
    func purchase(_ product: Product) async {
        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                purchaseState = .thanked
                dismissThankYouAfterDelay()
            case .userCancelled, .pending:
                purchaseState = .idle
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            print("Purchase failed: \(error)")
            purchaseState = .idle
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.verificationFailed
        case .verified(let value):
            return value
        }
    }

    private func observeTransactions() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                if let transaction = try? self.checkVerified(result) {
                    await transaction.finish()
                }
            }
        }
    }

    private func dismissThankYouAfterDelay() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if purchaseState == .thanked {
                purchaseState = .idle
            }
        }
    }

    enum StoreError: Error {
        case verificationFailed
    }
}
