import Foundation

enum ClipboardSettings {
    static let historyLimitKey = "historyLimit"
    static let excludedApplicationBundleIdentifiersKey = "excludedApplicationBundleIdentifiers"
    static let defaultHistoryLimit = 500
    static let starterExcludedBundleIdentifiers = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.lastpass.LastPass",
        "com.dashlane.Dashlane",
        "com.bitwarden.desktop"
    ]

    static var historyLimit: Int {
        let storedLimit = UserDefaults.standard.object(forKey: historyLimitKey) as? Int
        return max(1, storedLimit ?? defaultHistoryLimit)
    }

    static var excludedApplicationBundleIdentifiers: [String] {
        guard let data = UserDefaults.standard.data(forKey: excludedApplicationBundleIdentifiersKey),
              let identifiers = try? JSONDecoder().decode([String].self, from: data) else {
            return starterExcludedBundleIdentifiers
        }
        return identifiers
    }

    static func setExcludedApplicationBundleIdentifiers(_ identifiers: [String]) {
        let normalizedIdentifiers = Array(Set(identifiers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }))
            .sorted()
        let data = try? JSONEncoder().encode(normalizedIdentifiers)
        UserDefaults.standard.set(data, forKey: excludedApplicationBundleIdentifiersKey)
    }

    static func shouldCapture(frontmostApplicationBundleIdentifier: String?) -> Bool {
        shouldCapture(
            frontmostApplicationBundleIdentifier: frontmostApplicationBundleIdentifier,
            excludedBundleIdentifiers: excludedApplicationBundleIdentifiers
        )
    }

    static func shouldCapture(
        frontmostApplicationBundleIdentifier: String?,
        excludedBundleIdentifiers: [String]
    ) -> Bool {
        guard let frontmostApplicationBundleIdentifier else { return true }
        return !excludedBundleIdentifiers.contains(frontmostApplicationBundleIdentifier)
    }
}
