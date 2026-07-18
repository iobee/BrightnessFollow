import Foundation

enum BrightnessMapper {
    static let standardKeyStep = 1.0 / 16.0
    static let fineKeyStep = 1.0 / 64.0

    static func following(
        sourceBrightness: Double,
        sensitivity: Double,
        minimum: Double
    ) -> Double {
        min(1, max(minimum, sourceBrightness * sensitivity))
    }

    static func ddcValue(normalized: Double, maximum: UInt16) -> UInt16 {
        UInt16((min(1, max(0, normalized)) * Double(maximum)).rounded())
    }

    static func adjustedByBrightnessKey(
        current: Double,
        direction: BrightnessKeyDirection,
        fine: Bool,
        minimum: Double
    ) -> Double {
        let step = fine ? fineKeyStep : standardKeyStep
        return min(1, max(minimum, current + direction.sign * step))
    }

    static func dellCompensated(raw: Double, offset: Double, minimum: Double) -> Double {
        min(1, max(minimum, raw + offset))
    }
}
