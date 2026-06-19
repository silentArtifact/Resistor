import XCTest
@testable import Resistor

@MainActor
final class TipJarViewModelTests: XCTestCase {

    // MARK: - Initial State

    func testInitialPurchaseStateIsIdle() {
        let vm = TipJarViewModel()
        XCTAssertEqual(vm.purchaseState, .idle)
    }

    func testInitialProductIsNil() {
        let vm = TipJarViewModel()
        XCTAssertNil(vm.product)
    }

    func testProductIdIsCorrect() {
        XCTAssertEqual(TipJarViewModel.productId, "com.resistor.tip")
    }

    // MARK: - PurchaseState Enum

    func testPurchaseStateHasExpectedCases() {
        let idle = TipJarViewModel.PurchaseState.idle
        let purchasing = TipJarViewModel.PurchaseState.purchasing
        let thanked = TipJarViewModel.PurchaseState.thanked

        // Verify all three states are distinct
        XCTAssertNotEqual(String(describing: idle), String(describing: purchasing))
        XCTAssertNotEqual(String(describing: purchasing), String(describing: thanked))
        XCTAssertNotEqual(String(describing: idle), String(describing: thanked))
    }

    // MARK: - Purchase Without Product

    func testPurchaseWithNoProductDoesNotCrash() async {
        let vm = TipJarViewModel()
        // product is nil, purchase should return immediately
        await vm.purchase()
        XCTAssertEqual(vm.purchaseState, .idle)
    }
}
