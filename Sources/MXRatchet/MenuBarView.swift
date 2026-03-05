import SwiftUI

struct MenuBarView: View {
    @ObservedObject var vm: MouseViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "computermouse.fill")
                    .font(.title2)
                Text("MX Master 3")
                    .font(.headline)
                Spacer()
                if vm.connected {
                    batteryView
                } else {
                    Text("Disconnected")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            if vm.connected {
                Divider()

                // Wheel Mode
                VStack(alignment: .leading, spacing: 6) {
                    Text("Wheel Mode")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("Wheel Mode", selection: Binding(
                        get: { vm.isRatchet },
                        set: { vm.setWheelMode(ratchet: $0) }
                    )) {
                        Text("Ratchet").tag(true)
                        Text("Free Spin").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // SmartShift
                Toggle("SmartShift auto-switch", isOn: Binding(
                    get: { vm.isSmartShiftEnabled },
                    set: { _ in vm.toggleSmartShift() }
                ))
                .font(.subheadline)

                // DPI
                if !vm.dpiList.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("DPI")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(vm.dpi)")
                                .font(.subheadline)
                                .monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { Double(vm.dpi) },
                                set: { vm.setDPI(snapToNearest(Int($0))) }
                            ),
                            in: Double(vm.dpiList.first ?? 200)...Double(vm.dpiList.last ?? 4000),
                            step: Double(dpiStep)
                        )
                    }
                }

                Divider()
            }

            // Footer
            HStack {
                if let error = vm.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                Spacer()
                Button("Settings\u{2026}") {
                    openWindow(id: "settings")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
        }
        .padding(16)
        .frame(width: 280)
        .onAppear { vm.fetchStatus(includeDPIList: true) }
    }

    // MARK: - Battery

    private var batteryView: some View {
        HStack(spacing: 4) {
            Image(systemName: batteryIconName)
                .foregroundStyle(batteryColor)
            Text("\(vm.batteryLevel)%")
                .font(.caption)
                .monospacedDigit()
        }
    }

    private var batteryIconName: String {
        if vm.batteryCharging { return "battery.100.bolt" }
        switch vm.batteryLevel {
        case 75...: return "battery.100"
        case 50..<75: return "battery.75"
        case 25..<50: return "battery.50"
        case 10..<25: return "battery.25"
        default: return "battery.0"
        }
    }

    private var batteryColor: Color {
        if vm.batteryCharging { return .green }
        if vm.batteryLevel <= 10 { return .red }
        if vm.batteryLevel <= 25 { return .orange }
        return .primary
    }

    // MARK: - DPI Helpers

    private var dpiStep: Int {
        guard vm.dpiList.count >= 2 else { return 50 }
        return vm.dpiList[1] - vm.dpiList[0]
    }

    private func snapToNearest(_ value: Int) -> Int {
        guard !vm.dpiList.isEmpty else { return value }
        return vm.dpiList.min(by: { abs($0 - value) < abs($1 - value) }) ?? value
    }
}
