import Foundation

extension Notification.Name {
    /// Publicada quando a preferência do botão flutuante muda na janela de
    /// Preferências, para o delegate religar ou parar o vigia.
    static let hollySelectionPillPreferenceChanged =
        Notification.Name("HollySelectionPillPreferenceChanged")
}

enum AppPreferences {
    static let customPromptKey = "customPrompt"
    static let saveHistoryKey = "saveHistory"
    static let privateCloudComputeKey = "usePrivateCloudCompute"
    static let selectionPillKey = "showSelectionPill"

    /// Chave antiga: o histórico ficava em texto claro dentro do plist de
    /// preferências. Continua declarada para a migração poder limpá-la.
    static let legacyHistoryKey = "HollyCorretorHistory"

    private static let migrationKey = "didMigrateFromZapCorrector"
    private static let legacyBundleIdentifier = "local.zapcorrector.app"
    private static let legacyZapHistoryKey = "ZapCorrectorHistory"

    static func prepare() {
        UserDefaults.standard.register(defaults: [
            // Nasce desligado: o app trata material sob sigilo profissional, e
            // guardar isso por padrão inverte a expectativa de quem o usa.
            saveHistoryKey: false,
            privateCloudComputeKey: false,
            // Nasce desligado: a ativação padrão é o submenu HollyCorretor no
            // menu de clique direito. A pastilha continua disponível para quem
            // preferir, mas exige monitorar o mouse no sistema inteiro, o que é
            // bem mais intrusivo do que responder a um item de menu.
            selectionPillKey: false
        ])
        migrateLegacyPreferencesIfNeeded()
    }

    static var customPrompt: String? {
        UserDefaults.standard.string(forKey: customPromptKey)
    }

    static var shouldSaveHistory: Bool {
        UserDefaults.standard.bool(forKey: saveHistoryKey)
    }

    /// Mostra a pastilha do HollyCorretor ao lado de qualquer texto selecionado,
    /// em qualquer aplicativo.
    static var showsSelectionPill: Bool {
        UserDefaults.standard.bool(forKey: selectionPillKey)
    }

    /// Envia textos longos ao Private Cloud Compute da Apple quando eles não
    /// cabem no modelo local. Sai do aparelho, por isso é decisão explícita.
    static var usesPrivateCloudCompute: Bool {
        UserDefaults.standard.bool(forKey: privateCloudComputeKey)
    }

    private static func migrateLegacyPreferencesIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationKey) else { return }

        let legacyDefaults = UserDefaults(suiteName: legacyBundleIdentifier)

        if defaults.object(forKey: customPromptKey) == nil,
           let customPrompt = legacyDefaults?.string(forKey: customPromptKey) {
            defaults.set(customPrompt, forKey: customPromptKey)
        }

        defaults.set(true, forKey: migrationKey)
    }

    /// Histórico deixado por versões anteriores no plist. Apenas lê: apagar é
    /// operação separada, feita só depois que o arquivo protegido foi gravado
    /// com sucesso. Do contrário, um disco cheio ou uma pasta sem permissão de
    /// escrita destruiria a única cópia que existe.
    static func legacyHistoryData() -> Data? {
        let defaults = UserDefaults.standard
        let legacyDefaults = UserDefaults(suiteName: legacyBundleIdentifier)

        return defaults.data(forKey: legacyHistoryKey)
            ?? defaults.data(forKey: legacyZapHistoryKey)
            ?? legacyDefaults?.data(forKey: legacyHistoryKey)
            ?? legacyDefaults?.data(forKey: legacyZapHistoryKey)
    }

    /// Remove o histórico em texto claro do plist. Só deve ser chamado depois de
    /// a transferência ter dado certo.
    static func removeLegacyHistoryData() {
        let defaults = UserDefaults.standard
        let legacyDefaults = UserDefaults(suiteName: legacyBundleIdentifier)

        defaults.removeObject(forKey: legacyHistoryKey)
        defaults.removeObject(forKey: legacyZapHistoryKey)
        legacyDefaults?.removeObject(forKey: legacyHistoryKey)
        legacyDefaults?.removeObject(forKey: legacyZapHistoryKey)
    }
}
