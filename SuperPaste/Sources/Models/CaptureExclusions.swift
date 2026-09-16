import Combine
import Foundation

@MainActor
final class CaptureExclusions: ObservableObject {
    @Published private(set) var bundleIDs: [String]
    private let defaults: UserDefaults
    private static let key = "excludedCaptureBundleIDs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bundleIDs = Array(Set((defaults.stringArray(forKey: Self.key) ?? []).map { $0.lowercased() })).sorted()
    }

    func contains(_ bundleID: String) -> Bool {
        bundleIDs.contains(bundleID.lowercased())
    }

    func setExcluded(_ excluded: Bool, bundleID: String) {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !id.isEmpty else { return }
        var ids = Set(bundleIDs)
        if excluded { ids.insert(id) } else { ids.remove(id) }
        bundleIDs = ids.sorted()
        defaults.set(bundleIDs, forKey: Self.key)
    }
}
