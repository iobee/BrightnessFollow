// The Apple Silicon DDC transport is adapted from MonitorControl.
// Copyright (c) MonitorControl contributors. Used under the MIT License.

import CoreGraphics
import DisplayBridge
import Foundation
import IOKit

enum DDC {
    static let luminanceVCP: UInt8 = 0x10
    static let ambientLightSensorVCP: UInt8 = 0x66

    struct RegistryService {
        var edidUUID = ""
        var productName = ""
        var serialNumber: Int64 = 0
        var ioDisplayLocation = ""
        var service: IOAVService?
        var serviceLocation = 0
    }

    struct DisplayService {
        let displayID: CGDirectDisplayID
        let service: IOAVService
        let serviceLocation: Int
        let name: String
        let matchScore: Int
    }

    static func matchedServices(displayIDs: [CGDirectDisplayID]) -> [DisplayService] {
        let registryServices = registryServices()
        var candidates: [DisplayService] = []

        for displayID in displayIDs {
            for registry in registryServices {
                guard let service = registry.service else { continue }
                let score = matchScore(
                    displayID: displayID,
                    edidUUID: registry.edidUUID,
                    ioDisplayLocation: registry.ioDisplayLocation,
                    productName: registry.productName,
                    serialNumber: registry.serialNumber
                )
                guard score > 0 else { continue }
                candidates.append(
                    DisplayService(
                        displayID: displayID,
                        service: service,
                        serviceLocation: registry.serviceLocation,
                        name: DisplayDetector.name(for: displayID),
                        matchScore: score
                    )
                )
            }
        }

        var result: [DisplayService] = []
        var usedDisplays = Set<CGDirectDisplayID>()
        var usedLocations = Set<Int>()
        for candidate in candidates.sorted(by: { $0.matchScore > $1.matchScore }) {
            guard !usedDisplays.contains(candidate.displayID),
                  !usedLocations.contains(candidate.serviceLocation) else { continue }
            usedDisplays.insert(candidate.displayID)
            usedLocations.insert(candidate.serviceLocation)
            result.append(candidate)
        }
        return result
    }

    static func read(service: IOAVService, command: UInt8) -> (current: UInt16, max: UInt16)? {
        var send = [command]
        var reply = [UInt8](repeating: 0, count: 11)
        guard communicate(service: service, send: &send, reply: &reply) else { return nil }
        let maximum = UInt16(reply[6]) * 256 + UInt16(reply[7])
        let current = UInt16(reply[8]) * 256 + UInt16(reply[9])
        guard maximum > 0, current <= maximum else { return nil }
        return (current, maximum)
    }

    static func write(service: IOAVService, command: UInt8, value: UInt16) -> Bool {
        var send = [command, UInt8(value >> 8), UInt8(value & 0xff)]
        var reply: [UInt8] = []
        return communicate(service: service, send: &send, reply: &reply)
    }

    static func checksum(seed: UInt8, data: [UInt8]) -> UInt8 {
        data.reduce(seed, ^)
    }

    private static func communicate(
        service: IOAVService,
        send: inout [UInt8],
        reply: inout [UInt8]
    ) -> Bool {
        let sevenBitAddress: UInt8 = 0x37
        let dataAddress: UInt8 = 0x51
        var packet = [UInt8(0x80 | (send.count + 1)), UInt8(send.count)] + send + [0]
        let seed = send.count == 1
            ? sevenBitAddress << 1
            : (sevenBitAddress << 1) ^ dataAddress
        packet[packet.count - 1] = checksum(seed: seed, data: Array(packet.dropLast()))

        for _ in 0..<3 {
            usleep(10_000)
            let writeResult = IOAVServiceWriteI2C(
                service,
                UInt32(sevenBitAddress),
                UInt32(dataAddress),
                &packet,
                UInt32(packet.count)
            )

            if reply.isEmpty, writeResult == kIOReturnSuccess {
                return true
            }

            if !reply.isEmpty {
                usleep(50_000)
                let readResult = IOAVServiceReadI2C(
                    service,
                    UInt32(sevenBitAddress),
                    0,
                    &reply,
                    UInt32(reply.count)
                )
                if writeResult == kIOReturnSuccess,
                   readResult == kIOReturnSuccess,
                   checksum(seed: 0x50, data: Array(reply.dropLast())) == reply.last {
                    return true
                }
            }
            usleep(20_000)
        }
        return false
    }

