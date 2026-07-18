import CoreGraphics
import Foundation

enum Diagnostics {
    static func printApplicationWindows() -> Int32 {
        guard let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID)
                as? [[String: Any]] else {
            print("ERROR: Could not read window list")
            return 9
        }

        let matches = windows.filter { window in
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            return owner.localizedCaseInsensitiveContains("BrightnessFollow")
                || owner.localizedCaseInsensitiveContains("亮度跟随")
        }
        for window in matches {
            let id = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
            let name = window[kCGWindowName as String] as? String ?? ""
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            let bounds = window[kCGWindowBounds as String] ?? ""
            print("window=\(id) owner=\(owner) name=\(name) layer=\(layer) bounds=\(bounds)")
        }
        return matches.isEmpty ? 10 : 0
    }

    static func run(verifyWrite: Bool) -> Int32 {
        let displays = DisplayDetector.onlineDisplays()
        print("Online displays: \(displays.count)")
        displays.forEach { print("- \($0)") }

        if let source = DisplayDetector.builtInDisplay(from: displays) {
            if let sourceBrightness = DisplayDetector.brightness(of: source.id) {
                print("Built-in brightness: \(Int((sourceBrightness * 100).rounded()))%")
            } else {
                print("WARNING: Could not read built-in brightness")
            }
        } else {
            print("Built-in display: unavailable (likely clamshell mode)")
        }

        guard let target = DisplayDetector.preferredExternalDisplay(from: displays) else {
            print("ERROR: External display not found")
            return 4
        }
        let services = DDC.matchedServices(displayIDs: displays.filter { !$0.isBuiltIn }.map(\.id))
        print("Matched DDC services: \(services.count)")
        guard let service = services.first(where: { $0.displayID == target.id }) else {
            print("ERROR: No DDC service matched \(target.name)")
            return 5
        }
        print("DDC match: \(service.name), score=\(service.matchScore), location=\(service.serviceLocation)")

        guard let brightness = DDC.read(service: service.service, command: DDC.luminanceVCP) else {
            print("ERROR: DDC brightness read failed")
            return 6
        }
        print("External hardware brightness: \(brightness.current)/\(brightness.max)")

        if let ambient = DDC.read(service: service.service, command: DDC.ambientLightSensorVCP) {
            print("External ambient-light sensor VCP 0x66: \(ambient.current)/\(ambient.max)")
        } else {
            print("External ambient-light sensor VCP 0x66: not readable")
        }

        if verifyWrite {
            print("Writing the same value back for a state-neutral DDC verification…")
            guard DDC.write(service: service.service, command: DDC.luminanceVCP, value: brightness.current) else {
                print("ERROR: DDC brightness write failed")
                return 7
            }
            guard let after = DDC.read(service: service.service, command: DDC.luminanceVCP),
                  after.current == brightness.current else {
                print("ERROR: DDC verification readback failed")
                return 8
            }
            print("DDC write verification: PASS")
        }
        return 0
    }
}
