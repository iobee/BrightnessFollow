import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: BrightnessSyncController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            displayCard

            if controller.hasTarget {
                if controller.canAutoSync {
                    Toggle("直接跟随 MacBook 当前亮度", isOn: $controller.isEnabled)
                        .toggleStyle(.switch)
                } else {
                    Toggle("增强 Dell 自动亮度（实验）", isOn: $controller.dellCompensationEnabled)
                        .toggleStyle(.switch)
                }

                VStack(alignment: .leading, spacing: 7) {
                    valueHeader("外屏实际亮度", value: percent(controller.targetBrightness))
                    Slider(
                        value: Binding(
                            get: { controller.targetBrightness },
                            set: { controller.setTargetBrightness($0) }
                        ),
                        in: 0...1
                    )
                }

                if controller.canAutoSync {
                    VStack(alignment: .leading, spacing: 7) {
                        valueHeader("外屏亮度比例", value: "\(Int((controller.sensitivity * 100).rounded()))%")
                        Slider(value: $controller.sensitivity, in: 0.5...1.5, step: 0.05)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        valueHeader("Dell 亮度补偿", value: "+\(percent(controller.dellCompensation))")
                        Slider(value: $controller.dellCompensation, in: 0...0.40, step: 0.01)
                            .disabled(!controller.dellCompensationEnabled)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    valueHeader("最低外屏亮度", value: percent(controller.minimumBrightness))
                    Slider(value: $controller.minimumBrightness, in: 0...0.5, step: 0.01)
                }

                Text(instructionText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: controller.brightnessKeyRoutingAvailable ? "keyboard.badge.ellipsis" : "exclamationmark.triangle")
                        .foregroundStyle(controller.brightnessKeyRoutingAvailable ? Color.green : Color.orange)
                    Text(controller.brightnessKeyRoutingDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if !controller.brightnessKeyRoutingAvailable {
                        Button("打开设置") { openAccessibilitySettings() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
            } else {
                Text("Dell 重新连接或唤醒后会自动检测，并立即跟随内屏当前亮度。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("重新检测") { controller.detectDisplays() }
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(18)
        .frame(width: 350)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 22))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("亮度跟随")
                    .font(.headline)
                Text(controller.state.title)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
            Spacer()
        }
    }

    private var displayCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            displayRow(
                name: controller.sourceName,
                value: controller.hasSource ? controller.sourceBrightness : nil,
                symbol: "laptopcomputer"
            )
            Divider()
            displayRow(
                name: controller.targetName,
                value: controller.hasTarget ? controller.targetBrightness : nil,
                symbol: "display"
            )
            Text(controller.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
    }

    private func displayRow(name: String, value: Double?, symbol: String) -> some View {
        HStack {
            Image(systemName: symbol)
                .frame(width: 20)
            Text(name)
                .lineLimit(1)
            Spacer()
            Text(value.map(percent) ?? "—")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func valueHeader(_ title: String, value: String) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Text(value).font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch controller.state {
        case .syncing, .dellCompensating: return .green
        case .paused, .detecting: return .secondary
        default: return .orange
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private var instructionText: String {
        if controller.canAutoSync {
            return "请关闭 Dell 自带自动亮度。内屏无论自动变化还是手动调节，外屏都会直接跟到当前亮度；比例可用于微调两块屏幕的观感差异。"
        }
        return "增强模式需要保持 Dell 自动亮度开启；若出现亮度来回跳动，请关闭增强模式并改用手动滑杆。"
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
