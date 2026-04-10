import Foundation
import StoreKit

@MainActor @Observable
final class TipJarViewModel {
    private(set) var product: Product?
    private(set) var purchaseState: PurchaseState = .idle
    @ObservationIgnored private var updates: Task<Void, Never>?

    enum PurchaseState {
        case idle
        case purchasing
        case thanked
    }

    static let productId = "com.resistor.tip"

    init() {
        updates = observeTransactions()
        Task { await loadProduct() }
    }

    deinit {
        updates?.cancel()
    }

    func loadProduct() async {
        do {
            let storeProducts = try await Product.products(for: [Self.productId])
            product = storeProducts.first
        } catch {
            print("Failed to load product: \(error)")
        }
    }

    func purchase() async {
        guard let product else { return }
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

}
