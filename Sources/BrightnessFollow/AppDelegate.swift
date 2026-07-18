import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let didShowWelcomeKey = "didShowWelcomePopover"
    private let controller = BrightnessSyncController()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var brightnessKeyRouter: BrightnessKeyRouter?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let isQASticky = CommandLine.arguments.contains("--qa-sticky")
        popover.behavior = isQASticky ? .applicationDefined : .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 350, height: 340)
        popover.contentViewController = NSHostingController(rootView: ContentView(controller: controller))

        controller.$hasTarget
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasTarget in
                guard let self else { return }
                self.popover.contentSize = self.preferredPopoverSize(hasTarget: hasTarget)
                self.reanchorPopoverIfShown()
            }
            .store(in: &cancellables)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "亮度跟随")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        statusItem = item

        let keyRouter = BrightnessKeyRouter(
            canControlExternal: { [weak controller] displayID in
                controller?.canRouteBrightnessKey(to: displayID) ?? false
            },
            adjustExternal: { [weak controller] displayID, direction, fine in
                controller?.routeBrightnessKey(to: displayID, direction: direction, fine: fine)
            },
            noteInternalKey: { [weak controller] in
                controller?.noteRoutedInternalBrightnessKey()
            },
            statusChanged: { [weak controller] available, detail in
                controller?.setBrightnessKeyRoutingStatus(available: available, detail: detail)
            }
        )
        brightnessKeyRouter = keyRouter
        keyRouter.start(promptForPermission: true)

        if isQASticky {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.showPopover()
            }
        } else if !UserDefaults.standard.bool(forKey: Self.didShowWelcomeKey) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.showPopover()
                if self?.popover.isShown == true {
                    UserDefaults.standard.set(true, forKey: Self.didShowWelcomeKey)
                }
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        brightnessKeyRouter?.start(promptForPermission: false)
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        popover.contentSize = preferredPopoverSize(hasTarget: controller.hasTarget)
        button.window?.layoutIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        DispatchQueue.main.async { [weak self] in self?.removeUnexpectedPopoverGap() }
    }

    private func preferredPopoverSize(hasTarget: Bool) -> NSSize {
        NSSize(width: 350, height: hasTarget ? 560 : 340)
    }

    private func reanchorPopoverIfShown() {
        guard popover.isShown, let button = statusItem?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        DispatchQueue.main.async { [weak self] in self?.removeUnexpectedPopoverGap() }
    }

    private func removeUnexpectedPopoverGap() {
        guard popover.isShown,
              let button = statusItem?.button,
              let buttonWindow = button.window,
              let popoverWindow = popover.contentViewController?.view.window else { return }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let anchorRect = buttonWindow.convertToScreen(buttonRectInWindow)
        let currentFrame = popoverWindow.frame
        let verticalGap = anchorRect.minY - currentFrame.maxY
        guard verticalGap > 12 else { return }

        let availableFrame = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? anchorRect
        var origin = currentFrame.origin
        origin.x = min(
            max(anchorRect.midX - currentFrame.width / 2, availableFrame.minX),
            availableFrame.maxX - currentFrame.width
        )
        origin.y = max(availableFrame.minY, anchorRect.minY - currentFrame.height - 4)
        popoverWindow.setFrameOrigin(origin)
    }

    @objc private func screenConfigurationChanged() {
        controller.detectDisplays()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.reanchorPopoverIfShown()
        }
    }
}
