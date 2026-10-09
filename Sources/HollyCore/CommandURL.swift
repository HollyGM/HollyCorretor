import Foundation

/// Endereços `hollycorretor://<ação>`, que acionam uma ação sobre o texto
/// selecionado a partir de qualquer lugar que abra URLs: um atalho do app
/// Atalhos chamado pela Siri, o Terminal, um lançador de aplicativos.
///
/// Só a ação viaja no endereço. Uma instrução livre não é aceita: qualquer
/// página da web pode abrir um URL, e ela poderia ditar o que fazer com o
/// texto da pessoa.
public enum CommandURL {
    public static let scheme = "hollycorretor"

    /// Aceita `hollycorretor://revisar` e também `hollycorretor:revisar`.
    public static func action(from url: URL) -> CorrectionAction? {
        // URLComponents também existe fora do macOS, onde o HollyCore precisa
        // continuar compilando.
        guard url.scheme?.lowercased() == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let name = components.host.flatMap { $0.isEmpty ? nil : $0 } ?? components.path
        guard !name.isEmpty else { return nil }
        return CorrectionAction(commandName: name.removingPercentEncoding ?? name)
    }

    public static func url(for action: CorrectionAction) -> URL {
        URL(string: "\(scheme)://\(action.commandName)")!
    }
}
