import SwiftUI

@main
struct MXRatchetApp: App {
    @StateObject private var vm = MouseViewModel()
    @StateObject private var mappingStore = MappingStore()
    @StateObject private var appMonitor = ActiveAppMonitor()
    @State private var eventTapStarted = false

    // Keep alive for the lifetime of the app
    private static var sharedEventTap: EventTapService?

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(vm: vm)
                .onAppear {
                    if !eventTapStarted {
                        eventTapStarted = true
                        let _ = EventTapService.checkAccessibility()
                        let service = EventTapService(mappingStore: mappingStore, appMonitor: appMonitor)
                        service.start()
                        MXRatchetApp.sharedEventTap = service
                    }
                }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "computermouse")
                if vm.connected {
                    Text("\(vm.batteryLevel)%")
                }
            }
        }
        .menuBarExtraStyle(.window)

        Window("MXRatchet Settings", id: "settings") {
            SettingsView(mappingStore: mappingStore)
        }
    }
}