    private static func matchScore(
        displayID: CGDirectDisplayID,
        edidUUID: String,
        ioDisplayLocation: String,
        productName: String,
        serialNumber: Int64
    ) -> Int {
        guard let dictionary = displayInfo(displayID) else { return 0 }
        var score = 0

        if !ioDisplayLocation.isEmpty,
           let displayLocation = dictionary[kIODisplayLocationKey] as? String,
           displayLocation == ioDisplayLocation {
            score += 10
        }

        if !productName.isEmpty,
           DisplayDetector.name(from: dictionary).caseInsensitiveCompare(productName) == .orderedSame {
            score += 2
        }

        if serialNumber != 0,
           let displaySerial = numericValue(dictionary[kDisplaySerialNumber]),
           displaySerial == serialNumber {
            score += 2
        }

        if let vendor = numericValue(dictionary[kDisplayVendorID]),
           edidUUID.uppercased().hasPrefix(String(format: "%04X", vendor)) {
            score += 1
        }
        return score
    }

    private static func displayInfo(_ displayID: CGDirectDisplayID) -> NSDictionary? {
        CoreDisplay_DisplayCreateInfoDictionary(displayID)?.takeRetainedValue() as NSDictionary?
    }

    private static func numericValue(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let integer = value as? Int64 { return integer }
        if let integer = value as? Int { return Int64(integer) }
        return nil
    }

    private static func registryServices() -> [RegistryService] {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else { return [] }
        defer { IOObjectRelease(root) }

        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(
            root,
            kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively),
            &iterator
        ) == kIOReturnSuccess else { return [] }
        defer { IOObjectRelease(iterator) }

        var current = RegistryService()
        var result: [RegistryService] = []
        var serviceLocation = 0

        while case let entry = IOIteratorNext(iterator), entry != IO_OBJECT_NULL {
            defer { IOObjectRelease(entry) }
            var nameBuffer = [CChar](repeating: 0, count: 128)
            guard IORegistryEntryGetName(entry, &nameBuffer) == kIOReturnSuccess else { continue }
            let name = String(cString: nameBuffer)

            if name.contains("AppleCLCD2") || name.contains("IOMobileFramebufferShim") {
                serviceLocation += 1
                current = registryMetadata(entry: entry, serviceLocation: serviceLocation)
            } else if name.contains("DCPAVServiceProxy"), isExternal(entry: entry) {
                if let unmanaged = IOAVServiceCreateWithService(kCFAllocatorDefault, entry) {
                    current.service = unmanaged.takeRetainedValue()
                    result.append(current)
                }
            }
        }
        return result
    }

    private static func registryMetadata(entry: io_registry_entry_t, serviceLocation: Int) -> RegistryService {
        var metadata = RegistryService()
        metadata.serviceLocation = serviceLocation
        metadata.edidUUID = property(entry, key: "EDID UUID") as? String ?? ""

        var pathBuffer = [CChar](repeating: 0, count: 512)
        if IORegistryEntryGetPath(entry, kIOServicePlane, &pathBuffer) == kIOReturnSuccess {
            metadata.ioDisplayLocation = String(cString: pathBuffer)
        }

        if let attributes = property(entry, key: "DisplayAttributes") as? NSDictionary,
           let product = attributes["ProductAttributes"] as? NSDictionary {
            metadata.productName = product["ProductName"] as? String ?? ""
            metadata.serialNumber = numericValue(product["SerialNumber"]) ?? 0
        }
        return metadata
    }

    private static func isExternal(entry: io_registry_entry_t) -> Bool {
        property(entry, key: "Location") as? String == "External"
    }

    private static func property(_ entry: io_registry_entry_t, key: String) -> Any? {
        IORegistryEntryCreateCFProperty(
            entry,
            key as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively)
        )?.takeRetainedValue()
    }
}
