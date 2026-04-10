import Foundation
import StoreKit

@MainActor @Observable
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

    func loadProducts() async {
        do {
            let storeProducts = try await Product.products(for: Self.productIds)
            products = storeProducts.sorted { $0.price < $1.price }
        } catch {
            print("Failed to load products: \(error)")
        }
    }

    func purchase(_ product: Product) async {
        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = checkVerified(verification)
                if let transaction {
                    await transaction.finish()
                    purchaseState = .thanked
                    dismissThankYouAfterDelay()
                } else {
                    purchaseState = .idle
                }
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

    private nonisolated func checkVerified<T: Sendable>(_ result: VerificationResult<T>) -> T? {
        switch result {
        case .unverified:
            return nil
        case .verified(let value):
            return value
        }
    }

    private func observeTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { break }
                if let transaction = self.checkVerified(result) {
                    await transaction.finish()
                }
            }
        }
    }

    private func dismissThankYouAfterDelay() {
        Task {
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
