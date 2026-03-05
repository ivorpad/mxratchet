import Foundation
import Combine

class MappingStore: ObservableObject {
    @Published var profiles: [AppProfile] = []

    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MXRatchet")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("profiles.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([AppProfile].self, from: data),
              !decoded.isEmpty else {
            profiles = [AppProfile.makeDefault()]
            return
        }
        profiles = decoded
        if !profiles.contains(where: { $0.bundleId == "*" }) {
            profiles.insert(AppProfile.makeDefault(), at: 0)
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(profiles) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func activeProfile(for bundleId: String) -> AppProfile {
        if let specific = profiles.first(where: { $0.bundleId == bundleId }) {
            return specific
        }
        return profiles.first(where: { $0.bundleId == "*" }) ?? AppProfile.makeDefault()
    }

    func updateProfile(_ profile: AppProfile) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
        save()
    }

    func deleteProfile(_ profile: AppProfile) {
        guard profile.bundleId != "*" else { return }
        profiles.removeAll { $0.id == profile.id }
        save()
    }

    @discardableResult
    func addProfile(bundleId: String, displayName: String, iconPath: String? = nil) -> AppProfile {
        let profile = AppProfile(
            id: UUID(),
            bundleId: bundleId,
            displayName: displayName,
            appIconPath: iconPath,
            buttons: ButtonConfig.defaultButtons,
            gesture: .default
        )
        profiles.append(profile)
        save()
        return profile
    }
}
