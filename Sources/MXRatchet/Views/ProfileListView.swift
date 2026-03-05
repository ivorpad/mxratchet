import SwiftUI
import AppKit

struct ProfileListView: View {
    @ObservedObject var mappingStore: MappingStore
    @Binding var selectedProfileId: UUID?

    var body: some View {
        List(selection: $selectedProfileId) {
            ForEach(mappingStore.profiles) { profile in
                HStack(spacing: 8) {
                    profileIcon(for: profile)
                        .frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(profile.displayName)
                            .font(.body)
                        if profile.bundleId != "*" {
                            Text(profile.bundleId)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tag(profile.id)
                .contextMenu {
                    if profile.bundleId != "*" {
                        Button("Delete", role: .destructive) {
                            if selectedProfileId == profile.id {
                                selectedProfileId = mappingStore.profiles.first?.id
                            }
                            mappingStore.deleteProfile(profile)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: addProfile) {
                    Image(systemName: "plus")
                }
            }
        }
    }

    @ViewBuilder
    private func profileIcon(for profile: AppProfile) -> some View {
        if profile.bundleId == "*" {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
        } else if let path = profile.appIconPath,
                  let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else if let icon = appIcon(for: profile.bundleId) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app")
                .foregroundStyle(.secondary)
        }
    }

    private func appIcon(for bundleId: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func addProfile() {
        let panel = NSOpenPanel()
        panel.title = "Select Application"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let bundle = Bundle(url: url),
              let bundleId = bundle.bundleIdentifier else { return }

        let name = FileManager.default.displayName(atPath: url.path)

        // Don't add duplicates
        guard !mappingStore.profiles.contains(where: { $0.bundleId == bundleId }) else {
            selectedProfileId = mappingStore.profiles.first(where: { $0.bundleId == bundleId })?.id
            return
        }

        let iconPath = bundle.pathForImageResource(
            bundle.infoDictionary?["CFBundleIconFile"] as? String ?? ""
        )

        let profile = mappingStore.addProfile(
            bundleId: bundleId,
            displayName: name,
            iconPath: iconPath
        )
        selectedProfileId = profile.id
    }
}
