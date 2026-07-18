import AppKit
import CoreGraphics
import DisplayBridge
import Foundation
import IOKit

struct DetectedDisplay: CustomStringConvertible {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltIn: Bool
    let vendorID: UInt32
    let modelID: UInt32

    var description: String {
        "\(name) [id=\(id), builtIn=\(isBuiltIn), vendor=0x\(String(vendorID, radix: 16)), model=0x\(String(modelID, radix: 16))]"
    }
}

enum DisplayDetector {
    static func onlineDisplays() -> [DetectedDisplay] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).filter { $0 != 0 }.map { id in
            DetectedDisplay(
                id: id,
                name: name(for: id),
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                vendorID: CGDisplayVendorNumber(id),
                modelID: CGDisplayModelNumber(id)
            )
        }
    }

    static func builtInDisplay(from displays: [DetectedDisplay]) -> DetectedDisplay? {
        displays.first(where: \.isBuiltIn)
    }

    static func preferredExternalDisplay(from displays: [DetectedDisplay]) -> DetectedDisplay? {
        let externals = displays.filter { !$0.isBuiltIn }
        return externals.first { $0.name.localizedCaseInsensitiveContains("U2725QE") }
            ?? externals.first { $0.vendorID == 0x10ac }
            ?? externals.first
    }

    static func brightness(of displayID: CGDirectDisplayID) -> Float? {
        var value: Float = -1
        guard DisplayServicesGetBrightness(displayID, &value) == 0,
              value >= 0, value <= 1 else { return nil }
        return value
    }

    static func name(for displayID: CGDirectDisplayID) -> String {
        if let dictionary = CoreDisplay_DisplayCreateInfoDictionary(displayID)?.takeRetainedValue() as NSDictionary? {
            let resolved = name(from: dictionary)
            if !resolved.isEmpty { return resolved }
        }
        if let screen = NSScreen.screens.first(where: { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }) {
            return screen.localizedName
        }
        return CGDisplayIsBuiltin(displayID) != 0 ? "MacBook 内建显示器" : "外接显示器"
    }

    static func name(from dictionary: NSDictionary) -> String {
        guard let names = dictionary["DisplayProductName"] as? [String: String] else { return "" }
        return names[Locale.current.identifier] ?? names["zh_CN"] ?? names["en_US"] ?? names.first?.value ?? ""
    }
}
