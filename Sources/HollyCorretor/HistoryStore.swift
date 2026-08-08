import Foundation

struct HistoryItem: Codable, Identifiable {
    let id: UUID
    let actionTitle: String
    let originalText: String?
    let processedText: String
    let date: Date
}

@MainActor
final class HistoryStore {
    static let shared = HistoryStore()
    
    private let maxItems = 10
    
    private(set) var items: [HistoryItem] = []
    
    private init() {
        AppPreferences.prepare()
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
        save()
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: AppPreferences.historyKey) else {
            return
        }
        do {
            items = try JSONDecoder().decode([HistoryItem].self, from: data)
        } catch {
            NSLog("HollyCorretor: histórico inválido: %@", error.localizedDescription)
        }
    }
    
    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: AppPreferences.historyKey)
        } catch {
            NSLog("HollyCorretor: não foi possível salvar o histórico: %@", error.localizedDescription)
        }
    }
}
