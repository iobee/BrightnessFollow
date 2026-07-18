import AppKit
import ApplicationServices
import CoreGraphics

private let systemDefinedEventType = CGEventType(rawValue: 14)!

enum BrightnessKeyDirection: Equatable {
    case increase
    case decrease

    var sign: Double {
        switch self {
        case .increase: return 1
        case .decrease: return -1
        }
    }
}

struct BrightnessKeyEvent: Equatable {
    enum Phase: Equatable {
        case pressed
        case released
    }

    let direction: BrightnessKeyDirection
    let phase: Phase
    let isFineAdjustment: Bool

    static func parse(data1: Int, modifierFlags: NSEvent.ModifierFlags) -> BrightnessKeyEvent? {
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let keyState = (data1 & 0x0000_FF00) >> 8

        let direction: BrightnessKeyDirection
        switch keyCode {
        case 2: direction = .increase
        case 3: direction = .decrease
        default: return nil
        }

        let phase: Phase
        switch keyState {
        case 0x0A: phase = .pressed
        case 0x0B: phase = .released
        default: return nil
        }

        return BrightnessKeyEvent(
            direction: direction,
            phase: phase,
            isFineAdjustment: modifierFlags.contains([.option, .shift])
        )
    }
}

final class BrightnessKeyRouter {
    typealias CanControlExternal = (CGDirectDisplayID) -> Bool
    typealias AdjustExternal = (CGDirectDisplayID, BrightnessKeyDirection, Bool) -> Void
    typealias NoteInternalKey = () -> Void
    typealias StatusChanged = (Bool, String) -> Void

    private let canControlExternal: CanControlExternal
    private let adjustExternal: AdjustExternal
    private let noteInternalKey: NoteInternalKey
    private let statusChanged: StatusChanged

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var didRequestPermission = false

    init(
        canControlExternal: @escaping CanControlExternal,
        adjustExternal: @escaping AdjustExternal,
        noteInternalKey: @escaping NoteInternalKey,
        statusChanged: @escaping StatusChanged
    ) {
        self.canControlExternal = canControlExternal
        self.adjustExternal = adjustExternal
        self.noteInternalKey = noteInternalKey
        self.statusChanged = statusChanged
    }

    deinit {
        stop()
    }

    func start(promptForPermission: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            statusChanged(true, "亮度键已按鼠标所在屏幕分流。")
            return
        }

        let eventMask = CGEventMask(1) << systemDefinedEventType.rawValue
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.eventTapCallback,
            userInfo: userInfo
        ) else {
            if promptForPermission, !didRequestPermission {
                didRequestPermission = true
                let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
            }
            statusChanged(false, "需要开启辅助功能权限，才能拦截并分流亮度键。")
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            statusChanged(false, "亮度键监听启动失败，请重新打开应用。")
            return
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        statusChanged(true, "亮度键已按鼠标所在屏幕分流。")
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let router = Unmanaged<BrightnessKeyRouter>.fromOpaque(userInfo).takeUnretainedValue()
        return router.handle(type: type, event: event)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == systemDefinedEventType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8,
              let brightnessEvent = BrightnessKeyEvent.parse(
                data1: nsEvent.data1,
                modifierFlags: nsEvent.modifierFlags
              ),
              let displayID = displayUnderMouse() else {
            return Unmanaged.passUnretained(event)
        }

        if CGDisplayIsBuiltin(displayID) != 0 {
            if brightnessEvent.phase == .pressed {
                noteInternalKey()
            }
            return Unmanaged.passUnretained(event)
        }

        guard canControlExternal(displayID) else {
            return Unmanaged.passUnretained(event)
        }

        if brightnessEvent.phase == .pressed {
            adjustExternal(displayID, brightnessEvent.direction, brightnessEvent.isFineAdjustment)
        }
        return nil
    }

    private func displayUnderMouse() -> CGDirectDisplayID? {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }),
              let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return screenNumber.uint32Value
    }
}
