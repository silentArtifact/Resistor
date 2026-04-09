import XCTest
import SwiftUI
@testable import Resistor

final class ColorHexTests: XCTestCase {

    // MARK: - Valid 6-Character Hex

    func testValidSixCharWithHash() {
        let color = Color(hex: "#FF0000")
        XCTAssertNotNil(color)
    }

    func testValidSixCharWithoutHash() {
        let color = Color(hex: "FF0000")
        XCTAssertNotNil(color)
    }

    func testBlackHex() {
        let color = Color(hex: "#000000")
        XCTAssertNotNil(color)
    }

    func testWhiteHex() {
        let color = Color(hex: "#FFFFFF")
        XCTAssertNotNil(color)
    }

    func testLowercaseHex() {
        let color = Color(hex: "#ff0000")
        XCTAssertNotNil(color)
    }

    func testMixedCaseHex() {
        let color = Color(hex: "#fF00aB")
        XCTAssertNotNil(color)
    }

    // MARK: - Valid 8-Character Hex (ARGB)

    func testValidEightCharARGB() {
        let color = Color(hex: "#FF007AFF")
        XCTAssertNotNil(color)
    }

    func testEightCharWithoutHash() {
        let color = Color(hex: "FF007AFF")
        XCTAssertNotNil(color)
    }

    func testFullyTransparentARGB() {
        let color = Color(hex: "#00000000")
        XCTAssertNotNil(color)
    }

    func testFullyOpaqueARGB() {
        let color = Color(hex: "#FFFFFFFF")
        XCTAssertNotNil(color)
    }

    // MARK: - Invalid Inputs

    func testEmptyStringReturnsNil() {
        let color = Color(hex: "")
        XCTAssertNil(color)
    }

    func testHashOnlyReturnsNil() {
        let color = Color(hex: "#")
        XCTAssertNil(color)
    }

    func testThreeCharShorthandReturnsNil() {
        let color = Color(hex: "#FFF")
        XCTAssertNil(color)
    }

    func testFourCharReturnsNil() {
        let color = Color(hex: "#FFFF")
        XCTAssertNil(color)
    }

    func testFiveCharReturnsNil() {
        let color = Color(hex: "#FFFFF")
        XCTAssertNil(color)
    }

    func testSevenCharReturnsNil() {
        let color = Color(hex: "#FFFFFFF")
        XCTAssertNil(color)
    }

    func testNineCharReturnsNil() {
        let color = Color(hex: "#FFFFFFFFF")
        XCTAssertNil(color)
    }

    func testInvalidHexCharactersReturnsNil() {
        let color = Color(hex: "#GGGGGG")
        XCTAssertNil(color)
    }

    func testNonHexStringReturnsNil() {
        let color = Color(hex: "notahex")
        XCTAssertNil(color)
    }

    // MARK: - Whitespace Handling

    func testLeadingWhitespace() {
        let color = Color(hex: "  #FF0000")
        XCTAssertNotNil(color)
    }

    func testTrailingWhitespace() {
        let color = Color(hex: "#FF0000  ")
        XCTAssertNotNil(color)
    }

    func testLeadingAndTrailingWhitespace() {
        let color = Color(hex: "  #FF0000  ")
        XCTAssertNotNil(color)
    }

    // MARK: - App Color Palette

    func testAllAppColorsParseSuccessfully() {
        let appColors = [
            "#007AFF", "#34C759", "#FF9500", "#FF3B30",
            "#AF52DE", "#FF2D55", "#5AC8FA", "#5856D6",
            "#FFCC00", "#8E8E93"
        ]

        for hex in appColors {
            XCTAssertNotNil(Color(hex: hex), "Failed to parse app color: \(hex)")
        }
    }
}
