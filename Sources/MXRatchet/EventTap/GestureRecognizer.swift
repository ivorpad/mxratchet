import Foundation

class GestureRecognizer {
    private let mappingStore: MappingStore
    private let appMonitor: ActiveAppMonitor
    private var tracking = false
    private var accumulatedDX: Double = 0
    private var accumulatedDY: Double = 0

    private let swipeThreshold: Double = 50.0

    init(mappingStore: MappingStore, appMonitor: ActiveAppMonitor) {
        self.mappingStore = mappingStore
        self.appMonitor = appMonitor
    }

    func buttonDown() {
        tracking = true
        accumulatedDX = 0
        accumulatedDY = 0
    }

    func addDelta(dx: Double, dy: Double) {
        guard tracking else { return }
        accumulatedDX += dx
        accumulatedDY += dy
    }

    func buttonUp() {
        guard tracking else { return }
        tracking = false

        let action = resolveDirection()
        if case .passthrough = action { return }
        ActionExecutor.execute(action)
    }

    private func resolveDirection() -> ButtonAction {
        let bundleId = appMonitor.frontmostBundleId
        let profile = mappingStore.activeProfile(for: bundleId)
        let gesture = profile.gesture

        let absDX = abs(accumulatedDX)
        let absDY = abs(accumulatedDY)

        // If movement is below threshold, it's a tap
        if absDX < swipeThreshold && absDY < swipeThreshold {
            return gesture.tap
        }

        // Dominant axis determines direction
        if absDY > absDX {
            return accumulatedDY < 0 ? gesture.swipeUp : gesture.swipeDown
        } else {
            return accumulatedDX < 0 ? gesture.swipeLeft : gesture.swipeRight
        }
    }
}
