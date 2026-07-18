import Combine
import CoreGraphics
import Foundation

final class BrightnessSyncController: ObservableObject {
    enum State: Equatable {
        case detecting
        case syncing
        case dellCompensating
        case paused
        case sourceUnavailable
        case targetUnavailable
        case ddcUnavailable
        case writeFailed
        case externalControlConflict

        var title: String {
            switch self {
            case .detecting: return "正在检测"
            case .syncing: return "正在跟随"
            case .dellCompensating: return "正在增强 Dell 自动亮度"
            case .paused: return "已暂停"
            case .sourceUnavailable: return "未找到 MacBook 内屏"
            case .targetUnavailable: return "未找到外接显示器"
            case .ddcUnavailable: return "外屏不支持 DDC"
            case .writeFailed: return "DDC 写入失败"
            case .externalControlConflict: return "外屏亮度被覆盖"
            }
        }
    }

    @Published private(set) var state: State = .detecting
    @Published private(set) var sourceName = "MacBook 内屏"
    @Published private(set) var targetName = "Dell 外屏"
    @Published private(set) var sourceBrightness = 0.0
    @Published private(set) var targetBrightness = 0.0
    @Published private(set) var detail = "正在查找显示器…"
    @Published private(set) var canAutoSync = false
    @Published private(set) var hasSource = false
    @Published private(set) var hasTarget = false
    @Published private(set) var brightnessKeyRoutingAvailable = false
    @Published private(set) var brightnessKeyRoutingDetail = "亮度键正在连接…"

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            if isEnabled, !oldValue { scheduleSourceSync() }
            refreshState()
        }
    }
    @Published var sensitivity: Double {
        didSet {
            defaults.set(sensitivity, forKey: Keys.sensitivity)
            scheduleSourceSync()
        }
    }
    @Published var minimumBrightness: Double {
        didSet {
            defaults.set(minimumBrightness, forKey: Keys.minimum)
            scheduleSourceSync()
            reapplyDellCompensationIfNeeded()
        }
    }
    @Published var dellCompensationEnabled: Bool {
        didSet {
            defaults.set(dellCompensationEnabled, forKey: Keys.dellCompensationEnabled)
            if dellCompensationEnabled, !oldValue {
                lastAppWrittenTarget = nil
                defaults.removeObject(forKey: Keys.lastAppWrittenTarget)
                queue.async { [weak self] in self?.pollDellAutoBrightness(force: true) }
            }
            refreshState()
        }
    }
    @Published var dellCompensation: Double {
        didSet {
            defaults.set(dellCompensation, forKey: Keys.dellCompensation)
            reapplyDellCompensationIfNeeded()
        }
    }

    private enum Keys {
        static let enabled = "syncEnabled"
        static let sensitivity = "sensitivity"
        static let minimum = "minimumBrightness"
        static let dellCompensationEnabled = "dellCompensationEnabled"
        static let dellCompensation = "dellCompensation"
        static let lastAppWrittenTarget = "lastAppWrittenTarget"
        static let lastDellRawTarget = "lastDellRawTarget"
    }

    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "BrightnessFollow.sync")
    private var timer: Timer?
    private var sourceDisplayID: CGDirectDisplayID?
    private var targetService: DDC.DisplayService?
    private var targetMaximum: UInt16 = 100
    private var lastSourceBrightness: Double?
    private var consecutiveWriteFailures = 0
    private var tickCount = 0
    private var pendingWrite: DispatchWorkItem?
    private var pendingSourceSync: DispatchWorkItem?
    private var lastAppWrittenTarget: Double?
    private var lastDellRawTarget: Double?
    private var lastConfirmedTarget: Double?
    private var expectedTargetAfterWrite: Double?
    private var routingTargetDisplayID: CGDirectDisplayID?

    init(defaults: UserDefaults = .standard, startsTimer: Bool = true) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        sensitivity = defaults.object(forKey: Keys.sensitivity) as? Double ?? 1.0
        minimumBrightness = defaults.object(forKey: Keys.minimum) as? Double ?? 0.10
        dellCompensationEnabled = defaults.object(forKey: Keys.dellCompensationEnabled) as? Bool ?? false
        dellCompensation = defaults.object(forKey: Keys.dellCompensation) as? Double ?? 0.15
        lastAppWrittenTarget = defaults.object(forKey: Keys.lastAppWrittenTarget) as? Double
        lastDellRawTarget = defaults.object(forKey: Keys.lastDellRawTarget) as? Double
        detectDisplays()
        if startsTimer { startTimer() }
    }

    deinit { timer?.invalidate() }

    func detectDisplays() {
        state = .detecting
        detail = "正在查找显示器…"
        queue.async { [weak self] in self?.performDetection() }
    }

    func setTargetBrightness(_ normalized: Double) {
        let clamped = min(1, max(0, normalized))
        targetBrightness = clamped
        pendingWrite?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.writeTarget(clamped) }
        pendingWrite = work
        queue.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    func setBrightnessKeyRoutingStatus(available: Bool, detail: String) {
        if Thread.isMainThread {
            brightnessKeyRoutingAvailable = available
            brightnessKeyRoutingDetail = detail
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.setBrightnessKeyRoutingStatus(available: available, detail: detail)
            }
        }
    }

    func canRouteBrightnessKey(to displayID: CGDirectDisplayID) -> Bool {
        routingTargetDisplayID == displayID
    }

    func routeBrightnessKey(
        to displayID: CGDirectDisplayID,
        direction: BrightnessKeyDirection,
        fine: Bool
    ) {
        guard canRouteBrightnessKey(to: displayID) else { return }
        queue.async { [weak self] in
            self?.adjustExternalBrightness(direction: direction, fine: fine)
        }
    }

    func noteRoutedInternalBrightnessKey() {
        scheduleSourceSync(after: 0.12)
    }

    private func scheduleSourceSync(after delay: TimeInterval = 0.12) {
        guard isEnabled else { return }
        pendingSourceSync?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.syncCurrentSource() }
        pendingSourceSync = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func syncCurrentSource() {
        guard isEnabled,
              let sourceDisplayID,
              let targetService,
              let source = DisplayDetector.brightness(of: sourceDisplayID) else { return }
        let normalized = Double(source)
        lastSourceBrightness = normalized
        DispatchQueue.main.async { [weak self] in self?.sourceBrightness = normalized }
        syncTarget(toSourceBrightness: normalized, using: targetService)
    }

    private func syncTarget(
        toSourceBrightness sourceBrightness: Double,
        using service: DDC.DisplayService,
        knownCurrentTarget: Double? = nil
    ) {
        guard isEnabled else { return }
        let desired = BrightnessMapper.following(
            sourceBrightness: sourceBrightness,
            sensitivity: sensitivity,
            minimum: minimumBrightness
        )
        let current = knownCurrentTarget ?? lastConfirmedTarget
        expectedTargetAfterWrite = desired

        if let current,
           BrightnessMapper.ddcValue(normalized: desired, maximum: targetMaximum)
            == BrightnessMapper.ddcValue(normalized: current, maximum: targetMaximum) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.targetBrightness = current
                self.refreshState()
                self.detail = "外屏已与内屏当前亮度一致：\(Self.percent(desired))。"
            }
            return
        }
        writeTarget(desired, using: service)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            self?.queue.async { self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func performDetection() {
        let displays = DisplayDetector.onlineDisplays()
        guard let target = DisplayDetector.preferredExternalDisplay(from: displays) else {
            publishDetectionFailure(
                .targetUnavailable,
                detail: "当前只检测到内屏；连接或唤醒 Dell 后会自动重试。",
                displays: displays
            )
            return
        }
        let services = DDC.matchedServices(displayIDs: displays.filter { !$0.isBuiltIn }.map(\.id))
        guard let service = services.first(where: { $0.displayID == target.id }) else {
            publishDetectionFailure(
                .ddcUnavailable,
                detail: "已检测到 \(target.name)，但连接链路没有暴露 DDC/CI。",
                displays: displays,
                detectedTargetName: target.name
            )
            return
        }
        guard let targetValue = DDC.read(service: service.service, command: DDC.luminanceVCP) else {
            publishDetectionFailure(
                .ddcUnavailable,
                detail: "已检测到 \(target.name)，但无法读取硬件亮度。",
                displays: displays,
                detectedTargetName: target.name
            )
            return
        }

        let targetNormalized = Double(targetValue.current) / Double(targetValue.max)
        targetService = service
        targetMaximum = targetValue.max
        lastConfirmedTarget = targetNormalized
        expectedTargetAfterWrite = nil
        consecutiveWriteFailures = 0

        guard let source = DisplayDetector.builtInDisplay(from: displays),
              let sourceValue = DisplayDetector.brightness(of: source.id) else {
            sourceDisplayID = nil
            lastSourceBrightness = nil
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.sourceName = "MacBook 内屏"
                self.sourceBrightness = 0
                self.targetName = target.name
                self.targetBrightness = targetNormalized
                self.routingTargetDisplayID = target.id
                self.canAutoSync = false
                self.hasSource = false
                self.hasTarget = true
                self.refreshState()
            }
            handleDellReading(targetNormalized, service: service, force: false)
            return
        }

        sourceDisplayID = source.id
        lastSourceBrightness = Double(sourceValue)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.sourceName = source.name
            self.targetName = target.name
            self.sourceBrightness = Double(sourceValue)
            self.targetBrightness = targetNormalized
            self.routingTargetDisplayID = target.id
            self.canAutoSync = true
            self.hasSource = true
            self.hasTarget = true
            self.refreshState()
        }
        syncTarget(
            toSourceBrightness: Double(sourceValue),
            using: service,
            knownCurrentTarget: targetNormalized
        )
    }

    private func tick() {
        tickCount += 1
        guard let targetService else {
            if tickCount.isMultiple(of: 7) {
                DispatchQueue.main.async { [weak self] in self?.detectDisplays() }
            }
            return
        }
        guard let sourceDisplayID else {
            if tickCount.isMultiple(of: 4) {
                pollDellAutoBrightness(force: false)
            }
            if tickCount.isMultiple(of: 12),
               DisplayDetector.builtInDisplay(from: DisplayDetector.onlineDisplays()) != nil {
                DispatchQueue.main.async { [weak self] in self?.detectDisplays() }
            }
            return
        }
        guard let source = DisplayDetector.brightness(of: sourceDisplayID) else {
            DispatchQueue.main.async { [weak self] in self?.detectDisplays() }
            return
        }

        let newSource = Double(source)
        let previousSource = lastSourceBrightness ?? newSource
        let delta = newSource - previousSource
        lastSourceBrightness = newSource
        DispatchQueue.main.async { [weak self] in self?.sourceBrightness = newSource }

        if tickCount.isMultiple(of: 4) {
            pollTargetReadback(using: targetService)
        }

        guard isEnabled, abs(delta) >= 0.002 else { return }
        syncTarget(toSourceBrightness: newSource, using: targetService)
    }

    private func writeTarget(_ normalized: Double, using service: DDC.DisplayService? = nil) {
        guard let service = service ?? targetService else { return }
        let value = BrightnessMapper.ddcValue(normalized: normalized, maximum: targetMaximum)
        let requested = Double(value) / Double(max(targetMaximum, 1))
        expectedTargetAfterWrite = requested

        guard DDC.write(service: service.service, command: DDC.luminanceVCP, value: value) else {
            publishWriteFailure("DDC 写入失败；请确认显示器 DDC/CI 已开启。")
            return
        }

        usleep(40_000)
        guard var readback = DDC.read(service: service.service, command: DDC.luminanceVCP) else {
            publishWriteFailure("亮度已经写出，但无法回读确认；不会把缓存值当作成功。")
            return
        }

        var confirmed = Double(readback.current) / Double(readback.max)
        var oneStep = 0.5 / Double(max(readback.max, 1))
        if abs(confirmed - requested) > oneStep {
            usleep(120_000)
            if let retry = DDC.read(service: service.service, command: DDC.luminanceVCP) {
                readback = retry
                confirmed = Double(retry.current) / Double(retry.max)
                oneStep = 0.5 / Double(max(retry.max, 1))
            }
        }

        targetMaximum = readback.max
        lastConfirmedTarget = confirmed

        guard abs(confirmed - requested) <= oneStep else {
            consecutiveWriteFailures = 0
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.targetBrightness = confirmed
                self.state = .externalControlConflict
                self.detail = "请求 \(Self.percent(requested))，回读却是 \(Self.percent(confirmed))；Dell 自动亮度或其他调光软件正在覆盖。"
            }
            return
        }

        consecutiveWriteFailures = 0
        lastAppWrittenTarget = confirmed
        expectedTargetAfterWrite = confirmed
        defaults.set(confirmed, forKey: Keys.lastAppWrittenTarget)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.targetBrightness = confirmed
            self.refreshState()
            self.detail = "DDC 回读已确认，外屏当前亮度 \(Self.percent(confirmed))。"
        }
    }

    private func adjustExternalBrightness(direction: BrightnessKeyDirection, fine: Bool) {
        guard let targetService,
              let value = DDC.read(service: targetService.service, command: DDC.luminanceVCP) else {
            publishWriteFailure("无法读取外屏当前亮度，亮度键没有执行。")
            return
        }

        targetMaximum = value.max
        let current = Double(value.current) / Double(value.max)
        lastConfirmedTarget = current
        let next = BrightnessMapper.adjustedByBrightnessKey(
            current: current,
            direction: direction,
            fine: fine,
            minimum: minimumBrightness
        )
        guard BrightnessMapper.ddcValue(normalized: next, maximum: value.max) != value.current else {
            DispatchQueue.main.async { [weak self] in self?.targetBrightness = current }
            return
        }
        writeTarget(next, using: targetService)
    }

    private func pollTargetReadback(using service: DDC.DisplayService) {
        guard let value = DDC.read(service: service.service, command: DDC.luminanceVCP) else { return }
        targetMaximum = value.max
        let normalized = Double(value.current) / Double(value.max)
        lastConfirmedTarget = normalized

        let oneStep = 0.5 / Double(max(value.max, 1))
        let wasOverridden = expectedTargetAfterWrite.map { abs($0 - normalized) > oneStep } ?? false
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.targetBrightness = normalized
            if wasOverridden {
                self.state = .externalControlConflict
                self.detail = "外屏真实亮度已变为 \(Self.percent(normalized))；检测到 Dell 自动亮度、DDPM 或其他控制源改写。"
            } else if self.state == .externalControlConflict {
                self.refreshState()
            }
        }
    }

    private func publishWriteFailure(_ detail: String) {
        consecutiveWriteFailures += 1
        DispatchQueue.main.async { [weak self] in
            self?.state = .writeFailed
            self?.detail = detail
        }
    }

    private func publishDetectionFailure(
        _ state: State,
        detail: String,
        displays: [DetectedDisplay] = [],
        detectedTargetName: String? = nil
    ) {
        let detectedSource = DisplayDetector.builtInDisplay(from: displays)
        let detectedSourceBrightness = detectedSource.flatMap { DisplayDetector.brightness(of: $0.id) }
        sourceDisplayID = nil
        targetService = nil
        lastSourceBrightness = nil
        lastConfirmedTarget = nil
        expectedTargetAfterWrite = nil
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.state = state
            self.detail = detail
            self.sourceName = detectedSource?.name ?? "MacBook 内屏"
            self.sourceBrightness = Double(detectedSourceBrightness ?? 0)
            self.targetName = detectedTargetName ?? "未连接外屏"
            self.targetBrightness = 0
            self.canAutoSync = false
            self.hasSource = detectedSourceBrightness != nil
            self.hasTarget = false
            self.routingTargetDisplayID = nil
        }
    }

    private func refreshState() {
        guard targetService != nil else { return }
        if sourceDisplayID != nil {
            state = isEnabled ? .syncing : .paused
            detail = "外屏按当前内屏亮度直接跟随；自动变化和手动亮度键都会同步。"
        } else if dellCompensationEnabled {
            state = .dellCompensating
            detail = "保持 Dell 自动亮度开启；工具会叠加补偿并守住最低值。"
        } else {
            state = .sourceUnavailable
            detail = "当前是合盖模式；可增强 Dell 自动亮度，或直接使用外屏滑杆。"
        }
    }

    private func pollDellAutoBrightness(force: Bool) {
        guard sourceDisplayID == nil, let targetService,
              let value = DDC.read(service: targetService.service, command: DDC.luminanceVCP) else { return }
        targetMaximum = value.max
        let normalized = Double(value.current) / Double(value.max)
        handleDellReading(normalized, service: targetService, force: force)
    }

    private func handleDellReading(_ raw: Double, service: DDC.DisplayService, force: Bool) {
        lastConfirmedTarget = raw
        DispatchQueue.main.async { [weak self] in self?.targetBrightness = raw }
        guard dellCompensationEnabled else { return }

        let oneStep = 0.5 / Double(max(targetMaximum, 1))
        if !force, let lastAppWrittenTarget,
           abs(raw - lastAppWrittenTarget) <= oneStep {
            return
        }

        lastDellRawTarget = raw
        defaults.set(raw, forKey: Keys.lastDellRawTarget)
        let compensated = BrightnessMapper.dellCompensated(
            raw: raw,
            offset: dellCompensation,
            minimum: minimumBrightness
        )
        guard BrightnessMapper.ddcValue(normalized: compensated, maximum: targetMaximum)
                != BrightnessMapper.ddcValue(normalized: raw, maximum: targetMaximum) else { return }
        writeTarget(compensated, using: service)
    }

    private func reapplyDellCompensationIfNeeded() {
        guard dellCompensationEnabled, let raw = lastDellRawTarget else { return }
        let compensated = BrightnessMapper.dellCompensated(
            raw: raw,
            offset: dellCompensation,
            minimum: minimumBrightness
        )
        queue.async { [weak self] in self?.writeTarget(compensated) }
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
