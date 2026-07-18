import XCTest
import AppKit
@testable import BrightnessFollow

final class BrightnessMapperTests: XCTestCase {
    func testAbsoluteFollowingMatchesCurrentSourceAtOneHundredPercent() {
        let result = BrightnessMapper.following(
            sourceBrightness: 0.49,
            sensitivity: 1,
            minimum: 0.10
        )
        XCTAssertEqual(result, 0.49, accuracy: 0.0001)
    }

    func testMinimumBrightnessIsRespected() {
        let result = BrightnessMapper.following(
            sourceBrightness: 0.03,
            sensitivity: 1,
            minimum: 0.10
        )
        XCTAssertEqual(result, 0.10, accuracy: 0.0001)
    }

    func testMaximumBrightnessIsClamped() {
        let result = BrightnessMapper.following(
            sourceBrightness: 0.80,
            sensitivity: 1.5,
            minimum: 0
        )
        XCTAssertEqual(result, 1.0, accuracy: 0.0001)
    }

    func testDDCConversion() {
        XCTAssertEqual(BrightnessMapper.ddcValue(normalized: 0.426, maximum: 100), 43)
        XCTAssertEqual(BrightnessMapper.ddcValue(normalized: -1, maximum: 100), 0)
        XCTAssertEqual(BrightnessMapper.ddcValue(normalized: 2, maximum: 100), 100)
    }

    func testBrightnessKeyUsesAppleLikeSteps() {
        XCTAssertEqual(
            BrightnessMapper.adjustedByBrightnessKey(
                current: 0.50,
                direction: .increase,
                fine: false,
                minimum: 0.10
            ),
            0.5625,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            BrightnessMapper.adjustedByBrightnessKey(
                current: 0.50,
                direction: .decrease,
                fine: true,
                minimum: 0.10
            ),
            0.484375,
            accuracy: 0.0001
        )
    }

    func testBrightnessKeyRespectsExternalMinimum() {
        XCTAssertEqual(
            BrightnessMapper.adjustedByBrightnessKey(
                current: 0.11,
                direction: .decrease,
                fine: false,
                minimum: 0.10
            ),
            0.10,
            accuracy: 0.0001
        )
    }

    func testBrightnessMediaKeyParser() {
        let brightnessUpPressed = (2 << 16) | (0x0A << 8)
        XCTAssertEqual(
            BrightnessKeyEvent.parse(data1: brightnessUpPressed, modifierFlags: []),
            BrightnessKeyEvent(direction: .increase, phase: .pressed, isFineAdjustment: false)
        )

        let brightnessDownReleased = (3 << 16) | (0x0B << 8)
        XCTAssertEqual(
            BrightnessKeyEvent.parse(
                data1: brightnessDownReleased,
                modifierFlags: [.option, .shift]
            ),
            BrightnessKeyEvent(direction: .decrease, phase: .released, isFineAdjustment: true)
        )
    }

    func testUnrelatedMediaKeyIsIgnored() {
        let volumeUpPressed = (0 << 16) | (0x0A << 8)
        XCTAssertNil(BrightnessKeyEvent.parse(data1: volumeUpPressed, modifierFlags: []))
    }

    func testChecksum() {
        XCTAssertEqual(DDC.checksum(seed: 0x50, data: [0x01, 0x02, 0x03]), 0x50)
    }

    func testDellCompensationAddsOffsetAndFloor() {
        XCTAssertEqual(
            BrightnessMapper.dellCompensated(raw: 0.03, offset: 0.15, minimum: 0.10),
            0.18,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            BrightnessMapper.dellCompensated(raw: 0.03, offset: 0, minimum: 0.10),
            0.10,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            BrightnessMapper.dellCompensated(raw: 0.90, offset: 0.20, minimum: 0.10),
            1.0,
            accuracy: 0.0001
        )
    }
}
