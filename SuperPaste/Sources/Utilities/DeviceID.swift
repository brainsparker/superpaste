import Foundation

/// Stable device identifier generated once and persisted in UserDefaults.
/// Sent with every API request so the server can track trial periods and usage.
enum DeviceID {
    static var current: String {
        if let id = UserDefaults.standard.string(forKey: "deviceId") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "deviceId")
        return id
    }
}
