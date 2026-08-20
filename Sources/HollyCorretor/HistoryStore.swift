import Foundation
import OSLog

struct HistoryItem: Codable, Identifiable {
    let id: UUID
    let actionTitle: String
    let originalText: String?
    let processedText: String
    let date: Date
}

/// Guarda os últimos resultados em arquivo próprio, fora do plist de
/// preferências. O conteúdo é material de cliente: o arquivo fica com
/// permissão 0600 e, quando o volume oferece, com proteção de dados completa.
@MainActor
final class HistoryStore {
    static let shared = HistoryStore()

    private let maxItems = 10
    private let logger = Logger(
        subsystem: "com.hollycorretor.app",
        category: "HistoryStore"
    )

    private(set) var items: [HistoryItem] = []

    private lazy var directoryURL: URL? = {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        return base.appendingPathComponent("HollyCorretor", isDirectory: true)
    }()

    private var fileURL: URL? {
        directoryURL?.appendingPathComponent("historico.json", isDirectory: false)
    }

    /// Chamado na abertura do aplicativo. A transferência do histórico do plist
    /// para o arquivo protegido é uma correção de privacidade: precisa
    /// acontecer mesmo que a pessoa nunca abra a janela de histórico, e o
    /// singleton só nasce quando alguém o usa.
    static func prepare() {
        _ = shared
    }

    private init() {
        AppPreferences.prepare()
        migrateFromPreferencesIfNeeded()
        load()
    }

    func add(actionTitle: String, processedText: String) {
        let item = HistoryItem(
            id: UUID(),
            actionTitle: actionTitle,
            originalText: nil,
            processedText: processedText,
            date: Date()
        )

        items.insert(item, at: 0)
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }

        save()
    }

    func clear() {
        items.removeAll()
        guard let fileURL else { return }
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            logger.error("Não foi possível apagar o histórico: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Tira do plist o histórico gravado por versões anteriores e o regrava no
    /// arquivo protegido, para que o material sigiloso não continue em claro.
    private func migrateFromPreferencesIfNeeded() {
        guard let data = AppPreferences.takeLegacyHistoryData() else { return }
        guard let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) else {
            logger.error("Histórico antigo ilegível; descartado do plist.")
            return
        }
        items = Array(decoded.prefix(maxItems))
        save()
        logger.info("Histórico movido do plist para arquivo protegido.")
    }

    private func load() {
        guard let fileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            items = try JSONDecoder().decode([HistoryItem].self, from: data)
        } catch {
            logger.error("Histórico inválido: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        guard let directoryURL, let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            logger.error("Não foi possível salvar o histórico: \(error.localizedDescription, privacy: .public)")
        }
    }
}
