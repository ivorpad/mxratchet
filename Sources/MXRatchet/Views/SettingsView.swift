import SwiftUI

struct SettingsView: View {
    @ObservedObject var mappingStore: MappingStore
    @State private var selectedProfileId: UUID?

    var body: some View {
        NavigationSplitView {
            ProfileListView(
                mappingStore: mappingStore,
                selectedProfileId: $selectedProfileId
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            if let id = selectedProfileId,
               let profile = mappingStore.profiles.first(where: { $0.id == id }) {
                ProfileEditorView(
                    profile: profile,
                    mappingStore: mappingStore
                )
            } else {
                Text("Select a profile")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            if selectedProfileId == nil {
                selectedProfileId = mappingStore.profiles.first?.id
            }
        }
    }
}
