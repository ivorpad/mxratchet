import SwiftUI
import Shared

@MainActor
class MouseViewModel: ObservableObject {
    @Published var batteryLevel: Int = 0
    @Published var batteryCharging: Bool = false
    @Published var wheelMode: Int = 2
    @Published var autoDisengage: Int = 0xFF
    @Published var dpi: Int = 1000
    @Published var dpiList: [Int] = []
    @Published var connected: Bool = false
    @Published var error: String?
    @Published var thumbWheelInverted: Bool = false
    @Published var hiResScrollEnabled: Bool = false
    @Published var scrollInverted: Bool = false

    let client = HelperClient()
    private var pollTimer: Timer?
    private var dpiListFetched = false
    private var dpiDebounceTask: Task<Void, Never>?

    var isRatchet: Bool { wheelMode == 2 }
    var isSmartShiftEnabled: Bool { autoDisengage != 0xFF }

    init() {
        startPolling()
    }

    func startPolling() {
        fetchStatus(includeDPIList: true)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fetchStatus()
            }
        }
    }

    func fetchStatus(includeDPIList: Bool = false) {
        Task {
            do {
                let resp = try await client.getStatus(includeDPIList: includeDPIList || !dpiListFetched)
                if resp.ok, let data = resp.data {
                    batteryLevel = data.batteryLevel
                    batteryCharging = data.batteryCharging
                    wheelMode = data.wheelMode
                    autoDisengage = data.autoDisengage
                    dpi = data.dpi
                    if let list = data.dpiList, !list.isEmpty {
                        dpiList = list
                        dpiListFetched = true
                    }
                    connected = true
                    error = nil
                } else {
                    connected = false
                    error = resp.error
                }
            } catch {
                connected = false
                self.error = error.localizedDescription
            }
        }
    }

    func setWheelMode(ratchet: Bool) {
        let mode = ratchet ? 2 : 1
        let ad = ratchet ? 0xFF : 0
        wheelMode = mode
        autoDisengage = ad
        Task {
            let resp = try? await client.setWheelMode(mode, autoDisengage: ad)
            if let data = resp?.data {
                wheelMode = data.wheelMode
                autoDisengage = data.autoDisengage
            }
        }
    }

    func toggleSmartShift() {
        let newAD = autoDisengage == 0xFF ? 30 : 0xFF
        autoDisengage = newAD
        Task {
            let resp = try? await client.setWheelMode(wheelMode, autoDisengage: newAD)
            if let data = resp?.data {
                autoDisengage = data.autoDisengage
            }
        }
    }

    func setDPI(_ newDPI: Int) {
        dpi = newDPI
        dpiDebounceTask?.cancel()
        dpiDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }
            let _ = try? await client.setDPI(newDPI)
        }
    }

    func setThumbWheelInverted(_ inverted: Bool) {
        thumbWheelInverted = inverted
        Task {
            let _ = try? await client.setThumbWheel(inverted: inverted)
        }
    }

    func setHiResScroll(_ enabled: Bool) {
        hiResScrollEnabled = enabled
        Task {
            let _ = try? await client.setHiResScroll(hiRes: enabled, inverted: scrollInverted)
        }
    }

    func setScrollInverted(_ inverted: Bool) {
        scrollInverted = inverted
        Task {
            let _ = try? await client.setHiResScroll(hiRes: hiResScrollEnabled, inverted: inverted)
        }
    }
}
