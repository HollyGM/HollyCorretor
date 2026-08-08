import Foundation

enum AppPreferences {
    static let customPromptKey = "customPrompt"
    static let saveHistoryKey = "saveHistory"
    static let historyKey = "HollyCorretorHistory"

    private static let migrationKey = "didMigrateFromZapCorrector"
    private static let legacyBundleIdentifier = "local.zapcorrector.app"
    private static let legacyHistoryKey = "ZapCorrectorHistory"

    static func prepare() {
        UserDefaults.standard.register(defaults: [saveHistoryKey: true])
        migrateLegacyPreferencesIfNeeded()
    }

    static var customPrompt: String? {
        UserDefaults.standard.string(forKey: customPromptKey)
    }

    static var shouldSaveHistory: Bool {
        UserDefaults.standard.bool(forKey: saveHistoryKey)
    }

    private static func migrateLegacyPreferencesIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationKey) else { return }

        let legacyDefaults = UserDefaults(suiteName: legacyBundleIdentifier)

        if defaults.object(forKey: customPromptKey) == nil,
           let customPrompt = legacyDefaults?.string(forKey: customPromptKey) {
            defaults.set(customPrompt, forKey: customPromptKey)
        }

        if defaults.data(forKey: historyKey) == nil {
            let history = defaults.data(forKey: legacyHistoryKey)
                ?? legacyDefaults?.data(forKey: legacyHistoryKey)
            if let history {
                defaults.set(history, forKey: historyKey)
            }
        }

        defaults.set(true, forKey: migrationKey)
    }
}
